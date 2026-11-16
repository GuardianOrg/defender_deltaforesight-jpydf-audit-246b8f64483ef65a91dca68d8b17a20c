# Protocol Governance GitHub Operations

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Domain | Protocol Governance |
| Lifecycle | Operations |
| Artifact Type | Runbook |
| Decision Authority | Protocol Governance |
| Maintainer | DeltaForesight |
| Visibility | Public |
| Status | Draft |
| Normative Source | [`Day-1-Governance-Proposal-Execution-Policy.md`](../../launch/gates/Day-1-Governance-Proposal-Execution-Policy.md)（approval / execution）/ [`Governance-Record-Reference-Spec.md`](../../../Governance-Record-Reference-Spec.md)（cross-repository reference） |

本書は、Protocol GovernanceがGitHubを公開JIPの記録・レビュー基盤として使う方法を定める。JIPのClass、承認threshold、notice、execution authorityはNormative Sourceを正とし、本書はそれらを変更しない。

---

## 1. Repository and Authority Boundary

| Repository / store | 保存するもの | 保存しないもの |
| --- | --- | --- |
| `deltaforesight/jpydf-governance`（Public） | JIP、公開討議、承認記録、calldata / simulation evidence、execution / readback、Governance Surface Register、Transparency Report | private signer security、未公開脆弱性、個人情報、秘密 |
| Restricted security records | 非公開脆弱性、private signer security、必要なincident evidence | 公開Protocol recordの重複正本 |

GitHubのrepository admin、maintainer、CODEOWNER、PR reviewerであることだけでは、Protocol Signer、Execution ActorまたはProtocol Governanceの決定主体にならない。Issueのclose、Discussionのlock、PRのmerge、label変更も承認判定の代替にしない。

## 2. GitHub Artifact and Governance Effect

| Artifact | 用途 | それ単独で生じない効果 |
| --- | --- | --- |
| Issue | intake、採番依頼、担当割当、期限管理 | JIPの承認 |
| Discussion | 公開討議、論点・異議の記録 | vote、approval、execution authorization |
| Proposal PR | JIP本文と差分のreview、Decision Package freeze | 所定thresholdを満たさない承認 |
| GitHub Review / vote record | 登録signer blockの記名・理由付き意思表示 | 権限外reviewerのvote、package hash不一致のvote |
| Merge | 承認済みrecordをdefault branchへ収載するministerial action | 未承認内容の追認、Safe transactionの実行承認 |
| Record PR | execution / readbackを追記する | 承認済みDecision Packageの変更 |

## 3. Operating Flow

### 3.1 Intake to Review

1. 起案者がIssue Formでintakeを作成し、秘密情報を記入しない。
2. record ownerが重複を確認し、JIP ID、Class候補、owner、期限を割り当てる。
3. 起案者が現行JIP templateからproposal branchとPRを作成する。
4. 討議が必要な場合はDiscussionを作り、Issue・Discussion・PRを相互リンクする。
5. record ownerが必須項目、Class、conflict / recusal、required review、evidence locationを形式確認する。

### 3.2 Package Freeze and Approval

1. 起案者がDecision Package内の未確定箇所を解消する。
2. CIが`package_sha256`を計算・検証する。
3. record ownerがstatusを`Voting`またはProtocol Policy上のapproval-ready stateへ移す。
4. 登録signer blockが同じ`package_sha256`に対して記名・理由付きvoteを残す。
5. package本文を変更した場合はhashを更新し、旧hashへの承認をstaleとして再取得する。
6. threshold、recusal、review、notice / discussion period、expiryを満たしたことをCIとrecord ownerが確認する。

### 3.3 Record, Execute, Close

1. approval gate通過後にproposal PRをmergeする。merge actorは内容を再裁定しない。
2. Execution Actorはdefault branch上の承認済みJIP ID・hashとexecution packageの一致を確認する。
3. 承認済みSafe / Timelock手順で実行する。
4. record ownerがrecord PRを作り、tx、readback、evidence referenceを追記する。Decision Packageは変更しない。
5. mismatchはcloseせず、incidentまたはcorrective JIPとして扱う。
6. close後にGitHub metadataとevidenceをexportする。

