#!/usr/bin/env bash
# .ci/scripts/esperar_stack.sh
#
# Espera a que el stack esté LISTO, no solo arrancado, y falla con un mensaje
# que dice qué servicio no llegó.
#
# `docker compose up --wait` no alcanza: solo seis de los diecisiete servicios
# declaran healthcheck, así que para Trino, el metastore o Spark «running»
# significa que el proceso existe, no que responda. Y `airflow-init` termina a
# propósito, lo que `--wait` cuenta como fallo. Aquí cada servicio se comprueba
# haciéndole la pregunta que de verdad importa.
#
# Uso: esperar_stack.sh [timeout_segundos]   (por defecto 600)

set -uo pipefail

TIMEOUT="${1:-600}"
P=docker-compose   # prefijo de los contenedores (nombre del directorio del Compose)

estado_salud() { docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}sin-healthcheck{{end}}' "$P-$1-1" 2>/dev/null; }

# Cada comprobación devuelve 0 cuando el servicio está listo.
sano()            { [ "$(estado_salud "$1")" = healthy ]; }
airflow_init_ok() { [ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' "$P-airflow-init-1" 2>/dev/null)" = "exited:0" ]; }
trino_ok()        { docker exec "$P-trino-1" trino --execute 'SELECT 1' >/dev/null 2>&1; }
# Listar esquemas del catálogo Delta obliga a Trino a hablar con el metastore,
# y el metastore con Postgres: tres servicios en una sola pregunta.
metastore_ok()    { docker exec "$P-trino-1" trino --execute 'SHOW SCHEMAS FROM delta' >/dev/null 2>&1; }
# Un master sin workers acepta trabajos y los deja esperando para siempre.
spark_ok()        { curl -fsS http://127.0.0.1:8082/json/ 2>/dev/null | grep -Eq '"aliveworkers"[[:space:]]*:[[:space:]]*[1-9]'; }
superset_ok()     { curl -fsS -o /dev/null http://127.0.0.1:8088/health 2>/dev/null; }
scheduler_ok()    { docker exec "$P-airflow-scheduler-1" airflow jobs check --job-type SchedulerJob --local >/dev/null 2>&1; }

COMPROBACIONES=(
    "postgres|sano postgres"
    "rustfs|sano rustfs"
    "redis|sano redis"
    "airflow-init|airflow_init_ok"
    "airflow-webserver|sano airflow-webserver"
    "airflow-scheduler|scheduler_ok"
    "marquez-api|sano marquez-api"
    "trino|trino_ok"
    "hive-metastore (vía Trino)|metastore_ok"
    "spark (master + worker)|spark_ok"
    "superset|superset_ok"
)

inicio=$(date +%s)
pendientes=("${COMPROBACIONES[@]}")

while [ ${#pendientes[@]} -gt 0 ]; do
    siguen=()
    for c in "${pendientes[@]}"; do
        nombre="${c%%|*}"; cmd="${c#*|}"
        if $cmd; then
            echo "  ✓ $nombre ($(( $(date +%s) - inicio ))s)"
        else
            siguen+=("$c")
        fi
    done
    pendientes=(${siguen[@]+"${siguen[@]}"})
    [ ${#pendientes[@]} -eq 0 ] && break

    if [ $(( $(date +%s) - inicio )) -ge "$TIMEOUT" ]; then
        echo ""
        echo "  ✗ Tras ${TIMEOUT}s siguen sin estar listos:" >&2
        for c in "${pendientes[@]}"; do echo "      ${c%%|*}" >&2; done
        exit 1
    fi
    sleep 5
done

echo "  ✓ Stack listo en $(( $(date +%s) - inicio ))s"
