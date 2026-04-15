#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
ruff check spark/jobs/
ruff format --check spark/jobs/
echo "✓ Lint Spark OK"
