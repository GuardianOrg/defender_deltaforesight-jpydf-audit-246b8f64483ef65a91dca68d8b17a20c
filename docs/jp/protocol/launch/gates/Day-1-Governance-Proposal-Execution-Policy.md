# Day-1 Governance Proposal & Execution Policy

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Draft |
| Owner | DeltaForesight |
| 対象 | Day-1（ガバナンストークン・staking・投票 UI 不在）における mainnet 特権操作の提案・承認・執行・記録の手続 |
| 文書の役割 | **Day-1 における「ガバナンス承認済み（governance-approved）」の正本定義**。design / runbook の「governance approval」、Operating Agreement の「ガバナンス承認済み決議」は本書を参照する。オンチェーン権限（誰がどの関数を呼べるか）の正本は [Governance.md](../../../Governance.md) であり、本書はその**行使に必要なオフチェーン承認レイヤー**を定義する |
| Operational repository | `deltaforesight/jpydf-governance`（Public。新設・go-live 前） |
| 関連ドキュメント | [Governance.md](../../../Governance.md)（ロール×関数の正本）/ [Protocol Governance GitHub Operations](../../operations/runbooks/Protocol-Governance-GitHub-Operations.md)（GitHub runbook）/ [JIP Template](../../operations/templates/JIP-Template.md) / [Governance-Roles-Timelock.md](../../product/policies/Governance-Roles-Timelock.md)（タイミング設計の why）/ [Foundation-Entity-Setup-Requirements.md](../../../foundation/requirements/Foundation-Entity-Setup-Requirements.md)（Foundation core requirements）/ [Foundation-Entity-RMI-DAO-LLC-Requirements.md](../../../foundation/requirements/Foundation-Entity-RMI-DAO-LLC-Requirements.md)（RMI DAO LLC / candidate requirements）/ [Foundation-Entity-Operating-Agreement-Requirements.md](../../../foundation/requirements/Foundation-Entity-Operating-Agreement-Requirements.md)（OA checklist）/ [Mainnet-Role-Assignment-Safe-Threshold-Policy.md](./Mainnet-Role-Assignment-Safe-Threshold-Policy.md)・[Mainnet Protocol Role Holder Manifest](../manifests/Mainnet-Protocol-Role-Holder-Manifest.md)（signer構成・expected address）/ [Mainnet-Safe-Role-Assignment-Gate.md](./Mainnet-Safe-Role-Assignment-Gate.md)（launch evidence） |

---

## 1. 目的・適用範囲・定義

### 1.1 「ガバナンス承認済み」の正規定義（4 条件）

mainnet の特権操作は、次の 4 条件をすべて満たしたときに限り「ガバナンス承認済み」であり、署名・執行できる。

1. JIP（§6）が公開され、Class（§5）に応じた討議期間を満了している。
2. 署名主体（§4）の**事前の記名・理由付き承認**が閾値を満たしている。閾値は**全 Class 共通**で「承認した signer block の保有鍵数合計 ≥ 当該 Safe の threshold」（例: Protocol 系 Safe 3-of-5 なら承認鍵数 ≥3）。
3. JIP が status=Approved で公開されている。
4. 執行内容（target / value / selector / args）が JIP の Specification と一致することが第三者検証可能である。

「Safe 上で署名が集まったこと」を事後的に承認と呼ばない。**公開の承認記録（JIP）が先、Safe 署名が後**。同じ署名主体が両方を行うが、必ず 2 段階に分けて記録する。

### 1.2 Day-1 governance body = 署名主体（signer-block governance）

Day-1 の governance body は **protocol 系 Safe の署名主体（signer block）の総体**とする。別建ての委員会・評議会・トークン投票は置かない。署名主体の実構成・閾値の正本は [Safe-Threshold-Policy](./Mainnet-Role-Assignment-Safe-Threshold-Policy.md) / [Protocol Role Holder Manifest](../../../protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md) であり、本書は具体的な signer 構成に依存しない（前提は §7.3 の不変式のみ）。

### 1.3 DFKK（DeltaForesight株式会社）の位置づけ

DFKK はメインコントリビューターとして、提案・討議・承認・執行のすべてに参加する**一署名主体**である。ただし DFKK 支配鍵のみでは承認閾値にも Safe threshold にも到達しない（INV-1）ため、**いかなる特権操作にも独立署名主体 ≥1 の賛成が構造的に必要**となる。DFKK は事務局（JIP の形式チェック・執行調整・運用実行）を兼ねてよいが、内容の裁定はしない。

### 1.4 適用範囲

- **適用**: mainnet 上の全特権操作（GOV / WRITEOFF / GUARDIAN / ORACLE-OWNER / BRIDGE-ADMIN の各操作、ALLOCATOR の運用枠設定）、protocol 系 Safe の signer / holder 変更、Protocol Treasury からの資金移動、本書と Register（§3）の改定。
- **非適用**: launch 1 回性 gate（各 runbook の既存規律で扱う初期設定）、DFKK 社内決定、Foundation 法人運営事務（OA 事項）、承認済み枠内の日常運用（§5.3）。
- **トークン非依存**: 本書はトークン残高・quorum 等トークンに依存する数値・前提を含まない。ガバナンストークンを発行しない場合も、§4.3 の交代手続だけで無期限に自走する。

