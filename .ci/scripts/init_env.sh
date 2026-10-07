#!/usr/bin/env bash
#
# Prepara infra/docker-compose/.env a partir de .env.example.
#
# Genera las claves criptográficas y pide las contraseñas de servicio, con un
# valor generado por defecto que se acepta pulsando Enter.
#
# Es idempotente: solo rellena lo que esté vacío o marcado como GENERAR /
# cambiar-esta-clave. Nunca sobrescribe un valor ya definido, así que puede
# ejecutarse las veces que haga falta sin perder configuración.
#
# Log: mismo formato que check_deps.sh/setup.sh — [INFO]/[WARN]/[ERROR], en
# inglés — homologado a mano acá porque este script no sourcea check_deps.sh
# (corre antes de que exista nada que chequear).
#
# Generación de valores: por `openssl`, no por `python3`. Este script corre
# ANTES que check_deps.sh — no hay garantía de que exista un Python utilizable
# todavía. En macOS, además, `python3` es parte de Xcode Command Line Tools:
# en una Mac recién formateada sin CLT, invocarlo dispara un diálogo pidiendo
# instalarlas (o directamente falla sin GUI), antes incluso de llegar a
# chequear nada. `openssl` viene en la instalación base de macOS (no en CLT) y
# en cualquier Linux con las herramientas mínimas, así que no agrega esa
# dependencia oculta. La clave Fernet, en particular, usaba el paquete
# `cryptography` solo para `Fernet.generate_key()`, que por su propio código
# fuente es `base64.urlsafe_b64encode(os.urandom(32))` — exactamente lo que
# hace `openssl rand -base64 32 | tr '+/' '-_'` acá abajo. Mismo formato,
# misma entropía, sin necesitar compilar ni instalar nada.

set -euo pipefail
cd "$(dirname "$0")/../.."

PLANTILLA=".env.example"
DESTINO="infra/docker-compose/.env"

# ── Message helpers ──────────────────────────────────────────────────────────

_info() { echo "[INFO]  $1"; }
_warn() { echo "[WARN]  $1"; }
_err()  { echo "[ERROR] $1" >&2; }

# Claves criptográficas: se generan siempre sin preguntar. No hay motivo para
# que una persona elija un valor aquí.
CLAVES_HEX=(
    AIRFLOW__API__SECRET_KEY
    AIRFLOW__API_AUTH__JWT_SECRET
    SUPERSET_SECRET_KEY
)

# Contraseñas de servicio: se ofrece una generada, editable.
declare -a PASSWORDS=(
    "POSTGRES_PASSWORD|PostgreSQL database"
    "S3_ROOT_PASSWORD|object store console and API"
    "AIRFLOW_ADMIN_PASSWORD|Airflow admin user"
    "SUPERSET_ADMIN_PASSWORD|Superset admin user"
    "OPENBAO_TOKEN|OpenBao root token"
    "S3_PIPELINE_SECRET_KEY|object store account for Airflow and Spark"
    "S3_HIVE_SECRET_KEY|object store account for the metastore"
    "S3_TRINO_SECRET_KEY|object store account for Trino"
)

# Valores de la plantilla que cuentan como «sin definir».
es_placeholder() {
    case "$1" in
        ""|GENERAR|cambiar-esta-clave|cambiar-este-token) return 0 ;;
        *) return 1 ;;
    esac
}

leer_valor() {
    grep -E "^${1}=" "$DESTINO" 2>/dev/null | head -1 | cut -d= -f2- || true
}

# sed con delimitador | para no chocar con las barras de las URL, y escapando
# el valor por si contiene caracteres especiales.
#
# Si la clave NO está en el archivo, se añade. Antes solo se sustituía: `sed` no
# encontraba línea que cambiar, no escribía nada, y el bucle de más abajo —que
# había leído un valor vacío y la daba por pendiente— anunciaba «generada» de
# todos modos. Cualquier variable nueva de la plantilla se perdía en silencio
# para quien ya tuviera un .env, que es todo el mundo salvo en la primera
# instalación.
escribir_valor() {
    local clave="$1" valor="$2"
    local escapado
    escapado=$(printf '%s' "$valor" | sed -e 's/[\\|&]/\\&/g')
    if grep -qE "^${clave}=" "$DESTINO"; then
        sed -i.bak -E "s|^${clave}=.*|${clave}=${escapado}|" "$DESTINO"
        rm -f "${DESTINO}.bak"
    else
        printf '%s=%s\n' "$clave" "$valor" >> "$DESTINO"
    fi

    # Comprobar lo escrito en vez de suponerlo: es justo lo que faltaba para que
    # el fallo anterior se notara. -x exige línea completa y -F la trata como
    # texto literal, sin interpretar nada del valor.
    if ! grep -qxF "${clave}=${valor}" "$DESTINO"; then
        _err "Could not write $clave to $DESTINO"
        exit 1
    fi
}

generar_hex() {
    openssl rand -hex 32
}

