# 自己 B/S による Day-1 初期流動性の算定根拠

| 項目 | 内容 |
| --- | --- |
| Status | Active |
| 役割 | 自己 B/S 配分、SP seed、bootstrap Trove rate の算定根拠・比較・棄却理由 |
| 会社採用値 | [`Day1-Self-BS-Launch-Commitment.md`](./Day1-Self-BS-Launch-Commitment.md) |
| Product requirement | [`Mainnet-Launch-Product-Decision-Record.md`](../../../protocol/launch/decisions/Mainnet-Launch-Product-Decision-Record.md) |
| 対象外 | Gate、実行手順、証跡、現在の実装状況 |

対象は自己資金由来の DEX LP seed と事前 SP 預入であり、ユーザー deposit 由来の Vault buffer / Strategy 運用は扱わない。

B/S bucket は [`Balance-Sheet-Liquidity-Allocation-Policy.md`](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md)、清算 backstop / JIT の境界は [`Liquidation-Backstop-And-JIT-Policy.md`](../../../protocol/operations/policies/Liquidation-Backstop-And-JIT-Policy.md)、DEX route は [`Liquidity-Route-Policy.md`](../../../protocol/product/policies/Liquidity-Route-Policy.md)、担保 parameter は [`../../Parameters.md`](../../../Parameters.md) を正本とする。

## 1. 算定制約

- 自己 B/S の現金支出は 1.5 億円以内。
- JPYdf/USDC の初期 DEX 流動性を優先し、SP をゼロにはしない。
- inert branch には自己資金を配分しない。
- LP seed、SP seed、backstop、Vault buffer、Treasury 留保を二重計上しない。
- 大口 dwstETH borrower の redemption risk を下げるが、第三者 redemption の除外や回避を保証しない。

この制約に対し、DEX 重視案と dwstETH 側の redemption buffer を組み合わせた。会社の採用額は
Self-B/S Launch Commitment、product requirement は Product Decision Record、比較過程は §3 に示す。

## 2. Borrow APR / Bootstrap Trove の算定

Day-1 の borrow APR は、public UI 上で固定の「推奨利率」を protocol promise として強く出すのではなく、Automatic / Operator-managed を標準導線とする。ここでいう Automatic / Operator-managed は UI 上の delegate 選択、operator policy、launch evidence の導線であり、#570 の fully automated rate-management bot や自動 rate tx を Day-1 前提にする意味ではない。会社 bootstrap Trove の初期 rate、管理レンジ、変更条件は launch operation evidence で freeze する。

Day-1 の business target は、ETH borrower / DAT が **USD stablecoin を直接借りるより低い APR で JPYdf を借りられる** ことを優先する。JPY と USD の金利差をオンチェーンで取り込み、ETH collateral → JPYdf borrow → USDC swap の JPY-funded carry trade を成立させることが borrower acquisition の中核仮説である。したがって dwstETH / wstETH の通常時 target APR は、wstETH 価格変動 risk premium を厚く乗せることから始めず、**2.0% を business target upper bound** とする。

会社 bootstrap dUSDC / dwstETH Trove の rate は、外部 USD DeFi 利回りから大まかに決めるのではなく、borrower 側の低コスト仮説と SP depositor 側の JPY 建て利回りを両立する水準から逆算する。短期 JPY の参考利回りは即時引き出し性を考慮して短期国債側に寄せ、2026-06-25 時点の参考値では 6 ヶ月 JGB が約 1.0%、2 年が約 1.4%、10 年が約 2.7% である。JPYdf SP はスマートコントラクト、流動性、オラクル、redemption / liquidation 運用のリスクを持つため、短期 JPY 基準利回りに DeFi risk premium を乗せた **SP 目標利回り**を確認するが、SP APR を高く見せるために通常時 borrow APR を引き上げない。

算式:

`borrow APR = target SP APR × target SP coverage / SP_YIELD_SPLIT`

ここで `SP_YIELD_SPLIT = 75%`、`target SP coverage = SP deposits / branch debt` とする。算定時の USDC branch scenario では、branch debt 1 億円（self-mint 6,958 万 + 仮定上の外部 debt 3,042 万）に対し、自社 SP 833 万 + 外部 / campaign SP 約 2,917 万を目標 coverage と置くと `target SP coverage = 37.5%`。短期 JPY 1.0% + DeFi risk premium 3.0% = `target SP APR 4.0%` と置く場合、bootstrap borrow APR は `4.0% × 37.5% / 75% = 2.0%` となる。

