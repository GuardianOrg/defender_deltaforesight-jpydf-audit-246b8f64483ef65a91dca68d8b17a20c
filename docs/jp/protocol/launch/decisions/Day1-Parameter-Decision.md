# JPY DeFi Day1 Parameter Decision

> Domain: Protocol
>
> Lifecycle: Launch
>
> Artifact Type: Decision Record
>
> Decision Authority: Protocol Governance
>
> Maintainer: DeltaForesight (Contributor)
>
> Status: Proposed — PR #1462のOwner-approved reviewまたはOwner mergeを承認記録とし、成立後はApproved

## 1. 決定の範囲

本書は、Day1の担保branch risk parameterとdToken Layer parameterについて、採用した入力、算定規則、値表に至った理由、例外、launch条件を記録する。本書だけでDay1判断をreviewできる粒度を持たせ、生データの全分布やDay1非採用候補まで読むことを前提にしない。

具体値は [`Parameters.md`](../../../Parameters.md) のDay1 Parameter Manifestを正本とする。parameterの意味と不変条件は [Parameter Catalog](../../product/parameters/Parameter-Catalog.md)、将来の担保追加またはlaunch後の値変更に用いる選定基準は [Collateral Parameter Policy](../../product/policies/Collateral-Parameter-Policy.md) を正本とする。

Day1のpublic branch、product exposure、SP requirement、PIL routing、会社自己資金は本書の決定対象ではない。それぞれ [Mainnet Launch Product Decision Record](./Mainnet-Launch-Product-Decision-Record.md) と資金ownerのcommitmentを正本とする。

## 2. Risk parameterの判断

### 2.1 Branch別model

Day1は、branchの性質に応じて次のmodelを採用する。

| Branch group | 採用した判断 | 理由 |
| --- | --- | --- |
| WETH / wstETH | price、liquidation exit、JPY FX、SP penaltyを含む高ボラmodel | 清算完了までのprice moveとJPY建て負債を同時にstressするため |
| USDC | observed stablecoin downsideとJPY FXを用いるstable model | price / FX stress後にも過剰担保を維持するため |
| dUSD-A / dUSD-B | structured / RWA stableを受け入れるMCR floor | exact asset未確定時に、観測depegだけでは表れないwrapper、exit、issuer、oracle riskを織り込むため |
| dBTC | BTC price、wrapped-asset depeg、liquidation exit、JPY FXを含むmodel | BTC変動とwrapper / market exitを分離せず評価するため |
| dJPY / dJGB | JPY同通貨modelとJGB price stress | FXを重複計上せず、短期金利・NAV変動と清算penaltyを評価するため |

採用modelへ入力したstressは次のとおり。出力値はDay1 Parameter Manifestを参照し、本書へ重ねない。

| Branch | Price / downside | Depeg | Exit slippage | JPY FX | Policy floor |
| --- | ---: | ---: | ---: | ---: | ---: |
| dETH | ETH 2h 99.9th 9.07% | 0% | 0.98% × 2 | 1.17% | — |
| dUSDC | 2h max downside 9.32% | — | — | 1.17% | — |
| dwstETH | ETH 2h 99.9th 9.07%（dETHと同値） | stETH/ETH 2h 最大DD 3.25% | 0.98% × 2（dETHと同値） | 1.17% | — |
| dUSD-A / dUSD-B | proxy max downside 11.79% | — | — | 1.17% | MCR 120% |
| dBTC | BTC 2h 99.9th 7.54% | 0.53% | 1.68% × 2 | 1.17% | — |
| dJPY / dJGB | JGB 1Y 2h max 0.28% | — | — | — | — |

### 2.2 採用データと候補比較

Day1で採用したstress入力のprovenanceと、値の選択に影響した主要な代替案を次に固定する。

