#!/usr/bin/env bash
# .ci/scripts/init_users.sh
#
# Inicializa usuarios y recursos del stack leyendo credenciales desde .env.
# Lo ejecuta `make dev-reset`.
#
# Cada paso reporta si tuvo éxito. Un fallo no detiene el resto —los pasos son
# independientes— pero sí se refleja en el código de salida, para que el
# problema no pase inadvertido.
#
# Log: mismo formato [INFO]/[WARN]/[ERROR] en inglés que el resto de los
# scripts. step_failed() usa [WARN] porque no detiene el script — solo se
# cuenta en FAILURES, igual que antes.

set -uo pipefail

ENV_FILE="${1:-infra/docker-compose/.env}"
FAILURES=0

if [ ! -f "$ENV_FILE" ]; then
    echo "[ERROR] $ENV_FILE not found" >&2
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
S3_ROOT_USER_VAL=$(get_var S3_ROOT_USER)
S3_ROOT_PASS_VAL=$(get_var S3_ROOT_PASSWORD)
AF_USER=$(get_var AIRFLOW_ADMIN_USER)
AF_PASS=$(get_var AIRFLOW_ADMIN_PASSWORD)
AF_EMAIL=$(get_var AIRFLOW_ADMIN_EMAIL)
SS_USER=$(get_var SUPERSET_ADMIN_USER)
SS_PASS=$(get_var SUPERSET_ADMIN_PASSWORD)
SS_EMAIL=$(get_var SUPERSET_ADMIN_EMAIL)
OB_TOKEN=$(get_var OPENBAO_TOKEN)

# Cuentas de servicio del object store. Los identificadores no son secretos;
# llevan valor por defecto para que un .env antiguo no rompa el arranque.
PIPELINE_KEY=$(get_var S3_PIPELINE_ACCESS_KEY)
PIPELINE_SECRET=$(get_var S3_PIPELINE_SECRET_KEY)
HIVE_KEY=$(get_var S3_HIVE_ACCESS_KEY)
HIVE_SECRET=$(get_var S3_HIVE_SECRET_KEY)
TRINO_KEY=$(get_var S3_TRINO_ACCESS_KEY)
TRINO_SECRET=$(get_var S3_TRINO_SECRET_KEY)
PIPELINE_KEY="${PIPELINE_KEY:-vf-pipeline}"
HIVE_KEY="${HIVE_KEY:-vf-hive}"
TRINO_KEY="${TRINO_KEY:-vf-trino}"

POSTGRES_USER="${POSTGRES_USER:-vektralforge}"
AF_USER="${AF_USER:-admin}"
AF_EMAIL="${AF_EMAIL:-admin@example.com}"
SS_USER="${SS_USER:-admin}"
SS_EMAIL="${SS_EMAIL:-admin@example.com}"
OB_TOKEN="${OB_TOKEN:-dev-root-token}"

# Sin valores por defecto: una credencial silenciosamente incorrecta es peor
# que un error inmediato.
check_required() {
    [ -n "$2" ] || { echo "[ERROR] $1 missing in $ENV_FILE" >&2; exit 1; }
}
check_required S3_ROOT_USER "$S3_ROOT_USER_VAL"
check_required S3_ROOT_PASSWORD "$S3_ROOT_PASS_VAL"  # pragma: allowlist secret
check_required AIRFLOW_ADMIN_PASSWORD "$AF_PASS"  # pragma: allowlist secret
check_required SUPERSET_ADMIN_PASSWORD "$SS_PASS"  # pragma: allowlist secret
check_required S3_PIPELINE_SECRET_KEY "$PIPELINE_SECRET"  # pragma: allowlist secret
check_required S3_HIVE_SECRET_KEY "$HIVE_SECRET"  # pragma: allowlist secret
check_required S3_TRINO_SECRET_KEY "$TRINO_SECRET"  # pragma: allowlist secret

