# JPY DeFi Deployment Configuration Spec

| Field | Value |
| --- | --- |
| Domain | Contributor: DeltaForesight |
| Lifecycle | Evergreen |
| Artifact Type | Spec |
| Decision Authority | DeltaForesight |
| Maintainer | DeltaForesight |
| Status | Active |

## 0. Scope

本Specは`DeployLiquity2.s.sol`のdeployment mode、wiring、生成Manifest schema、env validation、deploy-tail verificationを定める。Protocolが採用するbranch、parameter値、role holder、外部addressを本書では決定しない。

特定environmentの値はManifest、Day 1の承認値は[`Parameters.md`](../../Parameters.md)とLaunch文書、実行結果はEvidenceを正本とする。

---

## 1. Source of Truth

| 対象 | 正とする入力 / 出力 | 備考 |
| --- | --- | --- |
| Day-1 公開 branch | `documents/jp/protocol/launch/decisions/Mainnet-Launch-Product-Decision-Record.md` §1 | deploy実装は採否を再決定せずManifestへ反映する |
| Strategy venue 採用 | `documents/jp/protocol/operations/policies/Strategy-Selection-Policy.md` | selector の実装対応は production 採用を意味しない |
| Ethereum mainnet Day 1のparameter値 | `documents/jp/Parameters.md` | MCR/CCR/SCR/BCR、mintCap、withdrawDelay等の正本 |
| mainnet external address / env freeze | `documents/jp/protocol/launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md` | broadcast候補ごとのManifest / Evidenceを生成する |
| Protocol role holder | `documents/jp/protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md` | env・handover・readbackと照合する |
| deploy 実装 | `contracts/script/DeployLiquity2.s.sol` | `DEPLOYMENT_MODE` と `chainid` により mainnet gate / local-test wiring が変わる |
| deploy CLI | `contracts/utils/deploy-cli.ts` | `./deploy local/mainnet` の UX wrapper。実体は Forge script |
| current deploy output | generated `contracts/deployment-manifest.json` | deploy script が生成する git-ignored output。frontend / ops / bot / local verification が読む現行 manifest。旧 schema / 手置き address snapshot は不可 |

---

## 2. Deployment Modes

| `DEPLOYMENT_MODE` | 役割 | Manifest | 主な用途 |
| --- | --- | --- | --- |
| `complete` | JPYdfToken、core、governance、branch 群を一括 deploy | full manifest | 通常 deploy |
| `jpydf-only` | JPYdfToken のみ deploy | `{"jpydfToken": ..., "bridgeAdmin": ..., "bridgeMinterCount": 0, "proposedBridgeMinter": ..., "launchEvidence": ...}` | CREATE2 address 固定・事前確認 |
| `use-existing-jpydf` | 既存 JPYdfToken を検証して core 以降を deploy | full manifest | token address を先に固定した後の本体 deploy |

`use-existing-jpydf` は、対象 token の `totalSupply == 0`、`collateralRegistryAddress == 0`、`owner == deployer`、`bridgeAdmin == DF_BRIDGE_ADMIN`、`bridgeMinterCount == 0`、`proposedBridgeMinter == address(0)` を要求する。既に mint / registry 設定済み、または bridge proposal / minter 登録済みの token を流用するモードではない。

---

## 3. Chain / Wiring Matrix

| Chain / condition | Branch count | Core collateral | PriceFeed | `dfYield[]` | Status |
| --- | ---: | --- | --- | --- | --- |
| mainnet + `complete` + `DF_ENABLE_MAINNET_DTOKEN_WIRING=true` | 8 | active 3 + inert 5 | active 3 = `PriceFeedProxy` + production source、inert 5 = placeholder | あり | Day-1 production path |
| mainnet + `complete` without `DF_ENABLE_MAINNET_DTOKEN_WIRING=true` | - | - | - | - | revert: `DeployLiquity2: mainnet dToken wiring disabled` |
| mainnet + `jpydf-only` | 0 | - | - | なし | JPYdfToken only |
| local anvil `31337` | 8 | active 3 + inert 5 | production-parity local source / placeholder | あり | production-parity local |
| Sepolia `11155111` | 8 | active 3 + inert 5 | test source / placeholder | あり | rehearsal |
| other non-mainnet | 8 | active 3 + inert 5 | same as non-mainnet | あり | requires `DF_ALLOW_TEST_WIRING=true` |

