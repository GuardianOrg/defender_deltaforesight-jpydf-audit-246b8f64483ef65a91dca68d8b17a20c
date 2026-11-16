# JPY DeFi Roadmap — 将来施策候補

> **位置づけ**: JPYdf の将来施策候補を、実装着手前の再評価条件とともに管理する社内資料。ここへの掲載は採用・実装・予算・スケジュールの承認を意味しない。

## 1. 目的と正本境界

本書は、現時点では実装しないが、外部環境や事業上の前提が変われば再評価しうる施策を保持する。候補を active backlog と混同しないため、実装 Issue や sub-issue は再評価ゲートを満たしてから作成する。

- active な実装・進捗・依存順序は [Development Plan](../../engineering/plans/Development-Plan.md) が管理する。
- 現行仕様と確定値は [Product Overview](../product/Product-Overview.md)、[Parameters](../../Parameters.md)、各 component spec が正本であり、本書では再掲しない。
- 候補に固有の資料（事業検討・技術設計・調査）は [`initiatives/`](./initiatives/) の施策フォルダが持つ。昇格時は実装計画を `engineering/plans/`、活性化手順を `protocol/operations/runbooks/` へ分離する。本書は採否、観察対象、再評価ゲートだけを持つ。
- 候補を実装対象へ昇格させる場合は、owner・scope・acceptance criteria を確定して Development Plan へ移し、本書には昇格先だけを残す。

## 2. 状態

| 状態 | 意味 |
| --- | --- |
| `Candidate` | 将来候補。調査・観察の開始も未確定 |
| `Observing` | 実装せず、外部実績または事業条件の変化を観察中 |
| `Evaluating` | 再評価トリガー成立後、採否と実装条件を検証中 |
| `Promoted` | 採用承認済み。実装管理を Development Plan へ移管済み |
| `Dropped` | 再評価対象から除外。理由を候補欄へ残す |

`ROADMAP-CAND-*` は候補管理用 ID であり、実装・監査が参照する要件 ID ではない。

## 3. 候補

### `ROADMAP-CAND-001` — Babylon TBV を利用した native BTC 担保

| 項目 | 内容 |
| --- | --- |
| 状態 | `Observing` |
| 判断日 | 2026-07-16 |
| 対象 | Branch 4 `dBTC` の Underlying 候補として Babylon Trustless Bitcoin Vaults（TBV）を利用する |
| 現時点の判断 | JPYdf による TBV 固有レイヤーの自前実装には進まない。Branch 4は [Mainnet Launch Product Decision Record](../launch/decisions/Mainnet-Launch-Product-Decision-Record.md) のinert状態と [Day1 Parameter Manifest](../../Parameters.md) の`mintCap = 0`を維持する |
| 詳細調査 | [BTV Collateral Integration](./initiatives/babylon-btv/BTV-Collateral-Integration.md) |
| 活性化共通ゲート | [Inert Branch Activation Runbook](../operations/runbooks/Inert-Branch-Activation-Runbook.md) |

#### 再評価トリガー

次の両方が成立するまでは `Evaluating` へ移さない。

1. Aave v4 × Babylon TBV が mainnet で稼働し、TVL、清算、WBTC exit、arbitrageur の継続性、cap・pause 運用、インシデント、監査結果を評価できるだけの公開実績が得られる。
2. Aave 側の利用・観察に留まらず、JPYdf が TBV 固有の運用責任と監査範囲を負って自前統合する強い経済的理由が確認される。

#### 再評価時の acceptance criteria

- `dBTC → WBTC` exit について、最大 delay、最大 haircut、即時決済可能量が有界である。
- SP 預入者、償還者、清算実行者が利用できる出口と、流動性不足時の claim 手順が定義されている。
- `mintCap` と WBTC 決済 buffer・回収能力が連動し、cap 引き上げ時にも出口容量が先行して確保される。
- pause 条件、資金不足・arbitrageur 不在・claim 遅延時の recovery、再開条件が定義されている。
- claimer、challenger、arbitrageur の権限、集中リスク、交代可能性、監視責任が定義されている。
- Escrow、oracle / backing、SP・redemption・liquidation との接続、運用手順が外部 audit scope に含まれる。
- 確定 Underlying のリスクが Branch 4 の immutable risk parameters に収まることを、共通 activation gate に従って go / no-go 検証できる。

#### 境界

WBTC、cbBTC、tBTC 等の ERC-20 BTC collateral は、native BTC / TBV とはユーザーニーズ、信頼境界、流動性、運用責任が異なる。BTC exposure を先に検討する場合も、本候補へ統合せず別候補として比較する。

#### 外部一次情報

