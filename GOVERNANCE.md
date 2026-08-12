# Governance

This document describes how VektralForge is governed: who makes decisions, how
people gain and lose responsibility, and what happens if the project's current
sponsor or maintainers step away.

VektralForge is sponsored by ALEPH SERVER LTDA. but is **not owned or controlled
by it**. The sponsor funds work and contributes maintainers; it does not hold a
veto, a casting vote, or any reserved seat on the Technical Steering Committee.
See [SPONSORS.md](SPONSORS.md) and [TRADEMARK.md](TRADEMARK.md) for the exact
boundaries of that relationship.

## 1. Roles

### 1.1 Contributor

Anyone who submits an issue, a pull request, documentation, a translation, a
bug report or a review. No formal approval is required. Contributors retain the
copyright in their own contributions; see [CONTRIBUTING.md](CONTRIBUTING.md) for
the Developer Certificate of Origin process.

### 1.2 Maintainer

A contributor with commit rights on one or more repositories, listed in
[MAINTAINERS.md](MAINTAINERS.md) and belonging to the `@vektralforge/maintainers`
team.

**Becoming a maintainer.** Any maintainer may nominate a contributor by opening
an issue in the main repository. Nomination requires a track record of sustained,
high-quality contribution — as a guideline, several months of activity, not a
single large pull request. The TSC approves by simple majority. There is no
requirement to be employed by any particular company, and no company may
nominate on behalf of an individual.

**Responsibilities.** Review and merge pull requests, triage issues, uphold the
[Code of Conduct](CODE_OF_CONDUCT.md), and decline to merge their own changes
without an independent review.

**Stepping down.** A maintainer may step down at any time by opening a pull
request against `MAINTAINERS.md`. A maintainer with no activity for twelve
consecutive months moves automatically to *emeritus* status; emeritus
maintainers keep the recognition, lose commit rights, and may be reinstated by
simple TSC majority without a new nomination process.

**Removal.** A maintainer may be removed for sustained inactivity, repeated
Code of Conduct violations, or actions that damage the project, by a two-thirds
majority of the TSC excluding the person concerned.

### 1.3 Technical Steering Committee (TSC)

The TSC is the project's final decision-making body. It consists of **three to
seven members**, listed in [MAINTAINERS.md](MAINTAINERS.md) and belonging to the
`@vektralforge/tsc` team.

**Scope.** Technical architecture and roadmap; licence and copyright policy;
admission and removal of maintainers; release policy; changes to this document;
custody of project assets; and any decision the maintainers escalate.

**Composition rule.** **No more than 50% of TSC members may share the same
employer or be affiliated with the same organisation.** This rule is the
structural guarantee of the project's independence. Every TSC member must
declare their affiliation in `MAINTAINERS.md` and must report any change of
affiliation within thirty days.

If a change of employment causes the rule to be breached, the TSC has ninety
days to restore compliance — normally by expanding the committee rather than by
removing anyone. During that period the TSC may not decide on licensing,
trademark, or asset custody matters.

**Terms.** TSC members serve until they resign, become inactive for twelve
months, or are removed. There are no fixed terms; the composition rule and the
inactivity rule together prevent capture.

## 2. Decision making

The project defaults to **lazy consensus**: a proposal that receives no
objection within a reasonable period (normally seventy-two hours for routine
matters, one week for substantial ones) is considered accepted.

When consensus is not reached, the TSC votes.

| Decision | Threshold |
| --- | --- |
| Merging an ordinary pull request | One maintainer approval, author excluded |
| Adding a maintainer | Simple majority of the TSC |
| Removing a maintainer | Two-thirds of the TSC, person excluded |
| Adding or removing a TSC member | Two-thirds of the TSC |
| Amending this document | Two-thirds of the TSC, public pull request, minimum fourteen days open |
| Changing the licence | See §3 — effectively unavailable |
| Transferring the project to a foundation | Two-thirds of the TSC, public pull request, minimum thirty days open |

