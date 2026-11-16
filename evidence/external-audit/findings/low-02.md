# Low 02 — Allocate Mis-Sizes Buffer Target When Strategy View Is Unavailable

| Item | Value |
| --- | --- |
| Reported severity | Low |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | Low accepted; recommendation corrected |
| Candidate implementation | [jpydf-v2#1397](https://github.com/deltaforesight/jpydf-v2/pull/1397) (merged as `5124599e` ahead of audit approval) |

The partial live-or-zero sum did understate the buffer target and moved 40 from
the exact reported 100/800/200 example. The report's cache fallback claim was
unsafe because a pre-loss cache can exceed current recoverable value. PR
jpydf-v2#1397 instead requires a full live preflight, stops allocation and
Treasury outbound movement on any unavailable registered Strategy, preserves
solvency-only cache behavior, and automatically resumes after recovery without
consuming cooldown. It merged after A/B reproduction, allocation/Treasury
recovery tests, and the full local/mainnet review battery.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved as merged ahead of audit approval |
| Approved diff | jpydf-v2 `3c2ee613..5124599e` ([#1397](https://github.com/deltaforesight/jpydf-v2/pull/1397)) |
| Diff SHA-256 | `bf1fa737d9de12aadbb36d770faa0d9678d3899d44add803d0ccd641c7648831` |
| Diff size | 9 files changed, 285 insertions(+), 68 deletions(-) |
| Test evidence | Merge-time regression battery recorded in the proposed-disposition prose. |

Basis: the merge-time evidence cycle recorded in the proposed-disposition
prose. The merged diff is adopted as the approved diff; the sync step
verifies the merge commit remains reachable from jpydf-v2 `develop`.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#54](https://github.com/deltaforesight/jpydf-audit/pull/54): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/low-02.patch`](../patches/low-02.patch).

Deferred doc-mirror hunks (mirror drift; see the preserved patch): `documents/en .../spec/CollateralVault.md`; `documents/jp .../Strategy-Incident-Liquidation-Safety-Runbook.md`.

## Fix-quality review (2026-08-05)

Verdict: **approve with nits**. `_managedUnderlying` preflights every
registered strategy (including disabled/zero-weight, proven by test) and
gates exactly `allocate` and `transferYieldToTreasury`; solvency views keep
their non-reverting cache fallback; the blocked attempt does not consume the
allocator cooldown. The report's exact 100/800/200 example is pinned.

Escape-hatch investigation (owner question, resolved): a permanently bricked
strategy blocks allocate/Treasury indefinitely and cannot be removed
(`removeStrategy` needs live views). The exit is the strategy's UUPS upgrade:
`_authorizeUpgrade` requires the dedicated `upgrader`, which the governance
handover sets to the Timelock (`VerifyDFGovernanceHandover` requires
`strategyUpgrader == timelock`), and `upgradeTo` does not depend on the
bricked implementation's views. So the hatch is real, with timelock latency
as the accepted cost while outbound movement stays blocked. Follow-ups
recorded in the audit ledger: an end-to-end rehearsal test
(brick → timelocked upgrade → writeoff → remove), a runbook entry naming the
sequence, and optionally a dedicated `AllocationBlocked` event (currently the
blocked no-op is observable only via the runbook's missing-`Allocated` alert).
