# 🟢 dToken 要件定義

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Draft（実装あり・要件の正本化中） |
| Owner | DeltaForesight |
| 対象コントラクト | `contracts/src/DToken.sol`（本体・UUPS）/ `contracts/src/Interfaces/IDToken.sol`（規定インターフェース `IDToken`） |
| 関連ドキュメント | [Product-Overview](../Product-Overview.md)（アーキ・責務分離）/ [CollateralVault](./CollateralVault.md)（mint/burn 呼出側）/ [Strategy](./strategies/Strategy.md)（運用先）/ [Parameters](../../../Parameters.md)（mintCap 等の値） |

> 本書は [要件定義ドキュメント標準](../../../Requirements-Spec-Standard.md)に従う。要件・不変条件・セキュリティ要件には永続 ID（`DTKN-…`）を付し、相互参照は ID で行う。

---

## 1. 目的・スコープ・非責務

dToken は CollateralVault が発行・償却する**担保受益権トークン**（ERC-20, 18 decimals, UUPS）。Underlying（WETH / USDC 等）元本の **1:1 請求権**を表し、Liquity v2 コアからは「ごく普通の 18dec 担保 ERC-20」として扱われる。

- **本書が規定する**: decimals と Underlying 換算 / Underlying allowlist / 担保 Cap / `setTokenInfo`（Underlying 後付け確定）/ EIP-2612 Permit / mint・burn の認可 / `initialize`（遅延初期化）/ UUPS アップグレード / 2-step Owner 移譲 / Owner 放棄無効化。
- **本書が規定しない（非責務・他文書）**:
  - Underlying の保管・dToken の mint/burn **呼び出し**・buffer 会計・Strategy への配分・遅延償還・Vault 側 Underlying 後付け確定（`setUnderlying`）→ [CollateralVault](./CollateralVault.md)
  - Strategy 実装・`IStrategy` / `BaseStrategy` → [Strategy](./strategies/Strategy.md)
  - 担保別パラメータ（mintCap 等）の確定値 → [Parameters](../../../Parameters.md)
  - 🔵 Liquity コアの担保・清算・Redemption 挙動、および債務トークン `JpydfToken` の core surface（`setBranchAddresses` / `setCollateralRegistry` / `sendToPool` / `returnFromPool` / `transferFrom` の制限を含む）→ [JpydfToken](./JpydfToken.md) `CORE-BT-*`
- **責務境界（あえて知らない）**: dToken は Underlying の数量換算・Cap・発行/償却の認可を担い、発行時には対応ブランチの設定確定を確認する。運用先の資産評価は行わない。

---

## 2. 背景・設計方針

dToken の設計は、**Liquity v2 コアを無改変のまま使う**ための「担保ラッパー」として一貫している。

