# Strategy Incident / Liquidation Safety Runbook

| 項目 | 内容                                                                                                                                                                                                              |
| ---- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 対象 | Strategy 側の会計に直ちに現れない損失、外部プロトコルの流動性停止、reserve deficit / bad debt / depeg 疑い                                                                                                        |
| 目的 | 回収不能額を backing に反映するまでの間に、運営 bot が不当に liquidation を進めないこと                                                                                                                           |
| 正本 | [Strategy spec](../../product/spec/strategies/Strategy.md) / [AaveV3Strategy spec](../../product/spec/strategies/AaveV3Strategy.md) / [CollateralVault spec](../../product/spec/CollateralVault.md) / [Oracle spec](../../product/spec/Oracle.md) |

## 1. 原則

1. **会計に出ない損失は自動 markdown されない**
   Aave の reserve deficit / bad debt / collateral depeg など、Strategy の `estimatedTotalUnderlying()` に現れない事象は `backingRatio()` にも自動反映されない。監視・回収・GOV 判断で `writeoffStrategyPrincipal` を行うまで、オンチェーン価格は健全に見え続ける。

2. **未確定損失で先に清算しない**
   回収不能額が未確定の段階では、運営 liquidation bot は該当 branch を fail-closed にする。第三者清算は止められないが、運営主体は speculative markdown で liquidation を進めない。

3. **writeoff は清算価格を動かす操作である**
   `writeoffStrategyPrincipal` により `backingRatio() < 1e18` になると、DF PriceFeed は担保価格へ下方反映する。これは borrowing / redemption / liquidation の価格に入るため、writeoff は「損失確定」と「清算影響」の両方を伴う GOV 操作として扱う。

4. **復旧は回収・補填・反映の順序で行う**
   liquid に回収できる資産を先に Vault へ戻し、必要なら `backstopDeposit` で補填し、最後に確定残額だけ writeoff する。先に大きく writeoff して後から補填する運用は、短時間でも不必要な liquidation window を作る。

5. **補填資産は対象 Vault の Underlying に限る**
   `backstopDeposit` は対象 `CollateralVault.underlying()` を `safeTransferFrom` で受け取る。JPYdf、dToken、Aave/Merkl 等の reward token をそのまま入れても dToken backing は修復されない。Safe / Treasury が JPYdf や reward token を保有している場合は、対象 branch の Underlying へ換金してから `backstopDeposit` する。

## 2. Strategy 別の判定基準

「会計に出るか」「回収不能か」「単なる流動性制約か」は Strategy 実装ごとに異なる。branch の collateral symbol ではなく、実際に登録されている Strategy kind / 外部 protocol の状態で判定する。

