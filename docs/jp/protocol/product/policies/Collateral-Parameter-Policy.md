# JPY DeFi Collateral Parameter Policy

> Domain: Protocol
>
> Lifecycle: Evergreen
>
> Artifact Type: Policy
>
> Decision Authority: Protocol Governance
>
> Maintainer: DeltaForesight (Contributor)
>
> Status: Active

## 1. 目的と境界

本書は、新規担保のactivationまたはlaunch後のparameter変更において、担保branchのrisk parameterとdToken Layerの運用parameterをどの入力と判断基準で選定・変更するかを定める。

parameterの意味、単位、binding、mutability、不変条件は [Parameter Catalog](../parameters/Parameter-Catalog.md)を正本とする。Ethereum mainnet Day1の値は[`Parameters.md`](../../../Parameters.md)、Day1で採用した入力・算定規則・例外・理由は[Day1 Parameter Decision](../../launch/decisions/Day1-Parameter-Decision.md)を参照する。本書はそれらのDay1 snapshotを複製しない。

個別の値、採用理由、実行手順、承認結果、on-chain readbackは、対象releaseまたは変更ごとのDecision Record、Manifest、Runbook / Gate、Evidenceへ分離する。

Oracle、Governance、Bridge、PILのparameterは、それぞれのcomponent policy / activation packageの所管とし、本書では担保branchとの横断条件だけを扱う。

## 2. Risk parameterの選定

### 2.1 必須入力

新規担保のactivationまたはrisk parameter変更を承認する前に、少なくとも次を同一の観測期間・時間窓・通貨基準で揃える。

- collateral価格のdownside move
- wrapped asset、stablecoin、RWA等のmarket priceとclaim valueのdepeg
- 清算出口のslippageと、流動性悪化時に適用するstress multiplier
- JPY建て負債に対するFX downside
- issuer、custodian、transfer restriction、redemption、settlement、queue、market-hours等の非価格リスク
- SP、JIT liquidator、redemption routeの実行可能性

入力データ、取得元、観測期間、算出block、計算sheet、棄却した代替案は対象Decision RecordまたはEvidenceへ保存し、本書へ複製しない。

### 2.2 MCR / LLTV

高ボラ担保は、清算閾値のpositionが清算完了までの複合stressを受けても負債と清算penaltyを担保で賄える水準を選ぶ。新しいasset classまたは清算経路へ適用する場合、各stress項の採否と観測windowをDecision Recordで明示する。

```text
MCR = (1 + liquidationPenaltySP)
      / ((1 - priceStress)
         (1 - depegStress)
         (1 - slippageStress × multiplier)
         (1 - fxStress))

LLTV = 1 / MCR
```

USD stable / structured assetは、観測depegとFXだけで得られる水準を機械的な上限とはしない。exit、oracle、wrapper、issuer、custody等の構造リスクを反映したMCR floorを別途比較し、より保守的な水準を採用する。floorの具体値は対象Decision Recordで承認する。

JPY-denominated settlement assetはFXを重ねず、価格・NAV・settlement stressと清算penaltyで評価する。担保通貨がJPYであることだけを理由にdepeg、exit、issuerまたはsettlement riskを0とみなさない。

### 2.3 CCR / SCR / BCR / liquidation penalty

