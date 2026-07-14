# Base de Conocimiento — lakeforge

## 📋 RESUMEN EJECUTIVO

**Proyecto:** lakeforge — Lakehouse Open Source Stack
**Empresa:** ALEPH SERVER LTDA.
**Estado:** PoC validado y operativo — Fase 1 completada ✅
**Repositorio:** bitbucket.org/alephserver/lakeforge
**Branch activo:** develop
**Año:** 2026

### Entregables actuales
- ✅ Stack Docker Compose con 13 servicios operativos
- ✅ Pipeline validado end-to-end: Airflow → Spark → Delta Lake → Trino → Superset
- ✅ DAG indicadores financieros Chile (mindicador.cl — UF, IPC, Dólar, Euro, UTM, TPM)
- ✅ DAG clientes ejemplo (datos sintéticos raw → bronze)
- ✅ CI/CD Escenario 1 (lint + detect-secrets + pre-commit)
- ✅ Gestión de credenciales con make dev-reset leyendo desde .env
- ✅ Documentación arquitectura con diagramas SVG en docs/img/
- ✅ Documentos comparativa: on-premise vs AWS vs GCP vs AliCloud

---

## 🏗️ ARQUITECTURA DEL STACK

### Stack técnico completo

| Componente | Versión | Puerto | Rol |
|---|---|---|---|
| Apache Airflow | 2.9.1 | 8090 | Orquestación ETL batch |
| Apache Spark Master | 3.5.3 | 8082/7077 | Procesamiento ACID — escritura Delta Lake |
| Apache Spark Worker | 3.5.3 | 8083 | Worker de procesamiento |
| Delta Lake | 3.2.0 | — | Formato ACID sobre MinIO |
| MinIO | 2024-04 | 9000/9001 | Object storage S3-compatible |
| Trino | 448 | 8081 | Motor SQL — lectura Delta Lake |
| Hive Metastore | 4.0.0 | 9083 | Catálogo de tablas |
| Apache Kafka | 7.6.1 (CP) | 9092 | Streaming tiempo real |
| Zookeeper | 7.6.1 (CP) | 2181 | Coordinación Kafka |
| OpenBao | 2.1.0 | 8200 | Gestión de credenciales MPL 2.0 |
| Apache Superset | 3.1.3 | 8088 | Visualización BI |
| Redis | 7.2 | 6379 | Caché Superset |
| PostgreSQL | 15 | 5432 | Metastore Airflow + Hive |

### Regla fundamental del lakehouse

> **Spark escribe (ACID). Trino lee (SQL).**

| Motor | Escribe Delta Lake | Lee Delta Lake | Streaming |
|---|---|---|---|
| Apache Spark | ✓ MERGE, UPDATE, DELETE, VACUUM | ✓ | ✓ Structured Streaming |
| Trino | ✗ Solo lectura | ✓ SQL ad-hoc | ✗ |

### Capas del Data Lake (MinIO)

```
raw/        → Datos crudos sin transformar    (retención 30 días)
bronze/     → Delta Lake ACID validado        (retención 90 días)
silver/     → Delta Lake limpio y enriquecido (retención indefinida)
gold/       → Agregaciones y métricas         (retención indefinida)
checkpoints/→ Spark Structured Streaming      (retención 7 días)
```

---

## 📁 ESTRUCTURA DEL REPOSITORIO