| Strategy kind                                       | `estimatedTotalUnderlying()` が表すもの                                                                                                                                                                    | writeoff 前に分けるべき事象                                                                                                                        | 復旧・清算 safety                                                                                                                                                                                                                                                                            |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AaveV3Strategy                                      | Strategy 自身が供給した scaled balance × Aave normalized income。Aave 側の scaled balance 減少は反映するが、reserve deficit / bad debt / market depeg が Aave 会計値を直接減らさない場合は自動反映されない | reserve utilization による一時的な `withdraw` 不足、reserve pause/freeze、aToken 流動性不足、Aave governance の deficit 処理、担保資産の市場 depeg | `max withdraw` 不足だけで writeoff しない。`emergencyWithdrawFromAave` は liquid 分だけ Vault へ戻し、残余は外部会計・Aave governance 状態・実回収見込みを確認する。bot は Vault pause 中 skip。確定残額だけ writeoff                                                                        |
| ERC4626Strategy（Morpho Vault / EulerEarn 等）      | Strategy 自身が mint した share の `convertToAssets()`。share price 低下は原則として live valuation に出る                                                                                                 | share price 低下による実損、`maxWithdraw` / `maxRedeem` の一時制限、withdraw queue、vault pause、oracle / loan-market bad debt                     | `convertToAssets(ownShares) < principal` は損失シグナルになり得るが、`maxWithdraw` 不足だけなら流動性制約。緊急 redeem で回収可能分を戻し、share price 低下と bad debt が確定した分のみ writeoff。二重 writeoff を避けるため、既に valuation に出ている loss と `principal` 減算額を突合する |
| LidoStrategy                                        | 自己 wstETH の canonical stETH 換算 + pending withdrawal amount の bps 評価 + claim 済み自己 idle WETH。stETH の DEX 市場価格 depeg はそのまま canonical 会計損ではない。通常時の pending は 10000 bps で request 時記録額、incident freeze 後だけ Vault `WRITEOFF_ROLE` が bps を下げられる | withdrawal queue の待機、pending valuation bps、finalization rate、slashing / consensus loss、stETH 市場 depeg、request NFT claim 遅延、直接 stETH/wstETH/WETH/raw ETH donation | queue 待ちを loss と見なさない。`requestLidoWithdrawal` 後は finalization / claim を追跡し、claim 実額に疑義がある場合は `pausedAllocation == true` を確認してから `setPendingWithdrawalValuationBps` で pending を保守割引して判断する。claim 後に実受領 WETH を Vault へ戻す。slashing 等で canonical rate / claim 実受領額が元本を下回ることが確認されるまで writeoff しない。直接 stETH/wstETH/WETH/raw ETH donation は backing として扱わない。WETH donation は必要時に汎用 `emergencyWithdraw` で戻せるが principal return ではない |
| EtherfiWeETHStrategy                                | 自己 weETH の eETH/WETH 換算 + WithdrawRequestNFT pending amount の bps 評価 + claim 済み自己 idle WETH。通常時の pending は 10000 bps で request 時の net eETH 額、incident freeze 後だけ Vault `WRITEOFF_ROLE` が bps を下げられる | Ether.fi withdrawal finalization 待ち、pending valuation bps、NFT claim 遅延、claim 実受領 ETH の不足、weETH/eETH canonical rate 低下、LRT market depeg、直接 eETH/weETH/WETH/raw ETH donation | pending NFT 待ちを loss と見なさない。`requestEtherfiWithdrawal` 後は NFT / `isFinalized` / claim 実受領 ETH を追跡し、claim 実額に疑義がある場合は `pausedAllocation == true` を確認してから `setPendingWithdrawalValuationBps` で pending を保守割引して判断する。claim 後に WETH として Vault へ戻す。claim 実受領額や canonical rate 低下で residual が確認されるまで writeoff しない。直接 eETH/weETH/WETH/raw ETH donation は backing として扱わない。WETH donation は必要時に汎用 `emergencyWithdraw` で戻せるが principal return ではない |
| SkyUsdcSUsdsStrategy                                | 通常時は自己 sUSDS share の USDS 建て value + 自己 idle USDS を、converter `previewUsdsToUsdc` と 1:1 換算の小さい方で USDC 建て評価する。明示的な逆変換 route halt 中は `min(1:1 position, principal)` とし、未実現 yield は認識しない。直接 sUSDS/USDS/USDC donation は通常 valuation に含めない | converter halt / pause、USDS→USDC route slippage、USDS depeg、sUSDS `convertToAssets` 低下、sUSDS vault `maxWithdraw` 制限、USDS idle residue | converter 停止や slippage 拡大は即 writeoff ではなく回収経路停止として扱う。`emergencyRedeemSUsdsToUsds` で USDS に戻せても、Vault backing に戻るのは USDC に変換して `receiveFromStrategy` が成功した分だけ。明示的 halt 以外の quote 障害を 1:1 と推定せず、最終 USDC 建ての保守 quote と実回収額で residual が確定した分だけ writeoff |
| 直接 idle / mock / inert                            | Vault buffer または Strategy 直接保有分                                                                                                                                                                    | 誤送金、直接保有 idle、未設定 Strategy                                                                                                             | `emergencyWithdraw` / `receiveFromStrategy` で Vault へ戻す。外部 protocol 損失ではないため、原則 writeoff しない                                                                                                                                                                            |

### 判定の補助線