Foundation 法人運営事務（OA 事項）には、Foundation Operating Multisig Wallet、5 Member / Exhibit A、MINS Category C reporting member、MIDAO / annual filing / KYB、Foundation operating assets の支出が含まれる。これらは private `jpydf-foundation-governance` の CDR 手続で扱い、本書の public protocol signer-block governance とは別レイヤーである。本書の A-E signer address / Safe address / threshold を OA / Exhibit A の Member address として扱わず、Foundation の private CDR / Member vote を `jpydf-governance` へ転載しない。ただし CD-P は公開 JIP と private CDR を ID / hash で相互参照する。

## 2. 設計原則

| # | 原則 | 内容 |
|---|------|------|
| P1 | 決めないことを宣言する | 統治対象を最大限 immutable / permissionless に保ち、Non-Governable List（§3）として公開する |
| P2 | 方向非対称 | 保守化（pause・cap 減・markdown）は速く軽く、拡張（unpause・cap 増・upgrade・新 venue）は遅く重く（SYS-NFR-002 の手続レイヤーへの拡張） |
| P3 | 承認と執行の分離 | 承認記録（JIP）が先、Safe 署名が後（§1.1） |
| P4 | default-dead | 期限内に承認要件を満たさない提案は自動失効。governance が機能停止したらパラメータは凍結する（immutable コア＋Redemption により、何も変えないことが常に安全側）。「DFKK へ権限返還」型のフォールバックは置かない |
| P5 | 追認禁止 | Emergency（§8）の事後レビューを除き、実行済み事項の事後 ratification を承認として扱わない |

## 3. Governance Surface Register（統治面の棚卸し）

公開リポジトリ（§9）に `registry/governance-surface.md` として常置する。初版は [Governance.md](../../../Governance.md) のロール×関数マトリクスから生成する。

- **Non-Governable List**: 🔵 Core（借入・償還・清算・SP・Redemption。停止主体なし・shutdown は TCR<SCR 条件付き自動のみ）／JpydfToken owner（renounce 済み・恒久無権限）／DFStabilityPool（特権関数ゼロ）／価格 feed 本体（owner・setter なし）／permissionless 操作群。「DFKK が支配できない」以前に「誰も支配できない」領域の公開宣言であり、規制・取引所・監査人向けの一次資産として維持する。
- **Governable List**: 全特権操作を §5 の Class（N / C / E）に対応づけて列挙する。事前承認枠（§5.3）を持つ操作は bound・cooldown も記載する。
- **維持**: jpydf-v2 の PR テンプレートに「Governance Surface Diff」欄（当該変更が追加・削除する特権・bound。差分ゼロなら「なし」）を設ける。四半期ごとに on-chain readback で Register を検証する（§9.3）。Register の改定は Class C。

## 4. 署名主体（governance body）

### 4.1 構成と権利

| 主体 | 提案 | 討議 | 承認 | 執行（署名） | 備考 |
|---|---|---|---|---|---|
| DFKK | ○ | ○ | ○（支配鍵数分） | ○ | 単独では閾値不到達（INV-1）。事務局兼務可 |
| 独立署名主体（複数） | ○ | ○ | ○（各鍵数分） | ○ | DFKK からの独立性は Foundation core / RMI DAO LLC candidate requirements に従う |
| Foundation / 5 Member / MINS Category C reporting member | — | — | — | Foundation affairs の会社運営事務のみ | Foundation core / RMI DAO LLC 要件と整合。protocol 議決に参加しない |

**DFKK が単独でできないこと（公開列挙）**: パラメータ変更・upgrade・oracle source 差替・strategy 追加・Treasury 移動・bridge 活性化・signer block 変更・本書の改定。
**DFKK が単独でできること**: 提案・討議・承認済み枠内の運用（ALLOCATOR 等）・Guardian pause の発動（Guardian Safe の threshold を DFKK 支配鍵のみで満たす構成の場合。可逆・保守方向のみ。§8）。

### 4.2 独立性・相互レビュー

- 独立署名主体の独立性・KYB・制裁スクリーニングは、[Foundation-Entity-Setup-Requirements.md](../../../foundation/requirements/Foundation-Entity-Setup-Requirements.md) の non-control 要件、および [Foundation-Entity-RMI-DAO-LLC-Requirements.md](../../../foundation/requirements/Foundation-Entity-RMI-DAO-LLC-Requirements.md) / [Foundation-Entity-Member-Signer-Requirements.md](../../../foundation/requirements/Foundation-Entity-Member-Signer-Requirements.md) の候補要件に従い、独立性を裏づける表明・記録を年 1 回更新・公開する。**本書の実効性は独立署名主体の実在的独立性に全面的に依存する**。
- **相互レビュー**: 常設のレビュアーは置かず、討議・技術確認は署名主体が相互に行う。ただし次の 2 点は必須:
  1. **calldata 検証は起案 block 以外の block が実施**する（起案者の自己検証のみで執行しない。§6.1 / §6.4）。
  2. **upgrade（Class C）は外部セキュリティレビュー（diff 監査等）を承認の前提**とする（常設でなくスポット委託でよい）。
