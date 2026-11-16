# 🟢 CollateralVault 要件定義

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Draft（実装あり・要件の正本化中） |
| Owner | DeltaForesight |
| 対象コントラクト | `contracts/src/CollateralVault.sol`（本体・UUPS）/ `contracts/src/Interfaces/ICollateralVault.sol`（規定インターフェース）/ `IDToken`（mint/burn 呼出先）/ `IStrategy`（push 受入・配分先） |
| 関連ドキュメント | [Product-Overview](../Product-Overview.md)（アーキ・責務分離）/ [dToken](./dToken.md)（mint/burn される担保受益権トークン）/ [Strategy](./strategies/Strategy.md)（運用先・push 元）/ [Oracle](./Oracle.md)（PriceFeed 整合）/ [Zapper](./Zapper.md)（permit・referral 経路）/ [Parameters](../../../Parameters.md)（buffer / allocator / mintCap 等の値） |

> 本書は [要件定義ドキュメント標準](../../../Requirements-Spec-Standard.md)に従う。要件・不変条件・セキュリティ要件には永続 ID（`VAULT-…`）を付し、相互参照は ID で行う。

---

## 1. 目的・スコープ・非責務

CollateralVault は dToken レイヤーの**中核コントラクト**（担保資産ごとに 1 つ・UUPS）。Underlying（WETH / USDC 等）の保管、dToken の mint/burn 呼び出し、liquid buffer 会計、Strategy への配分（`allocate`）と Strategy からの push 受入（`receiveFromStrategy`）、dToken を mint しない backstop 補填 reserve（`backstopDeposit` / `releaseBackstopToBuffer`）、運用益の Treasury 送付、遅延償還（request/claim）、Underlying の後付け確定を担う。Liquity v2 コアからは「ごく普通の 18dec ERC-20 担保（dToken）」の発行体として扱われ、その裏側（実 Underlying・Strategy 運用）を一切露出しない。

