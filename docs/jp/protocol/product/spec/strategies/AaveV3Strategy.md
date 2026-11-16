# 🟢 AaveV3Strategy 要件定義

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Draft（実装あり・要件の正本化中） |
| Owner | DeltaForesight |
| 対象コントラクト | `contracts/src/Strategies/AaveV3Strategy.sol`（Aave V3 個別 Strategy・`BaseStrategy` を継承・UUPS） |
| 関連ドキュメント | [Strategy](./Strategy.md)（`IStrategy` / `BaseStrategy` / push モデル・共通権限・共通リスクの正本）/ [CollateralVault](../CollateralVault.md)（whitelist / addStrategy / receiveFromStrategy 呼出側）/ [Product-Overview](../../Product-Overview.md)（アーキ・責務分離） |

> 本書は [要件定義ドキュメント標準](../../../../Requirements-Spec-Standard.md)に従う。要件・不変条件・セキュリティ要件には永続 ID（`AAVE-…`）を付し、相互参照は ID で行う。
> **本書のスコープ**: `AaveV3Strategy` の **Aave V3 固有の要件**のみを扱う。Strategy 共通事項（`IStrategy` / `BaseStrategy` 規約・Vault との結合・共通権限・共通リスク・共通イベント）は親ページ [Strategy 要件定義](./Strategy.md) を正本とし、本書では名前で参照する。

---

## 1. 目的・スコープ・非責務

`AaveV3Strategy` は CollateralVault が配分した Underlying を **Aave V3 へ供給して利回りを得る**個別 Strategy（[Strategy 要件定義](./Strategy.md) の `BaseStrategy` を継承する子実装）。1 つのインスタンスが 1 つの Underlying と 1 つの Aave V3 reserve に 1:1 で対応し、push モデル（Strategy が引き出して Vault へ push する）で動作する。

- **本書が規定する**: 対象 Underlying と Aave V3 アドレス（Pool / aToken）/ Aave 固有の追加ストレージ（`aavePool` / `aToken` / `_ownScaledBalance`）/ `initialize`（6 引数固定・Pool への max approve）/ Aave I/F へマッピングする 3 hook（`_doDeposit` = `aavePool.supply` / `_doWithdraw` = `aavePool.withdraw` / `_estimatedTotalUnderlying` = scaled balance × normalized income）/ Aave 固有の緊急回収関数 `emergencyWithdrawFromAave` / Aave `RewardsController` claim 関数 `claimAaveRewards` / 報酬トークンの取扱い方針（着金済み reward は `BaseStrategy.sweepRewardToken`、Merkl 報酬は `BaseStrategy.claimMerklRewards`、Aave 報酬は `claimAaveRewards`。ただし aToken は protected token として sweep / claim settlement 不可）/ Aave 固有のリスク（frozen・paused・supply cap・utilization 100%・aToken 評価・第三者 donation 耐性）。
- **本書が規定しない（非責務・他文書）**:
  - `IStrategy` 共通インターフェース・`BaseStrategy` が提供する `deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / `principal` / `realizedYield` / `estimatedTotalUnderlying` / `underlying` 本体・共通 `emergencyWithdraw`（送金先 Vault 固定）・push モデルの会計と `principal` 管理 → [Strategy 要件定義](./Strategy.md)（`BaseStrategy`）
  - Vault との結合（whitelist / weights / cap / `addStrategy` / `receiveFromStrategy` / 障害耐性）→ [CollateralVault 要件定義](../CollateralVault.md)
  - branch の dToken / Underlying mapping・mintCap・buffer 等の Day-1 値 → [Parameters](../../../../Parameters.md)
  - Aave Strategy の採用状態 → [Strategy Selection Policy](../../../operations/policies/Strategy-Selection-Policy.md)
  - Day-1 の登録kind・cap・weight → [Mainnet Deploy Env Freeze Runbook](../../../launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md) と生成Manifest
  - deploy mode・wiring shape・Manifest schema → [Deployment Configuration Spec](../../../../engineering/guides/Deployment-Configuration-Spec.md)
  - 🔵 Liquity コアの担保・清算・Redemption 挙動 → [Liquity-v2-Core-Spec](../Liquity-v2-Core-Spec.md)
- **責務境界（あえて知らない）**: `AaveV3Strategy` は「誰の担保として配分されるか」「Vault の buffer / weights がどう決まるか」を前提とせず、純粋に「受け取った Underlying を Aave V3 という 1 つの外部プロトコルにどう預け・どう取り戻し・いくらの価値があるか」という外部プロトコル I/F の変換層に責任を持つ。

---

## 2. 背景・設計方針

`AaveV3Strategy` は [Strategy 要件定義](./Strategy.md) の push モデルと「1 Strategy = 1 Underlying = 1 外部運用先」原則に沿った、Aave V3 への最初の具体実装である。

- **Aave V3 を選ぶ根拠（採用理由）**:
  - **対応 Underlying が広い**: `AaveV3Strategy` は、Ethereum mainnet に Aave V3 reserve が存在する USDC / USDT / WETH / WBTC などに適用できる。ただし Day-1 採用対象は Strategy Selection Policy とMainnet Deploy Env Freeze Runbookに従う。
  - **同期引出可（liquid reserve 分）**: Aave V3 の `withdraw` は unbond を持たないが、reserve utilization / 実 underlying 流動性に制約される。`_doWithdraw` は要求額を Aave 会計値と aToken の liquid underlying の小さい方に抑え、Strategy 自身へ引き出す。その後、`BaseStrategy` の `sendToVault` は `receiveFromStrategy` 経由で元本返却として Vault へ push し、`sendProfitToVault` は yield-only として Vault buffer へ直接 transfer する（[Strategy 要件定義](./Strategy.md) の push モデル）。
  - **流動性の厚さ**: 主要担保で utilization が常識的範囲に収まり、流動性不足による `withdraw` revert の確率が低い。
  - **オラクル参照不要**: aToken の scaled balance × `getReserveNormalizedIncome` で利息込みの Underlying 換算値を算出できる（第三者 donation を排除するため `balanceOf` ではなく自己管理の scaled balance を用いる。[AAVE-FR-005](#aave-fr-005-_estimatedtotalunderlying評価額の算出) / [AAVE-SEC-002](#aave-sec-002-第三者-donation-による-aum-水増しの排除)）。
  - **Sepolia と mainnet が 1:1**: テストデプロイが容易（[AAVE-GOV-002](#aave-gov-002-testnet-先行)）。
- **投資先を Strategy 側で動かせないようにする**: `aavePool` / `aToken` / Underlying / Pool への approve はすべて `initialize` で固定し、`setAavePool` / `setAToken` の類を一切設けない。後から投資先を差し替えたい場合は **Strategy ごと作り直して Vault のホワイトリスト＆登録を入れ替える**運用方針とすることで、storage migration リスクと「運用ロールが投資先を動かす」攻撃面を排除する（[AAVE-SEC-001](#aave-sec-001-投資先アドレスの-initialize-時固定) / [AAVE-GOV-001](#aave-gov-001-投資先差し替えは-strategy-再作成)）。
- **第三者 donation を AUM に含めない**: Aave V3 の `supply(onBehalfOf=任意)` は permissionless で、誰でも当 Strategy の aToken を増やせる。`aToken.balanceOf` をそのまま AUM にすると第三者の donation が `realizedYield` を水増しし収益送付経由で Treasury に任意額を流し込めてしまうため、当 Strategy 自身の supply / withdraw で増減した `_ownScaledBalance` を AUM 評価の基礎とする（[AAVE-SEC-002](#aave-sec-002-第三者-donation-による-aum-水増しの排除)）。
- **緊急回収は Aave→Vault 原子直送・宛先固定**: `emergencyWithdrawFromAave` は Aave からその時点で liquid な分を引き出し、Vault への push（`receiveFromStrategy`）と returned principal 記帳を**同一 Tx で原子的に**行う。引き出した Underlying を Strategy idle に滞留させると、評価（`_estimatedTotalUnderlying` は idle 非算入）にも Vault buffer にも算入されない宙吊りが生まれ、`backingRatio` の過小評価 → 当該ブランチ Trove の不当清算を誘発しうるため、中間状態を構造的に排除する。宛先は Vault 固定で、Owner 鍵が侵害されても任意宛先には資金を抜けない（[AAVE-FR-006](#aave-fr-006-emergencywithdrawfromaave緊急回収) / [AAVE-SEC-003](#aave-sec-003-緊急回収の宛先固定と権限分離)）。`BaseStrategy.emergencyWithdraw`（idle→Vault）は donation・残余の回収用に併存する。
- **非 Underlying 報酬は backing に混ぜない**: Aave incentives / Merkl 等の reward token は aToken 利息とは別資産であり、`_estimatedTotalUnderlying()` / `realizedYield()` / dToken backing には含めない。Strategy に着金済みの reward token は共通 `BaseStrategy.sweepRewardToken` で Vault の現在 Treasury へ送り、Merkl の標準 distributor 報酬は共通 `BaseStrategy.claimMerklRewards` で claim + sweep できる。Aave `RewardsController` 報酬は Owner が `claimAaveRewards` で claim でき、reward が Underlying の場合だけ Vault buffer へ yield として直送し、非 Underlying reward は Treasury へ sweep する。aToken は Aave position / accounting token であり reward ではないため sweep / Merkl claim / Aave claim settlement 前に拒否する。reward を swap して Underlying 化する経路や、非 Underlying reward の backing 補填は本 Strategy の現行実装には含めない（[AAVE-FR-007](#aave-fr-007-claimaaverewardsaave-rewardscontroller-報酬claim) / [AAVE-ERR-005](#aave-err-005-報酬トークン取りこぼし) / [AAVE-TBD-005](#aave-tbd-005)）。

---

## 3. 用語・外部依存・前提

**用語**

| 用語 | 意味 |
| --- | --- |
| Underlying | 当 Strategy が運用する実担保資産（USDC / USDT / WETH / WBTC のいずれか 1 つ） |
| vault | この Strategy を登録する対応 CollateralVault（`BaseStrategy` が `initialize` で固定） |
| Owner | 当 Strategy の緊急操作主体（Guardian multisig・即時のマルチシグ。2026-06-12 確定） |
| upgrader | UUPS アップグレード承認の専用権限（Owner から分離。holder = 共通 TimelockController。[Strategy 要件定義](./Strategy.md) STGY-FR-009） |
| ALLOCATOR | Vault の `ALLOCATOR_ROLE`。`sendToVault` / `sendProfitToVault` を起動する運用ロール（[Strategy 要件定義](./Strategy.md)） |
| aToken | 当該 Underlying に対応する Aave V3 の利息付きトークン（`scaledBalanceOf` を参照） |
| scaled balance | aToken の RAY 精度の正規化残高。`× getReserveNormalizedIncome / RAY` で実残高に戻る |
| `_ownScaledBalance` | この Strategy 自身の supply / withdraw で増減した scaled balance。第三者 donation を含まない |
| normalized income | `getReserveNormalizedIncome`（RAY = 1e27）。scaled → 利息込み Underlying 換算の係数 |
| donation | 第三者が `supply(onBehalfOf=this)` で当 Strategy の aToken を勝手に増やす行為 |

**外部依存（信頼する外部）**

- **Aave V3 Pool（`IAaveV3Pool`）** — `supply` / `withdraw` / `getReserveNormalizedIncome` の呼び出し先。Pool が侵害されないこと、reserve の会計（scaled balance / normalized income）が健全であることを信頼する。Pool が侵害されると Strategy の一時残高や aToken ポジションが影響を受けうる（[AAVE-ERR-001](#aave-err-001-aave-reserve-設定変更frozen--paused--supply-cap)）。
- **Aave V3 aToken（`IAToken`）** — `scaledBalanceOf(this)` / `balanceOf(this)` / `UNDERLYING_ASSET_ADDRESS()` を参照。当 Underlying に正しく対応する aToken であることを `initialize` で検証する（誤設定は致命的バグ。[AAVE-SEC-004](#aave-sec-004-aave-pool--atoken-アドレス誤設定の防止)）。
- **Aave V3 RewardsController（`IAaveRewardsController`）** — `claimRewards(assets, amount, to, reward)` の呼び出し先。`claimAaveRewards` は `assets` を当 Strategy の `aToken` 1 要素に固定し、任意の Aave position の claim adapter として悪用されないようにする（[AAVE-FR-007](#aave-fr-007-claimaaverewardsaave-rewardscontroller-報酬claim)）。
- **`BaseStrategy`（親 [Strategy 要件定義](./Strategy.md)）** — `deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / `emergencyWithdraw` / `principal` / `realizedYield` / `estimatedTotalUnderlying` / `underlying` 本体と push モデルの会計を信頼して継承する。

