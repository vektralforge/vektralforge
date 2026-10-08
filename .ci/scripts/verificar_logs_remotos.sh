#!/usr/bin/env bash
# .ci/scripts/verificar_logs_remotos.sh
#
# Comprueba que los logs de las tareas de Airflow llegaron al object store.
#
# El logging remoto falla en silencio: si el bucket no existe o la cuenta no
# puede escribir, Airflow sigue ejecutando las tareas y solo lo deja anotado en
# su propio log. Con el volumen compartido desaparecido, eso significa logs que
# se pierden al reiniciar el contenedor sin que nada se ponga rojo. Este guion
# es lo que lo pone rojo.
#
# Va DESPUÉS de haber ejecutado algún DAG —en CI, tras los pipelines de
# ejemplo; en local, tras `make dev-load-example`— y corre dentro del
# contenedor de Airflow, con la misma cuenta y el mismo endpoint que usa el
# S3TaskHandler. Ningún secreto pasa por aquí.
#
# Log: mismo formato [INFO]/[ERROR] en inglés que el resto de los scripts —
# homologado también dentro del programa Python embebido.

set -uo pipefail

C_AIRFLOW=docker-compose-airflow-webserver-1

if ! docker inspect --format='{{.State.Status}}' "$C_AIRFLOW" 2>/dev/null | grep -q running; then
    echo "[ERROR] $C_AIRFLOW is not running. Run: make dev-up" >&2
    exit 1
fi

docker exec -i "$C_AIRFLOW" python3 - <<'PY'
import os
import sys

import boto3
from botocore.config import Config

s3 = boto3.client(
    "s3",
    endpoint_url=os.environ.get("S3_ENDPOINT", "http://rustfs:9000"),
    region_name="us-east-1",
    config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
)

# Airflow 3 escribe dag_id=<dag>/run_id=<run>/task_id=<tarea>/attempt=<n>.log.
# Lo que deja verificar_permisos.py en _control_permisos/ no cuenta.
logs = []
for pagina in s3.get_paginator("list_objects_v2").paginate(
    Bucket="airflow-logs", Prefix="dag_id="
):
    logs += [o for o in pagina.get("Contents", []) if o["Key"].endswith(".log")]

if not logs:
    print("[ERROR] airflow-logs has no task logs.")
    print("    If a DAG already ran, Airflow isn't uploading the logs: check the")
    print("    scheduler log for \"S3\" or \"remote\".")
    sys.exit(1)

dags = sorted({o["Key"].split("/", 1)[0].removeprefix("dag_id=") for o in logs})
vacios = [o["Key"] for o in logs if o["Size"] == 0]
print(f"[INFO]  {len(logs)} task log(s) in airflow-logs, from {len(dags)} DAG(s):")
for d in dags:
    print(f"    {d}")
if vacios:
    print(f"[ERROR] {len(vacios)} empty log(s), e.g. {vacios[0]}")
    sys.exit(1)
PY
