<p align="center">
  <img src="docs/brand/logo/vektralforge-logo-horizontal-dark.svg#gh-dark-mode-only" width="420" alt="VektralForge">
  <img src="docs/brand/logo/vektralforge-logo-horizontal-light.svg#gh-light-mode-only" width="420" alt="VektralForge">
</p>

<p align="center">
  <strong>Data Lakehouse open source con linaje de datos integrado</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licencia-Apache%202.0-B4552D" alt="Apache 2.0"></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/contribuciones-DCO-B4552D" alt="DCO"></a>
  <a href="GOVERNANCE.md"><img src="https://img.shields.io/badge/gobernanza-TSC-B4552D" alt="Gobernanza"></a>
</p>

---

VektralForge integra Apache Airflow, Spark, Delta Lake, Trino y Superset en un
stack desplegable, con trazabilidad de extremo a extremo mediante OpenLineage y
Marquez. Levanta en local con Docker Compose y está pensado para producción
sobre K3s.

Dos pipelines reales vienen incluidos como ejemplo, ambos contra APIs públicas
chilenas sin credenciales: indicadores financieros de mindicador.cl y riesgo
climático comunal de ARClim (Ministerio del Medio Ambiente).

**Licencia [Apache 2.0](LICENSE) con [DCO](CONTRIBUTING.md) en lugar de CLA**: el
copyright queda distribuido entre quienes contribuyen, no concentrado en una
empresa. Ver [OPEN_SOURCE_PROMISE.md](OPEN_SOURCE_PROMISE.md).

