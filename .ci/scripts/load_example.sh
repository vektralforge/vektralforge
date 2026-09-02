#!/usr/bin/env bash
# .ci/scripts/load_example.sh
# Carga datos de ejemplo después de make dev-reset o make dev-reset-hard
#
# Diseño: cada DAG es independiente — si uno falla, los demás continúan.
# Al final se muestra resumen de qué tuvo éxito y qué falló.
set -uo pipefail

ENV_FILE="${1:-infra/docker-compose/.env}"
TIMEOUT=300
INTERVAL=10

# Registro de resultados por DAG
declare -A DAG_STATUS

log()     { echo "→ $*"; }
ok()      { echo "  ✓ $*"; }
warn()    { echo "  ⚠ $*"; }
fail_msg(){ echo "  ✗ $*"; }

# Esperar que un DAG complete — task por task
# Retorna 0 si todo éxito, 1 si algún task falló
wait_dag() {
    local dag_id="$1" run_id="$2"
    shift 2
    local tasks=("$@")
    local elapsed=0

    for task in "${tasks[@]}"; do
        echo "    Esperando: $task"
        local task_elapsed=0
        while [ $task_elapsed -lt $TIMEOUT ]; do
            sleep $INTERVAL
            task_elapsed=$((task_elapsed + INTERVAL))
            elapsed=$((elapsed + INTERVAL))
            local state
            state=$(docker exec docker-compose-airflow-scheduler-1 \
                airflow tasks state "$dag_id" "$task" "$run_id" 2>/dev/null \
                | tail -1 | tr -d '[:space:]')
            echo "      [${elapsed}s] $task → ${state:-pendiente}"
            if [ "$state" = "success" ]; then
                ok "$task completado"
                break
            elif [ "$state" = "failed" ] || [ "$state" = "upstream_failed" ]; then
                fail_msg "$task falló"
                return 1
            elif [ $task_elapsed -ge $TIMEOUT ]; then
                fail_msg "$task no completó en ${TIMEOUT}s"
                return 1
            fi
        done
    done
    return 0
}

# ── 1. Verificar stack ────────────────────────────────────────────────────────
log "Verificando stack..."
stack_ok=true
for s in airflow-webserver airflow-scheduler spark-master minio trino superset postgres; do
    st=$(docker inspect --format='{{.State.Status}}' "docker-compose-${s}-1" 2>/dev/null || echo "missing")
    if [ "$st" != "running" ]; then
        fail_msg "Servicio $s no está corriendo. Ejecuta: make dev-up"
        stack_ok=false
    fi
done
[ "$stack_ok" = "true" ] || { echo "✗ Stack incompleto — abortando"; exit 1; }
ok "Stack operativo"

# ── 2. Verificar buckets ──────────────────────────────────────────────────────
log "Verificando buckets MinIO..."
for b in raw bronze silver gold checkpoints; do
    if ! docker exec docker-compose-minio-1 mc ls "local/$b" &>/dev/null; then
        warn "Buckets faltantes — creándolos..."
        # Solo los buckets. Antes se llamaba a init_users.sh entero, que además
        # recreaba los usuarios admin y reinicializaba los roles de Superset:
        # efectos que nadie pide al cargar datos de ejemplo.
        bash .ci/scripts/init_users.sh "$ENV_FILE" buckets
        break
    fi
done
ok "Buckets MinIO disponibles"

# Aquí había un bloque que descargaba antlr4-runtime-4.9.3.jar desde
# repo1.maven.org, sin hash ni firma, y lo metía como root en /opt/spark/jars de
# master y worker. No hacía falta y hacía daño: la imagen de Spark ya trae
# antlr4-runtime-4.13.1.jar (spark 4.0.x, 4.1.x y 4.2.x fijan antlr4.version en
# 4.13.1 en su pom). Como el `test -f` buscaba la 4.9.3, nunca acertaba, así que
# la bajaba en cada ejecución y dejaba dos runtimes de antlr en el classpath.
# Si algún día vuelve a fallar el parser de SQL, la respuesta no es descargar un
# JAR a mano: es mirar qué versión trae la imagen.

# ── 3. Copiar jobs Spark ──────────────────────────────────────────────────────
log "Sincronizando jobs Spark..."
docker cp spark/jobs/bronze_indicadores.py \
    docker-compose-spark-master-1:/opt/spark/jobs/bronze_indicadores.py 2>/dev/null || true
