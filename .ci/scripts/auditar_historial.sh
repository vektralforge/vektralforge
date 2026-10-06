#!/usr/bin/env bash
#
# Auditoría del historial completo de git, en dos modos.
#
# `detect_secrets.sh` mira el árbol de trabajo: lo que hay ahora. Este guion
# mira lo que hubo alguna vez. Un secreto borrado en un commit posterior sigue
# estando en el historial, y con el repositorio público sigue siendo público.
# Lo mismo vale para el nombre de un cliente.
#
#   credenciales     cadenas de alta entropía (el modo original)
#   identificadores  rastros de infraestructura ajena: IPs privadas, hosts
#                    internos, registros de contenedores privados, y los
#                    términos de una lista local que no se versiona
#
# Sin argumentos corre los dos.
#
# Dos pasadas, las mismas dos que usa detect-secrets para entropía:
#
#   base64  cadenas de [A-Za-z0-9+/=] de 20+ con entropía de Shannon > 4.5
#   hex     cadenas de [0-9a-fA-F]    de 20+ con entropía de Shannon > 3.0
#
# Se hacen las dos porque no se solapan: una clave hexadecimal larga tiene
# entropía baja en el alfabeto base64 (solo usa 16 de sus 64 símbolos) y se
# escapa de la primera pasada. Fue así como apareció el único hallazgo real
# del historial de este repositorio.
#
# SOBRE LA SALIDA: no imprime valores. De cada línea sospechosa se enmascara
# *toda* racha larga, no solo la que disparó el hallazgo — si en una misma
# línea hay dos tokens y solo se enmascara uno, el otro queda a la vista, que
# es un error que ya se cometió una vez en este proyecto. Cada hallazgo se
# identifica por una huella: los 12 primeros hex de su SHA-256.
#
# Uso:
#   .ci/scripts/auditar_historial.sh                         # los dos modos
#   .ci/scripts/auditar_historial.sh credenciales
#   .ci/scripts/auditar_historial.sh identificadores
#   .ci/scripts/auditar_historial.sh credenciales develop    # acotado a un rango
#   .ci/scripts/auditar_historial.sh develop                 # forma antigua: rango
#
# Salida: 0 si no hay hallazgos nuevos en ningún modo, 1 si los hay.

set -euo pipefail
cd "$(dirname "$0")/../.."

# El primer argumento era el rango, y lo sigue siendo si no nombra un modo: así
# `auditar_historial.sh develop` no se rompe.
case "${1:-}" in
    credenciales|identificadores|todo) MODO="$1"; shift ;;
    *)                                 MODO="todo" ;;
esac
RANGO="${1:---all}"
REVISADOS=".ci/historial-revisado.txt"
IDS_LISTA=".ci/identificadores-cliente.txt"
IDS_REVISADOS=".ci/identificadores-revisados.txt"

