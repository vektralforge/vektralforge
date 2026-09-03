#!/usr/bin/env bash
#
# Auditoría de credenciales en el historial completo de git.
#
# `detect_secrets.sh` mira el árbol de trabajo: lo que hay ahora. Este guion
# mira lo que hubo alguna vez. Un secreto borrado en un commit posterior sigue
# estando en el historial, y con el repositorio público sigue siendo público.
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
#   .ci/scripts/auditar_historial.sh            # todo el historial
#   .ci/scripts/auditar_historial.sh develop    # solo una rama o rango
#
# Salida: 0 si no hay hallazgos nuevos, 1 si los hay.

set -euo pipefail
cd "$(dirname "$0")/../.."

RANGO="${1:---all}"
REVISADOS=".ci/historial-revisado.txt"

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

echo "→ Auditando el historial en busca de credenciales…"
python3 -c "$PROGRAMA" "$RANGO" "$REVISADOS"
