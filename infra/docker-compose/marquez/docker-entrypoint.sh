#!/usr/bin/env sh
#
# Genera marquez.yml a partir de la plantilla y las variables de entorno,
# luego arranca Marquez.
#
# Se usa sed en vez de envsubst para no depender del paquete gettext, que no
# está en todas las imágenes base.

set -eu

TEMPLATE="${MARQUEZ_CONFIG_TEMPLATE:-/usr/src/app/marquez.yml.template}"
OUTPUT="${MARQUEZ_CONFIG:-/usr/src/app/marquez.yml}"

: "${MARQUEZ_DB_HOST:=postgres}"
: "${MARQUEZ_DB_PORT:=5432}"
: "${MARQUEZ_DB_NAME:=marquez}"
: "${MARQUEZ_LOG_LEVEL:=INFO}"

# Estas dos no tienen valor por defecto a propósito: sin ellas Marquez
# arrancaría con credenciales silenciosamente incorrectas y fallaría 40
# segundos después con un error de autenticación difícil de rastrear.
if [ -z "${MARQUEZ_DB_USER:-}" ] || [ -z "${MARQUEZ_DB_PASSWORD:-}" ]; then
  echo "ERROR: faltan MARQUEZ_DB_USER o MARQUEZ_DB_PASSWORD." >&2
  echo "       Se pasan desde infra/docker-compose/.env vía docker-compose.yml." >&2
  exit 1
fi

if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: no se encuentra la plantilla en $TEMPLATE" >&2
  exit 1
fi

# El delimitador | evita conflictos con las barras de la URL JDBC.
sed \
  -e "s|\${MARQUEZ_DB_HOST}|${MARQUEZ_DB_HOST}|g" \
  -e "s|\${MARQUEZ_DB_PORT}|${MARQUEZ_DB_PORT}|g" \
  -e "s|\${MARQUEZ_DB_NAME}|${MARQUEZ_DB_NAME}|g" \
  -e "s|\${MARQUEZ_DB_USER}|${MARQUEZ_DB_USER}|g" \
  -e "s|\${MARQUEZ_DB_PASSWORD}|${MARQUEZ_DB_PASSWORD}|g" \
  -e "s|\${MARQUEZ_LOG_LEVEL}|${MARQUEZ_LOG_LEVEL}|g" \
  "$TEMPLATE" > "$OUTPUT"

chmod 600 "$OUTPUT"

echo "→ marquez.yml generado: ${MARQUEZ_DB_USER}@${MARQUEZ_DB_HOST}:${MARQUEZ_DB_PORT}/${MARQUEZ_DB_NAME}"

exec "$@"
