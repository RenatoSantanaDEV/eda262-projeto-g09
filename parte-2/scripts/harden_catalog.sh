#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command aws
require_command python3
mode="${1:---plan}"
[[ "$mode" == "--plan" || "$mode" == "--apply" ]] || exit 2
database="$(tf_output database)"
account="$(tf_output account_id)"
[[ "$database" == "eda262_g09_av2" ]] || { printf 'Banco fora do escopo g09.\n' >&2; exit 2; }
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
aws lakeformation list-permissions --output json >"$tmp/grants.json"
python3 - "$tmp" "$database" "$account" <<'PYREQ'
import json
import sys
from pathlib import Path

root, database, account = sys.argv[1:]
root = Path(root)
entries = json.loads((root / "grants.json").read_text())["PrincipalResourcePermissions"]
for index, entry in enumerate(entries):
    principal = entry.get("Principal", {}).get("DataLakePrincipalIdentifier")
    if principal not in {"IAM_ALLOWED_PRINCIPALS", "IAMAllowedPrincipals"}:
        continue
    resource = entry.get("Resource", {})
    in_scope = False
    for kind, body in resource.items():
        if body.get("CatalogId") != account:
            continue
        in_scope |= kind == "Database" and body.get("Name") == database
        in_scope |= kind in {"Table", "TableWithColumns"} and body.get("DatabaseName") == database
    if in_scope and entry.get("Permissions"):
        request = {key: entry[key] for key in ("Principal", "Resource", "Permissions", "PermissionsWithGrantOption") if key in entry}
        (root / f"request-{index}.json").write_text(json.dumps(request))
        print(f"Remover compatibilidade {principal} em {next(iter(resource))} do banco {database}")
PYREQ
for request in "$tmp"/request-*.json; do
  [[ -f "$request" ]] || continue
  if [[ "$mode" == "--apply" ]]; then
    aws lakeformation revoke-permissions --cli-input-json "file://${request}"
  fi
done
printf 'Tratamento de compatibilidade concluído (%s), somente banco %s.\n' "$mode" "$database"