- **Recusal**: 直接の金銭的利害がある議案（例: 自社が counterparty となる Strategy 採用）では、当該 block の承認を閾値に数えず、その旨を JIP に記録する。recusal により閾値が満たせない場合は、残る署名主体全員の承認＋公開告知 7 日延長で代替する。
- 四半期 liveness check（テスト承認への応答）を行い、連続 2 回無応答は交代事由とする。

### 4.3 signer block の交代・追加・解任（capture 防止）

- すべて **Class C**。さらに次を追加要件とする:
  - 対象 block は自身の解任・交代議案の承認に参加できない（recusal）。
  - **独立署名主体の解任・交代は、対象を除く独立署名主体全員の賛成を含む** — DFKK＋独立 1 者の組合せで他の独立署名主体を順次入れ替える「段階的 capture」を遮断する。全 Class 共通閾値（§1.1）に対する唯一の追加要件であり、対象は signer block 変更という 1 操作のみ。
- 変更後の roster は launch 時と同一の evidence 規律（[Mainnet-Safe-Role-Assignment-Gate.md](./Mainnet-Safe-Role-Assignment-Gate.md)）で non-control / independence 要件の充足を再検証する（INV-5）。
- 欠員時: Foundation は 60 日以内に補充手続（候補公募・KYB・14 日パブリックコメント）を開始する。独立署名主体が 2 block 未満になった場合、Class N/C の新規承認を凍結し（Emergency と事前承認枠内の保守方向操作のみ継続）、補充を最優先する。

## 5. Proposal Class（N / C / E の 3 分類）

### 5.1 Class 定義

| Class | 対象 | 討議期間 | 承認要件 | 実行前の遅延（exit window） |
|---|---|---|---|---|
| **N（Normal）** | Critical・Emergency 以外のすべての特権操作（bound 外パラメータ変更、addStrategy / updateStrategy、PIL initiative 登録、予算外 Treasury 支出、unpause・recovery、事前承認枠の設定・更新 等） | **≥7 日**（保守方向の操作は 72h に短縮可） | 承認鍵数 ≥ Safe threshold（§1.1）＋未解消の反対なし | 共通 Timelock（delay は [Parameters](../../../Parameters.md) `PRM-GOV-COMMON-TIMELOCK-DELAY`）。退出経路に影響する変更は承認から実行まで ≥7 日確保 |
| **C（Critical・限定列挙）** | upgrade 全種／oracle source 差替／bridge minter activation（[Bridge-Minter-Activation-Gate](../../operations/runbooks/Bridge-Minter-Activation-Gate.md) 併用）／Treasury cutover（[Treasury-Safe-Retention-Runbook](../../operations/runbooks/Treasury-Safe-Retention-Runbook.md) 併用）／InterestRouterForwarder setRecipient／role holder・signer block 変更／本書・Register の改定 | **≥14 日** | **Normal と同一**＋upgrade は外部セキュリティレビュー完了＋signer block 変更は §4.3 の追加要件 | 承認後 **≥7 日**の公示を経て Timelock queue（oracle 内蔵 24h・bridge 内蔵 48h は重畳） |
| **E（Emergency）** | §8 の列挙操作のみ | なし（事前承認不要） | on-chain 定足数がそのまま統制（WRITEOFF 高定足数・GUARDIAN 等）＋§8 の事後義務 | なし |

共通規則:

- Class 判定に迷う場合は重い方（C）に倒す。判定は起案時に proposer が宣言し、signer block 1 者の異議で重い方を採用する。
- **Expedited 変則**（インシデント起因の N/C。feed 障害時の oracle 差替、インシデント後の unpause 等）: **全 signer block の明示同意**を条件に討議を 24h まで短縮できる。事後 postmortem 必須。
- **exit window 規則**: 全 N/C 提案は「影響を受けるユーザーと退出手段」を JIP に明記し、公示から発効までの合計が max(上表の既定値, 当該ユーザーの退出所要時間（withdrawDelay 含む)) を下回らないこと。exit window は「不同意ユーザーが Redemption / Trove クローズ / 引出で退出できる時間」として公示する。
- 反対票が出た場合、反対理由への公開応答なしに執行できない。否決時も理由を公開する。
- **承認後 30 日以内に Timelock queue（または実行）しなければ失効**（再承認要）。承認内容の変更は不可、変更は新 JIP とする。

### 5.2 代表操作 → Class 対応（初版。全量は Register に収載）

