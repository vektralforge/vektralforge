#!/usr/bin/env bash
# .ci/scripts/deploy_k3s.sh
# Despliega manifiestos K3s al namespace especificado.
# Uso: .ci/scripts/deploy_k3s.sh [staging|prod]
set -euo pipefail
ENVIRONMENT="${1:-staging}"

if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "prod" ]]; then
  echo "ERROR: ambiente debe ser 'staging' o 'prod'"
  exit 1
fi

NAMESPACE="lakeforge-${ENVIRONMENT}"
cd "$(dirname "$0")/../.."

echo "→ Validando manifiestos K3s..."
kubectl apply --dry-run=client -f infra/k3s/namespaces/
kubectl apply --dry-run=client -f infra/k3s/services/

echo "→ Aplicando manifiestos a namespace ${NAMESPACE}..."
kubectl apply -f infra/k3s/namespaces/
kubectl apply -n "$NAMESPACE" -f infra/k3s/services/

echo "✓ Deploy a ${NAMESPACE} completado"
