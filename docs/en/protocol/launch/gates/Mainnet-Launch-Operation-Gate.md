# Mainnet Launch Operation Gate

> **Positioning**: even if deploy / handover succeeds technically, do not publicly launch unless SP seed, JPYdf/USDC exit liquidity, bootstrap Trove, redemption / liquidation operations, ops monitoring, and per-participant readiness are all in place. The source of truth for deploy evidence is [`Mainnet-Initial-Configuration-Checklist.md`](Mainnet-Initial-Configuration-Checklist.md), the Safe / role holder real-address package is [`Mainnet-Safe-Role-Assignment-Gate.md`](Mainnet-Safe-Role-Assignment-Gate.md), the source of truth for B/S buckets is [`Balance-Sheet-Liquidity-Allocation-Policy.md`](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md), the source of truth for liquidity routes is [`Liquidity-Route-Policy.md`](../../product/policies/Liquidity-Route-Policy.md), and the display / evidence gate from the borrower / SP depositor / liquidator perspective is [`Mainnet-Participant-Readiness-Gate.md`](Mainnet-Participant-Readiness-Gate.md).
>
> This document is a gate for deciding "can we sustain this after opening the market," and does not record private keys, undisclosed Safe nonces, the raw `MAINNET_RPC_URL`, RPC provider API keys, or detailed real fund balances. RPC information left in evidence is limited to the provider label and a redacted URL.

---

## 0. Principles

Launch risk for the Liquity v2 family depends more on initial market depth and operational monitoring than on the contract deploy itself.

- On a branch with a thin SP, liquidation tends to fall back to redistribution, making peg / branch health harder to explain.
- If JPYdf exit liquidity is thin, then borrowers, SP depositors, and liquidators all find JPYdf hard to handle.
- When using initial JPYdf for LP / SP seed, the risk and accounting of the bootstrap Trove that issues it must be decided first.
- The current liquidator is an operator maintenance bot and does not include JPYdf sourcing, automatic SP top-up, atomic JIT bundles, or collateral disposal.
- subgraph / frontend display is necessary for launch UX, but the primary source for launch safety is the current manifest + direct RPC reads.
- If borrowers / SP depositors / liquidators cannot read the metrics they need, then opening the market means we cannot explain the expected value of natural participation, so per-participant readiness is included in the launch evidence.

---

## 1. Gate Stages

| Stage                    | Purpose                                                 | Go condition                                                          |
| ------------------------ | ------------------------------------------------------- | --------------------------------------------------------------------- |
| T-1 deploy readiness     | freeze the operations plan before entering deploy / handover | the owners, targets, fund buckets, and execution order of §2–§7 are approved |
| T-0 activation readiness | execution confirmation after handover, before public launch / liquidity add | evidence for SP seed / JPYdf liquidity / bot dry-run / ops monitoring / participant readiness is complete |
| T+24h watch              | monitoring immediately after launch                     | the metrics in §8 are monitored with no block lag and the incident owner is available to respond |

A branch that has not met T-0 readiness cannot open exposure through any of public UI / cap / liquidity / campaign. To open it as an exception, leave a signed exception from the risk owner and launch owner in the evidence package.

---

## 2. SP Seed Gate

For each active branch, freeze the target and minimum acceptable value of the initial Stability Pool seed.

