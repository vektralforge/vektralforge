#!/usr/bin/env bash
# .ci/scripts/lint_sql.sh
# Lint de queries SQL con sqlfluff.
set -euo pipefail
cd "$(dirname "$0")/../.."
echo "→ sqlfluff lint trino/catalog/ hive/schemas/..."
sqlfluff lint trino/catalog/ hive/schemas/ --dialect trino
echo "✓ Lint SQL OK"
