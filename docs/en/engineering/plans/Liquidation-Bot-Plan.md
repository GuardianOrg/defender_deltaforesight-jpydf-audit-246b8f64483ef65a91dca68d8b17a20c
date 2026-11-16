# Liquidation Bot Implementation Plan

## Purpose

Provide a Rust keeper that continuously detects undercollateralized Troves in the JPYdf/Liquity v2 Core and lets the operating entity execute liquidations as needed. For operational use, the requirements include not making external profit maximization of liquidations a hard condition, and being able to prioritize protocol health within an explicit gas / loss budget.

## Modes

| Mode | Policy |
| --- | --- |
| `profit-seeking` | Day-2 mode. Live startup fails closed until the bot has collateral-disposal and inventory-aware profit modeling |
| `protocol-maintenance` | Allow sending if the estimated loss is at most `max_loss_wei_per_tx` and at most `max_gas_cost_wei` |

In both modes `dry_run = true` is the initial value. Read-only / dry-run mode does not load a signing key and uses only an HTTP RPC Provider. Actual sending is permitted only when `execution.enabled = true`, `execution.dry_run = false`, `execution.private_key_env` is configured to a non-empty env var name, that env var exists, the RPC `eth_chainId` matches `chain.chain_id`, and the live policy has explicit positive caps. The current implementation only supports live `protocol-maintenance`; live `profit-seeking` is rejected even when `min_profit_wei` is positive.

## Initial Implementation Scope

1. Per-branch `SortedTroves` paging exploration via `LiquidationCandidateGetter.getLiquidationCandidatesWithLastZombie`, with simultaneous confirmation of `lastZombieTroveId`.
2. Use the protocol price obtained via `IPriceFeed.fetchPrice()`.
3. Obtain the MCR from `IAddressesRegistry.MCR()` or a configured value.
4. Re-verify candidate Troves with `TroveManager.getCurrentICR` immediately before sending.
5. Take a gas estimate of `TroveManager.batchLiquidateTroves` and decide whether to send via operator policy.
6. Confirm zombie Troves that have dropped out of `SortedTroves` via the LCG `includeLastZombie` path, and handle `entireDebt` / `entireColl` with the same candidate structure.
7. The initial version's revenue estimation conservatively treats the gas cost as a loss. Profit estimation including collateral receipt and disposal is to be added later.

## Catch Model

The initial backend makes the `new-block` trigger that works with HTTP RPC alone the standard. While `run` is active, it polls `eth_blockNumber` and, when it detects a new block, runs `LiquidationCandidateGetter` from the branch cursor. After each scan it saves `last_seen_block` and the branch cursor to a state file, so even after a restart it continues the traversal without excessively repeating the same range. The state file is written to a temporary file and then atomically replaced, reducing the chance of leaving a partially written cursor file on daemon stop/restart.

In Liquity v2, `SortedTroves` is ordered by annual interest rate, not by ICR, so a liquidation search cannot early-stop. Therefore the bot keeps performing a traversing scan per branch. `batchLiquidateTroves` skips non-target Troves in the array and liquidates only active/zombie Troves with `ICR < MCR`, but the bot also re-confirms with `getCurrentICR` immediately before sending.

Liquidation distribution follows the Liquity Core path. If there is JPYdf available in the Stability Pool, an SP offset is applied; the shortfall goes to redistribution; surplus collateral is accumulated in the CollSurplusPool. JIT is an external action where a third party deposits into the SP before execution, not a branch inside `batchLiquidateTroves`. Because `TroveManager` offsets while leaving `MIN_JPYDF_IN_SP`, the bot logs the offset capacity from `getTotalJpydfDeposits()`.

As an auxiliary trigger, the `poll-interval` is retained. This is because in a local anvil or a verification environment with irregular block production, there are cases where one wants to scan at fixed intervals even within the same block.

## Liquity v2 Assumptions

| Core behavior | Reflection in the Bot |
| --- | --- |
| Only active/zombie Troves with `ICR < MCR` are liquidation targets | The bot's final decision is also unified on `getCurrentICR(troveId, protocolPrice) < MCR` |
| `batchLiquidateTroves` runs `priceFeed.fetchPrice()` internally | The bot-side price is for exploration / re-verification / logging. The final execution price follows the Core |
| After the SP offset, the shortfall goes to redistribution | Keep the SP deposits and offset capacity in the log and use them as context for the deficit-tolerance decision |
| `SortedTroves` is ordered by annual interest rate | Do not do ICR-ordered priority exploration. Make cursor traversal and re-verification the basis |
| Zombies drop out of `SortedTroves` | Pick up the `lastZombieTroveId` as a trailing candidate via the LCG `getLiquidationCandidatesWithLastZombie(..., includeLastZombie=true)`. However, full coverage of multiple zombies is a follow-up task |
| Even after a branch shutdown, the remaining debt is wound up by urgent redemption / repayment / liquidation | The liquidation keeper does not auto-stop a shutdown branch. The urgent redemption keeper is made a separate process |

