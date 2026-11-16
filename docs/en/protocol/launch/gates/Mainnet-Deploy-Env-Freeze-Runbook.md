# Mainnet Deploy Env Freeze Runbook

> **Purpose**: freeze external dependencies and deployment environment values before a mainnet fork dry-run or broadcast through `DeployLiquity2.s.sol`. [Deployment Configuration](../../../engineering/guides/Deployment-Configuration-Spec.md) owns deploy-mode and manifest design, [`config/day1-branch-manifest.json`](../../../../../config/day1-branch-manifest.json) owns branch topology and production native-ETH route inputs, [Parameters](../../../Parameters.md) owns collateral and risk values, and [Mainnet Safe Role Assignment Gate](Mainnet-Safe-Role-Assignment-Gate.md) owns DF holder addresses and Safe/Timelock thresholds.
>
> **Staleness**: `PRM-ORACLE-*` in [Parameters](../../../Parameters.md) is canonical. Before broadcast, confirm every candidate against official metadata and current `latestRoundData.updatedAt`, then retain the fork block and risk-owner sign-off.

## 1. Scope

This runbook applies to Ethereum mainnet with `DEPLOYMENT_MODE=complete` and `DF_ENABLE_MAINNET_DTOKEN_WIRING=true`.

- Deploy all eight branches. `NUM_DF_ACTIVE_BRANCHES = 2`: only Branches 0–1 (`dwstETH` / `dUSDC`) bind an Underlying, a real collateral/USD feed, and a CollateralYieldZapper.
- Branches 2–7 launch inert: no Underlying binding, placeholder PriceFeed, cap 0, and no Strategy or Zapper.
- Liquidity and Zapper routes may be USDC-centered independently of branch count.
- Never record private keys, Safe nonces, raw `MAINNET_RPC_URL`, or provider API keys. Evidence may contain only a provider label and redacted URL.
- `contracts/lib/**` and unrelated Liquity core fork surfaces are outside this runbook.

## 2. Primary Sources