| 操作（ロール） | Class |
|---|---|
| upgrade 全種、oracle source 差替、bridge activation、Treasury cutover、setRecipient、role holder / signer 変更（GOV / ORACLE-OWNER / BRIDGE-ADMIN） | C |
| addStrategy / updateStrategy、bound 外 risk param、unpause 4 種、PIL initiative 登録、予算枠設定（GOV / Treasury） | S 相当なし → N |
| 承認済みスケジュール内 cap step、bound 内 param・setWeights、予算内 Treasury 支出 | N（事前承認枠。§5.3） |
| pause 系・emergencyDisableStrategy・removeStrategy・emergencyWithdraw 系（GUARDIAN）／writeoff・valuation markdown・invalidateCache（WRITEOFF）／Timelock cancel（CANCELLER）／cancelSourceProposal・confirmSourceEmergency（ORACLE-OWNER） | E |
| allocate 等の on-chain bound 済み運用（ALLOCATOR、枠内） | 対象外（ログのみ） |

### 5.3 事前承認枠（Normal 承認の反復適用）

反復的・定型的な操作は、**親 JIP（Class N）で「枠」を一括承認**し、枠内の各実行に新たな承認を要しない。

- 例: branch mintCap ramp スケジュール（step 幅・間隔。[Active-Branch-Cap-Ramp-Runbook](../../operations/runbooks/Active-Branch-Cap-Ramp-Runbook.md) と突合）／Strategy cap の増額上限・頻度／Treasury の年間予算枠（宛先ホワイトリスト固定）／ALLOCATOR の運用枠（四半期更新・月次実績報告）。
- 枠内の各実行は **72h 前の公示（親 JIP への追記）＋署名時の bound 充足確認（§7.1）**のみで実行できる。枠逸脱は通常の Class N。
- 枠の bound・cooldown の確定値は Register に記載し、[Parameters.md](../../../Parameters.md)・各 runbook と矛盾しないこと。

## 6. Proposal Lifecycle（JIP: JPY DeFi Improvement Proposal）

採番 `JIP-YYYY-NNN`、緊急事後報告は `JIP-E-YYYY-NNN`。

1. **Draft** — 誰でも公開リポジトリへ提出できる。Review 昇格には signer block 1 者（DFKK 可）の sponsor が必要（spam 防止。拒否時は理由を公開）。テンプレート必須項目: Summary / Motivation / Specification（対象コントラクト・関数・args・期待 calldata・期待 post-state。実アドレスは redacted 参照）/ Class 判定と根拠 / Stakeholder Impact と退出手段 / Security & Risk / Verification plan / Rollback。
2. **Review** — Class 別討議期間。提起された**全異議に理由付きで応答**した記録を残す（rough consensus 規律）。Class C は外部セキュリティレビュー（upgrade）・該当する既存 gate / runbook（strategy 採用は [Strategy-Selection-Policy](../../operations/policies/Strategy-Selection-Policy.md)、cap ramp・bridge・Treasury cutover は各 runbook）の充足を先に完了する。**本書は既存 gate を置換せず、その上に「承認」を定義する**。
3. **Approval** — 各 signer block が記名・理由付き承認 / 反対を JIP に記録する（block の登録 GitHub アカウント＋登録アドレスの EIP-191 署名または Safe の EIP-1271）。§1.1 の閾値充足で status=Approved。期限切れは Expired（default-dead）。recusal も記録する。
4. **Execution** — Safe tx bundle を作成（description に JIP ID 必須）。**起案 block 以外の signer block 1 者以上**が calldata と Specification の一致を fork simulation（Tenderly / foundry）付きで検証し、検証記録（payload の keccak ハッシュ含む）を JIP に添付する（[Mainnet-Safe-Role-Assignment-Gate](./Mainnet-Safe-Role-Assignment-Gate.md) の calldata review 規律を proposal 単位へ一般化したもの）。実行予定（何が・いつ・どう変わるか・退出手段）は Approved 時点で JIP に明記し、これを公示とする。公示中は誰でも異議を申立てでき、signer block 1 者が「重大」と認めた場合は執行を停止して Review へ差し戻す。exit window と Timelock の両方の満了後に execute する。
5. **Record** — 執行後 24h 以内に post-state readback を実施し、Safe tx hash・Timelock operation id・readback 結果を JIP に追記して status=Executed。readback 不一致は incident として扱う（§8 系対応）。決定→執行→承認記録の対応は JIP 1 ファイルで完結する。

再提出: Rejected / Expired は再提出できる（討議期間 1/2 に短縮可）。同一内容 3 回目以降は 30 日 cooldown。

機械可読 frontmatter、Decision Package marker、approval / execution record の schema は [`JIP-Template.md`](../../operations/templates/JIP-Template.md) を唯一の正本として使う。

### 6.1 GitHub Operating Sequence

既存 5 段階を GitHub 上では次の順に実施する。

