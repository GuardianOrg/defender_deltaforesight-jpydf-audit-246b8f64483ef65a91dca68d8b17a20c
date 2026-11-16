# JPY DeFi Multichain Expansion / JPYdf Bridge Research

> **Status**: Research memo / not an active requirement.
>
> This document is a comparative research memo for considering JPYdf's future multichain expansion. The source of truth for the current jpydf-v2 remains
> [Product-Overview](../../../product/Product-Overview.md) and each component spec. A Day-1 active bridge adapter,
> issuance on other chains, and full-protocol expansion to other chains are not in active scope. On the other hand, to avoid making bridging impossible after token freeze,
> the dormant bridge-readiness of `JpydfToken` (`bridgeAdmin` / bridge minter registry / `bridgeMint` / self-burn
> `bridgeBurn`) has already been adopted as a Core token requirement. Prior proposals remain in [Multichain](../../../../archive/Multichain.md) as historical material.
> For Day-2 and later, bridge minter registration / route open / cap ramp gate, the source of truth is
> [Bridge-Minter-Activation-Gate](../../../operations/runbooks/Bridge-Minter-Activation-Gate.md), and this document is treated only as background material for protocol comparison.

## 1. Current JPY DeFi / JPYdf Starting Point

In the current design, at Day-1 launch the effective increase/decrease paths of `JpydfToken.totalSupply` are closed within Liquity v2 Core. Increases are limited to borrow / interest / fee mint originating from BorrowerOperations /
ActivePool, and decreases to Core paths such as repay / redemption / liquidation offset. Although the
token has `bridgeMint` / self-burn `bridgeBurn` as dormant bridge-readiness, Day-1 starts with 0 bridge minters and no pending proposal, so no active bridge supply path exists.

Therefore, the current answer to the question "can it be moved like Across or Stargate?" is as follows.

- **Not possible in the Day-1 launch state**: there are 0 bridge minters, and no bridge / router / OFT adapter is yet registered. There is also no path to issue canonical JPYdf on other chains.
- **UX and issuance design should be separated**: a fast UX layer like Across only works once a valid JPYdf representation and liquidity exist on the destination side.
- **The first thing to decide is JPYdf itself only**: a design that moves dToken, Trove debt, collateral, and Stability Pool deposits across chains has too large a blast radius on the liquidation, oracle, and accounting fronts.

## 2. Issues of Day1 Bridge-Readiness

The main focus of this research is not to operate a bridge at Day1, but **to avoid a situation where the Day1 token shape makes it impossible to build a canonical bridge later**.

### 2.1 The Option to Close at Day1

If at Day1 the non-upgradeable `JpydfToken` is wired with only Core mint/burn and fixed in a form where token-level extensions cannot be added after owner renounce, the following options become hard to take later.

- **token-native burn/mint**: a canonical route that burns JPYdf on the source and mints JPYdf on the destination requires bridge authority on both the source token and the destination token.
- **Stargate / LayerZero MABA type**: for an adapter to call the base token's `mint()` / `burn()`, the base token must be able to grant authority to an external adapter.
- **CCIP CCT burn/mint type**: a design that hands burn/mint authority to a token pool cannot be established without the token-side authority design.

That said, even without putting a bridge extension into Day1, **a bridge does not become entirely impossible**. A path that deposits the existing token into a lockbox / OFT Adapter and mints/burns a representation on the destination side can be added later. In that case, the destination token is strictly an "Ethereum locked JPYdf backed representation," requiring a different explanation and monitoring from a token-native JPYdf supply.

### 2.2 Day1 Options

| Day1 choice | What can be done later | Day1 load | Main trade-off |
| --- | --- | --- | --- |
| No bridge extension | Lockbox / OFT Adapter type, or token migration | Minimum | The Core-only invariant is simplest. However, a native burn/mint route is hard to build later |
| Dormant bridge extension | Enabling bridge minter / MABA / CCIP CCT burn-mint / OFT burn-mint | Medium | At Day1 it can stay dormant with no minter registered, but because it includes strong future authority, the token audit scope grows |
| Upgradeable token | Add any bridge logic later | Large | Flexible, but a poor fit with the current non-upgradeable / Core-invariant policy |
| Pre-committed adapter route | Keep the Day1 token immutable and activate a canonical adapter later | Medium | The design must be fixed as a lockbox representation rather than token-native |

### 2.3 Minimum Conditions When Choosing the Dormant Extension

If bridge-readiness is included at Day1, treating it as a **dormant extension with unregistered minters**, rather than an operating bridge, is the minimum blast radius.

