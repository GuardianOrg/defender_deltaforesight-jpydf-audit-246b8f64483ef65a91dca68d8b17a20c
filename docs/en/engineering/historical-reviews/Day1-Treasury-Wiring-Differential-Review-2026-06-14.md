# Day-1 Vault Treasury Wiring Differential Review (2026-06-14)

Scope: the Day-1 Vault `treasury` wiring, the `DeployLiquity2` env/manifest/verify, and the Treasury / CollateralVault / Governance docs.

## Findings

### Fixed: the deploy initial treasury was hardcoded to `deployer` despite the Day-1 Safe-retention policy

Treasury / SPRewardDistributor are not implemented on Day-1, and the docs specify setting each Vault's `treasury` to the Foundation/GOV Safe to accumulate deployment yield. The deploy script, however, hardcoded `CollateralVault.initialize(..., deployer, deployer)`, so if `transferYieldToTreasury` or a Strategy reward sweep ran before handover, the deployer could become the recipient.

Resolution:

- Updated to a fail-fast policy on 2026-06-15: `DeployLiquity2` uses the required env `DF_TREASURY` for the Vault treasury and halts the deploy if it is unset. The `DF_VAULT_TREASURY` / deployer fallback was removed.
- Added `vault.treasury() == _dfVaultTreasury()` to deploy-time verify.
- The deployment manifest now outputs `treasury` under `dfYield[]`.
- Documented the Day-1 deploy env, the `DF_TREASURY` cross-check in handover/verify, and the fail-fast on unset in the Treasury / CollateralVault / Governance docs.

## Residual Risks / Operational Assumptions

- The `Treasury.sol` / `SPRewardDistributor` bodies remain unimplemented until Day-2. Day-1 only accumulates into the Safe; no additional SP distribution or buyback occurs.
- When `DF_TREASURY` is unset the deploy fails fast. The production runbook confirms the Safe via the manifest's `dfYield[].treasury` and `VerifyDFGovernanceHandover`.
- Because `CollateralVault` allows later changes via `setTreasury`, the Day-2 Treasury introduction switches from Safe to Treasury through the Timelock.

## Verification

- `forge test --match-path test/LocalParityDrill.t.sol` (1 skipped because `DF_PARITY_DRILL` is unset)
- `forge build` (succeeds; existing Foundry lint notes / mutability warnings remain)
- `git diff --check` (passes)
