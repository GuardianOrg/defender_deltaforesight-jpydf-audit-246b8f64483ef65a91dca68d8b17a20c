# JPY DeFi Parameter Catalog

> Domain: Protocol
>
> Lifecycle: Evergreen
>
> Artifact Type: Spec
>
> Decision Authority: Protocol Governance
>
> Maintainer: DeltaForesight (Contributor)
>
> Status: Active

## 1. 目的と境界

本書は、JPYdfで使用するparameter ID、意味、単位、オンチェーン表現、scope、mutability、decision authority、およびparameter間の不変条件を定義する。

本書は具体的な値、特定environmentのaddress、採用状態、選定理由、承認記録、実行手順、実行結果を持たない。Day1の値は [`Parameters.md`](../../../Parameters.md) のDay1 Parameter Manifestを正本とする。launch後の現行値はon-chain stateを正とし、block付きreadbackはEvidenceとして保存する。

componentの挙動は各component specを正とする。本書の「意味」はparameterを識別するための短い定義であり、setterの要件や失敗条件を再仕様化しない。

## 2. 記載規約

| Field | 意味 |
| --- | --- |
| ID | 文書、proposal、Manifest、Evidenceから参照する安定識別子 |
| Scope | global、branch、oracle source、chain、route等の適用単位 |
| Unit / encoding | human-readable単位とオンチェーン表現 |
| Binding | 値を保持・導出・変更するconstant、storage、setterまたは外部contract |
| Mutability / authority | 値の変更可能性と決定主体。実holderやaddressは含めない |
| Owner spec | parameterを消費するcomponentの規範仕様 |

`deploy immutable`は当該deployment後に変更できない値、`contract constant`はbytecodeへ焼き込まれる値、`GOV mutable`はProtocol Governanceの承認と該当setterで変更できる値を表す。`derived`は別parameterから導出し、独立したon-chain storageを持たない。

### 2.1 Encoding conventions

| Parameter種別 | Human-readable単位 | On-chain encoding |
| --- | --- | --- |
| CR（MCR / CCR / SCR / BCR） | percentage | WAD（`1e18 = 100%`） |
| liquidation penalty | percentage | WAD |
| `bufferTargetBps`、Merkl weight | basis points | `10000 = 100%` |
| `allocatorCooldown`、`withdrawDelay`、staleness、timelock | duration | seconds |
| `mintCap` | dToken quantity | dToken 18 decimals |
| `allocateMaxMove`、`bufferFloor` | underlying quantity | underlying token decimals |
| PIL JPYdf amount | JPYdf quantity | JPYdf 18 decimals |
| allocator weight | ratio | WAD。inactiveは合計0、activeは合計`1e18` |

名目JPY exposureはon-chain値ではない。`mintCap`等を名目額で承認する場合、environment固有の価格、丸め、算出block、encoded値をManifestまたはEvidenceに残す。

## 3. Parameter catalog

### 3.1 Core risk parameters

| ID | 意味 | Scope | Unit / encoding | Binding | Mutability / authority | Owner spec |
| --- | --- | --- | --- | --- | --- | --- |
| `PRM-LLTV` | liquidation可能になるLTV境界 | branch | ratio。`1 / MCR` | on-chain非保持 | derived | [`Liquity-v2-Core-Spec.md`](../spec/Liquity-v2-Core-Spec.md) |
| `PRM-MCR` | 通常時の最小担保率 | branch | WAD | `MCR_D<X>` | deploy immutable / Protocol Governance | `Liquity-v2-Core-Spec.md` |
| `PRM-CCR` | Recovery Modeへ入るbranch担保率 | branch | WAD | `CCR_D<X>` | deploy immutable / Protocol Governance | `Liquity-v2-Core-Spec.md` |
| `PRM-SCR` | shutdown判定に使う担保率 | branch | WAD | `SCR_D<X>` | deploy immutable / Protocol Governance | `Liquity-v2-Core-Spec.md` |
| `PRM-BCR` | batch内で要求する担保率buffer | branch | WAD | `BCR_D<X>` | deploy immutable / Protocol Governance | `Liquity-v2-Core-Spec.md` |
| `PRM-LIQPEN-SP` | Stability Pool清算時の担保penalty | branch | WAD | `LIQUIDATION_PENALTY_SP_D<X>` | deploy immutable / Protocol Governance | `Liquity-v2-Core-Spec.md` |
| `PRM-LIQPEN-RD` | redistribution清算時の担保penalty | branch | WAD | `LIQUIDATION_PENALTY_REDISTRIBUTION_D<X>` | deploy immutable / Protocol Governance | `Liquity-v2-Core-Spec.md` |
| `PRM-LIQ-KEEPER` | liquidatorへ支払う担保補償の率と上限 | branch | divisor / collateral units | `COLL_GAS_COMPENSATION_DIVISOR` / TroveManager cap | deploy時、または予約ブランチ有効化前に一度確定 / Protocol Governance | `Liquity-v2-Core-Spec.md` |

