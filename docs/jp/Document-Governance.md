# JPY DeFi 文書ガバナンスポリシー

> Status: Active
>
> Classification: Meta document
>
> Lifecycle: Evergreen
>
> Artifact Type: Policy
>
> Applies to: `documents/` 配下の JPYdf 文書、および文書から参照する governance record / manifest / evidence

## 1. 目的

JPYdf の文書を、次の3つの独立した軸で分類する。

1. **Domain** — 何についての文書か
2. **Lifecycle** — いつ必要な文書か
3. **Artifact Type** — 何のための文書か

これにより、Protocol、Protocol Governance、Contributor、Foundation の責任と決定権、および Day1 launch と launch 後の運用を混同しない。各情報の正本を1か所に定め、同じ決定・値・手順を複数文書へ重複して書かない。

本ポリシーは文書の分類・正本・配置を定める。Protocol の機能、個別のリスク判断、法人の権限そのものは定めない。

## 2. Domain — 対象と決定権

| Domain | 扱うもの | 決定権 |
| --- | --- | --- |
| `Protocol` | 機能、仕様、不変条件、担保・リスク基準、権限、parameter の意味、変更可能範囲、利用者への約束 | Protocol Governance。ただし、immutable code や放棄済み権限は文書上の決定だけでは変更できない |
| `Protocol Governance` | JIP、意思決定手続、privileged action の提案・承認・Timelock・on-chain execution、Protocol Treasury、実行記録 | Protocol Governance |
| `Contributor` | 実装、監査調整、infra、監視、調査、提案作成、担当者、予算、自己資金・流動性 commitment | 当該 Contributor。DeltaForesight に関する事項は DeltaForesight |
| `Foundation` | 法人設立、Member、OA、法務・compliance、IP・trademark・domain・documentation stewardship、契約、Foundation operating assets、法人内部手続 | Foundation の法人機関（`Foundation Governance`） |

`Foundation Governance` を Foundation の意思決定系統を表す横断分類名とする。OA、resolution、legal opinion 等で `Company Governance Approval` のような定義語が必要な場合は、その法人文書内に限って原文どおり使用できる。この場合の `Company` は DeltaForesight株式会社を意味する分類名ではない。

Foundation と Protocol Governance は別の権限系統である。Foundation が IP、domain、documentation を steward しても Protocol の仕様変更権限を取得しない。Foundation の詳細な権限・禁止事項は [`Foundation-Entity-Setup-Requirements.md`](./foundation/requirements/Foundation-Entity-Setup-Requirements.md) を正本とし、本ポリシーでは再掲しない。

### 2.1 組織名と役割を分ける

組織名だけで Domain や決定権を判断しない。同じ組織が複数の立場で関与し得るため、文書では立場を明示する。

- DeltaForesight が実装・監視・提案作成を行う場合: `Contributor`
- DeltaForesight 関係者が Protocol signer として行動する場合: `Protocol Governance`
- DeltaForesight が Foundation との契約に基づき事務を行う場合: `Foundation` の service provider

`Maintainer`、`Decision Authority`、`Steward` は別の属性である。たとえば「DeltaForesight が maintain、Protocol Governance が approve、Foundation が steward」という関係を表現でき、maintain や steward を仕様変更権限とみなさない。

## 3. Lifecycle — 時間軸

| Lifecycle | 対象 |
| --- | --- |
| `Evergreen` | launch 前後を通じて有効な仕様、不変条件、恒常的な判断基準 |
| `Launch` | Day1 mainnet launch の前提条件、初期値、role handover、freeze、readiness gate |
| `Operations` | launch 後の監視、incident 対応、担保追加、Cap 変更、oracle / strategy 差替え、parameter 変更、定期保守 |
| `Historical` | 実行済み decision、evidence、日付付き snapshot、廃止済み判断 |
| `Future` | 未採用・未 activation の候補。現行仕様や現行手順として扱わない |

`Launch` の完了後も、再現・監査に必要な manifest、decision record、evidence は `Historical` として保持する。launch 後の現行値は Day1 文書を上書きせず、on-chain state と Operations の artifact で管理する。

## 4. Artifact Type — 文書の役割

原則として、1文書に複数の Artifact Type を同居させない。

