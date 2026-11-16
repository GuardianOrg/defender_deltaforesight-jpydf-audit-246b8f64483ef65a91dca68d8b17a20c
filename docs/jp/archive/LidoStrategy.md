# 🟡 LidoStrategy 要件定義

> **Status: Archived / Out of Day-1 scope**
>
> `LidoStrategy` は **アーカイブ済み**。branch 0 の Vault underlying が WETH から wstETH に移行したため、
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
> [Strategy](../protocol/product/spec/strategies/Strategy.md) を正本とする。`LIDO-*` ID は履歴保持の
> ため残すが、再利用してはならず、active な監査スコープとして参照してはならない。再有効化には
> `DeployLiquity2` strategy selector への再登録と、新規の activation package（venue evidence /
> risk sign-off / audit-scope 変更）が必要である。

> ⚠️ **Day-1 deploy surface から退役済み。** WETH → wstETH の branch swap（branch 0 = dwstETH・Day-1 Strategy set は aave のみ）に伴い、`LidoStrategy` は deploy / register / allocation しない。source / test は削除せず、監査済み成果物として archive へ退避する（source は `contracts/src/Strategies/archive/`、spec は `documents/{en,jp}/archive/`。identity `0c7766e0` で監査済み）。active な Day-1 scope からは外れるが参照可能な状態を保つ。退避そのものは別の retirement 変更で実施する。本書は残存実装と退役・非 activation 要件（`LIDO-GOV-001`）を記述するものであり、再開の承認ではない。

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Archived / Out of Day-1 scope（履歴資料。`0c7766e0` で監査済み） |
| Owner | DeltaForesight |
| 対象コントラクト | `contracts/src/Strategies/archive/LidoStrategy.sol`（Lido wstETH 個別 Strategy・`AsyncRequestStrategy` / `BaseStrategy` を継承・UUPS・**非同期引き出し**） |
| 関連ドキュメント | [Strategy](../protocol/product/spec/strategies/Strategy.md)（`IStrategy` / `BaseStrategy` / push モデル・共通権限・共通リスク・**STGY-ERR-002 非同期取り扱い**の正本）/ [CollateralVault](../protocol/product/spec/CollateralVault.md)（whitelist / addStrategy / receiveFromStrategy / 遅延償還 claim / writeoff の呼出側）/ [Product-Overview](../protocol/product/Product-Overview.md)（アーキテクチャ・責務分離）/ [Mainnet Launch Risk Gate](../protocol/launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-004) / [Oracle](../protocol/product/spec/Oracle.md)（WETH underlying branch の想定オラクルは ETH/USD Standard で本選択の影響を受けない。本 Strategy の AUM 評価は wstETH の canonical rate〔`getStETHByWstETH` / `stEthPerToken`〕で行い、Liquity v2 の wstETH/rETH canonical-rate valuation と同族。production `CompositePriceFeed` は sUSDS 用に pruning 済み） |

> 本書は [要件定義ドキュメント標準](../Requirements-Spec-Standard.md)に従う。要件・不変条件・セキュリティ要件には永続 ID（`LIDO-…`）を付し、相互参照は ID で行う。
> **本書のスコープ**: `LidoStrategy` の **Lido 固有の要件**のみを扱う。Strategy 共通事項（`IStrategy` / `BaseStrategy` / `AsyncRequestStrategy` 規約・Vault との結合・共通権限・共通リスク・共通イベント・**非同期プロトコルの取り扱い方針 STGY-ERR-002**）は親ページ [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) を正本とし、本書では名前で参照する。

---

## 1. 目的・スコープ・非責務

`LidoStrategy` は CollateralVault が配分した **WETH** を **Lido に stake（`submit` → `wrap` で wstETH 化）して ETH ステーキング利回りを得る**現行実装（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) の `AsyncRequestStrategy` / `BaseStrategy` を継承する子実装）である。1 インスタンス = WETH underlying branch = Lido ステーキング（保有形は **wstETH**＝非 rebasing）に対応し、**push モデル**で動作する。Lido の引き出しは Withdrawal Queue（unstETH NFT）を介する**非同期**（finalization に概ね 1〜5 日）であり、本 Strategy は[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) の **STGY-ERR-002（非同期な外部プロトコルの取り扱い）** に従って、その非同期性を **Strategy 実装の内部に閉じ込める**。

- **対象 Underlying / 外部プロトコル**: WETH（WETH underlying branch）／ Lido stETH（`submit`）＋ wstETH（`wrap`）＋ Lido Withdrawal Queue（`requestWithdrawalsWstETH` / `claimWithdrawal` / `claimWithdrawals`）。詳細は §3。
- **本書が規定する**: Lido 固有の追加ストレージ（`lido` / `stETH` / `wstETH` / `withdrawalQueue` / `weth` / `referral` / `_ownWstETH`）と、`AsyncRequestStrategy` が共通提供する async accounting（`_ownIdleUnderlying` / `pendingWithdrawAmount` / `pendingWithdrawalValuationBps` / 未 claim requestId 管理）を使う方法／ `initialize`（`upgrader` 引数を含む新シグネチャ・stETH→wstETH および wstETH→Withdrawal Queue の max approve）／ Lido I/F へマッピングする 3 hook（`_doDeposit` = WETH→ETH→`lido.submit`→`wstETH.wrap` / `_doWithdraw` = **claim 済み自己 idle WETH のみ返却** / `_estimatedTotalUnderlying` = 自己 wstETH の canonical rate 換算 ＋ bps 調整後 pending ＋ 自己 idle WETH）／ **非同期ライフサイクルの keeper 関数**（`requestLidoWithdrawal` / `claimLidoWithdrawals`、引き出しは `requestWithdrawalsWstETH`）／ Lido 固有の緊急回収関数 `emergencyWithdrawFromLido`（**非 atomic の限界を明示**）／ `referral` 設定／ wstETH（非 rebasing）・WETH/raw ETH donation・finalization 遅延・slashing 等の Lido 固有リスク。
- **本書が規定しない（非責務・他文書）**:
  - `IStrategy` 共通インターフェース・`BaseStrategy` が提供する `deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / `emergencyWithdraw`（送金先 Vault 固定）/ `sweepRewardToken` / `principal` / `realizedYield` / `estimatedTotalUnderlying` / `underlying` 本体・push モデルの会計と `principal` 管理、および `AsyncRequestStrategy` が提供する requestId / pending / idle Underlying 共通会計・**STGY-ERR-002（非同期は Strategy 内部に閉じる方針）** → [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md)
  - Vault との結合（whitelist / weights / cap / `addStrategy` / `receiveFromStrategy` / **遅延償還 `claim`（VAULT-FR-006）** / 障害耐性）→ [CollateralVault 要件定義](../protocol/product/spec/CollateralVault.md)
  - 各 branch の dToken / Underlying 割当・cap・**`withdrawDelay`（現行値は 3 日）**・buffer の Day-1 値 → [Parameters](../Parameters.md)
  - Day-1 の Strategy 登録・weight / cap 状態 → [Mainnet Deploy Env Freeze Runbook](../protocol/launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md) と生成Manifest
  - 🔵 Liquity コアの担保・清算・Redemption 挙動 → [Liquity-v2-Core-Spec](../protocol/product/spec/Liquity-v2-Core-Spec.md)
  - 運用益の用途別配分（`SYS-RISK-003`）→ [Protocol-Revenue-Allocation-Policy](../protocol/roadmap/policies/Protocol-Revenue-Allocation-Policy.md)
- **責務境界（あえて知らない）**: `LidoStrategy` は「誰の担保として配分されるか」「Vault の buffer / weights / `withdrawDelay` がどう決まるか」を前提とせず、純粋に「受け取った WETH を Lido という 1 つの外部プロトコルにどう stake し、どう（非同期に）取り戻し、いくらの価値があるか」という外部プロトコル I/F の変換層に責任を持つ。Lido の非同期引き出しを Vault の同期会計に**漏らさない**ことが本 Strategy の中心責務である。

---

## 2. 背景・設計方針

`LidoStrategy` は [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) の push モデルと「1 Strategy = 1 Underlying = 1 外部運用先」原則に沿った、**最初の非同期（async）Strategy** の具体実装である。Lido は ETH ステーキングの代表的運用先だが、引き出しに Withdrawal Queue の finalization 待ち（概ね 1〜5 日、混雑時はそれ以上）を伴うため、即時引き出し前提の Aave V3（[AaveV3Strategy 要件定義](../protocol/product/spec/strategies/AaveV3Strategy.md)）とは回収経路が根本的に異なる。

### 2.1 残存 async Strategy の仕様境界

`LidoStrategy` は async 対応を具体化した残存実装である。本書の機能・会計要件は残存 code と履歴 ID を保全するためのものであり、activation package ではない。

### 2.2 push モデルと非同期性の隠蔽（STGY-ERR-002 準拠の再キャスト）

本 Strategy の設計の核心は、**Lido の非同期引き出しを `IStrategy` 表層に漏らさず、Strategy 実装の内部に閉じる**ことである（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) STGY-ERR-002）。

- **`IStrategy` 表層は push モデルのまま**: `deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / view は [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) の `BaseStrategy` / `AsyncRequestStrategy` を継承する。Vault 側は `requestKey` を保持せず、`isAsyncWithdraw` 分岐や `claimWithdraw` / `claimHarvest` 相当の非同期清算経路を持たない（`StrategyConfig = {enabled, weightBps, cap}` のまま）。
- **`_doWithdraw` は「その時点で即時に引き出せる自己資金のみ」を返す**: 本 Strategy の `_doWithdraw` は stETH に直接触れず、**Withdrawal Queue から claim 済みで Strategy 手元にある自己 idle WETH** のみを `min(要求額, min(_ownIdleUnderlying, WETH.balanceOf(this)))` で返す。第三者が直接送った WETH や raw ETH は返却対象にも AUM にも混ぜない。自己 idle WETH が無ければ `0` を返す。要求額に満たない（`0` を含む）ことは**正常系**として扱う（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) STGY-SEC-005）。これにより `sendToVault` は `receiveFromStrategy` 経由の元本返却、`sendProfitToVault` は Vault buffer への yield-only direct transfer として、同期 Strategy と同じ BaseStrategy surface で動作する。
- **非同期ライフサイクルは Strategy 内部の keeper 関数に閉じる**: unstake 要求の発行（`requestLidoWithdrawal`、LIDO-FR-006）→ finalization 待ち → 受領（`claimLidoWithdrawals`、LIDO-FR-007）という複数ステップは、`IStrategy` 表層ではなく本 Strategy 固有の関数として実装し、Strategy 内部状態（`pendingWithdrawAmount` / 未 claim requestId）で管理する。これは Aave V3 が固有の `emergencyWithdrawFromAave` を `IStrategy` 表層の外に持つのと同じ「子 Strategy 固有関数」のパターンである。
- **Vault 側の現行値は Lido 回収を前提にしない**: ユーザーの dToken redeem は、buffer 不足時に Vault の遅延償還（[CollateralVault 要件定義](../protocol/product/spec/CollateralVault.md) VAULT-FR-006、`WithdrawRequest` / `claim`）に接続する。ただし現行の `withdrawDelay = 3 日` / `bufferTargetBps = 3.33%`（[Parameters](../Parameters.md)）は Lido の finalization 遅延を吸収する設定ではない。Day-1 は [Mainnet Deploy Env Freeze Runbook](../protocol/launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md) が全 branch を本 Strategy 未登録でfreezeし、生成Manifestで照合する。Lido のために Vault / Core へ分岐や旧 17 日設定を戻さない。

> **旧 `deltaforesight/jpydf` の Lido 実装からの差分（再キャストの要点）**: 旧リポジトリの試作 Lido Strategy は、旧 pull 寄りの `IStrategy`（`requestWithdraw` が `bytes32 key` を返し、`claimWithdraw(key)` と `supportsImmediateWithdraw()` を表層に持ち、Vault 登録が `isAsyncWithdraw = true` の 4 引数 `addStrategy`）を前提としていた。現行 jpydf-v2 はこの設計を**構造的に採らない**（STGY-ERR-002）。本書はこれを以下のように再キャストする: ① 非同期 I/F を表層から外し Strategy 内部の keeper 関数へ移す、② `addStrategy(IStrategy, weightBps, cap)` の 3 引数に合わせ Vault に async フラグを渡さない、③ 派生 `initialize` に `upgrader` 引数を追加し push モデルの Vault max approve に揃える。これらは要件であり、揮発する PR/コミット情報は本書に持ち込まない（git・[Retrospective](../engineering/historical-reviews/Retrospective.md) が持つ）。

### 2.3 元本・収益の分離と保守的評価

