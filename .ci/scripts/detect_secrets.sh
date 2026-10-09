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
    echo "[ERROR] .secrets.baseline not found"
    echo "    Generate it with:"
    echo "        detect-secrets scan --exclude-files '\\.secrets\\.baseline\$' \\"
    echo "            > .secrets.baseline"
    exit 1
fi

# El baseline guarda DENTRO los filtros con los que se generó, y de ahí los lee
# todo lo que lo consume después, incluido el hook de pre-commit. Regenerarlo
# sin --exclude-files no solo omite la exclusión en esa ejecución: la borra del
# archivo para siempre. Con el baseline vacío no se nota —es lo que pasó el
# 2026-10-02— pero en cuanto tenga una entrada real, sus propios hashes de alta
# entropía hacen que el archivo se delate a sí mismo en el siguiente escaneo.
if ! grep -q 'should_exclude_file' .secrets.baseline; then
    echo "[ERROR] .secrets.baseline doesn't carry the filter that excludes itself."
    echo "    It was lost by regenerating without --exclude-files. Redo it with:"
    echo "        detect-secrets scan --exclude-files '\\.secrets\\.baseline\$' \\"
    echo "            > .secrets.baseline"
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
    echo "[ERROR] Potential credentials not present in the baseline:"
    echo "$nuevos" | sed 's/^/      /'
    echo ""
    echo "    If they're false positives, mark them in the code:"
    echo "        VALUE = \"...\"  # pragma: allowlist secret"
    echo ""
    echo "    If they're real: do NOT add them to the baseline. Rotate them"
    echo "    and remove them from the code."
    exit 1
fi

echo "[INFO]  No new credentials relative to the baseline"
