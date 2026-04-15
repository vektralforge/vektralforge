# lakeforge Makefile — interfaz unificada de comandos
.PHONY: setup dev-up dev-down dev-logs dev-reset \
        lint-dags test-dags lint-spark test-spark lint-sql \
        lint-all test-all detect-secrets \
        deploy-staging deploy-prod help

setup:
	@.ci/scripts/setup.sh

dev-up:
	@echo "→ Levantando stack local..."
	docker compose -f infra/docker-compose/docker-compose.yml up -d
	@echo "✓ Airflow: http://localhost:8080 | Trino: http://localhost:8081 | OpenBao: http://localhost:8200"

dev-down:
	docker compose -f infra/docker-compose/docker-compose.yml down

dev-logs:
	docker compose -f infra/docker-compose/docker-compose.yml logs -f

dev-reset:
	docker compose -f infra/docker-compose/docker-compose.yml down -v

lint-dags:
	@.ci/scripts/lint_dags.sh

test-dags:
	@.ci/scripts/test_dags.sh

lint-spark:
	@.ci/scripts/lint_spark.sh

test-spark:
	@.ci/scripts/test_spark.sh

lint-sql:
	@.ci/scripts/lint_sql.sh

lint-all: lint-dags lint-spark lint-sql
	@echo "✓ Lint completo OK"

test-all: test-dags test-spark
	@echo "✓ Tests completos OK"

detect-secrets:
	@.ci/scripts/detect_secrets.sh

deploy-staging:
	@.ci/scripts/deploy_k3s.sh staging

deploy-prod:
	@read -p "¿Confirmar deploy a PRODUCCIÓN? (yes/no): " c; \
	[ "$$c" = "yes" ] && .ci/scripts/deploy_k3s.sh prod || echo "Deploy cancelado."

help:
	@echo ""
	@echo "  lakeforge — comandos disponibles"
	@echo "  make setup / dev-up / dev-down / dev-logs / dev-reset"
	@echo "  make lint-dags / lint-spark / lint-sql / lint-all"
	@echo "  make test-dags / test-spark / test-all"
	@echo "  make detect-secrets"
	@echo "  make deploy-staging / deploy-prod"
	@echo ""
