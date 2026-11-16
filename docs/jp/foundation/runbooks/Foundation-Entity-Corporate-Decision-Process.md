# Foundation Entity Corporate Decision Process

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Draft |
| Owner | DeltaForesight |
| 対象 | RMI DAO LLC として組成する Foundation の Company Governance、Corporate Decision Record（CDR）、Foundation affairs および Protocol-linked company-side acts に限定された承認・執行・記録手続 |
| 文書の役割 | Company Governance Approval とその執行を Protocol Governance と混同せずに記録するための運用手順 |
| Operational workspace | `deltaforesight/jpydf-foundation-governance`（Private。設立・go-live 前） |
| 正本関係 | Foundation core requirements は [`Foundation-Entity-Setup-Requirements.md`](../requirements/Foundation-Entity-Setup-Requirements.md)、RMI / Registered Agent / BOIR / Member 構成は [`Foundation-Entity-RMI-DAO-LLC-Requirements.md`](../requirements/Foundation-Entity-RMI-DAO-LLC-Requirements.md)、actions under Protocol Governance は [`Day-1-Governance-Proposal-Execution-Policy.md`](../../protocol/launch/gates/Day-1-Governance-Proposal-Execution-Policy.md) が正本 |
| 非対象 | protocol upgrade、oracle source 差替、writeoff、unpause、bridge minter activation、Strategy / venue 登録変更、Protocol Treasury 移動、Protocol Safe signer / holder 変更等の action under Protocol Governance の承認そのもの |

本書は法的助言ではない。本書は有効な OA および適用法に従って運用し、適用法上必要な filing・consent・approval その他の実体条件を各 CDR に記録する。有効な OA と本書が矛盾する場合は OA を優先し、本書を更新する。

---

## 1. Boundary and Privacy Model

CDR は Company Governance の運用記録として、Company / Foundation 自身の権限・資産・契約・記録に関する内部決定だけを扱う。action under Protocol Governance は、Company Governance Approval や Foundation Operating Multisig Wallet による action では承認・代替できない。

| 行為 | 本書で扱うか | 正本 / 条件 |
| --- | --- | --- |
| OA 改定、Member admission / dissociation、Foundation Operating Multisig Wallet、Representative Agent、service provider 契約、Foundation operating assets、related-party payment、Protocol Claim の会社側対応、Claim Commitment、indemnity / advancement、redomicile / dissolution | 扱う | OA / CDR / corporate records |
| 年次 filing、Registered Agent / Representative Agent 対応、KYC / KYB / BOIR 書類回収、Good Standing 維持の定型記録 | 扱う | CD-0 または CD-3 |
| upgrade、oracle source 差替、writeoff、unpause、bridge minter activation、Strategy 追加、Protocol Treasury 移動、Protocol Safe signer / holder 変更 | 扱わない | Day-1 Governance Policy |
| Approved JIP に付随する契約署名、notice、filing、counterparty communication、Foundation records 更新 | 条件付きで扱う | CD-P。JIP approval と Company 側 Member approval の両方が必要 |

### 1.1 Private by Default

- CDR、Member 討議、vote、契約承認、支払承認、compliance record は `jpydf-foundation-governance` の private repository で扱う。
- private repository は **Company Governance Workspace** であり、RMI 法上の `Official Online Venue` と自動的に同一視しない。Official Online Venue の指定要否・公開範囲は、OA および適用法に従う。
- CDR の public summary は既定で作らない。法令、filing、契約、counterparty 要請、または Member decision により必要な場合だけ、承認された範囲を開示する。
- applicable public registry、法令上必要な連絡先、Company を直接運営する smart-contract identifier、public blockchain 上の transaction 等、公開が必要または不可避な最小情報は private CDR と分離して管理する。
- private GitHub にも passport、住所、KYC / KYB link、private key、seed phrase、raw legal / tax memo、完全な契約原本を置かない。restricted corporate records への `evidence_ref` と digest だけを置く。

RMI DAO Act §711 の public distributed-ledger recordkeeping 特例に依存せず、CDR、議事・vote、会計・execution evidence を corporate records として保持する。Foundation Operating Multisig Wallet の identifier / transaction が public でも、関連 CDR や契約条件まで当然に公開されるものとは扱わない。

