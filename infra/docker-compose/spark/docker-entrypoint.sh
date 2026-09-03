#!/usr/bin/env bash
#
# VektralForge — arranque de spark-master y spark-worker
#
# Materializa las credenciales de MinIO en core-site.xml y en el INI del SDK
# (ver credenciales_minio.sh) y luego cede el control al entrypoint de la
# imagen base, que es quien sabe interpretar los modos `driver` y `executor`.
#
# Las rutas de salida las fija el Dockerfile con ENV VF_*; aquí no se repiten
# para que solo haya un sitio donde cambiarlas.

set -euo pipefail

/opt/vektralforge/bin/credenciales_minio.sh

# La imagen de Apache Spark trae su propio /opt/entrypoint.sh. Se encadena en
# vez de sustituirlo, y si algún día desaparece de la base esto sigue
# arrancando el comando directamente en vez de morir con «not found».
if [ -x /opt/entrypoint.sh ]; then
  exec /opt/entrypoint.sh "$@"
fi

echo "⚠ /opt/entrypoint.sh no existe en la imagen base; se ejecuta el comando directamente." >&2
exec "$@"