| 対象 | Provenance | 採用判断と棄却案 |
| --- | --- | --- |
| JPY/USD | Twelve Data API、5分足、2021-01-18〜2026-01-16、360,781件。異常値270件を除外 | 2h 99.9thの1.17%をJPY建て負債に対するFX stressとして採用。dBTC検討でJPY/USDとBTC/USDの2h maxを同時使用する案はLLTV 69.09%となり、資本効率を大きく損なうため棄却 |
| dETH / dwstETH | Binance ETH/USD、5分足、2017-08〜。清算slippageはParaSwap APIによるhistorical quote | 1h 99.9thより保守的な2h 99.9thを採用 |
| dwstETH depeg | DefiLlama時間足のstETH / WETH USD価格、2022-01-01〜2026-08-05、joint 27,694点（除去486点） | ジャンプ系depegの規約どおり2h最大DD 3.25%を採用。エピソード全体7.7%はCCR / SCRの責務として棄却。粒度が時間足である点は残存不確実性として記録（[導出と判断根拠](./dwsteth-risk-parameter-derivation.md) §6） |
| dUSDC | 5分足のhistorical distribution。2h max 9.32%はSVB eventを含む | 非正規なjumpを捉えるためmax downsideを採用。99.9th / CVaRを使う代替案はJPY/USDを含めず、JPY建て負債を過小評価するため棄却 |
| dUSD-A / dUSD-B | Binance DAI/USDT、5分足、2020-08-11〜をstructured stableのproxyとして使用 | stress-implied値だけを使う案とUSDe固有proxyを棄却し、wrapper、exit、issuer、oracle riskを含むMCR 120% floorを採用 |
| dBTC | Binance BTC/USD、5分足、2017-08〜。Binance WBTC/BTC、5分足、2020-08〜。清算slippageはParaSwap APIによるhistorical quote | 2h max同士の組合せは資本効率を大きく損ない、1h 99.9thは清算遅延への余裕が小さいため、2h 99.9thを採用 |
| dJPY / dJGB | 財務省「国債金利情報」52年分。3か月データを取得できないため1年JGBをproxyとして使用 | 2h max 0.279%を0.28%へ丸めて採用。1円固定のJPYC理論値はJGB / settlement riskを表さないためDay1 branch値に使用しない |

USDC系列の取得元・観測期間と、ParaSwap quoteのtoken amount、route、取得時刻・blockはhistorical recordに残っていない。Day1の承認に使うfull-precision inputとともにlaunch calculation Evidenceへ固定する。

全分布、Day1非採用asset、過去の棄却候補は[2026-07-27 Collateral Parameter Rationale](../../../engineering/historical-reviews/2026-07-27-Collateral-Parameter-Rationale.md)にHistorical snapshotとして保存する。同snapshotは現行値または判断の正本ではなく、本書の理解に必須ではない。

### 2.3 Day1算定規則

§2.1の入力からDay1値を導出する規則を次のとおり採用した。高ボラmodelと通常CCRは [Collateral Parameter Policy](../../product/policies/Collateral-Parameter-Policy.md) §2.2 / §2.3の式を使い、stable / JPY model、dBTC CCRのstress入力、JPY固有gapは本節の例外を使う。

```text
USDC:
  LLTV = (1 - maxDownside) (1 - fxStress)
  MCR  = 1 / LLTV

dUSD-A / dUSD-B:
  LLTV = min((1 - proxyDownside) (1 - fxStress), 1 / 1.20)
  MCR  = 1 / LLTV

dJPY / dJGB:
  MCR  = (1 + liquidationPenaltySP) / (1 - priceStress)
  LLTV = 1 / MCR
  CCR  = MCR + 2 percentage points
  SCR  = MCR - 2 percentage points
```

dUSD-A / dUSD-Bの通常CCRにはMCR floor適用後の`1.20`を使うため、`1.20 / ((1 - 0.1179)(1 - 0.0117)) = 1.376494...`となる。

dBTCはMCRの算定にwrapped-asset custody depegを含める一方、CCRはDay1例外としてcustody depegを含めず、`CCR = MCR / ((1 - priceStress)(1 - fxStress))`へPrice 7.54%とJPY FX 1.17%を適用して導出した。exact Underlyingのcustody / depeg stressがimmutable値へ収まるかはactivation時に検証する。

JPY系はPolicyの通常CCR式を適用せず、少数positionによるRecovery Mode / shutdown境界の重なりを避けるため上記の`±2 percentage points`を採用した。

Day1 Parameter Manifestのpercent値は算定engineのfull-precision出力を小数第2位へ丸めた最終値である。§2.1の表示入力は可読性のため丸めているため、表示値だけの手計算は最大`±0.01 percentage points`ずれ得る。入力のfull-precision値、式、raw output、丸め前後の値は同一のlaunch calculation Evidenceへ保存し、Manifestとdeploy encoded値を照合する。

wstETHは当初WETHと同じimmutable値を暫定採用し、wstETH固有のmarket / canonical rate、depeg、清算出口がそのenvelopeへ収まるかを別のlaunch Evidenceで確認するとしていた。2026-08-06にその確認を完了し、**収まらないと判断して再導出した**（[dwstETH risk parameterの導出と判断根拠](./dwsteth-risk-parameter-derivation.md)）。stETH/ETHのdepegレッグ3.25%（2h最大DD）を高ボラmodelへ加え、Branch 0は`LLTV 81.18% / MCR 123.18% / CCR 141.67%`とする。SCR / BCR / SP penalty / redistribution penaltyは据え置く。

### 2.4 Recovery / shutdown / penalty

- CCRは各branchのMCRから、§2.3で定めた通常式またはDay1例外のstress入力を用いて導出する。
- SCRはirreversible shutdownの誤発動を避けるためMCR未満とし、urgent redemption bonusの支払可能性を維持する。
- JPY系はMCR近傍にCCR / SCRを置き、BCRとredistribution penaltyも低volatility前提に合わせる。
- Stability Pool penaltyはbranch間のSP流動性偏在を避けるため共通水準を基本とし、redistribution penaltyはCoreの担保保全条件を満たす。
- dJPY / dJGBのMCRとSP penaltyは余裕が小さいため、境界挙動をlaunch前test Evidenceで確認する。

