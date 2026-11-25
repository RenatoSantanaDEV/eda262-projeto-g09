#!/usr/bin/env bash
set -u
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PART1_DIR="${PROJECT_DIR}/parte-1"
BOOTSTRAP_DIR="${PART1_DIR}/bootstrap"
MODULE_DIR="${PART1_DIR}/modules/data_lake"
SCENARIO_FILE="${PART1_DIR}/scenario.auto.tfvars"
CLEAN_DATA="${PROJECT_DIR}/dados/pedidos.csv"
DIRTY_DATA="${PROJECT_DIR}/dados/exemplos-sujeira.csv"
QUERY_FILE="${PROJECT_DIR}/consultas/pergunta-negocio.sql"
EVIDENCE_DIR="${PROJECT_DIR}/evidencias"
EXECUTION_EVIDENCE="${EVIDENCE_DIR}/execucao-aws.md"
DECISIONS_FILE="${PROJECT_DIR}/DECISOES-AV1.md"

RUN_OPERATIONAL="${RUN_OPERATIONAL_CHECKS:-0}"
RUN_AWS="${RUN_AWS_CHECKS:-0}"
TERRAFORM_BIN="${TERRAFORM_BIN:-terraform}"

EXPECTED_STACK_RESOURCES=14
EXPECTED_WORKSPACE="av1"

PASSES=0
SKIPS=0
FAILURES=0

passa() {
  printf 'PASSA: %s\n' "$1"
  PASSES=$((PASSES + 1))
}

pula() {
  printf 'PULADO: %s\n' "$1"
  SKIPS=$((SKIPS + 1))
}

falha() {
  printf 'FALHA: %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

check_file() {
  if [[ -f "$1" ]]; then
    passa "$2"
  else
    falha "$2 (ausente: $1)"
  fi
}

check_tf_pattern() {
  local pattern="$1"
  local label="$2"

  if grep -R -E -q --include='*.tf' --exclude-dir='.terraform' -- "$pattern" "$PART1_DIR"; then
    passa "$label"
  else
    falha "$label"
  fi
}

MODE_LABEL="entrega/local"
if [[ "$RUN_OPERATIONAL" == "1" ]]; then
  MODE_LABEL="${MODE_LABEL} + operacional"
fi
if [[ "$RUN_AWS" == "1" ]]; then
  MODE_LABEL="${MODE_LABEL} + AWS (leitura)"
fi

printf 'Verificação AV1 g09 — não destrutiva\n'
printf 'Modo: %s\n' "$MODE_LABEL"
printf 'Projeto: %s\n\n' "$PROJECT_DIR"


check_file "${PROJECT_DIR}/README.md" "README presente"
check_file "$DECISIONS_FILE" "DECISOES-AV1.md presente"
check_file "$SCENARIO_FILE" "configuração versionada do cenário presente"
check_file "$CLEAN_DATA" "dataset trusted presente"
check_file "$DIRTY_DATA" "exemplos separados de sujeira presentes"
check_file "$QUERY_FILE" "consulta de negócio presente"
check_file "${PART1_DIR}/backend.hcl.example" "configuração de exemplo do backend presente"

if [[ -d "$MODULE_DIR" ]]; then
  passa "stack organizada no módulo data_lake"
else
  falha "stack organizada no módulo data_lake"
fi

check_tf_pattern 'backend[[:space:]]+"s3"' "backend S3 declarado"
if grep -q -E 'dynamodb_table[[:space:]]*=[[:space:]]*"eda262-g09-terraform-locks"' \
  "${PART1_DIR}/backend.hcl.example"; then
  passa "lock DynamoDB do g09 documentado"
else
  falha "lock DynamoDB do g09 documentado"
fi

check_tf_pattern 'terraform\.workspace' "workspace usado pela configuração"
check_tf_pattern 'aws_s3_bucket' "buckets S3 declarados"
check_tf_pattern 'aws_glue_catalog_database' "Glue Data Catalog declarado"
check_tf_pattern 'aws_glue_catalog_table' "tabela Glue trusted declarada"
check_tf_pattern 'aws_athena_workgroup' "workgroup Athena declarado"
check_tf_pattern 'schema_columns' "schema declarado na infraestrutura"
check_tf_pattern 'turma[[:space:]]*=[[:space:]]*"eda262"' "tag turma declarada"
check_tf_pattern 'projeto[[:space:]]*=[[:space:]]*"engenharia-de-dados"' "tag projeto declarada"
check_tf_pattern 'grupo[[:space:]]*=' "tag grupo declarada"
check_tf_pattern 'eda262-\$\{var\.group_id\}' "prefixo obrigatório parametrizado"

if grep -R -E -q --include='*.tf' --exclude-dir='.terraform' 'aws_glue_crawler' "$PART1_DIR"; then
  falha "Crawler ausente (foi encontrada uma declaração de Crawler)"
else
  passa "Crawler ausente"
fi

if grep -q -E 'default[[:space:]]*=[[:space:]]*"us-east-1"' "${PART1_DIR}/variables.tf" &&
  grep -q -E 'var\.aws_region[[:space:]]*==[[:space:]]*"us-east-1"' "${PART1_DIR}/variables.tf" &&
  grep -q -E 'region[[:space:]]*=[[:space:]]*"us-east-1"' "${PART1_DIR}/backend.hcl.example"; then
  passa "região obrigatória us-east-1 fixada e validada"
else
  falha "região obrigatória us-east-1 fixada e validada"
fi

if grep -q -E 'group_id[[:space:]]*=[[:space:]]*"g09"' "$SCENARIO_FILE" &&
  grep -q -E 'scenario[[:space:]]*=[[:space:]]*"pedidos-ecommerce"' "$SCENARIO_FILE" &&
  ! grep -q -E 'TODO|gNN' "$SCENARIO_FILE"; then
  passa "cenário g09 preenchido sem placeholders"
else
  falha "cenário g09 preenchido sem placeholders"
fi

FORCE_DESTROY_COUNT="$(grep -c -E '^[[:space:]]*force_destroy[[:space:]]*=[[:space:]]*true' \
  "${MODULE_DIR}/main.tf" 2>/dev/null || true)"
if [[ "$FORCE_DESTROY_COUNT" == "3" ]]; then
  passa "force_destroy nos dois buckets e no workgroup da stack"
else
  falha "force_destroy nos dois buckets e no workgroup da stack (encontrados: ${FORCE_DESTROY_COUNT:-0})"
fi

if grep -R -E -q --include='*.tf' --exclude-dir='.terraform' 'abspath\(' "$PART1_DIR"; then
  falha "caminho dos arquivos de dados independente da máquina (abspath encontrado)"
else
  passa "caminho dos arquivos de dados independente da máquina"
fi

RESOURCE_BLOCKS="$(cat "${PART1_DIR}"/*.tf "${MODULE_DIR}"/*.tf 2>/dev/null |
  grep -c -E '^resource[[:space:]]+"' || true)"
