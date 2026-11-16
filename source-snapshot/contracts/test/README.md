# Contract Test Map

This index helps agents and auditors choose focused tests before running broad
Foundry suites.

## Test Families

| Family | Files | Covers |
| --- | --- | --- |
| Core borrow/Trove/SP behavior | `borrowerOperations.t.sol`, `troveManager.t.sol`, `stabilityPool.t.sol`, `liquidations*.t.sol`, `redemptions.t.sol` | Inherited Liquity branch behavior and JPYdf rename surface. |
| Invariants | `Invariants.t.sol`, `SPInvariants.t.sol`, `AnchoredInvariantsTest.t.sol`, `AnchoredSPInvariantsTest.t.sol`, `InvariantPushModel.t.sol` | State conservation, SP accounting, anchored behavior, strategy push model. |
| dToken/vault/strategy | `DToken.t.sol`, `CollateralVault*.t.sol`, `AaveV3Strategy.t.sol`, `ERC4626Strategy.t.sol`, `MorphoV2Strategy.t.sol` | Mint/redeem, buffer, strategy allocation, impairment. |
| Archived implementations | `archive/LidoStrategy.t.sol`, `archive/EtherfiWeETHStrategy.t.sol`, `archive/DFCandidateStandardPriceFeeds.t.sol`, `archive/DFWBTCPriceFeed*.t.sol`, `archive/sUSDSPriceFeed*.t.sol`, `archive/SkyUsdcSUsdsYieldZapper.t.sol` | Suites for sources preserved under module-local `src/*/archive/` directories. They still run under `forge test` so preserved artifacts cannot silently rot, and are intentionally excluded from coverage shards targeting active scope. |
| Oracles | `DFPriceFeed.t.sol`, `DFWstETHPriceFeed*.t.sol`, `PriceFeedProxy*.t.sol` | Active Chainlink/composite feed behavior, stale/fallback/shutdown handling. |
| Zappers | `zapper*.t.sol`, `CollateralYieldZapper.t.sol`, `Exchange*.t.sol`, `ExchangeApprovalHygiene.t.sol` | Leverage/close flows, approvals, swaps, leftover handling. |
| Governance/deploy/local parity | `deployment.t.sol`, `DFGovernanceHandover.t.sol`, `LocalParityDrill.t.sol`, `DeployLiquity2StrategySelector.t.sol` | Deployment wiring, handover, local production-parity drills. |
| Frontend/off-chain helpers | `MultiTroveGetter.t.sol`, `DebtInFrontHelper.t.sol`, `HintHelpers.t.sol`, `SortedTroves.t.sol` | Read helper behavior and off-chain scanning assumptions. |

## Shared Helpers

| Path | Purpose |
| --- | --- |
| `TestContracts/BaseTest.sol` | Core test base. |
| `TestContracts/BaseMultiCollateralTest.sol` | Multi-branch setup. |
| `TestContracts/DevTestSetup.sol` and `Deployment.t.sol` | Deployment fixture wiring. |
| `TestContracts/*Mock.sol`, `mocks/` | Mock tokens, feeds, strategy, router, and gas grief helpers. |
| `Utils/` | Trove helpers, math/string utilities, logging, deployment access helpers. |

## Suggested Focused Runs

```sh
cd contracts

# Fast local gate similar to normal PR CI
forge test -vv --no-match-contract 'Mainnet|Invariant|Anchored|Initiative|LocalParityDrill'

# Liquidation-related review
forge test -vv --match-path 'test/liquidations*.t.sol'
forge test -vv --match-path test/DebtInFrontHelper.t.sol

# Vault/strategy review
forge test -vv --match-path 'test/CollateralVault*.t.sol'
forge test -vv --match-path 'test/*Strategy.t.sol'

# Active Oracle review
forge test -vv --match-path 'test/*PriceFeed*.t.sol'

# Preserved archive review
forge test -vv --match-path 'test/archive/*.t.sol'
```

Run heavier mainnet, invariant, anchored, and initiative tests locally or through
full CI when the change affects those surfaces.

## Coverage Shards

`forge coverage` disables the normal optimizer and cannot compile the complete
inherited test tree as one unit. CI therefore imports every top-level test into
ten explicit instrumentation shards sized for the GitHub-hosted runner:

| Shard | Import manifest | Scope |
| --- | --- | --- |
| Core base | `coverage-shards/core-base/CoreBaseCoverage.t.sol` | JPYdf token, branch parameters, deployment, and read helpers |
| Core ops A | `coverage-shards/core-ops-a/CoreOpsACoverage.t.sol` | borrower operations and events |
| Core ops B | `coverage-shards/core-ops-b/CoreOpsBCoverage.t.sol` | interest and trove management |
| Core redemption | `coverage-shards/core-redemption/CoreRedemptionCoverage.t.sol` | redemptions, batches, and rebasing shares |
| Core liquidation | `coverage-shards/core-liquidation/CoreLiquidationCoverage.t.sol` | liquidations, shutdown, and stability pool |
| DF vault | `coverage-shards/df-vault/DFVaultCoverage.t.sol` | dToken, vault, strategies, converter, and collateral zapper |
| DF oracle | `coverage-shards/df-oracle/DFOracleCoverage.t.sol` | production and integration price-feed coverage |
| DF deploy | `coverage-shards/df-deploy/DFDeployCoverage.t.sol` | deployment and governance handover guards |
| DF ops | `coverage-shards/df-ops/DFOpsCoverage.t.sol` | PIL, exchange, initiative, debt helper, and router coverage |
| Invariant | `coverage-shards/invariant/CoreInvariantCoverage.t.sol` | inherited, anchored, SP, and push-model invariant suites |

Run one shard with:

```sh
cd contracts
bash utils/run-foundry-coverage-shard.sh core-base lcov_core-base.info
```

`utils/check-foundry-coverage-shards.sh` fails if a top-level test is missing or
imported more than once. `LocalParityDrill.t.sol` is the sole exclusion because
the deployment-wiring CI job runs it against a generated 8-branch manifest.
Mainnet test contracts remain in their owning source shard but are not executed
by coverage; the required mainnet Foundry job runs them with the configured RPC.

Shard directories containing `*.t.sol` are the registration source of truth.
CI discovers its matrix from those directories and merges every resulting LCOV
artifact, so adding or rebalancing a shard does not require parallel name lists.

Coverage uses bounded fuzz and invariant budgets and `--ir-minimum` for stable
instrumentation. It does not replace the required full local, mainnet, or local
deployment test jobs, which retain their normal profiles and failure behavior.
