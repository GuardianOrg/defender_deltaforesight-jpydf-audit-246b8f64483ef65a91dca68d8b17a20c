# Mainnet Launch Operation Gate

| 項目 | 内容 |
| --- | --- |
| Status | Active |
| 役割 | market open の判定、固有 No-Go、実行順序、launch operation evidence schema |
| Product requirement | [`Mainnet-Launch-Product-Decision-Record.md`](../decisions/Mainnet-Launch-Product-Decision-Record.md) |
| 会社資金 | [`Day1-Self-BS-Launch-Commitment.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Launch-Commitment.md) |
| 算定根拠 | [`Day1-Self-BS-Initial-Liquidity-Plan.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Initial-Liquidity-Plan.md) |
| 関連 Gate | deploy の最終確認は [`Mainnet-Initial-Configuration-Checklist.md`](./Mainnet-Initial-Configuration-Checklist.md)、holder は [`Mainnet-Safe-Role-Assignment-Gate.md`](./Mainnet-Safe-Role-Assignment-Gate.md)、参加者表示は [`Mainnet-Participant-Readiness-Gate.md`](./Mainnet-Participant-Readiness-Gate.md) |

本書に secret、未公開 Safe nonce、raw RPC URL、実資金残高の詳細は記録しない。

---

## 0. 原則

Liquity v2 系の launch risk は、contract deploy そのものよりも、初期 market depth と運用監視に寄る。

- SP が薄い branch は liquidation が redistribution に寄りやすく、peg / branch health の説明が難しくなる。
- JPYdf exit liquidity が薄いと、borrower、SP depositor、liquidator の全員が JPYdf を扱いにくい。
- 初期 JPYdf を LP / SP seed に使う場合、発行元となる bootstrap Trove のリスクと会計を先に決める必要がある。
- 現行 liquidator は operator maintenance bot であり、JPYdf sourcing、automatic SP top-up、atomic JIT bundle、collateral disposal は含まない。
- subgraph / frontend 表示は launch UX には必要だが、launch safety の一次ソースは current manifest + direct RPC reads とする。
- Borrower / SP depositor / liquidator が必要指標を読めない場合、market を開いても自然参加の期待値を説明できないため、参加者別 readiness を launch evidence に含める。

---

## 1. Gate Stages

| Stage                    | 目的                                                    | Go 条件                                                               |
| ------------------------ | ------------------------------------------------------- | --------------------------------------------------------------------- |
| T-1 deploy readiness     | deploy / handover に入る前の運用計画 freeze             | §2〜§7 の owner、target、資金 bucket、実行順序が承認済み              |
| T-0 activation readiness | handover 後、public launch / liquidity add 前の実行確認 | SP seed / JPYdf liquidity / bot dry-run / ops monitoring / participant readiness の証跡が揃う |
| T+24h watch              | launch 直後の監視                                       | §8 の指標を block lag なしで監視し、incident owner が応答可能         |

T-0 readiness が未達の branch は、public UI / cap / liquidity / campaign のいずれかで exposure を開けない。例外として開ける場合は、risk owner と launch owner の署名付き exception を evidence package に残す。

---

## 2. SP Seed Gate

各 active branch について、初期 Stability Pool seed の目標と最低許容値を freeze する。

| 項目               | 必須内容                                                                                                                                |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| `targetSpJpydf`    | branch ごとの目標 SP deposit。JPYdf 18 decimals で evidence 化                                                                          |
| `plannedDebtJpydf` | branch debt が 0 の場合に coverage 分母として使う計画 debt。JPYdf 18 decimals。追加発行ではなく、launch exposure envelope の記録        |
| `minSpCoverageBps` | （任意）`SP deposits / coverage debt` の advisory check 値。Day-1 は Product Decision Record の絶対 SP requirement を優先し、post-launch の cap ramp 用 advisory は [`Active-Branch-Cap-Ramp-Runbook.md`](../../operations/runbooks/Active-Branch-Cap-Ramp-Runbook.md) で扱う |
| seed source        | bootstrap borrower、treasury-held JPYdf、既存 holder など。資金 owner のコミットメント、実資金 bucket、会計 owner を明記                 |
| seed owner         | SP deposit を実行・維持する Safe / account。会社拠出の場合は Self-B/S Launch Commitment と照合し、private key は書かない                  |
| exit plan          | seed をいつまで維持するか、引き出し条件、引き出し時の代替 coverage                                                                      |