- **`principal` は `BaseStrategy` が自己管理**: `deposit` で「Vault が送った WETH 額」を加算し、`sendToVault` および `emergencyWithdrawFromLido` の自己 idle push で「Vault が実受領した `sent`」を `min(sent, principal)` 減算する（principal-first）。wstETH の canonical rate 上昇（`getStETHByWstETH` の単調増加＝ステーキング利回り）による増価は `realizedYield() = max(estimatedTotalUnderlying() − principal, 0)` として現れる。**収益（canonical rate 増分）と元本を取り違えない**ことは、`principal` を動かさない `sendProfitToVault` と、`sent` ベースで `principal` を減らす元本回収経路で担保される（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) STGY-FR-002 / STGY-FR-003）。
- **pending principal を AUM に含めるが incident 時は保守割引できる**: Withdrawal Queue に投入済みでまだ claim していない元本（`pendingWithdrawAmount`）は、`principal` には残したまま `pendingWithdrawalValuationBps`（effective 初期値 10000）で `estimatedTotalUnderlying()` に算入する。通常時は unstake 中の元本が AUM から一時的に消えることを防ぎ、claim 実額に疑義がある incident 時は `pausedAllocation == true` の freeze 後に Vault の `WRITEOFF_ROLE` が bps を下げて pending 部分を先に保守評価できる（LIDO-FR-005 / LIDO-INV-005）。
- **donation 耐性（自己 position / 自己 idle の二段追跡）**: wstETH と WETH は ERC-20 として誰でも本 Strategy に transfer でき、raw ETH も `receive()` へ直接送れる。外部からの donation をそのまま AUM にすると `realizedYield()` が水増しされ、`sendProfitToVault` 経由で任意額を protocol yield と誤認する。これを防ぐため、stake 済み分は本 Strategy 自身の `submit`→`wrap` で得た **wstETH（`_ownWstETH`）** のみを追跡し、claim 済み分は Withdrawal Queue claim で受領・wrap した **自己 idle WETH（`_ownIdleUnderlying`）** のみを追跡する。評価は `getStETHByWstETH(min(_ownWstETH, wstETH.balanceOf(this))) + pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000 + min(_ownIdleUnderlying, WETH.balanceOf(this))` とし、直接 stETH / wstETH / WETH / raw ETH donation は AUM に混ぜない（[AaveV3Strategy 要件定義](../protocol/product/spec/strategies/AaveV3Strategy.md) の `_ownScaledBalance` と同じ「自己由来数量だけを評価する」思想。LIDO-SEC-002）。
- **緊急回収の限界を honest に明示**: Aave と異なり、Lido は stake 済み元本を**即時には ETH 化できない**。`emergencyWithdrawFromLido` は「claim 済み自己 idle 分の atomic push ＋ 残 wstETH の unstake 要求発行」までしかできず、stake 済み元本の完全回収は finalization 待ちで本質的に遅延する。本書はこれを誇張せず、緊急時にも即時全回収は保証しないことを明記する（LIDO-FR-008 / LIDO-ERR-004 / LIDO-SEC-003）。

---

## 3. 用語・外部依存・前提

**用語**

| 用語 | 意味 |
| --- | --- |
| Underlying | 当 Strategy が運用する実担保資産。本 Strategy では **WETH** に固定 |
| stETH | Lido のリキッドステーキングトークン。`submit` で ETH を預けて得る。**rebasing**（残高が利回りで増える）。本 Strategy では submit 直後に `wrap` で wstETH に変換し、stETH は wrap / withdraw 経路の**中間トークン**としてのみ扱う（平常時の保有残高は ~0） |
| wstETH | stETH の **非 rebasing** ラッパー（Lido `WstETH`）。`wrap` / `unwrap` で stETH と相互交換。**残高は不変**で、`stEthPerToken` / `getStETHByWstETH`（canonical rate）が単調増加して価値が増える。**1 wstETH = 自己の stETH shares に対応**。本 Strategy の**保有形・AUM 評価の基礎** |
| canonical rate | wstETH→stETH(≈ETH) の換算レート（`getStETHByWstETH(wstETH)` / `stEthPerToken()`）。rebase の影響を受けず、ステーキング利回りで単調増加する。Liquity v2 が wstETH / rETH に用いる `CompositePriceFeed` と同族の評価軸 |
| `_ownWstETH` | この Strategy 自身の `submit`→`wrap` で得た wstETH（= 自己の stETH shares）。第三者 donation を含まない。AUM 評価の基礎（LIDO-FR-005） |
| `_ownIdleUnderlying` | この Strategy 自身の Lido Withdrawal Queue claim で受領し WETH 化した idle Underlying。第三者 WETH donation を含まない。`_doWithdraw` / `emergencyWithdrawFromLido` / AUM 評価の idle 成分の上限 |
| Withdrawal Queue | Lido の引き出しキュー（`WithdrawalQueueERC721`、unstETH NFT）。stETH を預けて requestId を得て、finalization 後に ETH を claim |
| unstETH NFT | 引き出し要求を表す ERC-721。`requestWithdrawalsWstETH` で mint、`claimWithdrawal` / `claimWithdrawals` で焼却し ETH を受領 |
| finalization | Lido oracle が引き出し要求を確定する処理。概ね 1〜5 日（混雑時はそれ以上） |
| `pendingWithdrawAmount` | Withdrawal Queue 投入済みで未 claim の stETH 額の合計（pending principal の管理） |
| `pendingWithdrawalValuationBps` | 未 claim request を評価する bps。effective 初期値 10000、Vault の `WRITEOFF_ROLE` が 0〜10000 に変更でき、下方変更は `pausedAllocation == true` が必須。`pendingWithdrawAmount * bps / 10000` は切り捨て丸め。未設定 storage でも getter / valuation は 10000 を返す |
| `referral` | `lido.submit` に渡すリファラルアドレス（ゼロ可）。Lido のインセンティブ帰着先 |
| vault | この Strategy を登録する対応 CollateralVault（`BaseStrategy` が `initialize` で固定） |
| Owner / Guardian multisig | 当 Strategy の Owner（緊急回収・`setReferral`・ownership 操作の主体） |
| STRATEGY_UPGRADER | 当 Strategy の `upgrader`（UUPS upgrade 承認主体） |
| ALLOCATOR | Vault の `ALLOCATOR_ROLE`。`sendToVault` / `sendProfitToVault`、および本 Strategy の async request keeper（`requestLidoWithdrawal`）を起動する運用ロール |

**外部依存（信頼する外部）**

- **Lido stETH（`ILido` / `IStETH`）** — `submit(referral)`（ETH→stETH）の呼び出し先、かつ `wstETH.wrap` の入力トークン（stETH→wstETH の approve 先）。最小 interface は `sharesOf(account)` / `getPooledEthByShares(sharesAmount)` も公開するが、現行 AUM 評価は wstETH の canonical helper を正とする。stETH のコア会計が健全であることを信頼する。Lido のコンセンサス層 slashing や stETH コントラクト侵害は元本に影響しうる（LIDO-ERR-003 / LIDO-ERR-004）。
- **Lido wstETH（`IWstETH`）** — `wrap(stETH)` / `unwrap(wstETH)` / `getStETHByWstETH(wstETH)` / `getWstETHByStETH(stETH)` / `stEthPerToken()` / `balanceOf` の呼び出し先。**非 rebasing の保有形**であり、AUM 評価（canonical rate）と Withdrawal Queue への wstETH 投入に用いる。stETH と同じく Lido が管理する。
- **Lido Withdrawal Queue（`IWithdrawalQueueERC721`）** — `requestWithdrawalsWstETH(amounts, owner)`（**wstETH を直接投入**し Queue が内部で unwrap）/ `claimWithdrawal(requestId)` / `claimWithdrawals(requestIds, hints)` / `MIN_STETH_WITHDRAWAL_AMOUNT()` / `MAX_STETH_WITHDRAWAL_AMOUNT()` / `getWithdrawalStatus(requestIds)`（finalization / claimed 状態の確認）の呼び出し先。wstETH 要求の MIN/MAX 判定は各要求量の `getStETHByWstETH(amount)`（= stETH 換算）に対して行われる。finalization のタイミングは Lido oracle に依存し、本 Strategy は制御できない。
- **WETH（`IWETH`）** — `deposit()`（ETH→WETH）/ `withdraw(amount)`（WETH→ETH）。Underlying と同一トークン。
- **`BaseStrategy`（親 [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md)）** — `deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / `emergencyWithdraw` / `principal` / `realizedYield` / `estimatedTotalUnderlying` / `underlying` 本体と push モデルの会計を信頼して継承する。
- **OpenZeppelin Contracts (upgradeable)** — `OwnableUpgradeable` / UUPS（`BaseStrategy` 経由）。

**前提**

- 当 Strategy の Underlying は **WETH に固定**で、対応 Vault の Underlying と一致する（Vault の `addStrategy` が `strategy.underlying() == vault.underlying()` を on-chain 検証する。[CollateralVault 要件定義](../protocol/product/spec/CollateralVault.md) `addStrategy`）。
- `lido.submit{value: x}` は概ね 1:1 で ETH 相当の stETH を mint し、続く `wstETH.wrap(stETH)` がその時点の canonical rate で wstETH を mint して戻り値で返す（端数の -1 wei 丸め・wrap の floor 丸めが起こりうる。LIDO-SEC-006）。
- wstETH は **非 rebasing**（残高不変・価値が canonical rate で増える）だが、ERC-20 として誰でも transfer 可能（donation 経路は存在する。LIDO-SEC-002）。
- Withdrawal Queue は 1 要求あたり stETH 換算で `MIN_STETH_WITHDRAWAL_AMOUNT` 以上 `MAX_STETH_WITHDRAWAL_AMOUNT` 以下しか受け付けない（mainnet 既定は最小 100 wei・最大 1000 stETH）。wstETH 投入時は各要求量の `getStETHByWstETH(amount)` がこの範囲に収まる必要があり、大口は複数要求に分割する（LIDO-FR-006）。
- finalization 前の `claimWithdrawal` は Withdrawal Queue が revert する（早期 claim 不可。LIDO-FR-007 / LIDO-ERR-001）。
- 引き出しで受領する ETH は **Lido プロトコルレート**であり、stETH の二次市場価格（DEX デペグ）とは独立する（LIDO-ERR-005）。

---

## 4. アクター・ロール・信頼境界

共通の権限設計（Owner / Upgrader / ALLOCATOR / permissionless の操作別マトリクス・鍵侵害時の被害境界）は [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) を正本とする。Lido 固有の操作のみ以下に示す。

| アクター | Lido 固有の操作 | 信頼境界 |
| --- | --- | --- |
| **Owner（Guardian multisig）** | `initialize`（投資先固定・1 度のみ）/ `emergencyWithdrawFromLido`（claim 済み自己 idle を Vault へ atomic push ＋ 残 wstETH の unstake 要求発行）/ `setReferral` | 緊急操作の即時主体。必ずマルチシグ。`emergencyWithdrawFromLido` は自己 idle 分を Vault 固定宛先へ push し、任意宛先を持たない（LIDO-SEC-003）。ただし stake 済み元本は即時回収できず、直接 WETH/raw ETH donation は Lido principal として扱わない（LIDO-FR-008） |
| **Upgrader（STRATEGY_UPGRADER）** | UUPS アップグレード承認 / `setUpgrader` | ロジック差替の強権限。Owner とは分離。共通方針は [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) を正本とする |
| **ALLOCATOR（Vault ロール）** | `sendToVault` / `sendProfitToVault`（内部 `_doWithdraw` は自己 idle WETH のみ動かす）/ **`requestLidoWithdrawal`（unstake 要求発行）** | 資金は Vault へ push されるのみ・任意宛先不可。`requestLidoWithdrawal` は MIN/MAX 検証と pending 記帳のみで、資金を外部へ出さない（unstETH の owner は Strategy 自身） |
| **WRITEOFF（Vault ロール）** | `setPendingWithdrawalValuationBps` | pending request の valuation を下げられる price-moving 操作。下方変更は `pausedAllocation == true` の incident freeze 後のみ可能。資金は移動しないが backing に効くため、高定足数 GOV multisig の即時ロールに限定する |
| **任意（permissionless）** | view（`estimatedTotalUnderlying` 等）/ `claimLidoWithdrawals`（finalized 要求の受領）/ stETH・wstETH・WETH・raw ETH donation | view は信頼不要。claim は finalized request を Strategy 自身へ回収して WETH 化するだけで任意宛先を持たず、finalized loss を隠れたままにしない。donation は AUM・profit push・Lido 固有 emergency principal return に混入させない（LIDO-SEC-002） |

- **権限分離**: `emergencyWithdrawFromLido` と `setReferral` は `onlyOwner` であり、運用ロール（ALLOCATOR）から発動できない。`requestLidoWithdrawal` は運用 Bot（ALLOCATOR）が日常的に起動するため、資金を外部へ動かさない・宛先を持たない設計にして、運用鍵侵害時の被害を「unstake タイミングの撹乱」に限定する。pending valuation の markdown は Owner / ALLOCATOR ではなく Vault `WRITEOFF_ROLE` のみで、下方変更は Vault `pausedAllocation` 後に限る。`claimLidoWithdrawals` は permissionless とし、finalized request の受領・損益反映を特定 keeper に依存させない（LIDO-SEC-003 / LIDO-SEC-004）。

---

## 5. インターフェース仕様

共通 surface は [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) を正本とし、Lido 固有の関数・hook だけを以下に要約する（非規範）。

| 関数 | 可視性 | 要約 | 規定要件 |
| --- | --- | --- | --- |
| `initialize(address _vault, IWETH _weth, address _owner, address _upgrader, ILido _lido, IWstETH _wstETH, IWithdrawalQueueERC721 _withdrawalQueue, address _referral)` | external (initializer) | BaseStrategy 初期化（`upgrader` 含む）＋投資先固定＋stETH→wstETH・wstETH→Withdrawal Queue を max approve | LIDO-FR-001 |
| `_doDeposit(uint256 _amount)` | internal（`deposit` の hook） | WETH→ETH unwrap → `lido.submit{value}` → stETH → `wstETH.wrap` → wstETH。`_ownWstETH` に wstETH 実残高差分を加算 | LIDO-FR-003 |
| `_doWithdraw(uint256 _amount) → uint256 actual` | internal（`sendToVault` / `sendProfitToVault` の hook） | **claim 済み自己 idle WETH のみ** `min(_amount, min(_ownIdleUnderlying, WETH.balanceOf(this)))` を返し、返却分だけ `_ownIdleUnderlying` を減らす。wstETH / stETH には直接触れない | LIDO-FR-004 |
| `_estimatedTotalUnderlying() → uint256` | internal view（`estimatedTotalUnderlying` の hook） | `getStETHByWstETH(min(_ownWstETH, wstETH.balanceOf(this)))` ＋ `pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000` ＋ `min(_ownIdleUnderlying, WETH.balanceOf(this))` | LIDO-FR-005 |
| `requestLidoWithdrawal(uint256 _stETHAmount) → uint256[] requestIds` | external (ALLOCATOR) | 要求値（stETH 換算）を wstETH に変換し `requestWithdrawalsWstETH` で Withdrawal Queue へ投入（MIN/MAX 分割）。`pendingWithdrawAmount` 加算・requestId 記録・`_ownWstETH` 減算 | LIDO-FR-006 |
| `claimLidoWithdrawals(uint256[] _requestIds)` / `claimLidoWithdrawals(uint256[] _requestIds, uint256[] _hints)` | external (permissionless) | finalized 要求を claim → 受領 ETH → WETH wrap（自己 idle 化）。単一 request は no-hint、複数 request は hint 付き batch。`pendingWithdrawAmount` 減算・`_ownIdleUnderlying` 加算 | LIDO-FR-007 |
| `emergencyWithdrawFromLido()` / `emergencyWithdrawFromLido(uint256 maxStETHToRequest)` | external (onlyOwner) | claim 済み自己 idle を Vault へ atomic push・returned principal 記帳 ＋ 残 wstETH の unstake 要求を発行（**stake 済みは即時回収不可**）。引数付き overload は当該 tx で要求する stETH 額を cap できる。直接 WETH/raw ETH donation は Lido principal として push しない | LIDO-FR-008 |
| `setReferral(address _referral)` | external (onlyOwner) | `lido.submit` のリファラル更新 | LIDO-FR-009 |
| `setPendingWithdrawalValuationBps(uint256 bps)` | external (Vault `WRITEOFF_ROLE`・AsyncRequestStrategy) | pending request の評価 bps を 0〜10000 に更新。下方変更は `pausedAllocation == true` の incident freeze 後に限り、claim 前の pending value を保守割引する | LIDO-FR-005 |
| `ownWstETH() → uint256` | external view | donation を除いた自己 wstETH 追跡量（`_ownWstETH`）を返す | LIDO-FR-005 |
| `pendingRequestCount() → uint256` | external view | 未 claim requestId 配列の長さを返す | LIDO-FR-006 / LIDO-FR-007 |
| `getPendingRequestIds() → uint256[]` | external view | 未 claim requestId のスナップショットを返す | LIDO-FR-006 / LIDO-FR-007 |
| `receive() external payable` | external | WETH unwrap・Withdrawal Queue からの ETH 受領のために必要 | LIDO-FR-003 / LIDO-FR-007 |
| `_isSweepProtectedToken(address) → bool` | internal view (override) | Underlying(WETH) に加え stETH / wstETH / unstETH を sweep 禁止に追加 | LIDO-SEC-007 |

### 5.1 資金・ライフサイクル図（参考）

```text
[配分] allocate（Vault → Strategy）           [stake]
  CollateralVault ──safeTransfer(WETH)──▶ LidoStrategy
                  ──deposit(amount)──────▶   _doDeposit: WETH→ETH→lido.submit→wstETH.wrap → wstETH（_ownWstETH += wstETH 実残高差分）

