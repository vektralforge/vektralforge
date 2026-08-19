# Third-Party Notices

VektralForge itself is licensed under the [Apache License 2.0](LICENSE). This
document lists the third-party components the project orchestrates, together with
their copyright holders and licence terms.

**How to read this.** VektralForge does not fork, embed, or statically link any of
these components. It composes them: they run as separate services and processes,
and the project ships configuration, DAGs, Spark jobs and glue code that make them
work together. Most are pulled at runtime as container images or installed as
declared dependencies.

That distinction matters for the two components below whose licences are not
Apache 2.0, and it is why they can be part of the stack without affecting the
licence of VektralForge's own code. It does **not** relieve you of assessing your
own obligations for your deployment.

---

## Components requiring attention

These two do not share the permissive terms of the rest of the stack. If you plan
to deploy VektralForge commercially, offer it as a hosted service, or embed it in
a proprietary product, review them with counsel before you do.

### MinIO — GNU AGPL v3.0

Copyright © MinIO, Inc. — https://github.com/minio/minio

The MinIO server, client and gateway are licensed under AGPLv3; the client SDKs
remain under Apache 2.0. AGPLv3's network clause requires that users who interact
with a modified version over a network be able to obtain the corresponding source
code. MinIO states that any commercial or proprietary use of the AGPLv3 software —
including repackaging or reselling features or services — is undertaken at the
user's own risk, and that determining compliance is the user's responsibility, not
MinIO's. MinIO offers a separate commercial licence for cases where the AGPLv3
obligations are triggered.

**If this is a problem for your deployment,** VektralForge's storage layer speaks
the S3 API. Any S3-compatible backend works — AWS S3, Ceph RADOS Gateway,
Garage (AGPLv3), SeaweedFS (Apache 2.0), or a managed provider. MinIO is the
default because it is the most convenient for local development, not because the
project depends on it.

### Graylog Open — Server Side Public License v1

Copyright © Graylog, Inc. — https://github.com/Graylog2/graylog2-server

Releases before Graylog 4.0 were GPLv3; from 4.0 onward, including the free
Graylog Open tier, the licence is SSPL v1. The SSPL is based on the GPL but was
authored by MongoDB and **has not been approved by the Open Source Initiative**.
Its section 13 sets out obligations for anyone offering the software as a service:
in that case the management, interface, API, automation, monitoring, backup,
storage and hosting software must all be released under SSPL terms.

Self-hosting Graylog for your own log management does not trigger section 13.
Offering it as part of a service to third parties may.

**Alternatives** if SSPL is unacceptable in your context: Grafana Loki (AGPLv3),
OpenSearch (Apache 2.0), or Vector (MPL 2.0) with a backend of your choice.
Logging is the most loosely coupled part of the stack and the easiest to swap.

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
| Redis                   | BSD-3-Clause (see note) | https://github.com/redis/redis              |
| Apache ZooKeeper        | Apache-2.0              | https://github.com/apache/zookeeper         |
| MinIO                   | **AGPL-3.0**            | https://github.com/minio/minio              |
| Graylog Open            | **SSPL-1.0**            | https://github.com/Graylog2/graylog2-server |

A note on **OpenBao**: it is the Linux Foundation fork of HashiCorp Vault, created
after Vault moved to the Business Source Licence. OpenBao remains under MPL 2.0,
which is why VektralForge uses it rather than Vault.

A note on **Redis**: the image is pinned to 7.2, which is BSD-3-Clause. From 7.4
onward Redis moved to a dual RSALv2 / SSPLv1 licence that is not OSI-approved.
The pin is what preserves the permissive terms, so an automated version bump
would silently change them. Valkey, the Linux Foundation fork, stays under
BSD-3-Clause if you prefer a version that keeps receiving updates on those terms.

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

## Container images

The `docker-compose` and Kubernetes manifests reference upstream images published
by each project. VektralForge does not republish or modify them. Each image
carries the licence of its upstream project, plus the licences of the base image
and system packages it contains. Run a scanner such as `syft` or `trivy` against
the images if you need a component-level inventory for your own compliance
process.

---

## Maintaining this file

This inventory is reviewed when a component is added, removed, or upgraded across
a major version, and at least once a year. Licences change: Vault, Elastic, Redis
and Graylog itself all illustrate the point. If you notice an entry that has gone
stale, please open a pull request or an issue — corrections are welcome and
useful.

## Disclaimer

This document is provided as a good-faith inventory to help you assess your own
obligations. **It is not legal advice, and it is not a legal opinion about your
deployment.** Licence compatibility depends on how you use, modify, distribute and
offer the software, and those facts are yours, not ours. Consult qualified counsel
for your specific situation.

Report errors or omissions to `opensource@vektralforge.org`.