- Make `bridgeAdmin` a role separate from owner, not dependent on the owner renounce after Core wiring.
- Keep bridge minters at 0 at the Day1 launch point.
- Limit `bridgeAdmin` / bridge minters to contract addresses only, and forbid one entity holding both admin and minter.
- Make bridge minter addition timelocked and removal immediate.
- Do not import bridge-specific code into the token. CCIP / LayerZero / Stargate connect on the minter / adapter side.
- Do not give the token a token-level cap; make a bridge pool / adapter-side cap mandatory. On the premise that a token-level cap cannot be added later, do not register an adapter that lacks cap / rate / pause.
- The Day1 tests must explicitly state that "if no minter is registered, mint/burn outside Core is impossible."
- Before `proposeBridgeMinter`, satisfy [Bridge-Minter-Activation-Gate](../../../operations/runbooks/Bridge-Minter-Activation-Gate.md) Stage A and the `CORE-BT-*` verification ledger. operator-only canary / public route open / cap ramp follow Stage B / C of the same runbook. Do not reuse the old `MCHN-*` IDs.

In this case, the current `SYS-INV-003` / `ADR-004` change from "no bridge" to "a bridge extension exists but is dormant," so the active requirements in [Product Overview](../../../product/Product-Overview.md), [Architecture Decision Records](../../../product/architecture/Architecture-Decision-Records.md), and the verification ledgers need updating. Treat this not as a mere implementation detail, but as a change to the Day1 audit scope.

### 2.4 Adoption Decision

Prioritizing the goal "in the future, move JPYdf naturally like Across / Stargate," we do not choose the option of putting nothing in at Day1. At Day-1 we do not operate a bridge, and put only a protocol-agnostic dormant bridge extension into the token.

This increases the Day-1 audit scope, but by fixing the launch gate at `bridgeMinterCount == 0` / `proposedBridgeMinter == address(0)`, the effective supply path remains Core only.

The question to decide again before Day2 activation is **whether to treat the destination JPYdf as canonical burn/mint supply, or as an Ethereum locked JPYdf backed representation**. The current first candidate is the former, but the adapter / chain / cap / monitoring are finalized in a separate spec.

## 3. Recommended Bridge Approach (Assuming Arc / Hype / Base / Solana)

### 3.1 Outline of the Recommendation

The recommendation is to **put a dormant bridge-agnostic extension into `JpydfToken` at Day1, and for the JPYdf-itself bridge from Day2 onward, verify Wormhole NTT as the first candidate**. The former is already adopted; the latter is an unimplemented activation study.

At the same time, because Arc / HyperEVM / Base / Solana all have strong Circle CCTP / Gateway USDC support, we use a **USDC rail** as an auxiliary path separate from the JPYdf-itself bridge.

- **JPYdf canonical rail**: Wormhole NTT as the first candidate. Prioritize Base / HyperEVM / Solana, and add Arc only after custom token bridge support such as NTT / OFT / CCIP CCT becomes clear.
- **USDC rail**: Circle CCTP / Gateway / App Kit. Use it for USDC movement among Arc / HyperEVM / Base / Solana, liquidity funding, and destination-side swap / onboarding. However, the USDC rail is not a substitute for JPYdf supply authority.
- **UX rail**: aggregators such as Across / Stargate / App Kit are used after the canonical JPYdf route and destination liquidity are settled.

Reasons:

- Base / HyperEVM / Solana are included in Wormhole NTT's supported networks, and NTT has both hub-and-spoke and burn-and-mint, rate limit, and Global Accountant.
- Because Solana is non-EVM, an SVM-capable token transfer framework, rather than an EVM-only bridge, is required.
- HyperEVM has an NTT Hyperliquid deployment guide, but because there is an experimental warning, the initial cap needs to be small.
- Arc has strong CCTP / Gateway / App Kit USDC experience in the Circle docs, but a standard route to natively bridge a custom token like JPYdf needs to be confirmed separately.

### 3.2 Per-Chain Recommendations

| Chain | Recommended initial handling | JPYdf-itself bridge | USDC rail / UX | Main caveats |
| --- | --- | --- | --- | --- |
| Base | First pilot | Wormhole NTT or LayerZero OFT. Easiest to implement since it is EVM | CCTP / Gateway / App Kit supported. USDC liquidity is also easy to create | Make the Optimistic L2 finality / withdrawal assumptions and the bridge cap into a runbook |
| HyperEVM / Hype | Second pilot | Wormhole NTT is the first candidate since it has a Hyperliquid guide | CCTP / Gateway supported. Expansion to HyperCore is a separate design | The HyperCore spot token / HyperEVM link has many irreversible steps. Start with a small cap, assuming the experimental warning |
| Solana | Third pilot | Wormhole NTT or LayerZero Solana OFT. Design SPL mint / decimal / ATA / rent | CCTP / Gateway / App Kit supported | Make explicit the difference between ERC20 18 decimals and SPL decimals, dust, u64 supply cap, and program upgrade authority |
| Arc | Strategic target, not first canonical JPYdf bridge | Wait until custom token bridge support is clear. The Day1 extension allows adding a minter / adapter later | Prioritize the CCTP / Gateway / App Kit USDC rail | Arc has strong USDC gas / Circle stack. Do not confuse the JPYdf bridge with the USDC bridge |

