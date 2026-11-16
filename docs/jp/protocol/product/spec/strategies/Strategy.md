# 🟢 Strategy 個別要件定義

## 0. メタ情報

| 項目             | 値                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Status           | Draft（実装あり・要件の正本化中）                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Owner            | DeltaForesight                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| 対象コントラクト | `contracts/src/Interfaces/IStrategy.sol`（規定インターフェース `IStrategy`）/ `contracts/src/Strategies/BaseStrategy.sol`（抽象基底・UUPS）。active な Strategy はすべて `BaseStrategy` を直接継承し、active scope に async 基底は存在しない（`contracts/src/Strategies/archive/AsyncRequestStrategy.sol` は唯一の subclass 2 件とともに archived。[Contract-Audit-Scope-And-nSLOC](../../../../engineering/guides/Contract-Audit-Scope-And-nSLOC.md) 3.5 節）。具体実装は子ドキュメント（例: [AaveV3Strategy 要件定義](./AaveV3Strategy.md) / [ERC4626Strategy 要件定義](./ERC4626Strategy.md) / [MorphoV2Strategy 要件定義](./MorphoV2Strategy.md)） |
| 関連ドキュメント | [Product-Overview](../../Product-Overview.md)（アーキ・責務分離）/ [CollateralVault](../CollateralVault.md)（allocate / push 受入 / ロール）/ [dToken](../dToken.md)（担保トークン）/ [AaveV3Strategy](./AaveV3Strategy.md)（個別実装）/ [ERC4626Strategy](./ERC4626Strategy.md)（Morpho / Euler 等の ERC-4626 adapter）/ [LidoStrategy](../../../../archive/LidoStrategy.md)（Lido stETH async Strategy）/ [EtherfiWeETHStrategy](../../../../archive/EtherfiWeETHStrategy.md)（Etherfi eETH / weETH async Strategy）/ [Collateral-Asset-Management-Policy](../../../operations/policies/Collateral-Asset-Management-Policy.md)（候補 venue と adapter 対応範囲） |

> 本書は [要件定義ドキュメント標準](../../../../Requirements-Spec-Standard.md)に従う。要件・不変条件・セキュリティ要件には永続 ID（`STGY-…`）を付し、相互参照は ID で行う。本書は全 Strategy に共通する事項のみを規定し、個別 Strategy（Aave V3 / Lido stETH + Withdrawal Queue / Morpho / Euler 等）固有の要件は子ドキュメントに記載する。

---

## 1. 目的・スコープ・非責務

Strategy は、CollateralVault が `allocate` で送った Underlying を **1 つの外部運用先**（Aave V3 / Lido stETH + Withdrawal Queue / Morpho / Euler 等）に対して預け入れ・取り戻し・評価する**運用アダプタ層**（UUPS）。外部プロトコル I/F への変換層であり、回収・収益送付は Strategy 側が主導して Vault へ **push** する（push モデル）。

