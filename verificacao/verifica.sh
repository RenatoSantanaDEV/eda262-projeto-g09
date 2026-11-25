#!/usr/bin/env bash
set -uo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PART2_DIR="${PROJECT_DIR}/parte-2"
MODULE_DIR="${PART2_DIR}/modules/data_lake"
FAILURES=0
PASSES=0

passa() {
  printf 'PASSA [%s] %s\n' "$1" "$2"
  PASSES=$((PASSES + 1))
}

falha() {
  printf 'FALHA [%s] %s\n' "$1" "$2" >&2
  FAILURES=$((FAILURES + 1))
}

contains_tf() {
  grep -R -E -q --include='*.tf' -- "$1" "$PART2_DIR"
}

resultado() {
  printf '\nResultado: %d PASSA, %d FALHA\n' "$PASSES" "$FAILURES"
  ((FAILURES == 0))
}

probe_absent() {
  local label="$1"
  local expected="$2"
  shift 2
  local error_file
  error_file="$(mktemp)"
  if "$@" >/dev/null 2>"$error_file"; then
    POST_DESTROY_LEFTOVERS+=("$label")
  elif grep -Eiq -- "$expected" "$error_file"; then
    passa destroy "$label ausente"
  else
    POST_DESTROY_ERRORS+=("$label: $(tr '\n' ' ' <"$error_file" | cut -c1-240)")
  fi
  rm -f -- "$error_file"
}

if [[ "${1:-}" == "--av1" ]]; then
  exec "${PROJECT_DIR}/verificacao/verifica-av1.sh"
fi