### 3.3 Recommended Token-Side Interface

Even when putting a dormant extension in at Day1, avoid handing a bridge minter the same arbitrary burn authority as the existing `burn(address,uint256)`. The recommendation is to separate Core mint/burn from bridge mint/burn.

- Core path: keep the existing `mint(address,uint256)` / `burn(address,uint256)` limited to BO / AP / CR / BO / TM / SP.
- Bridge path: add `bridgeMint(to, amount)` and `bridgeBurn(amount)`, which burns only the adapter's / manager's own holdings, or an equivalent self-burn-type interface.
- The `to` of `bridgeMint(to, amount)` passes the same protocol recipient blacklist as a normal transfer, so it does not mistakenly mint directly into a core protocol contract.
- The bridge adapter / NTT manager receives JPYdf from users via transfer / allowance, burns its own balance, and sends a message. Do not design it so it can directly burn arbitrary user balances.
- `bridgeAdmin` only registers/removes bridge adapters / managers, and does not import protocol-specific code into the token. Do not make `bridgeAdmin` itself a minter.
- Make a per-route cap / rate limit the first candidate on the bridge side. Do not give the current token extension a per-minter hard cap; handle it with the activation PR's adapter / pool cap and monitoring.

In this form, Day1 keeps Core-only behavior with 0 bridge minters, while at Day2 a Wormhole NTT manager, LayerZero OFT Adapter, CCIP token pool, and so on can be plugged in as bridge minters.

### 3.4 Why Wormhole NTT Is the First Candidate

Wormhole NTT is a good fit for JPYdf's initial bridge requirements.

- It can select both hub-and-spoke and burn-and-mint.
- It can handle both ERC-20 and SPL tokens.
- Base / HyperEVM / Solana are included in its supported networks.
- Rate limit, access control, and Global Accountant are provided as protocol-side controls.
- It has a deployment guide to link HyperEVM and the HyperCore spot token for Hyperliquid.

On the other hand, NTT does not assume Arc as a first-batch supported target. Because Arc has strong Circle USDC rail UX, it is realistic to treat it initially not as a JPYdf bridge target, but as a target for USDC funding / swap / payment.

### 3.5 Positioning of LayerZero OFT / Stargate

LayerZero OFT is a strong backup. It has endpoints for Base / HyperEVM / Solana, and there is also a Solana OFT Program. There is also room to put it on a Stargate / OFT route.

However, the reasons for leaning the initial recommendation toward Wormhole NTT are as follows.

- For JPYdf, the supply risk on bridge compromise is large, and NTT's Global Accountant / rate limit is clearer by design.
- For Hyperliquid, there is a concrete deployment guide on the NTT side.
- Solana OFT has many caveats such as upgrade authority, ATA rent, shared decimals, and one adapter per mesh, and adopting it would require a separate Solana-specific runbook.

Stargate is evaluated later as a "route / UX." Avoid fixing JPYdf token authority solely for the sake of Stargate.

### 3.6 Positioning of Circle CCTP / Gateway

Circle CCTP / Gateway does not bridge JPYdf directly. Its target is USDC.

However, because Arc / HyperEVM / Base / Solana are all included in the CCTP / Gateway supported chains, it becomes a very important auxiliary rail in JPYdf's multichain expansion.

- Seeding JPYdf/USDC liquidity on the destination chain.
- USDC rebalancing for treasury / market makers.
- user onboarding: move USDC via CCTP / Gateway, and swap to JPYdf at the destination.
- Arc: payment UX leveraging USDC gas / Circle App Kit / Gateway.

Because this rail does not create canonical JPYdf supply, the spec treats the "USDC route" and the "JPYdf bridge route" separately.

Sources:

- Wormhole NTT overview: <https://wormhole.com/docs/products/token-transfers/native-token-transfers/overview/>
- Wormhole NTT supported networks: <https://wormhole.com/docs/products/token-transfers/native-token-transfers/reference/supported-networks/>
- Wormhole NTT Hyperliquid deployment: <https://wormhole.com/docs/products/token-transfers/native-token-transfers/guides/deploy-to-hyperliquid/>
- Circle CCTP overview: <https://developers.circle.com/cctp>
- Circle CCTP supported blockchains and domains: <https://developers.circle.com/cctp/concepts/supported-chains-and-domains>
- Circle Gateway supported blockchains: <https://developers.circle.com/gateway/references/supported-blockchains>
- Arc App Kit supported blockchains and tokens: <https://docs.arc.io/app-kit/references/supported-blockchains>
- LayerZero Solana OFT: <https://docs.layerzero.network/v2/developers/solana/oft/overview>
- LayerZero deployed endpoints: <https://docs.layerzero.network/v2/deployments/deployed-contracts>

