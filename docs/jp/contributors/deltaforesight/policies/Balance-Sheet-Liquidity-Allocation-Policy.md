# DeltaForesight B/S Liquidity Allocation Policy

| Field | Value |
| --- | --- |
| Domain | Contributor: DeltaForesight |
| Lifecycle | Evergreen |
| Artifact Type | Policy |
| Decision Authority | DeltaForesight |
| Maintainer | DeltaForesight |
| Status | Active |

## 1. Scope

本Policyは、DeltaForesight株式会社が自己資金でJPYdfの初期・継続的な流動性を支援する場合の資金bucketと判断境界を定める。具体的なDay 1採用額は[`Day1-Self-BS-Launch-Commitment.md`](../commitments/Day1-Self-BS-Launch-Commitment.md)、算定根拠は[`Day1-Self-BS-Initial-Liquidity-Plan.md`](../commitments/Day1-Self-BS-Initial-Liquidity-Plan.md)を正本とする。

Protocolのpublic branch、利用者向け要件、parameterの意味・値・変更手続は本Policyの対象外であり、Protocol Governanceの正本に従う。DeltaForesightの自己資金commitmentはProtocolの保証、Protocol Treasury、Foundation operating assetsではない。

## 2. Funding buckets

| Bucket | Funding source | Execution | Boundary / normative source |
| --- | --- | --- | --- |
| JPYdf/USDC LP seed | DeltaForesight B/SのUSDCとself-mintしたJPYdf | Uniswap v4 position | dToken backing / Vault bufferではない。routeは[`Liquidity-Route-Policy.md`](../../../protocol/product/policies/Liquidity-Route-Policy.md) |
| Initial JPYdf mint | DeltaForesight B/SのUSDC / wstETHを担保にCoreでmint | `openTrove` | LP seed / pre-seeded SPのJPYdf原資 |
| Pre-seeded SP | self-mintしたJPYdf | `StabilityPool.provideToSP` | liquidation backstop / JITの境界は[`Liquidation-Backstop-And-JIT-Policy.md`](../../../protocol/operations/policies/Liquidation-Backstop-And-JIT-Policy.md) |
| Backstop deposit | DeltaForesight B/Sから対象Underlyingを入金 | `backstopDeposit()` | protected reserve。通常bufferへ移すにはProtocol Governanceによる`releaseBackstopToBuffer()`が必要 |
| JIT / SP top-up capacity | DeltaForesight B/Sまたはmarket makerのJPYdf / USDC | 非原子的な`provideToSP` | planning capacityであり、contractまたはProtocolによる保証ではない |
| JPYdf/JPYC LP seed（dormant） | 発動時にJPYdf/USDC LP seedから再配分（プリセット額は[`Liquidity-Route-Policy.md`](../../../protocol/product/policies/Liquidity-Route-Policy.md) §7） | Uniswap v4 position（発動条件成立まで作成しない） | 発動条件・gateは同Policy §7。dToken backing / Vault bufferではない |

## 3. Decision rules

1. 最初の直接市場流動性はJPYdf/USDC Uniswap v4へ集約する。追加routeの採否はProtocol側のLiquidity Route Policyに従う。JPYdf/JPYC dormant routeの発動条件は同Policy §7に従う。
2. LP、Vault buffer、backstopを相互に代替可能な資金として数えない。LPは価格発見・入口/出口、bufferはdToken holderの請求権reserve、backstopは対象Underlyingによるrepair reserveである。
3. DeltaForesight B/SからStrategyへ直接資金を入れ、Protocol backingと混在させない。repairする場合は対象VaultのUnderlyingを`backstopDeposit()`する。
4. LP / SP / backstopの採用額、funding source、owner、実行時期はDeltaForesightが決定する。ただし、Protocol parameter、Protocol role、利用者資産をDeltaForesightの単独裁量で変更しない。
5. JIT / SP top-up capacityをlaunchまたはpost-launchのcontract guaranteeとして表示しない。

## 4. Initial seed market-risk policy

1. [`Day1-Self-BS-Launch-Commitment.md`](../commitments/Day1-Self-BS-Launch-Commitment.md)で承認した初期seedは、USD/JPY・USDC・wstETH等の価格リスクをヘッジせず、DeltaForesightが自己B/Sで負担する。この判断は承認済みの金額に限り、追加拠出またはexposure拡大を自動承認しない。
2. ヘッジしない方針は、Trove LTV、USDCの健全性、LP在庫、SP取得担保の監視、および返済・縮小・unwindによるexposure管理を否定しない。
3. ヘッジはlaunch requirementとしない。保有exposureと対応し、notionalが実exposure以下のヘッジについて、金利・staking yield・funding・basis等を合算し、借入金利・取引・証拠金調達・運用の各costを差し引いたnet carryが正であり、追加のliquidity・counterparty・margin riskが許容範囲内であれば、収益獲得手段としてDeltaForesightが個別に採否・金額・venueを決定できる。

## 5. Protocol boundary

次の情報は本Policyへ複製しない。

| Information | Normative source |
| --- | --- |
| parameterの意味・単位・制約 | [`Parameter-Catalog.md`](../../../protocol/product/parameters/Parameter-Catalog.md)とcomponent Spec |
| Ethereum mainnet Day 1の値 | [`Parameters.md`](../../../Parameters.md) |
| Day 1のbranch / exposure判断 | [`Mainnet-Launch-Product-Decision-Record.md`](../../../protocol/launch/decisions/Mainnet-Launch-Product-Decision-Record.md) |
| deploy / handover時のfreeze手順 | [`Mainnet-Deploy-Env-Freeze-Runbook.md`](../../../protocol/launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md) |
| post-launchのcap / buffer / liquidity変更 | [`Liquidity-Management-Policy.md`](../../../protocol/operations/policies/Liquidity-Management-Policy.md)と該当Runbook |
| Safe retained yield | [`Treasury-Safe-Retention-Runbook.md`](../../../protocol/operations/runbooks/Treasury-Safe-Retention-Runbook.md) |

Protocol側の値が変更されても、DeltaForesightの自己資金commitmentが自動的に増減したとは扱わない。DeltaForesightのcommitment変更は同社が別途決定し、該当Manifest / Commitment / Evidenceへ反映する。