---

## 2. Roles, Capacities, and GitHub Access

同じ法人・自然人が複数の立場を兼ね得るため、CDR、vote および execution record では capacity を必ず記録する。

| Role | CDR 上の権限・責務 |
| --- | --- |
| Member | Company Governance を通じて OA 上の会社内部決議を行う。action under Protocol Governance の承認主体ではない。 |
| Nominee member | Member voting capacity を持たない。OA Article III.3 に定める登録・compliance filing 等を、Article V.4 に従い nominee member を明示的に授権する Company Governance Approval の範囲で会社側 capacity として行う。Representative Agent を兼ねる場合も capacity を区別して記録する。 |
| Foundation Operating Multisig Wallet およびその署名者 | Foundation operating assets と Foundation affairs の承認済み execution だけを行う。Membership とは別の capacity であり、Member との兼任だけでは signer authority を生じさせない。 |
| Representative Agent contact | Registered Agent から転送される correspondence / service of process 等を受領し、必要な社内連絡を行う。 |
| Counsel / tax advisor / Registered Agent or formation service provider | 必要に応じて外部助言または filing・compliance の実務支援を提供する。Member でない限り approval vote を持たず、その関与は独立した approval gate を構成しない。 |
| Protocol Signer | Protocol Governance に従う protocol action の signer。Company を bind する権限ではない。 |
| Repository custodian | private repository の access、ruleset、backup を管理する。Member でない限り vote を持たない。 |

GitHub の `Admin` / `Maintain` / `Write` / CODEOWNER / reviewer は技術的 role であり、OA 上の capacity を付与しない。Member GitHub account と Member address / designated voting wallet の mapping は private register で管理し、四半期ごとおよび変更時に review する。

---

## 3. Decision Classes and Approval Rules

`class` は事案の性質、`approval_rule` は有効な OA が要求する threshold・denominator・quorum を表す。CD-2 だから常に 4-of-5、CD-1 だから常に 3-of-5、とは機械的に決めない。適用法上必要な filing・consent・approval その他の実体条件は execution condition として記録し、外部 review の取得・完了自体を独立した approval gate としない。

| Class | 名称 | 対象 | 事前 approval |
| --- | --- | --- | --- |
| CD-0 | Ministerial / no-vote | 年次 filing 準備、Registered Agent / Representative Agent 連絡、KYC / KYB / BOIR 書類回収、records 整理、evidence index 更新 | record owner、Representative Agent contact、service provider が既存承認・既存契約・法定義務の範囲で処理する |
| CD-1 | Ordinary corporate decision | 通常予算内支出、非関連第三者 vendor 契約、通常 grant / service payment、records policy 更新、保険更新、公開文書の軽微改定、既存承認・予算の範囲内の Protocol Claim に関する定型的な法的・管理上の対応 | Foundation Operating Multisig Wallet または指定 Execution Actor が承認本文と一致する支払・署名・通知・記録だけを実施 |
| CD-2 | Protected / high-impact corporate decision | OA 改定、Member 変更、Foundation Operating Multisig Wallet またはその署名者の変更、related-party transaction、Claim Commitment、settlement、indemnity / advancement、Foundation operating assets の高額支出、asset boundary に影響する契約、redomicile、migration、dissolution | 承認済み Execution Actor だけが実施。利害関係者は conflict / recusal を記録する |
| CD-3 | Urgent compliance | Registered Agent / annual filing default、Good Standing 喪失リスク、BOIR / KYC 不備、Restricted Person 該当、期限付き Registrar / Registered Agent / competent authority notice | 保存的・可逆的措置だけを即時実施可。72h 以内に Member notice、7 日以内に CD-1 / CD-2 review |
| CD-P | Protocol-linked company action | Approved JIP に付随する契約署名、notice、filing、counterparty communication、Foundation records 更新 | Company Governance Approval の対象である Company 側 off-chain act だけを実施。protocol tx / signer-block action は Day-1 Governance Policy が正本 |

### 3.1 Approval Rule Snapshot

CDR は Voting 前に次を freeze する。