mainnet では `DF_ENABLE_MAINNET_DTOKEN_WIRING=true` を明示しない限り 8 branch path には入らない。legacy 3-branch deploy path は Day-1 方針と manifest consumer の前提から外れたため削除済み。

---

## 4. Branch Wiring Shape

現行の`complete` modeは`NUM_DF_BRANCHES = 8`を固定順で出力し、`NUM_DF_ACTIVE_BRANCHES = 2`（index 0–1）だけをactive wiring、index 2–7をinertとする。

| Index | dToken / Underlying | State | Deploy expectation |
| ---: | --- | --- | --- |
| 0 | `dwstETH / wstETH` | configurable active wiring | dToken + Vault + composite PriceFeed（`DFWstETHPriceFeed`）+ CollateralYieldZapper（native-ETH staking route は `DF_ZAPPER_EXPECTED_STETH_0` で gate）。Strategyはenvで明示。`DF_UNDERLYING_0` は script 既定値を持たない必須 env（protocol WETH は gas compensation 専用） |
| 1 | `dUSDC / USDC` | configurable active wiring | dToken + Vault + PriceFeedProxy + CollateralYieldZapper。Strategyはenvで明示 |
| 2 | `dETH / TBD` | inert wiring | Underlyingなし、placeholder PriceFeed、cap 0、Strategy / CollateralYieldZapperなし |
| 3 | `dUSD-A / TBD` | inert wiring | same |
| 4 | `dBTC / TBD` | inert wiring | same |
| 5 | `dUSD-B / TBD` | inert wiring | same |
| 6 | `dJPY / TBD` | inert wiring | same |
| 7 | `dJGB / TBD` | inert wiring | same |

active / inert、public / non-public、cap、Strategy setはenvironment / releaseごとの承認済みManifestから入力する。現行Day 1値は[`Parameters.md`](../../Parameters.md)と[`Mainnet-Deploy-Env-Freeze-Runbook.md`](../../protocol/launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md)を参照する。

### 4.1 Proxy initialization boundary

`DToken` / `CollateralVault` は互いの address を初期化時に検証する circular dependency を持つため、`DeployLiquity2` は `YieldLayerProxyDeployer` を使い、1 helper transaction の中で両 proxy を deploy してから `DToken.initialize` / `CollateralVault.initialize` / active branch の `setAllowedUnderlying` / `setTokenInfo`（inert branch は `cap=0`）まで完了させる。これにより mainnet broadcast 中に外部から触れる未初期化 `DToken` / `CollateralVault` proxy window を作らない。 `AddressesRegistry.setAddresses` 後、deployer は各 dToken の `setRiskParamsRegistry` に対応 Registry を設定し、デプロイ後の検証で一致を確認する。cap は初期値0を維持し、ブランチのリスク設定確定後に開放する。

helper transaction 完了直後の `DToken` は `pendingOwner == deployer` の 2-step ownership 待ちであり、`DeployLiquity2` は直後に `acceptOwnership()` を実行して owner を deployer に確定する。これは未初期化状態ではなく、handover 前の一時的な deployer ownership である。最終 holder は `PrepareDFGovernanceHandover` / `VerifyDFGovernanceHandover` / holder 側 `acceptOwnership` で確定する。

nonzero Strategy proxy は `ERC1967Proxy` constructor calldata で `initialize` を同時実行する。Aave / ERC4626 / MorphoV2 / Sky の各 Strategy について、proxy address が外部から観測可能になった時点で `vault` / `underlying` / owner / upgrader / venue address は設定済みでなければならない。