### 3.2 dToken Layer parameters

| ID | 意味 | Scope | Unit / encoding | Binding | Mutability / authority | Owner spec |
| --- | --- | --- | --- | --- | --- | --- |
| `PRM-mintCap` | dToken総供給上限 | branch | dToken 18 decimals | `DToken.setCap` | GOV mutable / Protocol Governance | [`dToken.md`](../spec/dToken.md) `DTKN-FR-006` |
| `PRM-allocCooldown` | `allocate`を連続実行できない最小間隔 | branch | seconds | `CollateralVault.setAllocatorConfig` | GOV mutable / Protocol Governance | [`CollateralVault.md`](../spec/CollateralVault.md) |
| `PRM-allocMaxMove` | `allocate` 1回のbufferからStrategyへの移動上限 | branch | underlying decimals | `CollateralVault.setAllocatorConfig` | GOV mutable / Protocol Governance | `CollateralVault.md` |
| `PRM-withdrawDelay` | 遅延償還requestがclaim可能になるまでの期間 | branch | seconds | `CollateralVault.setWithdrawDelay` | GOV mutable / Protocol Governance | `CollateralVault.md` |
| `PRM-bufferTargetBps` | Vaultが保持するliquid bufferの目標比率 | branch | basis points | `CollateralVault.setBufferConfig` | GOV mutable / Protocol Governance | `CollateralVault.md` |
| `PRM-bufferFloor` | Vaultが保持するliquid bufferの絶対下限 | branch | underlying decimals | `CollateralVault.setBufferConfig` | GOV mutable / Protocol Governance | `CollateralVault.md` |

`PRM-mintCap`はdToken supply / collateral exposure capであり、JPYdfのglobal issuance capまたはCore branch debt ceilingではない。

### 3.3 Oracle parameters

| ID | 意味 | Scope | Unit / encoding | Binding | Mutability / authority | Owner spec |
| --- | --- | --- | --- | --- | --- | --- |
| `PRM-ORACLE-001` | JPY/USD sourceのstaleness threshold | oracle source | seconds | JPY/USD `Oracle.stalenessThreshold` | source deploy immutable / Protocol Governance | [`Oracle.md`](../spec/Oracle.md) |
| `PRM-ORACLE-002` | ETH/USD sourceのstaleness threshold | oracle source | seconds | ETH/USD `Oracle.stalenessThreshold` | source deploy immutable / Protocol Governance | `Oracle.md` |
| `PRM-ORACLE-003` | stETH/USD sourceのstaleness threshold | oracle source | seconds | stETH/USD `Oracle.stalenessThreshold` | source deploy immutable / Protocol Governance | `Oracle.md` |
| `PRM-ORACLE-004` | USDC/USD sourceのstaleness threshold | oracle source | seconds | USDC/USD `Oracle.stalenessThreshold` | source deploy immutable / Protocol Governance | `Oracle.md` |
| `PRM-ORACLE-005` | WBTC/BTC sourceのstaleness threshold | oracle source | seconds | WBTC/BTC `Oracle.stalenessThreshold` | source deploy immutable / Protocol Governance | `Oracle.md` |
| `PRM-ORACLE-006` | JPY rate soft-freezeの最大継続時間 | global | seconds | `JpyUsdRateProvider.MAX_JPY_FREEZE_DURATION` | contract constant / Protocol Governance | `Oracle.md` |

### 3.4 Governance delay parameters

| ID | 意味 | Scope | Unit / encoding | Binding | Mutability / authority | Owner spec |
| --- | --- | --- | --- | --- | --- | --- |
| `PRM-GOV-COMMON-TIMELOCK-DELAY` | 共通governance actionの最小遅延 | governance instance | seconds | external `TimelockController.minDelay` | Timelock self-admin / Protocol Governance | component `*-GOV-*` |
| `PRM-GOV-PRICE-FEED-SOURCE-DELAY` | PriceFeed source差替えの待機時間 | PriceFeedProxy | seconds | `PriceFeedProxy.TIMELOCK_DELAY` | contract constant / Protocol Governance | `Oracle.md` |