| Field | 内容 |
| --- | --- |
| `basis` | OA Article / prior CDR / statutory duty |
| `affirmative_required` | 必要な FOR vote 数 |
| `denominator` | vote 判定に用いる admitted Members の数 |
| `quorum` | OA 上の quorum と計算方法 |
| `vacancy_effect` | vacancy 時の denominator、凍結対象、replacement 条件 |
| `recusal_effect` | recusal が affirmative / denominator / fallback に与える影響 |
| `notice_period` | discussion / objection / voting の開始・終了 |

Member roster や OA が変わった場合、Voting 前なら snapshot を更新する。Voting 開始後なら vote を停止し、package と approval rule を更新して全 vote を取り直す。

- record owner は、起案者から独立して Class、conflict、approval rule、適用法上の execution condition を確認する。
- CD-P は、Company Governance Approval を記録した場合も、対応する JIP / Approved status / execution evidence が存在するまで Company 側 off-chain act を実施しない。
- material objection が未解消のまま Execution Actor が署名・支払・filing・notice を進めない。
- Company Governance Approval は OA で許容される方式に従い、CDR ID、Class、決議本文、承認 Member と capacity、recusal / conflict、effective date、Execution Actor を含める。
- Claim Commitment の CDR は、OA Article XIII.2 に従い、対象 Protocol Claim と予定 beneficiary / counterparty、commitment の性質と aggregate 上限額、許容される支払原資、適用が見込まれる保険、関連 conduct / authorization、利用可能な defense、予想費用、および非営利目的・solvency・非保証・Protocol Treasury / user assets 不使用に関する determination を approval package と決議本文に含める。

### 3.2 CD-3 Prohibited Actions

CD-3 単独では次を実施しない。

- Member admission / removal、vote / economic right の変更。
- 新規裁量支出、related-party payment、契約締結・終了、Claim Commitment、settlement、indemnity / advancement。
- redomicile、migration、dissolution、OA の実質改定。
- protocol action、Protocol Treasury 移動、user / protocol asset への影響。
- Foundation Operating Multisig Wallet threshold の緩和または signer の恣意的追加。

### 3.3 Execution Conditions

Execution Actor は、次を満たした場合だけ執行する。

- CDR に Company Governance Approval が記録されている。
- conflict / recusal / quorum、allowed action、適用法上の execution condition が記録されている。
- 支払は Foundation operating assets からの支払であり、Protocol Treasury またはユーザー資産を自動的に使わない。
- 契約は相手方・金額・成果物・終了条項・indemnity・tax treatment が承認本文と一致する。Claim Commitment を定める契約は、OA Article XIII に従う上限額、許容される支払原資および limited recourse を明記する。
- CD-P は JIP Approved、notice / exit window、Safe tx evidence、post-state readback requirements を参照している。

執行後、record owner は 5 business days 以内に signed agreement / filing receipt / payment receipt / notice / response を保存し、public summary と private evidence を分けて close する。

### 3.4 Closing Support and External Advice

OA の締結・発効および個別 CDR について外部助言を取得するか否かは、適用法、事案の性質、金額、利益相反、税務・規制・保険への影響および未解決事項を踏まえて判断する。外部助言の取得・完了自体は独立した approval / effectiveness / execution gate とせず、取得した場合は通常の supporting evidence として扱う。

Day-1 の formation closing record は、少なくとも次の状態を記録する。

- 適用法上必要な filing・consent・approval その他の実体条件、および OA・executed Exhibit・written designation の未記入値。
- RMI counsel、Registered Agentその他の外部助言・実務支援を取得した場合は、`obtained / not obtained / not applicable`、scope、結論・条件およびrestricted evidence ref。日本法務・税務は社内分析の適用箇所、前提事実、controlsおよび再判定の要否を記録する。
- CFC、PE、transfer pricing、donation、源泉徴収その他 material な税務論点の取扱い。
- Member・holder・signer independence、KYC / KYB / BOIR、Restricted Person screening および control-domain evidence の完了状態。
- 未解決事項、その owner、期限、および署名・発効・執行を妨げる適用法上の条件か否か。

将来の governance mechanism / governance-token issuance、related-party transaction、Claim Commitment / settlement / indemnity / advancement その他の高影響案件でも、外部助言を取得した場合は同じ方法で status と evidence ref を CDR に記録する。外部助言は Member vote、threshold、denominator、quorum または recusal の代替・治癒としない。

---

