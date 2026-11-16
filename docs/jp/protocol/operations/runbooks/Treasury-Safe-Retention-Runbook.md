# Treasury Safe Retention Runbook

## 0. Scope

Day-1 では `Treasury.sol` / `SPAdditionalRewardDistributor` / `BorrowReferralRewardDistributor` / `SPDepositReferralRewardDistributor` を実装せず、各 Vault の `treasury` を Protocol retention Safe（A-E signer-block-governed Safe。Foundation は署名鍵を持たない）に設定して運用益を蓄積する。Day-2 で Treasury 実装を導入する場合、`setTreasury` で Protocol retention Safe から Treasury へ切替え、蓄積分を合流する。

本 runbook は Safe 留保期間の会計分類、月次照合、Day-2 切替手順を定める。
B/S 資金を JPYdf/USDC LP、Vault backstop、Strategy 運用上限へどう分類するかは
[`Balance-Sheet-Liquidity-Allocation-Policy.md`](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md)
を参照する。

## 1. Accounting Buckets

Safe 入金は token / source / branch ごとに分類する。

| Bucket | Source | Day-1 treatment |
| --- | --- | --- |
| Vault underlying yield | `CollateralVault.transferYieldToTreasury()` | Underlying 別に Safe 留保。SP 追加分配なし |
| Strategy reward sweep | `BaseStrategy.sweepRewardToken()` | 非 Underlying reward token として Safe 留保。backing には自動算入しない |
| Interest residual JPYdf | `InterestRouterForwarder.route()` | JPYdf として Safe 留保。分配ロジックなし |
| Manual backstop funds | `backstopDeposit()` の原資 | 対象 Vault の Underlying に換金し、Vault に明示入金した分のみ backing 修復扱い |
| Manual LP seed funds | B/S の USDC / JPYdf | JPYdf/USDC v4 position 用に別分類。Vault buffer / backstop / protocol yield と混ぜない |

Day-1 は「蓄積のみ」が仕様。Safe 残高を SP 追加報酬として約束しない。
JPYdf/USDC LP に使う資金は市場 liquidity 用であり、dToken backing 修復として分類しない。

`backstopDeposit` に使う資産は、必ず対象 Vault の `underlying()` である。Safe が保有する JPYdf、dToken、Aave/Merkl 等の reward token は、そのままでは backing 修復にならない。backing repair に充てる場合は、Protocol retention Safe または Foundation 運営資産の個別承認済み手順で対象 Underlying に換金し、`backstopDeposit` の `BackstopDeposited(backstop, declaredAmount, received)` をもって repair 実行額として分類する。Foundation 運営資産を使う場合は、Protocol Treasury 側の判断とは別に Foundation の承認・会計/税務証跡を残す。

## 2. Monthly Reconciliation

1. Export Safe token balances and incoming transfers.
2. Export protocol-originated accounting events with the ops ledger:
   ```bash
   pnpm --filter @jpydf/ops export-treasury-ledger -- \
     --pretty \
     --from-block <period-start-block> \
     --out artifacts/treasury-ledger-YYYY-MM.json
   ```
3. The ledger includes active Vault `YieldTransferredToTreasury`, current and historically registered Strategy `RewardTokenSwept`, `InterestRouterForwarder.Routed`, current retention-address ERC20 balances, tx hash, block, token, amount, and branch/source labels.
4. Reconcile event totals against Safe balance deltas by token.
5. Label each unmatched Safe entry with source, tx hash, token, amount, and intended Day-2 handling.
6. Record any manual transfers separately. Manual top-ups must not be mixed with protocol yield unless governance explicitly classifies them.
7. For any manual backstop repair, record the target Vault, target Underlying address/symbol/decimals, source token sold or transferred, conversion tx if any, `backstopDeposit` tx, declared amount, and received amount. JPYdf-denominated Safe balance must not be counted as repaired backing until the target Vault receives Underlying.

### 2.1 Ops Ledger Parameters

- `TREASURY_LEDGER_RPC_URL` (fallback: `OPS_RPC_URL`, generated deployment RPC): RPC endpoint.
- `TREASURY_LEDGER_EXPECTED_CHAIN_ID` (default: generated deployment chainId): RPC chain guard. Mismatch fails.
- `TREASURY_LEDGER_FROM_BLOCK` / `--from-block`: first block included in the event scan.
- `TREASURY_LEDGER_LOG_CHUNK_BLOCKS` / `--log-chunk-blocks`: `eth_getLogs` range size. Default is 250,000 blocks.
- `TREASURY_LEDGER_OUTPUT` / `--out`: output file. Writes atomically when set.
- `TREASURY_LEDGER_PRETTY=1` / `--pretty`: human-readable JSON.

The script fails if the deployment is not using a single `InterestRouterForwarder`, if the Forwarder `jpydfToken()` does not match the generated JPYdf token, or if active underlying token metadata cannot be read. Reward token `symbol` / `decimals` are optional ERC20 metadata; when unavailable, the ledger preserves exact raw amounts and marks decimal display as `null`.

### 2.2 Launch Evidence

