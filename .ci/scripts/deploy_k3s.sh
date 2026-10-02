#!/usr/bin/env bash
#
# Despliegue a K3s — NO IMPLEMENTADO TODAVÍA.
#
# Este script aplicaba `infra/k3s/services/`, un directorio que nunca ha
# existido. `make deploy-staging` y `make deploy-prod` han fallado siempre, y no
# con un mensaje sino con un error de kubectl sobre una ruta ausente, después de
# haber creado ya los namespaces. Era el hallazgo §1.4 de la revisión y el más
# antiguo sin resolver.
#
# Lo que falta no es un directorio: es el despliegue entero. Trece cargas de
# trabajo con sus Services, ConfigMaps, Secrets, PVCs e Ingress. Y antes de eso,
# un prerrequisito que tampoco estaba escrito en ninguna parte: las imágenes del
# proyecto solo existen como etiquetas locales en la máquina que las construyó,
# así que no hay registro del que un cluster pueda tirarlas.
#
# Mientras tanto, esto falla a propósito y explica por qué, en vez de intentarlo
# y reventar a mitad. El entorno soportado hoy es Docker Compose: `make dev-up`.

set -euo pipefail

ENVIRONMENT="${1:-staging}"
if [ "$ENVIRONMENT" != "staging" ] && [ "$ENVIRONMENT" != "prod" ]; then
    echo "[ERROR] environment must be 'staging' or 'prod'." >&2
    exit 1
fi

cd "$(dirname "$0")/../.."

MANIFIESTOS="infra/k3s/services"

if [ ! -d "$MANIFIESTOS" ]; then
    cat >&2 <<'MENSAJE'
[ERROR] K3s deployment is not implemented yet.

  infra/k3s/services/ is missing, along with the manifests for the thirteen
  services. Only the namespaces currently exist under infra/k3s/.

  There's also an earlier prerequisite missing: publishing the project's
  images to a registry. vektralforge/airflow, /spark, /hive-metastore, /trino
  and /marquez-api currently only exist as local tags.

  Tracking: the "K3s deployment" issue in the repository.
  Supported environment today: Docker Compose — `make dev-up`.
MENSAJE
    exit 1
fi

# ── A partir de aquí, el día que existan los manifiestos ─────────────────────
#
# Se comprueba kubectl antes de usarlo: sin él, el error es un «command not
# found» que no dice qué falta instalar.
if ! command -v kubectl >/dev/null 2>&1; then
    echo "[ERROR] kubectl is not installed or not in PATH." >&2
    exit 1
fi

NAMESPACE="vektralforge-${ENVIRONMENT}"

kubectl apply --dry-run=client -f infra/k3s/namespaces/
kubectl apply -f infra/k3s/namespaces/
kubectl apply --dry-run=client -n "$NAMESPACE" -f "$MANIFIESTOS/"
kubectl apply -n "$NAMESPACE" -f "$MANIFIESTOS/"

echo "[INFO]  Deploy to ${NAMESPACE} completed"
