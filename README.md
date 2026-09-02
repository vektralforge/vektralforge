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
  <a href="../../actions/workflows/ci.yml"><img src="../../actions/workflows/ci.yml/badge.svg?branch=develop" alt="CI"></a>
</p>

---

VektralForge integra Apache Airflow, Spark, Delta Lake, Trino y Superset en un
stack desplegable, con trazabilidad de extremo a extremo mediante OpenLineage y
Marquez. Levanta en local con Docker Compose y está pensado para producción
sobre K3s.

Dos pipelines reales vienen incluidos, ambos contra APIs públicas chilenas sin
credenciales: indicadores financieros de mindicador.cl y riesgo climático
comunal de ARClim (Ministerio del Medio Ambiente).

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
| Apache Spark | 4.1.3 | Procesamiento y escritura ACID |
| Delta Lake | 4.1.0 | Formato de tabla transaccional |
| Apache Hive Metastore | 4.0.0 | Catálogo compartido Spark ↔ Trino |
| Trino | 448 | Consulta SQL |
| MinIO | 2024-04 | Almacenamiento de objetos S3 |
| Apache Superset | 3.1.3 | Visualización |
| OpenLineage | 1.52.0 | Linaje en Airflow y Spark |
| Marquez | — | Almacén y UI de linaje |
| PostgreSQL | 15 | Metadatos |
| Redis | 7.2 | Caché de Superset (metadatos y datos de los gráficos) |
| OpenBao | 2.1.0 | Secretos (modo dev en local) |
| Apache Kafka | 7.6.1 (CP) | Perfil opcional `streaming`; sin pipeline aún |
| Apache ZooKeeper | 7.6.1 (CP) | Perfil opcional `streaming`; solo sirve a Kafka |

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

make init-env          # Genera claves y pide contraseñas
make setup             # Crea .venv con Python 3.12
make dev-up            # Levanta el stack
make dev-load-example  # Ejecuta los pipelines y configura los dashboards
```

`make init-env` crea `infra/docker-compose/.env` a partir de `.env.example`:
genera las claves criptográficas y ofrece una contraseña por servicio, que
puedes aceptar o reemplazar. Es idempotente, así que puedes volver a
ejecutarlo cuando aparezcan variables nuevas.

`make dev-load-example` tarda unos cinco minutos la primera vez.

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

Las credenciales salen de `infra/docker-compose/.env`, que tiene permisos 600.
`make dev-up` **no las imprime**: el banner final muestra el nombre de la
variable de cada una. Para leer una concreta:

```bash
grep '^AIRFLOW_ADMIN_PASSWORD=' infra/docker-compose/.env | cut -d= -f2-
```

Trino, Spark y Marquez no piden credenciales de ningún tipo: cualquiera que
alcance esos puertos entra. Por eso el `.env` fija `BIND_HOST=127.0.0.1`.

---

## Arquitectura

**Spark escribe, Trino lee.** Las operaciones ACID sobre Delta Lake —`MERGE`,
`UPDATE`, `DELETE`, `VACUUM`— solo las hace Spark; Trino aporta consulta SQL
interactiva sobre las mismas tablas.

Ambos comparten el Hive Metastore. Los jobs escriben con `saveAsTable`, no con
`save(ruta)`, así que la tabla queda registrada en el catálogo en el mismo acto
en que se escribe y Trino la ve sin registrarla dos veces. Añadir un pipeline no
exige tocar ningún script de registro: basta con escribir en `bronze`.

```
API pública → Airflow → Spark → Delta Lake → MinIO
                                     ↓
                          Hive Metastore (compartido)
                                     ↓
                                  Trino → Superset

        OpenLineage captura el linaje en cada paso → Marquez
```

El linaje se captura en dos niveles. El provider de OpenLineage de Airflow emite
el run de cada tarea; el `OpenLineageSparkListener` —declarado en el
`spark-defaults.conf` que comparten las imágenes de Airflow y Spark— emite los
datasets de entrada y salida de cada job. Airflow inyecta en cada `spark-submit`
el parent job y la URL de transporte, así que el run de Spark cuelga de su tarea
en Marquez en vez de aparecer como un grafo suelto.

El soporte de Spark 4 llegó en OpenLineage 1.37.0: versiones anteriores no
sirven con este stack.

Las capas siguen el patrón medallón: `raw/` guarda la respuesta cruda de la API,
`bronze/` las tablas Delta tipadas, `silver/` y `gold/` los modelos derivados.

Detalle completo en [docs/arquitectura.md](docs/arquitectura.md).

### Estructura

```
airflow/          DAGs, plugins y tests
spark/            Jobs PySpark y tests
trino/catalog/    Catálogos de Trino
superset/         Configuración de dashboards
infra/
  docker-compose/ Stack local y Dockerfiles
  k3s/            Manifiestos Kubernetes
