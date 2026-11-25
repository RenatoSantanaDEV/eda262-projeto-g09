#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command python3
require_command terraform

if [[ "${CONFIRM_DESTROY:-}" != "eda262-g09-av2" ]]; then
  printf 'Ação destrutiva bloqueada. Execute com CONFIRM_DESTROY=eda262-g09-av2.\n' >&2
  exit 2
fi

manifest="${PART2_DIR}/.runtime/active-destroy-plan.json"
[[ -f "$manifest" ]] || {
  printf 'Crie e revise o plano com: ./parte-2/scripts/capture_terraform.sh destroy-plan\n' >&2
  exit 2
}

IFS=$'\t' read -r kind plan_rel plan_stamp plan_sha plan_evidence < <(
  python3 - "$manifest" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
required = ("kind", "plan", "plan_created_utc", "plan_sha256", "plan_evidence")
missing = [key for key in required if not payload.get(key)]
if missing:
    raise SystemExit(f"manifesto incompleto: {', '.join(missing)}")
print("\t".join(str(payload[key]) for key in required))
PY
)
[[ "$kind" == "destroy" ]] || {
  printf 'Manifesto ativo não pertence a um destroy.\n' >&2
  exit 2
}
plan="${PART2_DIR}/${plan_rel}"
[[ -f "$plan" ]] || {
  printf 'Plano pareado ausente: %s\n' "$plan" >&2
  exit 2
}
if command -v sha256sum >/dev/null 2>&1; then
  actual_sha="$(sha256sum "$plan" | awk '{print $1}')"
else
  actual_sha="$(shasum -a 256 "$plan" | awk '{print $1}')"
fi
[[ "$actual_sha" == "$plan_sha" ]] || {
  printf 'SHA-256 do plano divergiu do manifesto.\n' >&2
  exit 2
}
destroy_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
destroy_name="terraform-destroy-plan-${plan_stamp}-at-${destroy_stamp}.txt"
destroy_path="${EVIDENCE_DIR}/${destroy_name}"
pairing_path="${EVIDENCE_DIR}/terraform-destroy-pair-${plan_stamp}-at-${destroy_stamp}.json"
[[ ! -e "$destroy_path" && ! -e "$pairing_path" ]] || {
  printf 'Evidência pareada de destroy já existe.\n' >&2
  exit 2
}
terraform -chdir="$PART2_DIR" apply -no-color -input=false "$plan_rel" 2>&1 \
  | sanitize_to "$destroy_path"
python3 - "$pairing_path" "$plan_stamp" "$destroy_stamp" "$plan_sha" "$plan_evidence" "$destroy_name" <<'PY'
import json
import pathlib
import sys

output, plan_stamp, destroy_stamp, sha256, plan_evidence, destroy_evidence = sys.argv[1:]
payload = {
    "kind": "destroy",
    "plan_created_utc": plan_stamp,
    "apply_created_utc": destroy_stamp,
    "plan_sha256": sha256,
    "plan_evidence": plan_evidence,
    "apply_evidence": destroy_evidence,
}
pathlib.Path(output).write_text(
    json.dumps(payload, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
mv "$manifest" "${PART2_DIR}/.runtime/destroyed-${plan_stamp}-at-${destroy_stamp}.json"
"${PROJECT_DIR}/verificacao/verifica.sh" --post-destroy \
  | sanitize_to "${EVIDENCE_DIR}/post-destroy-${destroy_stamp}.txt"
printf 'PASSA: destroy e verificação concluídos. Backend não foi removido.\n'

