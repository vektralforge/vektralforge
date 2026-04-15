#!/usr/bin/env bash
# .ci/scripts/lint_dags.sh
# Lint de DAGs de Airflow con Ruff.
set -euo pipefail
cd "$(dirname "$0")/../.."
echo "→ Ruff lint airflow/dags/..."
ruff check airflow/dags/ airflow/plugins/
echo "→ Ruff format check airflow/dags/..."
ruff format --check airflow/dags/ airflow/plugins/
echo "✓ Lint DAGs OK"