```
lakeforge/
├── airflow/
│   ├── dags/
│   │   ├── dag_bronze_ejemplo.py          # Pipeline sintético validado end-to-end
│   │   ├── dag_cmf_indicadores.py         # API CMF Chile (requiere API Key)
│   │   └── dag_indicadores_financieros.py # mindicador.cl (sin API Key) ← ACTIVO
│   ├── plugins/                           # Operadores y hooks custom
│   └── tests/                            # Tests unitarios de DAGs
├── spark/
│   └── jobs/
│       ├── bronze_clientes.py             # Job Spark pipeline clientes ejemplo
│       ├── bronze_cmf.py                  # Job Spark indicadores CMF
│       ├── bronze_indicadores.py          # Job Spark indicadores mindicador.cl ← ACTIVO
│       └── register_tables.py             # Registro tablas en Trino
├── trino/
│   └── catalog/
│       └── delta.properties               # Conector Delta Lake con file metastore
├── hive/
│   └── schemas/                          # DDL numeradas (convención Flyway)
├── superset/
│   └── dashboards/
│       └── setup_superset_dashboard.py   # Script auto-configuración dashboard
├── infra/
│   ├── docker-compose/
│   │   ├── docker-compose.yml            # Stack completo 13 servicios
│   │   ├── .env                          # Credenciales locales (NO versionado)
│   │   ├── hive/Dockerfile               # Driver PostgreSQL JDBC
│   │   ├── spark/Dockerfile              # JARs delta+hadoop-aws pre-instalados
│   │   └── superset/Dockerfile           # trino[sqlalchemy] incluido
│   ├── k3s/                              # Manifiestos Kubernetes producción
│   └── helm/                            # Charts Helm personalizados
├── .ci/
│   ├── scripts/
│   │   ├── setup.sh                      # Crea .venv Python 3.12
│   │   ├── init_users.sh                 # Crea usuarios + buckets MinIO
│   │   └── detect_secrets.sh             # Escaneo de credenciales
│   └── pipelines/                        # Adaptadores YAML CI/CD por plataforma
├── docs/
│   ├── arquitectura.md                   # 16 secciones con diagramas SVG
│   └── img/                             # 6 diagramas SVG del stack
│       ├── 01-flujo-datos.svg
│       ├── 02-stack-servicios.svg
│       ├── 03-capas-lakehouse.svg
│       ├── 04-gestion-secretos.svg
│       ├── 05-cicd-ambientes.svg
│       └── 06-hoja-de-ruta.svg
├── .env.example                          # Variables requeridas (SÍ versionado)
├── .secrets.baseline                     # Baseline detect-secrets
├── Makefile                              # Interfaz unificada de comandos
└── README.md                            # Guía de onboarding
```

---

## ⚙️ COMANDOS MAKE

```bash
make setup           # Crea .venv Python 3.12 e instala dependencias
make dev-up          # Levanta stack Docker Compose (requiere .env)
make dev-down        # Detiene stack
make dev-logs        # Logs en tiempo real
make dev-reset       # Reset completo: borra volúmenes, recrea usuarios desde .env
make dev-reset-hard  # Reset extremo: borra volúmenes + imágenes custom
make lint-all        # Lint completo (Ruff + sqlfluff)
make test-all        # Tests completos
make detect-secrets  # Escaneo de credenciales
make deploy-staging  # Deploy K3s staging
make deploy-prod     # Deploy K3s producción (requiere confirmación)
make help            # Lista todos los comandos disponibles
```

### URLs del stack tras make dev-up

| Servicio | URL | Credenciales |
|---|---|---|
| Airflow UI | http://localhost:8090 | admin / admin (según .env) |
| Trino UI | http://localhost:8081 | — |
| MinIO Console | http://localhost:9001 | minioadmin / minioadmin (según .env) |
| Superset | http://localhost:8088 | admin / admin (según .env) |
| OpenBao API | http://localhost:8200 | token: dev-root-token (según .env) |
| Spark Master | http://localhost:8082 | — |

---

## 🔑 GESTIÓN DE CREDENCIALES

### Arquitectura de secretos por ambiente

| Ambiente | Herramienta | Licencia | Notas |
|---|---|---|---|
| Local | `.env` file | — | Basado en `.env.example`. NUNCA commitear |
| Staging | Sealed Secrets | Apache 2.0 | Cifrado en Git, descifrado por K3s |
| Producción | **OpenBao** | MPL 2.0 | Fork Vault, Linux Foundation, API compatible |

### Variables de entorno requeridas (.env)