| Item               | Required content                                                                                                                        |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| `targetSpJpydf`    | the target SP deposit per branch. Evidenced in JPYdf 18 decimals                                                                        |
| `plannedDebtJpydf` | the planned debt used as the coverage denominator when branch debt is 0. JPYdf 18 decimals. Not additional issuance, but a record of the launch exposure envelope |
| `minSpCoverageBps` | optional advisory check value for `SP deposits / coverage debt`. Day-1 launch prioritizes the absolute-value design in [`Day1-Self-BS-Initial-Liquidity-Plan.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Initial-Liquidity-Plan.md); ratio rules are not Day-1 hard launch gates and are handled as post-launch cap-ramp advisory checks in [`Active-Branch-Cap-Ramp-Runbook.md`](../../operations/runbooks/Active-Branch-Cap-Ramp-Runbook.md) |
| seed source        | bootstrap borrower, treasury-held JPYdf, existing holder, etc. State the actual fund bucket and accounting owner                        |
| seed owner         | the Safe / account that executes and maintains the SP deposit. Do not write the private key                                            |
| exit plan          | until when the seed is maintained, the withdrawal conditions, and the alternative coverage at withdrawal                               |

`activeBranches` lists only branches that open exposure through public launch / UI / cap / campaign.
Day-1 inert or cap-zero branches are outside the SP coverage gate. If branch debt is zero when exposure opens,
`plannedDebtJpydf` is mandatory. `activeBranches`, SP targets, and planned debt must match the
[Mainnet Launch Product Decision Record](../decisions/Mainnet-Launch-Product-Decision-Record.md); company-funded
seed source, owner, and amount must match the
[Day-1 Self-B/S Launch Commitment](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Launch-Commitment.md).

No-Go:

- The SP seed target or advisory coverage policy of an active branch is not approved.
- An active branch has branch debt of 0 but `plannedDebtJpydf` is unapproved, 0, or unexplainable from the evidence.
- JPYdf for the SP seed is double-counted with LP seed, Treasury reserve, or backstop.
- The seed execution owner is not frozen in the Safe role assignment package, or is unable to operate at launch.
- There is no evidence for the reason to open a seed-unmet branch with a nonzero cap / public UI / campaign.

---

## 3. JPYdf/USDC Exit Liquidity Gate

Day-1 DEX liquidity targets only the JPYdf/USDC Uniswap v4.

| Item            | Required content                                                                                                                            |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| pool key        | token ordering, fee, tick spacing, hook address, PoolManager                                                                                |
| LP owner        | position owner / manager, accounting owner, allowance cleanup owner                                                                         |
| initial amounts | `initialUsdc` (USDC raw token amount), `initialUsdcValueJpy` (the JPY notional of 50 million yen), `initialJpydf` (50 million JPYdf), funding source |
| route checks    | sample sell / buy size, expected slippage, deadline, private tx policy                                                                      |
| exclusions      | that there is no Curve, Uniswap v3, Balancer, or USDT / USDS / WETH / XAUT direct JPYdf pool                                                |

No-Go:

- The JPYdf/USDC pool is uninitialized, or the LP owner / funding source / allowance cleanup is unapproved.
- The LP owner / funding source / allowance cleanup owner does not match the Safe role assignment package.
- The sample slippage of the JPYdf exit route is unmeasured.
- The frontend, ops, bot, or runbook assumes a direct pool / route outside the Day-1 policy.

---

## 4. Bootstrap Trove / JPYdf Source Gate

When JPYdf is needed for LP seed, SP seed, or operator inventory, freeze the issuer.

| Item                | Required content                                                                                                                                                                                                                                                                            |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| source type         | bootstrap Trove / market borrow / treasury-held JPYdf / other                                                                                                                                                                                                                               |
| branch              | the collateral branch when using a bootstrap Trove                                                                                                                                                                                                                                          |
| borrower owner      | Safe / account, accounting owner                                                                                                                                                                                                                                                            |
| collateral / debt   | collateral amount, debt amount, initial ICR, interest rate, whether a batch manager is used                                                                                                                                                                                                 |
| borrow APR policy   | the Borrow APR / Bootstrap Trove policy of [`Day1-Self-BS-Initial-Liquidity-Plan.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Initial-Liquidity-Plan.md), short-term JPY reference yield, DeFi risk premium, target SP APR, target SP coverage, `SP_YIELD_SPLIT`, the computed initial anchor, the management range, and the rate review cadence |
| Trove count / split | the Day-1 bootstrap sources are branch 0 dwstETH and branch 1 dUSDC as frozen by the Product Decision Record and Self-B/S commitment. Branches 2-7 have no bootstrap/SP seed. Record per-Trove debt, rate, owner, unwind plan, and accounting approval; this creates no redemption exclusion or reconstruction guarantee |
| structured split    | `bootstrapSources[*].collateralValueJpy`, `maxLtvBps`, `mintedJpydf`, `borrowRateBps`, `branches[*].targetSpJpydf`, `liquidity.initialJpydf`, `liquidity.initialUsdcValueJpy` |
| unwind plan         | repay / close conditions, the repayment source at LP / SP seed release                                                                                                                                                                                                                      |

