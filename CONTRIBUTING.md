# Contributing to VektralForge

Thanks for considering a contribution. This document covers the legal side (the
DCO), the practical side (how to get a change merged), and the conventions that
keep the project consistent.

Issues, discussions and pull requests are welcome in **English or Spanish**.
Code identifiers, commit messages and documentation in `docs/` are written in
English; Spanish translations live under `docs/es/`.

## Developer Certificate of Origin

VektralForge uses the [Developer Certificate of Origin](https://developercertificate.org/)
(DCO). We deliberately do **not** use a Contributor Licence Agreement.

The difference matters. A CLA typically assigns or licenses your copyright to a
single company, which is what allows that company to relicense the project later
without asking anyone. Under the DCO, **you keep the copyright in your own
contribution** and simply certify that you have the right to submit it. Copyright
in the codebase ends up distributed across all contributors, which is what makes
the commitment in [OPEN_SOURCE_PROMISE.md](OPEN_SOURCE_PROMISE.md) structurally
real rather than a promise we ask you to trust.

Signing off is one flag:

```bash
git commit -s -m "fix(trino): register Delta tables with correct catalog"
```

This appends a line to your commit message:

```
Signed-off-by: Jane Doe <jane@example.com>
```

The name and email must be real and must match your `git config user.name` and
`user.email`. Pseudonyms are not accepted for the sign-off, since the DCO is a
statement about provenance.

To sign off automatically, once per clone:

```bash
git config --local format.signOff true
```

Forgot to sign off? For the last commit:

```bash
git commit --amend -s --no-edit && git push --force-with-lease
```

For several commits, where `N` is how many:

```bash
git rebase --signoff HEAD~N && git push --force-with-lease
```

A CI check enforces this. Pull requests with unsigned commits cannot be merged.

## Before you start

For anything beyond a typo or an obvious bug fix, **open an issue first**. It
saves you from building something the project has already decided against, and it
gives maintainers a chance to point you at prior context.

Issues labelled `good first issue` are scoped deliberately small and are a good
entry point.

## Development setup

The project targets **Python 3.12**. Note the constraint below on Spark, which
runs an older interpreter.

```bash
git clone https://github.com/vektralforge/vektralforge.git
cd vektralforge
make dev-up          # start the stack with Docker Compose
make dev-load-example # verify stack, install JARs, activate DAGs, register tables
```

Install the pre-commit hooks before your first commit:

```bash
pip install pre-commit
pre-commit install
```

The hooks run `ruff`, `ruff-format` and `detect-secrets`, and block direct
commits to `main`. If `detect-secrets` flags a false positive, mark the line:

```python
FAKE_TOKEN = "not-a-real-secret"  # pragma: allowlist secret
```

Never mark a real credential this way. Push protection is enabled on the
repository and will reject the push regardless.

## Coding conventions

**Spark and Python versions.** Python 3.12 everywhere: the project environment,
the Airflow container that hosts the Spark driver, and the Spark image, which
installs 3.12 from deadsnakes for that reason. PySpark refuses to run when driver
and executors differ in minor version, so keep them aligned.

Earlier revisions said executors ran Python 3.8 and asked for tuple syntax in
`isinstance` with a `ruff` exemption. That stopped being true with the migration
to Spark 4; the 3.10+ union form is fine.

**Project name spelling.** The name has exactly one form per context. Please
respect it — mixed spellings are hard to fix once they spread.

| Context | Form |
| --- | --- |
| Prose, wordmark, titles | `VektralForge` |
| Repository, packages, CLI, paths | `vektralforge` |
| Environment variables | `VEKTRALFORGE_` |
| Java/Maven group ID | `org.vektralforge` |

Never `Vektral Forge`, `vektral-forge`, `VEKTRALFORGE`, or any spelling with an
`r` in place of the `k`.

**Commit messages** follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(airflow): add ARClim climate risk DAG
fix(superset): call fetch_metadata after dataset creation
docs(governance): clarify TSC composition rule
```

## Pull requests

1. Fork the repository and branch from `develop`.
2. Keep the change focused. One logical change per pull request.
3. Add or update tests for behaviour changes.
4. Update documentation in the same pull request, not a follow-up.
5. Ensure `pre-commit run --all-files` passes.
6. Sign off every commit.
7. Open the pull request against `develop`, describing what changed and why.

A maintainer other than the author reviews and merges. Maintainers do not merge
their own changes without an independent review. CI must be green, including the
DCO check, `ruff`, tests and CodeQL.

Expect a first response within a week. If a pull request goes quiet for longer,
a polite ping on the thread is welcome and not considered rude.

## Reporting security issues

**Do not open a public issue for a security vulnerability.** Follow the process
in [SECURITY.md](SECURITY.md).

## Code of Conduct

Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md). Reports
go to `conduct@vektralforge.org`.

## Note for organisation members

The `vektralforge` GitHub organisation requires two-factor authentication for
every member and outside collaborator. This does not affect contributions from
forks, which is how most contributions arrive — no membership is needed to open a
pull request.

## Licence

By contributing, you agree that your contribution is licensed under the
[Apache License 2.0](LICENSE), and you certify the DCO above. You retain the
copyright in your work.
