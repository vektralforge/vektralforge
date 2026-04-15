#!/usr/bin/env bash
set -euo pipefail
ENVIRONMENT="${1:-staging}"
[[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "prod" ]] && \
  echo "ERROR: ambiente debe ser 'staging' o 'prod'" && exit 1
NAMESPACE="lakeforge-${ENVIRONMENT}"
cd "$(dirname "$0")/../.."
kubectl apply --dry-run=client -f infra/k3s/namespaces/
kubectl apply -f infra/k3s/namespaces/
kubectl apply -n "$NAMESPACE" -f infra/k3s/services/
echo "✓ Deploy a ${NAMESPACE} completado"
