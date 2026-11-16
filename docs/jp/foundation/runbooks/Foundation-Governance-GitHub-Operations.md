# Foundation Governance GitHub Operations

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Domain | Foundation |
| Lifecycle | Operations |
| Artifact Type | Runbook |
| Decision Authority | Foundation Governance |
| Maintainer | DeltaForesight |
| Legal Steward / Custodian | Foundation |
| Visibility | Private |
| Status | Draft |
| Normative Source | [`Foundation-Entity-Corporate-Decision-Process.md`](./Foundation-Entity-Corporate-Decision-Process.md)と有効なOA / Schedule（approval / execution）/ [`Governance-Record-Reference-Spec.md`](../../Governance-Record-Reference-Spec.md)（cross-repository reference） |

本書は、Foundation GovernanceがGitHubを非公開CDRの記録・レビュー基盤として使う方法を定める。CD Class、承認threshold、Memberの法的承認要件はNormative Sourceを正とし、本書はそれらを変更しない。

---

## 1. Repository and Authority Boundary

| Repository / store | 保存するもの | 保存しないもの |
| --- | --- | --- |
| `deltaforesight/jpydf-foundation-governance`（Private） | CDR、Member討議・投票、Foundation operating assetsの承認、契約・filingのevidence index、CD-0 log | passport、住所、KYC / KYB link、raw legal / tax memo、秘密、private key、完全な契約原本 |
| Restricted corporate records | KYC / KYB / BOIR、契約原本、legal / tax memo、署名済み書類、bank / filing receipt、private evidence | repository recordの重複正本 |
| Public minimum surface | RMI / MIDAO registry、法令上必要な連絡先、Companyを直接運営するsmart-contract identifier、public blockchain上のFoundation Operating Multisig transaction | CDR全文やMember討議 |

Private repositoryはCompany Governance Workspaceであり、RMI法上の`Official Online Venue`と自動的に同一視しない。Official Online Venueの指定・公開範囲はOA / ScheduleとRMI counsel・MIDAO / Registered Agentの確認に従う。

GitHubのrepository admin、maintainer、CODEOWNER、PR reviewerであることだけでは、Foundation Member、Company agentまたはFoundation Governanceの決定主体にならない。Issueのclose、Discussionのlock、PRのmerge、label変更も承認判定の代替にしない。

## 2. GitHub Artifact and Governance Effect

| Artifact | 用途 | それ単独で生じない効果 |
| --- | --- | --- |
| Issue | intake、採番依頼、担当割当、期限管理 | CDRの承認 |
| Discussion | Member間の論点・異議の記録 | vote、approval、execution authorization |
| Proposal PR | CDR本文と差分のreview、Decision Package freeze | 所定thresholdを満たさない承認 |
| GitHub Review / vote record | 登録Memberの記名・理由付き意思表示 | 権限外reviewerのvote、package hash不一致のvote |
| Merge | 承認済みrecordをdefault branchへ収載するministerial action | 未承認内容の追認、Foundation Operating Multisig transactionの承認 |
| Record PR | receipt、signed agreement ref、execution evidenceを追記する | 承認済みDecision Packageの変更 |

## 3. Operating Flow

### 3.1 Intake to Review

1. 起案者がIssue Formでintakeを作成し、秘密情報を記入しない。
2. record ownerが重複を確認し、CDR ID、CD Class候補、owner、期限を割り当てる。
3. 起案者が現行CDR templateからproposal branchとPRを作成する。
4. 討議が必要な場合はPrivate Discussionを作り、Issue・Discussion・PRを相互リンクする。
5. record ownerが必須項目、Class、conflict / recusal、required review、evidence locationを形式確認する。

### 3.2 Package Freeze and Approval

1. 起案者がDecision Package内の未確定箇所を解消する。
2. CIが`package_sha256`を計算・検証する。
3. record ownerがstatusを`Voting`へ移す。
4. 登録Memberが同じ`package_sha256`に対して記名・理由付きvoteを残す。
5. package本文を変更した場合はhashを更新し、旧hashへの承認をstaleとして再取得する。
6. threshold、recusal、適用する社内legal / tax analysisとtransaction controls、RMI filing要件、notice、expiryを満たしたことをCIとrecord ownerが確認する。

### 3.3 Record, Execute, Close