- **1:1 請求権トークン**: Underlying 元本に対する 1:1 の請求権を ERC-20 として発行する。コアはこれを担保トークンとしてのみ扱い、裏側の実資産・運用を知らない。
- **decimals = 18 固定**: Liquity 側の前提・実装都合に合わせ、担保トークンは 18dec に統一する。非 18dec Underlying は dToken 側で換算する（[DTKN-FR-003](#dtkn-fr-003-underlying--dtoken-換算)）。
- **Underlying allowlist**: mainnet では canonical token address の取り違えが不可逆な事故になるため、`setTokenInfo` 前に Owner が `setAllowedUnderlying(token, true)` で intended token を明示 allowlist する。`setTokenInfo` は allowlist されていない token、EOA、未デプロイアドレスを拒否する（[DTKN-FR-010](#dtkn-fr-010-underlying-allowlistsetallowedunderlying)）。
- **利回りを持たない**: dToken は残高が増えず価値も上がらない、あくまで "元本請求権"。運用益は Treasury へ集約してプロトコル収益化する。なお上振れ（運用益）は dToken に乗らない一方、**Strategy 毀損で裏付けが不足すると Underlying に対し下方デペグしうる**。この下方リスクの担保価格への反映は dToken の責務外で、Vault の `backingRatio()`（[CollateralVault](./CollateralVault.md) `VAULT-FR-016`）とオラクル（[Oracle](./Oracle.md) `ORCL-FR-014`）が担う（dToken 自身は価格を持たず数量換算のみ）。裏付け回復も dToken の rebase / supply 更新ではなく、Vault の Strategy 回収・writeoff・`backstopDeposit`（protected reserve 入金）/ `releaseBackstopToBuffer`（明示的な流動化、[CollateralVault](./CollateralVault.md) `VAULT-FR-017`）で行う。
- **発行・償却を Vault の会計に束ねる**: dToken が勝手に増減すると請求権が保管残高から乖離して崩壊するため、mint/burn 権限は対応 CollateralVault のみに限定する（[DTKN-SEC-001](#dtkn-sec-001-mintburn-を-vault-に限定)）。
- **遅延初期化（placeholder）方針**: デプロイ時は Underlying・name・symbol を未確定（placeholder）で立ち上げ、後から 1 度だけ `setTokenInfo` で確定する。これにより placeholder 担保ブランチを Day-1 に inert デプロイし、後から有効化できる（[DTKN-FR-002](#dtkn-fr-002-settokeninfo-による-underlying-後付け確定)）。

> コア無改変の全体方針・dToken がコアの担保である背景は [Product-Overview](../Product-Overview.md) §5 を正本とする。

---

## 3. 用語・外部依存・前提

**用語**

| 用語 | 意味 |
| --- | --- |
| Underlying | dToken がラップする実担保資産（WETH / USDC 等） |
| vault | この dToken の mint/burn を行う対応 CollateralVault |
| GOV_MULTISIG | ガバナンスのマルチシグ。dToken Owner の **holder は共通 TimelockController**であり、GOV multisig はその Timelock の PROPOSER/EXECUTOR として Owner 操作（`setCap` / `setTokenInfo` / upgrade 等）を提案・実行する（owner を GOV multisig へ直接配線しない・[DTKN-GOV-004](#dtkn-gov-004-owner-timelock)） |
| placeholder 期 / active 期 | `setTokenInfo` 前（Underlying 未確定）/ 後（確定）の状態 |
| `_decimalMultiplier` | 換算倍率 `10**(18 - underlyingDecimals)` |
| cap | dToken 総供給上限（= 事実上の担保総量上限） |

**外部依存（信頼する外部）**

- OpenZeppelin Contracts (upgradeable) **v4.9** — `ERC20Upgradeable` / `ERC20PermitUpgradeable`（`EIP712Upgradeable`）/ `OwnableUpgradeable` / UUPS。v4.9 の `EIP712Upgradeable` が `DOMAIN_SEPARATOR` をキャッシュしない性質に依拠する（[DTKN-FR-007](#dtkn-fr-007-permiteip-2612)）。
- 対応 CollateralVault — mint/burn の唯一の呼出元として完全信頼する（[DTKN-SEC-001](#dtkn-sec-001-mintburn-を-vault-に限定)）。

**前提**

- Liquity コアは担保を 18dec ERC-20 前提で扱う。
- `underlyingDecimals ≤ 18`（[DTKN-FR-002](#dtkn-fr-002-settokeninfo-による-underlying-後付け確定) で強制）。

---

## 4. アクター・ロール・信頼境界

| アクター | 操作 | 信頼境界 |
| --- | --- | --- |
| **Owner（holder = 共通 TimelockController）** | `setAllowedUnderlying` / `setTokenInfo` / `setCap` / アップグレード承認 / `transferOwnership` | 強力権限（Cap 変更・Underlying allowlist・Underlying 確定・ロジック差替）。**holder = 共通 TimelockController のみ**（GOV multisig は Timelock の PROPOSER/EXECUTOR・[DTKN-GOV-004](#dtkn-gov-004-owner-timelock)）。Owner 移譲は 2-step |
| **pendingOwner** | `acceptOwnership` | Owner が指定した移譲候補。承諾するまで Owner 権限は移らない |
| **vault（対応 CollateralVault）** | `mint` / `burn` | 完全信頼。mint/burn を無制限に行え、burn は保有者 allowance を要求しない。`initialize` で固定し不変 |
| **任意（permissionless）** | `convertTo*`（view）/ `permit`（署名検証） | 信頼不要 |

- **権限分離**: Owner も `mint`/`burn` はできず、`vault` も `setCap`/`setTokenInfo`/アップグレードはできない。

---

## 5. インターフェース仕様

規定インターフェース `IDToken`（および ERC-20 / ERC20Permit / UUPS 標準）。挙動は §6 機能要件、可視性のみ以下に要約（非規範）。

| 関数 | 可視性 | 要約 | 規定要件 |
| --- | --- | --- | --- |
| `initialize(address vault, address owner)` | external (initializer) | proxy 初期化（placeholder 立ち上げ） | DTKN-FR-001 |
| `setAllowedUnderlying(address underlying, bool allowed)` | external (onlyOwner) | `setTokenInfo` 前の Underlying allowlist 更新 | DTKN-FR-010 |
| `setTokenInfo(string name, string symbol, address underlying)` | external (onlyOwner) | Underlying・name・symbol を 1 度確定 | DTKN-FR-002 |
| `convertToDToken(uint256) → uint256` | external view | Underlying → 18dec | DTKN-FR-003 |
| `convertToUnderlying(uint256) → uint256` | external view | 18dec → Underlying | DTKN-FR-003 |
| `mint(address to, uint256 amount)` | external (onlyVault) | 発行 | DTKN-FR-004 |
| `burn(address from, uint256 amount)` | external (onlyVault) | 償却（allowance 非依存） | DTKN-FR-005 |
| `setRiskParamsRegistry(address registry)` | external (onlyOwner) | ブランチの発行条件を1度だけ紐づける | DTKN-FR-006 |
| `setCap(uint256 newCap)` | external (onlyOwner) | 担保 Cap 更新 | DTKN-FR-006 |
| `permit(...)` / `nonces(address)` | external | EIP-2612 | DTKN-FR-007 |
| `decimals() → uint8` | public view | 常に 18 | DTKN-INV-001 |
| `name()` / `symbol()` | public view | placeholder→確定値 | DTKN-FR-002 |
| `eip712Domain()` | external view | ERC-5267（実 name() 反映） | DTKN-FR-007 |
| `_authorizeUpgrade(address)` | internal (onlyOwner) | UUPS 承認 | DTKN-FR-008 |
| `pendingOwner()` | public view | 2-step 移譲候補 | DTKN-FR-009 |
| `transferOwnership(address)` | public (onlyOwner) | Owner 移譲開始 / pending cancel | DTKN-FR-009 |
| `acceptOwnership()` | public | pendingOwner による Owner 承諾 | DTKN-FR-009 |
| `renounceOwnership()` | public (onlyOwner) | 常に `RenounceOwnershipDisabled` で revert | DTKN-FR-009 |

---

## 6. 機能要件（FR）

### DTKN-FR-001: initialize（proxy 初期化・placeholder 立ち上げ）

- **Type**: Functional ｜ **Source**: Product-Overview「dToken Layer」/ placeholder ブランチ運用
- **シグネチャ**: `initialize(address vault, address owner)`
- **目的**: UUPS proxy 越しに 1 度だけ初期化する。デプロイ時点では Underlying・name・symbol を未確定（placeholder）で立ち上げ、後から DTKN-FR-002 `setTokenInfo` で確定する遅延初期化フロー（placeholder ブランチ対応）。
- **権限**: デプロイ手順（proxy 初期化）の一部。`owner` を束縛する（本番では holder = 共通 TimelockController。GOV multisig は Timelock の PROPOSER/EXECUTOR・[DTKN-GOV-004](#dtkn-gov-004-owner-timelock)）。
- **事前条件（Checks）**:
  - `vault` / `owner` がゼロアドレスでない（いずれかゼロなら revert）
  - 多重初期化は不可（1 度きり、再呼出は revert）
  - ロジックコントラクト（実装）自体は初期化不能とし、初期化は proxy 経由に限定する
- **動作（Effects）**:
  1. `vault` を束縛（この dToken の mint/burn を行う対応 CollateralVault。**初期化時に固定し、以後変更しない**＝再設定用 setter を設けない）
  2. `owner` を設定（`setCap` / `setTokenInfo` / アップグレード承認の権限。本番 holder = 共通 TimelockController・[DTKN-GOV-004](#dtkn-gov-004-owner-timelock)）
  3. `cap = 0`（発行停止。DTKN-FR-006）で初期化
  4. placeholder の `name` / `symbol` で初期化（確定値は `setTokenInfo` が上書き。EIP-712 domain も実 `name()` を追従＝DTKN-FR-007）
  5. `underlying` は未設定（`address(0)`）のまま（確定は `setTokenInfo` のみ。DTKN-FR-002）
- **revert / 早期 return**: `vault` / `owner` がゼロ → revert。再初期化 → revert。
- **発火イベント**: なし（Underlying・name・symbol の確定は DTKN-EVT-001 `TokenInfoSet` で観測）。
- **設計上のポイント**: **`vault` 不変性** — mint/burn は `vault` のみに限定される（DTKN-SEC-001）。`vault` を後から変更可能にすると担保の発行・償却権限ごと移し替えられてしまうため、`vault` は初期化時固定とする。Vault 側の機能更新は CollateralVault の UUPS アップグレードで行い、dToken の `vault` 参照先は変えない。
- **Verification**: unit（再初期化 revert・ゼロアドレス revert・初期 cap/placeholder 値）。

### DTKN-FR-002: setTokenInfo による Underlying 後付け確定

- **Type**: Functional ｜ **Source**: Product-Overview「placeholder ブランチ」/ [CollateralVault](./CollateralVault.md) deferred-binding
- **シグネチャ**: `setTokenInfo(string name, string symbol, address underlying)`
- **目的**: デプロイ後に Owner が **1 度だけ** Underlying・name・symbol を確定し、同時に換算倍率 `_decimalMultiplier = 10**(18 - underlyingDecimals)` を保存する。事後変更は提供しない（「未確定で立ち上げ、後から 1 度だけ確定」のみ許容）。
- **権限**: dToken の Owner（holder = 共通 TimelockController）のみ。
- **事前条件（Checks）**（すべて満たす）:
  - `caller == Owner`
  - `underlying` 未設定（`address(underlying) == address(0)`）
  - 未発行（`totalSupply() == 0`）
  - `underlying`/`name`/`symbol` が空・ゼロでない
  - `underlying` は deployed contract（EOA / 未デプロイアドレス不可）
  - `allowedUnderlying[underlying] == true`（[DTKN-FR-010](#dtkn-fr-010-underlying-allowlistsetallowedunderlying)）
  - `underlying.decimals() ≤ 18`
- **動作（Effects）**:
  1. `underlying`/`name`/`symbol` を確定（以後不変）
  2. `underlying.decimals()` を取得し倍率 `_decimalMultiplier = 10**(18 - underlyingDecimals)` を計算・保存（換算式は DTKN-FR-003）
  3. `TokenInfoSet` を発火
- **revert / 早期 return**: 非 Owner；設定済みの再呼出 → `TokenInfoAlreadySet`；`totalSupply() > 0` → `SupplyAlreadyExists`；`underlying == address(0)` → `ZeroAddress`；空 name → `EmptyTokenName`；空 symbol → `EmptyTokenSymbol`；EOA / 未デプロイアドレス → `NotContract`；allowlist 未承認 → `UnderlyingNotAllowed`；`decimals > 18` → `InvalidUnderlyingDecimals`。
- **発火イベント**: `TokenInfoSet(name, symbol, underlying, underlyingDecimals)`（DTKN-EVT-001）。
- **設計上のポイント**: placeholder Vault と組み合わせる場合は **allowlist → dToken-first**。先に `setAllowedUnderlying(token, true)` で intended token を固定し、次に `setTokenInfo`、後続の `CollateralVault.setUnderlying(token)` が `dToken.underlying() == token` を検証する。不一致は `UnderlyingMismatch`（Vault 側）。placeholder 有効化中は実 PriceFeed の `confirmSourceEmergency()` 完了まで cap を 0 に維持し、最後に `setCap` で mint を解放する（DTKN-FR-006）。通常 source 差替で新旧価格差が 1% 以内なら `confirmSource()` を使うが、placeholder sentinel から実価格への差替は価格差 guard を越えるため emergency 経路を使う。
- **Verification**: unit（一度きり・各 revert 条件・倍率計算）, invariant=DTKN-INV-003 / DTKN-INV-004。

### DTKN-FR-003: Underlying ↔ dToken 換算

- **Type**: Functional ｜ **Source**: Product-Overview「18dec 統一」
- **シグネチャ**: `convertToDToken(uint256 underlyingAmount) → uint256` ／ `convertToUnderlying(uint256 dTokenAmount) → uint256`（いずれも external view）
- **目的**: 非 18dec Underlying と 18dec dToken の数量換算を dToken 自身が保持・提供する（Vault が deposit/redeem 時に呼ぶ）。`IDToken` 規定の 2 view。
- **権限**: なし（external view）。
- **事前条件（Checks）**: `_decimalMultiplier != 0`（Underlying 確定済み）。
- **動作（Effects）**:
  1. `convertToDToken`: `dTokenAmount = underlyingAmount * _decimalMultiplier`（**乗算のみで厳密**。桁あふれは Solidity 0.8 checked で revert）
  2. `convertToUnderlying`: `underlyingAmount = dTokenAmount / _decimalMultiplier`（**整数除算で floor**。倍率未満の端数は 0）
- **revert / 早期 return**: 未確定（`_decimalMultiplier == 0`）→ `TokenInfoNotSet`。
- **発火イベント**: なし（view）。
- **設計上のポイント**:
  - 切り捨ては縮小方向（`convertToUnderlying`）のみ＝端数を Vault/buffer に残す**安全側**（ユーザー過大払い防止）。
  - **往復の厳密性**: deposit の dToken は倍率の整数倍なので同額 redeem の往復は dust 0。倍率の整数倍でない残高（transfer 取得など）は `convertToUnderlying` 単体では floor されるが、Vault の redeem / redeemWithPermit は burn 前に `convertToDToken(convertToUnderlying(amount)) == amount` を要求し、ゼロ払い・端数焼却を拒否する（[CollateralVault](./CollateralVault.md) `VAULT-FR-002` / `VAULT-FR-003`）。
  - 18dec Underlying は倍率 1 で恒等変換。例: 8dec WBTC 倍率 1e10 → `convertToDToken(1e8)=1e18` / `convertToUnderlying(1e10−1)=0`。利用箇所: deposit→`convertToDToken`、redeem/収益化→`convertToUnderlying`（[CollateralVault](./CollateralVault.md)）。
- **Verification**: unit（境界例）, fuzz=DTKN-INV-006（往復 dust 0）。

### DTKN-FR-004: mint（発行）

- **Type**: Functional ｜ **Source**: Product-Overview「dToken Layer」
- **シグネチャ**: `mint(address to, uint256 amount)`
- **目的**: Underlying 受領に対応して dToken を発行する。請求権総量を Vault 会計に束ねるため vault のみに限定。
- **権限**: **vault（対応 CollateralVault）のみ**。Owner も不可（権限分離）。
- **事前条件（Checks）**: `caller == vault`；Underlying 確定済み；`riskParamsRegistry` 設定済みかつ `riskParamsFinalized()==true`；`totalSupply() + amount ≤ cap`。
- **動作（Effects）**:
  1. `to` の残高 +amount、`totalSupply` +amount
  2. ERC20 `Transfer(address(0), to, amount)` を発火
- **revert / 早期 return**: 非 vault → `OnlyVault`；未確定 → `TokenInfoNotSet`；Registry 未設定またはリスク設定未確定 → `DToken__RiskParamsNotFinalized`；`totalSupply()+amount > cap` → `CapExceeded`。
- **発火イベント**: ERC20 `Transfer`（mint, from=0）。
- **設計上のポイント**: 未確定 mint を禁止するのは、`totalSupply()>0` になると `setTokenInfo` が恒久不能化して placeholder のまま stranded になるのを防ぐため（DTKN-SEC-004）。
- **Verification**: unit（vault 限定・cap 超過・TokenInfoNotSet）, invariant=DTKN-INV-002 / DTKN-INV-005。

### DTKN-FR-005: burn（償却・allowance 非依存）

- **Type**: Functional ｜ **Source**: Product-Overview「dToken Layer」/ [CollateralVault](./CollateralVault.md) 償還フロー
- **シグネチャ**: `burn(address from, uint256 amount)`
- **目的**: 償還フローで保有者の dToken を償却する。**allowance を要求しない**強い権限を vault だけに閉じる。
- **権限**: **vault のみ**。Owner も不可。
- **事前条件（Checks）**: `caller == vault`；`from` の残高 ≥ amount。
- **動作（Effects）**:
  1. `from` の残高 −amount、`totalSupply` −amount
  2. ERC20 `Transfer(from, address(0), amount)` を発火
- **revert / 早期 return**: 非 vault → `OnlyVault`；残高不足 → ERC20 revert。
- **発火イベント**: ERC20 `Transfer`（burn, to=0）。
- **設計上のポイント**: allowance を要求しないのは Vault が償還フローで保有者の dToken を直接償却するため。vault 限定によりこの allowance 非依存の償却権限を vault だけに閉じる（信頼境界＝DTKN-SEC-002）。
- **Verification**: unit（vault 限定・allowance 非依存・残高不足 revert）, invariant=DTKN-INV-002。

### DTKN-FR-006: setCap による担保 Cap の更新

- **Type**: Functional ｜ **Source**: Product-Overview「担保Cap」/ [Parameters](../../../Parameters.md) mintCap
- **シグネチャ**: `setCap(uint256 newCap)`
- **目的**: dToken 総供給上限（=事実上の担保総量上限）を更新する。担保 Cap は dToken 自身が保持・検証する。
- **権限**: dToken の Owner（holder = 共通 TimelockController）のみ。
- **事前条件（Checks）**: `caller == Owner`。`newCap > 0` の場合は Registry 設定済みかつリスク設定確定済み。`setCap(0)` は常に許可する。
- **動作（Effects）**:
  1. `cap = newCap`（**現 `totalSupply()` 未満も設定可**＝新規 mint のみ停止し既発行は維持）
  2. `CapUpdated(oldCap, newCap)` を発火
- **revert / 早期 return**: 非 Owner → revert。正の cap を設定する際に Registry 未設定またはリスク設定未確定なら `DToken__RiskParamsNotFinalized`。
- **発火イベント**: `CapUpdated(oldCap, newCap)`（DTKN-EVT-002）。
- **設計上のポイント**: cap の初期値は `0`。正の値への変更と mint は、紐づけた Registry のリスク設定が確定済みの場合に限る（DTKN-FR-004）。
- **Verification**: unit（Owner 限定・`newCap < totalSupply` 可・既発行維持）, invariant=DTKN-INV-005。

Owner は `cap==0` かつ `totalSupply()==0` の間に、`setRiskParamsRegistry(address)` で対応する `AddressesRegistry` を一度だけ紐づける。宛先にはコードが存在し、`collToken()` がこの dToken と一致しなければならない。紐づけ時に `RiskParamsRegistryBound(registry)` を発火する。ブランチの `finalizeRiskParams` が要求する供給量0を維持し、確定前の入金による有効化の妨害を防ぐ。稼働済みトークンへのアップグレードでは、既存供給を保持したままの紐づけはできないため、別途移行設計を要する。

### DTKN-FR-007: permit（EIP-2612）

- **Type**: Functional ｜ **Source**: [CollateralVault](./CollateralVault.md) `redeemWithPermit` / [Zapper](./Zapper.md) permit 経路
- **シグネチャ**: `permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)` ／ `nonces(address owner)`
- **目的**: 事前 approve なしに署名 1 つで allowance を発行する。`DOMAIN_SEPARATOR` は `setTokenInfo` 確定後の実 `name()` を**追従**する（placeholder 名に固定されない）。OZ `ERC20PermitUpgradeable` 継承。ERC-5267 `eip712Domain()` も現 `name()`・version `"1"` を報告。
- **権限**: なし（permissionless・署名検証のみ）。
- **事前条件（Checks）**: 有効な署名（owner/spender/value/deadline/v/r/s）。
- **動作（Effects）**:
  1. `allowance(owner, spender) = value`、`nonces(owner)` +1
  2. `_EIP712Name()` を override し `name()` を返す → `DOMAIN_SEPARATOR()` の name ハッシュが実トークン名から導出（`DOMAIN_SEPARATOR() = keccak256(abi.encode(typehash, keccak256(name()), keccak256("1"), chainId, address(this)))`）
- **revert / 早期 return**: 署名不一致／期限切れ／nonce ズレ → revert。
- **発火イベント**: ERC20 `Approval`。
- **設計上のポイント**:
  - **追加 storage・gap 変更・再初期化は不要**: OZ v4.9 `EIP712Upgradeable` は proxy 向けに `DOMAIN_SEPARATOR` をキャッシュせず、`_domainSeparatorV4()` が毎回 `_EIP712NameHash()=keccak256(_EIP712Name())` から再導出する。`_EIP712Name()` は `virtual`。
  - **署名前に name 確定**: `setTokenInfo` は一度きり・`totalSupply()==0` 条件（DTKN-FR-002）のため、保有者が permit に署名するより前に name が確定する。
  - **代替案比較**: placeholder 名固定は `name()` 由来署名と on-chain domain の食い違いで `permit()` revert（UX 破壊・資金影響なし）。`initialize` で name 固定する案は遅延初期化フローを崩す。本方式は最小で OZ 公式 override hook を使う（前例: Circle USDC）。
- **Verification**: unit（確定後の `DOMAIN_SEPARATOR()` が `name()` を反映）, integration（標準ウォレットが `name()` から組んだ署名が `permit()` で検証成立）。

### DTKN-FR-008: アップグレード（UUPS）

- **Type**: Functional ｜ **Source**: Product-Overview「dToken Layer (UUPS)」
- **シグネチャ**: `_authorizeUpgrade(address newImpl)`（internal・UUPS authorization）
- **目的**: UUPS でロジック差替により請求権・換算・Cap 等の挙動を将来修正できるようにする。
- **権限**: 新実装の承認は **Owner（holder = 共通 TimelockController）のみ**。運用ロール（Vault / Strategy 等）は不可。
- **事前条件（Checks）**: `caller == Owner`。
- **動作（Effects）**:
  1. 実装アドレスを差替（UUPS）。ストレージは追記のみ（既存スロットの並べ替え・型変更をしない。gap で将来分を予約）
  2. ERC1967 `Upgraded(newImpl)` を発火
- **revert / 早期 return**: 非 Owner → revert。
- **発火イベント**: ERC1967 `Upgraded(newImpl)`。
- **設計上のポイント**: dToken 自体に内蔵 timelock はない。Owner を共通 TimelockController に置くことで全 Owner 操作に公示遅延を掛ける（[DTKN-GOV-004](#dtkn-gov-004-owner-timelock)）。Oracle PriceFeedProxy の内蔵 delay は別に管理する。
- **Verification**: unit（Owner 限定承認・運用ロール revert）, manual（storage layout review・gap 確保）。

### DTKN-FR-009: Owner 移譲（2-step）と renounce 無効化

- **Type**: Functional / Security ｜ **Source**: mainnet 権限運用・Oracle `Ownable2Step` 方針との整合
- **シグネチャ**: `pendingOwner() → address` / `transferOwnership(address newOwner)` / `acceptOwnership()` / `renounceOwnership()`
- **目的**: dToken の Owner は `setTokenInfo` / `setCap` / UUPS upgrade を握る強権限であり、誤アドレスへの 1-step 移譲や Owner 放棄で恒久的に運用不能化してはならない。Owner 移譲は候補者の明示承諾を要求し、Owner 放棄はコード上 revert で無効化する。
- **権限**:
  - `transferOwnership`: 現 Owner のみ
  - `acceptOwnership`: `pendingOwner` のみ
  - `renounceOwnership`: 現 Owner のみ呼べるが常に revert
- **事前条件（Checks）**:
  - `transferOwnership`: `caller == owner`
  - `acceptOwnership`: `caller == pendingOwner`
  - `renounceOwnership`: `caller == owner`
- **動作（Effects）**:
  1. `transferOwnership(newOwner)` は `_pendingOwner = newOwner` を保存し、`OwnershipTransferStarted(owner, newOwner)` を発火する。`newOwner == address(0)` は pending 移譲のキャンセルとして扱う
  2. `acceptOwnership()` は `owner = pendingOwner` に移譲し、`pendingOwner` をクリアする（OZ `OwnershipTransferred` 発火）
  3. `renounceOwnership()` は `RenounceOwnershipDisabled` で revert し、Owner を維持する
- **revert / 早期 return**: 非 Owner の `transferOwnership` / `renounceOwnership` は OZ Ownable revert。非 pendingOwner の `acceptOwnership` は `Ownable2Step: caller is not the new owner`。
- **発火イベント**: `OwnershipTransferStarted(previousOwner, newOwner)` / OZ `OwnershipTransferred(previousOwner, newOwner)`。
- **設計上のポイント**: `_pendingOwner` は dToken 自身の storage gap を 1 slot 消費して追加する。既存の `OwnableUpgradeable` 継承順は変えず、既存 storage slot を動かさない。
- **Verification**: unit（2-step 移譲・pending cancel・非 pending accept revert・renounce disabled・新 Owner による `setCap`）。

### DTKN-FR-010: Underlying allowlist（setAllowedUnderlying）

- **Type**: Functional / Security ｜ **Source**: mainnet deploy 手順・canonical token 誤指定防止
- **シグネチャ**: `setAllowedUnderlying(address underlying, bool allowed)`
- **目的**: `setTokenInfo` の前段で、当該 dToken が bind してよい Underlying contract を Owner が明示する。USDC など同名・類似 symbol・proxy / bridged token が複数存在し得る asset で、誤アドレスを一度きり setter に渡す事故を防ぐ。
- **権限**: dToken の Owner（holder = 共通 TimelockController）のみ。
- **事前条件（Checks）**:
  - `caller == Owner`
  - `underlying != address(0)`
  - `underlying.code.length > 0`（EOA / 未デプロイアドレス不可）
  - `setTokenInfo` 未実行（`address(underlying()) == address(0)`）
- **動作（Effects）**:
  1. `allowedUnderlying[underlying] = allowed` を保存
  2. `AllowedUnderlyingUpdated(underlying, allowed)` を発火
- **revert / 早期 return**: 非 Owner；ゼロアドレス → `ZeroAddress`；EOA / 未デプロイアドレス → `NotContract`；token info 確定後 → `TokenInfoAlreadySet`。
- **発火イベント**: `AllowedUnderlyingUpdated(underlying, allowed)`（DTKN-EVT-005）。
- **設計上のポイント**:
  - allowlist は bind 前の deploy safety rail であり、active 後の token 差替機構ではない。`setTokenInfo` 後は更新不可。
  - mainnet 手順では、USDC は canonical mainnet USDC contract だけを allowlist する。USDC は blacklistable token であり、blacklist による transfer revert は Vault 側の個別 redeem / claim tx の revert として扱う（batch push はしない）。詳細は [CollateralVault](./CollateralVault.md)。
  - `allowed=false` は誤 allowlist の取り消しに使う。`setTokenInfo` 成功前であれば再設定できる。
- **Verification**: unit（ゼロ・EOA・非 Owner・bind 後更新不可・イベント・allow/remove・`setTokenInfo` 未承認 revert）。

---

## 7. 状態変数・会計モデル

| 変数 | 型 | 説明 | 確定 |
| --- | --- | --- | --- |
| `vault` | `address` | mint/burn を行う対応 CollateralVault | `initialize` で固定・不変 |
| `underlying` | `address` | ラップ対象。未確定は `address(0)` | `setTokenInfo` で 1 度 |
| `_decimalMultiplier` | `uint256` | `10**(18 - underlyingDecimals)`。未確定は `0` | `setTokenInfo` で 1 度 |
| `riskParamsRegistry` | `address` | 発行可否を参照するブランチ Registry | `setRiskParamsRegistry` で1度 |
| `cap` | `uint256` | 総供給上限。初期値 `0` | `initialize` 既定 / `setCap` 更新 |
| `allowedUnderlying` | `mapping(address => bool)` | `setTokenInfo` 前に bind 可能な intended Underlying | `setAllowedUnderlying`（`setTokenInfo` 後は更新不可） |
| `name` / `symbol` | `string` | placeholder→確定 | `setTokenInfo` |
| `_pendingOwner` | `address` | 2-step Owner 移譲候補 | `transferOwnership` / `acceptOwnership` |
| `nonces` | `mapping` | EIP-2612 nonce | — |

**会計モデル**: dToken は **1:1 請求権**であり利回りを持たない（残高・価値は増えない）。価値の会計（buffer/principal/profit/dust）はすべて Vault 側に属し、dToken は供給量（`totalSupply`）と換算（`_decimalMultiplier`）のみを司る。Underlying との数量関係は常に「`totalSupply` = 既発行 dToken 量、対応 Underlying = `convertToUnderlying(totalSupply)`（floor 安全側）」。ただし Vault の `actualLiabilities()` は legacy / migration 由来の総供給 dust が存在する場合に Underlying 1 base unit へ切り上げて保守評価する。この換算は**名目元本**（1:1 請求権の額面）であり、実保有がこれを下回る（Strategy 毀損）場合の**実質裏付け率**は Vault が `backingRatio()`（[CollateralVault](./CollateralVault.md) `VAULT-FR-016`）として算出し、オラクルが担保価格へ反映する（[Oracle](./Oracle.md) `ORCL-FR-014`）。dToken 自身は名目換算のみを司り、裏付け率の会計・価格反映・補填入金は持たない。

---

## 8. 不変条件（INV）

| ID | 不変条件 | 検証 |
| --- | --- | --- |
| DTKN-INV-001 | `decimals()` は Underlying 確定の前後を問わず常に 18 | unit |
| DTKN-INV-002 | `mint`/`burn` は `vault` のみが実行できる（Owner も不可） | invariant |
| DTKN-INV-003 | `setTokenInfo` は `totalSupply()==0` のときのみ成功し、確定後の `underlying`/`name`/`symbol`/`_decimalMultiplier` は不変 | invariant |
| DTKN-INV-004 | `_decimalMultiplier` は確定後 `10**(18 - underlyingDecimals)`、確定前は `0` | unit |
| DTKN-INV-005 | `mint` は `totalSupply()+amount ≤ cap` のときのみ成功（超過は `CapExceeded`）。※`setCap` は cap を現 `totalSupply()` 未満へ下げられるため `totalSupply() ≤ cap` は**大域不変ではない**（[DTKN-FR-006](#dtkn-fr-006-setcap-による担保-cap-の更新)） | invariant |
| DTKN-INV-006 | 換算の整合: `convertToDToken` は乗算厳密、`convertToUnderlying` は floor（安全側）。倍率の整数倍 dToken の往復は dust 0 | fuzz |
| DTKN-INV-007 | `vault` は `initialize` 後不変 | invariant |
| DTKN-INV-008 | Underlying 未確定（`_decimalMultiplier==0`）の間は `convertTo*`/`mint` が `TokenInfoNotSet` で revert | unit |
| DTKN-INV-009 | Owner は `acceptOwnership` 成功時のみ変更され、`renounceOwnership` では変更されない | unit |
| DTKN-INV-010 | `setTokenInfo` は `allowedUnderlying[underlying] == true` かつ `underlying.code.length > 0` のときのみ成功し、`setTokenInfo` 後は allowlist 更新できない | unit |

---

## 9. セキュリティ要件（SEC）

### DTKN-SEC-001: mint/burn を vault に限定

- Type: Security
- Statement: `mint`/`burn` は `vault` のみが呼べ、Owner を含む他アドレスは `OnlyVault` で revert しなければならない（least privilege・請求権総量と保管残高の乖離防止）。
- Verification: unit（非 vault revert）, invariant=DTKN-INV-002

### DTKN-SEC-002: allowance 非依存 burn の閉じ込め

- Type: Security
- Statement: `burn` が保有者の allowance を要求しない強い権限は、`vault` 限定（DTKN-SEC-001）により vault だけに閉じられていなければならない。
- Verification: unit（任意アドレスが他者残高を burn 不可）, manual

### DTKN-SEC-003: permit DOMAIN_SEPARATOR の実名追従

- Type: Security
- Statement: `DOMAIN_SEPARATOR` は実 `name()` を追従し、placeholder 名固定による署名不整合（`permit()` の永久 revert）を起こしてはならない。
- Verification: unit（[DTKN-FR-007](#dtkn-fr-007-permiteip-2612) と同）, integration

### DTKN-SEC-004: placeholder stranded の防止

- Type: Security
- Statement: Underlying 未確定中の `mint` を禁止し、`totalSupply()>0` による `setTokenInfo` 恒久不能化（placeholder stranded）を防がなければならない。
- Verification: unit（未確定 mint revert）, invariant=DTKN-INV-008

### DTKN-SEC-005: アップグレード権限の限定

- Type: Security
- Statement: 新実装の承認は Owner（holder = 共通 TimelockController）のみで、運用ロール（vault 等）はアップグレードできてはならない。
- Verification: unit（非 Owner 承認 revert）, manual（storage layout review）

### DTKN-SEC-006: Owner 権限喪失の防止

- Type: Security
- Statement: Owner 移譲は 2-step とし、誤アドレスへの 1-step 移譲で `setCap` / `setTokenInfo` / upgrade 権限を失ってはならない。`renounceOwnership` は常に revert し、Owner 放棄による placeholder 有効化不能・cap 更新不能・upgrade 不能を防がなければならない。
- Verification: unit（2-step 移譲・renounce disabled）

### DTKN-SEC-007: Underlying 誤 bind の防止

- Type: Security
- Statement: `setTokenInfo` は Owner が事前に allowlist した deployed contract のみを Underlying として受け入れ、canonical token の誤指定・EOA 指定・未デプロイアドレス指定を拒否しなければならない。
- Verification: unit（DTKN-FR-010 / DTKN-INV-010）

> **reentrancy**: dToken 自体は価値移転を伴う外部呼び出しを持たない（mint/burn は内部会計、convert は view、permit は署名検証）。CEI/ReentrancyGuard は消費側（[CollateralVault](./CollateralVault.md) / [Zapper](./Zapper.md)）の責務であり、dToken は reentrancy 面を持ち込まない。

---

## 10. ガバナンス・運用・アップグレード要件（GOV）

### DTKN-GOV-001: Owner の holder は共通 TimelockController

- Statement: Owner（`setCap`/`setTokenInfo`/アップグレード承認の権限主体）の **holder は共通 TimelockController のみ**でなければならない（GOV multisig〔マルチシグ〕は Timelock の PROPOSER/EXECUTOR として提案・実行する。owner を GOV multisig へ直接配線しない・単一 EOA 禁止・[DTKN-GOV-004](#dtkn-gov-004-owner-timelock)）。
- Verification: manual（デプロイ構成レビュー）

### DTKN-GOV-002: Owner 移譲（2-step）

- Statement: Owner 移譲は 2-step（`transferOwnership` → `acceptOwnership`）で行う。誤アドレス指定時は `transferOwnership(address(0))` で pending をキャンセルできる。
- Verification: unit, manual

### DTKN-GOV-003: Owner 放棄の扱い

- Statement: Owner 放棄は `setCap`/`setTokenInfo`/アップグレードを恒久不能化し、placeholder Underlying の後付け確定運用と両立しないため、コード上 `RenounceOwnershipDisabled` で無効化する。
- Verification: unit

### DTKN-GOV-004: Owner timelock

- Statement: dToken contract 内に内蔵 timelock は置かず、**Owner を共通 TimelockController にする**（Vault `GOV_ROLE` / Strategy `upgrader` と同一 Timelock を共用。delay値は [Day1 Parameter Manifest](../../../Parameters.md) `PRM-GOV-COMMON-TIMELOCK-DELAY`、holder構成は [Protocol Role Holder Manifest](../../../protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md) を正本とする）。`setCap` / `setTokenInfo` / `setAllowedUnderlying` / UUPS upgrade はすべて同 Timelock の遅延対象となる。**`setCap` は恒久的な露出上限（risk param）であり緊急レバーではない**——急性デペグ等で新規 mint を即時に止める応答は Vault 側の `pauseDeposit`（GUARDIAN・即時、[CollateralVault 要件定義](./CollateralVault.md) VAULT-FR-014）が担う。dToken に緊急即時操作は存在せず、Owner timelock と pause 権限は分離して運用する。設計判断の正本: [protocol/product/policies/Governance-Roles-Timelock.md](../policies/Governance-Roles-Timelock.md)。
- Verification: manual（デプロイ構成レビュー・Owner = Timelock の assert）

### DTKN-GOV-005: Underlying allowlist の deploy レビュー

- Statement: `setAllowedUnderlying` は `setTokenInfo` と同じく one-shot bind に直結する重要操作として扱い、GOV multisig（Timelock の PROPOSER/EXECUTOR）の署名前に chainId・contract address・decimals・token implementation / proxy・blacklist / pause 権限の有無をレビューしなければならない。
- Verification: manual（mainnet deploy checklist）

---

## 11. イベント・監視要件（EVT）

| ID | イベント | 用途（off-chain） |
| --- | --- | --- |
| DTKN-EVT-001 | `TokenInfoSet(name, symbol, underlying, underlyingDecimals)` | Underlying 確定（placeholder→active）の検知。1 度のみ |
| DTKN-EVT-002 | `CapUpdated(oldCap, newCap)` | 担保上限変更の監視 |
| DTKN-EVT-003 | ERC20 `Transfer`（mint: from=0 / burn: to=0） | 供給量・発行償却の追跡 |
| DTKN-EVT-004 | `OwnershipTransferStarted(previousOwner, newOwner)` / OZ `OwnershipTransferred` | Owner 移譲の開始・確定 |
| DTKN-EVT-005 | `AllowedUnderlyingUpdated(underlying, allowed)` | Underlying allowlist の追加・取り消し。`TokenInfoSet` 前の deploy safety 操作 |

- 初期化に専用イベントは設けない（確定は DTKN-EVT-001 で観測）。

---

## 12. 失敗時・異常系挙動（ERR）

**placeholder 期（Underlying 未確定）の挙動**

| 関数 | placeholder 期 | active 期 |
| --- | --- | --- |
| `name()` / `symbol()` | placeholder 値 | 確定値 |
| `decimals()` | 18（DTKN-INV-001） | 18 |
| `convertTo*` | `TokenInfoNotSet` revert | 換算値 |
| `mint` | `TokenInfoNotSet` revert | 実行可（vault のみ） |

**エラーカタログ**

| エラー | 契機 |
| --- | --- |
| `OnlyVault` | vault 以外の mint/burn（DTKN-SEC-001） |
| `ZeroAddress` | `initialize` / `setTokenInfo` / `setAllowedUnderlying` でゼロアドレスを指定 |
| `TokenInfoNotSet` | 未確定での convert/mint（DTKN-INV-008） |
| `CapExceeded` | `totalSupply()+amount > cap` の mint（DTKN-FR-004） |
| `InvalidUnderlyingDecimals` | `setTokenInfo` で `decimals > 18`（DTKN-FR-002） |
| `NotContract` | `setAllowedUnderlying` / `setTokenInfo` で EOA または未デプロイアドレスを指定 |
| `UnderlyingNotAllowed` | `setTokenInfo` で allowlist 未承認の Underlying を指定 |
| `TokenInfoAlreadySet` | `setTokenInfo` 再呼出、または token info 確定後の `setAllowedUnderlying` |
| `EmptyTokenName` / `EmptyTokenSymbol` | `setTokenInfo` で空の name / symbol を指定 |
| `SupplyAlreadyExists` | `totalSupply() > 0` の状態で `setTokenInfo` を呼び出し |
| `UnderlyingMismatch`（Vault 側） | `CollateralVault.setUnderlying` が `dToken.underlying()` と不一致（dToken-first 違反含む） |
| `RenounceOwnershipDisabled` | `renounceOwnership` 呼び出し（DTKN-FR-009 / DTKN-SEC-006） |

---

## 13. 受け入れ基準・検証計画

各要件の合格条件 = 下表の検証手段を満たすこと（テスト名・実行結果は本書に書かない＝手段の種別まで）。

| ID | 要件（要約） | 検証手段 |
| --- | --- | --- |
| DTKN-FR-001 | initialize（placeholder 立ち上げ・vault/owner 固定） | unit |
| DTKN-FR-002 | setTokenInfo（一度きり・倍率確定・各 revert） | unit, invariant=DTKN-INV-003/004 |
| DTKN-FR-003 | 換算（乗算厳密・floor 安全側・境界） | unit, fuzz=DTKN-INV-006 |
| DTKN-FR-004 | mint（vault 限定・cap/未確定ガード） | unit, invariant=DTKN-INV-002/005 |
| DTKN-FR-005 | burn（vault 限定・allowance 非依存） | unit, invariant=DTKN-INV-002 |
| DTKN-FR-006 | setCap（Owner 限定・現 supply 未満可） | unit, invariant=DTKN-INV-005 |
| DTKN-FR-007 | permit（DOMAIN_SEPARATOR が name() 追従） | unit, integration |
| DTKN-FR-008 | アップグレード（Owner 限定・storage 追記のみ） | unit, manual |
| DTKN-FR-009 | Owner 移譲（2-step）と renounce 無効化 | unit, manual |
| DTKN-FR-010 | Underlying allowlist（contract-only・bind 前のみ・イベント） | unit, manual |
| DTKN-INV-001..010 | §8 各不変条件 | unit / invariant / fuzz（§8 記載どおり） |
| DTKN-SEC-001..007 | §9 各セキュリティ要件 | unit, manual |

---

## 14. 未決事項（TBD）

### DTKN-TBD-001

Resolved: `DTKN-FR-008`、`DTKN-GOV-004` に反映済み。

### DTKN-TBD-002

Resolved: `DTKN-FR-009`、`DTKN-GOV-002` に反映済み。

### DTKN-TBD-003

Resolved: `DTKN-FR-009`、`DTKN-GOV-003` に反映済み。

---

## 15. 参考資料

- [Product Overview](../Product-Overview.md) — 全体アーキテクチャ・責務分離・コア無改変方針（§5）
- [CollateralVault 要件定義](./CollateralVault.md) — Underlying 保管 / Mint・Redeem / buffer 会計 / 遅延償還 / 後付け確定
- [Strategy 要件定義](./strategies/Strategy.md) — `IStrategy` / push モデル / 運用先連携
- [Oracle 要件定義](./Oracle.md) — PriceFeedProxy（timelock の比較対象）
- [Parameters.md](../../../Parameters.md) — 担保別 mintCap / buffer / allocator 系の確定値
- [要件定義ドキュメント標準](../../../Requirements-Spec-Standard.md) — 本書が従う標準
