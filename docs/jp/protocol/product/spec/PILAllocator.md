# 🟢 PILAllocator / PIL 配分レイヤー 要件定義

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Draft（初期実装あり・パラメータ暫定。Phase-A=admin 配分が本書の主スコープ、Phase-B=投票型配分は方針のみ） |
| Owner | DeltaForesight |
| 対象コントラクト | 🟢 Original: `contracts/src/PILAllocator.sol`（admin 重み配分・非 UUPS / immutable）/ `contracts/src/Interfaces/IInitiative.sol`（本家 `liquity/V2-gov` 互換・4 hook）/ `contracts/src/Interfaces/IDistributionCreator.sol`（Merkl interface）/ `contracts/src/Initiatives/UniV4MerklInitiative.sol`（Merkl 経由 Uniswap v4 配分）/ `contracts/src/JpydfToken.sol` の `requireValidRecipient` view helper |
| 関連ドキュメント | [InterestRouter](./InterestRouter.md)（`IRTR-GOV-003` / `IRTR-TBD-004`＝本レイヤーを recipient として据える上流）/ [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md)（`CORE-AP-FR-007` PIL mint）/ [Treasury](../../roadmap/spec/Treasury.md)（担保運用益＝独立経路・PIL とは別）/ [Governance-Roles-Timelock](../policies/Governance-Roles-Timelock.md)/ [Governance-Token-Design](../../roadmap/initiatives/governance-token/Governance-Token-Design.md)（Phase-B の投票主体・T2 権限境界・発行 gate）/ [Day1-Self-BS-Initial-Liquidity-Plan](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Initial-Liquidity-Plan.md)（運営の自己BSシード流動性）/ [Merkl-Campaign-KPI-Policy](../../roadmap/policies/Merkl-Campaign-KPI-Policy.md)（campaign 採否・KPI・停止条件）/ [Mainnet-Deploy-Env-Freeze-Runbook](../../launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md)（`DeployPILAllocatorPhaseA` activation package）/ [Product-Overview](../Product-Overview.md)（PIL）/ [Architecture Decision Records](../architecture/Architecture-Decision-Records.md)（ADR-004/005）/ [Mainnet Launch Risk Gate](../../launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-003) / [参考調査（Liquity/Nerite/Asymmetry）](../../../engineering/historical-reviews/2026-06-25-PIL-DEX-Allocation-Reference-Liquity-Nerite-Asymmetry.md) |

> 本書は [要件定義ドキュメント標準](../../../Requirements-Spec-Standard.md) に従う。要件 ID は `PILA-*`。
> **Core parity の原則**: 集計利息の SP/PIL 分配・`interestRouter` への mint・immutable 束縛は 🔵 コアの規範（`CORE-AP-*`）であり再仕様化しない。PIL 原資を受ける Forwarder は [InterestRouter](./InterestRouter.md)（`IRTR-*`）が規範。本書は **Forwarder の `recipient` に据える配分レイヤー以降**のみを規定する。
> **マーカー**: 🟢 Original（DeltaForesight 独自・Core の外側に追加。Core 無改変・ARCH-001/004）。

### 0.1 フェーズ用語（重要・他 doc との読み替え）

本書の **Phase-A / Phase-B は「PIL 配分レイヤー内部の段階」** であり、[Product-Overview](../Product-Overview.md) / [InterestRouter](./InterestRouter.md) の **Day-1（mainnet launch）/ Day-2（PIL 配分機構の稼働）とは別軸**である。対応関係は以下。

| 本書の段階 | 内容 | 上流 doc の位置づけ |
| --- | --- | --- |
| **Phase-A** | admin（GOV→Timelock）が initiative 登録・weight 設定。投票なし | `IRTR-GOV-003` / `IRTR-TBD-004` がいう「Day-2 の PIL Distributor / governance」の**初代実体** |
| **Phase-B** | 投票トークン（未確定。DFT 採用時は DFT）の time-weighted 投票で、allowlist 済み initiative 間の weight だけを決定。**本書は方針のみ・別 doc/別監査** | 同上の後継（`VotingAllocator` へ recipient 差替） |

---

## 1. 目的・スコープ・非責務

🔵 コアは集計利息の PIL 残余（`SP_YIELD_SPLIT` を除く 25%）を `interestRouter` へ JPYdf として mint する（`CORE-AP-FR-007`）。[InterestRouter](./InterestRouter.md) の `InterestRouterForwarder` がこれを受け、`route()` で現 `recipient` へ flush する（`IRTR-FR-002`）。本書はその **`recipient` に据える配分レイヤー** を規定し、PIL を **DEX 流動性インセンティブへ配分**する。

設計の中核は **本家 Liquity v2 の構成（`liquity/V2-gov`: `Governance` ＋ `IInitiative` ＋ DEX initiative）を踏襲しつつ、投票部分を Phase-A では admin 設定の weight で代替**することにある。これにより Phase-B（投票トークンは未確定）へ**コア/Forwarder/既存 initiative を無改変のまま** recipient 差替だけで移行できる（ADR-004/005 と同型の「不変な上流＋差替可能な下流」）。

- **本書が規定する**:
  - `PILAllocator` — Forwarder から受けた JPYdf を、登録 initiative へ **admin 設定の weight で按分配分**する受け皿（Phase-A）。本家 `Governance` の epoch / 配分骨格を踏襲し、投票を admin weight で置換する。
  - `IInitiative` — 本家 `liquity/V2-gov` の `IInitiative` と**完全互換**（4 hook）。Phase-B の `VotingAllocator` がそのまま同一 initiative を再利用できるようにする。
  - `UniV4MerklInitiative` — PIL を **Merkl（Angle `DistributionCreator`）経由で Uniswap v4 の JPYdf プールへ**配分する唯一の Phase-A initiative（本家 `UniV4MerklRewards` 移植）。
  - Phase-A → Phase-B 移行・拡張境界（§10）。
