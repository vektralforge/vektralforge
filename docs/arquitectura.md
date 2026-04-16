# Lakeforge — Arquitectura Lakehouse Open Source Stack

**ALEPH SERVER LTDA. — Documento técnico de referencia**
Versión 2.0 — Stack validado y operativo en PoC — 2026

---

## Convenciones de madurez

| Badge | Significado |
|---|---|
| `PoC / Dev` | Validado en entorno local, no productivo aún |
| `Producción` | Desplegado y estable en producción |
| `Fase futura` | Planificado para etapa siguiente |

---

## 1. Introducción

Lakeforge es el mono-repositorio oficial de ALEPH SERVER LTDA. para el stack de datos Lakehouse open source. Centraliza el código de orquestación (Apache Airflow), procesamiento (Apache Spark), consulta (Trino), esquemas (Hive Metastore) e infraestructura (K3s/Helm) bajo un único repositorio Git con pipelines CI/CD agnósticos por dominio.

El diseño incorpora siete gaps identificados durante el análisis de arquitectura: ambientes formalizados, versionado de datos, gestión de secretos empresarial, dependencias Python estandarizadas, observabilidad, retención de datos y onboarding de desarrolladores.

---

## 2. Stack técnico completo

| Componente | Versión | Estado | Notas |
|---|---|---|---|
| Apache Kafka | 7.6.1 (CP) | `PoC / Dev` | Streaming tiempo real; reemplaza RabbitMQ |
| Apache Airflow | 2.9.1 | `Producción` | Orquestación ETL batch; DAGs en airflow/dags/ |
| MinIO | 2024-04 | `PoC / Dev` | Object storage S3-compatible; buckets raw/bronze/silver/gold |
| Delta Lake | 3.2.0 | `PoC / Dev` | Tablas ACID sobre MinIO; time travel; schema enforcement |
| Hive Metastore | 4.0.0 | `PoC / Dev` | Catálogo central; migraciones DDL numeradas en hive/schemas/ |
| Apache Spark | 3.5.3 | `PoC / Dev` | ETL distribuido; jobs en spark/jobs/; motor de escritura ACID |
| Trino | 448 | `PoC / Dev` | Motor SQL federado; file metastore local; consulta Delta Lake |
| Apache Atlas | — | `PoC / Dev` | Linaje de datos y catalogación de metadatos |
| Apache Ranger | — | `Producción` | Control de acceso; políticas por tabla/columna/fila |
| Great Expectations | — | `PoC / Dev` | Calidad de datos; integrado en pipeline CI/CD Escenario 2+ |
| Power BI | — | `Producción` | BI empresarial; conectado a Trino vía ODBC |
| Apache Superset | 3.1.3 | `PoC / Dev` | Exploración Big Data; integrado con Trino |
| Redis | 7.2 | `PoC / Dev` | Caché de consultas para Superset |
| OpenBao | 2.0.0 | `Producción` | Fork OSS de Vault; MPL 2.0; Linux Foundation; rotación + auditoría |
| Sealed Secrets | — | `PoC / Dev` | Secretos cifrados en Git para staging |
| Graylog | — | `Producción` | Centralización de logs de todo el stack |
| Prometheus + Grafana | — | `Fase futura` | Métricas de infraestructura y alertas operacionales |
| Docker Compose | — | `PoC / Dev` | Entorno local; definido en infra/docker-compose/ |
| K3s / Kubernetes | — | `Producción` | Plataforma de producción; manifiestos en infra/k3s/ |

---

## 3. Flujo de datos end-to-end