PROGRAMA=$(cat <<'PY'
import hashlib
import math
import re
import subprocess
import sys

RANGO, REVISADOS = sys.argv[1], sys.argv[2]

PASADAS = (
    ("base64", re.compile(r"[A-Za-z0-9+/=]{20,}"), 4.5),
    ("hex",    re.compile(r"[0-9a-fA-F]{20,}"),    3.0),
)

# Para enmascarar: cualquier racha larga, tenga o no entropia alta.
RACHA = re.compile(r"[A-Za-z0-9+/=_-]{16,}")

RUTAS_EXCLUIDAS = re.compile(
    r"(^|/)(\.secrets\.baseline|package-lock\.json|poetry\.lock|[^/]*\.lock)$"
)

# Exclusiones por linea, cada una con su motivo:
LINEAS_EXCLUIDAS = (
    # un pin de GitHub Actions es, por construccion, el id de un commit publico
    re.compile(r"uses:\s*[\w.-]+/[\w./-]+@[0-9a-f]{40}\b"),
    # el digest de una imagen de contenedor tambien es publico
    re.compile(r"@sha256:[0-9a-f]{64}\b"),
    # un pin de suma de verificacion es publico por definicion: existe para que
    # cualquiera lo recalcule sobre el artefacto descargado. Y cambia con cada
    # subida de version, asi que triarlo por huella obligaria a volver a
    # triarlo en cada bump.
    re.compile(r"\b(?:ARG|ENV)\s+[A-Za-z0-9_]*(?:SHA256|SHA512|CHECKSUM)[A-Za-z0-9_]*\s*="),
)


def ejecutar(orden):
    return subprocess.run(
        orden, capture_output=True, text=True, errors="replace", check=True
    ).stdout


def entropia(cadena):
    if not cadena:
        return 0.0
    total = len(cadena)
    return -sum(
        (n / total) * math.log2(n / total)
        for n in {c: cadena.count(c) for c in set(cadena)}.values()
    )


def huella(token):
    return hashlib.sha256(token.encode()).hexdigest()[:12]


# Un `NOMBRE=valor` deja ver el nombre y oculta el valor entero: sin el nombre
# el hallazgo no se puede triar sin abrir el commit. El nombre de una variable
# no es la credencial; el valor, aunque tenga varios tokens, se oculta completo.
ASIGNACION = re.compile(
    r"(\s*(?:ENV\s+|ARG\s+|export\s+)?[A-Za-z_][A-Za-z0-9_.-]*\s*[=:]\s*)(\S.*)"
)


def enmascarar(linea):
    m = ASIGNACION.match(linea)
    if m:
        return f"{m.group(1)}<{len(m.group(2))} caracteres ocultos>"[:200]
    return RACHA.sub(lambda m: f"<{len(m.group(0))} caracteres ocultos>", linea)[:200]


# Ids de objetos de este repositorio: un SHA que git conoce no es una
# credencial. Cubre los commits citados en la documentacion.
objetos = {
    l.split(" ", 1)[0]
    for l in ejecutar(["git", "rev-list", RANGO, "--objects"]).splitlines()
    if l
}

revisados = {}
try:
    with open(REVISADOS) as f:
        for linea in f:
            linea = linea.strip()
            if not linea or linea.startswith("#"):
                continue
            campos = linea.split(None, 1)
            revisados[campos[0]] = campos[1] if len(campos) > 1 else "(sin motivo)"
except FileNotFoundError:
    pass

registro = ejecutar(
    ["git", "log", RANGO, "--no-color", "--no-renames", "-p", "-U0",
     "--format=%x00%H %ad", "--date=short"]
)

hallazgos = {}
vistos_revisados = set()
commit = fecha = ruta = ""
lineas_leidas = 0

for linea in registro.splitlines():
    if linea.startswith("\0"):
        partes = linea[1:].split(" ", 1)
        commit, fecha = partes[0][:8], (partes[1] if len(partes) > 1 else "")
        ruta = ""
        continue
    if linea.startswith("+++ b/"):
        ruta = linea[6:]
        continue
    if not linea.startswith("+") or linea.startswith("+++"):
        continue

    lineas_leidas += 1
    contenido = linea[1:]

    if not ruta or ruta == "dev/null" or RUTAS_EXCLUIDAS.search(ruta):
        continue
    if any(p.search(contenido) for p in LINEAS_EXCLUIDAS):
        continue

    for nombre, patron, limite in PASADAS:
        for token in patron.findall(contenido):
            if token.lower() in objetos:
                continue
            if entropia(token) <= limite:
                continue
            h = huella(token)
            if h in revisados:
                vistos_revisados.add(h)
                continue
            hallazgos.setdefault(
                h,
                {"pasada": nombre, "commit": commit, "fecha": fecha,
                 "ruta": ruta, "linea": enmascarar(contenido), "veces": 0},
            )
            hallazgos[h]["veces"] += 1

print(f"  Rango: {RANGO}   lineas anadidas examinadas: {lineas_leidas}")

# Control positivo: si un hallazgo ya revisado deja de verse, no es una buena
# noticia — es que el escaneo dejo de mirar donde miraba. Falla igual.
perdidos = set(revisados) - vistos_revisados
if revisados:
    print(f"  Control positivo: {len(vistos_revisados)}/{len(revisados)} "
          "hallazgos ya revisados vueltos a encontrar")
else:
    print("  Control positivo: no hay ninguno — "
          f"{REVISADOS} esta vacio, el escaneo no esta comprobado")

if perdidos:
    print("\n  x No se encontraron hallazgos que si estaban en el historial:")
    for h in sorted(perdidos):
        print(f"      {h}  {revisados[h]}")
    print("\n    O se reescribio el historial, o este guion dejo de detectarlos.")
    print("    Las dos posibilidades hay que mirarlas antes de seguir.")
    sys.exit(1)

if not hallazgos:
    print("\n  OK Sin hallazgos nuevos de alta entropia en el historial.")
    sys.exit(0)

print(f"\n  x {len(hallazgos)} cadena(s) de alta entropia sin revisar:\n")
for h, d in sorted(hallazgos.items(), key=lambda kv: kv[1]["fecha"]):
    print(f"    huella {h}   pasada {d['pasada']}   {d['veces']} aparicion(es)")
    print(f"      primera vez: {d['commit']}  {d['fecha']}  {d['ruta']}")
    print(f"      {d['linea']}\n")

print(f"""    Cada una hay que mirarla en su commit y decidir:

      - Es una credencial viva  -> rotarla YA. Esta en el historial y el
        historial es publico; borrarla del arbol no la quita de ahi.
      - Es una credencial muerta o un falso positivo -> anadir la huella a
        {REVISADOS} con el motivo, y este guion deja de avisar de ella.

    Para verla sin exponerla en un log compartido:
      git log -p --all -S'<fragmento>' -- <ruta>""")
sys.exit(1)
PY
)