- **本書が規定しない（非責務・他文書）**:
  - 集計利息の SP/PIL 分配・`interestRouter` への mint・immutable 束縛 → 🔵 [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md)（`CORE-AP-FR-003/007`）。
  - PIL 原資の受領・`route()`・`recipient` 差替 → [InterestRouter](./InterestRouter.md)（`IRTR-*`）。本書はその下流。
  - **Phase-B（投票型配分）の実装詳細**（投票トークン・staking 方式・epoch 投票・bribe 市場）→ Day-2 の `VotingAllocator` 別 doc / 別監査（投票主体と T2 権限境界の正本は [Governance-Token-Design](../../roadmap/initiatives/governance-token/Governance-Token-Design.md)、方針は §10）。
  - **Curve 系 initiative**（`CurveGaugeInitiative` 等）→ Day-2・**Phase-A 監査スコープ外**（§10・[PILA-GOV-005](#10-ガバナンス運用アップグレード要件gov)）。設計は initiative 非依存で受け入れ可能にする。
  - 担保運用益（Strategy yield）の分配・buyback → [Treasury](../../roadmap/spec/Treasury.md)（PIL とは独立経路）。
  - 運営の自己 B/S によるシード流動性の提供・管理そのもの → [Day1-Self-BS-Initial-Liquidity-Plan](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Initial-Liquidity-Plan.md)（本書のスコープ外）。
  - Merkl campaign の採否、budget、launch KPI、停止条件 → [Merkl-Campaign-KPI-Policy](../../roadmap/policies/Merkl-Campaign-KPI-Policy.md)。
  - 具体パラメータ値（pool id / weight / threshold / Merkl アドレス / blacklist 方式）→ 承認済みactivation packageの`pil-activation-manifest.json`。

---

## 2. 背景・設計方針

### 2.1 出発点（動かせない上流制約）

| # | 事実 | 帰結 |
| --- | --- | --- |
| 1 | PIL 原資は `InterestRouterForwarder` に JPYdf として届き、`route()` で現 `recipient` へ全額 push される（`IRTR-FR-002`）。**受領にコールバックは無い** | 配分ロジックは recipient 側に閉じる。allocator は「叩かれて配る」push 受領＋pull 起動の両構え |
| 2 | `interestRouter` は immutable だが、Forwarder の `recipient` は owner（Timelock）が差替可能（`IRTR-FR-003`） | 配分レイヤーを **再デプロイなしで Phase-A→Phase-B 差替**できる |
| 3 | 本家 `liquity/V2-gov` は `interestRouter = Governance`（投票配分）。jpydf は Day-1 に投票トークンを発行せず、Phase-B の投票主体も未確定（`CORE-AP-TBD-001` / `IRTR` §1） | 投票を admin weight で代替する Phase-A を挟み、Phase-B を特定 token の発行に依存させない |

### 2.2 設計方針

1. **本家構成の踏襲（Phase-B で initiative を無改変流用するため）**: `IInitiative` を本家完全互換（4 hook）にし、`PILAllocator` は本家 `Governance` の epoch / claim 骨格を保ったまま「得票シェア按分」を「admin weight 按分」に置換する。Phase-B では投票トークン非依存の `VotingAllocator`（投票力計算は本家 `Governance` 準拠）に recipient 差替するだけで、**同一 initiative を再利用**する。拘束投票が変更できるのは allowlist 済み initiative 間の weight のみとする。
2. **配分先非依存（initiative 抽象）**: `PILAllocator` は `IInitiative` 越しにしか initiative を触らない。Uniswap v4 / Curve 等の DEX 固有実装を allocator に持ち込まない。Curve 等の追加は **新 initiative の deploy＋登録**で済み、allocator・既存 initiative・コアを無改変に保つ（§10）。
3. **明示配分（treasury sink を持たない）**: active な weight 合計は **0 または `1e18` のみ**とする。部分合計（`0 < Σweight < 1e18`）を許すと permissionless `distribute()` の繰り返しで未割当分の意味が崩れるため禁止する。配分しない期間は `Σweight = 0` とし、treasury/Foundation/reserve に PIL を回したい場合は、その Safe を **1 つの initiative として登録**し weight を与える（本家が grants Safe `defiCollectiveInitiative` を initiative として登録するのと同型）。閾値未満の小額だけ allocator に carry-over する。
4. **bounded 配分ループ**: `distribute()` は登録 initiative 全件を走査するため、Phase-A では `MAX_INITIATIVES = 32` を contract constant として固定する。将来 32 件を超える配分先が必要な場合は、新 allocator を deploy し `forwarder.setRecipient` で差替える。
5. **permissionless 配分・keeper 優先の campaign 作成**: `distribute()` は permissionless（誰でも・keeper 任意）。initiative の `createCampaign()` は `CAMPAIGN_CREATOR` が随時実行でき、一般 caller は `campaignStart` 直前の `CAMPAIGN_CREATION_WINDOW` 内だけ実行できる。Merkl の同一 start 1 campaign 制約による早押し grief を防ぎつつ、keeper 障害時の public fallback を残す。Merkl キャンペーンは固定 `EPOCH_DURATION`（既定 7 日目安）・`startTimestamp = epochEnd` で本家準拠（§6）。
6. **悪性 initiative の隔離**: hook 呼び出しは `safeCallWithMinGas`（最低ガス保証・try 相当）で、1 つの initiative の失敗が他 initiative への配分を止めない（本家準拠）。hook 成否はイベントに出し、監視側で失敗を検知できるようにする。
7. **非 UUPS・差替移行**: `PILAllocator`・各 initiative は immutable（非 upgradeable）。挙動変更や Phase-B 移行は**新コントラクト deploy＋`forwarder.setRecipient` 差替**で行う（ADR-001 整合・監査単純性。`IRTR-GOV-004` と同方針）。
8. **権限分離**: 登録・weight・pause-unpause は GOV→共通 Timelock。緊急 pause のみ GUARDIAN 即時。owner は 2-step・renounce 無効（`IRTR-FR-004` と同型）。
9. **活性化非依存**: weight 未設定・initiative 0 件でも安全に滞留する（[PILA-INV-004](#8-不変条件inv)）。

### 2.3 本家との対応（admin が投票を代替）

| 本家 `liquity/V2-gov` | 本書 Phase-A（`PILAllocator`） | Phase-B（`VotingAllocator`・別 doc） |
| --- | --- | --- |
| `Governance.sol`（投票配分） | `PILAllocator`（**admin weight 配分**） | `VotingAllocator`（投票トークン未確定・time-weighted 投票） |
| `registerInitiative`（permissionless・fee＋閾値） | **admin（Timelock）登録** | **T1 として JIP 承認した allowlist のみ**（拘束投票では変更不可） |
| 得票シェア `votes_i/Σvotes × boldAccrued` | **admin weight `weight_i/1e18 × balance`** | 得票シェア |
| 未請求分を recycle | **weight 全 0 / 閾値未満を carry-over**。active 時は `Σweight = 1e18` | 未請求分を recycle |
| `IInitiative`（4 hook） | 同（完全互換） | 同 |
| `UniV4MerklRewards` / `CurveV2GaugeRewards` | `UniV4MerklInitiative` のみ | Curve 等を追加 |

---

## 3. 用語・外部依存・前提

### 3.1 用語

| 用語 | 意味 |
| --- | --- |
| PIL | Protocol Incentivised Liquidity。借入金利残余（25%）を原資とする JPYdf 流動性インセンティブ |
| initiative | PIL の配分先 1 単位。`IInitiative` を満たす**任意のアドレス**（DEX 配分コントラクト／単なる Safe いずれも可）。粒度は **1 アドレス = 1 配分先**（DEX/プロトコル単位ではなく、Curve の USDC プールと USDT プールは別 initiative＝[参考調査](../../../engineering/historical-reviews/2026-06-25-PIL-DEX-Allocation-Reference-Liquity-Nerite-Asymmetry.md)） |
| weight | initiative ごとの配分比率（1e18 固定小数）。合計は **0 または `1e18`**。reserve/Treasury 分も initiative として明示する |
| `distribute()` | allocator 保持 JPYdf を weight 按分し各 initiative へ push する permissionless 関数 |
| `onClaimForInitiative` | allocator が initiative へ配分後に呼ぶ通知 hook（本家 `IInitiative`） |
| `onAfterAllocateLQTY` | 本家 `Governance` が「ユーザーが投票配分を変更するたび」に initiative へ呼ぶ hook。initiative 側で「誰がどの epoch にいくら投票したか」を記録し、bribe 按分等の原資にする。**Phase-A（投票なし）では未使用**だが、Phase-B 流用のため IF に保持（[PILA-FR-102](#pila-fr-102-iinitiative-本家完全互換4-hook)） |
| epoch | 配分・キャンペーンの固定周期。`EPOCH_START` / `EPOCH_DURATION` は immutable（本家 `Governance` と同シグネチャ） |
| Merkl | Angle Labs の `DistributionCreator`。reward token を渡すと off-chain 計算でプール LP へ配分するキャンペーンを作る（本家 `UniV4MerklRewards` が利用） |
| campaign blacklist | Merkl キャンペーンで incentive 対象外にするアドレス。**Day-1 は空（対象者なし）**。本家は自社 Funds Safe 1 件を blacklist |
| campaign creator | `UniV4MerklInitiative` の `createCampaign()` を早期実行できる運用 keeper / Safe。一般 caller は fallback window 内のみ実行可能 |
| campaign creation window | `campaignStart` 直前に一般 caller へ `createCampaign()` を開放する期間。keeper 障害時の liveness を確保するための public fallback |

### 3.2 外部依存（信頼する外部）

- **InterestRouterForwarder（🟢 DF・上流）** — PIL 原資の唯一の供給元。`route()` で push される（`IRTR-FR-002`）。allocator は Forwarder を呼ばない。
- **JpydfToken（JPYdf・🔵 Core）** — 配分対象。標準 ERC-20（転送フックなし）に依拠（[PILA-SEC-005](#9-セキュリティ要件sec)）。
- **Merkl `DistributionCreator`（Angle Labs・Ethereum mainnet）** — `UniV4MerklInitiative` がキャンペーン生成に用いる**新規の信頼境界**。off-chain 計算・claim・手数料・利用規約（`acceptConditions`）に依存。本家 Liquity と同等の信頼前提を採用（[PILA-SEC-001](#9-セキュリティ要件sec) / [PILA-TBD-004](#pila-tbd-004)）。
- **共通 TimelockController（🟢 DF）** — allocator の `owner`。登録・weight・unpause は同 Timelock の待機対象（[Governance-Roles-Timelock](../policies/Governance-Roles-Timelock.md)）。
- **GUARDIAN（🟢 DF）** — `distribute()` の緊急 pause（即時）。

### 3.3 前提

- allocator は JPYdf のみを正規原資として扱う。誤送トークン rescue は持たない（[IRTR](./InterestRouter.md) と同方針・[PILA-TBD-005](#pila-tbd-005) 範囲外）。
- Phase-A は投票トークン・staking・投票・bribe を**前提にしない**。Phase-B の投票トークンは未確定であり、DFT 採用時に限り DFT を用いる（[Governance-Token-Design](../../roadmap/initiatives/governance-token/Governance-Token-Design.md)）。
- Uniswap v4 / Merkl initiativeを有効化するchainは、当該releaseのDecision / Manifestへ固定する（`SYS-CON-005`）。現行のEthereum mainnet候補を他environmentへ暗黙に流用しない。

---

## 4. アクター・ロール・信頼境界

| アクター | 操作 | 信頼境界 |
| --- | --- | --- |
| **InterestRouterForwarder（🟢 上流）** | `route()` で PIL を allocator へ push | 受領のみ・コールバックなし |
| **owner**（= 共通 TimelockController） | `registerInitiative` / `unregisterInitiative` / `setWeights` / unpause / 2-step ownership | 特権。配分先・比率の変更は同 Timelock の待機対象。renounce 無効 |
| **GUARDIAN** | `distribute()` の pause（即時） | 可逆 fail-safe のみ。資金移動権限を持たない |
| **campaign creator** | initiative `createCampaign()` の早期実行 | 限定信頼。campaign 作成タイミングの運用者。配分先・比率・poolId には裁量なし |
| **distribute / public fallback 呼出者（任意）** | `distribute()` / fallback window 内の `createCampaign()` | 信頼不要。配分先・比率に裁量なし（登録 initiative と weight に従うのみ） |
| **initiative（`UniV4MerklInitiative` 等）** | allocator から JPYdf 受領→ DEX へ配分 | 限定信頼。受領額は weight 上限まで。登録時に JPYdf の外部 transfer 可能 recipient であることを検証し、hook 失敗は allocator をブリックできない（`safeCallWithMinGas`） |
| **Merkl `DistributionCreator`** | initiative からキャンペーン amount を pull | 限定信頼（新規境界）。approve は都度・キャンペーン額に限定（[PILA-SEC-003](#9-セキュリティ要件sec)） |

- **ロール分離の意図**: 「配分先・比率を変える権限（owner=Timelock・遅延付き）」と「資金を配る操作（distribute=permissionless・裁量なし）」を分離。owner 鍵侵害でも即時資金奪取経路を持たせない（`IRTR-SEC-001` と同型）。

---

## 5. インターフェース仕様（terse・非規範。規範は §6）

### 5.1 PILAllocator

| 関数 / 要素 | 可視性 | 要約 | 規定要件 |
| --- | --- | --- | --- |
| `constructor(IJpydfToken _jpydf, uint256 _epochStart, uint256 _epochDuration, uint256 _minDistribute, address _owner, address _guardian)` | — | immutable 設定・ゼロ拒否・fail-fast | PILA-FR-001 |
| `EPOCH_START()` / `EPOCH_DURATION()` / `epoch()` / `epochStart()` | external view | 本家 `Governance` 互換の epoch IF | PILA-FR-002 |
| `MAX_INITIATIVES()` | external view | 登録 initiative 件数上限（32） | PILA-FR-003 |
| `registerInitiative(address)` | external（onlyOwner） | initiative 登録＋`onRegisterInitiative` hook | PILA-FR-003 |
| `unregisterInitiative(address)` | external（onlyOwner） | 登録解除＋`onUnregisterInitiative` hook・weight 0 化 | PILA-FR-004 |
| `setWeights(address[],uint256[])` | external（onlyOwner） | weight 一括設定（`Σ = 0` または `1e18`・登録済みのみ） | PILA-FR-005 |
| `distribute()` | external（permissionless・nonReentrant） | 保持 JPYdf を weight 按分し各 initiative へ push＋hook | PILA-FR-006 |
| `pause()` / `unpause()` | external（GUARDIAN / onlyOwner） | `distribute()` の緊急停止／解除 | PILA-FR-008 |
| `setGuardian(address)` | external（onlyOwner） | GUARDIAN の差替 | PILA-FR-008 |
| `transferOwnership` / `acceptOwnership` / `renounceOwnership` | external | 2-step・renounce 無効（`IRTR-FR-004` と同型） | PILA-FR-010 |
| views（initiatives / weights / pending / epoch） | external view | 監視・subgraph | PILA-FR-009 |

### 5.2 IInitiative（本家 `liquity/V2-gov` 完全互換）

| 関数 | 呼出元 | Phase-A での使用 |
| --- | --- | --- |
| `onRegisterInitiative(uint256 atEpoch)` | allocator | 使用（登録時） |
| `onUnregisterInitiative(uint256 atEpoch)` | allocator | 使用（解除時） |
| `onAfterAllocateLQTY(uint256,address,UserState,Allocation,InitiativeState)` | allocator/voting | **未使用**（投票なし）。Phase-B 流用のため保持 |
| `onClaimForInitiative(uint256 claimEpoch, uint256 amount)` | allocator | 使用（配分後通知） |

### 5.3 UniV4MerklInitiative

| 関数 / 要素 | 可視性 | 要約 | 規定要件 |
| --- | --- | --- | --- |
| `constructor(...)` | — | allocator metadata / JPYdf / Merkl / poolId / weights / threshold / epoch を immutable 設定・`acceptConditions()` | PILA-FR-201 |
| `createCampaign()` | external（creator / fallback window） | 保持 JPYdf を Merkl Uniswap v4 キャンペーンに投入（都度 approve） | PILA-FR-202 |
| `nextCampaignStart()` / `publicCampaignCreationStart()` / `canCreateCampaign(address)` | external view | 次 campaign start、public fallback 開始時刻、caller 別の作成可否（残高・重複 campaign も加味）の監視・UI 補助 | PILA-FR-202 |
| `getCampaignData()` | external view | poolId / weights / blacklist の Merkl campaignData 生成 | PILA-FR-203 |
| `onRegister/onUnregister/onAfterAllocateLQTY/onClaimForInitiative` | external | no-op hook（Merkl 連携は `createCampaign` に分離） | PILA-FR-204 |

---

## 6. 機能要件（FR）

### 6.1 PILAllocator

### PILA-FR-001: constructor（配分レイヤーの確立・fail-fast）
- **Type**: Functional ｜ **Source**: §2.2 / `IRTR-TBD-004`
- **シグネチャ**: `constructor(IJpydfToken _jpydf, uint256 _epochStart, uint256 _epochDuration, uint256 _minDistribute, address _owner, address _guardian)`
- **目的**: 配分対象トークン（JPYdf）・epoch 基準・最小配分額・owner・guardian を確立する。
- **権限**: デプロイ時のみ。
- **事前条件（Checks）**: `_jpydf != 0` / `_jpydf.code.length > 0` / `_owner != 0` / `_guardian != 0`（`ZeroAddress`）/ `_epochStart <= block.timestamp` / `_epochDuration > 0` / `_minDistribute > 0` / `_epochDuration <= type(uint32).max`。
- **動作（Effects）**: immutable に `jpydfToken`・`EPOCH_START`・`EPOCH_DURATION`・`MIN_DISTRIBUTE` を保存、`owner`・`guardian` 設定、初期イベント発火。registry は空で開始。
- **設計上のポイント**: 初期値は deploy env 由来で未指定なら deploy 停止。epoch IF は initiative（`UniV4MerklInitiative`）が参照するため本家 `Governance` と同シグネチャにする（Phase-B 流用）。
- **Verification**: unit。

### PILA-FR-002: epoch インターフェース（本家互換）
- **Type**: Functional ｜ **Source**: §2.2（Phase-B 流用）
- **シグネチャ**: `EPOCH_START() / EPOCH_DURATION() / epoch() / epochStart()`
- **目的**: initiative が campaign 期間（`startTimestamp = epochEnd`）を決めるための epoch 基準を提供する。本家 `Governance` と同一シグネチャ。
- **権限**: view・permissionless。
- **動作**: `epoch() = (block.timestamp − EPOCH_START)/EPOCH_DURATION + 1`、`epochStart() = EPOCH_START + (epoch()−1)·EPOCH_DURATION`（本家準拠）。
- **設計上のポイント**: Phase-A の `distribute()` 自体は epoch ゲートしない（任意時点で現残高を按分）。epoch はキャンペーン期間整列のためにのみ initiative が使う。
- **Verification**: unit。

### PILA-FR-003: registerInitiative（admin 登録）
- **Type**: Functional / Governance ｜ **Source**: §2.2 / §2.3
- **シグネチャ**: `registerInitiative(address initiative)`
- **目的**: 配分先 initiative を登録する。
- **権限**: `onlyOwner`（共通 Timelock 経由）。**Phase-A は admin 登録**。Phase-B でも initiative の登録・allowlist 変更は T1 として JIP 承認を経て行い、拘束投票に登録権限を与えない。
- **事前条件（Checks）**: `initiative != 0`／未登録であること（重複は `AlreadyRegistered`）／登録済み件数が `MAX_INITIATIVES` 未満／`JpydfToken.transfer` の recipient 制限と同等の検証で JPYdf 外部 transfer 可能なアドレスであること（少なくとも JPYdf token 自身・`CollateralRegistry`・登録済み `TroveManager` / `StabilityPool` / `BorrowerOperations` / `ActivePool` ではない）。
- **動作（Effects）**: registry に追加（weight は 0 初期）、`safeCallWithMinGas` で `onRegisterInitiative(epoch())` を best-effort 呼出、`InitiativeRegistered(initiative, epoch, hookSucceeded)` を発火。
- **revert**: 非 owner → `Unauthorized`／重複 → `AlreadyRegistered`／ゼロ → `ZeroAddress`／上限超過 → `TooManyInitiatives`。
- **設計上のポイント**: initiative は JPYdf の外部 transfer 可能 recipient であればコントラクト / Safe / EOA のいずれも可（Safe を treasury 受け皿として登録する用途を含む＝§2.2-3）。登録時検証は `distribute()` 内の `safeTransfer` が JPYdf recipient blacklist で revert し、全 initiative 配分を止める事故を防ぐための fail-fast である。実装は `JpydfToken.requireValidRecipient` view helper で同等性を担保する。hook 失敗は登録自体を止めない（本家準拠）。
- **Verification**: unit。

### PILA-FR-004: unregisterInitiative（admin 解除）
- **Type**: Functional / Governance ｜ **Source**: §2.2
- **シグネチャ**: `unregisterInitiative(address initiative)`
- **目的**: 登録 initiative を配分対象から外す。
- **権限**: `onlyOwner`（Timelock）。
- **事前条件（Checks）**: 対象 initiative が登録済みであり、`weightOf[initiative] == 0`。weighted initiative を解除する場合は先に `setWeights` で残る initiative / reserve initiative へ `1e18` を再配分する。
- **動作（Effects）**: registry から論理削除、`safeCallWithMinGas` で `onUnregisterInitiative(epoch())` を呼出、`InitiativeUnregistered(initiative, epoch, hookSucceeded)` を発火。
- **設計上のポイント**: 解除操作で `0 < Σweight < 1e18` を作らない。配分停止したい場合は全 weight を 0 にする。
- **Verification**: unit。

### PILA-FR-005: setWeights（admin 配分比率）
- **Type**: Functional / Governance ｜ **Source**: §2.2 / §2.3
- **シグネチャ**: `setWeights(address[] initiatives, uint256[] weights)`
- **目的**: initiative ごとの配分比率（1e18 固定小数）を一括設定する。
- **権限**: `onlyOwner`（Timelock）。
- **事前条件（Checks）**: 配列長一致／全要素が登録済み initiative／重複なし／更新後の `Σweight` が **0 または `1e18`**（それ以外は `InvalidTotalWeight`）。
- **動作（Effects）**: 各 initiative の weight を更新、`WeightsUpdated` を発火。
- **設計上のポイント**: active 配分時は全量の行き先を明示する。treasury / reserve に回したい分はその Safe を initiative 登録して weight を与える（本家 grants Safe と同型）。**別途の treasury sink を持たない**（[PILA-INV-002](#8-不変条件inv)）。
- **Verification**: unit, invariant=PILA-INV-002。

### PILA-FR-006: distribute（PIL の weight 按分配分・permissionless）
- **Type**: Functional ｜ **Source**: §2.2 / 本家 `Governance.claimForInitiative`
- **シグネチャ**: `distribute() returns (uint256 total)`
- **目的**: allocator 保持 JPYdf を登録 initiative へ weight 按分で push する。
- **権限**: permissionless（誰でも・keeper 任意）。pause 中は不可。
- **事前条件（Checks）**: pause でないこと。`bal = balanceOf(this)` が閾値 `minDistribute` 未満なら no-op（carry-over）。
- **動作（Effects）**:
  1. `bal = jpydfToken.balanceOf(address(this))`；`bal < minDistribute` または登録 initiative 0 件 → `return 0`（滞留）。
  2. 各登録 initiative `i`（最大 `MAX_INITIATIVES=32`）: `amount_i = bal × weight_i / 1e18`。`amount_i > 0` なら `jpydfToken.safeTransfer(initiative_i, amount_i)` → `safeCallWithMinGas(onClaimForInitiative(epoch(), amount_i))` → `Distributed(initiative_i, amount_i, epoch(), hookSucceeded)` を発火。
  3. active weight 合計は `1e18` のため、丸め dust 以外の未割当残余を作らない。weight 全 0 / 閾値未満は allocator に滞留する。
- **revert / 早期 return**: pause → `Paused`；閾値未満/0 件 → `return 0`。
- **設計上のポイント**: 本家の「未請求分は recycle」を admin 版で再現。送金後に hook を呼ぶ順（資金は initiative に着金済みで、hook 失敗でも `createCampaign` で後追い実行できる）。1 initiative の hook 失敗が他を止めない（`safeCallWithMinGas`・[PILA-INV-003](#8-不変条件inv)）。CEI＋`nonReentrant`（[PILA-SEC-005](#9-セキュリティ要件sec)）。
- **Verification**: unit, invariant=PILA-INV-001/002/003, integration（Forwarder.route→distribute→initiative→Merkl）。

### PILA-FR-007: 閾値・carry-over（滞留の一元化）
- **Type**: Functional ｜ **Source**: §2.2-3 / 本家 `CurveV2GaugeRewards.remainder`
- **目的**: 小額配分による無駄（ガス・Merkl 手数料）を避け、閾値未満または未活性時の PIL を次回へ繰越す。treasury sink との二重定義を持たない。
- **要件**:
  - `distribute()` は `bal < minDistribute` で no-op（[PILA-FR-006](#pila-fr-006-distributepil-の-weight-按分配分permissionless)）。残余は allocator 滞留＝次回再評価。
  - `0 < Σweight < 1e18` は禁止。配分停止は `Σweight = 0`、active 配分は `Σweight = 1e18`。
  - **activation-agnostic**: initiative 0 件 / weight 全 0 なら全 PIL が allocator に滞留し、holding recipient での滞留と同じ資金移動結果になる（[PILA-INV-004](#8-不変条件inv)）。
- **設計上のポイント**: `minDistribute`の候補とfreeze境界は [PILA-TBD-002](#pila-tbd-002)、承認済み投入値はactivation packageの`pil-activation-manifest.json`が持つ。本家 `Governance.MIN_ACCRUAL` は `1000e18` で、未満を epoch 原資にせず carry-over する。同型に、PILAllocator は閾値未満を配分せず滞留させる。
- **Verification**: unit, invariant=PILA-INV-004。

### PILA-FR-008: pause / unpause / setGuardian（緊急停止）
- **Type**: Functional / Governance ｜ **Source**: §2.2-7
- **権限**: `pause()` = GUARDIAN（即時）／`unpause()`・`setGuardian(address)` = `onlyOwner`（共通 Timelock 経由）。
- **動作**: pause 中は `distribute()` を不可にする（PIL の受領＝Forwarder からの着金は継続）。`setGuardian` は緊急停止担当を差し替える。`Paused`/`Unpaused`/`GuardianUpdated` を発火。
- **設計上のポイント**: 可逆 fail-safe を GUARDIAN に、解除を Timelock に分離（`SYS-NFR-002` 例外運用と整合）。
- **Verification**: unit。

### PILA-FR-009: View 群
- `MAX_INITIATIVES()` / `initiatives()` / `initiativeCount()` / `initiativeAt(uint256)` / `registeredInitiatives(address)` / `weightOf(address)` / `pendingDistributable()`（次回 distribute 見込み）/ epoch views。監視・subgraph・運用 console 用。
- **Verification**: unit。

### PILA-FR-010: ownership（2-step・renounce 無効）
- **Type**: Governance / Security ｜ **Source**: `IRTR-FR-004`（同型）
- **要件**: `transferOwnership`（onlyOwner・`0` で pending 取消）/ `acceptOwnership`（onlyPendingOwner）/ `renounceOwnership` は常に revert（`RenounceOwnershipDisabled`）。handover で共通 Timelock へ移譲。
- **設計上のポイント**: owner 不在による配分能力の恒久 strand を防ぐ（`IRTR-FR-004` と同方針）。
- **Verification**: unit。

### 6.2 IInitiative

### PILA-FR-101: IInitiative（本家完全互換・4 hook）
- **Type**: Functional ｜ **Source**: 本家 `liquity/V2-gov:src/interfaces/IInitiative.sol`
- **目的**: Phase-A の `PILAllocator` と Phase-B の `VotingAllocator` の双方が**同一 initiative を呼べる**よう、本家 `IInitiative` と完全互換の 4 hook を定義する。
- **要件**: `onRegisterInitiative(uint256)` / `onUnregisterInitiative(uint256)` / `onAfterAllocateLQTY(uint256,address,UserState,Allocation,InitiativeState)` / `onClaimForInitiative(uint256,uint256)`。caller 制限の有無は initiative 実装ごとに定義する。`UniV4MerklInitiative` は hook が no-op のため caller 制限を持たない。
- **Verification**: unit / static（本家 IF とのシグネチャ一致）。

### PILA-FR-102: onAfterAllocateLQTY の保持（Phase-A 未使用）
- **Type**: Functional ｜ **Source**: §3.1（用語）
- **目的**: `onAfterAllocateLQTY` は本家で「ユーザーの投票配分変更ごとに per-user/total の投票量を initiative に記録させる」通知 hook（bribe 按分等の原資）。**Phase-A は投票が無いため `PILAllocator` はこれを呼ばない**が、Phase-B の `VotingAllocator` がそのまま呼べるよう IF に保持し、Phase-A initiative は no-op 実装にする。
- **設計上のポイント**: これにより Phase-A で書いた initiative（`UniV4MerklInitiative`）を Phase-B でも無改変で再利用できる（§2.2-1）。
- **Verification**: static（IF 互換）。

### 6.3 UniV4MerklInitiative

### PILA-FR-201: constructor（Merkl 連携の確立）
- **Type**: Functional ｜ **Source**: 本家 `UniV4MerklRewards`
- **目的**: 配分対象（JPYdf）・対象 Uniswap v4 プール・配分重み・閾値を immutable 固定し、Merkl を利用可能にする。
- **事前条件（Checks）**: `_allocator != 0` / `_jpydfToken != 0 && code.length > 0` / `_merklDistributionCreator != 0 && code.length > 0` / `_campaignCreator != 0` / `_campaignJpydfAmountThreshold > 0` / `0 < _campaignCreationWindow < _epochDuration` / `_uniV4PoolId != 0` / `_epochStart <= block.timestamp` / `_epochDuration > 0` / `_epochDuration <= type(uint32).max` / `WEIGHT_FEES + WEIGHT_TOKEN0 + WEIGHT_TOKEN1 == 10000`（本家準拠）。
- **動作（Effects）**: immutable に `allocator`（metadata）・`jpydfToken`・`merklDistributionCreator`・`CAMPAIGN_CREATOR`・`CAMPAIGN_CREATION_WINDOW`・`UNIV4_POOL_ID`・各 weight・`CAMPAIGN_JPYDF_AMOUNT_THRESHOLD`・`EPOCH_START`/`EPOCH_DURATION` を保存。Merkl `DistributionCreator.acceptConditions()` を実行（署名なしキャンペーン作成の前提）。**JPYdf の max approve は行わない**（都度 approve＝[PILA-SEC-003](#9-セキュリティ要件sec)）。
- **設計上のポイント**: 1 instance = 1 プール（poolId immutable）。複数プールは複数 instance を deploy・登録する（§10 拡張）。
- **Verification**: unit / fork（Merkl）。

### PILA-FR-202: createCampaign（Merkl Uniswap v4 キャンペーン生成・creator / fallback）
- **Type**: Functional ｜ **Source**: 本家 `UniV4MerklRewards.claimForInitiative`
- **シグネチャ**: `createCampaign()`
- **目的**: initiative 保持 JPYdf を、対象 Uniswap v4 プールの LP 向け Merkl キャンペーンに投入する。
- **権限**: `CAMPAIGN_CREATOR` は随時実行可。一般 caller は `block.timestamp >= campaignStart - CAMPAIGN_CREATION_WINDOW` のときのみ実行可。`nonReentrant`。
- **事前条件（Checks）**: `amount = jpydfToken.balanceOf(this) ≥ CAMPAIGN_JPYDF_AMOUNT_THRESHOLD`（未満は no-op／`return`）。
- **動作（Effects）**:
  1. `amount` を確定。
  2. `campaignStart = EPOCH_START + epoch() * EPOCH_DURATION` を算出し、`campaignIdByStartTimestamp[campaignStart] != 0` なら `MerklCampaignAlreadyCreated` を発火して no-op（残高 carry-over）。
  3. caller が `CAMPAIGN_CREATOR` でなく、かつ public fallback window 前なら revert。
  4. **都度 approve**: `jpydfToken.forceApprove(merkl, amount)`（max approve を持たない＝[PILA-SEC-003](#9-セキュリティ要件sec)）。
  5. `merkl.createCampaign({rewardToken: JPYdf, amount, campaignType: 13 (UNISWAP_V4), startTimestamp: campaignStart, duration: EPOCH_DURATION, campaignData: getCampaignData()})`。
  6. `campaignIdByStartTimestamp[campaignStart] = campaignId` を保存。
  7. `jpydfToken.forceApprove(merkl, 0)` で allowance を戻す。
  8. `NewMerklCampaign(epoch, amount, campaignId)` を発火。
- **view 補助**: `nextCampaignStart()` は次 campaign の start、`publicCampaignCreationStart()` は一般 caller が作成可能になる時刻、`canCreateCampaign(address caller)` は残高が閾値以上・同一 start 未作成・caller が creator または fallback window 内である場合に true を返す。
- **revert / 早期 return**: 閾値未満 → no-op（carry-over）。同じ `campaignStart` の campaign が作成済み → no-op（carry-over）。一般 caller が fallback window 前 → `CampaignCreationTooEarly`。Merkl が `campaignId == 0` を返す → `ZeroCampaignId`。
- **設計上のポイント**: Merkl 連携を `distribute()` の hook（`onClaimForInitiative`）から分離し、配分ループのガス肥大を避ける（本家準拠）。Merkl の campaign id は creator / reward token / campaign type / start / duration / campaignData で決まり、amount を含まないため、**同一 `campaignStart` につき 1 campaign** とする。早すぎる public call が小額 campaign で start を消費する grief を避けるため、通常は keeper/Safe の `CAMPAIGN_CREATOR` が予定した `route()` / `distribute()` 後に作成し、一般 caller は epoch 終盤の fallback window に限定する。campaign 作成後に同じ epoch 内で追加残高が入った場合、その残高は次の `campaignStart` まで initiative に carry-over される。Merkl が pull する実額（手数料込みか）を確認し approve 額を一致させる（[PILA-TBD-004/005](#14-未決事項tbd)）。
- **Verification**: unit / fork（Merkl `DistributionCreator`）。

### PILA-FR-203: getCampaignData（poolId / weight / blacklist の符号化）
- **Type**: Functional ｜ **Source**: 本家 `UniV4MerklRewards.getCampaignData`
- **目的**: Merkl Uniswap v4 キャンペーンの `campaignData`（対象 `UNIV4_POOL_ID`・手数料/token0/token1 重み・`IS_OUT_OF_RANGE_INCENTIVIZED=false`・blacklist）を生成する。
- **要件**: blacklist は Merkl campaignData の標準フィールドとして保持し、**Day-1 は空（対象者なし）**とする。範囲外流動性は非対象（`IS_OUT_OF_RANGE_INCENTIVIZED=false`、本家準拠）。将来 blacklist が必要になった場合（incentive を不正に吸う wash-trading・規制対応等）は **immutable-empty を既定とし新 instance で対応**（settable 化は「特定アドレスの報酬剥奪権限」という governance surface を増やすため要検討＝[PILA-TBD-003](#pila-tbd-003)）。
- **Verification**: unit / fork。

### PILA-FR-204: initiative hook（軽量 no-op）
- **Type**: Functional ｜ **Source**: 本家 `UniV4MerklRewards`
- **要件**: `UniV4MerklInitiative` の 4 hook は no-op。`onClaimForInitiative` は受領通知のみ（Merkl 連携は `createCampaign` に分離）。`onAfterAllocateLQTY` は no-op（[PILA-FR-102](#pila-fr-102-onafterallocatelqty-の保持phase-a-未使用)）。Phase-B で同一 initiative を再利用できるよう、no-op hook は単一 allocator 固定の caller 制限を持たない。将来の状態更新 hook を持つ initiative は、その initiative 側で必要な caller 制限を定義する。
- **Verification**: unit。

---

## 7. 状態変数・会計モデル

| 変数 | 型 | 説明 |
| --- | --- | --- |
| `jpydfToken` | `IERC20 immutable` | 配分対象（JPYdf） |
| `EPOCH_START` / `EPOCH_DURATION` | `uint256 immutable` | epoch 基準（本家 `Governance` 互換） |
| `owner` / `pendingOwner` | `address` | 配分先・比率・guardian の変更権限（handover 後＝Timelock）。2-step・renounce 無効 |
| `guardian` | `address` | `pause()` の即時実行者 |
| `initiatives` | `address[]` / registry | 登録 initiative の列挙 |
| `weightOf` | `mapping(address=>uint256)` | initiative ごとの配分比率（1e18） |
| `paused` | `bool` | `distribute()` の緊急停止 |
| `MAX_INITIATIVES` | `uint256 constant` | 登録 initiative 件数上限（32）。permissionless `distribute()` の loop gas を bounded に保つ |
| `CAMPAIGN_CREATOR` | `address immutable` | `UniV4MerklInitiative` の早期 campaign 作成 keeper / Safe |
| `CAMPAIGN_CREATION_WINDOW` | `uint256 immutable` | 一般 caller に campaign 作成を開放する `campaignStart` 直前 window |
| `campaignIdByStartTimestamp` | `mapping(uint256=>bytes32)` | `UniV4MerklInitiative` の Merkl campaign 重複作成防止。1 start timestamp につき 1 campaign |

**会計モデル**: allocator は予算・claim 状態を持たず、`distribute()` 時点の保持残高 `balanceOf(this)` を weight 按分するのみ。active weight は `Σweight = 1e18` とし、配分停止時は `Σweight = 0` で全額滞留させる。閾値未満は **保持残高として carry-over**。ブランチ別 PIL 内訳は Forwarder 同様に合算（off-chain 再構成・`IRTR` §2.3）。

---

## 8. 不変条件（INV）

| ID | 不変条件 | 検証 |
| --- | --- | --- |
| PILA-INV-001 | `distribute()` の流出先は**登録 initiative のみ**。owner も任意アドレスへ送金できない（送金先を引数に取る関数を持たない）。登録 initiative は JPYdf 外部 transfer 可能 recipient に限る | unit / invariant / manual |
| PILA-INV-002 | `Σweight` は 0 または `1e18`。reserve / Treasury 分も initiative として明示し、部分合計による未割当 weight を作らない（**treasury sink 等の追加流出先を持たない**） | unit / invariant |
| PILA-INV-003 | いずれかの initiative の hook revert/OOG が、他 initiative への配分を阻害しない（`safeCallWithMinGas` 隔離）。hook 成否はイベントで観測できる | unit / fuzz |
| PILA-INV-004 | initiative 0 件 / weight 全 0 のとき、全 PIL は allocator に滞留する（holding recipient での滞留と同じ資金移動結果＝活性化非依存） | unit / integration |
| PILA-INV-005 | 🔵 Core / `JpydfToken` / `InterestRouterForwarder` への状態変更呼び出しを行わない（受領のみ。Core 差分は Core spec `CORE-MOD-*` の所管） | manual / static |
| PILA-INV-006 | 登録・解除・weight・unpause は共通 Timelock 経由でしか実行できない（即時は GUARDIAN の pause のみ） | unit / manual |
| PILA-INV-007 | `IInitiative` は本家 `liquity/V2-gov` とシグネチャ完全一致（Phase-B で同一 initiative を無改変流用できる） | static / 差分検査 |
| PILA-INV-008 | 登録 initiative 数は `MAX_INITIATIVES=32` 以下。`distribute()` のループは admin proposal によって unbounded にならない | unit / manual |

---

## 9. セキュリティ要件（SEC）

### PILA-SEC-001: Merkl 依存の信頼境界
- **Statement**: `UniV4MerklInitiative` は Merkl `DistributionCreator` に reward（JPYdf）を渡し、配分計算・claim を委ねる。Merkl の off-chain 計算・claim インフラ・手数料・規約に依存する**新規の信頼境界**であり、本家 Liquity と同等の前提で受容する。緩和: immutable な campaign パラメータ、閾値、blacklist（Day-1 は空・将来必要時のみ）、**都度 approve による pull 上限の限定**（PILA-SEC-003）。
- **残存リスク**: Merkl 障害時はキャンペーン未成立で JPYdf が initiative に滞留（次 epoch 再試行）。Merkl 侵害時の被害は「当該キャンペーン approve 額」までに限定。
- **Verification**: fork / manual。

### PILA-SEC-002: admin 鍵侵害の被害境界
- **Statement**: owner（Timelock）が実行できるのは登録・解除・weight・unpause と、資金経路を持たないロール操作（`setGuardian` / 2-step ownership）のみで、即時に資金を奪う経路を持たない。不正な weight/登録変更には公示遅延が掛かり、その間に検知・対応できる（`IRTR-SEC-001` と同型）。`distribute()` は permissionless だが配分先・比率に呼出者裁量がない。
- **Verification**: unit / manual。

### PILA-SEC-003: Merkl approve は都度・キャンペーン額限定（本家比ハードニング）
- **Statement**: 本家 `UniV4MerklRewards` は Merkl へ `max approve` するが、本実装は **`createCampaign` ごとに `forceApprove(merkl, amount)`** とし、任意時点の Merkl の pull 可能額を当該キャンペーン額に限定する。これにより Merkl 側の不具合/侵害時に initiative 残高全額を抜かれる経路を塞ぐ。
- **影響評価（都度 approve の副作用）**: (a) 機能影響なし（approve→createCampaign が同 tx）。(b) ガス: epoch あたり approve 1 回（≈ SSTORE 1 つ）増。無視可能。(c) `forceApprove`（SafeERC20）で非標準 ERC-20 の allowance 競合を回避（JPYdf は標準のため実害なし）。(d) **要確認**: Merkl の `createCampaign` が pull する実額（campaign `amount` か `amount + fee` か）に approve を一致させる（[PILA-TBD-004/005](#14-未決事項tbd)）。
- **Verification**: unit / fork。

### PILA-SEC-004: initiative 隔離
- **Statement**: 悪性/故障 initiative は受領 JPYdf を weight 上限までしか得られず、`safeCallWithMinGas` により allocator・他 initiative をブリックできない（[PILA-INV-003](#8-不変条件inv)）。
- **Verification**: unit / fuzz。

### PILA-SEC-005: reentrancy / CEI
- **Statement**: `distribute()` は会計（残高読み）→外部呼出（transfer＋hook）の順で `nonReentrant`。JPYdf は転送フックを持たない標準 ERC-20 に依拠（§3.2）。`createCampaign` も `nonReentrant` とし、Merkl `createCampaign` 呼出中の allowance 有効期間に再入して二重 campaign 化する経路を閉じる。
- **Verification**: unit / manual。

### PILA-SEC-006: permissionless 起動と campaign 早押し防止
- **Statement**: `distribute()` は誰でも呼べるが、配分先（登録 initiative）・比率（weight）に呼出者裁量がない。`createCampaign()` は `CAMPAIGN_CREATOR` 優先、一般 caller は `CAMPAIGN_CREATION_WINDOW` 内のみとし、宛先プール（immutable poolId）・amount（initiative 残高）・start/duration に caller 裁量を持たせない。残高/閾値未満は no-op。
- **運用上の注意**: Merkl campaign は同一 `campaignStart` につき 1 回のみ作成できる。小額 campaign による早押し grief は fallback window 制限で抑止し、keeper 障害時は window 内の public call で liveness を確保する。campaign 作成後に同じ start に追加 JPYdf が入った場合は資金喪失ではなく次 `campaignStart` へ carry-over されるため、`MerklCampaignAlreadyCreated` と initiative 残高を監視する。
- **Verification**: unit。

---

## 10. ガバナンス・運用・アップグレード要件（GOV）

### PILA-GOV-001: ロール構成と handover
- 初期 `owner` は `DF_PILA_OWNER`（mainnet は Safe/Timelock 等の contract 必須）。Day-1 handoverでdToken / Vault / Strategy / `IRTR`と同じ共通TimelockControllerへ2-step移譲する。delay値は [Day1 Parameter Manifest](../../../Parameters.md) `PRM-GOV-COMMON-TIMELOCK-DELAY`、holder構成は [Protocol Role Holder Manifest](../../../protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md) を正本とする（[Governance-Roles-Timelock](../policies/Governance-Roles-Timelock.md)）。GUARDIAN は `DF_PILA_GUARDIAN`（mainnet は contract 必須）で pause のみ。権限の横断リファレンスは [Governance](../../../Governance.md)。

### PILA-GOV-002: 上流接続（Forwarder recipient）
- 稼働時、owner（Timelock）が `InterestRouterForwarder.setRecipient(PILAllocator)` を実行する（`IRTR-FR-003` / `IRTR-GOV-003`）。これにより本レイヤーが `IRTR-TBD-004` のいう PIL 配分機構の実体になる。接続の採用条件と evidence boundary は [Mainnet Launch Product Decision Record](../../launch/decisions/Mainnet-Launch-Product-Decision-Record.md) §6 に従う。

### PILA-GOV-003: Phase-A 稼働（activation）と activation-agnostic 性
- 契約 deploy・recipient 接続後も、**admin が initiative 登録＋weight 設定するまで配分は発生しない**（全 PIL は allocator 滞留＝[PILA-INV-004](#8-不変条件inv)）。`DeployPILAllocatorPhaseA` は `PILAllocator` と `UniV4MerklInitiative` を deploy し `pil-activation-manifest.json` を出力するが、initiative 登録・weight 設定・Forwarder recipient 変更は Safe/Timelock の明示 action として残す。

### PILA-GOV-004: Phase-A → Phase-B（投票型配分）移行
- Phase-B は投票トークン非依存の `VotingAllocator` を**新規 deploy**し、`forwarder.setRecipient(VotingAllocator)` で差替える（再デプロイ・コア無改変）。投票トークンは未確定であり、DFT を採用する場合に限り DFT を用いる。投票力計算は本家 `liquity/V2-gov:Governance` 準拠の time-weighted 方式を第一候補とするが、拘束投票が変更できるのは **1 epoch の確定済み PIL 予算内で allowlist 済み initiative 間の weight のみ**とする。VotingAllocator は予算総額・送付資産・initiative の登録/allowlist を変更できず、外部 GOV Timelock の PROPOSER その他の T1 role を持たない。initiative の登録・allowlist 変更は T1 として JIP 承認を経る。移行時は旧 `PILAllocator` の残高を最終 `distribute()` で掃き出してから切替える（runbook 化）。**同一 `IInitiative` 実装（`UniV4MerklInitiative` 等）を無改変流用**する（[PILA-INV-007](#8-不変条件inv)）。Phase-B の投票主体・権限境界・発行 gate は [Governance-Token-Design](../../roadmap/initiatives/governance-token/Governance-Token-Design.md) を正本とし、実装は別 doc・別監査とする。

### PILA-GOV-005: 拡張境界（initiative の追加・Curve スコープ外）
- **同種 DEX の別プール追加**（例: Uni v4 JPYdf/USDC に加え別ペア）: 新しい `UniV4MerklInitiative` instance（別 poolId）を deploy → `registerInitiative` → `setWeights`。allocator/既存 initiative/コア無改変。
- **別 DEX 追加（Curve 等）**: `IInitiative` を満たす新 initiative（例 `CurveGaugeInitiative`＝本家 `CurveV2GaugeRewards` 準拠の `gauge.deposit_reward_token`）を deploy → 登録。**Curve 系は Day-2・Phase-A 監査スコープ外**（[Contract-Audit-Scope-And-nSLOC](../../../engineering/guides/Contract-Audit-Scope-And-nSLOC.md) に明記）。
- いずれも allocator は initiative 抽象（`IInitiative`）越しにしか触らないため、Day-1 監査済みコントラクトを触らずに追加できる（§2.2-2・ARCH-004）。

### PILA-GOV-006: アップグレード方針
- `PILAllocator`・各 initiative は**非 UUPS（immutable）**。挙動変更は新コントラクト deploy＋`forwarder.setRecipient` 差替で対応する（`IRTR-GOV-004` と同方針・監査単純性）。

---

## 11. イベント・監視要件（EVT）

| ID | イベント（indexed） | 用途（off-chain） |
| --- | --- | --- |
| PILA-EVT-001 | `InitiativeRegistered(address indexed initiative, uint256 atEpoch, bool hookSucceeded)` | 配分先の追加追跡・登録 hook 失敗検知 |
| PILA-EVT-002 | `InitiativeUnregistered(address indexed initiative, uint256 atEpoch, bool hookSucceeded)` | 配分先の削除追跡・解除 hook 失敗検知 |
| PILA-EVT-003 | `WeightsUpdated(address[] initiatives, uint256[] weights)` | 配分比率変更の追跡（Timelock 提案/実行と併せ即時アラート） |
| PILA-EVT-004 | `Distributed(address indexed initiative, uint256 amount, uint256 indexed epoch, bool hookSucceeded)` | 配分実績・滞留量・claim hook 失敗の監視 |
| PILA-EVT-005 | `NewMerklCampaign(uint256 indexed epoch, uint256 amount, bytes32 campaignId)` / `MerklCampaignAlreadyCreated(uint256 indexed epoch, uint256 indexed startTimestamp, uint256 amount, bytes32 campaignId)` | Uniswap v4 キャンペーン生成と同一 start の carry-over 追跡 |
| PILA-EVT-006 | `Paused()` / `Unpaused()` | 緊急停止の監視 |
| PILA-EVT-007 | `GuardianUpdated(address indexed oldGuardian, address indexed newGuardian)` | 緊急停止担当の変更追跡 |

- 監視指標: allocator 保持残高（滞留量）、登録 initiative 件数（`MAX_INITIATIVES` 以下）、各 initiative の weight 合計（期待値は 0 または `1e18`）、`Distributed` の epoch 別実績、hookSucceeded=false イベント、`NewMerklCampaign` の成立、`MerklCampaignAlreadyCreated` 後の initiative 残高 carry-over、`WeightsUpdated`/`InitiativeRegistered` の即時アラート、Merkl キャンペーンの on-chain 反映。

---

## 12. 失敗時・異常系挙動（ERR）

| 事象 | 挙動 |
| --- | --- |
| initiative 0 件 / weight 全 0 で `distribute()` | `return 0`（全 PIL は allocator 滞留＝活性化前/未活性の正常系・[PILA-INV-004](#8-不変条件inv)） |
| 保持残高が `minDistribute` 未満 | no-op（carry-over）。誰でも安全に呼べる |
| invalid JPYdf recipient が initiative 登録されそうな場合 | `registerInitiative` / governance preflight が fail-fast。登録済み initiative への `safeTransfer` が recipient blacklist で revert し、配分全体を止める状態を作らない |
| initiative 登録数が上限に達した状態で追加登録 | `TooManyInitiatives` で fail-fast。配分先を整理するか、新 allocator deploy + recipient 差替で拡張する |
| ある initiative の `onClaimForInitiative` が revert/OOG | `safeCallWithMinGas` で隔離。資金は当該 initiative に着金済みで、`createCampaign` 等で後追い処理可。他 initiative の配分は継続（[PILA-INV-003](#8-不変条件inv)） |
| 同じ `campaignStart` の Merkl campaign が既に作成済み | 追加 campaign は作らず no-op。initiative 残高は次の `campaignStart` へ carry-over |
| Merkl `createCampaign` が閾値未満/障害で不成立 | initiative に JPYdf 滞留 → 次 epoch 再試行（資金喪失なし） |
| owner 鍵侵害による不正 weight/登録 | Timelock delay 中に `WeightsUpdated`/`InitiativeRegistered` 即時アラートで検知・対応（[PILA-SEC-002](#9-セキュリティ要件sec)） |
| Merkl 侵害/不具合 | 被害は当該キャンペーン approve 額に限定（都度 approve・[PILA-SEC-003](#9-セキュリティ要件sec)）。GUARDIAN が `pause()` で配分停止可 |
| JPYdf 以外の誤送 | rescue を持たない（滞留）。`distribute()` は JPYdf のみ対象（`IRTR` と同方針） |

---

## 13. 受け入れ基準・検証計画

| ID | 要件（要約） | 検証手段 |
| --- | --- | --- |
| PILA-FR-001/002 | constructor・epoch IF（本家互換） | unit |
| PILA-FR-003/004/005 | 登録・解除・weight（owner 限定・JPYdf recipient validation・Σ=0 or 1e18・weighted unregister 禁止） | unit, invariant=PILA-INV-001/002 |
| PILA-FR-006/007 | distribute（weight 按分・閾値・carry-over・hook 隔離・permissionless） | unit, fuzz, invariant=PILA-INV-001/003/004, integration |
| PILA-FR-008/010 | pause（GUARDIAN/Timelock）・2-step・renounce 無効 | unit |
| PILA-FR-101/102 | IInitiative 本家互換・onAfterAllocateLQTY 保持 | static（IF 差分）, unit |
| PILA-FR-201..204 | Merkl Uniswap v4 キャンペーン（都度 approve・blacklist・epoch 整列） | unit, fork（Merkl `DistributionCreator`） |
| PILA-INV-001..008 | §8 各不変条件 | unit / fuzz / invariant / static / manual |
| PILA-SEC-001..006 | §9 各セキュリティ要件 | unit / fork / manual |
| 上流接続 | `forwarder.setRecipient(PILAllocator)`→route→distribute→Merkl 一気通貫 | integration |
| 活性化非依存 | initiative 0 件 / weight 全 0 では PIL 滞留 | integration |

> コア側（PIL 残余の mint・SP/PIL 分配）と Forwarder の検証は 🔵 [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md)（`CORE-AP-FR-007`）/ [InterestRouter](./InterestRouter.md)（`IRTR-*`）の所管。本書は配分レイヤー以降のみを検証する。

---

## 14. 未決事項（TBD）

### PILA-TBD-001
**対象 Uniswap v4 プール** — Day-1（Phase-A）は `JPYdf/USDC` v4 1 プールを前提（「direct non-USDC JPYdf プールはスコープ外」＝[Product-Overview](../Product-Overview.md) §12.1 と整合）。複数ペアの要否は未確定。確定poolIdは承認済みactivation packageの`pil-activation-manifest.json`へ固定する。**拡張前提は確定**（複数プール = 複数 `UniV4MerklInitiative` instance＝[PILA-GOV-005](#10-ガバナンス運用アップグレード要件gov)）。

### PILA-TBD-002
**配分パラメータ** — `EPOCH_DURATION`（既定候補7日）/ `minDistribute`（既定候補`1000 JPYdf`）/ `CAMPAIGN_JPYDF_AMOUNT_THRESHOLD`（Merkl最小額）/ `CAMPAIGN_CREATOR`（未確定）/ `CAMPAIGN_CREATION_WINDOW`（既定候補1日）/ Merkl配分重み（`WEIGHT_FEES` / `WEIGHT_TOKEN0` / `WEIGHT_TOKEN1`の候補は`1500 / 4500 / 4000`、合計`10000`）。mainnet activation前に承認済みactivation packageの`pil-activation-manifest.json`へfreezeする。

`CAMPAIGN_JPYDF_AMOUNT_THRESHOLD = 168e18 + 1`の候補は、本家`UniV4MerklRewards` testの「7日間で1 token/hourを厳密に超える」境界に合わせたものとし、未満はinitiativeへcarry-overする。Merkl重みの`token0` / `token1`は名称から推測せず、確定したUniswap v4 `PoolKey.currency0` / `currency1`の順序に従う。activation Evidenceにはpool key、poolId、`currency0` / `currency1`のどちらがJPYdf / USDCか、および適用した各weightを記録する。

### PILA-TBD-003
**blacklist の方式（Day-1 は空・対象者なし）** — Day-1 blacklist は空とする。将来、incentive を不正に吸う wash-trading アドレスや規制対応で除外が必要になった場合の方式を決める: **(a) immutable-empty（既定・新 instance で差替・監査単純）** ／ (b) settable（Timelock 等で in-place 設定可・ただし「特定アドレスの報酬剥奪権限」という governance surface が増える）。

### PILA-TBD-004
**Merkl 依存の確定** — Merkl `DistributionCreator`（Angle・mainnet）アドレスの正本化、`acceptConditions()`／利用規約／KYC の許容、手数料モデル（`createCampaign` が pull する実額が campaign `amount` か `amount+fee` か）の確認。方針は「本家 Liquity と同等に許容」（ユーザー確認済み）。確定addressは承認済みactivation packageの`pil-activation-manifest.json`へ固定する。

### PILA-TBD-005
**approve 範囲の最終確定** — 本書既定は**都度 approve（キャンペーン額限定）**（[PILA-SEC-003](#9-セキュリティ要件sec)・本家 max approve からのハードニング）。PILA-TBD-004 の Merkl pull 実額確認を反映して `forceApprove` 額を確定する。

### PILA-TBD-006
Resolved: `PILA-GOV-003` に反映済み。

### PILA-TBD-007
Resolved: `PILA-FR-001` と [要件 ID 規約](../../../Requirements-Spec-Standard.md) に反映済み。

### PILA-TBD-008
Resolved: `SYS-FR-009` と [documents index](../../../../README.md)、[日本語 index](../README.md)、[英語 index](../../../../en/README.md) に反映済み。

---

## 15. 参考資料

- [InterestRouter](./InterestRouter.md) — `IRTR-FR-002`（route）/ `IRTR-FR-003`（setRecipient）/ `IRTR-GOV-003`（Day-1→Day-2 配送先移行）/ `IRTR-TBD-004`（Day-2 配分機構との接続）＝本書の上流
- 🔵 [Liquity-v2-Core-Spec](./Liquity-v2-Core-Spec.md) — `CORE-AP-FR-007`（PIL 残余 mint）
- [Treasury](../../roadmap/spec/Treasury.md) — 担保運用益（PIL とは独立経路）
- [Governance-Roles-Timelock](../policies/Governance-Roles-Timelock.md) — 共通 Timelock・handover
- [Governance-Token-Design](../../roadmap/initiatives/governance-token/Governance-Token-Design.md) — Phase-B の投票主体・T2 権限境界・DFT 発行 gate
- [Day1-Self-BS-Initial-Liquidity-Plan](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Initial-Liquidity-Plan.md) — 運営の自己 B/S シード流動性（本書スコープ外）
- [Merkl-Campaign-KPI-Policy](../../roadmap/policies/Merkl-Campaign-KPI-Policy.md) — Merkl campaign の採否・budget・KPI・停止条件
- [Contract-Audit-Scope-And-nSLOC](../../../engineering/guides/Contract-Audit-Scope-And-nSLOC.md) — 監査スコープ（Phase-A 追加・Curve スコープ外）
- `pil-activation-manifest.json` — 承認済みactivation packageのpool id / weight / threshold / Merkl / blacklist
- [Product-Overview](../Product-Overview.md) — PILのsystem requirement
- [Architecture Decision Records](../architecture/Architecture-Decision-Records.md) — ADR-004/005
- [Mainnet Launch Risk Gate](../../launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-003) — SP追加報酬のlaunch gate
- **参考調査（外部実装）**: [2026-06-25 PIL→DEX 配分 比較（Liquity v2 / Nerite / Asymmetry）](../../../engineering/historical-reviews/2026-06-25-PIL-DEX-Allocation-Reference-Liquity-Nerite-Asymmetry.md) — 本家 `liquity/V2-gov`（`Governance` / `IInitiative` / `UniV4MerklRewards` / `CurveV2GaugeRewards` / `BribeInitiative`）と Nerite・Asymmetry の実装比較。本設計の根拠
