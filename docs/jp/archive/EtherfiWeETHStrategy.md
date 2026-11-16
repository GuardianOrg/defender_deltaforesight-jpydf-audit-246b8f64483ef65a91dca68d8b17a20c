# 🟡 EtherfiWeETHStrategy 要件定義

> **Status: Archived / Out of Day-1 scope**
>
> `EtherfiWeETHStrategy` / `WeETHWithdrawAdapter` は **アーカイブ済み**。branch 0 の Vault underlying が WETH から wstETH に移行したため、
> 本コントラクトの underlying は構造的に WETH であり（`initialize` が `IWETH _weth` を受け取り、deposit
> 経路は WETH を native ETH へ unwrap する）、in-contract の `require(underlying == WETH)` は存在しない。
> 非 WETH underlying の拒否は deploy selector 側にあり、strategy kind / venue struct / helper / env key
> とともに PR #1424 で削除済みである。branch 0 の underlying も WETH → wstETH へ移行したため、
> WETH underlying を供給できる branch は存在しない。source は
> `contracts/src/Strategies/archive/`、test は `contracts/test/archive/` に無改変で保存され、
> いずれも compile / test は継続して通る。
>
> 本 surface は **2026-08-05 完了の外部監査（監査対象 identity `0c7766e0`）の対象に含まれていた**。
> その監査結果を破棄しないために保存するが、本コミット以降は **ACTIVE な監査スコープ外**である。
> [Contract-Audit-Scope-And-nSLOC](../engineering/guides/Contract-Audit-Scope-And-nSLOC.md) 3.5 節を参照。
>
> 本書は履歴資料であり、実装・監査・受け入れ基準の正本ではない。現行の venue 採用状況は
> [Strategy-Selection-Policy](../protocol/operations/policies/Strategy-Selection-Policy.md)、
> Strategy 共通アーキテクチャは
> [Strategy](../protocol/product/spec/strategies/Strategy.md) を正本とする。`EFWEETH-*` ID は履歴保持の
> ため残すが、再利用してはならず、active な監査スコープとして参照してはならない。再有効化には
> `DeployLiquity2` strategy selector への再登録と、新規の activation package（venue evidence /
> risk sign-off / audit-scope 変更）が必要である。

> ⚠️ **Day-1 deploy surface から退役済み。** WETH → wstETH の branch swap（branch 0 = dwstETH・Day-1 Strategy set は aave のみ）に伴い staking-venue 系 Strategy kind は廃止され、`EtherfiWeETHStrategy` / `WeETHWithdrawAdapter` は deploy / register / allocation しない。source / test は削除せず、監査済み成果物として archive へ退避する（source は `contracts/src/Strategies/archive/`、spec は `documents/{en,jp}/archive/`。identity `0c7766e0` で監査済み）。active な Day-1 scope からは外れるが参照可能な状態を保つ。退避そのものは別の retirement 変更で実施する。将来の採用は新規提案として activation gate と監査を要する。

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Archived / Out of Day-1 scope（履歴資料。`0c7766e0` で監査済み） |
| Owner | DeltaForesight |
| 対象コントラクト | `contracts/src/Strategies/archive/EtherfiWeETHStrategy.sol`（`AsyncRequestStrategy` / `BaseStrategy` を継承）/ `contracts/src/Strategies/archive/WeETHWithdrawAdapter.sol` |
| 関連ドキュメント | [Strategy](../protocol/product/spec/strategies/Strategy.md) / [LidoStrategy](LidoStrategy.md) / [CollateralVault](../protocol/product/spec/CollateralVault.md) / [Deployment Configuration Spec](../engineering/guides/Deployment-Configuration-Spec.md) |

本書は `EtherfiWeETHStrategy` の Ether.fi 固有要件を規定する。Strategy 共通の
push model、Vault 連携、`principal`、`sendToVault`、`sendProfitToVault`、
`writeoffPrincipal`、reward sweep、UUPS 権限、async request / idle Underlying 共通会計は
[Strategy](../protocol/product/spec/strategies/Strategy.md) を正本とする。

---

