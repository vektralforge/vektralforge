#!/usr/bin/env bash
# .ci/scripts/test_dags.sh
# Tests unitarios de DAGs de Airflow.
set -euo pipefail
cd "$(dirname "$0")/../.."
echo "→ pytest airflow/tests/..."
cd airflow
pytest tests/ -v --cov=dags --cov-report=term-missing
echo "✓ Tests DAGs OK"