## Implementation Location

- `bots/liquidator/`
  - Rust crate.
  - Place a local/dev configuration example in `config.example.toml`.
  - The initial commands are `scan-once` and `run`.
  - Place `systemd/jpydf-liquidator.service.example` and `Dockerfile` as operational startup templates.

## Phases

| Phase | Content | Completion condition |
| --- | --- | --- |
| M1 | read-only scanner | Can log each branch's price/MCR/candidates/cursor |
| M2 | operator policy | Fix the send decisions for `profit-seeking` and `protocol-maintenance` with unit tests |
| M3 | dry-run execution planning | Can output a gas estimate and send eligibility per batch |
| M3.5 | backend catch loop | Can do new-block detection, state persistence, restart resume, read-only startup without a key, and RPC chainId fail-fast |
| M4 | local fork live tx | Can actually send `batchLiquidateTroves` on an Anvil/local deploy |
| M5 | Day-1 production hardening | Add private relay, RPC quorum, persistent cursor, Prometheus, alert, and runbook for `protocol-maintenance` |
| M5.5 | profit-seeking evidence design | Freeze the evidence schema for collateral-disposal routes, inventory, gas, relay, RPC quorum, and receipt classification |

## Safety Conditions

- Do not send for a branch whose protocol price feed returned an oracle failure.
- Exclude candidates with `ICR + buffer >= MCR` from the send batch.
- Do not send an empty batch.
- Have a per-branch enable flag.
- Live execution requires RPC chainId match and the signing-key env var. Read-only / dry-run mode does not read a signing key.
- Branch config fails fast before startup when it is empty, has duplicate indexes, or has an enabled branch with incomplete contract settings.
- Even in `protocol-maintenance`, do not perform unlimited deficit liquidation. Live startup requires positive `max_loss_wei_per_tx` and `max_gas_cost_wei`, and both must be satisfied per batch.
- Live `profit-seeking` fails closed in the current implementation. Positive `min_profit_wei` and `max_gas_cost_wei` are not sufficient until the profit model includes collateral-disposal routes, inventory cost, slippage, gas, relay, and RPC quorum.
- Launch dry-run evidence includes `profitEvidence.status = "unsupported"` on each planned batch until collateral-disposal routes, inventory, market depth, relay policy, and scanner routing / provider voting are modeled. `profitEvidence.liquidatorGasCompensation` computes only the Core WETH gas compensation and collateral gas compensation on the SP-offset portion; it excludes SP/JIT gain, collateral disposal, and inventory cost. `profitEvidence.gasForecast` records base fee, priority fee, max fee, and the stress multiplier; it does not imply that private relay, replacement, cancellation, or bundle failure handling is implemented. Top-level `rpcQuorum` records configured RPC provider health and block lag without raw RPC URLs, while nested `profitEvidence.rpcQuorum` remains partial until fallback routing, provider voting, and price-source quorum are implemented. Nested `profitEvidence.receipt` records the timeout and supported live outcome classifications, but remains planning evidence until persistent receipt and PnL accounting exist.
- Strategy-incident writeoff and bot-restart decisions follow the [Strategy Incident / Liquidation Safety Runbook](../../protocol/operations/runbooks/Strategy-Incident-Liquidation-Safety-Runbook.md). Evaluate Aave, ERC-4626 (Morpho/Euler), Lido, and other asset-transforming Strategies by registered Strategy kind rather than branch symbol because accounting loss and temporary liquidity restriction have different meanings.
- Operate the hot key holding only ETH for gas. Disposal/evacuation of received collateral is handled not by the bot itself but by a follow-up executor / Safe runbook.

## Follow-up Tasks

- Create undercollateralized Troves on an Anvil/local deploy and verify the liquidation flow from dry-run to live tx.
- Subscribe to liquidation events / Trove update events to speed up the candidate cache.
- Add revenue estimation including collateral receipt, swap, and inventory valuation, and satisfy the Day-2 profit-seeking hardening gate in the Japanese source-of-truth liquidation management policy.
- Classify the redistribution revenue difference when the Stability Pool is depleted.
- Add an indexer that covers multiple zombie Troves (the LCG handles only the single `lastZombieTroveId` held by the core).
- Add the shutdown / urgent redemption keeper separated from the liquidation keeper.

## Auxiliary References (not authoritative)

- Liquity v2 Core: `contracts/src/TroveManager.sol`
- LiquidationCandidateGetter: `contracts/src/LiquidationCandidateGetter.sol`
- Aave V3 Pool `liquidationCall`: https://aave.com/docs/aave-v3/smart-contracts/pool
- Compound III Liquidation / `isLiquidatable` / `absorb`: https://docs.compound.finance/liquidation/
- Maker Liquidation 2.0 keeper wallet security: https://docs.makerdao.com/smart-contract-modules/dog-and-clipper-detailed-documentation
- Chainlink Automation interfaces: https://docs.chain.link/chainlink-automation/reference/automation-interfaces