## 1. 目的・スコープ

`EtherfiWeETHStrategy` は対象 branch の Vault underlying を **WETH のまま**保ち、
Vault から配分された WETH を Ether.fi に deposit し、eETH を weETH に wrap して保有する
async Strategy である。

- `underlying()`: WETH
- position: weETH
- 中間 token: eETH
- async request: DeltaForesight `WeETHWithdrawAdapter.requestWithdraw`（weETH -> eETH unwrap 後、Ether.fi native `LiquidityPool.requestWithdraw` を呼ぶ first-party adapter）
- pending position: Ether.fi `WithdrawRequestNFT`
- 回収時の最終 asset: ETH claim 後に WETH wrap

`sendToVault` / `sendProfitToVault` が同期的に返せるのは、claim 済みで Strategy が
自己追跡している idle WETH だけである。pending requestId、`pendingWithdrawAmount`、
`pendingWithdrawalValuationBps`、claim 済み自己 idle WETH の共通会計は `AsyncRequestStrategy` に集約し、weETH の unstake request と
NFT claim は Strategy 固有関数に閉じ込める。Vault / Liquity core には async 分岐を追加しない。

---

## 2. 採用条件

この Strategy は WETH underlying の branch にだけ登録する。

mainnet 採用前に以下を freeze する。

| 項目 | env key |
| --- | --- |
| Strategy kind | `DF_STRATEGY_KIND_i=etherfi-weeth` |
| Ether.fi LiquidityPool | `DF_STRATEGY_ETHERFI_LIQUIDITY_POOL_i` |
| eETH token | `DF_STRATEGY_ETHERFI_EETH_i` |
| weETH token | `DF_STRATEGY_ETHERFI_WEETH_i` |
| DeltaForesight WeETHWithdrawAdapter | `DF_STRATEGY_ETHERFI_WITHDRAW_ADAPTER_i` |
| WithdrawRequestNFT | `DF_STRATEGY_ETHERFI_WITHDRAW_REQUEST_NFT_i` |
| referral | `DF_STRATEGY_ETHERFI_REFERRAL_i`（任意） |

Vault は複数 Strategy を登録できるため、WETH underlying branch で Aave 50% / Etherfi 50% のような
weight 配分は on-chain 仕様上可能であり、`DeployLiquity2` も `DF_STRATEGY_COUNT_i`
配列形式で初期登録できる。例: WETH underlying の branch（index `i`）を Aave 50% / Etherfi 50% にするなら、
`DF_STRATEGY_COUNT_i=2`、`DF_STRATEGY_KIND_i_0=aave`、
`DF_STRATEGY_WEIGHT_BPS_i_0=5000`、`DF_STRATEGY_KIND_i_1=etherfi-weeth`、
`DF_STRATEGY_WEIGHT_BPS_i_1=5000` とし、Etherfi 固有 env は
`DF_STRATEGY_ETHERFI_*_0_1` に設定する。governance handover helper は Vault 登録済み
Strategy を全件走査するため、secondary Strategy も owner / upgrader handover 対象になる。

---

## 3. 実装仕様

### 3.1 初期化

`initialize(vault, weth, owner, upgrader, liquidityPool, eETH, weETH, withdrawAdapter, withdrawRequestNFT, referral)`
はすべての外部 address が非ゼロであることを検証する。加えて Ether.fi 公式 contract が露出する
getter を使い、以下の venue graph が一致しない場合は初期化を拒否する。

- `weETH.eETH() == eETH`
- `weETH.liquidityPool() == liquidityPool`
- `withdrawRequestNFT.eETH() == eETH`
- `withdrawRequestNFT.liquidityPool() == liquidityPool`
- `liquidityPool.withdrawRequestNFT() == withdrawRequestNFT`
- `withdrawAdapter.dfWeETHWithdrawAdapterId() == DF_WEETH_WITHDRAW_ADAPTER_ID`
- `withdrawAdapter.liquidityPool() == liquidityPool`
- `withdrawAdapter.eETH() == eETH`
- `withdrawAdapter.weETH() == weETH`
- `withdrawAdapter.withdrawRequestNFT() == withdrawRequestNFT`

