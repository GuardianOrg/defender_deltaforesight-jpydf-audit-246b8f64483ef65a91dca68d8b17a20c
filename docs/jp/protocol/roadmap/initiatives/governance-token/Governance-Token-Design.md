# ガバナンストークン設計（Governance Token Design）

## 0. 位置づけ

| 項目 | 値 |
| --- | --- |
| Status | Draft。Day-2 以降の設計メモ。**ガバナンストークン（DFT 仮称）の発行を前提としない** — 要否・方式・時期は §6 の decision gate で確定する |
| Owner | DeltaForesight |
| 対象 | Day-2 以降のガバナンス方式: 意思決定スコープの分類（§2）、投票主体 3 案の比較（§3）、先行事例エビデンス（§4）、段階導入と decision gate（§5・§6） |
| 関連ドキュメント | [Product-Overview](../../../product/Product-Overview.md) / [Governance](../../../../Governance.md) / [Governance-Roles-Timelock](../../../product/policies/Governance-Roles-Timelock.md) / [Day-1-Governance-Proposal-Execution-Policy](../../../launch/gates/Day-1-Governance-Proposal-Execution-Policy.md)（Day-1 の signer-block governance・JIP の正本）/ [PILAllocator](../../../product/spec/PILAllocator.md) / [Treasury](../../spec/Treasury.md) / 参考調査: [Day1-Governance-Reference-Web3-Projects](../../../../engineering/historical-reviews/2026-07-05-Day1-Governance-Reference-Web3-Projects.md)（他プロジェクトのガバナンス実務。本書 §4 はトークンの価格実績・攻撃事例側を担い、重複しない） |
| 市場データの時点 | 本書の価格・供給・TVL は **2026-07-07 時点**（CoinGecko / DefiLlama / 公式 docs。独立ソースで相互照合済みだが二次情報）。gate 判定時は再取得する |

本書は旧ドラフト（DFT 発行を前提とした設計）を置き換える。Day-1 にガバナンストークン・staking・投票 UI を持たない点は従来どおり（[Product-Overview](../../../product/Product-Overview.md) §4.1）。[Day-1-Governance-Proposal-Execution-Policy](../../../launch/gates/Day-1-Governance-Proposal-Execution-Policy.md) §11 が対象外と宣言した「**トークン発行の是非・時期・検討開始条件**」を本書が引き受ける。Day-2 の変更は PIL recipient → VotingAllocator に限定し、signer-block 承認レイヤーは存続させる。Governor を外部 GOV Timelock の一般 PROPOSER にせず、T2 専用の VotingAllocator にのみ接続することで、T1 へ到達できない権限境界をオンチェーンで強制する。

---

## 1. Design Summary

1. **T1 の拘束力ある実行権限は Day-2 でも変えない。** multisig ＋ Timelock（24h）＋ Guardian の既存境界（[Governance](../../../../Governance.md)）と、signer-block 承認（JIP）レイヤー（[Day-1 policy](../../../launch/gates/Day-1-Governance-Proposal-Execution-Policy.md)）を維持する。トークン投票に許す拘束力は、1 epoch の PIL 予算内で allowlist 済み initiative 間の weight を決める T2 専用 VotingAllocator に限る。トークン投票は外部 GOV Timelock の一般 PROPOSER にならず、JIP の技術承認・安全確認を代替しない。
2. **JPYdf を「拘束力ある投票権」に使う案は不採用とする。** 購入・mint 可能な資産による拘束投票は乗っ取り経路として繰り返し実証されており（§4.3）、CDP ステーブルコインでは攻撃コストが借入金利のみに縮退する。実装面でも `JpydfToken` は non-upgradeable・owner renounce 済・`burn` は Core 専用で、ガバナンス用 burn 経路を追加できない（§3.2）。JPYdf の利用は**提案 deposit（スパム防止）と非拘束シグナリングの投票主体**に限定して検討する。
3. **DFT の発行は否定しないが、前提にもしない。** 実収益に裏付けられた buyback を持たないステーブルコイン系ガバナンストークンは、規模を問わずほぼ全て ATH 比 -94%〜-99.9% で保有者に損失を残している（§4.2）。円金利環境では JPYdf の fee-share 原資は当面この必要条件を 2〜3 桁下回る（§4.4）。発行するなら「PMF・収益確立後に発行する」sequencing（Hyperliquid 型）とし、§6 の gate を満たすまで token contract の deploy、TGE、配布、プロジェクト主導の CEX listing、プロトコルへの権限・経済接続を行わない。
4. **Day-2 初期は「非拘束シグナリング ＋ 実行は既存 Timelock」で開始する**（§5 Step 1）。これは Beanstalk が governance 攻撃後に採用した Snapshot ＋ multisig 実行型と同型で、追加のオンチェーン実装をほぼ要しない。
5. **PIL Phase-B（投票型 allocator）は投票トークン非依存に設計する。** [PILAllocator](../../../product/spec/PILAllocator.md) PILA-GOV-004 の「DFT staking」は「投票トークン（未確定）」と読み替え、本書確定後に同 spec を追従改訂する（§7）。