Patrocinado por [ALEPH SERVER LTDA.](https://alephserver.cl), que financia el
proyecto sin controlarlo — ver [SPONSORS.md](SPONSORS.md) y
[GOVERNANCE.md](GOVERNANCE.md).

---

## Stack

| Componente | Versión | Rol |
|---|---|---|
| Apache Airflow | 3.3.0 | Orquestación |
| Apache Spark | 4.0.0 | Procesamiento y escritura ACID |
| Delta Lake | 4.0.0 | Formato de tabla transaccional |
| Trino | 448 | Consulta SQL |
| Apache Hive Metastore | 4.0.0 | Catálogo compartido Spark ↔ Trino |
| MinIO | 2024-04 | Almacenamiento de objetos S3 |
| Apache Superset | 3.1.3 | Visualización |
| OpenLineage / Marquez | — | Linaje de datos |
| Apache Kafka | 7.6.1 (CP) | Ingesta en streaming |
| OpenBao | 2.1.0 | Gestión de secretos |
| PostgreSQL | 15 | Metadatos |
| Redis | 7.2 | Caché de Superset |

Python **3.12** en todo el stack: driver y executors de Spark deben coincidir en
versión menor o PySpark rechaza la ejecución.

Licencias de terceros, incluidas las dos que no son permisivas —MinIO (AGPLv3) y
Graylog (SSPL)— en [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

---

## Arranque

### Requisitos

```bash
docker --version        # >= 24.0
docker compose version  # >= 2.20
python3.12 --version    # 3.12 exacto — brew install python@3.12
make --version
```

Docker Desktop necesita al menos **8 GB de RAM** asignados
(Settings → Resources → Memory). Con menos, los contenedores mueren por OOM.

### Puesta en marcha

```bash
git clone https://github.com/vektralforge/vektralforge.git
cd vektralforge

cp .env.example infra/docker-compose/.env
# Editar las credenciales antes de continuar

make setup        # Crea .venv con Python 3.12
make dev-up       # Levanta el stack
make dev-load-example
```

`make dev-load-example` ejecuta los dos pipelines de ejemplo, registra las tablas
Delta en Trino y configura los dashboards de Superset. Tarda unos cinco minutos
la primera vez.

### Servicios

| Servicio | URL |
|---|---|
| Airflow | http://localhost:8090 |
| Superset | http://localhost:8088 |
| Trino | http://localhost:8081 |
| MinIO | http://localhost:9001 |
| Marquez (linaje) | http://localhost:3000 |
| Spark Master | http://localhost:8082 |
| OpenBao | http://localhost:8200 |

Las credenciales salen de `infra/docker-compose/.env` y se muestran al terminar
`make dev-up`. **Los valores de `.env.example` son de ejemplo y no sirven para
nada que no sea desarrollo local.**

---

## Arquitectura

**Spark escribe, Trino lee.** Las operaciones ACID sobre Delta Lake —`MERGE`,
`UPDATE`, `DELETE`, `VACUUM`— solo las hace Spark; Trino aporta consulta SQL
interactiva sobre las mismas tablas. Ambos comparten el Hive Metastore, así que
una tabla escrita por Spark es consultable desde Trino sin registrarla dos veces.

```
API pública → Airflow → Spark → Delta Lake → MinIO
                                     ↓
                          Hive Metastore (compartido)
                                     ↓
                                  Trino → Superset

        OpenLineage captura el linaje en cada paso → Marquez
```

Las capas siguen el patrón medallón: `raw/` guarda la respuesta cruda de la API,
`bronze/` las tablas Delta tipadas, `silver/` y `gold/` los modelos derivados.

Detalle completo en [docs/arquitectura.md](docs/arquitectura.md), con diagramas
en `docs/img/`.

---

## Pipelines de ejemplo

| DAG | Fuente | Frecuencia |
|---|---|---|
| `indicadores_financieros_chile` | [mindicador.cl](https://mindicador.cl) | Lunes a viernes, 10:00 |
| `arclim_riesgo_climatico_chile` | [ARClim](https://arclim.mma.gob.cl) — MMA Chile | Lunes, 06:00 |

Ambas APIs son públicas y no requieren clave, de modo que cualquiera que clone el
repositorio puede ejecutar los pipelines completos sin registrarse en ningún
sitio.

**Indicadores financieros**: UF, dólar, euro, UTM y TPM se publican cada día
hábil; el IPC es mensual, así que una serie vacía no se trata como error.

**Riesgo climático**: indicadores por las 346 comunas de Chile y series de
tiempo 1970–2070 bajo escenario SSP5-8.5 para las capitales regionales.

### Consultas de referencia

```sql
SHOW TABLES FROM delta.bronze;

SELECT indicador, count(*) AS filas, min(fecha) AS desde, max(fecha) AS hasta
FROM delta.bronze.indicadores_uf
GROUP BY indicador;

SELECT nombre, indicador, anio_serie, valor_medio
FROM delta.bronze.arclim_series
WHERE cod_comuna = '13101' AND anio_serie >= 2050
ORDER BY anio_serie;
```

---

## Comandos

```bash
make setup              # Crea .venv con Python 3.12
make dev-up             # Levanta el stack
make dev-down           # Lo detiene
make dev-ps             # Estado de los contenedores
make dev-logs           # Logs (SERVICE=airflow-scheduler para uno solo)
make dev-reset          # Borra volúmenes y recrea usuarios
make dev-reset-hard     # Además reconstruye las imágenes locales
make dev-load-example   # Ejecuta los pipelines y configura los dashboards
make lint-all           # Ruff + sqlfluff
make test-all           # Tests
make detect-secrets     # Escaneo de credenciales
make deploy-staging     # Deploy K3s staging
make deploy-prod        # Deploy K3s producción (pide confirmación)
```

`dev-reset` tarda alrededor de un minuto y sirve cuando los datos quedaron
inconsistentes. `dev-reset-hard` tarda unos tres minutos y hace falta cuando
cambiaste algún Dockerfile.

---

## Secretos

| Entorno | Herramienta | Notas |
|---|---|---|
| Local | `.env` | Nunca versionado; `.env.example` documenta las variables |
| Staging | Sealed Secrets | Cifrado en Git, descifrado por K3s |
| Producción | OpenBao | Fork de Vault bajo MPL 2.0, con rotación automática |

Ningún archivo del repositorio contiene credenciales. Los que las necesitan
—`marquez.yml`, `core-site.xml` del metastore— se generan al arrancar el
contenedor a partir del `.env`, y los catálogos de Trino usan interpolación
`${ENV:...}` en tiempo de ejecución.

---

## Contribuir

Las contribuciones son bienvenidas. Antes de tu primer pull request:

- [CONTRIBUTING.md](CONTRIBUTING.md) — flujo de trabajo y firma DCO (`git commit -s`)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — normas de convivencia
- [GOVERNANCE.md](GOVERNANCE.md) — cómo se toman las decisiones
- [SECURITY.md](SECURITY.md) — reporte de vulnerabilidades (**no** por issue público)

Issues y pull requests se aceptan en español o en inglés.

---

## Notas de compatibilidad

- **Python 3.12 exacto.** Versiones más nuevas rompen la compilación de pandas,
  que los providers de Airflow acotan a `<2.2`. Driver y executors de Spark
  deben coincidir en versión menor.
- **Spark 4 usa Scala 2.13.** El soporte de 2.12 se eliminó, así que todas las
  coordenadas de JAR cambian respecto a Spark 3.5.
- **AWS SDK v2 en Spark, v1 en el metastore.** Hadoop 3.4 (Spark 4) migró al v2;
  Hadoop 3.3 (imagen de Hive) sigue con el v1. Son artefactos distintos, no
  versiones del mismo. Los Dockerfiles los resuelven con Maven en vez de fijarlos
  a mano.
- **ANSI mode activo por defecto en Spark 4.** Los casts inválidos lanzan
  excepción en lugar de devolver `null`.
- **`apache-airflow-providers-amazon` excluido** por incompatibilidad con
  SQLAlchemy 2.x. El acceso a MinIO se hace con `boto3` directo.
- **Airflow 3 exige `execution_api_server_url` y un JWT compartido** entre
  contenedores. Las tareas ya no acceden a la base de metadatos: hablan con el
  api-server por HTTP.
- **Trino usa `s3://`, Spark usa `s3a://`.** El metastore mapea ambos esquemas al
  conector S3A.

---

## Documentación

| Documento | Contenido |
|---|---|
| [docs/arquitectura.md](docs/arquitectura.md) | Arquitectura, flujo de datos, GitOps, hardware y hoja de ruta |
| [docs/airflow-fab-auth.md](docs/airflow-fab-auth.md) | Gestión de usuarios y roles en Airflow |
| [docs/marca.md](docs/marca.md) | Manual de marca e imagotipo |
| [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) | Inventario de licencias de terceros |

---

<p align="center">
  <sub>
    Apache 2.0 · Copyright The VektralForge Authors ·
    Patrocinado por <a href="https://alephserver.cl">ALEPH SERVER LTDA.</a>
  </sub>
</p>
