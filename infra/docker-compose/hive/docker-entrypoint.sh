#!/usr/bin/env bash
#
# Genera core-site.xml y hive-site.xml a partir del entorno y del secreto
# montado, luego cede el control al entrypoint original de la imagen de Hive.

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

# ── hive-site.xml: conexión al metastore ─────────────────────────────────────
#
# Estas cuatro propiedades viajaban en SERVICE_OPTS, que el entrypoint de la
# imagen concatena a HADOOP_CLIENT_OPTS. Eso las pone en la línea de comandos de
# la JVM, donde las lee cualquier proceso del contenedor con un `ps` y `docker
# top` desde fuera. Aquí acaban en un archivo con permisos 640.
#
# Se INSERTA en el hive-site.xml de la imagen, que trae once propiedades suyas
# (hive.metastore.warehouse.dir entre ellas). La copia .base la hace el
# Dockerfile y hace el arranque idempotente.

BASE="${HIVE_SITE_BASE:-/opt/hive/conf/hive-site.xml.base}"
HIVE_SITE="${HIVE_SITE:-/opt/hive/conf/hive-site.xml}"
PASSWORD_FILE="${POSTGRES_PASSWORD_FILE:-/run/secrets/postgres_password}"

: "${METASTORE_DB_DRIVER:=org.postgresql.Driver}"
: "${METASTORE_DB_URL:=jdbc:postgresql://postgres:5432/metastore}"

if [ -z "${METASTORE_DB_USER:-}" ]; then
  echo "ERROR: falta METASTORE_DB_USER." >&2
  echo "       Se pasa desde infra/docker-compose/.env vía docker-compose.yml." >&2
  exit 1
fi

if [ ! -r "$PASSWORD_FILE" ]; then
  echo "ERROR: no se puede leer el secreto en $PASSWORD_FILE" >&2
  echo "       Lo monta docker-compose.yml desde el bloque secrets:." >&2
  echo "       Requiere Compose 2.20 o superior para el origen environment:." >&2
  exit 1
fi

if [ ! -f "$BASE" ]; then
  echo "ERROR: no se encuentra el hive-site.xml base en $BASE" >&2
  echo "       Lo crea el Dockerfile copiando el de la imagen." >&2
  exit 1
fi

METASTORE_DB_PASSWORD="$(cat "$PASSWORD_FILE")"

# La contraseña va dentro de un <value>, así que hay que escapar los tres
# caracteres que XML no admite en texto. No se usa sed para insertarla: en sed
# el valor iría en el lado de reemplazo, donde & y \1 tienen significado.
escapar_xml() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

propiedad() {
  printf '  <property>\n    <name>%s</name>\n    <value>%s</value>\n  </property>\n' \
    "$1" "$(escapar_xml "$2")"
}

# Se escribe en un temporal y se renombra, no directamente sobre el destino.
# Dos motivos: `>` trunca el archivo existente y truncar exige permiso sobre el
# ARCHIVO —el de la imagen es de root:root 644 y esto corre como hive—, mientras
# que renombrar solo exige permiso sobre el directorio. Y hace la escritura
# atómica: matar el contenedor a media escritura no deja un XML truncado.
TMP="${HIVE_SITE}.tmp.$$"
{
  sed '/<\/configuration>/d' "$BASE"
  echo
  echo "  <!-- Generado en el arranque por docker-entrypoint.sh. No editar. -->"
  propiedad javax.jdo.option.ConnectionDriverName "$METASTORE_DB_DRIVER"
  propiedad javax.jdo.option.ConnectionURL        "$METASTORE_DB_URL"
  propiedad javax.jdo.option.ConnectionUserName   "$METASTORE_DB_USER"
  propiedad javax.jdo.option.ConnectionPassword   "$METASTORE_DB_PASSWORD"
  echo '</configuration>'
} > "$TMP"

chmod 640 "$TMP"
mv -f "$TMP" "$HIVE_SITE"

echo "→ hive-site.xml generado: ${METASTORE_DB_USER}@${METASTORE_DB_URL}"

exec /entrypoint.sh "$@"
