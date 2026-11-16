# 🟢 InterestRouter（InterestRouterForwarder）要件定義

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Draft（実装あり・要件の正本化中） |
| Owner | DeltaForesight |
| 対象コントラクト | `contracts/src/InterestRouterForwarder.sol`（🟢 Original・非 UUPS / ロジック極小の immutable コントラクト。`IInterestRouter` を継承せず、ActivePool の `interestRouter` には address として束縛される） |
| 関連ドキュメント | [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md)（`CORE-AP-FR-003/007` 集計利息の SP/PIL 75/25 分配・`CORE-AP-FR-001/015` `interestRouter` immutable・`CORE-AP-TBD-001` 受け口束縛の決定・`SP_YIELD_SPLIT` 定数表）/ [Product-Overview](../Product-Overview.md)（PIL＝借入金利の流動性インセンティブ）/ [Architecture Decision Records](../architecture/Architecture-Decision-Records.md#adr-005) / [PILAllocator](./PILAllocator.md)（Phase-A recipient 実体・`DeployPILAllocatorPhaseA` activation manifest）/ [Treasury](../../roadmap/spec/Treasury.md)（担保運用益＝独立経路・PIL は非責務）/ [Governance-Roles-Timelock](../policies/Governance-Roles-Timelock.md)（共通 Timelock・handover） |

> 本書は [要件定義ドキュメント標準](../../../Requirements-Spec-Standard.md) に従う。要件 ID は `IRTR-*`。
> **Core parity の原則**: 集計利息の SP/PIL 分配・`interestRouter` への mint・immutable 束縛は 🔵 コアの規範（`CORE-AP-*`）であり、本書では再仕様化しない（ID 参照のみ）。本書が規定するのは、その mint 先として束縛する 🟢 `InterestRouterForwarder` の要件に限る。
> **マーカー**: 🔵 Core（Liquity v2 から base-parity で継承し、JPYdf canonical surface / `CORE-MOD-*` 差分は Core spec が管理）/ 🟢 Original（DeltaForesight 独自・新規追加ファイル。本書は Core 側の差分を再仕様化しない）。

---

## 1. 目的・スコープ・非責務

🔵 Liquity v2 コアでは、集計利息のうち SP 取り分（`SP_YIELD_SPLIT`）を除く残余（PIL＝Protocol Incentivised Liquidity 原資）が `interestRouter` という immutable アドレスへ JPYdf として mint される（`CORE-AP-FR-007`）。`interestRouter` は AddressesRegistry の immutable で、デプロイ後は変更できない（`CORE-AP-FR-001`）。

本家 Liquity の `interestRouter` は ve-LQTY ガバナンス（PIL 投票）に直結するが、jpydf は DFT 未発行・本家外部依存が Day-1 要件と無関係のため、その経路を Day-1 で使えない（`CORE-AP-TBD-001`）。そこで「mint 先を可変にできない」制約を、間に薄い受け口 `InterestRouterForwarder` を挟むことで解消する。Oracle が `PriceFeedProxy` を挟んで source 差替を可能にした [ADR-005](../architecture/Architecture-Decision-Records.md#adr-005) と同型のパターンである。

- **本書が規定する**:
  - `InterestRouterForwarder` — コアが mint する JPYdf（PIL 分）を滞留・保持し、`route()` で現 `recipient` へ全額転送する受け口。`recipient` は owner が変更でき、`owner` は 2-step 移譲・renounce 無効で共通 Timelock 管理へ handover される。
  - 全担保ブランチ共通の単一インスタンスとしての性質（§2.3）と、その deploy / handover 配線要件（§10）。
- **本書が規定しない（非責務・他文書）**:
  - 集計利息の SP/PIL 分配・`interestRouter` への mint・immutable 束縛 → 🔵 [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md)（`CORE-AP-FR-003/007/008` / `CORE-AP-FR-001/015`）。`SP_YIELD_SPLIT = 75%` は Core inherited constant であり、値の正本は `Constants.sol` と Core spec の定数表。Parameters.md は DF が調整した値のみの正本で、`SP_YIELD_SPLIT` は載せない。
  - PIL 分の実配分ロジック（DEX 流動性ゲージ配布・配分投票・Distributor 等）→ Day-2 の PIL/governance レイヤー（スコープ外）。
  - 担保運用益（Strategy yield）の分配・buyback → [Treasury](../../roadmap/spec/Treasury.md)（PIL とは独立経路・受け皿 env も別＝§2.4）。
  - `recipient`/`owner` の具体アドレス・handover 手順の実体 → deploy 入力（env）と [Governance-Roles-Timelock](../policies/Governance-Roles-Timelock.md)。

### 1.1 Day-1 の金利フローと claim 境界

借入金利 / upfront fee が 100,000 JPYdf mint された場合、Core は `SP_YIELD_SPLIT` に従い 75,000 JPYdf を Stability Pool のネイティブ報酬会計へ、残余 25,000 JPYdf を `InterestRouterForwarder` へ mint する。

| 取り分 | on-chain 到達先 | ユーザーへの見せ方 |
| --- | --- | --- |
| 75%（SP） | `StabilityPool.triggerJpydfRewards` 経由で SP 預入者の通常会計に反映 | Earn 画面の SP ネイティブ報酬。InterestRouter / Treasury から別途 claim するものではない |
| 25%（PIL） | `InterestRouterForwarder` に JPYdf として滞留し、`route()` で現 `recipient` へ全額送付 | `recipient` への集約であり、Forwarder 自体をユーザー向け claim、SP 追加報酬、DFT 投票配分として表示しない |

したがって `InterestRouterForwarder.route()` は「ユーザーへ配る」関数ではなく、PIL 原資を現在の会計・配分受け皿へ flush するだけの運用関数である。Day-2 に PIL Distributor / governance / Treasury 等へ接続する場合も、ユーザーが claim できるかは接続先の別仕様で決まり、本 Forwarder は配分・按分・claim 状態を持たない。

---

## 2. 背景・設計方針

### 2.1 動かせないコア制約（本設計の出発点）

| # | 事実（🔵 コア・無改変） | 帰結 |
| --- | --- | --- |
| 1 | 集計利息 mint 時に PIL 残余 `mintedAmount − spYield` を `jpydfToken.mint(interestRouter, ...)` する（`CORE-AP-FR-007`）。`spYield = SP_YIELD_SPLIT × mintedAmount`（`SP_YIELD_SPLIT = 75%`、値は `Constants.sol` / Core spec 定数表） | PIL 原資は `interestRouter` アドレスに JPYdf として届く。**受領にコールバックは無い** |
| 2 | `interestRouter` は ActivePool が constructor で読む immutable（`CORE-AP-FR-001/015`）。AddressesRegistry も `setAddresses` 1 回 → owner renounce で固定 | **mint 先アドレスはデプロイ後に変更不可**。Treasury（`setTreasury` で後差替可）と非対称 |
| 3 | `IInterestRouter` は関数を持たない空インターフェース。受け口は EOA・マルチシグ・コントラクトいずれでもよい | 受け口に「最終配送先を後から変える」能力を持たせられる |

### 2.2 設計方針

1. **受け口で可変性を確保（Core parity・ADR-005 同型）**: immutable な `interestRouter` に薄い `InterestRouterForwarder` を束縛し、PIL の最終配送先（`recipient`）を Forwarder 側で変更可能にする。Day-2 の PIL/Treasury/governance への切替えを再デプロイなしで行う。
2. **pass-through・滞留のみ（会計を持たない）**: 受領した JPYdf を保持し、`route()` で現 `recipient` へ全額転送するだけ。比率・予算・claim 等の会計は持たない（Day-2 配分レイヤーの責務）。
3. **固定宛先原則（任意送金の禁止）**: 資金の出口は `recipient` 1 つだけ。`route()` は送金先を引数に取らず、常に現 `recipient` へ全額送る。`recipient` 変更のみ owner 権限。
4. **owner の権限分離と handover**: `recipient` を変更できる `owner` は 2-step 移譲・renounce 無効とし、Day-1 の handover で共通 TimelockController 管理へ移す（dToken / CollateralVault / Strategy と同一 Timelock）。recipient 付け替えに公示遅延を課す。
5. **会計分離した recipient**: `recipient` は担保運用益（[Treasury](../../roadmap/spec/Treasury.md)）の受け皿とは別 env・別管理にする（§2.4）。initial `recipient` の採用状態は [IRTR-GOV-003](#irtr-gov-003-pil-配送先移行) に委譲する。
6. **deploy 必須入力・fail-fast**: `recipient`/`owner` の初期値は deploy env で与え、未指定なら deploy を停止する（§10）。

### 2.3 単一共有 Forwarder（全ブランチ → 1 受け口）

DF dToken wiring では Forwarder を 1 個だけ deploy（CREATE2・決定論アドレス）し、その単一アドレスを全担保ブランチの `interestRouter` immutable に束縛する（本家が governance 1 個を全ブランチ共有するのと同型）。

- **クロスブランチ PIL 集約**: 各ブランチの ActivePool が PIL 分 JPYdf を同一 Forwarder へ mint する。Forwarder の保持残高は全ブランチ PIL の合算であり、`route()` はその合算を単一 `recipient` へ送る。
- **会計的含意**: ブランチ別 PIL の内訳は Forwarder 上では区別されない（合算）。ブランチ別按分や DeFiLlama 等の外部 fee/revenue 集計が必要なら、各 ActivePool の `AggregateInterestMinted` イベントから off-chain で再構成する（本書スコープ外）。
- 配線整合（全ブランチが同一 `interestRouter` を指す）は handover/verify で機械検証する（§10・[IRTR-INV-006](#8-不変条件inv)）。

### 2.4 recipient と Treasury の分離

deploy では受け皿が 2 系統に分かれる。

| 経路 | env | 受け皿の意味 |
| --- | --- | --- |
| **PIL（本書）** | `DF_INTEREST_ROUTER_RECIPIENT` | 借入金利 PIL 分 JPYdf の承認済み最終配送先 |
| 担保運用益（[Treasury](../../roadmap/spec/Treasury.md)） | `DF_TREASURY` | CollateralVault の `treasury`（Day-1 = Protocol retention Safe 留保。Foundation は署名鍵を持たない） |

両者は別 env・別アドレスであり、Day-1 から PIL と担保運用益を独立追跡する。

---

## 3. 用語・外部依存・前提

### 3.1 用語

| 用語 | 意味 |
| --- | --- |
| PIL | Protocol Incentivised Liquidity。借入金利の残余を原資とする JPYdf 流動性インセンティブ |
| `interestRouter` | コア（ActivePool）が PIL 原資を mint する immutable な宛先（`CORE-AP-FR-001/015`）。DF dToken wiring では単一の `InterestRouterForwarder` に束縛 |
| `SP_YIELD_SPLIT` | 集計利息の SP 取り分率（75%）。残余 25% が PIL。値の正本は `Constants.sol` / [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md)（`CORE-AP-FR-003/007` と定数表） |
| `route()` | Forwarder の保持 JPYdf 全額を現 `recipient` へ転送する permissionless 関数（転送額を返す） |
| `recipient` | PIL 原資の最終送付先。owner が変更可 |
| `owner` | `recipient` を変更できる権限主体。2-step 移譲・renounce 無効。Day-1 handover で共通 Timelock へ |
| `pendingOwner` | 2-step 移譲の保留先（`transferOwnership(0)` で取消） |

### 3.2 外部依存（信頼する外部）

- **ActivePool（🔵 Core・各ブランチ）** — PIL 原資（JPYdf）の唯一の mint 元。Forwarder は ActivePool を呼ばない（受領のみ・コールバックなし）。
- **JpydfToken（JPYdf・🔵 Core）** — `route()` の転送対象。constructor で immutable 保持。`constructor` / `setRecipient` は `requireValidRecipient` で現在の Core 禁止宛先を拒否する。標準 ERC-20（転送フックなし）であることに依拠（[IRTR-SEC-004](#irtr-sec-004-reentrancy--cei)）。
- **共通 TimelockController（🟢 DF）** — handover 後の `owner`。`setRecipient` に公示遅延を課す（[Governance-Roles-Timelock](../policies/Governance-Roles-Timelock.md)）。

### 3.3 前提

- Forwarder は JPYdf のみを正規原資として扱う。`route()` は `jpydfToken` 残高のみ転送する。
- `receive()` / `payable` を持たないため ETH は受領できない。JPYdf 以外のトークン誤送付の救済（rescue）は持たない（[IRTR-TBD-003](#irtr-tbd-003)）。
- 現行の complete deploy は dToken wiring の有無にかかわらず Forwarder を `interestRouter` に束縛し、`DF_INTEREST_ROUTER_RECIPIENT` / `DF_INTEREST_ROUTER_OWNER` を必須入力として扱う（§10 [IRTR-GOV-005](#irtr-gov-005-チェーン別配線ゲート)）。

---

## 4. アクター・ロール・信頼境界

| アクター | 操作 | 信頼境界 |
| --- | --- | --- |
| **ActivePool（🔵 Core・各ブランチ）** | PIL 原資を単一 Forwarder へ mint | コア。受領のみ・コールバックなし |
| **owner**（handover 後 = 共通 TimelockController） | `setRecipient` / 2-step ownership 移譲・pending 取消 | 唯一の特権。recipient 変更は共通 Timelock の待機対象。renounce 無効 |
| **route 呼出者（任意・permissionless）** | `route()` | 信頼不要。送金先は現 `recipient` 固定（誰が呼んでも資金は recipient へ） |
| **recipient** | 受領のみ | 承認済み PIL 受け皿。受領後の使途はスコープ外 |

- **ロール分離の意図**: 「recipient を変える権限（owner=Timelock・遅延付き）」と「資金を recipient へ流す操作（route=permissionless・無害）」を分離する。owner 鍵が侵害されても即時の資金奪取経路を持たせない（[IRTR-SEC-001](#irtr-sec-001-owner-鍵侵害の被害境界)）。

---

## 5. インターフェース仕様

挙動の規範は §6（可視性のみ要約・非規範）。実装は `IInterestRouter`（空 IF）を継承しないが、deploy で `IInterestRouter(address)` として束縛されるため空 IF の契約（特定関数を要求しない）は満たす。

| 関数 / 要素 | 可視性 | 要約 | 規定要件 |
| --- | --- | --- | --- |
| `constructor(IERC20 _jpydfToken, address _recipient, address _owner)` | — | immutable `jpydfToken`・初期 `recipient`・初期 `owner` を設定（いずれもゼロ拒否、recipient は JPYdf Core 禁止宛先も拒否）。初期値を `RecipientUpdated`/`OwnershipTransferred` で発火 | IRTR-FR-001 |
| `route() returns (uint256 amount)` | external（permissionless） | 保持 JPYdf 全額を現 `recipient` へ転送し転送額を返す | IRTR-FR-002 |
| `setRecipient(address newRecipient)` | external（onlyOwner） | 最終配送先の変更（ゼロおよび JPYdf Core 禁止宛先を拒否） | IRTR-FR-003 |
| `transferOwnership(address newOwner)` | external（onlyOwner） | 2-step 移譲の開始。`newOwner = 0` は pending の取消 | IRTR-FR-004 |
| `acceptOwnership()` | external（onlyPendingOwner） | 2-step 移譲の確定 | IRTR-FR-004 |
| `renounceOwnership()` | external view onlyOwner | 無効化（owner 呼出で `RenounceOwnershipDisabled`・非 owner は `Unauthorized`） | IRTR-FR-004 |
| `owner()` / `pendingOwner()` / `recipient()` / `jpydfToken()` | external view | 状態の可観測化 | IRTR-FR-005 |

- **エラー集合**: `ZeroAddress` / `Unauthorized` / `RenounceOwnershipDisabled`（OZ `Ownable2Step` ではなく自前の 2-step 実装）に加え、recipient が JPYdf Core 禁止宛先なら `JpydfToken__CannotTransferToProtocolContract` を JpydfToken から伝播する。

---

## 6. 機能要件（FR）

### IRTR-FR-001: constructor（受け口の確立・fail-fast）

- **Type**: Functional ｜ **Source**: §2.2 / `CORE-AP-TBD-001`
- **シグネチャ**: `constructor(IERC20 _jpydfToken, address _recipient, address _owner)`
- **目的**: PIL 原資の受け口を確立する。転送対象トークン（JPYdf）を immutable 固定し、承認済みの初期 `recipient` と初期 `owner` を設定する。
- **権限**: デプロイ時のみ。
- **事前条件（Checks）**: `_jpydfToken != 0` / `_recipient != 0` / `_owner != 0`（いずれもゼロは `ZeroAddress`）。さらに `IJpydfToken(_jpydfToken).requireValidRecipient(_recipient)` が成功すること。
- **動作（Effects）**: `jpydfToken` を immutable 保存、`recipient`・`owner` を設定。初期値を `RecipientUpdated(0, _recipient)` と `OwnershipTransferred(0, _owner)` で発火。
- **設計上のポイント**: 初期値は deploy env（[IRTR-GOV-002](#irtr-gov-002-deploy-入力と-fail-fast)）由来で、未指定または JPYdf が現在拒否する recipient なら deploy が停止する。Forwarder は CREATE2 で決定論アドレス。再デプロイは全ブランチ再配線を伴うため、可変なのは `recipient` のみ。Core アドレス登録は Forwarder 構築後にも進むため、deploy 末尾でも同じ recipient 妥当性を再検証する。
- **Verification**: unit。

### IRTR-FR-002: route（PIL 原資の転送・permissionless）

- **Type**: Functional ｜ **Source**: §2.2
- **シグネチャ**: `route() returns (uint256 amount)`
- **目的**: 保持する JPYdf 全額を現在の `recipient` へ転送する。
- **権限**: permissionless（誰でも）。
- **事前条件（Checks）**: なし（残高 0 は no-op）。
- **動作（Effects）**:
  1. `amount = jpydfToken.balanceOf(address(this))`
  2. `amount == 0` なら `return 0`（イベント発火なし）
  3. `jpydfToken.safeTransfer(recipient, amount)` — 宛先は現 `recipient` 固定（引数に取らない）
  4. `Routed(recipient, amount)` を発火し `amount` を返す
- **revert / 早期 return**: 残高 0 → `return 0`。
- **設計上のポイント**: 送金先を引数化しないため permissionless でも誤送・奪取が起きない。keeper 不要で誰でも flush でき滞留を最小化できる。CEI 準拠で、標準 ERC-20 前提なら再入余地はない（[IRTR-SEC-004](#irtr-sec-004-reentrancy--cei)）。
- **Verification**: unit, invariant=[IRTR-INV-001/002](#8-不変条件inv), integration（コア mint→route→recipient）。

### IRTR-FR-003: setRecipient（最終配送先の変更）

- **Type**: Functional / Governance ｜ **Source**: §2.2
- **シグネチャ**: `setRecipient(address newRecipient)`
- **目的**: PIL 原資の最終送付先を変更する（holding address、`PILAllocator`、将来の Distributor / governance 等）。
- **権限**: `onlyOwner`（handover 後は共通 Timelock 経由）。
- **事前条件（Checks）**: `newRecipient != 0`（`ZeroAddress`）かつ `IJpydfToken(jpydfToken).requireValidRecipient(newRecipient)` が成功すること。
- **動作（Effects）**: `recipient = newRecipient` → `RecipientUpdated(oldRecipient, newRecipient)` を発火。
- **revert**: 非 owner → `Unauthorized`；ゼロ → `ZeroAddress`；現在の JPYdf Core 禁止宛先 → `JpydfToken__CannotTransferToProtocolContract`。失敗時は既存 `recipient` を保持する。
- **設計上のポイント**: ActivePool の immutable は Forwarder のままで配送先だけが変わる（再デプロイ不要）。変更は将来効のみ（変更後の最初の `route()` から新 recipient へ）。
- **Verification**: unit。

### IRTR-FR-004: ownership（自前 2-step 移譲・renounce 無効）

- **Type**: Governance / Security ｜ **Source**: `CORE-AP-TBD-001` / [Governance-Roles-Timelock](../policies/Governance-Roles-Timelock.md)
- **目的**: owner 権限の安全な移譲（特に共通 Timelock への handover）を 2-step で行い、誤移譲・恒久 strand を防ぐ。
- **要件**:
  - `transferOwnership(newOwner)`（onlyOwner）→ `pendingOwner = newOwner`・`OwnershipTransferStarted` を発火。`newOwner = address(0)` を渡すと pending を取消できる（ゼロ拒否しない＝意図的なキャンセル路）。
  - `acceptOwnership()`（`msg.sender == pendingOwner` のみ・それ以外は `Unauthorized`）→ `owner` を更新・`pendingOwner` をクリア・`OwnershipTransferred` を発火。
  - `renounceOwnership()` は常に revert（`external view onlyOwner`。owner 呼出で `RenounceOwnershipDisabled`・非 owner は `Unauthorized`）。owner 不在は `recipient` の恒久固定（strand）を招くため無効化する。
- **設計上のポイント**: dToken / Strategy の renounce 無効 2-step と同型。ただし OZ `Ownable2Step` の継承ではなく自前実装で、`transferOwnership(0)` による pending 取消が可能（handover 完了前は現 owner が中断しうる＝[IRTR-SEC-005](#irtr-sec-005-pending-ownership-取消の悪用境界)）。
- **Verification**: unit。

### IRTR-FR-005: View 群

- `owner()` / `pendingOwner()` / `recipient()` / `jpydfToken()`。監視・subgraph・handover 検証に用いる。
- **Verification**: unit。

---

## 7. 状態変数・会計モデル

| 変数 | 型 | 説明 |
| --- | --- | --- |
| `jpydfToken` | `IERC20 immutable` | 転送対象（JPYdf）。constructor で固定 |
| `owner` | `address` | `setRecipient` の権限主体。handover 後 = 共通 Timelock |
| `pendingOwner` | `address` | 2-step 移譲の保留先（`transferOwnership(0)` で取消） |
| `recipient` | `address` | PIL 原資の現送付先 |

**会計モデル**: 予算・比率・claim 等の会計を持たない。保持残高 = `jpydfToken.balanceOf(this)` がそのまま未転送の PIL 原資（全ブランチ合算＝§2.3）で、`route()` で全額が `recipient` へ出る（pass-through）。按分・ブランチ別内訳は Day-2 配分レイヤー / off-chain の責務。

---

## 8. 不変条件（INV）

| ID | 不変条件 | 検証 |
| --- | --- | --- |
| IRTR-INV-001 | 資金流出先は `recipient` のみ。宛先を引数に取る送金関数は存在しない（rescue も無い） | unit / manual |
| IRTR-INV-002 | `route()` は保持 JPYdf 全額を現 `recipient` へ送る（部分送金・他宛先送金の経路がない） | unit / invariant |
| IRTR-INV-003 | `recipient` の変更は `owner`（handover 後 = Timelock）のみ。ゼロおよび変更時点で JPYdf が拒否する Core 宛先は不可 | unit |
| IRTR-INV-004 | `owner` は renounce 不可（常に有効な owner が存在し、付け替え能力が恒久 strand しない） | unit |
| IRTR-INV-005 | 🔵 core への状態変更呼び出しを行わない（ActivePool を呼ばず受領のみ。Core 側の差分は Core spec の `CORE-MOD-*` 台帳でのみ扱う） | manual / static review |
| IRTR-INV-006 | DF dToken wiring では全ブランチの `interestRouter` が同一の単一 Forwarder を指す | deploy（構築時保証）/ handover 検証 |

---

## 9. セキュリティ要件（SEC）

### IRTR-SEC-001: owner 鍵侵害の被害境界

- **Statement**: owner が実行できるのは `setRecipient`（と ownership 移譲）のみで、即時に資金を奪う経路を持たない。handover 後の owner は共通 Timelock のため、不正な `recipient` 変更には公示遅延が掛かり、その間に検知・対応できる。`route()` は permissionless だが送金先が現 `recipient` 固定のため、owner 侵害と無関係に資金は正規 recipient へしか向かわない。
- **残存リスク**: 共通 Timelock の待機時間内に対応できなければ、付け替え後の PIL は新 recipient へ流れる。監視（[IRTR-EVT-002](#11-イベント監視要件evt) の即時アラート）と incident 体制が前提。handover 完了前（owner = deployer/admin）は遅延が無いため、deploy → handover 確定を速やかに行い、その間の鍵管理を厳格化する。
- **Verification**: unit / manual。

### IRTR-SEC-002: route の permissionless 安全性

- **Statement**: 誰でも呼べるが、送金先・送金額（全額）に呼出者の裁量が無く、常に現 `recipient` へ全額が向かう。第三者呼出による不利益（誤送・MEV 横取り）が発生してはならない。残高 0 の呼出は no-op。
- **Verification**: unit。

### IRTR-SEC-003: 無効 recipient・renounce による strand 防止

- **Statement**: `recipient` をゼロまたは JPYdf Core 禁止宛先にできず（FR-001/003）、owner を renounce できない（FR-004）。拒否された変更は現 recipient を維持するため `route()` の既存経路を止めない。これにより既知の設定ミスで PIL 原資が送れず滞留する状態を構造的に防ぐ。
- **Verification**: unit。

### IRTR-SEC-004: reentrancy / CEI

- **Statement**: `route()` の外部呼出は `jpydfToken.safeTransfer` の 1 回のみで、状態を持たない pass-through のため再入の悪用余地が無い。`setRecipient` は記帳のみ。JPYdf（`JpydfToken`）が転送フックを持たない標準 ERC-20 であることに依拠する（§3.2）。`nonReentrant` ガードは持たない（不要）。
- **Verification**: unit / manual。

### IRTR-SEC-005: pending ownership 取消の悪用境界

- **Statement**: `transferOwnership(0)` による pending 取消は owner 権限。handover 後（owner = Timelock）はその待機時間下のみで、悪用境界は SEC-001 と同じ。handover 完了前は現 owner（deployer/admin）が一方的に中断しうるため、handover の完了（Timelock の `acceptOwnership` 実行）を deploy 直後に速やかに行う。
- **Verification**: unit / manual。

---

## 10. ガバナンス・運用・アップグレード要件（GOV）

### IRTR-GOV-001: ロール構成と handover

- 初期 `owner` は deploy env `DF_INTEREST_ROUTER_OWNER`。Day-1 handover（`PrepareDFGovernanceHandover` / `VerifyDFGovernanceHandover`）で、dToken / CollateralVault / Strategyと同じ共通TimelockControllerへ2-step移譲する。delay値は [Day1 Parameter Manifest](../../../Parameters.md) `PRM-GOV-COMMON-TIMELOCK-DELAY`、holder構成は [Protocol Role Holder Manifest](../../../protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md) を正本とする。
- handover は deploy manifest の各ブランチ `interestRouter` を読み、単一 Forwarder の `transferOwnership(<共通 Timelock>)` を開始し、全ブランチが同一 `interestRouter` であることを assert する（idempotent）。
- **前提**: handover の実行は「現 owner == 実行主体（currentAdmin）」を要求するため、初期 `DF_INTEREST_ROUTER_OWNER` は handover 実行主体（deployer/admin）と一致させる。直接 Timelock を初期 owner にする場合は handover 開始がスキップされ、Timelock 側で `acceptOwnership` を別途実行する。
- 2-step の確定（`acceptOwnership`）は Timelock が proposal 経由で実行する。verify は `owner == 共通 Timelock`（中間状態を許す設定では `pendingOwner == 共通 Timelock`）を検査する。

### IRTR-GOV-002: deploy 入力と fail-fast

- DF dToken wiring（[IRTR-GOV-005](#irtr-gov-005-チェーン別配線ゲート)）では必須 env `DF_INTEREST_ROUTER_RECIPIENT`（承認済み initial `recipient`）と `DF_INTEREST_ROUTER_OWNER`（初期 `owner`）を要求し、いずれかゼロなら deploy を停止する（fail-fast）。Forwarder は CREATE2 で 1 個 deploy し、全ブランチの `interestRouter` に束縛する。
- 束縛整合（`interestRouter == Forwarder`・`recipient`/`owner` が env と一致）と、全 Core アドレス登録後の `requireValidRecipient(recipient)` 成功を deploy 末尾および handover/verify/accept scripts で fail-fast 検証する（[IRTR-TBD-006](#irtr-tbd-006) は解決済み）。

### IRTR-GOV-003: PIL 配送先移行

- initial `recipient` と PIL 配分機構の採用状態は [Mainnet Launch Product Decision Record](../../launch/decisions/Mainnet-Launch-Product-Decision-Record.md) §6 を正本とする。PIL 配分機構を稼働する場合、owner（Timelock）が `setRecipient` で配送先を切り替える（再デプロイ不要）。切替前に滞留した分は `route()` で現 `recipient` へ随時 flush できる。

### IRTR-GOV-004: アップグレード方針

- 非 UUPS（非 upgradeable）。ロジックが極小で upgrade 面を持たないことを監査単純性のために選ぶ。挙動変更が必要な場合は新 Forwarder のデプロイ＋全ブランチ再配線で対応する。

### IRTR-GOV-005: チェーン別配線ゲート

- Complete deploy は chain / dToken wiring の有無にかかわらず単一 `InterestRouterForwarder` を deploy し、全ブランチの `interestRouter` に束縛する。mainnet で Day-1 8 branch dToken wiring に入るには引き続き `DF_ENABLE_MAINNET_DTOKEN_WIRING=true` と production env 一式を明示するが、V2-gov / Governance address への fallback は持たない。`DF_INTEREST_ROUTER_RECIPIENT`/`DF_INTEREST_ROUTER_OWNER` の mainnet 実値は常に必須（[IRTR-TBD-001](#irtr-tbd-001)）。[Product-Overview](../Product-Overview.md) の Launch Risk Register（mainnet 前に freeze するアドレス群）に両 env を含める。

---

## 11. イベント・監視要件（EVT）

| ID | イベント（引数は indexed） | 用途（off-chain） |
| --- | --- | --- |
| IRTR-EVT-001 | `Routed(address indexed recipient, uint256 amount)` | PIL 配送実績・滞留量の監視 |
| IRTR-EVT-002 | `RecipientUpdated(address indexed oldRecipient, address indexed newRecipient)` | 配送先変更の追跡（Timelock 提案/実行と併せて即時アラート）。constructor でも初期値を発火 |
| IRTR-EVT-003 | `OwnershipTransferStarted` / `OwnershipTransferred`（previousOwner/newOwner を indexed） | handover の追跡・verify の照合。constructor で初期 owner を発火 |

- 監視指標: Forwarder 保持残高（全ブランチ PIL 合算）、`recipient` の現在値（期待＝承認済み manifest / activation package と一致）、`owner` の現在値（期待＝共通 Timelock）、`RecipientUpdated`/`OwnershipTransferStarted` の即時アラート。

---

## 12. 失敗時・異常系挙動（ERR）

| 事象 | 挙動 |
| --- | --- |
| `route()` を残高 0 で呼出 | `return 0`（revert せず・イベントなし）。誰でも安全に呼べる |
| constructor / `setRecipient` に現在の JPYdf Core 禁止宛先を指定 | `JpydfToken__CannotTransferToProtocolContract` で revert。setter の場合は既存 recipient を保持し、既存の `route()` 経路は継続 |
| owner 鍵侵害による不正 `setRecipient` | handover 後は Timelock 経由。`RecipientUpdated`/Timelock イベントの即時アラートで delay 中に検知・対応（[IRTR-SEC-001](#irtr-sec-001-owner-鍵侵害の被害境界)） |
| `recipient` が受領拒否コントラクト等で機能不全 | 標準 ERC-20 `transfer` は受領側ロジックに依存しないため Forwarder からの送付は成立。recipient 側の滞留は recipient 管理の問題（owner が `setRecipient` で是正可能） |
| JPYdf 以外のトークン誤送付 | rescue 関数が無いため当該トークンは滞留（救済不可）。`route()` は `jpydfToken` のみ転送。ETH は受領不可（[IRTR-TBD-003](#irtr-tbd-003)） |
| handover 完了前に現 owner が `transferOwnership(0)` | pending（Timelock 移譲）が取消される。handover を速やかに完了させて緩和（[IRTR-SEC-005](#irtr-sec-005-pending-ownership-取消の悪用境界)） |
| PIL 配分機構が未稼働 | PIL は現 `recipient` に滞留する。稼働承認後に `setRecipient` で承認済み配分機構へ切り替える |

---

## 13. 受け入れ基準・検証計画

| ID | 要件（要約） | 検証手段 |
| --- | --- | --- |
| IRTR-FR-001 | constructor（ゼロ / JPYdf Core 禁止宛先拒否・初期値・初期イベント） | unit |
| IRTR-FR-002 | route（全額・固定宛先・残高 0 no-op・permissionless・戻り値） | unit, invariant=IRTR-INV-001/002, integration |
| IRTR-FR-003 | setRecipient（owner 限定・ゼロ / JPYdf Core 禁止宛先拒否・失敗時の現経路維持・将来効） | unit |
| IRTR-FR-004 | 2-step ownership・pending 取消・renounce 無効 | unit |
| IRTR-FR-005 | View 群 | unit |
| IRTR-INV-001..006 | §8 各不変条件 | unit / invariant / manual / CI / deploy・handover |
| IRTR-SEC-001..005 | §9 各セキュリティ要件 | unit / manual |
| 配線（handover） | owner が 2-step で共通 Timelock に移る | integration |
| 配線（deploy） | `interestRouter == Forwarder`・`recipient`/`owner` が env と一致・コア mint→route→recipient の一気通貫 | deploy / integration（[IRTR-TBD-006](#irtr-tbd-006) は解決済み。deploy 末尾で token / recipient / owner / pendingOwner / 全 branch 同一性を検査） |

> コア側（PIL 残余の mint・SP/PIL 分配）の検証は 🔵 [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md)（`CORE-AP-FR-007`）の所管。本書は受け口の挙動と配線整合のみを検証する。

---

## 14. 未決事項（TBD）

### IRTR-TBD-001

**initial recipient の mainnet 実値** — `DF_TREASURY` とは別の PIL recipient を用い、custody / accounting をアドレス単位で分離する。承認済み checksum address の正本は [Mainnet Protocol Role Holder Manifest](../../../protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md) とする。非 mainnet テストは暫定アドレスで可。

### IRTR-TBD-002

Resolved: `IRTR-FR-002` と [InterestRouterForwarder Route Runbook](../../operations/runbooks/InterestRouterForwarder-Route-Runbook.md) に反映済み。

### IRTR-TBD-003

**誤送トークンの rescue 有無** — 現状 rescue 関数を持たない（JPYdf 以外の誤送は救済不可）。既定方針は「持たない＋監視」とし、必要時は新 Forwarder の再デプロイ＋全ブランチ再配線で対応する（非 upgradeable のため）。付与する場合も JPYdf（正規原資）は対象外とし、固定宛先原則（[IRTR-INV-001](#8-不変条件inv)）を崩さない。

### IRTR-TBD-004

Resolved: `IRTR-GOV-003` に反映済み。

### IRTR-TBD-005

Resolved: `CORE-AP-FR-003`、`CORE-AP-FR-007` に反映済み。

### IRTR-TBD-006

Resolved: `IRTR-GOV-002`、`IRTR-GOV-005` に反映済み。

---

## 15. 参考資料

- 🔵 [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md) — `CORE-AP-FR-007/008`（集計利息の SP/PIL mint）/ `CORE-AP-FR-001/015`（`interestRouter` immutable・views）/ `CORE-AP-TBD-001`（受け口束縛の決定）
- [Product-Overview](../Product-Overview.md) — PIL（借入金利の流動性インセンティブ）
- [Architecture Decision Records](../architecture/Architecture-Decision-Records.md#adr-005) — PriceFeedProxyで固定参照の裏を可変化する設計理由
- [Mainnet Launch Risk Gate](../../launch/gates/Mainnet-Launch-Risk-Gate.md) — system-wide launch risk
- [Treasury](../../roadmap/spec/Treasury.md) — 担保運用益の分配（PIL とは独立経路・受け皿 env は `DF_TREASURY`）
- [Governance-Roles-Timelock](../policies/Governance-Roles-Timelock.md) — 共通 TimelockController・Day-1 handover
- `pil-activation-manifest.json` — 採用を承認したPIL activation packageの投入値（Core inherited constantである`SP_YIELD_SPLIT`はCore spec / `Constants.sol`側が正本）