## 4. Repository and Record Structure

GitHub の設定、directory、labels、branch rules、package hash、backup は [`Foundation-Governance-GitHub-Operations.md`](./Foundation-Governance-GitHub-Operations.md) を正本とする。

### 4.1 Foundation Repository

```text
decisions/YYYY/CDR-YYYY-NNN.md
ministerial/YYYY-MM.md
register/cdr-index.md
register/member-account-mapping.md
register/access-review.md
exports/YYYY-MM/<export-manifest>.md
```

`register/member-account-mapping.md` は private でも個人情報・private key を置かず、Member identifier、designated GitHub account、designated voting wallet ref、effective period、status だけを持つ。raw KYC / holder evidence は restricted corporate records に置く。

### 4.2 Artifact Mapping

Foundation operating-asset Safe は mainnet evidence package で checksum address と OA evidence ref / digest を照合する。Member identifier は executed Exhibit A を正本とする。これとは別に指定する Foundation Operating Multisig Wallet の public identifier、signer identifier および threshold は、Initial Member consent / written designation、signer acceptance および implementation record を一体として正本とする。両者の候補は重複できるが、どちらの指定も他方の役割を生じさせない。適用法が要求する会社側 smart-contract identifier は、Certificate of Formation・annual filing その他必要な filing を正本とし、実装・検証記録と照合する。holder identity・contact・KYC/KYB/BOIR・signed independence evidence・control-domain disclosure・operational change history は、access-controlled な Company records に保持する。その分類・項目・形式・保存先は、適用法および社内実務に従って決定する。protocol signer の raw list / threshold は Protocol Governance / launch evidence 側に分離する。

| GitHub artifact | Foundation operation |
| --- | --- |
| Issue | CDR intake、採番、owner、due date、Class 候補 |
| Private Discussion | Member 討議、質問、異議。confidential annex は `evidence_ref` のみ |
| Proposal PR | Decision Package の review、package freeze、Member vote |
| Record PR | execution / receipt / close の追記。Decision Package は変更不可 |
| Monthly log PR | CD-0 の月次一括記録・close |

Issue close、PR approval、merge だけでは OA 上の Member approval にならない。§6 の valid vote が threshold を満たすことが必要である。

---

## 5. CDR Status and Lifecycle

### 5.1 Status Values

`Open` / `Draft` / `Review` / `Voting` / `Approved` / `Executing` / `Executed` / `Closed` / `Rejected` / `Expired` / `Cancelled` / `Superseded` / `Emergency-Open` / `Logged`

### 5.2 Operating Steps

| Step | Status | Owner | Required action / exit criterion |
| --- | --- | --- | --- |
| 1. Intake | — | Proposer / record owner | Issue を作り、重複確認、`CDR-YYYY-NNN` 採番、Class 候補と owner を割当 |
| 2. Draft | Draft | Proposer | CDR template を作り、Decision Text、authority、Execution Actor、asset boundary、conflict、applicable execution condition、evidence ref を記載 |
| 3. Triage | Draft → Review | Record owner | Class と `approval_rule`、秘密情報除外、notice / expiry、適用法上の execution condition を確認 |
| 4. Review | Review | Members | Discussion で全 material objection に応答し、Decision Package の内容と裏付記録を確認 |
| 5. Freeze | Review → Voting | Record owner | Decision Package を freeze し `package_sha256` を確定。voting window と roster snapshot を告知 |
| 6. Vote | Voting | Members | 同一 hash へ記名・理由付き vote。conflict / recusal を記録 |
| 7. Approval gate | Voting → Approved | Record owner | threshold、quorum、recusal、未解消 objection、expiry を検証。結果を approval register に収載 |
| 8. Record | Approved | Repository custodian / record owner | 承認済み proposal PR を `main` へ merge、evidence export。merge は ministerial |
| 9. Execute | Approved → Executing → Executed | Execution Actor | §7 checklist を通し、approved allowed action だけを実行。receipt / tx / response を保存 |
| 10. Close | Executed → Closed | Record owner | 5 business days 以内に record PR、evidence index、follow-up、export manifest を完了 |

### 5.3 Stop / Reset Conditions