- **一時的な流動性制約**: Aave reserve utilization、ERC4626 `maxWithdraw` 制限、Lido queue 待ちは、回収が遅いだけなら損失ではない。Vault pause と bot skip を維持し、回収・claim・queue 進行を待つ。
- **live valuation に出る損失**: ERC4626 share price 低下や Lido finalization amount 低下など、`estimatedTotalUnderlying()` が既に落ちている場合は `backingRatio()` に反映され得る。追加の manual writeoff が二重反映にならないか、Strategy `principal` / Vault conservative value / returned principal を突合する。
- **live valuation に出ない損失**: Aave reserve deficit のように Strategy 会計値へ直ちに出ないものは、`backingRatio()` も健全に見える。外部 protocol の公式会計、reserve status、実回収 tx、監査・incident report を根拠に、確定残額だけ writeoff する。
- **市場 depeg と canonical 会計の違い**: stETH / wstETH や一部 yield token は、DEX 市場価格が下がっても protocol 内の canonical accounting が同時に毀損するとは限らない。清算価格へ反映するのは JPYdf の oracle / backing policy の対象であり、Strategy principal writeoff とは分ける。
- **branch symbol では判断しない**: 預け先が Aave なら Aave、Morpho / Euler なら ERC-4626、Sky なら asset-transforming の判定を使う。

### 2.1 Allocation valuation preflight の監視・復旧

- allocation keeper の各 call 前後で `getStrategyStatuses()` を外部 monitor から取得し、enabled / weight を問わず登録 Strategy の `estimateAvailable && principalAvailable` を確認する。1 件でも false なら `allocate` と `transferYieldToTreasury` は cached value や部分合計を使わず 0 outbound になる。`allocate` は `Allocated` を発火せず cooldown も消費しないため、keeper receipt 成功だけを正常配分と扱わず、status unavailable と同 call の `Allocated` 欠落を earliest stable machine event として warning/page する。
- dependency が回復すれば次の keeper call で自動再開できる。復旧 probe は対象 Strategy の両 view、全登録 Strategy の status、buffer target、実際の `Allocated` / `StrategyAllocated`、前後 buffer を同一 block で確認する。never-settling / gas-exhausting view は transaction 全体を revert し得るため、keeper timeout だけで回復と判定せず、affected data path の成功 receipt とイベントを確認する。
- 連続 failure または 1 keeper 周期を超える failure は on-call へ page し、`pauseAllocation`、外部 venue / RPC / Strategy implementation の調査、回復 probe の順に進める。fresh valuation cache を outbound 再開根拠にしない。
- production 有効化前に、外部 monitor、escalation policy、実 recipient を接続し、valuation unavailable → 0 outbound → dependency 回復 → 自動再開までの明示した test incident を発報・受信・resolve して incident log に残す。token / webhook URL は記録しない。

### 2.2 Allocation deposit reject の監視・upgrade

- `StrategyAllocationSkipped` を外部 monitor で購読し、同一 block 時点の `getStrategyStatuses()` が live available かつ cap 残ありなら、valuation/cap skip ではなく外部 venue の deposit reject と分類する。1 回目を warning、同一 Strategy の連続発生または keeper 周期内の再発を on-call へ page する。`allocate` が `DepositRecoveryFailed` で revert した場合は、完全回収不能として初回から page し、allocation を pause する。
- 構造化 log だけで完了扱いにしない。production 有効化前に外部 monitor、escalation policy、実際の当番 recipient を接続し、明示した test incident の発報・受信・resolve を一巡して incident log に記録する。token / webhook URL は記録しない。
- `deposit(uint256)` から `deposit(uint256,uint256)` への selector 変更を伴うため、upgrade 中は allocation を pause する。全登録 BaseStrategy implementation を先に upgrade し、続いて CollateralVault を upgrade する。全 Strategy の新 selector、Vault/Strategy の Underlying 一致、cap/weight、bytecode を照合し、affected data path の allocate probe とイベント受信を確認してから unpause する。途中状態の selector 不一致は fail-closed revert するが、pause を代替しない。

## 3. 即時対応フロー

1. **検知**
   外部プロトコルの incident、reserve deficit、withdraw 停止、価格乖離、監査報告、keeper の partial recovery を検知したら、該当 branch を incident mode とする。