| Step | Artifact / status | Owner | Exit criterion |
| --- | --- | --- | --- |
| 1. Intake | public Issue / intake | Proposer / secretariat | 重複確認、JIP ID、Class 候補、owner、due date を割当。Issue は proposal ではない |
| 2. Draft | proposal PR / Draft | Proposer | JIP template 必須項目、Discussion link、sponsor を記載 |
| 3. Review | public Discussion + PR / Review | Signer blocks / reviewers | Class 別期間、全異議応答、required review / runbook 完了 |
| 4. Freeze | proposal PR / Voting | Secretariat | Decision Package marker 内を freeze し `package_sha256` を確定 |
| 5. Approval | PR review / signed vote / Voting | Signer blocks | 同一 hash の valid vote が threshold、recusal、expiry を満たす |
| 6. Record | merge / Approved | Secretariat | Approved JIP を `main` へ収載。merge は ministerial |
| 7. Queue / execute | Safe + Timelock / Queued | Execution actors | notice / exit window、simulation、independent decode、delay を満了 |
| 8. Readback / close | record PR / Executed → Closed | Secretariat / verifier | 24h readback、tx / event / operation ID、follow-up を marker 外に記録 |

PR merge、label、CODEOWNERS approval は workflow gate であり、§1.1 の signer-block approval を代替しない。

### 6.2 Status and Transition Rules

`Draft` → `Review` → `Voting` → `Approved` → `Queued` → `Executed` → `Closed`。終端 / 置換は `Rejected` / `Expired` / `Cancelled` / `Superseded`。

- `Draft → Review`: sponsor、Class、必須 section、Discussion link がある。
- `Review → Voting`: 討議期間・required review を満たし、Decision Package を freeze した。
- `Voting → Approved`: threshold、recusal、異議応答、expiry、hash 一致を満たした。
- `Approved → Queued`: execution notice、exit window、calldata review、simulation、Safe bundle が揃った。
- `Queued → Executed`: Timelock / contract 内蔵 delay を満了し、approved payload と一致する tx が成功した。
- `Executed → Closed`: 24h readback、event / state、Transparency Report / follow-up link を記録した。
- package、target、value、selector、args、重要 precondition を変更した場合、旧 hash の vote を stale として `Review` または `Voting` をやり直す。

### 6.3 Package Freeze and Vote Record

Decision Package marker、SHA-256 canonicalization、vote minimum fields、stale 判定は [`Protocol-Governance-GitHub-Operations.md`](../../operations/runbooks/Protocol-Governance-GitHub-Operations.md) §4 を使う。

```text
RECORD-TYPE: JIP-VOTE
ID: JIP-YYYY-NNN
PACKAGE-SHA256: <64 hex>
VOTER: <registered signer block>
CAPACITY: Protocol Signer Block
VOTE: FOR | AGAINST | ABSTAIN | RECUSED
CONFLICT: none | <disclosure ref>
REASON: <reason or stable URL>
TIMESTAMP: <ISO-8601 UTC>
SIGNATURE-REF: <EIP-191 / EIP-1271 evidence ref>
```

次は approval に算入しない。

- signer-block register の effective period 外の account / address。
- package hash 不一致、package 変更後の旧 vote。
- reason / signature evidence 不足、撤回済み、期限外。
- `ABSTAIN` / `RECUSED`、または conflict rule 違反。

approval 集計は block ごとの有効鍵数を register と照合する。GitHub required review や CODEOWNERS は補助 gate であり、鍵数 threshold と EIP signature 検証の代替にしない。

### 6.4 Repository and CI

public repository の directory、labels、branch rules、access、backup は共通 runbook §§5–10 を適用する。少なくとも次を required check にする。

- JIP schema、ID / path uniqueness、Class / status transition。
- Decision Package marker と `package_sha256`。
- signer-block register、vote hash、鍵数、recusal、expiry、required review。
- target / selector / args / calldata hash、simulation / independent reviewer evidence。
- execution 後の tx hash、Timelock operation ID、readback。
- secret / private signer security / KYC pattern の public record 混入防止。

check は走査 JIP 数・vote 数・鍵数集計を出力し、走査対象 0 件や register 未読込を成功扱いにしない。

## 7. 署名者の確認範囲・拒否権・不変式

### 7.1 署名前チェックリスト（全 protocol 系 Safe 共通・全項目必須）

1. 対応する JIP が status=Approved で、当該 Class の要件（討議期間・承認鍵数・recusal・Class C の外部レビュー / §4.3 要件）を満たし、失効（30 日）前であること。事前承認枠内の実行は、親 JIP の bound 内・cooldown 経過・72h 公示済みであること。
2. tx の to / value / selector / args が承認済み Specification・検証記録と一致すること（Safe UI decode と独立ツール再 decode の突合）。
3. 当該操作が [Governance.md](../../../Governance.md) のマトリクス上、当該 Safe / ロールの権限範囲内であること。
4. 明白な違法性・制裁抵触・「emergency と称した §8 禁止行為」の兆候がないこと。

署名段階の役割は ministerial（承認済み内容の執行であり、内容の再審査はしない）だが、チェック不合格の tx への**署名拒否は義務**である。

### 7.2 拒否・差し戻し・報復禁止

