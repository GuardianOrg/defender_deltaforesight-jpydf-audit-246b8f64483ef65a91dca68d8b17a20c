# Low 01 — AAVE v3 Supply Cap Revert

| Item | Value |
| --- | --- |
| Reported severity | Low |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | Low accepted; recommendation corrected |
| Candidate implementation | [jpydf-v2#1396](https://github.com/deltaforesight/jpydf-v2/pull/1396) (merged as `4535dfed` ahead of audit approval) |

One Strategy deposit revert did roll back the full allocation. The report's
proposed catch-and-strand behavior would have left untracked Underlying in the
rejected Strategy, so PR jpydf-v2#1396 instead isolates the upstream deposit,
proves exact same-transaction recovery to the Vault, fails closed when recovery
is not exact, and continues to later healthy Strategies. It merged after full
local/mainnet Foundry, deployment-wiring, frontend, bot, storage-layout, size,
selector, and fault-injection review.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved as merged ahead of audit approval |
| Approved diff | jpydf-v2 `fe1c80f8..4535dfed` ([#1396](https://github.com/deltaforesight/jpydf-v2/pull/1396)) |
| Diff SHA-256 | `f7bc98e02e57093ba3847ad51c331280b743fb521bf5ed57b5aa48023a86ca63` |
| Diff size | 25 files changed, 627 insertions(+), 118 deletions(-) |
| Test evidence | Merge-time regression battery recorded in the proposed-disposition prose. |

Basis: the merge-time evidence cycle recorded in the proposed-disposition
prose. The merged diff is adopted as the approved diff; the sync step
verifies the merge commit remains reachable from jpydf-v2 `develop`.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#53](https://github.com/deltaforesight/jpydf-audit/pull/53): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/low-01.patch`](../patches/low-01.patch).

Deferred doc-mirror hunks (mirror drift; see the preserved patch): `documents/en .../strategies/AaveV3Strategy.md`; `documents/en .../strategies/ERC4626Strategy.md`; `documents/en .../strategies/LidoStrategy.md`; `documents/jp .../Strategy-Incident-Liquidation-Safety-Runbook.md`; `documents/jp .../strategies/ERC4626Strategy.md`.

## Fix-quality review (2026-08-05)

Verdict: **approve with nits**. Isolation is a self-call try/catch frame
(atomic rollback of upstream effects); recovery requires exact balance deltas
on both sides or the whole allocate reverts (`DepositRecoveryFailed`) — no
stranding path through BaseStrategy. Accounting cannot inflate (conservative
`min(est, principal)`), reentrancy surface is guarded, and the full scenario
battery (mid-list rejection with later strategies funded, fee-on-transfer,
false-return token, Aave supply cap) passes at the merge commit. Follow-up
(defense in depth, not a bug): the exactness invariant is Strategy-enforced;
a one-line Vault-side balance recheck on the skip path would make it
registry-proof against future non-BaseStrategy implementations.