# ── Paso de secretos a los contenedores ──────────────────────────────────────
#
# `docker exec -e VAR=valor` pone el valor en la línea de comandos del proceso
# DEL HOST: lo ve cualquier `ps` de la máquina, sin entrar en ningún contenedor.
# Con --env-file solo viaja la ruta de un archivo, creado con permisos 600 en un
# directorio 700 y borrado al salir.
#
# Eso cerraba la exposición en el HOST. Dentro del contenedor la clave seguía
# llegando como argumento, y esa frase decía además que no había alternativa:
# «ni airflow users create, ni superset fab create-admin ni mc alias set la
# aceptan de otra forma». Era falso en los tres casos.
#
#   · `airflow users create` sin --password llama a getpass dos veces.
#   · `superset fab create-admin` usa @click.password_option(), que es prompt
#     con confirmación.
#   · `rc alias import /dev/stdin` lee la credencial de la entrada estándar y
#     sustituye a `rc alias set`, que además sondea el endpoint.
#
# Los tres reciben ahora la clave por la TUBERÍA de `docker exec -i`: ni en la
# línea de comandos, ni en el entorno, ni en un archivo dentro del contenedor.
# Solo en el pipe y en la memoria del proceso.
#
# Queda uno, y no tiene salida: `rc admin service-account create` toma el
# secreto como argumento posicional, igual que `mc` lo tomaba en --secret-key.
# Los secretos de las tres cuentas de servicio siguen ahí durante los
# milisegundos que dura el comando, y conviene decirlo entero: `docker top`
# enseña desde el host la línea de comandos de los procesos de dentro, así que
# ese caso concreto tampoco estaba cerrado en el host.
DIR_SECRETOS=$(mktemp -d)
chmod 700 "$DIR_SECRETOS"
trap 'rm -rf "$DIR_SECRETOS"' EXIT

# Formato de --env-file: una línea NOMBRE=valor, sin comillas, el valor literal
# hasta el fin de línea. Lo usa ya solo `crear_cuenta_s3`, que es el único
# paso sin una vía por stdin.
archivo_env() {
    local nombre="$1"
    shift
    local archivo="$DIR_SECRETOS/$nombre"
    printf '%s\n' "$@" > "$archivo"
    chmod 600 "$archivo"
    printf '%s' "$archivo"
}

# `rc alias import` lee un JSON desde un archivo, y `/dev/stdin` vale como
# archivo: es la vía por la que la raíz entra al contenedor sin pasar por argv
# ni por el entorno. Comprobado que al importar NO contacta con el servidor, al
# contrario que `rc alias set`, que sondea el endpoint y falla si todavía no
# responde.
#
# El nombre del alias va DENTRO del JSON —`rc alias import` no lo recibe como
# argumento— y se borra con un trap al terminar cada comando, para no dejar la
# credencial raíz escrita en la configuración del CLI dentro del contenedor.
# RC_CONFIG_DIR la manda a /tmp porque el proceso corre con un UID cuyo HOME no
# es escribible.
#
# Solo hay que escapar la barra invertida y la comilla doble: `make init-env`
# genera claves alfanuméricas, pero un .env escrito a mano puede traer
# cualquier cosa, y un JSON roto daría un error de rc que no señala la causa.
escapar_json() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

json_alias_s3() {
    printf '{"schema_version":1,"aliases":[{"name":"vf","endpoint":"http://localhost:9000","credentials":{"access_key":"%s","secret_key":"%s"},"anonymous":false,"region":"us-east-1","signature":"v4","bucket_lookup":"path","insecure":false}]}\n' \
        "$(escapar_json "$S3_ROOT_USER_VAL")" "$(escapar_json "$S3_ROOT_PASS_VAL")"
}

C_POSTGRES=docker-compose-postgres-1
C_S3=docker-compose-rustfs-1
C_AIRFLOW=docker-compose-airflow-webserver-1
C_SUPERSET=docker-compose-superset-1

step_failed() {
    echo "[WARN]  $1"
    FAILURES=$((FAILURES + 1))
}

