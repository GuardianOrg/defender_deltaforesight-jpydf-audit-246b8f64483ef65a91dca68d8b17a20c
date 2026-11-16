# JPYdf Foundation Setup Requirements

> Support translation. The Japanese source document
> [`documents/jp/foundation/requirements/Foundation-Entity-Setup-Requirements.md`](../../../jp/foundation/requirements/Foundation-Entity-Setup-Requirements.md)
> is authoritative if this file conflicts with it. This translation is provided
> for reference and is not legal advice; rely on the Japanese source and on
> external counsel.

> **Role of this document**: sets out, in a form that can be shared with external
> counsel, the core requirements that must be satisfied when establishing the
> Foundation, regardless of jurisdiction. [`Foundation-Entity-RMI-DAO-LLC-Requirements.md`](../../../jp/foundation/requirements/Foundation-Entity-RMI-DAO-LLC-Requirements.md)
> is authoritative for the details of RMI DAO LLC / MIDAO / BOIR / OA / Member and
> candidate engagement.
>
> **Document relationships**: this document defines the jurisdiction-neutral
> upper-level requirements on the Foundation's purpose, permitted activities, and
> prohibitions; [`Foundation-Entity-OA-Draft.md`](../../../jp/foundation/spec/Foundation-Entity-OA-Draft.md)
> renders them as contractual provisions ([`Foundation-Entity-OA-Draft.ja.md`](../../../jp/foundation/spec/Foundation-Entity-OA-Draft.ja.md)
> is the Japanese reference translation). The OA must not extend the Foundation's
> authority as defined here, nor weaken the prohibitions.
>
> **Out of scope**: the detail of RMI law, draft OA provisions, engagement letters
> to candidates, MIDAO portal procedures, actual signer addresses / Safe addresses
> / thresholds, KYC links, and personal information.

---

## 1. Basic policy

DeltaForesight develops "JPY DeFi", an over-collateralised CDP protocol running
on Ethereum mainnet. JPYdf is a JPY-denominated stablecoin minted and burned by
the smart contracts of the JPY DeFi protocol. User transactions — borrow, repay,
opening / adjusting / closing a Trove, depositing to and withdrawing from the
Stability Pool, redemption, liquidation, and others — are initiated by users and
other protocol participants and executed by the JPY DeFi protocol's smart
contracts according to the code and rules in effect at that time. They do not
require Foundation approval.

The Foundation is a non-profit entity established as the long-term **steward** of
the JPY DeFi protocol and ecosystem and as an **administrative layer supporting
the protocol and its governance**. This role does not make the Foundation the
issuer of JPYdf, a counterparty or intermediary to user transactions, a custodian
of user assets, a protocol operator, a decision-maker or executor of Protocol
Governance, or the owner of the Protocol Treasury.

Company Governance, which decides on the Foundation's activities, and Protocol
Governance are separate lines of authority.

DeltaForesight K.K. (DFKK) is one contributor, performing software development,
a non-exclusive frontend, marketing, community support, and similar. It is not to
be the sole or de facto controller of the Foundation or the protocol.

---

## 2. Foundation purpose and permitted activities

The Foundation's purpose and permitted activities are limited to the following.

### 2.1 Stewardship of IP / domains / documentation

- Hold and manage intellectual property, trademarks, domains, and documentation
  relating to the JPY DeFi protocol and ecosystem.
- Support the continuity of the ecosystem through IP licensing and documentation
  management. This is not to be treated as owning, operating, or controlling the
  protocol or its implementation.

### 2.2 Contracts with contributors / service providers / grant recipients

- May enter into and administer contracts with contributors including DFKK,
  service providers, and grant recipients.

### 2.3 Off-chain acts incidental to Protocol Governance decisions

- Where a matter approved by Protocol Governance requires contracting, recording,
  confirmation, notification, filing, or another off-chain act, the Foundation
  may record, confirm, and perform that act.
