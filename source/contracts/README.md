# Contracts Workspace Index

This directory contains the Solidity implementation, deployment scripts, and
tests for JPYdf. Use this file as the contract-audit entry point; root
`README.md` is the repository overview and this file is the contract-specific
map.

## Read First

1. [`../AGENTS.md`](../AGENTS.md) - repository-level agent guide.
2. [`../documents/README.md`](../documents/README.md) - task-to-doc map.
3. [`../documents/jp/engineering/guides/Contract-Audit-Usage-Map.md`](../documents/jp/engineering/guides/Contract-Audit-Usage-Map.md)
   - expected actors, entrypoints, keeper/admin paths, and disabled routes.
4. [`../documents/jp/protocol/product/spec/Liquity-v2-Core-Spec.md`](../documents/jp/protocol/product/spec/Liquity-v2-Core-Spec.md)
   - inherited core behavior and JPYdf core modifications.
5. [`src/README.md`](src/README.md) - contract source map and audit lanes.
6. [`test/README.md`](test/README.md) - test suite map.

## Directory Map

| Path | Purpose |
| --- | --- |
| [`src/`](src/) | Protocol contracts, interfaces, price feeds, strategies, zappers, and types. |
| [`test/`](test/) | Foundry tests, invariant tests, fork tests, mocks, and shared test helpers. |
| [`script/`](script/) | Forge scripts for deployment, governance handover, seeding, redemptions, and liquidity operations. |
| [`utils/`](utils/) | TypeScript/JS deployment utilities, local-stack helpers, ABI extraction, and local app env writers. |
| [`abi/`](abi/) | Extracted ABI artifacts consumed by off-chain packages. |
| [`certora/`](certora/) | Certora configs/specs/harnesses for formal verification work. |
| [`lib/`](lib/) | Vendored submodules. Do not edit unless the task explicitly targets a dependency. |

Generated/build outputs such as `out/`, `cache/`, `broadcast/`, and
`deployment-manifest.json` / `pil-activation-manifest.json` should not be used
as checked-in source-of-truth code. Regenerate `deployment-manifest.json` from
the deploy script and reject any manifest that is missing required
`launchEvidence`. Regenerate `pil-activation-manifest.json` from
`script/DeployPILAllocatorPhaseA.s.sol` when Phase-A PIL activation is in scope.

## Audit Lanes

Use
[`../documents/jp/engineering/guides/Contract-Audit-Usage-Map.md`](../documents/jp/engineering/guides/Contract-Audit-Usage-Map.md)
to classify each external/public function by expected caller before reviewing an
audit lane below.