**前提**

- Aave V3 Ethereum mainnet では **Pool アドレスは全 reserve 共通**、**aToken は reserve ごとに異なる**。Day-1 mainnet で Strategy として登録する WETH / USDC の freeze 値と dry-run 手順は [Mainnet Deploy Env Freeze Runbook](../../../launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md) に集約する（[AAVE-TBD-007](#aave-tbd-007)）。その他の reserve は exact Underlying の activation package が承認されるまで登録しない。
- Aave V3 の `supply(asset, amount, onBehalfOf, referralCode)` は `onBehalfOf` を任意指定でき permissionless。
- Aave V3 の `withdraw` は流動性不足（utilization 100% 等）や残高超過の要求では **clamp せず revert** する。そのため `AaveV3Strategy._doWithdraw` は ERC-4626 の `maxWithdraw` と同じ役割として、要求額を `min(request, Aave accounting value, aToken liquid underlying)` に丸めてから呼び出す。
- Aave V3 は Sepolia に同型のテスト環境を提供し、mainnet と 1:1 でアドレス・I/F が対応する。

---

## 4. アクター・ロール・信頼境界

共通の権限設計（Owner / upgrader / ALLOCATOR / permissionless の操作別マトリクス・鍵侵害時の被害境界）は [Strategy 要件定義](./Strategy.md) を正本とする。Aave V3 固有の操作のみ以下に示す。

| アクター | Aave 固有の操作 | 信頼境界 |
| --- | --- | --- |
| **Owner（Guardian multisig）** | `initialize`（投資先固定・1 度のみ）/ `emergencyWithdrawFromAave`（Aave liquid reserve 分 → Vault 原子直送・returned principal 記帳）/ `claimAaveRewards`（Aave RewardsController 報酬の claim・settlement） | 緊急回収と protocol-specific reward claim の主体。必ずマルチシグ。緊急回収の宛先は Vault 固定で任意宛先なし（[AAVE-SEC-003](#aave-sec-003-緊急回収の宛先固定と権限分離)）。reward settlement は Underlying なら Vault buffer、非 Underlying なら Vault の現在 Treasury に固定される（[AAVE-FR-007](#aave-fr-007-claimaaverewardsaave-rewardscontroller-報酬claim)）。UUPS アップグレード承認は Owner から分離した `upgrader`（= 共通 TimelockController、[Strategy 要件定義](./Strategy.md) STGY-FR-009）が担う |
| **ALLOCATOR（Vault ロール）** | `sendToVault` / `sendProfitToVault`（内部で `_doWithdraw` = `aavePool.withdraw` を起動） | 資金は Vault へ push されるのみ・任意宛先不可。Aave への預入 `deposit`（→`_doDeposit`）は `onlyVault` で Vault 経由に限定 |
| **任意（permissionless）** | `estimatedTotalUnderlying` 等の view / Aave 側 `supply(onBehalfOf=this)` による donation | view は信頼不要。donation は AUM に混入させない（[AAVE-SEC-002](#aave-sec-002-第三者-donation-による-aum-水増しの排除)） |

- **権限分離**: `emergencyWithdrawFromAave` は `onlyOwner` であり、ALLOCATOR（運用 Bot 鍵）からは発動できない。逆に Owner は通常の回収（`sendToVault` 等）の常用主体ではない。UUPS upgrade は `upgrader`（= 共通 TimelockController）に分離され、Owner（Guardian multisig）は実装を差し替えられない。

---

## 5. インターフェース仕様

共通 surface は [Strategy 要件定義](./Strategy.md) を正本とし、Aave 固有の関数・hook だけを以下に要約する（非規範）。

| 関数 | 可視性 | 要約 | 規定要件 |
| --- | --- | --- | --- |
| `initialize(address _vault, IERC20 _underlying, address _owner, address _upgrader, IAaveV3Pool _aavePool, IAToken _aToken)` | external (initializer) | BaseStrategy 初期化＋投資先固定＋Pool へ max approve | AAVE-FR-001 |
| `_doDeposit(uint256 _amount)` | internal（`deposit` の hook） | `aavePool.supply(onBehalfOf=this)`・scaled 自己計上 | AAVE-FR-003 |
| `_doWithdraw(uint256 _amount) → uint256 actual` | internal（`sendToVault` / `sendProfitToVault` の hook） | `min(_amount, Aave会計値, aToken liquid underlying)` まで `aavePool.withdraw(to=this)`・scaled 自己減算 | AAVE-FR-004 |
| `_estimatedTotalUnderlying() → uint256` | internal view（`estimatedTotalUnderlying` の hook） | `mulDiv(min(_ownScaledBalance, aaveScaled), income, RAY)` | AAVE-FR-005 |
| `emergencyWithdrawFromAave() → uint256 sent` | external (onlyOwner) | Aave 保有（donation 含む）のうち liquid reserve 分を引き出し、idle 全額を同一 Tx で Vault へ push、Vault 実受領額を returned principal として記帳 | AAVE-FR-006 |
| `claimAaveRewards(IAaveRewardsController _rewardsController, uint256 _amount, address _reward) → (uint256 claimed, uint256 settled)` | external (onlyOwner) | Aave RewardsController から当 Strategy の aToken 報酬だけを claim。Underlying reward は Vault buffer へ yield 送付、非 Underlying reward は Treasury へ sweep | AAVE-FR-007 |

---

## 6. 機能要件（FR）

> `deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / `emergencyWithdraw`（送金先 Vault 固定）本体は `BaseStrategy` が提供する（[Strategy 要件定義](./Strategy.md)）。`AaveV3Strategy` は `initialize` と 3 hook（`_doDeposit` / `_doWithdraw` / `_estimatedTotalUnderlying`）＋固有の緊急回収関数＋ Aave RewardsController claim 関数を実装する。

### AAVE-FR-001: initialize（投資先固定・proxy 初期化）

- **Type**: Functional ｜ **Source**: [Strategy 要件定義](./Strategy.md) 派生クラスの `initialize` 規約 / Aave V3 supply
- **シグネチャ**: `initialize(address _vault, IERC20 _underlying, address _owner, address _upgrader, IAaveV3Pool _aavePool, IAToken _aToken) external initializer`
- **目的**: UUPS proxy 越しに 1 度だけ初期化し、`BaseStrategy` の標準初期化に加えて Aave V3 の投資先（`aavePool` / `aToken`）を固定し、Pool へ Underlying を max approve する。
- **権限**: デプロイ手順（proxy 初期化）の一部。`_owner` に Owner（Guardian multisig）、`_upgrader` に共通 TimelockController を束縛する（`BaseStrategy` が ownership と upgrader を設定）。
- **事前条件（Checks）**:
  - `initializer` により 1 度きり（多重初期化は revert）。ロジックコントラクト自体は初期化不能とし、初期化は proxy 経由に限定する
  - `_aavePool != address(0)`（ゼロなら `ZeroAddress` で revert）
  - `_aToken != address(0)`（ゼロなら `ZeroAddress` で revert）
  - `_aToken.UNDERLYING_ASSET_ADDRESS() == address(_underlying)`（不一致なら `InvalidATokenUnderlying` で revert）
  - `_vault` / `_underlying` / `_owner` / `_upgrader` のゼロチェックは `BaseStrategy` の標準初期化が行う
- **動作（Effects）**:
  1. `__BaseStrategy_init(_vault, _underlying, _owner, _upgrader)` — `BaseStrategy` の標準初期化。OZ Ownable / UUPS 初期化・ストレージ保存・ownership 移譲・upgrader 保存に加え、**Vault への `underlying.forceApprove(vault, type(uint256).max)` を含む**（`receiveFromStrategy` が `safeTransferFrom` で Strategy から Underlying を引き取れるようにする。詳細は [Strategy 要件定義](./Strategy.md) の `BaseStrategy`）
  2. aToken / Underlying 整合性検証（`UNDERLYING_ASSET_ADDRESS()`）
  3. `aavePool = _aavePool`（以後変更不可）
  4. `aToken = _aToken`（以後変更不可）
  5. `_underlying.forceApprove(address(_aavePool), type(uint256).max)` — Aave V3 Pool への max approve（initialize 時 1 回のみ。deposit 都度 approve のガス浪費を回避）
- **revert / 早期 return**: 多重初期化 → revert；`_aavePool == 0` / `_aToken == 0` → `ZeroAddress`；aToken の underlying 不一致 → `InvalidATokenUnderlying`。
- **発火イベント**: なし（`BaseStrategy` の初期化イベントに従う。投資先確定の専用イベントは設けない）。
- **設計上のポイント**:
  - **投資先と初期権限を `initialize` で確定**: 後から `setAavePool` / `setAToken` を生やすと「投資先を Strategy 側で動かせる」攻撃面ができるため、Aave Pool / aToken / Underlying / Vault は `initialize` で固定する（[AAVE-SEC-001](#aave-sec-001-投資先アドレスの-initialize-時固定)）。Owner / Upgrader は BaseStrategy の共通手順で初期設定し、その後の変更は共通の ownership / `setUpgrader` 経路に従う。投資先を変えたい場合は Strategy ごと作り直す（[AAVE-GOV-001](#aave-gov-001-投資先差し替えは-strategy-再作成)）。
  - **`forceApprove(max)` の信頼前提**: Aave V3 Pool が侵害されると Strategy の一時残高を引き抜かれうるが、per-deposit approve でも「Pool が侵害されない」という信頼前提は変わらない。現方針で問題ないかは [AAVE-TBD-001](#aave-tbd-001) で確認。
  - **aToken 整合性チェック**: `initialize` で `aToken.UNDERLYING_ASSET_ADDRESS() == address(_underlying)` を検証し、誤った reserve の aToken を束縛した Strategy が運用に入ることを防ぐ。デプロイスクリプト側でも同じ値を assert し、アドレス表の取り違えを二重に防ぐ。
- **Verification**: unit（多重初期化 revert・`ZeroAddress` 各 revert・aToken underlying mismatch revert・Pool への max approve 成立・投資先固定）。

### AAVE-FR-002: addStrategy 前提（Vault への登録契約）

- **Type**: Functional ｜ **Source**: [Strategy 要件定義](./Strategy.md) `underlying()` 契約 / [CollateralVault 要件定義](../CollateralVault.md) `addStrategy`
- **シグネチャ**: `underlying() → address`（`BaseStrategy` 提供）
- **目的**: デプロイ後、対応 CollateralVault が当 Strategy を運用に投入する前提を満たす。`underlying()` が当 Strategy の Underlying を返し、Vault の `addStrategy` がこれを on-chain 検証する。
- **権限**: なし（`underlying()` は view）。登録操作（whitelist / `addStrategy`）は GOV_MULTISIG（[CollateralVault 要件定義](../CollateralVault.md)）。
- **事前条件（Checks）**: 当 Strategy が対応 CollateralVault のホワイトリストに登録（`addToWhitelist`）済みであること。
- **動作（Effects）**:
  1. GOV が対応 CollateralVault で `addToWhitelist(strategy)`
  2. GOV が `addStrategy(strategy, weightBps, cap)` で実運用に投入。Vault は `strategy.underlying() == vault.underlying()` を on-chain 検証する（[CollateralVault 要件定義](../CollateralVault.md)）
- **revert / 早期 return**: `strategy.underlying()` が Vault の Underlying と不一致 → Vault 側 revert。
- **発火イベント**: Vault 側のイベントに従う（本 Strategy 固有イベントなし）。
- **設計上のポイント**: 当 Strategy は **AaveV3Strategy を適用する担保**（Aave V3 に reserve があるもの）に限り登録され、全ブランチではなくその部分集合に適用される。
- **Verification**: integration（whitelist 後 `addStrategy` 成立・Underlying 不一致 revert）, manual（デプロイ手順）。

### AAVE-FR-003: _doDeposit（Aave V3 への supply）

- **Type**: Functional ｜ **Source**: [Strategy 要件定義](./Strategy.md) `_doDeposit` hook / Aave V3 supply
- **シグネチャ**: `_doDeposit(uint256 _amount)`（internal・`deposit` の hook）
- **目的**: `BaseStrategy.deposit` が受領済みの Underlying を Aave V3 Pool へ供給し、その供給で増えた scaled balance のみを `_ownScaledBalance` に自己計上する。
- **権限**: 内部 hook。呼出元 `deposit` が `onlyVault`（[Strategy 要件定義](./Strategy.md)）。Vault は `deposit` を呼ぶ直前に `safeTransfer(strategy, _amount)` で Underlying を送付済みのため、Strategy 側で `safeTransferFrom` は不要。
- **事前条件（Checks）**: Underlying は呼び出し前に Vault → Strategy へ渡っている（push モデルの預入）。Aave reserve が `frozen` / `paused` でないこと（満たさなければ supply が revert）。
- **動作（Effects）**:
  1. `scaledBefore = aToken.scaledBalanceOf(address(this))`
  2. `aavePool.supply(asset = address(underlyingToken), amount = _amount, onBehalfOf = address(this), referralCode = 0)` — aToken の credit 先 = この Strategy 自身
  3. `scaledAfter = aToken.scaledBalanceOf(address(this))`
  4. `scaledMinted = scaledAfter - scaledBefore`
  5. `scaledMinted == 0` なら `AaveSupplyZeroScaledBalance(_amount)` で revert
  6. `_ownScaledBalance += scaledMinted`
  7. `OwnScaledBalanceUpdated(_ownScaledBalance)` を発火
- **revert / 早期 return**: Aave reserve が `frozen` / `paused` / supply cap 到達等で supply 不可、または scaled balance 差分が 0 → inner `_doDeposit` frame が revert。`BaseStrategy.deposit` がその frame を巻き戻して Underlying を Vault へ完全回収できれば当該 allocation を skip し、回収不一致なら `DepositRecoveryFailed` で `allocate` 全体を revert する。元本だけが増える dust / zombie 状態は作らない。
- **発火イベント**: `OwnScaledBalanceUpdated(_ownScaledBalance)`（AAVE-EVT-001）。`principal += _amount` と `Deposited(_amount, newPrincipal)` の発火は `BaseStrategy.deposit` が担う（[Strategy 要件定義](./Strategy.md)）。
- **設計上のポイント**:
  - **`onBehalfOf = address(this)`**: aToken の所有権を Strategy 自身が持つことで、後の引き出し時に Strategy 単独で全量回収できる。Vault に直接 credit すると Vault に Aave 知識が漏れて責務分離が壊れる。
  - **scaled balance の自己計上**: この `supply` で Aave が mint した scaled 分（before/after の差分）のみを `_ownScaledBalance` に加算する。差分 0 は Strategy 側では会計不能な極小 supply として fail-closed にする。並行 Tx での第三者 donation は before/after を等しく押し上げるため、差分には混入しない（[AAVE-SEC-002](#aave-sec-002-第三者-donation-による-aum-水増しの排除)）。
  - **`referralCode`**: 現状 `0` ハードコード＋TODO コメント。Aave のリファラル制度活用は [AAVE-TBD-002](#aave-tbd-002)。
- **Verification**: unit（scaled 差分計上・zero-scaled supply revert・`onBehalfOf=this`）, fork（実 Aave V3 への supply・frozen/paused 時 revert）, invariant=AAVE-INV-001。

### AAVE-FR-004: _doWithdraw（Aave V3 からの引き出し）

- **Type**: Functional ｜ **Source**: [Strategy 要件定義](./Strategy.md) `_doWithdraw` hook / Aave V3 withdraw
- **シグネチャ**: `_doWithdraw(uint256 _amount) → uint256 actual`（internal・`sendToVault` / `sendProfitToVault` の hook）
- **目的**: 通常の元本/収益回収用に、Aave V3 Pool から指定額を **Strategy 自身**へ引き出し（その後 `BaseStrategy` が元本返却は `receiveFromStrategy`、収益のみは Vault buffer への direct transfer として push する）、burn された scaled 分を `_ownScaledBalance` から減算し、実回収額 `actual` を返す。
- **権限**: 内部 hook。呼出元 `sendToVault` / `sendProfitToVault` が Vault の `ALLOCATOR_ROLE` を参照（[Strategy 要件定義](./Strategy.md)）。
- **事前条件（Checks）**: Aave reserve が引き出し可能な状態（`paused` でない）であること。reserve 流動性不足は Strategy 側の liquid cap で部分回収または 0 回収に丸める。
- **動作（Effects）**:
  1. `withdrawAmount = min(_amount, _ownedAaveAccountingValue(), underlying.balanceOf(aToken))`
  2. `if withdrawAmount == 0: return 0`
  3. `scaledBefore = aToken.scaledBalanceOf(address(this))`
  4. `aavePool.withdraw(asset = address(underlyingToken), amount = withdrawAmount, to = address(this))` — Strategy 自身へ引き出す（Vault が後で pull する）
  5. `scaledAfter = aToken.scaledBalanceOf(address(this))`
  6. `burned = scaledBefore - scaledAfter`
  7. `actual = underlying.balanceOf(this) の before/after 差分`
  8. `actual != 0 && burned == 0` なら `AaveWithdrawZeroScaledBurn(actual)` で revert
  9. `_ownScaledBalance = burned > _ownScaledBalance ? 0 : _ownScaledBalance - burned`（0 下限でクランプ）
  10. `OwnScaledBalanceUpdated(_ownScaledBalance)` を発火し `actual` を返す
- **revert / 早期 return**: `withdrawAmount == 0` → `0` を返す。Aave reserve が `paused` 等で `withdraw` 自体を拒否する場合は revert が伝播する。Strategy の実 Underlying 残高が増えたのに scaled burn が 0 → `AaveWithdrawZeroScaledBurn(actual)`、Aave の返り値が `0` なのに Strategy の実 Underlying 残高が増えた場合 → `AaveWithdrawZeroReported(actual)` で revert する。
- **発火イベント**: `OwnScaledBalanceUpdated(_ownScaledBalance)`（AAVE-EVT-001）。Vault への push と `principal` 減算・`SentToVault` / `ProfitSentToVault` の発火は `BaseStrategy` が担う（[Strategy 要件定義](./Strategy.md)）。
- **設計上のポイント**:
  - **`to = address(this)`**: push モデルでは Aave から **Strategy 自身**へ引き出す。その後 `BaseStrategy` が、元本返却では `vault.receiveFromStrategy(actual)` を呼んで Vault が `safeTransferFrom` で buffer へ引き取り、収益のみでは Strategy が Vault buffer へ直接 `safeTransfer` する。引き出し先を Vault に直送せず Strategy 自身に統一することで、元本返却と yield-only push の分離を BaseStrategy に閉じる。
  - **部分回収を Strategy 側で実現**: Aave V3 は流動性不足や残高超過の要求では clamp せず revert するため、Aave 呼び出し前に要求額を Aave 会計値と aToken の liquid underlying で cap する。これにより utilization 逼迫は solvency loss として扱わず、回収可能分だけ Vault に戻す。
  - **scaled balance の減算**: Aave が burn した scaled 分を `_ownScaledBalance` から引く（0 下限でクランプ）。実 Underlying を受け取ったのに burn 差分が 0 の場合は、元本だけ減って position が残る会計 drift を避けるため fail-closed にする。
- **Verification**: unit（scaled 減算・0 下限クランプ・zero-scaled burn revert・`to=this`・liquid reserve cap）, fork（実 Aave V3 からの引き出し・流動性不足時の cap）, invariant=AAVE-INV-001。

### AAVE-FR-005: _estimatedTotalUnderlying（評価額の算出）

- **Type**: Functional ｜ **Source**: [Strategy 要件定義](./Strategy.md) `_estimatedTotalUnderlying` hook（保守的評価前提）
- **シグネチャ**: `_estimatedTotalUnderlying() → uint256`（internal view・`estimatedTotalUnderlying` の hook）
- **目的**: 当 Strategy が Aave V3 で運用中の Underlying の評価額を、第三者 donation を排除しつつ Aave の会計値（scaled balance / normalized income）から返す。`BaseStrategy` の `estimatedTotalUnderlying` / `realizedYield` の基礎となる。Aave 会計に現れない実質損失は自動検知できず、GOV の回収・writeoff 運用で補正する。
- **権限**: なし（internal view）。
- **事前条件（Checks）**: なし（view）。`effective == 0` の早期 return を持つ。
- **動作（Effects）**:
  1. `aaveScaled = aToken.scaledBalanceOf(address(this))`
  2. `effective = min(_ownScaledBalance, aaveScaled)` — donation を排除しつつ、Aave 会計上の残高低下を反映
  3. `if effective == 0: return 0`
  4. `income = aavePool.getReserveNormalizedIncome(address(underlyingToken))` — RAY（1e27）
  5. `return Math.mulDiv(effective, income, RAY)`（RAY 換算の乗算 overflow を避ける）
- **revert / 早期 return**: `effective == 0` → `0` を返す。
- **発火イベント**: なし（view）。
- **設計上のポイント**:
  - **donation 耐性**: `aToken.balanceOf(this)` をそのまま AUM にすると第三者の donation が `realizedYield` を水増しし収益送付経由で Treasury に任意額を流し込めてしまうため、当 Strategy 自身の supply / withdraw で増減した `_ownScaledBalance`（[AAVE-FR-003](#aave-fr-003-_dodepositaave-v3-への-supply) / [AAVE-FR-004](#aave-fr-004-_dowithdrawaave-v3-からの引き出し)）を基礎とし、`getReserveNormalizedIncome`（RAY）で利息込み Underlying 換算する（[AAVE-SEC-002](#aave-sec-002-第三者-donation-による-aum-水増しの排除)）。
  - **`min(_ownScaledBalance, aaveScaled)` の意味**: Aave 側の scaled 残高を上限とすることで、Aave 会計上の残高低下は AUM へ反映しつつ、第三者 donation（`aaveScaled` のみを押し上げる）は AUM に含めない。「Aave が言う以上は主張しないが、第三者の寄付は含めない」評価。
  - **乖離可能性**: Aave V3 の `scaledBalanceOf` / `getReserveNormalizedIncome` が実質回収可能額を常に証明するわけではない。reserve 異常時（frozen / paused / utilization 100% / 大規模バッドデット）に、会計上の claim は残るが実回収できないケースでは `estimatedTotalUnderlying()` が過大になり得る。この場合は GUARDIAN が `emergencyDisableStrategy` で新規割当を止め、GOV が必要なら `cap = 0` 等の恒久設定を行い、回収できた額を Vault へ戻し、残額を `writeoffStrategyPrincipal` で明示的に backing へ下方反映する。さらなる保守的補正を入れるかは [AAVE-TBD-003](#aave-tbd-003)。
- **Verification**: unit（`min` 選択・`effective==0` で 0・RAY 換算）, fork（実 `getReserveNormalizedIncome` での評価）, invariant=AAVE-INV-002。

### AAVE-FR-006: emergencyWithdrawFromAave（緊急回収）

- **Type**: Functional ｜ **Source**: [Strategy 要件定義](./Strategy.md) 固有の緊急回収関数（`emergency*From{Protocol}()`）/ 2026-06-12 ガバナンス設計確定（旧 2 段構成を原子直送へ統合。[Governance-Roles-Timelock.md](../../policies/Governance-Roles-Timelock.md)）
- **シグネチャ**: `emergencyWithdrawFromAave() external onlyOwner returns (uint256 sent)`（`sent` = Vault へ実 push した Underlying 額）
- **目的**: Aave V3 が緊急停止される / 当該 reserve が frozen 化される / 重大な脆弱性が報告される等の状況で、Owner（Guardian multisig）が **Aave に預けてある残高（第三者 donation 含む）のうち liquid reserve 分を引き出し、Strategy idle 分を含む Underlying 全額を同一 Tx で Vault へ原子的に push する**緊急用関数。通常運用ではない。
- **権限**: `onlyOwner`（Guardian multisig）。運用ロール（ALLOCATOR）とは分離（[AAVE-SEC-003](#aave-sec-003-緊急回収の宛先固定と権限分離)）。
- **事前条件（Checks）**: `caller == Owner`。Aave 残高も Strategy idle Underlying も 0 のときは `0` を返して早期終了する。push が発生する場合、**当 Strategy が Vault に登録済み（`strategies[]` 残存）であること**——push 先の `receiveFromStrategy` は登録 Strategy のみ受け入れるため、`removeStrategy` 済みでは本関数全体が revert する（`emergencyDisableStrategy` による無効化は登録に残るため実行可）。
- **動作（Effects）**:
  1. `aTokenBalance = aToken.balanceOf(address(this))` — donation 含む Aave 会計値
  2. `liquidUnderlying = underlying.balanceOf(address(aToken))`
  3. `withdrawAmount = min(aTokenBalance, liquidUnderlying)` — Aave は普通の `withdraw` を部分約定しないため、Strategy 側で liquid reserve 分に丸める
  4. `withdrawAmount != 0` なら `aavePool.withdraw(asset = address(underlyingToken), amount = withdrawAmount, to = address(this))` で Strategy 自身へ引き出し、burn された scaled balance 分だけ `_ownScaledBalance` を減算して `OwnScaledBalanceUpdated` を発火する
  5. `idle = underlyingToken.balanceOf(address(this))` — drain 分＋既存 idle（事故的滞留・donation）の合算
  6. `if idle == 0: return 0` — 送る Underlying が無ければ何もせず終了
  7. `sent = ICollateralVault(vault).receiveFromStrategy(idle)` — idle 全額を**同一 Tx で Vault buffer へ push**（Vault 側は実着額計上・valuation cache を実着額分だけ減額。[CollateralVault 要件定義](../CollateralVault.md) VAULT-FR-005）
  8. `sent` を `BaseStrategy._accountReturnedPrincipal` で returned principal として記帳し、`principal -= min(sent, principal)` とする
  9. `EmergencyWithdrawn(sent)` を発火し `sent` を返す
- **revert / 早期 return**: `caller != Owner` → revert；Aave drain 後に `idle == 0` → `0` を返して何もせず正常終了；実 Underlying を受け取ったのに scaled burn が 0 → `AaveWithdrawZeroScaledBurn(actual)`；Aave 側が完全停止していて withdraw 自体が revert する場合は**関数全体が revert（fail-closed・状態変化なし）**＝宙吊りも過小評価も発生しない（[AAVE-ERR-003](#aave-err-003-aave-完全停止時の緊急回収不能)）。
- **発火イベント**: `OwnScaledBalanceUpdated(ownScaledBalance)`（AAVE-EVT-001・Aave burn 後）／ Strategy 共通 `PrincipalReturned(returned, newPrincipal)`・`EmergencyWithdrawn(sent)`（[Strategy 要件定義](./Strategy.md)・Vault への実 push 額）／ Vault 側 `ReceivedFromStrategy(strategy, declared, received)`。Aave drain 額専用イベント（`EmergencyAaveWithdrawn` 等）を追加すべきかは [AAVE-TBD-004](#aave-tbd-004)（AAVE-EVT-002）。
- **設計上のポイント**:
  - **liquid reserve cap**: Aave V3 の ordinary `withdraw` は流動性不足時に部分約定しない。緊急回収でも `aToken.balanceOf(this)` と `underlying.balanceOf(aToken)` の小さい方までに丸め、回収可能分だけ Vault に戻す。
  - **原子直送の理由（旧 2 段構成の廃止）**: 旧設計（Aave → Strategy idle → 手動 `emergencyWithdraw` → Vault）では、引き出しから push までの間、資金が `_estimatedTotalUnderlying`（idle 非算入）にも Vault buffer にも算入されない**宙吊り**となり、`totalUnderlying` / `backingRatio` が引き出し全額分だけ過小評価 → オラクル markdown → 当該ブランチ全 Trove の不当 mass 清算（permissionless・自動 MEV・不可逆）を誘発しうる。マルチシグの一括実行（multiSend）での連続実行は運用規律依存で、緊急時の非原子実行・部分 push・push 失敗で実害化するため、コードで原子化する。
  - **returned principal 記帳**: Vault が実受領した `sent` は returned principal として `principal` から減算する。これにより、部分回収後に残額が損失確定した場合、GOV は残 `principal` を `Vault.writeoffStrategyPrincipal` で下方確定すれば backing が二重計上されない（[CollateralVault 要件定義](../CollateralVault.md) VAULT-FR-009）。
  - **donation の回収**: 第三者 donation 分は通常 AUM に含めないが（[AAVE-FR-005](#aave-fr-005-_estimatedtotalunderlying評価額の算出)）、本関数は donation を含む Aave 残高から liquid reserve 分を Vault buffer へ入れ backing に算入させる（保有者へ帰属＝健全側）。
  - **`BaseStrategy.emergencyWithdraw` との関係**: `emergencyWithdraw(uint256 _amount)` は Strategy が直接保有する idle Underlying（donation・事故的滞留分）を Vault へ送る関数として**併存**する（削除しない。[Strategy 要件定義](./Strategy.md) STGY-FR-005）。
  - **登録前提と復旧経路**: 原子直送は Vault 側 `receiveFromStrategy` の登録ガードを前提とする。`removeStrategy` 後に Aave 側残余（donation 等）が見つかった場合は、再 whitelist → `addStrategy`（GOV=Timelock）で再登録してから本関数で回収する（fail-closed: 未登録の間、資金は Aave に留まり誤った宛先へは流れない）。
- **Verification**: unit（`onlyOwner` 限定・Aave/idle 残高 0 早期 return・idle-only push・liquid reserve cap・returned principal 記帳・`sent` 返却・**同一 Tx での Vault 着金・Aave withdraw revert 時の全体 revert**）, fork（実 Aave からの liquid recovery → Vault 着金）, integration（経路を通じて `backingRatio` が低下しないこと）。

### AAVE-FR-007: claimAaveRewards（Aave RewardsController 報酬 claim）

- **Type**: Functional ｜ **Source**: Aave V3 `RewardsController.claimRewards` / [Strategy 要件定義](./Strategy.md) reward settlement 方針
- **シグネチャ**: `claimAaveRewards(IAaveRewardsController _rewardsController, uint256 _amount, address _reward) external onlyOwner returns (uint256 claimed, uint256 settled)`
- **目的**: 当 Strategy の `aToken` position に発生した Aave V3 rewards を Owner が明示的に claim し、reward の性質に応じて Vault buffer または Treasury へ固定宛先で settlement する。未 claim reward は AUM / principal / realizedYield に含めない。
- **権限**: `onlyOwner`（Guardian multisig）。ALLOCATOR や任意 caller は protocol-specific reward claim を起動できない。
- **事前条件（Checks）**:
  - `_rewardsController != address(0)`（ゼロなら `ZeroAddress`）
  - `_rewardsController.code.length != 0`（EOA / 未デプロイなら `InvalidAaveRewardsController`）
  - `_reward != address(0)`（ゼロなら `ZeroAddress`）
  - `_reward != address(underlyingToken)` かつ `_isSweepProtectedToken(_reward)` なら `CannotSweepProtectedToken`。aToken / dToken 等の position token を reward として Treasury へ動かさない
- **動作（Effects）**:
  1. `assets = [address(aToken)]` を作る。claim 対象 asset は当 Strategy の aToken に固定し、任意の Aave position を claim する汎用 adapter にしない
  2. `_reward` の Strategy 残高を claim 前に記録する
  3. `_rewardsController.claimRewards(assets, _amount, address(this), _reward)` を呼び、戻り値を `claimed` として返す
  4. `_reward == underlying` の場合は claim 前後の実残高差分だけを `_sendUnderlyingToVault` で Vault buffer へ送る。`principal` は減らさず、Vault 実着額を `settled` として返す
  5. `_reward != underlying` の場合は `BaseStrategy._sweepRewardToken(_reward, type(uint256).max)` で Vault の現在 Treasury へ sweep し、実着額を `settled` として返す
- **revert / 早期 return**: 権限違反 → revert；controller / reward 不正 → 上記 custom error；protected token → `CannotSweepProtectedToken`；Aave 側 `claimRewards` revert は伝播。claim 実着が 0 の場合、Underlying branch は `settled == 0` で正常終了し、非 Underlying branch は `_sweepRewardToken` が 0 return する。
- **発火イベント**: Underlying reward は `AaveUnderlyingRewardsClaimed(rewardsController, reward, requested, claimed, sentToVault)`（AAVE-EVT-004）。非 Underlying reward は `RewardTokenSwept(token, treasury, requested, received)`（BaseStrategy 共通）＋ `AaveRewardsClaimed(rewardsController, reward, requested, claimed, settled)`（AAVE-EVT-003）。
- **設計上のポイント**:
  - **AUM に入れない**: Aave reward は aToken の normalized income とは別資産であり、claim 前も claim 後も `_estimatedTotalUnderlying()` の入力ではない。Underlying reward だけは Vault buffer へ実送付して backing に入れるが、`principal` は減らさない。
  - **swap しない**: 非 Underlying reward を Underlying に換金して backing 補填する swap 経路は本関数に含めない。reward token は Treasury へ集約し、換金・buyback・backstop 入金は Treasury / 運用 runbook の責務とする（[AAVE-TBD-005](#aave-tbd-005)）。
  - **position token 保護**: aToken は Aave position / accounting token であり、reward として扱わない。`_isSweepProtectedToken` により aToken / dToken / Underlying 等の移動を拒否する（Underlying reward branch は Vault buffer 宛のみ許可）。
- **Verification**: unit（onlyOwner・controller/reward ゼロ・controller code 検査・assets=aToken 固定・Underlying reward は Vault buffer へ実着額送付・非 Underlying reward は Treasury sweep・aToken/dToken reward 拒否・0 claim return）, fork（実 Aave RewardsController claim 可能 reserve での claim / no-reward 0 return）。

---

## 7. 状態変数・会計モデル

`BaseStrategy` が持つ共通ストレージ（`vault` / `underlyingToken` / `_principal`）に加え、`AaveV3Strategy` 固有のストレージは以下。`aavePool` / `aToken` は `initialize` で固定し以後変更不可。`_ownScaledBalance` は supply / withdraw に連動して更新される。

| 変数 | 型 | 役割 | 確定 |
| --- | --- | --- | --- |
| `aavePool` | `IAaveV3Pool` | Aave V3 Pool。`supply` / `withdraw` / `getReserveNormalizedIncome` の呼び出し先 | `initialize` で固定・不変 |
| `aToken` | `IAToken` | 当該 Underlying に対応する aToken。`scaledBalanceOf(this)` / `balanceOf(this)` を参照 | `initialize` で固定・不変 |
| `_ownScaledBalance` | `uint256` | **この Strategy 自身の** supply / withdraw で増減した scaled balance（RAY 精度）。第三者が `supply(onBehalfOf=this)` で寄付しても増えない。AUM 評価の基礎（[AAVE-FR-005](#aave-fr-005-_estimatedtotalunderlying評価額の算出)） | `_doDeposit` で加算 / `_doWithdraw`・`emergencyWithdrawFromAave` で burn 分だけ減算 |

**会計モデル**: 投下元本 `principal` の自己管理・`realizedYield = max(estimatedTotalUnderlying − principal, 0)` などの会計は `BaseStrategy` に属する（[Strategy 要件定義](./Strategy.md)）。`AaveV3Strategy` は Aave 側ポジションの評価（`_estimatedTotalUnderlying`）を担い、その基礎を `_ownScaledBalance`（自己 supply/withdraw 由来の scaled 残高）に置く。

- **`_ownScaledBalance` を自前管理する理由**: Aave V3 の `supply(onBehalfOf=任意)` は permissionless で誰でも当 Strategy の aToken を増やせるため、`aToken.balanceOf` をそのまま AUM にすると **第三者の donation が `realizedYield` を水増しし、`sendProfitToVault` ＋ Vault の収益→Treasury 経路で Treasury に任意の額を流し込めてしまう**（[AAVE-SEC-002](#aave-sec-002-第三者-donation-による-aum-水増しの排除)）。これを防ぐため自己管理の scaled 残高を AUM 評価の基礎とする。
- **`aavePool` / `aToken` に setter を生やさない理由**: 後から投資先を Strategy 側で動かせると攻撃面になるため、`initialize` で固定し storage migration リスクと攻撃面を排除する（投資先変更は Strategy 再作成。[AAVE-SEC-001](#aave-sec-001-投資先アドレスの-initialize-時固定) / [AAVE-GOV-001](#aave-gov-001-投資先差し替えは-strategy-再作成)）。
- **評価の保守性と限界**: `_estimatedTotalUnderlying = mulDiv(min(_ownScaledBalance, aaveScaled), income, RAY)`。Aave 会計上の scaled 残高低下は `aaveScaled` の縮小として反映し、donation は `_ownScaledBalance` 側の上限により排除する。一方、Aave の reserve deficit / bad debt / collateral depeg / utilization 逼迫のうち、scaled balance または normalized income に現れないものはこの view だけでは検知できない。流動性不足は `_doWithdraw` / `emergencyWithdrawFromAave` の liquid cap で partial recovery し、回収額は returned principal として記帳する。実質損失の下方反映は監視・GOV 判断・Vault 側 `writeoffStrategyPrincipal` で行う。
- **報酬トークンの会計境界**: Aave incentives / Merkl 等の非 Underlying reward token は `_ownScaledBalance` と `estimatedTotalUnderlying()` に入れない。着金済み reward は `BaseStrategy.sweepRewardToken`、Merkl の標準 distributor 報酬は `BaseStrategy.claimMerklRewards`、Aave `RewardsController` 報酬は `claimAaveRewards` で settlement する。Underlying reward は Vault buffer へ yield として直送し、非 Underlying reward は Treasury に送る。swap / backing 補填のための換金は別途明示的に設計する。aToken は Strategy の Aave 請求権そのものなので protected token とし、reward sweep / Merkl claim / Aave claim settlement では Treasury へ移動できない。

---

## 8. 不変条件（INV）

| ID | 不変条件 | 検証 |
| --- | --- | --- |
| AAVE-INV-001 | `_ownScaledBalance` は当 Strategy 自身の `_doDeposit`（before/after 差分加算）/ `_doWithdraw`・`emergencyWithdrawFromAave`（burn 分減算・0 下限クランプ）でのみ増減し、第三者 donation では増えない | invariant |
| AAVE-INV-002 | `_estimatedTotalUnderlying()` は `mulDiv(min(_ownScaledBalance, aToken.scaledBalanceOf(this)), getReserveNormalizedIncome, RAY)`。第三者 donation は AUM に含めず、Aave 会計上の scaled 残高低下は反映する。Aave 会計に現れない reserve deficit / 実質損失は GOV writeoff 運用で補正する。`effective == 0` のとき 0 | invariant / fork |
| AAVE-INV-003 | `aavePool` / `aToken` は `initialize` 後不変（setter を持たない） | invariant |
| AAVE-INV-004 | `_doDeposit` の `supply` は `onBehalfOf == address(this)`、通常 `_doWithdraw` と `emergencyWithdrawFromAave` の Aave `withdraw` は `to == address(this)`。緊急回収はその同一 Tx 内で `receiveFromStrategy` により Vault へ push し、任意宛先を持たない | unit |
| AAVE-INV-005 | `sweepRewardToken(aToken, ...)` は `CannotSweepProtectedToken` で revert し、Aave position token を Treasury へ移動できない。通常 reward token の sweep は引き続き可能 | unit |

---

## 9. セキュリティ要件（SEC）

### AAVE-SEC-001: 投資先アドレスの initialize 時固定

- Type: Security
- Statement: `aavePool` / `aToken` および Pool への approve は `initialize` で固定し、`setAavePool` / `setAToken` 等の事後変更 setter を一切持ってはならない（「投資先を Strategy 側で動かせる」攻撃面と storage migration リスクの排除）。投資先を変えたい場合は Strategy ごと作り直し Vault 登録を入れ替える（[AAVE-GOV-001](#aave-gov-001-投資先差し替えは-strategy-再作成)）。
- Verification: invariant=AAVE-INV-003, manual（setter 不在のコードレビュー）

### AAVE-SEC-002: 第三者 donation による AUM 水増しの排除

- Type: Security
- Statement: Aave V3 の `supply(asset, amount, onBehalfOf=任意, _)` は permissionless で誰でも当 Strategy の aToken を増やせる。`aToken.balanceOf` をそのまま AUM にすると第三者 donation が `realizedYield()` を水増しし、`sendProfitToVault` ＋ Vault の収益→Treasury 経路で **任意額を Treasury に流し込める**攻撃が成立する。これを防ぐため、`_estimatedTotalUnderlying()` は `balanceOf` ではなく当 Strategy 自身の supply / withdraw で増減した `_ownScaledBalance`（[AAVE-FR-003](#aave-fr-003-_dodepositaave-v3-への-supply) / [AAVE-FR-004](#aave-fr-004-_dowithdrawaave-v3-からの引き出し)）に基づいて算出しなければならない。`min(_ownScaledBalance, aToken.scaledBalanceOf)` により Aave 会計上の残高低下は反映しつつ donation は排除する。donation 分は緊急時に `emergencyWithdrawFromAave` で liquid reserve の範囲まで回収する。
- Verification: invariant=AAVE-INV-001/002, fork（donation を注入しても `realizedYield` が増えないこと）

### AAVE-SEC-003: 緊急回収の宛先固定と権限分離

- Type: Security
- Statement: `emergencyWithdrawFromAave` は `onlyOwner` とし運用ロール（ALLOCATOR）から発動できてはならない（運用 Bot 鍵が侵害されても緊急回収を勝手に発動できない）。Aave からの引き出しと Vault への push（`receiveFromStrategy`）は**同一 Tx で原子的に**行い、引き出した Underlying を Strategy に滞留させてはならない（評価非算入の宙吊りによる backing 過小評価の防止）。宛先は Vault 固定で任意宛先を持たず、Owner 鍵が侵害されても任意アドレスには資金を抜けない（Vault に戻してからガバナンスで再配分）。
- Verification: unit（ALLOCATOR からの呼び出し revert・同一 Tx での Vault 着金・宛先固定）, manual（緊急回収 runbook レビュー）

### AAVE-SEC-004: Aave Pool / aToken アドレス誤設定の防止

- Type: Security
- Statement: `initialize` 時に Aave V3 Pool または aToken のアドレスを誤って渡すと、Strategy が無関係の reserve に対して supply / withdraw を試み、資金喪失や評価誤算を起こす。特に `aToken` が Underlying と一致していないと AUM が他資産で評価される致命的バグになる。`initialize` は `aToken.UNDERLYING_ASSET_ADDRESS() == address(_underlying)` を on-chain 検証し、不一致は `InvalidATokenUnderlying` で fail-closed しなければならない。デプロイスクリプトでも同じ assert を行い、Pool / aToken の正式アドレス表との照合を必須化する。
- Verification: unit（誤設定 revert）, manual（デプロイスクリプトの assert 手順）

### AAVE-SEC-005: aToken の reward sweep 禁止

- Type: Security
- Statement: aToken は Aave position / accounting token であり、Aave incentives / Merkl 等の reward token ではない。`sweepRewardToken` で aToken を Treasury へ移動できると、Aave withdraw 経路・`_ownScaledBalance`・Vault の backing 会計を迂回するため、`AaveV3Strategy` は `BaseStrategy._isSweepProtectedToken` を override して `aToken` を protected token に含めなければならない。
- Verification: unit（`sweepRewardToken(aToken)` revert・通常 reward token sweep は成功）

> **reentrancy / CEI**: push 経路の権限・会計防御は `BaseStrategy` / CollateralVault の責務であり（[Strategy 要件定義](./Strategy.md) / [CollateralVault 要件定義](../CollateralVault.md)）、本書はそれを再仕様化しない。`AaveV3Strategy` の hook は外部呼び出し（`aavePool.supply` / `withdraw`）の前後で scaled balance 差分を計上するため、scaled の計上は外部呼び出し結果（before/after 実測）に基づく。

---

## 10. ガバナンス・運用・アップグレード要件（GOV）

共通の権限・アップグレード方針（UUPS `_authorizeUpgrade` = `upgrader` 限定・`transferOwnership` / `renounceOwnership` 無効化・マルチシグ＋将来のタイムロック）は [Strategy 要件定義](./Strategy.md) を正本とする。Aave V3 固有の運用要件のみ以下。

### AAVE-GOV-001: 投資先差し替えは Strategy 再作成

- Statement: Underlying や Aave market（Pool / aToken）を後から差し替えたい場合は、`setAavePool` / `setAToken` や `PoolAddressesProvider.getPool()` の動的追従で既存 position の接続先を動かすのではなく、**Strategy ごと作り直して**対応 CollateralVault のホワイトリスト＆登録（`addStrategy`）を入れ替える運用とする（[AAVE-SEC-001](#aave-sec-001-投資先アドレスの-initialize-時固定)）。
- **同一 market の implementation upgrade**: Aave の通常の `PoolAddressesProvider.setPoolImpl` は既存 Pool proxy の implementation を更新する。Pool proxy と reserve の aToken proxy が同じである限り、既存 Strategy の `aavePool` / `aToken` を変更しない。deploy / activation evidence では provider の `getPool()` が固定済み Pool と一致することを確認する。
- **別 market / hard replacement への移行**: 新しい Aave market は provider、Pool、reserve aToken を別組として扱う。旧 aToken position を新 Pool に接続してはならない。GUARDIAN が旧 Strategy を `emergencyDisableStrategy` で停止し、旧 Pool から `sendToVault` / `emergencyWithdrawFromAave` で回収する。残余がある間は旧 Strategy を disabled のまま登録に残し、回収不能額が確定した場合だけ writeoff 手順へ進む。新 provider の `getPool()`、新 Pool reserve の aToken、Underlying 対応、reserve 状態を独立した freeze package で検証して新 Strategy を deploy / 登録し、承認済み cap / weight で段階的に allocation を再開する。
- **fail-closed**: provider の `getPool()` が freeze 済み Pool と一致しない場合は自動追従せず、deploy / allocation を停止して、同一 market の proxy 継続か別 market 移行かを判定する。旧 position の回収と新 venue の activation を1つのアドレス更新に短絡しない。
- Verification: manual（[Mainnet Deploy Env Freeze Runbook](../../../launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md) の provider / Pool / aToken 照合と market migration 手順）

### AAVE-GOV-002: testnet 先行

- Statement: Aave V3 は Sepolia に mainnet と 1:1 でアドレス・I/F が対応する同型テスト環境を提供する。デプロイ・統合テストは Sepolia で先行実施し、その後 mainnet に移行する。
- Verification: manual（Sepolia 統合テスト完了）

### AAVE-GOV-003: 異常時の新規割当停止と緊急回収

- Statement: Aave reserve に異常兆候（frozen / paused / supply cap 変更 / utilization 逼迫 / reserve deficit / 大規模バッドデット）がある場合、GUARDIAN は Vault 側で `emergencyDisableStrategy` により当 Strategy の `weightBps = 0` / `enabled = false` に設定して新規 supply を即時停止し、GOV は必要なら `cap = 0` 等の恒久設定を行う。Owner は必要に応じて `emergencyWithdrawFromAave` で liquid reserve 分を Vault へ回収し、回収額を returned principal として記帳する。会計値と実回収可能額の乖離が損失として確定した場合は、残 `principal` を `writeoffStrategyPrincipal` で backing へ下方反映する。Aave Governance のフォーラム・Snapshot 投票を継続ウォッチする。
- Verification: manual（監視・オペレーション Runbook）

---

## 11. イベント・監視要件（EVT）

共通イベント（`Deposited` / `SentToVault` / `ProfitSentToVault` / `PrincipalWrittenOff` / `EmergencyWithdrawn` / `RewardTokenSwept`）は `BaseStrategy` が発火する（[Strategy 要件定義](./Strategy.md)）。Aave V3 固有のイベント・監視は以下。

| ID | イベント | 用途（off-chain） |
| --- | --- | --- |
| AAVE-EVT-001 | `OwnScaledBalanceUpdated(uint256 ownScaledBalance)` | `_doDeposit` / `_doWithdraw` / `emergencyWithdrawFromAave` 後の自己 scaled 残高の追跡。AUM の基礎の推移監視 |
| AAVE-EVT-002 | `EmergencyWithdrawn(uint256 amount)`（BaseStrategy 共通イベント） | `emergencyWithdrawFromAave` の Vault 直送回収額の観測。`PrincipalReturned` と組み合わせて returned principal を追跡 |
| AAVE-EVT-003 | `AaveRewardsClaimed(address rewardsController, address reward, uint256 requested, uint256 claimed, uint256 settled)` | Aave RewardsController から claim した非 Underlying reward と Treasury 実着額の追跡。`RewardTokenSwept` と突合する |
| AAVE-EVT-004 | `AaveUnderlyingRewardsClaimed(address rewardsController, address reward, uint256 requested, uint256 claimed, uint256 sentToVault)` | Aave RewardsController から claim した Underlying reward と Vault buffer 実着額の追跡。principal を減らさない yield settlement として監視する |

**監視指標（Aave 固有）**:

- 当該 reserve の **utilization**: 80% 超で `weightBps` 引き下げの運用シグナル（[AAVE-ERR-002](#aave-err-002-utilization-100-による-withdraw-revert)）。
- **AUM vs 実回収額の乖離**: reserve 異常時に `_estimatedTotalUnderlying`（`getReserveNormalizedIncome` / 実 scaled 残高）が実質回収可能額と乖離しうるため、subgraph 側で乖離を可視化する（[AAVE-ERR-001](#aave-err-001-aave-reserve-設定変更frozen--paused--supply-cap) / [AAVE-TBD-003](#aave-tbd-003)）。
- **Aave reserve のヘルス**: frozen / paused / supply cap / borrow cap の状態を Aave Governance フォーラム・Snapshot・dashboard で継続ウォッチ。
- **Aave rewards settlement**: `AaveRewardsClaimed` / `AaveUnderlyingRewardsClaimed` と `RewardTokenSwept` / Vault buffer 実残高を突合し、reward が AUM / principal に混入していないことを確認する（[AAVE-FR-007](#aave-fr-007-claimaaverewardsaave-rewardscontroller-報酬claim) / [AAVE-ERR-005](#aave-err-005-報酬トークン取りこぼし)）。

---

## 12. 失敗時・異常系挙動（ERR）

共通の異常系（流動性不足を正常系として扱う push の整理・非同期プロトコルの吸収）は [Strategy 要件定義](./Strategy.md) を参照。本節では Aave V3 固有の事象と緩和策のみを記述する。

### AAVE-ERR-001: Aave reserve 設定変更（frozen / paused / supply cap）

- 契機: Aave Governance により reserve の状態が変更され、`supply` / `withdraw` が制限される（`frozen` / `paused` / supply cap / borrow cap 変更）。
- 挙動: `_doDeposit` の `supply` revert は `BaseStrategy.deposit` の隔離 frame で処理し、完全回収後は当該 allocation の skip、回収不一致は全体 revert となる。`_doWithdraw` の `withdraw` revert は従来どおり `sendToVault` / `sendProfitToVault` へ伝播する。
- 緩和策: Aave Governance のフォーラム・Snapshot 投票を継続ウォッチ。異常兆候があれば GUARDIAN が `emergencyDisableStrategy` で新規 supply を止め、Owner が `emergencyWithdrawFromAave` で liquid reserve 分を回収する（[AAVE-GOV-003](#aave-gov-003-異常時の新規割当停止と緊急回収)）。

### AAVE-ERR-002: utilization 100% による withdraw revert

- 契機: reserve が 100% utilization の場合、Aave の `withdraw` は clamp せず **revert** する（要求額を引き出せない）。
- 挙動: `AaveV3Strategy` は `withdraw` 呼び出し前に要求額を aToken の liquid underlying で cap するため、単なる流動性不足では `sendToVault` / `sendProfitToVault` は `0` または部分回収額を返す。Aave reserve が paused などで `withdraw` 自体を拒否する場合は revert が伝播する。
- 緩和策: 当該 reserve の utilization を常時監視し、80% 超で `weightBps` を下げる運用。Vault 側 `bufferTargetBps` / `bufferFloor` で在庫を確保（[CollateralVault 要件定義](../CollateralVault.md)）。

### AAVE-ERR-003: Aave 完全停止時の緊急回収不能

- 契機: Aave 側が完全停止していて `emergencyWithdrawFromAave` の `withdraw` 自体が revert する。
- 挙動: 緊急回収（[AAVE-FR-006](#aave-fr-006-emergencywithdrawfromaave緊急回収)）が救済不能となる。原子退避のため**関数全体が revert（fail-closed）**し、状態変化・評価の宙吊りは発生しない。`withdrawAmount == 0` でも idle Underlying があれば Vault へ push し、Aave/idle ともに 0 のときだけ `0` を返す。
- 緩和策: さらに上位の対策（Aave Governance への働きかけ、時間を置いての再試行）が必要。

### AAVE-ERR-004: aToken 評価の前提崩れ

- 契機: reserve 異常時（[AAVE-ERR-001](#aave-err-001-aave-reserve-設定変更frozen--paused--supply-cap) / [AAVE-ERR-002](#aave-err-002-utilization-100-による-withdraw-revert)・大規模バッドデット）に、`getReserveNormalizedIncome` や実 scaled 残高が実質回収可能額と乖離する。
- 挙動: `estimatedTotalUnderlying()`（`min(_ownScaledBalance, aToken.scaledBalanceOf) × getReserveNormalizedIncome / RAY`、[AAVE-FR-005](#aave-fr-005-_estimatedtotalunderlying評価額の算出)）が実質回収可能額と乖離する可能性。
- 緩和策（[AAVE-TBD-003](#aave-tbd-003)）: 補正は入れず subgraph 側で「AUM vs 実回収額の乖離」を可視化、または GUARDIAN が異常時に `emergencyDisableStrategy`、GOV が必要に応じて `cap = 0` を設定して実質的に新規割当を止める。

### AAVE-ERR-005: 報酬トークン取りこぼし

- 契機: Aave V3 の一部 reserve には `RewardsController` 経由のインセンティブ報酬（stkAAVE 等）があり、Merkl 等の外部 distributor から追加報酬が出る場合もある。
- 挙動: 現行 `AaveV3Strategy` は Merkl の標準 distributor 報酬を `BaseStrategy.claimMerklRewards`、Aave `RewardsController` 報酬を `claimAaveRewards` で claim できる。非 Underlying・非 protected reward token は Vault の現在 Treasury へ sweep し、Underlying reward は Vault buffer へ yield として直送する。すでに Strategy に着金した非 Underlying・非 protected reward token は共通 `BaseStrategy.sweepRewardToken` で Treasury へ送れる。これらの reward token は claim 前には `_estimatedTotalUnderlying()` / `realizedYield()` / dToken backing に含まれず、Underlying reward だけが Vault 実着後に buffer として backing に入る。aToken は position token として sweep / Merkl claim / Aave claim settlement 前に拒否される。
- 緩和策: Aave / Merkl reward は上記の明示関数で claim し、非 Underlying reward は Treasury に集約する。報酬を backing 補填に使う場合は Treasury / 運用手順で Underlying へ換金して `backstopDeposit` 等で明示的に入金する。Strategy 本体は reward swap を持たない。aToken を含む position token は報酬経路では扱わず、Aave withdraw / emergency withdraw で Underlying 化して Vault に戻す。

---

## 13. 受け入れ基準・検証計画

各要件の合格条件 = 下表の検証手段を満たすこと（テスト名・実行結果は本書に書かない＝手段の種別まで）。共通関数（`deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / `emergencyWithdraw`）の検証は [Strategy 要件定義](./Strategy.md) を参照。

| ID | 要件（要約） | 検証手段 |
| --- | --- | --- |
| AAVE-FR-001 | initialize（投資先固定・aToken underlying 検証・Pool max approve・ゼロ/多重 revert） | unit |
| AAVE-FR-002 | addStrategy 前提（whitelist→addStrategy・Underlying 一致検証） | integration, manual |
| AAVE-FR-003 | _doDeposit（`supply(onBehalfOf=this)`・scaled 差分計上・zero-scaled supply revert） | unit, fork, invariant=AAVE-INV-001 |
| AAVE-FR-004 | _doWithdraw（`withdraw(to=this)`・scaled 減算・zero-scaled burn revert・liquid reserve cap・reported-zero guard） | unit, fork, invariant=AAVE-INV-001 |
| AAVE-FR-005 | _estimatedTotalUnderlying（`min`・RAY 換算・donation 排除） | unit, fork, invariant=AAVE-INV-002 |
| AAVE-FR-006 | emergencyWithdrawFromAave（onlyOwner・liquid reserve 分の回収・Vault atomic push・returned principal 記帳） | unit, fork |
| AAVE-FR-007 | claimAaveRewards（assets=aToken 固定・Underlying reward は Vault buffer・非 Underlying reward は Treasury sweep・protected token 拒否） | unit, fork |
| AAVE-INV-001..005 | §8 各不変条件 | invariant / fork / unit（§8 記載どおり） |
| AAVE-SEC-001..005 | §9 各セキュリティ要件 | invariant / unit / fork / manual |
| AAVE-EVT-001..004 | §11 各 Aave 固有イベント | unit |
| AAVE-ERR-001..005 | §12 各 Aave 固有異常系 | unit / fork / manual |

---

## 14. 未決事項（TBD）

### AAVE-TBD-001

`forceApprove(max)` 採用方針の最終確認 — per-deposit approve への変更余地、Aave Pool 侵害時のリスク評価。関連: [AAVE-FR-001](#aave-fr-001-initialize投資先固定proxy-初期化)。

### AAVE-TBD-002

`referralCode` の確定値 — `0` のまま / Aave リファラル登録 / 自前識別子。関連: [AAVE-FR-003](#aave-fr-003-_dodepositaave-v3-への-supply)。

### AAVE-TBD-003

aToken → Underlying 換算における保守的評価の要否 — `_estimatedTotalUnderlying` にさらなる保守的補正を入れるか。関連: [AAVE-FR-005](#aave-fr-005-_estimatedtotalunderlying評価額の算出) / [AAVE-ERR-004](#aave-err-004-atoken-評価の前提崩れ)。

現時点の整理:

- **一時的な流動性不足では評価を下げない**。reserve utilization 逼迫や liquid underlying 不足は confirmed loss ではなく、Aave 会計上の claim は残るため、`_estimatedTotalUnderlying` / `backingRatio` を liquid reserve で cap すると誤 markdown・誤清算を誘発する。withdraw 経路は [AAVE-TBD-008](#aave-tbd-008) の liquid reserve cap で部分回収 / 0 回収に留める。
- **Aave 会計に出た損失は live valuation に反映する**。`aToken.scaledBalanceOf(this)` または `getReserveNormalizedIncome` が下がる場合は [AAVE-FR-005](#aave-fr-005-_estimatedtotalunderlying評価額の算出) の式に自然に入る。
- **Aave 会計に出ないが実回収不能な損失だけが本 TBD の対象**。reserve deficit / bad debt / protocol incident により `estimatedTotalUnderlying()` と実回収可能額が乖離し、外部証跡・回収 tx・Aave governance 状態から残額が回収不能と判断できる場合、回収済み額を先に Vault へ戻し、補填できる場合は `backstopDeposit` を先行し、最後に確定残額だけ `writeoffStrategyPrincipal` で反映する。運用手順は [Strategy Incident / Liquidation Safety Runbook](../../../operations/runbooks/Strategy-Incident-Liquidation-Safety-Runbook.md) を正とする。

未決として残るのは、上記の manual writeoff 運用に加えて、外部 risk oracle / Aave reserve deficit feed / governance event watcher などを使った自動的な保守補正を入れるかどうかである。採用する場合も、一時流動性不足と confirmed loss を分ける guard が必須。

### AAVE-TBD-004

`emergencyWithdrawFromAave()` に Aave drain 額専用の `EmergencyAaveWithdrawn(uint256 withdrawn, uint256 sent)` イベントを追加するか。現状は Vault push 額を Strategy 共通 `EmergencyWithdrawn(sent)` と `PrincipalReturned(returned, newPrincipal)` で観測する。関連: [AAVE-FR-006](#aave-fr-006-emergencywithdrawfromaave緊急回収) / AAVE-EVT-002。

### AAVE-TBD-005

Aave / Merkl 等の未 claim 報酬を取り込むか — Resolved/Scoped（2026-06-18）: Merkl の標準 distributor 報酬は共通 `BaseStrategy.claimMerklRewards`、Aave `RewardsController` 報酬は `claimAaveRewards` で取り込む。claim 後は Underlying reward を Vault buffer へ yield 送付し、非 Underlying reward は `BaseStrategy._sweepRewardToken` の固定 Treasury / protected token 拒否 / 実着額イベントを再利用する。aToken は protected token なのでこの経路では扱わない。残る未決は reward swap、非 Underlying 報酬を backing 補填に使う場合の Underlying 換金・`backstopDeposit` 手順である。関連: [AAVE-FR-007](#aave-fr-007-claimaaverewardsaave-rewardscontroller-報酬claim) / [AAVE-ERR-005](#aave-err-005-報酬トークン取りこぼし)。

- **A**: 本 Strategy に claim → settlement / swap 経路を実装する。ただし Strategy 本体が swap router を持つ場合は攻撃面が増える。claim → settlement までは `claimMerklRewards` / `claimAaveRewards` として実装済み。
- **B**: そもそもインセンティブ発生 reserve / campaign を採用しない（実装複雑化を回避）。
- **C**: protocol-specific claim を別コントラクト（`AaveRewardsClaimer` 等）として切り出す案は不採用。Aave claim は `claimAaveRewards` として Strategy 本体に最小実装し、claim 後の送金は `BaseStrategy._sweepRewardToken` / `_sendUnderlyingToVault` helper に寄せる。

当面は claim / sweep までを Strategy が担い、swap / backing 補填は Treasury・運用 runbook 側で別途扱う。非 Underlying reward は Strategy の AUM・principal・Vault buffer に直接入れない。

### AAVE-TBD-006

Resolved: `AAVE-FR-001`、`AAVE-SEC-004` に反映済み。

### AAVE-TBD-007

Resolved: `AAVE-FR-001` と [Mainnet Deploy Env Freeze Runbook](../../../launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md) に反映済み。

### AAVE-TBD-008

Resolved: `AAVE-FR-004`、`AAVE-FR-005`、`AAVE-ERR-002`、`STGY-SEC-005` に反映済み。

---

## 15. 参考資料

### 実装

- `contracts/src/Strategies/AaveV3Strategy.sol`（Aave V3 個別 Strategy 本体）

### 関連ページ

- [Strategy 要件定義](./Strategy.md) — `IStrategy` / `BaseStrategy` / push モデル・共通権限・共通リスク・共通イベント（親ページ・正本）
- [CollateralVault 要件定義](../CollateralVault.md) — whitelist / `addStrategy` / `receiveFromStrategy` / buffer・cap・weights
- [dToken 要件定義](../dToken.md) — 担保受益権トークン（Underlying 換算・Cap）
- [要件定義ドキュメント標準](../../../../Requirements-Spec-Standard.md) — 本書が従う標準

### 外部リソース

- [Aave V3 documentation](https://aave.com/docs)
- [Aave addresses (mainnet / testnet)](https://aave.com/docs/resources/addresses)
- [Aave V3 supply](https://aave.com/docs#supply)