- チェック不合格または合理的疑義がある場合、signer は署名を拒否し、48h 以内に理由を JIP に記録する（秘匿情報は redacted）。軽微不備は Execution 段階で修正、実質的疑義は Review へ差し戻す。
- **報復禁止**: 誠実な拒否を理由とする不利益取扱い（解任提案・報酬減）を禁止する。拒否後 90 日間、当該 block の解任は拒否記録を添付した Class C でのみ可能。義務と保護は署名主体契約および Foundation / RMI DAO LLC 側の candidate requirements と整合させる。

### 7.3 不変式（signer 構成非依存・launch gate No-Go 化）

signer roster がどう定まっても、以下を [Mainnet-Safe-Role-Assignment-Gate.md](./Mainnet-Safe-Role-Assignment-Gate.md) の No-Go 条件に追加し、evidence package に「signer→支配主体マッピング（signerListHash 方式）＋検証結果」を含める。

- **INV-1**: 全 protocol 系 Safe（GOV 経路の Admin multisig・Treasury Safe 含む）で、DFKK 支配鍵のみで threshold に到達できない（単独支配禁止の恒常運用化）。
- **INV-2**: threshold を満たすいかなる署名組合せにも、独立署名主体の署名が最低 1 つ含まれる（INV-1 の帰結だが独立に検証する）。
- **INV-3**: 独立署名主体は契約で「承認済み JIP と一致する tx のみ署名する」（§7.1）に拘束される。
- **INV-4**: Timelock の queue（schedule）操作も INV-1〜3 に服する。JIP 承認前の queue は禁止。
- **INV-5**: signer 構成変更後 7 日以内に権限台帳（§9.3）を更新・readback する。

承認閾値（§1.1）とこの不変式が二重に効くことで、**DFKK が運用の大半を担っても、未承認の変更を承認・執行する組合せを構成できない**ことが signer 構成と無関係に保証される。

## 8. Emergency Path

- **範囲の限定（列挙主義）**: Class E はオンチェーン設計で即時性が正当化済みの操作の閉集合のみ — GUARDIAN の pause 4 種・emergencyDisableStrategy・removeStrategy / removeFromWhitelist・emergencyWithdraw 系（送金先 Vault 固定）・PILAllocator pause／WRITEOFF の writeoff・valuation markdown・invalidateCache（incident-ready 条件下）／CANCELLER の Timelock cancel／ORACLE-OWNER の cancelSourceProposal・confirmSourceEmergency（内蔵 24h は不変）。
- **禁止列挙**: 「emergency」を名目とする upgrade・Treasury 移動・権限付与・bridge minter 登録・パラメータの緩和方向変更・unpause は定義上存在しない（オンチェーンにもその経路がないことを Register で明示する）。必要が生じても必ず Class N/C を経る。WRITEOFF を Timelock 配下に置かない既存判断（[Governance-Roles-Timelock.md](../../product/policies/Governance-Roles-Timelock.md) §7-D）は維持する。
- **発動判断**: [Incident-Notification-Policy](../../../contributors/deltaforesight/operations/Incident-Notification-Policy.md) のインシデントレベルに紐付ける（Guardian pause は高確信時のみ、claim 停止は特に高確信時のみ、WRITEOFF は毀損証跡と markdown 幅の根拠を保存してから）。WRITEOFF は時間が許す限り他の署名主体へ事前通知・意見聴取するが、承認を執行条件にしない（即応性を損なわない）。
- **事後統制（すべて必須・公開）**:
  - 72h 以内: [`JIP-E-Template.md`](../../operations/templates/JIP-E-Template.md) を使った JIP-E 速報（実行した on-chain 操作の全列挙・redacted）。
  - 14 日以内: postmortem（原因・影響・タイムライン・再発防止）＋**発動主体以外の signer block による事後レビュー**（「正当」「是正勧告付き正当」「不当（再発防止策要求）」を理由付きで公開。追認ではなく検証 = P5）。
  - 復旧（unpause・re-enable・valuation 復元）は必ず Class N（Expedited 可）。オンチェーン非対称（pause 即時／unpause は GOV 経由）と一致。
  - 同一事象での pause 再発動は 2 回まで。3 回目以降は Class N 承認要（真の再緊急時は例外可・理由開示）。pause が 7 日超継続する場合、全 signer block レビューで「継続の公開承認」または「unpause 起案指示」を決定する（凍結恒久化の防止）。
  - CANCELLER 発動は「承認内容と queued 内容の不一致」または「Admin multisig 侵害の合理的疑い」に限る。
  - 年 1 回の emergency drill（pause→報告→レビュー→unpause の通し訓練）を実施・記録し、Class E 発動統計を四半期レポート（§9.4）で公開する。

## 9. 公開・記録ルール

### 9.1 正本の場所