## 4. Changes Needed When Preparing for Implementation

Preparing for this direction is treated not as a "PR that operates a bridge," but as **a PR that puts dormant bridge-readiness in before the Day1 token freeze**.

### 4.1 Where It Is Reflected in Active Requirements

Day-2 bridge minter activation does not revive a new `MCHN-*` requirement, but connects to `JpydfToken`'s `CORE-BT-*` and the operations runbook.

| File | Positioning |
| --- | --- |
| `documents/jp/protocol/product/Product-Overview.md` | Holds the higher-level decision that Day-1 has no operating bridge and Day-2 requires a staged activation gate |
| `documents/jp/protocol/product/spec/JpydfToken.md` | `CORE-BT-GOV-001` / `CORE-BT-SEC-005` / `CORE-BT-INV-004` specify the Stage A minter registration conditions, adapter fail-closed gate, and global canonical supply accounting |
| `documents/jp/Parameters.md` | Quantify the approved cap / rate values of `PRM-BRIDGE-*` in the Day-2 activation package, and treat unset routes as not allowed for minter registration / mint / unlock |
| `documents/jp/engineering/verification-ledgers/Core-Requirements-Verification-Ledger.md` | Tracks the `CORE-BT-*` Day-2 adapter verification / incident rehearsal rows |
| `documents/jp/protocol/operations/runbooks/Bridge-Minter-Activation-Gate.md` | The active runbook for bridge protocol, chain architecture, cap / rate, remote accounting, incident flow, tests / invariants, operator-only canary envelope, public route open, and cap ramp |
| `documents/jp/protocol/launch/gates/Mainnet-Initial-Configuration-Checklist.md` | Leaves in the Day-1 freeze checklist the `bridgeAdmin`, minter count = 0, pending minter proposal = none, and Day-2 activation gate reference |

English docs are support translations. Japanese docs should be changed first; English docs can follow after the Japanese source of truth stabilizes.

### 4.2 Contract changes

The minimal contract changes are limited to `JpydfToken` and interfaces. Core contracts (`BorrowerOperations`, `TroveManager`, `StabilityPool`, `CollateralRegistry`, `ActivePool`) are not touched.

| File | Required change |
| --- | --- |
| `contracts/src/JpydfToken.sol` | Add `bridgeAdmin`, pending admin, bridge minter registry, proposal/timelock, immediate remove, and bridge-specific mint/burn. The constructor receives `_bridgeAdmin` in addition to `_owner` |
| `contracts/src/Interfaces/IJpydfToken.sol` | Add `bridgeMint(to, amount)`, self-burn-type `bridgeBurn(amount)`, minter/admin views, and proposal/admin management events/functions |
| `contracts/src/Dependencies/Ownable.sol` | In principle unchanged. `bridgeAdmin` is implemented inside `JpydfToken` as separate storage and a separate role from Ownable |
| New adapter contracts | Not implemented at Day1. Wormhole NTT / LayerZero OFT / CCIP pool are split off into the scope of the Day2 activation PR |

Recommended interface:

- Existing Core functions stay unchanged: `mint(address,uint256)` and `burn(address,uint256)` remain Core-only.
- Add `bridgeMint(address to, uint256 amount)` callable only by registered bridge minter.
- Add `bridgeBurn(uint256 amount)` callable only by registered bridge minter and burning `msg.sender` balance only.
- Do not add `bridgeBurn(address from, uint256 amount)` unless a selected bridge cannot work without arbitrary burn. Arbitrary burn makes bridge minter compromise strictly worse.
- Add `isBridgeMinter(address)` and `bridgeAdmin()` views so deployment and monitoring can prove Day1 dormant state.

### 4.3 Deploy / CREATE2 changes

`JpydfToken` constructor bytecode changes will change the CREATE2 address. This is expected, but must be explicit before any address freeze.

| File | Required change |
| --- | --- |
| `contracts/script/DeployLiquity2.s.sol` | `JpydfToken` constructor args and `jpydfBytecode` preimage must include `_bridgeAdmin`. `DEPLOYMENT_MODE_USE_EXISTING_JPYDF` gate must verify `bridgeAdmin`, no registered minter, no pending proposal |
| `contracts/test/TestContracts/Deployment.t.sol` | test deploy helper has two `new JpydfToken{salt: SALT}(address(this))` paths and precomputed bytecode. Both must include bridge admin |
| `contracts/test/CollateralYieldZapper.t.sol` | local fixture creates `new JpydfToken`. Update constructor args |
| Deployment manifests | Day1 evidence should record `bridgeAdmin`, `bridgeMinterCount` or equivalent absence proof, and activation status |
| Governance handover scripts | Bridge admin handover must be separate from owner handover. Owner still renounces through `setCollateralRegistry`; bridge admin must survive |

