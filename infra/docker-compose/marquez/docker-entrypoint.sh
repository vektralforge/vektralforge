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

# El usuario no tiene valor por defecto a propósito: sin él Marquez arrancaría
# con credenciales silenciosamente incorrectas y fallaría 40 segundos después
# con un error de autenticación difícil de rastrear.
if [ -z "${MARQUEZ_DB_USER:-}" ]; then
  echo "ERROR: falta MARQUEZ_DB_USER." >&2
  echo "       Se pasa desde infra/docker-compose/.env vía docker-compose.yml." >&2
  exit 1
fi

# La contraseña llega como archivo, no como variable: así no aparece en
# `docker inspect` ni en /proc/<pid>/environ. Se acepta todavía la variable
# para no romper a quien tenga un compose antiguo, pero el archivo manda.
if [ -n "${MARQUEZ_DB_PASSWORD_FILE:-}" ]; then
  if [ ! -r "$MARQUEZ_DB_PASSWORD_FILE" ]; then
    echo "ERROR: no se puede leer el secreto en $MARQUEZ_DB_PASSWORD_FILE" >&2
    echo "       Lo monta docker-compose.yml desde el bloque secrets:." >&2
    echo "       Requiere Compose 2.20 o superior para el origen environment:." >&2
    exit 1
  fi
  MARQUEZ_DB_PASSWORD="$(cat "$MARQUEZ_DB_PASSWORD_FILE")"
elif [ -z "${MARQUEZ_DB_PASSWORD:-}" ]; then
  echo "ERROR: faltan MARQUEZ_DB_PASSWORD_FILE y MARQUEZ_DB_PASSWORD." >&2
  echo "       El compose monta el secreto en /run/secrets/postgres_password." >&2
  exit 1
fi

if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: no se encuentra la plantilla en $TEMPLATE" >&2
  exit 1
fi

# Los valores van en el lado de reemplazo de sed, donde \, & y el delimitador
# tienen significado propio: sin escaparlos, una contraseña con un & produce un
# marquez.yml corrupto y un fallo de autenticación que no apunta a su causa.
# Y \ y " se escapan además para el escalar YAML entrecomillado.
escapar_sed() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}
escapar_yaml() {
  printf '%s' "$1" | sed -e 's/[\\"]/\\&/g'
}

# El delimitador | evita conflictos con las barras de la URL JDBC.
sed \
  -e "s|\${MARQUEZ_DB_HOST}|$(escapar_sed "$MARQUEZ_DB_HOST")|g" \
  -e "s|\${MARQUEZ_DB_PORT}|$(escapar_sed "$MARQUEZ_DB_PORT")|g" \
  -e "s|\${MARQUEZ_DB_NAME}|$(escapar_sed "$MARQUEZ_DB_NAME")|g" \
  -e "s|\${MARQUEZ_DB_USER}|$(escapar_sed "$(escapar_yaml "$MARQUEZ_DB_USER")")|g" \
  -e "s|\${MARQUEZ_DB_PASSWORD}|$(escapar_sed "$(escapar_yaml "$MARQUEZ_DB_PASSWORD")")|g" \
  -e "s|\${MARQUEZ_LOG_LEVEL}|$(escapar_sed "$MARQUEZ_LOG_LEVEL")|g" \
  "$TEMPLATE" > "$OUTPUT"

chmod 600 "$OUTPUT"

echo "→ marquez.yml generado: ${MARQUEZ_DB_USER}@${MARQUEZ_DB_HOST}:${MARQUEZ_DB_PORT}/${MARQUEZ_DB_NAME}"

exec "$@"
