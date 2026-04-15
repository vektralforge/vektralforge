#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
cd spark && pytest tests/ -v --cov=jobs --cov-report=term-missing
echo "✓ Tests Spark OK"
