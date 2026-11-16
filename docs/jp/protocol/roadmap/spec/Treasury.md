# 🟢 Treasury 要件定義

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Future Draft |
| Lifecycle | Future |
| Owner | DeltaForesight |
| 対象コントラクト | `contracts/src/Treasury.sol`（新規・🟢 Original・UUPS） |
| 関連ドキュメント | [Protocol-Revenue-Allocation-Policy](../policies/Protocol-Revenue-Allocation-Policy.md)（担保運用益の用途配分）/ [Yield-Sharing-Rollout-Plan](../policies/Yield-Sharing-Rollout-Plan.md)（ρ の凍結決定・再評価 gate）/ [Reward-Distributors](./Reward-Distributors.md)（SP 追加報酬・借入 Referral・SP-deposit Referral）/ [CollateralVault](../../product/spec/CollateralVault.md)（VAULT-FR-007 / VAULT-FR-012 / VAULT-FR-017）/ [Strategy](../../product/spec/strategies/Strategy.md)（STGY-FR-003 / STGY-FR-010） |

> 本書は [要件定義ドキュメント標準](../../../Requirements-Spec-Standard.md)に従う。要件 ID は `TRSY-*`。
> 現行の留保先、照合、cutover 手順は [Treasury Safe Retention Runbook](../../operations/runbooks/Treasury-Safe-Retention-Runbook.md) を正本とし、本書では再掲しない。

---

## 1. 概要・責務

`Treasury.sol` は、CollateralVault から受け取った担保運用益（Underlying）を、[Protocol-Revenue-Allocation-Policy](../policies/Protocol-Revenue-Allocation-Policy.md) の単一 budget table に従って **用途別の固定宛先へ送る revenue router** である。

Treasury 自身は、DEX buyback、SP 預入者の TWAB 集計、Merkle claim、Referral partner / wallet の計算、Foundation 内部会計を行わない。それぞれの用途で必要な処理は、受け取り先コントラクトまたは Foundation operating-asset Safe (`foundationSafe`) 側の責務とする。backstop 補填については、Treasury は登録済み CollateralVault の `backstopDeposit` を呼ぶだけで、`releaseBackstopToBuffer` や補填 waterfall は Vault / incident policy 側の責務とする。

| 用途 | 宛先 | 宛先側の正本 |
| --- | --- | --- |
| `SP_ADDITIONAL_REWARD` | `SPAdditionalRewardDistributor` | [Reward-Distributors.md](./Reward-Distributors.md) |
| `BORROW_REFERRAL` | `BorrowReferralRewardDistributor` | [Reward-Distributors.md](./Reward-Distributors.md) |
| `SP_DEPOSIT_REFERRAL` | `SPDepositReferralRewardDistributor` | [Reward-Distributors.md](./Reward-Distributors.md) |
| `BORROWER_REBATE` | **凍結中**。share 0 / destination unset。`BorrowerRebateDistributor` は未実装の将来候補 | [Yield-Sharing-Rollout-Plan](../policies/Yield-Sharing-Rollout-Plan.md)（D1 不発動・再評価 gate） |
| `BACKSTOP_DEPOSIT` | 登録済み `CollateralVault.backstopDeposit` | [CollateralVault.md](../../product/spec/CollateralVault.md) VAULT-FR-017 |
| Foundation 残余 | `foundationSafe` | Foundation / DF 側の protocol 外会計 |

**Treasury の責務は4つだけ**:

1. 担保運用益を受領し、未処理残高を可視化する。
2. `purposeShareBps[purpose]` に従って `splitYield` し、用途別固定宛先へ送る。
3. 緊急時に、登録済み Vault の `backstopDeposit` へ不足額上限で補填する。
4. 宛先・比率変更を timelock / role / event で統制する。

---

## 2. スコープ・非責務

**本書が規定する**:

- `Treasury.sol` の用途別 routing、固定宛先、比率変更、経路変更 timelock、backstopDeposit 補填、pause、UUPS。
- 報酬トークン（Aave incentives / Merkl 等）の Foundation operating-asset Safe (`foundationSafe`) への単純転送。

