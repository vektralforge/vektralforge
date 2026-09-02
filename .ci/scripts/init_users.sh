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

# ── Paso de secretos a los contenedores ──────────────────────────────────────
#
# `docker exec -e VAR=valor` pone el valor en la línea de comandos del proceso
# DEL HOST: lo ve cualquier `ps` de la máquina, sin entrar en ningún contenedor.
# Con --env-file solo viaja la ruta de un archivo, creado con permisos 600 en un
# directorio 700 y borrado al salir.
#
# Alcance honesto: dentro del contenedor el comando final sigue recibiendo la
# clave como argumento —ni `airflow users create`, ni `superset fab create-admin`
# ni `mc alias set` la aceptan de otra forma—, así que sigue apareciendo en el
# `ps` de ESE contenedor mientras dura el comando. Lo que se cierra es la
# exposición en el host, que es la amplia.
DIR_SECRETOS=$(mktemp -d)
chmod 700 "$DIR_SECRETOS"
trap 'rm -rf "$DIR_SECRETOS"' EXIT

# Formato de --env-file: una línea NOMBRE=valor, sin comillas, el valor literal
# hasta el fin de línea.
archivo_env() {
    local nombre="$1"
    shift
    local archivo="$DIR_SECRETOS/$nombre"
    printf '%s\n' "$@" > "$archivo"
    chmod 600 "$archivo"
    printf '%s' "$archivo"
}

C_POSTGRES=docker-compose-postgres-1
C_MINIO=docker-compose-minio-1
C_AIRFLOW=docker-compose-airflow-webserver-1
C_SUPERSET=docker-compose-superset-1

step_failed() {
    echo "  ✗ $1"
    FAILURES=$((FAILURES + 1))
}

# ── Pasos ────────────────────────────────────────────────────────────────────
#
# Cada paso es una función y se invoca por separado. Antes era un guion lineal, y
# `load_example.sh` lo ejecutaba ENTERO para arreglar una sola cosa: los buckets
# de MinIO. Eso hacía que cargar datos de ejemplo recreara de paso los usuarios
# admin y reinicializara los roles de Superset —idempotente, pero nadie lo pedía—
# y que el banner apareciera al final de un comando que no lo necesita.
#
# La condición tampoco correspondía a la acción: se comprobaban los buckets y se
# ejecutaban los siete pasos, mientras que un admin de Airflow desaparecido no
# reparaba nada porque esa rama no se activaba.

paso_bases() {
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
}

paso_buckets() {
    # ── MinIO ────────────────────────────────────────────────────────────────────
    echo "→ Creando buckets en MinIO..."
    if out=$(docker exec --env-file "$(archivo_env minio "MC_USER=$MINIO_USER" "MC_PASS=$MINIO_PASS")" \
        "$C_MINIO" sh -c '
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
}

# `superset db upgrade` va aquí y no en un paso propio porque `fab create-admin`
# necesita el esquema: separarlos solo permitiría invocarlos en el orden que
# falla.
paso_usuarios() {
    # ── Airflow ──────────────────────────────────────────────────────────────────
    # En Airflow 3 la gestión de usuarios depende del auth manager configurado:
    # `airflow users` solo existe con el proveedor FAB instalado. Con
    # SimpleAuthManager los usuarios se declaran por configuración.
    echo "→ Creando usuario admin en Airflow ($AF_USER)..."
    if docker exec "$C_AIRFLOW" airflow users list >/dev/null 2>&1; then
        if out=$(docker exec --env-file "$(archivo_env airflow "CLAVE_ADMIN=$AF_PASS")" \
            "$C_AIRFLOW" sh -c '
                airflow users create \
                    --username "$1" --password "$CLAVE_ADMIN" \
                    --firstname Admin --lastname VektralForge \
                    --role Admin --email "$2"
            ' _ "$AF_USER" "$AF_EMAIL" 2>&1); then
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
    if out=$(docker exec --env-file "$(archivo_env superset "CLAVE_ADMIN=$SS_PASS")" \
        "$C_SUPERSET" sh -c '
            superset fab create-admin \
                --username "$1" --firstname Admin --lastname VektralForge \
                --email "$2" --password "$CLAVE_ADMIN"
        ' _ "$SS_USER" "$SS_EMAIL" 2>&1); then
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
}

paso_resumen() {
    # ── Resumen ──────────────────────────────────────────────────────────────────
    echo ""
    if [ "$FAILURES" -eq 0 ]; then
        echo "  ✓ Stack inicializado correctamente"
    else
        echo "  ⚠ Stack inicializado con $FAILURES paso(s) fallido(s)"
    fi
    echo ""
}

paso_banner() {
    # El banner NO imprime contraseñas. Antes las imprimía las cinco, y eso es
    # exactamente lo que hace fácil filtrarlas: basta pegar la salida de un `make`
    # en un issue, un chat o una captura de pantalla para publicarlas todas. Se
    # muestra el NOMBRE de la variable; el valor lo lee quien lo necesite.
    printf "  %-10s %-26s %-15s %s\n" "Servicio" "URL" "Usuario" "Contraseña"
    printf "  %-10s %-26s %-15s %s\n" "--------" "-------------------------" "---------------" "-------------------------"
    printf "  %-10s %-26s %-15s %s\n" "Airflow"  "http://localhost:8090" "$AF_USER"    "\$AIRFLOW_ADMIN_PASSWORD"
    printf "  %-10s %-26s %-15s %s\n" "Superset" "http://localhost:8088" "$SS_USER"    "\$SUPERSET_ADMIN_PASSWORD"
    printf "  %-10s %-26s %-15s %s\n" "MinIO"    "http://localhost:9001" "$MINIO_USER" "\$MINIO_ROOT_PASSWORD"
    printf "  %-10s %-26s %-15s %s\n" "OpenBao"  "http://localhost:8200" "token:"      "\$OPENBAO_TOKEN"
    printf "  %-10s %-26s %-15s %s\n" "Trino"    "http://localhost:8081" "trino"       "sin autenticación"
    printf "  %-10s %-26s %-15s %s\n" "Spark"    "http://localhost:8082" "-"           "sin autenticación"
    printf "  %-10s %-26s %-15s %s\n" "Marquez"  "http://localhost:3000" "-"           "sin autenticación"
    echo ""
    echo "  Las contraseñas viven en $ENV_FILE (permisos 600) y no se imprimen."
    echo "  Para leer una:"
    echo "      grep '^AIRFLOW_ADMIN_PASSWORD=' $ENV_FILE | cut -d= -f2-"
    echo ""
    echo "  Trino, Spark y Marquez no piden credenciales: cualquiera que alcance"
    echo "  esos puertos entra. Por eso el .env fija BIND_HOST=127.0.0.1."
    echo ""
    echo "  Buckets MinIO: raw/ bronze/ silver/ gold/ checkpoints/"
    echo "  Datos de ejemplo: make dev-load-example"
    echo ""
}

# ── Despacho ─────────────────────────────────────────────────────────────────
# El primer argumento sigue siendo el .env, como antes. El segundo elige qué
# hacer; sin él, todo.
case "${SUBCOMANDO:=${2:-todo}}" in
    bases)    paso_bases ;;
    buckets)  paso_buckets ;;
    usuarios) paso_usuarios ;;
    banner)   paso_banner ;;
    todo)
        paso_bases
        paso_buckets
        paso_usuarios
        paso_resumen
        paso_banner
        ;;
    *)
        echo "  ✗ Subcomando desconocido: $SUBCOMANDO" >&2
        echo "    Usa: bases | buckets | usuarios | banner | todo" >&2
        exit 1
        ;;
esac

exit "$FAILURES"