```bash
# PostgreSQL (definir primero — otras variables dependen de estos)
POSTGRES_USER=lakeforge
POSTGRES_PASSWORD=lakeforge

# Usuarios admin (leídos por make dev-reset)
AIRFLOW_ADMIN_USER=admin
AIRFLOW_ADMIN_PASSWORD=admin
AIRFLOW_ADMIN_EMAIL=admin@alephserver.cl
SUPERSET_ADMIN_USER=admin
SUPERSET_ADMIN_PASSWORD=admin
SUPERSET_ADMIN_EMAIL=admin@alephserver.cl

# Apache Airflow
AIRFLOW__CORE__EXECUTOR=LocalExecutor
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://lakeforge:lakeforge@postgres:5432/airflow  # pragma: allowlist secret
# IMPORTANTE: si cambias POSTGRES_USER/PASSWORD, actualizar también esta línea
AIRFLOW__CORE__FERNET_KEY=<generar con python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())">
AIRFLOW__WEBSERVER__SECRET_KEY=<generar con python3 -c "import secrets; print(secrets.token_hex(32))">

# MinIO
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin

# OpenBao
OPENBAO_ADDR=http://openbao:8200
OPENBAO_TOKEN=dev-root-token

# Superset
SUPERSET_SECRET_KEY=<generar con python3 -c "import secrets; print(secrets.token_hex(32))">

# API CMF Chile (opcional — para dag_cmf_indicadores)
CMF_API_KEY=<registrar en https://api.cmfchile.cl/apps/contactanos/index.html>
```

### Leer secretos desde OpenBao (Python)

```python
import hvac, os

client = hvac.Client(
    url=os.getenv("OPENBAO_ADDR", "http://openbao:8200"),
    token=os.getenv("OPENBAO_TOKEN"),
)
secret = client.secrets.kv.v2.read_secret_version(path="sqlserver/credentials")
password = secret["data"]["data"]["password"]
```

---

## 🔄 PIPELINES DAG ACTIVOS

### DAG 1: indicadores_financieros_chile ← PRINCIPAL ACTIVO

**Fuente:** mindicador.cl (sin API Key, gratuito)
**Schedule:** `0 10 * * MON-FRI` (Lunes a viernes 10:00 AM)
**Archivo:** `airflow/dags/dag_indicadores_financieros.py`

**Indicadores:**
| Indicador | Tipo | Frecuencia publicación |
|---|---|---|
| UF | Diario | Cada día hábil |
| Dólar | Diario | Cada día hábil |
| Euro | Diario | Cada día hábil |
| UTM | Diario | Cada día hábil |
| TPM | Diario | Cada día hábil |
| IPC | **Mensual** | ~día 8 de cada mes ← WARNING si no está |

**Flujo de tareas:**
```
extract_indicadores → transform_bronze → validar_bronze
       ↓                    ↓                  ↓
raw/indicadores/       Spark PySpark      Verifica Parquet
fecha={ds}/            escribe Delta      en bronze/
  snapshot_diario.json  Lake ACID
  uf_2026.json
  dolar_2026.json
  ...
```

**Tablas Delta Lake generadas:**
```
s3://bronze/indicadores_uf/
s3://bronze/indicadores_dolar/
s3://bronze/indicadores_euro/
s3://bronze/indicadores_utm/
s3://bronze/indicadores_tpm/
```

**Validación:**
- Indicadores diarios (UF, Dólar, Euro, UTM, TPM): ERROR si no tienen datos
- IPC: WARNING (no ERROR) si no tiene datos — publicación mensual normal

### DAG 2: bronze_clientes_ejemplo

**Fuente:** Datos sintéticos generados en el DAG
**Schedule:** Manual (no programado)
**Archivo:** `airflow/dags/dag_bronze_ejemplo.py`

**Flujo:**
```
generar_y_subir_raw → transformar_a_bronze → validar_resultado
       ↓                     ↓                     ↓
Genera CSV sintético    Spark escribe Delta    Verifica tabla
s3://raw/clientes/      s3://bronze/           en Trino
                        clientes_v2/
```

**Tabla Trino:** `delta.bronze.clientes_v2`

### DAG 3: cmf_indicadores_financieros ← PENDIENTE API KEY

**Estado:** Requiere API Key de CMF Chile
**Solicitar:** https://api.cmfchile.cl/apps/contactanos/index.html
**Error actual:** HTTP 421 con API key de ejemplo
**Indicadores:** UF, IPC, TMC, Dólar, Euro, Yen, Libra Esterlina

---

## 🗄️ TRINO — CONFIGURACIÓN Y USO

### Archivo de configuración principal

**Ruta:** `trino/catalog/delta.properties`