- Such off-chain acts are subject to Company Governance Approval and may be
  performed only where both the underlying valid Protocol Governance decision /
  record and the necessary execution evidence are present. Company Governance
  Approval does not approve, re-approve, or redefine the underlying Protocol
  Governance decision.

### 2.4 Management of Foundation operating assets

- Manage Foundation operating assets received for the Foundation's own non-profit
  activities.
- Segregate Foundation operating assets from the Protocol Treasury, user assets,
  and other protocol assets.

### 2.5 Liability backstop / indemnity wrapper

- May be the entity that assumes, defends, or indemnifies protocol-related claims.
- Funding for claim response, defence, and indemnity is limited to Foundation
  operating assets and insurance; the Protocol Treasury, user assets, and other
  protocol assets are not applied.

### 2.6 Private corporate governance and records

- CDRs, Member deliberation and votes, and approval of Foundation operating
  assets are conducted through an access-controlled private governance process,
  separate from public Protocol Governance.
- Public disclosure is limited to the minimum necessary — the RMI / MIDAO
  registry, statutory contact details, required smart-contract identifiers and
  public blockchain information, and similar. Private CDRs and contract terms are
  as a rule not published.
- Private off-chain governance does not rely on any public-ledger recordkeeping
  exemption; minutes, votes, accounts, and execution evidence are retained in
  accordance with applicable law and internal operations. The implementation of
  the repository, exports, and backups is defined in operating procedures rather
  than in the OA.

---

## 3. Foundation prohibitions

The Foundation must not do the following.

### 3.1 Not be the issuer of JPYdf or an obligor for maintaining its value

- Not be, and not represent itself as, the issuer of JPYdf.
- Not issue or mint JPYdf.
- Not assume, guarantee, or bear any obligation regarding the redemption,
  repurchase, or value maintenance of JPYdf.

### 3.2 Not be a counterparty or intermediary to user transactions

- Not be a party to a bilateral transaction with a user in respect of borrow,
  repay, opening / adjusting / closing a Trove, depositing to or withdrawing from
  the Stability Pool, redemption, liquidation, or any other user transaction.
- Not, as the Foundation, perform, intermediate, accept, reject, approve, or
  settle user transactions.

### 3.3 Not custody, own, or control user assets

- Not custody, hold, own, transfer, or exercise discretionary control over user
  collateral, assets deposited into the Stability Pool, assets recorded in or
  attributable to a Trove, assets transferred in the course of redemption or
  liquidation, or any other user assets, for or on behalf of users.
- Not hold private keys, signing authority, withdrawal authority, or any other
  power of disposition over such assets.

### 3.4 Not hold protocol keys / roles / authority

- Not hold signing keys or authority relating to the protocol's smart contracts,
  governance process, Protocol Treasury, risk controls, emergency controls, bridge
  controls, parameter setting, asset allocation, or similar protocol functions.
- Not take the position of signer, role holder, admin, operator, controller, or
  any equivalent position in respect of those functions.

### 3.5 Not decide, execute, or act in place of Protocol Governance

- Not decide, approve, amend, direct, or execute on-chain any matter within the
  scope of Protocol Governance, whether directly or through an arrangement acting
  for the Foundation.
- Not act on behalf of Protocol Governance, not operate or pause the protocol, and
  not otherwise exercise de facto control over the protocol.

### 3.6 Not own, manage, or dispose of the Protocol Treasury

- Not own, hold, manage, control, or dispose of the Protocol Treasury as the
  Foundation's own asset, a balance-sheet asset, or a freely disposable asset.

### 3.7 No private inurement or ownership distribution

- Not cause the Foundation's assets, income, earnings, or residual assets to inure
  to the benefit of a private person, nor distribute them as an ownership
  distribution.
- Grants that advance the Foundation's non-profit purpose, reasonable compensation
  for services actually rendered, and reimbursement of expenses incurred for the
  Foundation are not within the foregoing prohibition.
