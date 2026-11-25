#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command aws
require_command jq
require_command python3
require_command terraform

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
output="${EVIDENCE_DIR}/access-matrix-${stamp}.json"
temp_dir="$(mktemp -d)"
checks_file="${temp_dir}/checks.tsv"
touch "$checks_file"
chmod 700 "$temp_dir"
chmod 600 "$checks_file"

cleanup() {
  find "$temp_dir" -type f -delete
  rmdir "$temp_dir"
}
trap cleanup EXIT

record() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  local passed="$4"
  actual="$(printf '%s' "$actual" | tr '\t\r\n' ' ' | cut -c1-500)"
  printf '%s\t%s\t%s\t%s\n' "$label" "$expected" "$actual" "$passed" >>"$checks_file"
}

database="$(tf_output database)"
workgroup="$(tf_output athena_workgroup)"
raw_bucket="$(tf_output raw_bucket)"
trusted_bucket="$(tf_output trusted_bucket)"
refined_bucket="$(tf_output refined_bucket)"
roles_json="$(terraform -chdir="$PART2_DIR" output -json layer_roles)"
account_id="$(aws sts get-caller-identity --query Account --output text)"
ingestion_role="$(jq -r '.ingestion' <<<"$roles_json")"
analyst_role="$(jq -r '.analyst' <<<"$roles_json")"
ingestion_arn="arn:aws:iam::${account_id}:role/${ingestion_role}"
analyst_arn="arn:aws:iam::${account_id}:role/${analyst_role}"

simulate() {
  local label="$1"
  local action="$2"
  local resource="$3"
  local expected="$4"
  local decision
  decision="$(aws iam simulate-principal-policy \
    --policy-source-arn "$ingestion_arn" \
    --action-names "$action" \
    --resource-arns "$resource" \
    --query 'EvaluationResults[0].EvalDecision' \
    --output text 2>"${temp_dir}/${label}.err" || true)"
  if [[ "$expected" == "allowed" && "$decision" == "allowed" ]]; then
    record "$label" "$expected" "$decision" true
  elif [[ "$expected" == "denied" && "$decision" =~ ^(implicitDeny|explicitDeny)$ ]]; then
    record "$label" "$expected" "$decision" true
  else
    record "$label" "$expected" "${decision:-$(<"${temp_dir}/${label}.err")}" false
  fi
}

raw_bucket_arn="arn:aws:s3:::${raw_bucket}"
trusted_bucket_arn="arn:aws:s3:::${trusted_bucket}"
refined_bucket_arn="arn:aws:s3:::${refined_bucket}"
simulate iam_ingestion_list_raw s3:ListBucket "$raw_bucket_arn" allowed
simulate iam_ingestion_location_raw s3:GetBucketLocation "$raw_bucket_arn" allowed
for action in GetObject PutObject DeleteObject; do
  lower="$(tr '[:upper:]' '[:lower:]' <<<"$action")"
  simulate "iam_ingestion_${lower}_raw" "s3:${action}" "${raw_bucket_arn}/orders/access-matrix-probe.ndjson" allowed
  simulate "iam_ingestion_${lower}_trusted" "s3:${action}" "${trusted_bucket_arn}/orders/access-matrix-probe.parquet" denied
  simulate "iam_ingestion_${lower}_refined" "s3:${action}" "${refined_bucket_arn}/daily_sales/access-matrix-probe.parquet" denied
done

first_key() {
  local bucket="$1"
  local prefix="$2"
  aws s3api list-objects-v2 \
    --bucket "$bucket" \
    --prefix "$prefix" \
    --max-keys 1 \
    --query 'Contents[0].Key' \
    --output text
}

raw_key="$(first_key "$raw_bucket" orders/)"
trusted_key="$(first_key "$trusted_bucket" orders/)"
refined_key="$(first_key "$refined_bucket" daily_sales/)"
for key in "$raw_key" "$trusted_key" "$refined_key"; do
  if [[ -z "$key" || "$key" == "None" ]]; then
    printf 'ERRO: execute a carga e o pipeline antes da matriz de acesso.\n' >&2
    exit 2
  fi
done
for table in raw_orders trusted_orders refined_daily_sales; do
  aws glue get-table --database-name "$database" --name "$table" >/dev/null
done

credentials_file="${temp_dir}/credentials.json"
aws sts assume-role \
  --role-arn "$analyst_arn" \
  --role-session-name eda262-g09-av2-access-test \
  --duration-seconds 900 \
  --output json >"$credentials_file"
