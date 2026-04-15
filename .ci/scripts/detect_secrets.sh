#!/usr/bin/env bash
# .ci/scripts/detect_secrets.sh
# Escaneo de secretos en el repositorio.
# Bloquea el pipeline si encuentra credenciales.
set -euo pipefail
cd "$(dirname "$0")/../.."
echo "→ Escaneando secretos con detect-secrets..."
detect-secrets scan --baseline .secrets.baseline
detect-secrets audit .secrets.baseline
echo "✓ Sin secretos detectados"
