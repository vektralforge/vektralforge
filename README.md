# lakeforge

**ALEPH SERVER LTDA. — Lakehouse Open Source Stack**

Mono-repositorio oficial del stack de datos: Apache Airflow, Apache Spark,
Delta Lake, MinIO, Trino, Hive Metastore y OpenBao. Desplegado sobre K3s
con CI/CD agnóstico.

---

## Estructura

```
lakeforge/
├── airflow/          # DAGs, plugins y tests de Apache Airflow
├── spark/            # Jobs PySpark (escritura ACID Delta Lake + ELT batch)
├── trino/            # Configuración de catálogos y conectores (lectura SQL)
├── hive/             # Migraciones DDL numeradas
├── superset/         # Exports de dashboards
├── infra/
│   ├── k3s/          # Manifiestos Kubernetes (staging + producción)
│   ├── docker-compose/ # Stack local completo
│   └── helm/         # Charts Helm personalizados
├── .ci/
│   ├── scripts/      # Lógica CI/CD portable (bash)
│   └── pipelines/    # Adaptadores YAML por plataforma CI/CD
└── docs/             # Documentación técnica
```

## Rol de cada motor de datos

| Motor  | Escribe Delta Lake | Lee Delta Lake | Streaming Kafka |
|--------|--------------------|----------------|-----------------|
| Spark  | ✓ ACID completo    | ✓              | ✓ Structured Streaming |
| Trino  | ✗ (solo lectura)   | ✓ SQL ad-hoc   | ✗               |

**Spark escribe. Trino lee.** Esta separación es la base de la arquitectura.

---

## Onboarding rápido (< 30 minutos)

### 1. Requisitos previos

```bash
docker --version        # >= 24.0
docker compose version  # >= 2.20
python3 --version       # >= 3.11
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

| Servicio        | URL                         | Credenciales              |
|-----------------|-----------------------------|---------------------------|
| Airflow UI      | http://localhost:8080        | admin / admin             |
| Trino UI        | http://localhost:8081        | —                         |
| MinIO Console   | http://localhost:9001        | minioadmin / minioadmin   |
| Superset        | http://localhost:8088        | admin / admin             |
| OpenBao UI      | http://localhost:8200        | root token: dev-root-token|
| Hive Metastore  | thrift://localhost:9083      | (interno)                 |

### 4. Detener

```bash
make dev-down
```

---

## Comandos disponibles

```bash
make setup           # Instala dependencias locales
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
make deploy-prod     # Deploy K3s producción
```

## Gestión de secretos

| Ambiente   | Herramienta    | Licencia |
|------------|----------------|----------|
| Local      | .env file      | —        |
| Staging    | Sealed Secrets | Apache 2.0 |
| Producción | OpenBao        | MPL 2.0  |

OpenBao es un fork open source de HashiCorp Vault bajo la Linux Foundation.
API 100% compatible. Sin restricciones de licencia BSL.

---

ALEPH SERVER LTDA. — Documento técnico confidencial