```mermaid
flowchart LR
    subgraph Fuentes["Fuentes de datos"]
        SQL[(SQL Server)]
        API[APIs REST]
        CSV[Archivos CSV]
    end

    subgraph Ingesta["Ingesta"]
        AF[Apache Airflow]
        KF[Apache Kafka]
    end

    subgraph Storage["Object Storage — MinIO"]
        RAW[raw/\n30 días]
        BRONZE[bronze/\n90 días]
        SILVER[silver/\nindefinido]
        GOLD[gold/\nindefinido]
    end

    subgraph Procesamiento["Procesamiento"]
        SP[Apache Spark\nEscritura ACID]
        TR[Trino\nLectura SQL]
    end

    subgraph Consumo["Consumo"]
        SS[Apache Superset]
        PBI[Power BI]
    end

    SQL --> AF
    CSV --> AF
    API --> KF
    KF --> AF
    AF --> RAW
    RAW -->|Spark ACID| BRONZE
    BRONZE -->|Spark ACID| SILVER
    SILVER -->|Spark ACID| GOLD
    BRONZE --> TR
    SILVER --> TR
    GOLD --> TR
    TR --> SS
    TR --> PBI
```

> **Regla fundamental: Spark escribe. Trino lee.**

| Operación | Motor |
|---|---|
| Escribir en Delta Lake (ACID) | **Spark** |
| MERGE / UPSERT | **Spark** |
| Streaming Kafka → Delta | **Spark Structured Streaming** |
| Consultas SQL ad-hoc | **Trino** |
| Consultas federadas multi-fuente | **Trino** |

---

## 4. Arquitectura del stack de servicios

```mermaid
graph TB
    subgraph Orquestacion["Orquestación"]
        AW[Airflow Webserver :8090]
        AS[Airflow Scheduler]
    end

    subgraph Procesamiento["Procesamiento"]
        SM[Spark Master :7077/:8082]
        SW[Spark Worker :8083]
        SM --> SW
    end

    subgraph Streaming["Streaming"]
        ZK[Zookeeper]
        KK[Kafka :9092]
        ZK --> KK
    end

    subgraph Lake["Data Lake — MinIO :9001"]
        MN[(raw / bronze / silver / gold)]
    end

    subgraph Catalogo["Catálogo"]
        HM[Hive Metastore :9083]
        PG[(PostgreSQL :5432)]
        HM --> PG
    end

    subgraph Consulta["Consulta SQL"]
        TN[Trino :8081]
    end

    subgraph Visualizacion["Visualización"]
        SU[Superset :8088]
        RD[Redis :6379]
    end

    subgraph Secretos["Secretos"]
        OB[OpenBao :8200]
    end

    AW --- AS
    AS -->|spark-submit| SM
    AS --> MN
    SM --> MN
    TN --> HM
    TN --> MN
    SU --> RD
    SU --> TN
    OB --> AS
    OB --> SM
```

---

## 5. Mono-repo lakeforge

```
lakeforge/
├── airflow/
│   ├── dags/               # DAGs Python de Airflow
│   ├── plugins/            # Operadores y hooks custom
│   ├── tests/              # Tests unitarios de DAGs
│   └── requirements.txt    # Dependencias Python (pinning estricto)
├── spark/
│   ├── jobs/               # Scripts PySpark
│   ├── tests/              # Tests con pytest + chispa
│   └── requirements.txt    # Dependencias Python de Spark
├── trino/
│   └── catalog/            # Configuraciones de conectores
├── hive/
│   └── schemas/            # DDL numeradas (convención Flyway)
├── superset/
│   └── dashboards/         # Exports JSON de dashboards
├── infra/
│   ├── k3s/                # Manifiestos Kubernetes
│   ├── docker-compose/     # Stack local completo
│   └── helm/               # Charts Helm personalizados
├── .ci/
│   ├── scripts/            # Scripts bash portables (lógica CI/CD)
│   └── pipelines/          # Adaptadores YAML por plataforma
├── docs/                   # Documentación técnica
├── Makefile                # Interfaz unificada de comandos
└── README.md               # Guía de onboarding
```

### Makefile — comandos principales

```bash
make setup           # Crea .venv e instala dependencias (Python 3.12)
make dev-up          # Levanta stack Docker Compose
make dev-down        # Detiene stack
make lint-all        # Lint completo (Ruff + sqlfluff)
make test-all        # Tests completos
make detect-secrets  # Escaneo de secretos
make deploy-staging  # Deploy K3s staging
make deploy-prod     # Deploy K3s producción (requiere confirmación)
```

---

## 6. GitOps y CI/CD agnóstico

### Principio de agnosis

