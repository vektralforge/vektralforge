# VektralForge — interfaz unificada de comandos
#
# Requisitos: Python 3.12, Docker Compose v2, GNU Make
# Variables de entorno: infra/docker-compose/.env (ver .env.example)

.PHONY: help check-env check-python \
        setup init-env\
        dev-up dev-down dev-logs dev-ps dev-build dev-reset dev-reset-hard dev-load-example \
        lint-dags test-dags lint-spark test-spark lint-sql \
        lint-all test-all detect-secrets \
        deploy-staging deploy-prod

.DEFAULT_GOAL := help

COMPOSE  = docker compose -f infra/docker-compose/docker-compose.yml
ENV_FILE = infra/docker-compose/.env
PYTHON   = python3.12

# Variables que deben existir y tener valor en el .env
REQUIRED_VARS = POSTGRES_USER POSTGRES_PASSWORD MINIO_ROOT_USER MINIO_ROOT_PASSWORD

# ── Verificaciones ────────────────────────────────────────────────────────────

check-python:
	@command -v $(PYTHON) >/dev/null 2>&1 || { \
		echo ""; \
		echo "  ✗ ERROR: se requiere Python 3.12 (no se encontró '$(PYTHON)')"; \
		echo ""; \
		echo "  VektralForge fija Python 3.12: versiones más nuevas rompen la"; \
		echo "  compilación de pandas, que los providers de Airflow acotan a <2.2."; \
		echo ""; \
		echo "    macOS:   brew install python@3.12"; \
		echo "    Ubuntu:  sudo apt install python3.12 python3.12-venv"; \
		echo "    pyenv:   pyenv install 3.12 && pyenv local 3.12"; \
		echo ""; \
		exit 1; \
	}
	@echo "  ✓ $$($(PYTHON) --version)"

check-env:
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo ""; \
		echo "  ✗ ERROR: no existe $(ENV_FILE)"; \
		echo ""; \
		echo "  Docker Compose lee las variables desde ese archivo. Sin él, los"; \
		echo "  contenedores arrancan con credenciales sin expandir y Postgres"; \
		echo "  rechaza la conexión unos noventa segundos después."; \
		echo ""; \
		echo "    cp .env.example $(ENV_FILE)"; \
		echo ""; \
		echo "  Luego edita los valores según tu entorno."; \
		echo ""; \
		exit 1; \
	fi
	@missing=""; \
	for v in $(REQUIRED_VARS); do \
		val=$$(grep -E "^$$v=" "$(ENV_FILE)" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' '); \
		if [ -z "$$val" ]; then missing="$$missing $$v"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo ""; \
		echo "  ✗ ERROR: variables sin valor en $(ENV_FILE):"; \
		for v in $$missing; do echo "      $$v"; done; \
		echo ""; \
		exit 1; \
	fi
	@echo "  ✓ $(ENV_FILE) completo"

# ── Setup ─────────────────────────────────────────────────────────────────────

setup: check-python check-env
	@echo "→ Ejecutando setup..."
	@PYTHON_BIN=$(PYTHON) bash .ci/scripts/setup.sh

# ── Crea $(ENV_FILE) con claves generadas ─────────────────────────────────────────────────────────────────────
init-env:
	@bash .ci/scripts/init_env.sh

# ── Stack local ───────────────────────────────────────────────────────────────

# §4.13 — `dev-up` y `dev-reset` construyen antes de levantar.
#
# Antes no lo hacían, y `docker compose build` no recrea contenedores. Con las
# dos cosas a la vez se podía editar un Dockerfile, reconstruir, y seguir
# ejecutando la imagen anterior sin ningún aviso: pasó al subir Superset a 6.1.0,
# donde el contenedor falló dos veces con el mismo error y el diagnóstico apuntó
# al arreglo en vez de a que el arreglo no había llegado.
#
# Construir siempre sale barato porque Docker decide por CONTENIDO si hay algo
# que hacer: con la caché caliente son un par de segundos. Y `up -d` recrea los
# contenedores cuya imagen cambió — comprobado cambiando la de marquez-api y
# viendo que el contenedor pasaba a apuntar al sha256 nuevo.
#
# Se probó antes una comprobación por fechas —comparar el mtime de los archivos
# con la fecha de creación de la imagen— y NO converge: una reconstrucción
# totalmente cacheada devuelve la MISMA imagen, con su fecha original, así que
# los archivos siguen pareciendo más recientes para siempre. Y un `git checkout`
# cambia el mtime sin cambiar el contenido. Docker ya resuelve esto por
# contenido; duplicarlo por fechas solo añade falsos positivos y una tabla de
# dependencias que mantener a mano.
dev-up: check-env dev-build
	@echo "→ Levantando stack local..."
	$(COMPOSE) --env-file $(ENV_FILE) up -d
	@echo ""
	@echo "  ✓ Stack disponible en:"
	@echo "    Airflow  → http://localhost:8090"
	@echo "    Trino    → http://localhost:8081"
	@echo "    MinIO    → http://localhost:9001"
	@echo "    Superset → http://localhost:8088"
	@echo "    Marquez  → http://localhost:9100"
	@echo "    OpenBao  → http://localhost:8200"
	@echo "    Spark    → http://localhost:8082"
	@echo ""
	@echo "  Credenciales en: $(ENV_FILE)"
	@echo "  Datos de ejemplo: make dev-load-example"

dev-down: check-env
	$(COMPOSE) --env-file $(ENV_FILE) down

