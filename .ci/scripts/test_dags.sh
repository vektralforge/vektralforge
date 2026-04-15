#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
cd airflow && pytest tests/ -v --cov=dags --cov-report=term-missing
echo "✓ Tests DAGs OK"
