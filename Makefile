# lakeforge Makefile — interfaz unificada de comandos
.PHONY: setup dev-up dev-down dev-logs dev-reset dev-reset-hard \
        lint-dags test-dags lint-spark test-spark lint-sql \
        lint-all test-all detect-secrets \
        deploy-staging deploy-prod help

COMPOSE  = docker compose -f infra/docker-compose/docker-compose.yml
ENV_FILE = infra/docker-compose/.env

# ── Verificar que existe el .env ──────────────────────────────────────────────
check-env:
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo ""; \
		echo "  ✗ ERROR: No existe el archivo $(ENV_FILE)"; \
		echo ""; \
		echo "  Crea el archivo copiando el ejemplo:"; \
		echo "    cp .env.example $(ENV_FILE)"; \
		echo "  Luego edita los valores según tu entorno."; \
		echo ""; \
		exit 1; \
	fi
	@echo "  ✓ $(ENV_FILE) encontrado"

# Leer variables del .env para usarlas en targets Make
# Se usa un subshell con export para evitar problemas con variables con __
_load_env = $(shell grep -v '^\#' $(ENV_FILE) | grep -v '^$$' | grep '=' | sed 's/=.*//' | while read k; do echo $$k=$$(grep "^$$k=" $(ENV_FILE) | cut -d= -f2-); done)

# ── Setup ─────────────────────────────────────────────────────────────────────
setup: check-env
	@echo "→ Ejecutando setup..."
	@bash .ci/scripts/setup.sh

# ── Stack local ───────────────────────────────────────────────────────────────
dev-up: check-env
	@echo "→ Levantando stack local..."
	$(COMPOSE) --env-file $(ENV_FILE) up -d
	@echo ""
	@echo "  ✓ Stack disponible en:"
	@echo "    Airflow  → http://localhost:8090"
	@echo "    Trino    → http://localhost:8081"
	@echo "    MinIO    → http://localhost:9001"
	@echo "    Superset → http://localhost:8088"
	@echo "    OpenBao  → http://localhost:8200"
	@echo "    Spark    → http://localhost:8082"
	@echo ""
	@echo "  Credenciales en: $(ENV_FILE)"

dev-down:
	$(COMPOSE) --env-file $(ENV_FILE) down

dev-logs:
	$(COMPOSE) --env-file $(ENV_FILE) logs -f