各 UUPS implementation（`DToken` / `CollateralVault` / `BaseStrategy` 派生 Strategy）は constructor で `_disableInitializers()` を呼ぶ。deploy evidence では proxy 側の初期化状態だけでなく、implementation address への直接 `initialize` が拒否されることも確認対象にする。

---

## 5. Manifest Contract

現行 consumer は deploy script が生成した `deployment-manifest.json` だけを読む。`deployment-manifest.json` は git-ignored 生成物であり、旧 schema のローカル残骸や手置き address snapshot を current manifest として扱わない。

必須 top-level:

- `constants`
- `collateralRegistry`
- `jpydfToken`
- `bridgeAdmin`
- `bridgeMinterCount`
- `proposedBridgeMinter`
- `launchEvidence`
- `hintHelpers`
- `multiTroveGetter`
- `liquidationCandidateGetter`
- `debtInFrontHelper`
- `redemptionHelper`
- `branches[]`
- `governance`

DF wiring 時のみ:

- `dfYield[]`
  - `dToken`
  - `collateralVault`
  - `collateralYieldZapper`
  - `treasury`
  - `strategies[]`
    - `strategy`
    - `strategyKind`
    - `strategyWeightBps`
    - `strategyCap`
  - `underlying`

`dfYield.length` は `branches.length` と一致させる。inert branch は `underlying == address(0)`、`strategies.length == 0`、`collateralYieldZapper == address(0)` として出力される。active branch でも `DF_STRATEGY_KIND_i=none` を明示した場合は `strategies.length == 0` として出力されるが、Underlying / CollateralYieldZapper / PriceFeed は通常どおり active のまま残る。Strategy が 1 件以上ある branch は、`strategies[]` を唯一の manifest source とする。fresh deploy 方針のため、互換用の top-level `strategy` / `strategyKind` / `strategyWeightBps` / `strategyCap` は出力しない。

現行DF dToken deploy pathはupstream-derived `wethZapper` / `gasCompZapper` / `leverageZapper` を deploy せず、manifest field も出力しない。user-facing Zapper は `dfYield[].collateralYieldZapper` を正本とする。

### 5.1 Artifact State Transition

deployment artifact setは`Candidate → Deployed → Verified`の順に進む。状態は既存snapshotのfieldを後から書き換えて表現せず、次のartifactが前段のdigestを参照することで確定する。

| State | Artifact / authority | Entry condition | Exit condition |
| --- | --- | --- | --- |
| `Candidate` | 承認前または承認済みのParameter / holder Manifest、env freeze package、source commit | chain / release scope、入力正本、candidate env、toolchain、source commitが特定されている | applicable Launch GateとGovernance recordがbroadcastを承認 |
| `Deployed` | deploy scriptが生成した`deployment-manifest.json`とbroadcast receipt / transaction set | approved Candidateと同じsource commit・input digestでtarget chainへbroadcastし、生成Manifestとtransaction setを保存 | target chain上のcode / wiring / holder / parameter readbackを特定blockで完了 |
| `Verified` | immutable `deployment-verification.json` Evidence | §5.2のrequired fieldが揃い、manifest digest・broadcast・on-chain readback・Governance referenceが全て一致 | terminal snapshot。修正せず、変更時は新しいCandidateから別artifact setを作る |

補足:

- `deployment-manifest.json`が存在するだけでは`Verified`ではない。
- `Candidate`はexpected stateであり、contract addressやon-chain holderの実在を表明しない。
- `Deployed`はtransactionが送信・採掘された事実を表すが、全readbackの一致やGovernance handover完了を表明しない。
- `Verified`は指定blockのsnapshotであり、post-launch current stateではない。後続変更はJIP / execution recordと、新しいblockを基準に生成するcurrent-state artifactで追跡する。
- mismatch、reorg、wrong chain、unapproved input、partial broadcastは`Verified`へ進めない。失敗Evidenceを保持し、既存artifactを上書きせず新Candidateを作る。

### 5.2 Verified Deployment Evidence Schema

`deployment-verification.json`はgenerated `deployment-manifest.json`を複製せず、digestとreadback結果を束ねるEvidence envelopeとする。