Day-1 launch package には次を記録する。

| Field | Day-1 value |
| --- | --- |
| `accountingRunMode` | `safe-retention` |
| `ledgerRunMode` | `read-only` |
| distribution mode | disabled。Treasury / Distributor から SP / Referral へ分配しない |
| scan scope | mainnet chainId、manifest sha256、`fromBlock`、ledger config / output hash |
| owner / result | Finance / accounting owner、Safe balance reconciliation status、exception |

`accountingRunMode` が未記録、`fromBlock` が protocol-originated event を欠落させる、
または未承認の分配 / manual transfer を Safe retention と混同する場合は No-Go とする。

## 3. Day-2 Treasury Cutover

Before cutover:

1. Deploy and verify `Treasury.sol` / `SPAdditionalRewardDistributor` / `BorrowReferralRewardDistributor` / `SPDepositReferralRewardDistributor` according to their specs.
2. Confirm roles: Timelock holds GOV/admin, Guardian holds immediate fail-safe roles, Treasurer/keeper role is separate.
3. Queue `CollateralVault.setTreasury(newTreasury)` for every active Vault through Timelock.
4. Execute queued `setTreasury` calls.
5. Verify every active Vault `treasury()` equals the new Treasury address.

### 3.1 Governance and Audit Acceptance Gate

`Treasury.sol` / `SPAdditionalRewardDistributor` / `BorrowReferralRewardDistributor` / `SPDepositReferralRewardDistributor` は Day-1 audit scope の未実装 blocker ではない。Day-2 で導入する場合は、実装 PR / audit package / cutover proposal を同じ activation gate として扱い、次を満たすまで `setTreasury(newTreasury)`、Safe 留保資金の移行、SP 追加報酬・Referral claim の有効化を行わない。

- **Audit scope**: `Treasury.sol` / `SPAdditionalRewardDistributor.sol` / `BorrowReferralRewardDistributor.sol` / `SPDepositReferralRewardDistributor.sol` / interfaces / deploy scripts / tests を別 PR で追加し、`Contract-Audit-Scope-And-nSLOC.md` と `contracts/src/README.md` を更新する。Day-1 SOW に後から silently 混ぜない。
- **Admin holder**: mainnet では `DEFAULT_ADMIN_ROLE` / `GOV_ROLE` の holder を共通 Timelock のみにする。deployer / EOA / codeless address が admin として残る状態は cutover 不可。
- **Guardian holder**: `GUARDIAN_ROLE` は Guardian multisig のみ。purpose destination disable / proposal cancel、reward asset disable、`cancelRoot`、`pauseRouting`、`pauseBuyback`、`pauseClaims`、登録 Vault・不足額上限付き `emergencyBackstopDeposit` だけを即時操作にする。Guardian が upgrade、destination add / confirm、share 変更、`unpause...`、任意送金を実行できる場合は reject する。
- **Treasurer holder**: `TREASURER_ROLE` は ALLOCATOR / Guardian / Timelock と別の運用鍵にする。`splitYield`、`executeBuyback`、`forwardRewardToken`、`pauseRouting`、`pauseBuyback`、登録 Vault・不足額上限付き `emergencyBackstopDeposit` に限定し、宛先・比率・root 取消・destination 変更を持たせない。
- **Distributor boundary**: `notifyTreasuryRevenue` は Treasury のみ、`notifyEpoch` は ROOT_POSTER のみ、`claim` は permissionless、`cancelRoot` は challenge window 内の Guardian のみ。`challengeWindow < Timelock delay` でも不正 root を取り消せることを fork / unit で示す。
- **Asymmetric recovery**: `pauseRouting` / `pauseBuyback` / `pauseClaims` は TREASURER / Guardian が即時停止でき、`unpause...` は Timelock のみ。停止中でも `emergencyBackstopDeposit` だけは登録 Vault・不足額上限内で継続できることを確認する。
- **Fixed destination**: Treasury / Distributor に caller 指定の任意 `to` 送金経路を置かない。Treasury の宛先は purpose destination / Foundation operating-asset Safe (`foundationSafe`) / 登録 backstop Vault 固定、Distributor の claim 先は Merkle leaf の account / referrer 固定、route 追加は propose -> delay -> confirm にする。
- **Cutover sequencing**: 上記 role verifier と storage-layout / upgrade test が pass するまで、Vault `setTreasury` の queue、Safe 資金移行、root 投稿、buyback 有効化を開始しない。

After cutover:

1. Transfer classified Safe-held protocol yield to Treasury according to the approved migration proposal.
2. Keep manual top-ups / unrelated Safe assets out of Treasury unless explicitly approved.
3. Run Treasury / Distributor accounting tests and dry-run distribution before enabling any SP additional reward or Referral reward distribution.

## 4. Failure Handling

- If `setTreasury` is only partially executed, pause further Safe migration and finish Vault treasury consistency first.
- If Safe classification is incomplete, do not transfer ambiguous balances to Treasury.
- If Treasury / Distributor distribution logic is not yet audited, leave balances in Safe; Day-1 behavior remains valid.
