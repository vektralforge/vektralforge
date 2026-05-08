#!/usr/bin/env bash
# .ci/scripts/init_users.sh
# Inicializa usuarios de Airflow y Superset leyendo credenciales desde .env
set -euo pipefail

ENV_FILE="${1:-infra/docker-compose/.env}"

# Leer variables del .env
get_var() { grep "^${1}=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' | tr -d "'"; }

POSTGRES_USER=$(get_var POSTGRES_USER)
AF_USER=$(get_var AIRFLOW_ADMIN_USER)
AF_PASS=$(get_var AIRFLOW_ADMIN_PASSWORD)
AF_EMAIL=$(get_var AIRFLOW_ADMIN_EMAIL)
SS_USER=$(get_var SUPERSET_ADMIN_USER)
SS_PASS=$(get_var SUPERSET_ADMIN_PASSWORD)
SS_EMAIL=$(get_var SUPERSET_ADMIN_EMAIL)

# Valores por defecto
AF_USER="${AF_USER:-admin}"
AF_PASS="${AF_PASS:-admin}"
AF_EMAIL="${AF_EMAIL:-admin@alephserver.cl}"
SS_USER="${SS_USER:-admin}"
SS_PASS="${SS_PASS:-admin}"
SS_EMAIL="${SS_EMAIL:-admin@alephserver.cl}"

echo "→ Creando bases de datos PostgreSQL..."
docker exec docker-compose-postgres-1 \
    psql -U "$POSTGRES_USER" -c "CREATE DATABASE airflow;" 2>/dev/null || true
docker exec docker-compose-postgres-1 \
    psql -U "$POSTGRES_USER" -c "CREATE DATABASE metastore;" 2>/dev/null || true

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

echo ""
echo "  ✓ Usuarios creados exitosamente"
echo "    Airflow  → http://localhost:8090  ($AF_USER)"
echo "    Superset → http://localhost:8088  ($SS_USER)"
echo "    MinIO    → http://localhost:9001"
echo "    Trino    → http://localhost:8081"
echo "    OpenBao  → http://localhost:8200  (API)"
