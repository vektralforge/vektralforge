#!/usr/bin/env bash
# .ci/scripts/load_example.sh
# Carga datos de ejemplo después de make dev-reset o make dev-reset-hard
#
# Diseño: cada DAG es independiente — si uno falla, los demás continúan.
# Al final se muestra resumen de qué tuvo éxito y qué falló.
#
# Log: mismo formato [INFO]/[WARN]/[ERROR] en inglés que el resto de los
# scripts. Los status de DAG_STATUS/DASHBOARD_STATUS ahora empiezan con
# "[INFO]  SUCCESS" / "[ERROR] FAILED" en vez de "✓ SUCCESS" / "✗ FAILED" —
# el chequeo de all_failed al final se actualizó para seguir comparando
# contra el prefijo correcto, si no la detección de "todo falló" se habría
# roto en silencio.
set -uo pipefail

ENV_FILE="${1:-infra/docker-compose/.env}"

# Cuánto esperar a que una tarea termine.
#
# Antes eran 300 s, y contradecían al propio DAG: sus `default_args` declaran
# execution_timeout de 20 min, retries=1 y retry_delay de 5 min, o sea un peor
# caso legítimo de 45 minutos. Esperar 5 significaba reportar "✗ falló" sobre
# tareas que estaban trabajando bien — confundir lento con roto.
#
# Pasó de verdad el 2 sep con mindicador.cl degradado: el intento 1 murió por
# SSLError, la tarea entró en up_for_retry con 5 min de espera por delante, y el
# presupuesto entero se consumió ahí mientras el intento 2 descargaba sin
# problemas.
#
# 30 min cubre un ciclo completo de reintento sin llegar a los 45 del peor caso
# absoluto, que casi siempre indica algo realmente atascado. Ajustable por
# entorno para el CI o para una API que se sabe lenta.
TIMEOUT="${VF_TIMEOUT_TAREA:-1800}"
INTERVAL="${VF_INTERVALO_SONDEO:-10}"

# Registro de resultados por DAG
declare -A DAG_STATUS

log()     { echo "[INFO]  $*"; }
ok()      { echo "[INFO]  $*"; }
warn()    { echo "[WARN]  $*"; }
fail_msg(){ echo "[ERROR] $*"; }

# Esperar que un DAG complete — task por task
# Retorna 0 si todo éxito, 1 si algún task falló
wait_dag() {
    local dag_id="$1" run_id="$2"
    shift 2
    local tasks=("$@")
    local elapsed=0

    for task in "${tasks[@]}"; do
        echo "    Waiting: $task"
        local task_elapsed=0
        while [ $task_elapsed -lt $TIMEOUT ]; do
            sleep $INTERVAL
            task_elapsed=$((task_elapsed + INTERVAL))
            elapsed=$((elapsed + INTERVAL))
            local state
            state=$(docker exec docker-compose-airflow-scheduler-1 \
                airflow tasks state "$dag_id" "$task" "$run_id" 2>/dev/null \
                | tail -1 | tr -d '[:space:]')
            echo "      [${elapsed}s] $task → ${state:-pending}"
            case "$state" in
                success)
                    ok "$task completed"
                    break
                    ;;
                failed|upstream_failed)
                    fail_msg "$task failed"
                    return 1
                    ;;
                up_for_retry)
                    # Ni éxito ni fallo: Airflow va a reintentar tras
                    # retry_delay. Antes caía en el saco de "todavía nada" y el
                    # presupuesto se agotaba durante la espera. Se avisa una
                    # sola vez para que la pausa se entienda.
                    if [ "${aviso_reintento:-}" != "$task" ]; then
                        warn "$task will retry — the pause comes from the DAG's retry_delay"
                        aviso_reintento="$task"
                    fi
                    ;;
            esac
            if [ $task_elapsed -ge $TIMEOUT ]; then
                # "No terminó" no es lo mismo que "falló": puede seguir viva.
                fail_msg "$task is still in '${state:-pending}' after ${TIMEOUT}s"
                fail_msg "  It may still be running. Check the real status at:"
                fail_msg "  http://localhost:8090/dags/${dag_id}/grid"
                return 1
            fi
        done
    done
    return 0
}

