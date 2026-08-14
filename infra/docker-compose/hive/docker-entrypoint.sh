#!/usr/bin/env bash
#
# Genera core-site.xml a partir de la plantilla y las variables de entorno,
# luego cede el control al entrypoint original de la imagen de Hive.

set -euo pipefail

TEMPLATE="${HIVE_CORE_SITE_TEMPLATE:-/opt/hadoop/etc/hadoop/core-site.xml.template}"
OUTPUT="${HIVE_CORE_SITE:-/opt/hadoop/etc/hadoop/core-site.xml}"

: "${MINIO_ENDPOINT:=http://minio:9000}"

if [ -z "${MINIO_ROOT_USER:-}" ] || [ -z "${MINIO_ROOT_PASSWORD:-}" ]; then
  echo "ERROR: faltan MINIO_ROOT_USER o MINIO_ROOT_PASSWORD." >&2
  echo "       Se pasan desde infra/docker-compose/.env vía docker-compose.yml." >&2
  exit 1
fi

if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: no se encuentra la plantilla en $TEMPLATE" >&2
  exit 1
fi

# Delimitador | para no chocar con las barras de las URL.
sed \
  -e "s|__MINIO_ENDPOINT__|${MINIO_ENDPOINT}|g" \
  -e "s|__MINIO_ACCESS__|${MINIO_ROOT_USER}|g" \
  -e "s|__MINIO_SECRET__|${MINIO_ROOT_PASSWORD}|g" \
  "$TEMPLATE" > "$OUTPUT"

chmod 640 "$OUTPUT"

echo "→ core-site.xml generado: ${MINIO_ENDPOINT} (s3:// y s3a:// vía S3A)"

exec /entrypoint.sh "$@"