If Day1 keeps bridge minter 0, deploy order remains mostly the same:

1. Deploy `JpydfToken(owner, bridgeAdmin)`.
2. Deploy branches and call `setBranchAddresses`.
3. Deploy `CollateralRegistry`.
4. Call `setCollateralRegistry`, which renounces `owner`.
5. Verify `owner == address(0)` and `bridgeAdmin == Safe/Timelock holder`.
6. Verify no bridge minter is registered and no pending proposal exists.

### 4.4 Tests and invariants

New tests should prove both sides: dormant Day1 behavior is still Core-only, and future bridge activation works only through the intended path.

| Test area | Required verification |
| --- | --- |
| `contracts/test/JpydfToken.t.sol` | constructor invariants: zero admin, EOA vs contract policy if required, owner != bridgeAdmin; bridge admin transfer; minter propose/confirm/cancel/remove; timelock boundary; minter count / view |
| Authorization tests | Non-Core cannot call `mint` / `burn`; non-minter cannot call `bridgeMint` / `bridgeBurn`; owner cannot register bridge minter unless owner is also bridgeAdmin by explicit design, which should be avoided |
| Dormant invariant | After normal deploy with no minter, totalSupply can change only through existing Core call sites. Existing Core paths must remain unchanged |
| Bridge self-burn | Registered minter can only burn its own balance. It cannot burn arbitrary user balances without transfer/allowance path |
| Owner renounce survival | After `setCollateralRegistry`, `owner == address(0)` but `bridgeAdmin` can still remove minters / manage proposals |
| Emergency controls | Removing a minter immediately prevents further `bridgeMint` / `bridgeBurn`; pending proposal cancellation works; renouncing bridge admin is safe only after all minters are removed |
| Invariants | Existing supply/debt invariant must be scoped to Ethereum active supply. If bridge minter is active in tests, global supply monitor must include cross-chain accounting mock or exclude bridge-active runs from Core-only invariant |

### 4.5 Security review focus

This change adds supply authority, so it is audit-significant even if Day1 has no active minter.

- Bridge minter compromise: max mint exposure, rate limits, immediate remove.
- Arbitrary burn risk: avoid `burn(from, amount)` for bridge path.
- Admin key risk: `bridgeAdmin` must be Safe / Timelock, not lost when owner renounces.
- Timelock bypass: minter addition must be delayed; removal must be immediate.
- Misconfiguration: wrong bridge admin, owner == bridgeAdmin, EOA admin/minter, admin-minter dual role, pending proposal left at launch.
- CREATE2 address drift: all precomputed address evidence must use final constructor args.
- Event coverage: every minter/admin/proposal state transition must be indexable.
- Monitoring: total supply by chain, registered minter set, per-route cap utilization, failed messages.

### 4.6 Out of scope for the readiness PR

Keep the first PR narrow.

- No Wormhole NTT manager deployment.
- No LayerZero OFT / Stargate / CCIP pool deployment.
- No Arc / Base / HyperEVM / Solana bridge activation.
- No dToken bridge.
- No Trove debt migration.
- No cross-chain Stability Pool or liquidation.
- No frontend bridge UI.

Those belong to Day2 activation specs and runbooks after the dormant token surface is audited.

## 5. Classification of the Protocols Surveyed

| Protocol / route | Primary model | Reference points | Implications for JPYdf |
| --- | --- | --- | --- |
| Circle CCTP | issuer-controlled burn/mint | Burns native USDC on source and mints on destination, eliminating the need for wrapped tokens or liquidity pools | If JPY DeFi aims for this, it needs token-issuer-side mint/burn authority and attestation / message verification |
| Aave GHO | facilitator + cap + CCIP | Has a mint cap / bucket level per facilitator; cross-chain uses CCIP assuming Ethereum origin for lock/burn/release/mint | The old `bridgeMinter` proposal has room to consider "per-minter cap / bucket" |
| Frax Fraxferry | slow optimistic bridge | 24-48h delay, pause / dispute, risk capped by token amount inside the bridge contract | A reference for exit / large-transfer routes that prioritize safety over speed |
| Frax LayerZero/OFT | OFT / adapter | OFT has good UX, but Frax clarifies that some OFTs are a bridge lockbox claim rather than a protocol liability | If JPY DeFi uses an adapter type, it must make clear whether it is "canonical JPYdf" or a "bridge-backed JPYdf representation" |
| Sky USDS / SkyLink | OP Stack native bridge + LayerZero OFT Adapter | Base is escrow + mint/burn, Solana is Ethereum OFT Adapter + Solana OFT Program. Governance manages bridge support / close / upgrade | The realistic solution of adapter-izing without changing the existing token, and the governance-controlled bridge runbook, are useful references |
| LayerZero OFT / Stargate | OFT route layer | Provides multiple patterns such as native OFT, OFT Adapter, and Mint-and-Burn Adapter. Stargate abstracts as a route / API layer | JPYdf must choose whether to give mint/burn to the token itself or hand authority to an external adapter |
| Across | intent / relayer + CCTP/OFT routing | The relayer pre-funds on the destination, and the API selects intent / CCTP / OFT | Effective as a UX / routing layer after JPYdf's canonical cross-chain supply exists. Not a substitute for canonical issuance |
| Aave V4 / Compound III | chain-local market deployment | Places lending markets on multiple chains, but treats each market basically as chain-local risk | JPYdf Day3 full-protocol expansion should be treated as "independent markets per chain," not the movement of Trove debt |

