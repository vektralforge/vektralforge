#!/usr/bin/env bash
# .ci/scripts/setup.sh — Instala dependencias locales de vektralforge
# Compatible con macOS Homebrew (PEP 668) y Linux
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VENV_DIR="$REPO_ROOT/.venv"

# ── 1. Chequear/instalar dependencias de sistema ─────────────────────────────
# Delegado por completo a check_deps.sh: valida (e instala, con confirmación
# del usuario) python3.12, venv, pip, git, make, Homebrew/gestor de paquetes y
# Docker+Compose. Se sourcea (no se ejecuta directo) para que quede disponible
# su main() acá mismo, y para que el `exec > >(tee ...)` de su logging cubra
# también el resto de este script, no solo el chequeo de dependencias. Sourcear
# también deja disponibles sus helpers _info/_ok/_bad/_err — se reutilizan
# abajo en vez de reimplementar el mismo formato de log a mano.
# Al llamar a main() queda exportado PYTHON_BIN con la ruta absoluta del
# intérprete 3.12 ya validado — se usa más abajo para crear el virtualenv, en
# vez de confiar en cuál "python3" resuelva el PATH (que podía ser cualquier
# versión >= 3.10, no necesariamente la 3.12 que el resto del proyecto pisa).
source "$REPO_ROOT/.ci/scripts/check_deps.sh"
main

# ── 2. Crear virtualenv si no existe ─────────────────────────────────────────
if [ ! -d "$VENV_DIR" ]; then
  _info "Creating virtualenv in .venv/ (with $PYTHON_BIN)"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
  _ok "Virtualenv created"
else
  _info "Virtualenv .venv/ already exists, reusing it"
fi

# ── 3. Activar virtualenv ─────────────────────────────────────────────────────
source "$VENV_DIR/bin/activate"
_ok "Virtualenv active ($VIRTUAL_ENV)"

# ── 4. Actualizar pip ────────────────────────────────────────────────────────
_info "Updating pip"
pip install --upgrade pip --quiet

# ── 5. Instalar dependencias ──────────────────────────────────────────────────
_info "Installing Airflow dependencies"
pip install -r "$REPO_ROOT/airflow/requirements.txt"

_info "Installing Spark dependencies"
pip install -r "$REPO_ROOT/spark/requirements.txt"

# Desde los requirements, no desde una lista escrita aquí: esta línea instalaba
# ruff, sqlfluff y detect-secrets SIN versión, saltándose los pines que el CI sí
# respeta. El resultado era que el lint local y el del CI podían discrepar, que
# es exactamente lo que los pines existen para evitar.
_info "Installing development tools"
pip install --quiet -r "$REPO_ROOT/airflow/requirements-dev.txt"
pip install --quiet -r "$REPO_ROOT/spark/requirements-dev.txt"

# pre-commit es la única que se queda sin fijar, y a propósito: no es un linter
# sino el ejecutor, y las versiones que deciden el resultado son los `rev` de
# .pre-commit-config.yaml, que sí están fijados y que Dependabot vigila con su
# ecosistema `pre-commit`. Fijar además el ejecutor añadiría una dependencia que
# mantener a cambio de casi nada.
pip install --quiet pre-commit

# ── 6. pre-commit ─────────────────────────────────────────────────────────────
_info "Configuring pre-commit hooks"
cd "$REPO_ROOT"
pre-commit install

# ── 7. detect-secrets baseline ───────────────────────────────────────────────
_info "Initializing detect-secrets baseline"
detect-secrets scan > "$REPO_ROOT/.secrets.baseline"

# ── 8. .venv en .gitignore ───────────────────────────────────────────────────
if ! grep -q "^\.venv" "$REPO_ROOT/.gitignore" 2>/dev/null; then
  echo ".venv/" >> "$REPO_ROOT/.gitignore"
  _ok ".venv/ added to .gitignore"
fi

echo ""
_ok "Setup complete"
_info "Activate the environment: source .venv/bin/activate"
_info "Start the stack: make dev-up"
_info "OpenBao: http://localhost:8200"