.ci/scripts/      Lógica de lint, test y deploy
.github/          CI y plantillas
docs/             Documentación, marca y diagramas
```

Las dependencias están separadas en `requirements.txt` y `requirements-dev.txt`:
las herramientas de test no forman parte del entorno de ejecución.

---

## Pipelines de ejemplo

| DAG | Fuente | Frecuencia | Salida |
|---|---|---|---|
| `indicadores_financieros_chile` | [mindicador.cl](https://mindicador.cl) | Lunes a viernes, 10:00 | 5 tablas Delta |
| `arclim_riesgo_climatico_chile` | [ARClim](https://arclim.mma.gob.cl) — MMA Chile | Lunes, 06:00 | 3 tablas Delta |

Ambas APIs son públicas y no requieren clave, de modo que cualquiera que clone
el repositorio puede ejecutar los pipelines completos sin registrarse en ningún
sitio. Fue un criterio de selección: un ejemplo que necesita credenciales no es
un ejemplo.

Son servicios públicos que nadie nos debe, así que el cliente HTTP compartido
(`airflow/plugins/http_publico.py`) se identifica con un User-Agent con URL de
contacto, reintenta 429 y 5xx con backoff respetando `Retry-After`, y espacia
las llamadas de series.

`raw/` es zona de aterrizaje **y cache**: lo ya descargado para una fecha no se
vuelve a pedir, así que reejecutar un DAG mientras se itera sobre el transform
no cuesta ni una llamada. Para refrescar de verdad, disparar con
`forzar_descarga=true`.

**Indicadores financieros**: UF, dólar, euro, UTM y TPM se publican cada día
hábil; el IPC es mensual, así que una serie vacía no se trata como error.

**Riesgo climático**: cuatro indicadores por las 345 comunas de Chile —presente,
futuro y delta— y series de tiempo 1970–2070 bajo escenario SSP5-8.5 para las
capitales regionales. `valor_p10` y `valor_p90` son la envolvente de los 20
modelos climáticos que devuelve la API para cada año, no percentiles de la serie.

ARClim no sirve `total_precipitation` ni `dry_days`: devuelven 500 en `/datos/` y
en `/series/`, en las tres variantes. Están declarados en
`INDICADORES_NO_DISPONIBLES` con la comprobación fechada; basta un atributo de
`total_precipitation` para que falle entera la petición de `/datos/`.

Las escrituras son **idempotentes por fecha de carga**: los jobs usan
`replaceWhere` sobre `fecha_carga` (`fecha_proceso` en indicadores), así que
reejecutar un DAG reemplaza esa carga en lugar de duplicar filas. Los DAGs
declaran `max_active_runs=1` porque la idempotencia no protege de dos
escritores simultáneos sobre la misma fecha.

### Consultas de referencia

```sql
SHOW TABLES FROM delta.bronze;

SELECT indicador, count(*) AS filas, min(fecha) AS desde, max(fecha) AS hasta
FROM delta.bronze.indicadores_todos
GROUP BY indicador;

