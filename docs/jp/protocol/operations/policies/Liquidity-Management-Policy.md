# 流動性管理方針

## 0. 位置づけ

本書は JPYdf/USDC Uniswap v4 LP の launch 後の自己 B/S からの流動性管理方針（採用 infra、 レンジ設計、 リバランスロジック、 bot 実装方針）を定める。Day-1 の会社自己資金配分額は [`Day1-Self-BS-Launch-Commitment.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Launch-Commitment.md)、算定根拠は [`Day1-Self-BS-Initial-Liquidity-Plan.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Initial-Liquidity-Plan.md)、DEX route 仕様は [`Liquidity-Route-Policy.md`](../../product/policies/Liquidity-Route-Policy.md)、B/S 配分の枠組みは [`Balance-Sheet-Liquidity-Allocation-Policy.md`](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md) を正本とする。

本書は LP 管理戦略の方針を定める文書であり、launch broadcast / Safe role / fork evidence の正本ではない。IPOR Fusion / ALPHA bot を Day-1 で実稼働させるには、本書 §2.1 の activation gate を満たし、[`Mainnet-Launch-Operation-Gate.md`](../../launch/gates/Mainnet-Launch-Operation-Gate.md)、[`Mainnet-Initial-Configuration-Checklist.md`](../../launch/gates/Mainnet-Initial-Configuration-Checklist.md)、[`Mainnet-Safe-Role-Assignment-Gate.md`](../../launch/gates/Mainnet-Safe-Role-Assignment-Gate.md) 側の evidence に反映する必要がある。

本書は Issue #318 の決定事項を集約する。

## 1. 設計方針

以下の 3 制約を 守った上で、 「ユーザーの swap 体験を 損なわず、 自社 B/S の IL を 抑える」 配分を選定する。

| 制約 | 値 | 出典 |
| --- | --- | --- |
| LP 構造 | 複数 position による user depth / inventory / unwind の分離 | Issue #318 (= 二段構え原案) を本書 §6 で一般化 |
| 年間 IL 上限 | 10% | Issue #396 |
| swap depth 重視範囲 | 価格 0.1% / 0.5% を 軸に評価 | 本書 §2 |

「price ±0.1%」 と 「price ±0.5%」 の swap depth を 重視する理由:

- **±0.1%**: 現在価格近辺の depth が 厚いほど、 平常時の小口 swap で peg が動きにくい。 peg micro-defense と user UX の 指標。
- **±0.5%**: Liquity v2 base redemption fee = 0.5% に対応。 LP がここまで peg を守れれば、 第三者 redemption の経済合理性が成立せず、 redemption 発火を 構造的に抑えられる。 protocol 自律性の 指標。

## 2. 採用方針: IPOR Fusion

LP 管理 infra の採用方針は **IPOR Fusion** とする。リバランスロジック (= Alpha role) は 自社 bot で 内製化する。

ただし、これは **条件付きの採用方針** である。Uniswap v4 LP 用 fuse、Plasma Vault deploy、role assignment、bot config、fork evidence が揃うまでは、IPOR Fusion / ALPHA bot を launch PASS 条件として扱わない。gate 未達の場合、Day-1 は既存 runbook の `LP_OWNER` が管理する Safe-controlled / manual / static な JPYdf/USDC Uniswap v4 LP として開始し、IPOR Fusion は post-launch activation として扱う。

採用理由:

| 項目 | IPOR Fusion | Arrakis Pro |
| --- | --- | --- |
| 管理手数料 (年、 1 億円 LP 想定) | 0.3% × 1 億 = 30 万円 | retainer $5,000/月 ≒ 900 万円 |
| パフォーマンス手数料 | 2% | 別途 |
| レンジ管理 logic | 自社内製 (= Alpha role) | Arrakis 側に委託 |
| Uniswap v4 fuse | 要望ベースで実装 (= IPOR 回答)。公開 repo / fork evidence 未確認の間は activation gate | 既存 |

自社で リバランスロジックを 持つ前提では IPOR Fusion が cost 効率で 圧倒的に優位 (= 約 1/30)。 Arrakis Pro は 並行 交渉継続するが、 採用判断は IPOR Fusion を 主軸とする。

AWS-only の bot / signer で直接 LP position を動かす案は、IPOR Fusion の代替ではなく別設計として扱う。AWS は KMS / HSM、scheduler、monitoring、private relay、alert には適しているが、資金 custody、許可された action の on-chain 制限、asset / venue allowlist、share accounting、role revoke、pause を AWS だけで担保するものではない。

| 観点 | IPOR Fusion + AWS bot | AWS-only direct LP manager |
| --- | --- | --- |
| custody / 実行境界 | Plasma Vault / fuse / role により on-chain で許可 action を限定し、ALPHA key の権限を LP 管理範囲に閉じる | bot key / Safe module / custom executor の設計に依存。誤設定時に hot key の権限が広がりやすい |
| asset / venue 制限 | substrate / asset list / fuse allowlist で JPYdf / USDC と対象 pool key を制限できる | off-chain config と signer 運用に依存し、on-chain allowlist を別実装する必要がある |
| accounting / auditability | Vault / position / fuse call 単位で on-chain accounting と evidence を残しやすい | 独自台帳・bot log・Safe tx の突合が中心。監査対象の custom code が増える |
| emergency control | OWNER / ATOMIST / GUARDIAN / ALPHA revoke / pause の role model を使える | 同等機能を Safe module / custom contract / runbook で別途作る必要がある |
| 実装 risk | Uniswap v4 fuse readiness と IPOR dependency が activation gate | custom executor / custody / accounting を自前 audit する必要があり、Day-1 の scope が膨らむ |

