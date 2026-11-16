# 旧 jpydf の振り返りと教訓（再構築の背景・post-mortem）

> **この資料は「なぜ jpydf を 0 から作り直すのか」の背景と、旧リポジトリ `deltaforesight/jpydf`（凍結・参照専用）から引き継ぐ／避ける資産の分析。** 前向きな現行作業は [`Development-Plan.md`](../../engineering/plans/Development-Plan.md)。
>
> **PR 表記**: 本書の `jpydf#N` はすべて**旧リポジトリ `deltaforesight/jpydf`**（凍結・参照専用）の PR。新リポジトリ `deltaforesight/jpydf-v2`（現行）の PR は `v2#N` と表記し、本書ではほぼ登場しない。
> **「→ Phase」表記**は再構築時に用いた移植フェーズの履歴ラベルである。現在の作業は [`Development-Plan.md`](../../engineering/plans/Development-Plan.md) を参照する。

## 0. 要旨 — なぜ作り直すか

1. **コア最小改変の原則違反は実測で裏付け済み**: 旧 `develop`（`848c6b8`）は クリーン上流 `base`（`d2e75c3`）に対しコア（Liquity v2）ファイルを **15 本改変**（+257/−57 行）。大半は不要・無意味・誤った改変で、最も触ってはいけない `BorrowerOperations`/`TroveManager` まで改変されている（§1）。
2. **独自レイヤーは実在する再利用資産**（新規 18 ファイル・約 2,400 行 + 一部テスト）。`CollateralVault`/`CollateralYieldZapper`/`DToken`/`PriceFeedProxy`/`Strategies` は spec に整理し直せば移植可（§2, §4）。
3. **CI が一度も緑にならなかった（検証の土台の欠如）**: 旧 `develop` は数ヶ月にわたり CI が全 run 赤のまま放置され、各 PR はその赤を継承していた（PR 固有でなく develop 由来）。さらに、緑化のために必要なテストを `skip`／carve-out で回避して通そうとした形跡があるが、**それでも緑化には至らなかった**。「BOLD が想定するテストが常に通る」という検証の土台が最後まで成立しなかった。→ この反省を踏まえ、jpydf-v2 は各 commit・各 PR で CI を緑に保ちながら進める（[`Development-Plan.md`](../../engineering/plans/Development-Plan.md) §1、全文は本書 §6「毎ステップ全件緑・skip 禁止」）。
4. **方針**: develop を継ぎ接ぎせず、最新 upstream BOLD（v1.11.0）から作り直し、コア無改変を CI で commit 1 から強制し、**各 commit・各 PR で CI（build＋test＋コア無改変ガード）を緑に保ちながら**（skip による偽 green を禁止）検証済みレイヤー＋テストを現行 spec に移植する。→ 計画は [`Development-Plan.md`](../../engineering/plans/Development-Plan.md)。

---

## 1. 旧 develop（@ `848c6b8`）のコア改変の実態

**証拠**: `git diff base develop -- contracts/src` = 改変 15 / 新規 18

| ファイル | +/− | 判定 |
|---|---|---|
| `Dependencies/Constants.sol` | +58/−2 | パラメータ（許容）だが旧8担保設計に固着 |
| `PriceFeeds/MainnetPriceFeedBase.sol` | +44/−8 | JPY換算を**上流に直編集**（constructor 3→5引数化が全feedに波及）→ 再構築は**無改変継承の新DF基底**で回避 |
| `PriceFeeds/{WETH,WSTETH,RETH,Composite}PriceFeed.sol` | 各+24〜30 | ❌ WSTETH/RETH/Composite は **DF未採用LST。無駄な改変** |
| `AddressesRegistry.sol` (+I/F) | +20/+11 | ❌ `collateralVault/dToken/underlyingToken` をコア注入＝**責務分離違反** |
| `BorrowerOperations.sol` | +6/−2 | ❌ `if(ETH_GAS_COMPENSATION>0)` ガード×2＝**不要**（0送金は標準WETHで無害） |
| `TroveManager.sol` | +3/−1 | ❌ `+=0` を `if>0` で囲む＝**完全に無意味** |
| `BoldToken.sol` | +3/−3 | name/symbol は ✓、エラー文言変更は不要汚染 |
| `GasPool.sol` / `Zappers/*` / `Interfaces/IMainnetPriceFeed.sol` | 各 微小 | ❌ コメント/上流直編集の不要汚染 |