## 6. Protocol Notes

### 6.1 Circle CCTP

Circle CCTP executes USDC's source burn / destination mint in an issuer-controlled manner. The materials also describe a design that transfers native USDC 1:1 without using a wrapped token or a
traditional bridge liquidity pool.

Reading it across to JPYdf:

- To adopt the same type for JPYdf, an issuer / governance-managed bridge minter or token pool is needed.
- Circle's strength is that Circle itself is the USDC issuer and can directly mint native USDC on each chain. For JPYdf, this premise must be built in-house.
- CCTP is a "finished product for USDC" and does not put JPYdf onto CCTP as-is. We reference it as a design pattern.

Source: <https://developers.circle.com/cctp>

### 6.2 Aave GHO

Aave GHO takes the facilitator model. Governance approves facilitators, and each facilitator has a `bucketCapacity` and
`bucketLevel`. In GHO's cross-chain expansion, all GHO is considered Ethereum-mainnet-originated, and CCIP is used as the approved bridge.
The flow is lock on the Ethereum side, burn on other chains, and release or mint on the destination.

Reading it across to JPYdf:

- The old `bridgeMinter` proposal was a design that manages "who is the bridge minter" on the token side and places rate limits on the minter side.
- Because GHO has a token-level bucket, whether to give each `bridgeMinter` a supply bucket in JPYdf too is worth reconsidering.
- However, since GHO's facilitator assumes broadening mint authority to multiple uses, if JPY DeFi values the Core supply invariant, the bridge facilitator should be limited to bridge-only.

Source: <https://aave.com/docs/ecosystem/gho>

### 6.3 Frax

Frax uses multiple bridge models together.

Fraxferry is a slow bridge of 24-48h, adopting a design that limits risk to the token amount inside the bridge contract
to avoid bridge hacks / infinite mint risk. It has batch proposal, 24h wait, dispute, pause / cancel, and so on.

On the LayerZero x Stargate side, Frax assets are represented as OFTs on multiple chains. However, the docs clearly state that LayerZero OFT Frax Assets are
not a native liability of the Frax Protocol, but redeemability against the underlying Frax asset inside the LayerZero lockbox.

Reading it across to JPYdf:

- The idea of separating a "fast route" and a "safety-focused route" is useful. There is room to adopt the slow route for large transfers / treasury transfers.
- If an OFT Adapter type is adopted, the spec must clearly state whether the token visible to users is a JPY DeFi protocol liability or a bridge lockbox claim.
- Frax's multi-bridge combination is powerful, but in JPYdf's early stages, operations, monitoring, and accounting become too heavy.

Sources:

- <https://docs.frax.finance/cross-chain/bridge>
- <https://docs.frax.finance/cross-chain/layerzero-x-stargate>

### 6.4 Sky USDS / SkyLink

Sky separates methods according to multiple chain / bridge contexts.

For Base, it customizes the OP Stack native bridge, taking a configuration of escrow on the Ethereum side, mint on the Base side, and burn + security delay +
release from Base to Ethereum. Governance can manage token support, bridge upgrade, bridge close, and withdraw limit.

For Ethereum-Solana, there is material on migrating from Wormhole to LayerZero, where the Ethereum side locks the existing USDS into an OFT Adapter,
and the Solana side mints/burns via an OFT Program. USDS on Solana is explained as 1:1 backed by USDS on Ethereum, and sUSDS is described as out of scope for the initial bridge.

Reading it across to JPYdf:

- The adapter type that does not change the existing token can be a realistic option after shipping the Day1 token bridge-incapable.
- However, the adapter type creates a dependency on source-chain escrow / lockbox. It does not break the Core supply invariant, but monitoring of circulating supply and locked supply becomes mandatory.
- The decision to put sUSDS out of scope for the initial bridge is grounds for putting dToken / yield-bearing tokens out of the initial bridge scope in JPYdf too.