SOURCE_OBJECTS="$(grep -c -E '^[[:space:]]*key[[:space:]]*=' "$SCENARIO_FILE" 2>/dev/null || true)"
if [[ "$RESOURCE_BLOCKS" == "$EXPECTED_STACK_RESOURCES" && "$SOURCE_OBJECTS" == "1" ]]; then
  passa "stack declara ${EXPECTED_STACK_RESOURCES} recursos, como no apply evidenciado"
else
  falha "stack declara ${EXPECTED_STACK_RESOURCES} recursos, como no apply evidenciado (blocos: ${RESOURCE_BLOCKS:-0}; objetos enviados: ${SOURCE_OBJECTS:-0})"
fi


EXPECTED_HEADER='order_id,customer_id,order_timestamp,status,quantity,unit_price,city,state'
if [[ -f "$CLEAN_DATA" ]] && [[ "$(head -n 1 "$CLEAN_DATA")" == "$EXPECTED_HEADER" ]]; then
  passa "cabeçalho do dataset corresponde ao schema"
else
  falha "cabeçalho do dataset corresponde ao schema"
fi

if [[ -f "$CLEAN_DATA" ]] && awk -F, '
  NR == 1 { next }
  {
    rows++
    if (NF != 8) bad++
    for (i = 1; i <= 8; i++) if ($i == "") bad++
    if (seen[$1]++) duplicates++
    if ($3 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/) bad++
    if ($4 !~ /^(pending|paid|shipped|delivered|cancelled)$/) bad++
    if (($5 + 0) <= 0 || ($6 + 0) <= 0) bad++
  }
  END { exit !(rows == 12 && duplicates == 0 && bad == 0) }
' "$CLEAN_DATA"; then
  passa "dataset trusted tem 12 linhas válidas, sem nulos ou duplicatas"
else
  falha "dataset trusted tem 12 linhas válidas, sem nulos ou duplicatas"
fi

if ! grep -q 'exemplos-sujeira.csv' "$SCENARIO_FILE"; then
  passa "arquivo de sujeira não é carregado na camada trusted"
else
  falha "arquivo de sujeira não é carregado na camada trusted"
fi