実holder class、role state、addressおよびdeploy gateはparameterではない。既存参照を壊さないため、次のIDは改名せずGovernance configuration IDとして維持する。

| ID | 対象 | 正本 |
| --- | --- | --- |
| `PRM-GOV-TIMELOCK-PROPOSER-HOLDER` | `PROPOSER_ROLE` holder | Governance policy / environment Manifest |
| `PRM-GOV-TIMELOCK-EXECUTOR-HOLDER` | `EXECUTOR_ROLE` holder | Governance policy / environment Manifest |
| `PRM-GOV-TIMELOCK-CANCELLER-HOLDER` | `CANCELLER_ROLE` holder | Governance policy / environment Manifest |
| `PRM-GOV-TIMELOCK-EXTERNAL-ADMIN` | `TIMELOCK_ADMIN_ROLE` state | environment Manifest / Evidence |
| `PRM-GOV-WRITEOFF-HOLDER` | `WRITEOFF_ROLE` holder | Governance policy / environment Manifest |
| `PRM-GOV-GUARDIAN-HOLDER` | `GUARDIAN_ROLE` / emergency owner | Governance policy / environment Manifest |
| `PRM-GOV-ALLOCATOR-HOLDER` | `ALLOCATOR_ROLE` holder | Governance policy / environment Manifest |
| `PRM-GOV-PRICE-FEED-OWNER-HOLDER` | `PriceFeedProxy.owner()` holder | Governance policy / environment Manifest |
| `PRM-GOV-DEPLOY-ALLOCATOR-BOUND` | allocator初期値のdeploy gate | launch Gate / Evidence |

### 3.5 Bridge parameters

| ID | 意味 | Scope | Unit / encoding | Binding | Mutability / authority | Owner spec |
| --- | --- | --- | --- | --- | --- | --- |
| `PRM-BRIDGE-MINTER-TIMELOCK` | bridge minter追加のproposeからconfirmまでの待機時間 | JPYdfToken | seconds | `JpydfToken.BRIDGE_MINTER_TIMELOCK` | contract constant / Protocol Governance | [`JpydfToken.md`](../spec/JpydfToken.md) |
| `PRM-BRIDGE-GLOBAL-SUPPLY-CAP` | remote canonical JPYdf supplyの全体上限 | global | JPYdf 18 decimals | bridge adapter / operations accounting | activation-defined / Protocol Governance | bridge adapter spec |
| `PRM-BRIDGE-PER-CHAIN-CAP-<chain>` | remote canonical JPYdf supplyのchain別上限 | chain | JPYdf 18 decimals | bridge adapter | activation-defined / Protocol Governance | bridge adapter spec |
| `PRM-BRIDGE-ROUTE-HOURLY-LIMIT-<route>` | route別rolling 1時間mint上限 | route | JPYdf 18 decimals | bridge adapter | activation-defined / Protocol Governance | bridge adapter spec |
| `PRM-BRIDGE-ROUTE-DAILY-LIMIT-<route>` | route別rolling 24時間mint上限 | route | JPYdf 18 decimals | bridge adapter | activation-defined / Protocol Governance | bridge adapter spec |

adapterが存在しないparameterはFuture lifecycleであり、現行値や現行運用状態を持たない。

### 3.6 PIL / liquidity incentive parameters

