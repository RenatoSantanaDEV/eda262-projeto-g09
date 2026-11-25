#!/usr/bin/env bash
set -uo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/guarda.sh"

PASSES=0
ALERTS=0
FAILURES=0
ESTADO=""
SAIDA=""
DENIED_PATTERN='AccessDenied|UnauthorizedOperation|UnrecognizedClient|InvalidClientTokenId|not authorized|\(403\)|Forbidden'

passa() {
  printf 'PASSA [%s] %s\n' "$1" "$2"
  PASSES=$((PASSES + 1))
}

alerta() {
  printf 'ALERTA [%s] %s\n' "$1" "$2"
  ALERTS=$((ALERTS + 1))
}

falha() {
  printf 'FALHA [%s] %s\n' "$1" "$2"
  FAILURES=$((FAILURES + 1))
}

consulta() {
  local absence="$1"
  shift
  local error_file="${WORK_DIR}/erro.txt"
  if SAIDA="$("$@" 2>"$error_file")"; then
    ESTADO="existe"
  elif grep -Eq -- "$absence" "$error_file"; then
    ESTADO="ausente"
  elif grep -Eq -- "$DENIED_PATTERN" "$error_file"; then
    ESTADO="negado"
  else
    ESTADO="erro"
  fi
}

conflito() {
  local label="$1"
  local name="$2"
  local absence="$3"
  shift 3
  consulta "$absence" "$@"
  case "$ESTADO" in
    ausente) passa conflito "$label $name ausente" ;;
    existe) falha conflito "$label $name já existe nesta conta" ;;
    negado) falha conflito "$label $name: acesso negado; ausência não confirmada" ;;
    *) falha conflito "$label $name: verificação inconclusiva" ;;
  esac
}

exige_comandos aws jq
valida_alvo
le_identidade

WORK_DIR="$(mktemp -d)"
cleanup() {
  find "$WORK_DIR" -type f -delete
  rmdir "$WORK_DIR"
}
trap cleanup EXIT

passa conta "credenciais da conta dedicada confirmada com usuário IAM"

BACKEND_BUCKET="${BACKEND_BUCKET:-eda262-g09-tfstate}"
LOCK_TABLE="${LOCK_TABLE:-eda262-g09-terraform-locks}"
[[ "$BACKEND_BUCKET" =~ ^eda262-g09-[a-z0-9-]+$ ]] || bloqueia "BACKEND_BUCKET deve começar com eda262-g09-"
[[ "$LOCK_TABLE" =~ ^eda262-g09-[A-Za-z0-9_.-]+$ ]] || bloqueia "LOCK_TABLE deve começar com eda262-g09-"

for bucket in "${STACK_BUCKETS[@]}"; do
  consulta '\(404\)|Not Found|NoSuchBucket' \
    aws s3api head-bucket --bucket "$bucket" --expected-bucket-owner "$CONTA_DEDICADA_ID"
  case "$ESTADO" in
    ausente) passa nomes-s3 "$bucket disponível" ;;
    existe) falha nomes-s3 "$bucket já existe nesta conta; remova a implantação anterior antes de recriar" ;;
    negado) falha nomes-s3 "$bucket pertence a outra conta ou o acesso foi negado; coordene a liberação, sem trocar o padrão de nomes" ;;
    *) falha nomes-s3 "$bucket com verificação inconclusiva" ;;
  esac
done

consulta '\(404\)|Not Found|NoSuchBucket' \
  aws s3api head-bucket --bucket "$BACKEND_BUCKET" --expected-bucket-owner "$CONTA_DEDICADA_ID"
case "$ESTADO" in
  existe)
    consulta '__sem_ausencia__' \
      aws s3api get-bucket-versioning --bucket "$BACKEND_BUCKET" --expected-bucket-owner "$CONTA_DEDICADA_ID" --output json
    if [[ "$ESTADO" == "existe" ]] && jq -e '.Status == "Enabled"' >/dev/null 2>&1 <<<"$SAIDA"; then
      passa backend "bucket de estado $BACKEND_BUCKET pertence à conta e tem versionamento Enabled"
    elif [[ "$ESTADO" == "existe" ]]; then
      falha backend "bucket de estado $BACKEND_BUCKET sem versionamento Enabled"
    else
      falha backend "versionamento do bucket de estado não pôde ser confirmado"
    fi
    ;;
  ausente) alerta backend "bucket de estado $BACKEND_BUCKET ainda não existe; execute o bootstrap separado" ;;
  negado) falha backend "bucket de estado $BACKEND_BUCKET pertence a outra conta ou o acesso foi negado; escolha outro nome eda262-g09-* em BACKEND_BUCKET e no backend.hcl" ;;
  *) falha backend "bucket de estado com verificação inconclusiva" ;;
esac