El CI/CD opera en dos niveles independientes:

- **Nivel 1 — lógica portable:** scripts bash en `.ci/scripts/` con la lógica real de lint, test, build y deploy.
- **Nivel 2 — adaptadores de plataforma:** archivos YAML en `.ci/pipelines/` que solo invocan los scripts del Nivel 1.

**Plataformas soportadas:** Woodpecker CI, Bitbucket Pipelines, Azure DevOps, GitHub Actions.

### Estrategia de branching

```mermaid
gitGraph
    commit id: "init"
    branch develop
    checkout develop
    commit id: "estructura inicial"
    commit id: "docker-compose operativo"
    commit id: "pipeline bronze"
    branch feature/silver-layer
    checkout feature/silver-layer
    commit id: "silver DAG"
    commit id: "silver job Spark"
    checkout develop
    merge feature/silver-layer id: "merge silver"
    checkout main
    merge develop id: "release v1.0"
```

| Branch | Ambiente destino | Pipeline mínimo |
|---|---|---|
| `feature/*` | Local (Docker Compose) | Lint + secrets check |
| `develop` | Staging (K3s namespace) | Escenario 1 + deploy staging |
| `main` | Producción (K3s namespace) | Escenario 2/3 + smoke test |

### Pipelines por dominio

| Carpeta | Trigger | Pasos |
|---|---|---|
| `airflow/dags/` | Push a branch | Lint → test DAG → sync PVC Airflow |
| `spark/jobs/` | Push a branch | Lint → test PySpark → build imagen → deploy |
| `trino/catalog/` | Push a branch | Validar YAML → reload conector |
| `hive/schemas/` | Push a branch | Validar DDL → migración via DAG Airflow |
| `infra/k3s/` | Push a main | Validar manifiestos → kubectl apply |

---

## 7. Escenarios CI/CD

### Progresión recomendada

- **Mes 1-2:** Escenario 1 — instalar el hábito sin fricción
- **Mes 3-4:** Escenario 2 — agregar tests a medida que se escribe código nuevo
- **Mes 6+:** Escenario 3 — cuando el stack esté estable en staging

### Matriz de requisitos

| Requisito | E1 Básico | E2 Intermedio | E3 Avanzado |
|---|---|---|---|
| Lint (Ruff / sqlfluff) | Bloquea | Bloquea | Bloquea |
| detect-secrets | Bloquea | Bloquea | Bloquea |
| Sintaxis DAG válida | Bloquea | Bloquea | Bloquea |
| Tests unitarios (pytest) | — | Bloquea | Bloquea |
| Cobertura mínima 40% | — | Bloquea | Bloquea |
| Schema Delta válido (GE) | — | Bloquea | Bloquea |
| Cobertura mínima 70% | — | — | Bloquea |
| Tests de integración | — | — | Bloquea |
| Deploy staging OK | — | — | Bloquea |
| Smoke test en staging | — | — | Bloquea |
| Tiempo estimado | < 2 min | 4-8 min | 15-25 min |

---

## 8. Stack técnico por equipo

### Desarrollador de DAGs (Airflow)

```
Python 3.12 (venv aislado)
Airflow 2.9.1
Ruff — linter y formatter
pytest — tests unitarios
pre-commit — hooks automáticos
```

### Desarrollador de jobs Spark

```
Python 3.12 (venv aislado)
PySpark 3.5.3 + delta-spark 3.2.0
chispa — testing PySpark
pytest + pytest-cov
Ruff — linter y formatter
```

### Analista SQL / Trino

```
DBeaver o DataGrip (conector Trino nativo)
trino-cli — cliente CLI oficial
sqlfluff — linter SQL
```

### Ingeniero de infraestructura

```
kubectl + helm
k9s — UI terminal para K8s
kubectx — cambio rápido entre contextos
Docker Desktop (mínimo 8 GB RAM)
```

---

## 9. Gestión de secretos

