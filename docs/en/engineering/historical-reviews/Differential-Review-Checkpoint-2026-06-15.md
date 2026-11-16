# Differential Review Checkpoint - 2026-06-15

Scope: Governance/Timelock handover, InterestRouterForwarder, Day-1 Treasury wiring, Strategy selector, TroveNFT/metadata core immutability policy, LiquidationCandidateGetter zombie handling, the Rust liquidation bot, and the related deploy/frontend/docs diffs.

## Conclusion

No blocking finding remains. Three low-risk operational / verification-accuracy issues were fixed during the review.

## Fixed Findings

### Low: handover/verify trusted only branch 0's interestRouter

- Impact: The current `DeployLiquity2` binds the same `InterestRouterForwarder` across all branches, so there is no actual harm. However, if a manifest became mixed in the future, verify could miss a state where a non-branch-0 router owner had not moved to Timelock management.
- Fix: `PrepareDFGovernanceHandover` and `VerifyDFGovernanceHandover` now explicitly verify that every branch's `interestRouter` matches branch 0.
- Targets: `contracts/script/PrepareDFGovernanceHandover.s.sol`, `contracts/script/VerifyDFGovernanceHandover.s.sol`

### Low: the bot's zombie-candidate log could diverge from the post-re-verification batch reality

- Impact: Even when the LCG returns `lastZombieTroveId`, the candidate may be dropped during the bot's `min_icr_buffer` re-verification. If `last_zombie_candidate=true` is logged in that case, the operational log could read as if it "actually entered the batch."
- Fix: Changed the log value to be computed from whether a `CandidateSource::LastZombie` remains among the `VerifiedCandidate`s.
- Target: `bots/liquidator/src/scanner.rs`

### Low: the bot example config contradicted the local startup procedure

- Impact: The README recommends leaving the state path unset for a stateless local experiment, but the example config specified `/var/lib/...`, so a local `scan-once` could fail due to save-time permissions.
- Fix: Commented out `state.path` in `config.example.toml`, leaving the daemon path as a comment.
- Target: `bots/liquidator/config.example.toml`

## Residual Risks / Operational Gates

- `DF_TREASURY` / `DF_INTEREST_ROUTER_RECIPIENT` / `DF_INTEREST_ROUTER_OWNER` are required env. The deploy fails fast when they are unset. Confirm the Safe via the manifest's `dfYield[].treasury` and `VerifyDFGovernanceHandover`.
- `VerifyDFGovernanceHandover` verifies the Vault / Strategy holder separation for active branches. Starting Vault/Strategy operation on an inert branch is premised on re-verifying treasury / roles / strategy through a separate activation procedure.
- The Rust bot uses the new LCG ABI with `include_last_zombie=true`. To use it against an old deployment, either lower it to `include_last_zombie=false` in config or update the LCG first.
- The frontend still carries BOLD/Liquity wording originating from legacy / disabled surfaces. This review focuses on contract/docs/bot/deploy consistency; fully DF-ifying all UI wording is handled in a separate pass.

## Verification

- `cargo fmt --manifest-path bots/liquidator/Cargo.toml`
- `cargo test --manifest-path bots/liquidator/Cargo.toml` (14 passed)
- `forge test --match-path test/InterestRouterForwarder.t.sol` (9 passed)
- `forge test --match-contract LiquidationCandidateGetterTest` (3 passed)
- `forge test --match-path test/troveNFT.t.sol` (5 passed)
- `forge test --match-path test/LocalParityDrill.t.sol` (1 skipped: `DF_PARITY_DRILL` unset)
- `forge build` (succeeds; existing lint notes/warnings present)
- `pnpm -C frontend/app test -- --run src/constants.test.ts src/liquity-math.test.ts` (10 passed)
- `git diff --check`