- **本書が規定する**: Mint / Redeem（permissionless）/ buffer 会計（`min(est, principal)` 保守評価・先着総取り＋遅延ルール）/ Allocation（固定 weights 配分）/ Strategy → Vault の push 受入（`receiveFromStrategy`）/ backstop 補填 reserve（`backstopDeposit` / `releaseBackstopToBuffer`）/ 遅延償還（WithdrawRequest / claim）/ 収益の Treasury 送付（`transferYieldToTreasury`）/ Strategy 管理（whitelist・登録 CRUD・元本 writeoff）/ Underlying の後付け確定（`setUnderlying` / `whenUnderlyingReady`）/ GOV 設定 setter / View 群 / Pause・Unpause / UUPS アップグレード / ロール設計。
- **本書が規定しない（非責務・他文書）**:
  - dToken トークン自体の仕様（decimals / 換算 / 担保 Cap / `setTokenInfo` / EIP-2612 Permit / mint・burn 権限の内部） → [dToken 要件定義](./dToken.md)
  - Strategy 実装・`IStrategy` / `BaseStrategy`・Strategy 側関数本体（`sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / `emergencyWithdraw`） → [Strategy 要件定義](./strategies/Strategy.md)
  - 担保別 Day-1 パラメータ（`bufferTargetBps` / `bufferFloor` / `allocatorCooldown` / `allocateMaxMove` / `withdrawDelay` / mintCap 等）の確定値 → [Parameters.md](../../../Parameters.md)
  - Zapper の UX Router / permit / referral 記録 / Sky ingress（Flash Loan close は Day-1 ABI 外） → [Zapper 要件定義](./Zapper.md)
  - 🔵 Liquity コアの借入・清算・Redemption・Stability Pool・Surplus 等の挙動 → [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md)
- **責務境界（あえて知らない）**: Vault は Strategy から受領した Underlying を liquid buffer に積むだけで、それが元本回収か収益かを受領時には判別しない（収益の Treasury 送付は別関数が担う）。backstop 入金だけは protected reserve として別会計にする。また外部プロトコルが同期か非同期かを知らず、その差異は各 Strategy 実装の内部に閉じる。

---

## 2. 背景・設計方針

CollateralVault の設計は、**Liquity v2 コアを無改変のまま使う**ための「担保ラッパーの保管・会計層」として一貫している。

- **コアへの露出は dToken のみ**: コアは dToken を 18dec 担保 ERC-20 として扱い、その裏側（実 Underlying・Strategy 運用・buffer・遅延償還）を一切知らない。Vault がこの裏側を吸収する。
- **push モデル**: Strategy → Vault へ戻る資金は Strategy 主導で push する。元本返却・固有緊急回収・汎用 idle 救済など **Strategy valuation cache を減額すべき経路**は `receiveFromStrategy`（[VAULT-FR-005](#vault-fr-005-receivefromstrategystrategy--vault-の-push-受入)）に集約する。一方、`sendProfitToVault` や Underlying reward claim のような **yield-only push** は Strategy が Vault buffer へ直接 `safeTransfer` し、Strategy principal / Vault valuation cache を減らさない。Vault は元本を Strategy から pull せず、Strategy が Vault へ push する。これに伴い approve 方向は反転し、**Strategy が初期化時に Vault を max approve** する（[Strategy 要件定義](./strategies/Strategy.md) の `sendToVault` 等の前提）。同期/非同期の区別は各 Strategy 実装の内部に閉じ、Vault の会計（`StrategyConfig`）はこれを持たない。
- **保守的会計（`min(est, principal)`）**: ソルベンシー評価では live `min(estimatedTotalUnderlying, principal)` を使い、valuation failure 時だけ bounded last-good cache に fallback する。配分・収益送付は cached value や一部 Strategy を 0 とした不完全な全体像に対して送金せず、登録 Strategy の live valuation が 1 件でも読めなければ `managedUnderlying = 0` として outbound 全体を早期 return する。配分・収益送付では protected backstop reserve を除いた `managedUnderlying` を使う（[VAULT-INV-005](#vault-inv-005)・[§7](#7-状態変数会計モデル)）。
- **先着総取り＋遅延償還**: redeem は liquid buffer 十分時は 1 Tx で完結し、不足時は現在の liquid buffer を先着で渡し、残りを `WithdrawRequest` として遅延化する。`pendingWithdrawals` で claim 用資金を Strategy への流出から守る（[VAULT-FR-002](#vault-fr-002-redeemdtoken--underlying)・[VAULT-FR-006](#vault-fr-006-claimwithdrawrequest-の遅延償還受領)）。
- **buffer / backstop の責務分離**: `bufferBalance()` は redeem / claim / allocate / Treasury 送付に使える流動性のみを表す。`backstopDeposit()` は同じ Vault 内の Underlying を protected reserve として記帳し、`totalUnderlying()` / `backingRatio()` には含めるが、GOV が `releaseBackstopToBuffer()` で明示的に解放するまで redeem / claim には使わせない。これにより Strategy 毀損時の補填原資が通常 redeem の先着順で抜かれることを防ぐ（[VAULT-FR-017](#vault-fr-017-backstopdepositdtoken-を-mint-しない補填入金)）。
- **収益化の 2 段分離**: 第 1 段＝各 Strategy の Underlying 建て realized 収益を buffer へ引き上げる `Strategy.sendProfitToVault`（[Strategy 要件定義](./strategies/Strategy.md)）、第 2 段＝buffer 余剰を Treasury へ送る `transferYieldToTreasury`（[VAULT-FR-007](#vault-fr-007-transferyieldtotreasury収益の-treasury-送付)）。Strategy 内に滞留する収益は buffer 上限のため第 2 段だけでは届かないため、ALLOCATOR がまず第 1 段で引き上げる。Aave incentives / Merkl 等の非 Underlying・非 position reward token はこの 2 段会計には入れず、Strategy 共通 `sweepRewardToken` で Treasury へ送る。これにより 1 件の Strategy 障害が他へ波及しない。
- **遅延初期化（placeholder）方針**: Vault は `underlying == address(0)` の placeholder としてデプロイし、後から 1 度だけ `setUnderlying` で確定できる。Underlying の確定が「Vault 側（`setUnderlying`）」と「dToken 側（`setTokenInfo`）」の 2 つの独立した一度きり setter に分かれるため、両者の整合を `whenUnderlyingReady` で**利用時点に強制**し、別資産・別 decimals のサイレント誤評価を防ぐ（[VAULT-FR-011](#vault-fr-011-setunderlying後付け確定一度限り)・[VAULT-SEC-002](#vault-sec-002)）。
- **権限の最小化と非対称 pause**: 資金移動権限を ALLOCATOR_ROLE の 4 関数に限定し、宛先を事前登録 Strategy / Vault / 固定 Treasury に縛る。pause（4 系統）と可逆な緊急無害化（`emergencyDisableStrategy` / `removeStrategy` / `removeFromWhitelist`）は迅速性のため GUARDIAN（即時）、unpause を含む復旧・リスク増方向は GOV（holder = 共通 TimelockController）のみと非対称にし、ガーディアン鍵が侵害されても「可逆な停止・無害化」しかできないようにする。backing を下方修正できる markdown 経路（`writeoffStrategyPrincipal` と async Strategy の pending valuation bps 変更）は独立の WRITEOFF_ROLE（高定足数 GOV multisig・即時）に分離する（[§10](#10-ガバナンス運用アップグレード要件gov)）。
- **backing 毀損時の挙動**: backing < 1（`A < L_effective`）時の確定方針は[Architecture Decision Records](../architecture/Architecture-Decision-Records.md#adr-006)。本 Vault の該当機構は [VAULT-FR-014](#vault-fr-014-pause--unpause緊急停止)（止血）/ [VAULT-FR-017](#vault-fr-017-backstopdepositdtoken-を-mint-しない補填入金)（backstop 補填）/ `VAULT-FR-009`（確定損失の計上）/ [§12](#12-失敗時異常系挙動err)（恒久損失確定時の pro-rata 留保）。

> コア無改変の全体方針・dToken がコアの担保である背景は [Product-Overview](../Product-Overview.md) §4 / §5 を正本とする。

---

## 3. 用語・外部依存・前提

**用語**

| 用語 | 意味 |
| --- | --- |
| Underlying | Vault が保管する実担保資産（WETH / USDC 等）。dToken がラップする原資産 |
| dToken | この Vault が mint/burn する担保受益権トークン（[dToken 要件定義](./dToken.md)） |
| buffer | Vault が現に手元に保有し、redeem / claim / allocate / Treasury 送付に使える liquid Underlying 残高（`underlying.balanceOf(vault) - backstop reserve`） |
| backstop reserve | `backstopDeposit` で補填目的に入金された protected Underlying。`totalUnderlying()` には含むが、`releaseBackstopToBuffer` まで `bufferBalance()` から除外する |
| Strategy | Underlying を外部プロトコルで運用する運用先（[Strategy 要件定義](./strategies/Strategy.md)） |
| `principal` | 各 Strategy が自己管理する投下元本。ソルベンシー評価の保守側に使う |
| `estimatedTotalUnderlying` | Strategy が見積もる回収可能 Underlying 総量（収益込み・損失反映後） |
| WithdrawRequest | buffer 不足 redeem で発行される遅延償還の請求権 |
| `pendingWithdrawals` | 未 claim の WithdrawRequest 合計（claim 用資金の保護に使用） |
| GOV_MULTISIG | Vault の `GOV_ROLE` / `DEFAULT_ADMIN_ROLE` 主体（ガバナンスのマルチシグ） |
| ALLOCATOR | `ALLOCATOR_ROLE` 主体。mainnet の physical holder と実行形態は role assignment policy で管理 |
| GUARDIAN | `GUARDIAN_ROLE` 主体（旧 PAUSE_GUARDIAN_ROLE を改称・拡張）。緊急停止（pause 4 系統）と可逆な無害化のみ可（解除不可） |
| WRITEOFF | `WRITEOFF_ROLE` 主体（高定足数 GOV multisig が直接保持・即時）。`writeoffStrategyPrincipal` と async Strategy の pending valuation bps 変更のみ可 |
| placeholder 期 / active 期 | `setUnderlying` 前（Underlying 未確定）/ 後（確定）の状態 |
| Treasury | 運用益の送付先アドレス（GOV が `setTreasury` で更新） |

**外部依存（信頼する外部）**

- 対応 dToken（[dToken 要件定義](./dToken.md)） — `mint` / `burn` / `convertToDToken` / `convertToUnderlying` / `permit` / `underlying()` を呼ぶ。Vault は dToken の唯一の mint/burn 主体（[DTKN-SEC-001](./dToken.md)）。
- 登録済み Strategy（[Strategy 要件定義](./strategies/Strategy.md)） — `deposit` で配分、元本返却系は `receiveFromStrategy` で push 受入、yield-only push は Strategy から Vault buffer への直接 transfer、`estimatedTotalUnderlying()` / `principal()` を view 評価に使用。Strategy は初期化時に Vault を max approve する。
- Underlying ERC-20 — `safeTransfer` / `safeTransferFrom` / `balanceOf`。`SafeERC20` 経由で扱う。受入経路は残高差分で実着額を計上し、fee-on-transfer / rebasing 等で過大 mint・過大元本返却にならないようにする。redeem の即時送出も receiver の残高差分を `underlyingReceived` とし、nominal transfer 額を受取下限へ流さない。負の rebase 等で送出後残高が送出前を下回る場合は checked subtraction により tx 全体を fail-closed で revert する。blacklist revert は受領者側の個別 tx に閉じ、Vault は batch payout を持たない。
- OpenZeppelin Contracts (upgradeable) — `AccessControl`（5 ロール）/ `ReentrancyGuard`（`nonReentrant`）/ `Pausable` 相当の独自フラグ / UUPS。

**前提**

- Liquity コアは担保を 18dec ERC-20（= dToken）前提で扱う。
- `vault.underlying() ≡ dToken.underlying()` が active 期に常に成立する（[VAULT-SEC-002](#vault-sec-002) でコード強制）。dToken の `setTokenInfo`（[DTKN-FR-002](./dToken.md)）がアドレスと換算倍率を同一引数から一括かつ一度きりで確定するため、アドレス一致は decimals・換算倍率の一致を含意する（[VAULT-FR-011](#vault-fr-011-setunderlying後付け確定一度限り)）。
- 各 Strategy の投下元本は Strategy 側が `principal` として自己管理し、Vault は保有しない（[§7](#7-状態変数会計モデル)）。

---

## 4. アクター・ロール・信頼境界

| アクター | 操作 | 信頼境界 |
| --- | --- | --- |
| **GOV_MULTISIG**（`DEFAULT_ADMIN_ROLE` / `GOV_ROLE`。**holder = 共通 TimelockController のみ**） | Strategy 管理のリスク増方向（addToWhitelist / addStrategy / updateStrategy〔増額・再有効化〕）/ GOV 設定 setter（setBufferConfig / setAllocatorConfig / setWithdrawDelay / setTreasury / setStrategyValuationMaxAge）/ `releaseBackstopToBuffer`（protected backstop reserve の liquid buffer への明示解放、[VAULT-FR-017](#vault-fr-017-backstopdepositdtoken-を-mint-しない補填入金)）/ `setUnderlying` / `invalidateStrategyValuationCache` / unpause（4 系統）/ UUPS アップグレード承認 / `grantRole`・`revokeRole`（`DEFAULT_ADMIN_ROLE`） | 資金・パラメータ・コントラクトの重要変更を一手に握る最強権限。**holder を共通 TimelockController のみ**とし、公示遅延を全 GOV 操作に掛ける（GOV multisig は Timelock の PROPOSER/EXECUTOR として提案・実行し、Vault の GOV_ROLE / DEFAULT_ADMIN を直接持たない。[VAULT-GOV-004](#vault-gov-004-timelock-と緊急-pause-の分離)）。通常運用では資金移動に関与しない |
| **ALLOCATOR**（`ALLOCATOR_ROLE`） | `allocate` / `Strategy.sendToVault` / `Strategy.sendProfitToVault` / `transferYieldToTreasury` の **4 関数のみ** | 宛先・比率を引数で受け取らず事前設定に従う。鍵侵害時の被害は「登録 Strategy への送金」「Strategy→buffer の元本回収または yield-only push」「buffer 余剰の固定 Treasury 送付」に限定し、`pauseAllocation` で Vault からの outbound（`allocate` / `transferYieldToTreasury`）を即時停止できる（[VAULT-SEC-005](#vault-sec-005)） |
| **GUARDIAN**（`GUARDIAN_ROLE`。旧 PAUSE_GUARDIAN_ROLE を改称・拡張） | `pauseDeposit` / `pauseRedeem` / `pauseClaim` / `pauseAllocation`（停止のみ）/ `emergencyDisableStrategy` / `removeStrategy`（`principal == 0` かつ live `estimatedTotalUnderlying == 0` 要）/ `removeFromWhitelist` | Guardian multisig（即時マルチシグ）。可逆な fail-safe（停止・無害化）のみ許可し、backing 評価を下げる markdown 能力を持たない。解除（unpause）・再有効化・増額は不可（GOV=Timelock のみ）。非対称設計 |
| **WRITEOFF**（`WRITEOFF_ROLE`） | `writeoffStrategyPrincipal` / async Strategy の `setPendingWithdrawalValuationBps` | **高定足数 GOV multisig が直接保持（Timelock を経由しない＝即時）**。writeoff と pending valuation bps 変更は、外部プロトコルの実損または未 claim async request の疑義を backing へ下方反映する price-moving 経路で、遅延させると過大評価のまま新規借入が進み bad debt が積み増すため即時とする。async pending valuation の下方変更は `pausedAllocation == true` の incident freeze 後のみ可能で、復元・上方変更は pause 不要。不正 markdown → 不当清算への耐性は、①高定足数 ②下方変更前の allocation freeze ③検知時の `pauseRedeem`（GUARDIAN・即時）による換金出口封鎖 ④これらの操作自体は資金を送らないこと、の 4 層で担保する |
| **dToken Owner（GOV_MULTISIG）** | `dToken.setTokenInfo` / `dToken.setCap` / dToken アップグレード承認 | dToken 側の権限（[dToken 要件定義](./dToken.md)）。本 Vault の `setUnderlying` と活性化順序で連携 |
| **登録済み Strategy** | `receiveFromStrategy`（push 受入の唯一の呼出元集合） | ロールではなく `strategies[]` 登録で判定。`enabled` か無効化済みでも `strategies[]` に残存する間は受入可 |
| **任意（permissionless）** | `deposit` / `redeem` / `redeemWithPermit` / `claim`（request owner 固定送金）/ `backstopDeposit` / View 群 | 信頼不要。対応する停止フラグ（`pausedDeposit` / `pausedRedeem` / `pausedClaim`）が false かつ `whenUnderlyingReady` を満たすときのみ Mint/Redeem/claim 可。claim caller は request owner への送金をredirectできない。backstop 入金は補填 reserve を増やすだけで dToken を mint しない |

- **初期ロール集中と分離**: `initialize` は `_admin`（GOV）に `DEFAULT_ADMIN_ROLE` / `GOV_ROLE` / `ALLOCATOR_ROLE` / `GUARDIAN_ROLE` / `WRITEOFF_ROLE` の **5 ロールを一括付与**する（コード実体: `initialize` が `_admin` に 5 ロールすべてを grant）。本番では `DEFAULT_ADMIN_ROLE` / `GOV_ROLE` を共通 TimelockController、`ALLOCATOR_ROLE` を `DF_ALLOCATOR`、`GUARDIAN_ROLE` を Guardian multisig、`WRITEOFF_ROLE` を高定足数 GOV multisig へ分離・移譲することを前提とし、デプロイ後のロール再配置（deployer の全ロール revoke を含む）を活性化手順に含める（[VAULT-FR-010](#vault-fr-010-initializeプレースホルダー化proxy-初期化)・[VAULT-GOV-001](#vault-gov-001)・[VAULT-GOV-004](#vault-gov-004-timelock-と緊急-pause-の分離)）。
- **権限分離**: ALLOCATOR も `setTreasury` / Strategy 登録 / アップグレードはできず、GOV も通常運用では資金移動に関与しない（緊急時の writeoff は WRITEOFF_ROLE、Strategy の即時無害化・登録解除・whitelist 除去は GUARDIAN_ROLE が担う）。

---

## 5. インターフェース仕様

規定インターフェース `ICollateralVault`。挙動は §6 機能要件、可視性のみ以下に要約（非規範）。

| 関数 | 可視性 | 要約 | 規定要件 |
| --- | --- | --- | --- |
| `deposit(uint256) → uint256` | external (permissionless, whenUnderlyingReady) | Underlying → dToken | VAULT-FR-001 |
| `redeem(uint256, address) → (uint256, uint256)` | external (permissionless, whenUnderlyingReady) | dToken → Underlying（即時／遅延） | VAULT-FR-002 |
| `redeemWithPermit(uint256, uint256, uint8, bytes32, bytes32, address) → (uint256, uint256)` | external (permissionless, whenUnderlyingReady) | permit 経由 redeem | VAULT-FR-003 |
| `allocate()` | external (ALLOCATOR_ROLE) | buffer 余剰を Strategy へ配分 | VAULT-FR-004 |
| `receiveFromStrategy(uint256) → uint256` | external (登録 Strategy のみ) | Strategy → Vault の元本返却系 push 受入 | VAULT-FR-005 |
| `backstopDeposit(uint256) → uint256` | external (permissionless, whenUnderlyingReady) | dToken を mint しない補填 reserve 入金 | VAULT-FR-017 |
| `releaseBackstopToBuffer(uint256) → uint256` | external (GOV_ROLE, whenUnderlyingReady) | protected reserve を liquid buffer へ明示解放 | VAULT-FR-017 |
| `claim(uint256)` | external (permissionless trigger、送金先は request owner 固定) | 遅延償還の受領 | VAULT-FR-006 |
| `transferYieldToTreasury() → uint256` | external (ALLOCATOR_ROLE, `pausedAllocation == false`) | buffer 余剰を Treasury へ送付 | VAULT-FR-007 |
| `addToWhitelist(address)` | external (GOV_ROLE) | Strategy ホワイトリスト追加 | VAULT-FR-008 |
| `removeFromWhitelist(address)` | external (GUARDIAN_ROLE) | Strategy ホワイトリスト除去（fail-safe・即時） | VAULT-FR-008 |
| `addStrategy(IStrategy, uint256, uint256)` | external (GOV_ROLE) | Strategy 登録 | VAULT-FR-008 |
| `updateStrategy(IStrategy, uint256, uint256, bool)` | external (GOV_ROLE) | weights / cap / enabled 更新（増額・再有効化を含むため遅延） | VAULT-FR-009 |
| `emergencyDisableStrategy(IStrategy)` | external (GUARDIAN_ROLE) | 登録 Strategy の即時無効化（`enabled=false`・`weight=0`） | VAULT-FR-019 |
| `removeStrategy(IStrategy)` | external (GUARDIAN_ROLE) | Strategy 登録解除（`principal == 0` かつ live `estimatedTotalUnderlying == 0` 要・fail-safe） | VAULT-FR-008 |
| `writeoffStrategyPrincipal(IStrategy, uint256, uint256)` | external (WRITEOFF_ROLE) | 実行後 backing ratio guard 付きの元本毀損確定（高定足数・即時） | VAULT-FR-009 |
| `forceDeallocateMorphoV2(IStrategy, address, bytes, uint256, uint256, uint256)` | external (WRITEOFF_ROLE) | atomic incident pause と事後 backing guard 付き Morpho V2 penalty 実現 | VAULT-FR-009 |
| `refreshStrategyValuation(IStrategy) → bool` | external (permissionless) | Strategy 保守評価 cache の明示更新 | VAULT-FR-013 |
| `invalidateStrategyValuationCache(IStrategy)` | external (GOV_ROLE) | Strategy 保守評価 cache の明示破棄 | VAULT-FR-013 |
| `initialize(IERC20, IDToken, address, address)` | external (initializer) | proxy 初期化（placeholder 化） | VAULT-FR-010 |
| `setUnderlying(IERC20)` | external (GOV_ROLE) | Underlying の後付け確定（一度限り） | VAULT-FR-011 |
| `setBufferConfig(uint256, uint256)` | external (GOV_ROLE) | buffer 方針更新 | VAULT-FR-012 |
| `setAllocatorConfig(uint256, uint256)` | external (GOV_ROLE) | allocator ガードレール更新 | VAULT-FR-012 |
| `setStrategyValuationMaxAge(uint256)` | external (GOV_ROLE) | Strategy valuation cache の有効期間更新（0 で fallback 無効） | VAULT-FR-012 |
| `setWithdrawDelay(uint256)` | external (GOV_ROLE) | 遅延償還待機期間更新 | VAULT-FR-012 |
| `setTreasury(address)` | external (GOV_ROLE) | 収益送付先更新 | VAULT-FR-012 |
| `bufferBalance() → uint256` | external view | liquid buffer 残高（backstop reserve 除外・placeholder-safe） | VAULT-FR-013 |
| `backstopBalance() → uint256` | external view | protected backstop reserve 残高（placeholder-safe） | VAULT-FR-013 |
| `totalUnderlying() → uint256` | external view | Vault 実保有 Underlying（buffer + backstop reserve）+ Σ Strategy 保守評価（live `min(est, principal)`、valuation failure 時は fresh cache、stale/missing は 0） | VAULT-FR-013 |
| `pausedAllocation() → bool` | external view | allocation / treasury sweep の停止状態。async pending valuation の下方変更ガードにも使う | VAULT-FR-014 |
| `strategyValuationMaxAge() → uint256` | external view | valuation cache の TTL | VAULT-FR-013 |
| `strategyValuationCaches(IStrategy) → (uint256,uint256,bool)` | external view | Strategy 別 last-good 保守評価 cache | VAULT-FR-013 |
| `getStrategiesCount() → uint256` | external view | 登録 Strategy 数 | VAULT-FR-013 |
| `getStrategyAt(uint256) → (IStrategy, StrategyConfig)` | external view | index 番目の Strategy と config | VAULT-FR-013 |
| `getAllStrategies() → (IStrategy[], StrategyConfig[], uint256[])` | external view | 全 Strategy・config・残高 | VAULT-FR-013 |
| `getStrategyStatuses() → StrategyStatus[]` | external view | Strategy 別の alloc / principal / 保守評価 / 推定損益 / cap 余力 | VAULT-FR-013 |
| `backingRatio() → uint256` | external view | dToken 裏付け率 `min(1e18, A / L_effective)`（Oracle が乗算・下方専用） | VAULT-FR-016 |
| `backingRatioForPricing() → (uint256, bool)` | external view | 同じ比率と valuation availability（取得不能を実測 0 と区別） | VAULT-FR-016 |
| `actualLiabilities() → uint256` | external view | `L_effective = dToken 請求権 + pendingWithdrawals` | VAULT-FR-018 |
| `backingShortfall() → uint256` | external view | 100% backing までの不足額 `max(L_effective - A, 0)` | VAULT-FR-018 |
| `backstopRequiredForRatio(uint256) → uint256` | external view | 目標 backing 比率までの補填必要額（切り上げ） | VAULT-FR-018 |
| `pauseDeposit()` / `pauseRedeem()` / `pauseClaim()` / `pauseAllocation()` | external (GUARDIAN_ROLE) | 緊急停止（独立 4 フラグ） | VAULT-FR-014 |
| `unpauseDeposit()` / `unpauseRedeem()` / `unpauseClaim()` / `unpauseAllocation()` | external (GOV_ROLE) | 再開 | VAULT-FR-014 |
| `_authorizeUpgrade(address)` | internal (GOV_ROLE) | UUPS 承認 | VAULT-FR-015 |

---

## 6. 機能要件（FR）

### VAULT-FR-001: deposit（Underlying → dToken）

- **Type**: Functional ｜ **Source**: Product-Overview「dToken Layer」/ ユーザー Mint フロー
- **シグネチャ**: `deposit(uint256 _underlyingAmount) returns (uint256 dTokenAmount)`
- **目的**: Underlying を Vault に預け入れ、対応する dToken を 1:1 請求権として `msg.sender` に発行する。目的は Liquity コアの担保として使える 18dec の dToken を入手すること。
- **権限**: permissionless（ロール不要、`pausedDeposit == false` かつ `whenUnderlyingReady` のときのみ実行可）。
- **事前条件（Checks）**:
  - `pausedDeposit == false`（停止中は revert）
  - `whenUnderlyingReady`: `vault.underlying() != address(0)` かつ `dToken.underlying() == vault.underlying()`（[VAULT-FR-011](#vault-fr-011-setunderlying後付け確定一度限り)）
  - `_underlyingAmount != 0`
- **動作（Effects）**（CEI 順）:
  1. Pause チェック（不成立で revert）
  2. Underlying ready チェック（不成立で revert）
  3. 入力検証（`_underlyingAmount == 0` で revert）
  4. **Underlying 受領** — 受領前の Vault 残高を記録し、`msg.sender` から `safeTransferFrom` で `_underlyingAmount` を Vault に取り込む
  5. **dToken 量を算出** — 受領後残高との差分を `received` として確定し、`dTokenAmount = dToken.convertToDToken(received)` で 18dec に換算（[DTKN-FR-003](./dToken.md)）
  6. **dToken 発行** — `dToken.mint(msg.sender, dTokenAmount)` で `msg.sender` に mint（[DTKN-FR-004](./dToken.md)）
- **revert / 早期 return**: `pausedDeposit` → `Paused`；Vault Underlying 未設定 → `UnderlyingNotSet`；Vault/dToken 不一致（dToken 未初期化を含む）→ `UnderlyingMismatch`；`_underlyingAmount == 0` または実着額 `received == 0` → `ZeroAmount`；`safeTransferFrom` 失敗（残高・許可不足）→ 上流 revert；dToken 側 cap 超過 → `CapExceeded`（[DTKN-FR-004](./dToken.md)）。
- **発火イベント**: `Deposited(user, underlyingAmount, dTokenAmount)`（`user = msg.sender`、`underlyingAmount` は declared ではなく実着額 `received`、[VAULT-EVT-001](#11-イベント監視要件evt)）。
- **設計上のポイント**:
  - **mint 先は常に `msg.sender`**（`receiver` 引数を持たない）。referral を記録したい場合は Zapper 経由（[Zapper 要件定義](./Zapper.md)）。Zapper が `msg.sender` となるため dToken は Zapper に mint され、そのまま openTrove に流す。
  - **実着額 mint**: `receiveFromStrategy` / `backstopDeposit` と同様に残高差分で `received` を決め、fee-on-transfer / rebasing 等で実着額が declared を下回っても過大 mint しない。
  - **`nonReentrant`**: dToken の mint は外部コントラクトへの呼び出しを伴うため ReentrancyGuard で保護。
  - **Cap チェックの所在**: cap 上限は dToken 側で検証されるため Vault 側で重複ガードを置かない（[DTKN-FR-004](./dToken.md)）。
- **Verification**: unit（pause/ready/zero/各 revert・実着額換算量）, integration（approve→deposit→mint）。

### VAULT-FR-002: redeem（dToken → Underlying）

- **Type**: Functional ｜ **Source**: Product-Overview「dToken Layer」/ 償還フロー
- **シグネチャ**: `redeem(uint256 _dTokenAmount, address _receiver) returns (uint256 underlyingReceived, uint256 requestId)`
- **目的**: dToken を burn して Underlying を取り戻す。buffer 十分時は 1 Tx で完結し、不足時は遅延償還（[VAULT-FR-006](#vault-fr-006-claimwithdrawrequest-の遅延償還受領)）に接続する。目的は dToken 保有者が元本請求権を Underlying として現物受領すること。
- **権限**: permissionless（`pausedRedeem == false` かつ `whenUnderlyingReady`）。
- **事前条件（Checks）**: pause 非該当；`whenUnderlyingReady`；`_dTokenAmount != 0`；`_receiver != address(0)`。
- **動作（Effects）**（**Checks-Effects-Interactions 順序を厳守**）:
  1. Pause チェック（`Paused`）
  2. Underlying ready チェック（`UnderlyingNotSet` / `UnderlyingMismatch`）
  3. 入力検証（`_dTokenAmount == 0` → `ZeroAmount`）
  4. 受領者検証（`_receiver == address(0)` → `ZeroAddress`）
  5. **Checks: 必要 Underlying を exact 算出** — `underlyingNeeded = dToken.convertToUnderlying(_dTokenAmount)` を算出し、`underlyingNeeded != 0` かつ `dToken.convertToDToken(underlyingNeeded) == _dTokenAmount` を要求する。倍率の整数倍でない dToken 端数は `InvalidDTokenAmount` で revert し、burn しない。続けて `bufferBal = bufferBalance()` を burn 等の状態変更前に確定する
  6. **Effects: dToken を burn** — `dToken.burn(msg.sender, _dTokenAmount)`（`msg.sender` から焼却。残高不足は dToken 側で revert、[DTKN-FR-005](./dToken.md)）
  7. **Interactions: buffer 十分時の即時パス** — `bufferBal >= underlyingNeeded` なら nominal `underlyingNeeded` を `_receiver` に `safeTransfer` し、送出前後の receiver `balanceOf` 差分を `underlyingReceived` とする。`requestId = 0`
  8. **Interactions: buffer 不足時の混在パス** — 「先着総取り＋遅延ルール」（下記）に従う
- **先着総取り＋遅延ルール（buffer 不足時のみ）**:
  - **即時部分**: Vault が現に持つ nominal buffer 残高 `bufferBal` を `_receiver` に全額 `safeTransfer`。`bufferBal == 0` のときは送金スキップ（ガス節約）。戻り値と `Redeemed.underlyingPaidNow` は receiver の実残高増分とする。結果として最初に redeem を呼んだユーザーが nominal buffer を**先着総取り**し、後続ユーザーは即時支払い 0 ＋全額 WithdrawRequest になる。transfer fee は queue 債務へ付け替えず、`remaining = underlyingNeeded - nominalSent` を維持する。
  - **遅延部分**: 不足分 `remaining = underlyingNeeded - bufferBal` を `WithdrawRequest{ owner: _receiver, underlyingAmount: remaining, claimableAt: block.timestamp + withdrawDelay, claimed: false }` として登録し、`pendingWithdrawals += remaining`（claim 用資金が `allocate` で流出するのを防ぐ、[VAULT-FR-004](#vault-fr-004-allocatebuffer-余剰を-strategy-へ配分) / [VAULT-FR-006](#vault-fr-006-claimwithdrawrequest-の遅延償還受領)）。queue は常に Underlying base unit で記録し、dToken 端数は request 化しない。
- **revert / 早期 return**: `_dTokenAmount == 0` → `ZeroAmount`；`_receiver == address(0)` → `ZeroAddress`；倍率の整数倍でない dToken amount / `underlyingNeeded == 0` → `InvalidDTokenAmount`；`pausedRedeem` → `Paused`；Underlying 未設定 → `UnderlyingNotSet`；不一致 → `UnderlyingMismatch`；`dToken.burn` 残高不足 → ERC20 revert；`safeTransfer` 失敗 → 上流 revert。
- **発火イベント**: `Redeemed(user, receiver, dTokenAmount, underlyingPaidNow, requestId)`（`requestId == 0` は即時完了）/ buffer 不足時のみ追加で `WithdrawRequested(user, receiver, requestId, amount, claimableAt)`（[VAULT-EVT-002](#11-イベント監視要件evt) / [VAULT-EVT-003](#11-イベント監視要件evt)）。
- **設計上のポイント**:
  - **`_receiver` 引数の設計意図**: 呼び出し元（`msg.sender`）と最終受領者（`_receiver`）を分離する。buffer 十分時は `_receiver` に即時送金、不足時は `WithdrawRequest.owner = _receiver` として固定送金先を記録する。`claim()` は誰でも trigger できるが送金先を変更できないため、contract receiver は claim integration を持たなくても keeper 等の呼出しで受領できる（[VAULT-FR-006](#vault-fr-006-claimwithdrawrequest-の遅延償還受領)）。`_receiver = address(0)` は有効な受領先にならないため、burn / request 作成前に `ZeroAddress` で拒否する。
  - **CEI 順序**: 必要量算出 → burn → transfer の順を守り、再入時の状態不整合を防ぐ。
  - **decimal / dust 方針**: dToken は常に 18dec だが、USDC(6) なら最小 redeem 単位は `1e12` dToken、WBTC(8) なら `1e10` dToken。これ未満、または倍率の整数倍でない `_dTokenAmount` は 0 Underlying へ floor されるため、ユーザー価値の silent burn を避けて `InvalidDTokenAmount` で拒否する。
  - **`nonReentrant`**: `dToken.burn`・`safeTransfer` はいずれも外部呼び出しのため保護。
  - **部分 redeem は明示的に分割しない**: `_dTokenAmount` を必ず全量 burn し、即時／遅延の按分は戻り値（`underlyingReceived` と `requestId`）で表現する。
  - 例（標準 ERC-20）: `bufferBal = 100`、`underlyingNeeded = 300` → 即時 100 を `_receiver` 送金、200 を `WithdrawRequest` 登録、`underlyingReceived = 100`、`requestId = N`、`pendingWithdrawals += 200`。fee-on-transfer では nominalSent 100 と queue 200 は同じだが、`underlyingReceived` は receiver 実増分となる。
- **Verification**: unit（即時／不足分岐・先着総取り・receiver 残高差分・fee-on-transfer・各 revert）, invariant=[VAULT-INV-002](#vault-inv-002) / [VAULT-INV-003](#vault-inv-003), integration（burn→request Effects→transfer 順）。

### VAULT-FR-003: redeemWithPermit（permit 経由の redeem）

- **Type**: Functional ｜ **Source**: [Zapper](./Zapper.md) permit 経路 / 代行コントラクトの Tx 削減
- **シグネチャ**: `redeemWithPermit(uint256 _dTokenAmount, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s, address _receiver) returns (uint256 underlyingReceived, uint256 requestId)`
- **目的**: EIP-2612 Permit を使い、事前 approve なしで redeem を 1 Tx に集約する補助関数。目的は Zapper Router の permit パス・代行コントラクトの Tx 数削減のために提供すること。
- **権限**: permissionless（`pausedRedeem == false` かつ `whenUnderlyingReady`）。
- **事前条件（Checks）**: pause 非該当；`whenUnderlyingReady`；`_dTokenAmount != 0`；`_receiver != address(0)`；`_dTokenAmount` が Underlying base unit に exact に対応する；有効な permit 署名、または permit がすでに実行済みで Vault への allowance が `_dTokenAmount` 以上あること。
- **動作（Effects）**:
  1. Pause チェック（`Paused`）
  2. Underlying ready チェック（`UnderlyingNotSet` / `UnderlyingMismatch`、[VAULT-FR-011](#vault-fr-011-setunderlying後付け確定一度限り)）
  3. 入力検証（`_dTokenAmount == 0` → `ZeroAmount`）
  4. **受領者検証** — `_receiver == address(0)` なら `ZeroAddress` で revert（permit nonce 消費前）
  5. **Checks: 必要 Underlying を exact 算出** — [VAULT-FR-002](#vault-fr-002-redeemdtoken--underlying) と同じ exact check を permit 前に実行する。`InvalidDTokenAmount` なら permit nonce / allowance を消費しない
  6. **Permit 実行 / allowance 確認** — `dToken.permit(msg.sender, vault, _dTokenAmount, _deadline, _v, _r, _s)` で Vault に対する allowance を発行する。permit が失敗した場合でも、同じ permit が第三者に先行実行された等により既に `allowance(msg.sender, vault) >= _dTokenAmount` なら続行する。不足なら `PermitFailed` で revert（[DTKN-FR-007](./dToken.md)）。
  7. **dToken を Vault へ移送** — `safeTransferFrom(msg.sender, vault, _dTokenAmount)` で Vault が一時保有
  8. **Checks: buffer を計測** — `bufferBal = bufferBalance()`
  9. **Effects: dToken を burn** — `dToken.burn(address(this), _dTokenAmount)`（**Vault 自身が保有する dToken を焼却**。redeem との差分はここのみ）
  10. **Interactions: 以降は redeem と同一** — buffer 十分時は即時支払い、不足時は先着総取り＋WithdrawRequest 登録（[VAULT-FR-002](#vault-fr-002-redeemdtoken--underlying) と同じロジック）
- **revert / 早期 return**: `_dTokenAmount == 0` → `ZeroAmount`；`_receiver == address(0)` → `ZeroAddress`（permit nonce 消費前に拒否）；倍率の整数倍でない dToken amount / `underlyingNeeded == 0` → `InvalidDTokenAmount`（permit nonce 消費前に拒否）；`pausedRedeem` → `Paused`；Underlying 未設定 → `UnderlyingNotSet`；不一致 → `UnderlyingMismatch`；`dToken.permit` 失敗かつ Vault への allowance 不足 → `PermitFailed`；`safeTransferFrom` 失敗 → 上流 revert；以降は [VAULT-FR-002](#vault-fr-002-redeemdtoken--underlying) と同じ失敗パスを継承。
- **発火イベント**: `Redeemed(user, receiver, dTokenAmount, underlyingPaidNow, requestId)`（redeem と同一シグネチャ。`user = msg.sender` ＝ permit 署名者）/ buffer 不足時のみ `WithdrawRequested(...)`。
- **設計上のポイント**:
  - **redeem との唯一の差分**: burn の対象が `msg.sender` ではなく `address(this)`（Vault 自身）。permit→transferFrom により dToken が一時的に Vault に移される設計。
  - 本関数は dToken の EIP-2612 Permit 実装を前提とする（[DTKN-FR-007](./dToken.md)）。
  - **permit front-run 耐性**: EIP-2612 permit は第三者が先に提出できる。先行実行で nonce が消費されても allowance が残っていれば redeem を続行し、署名者の一括操作を grief できないようにする。
  - **DOMAIN_SEPARATOR は実トークン名を追従**: dToken は `_EIP712Name()` を `name()` を返すよう override しているため、`setTokenInfo` で `name` を確定させると EIP-712 の DOMAIN_SEPARATOR もその実名（例: `dWBTC`）を反映する。標準ウォレットが `name()` から組んだ permit 署名はそのまま検証成立する（根拠は [DTKN-FR-007](./dToken.md)）。
- **Verification**: unit（permit→burn(self)→分岐・各 revert、permit front-run 済み allowance の許容）, integration（標準ウォレット署名が検証成立）。

### VAULT-FR-004: allocate（buffer 余剰を Strategy へ配分）

- **Type**: Functional ｜ **Source**: Product-Overview「Strategy 配分」/ push モデル
- **シグネチャ**: `allocate()`
- **目的**: Vault buffer の余剰分を、事前登録された Strategy 群へ固定 weights に従って配分する。目的は buffer を target 水準まで縮小すること。宛先・比率を引数で受け取らず、事前設定の Strategy・weights に従うだけ。
- **権限**: `ALLOCATOR_ROLE` のみ。`pausedAllocation == false`（`whenNotPausedAllocation`）。
- **事前条件（Checks）**: `block.timestamp >= lastAllocatorTime + allocatorCooldown`；`pausedAllocation == false`。
- **動作（Effects）**:
  1. **managed assets とバッファを計測** — `M = managedUnderlying = bufferBalance() + Σ live min(Strategy_i.estimatedTotalUnderlying(), Strategy_i.principal())`。protected backstop reserve と cached Strategy value は配分対象でも目標 buffer 算出対象でもない。enabled / weight を問わず登録中の Strategy の live valuation が 1 件でも構成できなければ `M = 0` として outbound 全体を fail-closed にする。`M == 0` なら何もせず return（`lastAllocatorTime` 更新・`Allocated` 発火もしないため、依存回復後に cooldown 待ちなしで再試行できる）
  2. **目標バッファを算出** — `B_target = max(M * bufferTargetBps / 10000, bufferFloor) + pendingWithdrawals`（`pendingWithdrawals` 加算の根拠: claim 用資金が Strategy へ流出するのを防ぐ、[VAULT-FR-006](#vault-fr-006-claimwithdrawrequest-の遅延償還受領)）
  3. **配分対象量 `excess` を決定** — `excess = min(max(B - B_target, 0), allocateMaxMove)`
  4. **`excess` を Strategy 群へ配分**（下記「配分ルール」。Strategy ごとの実配分額は `StrategyAllocated(strategy, amount)` で発火）
  5. **`lastAllocatorTime = block.timestamp`** を更新
- **配分ルール**:
  - 対象は `enabled = true` の登録 Strategy のみ
  - 各 Strategy への配分量は `weightBps_i / totalWeightBps` で按分
  - 配分は **Vault が `safeTransfer(strategy, share)` で Underlying を送付し、Strategy の純受領額 `received` を残高差分で測った後に `strategy.deposit(share, received)` を呼ぶ**（push モデルの預入）。Strategy は成功時に `received`、完全回収後の skip 時に `0` を返す
  - 各 Strategy の cap 残（`cap_i - estimatedTotalUnderlying_i`）を超える分は当該 Strategy へ送らない。managed assets preflight で `estimatedTotalUnderlying()` または `principal()` が 1 件でも読めなければ当該回の allocation 全体を早期 return する。preflight 後の Strategy 別 cap 再読だけが失敗した場合は、その Strategy の share のみ skip する
  - `BaseStrategy.deposit` は `_doDeposit(received)` を self-only の別 call frame で実行する。非 0 の `share` に対して `received == 0` なら fail-closed とする。非 0 の受取後に外部プロトコルが reject した場合、その frame の protocol 操作を巻き戻し、`share == received`（往路 transfer fee なし）かつ Strategy 減少額・Vault 実増額がともに `received` と一致するときだけ idle Underlying を Vault へ戻して `0` を返す。Vault は `StrategyAllocationSkipped` を発火して後続 Strategy を続行する
  - `share != received`、返送失敗、fee-on-transfer / rebasing 等で送受残高差が一致しない場合は `DepositRecoveryFailed` で `allocate()` 全体を revert し、最初の `safeTransfer` から巻き戻す。単純な catch 後に Strategy idle へ資金を残す動作は許可しない
  - **cap で削られた分・preflight 後の Strategy 別 valuation 再読 failure または deposit reject で skip された分は他 Strategy へ再配分しない**（残量は Vault buffer に留まる）
  - 運用上 `totalWeightBps == 10000` を維持することを推奨。意図的に下げる場合、登録 Strategy 内で按分される量が増えることに注意
- **revert / 早期 return**: `block.timestamp < lastAllocatorTime + allocatorCooldown` → `CooldownNotMet`；`pausedAllocation == true` → revert；`M == 0`（残高 0 または登録 Strategy の live valuation 不可）→ 早期 return（イベント・時刻更新なし）；deposit reject 後に exact recovery できない場合 → `DepositRecoveryFailed` で全体 revert。exact recovery できる reject は当該 Strategy のみ skip する。
- **発火イベント**: `StrategyAllocated(strategy, amount)`（Strategy ごとの実配分額）/ `StrategyAllocationSkipped(strategy)`（preflight 後の cap 用 valuation 再読不可、cap 到達、または deposit reject 後の完全回収で当該 Strategy へ配分しない場合）/ `Allocated(bufferBefore, targetBuffer, bufferAfter)`（1 回の `allocate()` 前後のバッファ集約、[VAULT-EVT-004](#11-イベント監視要件evt)）。managed assets preflight failure は outbound も cooldown も進めずイベントなしで早期 return するため、外部 monitor は `getStrategyStatuses()` の availability と keeper call 後の `Allocated` 欠落を相関する。availability が正常かつ cap 残ありの `StrategyAllocationSkipped` は deposit reject と判定する。
- **設計上のポイント**:
  - Strategy 別の投下額は `StrategyAllocated` でイベント追跡できる。現在値・AUM・推定損益は `getStrategyStatuses()` を一次ソースにし、subgraph（The Graph）側で時系列スナップショット化する運用とする（[§11](#11-イベント監視要件evt)）。
  - 例: `excess = 1000`、A（`weightBps = 5000`、cap 残 200）、B（`weightBps = 5000`、cap 残 1000）、`totalWeightBps = 10000` → A は 500 算出 → cap で 200 に削られ A=200、B は 500 算出 → cap 余裕あり B=500、**残 300 は Vault buffer に残る**。managed assets preflight で A の valuation（estimate または principal）が revert した場合は allocation 全体を早期 return し、B にも送らない。
- **Verification**: unit（cooldown・pause・M==0・cap クランプ・estimate/principal failure 時の全 outbound 停止＋cooldown 非消費＋自動復旧・deposit reject の完全回収＋後続継続・transfer fee で exact recovery 不可なら全体 revert・再配分しない）, invariant=[VAULT-INV-006](#vault-inv-006)。

### VAULT-FR-005: receiveFromStrategy（Strategy → Vault の push 受入）

- **Type**: Functional ｜ **Source**: Product-Overview「push モデル」/ [Strategy](./strategies/Strategy.md) `sendToVault` / `sendProfitToVault`
- **シグネチャ**: `receiveFromStrategy(uint256 _declaredAmount) returns (uint256 received)`
- **目的**: push モデルにおける **Strategy → Vault の元本返却系受入口**。Strategy が外部プロトコルから引き出した Underlying のうち、元本回収 `sendToVault`、固有緊急回収 `emergencyWithdrawFrom{Protocol}`、汎用 idle 救済 `emergencyWithdraw` のように Strategy valuation cache を減額すべき経路はこの関数に集約する。収益のみを戻す `sendProfitToVault` と Underlying reward claim は、Strategy が Vault buffer へ直接 transfer し、principal と valuation cache を減らさない（[Strategy 要件定義](./strategies/Strategy.md)）。
- **権限**: 登録済み Strategy のみ（`msg.sender` が `strategies[]` に存在すること。ロールではなく登録で判定。`enabled` か無効化済みでも `strategies[]` に残存する間は可）。
- **事前条件（Checks）**: `msg.sender` が登録済み Strategy。
- **動作（Effects）**:
  1. **登録検証** — `msg.sender` が登録済み Strategy でなければ `NotRegisteredStrategy` で revert
  2. **ゼロ短絡** — `_declaredAmount == 0` なら `ReceivedFromStrategy(msg.sender, 0, 0)` を発火して `0` を返す（revert しない）
  3. **実受領計上** — 受領前の Vault 残高を記録し、`safeTransferFrom(msg.sender, vault, _declaredAmount)` で引き取り、残高差分を `received` として確定する
  4. **valuation cache reconciliation** — `received == _declaredAmount` の exact delivery なら fallback valuation cache の `conservativeValue` を `received` 分だけ減額するが、`updatedAt` は更新しない。receipt は Vault buffer への実着を証明しても、Strategy に残る価値の full valuation ではないためである。fee-on-transfer / rebase 等で両者が異なる場合、Vault は receipt だけから upstream position の減少量を確定できないため cache を無効化する。これにより live valuation 失敗時に曖昧または期限切れの cache を fresh として pricing へ使わない
  5. **`ReceivedFromStrategy(msg.sender, _declaredAmount, received)` を発火**
- **revert / 早期 return**: 未登録 Strategy → `NotRegisteredStrategy`；`_declaredAmount == 0` → `ReceivedFromStrategy(_, 0, 0)` 発火＋`0` 返却（revert しない）；`safeTransferFrom` 失敗（残高・allowance 不足）→ 上流 revert。
- **発火イベント**: `ReceivedFromStrategy(strategy, declaredAmount, received)`（`declaredAmount` は要求量、`received` は Vault が実際に受領した残高差分、[VAULT-EVT-005](#11-イベント監視要件evt)）。
- **設計上のポイント**:
  - **approve 方向は Strategy → Vault**: Strategy は初期化時に `underlying.safeApprove(vault, type(uint256).max)` で **Vault に対して** max approve しており、Vault は `safeTransferFrom` で引き取れる（[VAULT-FR-011](#vault-fr-011-setunderlying後付け確定一度限り) / [Strategy 要件定義](./strategies/Strategy.md)）。
  - **declared と実受領の分離**: `received` は declared 量ではなく **残高差分**で確定するため、fee-on-transfer / rebasing 等で実着額が declared を下回っても会計がずれない。呼び出し元 Strategy はこの `received`（= 戻り値）を基準に自らの `principal` を減算する（[Strategy 要件定義](./strategies/Strategy.md)）。
  - **元本返却系のみ cache を reconcile**: 本関数を通った受領は元本返却系として扱い、exact delivery なら cache を実着額分減額し、declared/received mismatch なら cache を無効化する。`sendProfitToVault` / Underlying reward claim は本関数を通らず Strategy から Vault へ直接送金されるため、Strategy principal / valuation cache を動かさない。収益の Treasury 送付は別関数 `transferYieldToTreasury`（[VAULT-FR-007](#vault-fr-007-transferyieldtotreasury収益の-treasury-送付)）が担う。
  - **部分回収は cache TTL を更新しない**: exact receipt で判明するのは「既知量が Strategy から Vault へ移った」ことだけで、残存 position の現在価値ではない。`updatedAt` を receipt 時刻へ進めると、未観測損失を含み得る古い高値 cache を少額回収で反復延命できる。したがって TTL は最後に full live valuation が成功した時刻から進み続け、期限後は partial recovery 中でも pricing unavailable として fail-closed する。pricing availability は両 live valuation read が復旧した時点で直ちに回復する。permissionless `refreshStrategyValuation` はその full valuation を bounded cache へ再格納し、その後の一時的な read failure に備える。確定損失の incident writeoff は帳簿上の毀損を確定するが、valuation が読取不能なままなら availability を回復しない（[VAULT-FR-009](#vault-fr-009-updatestrategy--emergencydisablestrategy--writeoffstrategyprincipal登録-strategy-の調整と元本毀損確定)）。
  - **`nonReentrant`**。
- **Verification**: unit（未登録 revert・ゼロ短絡・残高差分計上・declared/received mismatch 時の cache 無効化と live 回復・partial recovery が TTL を延長せず live read 復旧で availability 回復・full refresh で cache 再格納）, invariant=[VAULT-INV-005](#vault-inv-005)。

### VAULT-FR-006: claim（WithdrawRequest の遅延償還受領）

- **Type**: Functional ｜ **Source**: 償還フロー（buffer 不足の遅延化）
- **シグネチャ**: `claim(uint256 _requestId)`
- **目的**: redeem 時に buffer 不足で発行された `WithdrawRequest` を、`withdrawDelay` 経過後にユーザーが Vault から引き出せるようにする。目的は、即時 redeem では受け取れなかった残額を後から受領できるようにすること。
- **権限**: permissionless。誰でも成熟済み request の settlement を trigger できるが、送金先は記録済み `req.owner` に固定され、caller は受取先を変更できない。**`pausedDeposit` / `pausedRedeem` の影響は受けないが、`pausedClaim`（GUARDIAN、[VAULT-FR-014](#vault-fr-014-pause--unpause緊急停止)）の停止対象**。既得の引出し受領を平時に止めることはなく、Strategy 実損（A < L_effective）時の equitable repair freeze（buffer の先着ドレイン阻止）に限って停止する運用前提とする。
- **事前条件（Checks）**: `pausedClaim == false`（停止中は `Paused`）；request 存在。未決済 request の settlement には `block.timestamp >= req.claimableAt` と `bufferBalance() >= req.underlyingAmount` を要求する。既決済 request は idempotent に `0` を返す。
- **動作（Effects）**（Checks → buffer 検証 → Effects → Interaction の CEI 順）:
  1. **存在検証** — `withdrawRequests[_requestId].owner == address(0)` なら `RequestNotFound` で revert（未発行 ID への呼出し防止）
  2. **既決済 short-circuit** — `req.claimed == true` なら state、送金、event を変更せず `0` を返す。第三者が owner の tx より先に permissionless settlement を実行しても、owner 側 retry を revert させない
  3. **時刻検証** — `block.timestamp < req.claimableAt` なら `RequestNotReady` で revert（早期 claim 不可）
  4. **Buffer 残高検証** — `bufferBalance() < req.underlyingAmount` なら `InsufficientBuffer` で revert（部分 claim 不可、buffer 回復後に再試行）
  5. **状態更新（Effects）** — `req.claimed = true`、`pendingWithdrawals -= req.underlyingAmount`
  6. **支払い（Interactions）** — `req.underlyingAmount` を記録済み `req.owner` に `safeTransfer`。`msg.sender` への送金や任意 receiver 指定はない
- **revert / 早期 return**: `pausedClaim` → `Paused`；`_requestId == 0` または未発行 ID → `RequestNotFound`；既 claim 済み → `0` を早期 return；`block.timestamp < req.claimableAt` → `RequestNotReady`；`bufferBalance() < req.underlyingAmount` → `InsufficientBuffer`（state 変更は巻き戻し、後日 buffer 回復後に再試行可）。
- **発火イベント**: `WithdrawClaimed(user, requestId, amount)`（`user` は caller にかかわらず `req.owner`、`amount` は `req.underlyingAmount`、[VAULT-EVT-006](#11-イベント監視要件evt)）。
- **設計上のポイント**:
  - **WithdrawRequest 構造体**: redeem の buffer 不足分岐で発行され `withdrawRequests[requestId]` に永続化される。フィールド: `owner`(address, 固定送金先。redeem の `_receiver` を記録) / `underlyingAmount`(uint256, buffer 不足分 `remaining`) / `claimableAt`(uint256, `block.timestamp + withdrawDelay`) / `claimed`(bool, 二重 claim 防止)。requestId は `nextRequestId`（初期値 1、redeem 発行ごとに +1）で採番。`requestId = 0` は「即時完了」の予約値で `withdrawRequests` に登録されない。
  - **permissionless trigger / fixed payout**: redeem の `msg.sender`（呼出元）と `_receiver`（最終受領者）が異なる場合も、`WithdrawRequest.owner = _receiver` を entitlement / 固定送金先として保存する。EOA、Safe、任意実行機能を持たない contract receiver のいずれでも、本人・keeper・第三者が `claim()` を trigger でき、Underlying は常に owner だけへ送られる。caller は横取りやredirectをできない。
  - **idempotent retry**: permissionless caller が owner の claim tx を front-run しても、owner の後続 tx は `0` で成功し、二重送金・二重 event・`pendingWithdrawals` の二重減算を行わない。既決済 tx の gas 自体は caller が負担するため、これは revert-based griefing と失敗 UX を除く hardening であり、不要 tx の gas 費用を払い戻す仕組みではない。
  - **順序制御**: FIFO 制約なし。`claimableAt` を過ぎた request は任意の順序で claim 可能。buffer が回復した瞬間に最初に呼んだユーザーが受け取る**競争条件**が存在する（受容済みの既知リスクと運用対処は [§12](#12-失敗時異常系挙動err)）。
  - **有効期限**: なし。`claimed == false` である限り無期限で claimable。
  - **部分 claim**: 不可。buffer 不足時は全額 revert。
  - **`pendingWithdrawals` の役割**: 未 claim 残高合計を保持。`allocate()` で `B_target += pendingWithdrawals` として加算され claim 用資金の Strategy 流出を防ぐ（[VAULT-FR-004](#vault-fr-004-allocatebuffer-余剰を-strategy-へ配分)）。`transferYieldToTreasury()` では、(a) `L_effective = L_user + L_pending` としてユーザー負債扱いされ accounting 上の取りすぎを防ぎ、(b) 送金上限が `allocate` と同じ流動性予約 `B_reserve`（`pendingWithdrawals` を含む）を控除した liquid buffer に制限されることで、claim 用 liquidity が Treasury 送付で抜かれない（[VAULT-FR-007](#vault-fr-007-transferyieldtotreasury収益の-treasury-送付)）。
  - **CEI 順序の注記**: buffer 不足時は Effects 前に revert するため `claimed = true` は永続化されない。既決済 short-circuit は外部 call 前に終了する。Reentrancy も `nonReentrant` で防御。
  - 例: user A が `redeem(100, A)` を呼び buffer 30 / 不足 70 → `WithdrawRequest{owner:A, underlyingAmount:70, claimableAt: now+1day, claimed:false}` が requestId=5 で発行。24h 後 ALLOCATOR が対象 Strategy の `sendToVault(70)` で 70 を buffer 補充。keeper B が `claim(5)` → 存在/未 claim/時刻/buffer OK → `claimed=true`、`pendingWithdrawals -= 70` → 70 を A へ送金し、B は受け取らない。A の同 request retry は `0` を返し、追加送金・event・会計更新はない。未発行 ID は引き続き `RequestNotFound`。
- **Verification**: unit（存在/時刻/buffer 各 revert・既決済 idempotent return・permissionless front-run 後の owner retry・固定送金先・caller 非受領・contract receiver・部分 claim 不可・無期限）, invariant=[VAULT-INV-004](#vault-inv-004)。

### VAULT-FR-007: transferYieldToTreasury（収益の Treasury 送付）

- **Type**: Functional ｜ **Source**: Product-Overview「Treasury 収益化」/ push モデル収益化の第 2 段
- **シグネチャ**: `transferYieldToTreasury() returns (uint256 transferred)`
- **目的**: Vault liquid buffer のうち、managed assets が負債を超える分だけを Treasury へ送る。push モデルの収益化は 2 段構成で、本関数は Vault 側の第 2 段。第 1 段＝各 Strategy の realized 収益を buffer へ引き上げる `Strategy.sendProfitToVault` は Strategy 関数（[Strategy 要件定義](./strategies/Strategy.md)、ALLOCATOR が各 Strategy を 1 件ずつ呼ぶ）。
- **権限**: `ALLOCATOR_ROLE`、`nonReentrant`（第 1 段 `Strategy.sendProfitToVault` も ALLOCATOR）。`pausedAllocation == false`（Vault から系外へ出る treasury sweep は emergency allocation pause で停止する）。`allocatorCooldown` の対象ではない。
- **事前条件（Checks）**: ALLOCATOR_ROLE 保有；`pausedAllocation == false`。
- **会計原則**:
  - `A = totalUnderlying()`: backing / oracle 用の総資産。Vault raw Underlying balance（liquid buffer + backstop reserve）に、各 Strategy の保守評価を加算
  - `M = managedUnderlying`: allocation / Treasury 用の管理対象資産。`bufferBalance() + Σ live min(estimatedTotalUnderlying, principal)` で、protected backstop reserve を除外する。登録 Strategy の valuation が 1 件でも読めない場合は cached value や部分合計で送金せず、`M = 0` として outbound 全体を早期 return する
  - `L_user = actual dToken liabilities`: `convertToUnderlying(dToken.totalSupply())` を基本とし、legacy / migration 等で総供給が Underlying base unit に exact 対応しない dust を含む場合は 1 base unit へ切り上げる
  - `L_pending = pendingWithdrawals`: 既発行の遅延償還の未 claim 残（[VAULT-FR-006](#vault-fr-006-claimwithdrawrequest-の遅延償還受領)）
  - `L_effective = L_user + L_pending`
  - 原則: **常に `A >= L_effective` を維持**（`A < L_effective` は元本毀損。buffer / cap / Strategy 選定で最優先に防ぎ、万一発生時は `backingRatio()` がオラクルに下方反映する＝[VAULT-FR-016](#vault-fr-016-backingratiodtoken-裏付け率の供給) / [VAULT-INV-001](#vault-inv-001)）
  - buffer surplus（送金可能な収益）: `surplus = max(M - L_effective, 0)`。backstop reserve は surplus を作らない
- **動作（Effects）**:
  1. **超過分の算出** — `M = managedUnderlying`、`L = L_effective`。`M <= L` なら `YieldTransferredToTreasury(0, treasury)` を発火して `0` を返す
  2. **流動性予約を控除した buffer でクランプ** — `surplus = M - L`。送金は、`allocate` が手元に残すのと同じ流動性予約 `B_reserve = max(M·bufferTargetBps/10000, bufferFloor) + pendingWithdrawals`（[VAULT-FR-004](#vault-fr-004-allocatebuffer-余剰を-strategy-へ配分) の `B_target` と同一・実装は共有ヘルパー `_requiredBuffer`）を超える liquid buffer だけを上限とする: `transferred = min(surplus, max(bufferBalance() - B_reserve, 0))`。**buffer を上限とする**ことで Strategy 内 Underlying と protected backstop reserve を取り崩さず、さらに **`B_reserve` を控除する**ことで遅延償還の待機 claim 用 liquidity（`pendingWithdrawals`）と buffer target を Treasury 送付が抜かない（[VAULT-FR-006](#vault-fr-006-claimwithdrawrequest-の遅延償還受領)）。`surplus`（= `M - L_effective`）は送金の accounting 上限として維持され、予約超過分に元本が混じる局面でも送らない
  3. **送金** — `transferred > 0` なら `treasury` へ `safeTransfer`
  4. **`YieldTransferredToTreasury(transferred, treasury)` を発火**
- **revert / 早期 return**: 非 ALLOCATOR → revert；`pausedAllocation == true` → `Paused`；`M <= L` → `YieldTransferredToTreasury(0, treasury)` 発火＋`0` 返却（revert しない）。
- **発火イベント**: `YieldTransferredToTreasury(amount, treasury)`（Vault から発火。`amount` は Treasury へ送った額、0 でも発火、[VAULT-EVT-007](#11-イベント監視要件evt)）。（第 1 段の `ProfitSentToVault` は **Strategy から**発火、[Strategy 要件定義](./strategies/Strategy.md)）。
- **設計上のポイント**:
  - **2 段に分離した理由**: Strategy 内に滞留している収益は本関数だけでは Treasury へ届かない（buffer 上限のため）。ALLOCATOR はまず Strategy の `sendProfitToVault`（[Strategy 要件定義](./strategies/Strategy.md)）で収益を buffer へ引き上げ、続けて本関数で Treasury へ送る。
  - **取りすぎの抑制**: `M` は `min(estimatedTotalUnderlying, principal)` の保守評価で未実現収益（est > principal）の前計上を防ぎ、送金は buffer 上限のため Strategy 内資産と backstop reserve を取り崩さない。ただし **損失が est に未反映で est が principal を下回っていない**（または writeoff が遅延した）場合は surplus が過大評価され、buffer から取りすぎが起こり得る。適時の `writeoffStrategyPrincipal`（[VAULT-FR-009](#vault-fr-009-updatestrategy--writeoffstrategyprincipal登録-strategy-の調整と元本毀損確定)）と保守的 est で軽減する（[§9](#9-セキュリティ要件sec) / [§12](#12-失敗時異常系挙動err)）。
  - **個別 Strategy 障害の隔離**: push モデルでは ALLOCATOR が Strategy を 1 件ずつ `sendProfitToVault` で呼ぶため、1 件の失敗が他へ波及しない。本関数は全登録 Strategy の valuation view を preflight し、1 件でも取得不能なら `managedUnderlying = 0` として Treasury 送金全体を早期 return する。cached value や不完全な部分合計に対して送金しない。
  - **非 Underlying・非 position reward token は対象外**: `transferYieldToTreasury` は Vault liquid buffer 内の Underlying だけを扱い、backstop reserve には触れない。Aave incentives / Merkl 等の別トークン報酬は `totalUnderlying()` / `backingRatio()` に含めず、Strategy 側の `sweepRewardToken` で Treasury へ送る。Aave aToken、Morpho vault share、Euler eToken / vault share 等の position / receipt / accounting token は reward ではなく、派生 Strategy 側で protected token として sweep を拒否する。backing を修復する場合は Treasury / backstop が報酬を Underlying に換金して `backstopDeposit` 等で明示的に入金する。
  - 例: Strategy A（principal=1000、est=1080）、buffer=50、backstop reserve=0、`L_effective=1000` → 第 1 段前の `M = 50 + min(1080,1000) = 1050`、`surplus=50`（Strategy 内の収益 80 は保守評価で隠れている）。ALLOCATOR が `A.sendProfitToVault()`（Strategy 関数）: realized 80 が buffer へ積まれ buffer=130、principal 不変。ALLOCATOR が `transferYieldToTreasury()`: `M = 130 + min(1000,1000) = 1130`、`surplus=130`、`transferred = min(130,130) = 130` → Treasury へ 130（本例は `bufferTargetBps=0`・`pendingWithdrawals=0` ゆえ `B_reserve=0`＝予約控除なし。`pendingWithdrawals>0` または `bufferTargetBps>0` では送金は `min(surplus, max(bufferBalance()-B_reserve,0))` まで縮む）。backstop reserve が存在しても `M` から除外されるため、reserve 入金だけでは Treasury surplus は生まれない。
- **Verification**: unit（M<=L 早期・buffer クランプ・min 評価・backstop 除外）, invariant=[VAULT-INV-005](#vault-inv-005)。

### VAULT-FR-008: Strategy whitelist・登録・解除（addToWhitelist / removeFromWhitelist / addStrategy / removeStrategy）

- **Type**: Functional ｜ **Source**: Product-Overview「Strategy 配分」/ リスク制御（二段階承認）
- **シグネチャ**: `addToWhitelist(address strategy)` / `removeFromWhitelist(address strategy)` / `addStrategy(IStrategy strategy, uint256 weightBps, uint256 cap)` / `removeStrategy(IStrategy strategy)`
- **目的**: Strategy の登録は資金リスクが大きいため「ホワイトリスト登録（事前承認）→ 実際の追加（本番投入）」の二段階を明示的に分離する。解除は登録済み Strategy の除去（`principal == 0` かつ live `estimatedTotalUnderlying == 0` が前提）。
- **権限**: リスク増方向（`addToWhitelist` / `addStrategy`）は GOV_MULTISIG（Vault `GOV_ROLE`・holder = 共通 Timelock）。fail-safe 方向（`removeFromWhitelist` / `removeStrategy`）は `GUARDIAN_ROLE`（即時）。除去系はいずれも backing 評価に影響しない（remove は `principal == 0` かつ live `estimatedTotalUnderlying == 0` 必須＝寄与と残余資産が既に 0、whitelist 除去は登録済み Strategy に影響しない）ため即時で安全（[VAULT-GOV-004](#vault-gov-004-timelock-と緊急-pause-の分離)）。
- **事前条件（Checks）**:
  - `addToWhitelist`: `strategy != address(0)`；`strategy.code.length > 0`；未 whitelist（既に true なら `AlreadyWhitelisted`）
  - `addStrategy`: `whitelistedStrategies[strategy] == true`（未承認なら `NotWhitelisted`）；**`vault.underlying() != address(0)`**（未活性 placeholder には登録不可、`UnderlyingNotSet`）かつ **`strategy.underlying() == vault.underlying()`**（担保資産不一致なら `UnderlyingMismatch`）；既登録でない（`StrategyAlreadyExists`）；`strategies.length < MAX_STRATEGIES`（`MAX_STRATEGIES = 32`、`TooManyStrategies`）；`totalWeightBps + weightBps <= 10000`（`WeightExceedsBps`）
  - `addStrategy`: `strategy != address(0)`；`strategy.code.length > 0`（EOA / 未デプロイアドレス不可）
  - `removeFromWhitelist`: 既 whitelist であること
  - `removeStrategy`: 対象が登録済みであること。**`strategy.principal() == 0`**（残元本がある、または `principal()` が読めない場合は `StrategyHasPrincipal`）かつ live **`strategy.estimatedTotalUnderlying() == 0`**。live valuation が読めない、または残余資産・未回収 yield が残る場合は `StrategyHasAssets`。`enabled` か無効化済み（`strategies[]` 残存）かを問わず実行可
- **動作（Effects）**:
  1. `addToWhitelist`: `whitelistedStrategies[strategy] = true`、`StrategyWhitelisted(strategy)` 発火
  2. `removeFromWhitelist`: `whitelistedStrategies[strategy] = false`、`StrategyRemovedFromWhitelist(strategy)` 発火（既に `addStrategy` 済みの登録には影響しない）
  3. `addStrategy`: 前提条件をすべて満たしたうえで `strategies[]` に追加・`strategyConfigs[strategy] = {enabled, weightBps, cap}` を設定・`totalWeightBps += weightBps`（派生値の再集計、[§7](#7-状態変数会計モデル)）、`StrategyAdded(strategy, weightBps, cap)` 発火
  4. `removeStrategy`: `principal == 0` と live `estimatedTotalUnderlying == 0` を確認のうえ `strategies[]` から除去、valuation cache を破棄し、`StrategyRemoved(strategy)` 発火
- **revert / 早期 return**: `addToWhitelist`: `ZeroAddress` / `NotContract` / `AlreadyWhitelisted`。`removeFromWhitelist`: 未 whitelist → `StrategyNotFound`。`addStrategy`: `ZeroAddress` / `NotContract` / `NotWhitelisted` / `UnderlyingNotSet` / `UnderlyingMismatch` / `StrategyAlreadyExists` / `TooManyStrategies` / `WeightExceedsBps`。`removeStrategy`: 未登録 → `StrategyNotFound`／残元本あり・principal 読取不能 → `StrategyHasPrincipal`／live valuation 失敗または残余資産あり → `StrategyHasAssets`。
- **発火イベント**: `StrategyWhitelisted(strategy)` / `StrategyRemovedFromWhitelist(strategy)` / `StrategyAdded(strategy, weightBps, cap)` / `StrategyRemoved(strategy)`（[VAULT-EVT-008](#11-イベント監視要件evt)）。
- **設計上のポイント**:
  - **ホワイトリスト除去 ≠ Strategy 解除**: 既存 Strategy の資金回収（`Strategy.sendToVault`、[Strategy 要件定義](./strategies/Strategy.md)）・元本ゼロ化（`writeoffStrategyPrincipal`、[VAULT-FR-009](#vault-fr-009-updatestrategy--writeoffstrategyprincipal登録-strategy-の調整と元本毀損確定)）は `removeStrategy` の前処理として行う。解除前に回収不能分を writeoff して `principal` をゼロにし、さらに回収可能な残余資産・未回収 yield も live `estimatedTotalUnderlying() == 0` まで回収しておく必要がある。live valuation が読めない Strategy は誤除去を避けるため removal を fail-closed する。完了時に `StrategyRemoved` を発火する（救済用の失敗 removal リトライ機構は持たない＝引き出し失敗の救済は push 回収＋writeoff で行う）。
  - **addStrategy の Underlying 不変条件（活性化前ガードの復元）**: push モデルでは Underlying の approve 方向が反転し（**Strategy が初期化時に Vault を approve**、[VAULT-FR-005](#vault-fr-005-receivefromstrategystrategy--vault-の-push-受入)）、`addStrategy` は Underlying に触れない。このため「placeholder Vault（`underlying == address(0)`）では `addStrategy` が `underlying.safeApprove` で revert する」という暗黙の活性化前ガードが失われる。これを **明示的な前提条件**（`underlying != address(0)` かつ `strategy.underlying() == vault.underlying()`）で復元する。効果は 2 つ: (1) **活性化順序**（`setUnderlying`（[VAULT-FR-011](#vault-fr-011-setunderlying後付け確定一度限り)）→ `addStrategy`）を強制、(2) Vault と Strategy の **担保資産一致**を登録時に保証（別資産の Strategy を誤登録し、活性化後に `allocate` が誤った Underlying を送り込む／`receiveFromStrategy` が別トークンを pull する事故を防ぐ）。
  - **Strategy 数の上限**: `MAX_STRATEGIES = 32` は、strategy 一覧を走査する処理（`totalUnderlying` / `backingRatio`、`allocate`、`getStrategyStatuses`、`removeStrategy`、登録済み判定）に対する明示的な gas / 運用性の上限である。これ以上の外部運用先を追加する場合は、既存 Strategy から資金を回収または writeoff して remove / replace し、registry を無制限に伸ばさない。
  - **valuation gas の回帰境界**: `ExternalAuditGas01BackingRatioTest` は、実 `CollateralVault` に独立した実 `SkyUsdcSUsdsStrategy` proxy / implementation / sUSDS vault / converter を最大 32 件登録し、全件へ live position を配分する。baseline compiler 設定では `backingRatio()` が 32 件 cold で 1,332,387 gas、同一 transaction 内の warm 再評価で 261,884 gas、5 件 cold で 237,535 gas である。test は per-branch cold `< 2,000,000`、`CollateralRegistry` の protocol 上限10 branch が各32件を持つ `redeemCollateral` の cold + warm 2-pass valuation 部分 `< 20,000,000` を回帰上限とする（現行DF 8 branch 外挿は 12,754,168 gas、10 branch は 15,942,710 gas）。この外挿は PriceFeed / TroveManager の周辺処理と実際の Trove redemption loop を含む full transaction gas 上限ではない。新 Strategy 型の activation は、同じ最大件数 replay と target chain の block gas / `_maxIterationsPerCollateral` を含む gas estimate を再実行し、回帰上限を超える構成を承認しない。
  - **block 内 cache を置かない理由**: `backingRatio()` は借入・償還・清算価格へ伝播する solvency read であり、同一 block 内でも先行 transaction の Strategy 損失、回収、writeoff、backstop 入金により変化し得る。gas 削減のための block cache は invalidation surface と stale-price window を増やすため採用しない。
- **Verification**: unit（whitelist ガード・guardian remove・Underlying 不変条件・既登録・Strategy 数上限・weight 上限・`principal != 0` / live `estimatedTotalUnderlying != 0` / valuation failure の remove 拒否・最大32件の実 Sky valuation gas・最大10 branch 2-pass 外挿）, invariant=[VAULT-INV-007](#vault-inv-007) / [VAULT-INV-008](#vault-inv-008)。

### VAULT-FR-009: updateStrategy / emergencyDisableStrategy / writeoffStrategyPrincipal（登録 Strategy の調整と元本毀損確定）

- **Type**: Functional ｜ **Source**: Product-Overview「Strategy 配分」/ 緊急時の段階的回収
- **シグネチャ**: `updateStrategy(IStrategy _strategy, uint256 _weightBps, uint256 _cap, bool _enabled)` / `writeoffStrategyPrincipal(IStrategy _strategy, uint256 _amount, uint256 _minBackingRatioAfter)` / `forceDeallocateMorphoV2(IStrategy _strategy, address _adapter, bytes _data, uint256 _assets, uint256 _minReceived, uint256 _minBackingRatioAfter) → (uint256 penaltyShares, uint256 penaltyAssets, uint256 valuationLossAssets)`
- **目的**: `updateStrategy` は登録済み Strategy の配分比率（`weightBps`）・上限（`cap`）・有効フラグ（`enabled`）を GOV が更新する（増額・再有効化を含むため遅延。緊急の無効化は [VAULT-FR-019](#vault-fr-019-emergencydisablestrategy登録-strategy-の即時無効化) `emergencyDisableStrategy` が即時に担う）。`writeoffStrategyPrincipal` は Strategy の `estimatedTotalUnderlying()` が `principal` を恒久的に下回った場合、または外部プロトコルの実質損失が Strategy の評価 view に現れない場合に、当該 Strategy の `principal` を減算して帳簿上の毀損を確定する。`forceDeallocateMorphoV2` は Morpho V2 の share-paid penalty を confirmed loss として実現する操作を、同一 transaction の pause・valuation refresh・事後 backing guard と一体化する。
- **権限**: `updateStrategy` は GOV_MULTISIG（Vault `GOV_ROLE`・holder = 共通 Timelock）。`writeoffStrategyPrincipal` と `forceDeallocateMorphoV2` は **`WRITEOFF_ROLE`（高定足数 GOV multisig が直接保持・即時）**。実損の反映を遅延させると、markdown 未反映の過大評価担保で新規借入が進み bad debt が積み増すのを止められない（Core に任意発動できる可逆な借入停止は存在しない）ため、confirmed-loss 操作は timelock を経由させない（[VAULT-GOV-004](#vault-gov-004-timelock-と緊急-pause-の分離)）。
- **事前条件・動作（updateStrategy）**:
  1. **登録検証** — `_strategy` が登録済み（`strategies[]` に残存）でなければ `StrategyNotFound` で revert。無効化済み Strategy も GOV が cap / weight / enabled を再設定できる
  2. **無効化時の weight 不変条件** — `_enabled == false` かつ `_weightBps > 0` なら `InvalidWeight` で revert（**無効化済み Strategy は必ず `weightBps == 0`**。この不変条件が [§7](#7-状態変数会計モデル) / writeoff / remove の前提を支える、[VAULT-INV-009](#vault-inv-009)）
  3. **合計比率の上限** — `totalWeightBps - 旧 weightBps + _weightBps > 10000` なら `WeightExceedsBps` で revert
  4. **確定** — `totalWeightBps` を再集計（旧値を引き新値を足す派生値、[§7](#7-状態変数会計モデル)）し `config` の `weightBps` / `cap` / `enabled` を更新
  5. **`StrategyUpdated(strategy, weightBps, cap, enabled)` を発火**
- **事前条件・動作（emergencyDisableStrategy）**:
  1. **登録検証** — `_strategy` が登録済みでなければ `StrategyNotFound` で revert
  2. **即時停止** — 現在の `weightBps` を `oldWeightBps` として記録し、`totalWeightBps -= oldWeightBps`、`weightBps = 0`、`enabled = false` にする。`cap` / `principal` / valuation cache は変更しない
  3. **イベント** — `StrategyUpdated(strategy, 0, cap, false)` と `StrategyEmergencyDisabled(strategy, oldWeightBps)` を発火
- **事前条件・動作（writeoffStrategyPrincipal）**:
  1. **登録検証** — `_strategy` が登録済み（`enabled` か無効化済みでも `strategies[]` 残存）でなければ `StrategyNotFound` で revert
  2. **backing 影響 guard の検証** — `_minBackingRatioAfter <= 1e18` でなければ revert。caller は incident dry-run の結果からこの値を設定し、fat-finger・古い state・想定外の同時回収/損失で backing が想定以上に markdown されることを防ぐ
  3. **Strategy 側で減算** — `writtenOff = _strategy.writeoffPrincipal(_amount)` を呼ぶ（Strategy 側の動作要件は [Strategy 要件定義](./strategies/Strategy.md)。過大指定は Strategy 側で残 `principal` にクランプし、戻り値に実 writeoff 額を返す）
  4. **writeoff 後 backing guard** — cache refresh/reduction 後に `backingRatio()` を再計算する。`_minBackingRatioAfter` を下回る場合は、Strategy principal 減算や user-flow pause も含めて writeoff transaction 全体を revert する
  5. **`StrategyPrincipalWrittenOff(_strategy, writtenOff)` を発火**。要求額ではなく実際に減った `principal` を出す
- **事前条件・動作（forceDeallocateMorphoV2）**:
  1. `_assets != 0`、`_minReceived != 0`、`_minBackingRatioAfter <= 1e18`、`_strategy` が登録済みであることを検証する
  2. 同一 transaction 内で `pausedAllocation = true`、`pausedDeposit = true`、`pausedRedeem = true`、`pausedClaim = true` にする
  3. 登録 Strategy の Vault-only `forceDeallocate` wrapper を呼び、実 `penaltyShares` / `penaltyAssets` と追跡担保に帰属する `valuationLossAssets` を受け取る。Strategy は donated share を先に penalty へ充当し、init 凍結 penalty 上限超過は revert する。同じ呼出し内で追跡資産を最大 `_assets` 引き出して Vault へ直送し、実受領額だけ principal を減らす
  4. Vault の残高増分が `_minReceived` 未満なら全体を revert する。live valuation cache を refresh し、読取不能時は追跡損失と引出額の合計を cache から差し引く。引出額と実受領額が異なる場合は cache を無効化する
  5. 事後 `backingRatio()` が `_minBackingRatioAfter` 未満なら penalty・資金回収・pause を含む transaction 全体を revert する
  6. `MorphoV2ForceDeallocated(strategy, adapter, assets, penaltyShares, penaltyAssets, valuationLossAssets, backingRatioAfter)` を発火する
- **revert / 早期 return**: `updateStrategy`: `StrategyNotFound` / `InvalidWeight` / `WeightExceedsBps`。`emergencyDisableStrategy`: `StrategyNotFound`。`writeoffStrategyPrincipal`: `InvalidBackingRatioGuard` / `StrategyNotFound` / `StrategyWriteoffNotReady` / `BackingRatioBelowMinimum`。`forceDeallocateMorphoV2`: `ZeroAmount` / `InvalidBackingRatioGuard` / `StrategyNotFound` / Strategy wrapper の penalty guard / `RecoveryBelowMinimum` / `BackingRatioBelowMinimum`。
- **発火イベント**: `StrategyUpdated(strategy, weightBps, cap, enabled)` / `StrategyEmergencyDisabled(strategy, oldWeightBps)` / `StrategyPrincipalWrittenOff(strategy, amount)` / `MorphoV2ForceDeallocated(strategy, adapter, assets, penaltyShares, penaltyAssets, valuationLossAssets, backingRatioAfter)`（[VAULT-EVT-008](#11-イベント監視要件evt) / [VAULT-EVT-009](#11-イベント監視要件evt)）。
- **設計上のポイント**:
  - **正規の登録経路は `addStrategy`**（whitelist ＋ Underlying 不変条件のガードを通る、[VAULT-FR-008](#vault-fr-008-strategy-whitelist登録解除addtowhitelist--removefromwhitelist--addstrategy--removestrategy)）。`updateStrategy` は既登録 Strategy の調整専用で whitelist / Underlying 整合の再検査は行わない。
  - **無効化の手順**: 緊急時は `emergencyDisableStrategy(strategy)`（GUARDIAN・即時、[VAULT-FR-019](#vault-fr-019-emergencydisablestrategy登録-strategy-の即時無効化)）。計画的な無効化は `updateStrategy(strategy, 0, cap, false)`（手順 2 の不変条件に従い `weightBps` を 0 にする）。いずれも無効化後は `strategies[]` に残り、`receiveFromStrategy` での push 回収・`writeoffStrategyPrincipal`・`removeStrategy` の対象であり続ける。再有効化は遅延側の `updateStrategy` のみ（`addStrategy` での再登録は登録判定により `StrategyAlreadyExists` で拒否）。
  - **writeoff は帳簿操作のみ**: 実資産の移動は伴わない。回収可能分は先に `Strategy.sendToVault`（[Strategy 要件定義](./strategies/Strategy.md)）／緊急回収（`Strategy.emergencyWithdraw`、[Strategy 要件定義](./strategies/Strategy.md)）で Vault に戻し、残った回収不能分のみを writeoff する。Strategy の `estimatedTotalUnderlying()` が損失を反映しない場合でも、GOV が回収不能額を確定して writeoff すれば `min(est, principal)` の `principal` 側が下がり、`totalUnderlying()` / `backingRatio()` に下方反映される。
  - **writeoff と pricing availability は別境界**: writeoff 後の full live valuation が失敗した場合、Vault は cache の `conservativeValue` を実 writeoff 額だけ減らすが、`updatedAt` は最後の full valuation 時刻から進めない。元 TTL が期限切れなら、全額 writeoff で cache / principal が 0 になっても `backingRatioForPricing()` は unavailable のままである。writeoff は確定損失を会計へ反映する操作であって、読取不能な valuation を available にする証拠ではない。availability は両 live read の復旧時点で回復し、permissionless full refresh はその値を bounded cache へ再格納する。
  - **過大 writeoff の安全性**: `_amount > principal` でも Strategy 側でクランプされるため `principal` は負にならない。Vault 側イベントの `amount` は要求額ではなく実減少額を示す。`_minBackingRatioAfter` により operator が指定した backing 影響 guard が入り、要求額・単位・live state が incident dry-run とずれた場合に即時 writeoff が無音の過大 markdown にならない。無効化済み Strategy（`weightBps == 0`）にも実行できる。
- **Verification**: unit（登録検証・weight 不変条件・上限・guardian emergency disable・過大 writeoff クランプ・無効化済みへの writeoff・stale cache の全額 writeoff だけでは pricing availability が回復しない）, invariant=[VAULT-INV-009](#vault-inv-009)。

### VAULT-FR-010: initialize（プレースホルダー化・proxy 初期化）

- **Type**: Functional ｜ **Source**: Product-Overview「placeholder ブランチ」/ deferred-binding 運用
- **シグネチャ**: `initialize(IERC20 _underlying, IDToken _dToken, address _treasury, address _admin)`（`initializer`・UUPS 初期化）
- **目的**: UUPS proxy 越しに 1 度だけ初期化する。デプロイ時点では Underlying を未確定（placeholder）で立ち上げられ、後から [VAULT-FR-011](#vault-fr-011-setunderlying後付け確定一度限り) `setUnderlying` で確定する遅延初期化フロー（placeholder ブランチ対応）。
- **権限**: デプロイ手順（proxy 初期化）の一部。`_admin` に初期ロールを束縛する。
- **事前条件（Checks）**:
  - `_dToken` / `_treasury` / `_admin` が `address(0)` なら `ZeroAddress` で revert
  - `_dToken.code.length > 0`（EOA / 未デプロイアドレス不可）
  - `_underlying` のみ `address(0)` を**許容**する（プレースホルダー Vault）
  - `_underlying != address(0)` の即時 active deploy では、`_dToken.allowedUnderlying(_underlying) == true` を要求する
  - 多重初期化は不可（`initializer`）
- **動作（Effects）**:
  1. `_underlying`（placeholder 許容）/ `_dToken` / `_treasury` を束縛
  2. **初期ロール付与** — `_admin` に `DEFAULT_ADMIN_ROLE` / `GOV_ROLE` / `ALLOCATOR_ROLE` / `GUARDIAN_ROLE` / `WRITEOFF_ROLE` の **5 ロールを一括付与**（本番では `DEFAULT_ADMIN_ROLE` / `GOV_ROLE` を共通 TimelockController、`ALLOCATOR_ROLE` を `DF_ALLOCATOR`、`GUARDIAN_ROLE` を Guardian multisig、`WRITEOFF_ROLE` を高定足数 GOV multisig へ分離・移譲し deployer を全ロールから revoke する前提。デプロイ後のロール再配置を活性化手順に含める、[§4](#4-アクターロール信頼境界)・[VAULT-GOV-004](#vault-gov-004-timelock-と緊急-pause-の分離)）
  3. **デプロイ既定値**を設定（Day-1 値は [Parameters.md](../../../Parameters.md) を正本とし、活性化時に [VAULT-FR-012](#vault-fr-012-gov-設定-settersetbufferconfig--setallocatorconfig--setstrategyvaluationmaxage--setwithdrawdelay--settreasury) の setter で上書き）: `bufferTargetBps = 2000`（20%）／`bufferFloor = 0`／`allocateMaxMove = type(uint256).max`（無制限）／`allocatorCooldown = 0`／`strategyValuationMaxAge = 1 day`／`withdrawDelay = 1 day`／`nextRequestId = 1`。Day-1 deploy の `_treasury` は `DeployLiquity2` の必須 env `DF_TREASURY` で与え、未指定なら deploy は fail-fast する。handover/verify でも同じ `DF_TREASURY` と一致させる。
- **revert / 早期 return**: `_dToken` / `_treasury` / `_admin` がゼロ → `ZeroAddress`；`_dToken` が EOA / 未デプロイアドレス → `NotContract`；即時 active deploy で Underlying 未 allowlist → `UnderlyingNotAllowed`；再初期化 → revert。
- **発火イベント**: なし（Underlying の後付け確定は [VAULT-EVT-010](#11-イベント監視要件evt) `UnderlyingSet` で観測）。
- **設計上のポイント**: プレースホルダー状態（`underlying == address(0)`）の Vault は、`whenUnderlyingReady` ガードにより `deposit` / `redeem` / `redeemWithPermit` / `backstopDeposit` / `releaseBackstopToBuffer` がすべて revert し、資金の出入りができない（不活性）。view（`bufferBalance` / `backstopBalance` / `totalUnderlying`）は placeholder-safe（[VAULT-FR-013](#vault-fr-013-view-群bufferbalance--totalunderlying--strategy-列挙)）。
- **Verification**: unit（ゼロアドレス revert・再初期化 revert・既定値・5 ロール付与）, manual（デプロイ構成レビュー）。

### VAULT-FR-011: setUnderlying（後付け確定・一度限り）

- **Type**: Functional ｜ **Source**: Product-Overview「placeholder ブランチ」/ [dToken](./dToken.md) deferred-binding 整合
- **シグネチャ**: `setUnderlying(IERC20 _underlying)`
- **目的**: `underlying = address(0)` のプレースホルダー Vault に、後から **1 度だけ**本来の Underlying を確定する（Path-B プレースホルダーブランチ運用）。Vault↔dToken の Underlying 整合を強制し、別資産・別 decimals のサイレント誤評価を防ぐ。
- **権限**: GOV_MULTISIG（Vault の `GOV_ROLE`）のみ。
- **事前条件（Checks）**: `_underlying != address(0)`；`underlying == address(0)`（未確定）；`dToken.underlying() == _underlying`（dToken-first）；`dToken.allowedUnderlying(_underlying) == true`。
- **動作（Effects）**:
  1. **ゼロ検証** — `_underlying == address(0)` なら `ZeroAddress` で revert
  2. **一度きり検証** — `underlying != address(0)`（既に確定済み）なら `UnderlyingAlreadySet` で revert（上書き不可）
  3. **dToken 整合の即時検証** — `dToken.underlying() != _underlying` なら `UnderlyingMismatch` で revert（dToken が先に同一 Underlying へ確定済みであることを要求＝ **dToken-first 順序の強制**）
  4. **allowlist 検証** — `dToken.allowedUnderlying(_underlying) == false` なら `UnderlyingNotAllowed` で revert
  5. **確定** — `underlying = _underlying` を確定し、`UnderlyingSet(_underlying)` を発火
- **whenUnderlyingReady（利用時点の整合ガード）**: `deposit` / `redeem` / `redeemWithPermit` / `backstopDeposit` / `releaseBackstopToBuffer` に付与する modifier。各呼び出しの先頭で `underlying == address(0)` なら `UnderlyingNotSet`、`dToken.underlying() != underlying` なら `UnderlyingMismatch` で revert。利用時点でのチェックのため、**即時パス（`initialize` で underlying を確定）と遅延パス（`setUnderlying` で後付け）の双方を、活性化順序に依存せず**カバーする。即時パスで誤った Underlying を `initialize` に渡しても、`deposit` 時点でこのガードが `UnderlyingMismatch` で fail-closed にする。
- **revert / 早期 return**: `ZeroAddress` / `UnderlyingAlreadySet` / `UnderlyingMismatch` / `UnderlyingNotAllowed`。
- **発火イベント**: `UnderlyingSet(underlying)`（プレースホルダー Vault の Underlying を後付け確定したときに 1 度だけ発火、[VAULT-EVT-010](#11-イベント監視要件evt)）。
- **設計上のポイント**:
  - **なぜ必要か**: `deposit` は **Vault 側の `underlying`** を `safeTransferFrom` で受領する一方、mint 量は **dToken 側の decimals**（`convertToDToken`）で算出する。Underlying の確定が「Vault 側（`initialize` / `setUnderlying`）」と「dToken 側（`setTokenInfo`）」の **2 つの独立した一度きり setter** に分かれているため、両者に別資産・別 decimals を確定すると担保価値を**サイレントに誤評価**し、しかも両 setter は一度きりで**不可逆**になる（遅延パスだけでなく即時パスにも潜在）。したがって「Vault.underlying ≡ dToken.underlying」を**コードで強制**する（[VAULT-SEC-002](#vault-sec-002)）。
  - **アドレス一致 ⟹ decimals/評価一致 が成立する根拠**: `whenUnderlyingReady` / `setUnderlying` は Underlying の**アドレス一致のみ**を検証するが、これで decimals・換算倍率の一致まで保証される。理由は、dToken の `setTokenInfo`（[DTKN-FR-002](./dToken.md)）が `underlying` アドレスと換算倍率 `_decimalMultiplier = 10**(18 - underlyingDecimals)` を **同一トークン引数から一括で**確定し、かつ **一度きり**（再設定は revert）だからである。したがって `dToken.underlying() == underlying` が成立していれば、その倍率は必ずその Underlying の `decimals()` に対応する。
  - **安全制約**: `setUnderlying` は一度のみ成功（`UnderlyingAlreadySet`）。`setTokenInfo`（dToken 側、[DTKN-FR-002](./dToken.md)）も一度のみ。両者とも以後不変。活性化順序は **dToken-first**（`setTokenInfo` → `setUnderlying`）。逆順は `UnderlyingMismatch` で revert。
  - **活性化前に運用へ資金が流れない（多層防御）**: (1) `addStrategy` の **Underlying 不変条件**（[VAULT-FR-008](#vault-fr-008-strategy-whitelist登録解除addtowhitelist--removefromwhitelist--addstrategy--removestrategy)）で **placeholder には Strategy を登録できない**（`UnderlyingNotSet`）、(2) `deposit` / `backstopDeposit` / `releaseBackstopToBuffer` は `whenUnderlyingReady` で revert、(3) `bufferBalance()` / `backstopBalance()` / `totalUnderlying()` は `underlying == address(0)` を 0 として扱う（[VAULT-FR-013](#vault-fr-013-view-群bufferbalance--totalunderlying--strategy-列挙)）、(4) `allocate()` は `managedUnderlying() == 0` 相当で早期 return（[VAULT-FR-004](#vault-fr-004-allocatebuffer-余剰を-strategy-へ配分)）。これらの多層で、活性化前に運用へ資金が流れることはない。
  - **PriceFeed（第 3 の資産）**: ブランチの PriceFeed は Vault / dToken と一致すべき「第 3 の資産」。placeholder 有効化中は実 PriceFeed の `confirmSourceEmergency()` 完了まで cap を 0 に維持し、最後に `dToken.setCap(N)` で新規 mint を解放する（[DTKN-FR-002](./dToken.md) / [DTKN-FR-006](./dToken.md) / [Oracle 要件定義](./Oracle.md)）。通常 source 差替で新旧価格差が 1% 以内なら `confirmSource()` を使うが、placeholder sentinel から実価格への差替は価格差 guard を越えるため emergency 経路を使う。配線は Path-B の deploy 工程で扱う（本要件のスコープ外）。
  - **活性化ランブック（placeholder → active の完全手順）**: 順序が重要で、逆順は各ガードが revert で弾く。
    1. **Underlying allowlist** — `dToken.setAllowedUnderlying(WBTC, true)`（canonical token address を事前レビュー）
    2. **dToken 確定** — `dToken.setTokenInfo("dWBTC", "dWBTC", WBTC)`（dToken-first、[DTKN-FR-002](./dToken.md)）
    3. **Vault 確定** — `vault.setUnderlying(WBTC)`（`dToken.underlying() == WBTC` と allowlist を検証して成功。逆順なら `UnderlyingMismatch`）
    4. **PriceFeed 確定** — ブランチの実 PriceFeed で `confirmSourceEmergency()` 完了（[Oracle 要件定義](./Oracle.md)）。完了まで cap は 0 のまま
    5. **Strategy ホワイトリスト** — `vault.addToWhitelist(strategy)`（contract-only、[VAULT-FR-008](#vault-fr-008-strategy-whitelist登録解除addtowhitelist--removefromwhitelist--addstrategy--removestrategy)）
    6. **Strategy 登録** — `vault.addStrategy(strategy, weightBps, cap)`。Underlying 不変条件により **手順 3（`setUnderlying`）より前には成功しない**（placeholder では `UnderlyingNotSet`、別資産 Strategy なら `UnderlyingMismatch`）
    7. **buffer / allocator パラメータ** — `setBufferConfig` / `setAllocatorConfig` 等を [Parameters.md](../../../Parameters.md) の Day-1 値で設定
    8. **mint 解放** — 最後に `dToken.setCap(N)` で新規 deposit を解放（多層不活性の最後の層を cap に統一。配線完了まで資金流入を止める）
    - 換算例: 手順 1〜2 完了後、user が `vault.deposit(5e8)`（5 WBTC, 8dec）→ `convertToDToken(5e8) = 5e8 * 10**(18-8) = 5e18`（5 dWBTC, 18dec）を mint。
- **Verification**: unit（ゼロ・一度きり・dToken-first・`whenUnderlyingReady` の双方向ガード）, invariant=[VAULT-INV-010](#vault-inv-010), manual（活性化ランブックの順序）。

### VAULT-FR-012: GOV 設定 setter（setBufferConfig / setAllocatorConfig / setStrategyValuationMaxAge / setWithdrawDelay / setTreasury）

- **Type**: Functional ｜ **Source**: 運用パラメータ管理 / [Parameters.md](../../../Parameters.md)
- **シグネチャ**: `setBufferConfig(uint256 _targetBps, uint256 _floor)` / `setAllocatorConfig(uint256 _maxMove, uint256 _cooldown)` / `setStrategyValuationMaxAge(uint256 _maxAge)` / `setWithdrawDelay(uint256 _delay)` / `setTreasury(address _treasury)`
- **目的**: Vault の運用パラメータと収益送付先を GOV が更新する。担保別の Day-1 具体値は [Parameters.md](../../../Parameters.md) を正本とし、本要件は各 setter のシグネチャ・検証・既定挙動を定義する。
- **権限**: 各 setter は GOV_MULTISIG（Vault `GOV_ROLE`）のみ。
- **事前条件・動作**:
  - **setBufferConfig（buffer 方針の更新）**:
    1. **上限検証** — `_targetBps > 10000` なら `InvalidBufferConfig` で revert（比率は BPS で `<= 100%`）
    2. **確定** — `bufferTargetBps = _targetBps`、`bufferFloor = _floor`（`bufferFloor` は絶対量で上限検証はしない）。更新値は次回 `allocate()`（[VAULT-FR-004](#vault-fr-004-allocatebuffer-余剰を-strategy-へ配分)）の目標バッファ算出に即時反映
  - **setAllocatorConfig（allocator ガードレールの更新）**:
    - `allocateMaxMove = _maxMove`（`allocate()` 1 回あたりの buffer→Strategy 移動上限）、`allocatorCooldown = _cooldown`（`allocate()` の最小実行間隔秒数）を更新。**バリデーションなし**。`allocatorCooldown = 0` はクールダウン無効、`allocateMaxMove = 0` は outbound allocation 停止、`allocateMaxMove = type(uint256).max` は実質的な移動上限なしを意味する。いずれも `allocate()` のみに適用され、`Strategy.sendToVault`（元本回収）には適用しない（[§9](#9-セキュリティ要件sec)）
  - **setStrategyValuationMaxAge（valuation cache TTL の更新）**:
    - `strategyValuationMaxAge = _maxAge` を更新。`_maxAge = 0` は valuation failure 時の cache fallback を無効化し、live read failure は即 0 評価に戻す。上限検証は持たず、activation package と verified manifest で設定値を管理する
  - **setWithdrawDelay（遅延償還の待機期間）**:
    - `withdrawDelay = _delay` を更新（秒、redeem 不足時に発行する `WithdrawRequest` の待機期間、[VAULT-FR-006](#vault-fr-006-claimwithdrawrequest-の遅延償還受領)）。**`_delay > 30 days` なら `InvalidBufferConfig` で revert**（上限 30 days）。変更は **以後発行される request の `claimableAt` にのみ**適用され、既発行 request の待機時刻は変わらない。既定値は `1 day`（[VAULT-FR-010](#vault-fr-010-initializeプレースホルダー化proxy-初期化)）
  - **setTreasury（収益送付先の更新）**:
    1. **ゼロ検証** — `_treasury == address(0)` なら `ZeroAddress` で revert
    2. **確定** — `treasury = _treasury`
- **revert / 早期 return**: `setBufferConfig`（`_targetBps > 10000`）/ `setWithdrawDelay`（`_delay > 30 days`）: `InvalidBufferConfig`。`setTreasury`: `ZeroAddress`。`setAllocatorConfig` / `setStrategyValuationMaxAge`: 上限・バリデーションなし（非 GOV のみ revert）。
- **発火イベント**: setter はそれぞれ `BufferConfigUpdated(oldTargetBps, newTargetBps, oldFloor, newFloor)` / `AllocatorConfigUpdated(oldMaxMove, newMaxMove, oldCooldown, newCooldown)` / `StrategyValuationMaxAgeUpdated(oldMaxAge, newMaxAge)` / `WithdrawDelayUpdated(oldDelay, newDelay)` / `TreasuryUpdated(oldTreasury, newTreasury)` を発火する。監視はイベントを正本にし、対応する view（`bufferTargetBps` / `bufferFloor` / `allocateMaxMove` / `allocatorCooldown` / `strategyValuationMaxAge` / `withdrawDelay` / `treasury`）で反映後状態を確認する（[VAULT-EVT-011](#11-イベント監視要件evt)）。
- **設計上のポイント**:
  - **treasury は GOV により可変**だが、**ALLOCATOR からは変更できない**。`transferYieldToTreasury` は常に現在の `treasury` へのみ送るため、ALLOCATOR 鍵が侵害されても送付先を任意アドレスへ振り替えることはできない（[§9](#9-セキュリティ要件sec) / [VAULT-SEC-005](#vault-sec-005)）。「固定 Treasury」とは **ALLOCATOR から見た固定**を指す。
  - treasury の変更は GOV_MULTISIG の承認を要する重要操作であり、`TreasuryUpdated` を監視対象にする。
- **Verification**: unit（GOV 限定・`InvalidBufferConfig` / `ZeroAddress`・即時反映・既発行 request 不変・valuation cache TTL 更新）。

### <a id="vault-fr-013-view-群bufferbalance--totalunderlying--strategy-列挙"></a>VAULT-FR-013: View 群（bufferBalance / backstopBalance / totalUnderlying / Strategy 列挙）

- **Type**: Functional ｜ **Source**: 監視・subgraph・フロント
- **シグネチャ**: `bufferBalance() → uint256` / `backstopBalance() → uint256` / `totalUnderlying() → uint256` / `strategyValuationMaxAge() → uint256` / `strategyValuationCaches(IStrategy) → (uint256 conservativeValue, uint256 updatedAt, bool initialized)` / `getStrategiesCount() → uint256` / `getStrategyAt(uint256) → (IStrategy, StrategyConfig)` / `getAllStrategies() → (IStrategy[], StrategyConfig[], uint256[])` / `getStrategyStatuses() → StrategyStatus[]`（view は external view・permissionless）/ `refreshStrategyValuation(IStrategy) → bool`（external・permissionless）/ `invalidateStrategyValuationCache(IStrategy)`（external・GOV_ROLE）
- **目的**: 監視・subgraph・フロントが Vault 状態を読むための view 群、および keeper/GOV が Strategy valuation cache を管理するための補助関数群。
- **権限**: view は permissionless。`refreshStrategyValuation` は permissionless（呼び出し者が gas を負担して live 値を cache へ記録するだけ）。`invalidateStrategyValuationCache` は GOV_ROLE。
- **事前条件（Checks）**: view getter は原則なし（`getStrategyAt` のみ範囲チェック）。`refreshStrategyValuation` / `invalidateStrategyValuationCache` は対象が登録 Strategy であること。
- **動作（Effects）**:
  - `bufferBalance()` — Vault が現に保有する Underlying のうち、redeem / claim / allocate / Treasury 送付に使える liquid buffer 残高（`max(underlying.balanceOf(address(this)) - _backstopReserve, 0)`）。**placeholder-safe**: `underlying == address(0)` のとき 0 を返す（[VAULT-FR-011](#vault-fr-011-setunderlying後付け確定一度限り)）
  - `backstopBalance()` — protected backstop reserve の live 残高（`min(_backstopReserve, underlying.balanceOf(address(this)))`）。`backstopDeposit` で増え、`releaseBackstopToBuffer` で減る。placeholder では 0
  - `totalUnderlying()` — Vault raw Underlying balance（liquid buffer + backstop reserve）＋ 各登録 Strategy の保守評価合計（通常は `underlying.balanceOf(vault) + Σ min(estimatedTotalUnderlying_i, principal_i)`、[§7](#7-状態変数会計モデル)）。Strategy 未登録時は Vault raw Underlying balance に等しい。Strategy の `estimatedTotalUnderlying()` または `principal()` が revert した場合は、`strategyValuationMaxAge` 内の fresh cache があればその `cachedConservativeValue` を使い、cache が missing/stale/無効（TTL=0）の場合は 0 評価する
  - `strategyValuationMaxAge()` — valuation failure 時に last-good cache を使える最大経過時間。既定は 1 days、GOV が `setStrategyValuationMaxAge` で変更でき、0 にすると fallback を無効化する
  - `strategyValuationCaches(strategy)` — 直近に成功した `min(est, principal)` の cache（`conservativeValue` / `updatedAt` / `initialized`）。`addStrategy` / `allocate` / `writeoffStrategyPrincipal` / `refreshStrategyValuation` で更新される。`allocate` は投下前に読めた live `min(est, principal)` を基準にし、post-deposit refresh が失敗した場合でも「投下前 live 保守値 + Vault から Strategy へ移動した既知 outflow」で cache を seed する。古い/stale cache へ単純加算して fresh 化してはならない。`receiveFromStrategy` は exact delivery なら実着額分を減額し、declared/received mismatch なら無効化する
  - `getStrategiesCount()` — 登録 Strategy 数（`strategies.length`）
  - `getStrategyAt(_index)` — `_index` 番目の Strategy とその `StrategyConfig{ enabled, weightBps, cap }`。`_index >= strategies.length` なら **`StrategyNotFound`（カスタムエラー）で revert**
  - `getAllStrategies()` — 全登録 Strategy・各 `StrategyConfig`・各残高を 3 つの整列配列で一括返却。`_balances[i]` は読める場合は **各 Strategy の `estimatedTotalUnderlying()` 生値**、読めない場合は 0（`principal` との `min` クランプは掛けない）
  - `getStrategyStatuses()` — 全登録 Strategy の fail-soft snapshot を返す。各要素は `strategy` / `config` / `estimatedUnderlying` / `principal` / `conservativeValue` / `cachedConservativeValue` / `cacheUpdatedAt` / `estimatedGain` / `estimatedLoss` / `capRemaining` / `estimateAvailable` / `principalAvailable` / `usingCachedConservativeValue` / `cacheAvailable` / `cacheStale` を含む。live `estimatedTotalUnderlying()` と `principal()` が両方読める場合は `conservativeValue = min(est, principal)` と推定損益を表示する。どちらかが revert した場合、読めない field は 0、対応する `...Available` は `false`、fresh cache がある場合のみ `conservativeValue` に cache 値を入れて `usingCachedConservativeValue = true` とする。cache が stale/missing の場合は保守評価 0
  - `refreshStrategyValuation(strategy)` — 登録 Strategy の live `estimatedTotalUnderlying()` と `principal()` を読み、両方成功した場合に `min(est, principal)` を cache へ保存して `true` を返す。どちらかが失敗した場合は cache を変更せず `false` を返す
  - `invalidateStrategyValuationCache(strategy)` — GOV が登録 Strategy の cache を破棄する。外部プロトコル緊急回収や direct emergency transfer 後など、cache が二重計上を生み得る場合の明示リセット経路
- **revert / 早期 return**: `getStrategyAt`: `_index >= strategies.length` → `StrategyNotFound`。`getAllStrategies()` は raw `estimatedTotalUnderlying()` を fail-soft に読み、Strategy 側の estimate view が revert する場合は当該残高を 0 として返す。`getStrategyStatuses()` は fail-soft で snapshot 全体を revert させない。`refreshStrategyValuation` / `invalidateStrategyValuationCache` は未登録 Strategy に対して `StrategyNotFound`。
- **発火イベント**: `StrategyValuationMaxAgeUpdated`。cache の更新・破棄・refresh failure・保守的な減額は view/status と cache getter で検知する。
- **設計上のポイント**:
  - **placeholder-safe の根拠**: balance view を素朴に実装すると `underlying == address(0)` で `address(0)` への呼び出しが revert し、それを呼ぶ `totalUnderlying()` / `allocate()` / `transferYieldToTreasury()` も連鎖 revert する。fail-closed ではあるが、subgraph / 監視がplaceholderブランチ（Day1の対象と採用状態は [Mainnet Launch Product Decision Record](../../launch/decisions/Mainnet-Launch-Product-Decision-Record.md)、`mintCap = 0`は [Day1 Parameter Manifest](../../../Parameters.md) を正本とする）をviewしただけで壊れる。したがって `bufferBalance()` / `backstopBalance()` / `totalUnderlying()` は `underlying == address(0)` のとき 0 を返す（資金移動は Underlying 不変条件・`whenUnderlyingReady`・cap=0 で別途封じられているため、view が 0 を返しても不活性は保たれる）。
  - **Strategy valuation bounded last-good**: `totalUnderlying()` は live valuation が読める限り必ず live `min(est, principal)` を使う。valuation view が revert した場合だけ、`strategyValuationMaxAge` 内の last-good conservative cache を一時的に使い、cache が stale/missing/無効なら 0 評価する。これにより一時的な外部 view failure が全 Trove の即時誤清算に直結する経路を抑えつつ、cache の永久利用による過大評価を避ける。
  - **known flow による cache 連続性**: `allocate` は Strategy への deposit 後に live refresh を試みる。refresh が失敗した場合でも、Vault raw balance から出た既知 outflow 分を cache に増分反映し、`raw balance` だけが減って backing が一時的に過小評価されることを防ぐ。live valuation が復旧すれば live `min(est, principal)` が常に優先される。
  - **cache 二重計上防止**: `receiveFromStrategy` は exact delivery なら Strategy から Vault に戻った実着額分だけ cache を減額し、declared/received mismatch なら cache を無効化する。receipt と upstream position 減少が一致するか不明な fee-on-transfer / rebase 異常時に fresh cache を推測で残さない。対象は元本返却・固有緊急回収・汎用 idle 救済など cache reconciliation が必要な経路であり、`sendProfitToVault` / Underlying reward claim の yield-only push は本関数を通らず Vault buffer へ直接入る。`writeoffStrategyPrincipal` は writeoff 後に refresh を試み、失敗時は cache を writeoff 分だけ減額する。`removeStrategy` は cache を破棄する。
  - **`getAllStrategies` の `_balances` は生値または 0**: 読める場合は `estimatedTotalUnderlying()` の生値、estimate read が失敗する場合は 0 を返す。ソルベンシー評価に用いる `min(est, principal)`（[§7](#7-状態変数会計モデル)）とは異なる。`principal` との乖離（プラス＝未実現収益、マイナス＝元本毀損のシグナル、[§11](#11-イベント監視要件evt)）を見るには Strategy 側 `principal()` を併せて参照する。availability flag・principal・cache・保守評価の文脈が必要な監視では `getStrategyStatuses()` を使う。
  - **`getStrategyStatuses` は運用確認用の集約 view**: Strategy valuation view の revert を snapshot 全体の revert にしない。`getAllStrategies()` と異なり、read availability・cache status・保守評価 field を公開する。`estimatedGain` は推定値と principal の差分であり、実際に回収・送付できる利益の証明ではない。外部プロトコル損失が Strategy の推定値に現れない場合は、この view だけでは自動判定できず、GOV の回収・writeoff・backstop 運用に依存する。
  - **列挙の「登録」定義**: Strategy 列挙 view は **`strategies[]` 配列メンバーシップ**を返す（`enabled` か、無効化済みで `strategies[]` に残存するかを問わず、`removeStrategy` まで現れる）。これは受入口 `receiveFromStrategy`（[VAULT-FR-005](#vault-fr-005-receivefromstrategystrategy--vault-の-push-受入)）／ `writeoffStrategyPrincipal`（[VAULT-FR-009](#vault-fr-009-updatestrategy--writeoffstrategyprincipal登録-strategy-の調整と元本毀損確定)）が用いる「登録」判定と同一の定義。
- **Verification**: unit（placeholder で 0 返却・index out of bounds・`getAllStrategies` fail-soft・生値 vs min・status fail-soft・推定損益・fresh cache fallback・TTL expiry・allocation 後 refresh failure 時の cache 増分・cache 減額）, manual（subgraph/keeper 連携）。

### VAULT-FR-014: Pause / Unpause（緊急停止）

- **Type**: Functional ｜ **Source**: 緊急対応 / incident response ／ 2026-06-12 ガバナンス設計確定（[protocol/product/policies/Governance-Roles-Timelock.md](../policies/Governance-Roles-Timelock.md)）
- **シグネチャ**: `pauseDeposit()` / `unpauseDeposit()` / `pauseRedeem()` / `unpauseRedeem()` / `pauseClaim()` / `unpauseClaim()` / `pauseAllocation()` / `unpauseAllocation()`
- **目的**: deposit（mint）・redeem・claim・allocation を**独立 4 フラグ**で緊急停止する。pause（停止）は迅速性を優先して `GUARDIAN_ROLE`、unpause（再開）は `GOV_ROLE`（holder = 共通 Timelock）のみに分離する（誤・悪意の再開を防ぐ非対称設計。「ブレーキは引きやすく、戻すのは遅い」）。
- **権限**: pause は `GUARDIAN_ROLE`（`initialize` 既定では `_admin` も保有）／ unpause は `GOV_ROLE` のみ。
- **事前条件（Checks）**: pause は `caller` が `GUARDIAN_ROLE` 保有；unpause は `caller` が `GOV_ROLE` 保有。
- **動作（Effects）**:
  - `pauseDeposit()` — `pausedDeposit = true`、`DepositPaused()` 発火。`deposit` が `Paused` で revert（[VAULT-FR-001](#vault-fr-001-depositunderlying--dtoken)）
  - `pauseRedeem()` — `pausedRedeem = true`、`RedeemPaused()` 発火。`redeem` / `redeemWithPermit` が `Paused` で revert（[VAULT-FR-002](#vault-fr-002-redeemdtoken--underlying) / [VAULT-FR-003](#vault-fr-003-redeemwithpermitpermit-経由の-redeem)）
  - `pauseClaim()` — `pausedClaim = true`、`ClaimPaused()` 発火。`claim` が `Paused` で revert（[VAULT-FR-006](#vault-fr-006-claimwithdrawrequest-の遅延償還受領)）
  - `pauseAllocation()` — `pausedAllocation = true`、`AllocationPaused()` 発火。`allocate()` と `transferYieldToTreasury()` が `whenNotPausedAllocation` で revert（[VAULT-FR-004](#vault-fr-004-allocatebuffer-余剰を-strategy-へ配分) / [VAULT-FR-007](#vault-fr-007-transferyieldtotreasury収益の-treasury-送付)）。**`Strategy.sendToVault`（元本回収）・`Strategy.sendProfitToVault`（収益の Vault への引き上げ）は対象外**（資金を Vault buffer へ戻す安全側の操作のため、[§9](#9-セキュリティ要件sec)）
  - `unpauseDeposit()` / `unpauseRedeem()` / `unpauseClaim()` / `unpauseAllocation()`（`GOV_ROLE`）— 各フラグを false に戻し、対応する `*Unpaused()` を発火
- **revert / 早期 return**: pause: 非 GUARDIAN → revert。unpause: 非 GOV → revert。
- **発火イベント**: `DepositPaused()` / `DepositUnpaused()` / `RedeemPaused()` / `RedeemUnpaused()` / `ClaimPaused()` / `ClaimUnpaused()` / `AllocationPaused()` / `AllocationUnpaused()`（[VAULT-EVT-012](#11-イベント監視要件evt)）。
- **設計上のポイント**:
  - **分離停止の理由（シナリオで必要な操作が異なる）**: ① 担保のペグ・デペグ等で**新規流入だけ**止め、保有者の脱出（redeem）は開けておきたい局面 → `pauseDeposit` のみ（旧 `pauseMintRedeem` の両停止では脱出を不当に塞ぐ）。② Strategy 実損（A < L_effective）では dToken redeem / claim が 1:1（backingRatio ヘアカットなし）のまま有限の buffer を先着で奪い合う取り付けになる → `pauseRedeem` ＋ `pauseClaim` で freeze し、`backstopDeposit` → `releaseBackstopToBuffer`（[VAULT-FR-017](#vault-fr-017-backstopdepositdtoken-を-mint-しない補填入金)）で A ≥ L を回復してから resume する（equitable repair。全体方針は[Architecture Decision Records](../architecture/Architecture-Decision-Records.md#adr-006)）。
  - **claim を停止対象に加える理由（従来仕様の意図的変更）**: `pendingWithdrawals` は allocate からの保護（[VAULT-FR-004](#vault-fr-004-allocatebuffer-余剰を-strategy-へ配分)）であり、redeem 即時払いと既存 vested claim の buffer 先着レースは止めない。`pauseRedeem` 単独では vested claim が repair 窓の buffer を抜く穴が残り、queue 位置のくじ引きで損失分担が決まる不公平を許してしまう。完全 freeze には `pauseClaim` が必要。
  - **代償（明示）**: 確定債務（vested claim）を governance が凍結可能になり、非カストディアル性を一段弱める。緩和は ① GUARDIAN はマルチシグ ② 停止は保守方向 ③ unpause は GOV=Timelock。**`unpauseClaim` も共通 Timelock の待機対象であり、誤報での claim 凍結は同 delay 中継続する**ため、GUARDIAN は claim 停止を高確信時のみ発動する運用前提とする。また、freeze 中も 🔵 Core の Redemption・清算は停止しない（コア無改変）ため、redeemer は dXXX を受領しても Vault 出口の凍結中は Underlying へ換金できず、JPYdf の Redemption 裁定の実効性が一時的に低下する（ペグ防衛の弱まり）——この副作用も repair 窓を短く保つ運用前提に含める。
  - 4 フラグ独立により「deposit だけ再開し redeem は据え置き」等の選択的復旧が可能。緊急時の段階的回収は allocation のみ停止して redeem 用 buffer 補充を継続する（[§12](#12-失敗時異常系挙動err)）。
  - `initialize` は `_admin`（GOV）に `GUARDIAN_ROLE` も付与するため既定では `_admin` も pause できるが、本番では Guardian multisig へ分離することを前提とする（[§4](#4-アクターロール信頼境界)）。
- **Verification**: unit（pause は GUARDIAN・unpause は GOV・4 フラグ独立・claim の停止/再開・sendToVault/sendProfitToVault は対象外・transferYieldToTreasury は停止対象）。

### VAULT-FR-015: アップグレード（UUPS）

- **Type**: Functional ｜ **Source**: Product-Overview「dToken Layer (UUPS)」
- **シグネチャ**: `_authorizeUpgrade(address newImpl)`（internal・UUPS authorization）
- **目的**: UUPS でロジック差替により Vault の保管・会計・配分・償還等の挙動を将来修正できるようにする。Vault 側の機能更新は本アップグレードで行い、dToken の `vault` 参照先は変えない（[DTKN-FR-001](./dToken.md) の `vault` 不変性）。
- **権限**: 新実装の承認は **GOV_MULTISIG（Vault `GOV_ROLE`・holder = Timelock）のみ**。運用ロール（ALLOCATOR / GUARDIAN / WRITEOFF / Strategy 等）は不可。
- **事前条件（Checks）**: `caller` が `GOV_ROLE` 保有。
- **動作（Effects）**:
  1. 実装アドレスを差替（UUPS）。ストレージは追記のみ（既存スロットの並べ替え・型変更をしない。gap で将来分を予約）
  2. ERC1967 `Upgraded(newImpl)` を発火
  3. pre-cache 実装から upgrade した既存 proxy では、`strategyValuationMaxAge` は storage default の 0（fallback 無効）から始まる。GOV は `setStrategyValuationMaxAge(nonZeroMaxAge)` で明示的に有効化する
- **revert / 早期 return**: 非 GOV → revert。
- **発火イベント**: ERC1967 `Upgraded(newImpl)`（[VAULT-EVT-013](#11-イベント監視要件evt)）。
- **設計上のポイント**: UUPS upgrade 自体に内蔵 delay はない。**mainnet では `GOV_ROLE` / `DEFAULT_ADMIN_ROLE` の holder を共通 TimelockController のみにし、upgrade を含む全 GOV 操作へ公示遅延を掛ける（[VAULT-GOV-004](#vault-gov-004-timelock-と緊急-pause-の分離)）**。Oracle PriceFeedProxy の feed source 差替待機時間は [Oracle 要件定義](./Oracle.md) を正本とする。
- **Verification**: unit（GOV 限定承認・運用ロール revert）, manual（storage layout review・gap 確保）。

### VAULT-FR-016: backingRatio（dToken 裏付け率の供給）

- **Type**: Functional ｜ **Source**: [Oracle 要件定義](./Oracle.md) `ORCL-FR-014`（dToken backing peg）/ 本書 §7 会計原則（`A` vs `L_effective`）
- **シグネチャ**: `backingRatio() → uint256`（external view、1e18 基準・**下方専用** `<= 1e18`）/ `backingRatioForPricing() → (uint256 ratio, bool available)`
- **目的**: dToken の **裏付け率**（実保有 Underlying ÷ 元本請求権）を 1e18 基準で返す read-only view。Oracle Layer（各 DF PriceFeed 実装内の backing 乗算層、[Oracle 要件定義](./Oracle.md) `ORCL-FR-014`）が market price に乗じ、Strategy 毀損時の dToken デペグを担保価値へ反映するために参照する。**価値の会計はすべて本 Vault 側で完結**し、オラクルは比率を読むだけ。
- **権限**: なし（external view、permissionless）。
- **事前条件（Checks）**: なし（placeholder / 供給ゼロは下記で `1e18` を返す）。
- **動作（Effects）**:
  1. `L_effective = actualLiabilities()`（§7 会計原則の `L_user + L_pending`。dToken 総供給 dust がある場合は Underlying 1 base unit へ切り上げ）
  2. `L_effective == 0` なら `1e18` を返す（placeholder / 供給ゼロ、0 除算回避）
  3. それ以外: `A = totalUnderlying()`（Vault raw Underlying balance + Σ live `min(est, principal)`、Strategy valuation failure 時は fresh cache、stale/missing/無効 cache は 0）を用い `min(1e18, A * 1e18 / L_effective)` を返す
  4. `backingRatioForPricing()` は同じ合計と比率を用いるが、登録 Strategy の live valuation と fresh cache がどちらも無い場合は `(0, false)` を返す。全 Strategy を評価できた実測 0 は `(0, true)` として区別する。`L_effective == 0` は `(1e18, true)`
- **revert / 早期 return**: `L_effective == 0` → `1e18`。それ以外は常に算出値（view・revert しない設計。Strategy valuation failure は `totalUnderlying()` 側で bounded last-good または 0 評価）。
- **発火イベント**: なし（view）。
- **設計上のポイント**:
  - **`VAULT-INV-001` と直接対応**: `backingRatio == 1e18 ⟺ A >= L_effective`（健全）。`A < L_effective`（元本毀損）のとき `1e18` 未満を返し、毀損率がそのまま下方率になる。
  - **上振れキャップ（`min(1e18, …)`）**: 運用益で `A > L_effective` でも `1e18` 止まり。dToken が元本 1:1 請求権で利回りを持たない（運用益は Treasury 帰属）仕様と整合し、未実現益を担保価値へ膨らませない。
  - **pari passu（設計 B）**: pending（既 redeem 確定）と現存 dToken を `L_effective` で**同率評価**する（pending を優先弁済として現存 dToken から差し引く設計ではない）。`claim` の満額弁済は buffer 次第のため、深刻時は pending も実質減価しうる前提と整合する。
  - **operational / pricing の分離**: `backingRatio()` は監視・incident のため常に数値を返し、評価不能 Strategy を 0 とする保守挙動を維持する。`backingRatioForPricing()` は同じ数値に availability を添え、評価不能を実損 0 と混同しない。Oracle は `available == false` を standard oracle failure として扱う。ただし損失が est に未反映／`writeoffStrategyPrincipal` 遅延／fresh cache 期間中の実毀損では `A` が過大評価され backing も過大になりうる点は残る。
  - **placeholder-safe**: `totalSupply() == 0` かつ `pendingWithdrawals == 0` の placeholder では `L_effective == 0` → `1e18`。Oracle 側の `PriceFeedPlaceholder`（`(1e18, false)`）と矛盾しない。
- **Verification**: unit（`L_effective==0` で `1e18`・`min` キャップ・毀損時 `1e18` 未満・floor）, fork（実 Strategy 毀損での低下）, invariant=[VAULT-INV-012](#vault-inv-012)。

### VAULT-FR-017: backstopDeposit（dToken を mint しない補填入金）

- **Type**: Functional ｜ **Source**: dToken backing 毀損時の救済方針（SP 補填なし・Vault/backstop 補填）
- **シグネチャ**:
  - `backstopDeposit(uint256 _underlyingAmount) returns (uint256 received)`（external, permissionless, `whenUnderlyingReady`, `nonReentrant`）
  - `releaseBackstopToBuffer(uint256 _amount) returns (uint256 released)`（external, `GOV_ROLE`, `whenUnderlyingReady`）
- **目的**: Treasury・保険口座・任意の backstop から Underlying を protected reserve として注入し、dToken を新規 mint せずに `A = totalUnderlying()` と `backingRatio()` を回復させる。これは Strategy 回収・writeoff 後に残る不足を補う repair path であり、Liquity Stability Pool に Vault 損失を負わせないための明示経路である。入金された reserve は通常 redeem / claim の先着順では消費できず、GOV が明示的に `releaseBackstopToBuffer` した分だけ liquid buffer になる。
- **権限**: `backstopDeposit` はなし（permissionless）。想定 caller は Treasury / insurance / backstop multisig だが、第三者 donation も Vault solvency を改善するだけなので許容する。`releaseBackstopToBuffer` は GOV_MULTISIG のみ。
- **事前条件（Checks）**: `whenUnderlyingReady`；`backstopDeposit`: `_underlyingAmount != 0`。`releaseBackstopToBuffer`: `_amount != 0` かつ `_amount <= backstopBalance()`。
- **動作（Effects）**:
  1. 入力検証（`_underlyingAmount == 0` / `_amount == 0` → `ZeroAmount`）
  2. `backstopDeposit` は受領前の Vault raw underlying balance を記録
  3. `msg.sender` から `safeTransferFrom` で `_underlyingAmount` を Vault に取り込む
  4. 受領後残高との差分を `received` として確定する（declared amount ではなく実着額）
  5. `backstopDeposit` は `_backstopReserve += received` として reserve 会計を増やし、`BackstopDeposited(msg.sender, _underlyingAmount, received)` を発火し `received` を返す
  6. `releaseBackstopToBuffer` は `_backstopReserve -= _amount` として reserve 会計を減らし、同じ Underlying を liquid buffer として扱えるようにし、`BackstopReleased(msg.sender, _amount)` を発火し `_amount` を返す（実 ERC-20 transfer は発生しない）
- **revert / 早期 return**: Vault Underlying 未設定 → `UnderlyingNotSet`；Vault/dToken 不一致 → `UnderlyingMismatch`；`_underlyingAmount == 0` / `_amount == 0` または実着額 `received == 0` → `ZeroAmount`；`releaseBackstopToBuffer` の `_amount > backstopBalance()` → `InsufficientBackstop`；`safeTransferFrom` 失敗（残高・許可不足）→ 上流 revert。
- **発火イベント**: `BackstopDeposited(backstop, declaredAmount, received)` / `BackstopReleased(caller, amount)`（[VAULT-EVT-014](#11-イベント監視要件evt) / [VAULT-EVT-015](#11-イベント監視要件evt)）。
- **設計上のポイント**:
  - **dToken を mint しない**: deposit と異なり `dToken.mint` を呼ばない。既存 dToken / pending 請求権の裏付けだけを厚くする。
  - **pause 対象外**: `pausedDeposit` / `pausedRedeem` / `pausedClaim` / `pausedAllocation` のいずれの影響も受けない。停止中でも補填だけは継続できる（repair freeze 中の backstop 注入を可能にする）。
  - **buffer ではなく reserve に積む**: 補填は現物 Underlying として Vault に残るが、`bufferBalance()` から除外される。`redeem` / `claim` / `allocate` / `transferYieldToTreasury` は liquid buffer しか使えないため、Strategy 毀損時の補填原資が通常 redeem の先着順や Treasury sweep で抜かれない。
  - **明示 release**: `releaseBackstopToBuffer` は資金移動ではなく会計移動で、reserve を liquid buffer に戻す。pending claim を実際に支払う、または通常 redeem liquidity として使わせる判断は GOV の incident runbook で行う（全体方針は[Architecture Decision Records](../architecture/Architecture-Decision-Records.md#adr-006)）。
  - **実着額計上**: `receiveFromStrategy` と同様に残高差分で `received` を決め、fee-on-transfer / rebasing 異常時に過大計上しない。
  - **SP とは別責務**: Stability Pool は Oracle 価格低下後の Trove 清算を処理するだけで、Vault に Underlying を補填しない。backing repair は Strategy 回収・writeoff・本関数の組み合わせで Vault 側に閉じる。補填前の必要額確認は [VAULT-FR-018](#vault-fr-018-backing-ops-views補填運用補助) の view 群を使う。
- **Verification**: unit（ready/zero/transfer failure・実着額計上・mint 不発火・buffer 不使用・GOV release）, invariant=[VAULT-INV-013](#vault-inv-013), integration（毀損→backstopDeposit→`backingRatio` 回復→release→pending claim 可能）。

### VAULT-FR-018: backing ops views（補填運用補助）

- **Type**: Functional ｜ **Source**: [VAULT-FR-016](#vault-fr-016-backingratiodtoken-裏付け率の供給) / [VAULT-FR-017](#vault-fr-017-backstopdepositdtoken-を-mint-しない補填入金) / backing repair runbook
- **シグネチャ**:
  - `actualLiabilities() → uint256`（external view）
  - `backingShortfall() → uint256`（external view）
  - `backstopRequiredForRatio(uint256 _targetRatio) → uint256`（external view、`_targetRatio` は 1e18 基準）
- **目的**: dToken backing 毀損時に、off-chain runbook / keeper / governance が **現在の実効負債・100% backing までの不足額・目標 backing 比率までの補填必要額**を同じ会計式で読めるようにする。状態は変えず、Oracle が読む canonical 値は引き続き `backingRatio()`。
- **権限**: なし（external view、permissionless）。
- **事前条件（Checks）**: `backstopRequiredForRatio` は `_targetRatio <= 1e18`。`actualLiabilities` / `backingShortfall` は入力なし。
- **動作（Effects）**:
  1. `actualLiabilities()` は `L_effective = L_user + pendingWithdrawals` を返す。`L_user` は `convertToUnderlying(dToken.totalSupply())` を基本とし、dToken 総供給が Underlying base unit に exact 対応しない dust を含む場合は 1 base unit へ切り上げる
  2. `backingShortfall()` は `A = totalUnderlying()` と `L_effective` から `max(L_effective - A, 0)` を返す
  3. `backstopRequiredForRatio(_targetRatio)` は `_targetRatio == 0` または `L_effective == 0` なら `0` を返す
  4. それ以外は `requiredAssets = ceil(L_effective * _targetRatio / 1e18)` を計算し、`max(requiredAssets - A, 0)` を返す
- **revert / 早期 return**: `_targetRatio > 1e18` → `InvalidBackingTarget`。`_targetRatio == 0` / `L_effective == 0` → `0`。
- **発火イベント**: なし（view）。
- **設計上のポイント**:
  - **運用補助であり solvency gate ではない**: これらの view は補填額計算の重複を減らすための読み取り専用 helper。Oracle 連携は `backingRatio()` のみで完結する。
  - **pending を含む**: `backingRatio()` と同じ `L_effective` を使い、既 redeem 済みの pending claim も同率に扱う。
  - **切り上げ**: `actualLiabilities()` は dToken 総供給 dust を 1 base unit へ切り上げ、目標比率への補填額も整数除算の過小見積もりを避けるため `ceil` で計算する。
  - **SP とは別責務**: 不足額の補填は `backstopDeposit` / Strategy 回収 / writeoff の Vault 側運用で扱い、Stability Pool から自動補填しない。
- **Verification**: unit（liability / shortfall / target=0 / target=1e18 / 切り上げ / `_targetRatio > 1e18` revert）, integration（毀損→必要額算出→backstopDeposit→`backingRatio` 回復）。

---

### VAULT-FR-019: emergencyDisableStrategy（登録 Strategy の即時無効化）

- **Type**: Functional ｜ **Source**: [protocol/product/policies/Governance-Roles-Timelock.md](../policies/Governance-Roles-Timelock.md)。`updateStrategy` 経由の無効化は共通 Timelock delay の対象となるため、疑わしい Strategy への新規配分を即時に止める fail-safe 経路を分離する
- **シグネチャ**: `emergencyDisableStrategy(IStrategy _strategy)`
- **目的**: 登録済み Strategy を GUARDIAN が即時に新規 allocate 対象から外す（`enabled = false`・`weightBps = 0`）。backing 評価（estimated / principal / cache）には一切触れない＝markdown 能力を持たない純フロー制御。
- **権限**: `GUARDIAN_ROLE` のみ。
- **事前条件（Checks）**: `_strategy` が登録済み（`strategies[]` 残存）であること（未登録は `StrategyNotFound`）。
- **動作（Effects）**:
  1. `totalWeightBps -= config.weightBps`（派生値の再集計、[§7](#7-状態変数会計モデル)）
  2. `config.weightBps = 0`・`config.enabled = false`（[VAULT-INV-009](#vault-inv-009)「無効化済みは weight 0」を維持）
  3. `StrategyEmergencyDisabled(strategy, oldWeightBps)` を発火
- **revert / 早期 return**: 未登録 → `StrategyNotFound`。既に無効化済みの Strategy への呼出しは冪等（weight は既に 0、状態変化なし）。
- **発火イベント**: `StrategyEmergencyDisabled(strategy, oldWeightBps)`（[VAULT-EVT-008](#11-イベント監視要件evt)）。
- **設計上のポイント**:
  - **非対称の要**: 無効化（リスク低減）は GUARDIAN 即時、再有効化・weight/cap 引き上げ（リスク増）は `updateStrategy`（GOV=Timelock、[VAULT-FR-009](#vault-fr-009-updatestrategy--writeoffstrategyprincipal登録-strategy-の調整と元本毀損確定)）のみ。disable 後も `strategies[]` に残存するため `receiveFromStrategy` での push 回収・`writeoffStrategyPrincipal`・`removeStrategy` の対象であり続け、登録判定の仕様上 `addStrategy` での再登録は `StrategyAlreadyExists` で拒否される＝再有効化経路が遅延側の `updateStrategy` に一意化される。
  - 災害時の第一手は `pauseAllocation`（全 Strategy への outbound 停止）であり、本関数は特定 Strategy のみを外して残りの運用を継続したい場合に使う。
- **Verification**: unit（GUARDIAN 限定・weight 0 化・totalWeightBps 再集計・冪等・backing 不変・再有効化は updateStrategy のみ）, invariant=[VAULT-INV-009](#vault-inv-009)。

---

## 7. 状態変数・会計モデル

### Vault レベル

| 変数 | 型 | 説明 | 確定 |
| --- | --- | --- | --- |
| `underlying` | `IERC20` | 保管対象 Underlying。未確定は `address(0)`（placeholder） | `initialize`（即時）/ `setUnderlying`（後付け 1 度） |
| `dToken` | `IDToken` | mint/burn する対応 dToken | `initialize` で固定 |
| `treasury` | `address` | 収益送付先 | `initialize` / `setTreasury` 更新 |
| `strategies[]` | `IStrategy[]` | 登録 Strategy（担保資産ごとに複数登録可） | `addStrategy` / `removeStrategy` |
| `whitelistedStrategies` | `mapping` | Strategy のホワイトリスト（GOV 事前承認集合。`addStrategy` の前段ガード） | `addToWhitelist` / `removeFromWhitelist` |
| `strategyConfigs[strategy]` | `StrategyConfig` | `{ enabled, weightBps, cap }` の 3 フィールド | `addStrategy` / `updateStrategy` |
| `totalWeightBps` | `uint256` | 登録 Strategy の `weightBps` 合計（派生値、`<= 10000` を実装が強制。GOV 直接 setter なし） | `addStrategy` / `updateStrategy` / `removeStrategy` で自動集計 |
| `bufferTargetBps` | `uint256` | 目標在庫比率（BPS） | `initialize` 既定 / `setBufferConfig` |
| `bufferFloor` | `uint256` | 最低在庫の絶対量 | `initialize` 既定 / `setBufferConfig` |
| `allocateMaxMove` | `uint256` | `allocate()` 1 回の最大移動量（`allocate()` のみに適用。`0` は配分停止、`type(uint256).max` は実質無制限） | `initialize` 既定 / `setAllocatorConfig` |
| `allocatorCooldown` | `uint256` | `allocate()` 実行間隔の最小クールダウン秒数 | `initialize` 既定 / `setAllocatorConfig` |
| `lastAllocatorTime` | `uint256` | `allocate()` の最終実行時刻（cooldown 判定） | `allocate()` |
| `withdrawDelay` | `uint256` | 遅延償還の待機期間（既定 1 day） | `initialize` 既定 / `setWithdrawDelay` |
| `withdrawRequests[id]` | `mapping → WithdrawRequest` | 未 claim / claim 済みの遅延償還レコード | `redeem`（発行）/ `claim`（消込） |
| `nextRequestId` | `uint256` | requestId 採番（初期 1、発行ごと +1） | `initialize` 既定 / `redeem` |
| `pendingWithdrawals` | `uint256` | 未 claim の WithdrawRequest 合計（バッファ保護に使用） | `redeem`（+）/ `claim`（−） |
| `_backstopReserve` | `uint256` | protected backstop reserve の帳簿額。`bufferBalance()` から除外し、`totalUnderlying()` には Vault raw balance として含める | `backstopDeposit`（+）/ `releaseBackstopToBuffer`（−） |
| `pausedDeposit` / `pausedRedeem` / `pausedClaim` / `pausedAllocation` | `bool` | 停止フラグ（独立 4 系統） | `pause*` / `unpause*` |

> 📌 **担保別の Day-1 具体値**（`bufferTargetBps` / `bufferFloor` / `allocatorCooldown` / `allocateMaxMove` / `withdrawDelay` / mintCap）は [Parameters.md](../../../Parameters.md) を**正本**とする。本書は各パラメータの意味・既定挙動のみを定義する。

### Strategy レベル（`strategyConfigs[strategy]` = `StrategyConfig`）

- `weightBps`: 配分比率（登録 Strategy 合計で `<= 10000`）
- `cap`: 最大投下量（リスク制限）
- `enabled`: 有効/無効（個別停止）

> `StrategyConfig` は `{ enabled, weightBps, cap }` の 3 フィールドのみ。同期/非同期の区別は持たず、外部プロトコルが同期か非同期かは各 Strategy 実装の内部に閉じる（[Strategy 要件定義](./strategies/Strategy.md)）。各 Strategy の投下元本は **Strategy 側が `principal` として自己管理**し、Vault はソルベンシー評価に `min(estimatedTotalUnderlying, principal)` を用いる（[VAULT-FR-007](#vault-fr-007-transferyieldtotreasury収益の-treasury-送付)）。

### WithdrawRequest 構造体

| フィールド | 型 | 意味 |
| --- | --- | --- |
| `owner` | `address` | claim の固定送金先 / entitlement owner。redeem 時の `_receiver` を記録 |
| `underlyingAmount` | `uint256` | claim 時に受け取る Underlying 量（buffer 不足分の `remaining`） |
| `claimableAt` | `uint256` | claim 可能になる時刻（`block.timestamp + withdrawDelay`） |
| `claimed` | `bool` | 二重 claim 防止フラグ |

### 会計原則

- **保守評価（`min(est, principal)`）**: ソルベンシー（`totalUnderlying`）では各 Strategy を live `min(estimatedTotalUnderlying, principal)` で評価し、未実現収益（est > principal）の前計上を防ぐ。Strategy valuation view が revert した場合は、`strategyValuationMaxAge` 内の last-good conservative cache を一時的に使い、stale/missing/無効 cache は 0 評価する。一方、outbound 用の `managedUnderlying` は cached value や一部 Strategy の live 値だけに対して送金せず、登録 Strategy の live valuation が 1 件でも読めなければ全体を 0 とする。`getAllStrategies` は監視のため、読める場合は `est` 生値、読めない場合は 0 を返す。
- **負債の定義**: `L_user = convertToUnderlying(dToken.totalSupply())` を基本とし、dToken 総供給が Underlying base unit に exact 対応しない dust を含む場合は 1 base unit へ切り上げる（`actualLiabilities()` と同一）。`L_pending = pendingWithdrawals`、`L_effective = L_user + L_pending`。
- **A/L 判定は価格 oracle ではなく Underlying 建て会計**: `A = totalUnderlying()` と `L_effective` はどちらも当該 Vault の Underlying 単位で比較する。`A < L_effective` は「JPY 建て市場価格が下がった」という判定ではなく、Strategy から見た回収可能 Underlying と dToken/pending 請求権の同一資産建て会計比較である。dToken 自体に価格 oracle は持たせず、Oracle Layer は Vault が返す `backingRatio()` を市場価格へ乗じるだけ。
- **ソルベンシー原則**: 常に `A = totalUnderlying() >= L_effective` を維持することを目標にする。ここで `A` は backing / `backingRatio()` 用であり、protected backstop reserve を含む。一方、送金可能な収益は内部の `M = managedUnderlying = bufferBalance() + Σ live min(est, principal)` から `surplus = max(M - L_effective, 0)` で算出し、Treasury 送付は liquid buffer のうち `allocate` と同じ流動性予約 `B_reserve`（buffer target + `pendingWithdrawals`、[VAULT-FR-004](#vault-fr-004-allocatebuffer-余剰を-strategy-へ配分)）を超える分を上限にクランプする。Strategy valuation failure 時、`A` は fresh cache を使い得るが、`M` は cache や部分合計を使わず全体を 0 とする。したがって backstop reserve、cached Strategy value、不完全な system view は allocation / Treasury surplus にならない（[VAULT-FR-007](#vault-fr-007-transferyieldtotreasury収益の-treasury-送付) / [VAULT-INV-001](#vault-inv-001)）。
- **backing 比のオラクル供給**: 同じ `A` と `L_effective` から `backingRatioForPricing() = (min(1e18, A / L_effective), available)` を導き（[VAULT-FR-016](#vault-fr-016-backingratiodtoken-裏付け率の供給)）、Oracle Layer は available な値だけを dToken 担保価格に乗じる（[Oracle 要件定義](./Oracle.md) `ORCL-FR-014`）。実測 `A < L_effective` は担保価値へ下方伝播し、valuation 取得不能は全損と誤分類せず oracle failure path に入る。
- **補填入金の扱い**: `backstopDeposit` は `L_effective` や dToken 供給量を増やさず、protected reserve と `A` だけを増やす。したがって毀損時は `backingRatio()` を回復させるが、buffer 不足時の `claim` 原資として使うには GOV の `releaseBackstopToBuffer` が必要である。
- **`totalWeightBps` は派生値**: `addStrategy` / `updateStrategy` / `removeStrategy` で自動集計し `<= 10000` を実装が強制。GOV の直接 setter は持たない。

---

## 8. 不変条件（INV）

| ID | 不変条件 | 検証 |
| --- | --- | --- |
| <a id="vault-inv-001"></a>VAULT-INV-001 | ソルベンシー原則: 健全状態では `totalUnderlying() >= L_effective`（`= L_user + L_pending`）。`A < L_effective`（元本毀損）は buffer / cap / Strategy 選定で**未然に防ぐ**ことを第一とし、万一破れた場合は `backingRatio()`（[VAULT-FR-016](#vault-fr-016-backingratiodtoken-裏付け率の供給)）が `1e18` 未満を返し Oracle 経由（[Oracle 要件定義](./Oracle.md) `ORCL-FR-014`）で担保価値を下方修正してコアの清算機構に吸収させる（破綻として放置しない、[VAULT-FR-007](#vault-fr-007-transferyieldtotreasury収益の-treasury-送付)） | invariant |
| <a id="vault-inv-002"></a>VAULT-INV-002 | redeem 成功時は CEI 順序（必要量 exact 算出 → `dToken.burn` → `safeTransfer`）を守り、即時／遅延の按分後も `_dTokenAmount` は全量 burn される。非 exact dToken amount は burn 前に `InvalidDTokenAmount` で revert する（[VAULT-FR-002](#vault-fr-002-redeemdtoken--underlying)） | invariant |
| <a id="vault-inv-003"></a>VAULT-INV-003 | buffer 不足 redeem では `即時支払い + WithdrawRequest.underlyingAmount == underlyingNeeded` かつ `pendingWithdrawals` が `remaining` だけ増える（先着総取り＋遅延ルール、[VAULT-FR-002](#vault-fr-002-redeemdtoken--underlying)） | invariant |
| <a id="vault-inv-004"></a>VAULT-INV-004 | `pendingWithdrawals == Σ(未 claim の WithdrawRequest.underlyingAmount)`。初回 claim 成功で当該分だけ減り、既決済 retry は `0` で会計・送金・event を変更しない（`claimed` フラグ、[VAULT-FR-006](#vault-fr-006-claimwithdrawrequest-の遅延償還受領)） | invariant |
| <a id="vault-inv-005"></a>VAULT-INV-005 | `totalUnderlying() == underlying.balanceOf(vault) + Σ strategyConservativeValue_i`。live valuation が読める Strategy は `min(estimatedTotalUnderlying_i, principal_i)`、valuation failure 時は fresh cache、stale/missing/無効 cache は 0 評価する。この raw balance は liquid buffer と protected backstop reserve の合計であり、`bufferBalance()` は reserve を除外する。Vault→Strategy allocation 後に live refresh が失敗した場合、fallback cache は投下前に読めた live 保守値へ既知 outflow 分を足した値で seed し、古い/stale cache を fresh 化しない。`receiveFromStrategy` の `received` は declared でなく残高差分で計上され、exact delivery の fallback cache は実着額分だけ減額するが full valuation ではないため `updatedAt` を進めない。declared/received mismatch の cache は無効化される（[VAULT-FR-005](#vault-fr-005-receivefromstrategystrategy--vault-の-push-受入) / [VAULT-FR-007](#vault-fr-007-transferyieldtotreasury収益の-treasury-送付)） | invariant |
| <a id="vault-inv-006"></a>VAULT-INV-006 | `allocate()` の 1 回の buffer→Strategy 移動量は `allocateMaxMove` 以下、かつ各 Strategy への配分は cap 残（`cap_i - est_i`）以下。managed-assets preflight failure は outbound 全体を停止する。preflight 成功後、cap で削られた分・Strategy 別 valuation 再読/deposit failure で skip された分は再配分されず buffer に留まる。deposit reject 時は完全回収できた場合だけ skip し、不一致は全体 revert する（[VAULT-FR-004](#vault-fr-004-allocatebuffer-余剰を-strategy-へ配分)） | invariant |
| <a id="vault-inv-007"></a>VAULT-INV-007 | `addToWhitelist` / `addStrategy` は EOA / 未デプロイ strategy を拒否し、`addStrategy` は `whitelistedStrategies[strategy] == true` かつ `vault.underlying() != address(0)` かつ `strategy.underlying() == vault.underlying()` のときのみ成功する（[VAULT-FR-008](#vault-fr-008-strategy-whitelist登録解除addtowhitelist--removefromwhitelist--addstrategy--removestrategy)） | invariant |
| <a id="vault-inv-008"></a>VAULT-INV-008 | `removeStrategy` は `strategy.principal() == 0` かつ live `strategy.estimatedTotalUnderlying() == 0` のときのみ成功する（残元本があれば `StrategyHasPrincipal`、live valuation 失敗または残余資産があれば `StrategyHasAssets`、[VAULT-FR-008](#vault-fr-008-strategy-whitelist登録解除addtowhitelist--removefromwhitelist--addstrategy--removestrategy)） | invariant |
| <a id="vault-inv-009"></a>VAULT-INV-009 | 無効化済み Strategy（`enabled == false`）は必ず `weightBps == 0`。`totalWeightBps == Σ(登録 Strategy の weightBps) <= 10000`（[VAULT-FR-009](#vault-fr-009-updatestrategy--writeoffstrategyprincipal登録-strategy-の調整と元本毀損確定)） | invariant |
| <a id="vault-inv-010"></a>VAULT-INV-010 | `setUnderlying` は一度のみ成功（`UnderlyingAlreadySet`）し確定後 `underlying` は不変。active 期は常に `dToken.underlying() == vault.underlying()`（`whenUnderlyingReady` が利用時点で強制、[VAULT-FR-011](#vault-fr-011-setunderlying後付け確定一度限り)） | invariant |
| <a id="vault-inv-011"></a>VAULT-INV-011 | placeholder（`underlying == address(0)`）では `deposit` / `redeem` / `redeemWithPermit` / `backstopDeposit` / `releaseBackstopToBuffer` / `addStrategy` がすべて revert し、`bufferBalance()` / `backstopBalance()` / `totalUnderlying()` は 0 を返し、`allocate()` は早期 return する（資金が動かない、[VAULT-FR-011](#vault-fr-011-setunderlying後付け確定一度限り) / [VAULT-FR-013](#vault-fr-013-view-群bufferbalance--totalunderlying--strategy-列挙)） | invariant |
| <a id="vault-inv-012"></a>VAULT-INV-012 | `backingRatio()` は `L_effective == 0` のとき `1e18`、それ以外は `min(1e18, totalUnderlying() * 1e18 / L_effective)` を返す（下方専用 `<= 1e18`・健全時 `== 1e18`）。Strategy valuation failure は fresh cache または 0 評価で処理し、view で revert しない（[VAULT-FR-016](#vault-fr-016-backingratiodtoken-裏付け率の供給)） | invariant |
| <a id="vault-inv-013"></a>VAULT-INV-013 | `backstopDeposit` は dToken `totalSupply` と `pendingWithdrawals` を変えず、実着額 `received` 分だけ `backstopBalance()` / `totalUnderlying()` を増やし、`bufferBalance()` は増やさない。`releaseBackstopToBuffer` は `totalUnderlying()` を変えず `backstopBalance()` を減らし `bufferBalance()` を増やす。したがって同一 `L_effective` の下で `backingRatio()` を低下させてはならない（[VAULT-FR-017](#vault-fr-017-backstopdepositdtoken-を-mint-しない補填入金)） | invariant |
| <a id="vault-inv-014"></a>VAULT-INV-014 | `actualLiabilities()` / `backingRatio()` / `backstopRequiredForRatio()` は dToken 総供給 dust を過小評価せず、Underlying base unit へ切り上げて扱う（[VAULT-FR-016](#vault-fr-016-backingratiodtoken-裏付け率の供給) / [VAULT-FR-018](#vault-fr-018-backing-ops-views補填運用補助)） | unit / invariant |

---

## 9. セキュリティ要件（SEC）

### <a id="vault-sec-001"></a>VAULT-SEC-001: CEI / Reentrancy

- Type: Security
- Statement: 価値移転を伴う関数（`deposit` / `redeem` / `redeemWithPermit` / `receiveFromStrategy` / `backstopDeposit` / `claim` / `allocate` / `transferYieldToTreasury`）は `nonReentrant` で保護し、`redeem` / `claim` は Checks-Effects-Interactions 順序（状態確定 → burn / `claimed` 更新 → 外部送金）を守らなければならない。`allocate` は Strategy への transfer / deposit 中の Vault 変更系再入を拒否し、valuation cache 更新前に read-only view 再入が起きても裏付けを過大評価してはならない。buffer 不足 claim は Effects 前に revert し `claimed = true` を永続化してはならない。
- Verification: unit（再入テスト・allocate 中 read-only 観測テスト）, invariant=[VAULT-INV-002](#vault-inv-002) / [VAULT-INV-004](#vault-inv-004) / [VAULT-INV-006](#vault-inv-006)

### <a id="vault-sec-002"></a>VAULT-SEC-002: Underlying 整合の利用時点強制（fail-closed）

- Type: Security
- Statement: Vault と dToken の Underlying が分岐した状態では `deposit` / `redeem` / `redeemWithPermit` を実行してはならない。`whenUnderlyingReady` が利用時点で `dToken.underlying() == vault.underlying()` を検証し、不一致は `UnderlyingMismatch`（未設定は `UnderlyingNotSet`）で fail-closed する。即時パス・遅延パスの双方を活性化順序に依存せずカバーする（[VAULT-FR-011](#vault-fr-011-setunderlying後付け確定一度限り)）。
- Verification: unit（不一致・未設定 revert・両パス）, invariant=[VAULT-INV-010](#vault-inv-010)

### <a id="vault-sec-003"></a>VAULT-SEC-003: 受領額は残高差分で計上（declared 非依存）

- Type: Security
- Statement: `receiveFromStrategy` は declared 量ではなく受領前後の残高差分で `received` を確定し、fee-on-transfer / rebasing 等で実着額が declared を下回っても会計をずらしてはならない（[VAULT-FR-005](#vault-fr-005-receivefromstrategystrategy--vault-の-push-受入)）。
- Verification: unit（fee-on-transfer 模擬での差分計上・cache 無効化・valuation 回復）, invariant=[VAULT-INV-005](#vault-inv-005)

### <a id="vault-sec-004"></a>VAULT-SEC-004: 活性化前の資金封じ込め（多層防御）

- Type: Security
- Statement: placeholder Vault（`underlying == address(0)`）では運用へ資金が流れてはならない。(1) `addStrategy` の Underlying 不変条件で登録不可、(2) `deposit` は `whenUnderlyingReady` で revert、(3) view は 0 を返し、(4) `allocate()` は早期 return する、という多層で封じる（[VAULT-FR-011](#vault-fr-011-setunderlying後付け確定一度限り)）。
- Verification: unit（各層の封じ込め）, invariant=[VAULT-INV-011](#vault-inv-011)

### <a id="vault-sec-005"></a>VAULT-SEC-005: ALLOCATOR の最小権限（固定宛先・固定比率）

- Type: Security
- Statement: ALLOCATOR が呼べるのは `allocate` / `Strategy.sendToVault` / `Strategy.sendProfitToVault` / `transferYieldToTreasury` の 4 関数のみで、宛先は事前登録 Strategy／回収先は Vault／送付先は現在の `treasury`（ALLOCATOR からは固定。変更は GOV の `setTreasury` のみ）に限定されなければならない。ALLOCATOR 鍵が侵害されても任意アドレスへ送金できてはならず、Vault からの outbound（`allocate` / `transferYieldToTreasury`）は `pauseAllocation` で停止できなければならない（[§10](#10-ガバナンス運用アップグレード要件gov) / [VAULT-FR-012](#vault-fr-012-gov-設定-settersetbufferconfig--setallocatorconfig--setstrategyvaluationmaxage--setwithdrawdelay--settreasury)）。
- Verification: unit（ALLOCATOR から treasury 変更不可・送付先固定・pause 中 outbound 停止）, manual（ロール構成レビュー）

### <a id="vault-sec-006"></a>VAULT-SEC-006: pause/unpause の非対称権限

- Type: Security
- Statement: pause（4 系統）と緊急無害化（`emergencyDisableStrategy` / `removeStrategy` / `removeFromWhitelist`）は `GUARDIAN_ROLE`、unpause・再有効化・増額は `GOV_ROLE`（holder = 共通 Timelock）のみとし、ガーディアン鍵が侵害されても「可逆な停止・無害化」しかできず、再開には Timelock 経由の GOV 承認を要する非対称設計でなければならない。GUARDIAN_ROLE の操作は backing 評価（estimated / principal / valuation cache）を一切下方修正できてはならない（markdown 能力の排除、[VAULT-FR-014](#vault-fr-014-pause--unpause緊急停止) / [VAULT-FR-019](#vault-fr-019-emergencydisablestrategy登録-strategy-の即時無効化)）。
- Verification: unit（pause/無害化は GUARDIAN・unpause は GOV のみ・GUARDIAN 操作の backing 不変）

### <a id="vault-sec-007"></a>VAULT-SEC-007: アップグレード権限の限定

- Type: Security
- Statement: 新実装の承認は GOV_MULTISIG（`GOV_ROLE`・mainnet では holder = 共通 TimelockController のみ）に限定し、運用ロール（ALLOCATOR / GUARDIAN / WRITEOFF / Strategy 等）はアップグレードできてはならない。ストレージは追記のみ（既存スロットの並べ替え・型変更をしない、[VAULT-FR-015](#vault-fr-015-アップグレードuups)）。
- Verification: unit（非 GOV 承認 revert）, manual（storage layout review）

### <a id="vault-sec-008"></a>VAULT-SEC-008: dToken dust の silent burn 防止

- Type: Security
- Statement: `redeem` / `redeemWithPermit` は `_dTokenAmount` が Underlying base unit に exact に対応しない場合、burn / permit nonce 消費 / request 作成の前に `InvalidDTokenAmount` で revert しなければならない。USDC(6) なら `1e12` dToken、WBTC(8) なら `1e10` dToken が最小 redeem 単位であり、これ未満の dToken dust を 0 Underlying として焼却してはならない。
- Verification: unit（USDC6 / WBTC8 dust、permit nonce 未消費）, invariant=[VAULT-INV-002](#vault-inv-002) / [VAULT-INV-014](#vault-inv-014)

### <a id="vault-sec-009"></a>VAULT-SEC-009: blacklistable token の個別 revert 隔離

- Type: Security
- Statement: USDC 等の blacklistable Underlying が transfer を revert しても、`redeem` / `claim` の状態更新（burn、request 作成、`claimed`、`pendingWithdrawals`）は tx 全体の revert で巻き戻らなければならない。Vault は batch payout を行わず、blacklist による失敗は当該ユーザーの個別 tx / request に閉じ込める。
- Verification: unit（blacklisted receiver / request owner の transfer revert で state rollback）, manual（token risk review）

---

## 10. ガバナンス・運用・アップグレード要件（GOV）

### <a id="vault-gov-001"></a>VAULT-GOV-001: ロール分離（初期集中 → 本番分離）

- Statement: `initialize` は `_admin` に 5 ロール（`DEFAULT_ADMIN_ROLE` / `GOV_ROLE` / `ALLOCATOR_ROLE` / `GUARDIAN_ROLE` / `WRITEOFF_ROLE`）を集中付与するが、本番では (1) `DEFAULT_ADMIN_ROLE` / `GOV_ROLE` を**共通 TimelockController のみ**、(2) `WRITEOFF_ROLE` を高定足数 GOV multisig のみ、(3) `GUARDIAN_ROLE` を Guardian multisig のみ、(4) `ALLOCATOR_ROLE` を `DF_ALLOCATOR` のみが保持する状態へ分離・移譲し、`_admin`（deployer）を**全ロールから revoke** しなければならない。各ロールの単独 holder 状態は活性化手順の deploy gate として機械検証する（症状が出ない設定不備——全機能は動くが遅延が bypass 可能——を防ぐため。[§4](#4-アクターロール信頼境界) / [VAULT-FR-010](#vault-fr-010-initializeプレースホルダー化proxy-初期化) / [VAULT-GOV-004](#vault-gov-004-timelock-と緊急-pause-の分離)）。
- Verification: manual（デプロイ構成レビュー）＋ deploy script / integration test での holder assert

### <a id="vault-gov-002"></a>VAULT-GOV-002: ロール × 操作マトリックス

- Statement: 主要操作とロールの対応は下表のとおり。

| 操作 | GOV（=共通 Timelock） | WRITEOFF（GOV multisig・即時） | ALLOCATOR | GUARDIAN（即時） | permissionless |
| --- | --- | --- | --- | --- | --- |
| deposit（mint） | | | | | ✓ |
| redeem | | | | | ✓ |
| claim（WithdrawRequest を owner へsettle） | | | | | ✓（任意caller・owner固定送金・`pausedClaim == false` 時） |
| allocate | | | ✓ | | |
| `Strategy.sendToVault`（元本 push 回収） | | | ✓ | | |
| `Strategy.sendProfitToVault`（収益 push、allocation pause 対象外） | | | ✓ | | |
| `transferYieldToTreasury`（buffer 余剰→Treasury、allocation pause 対象） | | | ✓ | | |
| `receiveFromStrategy`（push 受入） | | | | | ✓（登録 Strategy のみ） |
| `backstopDeposit`（補填入金、dToken mint なし） | | | | | ✓ |
| `releaseBackstopToBuffer`（補填 reserve の明示解放） | ✓ | | | | |
| `writeoffStrategyPrincipal`（元本毀損の確定） | | ✓ | | | |
| async Strategy `setPendingWithdrawalValuationBps`（pending valuation markdown。下方変更は `pausedAllocation == true` 必須） | | ✓ | | | |
| Strategy 追加（addToWhitelist / addStrategy） | ✓ | | | | |
| Strategy 除去（removeFromWhitelist / removeStrategy、fail-safe） | | | | ✓ | |
| `emergencyDisableStrategy`（即時無効化、[VAULT-FR-019](#vault-fr-019-emergencydisablestrategy登録-strategy-の即時無効化)） | | | | ✓ | |
| weights / caps 更新・再有効化（updateStrategy） | ✓ | | | | |
| buffer / allocator パラメータ更新（setBufferConfig / setAllocatorConfig / setWithdrawDelay / setStrategyValuationMaxAge） | ✓ | | | | |
| Treasury 送金先変更（setTreasury、一度きりでない） | ✓（Vault GOV_ROLE） | | | | |
| valuation cache の明示破棄（invalidateStrategyValuationCache。markdown 能力ゆえ GUARDIAN に置かない） | ✓ | | | | |
| cap 更新（dToken.setCap） | ✓（dToken Owner = Timelock） | | | | |
| Underlying 初回設定（dToken.setTokenInfo、一度限り） | ✓（dToken Owner = Timelock） | | | | |
| Underlying 後付け確定（setUnderlying、一度限り） | ✓（Vault GOV_ROLE） | | | | |
| pause（pauseDeposit / pauseRedeem / pauseClaim / pauseAllocation） | | | | ✓ | |
| unpause（unpauseDeposit / unpauseRedeem / unpauseClaim / unpauseAllocation） | ✓ | | | | |
| `Strategy.emergencyWithdraw` / `Strategy.emergencyWithdrawFromAave`（送金先 Vault 固定） | | | | ✓（Strategy Owner = Guardian multisig） | |
| `Strategy.sweepRewardToken`（非 Underlying・非 position reward → Treasury 固定） | | | | ✓（Strategy Owner = Guardian multisig） | |
| Strategy Upgrade（UUPS、upgrader = Timelock） | ✓ | | | | |
| Contract Upgrade（UUPS） | ✓ | | | | |
| ロール付与・剥奪（`grantRole` / `revokeRole`） | ✓（`DEFAULT_ADMIN_ROLE`） | | | | |
| 自ロール放棄（`renounceRole`） | ✓（自分自身のみ） | ✓（自分自身のみ） | ✓（自分自身のみ） | ✓（自分自身のみ） | |

- 各操作の詳細は §6 の対応 FR（「権限」項目）を参照。`Strategy.sendToVault` / `sendProfitToVault` / `emergencyWithdraw` / `sweepRewardToken` の本体は [Strategy 要件定義](./strategies/Strategy.md)。
- Verification: manual（権限テストの網羅）

### <a id="vault-gov-003"></a>VAULT-GOV-003: ロール設計上の考察

- Statement:
  - **GOV_MULTISIG（holder = 共通 TimelockController）**: 資金・パラメータ・コントラクトの重要変更を一手に握るが、**すべての操作に公示遅延**が掛かる（GOV multisig は Timelock の PROPOSER/EXECUTOR）。緊急即時操作は持たない——緊急の損失確定は WRITEOFF_ROLE（`writeoffStrategyPrincipal` / async pending valuation bps）、即時無害化・登録解除は GUARDIAN_ROLE（`emergencyDisableStrategy` / `removeStrategy` / `removeFromWhitelist`）に分離済み（実資産の引き上げは ALLOCATOR の `Strategy.sendToVault`、または Strategy owner（= Guardian multisig）の固有緊急関数で行う）。
  - **WRITEOFF（高定足数 GOV multisig・即時）**: `writeoffStrategyPrincipal` と async Strategy の pending valuation bps 変更のみ。下方 bps 変更は `pausedAllocation == true` を必須とし、Guardian が新規配分・Treasury sweep を止めた incident freeze 後にだけ清算価格へ反映できる。タイミングはロールの holder が決まるため、「writeoff/markdown は即時・他の GOV 操作は遅延」を両立するには GOV_ROLE と別ロールにする必要がある（同居させると markdown も共通 Timelock delay の対象となるか、即時マルチシグ が unpause 等も即時実行できてしまう）。Guardian の即時ロールにも入れない——Guardian は速い緊急応答のため定足数を低めに回す一方、markdown は不当 markdown → 不当清算で窃取可能なため高定足数が必須で、同居させると「pause が遅くなる」か「markdown が甘くなる」のどちらかになる。
  - **ALLOCATOR**: 動作を `allocate()`・`Strategy.sendToVault()`・`Strategy.sendProfitToVault()`・`transferYieldToTreasury()` に限定し、Strategy / weights / 登録は事前設定に従う。holder signing plane 侵害時の被害は「登録済み Strategy への送金」「Strategy→Vault buffer 回収」「buffer 余剰の `treasury` 送付」に限定（送付先は現在の `treasury` 1 つに固定。ALLOCATOR は変更できず変更は GOV の `setTreasury` のみ）。ただし `transferYieldToTreasury` は AUM 評価次第で過大送付し得るため、ロール付＋`pauseAllocation` で停止可能にして人間監視でケアする（[§12](#12-失敗時異常系挙動err)）。permissionless 化は行わず、holder の liveness と移管条件は mainnet role assignment policy で管理する。permissionless 化の再評価は、est/writeoff 鮮度の on-chain 検証・keeper インセンティブ・Treasury 側 rate-limit のいずれかが実装された場合に限る。
  - **GUARDIAN**: Guardian multisig。緊急停止（pause 4 系統）と可逆な無害化（`emergencyDisableStrategy` / `removeStrategy` / `removeFromWhitelist`）のみを許可（解除・再有効化は GOV=Timelock のみ）。timelock を経由させると緊急停止として機能しないため、本番では Timelock とは別の Guardian multisig に分離する。GUARDIAN に許可する操作は「backing 中立 or 純フロー制御」に限定し、markdown 能力（writeoff / `invalidateStrategyValuationCache`）は持たせない——invalidateCache は live 評価失敗窓で cache をクリアすると当該 Strategy 評価が 0 になり清算を誘発しうるため GOV（遅延）に置く（緊急性は低い: cache は `strategyValuationMaxAge` で自動失効する）。
- Verification: manual

### <a id="vault-gov-004"></a>VAULT-GOV-004: timelock と緊急 pause の分離

- Statement（2026-06-12 確定）: mainnet では以下の holder 構成を必須とする（設計判断の正本: [protocol/product/policies/Governance-Roles-Timelock.md](../policies/Governance-Roles-Timelock.md)。原則は「資金流出・希薄化・markdown を起こしうる操作は遅延または高定足数、可逆な fail-safe は即時、復旧は遅延」）。
  - **共通 TimelockController が `GOV_ROLE` / `DEFAULT_ADMIN_ROLE` の唯一の holder**。delay値は [Day1 Parameter Manifest](../../../Parameters.md) `PRM-GOV-COMMON-TIMELOCK-DELAY`、PROPOSER / EXECUTOR / CANCELLERのholder構成は [Protocol Role Holder Manifest](../../../protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md) を正本とする。dToken Owner・Strategy upgrader・（実装後の）Treasury 系と**同一の Timelock を共用**する。
  - **GOV multisig が Vault に直接保持するロールは `WRITEOFF_ROLE` のみ**（GOV_ROLE / DEFAULT_ADMIN を直接持つと共通 Timelock delay を丸ごと bypass できるため禁止）。
  - **GUARDIAN_ROLE = Guardian multisig**（pause 4 系統＋緊急無害化・即時）。緊急停止は timelock を経由させない。
  - **`ALLOCATOR_ROLE` = `DF_ALLOCATOR`**。physical holder と実行形態は mainnet role assignment policy を正本とする。
  - unpause・再有効化・増額・設定変更・upgrade はすべて GOV（= 共通 Timelock）経由（「ブレーキは引きやすく、戻すのは遅い」）。
  - **deploy gate（機械検証必須）**: 各ロールの単独 holder／deployer の全ロール revoke／Timelock の PROPOSER・EXECUTOR・CANCELLER 構成と admin renounce／`allocateMaxMove` / `allocatorCooldown` の有界値設定（initialize 既定の `type(uint256).max` / `0` のまま運用に入らない）。
- Verification: manual（デプロイ構成レビュー）＋ deploy script / integration test での holder・Timelock 構成 assert

---

## 11. イベント・監視要件（EVT）

| ID | イベント | 用途（off-chain） |
| --- | --- | --- |
| VAULT-EVT-001 | `Deposited(user, underlyingAmount, dTokenAmount)` | deposit/Mint 追跡。`user = msg.sender`。referralCode は含めない（referral は Zapper 側で記録） |
| VAULT-EVT-002 | `Redeemed(user, receiver, dTokenAmount, underlyingPaidNow, requestId)` | redeem 追跡。`requestId == 0` は即時完了 |
| VAULT-EVT-003 | `WithdrawRequested(user, receiver, requestId, amount, claimableAt)` | 遅延償還発生（buffer 不足）の検知。`WithdrawClaimed` との差分で未 claim キューを再構成 |
| VAULT-EVT-004 | `Allocated(bufferBefore, targetBuffer, bufferAfter)` / `StrategyAllocated(strategy, amount)` / `StrategyAllocationSkipped(strategy)` | `allocate()` の前バッファ・目標バッファ・後バッファ（集約）、Strategy ごとの実配分額、および preflight 後の cap 用 valuation 再読不可・cap 到達・deposit reject 後の完全回収で配分しなかった Strategy。managed assets preflight failure はイベントなしの早期 return のため status availability と keeper receipt で監視する |
| VAULT-EVT-005 | `ReceivedFromStrategy(strategy, declaredAmount, received)` | 登録 Strategy からの push 受入。`declaredAmount` と `received` の差分で fee-on-transfer / トークン異常を検出 |
| VAULT-EVT-006 | `WithdrawClaimed(user, requestId, amount)` | 遅延償還の受領。`user = req.owner`、`amount = req.underlyingAmount` |
| VAULT-EVT-007 | `YieldTransferredToTreasury(amount, treasury)` | buffer 余剰の Treasury 送付（`amount == 0` でも発火）。頻度・金額が過大でないか監視 |
| VAULT-EVT-008 | `StrategyWhitelisted` / `StrategyRemovedFromWhitelist` / `StrategyAdded(strategy, weightBps, cap)` / `StrategyUpdated(strategy, weightBps, cap, enabled)` / `StrategyEmergencyDisabled(strategy, oldWeightBps)` / `StrategyRemoved(strategy)` | Strategy 管理（GOV / GUARDIAN 操作）の追跡。`StrategyEmergencyDisabled` は GUARDIAN の即時無効化（[VAULT-FR-019](#vault-fr-019-emergencydisablestrategy登録-strategy-の即時無効化)）＝インシデント対応の開始シグナル |
| VAULT-EVT-009 | `StrategyPrincipalWrittenOff(strategy, amount)` / `StrategyValuationRefreshed(strategy, estimatedUnderlying, principal, conservativeValue)` / `StrategyValuationRefreshFailed(strategy, estimateAvailable, principalAvailable)` / `StrategyValuationCacheReduced(strategy, oldValue, newValue, amount)` / `StrategyValuationCacheInvalidated(strategy, oldValue, oldUpdatedAt)` | WRITEOFF が回収不能元本を確定した場合、および valuation cache の更新・失敗・減額・破棄を追跡する。`StrategyPrincipalWrittenOff.amount` は要求額ではなく実際に減った `principal`。runtime event をアラートの一次シグナルにし、`strategyValuationCaches` / `getStrategyStatuses()` / `cacheStale` status で現在値を照合する |
| VAULT-EVT-010 | `UnderlyingSet(underlying)` | プレースホルダー Vault の Underlying を後付け確定したときに 1 度だけ発火 |
| VAULT-EVT-011 | `BufferConfigUpdated(oldTargetBps, newTargetBps, oldFloor, newFloor)` / `AllocatorConfigUpdated(oldMaxMove, newMaxMove, oldCooldown, newCooldown)` / `StrategyValuationMaxAgeUpdated(oldMaxAge, newMaxAge)` / `WithdrawDelayUpdated(oldDelay, newDelay)` / `TreasuryUpdated(oldTreasury, newTreasury)` | GOV 設定 setter の old/new 追跡。特に `TreasuryUpdated` は収益送付先変更、`StrategyValuationMaxAgeUpdated` は fallback TTL 変更の監視正本にする |
| VAULT-EVT-012 | `DepositPaused` / `DepositUnpaused` / `RedeemPaused` / `RedeemUnpaused` / `ClaimPaused` / `ClaimUnpaused` / `AllocationPaused` / `AllocationUnpaused` | 緊急停止・再開の検知（独立 4 系統）。特に `ClaimPaused` は vested 債務の凍結＝最重要アラート |
| VAULT-EVT-013 | ERC1967 `Upgraded(newImpl)` | UUPS アップグレードの追跡 |
| VAULT-EVT-014 | `BackstopDeposited(backstop, declaredAmount, received)` | dToken を mint しない補填入金。declared と received の差分で fee-on-transfer / トークン異常を検出 |
| VAULT-EVT-015 | `BackstopReleased(caller, amount)` | protected reserve を liquid buffer へ解放した GOV 操作の追跡 |

> dToken 側イベント（`CapUpdated` ＝ [DTKN-FR-006](./dToken.md)、`TokenInfoSet` ＝ [DTKN-FR-002](./dToken.md)）と Strategy 側イベント（`Deposited` / `SentToVault` / `ProfitSentToVault` / `PrincipalWrittenOff` / `EmergencyWithdrawn`、[Strategy 要件定義](./strategies/Strategy.md)）は各コントラクトから発火する。シグネチャ・意味はそれぞれの正本ドキュメントを参照。

**監視指標（最低限）**

- `A - L_effective`（超過/不足）／バッファ比率（liquid buffer/A）／`backstopBalance`
- 未処理 request 総量／平均待機時間（`WithdrawRequested` − `WithdrawClaimed` の差分。`pendingWithdrawals` view と一致）
- **滞留（stale）request の検知**（非没収型の予約解除を再評価するトリガ）: `claimableAt` 経過後、その間 buffer 充足・`pausedClaim` でなかった（＝claim 可能だった）にもかかわらず未 claim の request の合計額・最古経過日数を `managedUnderlying` 比でトレンド監視する。計時は claim 可能期間だけ進め、`pausedClaim` 中・`InsufficientBuffer` 状態・equitable repair freeze 中は停止する。暫定トリガは未 claim 合計が `managedUnderlying` の 1% 以上である状態の 30 日継続とし、mainnet 実測後に較正する
- GOV 設定変更イベント（VAULT-EVT-011）と反映後 view の一致
- Strategy 別投下額（`StrategyAllocated`）・allocation skip（`StrategyAllocationSkipped` + status availability / capRemaining と buffer 残）・cap 到達率・現在 alloc。現在値は `getStrategyStatuses()`、互換の一覧・`StrategyConfig`・推定残高は `getAllStrategies()`、件数は `getStrategiesCount()` を一次ソースとする（[VAULT-FR-013](#vault-fr-013-view-群bufferbalance--totalunderlying--strategy-列挙)）
- Strategy 別の `estimatedUnderlying` と `principal` の乖離（`estimatedLoss > 0` は元本毀損シグナル、`estimatedGain > 0` は推定上振れシグナル）。`estimateAvailable == false` / `principalAvailable == false` は monitoring alert
- `BackstopDeposited` の発生額・頻度・backstop アドレス（補填計画との一致）と `BackstopReleased` の額・タイミング（claim 原資化の承認確認）
- `transferYieldToTreasury` の頻度・金額（過大送付でないか）
- `Strategy.sendToVault` の `requested` と `actual`（= `sent`）の差分（流動性逼迫の検出シグナル、[Strategy 要件定義](./strategies/Strategy.md)）
- `ReceivedFromStrategy` の `declaredAmount` と `received` の差分（fee-on-transfer / トークン異常の検出）
- `getStrategyStatuses().usingCachedConservativeValue == true`、`estimateAvailable == false`、`principalAvailable == false`、`cacheStale == true` の継続（外部 protocol view failure / cache expiry 近接の検出）

---

## 12. 失敗時・異常系挙動（ERR）

> 本節はシステムレベルの異常系（pause / Underlying 未設定 / buffer 不足 / Strategy 失敗・元本毀損 / 遅延償還の既知リスク）を扱う。コア無改変の方針は [Product-Overview](../Product-Overview.md) §5、Strategy 固有リスクは [Strategy 要件定義](./strategies/Strategy.md)、dToken / Permit は [dToken 要件定義](./dToken.md) を参照。

### placeholder 期（Underlying 未確定）の挙動

| 関数 | placeholder 期（`underlying == 0`） | active 期 |
| --- | --- | --- |
| `deposit` / `redeem` / `redeemWithPermit` | `UnderlyingNotSet` revert（`whenUnderlyingReady`） | 実行可（pause 非該当時） |
| `backstopDeposit` / `releaseBackstopToBuffer` | `UnderlyingNotSet` revert（`whenUnderlyingReady`） | 実行可（release は GOV のみ） |
| `addStrategy` | `UnderlyingNotSet` revert（Underlying 不変条件） | 実行可（whitelist 済み・担保一致時） |
| `bufferBalance()` / `backstopBalance()` / `totalUnderlying()` | `0` を返す（placeholder-safe） | 実残高・保守評価合計 |
| `allocate()` | `managedUnderlying() == 0` 相当で早期 return | 実行可 |

### Underlying 設定リスク（[VAULT-SEC-002](#vault-sec-002)）

- 後付け初回設定のタイミングで誤った Underlying を指定すると、その後変更できない → デプロイから `dToken.setTokenInfo` → `vault.setUnderlying` 完了までの GOV_MULTISIG 運用手順（マルチシグ承認・事前テストネット検証）を厳格化。
- Vault と dToken の Underlying が分岐すると、保管資産と 18dec 換算・valuation がずれる → `setUnderlying` と各ユーザー価値フローで `dToken.underlying() == vault.underlying()` を強制し `UnderlyingMismatch` で fail-closed。
- 発行残高がある状態での Underlying 変更は構造的に不可（contract 側で revert）→ `underlying == address(0)` かつ dToken 側 `totalSupply() == 0` の二重ガードで物理的に防止（[DTKN-FR-002](./dToken.md)）。

### 償還流動性リスク（在庫不足 → 遅延増）

- ユーザーが dToken を Underlying へ償還したい時に buffer が不足すると遅延が発生し、常態化すると dToken の信用・市場価値に悪影響が出る可能性。
- 対策: `bufferTargetBps` を担保別に最適化（20% 固定にしない、[Parameters.md](../../../Parameters.md)）／Strategy を複数化し即時回収可能枠を必ず持つ／`Strategy.sendToVault` の Bot 運用・監視・緊急停止。

### Strategy リスク（スマコン・流動性・ペグ・アンボンド）と段階的回収

- Strategy 追加権限は GOV（= 共通 Timelock）のみ。cap 設定（Strategy ごとの最大配分）でリスク制限。
- **緊急時は無効化＋段階的回収**（`writeoffStrategyPrincipal` は [VAULT-FR-009](#vault-fr-009-updatestrategy--writeoffstrategyprincipal登録-strategy-の調整と元本毀損確定)、`Strategy.emergencyWithdraw` は [Strategy 要件定義](./strategies/Strategy.md)）:
  - 段階 1: `pausedAllocation = true`（GUARDIAN）で ALLOCATOR の `allocate` と `transferYieldToTreasury` を停止（`Strategy.sendToVault` / `Strategy.sendProfitToVault` による Vault への回収・引き上げは pause 対象外なので継続可能）
  - 段階 2: GUARDIAN が `emergencyDisableStrategy(strategy)` で問題 Strategy を即時無効化（新規 allocate 対象から除外、[VAULT-FR-019](#vault-fr-019-emergencydisablestrategy登録-strategy-の即時無効化)）
  - 段階 3: ALLOCATOR が `Strategy.sendToVault(全額相当)` で回収。外部プロトコル停止・incident 時は Strategy 個別 owner の固有緊急関数（例 `emergencyWithdrawFromAave` は liquid 分を同一 Tx で Vault へ push）を使い、Strategy が直接保有する idle donation / 残余は `emergencyWithdraw`（送金先 Vault 固定）で Vault へ push。各経路は `receiveFromStrategy` を通り、exact delivery では valuation cache を実着額分減額し、declared/received mismatch では自動無効化する。GOV / ops は `StrategyValuationCacheReduced` / `StrategyValuationCacheInvalidated` と `ReceivedFromStrategy` を照合し、必要に応じて `refreshStrategyValuation` で回復を確認する
  - 段階 4: 回収不能分は WRITEOFF_ROLE（高定足数 GOV multisig・即時）が `writeoffStrategyPrincipal` で確定。同時に GUARDIAN は必要に応じ `pauseRedeem` / `pauseClaim` で buffer の先着ドレインを freeze する（[VAULT-FR-014](#vault-fr-014-pause--unpause緊急停止)）
  - 段階 5: 回収・writeoff 後も `A < L_effective` が残る場合、Treasury / insurance / backstop が `backstopDeposit` で Underlying を protected reserve として補填
  - 段階 6: pending claim / 通常 redeem の流動性として使わせる額だけ、GOV が `releaseBackstopToBuffer` で reserve を liquid buffer に解放
- `enabled` フラグで個別停止。`removeStrategy` で完全除去（`principal == 0` かつ live `estimatedTotalUnderlying == 0` が前提。回収不能分は `writeoffStrategyPrincipal` で先にゼロ化し、回収可能な残余資産は removal 前に Vault へ戻す）。

### dToken backing 毀損のオラクル反映（担保価値の下方伝播）

- Strategy のハッキング・bad debt・slashing で実保有 `A = totalUnderlying()` が元本請求権 `L_effective` を下回ると、dToken は Underlying に対して**デペグ**する（dToken は 1:1 請求権だが裏付けが不足する）。`dToken.totalSupply()` は減らないため、市場価格だけを担保評価に使うと**過大評価**となり、過剰借入・JPYdf の Bad Debt を招く。
- **判定ソース**: `A < L_effective` は dToken の価格 oracle で判断しない。Vault は raw Underlying balance（liquid buffer + backstop reserve）と各 Strategy の `min(estimatedTotalUnderlying(), principal())` を合算して `A` を作る。Strategy loss が `estimatedTotalUnderlying()` に反映されれば backing は自動で下がる。外部プロトコル側の損失が Strategy の評価 view に反映されない場合、on-chain では自動検知できず、回収・個別停止・`writeoffStrategyPrincipal`・`backstopDeposit` の運用に依存する。
- **一時的な valuation failure の扱い**: live valuation が読める場合は必ず live `min(est, principal)` を使い、損失は即時に backing へ反映する。`estimatedTotalUnderlying()` または `principal()` の read が revert した場合だけ、Strategy 単位の bounded last-good cache を使う。cache が TTL 超過・未初期化・無効化済みの場合は 0 評価へ戻る。
- **対策（オラクルへの下方伝播）**: 本 Vault は available な `backingRatioForPricing()`（[VAULT-FR-016](#vault-fr-016-backingratiodtoken-裏付け率の供給)）を供給し、Oracle Layer（[Oracle 要件定義](./Oracle.md) `ORCL-FR-014`）が dToken 担保価格に乗じる。実測 backing 毀損は担保価値の下方修正として **Liquity コアの清算 / TCR<SCR branch shutdown / Urgent Redemptions に伝播**し、valuation 取得不能は standard oracle failure になる（両 consumer に対称適用）。
- **二重防御**: `min(est, principal)` 保守評価で est が損失を反映すれば backing は自動低下し、WRITEOFF の `writeoffStrategyPrincipal`（[VAULT-FR-009](#vault-fr-009-updatestrategy--writeoffstrategyprincipal登録-strategy-の調整と元本毀損確定)）で principal を下げれば `A` が下がり恒久確定する。
- **Stability Pool との責務分離**: Stability Pool は backing 低下後に unsafe になった Trove の清算を処理するだけで、Vault へ Underlying を補填しない。SP depositor に Strategy loss を直接負わせないため、dToken backing repair は Strategy 回収・writeoff・`backstopDeposit`（[VAULT-FR-017](#vault-fr-017-backstopdepositdtoken-を-mint-しない補填入金)）で Vault 側に閉じる。
- **補填経路**: `backstopDeposit` は dToken を mint せず Underlying を protected reserve に積み、`totalUnderlying()` と `backingRatio()` を回復させる。ただし reserve は通常 redeem / claim には使えない。buffer 不足の `claim` は、GOV が必要額を `releaseBackstopToBuffer` で liquid buffer に解放した後に再試行できる。
- **残課題**: est が損失を即反映しない外部プロトコルでは writeoff の適時性に依存する。また fresh cache 期間中に実毀損が発生し、同時に valuation view が取得不能な場合は TTL まで過大評価が残り得る。pricing call failure または live/cache valuation unavailable 時、PriceFeed は `lastGoodBacking` で価格を継続せず、標準 oracle failure path（branch shutdown + `lastGoodPrice`）に入る。深刻な実測毀損時は backing 専用 shutdown 閾値を設けず、価格下落のみで既存機構に委ねる方針。

### ALLOCATOR 鍵侵害時の影響（固定宛先・固定比率で被害を限定、[VAULT-SEC-005](#vault-sec-005)）

- ALLOCATOR が呼べるのは `allocate` / `Strategy.sendToVault` / `Strategy.sendProfitToVault` / `transferYieldToTreasury` の **4 つに限定**。宛先は事前登録 Strategy／回収先は Vault／送付先は `treasury`（ALLOCATOR からは固定。変更は GOV の `setTreasury` のみ）のいずれかに限定され、任意アドレスへ送金して抜かれることは防ぎやすい。
- **残るリスク**:
  - 過剰な `allocate` 連打（ガス・運用負荷）
  - `Strategy.sendToVault` / `Strategy.sendProfitToVault` の乱用（運用利回り低下・運用の不安定化）。ただし行き先は Vault buffer に固定されるため資金は系内に留まる
  - **`transferYieldToTreasury` による Treasury への過大送付（Vault buffer Underlying の系外流出経路）**: AUM（`estimatedTotalUnderlying`）の過大評価、または損失が est に未反映のとき `surplus = M - L_effective` が水増しされ buffer から取りすぎが起こり得る。`M = managedUnderlying` は protected backstop reserve と cached Strategy value を除外するため、backstop 入金や valuation fallback だけで Treasury surplus は生まれない。`sendToVault` / `sendProfitToVault`（系内）と異なり**Vault buffer から系外へ出る**点に注意。`min(estimatedTotalUnderlying, principal)` 保守評価・buffer 上限・適時 `writeoffStrategyPrincipal` で軽減し、緊急時は `pauseAllocation` で本関数を停止する。非 Underlying・非 position reward token の `Strategy.sweepRewardToken` は別資産の Treasury 集約であり、Vault buffer / backing 会計を直接動かさない
- **ガードレール（実装上の状態変数名）**:
  - `allocatorCooldown`（`allocate` に適用。`lastAllocatorTime` を最終実行時刻として使用。**`Strategy.sendToVault` はクールダウン対象外**＝ユーザー redeem 起因の buffer 補充は即応性が要求されるため）
  - `allocateMaxMove`（**`allocate()` の 1 回あたり buffer→Strategy 移動上限**。`Strategy.sendToVault` には適用しない）
  - `pausedAllocation`（GUARDIAN が止められる。**適用範囲は `allocate()` と `transferYieldToTreasury()`**＝Vault から Strategy / Treasury へ出る outbound 操作。`Strategy.sendToVault` / `Strategy.sendProfitToVault` は pause 対象外＝回収方向は資金を Vault buffer へ戻す安全側の操作のため）。**緊急時の経路**: `pausedAllocation = true` で outbound を止めた状態でも、GUARDIAN は `emergencyDisableStrategy`（即時無効化）、WRITEOFF_ROLE は `writeoffStrategyPrincipal`、ALLOCATOR は `Strategy.sendToVault` / `Strategy.sendProfitToVault` による回収を継続でき、「新規配分・Treasury 流出を止めつつ段階的回収」が実現可能
  - `strategyValuationMaxAge`（valuation failure 時の last-good cache TTL。0 で fallback 無効）。通常運用では keeper / monitoring が `refreshStrategyValuation` と `getStrategyStatuses` を監視し、stale 近接時は GOV/ALLOCATOR runbook で refresh・pause・個別停止・cache invalidation を判断する

### AUM 評価と収益化（取りすぎ）リスク（[VAULT-FR-007](#vault-fr-007-transferyieldtotreasury収益の-treasury-送付)）

- `estimatedTotalUnderlying()` が過大評価だと `transferYieldToTreasury` の `surplus = M - L_effective` が水増しされる恐れ。
- **ガードレール**:
  - 各 Strategy 実装で保守的評価（引出し摩擦・ペナルティを差し引く）。Vault は `A = totalUnderlying()` と `M = managedUnderlying` の Strategy 部分をどちらも live `min(estimatedTotalUnderlying, principal)` で評価し、未実現の「見かけ収益」を `transferYieldToTreasury` の対象に含めない。valuation failure 時、`A` は bounded cache を使い得るが、`M` は cached value や部分合計に対して送金せず全体を 0 とする。さらに `M` は protected backstop reserve を除外する
  - `pendingWithdrawals` を負債側（`L_effective`）に加算し claim 未受領分を Treasury に流出させない
  - **送金は buffer を上限**（[VAULT-FR-007](#vault-fr-007-transferyieldtotreasury収益の-treasury-送付)）。`transferYieldToTreasury` は手元の buffer 余剰しか送らず（実在しない資産は送れない）、収益実現は `Strategy.sendProfitToVault`（`realizedYield()` 上限）＋ Strategy 側の Vault 残高差分計上（yield-only direct transfer）が担う。`min(est, principal)` は est > principal の前計上を防ぐが、**損失が est に反映されず（または writeoff 遅延で）est が真の回収可能額を上回る**場合は surplus 過大評価による取りすぎが残るため、適時 writeoff と保守評価で軽減する
  - 非 Underlying・非 position reward token（Aave incentives / Merkl 等）は `estimatedTotalUnderlying()` と `totalUnderlying()` に含めず、`transferYieldToTreasury` の対象外とする。報酬を backing 修復へ使う場合は、別途 Underlying に換金して `backstopDeposit` 等で明示的に補填する。position / receipt / accounting token は派生 Strategy の protected token として reward sweep を拒否する
  - `sendProfitToVault` / `transferYieldToTreasury` は権限付き（ALLOCATOR）を恒久方針として運用監視する（permissionless 化は行わない、[VAULT-TBD-004](#14-未決事項tbd)）

### 遅延償還（WithdrawRequest）の受容済み既知リスクと運用対処

- **先着総取りの公平性**: 大口 redeem がバッファを瞬時に枯渇させ、後続ユーザーが全額遅延に回ることがある。pro-rata 按分は epoch / batch queue 化で監査面積を増やし、buffer 十分時の 1 Tx 即時完結を全ユーザーから奪う一方、先着インセンティブ自体を解消しないため不採用とする。backing 毀損時の常時自動 pro-rata も採用せず、まず [VAULT-FR-014](#vault-fr-014-pause--unpause緊急停止) の止血と [VAULT-FR-017](#vault-fr-017-backstopdepositdtoken-を-mint-しない補填入金) の補填で 1:1 維持を図る。恒久損失が確定した場合の按分だけを governance 判断に留保する。
- **claim 時の競争条件**: バッファ回復の瞬間は claim と新規 redeem が早い者勝ちで競合する（Bot 有利な構造）。redeem 即時パスで `pendingWithdrawals` を先取り予約する earmark は、`buffer <= pendingWithdrawals` の間に全新規 redeem をキューへ送り、未 claim request が即時容量を恒久的に減らし、ストレス時の Redemption 裁定を鈍らせるため Day-1 では採用しない。競争条件を受容したうえで、ALLOCATOR は `B_target`（`pendingWithdrawals` 全額を含む、[VAULT-FR-004](#vault-fr-004-allocatebuffer-余剰を-strategy-へ配分)）までの buffer 補充を速やかに行い、未 claim 滞留時間（`WithdrawRequested` − `WithdrawClaimed`）と claim の `InsufficientBuffer` revert 反復を監視する。本番で claim 飢餓（補充後も成熟 request が反復的に先取りされる事象）が観測された場合に限り、earmark（成熟分限定方式を含む）を再評価する。
- **古い request の滞留**: 失効＝請求権毀損型の Expiry は不採用。未 claim request の `pendingWithdrawals` 計上は `L_effective` / `B_target` に対する正しい負債計上であり会計を歪めない（滞留コストは当該額の運用機会損失に限られる）。ただし将来、[§11](#11-イベント監視要件evt) の滞留モニタリングで遊休予約 buffer の実害が顕在化した場合に限り、**非没収型の予約解除**の導入可否を再評価する。この方式は owner の請求権と `L_effective` への負債計上を維持し、stale request を `B_target` の buffer 予約からのみ外す。失効分を treasury 等へ没収してはならず、予約解除後も claim は永続する。

> Zapper 連携時の UX 残課題（requestId 伝達等）は [Zapper 要件定義](./Zapper.md) を参照。

### blacklistable Underlying（USDC 等）の既知挙動

- USDC は blacklistable token であり、`transfer` / `transferFrom` が blacklist 状態で revert し得る。
- Vault は batch payout / batch claim を持たないため、blacklist された受領者がいても他ユーザーの redeem / claim をまとめて止める構造ではない。
- buffer 十分時の `redeem` で `_receiver` への `safeTransfer` が revert した場合、tx 全体が revert し、dToken burn や request 作成は巻き戻る。
- `claim` で request owner への `safeTransfer` が revert した場合、`claimed=true` と `pendingWithdrawals -= amount` は巻き戻り、request は未 claim のまま残る。blacklist 解除または別運用判断後に再試行する。
- `claimTo` のような代替受領者指定は現時点では提供しない。token issuer の blacklist を迂回する挙動になり得るため、導入する場合は別途 governance / legal / compliance レビューを要する。

### エラーカタログ

| エラー | 契機 |
| --- | --- |
| `Paused` | `pausedDeposit` での deposit／`pausedRedeem` での redeem/redeemWithPermit／`pausedClaim` での claim／`pausedAllocation` での allocate/transferYieldToTreasury（[VAULT-FR-001](#vault-fr-001-depositunderlying--dtoken)〜[VAULT-FR-004](#vault-fr-004-allocatebuffer-余剰を-strategy-へ配分) / [VAULT-FR-006](#vault-fr-006-claimwithdrawrequest-の遅延償還受領) / [VAULT-FR-007](#vault-fr-007-transferyieldtotreasury収益の-treasury-送付) / [VAULT-FR-014](#vault-fr-014-pause--unpause緊急停止)） |
| `UnderlyingNotSet` | Vault の Underlying 未設定（`whenUnderlyingReady` / `addStrategy`） |
| `UnderlyingMismatch` | Vault / dToken の Underlying 不一致（`whenUnderlyingReady` / `setUnderlying` / `addStrategy`、dToken 未初期化を含む） |
| `UnderlyingAlreadySet` | `setUnderlying` の二度目呼出（[VAULT-FR-011](#vault-fr-011-setunderlying後付け確定一度限り)） |
| `UnderlyingNotAllowed` | `initialize` / `setUnderlying` で dToken allowlist 未承認の Underlying を指定 |
| `ZeroAmount` | `_underlyingAmount == 0` / `_dTokenAmount == 0`（deposit/redeem/redeemWithPermit/backstopDeposit/releaseBackstopToBuffer） |
| `ZeroAddress` | `initialize` の `_dToken`/`_treasury`/`_admin`、`redeem` / `redeemWithPermit` の `_receiver`、`setUnderlying`、`setTreasury` のゼロアドレス |
| `InvalidDTokenAmount` | `redeem` / `redeemWithPermit` で Underlying base unit に exact 対応しない dToken amount を指定 |
| `PermitFailed` | `redeemWithPermit` で permit が失敗し、かつ Vault への既存 allowance が `_dTokenAmount` 未満 |
| `NotContract` | `initialize` の `_dToken`、`addToWhitelist` / `addStrategy` の Strategy が EOA または未デプロイアドレス |
| `CapExceeded`（dToken 側） | deposit 時の dToken cap 超過（[DTKN-FR-004](./dToken.md)） |
| `CooldownNotMet` | `allocate()` の `allocatorCooldown` 未経過（[VAULT-FR-004](#vault-fr-004-allocatebuffer-余剰を-strategy-へ配分)） |
| `InvalidBufferConfig` | `setBufferConfig` で `_targetBps > 10000`（[VAULT-FR-012](#vault-fr-012-gov-設定-settersetbufferconfig--setallocatorconfig--setstrategyvaluationmaxage--setwithdrawdelay--settreasury)） |
| `NotRegisteredStrategy` | 未登録 Strategy による `receiveFromStrategy`（[VAULT-FR-005](#vault-fr-005-receivefromstrategystrategy--vault-の-push-受入)） |
| `NotWhitelisted` | `addStrategy` で whitelist 未承認（[VAULT-FR-008](#vault-fr-008-strategy-whitelist登録解除addtowhitelist--removefromwhitelist--addstrategy--removestrategy)） |
| `StrategyAlreadyExists` | `addStrategy` で既登録 |
| `TooManyStrategies` | `addStrategy` 時に `strategies.length >= MAX_STRATEGIES`（`MAX_STRATEGIES = 32`） |
| `WeightExceedsBps` | `addStrategy` / `updateStrategy` で `totalWeightBps` が 10000 超過 |
| `InvalidWeight` | `updateStrategy` で `_enabled == false` かつ `_weightBps > 0`（[VAULT-FR-009](#vault-fr-009-updatestrategy--writeoffstrategyprincipal登録-strategy-の調整と元本毀損確定)） |
| `StrategyNotFound` | `updateStrategy` / `writeoffStrategyPrincipal` の対象検証失敗 |
| `StrategyHasPrincipal` | `removeStrategy` で `principal != 0`（[VAULT-FR-008](#vault-fr-008-strategy-whitelist登録解除addtowhitelist--removefromwhitelist--addstrategy--removestrategy)） |
| `StrategyHasAssets` | `removeStrategy` で live `estimatedTotalUnderlying()` が読めない、または `estimatedTotalUnderlying != 0` |
| `RequestNotFound` | `claim` の未発行 ID（既決済 ID は `0` を返す、[VAULT-FR-006](#vault-fr-006-claimwithdrawrequest-の遅延償還受領)） |
| `RequestNotReady` | `claim` を `claimableAt` 前に呼ぶ |
| `InsufficientBuffer` | `claim` 時の buffer 不足（部分 claim 不可・後日再試行） |
| `InsufficientBackstop` | `releaseBackstopToBuffer` の `_amount > backstopBalance()` |
| `InvalidBackingTarget` | `backstopRequiredForRatio` の `_targetRatio > 1e18`（[VAULT-FR-018](#vault-fr-018-backing-ops-views補填運用補助)） |
| `StrategyNotFound` | `getStrategyAt` の範囲外 index（[VAULT-FR-013](#vault-fr-013-view-群bufferbalance--totalunderlying--strategy-列挙)） |

---

## 13. 受け入れ基準・検証計画

各要件の合格条件 = 下表の検証手段を満たすこと（テスト名・実行結果は本書に書かない＝手段の種別まで）。値は [Parameters.md](../../../Parameters.md)、🔵 コア挙動は [Liquity-v2-Core-Spec.md](./Liquity-v2-Core-Spec.md) を参照する。

| ID | 要件（要約） | 検証手段 |
| --- | --- | --- |
| VAULT-FR-001 | deposit（pause/ready/zero・換算・mint） | unit, integration |
| VAULT-FR-002 | redeem（即時／遅延・先着総取り・CEI・exact amount） | unit, integration, invariant=VAULT-INV-002/003/014 |
| VAULT-FR-003 | redeemWithPermit（exact check→permit→burn(self)・各 revert） | unit, integration |
| VAULT-FR-004 | allocate（cooldown/pause/M==0・partial valuation 時の outbound 全停止と自動復旧・cap クランプ・固定 weights・deposit failure skip・exact recovery 不可時のみ全体 revert） | unit, invariant=VAULT-INV-006 |
| VAULT-FR-005 | receiveFromStrategy（登録判定・残高差分・ゼロ短絡） | unit, invariant=VAULT-INV-005 |
| VAULT-FR-006 | claim（permissionless trigger・owner 固定送金・既決済 idempotent return・存在/時刻/buffer・部分不可・無期限・pausedClaim 停止） | unit, invariant=VAULT-INV-004 |
| VAULT-FR-007 | transferYieldToTreasury（M<=L 早期・buffer クランプ・min 評価・backstop 除外） | unit, invariant=VAULT-INV-001/005 |
| VAULT-FR-008 | whitelist/addStrategy/removeStrategy（ガード・Underlying 不変条件・principal==0・live estimatedTotalUnderlying==0・add=GOV / remove=GUARDIAN） | unit, invariant=VAULT-INV-007/008 |
| VAULT-FR-009 | updateStrategy（GOV）/ writeoffStrategyPrincipal（WRITEOFF・weight 不変条件・クランプ） | unit, invariant=VAULT-INV-009 |
| VAULT-FR-010 | initialize（placeholder 化・5 ロール・既定値） | unit, manual |
| VAULT-FR-011 | setUnderlying / whenUnderlyingReady（一度きり・dToken-first・両パス） | unit, invariant=VAULT-INV-010/011, manual |
| VAULT-FR-012 | GOV setter（限定・検証・即時反映） | unit |
| VAULT-FR-013 | View 群（placeholder-safe・index・生値 vs min） | unit, manual |
| VAULT-FR-014 | pause/unpause（GUARDIAN/GOV 非対称・4 系統独立・claim 停止） | unit |
| VAULT-FR-015 | アップグレード（GOV 限定・storage 追記のみ） | unit, manual |
| VAULT-FR-016 | backingRatio（下方専用・liability dust 切り上げ・placeholder-safe） | unit, fork, invariant=VAULT-INV-012/014 |
| VAULT-FR-017 | backstopDeposit / releaseBackstopToBuffer（実着額計上・mint なし・backing 回復・明示解放） | unit, integration, invariant=VAULT-INV-013 |
| VAULT-FR-018 | backing ops views（liability / shortfall / 目標比率補填額・切り上げ） | unit, integration, invariant=VAULT-INV-014 |
| VAULT-FR-019 | emergencyDisableStrategy（GUARDIAN 即時・weight 0 化・backing 不変・再有効化は updateStrategy のみ） | unit, invariant=VAULT-INV-009 |
| VAULT-INV-001..014 | §8 各不変条件 | invariant（§8 記載どおり） |
| VAULT-SEC-001..009 | §9 各セキュリティ要件 | unit, manual |

---

## 14. 未決事項（TBD）

### VAULT-TBD-002

Resolved: `VAULT-FR-002`、`VAULT-FR-006`、[§11](#11-イベント監視要件evt)、[§12](#12-失敗時異常系挙動err) に反映済み。

### VAULT-TBD-003

Resolved: `VAULT-FR-014`、`VAULT-FR-015`、`VAULT-FR-019`、`VAULT-GOV-001`、`VAULT-GOV-004` に反映済み。

### VAULT-TBD-004

Resolved: `VAULT-FR-007`、`VAULT-GOV-003` に反映済み。

---

## 15. 参考資料

- [Product Overview](../Product-Overview.md) — 全体アーキテクチャ・責務分離・コア無改変方針（§4 / §5）
- [dToken 要件定義](./dToken.md) — mint/burn される担保受益権トークン（換算 [DTKN-FR-003](./dToken.md) / cap [DTKN-FR-004](./dToken.md) / [DTKN-FR-006](./dToken.md) / setTokenInfo [DTKN-FR-002](./dToken.md) / permit [DTKN-FR-007](./dToken.md)）
- [Strategy 要件定義](./strategies/Strategy.md) — `IStrategy` / push モデル / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / `emergencyWithdraw`
- [AaveV3Strategy 要件定義](./strategies/AaveV3Strategy.md) — Aave V3 個別 Strategy 実装
- [Oracle 要件定義](./Oracle.md) — PriceFeedProxy（`confirmSource` / timelock の比較対象）
- [Zapper 要件定義](./Zapper.md) — permit 経路 / referral / Sky ingress / removed Flash Loan close surface / UX 残課題
- [Parameters.md](../../../Parameters.md) — 担保別 `bufferTargetBps` / `bufferFloor` / `allocatorCooldown` / `allocateMaxMove` / `withdrawDelay` / mintCap の確定値
- [Liquity-v2-Core-Spec.md](./Liquity-v2-Core-Spec.md) — 🔵 コア（借入 / Redemption / 清算 / Stability Pool）の継承解説
- [要件定義ドキュメント標準](../../../Requirements-Spec-Standard.md) — 本書が従う標準
