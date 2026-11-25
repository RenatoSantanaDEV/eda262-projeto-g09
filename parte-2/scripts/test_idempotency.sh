#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command aws
require_command python3
require_command terraform

query_file="${PROJECT_DIR}/consultas/av2-verificacao.sql"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
result_file="${EVIDENCE_DIR}/idempotency-${stamp}.json"
mkdir -p "$EVIDENCE_DIR"

run_diagnostic() {
  local label="$1"
  local results execution
  if ! results="$("${SCRIPT_DIR}/run_query.sh" "$query_file")"; then
    printf 'Consulta diagnóstica %s falhou.\n' "$label" >&2
    return 1
  fi
  execution="${results%-results.json}-execution.json"
  if [[ ! -f "$results" || ! -f "$execution" ]]; then
    printf 'Evidência exata da consulta %s não foi criada.\n' "$label" >&2
    return 1
  fi
  python3 - "$label" "$results" "$execution" <<'PY'
import json
import sys

label, path, execution_path = sys.argv[1:]
execution = json.load(open(execution_path, encoding="utf-8"))
state = execution.get("QueryExecution", {}).get("Status", {}).get("State")
if state != "SUCCEEDED":
    raise SystemExit(f"consulta diagnóstica {label} terminou em {state!r}")
payload = json.load(open(path, encoding="utf-8"))
rows = payload.get("ResultSet", {}).get("Rows", [])
if len(rows) < 2:
    raise SystemExit(f"consulta diagnóstica {label} não retornou dados")
headers = [cell.get("VarCharValue") for cell in rows[0]["Data"]]
values = [cell.get("VarCharValue") for cell in rows[1]["Data"]]
if not headers or len(headers) != len(values):
    raise SystemExit(f"consulta diagnóstica {label} retornou colunas inválidas")
row = dict(zip(headers, values))
required = {"trusted_rows", "distinct_keys", "partitions", "gross_sales"}
missing = sorted(required - row.keys())
if missing:
    raise SystemExit(f"consulta diagnóstica {label} sem colunas: {', '.join(missing)}")
if any(row[key] in (None, "") for key in required):
    raise SystemExit(f"consulta diagnóstica {label} contém valor vazio")
print(json.dumps({"label": label, **row}, sort_keys=True))
PY
}

report_pointer="$(mktemp)"
trap 'rm -f -- "$report_pointer"' EXIT
export PIPELINE_REPORT_PATH_FILE="$report_pointer"
"${SCRIPT_DIR}/run_pipeline.sh" FULL all
before_report="$(cat "$report_pointer")"
if ! before="$(run_diagnostic before)"; then
  exit 1
fi
"${SCRIPT_DIR}/run_pipeline.sh" FULL all
after_report="$(cat "$report_pointer")"
if ! after="$(run_diagnostic after)"; then
  exit 1
fi

python3 - "$before" "$after" "$before_report" "$after_report" >"$result_file" <<'PY'
import json
import sys
from decimal import Decimal, InvalidOperation

before, after = map(json.loads, sys.argv[1:3])
keys = ("trusted_rows", "distinct_keys", "partitions", "gross_sales")
for label, payload in (("before", before), ("after", after)):
    missing = [key for key in keys if key not in payload]
    if missing:
        raise SystemExit(f"{label} sem métricas: {', '.join(missing)}")
    if any(payload[key] in (None, "") for key in keys):
        raise SystemExit(f"{label} contém métrica vazia")
    try:
        rows = int(payload["trusted_rows"])
        distinct = int(payload["distinct_keys"])
        partitions = int(payload["partitions"])
        gross = Decimal(payload["gross_sales"])
    except (InvalidOperation, TypeError, ValueError) as exc:
        raise SystemExit(f"{label} contém métrica inválida: {exc}") from exc
    if rows <= 0 or distinct <= 0 or partitions <= 0 or gross <= 0:
        raise SystemExit(f"{label} contém métrica não positiva")
    if rows != distinct:
        raise SystemExit(f"{label} contém duplicatas: {rows} linhas, {distinct} chaves")
passed = all(before[key] == after[key] for key in keys)
reports = []
for path in sys.argv[3:]:
    with open(path, encoding="utf-8") as source:
        reports.append(json.load(source))
for report in reports:
    if report.get("mode") != "FULL" or not report.get("job_run_id"):
        raise SystemExit("Relatório sem identificação de execução FULL")
    digests = report.get("content_sha256", {})
    for layer in ("trusted", "refined", "quarantine_selected"):
        value = digests.get(layer)
        if not isinstance(value, str) or len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
            raise SystemExit(f"Hash inválido ou ausente: {layer}")
if reports[0]["job_run_id"] == reports[1]["job_run_id"]:
    raise SystemExit("Idempotência exige duas execuções distintas")
passed = passed and reports[0]["content_sha256"] == reports[1]["content_sha256"]
passed = passed and reports[0]["code_sha256"] == reports[1]["code_sha256"]
payload = {"passed": passed, "before": before, "after": after, "runs": [{k: report[k] for k in ("job_run_id", "code_sha256", "content_sha256")} for report in reports]}
print(json.dumps(payload, indent=2, sort_keys=True))
if not passed:
    raise SystemExit(1)
PY

printf 'PASSA: reexecução manteve métricas e conteúdo trusted/refined/quarentena. Evidência: %s\n' "$result_file"