```properties
connector.name=delta_lake
hive.metastore=file
hive.metastore.catalog.dir=/tmp/trino-file-metastore
hive.s3-file-system-type=TRINO
hive.s3.endpoint=http://minio:9000
hive.s3.aws-access-key=minioadmin
hive.s3.aws-secret-key=minioadmin
hive.s3.path-style-access=true
hive.s3.ssl.enabled=false
delta.security=ALLOW_ALL
delta.register-table-procedure.enabled=true
delta.enable-non-concurrent-writes=true
delta.metadata.cache-ttl=10m
```

### Registrar tablas en Trino

```sql
-- Crear schema
CREATE SCHEMA IF NOT EXISTS delta.bronze WITH (location = 's3://bronze/');

-- Registrar tabla individual
CALL delta.system.register_table(
    schema_name => 'bronze',
    table_name  => 'clientes_v2',
    table_location => 's3://bronze/clientes_v2'
);

-- Registrar todas las tablas de indicadores
CALL delta.system.register_table(schema_name => 'bronze', table_name => 'indicadores_uf',    table_location => 's3://bronze/indicadores_uf');
CALL delta.system.register_table(schema_name => 'bronze', table_name => 'indicadores_dolar',  table_location => 's3://bronze/indicadores_dolar');
CALL delta.system.register_table(schema_name => 'bronze', table_name => 'indicadores_euro',   table_location => 's3://bronze/indicadores_euro');
CALL delta.system.register_table(schema_name => 'bronze', table_name => 'indicadores_utm',    table_location => 's3://bronze/indicadores_utm');
CALL delta.system.register_table(schema_name => 'bronze', table_name => 'indicadores_tpm',    table_location => 's3://bronze/indicadores_tpm');
```

### Vista comparativa de indicadores

```sql
-- Crear vista unificada para dashboard Superset
CREATE OR REPLACE VIEW delta.bronze.indicadores_todos AS
SELECT fecha, valor, indicador, nombre FROM delta.bronze.indicadores_uf
UNION ALL
SELECT fecha, valor, indicador, nombre FROM delta.bronze.indicadores_dolar
UNION ALL
SELECT fecha, valor, indicador, nombre FROM delta.bronze.indicadores_euro
UNION ALL
SELECT fecha, valor, indicador, nombre FROM delta.bronze.indicadores_utm
UNION ALL
SELECT fecha, valor, indicador, nombre FROM delta.bronze.indicadores_tpm;
```

### Queries de verificación

```sql
-- Ver todas las tablas
SHOW TABLES IN delta.bronze;

-- Contar registros por indicador
SELECT indicador, COUNT(*) as registros, MIN(fecha) as desde, MAX(fecha) as hasta
FROM delta.bronze.indicadores_todos
GROUP BY indicador
ORDER BY indicador;

-- Último valor de cada indicador
SELECT indicador, MAX(fecha) as ultima_fecha, MAX(valor) as ultimo_valor
FROM delta.bronze.indicadores_todos
GROUP BY indicador;
```

---

## 📊 SUPERSET — CONFIGURACIÓN

### Conexión Trino en Superset

**SQLAlchemy URI:** `trino://trino@trino:8080/delta`

**Pasos para configurar:**
1. http://localhost:8088 → `+` → **Connect database**
2. Seleccionar **Trino**
3. URI: `trino://trino@trino:8080/delta`
4. **Test Connection** → debe decir "Connection looks good!"
5. **Connect**

**Nota:** Si aparece `Could not load database driver: TrinoEngineSpec`, reinstalar driver:
```bash
docker exec -u root docker-compose-superset-1 \
  pip install "trino[sqlalchemy]" --quiet
docker compose -f infra/docker-compose/docker-compose.yml restart superset
```

### Configurar dashboard automáticamente

```bash
# Registrar tablas en Trino y crear vista
docker exec docker-compose-trino-1 trino --execute "
CREATE SCHEMA IF NOT EXISTS delta.bronze WITH (location = 's3://bronze/');
CALL delta.system.register_table(schema_name => 'bronze', table_name => 'indicadores_uf', table_location => 's3://bronze/indicadores_uf');
-- ... (resto de tablas)
CREATE OR REPLACE VIEW delta.bronze.indicadores_todos AS ...;
"

# Ejecutar script de setup del dashboard
docker cp superset/dashboards/setup_superset_dashboard.py \
  docker-compose-superset-1:/tmp/setup_superset_dashboard.py
docker exec docker-compose-superset-1 \
  python3 /tmp/setup_superset_dashboard.py
```

