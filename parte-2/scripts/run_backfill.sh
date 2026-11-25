#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

day="${1:-2026-09-15}"
if [[ ! "$day" =~ ^20[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
  printf 'Uso: %s [AAAA-MM-DD]\n' "$0" >&2
  exit 2
fi
exec "${SCRIPT_DIR}/run_pipeline.sh" BACKFILL "$day"

