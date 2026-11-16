# JPY DeFi Day1 Parameter Manifest

> Domain: Protocol
>
> Lifecycle: Launch
>
> Artifact Type: Manifest
>
> Schema Version: `2`
>
> Decision Authority: Protocol Governance
>
> Maintainer: DeltaForesight (Contributor)
>
> Status: Draft
>
> Manifest State: Candidate
>
> Environment: Ethereum mainnet
>
> Chain ID: `1`
>
> Release: Day1
>
> Candidate ID: `day1-ethereum-mainnet-parameters`
>
> Normative Source: Self

## 1. 目的と境界

本書はEthereum mainnetのDay1 deploymentへ投入するparameterの人間可読Manifestである。machine-readableなOwner Decisionは[`config/day1-branch-manifest.json`](../../config/day1-branch-manifest.json)を正本とし、CIが本書・code・consumerとの一致を検証する。

- parameter ID、意味、単位、binding、mutability、不変条件は[Parameter Catalog](./protocol/product/parameters/Parameter-Catalog.md)が定める。
- 将来の担保追加またはlaunch後の値変更に用いる基準は[Collateral Parameter Policy](./protocol/product/policies/Collateral-Parameter-Policy.md)、Day1の算定規則と採用理由は[Day1 Parameter Decision](./protocol/launch/decisions/Day1-Parameter-Decision.md)が持つ。
- contract address、role holder、artifact hash、verification blockはdeploy時のenvironment ManifestとEvidenceへ固定する。

本書のsource commitは、このファイルを含むgit commitで識別する。名目JPY額からtoken数量への換算値などenvironment固有のencoded値は、broadcast前に同じsource commitを参照するfreeze Evidenceへ記録する。

### 1.1 State transition

| State | 意味 | 更新規則 |
| --- | --- | --- |
| Candidate | review中のDay1投入値 | 承認前は変更可 |
| Approved | Protocol Governanceが特定git commitを承認 | 本書をfreezeし、以後の値変更は新しいrelease artifactで行う |
| Deployed / Verified | deploy Manifestとblock付きreadbackがApproved値との一致を証明 | 本書を現行on-chain stateへ合わせて上書きしない |

現在は非JPY Oracle stalenessの値が未freezeであるためCandidateである。

## §1. Day1 branch scope

