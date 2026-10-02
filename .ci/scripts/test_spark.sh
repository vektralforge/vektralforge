#!/usr/bin/env bash
#
# Ejecuta los tests de jobs Spark.
#
# pytest devuelve 5 cuando no recoge ningún test. Se trata como fallo, igual que
# en test_dags.sh: un CI en verde sin tests transmite una confianza que no
# existe. La excepción que había aquí dejó de hacer falta cuando las
# transformaciones se separaron a spark/jobs/transformaciones.py.

set -euo pipefail
cd "$(dirname "$0")/../.."
cd spark

set +e
pytest tests/ -v --cov=jobs --cov-report=term-missing
codigo=$?
set -e

if [ "$codigo" -eq 5 ]; then
    echo ""
    echo "[ERROR] No tests were collected in spark/tests/"
    echo "    If this is intentional, CI shouldn't report success."
    exit 1
fi

exit "$codigo"