**結論**: 本来 `Constants.sol` のパラメータ設定で済む「gas=0」を、コアロジック改変で実装。`TroveManager` の `+=0` ガードは機能的に無意味。DF が使わない LST feed まで編集。「コア最小改変」原則は守られていない。履歴も `jpydf#24`（Revert to bold）・`jpydf#38`（コア改変）→`jpydf#54`（revert）と**コア汚染→revertの反復**を示す。

---

## 2. 再利用可能な資産（約 2,400 行）とギャップ

**移植可能**: `CollateralVault.sol` / `CollateralYieldZapper.sol`(509) / `DToken.sol`(271) / `PriceFeedProxy.sol`(208) / `Strategies/{BaseStrategy,AaveV3Strategy,MockStrategy}`。テスト: `DToken.t`/`CollateralVault.t`/`CollateralYieldZapper.t`/`PriceFeedProxy.t`/`CollateralYieldManagement.t`（統合）。

> ⚠️ 再構築時の移植元は develop の pull 型(893行)でなく **push-model 版（`jpydf#61` branch, `CollateralVault.sol`@blob `5e019a7`）に `jpydf#57` deferred-underlying を統合したもの**だった。現行要件の正本は [`CollateralVault.md`](../../protocol/product/spec/CollateralVault.md) と [`Strategy.md`](../../protocol/product/spec/strategies/Strategy.md)。`CollateralVault.t`/`CollateralYieldManagement.t` も `jpydf#61` の push-model 版で書き換わる（develop 版テストは削除）。

**新規が必要なギャップ**:
- ❌ `Treasury.sol` 不在（要件: harvest 送付先・**80% SP / 20% DF Corp** 分配・buyback）
- ❌ Strategy テスト皆無 / ❌ `PriceFeedPlaceholder.sol` 不在
- ❌ deferred-init（`setUnderlying`/Vault↔dToken整合）は develop 未マージ（`jpydf#57`）
- ❌ 非同期 Strategy の清算経路 元本回収（Strategy 要件 STGY-ERR-002）

---

## 3. 設計ドリフト（develop 旧 → 現行 spec 新）

| 論点 | develop（旧） | 現行 spec（新） | 参照PR |
|---|---|---|---|
| 担保ブランチ | 8担保を具体feedでハードコード | **確定5+inert3**（Parameters.md §1） | `jpydf#59`,`#60` |
| Underlying 確定 | デプロイ時固定 | 後付け1回（**setTokenInfo→setUnderlying の順**） | `jpydf#57` |
| コア結合 | AddressesRegistry に vault/dToken 注入 | **コア無結合**（deploy層で dToken を collateral 登録, getToken==collToken） | `jpydf#54` |
| Oracle source 検証 | 弱い | non-contract source 拒否・branch feed assert | `jpydf#58` |
| Vault 収益経路 | pull harvest（`claimHarvest`→treasury） | **push-model**（Strategy→`receiveFromStrategy`→`transferYieldToTreasury`）。`jpydf#52` pull は不採用 | `jpydf#61` |
| テスト | pull前提・赤CI | **push-model 移行 + invariant fuzz** | `jpydf#61` |

---

## 4. PR 資産マップ（旧 jpydf 全 61 PR = `jpydf#1`–`#62`〔#19 は issue で欠番〕: merged 35 / open 12 / closed-unmerged 14。2026-06-06 実測）

> すべて旧リポ `deltaforesight/jpydf` の PR。「→ Phase」列は再構築時の移植フェーズを示す。

