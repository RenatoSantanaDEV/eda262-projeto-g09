#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PART2_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROJECT_DIR="$(cd -- "${PART2_DIR}/.." && pwd)"
SANITIZER="${SCRIPT_DIR}/sanitize.py"
REGION="us-east-1"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_FILE="${EVIDENCE_FILE:-${PROJECT_DIR}/evidencias/av2/brutas/ingestion-access-real-${STAMP}.json}"
TEMP_DIR="$(mktemp -d)"
CHECKS_FILE="${TEMP_DIR}/checks.tsv"
PAYLOAD_FILE="${TEMP_DIR}/probe.ndjson"
DOWNLOAD_FILE="${TEMP_DIR}/download.ndjson"
VERSIONS_FILE="${TEMP_DIR}/versions.tsv"
ERROR_FILE="${TEMP_DIR}/aws.err"
CLEANUP_DONE=false
CLEANUP_STATUS=not_started
CLEANUP_REMOVED=0

export AWS_DEFAULT_REGION="$REGION"
export AWS_REGION="$REGION"

for command_name in aws jq python3 terraform; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'ERRO: comando obrigatório ausente: %s\n' "$command_name" >&2
    exit 2
  }
done

[[ -x "$SANITIZER" ]] || {
  printf 'ERRO: sanitizador não encontrado em %s\n' "$SANITIZER" >&2
  exit 2
}

touch "$CHECKS_FILE"
chmod 700 "$TEMP_DIR"
chmod 600 "$CHECKS_FILE"

tf_output() {
  terraform -chdir="$PART2_DIR" output -raw "$1"
}

first_key() {
  aws s3api list-objects-v2 \
    --bucket "$1" \
    --prefix "$2" \
    --max-keys 1 \
    --query 'Contents[0].Key' \
    --output text
}

record() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"$CHECKS_FILE"
}

cleanup_probe() {
  local response remaining key version_id cleanup_failed=false
  CLEANUP_STATUS=running
  if ! response="$(aws s3api list-object-versions \
    --bucket "$RAW_BUCKET" \
    --prefix "$PROBE_KEY" \
    --output json 2>"$ERROR_FILE")"; then
    CLEANUP_STATUS=failed
    return 1
  fi
  jq -r --arg key "$PROBE_KEY" \
    '[.Versions[]?, .DeleteMarkers[]?] | .[] | select(.Key == $key) | [.Key, .VersionId] | @tsv' \
    <<<"$response" >"$VERSIONS_FILE"
  while IFS=$'\t' read -r key version_id; do
    [[ -n "$key" && -n "$version_id" ]] || continue
    if aws s3api delete-object \
      --bucket "$RAW_BUCKET" \
      --key "$key" \
      --version-id "$version_id" >/dev/null 2>"$ERROR_FILE"; then
      CLEANUP_REMOVED=$((CLEANUP_REMOVED + 1))
    else
      cleanup_failed=true
    fi
  done <"$VERSIONS_FILE"
  if ! response="$(aws s3api list-object-versions \
    --bucket "$RAW_BUCKET" \
    --prefix "$PROBE_KEY" \
    --output json 2>"$ERROR_FILE")"; then
    CLEANUP_STATUS=failed
    return 1
  fi
  remaining="$(jq --arg key "$PROBE_KEY" \
    '[.Versions[]?, .DeleteMarkers[]?] | map(select(.Key == $key)) | length' \
    <<<"$response")"
  if [[ "$cleanup_failed" == false && "$remaining" == 0 ]]; then
    CLEANUP_STATUS=passed
    CLEANUP_DONE=true
    return 0
  fi
  CLEANUP_STATUS=failed
  return 1
}

remove_temp() {
  find "$TEMP_DIR" -type f -delete
  rmdir "$TEMP_DIR"
}

on_exit() {
  local status=$?
  trap - EXIT
  if [[ "$CLEANUP_DONE" != true && -n "${RAW_BUCKET:-}" && -n "${PROBE_KEY:-}" ]]; then
    cleanup_probe || status=1
  fi
  remove_temp
  exit "$status"
}
trap on_exit EXIT

aws sts get-caller-identity >/dev/null
RAW_BUCKET="$(tf_output raw_bucket)"
TRUSTED_BUCKET="$(tf_output trusted_bucket)"
REFINED_BUCKET="$(tf_output refined_bucket)"
ACCOUNT_ID="$(tf_output account_id)"
ROLES_JSON="$(terraform -chdir="$PART2_DIR" output -json layer_roles)"
INGESTION_ROLE="$(jq -r '.ingestion' <<<"$ROLES_JSON")"
INGESTION_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${INGESTION_ROLE}"
TRUSTED_KEY="$(first_key "$TRUSTED_BUCKET" orders/)"
REFINED_KEY="$(first_key "$REFINED_BUCKET" daily_sales/)"

for object_key in "$TRUSTED_KEY" "$REFINED_KEY"; do
  if [[ -z "$object_key" || "$object_key" == None ]]; then
    printf 'ERRO: execute o pipeline antes do teste para haver objetos reais em trusted e refined.\n' >&2
    exit 2
  fi
done

PROBE_UUID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
PROBE_KEY="orders/_access-check-${PROBE_UUID}.ndjson"
printf '{"probe":"eda262-g09-ingestion-access","synthetic":true}\n' >"$PAYLOAD_FILE"