- 公開 GitHub リポジトリ **`jpydf-governance`**（新設）を operational record の唯一の正本とする。JIP 正本は英語（日本語訳併記可）。本 policy の正本は `jpydf-v2` の本ファイルとし、governance repository は policy の commit SHA を参照する。
- directory は `proposals/YYYY/`（JIP）、`emergency/YYYY/`（JIP-E）、`registry/`（Governance Surface Register・権限台帳）、`reports/`（Transparency Report）とし、構成の正本は [GitHub runbook](../../operations/runbooks/Protocol-Governance-GitHub-Operations.md) §5 とする。
- Issue は intake、Discussions は討議、proposal PR は Decision Package と approval、record PR は execution / readback に使う。Issue close / PR merge は approval を意味しない。
- Notion・Slack 等での内部検討は、決定に影響した内容の redacted summary を JIP に転記しなければ承認手続に算入しない。
- Foundation の private CDR / Member vote / corporate evidence は `jpydf-governance` に置かない。CD-P は CDR ID と非秘密 hash / status だけを JIP に記録する。

### 9.2 Redaction

既存規律（[Mainnet-Safe-Role-Assignment-Gate](./Mainnet-Safe-Role-Assignment-Gate.md) / [Protocol Role Holder Manifest](../../../protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md) / [Safe-Threshold-Policy](./Mainnet-Role-Assignment-Safe-Threshold-Policy.md)）に準拠する。個人 signer 情報・デバイス・nonce・インフラ詳細は private evidence package 側に置き、public 側はハッシュ（signerListHash 方式）で照合する。署名主体の組織名と承認用アドレスは公開する。攻撃を誘発し得るインシデント詳細は、収束後 30 日以内に redacted postmortem を公開する。

### 9.3 権限台帳（permissions ledger）

role → holder address → 呼べる関数 → bound → timelock を 1 ページで公開する（リポジトリから自動生成）。**四半期ごとに on-chain readback で検証**し、機械検証されない項目（Timelock 内部ロール・minDelay・PriceFeedProxy owner の同一性 — [Governance.md](../../../Governance.md) の Verify 非対象群）を明示的にチェックリスト化する。

### 9.4 四半期 Transparency Report

実行 JIP 一覧／Class E 発動と postmortem／事前承認枠の運用実績／liveness／権限台帳検証結果。DFKK が起草し、**独立署名主体 ≥1 block が内容確認のうえ連署**して公開する。

## 10. ツール

| 機能 | Day-1 採用 | 備考 |
|---|---|---|
| 討議・正本 | GitHub（`jpydf-governance` repo＋Discussions） | Discourse は参加者拡大後の移行候補 |
| 承認の証跡 | JIP 上の記名承認＋EIP-191 / EIP-1271 署名 | Snapshot（whitelist 投票）は将来オプション |
| GitHub 運用 | [Protocol Governance GitHub Operations](../../operations/runbooks/Protocol-Governance-GitHub-Operations.md) | Issue / Discussion / PR、hash、ruleset、CI、backup の正本 |
| Proposal template | [JIP Template](../../operations/templates/JIP-Template.md) / [JIP-E Template](../../operations/templates/JIP-E-Template.md) | Decision Package marker と vote schema を固定 |
| 執行 | 既設の Safe＋外部 TimelockController。手動執行＋二重検証 | オフチェーン投票の自動オンチェーン執行製品は採用しない（外部ベンダー依存の持続性リスク） |
| シミュレーション | Tenderly / foundry fork test を Review・Execution で必須化 | |
| 権限台帳 | §9.3 のとおり自動生成・公開 | |
| Record gate | GitHub Actions の schema / hash / vote / transition / secret checks | 走査 0 件・register 未読込を fail にする |

## 11. Day-2 Token Optionality への移行パス

- 本書はトークン依存の前提を含まず、発行しない未来でも無期限に自走する。トークン発行を前提とした権限配置（「後でトークンで直す」）は認めない。
- 発行する場合の接続・存続条件は次の 2 つに限る（接続変更は Class C）:
  1. **PIL recipient を VotingAllocator へ差替**（Phase-B 設計どおり。`liquity/V2-gov` の監査済み実装が再利用候補）。Governor はこの T2 専用 VotingAllocator にのみ接続し、外部 GOV Timelock の PROPOSER その他の Core / Strategy / Treasury 権限を持たない。VotingAllocator が変更できるのは、1 epoch の確定済み PIL 予算内における allowlist 済み initiative 間の weight に限る。
  2. signer-block 承認レイヤーは**技術承認・安全確認レイヤーとして存続**させ、トークン投票を限定的な政治レイヤーとして追加する（トークン投票は Class C の外部レビュー・独立承認要件を代替しない）。
- トークン発行の是非・時期・検討開始条件は本書の対象外。
- **年次レビュー**: 毎年 launch 応当日に「継続／改定／次段階移行」を明示決定し公開する（default = 現状維持。不履行は Transparency Report に記録）。

## 12. 発効条件（launch gate への追加 No-Go）