[非同期回収トリガ]（ALLOCATOR・keeper）
  requestLidoWithdrawal(stETHAmount) ──▶ WithdrawalQueue.requestWithdrawalsWstETH → unstETH NFT
                                          （pendingWithdrawAmount += amount・_ownWstETH -= 投入 wstETH）
        … finalization 待ち（〜1-5 日。現行の 3 日設定で吸収できるとは扱わない）…
  claimLidoWithdrawals(requestIds) ───▶ WithdrawalQueue.claimWithdrawal → ETH → WETH（自己 idle 化・pendingWithdrawAmount -= amount・_ownIdleUnderlying += WETH実増分）

[push]（ALLOCATOR）
  sendToVault(amount) / sendProfitToVault()
        └ _doWithdraw: 自己 idle WETH のみ min(要求, min(_ownIdleUnderlying, WETH残高)) を返す（0 可）
        └ vault.receiveFromStrategy(actual) → Vault buffer（principal は sent ベースで減算）

[ユーザー redeem]（Vault 側・本 Strategy の責務外）
  redeem → buffer 不足 → WithdrawRequest（claimableAt = now + 現行 withdrawDelay 3日）→ 後で claim（VAULT-FR-006）

※ 上記は残存実装のライフサイクル説明であり、deploy / register / allocation の承認ではない。
```

---

## 6. 機能要件（FR）

> `deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / `emergencyWithdraw`（送金先 Vault 固定）/ `sweepRewardToken` 本体は `BaseStrategy` が提供する（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md)）。`LidoStrategy` は `initialize` と 3 hook（`_doDeposit` / `_doWithdraw` / `_estimatedTotalUnderlying`）＋ **非同期 keeper 関数**（`requestLidoWithdrawal` / `claimLidoWithdrawals`）＋ 固有の緊急回収関数 ＋ `setReferral` のみを実装する。

### LIDO-FR-001: initialize（投資先固定・proxy 初期化）

- **Type**: Functional ｜ **Source**: [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) 派生クラスの `initialize` 規約 / Lido submit
- **シグネチャ**: `initialize(address _vault, IWETH _weth, address _owner, address _upgrader, ILido _lido, IWstETH _wstETH, IWithdrawalQueueERC721 _withdrawalQueue, address _referral) external initializer`
- **目的**: UUPS proxy 越しに 1 度だけ初期化し、`BaseStrategy` の標準初期化（`upgrader` 引数を含む）に加えて Lido の投資先（`lido` / `stETH` / `wstETH` / `withdrawalQueue` / `weth`）を固定し、stETH→wstETH（`wrap` 用）と wstETH→Withdrawal Queue（`requestWithdrawalsWstETH` 用）を max approve する。
- **権限**: デプロイ手順（proxy 初期化）の一部。`_owner` に Guardian multisig、`_upgrader` に STRATEGY_UPGRADER（共通 TimelockController）を束縛する。
- **事前条件（Checks）**:
  - `initializer` により 1 度きり（多重初期化は revert）。ロジックコントラクト自体は初期化不能とし、初期化は proxy 経由に限定する
  - `_lido != address(0)` / `_wstETH != address(0)` / `_withdrawalQueue != address(0)`（ゼロなら `ZeroAddress` で revert）
  - `_wstETH.stETH() == address(_lido)`。wstETH が別 stETH/Lido に紐づいている場合は `InvalidWstETHStETH` で revert
  - `_withdrawalQueue.MIN_STETH_WITHDRAWAL_AMOUNT() != 0` かつ `MAX_STETH_WITHDRAWAL_AMOUNT() >= MIN_STETH_WITHDRAWAL_AMOUNT()`。不正な Queue bounds は `InvalidWithdrawalQueueBounds` で revert
  - `_vault` / `_weth`(= Underlying) / `_owner` / `_upgrader` のゼロチェックは `BaseStrategy` の標準初期化が行う
- **動作（Effects）**:
  1. `__BaseStrategy_init(_vault, IERC20(address(_weth)), _owner, _upgrader)` — `BaseStrategy` の標準初期化（Ownable / UUPS・ストレージ保存・ownership 移譲・`upgrader` 保存・**Vault への `underlying.forceApprove(vault, max)`**）。詳細は [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) の `BaseStrategy`
  2. `lido = _lido` / `stETH = IStETH(address(_lido))` / `wstETH = _wstETH` / `withdrawalQueue = _withdrawalQueue` / `weth = _weth`（以後変更不可）
  3. `referral = _referral`（`setReferral` で更新可・LIDO-FR-009）
  4. `IERC20(address(_lido)).forceApprove(address(_wstETH), type(uint256).max)` — `wstETH.wrap` が stETH を引き取れるようにする／ `IERC20(address(_wstETH)).forceApprove(address(_withdrawalQueue), type(uint256).max)` — Withdrawal Queue が `requestWithdrawalsWstETH` で wstETH を引き取れるようにする（いずれも initialize 時 1 回のみ）
- **revert / 早期 return**: 多重初期化 → revert；`_lido == 0` / `_wstETH == 0` / `_withdrawalQueue == 0` → `ZeroAddress`；BaseStrategy 標準のゼロチェック失敗 → revert。
- **発火イベント**: なし（`BaseStrategy` の初期化に従う。投資先確定の専用イベントは設けない）。
- **設計上のポイント**:
  - **`upgrader` 引数の追加**: 旧試作実装は `(vault, weth, owner, lido, withdrawalQueue, referral)` で `upgrader` を持たなかった。現行 `BaseStrategy` は Owner と Upgrader を分離するため、`_upgrader` を引数に加えて push モデルの標準初期化に揃える（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) STGY-FR-007）。
  - **投資先を `initialize` で確定**: `setLido` / `setWithdrawalQueue` の類は設けない。投資先を変えたい場合は Strategy ごと作り直し Vault 登録を入れ替える（[AaveV3Strategy 要件定義](../protocol/product/spec/strategies/AaveV3Strategy.md) AAVE-GOV-001 と同方針。LIDO-SEC-001）。
  - **Lido 三点セットの整合性を deploy 時に落とす**: `lido` / `wstETH` / `withdrawalQueue` は同じ Lido 系でなければならない。`wstETH.stETH()` と `lido` の一致、および Queue の MIN/MAX bounds を initializer で読んで、誤った venue address・mock・将来別バージョンを fail-fast する（LIDO-SEC-008）。
  - **Underlying = WETH を on-chain で確認**: Vault 登録時に `strategy.underlying() == vault.underlying()` が検証される（LIDO-FR-002）。デプロイスクリプトでも対象 Vault の Underlying が WETH であることを assert する。
- **Verification**: unit（多重初期化 revert・`ZeroAddress` 各 revert・wstETH/stETH mismatch reject・Queue bounds reject・stETH→wstETH／wstETH→Withdrawal Queue の max approve 成立・投資先固定・`upgrader` 保存）。

### LIDO-FR-002: addStrategy 前提（Vault 登録契約）

- **Type**: Functional ｜ **Source**: [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) `underlying()` 契約 / [CollateralVault 要件定義](../protocol/product/spec/CollateralVault.md) `addStrategy`
- **シグネチャ**: `underlying() → address`（`BaseStrategy` 提供）
- **目的**: 残存実装と integration test が前提とする Vault 登録契約を記録する。`underlying()` が WETH を返し、Vault の `addStrategy` がこれを on-chain 検証する。
- **権限**: なし（`underlying()` は view）。登録操作（whitelist / `addStrategy`）は Vault の `GOV_ROLE` holder（共通 TimelockController、[CollateralVault 要件定義](../protocol/product/spec/CollateralVault.md)）。
- **事前条件（Checks）**: 当 Strategy が対応 CollateralVault のホワイトリストに登録（`addToWhitelist`）済みであること。
- **動作（Effects）**:
  1. integration test では対応 CollateralVault で `addToWhitelist(strategy)` を実行する
  2. **`addStrategy(strategy, weightBps, cap)`（3 引数）** を呼ぶと、Vault は `strategy.underlying() == vault.underlying()` を on-chain 検証する（[CollateralVault 要件定義](../protocol/product/spec/CollateralVault.md) `addStrategy`）
- **revert / 早期 return**: `strategy.underlying()` が Vault の Underlying と不一致 → Vault 側 `UnderlyingMismatch` で revert。placeholder（`underlying == address(0)`）への登録 → `UnderlyingNotSet`。
- **発火イベント**: Vault 側のイベントに従う（本 Strategy 固有イベントなし）。
- **設計上のポイント**:
  - **`isAsyncWithdraw` フラグを Vault に渡さない**: 旧試作は `addStrategy(strategy, weight, cap, true /*isAsyncWithdraw*/)` の 4 引数で Vault に非同期性を通知していた。現行 `StrategyConfig = {enabled, weightBps, cap}` は async フィールドを持たず、`addStrategy` も 3 引数である（[CollateralVault 要件定義](../protocol/product/spec/CollateralVault.md)）。非同期性は本 Strategy 内部に閉じるため、Vault は本 Strategy を**同期 Strategy と同じインターフェースで**登録・運用する（STGY-ERR-002）。
  - **本番適用可否**: deploy / register / allocation の扱いは `LIDO-GOV-001` に従う。将来の別設計では、その Strategy 固有の最悪回収期間から buffer / `withdrawDelay` を再導出する。
- **Verification**: integration（test fixture で whitelist 後 `addStrategy`（3 引数）成立・Underlying 不一致 revert）, manual（production deploy / register 対象外であること）。

### LIDO-FR-003: _doDeposit（WETH を ETH 化して Lido へ submit）