| Artifact Type | 答える問い | 含めるもの | 含めないもの |
| --- | --- | --- | --- |
| `Spec` | 何が成立しなければならないか | 機能、interface、不変条件、制約、受入条件 | 実行担当者、承認議事、逐次操作手順 |
| `Policy` | 誰が、どの条件で判断するか | 判断基準、authority、threshold、例外、変更条件 | 個別案件の判断理由、コマンド列 |
| `Runbook / Gate` | どう実行・検証するか | prerequisite、手順、rollback / abort 条件、完了条件 | 仕様の再定義、個別値の正本 |
| `Manifest` | 特定環境・release に何が存在するか | chain ID、contract address、implementation、role holder、parameter、artifact hash、生成時刻・block | 判断基準、理由、秘密鍵 |
| `Decision Record` | なぜその判断をしたか | 選択肢、根拠、approval、effective condition | 現行仕様や値の全面的な複製 |
| `Evidence` | 実際に何を検証・実行したか | transaction、block、test / monitoring result、署名済み記録、照合結果 | 将来の要件や承認ルール |

同じ業務フローで複数 Artifact Type が必要な場合は別ファイルに分け、相互参照する。たとえば担保追加は、受入基準を `Policy`、実行手順を `Runbook`、承認を `Decision Record`、反映値を `Manifest`、on-chain 照合を `Evidence` に置く。

Manifestは対象scopeを明示すれば、parameter、address / wiring、role holder等に分割できる。scope外のfieldを埋めるために別Manifestの内容を複製しない。人間が承認するMarkdownと機械可読artifactを併用する場合は、それぞれのscopeと正本関係を明示し、同じ値を手作業で二重管理しない。

Manifest の schema、state transition、生成・照合方法、および既存文書からの移行方法は、本ポリシーではなく対象システムの Spec / Policy / migration plan で定める。

## 5. 正本の原則

1. **1つの情報に正本は1つ** — 仕様、判断基準、実行手順、値、判断理由、検証結果を、それぞれ対応する Artifact Type に置く。
2. **索引は正本を指す** — README や一覧表は入口であり、詳細を複製しない。
3. **Decision Record は現行ルールを代替しない** — 決定後は必要に応じて Spec / Policy を更新し、Decision Record には理由と承認を残す。
4. **Evidence は要件を作らない** — 実行結果から新しい仕様を暗黙に導入しない。
5. **snapshot を上書きしない** — Day1、release、実行済み governance action の記録は immutable に扱う。

`documents/jp` は、本 repository が管理する日本語の現行文書の正本群である。ディレクトリ全体を単一の「プロダクト仕様」とは扱わない。英訳・公開用 mirror・要約は日本語の該当正本から派生させる。

README、index、本ポリシーのように複数 Domain を横断して配置・分類だけを定める文書は **Meta document** とする。`Meta` は業務上の第5 Domainではなく、4 Domain の境界を管理するための例外である。

Meta documentのうち、正本を指すだけのREADMEは`Index`と表記できる。`Index`は非規範的な案内役であり、第7のArtifact Typeではない。

## 6. Repository と visibility

| 対象 | Visibility | 正本の置き場所 |
| --- | --- | --- |
| Protocol の Spec / Policy、launch・operations の Runbook、repositoryで管理するContributor文書 | repository 方針に従う | `jpydf-v2` の `documents/jp/` |
| Foundationのrequirements、Spec、Policy、Runbook、Template、repositoryで管理するEvidence / reference source | 文書ごとのmetadataに従う | `jpydf-v2` の `documents/jp/foundation/` |
| Protocol Governance の proposal、vote、execution record | Public | `jpydf-governance` |
| Foundation Governance の CDR、Member 討議・vote、法人内部の execution record | Private | `jpydf-foundation-governance` |
| 契約、本人確認資料、法務意見、会計、署名原本等の restricted record | Need-to-know | access-controlled corporate storage |

現在`jpydf-v2`で追跡しているFoundation関連Markdownは、再配置時も削除または外部化せず、内容とgit履歴を保ったまま`documents/jp/foundation/`配下へ移す。`foundation/`はFoundation Domainの配置境界であり、公開文書だけを意味しない。Visibilityは各文書のmetadataとrepository accessで管理する。

署名原本、KYC / KYB、個人情報、契約原本、bank / filing receipt等のraw restricted recordは、引き続きaccess-controlled corporate storageで管理する。この外部保管は、repositoryで追跡するrequirement、draft、index、reference copy等を削除する根拠にしない。

