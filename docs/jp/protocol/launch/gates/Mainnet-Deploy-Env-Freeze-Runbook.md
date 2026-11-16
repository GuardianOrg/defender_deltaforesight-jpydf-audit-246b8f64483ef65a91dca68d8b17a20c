# Mainnet Deploy Env Freeze Runbook

> **位置づけ**: `DeployLiquity2.s.sol` の mainnet dToken wiring を fork dry-run / broadcast する前に、外部依存アドレスと env の凍結状態を確認する runbook。deploy mode / manifest schema の設計整理は [`Deployment-Configuration-Spec.md`](../../../engineering/guides/Deployment-Configuration-Spec.md)、担保・リスク値の正本は [Day1 Parameter Manifest](../../../Parameters.md)、holder候補値はProtocol / Contributorの各Manifest、Protocol Safe / Timelock thresholdは[`Mainnet-Role-Assignment-Safe-Threshold-Policy.md`](./Mainnet-Role-Assignment-Safe-Threshold-Policy.md)を参照し、[`Mainnet-Safe-Role-Assignment-Gate.md`](./Mainnet-Safe-Role-Assignment-Gate.md)で統合検証する。
> **staleness の扱い**: 承認済み値はDay1 Parameter Manifestの`PRM-ORACLE-*`を正本とする。未freezeの非JPY候補値は [判断記録](../decisions/non-jpy-oracle-staleness-threshold-rationale.md) に置き、broadcast前に公式metadata、current `latestRoundData.updatedAt`、fork block、risk owner sign-offをevidence化してManifestへ反映する。

---

## 1. Scope

対象は Ethereum mainnet の `DEPLOYMENT_MODE=complete` + `DF_ENABLE_MAINNET_DTOKEN_WIRING=true` path。

- [`config/day1-branch-manifest.json`](../../../../../config/day1-branch-manifest.json)のOwner判断を8 branchのenvとdeploy manifestへ反映する。`NUM_DF_ACTIVE_BRANCHES = 2`とし、branch 0–1だけがUnderlying・実collateral/USD feed・CollateralYieldZapperをbindingする。branch 2–7はUnderlying未binding、placeholder PriceFeed、cap 0、Strategy / Zapperなしのinert構成とする。
- Liquidity / zap route は Day-1 USDC 中心でも、担保 branch 数とは別管理する。
- 本 runbook は private key / Safe nonce / raw `MAINNET_RPC_URL` / RPC provider API key を記録しない。証跡に残す RPC 情報は provider label と redacted URL までに限定する。
- `contracts/lib/**` や Liquity core fork surface は対象外。

---

## 2. Source Links

| 種別                                                | 一次ソース                                                                                                                        |
| --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Chainlink feed proxy                                | <https://docs.chain.link/data-feeds/price-feeds/addresses>（Ethereum Mainnet の標準 feed。SVR / shared-SVR は採用しない）         |
| Chainlink feed metadata                             | <https://reference-data-directory.vercel.app/feeds-mainnet.json>（heartbeat / deviation / marketHours / decimals / proxy の照合） |
| Aave V3 provider / Pool / aToken                    | <https://github.com/aave-dao/aave-address-book/blob/main/src/AaveV3Ethereum.sol> と <https://github.com/aave-dao/aave-v3-origin/blob/main/src/contracts/protocol/configuration/PoolAddressesProvider.sol> |
| wstETH / USDC token address cross-check             | Aave Address Book の `AaveV3EthereumAssets`                                                                                       |
| wstETH / stETH（Lido）                              | Lido 公式 deployed contracts（<https://docs.lido.fi/deployed-contracts/>）                                                        |

外部アドレスは deploy 前に上記ソースで再照合し、値の差異があれば broadcast しない。Chainlink は同名 feed に SVR / shared-SVR が存在するため、下表の `path` が素の標準 feed であることを確認する。
RPC で再現できる evidence として `contracts/utils/mainnet-preflight.ts` を使い、Chainlink
feed 実体 / token symbol-decimals / Aave reserve / 採用した ERC-4626 vault を同一 `FORK_BLOCK`
で機械確認する。

---

## 3. Frozen External Addresses

### 3.1 Chainlink feeds

| Env                  | Feed       | Chainlink `path` | Proxy                                        | Parameter |
| -------------------- | ---------- | ---------------- | -------------------------------------------- | --------- |
| `DF_JPY_USD_FEED`    | JPY / USD  | `jpy-usd`        | `0xBcE206caE7f0ec07b545EddE332A47C2F75bbeb3` | `PRM-ORACLE-001` |
| `DF_COLL_USD_FEED_0` | stETH / USD | `steth-usd` | `0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8` | `PRM-ORACLE-003` |
| `DF_COLL_USD_FEED_1` | USDC / USD | `usdc-usd`       | `0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6` | `PRM-ORACLE-004` |