No-Go:

- The JPYdf acquisition path for LP / SP seed is unknown.
- The sum of `bootstrapSources[*].mintedJpydf` does not match the sum of `branches[*].targetSpJpydf` + `liquidity.initialJpydf`.
- `liquidityUsdcValueJpy` does not match `initialUsdcValueJpy` in the liquidity config, or the runtime `initialUsdc` raw amount is undetermined.
- The bootstrap Trove's owner, ICR, interest rate, or repayment plan is unapproved.
- The bootstrap borrower owner / repayment owner does not match the Safe role assignment package.
- The bootstrap Trove's borrow APR cannot be explained from the Day-1 policy back-calculation formula, or the rate review / adjustment owner is undetermined.
- Multiple bootstrap Troves are created, but the launch checker / evidence cannot record the per-Trove split and the DF-side risk-reduction buffer approval.
- A demo Trove / test data / local-only helper is confused with the mainnet seed.

---

## 5. Redemption Monitoring Gate

Even when there is no automatic redemption bot on Day-1, ensure that the operator can monitor redemption health.

| Metric                                 | Primary source                                    |
| -------------------------------------- | ------------------------------------------------- |
| JPYdf/USDC pool price / depth          | Uniswap v4 pool direct read                       |
| redemption fee / base rate             | CollateralRegistry / RedemptionHelper direct read |
| branch outside debt / unbacked portion | ActivePool / StabilityPool / console direct reads |
| lowest-rate Trove distribution         | SortedTroves / helper direct read                 |
| urgent redemption / shutdown state     | TroveManager / CollateralRegistry direct read     |

No-Go:

- There is no owner to monitor the JPYdf price and redemption route at launch.
- There is no dry-run to confirm the redemption fee / base rate / branch routing.
- The liquidity add / SP seed / pause / communication owner in case JPYdf depegs is undetermined.

---

## 6. Liquidation Operator Gate

Treat the current bot as an operator maintenance bot. Do not assume completion of a profit-seeking keeper network as a Day-1 premise.

| Item                              | Required content                                                                                                                                                                          |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| config source                     | the generated config derived from the current `deployment-manifest.json`                                                                                                                 |
| enabled branches                  | borrowable dwstETH / dUSDC only; branches 2–7 are excluded from scanning/submission                                                                                       |
| mode                              | whether to launch in dry-run / protocol-maintenance. `profit-seeking` is No-Go as Day-2 treatment until collateral disposal / inventory-aware profit model is implemented               |
| role lifecycle isolation          | physically separate dry-run and live-signer task roles; a first monotonic-cutoff non-live desired-zero stop epoch leaves both roles deny-only and unconditionally denied until cutoff passage; a second future-cutoff epoch completes non-live packet refresh and live desired-zero staging before `PRIMARY.updatedAt < cutoff`; desired one removes only the live deny-all guard and changes only live trust |
| scoped activation authority       | a local `iamAuthorityEvidence` exact-byte hash generated within 30 minutes; from canonical raw records the checker re-derives a conservative static-Allow upper bound for all-cluster active tasks/effective roles, Application Auto Scaling, every regional CloudFormation stack/RoleARN, deferred ECS targets in EventBridge/Scheduler/Pipes, and direct ECS/CFN plus STS trust-chain authority for every IAM user/role; zero signer-role task, zero deferred live-role target, and zero unexpected capable principal. It does not prove effective IAM decisions or the absence of all account-wide AWS authority. Deferred targets are a point-in-time inventory; subsequent EventBridge/Scheduler/Pipes mutation, IAM/KMS policy mutation, human controllers of the GitHub repository, and concurrent admin drift are an explicit change-freeze boundary from packet generation through activation. Operator approval is sufficient; no third party is required |
| gas wallet / caps                 | public address, funding owner, `maxGasCostWei`, `maxLossWeiPerTx`, `gasCostStressMultiplierBps`, high-gas escalation owner                                                               |
| RPC                               | chain id check, provider label, `rpcQuorumRequired`, `rpcMaxBlockLag`, fallback policy                                                                                                   |
| dry-run evidence                  | top candidate, min ICR, SP deposit, SP offset capacity, SP-covered candidate count, top-level `rpcQuorum`, planned batch gas/baseFee/priorityFee/maxFee/gasCost/stressedGasCost/decision, `profitEvidence.status` / `liquidatorGasCompensation` / `gasForecast` / `rpcQuorum` / `receipt`, `generatedAtBlock` and acceptable block age |
| thin-SP / redistribution decision | the condition for receiving redistribution without JIT on a thin-SP branch, the judging owner, and the decision log                                                                      |
| manual JIT / top-up               | who judges and executes outside the bot, the JPYdf funding source, the SP deposit account, and the top-up tx procedure                                                                   |
| collateral disposal               | who values, evacuates, and disposes of the dToken / underlying received in liquidation                                                                                                   |