- **Type**: Functional ｜ **Source**: [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) `_doDeposit` hook / Lido submit
- **シグネチャ**: `_doDeposit(uint256 _amount)`（internal・`deposit` の hook）
- **目的**: `BaseStrategy.deposit` が受領済みの WETH を ETH へ unwrap し、`lido.submit` で stETH 化、続けて `wstETH.wrap` で wstETH 化する。その submit→wrap で得た wstETH のみを `_ownWstETH` に自己計上する。
- **権限**: 内部 hook。呼出元 `deposit` が `onlyVault`（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md)）。Vault は `deposit` 直前に `safeTransfer(strategy, _amount)` で WETH を送付済み。
- **事前条件（Checks）**: WETH は呼び出し前に Vault → Strategy へ渡っている（push モデルの預入）。
- **動作（Effects）**:
  1. `stBefore = stETH.balanceOf(address(this))` — 既存の stETH 残高（donation 等）を控除する基準
  2. `weth.withdraw(_amount)` — WETH を ETH へ unwrap（`receive()` で ETH を受領）
  3. `lido.submit{value: _amount}(referral)` — ETH を Lido へ預け stETH を mint。crediting 先 = この Strategy 自身
  4. `stReceived = stETH.balanceOf(address(this)) - stBefore` — この submit で受領した stETH のみ（donation 非混入）
  5. `wstBefore = wstETH.balanceOf(address(this))` → `reportedWstMinted = wstETH.wrap(stReceived)` → `wstAfter = wstETH.balanceOf(address(this))`。`wstMinted = wstAfter - wstBefore` とし、`reportedWstMinted` と一致しない場合は `LidoShareBalanceMismatch` で revert
  6. `wstMinted == 0` なら `LidoZeroShares` で revert。正常時は `_ownWstETH += wstMinted`
  7. `Deposited`（`principal += _amount`）の発火は `BaseStrategy.deposit` が担う。`OwnWstETHUpdated(_ownWstETH)` を発火（LIDO-EVT-004）
- **revert / 早期 return**: `weth.withdraw` / `lido.submit` / `wstETH.wrap` の失敗は inner `_doDeposit` frame を revert する。`BaseStrategy.deposit` がその frame を巻き戻し、WETH を Vault へ完全回収できれば当該 allocation を skip、回収不一致なら全体 revert する。`_receivedAmount == 0` の no-op も BaseStrategy 側で処理する（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) STGY-FR-001）。
- **発火イベント**: `OwnWstETHUpdated(uint256 ownWstETH)`（LIDO-EVT-004）。`Deposited(_amount, newPrincipal)` は `BaseStrategy`。
- **設計上のポイント**:
  - **wstETH の自己計上**: この `submit` で受領した stETH（`stBefore` 控除後の `stReceived`）のみを `wrap` し、wstETH の実残高差分（`wstAfter - wstBefore`）を `_ownWstETH` に加算する。第三者の stETH / wstETH donation は `balanceOf` を押し上げるが、同一 tx 内の `stReceived` 算定と `wrap` 実残高差分には混入しない（LIDO-SEC-002）。
  - **wrap 返り値を単独では信頼しない**: wstETH は非 rebasing position token なので、実際に Strategy が受け取った wstETH は `balanceOf` before/after 差分で確定できる。`wrap` の返り値と残高差分を照合し、不一致なら会計不整合として fail-fast する（LIDO-SEC-008）。
  - **`principal` は ETH 額（= `_amount`）で加算**: wstETH の canonical rate 上昇による増価は元本ではなく収益として後から `realizedYield()` に現れる（LIDO-FR-005）。`submit` の -1 wei 丸め・`wrap` の floor 丸めは `_ownWstETH`（wstETH 数量）側に吸収され、`principal` は Vault 送付額そのもの（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) STGY-FR-001）。
  - **`referral`**: `lido.submit` に現在の `referral` を渡す（LIDO-FR-009 で更新可能）。
- **Verification**: unit（WETH unwrap・submit・wrap 実残高差分計上・wrap 返り値不一致 reject・donation 非混入）, fork（実 Lido への submit→wrap）, invariant=LIDO-INV-001。

### LIDO-FR-004: _doWithdraw（即時引き出し可能な自己 idle WETH のみ返却）

- **Type**: Functional ｜ **Source**: [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) `_doWithdraw` hook / **STGY-ERR-002**
- **シグネチャ**: `_doWithdraw(uint256 _amount) → uint256 actual`（internal・`sendToVault` / `sendProfitToVault` の hook）
- **目的**: 通常の元本/収益回収用に、**Withdrawal Queue から claim 済みで Strategy 手元にある自己 idle WETH** のうち要求額分を返す（その後 `BaseStrategy` が元本返却は `receiveFromStrategy`、収益のみは Vault buffer への direct transfer として push する）。stETH / wstETH には直接触れない（Lido は同期引き出しできないため）。第三者が直接送った WETH や raw ETH は protocol-owned idle として返さない。
- **権限**: 内部 hook。呼出元 `sendToVault` / `sendProfitToVault` が Vault の `ALLOCATOR_ROLE` を参照（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md)）。
- **事前条件（Checks）**: なし（自己 idle WETH と実 WETH 残高の小さい方に応じてクランプ）。
- **動作（Effects）**:
  1. `ownIdle = min(_ownIdleUnderlying, IERC20(address(weth)).balanceOf(address(this)))`
  2. `actual = Math.min(_amount, ownIdle)`
  3. `_ownIdleUnderlying -= actual`（0 下限クランプ）し、`OwnIdleUnderlyingUpdated` を発火
  4. `return actual`（自己 idle WETH は既に Strategy 残高にあり、`BaseStrategy` が `vault.receiveFromStrategy(actual)` で引き取る）
- **revert / 早期 return**: revert しない。自己 idle WETH が無ければ `actual = 0` を返す（`sendToVault` / `sendProfitToVault` は `actual == 0` を正常系として扱う。[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) STGY-SEC-005）。
- **発火イベント**: なし（`SentToVault` / `ProfitSentToVault` は `BaseStrategy`）。
- **設計上のポイント**:
  - **非同期性の隠蔽の核心**: `_doWithdraw` は wstETH を unstake しない。wstETH→ETH は finalization 待ちの `requestLidoWithdrawal`（LIDO-FR-006）→ `claimLidoWithdrawals`（LIDO-FR-007）でしか進まないため、`_doWithdraw` は「その時点で即時に引き出せる自己資金」＝ claim 済み自己 idle WETH のみを返す（STGY-ERR-002）。これにより Vault 側は非同期清算経路を持たずに済む。
  - **donation を profit/principal にしない**: 直接 WETH donation は `WETH.balanceOf(this)` を押し上げるが `_ownIdleUnderlying` を増やさないため、`sendProfitToVault` や `sendToVault` の通常 push 対象にならない。raw ETH donation は WETH 化しない限り Underlying としても扱わない。
  - **`sent < 要求` は正常**: 自己 idle WETH が要求額に満たない（`0` を含む）ことは流動性の正常系であり、`sendToVault` / `sendProfitToVault` は revert しない。Buffer 補充に不足する分は、ALLOCATOR が事前に `requestLidoWithdrawal` を発行し、finalization 後に keeper または任意実行者が `claimLidoWithdrawals` で自己 idle WETH を積み増してから再度 `sendToVault` を呼ぶ運用とする（LIDO-ERR-001）。
  - **収益回収との関係**: `sendProfitToVault` は `realizedYield()` 上限で `_doWithdraw(yield)` を呼ぶが、本 Strategy では「収益分を自己 idle WETH 化」するのも `requestLidoWithdrawal` / `claimLidoWithdrawals` 経由になる。自己 idle WETH が無ければ収益 push も `0`（正常系）。
- **Verification**: unit（自己 idle WETH クランプ・`ownIdle==0` で 0・直接 WETH donation 非混入・stETH 不接触）, integration（request→claim→自己 idle→sendToVault の連携）。

### LIDO-FR-005: _estimatedTotalUnderlying（評価額の算出）

- **Type**: Functional ｜ **Source**: [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) `_estimatedTotalUnderlying` hook（保守的評価前提）
- **シグネチャ**: `_estimatedTotalUnderlying() → uint256`（internal view・`estimatedTotalUnderlying` の hook）
- **目的**: 当 Strategy が Lido で運用中の Underlying（ETH/WETH 建て）評価額を、第三者 donation を排除しつつ wstETH の canonical rate（`getStETHByWstETH`）から返す。`BaseStrategy` の `estimatedTotalUnderlying` / `realizedYield` の基礎となる。
- **権限**: なし（internal view）。
- **事前条件（Checks）**: なし（view）。
- **動作（Effects）**:
  1. `ownWst = Math.min(_ownWstETH, wstETH.balanceOf(address(this)))` — donation を排除しつつ Lido 会計上の残高低下（slashing 等で自己 wstETH が縮小する場合）を反映
  2. `stakedValue = ownWst == 0 ? 0 : wstETH.getStETHByWstETH(ownWst)` — wstETH を canonical rate で stETH(≈ETH) 換算
  3. `pendingValue = pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000`（切り捨て丸め）
  4. `ownIdleWeth = min(_ownIdleUnderlying, IERC20(address(weth)).balanceOf(address(this)))`
  5. `return stakedValue + pendingValue + ownIdleWeth`
- **revert / 早期 return**: `ownWst == 0` のとき staked 分は `0`。
- **発火イベント**: なし（view）。
- **設計上のポイント**:
  - **pending principal の算入と割引**: `pendingWithdrawAmount`（Withdrawal Queue 投入済み・未 claim、LIDO-FR-006 / LIDO-FR-007）は `pendingWithdrawalValuationBps` で評価する。effective 初期値は 10000 bps のため通常時は unstake 中の元本が AUM から一時的に消えない。Lido finalization / claim 実額に疑義がある incident 時は `pausedAllocation == true` の freeze 後に Vault の `WRITEOFF_ROLE` が bps を下げ、claim 前から pending 部分を保守的に `backingRatio()` へ反映できる。bps 計算は 1 wei 未満を切り捨てるため、端数は常に保守側に丸まる（SYS-RISK-004 の「pending principal」要件。LIDO-INV-005）。
  - **donation 耐性**: `wstETH.balanceOf(this)` と `WETH.balanceOf(this)` をそのまま使わず、自己 `submit`→`wrap` 由来の `_ownWstETH` と Lido claim 由来の `_ownIdleUnderlying` を上限とする。第三者の stETH / wstETH / WETH donation は実残高だけを押し上げるため AUM に含まれない。wstETH は非 rebasing なので平常時の評価ブレが無く、slashing 等で canonical rate（`getStETHByWstETH`）が縮小すれば下方反映される（LIDO-SEC-002 / LIDO-INV-002）。
  - **raw ETH を算入しない**: 通常 `_doDeposit` / `claimLidoWithdrawals` が同一 tx 内で ETH を wstETH 化 / WETH 化するため、平常時の生 ETH 残高は ~0。生 ETH（`address(this).balance`）は donation 経路になり得るため評価に含めず、`emergencyWithdrawFromLido` でも自動 WETH 化しない。
  - **保守性の限界**: Lido のコンセンサス層 slashing が `wstETH.balanceOf` / `getStETHByWstETH`（canonical rate）に反映される前後で評価が実回収可能額と乖離しうる。会計に現れない損失は Vault の `writeoffStrategyPrincipal`（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) STGY-FR-004 / [CollateralVault 要件定義](../protocol/product/spec/CollateralVault.md)）で明示的に backing へ下方反映する（LIDO-ERR-003）。
- **Verification**: unit（`min` 選択・pending bps 算入・端数切り捨て・0 bps / 10000 bps・stETH/wstETH/WETH/raw ETH donation 排除・raw ETH 非算入）, fork（実 `getStETHByWstETH` での評価・canonical rate 反映）, invariant=LIDO-INV-002 / LIDO-INV-005 / LIDO-INV-010。

### LIDO-FR-006: requestLidoWithdrawal（unstake 要求の発行・async 回収トリガ）

- **Type**: Functional ｜ **Source**: [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) STGY-ERR-002（非同期回収を Strategy 内部に閉じる）/ SYS-RISK-004「async 回収トリガ」
- **シグネチャ**: `requestLidoWithdrawal(uint256 _stETHAmount) external returns (uint256[] memory requestIds)`
- **目的**: stETH を Lido Withdrawal Queue へ投入して unstETH NFT（requestId）を得る、**非同期回収の起点**。MIN/MAX 制約に合わせて複数要求へ分割し、pending を記帳する。
- **権限**: Vault の `ALLOCATOR_ROLE`（運用 keeper）。資金は外部へ出ず、unstETH の owner は Strategy 自身。
- **事前条件（Checks）**:
  - 呼び出し元が Vault の `ALLOCATOR_ROLE` を保持していること（不保持は `Unauthorized`）
  - `_stETHAmount != 0`（ゼロは `0` 件の `requestIds` を返す no-op）
  - `_stETHAmount <= getStETHByWstETH(min(_ownWstETH, wstETH.balanceOf(this)))`（自己保有を超える要求はしない。超過は `AmountExceedsStaked`）
  - 分割後の request 件数が `MAX_LIDO_WITHDRAWAL_REQUESTS_PER_CALL`（実装定数 32）以下であること（超過は `LidoWithdrawalRequestTooLarge`）
  - 既存 pending request 数 + 分割後 request 件数が `MAX_ASYNC_PENDING_REQUESTS`（128）以下であること（超過は `AsyncPendingRequestLimitExceeded`）