dwstETH branch の算定 scenario は `plannedDebtJpydf = 35 百万円`、`targetSpJpydf = 1,595 万` で、coverage は約 45.6% である。2.0% borrow APR の interest-only SP gross APR は `2.0% × 75% / 45.6% ≒ 3.3%` となり、dUSDC の 4.0% scenario より低い。これは dwstETH SP を A 社想定 borrow / wstETH 急落 / 25% event の safety buffer として厚く置くためであり、SP APR の見栄えを優先して dwstETH borrow APR を 4%+ に引き上げる理由にはしない。実際の SP APR は actual branch debt、SP deposit、upfront fee、liquidation gain、SP deposit の入出金で変わるため、UI では保証利回りとして扱わない。

本節の外部 debt / headroom は rate と stress を比較した算定入力であり、現在の実行可能な借入余力ではない。
freeze block の capacity は Product Decision Record §2.2 と Launch Gate の evidence に従って別途算定する。

Borrow APR は単なる資金コストではなく、redemption 順位を決める値である。Liquity v2 型では低金利 Trove から redemption され、同率では後から設定した Trove が先に redemption される。したがって bootstrap Trove の rate は、LP / SP seed の調達コストだけでなく、会社 self-mint をユーザー Trove より先に消化されやすい位置へ置く会計判断でもある。Day-1 は「可能な限り安く借りたいが redemption は受けたくない」一般 borrower の前に、会社 bootstrap Trove を低 rate で置く方針とする。

rate を上げる判断材料は、JPYdf/USDC の下方向乖離、redemption fee / base rate、debt-in-front、SP coverage、wstETH 急落、清算候補、LP depth とした。低下方向は borrow demand、上方向乖離、redemption の沈静化、SP / LP の改善を見る。通常 target から risk-mode upper range へ一度に移さず、borrower demand / peg / redemption / SP coverage の state を evidence 化し、Product Decision Record の条件を満たす場合だけ段階的に調整する。一般 borrower の business target / risk-mode range は Product Decision Record、会社 bootstrap Trove の anchor・管理レンジ・Trove 数は Self-B/S Launch Commitment に置き、本書では再掲しない。

## 3. 比較と棄却理由

### SP / DEX 配分 4 案

下表は 3 active branch・各 branch 1 億円 cap を仮定した当時の比較であり、現在の launch config ではない。DEX 重視案は peg 防御と SP ゼロ回避の均衡から採用し、現在の product requirement と会社コミットメントはそれぞれの正本へ移した。

| | A. SP 重視 | B. バランス | **C. DEX 重視（採用）** | D. 100% DEX |
| --- | --- | --- | --- | --- |
| DEX LP（JPYdf / USDC） | 6,000 万円 | 8,000 万円 | **1 億円** | 1.286 億円 |
| SP per branch | 2,000 万円 | 1,420 万円 | **833 万円** | 0 |
| SP 合計 | 6,000 万円 | 4,250 万円 | **2,500 万円** | 0 |
| Operator self-mint 合計 | 9,000 万円 | 8,250 万円 | **7,500 万円** | 6,430 万円 |
| Operator self-mint / stable branch | 4,500 万円 | 4,125 万円 | **3,750 万円** | 3,215 万円 |
| SP 単独完結 清算 size 上限 | ≤ 2,000 万円 | ≤ 1,420 万円 | **≤ 833 万円** | 0 |
| SP 単独完結 清算割合（※） | ~95% | ~90% | **~80%** | 0% |
| operator JIT capacity（※2） | 2,860 万円 | 3,800 万円 | **4,760 万円** | 6,120 万円 |
| SP + JIT 合計 capacity / branch（※2） | 4,860 万円 | 5,220 万円 | **5,590 万円** | 6,120 万円 |
| 25% event（2,500 万円）吸収余裕 | 1.94 倍 | 2.09 倍 | **2.24 倍** | 2.45 倍 |
| Swap: peg ±0.5% 動かす size | 300 万円（$19k） | 400 万円（$25k） | **500 万円（$31k）** | 640 万円（$40k） |
| Swap: peg ±1% 動かす size | 600 万円（$38k） | 800 万円（$50k） | **1,000 万円（$63k）** | 1,280 万円（$80k） |

※ Liquity v2 mainnet WETH branch の ブランチ debt に対する 清算 size 分布（比率ベース）を JPYdf に当てはめた推定値。 DEX LP は ±5% concentrated を仮定（採用 range は 別途議論）。

※2 「operator JIT capacity」「SP + JIT capacity」は **運用 planning capacity であり、コントラクト保証ではない**（JPYdf 調達は DEX 深度・在庫に律速し、Atomic JIT executor は Day-1 未実装）。用語・境界は [`Liquidation-Backstop-And-JIT-Policy.md`](../../../protocol/operations/policies/Liquidation-Backstop-And-JIT-Policy.md) を正本とする。

### 配分判断の 基本観点