# ── 1. Verificar stack ────────────────────────────────────────────────────────
log "Checking the stack..."
stack_ok=true
for s in airflow-webserver airflow-scheduler spark-master minio trino superset postgres; do
    st=$(docker inspect --format='{{.State.Status}}' "docker-compose-${s}-1" 2>/dev/null || echo "missing")
    if [ "$st" != "running" ]; then
        fail_msg "Service $s is not running. Run: make dev-up"
        stack_ok=false
    fi
done
[ "$stack_ok" = "true" ] || { echo "[ERROR] Incomplete stack — aborting"; exit 1; }
ok "Stack operational"

# ── 2. Verificar buckets ──────────────────────────────────────────────────────
log "Checking MinIO buckets..."
for b in raw bronze silver gold checkpoints; do
    if ! docker exec docker-compose-minio-1 mc ls "local/$b" &>/dev/null; then
        warn "Missing buckets — creating them..."
        # Solo los buckets. Antes se llamaba a init_users.sh entero, que además
        # recreaba los usuarios admin y reinicializaba los roles de Superset:
        # efectos que nadie pide al cargar datos de ejemplo.
        bash .ci/scripts/init_users.sh "$ENV_FILE" buckets
        break
    fi
done
ok "MinIO buckets available"

# Aquí había un bloque que descargaba antlr4-runtime-4.9.3.jar desde
# repo1.maven.org, sin hash ni firma, y lo metía como root en /opt/spark/jars de
# master y worker. No hacía falta y hacía daño: la imagen de Spark ya trae
# antlr4-runtime-4.13.1.jar (spark 4.0.x, 4.1.x y 4.2.x fijan antlr4.version en
# 4.13.1 en su pom). Como el `test -f` buscaba la 4.9.3, nunca acertaba, así que
# la bajaba en cada ejecución y dejaba dos runtimes de antlr en el classpath.
# Si algún día vuelve a fallar el parser de SQL, la respuesta no es descargar un
# JAR a mano: es mirar qué versión trae la imagen.

# Ejecuta uno de los scripts de dashboards dentro del contenedor de Superset.
#
# Antes esto iba en línea con `2>/dev/null | grep -E "✓|✗|⚠|====" || true`, y esa
# combinación hacía el paso INCAPAZ DE FALLAR: el stderr se descartaba, el grep
# se quedaba solo con las líneas decoradas y el `|| true` borraba el código de
# salida. Un ImportError dejaba el paso mudo y el resumen final seguía diciendo
# SUCCESS.
#
# Importa porque estos scripts no usan la API REST: importan modelos internos de
# Superset (`superset.connectors.sqla.models`, `superset.models.dashboard`), que
# es lo primero que se mueve al subir de versión mayor. Sin ver el error, una
# subida rota parece una subida limpia.
DASHBOARD_STATUS=()

configurar_dashboard() {
    local etiqueta="$1" script="$2"
    local ruta_local="superset/dashboards/${script}"
    local salida codigo

    log "Configuring ${etiqueta} dashboard in Superset..."

    if ! docker cp "$ruta_local" "docker-compose-superset-1:/tmp/${script}"; then
        fail_msg "${etiqueta}: could not copy ${script} to the container"
        DASHBOARD_STATUS+=("[ERROR] FAILED  (dashboard ${etiqueta})")
        return 1
    fi

    # stderr se une a stdout a propósito: es donde aparece el traceback. No hace
    # falta `set +e`: este script corre con `set -uo pipefail`, sin errexit —
    # restaurarlo con `set -e` lo habría ACTIVADO para todo lo que viene después.
    salida=$(docker exec docker-compose-superset-1 bash -c "cd /app && python3 -c \"
import sys; sys.path.insert(0, '/app')
from superset.app import create_app
app = create_app()
with app.app_context():
    exec(open('/tmp/${script}').read())
\"" 2>&1)
    codigo=$?

    if [ "$codigo" -ne 0 ]; then
        fail_msg "${etiqueta}: the script exited with code ${codigo}"
        echo "$salida" | tail -15 | sed 's/^/      /'
        DASHBOARD_STATUS+=("[ERROR] FAILED  (dashboard ${etiqueta})")
        return 1
    fi

    # Este grep filtra la salida del script de Superset (no nuestra), que
    # sigue imprimiendo sus propios ✓/✗/⚠/==== — no se toca aquí porque ese
    # script queda fuera del alcance de esta homologación.
    echo "$salida" | grep -E "✓|✗|⚠|====" | sed 's/^/  /'
    DASHBOARD_STATUS+=("[INFO]  SUCCESS (dashboard ${etiqueta})")
    return 0
}

