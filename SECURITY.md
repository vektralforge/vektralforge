# Security Policy

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues,
discussions, or pull requests.**

Use either of these private channels:

**GitHub Private Vulnerability Reporting** — preferred. Go to the
[Security tab](https://github.com/vektralforge/vektralforge/security/advisories/new)
of the repository and open a draft advisory. This keeps the report, the
discussion and the eventual fix in one private place, and lets us credit you
automatically when the advisory is published.

**Email** — `security@vektralforge.org`, monitored by the
`@vektralforge/security` team.

Please include, as far as you can determine it:

- The type of issue and the component affected
- Affected versions or commit range
- Steps to reproduce, or a proof of concept
- The impact you believe an attacker could achieve
- Any configuration required to trigger it

## What to expect

| Stage | Target |
| --- | --- |
| Acknowledgement of your report | 3 business days |
| Initial assessment and severity | 10 business days |
| Status updates while open | Every 14 days |
| Fix and coordinated disclosure | Depends on severity and complexity |

We follow coordinated disclosure. We will agree a disclosure date with you and
credit you in the advisory unless you prefer to remain anonymous. If we conclude
a report is not a vulnerability, we will explain why rather than simply closing
it.

These are the targets of a small volunteer team, not a contractual commitment. If
you have not heard from us within the acknowledgement window, please send a
follow-up — occasionally mail goes astray.

## Scope

**In scope:** the VektralForge codebase, its build and release pipeline, its
default configurations, its container images, and the project's own
infrastructure (`vektralforge.org`, the GitHub organisation, published packages).

**Out of scope:** vulnerabilities in upstream components — Apache Airflow, Spark,
Delta Lake, MinIO, Hive Metastore, Trino, Superset, Kafka, OpenBao, Marquez,
Graylog and their dependencies. Please report those to the respective projects.
If the issue is in how VektralForge *configures* or *integrates* one of these, it
is in scope and we want to hear about it.

Also out of scope: findings from automated scanners without a demonstrated
impact, denial of service through resource exhaustion in a development
configuration, and reports concerning deployments operated by third parties
rather than by the project.

## Deployment security

VektralForge ships development defaults intended for local work. They are not
production-hardened. Before deploying, review at minimum:

- Every default credential in `.env` and the Compose files
- Secrets management — OpenBao, or your platform's equivalent
- Network exposure of MinIO, Trino, Superset and the Airflow web interface
- TLS termination for every exposed service
- Object storage bucket policies

Deployments that process personal data in Chile fall under **Ley 21.719**.
The project's documentation is not legal advice; consult your Data Protection
Officer or counsel about your obligations.

## Safe harbour

We will not pursue legal action against researchers who act in good faith, avoid
privacy violations and service disruption, and give us reasonable time to respond
before public disclosure.

## Supported versions

Until the first stable release, only the latest commit on `main` receives
security fixes. This section will be updated when the project publishes tagged
releases.
