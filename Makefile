# VektralForge — interfaz unificada de comandos
#
# Requisitos: Python 3.12, Docker Compose v2, GNU Make
# Variables de entorno: infra/docker-compose/.env (ver .env.example)
#
# WARNING: no soportado en arquitecturas BSD (FreeBSD, OpenBSD, NetBSD,
# DragonFly). Docker Compose depende de namespaces y cgroups del kernel de
# Linux, que esos sistemas no tienen — no hay instalación nativa posible.
# check_deps.sh ya lo detecta y lo corta con ese mismo mensaje, pero eso
# solo corre dentro de `setup`; cualquier otro target (init-env, dev-up,
# etc.) ejecutado directo en BSD falla más abajo, con un error de Docker o
# de alguna otra herramienta en vez de esta explicación.

.PHONY: help check-env \
        setup init-env\
        dev-up dev-down dev-logs dev-ps dev-build dev-reset dev-reset-hard dev-load-example \
        dev-check-perms dev-check-logs dev-bundle-git \
        lint-dags test-dags lint-spark test-spark lint-sql \
        lint-all test-all detect-secrets auditar-historial auditar-identificadores \
        deploy-staging deploy-prod

.DEFAULT_GOAL := help

COMPOSE  = docker compose -f infra/docker-compose/docker-compose.yml
ENV_FILE = infra/docker-compose/.env

# Variables que deben existir y tener valor en el .env
REQUIRED_VARS = POSTGRES_USER POSTGRES_PASSWORD S3_ROOT_USER S3_ROOT_PASSWORD

# ── Verificaciones ────────────────────────────────────────────────────────────
#
# El chequeo de Python 3.12 (antes un target `check-python` acá) vivía
# duplicado: esta misma verificación, pero más superficial (solo
# `command -v`), corría de nuevo apenas arrancaba .ci/scripts/setup.sh, que
# ahora delega TODO el chequeo de dependencias de sistema — Python 3.12
# exacto, venv, pip, git, make, Homebrew/gestor de paquetes, Docker+Compose —
# a .ci/scripts/check_deps.sh. Se eliminó acá para no mantener dos fuentes de
# verdad sobre qué versión de Python se requiere.
#
# El logging de este archivo usa el mismo formato [INFO]/[ERROR] que
# check_deps.sh, en inglés — homologado a mano acá porque cada línea de una
# receta de Make corre en su propio subshell (no hay forma de sourcear los
# helpers _info/_ok/_err de check_deps.sh y que persistan entre líneas, como
# sí ocurre en setup.sh).

check-env:
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo ""; \
		echo "[ERROR] $(ENV_FILE) not found"; \
		echo ""; \
		echo "  Docker Compose reads its variables from that file. Without it,"; \
		echo "  the containers start with unexpanded credentials and Postgres"; \
		echo "  refuses the connection about ninety seconds later."; \
		echo ""; \
		echo "    make init-env"; \
		echo ""; \
		echo "  Generates $(ENV_FILE) with keys and offers a password per service."; \
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
		echo "[ERROR] Variables with no value in $(ENV_FILE):"; \
		for v in $$missing; do echo "      $$v"; done; \
		echo ""; \
		exit 1; \
	fi
	@echo "[INFO]  $(ENV_FILE) ... OK"

# ── Setup ─────────────────────────────────────────────────────────────────────
#
# .ci/scripts/check_deps.sh detecta el sistema, revisa Python 3.12, venv, pip,
# git, make, Homebrew/gestor de paquetes y Docker+Compose, e instala lo
# instalable con confirmación. No tiene target propio acá a propósito: los
# comandos de este archivo son independientes entre sí, y check_deps.sh no es
# uno de ellos — es un detalle interno de `setup`, que ya lo sourcea y llama a
# su main() internamente (para quedarse con PYTHON_BIN exportado). Exponerlo
# también como target lo correría dos veces seguidas en una instalación
# normal. Quien lo necesite standalone (el script ya soporta ese modo, ver su
# propio encabezado) lo invoca directo: `bash .ci/scripts/check_deps.sh`.
#
# `init-env` es igual de independiente: el primer comando de la secuencia
# documentada (`make init-env → make setup → ...`) y su único trabajo es
# crear $(ENV_FILE) con las claves generadas — no depende de `setup` ni de
# check_deps.sh.
#
# Lo que esto NO resuelve: Xcode Command Line Tools en una Mac que no las
# tiene todavía. `make` mismo —igual que `git`, `cc`, `clang`— es un binario
# "shim" de Xcode CLT: el sistema operativo intercepta su primera invocación
# y dispara el diálogo de instalación ANTES de que Make llegue a leer una sola
# línea de este archivo, prerrequisitos incluidos. Ningún target ni receta
# puede interceptar eso — ocurre un nivel por debajo de Make. Sigue siendo un
# prerrequisito manual de verdad, documentado como paso 0 (antes de cualquier
# `make`): instalar las CLT con `xcode-select --install`.
setup: check-env
	@echo "[INFO]  Running setup"
	@bash .ci/scripts/setup.sh

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
	@echo "[INFO]  Starting local stack"
	$(COMPOSE) --env-file $(ENV_FILE) up -d
	@echo ""
	@echo "[INFO]  Stack available at:"
	@echo "    Airflow  → http://localhost:8090"
	@echo "    Trino    → http://localhost:8081"
	@echo "    RustFS   → http://localhost:9001"
	@echo "    Superset → http://localhost:8088"
	@echo "    Marquez  → http://localhost:9100"
	@echo "    OpenBao  → http://localhost:8200"
	@echo "    Spark    → http://localhost:8082"
	@echo ""
	@echo "[INFO]  Credentials in: $(ENV_FILE)"
	@echo "[INFO]  Sample data: make dev-load-example"