chmod 600 "$credentials_file"

(
  export AWS_ACCESS_KEY_ID="$(jq -r '.Credentials.AccessKeyId' "$credentials_file")"
  export AWS_SECRET_ACCESS_KEY="$(jq -r '.Credentials.SecretAccessKey' "$credentials_file")"
  export AWS_SESSION_TOKEN="$(jq -r '.Credentials.SessionToken' "$credentials_file")"
  unset AWS_PROFILE AWS_DEFAULT_PROFILE

  check_get_object() {
    local label="$1"
    local bucket="$2"
    local key="$3"
    local expected="$4"
    local body="${temp_dir}/${label}.body"
    local error_file="${temp_dir}/${label}.err"
    if aws s3api get-object \
      --bucket "$bucket" \
      --key "$key" \
      --range bytes=0-0 \
      "$body" >"${temp_dir}/${label}.json" 2>"$error_file"; then
      if [[ "$expected" == "allowed" ]]; then
        record "$label" "$expected" allowed true
      else
        record "$label" "$expected" allowed false
      fi
    elif [[ "$expected" == "denied" ]] && grep -Eiq 'AccessDenied|Forbidden|\(403\)|not authorized' "$error_file"; then
      record "$label" "$expected" denied true
    else
      record "$label" "$expected" "$(<"$error_file")" false
    fi
  }

  check_query() {
    local label="$1"
    local table="$2"
    local expected="$3"
    local error_file="${temp_dir}/${label}.err"
    local query_id state reason
    if ! query_id="$(aws athena start-query-execution \
      --work-group "$workgroup" \
      --query-execution-context "Database=${database}" \
      --query-string "SELECT COUNT(*) FROM \"${database}\".\"${table}\"" \
      --query QueryExecutionId \
      --output text 2>"$error_file")"; then
      record "$label" "$expected" "start_failed: $(<"$error_file")" false
      return
    fi
    for _ in {1..90}; do
      state="$(aws athena get-query-execution \
        --query-execution-id "$query_id" \
        --query 'QueryExecution.Status.State' \
        --output text)"
      case "$state" in
        SUCCEEDED | FAILED | CANCELLED) break ;;
      esac
      sleep 2
    done
    reason="$(aws athena get-query-execution \
      --query-execution-id "$query_id" \
      --query 'QueryExecution.Status.StateChangeReason' \
      --output text)"
    if [[ "$expected" == "allowed" && "$state" == "SUCCEEDED" ]]; then
      record "$label" "$expected" "SUCCEEDED query_id=${query_id}" true
    elif [[ "$expected" == "denied" && "$state" == "FAILED" ]] &&
      grep -Eiq 'AccessDenied|not authorized|insufficient|permission|TABLE_NOT_FOUND|does not exist' <<<"$reason"; then
      record "$label" "$expected" "FAILED query_id=${query_id} reason=${reason}" true
    else
      record "$label" "$expected" "${state} query_id=${query_id} reason=${reason}" false
    fi
  }

  check_get_object analyst_s3_get_refined "$refined_bucket" "$refined_key" allowed
  check_get_object analyst_s3_get_raw "$raw_bucket" "$raw_key" denied
  check_get_object analyst_s3_get_trusted "$trusted_bucket" "$trusted_key" denied
  check_query analyst_athena_refined refined_daily_sales allowed
  check_query analyst_athena_raw raw_orders denied
  check_query analyst_athena_trusted trusted_orders denied
)

mkdir -p "$EVIDENCE_DIR"
set +e
python3 - "$checks_file" "$stamp" <<'PY' | sanitize_to "$output"
import csv
import json
import sys

path, stamp = sys.argv[1:]
with open(path, encoding="utf-8", newline="") as source:
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
    "passed": len(checks) == 17 and all(check["passed"] for check in checks),
    "check_count": len(checks),
    "checks": checks,
}
print(json.dumps(payload, indent=2, sort_keys=True))
if not payload["passed"]:
    raise SystemExit(1)
PY
statuses=("${PIPESTATUS[@]}")
set -e

if [[ "${statuses[0]}" -ne 0 || "${statuses[1]}" -ne 0 || ! -s "$output" ]]; then
  printf 'FALHA: matriz de acesso divergiu ou evidência não foi gravada. Evidência: %s\n' "$output" >&2
  exit 1
fi
printf 'PASSA: matriz de acesso funcional validada. Evidência: %s\n' "$output"