```mermaid
flowchart LR
    subgraph Local["Local"]
        ENV[.env file]
    end
    subgraph Staging["Staging — K3s"]
        SS[Sealed Secrets\nApache 2.0]
    end
    subgraph Prod["Producción — K3s"]
        OB[OpenBao\nMPL 2.0]
    end
    subgraph Apps["Consumidores"]
        AF[Airflow]
        SP[Spark]
        TR[Trino]
    end

    ENV --> AF & SP
    SS --> AF & SP
    OB --> AF & SP & TR
```

| Ambiente | Herramienta | Licencia | Notas |
|---|---|---|---|
| Local | `.env` file | — | Nunca commitear |
| Staging | Sealed Secrets | Apache 2.0 | Cifrado en Git, descifrado por K3s |
| Producción | **OpenBao** | MPL 2.0 | Fork Vault, Linux Foundation, API compatible |

### Por qué OpenBao y no HashiCorp Vault

HashiCorp cambió Vault a BSL v1.1 en agosto 2023 — ya no es open source. OpenBao es el fork MPL 2.0 bajo Linux Foundation con API 100% compatible. Sin restricciones BSL.

### Cliente Python (hvac)

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

## 10. Capas del Lakehouse

```mermaid
flowchart TD
    C1[SQL Server] & C2[APIs REST] & C3[CSV/Excel] --> I1[Airflow] & I2[Kafka]
    I1 & I2 --> R1[raw/\n30 días]
    R1 -->|Spark ACID| B1[bronze/\n90 días\nDelta Lake]
    B1 -->|Spark ACID| S1[silver/\nindefinido\nDelta Lake]
    S1 -->|Spark ACID| G1[gold/\nindefinido\nDelta Lake]
    B1 & S1 & G1 -->|Trino SQL| CO1[Trino]
    CO1 --> CO2[Superset] & CO3[Power BI]
```

### Retención de datos

| Capa | Retención | Mecanismo |
|---|---|---|
| `raw/` | 30 días | Lifecycle policy en MinIO |
| `bronze/` | 90 días | Lifecycle policy en MinIO |
| `silver/` | Indefinido | Política de negocio |
| `gold/` | Indefinido | Política de negocio |
| Delta versions | 7 días | VACUUM DAG en Airflow |

---

## 11. Gobernanza y calidad de datos

### Apache Atlas — `PoC / Dev`
- Linaje de datos y catalogación de metadatos
- Clasificaciones para datos sensibles: PII, financiero, confidencial

### Apache Ranger — `Producción`
- Control de acceso centralizado para Trino, Spark y Hive Metastore
- Políticas a nivel de base de datos, tabla, columna y fila
- Auditoría completa. Integración con LDAP / Active Directory

### Great Expectations — `PoC / Dev`
- Validación de calidad en el pipeline CI/CD desde Escenario 2
- Valida schema, nulos, rangos y unicidad antes de capas silver/gold

---

## 12. Observabilidad

### Graylog — `Producción` (activo)
- Centralización de logs via GELF/Syslog
- Dashboards por componente: Airflow, Spark, Trino, Kafka
- Alertas por patrones de error

### Prometheus + Grafana — `Fase futura`
- Métricas de infraestructura K3s
- Métricas de pipelines Airflow (duración, tasa de fallos)

---

## 13. Ambientes y despliegue

```mermaid
flowchart LR
    FT[feature/*] -->|make dev-up| DC[Docker Compose\nLocal]
    DV[develop] -->|CI/CD automático| NS[K3s\nlakeforge-staging]
    MN[main] -->|CI/CD + aprobación| NP[K3s\nlakeforge-prod]
```

### Servicios disponibles tras make dev-up

| Servicio | URL | Credenciales |
|---|---|---|
| Airflow UI | http://localhost:8090 | admin / admin |
| Trino UI | http://localhost:8081 | — |
| MinIO Console | http://localhost:9001 | minioadmin / minioadmin |
| Superset | http://localhost:8088 | admin / admin |
| OpenBao | http://localhost:8200 | token: dev-root-token |
| Spark Master | http://localhost:8082 | — |

---

## 14. Requisitos de hardware

### PoC — Servidor único