**本書が規定しない**:

- 3種の Distributor に共通する buyback / root / claim と方式差分 → [Reward-Distributors](./Reward-Distributors.md)
- Referral の attribution / cap / holding-period → [Referral-Program-Policy](../../operations/policies/Referral-Program-Policy.md)
- 借り手リベートの将来再評価条件。TWAB / owner slice / root / claim は現行仕様に含めず、再開時に再設計する → [Yield-Sharing-Rollout-Plan](../policies/Yield-Sharing-Rollout-Plan.md)
- 担保運用益の用途配分比率そのもの → [Protocol-Revenue-Allocation-Policy](../policies/Protocol-Revenue-Allocation-Policy.md)
- `releaseBackstopToBuffer`、補填後の redeem / claim 再開順序、補填 waterfall。これらは [CollateralVault](../../product/spec/CollateralVault.md) と incident policy / governance decision で扱う。

---

## 3. 用語・会計

| 用語 | 意味 |
| --- | --- |
| Underlying yield | Vault が `transferYieldToTreasury` で Treasury に送る担保運用益 |
| purpose | `SP_ADDITIONAL_REWARD` / `BORROW_REFERRAL` / `SP_DEPOSIT_REFERRAL` / `BORROWER_REBATE` / `BACKSTOP_DEPOSIT` の固定用途。`BORROWER_REBATE` は 2026-07-16 に dormant purpose として追加し、2026-07-17 の D1 不発動決定により share 0 / destination unset で凍結する（[Protocol-Revenue-Allocation-Policy](../policies/Protocol-Revenue-Allocation-Policy.md) §2、[Yield-Sharing-Rollout-Plan](../policies/Yield-Sharing-Rollout-Plan.md)） |
| Foundation 残余 | `10000 - Σ purposeShareBps[purpose]`。split 時に `foundationSafe` へ送る |
| `purposeShareBps[purpose]` | split 時に当該 purpose 宛先へ送る比率。初期値は activation Decision Record と verified manifest で確定する |
| `purposeDestination[purpose]` | `SP_ADDITIONAL_REWARD` / `BORROW_REFERRAL` / `SP_DEPOSIT_REFERRAL` / `BORROWER_REBATE` の固定宛先コントラクト |
| `backstopVault[token]` | `BACKSTOP_DEPOSIT` と emergency backstop の送付先。`CollateralVault.underlying() == token` を満たす登録 Vault |
| `unsplitBalance(token)` | Treasury の token 残高のうち、まだ `splitYield` していない額。受領 hook は持たず、処理時に確定する |

Treasury は用途別の累積送付額を event / view で可視化するが、送付後の資産会計は宛先側の正本に移る。したがって Treasury には `rewardShareBps`、`buybackBudget`、`assetBudget`、`epoch`、`claimed` を置かない。SP / Referral / Borrower rebate の distributor purpose 宛先は共通インターフェース `notifyTreasuryRevenue(address token, bytes32 purpose, uint256 amount)` を実装する。Treasury は宛先へ `amount` だけ一時 allowance を設定して通知し、宛先が通知内で Underlying を pull して実着額を記帳する。`BACKSTOP_DEPOSIT` は通知ではなく、登録 Vault の `backstopDeposit` に Underlying を入金して `BackstopDeposited` event と突合する。

---

## 4. アクター・ロール

| アクター | 操作 | 信頼境界 |
| --- | --- | --- |
| `GOV_ROLE` | `setPurposeShareBps` / destination・backstopVault 変更の propose・confirm / `unpauseRouting` / UUPS 承認 | holder は共通 TimelockController を想定。即時資金流出できない |
| `TREASURER_ROLE` | `splitYield` / `forwardRewardToken` / `pauseRouting` / `emergencyBackstopDeposit` | 運用実行ロール。比率・宛先を引数で変えられない。emergency backstop は登録 Vault・不足額上限のみ |
| `GUARDIAN_ROLE` | destination proposal cancel / destination disable / `pauseRouting` / `emergencyBackstopDeposit` | fail-safe 専用。資金送付先の追加・比率変更はできない。backstop 補填は登録 Vault・不足額上限のみ |
| Purpose destination / backstop Vault | Treasury から用途別資金を受ける | 宛先ごとの仕様で処理する |
| Foundation operating-asset Safe (`foundationSafe`) | Foundation 残余・報酬トークンの受領 | protocol 外 |