PROGRAMA_IDS=$(cat <<'PY'
import hashlib
import re
import subprocess
import sys

RANGO, LISTA, REVISADOS = sys.argv[1], sys.argv[2], sys.argv[3]

# Patrones ESTRUCTURALES. Van versionados porque no nombran a nadie: describen
# la FORMA de un rastro de infraestructura ajena, no su contenido. Cada uno
# lleva una muestra que DEBE coincidir, y con ella se comprueba el metodo antes
# de usarlo — la leccion del #53: un barrido que no encuentra nada tambien da
# verde cuando esta roto.
#
# Los rangos reservados para documentacion (RFC 5737) y el loopback quedan
# fuera a proposito: son los que se DEBEN usar en los ejemplos del repositorio.
PATRONES = [
    ("IP privada RFC1918",
     r"\b(?:10\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])|192\.168)\.\d{1,3}\.\d{1,3}\b",
     "10.14.3.9"),
    ("IP de enlace local o CGNAT",
     r"\b(?:169\.254|100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7]))\.\d{1,3}\.\d{1,3}\b",
     "169.254.1.1"),
    # La mirada atras descarta los globs: en `*.env.local` el candidato
    # `env.local` viene precedido de un punto, y un host no. La cadena se
    # consume entera para que `sub.host.internal` coincida de una pieza.
    ("host de red interna",
     r"(?<![*\w.-])(?:[a-z0-9][a-z0-9-]{0,62}\.)+"
     r"(?:local|lan|internal|intranet|corp|priv)\b",
     "servidor-ejemplo.internal"),
    ("registro de contenedores privado",
     r"\b(?:[a-z0-9-]+\.(?:azurecr\.io|gcr\.io|pkg\.dev)"
     r"|\d{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com)\b",
     "registroejemplo.azurecr.io"),
    # El primer caracter del host debe ser alfanumerico: sin eso, una expresion
    # regular escapada como '\\.secrets\\.baseline' se lee como ruta UNC.
    ("ruta UNC de Windows",
     r"\\\\[A-Za-z0-9][A-Za-z0-9._-]{1,}\\[A-Za-z0-9._$-]{1,}",
     r"\\servidor\recurso"),
]

RUTAS_EXCLUIDAS = re.compile(
    r"(^|/)(\.secrets\.baseline|[^/]*\.lock|identificadores-cliente\.txt"
    r"|identificadores-cliente\.txt\.example|identificadores-revisados\.txt"
    r"|auditar_historial\.sh)$"
)


def ejecutar(orden):
    return subprocess.run(
        orden, capture_output=True, text=True, errors="replace", check=True
    ).stdout


def huella(token):
    return hashlib.sha256(token.lower().encode()).hexdigest()[:12]


compilados = []
fallos_autoprueba = []
for nombre, patron, muestra in PATRONES:
    rx = re.compile(patron, re.I)
    if not rx.search(muestra):
        fallos_autoprueba.append(nombre)
    compilados.append((nombre, rx))

# La lista local NO se versiona: en un repositorio publico, enumerar los
# nombres que se buscan es publicarlos. Un termino por linea, literal, o
# expresion regular si empieza por "re:".
terminos = 0
try:
    with open(LISTA) as f:
        for linea in f:
            linea = linea.strip()
            if not linea or linea.startswith("#"):
                continue
            if linea.startswith("re:"):
                rx = re.compile(linea[3:], re.I)
            else:
                rx = re.compile(r"\b" + re.escape(linea) + r"\b", re.I)
            compilados.append(("termino de la lista local", rx))
            terminos += 1
except FileNotFoundError:
    pass

if fallos_autoprueba:
    print("  x El metodo esta roto: estos patrones no reconocen su propia muestra:")
    for n in fallos_autoprueba:
        print(f"      {n}")
    sys.exit(1)

revisados = {}
try:
    with open(REVISADOS) as f:
        for linea in f:
            linea = linea.strip()
            if not linea or linea.startswith("#"):
                continue
            campos = linea.split(None, 1)
            revisados[campos[0]] = campos[1] if len(campos) > 1 else "(sin motivo)"
except FileNotFoundError:
    pass

registro = ejecutar(
    ["git", "log", RANGO, "--no-color", "--no-renames", "-p", "-U0",
     "--format=%x00%H %ad", "--date=short"]
)

hallazgos = {}
vistos_revisados = set()
commit = fecha = ruta = ""
lineas_leidas = 0

for linea in registro.splitlines():
    if linea.startswith("\0"):
        partes = linea[1:].split(" ", 1)
        commit, fecha = partes[0][:8], (partes[1] if len(partes) > 1 else "")
        ruta = ""
        continue
    if linea.startswith("+++ b/"):
        ruta = linea[6:]
        continue
    if not linea.startswith("+") or linea.startswith("+++"):
        continue

    lineas_leidas += 1
    contenido = linea[1:]
    if not ruta or ruta == "dev/null" or RUTAS_EXCLUIDAS.search(ruta):
        continue

    for nombre, rx in compilados:
        for m in rx.finditer(contenido):
            h = huella(m.group(0))
            if h in revisados:
                vistos_revisados.add(h)
                continue
            # El valor se oculta igual que en el modo de credenciales: el
            # nombre de un cliente en un log compartido es el propio problema.
            oculto = rx.sub(
                lambda mm: f"<{len(mm.group(0))} caracteres ocultos>", contenido
            )[:200]
            hallazgos.setdefault(
                h,
                {"tipo": nombre, "commit": commit, "fecha": fecha,
                 "ruta": ruta, "linea": oculto, "veces": 0},
            )
            hallazgos[h]["veces"] += 1

print(f"  Rango: {RANGO}   lineas anadidas examinadas: {lineas_leidas}")
print(f"  Patrones estructurales: {len(PATRONES)} (autoprueba superada)"
      f"   terminos de la lista local: {terminos}")
if terminos == 0:
    print(f"  Aviso: no hay lista local en {LISTA} — solo corrieron los")
    print(f"         patrones estructurales. Ver {LISTA}.example")

perdidos = set(revisados) - vistos_revisados
if revisados:
    print(f"  Control positivo: {len(vistos_revisados)}/{len(revisados)} "
          "hallazgos ya revisados vueltos a encontrar")
if perdidos:
    print("\n  x No se encontraron hallazgos que si estaban en el historial:")
    for h in sorted(perdidos):
        print(f"      {h}  {revisados[h]}")
    print("\n    O se reescribio el historial, o este guion dejo de detectarlos.")
    sys.exit(1)

if not hallazgos:
    print("\n  OK Sin rastros de infraestructura ajena en el historial.")
    sys.exit(0)

print(f"\n  x {len(hallazgos)} identificador(es) sin revisar:\n")
for h, d in sorted(hallazgos.items(), key=lambda kv: kv[1]["fecha"]):
    print(f"    huella {h}   {d['tipo']}   {d['veces']} aparicion(es)")
    print(f"      primera vez: {d['commit']}  {d['fecha']}  {d['ruta']}")
    print(f"      {d['linea']}\n")

print(f"""    Cada uno hay que mirarlo en su commit y decidir:

      - Es un rastro real de infraestructura ajena -> no basta con borrarlo del
        arbol. Esta en el historial, y el historial es publico.
      - Es un ejemplo legitimo o un falso positivo -> anadir la huella a
        {REVISADOS} con el motivo. Para los ejemplos, usar los rangos de
        documentacion de la RFC 5737, que este guion no marca.

    Para verlo sin exponerlo en un log compartido:
      git log -p --all -S'<fragmento>' -- <ruta>""")
sys.exit(1)
PY
)

ESTADO=0

if [ "$MODO" = "credenciales" ] || [ "$MODO" = "todo" ]; then
    echo "→ Auditando el historial en busca de credenciales…"
    python3 -c "$PROGRAMA" "$RANGO" "$REVISADOS" || ESTADO=1
fi

if [ "$MODO" = "identificadores" ] || [ "$MODO" = "todo" ]; then
    [ "$MODO" = "todo" ] && echo ""
    echo "→ Auditando el historial en busca de identificadores de cliente…"
    python3 -c "$PROGRAMA_IDS" "$RANGO" "$IDS_LISTA" "$IDS_REVISADOS" || ESTADO=1
fi

exit "$ESTADO"