### 4.1 REUSE（移植すべき実証済み資産）
| PR | 状態 | 内容 | → Phase |
|---|---|---|---|
| `jpydf#54` | merged | **コア無改変でdTokenを担保化する正解配線**（CollateralRegistryにdToken登録, getToken==collToken, deploy末尾require） | P4 |
| `jpydf#35` | merged | `AddressVars.collToken = dToken`（1行・最小の正解） | P4 |
| `jpydf#33` | merged | deploy owner を `deployer` に固定 | P4 |
| `jpydf#17` | merged | dToken層基盤（DToken固定1:1レート / Vault骨格 / IStrategy・BaseStrategy・AaveV3 / CYZ） | P3a(DToken/Vault)/P3b(Strategy)/P5(CYZ) |
| `jpydf#31` | merged | `setTokenInfo` deferred-init + `__gap[50]` | P3a |
| `jpydf#42` | merged | `Allocated` イベント3引数化 | P3b |
| `jpydf#52` | open | per-strategy 配分・bulk廃止の**設計参照のみ**。⚠️ weightBps async harvest/`claimHarvest`/`failedRemovalList` は **push-model(`jpydf#61`) に置換され不採用**（STGY-ERR-002 async 元本回収の論点だけ Phase 3b 設計ゲートへ） | P3b(参照) |
| `jpydf#53` | open | LidoStrategy（唯一の実async実装・要監査） | P3b-2（MVP内・個別 Strategy として実装） |
| `jpydf#57` | open | **deferred-underlying + Vault↔dToken整合**（`whenUnderlyingReady`/`setUnderlying` eager check, 148 passed） | P3a |
| `jpydf#59` | open | **placeholder inert化 + PriceFeedPlaceholder + Zapper vault-source + Day2活性化順序** | P2/P3a/P4 |
| `jpydf#26` | merged | PriceFeedProxy（source差替/24h TL/try-catch shutdown/lastGoodPrice） | P2 |
| `jpydf#37` | merged | PriceFeedProxy `Ownable2Step`（OZOwnable別名で衝突回避） | P2 |
| `jpydf#22` | merged | WBTC peg-monitored 3段 | P2 |
| `jpydf#55` | open | PriceFeedProxy gas-error re-revert（`err.length==4`厳密bubble） | P2 |
| `jpydf#58` | open | PriceFeedProxy 非コントラクトsource拒否 + branch feed assert | P2/P4 |
| `jpydf#45` | merged | Zapper multicall 境界3不変条件（nested拒否/replay/refund） | P5 |
| `jpydf#61` | open | **push-model Vault/Strategy アーキテクチャの一次参照**（branch `feat/push-model-migration` head `9acb750`。`1312baa` push-model 移行 ＋ テスト全面書換: 57ユニット+3 invariant+PushModelMocks）。`CollateralVault.sol`@blob `5e019a7`＝`receiveFromStrategy`/`transferYieldToTreasury` | **P3b** |
| `jpydf#25` | merged | CI trigger（develop push + PR opened/synchronize） | P0 |
| `jpydf#49` | open | **bridge-agnostic** mint/burn（永続bridgeAdmin/48h timelock/getCCIPAdmin shim） | 履歴参照。現行正本では active bridge は Day-1 cut、token は休眠 bridge-ready surface のみ |

### 4.2 REFERENCE（設計を参照、コードは作り直す）
`jpydf#24`(BOLD識別子復帰) / `jpydf#20`(collUsd命名) / `jpydf#27`(Proxy ABI) / `jpydf#36`(Proxy統合配線) / `jpydf#56`(CYZ経由demo+debt>MIN_DEBT) / `jpydf#62`(faucet sizing+再実行salt) / `jpydf#51`(Path B分割の教訓) / `jpydf#40`(文言置換・内部キー据置) / `jpydf#43`(docs仕様) / `jpydf#30`(JPYC depeg) / `jpydf#2`(WBTC変換数式) / `jpydf#16`(固定feed概念→RWA/JGB)。

### 4.3 AVOID（再現禁止・反面教師）
| PR | 失敗の本質 | 反映先 |
|---|---|---|
| `jpydf#1` | JPY換算を MainnetPriceFeedBase constructor に**直編集**で焼込→全feed署名連鎖 | upstream無改変・**JPYは継承した新DF基底で**足す → P2 |
| `jpydf#13`/`#14` | gas=0「最適化」で BorrowerOps/TroveManager に `if(gas>0)` | 0送金/+=0は無害→コア触らない → P1ガード |
| `jpydf#9` | BoldToken→JPYdfToken をコア全ファイルでリネーム | コア名不変・可視名のみdeploy引数 → P1 |
| `jpydf#38` | redemption不一致を**コア改変**で症状対応→`jpydf#54`で全revert | 症状をコアで消さない・真因はdeploy登録 → P4 |
| `jpydf#39`/`#44` | Pyth dual-oracle（コアfeed侵襲・payable/refund/VAA複雑） | 単一Chainlink・payable feed作らない → P2 |
| `jpydf#47` | LST物理削除（コア無改変違反+テスト巻き添え+件数定数旧literal残存OOB） | pristine温存・件数定数は全grep → P2/P4 |
| `jpydf#50` | NUM_BRANCHES 8→4 ハード縮小 | branch immutable→最終本数でDay-1デプロイ → P4 |
| `jpydf#51` | deferred-underlying を相互チェック無し独立setter2つ | 跨ぎ不変条件をコード強制（`jpydf#57`方式）→ P3a |
| `jpydf#28` | CCIP setBridgeMinter を renounce後に呼べずロックアウト | 永続admin方式（`jpydf#49`）→ P6（🚫 Cut） |
| `jpydf#3`/`#5` | code-copyでリポ作成→clean履歴喪失 | 正規取り込み（jpydf-v2で解消済） |
| `jpydf#7` | React/Next.js RCE CVE | 新frontendはpatched版から → P5 |