No-Go:

- The bot config is not generated from the current manifest.
- Dry-run and live reuse one physical task role, the live role can be assumed while non-live, the KMS key-policy principal differs from `LiquidatorLiveTaskRoleArn`, either monotonic-cutoff epoch is skipped, or the staged PRIMARY deployment is not older than the activation cutoff.
- `iamAuthorityEvidence` contains only self-asserted summaries, does not match its exact-byte hash, is older than 30 minutes, omits any account principal/cluster/pagination/Auto Scaling restart path, or its observed capable-principal set differs from the operator-approved set.
- The liquidator gas wallet / keeper ops wallet / escalation owner does not match the Safe role assignment package.
- The dry-run does not scan the active branches.
- `liquidator.dryRunEvidence` is not readable as local JSON, or the chain id / config hash / enabled branches / scanned branches / `generatedAtBlock` freshness / RPC quorum evidence does not match the launch config.
- `maxGasCostWei` / `maxLossWeiPerTx` / `gasCostStressMultiplierBps` / `minSpOffsetCoverageBps` / `rpcQuorumRequired` / `rpcMaxBlockLag` / `receiptTimeoutSecs`, the high-gas escalation owner, or the failed receipt escalation owner is unapproved.
- The dry-run evidence does not include per-branch SP deposit / SP offset capacity / SP-covered candidate count, top-level `rpcQuorum`, the planned batch's gas / baseFeePerGas / priorityFeePerGas / maxFeePerGas / gasCost / stressedGasCost / decision / `profitEvidence.status` / `liquidatorGasCompensation` / `gasForecast` / `rpcQuorum` / `receipt`, or treats only gas compensation, gas forecast, RPC health, or receipt classification as full profit.
- The `execution.enabled` of the launch dry-run evidence is not true, or a policy blocker is not surfaced as a `skipReason`.
- `liquidator.mode = "profit-seeking"` is put in the Day-1 launch config.
- There is no judging owner and decision log for whether to JIT top-up or receive redistribution under thin SP.
- It is live mode but the gas / loss / receipt policy is unapproved, or the caps in the dry-run evidence do not match the launch config.
- SP top-up / JIT / collateral disposal is misperceived as already implemented in the bot.

---

## 7. Ops Monitoring Gate

In the launch window, at least the following metrics must be confirmable on a single screen or by a runbook command.