- DEX 流動性を増やせば peg 維持 + JIT 清算条件改善の両面に寄与する。
- ただし SP ゼロにすると JIT bot 障害時 全清算が redistribute に流れ、 user UX が悪化する。
- 「基本的な清算は SP cover、 大口のみ JIT、 運営がカバーできなくなって初めて redistribute」 が望ましい。

### 各 case の特徴

- **A. SP 重視**: SP 厚で 9 割超清算が SP 単独完結、 ただし DEX 薄で 大口 swap で peg 動きやすい
- **B. バランス**: 9 割の清算 SP 単独完結 + peg ±0.5% を $25k swap まで防御
- **C. DEX 重視（採用）**: Peg 防御強化、 SP 80% カバー、 中口は JIT 依存
- **D. 100% DEX**: Peg 防御最強、 SP ゼロで JIT bot 障害時 全清算 redistribute → UX 悪化 risk

### Liquity v2 mainnet 実測 ratio

Liquity v2 BOLD 1 年運用実績（2026-06 時点）:

| Branch | TVL | SP balance | 推定 debt | SP / debt | 単発 max trove / debt | 単発 max trove（実額） |
| --- | --- | --- | --- | --- | --- | --- |
| WETH | $23M | $6.0M | ~$9M | 67% | 3.2% | $285k |
| wstETH | $118M | $8.7M | ~$13M | 67% | 22.8% | $2.97M |
| rETH | $22M | $5.2M | ~$8M | 65% | 0.4% | $30k |

**観察**:
- 1 年で liquidation event 63 件。
- ただし Liquity v2 は organic SP 預金者多数で SP/debt 67% を維持。 DeltaForesight launch 直後（organic SP 預金者ゼロ）と単純比較は不可。

### 清算 size 分布（Liquity v2 WETH branch、 1 年実績）

| percentile | 清算 size（USD） | branch debt 比 |
| --- | --- | --- |
| p50（median） | $7.6k | 0.085% |
| p75 | $34k | 0.4% |
| p90 | $91k | 1.0% |
| p95 | $130k | 1.45% |
| max | $285k | 3.2% |

→ 比較時の外部 debt 仮定（dwstETH 約 30.3 百万円、dUSDC 約 30.4 百万円）に比率ベースで当てはめると、9 割の清算が 30 万円程度、max event は 100 万円弱。dUSDC branch 全体 1 億円（self-mint 6,958 万円込み）を分母に置く保守比較では、9 割の清算が 100 万円以下、max event は 320 万円程度。

### 25% event 想定の計算

以下の比較 scenario では、外部 debt を dwstETH = 約 3,030 万円（= A 社想定）、dUSDC = 約 3,042 万円（うち launch planning room は 2,500 万円）と仮定する。Day-1 運用 event としては、1 trove / cluster が仮定上の外部 debt の 25% を占める case を見る。dUSDC の self-mint 込み branch debt 1 億円に対する 25%（2,500 万円）は、branch-wide stress として別管理する。

- Liquity v2 wstETH の単発 max は branch debt の 22.8% で、 「25%」 は 1 段保守的。
- dUSDC: launch planning room 25% event ≈ 625 万円。仮定上の外部 debt 全体でも 25% event ≈ 761 万円で、事前 SP 833 万円で単独完結可能。
- dwstETH: 仮定上の外部 debt 25% event ≈ 758 万円。事前 SP 1,595 万円で単独完結可能。

### A 社対応のための追加検討（Pattern A〜E、 採用 Pattern D）

日系 DAT 企業 A 社が Day-1 から dwstETH branch を利用する想定（3,000 万 JPYdf borrow）を受け、 A 社 Trove が redemption 対象になる確率と影響を下げる配分を追加検討した。

**設計方針**（以下を優先しつつ、 A 社 Trove redemption 対象化の確率と影響を下げる）:

1. DEX 流動性 1 億円維持（peg 防御 最優先、 上記「SP / DEX 配分 4 案」採用案 C と整合）
2. SP per branch 833 万円 floor 維持（清算を SP で捌けるライン、 採用案 C と整合）
3. 自社 B/S 1.5 億円維持（運営予算上限）

**想定 redemption 規模**: Liquity v2 BOLD mainnet 13 ヶ月実測（2025-05 〜 2026-06、 Dune Analytics）から protocol-wide total debt 比で算出した N 日累積 worst を採用。conservative case として **Scenario A**（= 一般 user の dUSDC launch planning room 2,500 万円が 100% SP に deposit される想定、dUSDC SP state = 833 + 2,500 = 3,333 万円）で計算。仮定した dUSDC 外部 debt の残余 542 万円はこの Scenario A の demand / SP 前提に含めない。