---

## 5. インターフェース仕様

| 関数 | 可視性 | 要約 | 要件 |
| --- | --- | --- | --- |
| `initialize(address admin, address foundationSafe, PurposeConfig[] initialPurposes, BackstopConfig[] initialBackstops)` | external initializer | role・Foundation operating-asset Safe・初期 purpose 宛先/比率・backstop Vault を設定 | TRSY-FR-001 |
| `splitYield(address token, uint256 amount)` | external `TREASURER_ROLE` | 未処理 Underlying を purpose 宛先と Foundation operating-asset Safe へ送る | TRSY-FR-002 |
| `forwardRewardToken(address token, uint256 amount)` | external `TREASURER_ROLE` | 非 Underlying 報酬トークンを Foundation operating-asset Safe へ転送 | TRSY-FR-003 |
| `setPurposeShareBps(bytes32 purpose, uint256 bps)` | external `GOV_ROLE` | 用途比率を bounds 内で更新（将来効） | TRSY-FR-004 |
| `proposePurposeDestination(bytes32 purpose, address destination)` / `confirmPurposeDestination(bytes32 purpose)` / `cancelPurposeDestination(bytes32 purpose)` | external | 宛先変更の2段階統制 | TRSY-FR-005 |
| `proposeBackstopVault(address token, address vault)` / `confirmBackstopVault(address token)` / `cancelBackstopVault(address token)` | external | backstop Vault 変更の2段階統制 | TRSY-FR-005 |
| `disablePurposeDestination(bytes32 purpose)` | external `GUARDIAN_ROLE` | 侵害・不具合時に当該 purpose への新規送付を止める | TRSY-FR-005 |
| `pauseRouting()` / `unpauseRouting()` | external | routing 全体の非対称停止 | TRSY-FR-006 |
| `emergencyBackstopDeposit(address vault, uint256 amount)` | external `TREASURER_ROLE` or `GUARDIAN_ROLE` | routing pause 中でも登録 Vault へ不足額上限で補填 | TRSY-FR-007 |
| `unsplitBalance(address token)` / `purposeDestination(bytes32 purpose)` / `purposeShareBps(bytes32 purpose)` / `backstopVault(address token)` / `routedTotal(address token, bytes32 purpose)` | external view | 監視・照合用 view | TRSY-FR-008 |
| `_authorizeUpgrade(address)` | internal | UUPS 承認 | TRSY-FR-009 |

---

## 6. 機能要件

### TRSY-FR-001: initialize

- **Type**: Functional ｜ **Source**: Protocol-Revenue-Allocation-Policy §2 / UUPS 方針
- **シグネチャ**: `initialize(address admin, address foundationSafe, PurposeConfig[] initialPurposes, BackstopConfig[] initialBackstops)`
- **目的**: Treasury を revenue router として一度だけ初期化し、Foundation operating-asset Safe、用途別 share、正の share を持つ初期 destination / backstop Vault を確立する。
- **権限**: initializer（proxy 初期化の一部。ロジックコントラクト自体は初期化不能とする）。
- **事前条件（Checks）**:
  - `admin != address(0)`、`foundationSafe != address(0)`。
  - 多重初期化は不可。
  - `Σ initialPurposeShareBps <= PURPOSE_SHARE_TOTAL_MAX_BPS`。
  - 初期 share が正の distributor purpose（`SP_ADDITIONAL_REWARD` / `BORROW_REFERRAL` / `SP_DEPOSIT_REFERRAL` / `BORROWER_REBATE`）は `destination != address(0)`。
  - 初期 share が正の `BACKSTOP_DEPOSIT` は `backstopVault[token] != address(0)` かつ `CollateralVault(vault).underlying() == token`。
