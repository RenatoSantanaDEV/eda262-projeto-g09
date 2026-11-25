#!/usr/bin/env bash
SHARED_ACCOUNT_ID="325583868777"
STACK_BUCKETS=(
  eda262-g09-lake-raw
  eda262-g09-lake-trusted
  eda262-g09-lake-refined
  eda262-g09-artifacts-av2
  eda262-g09-athena-results-av2
)
STACK_ROLES=(
  eda262-g09-av2-ingestion
  eda262-g09-av2-glue-pipeline
  eda262-g09-av2-analyst
)
STACK_DATABASE="eda262_g09_av2"
STACK_JOB="eda262-g09-av2-orders-pipeline"
STACK_WORKGROUP="eda262-g09-av2"
LAYER_BUCKETS=(
  eda262-g09-lake-raw
  eda262-g09-lake-trusted
  eda262-g09-lake-refined
)
export AWS_REGION="us-east-1"
export AWS_DEFAULT_REGION="us-east-1"

bloqueia() {
  printf 'BLOQUEADO: %s\n' "$1" >&2
  exit 2
}

exige_comandos() {
  local command_name
  for command_name in "$@"; do
    command -v "$command_name" >/dev/null 2>&1 || bloqueia "comando ausente: $command_name"
  done
}

valida_alvo() {
  local alvo="${CONTA_DEDICADA_ID:-}"
  [[ "$alvo" =~ ^[0-9]{12}$ ]] ||
    bloqueia "defina CONTA_DEDICADA_ID com os 12 dígitos da conta dedicada confirmada com o avaliador"
  [[ "$alvo" != "$SHARED_ACCOUNT_ID" ]] ||
    bloqueia "a conta compartilhada da disciplina não pode receber este procedimento"
  [[ "${CONFIRMA_CONTA_DEDICADA:-}" == "$alvo" ]] ||
    bloqueia "repita o mesmo ID em CONFIRMA_CONTA_DEDICADA para confirmar a conta alvo"
}

le_identidade() {
  local identidade
  identidade="$(aws sts get-caller-identity --output json 2>/dev/null)" ||
    bloqueia "não foi possível identificar o principal das credenciais atuais"
  CALLER_ACCOUNT="$(jq -r '.Account // empty' <<<"$identidade")"
  CALLER_ARN="$(jq -r '.Arn // empty' <<<"$identidade")"
  [[ "$CALLER_ACCOUNT" != "$SHARED_ACCOUNT_ID" ]] ||
    bloqueia "as credenciais atuais pertencem à conta compartilhada"
  [[ "$CALLER_ACCOUNT" == "$CONTA_DEDICADA_ID" ]] ||
    bloqueia "as credenciais atuais pertencem a uma conta diferente da conta dedicada confirmada"
  [[ "$CALLER_ARN" =~ ^arn:aws:iam::[0-9]{12}:user/[^/]+ ]] ||
    bloqueia "o principal precisa ser um usuário IAM; sessões STS/SSO não são suportadas pela stack"
}