- Decision Package を変更した場合、既存 vote をすべて stale とし Review または Voting をやり直す。
- Class / approval rule に合理的疑義がある場合、軽い方で進めず重い rule を適用し、疑義と採用根拠を decision record に記録する。
- material objection、conflict、evidence gap、適用法上の execution condition が未解消なら Voting / Execution を開始しない。
- Approved 後に allowed action、counterparty、金額、期限、重要条項を変える場合は新 CDR で supersede する。
- Voting close までに threshold を満たさない場合は `Expired`。期限延長は package 変更として vote を取り直す。
- Rejected / Cancelled / Expired record は削除しない。理由と後続 ID を残す。

---

## 6. Member Vote and Approval Gate

### 6.1 Valid Vote

valid vote は次をすべて満たす。

1. current Member register にある Member が Member capacity で行う。
2. `CDR ID` と `package_sha256` が Voting 中の package と一致する。
3. `FOR / AGAINST / ABSTAIN / RECUSED`、reason、conflict、timestamp、consent evidence ref を含む。
4. OA が許容する meeting、written / electronic consent、email、designated wallet signature 等の方式である。
5. voting window 内で、撤回・supersede されていない。

private GitHub Review は electronic consent の記録手段として使用できるが、designated account mapping と OA の許容方式を満たすことを前提とする。cryptographic signature が必要な事案は、private comment に秘密を貼らず signature evidence ref を記録する。

標準 vote record は [`CDR-Template.md`](../templates/governance/CDR-Template.md) を使う。

### 6.2 Counting

- `FOR` だけを affirmative に数える。
- `AGAINST` は threshold に算入せず、reason への応答と objection status を記録する。
- `ABSTAIN` / `RECUSED` は affirmative に数えない。
- recusal / vacancy / no-response の denominator と fallback は有効な OA に従う。record owner が独自に denominator を減らさない。
- GitHub の required reviews や CODEOWNERS は補助 gate であり、Member threshold の代替ではない。
- CI と record owner の集計が食い違う場合は Approved にせず、Member register・hash・capacity・OA basis を再確認する。

### 6.3 Approval Result

record owner は次を CDR の marker 外に記録する。

- affirmative / against / abstain / recused / no-response の件数。
- threshold、denominator、quorum の充足結果。
- conflict / material objection の結果。
- Approved / Rejected / Expired の決定時刻。
- 各 vote の stable URL または restricted evidence ref。

---

## 7. Execution and Signer Checklist

Foundation Operating Multisig Wallet signer または Authorized Agent は、実行前に全項目を確認する。

1. CDR が default branch 上で `Approved` であり、`package_sha256` が approval record と一致する。
2. threshold、quorum、recusal、effective date、expiry および適用法上の execution condition を満たす。
3. 自身が `execution.actor` として指定され、実行内容が `allowed_action` の範囲内である。
4. contract / payment / filing の相手方、金額、asset、期限、重要条項が Decision Package と一致する。
5. 支払元は Foundation operating assets であり、Protocol Treasury、user / protocol asset、Member / holder 自己資産と混同しない。
6. Restricted Person、KYC / KYB / BOIR、Good Standing、tax / accounting の precondition を満たす。
7. CD-P は対応 JIP の ID、Approved / Executed status、必要な protocol evidence を満たす。
8. tx / agreement / filing の独立照合者が proposer または作成者と別である。

不一致時の署名拒否は義務であり、48h 以内に CDR へ理由を記録する。Execution Actor は package を都合よく解釈して scope を拡張しない。

---

## 8. Class-Specific Procedures

### 8.1 CD-0 Monthly Ministerial Log

- [`CD-0-Ministerial-Log-Template.md`](../templates/governance/CD-0-Ministerial-Log-Template.md) で月次記録する。
- 各 entry は `mandate_ref`、actor / capacity、evidence ref、`new_discretion=no` を持つ。
- 新規 counterparty、金額・scope の裁量、関連当事者、asset boundary、権限変更があれば CD-1 / CD-2 / CD-P へ escalate する。
- 翌月 5 business days 以内に record owner が log を close し、missing evidence と次月 deadline を確認する。

### 8.2 CD-3 Urgent Compliance