1. approval gate通過後にproposal PRをmergeする。merge actorは内容を再裁定しない。
2. Execution Actorはdefault branch上の承認済みCDR ID・hashとexecution packageの一致を確認する。
3. Foundation Operating MultisigまたはCDRで明示されたCompany agentが承認済み行為を実行する。
4. record ownerがrecord PRを作り、receipt、signed agreement ref、transaction、evidence referenceを追記する。Decision Packageは変更しない。
5. mismatchはcloseせず、incidentまたはcorrective CDRとして扱う。
6. close後にGitHub metadataとexternal evidence indexをexportする。

### 3.4 Cross-Repository Reference

`jpydf-v2`、public JIP、restricted evidence indexからCDRを参照する場合は、[`Governance-Record-Reference-Spec.md`](../../Governance-Record-Reference-Spec.md)のreference envelopeを使う。

- publicまたはrepository-visible文書へCDR本文、private URL、Member、vote、理由、restricted storage pathを記録しない。
- public JIPをCDRから参照する場合も、IDとURLだけで承認済みと推定せず、`package_sha256`と`source_revision`を照合する。
- CDRのstatusを`Approved`以降として参照する場合、同じrecord stateの`approved_at`、`package_sha256`、`source_revision`を必須とする。
- private executionに公開可能なidentifierがない場合、`execution_refs`は空配列とし、private CDRとrestricted evidence indexを完了判定の正本とする。
- public surfaceへ出すreferenceはSpecの§4.2を超えない。

## 4. Decision Package Freeze

CDR templateの次のmarker間をDecision Packageとする。

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

承認後に更新できるのは、marker外のstatus、approval index、execution、receipt、evidence reference等の事務記録だけである。Decision Packageを変更する場合は同じPR内でvoteをresetするか、新CDRでsupersedeする。

標準vote recordは次を満たす。

```text
RECORD-TYPE: CDR-VOTE
ID: <CDR-YYYY-NNN>
PACKAGE-SHA256: <64 hex>
VOTER: <registered Member identifier>
CAPACITY: Foundation Member
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
decisions/YYYY/CDR-YYYY-NNN.md
ministerial/YYYY-MM.md
register/cdr-index.md
register/access-review.md
exports/YYYY-MM/<export-manifest>.md
.github/ISSUE_TEMPLATE/cdr-intake.yml
.github/DISCUSSION_TEMPLATE/cdr-discussion.yml
.github/PULL_REQUEST_TEMPLATE/cdr.md
.github/CODEOWNERS
.github/workflows/corporate-record-gate.yml
```

Confidential原本はcommitせず、`evidence_ref`とdigestだけを保存する。

| 種別 | Labels |
| --- | --- |
| Type | `type:cdr`, `type:ministerial` |
| Class | `class:CD-0`, `class:CD-1`, `class:CD-2`, `class:CD-3`, `class:CD-P` |
| State | `state:intake`, `state:open`, `state:draft`, `state:review`, `state:voting`, `state:approved`, `state:executing`, `state:executed`, `state:logged`, `state:closed` |
| Outcome | `outcome:rejected`, `outcome:expired`, `outcome:cancelled`, `outcome:superseded` |
| Gate | `needs:legal`, `needs:tax`, `needs:midao`, `blocked:conflict`, `blocked:evidence` |

Labelは検索・queue管理用であり、Markdown frontmatterのstatusをrecordの正本とする。

| From | To | Gate |
| --- | --- | --- |
| Intake | Draft | ID、owner、Class候補を割当 |
| Draft | Review | 必須項目が埋まり、秘密情報を除外 |
| Review | Voting | required reviewと討議期間を満了し、package freeze |
| Voting | Approved | threshold、recusal、異議応答、expiry、hash一致 |
| Approved | Executing | merge、execution checklist |
| Executing | Executed | approved action成功、receipt、package match |
| Executed | Closed | evidence index、follow-up、mismatchなし |
| Open | Logged / Closed | CD-0月次review、escalation、missing evidence、次月deadlineを記録 |
| Any pre-execution | Rejected / Expired / Cancelled | 理由、actor、timestampを記録 |
| Closed | Superseded | 後続IDを相互参照し、過去recordは改変しない |

## 6. Access and Repository Rules

