#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
ruff check airflow/dags/ airflow/plugins/
ruff format --check airflow/dags/ airflow/plugins/
echo "✓ Lint DAGs OK"
