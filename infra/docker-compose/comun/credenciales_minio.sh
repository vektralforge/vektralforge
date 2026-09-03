#!/usr/bin/env bash
#
# VektralForge — materializa en archivos las credenciales de MinIO
#
# Se ejecuta al arrancar el contenedor, antes de ceder el control al proceso
# real. Lee el secreto que docker-compose monta bajo /run/secrets/ y escribe,
# según lo que le pidan, uno o los dos consumidores que hay en el stack:
#
#   · core-site.xml  — lo lee S3A desde el classpath (el driver de Spark en el
#                      contenedor de Airflow, los executors en spark-worker y el
#                      Hive Metastore). La propiedad fs.s3a.aws.credentials.provider
#                      de la plantilla fija SimpleAWSCredentialsProvider, que
#                      toma access.key y secret.key de esta configuración.
#   · credentials    — el archivo INI del SDK de AWS, que boto3 encuentra por
#                      AWS_SHARED_CREDENTIALS_FILE. Es el segundo eslabón de su
#                      cadena por defecto, justo después del entorno.
#
# Por qué archivos y no variables de entorno: la variable de un contenedor de
# larga vida la enseñan `docker inspect`, `docker compose config` y el
# /proc/<pid>/environ de cualquier proceso del contenedor —incluido un volcado
# de soporte que alguien pegue en un issue—. Un archivo 600 escrito en el
# arranque, no.
#
# Entrada, toda por entorno. Ninguna de estas variables es un secreto: la única
# que lo es viaja como el CONTENIDO del archivo al que apunta la tercera.
#
#   MINIO_ACCESS_KEY       identificador de la cuenta de servicio
#   MINIO_ENDPOINT         URL de MinIO
#   MINIO_SECRET_KEY_FILE  ruta del secreto montado
#   VF_CORE_SITE           destino del core-site.xml   (vacío: no se genera)
#   VF_CORE_SITE_BASE      plantilla con las propiedades fijas
#   VF_AWS_CREDENTIALS     destino del archivo INI     (vacío: no se genera)

set -euo pipefail

: "${MINIO_ENDPOINT:=http://minio:9000}"
: "${MINIO_SECRET_KEY_FILE:=/run/secrets/minio_secret_key}"
: "${VF_CORE_SITE:=}"
: "${VF_CORE_SITE_BASE:=/opt/vektralforge/conf/core-site.xml.base}"
: "${VF_AWS_CREDENTIALS:=}"

if [ -z "${MINIO_ACCESS_KEY:-}" ]; then
  echo "ERROR: falta MINIO_ACCESS_KEY." >&2
  echo "       Es el identificador de la cuenta, no un secreto, y lleva valor" >&2
  echo "       por defecto en docker-compose.yml: si falta es que se borró." >&2
  exit 1
fi

if [ ! -r "$MINIO_SECRET_KEY_FILE" ]; then
  echo "ERROR: no se puede leer el secreto en $MINIO_SECRET_KEY_FILE" >&2
  echo "       Lo monta docker-compose.yml desde el bloque secrets:, que lo" >&2
  echo "       toma de MINIO_*_SECRET_KEY del .env. El origen environment:" >&2
  echo "       requiere Compose 2.20 o superior." >&2
  exit 1
fi

# La sustitución de comando ya se come los saltos de línea finales.
MINIO_SECRET_KEY="$(cat "$MINIO_SECRET_KEY_FILE")"

if [ -z "$MINIO_SECRET_KEY" ]; then
  echo "ERROR: el secreto en $MINIO_SECRET_KEY_FILE está vacío." >&2
  echo "       Arrancar con una credencial vacía da un 403 de MinIO en medio" >&2
  echo "       de un DAG, a media hora de distancia de la causa." >&2
  exit 1
fi

# Un espacio interior o un salto de línea no sobreviven al formato INI: el
# parser del SDK recorta y parte. Mejor rechazarlo aquí que depurar un 403.
case "$MINIO_SECRET_KEY" in
  *[[:space:]]*)
    echo "ERROR: el secreto contiene espacios o saltos de línea." >&2
    echo "       El archivo INI de credenciales no puede representarlos." >&2
    echo "       \`make init-env\` genera claves alfanuméricas de 40 caracteres." >&2
    exit 1 ;;
esac

# ── core-site.xml ────────────────────────────────────────────────────────────
#
# Se INSERTA en la plantilla en vez de sustituir marcadores con sed. El motivo
# es el mismo que llevó a hacerlo así con hive-site.xml en el #47: en un
# `sed s|__MARCA__|$VALOR|` el valor va en el lado de REEMPLAZO, donde & y \1
# tienen significado propio. Una clave con un & se corrompía en silencio.
escapar_xml() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

propiedad() {
  printf '  <property>\n    <name>%s</name>\n    <value>%s</value>\n  </property>\n' \
    "$1" "$(escapar_xml "$2")"
}

if [ -n "$VF_CORE_SITE" ]; then
  if [ ! -f "$VF_CORE_SITE_BASE" ]; then
    echo "ERROR: no se encuentra la plantilla en $VF_CORE_SITE_BASE" >&2
    echo "       La copia el Dockerfile desde infra/docker-compose/comun/." >&2
    exit 1
  fi

  # Escribir en un temporal y renombrar: `>` trunca el destino y truncar exige
  # permiso sobre el ARCHIVO, mientras que renombrar solo lo exige sobre el
  # DIRECTORIO. Y hace la escritura atómica.
  TMP="${VF_CORE_SITE}.tmp.$$"
  {
    sed '/<\/configuration>/d' "$VF_CORE_SITE_BASE"
    echo
    echo "  <!-- Generado en el arranque por credenciales_minio.sh. No editar. -->"
    propiedad fs.s3a.endpoint   "$MINIO_ENDPOINT"
    propiedad fs.s3a.access.key "$MINIO_ACCESS_KEY"
    propiedad fs.s3a.secret.key "$MINIO_SECRET_KEY"
    echo '</configuration>'
  } > "$TMP"
  chmod 600 "$TMP"
  mv -f "$TMP" "$VF_CORE_SITE"

  echo "→ core-site.xml: ${MINIO_ACCESS_KEY}@${MINIO_ENDPOINT} en $VF_CORE_SITE"
fi

# ── credentials (INI del SDK de AWS) ─────────────────────────────────────────
if [ -n "$VF_AWS_CREDENTIALS" ]; then
  DIRECTORIO="$(dirname "$VF_AWS_CREDENTIALS")"
  mkdir -p "$DIRECTORIO"
  chmod 700 "$DIRECTORIO"

  TMP="${VF_AWS_CREDENTIALS}.tmp.$$"
  printf '# Generado en el arranque por credenciales_minio.sh. No editar.\n[default]\naws_access_key_id = %s\naws_secret_access_key = %s\n' \
    "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" > "$TMP"
  chmod 600 "$TMP"
  mv -f "$TMP" "$VF_AWS_CREDENTIALS"

  echo "→ credenciales de boto3: perfil default en $VF_AWS_CREDENTIALS"
fi