`activeBranches` は public launch / UI / cap / campaign で exposure を開ける branch だけを列挙する。
Day-1 inert branch（cap 0、public exposure なし）は SP coverage gate の対象にしない。
branch debt が 0 のまま exposure を開ける場合は `plannedDebtJpydf` を必須とする。`activeBranches`、
SP target、planned debt は Product Decision Record、会社拠出の seed source / owner / amount は
Self-B/S Launch Commitment と一致することを確認する。

No-Go:

- active branch の SP seed target または minimum coverage が未承認。
- active branch の branch debt が 0 なのに `plannedDebtJpydf` が未承認、0、または evidence から説明できない。
- SP seed 用 JPYdf が LP seed、Treasury 留保、backstop と二重計上されている。
- seed 実行 owner が Safe role assignment package で freeze されていない、または launch 時に操作不能。
- seed 未達の branch を nonzero cap / public UI / campaign で開ける理由が evidence にない。

---

## 3. JPYdf/USDC Exit Liquidity Gate

Day-1 の DEX liquidity は JPYdf/USDC Uniswap v4 だけを対象にする。

| 項目            | 必須内容                                                                                                                                    |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| pool key        | token ordering、fee、tick spacing、hook address、PoolManager。PoolManager / Universal Router / Permit2 address は Uniswap 公式 deployment 情報と再照合し、source を evidence に記録 |
| LP owner        | position owner / manager、accounting owner、allowance cleanup owner                                                                         |
| initial amounts | Product Decision Record の最低 JPY notional / JPYdf / USDC value、資金 owner の commitment、実行時の `initialUsdc` raw token amount、funding source |
| route checks    | sample sell / buy size、expected slippage、deadline、private tx 方針                                                                        |
| exclusions      | Curve、Uniswap v3、Balancer、USDT / USDS / WETH / XAUT direct JPYdf pool が無いこと                                                         |

No-Go:

- JPYdf/USDC pool が未初期化、または LP owner / funding source / allowance cleanup が未承認。
- PoolManager / Universal Router / Permit2 address が Uniswap 公式 deployment 情報と再照合されていない。
- LP owner / funding source / allowance cleanup owner が Safe role assignment package と一致しない。
- JPYdf exit route の sample slippage が未測定。
- Day-1 方針外の direct pool / route を frontend、ops、bot、runbook が前提にしている。

---

## 4. Bootstrap Trove / JPYdf Source Gate

LP seed、SP seed、operator inventory に JPYdf が必要な場合、発行元を freeze する。

| 項目                | 必須内容                                                                                                                                                                                                                                                                                    |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| source type         | bootstrap Trove / market borrow / treasury-held JPYdf / other                                                                                                                                                                                                                               |
| branch              | bootstrap Trove を使う場合の collateral branch                                                                                                                                                                                                                                              |
| borrower owner      | Safe / account、accounting owner                                                                                                                                                                                                                                                            |
| collateral / debt   | collateral amount、debt amount、initial ICR、interest rate、batch manager 利用有無                                                                                                                                                                                                          |
| borrow APR policy   | Product Decision Record の一般 borrower 向け business target / risk-mode range、Self-B/S Launch Commitment の会社 bootstrap anchor・管理レンジ・Trove 構成と、算定根拠に用いた短期 JPY reference yield、DeFi risk premium、target SP APR、target SP coverage、`SP_YIELD_SPLIT`、rate review cadence |
| borrow rate evidence | `pnpm --filter @jpydf/ops check-borrow-rate-policy -- --out <evidence>/borrow-rate-policy.json --pretty` の JSON。これは read-only operator evidence であり、signer、tx submission、自動 rate adjustment を含まない |
| interest-rate dry-run evidence | 任意: `pnpm --filter @jpydf/ops check-interest-rate-management -- --config <watchlist.json> --out-dir <evidence>/interest-rate-management --pretty`。watched Trove の rate 判断材料を出す read-only analyzer であり、calldata generation、signer、tx submission は含まない |
| Trove count / split | Self-B/S Launch Commitment の会社 branch 別構成を `bootstrapSources[]` へ記録し、per-Trove debt / rate / owner / unwind plan と、dwstETH 側 buffer の会計承認を残す。これは redemption 除外・回避保証・復元 SLA ではない |
| structured split    | `bootstrapSources[*].collateralValueJpy`、`maxLtvBps`、`mintedJpydf`、`borrowRateBps`、`branches[*].targetSpJpydf`、`liquidity.initialJpydf`、`liquidity.initialUsdcValueJpy`                                                                                                                    |
| unwind plan         | repay / close 条件、LP / SP seed 解除時の repayment source。[`Product-Unwind-And-Sunset-Runbook.md`](../../operations/runbooks/Product-Unwind-And-Sunset-Runbook.md) に従い、Core 無改修で止められる範囲と止められない範囲を分けて記録する |

