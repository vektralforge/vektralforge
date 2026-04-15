#!/usr/bin/env bash
# .ci/scripts/setup.sh
# Instala todas las dependencias locales para desarrollo en lakeforge.
set -euo pipefail

echo "→ Verificando Python 3.11+..."
python3 -c "import sys; assert sys.version_info >= (3,11), 'Requiere Python 3.11+'"

echo "→ Instalando dependencias Airflow..."
pip install -r airflow/requirements.txt

echo "→ Instalando dependencias Spark..."
pip install -r spark/requirements.txt

echo "→ Instalando herramientas de desarrollo..."
pip install pre-commit detect-secrets ruff sqlfluff

echo "→ Configurando pre-commit hooks..."
pre-commit install

echo "→ Inicializando baseline de detect-secrets..."
detect-secrets scan > .secrets.baseline

echo ""
echo "✓ Setup completo. Ejecuta 'make dev-up' para levantar el stack local."
