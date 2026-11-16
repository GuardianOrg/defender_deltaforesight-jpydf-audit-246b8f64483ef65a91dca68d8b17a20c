# Low 04 — Independent JPY Freeze Timers Create Cross-Branch Price Divergence

| Item | Value |
| --- | --- |
| Reported severity | Low |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | Low accepted; recommendation corrected |
| Candidate implementation | [jpydf-v2#1404](https://github.com/deltaforesight/jpydf-v2/pull/1404) (merged as `789466ee` ahead of audit approval) |

Feed instances did keep separate JPY state, while the proposed shared
inheritance would still create per-instance storage. PR jpydf-v2#1404 instead
introduced one shared JPY/USD rate provider, injected it into every active
branch, latched expiry globally before branch-local shutdown handling, and
added deployment, frontend, ops, monitoring, runbook, and cross-branch recovery
coverage. It merged after A/B reproduction, 1,445-test Foundry, and the
standard review battery.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved as merged ahead of audit approval |
| Approved diff | jpydf-v2 `409dfdec..789466ee` ([#1404](https://github.com/deltaforesight/jpydf-v2/pull/1404)) |
| Diff SHA-256 | `5edda6d94a3683200bed45f69a570495aa0937a0f02d2fa5ebaa4147ed5448c7` |
| Diff size | 39 files changed, 913 insertions(+), 359 deletions(-) |
| Test evidence | Merge-time regression battery recorded in the proposed-disposition prose. |

Basis: the merge-time evidence cycle recorded in the proposed-disposition
prose. The merged diff is adopted as the approved diff; the sync step
verifies the merge commit remains reachable from jpydf-v2 `develop`.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#56](https://github.com/deltaforesight/jpydf-audit/pull/56): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/low-04.patch`](../patches/low-04.patch).

Deferred doc-mirror hunks (mirror drift; see the preserved patch): `documents/en/Parameters.md`; `documents/en .../jpyusd-staleness-threshold-determination.md`; `documents/en .../Mainnet-Deploy-Env-Freeze-Runbook.md`; `documents/en .../spec/Oracle.md`; `documents/jp .../jpyusd-staleness-threshold-determination.md`; `documents/jp .../spec/Oracle.md`.

Outside snapshot curation scope: `documents/jp .../Parameter-Catalog.md`.

## Fix-quality review (2026-08-05)

Verdict: **approve with nits**. The shared provider is non-upgradeable,
ownerless, and setter-free (trust reduces to the Chainlink JPY/USD feed); the
expiry latch is set before the failure return and short-circuits every later
call, closing the divergence class including proxy-delegated shutdowns
(tested); feeds cannot be constructed without a code-backed provider and the
deploy script injects a single instance into every branch with a preflight
sameness assertion.

Accepted residual risks (owner-confirmed 2026-08-05):
1. A JPY oracle outage longer than 24h shuts down **all** branches
   permanently (designed fail-closed; the alternative was divergence).
2. Recovery from a latched expiry requires a new provider **plus** new feed
   sources for every branch through the 24h-timelocked proxy swap.
3. Single-provider sameness is enforced at deploy/preflight only, not
   on-chain.
Freeze-age monitoring is computed from `jpyFrozenSince` in the ops alert
code (confirmed). Cosmetic: the freeze-conversion helpers are intentionally
duplicated in `sUSDSPriceFeed` and must be kept in lockstep.
