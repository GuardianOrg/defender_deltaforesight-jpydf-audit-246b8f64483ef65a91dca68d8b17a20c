# Low 05 — `InterestRouterForwarder::setRecipient` Missing `requireValidRecipient`

| Item | Value |
| --- | --- |
| Reported severity | Low |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | Low accepted; impact corrected |
| Candidate implementation | [jpydf-v2#1405](https://github.com/deltaforesight/jpydf-v2/pull/1405) (merged as `1adab166` ahead of audit approval) |

A nonzero Core protocol recipient could be stored and make `route()` revert,
but governance could restore a valid recipient, so the report's "permanently
bricked" claim was incorrect. PR jpydf-v2#1405 now reuses
`JpydfToken.requireValidRecipient` in the constructor and setter, preserves the
prior live route on rejection, and repeats validation after Core wiring and
during all handover phases. It merged after production-token coverage for every
forbidden class, 1,449-test full Foundry, and the standard review battery.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved as merged ahead of audit approval |
| Approved diff | jpydf-v2 `789466ee..1adab166` ([#1405](https://github.com/deltaforesight/jpydf-v2/pull/1405)) |
| Diff SHA-256 | `bf7bbc3a6474bef9caba6c0785badbe0941cdefd3b276f36c9b1e999dc079dc1` |
| Diff size | 10 files changed, 306 insertions(+), 49 deletions(-) |
| Test evidence | Merge-time regression battery recorded in the proposed-disposition prose. |

Basis: the merge-time evidence cycle recorded in the proposed-disposition
prose. The merged diff is adopted as the approved diff; the sync step
verifies the merge commit remains reachable from jpydf-v2 `develop`.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#57](https://github.com/deltaforesight/jpydf-audit/pull/57): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/low-05.patch`](../patches/low-05.patch).

Deferred doc-mirror hunks (mirror drift; see the preserved patch): `documents/en .../spec/InterestRouter.md`; `documents/jp .../spec/InterestRouter.md`.

## Fix-quality review (2026-08-05)

Verdict: **approve with nits**. Constructor and setter both validate via the
production token's `requireValidRecipient`; the checked set equals `route()`'s
revert set exactly (plain OZ ERC20, no receive hooks), and the registry is
frozen after wiring so a validated recipient cannot later become invalid.
Rejection is atomic and the prior route stays live (tested). The deferred
validation points in deploy and all three handover phases abort on failure
(revert propagates outside the try block). Every forbidden class is tested
against the production token.