SELECT nombre, indicador, anio_serie, valor_medio
FROM delta.bronze.arclim_series
WHERE cod_comuna = '13101' AND anio_serie >= 2050
ORDER BY anio_serie;
```

---

## Comandos

```bash
make init-env           # Prepara .env con claves generadas
make setup              # Crea .venv con Python 3.12
make dev-up             # Levanta el stack
make dev-down           # Lo detiene
make dev-ps             # Estado de los contenedores
make dev-logs           # Logs (SERVICE=airflow-scheduler para uno solo)
make dev-build          # Reconstruye las imágenes (tras cambiar un Dockerfile)
make dev-reset          # Borra volúmenes y recrea usuarios
make dev-reset-hard     # Además reconstruye las imágenes locales
make dev-load-example   # Ejecuta los pipelines y configura los dashboards
make lint-all           # Ruff + sqlfluff
make test-all           # Tests
make detect-secrets     # Escaneo de credenciales
make deploy-staging     # Deploy K3s staging
make deploy-prod        # Deploy K3s producción (pide confirmación)
```

Kafka y ZooKeeper no arrancan con `make dev-up`: están detrás de un perfil, para
no encender dos contenedores que hoy nada consume. Para levantarlos:

```bash
cd infra/docker-compose && docker compose --profile streaming up -d
```

`dev-reset` tarda alrededor de un minuto y sirve cuando los datos quedaron
inconsistentes, o tras cambiar `POSTGRES_USER` o `POSTGRES_PASSWORD` — el
usuario se fija al crear el volumen. `dev-reset-hard` tarda unos tres minutos y
hace falta cuando cambiaste algún Dockerfile; si solo necesitas la imagen nueva
sin perder los datos, `dev-build` reconstruye y `dev-up` recrea los contenedores.

---

## Secretos

| Entorno | Herramienta | Estado |
|---|---|---|
| Local | `.env` | Operativo |
| Staging | Sealed Secrets | En evaluación |
| Producción | OpenBao | Planificado |

Ningún archivo del repositorio contiene credenciales. Los que las necesitan
—`marquez.yml`, el `core-site.xml` del metastore— se generan al arrancar el
contenedor a partir del `.env`, y los catálogos de Trino usan interpolación
`${ENV:...}` en tiempo de ejecución.

Las credenciales de MinIO viajan **solo como variables de entorno**
(`AWS_ACCESS_KEY_ID` y `AWS_SECRET_ACCESS_KEY`, que el Compose deriva de
`MINIO_ROOT_USER` y `MINIO_ROOT_PASSWORD`). Nunca se pasan como propiedades de
Spark: un `--conf` acaba en la línea de comandos de `spark-submit` y en el `ps`
del contenedor, aunque el hook lo enmascare en el log. S3A las resuelve con
`EnvironmentVariableCredentialsProvider` y boto3 con su cadena por defecto; un
test del CI verifica que ninguna tarea las reintroduzca en la configuración.

Detalle en [docs/secretos.md](docs/secretos.md).

---

## Contribuir

Las contribuciones son bienvenidas. Antes de tu primer pull request:

- [CONTRIBUTING.md](CONTRIBUTING.md) — flujo de trabajo y firma DCO (`git commit -s`)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — normas de convivencia
- [GOVERNANCE.md](GOVERNANCE.md) — cómo se toman las decisiones
- [SECURITY.md](SECURITY.md) — reporte de vulnerabilidades (**no** por issue público)

Issues y pull requests se aceptan en español o en inglés.

El CI ejecuta lint, tests y escaneo de credenciales en cada pull request. Los
tests cubren el parseo de los DAGs y sus funciones puras; **la ejecución del
stack completo no está automatizada**, así que verifica con `make dev-up` y
`make dev-load-example` antes de proponer cambios en la infraestructura.

---

## Notas de compatibilidad

- **Python 3.12 exacto.** Versiones más nuevas rompen la compilación de pandas,
  que los providers de Airflow acotan a `<2.2`. Driver y executors de Spark
  deben coincidir en versión menor.
- **Spark 4 usa Scala 2.13.** El soporte de 2.12 se eliminó, así que todas las
  coordenadas de JAR cambian respecto a Spark 3.5.
- **AWS SDK v2 en Spark, v1 en el metastore.** Hadoop 3.4 (Spark 4) migró al v2;
  Hadoop 3.3 (imagen de Hive 4.0.0) sigue con el v1. Son artefactos distintos, no
  versiones del mismo. Los Dockerfiles los resuelven con Maven en vez de fijarlos
  a mano, y verifican en tiempo de build que el `hadoop-common` de la imagen
  coincida con el ARG.
- **El metastore está clavado en Hive 4.0.0, y no es una preferencia.** Spark 4
  lleva embebido el cliente de Hive 2.3.10, que llama al método Thrift
  `get_table`. Ese método **se eliminó en Hive 4.0.1**; desde entonces solo
  existe `get_table_req`. Comprobado en el IDL de cada etiqueta:

  | Hive | `get_table` |
  |---|---|
  | 4.0.0 | sí |
  | 4.0.1 · 4.1.0 · 4.2.x | **no** |

  Se intentó subir a 4.2.1: el metastore arranca, `CREATE DATABASE` funciona
  —`get_database` sigue existiendo— y **todas** las escrituras de tabla fallan
  con `Invalid method name: 'get_table'`. Cualquier subida del metastore, aunque
  sea de un parche, rompe el stack mientras Spark use su cliente embebido.

  Salir de ahí exigiría `spark.sql.hive.metastore.jars` con un juego de Hive 4.x
  en la imagen del driver, con los conflictos de classpath que eso trae. No se
  ha hecho porque aquí Hive solo actúa como registro nombre→ubicación: las
  transacciones las gestiona Delta. `dependabot.yml` ignora estas subidas para
  que la propuesta no vuelva cada release.
- **ANSI mode activo por defecto en Spark 4.** Los casts inválidos lanzan
  excepción en lugar de devolver `null`.
- **Airflow 3 exige `execution_api_server_url` y un JWT compartido** entre
  contenedores. Las tareas ya no acceden a la base de metadatos: hablan con el
  api-server por HTTP.
- **Trino usa `s3://`, Spark usa `s3a://`.** El metastore mapea ambos esquemas al
  conector S3A.
- **`apache-airflow-providers-amazon` excluido** por incompatibilidad con
  SQLAlchemy 2.x. El acceso a MinIO se hace con `boto3` directo.

---

## Documentación

| Documento | Contenido |
|---|---|
| [docs/arquitectura.md](docs/arquitectura.md) | Arquitectura, flujo de datos, CI/CD, hardware y decisiones de diseño |
| [docs/secretos.md](docs/secretos.md) | Gestión de credenciales por entorno |
| [docs/airflow-fab-auth.md](docs/airflow-fab-auth.md) | Usuarios y roles en Airflow |
| [docs/marca.md](docs/marca.md) | Manual de marca e imagotipo |
| [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) | Inventario de licencias de terceros |

---

<p align="center">
  <sub>
    Apache 2.0 · Copyright The VektralForge Authors ·
    Patrocinado por <a href="https://alephserver.cl">ALEPH SERVER LTDA.</a>
  </sub>
</p>