```json
{
  "schemaVersion": 1,
  "artifactType": "deployment-verification",
  "state": "Verified",
  "chainId": 1,
  "deploymentMode": "complete",
  "sourceCommit": "<40 or 64 lowercase hex>",
  "parameterManifestRef": "documents/jp/Parameters.md@<sourceCommit>",
  "holderManifestRefs": [
    "documents/jp/protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md@<sourceCommit>"
  ],
  "deploymentManifest": {
    "path": "deployment-manifest.json",
    "sha256": "<64 lowercase hex>"
  },
  "broadcastEvidence": {
    "sha256": "<64 lowercase hex>",
    "transactions": ["0x<64 lowercase hex>"]
  },
  "verification": {
    "blockNumber": 0,
    "blockHash": "0x<64 lowercase hex>",
    "observedAt": "YYYY-MM-DDTHH:MM:SSZ",
    "verifierCommit": "<40 or 64 lowercase hex>",
    "result": "PASS",
    "checks": {
      "code": "PASS",
      "wiring": "PASS",
      "holders": "PASS",
      "parameters": "PASS",
      "launchEvidence": "PASS"
    }
  },
  "governanceRecords": []
}
```

| Field | Rule |
| --- | --- |
| `schemaVersion` | 現行はinteger `1` |
| `artifactType` | `deployment-verification`固定 |
| `state` | 全check PASS時のみ`Verified`。失敗出力に`Verified`を使用しない |
| `chainId` | RPC応答のchain IDとbroadcast対象が一致 |
| `deploymentMode` | `complete` / `jpydf-only` / `use-existing-jpydf` |
| `sourceCommit` | deploy scriptと承認済み入力を含むcommit。dirty worktreeは不可 |
| `parameterManifestRef` / `holderManifestRefs` | pathだけでなく`sourceCommit`または別の固定revisionへbindする |
| `deploymentManifest.sha256` | 検証対象bytesのSHA-256。整形・key sort後ではなく保存artifactそのものをhashする |
| `broadcastEvidence` | broadcast transaction setを一意に再構成できるartifact digestとtx hash |
| `verification.blockNumber` / `blockHash` | 同じRPC readback snapshotを固定する。`latest`だけを記録しない |
| `verification.verifierCommit` | readback / validation codeのrevision |
| `verification.result` | 全required check PASS時のみ`PASS` |
| `verification.checks` | §7のcode / wiring / holder / parameter / launch Evidenceを最低限含む |
| `governanceRecords` | [`Governance-Record-Reference-Spec.md`](../../Governance-Record-Reference-Spec.md)に準拠するreference envelope。Decision本文を複製しない |

Verified Evidenceの生成処理は次をfail-closedにする。

1. required field欠落、未知schema version、未知deployment mode
2. manifest / broadcast digest不一致
3. chain ID、verification block hash、transaction receiptの不一致
4. source commitまたは承認済みManifest referenceがmutable / dirty / unresolved
5. §7のいずれかのreadback failure
6. `governanceRecords`のApproved profile不足またはpackage hash不一致
7. secret、private key、RPC credential、private Foundation locatorの混入

実装時はJSON Schemaとpositive / negative fixtureを同じPRで追加し、validatorが走査対象0件を成功扱いしないことを確認する。

---

## 6. Deploy Env Checklist

### Base deploy

