# Governance / PriceFeed / Day-1 Params Differential Review

The scope covers `PrepareDFGovernanceHandover` / `VerifyDFGovernanceHandover`, the `PriceFeedProxy` owner handover, the Day-1 dToken/Vault parameter injection, and the related docs.

## Fix Policy

We treat "correct" as whichever side is healthier for the protocol, and aligned the implementation toward it using the following criteria.

- Do not leave the price oracle source-swap authority on the deployer hot key.
- Do not leave initial default values such as `cap=max` / `allocateMaxMove=max` / `allocatorCooldown=0` in production activation.
- Do not put implicit conversion from USD nominal values to on-chain quantities into the script.
- Remove the default fallback for the Strategy owner/upgrader and fail-fast with explicit env only.
- Remove the default fallback for the deploy-time Strategy selector / weight / cap and fail-fast with explicit env only.
- Do not let the Oracle's dToken backing read failure continue with the last-good backing; route it to shutdown as an oracle failure.

## Fixed

### PriceFeedProxy owner handover

`DeployLiquity2` initializes the `PriceFeedProxy` owner with the deployer, but in the docs the production owner is held directly by the GOV multisig. `PrepareDFGovernanceHandover` starts a 2-step transfer of every branch's `.branches[i].priceFeed` to `DF_PRICE_FEED_OWNER`, and `VerifyDFGovernanceHandover` verifies either the completed state or the pending state when `DF_VERIFY_PENDING_OWNERSHIP=true`.

`DF_PRICE_FEED_OWNER` must not be the same as `DF_TIMELOCK` / `DF_GUARDIAN` / `DF_ALLOCATOR`. This avoids a double delay between the PriceFeedProxy's built-in 24h source timelock and the TimelockController, while retaining the responsiveness to cancel a suspicious proposal promptly.

### Day-1 dToken/Vault parameters

`PrepareDFGovernanceHandover` requires the following env for each active branch, and when the value differs it injects it while the deployer/current admin authority still remains.

- `DF_DTOKEN_CAP_<branchIndex>`
- `DF_ALLOCATE_MAX_MOVE_<branchIndex>`
- `DF_ALLOCATOR_COOLDOWN_<branchIndex>`
- `DF_WITHDRAW_DELAY_<branchIndex>`
- `DF_BUFFER_TARGET_BPS_<branchIndex>`
- `DF_BUFFER_FLOOR_<branchIndex>`

`VerifyDFGovernanceHandover` verifies that the same env matches the on-chain values. For inert branches it verifies `cap == 0`.

`mintCap` / `allocateMaxMove` are managed as USD nominal values in the docs, but the on-chain setter receives quantities that do not reference the price. The script performs no implicit conversion and receives only the quantities finalized in the pre-deploy review as env.

### Strategy owner/upgrader fail-fast

Removed the `envOr(guardian/timelock)` fallback for `DF_STRATEGY_OWNER` / `DF_STRATEGY_UPGRADER` and made them required env. Their values must match `DF_GUARDIAN` / `DF_TIMELOCK` respectively.

### Deploy-time Strategy selector / weight / cap fail-fast

In the DF dToken wiring of `DeployLiquity2`, removed the default of falling back to Aave / 100% / `type(uint256).max` when `DF_STRATEGY_KIND` / `DF_STRATEGY_WEIGHT_BPS` / `DF_STRATEGY_CAP` are unset. A branch-specific env takes precedence if present, and the common env can be used otherwise, but if neither exists the deploy fails fast.

The Strategy kind, weight, and cap are the substantive risk boundary for moving assets from the Vault to external operating destinations, and an implicit Aave fixed setting or an infinite cap weakens the confirmation of intent for production operation. `local-stack.sh` explicitly injects the same values for local parity, so development reproducibility is maintained.

### Oracle backing read failure fail-fast

The `_applyBackingRatio` of `DFPriceFeedBase` / `sUSDSPriceFeed` does not pass a normal read failure of `CollateralVault.backingRatio()` through with `lastGoodBacking`; it routes it to the standard oracle failure path (source-side `lastGoodPrice` shutdown, Proxy-side branch shutdown). A low-gas call re-reverts `InsufficientGasForExternalCall` and does not let a gas-starved call be used to trigger a shutdown.

Reason: `backingRatio()` is the last safety valve that reflects Strategy impairment into the collateral value, and if a stale backing keeps being used here, an overvalued price could continue while a loss is occurring. A Strategy-unit view failure is absorbed by the Vault's bounded cache, while a Vault-wide backing read failure is made fail-fast, prioritizing protocol health.

### Core spec cleanup

Because `CORE-AP-TBD-001` has been resolved, the "undecided" notation that remained in the Core spec summary / glossary / ActivePool state table was updated to the `InterestRouterForwarder`-resolved description.

## Remaining Work

- In the production deployment, finalize the quantities of `DF_DTOKEN_CAP_<i>` / `DF_ALLOCATE_MAX_MOVE_<i>` based on the final prices and collateral decimals.
- In the production deployment, finalize `DF_STRATEGY_KIND(_<i>)` / `DF_STRATEGY_WEIGHT_BPS(_<i>)` / `DF_STRATEGY_CAP(_<i>)` based on the Strategy adopted per branch and the cap review.
- The TimelockController's own minDelay / proposer / executor / canceller / admin renounce remain external assumptions, so a separate verify script or runbook evidence is needed.
- Treasury / SPRewardDistributor remain unimplemented as Day-2.

## Verification

- `forge build` passed (a large number of existing lint notes appear, but the compile succeeds).