Sources:

- <https://developers.skyeco.com/guides/skylink/base-eth-native-bridge/>
- <https://developers.skyeco.com/guides/skylink/usds-ethereum-solana-bridge/>

### 6.5 LayerZero OFT / Stargate

LayerZero OFT is a standard that maintains unified supply while letting a fungible token exist on multiple chains, basically source debit /
destination credit. Native OFT uses burn/mint, and OFT Adapter for existing tokens uses lock/release.

Stargate, as a route layer, abstracts OFT, CCTP, Stargate V1/V2, and so on. OFT routes include native OFT, lockbox adapter,
and mint-and-burn adapter; in the MABA type, the base token must have external `mint()` / `burn()` and authorization to the adapter.

Reading it across to JPYdf:

- If the token can be changed before Day1, native burn/mint or a bridge minter registry is the most natural for canonical supply.
- If the token cannot be changed after Day1, the OFT Adapter / lockbox type is realistic. However, its canonical nature must be explained as an "Ethereum locked JPYdf backed representation."
- The MABA type is close to the old `bridgeMinter` proposal. If the JPYdf token can register adapters/minters, it is easy to put on the Stargate / LayerZero route.

Sources:

- <https://docs.layerzero.network/v2/developers/evm/oft/quickstart>
- <https://docs.stargate.finance/introduction/architecture>
- <https://docs.stargate.finance/primitives/routes/oft>

### 6.6 Across

Across uses the intent / relayer type as its main axis, and for stablecoin routes the API selects intents, CCTP, or OFT. The relayer fills fast with its own capital on the destination side,
and receives settlement later. In the materials, stablecoin settlement is organized into three paths: relayer fill, Circle mint/burn, and LayerZero
mint/burn.

Reading it across to JPYdf:

- Across is not the answer to "how to issue JPYdf." It is a UX layer that presupposes JPYdf or a JPYdf representation and route liquidity on the destination chain.
- In the future, putting an Across-like API / relayer UX on top of the JPYdf bridge gives the best user experience.
- However, the dependence on relayer capacity, refund settlement, and optimistic verification is treated as separate risk.

Sources:

- <https://docs.across.to/introduction/stablecoins>
- <https://docs.across.to/introduction/actors>

## 7. Candidate Architectures for JPY DeFi / JPYdf

### Option A: Token-native burn/mint

Register a bridge minter / bridge adapter on the JPYdf token, burn on source, and mint on destination.

Pros:

- Easy to avoid wrapped tokens.
- Easy to align circulating supply across all chains by design.
- Good fit with LayerZero OFT / CCIP CCT / Stargate MABA.

Cons:

- Requires changing the active requirements of `JpydfToken`.
- Arbitrary mint risk on bridge minter compromise is the largest.
- Changes the Day1 "Core mint/burn only" invariant, so the audit scope is large.

Required controls:

- bridge admin is Safe + timelock.
- bridge minter addition is timelocked, removal is immediate.
- adapter-side per-chain / per-route cap, rate limit, pause, emergency remove.
- cross-chain supply monitor.
- bridge-specific runbook and incident drill.

### Option B: Existing-token lockbox / OFT Adapter

Ethereum JPYdf is unchanged; the adapter locks Ethereum JPYdf and mints/burns the destination representation.

Pros:

- Does not break the Ethereum Core mint/burn invariant.
- Easy to introduce even after Day1.
- Can expand an existing token across chains like Sky USDS / Frax OFT.

Cons:

- The destination token is strictly an Ethereum locked JPYdf backed representation, and is hard to explain as native JPYdf.
- Must monitor lockbox balance, destination supply, failed messages, and exit on bridge close.
- Placing multiple adapters fragments liquidity / accounting, producing operational risk equivalent to permanent loss.

Required controls:

- Limit adapters to one per chain pair / route.
- Continuously monitor locked JPYdf >= destination minted representation.
- Make the canonical route explicit in the bridge UI / token list.
- Runbook for bridge close / migration / pending transfer finalization.

### Option C: CCIP CCT-style token pool

Use Chainlink CCIP CCT's token pool and admin registry to configure a token pool of lock/release or burn/mint.

Pros:

- The operational units of token pool, admin, rate limit, and registration are clear.
- Close to GHO's CCIP adoption example.
- Easy to design the registration / administration flow from a Safe.

Cons:

- Locks in to CCIP adoption.
- Depends on CCIP supported chain / token pool capability.
- Requires selecting whether to allow external mint/burn on the JPYdf token side, or to lean toward lock/release.

### Option D: Across-like UX layer only

JPYdf bridge issuance is solved by another method, and an Across / intent / relayer-type UX is placed on top.

Pros:

