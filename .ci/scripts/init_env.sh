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

set -euo pipefail
cd "$(dirname "$0")/../.."

PLANTILLA=".env.example"
DESTINO="infra/docker-compose/.env"

# Claves criptográficas: se generan siempre sin preguntar. No hay motivo para
# que una persona elija un valor aquí.
CLAVES_HEX=(
    AIRFLOW__API__SECRET_KEY
    AIRFLOW__API_AUTH__JWT_SECRET
    SUPERSET_SECRET_KEY
)

# Contraseñas de servicio: se ofrece una generada, editable.
declare -a PASSWORDS=(
    "POSTGRES_PASSWORD|base de datos PostgreSQL"
    "MINIO_ROOT_PASSWORD|consola y API de MinIO"
    "AIRFLOW_ADMIN_PASSWORD|usuario admin de Airflow"
    "SUPERSET_ADMIN_PASSWORD|usuario admin de Superset"
    "OPENBAO_TOKEN|token raíz de OpenBao"
    "MINIO_PIPELINE_SECRET_KEY|cuenta de MinIO de Airflow y Spark"
    "MINIO_HIVE_SECRET_KEY|cuenta de MinIO del metastore"
    "MINIO_TRINO_SECRET_KEY|cuenta de MinIO de Trino"
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
        echo "  ✗ No se pudo escribir $clave en $DESTINO" >&2
        exit 1
    fi
}

generar_hex() {
    python3 -c "import secrets; print(secrets.token_hex(32))"
}

generar_password() {
    # token_urlsafe evita caracteres que rompen cadenas de conexión y comandos.
    python3 -c "import secrets; print(secrets.token_urlsafe(24))"
}

# ── Preparación ───────────────────────────────────────────────────────────────

[ -f "$PLANTILLA" ] || { echo "✗ No existe $PLANTILLA"; exit 1; }

if [ ! -f "$DESTINO" ]; then
    mkdir -p "$(dirname "$DESTINO")"
    cp "$PLANTILLA" "$DESTINO"
    echo "→ Creado $DESTINO desde $PLANTILLA"
else
    echo "→ $DESTINO ya existe: se rellenan solo los valores pendientes"
fi
echo

# ── Claves criptográficas ─────────────────────────────────────────────────────

echo "Claves criptográficas"
for clave in "${CLAVES_HEX[@]}"; do
    actual=$(leer_valor "$clave")
    if es_placeholder "$actual"; then
        escribir_valor "$clave" "$(generar_hex)"
        echo "  + $clave generada"
    else
        echo "  · $clave ya definida"
    fi
done

# Fernet tiene su propio formato: no vale un token_hex.
actual=$(leer_valor AIRFLOW__CORE__FERNET_KEY)
if es_placeholder "$actual"; then
    fernet=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" 2>/dev/null) || {
        echo "  ✗ Falta el paquete cryptography. Instálalo con: pip install cryptography"
        exit 1
    }
    escribir_valor AIRFLOW__CORE__FERNET_KEY "$fernet"
    echo "  + AIRFLOW__CORE__FERNET_KEY generada"
else
    echo "  · AIRFLOW__CORE__FERNET_KEY ya definida"
fi

# ── Contraseñas ───────────────────────────────────────────────────────────────

echo
echo "Contraseñas de servicio"
echo "  Pulsa Enter para aceptar la generada, o escribe la tuya."
echo

pendientes=0
for entrada in "${PASSWORDS[@]}"; do
    clave="${entrada%%|*}"
    descripcion="${entrada#*|}"
    actual=$(leer_valor "$clave")

    if ! es_placeholder "$actual"; then
        echo "  · $clave ya definida"
        continue
    fi

    pendientes=$((pendientes + 1))
    sugerida=$(generar_password)
    printf '  %s\n    %s\n    [%s]: ' "$clave" "$descripcion" "$sugerida"

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
        echo "(sin terminal: se usa el valor generado)"
    fi

    escribir_valor "$clave" "${respuesta:-$sugerida}"
done

[ "$pendientes" -eq 0 ] && echo "  (nada pendiente)"

# ── Comprobación final ────────────────────────────────────────────────────────

echo
restantes=$(grep -nE "=(GENERAR|cambiar-esta-clave|cambiar-este-token)$" "$DESTINO" || true)
if [ -n "$restantes" ]; then
    echo "  ⚠ Quedan valores sin definir:"
    echo "$restantes" | sed 's/^/      /'
else
    echo "  ✓ Sin placeholders pendientes"
fi

chmod 600 "$DESTINO"

cat <<EOF

  $DESTINO listo (permisos 600).

  Si cambiaste POSTGRES_USER o POSTGRES_PASSWORD, hace falta recrear el
  volumen: el usuario se fija al inicializar la base y un .env nuevo no lo
  actualiza.

      make dev-reset

  Si no, basta con:

      make dev-up

EOF