2. **Vault / Strategy 停止**
   GUARDIAN は `emergencyDisableStrategy(strategy)` を実行する。これにより Strategy の `weightBps = 0` / `enabled = false` になり、Vault の deposit / redeem / claim / allocation が pause される。新規 outbound allocation とユーザー flow を止め、回収・補填判断に集中する。

3. **運営 liquidation bot 停止確認**
   bot は branch config の `collateral_vault` を読み、以下のいずれかで該当 branch を skip する。
   - `pausedDeposit || pausedRedeem || pausedClaim`
   - `backingRatio() < safety.min_backing_ratio_wei`
   - Vault guard が必須なのに `collateral_vault` 未設定

   Lido / Etherfi の `setPendingWithdrawalValuationBps` で pending 評価を下げる場合も、先に `pausedAllocation == true` と bot skip 条件を確認する。pending bps 下方変更は元本 writeoff ではないが、`backingRatio()` と清算価格を同じく下げ得る暫定 markdown として扱う。

4. **回収**
   Strategy 固有の emergency 関数を実行し、回収可能な liquid 分を同一 tx で Vault へ戻す。Vault 実受領額は returned principal として Strategy `principal` から減算される。

5. **補填判断**
   `backingShortfall()` / `backstopRequiredForRatio(1e18)` と対象 Vault の `underlying()` / symbol / decimals を確認し、Treasury / Protocol retention Safe / Foundation operating-asset Safe がその Underlying を用意できるか判断する。Foundation operating-asset Safe を使う場合は、Protocol Treasury 側の判断ではなく Foundation の個別承認・会計/税務証跡を先に取得する。補填できる場合は writeoff 前に `backstopDeposit` で Underlying を入金し、不必要な `backingRatio` 低下を避ける。JPYdf、dToken、非 Underlying reward token は直接の補填資産にしない。

6. **損失確定 writeoff**
   回収不能額が確定した分だけ `writeoffStrategyPrincipal(strategy, amount, minBackingRatioAfter)` を実行する。`minBackingRatioAfter` は手順 3 の dry-run で算出した expected backing ratio から、丸め・同時状態変化の余裕を差し引いた下限値にする。transaction が `BackingRatioBelowMinimum` で revert した場合は、単位ミス・直前 state 変化・未反映回収の可能性を再確認し、値を雑に下げて再送しない。writeoff 後の `backingRatio()` と PriceFeed 表示価格を記録し、MCR 近傍 Trove への影響を確認する。

7. **再開**
   `backingRatio == 1e18` に戻り、Strategy 追加・cap・weight・oracle・bot guard が確認できた後、GOV が Vault user flow を必要な順序で unpause する。運営 bot の `min_backing_ratio_wei` を緩和する場合は、GOV/運営判断と理由を incident log に残す。

### 3.1 操作別 policy ledger

Admin Console と Ops Dashboard は、以下の分類を同じ語彙で表示する。UI 上のボタン名だけで判断せず、各操作が backing / buffer / principal / bot safety に何を変えるかを incident log に残す。