### 4.4 純DEAD-END（再構築で無関係）
`jpydf#6`(中継マージ)/`jpydf#10`(config)/`jpydf#23`(AI解説md)/`jpydf#11`(巨大未マージ)/`jpydf#18`(WIP doc)/`jpydf#21`(artifact混入)/`jpydf#41`・`#48`(単独不採用→`jpydf#52`統合)/`jpydf#46`(revert破棄→Proxy確定の証跡)。

---

## 5. 資産の扱い 早見表
| 区分 | 対象 |
|---|---|
| **Revert/破棄** | コア改変15本（BorrowerOps/TroveManager の if>0、GasPool/Bold文言、AddressesRegistry結合、WSTETH/RETH/Composite編集） |
| **そのまま継承** | クリーン upstream BOLD コア一式（無改変） |
| **パラメータのみ適用** | BoldToken name/symbol、Constants(gas=0/MIN_DEBT/ブランチ別CR) |
| **移植** | DToken / **CollateralVault(push-model `jpydf#61` + `jpydf#57` deferred-underlying)** / PriceFeedProxy / Strategies(push) / CollateralYieldZapper / テスト(push-model版 `jpydf#61`)。feed は新規ファイル(下記) |
| **新規構築** | Treasury(80/20・設計ゲート) / `DFPriceFeedBase`＋DF feed(WETH/USDC/USDT/sUSDS/XAUT, Day-1) / PriceFeedPlaceholder / RWA・JGB・WBTC feed(Day-2) / Strategyテスト / async元本回収(MVP内＝P3b-2 で実装・LidoStrategy.md。対応設計は STGY-ERR-002) / コア無改変CIガード |
| **一次参照（未マージPR）** | `jpydf#55-62`スタック / **`jpydf#61`(push-model Vault/Strategy 基盤＋テスト)** / `jpydf#52`(strategy 設計参照のみ・pull不採用) / `jpydf#53`(Lido async・**MVP内＝P3b-2 で実装**) / `jpydf#57`(deferred-underlying) / `jpydf#49`(bridge は履歴参照。現行は Day-1 active bridge cut + token 休眠 readiness) |

---

## 6. コア差分管理の教訓（再構築時の13ルール・PR証拠付き）

> 本節は旧 jpydf の失敗（§1・§4.3 AVOID）から導いた再構築時の教訓と証拠を残す。現在の規範は [`Development-Plan.md`](../../engineering/plans/Development-Plan.md) §1 と [`Liquity-v2-Core-Spec.md`](../../protocol/product/spec/Liquity-v2-Core-Spec.md) の `CORE-MOD-*` 台帳を正とする。