---

## 2. ガバナンス対象のスコープ分類

[Governance](../../../../Governance.md) が定義する権限を、トークン投票へ開放しうるかで 3 Tier に分類する。**この分類が本書の背骨**である。T2 は「1 epoch の確定済み PIL 予算を、allowlist 済み initiative 間で配分する weight」に限定する。VotingAllocator は予算総額・送付資産・送付先 allowlist を変更できず、外部 GOV Timelock の PROPOSER 権限を持たない。この境界をコントラクトで強制し、各 epoch の配分を監視して次回配分前に pause / recipient 差替できる運用を置くことで、1 回の悪意ある投票による直接損失を当該 epoch の PIL 予算以下に閉じる。

| Tier | 性質 | 対象（例） | Day-2 での扱い |
| --- | --- | --- | --- |
| **T1: 資金保全直結** | 失敗が担保・供給・プロトコル保有資産の毀損に直結 | Vault / dToken / Strategy の UUPS upgrade、oracle source 差替、`writeoffStrategyPrincipal`、unpause、cap、bridge minter、Timelock role 変更、Strategy venue / adapter、Treasury の reward asset / share / destination・Distributor funding、資金移転 | **いかなるトークン投票にも渡さない**。既存の multisig ＋ Timelock ＋ Guardian と signer-block 承認を維持。トークン投票は最大でも「非拘束の事前シグナル」 |
| **T2: 上限付き PIL 配分** | 1 回の悪意ある投票による直接損失を当該 epoch の確定済み PIL 予算に閉じ込められる | allowlist 済み PIL initiative 間の weight（[PILAllocator](../../../product/spec/PILAllocator.md)） | 拘束投票に開放しうる唯一の領域。VotingAllocator に epoch cap・送付先 allowlist・pause を実装し、予算総額・資産・送付先の変更権限を持たせない。initiative の登録・allowlist 変更は T1 として JIP 承認で行う。各配分を監視し、異常時は次回配分前に pause / recipient 差替を行う |
| **T3: 方針シグナル** | 拘束力を持たせる必要がない | 新担保 branch 候補の優先度、チェーン展開・bridge 接続先の希望、パラメータ変更要望 | 非拘束シグナリングとして Day-2 初期から開始できる |

> 旧ドラフトの「Governance Scope」（Strategy / PIL / Treasury / Protocol admin の 4 領域と、Core immutable への不介入）は本分類に吸収した。Core の借入・償還・清算・SP・branch immutable パラメータが**そもそもガバナンス対象外**である点は不変（SYS-NFR-002 / ARCH-001）。

---

## 3. 投票メカニズム 3 案の比較

