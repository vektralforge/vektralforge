#!/usr/bin/env bash
# .ci/scripts/test_spark.sh
# Tests de jobs PySpark con pytest + chispa.
set -euo pipefail
cd "$(dirname "$0")/../.."
echo "→ pytest spark/tests/..."
cd spark
pytest tests/ -v --cov=jobs --cov-report=term-missing
echo "✓ Tests Spark OK"