if grep -q -E 'SUM\(' "$QUERY_FILE" &&
  grep -q -E 'quantity.*unit_price' "$QUERY_FILE" &&
  grep -q -E 'GROUP BY' "$QUERY_FILE" &&
  grep -q -E 'order_timestamp' "$QUERY_FILE" &&
  grep -q -E 'status' "$QUERY_FILE" &&
  ! grep -q -E 'TODO|WHERE[[:space:]]+1[[:space:]]*=[[:space:]]*0' "$QUERY_FILE"; then
  passa "consulta responde valor bruto por dia e status"
else
  falha "consulta responde valor bruto por dia e status"
fi


if find "$EVIDENCE_DIR" -maxdepth 1 -type f ! -name README.md 2>/dev/null | grep -q .; then
  passa "evidências reais adicionadas"
else
  falha "evidências reais adicionadas"
fi

DATA_BYTES=""
if [[ -f "$CLEAN_DATA" ]]; then
  DATA_BYTES="$(wc -c <"$CLEAN_DATA" | tr -d '[:space:]')"
fi
EVIDENCE_BYTES="$(grep -o -E 'Dados processados: [0-9]+ bytes' "$EXECUTION_EVIDENCE" 2>/dev/null |
  grep -o -E '[0-9]+' | head -n 1 || true)"
if [[ -n "$DATA_BYTES" && "$DATA_BYTES" == "$EVIDENCE_BYTES" ]]; then
  passa "tamanho do dataset (${DATA_BYTES} bytes) igual aos bytes processados na evidência"
else
  falha "tamanho do dataset (${DATA_BYTES:-?} bytes) igual aos bytes processados na evidência (${EVIDENCE_BYTES:-?})"
fi

if grep -q -E "\`${EXPECTED_STACK_RESOURCES} added, 0 changed, 0 destroyed\`" "$EXECUTION_EVIDENCE" 2>/dev/null; then
  passa "evidência registra apply de ${EXPECTED_STACK_RESOURCES} recursos"
else
  falha "evidência registra apply de ${EXPECTED_STACK_RESOURCES} recursos"
fi

UUID_PATTERN='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
QUERY_ID_EVIDENCE="$(grep -E 'Query execution ID' "$EXECUTION_EVIDENCE" 2>/dev/null |
  grep -o -E "$UUID_PATTERN" | sort -u || true)"
QUERY_ID_DECISIONS="$(grep -E 'Query execution ID' "$DECISIONS_FILE" 2>/dev/null |
  grep -o -E "$UUID_PATTERN" | sort -u || true)"
if [[ -n "$QUERY_ID_EVIDENCE" && "$QUERY_ID_EVIDENCE" == "$QUERY_ID_DECISIONS" ]]; then
  passa "Query execution ID idêntico em DECISOES-AV1.md e na evidência"
else
  falha "Query execution ID idêntico em DECISOES-AV1.md e na evidência"
fi


SENSITIVE_NAME="$(find "$PROJECT_DIR" -type f \
  \( -iname '*.pem' -o -iname '*.key' -o -iname 'credentials*' \
  -o -iname 'credenciais*' -o -iname '*acesso-programatico*' \
  -o -iname '*acesso_programatico*' \) -print -quit)"
if [[ -z "$SENSITIVE_NAME" ]]; then
  passa "nenhum arquivo com nome típico de credencial"
else
  falha "arquivo sensível encontrado: $SENSITIVE_NAME"
fi

SECRET_PATTERN='(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}'
SECRET_PATTERN="${SECRET_PATTERN}|aws_access_key_id[[:space:]]*="
SECRET_PATTERN="${SECRET_PATTERN}|aws_secret_access_key[[:space:]]*="
SECRET_PATTERN="${SECRET_PATTERN}|aws_session_token[[:space:]]*="
SECRET_PATTERN="${SECRET_PATTERN}|(access_key|secret_key|session_token)[[:space:]]*=[[:space:]]*\"[^\"]"
SECRET_PATTERN="${SECRET_PATTERN}|BEGIN [A-Z ]*PRIVATE KEY)"
if grep -R -E -q \
  --exclude='verifica.sh' --exclude-dir='.terraform' \
  -e "$SECRET_PATTERN" "$PROJECT_DIR"; then
  falha "nenhum padrão de credencial AWS ou chave privada no projeto"
else
  passa "nenhum padrão de credencial AWS ou chave privada no projeto"
fi

ACCOUNT_PATTERN='(^|[^0-9A-Za-z-])[0-9]{12}([^0-9A-Za-z]|$)'
if grep -R -I -E -q -e "$ACCOUNT_PATTERN" "$EVIDENCE_DIR" 2>/dev/null; then
  falha "evidências sem ID de conta AWS completo"