- visibilityはPrivateとし、organization base permissionによる意図しない閲覧を禁止する。
- Member、record owner、repository custodian、必要なcounsel / auditorをrole別teamに分ける。
- repository custodianは技術管理者であり、Memberでない限りvoteを持たない。
- outside collaboratorを含め2FAを必須とし、四半期ごとおよびMember / service provider変更時にaccess reviewを行う。
- private forkとexternal Actions reuseを無効化し、workflow log / artifactへprivate evidenceを出力しない。
- offboarding時はrepository access削除に加え、local clone削除確認をevidence化する。
- `main`はPR経由のみとし、direct push、force push、branch deletionを禁止する。
- stale approval dismissal、latest reviewable pushの他者承認、conversation resolution、required checksを有効にする。
- admin bypassを常用しない。break-glass利用はincident recordと事後reviewを必須にする。
- CODEOWNERS reviewをFoundation Member thresholdの代替にしない。

## 7. Required Automated Checks

| Check | Fail条件 |
| --- | --- |
| Schema | 必須frontmatter / section欠落、未知status / Class |
| ID | 重複、pathとID / year不一致、採番飛びの説明なし |
| Package | marker不正、`package_sha256`不一致、Voting後のpackage変更 |
| Approval | 指定外voter、hash不一致、threshold不足、recusal / conflict違反、期限切れ |
| Transition | 許可されないstatus遷移、Approved後の本文変更 |
| Evidence | execution後のreceipt / evidence ref欠落 |
| Boundary | secret、KYC / KYB、個人情報、契約原本の混入 |
| Link | repository内relative link切れ、CDR相互参照不一致 |

各checkは走査件数・対象ID・vote集計をlogに出し、走査対象0件やMember register未読込を成功扱いにしない。

## 8. Backup, Export, and Retention

- GitHubを唯一のarchiveにしない。
- 月次でdefault branch、Issue / PR / Discussion metadata、review / comment、workflow evidenceをexportする。
- export manifestにrepository、visibility、export timestamp、head SHA、件数、archive digest、保存先evidence refを記録する。
- OA / applicable lawの保存期間に従い、少なくとも解散後5年までcorporate recordsを保持する。
- 四半期ごとにrestore testを行い、branch、CDR、vote、execution evidenceを再構成できることを確認する。
- Public recordを参照する場合もURLだけに依存せず、record ID、commit SHA、digestを保存する。

## 9. Bootstrap and Go-Live Checklist

1. repository owner、name、Private visibilityを確定する。
2. Corporate Decision Processの正本commit SHAとtemplate versionを固定する。
3. teams / collaborators / 2FA / offboarding ownerを設定する。
4. directory、Issue Form、Discussion category、PR template、CODEOWNERS、labelsを作る。
5. Member mappingと権限台帳を登録し、raw identityをcommitしない。
6. branch rulesとCIを有効化し、admin bypassを無効または監査対象にする。
7. backup destination、export schedule、retention owner、restore testを設定する。
8. dummy CDRでIntakeからCloseまで通し、CD-0 monthly logも検証する。
9. stale vote、recusal、threshold不足、package改変、期限切れ、secret混入がfailすることを確認する。
10. 全Memberがgo-live evidenceを確認してから実案件を開始する。

Repository作成、visibility設定、collaborator招待、ruleset適用は外部状態を変更するため、別途明示承認を得て実施する。

Copy-ready assets:

- [`CDR-Intake-Issue-Form.yml`](../templates/governance/CDR-Intake-Issue-Form.yml) → `.github/ISSUE_TEMPLATE/cdr-intake.yml`
- [`CDR-Pull-Request-Template.md`](../templates/governance/CDR-Pull-Request-Template.md) → `.github/PULL_REQUEST_TEMPLATE/cdr.md`

## 10. Sources

- [RMI Decentralized Autonomous Organization Act 2022, as amended](https://rmiparliament.org/cms/images/LEGISLATION/PRINCIPAL/2022/2022-0050/2022-0050_2.pdf)
- [RMI DAO Regulations 2024](https://rmiparliament.org/cms/images/LEGISLATION/SUBORDINATE/2024/2024-0001/2024-0001_1.pdf)
- [GitHub Docs: syntax for Issue Forms](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms)
- [GitHub Docs: managing Discussion categories](https://docs.github.com/en/discussions/managing-discussions-for-your-community/managing-categories-for-discussions)
- [GitHub Docs: protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges/managing-protected-branches/about-protected-branches)
- [GitHub Docs: repository roles](https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization)
