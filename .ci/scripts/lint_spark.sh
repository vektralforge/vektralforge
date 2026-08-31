#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
ruff check spark/jobs/ spark/tests/
ruff format --check spark/jobs/ spark/tests/
echo "✓ Lint Spark OK"