`jpydf-v2`からprivate / restricted recordへリンクする場合は、機密情報を含めず、record ID、承認日、hash等の検証に必要な最小情報だけを記載する。cross-repository referenceのfieldとvisibility境界は[`Governance-Record-Reference-Spec.md`](./Governance-Record-Reference-Spec.md)、各governance repositoryの運用は[`Protocol-Governance-GitHub-Operations.md`](./protocol/operations/runbooks/Protocol-Governance-GitHub-Operations.md)と[`Foundation-Governance-GitHub-Operations.md`](./foundation/runbooks/Foundation-Governance-GitHub-Operations.md)が定める。

## 7. `jpydf-v2` の目標構成

分類後の目標構成は次のとおりとする。空の組合せを表すためだけの directory は作成せず、文書の分割・移設は内容変更と分けて段階的に行う。

```text
documents/jp/
├── README.md
├── Document-Governance.md
├── Document-Inventory.md
├── Requirements-Spec-Standard.md
├── protocol/
│   ├── product/
│   │   ├── Product-Overview.md
│   │   ├── architecture/
│   │   ├── spec/
│   │   ├── parameters/
│   │   └── policies/
│   ├── launch/
│   │   ├── manifests/
│   │   ├── decisions/
│   │   ├── gates/
│   │   └── evidence/
│   ├── operations/
│   │   ├── policies/
│   │   ├── runbooks/
│   │   └── templates/
│   └── roadmap/
├── contributors/
│   └── deltaforesight/
│       ├── commitments/
│       ├── policies/
│       ├── manifests/
│       ├── delivery-plans/
│       ├── operations/
│       └── evidence/
├── foundation/
│   ├── requirements/
│   ├── spec/
│   ├── policies/
│   ├── manifests/
│   ├── runbooks/
│   ├── templates/
│   ├── evidence/
│   └── reference-sources/
├── engineering/
│   ├── plans/
│   ├── guides/
│   ├── verification-ledgers/
│   └── historical-reviews/
└── archive/
```

DeltaForesight の内部予算、人員、未公表契約等は `jpydf-v2` に置かず、同社の access-controlled workspace で管理する。

## 8. 文書メタ情報

新規文書、移設文書、または役割を読み違える可能性がある文書には、必要な項目だけを冒頭へ記載する。全既存文書への一括追加は行わない。

| Field | 用途 |
| --- | --- |
| `Domain` | 4 Domain のいずれを扱うか |
| `Lifecycle` | `Evergreen` / `Launch` / `Operations` / `Historical` / `Future` |
| `Artifact Type` | `Spec` / `Policy` / `Runbook` / `Gate` / `Manifest` / `Decision Record` / `Evidence` |
| `Decision Authority` | 内容を決定・承認できる主体 |
| `Maintainer` | 更新案、実装、整合性維持を担当する主体 |
| `Legal Steward / Custodian` | IP・公開・保管等を管理する主体。決定権とは限らない |
| `Visibility` | `Public` / `Private` / `Need-to-know` 等の公開範囲 |
| `Status` | 現在有効、draft、historical 等の文書状態 |
| `Normative Source` | mirror、要約、evidence 等が参照する正本 |

### 8.1 Status語彙

Statusは文書の現在の役割を示す。更新時は次の語彙だけを使い、過去時点の状態は本文ではなくHistorical artifactに残す。

| Status | 意味 |
| --- | --- |
| `Active` | 現在有効な仕様・方針・計画・手順 |
| `Draft` | 内容が未確定で、現行判断の正本にできない文書 |
| `Future Draft` | 未実装で、別のactivation判断を要する将来仕様 |
| `Historical` | 日付付きreview・検証記録・過去判断 |
| `External Source` | 外部原文またはその保存版 |
| `Template` | 未記入の雛形 |

Status表を全ファイルへ一括追加しない。文書の役割が読み違えられる場合だけ冒頭に置く。

例:

```text
Domain: Protocol
Lifecycle: Operations
Artifact Type: Policy
Decision Authority: Protocol Governance
Maintainer: DeltaForesight (Contributor)
Status: Active
```

## 9. 移行ルール

既存文書の分類・移設は、次の順で小さな Pull Request に分ける。

1. 本ポリシーと index を確定する
2. 既存文書を Domain × Lifecycle × Artifact Type で棚卸しする
3. 混在文書を Artifact Type ごとに分割する
4. Artifact 固有の schema、生成、照合、移行方法は別の Spec / Policy / migration plan で定める
5. 旧 path の参照、日英文書、外部 repository とのリンクを更新する

移設だけの変更と内容変更を同じ Pull Request に混在させない。移設時は repository 内リンク、生成処理、参照元を検証し、履歴を追える形で行う。