| 観点 | **A: トークンレス継続** | **B: JPYdf を投票に使う** | **C: DFT を発行する** |
| --- | --- | --- | --- |
| 拘束投票の攻撃耐性 | n/a（拘束投票を作らない） | ✗ mint-to-vote に構造的に脆弱（§3.2・§4.3） | △ time-weighted voting で flash 攻撃は緩和可（Liquity V2-gov で実証、§4.1）。市場買い集め型は残る |
| 実装・監査コスト | ほぼゼロ（Snapshot 等のオフチェーン） | burn 経路なし・stake は SP と資本競合（§3.2） | VotingAllocator ほか新規実装＋別監査（PILA-GOV-004） |
| 規制・税務 | 追加論点なし | **本体 JPYdf の規制区分を汚染するリスク**（§4.5） | 論点を発行体・別トークン側に隔離可（それ自体は要法務確認） |
| 先行事例の実績 | Felix: トークンなしで Liquity v2 fork 最大 TVL（§4.2） | 主要先行例なし。最近傍の Beanstalk（預入投票）は $182M 喪失で崩壊（§4.3） | 実収益 buyback なしの発行例はほぼ全敗（§4.2） |
| 資金調達 | なし（points で将来期待は供給可能） | なし | あり（国内 IEO 実績 数億〜15 億円、海外 TGE。§4.5） |
| コミュニティへの分配 | points（後日トークン化の選択肢を保持） | 提案 deposit・シグナル参加のみ | staking / 投票 / bribe / airdrop |

### 3.1 A: トークンレス継続 — Day-2 初期の標準

現行の Governance 構成（multisig ＋ Timelock ＋ Guardian）をそのまま維持し、参加要素は §5 Step 1 の非拘束シグナリングと points プログラムで供給する。points は「後日トークンを発行する場合の配分根拠」になるため、**C 案の選択肢を消さずに** トークンレス期間を延長できる（Hyperliquid は mainnet から TGE まで約 1.5 年、Felix・Polymarket はトークンなしで運営継続中。§4.2）。

### 3.2 B: JPYdf 利用の評価 — 拘束投票には使えない。使える形は 2 つ

**burn-to-vote は実装不可能に近い。** `JpydfToken` は non-upgradeable（SYS-CON-004）で owner は deploy 配線後に自己 renounce 済、`burn` は Core（BO / TroveManager / SP / CollateralRegistry）専用であり、ガバナンス用 burn 経路を後付けできない（[Governance](../../../../Governance.md) §2・§9）。dead address 送付の擬似 burn は可能だが、「1 票 = ¥1 の全損」の投票に経済合理的な参加は見込めない。

**stake-to-vote（拘束）は攻撃と資本競合の両面で不成立。**

- 攻撃者は担保（USDC 等）を入れて JPYdf を mint するだけで投票権を得られる。コストは user-set 借入金利のみで、円金利環境では額面の年 1〜2% 程度で投票権を「レンタル」できる。time-weighted 化しても、資本コストが低いため長期保有型の買い集めを排除できない。
- ガバナンス失敗で JPYdf が減価すると、**mint した攻撃者（= 債務者）は実質債務の低下で利得する**。投票主体の経済的エクスポージャーが負に反転しうる点で、Vitalik の指摘する「借入トークン投票者はエクスポージャーを負わない」（§4.3）より悪い。
- stake は Stability Pool（清算の第一原資・借入金利 75% の受け皿）と同じ JPYdf の奪い合いになり、SP coverage（launch/ops の管理指標）を毀損する方向に働く。
- MakerDAO が「ガバナンス失敗時に MKR 保有者が希薄化で損失を負う（debt auction）」構造でガバナンス主体に skin in the game を課しているのと正反対に、ステーブルコイン保有者は失敗の損失を引き受ける主体として設計できない。主要プロトコル（Maker / Curve / Aave / Frax / Liquity）が例外なくステーブルコインと投票権を分離しているのはこのためと解される（§4.3）。

**使える形（採用候補）は次の 2 つに限る。**

