# 🔑 JPY DeFi ガバナンス権限リファレンス（Governance Permissions Reference）

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Domain | Meta（Protocol capability index） |
| Lifecycle | Evergreen |
| Classification | Meta document / Index |
| Decision Authority | Protocol Governance（参照先の個別要件） |
| Maintainer | DeltaForesight (Contributor) |
| Status | Active |
| 文書の役割 | **「各ガバナンス主体が、どのコントラクトのどの特権関数を呼べるか」をロール起点で引く横断インデックス**。個別 gate の規範は component spec、delay値は [Day1 Parameter Manifest](./Parameters.md)、holder実値は [Protocol Role Holder Manifest](./protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md)、分離条件は[Role Holder Separation Policy](./protocol/launch/gates/Mainnet-Role-Holder-Separation-Policy.md)、判断理由は [Governance-Roles-Timelock.md](./protocol/product/policies/Governance-Roles-Timelock.md)、実行手順は各 Runbook を正本とする。 |
| 正本関係 | 本書の索引は component spec の GOV / FR 要件をロール別に横断表示する。個別 gate・効果・異常系・値の独立した正本ではない。矛盾時は該当する正本を修正し、本書を追従させる。 |
| オフチェーン承認 | [Day-1 Governance Proposal & Execution Policy](./protocol/launch/gates/Day-1-Governance-Proposal-Execution-Policy.md) が JIP・承認・公示・執行・readback、[Protocol Governance GitHub Operations](./protocol/operations/runbooks/Protocol-Governance-GitHub-Operations.md) が GitHub 実務、[Governance Record Reference Spec](./Governance-Record-Reference-Spec.md) が外部recordの参照schemaを定義する。本書の permission が存在するだけでは実行を承認しない。 |
| 照合対象（コード） | `deltaforesight/jpydf-v2` の `contracts/src`（`develop`）。本書は**正規ロール名を主キー**とし、行番号は周辺コード改変で流動するため載せない。**着手・参照前に develop 最新 head で関数名・ロール定義を再 grep すること。** |
| 相互参照 | **ロールは正規名（GOV / WRITEOFF / GUARDIAN / ALLOCATOR / ORACLE-OWNER / BRIDGE-ADMIN / BRIDGE-MINTER）で参照**する（章は再番号されうるため節番号での参照は避ける）。 |

---

## 1. 目的・スコープ・非責務

### 1.1 スコープ・非責務

- **本書が扱う**: 🟢 DF 独自レイヤー（CollateralVault / dToken / Strategy / Oracle / InterestRouter / PILAllocator）と **JpydfToken（ステーブルコイン本体・bridge 系）** の継続的なガバナンス主体・特権 entrypoint、外部 GOV Timelock の内部ロール（PROPOSER / EXECUTOR / CANCELLER）の所在、及び 🔵 Core が「特権主体を持たない」ことの確認。
- **本書が扱わない（→他文書）**: Contract 起点の interface・個別 gate・効果・異常系（各 `protocol/product/spec/*.md`）／permissionless surface（[Permissionless User Operations](./protocol/product/spec/Permissionless-User-Operations.md)）／タイミング設計の判断根拠 why（[Governance-Roles-Timelock.md](./protocol/product/policies/Governance-Roles-Timelock.md)）／パラメータ値（[Parameters.md](./Parameters.md)）／Foundation 法人運営事務、Foundation operating multisig、5 Member / Exhibit A、MINS Category C reporting member（[Foundation docs](./foundation/requirements/Foundation-Entity-Setup-Requirements.md)）。

Foundation operating multisig / Member / Exhibit A は RMI DAO LLC / Foundation の会社運営レイヤーであり、本書の Admin multisig / Guardian / Treasury / Timelock holder とは別である。Foundation側のexpected holderは[Foundation Operating-Asset Holder Manifest](./foundation/manifests/Foundation-Operating-Asset-Holder-Manifest.md)で管理し、Protocol Safe / signer addressをFoundation Exhibit AのMember addressとして扱わない。

### 1.2 要約

**核心原則**: 「**資金流出・希薄化・markdown を起こしうる操作は遅延 or 高定足数、可逆な fail-safe は即時、復旧は遅延**」（ブレーキは引きやすく、戻すのは遅い）。🔵 Core（借入・償還・清算・SP・Redemption）は **immutable・permissionless で停止主体を持たない**（GOV はパラメータ統制のみ・SYS-NFR-002）。why の正本は [Governance-Roles-Timelock.md](./protocol/product/policies/Governance-Roles-Timelock.md)。

ガバナンスは **3 系統**＝ ① DF プロトコル層（CollateralVault 中心・5 ロール＋各契約 Owner・Oracle 含む）／② GOV Timelock の内部（PROPOSER / EXECUTOR / CANCELLER）／③ JpydfToken（core mint / burn＋休眠 bridge）。アクターと holder は §2、ロール別の権限索引は §3 を使う。