No-Go:

- LP / SP seed の JPYdf acquisition path が不明。
- `bootstrapSources[*].mintedJpydf` 合計が `branches[*].targetSpJpydf` 合計 + `liquidity.initialJpydf` と一致しない。
- `liquidityUsdcValueJpy` と liquidity config の `initialUsdcValueJpy` が一致しない、または実行時の `initialUsdc` raw amount が未確定。
- bootstrap Trove の owner、ICR、interest rate、repayment plan が未承認。
- bootstrap borrower owner / repayment owner が Safe role assignment package と一致しない。
- bootstrap Trove の borrow APR が Day-1 方針の逆算式から説明できない、または rate review / adjustment owner が未定。
- `check-borrow-rate-policy` evidence が `ready` でない、または read-only boundary（signer / transactionSubmission / automaticRateAdjustment が false）を示していない。
- 複数 bootstrap Trove を作るのに、launch checker / evidence が per-Trove split と DF 側 risk-reduction buffer 承認を記録できない。
- demo Trove / test data / local-only helper を mainnet seed と混同している。

---

## 5. Redemption Monitoring Gate

Day-1 に自動 redemption bot がない場合でも、operator が redemption health を監視できる状態にする。
大口 dwstETH borrower の third-party redemption risk monitoring は
[`Redemption-Risk-Monitoring-Design.md`](../../../contributors/deltaforesight/operations/Redemption-Risk-Monitoring-Design.md)
を設計（監視モデル・bot アーキ）、
[`Redemption-Risk-Monitoring-Runbook.md`](../../../contributors/deltaforesight/operations/Redemption-Risk-Monitoring-Runbook.md)
を運用境界、
[`Redemption-Risk-Monitoring-Implementation-Plan.md`](../../../engineering/plans/Redemption-Risk-Monitoring-Implementation-Plan.md)
を実装順序、
[`Redemption-Risk-Monitoring-Integration-Guide.md`](../../../engineering/guides/Redemption-Risk-Monitoring-Integration-Guide.md)
を read 仕様として扱う。DF internal read-only bot / sample report は Day-1
in-scope implementation として採用してよいが、A 社への自動 alert 配信、rate
tx、rehedge / buyback / Trove rebuild はこの gate の対象外である。

| 指標                                   | 一次ソース                                        |
| -------------------------------------- | ------------------------------------------------- |
| JPYdf/USDC pool price / depth          | Uniswap v4 pool direct read                       |
| redemption fee / base rate             | CollateralRegistry / RedemptionHelper direct read |
| branch outside debt / unbacked portion | ActivePool / StabilityPool / console direct reads |
| lowest-rate Trove distribution         | SortedTroves / helper direct read                 |
| urgent redemption / shutdown state     | TroveManager / CollateralRegistry direct read     |
| watched Trove debt-in-front / rate     | DebtInFrontHelper / SortedTroves / TroveManager direct read |
| watched Trove impact estimate          | TroveManager / PriceFeed / JPYdf liquidity read   |

No-Go:

