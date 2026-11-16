# Contract Audit Scope and nSLOC

> **今回の追加auditについてはSUPERSEDEDです。** 以下は旧scope checkpointです。現行SOWは
> root [`SCOPE.md`](../../../../SCOPE.md)、日本語参考訳は
> [`SCOPE.ja.md`](../../../../SCOPE.ja.md)を参照してください。現行review boundaryは164 hunks、
> final-side changed-code 510 nSLOCです。6,124 final whole-file nSLOCはcontextでありscopeでは
> ありません。

## 1. Auditor quick read

本書はIssue #1454後のmainnet contract review境界を定める。Day-1 branch topologyは[`config/day1-branch-manifest.json`](../../../../config/day1-branch-manifest.json)を正本とし、branch 0–1だけがactive、branch 2–7はinertである。

| Scope | nSLOC | Treatment |
| --- | ---: | --- |
| Economic/security full-review body | 5,225 | 推奨SOW本体。5,472から#1454のcandidate固有401を除外し、§4の+154を加算 |
| TroveNFT / metadata light review | +330 | fund movement等を持たない表示surface |
| Interfaces / ABI shims | +1,264 | ABI整合性のみ。実装nSLOCから除外 |
| Base-derived core whole-file upper bound | +2,890 | 通常はdiff/parity review |
| Active `contracts/src` population | 12,060 | archiveを除く全Solidity sourceのreconciliation値 |
| Archive population | 1,212 | Strategy archive 810 + candidate-specific archive 402 |
| Whole `contracts/src` population | 13,272 | active + archive。SOW本体ではない |

計測はclocの`code`列。freeze SHAで次を再実行し、使用version、CSV、hashをEvidenceへ保存する。

```sh
cloc --by-file --csv --quiet --include-lang=Solidity contracts/src
find contracts/src -type f -name '*.sol' -not -path '*/archive/*' -print0 | xargs -0 cloc --csv --quiet --include-lang=Solidity
find contracts/src -type f -name '*.sol' -path '*/archive/*' -print0 | xargs -0 cloc --csv --quiet --include-lang=Solidity
```

## 2. Day-1 deploy boundary

| Branch | State | Required launch surface |
| ---: | --- | --- |
| 0 `dwstETH` | active | wstETH、DFWstETHPriceFeed、CollateralYieldZapper、Aave Strategy |
| 1 `dUSDC` | active | USDC、DFUSDCPriceFeed、CollateralYieldZapper、Aave + Morpho V2 Strategy |
| 2–7 | inert | Underlyingなし、PriceFeedPlaceholder、cap 0、Strategy / Zapperなし |

inert slotのexact Underlying、Oracle、Strategy、Zapperは現行監査scopeに含めない。activation時にimmutable risk適合Evidence、Owner承認、実装review、追加監査要否を1つのpackageで確定する。

## 3. Archived source

### 3.1 Candidate-specific archive — 402 nSLOC

| File | nSLOC | Status |
| --- | ---: | --- |
| `contracts/src/PriceFeeds/archive/DFUSDTPriceFeed.sol` | 19 | Day-1 map不採用。official deploy importなし |
| `contracts/src/PriceFeeds/archive/sUSDSPriceFeed.sol` | 95 | Day-1 map不採用。official deploy importなし |
| `contracts/src/PriceFeeds/archive/DFXAUTPriceFeed.sol` | 19 | XAUT downside depegを反映するOracleへ置換するまで再採用不可 |
| `contracts/src/PriceFeeds/archive/DFWBTCPriceFeed.sol` | 82 | exact BTC Underlying未承認 |
| `contracts/src/Zappers/archive/SkyUsdcSUsdsYieldZapper.sol` | 187 | candidate collateral ingress。dUSDC運用Strategyとは別surface |
| **Subtotal** | **402** | active body 5,472から除外 |

archive testは`contracts/test/archive/`でcompile / executionを継続する。再採用はsourceをactive treeへ戻すだけでは足りず、activation package、Owner承認、review、追加監査判断を必要とする。

### 3.2 Previously archived Strategy sources — 810 nSLOC

