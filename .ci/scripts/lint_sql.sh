#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
sqlfluff lint trino/catalog/ hive/schemas/ --dialect trino
echo "✓ Lint SQL OK"
