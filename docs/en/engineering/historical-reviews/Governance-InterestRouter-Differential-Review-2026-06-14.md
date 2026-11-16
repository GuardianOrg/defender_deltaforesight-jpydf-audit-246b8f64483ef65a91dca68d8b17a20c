# Governance / InterestRouter Differential Review (2026-06-14)

The scope covers the Governance/Timelock handover, `InterestRouterForwarder`, the interestRouter wiring in `DeployLiquity2`, the local parity drill, and the related docs.

## Findings

### Fixed: `InterestRouterForwarder` owner was missing from handover/verify

`InterestRouterForwarder` has an owner that can change `recipient`, so it must be included in the same Day-1 activation scope as the docs' "Timelock-managed" set. In the initial implementation, `PrepareDFGovernanceHandover` / `VerifyDFGovernanceHandover` handled only `DToken` / `Vault` / `Strategy`, and the Forwarder owner alone was left out of the verification scope.

Actions:

- Updated to the 2026-06-15 fail-fast policy: `DeployLiquity2` treats `DF_INTEREST_ROUTER_RECIPIENT` / `DF_INTEREST_ROUTER_OWNER` as required env, and halts the deploy if they are unset. The local-stack explicitly injects local values.
- Added the start of the Forwarder owner 2-step transfer of `.branches[0].interestRouter` to `PrepareDFGovernanceHandover`.
- Added verification of the Forwarder owner / pendingOwner to `VerifyDFGovernanceHandover`.
- Added the `InterestRouterForwarder owner -> Timelock` Timelock accept ceremony to the local parity drill.
- Updated the owner initial values and activation procedure in the Core spec and the Governance-Roles doc.

### Fixed: insufficient tests for Forwarder owner boundary conditions

`transferOwnership(address(0))` is permitted as a pending owner cancel, but there was no explicit test for it. In addition, the failure cases of constructor zero arguments and a non-pending accept were unverified.

Actions:

- Added tests for zero constructor args, pending owner cancel, and non-pending accept to `contracts/test/InterestRouterForwarder.t.sol`.
- Documented the meaning of `transferOwnership(address(0))` in the NatSpec.

## Residual Risks / Operational Assumptions

- Because `CollateralVault` is not `AccessControlEnumerable`, `VerifyDFGovernanceHandover` cannot fully enumerate unknown extra role holders. As stated in the docs, this is supplemented by the prepare procedure and multisig review.
- `LocalParityDrill` assumes a `DF_PARITY_DRILL=true` live non-mainnet deployment. A normal `forge test --match-path test/LocalParityDrill.t.sol` only performs the skip gate and a compile check.
- For production activation, after prepare, the Timelock must execute `acceptOwnership` for `DToken` / `InterestRouterForwarder` and the Guardian must execute `acceptOwnership` for the Strategy, after which `VerifyDFGovernanceHandover` must pass in the completed state.

## Verification

- `forge test --match-path test/InterestRouterForwarder.t.sol` (9 passed)
- `forge test --match-path test/LocalParityDrill.t.sol` (1 skipped because `DF_PARITY_DRILL` is unset)
- `forge build` (succeeded; existing Foundry lint notes / mutability warnings remain)
- `git diff --check` (succeeded)
