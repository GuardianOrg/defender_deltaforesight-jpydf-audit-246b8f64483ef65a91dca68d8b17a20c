# Mainnet Launch Risk Gate

| Field | Value |
| --- | --- |
| Domain | Protocol |
| Lifecycle | Launch |
| Artifact Type | Runbook / Gate |
| Decision Authority | Protocol Governance |
| Maintainer | DeltaForesight |
| Visibility | Repository |
| Status | Active |
| Normative Source | 本書（`SYS-RISK-*`のLaunch gate）。Protocol要件はProduct / component Spec、設計理由はArchitecture Decision Records |

## 1. 目的

Ethereum mainnet Day1 launch前に、システム横断の構造リスクが各Spec / Policyの統制と実行Evidenceで閉じていることを確認する。Core内部へ場当たり的なtry/catchやbacking会計を追加せず、外側レイヤー、deploy gate、Operations artifactで検査する。

本書はProtocol behavior、parameter値、Contributorの自己資金commitmentを定義しない。個別値はDay1 Manifest、実行結果はEvidenceを正本とする。

## 2. Gate

<a id="sys-risk-001"></a>
### `SYS-RISK-001` JPY/USD共通依存

- **リスク**: `collateral/USD ÷ (JPY/USD)`（JPY/USDはUSD per JPY）のため、JPY/USD feedのstale / deprecation / 誤更新は全branchに波及する。
- **Protocol統制**: 全active feed（`DFPriceFeedBase`系・composite系）は共有`JpyUsdRateProvider`によりJPY/USD障害時に`lastGoodJpyRate`でsoft-freezeし、承認済みstaleness threshold以上継続した場合のみ標準shutdown + `lastGoodPrice`へフォールバックする。
- **合格条件**: `PRM-ORACLE-001`の投入、`ORCL-SEC-005`の監視、source差替runbook、`PriceFeedProxy.renounceOwnership()`無効化を確認する。

<a id="sys-risk-002"></a>
### `SYS-RISK-002` dToken backing毀損