したがって IPOR 採用理由は「AWS を使わないため」ではない。AWS は ALPHA bot の実行基盤として使い、IPOR は資金を動かせる範囲を on-chain で狭めるために使う。IPOR の Uniswap v4 fuse / role / fork evidence が揃わない場合は、本書どおり Safe-controlled / manual / static LP に fallback し、AWS-only の自動 direct LP manager を無審査で代替投入しない。

### 2.1 Day-1 activation gate と fallback

IPOR Fusion / ALPHA bot を Day-1 で実稼働させるには、少なくとも以下を launch evidence として揃える。

1. **Uniswap v4 fuse readiness**: JPYdf/USDC v4 LP の new position / modify / collect / withdraw / required swap を扱う fuse 一式が実装済みで、commit / bytecode / deploy address / internal review / fork-run evidence が残っている。
2. **Vault readiness**: Plasma Vault が JPYdf / USDC のみを substrate / asset list として扱い、想定外 token / venue / hook へ資金が移動しないことを fork-run で確認済み。
3. **Role readiness**: OWNER / ATOMIST / GUARDIAN / FUSE_MANAGER / ALPHA / WHITELIST の保有者、Safe threshold、pause / cancel / revoke 手順が Safe role assignment package に入っている。
4. **Bot readiness**: ALPHA key は AWS KMS or HSM 管理、bot config hash、tx relay、max recenter / max withdraw / cooldown / emergency stop / alert 経路が evidence 化されている。
5. **Route readiness**: JPYdf/USDC Uniswap v4 pool は `fee = 500` / `tickSpacing = 10` / no hook を前提に pool key / route config / allowance cleanup が freeze 済み。
6. **Operational readiness**: fair FX anchor / pool price / TWAP / protocol oracle の参照元と相互乖離ガード、LP position 別のレコンシリエーション、recenter / swap / redemption / borrow の action selection、短期 order-flow / inventory model、bot と redemption / liquidation monitoring の衝突時の優先順位、manual intervention、incident notification owner が runbook に入っている。

いずれかが未達の場合、Day-1 は IPOR Fusion / ALPHA bot を稼働させない。launch は `Mainnet-Launch-Operation-Gate.md` の JPYdf/USDC v4 liquidity evidence と `LP_OWNER` 管理に限定し、本書の β パラメータは post-launch activation の初期候補として保持する。

## 3. 採用パラメータ

5 年 USD/JPY daily data によるバックテスト と 検討過程 (§4) を経て、 以下を activation gate PASS 時の初期採用候補とする (= 哲学別 3 候補の **balance 案**)。fee 前提は [`Liquidity-Route-Policy.md`](../../product/policies/Liquidity-Route-Policy.md) の Day-1 標準である `fee = 500` / `tickSpacing = 10` / no hook とする。

| 項目 | 値 |
| --- | --- |
| Tier 1 (狭) range | ±0.5% |
| Tier 2 (広) range | ±9% |
| Tier 1 への配分 | 1 億 LP のうち 15% (= 1,500 万円相当) |
| recenter trigger threshold | レンジ端の 70% (= ±0.35% / ±6.3% で trigger) |
| recenter cooldown | Tier 1: 1 時間、 Tier 2: 24 時間 |
| 緊急 stop | 1 時間で 1% 価格動いたら bot pause + alert |

上表の Tier 1 / Tier 2 は backtest 用の liquidity shape であり、production の LP position 数を固定するものではない。MM bot の実 position 数は §6.1 の通り user depth / inventory / unwind / ops evidence から決める。

**性能** (= バックテスト結果、 5 年 USD/JPY 過去 data):

| metric | 値 |
| --- | --- |
| 年間 IL | -6.94% (= 10% 上限への margin 3pp) |
| price 0.1% 動かすために必要な swap size | 約 108 万円 |
| price 0.5% 動かすために必要な swap size | 約 522 万円 |
| price 1.0% 動かすために必要な swap size | 約 757 万円 |
| recenter 頻度 | 約 131 回/年 (= 月 11 回) |

## 4. 検討過程

### 4.1 アプローチ

「ある程度の網羅性 と 過剰適合への 配慮」 を 持って 候補を 絞る。 launch までの時間を 鑑み、 厳密な data science (= Monte Carlo simulation、 fee revenue モデル化、 redemption coupling 等) は 後追い 別 task とする (= §8 limitation 参照)。

### 4.2 ステップ

1. **制約条件 確定**: §1 の 3 制約を 入力とする。

2. **param grid 設計**: Tier 1 range (0.2% 〜 2.0%、 19 値) × Tier 2 range (2% 〜 10%、 17 値) × Tier 1 配分 (5% 〜 30%、 6 値) × threshold (50% 〜 80%、 4 値) = **7,752 候補**。

3. **バックテスト**: USD/JPY 5 年 daily data (2021-06 〜 2026-06、 +45.9% 円安期) を input に、 各候補で Uniswap v3 / v4 concentrated LP simulator を回し、 年間 IL、 swap depth、 recenter 頻度を 集計。

4. **IL 制約 filter**: 年間 IL > 10% の候補 (= 2,892 個) を 棄却。 残り **4,836 候補**。

5. **過剰適合 filter (= walk forward 検証)**: 5 年 data を train 期間 (2021-2024) / test 期間 (2024-2026) に分割、 train で 良かった params が test で 大きく劣化する candidates (= train/test IL 差 > 3pp) を 棄却。 残り 約 3,000 候補。

6. **Pareto frontier 抽出**: IL と 0.1% / 0.5% / 1% swap depth の 3 軸 trade-off で、 他に dominated されない候補を 抽出。 残り 129 候補。

7. **3 候補 選定 (= 哲学別)**: Pareto frontier 上から、 設計思想 (= ops 哲学 + capital risk) が 異なる 3 候補を 抽出 (§5)。

