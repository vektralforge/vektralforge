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
        warn "Buckets faltantes — ejecutando init_users.sh..."
        bash .ci/scripts/init_users.sh "$ENV_FILE"
        break
    fi
done
ok "Buckets MinIO disponibles"

# ── 3. Verificar antlr4 JAR en Spark ─────────────────────────────────────────
log "Verificando JAR antlr4-runtime en Spark..."
if ! docker exec docker-compose-spark-master-1 \
    test -f /opt/spark/jars/antlr4-runtime-4.9.3.jar 2>/dev/null; then
    log "Instalando antlr4-runtime-4.9.3.jar..."
    docker exec -u root docker-compose-spark-master-1 \
        curl -sL -o /opt/spark/jars/antlr4-runtime-4.9.3.jar \
        https://repo1.maven.org/maven2/org/antlr/antlr4-runtime/4.9.3/antlr4-runtime-4.9.3.jar
    docker exec -u root docker-compose-spark-worker-1 \
        curl -sL -o /opt/spark/jars/antlr4-runtime-4.9.3.jar \
        https://repo1.maven.org/maven2/org/antlr/antlr4-runtime/4.9.3/antlr4-runtime-4.9.3.jar \
        2>/dev/null || true
fi
ok "antlr4-runtime-4.9.3.jar presente"

# ── 4. Copiar jobs Spark ──────────────────────────────────────────────────────
log "Sincronizando jobs Spark..."
docker cp spark/jobs/bronze_indicadores.py \
    docker-compose-spark-master-1:/opt/spark/jobs/bronze_indicadores.py 2>/dev/null || true
docker cp spark/jobs/bronze_arclim.py \
    docker-compose-spark-master-1:/opt/spark/jobs/bronze_arclim.py 2>/dev/null || true
ok "Jobs Spark actualizados"

# ── 5. Crear schema Trino ─────────────────────────────────────────────────────
docker exec docker-compose-trino-1 trino --execute \
    "CREATE SCHEMA IF NOT EXISTS delta.bronze WITH (location = 's3://bronze/');" \
    2>/dev/null | grep -v "WARNING\|INFO\|jline" || true

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

    # Disparar
    local ts
    ts=$(date -u +"%Y%m%dT%H%M%S")
    local run_id="${run_prefix}-${ts}"

    docker exec docker-compose-airflow-scheduler-1 \
        airflow dags trigger "$dag_id" --run-id "$run_id" 2>/dev/null \
        | grep -v "^$\|INFO\|WARNING\|DagBag" || true
    ok "Disparado (run_id: $run_id)"

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

    # Post-proceso: registrar tablas en Trino + Superset
    log "Registrando tablas indicadores en Trino..."
    for tabla in indicadores_uf indicadores_dolar indicadores_euro indicadores_utm indicadores_tpm; do
        docker exec docker-compose-trino-1 trino --execute \
            "CALL delta.system.register_table(schema_name => 'bronze', table_name => '${tabla}', table_location => 's3://bronze/${tabla}');" \
            2>/dev/null | grep -v "WARNING\|INFO\|jline" || true
        ok "Trino: $tabla"
    done

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

    log "Registrando tablas ARClim en Trino..."
    for tabla in arclim_indicadores arclim_series; do
        docker exec docker-compose-trino-1 trino --execute \
            "CALL delta.system.register_table(schema_name => 'bronze', table_name => '${tabla}', table_location => 's3://bronze/${tabla}');" \
            2>/dev/null | grep -v "WARNING\|INFO\|jline" || true
        ok "Trino: $tabla"
    done

    log "Conteo ARClim en Trino:"
    docker exec docker-compose-trino-1 trino --execute \
        "SELECT indicador, COUNT(*) as comunas, MIN(anio_serie) as desde, MAX(anio_serie) as hasta
         FROM delta.bronze.arclim_series GROUP BY indicador ORDER BY indicador;" \
        2>/dev/null | grep -v "WARNING\|INFO\|jline\|^$" | sed 's/^/    /' || true

else
    warn "arclim_riesgo_climatico_chile falló — omitiendo registro Trino para ARClim"
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