- **リスク**: Strategy loss / slashing / hackで`A < L_effective`になると、Coreが名目dTokenを満額担保と誤認しうる。
- **Protocol統制**: Coreへbacking会計は追加しない。Vaultが`backingRatio()`を算出し、Oracleが価格へ下方乗算する（`ORCL-FR-014` / `VAULT-FR-016`）。挙動の設計理由は[`ADR-006`](../../product/architecture/Architecture-Decision-Records.md#adr-006)。
- **合格条件**: 全active feedが正しいVaultを参照し、loss / writeoff / backstop deposit / releaseで価格が下方・回復すること、reserveが通常redeemに先着消費されないことをintegration testと監視で確認する。

<a id="sys-risk-003"></a>
### `SYS-RISK-003` 担保運用益のSP追加報酬

- **リスク**: branchごとのunderlying yieldをJPYdf化し、base-parityのSP預入者へ届ける経路は未接続である。
- **Protocol統制**: Strategy運用益はManifestで指定したProtocol retention Safeに蓄積し、SP追加報酬として表示しない。現行の着金先・照合手順は[`Treasury-Safe-Retention-Runbook`](../../operations/runbooks/Treasury-Safe-Retention-Runbook.md)が持つ。
- **合格条件**: 未接続の追加分配をuser-facing rewardとして表示せず、Core nativeの借入金利75%と清算益だけをSP報酬として扱う。

<a id="sys-risk-004"></a>
### `SYS-RISK-004` async Strategy元本回収

- **リスク**: unstake queue等は即時回収できず、Vaultの同期会計・利益/元本分離と衝突しうる。
- **Activation boundary**: 非同期回収を伴うStrategyは、下記条件を満たすまで有効化しない。releaseごとの採否・weight / capはLaunch Decision / Manifestまたはactivation recordが持つ。
- **合格条件**: 非同期Strategyを非ゼロ配分にする場合、async回収、pending principal、収益/元本分離、borrower disclosure、redemption / refill、loss / writeoff、keeper / incident、withdrawDelay / bufferの再設定を承認する。

<a id="sys-risk-005"></a>
### `SYS-RISK-005` immutable risk parameter

- **リスク**: branch risk parameterはimmutableであり、liquidation penaltyとの静的余裕が小さい構成はdeploy後に修正できない。
- **合格条件**: [Parameter Catalog §4](../../product/parameters/Parameter-Catalog.md#4-parameter-invariants)の`PRM-INV-*`をforge / deploy scriptで検証し、[Collateral Parameter Policy](../../product/policies/Collateral-Parameter-Policy.md)と[Day1 Parameter Decision](../decisions/Day1-Parameter-Decision.md)のgo/no-go条件を満たすbranchだけを開放する。branch別の値と状態は本書へ複製しない。

<a id="sys-risk-006"></a>
### `SYS-RISK-006` Redemptionのfeed revert依存

- **リスク**: Redemptionは全branchを走査するため、1 feedのrevertが全redemptionを止めうる。
- **Protocol統制**: Coreへtry/catchは追加しない。`PriceFeedProxy` constructor / `confirmSource`が`fetchPrice`と`fetchRedemptionPrice`をsmoke-testし、runtimeではsource revert / invalid priceをcatchしてshutdown + fallbackへ流す。
- **合格条件**: 全active / inert sourceがno-revert、ABI正常、nonzero-nonmax、failure=falseを満たす構成検査をdeploy末尾とintegration testで行う。

<a id="sys-risk-007"></a>
### `SYS-RISK-007` 中央集権wrapperのmarket depeg

- **リスク**: 原資産価格だけを参照すると、wrapper固有のmarket depeg、償還停止、transfer restrictionを担保価値へ反映できない。
- **Protocol統制**: wrapperを候補評価する場合も、market / peg legをon-chain PriceFeedへ組み込み、off-chain monitoringだけで代替しない。
- **合格条件**: wrapper固有のdepeg、issuer / custodian、redemption、freeze / blacklist、liquidityを一括承認する（[Oracle](../../product/spec/Oracle.md) `ORCL-FR-013` / `ORCL-SEC-006`）。

<a id="sys-risk-008"></a>
### `SYS-RISK-008` mintCapはbranch debt ceilingではない

- **リスク**: dToken `mintCap` / `pauseDeposit` / cap reductionは新規dToken supplyを止めるが、既存dTokenを担保にしたCoreの`openTrove` / `withdrawJpydf` / `adjustTrove`によるJPYdf debt increaseは止めない。
- **Protocol統制**: Liquity v2 Coreに新しいhard branch debt ceilingは追加しない。露出はdToken `mintCap`、MCR / CCR / SCR、SP coverage、frontend / ops borrowable branch gate、cap ramp承認、redemption / liquidation monitoringで管理する。
- **合格条件**: docs / UI / opsで`mintCap`を「JPYdf発行上限」または「branch debt ceiling」と表示しない。`plannedDebtJpydf`もオンチェーンcapや実行可能な借入余力として扱わず、cap reduction後も既存dToken collateralに対するdebt increaseが残ることを確認する。

<a id="sys-risk-009"></a>
### `SYS-RISK-009` JPYdf上方乖離（供給側防御の非対称）

- **リスク**: Redemptionは下方向への名目¥1の価格圧力を作るが、市場価格の床を保証しない。上方（JPYdf > ¥1）を対称に是正する機構はなく、供給反応は既存dToken collateralまたは現在のcap headroomを使う新規借入に依存する。利用可能なcollateral、借入意思、APRの範囲を需要が超えると上方乖離が固定化しうる。
- **Protocol境界**: 速い供給反応は、任意の適格borrowerが既存collateral / cap headroomの範囲でCoreの通常借入を行い、市場へ供給する経路に限る。Protocolは特定Contributorに追加借入・自己資金拠出・市場売却を義務づけない。現capを超えるdToken supply headroomは[Active Branch Cap Ramp Runbook](../../operations/runbooks/Active-Branch-Cap-Ramp-Runbook.md)に従うProtocol Governanceのcap rampを要する。
- **合格条件**: 実行可能な供給余力を、既存担保の追加借入余力、`cap - totalSupply`で受け入れられる新規担保、その担保からupfront fee込みで借りられるdebtに分け、live stateから算定する。検知条件、承認、実行手順、Evidenceは各Operations artifact、DeltaForesightが自己B/S対応を採用する場合は同社の[B/S Policy](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md)とCommitmentを正本とする。
- **Residual risk**: PSM・自動供給弾力機構は持たない。追加capの拡張はTimelock delay未満に短縮できないため短期の上方乖離を許容する。別の裁定routeを採用しても、新しい供給能力自体を作らないことを確認する。

## 3. 完了条件

1. `SYS-RISK-001..009`の合格条件に、実行済みtest / Manifest / Evidenceの参照がある。
2. 未充足項目はGo / No-Goで明示的にNo-Goまたは承認済みの非公開・非activation scopeへ隔離されている。
3. 本書の合格だけでContributorの資金拠出、Foundation assetの使用、未承認parameter変更を承認済みと扱わない。