dev-down: check-env
	$(COMPOSE) --env-file $(ENV_FILE) down

dev-logs: check-env
	$(COMPOSE) --env-file $(ENV_FILE) logs -f $(SERVICE)

dev-ps: check-env
	@$(COMPOSE) --env-file $(ENV_FILE) ps

# ── Reset ─────────────────────────────────────────────────────────────────────

dev-reset: check-env dev-build
	@echo "[INFO]  Full stack reset (volumes will be deleted)"
	$(COMPOSE) --env-file $(ENV_FILE) down -v
	@echo "[INFO]  Starting clean stack"
	$(COMPOSE) --env-file $(ENV_FILE) up -d
	@echo "[INFO]  Waiting for services to be ready (60s)"
	@sleep 60
	@bash .ci/scripts/init_users.sh $(ENV_FILE)
	@echo ""
	@echo "[INFO]  To load sample data: make dev-load-example"

# `down --rmi local` NO sirve aquí: borra solo las imágenes sin tag propio en el
# campo `image:`, y las tres del proyecto lo tienen (vektralforge/airflow,
# vektralforge/spark, vektralforge/hive-metastore). Compose las saltaba, así que
# un cambio en un Dockerfile nunca llegaba al contenedor. Se reconstruye explícito.
dev-build: check-env
	@echo "[INFO]  Rebuilding project images"
	$(COMPOSE) --env-file $(ENV_FILE) build

# Ahora que `dev-reset` construye siempre, lo que distingue a esta variante es
# ignorar la caché: es la que sirve cuando se sospecha de una capa cacheada y no
# de un Dockerfile desactualizado.
dev-reset-hard: check-env
	@echo "[INFO]  Extreme reset (deletes volumes and rebuilds with no cache)"
	$(COMPOSE) --env-file $(ENV_FILE) down -v
	@echo "[INFO]  Rebuilding images from scratch"
	$(COMPOSE) --env-file $(ENV_FILE) build --no-cache
	@$(MAKE) dev-reset

# ── Cargar datos de ejemplo ───────────────────────────────────────────────────

dev-load-example: check-env
	@echo "[INFO]  Loading sample data"
	@echo "  DAGs: indicadores_financieros_chile · arclim_riesgo_climatico_chile"
	@echo "  Sources: mindicador.cl · ARClim API (both public, no API key)"
	@echo "  Output: Delta tables in Trino + dashboards in Superset"
	@echo ""
	@bash .ci/scripts/load_example.sh $(ENV_FILE)

# Los DAGs como llegarían en Kubernetes: desde un GitDagBundle que clona el
# repositorio público, en vez del directorio montado. Es una prueba, no el modo
# de desarrollo; `make dev-up` vuelve al montaje. Ver compose.bundle-git.yml.
# La ref tiene que estar publicada en GitHub.
dev-bundle-git: check-env
	@echo "[INFO]  DAGs from GitDagBundle (ref: $(or $(VF_BUNDLE_REF),develop))"
	VF_BUNDLE_REF=$(VF_BUNDLE_REF) $(COMPOSE) -f infra/docker-compose/compose.bundle-git.yml \
		--env-file $(ENV_FILE) up -d airflow-dag-processor airflow-scheduler airflow-webserver
	@echo ""
	@echo "[INFO]  Each DAG run records the commit it was created from:"
	@echo "    $(COMPOSE) --env-file $(ENV_FILE) exec postgres sh -c \\"
	@echo "      'psql -U \$$POSTGRES_USER -d airflow -c \"select dag_id, run_id, bundle_name, bundle_version from dag_run order by id desc limit 5\"'"
	@echo "  Back to the mounted directory: make dev-up"

# El §2.9 dio a cada consumidor una cuenta acotada en vez de la raíz. Un permiso
# de más no da síntomas —el stack funciona igual—, así que la única forma de
# saberlo es intentarlo. Necesita el stack levantado.
dev-check-perms: check-env
	@echo "[INFO]  Checking that the pipeline account is scoped"
	@bash .ci/scripts/verificar_permisos.sh

