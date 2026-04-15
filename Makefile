# ─────────────────────────────────────────────────────────────────────────────
# lakeforge — Makefile
# Interfaz unificada de comandos para todos los roles del equipo.
# Uso: make <comando>
# ─────────────────────────────────────────────────────────────────────────────

.PHONY: setup dev-up dev-down \
        lint-dags test-dags \
        lint-spark test-spark \
        lint-sql \
        lint-all test-all \
        detect-secrets \
        deploy-staging deploy-prod \
        help

# ── setup ─────────────────────────────────────────────────────────────────────
setup:
	@echo "→ Instalando dependencias locales..."
	@.ci/scripts/setup.sh

# ── entorno local ─────────────────────────────────────────────────────────────
dev-up:
	@echo "→ Levantando stack local..."
	docker compose -f infra/docker-compose/docker-compose.yml up -d
	@echo "✓ Stack disponible en http://localhost:8080 (Airflow)"

dev-down:
	@echo "→ Deteniendo stack local..."
	docker compose -f infra/docker-compose/docker-compose.yml down

dev-logs:
	docker compose -f infra/docker-compose/docker-compose.yml logs -f

dev-reset:
	@echo "→ Reset completo del stack local (borra volúmenes)..."
	docker compose -f infra/docker-compose/docker-compose.yml down -v

# ── airflow ───────────────────────────────────────────────────────────────────
lint-dags:
	@echo "→ Lint DAGs (Ruff)..."
	@.ci/scripts/lint_dags.sh

test-dags:
	@echo "→ Tests DAGs (pytest)..."
	@.ci/scripts/test_dags.sh

# ── spark ─────────────────────────────────────────────────────────────────────
lint-spark:
	@echo "→ Lint Spark jobs (Ruff)..."
	@.ci/scripts/lint_spark.sh

test-spark:
	@echo "→ Tests Spark (pytest + chispa)..."
	@.ci/scripts/test_spark.sh

# ── sql / trino ───────────────────────────────────────────────────────────────
lint-sql:
	@echo "→ Lint SQL (sqlfluff)..."
	@.ci/scripts/lint_sql.sh

# ── all ───────────────────────────────────────────────────────────────────────
lint-all: lint-dags lint-spark lint-sql
	@echo "✓ Lint completo OK"

test-all: test-dags test-spark
	@echo "✓ Tests completos OK"

# ── seguridad ─────────────────────────────────────────────────────────────────
detect-secrets:
	@echo "→ Escaneando secretos..."
	@.ci/scripts/detect_secrets.sh

# ── despliegue ────────────────────────────────────────────────────────────────
deploy-staging:
	@echo "→ Deploy a K3s staging..."
	@.ci/scripts/deploy_k3s.sh staging

deploy-prod:
	@echo "→ Deploy a K3s producción..."
	@read -p "¿Confirmar deploy a PRODUCCIÓN? (yes/no): " confirm; \
	[ "$$confirm" = "yes" ] && .ci/scripts/deploy_k3s.sh prod || echo "Deploy cancelado."

# ── help ──────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  lakeforge — comandos disponibles"
	@echo ""
	@echo "  Entorno local:"
	@echo "    make setup          Instala dependencias locales"
	@echo "    make dev-up         Levanta stack Docker Compose"
	@echo "    make dev-down       Detiene stack Docker Compose"
	@echo "    make dev-logs       Muestra logs en tiempo real"
	@echo "    make dev-reset      Reset completo (borra volúmenes)"
	@echo ""
	@echo "  Calidad de código:"
	@echo "    make lint-dags      Lint Airflow DAGs"
	@echo "    make lint-spark     Lint Spark jobs"
	@echo "    make lint-sql       Lint SQL Trino"
	@echo "    make lint-all       Lint completo"
	@echo "    make test-dags      Tests DAGs"
	@echo "    make test-spark     Tests Spark"
	@echo "    make test-all       Tests completos"
	@echo ""
	@echo "  Seguridad:"
	@echo "    make detect-secrets Escaneo de secretos"
	@echo ""
	@echo "  Despliegue:"
	@echo "    make deploy-staging Deploy a K3s staging"
	@echo "    make deploy-prod    Deploy a K3s producción"
	@echo ""
