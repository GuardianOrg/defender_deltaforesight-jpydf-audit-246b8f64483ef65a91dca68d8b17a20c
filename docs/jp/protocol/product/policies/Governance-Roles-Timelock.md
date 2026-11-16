# JPY DeFi ガバナンス権限・Timelock 設計判断

> **役割**: dToken / Strategy / Oracle / Treasury 系の権限を、遅延・即時 fail-safe・運用・損失反映へ分けた理由と受容リスクを記録する。
>
> **正本関係**: 個別gateは各component spec、delay値は [Day1 Parameter Manifest](../../../Parameters.md) `PRM-GOV-*`、holder構成は [Protocol Role Holder Manifest](../../../protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md)、横断索引は [`Governance.md`](../../../Governance.md)、実addressと検証結果はmainnet Gate / Evidenceを正本とする。本書は値・関数一覧・実装状況の正本ではない。
>
> **Status**: Active

---

## 0. 一行サマリ

**二主体ガバナンス（遅延=Timelock／即時=Guardian multisig）＋運用主体（ALLOCATOR）**に、**損失・不確実性を backing へ即時反映する高定足数の独立ロール（WRITEOFF_ROLE）**を加えた5ロール体系。原則は「**資金流出・希薄化・markdown を起こしうる操作は遅延（または高定足数）、可逆な fail-safe（停止・無害化）は即時、復旧は遅延**」。タイミングは**ロールの holder が決める**ため、異なるタイミング/定足数が必要な操作は必ず別ロールに分ける。

---

## 1. 問題（何が危険か）

| # | 問題 | 詳細 |
|---|---|---|
| **P1** | upgrade が即時 | GOV/Owner 鍵侵害で即座に implementation 差替→任意ロジック注入→他の全防御（role 分離・cap・whitelist・固定宛先・pause）を一括無効化 |
| **P2** | upgrade 無しでも即時流出経路 | DEFAULT_ADMIN+GOV 掌握なら `setBufferConfig(0,0)`→`setAllocatorConfig(max,0)`→`addToWhitelist`→`addStrategy(悪意)`→（grantRole で自分に ALLOCATOR 付与）→`allocate` で buffer を流出。`allocateMaxMove` の既定は `type(uint256).max`・cooldown 既定 0＝**初期状態では実効上限が無い** |
| **P3** | 即時操作で backing 希薄化→過剰清算 | (a) `emergencyWithdrawFromAave`→idle 非算入で `estimated=0`→backing 急落（Vault push まで窓）／(b) `writeoff`／`invalidateStrategyValuationCache` で principal/評価を下方 |
| **P4** | Strategy 損失の反映は writeoff が主経路 | Aave V3 は bad debt/deficit/frozen で `scaledBalanceOf`/`normalizedIncome` が下がらない場合があり `estimated` が過大。会計に出ない実損は **writeoff で明示反映するしかない**（AAVE-INV-002）。よって writeoff の遅延は損失反映を遅らせ過大評価窓を深める |

> P1 だけ直しても不十分（P2）、即時側も無条件に安全ではない（P3）、損失反映は自動でない（P4）。

---

## 2. 設計原則

1. **タイミングは holder が決める**: 同一ロール＝同一 holder＝同一タイミング。異なるタイミング/定足数が必要な操作は**必ず別ロール**にする（これが WRITEOFF_ROLE を独立させる理由）。
2. **リスク増・資金移動・markdown を起こしうる操作 → 遅延または高定足数即時**。
3. **可逆な fail-safe（停止・無害化）→ 即時（Guardian）**。
4. **復旧（unpause・再有効化・増額）→ 遅延（Timelock）**。「ブレーキは引きやすく、戻すのは遅い」。
5. **二主体＋運用主体**: 遅延主体=Timelock、即時主体=Guardian multisig、日常運用=ALLOCATOR。**holder 設計が一次防御**で、コードの gate は枠組み。
6. **🔵 Core 無改変（ARCH-001）**: すべて 🟢 DF 層の権限・配線で解決。Core には触れない。