1. **コアの transferFrom / 加算に `if(gas>0)` を入れない**（gas=0 は定数のみ・0 送金は無害）。← `jpydf#13/#14`。
2. **JPY 換算を upstream feed（`MainnetPriceFeedBase` 含む）の constructor/ロジックに焼かない**。upstream は無改変のまま継承し、**新規 DF 基底サブクラス**で JPY 換算を足す（編集でなく拡張）。← `jpydf#1`。
3. **BoldToken の contract 名・ファイル名・識別子は upstream のまま**。可視名は `_NAME`/`_SYMBOL` のみ。← `jpydf#9`。
4. **redemption/トークン不一致を CollateralRegistry/RedemptionHelper/IActivePool の改変で直さない**。真因は deploy のトークン登録。← `jpydf#38`→`jpydf#54`。
5. **AddressesRegistry に vault/dToken/underlying を注入しない**（既存 `collToken` + deploy ローカルで足りる）。← 旧 develop の M 違反。
6. **NUM_BRANCHES は最終本数（8）で固定。縮小デプロイ禁止**。← `jpydf#50`。
7. **件数/配列長定数の変更時は旧値 literal（`i<3`,`[2]`）を全 grep**。catch-all else は `revert`（fail-closed）。← `jpydf#47`/`jpydf#60`。
8. **承認＝正しさではない**（`jpydf#38` は member 承認でマージ）。再構築初期は凍結リストの `base` byte-identical を CI で強制した。現在は JPYdf canonical surface guard と [`Liquity-v2-Core-Spec.md`](../../protocol/product/spec/Liquity-v2-Core-Spec.md) の `CORE-MOD-*` 台帳、diff review、parity test で許容差分を管理する。
9. **Pyth/payable feed を作らない**（単一 Chainlink）。← `jpydf#39`/`jpydf#44`。
10. **手順・順序は実コードでも実測する**。規範は仕様とし、doc↔code 不一致は監査所見として解消する。実装の現状だけを理由に承認済み仕様を書き換えない。
11. **仕様の正本 = リポジトリ `deltaforesight/jpydf-v2` の `documents/jp/*.md`**（[`Development-Plan.md`](../../engineering/plans/Development-Plan.md) の `../*.md` 表記はこれを指す）。canonical はチーム共有の `develop`、各自のローカルフォルダはその git 作業ツリー（作業コピー）で、編集は該当 `.md` を直接直し commit→push で `develop` に反映する。実装・レビュー・監査はこの spec を一次情報として読み、Oracle/Parameters 等の不整合も `documents/jp/*.md` を直す。ディレクトリ案内・一覧は `[../../README.md](../../README.md)`。
12. **各 commit・各 PR で CI（`forge build`＋`forge test`＋Core JPYdf surface guard）が green であることを必ず確認する**。red のままマージしない。新 repo `jpydf-v2` は commit 1 からクリーンなので CI green を維持可能（旧 develop が何ヶ月も赤を継承していた状態を再現しない）。fork 系テストは `MAINNET_RPC_URL` 前提のものを CI で実走させ green を確認。「ローカルで通った」だけで完了としない（[`Development-Plan.md`](../../engineering/plans/Development-Plan.md) §5 完了定義）。**影響を受ける既存テストの適応はルール 13 に従い同一 PR 内で完了させる**。
13. **テストは「都度・全件緑」を維持する（後段フェーズへ先送りしない・skip で逃げない）**: 各フェーズでパラメータ／機能を 1 つ実装するたびに、その変更で影響を受ける **forkless・Mainnet fork・E2E の全 upstream BOLD テスト**（trove debt／担保額・期待値・revert 条件・境界アサート・invariant handler の bound〔例: `BORROWED_MAX`〕・anchored fuzz 反例 replay 等）を**同じ PR 内で全て修正**し、`forge test` を常に緑に保つ。「BOLD が想定していたテストケースが常に通る」状態を**毎ステップ維持**する。**テスト適応を後段フェーズへ先送りすること、および新規 `vm.skip` で回避することは禁止（例外なし）**。fork テストは `MAINNET_RPC_URL`／public アーカイブ RPC（pinned block は blastapi、latest は publicnode）で実走検証し、実プール swap がある場合は担保と pool seeding を同率でスケールしてスリッページを保存、サイズ依存の絶対許容のみスケールする（比率・金利・seed は据置。教訓: fork テストを carve-out で赤のまま放置しない）。← 本方針（2026-06-06 ユーザー確定。`v2#6` で `MIN_DEBT=100_000e18` の Mainnet fork 147＋E2E＋anchored fuzz replay 11 件を **skip 撤回して全適応**＝carve-out なしで全 CI 緑を実証）。

---

## 付録. 実測コマンド（再現用）
```bash
# 旧develop のコア改変の実測（分析の根拠）
git clone --quiet https://github.com/deltaforesight/jpydf.git <dir> && cd <dir>
git diff origin/base origin/develop --name-status -- contracts/src   # A18 / M15
# 新repo の baseline 確認
gh repo view deltaforesight/jpydf-v2
```
> 実測値は head 固定時点（旧 develop=`848c6b8` / base=`d2e75c3`、新 baseline=`d62e2ea3`）。リポジトリ状態は変化するため、着手時に再取得・再検算すること。

---

> この背景・教訓がどう前向きな計画に効くか（ガードレール・Phase ToDo）→ [`Development-Plan.md`](../../engineering/plans/Development-Plan.md)