- **動作（Effects）**:
  1. **ロール検証** — ALLOCATOR でなければ `Unauthorized`
  2. **stETH 建て分割** — 要求値（stETH 換算）を `MAX_STETH_WITHDRAWAL_AMOUNT()` 以下の chunk に分割し、端数が `MIN_STETH_WITHDRAWAL_AMOUNT()` 未満にならないよう調整する
  3. **wstETH 換算** — 各 chunk を `wstETH.getWstETHByStETH` で wstETH 量へ変換し、各 chunk の stETH 換算 `getStETHByWstETH(chunk)` が MIN/MAX 内であることを確認する。投入 wstETH 合計が `min(_ownWstETH, wstETH.balanceOf(address(this)))` を超える場合は `AmountExceedsStaked`
  4. **pending capacity 検査** — 新規 request 追加後の未 claim request 総数が `MAX_ASYNC_PENDING_REQUESTS`（128）を超えないことを確認する
  5. `requestIds = withdrawalQueue.requestWithdrawalsWstETH(amounts, address(this))` — wstETH を Queue が引き取り（内部で unwrap）、unstETH NFT を Strategy 自身に mint
  6. before/after の wstETH 残高差分が投入 wstETH 合計と一致することを確認し、`_ownWstETH -= totalWstETH`（0 下限クランプ）
  7. 各 `requestId` について `withdrawalQueue.ownerOf(requestId) == address(this)` を検証する
  8. `pendingWithdrawAmount += totalRequested`；各 `requestId` を未 claim 集合に記録（claim 時に額を引けるよう requestId→amount を保持）
  9. `WithdrawRequested(requestIds, totalRequested)`（LIDO-EVT-002）/ `OwnWstETHUpdated(_ownWstETH)`（LIDO-EVT-004）を発火
- **revert / 早期 return**: 非 ALLOCATOR → `Unauthorized`；MIN/MAX を満たす分割が不能（極端に小さい額）→ `AmountOutOfRange`；自己保有超過 → `AmountExceedsStaked`；request 件数上限超過 → `LidoWithdrawalRequestTooLarge`；pending request 総数上限超過 → `AsyncPendingRequestLimitExceeded`；返却 requestId の owner が Strategy でない場合 → `UnexpectedWithdrawalRequestOwner`。
- **発火イベント**: `WithdrawRequested(uint256[] requestIds, uint256 stETHAmount)`（LIDO-EVT-002）/ `OwnWstETHUpdated`（LIDO-EVT-004）。
- **設計上のポイント**:
  - **pending principal は `principal` を減らさない**: 要求発行時点では元本はまだ Vault へ戻っていない。`principal` は減算せず、`pendingWithdrawAmount` を `pendingWithdrawalValuationBps` で AUM に保持する（減算は自己 idle WETH を実際に Vault へ push する `sendToVault` でのみ起こる）。これが SYS-RISK-004 の「pending principal」要件（LIDO-INV-005 / LIDO-INV-006）。
  - **どれだけ要求するかは Vault 状況から決める運用**: 要求額は「buffer 不足の `WithdrawRequest` 残（[CollateralVault 要件定義](../protocol/product/spec/CollateralVault.md) `pendingWithdrawals`）＋ リバランス目標」を満たすよう ALLOCATOR が決める。Strategy は要求額の妥当性（自己保有上限・MIN/MAX）だけを検証する。
  - **griefing 耐性**: ALLOCATOR 限定とし、第三者が無意味な unstake で利回りを止める攻撃を防ぐ（LIDO-SEC-004）。資金は外部へ出ないため、運用鍵侵害の被害は「unstake タイミングの撹乱」に限定される。
- **Verification**: unit（ALLOCATOR 限定・MIN/MAX 分割・request 件数上限・自己保有上限・requestId owner 確認・pending 記帳・wstETH 減算）, fork（実 Withdrawal Queue への requestWithdrawalsWstETH）, invariant=LIDO-INV-005。

### LIDO-FR-007: claimLidoWithdrawals（finalized 要求の受領・claimable 化）

- **Type**: Functional ｜ **Source**: [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) STGY-ERR-002 / SYS-RISK-004「claimable 化」
- **シグネチャ**: `claimLidoWithdrawals(uint256[] calldata _requestIds) external` / `claimLidoWithdrawals(uint256[] calldata _requestIds, uint256[] calldata _hints) external`
- **目的**: finalization 済みの unstETH 要求を claim して ETH を受領し、WETH に wrap して **自己 idle 化**する。自己 idle WETH はその後 `sendToVault`（LIDO-FR-004）で Vault buffer へ push できる。
- **権限**: permissionless。受領 ETH は Strategy 自身に入り WETH 化されるだけで外部へ出ず、任意宛先を持たない。finalized request の損益反映を keeper 権限に依存させない。
- **事前条件（Checks）**:
  - 各 `requestId` が本 Strategy の未 claim 集合に属すること（未知 ID は `UnknownRequest`）
  - 各 `requestId` が finalization 済みであること（未 finalization は Withdrawal Queue が revert。事前に `getWithdrawalStatus` で確認する運用）
  - no-hint overload は単一 request 専用。複数 request は hint 付き overload を使う（複数 no-hint は `ClaimHintsRequired`、hint 長不一致は `WithdrawalQueueRequestMismatch`）
  - 1 tx の claim batch は `MAX_ASYNC_REQUESTS_PER_CLAIM`（32）以下であること（超過は `AsyncRequestClaimTooLarge`）
- **動作（Effects）**:
  1. 先に各 `requestId` を未 claim 集合から除去し、`pendingWithdrawAmount -= 記録していた要求額`（0 下限クランプ）
  2. no-hint overload は `withdrawalQueue.claimWithdrawal(requestId)`、hint 付き overload は `withdrawalQueue.claimWithdrawals(requestIds, hints)` を呼び、ETH を Strategy へ送金する（`receive()` で受領）
  3. claim 前後の ETH 残高差分 `ethReceived` のみを `weth.deposit{value: ethReceived}()` で WETH に wrap（自己 idle 化）。既存 raw ETH donation は巻き込まない
  4. WETH 実残高差分を `_ownIdleUnderlying` に加算し、`OwnIdleUnderlyingUpdated`（LIDO-EVT-005）を発火
  5. `WithdrawClaimed(_requestIds, ethReceived)`（LIDO-EVT-003）を発火
- **revert / 早期 return**: 未知 ID → `UnknownRequest`；複数 no-hint → `ClaimHintsRequired`；claim batch 上限超過 → `AsyncRequestClaimTooLarge`；hint 長不一致 → `WithdrawalQueueRequestMismatch`；未 finalization → Withdrawal Queue が revert（早期 claim 不可。LIDO-ERR-001）。
- **発火イベント**: `WithdrawClaimed(uint256[] requestIds, uint256 ethReceived)`（LIDO-EVT-003）/ `OwnIdleUnderlyingUpdated(uint256 ownIdleUnderlying)`（LIDO-EVT-005、`ethReceived == 0` の場合は省略可）。
- **設計上のポイント**:
  - **pending の減算は記録額ベース**: `pendingWithdrawAmount` は要求時に記録した stETH 額で減算し、走行中の見積りを安定させる。finalization レートにより実 ETH 受領額が要求 stETH 額とわずかに乖離しても、その差は `_estimatedTotalUnderlying()`（自己 idle WETH 算入）と `realizedYield()` 側に自然に現れる。
  - **finalized だけでは損益を確定しない**: request が Lido 側で finalized 済みでも、`claimLidoWithdrawals` が実行されるまでは本 Strategy の AUM は `pendingWithdrawAmount` を `pendingWithdrawalValuationBps` で評価する。finalization amount の haircut / surplus は claim 後に自己 idle WETH として初めて会計へ出るため、incident 時の writeoff・清算判断は「finalized 状態確認」だけで行わず、必要に応じて `pausedAllocation == true` を確認してから `WRITEOFF_ROLE` が bps を保守側へ下げ、claim 実行後の `ethReceived` / `estimatedTotalUnderlying()` / `principal` を突合してから行う。
  - **claim 後は自己 idle WETH に化け、`_doWithdraw` の返却対象になる**: ここで初めて「即時引き出し可能な自己資金」が増える。Vault への実 push と `principal` 減算は `sendToVault`（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) STGY-FR-002）が担う（claim 自体は `principal` を動かさない）。
  - **raw ETH donation を巻き込まない**: wrap する ETH は claim 前後の増分だけであり、過去に直接送られた raw ETH donation を自己 idle として計上しない。
  - **claim hint 最適化**: no-hint overload は Lido の単一 request claim を使い、複数 request は off-chain keeper または任意実行者が `findCheckpointHints` 等で hint を取得して batch claim する。hint の取得方法は off-chain 運用手順に委ねる。pending request が 32 件を超える場合は複数 tx に分割する。
- **Verification**: unit（permissionless claim・未知 ID revert・複数 no-hint revert・hint 長不一致 revert・pending 減算・ETH→WETH wrap・自己 idle 化・raw ETH donation 非混入）, fork（finalization 後の claim・未 finalization revert）, invariant=LIDO-INV-005 / LIDO-INV-010。

### LIDO-FR-008: emergencyWithdrawFromLido（緊急回収・非 atomic の限界明示）

- **Type**: Functional ｜ **Source**: [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) 固有の緊急回収関数（`emergency*From{Protocol}()`）/ async の限界
- **シグネチャ**: `emergencyWithdrawFromLido() external onlyOwner returns (uint256 sent)` / `emergencyWithdrawFromLido(uint256 _maxStETHToRequest) external onlyOwner returns (uint256 sent)`
- **目的**: Lido / stETH / wstETH に重大インシデントが疑われる場合に、Owner（Guardian multisig）が **(a) claim 済み自己 idle WETH を同一 tx 内で Vault へ push し、(b) 残る wstETH 全量の unstake 要求を発行**する緊急関数。stake 済み元本は finalization 待ちのため即時には回収できない。直接 WETH/raw ETH donation は Lido principal として扱わない。
- **権限**: `onlyOwner`（Guardian multisig）。運用ロール（ALLOCATOR）とは分離（LIDO-SEC-003）。
- **事前条件（Checks）**: `caller == Owner`。
- **動作（Effects）**:
  1. **自己 idle の確定** — `idle = min(_ownIdleUnderlying, weth.balanceOf(this))`。raw ETH は WETH 化せず、直接 WETH donation は `_ownIdleUnderlying` を増やさないため含めない
  2. **Vault へ atomic push** — `idle != 0` なら `sent = CollateralVault.receiveFromStrategy(idle)`（Vault buffer へ即時計上・valuation cache も減額）し、`_ownIdleUnderlying -= idle`、`sent` を returned principal として `principal -= min(sent, principal)` と記帳する
  3. **残 wstETH の unstake 要求** — `remaining = min(_ownWstETH, wstETH.balanceOf(this))` があれば、no-arg 版は 1 tx あたりの実装上限（`MAX_STETH_WITHDRAWAL_AMOUNT * MAX_LIDO_WITHDRAWAL_REQUESTS_PER_CALL`）、引数付き overload は `min(_maxStETHToRequest, 実装上限)` を上限に request 量を決める。その stETH 換算が MIN/MAX に収まるよう分割して `withdrawalQueue.requestWithdrawalsWstETH(amounts, this)` を発行し、`pendingWithdrawAmount += requestAmount` 加算・`_ownWstETH -= queuedWstETH` 減算・requestId 記録（LIDO-FR-006 と同じ記帳）。**この分の ETH 回収は finalization 後の `claimLidoWithdrawals` ＋ `sendToVault` でしか完了しない**
  4. `EmergencyWithdrawn(sent)`（`BaseStrategy` 共通イベント）/ 残 wstETH を要求した場合は `WithdrawRequested`（LIDO-EVT-002）を発火し `sent` を返す
- **revert / 早期 return**: 非 Owner → revert；idle・stETH ともに 0、または `_maxStETHToRequest` が MIN 未満で要求可能量が無い場合 → 何もせず正常終了（`sent = 0`）。
- **発火イベント**: `EmergencyWithdrawn(uint256 amount)`（共通）/ `WithdrawRequested(...)`（残 wstETH を要求した場合）。
- **設計上のポイント**:
  - **即時全回収は保証しない（honest な限界）**: Aave の `emergencyWithdrawFromAave` は 1 tx で全額を Vault へ戻せるが、Lido は stake 済み元本を即時 ETH 化できない。本関数は「即時に出せる idle の atomic push」＋「残部の unstake 要求発行」までで、stake 済み元本の Vault 復帰は finalization（〜1-5 日、混雑時はそれ以上）に律速される。要件として**即時償還を約束しない**（LIDO-ERR-004 / [Product-Overview](../protocol/product/Product-Overview.md) SYS-NFR-004 と整合）。
  - **第三者 donation は回収対象にしない**: `emergencyWithdrawFromLido` が unstake 要求へ投入するのは `min(_ownWstETH, wstETH.balanceOf(this))`、即時 push するのは `min(_ownIdleUnderlying, WETH.balanceOf(this))` に限る。第三者が直接送った stETH / wstETH / WETH / raw ETH は AUM に含めず、Lido 固有緊急回収でも protocol backing として扱わない。誤送金回収を導入する場合は、donation と protocol-owned position の境界を壊さない別 upgrade / governance 手順で扱う。
  - **宛先固定**: idle の push 先は Vault 固定で任意 `_to` を持たない（LIDO-SEC-003）。残 wstETH の unstETH owner も Strategy 自身で、第三者へ渡らない。
  - **`backingRatio()` の一時 window**: idle を atomic push して returned principal を記帳し、残 wstETH は `pendingWithdrawAmount` として AUM に残るため、緊急回収による `backingRatio()` の不当な一時低下や部分回収後 writeoff の二重計上を避ける（pending を AUM 算入する LIDO-FR-005 の効果）。
  - **`BaseStrategy.emergencyWithdraw` との違い**: 共通 `emergencyWithdraw(uint256)` は Strategy 直接保有の Underlying を Vault へ送る汎用救済であり、`principal` は減算しない。直接 WETH donation の救済には使えるが Lido principal return ではない。`emergencyWithdrawFromLido()` は Lido position を可能な範囲で unwind（claim 済み自己 idle push ＋ 残 unstake 要求）する Lido 固有関数で、Vault 実受領分を returned principal として記帳する。どちらも任意宛先を持たない。
