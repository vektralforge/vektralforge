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
| OpenBao | 2.1.0 | — |
| MinIO | 2024-04 | — |
| Apache Superset | 3.1.3 | — |
| Apache Kafka | 7.6.1 (CP) | — |
| PostgreSQL | 15 | — |
| Redis | 7.2 | — |

---

## Estructura

```
lakeforge/
├── airflow/
│   └── dags/
│       ├── dag_bronze_ejemplo.py          # Pipeline sintético validado
│       ├── dag_cmf_indicadores.py         # API CMF Chile (requiere API Key)
│       └── dag_indicadores_financieros.py # mindicador.cl (sin API Key) ← activo
├── spark/
│   └── jobs/
│       ├── bronze_clientes.py             # Job Spark clientes ejemplo
│       ├── bronze_cmf.py                  # Job Spark indicadores CMF
│       └── bronze_indicadores.py          # Job Spark indicadores mindicador.cl
├── trino/
│   └── catalog/                           # Configuración Delta Lake connector
├── hive/
│   └── schemas/                           # DDL numeradas (Flyway)
├── superset/
│   └── dashboards/
│       └── setup_superset_dashboard.py    # Script auto-configuración dashboard
├── infra/
│   ├── k3s/                               # Manifiestos Kubernetes (staging + prod)
│   ├── docker-compose/
│   │   ├── docker-compose.yml             # Stack completo 13 servicios
│   │   ├── .env                           # Credenciales locales (NO versionado)
│   │   ├── spark/Dockerfile               # JARs delta+hadoop-aws pre-instalados
│   │   └── superset/Dockerfile            # trino[sqlalchemy] incluido
│   └── helm/                              # Charts Helm personalizados
├── .ci/
│   ├── scripts/
│   │   ├── setup.sh                       # Crea .venv Python 3.12
│   │   ├── init_users.sh                  # Crea usuarios + buckets MinIO
│   │   └── load_example.sh                # Carga datos de ejemplo post-reset
│   └── pipelines/                         # Adaptadores YAML por plataforma CI/CD
├── docs/
│   ├── arquitectura.md                    # Arquitectura completa con diagramas SVG
│   └── img/                               # 6 diagramas SVG del stack
├── .env.example                           # Variables requeridas (SÍ versionado)
├── .secrets.baseline                      # Baseline detect-secrets
├── Makefile                               # Interfaz unificada de comandos
└── README.md
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

> Docker Desktop requiere mínimo **8 GB de RAM** (Settings → Resources → Memory).

### 2. Clonar y configurar

```bash
git clone https://bitbucket.org/alephserver/lakeforge.git
cd lakeforge
```

### 3. Configurar variables de entorno

```bash
cp .env.example infra/docker-compose/.env
nano infra/docker-compose/.env   # ajustar según el entorno
```

> El archivo `.env` está en `.gitignore` y nunca se versiona.
> `.env.example` documenta todas las variables con valores placeholder.

### 4. Setup del entorno Python

```bash
make setup
source .venv/bin/activate
```

### 5. Levantar stack local

```bash
make dev-up
```

Al finalizar se muestra la tabla de servicios con credenciales leídas del `.env`:

| Servicio | URL | Usuario | Password |
|---|---|---|---|
| Airflow | http://localhost:8090 | admin | admin |
| Superset | http://localhost:8088 | admin | admin |
| MinIO Console | http://localhost:9001 | minioadmin | minioadmin |
| Trino | http://localhost:8081 | trino | (sin password) |
| OpenBao | http://localhost:8200 | token: | dev-root-token |
| Spark Master | http://localhost:8082 | (sin auth) | — |

> Las credenciales reales están en `infra/docker-compose/.env`.

### 6. Cargar datos de ejemplo

```bash
make dev-load-example
```

Ejecuta automáticamente en orden:

1. Verifica que el stack está operativo
2. Instala dependencias Spark si faltan (antlr4-runtime JAR)
3. Activa y dispara el DAG `indicadores_financieros_chile`
4. Monitorea cada task hasta completar (~3 min)
5. Registra 5 tablas Delta en Trino + crea vista `indicadores_todos`
6. Configura dashboard Superset con 10 charts

Al finalizar el dashboard está disponible en:
```
http://localhost:8088/superset/dashboard/indicadores-financieros-chile/
```

### 7. Detener

```bash
make dev-down
```

---

## Comandos disponibles

```bash
make setup              # Crea .venv e instala dependencias (Python 3.12)
make dev-up             # Levanta stack Docker Compose
make dev-down           # Detiene stack
make dev-logs           # Logs en tiempo real
make dev-reset          # Reset completo: borra volúmenes, recrea usuarios desde .env
make dev-reset-hard     # Reset extremo: borra volúmenes + imágenes custom (rebuild)
make dev-load-example   # Carga datos de ejemplo y configura dashboard Superset
make lint-all           # Lint completo (Ruff + sqlfluff)
make test-all           # Tests completos
make detect-secrets     # Escaneo de credenciales y secretos
make deploy-staging     # Deploy K3s staging
make deploy-prod        # Deploy K3s producción (requiere confirmación)
```

### Diferencia entre dev-reset y dev-reset-hard

| Comando | Borra datos | Borra imágenes Docker | Velocidad | Cuándo usar |
|---|---|---|---|---|
| `dev-reset` | ✓ | ✗ | ~60s | Datos corruptos, empezar limpio |
| `dev-reset-hard` | ✓ | ✓ (imágenes custom) | ~3 min | Cambios en Dockerfiles, caché corrupto |

### Flujo típico post reset

```bash
make dev-reset-hard      # Stack completamente limpio
make dev-load-example    # Datos + Trino + Dashboard (~5 min)
```

---

## DAGs disponibles

| DAG | Fuente | Schedule | Estado |
|---|---|---|---|
| `indicadores_financieros_chile` | mindicador.cl (sin API Key) | Lunes-Viernes 10:00 AM | ✓ Activo |
| `dag_cmf_indicadores` | API CMF Chile (requiere API Key) | Diario 9:00 AM | ⏳ Pendiente API Key |
| `bronze_clientes_ejemplo` | Datos sintéticos | Manual | ✓ Disponible |

### Indicadores financieros (mindicador.cl)

| Indicador | Tipo | Publicación |
|---|---|---|
| UF | Diario | Cada día hábil |
| Dólar | Diario | Cada día hábil |
| Euro | Diario | Cada día hábil |
| UTM | Diario | Cada día hábil |
| TPM | Diario | Cada día hábil |
| IPC | Mensual | ~día 8 de cada mes (WARNING si no está) |

> Para activar `dag_cmf_indicadores`, registrar API Key en:
> https://api.cmfchile.cl/apps/contactanos/index.html

---

## Trino — consultas de referencia

```sql
-- Ver todas las tablas
SHOW TABLES IN delta.bronze;