### 3.4 Cross-Repository Reference

`jpydf-v2`、Foundation record、外部Evidence indexからJIPを参照する場合は、[`Governance-Record-Reference-Spec.md`](../../../Governance-Record-Reference-Spec.md)のreference envelopeを使う。

- JIP本文・vote・calldataを参照先へ複製しない。
- public JIPの`locator`はdefault branchのmutable URLではなく、`source_revision`へ固定したpermalinkとする。
- Foundation CDRをJIPから参照する場合、private URL、Member、vote、理由をpublic recordへ記録しない。
- JIPのstatusを`Approved`以降として参照する場合、同じrecord stateの`approved_at`、`package_sha256`、`source_revision`を必須とする。
- execution / readbackのrecord PR後にenvelopeを新しい`source_revision`へ更新し、Git履歴からApproved時点とExecuted / Closed時点を再構成できるようにする。

## 4. Decision Package Freeze

JIP templateの次のmarker間をDecision Packageとする。

```markdown
<!-- BEGIN DECISION PACKAGE -->
...
<!-- END DECISION PACKAGE -->
```

`package_sha256`は次のcanonical bytesに対するSHA-256とする。

- marker行自体を除く。
- UTF-8、改行はLF。
- 行末spaceを削除しない。
- package最終行の後にLFを1つ置く。

承認後に更新できるのは、marker外のstatus、approval index、execution、readback、evidence reference等の事務記録だけである。Decision Packageを変更する場合は同じPR内でvoteをresetするか、新JIPでsupersedeする。

標準vote recordは次を満たす。

```text
RECORD-TYPE: JIP-VOTE
ID: <JIP-YYYY-NNN>
PACKAGE-SHA256: <64 hex>
VOTER: <registered signer block identifier>
CAPACITY: Protocol Signer Block
VOTE: FOR | AGAINST | ABSTAIN | RECUSED
CONFLICT: none | <disclosure ref>
REASON: <reason or stable URL>
TIMESTAMP: <ISO-8601 UTC>
SIGNATURE-REF: <required signature or consent evidence ref>
```

登録外account / capacity、hash不一致、`ABSTAIN` / `RECUSED`、reason不記載、conflict・expiry・Class別review違反、撤回済み、identity / signature検証失敗のvoteは賛成票に算入しない。

## 5. Repository Layout, Labels, and State

```text
README.md
proposals/YYYY/JIP-YYYY-NNN.md
emergency/YYYY/JIP-E-YYYY-NNN.md
registry/governance-surface.md
registry/permissions-ledger.md
reports/YYYY-QN-transparency.md
.github/ISSUE_TEMPLATE/jip-intake.yml
.github/DISCUSSION_TEMPLATE/jip-discussion.yml
.github/PULL_REQUEST_TEMPLATE/jip.md
.github/CODEOWNERS
.github/workflows/governance-record-gate.yml
```

| 種別 | Labels |
| --- | --- |
| Type | `type:jip`, `type:jip-e` |
| Class | `class:N`, `class:C`, `class:E` |
| State | `state:intake`, `state:draft`, `state:review`, `state:voting`, `state:approved`, `state:queued`, `state:executing`, `state:executed`, `state:emergency-open`, `state:closed` |
| Outcome | `outcome:rejected`, `outcome:expired`, `outcome:cancelled`, `outcome:superseded` |
| Gate | `needs:legal`, `needs:tax`, `needs:security`, `blocked:conflict`, `blocked:evidence` |

Labelは検索・queue管理用であり、Markdown frontmatterのstatusをrecordの正本とする。

