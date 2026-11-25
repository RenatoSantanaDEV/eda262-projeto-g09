#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command aws
require_command python3
require_command terraform

mode="${1:-FULL}"
days="${2:-all}"
mode="$(printf '%s' "$mode" | tr '[:lower:]' '[:upper:]')"
if [[ "$mode" != "FULL" && "$mode" != "BACKFILL" ]]; then
  printf 'Uso: %s [FULL|BACKFILL] [all|AAAA-MM-DD[,AAAA-MM-DD]]\n' "$0" >&2
  exit 2
fi
if [[ "$mode" == "BACKFILL" && ! "$days" =~ ^20[0-9]{2}-[0-9]{2}-[0-9]{2}(,20[0-9]{2}-[0-9]{2}-[0-9]{2})*$ ]]; then
  printf 'BACKFILL exige uma ou mais datas AAAA-MM-DD.\n' >&2
  exit 2
fi

job="$(tf_output glue_job)"
report_bucket="$(tf_output artifacts_bucket)"
mkdir -p "$EVIDENCE_DIR"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
prefix="pipeline-$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')-${stamp}"

arguments="{\"--MODE\":\"${mode}\",\"--DAYS\":\"${days}\"}"
start_timeout="${GLUE_START_TIMEOUT_SECONDS:-180}"
retry_interval="${GLUE_START_RETRY_SECONDS:-10}"
if [[ ! "$start_timeout" =~ ^[1-9][0-9]*$ || ! "$retry_interval" =~ ^[1-9][0-9]*$ ]]; then
  printf 'GLUE_START_TIMEOUT_SECONDS e GLUE_START_RETRY_SECONDS devem ser inteiros positivos.\n' >&2
  exit 2
fi
start_deadline=$((SECONDS + start_timeout))
start_error="$(mktemp)"
run_id=""
while [[ -z "$run_id" ]]; do
  if run_id="$(aws glue start-job-run \
    --job-name "$job" \
    --arguments "$arguments" \
    --query 'JobRunId' \
    --output text 2>"$start_error")"; then
    break
  fi
  run_id=""
  if ! grep -q 'ConcurrentRunsExceededException' "$start_error"; then
    cat "$start_error" >&2
    rm -f -- "$start_error"
    exit 1
  fi
  if ((SECONDS + retry_interval > start_deadline)); then
    printf 'Timeout de %ss aguardando liberação do slot Glue para %s.\n' "$start_timeout" "$job" >&2
    cat "$start_error" >&2
    rm -f -- "$start_error"
    exit 1
  fi
  printf 'Slot Glue ainda ocupado; nova tentativa em %ss.\n' "$retry_interval" >&2
  sleep "$retry_interval"
done
rm -f -- "$start_error"
prefix="${prefix}-${run_id}"

set +e
wait_for_glue_run "$job" "$run_id" | sanitize_to "${EVIDENCE_DIR}/${prefix}.txt"
wait_statuses=("${PIPESTATUS[@]}")
set -e
aws glue get-job-run \
  --job-name "$job" \
  --run-id "$run_id" \
  --output json \
  | sanitize_to "${EVIDENCE_DIR}/${prefix}.json"
if [[ "${wait_statuses[0]}" -ne 0 || "${wait_statuses[1]}" -ne 0 ]]; then
  printf 'Execução Glue ou gravação de evidência falhou: %s\n' "$run_id" >&2
  exit 1
fi
aws s3 cp \
  "s3://${report_bucket}/reports/runs/${run_id}.json" \
  - \
  | sanitize_to "${EVIDENCE_DIR}/${prefix}-report.json"

python3 - "${EVIDENCE_DIR}/${prefix}-report.json" "$run_id" "$mode" <<'PYREPORT'
import json
import sys

path, run_id, mode = sys.argv[1:]
with open(path, encoding="utf-8") as source:
    report = json.load(source)
if report.get("job_run_id") != run_id or report.get("mode") != mode:
    raise SystemExit("Relatório não pertence à execução e modo solicitados")
PYREPORT

if [[ -n "${PIPELINE_REPORT_PATH_FILE:-}" ]]; then
  printf '%s\n' "${EVIDENCE_DIR}/${prefix}-report.json" >"$PIPELINE_REPORT_PATH_FILE"
fi

printf 'Glue run concluído: %s (evidências %s*)\n' "$run_id" "${EVIDENCE_DIR}/${prefix}"

