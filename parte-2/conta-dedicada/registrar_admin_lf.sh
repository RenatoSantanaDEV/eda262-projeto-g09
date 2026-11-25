#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/guarda.sh"

mode="${1:-}"
[[ -z "$mode" || "$mode" == "--aplicar" ]] || bloqueia "uso: $0 [--aplicar]"
exige_comandos aws jq
valida_alvo
le_identidade

work_dir="$(mktemp -d)"
cleanup() {
  find "$work_dir" -type f -delete
  rmdir "$work_dir"
}
trap cleanup EXIT

before="${work_dir}/antes.json"
proposed="${work_dir}/proposta.json"
after="${work_dir}/depois.json"

aws lakeformation get-data-lake-settings --output json 2>/dev/null | jq '.DataLakeSettings' >"$before" ||
  bloqueia "configurações do Lake Formation não puderam ser lidas"
jq -e 'type == "object"' "$before" >/dev/null || bloqueia "resposta inválida do Lake Formation"

if jq -e --arg arn "$CALLER_ARN" 'any(.DataLakeAdmins[]?; .DataLakePrincipalIdentifier == $arn)' "$before" >/dev/null; then
  printf 'PASSA [lakeformation-admin] usuário atual já é administrador; nada a alterar\n'
  exit 0
fi

jq --arg arn "$CALLER_ARN" \
  '.DataLakeAdmins = ((.DataLakeAdmins // []) + [{DataLakePrincipalIdentifier: $arn}])' \
  "$before" >"$proposed"
admins_before="$(jq '(.DataLakeAdmins // []) | length' "$before")"
preserved="$(jq -r 'del(.DataLakeAdmins) | keys | join(", ")' "$before")"
printf 'PLANO [lakeformation-admin] adicionar %s; administradores %s -> %s; campos preservados: %s\n' \
  "$CALLER_ARN" "$admins_before" "$((admins_before + 1))" "${preserved:-nenhum}"

if [[ "$mode" != "--aplicar" ]]; then
  printf 'Simulação concluída. Nenhuma alteração foi feita.\n'
  exit 0
fi

[[ "${CONFIRMA_ALTERACAO_LF:-}" == "adicionar-admin-${CONTA_DEDICADA_ID}" ]] ||
  bloqueia "defina CONFIRMA_ALTERACAO_LF=adicionar-admin-${CONTA_DEDICADA_ID} para aplicar"

aws lakeformation put-data-lake-settings --data-lake-settings "file://${proposed}" >/dev/null ||
  bloqueia "a API recusou a atualização das configurações"
aws lakeformation get-data-lake-settings --output json | jq '.DataLakeSettings' >"$after" ||
  bloqueia "configurações não puderam ser relidas após a atualização"

if ! jq -e --arg arn "$CALLER_ARN" 'any(.DataLakeAdmins[]?; .DataLakePrincipalIdentifier == $arn)' "$after" >/dev/null; then
  printf 'FALHA [lakeformation-admin] usuário atual não aparece entre os administradores após a atualização\n'
  exit 1
fi
if [[ "$(jq -S 'del(.DataLakeAdmins)' "$before")" != "$(jq -S 'del(.DataLakeAdmins)' "$after")" ]] ||
  ! jq -e --slurpfile antes "$before" \
    '[.DataLakeAdmins[]?.DataLakePrincipalIdentifier] as $depois | all($antes[0].DataLakeAdmins[]?; .DataLakePrincipalIdentifier as $p | $depois | index($p))' \
    "$after" >/dev/null; then
  printf 'FALHA [lakeformation-admin] a releitura mostrou alteração além da inclusão do usuário atual\n'
  exit 1
fi
printf 'PASSA [lakeformation-admin] usuário atual incluído; administradores e demais campos anteriores preservados\n'
