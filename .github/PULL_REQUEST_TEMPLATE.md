## What this changes, and why

<!--
The "why" matters more than the "what": the diff already shows what changed.
If it closes an issue, write `Closes #N`.
-->

## How it was verified

<!--
This is the section the maintainers read first.

A green CI is not enough on its own, and the reason is written down: **the CI
does not build images and does not start containers.** A pull request can be
green and still leave the metastore dead or a container in a restart loop —
that has happened more than once in this repository.

So: what did you run, and what did you observe? If the change touches the
stack, `make dev-reset && make dev-load-example` and the row counts it produced
are the strongest evidence there is.

Two habits worth borrowing, both learned the hard way here:

  * A check that can only come out green proves nothing. If your verification
    is a set of "X no longer appears" checks, add one that asserts something
    *is* there — otherwise a broken check and a passing system look identical.
  * "It returned 0" is not the same as "it worked". A user created without an
    error may still have the wrong password.
-->

## Checklist

- [ ] Every commit is signed off (`git commit -s`) — the DCO check enforces it
- [ ] `make lint-all` and `make test-all` pass locally
- [ ] Documentation updated if the behaviour or the interface changed
- [ ] No credentials in the diff, the commit messages or the pasted output
