# Mid 03 — JPY Freeze Clock Starts At First Call, Not Oracle Failure

| Item | Value |
| --- | --- |
| Reported severity | Medium |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | Medium accepted with claim correction |
| Candidate implementation | [jpydf-v2#1385](https://github.com/deltaforesight/jpydf-v2/pull/1385) (merged ahead of audit approval) |

Both JPY freeze implementations restarted the 24-hour window on the first
post-dormancy failure. Zero traffic did not itself consume a stale price, but
returning activity could use an already-expired cached FX rate. PR
jpydf-v2#1385 now stores the timestamp paired with `lastGoodJpyRate`, anchors
the freeze to the earlier of observation and the cached rate's stale boundary,
and merged after direct/Proxy regressions, full side-effect review, CI, and a
newly surfaced dependency-advisory unblock.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved as merged ahead of audit approval |
| Approved diff | jpydf-v2 `e32d7d2c..fe1c80f8` ([#1385](https://github.com/deltaforesight/jpydf-v2/pull/1385)) |
| Diff SHA-256 | `e90e571c3c733bb5207d3a163aa1074b1bb46110d5f503213b2347c16edefb17` |
| Diff size | 18 files changed, 389 insertions(+), 65 deletions(-) |
| Test evidence | Merge-time regression battery recorded in the proposed-disposition prose. |

Basis: the merge-time evidence cycle recorded in the proposed-disposition
prose. The merged diff is adopted as the approved diff; the sync step
verifies the merge commit remains reachable from jpydf-v2 `develop`.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#52](https://github.com/deltaforesight/jpydf-audit/pull/52): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/mid-03.patch`](../patches/mid-03.patch).

Deferred doc-mirror hunks (mirror drift; see the preserved patch): `documents/en .../spec/Oracle.md`; `documents/jp .../jpyusd-staleness-threshold-determination.md`; `documents/jp .../spec/Oracle.md`.

## Fix-quality review (2026-08-05)

Verdict: **approve with nits**. The freeze anchor is
`min(observation, lastGoodJpyUpdatedAt + stalenessThreshold)` and the expiry
check runs in the same call that sets the anchor, so a returning caller after
dormancy past threshold+24h gets shutdown on the very first call — the
finding's replay is impossible, not merely bounded. Underflow/clock-skew safe;
constructor seeds a validated-fresh cache. The per-branch hunks were later
superseded by Low 04's shared `JpyUsdRateProvider`, which preserves and
latches the same anchor semantics (recorded in the audit ledger). Ops alert
age is computed from `jpyFrozenSince` (confirmed in the ops alert code).

Owner ratification (2026-08-05): the `socket.io-parser` 4.2.6→4.2.7 bump
inside this approved diff was a CI dependency-advisory unblock that rode along
with the fix; ratified as part of the approved hash.
