# Foundation RMI DAO LLC Requirements

> **本書の役割**: Foundation を Republic of the Marshall Islands（RMI）の Non-Profit DAO LLC として MIDAO 経由で設立するための固有要件を定める。Foundation の法域中立な絶対要件は [`Foundation-Entity-Setup-Requirements.md`](./Foundation-Entity-Setup-Requirements.md) を正本とする。
>
> **用語**: MIDAO Directory Services Inc. は現在の法定 `Registered Agent` 兼 onboarding provider である。本書では具体的な portal・template・review 手順を指す場合に `MIDAO`、法的な役割・権限・義務を指す場合に `Registered Agent` を用いる。`Representative Agent` と `Registrar` は別の役割である。
>
> **本公開文書に記載しないもの**: 個人情報、KYC link、passport / address proof、raw signer list、private key、seed phrase、署名・提出用 OA package の非公開情報、見積金額の確定値。契約上の効力が必要な Foundation Member identifier は executed Exhibit A、Foundation Operating Multisig Wallet signer identifier / threshold は written designation・signer acceptance・implementation record に記載する。適用法が要求する会社側 smart-contract identifier は Certificate of Formation・annual filing その他必要な filing に記載する。

---

## 1. 設立モデル

Day-1 の設立モデルは次を基準線とする。

| 項目 | 要件 |
| --- | --- |
| 法人格 | 新規設立の RMI Non-Profit DAO LLC |
| 設立経路 | MIDAO onboarding portal / MIDAO Directory Services |
| Foundation entity management | member-managed only。Managing Member / Manager は置かない |
| Member | 5 entity。各 Member は同等 role、20% Foundation Member voting right |
| Nominee member | 5 Member とは別枠。Day-1 の provider 候補は MINS。Membership Interest、議決権、経済権、Foundation Operating Multisig Wallet の signer slot を持たず、登録・compliance filing 等の限定的な会社側事務を担う |
| Foundation Operating Multisig Wallet | Foundation affairs 専用。signer set は Member set と別に承認・記録し、両者は重複できるが一致を要しない |
| Protocol roles | OA / Exhibit A の対象外。Protocol Admin Multisig、Guardian、Treasury、PIL recipient、A-E signer address、protocol threshold を載せない |
| Protocol 用 governance token | Day-1 の前提にしない。将来採用する場合は別 gate / OA amendment で扱う |

---

## 2. 必須要件

| ID | 要件 |
| --- | --- |
| RMI-ORG-1 | Non-Profit DAO LLC として設立し、no private inurement、経済権なし、残余財産の非営利移転を OA に入れる。 |
| RMI-ORG-2 | Foundation は JPYdf の issuer / custodian / protocol operator ではないことを OA の目的・制限条項に入れる。 |
| RMI-MEM-1 | Day-1 Member は 5 entity、各 20%。25% 以上の Foundation Member voting right、経済権、managerial control を持つ Member を置かない。 |
| RMI-MEM-2 | Managing Member / Manager を置かない。適用法、Registered Agent または RMI counsel が事務 role を求める場合だけ、authorized agent / nominee / service provider として限定的に扱う。 |
| RMI-MINS-1 | MINS は 5 Member とは別枠の nominee member provider 候補とする。nominee member は Membership Interest、Foundation Member voting right、経済権および Foundation Operating Multisig Wallet の signer slot を持たない。 |
| RMI-MINS-2 | Nominee member の権限は、OA Article V.4 に従い nominee member を明示的に授権する Company Governance Approval の範囲で行う登録・formation・dissolution・BOIR・annual filing・Representative Agent 対応その他適用法上必要な会社側事務に限定し、management right、veto、appointment right または protocol key を生じさせない。 |
| RMI-OPS-1 | Foundation Operating Multisig Wallet は Foundation affairs 専用。protocol parameter、contract owner、Timelock、Guardian、Treasury、PIL recipient を承認・実行しない。 |
| RMI-OPS-2 | Foundation Operating Multisig Wallet の signer set は Company Governance を通じて Member set とは別に承認し、各 signer を独立した control domain とする。Member と signer は重複できるが、いずれの role も他方を生じさせない。正確な public identifier、signer 数、signer identifier および threshold は OA が授権する Initial Member consent / written designation、signer acceptance および implementation record で確定する。 |
| RMI-CMP-1 | BOIR / KYC / KYB 対象者を OA / Exhibit A / CF signer / filer / Category A/B/C 分類と合わせて確定する。 |
| RMI-CMP-2 | MINS が法人 nominee member provider になる場合、MINS KYB と Registered Agent または適用法が求める ultimate natural-person UBO / controller KYC、および BOIR 上の nominee / authorized representative 分類を処理する。 |
| RMI-CMP-3 | 5 Member は、各20%・Manager不設置・actual controlなしを前提に、membershipのみでBOIR full KYC対象にしない分類をOA、holder factsおよびMIDAO提出様式と一致させる。 |
| RMI-REC-1 | Member identifier は executed Exhibit A に置く。Foundation Operating Multisig Wallet の public identifier・signer identifier / threshold は、OA が授権する Initial Member consent / written designation、signer acceptance および implementation record に置く。適用法が要求する会社側 smart-contract identifier は Certificate of Formation・annual filing その他必要な filing に記載し、実装・検証記録と一致させる。holder本人情報・連絡先、KYC/KYB/BOIR、signed independence evidence、control-domain disclosure、変更証跡、annual filing は access-controlled な Company records で管理し、公開 repo に置かない。そのrecordsの分類・項目・形式・保存先・更新手続は、適用法および社内実務に従い柔軟に決定する。 |
| RMI-TAX-1 | [`Foundation-Entity-Japan-Legal-Tax-Analysis.md`](../evidence/Foundation-Entity-Japan-Legal-Tax-Analysis.md) の社内判断とcontrolsを適用する。DFKKは独立した越境service providerとし、Foundationの意思決定・契約締結・資産管理を日本国外で行い、日本にoffice・representative・契約権限者を置かない。 |