8. **追加検証**: sensitivity (= 採用候補の params を ±20% 揺らした際の 性能安定性)、 stress test (= 過去 worst event 集中シナリオ) で 採用候補の robustness を 確認。

### 4.3 評価軸の 選択

「価格を 0.1% / 0.5% 動かす swap size」 を 主要 metric にした。 0.1% は user 平常時 UX、 0.5% は protocol redemption 線という 意味で、 両者を 同等に重視する 立場で 候補絞り込みを行った。 1.0% は 補助 metric とした。

参考までに、 0.1% depth を 過度に優先した場合 (= 例 weight 80:20 等)、 採用候補は Tier 1 ±0.2% の 候補 (= 狭い Tier 1 で depth_p01 が 大きくなる) が ほぼ全てを 占める結果となる。 これに対し 0.1% と 0.5% を 同程度に重視する 場合は、 Tier 1 = 0.5% 〜 1.0% の 中庸 width が Pareto frontier 上で 採用されやすい (= §5 採用 β は Tier 1 = ±0.5%)。 weight を どこに置くかは 「user UX 重視 / protocol 自律性 重視」 の trade-off で、 本書は 「両方 同等」 の立場を 採る。

## 5. 採用候補と 比較

検討過程 (§4) を経て、 設計思想が 異なる 3 候補を 抽出した。 **β (balance) を activation gate PASS 時の初期採用候補** とする。

| 案 | Tier 1 range | Tier 2 range | Tier 1 配分 | threshold | 年間 IL | depth 0.1% | depth 0.5% | depth 1% | recenter/年 | 設計思想 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| α (低運用負荷) | ±2.0% | ±10% | 5% | 60% | -4.18% | 49 万 | 245 万 | 491 万 | 36 (月 3 回) | 単一広 tier に近い、 ops 最小 |
| **β (balance、 採用)** | **±0.5%** | **±9%** | **15%** | **70%** | **-6.94%** | **108 万** | **522 万** | **757 万** | **131 (月 11 回)** | **中庸 二段構え、 0.1%/0.5% depth 両立** |
| γ (depth 重視 active) | ±0.2% | ±8% | 20% | 80% | -8.94% | 227 万 | 588 万 | 799 万 | 194 (月 16 回) | Tier 1 狭め + 高配分、 small swap に強い |

**β 採用理由**:

- IL margin 3pp (= 上限 10% に対し 余裕あり、 一方で α の 5pp に近い 安全側)。
- depth 0.5% = 522 万円 (= protocol redemption 線 を 平常時 swap で 越えない target を 達成)。
- depth 0.1% = 108 万円 (= 100 万円規模の retail user swap で peg が ほぼ動かない)。
- recenter 頻度 月 11 回 (= α より 多いが γ より少ない、 操作負荷 中庸)。
- 採用 params が 数学的 結果 (= grid search) の Pareto 上、 直感ではない。

α / γ の 採用可能性:

- α は 「ops 最小 + IL 最小」 の哲学。 ただし depth 0.5% が 245 万円のため、 中口 swap (= 数 1,000 万) で redemption 線に 達しやすい。 ops capacity に強い制約がある 場合に 検討余地あり。
- γ は 「small swap UX + 大口対応」 の哲学。 ただし IL margin 1pp で 上限ぎり、 月 16 回 recenter で 操作負荷 大、 後述 (§7) の DEX swap 手数料 影響も 大きい。 launch 後の改善 余地として 残す。

## 6. リバランス / レコンシリエーション ロジック (β 採用想定)

ALPHA bot は **pool price をそのまま中心価格として追従しない**。JPYdf/USDC pool price は需給、redemption pressure、LP 薄さ、単発大口 swap の影響を受けるため、これを中心に recenter すると depeg を追認する可能性がある。recenter の中心は fair FX anchor（JPY/USD または USD/JPY の外部 reference）であり、pool price / TWAP は fair anchor からの乖離と execution slippage を測るために使う。

本書の LP manager は、単に chart を追う range bot ではなく、JPYdf / USDC 在庫を持つ market maker として扱う。AMM が user flow を受けた直後に同じ pool で機械的に hedge / rebalance すると、adverse selection（例: user から USDC を受け取った直後に USDC の fair value が下がり、悪い在庫だけが残る）を実現損として固定化する可能性がある。したがって production bot は、pool swap だけで在庫を解くのではなく、自然相殺、Liquity-native な redemption / borrow / self-mint、manual top-up を含む action を比較する。

価格入力は次の 4 つに分ける:

| 入力 | 役割 | Day-1 / activation 時の扱い |
| --- | --- | --- |
| fair FX anchor | LP range の中心価格。JPY/USD または USD/JPY reference と USDC/USD reference を合わせて JPYdf/USDC の fair price を決める | source、freshness、fallback、operator sign-off を activation evidence で freeze。stale / 不整合時は recenter しない |
| USDC/USD reference / stablecoin health | USDC を 1 USD とみなせるか、または USDC depeg を fair price / inventory risk に反映すべきかを判断する | USDC/USD source、depeg threshold、stale threshold、fallback を freeze。depeg / stale 時は recenter と bounded swap を止め、manual review |
| pool spot / TWAP | 現在の market deviation、swap slippage、MEV / manipulation を見る | fair anchor からの乖離が大きい場合は recenter ではなく pause / manual review |
| core oracle / protocol state | redemption / liquidation / branch health の判断材料 | LP bot の中心価格そのものではなく、redemption / liquidation action selection の補助入力。fair anchor との乖離を §6.4 の risk limit で監視し、上限超過時は recenter / bounded swap を止めて manual review |