- The user experience is the fastest.
- Can abstract route selection / fee estimation / destination delivery on the API side.

Cons:

- Not a means of creating canonical supply.
- Hard to establish in the early stage when relayer liquidity is thin.
- Becomes two layers of risk: bridge settlement and relayer settlement.

### Option E: Full protocol per chain

Deploy Core / dToken / Oracle / Zapper / liquidation infra independently on each chain, and circulate JPYdf across chains by inter-chain burn/mint.

Pros:

- Can issue JPYdf from local collateral on each chain.
- Natural as Aave / Compound-type multi-market DeFi.

Cons:

- Must hold Oracle, liquidation bots, SP liquidity, governance, and treasury accounting per chain.
- Trove debt cannot be moved. Each chain holds risk parameters as an independent market.
- Compared to Day2 token-only, the audit and operations cost is large.

## 8. Recommended Order of Consideration

1. **Keep Day1 single-chain as protocol operation.** Do not open other-chain transfers at Day1.
2. **But decide bridge-readiness before token freeze.** If targeting Arc / Hype / Base / Solana in the future, make putting in a dormant bridge extension the first candidate.
3. **Redesign Day2 token-only as the minimum scope.** Place only JPYdf on other chains, and do not place Core / dToken / Trove / SP.
4. **Make Wormhole NTT the first candidate for the bridge protocol.** Verify in the order Base pilot → HyperEVM pilot → Solana pilot, and add Arc after custom token bridge support becomes clear.
5. **Build in Circle CCTP / Gateway as the USDC rail.** Treat it not as a JPYdf bridge, but as an auxiliary route for liquidity funding / treasury rebalance / user onboarding.
6. **The first branch is token-native burn/mint or lockbox adapter.**
   - Choose Option A if prioritizing canonical JPYdf.
   - Choose Option B if prioritizing Day1 token immutability.
7. **Exclude dToken / sUSDS-like yield-bearing representations from the initial bridge scope.** Just as Sky put sUSDS out of scope for the initial USDS Solana bridge, do not mix yield / share accounting into the initial bridge design.
8. **Treat Across / Stargate not as a protocol choice but as a route / UX choice.** Consider it after JPYdf's supply authority and canonical route are settled.
9. **Do not reuse the old `MCHN-*`.** The active Stage A/B/C gate is handled by `JpydfToken`'s `CORE-BT-*` and [Bridge-Minter-Activation-Gate](../../../operations/runbooks/Bridge-Minter-Activation-Gate.md).

## 9. Open Questions

- How to define the conditions for calling the destination token "JPYdf." Only native burn/mint, or also including an Ethereum locked JPYdf backed representation.
- On which adapter / pool / monitoring to enforce bridge minter cap / rate limit.
- How post-activation governance separates bridge admin / bridge adapter admin / emergency council.
- Whether the initial chain should be Base. The bridge standard, finality, wallet UX, and liquidity venue differ on HyperEVM / Solana / Arc.
- Which of NTT / OFT / CCIP CCT / custom minter is production-ready for Arc's custom JPYdf bridge.
- How many decimals to use for JPYdf mint on the Solana side. How to handle dust / u64 cap against ERC20 18 decimals.
- In which runbook to manage pending transfers, deprecation, UI disable, and token list update on bridge migration.
- Which invariant the cross-chain supply monitor watches. For example, a model-specific definition such as `Ethereum locked + Ethereum circulating + Sum(destination minted) == Ethereum JPYdf totalSupply + adapter-accounted minted` is needed.

## 10. First Draft Decision

The current decision is as follows.

**JPYdf puts in a dormant bridge extension before the Day1 token freeze. The Day2 token-only bridge makes Wormhole NTT the first candidate. Verify in the order Base → HyperEVM → Solana, treat Arc for the time being as a USDC rail and add it after custom JPYdf bridge support becomes clear. Defer full protocol per chain.**

Reasons:

- The "movement" users want is sufficiently met first by moving JPYdf itself across chains.
- Choosing no extension at Day1 makes future canonical burn/mint hard to build without token migration.
- Because Arc / HyperEVM / Base / Solana have strong USDC rails, separating the JPYdf bridge from USDC movement makes it easier not to confuse UX and supply risk.
- Wormhole NTT is easy to handle Base / HyperEVM / Solana together, and its rate limit / Global Accountant fits JPYdf's supply risk management.
- Arc has high strategic value in USDC gas / CCTP / Gateway, but making it the first batch of the JPYdf custom token bridge carries large uncertainty.
- Moving Trove debt / dToken / collateral would extend the Liquity core risk model across chains, which is excessive as an initial scope.
- Other protocols also separate the bridge of the stablecoin itself from the multi-chain expansion of the lending / collateral market.
- Across-like UX is effective later, but canonical supply / lockbox backing / bridge governance are needed first.