| Env / option | 必須性 | 意味 |
| --- | --- | --- |
| `DEPLOYER` | 必須 | public deployer address のみ。秘密鍵は指定不可。署名は `./deploy` の Ledger（default）/ `--account`（Foundry keystore）/ `--aws`（AWS KMS）/ `--trezor`、または local/fork 限定の `--unlocked` で行う |
| `DEPLOYMENT_MODE` | default `complete` | `complete` / `jpydf-only` / `use-existing-jpydf` |
| `SALT` | 実装上は任意、mainnet production は必須 | CREATE2 salt。未指定時の `block.timestamp` fallback は local / test 用であり、mainnet broadcast では [`Mainnet-Deploy-Env-Freeze-Runbook.md`](../../protocol/launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md) に従って明示 freeze する |
| `DF_BRIDGE_ADMIN` | mainnet / Sepolia / unknown non-mainnet で必須（local 31337 は未指定なら `LocalBridgeAdmin` を deploy） | `JpydfToken` の bridge-ready dormant extension holder。mainnet は Safe / Timelock contract、deployer と同一不可。token 本体も contract-only を強制する |
| `DF_ENABLE_MAINNET_DTOKEN_WIRING` | mainnet production only | mainnet `complete` を 8 branch dToken wiring に切替 |
| `DF_ALLOW_TEST_WIRING` | unknown non-mainnet only | unrecognized chain で local/test wiring を許可 |
bool env は `true` / `1` / `yes` だけを有効扱いにする。`false` / `0` / unset は無効扱い。

### DF dToken wiring

| Env | 必須性 | 意味 |
| --- | --- | --- |
| `DF_TREASURY` | DF wiring で必須 | Vault treasury 初期値 |
| `DF_INTEREST_ROUTER_RECIPIENT` | DF wiring で必須 | PIL recipient |
| `DF_INTEREST_ROUTER_OWNER` | DF wiring で必須 | InterestRouterForwarder owner |
| `DF_JPY_USD_FEED` | mainnet DF wiring で必須 | 全 active branch 共通の JPY/USD feed |
| `DF_JPY_USD_STALENESS` | mainnet DF wiring で必須 | JPY/USD staleness threshold |
| `DF_UNDERLYING_0..1` | active branch のみ | wstETH / USDC。Branch 2–7 は未設定 |
| `DF_COLL_USD_FEED_0..1` | mainnet active branch で必須 | stETH/USD（Branch 0 dwstETH の market leg）/ USDC/USD |
| `DF_COLL_USD_STALENESS_0..1` | mainnet active branch で必須 | active branch の collateral/USD staleness threshold |
| `DF_STRATEGY_KIND[_i]` | active branch で必須 | `aave` / `erc4626` / `morpho-v2` / `sky-susds` / `none`（`lido` / `etherfi-weeth` kind は wstETH branch swap で廃止済み） |
| `DF_STRATEGY_WEIGHT_BPS[_i]` | active branch で必須 | Vault strategy weight。`none` では `0` 必須 |
| `DF_STRATEGY_CAP[_i]` | active branch で必須 | Strategy cap。`none` では `0` 必須 |
| `DF_STRATEGY_COUNT_i` | 任意 | branch に複数 Strategy を自動 deploy/register する場合の Strategy 数。未指定なら単一 Strategy env を読む |
| strategy-kind specific env | kind に応じて必須 | Aave / ERC4626 / MorphoV2 / Sky addresses 等（退役した Lido / Etherfi の env reader は kind とともに削除済み） |

`LidoStrategy.sol` / `EtherfiWeETHStrategy.sol` と専用 test は **archived** であり（`contracts/src/Strategies/archive/` / `contracts/test/archive/`）、active な production source / audit scope ではない（[Contract-Audit-Scope-And-nSLOC](./Contract-Audit-Scope-And-nSLOC.md) 3.5 節）。公式 deploy script の `lido` / `etherfi-weeth` selector、deploy / register helper、専用 env reader は PR #1424 で削除済みで、`lido` 指定は generic unknown-kind fallback で失敗する。専用 reject を preflight / manifest へ重ねず、承認済み Strategy set、生成 Manifest、Vault 登録件数の汎用照合を非採用の正本とする。

`DF_STRATEGY_KIND_i=aave` は mainnet では `DF_STRATEGY_AAVE_POOL_i` と `DF_STRATEGY_AAVE_ATOKEN_i` が必須で、Aave V3 Ethereum の production Pool / branch Underlying に対応する aToken を明示する。non-mainnet は production Strategy 実装 + local Aave venue の production-parity drill を維持する。Day-1 の freeze 値と fork dry-run 手順は [`Mainnet-Deploy-Env-Freeze-Runbook.md`](../../protocol/launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md) を参照する。