| Componente | Mínimo | Recomendado |
|---|---|---|
| CPU | 8 cores | 16 cores |
| RAM | 32 GB | 64 GB |
| Disco OS | 100 GB SSD | 200 GB SSD |
| Disco datos (MinIO) | 500 GB HDD | 2 TB SSD |

> Referencia: Hetzner AX42 (16 cores / 64 GB / 2×512 GB NVMe) — EUR 79/mes

### Producción mínima — Cluster K3s 3 nodos

```mermaid
graph LR
    subgraph N1["node-1 · 8c / 32 GB"]
        CP[Control plane]
        AF2[Airflow]
        OB2[OpenBao]
    end
    subgraph N2["node-2 · 16c / 64 GB"]
        SP2[Spark]
        TR2[Trino]
    end
    subgraph N3["node-3 · 8c / 32 GB / 4 TB"]
        MN2[MinIO]
        KK2[Kafka]
        AT[Atlas]
    end
    N1 <--> N2
    N2 <--> N3
    N1 <--> N3
```

| Nodo | Rol | CPU | RAM | Datos |
|---|---|---|---|---|
| node-1 | Control plane + Airflow + OpenBao | 8 cores | 32 GB | — |
| node-2 | Spark + Trino | 16 cores | 64 GB | — |
| node-3 | MinIO + Kafka + Atlas | 8 cores | 32 GB | 4 TB |
| **Total** | | **32 cores** | **128 GB** | **4 TB** |

---

## 15. Correcciones de validación arquitectural

### 15.1 HashiCorp Vault → OpenBao

En agosto 2023, HashiCorp cambió Vault a BSL v1.1 (source-available, no open source). OpenBao es el reemplazo con licencia MPL 2.0 bajo Linux Foundation y API 100% compatible.

| Aspecto | HashiCorp Vault | OpenBao |
|---|---|---|
| Licencia | BSL 1.1 (source-available) | MPL 2.0 (open source OSI) |
| Gobernanza | HashiCorp / IBM | Linux Foundation + OpenSSF |
| API | Referencia | 100% compatible |
| Namespaces | Solo Enterprise (pago) | Incluido en open source |

### 15.2 Rol real de Apache Spark

| Rol | Descripción |
|---|---|
| Escritura ACID | Único motor con MERGE, UPDATE, DELETE, VACUUM sobre Delta Lake |
| ELT batch | Transforma raw → bronze → silver → gold |
| Streaming | Spark Structured Streaming: Kafka → Delta Lake exactly-once |

---

## 16. Hoja de ruta

```mermaid
gantt
    title Hoja de ruta lakeforge 2026
    dateFormat  YYYY-MM
    section Fase 1 - PoC
    Mono-repo y Docker stack     :done, 2026-01, 1M
    Pipeline raw a bronze        :done, 2026-01, 1M
    CI/CD Escenario 1            :done, 2026-02, 1M
    Superset y Trino conectados  :done, 2026-02, 1M
    section Fase 2 - Produccion
    Migrar a K3s staging         :2026-03, 2M
    Kafka tiempo real            :2026-03, 2M
    CI/CD Escenario 2            :2026-04, 2M
    OpenBao en K3s               :2026-04, 1M
    SQL Server real              :2026-05, 1M
    section Fase 3 - Madurez
    CI/CD Escenario 3            :2026-07, 2M
    Prometheus y Grafana         :2026-07, 2M
    Atlas catalogacion completa  :2026-08, 2M
    section Fase 4 - Agentes
    NL2SQL sobre Trino           :2026-10, 3M
    Automatizacion LLM VEKTRAL   :2026-11, 3M
```

### Resumen de fases

| Fase | Período | Hito principal |
|---|---|---|
| 1 — PoC | Q1 2026 ✓ | Stack Docker + pipeline bronze + CI/CD E1 + Superset |
| 2 — Producción | Q2 2026 | K3s + Kafka + SQL Server real + Power BI |
| 3 — Madurez | Q3 2026 | CI/CD E3 + Prometheus + Atlas completo |
| 4 — Agentes | Q4 2026 | NL2SQL + automatización LLM via VEKTRAL |

---

*ALEPH SERVER LTDA. — Documento técnico confidencial — lakeforge v2.0 — 2026*