- JPYdf price と redemption route を launch 時に監視する owner がいない。
- redemption fee / base rate / branch routing を確認する dry-run がない。
- JPYdf が depeg した場合の liquidity add / SP seed / pause / communication owner が未定。
- A 社 dwstETH exposure を Day-1 に開けるのに、watchlist、manual read 手順、owner /
  backup、evidence template、A 社 comms path が未承認。
- 社内 bot を使う場合に、`DebtInFrontHelper` / `TroveManager` / `SortedTroves`
  read が manifest / generated binding 由来でない、または JSON / Markdown /
  notification payload / Slack delivery の dry-run evidence がない。
- 社内 bot の watchlist / schedule config evidence が無い、または
  `check-redemption-risk-config` が placeholder Trove / external delivery mode /
  missing internal delivery target を blocker として返している。

---

## 6. Liquidation Operator Gate

現行 bot は operator maintenance bot として扱う。profit-seeking keeper network の完成を Day-1 前提にしない。

| 項目                              | 必須内容                                                                                                                                                                                    |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| config source                     | current `deployment-manifest.json` 由来の generated config                                                                                                                                  |
| enabled branches                  | borrowable dwstETH / dUSDC のみ。inert の branch 2–7 は scan / submit 対象外であること                                                                                                                         |
| mode                              | dry-run / protocol-maintenance のどちらで launch するか。`profit-seeking` は collateral disposal / inventory-aware profit model 実装まで Day-2 扱いで No-Go                                  |
| gas wallet / caps                 | public address、funding owner、`maxGasCostWei`、`maxLossWeiPerTx`、`gasCostStressMultiplierBps`、`maxSubmissionsPerCycle`、`submissionCooldownBlocks`、high-gas escalation owner                                                                  |
| RPC                               | chain id check、provider label、`rpcQuorumRequired`、`rpcMaxBlockLag`、`rpcReadTimeoutMs`、fallback 方針                                                                                                         |
| dry-run evidence                  | top candidate、min ICR、SP deposit、SP offset capacity、SP-covered candidate count、top-level `rpcQuorum`、planned batch gas/baseFee/priorityFee/maxFee/gasCost/stressedGasCost/decision、`profitEvidence.status` / `liquidatorGasCompensation` / `gasForecast` / `rpcQuorum` / `receipt`、`generatedAtBlock` と許容 block age |
| thin-SP / redistribution decision | SP が薄い branch で JIT せず redistribution を受ける条件、判断 owner、decision log                                                                                                          |
| manual JIT / top-up               | bot 外で誰が判断・実行するか、JPYdf funding source、SP deposit account、top-up tx 手順                                                                                                      |
| collateral disposal               | 清算で受けた dToken / underlying を誰が評価・退避・処分するか                                                                                                                               |

No-Go:

- current manifest から bot config を生成していない。
- liquidator gas wallet / keeper ops wallet / escalation owner が Safe role assignment package と一致しない。
- dry-run が active branch を scan していない。
- `liquidator.dryRunEvidence` が local JSON として読めない、または chain id / config hash / enabled branches / scanned branches / `generatedAtBlock` freshness / RPC quorum evidence が launch config と一致しない。
- `maxGasCostWei` / `maxLossWeiPerTx` / `gasCostStressMultiplierBps` / `minSpOffsetCoverageBps` / `maxSubmissionsPerCycle` / `submissionCooldownBlocks` / `rpcQuorumRequired` / `rpcMaxBlockLag` / `rpcReadTimeoutMs` / `receiptTimeoutSecs`、high-gas escalation owner、failed receipt escalation owner が未承認。
- dry-run evidence に branch ごとの SP deposit / SP offset capacity / SP-covered candidate count、top-level `rpcQuorum`、planned batch の gas / baseFeePerGas / priorityFeePerGas / maxFeePerGas / gasCost / stressedGasCost / decision / `profitEvidence.status` / `liquidatorGasCompensation` / `gasForecast` / `rpcQuorum` / `receipt` が含まれない、または gas compensation・gas forecast・RPC health・receipt classification だけを full profit として扱っている。
- launch 用 dry-run evidence の `execution.enabled` が true ではない、または policy blocker が `skipReason` として出ていない。
- `liquidator.mode = "profit-seeking"` を Day-1 launch config に入れている。
- thin-SP 時に JIT top-up するか redistribution を受けるかの判断 owner と decision log が無い。
- live mode なのに gas / loss / receipt policy が未承認、または dry-run evidence の caps と launch config が一致しない。
- SP top-up / JIT / collateral disposal が bot に実装済みだと誤認している。