Votes are held in public — in a GitHub issue or pull request — unless they
concern an individual's conduct or an unpublished security matter. Results and
tallies are recorded publicly in all cases.

Quorum is a simple majority of TSC members. A member may abstain; abstentions
count towards quorum but not towards the threshold.

## 3. Licence and relicensing

VektralForge is licensed under **Apache License 2.0**. Contributions are
accepted under the **Developer Certificate of Origin**, not a Contributor
Licence Agreement, and **no copyright is assigned to any party**. Copyright is
held collectively by the individual contributors, referred to in file headers as
*The VektralForge Authors*.

The practical consequence is deliberate: because no single entity holds the
copyright in the codebase, **relicensing the project to a proprietary or
source-available licence would require the consent of every contributor**. This
is the mechanism that makes the commitment in
[OPEN_SOURCE_PROMISE.md](OPEN_SOURCE_PROMISE.md) enforceable rather than merely
declaratory.

Apache 2.0 is irrevocable for everything already published. Any release made
under it remains free and forkable regardless of what happens to the project,
the sponsor, or this governance document.

## 4. Project assets

The TSC holds custody of the project's assets. The current holder of each asset,
and the location of recovery credentials, is recorded in a private asset
inventory maintained by the TSC and reviewed at least annually.

Assets include, at minimum:

- The `vektralforge.org` domain and its DNS configuration
- The `vektralforge` GitHub organisation and its Owner accounts
- Package registry accounts: PyPI, Docker Hub, npm, Maven Central, Helm
- Release signing keys
- Project email accounts and aliases
- The VektralForge trademark (see [TRADEMARK.md](TRADEMARK.md))

**No asset may have a single custodian.** Every asset must be recoverable by at
least two TSC members acting independently. Recovery credentials are stored
offline and are never shared through the project's own communication channels.

## 5. Succession and continuity

This section exists so that the project survives the departure of any individual
or of the sponsor.

**If the sponsor withdraws.** ALEPH SERVER LTDA. may end its sponsorship at any
time. Doing so removes funding and the sponsor's contributed maintainers; it does
not transfer, suspend, or terminate anything else. The trademark licence granted
in `TRADEMARK.md` survives withdrawal, and the sponsor undertakes to transfer the
mark to the TSC or to a successor foundation on request.

**If a TSC member becomes unreachable.** After ninety days without response, the
remaining members may declare the seat vacant by simple majority and appoint a
replacement, subject to the composition rule in §1.3.

**If the TSC falls below three members.** The remaining members must appoint
enough maintainers to restore the minimum within ninety days. If no TSC member
remains, any three maintainers listed in `MAINTAINERS.md` may jointly reconstitute
the TSC by public announcement in the main repository, with a thirty-day objection
period.

**If no maintainer remains.** The project is dormant, not dead. The code remains
under Apache 2.0 and any fork is legitimate. Contributors are encouraged to
continue the work under a new name, since the trademark does not transfer
automatically.

**Migration to a foundation.** The TSC may transfer stewardship of the project to
a neutral foundation — for example the Linux Foundation / LF AI & Data, the
Apache Software Foundation, or the Commons Conservancy — under the threshold in
§2. Such a transfer must include the trademark, the domain, and the asset
inventory, and may not be used to change the licence to anything less permissive
than Apache 2.0.

## 6. Code of Conduct

All participants are bound by the [Code of Conduct](CODE_OF_CONDUCT.md).
Enforcement is the responsibility of the TSC, which may delegate to a subset of
its members where a conflict of interest exists. Reports go to
`conduct@vektralforge.org`.

## 7. Amending this document

Changes are made by public pull request, must remain open for at least fourteen
days, and require a two-thirds majority of the TSC. The rationale for each change
is recorded in the pull request, which serves as the document's history.

---

*Questions about this document: `opensource@vektralforge.org`*