1. 発動者は法定期限・Good Standing・Restricted Person 等の trigger と、遅延による具体的害を記録する。
2. 保存的・可逆的で既存義務の範囲内の措置だけを行う。
3. 可能な限り実行前、遅くとも 72h 以内に全 Member へ private notice を送る。
4. 7 日以内に CDR を `Emergency-Open` から Review へ移し、正当性、継続、解除、追加 action を review する。
5. 新規裁量行為は CD-1 / CD-2 として別承認する。CD-3 の事後 review を追認として使わない。

### 8.3 CD-P Protocol-Linked Company Action

CD-P は Company 側 off-chain act に対する Company Governance Approval であり、JIP の target / selector / args / tx bundle を承認、再承認または再定義しない。

Execution 前に次をすべて満たす。

1. 対応する JIP ID、Class、`package_sha256`、status=Approved を確認する。
2. JIP 上の notice / exit window、Safe tx / calldata hash、simulation、independent review、必要な execution / readback を確認する。
3. CDR 自身が Company 側 action を OA の threshold で Approved にしている。
4. Company 側の相手方、契約・notice / filing 文面、Execution Actor、Foundation operating assets effect を CDR が確定している。
5. JIP と CDR が矛盾しない。JIP 未承認、失効、cancel、内容不一致なら CDR を実行しない。

Protocol tx の execution は Protocol Signer、Company-side execution は Foundation Operating Multisig Wallet / Authorized Agent が行う。同一人が両 capacity を兼ねることは妨げない。ただし、各行為について capacity、wallet-address / signing-credential reference、record、署名・執行理由および authority source を完全に分離する。Protocol action の authority source は Protocol Governance、Company-side action の authority source は OA その他の既存 mandate および該当する Company Governance Approval として明示し、該当する JIP / CDR / execution record をその証拠として記録する。一方の capacity における行為または権限を他方へ帰属させず、private key その他の secret 自体は記録しない。

JIP が Approved でない場合、必要な Protocol Governance records / execution evidence が存在しない場合、または JIP と CDR が矛盾する場合、CD-P は執行しない。

### 8.4 Related-Party / Conflict

関連当事者取引は CD-2 とし、次を Decision Package に追加する。

| 項目 | 記録すること |
| --- | --- |
| Related party scope | DFKK / founder-affiliated entity、Member、nominee member、Foundation Operating Multisig Wallet の署名者、Protocol Signer、Representative Agent contact、service provider、その関連会社。 |
| Transaction basis | 契約目的、Foundation purpose との整合、成果物、期間、終了条項、金額・価格決定根拠。 |
| Protections | no private inurement、applicable tax treatment、conflict disclosure、recusal、non-conflicted approval。 |

直接の counterparty または affiliate に該当する Member は recuse する。recusal により threshold を満たせない場合、record owner は threshold を下げず OA の fallback を適用し、なお満たせないときは status quo を維持する。外部助言を取得した場合は通常の supporting evidence として扱い、recusal、賛成投票または threshold の代替としない。

---

## 9. Evidence, Retention, and Disclosure

### 9.1 Storage Classes

| 区分 | 保存対象 | Access / disclosure |
| --- | --- | --- |
| Private governance record | CDR、Member vote、Discussion / PR、Class、approval result、execution index | repository の authorized users のみ |
| Restricted evidence | BOIR、passport、住所、UBO、raw legal / tax memo、契約原本、bank / filing receipt、signer security | need-to-know。private GitHub に置かない |
| Public minimum | registry、法定連絡先、必要な smart-contract identifier、public blockchain tx | 法令・registry・blockchain に従う |
| Optional disclosure | counterparty copy、監査用抜粋、Member-approved summary | purpose と recipient を CDR / disclosure log に記録 |

`records.public_disclosure` の default は `not_required` とする。開示するときは scope、recipient、legal / contractual basis、redaction、実施者、日付を記録する。

### 9.2 Retention and Export

- CDR、vote、meeting / Discussion、execution、会計記録を OA / applicable law の期間保持する。Day-1 OA baseline は解散後も最低5年。
- GitHub を唯一の archive にせず、月次 export と四半期 restore test を実施する。
- export manifest に repository head SHA、Issue / PR / Discussion / review 件数、archive digest、restricted保存先を記録する。
- Member / counsel / service provider の追加・削除時に access review と offboarding evidence を作る。
- GitHub account deletion、organization ownership change、service outage でも CDR と vote を再構成できるようにする。