---

## 7. Ops Monitoring Gate

launch window では、少なくとも次の指標を一画面または runbook command で確認できること。

| 領域                    | 指標                                                                                                                    |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| branch health           | TCR、SCR、CCR、MCR、shutdownTime、oracle price / updatedAt、`priceSource == primary`、`jpyFrozenSince == 0`             |
| SP coverage             | branch debt、SP deposits、outside debt、coverage bps、pending SP yield                                                  |
| liquidation             | top candidate、min ICR、candidate count、SP offset capacity、bot block lag                                              |
| redemption              | JPYdf supply、redemption sample amount、fee / base rate、routing rows                                                   |
| liquidity               | JPYdf/USDC price、pool depth、sample slippage、LP owner、ERC20 / Permit2 residual allowance                             |
| dToken / strategy       | cap usage、Vault buffer、backing ratio、strategy exposure、paused flags                                                 |
| external depeg monitors | active collateral の secondary market / wrapper depeg と oracle の比較、monitor source、alert owner |
| peg defense readiness   | `frontend/ops` の `buildPegDefenseReadinessEvidence` で JPYdf/USDC liquidity、redemption fee/base rate、branch SP coverage、Vault/Strategy health、external peg monitor、public-comms alert を read-only evidence として束ねる |
| bridge readiness        | `bridgeMinterCount == 0`、`proposedBridgeMinter == address(0)`、active bridge adapter 不在、bridge admin owner/evidence |
| incidents               | Guardian availability、cap freeze plan、pause tx owner、communication owner                                             |

No-Go:

- branch health、SP coverage、oracle freshness、redemption routing、liquidation scan のいずれかが launch 時に読めない。
- [Mainnet-Participant-Readiness-Gate.md](./Mainnet-Participant-Readiness-Gate.md) の borrower / SP depositor / liquidator No-Go が未解消、または Day-2 未実装項目を実装済みのように表示している。
- active branch の oracle source が `primary` でない、または JPY soft-freeze 中（`jpyFrozenSince != 0`）。
- active USD stable branch の secondary market depeg monitor と oracle 乖離確認の証跡がない。
- active wrapper collateral の market / canonical depeg monitor、閾値、Guardian `pauseDeposit` owner が確認できない。
- Day-1 の `bridgeMinterCount` が 0 でない、`proposedBridgeMinter` が残っている、または active bridge adapter / other-chain issuance が接続されている。
- Day-2 以降の bridge minter registration / canary / public route / cap ramp を同時に進める場合に、[Bridge-Minter-Activation-Gate.md](../../operations/runbooks/Bridge-Minter-Activation-Gate.md) の対応 Stage A/B/C evidence が未承認、または minter 登録だけで frontend / public route、third-party accessible route、cap ramp を開こうとしている。
- BTC wrapper branch を active にする場合、collateral/USD・JPY/USD に加えて WBTC/BTC peg leg の freshness evidence が読めない。
- JPYdf/USDC LP owner の JPYdf / USDC residual allowance が PoolManager、Universal Router、Permit2、または Permit2 内部 Universal Router allowance に残っている。
- ops dashboard / script が stale manifest または legacy snapshot を読んでいる。
- Guardian / Allocator / Writeoff / Timelock の incident owner が launch window に応答不能。