**URL del dashboard:** http://localhost:8088/superset/dashboard/indicadores-financieros-chile/

### Limpiar sesión Superset (si hay error 500 o login inválido)

```bash
# Opción 1: Limpiar sesiones en PostgreSQL
docker exec docker-compose-postgres-1 psql -U lakeforge -d airflow \
  -c "DELETE FROM session;"
docker compose -f infra/docker-compose/docker-compose.yml restart superset

# Opción 2: Limpiar caché Redis
docker exec docker-compose-redis-1 redis-cli FLUSHALL
docker compose -f infra/docker-compose/docker-compose.yml restart superset

# Opción 3: Recrear usuario admin
docker exec docker-compose-superset-1 superset db upgrade
docker exec docker-compose-superset-1 superset fab create-admin \
  --username admin --firstname Admin --lastname Lakeforge \
  --email admin@alephserver.cl --password admin
docker exec docker-compose-superset-1 superset init
```

---

## 🐛 SOLUCIÓN DE PROBLEMAS CONOCIDOS

### Error: NoSuchBucket al ejecutar DAG

**Causa:** Los buckets MinIO no existen (después de make dev-reset)
**Solución:**
```bash
bash .ci/scripts/init_users.sh infra/docker-compose/.env
```
Esto crea automáticamente: `raw/`, `bronze/`, `silver/`, `gold/`, `checkpoints/`

### Error: antlr4-runtime JAR corrupto en Spark

**Síntoma:** `impossible to move part file to definitive one: antlr4-runtime-4.9.3.jar`
**Solución:**
```bash
# Limpiar caché corrupto
docker exec docker-compose-spark-master-1 \
  rm -f /home/spark/.ivy2/cache/org.antlr/antlr4-runtime/jars/antlr4-runtime-4.9.3.jar \
        /home/spark/.ivy2/cache/org.antlr/antlr4-runtime/jars/antlr4-runtime-4.9.3.jar.part

# Instalar directamente en /opt/spark/jars/
docker exec -u root docker-compose-spark-master-1 \
  curl -L -o /opt/spark/jars/antlr4-runtime-4.9.3.jar \
  https://repo1.maven.org/maven2/org/antlr/antlr4-runtime/4.9.3/antlr4-runtime-4.9.3.jar
```

### Error: HTTP 421 en DAG CMF

**Causa:** API Key de CMF inválida o de ejemplo
**Solución:** Registrar API Key real en https://api.cmfchile.cl/apps/contactanos/index.html
**Alternativa:** Usar `dag_indicadores_financieros.py` con mindicador.cl (sin API Key)

### Error: Airflow webserver unhealthy

**Causa:** Healthcheck demasiado estricto — el webserver tarda en arrancar
**Verificar:** `curl -s -o /dev/null -w "%{http_code}" http://localhost:8090/health`
Si devuelve 200, el servicio funciona aunque marque unhealthy.

### Error: Superset error 500 tras make dev-reset

**Causa:** SECRET_KEY cambió entre resets — sesiones inválidas
**Solución:**
```bash
docker exec docker-compose-superset-1 superset db upgrade
docker exec docker-compose-superset-1 superset fab delete-user --username admin 2>/dev/null || true
docker exec docker-compose-superset-1 superset fab create-admin \
  --username admin --firstname Admin --lastname Lakeforge \
  --email admin@alephserver.cl --password admin
docker exec docker-compose-superset-1 superset init
docker exec docker-compose-postgres-1 psql -U lakeforge -d airflow -c "DELETE FROM session;"
docker compose -f infra/docker-compose/docker-compose.yml restart superset
```

### Error: make dev-reset no toma credenciales del .env

**Causa:** Make no puede interpolar variables con `__` doble guión
**Solución actual:** El Makefile usa `grep` directo en `.ci/scripts/init_users.sh`
Verificar: `grep AIRFLOW_ADMIN_PASSWORD infra/docker-compose/.env`

### Error: detect-secrets bloquea .env.example