| Area                    | Metric                                                                                                                  |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------- |
| branch health           | TCR, SCR, CCR, MCR, shutdownTime, oracle price / updatedAt, `priceSource == primary`, `jpyFrozenSince == 0`            |
| SP coverage             | branch debt, SP deposits, outside debt, coverage bps, pending SP yield                                                 |
| liquidation             | top candidate, min ICR, candidate count, SP offset capacity, bot block lag                                             |
| redemption              | JPYdf supply, redemption sample amount, fee / base rate, routing rows                                                  |
| liquidity               | JPYdf/USDC price, pool depth, sample slippage, LP owner, ERC20 / Permit2 residual allowance                            |
| dToken / strategy       | cap usage, Vault buffer, backing ratio, strategy exposure, paused flags                                                |
| external depeg monitors | USDC market vs Chainlink and dwstETH stETH/ETH plus canonical-rate monitoring, monitor source, alert owner             |
| bridge readiness        | `bridgeMinterCount == 0`, `proposedBridgeMinter == address(0)`, absence of an active bridge adapter, bridge admin owner/evidence |
| incidents               | Guardian availability, cap freeze plan, pause tx owner, communication owner                                           |

No-Go:

- Any of branch health, SP coverage, oracle freshness, redemption routing, or liquidation scan is unreadable at launch.
- The borrower / SP depositor / liquidator No-Go items of [Mainnet-Participant-Readiness-Gate.md](Mainnet-Participant-Readiness-Gate.md) are unresolved, or Day-2 unimplemented items are displayed as if implemented.
- An active branch's oracle source is not `primary`, or it is under JPY soft-freeze (`jpyFrozenSince != 0`).
- The dUSDC market/Chainlink divergence monitor or dwstETH stETH/ETH and canonical-rate monitor cannot be confirmed.
- The Day-1 `bridgeMinterCount` is not 0, `proposedBridgeMinter` remains, or an active bridge adapter / other-chain issuance is connected.
- When advancing Day-2 and later bridge minter registration / canary / public route / cap ramp simultaneously, the corresponding Stage A/B/C evidence of [Bridge-Minter-Activation-Gate.md](../../operations/runbooks/Bridge-Minter-Activation-Gate.md) is unapproved, or you are trying to open the frontend / public route, third-party accessible route, or cap ramp with only minter registration.
- When making a BTC wrapper branch active, the WBTC/BTC peg leg freshness evidence in addition to collateral/USD and JPY/USD is unreadable.
- The JPYdf / USDC residual allowance of the JPYdf/USDC LP owner remains on the PoolManager, Universal Router, Permit2, or the Universal Router allowance inside Permit2.
- Private Operations Monitor / headless script is reading a stale manifest or a legacy snapshot.
- The Guardian / Allocator / Writeoff / Timelock incident owner is unable to respond in the launch window.

---

## 8. T+24h Watch

For 24 hours after launch, retain the following as periodic snapshots.

- JPYdf/USDC price / depth / sample slippage.
- branch debt, SP deposits, outside debt, coverage bps.
- branch TCR / SCR / CCR proximity.
- oracle freshness and last good price.
- liquidation bot cycles, candidate count, tx submission / failures.
- redemption route sample and fee / base rate.
- Vault buffer / strategy exposure / backing ratio.
- USDC secondary market depeg monitor (wstETH/stETH market health is covered by the oracle freshness checks).
- bridge dormant state: minter count, pending minter, active adapter flag, supply monitor baseline.
- Guardian pause / cap freeze readiness.

The standard snapshot is taken with `mainnet-launch-24h-snapshot`. This command runs `mainnet-launch-operation-check`
once, and in addition to the per-snapshot `launch-operation-evidence.{json,md}`, it updates the 24h-watch
`t24h-snapshots.json` / `t24h-snapshots.csv` / `t24h-snapshots.md`.
Even when `mainnet-launch-operation-check` detects a No-Go, the evidence file is retained and the wrapper also exits non-zero.

```bash
cd contracts
pnpm mainnet-launch-24h-snapshot \
  --rpc-url "$MAINNET_RPC_URL" \
  --manifest deployment-manifest.json \
  --config /path/to/mainnet-launch-operation.config.json \
  --out /path/to/evidence-dir/t24h \
  --label t00
```

Align `--label` with the operational time of the launch window, such as `t00`, `t01h`, `t06h`, `t12h`, `t24h`.
When unspecified, a UTC timestamp is used. Even when running via scheduler / cron, do not include the raw RPC URL in the output;
leave the redacted `rpcUrl` of `launch-operation-evidence.json` and the provider label in the evidence bundle.