| Branch | dToken | Underlying | Day1 state |
| ---: | --- | --- | --- |
| 0 | dwstETH | wstETH `0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0` | active |
| 1 | dUSDC | USDC `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | active |
| 2 | dETH | TBD | inert |
| 3 | dUSD-A | TBD | inert |
| 4 | dBTC | TBD | inert |
| 5 | dUSD-B | TBD | inert |
| 6 | dJPY | TBD | inert |
| 7 | dJGB | TBD | inert |

branch 0 / 1だけがUnderlying・実PriceFeed・CollateralYieldZapperをbindingする。branch 2–7はUnderlying未binding、`PriceFeedPlaceholder`、cap 0、Strategy / CollateralYieldZapperなしであり、Day1には利用できない。

## §2. Day1 parameter values

### §2-A. Core risk

branch 2–7の表中の値は、未稼働のCoreをデプロイするための初期値であり、将来のUnderlyingの採用値ではない。Underlyingを選定した後、MCRなどの6項目と清算担保補償上限を算定し、共通Timelockによる`finalizeRiskParams`で一度だけ確定する。cap・供給量・Core残高がゼロなどの有効化前条件を満たし、確定後にmint capを開く。確定後の変更は認めない。

| Branch | dToken | Underlying | LLTV | MCR | CCR | SCR | BCR | Liquidation Penalty | Redistribution Penalty |
| ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | dwstETH | wstETH | 81.18% | 123.18% | 141.67% | 110% | 10% | 5% | 10% |
| 1 | dUSDC | USDC | 89.62% | 111.58% | 124.50% | 105% | 10% | 5% | 10% |
| 2 | dETH | TBD | 81.18% | 123.18% | 141.67% | 110% | 10% | 5% | 10% |
| 3 | dUSD-A | TBD | 83.33% | 120.00% | 137.65% | 105% | 10% | 5% | 10% |
| 4 | dBTC | TBD | 83.65% | 119.55% | 130.82% | 110% | 10% | 5% | 10% |
| 5 | dUSD-B | TBD | 83.33% | 120.00% | 137.65% | 105% | 10% | 5% | 10% |
| 6 | dJPY | TBD | 94.76% | 105.53% | 107.30% | 103.30% | 5% | 5% | 5% |
| 7 | dJGB | TBD | 94.76% | 105.53% | 107.30% | 103.30% | 5% | 5% | 5% |

| ID | Day1値 |
| --- | ---: |
| `PRM-LIQ-KEEPER` | `min(0.5% × SP-offset collateral, branch cap)`; dwstETH: `2e18`, dUSDC: `1_000e18` |

### §2-B. dToken Layer

branch 0 / 1の`mintCap` / `allocateMaxMove`はenv freezeの入力値である。branch 2–7はtoken数量へ換算するactive設定ではなく、全てcap 0・allocation 0で固定する。

| Branch | dToken | Underlying | mintCap | allocatorCooldown | allocateMaxMove | withdrawDelay | bufferTargetBps | bufferFloor |
| ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | dwstETH | wstETH | 35 百万円 | `1800s`（30m） | 0 | `259200s`（3日） | `333 bps`（3.33%） | 0 |
| 1 | dUSDC | USDC | 1億円 | `1800s`（30m） | 1億円 | `259200s`（3日） | `333 bps`（3.33%） | 0 |
| 2 | dETH | TBD | 0 | `1800s`（30m） | 0 | `259200s`（3日） | `333 bps`（3.33%） | 0 |
| 3 | dUSD-A | TBD | 0 | `1800s`（30m） | 0 | `259200s`（3日） | `333 bps`（3.33%） | 0 |
| 4 | dBTC | TBD | 0 | `1800s`（30m） | 0 | `259200s`（3日） | `333 bps`（3.33%） | 0 |
| 5 | dUSD-B | TBD | 0 | `1800s`（30m） | 0 | `259200s`（3日） | `333 bps`（3.33%） | 0 |
| 6 | dJPY | TBD | 0 | `1800s`（30m） | 0 | `259200s`（3日） | `333 bps`（3.33%） | 0 |
| 7 | dJGB | TBD | 0 | `1800s`（30m） | 0 | `259200s`（3日） | `333 bps`（3.33%） | 0 |

名目JPYの`mintCap` / `allocateMaxMove`はhandover前にtoken数量へ換算し、価格、round、block、式、丸め、encoded値をfreeze Evidenceへ残す。

### §2-F. Manifest table boundary

この空sectionはCIが`§2-A` / `§2-B`の表境界を機械判定するために置く。parameter値は持たない。

### §2-C. Oracle

| ID | Day1値 |
| --- | ---: |
| `PRM-ORACLE-001` | `108000s`（30h） |
| `PRM-ORACLE-006` | `86400s`（24h） |
| `PRM-ORACLE-008` | `108000s`（30h。JPY更新時刻による通常償還・BorrowerOperationsの価格利用制限） |

JPY価格が30時間以上古い場合、新規借入・債務増加・担保引出・通常償還・新たな恒久shutdown判定を止める。返済と担保追加だけの調整は価格取得を要しない。清算は他の価格入力が有効な場合に限り、30時間の閾値と24時間の猶予を合わせて54時間未満まで継続できる。猶予中の誤清算・清算漏れと、清算停止による担保不足のトレードオフは残る。

### §2-D. Governance delays

| ID | Day1値 |
| --- | ---: |
| `PRM-GOV-COMMON-TIMELOCK-DELAY` | `43200s`（12h） |
| `PRM-GOV-PRICE-FEED-SOURCE-DELAY` | `43200s`（12h） |

### §2-E. Bridge

| ID | Day1値 |
| --- | ---: |
| `PRM-BRIDGE-MINTER-TIMELOCK` | `172800s`（48h） |

## §3. Unfrozen launch inputs

次のparameterはDay1に必要だが、まだApproved値ではない。broadcast前にfreezeし、本書をApprovedへ遷移させるcommitで具体値を追加する。

| ID | Freeze gate |
| --- | --- |
| `PRM-ORACLE-002` | Day1 consumerなし。将来のETH/USD建てbranch活性化時に公式metadata・fork block・risk owner sign-offでfreezeする |
| `PRM-ORACLE-003` | stETH/USD公式metadata・fork block・risk owner sign-off |
| `PRM-ORACLE-004` | USDC/USD公式metadata・fork block・risk owner sign-off |

将来branch、bridge route、PIL等のDay1非採用surfaceに対する候補値は本Manifestの対象外とし、採用を決定したactivation packageで別Manifestを作成する。
