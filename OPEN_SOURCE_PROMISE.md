# The VektralForge Open Source Promise

Over the past decade, several widely-used open source projects were relicensed to
source-available or proprietary terms after their communities had already built
on them. Elastic, HashiCorp, Redis, MongoDB and others each moved from a
permissive licence to something more restrictive, and in every case the people
who had adopted the software in good faith absorbed the cost.

The pattern shared one enabling condition: **a single company owned the copyright
in the entire codebase**, usually because contributors had signed a Contributor
Licence Agreement assigning their rights to it. Owning all of the copyright is
what makes unilateral relicensing possible.

VektralForge is built so that this cannot happen here.

## What we commit to

**VektralForge will remain licensed under Apache License 2.0.**

We will not relicense the project under BSL, SSPL, Elastic License, Commons
Clause, or any other licence not approved by the Open Source Initiative.

We will not add usage restrictions, field-of-use limitations, or clauses
restricting who may offer the software as a service.

We will not move features into a proprietary edition, and we will not introduce
an "open core" split where the freely licensed version is deliberately crippled.

We will not require a Contributor Licence Agreement.

## Why you can rely on this beyond our word

A promise is worth what enforces it. Three mechanisms make this one structural:

**Copyright is distributed.** Contributions arrive under the
[Developer Certificate of Origin](CONTRIBUTING.md), not a CLA. Every contributor
retains copyright in their own work. Nobody — not the TSC, not the sponsor —
owns the codebase outright, so nobody can relicense it unilaterally. Doing so
would require the consent of every contributor, which becomes practically
impossible as the project grows. That impossibility is the point.

**Apache 2.0 is irrevocable for what is already published.** Every release made
under it stays free permanently. Even in the worst case — the organisation
disappears, the maintainers vanish, someone attempts to close the project — the
existing code remains free and forkable by anyone, forever.

**Governance is distributed.** No more than 50% of the Technical Steering
Committee may share an employer, and licence changes require a two-thirds
majority through a public pull request open for at least fourteen days. See
[GOVERNANCE.md](GOVERNANCE.md).

## The sponsor's position

VektralForge is sponsored by **ALEPH SERVER LTDA.**, which funds development and
contributes maintainers. The sponsor holds no veto, no casting vote and no
reserved seat on the TSC. It holds the trademark, and has committed in
[TRADEMARK.md](TRADEMARK.md) to transfer it to the TSC or a neutral foundation on
request.

If ALEPH SERVER LTDA. ends its sponsorship, the project continues. If ALEPH
SERVER LTDA. ceases to exist, the project continues. The succession clauses in
`GOVERNANCE.md` §5 exist precisely for those scenarios.

## Forking

If we ever break this promise, **fork the project**. We consider that a
legitimate and appropriate response, not a hostile act. Apache 2.0 guarantees
your right to do it, and [TRADEMARK.md](TRADEMARK.md) explains the one condition:
choose a different name, so users can tell the two apart.

We would rather state this plainly than have you discover it in a licence change
announcement.

---

*This document may be amended only under `GOVERNANCE.md` §7 — two-thirds of the
TSC, by public pull request, open for at least fourteen days. Its history is the
history of that pull request.*
