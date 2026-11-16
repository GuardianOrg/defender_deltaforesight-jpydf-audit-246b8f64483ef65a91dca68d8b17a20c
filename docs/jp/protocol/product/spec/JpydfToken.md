# 🔵/🟡 JpydfToken 要件定義

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Draft（実装あり・要件の正本化中。Core Spec から `CORE-BT-*` を分離して本書に集約） |
| Owner | DeltaForesight |
| 区分 | 🔵/🟡（Liquity v2 Core の debt token を base-parity 継承し、DF 差分を台帳化した singleton。差分 = CORE-MOD-001 命名 / CORE-MOD-008 bridge-ready dormant extension / CORE-MOD-009 registration hardening） |
| 対象コントラクト | `contracts/src/JpydfToken.sol` / `contracts/src/Interfaces/IJpydfToken.sol`。🔵 upstream 由来基底 = OpenZeppelin v4.9.5 `ERC20` / `ERC20Permit`（EIP-2612・ERC-5267）、Liquity 版 `Ownable`。配線 = `contracts/script/DeployLiquity2.s.sol` |
| 関連ドキュメント | [Product-Overview](../Product-Overview.md)（SYS-FR-006 / SYS-CON-004 / SYS-INV-003）/ [Architecture Decision Records](../architecture/Architecture-Decision-Records.md#adr-004) / [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md)（Core `mint`/`burn` の呼出元 BO/AP/TM/SP/CR、§2.2 CORE-MOD 台帳）/ [Parameters](../../../Parameters.md)（`PRM-BRIDGE-MINTER-TIMELOCK` 等の security parameter）/ [Bridge-Minter-Activation-Gate](../../operations/runbooks/Bridge-Minter-Activation-Gate.md)（Day-2 bridge minter 登録前 gate）/ [dToken](./dToken.md)（担保トークン） |

> 本書は [要件定義ドキュメント標準](../../../Requirements-Spec-Standard.md)に従う。要件・不変条件・セキュリティ要件には永続 ID（`CORE-BT-…`）を付し、相互参照は ID で行う。Core Spec から本書へ移設後も **`CORE-BT-*` namespace は維持**し、既存の ID 参照（台帳・トレース・レビュー）はそのまま解決する。

## 1. 目的・スコープ・非責務

`JpydfToken` は、システム全体（全 branch 共有）で 1 つだけデプロイされる円建てステーブルコイン JPYdf の本体（ERC-20 + EIP-2612）。Liquity v2 の `BoldToken` を base-parity で継承し、Core の債務会計（借入・利息発行・返済・redemption・清算 offset）にのみ連動する供給経路を持つ。

- **本書が規定する**: Core 供給経路（`mint` / `burn`）と権限境界、SP 内部移転（`sendToPool` / `returnFromPool`）、受取人制限付き ERC-20 移転、EIP-2612 permit、デプロイ配線と owner renounce による Core 権限の恒久固定化、および DF 独自の bridge-ready dormant surface（`bridgeAdmin` / bridge minter registry / `bridgeMint` / self-burn `bridgeBurn`）。
- **非責務**: branch ロジック・担保会計・価格取得・redemption ルーティング（それぞれ Core 各コントラクト / [dToken](./dToken.md) / [Oracle](./Oracle.md) / CollateralRegistry の責務）。bridge adapter 本体・他チェーン token・rate limit・message verification は token 内では実装せず、Day-2 以降に [Bridge-Minter-Activation-Gate](../../operations/runbooks/Bridge-Minter-Activation-Gate.md) と adapter 監査で fail-closed に確定する。
- **Day-1 スコープ**: Ethereum mainnet 単一チェーン。bridge minter 0 件・pending proposal なしの休眠状態で launch する（CORE-BT-INV-003）。

## 2. 背景・設計方針（Core supply path と bridge-ready surface の分離）

システム全体（全 branch 共有）で 1 つだけデプロイされるステーブルコイン本体。OZ v4.9.5 の `ERC20` / `ERC20Permit`（EIP-2612・ERC-5267）と Liquity 版 `Ownable` を継承する。既存 Core 発行（`mint`）は登録済み BorrowerOperations / ActivePool に、既存 Core 償却（`burn`）は CollateralRegistry と登録済み BorrowerOperations / TroveManager / StabilityPool に限定され、これにより Core supply path はプロトコルの債務会計（借入・利息発行・返済・redemption・清算 offset）にのみ連動する。branch コントラクトの登録は Owner が `setBranchAddresses` で行い、最後に `setCollateralRegistry` を呼んだ時点で ownership が renounce され、Core 権限構成は恒久固定となる（追加 branch の登録は以後不可能）。

DF はこれに加え、Day1 token freeze 後の bridge 不可を避けるため bridge-ready dormant surface（CORE-MOD-008）を持つ。bridge governance は `bridgeAdmin` が担い、Owner renounce 後も `bridgeAdmin` は独立して存続する。`bridgeAdmin` / bridge minter は contract address のみに限定し、admin と minter の兼任は許可しない。bridge minter 追加は 48h timelock、削除は即時。bridge supply path は別名 `bridgeMint` / self-burn 型 `bridgeBurn` に限定し、既存 Core `mint` / `burn` の権限条件には bridge minter を OR 追加しない。Day-1 launch は `bridgeMinterCount == 0` / `proposedBridgeMinter == address(0)` の休眠状態を必須とする。Day-2 以降の minter 登録は token-local な判断ではなく、adapter 側の per-chain cap / hourly・daily rate limit / global bridged supply cap / remote supply accounting / pause・incident runbook を [Bridge-Minter-Activation-Gate](../../operations/runbooks/Bridge-Minter-Activation-Gate.md) で満たしてから行う。proxy を介さない non-upgradeable コントラクトであり、DF 差分はトークン名・シンボル（CORE-MOD-001）と bridge-ready dormant extension（CORE-MOD-008）。

DF 差分は Core 差分台帳（[Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md) §2.2）で append-only 管理する: debt-token 命名 = `CORE-MOD-001`、bridge-ready dormant extension = `CORE-MOD-008`、core address registration hardening = `CORE-MOD-009`。本書の 🟡 要件はこれらを参照し、台帳と本書は相互にポインタで結ぶ。

## 3. 用語・外部依存・前提

- **Core supply path**: 既存 `mint` / `burn`。登録済み BorrowerOperations / ActivePool（mint）、CollateralRegistry・登録済み BorrowerOperations / TroveManager / StabilityPool（burn）だけが呼べる。
- **Bridge supply path**: `bridgeMint` / self-burn `bridgeBurn`。登録済み bridge minter だけが呼べる別経路。Day-1 は minter 0 件で休眠する。
- **外部依存**: OpenZeppelin `ERC20` / `ERC20Permit`（EIP-2612・ERC-5267）、Liquity 版 `Ownable`（`transferOwnership` を持たず internal `_renounceOwnership` のみの使い捨て owner パターン）。
- **前提**: non-upgradeable（proxy なし）。Core 権限構成は `setCollateralRegistry` の owner renounce で恒久固定され、branch の後付け追加・差替は不能。

## 4. アクター・ロール・信頼境界

| アクター | 役割 | 信頼境界 |
| --- | --- | --- |
| **Owner（デプロイ配線者）** | `setBranchAddresses` / `setCollateralRegistry` で Core 権限を一度だけ配線し renounce する | 使い捨て。renounce 後は `onlyOwner` 関数が恒久的に呼出不能 |
| **Core 呼出元（BO / AP / TM / SP / CR）** | 登録済みアドレスのみが `mint` / `burn` / `sendToPool` / `returnFromPool` を呼ぶ | 信頼（登録は owner 配線時に固定） |
| **bridgeAdmin** | bridge minter registry の管理・admin 移譲（Owner と独立ロール） | 信頼（contract-only・mainnet は Safe / Timelock holder。Day-1 は休眠 holder） |
| **bridge minter** | `bridgeMint` / self-burn `bridgeBurn` を実行する登録済み adapter | Day-1 は不在。Day-2 以降は完全信頼（contract-only・`bridgeAdmin` との兼任禁止）。登録前に per-chain cap / rate limit / global bridged supply cap / remote accounting / pause を adapter 側で強制する |
| **一般保有者 / 一般呼出者** | ERC-20 移転・permit | 敵対前提。protocol contract 宛の移転は revert |

## 5. インターフェース仕様

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `constructor(address,address)` | deploy | Owner と bridgeAdmin を設定 | CORE-BT-FR-001 / CORE-BT-FR-013 |
| `setBranchAddresses(address,address,address,address)` | external（onlyOwner） | branch の TM/SP/BO/AP を Core mint/burn 権限セットへ登録 | CORE-BT-FR-002 |
| `setCollateralRegistry(address)` | external（onlyOwner） | CR アドレスを設定し ownership を renounce（権限固定化） | CORE-BT-FR-003 |
| `mint(address,uint256)` | external（登録済み BO / AP のみ） | JPYdf 発行 | CORE-BT-FR-004 |
| `burn(address,uint256)` | external（CR・登録済み BO / TM / SP のみ） | JPYdf 償却（allowance 非依存） | CORE-BT-FR-005 |
| `proposeBridgeMinter(address)` / `confirmBridgeMinter()` / `cancelBridgeMinterProposal()` / `removeBridgeMinter(address)` | external（bridgeAdmin） | bridge minter registry 管理（追加は 48h timelock、削除は即時） | CORE-BT-FR-014 |
| `bridgeMint(address,uint256)` | external（登録済み bridge minter のみ） | bridge 用 JPYdf 発行 | CORE-BT-FR-015 |
| `bridgeBurn(uint256)` | external（登録済み bridge minter のみ） | bridge minter 自身の残高だけを burn | CORE-BT-FR-015 |
| `transferBridgeAdmin(address)` / `acceptBridgeAdmin()` / `renounceBridgeAdmin()` | external | bridgeAdmin の 2-step 移譲・安全な renounce | CORE-BT-FR-016 |
| `sendToPool(address,address,uint256)` | external（登録済み SP のみ） | 預入者 → SP への内部移転 | CORE-BT-FR-006 |
| `returnFromPool(address,address,uint256)` | external（登録済み SP のみ） | SP → 預入者への内部移転 | CORE-BT-FR-007 |
| `transfer(address,uint256) → bool` | public | ERC-20 移転（受取人制限付き） | CORE-BT-FR-008 |
| `transferFrom(address,address,uint256) → bool` | public | ERC-20 移転（受取人制限付き） | CORE-BT-FR-008 |
| `isValidRecipient(address) → bool` | external view | 外部 transfer と同じ受取人制限の判定 helper | CORE-BT-FR-008 |
| `requireValidRecipient(address)` | external view | 外部 transfer と同じ受取人制限の fail-fast helper | CORE-BT-FR-008 |
| `approve(address,uint256) → bool` | public | ERC-20 標準 | CORE-BT-FR-009 |
| `increaseAllowance(address,uint256) → bool` | public | ERC-20 標準（OZ 拡張） | CORE-BT-FR-009 |
| `decreaseAllowance(address,uint256) → bool` | public | ERC-20 標準（OZ 拡張） | CORE-BT-FR-009 |
| `allowance(address,address) → uint256` | public view | ERC-20 標準 | CORE-BT-FR-009 |
| `balanceOf(address) → uint256` | public view | ERC-20 標準 | CORE-BT-FR-009 |
| `totalSupply() → uint256` | public view | ERC-20 標準 | CORE-BT-FR-009 |
| `decimals() → uint8` | public view | 常に 18 | CORE-BT-FR-009 |
| `name() → string` | public view | `"JPYdf Stablecoin"` 🟡 | CORE-BT-FR-010 |
| `symbol() → string` | public view | `"JPYdf"` 🟡 | CORE-BT-FR-010 |
| `permit(address,address,uint256,uint256,uint8,bytes32,bytes32)` | public | EIP-2612 署名 approve | CORE-BT-FR-011 |
| `nonces(address) → uint256` | public view | EIP-2612 nonce | CORE-BT-FR-011 |
| `DOMAIN_SEPARATOR() → bytes32` | external view | EIP-712 ドメイン | CORE-BT-FR-011 |
| `eip712Domain() → (bytes1,string,string,uint256,address,bytes32,uint256[])` | public view | ERC-5267 ドメイン報告 | CORE-BT-FR-011 |
| `owner() → address` | public view | 現 Owner（renounce 後は `address(0)`） | CORE-BT-FR-012 |
| `isOwner() → bool` | public view | `msg.sender == owner` 判定 | CORE-BT-FR-012 |
| `collateralRegistryAddress() → address` | public view（自動生成 getter） | 設定済み CR アドレス | CORE-BT-FR-012 |
| `bridgeAdmin()` / `pendingBridgeAdmin()` / `proposedBridgeMinter()` / `bridgeMinterProposedAt()` / `bridgeMinterCount()` / `isBridgeMinter(address)` | external/public view | bridge readiness の状態証跡 | CORE-BT-FR-013 / CORE-BT-FR-014 |

## 6. 機能要件（FR）

### CORE-BT-FR-001: constructor（デプロイ初期化）🔵/🟡
- **Type**: Functional ｜ **Source**: base 実装（JpydfToken.sol）＋ CORE-MOD-008
- **シグネチャ**: `constructor(address _owner, address _bridgeAdmin)`
- **目的**: ERC-20 メタデータ・EIP-712 ドメイン・初期 Owner・独立 bridgeAdmin を固定してシステム唯一の JPYdf トークンを立ち上げる。
- **権限**: デプロイ時 1 度のみ。
- **事前条件（Checks）**: `_owner != address(0)`、`_bridgeAdmin != address(0)`、`_bridgeAdmin != _owner`、`_bridgeAdmin.code.length > 0`。
- **動作（Effects）**:
  1. `Ownable(_owner)`: `_owner` を Owner に設定し `OwnershipTransferred(address(0), _owner)` を発火
  2. `ERC20(_NAME, _SYMBOL)`: name/symbol を固定
  3. `ERC20Permit(_NAME)`: EIP-712 ドメイン（name=`_NAME`, version=`"1"`, chainId, 自アドレス）を構築し immutable にキャッシュ（OZ v4.9.5。name は 31 bytes 以下のため ShortString として保持）
  4. `bridgeAdmin = _bridgeAdmin` を設定し `BridgeAdminTransferred(address(0), _bridgeAdmin)` を発火
- **revert / 早期 return**: owner zero → `JpydfToken__ZeroOwner`；bridge admin zero → `JpydfToken__ZeroBridgeAdmin`；owner と bridgeAdmin 同一 → `JpydfToken__BridgeAdminCannotBeOwner`；bridgeAdmin が contract でない → `JpydfToken__BridgeAdminMustBeContract`。name/version が 31 bytes 超の場合のみ OZ `ShortStrings` が `StringTooLong(string)` で revert し得るが、固定値 16 bytes / 1 byte のため到達しない。
- **発火イベント**: `OwnershipTransferred`（CORE-BT-EVT-008）、`BridgeAdminTransferred`（CORE-BT-EVT-010）。
- **Verification**: parity（既存 ERC-20 / Ownable 初期状態。name/symbol 値は CORE-MOD-001、bridgeAdmin は CORE-MOD-008 として除外）＋ unit（constructor 不変条件）。

### CORE-BT-FR-002: setBranchAddresses（branch コントラクトの権限登録）🔵/🟡
- **Type**: Functional / Governance ｜ **Source**: base 実装（JpydfToken.sol）＋ CORE-MOD-009
- **シグネチャ**: `setBranchAddresses(address _troveManagerAddress, address _stabilityPoolAddress, address _borrowerOperationsAddress, address _activePoolAddress)`
- **目的**: 1 branch 分の TM / SP / BO / AP を mint・burn 等の権限セットへ登録する。branch 数だけ繰り返し呼ぶ。
- **権限**: `onlyOwner`。
- **事前条件（Checks）**: caller が Owner。4 引数はいずれも非ゼロかつ `code.length > 0` の contract address（CORE-MOD-009）。
- **動作（Effects）**:
  1. `troveManagerAddresses[_troveManagerAddress] = true` → `TroveManagerAddressAdded` 発火
  2. `stabilityPoolAddresses[_stabilityPoolAddress] = true` → `StabilityPoolAddressAdded` 発火
  3. `borrowerOperationsAddresses[_borrowerOperationsAddress] = true` → `BorrowerOperationsAddressAdded` 発火
  4. `activePoolAddresses[_activePoolAddress] = true` → `ActivePoolAddressAdded` 発火
- **revert / 早期 return**: 非 Owner → `"Ownable: caller is not the owner"`；ゼロアドレス → `JpydfToken__ZeroCoreAddress`；codeless address → `JpydfToken__CoreAddressMustBeContract`。
- **発火イベント**: CORE-BT-EVT-002〜005。
- **設計上のポイント**: mapping への追加（true 設定）のみで、登録解除の手段は存在しない。`setCollateralRegistry` 実行（=ownership renounce）以降は呼出不能となり、新 branch を後から JpydfToken に追加することはできない。CORE-MOD-009 によりゼロ / 未デプロイ address は token 側で拒否するが、正しい branch 種別・registry 整合性の検証は引き続きデプロイスクリプトと検証手順に依存する（CORE-BT-SEC-002）。
- **Verification**: parity / unit（onlyOwner・mapping 反映・イベント）。

### CORE-BT-FR-003: setCollateralRegistry（CR 設定と権限の恒久固定）🔵/🟡
- **Type**: Functional / Governance ｜ **Source**: base 実装（JpydfToken.sol）＋ CORE-MOD-009
- **シグネチャ**: `setCollateralRegistry(address _collateralRegistryAddress)`
- **目的**: CollateralRegistry（redemption 時の burn 呼出元）を設定し、同一 tx 内で ownership を放棄してデプロイ配線を完了・凍結する。
- **権限**: `onlyOwner`。
- **事前条件（Checks）**: caller が Owner。`_collateralRegistryAddress` は非ゼロかつ `code.length > 0` の contract address（CORE-MOD-009）。
- **動作（Effects）**:
  1. `collateralRegistryAddress = _collateralRegistryAddress` → `CollateralRegistryAddressChanged` 発火
  2. `_renounceOwnership()`: `OwnershipTransferred(旧 owner, address(0))` を発火し `_owner = address(0)`
- **revert / 早期 return**: 非 Owner → `"Ownable: caller is not the owner"`；ゼロアドレス → `JpydfToken__ZeroCoreAddress`；codeless address → `JpydfToken__CoreAddressMustBeContract`。
- **発火イベント**: CORE-BT-EVT-001、CORE-BT-EVT-008。
- **設計上のポイント**: 「1 回限り」は明示フラグではなく ownership renounce によって強制される（実行後は `onlyOwner` 関数全体が恒久的に呼出不能）。これにより `setBranchAddresses` も同時に封鎖されるため、本関数は**全 branch の登録完了後・デプロイ手順の最後**に呼ぶ必要がある。以後 Core owner は存在せず、Core 権限集合は完全固定化される。bridgeAdmin は別ロールとして存続する（CORE-BT-FR-013）。
- **Verification**: parity / unit（設定値・renounce 後の owner==0・再呼出 revert）。

### CORE-BT-FR-004: mint（発行）🔵
- **Type**: Functional ｜ **Source**: base 実装（JpydfToken.sol）
- **シグネチャ**: `mint(address _account, uint256 _amount)`
- **目的**: 債務発生・利息発行に対応して JPYdf を発行する。
- **権限**: 登録済み BorrowerOperations **または** ActivePool のみ（`_requireCallerIsBOorAP`: `borrowerOperationsAddresses[msg.sender] || activePoolAddresses[msg.sender]`）。
- **事前条件（Checks）**: 上記権限のみ（`_mint` 内部で `_account != address(0)` を要求）。
- **動作（Effects）**:
  1. `_mint(_account, _amount)`: `_account` 残高 +amount、`totalSupply` +amount
  2. ERC-20 `Transfer(address(0), _account, _amount)` 発火
- **revert / 早期 return**: 権限外 → `JpydfToken__CallerIsNotBorrowerOperationsOrActivePool`；`_account == address(0)` → `"ERC20: mint to the zero address"`。
- **発火イベント**: ERC-20 `Transfer`（mint、CORE-BT-EVT-006）。
- **設計上のポイント**: 呼出元は実装上 (a) BO の借入・debt 増額（借り手へ発行）、(b) AP の集計利息発行（SP yield 分 75% を SP へ、残余を interestRouter へ）および batch 管理 fee 発行、の 2 系統（各 BO / AP 担当節参照）。bridge minter はこの関数を呼べない。bridge supply path は別名 `bridgeMint`（CORE-BT-FR-015）に分離する。
- **Verification**: parity / unit（権限 revert・残高/supply 反映）。供給と債務のコントラクト横断整合は CORE-SYS-INV-003。

### CORE-BT-FR-005: burn（償却）🔵
- **Type**: Functional ｜ **Source**: base 実装（JpydfToken.sol）
- **シグネチャ**: `burn(address _account, uint256 _amount)`
- **目的**: 返済・redemption・清算 offset に対応して JPYdf を償却する。
- **権限**: CollateralRegistry（`msg.sender == collateralRegistryAddress`）、または登録済み BorrowerOperations / TroveManager / StabilityPool（`_requireCallerIsCRorBOorTMorSP`）。
- **事前条件（Checks）**: 上記権限；`_account` 残高 ≥ `_amount`（ERC-20 内部チェック）。
- **動作（Effects）**:
  1. `_burn(_account, _amount)`: `_account` 残高 −amount、`totalSupply` −amount
  2. ERC-20 `Transfer(_account, address(0), _amount)` 発火
- **revert / 早期 return**: 権限外 → `JpydfToken__CallerIsNotCoreBurner`；残高不足 → `"ERC20: burn amount exceeds balance"`。
- **発火イベント**: ERC-20 `Transfer`（burn、CORE-BT-EVT-006）。
- **設計上のポイント**: allowance 非依存の強権限だが、実装上の burn 対象は (a) BO: 返済・close する借り手（`msg.sender`）、(b) TM: shutdown 後 urgent redemption の実行者（`msg.sender`）、(c) CR: redemption 実行者（`msg.sender`）、(d) SP: 清算 offset 時の SP 自身（`address(this)`）に限られ、第三者残高を恣意的に焼く経路は core 実装には存在しない（CORE-BT-SEC-003）。bridge minter はこの関数を呼べず、bridge burn は self-burn 型 `bridgeBurn`（CORE-BT-FR-015）に分離する。
- **Verification**: parity / unit（4 系統の権限・残高不足 revert）。

### CORE-BT-FR-006: sendToPool（SP への預入移転）🔵
- **Type**: Functional ｜ **Source**: base 実装（JpydfToken.sol）
- **シグネチャ**: `sendToPool(address _sender, address _poolAddress, uint256 _amount)`
- **目的**: SP 預入（provideToSP）時に、預入者から SP へ JPYdf を allowance なしで内部移転する。
- **権限**: 登録済み StabilityPool のみ（`_requireCallerIsStabilityPool`: `stabilityPoolAddresses[msg.sender]`）。
- **事前条件（Checks）**: 上記権限；`_sender` 残高 ≥ `_amount`。
- **動作（Effects）**:
  1. `_transfer(_sender, _poolAddress, _amount)`（受取人制限 `_requireValidRecipient` は適用されない＝core 内部移転）
  2. ERC-20 `Transfer(_sender, _poolAddress, _amount)` 発火
- **revert / 早期 return**: 権限外 → `JpydfToken__CallerIsNotStabilityPool`；残高不足 → `"ERC20: transfer amount exceeds balance"`。
- **発火イベント**: ERC-20 `Transfer`（CORE-BT-EVT-006）。
- **設計上のポイント**: 実装上 SP は `sendToPool(msg.sender, address(this), _topUp)` の形でのみ呼ぶ（預入者は SP を呼んだ本人）。`_poolAddress` を SP 自身に固定するのは呼び手側の規律であり、本関数自体は引数を検証しない。
- **Verification**: parity / unit（SP 限定・移転反映）。

### CORE-BT-FR-007: returnFromPool（SP からの払戻移転）🔵
- **Type**: Functional ｜ **Source**: base 実装（JpydfToken.sol）
- **シグネチャ**: `returnFromPool(address _poolAddress, address _receiver, uint256 _amount)`
- **目的**: SP からの引出（withdrawFromSP）時に、SP から預入者へ JPYdf を内部移転する。
- **権限**: 登録済み StabilityPool のみ（`_requireCallerIsStabilityPool`）。
- **事前条件（Checks）**: 上記権限；`_poolAddress` 残高 ≥ `_amount`。
- **動作（Effects）**:
  1. `_transfer(_poolAddress, _receiver, _amount)`
  2. ERC-20 `Transfer(_poolAddress, _receiver, _amount)` 発火
- **revert / 早期 return**: 権限外 → `JpydfToken__CallerIsNotStabilityPool`；残高不足 → ERC-20 revert。
- **発火イベント**: ERC-20 `Transfer`（CORE-BT-EVT-006）。
- **Verification**: parity / unit（SP 限定・移転反映）。

### CORE-BT-FR-008: transfer / transferFrom / recipient helper（受取人制限付き ERC-20 移転）🔵/🟢
- **Type**: Functional ｜ **Source**: base 実装（JpydfToken.sol）
- **シグネチャ**: `transfer(address recipient, uint256 amount) → bool` ／ `transferFrom(address sender, address recipient, uint256 amount) → bool` ／ `isValidRecipient(address recipient) → bool` ／ `requireValidRecipient(address recipient)`
- **目的**: ERC-20 標準移転に受取人検証を上乗せし、誤送金による恒久ロックを防ぐ。補助 view は同じ判定を外部 contract が preflight できるようにする。
- **権限**: permissionless（`transferFrom` は allowance 要）。
- **事前条件（Checks）**: `_requireValidRecipient(recipient)`: `recipient != address(0) && recipient != address(this) && recipient != collateralRegistryAddress && !troveManagerAddresses[recipient] && !stabilityPoolAddresses[recipient] && !borrowerOperationsAddresses[recipient] && !activePoolAddresses[recipient]`。以降は OZ ERC20 標準（残高・allowance）。
- **動作（Effects）**:
  1. 受取人検証ののち `super.transfer` / `super.transferFrom` に委譲（残高移転、`transferFrom` は allowance 減算。`type(uint256).max` の allowance は減算しない＝OZ v4.9.5 標準）
  2. ERC-20 `Transfer` 発火（`transferFrom` で allowance が変動した場合 `Approval` も発火）
  3. `isValidRecipient` は同じ predicate を bool で返す。`requireValidRecipient` は同じ predicate に失敗した場合のみ revert し、状態を変更しない
- **revert / 早期 return**: `recipient` がゼロ、JpydfToken 自身、CollateralRegistry、登録済み TM/SP/BO/AP → `JpydfToken__CannotTransferToProtocolContract`；残高不足 / allowance 不足 → OZ ERC20 標準 revert。
- **発火イベント**: ERC-20 `Transfer` / `Approval`（CORE-BT-EVT-006/007）。
- **設計上のポイント**: core contract 宛のユーザー誤送金を防ぐための blacklist。`sendToPool` / `returnFromPool` は内部移転であり、この外部 transfer 制限を通らない。`requireValidRecipient` は `PILAllocator.registerInitiative` 等が 0 amount transfer の副作用なしに同じ制限を fail-fast するための helper。
- **Verification**: unit（制限 revert・標準移転）。

### CORE-BT-FR-009: ERC-20 標準準拠（approve / allowance / 残高・供給 view ほか）🔵
- **Type**: Functional ｜ **Source**: base 実装（OZ v4.9.5 ERC20 継承）
- **シグネチャ**: `approve(address,uint256) → bool` / `increaseAllowance(address,uint256) → bool` / `decreaseAllowance(address,uint256) → bool` / `allowance(address,address) → uint256` / `balanceOf(address) → uint256` / `totalSupply() → uint256` / `decimals() → uint8`
- **目的**: ERC-20 標準セマンティクスの提供。JpydfToken 固有の override はない。
- **権限**: permissionless。
- **動作（Effects）**: OZ v4.9.5 `ERC20` の標準実装に完全準拠。`decimals()` は固定 18。`decreaseAllowance` は現 allowance 未満への減算で `"ERC20: decreased allowance below zero"`、`approve` のゼロアドレス spender は `"ERC20: approve to the zero address"`。
- **revert / 早期 return**: OZ 標準どおり。
- **発火イベント**: `Approval`（CORE-BT-EVT-007）。
- **設計上のポイント**: OZ v4.9 系のため `increaseAllowance` / `decreaseAllowance` が ABI に存在する（v5 系では削除されている拡張）。
- **Verification**: parity（標準挙動の base 同一性）。

### CORE-BT-FR-010: name / symbol（トークン名・シンボル）🟡
- **Type**: Functional ｜ **Source**: DF 改変（JpydfToken.sol `_NAME` / `_SYMBOL`）＋ OZ ERC20 metadata
- **シグネチャ**: `name() → string` ／ `symbol() → string`
- **目的**: トークンのメタデータを返す。値はコンパイル時定数 `_NAME` / `_SYMBOL` で固定。
- **権限**: permissionless（view）。
- **動作（Effects）**: `name()` は `"JPYdf Stablecoin"`、`symbol()` は `"JPYdf"` を返す（変更手段なし）。
- **revert / 早期 return**: なし。
- **発火イベント**: なし。
- **Base との差分**: base では `_NAME = "BOLD Stablecoin"` / `_SYMBOL = "BOLD"`。DF では `_NAME = "JPYdf Stablecoin"` / `_SYMBOL = "JPYdf"`。根拠: CORE-MOD-001（§2.2）（JPYdf ブランドへの名称変更。ロジック・ストレージ・権限への影響はなく、波及は ERC-20 メタデータと EIP-712 ドメインの name 値のみ＝CORE-BT-FR-011）。
- **Verification**: unit（固定値の検証）。parity 対象からは値を除外し、CORE-MOD-001 としてトレースする。
- **設計上のポイント**: `_NAME` は `ERC20Permit(_NAME)` にも渡るため、EIP-2612 署名ドメインの name も `"JPYdf Stablecoin"` となる（base デプロイ品と署名互換性はないが、独立デプロイのため問題にならない）。

### CORE-BT-FR-011: permit（EIP-2612）と EIP-712 ドメイン view 群 🔵
- **Type**: Functional ｜ **Source**: base 実装（OZ v4.9.5 ERC20Permit / EIP712 継承）
- **シグネチャ**: `permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)` ／ `nonces(address owner) → uint256` ／ `DOMAIN_SEPARATOR() → bytes32` ／ `eip712Domain() → (bytes1, string, string, uint256, address, bytes32, uint256[])`
- **目的**: 事前 approve 不要の署名ベース allowance 設定（EIP-2612）と、署名生成に必要なドメイン情報の提供（ERC-5267）。
- **権限**: permissionless（署名検証のみ）。
- **事前条件（Checks）**: `block.timestamp <= deadline`；`ECDSA.recover` の署名者 `== owner`（nonce は `owner` の現在値を消費）。
- **動作（Effects）**:
  1. `_useNonce(owner)`: `nonces(owner)` を +1（連番強制・リプレイ防止）
  2. `_approve(owner, spender, value)` → `Approval` 発火
- **revert / 早期 return**: 期限超過 → `"ERC20Permit: expired deadline"`；署名者不一致（nonce ズレ含む） → `"ERC20Permit: invalid signature"`。
- **発火イベント**: ERC-20 `Approval`（CORE-BT-EVT-007）。
- **設計上のポイント**: ドメインは constructor で `(name=_NAME, version="1", chainId, address(this))` から構築し immutable キャッシュする（OZ v4.9.5。chain fork 等で chainId が変わった場合は都度再導出）。`eip712Domain()` は fields=`0x0f`（name/version/chainId/verifyingContract）を報告し、salt・extensions は未使用。`EIP712DomainChanged` イベントは ERC-5267 インターフェース宣言として ABI に現れるが、ドメイン不変のため**発火することはない**。name 値が base と異なる点は CORE-MOD-001 の帰結であり、permit ロジック自体は base と同一。
- **Verification**: parity（署名検証・nonce・revert 挙動）、unit（`DOMAIN_SEPARATOR` が name=`_NAME` から導出されること）。

### CORE-BT-FR-012: 自明 view 関数群（owner / isOwner / collateralRegistryAddress）🔵
- **Type**: Functional ｜ **Source**: base 実装（Ownable.sol / 自動生成 getter）
- **シグネチャ・返り値**:

  | 関数 | 返り値の意味 |
  | --- | --- |
  | `owner() → address` | 現 Owner。`setCollateralRegistry` 実行後は `address(0)` |
  | `isOwner() → bool` | `msg.sender == _owner` の判定（Liquity 版 Ownable 固有の public view） |
  | `collateralRegistryAddress() → address` | 設定済み CR（未設定なら `address(0)`） |
- **権限**: permissionless（view）。
- **Verification**: parity。

### CORE-BT-FR-013: bridgeAdmin と bridge readiness view 群 🟡
- **Type**: Functional / Governance ｜ **Source**: CORE-MOD-008
- **シグネチャ**: `bridgeAdmin()`, `pendingBridgeAdmin()`, `proposedBridgeMinter()`, `bridgeMinterProposedAt()`, `bridgeMinterCount()`, `isBridgeMinter(address)`
- **目的**: Core owner と独立した bridge governance 状態を保持し、Day-1 休眠状態（minter 0 件・pending proposal なし）を on-chain / manifest で証跡化する。
- **権限**: view は permissionless。状態変更は FR-014 / FR-016。
- **動作（Effects）**: なし（view）。constructor 時点で `bridgeAdmin = _bridgeAdmin`、その他はゼロ初期化。
- **設計上のポイント**: `setCollateralRegistry` により owner が `address(0)` になっても `bridgeAdmin` は別ストレージのため存続する。`bridgeAdmin` は contract address のみに限定する。Day-1 mainnet では Safe / Timelock holder を設定し、deployer と同一にしない。
- **Verification**: unit（owner renounce 後の bridgeAdmin 存続、view の初期値）。

### CORE-BT-FR-014: bridge minter registry（propose / confirm / cancel / remove）🟡
- **Type**: Functional / Governance ｜ **Source**: CORE-MOD-008
- **シグネチャ**: `proposeBridgeMinter(address)`, `confirmBridgeMinter()`, `cancelBridgeMinterProposal()`, `removeBridgeMinter(address)`
- **目的**: bridge adapter / minter の追加を 48h timelock 付きで慎重に行い、侵害・誤設定時は即時に削除できるようにする。
- **権限**: `bridgeAdmin` のみ。
- **事前条件（Checks）**:
  - `proposeBridgeMinter`: minter 非ゼロ、token 自身でない、current / pending `bridgeAdmin` でない、未登録、既存 proposal なし、contract address
  - `confirmBridgeMinter`: proposal あり、proposal 先が current / pending `bridgeAdmin` でない、contract address、`block.timestamp >= bridgeMinterProposedAt + 48 hours`
  - `cancelBridgeMinterProposal`: proposal あり
  - `removeBridgeMinter`: minter 登録済み
- **動作（Effects）**:
  - propose: `proposedBridgeMinter` と `bridgeMinterProposedAt` を設定
  - confirm: `bridgeMinterAddresses[minter] = true`、`bridgeMinterCount++`、proposal を消去
  - cancel: proposal を消去
  - remove: `bridgeMinterAddresses[minter] = false`、`bridgeMinterCount--`
- **revert / 早期 return**: 非 admin → `JpydfToken__CallerIsNotBridgeAdmin`；timelock 未経過 → `JpydfToken__BridgeMinterTimelockNotElapsed`；そのほか custom error は CORE-BT-ERR-001。
- **発火イベント**: CORE-BT-EVT-010。
- **設計上のポイント**: `JpydfToken` は proposal 先が adapter として十分な cap / rate / accounting / pause を持つかを introspect しない。`bridgeAdmin` は `proposeBridgeMinter` 前に CORE-BT-GOV-001 の Stage A activation package を承認し、`confirmBridgeMinter` 前にも同じ証跡を再確認する。条件を満たさない adapter は proposal せず、pending 中に条件が崩れた場合は cancel する。
- **Verification**: unit（timelock 境界、cancel、remove、count/view）。

### CORE-BT-FR-015: bridgeMint / bridgeBurn（bridge supply path）🟡
- **Type**: Functional ｜ **Source**: CORE-MOD-008
- **シグネチャ**: `bridgeMint(address _account, uint256 _amount)` / `bridgeBurn(uint256 _amount)`
- **目的**: Day-2 以降の token-only canonical bridge で、登録済み bridge minter が source/destination supply を調整できるようにする。
- **権限**: 登録済み bridge minter のみ（`bridgeMinterAddresses[msg.sender]`）。
- **動作（Effects）**:
  - `bridgeMint`: 通常 transfer と同じ protocol recipient blacklist を `_account` に適用してから `_mint(_account, _amount)`。`totalSupply` と `_account` 残高を増やす。
  - `bridgeBurn`: `_burn(msg.sender, _amount)`。bridge minter 自身の残高だけを burn する。
- **revert / 早期 return**: 非 minter → `JpydfToken__CallerIsNotBridgeMinter`；protocol recipient 宛の mint → `JpydfToken__CannotTransferToProtocolContract`；mint zero address / burn 残高不足は OZ ERC-20 revert。
- **発火イベント**: `BridgeMint` / `BridgeBurn` と ERC-20 `Transfer`。
- **設計上のポイント**: Core `mint` / `burn` には bridge minter を追加しない。`bridgeBurn(address from, uint256 amount)` のような任意アドレス burn は持たせず、minter compromise 時の被害面を self-burn に限定する。bridge minter は contract address のみで、`bridgeAdmin` との兼任を禁止する。token-level の per-chain cap / rate limit は持たないため、これらは登録済み adapter が on-chain で強制する（CORE-BT-SEC-005）。adapter が hard cap / rolling mint limit / global bridged supply cap / pause / replay・domain binding を持たない場合、`bridgeMint` を使わせない。
- **Verification**: unit（非 minter revert、mint、self-burn、remove 後遮断）。

### CORE-BT-FR-016: bridgeAdmin transfer / renounce 🟡
- **Type**: Functional / Governance ｜ **Source**: CORE-MOD-008
- **シグネチャ**: `transferBridgeAdmin(address)`, `acceptBridgeAdmin()`, `renounceBridgeAdmin()`
- **目的**: bridgeAdmin を 2-step で移譲し、完全に bridge readiness を放棄する場合も安全条件付きで renounce できるようにする。
- **権限**: `transferBridgeAdmin` / `renounceBridgeAdmin` は current `bridgeAdmin` のみ。`acceptBridgeAdmin` は `pendingBridgeAdmin` のみ。
- **事前条件（Checks）**:
  - transfer: new admin 非ゼロ、token 自身でない、current owner と非同一、登録済み / proposal 中の bridge minter でない、contract address
  - accept: caller が pending、登録済み / proposal 中の bridge minter でない、contract address
  - renounce: `bridgeMinterCount == 0`、`proposedBridgeMinter == address(0)`
- **動作（Effects）**: transfer は `pendingBridgeAdmin` を設定。accept は `bridgeAdmin` を pending に更新し pending を消去。renounce は `bridgeAdmin` と pending を消去。
- **revert / 早期 return**: 非 admin / 非 pending / live minter / pending proposal は require 文字列で revert。
- **発火イベント**: CORE-BT-EVT-010。
- **Verification**: unit（2-step、非 pending reject、live minter renounce reject、minter 0 で renounce）。

## 7. 状態変数・会計モデル

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `_NAME` | `string internal constant` | `"JPYdf Stablecoin"` 🟡（CORE-MOD-001（§2.2）） | ERC-20 name・EIP-712 ドメイン name の双方に使用 |
| `_SYMBOL` | `string internal constant` | `"JPYdf"` 🟡（CORE-MOD-001（§2.2）） | ERC-20 symbol |
| `collateralRegistryAddress` | `address public` | `setCollateralRegistry` で 1 度設定 | burn 権限を持つ CR の単一アドレス |
| `troveManagerAddresses` | `mapping(address => bool)`（internal） | `setBranchAddresses` で true 追加のみ | burn 権限セット（branch ごとの TM） |
| `stabilityPoolAddresses` | `mapping(address => bool)`（internal） | `setBranchAddresses` で true 追加のみ | burn / sendToPool / returnFromPool 権限セット |
| `borrowerOperationsAddresses` | `mapping(address => bool)`（internal） | `setBranchAddresses` で true 追加のみ | mint / burn 権限セット |
| `activePoolAddresses` | `mapping(address => bool)`（internal） | `setBranchAddresses` で true 追加のみ | mint 権限セット（利息・管理 fee の発行元） |
| （継承: Ownable）`_owner` | `address private` | constructor で `_owner` 引数、`setCollateralRegistry` 内の `_renounceOwnership()` で `address(0)` | デプロイ配線期間のみ有効な管理者 |
| （継承: ERC20）`_balances` / `_allowances` / `_totalSupply` / `_name` / `_symbol` | OZ v4.9.5 標準 storage | constructor（`_name`/`_symbol` は `_NAME`/`_SYMBOL`） | ERC-20 会計の正本 |
| （継承: ERC20Permit）`_nonces`（storage）・`_PERMIT_TYPEHASH_DEPRECATED_SLOT`（storage・OZ の互換 placeholder、未使用） | OZ v4.9.5 標準 | — | EIP-2612 リプレイ防止 |
| （継承: EIP712）`_nameFallback` / `_versionFallback`（storage・name/version が 31 bytes 超のときのみ使用＝本構成では常に空）・`_cachedDomainSeparator` / `_cachedChainId` / `_cachedThis` / `_hashedName` / `_hashedVersion` / `_name` / `_version`（immutable） | OZ v4.9.5 標準 | constructor で `EIP712(_NAME, "1")` として固定 | EIP-712 ドメイン（name は 🟡 CORE-MOD-001 の値） |

## 8. 不変条件（INV）

### CORE-BT-INV-001: 権限構成の恒久固定 🔵
`setCollateralRegistry` 実行後は `owner() == address(0)` であり、`collateralRegistryAddress` と 4 つの Core 権限 mapping は以後いかなる手段でも変更できない（追加・削除関数が存在せず、コントラクトは non-upgradeable）。Core `mint` / `burn` / `sendToPool` / `returnFromPool` の権限集合はデプロイ配線完了時点の値で恒久不変。

### CORE-BT-INV-002: ERC-20 会計整合 🔵
`totalSupply() == Σ balanceOf(a)`。供給の増減は Core `mint`（CORE-BT-FR-004）/ Core `burn`（CORE-BT-FR-005）/ `bridgeMint` / `bridgeBurn`（CORE-BT-FR-015）のみで生じる。
供給と全 branch 債務総額のコントラクト横断整合は CORE-SYS-INV-003 を参照。

### CORE-BT-INV-003: bridge readiness の休眠性 🟡
Day-1 launch 時点では `bridgeMinterCount == 0`、`proposedBridgeMinter == address(0)`、`bridgeMinterProposedAt == 0` である。bridgeAdmin は owner renounce 後も存続するが、minter が 0 件である限り `bridgeMint` / `bridgeBurn` を実行できるアドレスは存在しない。
- **Verification**: unit / deploy manifest evidence。

### CORE-BT-INV-004: bridge 有効化後の global canonical supply accounting 🟡
Day-2 以降に bridge minter を登録する場合、任意の監査 checkpoint で `globalCanonicalJpydfSupply = ethereumJpydfToken.totalSupply() - ethereumBridgeEscrowedCanonical + Σ remoteCanonicalJpydfSupply[chain]` を chain/domain 別に再構成できなければならない。burn/mint 型では `ethereumBridgeEscrowedCanonical = 0`、lock/unlock 型では source escrow を二重計上しない。source burn / lock と destination mint / unlock は finalized message 単位で 1:1 に対応し、pending / in-flight / failed message は canonical supply と別 bucket で追跡する。remote token、wrapped representation、test token、DEX LP token のどれを canonical JPYdf とみなすかは activation package で固定し、未承認 representation は supply accounting と user-facing canonical 表示から除外する。
- **Verification**: adapter invariant / off-chain accounting replay / fork・integration test / monitoring dry-run。

## 9. セキュリティ要件（SEC）

### CORE-BT-SEC-001: mint 権限の信頼境界 🔵
Core `mint` による JPYdf の供給増加は登録済み BO（借入）と AP（利息・batch 管理 fee 発行）のみが実行可能。この 2 契約以外（Owner / bridgeAdmin / bridge minter 含む）に Core `mint` 経路がないことが価値裏付けの前提。デプロイ配線で誤った（または悪意ある）アドレスを `setBranchAddresses` に渡すと無制限 Core mint が可能になるため、登録アドレスの正当性検証はデプロイ手順の必須項目。

### CORE-BT-SEC-002: 登録の不可逆性（デプロイ手順依存）🔵
`setBranchAddresses` / `setCollateralRegistry` は CORE-MOD-009 によりゼロアドレス・codeless address を拒否する。ただし重複、branch 種別の取り違え、別 branch contract の誤登録、registry との意味的整合までは token 側で検証しない。登録の取消手段はなく、`setCollateralRegistry` 後は owner が renounce されるため誤登録は恒久に残る。緩和策はデプロイスクリプトの検証・renounce 前の突合・manifest evidence である。

### CORE-BT-SEC-003: allowance 非依存の burn / 内部移転 🔵
`burn` / `sendToPool` / `returnFromPool` は保有者の approve なしに残高を動かせる。core 実装上の利用は本人起点フロー（返済・redemption・SP 預入/引出・SP offset）に限定されるが、信頼境界としては「登録済み core 契約は任意アカウントの JPYdf を償却・移転できる」ことを前提に監査・監視する。

### CORE-BT-SEC-004: bridge minter 信頼境界 🟡
登録済み bridge minter は `bridgeMint` により任意アカウントへ JPYdf を発行できる。`bridgeBurn` は self-burn 型で minter 自身の残高だけを焼くため、minter は任意ユーザー残高を直接 burn できない。minter 追加は 48h timelock、削除は即時。rate limit / message verification / bridge 固有の pause は minter / adapter 側の責務であり、`JpydfToken` は「登録済み minter かどうか」だけを判定する。

### CORE-BT-SEC-005: bridge adapter cap / rate / pause fail-closed gate 🟡
`JpydfToken` は non-upgradeable であり、bridge route ごとの cap / rate limit / pause / remote accounting を token 内で後付けできない。登録される bridge minter は、per-destination cap、per-route hourly / daily rolling mint limit、global bridged supply cap、route pause、message replay protection、source chain/domain binding、remote token binding、remote supply accounting を adapter 側で on-chain 強制しなければならない。これらを持たない adapter は `bridgeAdmin` が proposal / confirm してはならない。承認済み activation package がある場合、adapter を runtime cap 0 / route paused のまま minter 登録してよいが、nonzero cap や public route open は別 gate とする。token-level control が必要な設計に変更する場合は、既存 `JpydfToken` への unsafe registration ではなく、新 token / wrapper / migration を含む別設計・別監査として扱う。
- **Verification**: adapter unit / invariant / integration / incident dry-run。token 側 unit は「未登録・削除済み minter は mint 不能」を検証し、adapter control の検証は Day-2 activation package が持つ。

## 10. ガバナンス・運用・アップグレード要件（GOV）

- **Core 権限の固定化**: Owner は `setBranchAddresses`（branch 数だけ反復可）→ `setCollateralRegistry`（CR 設定と同時に `_renounceOwnership`）で使い捨てる。renounce 後、Core 権限集合（mint/burn 権限・CR 参照）は恒久固定で、branch の後付け追加・差替は不能（CORE-BT-FR-002 / CORE-BT-FR-003 / CORE-BT-INV-001）。
- **bridge governance の独立性**: `bridgeAdmin` は Owner と別ストレージで、owner renounce 後も存続する。`bridgeAdmin` / bridge minter は contract address のみ、admin と minter の兼任は禁止。bridge minter 追加は 48h timelock（`PRM-BRIDGE-MINTER-TIMELOCK`、[Parameters](../../../Parameters.md)）、削除は即時。admin 移譲は 2-step、renounce は `bridgeMinterCount == 0` かつ pending proposal なしのときのみ（CORE-BT-FR-013 / CORE-BT-FR-014 / CORE-BT-FR-016）。
- **非 upgradeable**: proxy を持たない。token ロジックの変更は再デプロイ級（Core / CollateralRegistry の immutable 前提と同じ扱い）。
- **Day-1 launch gate**: `bridgeMinterCount == 0` / `proposedBridgeMinter == address(0)` の休眠を必須とし、deploy manifest と governance handover evidence で証跡化する（CORE-BT-INV-003 / CORE-MOD-008、[Product-Overview](../Product-Overview.md) SYS-INV-003）。

### CORE-BT-GOV-001: bridge minter activation gate 🟡
`bridgeAdmin` は、[Bridge-Minter-Activation-Gate](../../operations/runbooks/Bridge-Minter-Activation-Gate.md) Stage A の activation package が承認されるまで、`proposeBridgeMinter` を実行してはならない。Stage A package は採用 bridge protocol / chain IDs / domain IDs / endpoint addresses、remote token / adapter addresses と codehash、approved pilot cap / rate limit、global bridged supply cap、remote supply accounting / monitoring plan、pause / guardian holder、admin / minter / upgrader / relayer / accounting operator の分離、adapter test / invariant evidence、internal differential review、incident runbook を含む。`confirmBridgeMinter` 前にも同じ package を再確認し、timelock 中に adapter upgrade、remote admin change、chain incident、verification drift があれば proposal を cancel する。`confirmBridgeMinter` 後から Stage B 前までに adapter / remote program codehash、endpoint config、remote token authority、role holder、cap / rate config が変わった場合は Stage A evidence を失効させ、route を paused / runtime cap 0 のまま再検証する。operator-only canary は adapter / endpoint enforced allowlisted operator / max amount / expiry / public flag closed の canary envelope 内だけで扱い、UI / ops flag だけで閉じる route、frontend / ops route flag の public open、third-party accessible route、canary envelope 超過、cap ramp は Stage B / C の別 gate とする。
- **Verification**: manual governance review / Safe・Timelock transaction evidence / adapter verification package / incident rehearsal。public route open は Stage B evidence、cap ramp は Stage C evidence を要求する。

## 11. イベント・監視要件（EVT）

| ID | Event | 発火箇所 | indexed | off-chain 用途 |
| --- | --- | --- | --- | --- |
| CORE-BT-EVT-001 | `CollateralRegistryAddressChanged(address _newCollateralRegistryAddress)` | `setCollateralRegistry` | なし | デプロイ配線完了（=権限凍結）の検知 |
| CORE-BT-EVT-002 | `TroveManagerAddressAdded(address _newTroveManagerAddress)` | `setBranchAddresses` | なし | branch 登録の監査証跡 |
| CORE-BT-EVT-003 | `StabilityPoolAddressAdded(address _newStabilityPoolAddress)` | `setBranchAddresses` | なし | 同上 |
| CORE-BT-EVT-004 | `BorrowerOperationsAddressAdded(address _newBorrowerOperationsAddress)` | `setBranchAddresses` | なし | 同上 |
| CORE-BT-EVT-005 | `ActivePoolAddressAdded(address _newActivePoolAddress)` | `setBranchAddresses` | なし | 同上 |
| CORE-BT-EVT-006 | ERC-20 `Transfer(address from, address to, uint256 value)` | mint（from=0）/ burn（to=0）/ 各移転 | from, to | 供給量・資金フローの追跡（subgraph 主要ソース） |
| CORE-BT-EVT-007 | ERC-20 `Approval(address owner, address spender, uint256 value)` | `approve` / `permit` / allowance 変動 | owner, spender | allowance 監視 |
| CORE-BT-EVT-008 | `OwnershipTransferred(address previousOwner, address newOwner)` | constructor / `_renounceOwnership` | previousOwner, newOwner | Owner 設定・renounce（newOwner=0）の検知 |
| CORE-BT-EVT-009 | `EIP712DomainChanged()` | **発火しない**（ERC-5267 宣言のみ・ドメイン不変） | なし | 監視不要（ABI 照合用に記載） |
| CORE-BT-EVT-010 | `BridgeAdminTransferStarted(address indexed currentBridgeAdmin, address indexed pendingBridgeAdmin)` / `BridgeAdminTransferred(address indexed previousBridgeAdmin, address indexed newBridgeAdmin)` / `BridgeMinterProposed(address indexed bridgeMinter, uint256 proposedAt, uint256 confirmableAt)` / `BridgeMinterProposalCancelled(address indexed bridgeMinter)` / `BridgeMinterConfirmed(address indexed bridgeMinter)` / `BridgeMinterRemoved(address indexed bridgeMinter)` / `BridgeMint(address indexed bridgeMinter, address indexed account, uint256 amount)` / `BridgeBurn(address indexed bridgeMinter, uint256 amount)` | constructor / bridgeAdmin functions / bridge supply path | 対象 address | bridge readiness の governance・activation・supply 監視。Day-2 bridge 有効化後は adapter event と合わせて CORE-BT-INV-004 の supply accounting / cap alert に使う |

## 12. 失敗時・異常系挙動（ERR）

### CORE-BT-ERR-001: 失敗時挙動（custom error / 標準 revert）🔵
| 条件 | revert |
| --- | --- |
| mint 権限外 | `JpydfToken__CallerIsNotBorrowerOperationsOrActivePool` |
| burn 権限外 | `JpydfToken__CallerIsNotCoreBurner` |
| sendToPool / returnFromPool 権限外 | `JpydfToken__CallerIsNotStabilityPool` |
| transfer/transferFrom/bridgeMint の受取人がゼロ / 自身 / 登録済み protocol contract | `JpydfToken__CannotTransferToProtocolContract` |
| setBranchAddresses / setCollateralRegistry の core address がゼロ | `JpydfToken__ZeroCoreAddress` |
| setBranchAddresses / setCollateralRegistry の core address が contract でない | `JpydfToken__CoreAddressMustBeContract` |
| constructor owner zero | `JpydfToken__ZeroOwner` |
| constructor bridgeAdmin zero | `JpydfToken__ZeroBridgeAdmin` |
| constructor / transferBridgeAdmin の bridgeAdmin と owner 同一 | `JpydfToken__BridgeAdminCannotBeOwner` |
| constructor / transferBridgeAdmin / acceptBridgeAdmin の bridgeAdmin が contract でない | `JpydfToken__BridgeAdminMustBeContract` |
| transferBridgeAdmin の bridgeAdmin が token 自身 | `JpydfToken__BridgeAdminCannotBeToken` |
| transferBridgeAdmin / acceptBridgeAdmin の bridgeAdmin が登録済みまたは proposal 中 bridge minter | `JpydfToken__BridgeAdminCannotBeMinter` |
| bridgeAdmin 以外が admin 関数呼出 | `JpydfToken__CallerIsNotBridgeAdmin` |
| bridge minter zero proposal | `JpydfToken__ZeroBridgeMinter` |
| bridge minter proposal が token 自身 | `JpydfToken__BridgeMinterCannotBeToken` |
| bridge minter proposal / confirm 先が current / pending bridgeAdmin | `JpydfToken__BridgeMinterCannotBeAdmin` |
| bridge minter proposal / confirm 先が contract でない | `JpydfToken__BridgeMinterMustBeContract` |
| 登録済み minter を propose | `JpydfToken__BridgeMinterAlreadySet` |
| pending proposal がある状態で propose | `JpydfToken__BridgeMinterAlreadyProposed` |
| proposal なしで confirm/cancel | `JpydfToken__NoBridgeMinterProposed` |
| bridge minter timelock 未経過 | `JpydfToken__BridgeMinterTimelockNotElapsed` |
| 未登録 minter の remove | `JpydfToken__NotBridgeMinter` |
| pendingBridgeAdmin 以外が accept | `JpydfToken__CallerIsNotPendingBridgeAdmin` |
| live bridge minter がある状態で renounceBridgeAdmin | `JpydfToken__BridgeMintersStillSet` |
| pending bridge minter proposal がある状態で renounceBridgeAdmin | `JpydfToken__CannotRenounceWithPendingBridgeMinter` |
| bridgeMint / bridgeBurn を非 minter が呼出 | `JpydfToken__CallerIsNotBridgeMinter` |
| onlyOwner 違反 | `"Ownable: caller is not the owner"` |
| ERC-20 / EIP-2612 標準違反 | OZ v4.9.5 標準文字列（残高不足・allowance 不足・期限超過・署名不一致等） |

（ABI 上のカスタムエラー `InvalidShortString()` / `StringTooLong(string)` は OZ `ShortStrings` 由来で、constructor の name/version 処理でのみ到達し得る＝運用時は発生しない。）

## 15. 参考資料

- 🔵 [Liquity v2 コア仕様](./Liquity-v2-Core-Spec.md) — Core `mint` / `burn` の呼出元（BO/AP/TM/SP/CR）、§2.2 DF 差分台帳（CORE-MOD-001 / 008 / 009）、redemption / 清算 / Stability Pool フロー
- 🧭 [Product Overview](../Product-Overview.md) — SYS-FR-006（bridge-ready dormant surface）/ SYS-CON-004 / SYS-INV-003
- 🧾 [Architecture Decision Records](../architecture/Architecture-Decision-Records.md#adr-004) — Coreから分離したbridge supply pathの設計理由
- 📊 [Parameters](../../../Parameters.md) — `PRM-BRIDGE-MINTER-TIMELOCK`（48h）ほか bridge security parameter の正本
- 🧯 [Bridge Minter Activation Gate](../../operations/runbooks/Bridge-Minter-Activation-Gate.md) — Day-2 bridge minter 登録前の cap / rate limit / remote supply accounting / incident runbook / adapter verification gate
- 🟢 [dToken 要件定義](./dToken.md) — Core が担保として扱うトークン（本書の債務トークンと対）
