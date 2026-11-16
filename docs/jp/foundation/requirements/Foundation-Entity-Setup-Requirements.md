# JPYdf Foundation Setup Requirements

> **本書の役割**: Foundation を設立するにあたり、法域を問わず必ず満たすべき core requirements を、外部 counsel に共有できる形で整理する。RMI DAO LLC / MIDAO / BOIR / OA / Member / 候補依頼の詳細は [`Foundation-Entity-RMI-DAO-LLC-Requirements.md`](./Foundation-Entity-RMI-DAO-LLC-Requirements.md) を正本とする。
>
> **文書関係**: 本書が Foundation の目的、許容活動および禁止事項に関する法域中立な上位要件を定義し、[`Foundation-Entity-OA-Draft.md`](../spec/Foundation-Entity-OA-Draft.md) はこれを契約条項へ落とし込む（[`Foundation-Entity-OA-Draft.ja.md`](../spec/Foundation-Entity-OA-Draft.ja.md) は日本語参照訳）。OA は、本書が定める Foundation の権限を拡張し、または禁止事項を弱めてはならない。
>
> **対象外**: RMI 法制の細目、OA 条項案、候補者への依頼文、MIDAO ポータル手順、実 signer address / Safe address / threshold、KYC link、個人情報。

---

## 1. 基本方針

DeltaForesight は、Ethereum mainnet 上で稼働する過剰担保型 CDP protocol「JPY DeFi」を開発している。JPYdf は、JPY DeFi protocol の smart contracts により mint / burn される円建て stablecoin である。borrow、repay、Trove の開設・変更・閉鎖、Stability Pool への預入・引出、redemption、liquidation その他の user transaction は、ユーザーその他の protocol participant が開始し、その時点で有効な code と rules に従って JPY DeFi protocol の smart contracts が実行する。Foundation の承認を要しない。

Foundation は、JPY DeFi protocol および ecosystem の長期的な **steward かつ protocol およびその governance を支援する administrative layer** として設立する non-profit entity である。この役割は、Foundation が JPYdf の issuer、user transaction の counterparty / intermediary、user asset の custodian、protocol operator、Protocol Governance の decision-maker / executor または Protocol Treasury の owner になることを意味しない。

Foundation の活動に関する意思決定を行う Company Governance と Protocol Governance は、別の権限系統である。

DeltaForesight 株式会社（DFKK）は、ソフトウェア開発、非独占フロントエンド、マーケティング、コミュニティ支援等を行う一 contributor であり、Foundation または protocol の単独・実質支配者にしない。

---

## 2. Foundation の目的・許容活動

Foundation の目的および許容される活動は、次に掲げるものに限定する。

### 2.1 IP / domain / documentation の stewardship

- JPY DeFi protocol および ecosystem に関する知的財産、商標、ドメイン、ドキュメントを保有・管理する。
- IP license や documentation 管理を通じて ecosystem の継続性を支える。ただし、これを理由として protocol またはその implementation を所有・運営・支配していると扱わない。

### 2.2 Contributor / service provider / grant recipient との契約

- DFKK を含む contributor、service provider、grant recipient との契約を締結・管理できる。

### 2.3 Protocol Governance の決定に付随する off-chain 行為

- Protocol Governance により承認された事項について、契約締結、記録、確認、通知、filing その他の off-chain 行為が必要となる場合、その行為を記録・確認・実行できる。
- 当該 off-chain 行為は Company Governance Approval の対象とし、基礎となる Protocol Governance の有効な決定・記録・必要な execution evidence の双方が揃った場合に限り実行できる。Company Governance Approval は、基礎となる Protocol Governance の決定を承認、再承認または再定義しない。

### 2.4 Foundation operating assets の管理

- Foundation 自身の非営利活動のために受領した Foundation operating assets を管理する。
- Foundation operating assets を、Protocol Treasury、user assets およびその他の protocol assets と分離する。

### 2.5 Liability backstop / indemnity wrapper

- protocol 関連 claim を引き受け、防御し、または補償する主体になり得る。
- claim 対応・防御・補償の原資は Foundation operating assets / insurance に限定し、Protocol Treasury、user assets その他の protocol assets を充てない。

### 2.6 Private corporate governance and records

- CDR、Member 討議・vote、Foundation operating assets の承認は access-controlled な private governance process で行い、public Protocol Governance と分離する。
- 公開は RMI / MIDAO registry、法定連絡先、必要な smart-contract identifier / public blockchain 情報等の最小範囲とし、private CDR や契約条件を原則公開しない。
- private off-chain governance は public-ledger recordkeeping 特例に依存せず、議事・vote・会計・execution evidence を適用法および社内運用に従って保持する。repository、export、backup の実装は OA ではなく運用手順で定める。

---

## 3. Foundation の禁止事項

Foundation は次を行ってはならない。

### 3.1 JPYdf の issuer または価値維持義務者にならない

- JPYdf の issuer にならず、issuer であると表示しない。
- JPYdf を発行または mint しない。
- JPYdf の redemption、repurchase または価値維持に関する義務を引き受け、保証し、または負担しない。

### 3.2 User transaction の counterparty / intermediary にならない

- borrow、repay、Trove の開設・変更・閉鎖、Stability Pool への預入・引出、redemption、liquidation その他の user transaction について、ユーザーとの相対取引の当事者にならない。
- Foundation として、user transaction を行い、仲介し、受け付け、拒否し、承認し、または決済しない。