**Issue #558 との境界**: 本節は `redemption risk reduction / exposure preservation support` のための B/S 配分であり、第三者 redemption の絶対回避ではない。DF は特定ユーザーを Core redemption path から除外せず、permissionless redemption を止めない。この配分は redemption の確率・影響を下げる buffer であって、monitoring / alert / 復元の best-effort 性、Day-1 commitment の範囲（専用 dashboard / alert / report を約束するなら別ゲート）、執行（返済・ETH delta 復元・rehedge・buyback・Trove 再構築＝Allied 側 treasury operation）、および DF が復元・代行する場合の separate managed service / legal / audit gate といった運用境界は [`Redemption-Risk-Monitoring-Runbook.md`](../operations/Redemption-Risk-Monitoring-Runbook.md) §0・§6 を正とする。

**5 Pattern 比較**（全 Pattern とも上記「設計方針」の 3 制約を維持）:

| 項目 | A (1 日) | B (3 日) | C (7 日) | **D (10 日、 採用)** | E (14 日) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 想定 redemption（= total debt 比 %） | 4% | 8% | 14% | **15.3%** | 19% |
| 想定 redemption 量（万円） | 524 | 1,058 | 1,876 | **2,061** | 2,594 |
| 自社 dwstETH self-mint（万円） | 95 | 220 | 400 | **470** | 650 |
| 自社 ETH 担保（万円） | 146 | 338 | 615 | **723** | 1,000 |
| 自社 dUSDC self-mint（万円） | 7,391 | 7,247 | 7,039 | **6,958** | 6,750 |
| 自社 USDC 担保（万円） | 9,854 | 9,662 | 9,385 | **9,277** | 9,000 |
| DEX LP（万円） | 10,000 | 10,000 | 10,000 | **10,000** | 10,000 |
| dwstETH SP（万円） | 1,653 | 1,634 | 1,606 | **1,595** | 1,567 |
| dUSDC SP 自社拠出（万円、 floor） | 833 | 833 | 833 | **833** | 833 |
| Scenario 上、A 社到達前に DF 側 buffer が先に消化される推定 redemption 規模（万円） | 534 | 1,146 | 1,887 | **2,146** | 2,727 |
| B/S 合計（万円） | 15,000 | 15,000 | 15,000 | **15,000** | 15,000 |
| dwstETH mintCap（= 自社 + A 社 + 100 万切上げ、 万円） | 3,100 | 3,300 | 3,400 | **3,500** | 3,700 |

※ ETH 担保額は ETH 価格 ¥600k 想定の円建て。redemption 規模は protocol-wide total debt 比、Scenario A 想定（一般 user の dUSDC launch planning room 2,500 万円が SP に 100% deposit）。dUSDC SP の state 値は自社拠出 833 + 一般 user 想定 2,500 = 3,333 万円。仮定した dUSDC 外部 debt の残余 542 万円は、この比較表では追加 campaign 余地として扱わない。

**採用 Pattern D の根拠**:

- Scenario A の前提では、Liquity v2 BOLD mainnet 13 ヶ月実測の 10 日累積 worst redemption 規模に対して、A 社 Trove へ到達する前に DF 側 dwstETH bootstrap Trove が先に消化される見込みとなる。
- ETH 価格 risk は 723 万円（= 約 12 ETH @¥600k） に限定。承認済みの初期seedはヘッジせず保有し、ヘッジをDay-1 / audit前のblockerにしない。市場リスクとヘッジの判断基準は[`Balance-Sheet-Liquidity-Allocation-Policy.md`](../policies/Balance-Sheet-Liquidity-Allocation-Policy.md) §4を正とする。

## 参考

- [`Balance-Sheet-Liquidity-Allocation-Policy.md`](../policies/Balance-Sheet-Liquidity-Allocation-Policy.md) — DeltaForesight B/Sのbucket分類・判断境界の正本
- [`Liquidation-Backstop-And-JIT-Policy.md`](../../../protocol/operations/policies/Liquidation-Backstop-And-JIT-Policy.md) — SP / backstop / JIT の用語・境界の正本
- [`Liquidity-Route-Policy.md`](../../../protocol/product/policies/Liquidity-Route-Policy.md) — DEX route policy（JPYdf/USDC・Uniswap v4）
- [`../../Parameters.md`](../../../Parameters.md) — 担保 / parameter（mintCap 等）の正本
- Liquity v2 BOLD mainnet 実測データ（Dune Analytics、 2026-06 取得）
- [Liquity v2 Redemptions and Delegation](https://docs.liquity.org/v2-faq/redemptions-and-delegation) — redemption order / interest delegation の仕様確認
- [Liquity v2 Borrowing and Multiply](https://docs.liquity.org/v2-faq/borrowing-and-liquidations) — user-set interest rate / multiple Troves / upfront fee の仕様確認
- [DeFiLlama yields API](https://yields.llama.fi/pools) — 2026-06-24 市場利回り snapshot の参照元
