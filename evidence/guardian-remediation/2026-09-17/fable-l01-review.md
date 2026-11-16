**Verdict: Approve for head 3e9a625.** The patch closes the L-01 finalization DoS with no blocking regressions. Findings below are informational or optional polish.

**How the fix closes the finding**

- `DToken.setCap` at `source-snapshot/contracts/src/DToken.sol:368` refuses any nonzero cap unless a bound registry reports finalized risk parameters. `setCap(0)` stays unconditional, so the owner can always fail closed.
- `DToken.mint` at line 304 re-checks finalization on every issuance, so even a stale nonzero cap cannot create supply on a reserved branch. Since `CollateralVault.deposit` (line 269) is the only mint caller and `backstopDeposit` does not mint, there is no bypass path. The whole deposit reverts, so the depositor's underlying is never stranded in the vault.
- The circular constraint is sound: `finalizeRiskParams` requires cap and supply zero, and cap can only leave zero after `riskParamsFinalized` is true. `finalizeRiskParams` reverts with `RiskParamsAlreadyFinalized` before ever reaching the cap check, so the sequence finalize-then-open cannot deadlock.
- Binding is one-shot, owner-only, requires code, cap 0, supply 0, and `collToken()` equal to the token. `AddressesRegistry.setAddresses` renounces ownership after writing `collToken`, so the registry side cannot be repointed after binding.

**Deployment wiring is correct**

- `_deployYieldLayer` accepts ownership at `DeployLiquity2.s.sol:1364` before the branch loop, so the deployer is owner when `setRiskParamsRegistry` runs at line 905, right after `setAddresses` at line 902. Reserved branches bind with cap 0 and no token info, which the binding permits.
- Active branch registries pass a zero finalizer and are finalized in the constructor, so later cap opening by handover or the pilot controller works. Reserved branches keep cap 0 until the timelock finalizes.
- `_verifyDFWiring` at line 1990 reads the binding back for all eight branches. Handover, verify, seed, and pilot scripts only call `setCap(0)` on unfinalized tokens.

**Non-blocking findings**

- **Informational, `DToken.sol:379`.** A live token with supply can never bind after an implementation upgrade, and minting stays reverted until a further upgrade. The docs state this. Note also that the pilot controller's dToken interface has no bind function, so it must never receive ownership of an unbound token. In the fresh flow, binding precedes handover, so this holds.
- **Informational, `AddressesRegistry.sol:279`.** The `DTokenCapNotZero` guard is now unreachable through the honest path and serves only as defense in depth. Keep it.
- **Informational, `DeployLiquity2.s.sol:127`.** `setCap(0)` in the helper is now redundant since `initialize` no longer sets an unlimited cap. Harmless; keeping it makes fail-closed explicit.
- **Low, tests, `test/mocks/MockDTokenRegistry.sol:16`.** The mock allows un-finalizing, which the real registry cannot do. The unit test that uses this is explicit about it. The real lifecycle is covered by `GuardianL01Finalization.t.sol` with a real registry and fuzzing, so tests are not masking a defect.
- **Polish, `docs/en/protocol/product/spec/dToken.md:31`.** The new setter shares the FR-006 identifier with `setCap`. A dedicated requirement id would make traceability cleaner.

**Checked and clean:** storage layout (new field appended before the gap, gap reduced by one), authorization (owner binds, vault mints, unchanged), reentrancy (view call to a trusted non-upgradeable registry; the pre-write external call in the setter is owner-gated), and error precedence in both `mint` and the setter, which the unit tests pin.

No additional correctness scope is needed. The items above are optional polish.