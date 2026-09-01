#!/usr/bin/env bash
#
# Ejecuta los tests de DAGs.
#
# pytest devuelve 5 cuando no recoge ningún test. Se trata como fallo, no como
# éxito: un pipeline de CI en verde sin tests es peor que uno en rojo, porque
# transmite una confianza que no existe.

set -euo pipefail
cd "$(dirname "$0")/../.."
cd airflow

set +e
pytest tests/ -v --cov=dags --cov=plugins --cov-report=term-missing
codigo=$?
set -e

if [ "$codigo" -eq 5 ]; then
    echo ""
    echo "  ✗ No se recogió ningún test en airflow/tests/"
    echo "    Si es intencional, el CI no debería reportar éxito."
    exit 1
fi

exit "$codigo"