# ── Pasos ────────────────────────────────────────────────────────────────────
#
# Cada paso es una función y se invoca por separado. Antes era un guion lineal, y
# `load_example.sh` lo ejecutaba ENTERO para arreglar una sola cosa: los buckets
# del object store. Eso hacía que cargar datos de ejemplo recreara de paso los
# usuarios admin y reinicializara los roles de Superset —idempotente, pero
# nadie lo pedía— y que el banner apareciera al final de un comando que no lo
# necesita.
#
# La condición tampoco correspondía a la acción: se comprobaban los buckets y se
# ejecutaban los siete pasos, mientras que un admin de Airflow desaparecido no
# reparaba nada porque esa rama no se activaba.

paso_bases() {
    # ── PostgreSQL ───────────────────────────────────────────────────────────────
    # init-multiple-dbs.sh crea las bases al inicializar el volumen. Esto es una
    # red de seguridad para volúmenes creados antes de añadir alguna base.
    echo "[INFO]  Checking PostgreSQL databases..."
    for db in airflow metastore marquez superset; do
        if docker exec "$C_POSTGRES" psql -U "$POSTGRES_USER" -lqt 2>/dev/null \
            | cut -d\| -f1 | grep -qw "$db"; then
            echo "[INFO]  $db already exists"
        else
            if docker exec "$C_POSTGRES" createdb -U "$POSTGRES_USER" "$db" 2>&1; then
                echo "[INFO]  $db created"
            else
                step_failed "could not create database $db"
            fi
        fi
    done
}

