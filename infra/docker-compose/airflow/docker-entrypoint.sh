#!/usr/bin/env bash
#
# VektralForge — arranque de los cuatro contenedores de Airflow
#
# Materializa las credenciales de MinIO en dos archivos y cede el control al
# entrypoint de la imagen de Airflow, que prepara el entorno antes del comando.
#
# Aquí hacen falta los dos formatos, porque en este contenedor conviven dos
# consumidores distintos: el driver de Spark —SparkSubmitOperator usa modo
# client, así que el driver corre AQUÍ— lee core-site.xml desde SPARK_CONF_DIR,
# y boto3, tanto el de los DAGs como el de los jobs de spark/jobs/, lee el INI
# que le indica AWS_SHARED_CREDENTIALS_FILE.
#
# Las rutas de salida las fija el Dockerfile con ENV VF_*.

set -euo pipefail

# airflow-init solo hace `db migrate` y no habla con MinIO, así que no recibe
# ni la cuenta ni el secreto. La exclusión es EXPLÍCITA y no un «si falta la
# variable, no pasa nada»: con esa forma, un servicio al que se le olvidara la
# cuenta arrancaría en silencio y fallaría media hora después con un 403.
if [ "${VF_CREDENCIALES_MINIO:-si}" = "no" ]; then
  echo "→ credenciales de MinIO omitidas a propósito (VF_CREDENCIALES_MINIO=no)"
else
  /opt/vektralforge/bin/credenciales_minio.sh
fi

if [ -x /entrypoint ]; then
  exec /entrypoint "$@"
fi

echo "⚠ /entrypoint no existe en la imagen base; se ejecuta el comando directamente." >&2
exec "$@"