`DF_STRATEGY_KIND_i=none` は「運用先なし」を明示するための値であり、deploy し忘れを黙認する escape hatch ではない。`DeployLiquity2` は `none` の branch で `DF_STRATEGY_WEIGHT_BPS_i == 0`、`DF_STRATEGY_CAP_i == 0`、Vault 登録 Strategy 数 0 を要求する。handover / verify / local accept helper は manifest の `strategies[]` 件数と Vault 登録 Strategy 数を照合し、`none` branch では `strategies.length == 0` を要求する。

branchごとのStrategy採否、kind、weight、capは本Specで決めない。Ethereum mainnet Day 1の値は[`Mainnet-Deploy-Env-Freeze-Runbook.md`](../../protocol/launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md)でfreezeし、生成Manifestとon-chain readbackで照合する。`withdrawDelay` / `bufferTargetBps` 等のparameter値は対象environment / releaseのParameter Manifestを正本とする。

複数 Strategy branch では `DF_STRATEGY_COUNT_i=N` を設定し、各 Strategy の env を
`DF_STRATEGY_KIND_i_j` / `DF_STRATEGY_WEIGHT_BPS_i_j` / `DF_STRATEGY_CAP_i_j`
および kind 固有 env の `..._i_j` 形式で指定する。例: dUSDC branch（index 1）で Aave + Morpho Vault V2 にする場合、
`DF_STRATEGY_COUNT_1=2`、`DF_STRATEGY_KIND_1_0=aave`、
`DF_STRATEGY_KIND_1_1=morpho-v2`、`DF_STRATEGY_MORPHOV2_VAULT_1_1` と
freeze 済み weight を設定する。
配列形式の中に `none` は入れない。`none` は単独 branch の「Strategy なし」だけを表す。

Strategy kind の選択は [Strategy 要件定義](../../protocol/product/spec/strategies/Strategy.md) §2.2 と
[`Collateral-Asset-Management-Policy.md`](../../protocol/operations/policies/Collateral-Asset-Management-Policy.md) に従う。
`asset()==underlying` の ERC-4626 venue は `erc4626` で足りるため venue 専用 kind を増やさない。
Underlying を別 asset へ変換する運用（USDC -> sUSDS、WETH -> weETH 等）は、専用
asset-transforming Strategy と preflight / runbook が必要である。現行実装では
`sky-susds`（USDC -> USDS -> sUSDS）と `morpho-v2`（Morpho Vaults V2。max\* view が設計上 0 のため `erc4626` 不適格）が追加済み。
それ以外の route は設定だけでは採用しない。

`sky-susds` は dUSDC branch（branch index 1）専用であり、`DeployLiquity2` は branch index と
deployment-wide `USDC` address の両方を検証する。USDT や任意の 6 decimals token を
Sky converter に流す設定は deploy 時に fail-fast させる。

追加 kind の env:

| kind | 必須 env |
| --- | --- |
| `erc4626` | `DF_STRATEGY_ERC4626_VAULT_i` |
| `morpho-v2` | `DF_STRATEGY_MORPHOV2_VAULT_i` |
| `sky-susds` | `DF_STRATEGY_SKY_USDS_i`, `DF_STRATEGY_SKY_SUSDS_VAULT_i`, `DF_STRATEGY_SKY_USDC_USDS_PSM_WRAPPER_i`, `DF_STRATEGY_SKY_MAX_CONVERSION_LOSS_BPS_i`。converter は deploy script が wrapper を immutable に束縛して新規 deploy |

`DeployLiquity2` は kind 固有の外部 venue address（Aave Pool / aToken、ERC-4626 vault、
Morpho Vaults V2 vault、Sky USDS / sUSDS / converter）が
`address(0)` または codeless address の場合は fail-fast する。referral 等の任意アドレスは
この contract-only preflight の対象外である。

任意 env:

