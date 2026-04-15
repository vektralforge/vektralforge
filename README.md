# lakeforge

**ALEPH SERVER LTDA. — Lakehouse Open Source Stack**

Mono-repositorio oficial del stack de datos basado en Apache Airflow, Apache Spark,
Delta Lake, MinIO, Trino y Hive Metastore. Desplegado sobre K3s con CI/CD agnóstico.

---

## Estructura

```
lakeforge/
├── airflow/          # DAGs, plugins y tests de Apache Airflow
├── spark/            # Jobs PySpark y tests
├── trino/            # Configuración de catálogos y conectores
├── hive/             # Migraciones DDL numeradas
├── superset/         # Exports de dashboards
├── infra/
│   ├── k3s/          # Manifiestos Kubernetes (staging + producción)
│   ├── docker-compose/ # Stack local completo
│   └── helm/         # Charts Helm personalizados
├── .ci/
│   ├── scripts/      # Lógica CI/CD portable (bash)
│   └── pipelines/    # Adaptadores YAML por plataforma
└── docs/             # Documentación técnica
```

---

## Onboarding rápido (< 30 minutos)

### 1. Requisitos previos

```bash
# Ubuntu 22.04 / macOS 13+
docker --version      # >= 24.0
docker compose version # >= 2.20
python3 --version     # >= 3.11
make --version
```

### 2. Clonar y configurar

```bash
git clone https://bitbucket.org/alephserver/lakeforge.git
cd lakeforge
make setup
```

### 3. Levantar stack local

```bash
make dev-up
```

Servicios disponibles tras el arranque:

| Servicio        | URL                        | Credenciales         |
|-----------------|----------------------------|----------------------|
| Airflow UI      | http://localhost:8080       | admin / admin        |
| Trino UI        | http://localhost:8081       | —                    |
| MinIO Console   | http://localhost:9001       | minioadmin / minioadmin |
| Superset        | http://localhost:8088       | admin / admin        |
| Hive Metastore  | thrift://localhost:9083     | (interno)            |

### 4. Detener stack

```bash
make dev-down
```

---

## Comandos disponibles

```bash
make setup          # Instala todas las dependencias locales
make dev-up         # Levanta stack local con Docker Compose
make dev-down       # Detiene stack local
make lint-dags      # Lint sobre airflow/dags/ (Ruff)
make test-dags      # Tests unitarios de DAGs (pytest)
make lint-spark     # Lint sobre spark/jobs/ (Ruff)
make test-spark     # Tests PySpark (pytest + chispa)
make lint-sql       # Lint SQL sobre trino/catalog/ (sqlfluff)
make lint-all       # Lint completo de todos los módulos
make test-all       # Tests completos de todos los módulos
make detect-secrets # Escaneo de secretos en el repo
make deploy-staging # Deploy a K3s namespace staging
make deploy-prod    # Deploy a K3s namespace producción (requiere aprobación)
```

---

## Estrategia de branching

```
feature/*  →  local (Docker Compose)
develop    →  staging (K3s namespace staging)
main       →  producción (K3s namespace prod)
```

---

## Documentación

- [Arquitectura completa](docs/arquitectura.md)
- [Guía de DAGs Airflow](docs/airflow.md)
- [Guía de jobs Spark](docs/spark.md)
- [Configuración Trino](docs/trino.md)
- [Gestión de secretos](docs/secretos.md)
- [Requisitos de hardware](docs/hardware.md)

---

ALEPH SERVER LTDA. — Documento técnico confidencial
