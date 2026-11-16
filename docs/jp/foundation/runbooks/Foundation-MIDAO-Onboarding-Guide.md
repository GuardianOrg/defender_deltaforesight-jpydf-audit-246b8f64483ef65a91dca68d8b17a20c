# MIDAO Onboarding Guide

> **本書の役割**: MIDAO onboarding portal で提出する書類、作業順、継続義務を管理する手順書。RMI DAO LLC の設立要件・確認 Gate は [`Foundation-Entity-RMI-DAO-LLC-Requirements.md`](../requirements/Foundation-Entity-RMI-DAO-LLC-Requirements.md) を正本とする。
>
> 記入済み書類、BOIR 個人情報、KYC link、passport / address proof、raw signer list は public repo に置かない。
>
> **用語**: MIDAO Directory Services Inc. は現行制度上の Registered Agent 兼 onboarding provider である。本書では portal、template、review 等の具体的サービスを `MIDAO`、法令上の役割を `Registered Agent` と記載し、Representative Agent および Registrar とは区別する。

---

## 1. 取得済テンプレート

空白テンプレートは [`foundation/templates/midao/`](../templates/midao/) に保存済み。英語原本が正本で、`.ja.md` は読解補助である。

| ファイル | 用途 |
| --- | --- |
| `Operating_Agreement_Template_Non-Profit_and_For-Profit.docx` | OA |
| `Certificate_of_Formation_Non-Profit_DAO_LLC.docx` | Certificate of Formation |
| `Beneficial_Owner_Information_Report_BOIR.pdf` | BOIR |
| `Foreign_Investment_Business_License_FIBL_Application.pdf` | FIBL |
| `Representative_Agent_Form.pdf` | Representative Agent |

---

## 2. Submission Flow

| 順序 | 提出物 / 手続 | DF の作業 |
| --- | --- | --- |
| 1 | OA | Counsel-reviewed execution formへM1–M5 addressを反映し、#1400版DOCXを提出済み。全holderのacceptance / KYC / KYB・署名と、必要な追加・最終提出を完了する。 |
| 2 | Certificate of Formation | CF signer / filer の BOIR / KYC 区分を確認して記入する。 |
| 3 | BOIR | Category A/B/C、nominee member / authorized representative、CF signer / filer を反映する。 |
| 4 | KYC / KYB | BOIR 記載者全員。法人が対象なら法人 KYB と UBO 自然人 KYC。 |
| 5 | FIBL | OA business purpose と一致させ、要否・制度趣旨を MIDAO に確認する。 |
| 6 | Representative Agent Form | Registered Agent へ連絡先を提供し、同 Agent から転送される correspondence / service of process 等を受領する担当を指定する。Nominee member provider が兼ねる場合も、Membership Interest・議決権・Manager role・protocol signer role を生じさせず、各 capacity を区別する。 |
| 7 | MIDAO review / submit | MIDAO commentを残る書類へ反映し、必要なOAの追加・最終提出とCF / BOIR / FIBLの提出を完了する。 |
| 8 | Charter / filed docs | 承認済み charter / filed docs を取得し、private corporate records に保管する。 |

---

## 3. Before Remaining / Final Submission

提出前に次を決める。未確定事項の判断基準は RMI Requirements §7 を参照する。

1. 正式名称、DBA の要否、Principal Office、Registered Agent。
2. 5 Member の final roster、これとは別に指定する Foundation Operating Multisig Wallet signer roster、既に固定したthresholdの記録、別枠nominee member provider、機密Company recordsのaccess-controlと保存方針。Memberとsignerの兼任は許容できるが、一方の指定から他方の役割を生じさせない。
3. 提出済みOA、repository copyおよび非公開execution packageの対応関係と、holder署名後の追加・最終提出要否。
4. CF signer / filer、Representative Agent、BOIR / KYC / KYB 対象者。
5. OA business purpose と FIBL section [6] の文言。
6. DFKKの初期費用負担、service / grant / reimbursementの分類と、独立した越境service provider / 無代理の契約境界。

---

## 4. 作業順

1. RMI Requirements §7 の Gate を確認する。
2. Counsel-reviewed OAを正本とし、holder acceptance、KYC/KYB、署名および提出後の追加対応をexecution checklistで完了する。
3. 候補確認は [`Foundation-Entity-Operating-Multisig-Member-Request-Package.md`](./Foundation-Entity-Operating-Multisig-Member-Request-Package.md) を使い private channel で回収する。
4. CF signer / filer、BOIR 対象者、KYC / KYB 対象者を確定する。
5. BOIR、KYC / KYB、FIBL、Representative Agent Form を並行で準備する。
6. MIDAO review commentを受け、RMI filing / format事項はRMI Requirements §7へ、Day-1事実の変更はJapan legal / tax analysisの再判定triggerへ戻す。

---

## 5. ボトルネック

| ボトルネック | 対応 |
| --- | --- |
| OA execution | Legal wording、M1–M5 address、英日・DOCX parityおよび#1400版DOCX提出は完了済み。全holderのacceptance・署名と追加・最終提出要否をexecution checklistで完了する。 |
| Candidate acceptance | 候補回答は private channel で回収し、public repo には要約だけを置く。 |
| KYC / KYB | BOIR 対象者と法人 UBO を早く確定し、SumSub link は非公開で送る。 |
| FIBL | OA business purpose と一致必須。OA 確定前に単独で確定しない。 |
| Japan-side controls | DFKKを独立した越境service providerとし、非日本拠点・無代理を維持する。service / reimbursement / grant / loan / IPを取引別に契約・記録する。 |

---

## 6. 継続義務

- BOIR、Representative Agent、annual filing は毎年更新対象。
- Member、operating signer、Representative Agent、BOIR 記載者に変更があれば、KYC / KYB と corporate records を更新する。
- RMI上の継続義務と、日本側の外国会社登記・PEの再判定triggerおよび取引別税務controlsは別々に記録・更新する。
- Public registry / good standing を定期確認する。
