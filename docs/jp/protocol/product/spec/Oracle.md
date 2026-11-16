# 🟢 オラクル 要件定義

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Draft（実装あり・要件の正本化中） |
| Owner | DeltaForesight |
| 対象コントラクト | `contracts/src/PriceFeeds/PriceFeedProxy.sol`（外側固定参照レイヤー・`Ownable2Step`）/ `contracts/src/PriceFeeds/DFPriceFeedBase.sol`（DF JPY 換算基底・`is MainnetPriceFeedBase`）/ 共有 JPY 層: `contracts/src/PriceFeeds/JpyUsdRateProvider.sol`（deployment-wide JPY/USD cache・freeze state machine）/ `contracts/src/PriceFeeds/JpyFreezeLib.sol`（共有 JPY 換算 / freeze / backing library）/ Active な担保別 PriceFeed: `contracts/src/PriceFeeds/DFUSDCPriceFeed.sol` / `contracts/src/PriceFeeds/DFWstETHPriceFeed.sol`（stETH/USD × canonical rate composite・`CompositePriceFeed` 継承）/ `contracts/src/PriceFeeds/PriceFeedPlaceholder.sol`（placeholder ブランチの初期 source）。Archived candidate feed: `contracts/src/PriceFeeds/archive/DFUSDTPriceFeed.sol` / `contracts/src/PriceFeeds/archive/DFXAUTPriceFeed.sol` / `contracts/src/PriceFeeds/archive/DFWBTCPriceFeed.sol` / `contracts/src/PriceFeeds/archive/sUSDSPriceFeed.sol`（Composite rate・`CompositePriceFeed` 継承）。🔵 upstream 由来基底 = `contracts/src/PriceFeeds/MainnetPriceFeedBase.sol`（Chainlink 応答検証の硬化差分あり）/ `contracts/src/PriceFeeds/CompositePriceFeed.sol`（sUSDS 用に primary → `lastGoodPrice` へ絞った upstream 由来基底。WSTETH/RETH 用 LST secondary fallback は削除済み）。配線 = `contracts/script/DeployLiquity2.s.sol` |
| 関連ドキュメント | [Product-Overview](../Product-Overview.md)（アーキ・責務分離）/ [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md)（🔵 コアの担保・清算・Redemption・PriceFeed 基底）/ [CollateralVault](./CollateralVault.md)（Underlying 後付け確定・placeholder 連携）/ [dToken](./dToken.md)（placeholder ブランチ・cap・setTokenInfo）/ [Parameters](../../../Parameters.md)（ブランチ↔担保割当・staleness・MCR/LLTV 等の値） |

> 本書は [要件定義ドキュメント標準](../../../Requirements-Spec-Standard.md)に従う。要件・不変条件・セキュリティ要件には永続 ID（`ORCL-…`）を付し、相互参照は ID で行う。

---

## 1. 目的・スコープ・非責務

オラクルレイヤーは、Liquity v2 コアが参照する**オラクル参照先アドレスを固定**したまま、その裏側の実 PriceFeed（source）を**差し替え可能**にし、かつ全担保価格を**JPY 建て**で供給する DeltaForesight 独自レイヤー。固定参照先 `PriceFeedProxy` を各担保ブランチに 1 つずつ挟み、JPY/USD 換算は upstream 由来の PriceFeed 基底へ焼き込まず DF 層で足す。`MainnetPriceFeedBase` の差分は、後述の Chainlink 応答検証硬化に限定する。

- **本書が規定する**: `PriceFeedProxy`、DF PriceFeed、担保別オラクルパターン、backing 比反映、placeholder 有効化、両 consumer 経路、障害時挙動。
- **本書が規定しない（非責務・他文書）**:
  - 🔵 upstream 由来の価格取得基底（`MainnetPriceFeedBase` / `CompositePriceFeed`）の内部挙動・`PriceSource` 状態機械・Chainlink 取得・18 桁正規化・shutdown の発火本体 → [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md)（本書は DF が足す層、`MainnetPriceFeedBase` の Chainlink 応答検証硬化差分、および `CompositePriceFeed` の sUSDS 限定 pruning を規定）
  - dToken の placeholder 立ち上げ・`setTokenInfo`・cap・換算 → [dToken](./dToken.md)
  - Underlying の保管・`setUnderlying`・mint/redeem・buffer 会計 → [CollateralVault](./CollateralVault.md)
  - ブランチ番号↔担保（Underlying）割当・確定/未確定の別・staleness 確定値・MCR/LLTV/CCR・デペグ織込み値 → [Parameters](../../../Parameters.md)
- **責務境界（あえて知らない）**: オラクルレイヤーは「どのブランチが何番か」を前提とせず、**担保資産の性質ごとのオラクルパターン**だけを定義する。具体的なブランチ↔担保割当・確定状況は [Parameters](../../../Parameters.md) を正本として参照する。

---

## 2. 背景・設計方針

Liquity v2 では、プロトコル（BorrowerOperations / TroveManager）が **Chainlink の Price Feed コントラクトを直接参照**し、その参照先アドレスはデプロイ後**変更できない**。

```javascript
Protocol (BorrowerOperations, TroveManager)
            ↓
Chainlink Price Feed (ETH/USD, BTC/USD…)
```

この設計のままでは、Chainlink が特定フィードを deprecate した場合・フィード障害が発生した場合・担保資産の構成を将来変更する場合に、参照先を差し替える手段がない。DeltaForesight のオラクルレイヤーは以下の方針でこれを解決する。