---

## 3. 必須提出物

MIDAO onboarding で DF が準備する書類は次に限定して管理する。各テンプレートは [`foundation/templates/midao/`](../templates/midao/) に置く。

| 書類 / 手続 | 要件 |
| --- | --- |
| Operating Agreement | 本書 §4 の内容を反映する。MIDAO template の Managing Member 条項は、不要なら削除または未採用にできるか確認する。 |
| Certificate of Formation | Non-Profit DAO LLC 用テンプレートを使う。CF signer / filer は BOIR / KYC 対象になり得るため、事前に分類する。 |
| BOIR | Category A/B/C、nominee member / authorized representative、CF signer / filer を確定して記載する。 |
| KYC / KYB | BOIR 記載者全員。法人が対象なら法人 KYB と UBO 自然人 KYC。 |
| FIBL | OA business purpose と一致させる。制度趣旨・要否根拠は MIDAO に確認する。 |
| Representative Agent Form | Registered Agent に連絡先を提供し、同 Agent から転送される correspondence / service of process を受領する者を指定する。Nominee member provider が兼ねる場合も、Membership Interest・議決権・Manager role・protocol signer role を生じさせず、各 capacity を区別する。KYC 要否は Registered Agent の現行要件に従う。 |

---

## 4. OA に最低限入れる事項

OA は詳細な法務文書だが、要件定義としては次を満たせばよい。

1. RMI Non-Profit DAO LLC としての組成、名称、Registered Agent、Principal Office、term。
2. JPY DeFi ecosystem の steward 目的。issuer / custodian / protocol operator ではない旨。
3. no private inurement、経済権なし、合理的対価・費用償還だけを許容すること。
4. 5 Member、各 20%、Manager 不設置、Member replacement / voting / quorum、および 5 Member と別枠の nominee member。
5. Foundation Operating Multisig Wallet の scope、threshold、replacement、lost key / compromise / rotation。
6. Protocol Admin Multisig / Guardian / Treasury / PIL recipient と Foundation Operating Multisig Wallet の分離。
7. Foundation operating assets と Protocol Treasury の分離。
8. DFKK / related party payment は service / grant agreement、conflict approval、arm's-length terms、取引別の会計・税務controlsに基づくこと。
9. BOIR / KYC / KYB / annual filing / restricted persons / sanctions screening。
10. Member、MINS、operating signer、authorized agent、service provider の liability / indemnity と carve-out。
11. 解散時の残余財産は同一または類似目的の非営利・慈善団体へ移転し、DFKK / founder / Member / service provider へ分配しない。
12. OA amendment は DFKK 単独、founder 単独、authorized agent 単独でできない。core protections は重くする。
13. private な会社ガバナンス記録、electronic consent、CDR、access / retention と、Official Online Venue / public blockchain transparency の分離。repository、export、backup の実装は OA に固定せず、社内運用で管理する。

---

## 5. Member と Operating Multisig Signer

Day-1 Member の作業仮説は次の5 slotsとする。M1–M5 addressはOAの英語正本・日本語参照訳・DOCXへ反映済みである。holder名その他の非公開情報は、受諾、独立性、KYB/KYC、sanctions screeningが完了するまで確定扱いにしない。

| Slot | Day-1 の扱い | 主な確認事項 |
| --- | --- | --- |
| M1 | 独立 Member 候補（TBD） | 受諾、sanctions screening、独立性、control domain |
| M2 | DFKK または独立 ecosystem participant | DFKK を入れる場合は最大1 slot、related-party approval、社内分析のtransaction controls、非支配性 |
| M3 | Fracton 等の独立 ecosystem participant | 受諾、sanctions screening、利益相反、独立性 |
| M4 | Allied 等の独立 ecosystem participant | 受諾、sanctions screening、availability、responsibility |
| M5 | Tokyo Dome EnCross / investor / partner 等 | 受諾、sanctions screening、DFKK との関係、control domain |

