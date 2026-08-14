#!/usr/bin/env bash
# .ci/scripts/init_users.sh
#
# Inicializa usuarios y recursos del stack leyendo credenciales desde .env.
# Lo ejecuta `make dev-reset`.
#
# Cada paso reporta si tuvo éxito. Un fallo no detiene el resto —los pasos son
# independientes— pero sí se refleja en el código de salida, para que el
# problema no pase inadvertido.

set -uo pipefail

ENV_FILE="${1:-infra/docker-compose/.env}"
FAILURES=0

if [ ! -f "$ENV_FILE" ]; then
    echo "  ✗ No existe $ENV_FILE" >&2
    exit 1
fi

# ── Lectura del .env ─────────────────────────────────────────────────────────
# Descarta comentarios al final de línea y comillas envolventes.
get_var() {
    grep -E "^${1}=" "$ENV_FILE" 2>/dev/null \
        | head -1 \
        | cut -d= -f2- \
        | sed -e 's/[[:space:]]\{1,\}#.*$//' -e 's/^["'"'"']//' -e 's/["'"'"']$//' \
        | tr -d '\r'
}

POSTGRES_USER=$(get_var POSTGRES_USER)
MINIO_USER=$(get_var MINIO_ROOT_USER)
MINIO_PASS=$(get_var MINIO_ROOT_PASSWORD)
AF_USER=$(get_var AIRFLOW_ADMIN_USER)
AF_PASS=$(get_var AIRFLOW_ADMIN_PASSWORD)
AF_EMAIL=$(get_var AIRFLOW_ADMIN_EMAIL)
SS_USER=$(get_var SUPERSET_ADMIN_USER)
SS_PASS=$(get_var SUPERSET_ADMIN_PASSWORD)
SS_EMAIL=$(get_var SUPERSET_ADMIN_EMAIL)
OB_TOKEN=$(get_var OPENBAO_TOKEN)

POSTGRES_USER="${POSTGRES_USER:-vektralforge}"
AF_USER="${AF_USER:-admin}"
AF_EMAIL="${AF_EMAIL:-admin@example.com}"
SS_USER="${SS_USER:-admin}"
SS_EMAIL="${SS_EMAIL:-admin@example.com}"
OB_TOKEN="${OB_TOKEN:-dev-root-token}"

# Sin valores por defecto: una credencial silenciosamente incorrecta es peor
# que un error inmediato.
check_required() {
    [ -n "$2" ] || { echo "  ✗ Falta $1 en $ENV_FILE" >&2; exit 1; }
}
check_required MINIO_ROOT_USER "$MINIO_USER"
check_required MINIO_ROOT_PASSWORD "$MINIO_PASS"  # pragma: allowlist secret
check_required AIRFLOW_ADMIN_PASSWORD "$AF_PASS"  # pragma: allowlist secret
check_required SUPERSET_ADMIN_PASSWORD "$SS_PASS"  # pragma: allowlist secret

C_POSTGRES=docker-compose-postgres-1
C_MINIO=docker-compose-minio-1
C_AIRFLOW=docker-compose-airflow-webserver-1
C_SUPERSET=docker-compose-superset-1

step_failed() {
    echo "  ✗ $1"
    FAILURES=$((FAILURES + 1))
}

# ── PostgreSQL ───────────────────────────────────────────────────────────────
# init-multiple-dbs.sh crea las bases al inicializar el volumen. Esto es una
# red de seguridad para volúmenes creados antes de añadir alguna base.
echo "→ Verificando bases de datos PostgreSQL..."
for db in airflow metastore marquez superset; do
    if docker exec "$C_POSTGRES" psql -U "$POSTGRES_USER" -lqt 2>/dev/null \
        | cut -d\| -f1 | grep -qw "$db"; then
        echo "  · $db"
    else
        if docker exec "$C_POSTGRES" createdb -U "$POSTGRES_USER" "$db" 2>&1; then
            echo "  + $db (creada)"
        else
            step_failed "no se pudo crear la base $db"
        fi
    fi
done

