# 🟢 CollateralYieldZapper 要件定義

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Draft（`CollateralYieldZapper` / `SkyUsdcSUsdsYieldZapper` / `SkyUsdcSUsdsConverter` / `UniV4Exchange` 実装あり。Flash Loan close / Balancer / Uniswap v3 route は Day-1 ABI 外。残 gate は user app flow 採用、Sky route fork evidence、JPYdf/USDC v4 route 本番有効化） |
| Owner | DeltaForesight |
| 対象コントラクト | Active: `contracts/src/Zappers/CollateralYieldZapper.sol` / `contracts/src/Zappers/Modules/Exchanges/UniV4Exchange.sol` / `IZapper` / `BaseZapper`。Archived reference: `contracts/src/Zappers/archive/SkyUsdcSUsdsYieldZapper.sol` |
| 関連ドキュメント | [Product-Overview](../Product-Overview.md)（アーキ・責務分離）/ [CollateralVault](./CollateralVault.md)（deposit/redeem/遅延償還の依存元）/ [dToken](./dToken.md)（換算・permit の依存元）/ [Oracle](./Oracle.md) / [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md)（BorrowerOperations 等）/ [Parameters](../../../Parameters.md) |

対象の内訳:

- `contracts/src/Zappers/CollateralYieldZapper.sol`: 本体。永続 business state を持たない UX Router（immutable 参照 + `ReentrancyGuard` lock）。
- `contracts/src/Zappers/archive/SkyUsdcSUsdsYieldZapper.sol`: ARCHIVED candidate collateral ingress。Day-1 deploy / active audit scope外。
- `contracts/src/Strategies/SkyUsdcSUsdsConverter.sol`: Sky LitePSMWrapper-USDS-USDC の concrete adapter。
- `contracts/src/Zappers/Modules/Exchanges/UniV4Exchange.sol`: JPYdf/USDC Uniswap v4 route adapter（immutable route config + `ReentrancyGuard` lock）。Day-1 audit scope に含めるが、production 配線は ZAP-TBD-010 の gate 後。
- `IZapper`: Liquity v2 base 由来の最小 surface と DeltaForesight 拡張関数。
- `BaseZapper`: `AddRemoveManagers` / `LeftoversSweep` / `IZapper` を共有する基底。`ReentrancyGuard` は concrete user-facing contract 側で継承する。

> 本書は [要件定義ドキュメント標準](../../../Requirements-Spec-Standard.md)に従う。要件・不変条件・セキュリティ要件には永続 ID（`ZAP-…`）を付し、相互参照は ID で行う。
>
> 📌 **要件の由来**: 本コントラクトは 🟢 新規ファイルだが、**個々の要件は Liquity v2 base 由来と DeltaForesight 新規が混在する**。各要件の由来（**B**=Base 踏襲 / **B+**=Base 更新 / **N**=完全新規）は §1.5 の分類表と §5 要約表の「由来」列を参照。
>
> 📌 **実装同期メモ（2026-06-19）**:
> - `CollateralYieldZapper` は active branch の deploy / manifest / frontend binding へ配線済み。
> - `UniV4Exchange` は Day-1 audit scope に含めるが、user-facing route は route config / fork evidence 後に有効化する。
> - Day-1 liquidity は [`Liquidity-Route-Policy.md`](../policies/Liquidity-Route-Policy.md) のとおり JPYdf/USDC Uniswap v4 のみ。
> - Flash Loan close / Balancer / Uniswap v3 / Multiply は production `src` と ABI に存在しない。
> - 現時点の production PASS は open / add / withdraw / close-with-JPYdf / Sky USDC ingress の範囲で判定する。

---

## 1. 目的・スコープ・非責務

`CollateralYieldZapper` は、Underlying（WETH / WBTC / USDC 等）を入口にして JPYdf 借入・返済・担保引出を **1 Tx・Underlying ベース**で行う stateless UX Router である。内部で dToken を一時保有して Core に渡すため、ユーザーは dToken を直接扱わない。

### 1.1 目的と背景（なぜ Zapper が要るか）

Liquity v2 の `BorrowerOperations.openTrove` は、担保を `msg.sender` から pull し、base debt token（DF では JPYdf）を `msg.sender` に mint する設計である。dToken Layer を素朴に挟むとユーザー操作が増える：

- **Liquity v2 オリジナル**：① 担保 Approval → ② 担保送金 & JPYdf 借入（2 ステップ）
- **dToken の単純実装**：① 担保 Approval → ② 担保送金 & dToken 受領 → ③ dToken Approval → ④ dToken 送金 & JPYdf 借入（4 ステップ）
- **Zapper 利用時**：① 担保 Approval → ② Zapper 呼出し（担保送金 & dToken 受領 & dToken 送金 & JPYdf 借入まで一気通貫）

Zapper を外付けにすることで、Vault / Liquity Core に専用ロジックを入れずに UX を改善する。

### 1.2 本書が規定する対象（`CollateralYieldZapper` の責務）

- **Underlying ベースの Trove 操作の 1 Tx 化**
  - open（`openTroveWithRawETH` / `…AndReferral`）、増担保・借入増減（`addCollWithUnderlying` / `adjustTroveWithUnderlying` / `adjustZombieTroveWithUnderlying`）、返済（`repayJpydf`）、担保引出（`withdrawCollToUnderlying` / `…WithMin`）、借入引出（`withdrawJpydf`）、close（`closeTroveToUnderlying` / `…WithMin`）