dev-logs: check-env
	$(COMPOSE) --env-file $(ENV_FILE) logs -f $(SERVICE)

dev-ps: check-env
	@$(COMPOSE) --env-file $(ENV_FILE) ps

# ── Reset ─────────────────────────────────────────────────────────────────────

dev-reset: check-env dev-build
	@echo "→ Reset completo del stack (se borran los volúmenes)..."
	$(COMPOSE) --env-file $(ENV_FILE) down -v
	@echo "→ Levantando stack limpio..."
	$(COMPOSE) --env-file $(ENV_FILE) up -d
	@echo "→ Esperando que los servicios estén listos (60s)..."
	@sleep 60
	@bash .ci/scripts/init_users.sh $(ENV_FILE)
	@echo ""
	@echo "  Para cargar datos de ejemplo:"
	@echo "    make dev-load-example"

# `down --rmi local` NO sirve aquí: borra solo las imágenes sin tag propio en el
# campo `image:`, y las tres del proyecto lo tienen (vektralforge/airflow,
# vektralforge/spark, vektralforge/hive-metastore). Compose las saltaba, así que
# un cambio en un Dockerfile nunca llegaba al contenedor. Se reconstruye explícito.
dev-build: check-env
	@echo "→ Reconstruyendo las imágenes del proyecto..."
	$(COMPOSE) --env-file $(ENV_FILE) build

# Ahora que `dev-reset` construye siempre, lo que distingue a esta variante es
# ignorar la caché: es la que sirve cuando se sospecha de una capa cacheada y no
# de un Dockerfile desactualizado.
dev-reset-hard: check-env
	@echo "→ Reset extremo (borra volúmenes y reconstruye sin caché)..."
	$(COMPOSE) --env-file $(ENV_FILE) down -v
	@echo "→ Reconstruyendo las imágenes desde cero..."
	$(COMPOSE) --env-file $(ENV_FILE) build --no-cache
	@$(MAKE) dev-reset

# ── Cargar datos de ejemplo ───────────────────────────────────────────────────

dev-load-example: check-env
	@echo "→ Cargando datos de ejemplo..."
	@echo "  DAGs: indicadores_financieros_chile · arclim_riesgo_climatico_chile"
	@echo "  Fuentes: mindicador.cl · API ARClim (ambas públicas, sin API key)"
	@echo "  Salida: tablas Delta en Trino + dashboards en Superset"
	@echo ""
	@bash .ci/scripts/load_example.sh $(ENV_FILE)

# ── Lint y tests ──────────────────────────────────────────────────────────────

lint-dags:
	@bash .ci/scripts/lint_dags.sh

test-dags:
	@bash .ci/scripts/test_dags.sh

lint-spark:
	@bash .ci/scripts/lint_spark.sh

test-spark:
	@bash .ci/scripts/test_spark.sh

lint-sql:
	@bash .ci/scripts/lint_sql.sh

lint-all: lint-dags lint-spark lint-sql
	@echo "✓ Lint completo OK"

test-all: test-dags test-spark
	@echo "✓ Tests ejecutados (ver avisos arriba)"

detect-secrets:
	@bash .ci/scripts/detect_secrets.sh

# ── Deploy ────────────────────────────────────────────────────────────────────

deploy-staging:
	@bash .ci/scripts/deploy_k3s.sh staging

deploy-prod:
	@read -p "¿Confirmar deploy a PRODUCCIÓN? (escribe 'yes'): " c; \
	if [ "$$c" = "yes" ]; then \
		bash .ci/scripts/deploy_k3s.sh prod; \
	else \
		echo "Deploy cancelado."; \
	fi

# ── Help ──────────────────────────────────────────────────────────────────────

help:
	@echo ""
	@echo "  VektralForge — comandos disponibles"
	@echo ""
	@echo "  Setup y stack local:"
	@echo "    make setup                Crea .venv (Python 3.12) e instala dependencias"
	@echo "    make init-env             Crea $(ENV_FILE) con claves generadas"
	@echo "    make dev-up               Levanta el stack"
	@echo "    make dev-down             Detiene el stack"
	@echo "    make dev-ps               Estado de los contenedores"
	@echo "    make dev-logs             Logs en tiempo real (SERVICE=airflow-scheduler para uno solo)"
	@echo "    make dev-build            Reconstruye las imágenes tras cambiar un Dockerfile"
	@echo "    make dev-reset            Reset completo (borra volúmenes, recrea usuarios)"
	@echo "    make dev-reset-hard       Reset extremo (borra volúmenes y reconstruye imágenes)"
	@echo "    make dev-load-example     Carga los pipelines de ejemplo y los dashboards"
	@echo ""
	@echo "  Calidad de código:"
	@echo "    make lint-all             Lint completo (Ruff + sqlfluff)"
	@echo "    make test-all             Tests completos"
	@echo "    make detect-secrets       Escaneo de credenciales"
	@echo ""
	@echo "  Deploy — PLANIFICADO, no implementado:"
	@echo "    make deploy-staging       Falla explicando qué falta"
	@echo "    make deploy-prod          Ídem"
	@echo ""
	@echo "  Primer arranque:"
	@echo "    cp .env.example $(ENV_FILE)"
	@echo "    make setup"
	@echo "    make dev-up"
	@echo "    make dev-load-example"
	@echo ""
	@echo "  Requisitos: Python 3.12 · Docker Compose v2"
	@echo "  Variables:  $(ENV_FILE)"
	@echo ""
