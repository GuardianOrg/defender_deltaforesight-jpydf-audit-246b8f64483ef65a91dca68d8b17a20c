# Morpho Day-1 Vault Freeze Package

> Positioning: evidence package for freezing the adopted Morpho vaults, curator, oracle, queue,
> bad debt, and withdrawability before enabling the `dUSDC` Day-1 Morpho
> `erc4626` / `morpho-v2` Strategy slots. This is the execution runbook for
> [`../design/Morpho-Operation-Policy.md`](../../operations/policies/Morpho-Operation-Policy.md) and is attached to
> the strategy venue evidence in `Mainnet-Deploy-Env-Freeze-Runbook.md`.

## 1. Scope

This applies only to planned active Ethereum-mainnet Morpho allocation: dUSDC on Day 1. An inert Branch 2–7 enters scope only through its own activation decision.

| Branch | Underlying | Required Strategy kind | Evidence target |
| ---: | --- | --- | --- |
| 0 `dwstETH` | wstETH | none (Day-1 is `aave`-only; no Morpho slot) | No Morpho evidence target until a credible wstETH venue exists (see §4a for the V2 note) |
| 1 `dUSDC` | USDC | `erc4626` / `morpho-v2` | USDC-asset Morpho / MetaMorpho vault, or USDC-asset Morpho Vaults V2 vault via the dedicated `MorphoV2Strategy` (Day-1 policy requires the `morpho-v2` slot on branch 1; see §4a for V2 evidence fields) |

This package approves the **adopted vault**, not a candidate scan. Even though Morpho is in the
planned active set in `Strategy-Selection-Policy.md`, Morpho allocation is not freeze-complete until
this package is complete.

## 2. Required Artifacts

Attach at least the following to the freeze issue / PR.

| Artifact | Required contents |
| --- | --- |
| `morpho-vault-freeze.json` | Output of `contracts/utils/morpho-vault-freeze-evidence.ts`: vault address, asset, roles, pending configs, allocation, queue indexes, oracle, IRM, LLTV, bad debt, API warnings, and optional on-chain ERC-4626 readback |
| `morpho-vault-risk-memo.md` | Human review for curator / owner / guardian / fee / timelock / pending actions, market collateral, oracle, LLTV, liquidity, bad debt, and incident history per adopted vault |
| `morpho-vault-fork-dryrun.json` | Fork block, deposit amount, partial withdraw, full withdraw, `sendToVault`, `emergencyWithdrawFromERC4626`, residual principal / writeoff decision |
| `safe-calldata/` | Safe / Timelock calldata for allocation pause, cap / weight reduction, `sendToVault`, `emergencyWithdrawFromERC4626`, and `writeoffStrategyPrincipal` if needed |
| `monitoring-plan.md` | Alert owner for share price, `maxWithdraw`, `maxRedeem`, pending config, queue / cap change, bad debt, oracle warnings, and curator / allocator changes |

## 3. Evidence Command

After the adopted vault candidates are selected, capture the API snapshot and on-chain readback at
the same `FORK_BLOCK`.

```bash
export FORK_BLOCK=<MAINNET_BLOCK_NUMBER>
export MORPHO_WETH_VAULT=<MORPHO_WETH_ERC4626_VAULT>
export MORPHO_USDC_VAULT=<MORPHO_USDC_ERC4626_VAULT>

pnpm -C contracts exec tsx utils/morpho-vault-freeze-evidence.ts \
  --vault 0:$MORPHO_WETH_VAULT \
  --vault 1:$MORPHO_USDC_VAULT \
  --rpc-url "$MAINNET_RPC_URL" \
  --block "$FORK_BLOCK" \
  --fail-on-blockers \
  --output /path/to/morpho-vault-freeze.json
```

After deploy or fork dry-run, when Strategy addresses are known, also capture `maxWithdraw(strategy)`
/ `maxRedeem(strategy)` readback.

```bash
pnpm -C contracts exec tsx utils/morpho-vault-freeze-evidence.ts \
  --vault 0:$MORPHO_WETH_VAULT \
  --vault 1:$MORPHO_USDC_VAULT \
  --strategy 0:<DEPLOYED_WETH_ERC4626_STRATEGY> \
  --strategy 1:<DEPLOYED_USDC_ERC4626_STRATEGY> \
  --rpc-url "$MAINNET_RPC_URL" \
  --block "$FORK_BLOCK" \
  --fail-on-blockers \
  --output /path/to/morpho-vault-freeze-postdeploy.json
```

`--fail-on-blockers` is required for Day-1 freeze. Omit it only for candidate research.

## 4. Blocker Conditions

Do not freeze Morpho allocation if any of the following applies.

- Branch 0 vault `asset()` is not WETH, or branch 1 vault `asset()` is not USDC.
- Morpho API returns `listed=false`, RED warnings, deposit disabled, or the address cannot be verified from an official source.
- Vault owner / curator / guardian / fee recipient / timelock / pending actions cannot be explained.
- Pending configs exist and their content, executable time, and impact are not approved by the risk owner.
- An allocation market loan asset does not match the branch underlying.
- Active market oracle / IRM / LLTV / collateral / queue index cannot be fetched.
- `badDebt` or `realizedBadDebt` is nonzero.
- High utilization / low liquidity / degraded queues do not have partial withdraw / emergency withdraw dry-runs.
- A vault adopted through kind `erc4626` cannot satisfy `maxWithdraw` / `maxRedeem` evidence
  (always-zero Vault V2-style designs are not an `erc4626` blocker exception — they must be adopted
  through kind `morpho-v2` and satisfy the §4a evidence fields instead).