契約ごとの `owner` は同じ holder を意味しない。GOV Timelock は外部、PriceFeedProxy と bridge minter の待機時間は各契約内蔵である。delay値はDay1 Parameter Manifestの`PRM-GOV-*` / `PRM-BRIDGE-*`を使う。

### 1.3 Operational Approval Gate

on-chain capability は実行承認を意味しない。JIP・公示・calldata 照合・readback は [Day-1 Governance Proposal & Execution Policy](./protocol/launch/gates/Day-1-Governance-Proposal-Execution-Policy.md)、外部文書からJIP / CDRを参照するfieldは[Governance Record Reference Spec](./Governance-Record-Reference-Spec.md)を正本とする。

---

## 2. アクター対応表（正規名 ↔ role ↔ holder ↔ env）

**同じ鍵が場所により別名で出てくる**混乱を断つための単一対応表。**左端の「正規名」が本書の統一語**で、§3 はこの正規名を主キーとする。

| 正規名 | コード上の identity（role / owner） | holder（実体の鍵） | deploy env |
| --- | --- | --- | --- |
| **GOV** | Vault `GOV_ROLE`＋`DEFAULT_ADMIN_ROLE`／DToken `owner`／Strategy `upgrader`／InterestRouter `owner`／PILAllocator `owner` | 外部 Timelock | `DF_TIMELOCK`（=`DF_STRATEGY_UPGRADER`）。PIL Phase-A は `DF_PILA_OWNER` |
| **WRITEOFF** | Vault `WRITEOFF_ROLE` | Admin multisig | `DF_WRITEOFF` |
| **GUARDIAN** | Vault `GUARDIAN_ROLE`／各 Strategy `owner`／PILAllocator `guardian` | Guardian multisig | `DF_GUARDIAN`（=`DF_STRATEGY_OWNER`）。PIL Phase-A は `DF_PILA_GUARDIAN` |
| **ALLOCATOR** | Vault `ALLOCATOR_ROLE` | Allocator holder（形態・移管条件は [Allocator Signer Policy](./protocol/launch/gates/Mainnet-Role-Assignment-Allocator-Signer-Policy.md)） | `DF_ALLOCATOR` |
| **ORACLE-OWNER** | PriceFeedProxy `owner` | Admin multisig | `DF_PRICE_FEED_OWNER` |
| **BRIDGE-ADMIN** | JpydfToken `bridgeAdmin` | Admin multisig | `DF_BRIDGE_ADMIN` |
| **BRIDGE-MINTER** | JpydfToken bridge minter（`bridgeMint` / `bridgeBurn`） | 登録アドレス（Day-1 ゼロ） | on-chain |

**外部 Timelock の内部ロール**（上表とは別レベルで、DF コントラクトのロールではない）:

| 内部ロール | holder | 役割 | repo の env |
| --- | --- | --- | --- |
| **PROPOSER** | Admin multisig | 遅延操作を起案（schedule） | なし（外部 Timelock 側で設定） |
| **EXECUTOR** | Admin multisig | minDelay 後に実行 | なし（外部 Timelock 側で設定） |
| **CANCELLER** | Admin multisig | 待機中の proposal を取消 | launch evidence 上の `DF_TIMELOCK_CANCELLER`（contracts env なし） |

holder実値は[Protocol Role Holder Manifest](./protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md)、holder間の分離条件は[Role Holder Separation Policy](./protocol/launch/gates/Mainnet-Role-Holder-Separation-Policy.md)、delay値は [Day1 Parameter Manifest](./Parameters.md) `PRM-GOV-*`、権限設計の理由は [Governance-Roles-Timelock.md](./protocol/product/policies/Governance-Roles-Timelock.md) を参照する。

**継続的なガバナンス権限を持たない主体**: JpydfToken `owner` は deploy 配線後に自己 renounce する。JpydfToken core `mint` / `burn` は BO / AP / CR / TM / SP、DToken `mint` / `burn` は Vault、Strategy `deposit` / `writeoffPrincipal` は Vault、Vault `receiveFromStrategy` は登録 Strategy がそれぞれ呼ぶ。価格 feed 本体（`DF*PriceFeed` 等）は owner / setter を持たず、🔵 Core と一般ユーザー操作は permissionless である。これらの Contract 起点の認可条件は各 component spec を正本とし、§3 のガバナンス索引には重ねない。

---

## 3. ロール別権限索引（role → contract → privileged function）