| 分類     | 主な関数 / 手順                                                         | 目的                                                     | backing への影響                                                           | buffer / claim liquidity への影響                          | 実行前チェック                                                                                                    |
| -------- | ----------------------------------------------------------------------- | -------------------------------------------------------- | -------------------------------------------------------------------------- | ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Freeze   | `emergencyDisableStrategy`, Vault pause                                 | 新規 allocation と user flow を止める                    | なし。損失確定ではない                                                     | なし                                                       | 対象 Strategy、branch、bot skip 条件、第三者清算リスク                                                            |
| 回収     | `sendToVault`, Strategy 固有 emergency withdraw, `claimLidoWithdrawals` | 回収可能分を Vault へ戻す                                | 実受領分は returned principal として会計に戻る                             | Vault buffer / idle に戻る                                 | `requested` と `sent` の差、Aave reserve liquidity、ERC4626 `maxWithdraw` / queue、Lido finalization / claim 状態 |
| Writeoff | `writeoffStrategyPrincipal`                                             | 回収不能額を principal から確定控除する                  | conservative value が追加で下がる分だけ `backingRatio` と PriceFeed に反映 | 直接の liquidity 追加はない                                | live valuation に既に出ている損失との二重計上、MCR 近傍 Trove、backstop 可否                                      |
| 注入     | `backstopDeposit`                                                       | Treasury / Protocol retention Safe / Foundation operating-asset Safe（個別承認済みの場合）等から不足 backing を補填する | `totalUnderlying` / backstop reserve が増え、full backing 復帰に使える     | protected reserve であり、まだ claim / redeem 原資ではない | 対象 Vault の `underlying()`、補填元 Underlying balance / allowance、full repair amount、writeoff 後の不足額。JPYdf / dToken / reward token を直接入れない |
| 解放     | `releaseBackstopToBuffer`                                               | protected reserve を claim / redeem 原資へ移す           | Vault 内部分類の変更のみ。`totalUnderlying` は増えない                     | buffer が増え、pending claim / withdraw の支払いに使える   | full backing 復帰済み、pending queue、残すべき protected reserve                                                  |
| 再開     | unpause, strategy weight / cap 再設定, bot safety 緩和                  | 通常運用に戻す                                           | 新規影響なし。ただし再配分で将来 risk が戻る                               | user flow 再開                                             | backingRatio、oracle、strategy selector、bot `min_backing_ratio_wei`、incident log 承認                           |

特に `writeoff` は「損失確定」であり、「回収」「注入」「buffer への解放」とは別の操作である。Aave では reserve deficit が Strategy 会計に直ちに出ない場合があり、ERC4626 / Lido では share price や canonical finalization amount の低下が live valuation に既に出る場合がある。Strategy ごとに二重 markdown にならないことを確認してから実行する。

### 3.2 Strategy kind 別 execute checklist

同じ `sendToVault` / `writeoffStrategyPrincipal` でも、外部 venue ごとに意味が異なる。Admin Console / Ops Dashboard は Strategy 固有 view から kind を検出し、operator は以下の checklist を incident log に残す。

| Strategy kind                     | 回収で使う主経路                                                                                                      | `requested != sent` の第一解釈                                                            | writeoff してよい残額                                                                                                | bot 再開前の追加確認                                                                                 |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Aave V3                           | `sendToVault`、重大時は `emergencyWithdrawFromAave`                                                                   | reserve utilization / liquid underlying 不足。Aave 会計値が残っている限り即 loss ではない | Aave reserve deficit / bad debt が会計に出ず、実回収見込みもないと判断した residual                                  | Aave reserve pause/freeze、normalized income、scaled balance、liquid reserve、外部 incident report   |
| ERC-4626                          | `sendToVault`、重大時は `emergencyWithdrawFromERC4626`                                                                | `maxWithdraw` / `maxRedeem` / queue / vault pause による liquidity limit                  | `convertToAssets(ownShares) < principal` と bad debt が確定し、既に live valuation に出た loss と重複しない residual | share price、maxWithdraw/maxRedeem、curator/governance action、underlying market bad debt            |
| Lido                              | `requestLidoWithdrawal` → finalization → `claimLidoWithdrawals` → `sendToVault`。重大時は `emergencyWithdrawFromLido` | claim 済み自己 idle WETH が足りないだけ。stake 済み分は queue 待ち。finalized でも未 claim なら freeze 後の bps 調整済み pending 評価のまま。直接 WETH/raw ETH donation は回収可能性や backing の証拠にしない | queue 待ちではなく、claim 実受領額または canonical rate 低下で確認された residual                                    | requestId、pending amount と requestId 別合計の一致、`pausedAllocation`、pending valuation bps、finalization/claim 状態、実受領 ETH、自己 idle WETH、donation residue、withdrawDelay と pending user claims |
| Etherfi weETH                     | `requestEtherfiWithdrawal` → NFT finalization → `claimEtherfiWithdrawals` → `sendToVault`。重大時は `emergencyWithdrawFromEtherfi` | claim 済み自己 idle WETH が足りないだけ。weETH 分は pending NFT / finalization 待ち。直接 WETH/raw ETH donation は回収可能性や backing の証拠にしない | NFT 待ちではなく、claim 実受領 ETH または weETH/eETH canonical rate 低下で確認された residual                         | requestId、NFT owner / validity、pending amount と requestId 別合計の一致、`pausedAllocation`、pending valuation bps、`isFinalized`、実受領 ETH、自己 idle WETH、donation residue |
| Sky USDC/sUSDS                    | `sendToVault`、重大時は `emergencyRedeemSUsdsToUsds` → `emergencyConvertIdleUsdsToVault` または `emergencyWithdrawFromSky` | converter halt / slippage / USDS idle 化。USDS に戻せても USDC として Vault に戻るまでは backing 修復ではない | 通常時は converter preview と 1:1 cap、明示的 halt 中は principal-capped 1:1 valuation、実USDC回収額、sUSDS share value 低下で確認された residual | route-status read、converter preview / halt、`maxConversionLossBps`、USDS idle、sUSDS `maxWithdraw`、実USDC回収額、branch 1 / USDC 専用設定 |

