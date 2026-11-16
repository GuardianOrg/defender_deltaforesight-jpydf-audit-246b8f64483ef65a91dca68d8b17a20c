# 担保パラメータ算定根拠 — 2026-07-27 Historical Snapshot

> Domain: Protocol
>
> Lifecycle: Historical
>
> Artifact Type: Decision Record
>
> Decision Authority: Protocol Governance
>
> Maintainer: DeltaForesight (Contributor)
>
> Status: Historical
>
> Snapshot Date: 2026-07-27
>
> Normative Source: [Parameter Catalog](../../protocol/product/parameters/Parameter-Catalog.md) / [Collateral Parameter Policy](../../protocol/product/policies/Collateral-Parameter-Policy.md) / [Day1 Parameter Decision](../../protocol/launch/decisions/Day1-Parameter-Decision.md) / [Day1 Parameter Manifest](../../Parameters.md)

本書は、旧Notionのparameterページ群と後続の追加検討を統合した、変数model、生データ、棄却案、旧branch候補の履歴snapshotである。現在の値、選定基準またはDay1判断の正本ではなく、今後の判断に合わせて更新しない。本文中の「現行」「確定」は各注記を追加した時点を指し、現在の`develop`を意味しない。

- **旧Notion source**: 親「担保資産及びパラメーターの設定」／子「Liquidation LTV」「パラメータ検討メモ」／孫「JGB トークンブランチの LLTV 設定」「最低金利に関する議論メモ_20260610」。Notion側は廃止済み。
- **算定スプレッドシート**: `LLTV_DeltaForesight_20260111`（社内Google Sheets）。同sheetのstable系一般式は後続判断で置換され、最終一致するのはWBTC / WETHのみ。
- **上流制約**: [liquity/bold README](https://github.com/liquity/bold/blob/main/README.md#liquidation-penalties-and-borrowers-collateral-surplus)

---

## §0. 現行確定値との差分（重要）

本書執筆後、ステーブル系ブランチは一度 **Day-1 immutable risk policy floor** で一律に引き締める案が採られたが、最終方針では plain stable と structured / RWA stable を分離した。USDC / USDT は構造が単純な plain stable として stress-implied 値を現行確定値に戻し、sUSDS（USDS depeg に加え ERC-4626 share / PSM / withdrawal / oracle 構成リスクを持つ yield-stable）と dUSD（RWA 系）は構造リスク例外として MCR 120% floor を適用する。算定式は次の扱いに整理された:

`USDC / USDT LLTV = (1 − 最大 DD)(1 − FX)`

`sUSDS / dUSD LLTV = min((1 − 最大 DD)(1 − FX), 1 / 1.20)`

| 担保 | 本書の検討時点の値（LLTV / MCR / CCR） | **現行 Parameters.md の確定値** | 差分の理由 |
| --- | --- | --- | --- |
| USDC（Br1） | 89.62% / 111.58% / 124.50% | **89.62% / 111.58% / 124.50%** | plain stable として stress-implied 値を採用 |
| USDT（Br2） | 89.62% / 111.58% / 124.50% | **89.62% / 111.58% / 124.50%** | = USDC |
| sUSDS（Br3） | 87.18% / 114.71% / 131.58% | **83.33% / 120.00% / 137.65%** | policy floor MCR 120%（USDS depeg + ERC-4626/PSM/withdrawal/oracle 複合リスク） |
| WETH（Br0） | 83.91% / 119.18% / 132.61% | 83.91% / 119.18% / 132.61%（不変） | — |
| XAUT（Br4） | 77.52% / 129.00% / 152.93% | 77.52% / 129.00% / 152.93%（不変） | — |
| dBTC（Br5） | 83.65% / 119.55% / 130.82% | 83.65% / 119.55% / 130.82%（不変） | — |
| dUSD（Br6, USDe暫定） | 86.30% / 115.87% / 134.26% | **83.33% / 120.00% / 137.65%** | policy floor MCR 120%（RWA structured stable。CCR は sUSDS と同じ max DD 11.79% 基準で再算定） |
| dJPY（Br7） | 94.97% / 105.30% / 107.30% | 94.97% / 105.30% / 107.30%（不変） | — |

> 以降の §D / §E に出てくる USDC / USDT の値は注記追加時点の確定値と一致する。sUSDS / dUSD の値は**検討時点の stress-implied 値**であり、注記追加時点の確定値ではない（sUSDS は stress-implied、dUSD は旧 USDe-proxy placeholder）。

---

## §A. 設計思想（共通原理）

### §A-1. 問題設定

LLTV / MCR 設定の問題を「**資本効率を損なわない範囲で、清算が安全に行われる（プロトコルが Bad Debt を抱えない）値を求める**」と定義する。

- Liquidator は収益が見込めれば清算を実行するが、以下のように収益期待値が低い状況では実行されず、プロトコルが Bad Debt を抱えるリスクがある。
  - 担保資産価格が極めて速い速度で下落。
  - LTV が清算閾値を突破しているがオラクルが更新されない。
  - 清算後の売却ルートでスリッページ・ガス代高騰により採算が合わない。
- LLTV 設定の考え方: 清算ペナルティとして得られる収益から、ガス代・スリッページ等を差し引いて残る収益が、特定期間内に担保資産価格が Loan Asset（JPY）に対して下落しても清算が実行される、というラインを見つける。

### §A-2. Bad Debt を出さないという絶対条件

ここで **Bad Debt = 清算しても担保で負債を回収し切れない状態（担保価値 < 負債）**。これを出さないことが設計の絶対条件。

清算は即時に成立するとは限らず、(a) 価格急落、(b) オラクル未更新、(c) スリッページ・ガス高騰による採算割れ で遅延・不成立になりうる。そこで清算閾値ちょうどのポジション（オラクル価格で 担保価値 = MCR × 負債）が、**清算完了までの想定時間（オラクル更新間隔を踏まえ 2h を基本に想定）に複合ストレスで目減りしても、なお過剰担保（担保価値 ≥ 負債）を保つ**水準に MCR を置く。

目減りは単一の価格下落では捉えきれず、**価格変動・depeg・DEX スリッページ（ストレス時は流動性枯渇で平時の数倍）・円高方向の FX** が掛け合わさって効く（残存率の積）。

### §A-3. 清算方式の前提（ICR > 105% フロア）

- Liquity v2 の清算方式は、最優先が Stability Pool、空なら JIT 清算。清算実行者には担保の 0.5%（上限 1,000 単位）が担保補償として支払われる（`COLL_GAS_COMPENSATION`）。
- ICR > 105% であれば、SP・JIT いずれでも清算が確実に実行されるため、保守的にこのラインを上回る MCR / LLTV 設計を志向する。
- USD ステーブル系はこの 105% を安全条件には含めず過剰担保ギリギリを狙うが、結果的に全ブランチの MCR はこのラインを上回り、清算機構が機能する範囲に収まる（最小は JPY ブランチ 105.30%）。

### §A-4. 算式は担保タイプで 2 系統（＋ JGB 特殊形）

| 系統 | 対象 | ストレス後に守る水準 | 確定式（検討時点） |
| --- | --- | --- | --- |
| 高ボラ系 | WETH / WBTC / XAUT | 担保 ≥ 負債 ＋ 清算ペナルティ（＋スリッページ） | `MCR = (1 + SP) / [(1 − Price)(1 − Depeg)(1 − Slip × Mult)(1 − FX)]` |
| USD ステーブル系 | USDC / USDT / sUSDS / dUSD | 担保 ≥ 負債（過剰担保を維持） | USDC / USDT: `LLTV = (1 − 最大 DD)(1 − FX)`、sUSDS / dUSD: `min((1 − 最大 DD)(1 − FX), 1 / 1.20)`（SP・スリッページを含めない） |
| JGB 系 | dJPY | 担保 ≥ 負債 ＋ 清算ペナルティ | `MCR = (1 + SP) / (1 − Price)`（§E-9） |

- **高ボラ系**は DEX 売却を伴うため、清算ペナルティ（SP = 5%）とスリッページを式に含め、2h で 1000 回に 1 回級の価格急落と円高が同時に起きても Bad Debt が生じない水準を満たす。
- **USD ステーブル系**は、清算ペナルティ・スリッページを buffer に含めず、過去最大級の depeg が起きても過剰担保を保つところまで LLTV を高くとる（理由: 平時ボラが低い／清算が主に SP の現物吸収で成立し DEX 売却スリッページを負わない）。現行 Day-1 では USDC / USDT はこの stress-implied 値を採用し、sUSDS（yield-stable）/ dUSD（RWA）は非価格・exit・oracle 構造リスク premium として MCR 120% policy floor を適用する（§0）。
- 3 系統は 1 本の式に統一でき、高ボラ系が大本、USD ステーブル系（`SP = Price = Slip×Mult = 0`）も JGB 系（`Depeg = Slip×Mult = FX = 0`）もその特殊形。

---

## §B. ストレス変数とデータソース

### §B-1. ストレス変数の定義

| 変数 | 意味 |
| --- | --- |
| `Oracle_Update_Frequency` | オラクル更新頻度（日次 or 閾値超過時）。遅延を 30m / 1h / 2h の 3 パターン想定 |
| `Liquidation_Penalty_Percent` | Liquity v2 同様 5% 仮定。低いほど借り手はレバを掛けやすいが安全性低下（資本効率とセキュリティのトレードオフ） |
| `Stress_Price_Shock_D_Percent` | WBTC / WETH のような常時 USD 建て変動トークンが特定期間に下落する想定 |
| `Stress_Depeg_Shock_D_Percent` | USDC のような通常はペグするが特定イベントで乖離するトークンの下落想定 |
| `Stress_FX_Shock_USDJPY_Percent` | JPY/USD が特定期間に円高ドル安方向へ動く想定 |
| `Stress_Slippage_S_Percent` | ストレス時に担保を外部 DEX で売却する際のスリッページ想定。dex aggregator（ParaSwap）API で平時スリッページ平均を取得 |
| `Stress_Liquidity_Stress_Multiplier` | ストレス時の主要 DEX TVL 減少からの倍率（業界慣行 2〜3 倍） |

- 導出値: `MCR_Proposed`（想定担保率）→ `LTVmax_Proposed = 1 / MCR_Proposed`。
- スリッページの仮置きは「平時に $5m の清算を捌く想定」で、UST 崩壊時の Aave レベルを採用したかなり保守的な値。`MCR_Proposed` を求める際は `Stress_Slippage` に `Stress_Liquidity_Stress_Multiplier` を掛けて利用する。

### §B-2. データソース一覧（provenance）

| 対象 | データソース | 粒度・期間・件数・備考 |
| --- | --- | --- |
| JPY/USD | Twelve Data API | 5 分足 / 2021-01-18〜2026-01-16（約 5 年）/ **360,781 件** / **異常値 270 件を排除** |
| WBTC（BTC/USD） | Binance API | 5 分足 / 2017-08〜 |
| WBTC/BTC（depeg） | Binance API | 5 分足 / 2020-08〜 |
| WETH（ETH/USD） | Binance API | 5 分足 / 2017-08〜（カストディ depeg リスクは考慮しない） |
| USDC（USD 建て） | — | 5 分足。分布が正規でない（ジャンプあり）ため depeg は max DD を採用 |
| USDT（参考・棄却候補） | Binance API | TUSDUSDT 5 分足（2h max DD 13.6%）。簡易ソースのため棄却（§D-4） |
| USDS | Binance API | DAI/USDT 5 分足 / 2020-08-11〜（USDS は歴史が浅く DAI 時代データで代替） |
| USDe | Curve | 5 分間隔 price / 2024-01〜（単発 5 分の異常値は除外） |
| XAU/USD | Twelve Data API | 5 分足 / 2020-09-01 00:00 UTC〜2026-05-13 00:55 UTC |
| XAUt/XAU（depeg） | Bitfinex API（XAUt/USD）を XAU/USD と突合 | 5 分足 / 2020-09-01〜2026-05-13 |
| JGB | 財務省「国債金利情報」 | 52 年分。3M データ取得困難のため **1Y JGB を 3M の代替**として使用 |

---

## §C. ボラティリティ生データ（全分布）

### §C-1. JPY/USD（Twelve Data, 5分足, 2021-01-18〜2026-01-16, 360,781件, 異常値270件除外）

| ウィンドウ | 最大下落率 | 99.9th | 99th |
| --- | --- | --- | --- |
| 30分 | 1.79% | 0.51% | 0.23% |
| 1時間 | 2.02% | 0.78% | 0.36% |
| 2時間 | 2.29% | 1.17% | 0.52% |

- 各担保の FX 調整に用いる確定値 = **JPY/USD 2h 99.9th = 1.17%**。

### §C-2. WBTC

**BTC/USD（Binance 2017-08〜 5分足）**

| ウィンドウ | 最大下落率 | 99.9th | 99th | 95th |
| --- | --- | --- | --- | --- |
| 30分 | 17.38% | 3.78% | 1.66% | 0.78% |
| 1時間 | 22.29% | 5.53% | 2.53% | 1.22% |
| 2時間 | 23.62% | 7.54% | 3.66% | 1.84% |

**WBTC/BTC（depeg, 2020-08〜）**

| ウィンドウ | 最大下落率 | 99.9th | 99th |
| --- | --- | --- | --- |
| 30分 | 2.49% | 0.32% | 0.14% |
| 1時間 | 2.91% | 0.43% | 0.17% |
| 2時間 | 2.91% | 0.53% | 0.20% |

### §C-3. WETH（ETH/USD, Binance 5分足）

| ウィンドウ | 最大下落率 | 99.9th | 99th | 95th |
| --- | --- | --- | --- | --- |
| 30分 | 24.21% | 4.41% | 2.00% | 0.99% |
| 1時間 | 29.38% | 6.55% | 3.05% | 1.53% |
| 2時間 | 31.17% | 9.07% | 4.44% | 2.29% |

### §C-4. USDC

| ウィンドウ | 最大下落率 | 99.9th | 99th | 95th | CVaR 99.9th |
| --- | --- | --- | --- | --- | --- |
| 30分 | 9.31% | 0.34% | 0.14% | 0.05% | 0.66% |
| 1時間 | 9.32% | 0.51% | 0.19% | 0.08% | 1.04% |
| 2時間 | 9.32% | 0.77% | 0.26% | 0.11% | 1.60% |

- USD ステーブルの USD 建て価格分布は正規でない（ジャンプがある）ため、depeg は **2h 最大 DD 9.32%（SVB 事件）**を採用。

### §C-5. XAU/USD・XAUt/XAU（Gold）

**XAU/USD（Twelve Data 2020-09-01〜2026-05-13 5分足）**

| ウィンドウ | MAX DD | 99.9th | 99th |
| --- | --- | --- | --- |
| 30分 | 7.27% | 1.11% | 0.49% |
| 1時間 | 7.27% | 1.60% | 0.71% |
| 2時間 | 7.62% | 2.19% | 1.04% |

**XAUt/XAU（Bitfinex XAUt/USD を XAU/USD と突合）**

| ウィンドウ | MAX DD | 99.9th | 99th |
| --- | --- | --- | --- |
| 30分 | 7.616% | 1.764% | 1.022% |
| 1時間 | 7.616% | 2.015% | 1.274% |
| 2時間 | 7.616% | 2.355% | 1.575% |

- XAUt/XAU の max DD 発生は 2025-10-10 21:40 UTC、XAU/USD の max DD は 2026-01-29 14:25 UTC で、**数値は近いが別事象**。max DD 近傍のドローダウンが複数回発生しているため、価格変動・depeg とも **max DD を採用**。

### §C-6. JGB（財務省 国債金利情報・52年・1Y で 3M を代替）

- 2h ウィンドウで **p99.9 = 0.248% / max = 0.279% → 採用 0.28%**。
- ソース: [財務省 国債金利情報 CSV](https://www.mof.go.jp/jgbs/reference/interest_rate/data/jgbcm_all.csv)

---

## §D. LLTV / MCR — 担保別の採用根拠と棄却候補（検討時点）

> ⚠️ ステーブル系のうち、USDC / USDT の「採用」値は現行確定値と一致する。sUSDS / dUSD の「採用」値は**検討時点の stress-implied / USDe-proxy 値**であり、現行確定値は §0 の policy floor 適用後（いずれも LLTV 83.33% / MCR 120.00%）。高ボラ系・JGB 系は現行と一致。

### §D-1. WBTC（→ Branch 5 dBTC の暫定値）

- LLTV は 83.87〜89.35% のレンジ。効いている変数は「どのウィンドウを使うか」「`Stress_FX_Shock` に何を置くか」。
- ~~**候補A（超保守・棄却）**~~: JPY/USD・BTC/USD ともに 2h **最大下落率**。**LLTV 69.09%**。Aave でも 78% であり資本効率の競争力が低いため棄却。
- **候補B（採用）**: JPY/USD・BTC/USD ともに **2h 99.9th**。清算 2h 遅れでも 1000 回に 1 回級の同時発生で Bad Debt が生じないライン。**LLTV 83.65%**。Morpho/Euler 86%・Compound 85% に近い。
- ~~**候補C（やや攻め・棄却）**~~: 1h 99.9th。**LLTV 85.47%**。保守側の候補 B を採用。

### §D-2. WETH（Branch 0・採用 83.91%）

- 考え方は WBTC と同様だがカストディ depeg リスクを考慮しない。採用 = WBTC 候補 B と同じ「2h 99.9th」方式。**LLTV 83.91%**（現行確定と一致）。

### §D-3. USDC（Branch 1・現行 89.62%）

- ~~**候補A（棄却）**~~: SVB を想定し max DD 使用。**LLTV 85.01%**。資本効率が良くないため棄却。
- ~~**候補B（棄却）**~~: 99.9th で資本効率優先。**LLTV 93.03%**。JPY/USD 変動を無視するため棄却。
- ~~**候補C（棄却）**~~: 2h 99.9th の CVaR。**LLTV 92.24%**。同上の理由で棄却。
- **候補D（検討時点の採用）**: e-mode 由来の `1 − LLTV > max divergence` を採用し FX 調整。`LLTV = (1 − 0.0932)(1 − 0.0117) = 89.62%`。
- ~~**候補E（棄却）**~~: FX にも最大下落率。**LLTV 88.60%**。過度に保守的として棄却。
- **現行確定値**: plain stable として上記の stress-implied 値を採用し、**LLTV 89.62% / MCR 111.58% / CCR 124.50%**（§0）。

### §D-4. USDT（Branch 2・現行 89.62%）

- **候補A（採用）**: USDC と同値。USDT 固有 depeg から 7 年以上経過、SVB 危機では USDT にプレミアム等のポジティブ面。提携の話が進み USDC より下げるのは悪印象。
- ~~**候補B（棄却）**~~: Binance TUSDUSDT の 2h max DD 13.6% を代入。**LLTV 85.389%**。簡易ソースの無理計算のため棄却。
- **現行確定値**: USDC と同様、plain stable として **89.62% / 111.58% / 124.50%**（§0）。

### §D-5. USDS / sUSDS（Branch 3・検討時点 87.18% → 現行 83.33%）

- USDS は歴史が浅いため DAI 時代データ（Binance DAI/USDT 2020-08-11〜）を参照。2h 最大下落率 **11.79%**。
- 検討時点: `LLTV = (1 − 0.1179)(1 − 0.0117) = 0.8821 × 0.9883 = 87.18%`。
- ⚠️ **注記追加時点の確定値**: sUSDS は USDS depeg に加え ERC-4626 share / PSM / withdrawal / oracle 構成リスクを持つため、Day-1 immutable policy floor（MCR 120%）を適用し **LLTV 83.33% / MCR 120.00% / CCR 137.65%**（§0）。
- **WETH / dBTC との関係**: sUSDS の MCR 120.00% が WETH 119.18% / dBTC 119.55% をわずかに上回るのは、価格ボラティリティ順ではなく、非価格・exit・oracle 構造リスク premium としての例外。dUSDS は Day-1 cap 0 dormant のため borrowable capacity には影響させず、Sky activation / cap 引き上げ前に route・oracle・liquidity・withdrawal evidence と MCR 120% 維持可否を再承認する。

### §D-6. GHO（検討候補・非デプロイ）

> ⚠️ GHO は **Day-1 担保ブランチに含まれない**。本項は検討記録。

- SVB depeg データが無い（2023-07 ローンチ）。実績上 USDS より LLTV が高いのは不自然。
- **候補A**: USDS の旧 stress-implied benchmark と同値 **87.18%**（Aave CDP の信頼性で補強）。
- ~~**候補B（棄却）**~~: 安全係数を掛ける。恣意的で非推奨。

### §D-7. USDe（→ Branch 6 dUSD の旧暫定値 86.30%・現行は 83.33% へ差し替え）

- Curve 5 分間隔 price（2024-01〜）。2h 最大下落率 5.94%。CDP でなくデルタニュートラルのため USDS と同値とは決めにくい。
- **旧暫定値（USDe proxy）**: USDC 式に安全係数 **1.36**（データ期間比較・極値統計 GEV の 2 年 95% 信頼区間に収まる）。`(1 − 0.0932 × 1.36)(1 − 0.0117) = 0.8732 × 0.9883 = 86.30%`。
- ⚠️ 旧 Notion 子「Liquidation LTV」は「86.03%」と記載していたが入れ違い（タイプミス）で、算式が出すのは **86.30%**（USDe proxy 値）。
- ⚠️ **注記追加時点の確定値**: Branch 6（dUSD）は USDe-proxy 暫定値（86.30% / MCR 115.87% / CCR 134.26%）を採らず、sUSDS と同じ structured / RWA stable 扱いで Day-1 immutable policy floor（MCR 120%）を適用し **LLTV 83.33% / MCR 120.00% / CCR 137.65%** とする。CCR は sUSDS と同じ DAI 時代 2h max DD 11.79% 基準で算定（= sUSDS と同値）。Underlying（BUIDL / USYC / USDY 想定）確定時に当該資産のストレスデータで MCR 120% floor の妥当性を再検証する（§0）。

### §D-8. XAUT / Gold（Branch 4・採用 77.52%）

- 入力（§C-5）: Price 7.62%（XAU/USD 2h max DD）/ Depeg 7.616%（XAUt/XAU 2h max DD）/ Slippage 0.35%（$500k swap）× Multiplier 10 / FX 1.17% / SP 5%。
- `MCR = 1.05 / [(1 − 0.0762)(1 − 0.07616)(1 − 0.0035 × 10)(1 − 0.0117)] = 129.00%`、`LLTV = 77.52%`（現行と一致）。
- **ストレス入力の留意**: 別ソースには depeg 10.53% / slippage 4.52% / 99.9th 2.403% の記載もあるが、MCR 129.00% を導く確定式は depeg 7.616% / slippage 0.35%×10 / price max DD 7.62% を用いる。スリッページ大のため mintCap を低く保つ前提。

### §D-9. dJPY（JGB ブランチ・採用 94.97%）と JPYC（100%）の区別

> ⚠️ 旧 Notion 推奨まとめは「JPYC: 100%」だったが、**Day-1 Branch 7（dJPY）は JGB トークン担保の JGB 系設計で LLTV 94.97% / MCR 105.30%**（§E-9・現行と一致）。「100%」は JPYC を担保にしオラクル 1 円ハードコード前提の理論値で、デプロイ値ではない。

- **JPYC（理論検討）**: オラクル 1 円ハードコード（価格不動）前提で 100%。懸念点 = 裏付け国債の利回り急騰で SVB 超 depeg の可能性、JPYC 社の裏付け資産運用リスク。将来のオラクル変更時は要再検討。
- **JGB トークン（Branch 7 確定設計）= §E-9 を参照。**

### §D-10. 推奨 LLTV まとめ（検討時点。現行確定値は §0 / Parameters.md が正）

| 担保 | 検討時点 LLTV | 算定要点 |
| --- | --- | --- |
| WETH | 83.91% | ETH/USD・JPY/USD ともに 2h 99.9th（現行一致） |
| WBTC | 83.65% | BTC/USD・JPY/USD ともに 2h 99.9th（現行一致） |
| USDC | 89.62% | `(1 − max DD 9.32%)(1 − FX 1.17%)`。plain stable stress-implied 値 |
| USDT | 89.62% | USDC と同値。plain stable stress-implied 値 |
| USDS | 87.18% ⚠️→現行 83.33% | DAI 時代 2h max DD 11.79%。現行は policy floor MCR 120% |
| GHO | 87.18% | データ不足のため旧 USDS benchmark と同値（**非デプロイ**） |
| USDe | 86.30% ⚠️→現行 dUSD 83.33% | USDC 式に安全係数 1.36（USDe-proxy 旧値）。Branch 6（dUSD）現行は USDS 基準 + MCR 120% floor（§D-7） |
| XAUT | 77.52% | §D-8（高ボラ系・Gold、現行一致） |
| dJPY（JGB） | 94.97% | §E-9（JGB 系・MCR 105.30%、現行一致） |
| JPYC | 100% | オラクル 1 円ハードコード前提の理論値（**dJPY デプロイ値ではない**） |

---

## §E. CCR / SCR / BCR / 清算ペナルティ — 採用根拠

> 現在の確定値は [Parameters.md](../../Parameters.md) が正本。本節は意思決定根拠とピア比較・棄却検討を保存する。

### §E-1. CCR（Critical Collateral Ratio）

- **役割**: TCR が CCR を下回ると新規借入・担保引き出しを禁止。清算が意図通り動かず TCR が下がり続けた場合の「防波堤」。
- **設計式**: `CCR = MCR / [(1 − Price)(1 − Depeg)(1 − FX)]`。設計目標は「TCR_before = CCR のとき最悪ストレス後でも TCR_after = MCR までしか下がらない」。
- ストレス入力と結果（USDC / USDT は現行一致。sUSDS / dUSD は §0 の通り現行が異なる）:

  | 担保 | MCR | 担保/USD DD 2h（Price） | depeg DD 2h（Depeg） | JPY/USD DD 2h 99.9th | CCR |
  | --- | --- | --- | --- | --- | --- |
  | WBTC | 119.55% | 7.54%（BTC 2h 99.9th） | — | 1.17% | 130.82% |
  | WETH | 119.18% | 9.07%（ETH 2h 99.9th） | — | 1.17% | 132.61% |
  | USDC | 111.58% | — | 9.32%（max DD） | 1.17% | 124.50% |
  | USDT | 111.58% | — | 9.32%（=USDC） | 1.17% | 124.50% |
  | sUSDS ⚠️ | 114.71%→現行120.00% | — | 11.79%（USDS max DD） | 1.17% | 131.58%→現行137.65% |
  | dUSD（dUSD/TBD）⚠️ | 115.87%→現行120.00% | — | 11.79%（USDS 基準・sUSDS と同値。旧 USDe-proxy は Price 12.6752%） | 1.17% | 134.26%→現行137.65% |
  | Gold（XAUT） | 129.00% | 7.62% | 7.616% | 1.17% | 152.93% |
  | JGB トークン | 105.30% | — | — | — | 107.30%（別ロジック。§E-9） |

- **方針**: MCR を保守的に置いているため CCR は過度に保守的にしなくてよい。AsymmetryFi はステーブルを `CCR = MCR + 10%`。

### §E-2. SCR（Shutdown Collateral Ratio）

- **役割**: TCR が SCR に達するとブランチをシャットダウンし緊急償還開始（復活不可）。SP/JIT・Redistribution・CCR を経てもなお TCR が下がる場合の「最後の砦」。
- **採用値**: USD 系ステーブル 105% / WETH・WBTC・Gold 系 110%。
- **設計思想**: 本家は `SCR = MCR` だが寡占ブランチでは大口清算閾値入りで誤シャットダウンの恐れ → `SCR < MCR` が望ましい。`URGENT_REDEMPTION_BONUS = 2%` 踏襲のため最低 102% 以上。Liquidation Penalty 5% を含む 105% を USD ステーブルの最終手段ラインとし、WETH/WBTC は Redistribution ボーナス満額ライン 110% まで buffer（AsymmetryFi と一致）。

### §E-3. BCR（Batch CR buffer）

- **採用値**: 全ブランチ 10% 統一（JPY ブランチのみ 5%）。
- **根拠**: 本家・AsymmetryFi・Nerite が 10% 統一で実績。前提（`MAX_ANNUAL_INTEREST_RATE 250%`、`MAX_ANNUAL_BATCH_MANAGEMENT_FEE 10%`、`UPFRONT_INTEREST_PERIOD = INTEREST_RATE_ADJ_COOLDOWN 7日`）で極端ケースでも 7 日分管理手数料 + 1 回金利変更 upfront fee 合計 **4.98%** を払ってなお 2 回の金利変更まで保護。
- **JPY ブランチ**: 金利 250% は極端すぎるため、50% で 2 サイクル耐える想定で **5%（≒4.22%）**。

### §E-4. Liquidation Penalty（SP 清算ペナルティ）

- **採用値**: 全ブランチ 5% 統一（JPY も 5%）。
- **根拠**: 本家・Fork 群も 5% で実績。SP 間で penalty が異なると SP 流動性が偏る。低く・差別化しても明確なメリットなし。
- ⚠️ **JPY ブランチ（履歴）**: 旧「パラメータ検討メモ」では MCR 102.04% 時に「`(1 + 5%) ≤ MCR` を満たせず 2% 採用」としていたが、後続設計で MCR を 105.30% に引き上げ、`1.05 ≤ 1.0530` を満たして **5% を確保**。

### §E-5. Redistribution Penalty

- **採用値**: 全ブランチ 10% 統一（JPY のみ 5%）。
- **根拠**: 本家 WETH 10%（wstETH/rETH 20%）、AsymmetryFi 全 10% 統一で実績。高くしすぎると Redistribution 誘発の攻撃インセンティブが上がる。JPY は清算 permissioned 設計のため Liquidation Penalty と差をつける必要なく 5%。

### §E-6. 制約条件（本家 Whitepaper / BOLD README）

```
LIQUIDATION_PENALTY_SP  ≤  LIQUIDATION_PENALTY_REDISTRIBUTION  ≤  10%  ≤  MCR
```

- 清算で奪える担保の最大値は `(1 + penalty) × debt`。`(1 + penalty) × debt ≤ MCR × debt` が成立しないと collateral surplus が負になる。
- Redistribution 時にペナルティを高くするのは TCR が清算で低下しないため（本家 Whitepaper）。
- 出典: [liquity/bold README](https://github.com/liquity/bold/blob/main/README.md#liquidation-penalties-and-borrowers-collateral-surplus)

### §E-7. ピアの LLTV / MCR / CCR / SCR 設計（参考）

**ピア LLTV 事例**

| 担保 | Aave | Morpho | Euler | Fluid | Compound |
| --- | --- | --- | --- | --- | --- |
| WETH | 83% | 86% | 85% | 92% | 88% |
| WBTC | 78% | 86% | 86% | 90% | 85% |
| USDC | 78%（e-mode 90〜91%） | — | — | — | — |
| USDT | 78%（e-mode 90〜91%） | — | — | — | — |
| USDS | 78% | — | 94% | — | — |
| USDe | 75%（e-mode 90〜94%） | 91.5% | 92% | 94% | — |
| XAUt | 75%（isolated） | 77% | 75% | 80% | — |
| stETH | 81% | 86% | 83% | 88% | 86% |

**ピア MCR / CCR / SCR**

- **Liquity v2 本家**: WETH `110 / 150 / 110`、wstETH・rETH `120 / 160 / 120`。`SCR = MCR`、CCR は MCR+40%。
- **AsymmetryFi**: ステーブル例 `110 / 120 / 105`、tBTC・WBTC `120 / 150 / 110`。`SCR < MCR`、ステーブルは CCR−MCR buffer 10%。
- **Nerite**: WETH `110/150/110`、LST `130/160/115`、ARB・COMP `140/165/115`、tBTC `115/150/110`。

### §E-8. 清算実行者担保補償

- **採用値**: `min(0.5% × collateral, 1,000 units)`（`COLL_GAS_COMPENSATION_DIVISOR = 200` / `COLL_GAS_COMPENSATION_CAP = 1_000e18`）。

### §E-9. dJPY（JGB トークン）ブランチの特殊設計

担保通貨と発行通貨がともに JPY のため、一般式の Depeg・Slip・FX は 0、Stress_Price のみが効く。

- **清算フロー（permissioned）**: tokenized JGB は移転制限付きで DEX 売却なし。`Trove liquidatable → 運営が JPYdf で清算 → JGB token 受領 → 発行体に redeem → JPY 受領 → JPYdf へ戻す`。オラクルは発行体/提携業者公表 NAV を Chainlink Proof of Reserves 等で取り込む想定。
- **duration 前提**: BUIDL / OUSG 並みの **3M 以下**。BUIDL は $1 stable + USDC par 償還、OUSG は NAV ベース償還。保守的に OUSG メカニズムを想定。
- **清算〜償還期間**: オラクル lag 数時間 + 更新間隔 24h + liquidator 反応数分 + redemption ワーストケース（連休跨ぎ）≈ 約 2 週間。
- **LLTV / MCR**: Stress_Price = §C-6 より 2h max 0.279% / p99.9 0.248% → 採用 0.28%。`MCR = 1.05 / (1 − 0.0028) = 105.30%`、`LLTV = 94.97%`。
- **CCR**: 他式では `MCR = CCR` となり機能しないため gap で設計。`CCR = MCR + 2% = 107.30%`。

  | gap（CCR−MCR） | APR 1% | APR 5% | APR 10% | APR 50% | APR 250% |
  | --- | --- | --- | --- | --- | --- |
  | 1% | 358日 | 73日 | 37日 | 8.8日 | 2.8日 |
  | 2% | 712日 | 145日 | 74日 | **17日** | 5.7日 |
  | 3% | 1063日 | 217日 | 111日 | 26日 | 8.4日 |

  APR 250% は異常値。APR 50% 想定でも 2 週間あれば清算準備でブランチを健全に保てる → CCR 107.30%。
- **SCR**: `URGENT_REDEMPTION_BONUS`（2%）を払えない水準まで落ちると urgent redemption が revert し Bad Debt が残る。CCR と対称の gap で `SCR = MCR − 2% = 103.30%`（102% 以上を満たす）。
- **オラクル**: JPYC 系担保の場合、初期はオラクルを 1 円ハードコード（将来アップグレード可能性あり）。

---

## §F. dToken Layer 運用系パラメータ — 採用根拠

> Liquity v2 コアではなく DeltaForesight 独自の dToken / CollateralVault が持つ運用パラメータ。実装仕様は [CollateralVault](../../protocol/product/spec/CollateralVault.md) / [dToken](../../protocol/product/spec/dToken.md) / [Strategy](../../protocol/product/spec/strategies/Strategy.md)。現在の確定値は [Parameters.md](../../Parameters.md)。

### §F-1. mintCap

- **方針**: Biz 視点ではローンチ当日に埋まる cap を置き「初日で cap 達成」と見せる方がユーザー獲得に効く。Day-1 の open branch は wstETH / USDC。Underlying 未確定の予約枠（Branch 3–7）は初期 0。XAUT 候補の引き上げはデペグのオンチェーン反映実装の稼働後に限る。
- ⚠️ **cap 規模の検討経緯**: 旧メモでは「自己 B/S mint $250k 下限・USDT ディール上限 $3m」「各ブランチ $1m」案も検討したが、2026-06-18 再検討で、Liquity v2 直近 1 年の wstETH ブランチ debt 比最大清算規模 22% を踏まえ、$1m cap では 50% 規模清算を吸収しきれず **1 億 JPYdf 規模なら余裕**と判明。現行 Day-1 open branch cap は dwstETH=35 百万円・dUSDC=1 億円（確定値は Parameters.md）。
- **Day-1 branch debt ceiling 判断（#301）**: Day-1 では Core に新しいオンチェーン branch debt ceiling を追加しない（Core 差分・テスト・監査の複雑性大、初期露出は dToken mintCap・MCR/CCR/SCR・SP coverage・ops gate で管理できるため）。`mintCap` を「JPYdf 発行上限」「branch debt ceiling」と表記してはならない。

### §F-2. allocatorCooldown

- **採用値**: 全ブランチ 30m。`Strategy.sendToVault`（buffer 補充）には不適用。
- **方針**: ALLOCATOR 鍵漏洩時のリスク低減が目的。whitelist 限定のため保守的に延ばしても安全性が大きく上がらず利便性優先でよい可能性。allocator 鍵漏洩と whitelist 先 exploit が重なると間接的に資金を奪われうる点は残存リスク。

### §F-3. allocateMaxMove

- **採用値（Day-1）**: dUSDC=1 億円、その他（dETH / dwstETH / inert branch）は 0（`0`=配分停止、`type(uint256).max`=実質上限なし。dwstETH は Day-1 Strategy なし）。
- **位置付け**: 鍵侵害時に一度に動かせる額を制限する安全装置。設計思想の記述が薄く、活性化時の値根拠は今後詰める。

### §F-4. withdrawDelay

| 担保 | withdrawDelay | 根拠 |
| --- | --- | --- |
| WETH | 3日 | 現行 dETH は cap 0・同期回収可能な Strategy 前提。旧 Lido 非同期回収前提の 17 日は採用しない |
| WBTC | 12日 | Lombard 利用時 9 日 + buffer 3 日 |
| USDC / USDT | 3日 | 基本的に sync strategy |
| USD ステーブル（sUSDS 等） | 10日 | sUSDe の 7 日を想定 |
| Gold（XAUT） | 3日 | 運用先特になし |
| JPY ステーブル | 3日 | 基本的に sync strategy |

- **方針**: async 型 Strategy の引き出し期間に buffer を上乗せするくらい保守的でも可。「引き出せると言ってできない」方が reputation リスク大。
- ⚠️ 旧 Notion 親表は WETH=12日 / dBTC=17日 と取り違えがあった。確定は **WETH=17日 / dBTC=12日**。

### §F-5. bufferTargetBps

- Vault 内に即時引出し可能な流動性として保持する目標比率。Redemption はこの buffer を使う。
- **算定根拠**: Liquity v2 の 2025-05-15〜2026-05-04 の redemption TVL 比を各 withdrawDelay 期間で rolling-max 集計し、最大の **WETH ブランチ**値を保守的に採用。

  | Branch | TVL | 3d | 10d | 12d | 17d |
  | --- | --- | --- | --- | --- | --- |
  | WETH | $23m | 3.33% | 9.38% | 10.16% | 12.00% |
  | wstETH | $118m | 0.62% | 1.66% | 1.90% | 2.52% |
  | rETH | $22m | 1.24% | 2.12% | 2.44% | 3.42% |

  → withdrawDelay 期間ごとに 3日=3.33% / 10日=9.38% / 12日=10.16% / 17日=12.00%。
- 最大の単一 redemption（1tx）は TVL 比 1.34%（WETH ブランチ）。
- **方針**: DeltaForesight 初期は 1 件の redemption が相対的に大きくなりうるため倍率 1.5〜3 倍の余地あり。peg 監視 + フラッシュローン裁定 bot と併用検討。

### §F-6. bufferFloor

- **採用値**: 全ブランチ 0。`bufferTargetBps` で制御できれば不要との整理。

---

## §G. 最低金利（MIN_ANNUAL_INTEREST_RATE）— 採用根拠

> **確定値**: 全ブランチ共通 **0.5%（`_1pct / 2`）・2026-06-10 確定**。Liquity v2 標準値を維持し DF 独自変更なし。Core 継承定数のため**値の正本は [Liquity-v2-Core-Spec.md §7](../../protocol/product/spec/Liquity-v2-Core-Spec.md)**（base 無改変継承のため [Parameters.md](../../Parameters.md) には掲載しない方針）。本節は値決定の根拠（旧 Notion 子「最低金利に関する議論メモ_20260610」を移管）。

### §G-1. 結論

全ブランチで `MIN_ANNUAL_INTEREST_RATE = 0.5%` を採用（標準値維持、引き下げなし）。借り手は年利を `[MIN, MAX]` の範囲で自由設定でき、その下限を base から変更しない。

### §G-2. 議論の発端

トークン化 JGB ブランチで、借入コストを下げれば JPYdf 発行量を増やせるのではという仮説から引き下げ（0.5% → 0.3%）を検討。

### §G-3. 検討した攻撃 / リスク（0.5% → 0.3%）

| 観点 | 影響 |
| --- | --- |
| 直接攻撃 | 新規の攻撃ベクトルはなし |
| 二次的脆弱性 | 借入コスト 0.2% 低下で既存攻撃（JPYdf dump 連鎖、裁定）の経済性が微増 |
| Redemption 回避 | 一時的な金利操作コストがわずかに低下 |
| SP yield | 金利由来 yield 低下で SP 預金者退出 → SP 弱体化 → 清算機構の脆弱化 |

直ちに致命的脆弱性は生じないが、いずれも安全性をわずかに削る方向。

### §G-4. 0.5% 維持の論拠

- **市場金利環境**: 日本は物価上昇・円安で利下げ余地が乏しく、2026-06 会合でも政策金利 1% への上昇。0.5% 円建て借入は十分魅力的。財政逼迫で JGB 利回りは上がり続ける構造で、借入コストをさらに下げる必然性が乏しい。
- **攻撃耐性と Fork 方針**: 引き下げの便益（発行量増）はリスクに見合わない。Liquity v2 Fork として **base パラメータをできるだけ変更しない**（監査・実績の継承、想定外挙動の回避）。

### §G-5. 実装・参照

- 値の正本: [Liquity-v2-Core-Spec.md §7](../../protocol/product/spec/Liquity-v2-Core-Spec.md) — `MIN_ANNUAL_INTEREST_RATE = _1pct / 2`（0.5%）。
- コード: `contracts/src/Dependencies/Constants.sol` / `contracts/src/BorrowerOperations.sol`（`_requireValidAnnualInterestRate`）。

---

## §H. 旧 Notion 値との差分メモ（stale 注意）

旧 Notion 各ページの検討途中で残っていた stale 値（いずれも **Parameters.md / 本書の確定記載を正**とする）。**※ §0 の sUSDS policy floor / USDC・USDT stress-derived 復帰とは別軸**（こちらは Notion 内の取り違え・旧版）。

| 項目 | 旧 Notion の記載 | 本書の記載 | 備考 |
| --- | --- | --- | --- |
| USDe / dUSD LLTV | 86.03% | 86.30%（USDe-proxy 旧値） | 算式 `0.8732×0.9883≈0.8630` の入れ違い。現行 dUSD は USDS 基準 + MCR 120% floor で **83.33%**（§D-7 / §0） |
| dJPY LLTV / MCR | 98% / 102.04%（メモ初期） | 94.97% / 105.30% | JGB 系確定設計（§E-9） |
| JPY Liquidation Penalty | 2%（MCR 102.04% 前提時） | 5%（MCR 105.30% で確保） | §E-4 |
| WETH withdrawDelay | 12日（親表） | 17日 | §F-4 取り違え |
| dBTC(WBTC) withdrawDelay | 17日（親表） | 12日 | §F-4 取り違え |
| mintCap | 1 億 JPYdf（WETH, 親表）/ $1m 案 | dwstETH=35 百万円・dUSDC=1 億円 | §F-1（2026-06-18 再検討。現行値は Parameters.md） |
| rebalanceCooldown / rebalanceMaxMove | 旧名称 | allocatorCooldown / allocateMaxMove | 改称（[CollateralVault](../../protocol/product/spec/CollateralVault.md)） |

---

## §I. 参照

- **確定値**: [Parameters.md](../../Parameters.md)
- **parameter の意味・不変条件**: [Parameter Catalog](../../protocol/product/parameters/Parameter-Catalog.md)
- **メカニズム仕様**: [Liquity v2 コア仕様](../../protocol/product/spec/Liquity-v2-Core-Spec.md) / [CollateralVault](../../protocol/product/spec/CollateralVault.md) / [dToken](../../protocol/product/spec/dToken.md) / [Strategy](../../protocol/product/spec/strategies/Strategy.md) / [Oracle](../../protocol/product/spec/Oracle.md)
- **算定スプレッドシート**: `LLTV_DeltaForesight_20260111`（社内 Google Sheets）
- **上流**: [liquity/bold README](https://github.com/liquity/bold/blob/main/README.md#liquidation-penalties-and-borrowers-collateral-surplus)
- **データソース**: §B-2 の各 API / 財務省 国債金利情報

> 本ページは旧Notion parameterページ群の統合・置換版であり、2026-07-27時点でfreezeした。新しい検討は対象ごとのDecision Record / Evidenceへ残し、本snapshotを更新しない。