active branch 0–1だけが`DF_COLL_USD_FEED_i` / `DF_COLL_USD_STALENESS_i`を必須とする。dwstETHはstETH/USD × wstETH canonical rate ÷ JPY/USDを使う。branch 2–7の実feedとthresholdは個別activation packageでのみ確定する。

#### 3.1.1 Staleness monitoring evidence

Broadcast / activation evidence には、各 feed について次の列を残す。

| Field                                    | Meaning                                                                   |
| ---------------------------------------- | ------------------------------------------------------------------------- |
| `proxy`, `description`, `decimals`       | 凍結した Chainlink feed と実体の照合                                      |
| `latestRoundData.updatedAt`              | stale 判定の基準時刻                                                      |
| `ageSeconds`                             | `block.timestamp - updatedAt`                                             |
| `stalenessThreshold`                     | deploy env に入れる閾値                                                   |
| `secondsToStale`                         | `stalenessThreshold - ageSeconds`。strict `<` 判定なので `0` 以下は stale |
| `answer` / `roundId` / `answeredInRound` | invalid response の切り分け                                               |

初期 alert band は次のとおり運用する。値は monitoring の最低ラインであり、より早い warning を追加してよい。

| Signal                           | Warning                                                                                                                                                          | Critical / incident                                                                                                                                                                                                                                      |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| branch-local collateral/USD feed | `secondsToStale <= min(21600, stalenessThreshold / 4)`                                                                                                           | stale 到達、invalid round、または branch `ShutDownFromOracleFailure`                                                                                                                                                                                     |
| JPY/USD feed | `age > 25h`でWATCH / Warning。30hまでに借入・引出・通常償還の停止を案内し、復旧手順を開始 | 30h到達、shared providerのfreeze / expiry、provider address不一致、invalid responseの継続 |
| JPY soft-freeze age | freeze開始後12hで復旧とsource proposalの進捗を確認 | stalenessのみならage 54hで清算用価格も失効。12h timelockを考慮し、age 42hより前にproposalを開始できなければ清算停止を前提に対応 |

`JpyUsdRateProvider.jpyFrozenSince` は初回障害観測と `lastGoodJpyUpdatedAt + 30h` の早い方で、event blockより古い場合がある。期限はこの起点から計算する。providerとunderlyingの `updatedAt` を監視し、全active sourceが単一providerを参照することを確認する。expiryを観測した後も新しい有効なJPY更新は回復に使えるが、別途立ったBOのoracle pauseはOwnerの検証付きresumeを要する。

production activation は、provider address 一致・`jpyFrozenSince`・`jpyFreezeExpired` を process 外から監視する external monitor、P0/P1 escalation target、明記した human recipient を用意し、label 付き test incident の作成→想定 policy / recipient への到達確認→resolve まで完了するまで block する。dashboard、structured log、sink の HTTP 2xx だけを delivery evidence としない。

**source差替のタイミング**: 30h thresholdを持つ健全な `JpyUsdRateProvider` を1つ配置し、全replacement sourceを同じaddressへ向ける。全branchのproposalを同じchange setで開始し、12h timelock後にgovernance batchで同一transaction内にconfirmする。emergencyもtimelockは省略しない。30hのWarning段階で準備を開始し、54hより前の切替には42hより前のproposalと実行余裕を確保する。無効値を早期検出した場合は期限も早まる。oracle pauseは回復可能だが、既に実行したTCR/SCRによる恒久shutdownは解除できない。

### 3.2 Underlying tokens

| Env               | Token       | Address                                      | Source                              |
| ----------------- | ----------- | -------------------------------------------- | ----------------------------------- |
| `DF_UNDERLYING_0` | wstETH      | `0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0` | Lido 公式 / freeze 時に primary source で再照合 |
| `DF_UNDERLYING_1` | USDC        | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | Aave Address Book / script default  |

`DF_UNDERLYING_0..1` は mainnet freeze log で明示投入する（script 既定値を持つのは `DF_UNDERLYING_1`（USDC）のみで、0 は必須 env）。`mainnet-preflight.ts` が各 token の symbol / decimals を本表と照合し、`DF_UNDERLYING_2..7` が設定されていないことを検査する。branch 2–7 は Underlying を binding せず、one-shot binding が未実行であることを evidence 化する（wiring shape は [Deployment-Configuration-Spec](../../../engineering/guides/Deployment-Configuration-Spec.md) §4）。

### 3.3 Strategy venues

