# Mid 01 — AAVE Pool Address Staleness

| Item | Value |
| --- | --- |
| Reported severity | Medium |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | Medium code finding rejected; operational migration risk accepted |
| Candidate implementation | [jpydf-v2#1383](https://github.com/deltaforesight/jpydf-v2/pull/1383) (merged ahead of audit approval) |

Aave's normal `setPoolImpl` retains the Pool proxy, while Core/Lido/EtherFi are
separate markets with separate Pool/aToken positions. Dynamic provider
following, as the report recommended, would misconnect the old aToken position.
PR jpydf-v2#1383 kept the immutable Strategy boundary, added a fail-closed
provider→Pool mainnet preflight, and documented old-Strategy recovery and
new-Strategy activation after full side-effect review.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved as merged ahead of audit approval |
| Approved diff | jpydf-v2 `af194a1a..a0a90c71` ([#1383](https://github.com/deltaforesight/jpydf-v2/pull/1383)) |
| Diff SHA-256 | `1923aebc010678e7bf01008f3a15c52c0c3b101716a79dcd22c63bb025b12e8d` |
| Diff size | 5 files changed, 226 insertions(+), 5 deletions(-) |
| Test evidence | Merge-time regression battery recorded in the proposed-disposition prose. |

Basis: the merge-time evidence cycle recorded in the proposed-disposition
prose. The merged diff is adopted as the approved diff; the sync step
verifies the merge commit remains reachable from jpydf-v2 `develop`.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#50](https://github.com/deltaforesight/jpydf-audit/pull/50): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/mid-01.patch`](../patches/mid-01.patch).

Deferred doc-mirror hunks (mirror drift; see the preserved patch): `documents/jp .../Mainnet-Deploy-Env-Freeze-Runbook.md`.

Outside snapshot curation scope: `contracts/utils/mainnet-preflight.ts`.

## Fix-quality review (2026-08-05)

Verdict: **approve with nits**. Rejection rationale verified in source: pool,
aToken, and scaled balance form a coupled market triple; dynamic
provider-following would price an old-market position with a new market's
index. The mainnet preflight (in the preserved patch; `contracts/utils` is
outside snapshot curation) is fail-closed on provider→Pool mismatch, but it is
a runbook gate, not a code gate, and `--manifest-only` skips it. Recovery path
(emergencyDisableStrategy → emergencyWithdrawFromAave → writeoff → fresh
strategy) is executable with the current surface, capped by old-pool
liquidity. Ongoing Aave-governance watch is a documented duty (AAVE-GOV-003)
with no automated watcher — recorded as a post-merge follow-up.