- CCRは、branch全体が選定stressを受けた後もMCRを下回らないRecovery Mode境界として、`CCR = MCR / ((1 - priceStress)(1 - depegStress)(1 - fxStress))`で導出する。
- SCRは不可逆なshutdownを開始する境界である。`SCR < MCR < CCR`とurgent redemption bonusの支払可能性を同時に満たし、少数positionに集中するbranchの誤shutdown riskを考慮する。
- BCRはbatch feeとinterest-rate changeがpositionを直ちに清算へ押し込まないbufferとして選ぶ。
- Stability Pool penaltyはcontract下限以上、redistribution penalty以下とし、いずれもMCRで担保から支払える水準にする。
- parameter組合せは [Parameter Catalog §4](../parameters/Parameter-Catalog.md#4-parameter-invariants) をdeploy preflightとreadbackで検証する。

### 2.4 Exact Underlying未確定branch

deploy immutable parameterを持つinert branchは、将来候補の平均値ではなく、想定asset classを受け入れられる保守的なenvelopeとして選ぶ。

activation時は確定Underlyingのstress、oracle、liquidity、exit、legal / custody、SP / liquidator capacityが既存envelopeへ収まるかを検証する。収まらない場合、mutable capやoracle haircutで補って開放せず、inertを維持するかsystem migrationを別途判断する。

## 3. dToken Layer parameterの選定

### 3.1 mintCap

`PRM-mintCap`の新規設定または変更は、担保のexit liquidity、SP / liquidator capacity、oracle confidence、operational readiness、planned exposureを基に選ぶ。JPYdfのglobal issuance capまたはCore branch debt ceilingとして扱わない。

名目JPYで承認する場合は、production PriceFeedと同じ外部legsからbacking ratio適用前のunderlying価格を取得し、capが承認名目額を超えない方向へ丸める。価格、round、block、式、丸め、encoded値はfreeze Evidenceへ保存する。

post-launchのtoken数量capは、次のいずれかで名目JPY exposureを再計算する。

- cap引上げproposalを作成するとき
- 対象branchのDecision Recordまたは直近の承認済みproposalが定める乖離thresholdへ到達したとき
- risk ownerがexposure reductionを提案するとき

推定名目額は、現行cap数量とproduction PriceFeedと同じ外部legsによるunderlying価格から算出し、backing ratioは適用しない。比較基準は直近の承認済みDecision Record、proposalまたはexecution Evidenceに記録した名目額とする。乖離は`abs(estimatedCapNotionalJpy - approvedNominalJpy) × 10,000 / approvedNominalJpy`でbps換算する。再計算Evidenceには価格、round、block、式、丸め、encoded値、比較基準、乖離bpsを残す。

cap引上げは [Active Branch Cap Ramp Runbook](../../operations/runbooks/Active-Branch-Cap-Ramp-Runbook.md) に従う。cap引下げは既存supplyをburnせず新規mintだけを止め得るため、残余リスクをproposalとexecution Evidenceへ明記する。

### 3.2 allocatorCooldown / allocateMaxMove

`allocatorCooldown`はcompromised allocatorによる連続操作を制限しつつ、許可済みStrategyへの通常配分と緊急回収を妨げない水準にする。Vaultへ資産を戻すrecovery pathへ同じ待機を課さない。

`allocateMaxMove`は1回のoutbound allocationで動かせるunderlying数量を制限する。Strategyを採用しないbranchではoutbound allocationを開けない。inert branchでStrategyを有効化する場合、capと別にloss envelope、回収経路、keeper capacityを評価し、同じactivation packageで承認する。

### 3.3 withdrawDelay / bufferTargetBps / bufferFloor

`withdrawDelay`はunderlying / Strategyのwithdrawal、settlement、queue、lockの最悪回収期間から導出する。async Strategyを採用する場合、同期回収またはStrategyなしの値を流用しない。

`bufferTargetBps`と`bufferFloor`は、redemption需要と回収遅延に対して[Parameter Catalog](../parameters/Parameter-Catalog.md) `PRM-INV-007`の`requiredBuffer`を確保する組合せとして選ぶ。

小規模TVLで比率bufferが絶対額として不足する場合にのみ`bufferFloor`を設定する。継続的なbuffer shortfall、`pendingWithdrawals > bufferBalance`、回収期間の変更、redemptionが主要なpeg exitになる変化を再評価triggerとする。

## 4. Decision・実行・検証

新規値または値変更のproposalは、本書の適用項目、使用した入力、代替案、例外、再評価triggerをDecision Recordへ残す。Artifact間の情報境界は[Document Governance](../../../Document-Governance.md#4-artifact-type--文書の役割)に従う。

GOV mutable parameterはTimelock executionとblock付きreadbackが完了して初めて現行値になる。deploy immutable parameterはbroadcast前にCatalogの不変条件とManifestのencoded値を照合し、差異があればdeployを中止する。