---

## 3. ロール体系

### 3.1 CollateralVault — 5ロール

| ロール | Holder | タイミング | 担当関数 |
|---|---|---|---|
| `DEFAULT_ADMIN_ROLE` | **Timelock** | 遅延 | grant/revokeRole（ロール管理） |
| `GOV_ROLE` | Timelock | 遅延 | risk param、upgrade、復旧、ロール管理 |
| `WRITEOFF_ROLE` | 高定足数 Admin multisig | 即時 | 損失・不確実性の backing 反映 |
| `GUARDIAN_ROLE` | Guardian multisig | 即時 | pause、無害化、緊急回収 |
| `ALLOCATOR_ROLE` | `DF_ALLOCATOR` | 運用 | 固定経路の配分・回収・yield 送付 |

**設計上の要点**：

- **writeoff は独立ロール（WRITEOFF_ROLE）**。Guardian の即時ロールに入れない——Guardian は「速い緊急応答」のため低めの定足数で回す一方、writeoff は窃取可能（不当 markdown→不当清算→SP/清算経由で利得）なため高定足数が必須。同居させると「pause が遅くなる」か「writeoff が甘くなる」のどちらかになる。**holder が違う（高定足数 Admin multisig）から別ロール**——この一点だけが分離の対価を払う基準。
- **`invalidateStrategyValuationCache` は GUARDIAN に入れない**。これは「無害な fail-safe」ではなく、live 評価失敗窓で cache をクリアすると当該 Strategy 評価が 0→backing 下方→**清算を誘発しうる markdown 能力**を持つ（writeoff と同性格）。通常経路は GOV_ROLE / Timelock の遅延操作だが、実装は `WRITEOFF_ROLE` にも incident-ready 条件（Strategy disabled または allocation paused）下でのみ許可する。これにより高定足数の即時損失反映と stale cache 除去を同じ incident response 境界に置き、Guardian には markdown 能力を渡さない。
- **GUARDIAN_ROLE に入れた操作はすべて backing 中立 or 純フロー制御**で、markdown 能力を持たない：
  - `emergencyDisableStrategy`：`enabled=false`＋`weight=0`。estimated/principal を触らないので **backing 不変**、新規 allocate のみ停止。
  - `removeStrategy`：`principal==0` 必須＝寄与は既に min(estimated,0)=0 で **backing 不変**。
  - `removeFromWhitelist`：登録済み Strategy にも backing にも無影響。
  - pause 群：可逆なフロー停止。
  → だから EMERGENCY と PAUSE の統合（GUARDIAN_ROLE）は安全。markdown 能力を持つ writeoff（→WRITEOFF）と invalidateCache（→GOV/遅延、または WRITEOFF/incident-ready）だけを Guardian の外に出す。

### 3.2 DToken — Owner = Timelock

- 単一 Owner（2-step 移譲・自前実装＝OZ Ownable2Step 同等）を **Timelock** に配線。`setCap` / `setTokenInfo` / `setAllowedUnderlying` / upgrade はすべて遅延。
- **緊急の新規 mint 停止は Vault の `pauseDeposit`（Guardian・即時）が担う**ため、DToken にコード改変は不要。`setCap` は「恒久的な露出上限（risk param）」に格下げし、急がない遅延操作とする。

### 3.3 Strategy — upgrader と owner の分離

| 権限 | Holder | タイミング | 関数 |
|---|---|---|---|
| `upgrader` | Timelock | 遅延 | upgrade と upgrader 変更 |
| `owner` | Guardian multisig | 即時 | 緊急回収・報酬処理・protocol 固有 fail-safe |

Ownable の owner 1つでは「upgrade=遅延・emergency=即時」を両立できないため、upgrade を専用 `upgrader` へ分離する。

### 3.4 PriceFeedProxy — Owner = Admin multisig（直）

source 差替 delay を内蔵し `confirmSourceEmergency` でも強制されるため、Owner を共通 Timelock 配下に置くと二重遅延になる。Owner は Admin multisig が直接保持し、不正 source 提案の `cancelSourceProposal` を即時に保つ。