# Los logs de las tareas van al bucket airflow-logs. Si no llegan, Airflow no
# avisa: las tareas corren igual. Tiene sentido después de dev-load-example.
dev-check-logs: check-env
	@echo "[INFO]  Checking that task logs reach the object store"
	@bash .ci/scripts/verificar_logs_remotos.sh

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
	@echo "[INFO]  Lint complete ... OK"

test-all: test-dags test-spark
	@echo "[INFO]  Tests run (see warnings above)"

detect-secrets:
	@bash .ci/scripts/detect_secrets.sh

# detect-secrets mira el árbol de trabajo; esto mira el historial. Un secreto
# borrado en un commit posterior sigue estando en el historial, y con el
# repositorio público sigue siendo público.
auditar-historial:
	@bash .ci/scripts/auditar_historial.sh

# Segundo modo del mismo guion. La lista de términos vive en
# .ci/identificadores-cliente.txt, que no se versiona; sin ella corren igual los
# patrones estructurales (IPs privadas, hosts internos, registros privados).
auditar-identificadores:
	@bash .ci/scripts/auditar_historial.sh identificadores

# ── Deploy ────────────────────────────────────────────────────────────────────

deploy-staging:
	@bash .ci/scripts/deploy_k3s.sh staging

deploy-prod:
	@read -p "[INFO]  Confirm deploy to PRODUCTION? (type 'yes'): " c; \
	if [ "$$c" = "yes" ]; then \
		bash .ci/scripts/deploy_k3s.sh prod; \
	else \
		echo "[INFO]  Deploy cancelled"; \
	fi

# ── Help ──────────────────────────────────────────────────────────────────────

help:
	@echo ""
	@echo "  VektralForge — available commands"
	@echo ""
	@echo "  Setup and local stack:"
	@printf '%s\t%s\n' \
		"make setup" "Creates .venv (Python 3.12) and installs dependencies" \
		"make init-env" "Creates $(ENV_FILE) with generated keys" \
		"make dev-up" "Starts the stack" \
		"make dev-down" "Stops the stack" \
		"make dev-ps" "Container status" \
		"make dev-logs" "Live logs (SERVICE=airflow-scheduler for a single one)" \
		"make dev-build" "Rebuilds images after changing a Dockerfile" \
		"make dev-reset" "Full reset (deletes volumes, recreates users)" \
		"make dev-reset-hard" "Extreme reset (deletes volumes and rebuilds images)" \
		"make dev-load-example" "Loads the sample pipelines and dashboards" \
		"make dev-check-perms" "Checks that the pipeline account is scoped" \
		"make dev-check-logs" "Checks that task logs reach the bucket" \
		"make dev-bundle-git" "DAGs from a GitDagBundle (VF_BUNDLE_REF=<branch|tag>)" \
	| awk -F'\t' '{c[NR]=$$1; d[NR]=$$2; if (length($$1)>w) w=length($$1)} END{for(i=1;i<=NR;i++) printf "    %-*s  %s\n", w, c[i], d[i]}'
	@echo ""
	@echo "  Code quality:"
	@printf '%s\t%s\n' \
		"make lint-all" "Full lint (Ruff + sqlfluff)" \
		"make test-all" "Full tests" \
		"make detect-secrets" "Credential scan (working tree)" \
		"make auditar-historial" "Credentials and identifiers (git history)" \
		"make auditar-identificadores" "Only external-infrastructure identifiers" \
	| awk -F'\t' '{c[NR]=$$1; d[NR]=$$2; if (length($$1)>w) w=length($$1)} END{for(i=1;i<=NR;i++) printf "    %-*s  %s\n", w, c[i], d[i]}'
	@echo ""
	@echo "  Deploy — PLANNED, not implemented:"
	@printf '%s\t%s\n' \
		"make deploy-staging" "Fails explaining what's missing" \
		"make deploy-prod" "Same" \
	| awk -F'\t' '{c[NR]=$$1; d[NR]=$$2; if (length($$1)>w) w=length($$1)} END{for(i=1;i<=NR;i++) printf "    %-*s  %s\n", w, c[i], d[i]}'
	@echo ""
	@echo "  First run:"
	@echo "    macOS only: if this machine has never run 'make', 'git' or similar"
	@echo "    tools, install Xcode Command Line Tools FIRST — xcode-select --install"
	@echo "    'make' itself is gated by them; without CLT it won't even start, so"
	@echo "    this text can't appear on screen to say so. Nothing below runs until"
	@echo "    that's done."
	@echo ""
	@echo "    make init-env             Generates $(ENV_FILE), offers a password per service"
	@echo "    make setup"
	@echo "    make dev-up"
	@echo "    make dev-load-example"
	@echo ""
	@echo "  Requirements: Python 3.12 · Docker Compose v2"
	@echo "  Variables:    $(ENV_FILE)"
	@echo "  [WARN]  Not supported on BSD architectures (FreeBSD, OpenBSD, NetBSD,"
	@echo "          DragonFly) — Docker Compose needs Linux kernel namespaces/cgroups."
	@echo ""
