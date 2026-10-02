#!/usr/bin/env bash
set -u
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PART1_DIR="${PROJECT_DIR}/parte-1"
SCENARIO_FILE="${PART1_DIR}/scenario.auto.tfvars"
CLEAN_DATA="${PROJECT_DIR}/dados/pedidos.csv"
DIRTY_DATA="${PROJECT_DIR}/dados/exemplos-sujeira.csv"
QUERY_FILE="${PROJECT_DIR}/consultas/pergunta-negocio.sql"
FAILURES=0

passa() {
  printf 'PASSA: %s\n' "$1"
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

  if grep -R -E -q --include='*.tf' -- "$pattern" "$PART1_DIR"; then
    passa "$label"
  else
    falha "$label"
  fi
}

printf 'Verificação AV1 g09 — modo local e não destrutivo\n'
printf 'Projeto: %s\n\n' "$PROJECT_DIR"

check_file "${PROJECT_DIR}/README.md" "README presente"
check_file "${PROJECT_DIR}/DECISOES.md" "DECISOES.md presente"
check_file "$SCENARIO_FILE" "configuração versionada do cenário presente"
check_file "$CLEAN_DATA" "dataset trusted presente"
check_file "$DIRTY_DATA" "exemplos separados de sujeira presentes"
check_file "$QUERY_FILE" "consulta de negócio presente"
check_file "${PART1_DIR}/backend.hcl.example" "configuração de exemplo do backend presente"

if [[ -d "${PART1_DIR}/modules/data_lake" ]]; then
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

if grep -R -E -q --include='*.tf' 'aws_glue_crawler' "$PART1_DIR"; then
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

SENSITIVE_NAME="$(find "$PROJECT_DIR" -type f \
  \( -iname '*.pem' -o -iname '*.key' -o -iname 'credentials*' \
  -o -iname 'credenciais*' -o -iname '*acesso-programatico*' \
  -o -iname '*acesso_programatico*' \) -print -quit)"
if [[ -z "$SENSITIVE_NAME" ]]; then
  passa "nenhum arquivo com nome típico de credencial"
else
  falha "arquivo sensível encontrado: $SENSITIVE_NAME"
fi

if grep -R -E -q \
  --exclude='verifica.sh' --exclude-dir='.terraform' \
  '(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|aws_access_key_id[[:space:]]*=|aws_secret_access_key[[:space:]]*=)' \
  "$PROJECT_DIR"; then
  falha "nenhum padrão de credencial AWS versionado"
else
  passa "nenhum padrão de credencial AWS versionado"
fi

if command -v terraform >/dev/null 2>&1; then
  if terraform fmt -check -recursive "$PART1_DIR" >/dev/null; then
    passa "formatação Terraform"
  else
    falha "formatação Terraform"
  fi

  if [[ -d "${PART1_DIR}/.terraform" ]]; then
    if terraform -chdir="$PART1_DIR" validate >/dev/null; then
      passa "terraform validate da stack principal"
    else
      falha "terraform validate da stack principal"
    fi
  else
    falha "terraform validate da stack principal (execute terraform init -backend=false primeiro)"
  fi
else
  falha "Terraform disponível para fmt/validate"
fi

if [[ -f "${PART1_DIR}/backend.hcl" ]] &&
  ! grep -q -E 'TODO|gNN' "${PART1_DIR}/backend.hcl"; then
  passa "backend.hcl operacional preenchido"
else
  falha "backend.hcl operacional preenchido (copie o exemplo após criar o backend)"
fi

if find "${PROJECT_DIR}/evidencias" -maxdepth 1 -type f ! -name README.md | grep -q .; then
  passa "evidências reais adicionadas"
else
  falha "evidências reais adicionadas"
fi

if [[ "${RUN_AWS_CHECKS:-0}" == "1" ]]; then
  if ! command -v aws >/dev/null 2>&1; then
    falha "AWS CLI disponível para verificações remotas"
  elif ! command -v terraform >/dev/null 2>&1; then
    falha "Terraform disponível para ler outputs do deploy"
  elif ! command -v jq >/dev/null 2>&1; then
    falha "jq disponível para ler outputs do deploy"
  elif ! aws sts get-caller-identity >/dev/null 2>&1; then
    falha "identidade AWS válida para verificações de leitura"
  else
    passa "identidade AWS válida para verificações de leitura"

    OUTPUTS="$(terraform -chdir="$PART1_DIR" output -json 2>/dev/null || true)"
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
  falha "verificações AWS de leitura executadas (use RUN_AWS_CHECKS=1 após o deploy)"
fi

printf '\nTotal de falhas: %d\n' "$FAILURES"
if ((FAILURES > 0)); then
  exit 1
fi

exit 0
