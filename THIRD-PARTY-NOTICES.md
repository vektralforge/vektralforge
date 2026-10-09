# Third-Party Notices

VektralForge itself is licensed under the [Apache License 2.0](LICENSE). This
document lists the third-party components the project orchestrates, together with
their copyright holders and licence terms.

**How to read this.** VektralForge composes third-party components rather than
forking them: they run as separate services and processes, and the project ships
configuration, DAGs, Spark jobs and glue code that make them work together. Most
are pulled at runtime as container images or installed as declared dependencies.

That distinction matters for the component below whose licence is not Apache 2.0,
and it is why it can be part of the stack without affecting the licence of
VektralForge's own code. It does **not** relieve you of assessing your own
obligations for your deployment.

**There is one exception.** Since October 2026 the `vektralforge/rustfs` image
copies one binary in at build time, so that binary *is* redistributed by this
project rather than merely orchestrated. It has its own section below —
[Binaries vendored into VektralForge
images](#binaries-vendored-into-vektralforge-images).

---

## Every component is permissively licensed

As of October 2026 nothing in the stack carries copyleft or a source-available
licence, and the project redistributes no copyleft binary. Two entries in the
tables below still carry a note worth reading — Redis, whose permissive terms
depend on the version pin, and OpenBao, which exists because Vault's did not
survive — but neither constrains how you deploy, offer or embed VektralForge.

Getting here took two removals. **MinIO** (AGPLv3) was the storage backend until
October 2026 and was replaced by RustFS (Apache 2.0). **Graylog Open** (SSPL-1.0)
was listed as a stack component but was never one: it had no service in the
Compose file, no logging driver pointed at it and no Kubernetes manifest declared
it. It was under evaluation for centralised logging and the evaluation is closed
— see the architecture document for what logging is still missing and why the
SSPL ruled this candidate out.

---

## Core stack

| Component               | Licence                 | Source                                      |
| ----------------------- | ----------------------- | ------------------------------------------- |
| Apache Airflow          | Apache-2.0              | https://github.com/apache/airflow           |
| Apache Spark / PySpark  | Apache-2.0              | https://github.com/apache/spark             |
| Delta Lake              | Apache-2.0              | https://github.com/delta-io/delta           |
| Apache Hive (Metastore) | Apache-2.0              | https://github.com/apache/hive              |
| Trino                   | Apache-2.0              | https://github.com/trinodb/trino            |
| Apache Superset         | Apache-2.0              | https://github.com/apache/superset          |
| Apache Kafka            | Apache-2.0              | https://github.com/apache/kafka             |
| OpenLineage             | Apache-2.0              | https://github.com/OpenLineage/OpenLineage  |
| Marquez                 | Apache-2.0              | https://github.com/MarquezProject/marquez   |
| OpenBao                 | MPL-2.0                 | https://github.com/openbao/openbao          |
| PostgreSQL              | PostgreSQL Licence      | https://www.postgresql.org/about/licence/   |
| Valkey                  | BSD-3-Clause (see note) | https://github.com/valkey-io/valkey         |
| Apache ZooKeeper        | Apache-2.0              | https://github.com/apache/zookeeper         |
| RustFS                  | Apache-2.0              | https://github.com/rustfs/rustfs            |

A note on **OpenBao**: it is the Linux Foundation fork of HashiCorp Vault, created
after Vault moved to the Business Source Licence. OpenBao remains under MPL 2.0,
which is why VektralForge uses it rather than Vault.

A note on **Valkey**: it replaces Redis as Superset's cache. Redis moved to a
dual RSALv2 / SSPLv1 licence from 7.4 and added AGPLv3 as a third option from
8.0; none of the three is permissive. Valkey is the Linux Foundation fork of
Redis 7.2.4 and remains under BSD-3-Clause. Being hosted by a foundation means
the trademark is not held by a single vendor, which is what allowed the Redis
relicensing in the first place. Major-version bumps are excluded from
Dependabot and reviewed by hand.

A note on **Kafka**: the images come from `confluentinc/cp-kafka` and
`confluentinc/cp-zookeeper`, which package Apache Kafka under Apache 2.0. Other
images in the `cp-` family — `cp-server` among them — carry the Confluent
Community Licence instead, which is not OSI-approved. Check the image name if
you change it.

## Python dependencies

The full transitive dependency tree, with licences, is generated from the
project's lockfiles rather than maintained by hand. To reproduce it:

```bash
pip install pip-licenses
pip-licenses --format=markdown --with-urls --with-license-file \
  --output-file docs/PYTHON-DEPENDENCIES.md
```

GitHub's dependency graph is enabled on this repository and shows licence
information for every declared dependency, including transitive ones, under the
Insights tab.

## Fonts and brand assets

| Asset          | Licence                   | Source                                          |
| -------------- | ------------------------- | ----------------------------------------------- |
| Space Grotesk  | SIL Open Font License 1.1 | https://github.com/floriankarsten/space-grotesk |
| JetBrains Mono | SIL Open Font License 1.1 | https://github.com/JetBrains/JetBrainsMono      |
| Inter          | SIL Open Font License 1.1 | https://github.com/rsms/inter                   |

The wordmark in `docs/brand/` ships as vector paths rather than text, so **no
font file is redistributed** by this repository. Converting to outlines is also
what keeps the logo rendering identically everywhere: an SVG declaring
`font-family` falls back to Arial wherever the font is absent, including on
GitHub.

The VektralForge name, wordmark and logo are **not** covered by the Apache
licence — see [TRADEMARK.md](TRADEMARK.md).

## JAR dependencies

These are downloaded at build time into the Spark, Airflow and Hive Metastore
images. They are not vendored in this repository; the Dockerfiles resolve them
through Maven so that the versions stay consistent with the base images.

| Artefact                            | Licence          | Notes                                                |
| ----------------------------------- | ---------------- | ---------------------------------------------------- |
| `io.delta:delta-spark_2.13`         | Apache-2.0       | Delta Lake for Spark 4 / Scala 2.13                  |
| `io.delta:delta-storage`            | Apache-2.0       | Delta transaction log storage layer                  |
| `org.apache.hadoop:hadoop-aws`      | Apache-2.0       | S3A connector                                        |
| `software.amazon.awssdk:bundle`     | Apache-2.0       | AWS SDK v2, required by Hadoop 3.4                   |
| `com.amazonaws:aws-java-sdk-bundle` | Apache-2.0       | AWS SDK v1, required by Hadoop 3.3 in the Hive image |
| `org.antlr:antlr4-runtime`          | **BSD-3-Clause** | Parser runtime; the only non-Apache entry here       |
| PostgreSQL JDBC driver              | BSD-2-Clause     | Metastore connection                                 |

All are permissive and compatible with Apache 2.0. Note that Spark 4 (Hadoop
3.4) uses the AWS SDK **v2** while the Hive Metastore image (Hadoop 3.3) still
uses **v1** — they are different artefacts under different group IDs, not
versions of the same one.

## Binaries vendored into VektralForge images

Everything above is orchestrated. This one is **redistributed**: the
`vektralforge/rustfs` image is built from the upstream `rustfs/rustfs` image with
the binary copied in at build time (`infra/docker-compose/s3/Dockerfile`), so
whoever pulls that image receives it and its terms travel with it.

| Binary | Licence | Source | Why it is in the image |
| ------ | ------- | ------ | ---------------------- |
| `rc` — RustFS CLI | Apache-2.0 OR MIT | https://github.com/rustfs/cli | Upstream publishes the CLI as a separate artefact; unlike MinIO's `mc`, it does not ship inside the server image. `init_users.sh` needs it *inside* the container so the root credential can arrive over a pipe instead of through argv or the environment. |

This entry is different in kind from the rest of the document — the binary is
dual-licensed Apache-2.0 OR MIT and raises no obligation beyond attribution,
which is what this table is — but it is listed because redistribution is a
different relationship from orchestration, and the distinction should be visible
rather than assumed.

An earlier revision of this section also listed busybox (GPL-2.0-only), copied
from Alpine for the container healthcheck. It was removed once it was verified
that the RustFS image already carries curl: **VektralForge redistributes no
copyleft binary.**

## Container images

The `docker-compose` and Kubernetes manifests reference upstream images published
by each project. Except for `vektralforge/rustfs`, described in the section
above, VektralForge does not republish or modify them. Each image
carries the licence of its upstream project, plus the licences of the base image
and system packages it contains. Run a scanner such as `syft` or `trivy` against
the images if you need a component-level inventory for your own compliance
process.

---

## Maintaining this file

This inventory is reviewed when a component is added, removed, or upgraded across
a major version, and at least once a year. Licences change — Vault, Elastic,
Redis and Graylog all illustrate the point — and so does the inventory itself:
Graylog sat in this file as a stack component for months without ever being one.
If you notice an entry that has gone stale, please open a pull request or an
issue; corrections are welcome and useful.

## Disclaimer

This document is provided as a good-faith inventory to help you assess your own
obligations. **It is not legal advice, and it is not a legal opinion about your
deployment.** Licence compatibility depends on how you use, modify, distribute and
offer the software, and those facts are yours, not ours. Consult qualified counsel
for your specific situation.

Report errors or omissions to `opensource@vektralforge.org`.