generar_password() {
    # Base64 url-safe sin relleno: evita caracteres que rompen cadenas de
    # conexión y comandos, igual que hacía secrets.token_urlsafe(24).
    openssl rand -base64 24 | tr '+/' '-_' | tr -d '=\n'
}

generar_fernet() {
    # Formato propio de Fernet: 32 bytes aleatorios en base64 url-safe, CON
    # el relleno '=' (a diferencia de generar_password, acá no se recorta:
    # Fernet exige ese formato exacto).
    openssl rand -base64 32 | tr '+/' '-_' | tr -d '\n'
}

# ── Preparación ───────────────────────────────────────────────────────────────

if [ ! -f "$PLANTILLA" ]; then
    _err "$PLANTILLA not found"
    exit 1
fi

# Garantizado en macOS base y en toda instalación estándar de Debian/Ubuntu,
# Fedora/RHEL, Arch y openSUSE — pero no en imágenes mínimas de contenedor.
# Si falta, mejor un error claro acá que un fallo críptico del pipeline dentro
# de generar_hex/generar_password/generar_fernet.
if ! command -v openssl >/dev/null 2>&1; then
    _err "openssl is not installed or not in PATH."
    echo "  It's required to generate the keys and passwords in $DESTINO." >&2
    echo "  It ships by default on macOS and on virtually every Linux desktop/server" >&2
    echo "  install; if it's missing here, install it with your package manager" >&2
    echo "  (apt-get install openssl / dnf install openssl / pacman -S openssl /" >&2
    echo "  zypper install openssl) and run this again." >&2
    exit 1
fi

if [ ! -f "$DESTINO" ]; then
    mkdir -p "$(dirname "$DESTINO")"
    cp "$PLANTILLA" "$DESTINO"
    _info "Created $DESTINO from $PLANTILLA"
else
    _info "$DESTINO already exists, filling in only the pending values"
fi
echo ""

# ── Claves criptográficas ─────────────────────────────────────────────────────

_info "Cryptographic keys"
for clave in "${CLAVES_HEX[@]}"; do
    actual=$(leer_valor "$clave")
    if es_placeholder "$actual"; then
        escribir_valor "$clave" "$(generar_hex)"
        _info "$clave generated"
    else
        _info "$clave already set"
    fi
done

# Fernet tiene su propio formato: no vale un token_hex.
actual=$(leer_valor AIRFLOW__CORE__FERNET_KEY)
if es_placeholder "$actual"; then
    escribir_valor AIRFLOW__CORE__FERNET_KEY "$(generar_fernet)"
    _info "AIRFLOW__CORE__FERNET_KEY generated"
else
    _info "AIRFLOW__CORE__FERNET_KEY already set"
fi

# ── Contraseñas ───────────────────────────────────────────────────────────────

echo ""
_info "Service passwords"
echo "  Press Enter to accept the generated value, or type your own."
echo ""

pendientes=0
for entrada in "${PASSWORDS[@]}"; do
    clave="${entrada%%|*}"
    descripcion="${entrada#*|}"
    actual=$(leer_valor "$clave")

    if ! es_placeholder "$actual"; then
        _info "$clave already set"
        continue
    fi

    pendientes=$((pendientes + 1))
    sugerida=$(generar_password)
    printf '[INFO]  %s\n    %s\n    [%s]: ' "$clave" "$descripcion" "$sugerida"

    # Se lee del terminal para que funcione aunque el script se invoque desde
    # make con la salida redirigida. Comprobar que /dev/tty existe no basta:
    # en un contenedor o una tubería el archivo está pero no se puede abrir.
    respuesta=""
    tty_disponible=0
    { exec 3</dev/tty; } 2>/dev/null && tty_disponible=1

    if [ "$tty_disponible" -eq 1 ]; then
        read -r respuesta <&3 || respuesta=""
        exec 3<&-
    else
        echo "(no terminal: using the generated value)"
    fi

    escribir_valor "$clave" "${respuesta:-$sugerida}"
done

[ "$pendientes" -eq 0 ] && _info "(nothing pending)"

# ── Comprobación final ────────────────────────────────────────────────────────

echo ""
restantes=$(grep -nE "=(GENERAR|cambiar-esta-clave|cambiar-este-token)$" "$DESTINO" || true)
if [ -n "$restantes" ]; then
    _warn "Remaining undefined values:"
    # shellcheck disable=SC2001
    echo "$restantes" | sed 's/^/      /'
else
    _info "No placeholders left"
fi

chmod 600 "$DESTINO"

echo ""
_info "$DESTINO ready (permissions 600)"
echo ""
echo "  If you changed POSTGRES_USER or POSTGRES_PASSWORD, the volume needs to"
echo "  be recreated: the user is fixed when the database is initialized, and"
echo "  a new .env doesn't update it."
echo ""
echo "    make dev-reset"
echo ""
echo "  Otherwise:"
echo ""
echo "    make dev-up"
echo ""
