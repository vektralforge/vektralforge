#!/usr/bin/env bash
# .ci/scripts/load_example.sh
# Carga datos de ejemplo después de make dev-reset o make dev-reset-hard
#
# Pasos:
#   1. Verifica stack y buckets MinIO
#   2. Instala antlr4-runtime JAR en Spark si falta
#   3. DAG indicadores_financieros_chile → bronze + Trino + Superset
#   4. DAG arclim_riesgo_climatico_chile → bronze + Trino
set -euo pipefail

ENV_FILE="${1:-infra/docker-compose/.env}"
TIMEOUT=300
INTERVAL=10

log()  { echo "→ $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*"; }
fail() { echo "  ✗ $*"; exit 1; }

# Obtener estado de un task para un DAG y run_id dados
task_state() {
    local dag_id="$1" run_id="$2" task="$3"
    docker exec docker-compose-airflow-scheduler-1 \
        airflow tasks state "$dag_id" "$task" "$run_id" 2>/dev/null \
        | tail -1 | tr -d '[:space:]'
}

# Esperar que un DAG complete — task por task
wait_dag() {
    local dag_id="$1" run_id="$2"
    shift 2
    local tasks=("$@")
    local elapsed=0

    log "Monitoreando $dag_id..."
    for task in "${tasks[@]}"; do
        echo "    Esperando: $task"
        local task_elapsed=0
        while [ $task_elapsed -lt $TIMEOUT ]; do
            sleep $INTERVAL
            task_elapsed=$((task_elapsed + INTERVAL))
            elapsed=$((elapsed + INTERVAL))
            local state
            state=$(task_state "$dag_id" "$run_id" "$task")
            echo "      [${elapsed}s] $task → ${state:-pendiente}"
            if [ "$state" = "success" ]; then
                ok "$task completado"
                break
            elif [ "$state" = "failed" ] || [ "$state" = "upstream_failed" ]; then
                fail "$task falló. Ver http://localhost:8090"
            elif [ $task_elapsed -ge $TIMEOUT ]; then
                fail "$task no completó en ${TIMEOUT}s"
            fi
        done
    done
}

# ── 1. Verificar stack ────────────────────────────────────────────────────────
log "Verificando stack..."
for s in airflow-webserver airflow-scheduler spark-master minio trino superset postgres; do
    st=$(docker inspect --format='{{.State.Status}}' "docker-compose-${s}-1" 2>/dev/null || echo "missing")
    [ "$st" = "running" ] || fail "Servicio $s no está corriendo. Ejecuta: make dev-up"
done
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

# ── 4. Copiar jobs Spark al contenedor ────────────────────────────────────────
log "Sincronizando jobs Spark..."
docker cp spark/jobs/bronze_indicadores.py \
    docker-compose-spark-master-1:/opt/spark/jobs/bronze_indicadores.py 2>/dev/null || true
docker cp spark/jobs/bronze_arclim.py \
    docker-compose-spark-master-1:/opt/spark/jobs/bronze_arclim.py 2>/dev/null || true
ok "Jobs Spark actualizados"

# ════════════════════════════════════════════════════════════════════════════════
# DAG 1: indicadores_financieros_chile
# ════════════════════════════════════════════════════════════════════════════════
log "═══ DAG 1/2: indicadores_financieros_chile ═══"

docker exec docker-compose-airflow-scheduler-1 \
    airflow dags unpause indicadores_financieros_chile 2>/dev/null \
    | grep -v "^$\|INFO\|WARNING\|DagBag" || true
ok "DAG indicadores activado"

TIMESTAMP=$(date -u +"%Y%m%dT%H%M%S")
RUN_IND="dev-load-example-ind-${TIMESTAMP}"

docker exec docker-compose-airflow-scheduler-1 \
    airflow dags trigger indicadores_financieros_chile \
    --run-id "$RUN_IND" 2>/dev/null \
    | grep -v "^$\|INFO\|WARNING\|DagBag" || true
ok "DAG indicadores en cola..."

wait_dag "indicadores_financieros_chile" "$RUN_IND" \
    "extract_indicadores" "transform_bronze" "validar_bronze"

# Verificar bronze indicadores
archivos=$(docker exec docker-compose-minio-1 \
    mc ls local/bronze/ --recursive 2>/dev/null | grep -c ".parquet" || echo "0")
[ "$archivos" -gt 0 ] || fail "Sin Parquet en bronze/ para indicadores"
ok "bronze/ tiene $archivos archivos Parquet"

# Registrar tablas indicadores en Trino
log "Registrando tablas indicadores en Trino..."
docker exec docker-compose-trino-1 trino --execute \
    "CREATE SCHEMA IF NOT EXISTS delta.bronze WITH (location = 's3://bronze/');" \
    2>/dev/null | grep -v "WARNING\|INFO\|jline" || true

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

# Dashboard Superset
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
\"" 2>/dev/null | grep -E "✓|✗|⚠|Chart|Dataset|Dashboard|====" || true

# ════════════════════════════════════════════════════════════════════════════════
# DAG 2: arclim_riesgo_climatico_chile
# ════════════════════════════════════════════════════════════════════════════════
log "═══ DAG 2/2: arclim_riesgo_climatico_chile ═══"

docker exec docker-compose-airflow-scheduler-1 \
    airflow dags unpause arclim_riesgo_climatico_chile 2>/dev/null \
    | grep -v "^$\|INFO\|WARNING\|DagBag" || true
ok "DAG ARClim activado"

TIMESTAMP2=$(date -u +"%Y%m%dT%H%M%S")
RUN_ARCLIM="dev-load-example-arclim-${TIMESTAMP2}"

docker exec docker-compose-airflow-scheduler-1 \
    airflow dags trigger arclim_riesgo_climatico_chile \
    --run-id "$RUN_ARCLIM" 2>/dev/null \
    | grep -v "^$\|INFO\|WARNING\|DagBag" || true
ok "DAG ARClim en cola..."

wait_dag "arclim_riesgo_climatico_chile" "$RUN_ARCLIM" \
    "extract_arclim" "transform_bronze" "validar_bronze"

# Registrar tablas ARClim en Trino
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

# ── Resumen final ─────────────────────────────────────────────────────────────
echo ""
echo "  ✓ Datos de ejemplo cargados exitosamente"
echo ""
echo "  DAG 1 — Indicadores financieros Chile (mindicador.cl)"
echo "    Tablas Trino: indicadores_uf, dolar, euro, utm, tpm + vista todos"
echo ""
echo "  DAG 2 — Riesgo climático Chile (ARClim MMA)"
echo "    Tablas Trino: arclim_indicadores (69), arclim_series (3,900 filas)"
echo ""
echo "  Airflow   → http://localhost:8090"
echo "  Trino     → http://localhost:8081"
echo "  MinIO     → http://localhost:9001"
echo "  Marquez   → http://localhost:3000  (linaje automático)"
echo "  Dashboard → http://localhost:8088/superset/dashboard/indicadores-financieros-chile/"
echo ""
