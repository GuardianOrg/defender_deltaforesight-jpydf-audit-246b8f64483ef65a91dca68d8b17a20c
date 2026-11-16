# Audit Handoff Review Followups

Status date: 2026-07-01

This file records review findings that are not fully resolved by the handoff
repository alone because they either require deployment execution evidence or a
source-repository change.

## Source-Repository Followups

1. `contracts/slither.config.json` in `jpydf-v2` is a development triage config.
   It filters first-party helper paths such as `src/Dependencies` and disables
   several noisy detectors. Audit preparation should use
   `config/slither-audit.config.json` from this handoff repository until a
   source-repository audit config is added. The audit config has been run once,
   and initial detector-level triage is recorded in
   `evidence/slither-triage.md`.

2. The GitHub Actions command `forge test -vv --match-contract Mainnet` should
   not be treated as audit evidence unless concrete `*Mainnet*` fork test
   contracts exist. Mainnet-state verification for this handoff is the
   `mainnet-fork-evidence` / stress evidence flow described in
   `BUILD_AND_TEST.md` and the copied mainnet fork runbooks.

3. The copied Incident Notification Policy now matches the source freeze for the
   external-risk-monitor freshness row. That source row currently shares
   `ALRT-STGY-004` with the external venue incident row. If alert IDs must be
   globally unique in tooling, fix the ID in `jpydf-v2` first and then refresh
   this package.


Resolved in the source repository before this handoff and included in the
current freeze commit:

- `ITroveManager` now uses `_redeemedAmount` for the selector-neutral redemption
  return name.
- `CollateralVault.md` JP/EN specs now include `allocate()` in `VAULT-SEC-001`,
  and `CollateralVaultStrategyTest` covers allocation read-only reentry plus
  mutating reentry rejection.

## Deployment Execution Evidence Followups

The following fields are intentionally not final in this handoff package:

- production `deployment-manifest.json` sha256
- final `FORK_BLOCK`
- mainnet fork evidence output
- Safe signer hash, threshold, and role readback evidence

These must be attached before mainnet delivery. They are not blockers for
source-review handoff unless the audit SOW explicitly includes production
deployment execution.