| kind | 任意 env |
| --- | --- |
| `morpho-v2` | `DF_STRATEGY_MORPHOV2_MAX_PENALTY_BPS_i`（既定 `200`。200 bps 超は拒否） |

`CollateralVault` 自体は 1 branch に複数 Strategy を登録でき、`DeployLiquity2` も
`DF_STRATEGY_COUNT_i` 配列形式で branch 1 の Aave + Morpho Vault V2 のような複数 Strategy 初期登録に対応する。
deploy-tail verify は Vault 登録数、primary strategy、各 Strategy の `vault()` / `underlying()`、
および total weight 非ゼロを確認する。governance prepare / verify / accept helper は live Vault の
登録 Strategy 一覧を走査するため、secondary Strategy も primary と同じ owner / upgrader handover 対象になる。

Handover / activation では別途 `PrepareDFGovernanceHandover.s.sol` と `VerifyDFGovernanceHandover.s.sol` が `DF_TIMELOCK`、`DF_GUARDIAN`、`DF_ALLOCATOR`、`DF_WRITEOFF`、`DF_PRICE_FEED_OWNER`、`DF_STRATEGY_OWNER`、`DF_STRATEGY_UPGRADER`、branch ごとの `DF_DTOKEN_CAP_i` などを要求する。

---

## 7. Deploy-Tail Verification

DF wiring では script 末尾で以下を fail-fast する。

- registry token / troveManager が branch contract と一致する
- `PriceFeedProxy.borrowerOperations()` と `AddressesRegistry.priceFeed()` が一致する
- `fetchPrice()` / `fetchRedemptionPrice()` が nonzero / nonmax / nonfailed
- core collateral が dToken である
- dToken と Vault が相互に一致する
- Vault treasury が `DF_TREASURY` と一致する
- active branch の backingRatio が `1e18`
- active feed source が当該 branch の Vault を参照する
- active Strategy がある場合は Vault / underlying と一致する。`DF_STRATEGY_KIND_i=none` の active branch は `dfYield[i].strategies.length == 0`、Vault 登録 Strategy 数 0、`totalWeightBps == 0` を確認する
- active CollateralYieldZapper が Vault / dToken / BO / JPYdf / underlying と一致する
- inert branch は underlying なし、cap 0、CollateralYieldZapper なし
- all branches の `interestRouter` が単一 `InterestRouterForwarder` で、token / recipient / owner / pendingOwner が期待値と一致する
- JPYdf token の `bridgeAdmin` が `DF_BRIDGE_ADMIN` と一致し、contract address であり、`bridgeMinterCount == 0`、`proposedBridgeMinter == address(0)` である
- manifest の `launchEvidence` は bridge adapter なし、Day-1 方針外の JPYdf liquidity route なし、JPYdf/USDC v4 route は `unwired-audit-scope` または承認済み adapter address 付き `enabled` のどちらかである

この検証は non-mainnet DF wiring と mainnet opt-in DF wiring の品質を担保するが、mainnet 実値 env の freeze と fork dry-run の代替にはならない。

---

## 8. Environment-specific artifacts

| Artifact | Role |
| --- | --- |
| [`Parameters.md`](../../Parameters.md) | Ethereum mainnet Day 1のparameter Manifest |
| [`Mainnet-Protocol-Role-Holder-Manifest.md`](../../protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md) | Ethereum mainnet Day 1のexpected Protocol holder |
| [`Mainnet-Deploy-Env-Freeze-Runbook.md`](../../protocol/launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md) | external address・env・salt・toolchainをfreezeし、Manifest / Evidenceを生成する手順 |
| generated `contracts/deployment-manifest.json` | 特定deploy実行のaddress / wiring / holder / parameter出力 |
| generated `deployment-verification.json` | manifest digest、broadcast、Governance approval、特定blockのon-chain readbackを束ねるVerified Evidence |
| launch Evidence package | generated Manifestとon-chain readbackの照合結果 |

本Specへ特定実行のaddress、block、transaction、hashを追記しない。schemaまたはvalidation ruleが変わる場合だけ本書を更新する。
