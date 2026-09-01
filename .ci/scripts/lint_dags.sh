#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Se incluye tests/: es código como cualquier otro y hasta ahora quedaba
# fuera del CI. Un fallo de orden de imports en un test solo lo veía
# pre-commit, que corre sobre todos los archivos.
ruff check airflow/dags/ airflow/plugins/ airflow/tests/
ruff format --check airflow/dags/ airflow/plugins/ airflow/tests/
echo "✓ Lint DAGs OK"
