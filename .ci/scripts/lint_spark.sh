#!/usr/bin/env bash
# .ci/scripts/lint_spark.sh
# Lint de jobs PySpark con Ruff.
set -euo pipefail
cd "$(dirname "$0")/../.."
echo "→ Ruff lint spark/jobs/..."
ruff check spark/jobs/
ruff format --check spark/jobs/
echo "✓ Lint Spark OK"