# ── MinIO ────────────────────────────────────────────────────────────────────
echo "→ Creando buckets en MinIO..."
if out=$(docker exec -e MC_USER="$MINIO_USER" -e MC_PASS="$MINIO_PASS" "$C_MINIO" sh -c '
    set -e
    mc alias set local http://localhost:9000 "$MC_USER" "$MC_PASS" --quiet
    for b in raw bronze silver gold checkpoints; do
        mc mb --ignore-existing "local/$b" --quiet
    done
    mc ls local
' 2>&1); then
    echo "$out" | sed 's/^/  /'
else
    step_failed "MinIO: $out"
fi

# ── Airflow ──────────────────────────────────────────────────────────────────
# En Airflow 3 la gestión de usuarios depende del auth manager configurado:
# `airflow users` solo existe con el proveedor FAB instalado. Con
# SimpleAuthManager los usuarios se declaran por configuración.
echo "→ Creando usuario admin en Airflow ($AF_USER)..."
if docker exec "$C_AIRFLOW" airflow users list >/dev/null 2>&1; then
    if out=$(docker exec "$C_AIRFLOW" airflow users create \
        --username "$AF_USER" --password "$AF_PASS" \
        --firstname Admin --lastname VektralForge \
        --role Admin --email "$AF_EMAIL" 2>&1); then
        echo "  ✓ creado"
    elif echo "$out" | grep -qi "already exist"; then
        echo "  · ya existía"
    else
        step_failed "Airflow: $out"
    fi
else
    echo "  · el comando 'airflow users' no está disponible"
    echo "    (Airflow 3 con SimpleAuthManager: los usuarios se definen por"
    echo "     configuración; instala apache-airflow-providers-fab para usar CLI)"
fi

# ── Superset ─────────────────────────────────────────────────────────────────
echo "→ Inicializando Superset..."
if out=$(docker exec "$C_SUPERSET" superset db upgrade 2>&1); then
    echo "  ✓ esquema actualizado"
else
    step_failed "superset db upgrade: $(echo "$out" | tail -3)"
fi

echo "→ Creando usuario admin en Superset ($SS_USER)..."
if out=$(docker exec "$C_SUPERSET" superset fab create-admin \
    --username "$SS_USER" --firstname Admin --lastname VektralForge \
    --email "$SS_EMAIL" --password "$SS_PASS" 2>&1); then
    echo "  ✓ creado"
elif echo "$out" | grep -qiE "already exists|Error: .*duplicate"; then
    echo "  · ya existía"
else
    step_failed "Superset: $(echo "$out" | tail -3)"
fi

echo "→ Inicializando roles de Superset..."
if out=$(docker exec "$C_SUPERSET" superset init 2>&1); then
    echo "  ✓ roles inicializados"
else
    step_failed "superset init: $(echo "$out" | tail -3)"
fi

# ── Resumen ──────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" -eq 0 ]; then
    echo "  ✓ Stack inicializado correctamente"
else
    echo "  ⚠ Stack inicializado con $FAILURES paso(s) fallido(s)"
fi
echo ""
printf "  %-10s %-26s %-15s %s\n" "Servicio" "URL" "Usuario" "Password"
printf "  %-10s %-26s %-15s %s\n" "--------" "-------------------------" "---------------" "--------"
printf "  %-10s %-26s %-15s %s\n" "Airflow"  "http://localhost:8090" "$AF_USER"    "$AF_PASS"
printf "  %-10s %-26s %-15s %s\n" "Superset" "http://localhost:8088" "$SS_USER"    "$SS_PASS"
printf "  %-10s %-26s %-15s %s\n" "MinIO"    "http://localhost:9001" "$MINIO_USER" "$MINIO_PASS"
printf "  %-10s %-26s %-15s %s\n" "Trino"    "http://localhost:8081" "trino"       "(sin password)"
printf "  %-10s %-26s %-15s %s\n" "OpenBao"  "http://localhost:8200" "token:"      "$OB_TOKEN"
printf "  %-10s %-26s %-15s %s\n" "Spark"    "http://localhost:8082" "(sin auth)"  ""
printf "  %-10s %-26s %-15s %s\n" "Marquez"  "http://localhost:3000" "(sin auth)"  ""
echo ""
echo "  Buckets MinIO: raw/ bronze/ silver/ gold/ checkpoints/"
echo "  Datos de ejemplo: make dev-load-example"
echo ""

exit "$FAILURES"
