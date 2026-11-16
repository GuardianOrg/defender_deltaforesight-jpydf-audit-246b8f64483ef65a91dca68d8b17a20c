# Mid 02 — `PriceFeedProxy::confirmSource` Skips 1% Price Deviation Guard When Old Source Is Unhealthy

| Item | Value |
| --- | --- |
| Reported severity | Medium |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | Medium accepted with claim correction |
| Candidate implementation | [jpydf-v2#1384](https://github.com/deltaforesight/jpydf-v2/pull/1384) (merged ahead of audit approval) |

The baseline allowed normal `confirmSource` to accept a 50% jump when the old
source became unhealthy. The trigger remained owner-only and timelocked, but
the normal path silently changed to emergency semantics. PR jpydf-v2#1384 now
compares both price paths against their separate last-good caches, reserves
bypass for explicit `confirmSourceEmergency`, and merged after full side-effect
review and CI.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved as merged ahead of audit approval |
| Approved diff | jpydf-v2 `a0a90c71..e32d7d2c` ([#1384](https://github.com/deltaforesight/jpydf-v2/pull/1384)) |
| Diff SHA-256 | `b88e9e05f8f404fd0fccf03435dc0ed3d068ad76161fa444ab90c410030623b7` |
| Diff size | 9 files changed, 271 insertions(+), 36 deletions(-) |
| Test evidence | Merge-time regression battery recorded in the proposed-disposition prose. |

Basis: the merge-time evidence cycle recorded in the proposed-disposition
prose. The merged diff is adopted as the approved diff; the sync step
verifies the merge commit remains reachable from jpydf-v2 `develop`.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#51](https://github.com/deltaforesight/jpydf-audit/pull/51): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/mid-02.patch`](../patches/mid-02.patch).

Deferred doc-mirror hunks (mirror drift; see the preserved patch): `documents/en .../spec/Oracle.md`; `documents/jp .../spec/Oracle.md`.

## Fix-quality review (2026-08-05)

Verdict: **approve with nits**. The deviation guard is now unskippable on the
normal path (health condition removed); reference falls back to the per-path
last-good caches; `confirmSourceEmergency` is onlyOwner + the same 24h
timelock + the same smoke tests, bypassing only the 1% check, and
`priceGuardBypassed=true` fires only on the explicit emergency path. No
empty-cache state exists (constructor warms both caches). Ops alert
ALRT-ORCL-010 on `priceGuardBypassed=true` confirmed present in the ops alert
catalog. Nit (pre-existing): `_handleFailedFetch` refreshes the normal cache
but not the redemption cache during outages, so redemption-cache drift can
force the emergency path more often than strictly necessary.