- **EIP-2612 Permit 対応**（事前 approve なし）：`openTroveWithUnderlyingPermit` / `…AndReferral`
- **Day-1 ABI から削除済みの経路**：Flash Loan close / collateral-funded repay / Multiply は本書の active production scope に含めない（[ZAP-FR-011](#zap-fr-011-day-1-abi-から削除済みflash-loan-close--collateral-funded-close) / [ZAP-FR-012](#zap-fr-012-day-1-abi-から削除済みflash-loan-callback)）。
- **referralCode のオフチェーン追跡**：`ReferralDeposit` イベント（open ケースのみ）
- **ARCHIVED Sky route variant**：candidate collateral ingressの履歴仕様。official deploy pathには存在せず、archive suiteだけで継続検証する。

### 1.3 本書が規定しない（非責務・他文書）

- **Liquity v2 Fork（コア）**：`BorrowerOperations` / `TroveManager` / `TroveNFT` / `JpydfToken` の挙動 → [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md)
- **dToken Layer**：`CollateralVault.deposit` / `redeem` / 遅延償還 / claim、`dToken` の換算・permit の本体仕様 → [CollateralVault](./CollateralVault.md) / [dToken](./dToken.md)
- **Exchange / route モジュール**：Day-1 の liquidity / route policy は [Liquidity-Route-Policy](../policies/Liquidity-Route-Policy.md) を正本とする。`UniV4Exchange` は Day-1 audit scope に含める JPYdf/USDC v4 route adapter / evidence 対象だが、現行 `CollateralYieldZapper` の constructor 依存・user-facing entrypoint ではない。
- **レバレッジ操作**：本コントラクトは対象外。Day-1 では leverage 用 callback / router interface も production `src` から削除し、dToken 担保でのレバレッジが必要になれば別コントラクトとして設計する（[ZAP-TBD-004](#zap-tbd-004)）。
- **Sky LitePSMWrapper route**：`SkyUsdcSUsdsYieldZapper` は USDC→USDS 変換を `ISkyUsdcSUsdsConverter` に委譲する。具象 adapter は Sky 公式 LitePSMWrapper-USDS-USDC を immutable に束縛し、手数料、halt、decimals、実残高差分を検査する（[ZAP-TBD-009](#zap-tbd-009)）。
- **担保別パラメータ**（mintCap / buffer 等）の確定値 → [Parameters](../../../Parameters.md)

### 1.4 Zapper 群の中での位置づけ

Liquity v2 base は担保タイプごとに複数の Zapper を持つ。代表例は `WETHZapper`、`GasCompZapper`、`LeverageWETHZapper` / `LeverageLSTZapper` である。いずれも担保 ERC-20 をそのまま `BorrowerOperations` に渡す前提で、dToken / CollateralVault を知らない。

DeltaForesight では担保 = dToken（全担保ブランチで 18dec ERC-20）となるため、`CollateralYieldZapper` は次の設計判断を採る（根拠は §2）：

- **`GasCompZapper` パターンを踏襲する**：gas compensation 分の ETH だけを `msg.value` で受け取り、担保は **Underlying を ERC-20 として `transferFrom`** で pull する。pull した Underlying を `CollateralVault.deposit` で dToken 化し、その dToken を担保として `BorrowerOperations` に渡す。
- **全担保を 1 コントラクトで扱う**：担保はすべて dToken（18dec ERC-20）に正規化される。ERC-20 Underlying を受け取って dToken に変換するのが全 branch 共通の既定経路であり、`msg.value` は gas compensation 専用である。唯一の例外が dwstETH ブランチの native-ETH on-ramp（[ZAP-FR-015](#zap-fr-015-native-eth-on-rampethstethwstethdwsteth)）で、これは deploy パラメータで明示的に有効化した場合にのみ存在する。
- **`BaseZapper` を継承して安全機構を共有する**：`AddRemoveManagers`（owner / add manager / remove manager・receiver の権限チェック）と `LeftoversSweep`（残余返却）を Liquity v2 base 由来の基底からそのまま継承し、独自実装を最小化する。再入防止は concrete user-facing contract が `ReentrancyGuard` を継承して担う。
- **Leverage / Flash Loan close は対象外**：Day-1 の leverage callback / router surface と Flash Loan close surface は production `src` / ABI から削除済みである。必要になれば、route config と fork evidence を持つ別の audited entrypoint / contract として追加する。

upstream 由来の `WETHZapper` / `GasCompZapper` / `LeverageWETHZapper` / `LeverageLSTZapper` と `ILeverageZapper` は production `contracts/src` から削除済みである。DF の user-facing production 対象は `CollateralYieldZapper` のみで、`SkyUsdcSUsdsYieldZapper` は archived candidate-ingress variant（再採用は activation package と Owner 承認による）であり、leverage UI は提供しない。native ETH は upstream の `WETHZapper` のような担保 flow としてではなく、dwstETH ブランチの on-ramp（ETH→stETH→wstETH、[ZAP-FR-015](#zap-fr-015-native-eth-on-rampethstethwstethdwsteth)）としてのみ受け入れる。

**Sky route variantの位置づけ**: 以下のSky ingress要件（ZAP-FR-014 / ZAP-INV-009を含む）はarchive sourceの履歴仕様であり、Day-1要件・activation承認ではない。再採用にはOwner承認、実装review、追加監査要否の判断が必要である。

### 1.5 要件の由来（Base 踏襲 / Base 更新 / 完全新規）

本コントラクトは 🟢 新規ファイルだが、**個々の要件は由来が異なる**。upstream Liquity v2 base の `IZapper` 規定と `GasCompZapper` パターン（DF が踏襲する非 WETH ERC-20 担保 Zapper）を基準に、各要件を以下のマーカーで分類する（§5 要約表の「由来」列と相互参照）。

- **B（Base 踏襲）**: upstream に同等関数があり、ほぼそのまま継承（シグネチャ・挙動が実質同一）。
- **B+（Base 更新）**: upstream に同等関数があるが、担保 = dToken に合わせて Underlying↔dToken 変換を挟む等の改変を加えたもの。
- **N（完全新規）**: upstream に対応物が無い DeltaForesight 独自要件。

| 要件 | 由来 | 補足（base との差分） |
| --- | :---: | --- |
| ZAP-FR-001 `openTroveWithRawETH` | B+ | `IZapper` 規定。担保を Underlying で pull→`deposit`→dToken 化（base は実担保を直接 pull） |
| ZAP-FR-002 `…AndReferral` | B+／N | open は base 由来、`…AndReferral` ＋ `ReferralDeposit` は新規 |
| ZAP-FR-003/004 `openTroveWithUnderlyingPermit(…)` | N | upstream 非 WETH/WETH Zapper に permit-open は無い |
| ZAP-FR-005 `addCollWithUnderlying` | B+ | base `addColl` を Underlying→dToken 化 |
| ZAP-FR-006 `withdrawCollToUnderlying` / `…WithMin` | B+ | base `withdrawColl` を dToken→Underlying redeem 化し、DF で受取 Underlying 下限を追加 |
| ZAP-FR-007 `withdrawJpydf` | B+ | base `withdrawBold` を JPYdf 命名に更新。挙動は base と同型 |
| ZAP-FR-008 `repayJpydf` | B+ | base `repayBold` を JPYdf 命名に更新。`_returnLeftovers` は base 由来 |
| ZAP-FR-009 `adjustTroveWithUnderlying` / `adjustZombieTroveWithUnderlying` | N | upstream 非 WETH/WETH Zapper に combined adjust ラッパー無し。コアの `adjustTrove` / `adjustZombieTrove` を Underlying でラップし、DF で `…WithMin` を追加 |
| ZAP-FR-010 `closeTroveToUnderlying` / `…WithMin` | B+ | base `closeTroveToRawETH` を dToken→Underlying redeem＋gasComp 化し、DF で受取 Underlying 下限を追加 |
| ZAP-FR-011 `closeTroveFromCollateral` | Deferred | fresh deploy 方針により Day-1 production ABI から削除済み。将来追加する場合は新しい audited entrypoint として再設計する |
| ZAP-FR-012 close-from-coll コールバック | Deferred | Flash Loan close 削除に伴い Day-1 production ABI から削除済み。callback surface は現行実装に存在しない |
| ZAP-FR-013 `receive` | B+ | gas compensation の `WETH.withdraw` 受領だけを許容。旧 leverage callback surface は削除済み |
| ZAP-FR-014 Sky USDC route | N | `SkyUsdcSUsdsYieldZapper`・`ISkyUsdcSUsdsConverter` 経由。base に対応物なし |
| ZAP-FR-015 native ETH on-ramp | N | base の `WETHZapper` は ETH を担保そのものとして扱うが、本 route は ETH を stETH→wstETH へ変換して既存の dToken 経路へ合流させる。deploy パラメータで有効化する点も base に対応物なし |

> 非機能要件の由来:
> - **B（base 由来）**: `BaseZapper` / `AddRemoveManagers` / `LeftoversSweep`、永続 business state を持たない設計（immutable 参照 + `ReentrancyGuard` lock）、`nonReentrant`、manager / receiver 整合、残余返却、gasComp 送付検査。
> - **N（新規）**: dToken 中継、referral、Sky route、`minUsdsOut` / `minSUsdsOut`。
> - 旧 Flash Loan callback 呼出元検証は、Day-1 ABI から削除された surface の不在確認として扱う。

---

## 2. 背景・設計方針

`CollateralYieldZapper` は **UX 改善のためのオプションモジュール**であり、以下の原則を遵守する。`GasCompZapper` のパターンを**踏襲する**のは、担保 = dToken（18dec ERC-20）に正規化できるため、非 WETH の ERC-20 担保を `msg.value`（gas comp 専用）＋ ERC-20 pull で扱う `GasCompZapper` 形が最小改変で成立するからである。

- **コア・Vault・dToken を「順番に呼ぶ」が、状態と責務の主体は変えない**。
- Liquity v2 コアは Zapper を知らない（コアにフックや特別対応を入れない）。
- dToken Layer も Zapper を知らない（CollateralVault の汎用 IF、すなわち `deposit(amount)` / `redeem(amount, receiver)` / `redeemWithPermit(...)` をそのまま使う。Vault に Zapper 専用シグネチャを一切追加しない＝"No Router" 方針）。
- referralCode は Vault / Liquity コアには渡さず、Zapper 内部で保持・イベント発火してオフチェーン追跡に閉じる（[ZAP-EVT-001](#zap-evt-001-referraldeposit)）。
- referral 計装（型・payload・indexing）の設計根拠は本書を正本とする（Zapper は immutable / 非 upgradeable のため deploy 後に function signature・event ABI を変更できず、referral surface は Day-1 前に固定する）:
  - **型 = `bytes32`**: `uint16` は per-user code に狭く枠上限が protocol growth の制約になりうる。短い slug・hash・address-derived key を収容でき、off-chain registry と将来の on-chain registry の双方に使える `bytes32` を採用する。
  - **payload の `jpydfAmount`**: user が受領する借入額（`_params.jpydfAmount`）であり、upfront fee 込みの `entireDebt` ではない。`entireDebt` 基準の配点が必要になった場合は [ZAP-EVT-001](#zap-evt-001-referraldeposit) と実装を改訂してから deploy する。
  - **indexing / 境界**: `referralCode` は storage に保存せず、会計・権限・資金移動に関与しない（Zapper 内の event 発火条件と payload にのみ使い、Vault / Liquity core へ渡さない）。subgraph / analytics consumer は `referralCode` を indexed topic として扱い、`jpydfAmount` を user-received debt として解釈する。
- **Zapper 自身は永続 business state を持たない**（その都度トークンを user に返却し、route / core 参照は constructor で固定する。例外は OpenZeppelin `ReentrancyGuard` の一時 lock 状態＝[ZAP-INV-001](#7-状態変数会計モデル)）。
- すべての user-facing 外部状態変更関数を `nonReentrant` で保護する。Day-1 ABI には Flash Loan callback を持たないため、callback 専用の非 `nonReentrant` 例外を作らない（[ZAP-SEC-001](#zap-sec-001-user-facing-外部状態変更関数の-nonreentrant) / [ZAP-SEC-004](#zap-sec-004-day-1-abi-に-flash-loan-callback-が存在しないこと)）。

#### CollateralYieldZapper が果たす 3 つの役割

1. **dToken をユーザーから隠蔽する** — ユーザーは Underlying を預けて JPYdf を借り、返済後に Underlying を受け取るだけでよい。dToken approval や中間残高を直接扱わせない。
2. **1 Tx 一気通貫を提供する** — dToken の deposit / approve / Core 操作を Zapper が束ねる。Permit 対応 Underlying では approve も同一 Tx に含める。
3. **流入元（referral）を追跡する** — referralCode は会計に関与しないオフチェーン集計用 metadata として、`ReferralDeposit` イベントだけに記録する。

> 責務分離の基本原則は [Product Overview](../Product-Overview.md) を正本とする。

---

## 3. 用語・外部依存・前提

**用語**

| 用語 | 意味 |
| --- | --- |
| Underlying | ユーザーが入出庫する実担保資産（WETH / WBTC / USDC 等）。Zapper の入出力はすべて Underlying 建て |
| dToken | Underlying を 18dec に揃えた 1:1 請求権トークン。コアから見た担保（`collToken == dToken`）。Zapper が一時保有してコアに渡す |
| collToken | コアから見た担保トークン（= dToken の ERC-20 ビュー）。`collToken == dToken` |
| gas compensation | Trove ごとに `ETH_GAS_COMPENSATION`（WETH 建て）でロックされる清算補償。担保とは別枠 |
| referralCode | 送客チャネル識別用のオフチェーンメタデータ（`bytes32`）。会計に関与しない。`bytes32(0)` は referral なし |
| receiver | Trove 操作で出力トークンを受け取るアドレス。Zapper が一時的に receiver となり最終的に endUser へ委譲 |
| stateless | 永続的な可変状態を持たず、毎 Tx 残高を user に返却する性質 |

**外部依存（信頼する外部）**

`CollateralYieldZapper` が呼び出す外部 IF を規定する。各 IF の本体仕様は参照先ドキュメントを正本とする（[ZAP-SEC-006](#zap-sec-006-approve-先の信頼コンポーネント限定) により approve 先は信頼コンポーネントに限定）。

| 依存先 | 使用する関数（規定インターフェース） | 参照 |
| --- | --- | --- |
| **CollateralVault** | `deposit(uint256 _underlyingAmount) returns (uint256 dTokenAmount)` | [CollateralVault 要件定義](./CollateralVault.md) |
| | `redeem(uint256 _dTokenAmount, address _receiver) returns (uint256 underlyingReceived, uint256 requestId)` | [CollateralVault 要件定義](./CollateralVault.md) |
| **dToken** | `convertToDToken(uint256 underlyingAmount) returns (uint256)`（Underlying→18dec、乗算・厳密） | [DTKN-FR-003](./dToken.md) |
| | `convertToUnderlying(uint256 dTokenAmount) returns (uint256)`（18dec→Underlying、切り捨て） | [DTKN-FR-003](./dToken.md) |
| **BorrowerOperations** | `openTrove` / `openTroveAndJoinInterestBatchManager` / `addColl` / `withdrawColl` / `withdrawJpydf` / `repayJpydf` / `adjustTrove` / `adjustZombieTrove` / `closeTrove` / `removeManagerReceiverOf` | [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md) |
| **TroveManager** | `getLatestTroveData(troveId)` / **TroveNFT** `ownerOf(troveId)` | [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md) |
| **JpydfToken** | `transfer` / `transferFrom` | [JpydfToken](./JpydfToken.md) |
| **Exchange / route adapter** | `UniV4Exchange`。現行 `CollateralYieldZapper` は Exchange を constructor 依存に持たない。 | [Product Overview](../Product-Overview.md) / [Liquidity-Route-Policy](../policies/Liquidity-Route-Policy.md) |
| **AddressesRegistry** | `collToken()` / `borrowerOperations()` / `troveManager()` / `jpydfToken()` / `WETH()` | Liquity v2 base 由来 Registry（追加 getter 不要） |
| **Sky USDC→USDS Adapter** | `convertUsdcToUsds(usdcAmount, minUsdsOut, receiver) returns (usdsOut)` | `ISkyUsdcSUsdsConverter`（具象実装は `SkyUsdcSUsdsConverter`） |
| **sUSDS ERC4626 Vault** | `asset()` / `deposit(assets, receiver)` | ERC4626。`asset() == USDS` を constructor で assert |

**Adapter / helper surface の扱い**:

- pool 初期化に必要な sqrt price 計算は off-chain / script tooling の責務とし、production `UniV4Exchange` ABI には補助 read-only helper を持たせない。
- `UniV4Exchange` は Day-1 audit scope に含める JPYdf/USDC Uniswap v4 final leg の adapter である。
- `UniV4Exchange.swapFromJpydf(jpydfAmount, minCollAmount)` は v4 single-pool **exact-output**
  実行であり、`minCollAmount` は「最低受取量」であると同時に「買う collToken 量」
  として router に渡される。`jpydfAmount` は最大入力で、未使用 JPYdf は caller に返る。
- `UniV4Exchange.swapToJpydf(collAmount, minJpydfAmount)` は v4 single-pool **exact-input**
  実行であり、`collAmount` 全量を入力し、実受取 JPYdf が `minJpydfAmount` 未満なら revert する。
- v4 action / command calldata は adapter が固定生成する。user supplied calldata は受け取らず、`TAKE_ALL`
  の受取先は Universal Router の `msgSender()`（adapter 呼出元としての `UniV4Exchange`）に限定される。
- 現行 ABI には swap-backed close / collateral-funded repay / Multiply の user-facing entrypoint はない。
- production-reviewed として扱える JPYdf final leg は JPYdf/USDC Uniswap v4 のみ。Curve、Uniswap v3 route、USDT/USDS/WETH/XAUT の JPYdf 直接 pool は scope 外。
- v4 production 配線は [ZAP-TBD-010](#zap-tbd-010) の route config / evidence gate 後に、新しい audited entrypoint として扱う。

> 📌 **Registry 非拡張方針**:
> - `AddressesRegistry` には `collateralVault()` / `dToken()` / `underlyingToken()` を追加しない。
> - Zapper 固有の `collateralVault` / `underlyingToken` は constructor 引数で受ける。
> - `dToken` は既存 `AddressesRegistry.collToken()`（= Core から見た担保）から導出する。
> - `DeployLiquity2` は active branch 末尾で `collToken == dToken`、`vault.underlying() == underlyingToken`、CYZ の core 参照束縛を assert する（[ZAP-TBD-003](#zap-tbd-003)）。

**前提**

- 逆方向の依存は存在しない（Vault / Liquity コア / dToken から Zapper を参照しない）。
- referralCode は Vault には渡さない（Vault は referral 概念を持たない）。Zapper 経由の open ケースでのみ `ReferralDeposit` を発火する（[ZAP-EVT-001](#zap-evt-001-referraldeposit)）。
- EIP-2612 Permit を使えるのは permit 対応 Underlying（USDC 等）に限る。非対応トークンは事前 approve 経路を使う（[ZAP-FR-004](#zap-fr-004-opentrovewithunderlyingpermitandreferralpermit-open--referral) / [ZAP-TBD-006](#zap-tbd-006)）。

---

## 4. アクター・ロール・信頼境界

| アクター | 操作 | 信頼境界 |
| --- | --- | --- |
| **endUser（Trove owner）** | open / addColl / withdrawColl / adjust / repay / withdrawJpydf / close を Underlying ベースで呼ぶ | 自分の Trove のみ。open 系は `_params.owner == msg.sender` を要求し、既存 Trove 操作は manager / receiver 整合（`AddRemoveManagers`）で他人の Trove を操作不可（[ZAP-SEC-002](#zap-sec-002-受益者と実行者の整合managerreceiver)） |
| **add manager / remove manager** | owner が委譲した担保増・借入返済（add）／担保引出・借入・close（remove）の代行 | `BaseZapper`（`AddRemoveManagers`）の共通関数で検査 |
| **Zapper 自身** | 一時的に Trove の add/remove manager・receiver となり、dToken / JPYdf を一時保有 | stateless。毎 Tx 残余を user へ返却（[ZAP-SEC-003](#zap-sec-003-残余の返却固定化回避)）。最後にユーザー指定の manager / receiver へ委譲 |

- **権限主体の不変**: Zapper は順番に呼ぶだけで、状態と責務の主体（担保所有者 = Trove owner、債務者 = Trove owner）を変えない。
- **アップグレード権限なし**: Zapper は stateless / immutable で proxy を持たない（[ZAP-GOV-002](#zap-gov-002-stateless--非アップグレード)）。差替が必要なら新コントラクトをデプロイし、フロントエンド / デプロイ設定側の参照を切り替える。

---

## 5. インターフェース仕様

規定インターフェース `IZapper`（Liquity v2 base 由来）＋ DeltaForesight 拡張。挙動は §6 機能要件、可視性のみ以下に要約（非規範）。共通事項として、**借入された JPYdf は一度 Zapper が受領し、ユーザー（または指定 receiver）へ転送する**（`BorrowerOperations` が mint 先に `msg.sender = Zapper` を使うため）。

| 関数 | 可視性 | 由来 | 要約 | 規定要件 |
| --- | --- | :---: | --- | --- |
| `openTroveWithRawETH(OpenTroveParams) → troveId` | external payable nonReentrant | B+ | open（referral=`bytes32(0)` へ委譲） | ZAP-FR-001 |
| `openTroveWithRawETHAndReferral(OpenTroveParams, bytes32) → troveId` | external payable nonReentrant | B+／N | open ＋ referral | ZAP-FR-002 |
| `openTroveWithUnderlyingPermit(OpenTroveParams, deadline, v, r, s) → troveId` | external payable nonReentrant | N | permit open（referral=`bytes32(0)` へ委譲） | ZAP-FR-003 |
| `openTroveWithUnderlyingPermitAndReferral(OpenTroveParams, deadline, v, r, s, bytes32) → troveId` | external payable nonReentrant | N | permit open ＋ referral | ZAP-FR-004 |
| `addCollWithUnderlying(troveId, underlyingAmount)` | external nonReentrant | B+ | 増担保（Underlying 建て） | ZAP-FR-005 |
| `withdrawCollToUnderlying(troveId, dTokenAmount) → (underlyingReceived, requestId)` | external nonReentrant | B+ | 減担保（Underlying で受取） | ZAP-FR-006 |
| `withdrawCollToUnderlyingWithMin(troveId, dTokenAmount, minUnderlyingReceived) → (underlyingReceived, requestId)` | external nonReentrant | N | 減担保（受取下限付き） | ZAP-FR-006 |
| `withdrawJpydf(troveId, jpydfAmount, maxUpfrontFee)` | external nonReentrant | B+ | 借入増 | ZAP-FR-007 |
| `repayJpydf(troveId, jpydfAmount)` | external nonReentrant | B+ | 返済 | ZAP-FR-008 |
| `adjustTroveWithUnderlying(troveId, underlyingChange, isCollIncrease, jpydfChange, isDebtIncrease, maxUpfrontFee) → (dTokenChange, underlyingReceived, requestId)` | external nonReentrant | N | 担保＋債務の同時調整 | ZAP-FR-009 |
| `adjustTroveWithUnderlyingWithMin(troveId, underlyingChange, isCollIncrease, jpydfChange, isDebtIncrease, maxUpfrontFee, minUnderlyingReceived) → (dTokenChange, underlyingReceived, requestId)` | external nonReentrant | N | 担保＋債務の同時調整（受取下限付き） | ZAP-FR-009 |
| `adjustZombieTroveWithUnderlying(troveId, underlyingChange, isCollIncrease, jpydfChange, isDebtIncrease, upperHint, lowerHint, maxUpfrontFee) → (dTokenChange, underlyingReceived, requestId)` | external nonReentrant | N | zombie Trove 調整 | ZAP-FR-009 |
| `adjustZombieTroveWithUnderlyingWithMin(troveId, underlyingChange, isCollIncrease, jpydfChange, isDebtIncrease, upperHint, lowerHint, maxUpfrontFee, minUnderlyingReceived) → (dTokenChange, underlyingReceived, requestId)` | external nonReentrant | N | zombie Trove 調整（受取下限付き） | ZAP-FR-009 |
| `closeTroveToUnderlying(troveId) → (underlyingReceived, requestId)` | external nonReentrant | B+ | close（JPYdf 保有時） | ZAP-FR-010 |
| `closeTroveToUnderlyingWithMin(troveId, minUnderlyingReceived) → (underlyingReceived, requestId)` | external nonReentrant | N | close（受取下限付き） | ZAP-FR-010 |
| `receive()` | external payable | B（IF） | `WETH.withdraw` の ETH 受領のみ許容 | ZAP-FR-013 |
| `openTroveWithUsdc(OpenTroveParams, minUsdsOut, minSUsdsOut) → troveId` | external payable nonReentrant | N | Sky route open（USDC→USDS→sUSDS→dUSDS） | ZAP-FR-014 |
| `openTroveWithUsdcAndReferral(OpenTroveParams, minUsdsOut, minSUsdsOut, referralCode) → troveId` | external payable nonReentrant | N | Sky route open ＋ referral | ZAP-FR-014 |
| `addCollWithUsdc(troveId, usdcAmount, minUsdsOut, minSUsdsOut)` | external nonReentrant | N | Sky route 増担保 | ZAP-FR-014 |
| `openTroveWithNativeEth(OpenTroveParams, minWstEthOut) → troveId` | external payable nonReentrant | N | native ETH route open（ETH→stETH→wstETH→dwstETH） | ZAP-FR-015 |
| `openTroveWithNativeEthAndReferral(OpenTroveParams, minWstEthOut, referralCode) → troveId` | external payable nonReentrant | N | native ETH route open ＋ referral | ZAP-FR-015 |

---

## 6. 機能要件（FR）

### ZAP-FR-001: openTroveWithRawETH（open への委譲）

- **Type**: Functional ｜ **Source**: Product-Overview「Zapper（UX Router）」/ `IZapper` 規定
- **シグネチャ**: `openTroveWithRawETH(OpenTroveParams _params) payable returns (uint256 troveId)`
- **目的**: `IZapper` 規定の関数名を override し、`openTroveWithRawETHAndReferral(_params, bytes32(0))` へ委譲する（referralCode = `bytes32(0)`）。
- **権限**: permissionless（実体の権限・manager 設定は委譲先 [ZAP-FR-002](#zap-fr-002-opentrovewithrawethandreferralopen--referral) が行う）。
- **事前条件（Checks）**: 委譲先に従う。
- **動作（Effects）**: `openTroveWithRawETHAndReferral(_params, bytes32(0))` を呼び、戻り値 `troveId` をそのまま返す。
- **revert / 早期 return**: 委譲先（[ZAP-FR-002](#zap-fr-002-opentrovewithrawethandreferralopen--referral)）に従う。
- **発火イベント**: なし（referral=`bytes32(0)` のため `ReferralDeposit` も発火しない）。
- **設計上のポイント**: 既存ウォレット / SDK が `IZapper` の標準名で呼べるよう、referral なしのエントリを別名で用意する。
- **Verification**: unit（委譲先と同一 troveId を返す）。

### ZAP-FR-002: openTroveWithRawETHAndReferral（open ＋ referral）

- **Type**: Functional ｜ **Source**: Product-Overview「Zapper / referral」/ §1.1 フロー圧縮
- **シグネチャ**: `openTroveWithRawETHAndReferral(OpenTroveParams _params, bytes32 _referralCode) payable nonReentrant returns (uint256 troveId)`
- **目的**: Underlying を pull → dToken 化 → コアに担保として渡して Trove を open し、mint された JPYdf を user へ転送する 1 Tx エントリ。担保分 ETH は受け取らず、gas compensation 分の ETH ちょうどのみ受領する。
- **権限**: permissionless（Trove は `msg.sender` を owner として作成し、`_params.owner` は `msg.sender` と一致しなければならない。内部で一時的に Zapper を manager にし、最後にユーザー指定 manager / receiver へ委譲）。
- **事前条件（Checks）**:
  - `msg.value == ETH_GAS_COMPENSATION`（担保分の ETH は受け取らない）
  - `_params.owner == msg.sender`
  - batch 整合：`_params.batchManager == address(0) || _params.annualInterestRate == 0`
  - `underlyingToken` の `_params.collAmount` 分を Zapper が pull できる approve / 残高（呼出側で確保）
- **動作（Effects）**:
  1. `WETH.deposit{value: msg.value}()` — 受領した ETH を WETH 化（gas compensation 原資）
  2. 共通内部処理 `_openTroveWithUnderlying(_params, _referralCode)` を実行（下記 a〜g）
  - **`_openTroveWithUnderlying` の手順**:
    - a. `underlyingToken.safeTransferFrom(msg.sender, address(this), _params.collAmount)` — Underlying を pull（`collAmount` は **Underlying 建て**）
    - b. `dTokenAmount = collateralVault.deposit(_params.collAmount)` — Underlying を dToken 化（dToken は Zapper 宛に mint）
    - c. `index = _getTroveIndex(_params.ownerIndex)` — `msg.sender` を index に織り込む（troveId 導出に必須）
    - d. `borrowerOperations.openTrove(owner, index, dTokenAmount, jpydfAmount, …, addManager=address(this), removeManager=address(this), receiver=address(this))` で Trove を user owner として作成（担保は Zapper が保持する dToken）。`batchManager != 0` の場合は `openTroveAndJoinInterestBatchManager` を使用
    - e. `jpydfToken.transfer(msg.sender, _params.jpydfAmount)` — mint された JPYdf を user へ転送
    - f. `_setAddManager` / `_setRemoveManagerAndReceiver` で**ユーザー指定の** manager / receiver に設定し直す（一時的に Zapper を manager にしていたのを委譲）
    - g. `_referralCode != bytes32(0)` の場合のみ `ReferralDeposit(msg.sender, troveId, collAmount, dTokenAmount, jpydfAmount, referralCode)` を発火（[ZAP-EVT-001](#zap-evt-001-referraldeposit)）
- **revert / 早期 return**: `msg.value != ETH_GAS_COMPENSATION`；`_params.owner != msg.sender`；batch 整合違反；`collAmount` 不足の approve / 残高；`CollateralVault.deposit` の cap 超過・Underlying 未確定（`TokenInfoNotSet`）；MIN_DEBT 未満の `jpydfAmount`（値・検査とも [Liquity-v2-Core-Spec.md](./Liquity-v2-Core-Spec.md) CORE-LIB-FR-002 / CORE-BO-FR-001）等で revert。
- **発火イベント**: `ReferralDeposit`（`_referralCode != bytes32(0)` のときのみ・[ZAP-EVT-001](#zap-evt-001-referraldeposit)）。コア側 open 関連イベントは [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md)。
- **設計上のポイント**:
  - **本 FR では native ETH 担保を受け取らない**：担保は常に `underlyingToken` を ERC-20 として pull し、`msg.value` は gas compensation 専用である。WETH を Underlying とするブランチではユーザーが WETH（ERC-20）を approve して渡し、native ETH のみを持つユーザー向け UX は frontend が事前に `WETH.deposit` を挿入することで扱う。native ETH を直接受け取る payable collateral entrypoint は dwstETH ブランチの on-ramp（[ZAP-FR-015](#zap-fr-015-native-eth-on-rampethstethwstethdwsteth)）だけに閉じ、本 FR の経路には追加しない（[ZAP-TBD-005](#zap-tbd-005)）。
  - **残余ゼロ**：open フローでは `deposit` が返した dToken を `openTrove` がそのまま全量 pull し、mint された JPYdf も全額 user へ transfer されるため Zapper に残余は発生しない。よって `_returnLeftovers` の呼び出しは不要（[ZAP-INV-004](#8-不変条件inv)）。
- **Verification**: unit（`msg.value` 厳格一致・batch 整合・referral 発火条件）, integration（Underlying→dToken→openTrove→JPYdf 転送の通し・残余ゼロ）。

### ZAP-FR-003: openTroveWithUnderlyingPermit（permit open への委譲）

- **Type**: Functional ｜ **Source**: §1.1「完全 1 Tx 化」/ [DTKN-FR-007](./dToken.md)（permit 依存）
- **シグネチャ**: `openTroveWithUnderlyingPermit(OpenTroveParams _params, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) payable nonReentrant returns (uint256)`
- **目的**: `openTroveWithUnderlyingPermitAndReferral(_params, _deadline, _v, _r, _s, bytes32(0))` へ委譲する（referralCode = `bytes32(0)`）。
- **権限**: permissionless（実体は委譲先 [ZAP-FR-004](#zap-fr-004-opentrovewithunderlyingpermitandreferralpermit-open--referral)）。
- **事前条件（Checks）**: 委譲先に従う。
- **動作（Effects）**: 委譲先を呼び、戻り値をそのまま返す。
- **revert / 早期 return**: 委譲先に従う。
- **発火イベント**: なし（referral=`bytes32(0)`）。
- **設計上のポイント**: permit 経路にも referral なしの標準エントリを用意する。
- **Verification**: unit（委譲先と同一戻り値）。

### ZAP-FR-004: openTroveWithUnderlyingPermitAndReferral（permit open ＋ referral）

- **Type**: Functional ｜ **Source**: §1.1「完全 1 Tx 化」/ [DTKN-FR-007](./dToken.md) permit 経路
- **シグネチャ**: `openTroveWithUnderlyingPermitAndReferral(OpenTroveParams _params, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s, bytes32 _referralCode) payable nonReentrant returns (uint256)`
- **目的**: [ZAP-FR-002](#zap-fr-002-opentrovewithrawethandreferralopen--referral) と同一だが、Underlying pull の前に **EIP-2612 permit** を実行し、Underlying の事前 approve を不要にする（完全 1 Tx）。
- **権限**: permissionless（Trove owner = `msg.sender`）。
- **事前条件（Checks）**:
  - `msg.value == ETH_GAS_COMPENSATION`、batch 整合（[ZAP-FR-002](#zap-fr-002-opentrovewithrawethandreferralopen--referral) と同）
  - `underlyingToken` が EIP-2612 permit 対応であること（前提）
- **動作（Effects）**:
  1. `IERC20Permit(underlyingToken).permit(msg.sender, address(this), _params.collAmount, _deadline, _v, _r, _s)` を `try/catch` で実行する。permit が失敗した場合でも、同じ permit が第三者に先行実行された等により既に `allowance(msg.sender, address(this)) >= _params.collAmount` なら続行する。不足なら `CollateralYieldZapper__PermitFailed` で revert。
  2. `WETH.deposit{value: msg.value}()`
  3. `_openTroveWithUnderlying(_params, _referralCode)`（[ZAP-FR-002](#zap-fr-002-opentrovewithrawethandreferralopen--referral) と同一の a〜g）
- **revert / 早期 return**: `msg.value` 不一致；batch 整合違反；permit 失敗かつ Zapper への allowance 不足（`CollateralYieldZapper__PermitFailed`）；以降は [ZAP-FR-002](#zap-fr-002-opentrovewithrawethandreferralopen--referral) と同。
- **発火イベント**: `ReferralDeposit`（`_referralCode != bytes32(0)` のとき・[ZAP-EVT-001](#zap-evt-001-referraldeposit)）。
- **設計上のポイント / 注意**:
  - Permit を使えるのは EIP-2612 対応 Underlying（USDC 等）に限る。
  - EIP-2612 permit は第三者が先に提出できる。先行実行で nonce が消費されても allowance が残っていれば open を続行し、署名者の一括操作を grief できないようにする。
  - Permit 非対応 token / EOA では、`try/catch` が ABI デコード不能・no-code 呼び出しを捕捉できず revert する場合がある。
  - 非対応トークンでは [ZAP-FR-001](#zap-fr-001-opentrovewithrawethopen-への委譲)（事前 approve 経路）を使う（[ZAP-TBD-006](#zap-tbd-006)）。
- **Verification**: unit（permit 成功で approve 不要 open・permit 失敗 revert）, integration（permit 対応 Underlying の完全 1 Tx）。

### ZAP-FR-005: addCollWithUnderlying（増担保・Underlying 建て）

- **Type**: Functional ｜ **Source**: §1.2 担保操作
- **シグネチャ**: `addCollWithUnderlying(uint256 _troveId, uint256 _underlyingAmount) nonReentrant`
- **目的**: Underlying 建てで既存 Trove に増担保する。
- **権限**: owner または add manager のみ（`AddRemoveManagers` で検査・[ZAP-SEC-002](#zap-sec-002-受益者と実行者の整合managerreceiver)）。
- **事前条件（Checks）**: 呼出者が owner / add manager；`underlyingToken` の `_underlyingAmount` を pull 可能。
- **動作（Effects）**:
  1. `underlyingToken` を pull
  2. `collateralVault.deposit` で dToken 化
  3. `borrowerOperations.addColl(_troveId, dTokenAmount)`
- **revert / 早期 return**: 権限なし；pull 不能；`deposit` の cap 超過・未確定。
- **発火イベント**: なし（コア側 `addColl` 関連は [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md)）。
- **設計上のポイント**: 増担保は出力トークンを伴わないため残余は発生しない。
- **Verification**: unit（owner/add manager 限定）, integration（Underlying→dToken→addColl）。

### ZAP-FR-006: withdrawCollToUnderlying（減担保・Underlying で受取）

- **Type**: Functional ｜ **Source**: §1.2 担保操作
- **シグネチャ**:
  - `withdrawCollToUnderlying(uint256 _troveId, uint256 _dTokenAmount) nonReentrant returns (uint256 underlyingReceived, uint256 requestId)`
  - `withdrawCollToUnderlyingWithMin(uint256 _troveId, uint256 _dTokenAmount, uint256 _minUnderlyingReceived) nonReentrant returns (uint256 underlyingReceived, uint256 requestId)`
- **目的**: Trove から担保 dToken を引き出し、Underlying に交換して endUser へ渡す。
- **権限**: owner または remove manager のみ（receiver を取得）。
- **事前条件（Checks）**: `_requireZapperIsReceiver` で Zapper が当該 Trove の receiver であることを確認（[ZAP-SEC-002](#zap-sec-002-受益者と実行者の整合managerreceiver)）。
- **動作（Effects）**:
  1. `borrowerOperations.withdrawColl(_troveId, _dTokenAmount)` で dToken を Zapper に引き出し
  2. `_redeemDTokenToUnderlying` は `redeemable = convertToDToken(convertToUnderlying(_dTokenAmount))` と `dust = _dTokenAmount - redeemable` を求める。`redeemable > 0` の場合だけ `collateralVault.redeem(redeemable, receiver)` で Underlying に交換し、`dust > 0` は dToken のまま receiver へ返す。
  3. `WithMin` は即時の `underlyingReceived`（queue 分および dToken dust を含まない）が `_minUnderlyingReceived` 未満なら全処理を revert する。`underlyingReceived` は Vault の nominal transfer 引数ではなく receiver の送出前後 `balanceOf` 差分であり、fee-on-transfer Underlying でも実増分を保証する。非 `WithMin` は下限 0 として同じ内部処理に委譲する。`redeemable == 0` では Vault 呼出を省略し、下限 0 の場合だけ全量を dToken dust として返す。
- **revert / 早期 return**: 権限なし；Zapper が receiver でない。
- **発火イベント**: なし。遅延償還時の追跡は §7.2 のとおり Vault の `WithdrawRequested` を用いる（[CollateralVault 要件定義](./CollateralVault.md)）。
- **設計上のポイント**: `_dTokenAmount` は **dToken 建て**。Underlying 建てで指定したい場合はフロントエンドが [DTKN-FR-003](./dToken.md) `convertToDToken` で換算する。Underlying の基底単位未満は切り捨てず dToken として receiver に返すため、6/8dec Underlying でも Vault の exact-conversion guard を維持したまま固定化を防ぐ。queue が発生しても dust は queue に含めず同一 Tx で返す。`redeem` の `requestId` は再 emit しない（[ZAP-TBD-001](#zap-tbd-001)）。
- **Verification**: unit（owner/remove manager・receiver・受取下限・fee-on-transfer receiver 実増分・6/8/18dec・only-dust・queue+dust）, integration（withdrawColl→redeem）。

### ZAP-FR-007: withdrawJpydf（借入増）

- **Type**: Functional ｜ **Source**: §1.2 債務操作
- **シグネチャ**: `withdrawJpydf(uint256 _troveId, uint256 _jpydfAmount, uint256 _maxUpfrontFee) nonReentrant`
- **目的**: 既存 Trove から JPYdf を追加借入し receiver へ渡す。
- **権限**: owner または remove manager のみ（Zapper が receiver であること必須）。
- **事前条件（Checks）**: 権限；`_requireZapperIsReceiver`。
- **動作（Effects）**:
  1. `borrowerOperations.withdrawJpydf(_troveId, _jpydfAmount, _maxUpfrontFee)`
  2. `jpydfToken.transfer(receiver, _jpydfAmount)`
- **revert / 早期 return**: 権限なし；Zapper が receiver でない；`_maxUpfrontFee` 超過（🔵 コア）。
- **発火イベント**: なし（コア側）。
- **設計上のポイント**: 借入分はそのまま receiver へ転送し Zapper に滞留させない。
- **Verification**: unit（権限・receiver 検査）, integration（withdrawJpydf→transfer）。

### ZAP-FR-008: repayJpydf（返済）

- **Type**: Functional ｜ **Source**: §1.2 債務操作
- **シグネチャ**: `repayJpydf(uint256 _troveId, uint256 _jpydfAmount) nonReentrant`
- **目的**: JPYdf を pull して既存 Trove を返済し、過剰分を user へ返却する。
- **権限**: owner または add manager のみ。
- **事前条件（Checks）**: 権限；`jpydfToken` の `_jpydfAmount` を pull 可能。
- **動作（Effects）**:
  1. `_setInitialTokensAndBalances(collToken, jpydfToken)` で残高基準を記録（[ZAP-SEC-003](#zap-sec-003-残余の返却固定化回避)）
  2. `jpydfToken.transferFrom(msg.sender, this, _jpydfAmount)` で JPYdf を pull
  3. `borrowerOperations.repayJpydf(_troveId, _jpydfAmount)`
  4. `_returnLeftovers` で過剰返済分（返しきれなかった JPYdf 等）を user へ返却
- **revert / 早期 return**: 権限なし；pull 不能。
- **発火イベント**: なし（コア側）。
- **設計上のポイント**: 返済額がコア側で丸められても残余を `_returnLeftovers` で確実に返す（Zapper 滞留ゼロ＝[ZAP-INV-003](#8-不変条件inv)）。
- **Verification**: unit（add manager 限定・過剰返済の残余返却）, integration。

### ZAP-FR-009: adjustTroveWithUnderlying（担保＋債務の同時調整）

- **Type**: Functional ｜ **Source**: §1.2 Trove 調整
- **シグネチャ**:
  - `adjustTroveWithUnderlying(uint256 _troveId, uint256 _underlyingChange, bool _isCollIncrease, uint256 _jpydfChange, bool _isDebtIncrease, uint256 _maxUpfrontFee) nonReentrant returns (uint256 dTokenChange, uint256 underlyingReceived, uint256 requestId)`
  - `adjustTroveWithUnderlyingWithMin(uint256 _troveId, uint256 _underlyingChange, bool _isCollIncrease, uint256 _jpydfChange, bool _isDebtIncrease, uint256 _maxUpfrontFee, uint256 _minUnderlyingReceived) nonReentrant returns (uint256 dTokenChange, uint256 underlyingReceived, uint256 requestId)`
  - `adjustZombieTroveWithUnderlying(uint256 _troveId, uint256 _underlyingChange, bool _isCollIncrease, uint256 _jpydfChange, bool _isDebtIncrease, uint256 _upperHint, uint256 _lowerHint, uint256 _maxUpfrontFee) nonReentrant returns (uint256 dTokenChange, uint256 underlyingReceived, uint256 requestId)`
  - `adjustZombieTroveWithUnderlyingWithMin(uint256 _troveId, uint256 _underlyingChange, bool _isCollIncrease, uint256 _jpydfChange, bool _isDebtIncrease, uint256 _upperHint, uint256 _lowerHint, uint256 _maxUpfrontFee, uint256 _minUnderlyingReceived) nonReentrant returns (uint256 dTokenChange, uint256 underlyingReceived, uint256 requestId)`
- **目的**: 担保（Underlying 建て）と債務（JPYdf）を 1 Tx で同時調整する。zombie Trove についてはコア `adjustZombieTrove` の hint 付き entrypoint を同じ Underlying ベースで提供する。
- **権限**: `_checkAdjustTroveManagers` で権限・receiver を決定（増担保・返済は add 系、減担保・借入は remove 系）。
- **事前条件（Checks）**: 上記権限決定；`_setInitialTokensAndBalances(collToken, jpydfToken)` で残高基準を記録。
- **動作（Effects）**（pre / 本体前の担保量決定 / 本体 / post）:
  1. **pre**（`_adjustTroveWithUnderlyingPre`）：権限・receiver 決定と残高基準記録。`!_isDebtIncrease && _jpydfChange > 0` なら返済用 JPYdf を pull。
  2. **本体前の担保量決定**：`_underlyingChange > 0` のとき、増担保では Underlying を pull して `collateralVault.deposit` の戻り値を `dTokenChange` とし、減担保では `dToken.convertToDToken(_underlyingChange)` を `dTokenChange` とする。
  3. **本体**：通常 entrypoint は `borrowerOperations.adjustTrove(_troveId, dTokenChange, _isCollIncrease, _jpydfChange, _isDebtIncrease, _maxUpfrontFee)`、zombie entrypoint は `borrowerOperations.adjustZombieTrove(_troveId, dTokenChange, _isCollIncrease, _jpydfChange, _isDebtIncrease, _upperHint, _lowerHint, _maxUpfrontFee)` を呼ぶ。
  4. **post**（`_adjustTroveWithUnderlyingPost`）：減担保で `dTokenChange > 0` なら、[ZAP-FR-006](#zap-fr-006-withdrawcolltounderlying減担保underlying-で受取) と同じ正規化を行い、Underlying の基底単位で表現可能な dToken のみを redeem、端数は dToken のまま receiver へ返す。`WithMin` では即時 `underlyingReceived` が下限未満なら revert する。`_isDebtIncrease && _jpydfChange > 0` なら借入分 JPYdf を receiver へ transfer。最後に `_returnLeftovers`。
- **revert / 早期 return**: 権限なし；pull 不能；`deposit` の cap/未確定；`_maxUpfrontFee` 超過（🔵 コア）。
- **発火イベント**: なし（コア側）。減担保の遅延償還追跡は Vault の `WithdrawRequested`（§7.2）。
- **設計上のポイント**:
  - 増担保時は `collateralVault.deposit` の戻り値を `dTokenChange` として直接使う（[ZAP-TBD-002](#zap-tbd-002) 解決）。`convertToDToken` は乗算のみで厳密だが、増担保経路では再計算しない。
  - 減担保時は `convertToDToken(_underlyingChange)` 分の dToken を引き出して redeem する。通常この値は Underlying 基底単位に厳密変換できるが、共通 helper は非整数量にも対応し、端数 dust を Vault/Zapper に残さず receiver へ dToken で返す。
  - `adjustZombieTrove` 系（zombie Trove の調整）は実装済みで、通常 adjust と同じ pre/post・残余返却・受取下限の扱いに従う。
- **Verification**: unit（4 象限：増減担保 × 借入返済の権限・受渡・zombie hint 経路・受取下限）, integration（同時調整の通し・残余ゼロ）。

### ZAP-FR-010: closeTroveToUnderlying（close・JPYdf 保有時）

- **Type**: Functional ｜ **Source**: §1.2 クローズ
- **シグネチャ**:
  - `closeTroveToUnderlying(uint256 _troveId) nonReentrant returns (uint256 underlyingReceived, uint256 requestId)`
  - `closeTroveToUnderlyingWithMin(uint256 _troveId, uint256 _minUnderlyingReceived) nonReentrant returns (uint256 underlyingReceived, uint256 requestId)`
- **目的**: ユーザーが JPYdf を保有しているケースで、返済用 JPYdf を pull して Trove をクローズし、担保を Underlying に交換して返す。
- **権限**: owner または remove manager のみ（Zapper が receiver であること必須）。
- **事前条件（Checks）**: 権限；`_requireZapperIsReceiver`。
- **動作（Effects）**:
  1. `trove = troveManager.getLatestTroveData(_troveId)` で `entireDebt` を取得し、`jpydfToken.transferFrom(msg.sender, this, trove.entireDebt)` で返済用 JPYdf を pull
  2. `borrowerOperations.closeTrove(_troveId)` → 担保 dToken が Zapper に返却される
  3. close 前に取得した `trove.entireColl` を [ZAP-FR-006](#zap-fr-006-withdrawcolltounderlying減担保underlying-で受取) と同じ正規化へ渡す。Underlying 基底単位で表現可能な最大 dToken 量を Vault で redeem し、残る sub-unit dust は dToken のまま receiver へ返す。`WithMin` は即時 `underlyingReceived`（queue/dust を含まない）が下限未満なら全処理を revert する。
  4. gas compensation（`ETH_GAS_COMPENSATION`）を `WETH.withdraw` で ETH 化し receiver へ送付（`safeTransferETH` が失敗時に revert＝[ZAP-SEC-007](#zap-sec-007-gas-compensation-eth-送付の失敗時-revert)）
- **revert / 早期 return**: 権限なし；Zapper が receiver でない；JPYdf 残高/approve 不足；受取 Underlying 下限割れ；ETH 送付失敗。
- **発火イベント**: なし。遅延償還時は Vault の `WithdrawRequested`（§7.2）。
- **設計上のポイント**: redemption 等により `entireColl` が 6/8dec Underlying の換算単位と非整合でも close を妨げない。Vault の exact-conversion guard は緩和せず、Zapper が redeemable 部分と dToken dust を分離する。`requestId` は再 emit しない（[ZAP-TBD-001](#zap-tbd-001)）。close が即時に Underlying を返すとは限らない点は §7.4。
- **Verification**: unit（権限・receiver・受取下限・gas comp・6dec redemption 後の非整数担保 close と dust 返却）, integration（close→redeem→ETH 返却）。

### ZAP-FR-011: Day-1 ABI から削除済み（Flash Loan close / collateral-funded close）

- **Type**: Deferred / Removed from Day-1 production ABI ｜ **由来**: fresh deploy simplification
- **現行仕様**: `CollateralYieldZapper` は `closeTroveFromCollateral` を公開しない。ユーザーが JPYdf を保有していない状態で担保を原資に close する経路、collateral-funded repay、Multiply は Day-1 production ABI に含めない。
- **理由**:
  1. Day-1 の JPYdf liquidity は JPYdf deploy / 発行後に組む JPYdf/USDC Uniswap v4 のみであり、非 USDC collateral からの reverse route は asset-specific pre-leg と fork evidence が必要である。
  2. dToken collateral は DEX 市場を持たないため、担保原資 close は Underlying / dToken / JPYdf / Vault buffer を跨ぐ複合経路になり、監査対象の blast radius が大きい。
  3. fresh deploy のため、未使用の legacy/helper compatibility ABI を維持する必要がない。
- **実装上の要件**: production `contracts/src` / generated ABI / deploy script / app flow に `closeTroveFromCollateral`、flash-loan provider dependency、Balancer Flash Loan adapter、fail-fast exchange placeholder dependency が存在してはならない。
- **将来追加条件**: 担保原資 close / Multiply は、Balancer や削除済み Flash Loan callback を再利用せず、新しい audited entrypoint として追加する。route 条件は [ZAP-TBD-010](#zap-tbd-010) を正とする。
- **Verification**: manual / build artifact review（ABI absence、deploy wiring absence、frontend flow absence）。

### ZAP-FR-012: Day-1 ABI から削除済み（Flash Loan callback）

- **Type**: Deferred / Removed from Day-1 production ABI ｜ **由来**: fresh deploy simplification
- **現行仕様**: `receiveFlashLoanOnCloseTroveFromCollateral` / `CloseTroveParams` / `IFlashLoanReceiver` / `IFlashLoanProvider` / Balancer Flash Loan adapter は production `src` と ABI に存在しない。Balancer は Day-1 だけでなく将来計画にも含めない。
- **セキュリティ意図**: callback surface 自体を持たないことで、callback spoofing / provider misbinding / flash-loan repayment path を Day-1 監査対象から外す。
- **将来方針**: Flash Loan callback / Balancer adapter を復活させる前提は置かない。atomic liquidity が必要な別機能は、新規 scope として Balancer 非依存で再設計する。
- **Verification**: manual / build artifact review（callback selector absence、interface absence、deploy dependency absence）。

### ZAP-FR-013: receive（WETH からの ETH 受領）

- **Type**: Functional ｜ **Source**: §1.4 Leverage 非対応 / gas compensation 送付
- **シグネチャ**: `receive() external payable`
- **目的**: `WETH.withdraw`（gas compensation の ETH 化）で受け取る ETH のみを許容し、WETH 以外からの ETH 送付を拒否する。
- **権限**: `msg.sender == WETH` の ETH 受領のみ。
- **事前条件（Checks）**: `msg.sender == address(WETH)`。
- **動作（Effects）**: WETH からの ETH を受領するのみ。
- **revert / 早期 return**: WETH 以外からの ETH を `CollateralYieldZapper__OnlyWETH` で revert。
- **発火イベント**: なし。
- **設計上のポイント**: dToken 担保でのレバレッジが必要になれば別コントラクト（例：`LeverageCollateralYieldZapper`）として将来設計する（[ZAP-TBD-004](#zap-tbd-004)）。旧 leverage callback / router interface は Day-1 production `src` から削除済み。
- **Verification**: unit（`receive()` が `WETH.withdraw` の ETH のみを受領）。

### ZAP-FR-014: ARCHIVED Sky USDC route variant（USDC→USDS→sUSDS→dUSDS）

- **Type**: Functional ｜ **Source**: Sky / MakerDAO 系 collateral route 要件
- **対象**: `SkyUsdcSUsdsYieldZapper`
- **シグネチャ**:
  - `openTroveWithUsdc(OpenTroveParams _params, uint256 _minUsdsOut, uint256 _minSUsdsOut) payable returns (uint256 troveId)`
  - `openTroveWithUsdcAndReferral(OpenTroveParams _params, uint256 _minUsdsOut, uint256 _minSUsdsOut, bytes32 _referralCode) payable returns (uint256 troveId)`
  - `addCollWithUsdc(uint256 _troveId, uint256 _usdcAmount, uint256 _minUsdsOut, uint256 _minSUsdsOut) returns (uint256 usdsAmount, uint256 susdsAmount, uint256 dTokenAmount)`
- **目的**: USDC を直接 UX 入力として受け取り、Sky route を通じて dUSDS collateral Trove を open / 増担保する。
- **権限**: open は permissionless、増担保は owner または add manager のみ（親 `CollateralYieldZapper` と同じ）。
- **事前条件（Checks）**:
  - open 系は `msg.value == ETH_GAS_COMPENSATION`、batch 整合（[ZAP-FR-002](#zap-fr-002-opentrovewithrawethandreferralopen--referral) と同じ）
  - constructor で `sUSDS.asset() == USDS` を assert
  - constructor で route の decimals 前提を固定する：`USDC.decimals() == 6`、`USDS.decimals() == 18`、`sUSDS.decimals() == 18`
  - `collAmount` / `usdcAmount` は 0 であってはならない
  - USDC→USDS converter の返り値と USDS 実増分が一致し、USDC→USDS の結果が `_minUsdsOut` 以上、USDS→sUSDS deposit の結果が `_minSUsdsOut` 以上
  - USDC→USDS converter、USDS→sUSDS vault、sUSDS→CollateralVault deposit の各段階で、Zapper の中間 token 残高が呼出前水準へ戻ること
- **動作（Effects）**:
  1. USDC を user から Zapper に pull
  2. USDC を converter に必要額だけ temporary approve し、`ISkyUsdcSUsdsConverter.convertUsdcToUsds(usdcReceived, minUsdsOut, address(this))` で USDS 化した後、allowance を 0 に戻す。converter 返り値の USDS 量は Zapper の USDS 実増分と照合する
  3. USDS を ERC4626 sUSDS vault に必要額だけ temporary approve し、USDS を deposit して sUSDS shares を受領した後、allowance を 0 に戻す
  4. `CollateralVault.deposit(susdsAmount)` で dUSDS 化
  5. open 系は dUSDS を担保として Trove を作成し、mint された JPYdf を user へ転送。増担保は既存 Trove に dUSDS を追加
- **revert / 早期 return**:
  - `collAmount == 0` / `usdcAmount == 0`
  - USDC / USDS / sUSDS decimals 不一致、USDC pull 不能、converter 側 revert
  - converter 返り値と USDS 実増分の不一致（`SkyUsdcSUsdsYieldZapper__UsdsAmountMismatch`）
  - `usdsAmount < minUsdsOut`
  - `susdsAmount == 0 || susdsAmount < minSUsdsOut`
  - 中間 token 残高が呼出前水準に戻らない場合
  - 親 Zapper / Liquity Core / CollateralVault 由来の revert
- **発火イベント**:
  - `SkyUsdcRouteDeposit(user, troveId, usdcAmount, usdsAmount, susdsAmount, dTokenAmount, referralCode)`
  - `SkyUsdcRouteAddColl(user, troveId, usdcAmount, usdsAmount, susdsAmount, dTokenAmount)`
  - `_referralCode != bytes32(0)` の open では親と同じ `ReferralDeposit` も発火する。`underlyingAmount` はこの route の user-facing input である USDC amount とする。
  - `usdcAmount` は `_params.collAmount` / `_usdcAmount` の要求値ではなく、Zapper が balance-diff で確認した実受取 USDC 量とする。
- **設計上のポイント / 注意**:
  - Zapper は Sky PSM / LitePSM の具象 IF を持たない。Sky LitePSMWrapper の halt、手数料、decimals、実行先固定は `ISkyUsdcSUsdsConverter` adapter 側で吸収する。
  - `_params.collAmount` は Sky route では **USDC 建て入力額**であり、実際に Trove に入る collateral は route 後の `dTokenAmount` である。UI / SDK は `minUsdsOut` / `minSUsdsOut` を必ず指定する。
  - LitePSM / PSM 系では governance fee（`tin` / `tout`）や halt が入りうるため、USDC→USDS adapter は route 内で fee/halt を反映して revert し、Zapper 側でも `minUsdsOut` で最終受取量を再検査する。fee 上限を明示する具象 adapter では、`allowedTin` のようなパラメータを adapter 側で設ける。
  - USDC converter と sUSDS vault は外部 route 境界のため、Zapper は恒久的な max approval を持たせず、per-route の `forceApprove(amount)` / `forceApprove(0)` に限定する。
  - 親の withdraw / close 経路を継承するため、返却資産は sUSDS（= この branch の Underlying）である。USDC への逆変換 UX は別 route として設計する。
- **Verification**: unit / integration（USDC→USDS→sUSDS→dUSDS→open、slippage 下限、残余ゼロ、temporary allowance のゼロ戻し、referral）。

---

### ZAP-FR-015: native ETH on-ramp（ETH→stETH→wstETH→dwstETH）

- **Type**: Functional ｜ **Source**: dwstETH branch の onboarding 要件（Branch 0 の Underlying が WETH → wstETH へ移行したことに伴う）
- **対象**: `CollateralYieldZapper`（dwstETH ブランチに deploy し、route を有効化した instance のみ）
- **シグネチャ**:
  - `openTroveWithNativeEth(OpenTroveParams _params, uint256 _minWstEthOut) payable returns (uint256 troveId)`
  - `openTroveWithNativeEthAndReferral(OpenTroveParams _params, uint256 _minWstEthOut, bytes32 _referralCode) payable returns (uint256 troveId)`
- **目的**: native ETH 保有者が wstETH を自前で用意せずに dwstETH Trove を open できるようにする。既存の wstETH ERC-20 経路は変更しない。
- **権限**: permissionless（open のみ。増担保・返却系にこの route は存在しない）。
- **route 有効化**: constructor の `_expectedStEth` が正本である。`address(0)` を渡した instance では route が存在せず、全ての呼出が `CollateralYieldZapper__NativeEthRouteUnavailable` で revert する。非 zero を渡した場合は Underlying（wstETH）の `stETH()` getter を読み、値が一致しない、または contract でない場合は **deploy 時に revert** する。interface probe による暗黙有効化は行わない。
- **事前条件（Checks）**:
  - `stEthToken != address(0)`（= route が有効化された instance である）
  - `_params.collAmount != 0` かつ `msg.value == ETH_GAS_COMPENSATION + _params.collAmount`
  - open owner が `msg.sender` であること、batch 整合（[ZAP-FR-002](#zap-fr-002-opentrovewithrawethandreferralopen--referral) と同じ）
  - wrap 後の wstETH 実増分が `_minWstEthOut` 以上、かつ 0 でないこと
- **動作（Effects）**:
  1. `ETH_GAS_COMPENSATION` 分だけ `WETH.deposit` で WETH 化する（gas compensation の扱いは他 route と同一）
  2. 残りの `collAmount` を `stETH.submit{value: collAmount}(address(0))` で stake する。stETH 受領量は balance 差分で確定する
  3. stETH を wstETH へ必要額だけ `forceApprove` し `wrap` した後、allowance を 0 に戻す。wstETH 受領量は balance 差分で確定する
  4. Lido の share 丸めで 1〜2 wei の stETH が残る場合、呼出元へ sweep する
  5. `CollateralVault.deposit(wstEthAmount)` で dwstETH 化し、これを担保として Trove を作成、mint された JPYdf を user へ転送する
- **revert / 早期 return**:
  - route 無効 instance での呼出（`CollateralYieldZapper__NativeEthRouteUnavailable`）
  - `collAmount == 0` または `msg.value` 不一致（`CollateralYieldZapper__WrongETH`）
  - Lido 側の staking 停止・上限などによる `submit` の失敗は理由を包んで再送出（`CollateralYieldZapper__StEthSubmitFailed(reason)`）。このとき既存の wstETH 直接投入経路は影響を受けない
  - `wstEthAmount < _minWstEthOut` または `wstEthAmount == 0`（`CollateralYieldZapper__InsufficientWstEthOut`）
  - deploy 時の `stETH()` 不一致（`CollateralYieldZapper__StEthMismatch`）/ 非 contract（`CollateralYieldZapper__NotContract`）
  - 親 Zapper / Liquity Core / CollateralVault 由来の revert
- **発火イベント**:
  - `NativeEthRouteDeposit(user, troveId, ethAmount, stEthAmount, wstEthAmount, dTokenAmount, referralCode)`
  - `_referralCode != bytes32(0)` の場合は親と同じ `ReferralDeposit` も発火する。referral の `underlyingAmount` は ERC-20 経路と揃えて **wstETH 建て**（route 後の実受領量）とする
- **設計上のポイント / 注意**:
  - `_params.collAmount` はこの route では **stake する ETH の量**であり、実際に Trove に入る担保は route 後の `dTokenAmount` である。UI / SDK は `_minWstEthOut` を必ず指定する
  - stETH / wstETH への approval は per-route の `forceApprove(amount)` / `forceApprove(0)` に限定し、恒久 max approval を持たせない
  - 返却系（`withdrawCollToUnderlying` / `closeTroveToUnderlying`）は親の経路を継承するため、**払い戻しは wstETH** である。native ETH への逆変換 UX は提供しない
  - route は `nonReentrant` 下で実行され、`submit` 中の再入は guard で遮断される
- **Verification**: unit / integration（stake→wrap→open、slippage 下限、`submit` 停止時の typed revert と直接経路の非影響、`msg.value` 不一致、丸め残余の sweep、route 無効 instance、referral、close で wstETH が戻ること、再入遮断）。

---

## 7. 状態変数・会計モデル

`CollateralYieldZapper` は **stateless** で、永続的な可変状態を持たない。

- すべてのストレージは `immutable`。
- constructor で既存 `AddressesRegistry` と Zapper 専用引数（`collateralVault` / `underlyingToken`）から参照を固定する（[ZAP-INV-001](#8-不変条件inv)）。
- 各 Tx で一時保有した token は user / receiver へ返却し、Zapper 残高を滞留させない（[ZAP-INV-003](#8-不変条件inv)）。

**ストレージ（すべて `immutable`）**

| 変数 | 型 | 役割 |
| --- | --- | --- |
| `collateralVault` | `ICollateralVault` | Underlying ↔ dToken の deposit / redeem 先 |
| `dToken` | `IDToken` | dToken 本体。`convertToDToken` の換算に使用 |
| `underlyingToken` | `IERC20` | 当該ブランチの Underlying（WETH / WBTC / USDC 等） |
| `collToken` | `IERC20` | コアから見た担保トークン（= dToken の ERC-20 ビュー）。`collToken == dToken`（[ZAP-INV-002](#8-不変条件inv)） |

加えて `BaseZapper` 由来で `borrowerOperations` / `troveManager` / `WETH` / `jpydfToken` を `immutable` で保持する。

`SkyUsdcSUsdsYieldZapper` は上記に加えて、`usdcToken` / `usdsToken` / `susdsVault` / `usdcUsdsConverter` を `immutable` で保持する。親の `underlyingToken` は sUSDS であり、`collateralVault.underlying() == sUSDS`、`AddressesRegistry.collToken() == dUSDS`、`sUSDS.asset() == USDS`、route token decimals（USDC=6、USDS/sUSDS=18）を constructor で検証する。

**コンストラクタと approve**

constructor は参照を次のように固定する。

- `BaseZapper(_addressesRegistry)` から Core 参照を得る。
- `collateralVault` / `underlyingToken` は Zapper 専用引数から受ける。
- `collToken` は既存 `AddressesRegistry.collToken()` から取得する。
- `dToken` は `IDToken(address(collToken))` として導出し、追加 Registry getter は使わない。

そのうえで、以下の approve を **デプロイ時に 1 回だけ**行う（approve 先は信頼コンポーネントに限定＝[ZAP-SEC-006](#zap-sec-006-approve-先の信頼コンポーネント限定)）。

1. `WETH → BorrowerOperations`（gas compensation 用、`type(uint256).max`）
2. `dToken(collToken) → BorrowerOperations`（担保として渡すため、`max`）
3. `underlyingToken → CollateralVault`（deposit のため、`max`）
`SkyUsdcSUsdsYieldZapper` の `USDC → ISkyUsdcSUsdsConverter`、`USDS → sUSDS Vault` は route 実行時に必要額だけ temporary approve し、成功後に allowance を 0 に戻す。Sky PSM / LitePSM の具象コントラクトは adapter 内部で管理するため、Zapper から外部 route 境界へ恒久的な max allowance を渡さない。

**会計モデル**: Zapper は価値を会計しない中継体である。担保・債務の会計主体は Core（Trove）と Vault（buffer/principal）に属する。Zapper は「pull → 変換 → Core/Vault 呼出 → 残余返却」の一過性フローだけを司る。Underlying ↔ dToken の数量関係は [DTKN-FR-003](./dToken.md) に従う。

---

## 8. 不変条件（INV）

| ID | 不変条件 | 検証 |
| --- | --- | --- |
| ZAP-INV-001 | Zapper / route adapter は永続 business state を持たない。route / core 参照は constructor 確定後に変化せず、可変 storage は `ReentrancyGuard` の一時 lock 状態に限定する | manual（storage layout review） |
| ZAP-INV-002 | `collToken == dToken`（コアから見た担保 = dToken）。`dToken` は `AddressesRegistry.collToken()` から導出し、追加の `AddressesRegistry.dToken()` getter を要求しない | manual / unit（デプロイ assert・[ZAP-TBD-003](#zap-tbd-003)） |
| ZAP-INV-003 | 任意の外部関数の正常終了後、Zapper の `underlyingToken` / `collToken` / `jpydfToken` 残高は滞留しない（一時保有分は user/receiver へ返却・`_returnLeftovers`）。Underlying 基底単位未満の `collToken` は Vault に不正確な量を渡さず receiver へ dToken のまま返す | invariant |
| ZAP-INV-004 | open フロー（[ZAP-FR-002](#zap-fr-002-opentrovewithrawethandreferralopen--referral) / [ZAP-FR-004](#zap-fr-004-opentrovewithunderlyingpermitandreferralpermit-open--referral)）は構造上残余ゼロ（`deposit` の dToken を `openTrove` が全量 pull、JPYdf は全額 user へ transfer）→ `_returnLeftovers` 不要 | unit |
| ZAP-INV-005 | `ReferralDeposit` は open ケース（permit 版含む）で `_referralCode != bytes32(0)` のときのみ 1 度発火し、referralCode は Vault / コアへ渡らない | unit |
| ZAP-INV-006 | 旧 leverage callback / router surface は production `src` に存在しない | manual |
| ZAP-INV-007 | Day-1 production ABI に Flash Loan callback / provider dependency / Balancer adapter / fail-fast exchange placeholder が存在しない | manual（ABI・deploy wiring review） |
| ZAP-INV-008 | 全 user-facing 外部状態変更関数は `nonReentrant` で再入不可。callback 専用の非 `nonReentrant` 例外を作らない | manual（修飾子の網羅）/ unit |
| ZAP-INV-009 | Sky route の正常終了後、Zapper に USDC / USDS / sUSDS / dUSDS / JPYdf が滞留しない | unit / invariant |

---

## 9. セキュリティ要件（SEC）

### ZAP-SEC-001: user-facing 外部状態変更関数の nonReentrant

- Type: Security
- Statement: `ReentrancyGuard` を継承し、**すべての user-facing 外部状態変更関数に `nonReentrant`** を付さなければならない（Vault / Strategy / Token の組合せでの再入を考慮）。Day-1 ABI には Flash Loan callback を持たないため、callback 専用の非 `nonReentrant` 例外を作らない。
- Verification: manual（修飾子の網羅確認）, unit（再入攻撃の revert）。invariant=[ZAP-INV-008](#8-不変条件inv)

### ZAP-SEC-002: 受益者と実行者の整合（manager/receiver）

- Type: Security
- Statement: open 系では `_params.owner == msg.sender` を要求し、第三者が他人名義で Trove を開けないようにしなければならない。既存 Trove 操作では owner / add manager / remove manager・receiver の整合を `BaseZapper`（`AddRemoveManagers`）の共通関数で検査しなければならない。担保引出・借入・close 系では `_requireZapperIsReceiver` で「Zapper が当該 Trove の receiver であること」を確認し、第三者が他人の Trove を操作できてはならない。
- Verification: unit（第三者操作の revert・add/remove manager の役割分離）, manual

### ZAP-SEC-003: 残余の返却・固定化回避

- Type: Security
- Statement: 複数トークンを一時保有しうるケースでは `_setInitialTokensAndBalances` / `_setInitialBalancesAndReceiver` と `_returnLeftovers` を必ず用いる。対象は repay / adjust / close-with-JPYdf 等。Zapper に資産が滞留してはならない。dToken→Underlying 変換では Underlying 基底単位で表現可能な部分だけを Vault に渡し、残る dToken dust を receiver へ返す。open フローは構造上残余ゼロのため不要（[ZAP-INV-004](#8-不変条件inv)）。
- Verification: unit（過剰返済・端数の返却）, invariant=[ZAP-INV-003](#8-不変条件inv)

### ZAP-SEC-004: Day-1 ABI に Flash Loan callback が存在しないこと

- Type: Security
- Statement: `CollateralYieldZapper` / `BaseZapper` / `IZapper` / deploy script / generated ABI は Flash Loan callback、Flash Loan provider getter、Balancer Flash Loan adapter、fail-fast exchange placeholder dependency を公開してはならない。任意 callback spoofing や provider misbinding は、caller guard ではなく surface removal で排除する。
- Verification: manual（ABI・selector・deploy wiring review）, invariant=[ZAP-INV-007](#8-不変条件inv)

### ZAP-SEC-005: スリッページ保護

- Type: Security
- Statement: `withdrawCollToUnderlyingWithMin` / `adjustTroveWithUnderlyingWithMin` / `adjustZombieTroveWithUnderlyingWithMin` / `closeTroveToUnderlyingWithMin` は `_minUnderlyingReceived` でユーザーが当該 tx に実際に受け取る Underlying の下限を保証し、下回る場合は revert しなければならない。Vault の nominal 送金値ではなく receiver `balanceOf` 実増分を使い、queued claim と dToken dust は含めない。Day-1 ABI には swap-backed close の JPYdf swap slippage surface を持たない。
- Sky route では、`minUsdsOut` と `minSUsdsOut` の二段階で USDC→USDS 変換および USDS→sUSDS deposit の下限を保証しなければならない。USDC→USDS adapter が LitePSM / PSM を使う場合、fee/halt による不利な実行は adapter revert と `minUsdsOut` の両方で防ぐ。
- Verification: unit（下限割れ revert・fee-on-transfer receiver 実増分）, fork（swap 価格変動下の下限保証）

### ZAP-SEC-006: approve 先の信頼コンポーネント限定

- Type: Security
- Statement: コンストラクタの `max` approve（§7）先は信頼コンポーネント（BorrowerOperations / CollateralVault）に限定しなければならない。Zapper は永続残高を持たない前提のため、無制限 approve の影響を信頼境界内に閉じる。
- Sky route では `USDC → ISkyUsdcSUsdsConverter`、`USDS → sUSDS ERC4626 vault` が追加 approve 先となる。`SkyUsdcSUsdsConverter` は Sky 側 route adapter として監査対象に含め、deploy script が指定 LitePSMWrapper から concrete adapter を deploy することを検証する。
- v4 adapter の外部 router / pool approve は一時 allowance として扱う。
- Curve 系 adapter と Uniswap v3 route は Day-1 scope 外であり、本番 route には含めない。
- zero-first token 互換のため `forceApprove(amount)` を使い、swap 後に `forceApprove(0)` で残 allowance を消す。
- Uniswap v4 route は ERC-20→Permit2 allowance と Permit2→Universal Router allowance の双方を swap 後に 0 に戻す。
- exact-output swap は未使用 input allowance が残り得るため、残余 token 返却と allowance reset の両方を検証対象に含める。
- Verification: manual（approve 先レビュー）, unit（zero-first token + partial-spend router で allowance reset / 再 swap 成功）

### ZAP-SEC-007: gas compensation ETH 送付の失敗時 revert

- Type: Security
- Statement: `closeTroveToUnderlying`（[ZAP-FR-010](#zap-fr-010-closetrovetounderlyingclosejpydf-保有時)）での ETH 送付は `SafeTransferLib.safeTransferETH` を使い、送付失敗時に revert しなければならない。
- Verification: unit（送付失敗 revert）

> **資産一時保有の前提**: Zapper は一時的に dToken / JPYdf を保持し、minted JPYdf は `msg.sender = Zapper` で mint される設計のため、実装ミスが資産ロスに直結する。返却・転送・残高ゼロ化を徹底し、テスト・監査対象として明確に分離する（§7.1 リスク）。

---

## 10. ガバナンス・運用・アップグレード要件（GOV）

### ZAP-GOV-001: コア・Vault・dToken への非侵襲

- Statement: Zapper はオプショナルな外付けモジュールであり、Liquity コア・CollateralVault・dToken に Zapper 専用のフック / シグネチャ / 状態を一切追加してはならない（"No Router" 方針・コア改変ゼロ）。Vault の汎用 IF（`deposit` / `redeem` / `redeemWithPermit`）のみを使う。
- Verification: manual（コア・Vault diff レビュー）

### ZAP-GOV-002: stateless / 非アップグレード

- Statement: Zapper は stateless / `immutable` で proxy を持たない。ロジック差替が必要な場合は新コントラクトをデプロイし、フロントエンド / デプロイ設定側の参照を切り替える（既存 Zapper を in-place 改変しない）。
- Verification: manual（デプロイ構成レビュー）

### ZAP-GOV-003: referralCode のオフチェーン閉域

- Statement: referralCode は会計に関与しないオフチェーンメタデータとして Zapper 内部に閉じ、Vault / Liquity コアへ渡してはならない。集計はイベント（[ZAP-EVT-001](#zap-evt-001-referraldeposit)）のみで行う。
- Verification: manual（Vault/コアへの referral 引数が無いことのレビュー）

---

## 11. イベント・監視要件（EVT）

### ZAP-EVT-001: ReferralDeposit

- **イベント**: `ReferralDeposit(address indexed user, uint256 indexed troveId, uint256 underlyingAmount, uint256 dTokenAmount, uint256 jpydfAmount, bytes32 indexed referralCode)`
- **発火条件**: open ケース（[ZAP-FR-002](#zap-fr-002-opentrovewithrawethandreferralopen--referral) / Permit 版 [ZAP-FR-004](#zap-fr-004-opentrovewithunderlyingpermitandreferralpermit-open--referral)）で `_referralCode != bytes32(0)` の場合にのみ発火
- **index 対象**: `user` / `troveId` / `referralCode`（チャネル別・ユーザー別フィルタ用）
- **用途（off-chain）**: referralCode は Vault / Liquity コアには渡さず、Zapper 内部で保持してこのイベントとしてのみ記録される。subgraph / オフチェーン集計では `user` / `troveId` / `referralCode` をキーに、チャネル別・パートナー別の流入・負債ボリューム・レベニューシェア計算に利用する。`jpydfAmount` はユーザーが受領する借入額（`_params.jpydfAmount`）であり、upfront fee 込みの `entireDebt` ではない。

> **Vault 側の関連イベント**は [CollateralVault 要件定義](./CollateralVault.md) を参照。
> close / 担保引出の遅延償還追跡は、Vault の
> `WithdrawRequested(user, receiver indexed, requestId, amount, claimableAt)` を
> `receiver == userAddress` でフィルタして用いる。Zapper は `requestId` を再 emit しない（[ZAP-TBD-001](#zap-tbd-001)）。

---

## 12. 失敗時・異常系挙動（ERR）

**エラーカタログ（Zapper レベル）**

| エラー / 契機 | 発生条件 |
| --- | --- |
| `CollateralYieldZapper__ZeroAddress` / `CollateralYieldZapper__NotContract` | constructor で CollateralVault / Underlying のいずれかがゼロ、または未デプロイ contract |
| `CollateralYieldZapper__InvalidVaultDToken` / `CollateralYieldZapper__InvalidVaultUnderlying` | constructor で Vault の dToken / Underlying が Zapper 引数と一致しない |
| `CollateralYieldZapper__WrongETH` | open 系で gas compensation 分以外の ETH を送った（[ZAP-FR-002](#zap-fr-002-opentrovewithrawethandreferralopen--referral) / [ZAP-FR-004](#zap-fr-004-opentrovewithunderlyingpermitandreferralpermit-open--referral)） |
| `CollateralYieldZapper__OwnerMismatch` | open 系で `_params.owner != msg.sender`（Zapper 経由の他人名義 Trove 作成を拒否） |
| `CollateralYieldZapper__CannotChooseInterestIfJoiningBatch` | `_params.batchManager != 0 && _params.annualInterestRate != 0`（open 系） |
| `CollateralYieldZapper__PermitFailed` | permit 経路で permit が失敗し、かつ Zapper への既存 allowance が必要額未満（[ZAP-FR-004](#zap-fr-004-opentrovewithunderlyingpermitandreferralpermit-open--referral)）。permit 非対応トークン / EOA では捕捉できず revert する場合あり（[ZAP-TBD-006](#zap-tbd-006)） |
| 権限なし | owner / add manager / remove manager の不一致（[ZAP-SEC-002](#zap-sec-002-受益者と実行者の整合managerreceiver)） |
| Zapper が receiver でない | 担保引出・借入・close 系で `_requireZapperIsReceiver` 不成立 |
| `CollateralYieldZapper__InsufficientUnderlyingReceived` | `underlyingReceived < _minUnderlyingReceived`（[ZAP-SEC-005](#zap-sec-005-スリッページ保護)・各 redeem 系） |
| `CollateralYieldZapper__OnlyWETH` | `receive()` に WETH 以外から ETH が送られた |
| ETH 送付失敗 | gas compensation の ETH 送付失敗（[ZAP-SEC-007](#zap-sec-007-gas-compensation-eth-送付の失敗時-revert)） |
| `UniV4Exchange__ZeroAddress` / `UniV4Exchange__NotContract` / `UniV4Exchange__IdenticalTokens` | Uniswap v4 adapter constructor で route 構成が不正。collToken / JPYdf / Universal Router / Permit2 はデプロイ済み contract でなければならない |
| `UniV4Exchange__AmountTooLarge` | Universal Router / Permit2 用の `uint128` / `uint160` へ安全に縮小できない amount |
| `UniV4Exchange__InsufficientOutput` | v4 swap 後の実受取が指定下限未満 |
| `SkyUsdcSUsdsYieldZapper__ZeroAddress` / `SkyUsdcSUsdsYieldZapper__NotContract` | Sky route constructor で USDC / USDS / USDC→USDS converter のいずれかがゼロ、または未デプロイ contract。sUSDS vault は親 `CollateralYieldZapper__NotContract` で Underlying として検証する |
| `SkyUsdcSUsdsYieldZapper__ZeroAmount` | Sky route で `collAmount` / `usdcAmount` が 0 |
| `SkyUsdcSUsdsYieldZapper__InvalidSUsdsAsset` | Sky route constructor で `sUSDS.asset() != USDS` |
| `SkyUsdcSUsdsYieldZapper__InvalidUsdcDecimals` / `SkyUsdcSUsdsYieldZapper__InvalidUsdsDecimals` / `SkyUsdcSUsdsYieldZapper__InvalidSUsdsDecimals` | Sky route constructor で route token decimals が USDC=6、USDS/sUSDS=18 の前提に合わない |
| `SkyUsdcSUsdsYieldZapper__UsdsAmountMismatch` | Sky route で USDC→USDS converter の返り値と Zapper の USDS 実増分が一致しない |
| `SkyUsdcSUsdsYieldZapper__InsufficientUsdsOut` | Sky route で USDC→USDS 変換後の受取 USDS が `_minUsdsOut` 未満 |
| `SkyUsdcSUsdsYieldZapper__InsufficientSUsdsOut` | Sky route で USDS→sUSDS deposit 後の shares が 0 または `_minSUsdsOut` 未満 |
| `SkyUsdcSUsdsYieldZapper__UnexpectedTokenResidue` | USDC / USDS / sUSDS の中間 token 残高が route 呼出前水準へ戻らない |

**依存先由来の revert（伝播）**

| 契機 | 由来 |
| --- | --- |
| `CapExceeded` / `TokenInfoNotSet` | `CollateralVault.deposit`（placeholder ブランチ：`cap = 0` / Underlying 未確定。[dToken 要件定義](./dToken.md)）。UX 明示は [ZAP-TBD-008](#zap-tbd-008) |
| MIN_DEBT 未満 / `_maxUpfrontFee` 超過 / その他コア検査 | 🔵 `BorrowerOperations`（値・挙動は [Liquity-v2-Core-Spec.md](./Liquity-v2-Core-Spec.md)） |
| Sky adapter 側の halt / 手数料 / route 不成立 | `ISkyUsdcSUsdsConverter` 実装（[ZAP-FR-014](#zap-fr-014-sky-usdc-route-variantusdcusdsusdsdusds)） |
| Lido staking の停止 / 上限による `submit` 失敗 | Lido stETH（[ZAP-FR-015](#zap-fr-015-native-eth-on-rampethstethwstethdwsteth)。`CollateralYieldZapper__StEthSubmitFailed` で理由を包んで再送出し、wstETH 直接投入経路は影響を受けない） |

> **遅延償還の即時性**: `redeem` は Buffer 十分時のみ即時に Underlying を返す。不足時は遅延 `WithdrawRequest` となり、claim も Buffer 不足時は revert しうる（[CollateralVault 要件定義](./CollateralVault.md)）。close / 担保引出が即時に Underlying を返すとは限らない点を UX 設計で明示する（§7.4）。

---

## 13. 受け入れ基準・検証計画

各要件の合格条件 = 満たすべき**振る舞い**（テスト名・実行結果ではなく）。下表は受け入れ基準と検証手段の台帳。

**受け入れ基準（機能要件・振る舞いとして規定）**

1. **1 Tx 完結**：open / addColl / withdrawColl / adjust / zombie adjust / repay / withdrawJpydf / close（JPYdf 保有時）が、Underlying ベースで 1 Tx で完結する。
2. **dToken 隠蔽**：ユーザーは dToken を保有・approve・操作することなく、Underlying と JPYdf のみで全操作を完了できる。
3. **referral**：`_referralCode != bytes32(0)` の open でのみ `ReferralDeposit` が 1 度発火し、Vault / コアには referralCode が渡らない。
4. **Permit**：EIP-2612 対応 Underlying で、事前 approve なしに open が完結する。
5. **残余ゼロ／返却**：複数トークン一時保有ケースで `_returnLeftovers` により残余が user に返却され、Zapper に資産が滞留しない。open フローは残余が発生しない。
6. **権限**：owner / add manager / remove manager・receiver の整合が検査され、第三者が他人の Trove を操作できない。
7. **Reentrancy**：user-facing 外部状態変更関数が `nonReentrant`。Day-1 ABI に callback 専用の非 `nonReentrant` 例外が存在しない。
8. **Flash Loan close 不在**：`closeTroveFromCollateral` / Flash Loan callback / Flash Loan provider dependency / Balancer adapter / fail-fast exchange placeholder は production `src`・deploy wiring・generated ABI に存在しない。
9. **Leverage 非対応**：旧 leverage callback / router surface は production `src` に存在しない。
10. **Sky route**：USDC→USDS→sUSDS→dUSDS の open / addColl が 1 Tx で完結し、`minUsdsOut` / `minSUsdsOut` 未満なら revert、USDC / USDS / sUSDS / dUSDS / JPYdf が Zapper に滞留しない。

**検証台帳（要件 × 手段）**

| ID | 要件（要約） | 検証手段 |
| --- | --- | --- |
| ZAP-FR-001 | openTroveWithRawETH（referral=`bytes32(0)` 委譲） | unit |
| ZAP-FR-002 | open ＋ referral（Underlying→dToken→open→JPYdf 転送） | unit, integration |
| ZAP-FR-003 | permit open（referral=`bytes32(0)` 委譲） | unit |
| ZAP-FR-004 | permit open ＋ referral（事前 approve 不要） | unit, integration |
| ZAP-FR-005 | addCollWithUnderlying（増担保） | unit, integration |
| ZAP-FR-006 | withdrawCollToUnderlying（減担保→Underlying） | unit, integration |
| ZAP-FR-007 | withdrawJpydf（借入増） | unit, integration |
| ZAP-FR-008 | repayJpydf（返済・過剰分返却） | unit, integration |
| ZAP-FR-009 | adjustTroveWithUnderlying / adjustZombieTroveWithUnderlying（担保＋債務同時調整） | unit, integration |
| ZAP-FR-010 | closeTroveToUnderlying（JPYdf 保有 close） | unit, integration |
| ZAP-FR-011 | Day-1 ABI から削除済み（Flash Loan close / collateral-funded close） | manual / build artifact review |
| ZAP-FR-012 | Day-1 ABI から削除済み（Flash Loan callback） | manual / build artifact review |
| ZAP-FR-013 | receive | unit |
| ZAP-FR-014 | Sky USDC route（USDC→USDS→sUSDS→dUSDS） | unit, integration |
| ZAP-FR-015 | native ETH on-ramp（ETH→stETH→wstETH→dwstETH） | unit, integration |
| ZAP-INV-001..009 | §8 各不変条件 | manual / unit / invariant（§8 記載どおり） |
| ZAP-SEC-001..007 | §9 各セキュリティ要件 | unit / fork / manual（§9 記載どおり） |
| ZAP-EVT-001 | ReferralDeposit（条件・index・非伝播） | unit |

---

## 14. 未決事項（TBD / 決定レジスタ）

### ZAP-TBD-001

Resolved: `ZAP-FR-006`、`ZAP-FR-010`、`ZAP-EVT-001` に反映済み。

### ZAP-TBD-002

Resolved: `ZAP-FR-009` に反映済み。

### ZAP-TBD-003

Resolved: `ZAP-INV-001`、`ZAP-GOV-001` に反映済み。

### ZAP-TBD-004

**Deferred: Leverage 対応** — dToken 担保でのレバレッジは MVP 必須ではない。user app は dToken branch の Multiply を公開しない。

将来提供する場合:

- Balancer / 削除済み Flash Loan callback に依存しない。
- JPYdf/USDC v4 final leg、asset-specific pre-leg、Vault buffer / delayed redeem 条件を新規仕様として定義する。
- 別コントラクト、または明示的 route selector として追加する。

### ZAP-TBD-005

Resolved（2026-08-05・dwstETH ブランチについて）: Branch 0 の Underlying が WETH → wstETH へ移行し、native ETH 保有者の onboarding を切らないために **open の 1 Tx native ETH route** を [ZAP-FR-015](#zap-fr-015-native-eth-on-rampethstethwstethdwsteth) として追加した（ETH→stETH→wstETH→dwstETH）。route は deploy パラメータで明示的に有効化した instance にのみ存在する。

未解決として残す範囲: **native ETH の担保増加（add collateral）**と、WETH を Underlying とするブランチの native ETH UX。いずれも Day-1 は contract entrypoint を増やさず、frontend が不足分の `WETH.deposit` を事前 Tx として挿入する方針を維持する。

### ZAP-TBD-006

Resolved: `ZAP-FR-003`、`ZAP-FR-004` に反映済み。

### ZAP-TBD-007

Resolved: `ZAP-FR-009` に反映済み。

### ZAP-TBD-008

**Frontend UX task: Cap / Underlying 未確定時の挙動** — placeholder ブランチで Zapper 呼出が `CapExceeded` / `TokenInfoNotSet` で revert するのは依存先仕様どおり。Zapper の追加ガードは不要。frontend / admin console 側で branch inactive / cap zero / underlying 未確定を表示し、ユーザー向け flow を出さない。

### ZAP-TBD-009

**Resolved in code / activation still conditional: Sky USDC→USDS adapter** —
`SkyUsdcSUsdsConverter` を concrete implementation とし、Strategy / Zapper は共有
`ISkyUsdcSUsdsConverter` を使う。adapter は Sky 公式 LitePSMWrapper-USDS-USDC の
`sellGem`（USDC→USDS）/ `buyGem`（USDS→USDC）を使い、`tin` / `tout` halt、
6↔18 decimals、最小受取、返り値と実残高、temporary allowance、逆変換 refund を検査する。
deploy script は `DF_STRATEGY_SKY_USDC_USDS_PSM_WRAPPER_i` から concrete adapter を deploy し、
任意 converter address を Strategy へ注入しない。

USDC 入力UXを実運用する前に残る gate:

- mainnet wrapper address、`gem()==USDC`、`dai()==USDS`、現行 `tin/tout`、流動性を fork で再確認する。
- wrapper governance による fee 変更・halt と、利用可能USDC/USDS残高の監視を運用へ接続する。
- `SkyUsdcSUsdsConverter` と共有interfaceを今回の auditor scope / nSLOCへ含める。

### ZAP-TBD-010

**Conditional: USDC-only liquidity / swap route の本番有効化** — Day-1 の JPYdf DEX 流動性は JPYdf/USDC Uniswap v4 のみを標準とする。`UniV4Exchange` は Day-1 audit scope に含めるが、現行 ABI に swap-backed close / collateral-funded repay / Multiply は存在しない。

本番有効化前に確定する事項:

- JPYdf/USDC pool の token address、fee、tick spacing、hook policy、pool key、position owner。
- slippage floor、frontend route selector、liquidity script、投入する JPYdf / USDC amount と funding source。
- fork / integration evidence。
- 非 USDC collateral の reverse route が必要な場合は、追加 JPYdf pool ではなく `Underlying -> USDC -> JPYdf` に分け、asset-specific adapter と evidence を別途追加する。
- v4 user-facing flow は route config と allowance cleanup 検証後、新しい audited entrypoint として有効化する。

---

## 15. 参考資料

- [Product Overview](../Product-Overview.md) — 全体アーキテクチャ・責務分離
- [CollateralVault 要件定義](./CollateralVault.md) — deposit / redeem / 遅延償還 / claim（依存元）
- [dToken 要件定義](./dToken.md) — decimals / 換算（`convertToDToken` / `convertToUnderlying`）/ permit（依存元）
- [Oracle 要件定義](./Oracle.md)
- [Liquity-v2-Core-Spec.md](./Liquity-v2-Core-Spec.md) — BorrowerOperations / TroveManager / 安全装置
- [Parameters.md](../../../Parameters.md) — 担保別 mintCap / buffer 等の Day-1 値
- [要件定義ドキュメント標準](../../../Requirements-Spec-Standard.md) — 本書が従う標準