docker cp spark/jobs/bronze_arclim.py \
    docker-compose-spark-master-1:/opt/spark/jobs/bronze_arclim.py 2>/dev/null || true
ok "Jobs Spark actualizados"

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
        warn "Run activo detectado — usando: $run_id"
    else
        local ts
        ts=$(date -u +"%Y%m%dT%H%M%S")
        run_id="${run_prefix}-${ts}"
        docker exec docker-compose-airflow-scheduler-1 \
            airflow dags trigger "$dag_id" --run-id "$run_id" 2>/dev/null \
            | grep -v "^$\|INFO\|WARNING\|DagBag" || true
        ok "Disparado (run_id: $run_id)"
    fi

    # Esperar
    if wait_dag "$dag_id" "$run_id" "${tasks[@]}"; then
        DAG_STATUS[$dag_id]="✓ SUCCESS"
        return 0
    else
        DAG_STATUS[$dag_id]="✗ FAILED — ver http://localhost:8090/dags/${dag_id}/grid"
        warn "$dag_id falló — continuando con el siguiente DAG"
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
    log "Tablas de indicadores visibles en Trino:"
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
    ok "Vista indicadores_todos creada"

    log "Conteo indicadores en Trino:"
    docker exec docker-compose-trino-1 trino --execute \
        "SELECT indicador, COUNT(*) as filas FROM delta.bronze.indicadores_todos GROUP BY indicador ORDER BY indicador;" \
        2>/dev/null | grep -v "WARNING\|INFO\|jline\|^$" | sed 's/^/    /' || true

    log "Configurando dashboard Superset..."
    docker cp superset/dashboards/setup_superset_dashboard.py \
        docker-compose-superset-1:/tmp/setup_superset_dashboard.py 2>/dev/null
    docker exec docker-compose-superset-1 \
        bash -c "cd /app && python3 -c \"
import sys; sys.path.insert(0, '/app')
from superset.app import create_app
app = create_app()
with app.app_context():
    exec(open('/tmp/setup_superset_dashboard.py').read())
\"" 2>/dev/null | grep -E "✓|✗|⚠|====" || true

else
    warn "indicadores_financieros_chile falló — omitiendo Trino y Superset para este DAG"
fi

# ════════════════════════════════════════════════════════════════════════════════
# DAG 2: arclim_riesgo_climatico_chile
# ════════════════════════════════════════════════════════════════════════════════
if load_dag "arclim_riesgo_climatico_chile" "dev-load-arclim" \
    "extract_arclim" "transform_bronze" "validar_bronze"; then

    log "Tablas ARClim visibles en Trino:"
    docker exec docker-compose-trino-1 trino --execute \
        "SHOW TABLES FROM delta.bronze LIKE 'arclim_%';" \
        2>/dev/null | grep -v "WARNING\|INFO\|jline\|^$" | sed 's/^/    /' || true

    log "Conteo ARClim en Trino:"
    docker exec docker-compose-trino-1 trino --execute \
        "SELECT indicador, COUNT(*) as comunas, MIN(anio_serie) as desde, MAX(anio_serie) as hasta
         FROM delta.bronze.arclim_series GROUP BY indicador ORDER BY indicador;" \
        2>/dev/null | grep -v "WARNING\|INFO\|jline\|^$" | sed 's/^/    /' || true

    log "Configurando dashboard ARClim en Superset..."
    docker cp superset/dashboards/setup_superset_arclim.py \
        docker-compose-superset-1:/tmp/setup_superset_arclim.py 2>/dev/null
    docker exec docker-compose-superset-1 \
        bash -c "cd /app && python3 -c \"
import sys; sys.path.insert(0, '/app')
from superset.app import create_app
app = create_app()
with app.app_context():
    exec(open('/tmp/setup_superset_arclim.py').read())
\"" 2>/dev/null | grep -E "✓|✗|⚠|====" || true

else
    warn "arclim_riesgo_climatico_chile falló — omitiendo Trino y dashboard ARClim"
fi

# ── Resumen final ─────────────────────────────────────────────────────────────
echo ""
echo "  ══════════════════════════════════════════════════"
echo "  Resumen de carga de ejemplos"
echo "  ══════════════════════════════════════════════════"
for dag_id in "${!DAG_STATUS[@]}"; do
    echo "    ${DAG_STATUS[$dag_id]}  ($dag_id)"
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
    [[ "${DAG_STATUS[$dag_id]}" == "✓"* ]] && all_failed=false
done
[ "$all_failed" = "true" ] && exit 1 || exit 0
