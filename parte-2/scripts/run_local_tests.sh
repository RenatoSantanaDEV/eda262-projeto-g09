#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PART2_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
export PYTHONDONTWRITEBYTECODE=1
python3 -m unittest discover -s "${PART2_DIR}/tests" -p 'test_*.py'
python3 -c 'import sys, pyspark; assert sys.version_info[:2] == (3, 10), "Use Python 3.10"; assert pyspark.__version__ == "3.3.0", "Use Spark 3.3.0"'
export PYSPARK_PYTHON="$(command -v python3)"
export SPARK_LOCAL_IP="${SPARK_LOCAL_IP:-127.0.0.1}"
python3 -m unittest discover -s "${PART2_DIR}/tests" -p 'spark_cases.py'