|            Branch | Day-1 Strategy set | Env shape |
| ----------------: | ------------------ | --------- |
|  0 `dwstETH / wstETH` | Aave V3 wstETH のみ（Day-1 active・aave-only set） | `DF_STRATEGY_COUNT_0=1` + `DF_STRATEGY_KIND_0_0=aave`（aEthwstETH） |
|  1 `dUSDC / USDC` | Aave V3 + Morpho Vault V2（`erc4626` は追加許容） | `DF_STRATEGY_COUNT_1=2` + `DF_STRATEGY_KIND_1_0=aave` + `DF_STRATEGY_KIND_1_1=morpho-v2` |
|  2 `dETH / TBD` | no Strategy (inert) | Underlying未設定、weight/cap 0、manifest / Vault Strategy count 0 |
|  3 `dUSD-A / TBD` | no Strategy (inert) | same |
|  4 `dBTC / TBD` | no Strategy (inert) | same |
|  5 `dUSD-B / TBD` | no Strategy (inert) | same |
|  6 `dJPY / TBD` | no Strategy (inert) | same |
|  7 `dJGB / TBD` | no Strategy (inert) | same |

`mainnet-preflight.ts` は branch ごとの policy を強制する（branch 0 = `aave` 必須かつ他 kind 不可、branch 1 = `aave` + `morpho-v2` 必須で `erc4626` 追加可、branch 2–7 = `strategies[]` 空）。