- **Verification**: unit（onlyOwner・自己 idle atomic push・直接 WETH/raw ETH donation 非混入・残 wstETH の requestWithdrawalsWstETH 発行・引数付き overload の request 額 cap・宛先 Vault 固定・即時全回収を約束しない）, fork（claim 済み自己 idle push ＋ 残 unstake 要求）。

### LIDO-FR-009: setReferral（リファラル更新）

- **Type**: Functional ｜ **Source**: 旧試作実装の `setReferral` / Lido referral 制度
- **シグネチャ**: `setReferral(address _referral) external onlyOwner`
- **目的**: `lido.submit` に渡す `referral` を更新する。Lido がリファラルインセンティブを付与する場合の帰着先。
- **権限**: `onlyOwner`（Guardian multisig）。
- **動作（Effects）**: `referral = _referral`（ゼロ可）；`ReferralUpdated(_referral)`（LIDO-EVT-001）を発火。
- **revert / 早期 return**: 非 Owner → revert。
- **発火イベント**: `ReferralUpdated(address indexed referral)`（LIDO-EVT-001）。
- **設計上のポイント**: 次回以降の `_doDeposit` の `submit` に反映される。過去の submit には遡及しない。referral インセンティブが別トークンで着金する場合の扱いは `sweepRewardToken`（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) STGY-FR-010）に準じ、stETH / unstETH は protected token として sweep しない（LIDO-SEC-007）。referral の確定値は LIDO-TBD-002。
- **Verification**: unit（onlyOwner・referral 反映・次回 submit への適用）。

---

## 7. 状態変数・会計モデル

`BaseStrategy` が持つ共通ストレージ（`vault` / `underlyingToken` / `_principal` / `_pendingOwner` / `upgrader`）と、`AsyncRequestStrategy` が持つ async 共通ストレージ（`_ownIdleUnderlying` / `pendingWithdrawAmount` / requestId 管理）に加え、`LidoStrategy` 固有のストレージは以下。`lido` / `stETH` / `withdrawalQueue` / `weth` は `initialize` で固定し以後変更不可。

| 変数 | 型 | 役割 | 確定 |
| --- | --- | --- | --- |
| `lido` | `ILido` | Lido stETH（`submit` の呼び出し先） | `initialize` で固定・不変 |
| `stETH` | `IStETH` | stETH の ERC-20 ビュー（= `lido` と同一アドレス）。`wstETH.wrap` の入力・中間トークン | `initialize` で固定・不変 |
| `wstETH` | `IWstETH` | Lido wstETH（`wrap` / `unwrap` / `getStETHByWstETH` / `getWstETHByStETH` / `balanceOf` の呼び出し先）。本 Strategy の**保有形・AUM 評価の基礎** | `initialize` で固定・不変 |
| `withdrawalQueue` | `IWithdrawalQueueERC721` | Lido Withdrawal Queue（requestWithdrawalsWstETH / claimWithdrawal / MIN・MAX） | `initialize` で固定・不変 |
| `weth` | `IWETH` | Underlying（= `underlyingToken`）を ETH 操作用に型付け保持 | `initialize` で固定・不変 |
| `referral` | `address` | `lido.submit` のリファラル | `initialize` 既定 / `setReferral` |
| `_ownWstETH` | `uint256` | **この Strategy 自身の** submit→wrap で得た wstETH（= 自己の stETH shares）。第三者 donation を含まない。AUM 評価の基礎（LIDO-FR-005） | `_doDeposit` で加算 / `requestLidoWithdrawal`・`emergencyWithdrawFromLido` で減算 |
| `_ownIdleUnderlying` | `uint256` | **この Strategy 自身の** Lido Withdrawal Queue claim で受領・WETH 化した idle Underlying。第三者 WETH/raw ETH donation を含まない。AUM の idle 成分・通常 push・Lido emergency push の上限 | `claimLidoWithdrawals` で加算 / `_doWithdraw`・`emergencyWithdrawFromLido`・汎用 `emergencyWithdraw` hook で減算 |
| `pendingWithdrawAmount` | `uint256` | Withdrawal Queue 投入済み・未 claim の stETH 額合計（pending principal） | `requestLidoWithdrawal` で加算 / `claimLidoWithdrawals` で減算 |
| `pendingWithdrawalValuationBps` | `uint256` | pending principal の effective 評価 bps。fresh 初期値 10000、未設定 storage も 10000 として扱い、incident freeze 後に Vault `WRITEOFF_ROLE` が 0〜10000 へ下方調整できる。復元・上方変更は pause 不要 | `initialize` で 10000 / `setPendingWithdrawalValuationBps` で更新 |
| 未 claim requestId 管理 | `mapping`/array | 未 claim の requestId と要求額（claim 時の pending 減算・claim 漏れ防止に使用） | `requestLidoWithdrawal` 追加 / `claimLidoWithdrawals` 除去 |

**会計モデル**: 投下元本 `principal` の自己管理・`realizedYield = max(estimatedTotalUnderlying − principal, 0)` などの会計は `BaseStrategy` に属する（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md)）。`LidoStrategy` は Lido 側ポジションの評価（`_estimatedTotalUnderlying`）と非同期ライフサイクル（pending / requestId）を担う。

- **AUM の構成**: `estimatedTotalUnderlying = getStETHByWstETH(min(_ownWstETH, wstETH.balanceOf(this))) + pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000 + min(_ownIdleUnderlying, WETH.balanceOf(this))`。stake 済み（canonical rate 込み）＋ bps 調整後の unstake 待機中 ＋ claim 済み自己 idle の 3 つを ETH/WETH 建てで合算する。bps 計算は切り捨て丸めで、直接 stETH / wstETH / WETH / raw ETH donation は AUM に含めない。
- **`principal` の増減**: `deposit` で「Vault が送った WETH 額」加算。`sendToVault` と `emergencyWithdrawFromLido` の idle push で「Vault が実受領した `sent`」を `min(sent, principal)` 減算（principal-first）。`writeoffPrincipal` で `min(_amount, principal)` 減算。`sendProfitToVault` / `requestLidoWithdrawal` / `claimLidoWithdrawals` / `setReferral` では不変。
- **元本/収益の分離（SYS-RISK-004「収益・元本の混同防止」）**: wstETH の canonical rate 上昇による増価は `realizedYield()` に現れ、`sendProfitToVault`（`principal` 不変）で push する。元本は `sendToVault` または `emergencyWithdrawFromLido` の自己 idle push（いずれも `sent` ベースで `principal` 減算）で Vault へ戻る。pending（unstake 中）は `principal` を減らさず AUM に保持し、claim → 自己 idle WETH → `sendToVault` / `emergencyWithdrawFromLido` の経路でのみ元本が Vault へ戻り `principal` が減る。
- **pending principal が `principal` を一時下回らせない**: 要求発行で stake が pending に移っても `principal` は据え置き、通常時は `pendingWithdrawalValuationBps = 10000` で pending を満額算入するため、unstake 中に `realizedYield()` が見かけ上マイナスへ振れない。incident freeze 後に bps を下げた場合は、未 claim pending の保守割引として明示的に `estimatedTotalUnderlying` と Vault の保守評価へ反映する（LIDO-INV-005 / LIDO-INV-006）。
- **報酬トークンの会計境界**: stETH 自体はステーキング元本＋利息を表す position token であり reward token ではない。stETH / unstETH NFT は `sweepRewardToken` の protected token として拒否する（LIDO-SEC-007）。Lido referral 等が別トークンで着金した場合のみ共通 `BaseStrategy.sweepRewardToken` で Treasury へ送る（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) STGY-FR-010）。

---

## 8. 不変条件（INV）

| ID | 不変条件 | 検証 |
| --- | --- | --- |
| LIDO-INV-001 | `_ownWstETH` は当 Strategy 自身の `_doDeposit`（`wrap` 後の wstETH 実残高増分の加算）/ `requestLidoWithdrawal`・`emergencyWithdrawFromLido`（投入 wstETH 分の減算・0 下限クランプ）でのみ増減し、第三者の stETH / wstETH donation では増えない | invariant |
| LIDO-INV-002 | `_estimatedTotalUnderlying()` は `getStETHByWstETH(min(_ownWstETH, wstETH.balanceOf(this))) + pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000 + min(_ownIdleUnderlying, WETH.balanceOf(this))`。pending bps 計算は切り捨て丸め。第三者 donation は AUM に含めず、canonical rate 低下（slashing）は反映する。生 ETH 残高は算入しない | invariant / fork |
| LIDO-INV-003 | `lido` / `stETH` / `wstETH` / `withdrawalQueue` / `weth` は `initialize` 後不変（setter を持たない） | invariant |
| LIDO-INV-004 | `_doWithdraw` は自己 idle WETH を超えて返さない（`actual <= min(_ownIdleUnderlyingBefore, weth.balanceOf(this))`）。返却分だけ `_ownIdleUnderlying` を減らし、stETH を同期 unstake しない | unit |
| LIDO-INV-005 | `pendingWithdrawAmount` は未 claim requestId の記録要求額の合計と一致し、`requestLidoWithdrawal` で増・`claimLidoWithdrawals` で減・claim 済み ID の二重 claim をしない | invariant |
| LIDO-INV-006 | `requestLidoWithdrawal` / `claimLidoWithdrawals` は `principal` を変えない（pending への移動・claim は元本帳簿に影響しない。`principal` 減算は `sendToVault` と `emergencyWithdrawFromLido` の Vault 実受領額ベースのみ） | invariant |
| LIDO-INV-007 | `sweepRewardToken` は Underlying(WETH)・stETH・wstETH・unstETH を拒否し、これらを Treasury へ移動できない（position token 保護） | unit |
| LIDO-INV-008 | `underlying()` は WETH 不変で、対応 Vault の Underlying と一致する | invariant |
| LIDO-INV-009 | `wstETH.stETH()` は `lido` と一致し、Withdrawal Queue bounds は `MIN != 0` かつ `MAX >= MIN` の初期化済み venue でなければならない | unit / manual |
| LIDO-INV-010 | `_ownIdleUnderlying` は Lido claim で実際に WETH 化した自己受領分でのみ増え、`_doWithdraw` / `emergencyWithdrawFromLido` / 汎用 `emergencyWithdraw` hook で減る。直接 WETH donation や raw ETH donation では増えず、stale な自己 idle 枠が後続 donation で再充填されない | unit / invariant |

> 共通の不変条件（`principal` 非負・`sendProfitToVault`/汎用 `emergencyWithdraw` が `principal` 不変・固有緊急回収は returned principal を記帳・`realizedYield` 恒等・2-step Owner・UUPS upgrader 限定など STGY-INV-001..010）は [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) を正本とし、本書では再掲しない。

---

## 9. セキュリティ要件（SEC）

### LIDO-SEC-001: 投資先アドレスの initialize 時固定

- Type: Security
- Statement: `lido` / `stETH` / `wstETH` / `withdrawalQueue` / `weth` および Withdrawal Queue への approve は `initialize` で固定し、`setLido` / `setWstETH` / `setWithdrawalQueue` 等の事後変更 setter を一切持ってはならない（「投資先を Strategy 側で動かせる」攻撃面と storage migration リスクの排除）。投資先を変えたい場合は Strategy ごと作り直し Vault 登録を入れ替える（[AaveV3Strategy 要件定義](../protocol/product/spec/strategies/AaveV3Strategy.md) AAVE-GOV-001 と同方針）。
- Verification: invariant=LIDO-INV-003, manual（setter 不在のコードレビュー）

### LIDO-SEC-002: 第三者 donation・rebase による AUM 水増しの排除

- Type: Security
- Statement: stETH / wstETH / WETH は誰でも本 Strategy に transfer でき、raw ETH も `receive()` に直接送れる（donation 経路が存在する）。これらの `balanceOf` / ETH balance をそのまま AUM にすると、第三者 donation が `realizedYield()` を水増しし、`sendProfitToVault` ＋ Vault の収益→Treasury 経路で任意額を protocol yield と誤認させる攻撃が成立する。これを防ぐため、`_estimatedTotalUnderlying()` は stake 済み分を `_ownWstETH`、claim 済み自己 idle 分を `_ownIdleUnderlying` で自己由来に限定し、`getStETHByWstETH(min(_ownWstETH, wstETH.balanceOf(this))) + pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000 + min(_ownIdleUnderlying, WETH.balanceOf(this))` で評価しなければならない。canonical rate を使うことでステーキング利回りの正当な増価は反映しつつ、donation（実残高のみ押し上げ）は排除する。raw ETH は評価にも Lido emergency push にも算入しない。
- Verification: invariant=LIDO-INV-001/002/010, fork（wstETH/WETH/raw ETH donation を注入しても `realizedYield` が増えないこと・canonical rate 上昇は反映されること）

### LIDO-SEC-003: 緊急回収の宛先固定と権限分離

- Type: Security
- Statement: `emergencyWithdrawFromLido` は `onlyOwner` とし運用ロール（ALLOCATOR）から発動できてはならない。自己 idle の引き出し先・push 先は Vault 固定（任意 `_to` を持たない）とし、残 wstETH の unstETH owner も Strategy 自身に固定して、Owner 鍵が侵害されても任意宛先には資金を抜けないようにしなければならない。stake 済み元本を即時 ETH 化できないことは設計の限界として明記し（LIDO-FR-008）、即時全回収を約束しない。直接 WETH/raw ETH donation は Lido principal return として処理しない。
- Verification: unit（ALLOCATOR からの呼び出し revert・自己 idle の Vault 固定 push・直接 WETH/raw ETH donation 非混入・残 wstETH の自己 owner・任意宛先なし）