### 3.5 Treasury / Distributor — 即時 fail-safe の GUARDIAN 分離（実装時・🟡）

[Treasury](../../roadmap/spec/Treasury.md) / [Reward Distributors](../../roadmap/spec/Reward-Distributors.md) にも Vault と同型の遅延・即時分離を適用する。`GOV_ROLE` / `DEFAULT_ADMIN_ROLE` は共通 Timelock、destination disable、proposal / root cancel、pause は Guardian とする。即時 cancel を GOV に残すと共通 delay により challenge window 内の取消が間に合わないためである。`emergencyBackstopDeposit` は登録済み Vault・underlying 一致・不足額上限に縛り、任意送金や markdown 能力を持たせない。

---

## 4. 重要な設計判断と検証済みの制約

### A. Mint / Redeem / Claim を分離停止する

- **pauseDeposit / pauseRedeem を分離**するのは、シナリオで必要な操作が異なるため:
  - **XAUT 価格デペグ（A=L 成立）**: 新規 mint を止め redeem は開けたい（保有者の公平な脱出を塞がない）→ pauseDeposit のみ。
  - **Strategy 実損（A<L）**: dToken redeem は 1:1（ヘアカットなし）のため先着取り付けになる→ pauseRedeem で秩序化。
  - 旧 `pauseMintRedeem`（両停止）では XAUT 局面で脱出を不当に塞ぐため分離する。
- **claim も停止対象にする**。理由は Strategy 起因の writeoff（実損）時の取り付け阻止:
  - dToken redeem / claim は **1:1（backingRatio ヘアカットなし）**。A<L では buffer が有限で全 liability を賄えず、**新規 redeem の即時払い分と既存 vested claim が buffer を先着で奪い合う**。`pendingWithdrawals` は allocate からは守るが、redeem/claim 同士の先着レースは止めない（redeem は `bufferBalance()` をそのまま引き pendingWithdrawals を差し引かない）。
  - 結果、先着で満額を抜いた者が抜け、遅い holder / borrower が損失を全部かぶる＝**queue 位置のくじ引きで損失分担が決まる不公平**。
  - 損失処理の正道は **freeze → backstop 注入（`backstopDeposit` → `releaseBackstopToBuffer`）で A≥L 回復 → resume**。この repair 窓の間、**claim も止めないと vested claim が buffer を抜いて equitable repair を空洞化**する。pauseRedeem 単独では vested claim ドレインの穴が残るため、**完全 freeze には pauseClaim が必要**。
- **代償（明示）**: 確定債務（vested claim）を governance が凍結可能になり、非カストディアル性を一段弱める。Guardian は claim 停止を高確信時だけ発動し、共通 Timelock delay を要する復旧まで repair 窓を短く保つ。freeze 中も Core の Redemption・清算は停止しないため、Vault 出口停止中は JPYdf の Redemption 裁定も一時的に弱まる。
- **採らない代替**: A<L 時に redeem/claim を `backingRatio` で**按分ヘアカット**して先着優位を構造的に消す設計もあるが、既存の「1:1 ＋ backstop 修復」哲学（ORCL-FR-014 / backstop reserve）と衝突する大改変のため不採用。pauseClaim が既存設計と整合する道具。

### B. setCap は恒久 risk param へ格下げ・緊急停止は pauseDeposit

- 急性デペグの即時応答は `pauseDeposit`（Guardian・即時）。`setCap` は「対象担保の露出を増やさない」恒久ポリシーのレバーで急がないため遅延（Owner=Timelock）でよい。両者は**補完**であり代替ではない。ORCL-FR-013 の「`setCap(0)` による流入停止」は「急性=pauseDeposit 即時／恒久=setCap 遅延」に再記述する。

### C. 🔵 Core の branch shutdown は可逆フリーズではない（実証）

設計時点の実コードで確認した制約：