| From | To | Gate |
| --- | --- | --- |
| Intake | Draft | ID、owner、Class候補を割当 |
| Draft | Review | 必須項目が埋まり、秘密情報を除外 |
| Review | Voting | required reviewと討議期間を満了し、package freeze |
| Voting | Approved | threshold、recusal、異議応答、expiry、hash一致 |
| Approved | Queued / Executing | merge、notice / exit window、execution checklist |
| Queued / Executing | Executed | approved action成功、tx、package match |
| Executed | Closed | readback、evidence、follow-up、mismatchなし |
| Any pre-execution | Rejected / Expired / Cancelled | 理由、actor、timestampを記録 |
| Closed | Superseded | 後続IDを相互参照し、過去recordは改変しない |

## 6. Access and Repository Rules

- visibilityはPublicとする。
- publicはIssue / Discussionへ参加できる。default branchへのwriteはgovernance maintainersと登録signer-block accountsに限定する。
- signer block、record owner、repository custodianのGitHub account mappingを公開registerで管理する。
- 未公開脆弱性はpublic Issue / Discussionに書かず、security intakeへ送る。
- `main`はPR経由のみとし、direct push、force push、branch deletionを禁止する。
- stale approval dismissal、latest reviewable pushの他者承認、conversation resolution、required checksを有効にする。
- admin bypassを常用しない。break-glass利用はincident recordと事後reviewを必須にする。
- CODEOWNERS reviewをN-of-M governance thresholdの代替にしない。

## 7. Required Automated Checks

| Check | Fail条件 |
| --- | --- |
| Schema | 必須frontmatter / section欠落、未知status / Class |
| ID | 重複、pathとID / year不一致、採番飛びの説明なし |
| Package | marker不正、`package_sha256`不一致、Voting後のpackage変更 |
| Approval | 指定外voter、hash不一致、threshold不足、recusal / conflict違反、期限切れ |
| Transition | 許可されないstatus遷移、Approved後の本文変更 |
| Evidence | execution後のtx / readback ref欠落 |
| Boundary | private evidence、secret、個人情報の混入 |
| Link | repository内relative link切れ、JIP相互参照不一致 |

各checkは走査件数・対象ID・vote集計をlogに出し、走査対象0件やregister未読込を成功扱いにしない。

## 8. Backup, Export, and Retention

- GitHubを唯一のarchiveにしない。
- 月次でdefault branch、Issue / PR / Discussion metadata、review / comment、release / workflow evidenceをexportする。
- export manifestにrepository、visibility、export timestamp、head SHA、件数、archive digest、保存先evidence refを記録する。
- 四半期ごとにrestore testを行い、branch、JIP、vote、execution evidenceを再構成できることを確認する。

## 9. Bootstrap and Go-Live Checklist

1. repository owner、name、Public visibilityを確定する。
2. Policyの正本commit SHAとtemplate versionを固定する。
3. teams、2FA、offboarding ownerを設定する。
4. directory、Issue Form、Discussion category、PR template、CODEOWNERS、labelsを作る。
5. signer-block mappingと権限台帳を登録する。
6. branch rulesとCIを有効化し、admin bypassを無効または監査対象にする。
7. backup destination、export schedule、retention owner、restore testを設定する。
8. dummy JIPでIntakeからCloseまで通す。
9. stale vote、recusal、threshold不足、package改変、期限切れ、secret混入がfailすることを確認する。
10. 全signer blockがgo-live evidenceを確認してから実案件を開始する。

Repository作成、visibility設定、collaborator招待、ruleset適用は外部状態を変更するため、別途明示承認を得て実施する。

Copy-ready assets:

- [`JIP-Intake-Issue-Form.yml`](../templates/JIP-Intake-Issue-Form.yml) → `.github/ISSUE_TEMPLATE/jip-intake.yml`
- [`JIP-Pull-Request-Template.md`](../templates/JIP-Pull-Request-Template.md) → `.github/PULL_REQUEST_TEMPLATE/jip.md`

## 10. Sources

- [GitHub Docs: syntax for Issue Forms](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms)
- [GitHub Docs: managing Discussion categories](https://docs.github.com/en/discussions/managing-discussions-for-your-community/managing-categories-for-discussions)
- [GitHub Docs: protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [GitHub Docs: repository roles](https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles-for-an-organization)