| ID | 意味 | Scope | Unit / encoding | Binding | Mutability / authority | Owner spec |
| --- | --- | --- | --- | --- | --- | --- |
| `PRM-PILA-EPOCH-DURATION` | PIL distribution epochの長さ | PIL deployment | seconds | `PILAllocator.EPOCH_DURATION` / `UniV4MerklInitiative.EPOCH_DURATION` | deploy immutable / Protocol Governance | [`PILAllocator.md`](../spec/PILAllocator.md) |
| `PRM-PILA-MIN-DISTRIBUTE` | allocatorがdistributionを実行する最小額 | PIL deployment | JPYdf 18 decimals | `PILAllocator.MIN_DISTRIBUTE` | deploy immutable / Protocol Governance | `PILAllocator.md` |
| `PRM-PILA-MAX-INITIATIVES` | initiative登録数の上限 | PIL deployment | count | `PILAllocator.MAX_INITIATIVES` | contract constant / Protocol Governance | `PILAllocator.md` |
| `PRM-PILA-ALLOCATOR-WEIGHTS` | initiative間の配分比率 | PIL deployment | WAD | `PILAllocator.setWeights` | GOV mutable / Protocol Governance | `PILAllocator.md` |
| `PRM-PILA-MERKL-CAMPAIGN-THRESHOLD` | Merkl campaignを作成する最小額 | initiative | JPYdf 18 decimals | `UniV4MerklInitiative.CAMPAIGN_JPYDF_AMOUNT_THRESHOLD` | deploy immutable / Protocol Governance | `PILAllocator.md` |
| `PRM-PILA-CAMPAIGN-CREATOR` | 優先campaign creator | initiative | address | `UniV4MerklInitiative.CAMPAIGN_CREATOR` | deploy immutable / Protocol Governance | `PILAllocator.md` |
| `PRM-PILA-CAMPAIGN-CREATION-WINDOW` | permissionless campaign creationを開く期間 | initiative | seconds | `UniV4MerklInitiative.CAMPAIGN_CREATION_WINDOW` | deploy immutable / Protocol Governance | `PILAllocator.md` |
| `PRM-PILA-MERKL-DISTRIBUTION-CREATOR` | Merkl DistributionCreator | initiative | address | `UniV4MerklInitiative.merklDistributionCreator` | deploy immutable / Protocol Governance | `PILAllocator.md` |
| `PRM-PILA-UNIV4-POOL-ID` | incentive対象のUniswap v4 pool | initiative | bytes32 | `UniV4MerklInitiative.UNIV4_POOL_ID` | deploy immutable / Protocol Governance | `PILAllocator.md` |
| `PRM-PILA-MERKL-WEIGHTS` | fee / token0 / token1のMerkl weight | initiative | basis points | `WEIGHT_FEES` / `WEIGHT_TOKEN_0` / `WEIGHT_TOKEN_1` | deploy immutable / Protocol Governance | `PILAllocator.md` |
| `PRM-PILA-OUT-OF-RANGE` | out-of-range liquidityをincentive対象にするか | initiative | bool | `IS_OUT_OF_RANGE_INCENTIVIZED` | contract constant / Protocol Governance | `PILAllocator.md` |

## 4. Parameter invariants

| ID | 不変条件 | 強制・検証境界 |
| --- | --- | --- |
| `PRM-INV-001` | branchごとに `SCR < MCR < CCR` | deploy preflight / readback |
| `PRM-INV-002` | `MCR = 1 / LLTV` | parameter derivation / review |
| `PRM-INV-003` | `LIQUIDATION_PENALTY_SP ≤ LIQUIDATION_PENALTY_REDISTRIBUTION` | deploy preflight / readback |
| `PRM-INV-004` | `MCR × (COLL_GAS_COMPENSATION_DIVISOR − 1) ≥ (1 + LIQUIDATION_PENALTY_SP) × COLL_GAS_COMPENSATION_DIVISOR` および `1 + LIQUIDATION_PENALTY_REDISTRIBUTION ≤ MCR` | deploy preflight / finalization / boundary test |
| `PRM-INV-005` | `LIQUIDATION_PENALTY_SP ≥ MIN_LIQUIDATION_PENALTY_SP` かつ `LIQUIDATION_PENALTY_REDISTRIBUTION ≤ MAX_LIQUIDATION_PENALTY_REDISTRIBUTION` | contract constants / deploy preflight |
| `PRM-INV-006` | `SCR ≥ 1 + URGENT_REDEMPTION_BONUS` | deploy preflight / boundary test |
| `PRM-INV-007` | `bufferTargetBps ≤ 10000`。必要bufferは `max(managedUnderlying × bufferTargetBps / 10000, bufferFloor) + pendingWithdrawals` | contract setter / configuration review / on-chain monitoring |

`PRM-INV-007`は、従来の「`bufferFloor ≤ bufferTarget`」という単位の異なる比較を置き換える。`bufferTargetBps`は比率、`bufferFloor`はunderlying数量であるため直接比較せず、[`CollateralVault.md`](../spec/CollateralVault.md)が定義する必要buffer式で評価する。

## 5. 参照方法

- parameterの意味、単位、mutabilityまたは不変条件が必要な文書は、本書の該当IDを参照する。
- Ethereum mainnet Day1の値が必要な文書は[`Parameters.md`](../../../Parameters.md)を参照する。他のenvironment / releaseは、それぞれのManifestを参照する。
- 実行手順は該当Runbook / Gate、個別判断はDecision Record、実行結果はEvidenceを参照する。
- component spec内で値や採用状態を必要としない場合、parameter文書への一般的な「関連文書」リンクは置かない。