fair FX anchor と protocol oracle 価格（`fetchPrice` / `fetchRedemptionPrice`）は仕様上乖離し得る（[Mainnet Launch Risk Gate](../../launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-001)のとおり、JPY/USD feed 障害時は protocol oracle 側が`lastGoodJpyRate`でsoft-freezeする）。redemption の受領価値は protocol oracle 価格で決まるため、乖離が上限を超えている間は fair anchor 単独で「JPYdf が安い」と判定せず、recenter / bounded swap / redemption 比較を止めて manual review に送る。

0xArchive の market snapshot / open interest / funding は補助観測として扱い、単独では fair FX anchor、model label、または自動 action の信頼根にしない。collector の `collectedAt` は全 request の完了時刻とし、request 開始時刻は `collectionStartedAt` として分離する。評価時は report の生成時刻だけでなく各 response 内の source timestamp を検証し、timestamp の timezone 欠落、不正、collection 完了より未来、または最古 source age が 30 秒を超える場合は fail closed で `pause` とする（正常上限 5 秒、caution 上限 30 秒）。block 単位の履歴を model に使う場合は、provider timestamp だけで位置合わせせず、block number、canonical node の block timestamp、native snapshot / diff replay の内容一致を別 evidence で証明する。

### 6.1 複数 LP position の扱い

MM bot は複数 LP position を持つことを基本設計とする。単一 position だけで user slippage、peg defense、inventory skew、unwind を同時に扱うと、range 変更のたびに全流動性を動かす必要があり、slippage 悪化、MEV、IL 実現、会計不透明化を招きやすい。

本書の Tier 1 / Tier 2 は backtest 上の liquidity shape を表す抽象であり、production の position 数を 2 本に固定するものではない。実際の position 数は、user-facing depth、inventory skew、自然相殺待ち、hedge、unwind、gas / accounting 負荷を踏まえて activation evidence で決める。passive wide、active narrow、intervention-only、unwind bucket などを分けることは自然だが、position を増やすほど accounting / gas / fuse call / reconciliation が増えるため、各 position の目的、上限、停止条件を明示する。

運営者としての制約は、自己 B/S の IL 最小化だけではない。JPYdf/USDC は user swap の主要 route であるため、position 設計は user slippage と route integrity を守る必要がある。狭い active position を抜く、inventory skew を作る、または hedge のために pool swap する場合でも、user が見る実効 depth、0.1% / 0.5% depth、fair anchor からの乖離、route の最良性を壊してはならない。user slippage guard を破る position update は、自己 B/S には有利でも ALPHA 自動実行不可とする。

各 position は少なくとも次を tracking する:

- position id / owner / vault / tick range / liquidity / token0-token1 composition
- intended role（micro peg defense、wide passive depth、intervention、unwind 等）
- initial notional、現在 notional、uncollected fees、realized fee、realized IL
- expected user depth contribution（0.1% / 0.5%）、slippage guard、withdraw / resize limit
- last recenter、last collect、last rebalance tx、想定外 token / allowance / hook が無いこと

### 6.2 action 前のレコンシリエーション

bot は recenter / rebalance の前に、Vault 残高、LP position、pending fee、allowance、pool key、fair FX anchor、pool spot / TWAP を再照合する。期待値と on-chain readback がズレる場合、ALPHA は action を止め、operator に alert する。

最低限の照合項目:

- Vault が JPYdf / USDC 以外を持っていない、または持つ理由が evidence 化されている。
- LP position ごとの token composition / uncollected fee / liquidity が前回 report から連続している。
- position update 後も user-facing 0.1% / 0.5% depth と slippage guard が下限を下回らない。
- recenter に必要な JPYdf / USDC inventory と、実際の idle balance / position withdraw 後見込みが一致する。
- `fee = 500` / `tickSpacing = 10` / no hook の pool key と一致する。
- fair FX anchor と USDC/USD reference が stale / outlier / depeg 状態ではない。
- LP operation に使う swap / redemption / borrow の max amount、max slippage、operator approval が設定範囲内である。

### 6.3 action selection: swap だけを前提にしない

recenter / rebalance 時の inventory 調整は、常に pool swap が最良とは限らない。JPYdf/USDC pool は唯一の external execution venue だが、DeltaForesight は同時に dUSDC / dwstETH branch、bootstrap Trove、redemption 経路、SP を持つ。特に dUSDC branch が開いている状況では、JPYdf inventory を pool で買うより、健全な dUSDC Trove から追加 borrow / self-mint する方が安い場合がある。また JPYdf が fair value より安い場合、redemption fee、受領 collateral、dToken unwrap、売却 route、時間差 risk を差し引いても、pool swap より redemption の方が安い場合がある。

ただし redemption は branch 配分、unbacked portion、`minColl`、oracle freshness、shutdown 状態、dToken / underlying 処分に依存し、任意の dUSDC collateral だけを必ず取れる仕組みではない。borrow / self-mint も debt、ICR / LTV、rate、upfront fee、redemption ordering、cap headroom を悪化させる。したがってこれらは「pool swap より安い可能性がある在庫調達手段」であって、無条件の bot 自動実行対象ではない。

bot / operator は以下の all-in cost と risk を比較して action を選ぶ。