継続的なオンチェーンガバナンス主体を起点に、対象 Contract と特権関数を逆引きする。ここには**関数名と規範要件への導線だけ**を置く。holder は §2、delay 等の値は `PRM-GOV-*` / `PRM-BRIDGE-*`、個別 gate・効果・異常系はリンク先の component spec を正本とする。`renounceOwnership` のように常に revert する無効化関数は capability として列挙しない。

CollateralVault の各ロール holder は、OZ AccessControl の `renounceRole` で**自分自身の当該ロールだけ**を放棄できる。この自己放棄は権限拡大ではないが、holder 不在を招きうる管理 surface のため [VAULT-GOV-002](./protocol/product/spec/CollateralVault.md#vault-gov-002) に含める。

### 3.1 GOV ＋ DEFAULT_ADMIN

- **CollateralVault**: `_authorizeUpgrade` / `setUnderlying` / `setBufferConfig` / `setWithdrawDelay` / `setTreasury` / `setAllocatorConfig` / `setStrategyValuationMaxAge` / `addToWhitelist` / `addStrategy` / `updateStrategy` / `releaseBackstopToBuffer` / `invalidateStrategyValuationCache` / `unpauseDeposit` / `unpauseRedeem` / `unpauseClaim` / `unpauseAllocation` / `grantRole` / `revokeRole` — [VAULT-GOV-002](./protocol/product/spec/CollateralVault.md#vault-gov-002)
- **DToken**: `setCap` / `setTokenInfo` / `setAllowedUnderlying` / `_authorizeUpgrade` / `transferOwnership` / `acceptOwnership` — [DTKN-GOV-004](./protocol/product/spec/dToken.md#dtkn-gov-004-owner-timelock)
- **Strategies**（専用 `upgrader`）: `_authorizeUpgrade` / `setUpgrader` — [STGY-GOV-003](./protocol/product/spec/strategies/Strategy.md#stgy-gov-003-upgrader-timelock)
- **InterestRouterForwarder**: `setRecipient` / `transferOwnership` / `acceptOwnership` — [IRTR-GOV-001](./protocol/product/spec/InterestRouter.md)
- **PILAllocator**: `registerInitiative` / `unregisterInitiative` / `setWeights` / `unpause` / `setGuardian` / `transferOwnership` / `acceptOwnership` — [PILA-GOV-001](./protocol/product/spec/PILAllocator.md)

### 3.2 WRITEOFF

- **CollateralVault**: `writeoffStrategyPrincipal` / `invalidateStrategyValuationCache` — [VAULT-GOV-002](./protocol/product/spec/CollateralVault.md#vault-gov-002)
- **AsyncRequestStrategy**（Etherfi。Lido は既存 instance の回収時のみ）: `setPendingWithdrawalValuationBps` — [STGY-SEC-004](./protocol/product/spec/strategies/Strategy.md#stgy-sec-004-aum-過大評価への保守的会計)

### 3.3 GUARDIAN

- **CollateralVault**: `pauseDeposit` / `pauseRedeem` / `pauseClaim` / `pauseAllocation` / `emergencyDisableStrategy` / `removeStrategy` / `removeFromWhitelist` — [VAULT-GOV-002](./protocol/product/spec/CollateralVault.md#vault-gov-002)
- **BaseStrategy 共通**: `emergencyWithdraw` / `sweepRewardToken` / `claimMerklRewards` / `transferOwnership` / `acceptOwnership` — [STGY-GOV-002](./protocol/product/spec/strategies/Strategy.md#stgy-gov-002-緊急時オペレーション)
- **AaveV3Strategy**: `emergencyWithdrawFromAave` / `claimAaveRewards` — [AAVE-FR-006 / AAVE-FR-007](./protocol/product/spec/strategies/AaveV3Strategy.md)
- **LidoStrategy**（**archived**・deploy 経路なし・既存 instance の回収用 capability のみ）: `emergencyWithdrawFromLido` / `setReferral` — [archived Lido Strategy spec](archive/LidoStrategy.md)
- **ERC4626Strategy**: `emergencyWithdrawFromERC4626` — [ERC-4626 Strategy spec](./protocol/product/spec/strategies/ERC4626Strategy.md)
- **EtherfiWeETHStrategy**（**archived**・deploy 経路なし）: `emergencyWithdrawFromEtherfi` / `setReferral` — [archived Etherfi Strategy spec](archive/EtherfiWeETHStrategy.md)
- **SkyUsdcSUsdsStrategy**: `setMaxConversionLossBps` / `emergencyRedeemSUsdsToUsds` / `emergencyConvertIdleUsdsToVault` / `emergencyWithdrawFromSky` — [Sky Strategy spec](./protocol/product/spec/strategies/SkySUsdsStrategy.md)
- **PILAllocator**: `pause` — [PILA-FR-008](./protocol/product/spec/PILAllocator.md)

### 3.4 ALLOCATOR

- **CollateralVault**: `allocate` / `transferYieldToTreasury` — [VAULT-GOV-002](./protocol/product/spec/CollateralVault.md#vault-gov-002)
- **BaseStrategy 共通**: `sendToVault` / `sendProfitToVault` — [STGY-FR-002 / STGY-FR-003](./protocol/product/spec/strategies/Strategy.md)
- **LidoStrategy / EtherfiWeETHStrategy**（いずれも **archived**・deploy 経路なし・既存 instance の回収時のみ）: `requestLidoWithdrawal` / `requestEtherfiWithdrawal` — [archived Lido Strategy spec](archive/LidoStrategy.md) / [archived Etherfi Strategy spec](archive/EtherfiWeETHStrategy.md)

### 3.5 ORACLE-OWNER

- **PriceFeedProxy**: `proposeSource` / `confirmSource` / `confirmSourceEmergency` / `cancelSourceProposal` / `transferOwnership` / `acceptOwnership` — [ORCL-GOV-001〜004](./protocol/product/spec/Oracle.md#orcl-gov-001-owner-は-governance--multisig)

### 3.6 BRIDGE-ADMIN

- **JpydfToken**: `proposeBridgeMinter` / `confirmBridgeMinter` / `cancelBridgeMinterProposal` / `removeBridgeMinter` / `transferBridgeAdmin` / `acceptBridgeAdmin` / `renounceBridgeAdmin` — [CORE-BT-FR-014 / CORE-BT-FR-016](./protocol/product/spec/JpydfToken.md)

### 3.7 BRIDGE-MINTER

- **JpydfToken**: `bridgeMint` / `bridgeBurn` — [CORE-BT-FR-015](./protocol/product/spec/JpydfToken.md)

### 3.8 外部 Timelock の内部ロール

- **PROPOSER**: `schedule` / `scheduleBatch`
- **EXECUTOR**: `execute` / `executeBatch`
- **CANCELLER**: `cancel`

これらは外部 OpenZeppelin `TimelockController` の権限であり、DF component の role ではない。構成規範は [Mainnet Timelock Deploy Policy](./protocol/launch/gates/Mainnet-Timelock-Deploy-Policy.md)、実行手順と readback は [Mainnet Timelock Deploy Runbook](./protocol/launch/gates/Mainnet-Timelock-Deploy-Runbook.md) を正本とする。

---

## 4. 🟡 Day-2（Treasury / reward distributors）— 未実装

`contracts/src` に **Treasury.sol / SPAdditionalRewardDistributor.sol / Referral distributors は存在しない**ため、Active な権限索引には含めない。予定する role・関数・gate は [Treasury](./protocol/roadmap/spec/Treasury.md) と [Reward Distributors](./protocol/roadmap/spec/Reward-Distributors.md) の Future Draft を正本とする。実装・監査・activation gate の完了後に、現行コードと突合して§3へ追加する。

---

## 5. 出典・正本関係

- **component 個別要件（Contract 起点の正本）**: [CollateralVault](./protocol/product/spec/CollateralVault.md)／[dToken](./protocol/product/spec/dToken.md)／[Strategy](./protocol/product/spec/strategies/Strategy.md) と各 Strategy spec／[Oracle](./protocol/product/spec/Oracle.md)／[InterestRouter](./protocol/product/spec/InterestRouter.md)／[JpydfToken](./protocol/product/spec/JpydfToken.md)／[PILAllocator](./protocol/product/spec/PILAllocator.md)。
- **holder実値**: [Mainnet Protocol Role Holder Manifest](./protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md)。
- **holder分離条件**: [Mainnet Role Holder Separation Policy](./protocol/launch/gates/Mainnet-Role-Holder-Separation-Policy.md)。
- **governance / bridge delay値**: [Day1 Parameter Manifest](./Parameters.md) `PRM-GOV-*` / `PRM-BRIDGE-*`。
- **タイミング設計の判断根拠（why）**: [Governance Roles & Timelock](./protocol/product/policies/Governance-Roles-Timelock.md)。
- **オフチェーン承認と GitHub 運用**: [Day-1 Governance Proposal & Execution Policy](./protocol/launch/gates/Day-1-Governance-Proposal-Execution-Policy.md)／[Protocol Governance GitHub Operations](./protocol/operations/runbooks/Protocol-Governance-GitHub-Operations.md)／[JIP Template](./protocol/operations/templates/JIP-Template.md)。
- **システム原則**: [Product Overview](./protocol/product/Product-Overview.md) SYS-NFR-002 / 003。

> 本書は仕様正本と現行実装を横断する **role → contract → privileged function** インデックス。**着手・参照前に develop 最新 head で関数名・ロール定義を再 grep すること**（行番号・周辺コードは流動する）。