- **本書が規定する**: Strategy 群に共通する事項 — 規定インターフェース `IStrategy`（[STGY-FR-001](#stgy-fr-001-deposit外部プロトコルへの預入)〜[STGY-FR-008](#stgy-fr-008-view-getterprincipal--realizedyield--estimatedtotalunderlying--underlying)）/ 基底 `BaseStrategy`（共通会計・`principal` 管理・hook 規約）/ `AsyncRequestStrategy`（Lido / Etherfi 等の async requestId・pending amount・自己 idle Underlying 共通会計）/ 共通権限設計（ALLOCATOR / Owner / upgrader の境界）/ 共通監視・イベント方針 / 共通リスク。
- **本書が規定しない（非責務・他文書）**:
  - buffer / cap / weights に基づく「どの Strategy にいくら送るか」の決定（`allocate`）・Strategy への Underlying 引き渡し・push 受入口 `receiveFromStrategy`・元本毀損の確定 `writeoffStrategyPrincipal`・第 2 段 `transferYieldToTreasury`・ロール定義（`ALLOCATOR_ROLE` 等）の正本 → [CollateralVault 要件定義](../CollateralVault.md)
  - 各個別 Strategy の外部プロトコル固有要件（追加ストレージ / hook 実装 / 固有の緊急回収関数 / 報酬トークン / 固有リスク） → 子ドキュメント（例: [AaveV3Strategy 要件定義](./AaveV3Strategy.md)）
  - 担保トークン dToken の仕様 → [dToken 要件定義](../dToken.md)
  - 担保別の mintCap / buffer / allocator / withdrawDelay の Day-1 値 → [Parameters](../../../../Parameters.md)
  - Strategy venue の採用状態 → [Strategy Selection Policy](../../../operations/policies/Strategy-Selection-Policy.md)
  - Day-1 の登録kind・cap・weight → [Mainnet Deploy Env Freeze Runbook](../../../launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md) と生成Manifest
  - deploy mode・wiring shape・Manifest schema → [Deployment Configuration Spec](../../../../engineering/guides/Deployment-Configuration-Spec.md)
  - 🔵 Liquity コアの担保・清算・Redemption 挙動 → [Liquity-v2-Core-Spec](../Liquity-v2-Core-Spec.md)
  - 各候補プロトコルの adapter 対応範囲・運用先候補の整理 → [Collateral-Asset-Management-Policy](../../../operations/policies/Collateral-Asset-Management-Policy.md)
  - 外部運用先を採用してよいかの risk / governance / monitoring gate → [Strategy-Selection-Policy](../../../operations/policies/Strategy-Selection-Policy.md)
- **責務境界（あえて知らない）**: 個別 Strategy は「受け取った Underlying を 1 つの外部プロトコルにどう預け、どう取り戻し、いくらの価値があるか」のみに責任を持つ。Vault 側の配分判断・buffer 会計・宛先決定は知らない。外部プロトコルの内部状態も知らず、その I/F を呼び出すだけである。

---

## 2. 背景・設計方針

Strategy 層は **Liquity v2 コアを無改変のまま使う** dToken 担保モデルの「運用先アダプタ」として一貫している。コア無改変の全体方針・dToken がコアの担保である背景は [Product Overview](../../Product-Overview.md) §5 を正本とする。

- **push モデル（回収は Strategy 主導）**: Vault は Strategy から資金を pull しない。元本返却・cache reconciliation 系（`sendToVault` / 固有 `emergencyWithdrawFrom{Protocol}` / 汎用 idle `emergencyWithdraw`）は `receiveFromStrategy` 経由で Vault buffer へ push する。declared と Vault 実受領が一致する通常系では valuation cache を実受領額分減額し、fee-on-transfer / rebase 等で一致しない場合は upstream position 減少を receipt だけから確定できないため cache を無効化する。収益のみ（`sendProfitToVault` / Underlying reward claim）は Strategy が Vault buffer へ直接 `safeTransfer` し、principal と valuation cache を動かさない。
- **`principal` の自己管理**: 各 Strategy は投下元本 `principal` を自身で帳簿管理する。`principal` は外部プロトコルでの観測値ではなく、Vault が送った額（`deposit` 引数）で加算し、通常回収（`sendToVault`）および固有緊急回収（`emergencyWithdrawFrom{Protocol}`）で Vault が実受領した額を減算する（後述の principal-first / `sent` ベース減算）。これにより `principal` と Vault buffer の乖離を防ぐ。
- **保守的評価**: AUM 評価 `estimatedTotalUnderlying()` は過大評価だと収益取りすぎを招くため保守的に行い、Vault 側は `min(estimatedTotalUnderlying, principal)` でソルベンシー評価と `managedUnderlying` 評価を行う。これは価格 oracle ではなく、当 Strategy が外部プロトコルから回収可能と見積もる Underlying 建て評価額である。収益送付は Strategy 側の `realizedYield()` 上限と Vault 側の `managedUnderlying` surplus + buffer 上限（`transferYieldToTreasury`）の二重で防御する。
- **同期/非同期は実装内に閉じる**: 外部プロトコルが同期（即時引き出し可）か非同期（unbond 等の待機を要する）かの違いは Strategy 実装内部に閉じ、`IStrategy` 表層では区別しない。非同期な外部プロトコルは `_doWithdraw` の内部で「その時点で即時に引き出せる額のみ返す」ことで吸収する（[STGY-FR-002](#stgy-fr-002-sendtovault元本回収の-push) / [STGY-ERR-002](#stgy-err-002-非同期な外部プロトコルの取り扱い)）。これにより Vault 側は `requestKey` 保持・`isAsyncWithdraw` 分岐・非同期清算経路（`claimWithdraw` / `claimHarvest` 相当）を持たず、非同期元本回収の清算経路欠落や「収益 claim が requestKey の用途を検証しない」といった課題は構造的に発生しない。元本/収益の区別と `principal` 会計は Strategy 側に閉じ、Vault は元本返却・cache 減額系を `receiveFromStrategy`、収益のみを直接 buffer 着金として受ける。
- **共通実装は BaseStrategy / AsyncRequestStrategy へ集約**: `deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` の本体と push モデルの会計・`principal` 管理は `BaseStrategy`（abstract, UUPS）が提供し、派生クラスは hook（`_doDeposit` / `_doWithdraw` / `_estimatedTotalUnderlying`）のみを実装する。Lido / Etherfi のように request / claim を持つ async Strategy は `AsyncRequestStrategy` を継承し、未 claim requestId 集合、`pendingWithdrawAmount`、claim 済み自己 idle Underlying の追跡を共通化する。これにより会計ロジックを 1 箇所に集約し、外部プロトコルごとの差分を hook と request/claim I/F に局所化する。
- **デプロイ単位 = 1 Underlying × 1 外部運用先**: 1 つの Strategy インスタンス = 1 つの Underlying = 1 つの外部運用先。同じ外部プロトコルでも Underlying が異なれば別インスタンスをデプロイする。1 つの CollateralVault に複数 Strategy インスタンスを `addStrategy` で登録できる。
- **運用先なし branch は Strategy を登録しない**: Day-1 に外部運用先を採らない branch（inert branch 2–7 等）は `DeployLiquity2` の `DF_STRATEGY_KIND_i=none` で Strategy デプロイ / Vault 登録を明示的にスキップできる。この場合、Vault は Underlying を buffer / backstop として保有し、`allocate` は登録 Strategy なしで早期 return する。`none` は `IStrategy` 実装ではなく deploy 構成値であり、weight / cap は 0 固定とする。
- **子ドキュメントへの分離**: 個別 Strategy の章立ては §15 に規約として保全する。共通事項は本書を参照させ、子ドキュメントには外部プロトコル固有事項のみを書く。

### 2.1 Strategy kind 別の運用差分

`IStrategy` 表層は共通だが、`estimatedTotalUnderlying()` の意味、`sendToVault` で即時に戻せる資産、writeoff 前に確認すべき外部状態は Strategy kind ごとに異なる。branch symbol ではなく、登録されている Strategy 実装で判断する。

| Strategy kind                      | 実装状態                                      | valuation に含むもの                                                                               | `sendToVault` が即時回収できるもの                                                                                                    | loss と誤認しやすいもの                                                                                            | residual writeoff 前の確認                                                                                                  |
| ---------------------------------- | --------------------------------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- |
| Aave V3                            | 実装済み `AaveV3Strategy.sol`                 | 自己 `_ownScaledBalance` と Aave `scaledBalanceOf(this)` の小さい方 × `getReserveNormalizedIncome` | Aave reserve の liquid underlying まで。`emergencyWithdrawFromAave` も liquid 分を Vault へ原子直送し returned principal 記帳         | reserve utilization / aToken 側の一時流動性不足。Aave 会計値に出ない reserve deficit / bad debt                    | Aave official reserve status、scaled balance / normalized income、実回収 tx、残存 Aave-accounted value                      |
| ERC-4626                           | 実装済み `ERC4626Strategy.sol`                | 自己 `_ownShares` と share `balanceOf(this)` の小さい方を `convertToAssets`                        | `maxWithdraw` / `maxRedeem` の範囲。`emergencyWithdrawFromERC4626` は redeem 可能 share を Vault へ原子直送し returned principal 記帳 | `maxWithdraw` / queue / vault pause による一時 illiquidity。share price 低下は既に valuation loss に出る場合がある | share price / `convertToAssets`、max withdraw/redeem、curator・market bad debt、既に valuation に出ている loss との二重計上 |
| Lido                               | 実装済み `LidoStrategy.sol`                 | 自己 wstETH の canonical stETH 換算 + `pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000` + claim 済み自己 idle WETH | claim 済み自己 idle WETH のみ。stake 済み分は `requestLidoWithdrawal` → finalization → `claimLidoWithdrawals` が先。直接 WETH/raw ETH donation は backing として扱わない | Withdrawal Queue 待ち、stETH DEX depeg、claim 未実行。これらは単独では principal loss ではない                     | requestId / pending amount、pending valuation bps、finalization 状態、claim 実受領 ETH、自己 idle WETH、canonical rate / slashing 反映、queue 待ち・donation residue を確認し、回収後に登録解除 |
| Sky USDC/sUSDS                    | 実装済み `SkyUsdcSUsdsStrategy.sol`           | 自己 sUSDS share の USDS 建て value + 自己 idle USDS を converter preview で USDC 建てへ保守換算    | route が halt していない場合の `sUSDS -> USDS -> USDC` 同期変換分。converter 停止時は USDS redeem と後続 convert を分けられる           | PSM / LitePSM / converter halt、route slippage、USDS depeg、sUSDS share price 低下。quote unavailable は即 loss ではない | converter preview、max conversion loss、USDS idle、sUSDS share、実 USDC 回収額、保守 quote と principal の差                |
| Etherfi weETH                     | 実装済み `EtherfiWeETHStrategy.sol`           | 自己 weETH の eETH/WETH 換算 + `pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000` + claim 済み自己 idle WETH | claim 済み自己 idle WETH のみ。weETH position は `requestEtherfiWithdrawal` -> finalization -> `claimEtherfiWithdrawals` が先           | WithdrawRequestNFT 待ち、weETH/eETH rate 変動、LRT/slashing/depeg、claim 未実行。これらは単独では principal loss ではない | requestId / pending amount、pending valuation bps、finalization 状態、claim 実受領 ETH、自己 idle WETH、weETH rate、NFT/donation residue |
| none                               | deploy 構成値。Strategy contract は存在しない | Vault の buffer / backstop のみ                                                                      | 対象なし。`allocate` は登録 Strategy なしで早期 return                                                                                 | deploy し忘れとの混同。env `DF_STRATEGY_KIND_i=none` / weight 0 / cap 0、manifest `strategies[]` 空、登録 Strategy 数 0 を確認する | Strategy incident ではなく担保そのもの・oracle・Vault buffer の問題として扱う                                             |

共通の `BaseStrategy.emergencyWithdraw(amount)` は **直接保有している Underlying の救済**であり、`principal` を減算しない。外部プロトコルからの principal 回収は、可能な限り各 Strategy 固有の `emergencyWithdrawFrom{Protocol}` または `sendToVault` を使い、Vault 実受領額を returned principal として記帳する。Base の idle 救済を upstream principal 回収の代替に使った場合、`principal` が残るため、残額の評価・writeoff 判断を incident log に明示する。

### 2.2 Strategy 採用の必要十分条件

Strategy は、外部運用先ごとに安易に増やさない。既存 kind で以下をすべて満たせる場合、その kind を採用し、新規 Strategy は追加しない。

1. Strategy の `underlying()` が対応 Vault の Underlying と一致する。
2. 外部運用先への deposit / withdraw が、既存 kind の責務内で表現できる。
   - Aave V3 reserve → `AaveV3Strategy`
   - `asset() == underlying` の ERC-4626 vault → `ERC4626Strategy`
   - WETH を Lido wstETH + Withdrawal Queue へ預ける WETH underlying branch → `LidoStrategy`
   - WETH を Etherfi eETH/weETH + WithdrawRequestNFT へ預ける WETH underlying branch → `EtherfiWeETHStrategy`
   - USDC を Sky USDS/sUSDS へ預け、USDC 建てで回収する dUSDC branch → `SkyUsdcSUsdsStrategy`
   - 外部運用先なし → `none`
3. `estimatedTotalUnderlying()` を Underlying 建てで保守的に返せる。
4. `sendToVault` / 固有 `emergencyWithdrawFrom{Protocol}` が、回収可能分を同じ Underlying として Vault に push できる。
5. position / receipt token と reward token の保護・sweep 境界が既存 hook で表現できる。
6. deploy / preflight / runbook が対象 kind の外部 address と risk を freeze できる。

以下のいずれかに該当する場合だけ、新規 Strategy を設計する。

- Underlying と異なる asset へ変換して運用する（例: USDC -> USDS -> sUSDS、WETH -> eETH/weETH）。
- 中間 token / route quote / min-out / converter halt / depeg を Strategy 内部で追跡する必要がある。
- request / claim / NFT / queue 等の非同期状態を既存 Strategy で表現できない。
- `estimatedTotalUnderlying()` が外部 route や複数 asset の保守換算に依存する。
- 緊急回収が単一 withdraw/redeem ではなく、protocol 固有の複数段階になる。

したがって、Morpho / EulerEarn のような `asset()==underlying` の ERC-4626 vault は ERC4626Strategy で十分であり、venue 名だけを理由に専用 adapter を作らない。一方、Etherfi / weETH や dUSDC branch の sUSDS 運用は `EtherfiWeETHStrategy` / `SkyUsdcSUsdsStrategy` のような asset-transforming Strategy として扱う。self-appreciating Underlying の canonical rate 増価は borrower の担保価値とし、外部 Strategy による Underlying 数量増加とは会計上分ける。

### 2.3 Deploy selector / 複数 Strategy 初期登録

`DeployLiquity2` の Strategy selector は `aave` / `erc4626` /
`etherfi-weeth` / `sky-susds` / `none` を採用可能な値として扱う。現行 code は legacy
`lido` selector も認識する。単一 Strategy branch は
`DF_STRATEGY_KIND_i` / `DF_STRATEGY_WEIGHT_BPS_i` / `DF_STRATEGY_CAP_i` を読む。
1 branch に複数 Strategy を初期登録する場合は `DF_STRATEGY_COUNT_i=N` を設定し、
`DF_STRATEGY_KIND_i_j` / `DF_STRATEGY_WEIGHT_BPS_i_j` / `DF_STRATEGY_CAP_i_j`
および kind 固有 env の `..._i_j` を使う。`none` は配列形式には入れず、単独 branch の
「外部運用先なし」だけを表す。

Deployment manifest は全 Strategy を `dfYield[i].strategies[]` にだけ出す。fresh deploy
方針のため、互換用 top-level `strategy` / `strategyKind` / `strategyWeightBps` /
`strategyCap` は出力しない。deploy-tail verification は Vault 登録数、primary strategy、
各 Strategy の `vault()` / `underlying()`、total weight を確認する。governance prepare /
verify / accept helper は manifest の `strategies[]` 件数と live Vault の登録 Strategy
一覧を照合するため、secondary Strategy も owner / upgrader handover 対象になる。

### 2.4 外部接続先 address の更新方針

Aave Pool / aToken、ERC-4626 vault、Lido 三点セット、Etherfi LiquidityPool / weETH /
WithdrawAdapter / WithdrawRequestNFT、Sky converter / sUSDS vault などの外部接続先 address は、
各 Strategy の `initialize` で固定する。通常の運用中に `setPool` / `setVault` /
`setWithdrawalQueue` のような setter で差し替えない。接続先を変える必要がある場合は、新しい
Strategy proxy をデプロイし、Vault 側で `addToWhitelist` → `addStrategy` / `updateStrategy`
→ 旧 Strategy の `sendToVault`・固有 emergency・`writeoffStrategyPrincipal`（必要時）
→ `removeStrategy` の順で入れ替える。

この入替は旧 Strategy proxy の implementation upgrade や migration setter を必要としない。新旧 Strategy を同時に
登録できるため、旧側を weight 0 / disabled にして新規 allocation を止めたまま、同期 venue は同一 tx の emergency 回収、
非同期 venue は request / claim 完了まで旧 proxy を登録状態で残せる。`removeStrategy` は旧 Strategy の `principal == 0` かつ
`estimatedTotalUnderlying() == 0` を on-chain で要求するため、position を残したまま登録だけを外すことはできない。

理由は、接続先 setter が「Owner が資金の行き先を後から変える」攻撃面になり、allowance・
storage layout・外部 protocol invariant の再検証範囲を広げるためである。さらに position share、自己保有量 ledger、
async requestId / NFT、token allowance は旧 venue graph に束縛されており、address だけを上書きすると旧 position の
valuation / claim / protected-token 境界を失い得る。core branch 用で one-shot の `AddressesRegistry` を複数 Strategy の
可変 venue registry として再利用しない。将来どうしても setter 型の
更新が必要な protocol は、Strategy 単体ではなく upgrade 設計・timelock・preflight・runbook を含む
別要件として扱う。

既存 proxy へ implementation だけを差し替える場合は、Solidity 継承順と storage layout の互換性を
個別に証明する必要がある。特に `AsyncRequestStrategy` のような共通基底へ会計 storage を移す変更は、
既存の個別 Strategy 実装と layout が一致するとは限らない。mainnet 前の pre-deploy / local 環境で
layout 互換を前提にしない変更を入れる場合も、運用上は fresh Strategy proxy をデプロイして Vault 登録を
入れ替える。

---

## 3. 用語・外部依存・前提

**用語**

| 用語                       | 意味                                                                                                                                    |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Underlying                 | Strategy が運用する実資産（WETH / USDC 等）。dToken がラップする対象と同一                                                              |
| vault                      | この Strategy を登録し、`allocate` / push 受入を行う対応 CollateralVault                                                                |
| 外部プロトコル             | 運用先本体（Aave V3 / Lido stETH + Withdrawal Queue / Morpho / Euler 等）。Strategy は I/F を呼ぶだけ                                   |
| `principal`                | 当 Strategy が自己管理する投下元本（帳簿値）                                                                                            |
| `estimatedTotalUnderlying` | 当 Strategy が外部プロトコルで運用中の Underlying 建て評価額（保守的評価）。価格 oracle ではなく、Vault の `A = totalUnderlying()` 入力 |
| `realizedYield`            | `max(estimatedTotalUnderlying − principal, 0)`。未実現収益の上限                                                                        |
| push モデル                | Strategy が引き出した Underlying を `receiveFromStrategy` 経由で Vault へ push する回収方式                                             |
| hook                       | 派生クラスが実装する外部プロトコル変換点（`_doDeposit` / `_doWithdraw` / `_estimatedTotalUnderlying`）                                  |
| 同期 / 非同期              | 外部プロトコルが即時引き出し可（同期）／ unbond 等の待機を要する（非同期）                                                              |
| Owner                      | Strategy の緊急操作主体（Guardian multisig・即時のマルチシグ。2026-06-12 確定）                                                         |
| upgrader                   | UUPS アップグレード承認の専用権限（Owner から分離。holder = 共通 TimelockController）                                              |
| ALLOCATOR                  | Vault の `ALLOCATOR_ROLE` 保持者。Strategy の `sendToVault` / `sendProfitToVault` を起動                                                |

**外部依存（信頼する外部）**

- **対応 CollateralVault** — `onlyVault` 関数（`deposit` / `writeoffPrincipal`）の唯一の呼出元、push 受入口 `receiveFromStrategy` の提供元、`ALLOCATOR_ROLE` 等の AccessControl の参照先として信頼する。ロール定義の正本は [CollateralVault 要件定義](../CollateralVault.md)（ロール定義）。
- **外部プロトコル**（Aave V3 / Sky USDS-sUSDS / Lido stETH + Withdrawal Queue / Etherfi eETH-weETH / Morpho / Euler 等） — supply / stake / transform / withdraw の I/F を信頼して呼び出す。スマコン・経済攻撃リスクは §6（共通リスク）／子ドキュメントで扱う。
- **OpenZeppelin Contracts (upgradeable)** — `OwnableUpgradeable` / UUPS（`BaseStrategy` の Ownable・UUPS 初期化・アップグレード authorization）。

**前提**

- Strategy の Underlying は対応 Vault の Underlying と一致する（Vault の `addStrategy` が `strategy.underlying() == vault.underlying()` を on-chain 検証する。[CollateralVault 要件定義](../CollateralVault.md) `addStrategy`）。
- 投下方向の `safeTransfer` は `deposit` 呼び出しの**直前**に Vault が行う（Underlying は `deposit` 受領時点で既に Strategy 残高にある）。
- 現行 source のうち Aave V3 / ERC-4626 / Sky USDC-sUSDS / Mock は同期引き出し、Lido stETH / Etherfi weETH Strategy は非同期引き出しを Strategy 内部に閉じる。いずれも `IStrategy` 表層と Vault 登録 I/F は共通である（[STGY-ERR-002](#stgy-err-002-非同期な外部プロトコルの取り扱い)）。

---

## 4. アクター・ロール・信頼境界

ロール定義は [CollateralVault 要件定義](../CollateralVault.md)（ロール定義）を正本とする。Strategy 単体に対する操作権限の集約:

| アクター                                | 操作                                                                                                                                                                                                                                                                                             | 信頼境界                                                                                                                                                                                                                                                                                                                 |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Owner（Guardian multisig）**          | `initialize`（デプロイ直後 1 度のみ）/ `emergencyWithdraw`（直接保有分を Vault へ救済）/ `sweepRewardToken`（非 Underlying・非 position 報酬を Treasury へ送付）/ `claimMerklRewards`（Merkl claim + 宛先固定 settlement）/ 固有の緊急回収関数（`emergencyWithdrawFrom{Protocol}()`）/ `transferOwnership` | 緊急操作の即時主体。可能な操作は宛先固定の fail-safe（Vault への返送・Underlying reward の Vault 精算・通常 reward の Treasury sweep）に限られる。必ずマルチシグ。Owner 移譲は 2-step、`renounceOwnership` は無効化。被害境界は [STGY-SEC-002](#stgy-sec-002-owner-鍵侵害時の被害境界)                                                                              |
| **upgrader（共通 TimelockController）** | UUPS `upgradeTo`・`upgradeToAndCall`（`_authorizeUpgrade`）                                                                                                                                                                                                                                      | `upgradeTo` による悪意 Implementation 差し替えが最大の脅威のため、承認権限を Owner から分離し holder を共通 TimelockController にする。upgrader の再指定は upgrader 自身（= Timelock 経由・遅延）のみ可能で、Owner からは変更できない（分離の無効化防止、[STGY-FR-009](#stgy-fr-009-アップグレードuups)） |
| **pendingOwner**                        | `acceptOwnership`                                                                                                                                                                                                                                                                                | Owner が指定した移譲候補。承諾するまで Owner 権限は移らない                                                                                                                                                                                                                                                              |
| **vault（対応 CollateralVault）**       | `deposit`（`allocate` から Vault が呼ぶ）/ `writeoffPrincipal`（`writeoffStrategyPrincipal` から呼ぶ）= いずれも `onlyVault`                                                                                                                                                                     | 完全信頼。`initialize` で固定                                                                                                                                                                                                                                                                                            |
| **ALLOCATOR（Vault ロール）**           | `sendToVault` / `sendProfitToVault`（Strategy を直接呼ぶ。Strategy が Vault の AccessControl を参照して検証）                                                                                                                                                                                    | 資金は **Vault へ push** されるのみ・任意アドレスへは送れない。被害境界は [STGY-SEC-001](#stgy-sec-001-allocator-鍵侵害時の被害境界)                                                                                                                                                                                     |
| **WRITEOFF（Vault ロール）**            | async Strategy の `setPendingWithdrawalValuationBps`（Strategy が Vault の AccessControl と `pausedAllocation` を参照して検証）                                                                                                                                                                     | pending async withdrawal の valuation を下げられる price-moving 操作。下方変更は `pausedAllocation == true` の incident freeze 後のみ可能で、復元・上方変更は復旧時に詰まらないよう pause 不要。資金は移動しないが backing に効くため、高定足数 GOV multisig の即時ロールに限定する。被害境界は [STGY-SEC-004](#stgy-sec-004-aum-過大評価への保守的会計) |
| **任意（permissionless）**              | `principal` / `realizedYield` / `estimatedTotalUnderlying` / `underlying`（view）                                                                                                                                                                                                                | 信頼不要                                                                                                                                                                                                                                                                                                                 |

- **権限分離**: ALLOCATOR は元本/収益の **push 回収**のみを起動でき、宛先（Vault）・比率は事前固定。`deposit`（外部プロトコルへの預入）は `onlyVault` で Vault 経由に限定される。Owner は `emergencyWithdraw` で直接保有分を Vault へ救済できるが、送金先は Vault 固定で任意 `_to` を持たない（[STGY-SEC-003](#stgy-sec-003-emergencywithdraw-の送金先-vault-固定)）。`sweepRewardToken` は非 Underlying・非 position 報酬だけを Vault の現在 `treasury` へ送る。`claimMerklRewards` は Underlying reward を Vault buffer へ、非 Underlying の通常 reward を Vault の現在 `treasury` へ精算し、非 Underlying の protocol position / receipt / accounting token は Merkl distributor 呼び出し前に fail-fast で拒否する。async pending valuation の markdown は Owner / ALLOCATOR ではなく Vault `WRITEOFF_ROLE` のみで、下方変更は Vault `pausedAllocation` 後に限る。UUPS upgrade は Owner ではなく dedicated `upgrader` のみが承認する。

---

## 5. インターフェース仕様

規定インターフェース `IStrategy`（および `BaseStrategy` 抽象基底・UUPS 標準）。挙動は §6 機能要件、可視性のみ以下に要約（非規範）。各 Strategy 実装は本表の必須メソッドをすべて満たす。

| 関数                                                                                                                                 | 可視性                                 | 要約                                                                                                                | 規定要件    |
| ------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ----------- |
| `deposit(uint256 _declaredAmount, uint256 _receivedAmount) → uint256 deposited`                                                      | external (onlyVault)                   | 外部プロトコルへ預入して純受領額を返す。reject 時は exact recovery 後に 0 を返す                                  | STGY-FR-001 |
| `deployUnderlying(uint256 _amount)`                                                                                                  | external (self-only)                   | `_doDeposit` を隔離 call frame で実行。外部 caller は `Unauthorized`                                               | STGY-FR-001 |
| `sendToVault(uint256 _amount) → uint256 sent`                                                                                        | external (ALLOCATOR)                   | 元本回収の push。`_doWithdraw`→`receiveFromStrategy`→`principal` 減算                                               | STGY-FR-002 |
| `sendProfitToVault() → uint256 sent`                                                                                                 | external (ALLOCATOR)                   | realized 収益のみを Vault buffer へ直接 push。`principal` 不変                                                       | STGY-FR-003 |
| `writeoffPrincipal(uint256 _amount) → uint256 writtenOff`                                                                            | external (onlyVault)                   | 元本毀損の確定。`principal -= min(_amount, principal)`、実 writeoff 額を返す                                        | STGY-FR-004 |
| `emergencyWithdraw(uint256 _amount)`                                                                                                 | external (onlyOwner)                   | 直接保有分を Vault へ救済（送金先 Vault 固定）                                                                      | STGY-FR-005 |
| `sweepRewardToken(IERC20 token, uint256 amount) → uint256 swept`                                                                     | external (onlyOwner)                   | 非 Underlying・非 position 報酬を Vault の現在 Treasury へ送付                                                      | STGY-FR-010 |
| `claimMerklRewards(IMerklDistributor distributor, address[] tokens, uint256[] amounts, bytes32[][] proofs) → uint256[] settledAmounts` | external (onlyOwner)                   | Merkl distributor から当 Strategy 分を claim し、非 Underlying・非 position 報酬は Treasury、Underlying 報酬は Vault へ精算 | STGY-FR-012 |
| `principal() → uint256`                                                                                                              | external view                          | 自己管理する投下元本                                                                                                | STGY-FR-008 |
| `realizedYield() → uint256`                                                                                                          | external view                          | `max(estimatedTotalUnderlying − principal, 0)`                                                                      | STGY-FR-008 |
| `estimatedTotalUnderlying() → uint256`                                                                                               | external view                          | 外部プロトコル運用中の Underlying 評価額（保守的）                                                                  | STGY-FR-008 |
| `underlying() → address`                                                                                                             | external view                          | 当 Strategy の Underlying アドレス                                                                                  | STGY-FR-008 |
| `_doDeposit(uint256 amount)`                                                                                                         | internal (hook, 派生で実装)            | 外部プロトコルへ supply / stake                                                                                     | STGY-FR-006 |
| `_doWithdraw(uint256 amount) → uint256 actual`                                                                                       | internal (hook, 派生で実装)            | 外部プロトコルから Strategy 自身へ引き出し（実額返却）                                                              | STGY-FR-006 |
| `_estimatedTotalUnderlying() → uint256`                                                                                              | internal (hook, 派生で実装)            | 外部プロトコル保有資産を Underlying 換算（保守的）                                                                  | STGY-FR-006 |
| `__BaseStrategy_init(address _vault, address _underlying, address _owner, address _upgrader)`                                        | internal (init)                        | Ownable/UUPS 初期化・ゼロ / contract code チェック・`forceApprove(vault, max)`・upgrader 固定                       | STGY-FR-007 |
| `initialize(...)`                                                                                                                    | external (initializer)                 | 派生: BaseStrategy 初期化＋追加ストレージ＋事前 approve                                                             | STGY-FR-007 |
| `_authorizeUpgrade(address newImpl)`                                                                                                 | internal (upgrader のみ)               | UUPS 承認（upgrader = 共通 Timelock。Owner から分離）                                                               | STGY-FR-009 |
| `setUpgrader(address _newUpgrader)`                                                                                                  | external (upgrader のみ)               | upgrade 承認権限の付替え（非ゼロ必須・`UpgraderUpdated` 発火）                                                      | STGY-FR-009 |
| `pendingOwner()` / `transferOwnership(address)` / `acceptOwnership()` / `renounceOwnership()`                                        | public                                 | 2-step Owner 移譲 / renounce 無効化                                                                                 | STGY-FR-011 |
| `emergencyWithdrawFrom{Protocol}()`                                                                                                  | external (onlyOwner, 派生固有)         | 外部プロトコルから回収可能分を引き出し、同一 Tx で Vault へ原子直送。Vault 実受領額を returned principal として記帳 | STGY-FR-005 |

`emergencyWithdrawFrom{Protocol}` は仕様上の抽象表記であり、`IStrategy` の共通関数名ではない。実装では派生 Strategy ごとの具体名（例: `emergencyWithdrawFromAave`, `emergencyWithdrawFromLido`, `emergencyWithdrawFromERC4626`, `emergencyWithdrawFromSky`）を使う。監査・SPECA などの property mapping では、抽象表記を literal な `emergencyFromProtocol` / `emergencyWithdrawFromProtocol` として検索しない。

### 5.1 コンポーネント関係（参考図）

```text
[配分] allocate（Vault → Strategy）
  CollateralVault (per Underlying)
    │ ① safeTransfer(strategy, amount)   (Vault → Strategy へ Underlying を先送り)
    │ ② strategy.deposit(declared, received)
    ▼
  IStrategy 実装 (per Underlying, UUPS)
    │ ③ self-call 内で外部プロトコルへ supply / stake
    │   reject → inner frame rollback → exact recovery to Vault → 0 return
    ▼
  外部プロトコル (Aave V3 / Lido stETH/WQ / Morpho / Euler / ...)

[元本回収] push（Strategy → Vault）
  ALLOCATOR が strategy.sendToVault(amount)
    │ ④ 外部プロトコルから引き出し（_doWithdraw、Strategy 自身へ）
    │ ⑤ vault.receiveFromStrategy(actual)（Vault が safeTransferFrom で buffer へ引き取り、cache を減額）
    ▼
  CollateralVault buffer

[収益回収] yield-only push（Strategy → Vault）
  ALLOCATOR が strategy.sendProfitToVault()
    │ ⑥ 外部プロトコルから realized yield を引き出し（_doWithdraw、Strategy 自身へ）
    │ ⑦ Strategy が Vault buffer へ直接 safeTransfer（principal / cache は不変）
    ▼
  CollateralVault buffer
```

| レイヤー          | 責務                                                                                                                                                                                                                                             |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| CollateralVault   | buffer / cap / weights に基づき配分先・額を決定（`allocate`）。Strategy への Underlying 引き渡し（safeTransfer）と `deposit` 呼び出し。元本返却系 push 受入口 `receiveFromStrategy`（実受領額を残高差分で計上し、exact delivery は cache 減額、mismatch は cache 無効化）。元本毀損の確定 `writeoffStrategyPrincipal` |
| **個別 Strategy** | 受け取った Underlying を 1 つの外部プロトコルへどう預け・取り戻し・評価するか。外部プロトコル I/F の変換層。元本回収は Strategy 主導で `receiveFromStrategy` へ push（`sendToVault` / 固有緊急回収）。収益回収は Vault buffer への直接 transfer（`sendProfitToVault` / Underlying reward claim）。投下元本 `principal` を自己管理 |
| 外部プロトコル    | 運用先本体。Strategy はその I/F を呼ぶだけで内部状態は知らない                                                                                                                                                                                   |

---

## 6. 機能要件（FR）

> 会計の基準は Strategy が自己管理する `principal` と外部プロトコル評価額 `estimatedTotalUnderlying()` であり、`realizedYield() = max(estimatedTotalUnderlying() − principal, 0)`。`deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` の本体は `BaseStrategy`（[STGY-FR-007](#stgy-fr-007-basestrategy-初期化-__basestrategy_init--派生-initialize)）が提供し、派生クラスは hook（`_doDeposit` / `_doWithdraw` / `_estimatedTotalUnderlying`、[STGY-FR-006](#stgy-fr-006-派生-hookdodeposit--dowithdraw--estimatedtotalunderlying)）のみを実装する。

### STGY-FR-001: deposit（外部プロトコルへの預入）

- **Type**: Functional ｜ **Source**: Product-Overview「Strategy Layer」/ push モデル
- **シグネチャ**: `deposit(uint256 _declaredAmount, uint256 _receivedAmount) returns (uint256 deposited)`
- **目的**: Vault が `allocate()`（[CollateralVault 要件定義](../CollateralVault.md)）で Strategy へ Underlying を `safeTransfer` した**直後**に呼ばれ、受領済みの Underlying を外部プロトコルへ預け入れる。BaseStrategy が本体を提供。
- **権限**: `onlyVault`（Vault 以外は `OnlyVault` で revert）。
- **事前条件（Checks）**: `caller == vault`。Underlying は本関数の呼び出し**前**に Vault → Strategy へ渡っている（push モデルの預入）。`_declaredAmount` は Vault buffer から減った額、`_receivedAmount` は Strategy の残高差分で測った純受領額。
- **動作（Effects）**:
  1. `onlyVault` 検証
  2. `_receivedAmount == 0` の場合、`_declaredAmount == 0` のときだけ状態を変えず `0` を返す。宣言額が非 0 なら、焼却や 100% fee の往路送金を skip として隠さないよう `DepositRecoveryFailed` で revert
  3. self-only `deployUnderlying(_receivedAmount)` を外部 self-call し、その call frame 内で `_doDeposit(_receivedAmount)` を実行
  4. 成功時は `principal += _receivedAmount`、`Deposited(_receivedAmount, principal)` を発火し `_receivedAmount` を返す
  5. reject 時は inner call frame の全効果が巻き戻った後、`_declaredAmount == _receivedAmount` を確認し、Strategy と Vault の回復前残高を記録して `_receivedAmount` を Vault へ直接返送する。Strategy 減少額・Vault 増加額がともに `_receivedAmount` と一致するときだけ `0` を返す
- **revert / 早期 return**: 非 vault → `OnlyVault`；外部から `deployUnderlying` → `Unauthorized`；`_declaredAmount == 0 && _receivedAmount == 0` → `0`；宣言額非 0 / 純受取 0、reject 回収時のその他の declared/received 不一致、返送失敗、または送受どちらかの残高差不一致 → `DepositRecoveryFailed`（外側の `allocate` 全体も revert）。
- **発火イベント**: `Deposited(uint256 amount, uint256 newPrincipal)`（STGY-EVT-001）。
- **設計上のポイント**: `principal` は外部プロトコルでの観測値ではなく Strategy の純受領額で加算する。reject を単純に catch して Strategy idle に残さず、EVM call-frame rollback と送受両端の残高差で完全回復を証明する。成功時のみ `Deposited` を発火し、回復後の `0` を受けた Vault が `StrategyAllocationSkipped` を発火する。配分ルール（buffer / cap / weights）は Vault 側（[CollateralVault 要件定義](../CollateralVault.md) 配分ルール）に属する。
- **Verification**: unit（onlyVault・self-only executor・`_receivedAmount==0` no-op・principal 加算・reject 時の inner state rollback・exact recovery・transfer fee 時の fail-closed）, integration（allocate→deposit・失敗 Strategy を skip して後続継続）。

### STGY-FR-002: sendToVault（元本回収の push）

- **Type**: Functional ｜ **Source**: Product-Overview「push モデル」/ [CollateralVault](../CollateralVault.md) redeem / リバランス
- **シグネチャ**: `sendToVault(uint256 _amount) returns (uint256 sent)`
- **目的**: 指定額を外部プロトコルから引き出し、`receiveFromStrategy`（[CollateralVault 要件定義](../CollateralVault.md)）経由で Vault buffer へ push し返す。ALLOCATOR が起動する用途はユーザー redeem の Buffer 補充・リバランス・`removeStrategy` 前処理。
- **権限**: Vault の `ALLOCATOR_ROLE`（Strategy が Vault の AccessControl を参照して検証）。
- **事前条件（Checks）**: 呼び出し元が Vault の `ALLOCATOR_ROLE` を保持していること。cap / pause / cooldown は回収方向には非適用（投下方向の `allocate()` のみに適用。ALLOCATOR 権限境界は [CollateralVault 要件定義](../CollateralVault.md)）。
- **動作（Effects）**:
  1. **ロール検証** — 呼び出し元が Vault の `ALLOCATOR_ROLE` を保持しているか（Strategy が Vault の AccessControl を参照）。不保持なら `Unauthorized` で revert
  2. **入力検証** — `_amount == 0` なら何もせず `0` を返す
  3. **外部プロトコルから引き出し** — `_doWithdraw(_amount)` を実行し、実際に引き出せた額 `actual` を得る（流動性不足等で要求額未満になりうる）。`actual == 0` なら `SentToVault(_, _amount, 0, principal)` を発火して `0` を返す
  4. **Vault へ push** — `vault.receiveFromStrategy(actual)` を呼び、Vault が実際に受領した額 `sent` を得る
  5. **principal を減算（principal-first）** — `principal -= min(sent, principal)`。`sent` が残 `principal` を超える分は収益の前倒し回収であり、Vault バッファに留まって `transferYieldToTreasury`（[CollateralVault 要件定義](../CollateralVault.md)）の対象になる
- **revert / 早期 return**:
  - `_amount == 0` → 何もせず `0` を返す
  - 呼び出し元が ALLOCATOR でない → `Unauthorized` で revert
  - `_doWithdraw` が `0` を返す（流動性ゼロ等）→ `SentToVault(_, _amount, 0, principal)` を発火して `0` を返す
  - `receiveFromStrategy` が未登録 Strategy 判定で revert → そのまま伝播（通常は登録済みのため発生しない）
- **発火イベント**: `SentToVault(caller, requested, actual, newPrincipal)`（STGY-EVT-002）— `requested = _amount`、`actual` フィールドには `receiveFromStrategy` が受領した `sent` が入る（Vault 側は `ReceivedFromStrategy` を発火＝[CollateralVault 要件定義](../CollateralVault.md)）。
- **設計上のポイント**:
  - **同期/非同期の隠蔽**: 外部プロトコルが同期か非同期かは Strategy 実装内に閉じる。`requestKey` / `isAsyncWithdraw` 分岐は持たない（[STGY-ERR-002](#stgy-err-002-非同期な外部プロトコルの取り扱い)）。
  - **principal 減算は `sent` ベース**: declared 量や `_doWithdraw` の返り値ではなく、Vault が実際に受領した `sent` で減算し、`principal` と Vault buffer の乖離を防ぐ。
  - **cap は無関係**: 投下ではなく回収のため cap チェックは行わない（cap は Vault の `allocate` 投下方向のみ）。要求額が AUM を超える場合の挙動は Strategy 実装依存（AaveV3 等の同期 Strategy では Aave 側が revert し得る）。
- **例**:
  - Strategy A（principal = 1000、estimatedTotalUnderlying = 1050）に対し ALLOCATOR が `A.sendToVault(100)`：`_doWithdraw(100)` で 100 引き出し → `receiveFromStrategy(100)` で Vault buffer +100、`sent = 100` → `principal = 900`
  - 同 Strategy に `A.sendToVault(1050)`（AUM 全量を要求）：`_doWithdraw(1050)` → `receiveFromStrategy(1050)` で `sent = 1050` → `principal -= min(1050, 1000) = 1000`（principal = 0）、超過 50 は収益として buffer に残り `transferYieldToTreasury` の対象になる
- **Verification**: unit（ALLOCATOR 限定・`_amount==0` / `actual==0` 早期 return・`sent` ベース減算・principal-first）, fork/integration（外部プロトコル引き出し→Vault 受領）。

### STGY-FR-003: sendProfitToVault（収益のみの push）

- **Type**: Functional ｜ **Source**: Product-Overview「収益化」/ [CollateralVault](../CollateralVault.md) harvest 第 1 段
- **シグネチャ**: `sendProfitToVault() returns (uint256 sent)`
- **目的**: 当該 Strategy の **realized 収益のみ**を Vault buffer へ push する（Vault 側 harvest の第 1 段。第 2 段の `transferYieldToTreasury` は [CollateralVault 要件定義](../CollateralVault.md)）。引数なし（Strategy が `realizedYield()` を計算）。
- **権限**: Vault の `ALLOCATOR_ROLE`。
- **事前条件（Checks）**: 呼び出し元が Vault の `ALLOCATOR_ROLE` を保持していること。
- **動作（Effects）**:
  1. **ロール検証** — 呼び出し元が Vault の `ALLOCATOR_ROLE` を保持していなければ `Unauthorized` で revert
  2. **収益額の算出** — `yield = realizedYield() = max(estimatedTotalUnderlying() − principal, 0)`。`yield == 0` なら `ProfitSentToVault(_, 0, 0)` を発火して `0` を返す
  3. **引き出し** — `_doWithdraw(yield)` を実行（`actual == 0` なら `ProfitSentToVault(_, yield, 0)` を発火して `0` を返す）
  4. **Vault buffer へ yield-only push** — Strategy が Vault の Underlying 残高差分で `sent` を測りながら `safeTransfer(vault, actual)` する。**`principal` は意図的に不変**（収益のみの push なので元本は減らさない）。`receiveFromStrategy` は通らないため、Vault の Strategy valuation cache も元本返却として減額されない
  5. `ProfitSentToVault(caller, yield, sent)` を発火（STGY-EVT-003）
- **revert / 早期 return**: 非 ALLOCATOR → `Unauthorized`；`yield == 0` → `ProfitSentToVault(_, 0, 0)` 発火・`0` 返却；`actual == 0` → `ProfitSentToVault(_, yield, 0)` 発火・`0` 返却。
- **発火イベント**: `ProfitSentToVault(address caller, uint256 yield, uint256 actual)`（STGY-EVT-003）。
- **設計上のポイント**: `principal` と Vault の Strategy valuation cache を動かさないことで、Vault の保守評価（`totalUnderlying()` / `managedUnderlying` の Strategy 部分はいずれも `min(estimatedTotalUnderlying, principal)`、[CollateralVault 要件定義](../CollateralVault.md) 会計原則）と整合する。収益だけの着金を `receiveFromStrategy` 経由にすると、fallback cache を元本返却として減額し、live valuation 一時失敗時に不要な保守的過小評価を作るため、yield-only push は direct transfer に分ける。収益送付の取りすぎ防止は、Strategy 側の `realizedYield()` 上限と Vault 側の `managedUnderlying` surplus + buffer 上限（`transferYieldToTreasury`）の両方で担保される。
- **Verification**: unit（ALLOCATOR 限定・`yield==0`/`actual==0` 早期 return・`principal` 不変）, fork/integration（収益引き出し→Vault 受領）。

### STGY-FR-004: writeoffPrincipal（元本毀損の確定）

- **Type**: Functional ｜ **Source**: [CollateralVault](../CollateralVault.md) `writeoffStrategyPrincipal`
- **シグネチャ**: `writeoffPrincipal(uint256 _amount) returns (uint256 writtenOff)`
- **目的**: Vault の `writeoffStrategyPrincipal`（[CollateralVault 要件定義](../CollateralVault.md)）から呼ばれ、回収不能となった元本を帳簿上ゼロ化する。
- **権限**: `onlyVault`（Vault の `writeoffStrategyPrincipal` 経由）。
- **事前条件（Checks）**: `caller == vault`。回収可能分は先に `sendToVault`（[STGY-FR-002](#stgy-fr-002-sendtovault元本回収の-push)）または固有緊急回収（`emergencyWithdrawFrom{Protocol}`、[STGY-FR-005](#stgy-fr-005-emergencywithdraw直接保有分を-vault-へ救済)）で Vault に戻し、**残った回収不能分のみ**を writeoff する。
- **動作（Effects）**:
  1. `onlyVault` 検証
  2. `principal -= min(_amount, principal)`（過大指定は残 `principal` にクランプ）
  3. `writtenOff = min(_amount, oldPrincipal)` を戻り値として確定する
  4. `PrincipalWrittenOff(writtenOff, principal)` を発火（STGY-EVT-004）。`writtenOff` は要求額ではなく実際に減った `principal`
- **revert / 早期 return**: 非 vault → `OnlyVault`。`_amount > principal` でも `min` クランプにより `principal` は負にならない（revert しない）。
- **発火イベント**: `PrincipalWrittenOff(uint256 amount, uint256 newPrincipal)`（STGY-EVT-004）。`amount` は実際に writeoff された額。
- **設計上のポイント**: **帳簿操作のみ**で実資産の移動は伴わない。`_amount > principal` でも `min` クランプにより `principal` は 0 でクランプされる（[STGY-INV-002](#stgy-inv-002)）。外部プロトコルの損失が `estimatedTotalUnderlying()` に自動反映されない場合でも、Vault GOV が回収不能額を確定して `writeoffStrategyPrincipal` を呼ぶことで `principal` 側から dToken backing へ下方反映できる。
- **Verification**: unit（onlyVault・`min` クランプ・過大指定で非負）, invariant=STGY-INV-002。

### STGY-FR-005: emergencyWithdraw（直接保有分を Vault へ救済）

- **Type**: Functional ｜ **Source**: [CollateralVault](../CollateralVault.md) 緊急時オーケストレーション
- **シグネチャ**: `emergencyWithdraw(uint256 _amount)`
- **目的**: Strategy が外部プロトコルに預けずに**直接保有**している Underlying（緊急引き出し後の滞留・誤送金・upgrade 中間状態等）を Vault へ戻す。Vault 側のオーケストレーション（緊急時の標準フロー）は [CollateralVault 要件定義](../CollateralVault.md)。
- **権限**: Strategy の Owner（`onlyOwner`）。
- **事前条件（Checks）**: `caller == Owner`。対象は通常運用では発生しない事故的な滞留分の救済に限定される。
- **動作（Effects）**:
  1. `_amount == 0` なら何もせず return
  2. `CollateralVault.receiveFromStrategy(_amount)` を呼び、Vault が Strategy から `safeTransferFrom` で Underlying を引き取る。戻り値 `sent` は Vault が実際に受領した額
  3. 派生 Strategy 用 hook `_afterEmergencyUnderlyingSent(_amount, sent)` を呼ぶ（既定は no-op）
  4. `EmergencyWithdrawn(sent)` を発火（STGY-EVT-005）
- **revert / 早期 return**: 非 Owner → revert；`_amount == 0` → 何もせず return；Strategy が Vault の `strategies[]` から削除済みの場合は Vault 側の `NotRegisteredStrategy` で revert。
- **発火イベント**: `EmergencyWithdrawn(uint256 amount)`（STGY-EVT-005）。
- **設計上のポイント**:
  - **送金先 Vault 固定**: 任意 `_to` を持たない。Strategy owner（運用ロールと分離されうる）が GOV 承認なしに任意アドレスへ Underlying を抜く経路を塞ぐ（[STGY-SEC-003](#stgy-sec-003-emergencywithdraw-の送金先-vault-固定)）。
  - **`principal` は減算しない**: Vault は Strategy 保有分を live `min(estimatedTotalUnderlying, principal)` で評価し、`estimatedTotalUnderlying`（例: Aave の自己 scaled 残高）は外部プロトコル預入分のみを表す。live valuation が読める限り、直接保有分を Vault へ push しても二重計上は起きない。回収不能の残元本があれば Vault の `writeoffStrategyPrincipal`（[STGY-FR-004](#stgy-fr-004-writeoffprincipal元本毀損の確定)）で確定する。
  - **Vault valuation cache との関係**: `emergencyWithdraw` は `receiveFromStrategy` を経由するため、exact delivery なら受領額に応じて cache を減額し、declared/received mismatch なら cache を無効化する。これにより、緊急回収後に live valuation が一時的に読めない場合でも `buffer + ambiguous cache` の二重計上・過大評価を避ける。
  - **派生補助会計との同期**: 派生 Strategy が「claim 済み idle」等の直接保有 Underlying を別ストレージで自己追跡する場合、`_afterEmergencyUnderlyingSent` でその補助会計を減額できる。これにより `emergencyWithdraw` で実残高だけが動いた後に、後続 donation が stale な自己追跡枠を再充填して AUM を水増しする事故を防ぐ。
  - **救済対象ケース**: ① Vault からの `safeTransfer` 後に `deposit` が呼ばれず Strategy アドレスに残ったケース（Vault 側のバグ・運用オペミス・将来の経路追加で生じうる）／② 第三者からの誤送金（ERC-20 transfer は受け取り側の同意なしに残高が増えるため）／③ upgrade 過程の中間状態で旧実装の保有分が新実装側から「直接保有」として見える状態。
- **外部プロトコルからの引き上げとの関係（原子直送の原則）**: 外部プロトコル側の残高を引き上げる固有関数（`emergencyWithdrawFrom{Protocol}()`）は、引き出した Underlying を Strategy idle に滞留させると、評価（`_estimatedTotalUnderlying` は idle 非算入）にも Vault buffer にも算入されない**宙吊り**が生じ、`backingRatio` の過小評価 → 不当清算を誘発しうる。このため固有関数は**外部プロトコル → Vault への原子直送（引き出しと `receiveFromStrategy` push を同一 Tx で実行・外部側 revert 時は全体 revert の fail-closed）**を原則とする。Vault 実受領額は `PrincipalReturned` として `principal` から減算し、部分回収後に残りが損失確定した場合でも `writeoffPrincipal` は残元本だけを落とせばよい。push 先の `receiveFromStrategy` は **Vault に登録済み（`strategies[]` 残存）の Strategy からのみ受け入れる**ため、`removeStrategy` 済みの Strategy では固有関数全体が revert する（fail-closed。除去後に外部プロトコル側の残余が見つかった場合は、再 whitelist → `addStrategy`〔GOV=Timelock〕で再登録してから回収する）。`emergencyWithdraw` は donation・残余など事故的滞留分の回収用に併存する。
- **Verification**: unit（onlyOwner・`_amount==0` no-op・送金先 Vault 固定・`principal` 不変）, integration（固有関数の原子直送・残余の emergencyWithdraw 回収）。

### STGY-FR-010: sweepRewardToken（非 Underlying・非 position 報酬の Treasury 送付）

- **Type**: Functional ｜ **Source**: 外部プロトコル報酬（Aave incentives / Merkl 等）の取りこぼし防止
- **シグネチャ**: `sweepRewardToken(IERC20 _token, uint256 _amount) returns (uint256 swept)`
- **目的**: Strategy に着金済みの **非 Underlying かつ非 position ERC20 報酬**（Aave incentives / Merkl reward / 誤送金された報酬トークン等）を Vault の現在 `treasury` へ送る。通常の Underlying yield / principal 回収とは別経路であり、backing 会計には直接混ぜない。Aave aToken、Morpho vault share、Euler eToken / vault share 等の position / receipt / accounting token は報酬ではなく Strategy の請求権なので対象外。
- **権限**: Strategy の Owner（`onlyOwner`）。
- **事前条件（Checks）**:
  - `_token != address(0)`（ゼロなら `ZeroAddress`）
  - `_isSweepProtectedToken(address(_token)) == false`（Underlying または派生 Strategy が保護する position / receipt / accounting token なら `CannotSweepProtectedToken`）
  - `_amount == 0` は no-op として `0` を返す。`_amount == type(uint256).max` は Strategy が保有する当該 reward token の全残高を sweep する指定として扱う
  - `ICollateralVault(vault).treasury() != address(0)`（ゼロなら `ZeroAddress`）
- **動作（Effects）**:
  1. `recipient = ICollateralVault(vault).treasury()` を読む（GOV の `setTreasury` 変更に追随）
  2. `recipient` の `_token.balanceOf` を送金前後で測る
  3. `_amount == type(uint256).max` の場合は `amount = _token.balanceOf(address(this))` に解決する
  4. `_token.safeTransfer(recipient, amount)` で reward token を Treasury へ送る
  5. `swept = max(balanceAfter - balanceBefore, 0)` を返す（fee-on-transfer reward token の実着額を表す）
  6. `RewardTokenSwept(token, recipient, requested, swept)` を発火（STGY-EVT-007）。`requested` は `type(uint256).max` ではなく、実際に transfer した `amount`
- **revert / 早期 return**: 非 Owner → revert；ゼロ token / ゼロ treasury → `ZeroAddress`；protected token 指定 → `CannotSweepProtectedToken`；`_amount == 0` または全量指定時の残高 0 → 送金せず `0`。
- **発火イベント**: `RewardTokenSwept(address indexed token, address indexed treasury, uint256 requested, uint256 received)`（STGY-EVT-007）。
- **設計上のポイント**:
  - **Underlying / position token は sweep 不可**: principal / Underlying yield は `sendToVault` / `sendProfitToVault` / `emergencyWithdraw` のいずれかで Vault に戻す。Aave aToken、Morpho vault share、Euler eToken / vault share 等の protocol position token は固有の withdraw 経路で Underlying 化して戻す。`sweepRewardToken` でこれらを Treasury へ直送できると、Vault buffer / backing / `principal` 会計を迂回するため禁止する。
  - **派生 Strategy の protected token hook**: `BaseStrategy` は Underlying を既定の protected token とし、派生 Strategy は `_isSweepProtectedToken` を override して protocol-specific な position / receipt / accounting token を追加する。Aave では `aToken`、Morpho / Euler では採用市場ごとの share / receipt token を必ず保護対象に入れる。
  - **送金先は Treasury 固定**: 任意 `_to` を持たない。Owner が報酬トークンを任意アドレスへ振り替える経路を作らず、Vault の `treasury` 設定に従う。
  - **backing に自動算入しない**: 非 Underlying・非 position reward token は `estimatedTotalUnderlying()` に含めず、dToken backing の修復にも自動利用しない。backing を修復したい場合は、別途 Treasury / backstop が reward を Underlying に換えて `backstopDeposit` 等で補填する。
  - **claim との関係**: 本関数は「すでに Strategy に着金した reward token の sweep」である。Merkl の標準 distributor claim は [STGY-FR-012](#stgy-fr-012-claimmerklrewardsmerkl-報酬の-claim--sweep) で共通実装する。claim 後、非 Underlying reward は `_sweepRewardToken`、Underlying reward は `_sendUnderlyingToVault` に寄せる。Aave RewardsController 固有 claim、swap、backing 補填は本関数の責務外であり、別設計とする。
- **Verification**: unit（onlyOwner・Underlying / position token 拒否・送金先 current treasury 固定・fee-on-transfer 実着額・`_amount==0` no-op・`type(uint256).max` 全量 sweep）。

### STGY-FR-012: claimMerklRewards（Merkl 報酬の claim + sweep）

- **Type**: Functional / Security ｜ **Source**: Merkl 等の外部 distributor 報酬の取り込み
- **シグネチャ**: `claimMerklRewards(IMerklDistributor _distributor, address[] calldata _tokens, uint256[] calldata _amounts, bytes32[][] calldata _proofs) returns (uint256[] settledAmounts)`
- **目的**: Merkl distributor から当 Strategy 宛の報酬を claim し、非 Underlying・非 position reward token は Vault の現在 `treasury` へ sweep、Underlying reward は Vault buffer へ yield として push する。reward claim と settlement の会計境界を BaseStrategy に集約し、任意 calldata / 任意 recipient / position token 移動を持ち込まない。
- **権限**: Strategy の Owner（`onlyOwner`）。
- **事前条件（Checks）**:
  - `_distributor != address(0)`（ゼロなら `ZeroAddress`）
  - `_distributor.code.length != 0`（EOA / 未デプロイなら `InvalidMerklDistributor`）
  - `_tokens.length > 0` かつ `_tokens.length == _amounts.length == _proofs.length`（不一致なら `InvalidMerklClaim`）
  - `_tokens.length <= MAX_MERKL_TOKENS_PER_CLAIM`（実装定数は `16`。超過なら `TooManyMerklTokens(tokenCount, maxTokenCount)`）
  - 各 `_tokens[i] != address(0)`（ゼロなら `ZeroAddress`）
  - `_tokens` 内に重複 token がないこと（重複時 `DuplicateMerklToken(token)`）
  - Underlying は許可する。Underlying 以外で `_isSweepProtectedToken(token) == true` の position / receipt / accounting token は distributor 呼び出し前に `CannotSweepProtectedToken` で fail-fast
- **動作（Effects）**:
  1. `users` 配列を全要素 `address(this)` で構築する（claim recipient を Strategy 自身に固定）
  2. claim 前の各 token 残高を記録する
  3. `_distributor.claim(users, _tokens, _amounts, _proofs)` を呼ぶ。Merkl の標準 `claim` selector のみを使い、任意 calldata / 任意 recipient を受け取らない
  4. token が Underlying の場合、claim 前後の残高差分だけを `_sendUnderlyingToVault` で Vault buffer へ送り、`MerklUnderlyingRewardsClaimed(distributor, token, cumulativeAmount, sentToVault)` を発火する
  5. token が Underlying 以外の場合、`_sweepRewardToken(IERC20(token), type(uint256).max)` を呼び、Strategy に残る当該 reward token 全額を Treasury へ送る。`RewardTokenSwept` と `MerklRewardsClaimed(distributor, token, cumulativeAmount, swept)` を発火する
- **revert / 早期 return**: 非 Owner → revert；distributor / 配列 / token / 重複 token / protected token 不正 → 上記 error；Merkl proof 不正や distributor 側失敗 → distributor revert を伝播；Treasury がゼロまたは token transfer 失敗 → `_sweepRewardToken` の revert を伝播。
- **発火イベント**: `RewardTokenSwept`（非 Underlying token sweep 時）、`MerklRewardsClaimed(address indexed distributor, address indexed token, uint256 cumulativeAmount, uint256 swept)`、`MerklUnderlyingRewardsClaimed(address indexed distributor, address indexed token, uint256 cumulativeAmount, uint256 sentToVault)`（STGY-EVT-010）。
- **設計上のポイント**:
  - **recipient 固定**: `users[i] = address(this)` に固定し、Owner が任意ユーザー/任意 recipient の Merkl claim を Strategy 経由で実行できないようにする。
  - **Underlying reward は Vault buffer へ送る**: Underlying 報酬は Treasury sweep ではなく Vault buffer へ yield として push し、`principal` は変更しない。これにより Morpho / Euler / Merkl 系の Underlying reward を backing 会計境界の内側に入れる。
  - **position token は claim 前に拒否**: position / receipt / accounting token が Strategy に着金すると、Treasury sweep も backing 会計も通常経路から外れるため、claim 前に fail-fast する。どうしても protected token の外部配布を回収する必要がある場合は、個別 runbook と Vault 回収経路を別途設計する。
  - **非 Underlying reward は backing に自動算入しない**: 非 Underlying reward token は claim 後も `estimatedTotalUnderlying()` / `principal` / Vault buffer には混ぜず、Treasury 資産として扱う。backing 修復に使う場合は Underlying へ換金後に `backstopDeposit` 等で明示的に入金する。
- **Verification**: unit（onlyOwner・distributor code 検証・配列長検証・recipient 固定・重複 token 拒否・position token claim 前拒否・Underlying reward の Vault push・Treasury 実着額・fee-on-transfer reward token）。

### STGY-FR-006: 派生 hook（_doDeposit / _doWithdraw / _estimatedTotalUnderlying）

- **Type**: Functional ｜ **Source**: Product-Overview「Strategy Layer」/ 外部プロトコル変換層
- **シグネチャ**: `_doDeposit(uint256 amount)` ／ `_doWithdraw(uint256 amount) → uint256 actual` ／ `_estimatedTotalUnderlying() → uint256`（いずれも internal hook・派生で実装）
- **目的**: 外部プロトコル I/F への変換点。BaseStrategy の本体（`deposit` / `sendToVault` / `sendProfitToVault`）がこれらを呼び出し、外部プロトコルごとの差分を hook に局所化する。
- **権限**: internal（BaseStrategy 本体から呼ばれる。外部からは直接呼べない）。
- **事前条件（Checks）**: 各派生実装の事前 approve（外部プロトコルへの supply 用）が済んでいること（[STGY-FR-007](#stgy-fr-007-basestrategy-初期化-__basestrategy_init--派生-initialize)）。
- **動作（Effects）**:
  1. `_doDeposit(amount)`: 外部プロトコルへ Underlying を預け入れる（例: `aavePool.supply(...)`）
  2. `_doWithdraw(amount) → actual`: 通常回収・収益回収用に、外部プロトコルから Underlying を **Strategy 自身へ**引き出す。元本返却系では BaseStrategy が `receiveFromStrategy` で Vault へ push し、収益のみでは Vault buffer へ直接 `safeTransfer` する。実引き出し額 `actual` を返す（要求額に満たない場合あり）。**非同期な外部プロトコルでは、その時点で即時に引き出せる額のみを返す**（[STGY-ERR-002](#stgy-err-002-非同期な外部プロトコルの取り扱い)）
  3. `_estimatedTotalUnderlying() → uint256`: 外部プロトコルでの自身の保有資産を Underlying 換算で返す（保守的評価）。dToken の JPY 建て価格ではなく、Vault が `A` と `L_effective` を同一 Underlying 単位で比較するための入力
- **revert / 早期 return**: 外部プロトコル I/F の失敗はそのまま伝播し得る（要求額が AUM を超える場合等は外部プロトコルが revert し得る。[STGY-FR-002](#stgy-fr-002-sendtovault元本回収の-push) 設計上のポイント）。
- **発火イベント**: hook 自体は発火しない（呼出元 BaseStrategy 本体が STGY-EVT-001..003 を発火）。固有の緊急回収関数（`emergencyWithdrawFrom{Protocol}()`、`onlyOwner`。外部プロトコルから引き出せた分を同一 Tx で Vault へ原子直送＝[STGY-FR-005](#stgy-fr-005-emergencywithdraw直接保有分を-vault-へ救済) の原則）は派生固有イベント `Emergency*Withdrawn(uint256 amount)`（[STGY-EVT-006](#11-イベント監視要件evt)）を推奨。
- **設計上のポイント**: 各派生 Strategy が実装するのは ①追加ストレージ（外部プロトコル固有のアドレス: Pool / Adapter 等）②`initialize`（BaseStrategy 初期化＋追加ストレージ＋事前 approve）③上記 3 hook ④必要なら固有の緊急回収関数のみ。`deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` 本体は BaseStrategy が提供する。`_estimatedTotalUnderlying` は外部プロトコルごとの会計に依存するため、損失・slashing・withdraw penalty 等がある場合は過大評価しない実装が必要である。例: AaveV3Strategy は自己管理する scaled balance を Aave 側の実 scaled balance で cap し、normalized income を掛けることで第三者 donation を除外しつつ Aave 側の残高低下を反映する。
- **Verification**: integration/fork（各子ドキュメントで外部プロトコル I/F マッピングを検証。例: [AaveV3Strategy 要件定義](./AaveV3Strategy.md)）, unit（保守的評価・`actual` 返却）。

### STGY-FR-007: BaseStrategy 初期化（__BaseStrategy_init / 派生 initialize）

- **Type**: Functional ｜ **Source**: Product-Overview「Strategy Layer (UUPS)」/ push モデル approve 方向
- **シグネチャ**: `__BaseStrategy_init(address _vault, address _underlying, address _owner, address _upgrader)`（internal）／ 派生 `initialize(...)`（external initializer）
- **目的**: UUPS proxy 越しに Strategy を初期化し、共通ストレージ・Ownable・UUPS・push モデルの approve を確立する。
- **権限**: デプロイ手順（proxy 初期化）の一部。`_owner` に Owner（Guardian multisig・[STGY-GOV-001](#stgy-gov-001-owner-と-upgrader-の-holder-構成)）を束縛する。
- **事前条件（Checks）**: `_vault` / `_underlying` / `_owner` / `_upgrader` がゼロアドレスでない。`_vault` / `_underlying` はデプロイ済み contract である。多重初期化は不可（initializer）。
- **事前条件（Checks）**（`__BaseStrategy_init`）:
  - `_vault != address(0)`
  - `_underlying != address(0)`
  - `_owner != address(0)`
  - `_upgrader != address(0)`
  - `_vault.code.length != 0`
  - `_underlying.code.length != 0`
  - 派生 `initialize` は追加の外部プロトコル依存先（Aave Pool / aToken、ERC-4626 vault、Lido stETH / wstETH / Withdrawal Queue、Etherfi LiquidityPool / eETH / weETH / WithdrawAdapter / WithdrawRequestNFT、Sky USDS / sUSDS vault / converter 等）についてもゼロアドレスと未デプロイ contract を fail-fast で拒否する。
- **動作（Effects）**（`__BaseStrategy_init`）:
  1. OZ Ownable / UUPS 初期化
  2. ゼロアドレス / contract code チェック
  3. 共通ストレージ保存（`vault` / `underlyingToken` / `_principal`）
  4. ownership 移譲（`_owner` = Owner〔Guardian multisig〕へ）
  5. `underlying.forceApprove(vault, type(uint256).max)`（**Vault へ approve**）。これにより `receiveFromStrategy` が `safeTransferFrom` で Strategy から Underlying を引き取れる（push モデル: approve 方向は Strategy → Vault）
  6. 派生 `initialize` が続けて追加ストレージの設定＋外部プロトコルへの supply 用の事前 approve を行う
- **revert / 早期 return**: ゼロアドレス → revert；EOA / 未デプロイ contract → `NotContract(target)`；再初期化 → revert。
- **発火イベント**: 該当なし（初期化に専用イベントは設けない。運用イベントは STGY-EVT-001..005）。
- **設計上のポイント**: 共通ストレージ・`onlyVault` modifier（Vault 以外を `OnlyVault` で revert）・`sendToVault` / `sendProfitToVault` の `ALLOCATOR_ROLE` ガード（Vault の AccessControl を参照する `onlyVaultRole(role)`）・外部 call を伴う entry point の local `nonReentrantStrategy` guard・`deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` 本体・view getter（`underlying()` / `principal()` / `realizedYield()` / `estimatedTotalUnderlying()`、`realizedYield = max(estimatedTotalUnderlying − principal, 0)`）・`emergencyWithdraw` / `_authorizeUpgrade` / `setUpgrader` はすべて BaseStrategy が提供する。派生は hook と固有事項のみ実装する。
- **Verification**: unit（ゼロアドレス revert・EOA / 未デプロイ contract revert・再初期化 revert・ownership 移譲・upgrader 保存・`forceApprove(vault, max)`・nested guarded entry の `ReentrantCall`）, manual（デプロイ構成レビュー）。

### STGY-FR-008: view getter（principal / realizedYield / estimatedTotalUnderlying / underlying）

- **Type**: Functional ｜ **Source**: [CollateralVault](../CollateralVault.md) ソルベンシー評価 / subgraph
- **シグネチャ**: `principal() → uint256` ／ `realizedYield() → uint256` ／ `estimatedTotalUnderlying() → uint256` ／ `underlying() → address`（いずれも external view）
- **目的**: Vault のソルベンシー評価・allocate 比率計算・収益判定・subgraph AUM 推移・on-chain Underlying 整合検証に用いる読み取り I/F を提供する。
- **権限**: なし（external view・permissionless）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**: 状態変化なし（view）。
  - `principal()`: 当 Strategy が自己管理する投下元本を返す。Vault の `removeStrategy`（`principal == 0` かつ live `estimatedTotalUnderlying() == 0` 要求）/ ソルベンシー評価（`min(estimatedTotalUnderlying, principal)`）に使用
  - `realizedYield()`: `max(estimatedTotalUnderlying() − principal, 0)` を返す。`sendProfitToVault` の引き出し上限
  - `estimatedTotalUnderlying()`: 当 Strategy が運用中の Underlying 建て評価額（保守的評価前提）を返す。価格 oracle ではない。Vault の allocate 比率計算 / 収益判定 / subgraph AUM 推移 / dToken backing の `A = totalUnderlying()` に使用
  - `underlying()`: 当 Strategy の Underlying アドレスを返す。Vault の `addStrategy` が `strategy.underlying() == vault.underlying()` を on-chain 検証（[CollateralVault 要件定義](../CollateralVault.md) `addStrategy`）。subgraph ラベリングにも使用
- **revert / 早期 return**: 該当なし（view）。
- **発火イベント**: なし（view）。
- **設計上のポイント**: BaseStrategy が提供。`estimatedTotalUnderlying()` の保守的評価が過大だと収益取りすぎを招くため、Vault 側で `min(estimatedTotalUnderlying, principal)` 保守評価＋`realizedYield()` 上限＋buffer 上限の多段防御を行う（[STGY-SEC-004](#stgy-sec-004-aum-過大評価への保守的会計)）。
- **Verification**: unit（`realizedYield` 計算・保守的評価）, integration（Vault の `addStrategy` underlying 一致検証）。

### STGY-FR-009: アップグレード（UUPS）

- **Type**: Functional ｜ **Source**: Product-Overview「Strategy Layer (UUPS)」
- **シグネチャ**: `_authorizeUpgrade(address newImpl)`（internal・UUPS authorization）/ `setUpgrader(address _newUpgrader)`。外部からは UUPS `upgradeTo` / `upgradeToAndCall`。
- **目的**: UUPS でロジック差替により外部プロトコル変換・会計等の挙動を将来修正できるようにする。
- **権限**: 新実装の承認は **専用 `upgrader`（holder = 共通 TimelockController）のみ**。Owner（Guardian multisig）・運用ロール（vault / ALLOCATOR 等）は不可（Owner の緊急即時性と upgrade の遅延統制を両立するため `_authorizeUpgrade` を Owner から分離する。`__gap` から変数 1 を充当）。
- **事前条件（Checks）**: `_authorizeUpgrade` / `setUpgrader` は `caller == upgrader`。`setUpgrader` の `_newUpgrader != address(0)`。
- **動作（Effects）**:
  1. `_authorizeUpgrade` が `msg.sender == upgrader` を確認し、実装アドレスを差替（UUPS）
  2. `setUpgrader` は現 `upgrader` のみが `_newUpgrader` を保存し、`UpgraderUpdated(oldUpgrader, newUpgrader)` を発火
  3. ERC1967 `Upgraded(newImpl)` を発火
- **revert / 早期 return**: 非 upgrader（Owner 含む）の upgrade / `setUpgrader` → revert。`setUpgrader(address(0))` → `ZeroAddress`。
- **発火イベント**: ERC1967 `Upgraded(newImpl)`、`UpgraderUpdated(oldUpgrader, newUpgrader)`。
- **設計上のポイント**: `upgradeTo` による悪意 Implementation 差し替えが最大の脅威であり、承認権限を Owner から分離した専用 `upgrader` に置き、その holder を共通 TimelockController にする。**upgrader の再指定は upgrader 自身（= Timelock 経由）のみが行え、Owner からは変更できない**（Owner が upgrader を自分へ差し替えると分離が無効化されるため。[STGY-SEC-002](#stgy-sec-002-owner-鍵侵害時の被害境界) / [STGY-GOV-003](#stgy-gov-003-upgrader-timelock)）。fresh deploy 前提のため、`upgrader` は `__BaseStrategy_init` で必ず初期化し、旧 proxy 救済用の後方互換 migration 入口は持たない。
- **Verification**: unit（upgrader 限定承認・Owner / 運用ロール revert・upgrader 再指定は upgrader のみ）, manual（storage layout review）。

### STGY-FR-011: Owner 移譲（2-step）と renounce 無効化

- **Type**: Functional / Security ｜ **Source**: mainnet 権限運用・dToken / Oracle ownership 方針との整合
- **シグネチャ**: `pendingOwner() → address` / `transferOwnership(address newOwner)` / `acceptOwnership()` / `renounceOwnership()`
- **目的**: Strategy Owner は緊急回収・reward sweep・ownership 操作を握る強権限であり、誤アドレスへの 1-step 移譲や Owner 放棄で救済経路を失ってはならない。Owner 移譲は候補者の明示承諾を要求し、Owner 放棄はコード上 revert で無効化する。UUPS upgrade は Owner ではなく `upgrader` が担う。
- **権限**:
  - `transferOwnership`: 現 Owner のみ
  - `acceptOwnership`: `pendingOwner` のみ
  - `renounceOwnership`: 現 Owner のみ呼べるが常に revert
- **動作（Effects）**:
  1. `transferOwnership(newOwner)` は `_pendingOwner = newOwner` を保存し、`OwnershipTransferStarted(owner, newOwner)` を発火する。`newOwner == address(0)` は pending 移譲のキャンセルとして扱う
  2. `acceptOwnership()` は `owner = pendingOwner` に移譲し、`pendingOwner` をクリアする（OZ `OwnershipTransferred` 発火）
  3. `renounceOwnership()` は `RenounceOwnershipDisabled` で revert し、Owner を維持する
- **設計上のポイント**: `_pendingOwner` は BaseStrategy 自身の storage gap を 1 slot 消費して追加する。既存の `OwnableUpgradeable` 継承順は変えず、既存 storage slot を動かさない。
- **Verification**: unit（2-step 移譲・pending cancel・非 pending accept revert・renounce disabled・zero owner init revert）。

---

## 7. 状態変数・会計モデル

| 変数                       | 型        | 説明                                                                    | 確定                                                                                            |
| -------------------------- | --------- | ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `vault`                    | `address` | `onlyVault` 検証先・push 先・AccessControl 参照先の対応 CollateralVault | `__BaseStrategy_init` で固定                                                                    |
| `underlyingToken`          | `address` | 当 Strategy の Underlying                                               | `__BaseStrategy_init` で固定                                                                    |
| `_principal`               | `uint256` | 自己管理する投下元本（帳簿値）                                          | `deposit` で加算 / `sendToVault`・固有緊急回収の returned principal・`writeoffPrincipal` で減算 |
| `_pendingOwner`            | `address` | 2-step Owner 移譲候補                                                   | `transferOwnership` / `acceptOwnership`                                                         |
| `upgrader`                 | `address` | UUPS upgrade 承認主体。Owner とは分離                                   | `__BaseStrategy_init` / `setUpgrader`                                                           |
| `_reentrancyStatus`        | `uint256` | Strategy entry point の local reentrancy guard 状態                     | `nonReentrantStrategy`（BaseStrategy の storage gap から 1 slot 充当）                           |
| 外部プロトコル固有アドレス | （派生）  | Pool / Adapter / aToken 等                                              | 派生 `initialize`                                                                               |

**会計モデル**: Strategy は投下元本 `principal` を自己管理し、外部プロトコル評価額 `estimatedTotalUnderlying()` との関係から `realizedYield() = max(estimatedTotalUnderlying() − principal, 0)` を導く。

- **`principal` の増減**: `deposit` で「Vault が送った額」加算（外部観測値ではない）。`sendToVault` と固有緊急回収で「Vault が実受領した `sent`」を `min(sent, principal)` 減算（principal-first）。`writeoffPrincipal` で `min(_amount, principal)` 減算。`sendProfitToVault` / 汎用 `emergencyWithdraw` / `sweepRewardToken` / `claimMerklRewards` では不変。
- **収益の前倒し回収**: `sendToVault` で `sent` が残 `principal` を超えた分は収益であり、Vault buffer に留まって `transferYieldToTreasury` の対象になる。
- **保守評価との整合**: Vault は Strategy 保有分を `min(estimatedTotalUnderlying, principal)` で評価する。`sendProfitToVault` が `principal` を動かさないこと、固有緊急回収が Vault 実受領額を returned principal として減算すること、汎用 `emergencyWithdraw` が事故的な直接保有分のみを動かすことで、この保守評価と二重計上なく整合する。
- **非 Underlying・非 position 報酬の会計外扱い**: Aave incentives / Morpho/Euler の Merkl 等の reward token は `estimatedTotalUnderlying()` と dToken backing に含めない。Strategy に着金した場合は `sweepRewardToken` で Treasury へ送る。Merkl 未 claim 分は `claimMerklRewards` で取り込み、Underlying reward は Vault buffer へ yield として push し、非 Underlying・非 position reward は Treasury へ sweep する。非 Underlying reward による backing 修復は別途 Underlying への換金・`backstopDeposit` 等を経て明示的に行う。protocol position / receipt / accounting token は reward token と見なさず、派生 Strategy の protected token として sweep / claim 前に拒否する。
- **async pending valuation**: `AsyncRequestStrategy` を継承する Lido / Etherfi は、未 claim request の記録額 `pendingWithdrawAmount` を `pendingWithdrawalValuationBps`（effective 初期値 10000、Vault の `WRITEOFF_ROLE` が 0〜10000 に変更可）で評価する。評価額は `pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000` を切り捨て丸めで算出する。fresh initialize は configured=true で 10000 bps を保存し、既存 proxy upgrade 等で storage が未設定の場合も getter / valuation は 10000 bps を effective default とする。通常時は 100% 評価を維持し、finalization / claim 実額に疑義がある incident 時だけ `WRITEOFF_ROLE` が pending 部分を保守的に割り引く。下方変更（`newBps < oldBps`）は `pausedAllocation == true` が必須で、新規 allocation / treasury sweep を止めた incident freeze 後にしか清算価格へ下方反映できない。復元・上方変更（`newBps >= oldBps`）は復旧時に詰まらないよう pause 不要。

---

## 8. 不変条件（INV）

| ID           | 不変条件                                                                                                                                                                                                                                                                               | 検証      |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| STGY-INV-001 | `deposit` / `writeoffPrincipal` は `vault` のみ、`sendToVault` / `sendProfitToVault` は Vault の `ALLOCATOR_ROLE` 保持者のみが実行できる（不保持は `OnlyVault` / `Unauthorized` で revert）                                                                                            | invariant |
| STGY-INV-002 | `principal` は `0` 未満にならない（`sendToVault` は `min(sent, principal)`、`writeoffPrincipal` は `min(_amount, principal)` でクランプ）                                                                                                                                              | invariant |
| STGY-INV-003 | `sendProfitToVault`・汎用 `emergencyWithdraw` は `principal` を変えない（収益 push・直接保有救済は元本帳簿に影響しない）。固有緊急回収は Vault 実受領額だけ `principal` を減算する                                                                                                     | invariant |
| STGY-INV-004 | `realizedYield() == max(estimatedTotalUnderlying() − principal, 0)`（恒等）                                                                                                                                                                                                            | unit      |
| STGY-INV-005 | `principal` 減算は declared 量ではなく Vault 実受領額 `sent` ベースで行われ、通常回収・固有緊急回収とも `principal` と Vault buffer の乖離を生まない                                                                                                                                   | invariant |
| STGY-INV-006 | 1 Strategy インスタンスの `underlying()` は不変で、対応 Vault の Underlying と一致する（Vault の `addStrategy` が検証）                                                                                                                                                                | invariant |
| STGY-INV-007 | `vault` / `underlyingToken` は `__BaseStrategy_init` 後不変                                                                                                                                                                                                                            | invariant |
| STGY-INV-008 | `sweepRewardToken` は Underlying と派生 Strategy が保護する position / receipt / accounting token を拒否する。`claimMerklRewards` は Underlying を Vault buffer への yield settlement としてのみ許可し、非 Underlying の protected token は claim 前に拒否する。両経路とも `principal` / `estimatedTotalUnderlying` を変更せず、非 Underlying・非 position 報酬は backing 会計外として Treasury へ送られる | unit      |
| STGY-INV-009 | Owner は `acceptOwnership` 成功時のみ変更され、`renounceOwnership` では変更されない                                                                                                                                                                                                    | unit      |
| STGY-INV-010 | UUPS upgrade は `upgrader` のみが承認でき、Owner / ALLOCATOR / vault では実行できない。`upgrader` はゼロアドレスに設定できない                                                                                                                                                         | unit      |
| STGY-INV-011 | `nonReentrantStrategy` が付いた Strategy entry point は同一 tx 内で nested 実行できず、外部 protocol / token callback から別の guarded entry point へ再入した場合は `ReentrantCall` で revert する                                                                                   | unit      |

---

## 9. セキュリティ要件（SEC）

### STGY-SEC-001: ALLOCATOR 鍵侵害時の被害境界

- Type: Security
- Statement: ALLOCATOR は Strategy の `sendToVault` / `sendProfitToVault` を直接呼べるが、いずれも資金は **Vault へ push** されるだけで任意アドレスへは送れない。`deposit`（外部プロトコルへの預入）は `onlyVault` で Vault 経由に限定され、宛先・比率は事前固定でなければならない。
- Verification: unit（ALLOCATOR が任意宛先へ送れない・`deposit` は onlyVault）, manual

### STGY-SEC-002: Owner 鍵侵害時の被害境界

- Type: Security
- Statement: Owner は `emergencyWithdraw` で Strategy 直接保有の Underlying を **Vault へ**送れる（送金先 Vault 固定、任意 `_to` を持たない）。対象は通常運用では発生しない事故的な滞留分の救済に限定される。Owner は非 Underlying・非 position 報酬の sweep / Merkl claim も実行できるが、宛先は Underlying reward なら Vault buffer、非 Underlying の通常 reward なら Vault の現在 Treasury に固定され、protected token は claim 前に拒否される。`upgradeTo` による悪意 Implementation 差し替えが最大の脅威であり、その承認権限は Owner から分離した専用 `upgrader`（holder = 共通 TimelockController）が持たなければならない——これにより Owner（Guardian multisig）鍵が侵害されても、可能な操作は「Vault への資金返送・Underlying reward の Vault 精算・通常 reward の Treasury sweep」という固定経路に限られ、ロジック差替や backing markdown はできない。緊急回収は Owner 側（即時）に残るため、timelock が緊急対応の被害を拡大する構成にならない（emergency bypass 不要）。
- Verification: unit（emergencyWithdraw 送金先固定・Owner からの upgrade 不可・Owner からの async pending valuation 変更不可）, manual（マルチシグ / Timelock 運用レビュー）

### STGY-SEC-003: emergencyWithdraw の送金先 Vault 固定

- Type: Security
- Statement: `emergencyWithdraw` は送金先を Vault に固定し、任意 `_to` を持ってはならない。Strategy owner（運用ロールと分離されうる）が GOV 承認なしに任意アドレスへ Underlying を抜く経路を塞ぐ。
- Verification: unit（任意アドレスへ送金不可・送金先 Vault のみ）

### STGY-SEC-004: AUM 過大評価への保守的会計

- Type: Security
- Statement: `estimatedTotalUnderlying()` の過大評価による収益取りすぎを防ぐため、評価は保守的に行い、Vault 側で `min(estimatedTotalUnderlying, principal)` 保守評価＋収益送付の `realizedYield()` 上限＋`managedUnderlying` surplus + buffer 上限（`transferYieldToTreasury`）の多段で防御しなければならない。
- `AsyncRequestStrategy` 系の `setPendingWithdrawalValuationBps` は async pending 部分の Vault 保守評価・backing に影響し得る price-moving 操作であるため、Strategy Owner / ALLOCATOR ではなく Vault の `WRITEOFF_ROLE` 保持者だけが呼べる。さらに下方変更は `pausedAllocation == true` を必須とし、incident log / bot pause / finalization evidence とセットで使う。
- Verification: unit（保守的評価・pending valuation bps は WRITEOFF_ROLE 限定・下方変更は allocation pause 後のみ）, integration（収益取りすぎ不可）

### STGY-SEC-005: 流動性不足の正常系扱い（DoS 耐性）

- Type: Security
- Statement: `sendToVault` は外部プロトコルが返せる額（`actual`）のみを push し、要求未満（`actual==0` 含む）は正常系として扱わなければならない。1 件の Strategy 不調で全体の回収が止まってはならない（buffer は `bufferTargetBps` / `bufferFloor` で在庫確保）。この「流動性不足を損失扱いしない」原則は[Architecture Decision Records](../../architecture/Architecture-Decision-Records.md#adr-006)の基盤でもある。本要件の no-revert は、外部が返せる額のみを push する clamp 型 Strategy が満たす: ERC4626 は `maxWithdraw` 等の保守利用で（[ERC4626Strategy](./ERC4626Strategy.md) §2 / §5）、AaveV3 は `_doWithdraw` を `min(要求額, Aave 会計値, aToken liquid underlying)` に cap し部分/0 を返すことで（[AAVE-FR-004](./AaveV3Strategy.md)）、いずれも illiquidity では revert しない。revert 伝播は reserve `paused` / Aave 全停止時の fail-closed のみ（[AAVE-ERR-002](./AaveV3Strategy.md) / [AAVE-ERR-003](./AaveV3Strategy.md)。全体回収の非停止は per-strategy 分離＋buffer で担保）。
- Verification: unit（`actual<requested` / `actual==0` で revert しない）, integration（1 Strategy 不調が全体を止めない）

### STGY-SEC-006: 非 Underlying・非 position 報酬 sweep の会計境界

- Type: Security
- Statement: `sweepRewardToken` は Underlying と protocol position / receipt / accounting token を拒否し、送金先を Vault の現在 `treasury` に固定しなければならない。`claimMerklRewards` は recipient を Strategy 自身に固定し、任意 calldata / 任意 recipient を受け取らず、Underlying reward は Vault buffer にのみ、非 Underlying reward は Vault の現在 `treasury` にのみ精算し、非 Underlying の protected position / receipt / accounting token は claim 前に拒否しなければならない。非 Underlying・非 position reward token は dToken backing / `estimatedTotalUnderlying` / `principal` に自動算入してはならず、backing 修復に使う場合は Treasury / backstop が Underlying に換金して明示的に補填する。
- Verification: unit（sweep の Underlying / position token 拒否・Treasury 宛先固定・fee-on-transfer 実着額・Merkl recipient 固定・protected token claim 前拒否・Underlying reward の Vault push）, manual（reward claim / swap adapter を追加する際の会計レビュー）

### STGY-SEC-007: Owner 権限喪失の防止

- Type: Security
- Statement: Owner 移譲は 2-step とし、誤アドレスへの 1-step 移譲で緊急回収・reward sweep・ownership 権限を失ってはならない。`renounceOwnership` は常に revert し、救済経路を恒久的に失う状態を防がなければならない。
- Verification: unit（2-step 移譲・renounce disabled・zero owner init revert）

### STGY-SEC-008: Upgrader 鍵侵害時の被害境界

- Type: Security
- Statement: UUPS upgrade は `upgrader` のみが承認でき、Owner / ALLOCATOR / vault からは実行できてはならない。`upgrader` 鍵が侵害されると悪意 Implementation 差替が可能になるため、`upgrader` は Owner と分離したマルチシグまたは外部 TimelockController / Safe module に置かなければならない。`setUpgrader` は現在の `upgrader` のみが実行でき、ゼロアドレスへの更新は禁止する。
- Verification: unit（upgrader のみ upgrade / setUpgrader 可、zero upgrader revert）, manual（upgrader 運用レビュー）

> **reentrancy / CEI**: BaseStrategy は OZ `ReentrancyGuardUpgradeable` を継承せず、既存 storage の後ろ（gap 1 slot）に `_reentrancyStatus` を置く local `nonReentrantStrategy` で shared mutating entry point（`deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / `emergencyWithdraw` / `sweepRewardToken` / `claimMerklRewards`）を保護する。派生 Strategy も外部 protocol / token / reward claim を呼ぶ public entry point に同じ guard を付ける。Vault 側の `receiveFromStrategy` は `nonReentrant`・実着額計上・exact delivery の cache 減額 / mismatch の cache 無効化で保護する。`sendProfitToVault` と Underlying reward claim は yield-only として Vault buffer へ直接 transfer し、principal / cache を動かさない。

---

## 10. ガバナンス・運用・アップグレード要件（GOV）

### STGY-GOV-001: Owner と upgrader の holder 構成

- Statement: Owner（`emergencyWithdraw` / 固有緊急回収 / reward sweep / ownership 操作の権限主体）は **Guardian multisig（即時のマルチシグ）**、UUPS アップグレード承認（`upgrader`）は Owner から分離し **共通 TimelockController** でなければならない（[STGY-FR-009](#stgy-fr-009-アップグレードuups) / [STGY-GOV-003](#stgy-gov-003-upgrader-timelock)）。いずれも単一 EOA を禁止する。
- Verification: manual（デプロイ構成レビュー・Owner / upgrader holder の assert）

### STGY-GOV-004: Owner 移譲と放棄

- Statement: Owner 移譲は 2-step（`transferOwnership` → `acceptOwnership`）で行う。誤アドレス指定時は `transferOwnership(address(0))` で pending をキャンセルできる。Owner 放棄は `RenounceOwnershipDisabled` で無効化する。
- Verification: unit, manual

### STGY-GOV-002: 緊急時オペレーション

- Statement: 外部プロトコルのスマコン / 経済攻撃が疑われる場合、GUARDIAN は Vault の `emergencyDisableStrategy`（即時、[CollateralVault 要件定義](../CollateralVault.md) VAULT-FR-019）で当該 Strategy への新規投下を止め、Owner（Guardian multisig）は固有の緊急回収関数（`emergencyWithdrawFrom{Protocol}()`・Vault への原子直送）で資金を Vault へ退避できなければならない。残余の idle は `emergencyWithdraw` で回収する。集中投下は Vault 側 `cap` で回避する。
- Verification: manual（緊急時 runbook レビュー）, integration（updateStrategy→緊急回収）

### STGY-GOV-003: Upgrader timelock

- Statement: Strategy 自体に内蔵 timelock は置かない。**UUPS upgrade の承認権限（`upgrader`）を Owner から分離し、holder を共通 TimelockController にする**（Vault `GOV_ROLE`・dToken Owner と同一 Timelock を共用する）。delay値は [Day1 Parameter Manifest](../../../../Parameters.md) `PRM-GOV-COMMON-TIMELOCK-DELAY`、holder構成は [Protocol Role Holder Manifest](../../../../protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md) を正本とする。Owner（緊急回収・reward sweep）は Guardian multisig（即時）とし、外部プロトコル事故時の緊急回収に遅延を掛けない——緊急側に timelock が掛からないため emergency bypass は不要。設計判断の正本: [protocol/product/policies/Governance-Roles-Timelock.md](../../policies/Governance-Roles-Timelock.md)。関連: [STGY-FR-009](#stgy-fr-009-アップグレードuups) / [STGY-SEC-002](#stgy-sec-002-owner-鍵侵害時の被害境界)。
- Verification: manual（デプロイ構成レビュー・holder assert）

### STGY-GOV-005: Upgrader 専用 holder

- Statement: `upgrader` は Owner / ALLOCATOR / Vault / deployer と同一主体にしてはならず、UUPS upgrade 専用の holder（Day-1 方針では共通 TimelockController）として構成する。これにより緊急回収を担う Owner 鍵の侵害が即時 upgrade 権限へ直結しない状態を保つ。非権限主体による upgrade / `setUpgrader` の拒否は [STGY-INV-010](#8-不変条件inv) / [STGY-SEC-008](#stgy-sec-008-upgrader-鍵侵害時の被害境界) で検証する。
- Verification: manual（デプロイ構成レビュー・holder assert）

---

## 11. イベント・監視要件（EVT）

BaseStrategy / AsyncRequestStrategy が発火する共通イベント:

| ID           | イベント                                                                                           | 用途（off-chain）                                                                                                               |
| ------------ | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| STGY-EVT-001 | `Deposited(uint256 amount, uint256 newPrincipal)`                                                  | `deposit`（外部プロトコルへの預入）完了の検知・累積投下額・principal 推移                                                       |
| STGY-EVT-002 | `SentToVault(address caller, uint256 requested, uint256 actual, uint256 newPrincipal)`             | `sendToVault`（元本 push 回収）時。`actual` は Vault 実受領額 `sent`。`requested − actual` が回収ギャップ（流動性逼迫シグナル） |
| STGY-EVT-003 | `ProfitSentToVault(address caller, uint256 yield, uint256 actual)`                                 | `sendProfitToVault`（収益 push）時。収益送付の追跡                                                                              |
| STGY-EVT-004 | `PrincipalWrittenOff(uint256 amount, uint256 newPrincipal)`                                        | `writeoffPrincipal`（元本毀損確定）時。`amount` は実際に減った `principal`                                                      |
| STGY-EVT-005 | `EmergencyWithdrawn(uint256 amount)`                                                               | `emergencyWithdraw`（直接保有分を Vault へ）時                                                                                  |
| STGY-EVT-006 | `Emergency*Withdrawn(uint256 amount)`（派生固有・推奨）                                            | 派生固有の緊急回収関数（`emergencyWithdrawFrom{Protocol}()`）発火時                                                            |
| STGY-EVT-007 | `RewardTokenSwept(address token, address treasury, uint256 requested, uint256 received)`           | 非 Underlying・非 position reward token の Treasury sweep。`requested - received` は fee-on-transfer 等の実着差分               |
| STGY-EVT-008 | `OwnershipTransferStarted(address previousOwner, address newOwner)` / OZ `OwnershipTransferred`    | Owner 移譲の開始・確定                                                                                                          |
| STGY-EVT-009 | `UpgraderUpdated(address oldUpgrader, address newUpgrader)` / ERC1967 `Upgraded(newImpl)`          | Upgrader 変更と UUPS upgrade の追跡                                                                                             |
| STGY-EVT-010 | `MerklRewardsClaimed(address distributor, address token, uint256 cumulativeAmount, uint256 swept)` / `MerklUnderlyingRewardsClaimed(address distributor, address token, uint256 cumulativeAmount, uint256 sentToVault)` | Merkl claim の settlement 追跡。非 Underlying は Treasury 実着額を `RewardTokenSwept` と照合し、Underlying は Vault buffer 実着額を監視 |
| STGY-EVT-011 | `PrincipalReturned(uint256 amount, uint256 newPrincipal)`                                          | 固有緊急回収で Vault 実受領額を returned principal として記帳した時。`amount` は実際に減った `principal`                        |
| STGY-EVT-012 | `PendingWithdrawalValuationBpsUpdated(uint256 oldBps, uint256 newBps)`                             | async pending withdrawal の保守評価 bps 変更。incident log / finalization evidence と照合する                                  |

**共通の監視指標**:

| 指標                                             | 取得元                                                                                                                                                                                                                       |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AUM（`estimatedTotalUnderlying()`）の経時推移    | Vault の `getStrategyStatuses()` / subgraph で定期スナップショット                                                                                                                                                           |
| 累積投下額・累積回収額・principal 推移           | Vault の `StrategyAllocated` と Strategy イベント（STGY-EVT-001 / STGY-EVT-002 / STGY-EVT-003）                                                                                                                              |
| 回収要求 vs 実 push のギャップ                   | `SentToVault` の `requested − actual`（= Vault 実受領 `sent`）。0 でない場合は流動性逼迫のシグナル（[CollateralVault 要件定義](../CollateralVault.md)）                                                                      |
| allocation deposit reject                       | Vault の `StrategyAllocationSkipped` のうち、同時点の `getStrategyStatuses()` が live available かつ cap 残ありのもの。外部 venue の供給停止・cap 到達を調査                                                             |
| `estimatedTotalUnderlying` と `principal` の乖離 | `getStrategyStatuses()` の `estimatedLoss` / `estimatedGain`。マイナス＝元本毀損、プラス＝推定上振れのシグナル。外部プロトコル損失が評価 view に現れない場合は自動検知できず、回収・`writeoffPrincipal`・backstop 運用が必要 |
| async pending valuation bps                      | `PendingWithdrawalValuationBpsUpdated` と `pendingWithdrawalValuationBps()`。Lido / Etherfi 等の claim 前保守割引・復元の監査証跡                                                                                           |
| 外部プロトコルのヘルス                           | 各プロトコル固有の dashboard / Governance フォーラム（オフチェーン）                                                                                                                                                         |

Strategy incident 時の損失確定、回収、補填、writeoff、および運営 liquidation bot の停止・再開判断は [Strategy Incident / Liquidation Safety Runbook](../../../operations/runbooks/Strategy-Incident-Liquidation-Safety-Runbook.md) を運用正本とする。Aave / ERC4626(Morpho・Euler) / Lido / asset-transforming Strategy では `estimatedTotalUnderlying()` が表す会計と一時流動性制約の意味が異なるため、branch symbol ではなく実際の Strategy kind で判定する。

---

## 12. 失敗時・異常系挙動（ERR）

### STGY-ERR-001: 共通リスクと失敗時挙動

全 Strategy に共通して適用される（個別 Strategy 固有のリスクは各子ドキュメント／§15 規約に従って記載）:

1. **外部プロトコルのスマコン / 経済攻撃リスク** — Vault 側 `cap` で集中投下を回避、緊急時は GUARDIAN が Vault の `emergencyDisableStrategy` で新規配分を即時停止し、Strategy Owner（Guardian multisig）が固有の緊急回収関数で対応する。恒久的な cap/weight 変更や再有効化は GOV（Timelock 経由）が行う（[STGY-GOV-002](#stgy-gov-002-緊急時オペレーション)）
2. **流動性リスク** — `sendToVault` は外部プロトコルが返せる額（`actual`）のみを push し、要求未満は正常系として扱う（1 件の不調で全体回収は止まらない＝[STGY-SEC-005](#stgy-sec-005-流動性不足の正常系扱いdos-耐性)）。`bufferTargetBps` / `bufferFloor` で在庫を確保
3. **AUM 評価リスク** — `estimatedTotalUnderlying()` が過大評価だと収益取りすぎの恐れ。Vault は `min(estimatedTotalUnderlying, principal)` で保守評価し、収益送付は `realizedYield()` 上限＋buffer 上限で防御（[STGY-SEC-004](#stgy-sec-004-aum-過大評価への保守的会計) / [CollateralVault 要件定義](../CollateralVault.md)）
4. **ALLOCATOR / Owner / Upgrader 鍵侵害** — [STGY-SEC-001](#stgy-sec-001-allocator-鍵侵害時の被害境界) / [STGY-SEC-002](#stgy-sec-002-owner-鍵侵害時の被害境界) / [STGY-SEC-008](#stgy-sec-008-upgrader-鍵侵害時の被害境界) 参照

**エラーカタログ**

| エラー                       | 契機                                                                                                                                                                                            |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `OnlyVault`                  | vault 以外の `deposit` / `writeoffPrincipal`（[STGY-SEC-001](#stgy-sec-001-allocator-鍵侵害時の被害境界)）                                                                                      |
| `Unauthorized`               | ALLOCATOR 以外の `sendToVault` / `sendProfitToVault`、upgrader 以外の UUPS upgrade / `setUpgrader`、Strategy 自身以外からの `deployUnderlying`                                                  |
| `DepositRecoveryFailed`      | deposit reject 後に declared/received が一致しない、Vault 返送が失敗する、または Strategy 減少額 / Vault 増加額が純受領額と一致しない場合                                                     |
| `ZeroAddress`                | 初期化時の `_vault` / `_underlying` / `_owner` / `_upgrader`、`setUpgrader(address(0))`、`sweepRewardToken` のゼロ token / ゼロ treasury、または `claimMerklRewards` のゼロ distributor / token |
| `NotContract(address target)` | 初期化時に `_vault` / `_underlying` / 派生 Strategy の外部プロトコル依存先へ EOA または未デプロイ address を指定した場合                                                                        |
| `ReentrantCall`              | `nonReentrantStrategy` guard 実行中に別の guarded Strategy entry point へ nested call した場合                                                                                                   |
| `CannotSweepProtectedToken`  | `sweepRewardToken` に Underlying または派生 Strategy が保護する position / receipt / accounting token を指定した場合、または `claimMerklRewards` に Underlying 以外の protected token を指定した場合 |
| `InvalidMerklDistributor`    | `claimMerklRewards` に EOA / 未デプロイ distributor を指定した場合                                                                                                                              |
| `InvalidMerklClaim`          | `claimMerklRewards` の token / amount / proof 配列長不一致、または空配列                                                                                                                        |
| `TooManyMerklTokens`         | `claimMerklRewards` の token 数が `MAX_MERKL_TOKENS_PER_CLAIM`（実装定数 `16`）を超える場合                                                                                                      |
| `DuplicateMerklToken`        | `claimMerklRewards` の token 配列に同一 token が複数回含まれる場合                                                                                                                              |
| `AsyncPendingRequestLimitExceeded` | `AsyncRequestStrategy` 系の未 claim request 総数が `MAX_ASYNC_PENDING_REQUESTS`（実装定数 `128`）を超える場合                                                                               |
| `RenounceOwnershipDisabled`  | `renounceOwnership` 呼び出し（STGY-FR-011 / STGY-SEC-007）                                                                                                                                      |

### STGY-ERR-002: 非同期な外部プロトコルの取り扱い

push モデルでは、外部プロトコルが同期（即時引き出し可）か非同期（unbond 等の待機を要する）かの違いを **Strategy 実装の内部に閉じる**。Vault 側は `requestKey` を保持せず、`isAsyncWithdraw` 分岐・非同期清算経路（`claimWithdraw` / `claimHarvest` 相当）を持たない。元本返却・cache 減額系は `receiveFromStrategy` で buffer に入り、yield-only push は Strategy から Vault buffer への直接 transfer として入る。元本/収益の区別と principal 会計は Strategy 側に閉じるため、「非同期元本回収の清算経路が無い」「収益 claim が requestKey の用途を検証しない」といった課題は構造的に発生しない。

非同期な外部プロトコル（Lido stETH + Withdrawal Queue 等）を Strategy 化する場合の実装方針:

- `sendToVault` / `sendProfitToVault` の内部 `_doWithdraw` は、**その時点で即時に引き出せる額のみ**を返す。`sendToVault` は `receiveFromStrategy` 経由で元本返却として push し、`sendProfitToVault` は yield-only として Vault buffer へ直接 transfer する（即時引き出せなければ `0` を返し、unbond 完了後の呼び出しで実際の額を push する）。`sent` が要求額に満たないことは正常系として扱う（[STGY-SEC-005](#stgy-sec-005-流動性不足の正常系扱いdos-耐性)）
- unbond 要求の発行・待機・受領といった複数ステップの管理は当該 Strategy の内部状態に閉じ、`IStrategy`（§5）の表層には現れない
- `AsyncRequestStrategy` 系の未 claim request 総数は `MAX_ASYNC_PENDING_REQUESTS`（128）で上限管理し、ALLOCATOR 誤作動や鍵侵害時の storage bloat / UI 取得不能化を防ぐ。claim batch は 1 tx あたり最大 32 request に制限するため、keeper / UI は `getPendingRequestIds()` の結果を chunk して複数 tx で claim する
- LidoStrategy は本項の実装例であり、`requestLidoWithdrawal` / `claimLidoWithdrawals` を Strategy 固有 keeper 関数として持つ一方、`IStrategy` 表層は同期 Strategy と同じまま維持する

---

## 13. 受け入れ基準・検証計画

各要件の合格条件 = 下表の検証手段を満たすこと（テスト名・実行結果は本書に書かない＝手段の種別まで）。

| ID                | 要件（要約）                                                                                                               | 検証手段                                   |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| STGY-FR-001       | deposit（onlyVault・self-call 隔離・成功時 principal 加算・reject 時 exact recovery / 0 return・不完全回収 fail-closed）   | unit, integration                          |
| STGY-FR-002       | sendToVault（ALLOCATOR 限定・`sent` ベース減算・早期 return）                                                              | unit, fork/integration                     |
| STGY-FR-003       | sendProfitToVault（ALLOCATOR 限定・principal 不変・早期 return）                                                           | unit, fork/integration                     |
| STGY-FR-004       | writeoffPrincipal（onlyVault・`min` クランプ）                                                                             | unit, invariant=STGY-INV-002               |
| STGY-FR-005       | emergencyWithdraw（onlyOwner・送金先 Vault 固定・汎用 idle 救済は principal 不変、固有緊急回収は returned principal 記帳） | unit, integration                          |
| STGY-FR-006       | 派生 hook（_doDeposit / _doWithdraw / _estimatedTotalUnderlying）                                                          | unit, integration/fork                     |
| STGY-FR-007       | BaseStrategy 初期化（ゼロ / contract code チェック・再初期化 revert・owner/upgrader 保存・forceApprove(vault)）             | unit, manual                               |
| STGY-FR-008       | view getter（realizedYield 恒等・保守的評価・underlying 一致）                                                             | unit, integration                          |
| STGY-FR-009       | アップグレード（upgrader 限定・Owner/運用ロール revert・旧 proxy の upgrader migration・storage layout）                   | unit, manual                               |
| STGY-FR-010       | sweepRewardToken（非 Underlying・非 position 報酬・送金先 current treasury・実着額・全量指定）                             | unit                                       |
| STGY-FR-011       | Owner 移譲（2-step）と renounce 無効化                                                                                     | unit, manual                               |
| STGY-FR-012       | claimMerklRewards（distributor 検証・recipient 固定・protected token claim 前拒否・Vault/Treasury 実着額）                 | unit                                       |
| STGY-INV-001..011 | §8 各不変条件                                                                                                              | unit / invariant（§8 記載どおり）          |
| STGY-SEC-001..008 | §9 各セキュリティ要件                                                                                                      | unit, manual, integration（§9 記載どおり） |
| STGY-EVT-001..012 | §11 各イベント発火                                                                                                         | unit                                       |
| STGY-ERR-001..002 | §12 共通リスク・非同期取り扱い                                                                                             | manual, integration                        |

---

## 14. 未決事項（TBD）

### STGY-TBD-001

Resolved: `STGY-FR-009`、`STGY-GOV-001`、`STGY-GOV-003`、`STGY-SEC-002` に反映済み。

### STGY-TBD-002

Resolved: `STGY-SEC-005`、`AAVE-FR-004`、[ERC4626 §2](./ERC4626Strategy.md#2-設計方針) に反映済み。

---

## 15. 参考資料

- [Product Overview](../../Product-Overview.md) — 全体アーキテクチャ・責務分離・コア無改変方針（§5）
- [CollateralVault 要件定義](../CollateralVault.md) — `allocate` / push 受入口 `receiveFromStrategy` / `writeoffStrategyPrincipal` / `transferYieldToTreasury` / ロール定義（`ALLOCATOR_ROLE`）/ buffer・cap・weights の正本
- [dToken 要件定義](../dToken.md) — 担保トークン（Strategy が運用する Underlying をラップする請求権トークン）。Underlying 後付け確定は `DTKN-FR-002`、mint の cap/未確定ガードは `DTKN-FR-004`
- [AaveV3Strategy 要件定義](./AaveV3Strategy.md) — Aave V3 への個別 Strategy 実装（本書の子ドキュメント。hook 実装・固有緊急回収関数・固有リスク）
- [ERC4626Strategy 要件定義](./ERC4626Strategy.md) — Morpho Vault / EulerEarn 等の ERC-4626 vault adapter（share donation 防御・固有緊急回収関数・固有リスク）
- [LidoStrategy 要件定義](../../../../archive/LidoStrategy.md) — Lido stETH + Withdrawal Queue への非同期 Strategy 実装（STGY-ERR-002 の実装例）
- [SkyUsdcSUsdsStrategy 要件定義](./SkySUsdsStrategy.md) — dUSDC branch の USDC -> USDS -> sUSDS asset-transforming Strategy
- [EtherfiWeETHStrategy 要件定義](../../../../archive/EtherfiWeETHStrategy.md) — WETH underlying branch 向けの Ether.fi eETH / weETH async Strategy
- [Liquity-v2-Core-Spec](../Liquity-v2-Core-Spec.md) — 🔵 コアの担保・清算・Redemption 挙動（再仕様化しない）
- [要件定義ドキュメント標準](../../../../Requirements-Spec-Standard.md) — 本書が従う標準

### Deploy 選択と検証

`DeployLiquity2` の DF dToken wiring は active branch ごとに Strategy kind を選択できる。Strategy kind / weight / cap は deploy 時に明示必須とし、未指定なら fail-fast する。Aave 固定・100% weight・cap 無限を暗黙既定にしない。

- `DF_STRATEGY_KIND` / `DF_STRATEGY_KIND_<branchIndex>`: `aave` / `erc4626` / `etherfi-weeth` / `sky-susds` / `none`。branch 個別 env があればそちらを優先し、なければ共通 env を使う。どちらもなければ deploy 停止。現行 code は実装同期前の legacy `lido` も認識するが、[LIDO-GOV-001](../../../../archive/LidoStrategy.md) に従い公式 deploy wiring から除外する。
- `none` は active branch の Underlying / Vault / dToken / PriceFeed / CollateralYieldZapper を残したまま Strategy だけを登録しない。`DF_STRATEGY_WEIGHT_BPS_<branchIndex> == 0`、`DF_STRATEGY_CAP_<branchIndex> == 0`、Vault 登録 Strategy 数 0 が deploy-tail / handover verify の条件になる。
- `DF_STRATEGY_WEIGHT_BPS` / `DF_STRATEGY_WEIGHT_BPS_<branchIndex>`: Vault 登録時の weight。branch 個別 env があればそちらを優先し、なければ共通 env を使う。どちらもなければ deploy 停止。
- `DF_STRATEGY_CAP` / `DF_STRATEGY_CAP_<branchIndex>`: Vault 登録時の cap。branch 個別 env があればそちらを優先し、なければ共通 env を使う。どちらもなければ deploy 停止。
- `erc4626`: `DF_STRATEGY_ERC4626_VAULT_<branchIndex>` を必須とし、`ERC4626Strategy.initialize` が `asset() == underlying` を検証する
- legacy `lido`: 実装同期までの現行 code は WETH branch 用 env `DF_STRATEGY_LIDO_STETH_<branchIndex>` / `DF_STRATEGY_LIDO_WSTETH_<branchIndex>` / `DF_STRATEGY_LIDO_WITHDRAWAL_QUEUE_<branchIndex>` / `DF_STRATEGY_LIDO_REFERRAL_<branchIndex>` を読む。source / test は残すが、公式 selector・deploy / register helper・env reader は削除し、指定時は generic unknown-kind fallback で失敗させる
- `etherfi-weeth`: WETH branch のみ選択可能。`DF_STRATEGY_ETHERFI_LIQUIDITY_POOL_<branchIndex>` / `DF_STRATEGY_ETHERFI_EETH_<branchIndex>` / `DF_STRATEGY_ETHERFI_WEETH_<branchIndex>` / `DF_STRATEGY_ETHERFI_WITHDRAW_ADAPTER_<branchIndex>` / `DF_STRATEGY_ETHERFI_WITHDRAW_REQUEST_NFT_<branchIndex>` を必須、`DF_STRATEGY_ETHERFI_REFERRAL_<branchIndex>` は任意
- `sky-susds`: dUSDC branch（branch index 1）かつ deployment-wide `USDC` と同一 Underlying のみ選択可能。`DF_STRATEGY_SKY_USDS_<branchIndex>` / `DF_STRATEGY_SKY_SUSDS_VAULT_<branchIndex>` / `DF_STRATEGY_SKY_USDC_USDS_PSM_WRAPPER_<branchIndex>` / `DF_STRATEGY_SKY_MAX_CONVERSION_LOSS_BPS_<branchIndex>` を必須。deploy script が監査対象の concrete converter を新規 deploy する

deploy-tail verify は具体型（Aave など）へ cast せず、BaseStrategy 共通の `vault()` と `IStrategy.underlying()` で branch wiring を検証する。各外部プロトコル固有アドレスの妥当性（ゼロアドレス / 未デプロイ contract / semantic consistency）は、派生 Strategy の `initialize` と子ドキュメントの fork/integration test が担う。

### 子ドキュメントの章立て規約

各個別 Strategy 子ドキュメントは、本書に集約された共通事項を参照する形で、以下の章立てに揃える（共通事項は本書を参照させ、子ドキュメントには外部プロトコル固有事項のみを書く）:

1. **対象 Underlying / 外部プロトコル** — どの Underlying のどのプロトコル（バージョン・チェーン・Pool / Adapter アドレス）を扱うか
2. **追加ストレージ** — BaseStrategy が持たない、当該 Strategy 固有の状態変数
3. **`initialize`** — 引数・処理フロー・事前 approve
4. **hook の実装内容** — 外部プロトコル I/F へのマッピング（`_doDeposit` / `_doWithdraw` / `_estimatedTotalUnderlying`）
5. **固有の緊急回収関数** — `emergencyWithdrawFrom{Protocol}()` など
6. **デプロイ・初期設定パラメータ** — 対応 Underlying 別の Pool / aToken / Cap / weight 等
7. **報酬トークンの取扱い** — claim 経路 / swap 必要性 / Treasury への帰着
8. **固有のリスク** — 外部プロトコル固有のリスクと緩和策（共通リスクは [STGY-ERR-001](#stgy-err-001-共通リスクと失敗時挙動) を参照させる）
9. **既知の TODO / 未決事項**
10. **参考資料**

子ドキュメントは最初に AaveV3Strategy を作成。ERC-4626 形式の Morpho / Euler 等は、`asset()==underlying` の場合のみ ERC4626Strategy を共通 adapter として扱う。ERC-4626 では表現できない Etherfi weETH、USDC -> USDS -> sUSDS、Yo Protocol / sUSDe / sGHO 等は必要に応じて個別 Strategy を追加する。

新規子ドキュメントを作る前に、§2.2 の必要十分条件を満たさないことを確認する。venue 名だけが違い、`asset()==underlying` の ERC-4626 として扱える場合は `ERC4626Strategy` の採用条件・runbook・preflight を更新し、専用 Strategy を増やさない。
