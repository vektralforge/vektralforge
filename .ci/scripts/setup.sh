#!/usr/bin/env bash
# .ci/scripts/setup.sh — Instala dependencias locales de vektralforge
# Compatible con macOS Homebrew (PEP 668) y Linux
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VENV_DIR="$REPO_ROOT/.venv"

# ── 1. Verificar Python ───────────────────────────────────────────────────────
echo "→ Verificando Python 3.10+..."
python3 -c "import sys; assert sys.version_info >= (3,10), 'Requiere Python 3.10+'"
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "  Python $PYTHON_VERSION detectado ✓"

# ── 2. Crear virtualenv si no existe ─────────────────────────────────────────
if [ ! -d "$VENV_DIR" ]; then
  echo "→ Creando virtualenv en .venv/ ..."
  python3 -m venv "$VENV_DIR"
  echo "  ✓ Virtualenv creado"
else
  echo "→ Virtualenv .venv/ ya existe, reutilizando"
fi

# ── 3. Activar virtualenv ─────────────────────────────────────────────────────
source "$VENV_DIR/bin/activate"
echo "→ Virtualenv activo: $VIRTUAL_ENV"

# ── 4. Actualizar pip ────────────────────────────────────────────────────────
echo "→ Actualizando pip..."
pip install --upgrade pip --quiet

# ── 5. Instalar dependencias ──────────────────────────────────────────────────
echo "→ Instalando dependencias Airflow..."
pip install -r "$REPO_ROOT/airflow/requirements.txt"

echo "→ Instalando dependencias Spark..."
pip install -r "$REPO_ROOT/spark/requirements.txt"

# Desde los requirements, no desde una lista escrita aquí: esta línea instalaba
# ruff, sqlfluff y detect-secrets SIN versión, saltándose los pines que el CI sí
# respeta. El resultado era que el lint local y el del CI podían discrepar, que
# es exactamente lo que los pines existen para evitar.
echo "→ Instalando herramientas de desarrollo..."
pip install --quiet -r "$REPO_ROOT/airflow/requirements-dev.txt"
pip install --quiet -r "$REPO_ROOT/spark/requirements-dev.txt"

# pre-commit es la única que se queda sin fijar, y a propósito: no es un linter
# sino el ejecutor, y las versiones que deciden el resultado son los `rev` de
# .pre-commit-config.yaml, que sí están fijados y que Dependabot vigila con su
# ecosistema `pre-commit`. Fijar además el ejecutor añadiría una dependencia que
# mantener a cambio de casi nada.
pip install --quiet pre-commit

# ── 6. pre-commit ─────────────────────────────────────────────────────────────
echo "→ Configurando pre-commit hooks..."
cd "$REPO_ROOT"
pre-commit install

# ── 7. detect-secrets baseline ───────────────────────────────────────────────
echo "→ Inicializando baseline de detect-secrets..."
detect-secrets scan > "$REPO_ROOT/.secrets.baseline"

# ── 8. .venv en .gitignore ───────────────────────────────────────────────────
if ! grep -q "^\.venv" "$REPO_ROOT/.gitignore" 2>/dev/null; then
  echo ".venv/" >> "$REPO_ROOT/.gitignore"
  echo "  ✓ .venv/ agregado a .gitignore"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✓ Setup completo                                        ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Activar entorno:   source .venv/bin/activate            ║"
echo "║  Levantar stack:    make dev-up                          ║"
echo "║  OpenBao:           http://localhost:8200                ║"
echo "╚══════════════════════════════════════════════════════════╝"
