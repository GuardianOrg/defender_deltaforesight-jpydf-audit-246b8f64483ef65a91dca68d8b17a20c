# JPYdf Foundation Setup References

> 本書は [`Foundation-Entity-Setup-Requirements.md`](../requirements/Foundation-Entity-Setup-Requirements.md) と [`Foundation-Entity-RMI-DAO-LLC-Requirements.md`](../requirements/Foundation-Entity-RMI-DAO-LLC-Requirements.md) の参考資料であり、要件正本ではない。判例、RMI DAO LLC の制度上の根拠、公開先行事例、依拠してはならない前提、主要出典をここに集約し、要件本文は必須事項に絞る。

---

## 1. 責任引受・インデムニフィケーションの参考資料

### 1.1 背景（判例）

ラップされない DAO・資産プールの参加者は、次のとおり訴訟リスクに晒され得る。

- *Sarcuni v. bZx DAO*（S.D. Cal. 2023-03-27, 664 F. Supp. 3d 1100）：当該 DAO の governance token 保有者全員を組合員とする general partnership の主張が motion to dismiss 段階で維持された。
- *CFTC v. Ooki DAO*（N.D. Cal. 2023-06 default judgment）：DAO 自体が CEA 上の person として制裁対象になった。
- *Samuels v. Lido DAO*（N.D. Cal. 2024-11-18）：Lido DAO は general partnership と適切に主張されたと判示され、Lido DAO governance に意味ある参加をした VC 投資家について訴訟が継続した。

上記は、プールに法的な帰属主体がない場合に、請求者・裁判所がその背後の個人・会社へ責任追及を試み得ることを示す。Foundation を責任の受け皿として明示的に立てる設計は、Member・署名者・コントリビューター保護のための参考になる。

### 1.2 RMI 法上の道具立て

RMI DAO LLC を採用する場合、少なくとも次の制度上の道具立てがある。他法域を採用する場合も、同等の責任遮断・indemnity・義務水準の手当てを確認する。

- LLC Act 1996 §20(1)：DAO LLC の債務はエンティティ単独の債務であり、Member／Manager はその地位のみを理由に個人責任を負わない。
- LLC Act 1996 §8：DAO LLC は Member、Manager、その他の者を indemnify する法定権限を持つ。具体的な対象・例外・原資は OA で定める。
- LLC Act 1996 §20(2)：Member／Manager 個人が任意に債務を引き受けるオプトイン規定。本件では OA またはその下位の governance rule 単独では個人責任引受を構成しないものとし、引受には当該 Member 自身が別個の書面による契約を明示的に締結することを要する前提。
- DAO Act §109：Member の fiduciary duty はデフォルトで否定され、good faith の黙示条項が残る。authorized agent / nominee / service provider を使う場合の義務水準は OA または service agreement で能動的に定義する。

### 1.3 公開前例・設計メモ

- 公開されている RMI DAO LLC の OA 実例（例：Odos DAO LLC）は、LLC Act §8 追随の indemnity 権限までは確認できるが、プロトコル資産プール関連クレームについて Foundation が責任の受け皿になる明示条項は一般的な先例として確立していない。JPY DeFi では意識的にドラフトする。
- indemnity の carve-out は fraud／willful misconduct／gross negligence を基準に置く。dYdX の Guernsey purpose trust や Lido Alliance BORG の公開実例が参考になる。
- indemnity・引受の原資を Foundation operating funds に限定し、それ以外の資産に及ぼすには DAO / Protocol Governance による承認を要する設計は、Lido Alliance BORG の公開実例が参考になる。
- a16z の siloed entity フレームワークおよび Paradigm の DAO wrapper 論点は、wrapper entity と protocol の相互作用を限定し、entity disregard を避ける設計上の参考になる。
- 保険は indemnity と別建ての検討事項である。標準的な D&O は authorized agent／nominee・署名者等の職務起因責任を対象にし得るが、Protocol Governance に能動参加する tokenholder / contributor の個人責任まで広げるには専用商品の検討が必要になる。Fenwick の REBA は一例であり、汎用類型ではなく特定ベンダーの商品として評価する。

---

## 2. 先行事例と依拠してはならない前提

### 2.1 参照してよい先行事例

