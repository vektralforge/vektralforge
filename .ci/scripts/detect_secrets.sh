#!/usr/bin/env bash
#
# Escaneo de credenciales con detect-secrets.
#
# Compara el árbol actual contra .secrets.baseline y falla si aparece algún
# hallazgo nuevo. Los falsos positivos se marcan en el código con
# `# pragma: allowlist secret`, no ampliando el baseline a ciegas.
#
# NO se usa `detect-secrets audit`: es una interfaz interactiva que pide
# confirmar cada hallazgo por teclado. En CI se queda colgada hasta el timeout.

set -euo pipefail
cd "$(dirname "$0")/../.."

if [ ! -f .secrets.baseline ]; then
    echo "  ✗ No existe .secrets.baseline"
    echo "    Generarlo con: detect-secrets scan > .secrets.baseline"
    exit 1
fi

# scan --baseline reescribe el archivo con los hallazgos actuales. Se trabaja
# sobre una copia para poder comparar sin modificar el original.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
cp .secrets.baseline "$tmp"

# El propio baseline contiene hashes de alta entropía que detect-secrets
# detectaría como secretos. Se excluye del escaneo.
detect-secrets scan --baseline "$tmp" --exclude-files '\.secrets\.baseline$'

# Los campos generated_at y version cambian en cada ejecución; solo importa si
# aparecieron entradas nuevas en results.
extraer() {
    python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    datos = json.load(f)
for archivo, hallazgos in sorted(datos.get('results', {}).items()):
    for h in hallazgos:
        print(f\"{archivo}:{h.get('line_number')}:{h.get('type')}\")
" "$1"
}

antes=$(extraer .secrets.baseline)
despues=$(extraer "$tmp")

nuevos=$(comm -13 <(echo "$antes" | sort) <(echo "$despues" | sort))

if [ -n "$nuevos" ]; then
    echo ""
    echo "  ✗ Credenciales potenciales no presentes en el baseline:"
    echo "$nuevos" | sed 's/^/      /'
    echo ""
    echo "    Si son falsos positivos, márcalos en el código:"
    echo "        VALOR = \"...\"  # pragma: allowlist secret"
    echo ""
    echo "    Si son reales: NO los añadas al baseline. Rótalos y sácalos"
    echo "    del código."
    exit 1
fi

echo "✓ Sin credenciales nuevas respecto al baseline"