# ── Reset ─────────────────────────────────────────────────────────────────────
dev-reset: check-env
	@echo "→ Reset completo del stack..."
	$(COMPOSE) --env-file $(ENV_FILE) down -v
	@echo "→ Levantando stack limpio..."
	$(COMPOSE) --env-file $(ENV_FILE) up -d
	@echo "→ Esperando que los servicios estén listos (60s)..."
	@sleep 60
	@echo "→ Creando bases de datos PostgreSQL..."
	@POSTGRES_USER=$$(grep '^POSTGRES_USER=' $(ENV_FILE) | cut -d= -f2); \
	docker exec docker-compose-postgres-1 \
		psql -U "$$POSTGRES_USER" -c "CREATE DATABASE airflow;" 2>/dev/null || true; \
	docker exec docker-compose-postgres-1 \
		psql -U "$$POSTGRES_USER" -c "CREATE DATABASE metastore;" 2>/dev/null || true
	@echo "→ Creando usuario admin en Airflow..."
	@AF_USER=$$(grep '^AIRFLOW_ADMIN_USER=' $(ENV_FILE) | cut -d= -f2); \
	AF_PASS=$$(grep '^AIRFLOW_ADMIN_PASSWORD=' $(ENV_FILE) | cut -d= -f2); \
	AF_EMAIL=$$(grep '^AIRFLOW_ADMIN_EMAIL=' $(ENV_FILE) | cut -d= -f2); \
	AF_USER=$${AF_USER:-admin}; AF_PASS=$${AF_PASS:-admin}; AF_EMAIL=$${AF_EMAIL:-admin@alephserver.cl}; \
	docker exec docker-compose-airflow-webserver-1 \
		airflow users create \
		--username "$$AF_USER" \
		--password "$$AF_PASS" \
		--firstname Admin \
		--lastname Lakeforge \
		--role Admin \
		--email "$$AF_EMAIL" 2>/dev/null || \
		echo "  (usuario ya existe o Airflow aún iniciando)"
	@echo "→ Inicializando base de datos Superset...
	@docker exec docker-compose-superset-1 superset db upgrade 2>/dev/null || true
	@echo "→ Creando usuario admin en Superset..."
	@SS_USER=$$(grep '^SUPERSET_ADMIN_USER=' $(ENV_FILE) | cut -d= -f2); \
	SS_PASS=$$(grep '^SUPERSET_ADMIN_PASSWORD=' $(ENV_FILE) | cut -d= -f2); \
	SS_EMAIL=$$(grep '^SUPERSET_ADMIN_EMAIL=' $(ENV_FILE) | cut -d= -f2); \
	SS_USER=$${SS_USER:-admin}; SS_PASS=$${SS_PASS:-admin}; SS_EMAIL=$${SS_EMAIL:-admin@alephserver.cl}; \
	docker exec docker-compose-superset-1 \
		superset fab create-admin \
		--username "$$SS_USER" \
		--firstname Admin \
		--lastname Lakeforge \
		--email "$$SS_EMAIL" \
		--password "$$SS_PASS" 2>/dev/null || \
		echo "  (usuario ya existe o Superset aún iniciando)"
	@echo "→ Inicializando roles Superset..."
	@docker exec docker-compose-superset-1 superset init 2>/dev/null || true
	@echo ""
	@echo "  ✓ Reset completo. Stack disponible en:"
	@echo "    Airflow  → http://localhost:8090"
	@echo "    Trino    → http://localhost:8081"
	@echo "    MinIO    → http://localhost:9001"
	@echo "    Superset → http://localhost:8088"
	@echo "    OpenBao  → http://localhost:8200"
	@echo ""
	@echo "  Credenciales en: $(ENV_FILE)"

# Reset extremo: borra también imágenes construidas localmente
dev-reset-hard: check-env
	@echo "→ Reset extremo (borra volúmenes + imágenes custom)..."
	$(COMPOSE) --env-file $(ENV_FILE) down -v --rmi local
	@$(MAKE) dev-reset

# ── Lint ──────────────────────────────────────────────────────────────────────
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
	@echo "✓ Tests completos OK"

detect-secrets:
	@bash .ci/scripts/detect_secrets.sh

# ── Deploy ────────────────────────────────────────────────────────────────────
deploy-staging:
	@bash .ci/scripts/deploy_k3s.sh staging

deploy-prod:
	@read -p "¿Confirmar deploy a PRODUCCIÓN? (yes/no): " c; \
	[ "$$c" = "yes" ] && bash .ci/scripts/deploy_k3s.sh prod || echo "Deploy cancelado."

# ── Help ──────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  lakeforge — comandos disponibles"
	@echo ""
	@echo "  Setup y stack local:"
	@echo "    make setup              Crea .venv e instala dependencias"
	@echo "    make dev-up             Levanta stack (requiere $(ENV_FILE))"
	@echo "    make dev-down           Detiene stack"
	@echo "    make dev-logs           Logs en tiempo real"
	@echo "    make dev-reset          Reset completo (lee credenciales del .env)"
	@echo "    make dev-reset-hard     Reset extremo (borra volúmenes + imágenes custom)"
	@echo ""
	@echo "  Calidad de código:"
	@echo "    make lint-all           Lint completo (Ruff + sqlfluff)"
	@echo "    make test-all           Tests completos"
	@echo "    make detect-secrets     Escaneo de credenciales"
	@echo ""
	@echo "  Deploy:"
	@echo "    make deploy-staging     Deploy K3s staging"
	@echo "    make deploy-prod        Deploy K3s producción (requiere confirmación)"
	@echo ""
	@echo "  Variables leídas desde: $(ENV_FILE)"
	@echo "  Ejemplo:                 cp .env.example $(ENV_FILE)"
	@echo ""