### LIDO-SEC-004: 非同期 keeper（request/claim）の権限と griefing 耐性

- Type: Security
- Statement: `requestLidoWithdrawal` は ALLOCATOR 限定とし、第三者が無意味な unstake を発行して利回りを止める griefing を防がなければならない。`requestLidoWithdrawal` は自己保有（`min(_ownWstETH, wstETH.balanceOf)` の stETH 換算）を超える要求をせず、MIN/MAX 制約に合わせて分割する。`claimLidoWithdrawals` は permissionless とし、finalized request の損益反映を keeper 鍵に依存させない。ただし未知 requestId の claim・二重 claim・複数 request の no-hint claim は拒否しなければならない。
- Verification: unit（request の ALLOCATOR 限定・自己保有上限・MIN/MAX 分割・claim の permissionless 実行・未知 ID / 二重 claim 拒否）

### LIDO-SEC-005: finalization 前 claim の拒否

- Type: Security
- Statement: finalization されていない requestId の `claimWithdrawal` は Lido Withdrawal Queue が revert する。本 Strategy はこれに依存し、独自に finalization 状態を偽って claim を試みてはならない。運用は `getWithdrawalStatus` で finalization を確認してから `claimLidoWithdrawals` を呼ぶ。早期 claim 不可は正常系として扱い（再試行）、回収不能とはみなさない（LIDO-ERR-001）。
- Verification: unit（未 finalization で revert 伝播）, fork（finalization 後のみ claim 成功）

### LIDO-SEC-006: stETH / wstETH の 1-wei 丸め・会計の安全側処理

- Type: Security
- Statement: `submit`（ETH→stETH）と `wrap`（stETH→wstETH）の換算で ±1 wei・floor の丸めが起こりうる。`principal` は Vault 送付額（`_doDeposit` 引数）で加算し、丸め差は `_ownWstETH`（wstETH 数量）・`realizedYield()` 側に吸収させて、`principal` の過大計上を起こしてはならない。`pendingWithdrawAmount` の減算は要求記録額ベースで行い、finalization レートとの僅少な乖離は自己 idle WETH 算入で自然に補正する。`_ownWstETH` / `_ownIdleUnderlying` 減算・pending 減算はいずれも 0 下限クランプを行う。wstETH は非 rebasing のため rebase ごとの丸め蓄積が無く、stETH を直接保有・追跡する場合より丸め面が小さい。
- Verification: unit（1-wei 境界・principal 非過大・pending 0 下限クランプ）

### LIDO-SEC-007: stETH / unstETH の reward sweep 禁止

- Type: Security
- Statement: stETH / wstETH はステーキング元本＋利息を表す position token、unstETH NFT は引き出し請求権であり、いずれも reward token ではない。`sweepRewardToken` でこれらを Treasury へ移動できると、Lido withdraw 経路・`_ownWstETH`・Vault の backing 会計を迂回するため、`LidoStrategy` は `BaseStrategy._isSweepProtectedToken` を override して Underlying(WETH)・stETH・wstETH・unstETH を protected token に含めなければならない。Lido referral 等の真の reward token の sweep は引き続き可能。
- Verification: unit（`sweepRewardToken(stETH/unstETH/WETH)` revert・通常 reward token sweep は成功）

### LIDO-SEC-008: Lido venue 誤配線と request / wstETH 返り値不整合の fail-fast

- Type: Security
- Statement: `initialize` は `wstETH.stETH() == lido` と Withdrawal Queue bounds（`MIN != 0` / `MAX >= MIN`）を検証し、Lido 三点セットの誤配線を拒否しなければならない。`requestLidoWithdrawal` は返却 requestId の owner が Strategy 自身であることを確認してから pending 会計に入れる。`_doDeposit` は `wstETH.wrap` の返り値だけで `_ownWstETH` を増やしてはならず、wstETH `balanceOf(this)` の before/after 差分を真実として返り値と照合しなければならない。不一致は `LidoShareBalanceMismatch` で revert し、外部 protocol adapter の会計が虚偽返り値に依存しないようにする。
- Verification: unit（wstETH/stETH mismatch reject・invalid Queue bounds reject・requestId owner mismatch reject・wrap return / balance delta mismatch reject）, manual（deploy address review）

> **reentrancy / CEI**: push 経路の権限・会計防御は `BaseStrategy` / CollateralVault の責務であり（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) / [CollateralVault 要件定義](../protocol/product/spec/CollateralVault.md)）、本書はそれを再仕様化しない。本 Strategy は `weth.withdraw` / `lido.submit` / `withdrawalQueue.claimWithdrawal` で ETH を受領する（`receive()`）。これらの外部呼び出し前後で wstETH 残高・受領 stETH・pending を before/after 実測または記録額で計上し、claim は未 claim 集合の存在確認 → 状態更新 → 外部呼び出しの順序とする。callback 性の強い経路を追加する場合は `BaseStrategy` 側の reentrancy guard 導入を [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) に従って再検討する。

---

## 10. ガバナンス・運用・アップグレード要件（GOV）

共通の権限・アップグレード方針（UUPS `_authorizeUpgrade` = `upgrader` 限定・`transferOwnership` / `renounceOwnership` 無効化・Owner は Guardian multisig・Upgrader は専用主体）は [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md)（STGY-GOV-001..005）を正本とする。Lido 固有の非 activation / deploy surface 要件と、inventory で既存 instance が見つかった場合の回収要件のみを以下に示す。新規 instance の運用開始を意図しない。

### LIDO-GOV-001: 非 activation / deploy surface ゲート

- Statement: 現行 `LidoStrategy` の source / test は削除せず、production Solidity source と監査 nSLOC に残す。一方、本番へ deploy / whitelist / `addStrategy` / allocation せず、公式 deploy script から Lido 固有 selector・deploy / register helper・env reader を除外する。`lido` 指定は既存の generic unknown-kind fallback で fail closed とし、Lido 専用 reject を deploy policy / preflight / manifest に重複実装しない。preflight / generated config は承認済み Strategy set と生成Manifestの汎用照合で非採用を保証する。既存環境の inventory で instance が見つかった場合は allocation 停止、pending / idle / principal 回収、`principal == 0` と live AUM 0 の readback、Vault 登録解除を完了する。将来の stETH 系 Strategy 採用は、残存 code の存在を承認とみなさず、新規 proposal、governance 承認、実装 review、外部監査を要求する。
- Verification: manual（audit scope / nSLOCへの残置、instance inventory、公式 deploy wiring / Manifest の非採用確認）、unit（`lido` 指定が generic unknown-kind fallback で失敗）

### LIDO-GOV-002: 非同期 keeper の運用 Runbook

- Statement: 新規 keeper は起動しない。inventory で既存 instance と回収対象残高が見つかった場合だけ、`requestLidoWithdrawal` は off-chain keeper（ALLOCATOR）が回収目的で起動し、`claimLidoWithdrawals` は off-chain keeper または任意実行者が起動できる。回収手順では、(a) allocation 停止後の残 position と pending request、(b) `getWithdrawalStatus` による finalization 監視、(c) claim 済み自己 idle WETH の `sendToVault`、(d) principal / AUM / Vault 受領額の readback、(e) donation residue の分離を定める。回収証跡が完了するまで必要な reader / runbook を先に削除しない。
- Verification: manual（運用 Runbook・keeper 障害時の縮退レビュー）

### LIDO-GOV-003: 異常時の新規割当停止と緊急回収

- Statement: inventory で既存 instance が見つかった場合、Lido / stETH の異常兆候にかかわらず、GUARDIAN は Vault 側で `emergencyDisableStrategy`（[CollateralVault 要件定義](../protocol/product/spec/CollateralVault.md)）により当 Strategy の `weightBps = 0` / `enabled = false` として新規 supply を停止する。Owner は `emergencyWithdrawFromLido` で自己 idle を Vault へ戻して returned principal を記帳し、残 wstETH の unstake を要求する（ただし即時全回収は不可・LIDO-FR-008）。直接 WETH donation の救済は必要に応じて汎用 `emergencyWithdraw` で Vault へ戻せるが、Lido principal return ではない。回収不能が確定した残 `principal` は `writeoffStrategyPrincipal`（[CollateralVault 要件定義](../protocol/product/spec/CollateralVault.md)）で backing へ下方反映する。既存 instance がない場合は本経路を新設・起動せず、source / test のみを保持して公式 deploy / runtime wiring を持たない。
- Verification: manual（監視・緊急時 Runbook）, integration（emergencyDisableStrategy → emergencyWithdrawFromLido → writeoff）

---

## 11. イベント・監視要件（EVT）

共通イベント（`Deposited` / `SentToVault` / `ProfitSentToVault` / `PrincipalWrittenOff` / `EmergencyWithdrawn` / `RewardTokenSwept` / Owner・Upgrader 系）は `BaseStrategy` が発火する（[Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md)）。Lido 固有のイベント・監視は、inventory で既存 instance が見つかり回収が必要な場合に限って以下を使う。既存 instance がない環境へ新規監視を追加しない。

| ID | イベント | 用途（off-chain） |
| --- | --- | --- |
| LIDO-EVT-001 | `ReferralUpdated(address indexed referral)` | `setReferral` の追跡 |
| LIDO-EVT-002 | `WithdrawRequested(uint256[] requestIds, uint256 stETHAmount)` | `requestLidoWithdrawal` / `emergencyWithdrawFromLido` の unstake 要求発行。pending 投入額・unstETH の追跡 |
| LIDO-EVT-003 | `WithdrawClaimed(uint256[] requestIds, uint256 ethReceived)` | `claimLidoWithdrawals` の受領追跡（finalization 完了・自己 idle WETH 増分） |
| LIDO-EVT-004 | `OwnWstETHUpdated(uint256 ownWstETH)` | `_doDeposit` / `requestLidoWithdrawal` / `emergencyWithdrawFromLido` 後の自己 wstETH 残高。AUM の基礎の推移監視 |
| LIDO-EVT-005 | `OwnIdleUnderlyingUpdated(uint256 ownIdleUnderlying)` | `claimLidoWithdrawals` / `_doWithdraw` / `emergencyWithdrawFromLido` / 汎用 `emergencyWithdraw` 後の自己 idle WETH 残高。直接 WETH donation と protocol-owned idle の切り分け |

**監視指標（Lido 固有）**:

- **pending withdraw の滞留**: `pendingWithdrawAmount` と未 claim requestId の経時推移。finalization 遅延が Vault の configured `withdrawDelay` に対して長期化していないかを監視。`pendingWithdrawAmount` は未 claim requestId の記録額合計と一致しなければならない。
- **finalization 状態**: `getWithdrawalStatus(requestIds)` の `isFinalized` / `isClaimed`。finalized 化した要求の claim 漏れ（自己 idle WETH 化されず Vault buffer 補充が遅れる）を検知。finalized 済みでも未 claim の間は request 時記録額で評価されるため、haircut / surplus は claim 実行後の `WithdrawClaimed.ethReceived` で確認する。
- **AUM vs 実回収可能額の乖離**: slashing・stETH デペグ時に `_estimatedTotalUnderlying`（wstETH × `getStETHByWstETH`）が実回収可能額と乖離しうるため subgraph で可視化。`OwnWstETHUpdated` と `getStETHByWstETH` の推移で利回り/毀損を追跡。
- **donation residue**: `WETH.balanceOf(strategy) - min(_ownIdleUnderlying, WETH.balanceOf(strategy))` と `address(strategy).balance` を監視する。これらは backing / yield ではなく、必要時は汎用 `emergencyWithdraw`（WETH のみ）または別 recovery policy で扱う。Lido 固有 emergency や liquidation 判定に混ぜない。
- **Lido プロトコルヘルス**: コンセンサス層 slashing・Withdrawal Queue の混雑（finalization 所要時間）・stETH 二次市場デペグを Lido dashboard / Governance フォーラムで継続ウォッチ。

---

## 12. 失敗時・異常系挙動（ERR）

共通の異常系（流動性不足を正常系として扱う push の整理・**非同期プロトコルの吸収 STGY-ERR-002**・鍵侵害時の被害境界）は [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) を参照。本節では Lido 固有の事象と緩和策のみを記述する。

### LIDO-ERR-001: finalization 遅延・早期 claim 不可

- 契機: Lido Withdrawal Queue の finalization は Lido oracle 報告に依存し、概ね 1〜5 日、混雑時はそれ以上かかる。finalization 前の `claimWithdrawal` は revert する。
- 挙動: 既存 instance の回収中に `claimLidoWithdrawals` を未 finalization 要求へ使うと revert する（LIDO-SEC-005）。自己 idle WETH が積み上がらないため `_doWithdraw` は `0` を返し、`sendToVault` は正常系として `sent = 0`。現行の `withdrawDelay = 3 日` はこの非同期回収を吸収する設定ではない。
- 緩和策: inventory で回収対象が見つかった場合は新規 allocation を停止し、keeper が finalization を監視して finalized 化後に claim → `sendToVault` を実行し、回収完了まで必要な reader / runbook を維持する（LIDO-GOV-002）。旧 17 日設定を Day-1 構成へ戻さない。

### LIDO-ERR-002: MIN/MAX_STETH_WITHDRAWAL_AMOUNT による要求制約