(
  set +e
  ASSUMED_JSON="$(aws sts assume-role \
    --role-arn "$INGESTION_ARN" \
    --role-session-name eda262-g09-ingestion-access \
    --duration-seconds 900 \
    --output json)"
  export AWS_ACCESS_KEY_ID="$(jq -r '.Credentials.AccessKeyId' <<<"$ASSUMED_JSON")"
  export AWS_SECRET_ACCESS_KEY="$(jq -r '.Credentials.SecretAccessKey' <<<"$ASSUMED_JSON")"
  export AWS_SESSION_TOKEN="$(jq -r '.Credentials.SessionToken' <<<"$ASSUMED_JSON")"
  unset ASSUMED_JSON AWS_PROFILE AWS_DEFAULT_PROFILE

  if aws s3api put-object \
    --bucket "$RAW_BUCKET" \
    --key "$PROBE_KEY" \
    --body "$PAYLOAD_FILE" >/dev/null 2>"$ERROR_FILE"; then
    record ingestion_put_raw allowed allowed true
  else
    record ingestion_put_raw allowed unexpected_error false
  fi

  if aws s3api get-object \
    --bucket "$RAW_BUCKET" \
    --key "$PROBE_KEY" \
    "$DOWNLOAD_FILE" >/dev/null 2>"$ERROR_FILE" && cmp -s "$PAYLOAD_FILE" "$DOWNLOAD_FILE"; then
    record ingestion_get_raw allowed allowed true
  else
    record ingestion_get_raw allowed unexpected_error false
  fi

  LISTED_KEY="$(aws s3api list-objects-v2 \
    --bucket "$RAW_BUCKET" \
    --prefix "$PROBE_KEY" \
    --max-keys 1 \
    --query 'Contents[0].Key' \
    --output text 2>"$ERROR_FILE")"
  if [[ "$LISTED_KEY" == "$PROBE_KEY" ]]; then
    record ingestion_list_raw allowed allowed true
  else
    record ingestion_list_raw allowed unexpected_result false
  fi

  if aws s3api delete-object \
    --bucket "$RAW_BUCKET" \
    --key "$PROBE_KEY" >/dev/null 2>"$ERROR_FILE"; then
    record ingestion_delete_raw allowed allowed true
  else
    record ingestion_delete_raw allowed unexpected_error false
  fi

  check_denied_get() {
    local label="$1" bucket="$2" key="$3" target="${TEMP_DIR}/${1}.body"
    if aws s3api get-object \
      --bucket "$bucket" \
      --key "$key" \
      --range bytes=0-0 \
      "$target" >/dev/null 2>"$ERROR_FILE"; then
      record "$label" denied allowed false
    elif grep -Eiq 'AccessDenied|Forbidden|\(403\)|not authorized' "$ERROR_FILE"; then
      record "$label" denied denied true
    else
      record "$label" denied unexpected_error false
    fi
  }

  check_denied_get ingestion_get_trusted "$TRUSTED_BUCKET" "$TRUSTED_KEY"
  check_denied_get ingestion_get_refined "$REFINED_BUCKET" "$REFINED_KEY"
)

cleanup_probe || true

mkdir -p "$(dirname -- "$EVIDENCE_FILE")"
set +e
python3 - "$CHECKS_FILE" "$STAMP" "$CLEANUP_STATUS" "$CLEANUP_REMOVED" <<'PY' | \
  python3 "$SANITIZER" >"$EVIDENCE_FILE"
import csv
import json
import sys

checks_path, stamp, cleanup_status, cleanup_removed = sys.argv[1:]
with open(checks_path, encoding="utf-8", newline="") as source:
    rows = list(csv.reader(source, delimiter="\t"))
checks = [
    {
        "name": name,
        "expected": expected,
        "actual": actual,
        "passed": passed == "true",
    }
    for name, expected, actual, passed in rows
]
payload = {
    "generated_at_utc": stamp,
    "region": "us-east-1",
    "probe_scope": "raw/orders/_access-check-<uuid>.ndjson",
    "passed": len(checks) == 6
    and all(check["passed"] for check in checks)
    and cleanup_status == "passed",
    "check_count": len(checks),
    "checks": checks,
    "cleanup": {
        "status": cleanup_status,
        "versions_and_delete_markers_removed": int(cleanup_removed),
        "remaining_probe_versions": 0 if cleanup_status == "passed" else None,
    },
}
print(json.dumps(payload, indent=2, sort_keys=True))
if not payload["passed"]:
    raise SystemExit(1)
PY
PIPE_STATUSES=("${PIPESTATUS[@]}")
STATUS=0
for pipeline_status in "${PIPE_STATUSES[@]}"; do
  if [[ "$pipeline_status" -ne 0 ]]; then
    STATUS=1
  fi
done
set -e

if [[ "$STATUS" -ne 0 ]]; then
  printf 'FALHA: teste de ingestão divergiu. Evidência sanitizada: %s\n' "$EVIDENCE_FILE" >&2
  exit 1
fi
printf 'PASSA: 6 verificações funcionais e limpeza completa. Evidência sanitizada: %s\n' "$EVIDENCE_FILE"