- [Aave Governance — Babylon Trustless BTC Vault Integration on Aave v4](https://governance.aave.com/t/temp-check-babylon-trustless-btc-vault-integration-on-aave-v4/24964)
- [Babylon Docs — Trustless Bitcoin Vault](https://docs.babylonlabs.io/trustless-bitcoin-vault/start-here/what-is-tbv/)

### `ROADMAP-CAND-002` — ガバナンストークン（DFT 仮称）の発行検討

| 項目 | 内容 |
| --- | --- |
| 状態 | `Observing` |
| 判断日 | 2026-07-16 |
| 対象 | Day-2 以降に、T2 の上限付き PIL 配分へ接続しうるガバナンストークンを発行するか |
| 現時点の判断 | 発行を前提としない。[Governance Token Design](./initiatives/governance-token/Governance-Token-Design.md) §6 の G1〜G5 が 1 つでも未充足の間は、token contract の deploy、TGE、配布、プロジェクト主導の CEX listing、プロトコルへの権限・経済接続を開始しない |
| 詳細設計 | [Governance Token Design](./initiatives/governance-token/Governance-Token-Design.md) |
| PIL 接続境界 | [PILAllocator](../product/spec/PILAllocator.md) `PILA-GOV-004` |

#### 再評価トリガー

次の両方が成立するまでは `Evaluating` へ移さない。

1. Governance Token Design §6 の G1〜G5 をすべて満たす証跡が揃い、公開 JIP に記録される。
2. signer-block 承認を経て、トークン発行の採否を正式に再評価すること自体が承認される。

ロードマップ上の日付、資金調達、投資家コミットメントは再評価トリガーを代替しない。

#### 再評価時の acceptance criteria

- G1 の閾値・算定式を測定期間開始前に公開 JIP の activation Decision Record へ freeze し、測定開始後の遡及変更を認めない。
- Governor の拘束力を T2 専用 VotingAllocator に限定し、外部 GOV Timelock の PROPOSER その他の T1 role を付与しない。
- VotingAllocator が変更できる対象を、確定済みの単一 epoch PIL 予算内における allowlist 済み initiative 間の weight のみに限定する。予算総額、送付資産、送付先 allowlist は変更できない。
- token、staking、Governor、VotingAllocator と、採用する場合の固定予算 Distributor を別監査し、配分上限・pause・recipient 差替を invariant test と incident runbook で検証する。
- 法務・税務、36 ヶ月の tokenomics 感応度、NDCF と安全準備金への影響を公開 JIP で確認できる。

#### 境界

Day-2 の非拘束シグナリングと、投票トークン非依存の PIL Phase-B は、本候補の発行判断に依存しない。必要性と各々の gate が成立した場合は、DFT 発行を待たずに別の実装項目として評価できる。

### `ROADMAP-CAND-003` — dUSD-A / dUSD-B の Underlying 選定

| 項目 | 内容 |
| --- | --- |
| 状態 | `Candidate` |
| 判断日 | 2026-07-20 |
| 対象 | Branch 3 `dUSD-A` / Branch 5 `dUSD-B` の exact Underlying を個別に選定する |
| 現時点の判断 | 両枠は同格の汎用 USD 担保予約枠として inert / `mintCap = 0` を維持する。permissionless / yield-bearing / RWA 等のカテゴリ、優先順位、組み合わせを事前に固定しない |
| 活性化共通ゲート | [Inert Branch Activation Runbook](../operations/runbooks/Inert-Branch-Activation-Runbook.md) |

#### 再評価トリガー

候補資産の borrower demand または提携仮説が具体化し、資産固有の oracle、償還 / exit、流動性、issuer / protocol dependency を一次情報で評価できる時点で `Evaluating` へ移す。

#### 再評価時の acceptance criteria

- on-chain で Core / Vault / SP / liquidator / protocol redemption の全フローが実行可能である。
- market price と canonical rate / NAV、freeze / blacklist / upgrade / custody、withdrawal / settlement delay、secondary liquidity を資産固有に検証できる。
- 確定 Underlying が対象 branch の immutable 値（MCR 120.00% / CCR 137.65% 等）に適合する。
- 両枠の候補が同じカテゴリの場合も、branch-local SP、liquidity、issuer / protocol concentration を個別に承認する。

### `ROADMAP-CAND-004` — dJGB branch の Underlying 選定（トークン化日本国債）

| 項目 | 内容 |
| --- | --- |
| 状態 | `Observing` |
| 判断日 | 2026-07-20 |
| 対象 | Branch 7 `dJGB` の Underlying として Token JGB（トークン化日本国債）を選定する |
| 現時点の判断 | 採用可能な商品は未特定。Branch 7は [Mainnet Launch Product Decision Record](../launch/decisions/Mainnet-Launch-Product-Decision-Record.md) のinert状態と [Day1 Parameter Manifest](../../Parameters.md) のrisk / dToken値を維持する。JGB式を選んだ理由は [Day1 Parameter Decision](../launch/decisions/Day1-Parameter-Decision.md) §2.1が持つ |
| 活性化共通ゲート | [Inert Branch Activation Runbook](../operations/runbooks/Inert-Branch-Activation-Runbook.md) |

#### 再評価トリガー

次の両方が成立するまでは `Evaluating` へ移さない。

1. トークン化 JGB 商品が実際に発行され、発行体・償還スキーム・規制上の位置づけ・オンチェーン流通可否を評価できる情報が揃う。
2. JGB 担保 branch を優先して立ち上げる事業判断が確認される。

#### 再評価時の acceptance criteria

- 発行体・償還性・規制適格性（DeFi 担保としての利用可否を含む）を一次情報で確認できる。
- duration 上限3か月、NAV publication、金利 stress、issuer / custodian、償還 calendar、最低単位、所要時間を確定できる。
- [Collateral Parameter Policy](../product/policies/Collateral-Parameter-Policy.md) §2.2のJPY同通貨modelと整合するoracle / price feed設計を確定できる（FX成分を重複させないJPY/JPY評価、金利・クーポンの扱いを含む）。
- decimals / oracle 合成の扱いが確定している。
- 確定 Underlying のリスクが Branch 7 の immutable risk parameters に収まることを、共通 activation gate に従って go / no-go 検証できる。収まらない場合は redeploy 判断として扱う。

商品組成を能動的に働きかける事業施策は [`ROADMAP-CAND-018`](#roadmap-cand-018--onchain-jgb-トークン化短期国債とjpydf統合) が持つ。

### `ROADMAP-CAND-005` — dJPY branch の Underlying 選定

| 項目 | 内容 |
| --- | --- |
| 状態 | `Candidate` |
| 判断日 | 2026-07-20 |
| 対象 | Branch 6 `dJPY` の Underlying として JPYSC、信託型 JPY stablecoin、tokenized deposit 等の regulated JPY settlement asset を選定する |
| 現時点の判断 | exact asset を binding せず、inert / `mintCap = 0` を維持する。発行残高や価格アンカーの用途だけで担保採用を判断しない |
| 活性化共通ゲート | [Inert Branch Activation Runbook](../operations/runbooks/Inert-Branch-Activation-Runbook.md) |

#### 再評価トリガー

候補資産の発行体 / 取扱事業者が DeFi 担保利用、custody、外部移転、償還、KYC / AML の責任分界を具体的に検証できる時点で `Evaluating` へ移す。

#### 再評価時の acceptance criteria

- issuer-approved かつ full-backed の custody / dToken architecture を確定し、reserve attestation、mint / burn 責任、freeze / allowlist、issuer / bank credit を確認できる。
- normal、銀行休日、settlement 停止、operator 破綻時の delay と、protocol redemption 後に全 receiver が利用できる exit を確定できる。
- SP / liquidation / redistribution / redemption / settlement capacity を実証し、low-SP を前提にしない。
- 確定Underlyingに基づきBranch 6の最終値を審査する。初期値はMCR 105.53% / CCR 107.30%とし、SP清算時の担保補償控除を含めて確認する。

### `ROADMAP-CAND-006` — zJPYdf（統一 yield × 守秘トークン）

| 項目 | 内容 |
| --- | --- |
| 状態 | `Evaluating` |
| 判断日 | 2026-07-17 |
| 対象 | JPYdf の yield 表現と zERC20 連携による守秘表現を、**単一の流通トークン zJPYdf に統一**して実装する（公開 sJPYdf との 2 トークン並立は採らない）。zJPYdf は JPYdf 本体とは異なる任意利用の managed wrapper で、国内 CEX 上場対象ではない。実現バリエーション（増価型 / ¥1 固定 float 型 / ¥1 固定 還元型）の選定を含む |
| 現時点の判断 | 統一トークンを前提条件として採否と実装条件を検証する（Phase 1 は canonical settlement chain の単一 manager、バリエーション選定は Intmax 相互確認・法務評価後。2 層 2 トークン構成は詳細調査 §5-1 のフォールバック）。実装 Issue / sub-issue は昇格ゲート通過後に作成する |
| 経緯 | 2026-07-13 Intmax（zERC20）との協業協議（zJPYdf mint 時の SP 預入による yield 化＋ Revenue Share 座組）を契機に、Epic #563（sJPYdf）/ #566（zERC20 連携）を統合・移管。2026-07-17 founder 方針で 2 層 2 トークン前提から単一トークン前提へ転換 |
| 詳細調査 | [zJPYdf](./initiatives/zjpydf/zJPYdf.md) |

#### 昇格（`Promoted`）ゲート

次のすべてが成立するまで `Promoted` へ移さない。

1. Intmax との技術相互確認が完了し、一次資料で裏取りできる（秘匿範囲・batch teleport の金額秘匿仕様・viewing key / selective disclosure・監査 / 実稼働状況、minter 差替または manager 共同拡張の可否、token owner / upgrade 鍵体制、teleport の supply cap / rate limit 導入余地、BUSL-1.1 ライセンス許諾、wallet / relay UI の表示前提）。
2. 実現バリエーション（増価型 / ¥1 固定 float 型 / 還元型）と θ（SP yield の holder 帰属割合）・par 防衛の要否が確定し、Revenue Share の原資・配分が [Protocol Revenue Allocation Policy](./policies/Protocol-Revenue-Allocation-Policy.md) および法務・税務整理（managed wrapper の AML/CFT、yield との複合 / 純化、Revenue Share の契約形態）と整合する。¥1 固定案は、初期外部 backstop・reserve 目標・SP 配分上限・保守的 NAV・損失吸収順序・recapitalization 不能時の最終処理まで確定する。
3. Phase 1 は canonical settlement chain の単一 manager だけが wrap / unwrap を行い、他チェーンの local minter は 0 address とする。`claimShares = canonicalWrapMint 累計 − canonicalUnwrapBurn 累計` で請求権を会計し、OFT / teleport はこの値を変えないこと、manager 交代時に請求権・資産・queue を欠損なく移行できること、および zJPYdf の unwrap 経路が `DFStabilityPool` の same-block 制約と SP 清算エクスポージャの下で有界であることを設計・invariant test で示せる（buffer / bounded withdrawal queue、¥1 固定案では外部 backstop を含む）。複数チェーンで local wrap / unwrap を提供する場合は、global liability ledger と bridge 障害時の fail-closed policy を別途確定する。
4. 監査 scope（zJPYdf manager ＋ zERC20 token / Verifier integration の activation audit package）と、backing / 即時償還可能額 / queue / （増価型では）rate 整合の invariant、および Verifier 侵害の緩和策（teleport cap 等）が定義される。
5. signer-block 承認を経て採用が承認され、owner・scope・acceptance criteria を確定して Development Plan へ移管する。

#### 境界

- Day-1 mainnet の blocker にしない（Day-1 コア監査 scope 外）。
- 国内 CEX 上場対象は JPYdf であり、zJPYdf の国内 CEX 上場は目指さない。zJPYdf の取扱可否を JPYdf 上場または本候補の昇格条件にしない。
- zJPYdf は任意利用の managed wrapper とし、Core / `JpydfToken` の非 upgrade・非管理の信頼モデルと混同しない。zJPYdf の owner / upgrade / Verifier / Hub / LayerZero リスクを JPYdf 本体へ伝播させない。
- 公開 sJPYdf の単独出荷（＝統一方針の変更・2 トークン化。詳細調査 §5-1 のフォールバック発動を含む）を判断する場合は、本候補内で吸収せず、統一方針の変更として別候補 / 別昇格に切り出す。
- Core / `JpydfToken` の変更、bridge minter 型（`bridgeMint` / `bridgeBurn`）の供給経路は本候補の scope 外（wrapper / escrow 型のみ）。

#### 外部一次情報

- [zERC20 実装リポジトリ（kbizikav/zERC20）](https://github.com/kbizikav/zERC20)
- [zERC20 公式](https://zerc20.io/)
- [Ethereum Magicians — zERC20: Cross-Chain Private ERC-20 Based on ZK Proof-of-Burn](https://ethereum-magicians.org/t/zerc20-cross-chain-private-erc-20-based-on-zk-proof-of-burn/26452)
- [Liquity Blog — sBOLD](https://www.liquity.org/blog/sbold---the-on-chain-defi-savings-account)
- [K3 Capital — sBOLD Docs](https://k3-capital.gitbook.io/sbold)
- Intmax zERC20 の詳細仕様一次資料: 受領待ち（受領後に本欄と詳細調査 doc へ追記）

### `ROADMAP-CAND-007` — トークン化日本株式 × JPYdf

| 項目 | 内容 |
| --- | --- |
| 状態 | `Evaluating` |
| 判断日 | 2026-07-21 |
| 対象 | トークン化日本株式を担保とするJPYdf貸出市場と、JPYdfを入力・受取資産とする同株式の売買・決済を、独立した2つの商品legとして評価する |
| 現時点の判断 | 方向性の評価を継続する。JPYdf建て売買は実ユーティリティを拡大する戦略legであり、USDC routeとのcost比較だけで採否を決めない。発行体、商品形式、chain、需要、供給・MM、法務、収益性が未確定であり、市場開設、bridge、予算、提携、対外公表は未承認 |
| 詳細検討 | [トークン化日本株式 × JPYdf](./initiatives/jpy-stock-tokenization/README.md) |

#### 商品legの昇格ゲート

貸出と売買・決済の各legは、対象legについて次のすべてが成立するまでDevelopment Planへ移さない。

1. 発行体、東京現物・ADR等の商品形式、発行・償還通貨、対象chain、利用可能地域、対象銘柄が一次情報または発行体確認で確定する。
2. 対象legの需要を他方から分けて検証する。売買・決済legではJPYdf支払・受取額、利用者、対応venue、quote・settlement採用範囲を事業KPIとし、実行costは継続運営上の制約として別に確認する。
3. 対象legに必要なJPYdf供給・オン／オフランプ、貸出回収、MM在庫、法定資金・担保の負担主体と退出条件が確定する。
4. oracle、LLTV、cap、株式閉場、清算、depeg、redemptionを含む市場riskが、現地の出口流動性で管理できる。
5. Ethereum mainnet外でのみ成立する場合は、bridge activation、chain別cap・rate limit、現地JPYdf流動性、監査・incident responseを確定する。
6. 発行体・venueのtransfer restriction、日本居住者の利用条件、売買・貸出・MM・OTC・資金運用の法務整理が完了する。
7. 対象legのowner、scope、予算、acceptance criteriaを確定し、signer-block承認を経てDevelopment Planへ移管する。

一方のlegだけを移管した場合、本候補は残るlegの状態と昇格先を記録して`Evaluating`を維持する。両legの採否が確定した時点で、本候補全体を`Promoted`または`Dropped`へ更新する。

#### 境界

- JPYdf mainnetのDay-1 blockerにしない。
- 貸出市場の作成とJPYdf建て売買を一括承認しない。成立したlegだけを個別に昇格できる。
- JPYdf建て売買はAMMだけを意味しない。atomicなUSDC hubによる購入UXを先行可能としつつ、order book、AMM、RFQまたはprimary settlementへJPYdf cash legを組み込むことを戦略目標とする。
- 発行体・venueの許可、利用者適格性、法務を、permissionlessなmarket・poolの作成可能性で代替しない。

### `ROADMAP-CAND-008` — Sunrise を起点とした JPYdf の Solana 展開

| 項目 | 内容 |
| --- | --- |
| 状態 | `Evaluating` |
| 判断日 | 2026-07-21 |
| 対象 | JPYdfトークンのみのSolana展開。Sunriseを含む実行手段、現地流動性、distributionを評価する |
| 現時点の判断 | Sunriseの公開サービスとコール上の提案条件に差があり、書面、供給原資、bridge、需要、予算、契約主体が未確定。提携、発注、loan、bridge activation、市場開設、実装、対外公表はいずれも未承認 |
| 詳細検討 | [Sunriseを起点としたJPYdfのSolana展開](./initiatives/solana-expansion/README.md) |

#### 昇格（`Promoted`）ゲート

1. Sunriseの書面提案を受領し、契約条件、成果物、実行主体が確定する。
2. JPYdfの供給主体、担保、規模、発行金利、返済・退出条件を確定し、既存B/Sとは別の承認済み原資を確保する。
3. Sunriseを使う場合の追加価値を、自力で取得可能なDEX routingと分けて示し、Solana上の需要、必要な板、出口流動性、継続コストを検証する。
4. 採用bridge、canonical supply accounting、cap・rate limit、監視、pause・復旧、Solana固有の監査を [Bridge Minter Activation Gate](../operations/runbooks/Bridge-Minter-Activation-Gate.md) に従って確定する。
5. 契約、無担保与信、法務・税務・会計、予算、custody、signer、incident responseの責任主体を確定する。

#### 境界

- 既存のmultichain pilot順序を本候補だけで上書きせず、Solanaを前倒しする場合は別途承認する。
- コール発言を確定済みの商業条件として扱わず、書面受領前に対外提示しない。
- `ROADMAP-CAND-007`（トークン化日本株式 × JPYdf）は独立施策とし、同施策の供給、需要、提携成立を本候補の前提にしない。

### `ROADMAP-CAND-009` — USDT / XAUT の担保候補としての再評価

| 項目 | 内容 |
| --- | --- |
| 状態 | `Observing` |
| 判断日 | 2026-07-20 |
| 対象 | USDT または XAUT を将来の担保 Underlying 候補として再評価する |
| 現時点の判断 | 8 branch の exact Underlying として予約しない。USDT は dUSD-A / dUSD-B の候補比較、XAUT は branch map 全体と immutable 値に適合する枠が確保できる場合の候補比較として扱う |

#### 再評価トリガー

- borrower demand または提携仮説が具体化し、他候補より branch slot を使う商品価値が確認できる。
- oracle、redemption / exit、secondary liquidity、issuer / custody、freeze / blacklist、Strategy と監査範囲を一次情報で評価できる。
- XAUT では market depeg を担保価値に反映する on-chain PriceFeed と清算流動性を確保できる。

#### 再評価時の acceptance criteria

- 対象 branch の用途と immutable 値に exact asset が適合する。
- [Inert Branch Activation Runbook](../operations/runbooks/Inert-Branch-Activation-Runbook.md) の共通 gate と資産固有 gate を満たす。
- cap、SP / liquidator capacity、monitoring、incident / exit runbook が揃ってから binding する。

### `ROADMAP-CAND-010` — ETH 保有者からの JPYdf 発行戦略

| 項目 | 内容 |
| --- | --- |
| 状態 | `Evaluating` |
| 判断日 | 2026-07-23 |
| 対象 | ETH 保有者を wstETH 保有、ETH 保有、Native Validator 運用の3類型に分け、dETH / dwstETH の5導線で JPYdf 発行へつなぐ。Lido V3 stVault は、自社 Node Operator・運用体制を維持したい Native Validator 運用者（3-B）に限って使う |
| 現時点の判断 | 事業性の評価を継続する。dETHは単純な発行経路、dwstETHはstaking増価を担保価値に残す経路として比較する。stVaultは全体戦略の前提ではなく3-Bの移行手段である。Branch 0 `dwstETH`のDay1 public scopeは [Mainnet Launch Product Decision Record](../launch/decisions/Mainnet-Launch-Product-Decision-Record.md) §1、risk gateは [Day1 Parameter Decision](../launch/decisions/Day1-Parameter-Decision.md) §4が持つ。stVault（3-B）のパートナー事業者、Lidoとの条件、担保の運用先は未確定で、提携、実装、予算、対外公表は未承認 |
| 詳細検討 | [ETH 保有者からの JPYdf 発行戦略](./initiatives/eth-holder-jpydf-strategy/README.md) |

#### 昇格（`Promoted`）ゲート

1. 3-Bを採る場合、パートナーまたは自社のバリデータ事業者が Lido の identified Node Operator として確定し、Node Operator fee、target validator、consolidation・exit の SLA を合意する。
3. 3-Bを採る場合、本構成が Lido の Rewards Share Program 除外条項および infrastructure fee 減免要件に抵触しないことを、Lido へ直接確認して確定する。
4. wstETH/JPY の多段 composite oracle 構成と、市場乖離・出口スリッページのデータが揃い、Branch 0の固定済みimmutable値でactivation可能と判断できる。
5. 3-Bの発行導線を DF 独自のコントラクトで組むか、Lido の DeFi Wrapper の strategy 枠に差し込むかを決める。後者を採る場合は、Trove の清算で顧客の持分が不足したときに損失を同一 pool の他の預入者へ転嫁するか否か (`maxLossSocializationBP` と `LOSS_SOCIALIZER_ROLE` の初期値) を先に確定する。
6. 想定顧客について、円建て支出・負債等の具体的使途、または必要スプレッドを満たす JPYdf の再運用先が成立する見込みを確認する。
7. owner、scope、予算、acceptance criteria を確定し、signer-block 承認を経て Development Plan へ移管する。

#### 境界

- JPYdf mainnet の Day-1 blocker にしない。
- 本候補の掲載はstVault（3-B）の提携・実装・予算・対外公表を承認しない（Branch 0のDay1 public scopeはMainnet Launch Product Decision Record §1の所管）。
- 顧客類型と発行導線は [詳細検討 §2](./initiatives/eth-holder-jpydf-strategy/01_JPYdf-Integration.md#2-eth保有者からの5つの発行導線) を正本とする。stVault を全顧客の前提にせず、3-Bに該当した場合のみ提示する。
- 3-Bは同じ validator pubkeyの継続ではなく、source validatorをexitさせてstVault配下のtarget validatorへ有効残高をconsolidateし、同じ自社Node Operator・運用体制をtarget側で継続する構成として説明する。
- Node Operator の指名可否を機関の一律要件として扱わない。3-Bでは顧客ごとに継続要件を確認する。

### `ROADMAP-CAND-011` — HyperliquidにおけるJPYdfユーティリティとHIP-1 Spot市場

| 項目 | 内容 |
| --- | --- |
| 状態 | `Evaluating` |
| 判断日 | 2026-07-31 |
| 対象 | Hyperliquidで`JPYdf/USDC` HIP-1 spot市場を開設し、Builder codesを利用した自社・提携先の取引導線と、JPYdfの発行・保有・返済・決済につながるユーティリティを構築する |
| 現時点の判断 | HIP-1 listingとBuilder市場を独立した事業legとして評価する。Permissionlessに市場を作れることは需要・流動性・法務・予算の成立を意味せず、auction、bridge activation、MM契約、自社注文UI、Builder fee、campaign、対外公表はいずれも未承認 |
| ユーティリティ | [JPYdfユーティリティとBuilder市場戦略](./initiatives/hyperliquid-expansion/01_JPYdf-Utility-And-Builder-Market-Strategy.md) |
| Spot listing | [HIP-1 Spot上場計画](./initiatives/hyperliquid-expansion/02_HIP-1-Spot-Listing-Plan.md) |

#### HIP-1 Spot listing legの昇格ゲート

1. Ethereum mainnetのJPYdfが安定稼働し、Day-1のactive multichain非採用方針から本施策を開始する承認がある。
2. 10〜15件の需要interview、3件以上のanchor flow、MM自己取引を除く月間想定gross flow、予定MM inventoryに対するcirculating supplyの余力を検証し、数値thresholdをDecision Recordへfreezeする。
3. Primary・backupのMM体制、spread・depth・uptime、JPYdf・USDC inventory、裁定、停止・返還条件をterm sheetで確定する。
4. Exact HIP-1 parameterとbridge構成をtestnetで再現し、[Bridge Minter Activation Gate](../operations/runbooks/Bridge-Minter-Activation-Gate.md)に従ってchain別cap、rate limit、供給会計、pause・recovery、監査を確定する。
5. Deployer、MM、bridge、listing表示、fee share、日本を含む対象地域への提供について法務・税務・会計を整理する。
6. HYPEのauction上限、12か月のdownside budget、MM subsidy停止条件、owner、scope、acceptance criteriaを確定し、signer-block承認を経てDevelopment Planへ移管する。

#### Builder市場legの昇格ゲート

1. 自社または提携先の対象顧客、提供画面、入出金、注文、support、地域制限の責任分界を確定する。
2. Builder codesは共有HyperCore order bookへの注文routingとfee attributionであり、独立order bookまたはJPYdfの証拠金・quote asset化ではないことを表示・契約・KPIに反映する。
3. Builder feeを0で開始する期間、導入判断、上限、利用者への追加価値、deployer feeとの会計を確定する。
4. 日本向けの表示・誘引・注文routing・fee受領を含む事業行為について法律意見を得る。Spot listingだけを先行し、自社注文UIを開始しない選択肢を維持する。
5. Organic order、net JPYdf、repeat率、spread・depth、partner経由比率、獲得費を測る仕組みと、拡大・停止thresholdを確定する。
6. Owner、scope、予算、acceptance criteriaを確定し、signer-block承認を経てDevelopment Planへ移管する。

一方のlegだけを移管した場合、本候補は残るlegの状態と昇格先を記録して`Evaluating`を維持する。両legの採否が確定した時点で、本候補全体を`Promoted`または`Dropped`へ更新する。

#### 境界

- JPYdf mainnetのDay-1 blockerにしない。
- JPYdfは初期市場ではspotのbase assetであり、perps・HIP-3の証拠金またはpermissionless / aligned quote assetとして扱わない。
- Builder codesはHIP-1登録、bridge、流動性を代替せず、それだけで独自の板を作らない。
- Hyperliquid Labs、Wormhole、wallet、MM、listing serviceとの提携・endorsementを、本候補の掲載だけで対外表明しない。
- Permissionless deploymentを、日本または他法域における注文媒介・勧誘・交換・MMの適法性と同一視しない。

### `ROADMAP-CAND-012` — Arcus × JPYdf：日本円証拠金・RWA市場協業

| 項目 | 内容 |
| --- | --- |
| 状態 | `Evaluating` |
| 判断日 | 2026-07-31 |
| 対象 | Arcusにおける日本コホートの需要検証、Robinhood Chain上のJPYdf流動性、上限付きperps証拠金pilotを段階的に評価し、長期的には日本円建てRWA市場へ接続する |
| 現時点の判断 | USDGをArcusの基軸証拠金・損益決済通貨として維持し、JPYdfを追加証拠金候補として評価する。日本コホート施策、Robinhood Chain展開、JPYdf/USDG市場、証拠金採用は独立した段階として個別に承認し、前段の実施だけで後段を確約しない。提携、上場、bridge activation、流動性予算、incentive、実装、対外公表はいずれも未承認 |
| 詳細調査・協業設計 | [Arcus × JPYdf](./initiatives/arcus-partnership/README.md) |

#### 段階ロードマップ

| 段階 | Arcusにとっての価値仮説 | 判断に使うKPI・証跡 | 次段階へ進む条件 |
| --- | --- | --- | --- |
| 1. 日本コホート需要検証 | 日本のRWA traderとfunded accountを獲得し、Stock Token・perpsへの追加需要をArcus側の低い実装負担で検証できる | 対象地域のeligible登録数、funded account、RWA取引量、D30 retention、net JPYdf増加額・lock期間、incentive終了後のorganic比率 | Arcus側の判断者と対象地域を確認し、計測方法、成功・停止thresholdを合意する。perps waitlistが存続する場合のStability Pool連携は時限的な実験手段の1つとして扱う |
| 2. Robinhood Chain市場整備 | Arcusのmulti-asset collateral候補に、USDGと交換可能なJPY資産、継続的な市場価格source、円資本の入口を追加できる | JPYdf/USDGのspread・depth・uptime、oracle可用性、net supply、organic turnover、償還・裁定容量、bridge incident件数 | JPYdf mainnetの監査・稼働実績、bridge安全性、MM・流動性原資、oracle、法務、運用責任が確定し、chain展開を個別承認する |
| 3. 上限付き証拠金pilot | USDG単一担保では獲得できないJPY建て資本を取り込み、multi-currency collateralのrisk modelと追加deposit・取引需要を限定リスクで実証できる | JPYdf担保残高、incremental funded account・取引量・open interest、利用者retention、oracle・liquidation uptime、depeg時の損失、bad debt | Arcusのmulti-asset collateral機能と採用基準が確定し、haircut・cap・oracle・清算・depeg・FX stress・停止条件を共同承認する |
| 4. 日本円RWA市場への拡張 | 日本株等のspot・perps・担保をJPY legと結び、24/7の日本市場という新しい商品面とdistributionを構築できる | 発行体・対象商品、eligible user、JPY settlement量、RWA取引量、貸出・担保需要、MM inventory、継続収益 | `ROADMAP-CAND-007`の該当商品legが独立に昇格し、発行体・商品形式・対象地域・規制・流動性が確定する。証拠金pilotの成否だけでは開始しない |

各KPIの数値threshold、測定期間、MM自己取引・社内残高の除外方法は実施前のDecision Recordでfreezeする。Arcusの追加deposit・取引量と、JPYdfのnet増加・lockを分けて計測し、一方の増加だけで両社の成功と判定しない。

#### 段階別の昇格ゲート

**日本コホート需要検証**

1. Arcusが日本を含む対象地域の利用可否、施策のdecision owner、提供画面・support・データ共有の責任分界を確認する。
2. 対象ユーザー、流入経路、計測期間、anti-gaming条件、成功・停止thresholdを合意する。waitlist連携を使う場合は、実施終了日とfull launch時の終了処理を先に定める。
3. 日本向けの表示・誘引、reward、wallet計測、個人データ共有について法務・税務・privacyを整理する。
4. 実装owner、scope、予算、acceptance criteriaを確定し、signer-block承認を経て必要な実装だけをDevelopment Planへ移管する。

**Robinhood Chain市場整備**

1. Ethereum mainnetのJPYdfが安定稼働し、監査結果、無事故稼働期間、供給規模がchain展開の内部基準を満たす。
2. [Bridge Minter Activation Gate](../operations/runbooks/Bridge-Minter-Activation-Gate.md)に従い、canonical supply accounting、chain別cap・rate limit、pause・recovery、monitoring、incident response、追加audit scopeを確定する。
3. Primary・backupのMM、JPYdf・USDG inventory、spread・depth・uptime、裁定・償還経路、流動性支援の負担主体と停止・返還条件をterm sheetで確定する。
4. Arcusが担保評価に利用できるmarket price sourceについて、通常時・薄商い・depeg時の価格形成、fallback、staleness、操作耐性を検証する。
5. Bridge、DEX pool、MM、incentive、日本を含む対象地域への提供について法務・税務・会計を整理し、owner、scope、予算、acceptance criteriaを確定してsigner-block承認を得る。

**上限付き証拠金pilot**

1. Arcusのmulti-asset collateralが本番利用可能となり、資産選定基準、integration owner、審査・変更手続き、実施時期が書面で確認できる。
2. JPYdfの発行・担保・redemption・全branch共通債務によるbad debt伝播、監査・incident履歴、market liquidityをArcusのrisk reviewへ開示する。
3. USDG建てPnL・fundingに対するJPY/USD変動を含め、通常時、JPY急変、JPYdf depeg、oracle停止、流動性枯渇、bridge停止をstress testし、haircutとglobal / user capを導出する。初期haircut・capを本候補で先に固定しない。
4. Deposit、withdrawal、cross-margin評価、liquidation、insurance / loss処理、pause、cap変更、asset removalまでの運用とincident runbookをArcus側と共同確認する。
5. Pilot期間、KPI、cap据置・引上げ・縮小・終了threshold、利用者告知、support、損失負担、データ共有を合意する。
6. Owner、scope、予算、acceptance criteriaを確定し、Arcus側の採用決定とJPYdf側のsigner-block承認を経てDevelopment Planへ移管する。

一部の段階だけを移管した場合、本候補は残る段階の状態と昇格先を記録して`Evaluating`を維持する。証拠金pilotの継続・cap引上げは初回承認に含めず、実測後に別途判断する。

#### 境界

- JPYdf mainnetのDay-1 blockerにしない。
- USDGを置き換えず、USDG建てPnL・funding・決済を前提に追加証拠金として評価する。
- Waitlist × Stability Pool連携はwaitlist存続中の時限オプションであり、協業全体または証拠金採用の前提にしない。
- PermissionlessなRobinhood Chain deployを、Arcusの担保採用、Robinhood・Paxosの支援、対象地域での適法性と同一視しない。
- USD/JPY perp市場の独立提案と、USDGのJPYdf担保追加は本候補に含めない。
- Arcus、Robinhood、Paxos、Stock Token発行体との提携・endorsementを、本候補の掲載だけで対外表明しない。

### `ROADMAP-CAND-013` — JPYdf固定利回り受け皿と貸出市場基盤

| 項目 | 内容 |
| --- | --- |
| 状態 | `Evaluating` |
| 判断日 | 2026-08-04 |
| 対象 | Ethereum上のJPYdf建てMorpho isolated市場の開設基盤 (oracle・curator・供給設計) と、その上のアンダーライト固定型受け皿vault、受け皿シェア担保のUSDC市場を評価する |
| 現時点の判断 | 掲載は市場開設・vault組成・掲示レート・curator起用・予算の承認を意味しない。掲示レートの原資は担保運用益の用途配分 ([Protocol-Revenue-Allocation-Policy](./policies/Protocol-Revenue-Allocation-Policy.md)) と一体で設計し、掲示レート自体の確定手続は本initiativeの未決事項である |
| 詳細検討 | [JPYdf固定利回り受け皿と貸出市場基盤](./initiatives/fixed-rate-sink/README.md) |

### `ROADMAP-CAND-014` — HashPort Wallet統合 (取得退出導線・ramp・Earn)

| 項目 | 内容 |
| --- | --- |
| 状態 | `Evaluating` |
| 判断日 | 2026-08-04 |
| 対象 | HashPort Walletに、JPYCの発行・償還導線を部品として使うJPYdfの取得・退出導線、JPYC/JPYdf poolによる円の間接on/off ramp、IPOR Fusion上のvault群を裏側とするEarn tabを統合する |
| 現時点の判断 | HashPortはDFの投資家であり接点は実在するが、統合の協議・合意は未着手。掲載は提携・実装・費用負担の承認を意味しない |
| 詳細 | [HashPort統合](./initiatives/hashport-wallet-integration/01_HashPort-Integration.md) |

### `ROADMAP-CAND-015` — stablecoinカードのJPYdf対応

| 項目 | 内容 |
| --- | --- |
| 状態 | `Observing` |
| 判断日 | 2026-08-04 |
| 対象 | 国内BINスポンサー付きstablecoinカード (Slash Card等) の利用者残高の対応通貨にJPYdfを追加し、決済用に滞留する円建て残高へ利回りを付ける |
| 現時点の判断 | 加盟店側の変更は不要で、営業対象はprogram manager / カード発行会社に限られる。掲載は提携・実装の承認を意味しない。残高利回りの訴求は受け皿vault (`ROADMAP-CAND-013`) の稼働に依存する |
| 詳細 | [カード残高統合](./initiatives/stablecoin-card-integration/01_Card-Balance-Integration.md) |

### `ROADMAP-CAND-018` — onchain JGB (トークン化短期国債とJPYdf統合)

| 項目 | 内容 |
| --- | --- |
| 状態 | `Evaluating` |
| 判断日 | 2026-08-04 |
| 対象 | JGB裏付けのNAV増価型トークンを、DeltaForesightが商品スポンサーとして自社主導で発行するか、既存の発行基盤・運用会社と共同組成し、JPYdf建てのMorpho isolated市場 (同通貨担保) を開設する。[`ROADMAP-CAND-004`](#roadmap-cand-004--djgb-branch-の-underlying-選定トークン化日本国債) の再評価トリガー1 (商品の実在) を自ら満たしに行く事業施策として位置づける |
| 現時点の判断 | JPY建ての短期金利トークンは現存せず、Progmat陣営の組成が進む2026年内に判断窓が閉じる (検証済み事実は詳細検討READMEに従う)。自社主導発行と既存基盤との共同組成を並行比較し、成功定義は外部Morpho市場の成立に置く。Branch 7の活性化は含めない。掲載は発行スキームの選定、法人・ファンド設立、発行体協業、市場開設、予算の承認を意味しない |
| 詳細検討 | [onchain JGB](./initiatives/jgb-tokenization/README.md) |

### `ROADMAP-CAND-019` — IPOR Fusion協業 (JPYdf vault製品ライン)

| 項目 | 内容 |
| --- | --- |
| 状態 | `Evaluating` |
| 判断日 | 2026-08-04 |
| 対象 | IPOR Fusionを基盤とするJPYdf建てvault製品ライン (SP預入vault、Liquity fuse差し替えキャリーvault、日本株ベーシスvault、受け皿vaultのFusion実装可否) と、IPOR側との協業条件を管理する |
| 現時点の判断 | IPOR founderとの協議進行中 (2026-08-05コール)。掲載は協業合意・vault組成・seed・feeの承認を意味しない |
| 詳細検討 | [IPOR Fusion協業](./initiatives/ipor-fusion-collaboration/README.md) |