if [[ "${1:-}" == "--post-destroy" ]]; then
  command -v aws >/dev/null 2>&1 || {
    falha destroy "AWS CLI ausente"
    resultado
    exit
  }
  export AWS_DEFAULT_REGION=us-east-1 AWS_REGION=us-east-1
  POST_DESTROY_LEFTOVERS=()
  POST_DESTROY_ERRORS=()
  for bucket in \
    eda262-g09-lake-raw \
    eda262-g09-lake-trusted \
    eda262-g09-lake-refined \
    eda262-g09-artifacts-av2 \
    eda262-g09-athena-results-av2; do
    probe_absent "s3:$bucket" '\(404\)|Not Found|NoSuchBucket' \
      aws s3api head-bucket --bucket "$bucket"
  done
  probe_absent "glue:eda262_g09_av2" 'EntityNotFoundException' \
    aws glue get-database --name eda262_g09_av2
  probe_absent "glue-job:eda262-g09-av2-orders-pipeline" 'EntityNotFoundException' \
    aws glue get-job --job-name eda262-g09-av2-orders-pipeline
  probe_absent "athena:eda262-g09-av2" 'not found|does not exist' \
    aws athena get-work-group --work-group eda262-g09-av2
  for role in eda262-g09-av2-ingestion eda262-g09-av2-glue-pipeline eda262-g09-av2-analyst; do
    probe_absent "iam:$role" 'NoSuchEntity' aws iam get-role --role-name "$role"
  done
  if ((${#POST_DESTROY_ERRORS[@]} > 0)); then
    falha destroy "não foi possível confirmar ausência: ${POST_DESTROY_ERRORS[*]}"
  fi
  if ((${#POST_DESTROY_LEFTOVERS[@]} > 0)); then
    falha destroy "recursos órfãos: ${POST_DESTROY_LEFTOVERS[*]}"
  elif ((${#POST_DESTROY_ERRORS[@]} == 0)); then
    passa destroy "nenhum recurso da stack AV2 foi encontrado; backend avaliado separadamente"
  fi
  resultado
  exit
fi

printf 'Verificação AV2 g09 — padrão local, sem acesso AWS\n\n'

[[ -d "$PART2_DIR" ]] && passa estrutura "parte-2 presente" || falha estrutura "parte-2 ausente"
[[ -f "${PROJECT_DIR}/DECISOES.md" ]] && passa decisoes "DECISOES.md canônico da AV2 presente" || falha decisoes "DECISOES.md ausente"
[[ -f "${PROJECT_DIR}/DECISOES-AV1.md" ]] && passa decisoes "histórico AV1 preservado" || falha decisoes "DECISOES-AV1.md ausente"
[[ -f "${PROJECT_DIR}/consultas/av2-valor-bruto.sql" ]] && passa consulta "SQL da pergunta presente" || falha consulta "SQL da pergunta ausente"

if grep -q 'raw[[:space:]]*=[[:space:]]*"\${local.prefix}-lake-raw"' "${MODULE_DIR}/locals.tf" &&
  grep -q 'trusted[[:space:]]*=[[:space:]]*"\${local.prefix}-lake-trusted"' "${MODULE_DIR}/locals.tf" &&
  grep -q 'refined[[:space:]]*=[[:space:]]*"\${local.prefix}-lake-refined"' "${MODULE_DIR}/locals.tf"; then
  passa camadas "buckets raw, trusted e refined seguem o padrão obrigatório"
else
  falha camadas "nomes das três camadas não encontrados"
fi

if [[ "$(grep -c 'classification[[:space:]]*=[[:space:]]*"parquet"' "${MODULE_DIR}/catalog.tf")" -eq 2 ]] &&
  [[ "$(grep -c 'partition_keys' "${MODULE_DIR}/catalog.tf")" -eq 3 ]]; then
  passa formato "trusted/refined em Parquet e tabelas particionadas"
else
  falha formato "Parquet/particionamento incompleto"
fi

if grep -q 'Window.partitionBy("order_id", "order_item_id")' "${PART2_DIR}/glue/pipeline_orders.py" &&
  grep -q '"_row_fingerprint"' "${PART2_DIR}/glue/pipeline_orders.py" &&
  grep -q 'partitionOverwriteMode", "dynamic"' "${PART2_DIR}/glue/pipeline_orders.py" &&
  grep -q 'if rows <= 0 or distinct <= 0 or partitions <= 0 or gross <= 0' "${PART2_DIR}/scripts/test_idempotency.sh"; then
  passa idempotencia "deduplicação determinística, overwrite dinâmico e teste não vazio"
else
  falha idempotencia "mecanismo idempotente ou validação de métricas incompleto"
fi

module_resources="$(cat "${MODULE_DIR}"/*.tf 2>/dev/null | grep -c '^resource "' || true)"
root_resources="$(cat "${PART2_DIR}"/*.tf 2>/dev/null | grep -c '^resource "' || true)"
moved_blocks="$(grep -c '^moved {' "${PART2_DIR}/moved.tf" 2>/dev/null || true)"
moved_targets="$(grep -c '^  to   = module\.data_lake\.' "${PART2_DIR}/moved.tf" 2>/dev/null || true)"
if grep -q 'source = "./modules/data_lake"' "${PART2_DIR}/main.tf" 2>/dev/null &&
  [[ "${module_resources:-0}" -gt 0 && "${root_resources:-1}" -eq 0 ]] &&
  [[ "$moved_blocks" == "$module_resources" && "$moved_targets" == "$module_resources" ]] &&
  grep -q 'from = aws_lakeformation_data_lake_settings.av2' "${PART2_DIR}/removed.tf" 2>/dev/null &&
  ! grep -R -q 'removed {' "$MODULE_DIR"; then
  passa modulo "stack AV2 encapsulada em modules/data_lake com ${moved_blocks} blocos moved e removed global na raiz"
else
  falha modulo "módulo, moved ou removed global inconsistentes"
fi

if grep -q 'mode == "BACKFILL"' "${PART2_DIR}/glue/pipeline_orders.py" &&
  grep -q '2026-09-15' "${PART2_DIR}/scripts/run_backfill.sh"; then
  passa backfill "backfill seletivo de partição implementado"
else
  falha backfill "backfill seletivo ausente"
fi

if grep -q 'valid_statuses' "${PART2_DIR}/glue/pipeline_orders.py" &&
  grep -q 'rejected.write' "${PART2_DIR}/glue/pipeline_orders.py" &&
  grep -q 'regexp_replace' "${PART2_DIR}/glue/pipeline_orders.py"; then
  passa limpeza "normalização, validação e quarentena implementadas"
else
  falha limpeza "limpeza real incompleta"
fi

lf_registrations="$(grep -c 'resource "aws_lakeformation_resource"' "${MODULE_DIR}/lakeformation.tf")"
lf_permissions="$(grep -c 'resource "aws_lakeformation_permissions"' "${MODULE_DIR}/lakeformation.tf")"
if [[ "$lf_registrations" -ge 1 && "$lf_permissions" -ge 6 ]] &&
  grep -q 'analyst_refined_table' "${MODULE_DIR}/lakeformation.tf"; then
  passa lakeformation-declaracao "recursos e grants por camada estão declarados; use --aws para validar a API"
else
  falha lakeformation-declaracao "declarações de permissões por camada incompletas"
fi

if contains_tf 'turma[[:space:]]*=[[:space:]]*"eda262"' &&
  contains_tf 'grupo[[:space:]]*=[[:space:]]*var\.group_id' &&
  contains_tf 'projeto[[:space:]]*=[[:space:]]*"engenharia-de-dados"'; then
  passa tags "tags obrigatórias declaradas"
else
  falha tags "tags obrigatórias incompletas"
fi

if grep -q 'var.aws_region == "us-east-1"' "${PART2_DIR}/variables.tf"; then
  passa regiao "us-east-1 é obrigatório"
else
  falha regiao "região não está bloqueada em us-east-1"
fi

if grep -q 'backend "s3"' "${PART2_DIR}/versions.tf" &&
  grep -q 'dynamodb_table' "${PART2_DIR}/backend.hcl.example"; then
  passa backend "backend remoto S3 + DynamoDB documentado"
else
  falha backend "backend remoto incompleto"
fi

scripts_ok=1
for script in \
  load_raw.sh run_pipeline.sh run_backfill.sh run_query.sh \
  test_idempotency.sh capture_terraform.sh capture_code_hashes.sh \
  verify_access_matrix.sh destroy_and_verify.sh verify_lf_grants.sh lf_grants.py; do
  if [[ ! -f "${PART2_DIR}/scripts/${script}" ]]; then
    falha scripts "script ausente: $script"
    scripts_ok=0
  fi
done
[[ "$scripts_ok" -eq 1 ]] && passa scripts "scripts operacionais presentes"

dedicated_dir="${PART2_DIR}/conta-dedicada"
if [[ -x "${dedicated_dir}/preflight.sh" && -x "${dedicated_dir}/registrar_admin_lf.sh" && -f "${dedicated_dir}/README.md" ]] &&
  grep -q '^SHARED_ACCOUNT_ID="[0-9]\{12\}"$' "${dedicated_dir}/guarda.sh" 2>/dev/null &&
  grep -q -- '--aplicar' "${dedicated_dir}/registrar_admin_lf.sh"; then
  passa conta-dedicada "procedimento opt-in presente, com bloqueio da conta compartilhada e simulação por padrão"
else
  falha conta-dedicada "procedimento opt-in de conta dedicada incompleto"
fi

if find "$PROJECT_DIR" -type f \
  \( -iname '*.pem' -o -iname '*.key' -o -iname 'credentials*' -o -iname 'credenciais*' \) \
  -not -path '*/.git/*' -print -quit | grep -q .; then
  falha seguranca "arquivo com nome sensível encontrado"
else
  passa seguranca "nenhum arquivo com nome típico de credencial"
fi

if grep -R -E -q \
  --exclude='verifica.sh' --exclude='verifica-av1.sh' \
  --exclude-dir='.git' --exclude-dir='.terraform' --exclude-dir='__pycache__' --binary-files=without-match \
  '(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|aws_access_key_id[[:space:]]*=|aws_secret_access_key[[:space:]]*=)' \
  "$PROJECT_DIR"; then
  falha seguranca "padrão de credencial AWS encontrado"
else
  passa seguranca "nenhum padrão de credencial AWS encontrado"
fi

if command -v python3 >/dev/null 2>&1 &&
  PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/eda262-pycache" python3 -m unittest discover -s "${PART2_DIR}/tests" -p 'test_*.py' >/dev/null; then
  passa testes "testes unitários Python"
else
  falha testes "testes unitários Python"
fi

if command -v terraform >/dev/null 2>&1; then
  terraform fmt -check -recursive "$PART2_DIR" >/dev/null &&
    passa terraform-fmt "terraform fmt -check" || falha terraform-fmt "terraform fmt -check"
  if [[ -d "${PART2_DIR}/.terraform" ]]; then
    terraform -chdir="$PART2_DIR" validate >/dev/null &&
      passa terraform-validate "terraform validate" || falha terraform-validate "terraform validate"
  else
    falha terraform-validate "execute terraform init -backend=false antes do validate"
  fi
else
  falha terraform "Terraform não está no PATH"
fi

if [[ "${1:-}" == "--aws" ]]; then
  if ! command -v aws >/dev/null 2>&1; then
    falha aws "AWS CLI ausente"
    resultado
    exit
  fi
  if ! command -v jq >/dev/null 2>&1; then
    falha aws "jq ausente"
    resultado
    exit
  fi
  export AWS_DEFAULT_REGION=us-east-1 AWS_REGION=us-east-1
  bucket_count=0
  for output in raw_bucket trusted_bucket refined_bucket artifacts_bucket athena_results_bucket; do
    bucket="$(terraform -chdir="$PART2_DIR" output -raw "$output" 2>/dev/null || true)"
    [[ -n "$bucket" ]] && aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1 &&
      bucket_count=$((bucket_count + 1))
  done
  [[ "$bucket_count" -eq 5 ]] && passa aws "cinco buckets existem" || falha aws "$bucket_count/5 buckets confirmados"

  database="$(terraform -chdir="$PART2_DIR" output -raw database 2>/dev/null || true)"
  job="$(terraform -chdir="$PART2_DIR" output -raw glue_job 2>/dev/null || true)"
  workgroup="$(terraform -chdir="$PART2_DIR" output -raw athena_workgroup 2>/dev/null || true)"
  raw_table="$(terraform -chdir="$PART2_DIR" output -raw raw_table 2>/dev/null || true)"
  trusted_table="$(terraform -chdir="$PART2_DIR" output -raw trusted_table 2>/dev/null || true)"
  refined_table="$(terraform -chdir="$PART2_DIR" output -raw refined_table 2>/dev/null || true)"
  aws glue get-database --name "$database" >/dev/null 2>&1 && passa aws "database Glue existe" || falha aws "database Glue não foi confirmado"
  table_count=0
  for table in "$raw_table" "$trusted_table" "$refined_table"; do
    aws glue get-table --database-name "$database" --name "$table" >/dev/null 2>&1 &&
      table_count=$((table_count + 1))
  done
  [[ "$table_count" -eq 3 ]] && passa aws "três tabelas Glue existem" || falha aws "$table_count/3 tabelas Glue confirmadas"
  aws glue get-job --job-name "$job" >/dev/null 2>&1 && passa aws "job Glue existe" || falha aws "job Glue não foi confirmado"
  aws athena get-work-group --work-group "$workgroup" >/dev/null 2>&1 && passa aws "workgroup Athena existe" || falha aws "workgroup Athena não foi confirmado"

  account_id="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
  roles_json="$(terraform -chdir="$PART2_DIR" output -json layer_roles 2>/dev/null || true)"
  raw_bucket="$(terraform -chdir="$PART2_DIR" output -raw raw_bucket 2>/dev/null || true)"
  trusted_bucket="$(terraform -chdir="$PART2_DIR" output -raw trusted_bucket 2>/dev/null || true)"
  refined_bucket="$(terraform -chdir="$PART2_DIR" output -raw refined_bucket 2>/dev/null || true)"
  if [[ -n "$account_id" && -n "$raw_bucket" && -n "$trusted_bucket" && -n "$refined_bucket" && -n "$roles_json" ]] &&
    jq -e '.ingestion and .pipeline and .analyst' >/dev/null 2>&1 <<<"$roles_json"; then
    lf_output="$("${PART2_DIR}/scripts/verify_lf_grants.sh" \
      --catalog-id "$account_id" \
      --database "$database" \
      --raw-table "$raw_table" \
      --trusted-table "$trusted_table" \
      --refined-table "$refined_table" \
      --raw-bucket "$raw_bucket" \
      --trusted-bucket "$trusted_bucket" \
      --refined-bucket "$refined_bucket" \
      --ingestion-arn "arn:aws:iam::${account_id}:role/$(jq -r '.ingestion' <<<"$roles_json")" \
      --pipeline-arn "arn:aws:iam::${account_id}:role/$(jq -r '.pipeline' <<<"$roles_json")" \
      --analyst-arn "arn:aws:iam::${account_id}:role/$(jq -r '.analyst' <<<"$roles_json")")"
    lf_status=$?
    lf_passes=0
    lf_failures=0
    while IFS=$'\t' read -r lf_result lf_label lf_message; do
      [[ -n "$lf_result" ]] || continue
      if [[ "$lf_result" == "PASSA" ]]; then
        passa lakeformation-api "${lf_label}: ${lf_message}"
        lf_passes=$((lf_passes + 1))
      else
        falha lakeformation-api "${lf_label}: ${lf_message}"
        lf_failures=$((lf_failures + 1))
      fi
    done <<<"$lf_output"
    if ((lf_status != 0 && lf_failures == 0)) || ((lf_status == 0 && lf_passes != 4)); then
      falha lakeformation-api "comparação exata terminou com código $lf_status e $lf_passes/4 verificações aprovadas"
    fi
  else
    falha lakeformation-api "conta, buckets ou papéis não puderam ser obtidos"
  fi
fi

resultado