## 3. dToken Layerの判断

### 3.1 Exposure cap

Day1の`mintCap`は、公開対象branchのplanned exposureと清算capacityを抑える初期envelopeとして採用する。これはJPYdf debt ceilingではない。

- public exposureを持つbranchだけにnonzero capを設定する。
- exact Underlying未確定branchはcap 0とし、activation packageの承認前に開けない。
- 名目JPYからtoken数量への換算はdeploy freeze時点で行い、暗黙の価格参照や追加haircutを用いない。

初期capは、旧案の各branch `$1m`を一律に置くのではなく、2026-06-18の再検討でLiquity v2の直近1年に観測した最大清算規模22%と50% liquidation clusterの想定を比較し、dwstETH 3,500万円、dUSDC 1億円を採用した。Day1ではCoreへ新しいbranch debt ceilingを追加せず、dToken cap、Core risk parameter、SP coverage、launch / operations gateで初期exposureを管理する。

Day1 active branchのtoken数量capを名目JPYへ再計算する初回thresholdは次のとおり。初回cap変更まではDay1 Parameter Manifestの名目額、変更後は直近の承認済みproposal / execution Evidenceの名目額を比較基準とする。換算方法とEvidence要件はCollateral Parameter Policy §3.1を適用する。

| Branch | Day1初回threshold |
| --- | ---: |
| dwstETH | `1,000 bps` |
| dUSDC | `500 bps` |

public branchの選択とplanned exposureの正本はMainnet Launch Product Decision Record、値はDay1 Parameter Manifest、freeze手順と換算EvidenceはMainnet Deploy Env Freeze Runbookが担う。

### 3.2 Allocator control / Strategy allocation

`allocatorCooldown`は、compromised allocatorによる連続操作を30分単位で制限しつつ通常配分を妨げない水準として全branch共通30分を採用する。Vaultへ資産を戻すrecovery pathには適用しない。

Day1に外部Strategyを採用しないbranchは`allocateMaxMove = 0`とし、Strategyへの実配分を開けない。dUSDCの`allocateMaxMove`は承認した名目capと同じ1億円を上限とする。wstETHのnative staking増価はcanonical rateを通じて担保価値へ残し、Strategy profitとして扱わない。

この記録はStrategyの採用状態の正本ではない。Day1 product scopeはMainnet Launch Product Decision Record、deploy bindingはMainnet Deploy Env Freeze Runbookと生成Manifestを正本とする。将来async Strategyを採用する場合は、回収期間に合わせてwithdraw / buffer parameterを再決定する。

### 3.3 Withdrawal / buffer

Day1は同期回収またはStrategyなしの構成を前提に、全branchで3日のwithdrawal delayを採用する。比例bufferはLiquity v2の2025-05-15〜2026-05-04におけるWETH branchの3日rolling redemption最大値3.33%を基準とし、`bufferTargetBps = 333`、absolute floorは0とする。

inert branchの値は将来activationの事前承認ではない。exact UnderlyingまたはStrategyを確定した時点で回収期間、settlement、queue、redemption需要から再導出し、capまたはallocationを0より大きくする前に承認する。

## 4. 未完了の検証と有効化条件

| 対象 | Day1条件 | 不成立時 |
| --- | --- | --- |
| wstETH risk envelope | composite oracle、depeg、清算出口、SP / liquidator capacityがimmutable値へ収まるEvidence。**depegと清算出口は2026-08-06に完了**（[導出と判断根拠](./dwsteth-risk-parameter-derivation.md)）。SP / liquidator capacityはmainnet-fork stress gateで確認 | public exposureとcapを再判断 |
| dwstETH追加監査 | dwstETH BranchとOracleの実装差分を追加監査scopeへ含め、launch-blocking findingの対応を完了。SOWは実装差分の確定後にfreeze | launchを止め、指摘対応後にgo / no-goを再判定 |
| JPY系penalty境界 | collateral surplusとurgent redemptionの境界testがpass | launchを止め、値またはbranch構成を再判断 |
| 計算provenance | USDC系列の取得元・観測期間、ParaSwap quote条件、全inputのfull-precision値を同一Evidenceへfreeze | ManifestをApprovedへ遷移させない |
| 名目cap換算 | production oracle legs、round、block、丸め、encoded値のreview完了 | broadcastを中止 |
| inert branch | cap / allocationが0で、未確定assetをpublic metadataへ出さない | handoverを中止 |

本書は値の設定またはgovernance executionを代替しない。Protocol Governanceの承認、deploy / Timelock操作、Manifest、block付きreadbackが別途必要である。