| Action | 使う場面 | 主な cost / risk | Day-1 権限境界 |
| --- | --- | --- | --- |
| Natural offset / wait | 在庫が risk limit 内で、短時間に反対 flow が来る確率が高い場合 | hedge 遅延中の fair FX / pool move、inventory limit 超過 | ALPHA は待機のみ可。risk limit 超過時は不可 |
| LP modify only | fair anchor が range 内で、inventory が十分な場合 | gas、position fee collect / accounting | ALPHA 実行可 |
| Pool swap | 小額の inventory imbalance、pool が fair anchor 近辺の場合 | pool fee、slippage、MEV、depeg 追認 risk | ALPHA 実行可。ただし max swap / slippage / fair deviation guard 必須 |
| Redemption | JPYdf が fair value より安く、redemption fee / collateral disposal cost を差し引いて swap より有利な場合 | redemption fee、branch 配分、dToken / underlying disposal、oracle / shutdown、collateral price risk、時間差 | Day-1 は原則 Safe / manual。ALPHA 自動実行は別 audit / runbook 後 |
| Additional borrow / self-mint | JPYdf inventory を pool で買うより、健全な dUSDC / dwstETH Trove から低 APR で調達する方が安い場合 | debt 増加、ICR / LTV 低下、upfront fee、redemption ordering、cap / collateral availability | Day-1 は Safe / manual。ALPHA 自動実行は不可 |
| Manual top-up / withdraw | 大口 flow、A 社対応 (= [`Day1-Self-BS-Initial-Liquidity-Plan.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Initial-Liquidity-Plan.md) の日系 DAT 企業 A 社)、emergency peg defense、bot pause 時 | signer availability、会計 owner、repayment / unwind plan | Safe / manual |

したがって標準フローは次の順序にする:

1. **Stop / stale check**: fair FX anchor stale、USDC/USD reference の stale / depeg、pool spot が fair anchor から大きく乖離、fair anchor と protocol oracle 価格の乖離が上限超過、1 時間以内に 1% 以上の異常変動、oracle / route / role readback 異常があれば ALPHA を pause し manual review。
2. **Reconcile**: Vault / LP position / idle balance / pending fee / allowance / expected inventory を照合。
3. **Need classification**: 必要なのが range recenter なのか、inventory imbalance 解消なのか、peg defense なのか、大口 flow 対応なのかを分類。
4. **Order-flow check**: 直近 flow が toxic か、短時間で自然相殺される可能性が高いか、inventory limit に余裕があるかを確認。
5. **Action compare**: wait、LP modify、pool swap、redemption、additional borrow / self-mint、manual top-up の all-in cost を比較。ALPHA が許可されるのは wait、LP modify (= fee collect を含む)、bounded pool swap まで。
6. **Execute / report**: action 後に LP state、realized IL、fee、borrow / redemption / swap cost、inventory delta、adverse selection cost を daily report と incident log に反映。

### 6.4 market-making model

β の range / threshold は liquidity shape の初期候補であり、production MM bot の完成条件ではない。実運用で user flow を受ける場合、bot は少なくとも以下を推定し、hedge / rebalance / wait を選ぶ。

| 予測対象 | 目的 | action への使い方 |
| --- | --- | --- |
| 次の 1 block（≒ 12 秒）で反対 flow が来る確率 | 受けたばかりの在庫を次 block で hedge すべきか、自然相殺を待つべきかを判断する | 確率が高く在庫が limit 内なら wait。低い、または fair FX が同方向に動く場合は hedge / manual escalation を検討 |
| 次の数 block（≒ 1 分以内）で自然相殺される expected notional | 小口連続 flow を pool swap で過剰 hedge しないため | expected offset が在庫 imbalance を十分吸収するなら LP modify / hedge を遅らせる |
| 次の数十 block（≒ 数分）の net customer flow | MM として持つべき JPYdf / USDC inventory と liquidity skew を決める | net flow が片方向に偏る場合は range / inventory / borrow / redemption action を比較 |

horizon は秒ではなく block で定義する。on-chain の swap event は block 粒度（≒ 12 秒）でしか観測できず、bot の執行も private relay 経由で block 単位となるため、sub-block の予測・hedge は前提にしない。具体的な block 数は Phase 1 の block 粒度 replay で較正する。

入力候補:

- JPYdf/USDC pool の swap event（方向、size、execution price、fee、wallet / route 種別の集計）
- fair FX anchor と短期変化率
- USDC/USD reference と stablecoin depeg / liquidity signal
- pool spot / TWAP と fair anchor 乖離
- LP position ごとの token composition と idle inventory
- redemption activity、base rate、branch unbacked、dUSDC / dwstETH borrow capacity、SP coverage
- gas、mempool / private relay 状態、直近 failed tx / reverted quote

最低限の risk limit:

- JPYdf / USDC inventory delta の上限
- 1 block / 数 block / 数十 block horizon の expected loss 上限
- fair anchor からの pool deviation 上限
- fair anchor と protocol oracle 価格の乖離上限
- USDC/USD depeg / stale guard
- single action の max notional、max slippage、max borrow、max redemption
- same direction flow が続いた時の kill switch

production activation 前に、trade-level replay で `natural offset rate`、`adverse selection cost`、`hedge cost`、`inventory limit breach`、`realized IL + fee` を測定する。日次 USD/JPY path による LP range バックテストだけでは、MM bot の妥当性 evidence として不足である。

### 6.5 recenter trigger

β パラメータの threshold / cooldown は fair FX anchor に対して適用する。pool price が range 端に近づいた場合でも、fair anchor が動いていないなら「recenter」ではなく「pool deviation / peg pressure」として扱う。

1. **Tier 1 recenter trigger**: fair FX anchor が Tier 1 中心から ±0.35% 以上動いた、かつ直前 recenter から 1 時間以上経過し、pool spot / TWAP が fair anchor から許容範囲内なら Tier 1 を fair anchor 中心で recenter。
2. **Tier 2 recenter trigger**: fair FX anchor が Tier 2 中心から ±6.3% 以上動いた、かつ直前 recenter から 24 時間以上経過し、pool spot / TWAP が fair anchor から許容範囲内なら Tier 2 を fair anchor 中心で recenter。
3. **Pool deviation trigger**: pool spot / TWAP が fair anchor から一定以上乖離している場合、ALPHA は recenter せず、peg defense / redemption / borrow / manual top-up の action selection に送る。
4. **24 時間ごとの健全性 inspect**: bot が position 別 state、recenter 履歴、IL 累積、fee 収入、pool deviation、fair anchor freshness、inventory delta を確認し、daily summary report を発する。異常検知時は alert。通常時は action なし。

**threshold (= range 端の 70%)** はバックテストで Pareto frontier 上で採用された値であり、pool price を追いかけるルールではない。fair anchor が動いたときに range が片側に寄るのを防ぐための予防線である。

**cooldown (= Tier 1 1h、Tier 2 24h)** は短期 FX noise と pool manipulation による連続 recenter を防ぎ、IL を無駄に多発実現させないため。短時間で何度も recenter すると各回ごとに IL を確定させ、累積で大きな loss となる。

## 7. cost 構造 (β 採用想定、 年間)

| 項目 | 金額 | 補足 |
| --- | --- | --- |
| IL (= LP 含み損) | 約 694 万円 (= 6.94%) | バックテスト結果 |
| Gas cost (= recenter transaction) | 約 34 万円 (= 0.34%) | 131 回 × 約 2,560 円 / tx (= 200K gas × 20 gwei × ETH ¥600k) |
| DEX swap 手数料 (= bounded swap を使った場合) | 約 66 万円 (= 0.66%) | 1 億 LP × 10% (= recenter 1 回あたり swap 対象比率の保守仮定) × 131 回 × 0.05% (= `fee = 500` / PR #643)。全 recenter を pool swap で解く前提の上限寄り試算 |
| IPOR Fusion 管理手数料 | 約 30 万円 (= 0.3%) | mgmt fee 0.3% × 1 億 |
| IPOR Fusion パフォーマンス手数料 | 変動 | 運用益に対し 2% |
| **参考合計 (β / IPOR / bounded swap 仮定)** | **約 824 万円 (= 8.24%)** | IPOR activation 済み、かつ bounded swap を使う前提の参考値。通常期待値や固定費ではない |

**DEX swap 手数料の 注**: Day-1 route は `fee = 500` / `tickSpacing = 10` / no hook を標準とする。Uniswap の既存 pool の fee tier は後から変更できない。将来 0.3% など別 fee tier の JPYdf/USDC pool が第三者に作られる場合は、それは別 pool / 別 pool key であり、route が分散または移る可能性として扱う。運営 bot は activation evidence で freeze した pool key だけを対象にし、別 pool を使う場合は route policy、pool key、depth、fee、MEV、LP accounting を別 PR で再評価する。実運用では pool swap、redemption、additional borrow / self-mint、manual top-up の all-in cost を比較するため、この項目は「swap を選ぶ場合の cost」であり、在庫調整の固定ルートではない。

LP fee 収入 (= 他の swap user が 支払う 手数料の LP 取り分) は 本書の cost 試算に 含まれていない (= §8 limitation 参照)。 fee 収入が IL を 部分相殺する可能性は あるが、 launch 直後の swap volume を 確実に予測できないため、 保守側に 試算する。

## 8. limitation (= 既知の 簡略化)

本検討では launch までの 時間制約を 鑑み、 以下の 厳密性は 後追い とする:

- **データ ソース**: USD/JPY 為替 daily data を proxy として使用。 実際の JPYdf/USDC pool 価格は、 為替に加えて 需給・redemption pressure・user 行動の影響を受けるため、 USD/JPY と 完全には 一致しない。
- **データ期間**: 過去 5 年 (2021-06 〜 2026-06) は 一方向 (= +45.9% 円安) のトレンド期間。 円高 regime や 大規模 depeg event は 含まれていない。
- **LP fee 収入 未モデル**: バックテストの IL 計算には pool fee 収入を 含めていない。 実運用では LP は swap 手数料を 受領するため、 net IL は バックテスト値より 改善する 想定。
- **Redemption interaction 未モデル**: JPYdf 価格が depeg した際に redemption が peg を 自律調整する dynamics を simulate していない。 実運用では LP と redemption が 協調して peg を 守るため、 LP 単独の負荷は バックテスト想定より 軽い 想定。
- **fair FX anchor / pool price 分離 未モデル**: バックテストは USD/JPY path をそのまま中心価格に使った簡略化であり、pool spot が depeg した状態で fair anchor と乖離する case、ならびにそのときの pause / redemption / borrow / manual top-up の action selection は未検証。
- **USDC depeg 未モデル**: バックテストは USDC を 1 USD とみなしており、USDC/USD が 1 から外れた場合の fair anchor、bad inventory、manual unwind は未検証。
- **在庫調達手段 未モデル**: recenter 内 swap を一律 cost としているが、実運用では additional borrow / self-mint、redemption、manual top-up が pool swap より有利な場合がある。これらは debt / redemption / accounting / signer risk を伴うため、別 runbook と fork evidence が揃うまで ALPHA 自動実行しない。
- **MM order-flow model 未モデル**: user flow の adverse selection、次 block の反対 flow 確率、数 block の自然相殺、数十 block の net customer flow を model 化していない。日次 FX path の LP range backtest は liquidity shape の検討であり、production MM bot の hedge / rebalance policy を正当化しない。
- **単一 path simulation**: 過去 5 年の 1 系列のみ で評価。 Monte Carlo 等の 多 path simulation は実施せず。
- **MEV / sandwich attack 未モデル**: recenter tx が public mempool で 観測された場合の MEV risk は 試算外。 §9 で 対策方針を述べる。

これらの簡略化により、 採用 params (= β) が 実運用で 想定通り機能するかは launch 後の 観察で確認する必要がある (§10)。

## 9. IPOR Fusion Vault 設計 と bot 実装方針

### 9.1 採用 Vault と 権限構造

Activation gate PASS 時は IPOR Fusion の **Plasma Vault** を採用する。 vault は role-based access control (= `IporFusionAccessManager`) で 権限管理される。 主要 role と保有先の初期案は以下 ([IPOR-Labs/ipor-fusion `contracts/libraries/Roles.sol`](https://github.com/IPOR-Labs/ipor-fusion/blob/main/contracts/libraries/Roles.sol) を参照):

| role | 主な権限 | activation 時の想定保有先 |
| --- | --- | --- |
| OWNER (1) | Atomist / Guardian の任命など 最上位管理 | 自社 multisig |
| ATOMIST (100) | Plasma Vault の設定変更、 fuse manager の任命、 whitelist 管理 等 | 自社 multisig |
| GUARDIAN (2) | 緊急 pause、 timelocked operation の cancel | 自社 multisig |
| FUSE_MANAGER (300) | fuse の add / remove / balance / reward | ATOMIST 管轄 (= 必要時 multisig が委任) |
| ALPHA (200) | `PlasmaVault.execute(...)` 経由で fuse を 呼び、 rebalance を実行 | bot 用 EOA、 AWS KMS or HSM で署名 |
| WHITELIST (800) | private vault の deposit / withdraw 可否 を 制御 | 自社のみ (= 後述の 私募 phase) |

設計意図: OWNER / ATOMIST / GUARDIAN は 上位権限 (= 資金移動・設定変更) を multisig で 集合保管し、 単一鍵漏洩での 致命傷を 防ぐ。 ALPHA は 日々の rebalance を 自動実行する 必要があるため bot key とするが、 daily withdraw / rebalance 上限を ATOMIST 側で 設定し、 鍵漏洩時の被害を 限定する。これらの role は activation 前に Safe role assignment package と on-chain readback evidence に反映する。

### 9.2 関数呼び出しの 流れ

rebalance 1 回の 標準フロー:

1. bot (= ALPHA) が fair FX anchor、USDC/USD reference、pool spot / TWAP、Vault / LP position / idle balance、customer flow、redemption / borrow state を一定間隔で観測する。
2. §6 の stop / stale check とレコンシリエーションを行い、異常時は action を止める。
3. recenter trigger 条件 (= fair anchor 基準の threshold + cooldown)、短期 order-flow model、action selection (= wait / LP modify / bounded pool swap / manual escalation) を判定する。
4. trigger 充足時、 bot が rebalance 用の fuse 呼び出し列 (= 例: Uniswap v4 LP 引出 → 必要なら bounded swap → fair anchor 中心で再 deposit) を構築する。redemption / borrow / self-mint が pool swap より有利な場合でも、Day-1 ALPHA の自動実行範囲外とし、Safe / manual route へ escalate する。
5. bot が Flashbots Protect 経由で `PlasmaVault.execute([fuseCall1, fuseCall2, ...])` を送信する (= public mempool への露出回避、MEV 抑制)。
6. tx 成功後、bot が結果 (= IL 確定額、gas 消費、新 LP state、inventory delta、fair / pool deviation) を監視 dashboard に記録する。

vault setup (= activation 時に 1 回):

1. ATOMIST (multisig) が deploy 時に fuse を register する (= Uniswap v4 LP 用 fuse 一式)。
2. ATOMIST が Substrate / Asset list 等を 設定する (= JPYdf、 USDC を 承認)。
3. ATOMIST が ALPHA role を bot wallet address に grant する。
4. GUARDIAN pause / ATOMIST revoke / WHITELIST private 設定の calldata と readback を evidence 化する。

### 9.3 私募 → 公募 移行

IPOR Fusion activation 時は **私募 (private vault) として 開始** する。 WHITELIST role を 自社 wallet のみに 付与し、 外部 user の deposit は 受け付けない。activation gate 未達で Day-1 を迎える場合、Plasma Vault は使わず、既存 launch runbook の `LP_OWNER` 管理に限定する。

将来、 流動性 bootstrap campaign 等の business judgment で 公募 化する 場合は、 ATOMIST が WHITELIST 設定を 緩和 (= 全 user 許可 等) する。 公募 化に伴い、 vault に 第三者資金が 流入する 形となるため、 fee 構造・管理 / パフォーマンス手数料の 受領先・redemption window の 透明性 等の business 設計が 必要となる。 これらの 詳細は 公募 化 タイミングで 別 PR / Issue で 議論する。

### 9.4 bot 実装方針

実装の詳細は 別 PR で 設計するが、 本書では 以下の 方針を 明示する:

- **言語 / framework**: TypeScript + Node.js (= 既存 `bots/liquidator/` と整合)。 ethers.js または viem で IPOR Fusion vault に接続。
- **インフラ**: AWS Lambda or ECS Fargate (= cron / event driven)。
- **MEV 対策**: bot tx は Flashbots Protect 経由で送信し、 public mempool への 露出を 避ける。 IPOR Fusion vault は on-chain contract であり、 vault 自体の MEV 対策とは 独立 (= bot 側で対応)。
- **Key 管理**: ALPHA role 鍵は AWS KMS or HSM で 管理し、 daily withdraw / rebalance 上限を ATOMIST 側で 設定して 鍵漏洩時の被害を 限定する。 OWNER / ATOMIST / GUARDIAN は 自社 multisig。config hash / key holder / revoke 手順が evidence 化されるまで production bot として扱わない。
- **監視 / alert**: bot 状態 (= recenter 履歴、 IL 累積、 fee 収入、 fair FX anchor freshness、 USDC/USD freshness / depeg、 pool deviation、 inventory delta、 adverse selection cost、 natural offset rate、 gas cost) を 監視 dashboard (= Prometheus + Grafana or Datadog) に出力し、 異常時は Slack / PagerDuty で alert。
- **Redemption / borrow との連携**: LP recenter、redemption、additional borrow / self-mint は同じ pool deviation と inventory shortage に反応し得る。別 bot / manual runbook で動かす場合、共通の state service を介して redemption activity、borrow capacity、ICR / LTV、SP coverage、JPYdf inventory、branch unbacked、redemption fee / base rate を観測し、redemption または borrow が swap より有利な場合は LP recenter を控えて manual action に escalate する。詳細は redemption bot / treasury operation の設計 PR (= 別途) と共同で詰める。

## 10. 実装計画と Day-1 後ロードマップ

β パラメータは LP の初期 liquidity shape であり、production bot の実装仕様そのものではない。production activation では、position 数、user slippage guard、redemption / borrow / self-mint の権限境界、IPOR + AWS の責務分離を activation evidence に落としてから段階的に進める。

| Phase | 稼働範囲 | 主な成果物 | PASS 条件 |
| --- | --- | --- | --- |
| 0. Manual / static launch | `LP_OWNER` 管理の Safe-controlled static LP。ALPHA bot なし | pool key / route / allowance cleanup、fair FX anchor、USDC/USD health source、初期 LP position evidence | `fee = 500` / `tickSpacing = 10` / no hook の route と Safe owner が launch gate に記録される |
| 1. Read-only shadow | bot は観測・レポートのみ。tx 送信なし | state service、dashboard、daily report、alert dry-run | fair anchor、USDC health、pool spot/TWAP、pool token composition、swap flow、LP position、baseRate、redemption volume、branch unbacked、SP coverage、borrow capacity を同一 timestamp で照合できる |
| 2. IPOR LP-only canary | private Plasma Vault + ALPHA。自動 action は wait / LP modify / collect / bounded pool swap まで | Uniswap v4 fuse evidence、role readback、KMS/HSM signer、private relay、position registry、reconciliation tests | action 後も user-facing 0.1% / 0.5% depth、route integrity、max slippage、fair-anchor deviation guard を破らない。redemption / borrow / self-mint は実行しない |
| 3. Manual inventory / peg-defense integration | comparator は redemption / borrow / self-mint / manual top-up を比較するが、実行は Safe / manual | runbook、Safe calldata templates、all-in cost report、incident owner | redemption cost は `baseRate + 0.5% floor`、baseRate spike、branch unbacked 比例 routing、受領 collateral 混合、dToken unwrap / disposal cost を含めて判断する |
| 4. Post-evidence automation candidate | redemption / borrow / self-mint の一部自動化を検討 | 別 Issue / PR、fork evidence、audit / runbook、kill switch | Phase 1〜3 の実 data で pool swap より安全・安価であることを示し、権限境界と loss cap が監査済み |

Phase 1 以降の state service は、LP bot、Peg Defense Orchestrator、redemption / borrow runbook が同じ状態を読む共通 layer とする。BOLD 実測 (#854) では redemption は `baseRate + 0.5% floor` で、使いたい局面ほど baseRate が上がり得るうえ、償還先 collateral は branch unbacked 比例で混合される。このため、LP bot が「JPYdf が安いから自動 redemption」と判断することは Day-1 / canary では禁止し、manual escalation の根拠として扱う。

pool token composition は alert signal として扱う。BOLD 実測では pool 構成比が価格の大幅乖離前に大きく振れたため、JPYdf/USDC でも `JPYdf share` / `USDC share` を監視する。ただし構成比は fair FX anchor、USDC/USD health、LP range 配置に依存するため、pool price と同様に recenter の中心には使わない。閾値は launch 後の実測で再較正する。

実装タスクは以下に分ける。

1. **State / data**: fair FX anchor、USDC/USD、pool spot/TWAP、pool token composition、swap flow、LP position、redemption activity、baseRate、branch unbacked、SP coverage、borrow capacity を同一 schema で収集する。
2. **Policy engine**: stop / stale check、position guard、user-depth guard、action comparator、manual escalation reason を純粋関数として実装し、trade-level replay で検証する。
3. **Executor**: IPOR fuse call builder、bounded pool swap、private relay、KMS/HSM signing、config hash、role readback、emergency pause / revoke を実装する。AWS-only direct LP manager は fallback にしない。
4. **Evidence / runbook**: fork-run、dry-run、dashboard、daily report、Safe calldata templates、incident log を launch / activation gate に紐づける。

- **Day-1 〜 Day-7**: gate 未達なら Phase 0 のまま開始。gate PASS 時のみ Phase 2 canary を小さい notional / strict limits で稼働し、想定通り動くか観察。
- **Day-7 〜 Day-30**: Phase 1 / 2 の実 data で `natural offset rate`、`adverse selection cost`、`hedge cost`、`inventory limit breach`、`realized IL + fee` を測定し、β params / guard / position count を調整する。
- **Day-30 以降**: 観察結果に基づき、動的 range 調整、MM order-flow model、redemption / borrow の一部自動化、§8 の limitation 後追い検証 (= fee 収入モデル化、Monte Carlo simulation 等) を別 PR / Issue で議論する。

## 11. 関連 Issue / PR

- Issue #318 (= 本書で解決): 流動性管理方針を決める
- Issue #396 (= 制約として参照): 年間 IL 上限と range 設計
- Issue #630 / PR #643 (= 前提として参照): JPYdf/USDC Uniswap v4 pool 手数料 tier 決定 (`fee = 500` / `tickSpacing = 10` / no hook)
- [`Balance-Sheet-Liquidity-Allocation-Policy.md`](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md) §4: 自社初期seedの市場リスク・ヘッジ方針
- Issue #558 (= 関連): 大口獲得に向けた Redemption の実質的回避策の検討
- PR #854 (= 関連): BOLD depeg / redemption 実測 review
- PR #266 (= 原典): 流動性配分・管理方針 (= Day1-Self-BS の B/S 配分原典)
