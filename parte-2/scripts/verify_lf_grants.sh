#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  printf 'FALHA\tlakeformation-api\t%s\n' "$1"
  exit 2
}

for command_name in aws jq python3; do
  command -v "$command_name" >/dev/null 2>&1 || fail "comando ausente: $command_name"
done

work_dir="$(mktemp -d)"
cleanup() {
  find "$work_dir" -type f -delete
  rmdir "$work_dir"
}
trap cleanup EXIT

entries="${work_dir}/entries.jsonl"
merged="${work_dir}/merged.json"
error_file="${work_dir}/error.txt"
tokens="${work_dir}/tokens.txt"
: >"$entries"
: >"$tokens"
next_token=""
page=0

while true; do
  page=$((page + 1))
  ((page <= 100)) || fail "paginação excedeu 100 páginas"
  page_file="${work_dir}/page-${page}.json"
  if [[ -n "$next_token" ]]; then
    command=(aws lakeformation list-permissions --next-token "$next_token" --output json)
  else
    command=(aws lakeformation list-permissions --output json)
  fi
  "${command[@]}" >"$page_file" 2>"$error_file" ||
    fail "listagem global de grants falhou na página $page: $(tr '\n' ' ' <"$error_file" | cut -c1-240)"
  jq -e '.PrincipalResourcePermissions | type == "array"' "$page_file" >/dev/null 2>&1 ||
    fail "resposta inválida na página $page"
  jq -c '.PrincipalResourcePermissions[]?' "$page_file" >>"$entries"
  next_token="$(jq -r '.NextToken // empty' "$page_file")"
  [[ -n "$next_token" ]] || break
  if grep -Fxq -- "$next_token" "$tokens"; then
    fail "token de paginação repetido na página $page"
  fi
  printf '%s\n' "$next_token" >>"$tokens"
done

jq -s '{PrincipalResourcePermissions: .}' "$entries" >"$merged" || fail "falha ao consolidar páginas"
python3 "${SCRIPT_DIR}/lf_grants.py" --input "$merged" "$@"