| Lane | Primary code | Source-of-truth docs | Typical tests |
| --- | --- | --- | --- |
| Liquity core accounting | `src/{BorrowerOperations,TroveManager,StabilityPool,ActivePool,DefaultPool,CollateralRegistry,RedemptionHelper}.sol` | `documents/jp/protocol/product/spec/Liquity-v2-Core-Spec.md` | `test/{borrowerOperations,troveManager,stabilityPool,redemptions,liquidations}.t.sol`, invariant suites |
| Debt token surface | `src/JpydfToken.sol`, `src/Interfaces/IJpydfToken.sol` | `documents/jp/protocol/product/spec/JpydfToken.md` | `test/JpydfToken.t.sol`, `test/MinDebtJPYdf.t.sol` |
| dToken and vault | `src/DToken.sol`, `src/CollateralVault.sol` | `documents/jp/protocol/product/spec/dToken.md`, `documents/jp/protocol/product/spec/CollateralVault.md` | `test/DToken.t.sol`, `test/CollateralVault*.t.sol`, `test/InvariantPushModel.t.sol` |
| Strategies | `src/Strategies/` | `documents/jp/protocol/product/spec/strategies/` | `test/{AaveV3Strategy,ERC4626Strategy,MorphoV2Strategy,SkyUsdcSUsdsStrategy,SkyUsdcSUsdsConverter}.t.sol`, strategy/vault integration tests |
| Archived Strategies | `src/Strategies/archive/` | `documents/jp/archive/` | `test/archive/{LidoStrategy,EtherfiWeETHStrategy}.t.sol`. Out of active audit scope; retained because they were covered by the external audit completed 2026-08-05 (`0c7766e0`). Still compiled and tested, excluded from coverage shards. No deploy path |
| Oracles | `src/PriceFeeds/` | `documents/jp/protocol/product/spec/Oracle.md`, `documents/jp/Parameters.md` | `test/*PriceFeed*.t.sol`, `test/PriceFeedProxy*.t.sol` |
| Zappers | `src/Zappers/` | `documents/jp/protocol/product/spec/Zapper.md` | `test/zapper*.t.sol`, `test/CollateralYieldZapper.t.sol`, approval hygiene tests |
| Treasury retention / interest route | `src/InterestRouterForwarder.sol`, `src/PILAllocator.sol`, `src/Initiatives/UniV4MerklInitiative.sol` plus deployment/governance scripts | `documents/jp/protocol/operations/runbooks/Treasury-Safe-Retention-Runbook.md`, `documents/jp/protocol/product/spec/InterestRouter.md`, `documents/jp/protocol/product/spec/PILAllocator.md` (`Treasury.md` describes future implementation scope) | `test/InterestRouterForwarder.t.sol`, `test/PILAllocator.t.sol`, `test/UniV4MerklInitiative.t.sol`, local parity drills |
| Liquidation discovery | `src/LiquidationCandidateGetter.sol`, core liquidation paths | core spec plus `bots/liquidator/README.md` | `test/liquidations*.t.sol`, `test/DebtInFrontHelper.t.sol`, liquidator bot tests |

## Local Commands

```sh
cd contracts
forge build
./utils/check-contract-sizes.sh
forge test -vv --no-match-contract 'Mainnet|Invariant|Anchored|Initiative|LocalParityDrill'
```

Use `./utils/check-contract-sizes.sh` for the EIP-170 production size gate. A
bare `forge build --sizes` also evaluates test artifacts, including deliberately
large tester contracts, and can return non-zero even when every deployable
contract is within the limit. The wrapper excludes `test/` and `script/` in the
same way locally and in CI, and writes the build to an isolated temporary
artifact directory so tester artifacts left by an earlier `forge test` cannot
leak back into the size report.

The normal PR `Foundry tests` check runs the fast gate above. Mainnet, invariant,
anchored, and initiative-heavy suites are available on protected branch pushes,
manual workflow runs, and PR labels such as `full-ci` / `full-foundry`.
`LocalParityDrill` is run by the local deployment CI job after an 8-branch
manifest has been generated.

## Slither

```sh
cd contracts
python3 -m venv .venv
source .venv/bin/activate
pip3 install -r requirements.txt
slither . --compile-force-framework foundry --config-file slither.config.json
```

`contracts/slither.config.json` is a development triage config. For external
audit evidence, use the audit handoff config and command in
`jpydf-audit/BUILD_AND_TEST.md` so first-party helper paths and noisy detectors
are reviewed consistently. Keep Slither output out of the repo unless a review
explicitly asks for a saved report. Temporary reports belong under
`/private/tmp` and can be deleted after the finding has been triaged.

## Simplification Checklist

When reviewing for simplification, prefer deleting or consolidating only after
checking the owning docs and downstream consumers:

- `utils/` scripts: verify whether frontend, local stack, CI, or deployment
  runbooks still call them.
- duplicate helpers in `script/` and `utils/`: keep the path used by deploy and
  local-stack flows.
- adapter-like contracts in `src/Zappers/`, `src/PriceFeeds/`, and
  `src/Strategies/`: preserve explicit trust boundaries even when logic looks
  thin.
- generated ABI/address consumers: update `frontend/df-shared`, `frontend/app`,
  `frontend/console`, `frontend/ops`, and `subgraph` together.