# ── 3. Copiar jobs Spark ──────────────────────────────────────────────────────
log "Syncing Spark jobs..."
docker cp spark/jobs/bronze_indicadores.py \
    docker-compose-spark-master-1:/opt/spark/jobs/bronze_indicadores.py 2>/dev/null || true
docker cp spark/jobs/bronze_arclim.py \
    docker-compose-spark-master-1:/opt/spark/jobs/bronze_arclim.py 2>/dev/null || true
ok "Spark jobs updated"

# ── 4. El catálogo lo crea Spark ─────────────────────────────────────────────
# Aquí había un CREATE SCHEMA desde Trino. Ya no hace falta: los jobs usan
# saveAsTable contra el Hive Metastore compartido, así que crean la base y
# registran las tablas ellos mismos. Crearla desde Trino además la fijaría con
# location s3:// antes de que Spark pudiera declarar la suya.

# ════════════════════════════════════════════════════════════════════════════════
# Función genérica para cargar un DAG
# Uso: load_dag <dag_id> <run_id_prefix> <task1> <task2> ...
# ════════════════════════════════════════════════════════════════════════════════
load_dag() {
    local dag_id="$1"
    local run_prefix="$2"
    shift 2
    local tasks=("$@")

    echo ""
    log "══ DAG: $dag_id ══"

    # Activar DAG
    docker exec docker-compose-airflow-scheduler-1 \
        airflow dags unpause "$dag_id" 2>/dev/null \
        | grep -v "^$\|INFO\|WARNING\|DagBag" || true

    # Verificar si ya hay un run activo (queued o running).
    #
    # En Airflow 3 el dag_id es posicional: `-d` y `--output` son de Airflow 2 y
    # hacían fallar el comando en silencio, así que esta comprobación nunca
    # detectó nada y el script disparaba siempre un run nuevo. Con el DAG recién
    # despausado eso significa dos runs en paralelo sobre la misma fecha.
    #
    # El CLI escribe líneas de log en stdout junto a la tabla, de ahí el filtro
    # por dag_id en lugar de saltar solo la cabecera.
    local existing_run
    existing_run=$(docker exec docker-compose-airflow-scheduler-1 \
        airflow dags list-runs "$dag_id" -o plain 2>/dev/null \
        | awk -v d="$dag_id" '$1 == d && ($3 == "queued" || $3 == "running") {print $2}' \
        | head -1)

    local run_id
    if [ -n "$existing_run" ]; then
        run_id="$existing_run"
        warn "Active run detected — using: $run_id"
    else
        local ts
        ts=$(date -u +"%Y%m%dT%H%M%S")
        run_id="${run_prefix}-${ts}"
        docker exec docker-compose-airflow-scheduler-1 \
            airflow dags trigger "$dag_id" --run-id "$run_id" 2>/dev/null \
            | grep -v "^$\|INFO\|WARNING\|DagBag" || true
        ok "Triggered (run_id: $run_id)"
    fi

    # Esperar
    if wait_dag "$dag_id" "$run_id" "${tasks[@]}"; then
        DAG_STATUS[$dag_id]="[INFO]  SUCCESS"
        return 0
    else
        DAG_STATUS[$dag_id]="[ERROR] FAILED — see http://localhost:8090/dags/${dag_id}/grid"
        warn "$dag_id failed — continuing with the next DAG"
        return 1
    fi
}

