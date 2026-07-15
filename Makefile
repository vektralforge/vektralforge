# lakeforge Makefile — interfaz unificada de comandos
.PHONY: setup dev-up dev-down dev-logs dev-reset dev-reset-hard \
        dev-load-example \
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
	@echo "  Datos de ejemplo: make dev-load-example"

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
	@bash .ci/scripts/init_users.sh $(ENV_FILE)
	@echo ""
	@echo "  Para cargar datos de ejemplo:"
	@echo "    make dev-load-example"

dev-reset-hard: check-env
	@echo "→ Reset extremo (borra volúmenes + imágenes custom)..."
	$(COMPOSE) --env-file $(ENV_FILE) down -v --rmi local
	@$(MAKE) dev-reset

# ── Cargar datos de ejemplo ───────────────────────────────────────────────────
dev-load-example: check-env
	@echo "→ Cargando datos de ejemplo..."
	@echo "  DAG: indicadores_financieros_chile"
	@echo "  Tablas: UF · Dólar · Euro · UTM · TPM"
	@echo "  Dashboard: Indicadores Financieros Chile 2026"
	@echo ""
	@bash .ci/scripts/load_example.sh $(ENV_FILE)

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
	@echo "    make setup                Crea .venv e instala dependencias"
	@echo "    make dev-up               Levanta stack (requiere $(ENV_FILE))"
	@echo "    make dev-down             Detiene stack"
	@echo "    make dev-logs             Logs en tiempo real"
	@echo "    make dev-reset            Reset completo (borra volúmenes, recrea usuarios)"
	@echo "    make dev-reset-hard       Reset extremo (borra volúmenes + imágenes custom)"
	@echo "    make dev-load-example     Carga datos de ejemplo y configura dashboard"
	@echo ""
	@echo "  Calidad de código:"
	@echo "    make lint-all             Lint completo (Ruff + sqlfluff)"
	@echo "    make test-all             Tests completos"
	@echo "    make detect-secrets       Escaneo de credenciales"
	@echo ""
	@echo "  Deploy:"
	@echo "    make deploy-staging       Deploy K3s staging"
	@echo "    make deploy-prod          Deploy K3s producción (requiere confirmación)"
	@echo ""
	@echo "  Flujo típico después de make dev-reset-hard:"
	@echo "    make dev-reset-hard"
	@echo "    make dev-load-example     ← carga indicadores + Trino + dashboard Superset"
	@echo ""
	@echo "  Variables leídas desde: $(ENV_FILE)"
	@echo "  Ejemplo:                 cp .env.example $(ENV_FILE)"
	@echo ""