- **動作（Effects）**:
  1. `DEFAULT_ADMIN_ROLE` / `GOV_ROLE` を `admin` に付与する。本番 holder は共通 TimelockController を想定する。
  2. `foundationSafe` を保存する。
  3. `purposeShareBps[purpose]`、`purposeDestination[purpose]`、`backstopVault[token]` を設定する。
  4. 初期 destination / backstop Vault は deploy 手順の一部として設定されるため timelock 対象外。以後の変更は TRSY-FR-005 に従う。
- **revert / 早期 return**: ゼロ admin / foundationSafe、多重初期化、share 上限超過、正 share に対する destination / backstop 欠落、backstop underlying 不一致は revert。
- **発火イベント**: `PurposeShareBpsUpdated`、`PurposeDestinationChanged`、`BackstopVaultChanged` を初期値 evidence として発火する。
- **Verification**: unit（ゼロ・再初期化・share 上限・正 share destination 必須・backstop underlying 一致）。

### TRSY-FR-002: splitYield

- **Type**: Functional / Security ｜ **Source**: 用途別 budget table / 固定宛先原則
- **シグネチャ**: `splitYield(address token, uint256 amount)`
- **目的**: Treasury に滞留した未処理 Underlying を、現在の purpose share に従って固定 destination、backstop Vault、Foundation operating-asset Safe へ分割送付する。
- **権限**: `TREASURER_ROLE`。`routingPaused == false` のときのみ。
- **事前条件（Checks）**:
  - `token` は登録 Vault の Underlying。
  - `amount != 0` かつ `amount <= unsplitBalance(token)`。
  - `Σ purposeShareBps <= PURPOSE_SHARE_TOTAL_MAX_BPS`。
  - 正の share を持つ distributor purpose は destination が set 済み・disabled でない。
  - 正の `BACKSTOP_DEPOSIT` share は `backstopVault[token]` が set 済み・disabled でなく、`CollateralVault(vault).underlying() == token`。
  - share が 0 の purpose は destination / backstop Vault 未設定でも `splitYield` を妨げない。
- **動作（Effects）**:
  1. 各 purpose `p` について `purposeAmount[p] = amount * purposeShareBps[p] / 10000` を算出する。
  2. `SP_ADDITIONAL_REWARD` / `BORROW_REFERRAL` / `SP_DEPOSIT_REFERRAL` / `BORROWER_REBATE` のうち `purposeAmount[p] > 0` のものだけを処理する。Treasury は当該 `purposeDestination[p]` への allowance を一度 0 にしてから `purposeAmount[p]` に設定し、`notifyTreasuryRevenue(token, p, purposeAmount[p])` を呼ぶ。destination は通知内で Treasury から全額を pull し、Treasury は呼出後の allowance が 0 であることを要求する。通知、exact receipt、allowance 残ゼロのいずれかが失敗した場合は `splitYield` 全体を revert する。
  3. `BACKSTOP_DEPOSIT` の `purposeAmount > 0` の場合、`backstopVault[token]` へ approve し、`backstopDeposit(purposeAmount)` を呼ぶ。実着額 `received` は Vault event と Treasury event の双方で突合する。
  4. `foundationAmount = amount - Σ purposeAmount[p]` を `foundationSafe` へ送る。端数 dust は Foundation 側へ寄せる。
  5. token/purpose 別 `routedTotal` を更新する。比率変更は以後の `splitYield` にのみ適用し、過去送付分は再配分しない。