| Dependency | Primary source |
| --- | --- |
| Chainlink standard feed proxies | [Chainlink Data Feed addresses](https://docs.chain.link/data-feeds/price-feeds/addresses); do not substitute SVR/shared-SVR |
| Chainlink feed metadata | [Reference Data Directory](https://reference-data-directory.vercel.app/feeds-mainnet.json) |
| Aave V3 Pool and aTokens | [Aave addresses](https://aave.com/docs/resources/addresses) and [Aave address book](https://github.com/aave-dao/aave-address-book/blob/main/src/AaveV3Ethereum.sol) |
| USDC token address | `AaveV3EthereumAssets` in the Aave address book |
| wstETH / stETH (Lido) | [Lido deployed contracts](https://docs.lido.fi/deployed-contracts/) |

Recheck every external address before deployment and stop if a value differs. At the same `FORK_BLOCK`, run `contracts/utils/mainnet-preflight.ts` to verify feed identity, token symbol/decimals, the dUSDC Aave reserve identity, and any adopted ERC-4626 vault.

## 3. Frozen External Dependencies

### 3.1 Oracle feeds

| Env / source | Feed | Standard proxy | Parameter |
| --- | --- | --- | --- |
| `DF_JPY_USD_FEED` | JPY/USD | `0xBcE206caE7f0ec07b545EddE332A47C2F75bbeb3` | `PRM-ORACLE-001` |
| `DF_COLL_USD_FEED_0` | stETH/USD | `0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8` | `PRM-ORACLE-003` |
| `DF_COLL_USD_FEED_1` | USDC/USD | `0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6` | `PRM-ORACLE-004` |
| `DF_REDEMPTION_ETH_USD_FEED_0` | ETH/USD | `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419` | `PRM-ORACLE-002` |
| `DF_REDEMPTION_STETH_ETH_FEED_0` | stETH/ETH | `0x86392dC19c0b719886221c78AB11eb8Cf5c52812` | `PRM-ORACLE-007` |

Only the two active branches require `DF_COLL_USD_FEED_i` and `DF_COLL_USD_STALENESS_i`; the deploy script fails closed without them. The dwstETH source is stETH/USD × the canonical wstETH rate ÷ JPY/USD, and only Branch 0's redemption reference additionally requires the ETH/USD and stETH/ETH feeds above. Branches 2–7 receive real feeds and thresholds only through separately approved activation packages.

#### 3.1.1 Launch staleness evidence

For each feed, evidence must record:

- `proxy`, `description`, and `decimals`;
- `latestRoundData.updatedAt`, `ageSeconds`, threshold, and `secondsToStale`;
- `answer`, `roundId`, and `answeredInRound`;
- source URL, fork block, capture time, reviewer, and risk-owner sign-off.

At the freeze block, mechanically verify `roundId > 0`, `answer > 0`, `updatedAt > 0`, `updatedAt <= block.timestamp`, `answeredInRound >= roundId`, and `ageSeconds < stalenessThreshold` for every feed, including Branch 0's redemption-only ETH/USD and stETH/ETH feeds.

The strict stale condition is `age < threshold`; zero `secondsToStale` is already stale.

| Signal | Warning | Critical / incident |
| --- | --- | --- |
| branch-local collateral/USD | `secondsToStale <= min(21600, threshold / 4)` | stale/invalid round or `ShutDownFromOracleFailure` |
| JPY/USD | watch/warning after age 25h; prepare for the 30h borrowing/withdrawal/normal-redemption cutoff | shared provider `JpyRateFrozen`, `jpyFrozenSince > 0`, `JpyFreezeExpired`, provider-address mismatch, or persistent invalid/stale data |
| JPY soft-freeze | 12h after freeze: prepare confirmation and check recovery | staleness-only grace expires at age 54h; with the 12h source timelock, propose before age 42h with execution margin or prepare for liquidation suspension |

`JpyUsdRateProvider.jpyFrozenSince` is the earlier of first failure observation and the shared cached report's `updatedAt + threshold`. Monitoring must poll the provider and underlying `updatedAt`, and must verify that every active source's `jpyUsdRateProvider()` equals the single manifest address. A JPY/USD replacement deploys one new provider with a 30h threshold and all replacement sources against it; propose every source together and confirm them in one governance batch after the 12-hour timelock. Emergency confirmation bypasses the old-source read and the price-difference guard, while retaining new-source validation. A provider-address mismatch is a deployment blocker/P0, not an accepted rolling state. Earlier invalid responses can shorten grace. Fresh valid prices can restore liquidation after expiry; a latched BO oracle pause still requires validated Owner resume. Permanent TCR/SCR shutdown cannot be reversed.

Production activation is blocked until an external monitor watches provider-address equality, `jpyFrozenSince`, and `jpyFreezeExpired`; routes P0/P1 to the recorded escalation target; and a labeled test incident proves delivery to the intended human recipient and is then resolved. A dashboard, structured log, or successful sink response alone is not delivery evidence.

#### 3.1.2 Initial-source dependency evidence

The constructor has no 12-hour review window. Before broadcast, complete the following for all eight initial `PriceFeedProxy` / source pairs, including placeholders, at the same candidate commit, env, and `FORK_BLOCK`:

1. Pin the target Proxy address produced by the fork dry-run and its artifact runtime codehash, plus the initial source address and runtime codehash. For every upgradeable node, trace implementation address/codehash, immutable bindings, every forwarding/delegation edge, mutable routing state, and the administrators/owners able to change those edges.
2. An independent reviewer confirms that the dependency graph has no path from the initial source back to the target PriceFeedProxy and no unreviewed mutable edge. The `source()` marker and constructor smoke calls prove only a one-level type classification and current price health; neither proves acyclicity.
3. Do not broadcast if any codehash, implementation, edge, routing value, administrator, or predicted address drifts from the dry-run, or if the graph cannot be closed. After deployment, re-read Proxy `source`, both codehashes, and routing state and match them to the freeze evidence.

For later source replacement, follow [Oracle ORCL-GOV-004](../../product/spec/Oracle.md#orcl-gov-004) and the proposal/confirmation procedure in the [Admin Console Operator Manual](../../operations/runbooks/Admin-Console-Operator-Manual.md).

### 3.2 Underlying tokens

| Branch | Token | Address | Source |
| ---: | --- | --- | --- |
| 0 | wstETH | `0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0` | Lido official; recheck against the primary source at freeze time |
| 1 | USDC | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | Aave Address Book / script default |

Set both explicitly in the freeze log after primary-source confirmation; `DF_UNDERLYING_0` is a required env with no script default, while `DF_UNDERLYING_1` has a USDC script default that must still be pinned explicitly. `mainnet-preflight.ts` asserts each token's symbol and decimals against this table and rejects any populated `DF_UNDERLYING_2..7`. Branches 2–7 must omit Underlying values and prove that one-shot binding has not executed (the wiring shape is [Deployment Configuration](../../../engineering/guides/Deployment-Configuration-Spec.md) §4).

### 3.3 Strategy venues

| Branch | Day-1 Strategy set | Required freeze state |
| ---: | --- | --- |
| 0 `dwstETH / wstETH` | none (active branch) | `DF_STRATEGY_KIND_0=none`, weight/cap 0, and no `DF_STRATEGY_COUNT_0` |
| 1 `dUSDC / USDC` | Aave V3 + Morpho Vault V2 | `DF_STRATEGY_COUNT_1=2` + `DF_STRATEGY_KIND_1_0=aave` + `DF_STRATEGY_KIND_1_1=morpho-v2` |
| 2 `dETH / TBD` | none | inert; Strategy count, weight, and cap all 0 |
| 3 `dUSD-A / TBD` | none | inert |
| 4 `dBTC / TBD` | none | inert |
| 5 `dUSD-B / TBD` | none | inert |
| 6 `dJPY / TBD` | none | inert |
| 7 `dJGB / TBD` | none | inert |

`mainnet-preflight.ts` enforces this per-branch policy: branch 0 and branches 2–7 must have empty `strategies[]`; branch 1 contains exactly `aave` + `morpho-v2`.

The adopted set follows [Strategy Selection Policy](../../operations/policies/Strategy-Selection-Policy.md). Generic `erc4626` is not allowed in production Day-1; adopting it later requires a separate activation package and policy update. A new freeze package must not configure a `lido` or `etherfi` kind or any `DF_STRATEGY_LIDO_*` value (LidoStrategy / EtherfiWeETHStrategy are retired from the Day-1 deploy surface). The branch 1 Aave slot requires Pool/aToken identity evidence, matching Underlying, unpaused/unfrozen reserve state, and reviewer/date fields. Branch 0 has no Aave reserve or aToken evidence target. The Morpho Vault V2 slot requires `DF_STRATEGY_MORPHOV2_VAULT_1_1` (`DF_STRATEGY_MORPHOV2_MAX_PENALTY_BPS_1_1` defaults to 200; values above 200 are rejected) and the withdrawal, bad-debt, curator, oracle, and queue evidence in [Morpho Vault Freeze Package](Morpho-Day1-Vault-Freeze-Package.md), with `BLOCKER=0`.

### 3.4 Lido referral attribution

| Env                          | Day-1 frozen value                                   | Purpose                                                                                     |
| ---------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `DF_ZAPPER_EXPECTED_STETH_0` | `nativeEthRoute.expectedStEth` in the owner manifest | Canonical stETH connected to Branch 0's native-ETH route                                    |
| `DF_ZAPPER_LIDO_REFERRAL_0`  | `0x57af3a60314cD24032a4435b715f4dC8eb5967F0`         | Protocol-designated referral address passed to Lido `submit` by Branch 0's native-ETH route |
| `DF_ZAPPER_EXPECTED_LIDO_REFERRAL_0` | unset for the initial check; approved current value after a Timelock update | Pins the preflight current-state readback without rewriting the deployment manifest |

The source of truth for the initial deployment values is Branch 0's `nativeEthRoute` in `config/day1-branch-manifest.json`. On production mainnet, the deploy CLI and Forge script reject missing, zero, or mismatched env before sending a transaction. The generated `deployment-manifest.json` records `stEthToken` and the initial `lidoReferral`; the initial `mainnet-preflight` compares those values with the getter readbacks. `stEthToken` is constructor-fixed: on mismatch, redeploy with the correct inputs and regenerate the manifest and frontend bindings rather than attempting to mutate the existing Zapper. `lidoReferral` can be updated after deployment only through `setLidoReferral` on `DF_TIMELOCK` (the immutable `lidoReferralManager`). After an update, preserve the original deployment manifest, set `DF_ZAPPER_EXPECTED_LIDO_REFERRAL_0` to the approved current value, and record the `LidoReferralUpdated` event, getter readback, and preflight result as separate current-state evidence.

## 4. DF-Owned Inputs

Freeze these through the role/address package before broadcast:

| Group | Env |
| --- | --- |
| deployment / treasury | `DEPLOYER`, `DF_BRIDGE_ADMIN`, `DF_TREASURY`, `DF_INTEREST_ROUTER_RECIPIENT`, `DF_INTEREST_ROUTER_OWNER` |
| optional PIL Phase-A | `DF_PILA_OWNER`, `DF_PILA_GUARDIAN`, epoch/campaign/pool/weight fields, and explicit salt |
| governance | `DF_TIMELOCK`, `DF_GUARDIAN`, `DF_ALLOCATOR`, `DF_WRITEOFF`, `DF_PRICE_FEED_OWNER`, `DF_STRATEGY_OWNER`, `DF_STRATEGY_UPGRADER` |
| branch policy | `DF_DTOKEN_CAP_0..7`, `DF_ALLOCATE_MAX_MOVE_0..7`, `DF_WITHDRAW_DELAY_0..7`, buffer target/floor, and allocator cooldown |

The broadcast freeze package also records:

| Field | Requirement |
| --- | --- |
| `SALT` | explicit string and `keccak256(bytes(SALT))`; production cannot use a timestamp fallback |
| signer | public deployer and hardware-wallet/KMS method; never the private key |
| toolchain | repository commit, submodule SHA, Foundry profile/version, Solidity version |
| inputs | deploy-artifact, script, and manifest hashes |
| verification | verify flag/provider/redacted URL and final source-verification result |
| submission | slow mode, gas policy, multiplier, and stuck/replacement policy |
| predicted address | JPYdf address derived from frozen salt/deployer and matched to receipt/manifest |

`DEPLOYER` is always the public broadcaster address. The deploy CLI and production-capable Forge scripts reject private-key-shaped values and never forward a private key through the child-process environment. Use the CLI's Foundry keystore, Ledger, Trezor, or AWS KMS signer mode for production; `--unlocked` is reserved for a controlled local/fork RPC.

Holder separation must match the holder design, Safe-threshold policy, and allocator-signer policy referenced by [Mainnet Safe Role Assignment Gate](Mainnet-Safe-Role-Assignment-Gate.md). Address selection alone is not approval.

Enter cap and `allocateMaxMove` values in token units. Freeze inert Branches 2–7 at zero. Branch 0 (dwstETH) has a positive dToken cap but `allocateMaxMove=0` (Day-1 value, [Parameters](../../../Parameters.md)).

For borrowable branches 0 and 1:

```text
DF_DTOKEN_CAP_i = floor(nominalCapJpyWad * 1e18 / priceJpyPerUnderlyingWad)
DF_ALLOCATE_MAX_MOVE_i =
  floor(nominalCapJpyWad * 10**underlyingDecimals / priceJpyPerUnderlyingWad)
```

Use JPY 100M for dUSDC and JPY 35M for dwstETH (stETH/USD, canonical rate, and JPY/USD legs; backing ratio excluded). Derive price from the production oracle legs at the freeze block before Vault backing-ratio adjustment. Do not use `PriceFeed.fetchPrice()` or `lastGoodPrice()` for this conversion. Attach `dtoken-cap-conversion.json` containing `forkBlock`, `capturedAt`, `capturedAtUnix`, a Unix `validUntil` no more than 24 hours later, all inputs, oracle rounds, formula, rounding, outputs, and sign-offs.

Use top-level `schemaVersion=1` and `chainId=1`. Order `branches` by `branchIndex`; each entry records `dToken`, `underlying`, `underlyingDecimals`, `nominalCapJpyWad`, `nominalAllocateMaxMoveJpyWad`, `priceJpyPerUnderlyingWad`, `priceSource`, `backingRatioExcluded=true`, `rounding="floor"`, `computedDTokenCap`, `computedAllocateMaxMove`, `riskOwnerSignoff`, and `deployReviewerSignoff`. Encode large integers as decimal strings.

Recompute after 24 hours, after any stale state, or when price moves more than 50 bps for dUSDC or 200 bps for dwstETH. Retain the prior evidence as superseded.

`DF_BRIDGE_ADMIN` must be a Safe/Timelock-style contract distinct from the deployer. Day-1 proves zero bridge minters and no pending proposal. Future minter registration follows [Bridge Minter Activation Gate](../../operations/runbooks/Bridge-Minter-Activation-Gate.md).

Phase-A PIL is disabled by default. Set the InterestRouter recipient to the PIL holding Safe/address. Freeze `DF_PILA_*` only for an approved pre-deploy or activation package; owner/guardian must be deployed contracts, and the campaign creator has no discretion over amount, pool, or weights.

## 5. Environment Skeleton

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
# Inert Branches 2–7: leave DF_UNDERLYING_2..7 unset (no Underlying binding).

# Branch 0 (dwstETH): stETH/USD market leg. The canonical rate is read from the
# Underlying itself (wstETH.stEthPerToken()), so it has no env value.
export DF_COLL_USD_FEED_0=0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8
export DF_COLL_USD_STALENESS_0=<PRM-ORACLE-003>
export DF_REDEMPTION_ETH_USD_FEED_0=0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
export DF_REDEMPTION_ETH_USD_STALENESS_0=<PRM-ORACLE-002>
export DF_REDEMPTION_STETH_ETH_FEED_0=0x86392dC19c0b719886221c78AB11eb8Cf5c52812
export DF_REDEMPTION_STETH_ETH_STALENESS_0=<PRM-ORACLE-007>
export DF_COLL_USD_FEED_1=0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6
export DF_COLL_USD_STALENESS_1=<PRM-ORACLE-004>
# Inert Branches 2–7 start on PriceFeedPlaceholder: leave DF_COLL_USD_FEED_2..7 /
# DF_COLL_USD_STALENESS_2..7 unset.

# Branch 0 native-ETH zap route. Read the values from the owner manifest instead of copying them.
export DF_ZAPPER_EXPECTED_STETH_0="$(jq -er '.branches[] | select(.index == 0) | .nativeEthRoute.expectedStEth' config/day1-branch-manifest.json)"
export DF_ZAPPER_LIDO_REFERRAL_0="$(jq -er '.branches[] | select(.index == 0) | .nativeEthRoute.lidoReferral' config/day1-branch-manifest.json)"

# Branch 0: do not deploy, register, or allocate an external Day-1 Strategy.
export DF_STRATEGY_KIND_0=none
export DF_STRATEGY_WEIGHT_BPS_0=0
export DF_STRATEGY_CAP_0=0
# Leave DF_STRATEGY_COUNT_0 and kind-specific env unset.

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

# Inert Branches 2–7: leave Strategy env unset. Manifest and Vault readback
# must show Strategy count, total weight, and cap all zero.
```

Never use `type(uint256).max` as a production initial cap.

## 6. Required Evidence and No-Go

Before broadcast, attach:

- source/address and oracle-metadata checks at one fork block;
- `mainnet-preflight` result with zero blockers;
- deployment/reproducibility fields and artifact hashes;
- role/holder/threshold evidence;
- eight-branch manifest showing Day-1 active Branches 0–1 and inert Branches 2–7;
- the exact `dtoken-cap-conversion.json` read through `DF_DTOKEN_CAP_CONVERSION`, with
  `classification=APPROVED_FOR_MAINNET_BROADCAST`, plus
  `dtoken-cap-conversion.sha256`, for dwstETH/dUSDC. A test-only package must say
  `TEST_ONLY_NOT_APPROVED_FOR_MAINNET_BROADCAST` and cannot substitute for production sign-off. The
  test-only path also requires the exact override token and sentinel code installed by the local
  Anvil helper, so the same artifact is rejected against the real mainnet state;
- fork logs proving both active dToken caps are 0 after deploy, Branch 1 recovery runs only inside an Anvil snapshot at the approved `DF_DTOKEN_CAP_1` with a bounded temporary 50/50 Aave/Morpho fixture, and the snapshot restores both caps plus the persistent strategy weights/caps before handover preparation becomes the only persistent cap activation. This lets a conditionally-approved venue remain at persistent weight/cap 0;
- an empty Strategy-set readback for Branch 0 and venue evidence for the Branch 1 Aave + Morpho Vault V2 set;
- native-ETH zap route evidence: `DF_ZAPPER_EXPECTED_STETH_0` = Lido stETH `0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84`, matched to the Lido primary source, and `mainnet-preflight` readback proving Zapper `lidoReferral()` = `DF_ZAPPER_LIDO_REFERRAL_0` = `0x57af3a60314cD24032a4435b715f4dC8eb5967F0`;
- fork dry-run receipt, post-deploy reads, and generated frontend/app bindings.

Generate the cap-conversion package with `pnpm --dir contracts dtoken-cap-conversion-evidence -- --rpc-url "$MAINNET_RPC_URL" --block "$FORK_BLOCK" --manifest contracts/deployment-manifest.json --classification APPROVED_FOR_MAINNET_BROADCAST --risk-owner-signoff '<APPROVAL_REFERENCE>' --deploy-reviewer-signoff '<REVIEW_REFERENCE>' --output /path/to/dtoken-cap-conversion.json`. The generator validates the pinned block, canonical assets, manifest feed topology and staleness, Chainlink rounds, and `stEthPerToken()` before bigint floor conversion; it refuses to overwrite an existing output. Use the test-only classification without sign-off options before approvals.

Do not broadcast when any active address or feed differs from primary sources; Zapper `lidoReferral()` differs from `DF_ZAPPER_LIDO_REFERRAL_0`; a feed is stale/invalid; salt, signer, toolchain, hashes, or verification settings are unfrozen; a holder violates separation; any Branch 2–7 Underlying is bound or has nonzero capacity / real feed / Strategy / Zapper; Branch 0 has any registered Strategy; the Branch 1 Strategy set differs from aave + morpho-v2; bridge readiness is not dormant; or dry-run, manifest, and bindings disagree.

## 7. References

- [Parameters](../../../Parameters.md)
- [Oracle](../../product/spec/Oracle.md)
- [Deployment Configuration](../../../engineering/guides/Deployment-Configuration-Spec.md)
- [Strategy Selection Policy](../../operations/policies/Strategy-Selection-Policy.md)
- [Mainnet Safe Role Assignment Gate](Mainnet-Safe-Role-Assignment-Gate.md)
- [Mainnet Fork Stress Gate](Mainnet-Fork-Stress-Gate.md)
- [Bridge Minter Activation Gate](../../operations/runbooks/Bridge-Minter-Activation-Gate.md)