- On dissolution, residual assets are not distributed to private persons and are
  transferred to a non-profit entity consistent with the Foundation's non-profit
  purpose.

---

## 4. Asset boundaries

| Asset class | Definition | Treatment at the Foundation |
| --- | --- | --- |
| Foundation operating assets | Assets received for the Foundation's own non-profit activities | The Foundation may manage them, segregated from the Protocol Treasury, user assets, and other protocol assets |
| Protocol Treasury | Protocol revenue and other treasury assets held and managed by on-chain smart contracts under Protocol Governance | The Foundation does not own, hold, manage, control, or dispose of them |
| User assets | Collateral, Stability Pool assets, Trove assets, assets in the redemption / liquidation flow, and other user assets | The Foundation does not custody, own, transfer, or exercise discretionary control over them |
| Other protocol assets | Assets attributable to the protocol other than the Protocol Treasury and user assets | Not made assets of the Foundation |
| IP / trademark / domain / documentation | Ecosystem assets the Foundation may hold and manage as steward | May be held and managed, but not conflated with ownership, operation, or control of the protocol |

---

## 5. Roles and authority boundaries

| Subject | Role / actor | Foundation's authority boundary |
| --- | --- | --- |
| Foundation | Steward of the JPY DeFi protocol and ecosystem / administrative layer supporting the protocol and its governance | May perform the activities in §2, but does not perform the acts in §3 |
| JPY DeFi protocol / user transactions | Initiated by users and other protocol participants and executed by the smart contracts according to code and rules | Does not become issuer, counterparty, intermediary, custodian, operator, or controller |
| Protocol Governance | The procedure in effect at the time, external to the Company | Does not decide, approve, or direct matters within its scope, and does not execute them on-chain |
| DFKK | Candidate contributor / service provider / grant recipient | Not to be the sole or de facto controller of the Foundation or the protocol |

---

## 6. Jurisdiction-specific implementation

Rendering into an RMI DAO LLC, the pre-formation confirmation Gate, OA / CF /
BOIR, Members, MIDAO procedures, records / evidence, and counsel review are
handled by
[`Foundation-Entity-RMI-DAO-LLC-Requirements.md`](../../../jp/foundation/requirements/Foundation-Entity-RMI-DAO-LLC-Requirements.md)
and
[`Foundation-MIDAO-Onboarding-Guide.md`](../../../jp/foundation/runbooks/Foundation-MIDAO-Onboarding-Guide.md),
and are not part of the core requirements in this document.

---

## 7. Referenced documents

- RMI DAO LLC specific requirements: [`Foundation-Entity-RMI-DAO-LLC-Requirements.md`](../../../jp/foundation/requirements/Foundation-Entity-RMI-DAO-LLC-Requirements.md)
- OA supporting checklist: [`Foundation-Entity-Operating-Agreement-Requirements.md`](../../../jp/foundation/requirements/Foundation-Entity-Operating-Agreement-Requirements.md)
- Signer candidate requirements for Member / Foundation Operating Multisig Wallet: [`Foundation-Entity-Member-Signer-Requirements.md`](../../../jp/foundation/requirements/Foundation-Entity-Member-Signer-Requirements.md)
- MIDAO procedures: [`Foundation-MIDAO-Onboarding-Guide.md`](../../../jp/foundation/runbooks/Foundation-MIDAO-Onboarding-Guide.md)
- Company decision / CDR procedures: [`Foundation-Entity-Corporate-Decision-Process.md`](../../../jp/foundation/runbooks/Foundation-Entity-Corporate-Decision-Process.md)
- Foundation Governance GitHub runbook: [`Foundation-Governance-GitHub-Operations.md`](../../../jp/foundation/runbooks/Foundation-Governance-GitHub-Operations.md)
- Sources and reference materials: [`Foundation-Entity-Setup-References.md`](../../../jp/foundation/evidence/Foundation-Entity-Setup-References.md)
