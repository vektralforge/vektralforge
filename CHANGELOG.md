# Changelog

All notable changes to VektralForge are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Until 1.0.0, the public interface — Compose service names, environment
variables, `make` targets and table schemas — may change in a minor release.
Anything that requires manual action on an existing installation is called out
under **Upgrading**.

## [Unreleased]

### Changed

- **Valkey `9.1` sustituye a Redis como caché de Superset.** El #72 había subido
  Redis de 7.2 a 8.0 como un bump de Dependabot más, y con él la licencia pasó
  de BSD-3-Clause a RSALv2/SSPLv1/AGPLv3 mientras la documentación seguía
  diciendo 7.2. Valkey es el fork de la Linux Foundation, BSD-3-Clause y
  compatible a nivel de protocolo: Superset no cambia de cliente. Dependabot
  deja de proponer saltos mayores de Valkey.

- **MinIO queda sustituido por RustFS `1.0.0-rc.6`.** MinIO se archivó en 2026 y
  ninguna imagen pública lleva el parche de `CVE-2025-62506`, así que no había
  versión a la que subir. RustFS es Apache 2.0 —el stack pierde su única
  dependencia AGPLv3— y habla la misma política de IAM de AWS, de modo que
  `politica-datos.json` se reutiliza sin cambios. La imagen se construye en
  `infra/docker-compose/s3/Dockerfile` para hornear dentro el CLI `rc`, que
  upstream publica como artefacto separado: sin él la credencial raíz tendría
  que viajar por argv o por el entorno, deshaciendo el #54 y el #55.
- **La configuración del object store deja de llamarse MinIO.** `MINIO_*` pasa a
  `S3_*`, `credenciales_minio.sh` a `credenciales_s3.sh` y la política a
  `infra/docker-compose/s3/`. Va en un commit propio: es renombrado, sin cambio
  de comportamiento.

- **Branch protection is now enforced on `develop` and `main`.** Merging needs a
  pull request, one approving review from somebody other than the author, and
  the `CI` and DCO checks green. Direct pushes, force pushes and branch deletion
  are refused — with an empty bypass list, so the rule applies to repository
  admins too.

### Removed

- **Graylog sale del inventario de licencias y de la documentación.** Figuraba
  como componente del stack y como la única dependencia no permisiva (SSPL-1.0),
  pero nunca estuvo: no hay servicio en el Compose, ningún contenedor declara un
  driver de logging que apunte a él y no existe manifiesto de K3s que lo
  despliegue. Estaba «en evaluación» para logging centralizado y la evaluación
  queda cerrada; `docs/arquitectura.md` recoge el hueco que deja y los
  candidatos vivos (Loki, OpenSearch, Vector). Con esto, y con la salida de
  MinIO, **todos los componentes del stack son de licencia permisiva**.

### Upgrading

- **Hay que renombrar las claves del `.env`.** Compose interpola `${S3_ROOT_USER}`
  directamente, así que un `.env` con nombres `MINIO_*` deja el stack sin
  arrancar. Con `sed -i -E 's/^MINIO_/S3_/' infra/docker-compose/.env` se
  conservan los valores; `make init-env` genera uno nuevo.
- **El volumen de datos cambia de nombre** (`minio-data` → `s3-data`) y el
  backend es otro, así que los objetos del volumen anterior no se reutilizan:
  `make dev-reset` y `make dev-load-example` los recrean. El volumen viejo queda
  huérfano y se borra con `docker volume rm docker-compose_minio-data`.
- **El servicio pasa a llamarse `rustfs`**: cualquier guion propio con
  `docker exec docker-compose-minio-1` hay que ajustarlo.
- **El servicio `redis` pasa a llamarse `valkey`.** El contenedor anterior queda
  huérfano y sigue escuchando en el 6379, así que el nuevo no puede publicar el
  puerto: levantar con `docker compose up -d --remove-orphans` (o `make
  dev-reset`). La caché no se migra: son datos regenerables. `REDIS_URL` sale
  de `.env.example` porque no la leía nadie; si está en tu `.env`, no estorba.

## [0.1.0] — 2026-09-03

First tagged release. The stack has been running end to end for some time; this
tag exists so that people can say which version they are running, report against
it, and depend on it.

### Added

- **Local LakeHouse stack** on Docker Compose: Apache Airflow 3.3.0, Apache
  Spark 4.1.3 with Delta Lake 4.1.0, Hive Metastore 4.0.0, Trino 448, MinIO,
  Apache Superset 6.1.0, OpenLineage 1.52.0 with Marquez, PostgreSQL 15, Redis
  and OpenBao. Kafka and ZooKeeper sit behind the optional `streaming` profile.
- **Two example pipelines** over Chilean public data — ARClim climate risk and
  `mindicador.cl` financial indicators — writing Delta tables and building
  Superset dashboards, with no API key required.
- **End-to-end lineage.** Airflow tasks and their Spark jobs appear as one graph
  in Marquez, not as disconnected runs.
- **A Hive Metastore shared between Spark and Trino**, so a table written by a
  job is queryable from Trino without registering it by hand.
- **89 tests** plus 16 pin-coherence checks, and a CI that runs linting, SQL
  linting, secret scanning and a DCO check.

### Security

Most of the work in this release went here. Every item was verified against the
running stack, not only in review:

- **Credentials are delivered as mounted files, never as environment
  variables** — neither the PostgreSQL password nor the three MinIO service
  keys appear in `docker inspect`, in `docker compose config` or in
  `/proc/<pid>/environ`.
- **One least-privilege MinIO service account per consumer**
  (`vf-pipeline`, `vf-hive`, `vf-trino`), scoped by policy to object operations
  on the five buckets. The root account is confined to the `minio` service and
  to the provisioning script. Previously five of six consumers used root.
- **No credential on a command line**, on the host or inside the containers,
  with one documented residual (`mc admin user svcacct add`, which accepts a
  secret no other way).
- **Ports bind to loopback by default**, configurable with `BIND_HOST`.
- **No image on a moving tag.** Every image, including the ones the project
  builds, is pinned to a version.
- **The whole git history was audited**, not only the working tree, in two
  entropy passes. `make auditar-historial` makes it repeatable, and
  `.ci/historial-revisado.txt` records what was found and why it was accepted.
  See the last item under *Known limitations* for what it found.

### Known limitations

Stated here rather than discovered later:

- **There is no deployment.** K3s is planned; `make deploy-staging` and
  `make deploy-prod` fail with a message explaining what is missing.
- **MinIO is pinned to an archived upstream.** `RELEASE.2025-04-08` is the last
  release with a full administration console; the project was archived in 2026
  and no published image carries the fix for `CVE-2025-62506`. Acceptable for a
  local development stack on loopback, and not for anything else.
- **The CI does not build images and does not start containers.** A green check
  means the linters and the DCO are satisfied; it does not mean the stack runs.
- **Four dead example credentials remain in the git history.** For a few days in
  August 2026, `.env.example` carried generated values instead of placeholders:
  the Airflow Fernet key, its API secret and JWT secret, and the Superset secret
  key. None of them is used by any installation — `make init-env` generates a
  fresh set per install, and the current `.env.example` says `GENERAR`. They are
  in `.ci/historial-revisado.txt`, and the history is deliberately not being
  rewritten: it would invalidate every commit hash referenced anywhere for four
  secrets that unlock nothing.

[Unreleased]: https://github.com/vektralforge/vektralforge/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/vektralforge/vektralforge/releases/tag/v0.1.0