**Causa:** URLs con usuario:password son detectadas como Basic Auth Credentials
**Solución:** Agregar `# pragma: allowlist secret` al final de la línea
```bash
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://lakeforge:lakeforge@postgres:5432/airflow  # pragma: allowlist secret
```
**Actualizar baseline:**
```bash
source .venv/bin/activate
detect-secrets scan > .secrets.baseline
git add .secrets.baseline
```

### OpenBao UI no disponible

**Mensaje:** "OpenBao UI is not available in this binary"
**Causa:** El binario de desarrollo no incluye UI web
**Estado:** Normal — la API REST funciona completamente
**Verificar API:** `curl -s -o /dev/null -w "%{http_code}" http://localhost:8200/v1/sys/health` → debe devolver 200

---

## 🔧 NOTAS DE COMPATIBILIDAD CRÍTICAS

| Componente | Restricción | Razón |
|---|---|---|
| **Python** | Usar 3.12 obligatoriamente | Python 3.14 no soportado — pandas sin wheels |
| **delta-spark** | Usar 3.2.0 (no 4.0.0) | delta-spark 4.0.0 requiere Spark 4.x |
| **airflow-providers-amazon** | Excluido del requirements | Arrastra sqlalchemy-redshift incompatible con SQLAlchemy 2.x. MinIO usa boto3 directo |
| **bitnami/spark** | No usar — archivado sept 2025 | Usar `apache/spark:3.5.3` |
| **Trino file metastore** | Más estable que Hive Metastore | El Hive Metastore puede fallar en PoC. File metastore local es más confiable |
| **Docker Desktop RAM** | Asignar mínimo 8 GB | Settings → Resources → Memory. OOM kills con stack completo si hay menos |
| **OpenBao versión** | Usar 2.1.0 (no 2.0.0) | 2.0.0 tiene issues con algunos endpoints |

---

## 🚀 CI/CD Y BRANCHING

### Estrategia de branches

```
main        → Producción (K3s namespace prod)
develop     → Staging (K3s namespace staging) ← branch activo
feature/*   → Desarrollo local (Docker Compose)
```

### Pipeline CI/CD agnóstico

El CI/CD opera en dos niveles:
- **Nivel 1 — lógica portable:** `.ci/scripts/` (bash, funciona en cualquier plataforma)
- **Nivel 2 — adaptadores:** `.ci/pipelines/` (YAML por plataforma: Bitbucket, GitHub Actions, Azure DevOps)

### Escenario CI/CD actual: Escenario 1 (básico)

```
Push → pre-commit hooks:
  ✓ trim trailing whitespace
  ✓ fix end of files
  ✓ check yaml
  ✓ check json
  ✓ check for merge conflicts
  ✓ check for added large files
  ✓ don't commit to branch (protege main)
  ✓ detect-secrets
  ✓ ruff (lint Python)
  ✓ ruff-format
```

---

## ☁️ DESPLIEGUE EN NUBE

### Comparativa de plataformas (validada 2026)

| Plataforma | Costo PoC/mes | Región Chile | Managed Airflow | Recomendado para |
|---|---|---|---|---|
| **On-Premise K3s** | ~$53 (Hetzner AX42) | ✓ Control total | Manual Docker | Clientes chilenos con datos regulados |
| **GCP** | ~$580 | ✓ southamerica-west1 | ✓ Managed Airflow Gen3 | Nube pública con datos en Chile |
| **AWS** | ~$727 | ✗ São Paulo | ✓ MWAA $364/mes | Clientes con ecosistema AWS existente |
| **AliCloud** | ~$400 | ✗ México | ✗ Manual en ACK | Clientes con operaciones en Asia |

### Supuestos de carga en precios

**PoC:** 500MB-1GB/día ingestado · 5-10 DAGs · Spark 2h/día · Kafka <1MB/s · 20-50 queries/día
**Producción HA:** 10-50GB/día · 50-100 DAGs · Spark 24/7 · Kafka 10-50MB/s · 200-500 queries/día

### Portabilidad del código

| Archivo | On-Premise | AWS | GCP | AliCloud |
|---|---|---|---|---|
| `airflow/dags/*.py` | ✓ Sin cambios | ✓ Sin cambios | ✓ Sin cambios | ✓ Sin cambios |
| `spark/jobs/*.py` | ✓ Sin cambios | ✓ Sin cambios | ✓ Sin cambios | ✓ Sin cambios |
| `.env` | Base | Cambiar endpoints | Cambiar endpoints | Cambiar endpoints |
| `trino/catalog/delta.properties` | ✓ Sin cambios | Cambiar metastore URI | Cambiar metastore URI | Cambiar metastore URI |