- **revert / 早期 return**: 非 TREASURER、routing pause、未登録 token、amount 0、未処理残超過、正 share destination / backstop 欠落、disabled destination、通知 / exact receipt / allowance 残ゼロの失敗、backstopDeposit revert、Foundation transfer 失敗は revert。
- **発火イベント**: `YieldRouted(token, amount, foundationAmount, purposes[], destinations[], purposeAmounts[])`。backstop 入金がある場合は `BackstopDepositedFromTreasury(token, vault, amount, received, false)`。
- **設計上のポイント**: SP-deposit Referral のような前提未確定 bucket と、D1 不発動で凍結した borrower rebate は share 0 にする。share 0 の unset destination で routing 全体を止めず、正 share だけ fail-closed にする。
- **Verification**: unit（share 0 unset 許容・正 share unset revert・通知 revert 巻戻し・exact pull・allowance 残ゼロ・事前 donation / fee-on-transfer・dust Foundation）, invariant=[TRSY-INV-001](#7-不変条件セキュリティ) / [TRSY-INV-003](#7-不変条件セキュリティ)。

### TRSY-FR-003: forwardRewardToken

- **Type**: Functional ｜ **Source**: Strategy reward token sweep / protocol 外処理方針
- **シグネチャ**: `forwardRewardToken(address token, uint256 amount)`
- **目的**: Aave incentives / Merkl 等の非 Underlying 報酬トークンを Foundation operating-asset Safe へそのまま退避する。
- **権限**: `TREASURER_ROLE`。
- **事前条件（Checks）**:
  - `token != address(0)`、`amount != 0`。
  - `token` は登録 Underlying ではない。
  - `token` は purpose destination の reward asset として escrow / claim 中の保護 asset ではない。
- **動作（Effects）**: `token.safeTransfer(foundationSafe, amount)` を実行し、`RewardTokenForwarded(token, amount)` を発火する。
- **revert / 早期 return**: 非 TREASURER、ゼロ token / amount、Underlying 指定、保護 reward asset 指定、transfer 失敗は revert。
- **設計上のポイント**: 報酬トークンを自動で buyback / backstop / Referral budget に転用しない。Foundation 側で換金後に backstop へ使う場合は別 tx / 別 governance 判断とする。
- **Verification**: unit（保護 token 拒否・固定宛先・transfer event）。

### TRSY-FR-004: purpose share setter

- **Type**: Governance / Functional ｜ **Source**: Protocol-Revenue-Allocation-Policy §2
- **シグネチャ**: `setPurposeShareBps(bytes32 purpose, uint256 bps)`
- **目的**: 担保運用益の用途配分を governance が更新する。
- **権限**: `GOV_ROLE`。
- **事前条件（Checks）**:
  - `purpose` は既知 purpose。
  - 更新後の `Σ purposeShareBps <= PURPOSE_SHARE_TOTAL_MAX_BPS`。
  - `PURPOSE_SHARE_TOTAL_MAX_BPS` は Foundation 残余の最低取り分を構造保証する上限で、activation 前に TRSY-TBD-001 を閉じて確定する。
- **動作（Effects）**: `purposeShareBps[purpose]` を更新し、`PurposeShareBpsUpdated(purpose, oldBps, newBps)` を発火する。setter は one-shot ではなく再設定可能だが、将来の `splitYield` にのみ効く。
- **revert / 早期 return**: 非 GOV、未知 purpose、share 上限超過は revert。
- **設計上のポイント**: SP-deposit Referral 未確定、borrower rebate の D1 不発動、Referral 手作業支払、backstop 優先などの運用判断は share を 0 にすることで表現する。過去 routing は再配分しない。
- **Verification**: unit（bounds・unknown purpose・将来効）。

### TRSY-FR-005: purpose destination 変更

- **Type**: Governance / Security ｜ **Source**: 固定宛先・timelock 変更原則
- **対象**: `proposePurposeDestination` / `confirmPurposeDestination` / `cancelPurposeDestination` / `proposeBackstopVault` / `confirmBackstopVault` / `cancelBackstopVault` / `disablePurposeDestination`
- **目的**: 資金流出先の追加・差替えを timelock と Guardian cancel で統制する。
- **権限**: propose / confirm は `GOV_ROLE`、cancel / disable は `GUARDIAN_ROLE`。
- **事前条件（Checks）**:
  - 新しい destination / backstop Vault はゼロ不可。
  - destination 変更は `propose -> TRSY_TIMELOCK_DELAY -> confirm`。confirm 前は旧 destination が有効。
  - backstop Vault 変更も `propose -> TRSY_TIMELOCK_DELAY -> confirm`。
  - backstop Vault は `CollateralVault(vault).underlying() == token` を満たす。
- **動作（Effects）**:
  1. proposal 作成時に `readyAt = block.timestamp + TRSY_TIMELOCK_DELAY` を保存する。
  2. `readyAt` 経過後、GOV が confirm すると destination / backstop Vault を差し替える。
  3. GUARDIAN は pending proposal を即時 cancel できる。
  4. GUARDIAN は侵害・不具合時に purpose destination を disable できる。disabled purpose は正 share の新規 `splitYield` 送付先にできない。
- **revert / 早期 return**: 非権限、ゼロ destination、delay 未経過 confirm、proposal 不存在、backstop underlying 不一致、disabled destination への正 share split は revert。
- **発火イベント**: `PurposeDestinationChangeProposed` / `PurposeDestinationChanged` / `PurposeDestinationChangeCancelled` / `PurposeDestinationDisabled` / `BackstopVaultChangeProposed` / `BackstopVaultChanged` / `BackstopVaultChangeCancelled`。
- **設計上のポイント**: 既に送付済みの資金処理は宛先側の incident 手順に従う。Treasury は過去送付分を arbitrary pull しない。
- **Verification**: unit（delay・cancel・disable・backstop underlying）, invariant=[TRSY-INV-005](#7-不変条件セキュリティ)。

### TRSY-FR-006: pauseRouting / unpauseRouting

- **Type**: Security / Governance ｜ **Source**: incident response
- **目的**: backing 毀損、宛先不具合、root incident 時に通常 routing を即時停止する。
- **権限**: TREASURER または GUARDIAN は `pauseRouting` できる。再開は `GOV_ROLE` のみ。
- **動作（Effects）**:
  - pause 中は `splitYield` を止める。
  - `forwardRewardToken` は Foundation 退避用途として継続可能。
  - `emergencyBackstopDeposit` は TRSY-FR-007 の条件を満たす場合に限り継続可能。
- **revert / 早期 return**: pause 中の `splitYield`、非 GOV の unpause は revert。
- **発火イベント**: `RoutingPaused(account)` / `RoutingUnpaused(account)`。
- **Verification**: unit（非対称 pause・forward 継続・GOV のみ再開）。

### TRSY-FR-007: emergencyBackstopDeposit

- **Type**: Security / Functional ｜ **Source**: backing repair incident path / CollateralVault VAULT-FR-017
- **シグネチャ**: `emergencyBackstopDeposit(address vault, uint256 amount)`
- **目的**: 通常 routing を止めた状態で、Treasury に残る未処理 Underlying を登録済み Vault の protected backstop reserve へ不足額上限で補填する。
- **権限**: `TREASURER_ROLE` または `GUARDIAN_ROLE`。
- **事前条件（Checks）**:
  - `routingPaused == true`。通常時の backstop 補填は `splitYield` の `BACKSTOP_DEPOSIT` bucket で扱う。
  - `BACKSTOP_DEPOSIT` purpose が disabled ではない。
  - `vault` は登録済み `backstopVault[token]` と一致し、`token == CollateralVault(vault).underlying()`。
  - `amount != 0` かつ `amount <= unsplitBalance(token)`。
  - `amount <= CollateralVault(vault).backstopRequiredForRatio(1e18)`。不足額が 0 の Vault へ緊急補填できない。
- **動作（Effects）**:
  1. Treasury は `token` を `vault` へ必要額だけ approve する。
  2. `CollateralVault(vault).backstopDeposit(amount)` を呼ぶ。
  3. 実着額 `received` を event に記録し、token/purpose 別 `routedTotal[token][BACKSTOP_DEPOSIT]` を更新する。
  4. approve 残余を残さない。
- **revert / 早期 return**: 非 TREASURER/GUARDIAN、routing 未停止、purpose disabled、未登録 vault、underlying 不一致、amount 0、未処理残超過、不足額超過、backstopDeposit revert は revert。
- **発火イベント**: `BackstopDepositedFromTreasury(token, vault, amount, received, true)`。
- **設計上のポイント**: 緊急補填は SP 追加報酬 / Referral / Foundation の既送付・既確定 budget を自動回収しない。Treasury に残っている未処理 Underlying だけを使える。
- **Verification**: unit（pause 必須・不足額上限・登録 Vault・approve 残ゼロ）, invariant=[TRSY-INV-006](#7-不変条件セキュリティ)。

### TRSY-FR-008: view

- **Type**: Functional ｜ **Source**: monitoring / accounting reconciliation
- **目的**: routing、destination、backstop、proposal、累積送付額を監視・突合できるようにする。
- **view 対象**: `unsplitBalance`、purpose share、destination、backstop Vault、disabled 状態、token/purpose 別 `routedTotal`、保留中 proposal、routing pause 状態。
- **Verification**: unit（各状態更新後の view 反映）, integration（Vault / distributor event との突合）。

### TRSY-FR-009: UUPS upgrade

- **Type**: Governance ｜ **Source**: UUPS upgrade 方針
- **目的**: Day-2 以降の routing / backstop / destination 設計を upgrade 可能にしつつ、権限と storage 破壊を制限する。
- **権限**: `_authorizeUpgrade` は `GOV_ROLE` のみ。mainnet では `GOV_ROLE` / `DEFAULT_ADMIN_ROLE` holder を共通 TimelockController のみにする。
- **事前条件（Checks）**: upgrade 実行前に storage layout diff、role holder、routing pause、未処理残高、destination / backstop proposal を確認する。
- **動作（Effects）**: storage は append-only。既存 `purposeShareBps`、destination、backstop Vault、`routedTotal`、未処理残の意味を変更しない。
- **Verification**: unit（非 GOV upgrade revert）, manual（storage layout / governance 手順）。

---

## 7. 不変条件・セキュリティ

| ID | 不変条件 / 要件 | 検証 |
| --- | --- | --- |
| TRSY-INV-001 | Treasury からの資金流出先は `{purposeDestination[p], backstopVault[token], foundationSafe}` のみ。任意 `to` を指定する送金関数を持たない | unit / manual |
| TRSY-INV-002 | `Σ purposeShareBps <= PURPOSE_SHARE_TOTAL_MAX_BPS` | unit |
| TRSY-INV-003 | `splitYield` は destination unset / disabled の purpose を黙って他用途へ流用しない | unit |
| TRSY-INV-004 | Treasury は DEX router、SP、Referral participant へ直接送金・呼び出ししない。Distributor 呼出は固定 destination の `notifyTreasuryRevenue` だけで、allowance は当該 purpose amount に限定し呼出後 0。Vault への直接呼び出しは登録済み `backstopDeposit` のみ | unit / static review |
| TRSY-INV-005 | destination 変更は timelock 経過前に効力を持たない | unit |
| TRSY-INV-006 | `emergencyBackstopDeposit` は routing pause 中、`BACKSTOP_DEPOSIT` 有効時、登録 Vault、underlying 一致、不足額上限内でしか実行できない | unit / invariant |

**TREASURER 鍵侵害の被害境界**: TREASURER は既定比率・固定宛先に従って routing するか、routing を止めることしかできない。緊急 backstop も登録 Vault の不足額上限までであり、攻撃者アドレス、任意 router、任意 referral payout address へ送る経路は存在しない。

**GOV 鍵侵害の被害境界**: destination 差替えは timelock と event 監視を通る。delay 中に GUARDIAN が cancel できる。UUPS upgrade 経由の迂回は GOV holder を TimelockController に限定して遅延統制する。

---

## 8. イベント・監視

| ID | イベント | 用途 |
| --- | --- | --- |
| TRSY-EVT-001 | `YieldRouted(token, amount, foundationAmount, purposes[], destinations[], purposeAmounts[])` | 用途配分実績の照合 |
| TRSY-EVT-002 | `RewardTokenForwarded(token, amount)` | 報酬トークン退避の追跡 |
| TRSY-EVT-003 | `PurposeShareBpsUpdated(purpose, oldBps, newBps)` | budget table 変更監視 |
| TRSY-EVT-004 | `PurposeDestinationChangeProposed/Changed/Cancelled(purpose, destination, readyAt)` | 経路変更監視 |
| TRSY-EVT-005 | `PurposeDestinationDisabled(purpose, destination)` | fail-safe 監視 |
| TRSY-EVT-006 | `RoutingPaused(account)` / `RoutingUnpaused(account)` | incident 監視 |
| TRSY-EVT-007 | `BackstopVaultChangeProposed/Changed/Cancelled(token, vault, readyAt)` | backstop Vault 変更監視 |
| TRSY-EVT-008 | `BackstopDepositedFromTreasury(token, vault, amount, received, emergency)` | 通常 / 緊急 backstop 補填の突合 |

監視指標: token 別 `unsplitBalance`、purpose 別累積送付額、Foundation 残余、destination / backstop proposal、disabled purpose、routing pause 期間、Vault 別 `backingShortfall` / `backstopRequiredForRatio(1e18)`。

---

## 9. 失敗時・異常系

| 事象 | 挙動 |
| --- | --- |
| destination contract 障害 / revert | `splitYield` 全体を revert。資金は Treasury に残り、他用途へ流用しない |
| destination の実着額不一致 / allowance 残存 | `splitYield` 全体を revert。事前 donation を実着額に含めず、fee-on-transfer token や不完全な pull を受け入れない |
| 正 share の purpose destination 未設定 / disabled | `splitYield` revert。GOV が destination を修復するか share を 0 にするまで未処理残として滞留 |
| 正 share の backstop Vault 未設定 / underlying 不一致 | `splitYield` / `emergencyBackstopDeposit` revert。GOV が登録を修復するか `BACKSTOP_DEPOSIT` share を 0 にするまで未処理残として滞留 |
| 比率変更ミス | bounds 違反は revert。bounds 内の誤設定は governance / monitoring で検知し、以後の split から修正 |
| backing 毀損 | `pauseRouting` で C/D/ρ/Foundation への通常支払いを止め、登録 Vault の不足額上限内で `emergencyBackstopDeposit` を実行できる。補填後の release / 再開順序は incident policy / governance decision で扱う |

---

## 10. 受け入れ基準

| ID | 要約 | 検証 |
| --- | --- | --- |
| TRSY-FR-001 | initialize | unit |
| TRSY-FR-002 | purpose routing | unit / invariant |
| TRSY-FR-003 | reward token forwarding | unit |
| TRSY-FR-004 | purpose share setter | unit |
| TRSY-FR-005 | destination timelock / disable | unit |
| TRSY-FR-006 | pause / unpause | unit |
| TRSY-FR-007 | emergency backstop | unit / invariant |
| TRSY-FR-008 | view | unit |
| TRSY-FR-009 | UUPS | unit / manual |
| TRSY-INV-001..006 | 固定宛先・比率・経路統制・緊急 backstop cap | unit / invariant / static review |

---

## 11. 未決事項

| ID | 未決 |
| --- | --- |
| TRSY-TBD-001 | `PURPOSE_SHARE_TOTAL_MAX_BPS`、初期 `purposeShareBps`、`TRSY_TIMELOCK_DELAY` の確定値 |
| TRSY-TBD-002 | Safe 留保資産の移行方法は [Treasury Safe Retention Runbook](../../operations/runbooks/Treasury-Safe-Retention-Runbook.md) の cutover proposal へ移管 |
| TRSY-TBD-003 | 緊急 backstop 補填後の `releaseBackstopToBuffer`、redeem / claim / routing 再開順序（別 incident policy） |
| TRSY-TBD-004 | `BORROWER_REBATE` は D1 不発動により凍結中。再評価 gate を満たす新しい明示決定、`BorrowerRebateDistributor` spec / destination、初期 share がそろうまで share 0 / destination unset |

---

## 12. 参考資料

- [Protocol-Revenue-Allocation-Policy](../policies/Protocol-Revenue-Allocation-Policy.md)
- [Yield-Sharing-Rollout-Plan](../policies/Yield-Sharing-Rollout-Plan.md)
- [Reward-Distributors](./Reward-Distributors.md)