paso_buckets() {
    # ── Object store ─────────────────────────────────────────────────────────────
    echo "[INFO]  Creating object store buckets..."
    if out=$(json_alias_s3 | docker exec -i "$C_S3" sh -c '
        set -e
        RC_CONFIG_DIR=$(mktemp -d); export RC_CONFIG_DIR
        trap "rc alias remove vf >/dev/null 2>&1; rm -rf \"$RC_CONFIG_DIR\"" EXIT
        rc alias import /dev/stdin --replace --quiet
        for b in raw bronze silver gold checkpoints; do
            rc bucket create "vf/$b" --ignore-existing --quiet
        done
        rc ls vf
    ' 2>&1); then
        echo "$out" | sed 's/^/  /'
    else
        step_failed "object store: $out"
    fi
}

# Crea las cuentas de servicio con las que Airflow, Spark, Hive y Trino entran al
# object store.
#
# Antes los cinco consumidores usaban las credenciales RAÍZ: cualquiera de esos
# contenedores podía borrar todos los buckets, crear usuarios o cambiar
# políticas. Ahora cada uno tiene una cuenta acotada por politica-datos.json, que
# permite operar sobre los objetos de los cinco buckets y nada más.
#
# Las cuentas cuelgan de la raíz y sus permisos son la INTERSECCIÓN de los del
# padre con la política adjunta, que es lo que las acota sin crear usuarios
# adicionales.
#
# Se borra y se recrea en vez de editar: `add` y `rm` son los verbos estables, y
# durante un dev-reset no hay nadie usando la cuenta anterior.
crear_cuenta_s3() {
    local nombre="$1" clave="$2" secreto="$3" out

    # La raíz entra por stdin. El SECRETO de la cuenta de servicio no puede:
    # `rc admin service-account create` lo toma como ARGUMENTO POSICIONAL, igual
    # que `mc admin user svcacct add` lo tomaba en --secret-key, así que sigue
    # viajando por --env-file hasta el entorno del contenedor y de ahí a argv.
    # El residual del §2.10 se queda exactamente donde estaba: el cambio de
    # backend no lo resuelve, y conviene escribirlo en vez de dejar creer que sí.
    #
    # Lo que SÍ desaparece es el usuario padre. `rc` cuelga la cuenta de la
    # identidad del alias cuando se omite --user, así que el nombre de la raíz
    # ya no tiene que entrar en el archivo de entorno.
    if out=$(json_alias_s3 | docker exec -i \
        --env-file "$(archivo_env "svcacct-$nombre" \
              "SVC_KEY=$clave" "SVC_SECRET=$secreto")" \
        "$C_S3" sh -c '
        set -e
        RC_CONFIG_DIR=$(mktemp -d); export RC_CONFIG_DIR
        trap "rc alias remove vf >/dev/null 2>&1; rm -rf \"$RC_CONFIG_DIR\"" EXIT
        rc alias import /dev/stdin --replace --quiet
        if rc admin service-account info vf "$SVC_KEY" >/dev/null 2>&1; then
            rc admin service-account rm vf "$SVC_KEY" >/dev/null
        fi
        rc admin service-account create vf "$SVC_KEY" "$SVC_SECRET" \
            --policy /tmp/politica-datos.json >/dev/null
        ' 2>&1); then
        echo "[INFO]  $clave configured"
    else
        step_failed "account $clave: $(echo "$out" | tail -2)"
    fi
}

paso_cuentas() {
    echo "[INFO]  Creating object store service accounts..."
    local politica="infra/docker-compose/s3/politica-datos.json"

    if [ ! -f "$politica" ]; then
        step_failed "$politica not found"
        return
    fi
    if ! docker cp "$politica" "$C_S3:/tmp/politica-datos.json" >/dev/null 2>&1; then
        step_failed "could not copy the policy to $C_S3"
        return
    fi

    crear_cuenta_s3 pipeline "$PIPELINE_KEY" "$PIPELINE_SECRET"
    crear_cuenta_s3 hive     "$HIVE_KEY"     "$HIVE_SECRET"
    crear_cuenta_s3 trino    "$TRINO_KEY"    "$TRINO_SECRET"
}

# `superset db upgrade` va aquí y no en un paso propio porque `fab create-admin`
# necesita el esquema: separarlos solo permitiría invocarlos en el orden que
# falla.
paso_usuarios() {
    # ── Airflow ──────────────────────────────────────────────────────────────────
    # En Airflow 3 la gestión de usuarios depende del auth manager configurado:
    # `airflow users` solo existe con el proveedor FAB instalado. Con
    # SimpleAuthManager los usuarios se declaran por configuración.
    echo "[INFO]  Creating Airflow admin user ($AF_USER)..."
    if docker exec "$C_AIRFLOW" airflow users list >/dev/null 2>&1; then
        # Sin --password: el CLI llama a getpass dos veces, así que la clave
        # llega por la tubería. `printf` es un builtin de bash, de modo que la
        # clave tampoco aparece en argv de ningún proceso del HOST.
        if out=$(printf '%s\n%s\n' "$AF_PASS" "$AF_PASS" | docker exec -i \
            "$C_AIRFLOW" sh -c '
                airflow users create \
                    --username "$1" \
                    --firstname Admin --lastname VektralForge \
                    --role Admin --email "$2"
            ' _ "$AF_USER" "$AF_EMAIL" 2>&1); then
            echo "[INFO]  created"
        elif echo "$out" | grep -qi "already exist"; then
            echo "[INFO]  already existed"
        else
            step_failed "Airflow: $out"
        fi
    else
        echo "[INFO]  the 'airflow users' command is not available"
        echo "    (Airflow 3 with SimpleAuthManager: users are defined via"
        echo "     configuration; install apache-airflow-providers-fab to use the CLI)"
    fi

    # ── Superset ─────────────────────────────────────────────────────────────────
    echo "[INFO]  Initializing Superset..."
    if out=$(docker exec "$C_SUPERSET" superset db upgrade 2>&1); then
        echo "[INFO]  schema upgraded"
    else
        step_failed "superset db upgrade: $(echo "$out" | tail -3)"
    fi

    echo "[INFO]  Creating Superset admin user ($SS_USER)..."
    # Igual que Airflow: @click.password_option() pregunta con confirmación,
    # así que basta con no pasar --password y darle la clave por stdin.
    if out=$(printf '%s\n%s\n' "$SS_PASS" "$SS_PASS" | docker exec -i \
        "$C_SUPERSET" sh -c '
            superset fab create-admin \
                --username "$1" --firstname Admin --lastname VektralForge \
                --email "$2"
        ' _ "$SS_USER" "$SS_EMAIL" 2>&1); then
        echo "[INFO]  created"
    elif echo "$out" | grep -qiE "already exists|Error: .*duplicate"; then
        echo "[INFO]  already existed"
    else
        step_failed "Superset: $(echo "$out" | tail -3)"
    fi

    echo "[INFO]  Initializing Superset roles..."
    if out=$(docker exec "$C_SUPERSET" superset init 2>&1); then
        echo "[INFO]  roles initialized"
    else
        step_failed "superset init: $(echo "$out" | tail -3)"
    fi
}

paso_resumen() {
    # ── Resumen ──────────────────────────────────────────────────────────────────
    echo ""
    if [ "$FAILURES" -eq 0 ]; then
        echo "[INFO]  Stack initialized successfully"
    else
        echo "[WARN]  Stack initialized with $FAILURES failed step(s)"
    fi
    echo ""
}

paso_banner() {
    # El banner NO imprime contraseñas. Antes las imprimía las cinco, y eso es
    # exactamente lo que hace fácil filtrarlas: basta pegar la salida de un `make`
    # en un issue, un chat o una captura de pantalla para publicarlas todas. Se
    # muestra el NOMBRE de la variable; el valor lo lee quien lo necesite.
    printf "  %-10s %-26s %-15s %s\n" "Service" "URL" "User" "Password"
    printf "  %-10s %-26s %-15s %s\n" "--------" "-------------------------" "---------------" "-------------------------"
    printf "  %-10s %-26s %-15s %s\n" "Airflow"  "http://localhost:8090" "$AF_USER"          "\$AIRFLOW_ADMIN_PASSWORD"
    printf "  %-10s %-26s %-15s %s\n" "Superset" "http://localhost:8088" "$SS_USER"          "\$SUPERSET_ADMIN_PASSWORD"
    printf "  %-10s %-26s %-15s %s\n" "RustFS"   "http://localhost:9001" "$S3_ROOT_USER_VAL" "\$S3_ROOT_PASSWORD"
    printf "  %-10s %-26s %-15s %s\n" "OpenBao"  "http://localhost:8200" "token:"            "\$OPENBAO_TOKEN"
    printf "  %-10s %-26s %-15s %s\n" "Trino"    "http://localhost:8081" "trino"             "no authentication"
    printf "  %-10s %-26s %-15s %s\n" "Spark"    "http://localhost:8082" "-"                 "no authentication"
    printf "  %-10s %-26s %-15s %s\n" "Marquez"  "http://localhost:3000" "-"                 "no authentication"
    echo ""
    echo "  Passwords live in $ENV_FILE (permissions 600) and are never printed."
    echo "  To read one:"
    echo "      grep '^AIRFLOW_ADMIN_PASSWORD=' $ENV_FILE | cut -d= -f2-"
    echo ""
    echo "  Trino, Spark, and Marquez don't ask for credentials: anyone who reaches"
    echo "  those ports gets in. That's why .env sets BIND_HOST=127.0.0.1."
    echo ""
    echo "  Buckets: raw/ bronze/ silver/ gold/ checkpoints/"
    echo "  Sample data: make dev-load-example"
    echo ""
}

# ── Despacho ─────────────────────────────────────────────────────────────────
# El primer argumento sigue siendo el .env, como antes. El segundo elige qué
# hacer; sin él, todo.
case "${SUBCOMANDO:=${2:-todo}}" in
    bases)    paso_bases ;;
    buckets)  paso_buckets ;;
    cuentas)  paso_cuentas ;;
    usuarios) paso_usuarios ;;
    banner)   paso_banner ;;
    todo)
        paso_bases
        paso_buckets
        paso_cuentas
        paso_usuarios
        paso_resumen
        paso_banner
        ;;
    *)
        echo "[ERROR] Unknown subcommand: $SUBCOMANDO" >&2
        echo "    Use: bases | buckets | cuentas | usuarios | banner | todo" >&2
        exit 1
        ;;
esac

exit "$FAILURES"