- 契機: Withdrawal Queue は 1 要求あたり最小 `MIN_STETH_WITHDRAWAL_AMOUNT`（mainnet 既定 100 wei）以上・最大 `MAX_STETH_WITHDRAWAL_AMOUNT`（同 1000 stETH）以下しか受け付けない。
- 挙動: `requestLidoWithdrawal` は要求額を MAX 以下の複数 chunk に分割し、各 chunk が MIN 以上になるよう構成する（LIDO-FR-006）。MIN 未満の極小要求は `AmountOutOfRange`。
- 緩和策: 分割ロジックで大口要求を複数 unstETH に展開。極小端数は次回要求にまとめる運用。

### LIDO-ERR-003: stETH slashing・元本毀損

- 契機: Lido のコンセンサス層で大規模 slashing が発生し、wstETH の stETH 換算レート（`getStETHByWstETH` / `stEthPerToken`＝canonical rate）が低下する。
- 挙動: `_estimatedTotalUnderlying()` が canonical rate 低下を反映して下がり、`estimatedTotalUnderlying < principal` となれば `realizedYield()` は 0、Vault の保守評価 `min(estimatedTotalUnderlying, principal)` が下がって `backingRatio()` に下方反映される。
- 緩和策: 会計に現れた毀損は自動で backing へ伝播。会計に現れない/確定的な回収不能分は、回収可能分を `sendToVault` で戻したうえで、GOV が `writeoffStrategyPrincipal`（[CollateralVault 要件定義](../protocol/product/spec/CollateralVault.md) / [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) STGY-FR-004）で `principal` を下方確定する（SYS-RISK-004「loss・writeoff 連動」）。Vault 側 `cap` で集中投下を回避（LIDO-GOV-003）。

### LIDO-ERR-004: Lido / Withdrawal Queue 停止時の緊急回収限界

- 契機: Lido プロトコル / Withdrawal Queue が停止し、`requestWithdrawalsWstETH` / `claimWithdrawal` / `claimWithdrawals` が revert する。
- 挙動: stake 済み元本の ETH 化が不能になり、`emergencyWithdrawFromLido` は idle 分の push までしかできない（stake 済みは即時回収不可。LIDO-FR-008）。
- 緩和策: 既存 instance の回収が必要な場合はこの限界を runbook に明示して回復後に再試行し、回収完了後に登録解除する。

### LIDO-ERR-005: stETH 二次市場デペグ（withdraw レートとの独立）

- 契機: stETH が DEX 等の二次市場で ETH に対しデペグする。
- 挙動: 本 Strategy の回収は Withdrawal Queue（プロトコルレートで ETH を受領）に依存し、二次市場価格では売らないため、**二次市場デペグは本 Strategy の回収額に直接は影響しない**（finalization まで保有して 1:1 相当を受領）。ただし finalization 遅延中は時間価値リスクがあり、デペグの背景にコンセンサス層問題があれば LIDO-ERR-003 として現れうる。
- 緩和策: 回収は常に Withdrawal Queue 経由とし、二次市場での投げ売りはしない。デペグの根因（slashing 懸念等）は LIDO-GOV-003 の監視対象。

**エラーカタログ（Lido 固有）**

| エラー | 契機 |
| --- | --- |
| `ZeroAddress` | `initialize` の `_lido` / `_wstETH` / `_withdrawalQueue` がゼロ |
| `Unauthorized` | ALLOCATOR 以外の `requestLidoWithdrawal` |
| `AmountOutOfRange` | `requestLidoWithdrawal` で MIN/MAX を満たす分割が不能 |
| `LidoWithdrawalRequestTooLarge` | `requestLidoWithdrawal` / `emergencyWithdrawFromLido` の分割後 request 件数が `MAX_LIDO_WITHDRAWAL_REQUESTS_PER_CALL`（32）を超過 |
| `AmountExceedsStaked` | `requestLidoWithdrawal` の要求が自己保有（`min(_ownWstETH, wstETH.balanceOf)` の stETH 換算）を超過 |
| `UnknownRequest` | `claimLidoWithdrawals` に本 Strategy の未 claim 集合に無い requestId を指定 |
| `AsyncRequestClaimTooLarge` | `claimLidoWithdrawals` の requestId 数が `MAX_ASYNC_REQUESTS_PER_CLAIM`（32）を超過 |
| `AsyncPendingRequestLimitExceeded` | `requestLidoWithdrawal` / `emergencyWithdrawFromLido` で未 claim request 総数が `MAX_ASYNC_PENDING_REQUESTS`（128）を超過 |
| `LidoZeroShares` | `_doDeposit` の `lido.submit` → `wstETH.wrap` 後に wstETH が mint されず、元本だけが増える異常を検知 |
| `LidoShareBalanceMismatch` | `_doDeposit` の wstETH `wrap` 返り値と実残高差分が一致しない、または wstETH 残高が不正に減少する会計不整合 |
| `InvalidWstETHStETH` | `initialize` で `wstETH.stETH()` が `_lido` と一致しない |
| `InvalidWithdrawalQueueBounds` | `initialize` で Withdrawal Queue の `MIN_STETH_WITHDRAWAL_AMOUNT` / `MAX_STETH_WITHDRAWAL_AMOUNT` が不正 |
| `ClaimHintsRequired` | hint なし overload に複数 requestId を指定 |
| `WithdrawalQueueRequestMismatch` | Withdrawal Queue が要求 chunk 数と異なる requestId 数を返す、hint 数が requestId 数と異なる等、pending request を安全に追跡できない不整合を検知 |
| `UnexpectedWithdrawalRequestOwner` | Withdrawal Queue が Strategy 自身を owner としない requestId を返した |
| （Withdrawal Queue 由来 revert） | finalization 前 claim・Queue 停止等は Lido コントラクトが revert し伝播（LIDO-ERR-001 / LIDO-ERR-004） |

> 共通エラー（`OnlyVault` / `CannotSweepProtectedToken` / `RenounceOwnershipDisabled` / 共通 `ZeroAddress` / `Unauthorized`）は [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) STGY-ERR-001 を参照。

---

## 13. 受け入れ基準・検証計画

各要件の合格条件 = 下表の検証手段を満たすこと（テスト名・実行結果は本書に書かない＝手段の種別まで）。共通関数（`deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / `emergencyWithdraw` / `sweepRewardToken` / 2-step Owner / UUPS）の検証は [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) を参照。

| ID | 要件（要約） | 検証手段 |
| --- | --- | --- |
| LIDO-FR-001 | initialize（投資先固定・`upgrader` 引数・wstETH/stETH 整合・Queue bounds・stETH→wstETH／wstETH→WQ approve・ゼロ/多重 revert） | unit |
| LIDO-FR-002 | addStrategy 前提（whitelist→`addStrategy`(3 引数)・Underlying=WETH 一致・isAsync 非通知） | integration, manual |
| LIDO-FR-003 | _doDeposit（WETH→ETH→submit→wrap・wstETH 実残高差分計上・返り値不一致 reject・donation 非混入） | unit, fork, invariant=LIDO-INV-001 |
| LIDO-FR-004 | _doWithdraw（自己 idle WETH のみ・`ownIdle==0` で 0・直接 WETH donation 非混入・stETH 不接触） | unit, integration |
| LIDO-FR-005 | _estimatedTotalUnderlying（min・pending bps 算入・端数切り捨て・stETH/wstETH/WETH/raw ETH donation 排除・raw ETH 非算入） | unit, fork, invariant=LIDO-INV-002/005/010 |
| LIDO-FR-006 | requestLidoWithdrawal（ALLOCATOR・requestWithdrawalsWstETH・MIN/MAX 分割・request 件数上限・自己保有上限・requestId owner 確認・pending 記帳・wstETH 減算） | unit, fork, invariant=LIDO-INV-005 |
| LIDO-FR-007 | claimLidoWithdrawals（finalized claim・pending 減算・ETH→WETH 自己 idle 化・raw ETH donation 非混入・未知/二重 claim 拒否・hint 付き batch claim） | unit, fork, invariant=LIDO-INV-005/010 |
| LIDO-FR-008 | emergencyWithdrawFromLido（onlyOwner・自己 idle atomic push・直接 WETH/raw ETH donation 非混入・returned principal 記帳・残 wstETH 要求・引数付き overload の request 額 cap・即時全回収を約束しない・宛先固定） | unit, fork |
| LIDO-FR-009 | setReferral（onlyOwner・次回 submit 反映） | unit |
| LIDO-INV-001..010 | §8 各不変条件 | invariant / fork / unit（§8 記載どおり） |
| LIDO-SEC-001..008 | §9 各セキュリティ要件 | invariant / unit / fork / manual |
| LIDO-EVT-001..005 | §11 各イベント発火 | unit |
| LIDO-ERR-001..005 | §12 Lido 固有異常系 | unit, fork, manual |

**SYS-RISK-004 の 5 必須項目とのトレース**（残存実装と履歴 ID の検証。activation 承認ではない）:

| SYS-RISK-004 の要請 | 充足する要件 |
| --- | --- |
| async 回収トリガ | LIDO-FR-006（requestLidoWithdrawal） |
| pending principal | LIDO-FR-005 / LIDO-INV-005 / LIDO-INV-006（通常時は pendingWithdrawAmount を 10000 bps で AUM 算入・incident freeze 後は bps で保守割引・principal 据え置き） |
| 収益・元本の混同防止 | §7 会計モデル / LIDO-FR-004 / LIDO-INV-006 / LIDO-INV-010（sendToVault・emergency 自己 idle push=元本・sendProfitToVault=収益・pending は principal 不変・donation は yield/principal 非混入） |
| claimable 化 | LIDO-FR-007（claimLidoWithdrawals）＋ Vault VAULT-FR-006（ユーザー claim） |
| loss・writeoff 連動 | LIDO-FR-005 / LIDO-ERR-003（slashing 反映 → writeoffStrategyPrincipal） |

---

## 14. 未決事項（TBD）

### LIDO-TBD-001

Resolved: `LIDO-FR-006`、`LIDO-FR-007` に反映済み。

### LIDO-TBD-002

`referral` の確定値 — ゼロのまま / Lido リファラル登録 / 自前識別子。関連: LIDO-FR-009 / LIDO-FR-003。

### LIDO-TBD-003

Resolved: `LIDO-FR-004`、`LIDO-FR-005`、`LIDO-FR-008`、`LIDO-SEC-002` に反映済み。

### LIDO-TBD-004

Resolved: `LIDO-FR-007` に反映済み。

### LIDO-TBD-005

Resolved: `LIDO-FR-001`、`LIDO-FR-003`、`LIDO-FR-005`、`LIDO-FR-006`、`LIDO-FR-008`、`LIDO-SEC-002`、`LIDO-SEC-006`、`LIDO-SEC-007` に反映済み。

### LIDO-TBD-006

Resolved: `LIDO-FR-003`、`LIDO-FR-006`、[STGY §2.2](../protocol/product/spec/strategies/Strategy.md#22-strategy-採用の必要十分条件) に反映済み。

### LIDO-TBD-007

Resolved: §2 の責務境界と現行値の扱い、LIDO-GOV-001、LIDO-ERR-001 に反映済み。

---

## 15. 参考資料

### 実装

- `contracts/src/Strategies/archive/LidoStrategy.sol`（Lido wstETH 個別 Strategy 本体）

### 関連ページ

- [Strategy 要件定義](../protocol/product/spec/strategies/Strategy.md) — `IStrategy` / `BaseStrategy` / push モデル・共通権限・共通リスク・共通イベント・**STGY-ERR-002 非同期取り扱い**（親ページ・正本）
- [CollateralVault 要件定義](../protocol/product/spec/CollateralVault.md) — whitelist / `addStrategy`(3 引数) / `receiveFromStrategy` / **遅延償還 `claim`（VAULT-FR-006）** / `writeoffStrategyPrincipal` / buffer・cap・weights
- [AaveV3Strategy 要件定義](../protocol/product/spec/strategies/AaveV3Strategy.md) — 同期 Strategy の子ドキュメント実例（donation 耐性 `_ownScaledBalance`〔本書 `_ownWstETH` と同じ「非 rebasing 単位を自己追跡」の思想〕・固有緊急回収の atomic push）
- [Product-Overview](../protocol/product/Product-Overview.md) — アーキテクチャ・責務分離・SYS-NFR-004（可用性・障害耐性）
- [Mainnet Launch Risk Gate](../protocol/launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-004) — async Strategy activation gate
- [Strategy Selection Policy](../protocol/operations/policies/Strategy-Selection-Policy.md#採用分類) — venue の現在の採用状態
- [Oracle 要件定義](../protocol/product/spec/Oracle.md) — WETH underlying branch の想定オラクルは ETH/USD Standard（本選択の影響を受けない）。本 Strategy の AUM 評価が用いる wstETH canonical rate（`getStETHByWstETH` / `stEthPerToken`）は Liquity v2 の wstETH/rETH canonical-rate valuation と同族。production `CompositePriceFeed` は sUSDS 用に pruning 済み
- [要件定義ドキュメント標準](../Requirements-Spec-Standard.md) — 本書が従う標準

### 外部リソース

- [Lido documentation](https://docs.lido.fi/)
- [Lido stETH (Lido.sol)](https://docs.lido.fi/contracts/lido)
- [Lido Withdrawal Queue (WithdrawalQueueERC721)](https://docs.lido.fi/contracts/withdrawal-queue-erc721)
- [Lido deployed contracts](https://docs.lido.fi/deployed-contracts/)