`pegDefenseReadiness.status` は Day-1 read-only monitor の集約結果であり、自動 redemption、
LP 操作、pause、writeoff、public comms 投稿の実行権限ではない。`blocked` / `watch` の場合は
該当 layer の missing source / alert を確認し、Peg Defense Orchestrator (#671) の manual
runbook 側で LP suspend、SP top-up、pause、backstop、writeoff alert、public comms のどれを
人間承認で進めるか判断する。

---

## 8. T+24h Watch

launch 後 24 時間は、以下を定期 snapshot として残す。

- JPYdf/USDC price / depth / sample slippage.
- branch debt、SP deposits、outside debt、coverage bps.
- branch TCR / SCR / CCR proximity.
- oracle freshness and last good price.
- liquidation bot cycles、candidate count、tx submission / failures.
- redemption route sample and fee / base rate.
- Vault buffer / strategy exposure / backing ratio.
- USDC secondary market depeg monitor (wstETH/stETH market health is covered by the oracle freshness checks).
- bridge dormant state: minter count, pending minter, active adapter flag, supply monitor baseline.
- Guardian pause / cap freeze readiness.

標準 snapshot は `mainnet-launch-24h-snapshot` で採取する。この command は `mainnet-launch-operation-check`
を 1 回実行し、snapshot ごとの `launch-operation-evidence.{json,md}` に加えて、24h watch 用の
`t24h-snapshots.json` / `t24h-snapshots.csv` / `t24h-snapshots.md` を更新する。
`mainnet-launch-operation-check` が No-Go を検出した場合でも evidence file は残し、wrapper も non-zero で終了する。

```bash
cd contracts
pnpm mainnet-launch-24h-snapshot \
  --rpc-url "$MAINNET_RPC_URL" \
  --manifest deployment-manifest.json \
  --config /path/to/mainnet-launch-operation.config.json \
  --out /path/to/evidence-dir/t24h \
  --label t00
```

`--label` は `t00`、`t01h`、`t06h`、`t12h`、`t24h` など launch window の運用時刻に合わせる。
未指定時は UTC timestamp が使われる。scheduler / cron で回す場合も raw RPC URL は出力に含めず、
`launch-operation-evidence.json` の redacted `rpcUrl` と provider label を evidence bundle に残す。

異常時は、原因が deploy / config / market depth / oracle / bot / liquidity のどれかを分類し、必要に応じて `pauseDeposit`、`pauseAllocation`、dToken cap reduction、liquidity add / remove、SP top-up、public communication を実行する。

---

## 9. Evidence Template

### 9.1 実行コマンド

launch target / threshold は JSON config として freeze し、current manifest と mainnet RPC against direct reads で証跡化する。

Evidence hygiene:

- `--rpc-url` には operator 環境の `MAINNET_RPC_URL` を渡すが、公開・共有する evidence には raw URL を残さない。
- `mainnet-launch-operation-check` の出力 `rpcUrl` は provider key / path leaf / query / hash を redacted した値でなければならない。
- Provider 識別は liquidator config の `rpcLabel` や evidence bundle の運用メモに残し、API key や private endpoint は貼らない。
- JSON config、liquidator dry-run evidence、手動メモが `.env` や raw RPC URL を複製していないことを package 前に確認する。
- `TBD` / `TODO` / generic owner labels / zero gas wallet などの placeholder は check で fail する。example config は必ず concrete owner / evidence path / address に置換する。

```bash
cd contracts
cp utils/mainnet-launch-operation.config.example.json /path/to/mainnet-launch-operation.config.json
# config 内の owner、SP target、liquidity、liquidator evidence を実値に更新してから実行する。
pnpm mainnet-launch-operation-check \
  --rpc-url "$MAINNET_RPC_URL" \
  --manifest deployment-manifest.json \
  --config /path/to/mainnet-launch-operation.config.json \
  --out /path/to/evidence-dir/launch-operation
```

`mainnet-fork-evidence` に組み込む場合は、同じ config を `DF_LAUNCH_OPERATION_CONFIG` で渡す。

```bash
DF_LAUNCH_OPERATION_CONFIG=/path/to/mainnet-launch-operation.config.json \
pnpm -C contracts --silent mainnet-fork-evidence \
  --out /path/to/evidence-dir
```

出力:

- `launch-operation-evidence.json`
- `launch-operation-evidence.md`
- `07-launch-operation-check.log`（`mainnet-fork-evidence` 経由の場合）

この check は product requirement や会社の資金コミットメントを決めない。Product Decision Record の
launch requirement と Self-B/S Launch Commitment の会社拠出内容を config へ転記し、前者を満たし、
後者の承認範囲内であることを内部合計・on-chain state と照合する。SP coverage は実 debt があれば実値、
0 なら `plannedDebtJpydf` を分母にする。`plannedDebtJpydf` は運用上の coverage 分母であり branch debt
ceiling または外部 borrower の実行可能な借入余力ではない。JPYdf/USDC liquidity、sample slippage、
ERC20 / Permit2 allowance は direct RPC で検査する。

`mainnet-launch-operation-check` の Day-1 active branch 定数（`DAY1_ACTIVE_BRANCH_IDS`）や
example config の `activeBranches` / `bootstrapSources[]` が current topology（borrowable =
branch 0 dwstETH / branch 1 dUSDC、branch 2–7 は inert で bootstrap / SP seed なし）と一致しない場合は、
checker / example config 側を current topology に更新してから実行する。旧 topology
（`activeBranches = [1, 2]` 等、現行 map と異なる config）の結果を
current launch evidence として流用しない。

liquidation operator の dry-run evidence は bot config から別途出力し、
`mainnet-launch-operation-check` の `liquidator.dryRunEvidence` に checker が読める local JSON path を記録する。

```bash
cargo run --manifest-path bots/liquidator/Cargo.toml -- \
  --config bots/liquidator/config.mainnet.toml \
  scan-once \
  --json \
  --out /path/to/evidence-dir/liquidator-scan-evidence.json
```

出力 JSON は config hash、enabled branches、`generatedAtBlock`、top-level `rpcQuorum`、branch ごとの SP offset capacity、top candidate、planned batch、gas estimate、stressed gas cost、execution decision、`profitEvidence.receipt` を含む。planned batch の `profitEvidence.status = "unsupported"` は、現行 bot が profit-seeking の担保処分・inventory・market depth・relay を未実装として証跡化していることを示す。`profitEvidence.liquidatorGasCompensation` は Core の WETH gas compensation と SP offset 部分の collateral gas compensation だけを計算し、full profit ではない。`profitEvidence.rpcQuorum` は provider health / block lag の partial evidence であり、scanner routing、provider voting、price-source quorum の実装済みを意味しない。`profitEvidence.receipt` は receipt timeout と outcome classification set の証跡であり、dry-run では `not-submitted` のままにする。live submission は JSONL receipt ledger に tx hash assignment、submitted tx の from / nonce metadata、receipt outcome を残すが、replacement / dropped tx tracking、PnL accounting の実装済みを意味しない。launch gate では「scan が読める」だけでなく、この evidence が current manifest 由来の bot config と一致し、現在 RPC block から `liquidator.maxDryRunEvidenceAgeBlocks` 以内であることを確認する。`mainnet-launch-operation-check` は `dryRunEvidence` を parse し、chain id、`configHash`、`generatedAtBlock` freshness、RPC quorum、enabled branches、scanned branches、branch ごとの SP offset capacity / candidate count、planned batch 配列、execution enabled / dry-run flag を gate する。
Black Thursday 型の market stress を launch blocker として扱うため、checker は追加で `maxGasCostWei` / `maxLossWeiPerTx` / `gasCostStressMultiplierBps` / `minSpOffsetCoverageBps` / `maxSubmissionsPerCycle` / `submissionCooldownBlocks` / `rpcQuorumRequired` / `rpcMaxBlockLag` / `rpcReadTimeoutMs` / `receiptTimeoutSecs` の config↔bot evidence 一致、branch ごとの SP deposit / SP offset capacity / SP-covered candidate count、planned batch の gas / gasPrice / baseFeePerGas / priorityFeePerGas / maxFeePerGas / gasCost / stressedGasCost / SP offset coverage / decision / receipt classification を確認する。SP coverage 閾値未満または stressed gas cap 超過の batch では `skipReason` も policy と一致しなければ No-Go とする。

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
Borrow rate policy evidence:
Borrow rate policy status:
Borrow rate policy blockers:
Unwind plan:
Product unwind / sunset runbook:

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