`contracts/src/Strategies/archive/`の`LidoStrategy`、`EtherfiWeETHStrategy`、`WeETHWithdrawAdapter`、`AsyncRequestStrategy`は引き続きactive scope外である。今回の402 nSLOCとは混同しない。

## 4. Active full-review body reconciliation

| Bucket | Before #1454 | #1454 delta | After #1454 | Since | Current |
| --- | ---: | ---: | ---: | ---: | ---: |
| DF-modified core | 849 | 0 | 849 | +6 | 855 |
| JPY DeFi implementation | 2,724 | 0 | 2,724 | +132 | 2,856 |
| Oracle / PriceFeed | 848 | -214 | 634 | +15 | 649 |
| Zapper / route | 1,051 | -187 | 864 | +1 | 865 |
| **Total** | **5,472** | **-401** | **5,071** | **+154** | **5,225** |

`Since`列は#1454後のoracle path修正、`CollateralVaultLens`抽出、監査前の
pricing / Morpho incident rail修正である。合計を信用ではなく`cloc`で照合できるよう、
全内訳を示す。

| File | Before | After | Δ | Bucket |
| --- | ---: | ---: | ---: | --- |
| `DFStabilityPool.sol` | 306 | 312 | **+6** | DF-modified core |
| `CollateralVault.sol` | 818 | 782 | **−36** | JPY DeFi |
| `CollateralVaultLens.sol` | — | 159 | **+159** | JPY DeFi |
| `Strategies/MorphoV2Strategy.sol` | 149 | 158 | +9 | JPY DeFi |
| `Strategies/SkyUsdcSUsdsConverter.sol` | 156 | 157 | +1 | Zapper / route |
| `PriceFeeds/JpyUsdRateProvider.sol` | 93 | 101 | +8 | Oracle |
| `PriceFeeds/JpyFreezeLib.sol` | 50 | 55 | +5 | Oracle |
| `PriceFeeds/DFPriceFeedBase.sol` | 69 | 70 | +1 | Oracle |
| `PriceFeeds/DFWstETHPriceFeed.sol` | 88 | 89 | +1 | Oracle |
| **Total** | | | **+154** | |

同じ期間の変更のうち2件は意図的に上表へ含めていない。
`Interfaces/ICollateralVault.sol`は156 → 167だが§1の行のとおりinterfaceは実装
nSLOCから除外される。`archive/sUSDSPriceFeed.sol`は94 → 95でarchive内の移動であり、
archive populationが1,211ではなく1,212になっている理由がこれである。
実装+154、interface +11、archive +1の合計+166が
13,106 → 13,272のpopulation差分を過不足なく説明する。ERC4626の最終補正は
state transitionを変更したが`cloc` code行数は91のままで、コメントだけが増えている。

`CollateralVault` → `CollateralVaultLens`の当初の分割は新規ロジックではなく再配置である。
VaultがEIP-170のruntime上限まで約50 byteに迫り修正を阻んでいたため、reporting view
を外部へ移した。その時点のペア合計+69は、LensがVaultを引数に取りpublic getterから
各値を再構成するための接続コードであった。その後の`CollateralVault`差分は、pricing
availability分離、Vault経由のMorpho incident rail、receiver実着額redemptionという挙動追加である。
最終runtimeは23,047 / 24,576 byte（余裕1,529 byte）である。

共有`DFPriceFeedBase` / `MainnetPriceFeedBase` / `CompositePriceFeed` / `PriceFeedProxy` / `PriceFeedPlaceholder`とgeneric `CollateralYieldZapper`はactive bodyに残る。`SkyUsdcSUsdsStrategy` / converter / interfaceもdUSDC Vaultの資産運用候補であり、candidate collateral branchとは別機能なのでarchiveしない。ただしDay-1 deploy policyはSky Strategy登録を拒否する。

## 5. Freeze evidence

auditor handoffにはexact commit SHA、active/archive source manifest、cloc CSV/hash、repo-wide legacy-hit classification、full Forge/archive suite、mainnet fork、deploy→handover→verify Evidenceを添付する。#1450のSOWはこれらが同一SHAで揃うまで確定しない。

旧5-active版は[英語archive](../../../en/engineering/guides/archive/Contract-Audit-Scope-And-nSLOC-pre-issue1454.md)に履歴として保存し、現行SOW入力には用いない。