Mainnet の `aave` は `DF_STRATEGY_AAVE_POOL_i_j` / `DF_STRATEGY_AAVE_ATOKEN_i_j`、
`morpho-v2` は `DF_STRATEGY_MORPHOV2_VAULT_i_j`（`DF_STRATEGY_MORPHOV2_MAX_PENALTY_BPS_i_j` は
既定 200・200 超は拒否）、`erc4626` は `DF_STRATEGY_ERC4626_VAULT_i_j` を必須にする。
現在の採用状態は
[`Strategy-Selection-Policy.md`](../../operations/policies/Strategy-Selection-Policy.md#採用分類) に従い、
新しい freeze package では `lido` / `etherfi` kind と `DF_STRATEGY_LIDO_*` を指定しない
（LidoStrategy / EtherfiWeETHStrategy は Day-1 deploy surface から退役済み）。
non-mainnet は local production-parity venue を使ってよい。`none` は deploy
し忘れの隠蔽ではなく、weight/cap 0 と Vault 登録 Strategy 数 0 を script が検証する。
Day-1 は branch 0（aave のみ）と branch 1（aave + morpho-v2 必須、erc4626 は追加許容）以外の
全 branch（2–7）を Strategy 未登録で freeze する。

Morpho Vault V2（`morpho-v2`）を採用する場合は withdraw / bad debt / curator / oracle / queue
evidence を freeze package で満たす。実採用 vault evidence は
[`Morpho-Day1-Vault-Freeze-Package.md`](./Morpho-Day1-Vault-Freeze-Package.md)
に従って `morpho-vault-freeze.json` と fork dry-run evidence を添付し、`BLOCKER=0` を確認する。

Aave venue evidence:

- Aave market 固有の `PoolAddressesProvider` address / `getMarketId()` を記録し、`getPool()` が `DF_STRATEGY_AAVE_POOL_i_j` と一致する。同一 chain 上の Core / Lido / EtherFi 等を混在させない。
- Pool address は Aave V3 Ethereum production Pool と一次ソースで一致する。
- 各 aToken の `UNDERLYING_ASSET_ADDRESS()` が branch の `DF_UNDERLYING_i` と一致する。
- Pool reserve data の aToken address が `DF_STRATEGY_AAVE_ATOKEN_i` と一致する。
- fork block 時点で reserve が pause / freeze / unexpected isolation state ではないことを確認する。
- provider / Pool / aToken / underlying の source、照合者、照合日時を evidence に記録する。

provider の `getPool()` が freeze 済み Pool と一致しない場合は値を自動更新せず broadcast / allocation を停止する。
同一 provider の implementation upgrade か、新 provider・新 Pool・新 aToken を伴う market migration かを区別し、後者は
[AAVE-GOV-001](../../product/spec/strategies/AaveV3Strategy.md#aave-gov-001-投資先差し替えは-strategy-再作成) に従って旧 Strategy の回収と新 Strategy の activation を分離する。

---

## 4. Required Operator Values

以下は外部 protocol address ではなく、DeltaForesight 側 holder / policy 値なので本 runbook では placeholder のままにする。broadcast 前に [`Mainnet-Safe-Role-Assignment-Gate`](./Mainnet-Safe-Role-Assignment-Gate.md) の address book / role matrix / threshold review で freeze し、fork dry-run evidence に添付する。

| Group                | Env                                                                                                                                                            |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| deploy / treasury    | `DEPLOYER`, `DF_BRIDGE_ADMIN`, `DF_TREASURY`, `DF_INTEREST_ROUTER_RECIPIENT`, `DF_INTEREST_ROUTER_OWNER`                                                       |
| PIL Phase-A deploy-ready / activation（任意） | `DF_PILA_OWNER`, `DF_PILA_GUARDIAN`, `DF_PILA_EPOCH_START`, `DF_PILA_EPOCH_DURATION`, `DF_PILA_MIN_DISTRIBUTE`, `DF_PILA_MERKL_DISTRIBUTION_CREATOR`, `DF_PILA_CAMPAIGN_CREATOR`, `DF_PILA_CAMPAIGN_THRESHOLD`, `DF_PILA_CAMPAIGN_CREATION_WINDOW`, `DF_PILA_UNIV4_POOL_ID`, `DF_PILA_WEIGHT_FEES`, `DF_PILA_WEIGHT_TOKEN0`, `DF_PILA_WEIGHT_TOKEN1`, `DF_PILA_SALT` |
| governance handover  | `DF_TIMELOCK`, `DF_GUARDIAN`, `DF_ALLOCATOR`, `DF_WRITEOFF`, `DF_PRICE_FEED_OWNER`, `DF_STRATEGY_OWNER`, `DF_STRATEGY_UPGRADER`                                |
| branch policy | `DF_DTOKEN_CAP_0..7`, `DF_ALLOCATE_MAX_MOVE_0..7`, `DF_WITHDRAW_DELAY_0..7`, `DF_BUFFER_TARGET_BPS_0..7`, `DF_BUFFER_FLOOR_0..7`, `DF_ALLOCATOR_COOLDOWN_0..7` |

### 4.1 Deployment reproducibility

Mainnet broadcast の freeze package には次を必須で記録する。値が未確定、または dry-run と
broadcast で変わった場合は No-Go とする。

| Field | Freeze 要件 |
| --- | --- |
| `SALT` | 明示文字列と `keccak256(bytes(SALT))`。未指定の `block.timestamp` fallback は production で禁止 |
| deployer / signer | public deployer address と Ledger / hardware wallet / KMS 等の signing method。private key は記録しない |
| toolchain | repository commit、submodule SHA、`FOUNDRY_PROFILE`、Foundry / Solidity version |
| deploy inputs | deploy artifact hash、`contracts/script/DeployLiquity2.s.sol` sha256、manifest sha256 |
| verification | `--verify` の採否、verifier、redacted verifier URL、verified-source 結果。API key は記録しない |
| gas / submission | `--slow`、gas price、gas estimate multiplier、stuck / replacement 方針 |
| predicted address | frozen salt と deployer から script が出力する JPYdf predicted address。broadcast receipt / manifest と照合 |

公開承認済みProtocol holder addressは[Protocol Role Holder Manifest](../manifests/Mainnet-Protocol-Role-Holder-Manifest.md)、DeltaForesightのlaunch-operation holderは[Contributor Holder Manifest](../../../contributors/deltaforesight/manifests/Mainnet-Launch-Operations-Holder-Manifest.md)、分離条件は[Role Holder Separation Policy](./Mainnet-Role-Holder-Separation-Policy.md)を正本とする。Day 1 env freezeは各holderが該当Manifestと一致し、Safe構成が[Safe Threshold Policy](./Mainnet-Role-Assignment-Safe-Threshold-Policy.md)、Allocatorの実行形態が[Allocator Signer Policy](./Mainnet-Role-Assignment-Allocator-Signer-Policy.md)と一致することを確認する。address選定だけではbroadcast条件を満たさない。

`DF_DTOKEN_CAP_i` と `DF_ALLOCATE_MAX_MOVE_i` は token unit で投入する。`Parameters.md` の JPY 表記をそのまま env に入れない。Day-1 は inert な branch 2–7を0でfreezeし、dwstETH（index 0）の `DF_ALLOCATE_MAX_MOVE_0` も0（Day-1値、[Parameters](../../../Parameters.md) §2-B）でfreezeする。

Day-1 borrowable branch（0 dwstETH / 1 dUSDC）の `DF_DTOKEN_CAP_i` は、同じ freeze block で production PriceFeed と同じ外部 oracle legs から、Vault backingRatio 適用前の `priceJpyPerUnderlyingWad` を読み、`DF_DTOKEN_CAP_i = floor(nominalCapJpyWad * 1e18 / priceJpyPerUnderlyingWad)` で計算する。dUSDC は 1 億円 / USDC-JPY、dwstETH は 3,500 万円 / wstETH-JPY（stETH/USD・canonical rate・JPY/USD legs、backingRatio 除外）を使う。`DF_ALLOCATE_MAX_MOVE_i` を同じ名目値から決める場合は `floor(nominalCapJpyWad * 10**underlyingDecimals / priceJpyPerUnderlyingWad)` とする。`PriceFeed.fetchPrice()` / `lastGoodPrice()` は backingRatio 適用後の dToken 価格になり得るため使わない。外部 market quote は sanity check に限り、env 値の一次ソースにしない。

Freeze package には `dtoken-cap-conversion.json` を添付する。最低限、以下を branch ごとに記録する。

- top-level: `schemaVersion=1`, `chainId=1`, `forkBlock`, `capturedAt`, `capturedAtUnix`, `validUntil`（24h以内のUnix timestamp）
- `branches[branchIndex]`: `branchIndex`, `dToken`, `underlying`, `underlyingDecimals`
- `nominalCapJpyWad`, `nominalAllocateMaxMoveJpyWad`, `priceJpyPerUnderlyingWad`, `priceSource`
- oracle address / feed description / decimals / roundId / answer / updatedAt / staleness result / `backingRatioExcluded=true`
- formula, `rounding="floor"`, `computedDTokenCap`, `computedAllocateMaxMove`
- secondary quote / sanity check result（任意）、`riskOwnerSignoff`, `deployReviewerSignoff`

大きな整数は精度を落とさないよう decimal string として記録する。`branches` は branch index 順に並べる。

env freeze から broadcast までに 24h を超える、PriceFeed が stale になる、または freeze block 価格から dwstETH 200 bps / dUSDC 50 bps を超えて乖離した場合は、`DF_DTOKEN_CAP_0/1` と該当する `DF_ALLOCATE_MAX_MOVE_i` を再計算し、古い `dtoken-cap-conversion.json` を superseded として残したうえで新しい evidence を添付する。

`DF_BRIDGE_ADMIN` は Safe / Timelock 等の contract address とし、deployer と同一にしない。
Day-1 は bridge minter 0 件・pending proposal なしを manifest と preflight evidence に残す。
Day-2 以降に bridge minter を提案する場合、この env freeze runbook ではなく [Bridge-Minter-Activation-Gate](../../operations/runbooks/Bridge-Minter-Activation-Gate.md) の cap / rate / remote supply accounting / incident evidence を先に完了する。
承認済み launch state に従って `DF_INTEREST_ROUTER_RECIPIENT` と PIL activation evidence を freeze する。`DF_PILA_*` は `PILAllocator` / `UniV4MerklInitiative` を deploy-ready として pre-deploy する場合、または承認済みの same-launch / post-launch activation package に含める場合だけ freeze する。いずれの場合も `DF_PILA_OWNER` / `DF_PILA_GUARDIAN` は deploy 済み contract（Safe / Timelock 等）でなければならない。`DeployPILAllocatorPhaseA` は mainnet で codeless owner / guardian と暗黙 salt を拒否する。`DF_PILA_CAMPAIGN_CREATOR` は Ops keeper / Safe のどちらも許容するが、campaign amount / poolId / weights への裁量は持たない。

---

## 5. Deploy Env Skeleton

```bash
export FORK_BLOCK=<MAINNET_BLOCK_NUMBER>

export DEPLOYMENT_MODE=complete
export SALT=<EXPLICIT_MAINNET_CREATE2_SALT>
export DF_ENABLE_MAINNET_DTOKEN_WIRING=true
export DF_BRIDGE_ADMIN=<SAFE_OR_TIMELOCK_CONTRACT>

export DF_JPY_USD_FEED=0xBcE206caE7f0ec07b545EddE332A47C2F75bbeb3
export DF_JPY_USD_STALENESS=<PRM-ORACLE-001>

export DF_UNDERLYING_0=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
export DF_UNDERLYING_1=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
# inert branch 2–7: DF_UNDERLYING_2..7 は設定しない（Underlying 未 binding）

# branch 0（dwstETH）: stETH/USD market leg。canonical rate は Underlying（wstETH）の
# stEthPerToken() を直読みするため専用 env はない
export DF_COLL_USD_FEED_0=0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8
export DF_COLL_USD_STALENESS_0=<PRM-ORACLE-003>
export DF_COLL_USD_FEED_1=0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6
export DF_COLL_USD_STALENESS_1=<PRM-ORACLE-004>
# inert branch 2–7 は PriceFeedPlaceholder のため DF_COLL_USD_FEED_2..7 /
# DF_COLL_USD_STALENESS_2..7 は設定しない

# branch 0 native-ETH zap route（CollateralYieldZapper が ETH→Lido stETH→wstETH を実行）
export DF_ZAPPER_EXPECTED_STETH_0=0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84

export DF_STRATEGY_COUNT_0=1
export DF_STRATEGY_KIND_0_0=aave
export DF_STRATEGY_AAVE_POOL_0_0=0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2
export DF_STRATEGY_AAVE_ATOKEN_0_0=0x0B925eD163218f6662a35e0f0371Ac234f9E9371
export DF_STRATEGY_WEIGHT_BPS_0_0=<WSTETH_AAVE_WEIGHT_BPS>
export DF_STRATEGY_CAP_0_0=<WSTETH_AAVE_CAP_18_DECIMALS>
export DF_STRATEGY_COUNT_1=2
export DF_STRATEGY_KIND_1_0=aave
export DF_STRATEGY_AAVE_POOL_1_0=0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2
export DF_STRATEGY_AAVE_ATOKEN_1_0=0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c
export DF_STRATEGY_WEIGHT_BPS_1_0=<USDC_AAVE_WEIGHT_BPS>
export DF_STRATEGY_CAP_1_0=<USDC_AAVE_CAP_6_DECIMALS>
export DF_STRATEGY_KIND_1_1=morpho-v2
export DF_STRATEGY_MORPHOV2_VAULT_1_1=<USDC_MORPHO_V2_VAULT>
export DF_STRATEGY_MORPHOV2_MAX_PENALTY_BPS_1_1=200
export DF_STRATEGY_WEIGHT_BPS_1_1=<USDC_MORPHOV2_WEIGHT_BPS>
export DF_STRATEGY_CAP_1_1=<USDC_MORPHOV2_CAP_6_DECIMALS>
export DF_STRATEGY_KIND_2=none
export DF_STRATEGY_WEIGHT_BPS_2=0
export DF_STRATEGY_CAP_2=0
export DF_STRATEGY_KIND_3=none
export DF_STRATEGY_WEIGHT_BPS_3=0
export DF_STRATEGY_CAP_3=0
export DF_STRATEGY_KIND_4=none
export DF_STRATEGY_WEIGHT_BPS_4=0
export DF_STRATEGY_CAP_4=0
export DF_STRATEGY_KIND_5=none
export DF_STRATEGY_WEIGHT_BPS_5=0
export DF_STRATEGY_CAP_5=0
export DF_STRATEGY_KIND_6=none
export DF_STRATEGY_WEIGHT_BPS_6=0
export DF_STRATEGY_CAP_6=0
export DF_STRATEGY_KIND_7=none
export DF_STRATEGY_WEIGHT_BPS_7=0
export DF_STRATEGY_CAP_7=0

# Optional: Phase-A PIL deploy-ready / activation stack. Include only if the
# PIL stack is pre-deployed as evidence or an exception activation is approved.
export DF_PILA_DEPLOYMENT_MANIFEST=deployment-manifest.json
export DF_PILA_OUTPUT_MANIFEST=pil-activation-manifest.json
export DF_PILA_SALT=<EXPLICIT_PIL_CREATE2_SALT>
export DF_PILA_OWNER=<TIMELOCK_OR_SAFE_CONTRACT>
export DF_PILA_GUARDIAN=<GUARDIAN_SAFE_CONTRACT>
export DF_PILA_EPOCH_START=<UNIX_TIMESTAMP_NOT_IN_FUTURE_AT_BROADCAST>
export DF_PILA_EPOCH_DURATION=604800
export DF_PILA_MIN_DISTRIBUTE=1000000000000000000000
export DF_PILA_MERKL_DISTRIBUTION_CREATOR=<MERKL_DISTRIBUTION_CREATOR>
export DF_PILA_CAMPAIGN_CREATOR=<OPS_KEEPER_OR_SAFE>
export DF_PILA_CAMPAIGN_THRESHOLD=168000000000000000001
export DF_PILA_CAMPAIGN_CREATION_WINDOW=86400
export DF_PILA_UNIV4_POOL_ID=<JPYDF_USDC_UNIV4_POOL_ID>
export DF_PILA_WEIGHT_FEES=1500
export DF_PILA_WEIGHT_TOKEN0=<POOL_TOKEN0_WEIGHT_BPS>
export DF_PILA_WEIGHT_TOKEN1=<POOL_TOKEN1_WEIGHT_BPS>
```

追加 Strategy の weight / cap placeholder は risk freeze 後に置換する。inert な branch 2–7 は Strategy count / weight / cap 0 を維持する。
mainnet では `type(uint256).max` を初期 cap として使わない。

### 5.1 PIL Phase-A deploy-ready / activation flow

[Mainnet Launch Product Decision Record](../decisions/Mainnet-Launch-Product-Decision-Record.md) §6 の標準 launch は、`DEPLOYMENT_MODE=complete` で `DF_INTEREST_ROUTER_RECIPIENT=<PIL専用Safe>` として開始する。

PIL stack を deploy-ready evidence として pre-deploy する場合は、`DeployLiquity2` に PIL deploy を混ぜず、JPYdf が存在する manifest を使って `DeployPILAllocatorPhaseA` を実行し、`pil-activation-manifest.json` を出力する。この manifest は deploy-ready evidence であり、`DF_INTEREST_ROUTER_RECIPIENT=<pilAllocator>` の承認ではない。

例外的に same-launch activation を承認する場合だけ、次の 3 段階で evidence を分ける。

1. `DEPLOYMENT_MODE=jpydf-only` で JPYdf と bridge dormant evidence を作る。
2. `forge script script/DeployPILAllocatorPhaseA.s.sol:DeployPILAllocatorPhaseA ...` で `PILAllocator` / `UniV4MerklInitiative` を deploy し、`pil-activation-manifest.json` を出力する。
3. `DEPLOYMENT_MODE=use-existing-jpydf` かつ `DF_INTEREST_ROUTER_RECIPIENT=<pilAllocator>` で本体を deploy する。

後追い活性化する場合は、PIL stack deploy / pre-deploy evidence を使い、Timelock/Safe で `InterestRouterForwarder.setRecipient(<pilAllocator>)` を提案・実行する。いずれの activation でも initiative 登録、`setWeights`、`route()`、`distribute()`、Merkl `createCampaign()` は Safe/Timelock/keeper の明示 action として evidence 化し、script が自動実行しない。

---

## 6. Fork Dry-Run Sequence

Stateful fork evidence は `contracts/utils/mainnet-fork-evidence.sh` を正面入口にする。
この helper は pinned anvil fork を起動し、deploy / manifest preflight /
handover prepare / pending verify を同一 fork state で実行する。`PrepareDFGovernanceHandover`
は state を変更するため、public RPC への broadcast なし dry-run と次の verify を別々に
実行しても pending state は残らない。必ず local fork に broadcast して検証する。

1. `MAINNET_RPC_URL` と `FORK_BLOCK` を固定し、fork block number を evidence に記録する。
2. `DEPLOYER` は fork evidence では public address を使う。helper は anvil
   `--auto-impersonate` と `anvil_setBalance` で local fork 上だけ funding する。production
   broadcast では `./deploy` の Foundry keystore / Ledger / hardware wallet / KMS signer を使う。
   deploy CLI と production-capable Forge scripts は private-key 形式の `DEPLOYER` を拒否し、
   child process の環境へ秘密鍵を渡さない。
3. 上記 env と operator values を読み込む。helper は未コミット tracked diff がある状態では停止する。例外的に dirty tree を使う場合は
   `DF_ALLOW_DIRTY_EVIDENCE=true` を明示し、その理由を evidence に残す。
4. deploy + manifest + handover pending evidence を同一 fork state で実行する。

```bash
pnpm -C contracts --silent mainnet-fork-evidence \
  --out /path/to/evidence-dir
```

helper output must include:

- `evidence-summary.txt` with repository commit, submodule status, Foundry version, fork block, deployer, and bridge admin.
- gas estimate multiplier. Default is `1000`, aligned with the local DF deploy wiring CI job unless `GAS_ESTIMATE_MULTIPLIER` is explicitly set.
- `01-external-preflight.log` proving active-branch Chainlink / token / Aave dependencies at the pinned fork block.
- `02-deploy-fork.log` proving deploy-tail verification passed on the local fork.
- `deployment-manifest.json` and `deployment-manifest.sha256`.
- If Phase-A PIL deploy-ready / activation evidence is included: `pil-activation-manifest.json`, its sha256, and a fork simulation proving `PILAllocator` / `UniV4MerklInitiative` constructor settings, Merkl `acceptConditions()`, poolId, weights, and owner/guardian role contracts. Evidence classification follows §5.1.
- `03-manifest-preflight.log` proving `launchEvidence`, `envFreeze`, active branch oracle staleness, `dfYield[].strategies[]` kind / weight / cap, branch 0 の aave-only set、branch 1 の aave + morpho-v2、branch 2–7 の Strategy 空・cap 0・Underlying 未 binding、bridge dormant gates.
- `morpho-vault-freeze.json` plus fork dry-run evidence from
  [`Morpho-Day1-Vault-Freeze-Package.md`](./Morpho-Day1-Vault-Freeze-Package.md), proving the adopted
  Morpho USDC vault, curator / owner / guardian, pending configs, queue indexes, oracle /
  IRM / LLTV, bad debt, and withdrawability.
- `04-app-env-generation.log` and generated `app.env`.
- `05-prepare-handover.log` and `06-verify-pending-handover.log`, unless `--skip-handover` was intentionally used and separately justified.

helper output に加え、freeze package には §4.1 の `FOUNDRY_PROFILE`、Solidity version、
artifact hash、deploy script sha256、salt / predicted JPYdf address、verification policy / result、
gas / replacement policy を記録する。`mainnet-fork-evidence` の summary だけでこれらを
記録済みと扱わない。

helper の required Strategy set、active branch 数、handover branch 数が §1 / §3.3 と
一致しない場合はhelperをcurrent Day-1 topologyへ更新して再実行する。旧topologyの結果をcurrent launch evidenceとして流用しない。現行値はbranch 0–1 active（`NUM_DF_ACTIVE_BRANCHES = 2`）、branch 0 = aave、branch 1 = aave + morpho-v2、branch 2–7 = inertである。

### 6.1 Post-broadcast app env annotation

Public frontend builds must not derive Vault event scan bounds from hand-written
notes. After mainnet broadcast and before generating production `app.env`, annotate
the broadcast manifest with each nonzero `dfYield[N].collateralVault` deploy block
using an archive-capable RPC:

```bash
pnpm -C contracts --silent annotate-vault-deploy-blocks \
  --manifest deployment-manifest.json \
  --out deployment-manifest.json

shasum -a 256 deployment-manifest.json > deployment-manifest.sha256
pnpm -C contracts --silent mainnet-preflight \
  --manifest deployment-manifest.json \
  --manifest-only
DF_DAY1_STRATEGY_SCOPE=strict pnpm -C contracts --silent exec tsx utils/deployment-manifest-to-app-env.ts \
  deployment-manifest.json \
  /path/to/app.env
```

`MAINNET_ARCHIVE_RPC_URL` は secret として扱い、evidence には provider label、
redacted URL、annotator output、更新後 manifest sha256 だけを残す。archive ではない
RPC が historical `eth_getCode` を返せない場合、annotator は停止する。その場合は
代替 archive RPC で再実行し、推測値や staging Anvil の block を mainnet app env に
転記しない。

`dfYield[N].collateralVaultDeployBlock` は app の `getLogs` 下限であり、contract
semantics ではなく consumer safety metadata である。値は deploy tx の receipt block
または archive RPC binary search の結果と一致しなければならない。active branch の
Vault deploy block が manifest にない状態では、`NEXT_PUBLIC_CHAIN_ID=1` の user app
hosting env check を通してはいけない。

---

## 7. Broadcast / Public Hosting Gate

mainnet broadcast 前、または broadcast 後の public frontend env freeze 前に、
該当する以下の gate をすべて満たすこと。

- active branch の Chainlink / Aave / token addresses を一次ソースで再照合済み。
- `mainnet-preflight` が同一 `FORK_BLOCK` で成功し、出力を evidence に添付済み。
- Chainlink feed evidence に `updatedAt` / `ageSeconds` / `secondsToStale` が含まれ、broadcast block 時点で全 feed が warning/critical band 外である。warning band 内なら broadcast せず、feed 更新・RPC 確認・risk owner 承認の再取得を行う。
- `deployment-manifest.json` の `launchEvidence` と `envFreeze` が `mainnet-preflight --manifest` で成功し、manifest sha256 と一緒に evidence 化済み。
- §5.1 の標準 launch state と一致している。PIL stack を pre-deploy する場合、`pil-activation-manifest.json`、manifest sha256、Merkl / Uniswap v4 poolId / owner / guardian / weight の fork evidence は deploy-ready evidence として添付済み。same-launch / post-launch activation を承認する場合は、同じ evidence に加えて `DF_INTEREST_ROUTER_RECIPIENT=<pilAllocator>` または `setRecipient(<pilAllocator>)` の Timelock/Safe bundle を別途添付する。
- broadcast 後の production app env 生成前に、archive RPC で
  `dfYield[N].collateralVaultDeployBlock` を注入し、更新後 manifest sha256 を evidence 化済み。
- Aave Pool / aToken / underlying / reserve data の整合性を fork block で evidence 化済み。
- branch 2–7 の Strategy count / weight / cap が0で、branch 0 = aave のみ、branch 1 = aave + morpho-v2 であることを product/security が承認済み。branch 0–1 の Underlying / feed / staleness が全て freeze 済みで `mainnet-preflight` を通過している。
- `DF_TREASURY`、InterestRouter recipient / owner、Timelock、Guardian、Allocator、Writeoff、PriceFeed owner、Strategy owner/upgrader の holder separation が freeze 済み。
- [`Mainnet-Safe-Role-Assignment-Gate`](./Mainnet-Safe-Role-Assignment-Gate.md) の address book、Safe threshold / signer hash、role matrix、env / manifest / consumer config diff が Go 判定済み。
- `DF_DTOKEN_CAP_i` と `DF_ALLOCATE_MAX_MOVE_i` が token unit で freeze 済み。inert な branch 2–7 は0、branch 0（dwstETH）は cap = 3,500 万円の token unit 換算値 / allocateMaxMove = 0。
- branch 0 の native-ETH zap route（`DF_ZAPPER_EXPECTED_STETH_0` = Lido stETH `0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84`）が Lido 公式一次ソースと一致済み。
- fork dry-run の deploy / handover / verify が同一 fork block で成功済み。
- §4.1 の salt / signer / toolchain / artifact / script / verifier / gas / predicted address と `deployment-manifest.json` sha256 が evidence に記録済み。
- checked-in address snapshot は使わず、current schema は `deployment-manifest.json` だけとする。
