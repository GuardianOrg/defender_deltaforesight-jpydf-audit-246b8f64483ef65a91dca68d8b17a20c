# Foundation Operating Agreement Conformance Checklist

> **本書の役割**: 外部 counsel review 反映済みの Operating Agreement（OA）が Foundation の core requirements と RMI 固有要件を満たすことを維持する conformance checklist。Foundation の core requirements は [`Foundation-Entity-Setup-Requirements.md`](./Foundation-Entity-Setup-Requirements.md)、RMI 固有要件は [`Foundation-Entity-RMI-DAO-LLC-Requirements.md`](./Foundation-Entity-RMI-DAO-LLC-Requirements.md) を正本とする。
>
> 本書は OA 条項の正本ではない。英語正本 [`Foundation-Entity-OA-Draft.md`](../spec/Foundation-Entity-OA-Draft.md) は契約文言を固定済みで、M1–M5 addressを英語正本・日本語参照訳・DOCXへ反映済みである。#1400版OA DOCXはMIDAO onboarding portalへ提出済みである。

---

## 1. Status と使い方

1. 外部 counsel review の反映内容は [`Foundation-Entity-OA-Counsel-Review.md`](../evidence/Foundation-Entity-OA-Counsel-Review.md) を evidence とする。
2. OA の実体条項を変更する場合は、Setup Requirements と RMI Requirements に再照合する。
3. holder acceptance、KYC/KYB、署名、残る提出、closingは [`Foundation-Entity-OA-Execution-Checklist.md`](../runbooks/Foundation-Entity-OA-Execution-Checklist.md) で管理する。
4. 日本法務・税務の社内判断は [`Foundation-Entity-Japan-Legal-Tax-Analysis.md`](../evidence/Foundation-Entity-Japan-Legal-Tax-Analysis.md) を正本とし、日本の外部 counsel / 税務専門家 review を OA の効力または設立完了の条件にしない。

---

## 2. OA が維持する領域

| Area | Conformance requirement |
| --- | --- |
| Organization | RMI Non-Profit DAO LLC、名称、Registered Agent、Principal Office、term、Certificate / OA / records の関係。 |
| Purpose / limitation | JPY DeFi ecosystem steward であり、issuer / custodian / protocol operator ではなく、Protocol Governance の鍵・role・authority を持たないこと。 |
| Governance separation | Company Governance と Protocol Governance を分離し、Company Governance Approval が Protocol 側の決定・承認・執行を構成または代替しないこと。 |
| Non-profit | no private inurement、経済権なし、reasonable compensation / reimbursement のみ許容、残余財産の非営利移転。 |
| Members / nominee | Day-1 の 5 Member / 各20% / member-managed / Manager 不設置。Nominee member は別枠で、Membership Interest・議決権・経済権・operating signer slot を持たない。 |
| Foundation Operating Multisig Wallet | Foundation affairs 専用の execution mechanism。Member / Exhibit A と別に signer set・threshold・rotation・lost-key対応を指定し、Member approvalを代替しない。 |
| Asset separation | Foundation Operating Assets、Protocol Treasury、user assets、IP / docs / domain を混同しないこと。 |
| Payments / conflicts | DFKK / related party payment は written service / grant agreement、conflict approval、arm's-length terms、取引別 evidence を条件にすること。 |
| Compliance / records | BOIR / KYC / KYB / annual filing / sanctions screening / restricted persons / corporate records。 |
| Liability / indemnity | 対象者、claim scope、carve-out、insurance、原資限定を定め、Protocol Treasury / user assets に及ばせないこと。 |
| Amendment / transition | DFKK・founder・MINS・authorized agent 単独改定を不可にし、future Protocol Governance は optional transition としてだけ扱うこと。 |

---

## 3. OA に入れない事項

- Protocol Safe address、A–E protocol signer address、protocol threshold を Member / Exhibit A / Foundation Operating Multisig Wallet address として載せる。
- Foundation が JPYdf の mint / redeem / borrow / liquidation / collateral movement を承認・実行するように読める文言。
- Foundation が Protocol Treasury を自己資産として自由処分できる文言。
- DFKK / founder / Member / service provider への所有者分配、残余財産請求権、保証取り分。
- Managing Member / Manager を Day-1 の標準構成にする文言。
- 将来の governance token / TGE / Protocol tokenholder governance を確定済みとして扱う文言。
- legal / tax / Registered Agent その他の外部 review を契約効力・承認・執行の独立条件とする文言。

---

## 4. OA 外に置く実行情報

| 置き場所 | 内容 |
| --- | --- |
| Certificate / required filings | 適用法が要求する Company smart-contract identifier、formation・annual filing 情報。 |
| Executed Exhibit A | M1–M5のMember addressは3形式へ反映済み。holder acceptance、署名権限、KYC/KYBおよび署名はexecution checklistで別に完了する。 |
| Written designation / implementation record | Foundation Operating Multisig Wallet の public identifier、signer set、threshold、signer acceptance、readback。 |
| Company non-public records | holder identity・連絡先、KYC / KYB / BOIR、independence evidence、control-domain disclosure、契約原本、取引・変更証跡。 |
| Protocol Governance / launch evidence | Protocol Admin Multisig、Guardian、Treasury、PIL recipient、A–E signer、protocol threshold、Safe transaction evidence。 |

---

## 5. 変更 Gate

外部 counsel review 反映済みのため、address・署名・提出だけでは OA の実体条項を再openしない。次の場合だけ、該当条項の再評価を行う。

1. RMI法またはRegistered Agentの必須要件が変わる。
2. Member / nominee / Manager / voting modelを変更する。
3. FoundationにProtocol role・Protocol asset・経済権を持たせる。
4. Foundation Operating Multisig WalletまたはCompany Governanceの権限構造を変える。
5. 日本にFoundationのoffice・representative・employee・契約権限者・事業場所を置くなど、[`Foundation-Entity-Japan-Legal-Tax-Analysis.md`](../evidence/Foundation-Entity-Japan-Legal-Tax-Analysis.md) の事実前提を変更する。