else
  passa "evidências sem ID de conta AWS completo"
fi

OPERATIONAL_PATTERN='(^|/)\.terraform/|\.tfstate($|\.)|\.tfplan$|(^|/)backend\.hcl$|(^|/)terraform\.tfvars$|(^|/)\.env($|\.)|(^|/)\.aws/'
if [[ -e "${PROJECT_DIR}/.git" ]] && command -v git >/dev/null 2>&1; then
  TRACKED_OPERATIONAL="$(git -C "$PROJECT_DIR" ls-files 2>/dev/null |
    grep -E "$OPERATIONAL_PATTERN" || true)"
  UNIGNORED_OPERATIONAL="$(git -C "$PROJECT_DIR" ls-files --others --exclude-standard 2>/dev/null |
    grep -E "$OPERATIONAL_PATTERN" || true)"
  if [[ -z "$TRACKED_OPERATIONAL" ]]; then
    passa "nenhum arquivo operacional versionado no Git"
  else
    falha "arquivo operacional versionado no Git: $(printf '%s' "$TRACKED_OPERATIONAL" | tr '\n' ' ')"
  fi
  if [[ -z "$UNIGNORED_OPERATIONAL" ]]; then
    passa "arquivos operacionais locais cobertos pelo .gitignore"
  else
    falha "arquivo operacional local fora do .gitignore: $(printf '%s' "$UNIGNORED_OPERATIONAL" | tr '\n' ' ')"
  fi
else
  LOCAL_OPERATIONAL="$(cd "$PROJECT_DIR" && find . \
    \( -type d \( -name '.terraform' -o -name '.aws' \) -prune -print \) -o \
    \( -type f \( -name '*.tfstate' -o -name '*.tfstate.*' -o -name '*.tfplan' \
    -o -name 'backend.hcl' -o -name 'terraform.tfvars' \
    -o -name '.env' -o -name '.env.*' \) -print \) 2>/dev/null |
    sed -e 's|^\./||' | sort)"
  if [[ -z "$LOCAL_OPERATIONAL" ]]; then
    passa "pacote sem estado, planos, cache de init, backend.hcl ou tfvars locais"
  elif [[ "$RUN_OPERATIONAL" == "1" ]]; then
    pula "limpeza de pacote (diretório de trabalho inicializado, fora do Git)"
  else
    falha "arquivos operacionais fora do Git: $(printf '%s' "$LOCAL_OPERATIONAL" | tr '\n' ' ') (remova-os de um pacote de entrega; em diretório de trabalho inicializado, use RUN_OPERATIONAL_CHECKS=1)"
  fi
fi


terraform_validate() {
  local dir="$1"
  local label="$2"

  if [[ -d "${dir}/.terraform" ]]; then
    if "$TERRAFORM_BIN" -chdir="$dir" validate >/dev/null; then
      passa "$label"
    else
      falha "$label"
    fi
  elif [[ "$RUN_OPERATIONAL" == "1" ]]; then
    falha "$label (execute terraform init primeiro)"
  else
    pula "$label (sem cache de init neste diretório)"
  fi
}

if command -v "$TERRAFORM_BIN" >/dev/null 2>&1; then
  printf 'Binário Terraform: %s\n' "$("$TERRAFORM_BIN" version 2>/dev/null | head -n 1)"

  if "$TERRAFORM_BIN" fmt -check -recursive "$PART1_DIR" >/dev/null; then
    passa "formatação Terraform"
  else
    falha "formatação Terraform"
  fi

  terraform_validate "$PART1_DIR" "terraform validate da stack principal"
  terraform_validate "$BOOTSTRAP_DIR" "terraform validate do bootstrap"
elif [[ "$RUN_OPERATIONAL" == "1" ]]; then
  falha "Terraform disponível para fmt/validate"
else
  pula "formatação e validate do Terraform (binário ${TERRAFORM_BIN} não encontrado)"
fi