# ════════════════════════════════════════════════════════════════════════════════
# DAG 1: indicadores_financieros_chile
# ════════════════════════════════════════════════════════════════════════════════
if load_dag "indicadores_financieros_chile" "dev-load-ind" \
    "extract_indicadores" "transform_bronze" "validar_bronze"; then

    # Spark ya registró las tablas en el metastore; aquí solo se comprueba que
    # Trino las ve. Si esta lista sale vacía, el problema está en el catálogo,
    # no en el pipeline.
    log "Indicator tables visible in Trino:"
    docker exec docker-compose-trino-1 trino --execute \
        "SHOW TABLES FROM delta.bronze LIKE 'indicadores_%';" \
        2>/dev/null | grep -v "WARNING\|INFO\|jline\|^$" | sed 's/^/    /' || true

    docker exec docker-compose-trino-1 trino --execute "
    CREATE OR REPLACE VIEW delta.bronze.indicadores_todos AS
    SELECT fecha, valor, indicador, nombre, fuente, fecha_proceso, anio, mes FROM delta.bronze.indicadores_uf
    UNION ALL SELECT fecha, valor, indicador, nombre, fuente, fecha_proceso, anio, mes FROM delta.bronze.indicadores_dolar
    UNION ALL SELECT fecha, valor, indicador, nombre, fuente, fecha_proceso, anio, mes FROM delta.bronze.indicadores_euro
    UNION ALL SELECT fecha, valor, indicador, nombre, fuente, fecha_proceso, anio, mes FROM delta.bronze.indicadores_utm
    UNION ALL SELECT fecha, valor, indicador, nombre, fuente, fecha_proceso, anio, mes FROM delta.bronze.indicadores_tpm;
    " 2>/dev/null | grep -v "WARNING\|INFO\|jline" || true
    ok "indicadores_todos view created"

    log "Indicator counts in Trino:"
    docker exec docker-compose-trino-1 trino --execute \
        "SELECT indicador, COUNT(*) as filas FROM delta.bronze.indicadores_todos GROUP BY indicador ORDER BY indicador;" \
        2>/dev/null | grep -v "WARNING\|INFO\|jline\|^$" | sed 's/^/    /' || true

    configurar_dashboard "indicators" setup_superset_dashboard.py || true

else
    warn "indicadores_financieros_chile failed — skipping Trino and Superset for this DAG"
fi

# ════════════════════════════════════════════════════════════════════════════════
# DAG 2: arclim_riesgo_climatico_chile
# ════════════════════════════════════════════════════════════════════════════════
if load_dag "arclim_riesgo_climatico_chile" "dev-load-arclim" \
    "extract_arclim" "transform_bronze" "validar_bronze"; then

    log "ARClim tables visible in Trino:"
    docker exec docker-compose-trino-1 trino --execute \
        "SHOW TABLES FROM delta.bronze LIKE 'arclim_%';" \
        2>/dev/null | grep -v "WARNING\|INFO\|jline\|^$" | sed 's/^/    /' || true

    log "ARClim counts in Trino:"
    docker exec docker-compose-trino-1 trino --execute \
        "SELECT indicador, COUNT(*) as comunas, MIN(anio_serie) as desde, MAX(anio_serie) as hasta
         FROM delta.bronze.arclim_series GROUP BY indicador ORDER BY indicador;" \
        2>/dev/null | grep -v "WARNING\|INFO\|jline\|^$" | sed 's/^/    /' || true

    configurar_dashboard "ARClim" setup_superset_arclim.py || true

else
    warn "arclim_riesgo_climatico_chile failed — skipping Trino and the ARClim dashboard"
fi

# ── Resumen final ─────────────────────────────────────────────────────────────
echo ""
echo "  ══════════════════════════════════════════════════"
echo "  Sample data load summary"
echo "  ══════════════════════════════════════════════════"
for dag_id in "${!DAG_STATUS[@]}"; do
    echo "    ${DAG_STATUS[$dag_id]}  ($dag_id)"
done
# Los dashboards también aparecen: antes su fallo era invisible aquí.
for estado in ${DASHBOARD_STATUS[@]+"${DASHBOARD_STATUS[@]}"}; do
    echo "    $estado"
done
echo ""
echo "  Airflow   → http://localhost:8090"
echo "  Trino     → http://localhost:8081"
echo "  MinIO     → http://localhost:9001"
echo "  Marquez   → http://localhost:3000"
echo "  Dashboard → http://localhost:8088/superset/dashboard/indicadores-financieros-chile/"
echo ""

# Salir con error solo si TODOS los DAGs fallaron
all_failed=true
for dag_id in "${!DAG_STATUS[@]}"; do
    [[ "${DAG_STATUS[$dag_id]}" == "[INFO]"* ]] && all_failed=false
done
[ "$all_failed" = "true" ] && exit 1 || exit 0