1. **提案 deposit**: 提案時に一定額の JPYdf を escrow に deposit させ、スパム・veto 成立時は Treasury へ slash、正常終了時は返還する（Cosmos Hub の deposit＋burn、Curve の 2500 veCRV 提案閾値、Arbitrum の 1M ARB 閾値と同型）。投票権は付与しないため mint-to-vote が成立しない。
2. **非拘束シグナリングの投票主体**: JPYdf 保有者・SP 預入者・Trove owner（借り手）の time-weighted snapshot を投票主体とする advisory 投票。結果は Timelock 提案の参考情報であり、実行権限は既存 GOV に残るため、買収しても得られるものが「シグナル」しかなく攻撃が成立しない。

### 3.3 C: DFT を発行する場合の骨格（旧ドラフトから継承）

発行する場合の接続面は次の 3 面に限定する: (1) **T2 governance** = Governor は T2 専用 VotingAllocator にのみ接続し、外部 GOV Timelock の PROPOSER その他の T1 role を持たない、(2) **PIL allocation** = `InterestRouterForwarder.setRecipient(VotingAllocator)` による下流差替（Core 無改変・PILA-GOV-004）。VotingAllocator は allowlist 済み initiative の weight だけを、固定された epoch cap 内で変更できる、(3) **Token economics** = fee-share / buyback を採用する場合も、トークン投票に Treasury の設定・送金権限を与えず、signer-block 承認済みの固定予算を別途監査した Distributor から実行する。voting power は Liquity V2-gov 準拠の time-weighted 型（stake 直後は 0 から線形増加）を第一候補とする（§4.1）。

発行しない・遅らせる場合も、PIL の Forwarder recipient 差替により VotingAllocator を後から接続できる。Token economics は既存 Treasury の権限境界へ混在させず、採用時に固定予算の Distributor を別設計・別監査する。**したがって DFT を前提から外してもプロトコル側で失うものはなく、意思決定を §6 の gate まで遅延できる。**

---

## 4. エビデンス（2026-07-07 時点）

### 4.1 Liquity 本家 — 機構は堅牢、トークンの価値裏付けは失敗