if [[ "$RUN_OPERATIONAL" == "1" ]]; then
  if [[ -f "${PART1_DIR}/backend.hcl" ]] &&
    ! grep -q -E 'TODO|gNN' "${PART1_DIR}/backend.hcl"; then
    passa "backend.hcl operacional preenchido"
  else
    falha "backend.hcl operacional preenchido (copie o exemplo após criar o backend)"
  fi

  if [[ -f "${PART1_DIR}/backend.hcl" ]] &&
    grep -q -E '^[[:space:]]*bucket[[:space:]]*=[[:space:]]*"eda262-g09-' "${PART1_DIR}/backend.hcl" &&
    grep -q -E '^[[:space:]]*dynamodb_table[[:space:]]*=[[:space:]]*"eda262-g09-' "${PART1_DIR}/backend.hcl" &&
    grep -q -E '^[[:space:]]*region[[:space:]]*=[[:space:]]*"us-east-1"' "${PART1_DIR}/backend.hcl"; then
    passa "backend.hcl aponta para S3 e DynamoDB do g09 em us-east-1"
  else
    falha "backend.hcl aponta para S3 e DynamoDB do g09 em us-east-1"
  fi

  CURRENT_WORKSPACE="default"
  if [[ -f "${PART1_DIR}/.terraform/environment" ]]; then
    CURRENT_WORKSPACE="$(tr -d '[:space:]' <"${PART1_DIR}/.terraform/environment")"
  fi
  if [[ "$CURRENT_WORKSPACE" == "$EXPECTED_WORKSPACE" ]]; then
    passa "workspace ${EXPECTED_WORKSPACE} selecionado"
  else
    falha "workspace ${EXPECTED_WORKSPACE} selecionado (atual: ${CURRENT_WORKSPACE})"
  fi
else
  pula "backend.hcl operacional e workspace ${EXPECTED_WORKSPACE} (use RUN_OPERATIONAL_CHECKS=1 após o init)"
fi


if [[ "$RUN_AWS" == "1" ]]; then
  if ! command -v aws >/dev/null 2>&1; then
    falha "AWS CLI disponível para verificações remotas"
  elif ! command -v "$TERRAFORM_BIN" >/dev/null 2>&1; then
    falha "Terraform disponível para ler outputs do deploy"
  elif ! command -v jq >/dev/null 2>&1; then
    falha "jq disponível para ler outputs do deploy"
  elif ! aws sts get-caller-identity >/dev/null 2>&1; then
    falha "identidade AWS válida para verificações de leitura"
  else
    passa "identidade AWS válida para verificações de leitura"

    OUTPUTS="$("$TERRAFORM_BIN" -chdir="$PART1_DIR" output -json 2>/dev/null || true)"
    REGION="$(jq -r '.aws_region.value // empty' <<<"$OUTPUTS")"
    LAKE_BUCKET="$(jq -r '.lake_bucket_name.value // empty' <<<"$OUTPUTS")"
    RESULTS_BUCKET="$(jq -r '.athena_results_bucket_name.value // empty' <<<"$OUTPUTS")"
    DATABASE="$(jq -r '.glue_database_name.value // empty' <<<"$OUTPUTS")"
    TABLE="$(jq -r '.glue_table_name.value // empty' <<<"$OUTPUTS")"
    WORKGROUP="$(jq -r '.athena_workgroup_name.value // empty' <<<"$OUTPUTS")"

    if [[ "$REGION" == "us-east-1" ]]; then
      passa "deploy está em us-east-1"
    else
      falha "deploy está em us-east-1"
    fi

    if [[ -n "$LAKE_BUCKET" ]] &&
      aws s3api head-bucket --bucket "$LAKE_BUCKET" --region us-east-1 >/dev/null 2>&1; then
      passa "bucket do Data Lake existe"
    else
      falha "bucket do Data Lake existe"
    fi

    if [[ -n "$RESULTS_BUCKET" ]] &&
      aws s3api head-bucket --bucket "$RESULTS_BUCKET" --region us-east-1 >/dev/null 2>&1; then
      passa "bucket de resultados do Athena existe"
    else
      falha "bucket de resultados do Athena existe"
    fi

    if [[ -n "$DATABASE" ]] &&
      aws glue get-database --name "$DATABASE" --region us-east-1 >/dev/null 2>&1; then
      passa "banco Glue existe"
    else
      falha "banco Glue existe"
    fi

    if [[ -n "$DATABASE" && -n "$TABLE" ]] &&
      aws glue get-table --database-name "$DATABASE" --name "$TABLE" --region us-east-1 >/dev/null 2>&1; then
      passa "tabela trusted existe no Glue"
    else
      falha "tabela trusted existe no Glue"
    fi

    if [[ -n "$WORKGROUP" ]] &&
      aws athena get-work-group --work-group "$WORKGROUP" --region us-east-1 >/dev/null 2>&1; then
      passa "workgroup Athena existe"
    else
      falha "workgroup Athena existe"
    fi
  fi
else
  pula "verificações AWS de leitura (use RUN_AWS_CHECKS=1 com a stack implantada)"
fi

printf '\nResumo: %d aprovadas, %d puladas, %d falhas\n' "$PASSES" "$SKIPS" "$FAILURES"
if ((FAILURES > 0)); then
  exit 1
fi

exit 0