On an anomaly, classify whether the cause is one of deploy / config / market depth / oracle / bot / liquidity, and as needed execute `pauseDeposit`, `pauseAllocation`, dToken cap reduction, liquidity add / remove, SP top-up, or public communication.

---

## 9. Evidence Template

### 9.1 Execution command

Freeze the launch target / threshold as a JSON config, and evidence it with the current manifest and direct reads against the mainnet RPC.

Evidence hygiene:

- Pass the operator environment's `MAINNET_RPC_URL` to `--rpc-url`, but do not leave the raw URL in publicly shared evidence.
- The `rpcUrl` output of `mainnet-launch-operation-check` must be a value with the provider key / path leaf / query / hash redacted.
- Leave provider identification in the liquidator config's `rpcLabel` or the operational notes of the evidence bundle; do not paste API keys or private endpoints.
- Before packaging, confirm that the JSON config, liquidator dry-run evidence, and manual notes do not duplicate the `.env` or raw RPC URL.
- Placeholders such as `TBD` / `TODO` / generic owner labels / a zero gas wallet fail the check. Always replace the example config with concrete owner / evidence path / address.

```bash
cd contracts
cp utils/mainnet-launch-operation.config.example.json /path/to/mainnet-launch-operation.config.json
# Update the owner, SP target, liquidity, and liquidator evidence in the config to real values before running.
pnpm mainnet-launch-operation-check \
  --rpc-url "$MAINNET_RPC_URL" \
  --manifest deployment-manifest.json \
  --config /path/to/mainnet-launch-operation.config.json \
  --out /path/to/evidence-dir/launch-operation
```

When incorporating into `mainnet-fork-evidence`, pass the same config via `DF_LAUNCH_OPERATION_CONFIG`.

```bash
DF_LAUNCH_OPERATION_CONFIG=/path/to/mainnet-launch-operation.config.json \
pnpm -C contracts --silent mainnet-fork-evidence \
  --out /path/to/evidence-dir
```

Output:

- `launch-operation-evidence.json`
- `launch-operation-evidence.md`
- `07-launch-operation-check.log` (when via `mainnet-fork-evidence`)

This check does not decide the business target. State the per-branch SP target, planned debt denominator, bootstrap JPYdf source / split, LP amount, slippage target, and owner explicitly in the config, and reconcile them against direct mainnet reads and the current manifest. SP coverage uses actual debt when it is nonzero and `plannedDebtJpydf` only when debt is zero; the planned value is an operational launch denominator, not an on-chain debt ceiling. The bootstrap source check reconciles dUSDC (75% LTV, JPY 69.205M mint) and dwstETH (65% LTV, JPY 4.70M mint), SP seed of JPYdf 7.955M for dUSDC and JPYdf 15.95M for dwstETH, and the JPYdf 50M side of the JPYdf/USDC pool. For liquidity it reads pool initialization / liquidity through StateView, samples sell/buy slippage through the v4 Quoter, and records ERC-20 and Permit2 approval cleanup.

The liquidation operator's dry-run evidence is output separately from the bot config, and
the local JSON path that the checker can read is recorded in the `liquidator.dryRunEvidence` of `mainnet-launch-operation-check`.

```bash
cargo run --manifest-path bots/liquidator/Cargo.toml -- \
  --config bots/liquidator/config.mainnet.toml \
  scan-once \
  --json \
  --out /path/to/evidence-dir/liquidator-scan-evidence.json
```

