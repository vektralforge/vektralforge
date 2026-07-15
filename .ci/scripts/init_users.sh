#!/usr/bin/env bash
# .ci/scripts/init_users.sh
# Inicializa usuarios y recursos del stack leyendo credenciales desde .env
# Ejecutado automáticamente por make dev-reset
set -euo pipefail

ENV_FILE="${1:-infra/docker-compose/.env}"

# Leer variables del .env
get_var() {
    grep "^${1}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'"
}

POSTGRES_USER=$(get_var POSTGRES_USER)
MINIO_ACCESS_KEY=$(get_var MINIO_ACCESS_KEY)
MINIO_SECRET_KEY=$(get_var MINIO_SECRET_KEY)
AF_USER=$(get_var AIRFLOW_ADMIN_USER)
AF_PASS=$(get_var AIRFLOW_ADMIN_PASSWORD)
AF_EMAIL=$(get_var AIRFLOW_ADMIN_EMAIL)
SS_USER=$(get_var SUPERSET_ADMIN_USER)
SS_PASS=$(get_var SUPERSET_ADMIN_PASSWORD)
SS_EMAIL=$(get_var SUPERSET_ADMIN_EMAIL)
OB_TOKEN=$(get_var OPENBAO_TOKEN)

# Valores por defecto
POSTGRES_USER="${POSTGRES_USER:-lakeforge}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-minioadmin}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-minioadmin}"
AF_USER="${AF_USER:-admin}"
AF_PASS="${AF_PASS:-admin}"
AF_EMAIL="${AF_EMAIL:-admin@alephserver.cl}"
SS_USER="${SS_USER:-admin}"
SS_PASS="${SS_PASS:-admin}"
SS_EMAIL="${SS_EMAIL:-admin@alephserver.cl}"
OB_TOKEN="${OB_TOKEN:-dev-root-token}"

# ── PostgreSQL: crear bases de datos ─────────────────────────────────────────
echo "→ Creando bases de datos PostgreSQL..."
docker exec docker-compose-postgres-1 \
    psql -U "$POSTGRES_USER" -c "CREATE DATABASE airflow;" 2>/dev/null || true
docker exec docker-compose-postgres-1 \
    psql -U "$POSTGRES_USER" -c "CREATE DATABASE metastore;" 2>/dev/null || true

# ── MinIO: crear buckets ──────────────────────────────────────────────────────
echo "→ Creando buckets en MinIO..."
docker exec docker-compose-minio-1 sh -c "
    mc alias set local http://localhost:9000 ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY} --quiet 2>/dev/null
    mc mb local/raw          --quiet 2>/dev/null || true
    mc mb local/bronze       --quiet 2>/dev/null || true
    mc mb local/silver       --quiet 2>/dev/null || true
    mc mb local/gold         --quiet 2>/dev/null || true
    mc mb local/checkpoints  --quiet 2>/dev/null || true
    echo '  Buckets disponibles:'
    mc ls local 2>/dev/null
"

# ── Airflow: crear usuario admin ──────────────────────────────────────────────
echo "→ Creando usuario admin en Airflow ($AF_USER)..."
docker exec docker-compose-airflow-webserver-1 \
    airflow users create \
    --username "$AF_USER" \
    --password "$AF_PASS" \
    --firstname Admin \
    --lastname Lakeforge \
    --role Admin \
    --email "$AF_EMAIL" 2>/dev/null || \
    echo "  (usuario ya existe o Airflow aún iniciando)"

# ── Superset: inicializar y crear usuario admin ───────────────────────────────
echo "→ Inicializando base de datos Superset..."
docker exec docker-compose-superset-1 superset db upgrade 2>/dev/null || true

echo "→ Creando usuario admin en Superset ($SS_USER)..."
docker exec docker-compose-superset-1 \
    superset fab create-admin \
    --username "$SS_USER" \
    --firstname Admin \
    --lastname Lakeforge \
    --email "$SS_EMAIL" \
    --password "$SS_PASS" 2>/dev/null || \
    echo "  (usuario ya existe o Superset aún iniciando)"

echo "→ Inicializando roles Superset..."
docker exec docker-compose-superset-1 superset init 2>/dev/null || true

# ── Resumen ───────────────────────────────────────────────────────────────────
echo ""
echo "  ✓ Stack inicializado correctamente"
echo ""
printf "  %-10s %-26s %-15s %s\n" "Servicio" "URL" "Usuario" "Password"
printf "  %-10s %-26s %-15s %s\n" "--------" "------------------------" "-------" "--------"
printf "  %-10s %-26s %-15s %s\n" "Airflow"  "http://localhost:8090" "$AF_USER"          "$AF_PASS"
printf "  %-10s %-26s %-15s %s\n" "Superset" "http://localhost:8088" "$SS_USER"          "$SS_PASS"
printf "  %-10s %-26s %-15s %s\n" "MinIO"    "http://localhost:9001" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY"
printf "  %-10s %-26s %-15s %s\n" "Trino"    "http://localhost:8081" "trino"             "(sin password)"
printf "  %-10s %-26s %-15s %s\n" "OpenBao"  "http://localhost:8200" "token:"            "$OB_TOKEN"
printf "  %-10s %-26s %-15s %s\n" "Spark"    "http://localhost:8082" "(sin auth)"        ""
printf "  %-10s %-26s %-15s %s\n" "Marquez"  "http://localhost:3000" "(sin auth)"        ""
echo ""
echo "  Buckets MinIO: raw/ bronze/ silver/ gold/ checkpoints/"
echo "  Datos de ejemplo: make dev-load-example"