---

## 10. Compliance Triggers

CDR は BOIR / KYC / KYB / Restricted Persons / Good Standing への影響を必ず記録する。詳細な設立前 Gate は RMI Requirements §7 を正本とする。

| Trigger | 既定 Class / action |
| --- | --- |
| Member の追加・削除・議決権比率変更 | CD-2 |
| Nominee member の選任・交代 | CD-2 |
| Representative Agent Form の変更 | CD-0 / CD-1 |
| Foundation Operating Multisig Wallet の署名者または構成の変更 | CD-2 |
| 会社が新たな substantial control person を持つ | CD-2 / CD-3 |
| Restricted Person 該当または合理的疑い | CD-3 で保存措置、CD-2 で replacement / termination |
| smart-contract identifier の Certificate / required filing 更新 | CD-1 / CD-2 / CD-P。実質変更と factual update を区別 |
| public disclosure request | CD-0（既存義務）/ CD-1（裁量開示）/ legal hold |

---

## 11. Go-Live Gate

実案件を開始する前に、共通 runbook §10 に加えて次を満たす。

1. 有効な OA が `approval_rule`、notice、quorum、recusal、Official Online Venue と private Company Governance Workspace の関係を確定している。
2. `jpydf-foundation-governance` が Private で、Member / record owner / custodian / counsel の access が最小化されている。
3. CDR template、CD-0 log、Issue Form、Discussion、PR template、CI、branch rules、backup が有効である。
4. Member account / designated voting method mapping が全 Member について検証済みである。
5. dummy CDR で 3-of-5、4-of-5、recusal、CD-3、CD-P、package change vote reset、export / restore を通している。
6. private GitHub と public minimum surface の分離が、OA および適用法と整合する形で記録されている。
7. §3.4 の formation closing record が作成され、適用法上の未充足条件と、それ以外の外部助言・運用上の未解決事項が区別されている。

Repository 作成、collaborator 招待、visibility / ruleset 設定は本書の編集だけでは実施しない。外部状態変更は別途明示承認を得る。

---

## 12. Templates and Sources

### 12.1 Templates

- [`CDR-Template.md`](../templates/governance/CDR-Template.md)
- [`CD-0-Ministerial-Log-Template.md`](../templates/governance/CD-0-Ministerial-Log-Template.md)
- [`CDR-Intake-Issue-Form.yml`](../templates/governance/CDR-Intake-Issue-Form.yml)
- [`CDR-Pull-Request-Template.md`](../templates/governance/CDR-Pull-Request-Template.md)
- [`Foundation-Governance-GitHub-Operations.md`](./Foundation-Governance-GitHub-Operations.md)

### 12.2 Internal Sources

- [`Foundation-Entity-Setup-Requirements.md`](../requirements/Foundation-Entity-Setup-Requirements.md)
- [`Foundation-Entity-RMI-DAO-LLC-Requirements.md`](../requirements/Foundation-Entity-RMI-DAO-LLC-Requirements.md)
- [`Foundation-Entity-Operating-Agreement-Requirements.md`](../requirements/Foundation-Entity-Operating-Agreement-Requirements.md)
- [`Foundation-Entity-Member-Signer-Requirements.md`](../requirements/Foundation-Entity-Member-Signer-Requirements.md)
- [`Day-1-Governance-Proposal-Execution-Policy.md`](../../protocol/launch/gates/Day-1-Governance-Proposal-Execution-Policy.md)
- [`Foundation-Operating-Asset-Holder-Manifest.md`](../manifests/Foundation-Operating-Asset-Holder-Manifest.md)
- [`Mainnet-Safe-Role-Assignment-Gate.md`](../../protocol/launch/gates/Mainnet-Safe-Role-Assignment-Gate.md)

### 12.3 External Primary Sources

- [RMI Decentralized Autonomous Organization Act 2022, as amended](https://rmiparliament.org/cms/images/LEGISLATION/PRINCIPAL/2022/2022-0050/2022-0050_2.pdf)
- [RMI DAO Regulations 2024](https://rmiparliament.org/cms/images/LEGISLATION/SUBORDINATE/2024/2024-0001/2024-0001_1.pdf)