`WeETHWithdrawAdapter` は Ether.fi 公式 contract ではなく、DeltaForesight が実装する薄い
first-party adapter である。Ether.fi 側にも同名 helper が存在し得るため、Strategy は ABI 互換だけでは
受け入れず、DF 固有 marker `dfWeETHWithdrawAdapterId()` が
`DF_WEETH_WITHDRAW_ADAPTER_ID` を返すことを approve 前に検証する。adapter address は env freeze と
deploy review で固定し、request 時は weETH 実減少額、NFT request data、claim 実受領 ETH で検証する。
adapter 自身も constructor で
`weETH` / `WithdrawRequestNFT` / `liquidityPool.withdrawRequestNFT()` が同一の設定済み
`eETH` / `liquidityPool` / `withdrawRequestNFT` graph を参照していることを検証する。

初期化後、以下の allowance を設定する。

- eETH -> weETH: max approve
- weETH -> WeETHWithdrawAdapter: max approve
- WETH -> Vault: `BaseStrategy` が `receiveFromStrategy` 用に max approve

投資先 address の setter は持たない。変更する場合は Strategy を作り直し、Vault の
whitelist / addStrategy / updateStrategy / removeStrategy で入れ替える。接続先更新の共通方針は
[Strategy](../protocol/product/spec/strategies/Strategy.md#24-外部接続先-address-の更新方針) を正本とする。

### 3.2 Deposit

`_doDeposit(amount)` は以下を実行する。

1. WETH を ETH に unwrap
2. `liquidityPool.deposit{value: amount}(referral)` で eETH を受領
3. 受領した eETH を `weETH.wrap(eETHReceived)` で weETH 化
4. Strategy 自身が mint した weETH だけを `_ownWeETH` に加算

第三者が weETH / eETH / WETH を直接送っても通常 valuation には含めない。

### 3.3 WeETHWithdrawAdapter

`WeETHWithdrawAdapter.requestWithdraw(weETHAmount, recipient)` は Strategy から承認済み weETH を受け取り、
以下を実行する。

1. caller から adapter へ `weETHAmount` の weETH を `transferFrom` し、実受領額が引数と一致することを検証する。
2. 受領した weETH を `weETH.unwrap(weETHAmount)` で eETH に戻し、adapter の eETH 実増分が unwrap 戻り値と一致することを検証する。
3. unwrap 後の adapter weETH 残高が request 前 baseline に戻っていることを検証する。
4. unwrap した実 eETH 額だけを Ether.fi native `LiquidityPool.requestWithdraw(recipient, eETHAmount)` に渡す。
5. request 後の adapter eETH 残高が request 前 baseline に戻っていることを検証する。
6. 返却された requestId の `WithdrawRequestNFT.ownerOf(requestId)` が `recipient` であることを検証する。

adapter は immutable 設定・admin なし・upgrade なしとし、rescue / sweep / owner 関数を持たない。直接送付された
weETH / eETH / ETH は Strategy valuation に含めず、通常 request の入力にも混ぜない。adapter は
read-only identity marker `dfWeETHWithdrawAdapterId()` を公開し、Strategy はこの marker が欠けた
ABI 互換 adapter を初期化時に拒否する。

### 3.4 Async withdraw

`requestEtherfiWithdrawal(eETHAmount)` は Vault の `ALLOCATOR_ROLE` だけが呼べる。

- 要求額は `_stakedUnderlyingValue()` 以下でなければならない。
- 既存 pending request 数 + 新規 request 1 件が `MAX_ASYNC_PENDING_REQUESTS`（128）以下でなければならない。
- eETH amount を `weETH.getWeETHByeETH` で weETH amount に変換する。
- 非ゼロ eETH amount が weETH の最小単位未満で 0 weETH に切り捨てられる場合は、1 wei
  weETH に切り上げて request する。これにより dust weETH を永久に残さず、pending value は
  後続の NFT request data の実 net eETH で記録する。
- `withdrawAdapter.requestWithdraw(weETHAmount, address(this))` を呼び、WithdrawRequestNFT を
  Strategy が受け取る。
- 返却された requestId は、`withdrawRequestNFT.ownerOf(requestId) == address(this)` であることを
  検証してから pending 会計へ入れる。
- NFT の `getRequest(requestId)` から `amountOfEEth - feeGwei * 1 gwei` を pending value として
  `pendingWithdrawAmount` と requestId map に記録する。
- spent weETH は `_ownWeETH` から減算する。

Strategy は `IERC721Receiver` を実装し、`withdrawRequestNFT` からの safe mint だけを受け付ける。

### 3.5 Claim

`claimEtherfiWithdrawals(requestIds)` は permissionless である。

- requestId は `AsyncRequestStrategy` が pending として追跡しているものだけを受け付ける。
- 未 claim request 総数は `MAX_ASYNC_PENDING_REQUESTS`（128）で上限管理し、ALLOCATOR 誤作動や鍵侵害時の storage bloat / UI 取得不能化を防ぐ。
- 1 tx の claim batch は `MAX_ASYNC_REQUESTS_PER_CLAIM`（32）以下に制限する。pending request が 32 件を超える場合、keeper / UI は requestIds を分割して複数 tx で claim する。
- claim 前に共通 pending map から削除し、`pendingWithdrawAmount` を減らす。
- `withdrawRequestNFT.claimWithdraw(requestId)` で ETH を受領する。
- 受領 ETH を WETH に wrap し、`_ownIdleUnderlying` に加算する。
- claim 前から Strategy に存在した raw ETH は claim delta に含めない。直接送金または force-send された
  raw ETH は `_ownIdleUnderlying` / `realizedYield()` / `estimatedTotalUnderlying()` に混入させない。

finalized 前の claim は Ether.fi 側で revert する。Ether.fi の claimable amount は request 時点の
`amountOfEEth` だけでなく、claim 時点の share value と fee にも依存する。claim 後に実受領額が
pending value を下回る場合、その差は valuation から消え、必要に応じて incident / writeoff 対応する。
実受領額が pending value を上回る場合、その差は `realizedYield()` として現れ、
`sendProfitToVault()` で principal を減らさず Vault buffer へ回収できる。

### 3.6 Synchronous Vault return

`_doWithdraw(amount)` は `min(amount, _ownIdleUnderlying, WETH.balanceOf(this))` だけを返す。
pending request や weETH position を同期的に強制回収しない。

`estimatedTotalUnderlying()` は以下の合計を返す。`pendingWithdrawalValuationBps` は effective
初期値 10000 で、Vault の `WRITEOFF_ROLE` が 0〜10000 に変更できる。下方変更は
`pausedAllocation == true` の incident freeze 後に限り、復元・上方変更は pause 不要。fresh initialize では configured=true で
10000 を保存し、未設定 storage でも getter / valuation は 10000 を返す。pending 部分の bps
計算は切り捨て丸めであり、claim 実額に疑義がある incident 時は claim 前から保守的に valuation を下げられる。

```text
weETH.getEETHByWeETH(min(_ownWeETH, weETH.balanceOf(this)))
+ pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000
+ min(_ownIdleUnderlying, WETH.balanceOf(this))
```

### 3.7 Emergency

`emergencyWithdrawFromEtherfi(maxEETHToRequest)` は Owner only である。

1. claim 済み idle WETH があれば Vault へ push し、Vault 実受領額を returned principal として記帳する。
2. 残る weETH position について、`maxEETHToRequest` まで withdraw request を発行する。

Ether.fi withdrawal は非同期なので、この関数は全額即時回収を保証しない。Lido と同じく、
pending request の finalization と claim は後続 keeper 操作で処理する。

---

## 4. セキュリティ要件

| ID | 要件 |
| --- | --- |
| EFWEETH-SEC-001 | WETH branch 以外に登録しない。deploy selector は WETH underlying を要求する |
| EFWEETH-SEC-002 | weETH donation は valuation / realizedYield を増やしてはならない |
| EFWEETH-SEC-003 | eETH / weETH / WithdrawRequestNFT は protected asset であり `sweepRewardToken` できない |
| EFWEETH-SEC-004 | `onERC721Received` は設定済み `withdrawRequestNFT` からの mint だけを受け付ける |
| EFWEETH-SEC-005 | pending request は requestId map で追跡し、未知 request の claim は拒否する |
| EFWEETH-SEC-006 | `_doWithdraw` は claim 済み idle WETH だけを返し、async position を同期回収したように見せない |
| EFWEETH-SEC-007 | 初期化時に `weETH` / `WithdrawRequestNFT` / `liquidityPool.withdrawRequestNFT()` / `withdrawAdapter` が設定済み `eETH` / `liquidityPool` / `weETH` / `withdrawRequestNFT` graph を参照し、`withdrawAdapter` が DF 固有 identity marker を返すことを検証する |
| EFWEETH-SEC-008 | `withdrawAdapter.requestWithdraw` が返した requestId は Strategy 自身が owner でなければ pending 会計に入れない |
| EFWEETH-SEC-009 | permissionless claim の requestIds 配列は 1 tx 32 件上限とし、巨大 batch による gas DoS / UI 操作ミスを避ける |
| EFWEETH-SEC-010 | pending request の valuation は Vault `WRITEOFF_ROLE` 限定の `pendingWithdrawalValuationBps`（0〜10000）で保守調整できる。下方変更は `pausedAllocation == true` 必須で、1 wei 未満は切り捨てる |
| EFWEETH-SEC-011 | 未 claim async request は総数 128 件上限とし、storage 増大と pending request 取得不能化を防ぐ |
| EFWEETH-SEC-012 | claim 前から Strategy に存在する raw ETH は claim delta / idle WETH / yield / valuation に混入させない |
| EFWEETH-SEC-013 | 非ゼロ eETH request が 0 weETH に floor される場合は 1 wei weETH に切り上げ、pending には NFT request data の実 net eETH を記録する |
| EFWEETH-SEC-014 | `WeETHWithdrawAdapter` は DeltaForesight first-party adapter として audit scope に含め、DF 固有 identity marker、immutable venue graph、LiquidityPool reverse binding、weETH / eETH balance-delta と residual balance、NFT owner を検証し、admin / upgrade / rescue surface を持たない |

---

## 5. Verification

`contracts/test/archive/EtherfiWeETHStrategy.t.sol` が以下を検証する。

- allocate で WETH が eETH / weETH position になり、WETH 建てで評価される
- request -> pending -> finalized claim -> WETH wrap -> `sendToVault` の流れ
- weETH 換算で 0 になる極小 eETH request は 1 wei weETH に切り上げ、staked + pending valuation の整合を維持する
- `WeETHWithdrawAdapter` が weETH を eETH に unwrap し、Ether.fi native withdrawal request を作成し、adapter に weETH / eETH を残さない
- `WeETHWithdrawAdapter` が venue graph / LiquidityPool reverse binding 不一致、zero request、residual weETH / eETH を拒否する
- claim 前の `sendToVault` は 0 を返し、async liquidity を偽装しない
- claim 実受領 ETH が pending value を下回る場合、実受領額だけを idle WETH / valuation に反映する
- claim 実受領 ETH が pending value を上回る場合、差額を `sendProfitToVault` で yield として回収できる
- pending valuation bps の初期値 10000、端数切り捨て、0 bps、claim 後の実額反映
- `weETH` / `WithdrawRequestNFT` / `liquidityPool.withdrawRequestNFT()` / `withdrawAdapter` の venue graph 不一致、または DF identity marker を公開しない ABI 互換 adapter で初期化が revert する
- requestId owner が Strategy でない場合は revert し、phantom pending を作らない
- claim batch 上限超過が pending map に触れる前に revert する
- weETH donation が valuation を増やさない
- raw ETH donation が claim delta / idle WETH / yield / valuation を増やさない
- eETH / weETH / WithdrawRequestNFT sweep が拒否される
- WETH Vault に Aave Strategy と Etherfi Strategy を 5000 / 5000 weight で登録し、allocate が 50/50 に分かれる