- There is no Safe calldata, writeoff / backstop process, or comms process for depeg / exploit / curator takeover.

`BLOCKER` findings from `morpho-vault-freeze-evidence.ts` remain Day-1 launch blockers until fixed
or explicitly approved as a scope change. `REVIEW` findings require risk-owner accept / reject /
cap-down decisions on the issue.

## 4a. MorphoV2 (`morpho-v2`) Evidence Fields

For a Morpho Vaults V2 vault adopted through `MorphoV2Strategy`, `maxWithdraw` / `maxRedeem`
readbacks are meaningless (zero by design). Record the following per adopted vault instead, at the
same `FORK_BLOCK`; the normative gate definitions are the V2 Gate table in
[`Morpho-Operation-Policy.md`](../../operations/policies/Morpho-Operation-Policy.md).

| Field | Required contents |
| --- | --- |
| Gates | All four gates (receive-shares / send-shares / receive-assets / send-assets) read back and confirmed unset |
| Sentinel | Sentinel address set; holder and escalation path explained |
| Per-selector timelocks | Timelock value per selector read back (defaults are zero; nonzero is a checklist item, not a protocol guarantee) |
| Adapter registry | Registered adapters (IDs, addresses, target protocols), each explained |
| forceDeallocate penalty | Per-adapter `forceDeallocatePenalty` readback, all ≤ the Strategy's init-frozen `maxForceDeallocatePenaltyBps` (`DF_STRATEGY_MORPHOV2_MAX_PENALTY_BPS`, protocol max 200 bps) |
| maxRate | `maxRate` readback; zero (deployment default) withholds all yield and requires explicit risk-owner acceptance plus monitoring |
| Adapter liquidity | Vault idle balance plus per-adapter deallocatable liquidity readback |
| Withdrawability dry-runs | Fork dry-runs for deposit, partial / full withdraw, `sendToVault`, `emergencyWithdrawFromMorphoV2`, and atomic `forceDeallocateMorphoV2` recovery with a measured penalty, a positive minimum receipt and a post-recovery backing floor |

Candidate selection pool for the branch 1 USDC slot (research snapshot 2026-08; freeze requires a
fresh readback at the adopted `FORK_BLOCK`):

- Steakhouse Prime USDC `0xbeef088055857739C12CD3765F20b7679Def0f51` (~$107M TVL)
- Gauntlet USDC Prime `0x8c106EEDAd96553e64287A5A6839c3Cc78afA3D0` (~$79M TVL)
- plus four further listed USDC V2 vaults from the same scan; record the full scan in the freeze
  issue

No credible wstETH-denominated V2 vault exists today (the sole candidate found held $0.23 TVL and is
unlisted), so branch 0 (`dwstETH`) has no `morpho-v2` evidence target until the market matures.

## 5. Risk Memo Checklist

For each adopted vault, record the following in the issue comment or PR description.

- vault name / symbol / address / official source / listed status / code hash / deployment source
- curator / owner / guardian / fee recipient / timelock / pending owner / pending configs
- public allocator config, flow caps, and whether third-party allocators exist
- supply queue / withdraw queue order, residual exposure in cap-0 markets, removableAt
- collateral, oracle, IRM, LLTV, utilization, liquidity, bad debt, realized bad debt per market
- oracle source and admin / upgrade / stale / revert behavior
- how collateral depeg / price crash / liquidation latency can propagate into supplier loss
- normal / partial / full / emergency withdraw dry-run amount and result
- Strategy cap / weight, CollateralVault buffer / withdrawDelay, and immediate-claim impact
- monitoring owner, backup owner, alert thresholds, and incident escalation

## 6. Issue Gate

Adopted vault freeze is tracked as a new Day-1 blocker issue, not as a policy issue like #569.
Use this title shape:

```text
mainnet: freeze Morpho vault evidence for dUSDC (Day-1)
```

Required labels:

- `Day1`
- `priority high`

Close conditions:

- `morpho-vault-freeze.json` and fork dry-run evidence are attached.
- `BLOCKER` count is zero, or product / risk / contracts / ops explicitly approve a scope change.
- `Parameters.md`, deploy env skeleton, manifest preflight, and frontend / ops displays match the adopted vaults.
- Safe / Timelock calldata and monitoring owner are finalized.

## 7. Handoff To Deploy Env Freeze

After this package passes, reflect the following in `Mainnet-Deploy-Env-Freeze-Runbook.md` env
skeleton.

- `DF_STRATEGY_ERC4626_VAULT_0_2=<MORPHO_WETH_ERC4626_VAULT>`
- `DF_STRATEGY_CAP_0_2`
- `DF_STRATEGY_WEIGHT_BPS_0_2`
- `DF_STRATEGY_ERC4626_VAULT_1_1=<MORPHO_USDC_ERC4626_VAULT>`
- `DF_STRATEGY_CAP_1_1`
- `DF_STRATEGY_WEIGHT_BPS_1_1`

For a `morpho-v2` slot, the corresponding keys are `DF_STRATEGY_MORPHOV2_VAULT_<branch>_<index>` and
`DF_STRATEGY_MORPHOV2_MAX_PENALTY_BPS_<branch>_<index>` (deploy default 200), alongside the same
`DF_STRATEGY_CAP` / `DF_STRATEGY_WEIGHT_BPS` keys.

If vault roles, pending configs, queues, market caps, bad debt, share price, `maxDeposit`, or
`maxWithdraw` materially change between env freeze and broadcast, mark the old package superseded
and regenerate the package at a new `FORK_BLOCK`.