The output JSON includes the config hash, enabled branches, `generatedAtBlock`, top-level `rpcQuorum`, per-branch SP offset capacity, top candidate, planned batch, gas estimate, stressed gas cost, execution decision, and `profitEvidence.receipt`. The planned batch's `profitEvidence.status = "unsupported"` indicates that the evidence records that the current bot does not implement profit-seeking collateral disposal / inventory / market depth / relay. `profitEvidence.liquidatorGasCompensation` computes only the Core WETH gas compensation and the collateral gas compensation for the SP offset portion, not full profit. `profitEvidence.rpcQuorum` is partial evidence of provider health / block lag, and does not mean that scanner routing, provider voting, or price-source quorum is implemented. `profitEvidence.receipt` is evidence of the receipt timeout and outcome classification set, and does not mean that a persistent receipt ledger, replacement / dropped tx tracking, or PnL accounting is implemented. At the launch gate, confirm not only that "the scan is readable" but also that this evidence matches the bot config derived from the current manifest, and is within `liquidator.maxDryRunEvidenceAgeBlocks` of the current RPC block. `mainnet-launch-operation-check` parses `dryRunEvidence` and gates the chain id, `configHash`, `generatedAtBlock` freshness, RPC quorum, enabled branches, scanned branches, per-branch SP offset capacity / candidate count, the planned batch array, and the execution enabled / dry-run flag.
To treat Black Thursday-type market stress as a launch blocker, the checker additionally confirms the config↔bot evidence match of `maxGasCostWei` / `maxLossWeiPerTx` / `gasCostStressMultiplierBps` / `minSpOffsetCoverageBps` / `rpcQuorumRequired` / `rpcMaxBlockLag` / `receiptTimeoutSecs`, the per-branch SP deposit / SP offset capacity / SP-covered candidate count, and the planned batch's gas / gasPrice / baseFeePerGas / priorityFeePerGas / maxFeePerGas / gasCost / stressedGasCost / SP offset coverage / decision / receipt classification. For a batch below the SP coverage threshold or exceeding the stressed gas cap, if the `skipReason` also does not match the policy, it is No-Go.

### 9.2 Template

```text
Launch operation evidence:

Launch owner:
Risk owner:
Finance / accounting owner:
Ops owner:
Launch window:

SP seed:
| Branch | Target SP JPYdf | Planned debt JPYdf | Min coverage bps | Seed source | Seed owner | Tx / evidence |
| --- | ---: | ---: | ---: | --- | --- | --- |

JPYdf/USDC liquidity:
PoolManager:
Pool key:
LP owner:
Initial USDC raw amount:
Initial USDC JPY notional:
Initial JPYdf:
Funding source:
Sample sell size:
Expected slippage:
Allowance cleanup evidence:

Bootstrap JPYdf source:
Source type:
Branch:
Borrower owner:
Accounting owner:
Collateral:
Collateral value JPY:
Debt:
Max LTV bps:
SP seed split:
Liquidity JPYdf:
Liquidity USDC JPY notional:
ICR:
Interest rate:
Unwind plan:

Redemption monitoring:
Command / dashboard:
JPYdf price:
Redemption fee:
Base rate:
Routing sample:
Owner:

Depeg incident response:
Liquidity add owner:
SP top-up owner:
Pause / cap signer:
Stablecoin depeg monitor:
Public communication owner:
Decision log location:

Liquidation operator:
Bot config hash:
Enabled branches:
Mode:
Gas wallet:
Max gas cost wei:
Max loss wei per tx:
Gas cost stress multiplier bps:
Minimum SP offset coverage bps:
Max dry-run evidence age blocks:
High gas escalation owner:
RPC label:
Dry-run output:
SP offset capacity:
Manual JIT / top-up owner:
JIT funding source:
SP shortfall decision owner:
Redistribution decision owner:
Collateral disposal owner:
Failed receipt escalation owner:

Ops monitoring:
Dashboard / script:
Branch health:
SP coverage:
Oracle freshness:
External depeg monitor:
Bridge dormant evidence:
Liquidation scan:
Redemption routing:
Liquidity depth:
Incident owners reachable:

Participant readiness:
Borrower UI evidence:
Earn / SP UI evidence:
Public stats schema / source block:
Liquidator operator evidence:
Day-2 features hidden / disabled:
Exception log:

T+24h watch plan:
Snapshot cadence:
Escalation owner:
Pause / cap freeze signer availability:
Communication owner:
```
