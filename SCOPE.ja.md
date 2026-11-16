# 追加本番Solidity監査スコープ（日本語参考訳）

> **参考訳（非正本）:** 本文書は英語版 [`SCOPE.md`](./SCOPE.md) の理解を助けるための
> 日本語訳です。監査SOWの正本は英語版です。内容に不一致がある場合は英語版を優先し、
> scope変更は英語版を先に更新した上で本訳へ反映します。

## 本SOWで使用する用語

- **監査対象の変更** — 見積とsecurity reviewに含むexact 171 Git diff hunks。hunkは
  Git diff内の連続した1つの変更blockを指す。
- **判断に必要なcontext** — included changeを評価するために確認が必要なunchanged caller、
  dependency、inheritance、routing、external-return assumption。unchanged file全体の
  再audit依頼ではない。
- **理解・再現用資料（review対象外）** — tests、build inputs、specifications、test compileに
  必要な一部deployment file、machine check。
- **Guardian** — 本SOWで依頼する外部audit firmであり、protocolの`GUARDIAN_ROLE`ではない。
  **Chain Defenders** — remediation baseを作った前回の外部audit firm。

## Solidityコードの確認場所

完全なSolidity source差分の正規表示には、
[audit PR #107 — Files changed](https://github.com/deltaforesight/jpydf-audit/pull/107/files)
を完全なsource差分の正規表示として使用します。これはaudit commit
`b5265f311abc524683561b79792eab2900823fa9` と
`2725216e0407a0ef4599e359a04094ae5f322624` の間で、
`source-snapshot/contracts/src/` 配下にある全25 changed paths・物理差分`+745/-185`を
そのまま表示します。全25 paths・全171 hunksがsecurity reviewの依頼scopeです。

commit対応は、upstream base `d4122704`とaudit snapshot commit `b5265f31`が共にsource tree
`417fe3b9`を持ち、upstream final `1b453c10`とaudit head `2725216e`が共にsource tree
`84476d90`を持ちます。code identityを拘束するのはrepository固有commit IDではなくtree
identityです。

[#107 head時点の完全な最終Solidity tree](https://github.com/deltaforesight/jpydf-audit/tree/2725216e0407a0ef4599e359a04094ae5f322624/source-snapshot/contracts/src)
のtree identityは `84476d9086e89580c58918b203f4142ecd839765` であり、本番candidateと
完全一致します。[Audit PR #109](https://github.com/deltaforesight/jpydf-audit/pull/109)
は、本SOW、完全なtests、build inputs、英語context、過去report、evidenceを含む資料PRです。
#107と比較して `source-snapshot/contracts/src/` に変更を加えておらず、第2のSolidity scope
ではありません。本文書のimmutable commitとtree identityを正本とします。

## 依頼するcode-review scope

reviewはChain Defenders remediation baseからfinal production candidateまでのsecurity
differentialです。各touched fileの全行をline-by-lineで再auditする依頼ではありません。
正確なreview targetは
[`FINAL_PRODUCTION_HUNK_PROVENANCE.tsv`](./FINAL_PRODUCTION_HUNK_PROVENANCE.tsv)
の全rowです。

各`H-<20 hex>` IDはledger rowの`hunk_sha256`先頭20 hexです。`base_range`と
`final_range`が正確なline spanを示します。hunk boundary/countは
`scripts/verify-final-hunk-provenance.mjs`が生成し、GitHub表示が隣接hunkをまとめる場合も
ledger rowを正本とします。

| 境界 | Identity |
| --- | --- |
| Base | `d4122704d08b521d832438c31c0ddccf202fea81`, tree `417fe3b995f3dec84fd611fcc2f5c3ebd62d5c7a` |
| Final | `1b453c10e3378390109cf42037a97b7f6de57b9e`, tree `84476d9086e89580c58918b203f4142ecd839765` |
| 依頼するsecurity review | 25 files、171 hunks、`+745/-185` |

`d4122704`をbaseとする理由は、Chain Defenders第2回remediation setを含むrepository endpoint
だからです。report記載source identity `469b1265`との関係のevidenceとGuardianによる明示的
acceptance要件は、Guardian handoffの **Chain Defenders Baseline Acceptance** にあります。

ledgerは全source hunkを記録するため、boundaryを検証できます。
新規又は未対応のproduction Solidity差分があればscopeを自動拡張します。小さいdiff、説明の
欠落、schedule、見積を理由にscope外を推定してはいけません。

included hunkが対象とするthemeは以下です。

- Oracle、JPY/USD runtime validation、3つのprice path、recovery/resume、freeze episode、
  source lifecycle、30時間normal-redemption gate
- wstETHのdirect/derived redemption pricingとurgent wind-down
- RedemptionHelperのfailed-branch share/refund accounting
- CollateralVaultがraw underlyingを先に数え、追加backingが必要な場合のみ正常に読めた
  live Strategy valueを数えるbacking check
- reserved branch riskのone-shot atomic finalization
- 100,000 JPYdfのminimum-debt、repayment、zombie共通境界
- Zapperのreferral/native-ETH挙動

[`KNOWN_RISKS_AND_CURRENT_POSITION.md`](./docs/audit/KNOWN_RISKS_AND_CURRENT_POSITION.md) は、final
candidateの既知risk、修正済み項目、将来変更時の条件、projectの現時点の見解を示します。
review questionの理解資料ですが、本SOWを拡大又は縮小するものではありません。
同台帳がGuardianへ依頼するtechnical assessmentは、included hunkと必須integration contextに
関する範囲のみquoted effortに含みます。launch evidenceの作成とprojectによる正式なrisk
acceptance判断はsource-audit deliverable外です。既知riskの開示はfindingを抑制又は格下げ
しません。projectが現状維持を推奨している場合でも、Guardianは独自のseverityで脆弱性として
報告できます。

### 追加assessmentの受入記録（2026-09-03）

projectは
[`ADDITIONAL_ASSESSMENT_REVIEW_2026-09-03.md`](./evidence/external-audit/ADDITIONAL_ASSESSMENT_REVIEW_2026-09-03.md)
（SHA-256 `39bd683d4c389042e3011576333d010f53b6f47a5e37559cbd442d92d5dff920`）
も開示しました。同書の各observationsは独立した再現とdispositionを要する潜在的既知事象として
扱い、findingとして受諾済みとは扱いません。この受入記録はimmutable source/hunk boundaryを
変更せず、同書の事実認定、severity、remediation、audit status、launch recommendationを
受諾しません。不一致時はfrozen source、本正本SOW、projectの日本語source of truthを優先します。

- **H-01:** `KR-10`として開示済み。frozen Solidityは変更せず、
  [`jpydf-v2#1957`](https://github.com/deltaforesight/jpydf-v2/issues/1957) のD-1/D-2
  deployment-binding evidenceでcloseします。
- **M-01:** `KR-01`として開示済み。formal risk-owner approval待ちでretainします。
- **M-02:** `KR-07A`として開示済み。formal risk-owner approval、funded backstop、human alert
  delivery、end-to-end recovery evidence待ちでfail-closed設計をretainします。
- **L-01:** `KR-06`として開示済み。formal risk-owner approvalと再帰的にreview済みの
  deployment-bound source dependency graph待ちでretainします。
- **L-02:** `KR-02`として開示済み。formal risk-owner approvalとoperational TCR/recovery
  evidence待ちでpermissionless economic-shutdown boundaryをretainします。
- **L-03:** `KR-03`として開示済み。formal risk-owner approvalとgovernance recovery evidence
  待ちでfail-closed urgent settlementをretainします。
- **L-04:** `KR-04`として開示済み。formal risk-owner approvalと90,000秒stETH/ETH thresholdの
  D-6 readback待ちで`max(direct, derived)` polarityをretainします。
- **L-05:** `KR-05`として開示済み。formal risk-owner approvalとrole、timelock、source identity、
  3 price pathsのexecution evidence待ちでdelayed emergency recovery pathをretainします。
- **L-06:** `KR-13`として開示済み。canonical Lido stETH/wstETH addresses、runtime identity、
  immutable binding、`submit(address)` semanticsのD-7 evidence取得までlaunch-blockedです。

旧test-only overrideの削除は、別code-review objectiveではなくmachine checkとして記録して
います。surviving source hunksは全171件ともscope内です。

## Review規模と参考context

本packageの **nSLOC** は、pinned `cloc 2.06`が数えるnon-blank・non-comment Solidity
code linesです。committed verifierで全数値を再現できます。他toolの“normalized SLOC”とは
異なるため、別toolでは異なる値になり得ます。**modified pair** はin-placeで変更したlineを
1回だけ数え、additionとdeletionの2回には数えません。

主たるsizing指標は完全なchanged codeです。`cloc 2.06`によるfinal-side changed-code
footprintは **535 nSLOC** です。Git上は171 hunks・物理差分`+745/-185`です。

以下のwhole-file値は参考contextにすぎません。**6,656 final whole-file nSLOCは
changed-line数、又は25 filesの全行を再auditする依頼ではありません。** review depthは171
changed hunksと、その判断に必要なreachable
function / invariantです。

| Included class | Paths | Base whole-file context | Final whole-file context | Included物理差分 | Included hunks |
| --- | ---: | ---: | ---: | ---: | ---: |
| 稼働実装 | 15 | 5,277 | 5,674 | `+674/-173` | 150 |
| Interfaces / ABI | 7 | 419 | 450 | `+47/-10` | 16 |
| Legacy / archive / inheritance context | 3 | 514 | 532 | `+24/-2` | 5 |
| **依頼するreview合計** | **25** | **6,210** | **6,656** | **`+745/-185`** | **171** |

### Guardian scope interfaceとの照合

Guardianが2026-09-03に提示したscope interfaceは同じ25 changed Solidity filesを列挙し、
合計は`Lines` 8,678、`Normalized` 5,702、`Diff` 930です。file setと各fileの`Diff`はimmutable
`b5265f31..2725216e` source differentialに完全一致し、930は`745 + 185`です。`Lines`と
`Normalized`はGuardian interface固有の指標であり、上記pinned `cloc 2.06`値へ置換しません。
完全な表と照合結果は
[`GUARDIAN_SCOPE_INVENTORY_2026-09-03.md`](./docs/audit/GUARDIAN_SCOPE_INVENTORY_2026-09-03.md)
に記録します。

7 interfacesは、変更されたselector、struct、mutability、event、errorのreview対象です。
450 whole-file nSLOCを、別個のfull-interface re-auditとして扱ってはいけません。

[`FINAL_PRODUCTION_NSLOC.tsv`](./FINAL_PRODUCTION_NSLOC.tsv) と以下のcommandでfile別値を
再現できます。verifierの`6,210 -> 6,656`はreview scopeを構成する同じ25 changed pathsを
数えます。535 changed-code nSLOCと6,656 final whole-file contextは`cloc`値であり、
Guardian portal固有のnormalizationとは別指標です。

```sh
./scripts/verify-final-nsloc.sh
```

<details>
<summary>正確な25 review pathsとfinal whole-file context</summary>

| Path | Class | Final nSLOC |
| --- | --- | ---: |
| `AddressesRegistry.sol` | 稼働実装 | 251 |
| `BorrowerOperations.sol` | 稼働実装 | 1,230 |
| `CollateralVault.sol` | 稼働実装 | 802 |
| `DFStabilityPool.sol` | 稼働実装 | 315 |
| `Dependencies/Constants.sol` | 稼働実装 | 74 |
| `Interfaces/IAddressesRegistry.sol` | interface / ABI | 76 |
| `Interfaces/IBorrowerOperations.sol` | interface / ABI | 144 |
| `Interfaces/IJpyUsdRateProvider.sol` | interface / ABI | 5 |
| `Interfaces/IPriceFeed.sol` | interface / ABI | 7 |
| `Interfaces/IPriceFeedProxy.sol` | interface / ABI | 45 |
| `Interfaces/IStabilityPool.sol` | interface / ABI | 30 |
| `Interfaces/ITroveManager.sol` | interface / ABI | 143 |
| `PriceFeeds/CompositePriceFeed.sol` | inheritance context | 32 |
| `PriceFeeds/DFPriceFeedBase.sol` | 稼働実装 | 74 |
| `PriceFeeds/DFWstETHPriceFeed.sol` | 稼働実装 | 142 |
| `PriceFeeds/JpyFreezeLib.sol` | 稼働実装 | 55 |
| `PriceFeeds/JpyUsdRateProvider.sol` | 稼働実装 | 110 |
| `PriceFeeds/MainnetPriceFeedBase.sol` | 稼働実装 | 92 |
| `PriceFeeds/PriceFeedPlaceholder.sol` | 稼働実装 | 23 |
| `PriceFeeds/PriceFeedProxy.sol` | 稼働実装 | 278 |
| `RedemptionHelper.sol` | 稼働実装 | 141 |
| `StabilityPool.sol` | legacy context | 303 |
| `TroveManager.sol` | 稼働実装 | 1,495 |
| `Zappers/CollateralYieldZapper.sol` | 稼働実装 | 592 |
| `Zappers/archive/SkyUsdcSUsdsYieldZapper.sol` | archive context | 197 |

</details>

## 以前提案した除外は現在scopeに含む

2026-08-31のtriageで候補にした7 hunksも、Guardian提示inventoryに合わせて全件review scopeへ
含めます。legacy/archive/cosmeticとの分類はcontext説明であり、除外ではありません。

| Path / hunk | 現在の扱い |
| --- | --- |
| `StabilityPool.sol`の3 hunks | legacy contextとしてincluded |
| `PriceFeeds/CompositePriceFeed.sol`の1 hunk | inheritance contextとしてincluded |
| `PriceFeeds/MainnetPriceFeedBase.sol`の1 hunk | archive-call contextとしてincluded |
| `TroveManager.sol`の1 comment hunk | cosmeticだがincluded |
| `Zappers/archive/SkyUsdcSUsdsYieldZapper.sol`の1 hunk | archive contextとしてincluded |

当時の判断記録は
[`ADDITIONAL_AUDIT_SCOPE_TRIAGE_2026-08-31.md`](./docs/audit/history/ADDITIONAL_AUDIT_SCOPE_TRIAGE_2026-08-31.md)
にhistorical evidenceとして残します。scope又は数値が異なる場合は本書を優先します。

## 判断に必要なcontext

unchanged codeはchanged-code targetではありませんが、included surfaceを
import、inherit、implement、call、delegate、ownする場合、又はincluded surfaceからcallされる
場合は確認が必要です。この作業はquoted engagement effortに含みますが、unchanged file全体の
review依頼ではありません。必要なcontextには以下を含みます。

- ActivePool、CollateralRegistry、SortedTroves、JpydfToken、DToken、
  CollateralVaultLens、InterestRouter、core consumer
- DFUSDCPriceFeedと全current/placeholder source implementation
- registered Strategyのvaluation/allocation pathと外部venue
- Chainlink aggregator、wstETH canonical rate、shared JPY/USD provider、
  Vault backing read
- PriceFeedProxyのownership/source-confirmation topology

`DFUSDCPriceFeed.sol`のsource blobはbase/finalで同一ですが、included
`DFPriceFeedBase`のinheritanceによりmetadata-free runtimeが変わります。そのためchanged-file
targetではなくても、inherited behaviorは必要なcontextです。

candidateの完全なsource-level price/control topologyとdeployment-binding circularity trace
手順は
[`FINAL_PRODUCTION_DEPENDENCY_GRAPH.md`](./docs/audit/FINAL_PRODUCTION_DEPENDENCY_GRAPH.md)
にあります。source-level topologyはreview contextです。deployment-binding手順はproject側の
launch checkであり、本SOWにおけるdeployment-script又はproduction deployment reviewではありません。

このcontext要件はcall-chainとinvariantの検証であり、列挙した全component又は外部protocolを
whole-fileで再auditすることではありません。171 changed hunksの判断に必要なreachable function、
state assumption、ownership/routing、external-return semanticsをreviewします。unchanged
component内の無関係なfunctionはreview対象外です。安全性の判断に、より広いunchanged
component又は新しいexternal targetが必要とauditorが判断した場合、そのreview areaを一旦止め、
full additional targetとして扱う前にscope/effort変更を合意します。

## 監査確認事項（review objectives）

外部reviewでは以下に回答します。

1. normal、redemption、urgentのprice pathは、全current sourceについて、それぞれ異なる
   cache、failure、pause、terminal-shutdown semanticsを維持しているか。
2. JPY/USD処理はruntime decimals/provenance drift、invalid response、stale-newer round、
   repeated freeze episode、Forex休場中のsame-value heartbeat更新、正確な30時間
   normal-redemption境界を安全に扱うか。expiry前のre-anchoringとexpiry後のfresh-only
   recoveryを確認し、新しい`updatedAt`を新しいmarket price discoveryの証明とみなさないか。
3. source変更、callback、forwarding dependency、ownership lifecycleによりcycle、source
   validation bypass、cache poisoning、system-wide redemptionの恒久DoSが発生しないか。
4. failed-branch redemption accountingはdenominator allocationを維持し、healthy branchへ
   valueを再配分せずunused JPYdfをrefundするか。
5. raw underlyingと正常に読めたlive Strategy valueでliabilityを覆えない状態で、deposit、
   redeem / redeem-with-permit、claim、又はnonzero Strategy allocationを完了できないか。
   また意図したrecovery functionは使用可能なままか。
6. reserved risk finalizationはauthorized、atomic、invariant-checked、one-shotであり、
   AddressesRegistry、BorrowerOperations、TroveManager間にpartial synchronizationを
   残さず、DFStabilityPoolはfinalization前のdepositを拒否するか。
7. `MIN_DEBT = 100_000e18`はfeeを含むopen/adjust entire debt、repayment clamp、
   normal-redemption zombification、zombie reactivationへ一貫して適用され、意図的に異なる
   closeとurgent residual挙動を維持しているか。
8. Lido referral又はnative-ETH Zapper変更がcustody destination、collateral/debt
   accounting、receiver、minimum output、refund、atomicityへ影響しないか。

## 明示的なnon-scopeと境界の扱い

「Out of scope」は「safe」「reviewed」「approved」を意味しません。このdifferential SOWに
含まれない作業を示します。これらの領域に依存するfindingは無視せず、明示的なscope変更を
必要とする場合があります。

| 領域 | 本engagementでの扱い | 理由／scopeへ戻る条件 |
| --- | --- | --- |
| included changeの評価に必要なunchanged importer、inheritor、caller、routing、external-return assumption | 必要なcontextのみ | 関連挙動をreviewする。無関係なfunctionはfull-component re-auditしない。より広いreviewなしに結論を出せない場合はscopeを拡張する。 |
| `ActivePool.sol`、`JpydfToken.sol`、`MorphoV2Strategy.sol`、`CollateralVaultLens.sol`、`DToken.sol`、その他Strategy contracts、`InterestRouterForwarder.sol`、`PILAllocator.sol`、`UniV4MerklInitiative.sol`、`UniV4Exchange.sol` | base/final byte identity確認後、changed fileとして除外。callされる場合はcontextに残る | byte identityによりchanged-file reviewから外れるだけで、included callerの理解には必要となり得る。 |
| complete tests/fixtures、Foundry configuration、tools、specifications、runbooks、manifests、prior reports、commitされたdeployment-script files | 理解・再現用資料。deployment scriptsは除外 | build、test、intended behaviorの理解に使う。改訂SOWで追加しない限り、auditorに`DeployLiquity2.s.sol`のreview又はinitial active-branch parameter/wiringのcertificationは求めない。 |
| vendored `contracts/lib/**`とChainlink、Lido/wstETH、Aave、Morpho、Uniswap等のexternal protocol | dependency assumptionとcalled interfaceのみ | 各projectのsource re-auditはしない。新しいintegration assumption又はunsupported behaviorが見つかれば別reviewが必要になり得る。 |
| frontend、backend、liquidator bot、subgraph、一般operational tooling | 除外 | frozen production Solidity treeを変更しない。必要なら別application/operations reviewを行う。 |
| initial active-branch parameter/wiring、generated deployment、broadcast、private RPC access、secret、Safe signature、production deployment、external alert delivery | source audit外。project所有のlaunch evidence | runtime parameter/address/codehash/role/wiring readbackとalert deliveryは別途完了する。source review合格だけでは成立しない。 |
| 継承したLiquity codebase全体 | whole-protocol re-auditなし | 171 changesと必要なcontextのみを対象とする。Liquity全体の再auditには別SOWが必要。 |

## 商用scope判断

Guardian提示の25-path・171-hunk boundaryをquotation baselineとします。見積価格に応じてkickoff前に
縮小を依頼する場合がありますが、projectとGuardianが、exact included hunksとtopic、
再計算size、結論に必要なsource/dependency context、縮小が生むriskのproject acceptance、
reportの結論範囲を記した改訂SOWを承認した後にのみ有効です。それまでは全171 hunksをscopeと
します。本SOWはproduction candidate全体の安全性を保証しません。

## 希望監査日程

security-denseなcross-contract DeFi logicであるため、effortは171 hunks、535
final-side changed code nSLOC、必須call-chain reviewに基づいて見積もります。6,656
whole-file context値だけを基準にしてはいけません。

projectは2026年9月中のEthereum mainnet releaseを計画しており、scope acceptance後、
Guardianに可能な限り早い開始を依頼します。finding後の実装修正時間を確保するため、code
review完了とfindings report受領の希望日は **2026年9月18日** です。この希望によりreview
depthを下げず、scope boundaryも変更しません。日付がdefensibleでない場合、Guardianは最短の
実現可能な代替日を提示します。project側からteam構成は規定しません。

source変更、materially broader dependency、又はreproduction failureには明示的な
re-scopeが必要です。
