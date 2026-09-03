<p align="center">
  <img src="docs/brand/logo/vektralforge-logo-horizontal-dark.svg#gh-dark-mode-only" width="420" alt="VektralForge">
  <img src="docs/brand/logo/vektralforge-logo-horizontal-light.svg#gh-light-mode-only" width="420" alt="VektralForge">
</p>

<p align="center">
  <strong>An open source data lakehouse with lineage built in</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-B4552D" alt="Apache 2.0"></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/contributions-DCO-B4552D" alt="DCO"></a>
  <a href="GOVERNANCE.md"><img src="https://img.shields.io/badge/governance-TSC-B4552D" alt="Governance"></a>
  <a href="../../actions/workflows/ci.yml"><img src="../../actions/workflows/ci.yml/badge.svg?branch=develop" alt="CI"></a>
</p>

<p align="center">
  <strong>English</strong> · <a href="README.es.md">Español</a>
</p>

---

VektralForge wires Apache Airflow, Spark, Delta Lake, Trino and Superset into
one stack, with end-to-end traceability through OpenLineage and Marquez. It runs
locally on Docker Compose; a K3s deployment is planned but **not implemented**
yet — see [Deployment](#deployment).

Two real pipelines ship with it, both against public Chilean APIs that need no
credentials: financial indicators from mindicador.cl and municipal climate risk
from ARClim (Chilean Ministry of the Environment).

**[Apache 2.0](LICENSE) with a [DCO](CONTRIBUTING.md) instead of a CLA**:
copyright stays distributed among the people who contribute rather than
concentrated in one company. See [OPEN_SOURCE_PROMISE.md](OPEN_SOURCE_PROMISE.md).

Sponsored by [ALEPH SERVER LTDA.](https://alephserver.cl), which funds the
project without controlling it — see [SPONSORS.md](SPONSORS.md) and
[GOVERNANCE.md](GOVERNANCE.md).

---

## Stack

| Component | Version | Role |
|---|---|---|
| Apache Airflow | 3.3.0 | Orchestration |
| Apache Spark | 4.1.3 | Processing and ACID writes |
| Delta Lake | 4.1.0 | Transactional table format |
| Apache Hive Metastore | 4.0.0 | Catalogue shared by Spark and Trino |
| Trino | 448 | SQL query engine |
| MinIO | 2025-04 | S3 object storage · see note |
| Apache Superset | 6.1.0 | Visualisation |
| OpenLineage | 1.52.0 | Lineage in Airflow and Spark |
| Marquez | 0.51.1 | Lineage store and UI |
| PostgreSQL | 15 | Metadata |
| Redis | 7.2 | Superset cache (metadata and chart data) |
| OpenBao | 2.1.0 | Secrets (dev mode locally) |
| Apache Kafka | 7.6.1 (CP) | Optional `streaming` profile; no pipeline yet |
| Apache ZooKeeper | 7.6.1 (CP) | Optional `streaming` profile; serves Kafka only |

**Python 3.12 everywhere**: the Spark driver and its executors must agree on the
minor version or PySpark refuses to run.

**About MinIO.** The version is pinned on purpose to `RELEASE.2025-04-08`: it is
the last one that keeps the full administration console, which MinIO removed
from the community edition in the following release. The project then shut down
— last published image in September 2025, repository archived in 2026 — so
**there is no later version to move to**, and no published image carries the fix
for `CVE-2025-62506` (privilege escalation, high severity). That is an accepted
risk for a local development stack bound to loopback, and it is not acceptable
for anything else. The way out is not another MinIO release but another backend:
the storage layer speaks S3 and nothing in the project depends on MinIO in
particular — see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

Third-party licences, including the two that are not permissive — MinIO (AGPLv3)
and Graylog (SSPL) — are listed in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

---

## Getting started

### Requirements

```bash
docker --version        # >= 24.0
docker compose version  # >= 2.20
python3.12 --version    # exactly 3.12 — brew install python@3.12
make --version
```

Docker Desktop needs at least **8 GB of RAM** allocated
(Settings → Resources → Memory). With less, containers are killed by the OOM
reaper.

### Start it

```bash
git clone https://github.com/vektralforge/vektralforge.git
cd vektralforge

make init-env          # Generates keys, offers a password per service
make setup             # Creates .venv with Python 3.12
make dev-up            # Brings the stack up
make dev-load-example  # Runs the pipelines and builds the dashboards
```

`make init-env` creates `infra/docker-compose/.env` from `.env.example`: it
generates the cryptographic keys and offers a password per service, which you can
accept or replace. It is idempotent, so run it again whenever new variables
appear.

`make dev-load-example` takes about five minutes the first time.

### Services

| Service | URL |
|---|---|
| Airflow | http://localhost:8090 |
| Superset | http://localhost:8088 |
| Trino | http://localhost:8081 |
| MinIO | http://localhost:9001 |
| Marquez (lineage) | http://localhost:3000 |
| Spark Master | http://localhost:8082 |
| OpenBao | http://localhost:8200 |

Credentials live in `infra/docker-compose/.env`, mode 600. `make dev-up` **does
not print them**: the closing banner shows the name of each variable instead. To
read one:

```bash
grep '^AIRFLOW_ADMIN_PASSWORD=' infra/docker-compose/.env | cut -d= -f2-
```

Trino, Spark and Marquez ask for no credentials at all: anyone who reaches those
ports is in. That is why `.env` sets `BIND_HOST=127.0.0.1`.

---

## Architecture

**Spark writes, Trino reads.** ACID operations on Delta Lake — `MERGE`,
`UPDATE`, `DELETE`, `VACUUM` — are Spark's job; Trino provides interactive SQL
over the same tables.

Both share the Hive Metastore. Jobs write with `saveAsTable` rather than
`save(path)`, so a table is registered in the catalogue by the same act that
writes it and Trino sees it without a second registration step. Adding a pipeline
does not mean touching a registration script: writing to `bronze` is enough.

```
public API → Airflow → Spark → Delta Lake → MinIO
                                    ↓
                        Hive Metastore (shared)
                                    ↓
                                 Trino → Superset

     OpenLineage captures lineage at every step → Marquez
```

Lineage is captured at two levels. Airflow's OpenLineage provider emits the run
of each task; the `OpenLineageSparkListener` — declared in the
`spark-defaults.conf` shared by the Airflow and Spark images — emits each job's
input and output datasets. Airflow injects the parent job and the transport URL
into every `spark-submit`, so the Spark run hangs off its task in Marquez instead
of appearing as a disconnected graph.

Spark 4 support landed in OpenLineage 1.37.0; earlier versions do not work with
this stack.

The layers follow the medallion pattern: `raw/` holds the raw API response,
`bronze/` the typed Delta tables, `silver/` and `gold/` the derived models.

Full detail in [docs/arquitectura.md](docs/arquitectura.md) (Spanish).

### Layout

```
airflow/          DAGs, plugins and tests
spark/            PySpark jobs and tests
trino/catalog/    Trino catalogues
superset/         Dashboard configuration
infra/
  docker-compose/ Local stack and Dockerfiles
  k3s/            Namespaces — the deployment is planned, not implemented
.ci/scripts/      Lint, test and deploy logic
.github/          CI and templates
docs/             Documentation, brand and diagrams
```

Dependencies are split between `requirements.txt` and `requirements-dev.txt`:
test tooling is not part of the runtime environment.

---

## Example pipelines

| DAG | Source | Schedule | Output |
|---|---|---|---|
| `indicadores_financieros_chile` | [mindicador.cl](https://mindicador.cl) | Weekdays, 10:00 | 5 Delta tables |
| `arclim_riesgo_climatico_chile` | [ARClim](https://arclim.mma.gob.cl) — Chilean MMA | Mondays, 06:00 | 3 Delta tables |

Both APIs are public and need no key, so anyone who clones the repository can run
the full pipelines without registering anywhere. That was a selection criterion:
an example that needs credentials is not an example.

They are public services nobody owes us, so the shared HTTP client
(`airflow/plugins/http_publico.py`) identifies itself with a User-Agent carrying
a contact URL, retries 429 and 5xx with backoff while honouring `Retry-After`,
and spaces out series calls.

`raw/` is both a landing zone **and a cache**: whatever has already been
downloaded for a date is not requested again, so re-running a DAG while iterating
on the transform costs no API calls at all. To genuinely refresh, trigger with
`forzar_descarga=true`.

**Financial indicators**: UF, dollar, euro, UTM and TPM are published every
business day; CPI is monthly, so an empty series is not treated as an error.

**Climate risk**: four indicators across the 345 municipalities of Chile —
present, future and delta — plus 1970–2070 time series under the SSP5-8.5
scenario for regional capitals. `valor_p10` and `valor_p90` are the envelope of
the 20 climate models the API returns for each year, not percentiles of the
series.

ARClim does not serve `total_precipitation` or `dry_days`: both return 500 from
`/datos/` and `/series/`, in all three variants. They are declared in
`INDICADORES_NO_DISPONIBLES` with the date the check was made; a single
`total_precipitation` attribute is enough to fail an entire `/datos/` request.

Writes are **idempotent per load date**: jobs use `replaceWhere` over
`fecha_carga` (`fecha_proceso` for the indicators), so re-running a DAG replaces
that load rather than duplicating rows. The DAGs declare `max_active_runs=1`,
because idempotency does not protect against two concurrent writers on the same
date.

### Sample queries

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

## Commands

```bash
make init-env           # Prepares .env with generated keys
make setup              # Creates .venv with Python 3.12
make dev-up             # Brings the stack up
make dev-down           # Stops it
make dev-ps             # Container status
make dev-logs           # Logs (SERVICE=airflow-scheduler for just one)
make dev-build          # Rebuilds the images (after changing a Dockerfile)
make dev-reset          # Wipes volumes and recreates users
make dev-reset-hard     # Also rebuilds the local images
make dev-load-example   # Runs the pipelines and builds the dashboards
make lint-all           # Ruff + sqlfluff
make test-all           # Tests
make detect-secrets     # Credential scan (working tree)
make auditar-historial  # Credential scan (git history)
```

Kafka and ZooKeeper do not start with `make dev-up`: they sit behind a profile,
so that two containers nothing currently consumes are not left running. To bring
them up:

```bash
cd infra/docker-compose && docker compose --profile streaming up -d
```

`dev-reset` takes about a minute and is what you want when the data ended up
inconsistent, or after changing `POSTGRES_USER` or `POSTGRES_PASSWORD` — the user
is fixed when the volume is created. `dev-reset-hard` takes about three minutes
and is needed after changing a Dockerfile; if you only need the new image without
losing data, `dev-build` rebuilds and `dev-up` recreates the containers.

### Deployment

The K3s deployment is **planned, not implemented**. `make deploy-staging` and
`make deploy-prod` exist but fail with a message explaining what is missing: the
service manifests, and before those, publishing the project's images to a
registry. See the "Despliegue a K3s" issue.

```bash
make deploy-staging     # Planned — currently fails explaining what is missing
make deploy-prod        # Planned — likewise
```

---

## Secrets

| Environment | Tool | Status |
|---|---|---|
| Local | `.env` | Working |
| Staging | Sealed Secrets | Under evaluation |
| Production | OpenBao | Planned |

No file in the repository contains credentials. The ones that need them —
`marquez.yml`, the `core-site.xml` shared by Spark, Airflow and the metastore,
and the Trino catalogues — are generated when the container starts, from the
secrets Compose delivers as files under `/run/secrets/`.

MinIO credentials **do not travel as environment variables**. Each consumer signs
in with its own service account — `vf-pipeline`, `vf-hive`, `vf-trino`; none of
them root — scoped by
`infra/docker-compose/minio/politica-datos.json` to object operations on the five
buckets. Its key arrives as a mounted file, out of reach of `docker inspect`,
`docker compose config` and `/proc/<pid>/environ`, and the entrypoint
materialises it in whatever form each consumer knows how to read: S3A in
`core-site.xml` with `SimpleAWSCredentialsProvider`, boto3 in the INI pointed at
by `AWS_SHARED_CREDENTIALS_FILE`, and Trino in the catalogue it renders at
startup. Only the `minio` service and `init_users.sh` — which legitimately create
buckets and accounts — receive the root credentials.

They are not passed as Spark properties either: a `--conf` ends up on the
`spark-submit` command line and in the container's `ps`, even though the hook
masks it in the log. A CI test verifies that no task reintroduces them into the
configuration.

Detail in [docs/secretos.md](docs/secretos.md) (Spanish).

---

## Contributing

Contributions are welcome. Before your first pull request:

- [CONTRIBUTING.md](CONTRIBUTING.md) — workflow and DCO sign-off (`git commit -s`)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — community standards
- [GOVERNANCE.md](GOVERNANCE.md) — how decisions get made
- [SECURITY.md](SECURITY.md) — vulnerability reports (**not** through a public issue)

**Language.** Governance documents and this README are in English; the Spanish
README, the documentation under `docs/` and the code comments are in Spanish.
Issues and pull requests are accepted in either language. See CONTRIBUTING.md.

CI runs linting, tests and a credential scan on every pull request. The tests
cover DAG parsing and pure functions; **running the full stack is not
automated**, so verify with `make dev-up` and `make dev-load-example` before
proposing infrastructure changes.

---

## Compatibility notes

- **Exactly Python 3.12.** Newer versions break the pandas build, which the
  Airflow providers cap at `<2.2`. The Spark driver and executors must agree on
  the minor version.
- **Spark 4 uses Scala 2.13.** Support for 2.12 was removed, so every JAR
  coordinate changes relative to Spark 3.5.
- **AWS SDK v2 in Spark, v1 in the metastore.** Hadoop 3.4 (Spark 4) moved to v2;
  Hadoop 3.3 (the Hive 4.0.0 image) is still on v1. They are different artifacts,
  not versions of the same one. The Dockerfiles resolve them with Maven rather
  than pinning by hand, and verify at build time that the image's
  `hadoop-common` matches the ARG.
- **The metastore is nailed to Hive 4.0.0, and that is not a preference.**
  Spark 4 embeds the Hive 2.3.10 client, which calls the Thrift method
  `get_table`. That method **was removed in Hive 4.0.1**; since then only
  `get_table_req` exists. Checked against the IDL of each tag:

  | Hive | `get_table` |
  |---|---|
  | 4.0.0 | yes |
  | 4.0.1 · 4.1.0 · 4.2.x | **no** |

  An upgrade to 4.2.1 was attempted: the metastore starts, `CREATE DATABASE`
  works — `get_database` still exists — and **every** table write fails with
  `Invalid method name: 'get_table'`. Any metastore upgrade, even a patch,
  breaks the stack while Spark uses its embedded client.

  Getting out would mean `spark.sql.hive.metastore.jars` with a Hive 4.x set in
  the driver image, and the classpath conflicts that brings. It has not been done
  because here Hive only acts as a name→location registry: transactions are
  Delta's job. `dependabot.yml` ignores these upgrades so the proposal does not
  come back every release.
- **ANSI mode is on by default in Spark 4.** Invalid casts raise instead of
  returning `null`.
- **Airflow 3 requires `execution_api_server_url` and a shared JWT** across
  containers. Tasks no longer reach the metadata database: they talk to the
  api-server over HTTP.
- **Trino writes `s3://`, Spark writes `s3a://`.** The metastore maps both
  schemes onto the S3A connector.
- **`apache-airflow-providers-amazon` is excluded** because of incompatibility
  with SQLAlchemy 2.x. MinIO access goes through `boto3` directly.

---

## Documentation

| Document | Contents |
|---|---|
| [docs/arquitectura.md](docs/arquitectura.md) | Architecture, data flow, CI/CD, hardware and design decisions |
| [docs/secretos.md](docs/secretos.md) | Credential management per environment |
| [docs/airflow-fab-auth.md](docs/airflow-fab-auth.md) | Users and roles in Airflow |
| [docs/marca.md](docs/marca.md) | Brand manual |
| [CHANGELOG.md](CHANGELOG.md) | Release history |
| [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) | Third-party licence inventory |

Documents under `docs/` are in Spanish.

---

<p align="center">
  <sub>
    Apache 2.0 · Copyright The VektralForge Authors ·
    Sponsored by <a href="https://alephserver.cl">ALEPH SERVER LTDA.</a>
  </sub>
</p>