- **恒久・不可逆**: `hasBeenShutDown = false` / `shutdownTime = 0` に戻す関数が**存在しない**。一度 shutdown したブランチは永久に urgent redemptions モードで通常運用に戻らない。
- **任意発動不可**: `shutdown()` は `if (TCR >= SCR) revert TCRNotBelowSCR()`＝**TCR<SCR 時のみ**。`shutdownFromOracleFailure()` は `_requireCallerIsPriceFeed()`＝**PriceFeed 経由のみ**。GOV/Guardian から任意に発動できない。
- **markdown 前は呼べない循環**: writeoff が要る局面では backingRatio=1e18 のまま→担保過大評価→TCR 過大→`TCR≥SCR` で shutdown が revert。
- **dToken 層 pause は Core 借入を止めない**: `pauseDeposit` / `emergencyDisableStrategy` は新規 dToken 供給と Strategy 配分を止めるだけ。既存 dXXX を担保にした Core の借入・調整系操作（`_requireIsNotShutDown` は `openTrove`・`adjustTrove` のほか `applyPendingDebt`・金利調整・batch 管理系を含む計 10 entrypoint を gate するが、弾くのは shutdown 時のみ）は過大評価価格のまま新規 JPYdf を借りられる。

→ **「一時停止して後で再開」を Core に期待してはならない**。既存 dXXX 露出を止める唯一の手段は shutdown（恒久・条件付き）で、平時はその規模を **mintCap で構造的に上限管理**する（ORCL-FR-013・SYS-INV-004 の限界）。

### D. writeoff は即時・高定足数（遅延+フリーズ案は撤回）

- C により「即時・可逆フリーズで出血を止め、writeoff は遅延」は**不成立**（Core に任意発動できる可逆フリーズが無い）。writeoff を遅延させると、markdown 未反映の過大評価担保で**新規借入が進み bad debt が積み増す**のを止められない。
- よって **writeoff は遅延せず高定足数 Admin multisig で即時実行**（WRITEOFF_ROLE）。レート制限は不採用（「悪用を止める低い上限」と「大損を即反映する高い上限」を単一スカラで両立できず自己矛盾）。
- 不正 writeoff（不当 markdown→不当清算→SP/清算経由で窃取）への耐性は次の3層で担保：①高定足数（単一鍵では発動不能）②検知時に `pauseRedeem`（Guardian・即時）で攻撃者の dXXX→Underlying 換金出口を瞬時に封鎖 ③writeoff 自体は資金を送らない（principal 減のみ）ため monetization に別アクションが要る高い障壁。

### E. emergencyWithdrawFromAave は原子直送にする

- `emergencyWithdrawFromAave`→`emergencyWithdraw` の2段の間、引き出した Underlying は Strategy idle に滞留し、`estimated=0`（idle 非算入）かつ Vault buffer 未着で **totalUnderlying から全額が宙吊り**→backingRatio 急落→**当該ブランチ全 Trove の不当 mass 清算**（permissionless・自動 MEV・不可逆）。
- bundling（マルチシグの multiSend）は運用規律依存で、緊急時の部分実行を防げない。
- したがって `emergencyWithdrawFromAave` は Aave→Vault を1トランザクションで完結させる。Aave revert 時は全体 revertし、idle 回収用の `emergencyWithdraw` は別用途として残す。

---

## 5. 残存リスクと運用前提

- **完全鍵侵害**では、共通 delay 中の検知・退避を前提とする。Admin multisig / proposer が侵害された場合、別 holder による cancel はできない。
- **Guardian 鍵侵害**は停止・無害化による可用性被害を起こせるが、任意送金や markdown はできない。
- **WRITEOFF_ROLE holder 侵害**は revoke 完了まで即時 writeoff が可能である。`pauseRedeem`、高定足数、直接送金不可で monetization を有界化する。
- **writeoff を timelock しない**選択は、Core に可逆フリーズが無いことの帰結（§4-C/D）。
- **遅延の運用コスト**: Strategy 追加、config 変更、dToken 活性化、unpause は即時にできない。緊急時は Guardian の pause で時間を作る。

---
