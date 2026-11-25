#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command aws
require_command python3
require_command terraform

query_file="${1:-${PROJECT_DIR}/consultas/av2-valor-bruto.sql}"
if [[ ! -f "$query_file" ]]; then
  printf 'Consulta não encontrada: %s\n' "$query_file" >&2
  exit 2
fi

database="$(tf_output database)"
workgroup="$(tf_output athena_workgroup)"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$EVIDENCE_DIR"
execution_file="${EVIDENCE_DIR}/athena-${stamp}-execution.json"
results_file="${EVIDENCE_DIR}/athena-${stamp}-results.json"
metrics_file="${EVIDENCE_DIR}/athena-${stamp}-metrics.json"
query_id="$(aws athena start-query-execution \
  --work-group "$workgroup" \
  --query-execution-context "Database=${database}" \
  --query-string "$(<"$query_file")" \
  --query 'QueryExecutionId' \
  --output text)"

while true; do
  state="$(aws athena get-query-execution \
    --query-execution-id "$query_id" \
    --query 'QueryExecution.Status.State' \
    --output text)"
  case "$state" in
    SUCCEEDED) break ;;
    FAILED | CANCELLED)
      aws athena get-query-execution --query-execution-id "$query_id" --output json >&2
      exit 1
      ;;
  esac
  sleep 2
done

aws athena get-query-execution \
  --query-execution-id "$query_id" \
  --output json \
  | sanitize_to "$execution_file"
aws athena get-query-results \
  --query-execution-id "$query_id" \
  --output json \
  | sanitize_to "$results_file"

python3 - "$EVIDENCE_DIR" "$stamp" <<'PY'
import json
import pathlib
import sys

evidence = pathlib.Path(sys.argv[1])
stamp = sys.argv[2]
execution = json.loads((evidence / f"athena-{stamp}-execution.json").read_text())
query = execution["QueryExecution"]
stats = query.get("Statistics", {})
summary = {
    "query_execution_id": query.get("QueryExecutionId"),
    "state": query.get("Status", {}).get("State"),
    "data_scanned_bytes": stats.get("DataScannedInBytes"),
    "engine_execution_ms": stats.get("EngineExecutionTimeInMillis"),
    "total_execution_ms": stats.get("TotalExecutionTimeInMillis"),
    "result_reused": stats.get("ResultReuseInformation", {}).get("ReusedPreviousResult", False),
    "cost_formula_pending": "Aplicar preço oficial vigente em us-east-1 e mínimo faturável da data da execução.",
}
(evidence / f"athena-{stamp}-metrics.json").write_text(
    json.dumps(summary, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

printf 'Consulta %s concluída. Métricas: %s\n' "$query_id" "$metrics_file" >&2
printf '%s\n' "$results_file"