- **固定参照先 ＋ 差替可能な source**: Liquity v2 コアから見た「オラクル参照先アドレス」は固定したまま、**`PriceFeedProxy` を挟み、その裏側の実 PriceFeed（source）を差し替え可能にする**ことで、実質的なオラクル変更を実現する（[ORCL-FR-001](#orcl-fr-001-source-差替の提案proposesource) / [ORCL-FR-002](#orcl-fr-002-source-差替の確定confirmsource)）。
- **障害をレッグ単位で隔離する**: 担保・peg・canonical・backing レッグは標準 shutdown、全ブランチ共通の JPY/USD レッグは `ORCL-SEC-005` の有界 soft-freeze を使う。
- **DF 差分を局所化する**: upstream 基底の変更は Chainlink 応答検証の硬化に限り、JPY 換算と backing 反映は DF 層へ閉じる（`ORCL-SEC-001`）。
- **8 ブランチ全登録 ＋ placeholder**: dToken アプローチにより Day 1 時点で 8 ブランチすべてを登録し、Underlying 未確定ブランチは `PriceFeedPlaceholder` を初期 source としてデプロイ、Day 2 に有効化する（[ORCL-FR-008](#orcl-fr-008-placeholder-ブランチの初期-source-pricefeedplaceholder) / [ORCL-FR-009](#orcl-fr-009-post-launch-未確定ブランチの-underlying-確定フロー)）。

設計判断は `ORCL-SEC-001`、`ORCL-SEC-003`、`ORCL-SEC-005` に規範化する。JPY/USD staleness の定量根拠は [設計メモ](../../launch/decisions/jpyusd-staleness-threshold-determination.md)、コア無改変の全体方針は [Product Overview](../Product-Overview.md) を正本とする。

---

## 3. 用語・外部依存・前提

### 3.1 アーキテクチャ全体像

```plain text
┌─────────────────────────────────────────────────────────────────┐
│ Protocol (BorrowerOperations, TroveManager, StabilityPool)       │
└───────────────────────────────┬─────────────────────────────────┘
                                │ fetchPrice() / fetchRedemptionPrice()
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ PriceFeedProxy (Ownable2Step, 非アップグレード)                   │
│  - source (差替可能, 12h timelock)                                │
│  - _lastGoodPrice / _lastGoodRedemptionPrice (自己防衛キャッシュ) │
│  - ownership (2-step transfer / renounce disabled)               │
└───────────────────────────────┬─────────────────────────────────┘
                                │ delegates to source
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ DF PriceFeed 実装（担保別。例: WETH / sUSDS / XAUT …）            │
│   継承 = upstream 由来の価格取得基底＋ DF JPY 換算基底             │
│                                                                   │
│  ┌──────────────────────────────┐   ┌──────────────────────────┐ │
│  │ 🔵 upstream 由来              │   │ 🟢 DF: DFPriceFeedBase    │ │
│  │  MainnetPriceFeedBase /       │ + │   (is MainnetPriceFeedBase)│ │
│  │  CompositePriceFeed（sUSDS）  │   │  ├ jpyUsdOracle (JPY/USD) │ │
│  │  ├ 担保/USD Chainlink         │   │  └ _convertUsdPriceToJpyWithFreeze │ │
│  │  ├ canonical rate（composite）│   └──────────────────────────┘ │
│  │  └ PriceSource / lastGoodPrice│                                │
│  └──────────────────────────────┘   担保/USD等の障害 → shutdown    │
│                                      JPY/USD障害 → soft-freeze      │
└─────────────────────────────────────────────────────────────────┘
```

固定参照先と差替可能 source の関係（Protocol から見たアドレスは固定、その裏の source は差替可能）:

```javascript
Protocol (BorrowerOperations, TroveManager)
            ↓  ★Protocol から参照するアドレスは固定（Liquity v2 と同様）
PriceFeedProxy
            ↓  ★PriceFeedProxy から参照する source（=各種 PriceFeed 実装）は差替可能
各種 PriceFeed (DFWstETHPriceFeed, DFUSDCPriceFeed, etc.)
            ↓  ★内部で Chainlink フィードを参照
Chainlink Aggregator（+ JPY/USD Chainlink、JPY 換算用）
```

確定済み／未確定ブランチと PriceFeedProxy の割当:

```javascript
Protocol
 ├─ 確定済みブランチ → PriceFeedProxy#n → 実 PriceFeed（担保別: Standard / Composite rate / Composite peg、§6）
 └─ 未確定ブランチ   → PriceFeedProxy#n → PriceFeedPlaceholder（Day2 に実 feed へ差替）
                              ↑
                        ブランチ毎に 1 つずつ PriceFeedProxy を割り当て
                        （固定の参照先としてコアロジックに渡す。ブランチ番号↔担保は Parameters.md を正本とする）
```

### 3.2 collateral/JPY 価格の導出

```javascript
Collateral/JPY        = (Collateral/USD) ÷ (JPY/USD)        // market price（担保別 _fetchPricePrimary）
dToken/JPY（担保価値）  = mulDiv(Collateral/JPY, backingRatio, 1e18) // 全担保共通の後段層（ORCL-FR-014, floor）
```

※ Chainlink の JPY/USD フィード（`0xBcE206caE7f0ec07b545EddE332A47C2F75bbeb3`）は **USD per JPY**（≈ 0.006667）を返す。JPY/USD の取得・cache・freeze 状態は deployment-wide に1つだけ配置する `JpyUsdRateProvider` が担い、全 active feed が同じ provider を参照する。`DFPriceFeedBase` / `sUSDSPriceFeed` は provider の返す rate で除算する。

※ JPY/USD の値は [Parameters](../../../Parameters.md) `PRM-ORACLE-001`、障害時挙動は `ORCL-SEC-005`、FX 休場を含む根拠は [設計メモ](../../launch/decisions/jpyusd-staleness-threshold-determination.md) を正本とする。

※ 最終段で **dToken の backing 比（裏付け率 `A / L_effective`、`<= 1e18`）** を乗じ、Strategy 毀損時の dToken デペグを担保価値へ反映する（[ORCL-FR-014](#orcl-fr-014-dtoken-backing-peg-の反映全担保共通の後段層)）。健全時は `backingRatio == 1e18` で market price と一致する。

### 3.3 用語

| 用語 | 意味 |
| --- | --- |
| source | `PriceFeedProxy` が委譲する実 PriceFeed 実装。差替可能（12h timelock） |
| 担保/USD オラクル | 担保資産の USD 建て Chainlink アグリゲータ。upstream ストレージ名は `ethUsdOracle`（担保が ETH 以外でも同名・本書擬似コードでは可読性のため `collUsdOracle` と表記） |
| `jpyUsdOracle` | JPY/USD の Chainlink アグリゲータ（**USD per JPY** を返す）。`JpyUsdRateProvider` が1箇所で保持 |
| `jpyUsdRateProvider` | 全 active feed に同じ address を注入する JPY rate/cache/freeze の単一 state machine |
| canonical rate | yield-bearing トークンの原資産換算レート（sUSDS なら USDS per sUSDS）。Chainlink ではなく rate provider コントラクトから取得 |
| `PriceSource` | 価格ソース状態（`primary` / `ETHUSDxCanonical` / `lastGoodPrice`）。upstream `MainnetPriceFeedBase` 定義を保持するが、現行 production feed は `primary` / `lastGoodPrice` のみを使う |
| `lastGoodPrice` | 障害時に返し続ける最後の健全価格。upstream 基底（feed 単位）と Proxy（通常経路 `_lastGoodPrice` / redemption 経路 `_lastGoodRedemptionPrice`）の二層 |
| branch shutdown | `borrowerOperations.shutdownFromOracleFailure()` によるブランチ停止 |
| placeholder ブランチ | Underlying 未確定でデプロイし Day 2 に有効化する担保枠。初期 source は `PriceFeedPlaceholder` |
| Peg Monitor | wrapper と原資産のペグ乖離を検知する監視フィード（WBTC/BTC・XAUT/XAU） |
| GOV / multisig | `PriceFeedProxy` の Owner（governance のマルチシグ） |

### 3.4 外部依存（信頼する外部）

- **Chainlink Data Feeds** — 担保/USD・JPY/USD・peg 監視の価格ソース。`roundId`、`answeredInRound`、`updatedAt`、staleness、`answer` を検証し、無効応答は fail-closed とする。
- **sUSDS コントラクト**（`0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD`、rate provider）— ERC-4626 `convertToAssets(1e18)` を canonical rate として直接参照（非 Chainlink）。
- **wstETH コントラクト**（`0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0`、rate provider）— `stEthPerToken()` を canonical rate（stETH per wstETH）として直接参照（非 Chainlink・staleness 概念なし。ORCL-FR-015）。
- **🔵 upstream 由来の価格取得基底**（`MainnetPriceFeedBase` / `CompositePriceFeed`）— Chainlink 取得・18 桁正規化・gas griefing 保護・`PriceSource`・shutdown 本体を担う。`MainnetPriceFeedBase` は Chainlink 応答検証の硬化差分を持ち、`CompositePriceFeed` は sUSDS 用に primary → `lastGoodPrice` 経路へ絞った upstream 由来基底として使う（WSTETH/RETH 用 LST secondary fallback は production `src` から削除済み、[Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md)）。
- **OpenZeppelin `Ownable2Step`** — `PriceFeedProxy` の 2 段階所有権移転。

### 3.5 前提

- Liquity v2 コアはオラクル参照先アドレスをデプロイ時固定し、コア側から変更できない。
- Chainlink 担保/USD・JPY/USD フィードはいずれも 8 桁（`decimals == 8` を upstream / DF 基底 constructor で `assert`）。`_getOracleAnswer` が 18 桁へ正規化済みの値のみを扱う。
- JPY/USD フィードは **USD per JPY**（≈ 0.006667）を返す。JPY 建ては full-precision の `mulDiv(collUsd, 1e18, jpyUsdRate)` で得る（丸め方向は従来の floor）。
- レッグ別の障害時挙動は `ORCL-SEC-005` に従う。
- ブランチ番号↔担保（Underlying）割当・確定/未確定の別は [Parameters](../../../Parameters.md) を正本とする（本書は番号を持たない）。

---

## 4. アクター・ロール・信頼境界

| アクター | 操作 | 信頼境界 |
| --- | --- | --- |
| **Owner（GOV / multisig）** | `proposeSource` / `confirmSource` / `cancelSourceProposal` / `transferOwnership` / `acceptOwnership` / `renounceOwnership` | 強力権限（source 差替・所有権移転）。本番は governance / multisig。デプロイ初期は deployer EOA。`renounceOwnership` は無効化 |
| **Protocol（BorrowerOperations / TroveManager / StabilityPool）** | `fetchPrice` / `fetchRedemptionPrice` | コアの正規 consumer。`PriceFeedProxy` を固定参照先として呼ぶ。`shutdownFromOracleFailure()` の呼出元は `address(priceFeed)`（= Proxy）であることを要求する信頼関係（[ORCL-FR-004](#orcl-fr-004-fetchprice障害透過と-shutdown-代行)） |
| **source（実 PriceFeed）** | Proxy から委譲を受け価格を返す | 差替可能。Proxy は source の revert / 無効価格 / brick を防御的に扱う（完全信頼しない） |
| **CollateralVault（backing source）** | source が `backingRatioForPricing()` を読む | dToken の裏付け率（`A / L_effective`）と valuation availability を提供する読み取り専用の参照先。通常の read failure または `available == false` は oracle failure として branch shutdown に流す（[ORCL-FR-014](#orcl-fr-014-dtoken-backing-peg-の反映全担保共通の後段層)）。Vault 側で完結する会計に依拠し、オラクルは比率を読むだけ |
| **任意（permissionless）** | `fetchPrice` / `fetchRedemptionPrice`（view 的読み出し）/ source proposal の観測 | 信頼不要 |

- **権限分離**: source 差替・所有権移転は Owner のみ。価格取得経路（`fetchPrice` / `fetchRedemptionPrice`）は認可を持たず、誰でも同じ価格を読める。
- **運用方針（所有権の移転）**: デプロイ初期は deployer EOA が所有し、本番移行時に `transferOwnership()` →（新オーナーが）`acceptOwnership()` で **governance / multisig** へ**移管**する。本番 Owner は GOV multisig が直接保持し、共通 TimelockController の配下には置かない（source 差替は PriceFeedProxy 内蔵の 12h timelock で保護され、Timelock 配下にすると 12h+12h の二重遅延と cancel 即時性の喪失を招くため。[ORCL-GOV-001](#orcl-gov-001-owner-は-governance--multisig) / [ORCL-GOV-002](#orcl-gov-002-owner-移譲は-2-step)）。

---

## 5. インターフェース仕様

`PriceFeedProxy`（外側固定参照）と DF PriceFeed 実装（内側 source）の主要関数。挙動は §6 機能要件、可視性のみ以下に要約（非規範）。

各 DF PriceFeed は upstream 由来の価格取得基底を継承し、deployment-wide の `JpyUsdRateProvider` から同じ JPY rate を取得して branch-local backing 比を適用する。JPY 換算 / freeze / backing のロジック本体は共有 `JpyFreezeLib` であり、標準・peg 型の `DFPriceFeedBase` と composite 型（`sUSDSPriceFeed` / `DFWstETHPriceFeed`、pruned `CompositePriceFeed` 継承）は library の state 保持と配線だけを持つ。JPY cache / freeze state は重複しない。

**PriceFeedProxy（`Ownable2Step`、非アップグレード）**

| 関数 | 可視性 | 要約 | 規定要件 |
| --- | --- | --- | --- |
| `proposeSource(address newSource)` | external (onlyOwner) | 新 source を提案（12h timelock 開始） | ORCL-FR-001 |
| `confirmSource()` | external (onlyOwner) | timelock 経過後に source 差替確定（通常時は価格差 guard あり） | ORCL-FR-002 |
| `confirmSourceEmergency()` | external (onlyOwner) | timelock 経過後に source 差替確定（価格差 guard のみ明示 bypass） | ORCL-FR-002 |
| `cancelSourceProposal()` | external (onlyOwner) | 保留中の source proposal を取消 | ORCL-FR-003 |
| `fetchPrice() → (uint256, bool)` | external | source へ委譲・障害透過・shutdown 代行 | ORCL-FR-004 |
| `fetchRedemptionPrice() → (uint256, bool)` | external | redemption 価格を同構造で委譲 | ORCL-FR-005 |
| `transferOwnership(address)` / `acceptOwnership()` | external (onlyOwner / pendingOwner) | 2-step 所有権移転 | ORCL-FR-006 |
| `renounceOwnership()` | external (onlyOwner) | 常に `RenounceOwnershipDisabled` で revert | ORCL-FR-007 |
| `_bubbleIfGasError(bytes)` | internal | gas guard revert を透過判定 | ORCL-FR-004 |
| `TIMELOCK_DELAY` | constant | `24 hours` | ORCL-FR-001 |

**DF PriceFeed 実装（内側 source）**

| 関数 | 可視性 | 要約 | 規定要件 |
| --- | --- | --- | --- |
| `_fetchPricePrimary()` | internal | 担保/USD → JPY 換算 → `lastGoodPrice` 記録 | ORCL-FR-010〜013 |
| `_convertUsdPriceToJpyWithFreeze(uint256 usdPrice)` | internal（実装 = 共有 `JpyFreezeLib`。呼出は `DFPriceFeedBase` / `sUSDSPriceFeed` / `DFWstETHPriceFeed`） | 共有 `JpyUsdRateProvider` の結果で USD→JPY 換算。live/frozen rate と expiry 判定は provider 側が単一保持し、expired freeze は standard branch shutdown | ORCL-FR-010 / ORCL-SEC-005 |
| `_getCanonicalRate()` | internal (composite) | canonical rate（sUSDS は `convertToAssets(1e18)`、wstETH は `stEthPerToken()`） | ORCL-FR-012 / ORCL-FR-015 |
| `_applyBackingRatio(uint256 collJpy)` | internal（実装 = 共有 `JpyFreezeLib`。state は各 feed） | `collateralVault.backingRatioForPricing()` を乗じ dToken 実質担保価値を返す。通常の read failure または valuation 取得不能は oracle failure、gas guard revert は再 revert | ORCL-FR-014 |
| `fetchPrice()` / `fetchRedemptionPrice()` / `lastGoodPrice()` | external | upstream 基底由来の IPriceFeed 標準 | [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md) |

**PriceFeedPlaceholder（placeholder ブランチの初期 source）**

| 関数 | 可視性 | 要約 | 規定要件 |
| --- | --- | --- | --- |
| `fetchPrice()` / `fetchRedemptionPrice()` | external view | 常に `(1e18, false)` を返す stub | ORCL-FR-008 |

---

## 6. 機能要件（FR）

> §6.A = PriceFeedProxy（外側固定参照レイヤー）。§6.B = DF PriceFeed 実装（内側 source / 担保別オラクルパターン）。§6.C = placeholder ブランチと Post-launch 確定。

### 6.A PriceFeedProxy（外側固定参照レイヤー）

`PriceFeedProxy` は OpenZeppelin **`Ownable2Step`** を継承する通常のコントラクトであり、UUPS 等のプロキシ・アップグレード機構は持たない（非アップグレード）。「Proxy」という名称は、Protocol から見た**固定参照先**として振る舞い、その裏側の `source`（実 PriceFeed）を差し替える役割を指す。コントラクトのロジック自体を `upgradeTo` で更新する仕組みではない。ロジックを変えたい場合は新しい PriceFeed をデプロイして `proposeSource()` で source を差し替える（= feed 単位の入れ替え）。

#### ORCL-FR-001: source 差替の提案（proposeSource）

- **Type**: Functional ｜ **Source**: Product-Overview「Oracle Layer」/ DF 設計根拠（フィード差替・MEV 緩和）
- **シグネチャ**: `proposeSource(address newSource)`
- **目的**: 裏側の実 PriceFeed（source）を新アドレスへ差し替えるための提案を登録し、12h timelock を開始する。即時差替は不可とし、切替予定時刻と新 source を 12 時間前に公開する（事前監査・キャンセルを可能にする）。
- **権限**: Owner（GOV / multisig）のみ（`onlyOwner`）。
- **事前条件（Checks）**: `caller == Owner`。`newSource` が有効アドレス（constructor 同様に `address(0)` / EOA は不可 = `InvalidSource`）で、現 `source` と同一ではないこと（同一なら `SameSource`）。
- **動作（Effects）**:
  1. 保留 source proposal（`newSource` と確定可能時刻 = `block.timestamp + TIMELOCK_DELAY`）を記録
  2. `SourceProposed` を発火（new source・確定可能時刻を index）
- **revert / 早期 return**: 非 Owner → revert；`newSource == address(0)` / EOA → `InvalidSource`；`newSource == source` → `SameSource`。
- **発火イベント**: `SourceProposed`（[ORCL-EVT-001](#11-イベント監視要件evt)）。
- **設計上のポイント**: `TIMELOCK_DELAY = 24 hours`（定数）。タイムロック単体では `confirmSource` ブロックでの**価格ジャンプ MEV**（切替直後に新価格で redemption / 清算を打つ）は排除しないため、確定時の価格差 guard と private 送信運用を併用する（[ORCL-SEC-003](#orcl-sec-003-source-差替-timelock-による-mev-緩和)）。
- **Verification**: unit（Owner 限定・`address(0)` 拒否・proposal 記録）。

#### ORCL-FR-002: source 差替の確定（confirmSource）

- **Type**: Functional ｜ **Source**: Product-Overview「Oracle Layer」/ DF 設計根拠
- **シグネチャ**: `confirmSource()` / `confirmSourceEmergency()`
- **目的**: 12h timelock 経過後に保留中の source proposal を確定し、`source` を新 PriceFeed に差し替える。
- **権限**: Owner（GOV / multisig）のみ。
- **事前条件（Checks）**: `caller == Owner`；保留中 proposal が存在；現在時刻が確定可能時刻（`proposedAt + TIMELOCK_DELAY`）以降。
- **動作（Effects）**:
  1. 旧 source を best-effort で読み、`fetchPrice` / `fetchRedemptionPrice` が両方とも有効価格・`failure=false` なら「旧 source 健全」と判定
  2. 新 source の `fetchPrice` / `fetchRedemptionPrice` を smoke-test し、revert / wrong ABI / 無効価格 / `failure=true` なら拒否
  3. 価格差の基準値は、旧 source が健全ならその live 通常価格・redemption 価格、不健全なら Proxy の `_lastGoodPrice`・`_lastGoodRedemptionPrice` とする
  4. `confirmSource()` は旧 source の健全性にかかわらず、新 source の両価格が基準値から `MAX_SOURCE_SWITCH_DEVIATION_BPS`（1%）以内であることを要求する。`confirmSourceEmergency()` だけが価格差 guard を明示 bypass する
  5. `_lastGoodPrice = newPrice` / `_lastGoodRedemptionPrice = newRedemptionPrice` で Proxy cache を新 source 価格に再初期化
  6. `source = proposedSource`（差替完了）、保留 proposal をクリア
  7. `SourceUpdated` / `SourceSwitchValidated` を発火
- **revert / 早期 return**: 非 Owner → revert；proposal なし → `NoProposalPending`；timelock 未経過 → `TimelockNotElapsed`；new source 不正 → `InvalidSource`；`proposedSource == source` → `SameSource`；通常 confirm で live / cached 基準から価格差 > 1% → `SourcePriceDeviationTooLarge`。
- **発火イベント**: `SourceUpdated(oldSource, newSource)`（[ORCL-EVT-002](#11-イベント監視要件evt)）、`SourceSwitchValidated`（[ORCL-EVT-006](#11-イベント監視要件evt)）。
- **設計上のポイント**: 通常差替は価格差 guard でサンドイッチ余地を抑える。旧 source 障害で通常経路が暗黙に emergency 化することはなく、validated cache との連続性を要求する。placeholder 有効化や cached 価格から1%を超える incident 復旧は `confirmSourceEmergency()` を private 送信（Flashbots Protect 等）し、必要に応じて cap 停止・keeper bundle と組み合わせる（[ORCL-SEC-003](#orcl-sec-003-source-差替-timelock-による-mev-緩和)）。
- **Verification**: unit（timelock 経過後のみ成功・未経過 revert・差替反映・live / cached 価格差 guard・通常経路の暗黙 bypass 禁止・emergency bypass）, manual（private 送信運用）。

#### ORCL-FR-003: source proposal の取消（cancelSourceProposal）

- **Type**: Functional ｜ **Source**: DF 設計根拠（差替の中断可能性）
- **シグネチャ**: `cancelSourceProposal()`
- **目的**: timelock 待機中の source proposal を Owner が中止し、clean state に戻す。
- **権限**: Owner（GOV / multisig）のみ。
- **事前条件（Checks）**: `caller == Owner`；保留中 proposal が存在。
- **動作（Effects）**:
  1. 保留 proposal をクリア（source は据置）
  2. `SourceProposalCancelled` を発火
- **revert / 早期 return**: 非 Owner → revert；proposal なし → `NoProposalPending`。
- **発火イベント**: `SourceProposalCancelled`（[ORCL-EVT-003](#11-イベント監視要件evt)）。
- **設計上のポイント**: Owner 放棄は無効化されているため、不要な保留 proposal は `cancelSourceProposal()` で明示的に取り消す（[ORCL-FR-007](#orcl-fr-007-renounceownership無効化)）。
- **Verification**: unit（Owner 限定・proposal クリア）。

#### ORCL-FR-004: fetchPrice（障害透過と shutdown 代行）

- **Type**: Functional ｜ **Source**: Liquity-v2-Core-Spec（shutdown 機構）/ DF 設計根拠（Proxy protection layer）
- **シグネチャ**: `fetchPrice() → (uint256 price, bool isShutdown)`（IPriceFeed 互換）
- **目的**: source の `fetchPrice()` へ委譲しつつ、Proxy 自身が protection layer として機能する。underlying feed が oracle 失敗時に `borrowerOperations.shutdownFromOracleFailure()` を直接呼ぶと `msg.sender` が underlying feed になり、BorrowerOperations が要求する `msg.sender == address(priceFeed)`（= Proxy）に反して revert する。これを避けるため Proxy が revert / 無効価格を `try/catch` で受け取り、**自身が** `shutdownFromOracleFailure()` を呼ぶ。
- **権限**: なし（permissionless・Protocol/任意が読める）。
- **事前条件（Checks）**: なし（防御は catch 側で行う）。
- **動作（Effects）**:
  1. `try IPriceFeed(source).fetchPrice()`
  2. successかつ有効価格 → `_lastGoodPrice` 更新。呼出元がBorrowerOperationsなら、JPY更新のprovenanceが無効または30h以上古い場合に `(price, true)` を返す。この制限だけではpauseを立てない。清算はsourceの30h+24h方針に従い、返済・担保追加だけの調整はこの関数を呼ばない
  3. revert が gas guard（`InsufficientGasForExternalCall`、ちょうど 4 バイト）→ `_bubbleIfGasError` が**そのまま再 revert**（shutdown しない・全体を revert）
  4. その他の revert / 無効価格 → `try borrowerOperations.shutdownFromOracleFailure()`。通常経路は `IPriceFeed(source).lastGoodPrice()` を試し、取得可かつ有効なら `_lastGoodPrice` を更新して返す。redemption 経路は `source.lastGoodPrice()` を読まない（この view は redemption 専用ではないため）ため、Proxy 自身の `_lastGoodRedemptionPrice` を返す。通常経路で source cache が bricked の場合は Proxy 自身の `_lastGoodPrice` を返す（permanent DoS 防止）。
- **revert / 早期 return**: gas guard revert（`InsufficientGasForExternalCall`・厳密 4 バイト）→ そのまま再 revert。
- **発火イベント**: shutdown 経路では upstream `borrowerOperations.shutdownFromOracleFailure()` 由来のイベント（本書は発火本体を持たない）。Proxy 側の shutdown 観測イベントは [ORCL-EVT-004](#11-イベント監視要件evt)。
- **設計上のポイント**:
  - **無効価格の判定**: `price == 0` または `price == type(uint256).max`。
  - **gas griefing 保護の透過**: `MainnetPriceFeedBase` は Chainlink 呼び出しがガス不足（OOG）で失敗したケースをオラクル障害と取り違えないよう、`gasleft() <= gasBefore / 64` のとき意図的に `InsufficientGasForExternalCall()` で revert する保護を持つ（§5）。Proxy の try/catch が**この保護 revert も無差別に shutdown 経路へ流す**と保護が Proxy 越しで実質無効化されるため、catch は revert データが `InsufficientGasForExternalCall` のセレクタと一致し**かつちょうど 4 バイト**のときだけ生 revert を再 revert する（`_bubbleIfGasError`）。それ以外は従来どおり shutdown 経路に流す（本物の障害の挙動は変わらない）。
  - **本物のオラクル障害との判別**: 本物の障害も Proxy には 4 バイトの `CallerNotPriceFeed()` 等として届く。長さでは gas guard と区別できないため判定は**セレクタ一致**で行い、長さは `== 4` に厳格化する（セレクタ前方一致＋追加データ付きの revert は再 revert しない）。これにより gas guard だけが透過され本物の障害は従来どおり shutdown する（[ORCL-SEC-002](#orcl-sec-002-gas-griefing-保護の透過の正確性)）。
  - **upstream へのコンパイル時結合**: 比較する `InsufficientGasForExternalCall` セレクタは `MainnetPriceFeedBase.InsufficientGasForExternalCall.selector` を直接参照してコンパイル時に upstream へ結合する（ローカルミラーを持たない）。upstream がこのエラーを rename / 削除すると本ファイルがコンパイル失敗するため、保護がサイレントに無効化されない（[ORCL-SEC-002](#orcl-sec-002-gas-griefing-保護の透過の正確性)）。
- **Verification**: unit（有効価格透過・無効価格 shutdown・source fetch brick で経路別 Proxy cache 返却・redemption fallback が `source.lastGoodPrice()` に潰れないこと）, fork（実 feed 障害シナリオ）, integration（gas guard 再 revert と本物障害の判別）。

#### ORCL-FR-005: fetchRedemptionPrice（redemption consumer 経路）

- **Type**: Functional ｜ **Source**: Liquity-v2-Core-Spec（Redemption）/ DF 設計根拠
- **シグネチャ**: `fetchRedemptionPrice() → (uint256 price, bool isShutdown)`
- **目的**: redemption 価格の取得を `fetchPrice` と**同じ try/catch 構造**で source の `fetchRedemptionPrice()` に委譲する。`fetchPrice` と並ぶ第 2 の consumer 経路であり、同等の障害透過・shutdown 代行・gas guard 透過を備える。
- **権限**: なし（permissionless）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**: sourceを先に読み、通常の失敗処理・gas guardを適用する。成功後もJPY更新のprovenanceが無効または30h以上古ければ、cacheを更新せず `(price, true)` を返す。この制限だけではpauseを立てず、新しいJPY更新後に解除される。pauseが別途立っている場合はOwnerのresumeも必要。urgent redemptionは別経路でsourceの有効性方針に従う。
- **revert / 早期 return**: gas guard revert（厳密 4 バイト）→ 再 revert。
- **発火イベント**: [ORCL-FR-004](#orcl-fr-004-fetchprice障害透過と-shutdown-代行) と同様。
- **設計上のポイント**: `fetchPrice` と `fetchRedemptionPrice` の**両 consumer 経路**に同一の防御を備える（片方だけ防御すると非対称な穴になる）。両経路に gas guard 透過と shutdown 代行を備えることが規範。
- **Verification**: unit（fetchPrice と同等の分岐）, integration（redemption 経路の障害透過）。

#### ORCL-FR-006: 所有権の 2 段階移転（transferOwnership / acceptOwnership）

- **Type**: Functional ｜ **Source**: OpenZeppelin `Ownable2Step`
- **シグネチャ**: `transferOwnership(address newOwner)` / `acceptOwnership()`
- **目的**: typo 等による誤移転を防ぐため、`transferOwnership(newOwner)` の後、新オーナーが `acceptOwnership()` を呼んで初めて所有権が確定する 2 段階移転。本番移行時に deployer EOA から governance / multisig へ**移管**する。
- **権限**: `transferOwnership` = Owner のみ／ `acceptOwnership` = pending owner のみ。
- **事前条件（Checks）**: `transferOwnership`: `caller == Owner`。`acceptOwnership`: `caller == pendingOwner`。
- **動作（Effects）**:
  1. `transferOwnership`: `pendingOwner = newOwner`（所有権は未移転）
  2. `acceptOwnership`: `owner = pendingOwner`、`pendingOwner` クリア
  3. OZ `OwnershipTransferStarted` / `OwnershipTransferred` を発火
- **revert / 早期 return**: 非 Owner の `transferOwnership` → revert；非 pendingOwner の `acceptOwnership` → revert。
- **発火イベント**: OZ `OwnershipTransferStarted(previousOwner, newOwner)` / `OwnershipTransferred(previousOwner, newOwner)`（[ORCL-EVT-005](#11-イベント監視要件evt)）。
- **設計上のポイント**: dToken（[DTKN-GOV-002](./dToken.md)）や Vault GOV 運用と整合する 2-step 方針（[ORCL-GOV-002](#orcl-gov-002-owner-移譲は-2-step)）。
- **Verification**: unit（2-step 確定・誤移転防止）, manual（本番移行構成レビュー）。

#### ORCL-FR-007: renounceOwnership（無効化）

- **Type**: Functional ｜ **Source**: JPY/USD 共通依存・source 差替 recovery path の維持
- **シグネチャ**: `renounceOwnership()`
- **目的**: 所有権放棄によって source 差替権限が永久に失われることを防ぐ。JPY/USD 共通依存・Chainlink deprecate・placeholder ブランチ有効化の recovery path を残すため、Owner は burn せず governance / multisig へ移譲する。
- **権限**: Owner（GOV / multisig）のみ。
- **事前条件（Checks）**: `caller == Owner`。
- **動作（Effects）**:
  1. 常に `RenounceOwnershipDisabled` で revert
  2. `owner` / `pendingOwner` / `proposedSource` / `sourceProposedAt` は変更しない
- **revert / 早期 return**: 非 Owner → revert。
- **発火イベント**: なし。
- **設計上のポイント**: 保留 proposal の取消は `cancelSourceProposal()`、保留 Owner 移譲の取消は `transferOwnership(address(0))` で明示的に行う。権限を分散化したい場合は `transferOwnership()` → `acceptOwnership()` で DAO / timelock / multisig へ移管する。
- **Verification**: unit（常に revert・Owner/source proposal/pendingOwner 不変）, manual（本番移管構成レビュー）。

### 6.B DF PriceFeed 実装（内側 source / 担保別オラクルパターン）

各 DF PriceFeed は §5 の二層構成で実装する。現行 branch map と deployment 値の正本は [Parameters](../../../Parameters.md) とする。Day-1 に実 feed を使うのは Branch 0 dwstETH（dwstETH composite・ORCL-FR-015）と Branch 1 dUSDC（Standard・ORCL-FR-010）だけで、Branch 2–7 は `PriceFeedPlaceholder`（ORCL-FR-008）で開始する。以下の BTC / sUSDS / XAUT の各 pattern は、将来 activation に向けた archived candidate research であり、active な deployment 要件ではない。

なお各 DF PriceFeed は、担保別 `_fetchPricePrimary()` で算出した market price（JPY 建て）に、**全担保共通で dToken backing 比を乗じる後段層（[ORCL-FR-014](#orcl-fr-014-dtoken-backing-peg-の反映全担保共通の後段層)）**を適用し、dToken の実質担保価値（market price × backing 比）を返す。

active な DF PriceFeed の constructor は初回 primary fetch 後に `priceSource == primary && lastGoodPrice != 0` を強制し、満たさなければ `InvalidInitialPrice` で deployment 全体を revert する。shared JPY provider が unhealthy な expiry episode 中で feed 自身がまだ BorrowerOperations に登録されていない場合も、shutdown call の catch によって zero-price deployment を通してはならない。fresh JPY round が provider の episode state を解除した後は同じ constructor が正常に成功する（[ORCL-INV-012](#8-不変条件inv)）。

本書が具体化するオラクルパターンと PriceFeed 実装（担保資産別）:

| Underlying（担保資産） | オラクルパターン | PriceFeed 実装 | 規定要件 |
| --- | --- | --- | --- |
| USDC（および WETH 等 direct collateral/USD feed を持つ候補） | Standard | `DFUSDCPriceFeed` / 資産固有 feed | ORCL-FR-010 |
| wstETH（dwstETH） | **dwstETH composite**（stETH/USD market × canonical rate / JPY/USD / backing ratio） | `DFWstETHPriceFeed` | ORCL-FR-015 |
| WBTC（archived candidate 例） | **Peg-monitored** | archived `DFWBTCPriceFeed` | ORCL-FR-011 |
| sUSDS（archived candidate 例） | **Composite rate** | archived `sUSDSPriceFeed` | ORCL-FR-012 |
| XAUT（将来候補） | **Composite peg** または同等の direct XAUT/USD market feed（現行 branch map への binding なし） | candidate 実装 | ORCL-FR-013 |
| Branch 2–7（activation 前） | Placeholder | `PriceFeedPlaceholder` | ORCL-FR-008 |

> ⚠️ 担保↔ブランチ割当・確定状況の正本は [Parameters](../../../Parameters.md)。担保別の Chainlink アドレス等の確定値は各 FR の表を参照（未確定は `要確認`）。

<a id="orcl-fr-010-standard-パターンweth--usdc--usdt"></a>

#### ORCL-FR-010: Standard パターン（USDC）

- **Type**: Functional ｜ **Source**: 再構築計画の採用方式 / Chainlink Coll/USD 直接フィード
- **シグネチャ**: `_fetchPricePrimary()`（`DFPriceFeedBase` 継承の各標準 feed。例: `DFUSDCPriceFeed`。archived candidate の feed は active source tree 外）
- **目的**: 担保/USD 直接フィードから JPY 建て価格を導出する。
- **権限**: なし（internal、Proxy 経由で読まれる）。
- **事前条件（Checks）**: `collUsdOracle` が staleness 内かつ `answer > 0`。
- **動作（Effects）**:
  1. `(collUsd, down1) = _getOracleAnswer(collUsdOracle)`（担保/USD・18 桁正規化済み）。`down1` なら `_shutDownAndSwitchToLastGoodPrice(collUsdOracle)`（終局 shutdown）
  2. `collJpy = _convertUsdPriceToJpyWithFreeze(collUsd)`。JPY レッグの障害時挙動は `ORCL-SEC-005`
  3. `lastGoodPrice = _applyBackingRatio(collJpy)`、`(price, false)` を返す
- **revert / 早期 return**: 担保レッグ障害は `lastGoodPrice` へ退避する。gas guard は再 revert する。
- **発火イベント**: `JpyRateFrozen` / `JpyRateUnfrozen`。
- **使用フィード**:

  | 担保 | Chainlink フィード（collUsdOracle） |
  | --- | --- |
  | USDC | USDC/USD `0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6` |
  | 全ブランチ共通 | JPY/USD `0xBcE206caE7f0ec07b545EddE332A47C2F75bbeb3`（jpyUsdOracle） |
- **Verification**: unit（担保レッグ shutdown 分岐・JPY レッグ soft-freeze・代用/回復/イベント）, fork（実 Chainlink での 18 桁正規化・JPY 換算）, integration。

<a id="orcl-fr-011-peg-monitored-パターンwbtcbtc-系"></a>

#### ORCL-FR-011: archived Peg-monitored candidate パターン（WBTC〔BTC 系〕）

- **Type**: Functional ｜ **Source**: 再構築計画 / Aave v3 WBTC/BTC × BTC/USD アダプター（業界標準）
- **シグネチャ**: `_fetchPricePrimary()` / `fetchRedemptionPrice()`（`DFWBTCPriceFeed`、`DFPriceFeedBase` 継承）
- **目的**: BTC wrapper の peg と BTC/USD を合成し、JPY 建て価格を導出する。
- **権限**: なし（internal）。
- **事前条件（Checks）**: `wbtcBtcOracle` / `collUsdOracle`（= BTC/USD）が staleness 内かつ `answer > 0`。
- **動作（Effects）**:
  1. Step 1: `(wbtcBtc, down1) = _getOracleAnswer(wbtcBtcOracle)`（WBTC/BTC ペグ監視）。`down1` なら shutdown
  2. Step 2: `(btcUsd, down2) = _getOracleAnswer(collUsdOracle)`（BTC/USD）。`down2` なら shutdown
  3. Step 3: `market = mulDiv(wbtcBtc, btcUsd, 1e18)`、`canonical = btcUsd`。通常の `fetchPrice()` は `min(market, canonical)` を使い、WBTC/BTC が 1 を上回るときは BTC 価格で上限を掛け、1 を下回るデペグは即時に下方反映する
  4. Step 4: `fetchRedemptionPrice()` は両者が `WBTC_BTC_DEVIATION_THRESHOLD`（2%）以内なら `max(market, canonical)` を使う。これは Liquity rETH/wstETH の redemption oracle arbitrage 緩和、および Asymmetry USDaf V2 audit fix と同型。閾値外では本物の WBTC デペグを隠さないため保守的な `min(market, canonical)` を使う
  5. Step 5: `wbtcJpy = _convertUsdPriceToJpyWithFreeze(wbtcUsd)`。JPY レッグの障害時挙動は `ORCL-SEC-005`
  6. `lastGoodPrice = _applyBackingRatio(wbtcJpy)`、`(price, false)` を返す
- **revert / 早期 return**: WBTC/BTC・BTC/USD レッグ障害は shutdown、gas guard は再 revert する。
- **発火イベント**: `JpyRateFrozen` / `JpyRateUnfrozen`。
- **使用フィード**:

  | # | レイヤー | Chainlink Address |
  | --- | --- | --- |
  | 1 | WBTC/BTC ペグ監視 | `0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23` |
  | 2 | BTC/USD | `0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c` |
  | 3 | JPY/USD（共通） | `0xBcE206caE7f0ec07b545EddE332A47C2F75bbeb3` |

  Peg Monitor が必要な理由（[ORCL-SEC-006](#orcl-sec-006-中央集権ラッパー担保のペグ監視)）:
  - **① Chainlink Ethereum Mainnet に WBTC/USD 直接フィードが存在しない**: WBTC の USD 建て価格を得る手段は合成（WBTC/BTC × BTC/USD）が唯一。他担保（WETH・各ステーブルコイン）は Coll/USD 直接フィードが存在するため Peg Monitor を必要としない。
  - **② WBTC は BitGo 社カストディの中央集権ラッパーで BTC との 1:1 ペグは保証されない**: BTC/USD を WBTC 価格として直接使用するとデペグ時に担保価値が過大評価され、不十分な担保での借入・清算不能を招く。WBTC/BTC Peg Monitor を挟むことでデペグ発生時に担保価値を正しく下方評価できる。
  - **③ 歴史的デペグ実績**: 2022 FTX 崩壊時に 0.985 まで乖離 / 2024 BiT Global・Justin Sun 問題で 0.98 まで乖離（Aave・MakerDAO が WBTC パラメータを引き下げ）。
  - **④ 業界標準への準拠**: Aave v3 も同等の複合アプローチ（WBTC/BTC × BTC/USD アダプター）を採用。BTC/USD を WBTC に直接使用する方式は監査で High/Medium 指摘が複数あり避けられている。
  - **⑤ Peg Monitor は Chainlink 単独**: WBTC/BTC ペグ監視は Chainlink フィードで、障害時は即 shutdown で保守的に動作する。
- **Verification**: unit（WBTC/BTC・BTC/USD の shutdown 分岐・JPY レッグ soft-freeze・合成計算・通常価格の canonical cap・redemption の閾値内 max 挙動）, fork（実 WBTC/BTC・BTC/USD）, integration。

<a id="orcl-fr-012-composite-rate-パターンsusdsyield-bearing"></a>

#### ORCL-FR-012: archived Composite rate candidate パターン（sUSDS〔Yield Bearing〕）

- **Type**: Functional ｜ **Source**: 再構築計画の採用方式 / sUSDS 用に pruning した upstream 由来 `CompositePriceFeed`
- **シグネチャ**: `_fetchPricePrimary()` ＋ `_getCanonicalRate()`（`sUSDSPriceFeed`、pruned `CompositePriceFeed` 継承）
- **目的**: sUSDS（Savings USDS。USDS を預けて利回りを得る yield-bearing トークン）の価値を **canonical rate（USDS per sUSDS）× USDS/USD** で sUSDS/USD を合成し、JPY 換算する。Liquity v2 の LST composite feed と同じ「USD アンカー × canonical rate」の考え方を使うが、現行実装では **USDS/USD × sUSDS の canonical rate** の primary 経路だけを残し、WSTETH/RETH 用 LST secondary fallback は削除済み。
- **権限**: なし（internal）。
- **事前条件（Checks）**: `collUsdOracle`（= USDS/USD）が staleness 内かつ `answer > 0`；canonical rate が取得可能。
- **動作（Effects）**:
  1. `(usdsUsd, down1) = _getOracleAnswer(collUsdOracle)`（USDS/USD・18 桁正規化済み）。`down1` なら shutdown
  2. `(usdsPerSusds, rateDown) = _getCanonicalRate()`（USDS per sUSDS・18 桁）。`rateDown` なら `_shutDownAndSwitchToLastGoodPrice(rateProviderAddress)`
  3. `susdsUsd = mulDiv(usdsUsd, usdsPerSusds, 1e18)`（sUSDS/USD・18 桁、floor）
  4. `susdsJpy = _convertUsdPriceToJpyWithFreeze(susdsUsd)`。JPY レッグの障害時挙動は `ORCL-SEC-005`
  5. `lastGoodPrice = _applyBackingRatio(susdsJpy)`、`(price, false)` を返す
- **revert / 早期 return**: canonical rate または USD アンカー取得失敗時は `lastGoodPrice` へ退避する。gas guard は再 revert する。
- **発火イベント**: `JpyRateFrozen` / `JpyRateUnfrozen`。
- **設計上のポイント**:
  - canonical rate は Chainlink ではなく **sUSDS コントラクト（`0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD`、rate provider）から直接取得**する。sUSDS は ERC-4626 準拠のため `convertToAssets(1e18)`（= 1 sUSDS あたりの USDS、18 桁）が canonical rate になる（wstETH の `stEthPerToken()` に相当。`_getCanonicalRate()` がこれを呼ぶ）。constructor は rate provider の `asset()` を読み、原資産 contract が存在し、sUSDS と `asset()` 側の `decimals()` がともに 18 であることを検証する。Chainlink フィードではないため staleness 概念は無い。
  - **スケール**: `usdsUsd` / `usdsPerSusds` / `susdsUsd` はいずれも 18 桁。生 Chainlink（8 桁）は `_getOracleAnswer` が `×1e10` で 18 桁に正規化済み（[§3.5 前提](#35-前提)）。canonical rate（USDS per sUSDS）も 18 桁スケール（例 `1.05e18` = 1 sUSDS あたり 1.05 USDS）。生 8 桁のまま割ると `1e10` 倍ズレる。
  - **`ETHUSDxCanonical` 非発生**: sUSDS は USD ソースが USDS/USD 単一で、wstETH のような別系統の市場フィードを持たないため、[§12](#12-失敗時異常系挙動err) の `ETHUSDxCanonical`（市場フィード障害時に「ベース USD × canonical rate」へ退避する状態）は本フィードでは発生しない。production `CompositePriceFeed` はこの未使用 LST secondary fallback を削除済みで、障害時は `lastGoodPrice` に退避する。
  - 使用するオラクル（mainnet、staleness は [ORCL-TBD-001](#orcl-tbd-001)・確定値は [Parameters](../../../Parameters.md)）:

    | レイヤー | ソース | アドレス / 状況 |
    | --- | --- | --- |
    | USDS/USD（USD アンカー） | Chainlink | ✅ `0xfF30586cD0F29eD462364C7e81375FC0C71219b1`（EACAggregatorProxy。Compound v3〔comet〕の USDS market・旧実装 `USDSPriceFeed.sol` も同アドレスを使用） |
    | sUSDS canonical rate（USDS per sUSDS） | sUSDS コントラクト `0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD`（ERC-4626 `convertToAssets(1e18)`、非 Chainlink） | ✅ 確認済 |
    | JPY/USD（共通） | Chainlink | `0xBcE206caE7f0ec07b545EddE332A47C2F75bbeb3` |

    > 補足: USDS は DAI の 1:1 後継のため、将来 USDS/USD が deprecate された場合は DAI/USD（`0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9`）への差替も `PriceFeedProxy` 経由で可能（フォールバック選択肢）。最終チェックサムは Chainlink 公式 addresses ページで照合する。
  - **Peg-monitored との違い**: Peg-monitored（[ORCL-FR-011](#orcl-fr-011-peg-monitored-パターンwbtcbtc-系) / [ORCL-FR-013](#orcl-fr-013-xautgold-xautxau-ペグ監視必須day-1-standardoff-chainフィード提供後-composite-peg-昇格)）は wrapper と原資産の**ペグ乖離を検知して保守評価**するための監視フィード（WBTC/BTC・XAUT/XAU 等）を挟むが、Composite rate は**正当に増加する交換レート**を canonical rate として使う（乖離検知ではなく利回りの反映）。
- **Verification**: unit（USDS/USD・canonical rate の shutdown 分岐・JPY の soft-freeze 分岐・合成計算）, fork（sUSDS `convertToAssets`・実 USDS/USD）, integration。

<a id="orcl-fr-013-xautgold-xautxau-ペグ監視必須day-1-standardoff-chainフィード提供後-composite-peg-昇格"></a>

#### ORCL-FR-013: XAUT 候補の Composite peg pattern

- **Type**: Functional ｜ **Source**: [ORCL-SEC-006](#orcl-sec-006-中央集権ラッパー担保のペグ監視)
- **目的**: XAUT を将来候補として評価する場合、XAUT/XAU または direct XAUT/USD market price により downside depeg を on-chain 価格へ反映する。
- **計算**: `min(1, XAUT/XAU) × XAU/USD ÷ JPY/USD × min(1, backingRatio)`、または同等の direct XAUT/USD market price を使う。
- **Failure policy**: market / peg / XAU leg の失敗は branch oracle failure、JPY/USD は bounded soft-freeze とする。
- **Activation gate**: feed 品質、market hours、staleness、liquidation liquidity、cap、monitoring / incident runbook を一括承認する。XAU/USD 単独または off-chain monitoring だけでは activation しない。
- **Verification**: unit（peg cap・各 failure）, fork（採用 feed）, integration（backing ratio・JPY soft-freeze）, manual（liquidity / monitoring）。

#### ORCL-FR-014: dToken backing peg の反映（全担保共通の後段層）

- **Type**: Functional ｜ **Source**: 旧 CollateralVault「dToken 担保価値のオラクル反映（Strategy 毀損時）」TODO の正式化 / CollateralVault 会計（`A` vs `L_effective`、[CollateralVault 要件定義](./CollateralVault.md) `VAULT-INV-001`）
- **シグネチャ**: 各担保 `_fetchPricePrimary()` の**最終段**で `_applyBackingRatio(uint256 collJpy)` を呼ぶ。ロジック本体は共有 `JpyFreezeLib` にあり、標準・peg 型の `DFPriceFeedBase` と composite 型（`sUSDSPriceFeed` / `DFWstETHPriceFeed`）は state 保持と配線のみを持つ。pricing 用 backing 比は `CollateralVault.backingRatioForPricing() → (uint256 ratio, bool available)`（ratio は1e18 基準・**下方専用** `<= 1e18`、定義は [CollateralVault 要件定義](./CollateralVault.md) `VAULT-FR-016`）。
- **目的**: dToken は Underlying 元本の 1:1 請求権だが、運用先 Strategy のハッキング・bad debt・slashing で **Underlying 実保有が元本を下回る**と dToken は Underlying に対してデペグする。market price（担保/JPY）だけを返すと backing 毀損が担保評価に反映されず、**担保過大評価 → 過剰借入 → JPYdf の Bad Debt** を招く。これを防ぐため market price に **backing 比（裏付け率）** を乗じ、dToken の実質担保価値を返す。
- **なぜ各継承系の最終段に置くか**: composite 型（sUSDS / dwstETH）は `CompositePriceFeed` 継承系で `DFPriceFeedBase` と別経路（[ORCL-FR-012](#orcl-fr-012-composite-rate-パターンsusdsyield-bearing) / ORCL-FR-015）。換算・backing のロジック本体は共有 `JpyFreezeLib` にあり、各 composite feed はその state だけをローカルに持つ（ロジックの重複なし）。実際の JPY cache / freeze state は `JpyUsdRateProvider` だけに置く。Proxy の責務は変えない。
- **権限**: なし（internal、Proxy 経由で読まれる）。
- **事前条件（Checks）**: source（実 PriceFeed）が対応 `CollateralVault` を参照（constructor で設定、feed↔Vault 1対1。[§5](#5-インターフェース仕様)）。担保別 `_fetchPricePrimary()` が market price `collJpy`（JPY 建て・18dec）を算出済み。
- **動作（Effects）**（`_fetchPricePrimary()` の最終段、`lastGoodPrice` 記録の直前）:
  1. 担保別パターン（[ORCL-FR-010](#orcl-fr-010-standard-パターンweth--usdc--usdt)〜[ORCL-FR-013](#orcl-fr-013-xautgold-xautxau-ペグ監視必須day-1-standardoff-chainフィード提供後-composite-peg-昇格)）で market price `collJpy` を算出
  2. `try CollateralVault.backingRatioForPricing() → (r, available)`: `available == true` なら `r` をクランプ（`> 1e18` は `1e18` キャップ／実測 `== 0` は `1`〔1 wei〕床）して `lastGoodBacking = r`。`available == false` または通常の revert（catch）時は standard oracle failure path（`lastGoodPrice` shutdown）。gas guard revert は再 revert（shutdown しない）
  3. `dTokenJpy = mulDiv(collJpy, r, 1e18)`（floor）
  4. `lastGoodPrice = dTokenJpy` を記録し `(dTokenJpy, false)` を返す
  5. 償還経路（source の `fetchRedemptionPrice` 系）も同一処理（**両 consumer 経路に対称適用**＝[ORCL-SEC-004](#orcl-sec-004-両-consumer-経路の対称な防御)）
- **revert / フォールバック**: `backingRatioForPricing()` の `available == false` または通常 revert（catch）時は `lastGoodBacking` で素通しせず、標準の oracle failure として `lastGoodPrice` shutdown に入る。理由は、backing read failure 中に Strategy 毀損が進むと古い backing で担保過大評価が残るため。全 Strategy を評価できた実測 0 だけは `1`〔1 wei〕床へ進み、完全な backing 喪失を stale fallback ではなく near-zero 価格として表現する。評価不能を実測 0 とみなして価格へ乗算してはならない。取得成功時の異常値はクランプで処理する（`> 1e18`→`1e18` キャップ）。gas-starved call は `InsufficientGasForExternalCall` を再 revert し、`PriceFeedProxy` も再 revert するため、低 gas 呼び出しを oracle failure と誤認して shutdown しない。Strategy 単位の `estimatedTotalUnderlying()` / `principal()` read failure は Vault 内の bounded last-good cache（[CollateralVault 要件定義](./CollateralVault.md) `VAULT-FR-013`）で処理し、fresh cache も無い場合は availability=false で Oracle へ伝播する。placeholder（`underlying==0` → `L_effective==0` → `(1e18,true)`）は `PriceFeedPlaceholder`（[ORCL-FR-008](#orcl-fr-008-placeholder-ブランチの初期-source-pricefeedplaceholder)）の `(1e18, false)` と矛盾しない。
- **設計上のポイント**:
  - **`CompositePriceFeed` と同型**: 「market price × rate」合成の rate を backing 比に置換（[ORCL-FR-012](#orcl-fr-012-composite-rate-パターンsusdsyield-bearing) の canonical rate に相当）。**コア無改変を維持**（コアは backing の存在を知らない）。
  - **二重防御（ライブ＋確定）**: backing は `totalUnderlying()` 由来のライブ値。est が損失を反映すれば自動下方、GOV の `writeoffStrategyPrincipal`（[CollateralVault 要件定義](./CollateralVault.md) `VAULT-FR-009`）で principal が下がれば `A` も下がり恒久確定する。live valuation が取得不能なときだけ、Vault 側の Strategy 単位 fresh cache が一時的な外部 view failure を吸収する。
  - **上振れキャップ（`min(1e18, …)`）**: 運用益で `A > L_effective` でも backing は `1e18` 止まり（dToken が利回りを持たない＝運用益は Treasury 帰属の仕様と整合）。
  - **深刻毀損時 = 価格下落のみ**: live backing 比で price が下落し、既存の清算 / TCR<SCR branch shutdown / Urgent Redemptions に処理を委ねる（**backing 専用の shutdown 閾値は設けない**）。実損の global smoothing は Day-1 では行わない。
  - **即時反映は確定損失のみ（ADR-006）**: backing の即時下方反映・平滑化なしの方針は[Architecture Decision Records](../architecture/Architecture-Decision-Records.md#adr-006)。反映対象は確定損失（市場 depeg・Strategy 評価額に出る損失）に限り、一時的流動性不足は損失でなく backing を下げない（writeoff しない）。会計に現れない外部 deficit は回収後の残差のみ `writeoffStrategyPrincipal` で確定する。
  - **Stability Pool は補填者ではない**: Stability Pool は price 低下後に unsafe になった Trove の清算を処理する。dToken backing の repair は Vault 側の Strategy 回収・`writeoffStrategyPrincipal`・`backstopDeposit`（protected reserve 入金）/ `releaseBackstopToBuffer`（償還流動性への明示解放、[CollateralVault 要件定義](./CollateralVault.md) `VAULT-FR-017`）で行い、SP depositors に Strategy loss を直接負わせない。
  - **`lastGoodBacking` は market price の `lastGoodPrice` とは別管理**（market 健全値と backing 健全値を独立に保持）。
  - **スケール厳守**: `mulDiv(collJpy, r, 1e18)` で `collJpy`(18dec) × `r`(1e18 基準) / 1e18 = 18dec を維持し、丸めは floor。
- **Verification**: unit（`min` キャップ・`L_effective==0` で `1e18`・両 consumer 対称・`backingRatio()` revert で shutdown）, fork（実 Vault backing 値での乗算）, integration（Strategy 毀損 → `backingRatio` 低下 → dToken 担保価値下落 → コア清算が作動）。

#### ORCL-FR-015: dwstETH の market / canonical composite

- **Type**: Functional ｜ **Source**: wstETH PriceFeed 方針（Owner Decision）/ Day-1 launch gate / `DFWstETHPriceFeed`
- **目的**: stETH/USD market の変動（下方 depeg を含む）、canonical rate 経由の slashing / negative rebase、JPY/USD、dToken backing 毀損を、dwstETH の借入・清算・redemption 価格に反映する。
- **価格（両 consumer 経路共通）**:

  ```text
  stETH/USD market（Chainlink 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8、
                    staleness = PRM-ORACLE-003）
  × stETH per wstETH canonical rate（wstETH.stEthPerToken()、担保トークン自身
    から直読み・staleness 概念なし）
  ÷ JPY/USD（共有 JpyUsdRateProvider）
  × min(1, dToken backing ratio)
  ```

  canonical rate の低下は slashing / negative rebase として価格に反映する。wstETH の USD source はこの 1 本のみで market / canonical の乖離裁定が存在しないため、`fetchRedemptionPrice` も同一価格を使う。
- **実装**: `DFWstETHPriceFeed` は pruned `CompositePriceFeed` の canonical-rate 基底（`sUSDSPriceFeed` と同じ親）を継承し、upstream の `ethUsdOracle` slot を stETH/USD として再利用する。JPY 換算 / freeze / backing のロジックは共有 `JpyFreezeLib` で、feed 側は state のみ保持する。constructor は rate provider（wstETH token）の 18 decimals と nonzero rate を検証し、初期価格を取得する。
- **Failure policy**: stETH/USD の取得失敗・stale・無効値、canonical rate の取得失敗（revert / zero。gas-griefing OOG は `InsufficientGasForExternalCall` を再 revert）、backing ratio の取得失敗は branch oracle failure（`lastGoodPrice` shutdown）。JPY/USD は ORCL-SEC-005 の bounded soft-freeze を使い、freeze 期限超過時に branch shutdown へ移行する。
- **会計境界**: canonical rate 上昇は wstETH の native staking 増価として borrower の担保価値に残し、Strategy profit として sweep しない。外部 Strategy による wstETH 数量増加と分けて評価する。
- **upstream との差分（設計判断）**: 通常価格の合成（stETH/USD × canonical）は upstream `WSTETHPriceFeed` と同じだが、upstream が stETH/USD 障害時に shutdown 後も `ETHUSDxCanonical`（ETH/USD × canonical を `lastGoodPrice` との min ラチェットで供給する fallback）で urgent redemption 価格を追従させるのに対し、本要件は `ETHUSDxCanonical` を採用しない — 全 pattern を `primary` / `lastGoodPrice` の 2 状態に揃え（ORCL-INV-010）、障害 branch が canonical・JPY/USD・backing の依存を読み続ける状態を作らない。帰結として、stETH/USD 障害で shutdown した後の urgent redemption は凍結 `lastGoodPrice`（JPY 建て）で実行され、実勢への追従は `PriceFeedProxy` の source 差替（12h timelock・`confirmSourceEmergency` でも短縮不可）まで回復しない。この凍結窓は upstream の WETH branch（ETH/USD 障害時）と同等であり、受容する。
- **Day-1 launch gate**: 実 feed address / heartbeat / staleness、canonical rate source、fork / integration / invariant test、monitoring、frontend 表示を **mainnet launch 前に**確定・完了する（launch blocker）。非JPY stalenessの候補値と判断根拠は [decision record](../../launch/decisions/non-jpy-oracle-staleness-threshold-rationale.md)、承認済み値は [Day1 Parameter Manifest](../../../Parameters.md)、wstETHのimmutable値適合と清算capacityは [Day1 Parameter Decision](../../launch/decisions/Day1-Parameter-Decision.md) §4、public launch scope / SP requirementは [Mainnet Launch Product Decision Record](../../launch/decisions/Mainnet-Launch-Product-Decision-Record.md) を正本とする。
- **Verification**: unit（composite 算出・各 failure）, fork（stETH/USD・canonical rate）, integration（backing ratio・JPY soft-freeze・shutdown）, invariant（価格スケール・両 consumer 経路対称）。

### 6.C placeholder ブランチと Post-launch 確定

dTokenアプローチによりDay-1時点で8slotを登録する。Branch 0–1だけが実sourceを持つ。Branch 2–7はUnderlying未binding、`mintCap = 0`、placeholder sourceのinert構成とし、[Inert Branch Activation Runbook](../../operations/runbooks/Inert-Branch-Activation-Runbook.md)完了後だけ実sourceへ差し替える。

#### ORCL-FR-008: placeholder ブランチの初期 source（PriceFeedPlaceholder）

- **Type**: Functional ｜ **Source**: dToken placeholder ブランチ運用 / 再構築計画
- **シグネチャ**: `PriceFeedPlaceholder.fetchPrice() → (1e18, false)` ／ `fetchRedemptionPrice() → (1e18, false)`（external view）
- **目的**: Underlying 未確定ブランチの Proxy アドレスを Day 1 に固定するため、初期 source に **常に `(1e18, false)` を返す stub** を設定する。`PriceFeedProxy` は constructor で `source == address(0)` を `InvalidSource` で拒否するため、`address(0)` ではなく非ゼロ価格を返す stub を渡す。
- **権限**: なし（external view）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**: 常に `(1e18, false)` を返す（価格は健全に見えるが操作は Vault / dToken 層で多重ガードされる）。
- **revert / 早期 return**: なし。
- **発火イベント**: なし。
- **設計上のポイント**: `1e18` は無効価格判定（`price == 0` または `type(uint256).max`）を満たさないため **branch shutdown を誘発しない**。価格が健全に見えても、以下の多重ガードにより placeholder ブランチは実質的に操作不能（[ORCL-SEC-007](#orcl-sec-007-placeholder-ブランチの操作不能性多重ガード)）:
  1. [CollateralVault](./CollateralVault.md) は `underlying = address(0)` で初期化され、`deposit()` / `redeem()` / `redeemWithPermit()` は `UnderlyingNotSet` で revert
  2. [CollateralVault](./CollateralVault.md) のユーザー価値フローは `dToken.underlying() == vault.underlying()` も要求し、不一致（dToken 未設定を含む）は `UnderlyingMismatch` で revert
  3. [dToken](./dToken.md) は `TokenInfo` 未設定（`_decimalMultiplier == 0`）のため `convertToDToken` / `convertToUnderlying` は `TokenInfoNotSet` で revert（[DTKN-FR-003](./dToken.md)）
  4. `dToken.setCap(0)` を deploy 時に明示設定（[DTKN-FR-006](./dToken.md)）
- **Verification**: unit（常に `(1e18, false)`・shutdown 非誘発）, integration（Vault/dToken 多重ガードで操作不能）。

#### ORCL-FR-009: Post-launch 未確定ブランチの Underlying 確定フロー

- **Type**: Functional ｜ **Source**: 再構築計画（Day 2 有効化）/ dToken-first 順序
- **シグネチャ**: GOV による 5 コール + cap 事前確認（`dToken.setTokenInfo` / `vault.setUnderlying` / `priceFeedProxy.proposeSource` → `confirmSource` / `confirmSourceEmergency` / `dToken.setCap`）
- **目的**: placeholder ブランチを Day 2 に GOV 権限のコールだけで有効化する。**プロトコルコア・dToken・Proxy の再デプロイは不要**。
- **権限**: GOV（dToken Owner / Vault Owner / `PriceFeedProxy` Owner。本番は multisig）。
- **事前条件（Checks）**: 各コールの前提（`dToken.totalSupply() == 0` / cap が 0 / `dToken.underlying() == token`）を満たすこと。
- **動作（Effects）**（ブランチごと、GOV による 5 コール + cap 事前確認）:
  1. **Underlying を決定**し、対応する Chainlink フィードとオラクルパターン（Standard / Composite rate / Peg-monitored / Composite peg / 固定値 等、§6.B）を確定。実 PriceFeed をデプロイ（標準・peg 型は `DFPriceFeedBase`、composite rate 型は sUSDS 用に pruning した `CompositePriceFeed` ＋ DF JPY 層を継承。必要なら WBTC 例のように追加 Oracle を持たせる）
  2. **cap が 0 のままか確認**する。0 でなければ有効化前に `dToken.setCap(0)` で mint を閉じ、手順中に新規入金が発生しない状態を維持する
  3. `dToken.setTokenInfo(name, symbol, token)` — dToken を先に実 Underlying へ one-shot 設定し、decimals / name / symbol を確定（`totalSupply() == 0` が必要）
  4. `vault.setUnderlying(token)` — placeholder の `underlying`(address(0)) に実トークンを one-shot 設定。`dToken.underlying() != token` の場合は `UnderlyingMismatch` で revert
  5. `priceFeedProxy.proposeSource(realFeed)` → **12h timelock** → `confirmSource()` / `confirmSourceEmergency()` — `PriceFeedPlaceholder` から実 PriceFeed へ差替。新旧価格差が guard 内なら通常 `confirmSource()`、placeholder sentinel から実価格への差替で guard を越える場合は `confirmSourceEmergency()` を使う（[ORCL-FR-001](#orcl-fr-001-source-差替の提案proposesource) / [ORCL-FR-002](#orcl-fr-002-source-差替の確定confirmsource)）
  6. `dToken.setCap(N)` — 上限を設定し入金を解放
- **revert / 早期 return**: dToken-first 順序違反（`vault.setUnderlying` を `dToken.setTokenInfo` より先に実行）→ dToken 側 Underlying がまだ `address(0)` のため `UnderlyingMismatch` で revert。
- **発火イベント**: 各コール由来（`TokenInfoSet` / `SourceUpdated` 等）。
- **設計上のポイント**:
  - **dToken-first 順序**: この順序により、Vault が保管する資産と dToken の decimals / valuation が分岐する事故を防ぐ。
  - **想定パターン（担保カテゴリ別。どのブランチがどのカテゴリかは [Parameters](../../../Parameters.md) を正本とする）**:

    | 担保カテゴリ | 想定パターン |
    | --- | --- |
    | USD Stablecoin（RWA / 米国債を含む） | Standard（[ORCL-FR-010](#orcl-fr-010-standard-パターンweth--usdc--usdt)） |
    | Yield Bearing（利回り付き USD ステーブル系） | Composite rate（[ORCL-FR-012](#orcl-fr-012-composite-rate-パターンsusdsyield-bearing)、sUSDS 例に準ずる。canonical rate × 原資産/USD） |
    | BTC 系 | Peg-monitored（[ORCL-FR-011](#orcl-fr-011-peg-monitored-パターンwbtcbtc-系)、WBTC 例に準ずる） |
    | GOLD（金）系 | wrapper / market depeg を on-chain で反映する Composite peg（[ORCL-FR-013](#orcl-fr-013-xautgold-xautxau-ペグ監視必須day-1-standardoff-chainフィード提供後-composite-peg-昇格)） |
    | JPY Stablecoin | Chainlink 対応フィード提供時は Standard 類似。未提供時は固定値ベース（例: 1:1 固定フィード）+ 将来差替方式。固定フィードはデペグを検知できないため、清算パラメータを他ステーブルコインより保守的に設定する |
  - `proposeSource()` → 12h timelock → `confirmSource()` により、プロトコル再デプロイなしで以下が可能: Chainlink フィードの deprecate 時に新フィードを使う PriceFeed ごと差替 / 担保トークンの変更（例: USDT → USDC、BTC ラッパーの変更）/ 未確定ブランチの Day 2 有効化。
  - 全 8 ブランチに `PriceFeedProxy` を 1 つずつデプロイし、確定済みブランチは実 PriceFeed を、未確定ブランチは `PriceFeedPlaceholder` を初期 source に設定する（`DeployLiquity2.s.sol` の `_deployPriceFeed` が feed を生成し、`new PriceFeedProxy(feed, deployer, borrowerOperations)` でラップ）。
- **Verification**: unit（dToken-first 順序の強制・各コールの前提）, integration（Day 2 有効化フロー全体）, manual（GOV 手順書レビュー）。

---

## 7. 状態変数・会計モデル

オラクルレイヤーは価値の会計（principal/profit/buffer）を持たない。保持するのは価格ソースの参照と障害時フォールバック用の最終健全価格、および dToken backing 比の最終健全値（`lastGoodBacking`）のみ。backing 比そのものの算出・会計は [CollateralVault](./CollateralVault.md)（`VAULT-FR-016`）が司り、オラクルはそれを**読むだけ**（[ORCL-FR-014](#orcl-fr-014-dtoken-backing-peg-の反映全担保共通の後段層)）。

**PriceFeedProxy（外側固定参照）**

| 変数 | 型 | 説明 | 確定 |
| --- | --- | --- | --- |
| `source` | `address` | 委譲先の実 PriceFeed。差替可能 | constructor（非ゼロ）/ `confirmSource` で更新 |
| 保留 source proposal | `(address newSource, uint256 readyAt)` | `proposeSource` で記録・`confirmSource`/`cancelSourceProposal` でクリア | `proposeSource` |
| `_lastGoodPrice` | `uint256` | Proxy 自己防衛キャッシュ（通常価格経路）。source brick 時に `fetchPrice` が返す（permanent DoS 防止） | constructor / `fetchPrice` / `confirmSource` で更新 |
| `_lastGoodRedemptionPrice` | `uint256` | Proxy 自己防衛キャッシュ（redemption 価格経路）。WBTC 等で通常価格と redemption 価格が分岐しても、source brick 時に `fetchRedemptionPrice` が通常価格 cache へ潰れないようにする | constructor / `fetchRedemptionPrice` / `confirmSource` で更新 |
| `TIMELOCK_DELAY` | `constant` | `24 hours` | 定数 |
| `owner` / `pendingOwner` | `address` | `Ownable2Step`。2-step 移転。`renounceOwnership` は無効化 | constructor / 移転 |
| `borrowerOperations` | `address` | shutdown 代行先（`shutdownFromOracleFailure()`） | constructor |

**DF PriceFeed 実装（内側 source）**

| 変数 | 型 | 帰属 | 説明 |
| --- | --- | --- | --- |
| `ethUsdOracle`（= 担保/USD。本書擬似コード `collUsdOracle`） | `Oracle{aggregator, stalenessThreshold, decimals}` | 🔵 upstream | 担保/USD の Chainlink アグリゲータ。`decimals == 8` を upstream constructor で `assert`。ストレージ名は upstream のまま（rename も「編集」になるため） |
| `jpyUsdRateProvider` | `address immutable` | 🟢 DF（全 active feed source） | 全 branch で同一の provider address。feed source は JPY cache / freeze state を重複保持しない |
| `jpyUsdOracle` / `lastGoodJpyRate` / `lastGoodJpyUpdatedAt` / `jpyFrozenSince` / `jpyFreezeExpired` | provider state | 🟢 DF（`JpyUsdRateProvider`） | JPY/USD binding、cache provenance、freeze 起点、当該 freeze episode の expiry 判定を全 branch で共有。fresh response は episode state を解除する。constructor は fresh な8桁 response を要求 |
| `wbtcBtcOracle` | `Oracle{...}` | 🟢 DF（`DFWBTCPriceFeed`） | WBTC/BTC ペグ監視（Peg-monitored 固有の追加ストレージ） |
| `xautXauOracle` | `Oracle{...}` | 🟢 DF（将来 `DFXAUTPriceFeed`） | XAUT/XAU ペグ監視（Composite peg 昇格時に追加） |
| `rateProviderAddress` | `address immutable` | 🔵 upstream 由来（pruned `CompositePriceFeed`） | canonical rate 取得先（sUSDS は `0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD`） |
| `priceSource` | `enum PriceSource` | 🔵 upstream | `primary` / `ETHUSDxCanonical` / `lastGoodPrice` の enum。production feed は `primary` / `lastGoodPrice` のみを使う（[§12](#12-失敗時異常系挙動err)） |
| `lastGoodPrice` | `uint256` | 🔵 upstream | feed 単位の最終健全価格（JPY 建て・**backing 乗算後の dToken 担保価値**で記録。`_fetchPricePrimary` 内で backing を適用するため。[ORCL-FR-014](#orcl-fr-014-dtoken-backing-peg-の反映全担保共通の後段層)） |
| `collateralVault` | `address immutable` | 🟢 DF（backing 乗算層・各 feed 実装内） | backing 比の参照先 CollateralVault（constructor で設定、feed↔Vault 1対1。[ORCL-FR-014](#orcl-fr-014-dtoken-backing-peg-の反映全担保共通の後段層)） |
| `lastGoodBacking` | `uint256` | 🟢 DF（backing 乗算層・各 feed 実装内） | backing 比の最終健全値（初期 `1e18`・available な pricing read でのみ更新）。監視・検証用に保持するが、call failure または `available == false` 時の価格継続には使わない。`lastGoodPrice` とは別管理 |

**会計モデル**: オラクルレイヤーは価格（JPY 建て）の供給のみを司り、担保・債務の会計は持たない。価格は常に「担保/USD（upstream 基底）→ JPY 換算（DF 基底）→ dToken backing 比の乗算（各 feed 実装内の backing 乗算層、[ORCL-FR-014](#orcl-fr-014-dtoken-backing-peg-の反映全担保共通の後段層)）」で導出し、`lastGoodPrice`（JPY 建て・backing 乗算後）に記録する。`A < L_effective` の判定主体は Oracle ではなく CollateralVault / Strategy の Underlying 建て会計であり、Oracle は available な `backingRatioForPricing()` を市場価格へ乗じるだけ。backing 比は CollateralVault から**読むのみ**（会計は Vault 側）で、read failure または valuation unavailable 時は、過大評価継続と取得不能=全損の誤分類を避けるため標準 oracle failure path に入る。Proxy は `_lastGoodPrice` / `_lastGoodRedemptionPrice`（JPY 建て）を自己防衛キャッシュとして持ち、source brick 時の permanent DoS と consumer 経路間の cache 混線を防ぐ。

---

## 8. 不変条件（INV）

| ID | 不変条件 | 検証 |
| --- | --- | --- |
| ORCL-INV-001 | Protocol から見た `PriceFeedProxy` のアドレスは不変（コアのオラクル参照先は固定）。差し替わるのは Proxy 裏の `source` のみ | manual / integration |
| ORCL-INV-002 | `source` の差替は `proposeSource` → 12h timelock 経過 → `confirmSource` / `confirmSourceEmergency` を経たときのみ成立する（即時差替は不可） | unit / invariant |
| ORCL-INV-003 | `confirmSource` は `proposedAt + TIMELOCK_DELAY` 以降のみ成功する | unit |
| ORCL-INV-004 | `source` は常に非ゼロアドレス（constructor / `proposeSource` で `address(0)` を `InvalidSource` 拒否） | unit |
| ORCL-INV-005 | `fetchPrice` / `fetchRedemptionPrice` は gas guard revert（`InsufficientGasForExternalCall`・厳密 4 バイト・セレクタ一致）のみ再 revert し、それ以外の revert / 無効価格は shutdown 経路へ流す | unit / integration |
| ORCL-INV-006 | source が brick（`lastGoodPrice()` も取得不能）でも Proxy は自身の経路別 cache（`_lastGoodPrice` / `_lastGoodRedemptionPrice`）を返し、価格取得は permanent DoS にならない。通常価格と redemption 価格が分岐する source でも、source brick 時に redemption 経路が通常価格 cache へ潰れない | unit |
| ORCL-INV-007 | 全担保価格は JPY 建てで導出される（`collJpy = mulDiv(collUsd, 1e18, jpyUsdRate)`、floor）。`collUsd` / `jpyUsdRate` はいずれも 18 桁正規化済み | unit / fork |
| ORCL-INV-008 | upstream 価格取得基底との差分は明示管理する。`MainnetPriceFeedBase` の差分は Chainlink の不完全 round（`roundId == 0` / `answeredInRound < roundId`）と無効 timestamp（`updatedAt == 0` / 未来時刻）を無効化する検証硬化、および通常の `_getOracleAnswer` semantics を変えず response の `updatedAt` を既存結果とともに返す internal provenance helper に限る。`CompositePriceFeed` は sUSDS の primary → `lastGoodPrice` 経路だけを残し、未使用の WSTETH/RETH 用 LST secondary fallback を削除済みであることを static diff で確認する。JPY 換算・backing 乗算は DF ファイルに閉じる | manual / static diff review / unit |
| ORCL-INV-009 | placeholder ブランチは `PriceFeedPlaceholder`（常に `(1e18, false)`）を source とし、branch shutdown を誘発せず、かつ Vault / dToken の多重ガードで操作不能 | unit / integration |
| ORCL-INV-010 | 全 production pattern は `primary` と `lastGoodPrice` の 2 状態のみを使い、`ETHUSDxCanonical` を使わない。JPY レッグは `ORCL-SEC-005` に従う | unit |
| ORCL-INV-011 | dToken backing 比は下方専用 `backingRatio ∈ (0, 1e18]`（健全時 `== 1e18`）で、全担保価格に `dTokenJpy = mulDiv(collJpy, backingRatio, 1e18)`（floor）として両 consumer 対称に適用される。pricing view の `available == false` または read failure 時は `lastGoodBacking` で素通しせず shutdown、gas guard revert は再 revert する。全 Strategy を評価できた実測 0 のみ 1 wei floor を適用する（[ORCL-FR-014](#orcl-fr-014-dtoken-backing-peg-の反映全担保共通の後段層)） | unit / fork |
| ORCL-INV-012 | active DF PriceFeed の constructor は初回 fetch 後に `priceSource == primary && lastGoodPrice != 0` を満たす場合だけ成功する。shared JPY provider の unhealthy expiry、担保 oracle / canonical / backing failure、未登録 feed の shutdown call failureを `lastGoodPrice == 0` のまま通さず `InvalidInitialPrice` で revertし、fresh JPY recovery 後は deployment が自動的に再開可能 | unit / integration |

---

## 9. セキュリティ要件（SEC）

### <a id="orcl-sec-001"></a>ORCL-SEC-001: upstream PriceFeed 基底の差分最小化

- Type: Security
- Statement: upstream PriceFeed 基底との差分は Chainlink 応答検証の硬化に限定し、JPY 換算・backing 乗算・担保固有の合成は `DFPriceFeedBase` / 各 DF feed / `PriceFeedProxy` / `PriceFeedPlaceholder` 等の DF ファイルに閉じる。dwstETH composite は ORCL-FR-015 の専用 source として Day-1 追加監査で検証する。
- Verification: manual（継承構成レビュー）, static diff review, unit（不完全 round / 無効 timestamp 異常時の branch shutdown / JPY soft-freeze）

### ORCL-SEC-002: gas griefing 保護の透過の正確性

- Type: Security
- Statement: `PriceFeedProxy` の try/catch は、`MainnetPriceFeedBase` の gas griefing 保護 revert（`InsufficientGasForExternalCall`）を**セレクタ一致かつちょうど 4 バイト**のときだけ生 revert で再 revert し、本物のオラクル障害（同じく 4 バイトで届く `CallerNotPriceFeed()` 等）は従来どおり shutdown 経路へ流さなければならない。セレクタ前方一致＋追加データ付きの revert は再 revert しない（長さ `== 4` に厳格化）。比較セレクタは `MainnetPriceFeedBase.InsufficientGasForExternalCall.selector` を直接参照しコンパイル時に upstream へ結合し、upstream の rename / 削除でサイレント無効化されないこと。
- Verification: unit（セレクタ一致・長さ厳格・本物障害との判別）, integration

### ORCL-SEC-003: source 差替 timelock による MEV 緩和

- Type: Security
- Statement: source 差替は `proposeSource` → 12h timelock → `confirmSource` / `confirmSourceEmergency` の 2-step で、切替予定時刻と新 source を 12 時間前に公開しなければならない（予告なし差替の禁止）。timelock 単体では `confirmSource` ブロックでの価格ジャンプ MEV を排除しないため、通常 `confirmSource` は旧 source が健全なら live 価格、不健全なら Proxy の path 別 last-good cache を基準に、通常価格・redemption 価格の差を 1% 以内に制限する。placeholder 有効化・大幅価格修正・incident 復旧で guard を越える必要がある場合のみ、GOV は `confirmSourceEmergency` を private 送信し、監視・cap 停止・keeper bundle 等の runbook と組み合わせる。
- Verification: unit（timelock 強制・live / cached 価格差 guard・通常経路の暗黙 bypass 禁止・emergency bypass）, manual（private 送信運用・incident runbook）

### ORCL-SEC-004: 両 consumer 経路の対称な防御

- Type: Security
- Statement: `fetchPrice` と `fetchRedemptionPrice` の**両 consumer 経路**に、同一の障害透過・shutdown 代行・gas guard 透過（[ORCL-SEC-002](#orcl-sec-002-gas-griefing-保護の透過の正確性)）、および **dToken backing 比の乗算（[ORCL-FR-014](#orcl-fr-014-dtoken-backing-peg-の反映全担保共通の後段層)）**を備えなければならない。片方だけ防御・片方だけ backing 適用すると非対称な穴になる（redemption 経路の無防備 consumer・backing 未適用 consumer を残さない）。
- Verification: unit（両経路の同等分岐）, integration

### ORCL-SEC-005: JPY/USD 共通依存のフェイルセーフ

- Type: Security
- Statement:
  1. deployment-wide に `JpyUsdRateProvider` を1つだけ配置し、全 active feed source へ同じ address を注入する。継承基底や feed ごとの state copy は shared storage にならないため禁止する。
  2. provider は健全な JPY/USD の `lastGoodJpyRate` と同じ response の `updatedAt` を `lastGoodJpyUpdatedAt` に対で保存する。
  3. stale・無効値・取得失敗では即時 shutdown せず、provider の単一 cache を代用する。初回障害観測時に `jpyFrozenSince = min(block.timestamp, lastGoodJpyUpdatedAt + PRM-ORACLE-001)` とし、全 branch が同じ rate / 起点 / 回復判定を受け取る。
  4. fresh response は期限到達前後を問わず live rate を採用し、`jpyFrozenSince = 0`、`jpyFreezeExpired = false` として `JpyRateUnfrozen` を発火する。期限到達後も oracle read を短絡してはならない。expiry latch は oracle が unhealthy な当該 episode 中だけ `failure=true` を再通知し、provider の lifetime 永続停止には使わない。
  5. expiry中はsourceが `failure=true` を返し、登録済みProxyが回復可能なoracle pauseを立てる。sourceは `primary` で価格を再読し、新しい有効価格で清算を再開できる。借入等のpause解除はOwnerの検証付きresumeを要する。
  6. 担保・peg・canonical・backingレッグの障害はJPYの猶予より優先し、回復可能なoracle pauseとする。恒久shutdownとは区別する。
  7. `InsufficientGasForExternalCall` は障害へ変換せず再 revert する。
  8. active feed source の constructor は初回 fetch が `primary` かつ nonzero `lastGoodPrice` を seed したことを検証する。unhealthy な shared expiry 中に未登録 feed からの shutdown が catch されても deployment を成功させず、fresh provider recovery 後は再 deployment を許可する（ORCL-INV-012）。
  9. `PRM-ORACLE-001 = 30h`、`006 = 24h` とする。清算はstalenessのみの障害ならJPY価格が54h未満、かつ他の入力が有効な場合に限り継続できる。BorrowerOperationsの価格利用と通常償還は `008 = 30h` で止め、新しい恒久shutdown判定にも古いJPY価格を使わない。返済・担保追加だけの調整は価格を要しない。
- Parameters: `PRM-ORACLE-001`、`PRM-ORACLE-006`
- Verification: unit（保存済み rate の timestamp provenance、stale / invalid 応答で無通信の freeze 上限超過後の初回 call が即 shutdown、保存済み rate が fresh な間の invalid response は初回観測 anchor、期限前後の fresh 回復、stale 応答では expiry 維持、回復後の次 episode が再度上限判定、既 shutdown branch は pinned / expiry 未観測 branch は再開、expired provider で Standard / dwstETH constructor reject・fresh recovery 後 deploy 成功、標準 / sUSDS 両実装）, integration（Proxy 経路）, fork

### ORCL-SEC-006: 中央集権ラッパー担保のペグ監視

- Type: Security
- Statement: wrapper / receipt token の market depeg が担保価値に反映されない PriceFeed では activation しない。WBTC 系は wrapper/original peg、XAUT 系は XAUT/XAU または direct XAUT/USD、wstETH は stETH/USD market を使う。off-chain monitoring は incident response の補助であり、on-chain 価格反映の代替にしない。
- Verification: unit（合成計算・ペグ段の shutdown）, fork（実ペグフィード）, manual（mainnet フィード提供状況・off-chain ペグ監視運用）

### ORCL-SEC-007: placeholder ブランチの操作不能性（多重ガード）

- Type: Security
- Statement: placeholder ブランチは価格が健全に見えても（`PriceFeedPlaceholder` が `(1e18, false)`）、Vault（`underlying == address(0)` で `deposit`/`redeem` revert・`UnderlyingMismatch`）・dToken（`TokenInfoNotSet`・`setCap(0)`）の多重ガードにより実質的に操作不能でなければならない。価格 stub 単独に依存しない多層防御とする。
- Verification: unit（各ガードの revert）, integration（placeholder ブランチで価値フロー全不能）

> **reentrancy**: オラクルレイヤーの読み出し（`fetchPrice` / `fetchRedemptionPrice`）は価格取得と shutdown 代行のみで価値移転を伴わない。CEI / ReentrancyGuard は消費側（[CollateralVault](./CollateralVault.md) / コア）の責務。source は差替可能だが、Proxy は source を完全信頼せず revert / 無効価格 / brick を防御的に扱う。

---

## 10. ガバナンス・運用・アップグレード要件（GOV）

### ORCL-GOV-001: Owner は governance / multisig

- Statement: `PriceFeedProxy` の Owner（`proposeSource` / `confirmSource` / `cancelSourceProposal` の権限主体）は、本番では governance / multisig でなければならない。デプロイ初期は deployer EOA が所有し、本番移行時に移管する。本番 Owner は GOV multisig が直接保持し、共通 TimelockController の配下には置かない（source 差替に 12h を内蔵するため、Timelock 配下にすると二重遅延・cancel 即時性の喪失を招く。Governance.md §5）。
- Verification: manual（デプロイ・本番移行構成レビュー）

### ORCL-GOV-002: Owner 移譲は 2-step

- Statement: Owner 移譲は `Ownable2Step`（`transferOwnership` →（新オーナー）`acceptOwnership`）で行い、typo 等による誤移転を防がなければならない。dToken（[DTKN-GOV-002](./dToken.md)）や Vault GOV 運用と整合。
- Verification: manual, unit（[ORCL-FR-006](#orcl-fr-006-所有権の-2-段階移転transferownership--acceptownership) と同）

### ORCL-GOV-003: Owner 放棄の無効化

- Statement: `renounceOwnership()` は常に revert しなければならない。source を永久 lock すると、JPY/USD 共通依存の事故対応、Chainlink deprecate、placeholder ブランチの後付け確定、将来のフィード差替が不能化するため、Owner 権限は burn せず GOV multisig へ 2-step で移譲する（共通 TimelockController の配下には置かない。Governance.md §5）。
- Verification: manual（本番移管構成レビュー）, unit（[ORCL-FR-007](#orcl-fr-007-renounceownership無効化)）

### ORCL-GOV-004: source 差替の運用（feed 単位の入れ替え）

- Statement: ロジック変更は `upgradeTo` ではなく、新 PriceFeed をデプロイして `proposeSource()` → 12h timelock → `confirmSource()` で feed 単位に入れ替える（`PriceFeedProxy` は非アップグレード）。Chainlink deprecate・担保トークン変更・placeholder の Day 2 有効化をプロトコル再デプロイなしで行う。
- JPY/USD 差替も同じ規範に従う。全 active branch の提案・確認・価格差・送信手順は Mainnet Deploy Env Freeze Runbook で一括管理する。
- Verification: manual（差替手順書）, integration（差替フロー・JPY/USD source swap）

### ORCL-GOV-005: Day 2 有効化フローの GOV 手順

- Statement: 未確定ブランチの有効化は [ORCL-FR-009](#orcl-fr-009-post-launch-未確定ブランチの-underlying-確定フロー) の dToken-first 順序（`dToken.setTokenInfo` → `vault.setUnderlying` → `proposeSource`/`confirmSource` → `setCap`）と cap 事前確認を GOV 手順として遵守しなければならない。順序違反は `UnderlyingMismatch` で revert する。
- Verification: manual（GOV 手順書レビュー）, integration

---

## 11. イベント・監視要件（EVT）

| ID | イベント | 用途（off-chain） |
| --- | --- | --- |
| ORCL-EVT-001 | `SourceProposed`（new source・確定可能時刻） | source 差替提案の検知・12h timelock 監視・事前監査開始 |
| ORCL-EVT-002 | `SourceUpdated(oldSource, newSource)` | source 差替確定の検知（feed 切替完了） |
| ORCL-EVT-003 | `SourceProposalCancelled` | 保留 proposal 取消の検知 |
| ORCL-EVT-004 | Proxy の shutdown 観測イベント（source 障害で shutdown 代行した契機）および upstream source の `ShutDownFromOracleFailure(address failedOracleAddr)` | branch shutdown 発生のアラート（incident response）。DF source 直下の oracle / backing / rate-provider 障害は `failedOracleAddr` で識別する |
| ORCL-EVT-005 | OZ `OwnershipTransferStarted` / `OwnershipTransferred` | 所有権移転（deployer→multisig）の監視 |
| ORCL-EVT-006 | `SourceSwitchValidated`（old/reference・new 価格、oldSourceHealthy、priceGuardBypassed） | 通常差替 / cache 基準復旧 / 明示 emergency bypass の識別、価格ジャンプ監査 |
| ORCL-EVT-007 | `JpyRateFrozen(timestamp, frozenRate)` | JPY soft-freeze の検知。`timestamp` は初回観測と保存済み JPY rate の stale 境界の早い方で、event emission block より古い場合がある |
| ORCL-EVT-008 | `JpyRateUnfrozen` | live JPY/USD への復帰検知 |
| ORCL-EVT-009 | `JpyFreezeExpired(timestamp, frozenRate)` | 当該 shared JPY freeze episode の expiry を示す最速の P0 signal。各 active branch の shutdown / `priceSource` と user action block を確認し、後続の provider 回復が既 shutdown branch を再開しないことを追跡 |

- 価格そのもの・`lastGoodPrice` への退避は upstream 基底由来のイベント／状態で観測する（本書は発火本体を持たない）。
- shutdown の発火本体は upstream `borrowerOperations.shutdownFromOracleFailure()`。Proxy 側は ORCL-EVT-004 で可観測化する。

---

## 12. 失敗時・異常系挙動（ERR）

**価格取得経路（`fetchPrice` / `fetchRedemptionPrice`、[ORCL-FR-004](#orcl-fr-004-fetchprice障害透過と-shutdown-代行) / [ORCL-FR-005](#orcl-fr-005-fetchredemptionpriceredemption-consumer-経路)）**

| 契機 | 挙動 |
| --- | --- |
| source success かつ有効価格 | 経路別 cache（`_lastGoodPrice` / `_lastGoodRedemptionPrice`）更新 → 返却（定常状態） |
| gas guard revert（`InsufficientGasForExternalCall`・厳密 4 バイト・セレクタ一致） | そのまま再 revert（shutdown しない・全体 revert）＝ OOG を障害と誤認しない |
| その他 revert / 無効価格（`0` または `type(uint256).max`） | `shutdownFromOracleFailure()` 代行 → source `lastGoodPrice()` 取得可ならそれを返す／ source brick なら Proxy の経路別 cache を返す（permanent DoS 防止） |

**価格ソース状態機械（`PriceSource`、upstream `MainnetPriceFeedBase` 定義を保持）**

```javascript
enum PriceSource { primary, ETHUSDxCanonical, lastGoodPrice }
```

```javascript
        fetchPrice() OK
primary ──────────────▶ primary   （定常状態 = Chainlink 正常）
   │
   │ 担保/USD・peg監視・canonical rate 等の個別レッグ障害
   ▼
lastGoodPrice         （以後は最後に記録した価格を返し続ける / branch shutdown 済み）
```

- Standard / Peg-monitored / Composite peg / dwstETH composite は `primary` と `lastGoodPrice` の 2 状態を使う。Composite rate も未使用の `ETHUSDxCanonical` fallback を持たず、障害時は `lastGoodPrice` に退避する。JPY レッグだけは `ORCL-SEC-005` に従う。

**JPY/USD の土日・祝日扱い**

曜日・祝日判定は持たず、`updatedAt` と `PRM-ORACLE-001` だけで判定する。値の根拠は [設計メモ](../../launch/decisions/jpyusd-staleness-threshold-determination.md) を正本とする。

**placeholder 期（Underlying 未確定）の挙動**

| 層 | placeholder 期 | active 期 |
| --- | --- | --- |
| `PriceFeedPlaceholder.fetchPrice()` | `(1e18, false)`（shutdown 非誘発） | 実 PriceFeed の JPY 建て価格 |
| Vault `deposit`/`redeem` | `UnderlyingNotSet` / `UnderlyingMismatch` revert | 実行可 |
| dToken `convertTo*` | `TokenInfoNotSet` revert | 換算値 |
| cap | `0`（mint 不能） | `setCap(N)` で解放 |

**エラーカタログ**

| エラー | 契機 |
| --- | --- |
| `InvalidSource` | `PriceFeedProxy` constructor / `proposeSource` / `confirmSource` で source がゼロ・非 contract・初期/switch smoke-test 不合格（[ORCL-FR-001](#orcl-fr-001-source-差替の提案proposesource) / [ORCL-INV-004](#8-不変条件inv)） |
| `SameSource` | `proposeSource` / `confirmSource` で新 source が現 `source` と同一 |
| `NoProposalPending` | `confirmSource` / `confirmSourceEmergency` / `cancelSourceProposal` で保留 proposal が存在しない |
| `TimelockNotElapsed` | `confirmSource` / `confirmSourceEmergency` が `TIMELOCK_DELAY`（12h）経過前に呼ばれた |
| `ZeroOwnerAddress` | `PriceFeedProxy` constructor の `_ownerAddress == address(0)` |
| `InvalidAddress` | `PriceFeedProxy` constructor の `_borrowerOperations == address(0)` |
| `SourcePriceDeviationTooLarge` | 通常 `confirmSource` で旧 source が健全かつ新旧通常価格 / redemption 価格の差分が `MAX_SOURCE_SWITCH_DEVIATION_BPS`（1%）を超える |
| `RenounceOwnershipDisabled` | `PriceFeedProxy.renounceOwnership()` 呼び出し（[ORCL-FR-007](#orcl-fr-007-renounceownership無効化) / [ORCL-GOV-003](#orcl-gov-003-owner-放棄の無効化)） |
| `InsufficientGasForExternalCall`（再 revert） | upstream の gas griefing 保護を Proxy が透過（[ORCL-FR-004](#orcl-fr-004-fetchprice障害透過と-shutdown-代行)） |
| `CallerNotPriceFeed`（upstream） | underlying feed が直接 `shutdownFromOracleFailure()` を呼ぶと `msg.sender != address(priceFeed)`。Proxy 代行で回避（[ORCL-FR-004](#orcl-fr-004-fetchprice障害透過と-shutdown-代行)） |
| `InvalidCollateralVault` | `DFPriceFeedBase` / `sUSDSPriceFeed` constructor で backing 参照先 CollateralVault が contract でない |
| `InvalidInitialPrice` | active `DFPriceFeedBase` / `DFWstETHPriceFeed` constructor の初回 fetch 後に `priceSource != primary` または `lastGoodPrice == 0`（ORCL-INV-012） |
| `InvalidRateProvider` | `sUSDSPriceFeed` constructor で sUSDS rate provider またはその `asset()` が contract でない |
| `InvalidRateProviderDecimals` | `sUSDSPriceFeed` constructor で sUSDS またはその asset が 18 decimals でない |
| `UnderlyingNotSet`（Vault 側） | placeholder ブランチの `deposit`/`redeem`（[ORCL-FR-008](#orcl-fr-008-placeholder-ブランチの初期-source-pricefeedplaceholder)） |
| `UnderlyingMismatch`（Vault 側） | dToken-first 順序違反 / `dToken.underlying() != token`（[ORCL-FR-009](#orcl-fr-009-post-launch-未確定ブランチの-underlying-確定フロー)） |
| `TokenInfoNotSet`（dToken 側） | placeholder 期の `convertTo*`（[ORCL-FR-008](#orcl-fr-008-placeholder-ブランチの初期-source-pricefeedplaceholder)） |

---

## 13. 受け入れ基準・検証計画

各要件の合格条件 = 下表の検証手段を満たすこと（テスト名・実行結果は本書に書かない＝手段の種別まで）。

| ID | 要件（要約） | 検証手段 |
| --- | --- | --- |
| ORCL-FR-001 | proposeSource（Owner 限定・`address(0)` 拒否・timelock 開始） | unit |
| ORCL-FR-002 | confirmSource / confirmSourceEmergency（timelock 経過後のみ・差替反映・通常価格差 guard・emergency bypass） | unit, manual |
| ORCL-FR-003 | cancelSourceProposal（Owner 限定・proposal クリア） | unit |
| ORCL-FR-004 | fetchPrice（障害透過・shutdown 代行・gas guard 再 revert・brick フォールバック） | unit, fork, integration |
| ORCL-FR-005 | fetchRedemptionPrice（fetchPrice と同等分岐・redemption consumer） | unit, integration |
| ORCL-FR-006 | 2-step 所有権移転（誤移転防止） | unit, manual |
| ORCL-FR-007 | renounceOwnership 無効化（Owner/source proposal/pendingOwner 不変） | unit, manual |
| ORCL-FR-008 | PriceFeedPlaceholder（`(1e18, false)`・shutdown 非誘発・多重ガード） | unit, integration |
| ORCL-FR-009 | Day 2 有効化フロー（dToken-first 順序・cap 事前確認） | unit, integration, manual |
| ORCL-FR-010 | Standard（USDC・担保/USD 障害は shutdown、JPY/USD 障害は soft-freeze） | unit, fork, integration |
| ORCL-FR-011 | Peg-monitored（WBTC・peg/担保/USD 障害は shutdown、JPY/USD 障害は soft-freeze） | unit, fork, integration |
| ORCL-FR-012 | Composite rate（sUSDS・USDS/USD/canonical rate 障害は shutdown、JPY/USD 障害は soft-freeze） | unit, fork, integration |
| ORCL-FR-013 | XAUT 候補の Composite peg（on-chain downside depeg 反映を activation の必須条件とする） | unit, fork, integration, manual |
| ORCL-FR-015 | dwstETH（stETH/USD × canonical rate composite、JPY/USD、backing ratio） | unit, fork, integration, invariant |
| ORCL-INV-001..012 | §8 各不変条件 | unit / invariant / fork / manual / CI（§8 記載どおり） |
| ORCL-SEC-001..007 | §9 各セキュリティ要件 | unit / fork / integration / manual / CI |

---

## 14. 未決事項（TBD）

### ORCL-TBD-001

Open: `PRM-ORACLE-003` / `PRM-ORACLE-004`の候補値をmainnet broadcast前に確定する。Branch 2–7は個別activation packageがexact Underlyingをbindするまでcollateral/USD inputを持たない。`PRM-ORACLE-001` / `006`は確定済み、`PRM-ORACLE-002`はDay-1 consumerを持たない。

### ORCL-TBD-002

Resolved: `ORCL-FR-012`、`ORCL-FR-014`、`ORCL-SEC-001` に反映済み。

### ORCL-TBD-003

XAUT を担保候補として評価する場合の feed 品質基準と Composite peg 実装形を確定する。現行 branch map への binding や activation を意味しない。

- **feed 品質基準**: 価格ソースの流動性、feedCategory、mainnet 運用実績、週末挙動、deviation / heartbeat を確定する。基準未満の feed では activation しない。
- **提供状況（2026-06-10・Chainlink 公式フィードレジストリ実測）**: Ethereum mainnet は XAU/USD のみ（XAUT/XAU・XAUT/USD なし。PAXG/USD は存在）。XAUT/USD は mainnet 以外のチェーンで提供あり（実測確認: Hyperliquid〔標準＋SVR の 2 proxy〕・Plasma。いずれも heartbeat 24h・deviation 0.5%。網羅列挙ではない）。Arbitrum レジストリの XAUT/USD-RefPrice エントリは contract 未配備で消費不能。direct の XAUT/XAU ratio フィードは確認した範囲ではどの提供者にも無い。実装前に Chainlink 公式 addresses ページで最終確認する。
- **昇格時の実装形の比較確定**: 提供 primitive が XAUT/USD（market）の場合、(i) ratio 合成（`xautXau = xautUsd × 1e18 / xauUsd` をペグ段に使う WBTC 同型）か (ii) `collUsdOracle = XAUT/USD` への Standard 置換かを比較確定する。設計留意: XAU/USD は Precious_Metals 市場時間、XAUT/USD は Crypto 24/7 のため、週末は ratio が金のオフマーケット変動分だけ見かけ上乖離し得る（偽デペグシグナル）。feed metadata と週末挙動は activation evidence で再確認し、premium 側（XAUT > XAU）を担保価値に計上するか `min(1e18, ratio)` でキャップするかも確定する。
- **off-chain ペグ監視**: downside peg ratio `r = XAUT/USD 市場中央値 / XAU/USD` を独立した複数ソースで監視し、premium（`r > 1`）は担保価値に加算しない。監視は on-chain PriceFeed の代替ではなく、operator への alert と incident response に使う。
  - **Watch**: `r < 0.99` が 2 サンプル連続、任意サンプル `r < 0.985`、または source dispersion 1.5% 超。ops 通知・source health 確認のみで、原則 on-chain action は行わない。
  - **Incident**: 1h median `r < 0.98`、または任意サンプル `r < 0.97`。guardian が XAUT Vault の `pauseDeposit` と `pauseAllocation` を手動実行する。redeem / claim は、別途 Vault solvency または transferability incident が無い限り開いたままにする。条件継続または source 品質に疑義がある場合、GOV は `dToken.setCap(0)`（または同等の no-new-mint cap）を queue する。
  - **Critical**: 1h median `r < 0.96`、任意サンプル `r < 0.94`、Tether 償還・移転可能性の失敗証跡、または source disagreement の長期化。deposit/allocation pause を維持し、cap freeze を実行/queue し、source 差替レビューを開始し、branch shutdown の前提条件・経済性を評価する。branch shutdown は不可逆で、過大な last-good price を保持し得るため最終手段に留める。
  - **Recovery**: 1h median `r >= 0.99`、source dispersion <= 1% が 24h 以上継続し、guardian/GOV が明示承認した場合のみ unpause する。静的 MCR haircut は downside depeg 7.616% を用いており、incident/critical band はこの損失予算を使い切る十分前に発火させる。
- **代替 peg ソース**: Tether Gold の on-chain proof-of-reserves 等（要デューデリジェンス）。Chainlink 外（Pyth `Crypto.XAUT/USD`〔pull〕・RedStone〔マルチ CEX 集約。mainnet 常設 push feed は未確認〕）は[Architecture Decision Records](../architecture/Architecture-Decision-Records.md#adr-005)の信頼境界変更を伴うため、採用するなら ADR 改訂を先行させる。

### ORCL-TBD-004

USDS/USD deprecate 時のフォールバック feed — USDS は DAI の 1:1 後継のため、将来 USDS/USD が deprecate された場合は DAI/USD（`0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9`）への差替を `PriceFeedProxy` 経由で行う選択肢。最終チェックサムは Chainlink 公式 addresses ページで照合する。関連: [ORCL-FR-012](#orcl-fr-012-composite-rate-パターンsusdsyield-bearing)。

### ORCL-TBD-005

Resolved: `ORCL-SEC-003` に反映済み。

### ORCL-TBD-006

Resolved: `ORCL-FR-014`、`VAULT-INV-012` に反映済み。

---

## 15. 参考資料

- [Product Overview](../Product-Overview.md) — 全体アーキテクチャ・責務分離・コア無改変方針
- [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md) — 🔵 コアの担保・清算・Redemption・upstream PriceFeed 基底（`MainnetPriceFeedBase` / sUSDS 用に pruned した `CompositePriceFeed`・`PriceSource`・shutdown・gas griefing 保護）
- [dToken 要件定義](./dToken.md) — placeholder ブランチ・`setTokenInfo`・cap・`convertTo*`（Day 2 有効化の dToken-first 連携先）
- [CollateralVault 要件定義](./CollateralVault.md) — `setUnderlying`・`UnderlyingNotSet`/`UnderlyingMismatch`・mint/redeem（placeholder 多重ガード連携先）
- [Parameters.md](../../../Parameters.md) — ブランチ↔担保割当・確定状況・staleness 確定値・MCR/LLTV/CCR・デペグ織込み値の正本
- 🔵 `contracts/src/PriceFeeds/MainnetPriceFeedBase.sol` — **upstream 由来・硬化差分あり**。Chainlink 取得・18 桁正規化・`PriceSource`・shutdown（JPY 換算は含まない）。`roundId == 0` / `answeredInRound < roundId` / `updatedAt == 0` / 未来時刻を無効応答として扱い、response の `updatedAt` を既存結果とともに internal provenance として返せる。
- 🔵 `contracts/src/PriceFeeds/CompositePriceFeed.sol` — **upstream 由来・sUSDS 用 pruning あり**。`USDS/USD × canonical rate` の合成基底（`sUSDSPriceFeed` の親）。WSTETH/RETH 用 LST secondary fallback は production `src` から削除済み
- 🟢 `contracts/src/PriceFeeds/JpyUsdRateProvider.sol` — **DF 新規**。deployment-wide に1つの JPY/USD cache・freeze timer・回復・latched expiry state machine
- 🟢 `contracts/src/PriceFeeds/DFPriceFeedBase.sol` — **DF 新規**。`is MainnetPriceFeedBase`。`JpyUsdRateProvider` を使う JPY 換算＋`collateralVault.backingRatioForPricing()` 乗算（標準・peg 型 DF feed の親）
- 🟢 `contracts/src/PriceFeeds/PriceFeedProxy.sol` — **DF 新規**。source 差替（12h timelock）・try/catch shutdown・`Ownable2Step`
- 🟢 `contracts/src/PriceFeeds/DFUSDCPriceFeed.sol` — **DF 新規**。担保別 PriceFeed（`DFPriceFeedBase` 継承、JPY 建てを返す）。archived candidate: `contracts/src/PriceFeeds/archive/DFUSDTPriceFeed.sol` / `contracts/src/PriceFeeds/archive/DFXAUTPriceFeed.sol` / `contracts/src/PriceFeeds/archive/DFWBTCPriceFeed.sol`
- 🟢 `contracts/src/PriceFeeds/JpyFreezeLib.sol` — **DF 新規**。共有 JPY 換算 / freeze / backing library（各 feed は state 保持のみ）
- 🟢 `contracts/src/PriceFeeds/DFWstETHPriceFeed.sol` — **DF 新規**。dwstETH の stETH/USD × canonical rate composite（pruned `CompositePriceFeed` 継承、ORCL-FR-015）
- 🟢 `contracts/src/PriceFeeds/archive/sUSDSPriceFeed.sol` — **DF 新規（archived candidate）**。Composite rate（sUSDS 用に pruning した `CompositePriceFeed` ＋ shared-provider JPY 換算 / local backing 乗算）
- 🟢 `contracts/src/PriceFeeds/PriceFeedPlaceholder.sol` — **DF 新規**。placeholder ブランチの初期 source
- `contracts/script/DeployLiquity2.s.sol` — フィード・staleness・アドレス配線
- Chainlink Data Feeds: [https://data.chain.link/](https://data.chain.link/)
- Chainlink feed metadata: [https://reference-data-directory.vercel.app/feeds-mainnet.json](https://reference-data-directory.vercel.app/feeds-mainnet.json) — Ethereum mainnet 標準 feed の heartbeat / deviation / marketHours / decimals / proxy 照合に使う
- [要件定義ドキュメント標準](../../../Requirements-Spec-Standard.md) — 本書が従う標準