`BaseStrategy.emergencyWithdraw(amount)` は「Strategy が直接保有する Underlying を Vault へ戻す」救済経路であり、`principal` を減算しない。Aave / ERC4626 / Lido の外部 protocol principal を回収する場合は、原則として固有 `emergencyWithdrawFrom...` または `sendToVault` を使い、Vault 実受領額を returned principal として減算する。Lido の直接 WETH donation は Base emergency で Vault へ戻せるが、Lido の principal return ではない。Base の idle 救済を使った場合は、その後に残る `principal` と `estimatedTotalUnderlying()` の差分を確認し、必要なら別途 residual writeoff を行う。

## 4. Bot 運用ルール

Day-1 の運営 liquidation bot は `safety.require_vault_guard = true` を標準とする。

```toml
[safety]
require_vault_guard = true
allow_liquidation_during_vault_pause = false
min_backing_ratio_wei = "1000000000000000000"

[[branches]]
symbol = "dUSDC"
collateral_vault = "0x..."
```

この設定では、Strategy incident で Vault user flow が pause された branch と、明示 writeoff 後に backingRatio が 1 未満になった branch では、運営 bot は liquidation tx を送信しない。
`allow_liquidation_during_vault_pause = true` または `min_backing_ratio_wei < 1e18` は、損失が確定済みで第三者清算と同じ条件で運営が介入すべき場合に限り、incident log とセットで一時適用する。

bot は scan 時と submit 計画時の両方で Vault guard を読む。scan 後に Vault pause / writeoff が入った場合も、submit 直前の再チェックで該当 branch を skip する。

## 5. 不当清算を避けるチェック

writeoff / bot 再開前に最低限以下を確認する。

| チェック                                                        | 目的                                                                                      |
| --------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `estimatedTotalUnderlying()` と外部プロトコル実回収可能額の差分 | 会計に出ない損失か、単なる一時 illiquidity かを分ける                                     |
| `backingShortfall()`                                            | 補填または writeoff が必要な絶対額を確認する                                              |
| `backstopRequiredForRatio(1e18)`                                | full backing 復帰に必要な補填額を確認する                                                 |
| MCR 近傍 Trove 一覧                                             | writeoff 後の価格で liquidation 対象になる Trove を事前把握する                           |
| `PriceFeed.fetchPrice()` / `fetchRedemptionPrice()`             | backing markdown が borrowing / redemption / liquidation の両価格で一致することを確認する |
| bot safety config                                               | 運営 bot が incident branch を skip することを確認する                                    |

## 6. 判断基準

- **一時流動性不足**: writeoff しない。回収 queue / protocol liquidity 回復を待つ。bot は Vault pause 中 skip。
- **回収済み + 補填で full backing 復帰可能**: 補填を先に行い、必要最小限の writeoff に留める。
- **確定損失で補填不能**: writeoff し、`backingRatio < 1` を市場価格へ反映する。この場合 liquidation は不当ではなく protocol solvency の反映だが、運営 bot の再開は明示判断とする。
- **評価不能 / データ不一致**: writeoff しない。Vault pause と bot skip を維持し、追加調査する。