1. 本書が公開され、全 signer block が署名主体契約で本書の遵守にコミットしてから、mainnet で Class N/C 相当の操作を行う（launch 1 回性 gate による初期設定を除く）。
2. 独立署名主体の独立性表明・KYB 証跡（redacted）が launch evidence package に含まれること。
3. INV-1〜5 の検証結果が evidence package に含まれること（§7.3）。
4. Register 初版・権限台帳初版・JIP テンプレートが公開されていること。
5. `jpydf-governance` の public visibility、teams / collaborators、Discussion categories、labels、branch rules、required checks、backup / export が設定済みであること。
6. signer-block GitHub account / approval address mapping と effective period が register にあり、EIP-191 / EIP-1271 検証手順が通ること。
7. dummy JIP で Intake → Review → Voting → Approved → Queued → Executed → Closed を通し、stale vote、threshold 不足、recusal、package 改変、expiry、secret 混入が fail すること。
8. repository export と restore test により JIP、Discussion、vote、execution evidence を再構成できること。

## 13. 既存文書・Repository への反映マップ

| 対象 | 反映内容 | 状態 |
|---|---|---|
| [Foundation Corporate Decision Process](../../../foundation/runbooks/Foundation-Entity-Corporate-Decision-Process.md) | Protocol=Public / Foundation=Private、CD-P の二重承認 | 反映済み |
| [Governance.md](../../../Governance.md) | on-chain permission と JIP operational approval の二重 gate | 反映済み |
| [Mainnet-Safe-Role-Assignment-Gate.md](./Mainnet-Safe-Role-Assignment-Gate.md) | evidence package に INV-1〜5、「JIP なき特権 tx」No-Go、§7.1 signer checklist | 反映済み |
| 各 activation runbook（bridge / cap ramp / referral / Treasury cutover） | 「governance approval」= 本書の該当 Class の JIP | 未反映分は go-live blocker |
| `jpydf-governance` repository | template、Register、権限台帳、ruleset、CI、backup | repository 新設時に実施 |

## 14. 設計判断（採らない代替案）と残存リスク

### 14.1 採らない代替案

- **別建ての独立レビュアー評議会（委員会型）**: 承認（審査）と執行（署名）の分離は強くなるが、外部組織の調達が launch のクリティカルパスに載り、tokenless Day-1 の規模に対して運用が重い。署名主体の相互レビュー＋公開手続で代替する。
- **Critical の承認を entity 数で数える（保有鍵数によらず 1 主体 1 票）**: 独立主体 ≥2 の賛成を機械的に保証できるが、計数方式が 2 本になり、policy・署名主体契約・OA 参照・evidence gate の整合維持コストが恒常化する。閾値は 1 本に統一し、重大事項は手続の重さ（討議 14 日・外部レビュー・実行前公示）で差別化する。
- **「proposer は承認者になれない」**: 名目上の起案者を差し替えることで実効閾値が変わり（proposer-shopping）、実務上ほぼ全件を DFKK が起案するため事実上「独立全員一致」となって liveness リスクが大きい。利益相反時の recusal（§4.2）で同じ目的をより的確に達成する。
- **独立 CANCELLER（cancel 専用 Safe への CANCELLER_ROLE 追加付与）**: Day-1 はオンチェーン構成を変更しない。[Mainnet-Timelock-Deploy-Policy.md](./Mainnet-Timelock-Deploy-Policy.md) が受容した残余リスクの扱いを維持し、署名者拡大のタイミングで再検討する。
- **bound の on-chain 強制（parameter steward / roles module）**: 追加コントラクトの監査・deploy リスクを Day-1 に負わない。運用実績（目安 2 四半期）を見て Class C で導入を判断する。
- **利用者 veto のオンチェーン実装（escrow ロックによる遅延延長等）**: 新規コントラクト＋監査が必要で Day-1 過剰。exit window 規則（§5.1）で近似し、将来拡張点として §6.1 の異議手続に留める。

### 14.2 残存リスクと運用前提

1. **承認者＝執行者**: 審査と執行の主体が同一。緩和は「承認先行の 2 段階記録」「起案外 block の calldata 検証」「upgrade の外部レビュー」「公示中の第三者異議」。
2. **全 Class が「DFKK＋独立 1 block」で承認され得る**: 閾値統一の帰結として明示的に受容する。緩和は手続側（Class C の 14 日公開討議・全異議応答義務・外部レビュー・実行前 7 日公示・exit window・署名拒否義務）と §4.3（capture 経路の遮断）。署名者拡大時に閾値強化を再検討する。
3. **独立性の実在への依存**: 独立署名主体が実態として DFKK から独立していることが全体の前提であり、表明・記録の年次更新・公開でしか担保できない。
4. **Admin multisig 侵害時に delay 中の proposal を cancel できる第三者がいない**: [Mainnet-Timelock-Deploy-Policy.md](./Mainnet-Timelock-Deploy-Policy.md) 等で受容済みのリスクを本書でも継続受容する（緩和: 高定足数・署名専用環境・共通 Timelock delay 中の監視退避・INV-4）。
5. **bound・exit window は Day-1 では手続的拘束**であり、コード強制ではない。署名チェックリスト・公開 calldata 検証・四半期 readback で補う。
