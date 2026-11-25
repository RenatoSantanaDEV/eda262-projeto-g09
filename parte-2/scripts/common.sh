#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PART2_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROJECT_DIR="$(cd -- "${PART2_DIR}/.." && pwd)"
EVIDENCE_DIR="${PROJECT_DIR}/evidencias/av2/brutas"
REGION="us-east-1"

export AWS_DEFAULT_REGION="$REGION"
export AWS_REGION="$REGION"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'ERRO: comando obrigatório ausente: %s\n' "$1" >&2
    exit 2
  }
}

tf_output() {
  terraform -chdir="$PART2_DIR" output -raw "$1"
}

sanitize_to() {
  local output="$1"
  python3 "${SCRIPT_DIR}/sanitize.py" >"$output"
}

wait_for_glue_run() {
  local job="$1"
  local run_id="$2"
  local state
  local timeout="${GLUE_WAIT_TIMEOUT_SECONDS:-2400}"
  local interval="${GLUE_POLL_SECONDS:-20}"
  if [[ ! "$timeout" =~ ^[1-9][0-9]*$ || ! "$interval" =~ ^[1-9][0-9]*$ ]]; then
    printf 'Timeout e intervalo Glue devem ser inteiros positivos.\n' >&2
    return 2
  fi
  local deadline=$((SECONDS + timeout))
  while true; do
    state="$(aws glue get-job-run \
      --job-name "$job" \
      --run-id "$run_id" \
      --query 'JobRun.JobRunState' \
      --cli-connect-timeout 10 --cli-read-timeout 30 \
      --output text)" || return 1
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$state"
    case "$state" in
      SUCCEEDED) return 0 ;;
      FAILED | STOPPED | TIMEOUT | ERROR | EXPIRED)
        aws glue get-job-run \
          --job-name "$job" \
          --run-id "$run_id" \
          --query 'JobRun.ErrorMessage' \
          --output text >&2
        return 1
        ;;
    esac
    if ((SECONDS >= deadline)); then
      printf 'Timeout local aguardando Glue; run %s pode continuar ativo.\n' "$run_id" >&2
      return 1
    fi
    local remaining=$((deadline - SECONDS))
    if ((remaining < interval)); then
      sleep "$remaining"
    else
      sleep "$interval"
    fi
  done
}

