# lakeforge Makefile — interfaz unificada de comandos
.PHONY: setup dev-up dev-down dev-logs dev-reset dev-reset-hard \
        lint-dags test-dags lint-spark test-spark lint-sql \
        lint-all test-all detect-secrets \
        deploy-staging deploy-prod help

COMPOSE = docker compose -f infra/docker-compose/docker-compose.yml

# ── Setup ─────────────────────────────────────────────────────────────────────
setup:
	@echo "→ Ejecutando setup..."
	@bash .ci/scripts/setup.sh

# ── Stack local ───────────────────────────────────────────────────────────────
dev-up:
	@echo "→ Levantando stack local..."
	$(COMPOSE) up -d
	@echo ""
	@echo "  ✓ Stack disponible en:"
	@echo "    Airflow  → http://localhost:8090  (admin / admin)"
	@echo "    Trino    → http://localhost:8081"
	@echo "    MinIO    → http://localhost:9001  (minioadmin / minioadmin)"
	@echo "    Superset → http://localhost:8088  (admin / admin)"
	@echo "    OpenBao  → http://localhost:8200  (token: dev-root-token)"
	@echo "    Spark    → http://localhost:8082"

dev-down:
	$(COMPOSE) down

dev-logs:
	$(COMPOSE) logs -f

# ── Reset ─────────────────────────────────────────────────────────────────────
dev-reset:
	@echo "→ Reset completo del stack (borra volúmenes y recrea usuarios)..."
	$(COMPOSE) down -v
	@echo "→ Levantando stack limpio..."
	$(COMPOSE) up -d
	@echo "→ Esperando que los servicios estén listos (60s)..."
	@sleep 60
	@echo "→ Recreando usuario admin en Airflow..."
	@docker exec docker-compose-airflow-webserver-1 \
		airflow users create \
		--username admin \
		--password admin \
		--firstname Admin \
		--lastname Lakeforge \
		--role Admin \
		--email admin@alephserver.cl 2>/dev/null || \
		echo "  (usuario ya existe o Airflow aún iniciando)"
	@echo "→ Recreando usuario admin en Superset..."
	@docker exec docker-compose-superset-1 \
		superset fab create-admin \
		--username admin \
		--firstname Admin \
		--lastname Lakeforge \
		--email admin@alephserver.cl \
		--password admin 2>/dev/null || \
		echo "  (usuario ya existe o Superset aún iniciando)"
	@echo "→ Inicializando Superset..."
	@docker exec docker-compose-superset-1 superset init 2>/dev/null || true
	@echo "→ Recreando bases de datos en PostgreSQL..."
	@docker exec docker-compose-postgres-1 \
		psql -U lakeforge -c "CREATE DATABASE airflow;" 2>/dev/null || true
	@docker exec docker-compose-postgres-1 \
		psql -U lakeforge -c "CREATE DATABASE metastore;" 2>/dev/null || true
	@echo ""
	@echo "  ✓ Reset completo. Stack disponible en:"
	@echo "    Airflow  → http://localhost:8090  (admin / admin)"
	@echo "    Trino    → http://localhost:8081"
	@echo "    MinIO    → http://localhost:9001  (minioadmin / minioadmin)"
	@echo "    Superset → http://localhost:8088  (admin / admin)"
	@echo "    OpenBao  → http://localhost:8200  (token: dev-root-token)"

# Reset extremo: borra también imágenes construidas localmente
dev-reset-hard:
	@echo "→ Reset extremo (borra volúmenes + imágenes custom)..."
	$(COMPOSE) down -v --rmi local
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
	@echo "    make dev-up             Levanta stack Docker Compose"
	@echo "    make dev-down           Detiene stack"
	@echo "    make dev-logs           Logs en tiempo real"
	@echo "    make dev-reset          Reset completo (borra volúmenes, recrea usuarios)"
	@echo "    make dev-reset-hard     Reset extremo (borra volúmenes + imágenes custom)"
	@echo ""
	@echo "  Calidad de código:"
	@echo "    make lint-dags          Lint DAGs Airflow (Ruff)"
	@echo "    make lint-spark         Lint Spark jobs (Ruff)"
	@echo "    make lint-sql           Lint SQL Trino (sqlfluff)"
	@echo "    make lint-all           Lint completo"
	@echo "    make test-dags          Tests DAGs (pytest)"
	@echo "    make test-spark         Tests Spark (pytest + chispa)"
	@echo "    make test-all           Tests completos"
	@echo "    make detect-secrets     Escaneo de credenciales y secretos"
	@echo ""
	@echo "  Deploy:"
	@echo "    make deploy-staging     Deploy K3s staging"
	@echo "    make deploy-prod        Deploy K3s producción (requiere confirmación)"
	@echo ""