- **PYTH DAO LLC（OA 公開）** — 非営利・algorithmically managed。公開 Constitution が OA（IPFS）を参照しており、OA 上は Members＝staked PYTH holder、1 staked token＝1 membership interest／1 vote、経済権なし、Council への権限委任、smart contract 上の記録、Pyth DAO governance vote による OA 改定、解散時の非営利目的エンティティへの資産移転を定める。Day-1 member-managed / managerless の前例ではないため、将来 algorithmically managed へ移行する場合の OA 条項設計の参考に限定する。
- **3A DAO LLC（公開情報は registry まで）** — MIDAO 公開レジストリ上は 2022 年登録・Non-Profit DAO LLC・Good Standing。OA、Constitution、EURO3 との関係、Managing Member／Member 構成を示す公開資料は未確認。MIDAO から OA または構成説明を取得するまで、非営利 RMI DAO LLC の登録実例としてのみ扱い、CDP ステーブルコイン運営構造の前例としては依拠しない。
- 多数決型マルチシグの独立性設計：Arbitrum Security Council（非関連性上限）・Optimism（2-of-2 二層＋1 エンティティ 1 名）・ZKsync Guardians（veto-only）。
- 署名者規模の参考基準：SEAL Secure Multisig Best Practices は、最低 3 署名者・閾値 50% 以上、US$1M 超の管理資産では 7 署名者以上を目安にする。
- 能動的監督の参考事例：Cayman の *Weavering* 事件は、受動的な independent director / nominee の危険性と、証跡ある監督の重要性を示す参考資料として扱う。
- nominee / independent manager ベンダー：公開情報だけでは役務範囲・価格・運営者情報が不足する場合があるため、採用時は MIDAO／候補ベンダーから直接書面取得する。

### 2.2 依拠してはならない前提

- **M1X／USDM1 は「DAO LLC 発行ステーブルコイン」の前例ではない**。USDM1 は RMI 政府自身が発行するソブリン債であり、「M1X DAO LLC」は公開レジストリに存在しない。
- **Lido の treasury 解説記事は法人構造の前例ではない**。純オンチェーン・トレジャリーの解説であり、法人・法域への言及はない。Lido の現行のラッパー実務は Cayman の BORG 財団群（資産保有＋DAO オンチェーン veto＋原資限定 indemnity）として別に評価する。
- **Silk DAO LLC は Cancelled／Seneca DAO LLC は Not in Good Standing**。RMI の維持義務は実際に執行されることを前提にする。

---

## 3. 主要出典メモ

- **RMI 法令（原文）**：DAO Act 2022 codified（52 MIRC Ch.7。§102(i)・§103(2)(d)・§105(4)・§112）・DAO (Amendment) Act 2023（P.L. 2023-83）・DAO Regulations 2024・LLC Act 1996（52 MIRC Ch.4）・Non-Profit Entities Act 2020（18 MIRC Ch.2。§202、§206、§207、§222、§228）・Income Tax Act 1989 §109。
- **MIDAO 公式**：docs.midao.org（nominees／KYC-KYB／non-profit／taxes／naming）・midao.org/pricing・registry.midao.org（公開レジストリ）。
- **判例**：*Sarcuni v. bZx DAO*, 664 F. Supp. 3d 1100 (S.D. Cal. 2023)／*CFTC v. Ooki DAO*（CFTC Release 8715-23）／*Samuels v. Lido DAO*, No. 23-cv-06492-VC (N.D. Cal. Nov. 18, 2024)／*Weavering*（Cayman、Ogier・Conyers 解説）。
- **設計前例・ベストプラクティス**：Pyth DAO Constitution／Operating Agreement・ArbitrumDAO Constitution・Optimism privileged roles／Security Council Charter v0.1・ZKsync Governance Schedule 4・SEAL Secure Multisig Best Practices・OpenZeppelin「Admin accounts and multisigs」・Trail of Bits「Maturing your smart contracts beyond private key risk」・Lido Alliance BORG・Odos DAO LLC Operating Agreement・dYdX Foundation「Legal Framework: Non-U.S. Trusts in DAOs」・a16z crypto「A Legal Framework for DAOs」「The DUNA」・Paradigm「DAO Strategy and Legal Wrappers」・FATF INR.24。
- **DAO 参加者責任・保険**：Fenwick「The Legal Landscape for DAOs: Key Lessons from Lido DAO and Ooki DAO」・Fenwick「REBA Solution」。
- **日本法（e-Gov 原文）**：租税特別措置法 66 条の 6・40 条の 4・66 条の 4／同施行令 39 条の 12・39 条の 14・39 条の 16／法人税法 2 条・37 条・141 条／同施行令 4 条の 4。財務省 租税条約ネットワーク。国税庁 暗号資産 FAQ（令和 7 年 12 月版）・外国子会社合算税制 Q&A・米国 LLC 質疑応答。
- **実装・設計（本リポジトリ）**：[`Foundation-Entity-Operating-Agreement-Requirements.md`](../requirements/Foundation-Entity-Operating-Agreement-Requirements.md)・[`Foundation-Entity-Member-Signer-Requirements.md`](../requirements/Foundation-Entity-Member-Signer-Requirements.md)・[`../../Governance.md`](../../Governance.md)・[`../../Parameters.md`](../../Parameters.md)・[`Governance-Roles-Timelock.md`](../../protocol/product/policies/Governance-Roles-Timelock.md)・[`Mainnet-Safe-Role-Assignment-Gate.md`](../../protocol/launch/gates/Mainnet-Safe-Role-Assignment-Gate.md)・[`Mainnet-Launch-Product-Decision-Record.md`](../../protocol/launch/decisions/Mainnet-Launch-Product-Decision-Record.md)・[`Balance-Sheet-Liquidity-Allocation-Policy.md`](../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md)。
