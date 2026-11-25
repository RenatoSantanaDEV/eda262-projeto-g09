#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command aws
require_command python3
require_command terraform

generated_dir="${PART2_DIR}/.generated"
summary_file="${EVIDENCE_DIR}/generation-summary.json"
load_file="${EVIDENCE_DIR}/raw-load.txt"
bucket="$(tf_output raw_bucket)"
mkdir -p "$EVIDENCE_DIR"

python3 "${SCRIPT_DIR}/generate_raw.py" \
  --output "$generated_dir" \
  --start-date 2026-09-01 \
  --days 30 \
  --orders-per-day 4000 \
  --seed 20261118 \
  >"$summary_file"

printf 'Sincronizando dataset determinístico para s3://%s/orders/\n' "$bucket"
aws s3 sync \
  "${generated_dir}/raw/orders/" \
  "s3://${bucket}/orders/" \
  --delete \
  --only-show-errors

{
  printf 'loaded_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'region=%s\n' "$REGION"
  printf 'bucket=%s\n' "$bucket"
  aws s3 ls "s3://${bucket}/orders/" --recursive --summarize
} | sanitize_to "$load_file"

printf 'Evidências sanitizadas: %s e %s\n' "$summary_file" "$load_file"

