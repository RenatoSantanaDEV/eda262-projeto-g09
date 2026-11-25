#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command python3
require_command terraform

action="${1:-}"
runtime_dir="${PART2_DIR}/.runtime"
mkdir -p "$runtime_dir" "$EVIDENCE_DIR"

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

write_manifest() {
  local manifest="$1"
  local kind="$2"
  local plan_rel="$3"
  local stamp="$4"
  local plan_sha="$5"
  local evidence_name="$6"
  python3 - "$manifest" "$kind" "$plan_rel" "$stamp" "$plan_sha" "$evidence_name" <<'PY'
import json
import pathlib
import sys

manifest, kind, plan, stamp, sha256, evidence = sys.argv[1:]
payload = {
    "kind": kind,
    "plan": plan,
    "plan_created_utc": stamp,
    "plan_sha256": sha256,
    "plan_evidence": evidence,
}
pathlib.Path(manifest).write_text(
    json.dumps(payload, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
}

read_manifest() {
  python3 - "$1" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
required = ("kind", "plan", "plan_created_utc", "plan_sha256", "plan_evidence")
missing = [key for key in required if not payload.get(key)]
if missing:
    raise SystemExit(f"manifesto incompleto: {', '.join(missing)}")
print("\t".join(str(payload[key]) for key in required))
PY
}

write_pairing() {
  local output="$1"
  local kind="$2"
  local plan_stamp="$3"
  local apply_stamp="$4"
  local plan_sha="$5"
  local plan_evidence="$6"
  local apply_evidence="$7"
  python3 - "$output" "$kind" "$plan_stamp" "$apply_stamp" "$plan_sha" "$plan_evidence" "$apply_evidence" <<'PY'
import json
import pathlib
import sys

output, kind, plan_stamp, apply_stamp, sha256, plan_evidence, apply_evidence = sys.argv[1:]
payload = {
    "kind": kind,
    "plan_created_utc": plan_stamp,
    "apply_created_utc": apply_stamp,
    "plan_sha256": sha256,
    "plan_evidence": plan_evidence,
    "apply_evidence": apply_evidence,
}
pathlib.Path(output).write_text(
    json.dumps(payload, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
}

case "$action" in
  plan)
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    plan_rel=".runtime/av2-${stamp}.tfplan"
    plan_path="${PART2_DIR}/${plan_rel}"
    evidence_name="terraform-plan-${stamp}.txt"
    evidence_path="${EVIDENCE_DIR}/${evidence_name}"
    manifest="${runtime_dir}/active-plan.json"
    [[ ! -e "$plan_path" && ! -e "$evidence_path" ]] || {
      printf 'Artefato do timestamp %s já existe. Tente novamente.\n' "$stamp" >&2
      exit 2
    }
    terraform -chdir="$PART2_DIR" plan \
      -no-color \
      -out="$plan_rel" \
      -input=false 2>&1 \
      | sanitize_to "$evidence_path"
    plan_sha="$(hash_file "$plan_path")"
    write_manifest "$manifest" apply "$plan_rel" "$stamp" "$plan_sha" "$evidence_name"
    printf '%s\n' "$evidence_path"
    ;;
  apply)
    manifest="${runtime_dir}/active-plan.json"
    [[ -f "$manifest" ]] || {
      printf 'Execute %s plan primeiro.\n' "$0" >&2
      exit 2
    }
    IFS=$'\t' read -r kind plan_rel plan_stamp plan_sha plan_evidence < <(read_manifest "$manifest")
    [[ "$kind" == "apply" ]] || {
      printf 'Manifesto ativo não pertence a um apply.\n' >&2
      exit 2
    }
    plan_path="${PART2_DIR}/${plan_rel}"
    [[ -f "$plan_path" ]] || {
      printf 'Plano pareado ausente: %s\n' "$plan_path" >&2
      exit 2
    }
    actual_sha="$(hash_file "$plan_path")"
    [[ "$actual_sha" == "$plan_sha" ]] || {
      printf 'SHA-256 do plano divergiu do manifesto.\n' >&2
      exit 2
    }
    apply_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    apply_name="terraform-apply-plan-${plan_stamp}-at-${apply_stamp}.txt"
    apply_path="${EVIDENCE_DIR}/${apply_name}"
    pairing_name="terraform-plan-apply-${plan_stamp}-at-${apply_stamp}.json"
    pairing_path="${EVIDENCE_DIR}/${pairing_name}"
    [[ ! -e "$apply_path" && ! -e "$pairing_path" ]] || {
      printf 'Evidência pareada já existe.\n' >&2
      exit 2
    }
    terraform -chdir="$PART2_DIR" apply \
      -no-color \
      -input=false "$plan_rel" 2>&1 \
      | sanitize_to "$apply_path"
    write_pairing "$pairing_path" apply "$plan_stamp" "$apply_stamp" "$plan_sha" "$plan_evidence" "$apply_name"
    mv "$manifest" "${runtime_dir}/applied-${plan_stamp}-at-${apply_stamp}.json"
    printf '%s\n%s\n' "$apply_path" "$pairing_path"
    ;;
  destroy-plan)
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    plan_rel=".runtime/av2-destroy-${stamp}.tfplan"
    plan_path="${PART2_DIR}/${plan_rel}"
    evidence_name="terraform-destroy-plan-${stamp}.txt"
    evidence_path="${EVIDENCE_DIR}/${evidence_name}"
    manifest="${runtime_dir}/active-destroy-plan.json"
    [[ ! -e "$plan_path" && ! -e "$evidence_path" ]] || {
      printf 'Artefato do timestamp %s já existe. Tente novamente.\n' "$stamp" >&2
      exit 2
    }
    terraform -chdir="$PART2_DIR" plan \
      -no-color \
      -destroy \
      -out="$plan_rel" \
      -input=false 2>&1 \
      | sanitize_to "$evidence_path"
    plan_sha="$(hash_file "$plan_path")"
    write_manifest "$manifest" destroy "$plan_rel" "$stamp" "$plan_sha" "$evidence_name"
    printf '%s\n' "$evidence_path"
    ;;
  *)
    printf 'Uso: %s {plan|apply|destroy-plan}\n' "$0" >&2
    exit 2
    ;;
esac