-- Conteo por indicador
SELECT indicador, COUNT(*) as filas, MIN(fecha) as desde, MAX(fecha) as hasta
FROM delta.bronze.indicadores_todos
GROUP BY indicador ORDER BY indicador;

-- Último valor de cada indicador
SELECT indicador, MAX(fecha) as fecha, MAX(valor) as valor
FROM delta.bronze.indicadores_todos
GROUP BY indicador;
```

---

## Gestión de credenciales y secretos

| Ambiente | Herramienta | Licencia | Notas |
|---|---|---|---|
| Local | `.env` file | — | Basado en `.env.example`, nunca commitear |
| Staging | Sealed Secrets | Apache 2.0 | Cifrado en Git, descifrado por K3s |
| Producción | **OpenBao** | MPL 2.0 | Fork Vault, Linux Foundation, rotación automática |

> OpenBao gestiona contraseñas, tokens API, certificados y claves de cifrado.
> La UI web no está disponible en el binario de desarrollo — la API REST funciona completamente en `:8200`.

---

## Diagramas de arquitectura

Los diagramas SVG están en `docs/img/`:

| Diagrama | Archivo |
|---|---|
| Flujo de datos end-to-end | `docs/img/01-flujo-datos.svg` |
| Stack de servicios Docker/K3s | `docs/img/02-stack-servicios.svg` |
| Capas del Lakehouse | `docs/img/03-capas-lakehouse.svg` |
| Gestión de credenciales y secretos | `docs/img/04-gestion-secretos.svg` |
| CI/CD y ambientes | `docs/img/05-cicd-ambientes.svg` |
| Hoja de ruta 2026 | `docs/img/06-hoja-de-ruta.svg` |

---

## Notas de compatibilidad

- **Python 3.14 no soportado** — usar siempre Python 3.12. pandas y Airflow sin wheels para 3.14.
- **delta-spark 3.2.0** — compatible con Spark 3.5.x. delta-spark 4.0.0 requiere Spark 4.x.
- **isinstance con tupla en Spark** — Spark corre Python 3.8 internamente. Usar `isinstance(x, (int, float))` con `# noqa: UP038`, no `int | float` (requiere Python 3.10+).
- **antlr4-runtime JAR** — puede corromperse en caché. `make dev-load-example` lo instala automáticamente. Fix manual: `docker exec -u root docker-compose-spark-master-1 curl -L -o /opt/spark/jars/antlr4-runtime-4.9.3.jar https://repo1.maven.org/maven2/org/antlr/antlr4-runtime/4.9.3/antlr4-runtime-4.9.3.jar`
- **apache-airflow-providers-amazon excluido** — conflicto con SQLAlchemy 2.x. MinIO usa `boto3` directo.
- **Trino usa file metastore** — más estable que Hive Metastore en PoC.
- **Docker Desktop** — asignar mínimo 8 GB RAM para evitar OOM kills.
- **OpenBao UI** — no disponible en binario de desarrollo. Usar API REST o CLI (`bao`).
- **Superset driver Trino** — incluido en `infra/docker-compose/superset/Dockerfile`. Si falta: `docker exec -u root docker-compose-superset-1 pip install "trino[sqlalchemy]"`.

---

## Documentación

- [docs/arquitectura.md](docs/arquitectura.md) — Arquitectura completa: stack, flujo de datos, GitOps, CI/CD, credenciales, gobernanza, hardware y hoja de ruta 2026.
- [docs/BASE_DE_CONOCIMIENTO_LAKEFORGE.md](docs/BASE_DE_CONOCIMIENTO_LAKEFORGE.md) — Base de conocimiento para Cowork: comandos, DAGs, troubleshooting y referencias rápidas.

---

ALEPH SERVER LTDA. — Documento técnico confidencial — 2026
