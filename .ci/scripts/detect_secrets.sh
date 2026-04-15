#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
detect-secrets scan --baseline .secrets.baseline
detect-secrets audit .secrets.baseline
echo "✓ Sin secretos detectados"
