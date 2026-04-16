# lakeforge

**ALEPH SERVER LTDA. — Lakehouse Open Source Stack**

Mono-repositorio oficial del stack de datos: Apache Airflow, Apache Spark,
Delta Lake, MinIO, Trino y OpenBao. Desplegado sobre K3s con CI/CD agnóstico.

Documentación completa: [docs/arquitectura.md](docs/arquitectura.md)

---

## Stack de versiones

| Componente | Versión | Python requerido |
|---|---|---|
| Apache Airflow | 2.9.1 | >= 3.12 |
| PySpark | 3.5.3 | >= 3.12 |
| delta-spark | 3.2.0 | >= 3.12 |
| Trino | 448 | — |
| OpenBao | 2.0.0 | — |
| MinIO | 2024-04 | — |

---

## Estructura

```
lakeforge/
├── airflow/            # DAGs, plugins y tests de Apache Airflow
├── spark/              # Jobs PySpark (escritura ACID Delta Lake + ELT batch)
├── trino/              # Configuración de catálogos y conectores (lectura SQL)
├── hive/               # Migraciones DDL numeradas
├── superset/           # Exports de dashboards
├── infra/
│   ├── k3s/            # Manifiestos Kubernetes (staging + producción)
│   ├── docker-compose/ # Stack local completo
│   └── helm/           # Charts Helm personalizados
├── .ci/
│   ├── scripts/        # Lógica CI/CD portable (bash)
│   └── pipelines/      # Adaptadores YAML por plataforma CI/CD
└── docs/               # Documentación técnica
    └── arquitectura.md # Arquitectura completa del stack
```

---

## Rol de cada motor de datos

| Motor | Escribe Delta Lake | Lee Delta Lake | Streaming Kafka |
|---|---|---|---|
| Spark | ✓ ACID completo | ✓ | ✓ Structured Streaming |
| Trino | ✗ (solo lectura) | ✓ SQL ad-hoc | ✗ |

**Spark escribe. Trino lee.** Esta separación es la base de la arquitectura.

---

## Onboarding rápido (< 30 minutos)

### 1. Requisitos previos

```bash
docker --version        # >= 24.0
docker compose version  # >= 2.20
python3.12 --version    # >= 3.12 (brew install python@3.12)
make --version
```

> Docker Desktop requiere mínimo **8 GB de RAM** asignados (Settings → Resources → Memory).

### 2. Clonar y configurar

```bash
git clone https://bitbucket.org/alephserver/lakeforge.git
cd lakeforge
make setup
```

`make setup` crea automáticamente un virtualenv en `.venv/` con Python 3.12
e instala todas las dependencias del proyecto.

### 3. Activar el entorno (cada sesión nueva)

```bash
source .venv/bin/activate
```

### 4. Levantar stack local

```bash
make dev-up
```

| Servicio | URL | Credenciales |
|---|---|---|
| Airflow UI | http://localhost:8090 | admin / admin |
| Trino UI | http://localhost:8081 | — |
| MinIO Console | http://localhost:9001 | minioadmin / minioadmin |
| Superset | http://localhost:8088 | admin / admin |
| OpenBao UI | http://localhost:8200 | root token: dev-root-token |
| Spark Master | http://localhost:8082 | — |

### 5. Detener

```bash
make dev-down
```

---

## Comandos disponibles

```bash
make setup           # Crea .venv e instala dependencias (Python 3.12)
make dev-up          # Levanta stack Docker Compose
make dev-down        # Detiene stack
make dev-logs        # Logs en tiempo real
make dev-reset       # Reset completo (borra volúmenes)
make lint-dags       # Lint DAGs Airflow (Ruff)
make test-dags       # Tests DAGs (pytest)
make lint-spark      # Lint Spark jobs (Ruff)
make test-spark      # Tests Spark (pytest + chispa)
make lint-sql        # Lint SQL Trino (sqlfluff)
make lint-all        # Lint completo
make test-all        # Tests completos
make detect-secrets  # Escaneo de secretos
make deploy-staging  # Deploy K3s staging
make deploy-prod     # Deploy K3s producción (requiere confirmación)
```

---

## Pipeline de prueba

El repositorio incluye un pipeline de ejemplo que valida el stack completo:

```bash
# Desde la UI de Airflow (http://localhost:8090)
# DAG: bronze_clientes_ejemplo → Trigger DAG ▶

# O desde terminal:
docker exec docker-compose-airflow-scheduler-1 \
  airflow dags trigger bronze_clientes_ejemplo
```

**Flujo:**
```
Airflow DAG
    ↓ genera CSV sintético
MinIO raw/clientes/
    ↓ Spark lee CSV y escribe Delta Lake ACID
MinIO bronze/clientes/
    ↓ Trino consulta SQL
Superset visualiza
```

---

## Gestión de secretos

| Ambiente | Herramienta | Licencia |
|---|---|---|
| Local | .env file | — |
| Staging | Sealed Secrets | Apache 2.0 |
| Producción | **OpenBao** | MPL 2.0 |

OpenBao es un fork open source de HashiCorp Vault bajo la Linux Foundation.
API 100% compatible con Vault. Sin restricciones de licencia BSL.

---

## Notas de compatibilidad

- **Python 3.14 no soportado**: pandas y Airflow aún no tienen wheels para 3.14. Usar siempre Python 3.12.
- **delta-spark 3.2.0**: versión compatible con Spark 3.5.x. delta-spark 4.0.0 requiere Spark 4.x.
- **apache-airflow-providers-amazon excluido**: arrastra `sqlalchemy-redshift` incompatible con SQLAlchemy 2.x. MinIO se conecta vía `boto3` directamente.
- **Trino usa file metastore**: elimina dependencia de Hive Metastore para mayor estabilidad en PoC local.
- **Docker Desktop**: asignar mínimo 8 GB RAM para evitar OOM kills con el stack completo.

---

## Documentación

- [docs/arquitectura.md](docs/arquitectura.md) — Arquitectura completa: stack, flujo de datos, GitOps, CI/CD, secretos, gobernanza, hardware y hoja de ruta.

---

ALEPH SERVER LTDA. — Documento técnico confidencial