- v1 は「ガバナンスゼロ・完全 immutable」で 2021 年から無事故稼働。v2 は唯一のガバナンスとして、借入金利 25%（PIL）の配分先を LQTY staking の週次 epoch 投票で決める（[docs](https://docs.liquity.org/v2-faq/lqty-staking) / [V2-gov](https://github.com/liquity/V2-gov)）。
- **time-weighted voting power**（voting power = stake 量 × 経過時間。新規 stake は 0 から線形増加）が flash loan / 即時買い集めを構造的に無効化し、60 epoch 無事故で稼働。initiative 登録は permissionless（投票力 0.01% ＋ 100 BOLD）、落選 initiative の抹消も permissionless。**Phase-B allocator の投票機構としてはこの設計をそのまま第一候補にできる。**
- 一方で価値裏付けは失敗: LQTY は ATH $146.94（2021-04）→ **$0.18（-99.9%）**、v2 稼働 1 年後の 2026-06 に ATL 更新。BOLD 供給が $30.5M（ピーク $49M）に留まるため PIL は週約 1.4 万 BOLD（≒$14K）の配分権に過ぎず、qualifying initiative は 4 件、bribe 市場は実質未成立（Liquity 自身の試算では bribe 市場成立に「供給 $250M・年 PIL $3.1M」規模が必要）。

### 4.2 フォークと主要プロジェクトの価格実績 — 「実収益 buyback なしの発行」はほぼ全敗

**Liquity v2 friendly forks**（2026-07-07、CoinGecko / DefiLlama、独立ソース照合済）:

| プロジェクト | トークン | 実績 |
| --- | --- | --- |
| **Felix**（Hyperliquid, feUSD） | **未発行**（points のみ） | fork 最大の成功例: TVL 計 ≈$143M（CDP ピーク $294M）、feUSD $11.7M。トークンなしが成長の障害になっていない |
| Beraborrow（Berachain, NECT） | POLLEN | 公募 FDV $42M → **-99.3%**。TVL ピーク $423M → $320K（チェーンごと崩壊） |
| Asymmetry（Ethereum, USDaf） | ASF | ATH $4.36 → $0.011（**-99.75%**）。ve 型収益分配を装備しても USDaf がピーク $21M 止まり |
| Nerite（Arbitrum, USND） | NERI | TGE 2026-03 → 3 ヶ月で **-81%**、FDV $35K。利息配分投票＋ARB 委任と JPYdf 検討に最も近い設計だが実質失敗 |
| Ēnosys Loans（Flare） | 既存 APS 流用 | 「新規発行せず既存トークンで統治」する唯一の実例。プロトコルは Felix に次ぐ TVL $4.7M だが APS 自体は -99.7% |
| Quill / Orki / Ebisu / Soneta / Aesyx / DeFi Dollar | 未発行 or 値付けなし | いずれも TVL $100K 未満〜消滅（Orki は Swellchain ごと 2026-06 に shutdown）。トークン計画の公表はトラクションを生まなかった |

**主要ステーブルコイン系ガバナンストークン 13 銘柄**: 10 銘柄が ATH 比 **-94% 超**（中央値 -99.4%）: CRV -98.7% / FRAX(旧FXS) -99.4% / ENA -95% / PRISMA -99.96% / SPELL -99.75% / ALCX -99.9% / INV -99.5% / FLX -99.9% / LISTA -94.2% / LQTY -99.9%。例外は 3 つだけ:

| 例外 | ATH 比 | 維持できた理由 |
| --- | --- | --- |
| SKY（旧MKR, USDS/DAI 計 $12.5B） | -45%（2024-12 ATH 比） | 年 ~$435M の実収益から **$1M/日の buyback&burn**（2025 年 $102M 投入）。emission 削減可決（2026-03）に価格が即 +10% 反応 |
| AAVE（GHO, TVL $13.3B） | -86%（2021 ATH 比） | 2025-04 から $1M/週 buyback、2026-07 Aavenomics 3.0 で全収益を buyback へ接続 |
| MKR（→SKY 統合） | -80%（2021 ATH 比） | Smart Burn Engine と $12.5B の供給規模 |

横断観察: 価格下落を相対的に抑えた例には、大規模なステーブルコイン供給、継続的な実収益、実収益に裏付けられた buyback、重大 exploit の回避が共通する。ただし ATH 比の横断比較だけでは因果を特定できず、buyback 金額と emission 数量も評価価格なしには比較できない。この観察をそのまま発行 gate にせず、G1 では実測 NDCF と 36 ヶ月の tokenomics 感応度を判定する。fee share の存在だけでは価格を守れなかった事例（CRV / SPELL / LISTA）と、周辺 zap の脆弱性でプロトコルとトークンが同時に毀損した PRISMA（-99.96%、$11.6M exploit）は設計上の反面教師とする。

**留意（結論を「発行禁止」に倒さないための 2 点）**: (1) 2025 年は市場全体で中央値トークン -79% の弱気相場であり、上記下落の一部は市場ベータ。(2) **Hyperliquid（HYPE）が強力な反例**: mainnet 後 約1.5 年トークンレスで PMF を確立してから TGE（2024-11、供給 31% を実ユーザーへ・VC 割当なし）し、四半期 $200-300M 級の収益 buyback を伴って時価総額 $15B 級を維持。正しい教訓は「発行するな」ではなく「**収益が立つ前に発行するな（sequencing）**」である。

### 4.3 拘束投票の乗っ取りは繰り返し実証されている

| 事例 | 手口 | 帰結 |
| --- | --- | --- |
| **Beanstalk**（2022-04） | ステーブルコイン等の**預入で投票権を得る設計**を flash loan で突かれ、1 tx で 2/3 超の投票権→即時実行 | **$182M 喪失・崩壊**。以後 on-chain 投票を廃止し Snapshot＋multisig 実行へ移行。「ステーブルコイン預入投票」の最近傍例 |
| MakerDAO（2020-10） | flash loan で MKR を借り oracle whitelist 投票を可決 | 対策として GSM delay を 12h→72h へ延長 |
| Build Finance（2022-02） | 低時価総額トークンの**市場買い集め**で mint 権・国庫を掌握 | 約 $470K 流出。flash loan 対策だけでは防げない実例 |
| Compound Prop 289（2024-07） | 3 ヶ月かけた COMP 買い集めで国庫 5%（$24M）の移転を可決 | snapshot・timelock 装備の大手 DAO でも成立 |

理論面は Vitalik「[Moving beyond coin voting governance](https://vitalik.eth.limo/general/2021/08/16/voting3.html)」(2021) — 借入したトークンの投票者は経済的エクスポージャーを負わない — が標準的参照点。なお「ステーブルコイン自体を拘束力ある投票権に使う」主要プロトコルの先行例は調査で確認できなかった（主要 CDP 発行体は全てガバナンストークンと分離）。**先行例の不在は機会ではなく、上記の構造的理由による意図的な回避**と解するのが妥当。

### 4.4 円金利での定量試算 — fee-share 型 DFT の原資は当面 2〜3 桁不足

日銀政策金利 1.00%（2026-06 利上げ後）の環境では、JPYdf の user-set 金利は「円金利＋リスクプレミアム」（年 1.5〜3% 程度）に収斂すると想定される。このとき:

- 供給 ¥100 億でも、PIL 原資（金利 25%）は **年 ¥3,750 万〜7,500 万**。§4.2 の「価格維持に必要な年 $100M（≒¥150 億）級の実収益」を 2〜3 桁下回る。
- Liquity 自身が bribe 市場成立ラインとした「年 PIL $3.1M」に金利 2% で到達するには、1 USD = 150 JPY の仮定で **`$3.1M × 150 JPY/USD ÷ (2% × 25%) = ¥930 億`**の供給が必要。
- 借入金利と運用益の総額は DFT に使える原資ではない。借入金利の 75% は SP に帰属し、残る収入からも流動性施策・運営・監査・税・安全準備金等を先に控除する。§6 G1 は、この控除後に法的・契約的に DFT 施策へ配分できる NDCF で判定する。
- 例えば供給 ¥300 億・平均金利 2% では借入金利総額は年 ¥6 億だが、SP 帰属分 ¥4.5 億を除くと残りは年 ¥1.5 億であり、他の控除前でも G1 の NDCF ¥5 億に届かない。供給 gate と NDCF gate は独立して判定する。
- 参考: 先行する円建てステーブルコイン JPYC（電子決済手段型）の流通は約 ¥26 億（2026-02 時点）。

すなわち「DFT に fee share / buyback を付ければ価値が付く」は当面成立せず、**JPYdf 供給の成長がすべてに先行する**。

### 4.5 日本の規制・税務論点（公開情報の整理。すべて要法務確認）

- **分水嶺は収益分配**: 収益分配のないガバナンストークンは資金決済法上の暗号資産、収益分配を付すと金商法 2 条 2 項 5 号（集団投資スキーム持分）→電子記録移転権利該当リスク、という整理が金融審 WG 報告（2025-12-10）でも維持。投票権のみの付加が有価証券該当性を生むとの公開見解は確認できず。
- **B 案固有の非対称リスク**: JPYdf 自体に投票権・staking 報酬を付けると、**本体プロダクトの規制区分（暗号資産該当性・SP yield との組合せ評価）の再評価を招く**。DFT 案なら論点を別トークンに隔離できる。失敗時の被害が本体に及ぶ点で B 案は法務面でも劣後。
- **発行時課税と TGE 実務**: 発行対価は権利確定主義で全額一時課税（調達の ~30% が法人税で流出しうる）。期末時価評価課税は令和 5・6 年度改正で大幅緩和済（特定自己発行暗号資産は原価法）。実務は BVI 発行体＋Cayman Foundation＋SG 運営が典型、国内 IEO は 5 例（2024-03 時点・調達数億〜15 億円・審査数ヶ月〜半年）。
- **2026 年制度改正**: 暗号資産規制を金商法へ移管する法案が 2026-04-10 国会提出。発行者が存在する「特定暗号資産」への継続開示・インサイダー規制は、DFT にも暗号資産型ステーブルコインたる JPYdf 自体にも及ぶ見込み。Day-2 の方式決定時に施行状況を再確認する。

---

## 5. 段階導入（推奨パス）

| Step | 内容 | 前提 gate |
| --- | --- | --- |
| **Step 0**（Day-1・現行） | multisig ＋ Timelock ＋ Guardian。トークン・投票なし | — |
| **Step 1**（Day-2 初期） | **非拘束シグナリング**を開始: JPYdf 保有者・SP 預入者・Trove owner の time-weighted snapshot による advisory 投票（T2・T3 スコープ）＋ JPYdf 提案 deposit によるスパム防止。投票結果は JIP の討議 input として扱い、実行は従来どおり JIP 承認 → Timelock。points プログラムで参加を記録 | 追加実装が軽微であること（オフチェーン snapshot ＋ deposit escrow のみ） |
| **Step 2**（Day-2） | T2 スコープの**投票型 allocator**（PILA-GOV-004 の Phase-B）を接続。投票トークンは未確定のまま V2-gov 準拠の time-weighted 設計で実装（DFT 発行時は DFT、未発行なら Step 1 の advisory 集計を admin weight に反映する運用でも可）。変更可能なのは allowlist 済み initiative の weight のみで、epoch cap・送付資産・送付先は変更できない | PIL 原資が配分投票に値する規模（目安: 年 ¥1 億超）に達し、T2 境界を invariant test で証明できること |
| **Step 3**（gate 充足時のみ） | **DFT TGE**: staking / T2 専用 VotingAllocator への拘束投票を接続。fee-share / buyback を採用する場合は、Treasury 権限と分離した固定予算 Distributor を別監査する | §6 の G1〜G5 すべて |

---

## 6. Decision Gates（DFT 発行の前提条件）

G1〜G5 は、すべて**発行前に満たす拘束 gate**である。1 つでも未充足なら default は「発行しない」とし、token contract の deploy、TGE、配布、プロジェクト主導の CEX listing、プロトコルへの権限・経済接続を開始しない。資金調達、投資家コミットメント、ロードマップ上の日付は例外理由にならない。各 gate の証跡と判定は公開 JIP に記録し、[Day-1 policy](../../../launch/gates/Day-1-Governance-Proposal-Execution-Policy.md) の signer-block 承認を経る。

G1 の閾値と算定式は、測定期間の開始前に公開 JIP の activation Decision Record へ freeze する。測定開始後に閾値を変更して同じ期間の判定へ遡及適用してはならない。変更する場合は新しい測定期間を開始する。

| Gate | 内容 |
| --- | --- |
| **G1: 供給・NDCF** | (a) JPYdf の 180 日日次平均供給が ¥300 億以上、(b) 直近 4 四半期の NDCF が各四半期で正、かつ TTM 合計 ¥5 億以上、(c) 月次算定表を公開し、財務記録と照合できること。**NDCF（net discretionary cash flow）** = 実現・回収済みのプロトコル関連収入（金利・運用益等）− SP 帰属分 − 流動性施策 − 運営費 − 監査・セキュリティ費 − 税金 − 法的・契約的な使途制限額 − activation Decision Record で定めた安全準備金積増し。emission / unlock は token 数量と明示した評価価格による JPY 価値を 36 ヶ月分開示し、base / downside の双方で DFT 施策後も安全準備金を割らないこと。「buyback > emission」は単位・価格依存のため単独の合否基準にしない |
| **G2: sequencing** | PMF の確立が TGE に先行していること（points 等で貢献記録は蓄積済み）。「トークンで成長をブートストラップする」目的の発行はしない（先行例は §4.2 のとおりほぼ全敗） |
| **G3: 法務・税務** | 暗号資産該当性・収益分配設計の金商法評価・発行ストラクチャー（国内 IEO / 海外 Foundation）・2026 金商法移管後の開示義務の整理完了（§4.5） |
| **G4: governance safety** | Governor は T2 専用 VotingAllocator にのみ接続し、外部 GOV Timelock の PROPOSER その他の T1 role を持たない。VotingAllocator は allowlist 済み initiative の weight のみ変更可能で、epoch cap・送付資産・送付先を変更できず、Guardian pause と signer-block による recipient 差替を維持する。T1 への拘束力は将来も付与しない（§2） |
| **G5: 実装・監査** | DFT token / staking / Governor と VotingAllocator（PILA-GOV-004 準拠・旧 PILAllocator からの recipient 差替）を別監査する。VotingAllocator は call surface / selector 制限、epoch cap、allowlist、pause、権限分離を invariant test し、1 回の配分による直接損失が 1 epoch の PIL 予算を超えないことを証明する。配分監視と次回配分前の pause / recipient 差替手順を incident runbook で検証する。fee-share / buyback を採用する場合は、Treasury の T1 権限から分離した固定予算 Distributor も別監査する |

---

## 7. 既存ドキュメントへの波及（本書確定後の follow-up。本 PR では変更しない）

| 対象 | 変更方針 |
| --- | --- |
| [PILAllocator](../../../product/spec/PILAllocator.md) PILA-GOV-004 ほか | 「DFT 投票 / DFT staking」→「投票トークン（未確定。DFT 採用時は DFT）」へ表現を改める |
| [Product-Overview](../../../product/Product-Overview.md) §4.1 | 「DFT（将来のガバナンストークン候補）」の記述を本書参照に差し替え（前提化しない表現へ） |
| 投資家向け Overview（Notion）ロードマップ | 「Q4 2026: Governance token TGE・CEX listing」は目標時期であり、§6 の G1〜G5 に従属する。予定時点で未充足なら TGE・プロジェクト主導の listing を延期し、ロードマップを更新する。投資家コミットメントを gate より先に確約しない |

---

## 8. Open Questions

| ID | 未決事項 |
| --- | --- |
| GOV-TKN-TBD-001 | Step 1 シグナリングの投票主体の重み（JPYdf 保有 / SP 預入 / Trove debt の混合比）と snapshot 方式 |
| GOV-TKN-TBD-002 | 提案 deposit の額・slash 条件・返還条件（JPYdf 建て。escrow の実装先） |
| GOV-TKN-TBD-003 | Step 2 を DFT 未発行のまま実装する場合の「advisory 集計 → admin weight 反映」の運用手順と正当性担保 |
| GOV-TKN-TBD-004 | G1 数値（180 日平均供給 ¥300 億・TTM NDCF ¥5 億）と安全準備金の妥当性検証、月次算定表の責任者・財務記録との照合方法、activation Decision Record への freeze 手順 |
| GOV-TKN-TBD-005 | DFT 採用時の voting power 形式（liquid / staked / lock・ve 型）— V2-gov 型 time-weighted を第一候補として比較確定 |
| GOV-TKN-TBD-006 | fee-share / buyback を採用する場合の固定予算 Distributor、予算上限、price guard / clip / pause と Treasury からの権限分離（旧 DFT-TBD-004 を置き換え） |

---

## 9. Non-Goals

- Day-1 launch にトークン issuance / staking / 投票 UI を含めること。
- JPYdf・DFT いずれかを問わず、トークン投票へ T1 権限（upgrade・oracle・writeoff・資金移転）の拘束力を与えること。
- JPYdf を拘束力ある投票権として使うこと（§3.2。deposit・非拘束シグナリングは対象外）。
- JPYdf を protocol reward のために discretionary mint すること。
- tokenomics の配分・価格、具体的な TGE 日付、CEX の選定を本書で確定すること。ただし、これらを実行できるのは §6 の G1〜G5 をすべて満たした後に限る。