---

## 📚 DOCUMENTOS DE REFERENCIA

| Documento | Ubicación | Descripción |
|---|---|---|
| Arquitectura completa | `docs/arquitectura.md` | 16 secciones con diagramas SVG. Stack, flujo datos, CI/CD, secretos, hardware, roadmap |
| Arquitectura AWS | `docs/lakeforge_arquitectura_aws.docx` | Comparativa on-premise vs AWS con costos, roadmap migración |
| Comparativa 4 nubes | `docs/lakeforge_comparativa_plataformas.docx` | On-premise vs AWS vs GCP vs AliCloud con supuestos de carga |
| README onboarding | `README.md` | Guía de inicio rápido en < 30 minutos |
| .env.example | `.env.example` | Todas las variables de entorno documentadas |

### Diagramas SVG disponibles

| Archivo | Contenido |
|---|---|
| `docs/img/01-flujo-datos.svg` | Pipeline end-to-end: fuentes → MinIO → Spark → Trino → Superset |
| `docs/img/02-stack-servicios.svg` | Mapa completo de servicios Docker y conexiones |
| `docs/img/03-capas-lakehouse.svg` | Capas raw/bronze/silver/gold con retención |
| `docs/img/04-gestion-secretos.svg` | OpenBao/Sealed Secrets/.env por ambiente |
| `docs/img/05-cicd-ambientes.svg` | Branching strategy y pipelines CI/CD |
| `docs/img/06-hoja-de-ruta.svg` | Roadmap Q1-Q4 2026 con 4 fases |

---

## 🗺️ HOJA DE RUTA 2026

| Fase | Período | Estado | Hito principal |
|---|---|---|---|
| **1 — PoC** | Q1 2026 | ✅ Completado | Stack Docker + pipeline bronze + CI/CD E1 + Superset + Trino |
| **2 — Producción** | Q2 2026 | 🔄 En curso | K3s + Kafka real + SQL Server real + Power BI |
| **3 — Madurez** | Q3 2026 | ⏳ Planificado | CI/CD E3 + Prometheus + Atlas completo + Runbooks |
| **4 — Agentes** | Q4 2026 | ⏳ Planificado | NL2SQL sobre Trino + automatización LLM via VEKTRAL |

### Pendientes Fase 1 (completar antes de Fase 2)

- [ ] Registrar API Key CMF en https://api.cmfchile.cl/apps/contactanos/index.html
- [ ] Activar `dag_cmf_indicadores.py` con API Key real
- [ ] Registrar tablas indicadores en Trino y crear vista `indicadores_todos`
- [ ] Configurar dashboard Superset ejecutando `setup_superset_dashboard.py`
- [ ] `git push origin develop` con últimos cambios
- [ ] Migrar stack a K3s (Fase 2)

---

## 👤 CONTEXTO ALEPH SERVER LTDA.

**Empresa:** ALEPH SERVER LTDA. (IT infrastructure consulting, cloud, automation, AI)
**Entidades relacionadas:** VEKTRAL SpA (IA y automatización), MKD EMBEDDED LTDA.
**Stack de referencia:** Apache Airflow como herramienta de orquestación principal
**Dominios:** vektral.ai / vektral.cl
**lakeforge:** mono-repo oficial del stack de datos — plataforma técnica para servicios de data engineering a clientes

### Uso de lakeforge como producto de consultoría

1. **PoC para clientes** — levantar en Hetzner AX42 (~$53/mes) para demostrar capacidades
2. **Despliegue on-premise** — K3s en hardware del cliente, datos 100% en sus instalaciones
3. **Despliegue en nube** — GCP (datos en Chile), AWS (ecosistema existente) o AliCloud (Asia)
4. **Servicios de datos** — ingesta, transformación y visualización de datos de clientes chilenos

---

*ALEPH SERVER LTDA. — Base de conocimiento lakeforge v2.0 — 2026*
*Generada para uso en Cowork — Actualizar después de cada sesión técnica significativa*