consulta 'ResourceNotFoundException' aws dynamodb describe-table --table-name "$LOCK_TABLE" --output json
case "$ESTADO" in
  existe)
    if jq -e '
      .Table.TableStatus == "ACTIVE" and
      .Table.KeySchema == [{"AttributeName": "LockID", "KeyType": "HASH"}] and
      any(.Table.AttributeDefinitions[]?; .AttributeName == "LockID" and .AttributeType == "S")
    ' >/dev/null 2>&1 <<<"$SAIDA"; then
      passa backend "tabela de lock $LOCK_TABLE ACTIVE com chave LockID (S, HASH)"
    else
      falha backend "tabela de lock $LOCK_TABLE não está ACTIVE ou não tem chave LockID (S, HASH)"
    fi
    ;;
  ausente) alerta backend "tabela de lock $LOCK_TABLE ainda não existe; execute o bootstrap separado" ;;
  negado) falha backend "tabela de lock: acesso negado; ausência não confirmada" ;;
  *) falha backend "tabela de lock com verificação inconclusiva" ;;
esac

consulta '__sem_ausencia__' aws lakeformation get-data-lake-settings --output json
if [[ "$ESTADO" == "existe" ]] && jq -e '.DataLakeSettings | type == "object"' >/dev/null 2>&1 <<<"$SAIDA"; then
  if jq -e --arg arn "$CALLER_ARN" 'any(.DataLakeSettings.DataLakeAdmins[]?; .DataLakePrincipalIdentifier == $arn)' >/dev/null <<<"$SAIDA"; then
    passa lakeformation "usuário atual já é administrador do Lake Formation"
  else
    alerta lakeformation "usuário atual não é administrador; use registrar_admin_lf.sh ou um administrador preexistente"
  fi
elif [[ "$ESTADO" == "negado" ]]; then
  falha lakeformation "leitura das configurações do Lake Formation negada"
else
  falha lakeformation "configurações do Lake Formation não puderam ser lidas"
fi

registered="${WORK_DIR}/registros.txt"
tokens="${WORK_DIR}/tokens.txt"
: >"$registered"
: >"$tokens"
listing_ok=1
next_token=""
page=0
while true; do
  page=$((page + 1))
  if ((page > 100)); then
    falha lakeformation "listagem de registros excedeu 100 páginas"
    listing_ok=0
    break
  fi
  if [[ -n "$next_token" ]]; then
    consulta '__sem_ausencia__' aws lakeformation list-resources --next-token "$next_token" --output json
  else
    consulta '__sem_ausencia__' aws lakeformation list-resources --output json
  fi
  if [[ "$ESTADO" != "existe" ]]; then
    falha lakeformation "listagem de registros falhou na página $page ($ESTADO)"
    listing_ok=0
    break
  fi
  if ! jq -e '(.ResourceInfoList // []) | type == "array" and all(.[]; (.ResourceArn | type) == "string")' >/dev/null 2>&1 <<<"$SAIDA"; then
    falha lakeformation "resposta inválida na página $page da listagem de registros"
    listing_ok=0
    break
  fi
  jq -r '(.ResourceInfoList // [])[].ResourceArn' <<<"$SAIDA" >>"$registered"
  next_token="$(jq -r '.NextToken // empty' <<<"$SAIDA")"
  [[ -n "$next_token" ]] || break
  if grep -Fxq -- "$next_token" "$tokens"; then
    falha lakeformation "token repetido na página $page da listagem de registros"
    listing_ok=0
    break
  fi
  printf '%s\n' "$next_token" >>"$tokens"
done
if ((listing_ok == 1)); then
  for bucket in "${LAYER_BUCKETS[@]}"; do
    arn="arn:aws:s3:::${bucket}"
    if grep -Fxq -- "$arn" "$registered" || grep -Fq -- "${arn}/" "$registered"; then
      falha conflito "localização $arn já registrada no Lake Formation"
    else
      passa conflito "localização $arn não registrada no Lake Formation"
    fi
  done
fi

conflito database "$STACK_DATABASE" 'EntityNotFoundException' aws glue get-database --name "$STACK_DATABASE"
conflito job "$STACK_JOB" 'EntityNotFoundException' aws glue get-job --job-name "$STACK_JOB"
conflito workgroup "$STACK_WORKGROUP" 'is not found|does not exist' aws athena get-work-group --work-group "$STACK_WORKGROUP"
for role in "${STACK_ROLES[@]}"; do
  conflito papel "$role" 'NoSuchEntity' aws iam get-role --role-name "$role"
done

printf '\nResultado: %d PASSA, %d ALERTA, %d FALHA. Nenhuma alteração foi feita na conta.\n' \
  "$PASSES" "$ALERTS" "$FAILURES"
((FAILURES == 0)) || exit 1
((ALERTS == 0)) || exit 3
exit 0