MINS は上記 5 slots に含めず、別枠の nominee member provider 候補として、KYB、必要自然人 KYC、BOIR 上の分類、年次更新および限定的な filing 権限を確認する。

Foundation Operating Multisig Wallet の signer 候補は、上記 Member slots とは別に評価・承認する。同じ entity が両 role を兼ねることはできるが、Member であることだけで signer とはならず、signer であることだけで Membership または議決権を得ない。

候補には [`Foundation-Entity-Operating-Multisig-Member-Request-Package.md`](../runbooks/Foundation-Entity-Operating-Multisig-Member-Request-Package.md) を private channel 用に使う。公開 repo には候補の回答、個人情報、raw signer list、KYC link を転記しない。

---

## 6. No-Go

- Foundation Operating Multisig Wallet を Protocol Admin Multisig / Guardian / Treasury / PIL recipient と同一視する。
- Protocol Safe address、A-E signer address、protocol threshold を OA / Exhibit A の Member address として載せる。
- Managing Member / Manager を Day-1 の標準構成にする。
- Nominee member に Membership Interest、Foundation Member voting right、経済権、management right、veto、appointment right、protocol key または Foundation Operating Multisig Wallet 署名者 slot を与える。
- 5 Member のいずれかに 25% 以上の Foundation Member voting right、経済権、残余財産請求権、所有者分配を与える。
- DFKK その他の単一 entity に、同じ role 内で複数の Member address または複数の Foundation Operating Multisig Wallet signer slot を与える。
- Representative Agent を Member / Manager / operating signer / protocol signer と混同する。
- 全5 holderの受諾、MINS KYB/KYC、5 Memberのsanctions screening、署名・提出欄が未完了のままOA / CF / BOIRをexecuted / filed扱いにする。

---

## 7. 確認 Gate

本節を Foundation 設立前 Gate の正本とする。Foundation の法域中立な core requirements は [`Foundation-Entity-Setup-Requirements.md`](./Foundation-Entity-Setup-Requirements.md) が持ち、本節ではそれを OA / CF / BOIR / MIDAO提出・候補受諾・社内法務税務分析・transaction controlsに落とす。

| Gate | 状態 | 確認事項 | 残る実行 |
| --- | --- | --- | --- |
| G-RMI-0: Core requirements consistency | Complete | issuer / custodian / protocol operator / protocol signerの否定、asset separation、no private inurement / non-controlをOAに反映済み | closing parity check |
| G-RMI-1: RMI legal design | Complete | 5 Member / 各20% / Manager不設置 / 別枠nominee member / Memberとoperating signerの分離 / Protocol address非掲載を外部counsel review反映済み。M1–M5 addressを3形式へ反映し、#1400版OA DOCXを提出済み | holder acceptance・署名と残るMIDAO packageの完了 |
| G-RMI-2: Candidate acceptance | Open | Member候補とoperating signer候補を別roleとして評価し、受諾、独立性、sanctions screening、KYB/KYC、annual filing協力を確認 | Member list / operating signer list / acceptance |
| G-RMI-3: Nominee package | Open | MINS KYB、必要自然人KYC、nominee / authorized representativeの実データ、限定権限、年次更新 | BOIR / KYC / KYB package |
| G-RMI-4: Japan tax / legal | Analysis complete | DFKKを独立した越境service providerとし、日本にoffice・representative・契約権限者を置かない前提では、外国会社登記・日本PEは不要。CFC / 移転価格 / 寄附金 / 外国法人該当性 / 消費税も社内分析済み | 非日本拠点・無代理の境界維持と取引別controlsの実行 |
| G-RMI-5: OA counsel review | Complete | OA本文、indemnity、dissolution、amendment、records等の外部counsel reviewを反映し、legal wordingを固定済み | holder署名と必要な追加・最終提出 |
| G-RMI-6: Governance process / disclosure | Design complete / implementation open | private Company Governance、Official Online Venue、public minimum surface、records / inspection / retentionを分離 | repository、export / backup、access controlsのgo-live |

---

## 8. 補助文書

- OA conformance checklist: [`Foundation-Entity-Operating-Agreement-Requirements.md`](./Foundation-Entity-Operating-Agreement-Requirements.md)
- OA precedent notes: [`Foundation-Entity-OA-Precedent-Wording.md`](../evidence/Foundation-Entity-OA-Precedent-Wording.md)
- Candidate requirements: [`Foundation-Entity-Member-Signer-Requirements.md`](./Foundation-Entity-Member-Signer-Requirements.md)
- Candidate request package: [`Foundation-Entity-Operating-Multisig-Member-Request-Package.md`](../runbooks/Foundation-Entity-Operating-Multisig-Member-Request-Package.md)
- MIDAO onboarding procedure: [`Foundation-MIDAO-Onboarding-Guide.md`](../runbooks/Foundation-MIDAO-Onboarding-Guide.md)
- Japan legal / tax analysis: [`Foundation-Entity-Japan-Legal-Tax-Analysis.md`](../evidence/Foundation-Entity-Japan-Legal-Tax-Analysis.md)
