#!/usr/bin/env bash
#
# VektralForge — arranque de Trino
#
# Renderiza los catálogos desde trino/catalog/ y cede el control al lanzador de
# la imagen base.
#
# Por qué hace falta renderizar: Trino solo sabe resolver `${ENV:VARIABLE}` en
# sus archivos de configuración, así que la clave de MinIO tenía que estar en el
# entorno del contenedor —y por tanto en `docker inspect`, en `docker compose
# config` y en el /proc/<pid>/environ de cualquier proceso de dentro—. Aquí
# llega como archivo montado y solo aparece en el catálogo renderizado, 600, en
# la capa de escritura del contenedor, que desaparece con él.
#
# El identificador de la cuenta SÍ sigue resolviéndose con ${ENV:...}: no es un
# secreto, y así se ve en el archivo versionado a qué cuenta entra Trino.

set -euo pipefail

PLANTILLAS="${VF_TRINO_PLANTILLAS:-/etc/trino/catalog-plantilla}"
DESTINO="${VF_TRINO_CATALOGO:-/etc/trino/catalog}"
MARCA="__MINIO_SECRET__"

: "${MINIO_SECRET_KEY_FILE:=/run/secrets/minio_trino_secret_key}"

if [ ! -d "$PLANTILLAS" ]; then
  echo "ERROR: no se encuentra el directorio de plantillas en $PLANTILLAS" >&2
  echo "       Lo monta docker-compose.yml desde trino/catalog/." >&2
  exit 1
fi

if [ ! -r "$MINIO_SECRET_KEY_FILE" ]; then
  echo "ERROR: no se puede leer el secreto en $MINIO_SECRET_KEY_FILE" >&2
  echo "       Lo monta docker-compose.yml desde el bloque secrets:, que lo" >&2
  echo "       toma de MINIO_TRINO_SECRET_KEY del .env." >&2
  exit 1
fi

MINIO_SECRET_KEY="$(cat "$MINIO_SECRET_KEY_FILE")"

if [ -z "$MINIO_SECRET_KEY" ]; then
  echo "ERROR: el secreto en $MINIO_SECRET_KEY_FILE está vacío." >&2
  exit 1
fi

mkdir -p "$DESTINO"
chmod 700 "$DESTINO"

# Se vacía antes de renderizar. La capa de escritura del contenedor sobrevive a
# un `restart`, así que un catálogo que se quitara de la plantilla seguiría
# activo indefinidamente sin que el repositorio lo dijera.
rm -f "$DESTINO"/*.properties

# Sustitución por línea COMPLETA, no con sed. En un `sed s|MARCA|$CLAVE|` el
# valor va en el lado de reemplazo, donde & y \1 tienen significado propio: una
# clave con un & se corrompería en silencio y Trino daría un 403 sin más pista.
sustituciones=0
for plantilla in "$PLANTILLAS"/*.properties; do
  [ -e "$plantilla" ] || continue
  destino="$DESTINO/$(basename "$plantilla")"
  tmp="${destino}.tmp.$$"

  while IFS= read -r linea || [ -n "$linea" ]; do
    case "$linea" in
      *"$MARCA"*)
        printf 's3.aws-secret-key=%s\n' "$MINIO_SECRET_KEY"
        sustituciones=$((sustituciones + 1))
        ;;
      *)
        printf '%s\n' "$linea"
        ;;
    esac
  done < "$plantilla" > "$tmp"

  chmod 600 "$tmp"
  mv -f "$tmp" "$destino"
done

if [ "$sustituciones" -ne 1 ]; then
  echo "ERROR: se esperaba exactamente una línea con $MARCA en $PLANTILLAS," >&2
  echo "       y se encontraron $sustituciones. O el catálogo cambió de forma," >&2
  echo "       o Trino iba a arrancar sin credencial." >&2
  exit 1
fi

echo "→ catálogos renderizados en $DESTINO ($(ls -1 "$DESTINO" | tr '\n' ' '))"

exec /usr/lib/trino/bin/run-trino "$@"