### 3.3 User assets を custody / own / control しない

- ユーザー担保、Stability Pool に預け入れられた資産、Trove に記録されもしくは帰属する資産、redemption / liquidation の過程で移転される資産その他の user assets を、ユーザーのために、またはユーザーに代わって custody、保有、所有、移転または discretionary control しない。
- これらの資産に関する private key、署名権限、withdrawal authority その他の処分権限を保有しない。

### 3.4 Protocol の key / role / authority を保有しない

- protocol の smart contracts、governance process、Protocol Treasury、risk controls、emergency controls、bridge controls、parameter setting、asset allocation その他これらに類する protocol function に関する signing key または authority を保有しない。
- 当該 function に関する signer、role holder、admin、operator、controller その他これらに相当する地位に就かない。

### 3.5 Protocol Governance を決定・執行・代行しない

- Foundation が直接、または Foundation のために行動する arrangement を通じて、Protocol Governance の対象事項を決定、承認、変更、指示または on-chain で実行しない。
- Protocol Governance に代わって行動せず、protocol を運営・pause せず、その他の方法で protocol に対する実質的支配を行使しない。

### 3.6 Protocol Treasury を所有・管理・処分しない

- Protocol Treasury を Foundation の固有資産、貸借対照表上の資産または自由処分可能な資産として所有、保有、管理、支配または処分しない。

### 3.7 Private inurement / ownership distribution をしない

- Foundation の資産、所得、収益または残余財産を、private person の利益に帰属させ、または ownership distribution として分配しない。
- Foundation の非営利目的を推進する grant、実際に提供された役務への reasonable compensation、および Foundation のために生じた費用の reimbursement は、前項の禁止に含まれない。
- 解散時の残余財産は private person に分配せず、Foundation の非営利目的と整合する非営利主体へ移転する。

---

## 4. 資産境界

| 資産区分                                | 定義                                                                                                                 | Foundation における扱い                                                                   |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Foundation operating assets             | Foundation 自身の非営利活動のために受領した資産                                                                      | Foundation が管理でき、Protocol Treasury、user assets その他の protocol assets と分離する |
| Protocol Treasury                       | Protocol Governance の下で on-chain smart contracts により保有・管理される protocol revenue その他の treasury assets | Foundation は所有、保有、管理、支配または処分しない                                       |
| User assets                             | collateral、Stability Pool assets、Trove assets、redemption / liquidation flow その他の user assets                  | Foundation は custody、所有、移転または discretionary control しない                      |
| Other protocol assets                   | Protocol Treasury / user assets 以外の protocol に帰属する assets                                                    | Foundation の資産にしない                                                                 |
| IP / trademark / domain / documentation | Foundation が steward として保有・管理し得る ecosystem assets                                                        | 保有・管理できるが、protocol の ownership / operation / control と混同しない              |

---

## 5. 役割と権限境界

| 対象                              | 役割・主体                                                                                      | Foundation の権限境界                                                                |
| --------------------------------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Foundation                        | JPY DeFi protocol および ecosystem の steward / administrative layer supporting the protocol and its governance | §2 の活動を行うことができるが、§3 の行為を行わない                                   |
| JPY DeFi protocol / user transaction | ユーザーその他の protocol participant が開始し、smart contracts が code と rules に従って実行                  | issuer、counterparty、intermediary、custodian、operator または controller にならない |
| Protocol Governance               | Company の外部にある、その時点で有効な手続                                                               | 対象事項を決定・承認・指示せず、on-chain で実行しない                                |
| DFKK                              | contributor / service provider / grant recipient 候補                                                          | Foundation または protocol の単独・実質支配者にしない                                |

---

## 6. 法域固有の実装

RMI DAO LLC への落とし込み、設立前の確認 Gate、OA / CF / BOIR、Member、MIDAO 手続、records / evidence および counsel review は、[`Foundation-Entity-RMI-DAO-LLC-Requirements.md`](./Foundation-Entity-RMI-DAO-LLC-Requirements.md) と [`Foundation-MIDAO-Onboarding-Guide.md`](../runbooks/Foundation-MIDAO-Onboarding-Guide.md) が扱い、本書の core requirements には含めない。

---

## 7. 参照文書

- RMI DAO LLC 固有要件: [`Foundation-Entity-RMI-DAO-LLC-Requirements.md`](./Foundation-Entity-RMI-DAO-LLC-Requirements.md)
- OA 補助チェックリスト: [`Foundation-Entity-Operating-Agreement-Requirements.md`](./Foundation-Entity-Operating-Agreement-Requirements.md)
- Member / Foundation Operating Multisig Wallet の署名者候補要件: [`Foundation-Entity-Member-Signer-Requirements.md`](./Foundation-Entity-Member-Signer-Requirements.md)
- MIDAO 手順: [`Foundation-MIDAO-Onboarding-Guide.md`](../runbooks/Foundation-MIDAO-Onboarding-Guide.md)
- Company decision / CDR 手順: [`Foundation-Entity-Corporate-Decision-Process.md`](../runbooks/Foundation-Entity-Corporate-Decision-Process.md)
- Foundation Governance GitHub runbook: [`Foundation-Governance-GitHub-Operations.md`](../runbooks/Foundation-Governance-GitHub-Operations.md)
- 出典・参考資料: [`Foundation-Entity-Setup-References.md`](../evidence/Foundation-Entity-Setup-References.md)
