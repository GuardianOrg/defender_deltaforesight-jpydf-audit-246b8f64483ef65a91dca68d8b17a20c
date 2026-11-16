# Bridge Minter Activation Gate

> **Positioning**: This is the activation gate that runs before registering even a single bridge minter on `JpydfToken` from Day-2 onward. Day-1 mainnet launch continues to proceed with zero bridge minters and no pending proposals. This document is the operational procedure for [JpydfToken](../../product/spec/JpydfToken.md) `CORE-BT-GOV-001` / `CORE-BT-SEC-005` / `CORE-BT-INV-004`; it does not reuse the `MCHN-*` items from the legacy material [Multichain](../../../archive/Multichain.md).
>
> **Principle**: `JpydfToken` is non-upgradeable and has no token-level chain cap / rate limit / route pause. Therefore, `bridgeAdmin` must not `proposeBridgeMinter` for a bridge adapter that lacks cap / rate / accounting / pause. If you want to retrofit token-level control, go back to a separate design and separate audit that includes a new token / wrapper / migration.

---

## 1. Scope

The subject of this gate is the decision to register any bridge adapter / minter into `bridgeMinterAddresses` for the canonical `JpydfToken` on Ethereum mainnet.

In scope:

- Registration of a minter that can call `JpydfToken.bridgeMint` / `bridgeBurn` on Ethereum mainnet.
- The canonical JPYdf representation on remote chains, bridge adapters, message endpoints, relayers / verifiers / DVNs / guardians.
- Per-chain cap, per-route rate limit, global bridged supply cap, remote supply accounting, pause / remove / emergency response.
- The conditions under which the frontend / ops / subgraph display and monitor a route as an active bridge route.

Out of scope:

- Day-1 launch dormant evidence. The [Mainnet Initial Configuration Checklist](../../launch/gates/Mainnet-Initial-Configuration-Checklist.md) is the source of truth for that.
- The USDC bridge / CCTP / Across route itself. The USDC rail is not the canonical JPYdf supply authority.
- Cross-chain representation of dToken, Trove debt, Stability Pool deposits, or yield-bearing representations. The initial bridge scope is limited to JPYdf token-only.

## 2. Staged Activation Decision

Bridge minter activation handles registration, canary / public route open, and cap ramp separately. To avoid over-blocking the initial Day-2 motion, do not conflate the gate that registers a cap-0 / paused adapter as a minter with the gate that opens a user-facing route.

| Stage | What it enables | Required conditions |
| --- | --- | --- |
| A. minter registration | `bridgeAdmin.proposeBridgeMinter` / `confirmBridgeMinter`. The adapter may be registered with the route paused and runtime cap 0 | The adopted bridge / framework / chain IDs / domain IDs / endpoint addresses / message origin policy are frozen. The adapter enforces on-chain per-destination cap, hourly / daily sliding-window mint limit, global bridged supply cap, route pause, replay protection, domain binding, and remote token binding. `globalCanonicalJpydfSupply` and per-chain `remoteCanonicalJpydfSupply` can be reconstructed, and pending / in-flight messages can be tracked in a separate bucket. admin / minter / upgrader / guardian / relayer / accounting operator are separated. The incident paths for pause, `removeBridgeMinter`, pending proposal cancel, and remote mint stop have been rehearsed. Unit / invariant / fork evidence for cap / pause / replay / accounting and internal differential review are in place |
| B. canary / public route open | An operator-only canary, or a public open of the frontend / ops route flag | Stage A complete. For an operator-only canary, the activation package has a canary envelope (adapter / endpoint enforced allowlisted operator, max amount, expiry, public flag closed), nonzero pilot cap / rate limit values, monitoring thresholds, and subgraph / indexer fields. A route closed by UI / ops flag alone is not treated as an operator-only canary and is regarded as a third-party accessible route. For a public route open, also prepare risk disclosure, frontend / ops route flag, and support response. For a public route, a third-party accessible route, or any breach of the canary envelope, complete an external audit / independent review. The canary has rehearsed the route paused -> small-cap -> paused rollback |
| C. cap ramp | A raise beyond the pilot cap, or addition of routes / chains | After Stage B, incident-free observation, accounting reconciliation, liquidity / support readiness, and governance approval. Cap raises follow a business / risk / ops cadence equivalent to the [Active Branch Cap Ramp Runbook](Active-Branch-Cap-Ramp-Runbook.md) |

Execute `proposeBridgeMinter` only after the Stage A evidence package is in place. Before `confirmBridgeMinter` once the 48h timelock has elapsed, re-verify the Stage A evidence as well, and if there is a chain halt, adapter upgrade, remote token owner change, or verification provider compromise, cancel the proposal. Stage A is not approval of a public bridge route.

If, between `confirmBridgeMinter` and Stage B, the adapter / remote program codehash, endpoint config, remote token authority, owner / upgrader / guardian holders, or cap / rate config change, the Stage A evidence is invalidated. Keep the route paused / runtime cap 0, redo the Stage A verification, and for unapproved drift proceed all the way to `removeBridgeMinter`.

An operator-only canary is enforced not by frontend / ops flags but by the adapter / endpoint-side allowlist, amount cap, and expiry. A route that cannot prove this is treated as a third-party accessible route even with the public display closed, and an external audit / independent review must be completed before Stage B.

## 3. Required Adapter Controls

The adapter / minter must enforce the following fail-closed.

| Control | Requirement |
| --- | --- |
| per-chain cap | An upper bound on outstanding canonical JPYdf per destination chain. State the approved pilot cap explicitly in the activation package, and start runtime at 0 / paused, ramping with each governance approval |
| per-route cap | An upper bound per `(sourceChain, destinationChain, token)` route. When a route is added, do not share an existing cap |
| hourly / daily mint limit | Limit destination mints over a rolling window. Implement so that a window reset or chain reorg does not cause an overrun |
| global bridged supply cap | An aggregate upper bound across all remote canonical supply. Even if the sum of per-chain caps exceeds the global cap, the global cap takes precedence |
| route pause | Separate chain-level, route-level, and global pause. While paused, mint / unlock / message execution stops via revert or no-op |
| message origin binding | Fix the endpoint, source chain/domain, source adapter address, and remote token address / codehash, and reject unknown origins |
| replay / idempotency | Consume each message nonce / GUID / burn id exactly once. Reject re-execution of the same message, different-route replay, and cross-chain replay |
| decimal / dust handling | Fix remote decimals, rounding, minimum amount, and dust burn / refund policy. On u64-amount chains, make overflow / truncation an invariant |
| upgrade gate | If the adapter / remote token / remote program is upgradeable, require a timelock, codehash allowlist, pre-upgrade pause, and post-upgrade smoke test |

On the `JpydfToken` side, the only determination is "whether this is a registered minter." If the adapter lacks the controls above, you must not use the token-side `bridgeMint` to compensate.

## 4. Supply Accounting

The activation package must, at minimum, be able to produce the following accounting view.

```text
globalCanonicalJpydfSupply
  = ethereumJpydfToken.totalSupply()
  - ethereumBridgeEscrowedCanonical
  + sum(remoteCanonicalJpydfSupply[chain])

remoteCanonicalJpydfSupply[chain]
  = remote canonical token totalSupply
  - non-canonical wrapped / escrowed / test balances
```

Operational buckets:

| Bucket | Contents | Treatment |
| --- | --- | --- |
| local Ethereum supply | mainnet `JpydfToken.totalSupply()` | Includes Core debt token supply plus the result of bridge burns / mints |
| Ethereum bridge escrow | Canonical JPYdf held on mainnet by a lock/unlock-type adapter | Deducted from `globalCanonicalJpydfSupply` so it is not double-counted with remote canonical supply. 0 for burn/mint type |
| remote canonical supply | Canonical JPYdf issued by an approved remote token / program | Subject to per-chain cap and global cap |
| in-flight debit | Source burn / lock is done but destination mint / unlock is not yet final | Conservatively treated as outstanding in cap calculation |
| failed / expired message | A message whose debit and credit do not correspond | Enters the incident queue and stops the route until a manual refund / burn / reconcile decision |
| non-canonical representation | DEX LP token, wrapped JPYdf, test token, unapproved token | Not included in canonical supply and not displayed as canonical in the UI |

Invariants under normal operation:

- Finalized source debit and destination credit correspond 1:1.
- `remoteCanonicalJpydfSupply[chain] <= perChainCap[chain]`.
- `sum(remoteCanonicalJpydfSupply) <= globalBridgedSupplyCap`.
- A message rejected by cap / rate limit does not produce a destination mint.
- When there is a manual action such as an emergency burn / admin mint, the incident ID and governance approval remain in the accounting ledger.

## 5. Chain Architecture Recommendation

For initial adoption, judge per chain by execution environment and user flow, rather than "the same adapter everywhere."

| Destination | Recommended initial policy | Rationale / caveats |
| --- | --- | --- |
| Base | The first candidate for the EVM pilot. Consider a LayerZero OFT / MintBurn adapter or a Wormhole NTT-type, and start with a small cap | EVM contracts / monitoring / fork tests are easy to reuse. The Base-Solana bridge involves wrapped / twin / proof flows, so as an initial minter for the JPYdf canonical bridge it is treated as a separate audit |
| HyperEVM | The second candidate for the EVM pilot. Verify the HyperEVM token and bridge adapter first, rather than connecting directly to HyperCore | HyperCore spot asset linking does not automatically guarantee system address balances or ERC20 validity on the bridge side, so HyperCore credit is a separate gate |
| Solana | The non-EVM pilot. Separately audit SPL / Token Extensions, program upgrade authority, PDA / ATA, u64 amounts, decimal dust, and finality | The same invariants as EVM are insufficient. Rehearsal of the remote supply reader and emergency authority is mandatory |
| Arc | USDC rail first. The JPYdf canonical bridge is deferred until Arc's token / domain / adapter support is solidified by production evidence | CCTP is a USDC burn/mint rail, not the supply authority for JPYdf. The Arc UX must not conflate USDC conversion with JPYdf canonical mint |

Handling by protocol family:

| Family | Treatment as a JPYdf bridge minter |
| --- | --- |
| CCTP / Gateway | A rail for USDC. Not a JPYdf bridge minter |
| Across | Useful as a fast UX / intents / USDC route. Treat as a canonical JPYdf route only when the underlying settlement is CCTP / OFT etc. and the JPYdf adapter controls are satisfied |
| Stargate | A liquidity transport / compose UX layer. To hand over JPYdf canonical supply authority, a separately approved adapter / pool control is required |
| LayerZero OFT | A candidate. However, single-DVN dependence is prohibited; require multiple required DVNs, rate limit, adapter-only mint authority, domain binding, and config evidence |
| Wormhole NTT-type | A candidate. Audit manager / transceiver / token authority / pause / rate limit / chain registry against the JPYdf cap/accounting model |

## 6. Governance And Role Separation

Minimum holder separation:

| Role | Holder | Prohibited |
| --- | --- | --- |
| `bridgeAdmin` | mainnet Safe / Timelock contract | Must not be the same as the adapter minter, a deployer EOA, or a relayer key |
| adapter owner / upgrader | Timelock contract | Immediate upgrade, unreviewed implementation, and upgrade without pause are prohibited |
| pause guardian | Guardian Safe / contract | Does not hold cap-raise, upgrade, or minter-confirm authority |
| accounting operator | read-only / dashboard operator | Does not hold mint / upgrade / pause authority |
| relayer / verifier / DVN | protocol-specific set | Must not share secret management with `bridgeAdmin` / adapter owner |

`bridgeAdmin` is responsible only for the propose / confirm / remove of token-level minters. The adapter's cap changes, route additions, and upgrades are separately timelocked by adapter-side governance and must not be mixed into the same Safe transaction bundle as token-level minter registration.

## 7. Incident Runbook

The following triggers are subject to route pause and incident declaration.

- A `BridgeMint` exceeding the expected cap / rate limit, or an inability to compute the cap.
- A message from an unknown source chain / source adapter / remote token.
- A mismatch between remote canonical supply and the accounting exporter.
- Suspected compromise of a bridge endpoint, DVN, validator, relayer, remote admin, or program upgrade authority.
- A destination chain halt, sequencer fault, finality regression, or a stuck bridge message.
- A suspicion that the frontend / indexer displayed a non-canonical representation as canonical.

Initial response:

| Time | Action |
| --- | --- |
| T+0 | Adapter global pause / affected route pause. Set the frontend route flag inactive. Switch the ops alert to incident mode |
| T+15m | `bridgeAdmin` cancels the pending proposal, or `removeBridgeMinter` on the live minter. If needed, the remote adapter owner stops remote mint / unlock |
| T+30m | Freeze the accounting snapshot. Collect source debit, destination credit, in-flight, failed messages, and remote token supply per chain |
| T+1h | Governance decision on emergency burn / refund / manual reconcile. Do not assume user balances can be burned directly; target only adapter-owned / escrowed / remote admin-controlled balances |
| T+24h | Postmortem, cap reset, route re-enable proposal, frontend / support update |

`JpydfToken.bridgeBurn` is self-burn only; it is not a function for emergency-burning arbitrary user balances on mainnet. State this constraint explicitly in the incident plan.

## 8. Verification Matrix

The adapter implementation / remote program must submit the following as tests / invariants.

| Area | Required checks |
| --- | --- |
| minter lifecycle | unregistered minter cannot mint, cannot mint after remove, pending proposal cancel, 48h timelock boundary |
| cap | per-chain cap, per-route cap, global cap, cap ramp, cap decrease, cap exhausted edge |
| rate limit | hourly / daily rolling window, window boundary, multi-message batch, reorg / retry |
| pause | global pause, route pause, source-only / destination-only pause, paused message execution |
| message auth | source chain/domain binding, source adapter binding, remote token binding, endpoint spoof reject |
| replay | same message replay, cross-route replay, cross-chain replay, nonce gap, idempotent retry |
| accounting | source debit vs destination credit, in-flight bucket, failed message bucket, remote supply reader, dashboard export |
| decimals | 18dec EVM, non-18 remote, u64 overflow, dust rounding, minimum amount |
| upgrade | timelock schedule / execute, codehash allowlist, pre-upgrade pause, post-upgrade smoke |
| incident | pause + remove minter rehearsal, emergency accounting snapshot, frontend route disable |

Minimum Stage A evidence:

- Adapter source commit, compiler / build hash, deployed bytecode hash.
- Remote token / adapter / endpoint addresses, chain ID / domain ID, source and destination codehash.
- Approved pilot cap / rate limit values, global cap, initial route state (runtime cap 0 / paused allowed).
- Holder separation table, Safe / Timelock transaction hashes, guardian contact path.
- Unit / integration / fork / invariant logs.
- Internal differential review for the adapter and remote program.
- Accounting exporter JSON sample, dry-run incident record.

Minimum Stage B evidence:

- Canary envelope (adapter / endpoint enforced allowlisted operator, max amount, expiry, public flag closed). For a route closed by UI / ops flag alone, a public / third-party accessible route, or any breach of the canary envelope, an external audit report or independent review.
- Re-reconciliation of the current codehash / config snapshot with the Stage A evidence. If there is drift, redo from Stage A.
- Monitoring dashboard screenshot / JSON export, alert thresholds.
- Subgraph / indexer fields. For a public route open, frontend / ops route flag, risk disclosure, support response.
- Operator-only canary transfer result, rollback / pause rehearsal.

## 9. Activation Procedure

1. Design freeze: Review the chain / protocol / adapter / remote token / cap model / accounting model and build the activation package.
2. Adapter deploy: Deploy the adapter and remote token / program, and start with initial cap 0 and route paused.
3. Stage A verification: Pass the §8 cap / pause / replay / accounting tests, fork / invariant, internal differential review, and incident dry-run. If proceeding to a public / third-party accessible route, or to a breach of the canary envelope, complete the external audit / independent review by Stage B.
4. Governance staging: Separate adapter owner / upgrader / guardian / accounting operator, and make the codehash / config snapshot into evidence.
5. Token proposal: Execute `bridgeAdmin.proposeBridgeMinter(adapter)` and publish the proposal event and `confirmableAt`.
6. Timelock watch: During the 48h, confirm there is no adapter upgrade, remote admin change, chain incident, or verification drift. If there is a problem, cancel.
7. Confirm: Execute `confirmBridgeMinter()`. The adapter may be registered with the route paused / runtime cap 0.
8. Stage B route open: Only after the current codehash / config snapshot matches the Stage A evidence and the approved pilot cap / rate limit, monitoring, and subgraph / indexer fields are in place, open up to the pilot value only. An operator-only canary runs with the public flag closed, within the adapter / endpoint enforced allowlist and the canary envelope. A public route open is a separate approval with frontend / ops route flag, risk disclosure, and support response.
9. Ramp: Cap raises follow a business / risk / ops approval cadence equivalent to the [Active Branch Cap Ramp Runbook](Active-Branch-Cap-Ramp-Runbook.md).

## 10. External Reference Baseline

The activation package must re-fetch the official docs as of the time of review and include at least the following in evidence.

- [Circle CCTP](https://developers.circle.com/cctp) / [supported chains and domains](https://developers.circle.com/cctp/concepts/supported-chains-and-domains): CCTP is a USDC burn/mint rail; confirm support and domain IDs for Arc / Base / HyperEVM / Solana. Treat it as distinct from JPYdf supply authority.
- [Base network docs](https://docs.base.org/base-chain/quickstart/connecting-to-base) / [Base-Solana bridge docs](https://docs.base.org/base-chain/quickstart/base-solana-bridge): Confirm the Base chain ID, the lock / burn / mint / unlock semantics of the Base-Solana bridge, and the validator / Merkle proof / wrapped token boundaries.
- [Hyperliquid HyperEVM docs](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm) / [HyperCore <> HyperEVM transfer docs](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/hypercore-less-than-greater-than-hyperevm-transfers): Confirm the HyperEVM chain ID, HyperCore spot asset link, and the system address balance / ERC20 validity caveat.
- [LayerZero OFT docs](https://docs.layerzero.network/v2/developers/evm/oft/quickstart): Confirm OFT / OFTAdapter / MintBurn adapter, multiple required DVNs, and rate-limit configuration.
- [Stargate docs](https://stargateprotocol.gitbook.io/stargate/v2-developer-docs/integrate-with-stargate/composability): Confirm the liquidity transport / composability scope and its separation from JPYdf canonical supply authority.
- [Across docs](https://docs.across.to/introduction) / [stablecoin settlement](https://docs.across.to/introduction/stablecoins) / [HyperCore route](https://docs.across.to/introduction/hypercore): Confirm intents / CCTP / OFT settlement and the HyperCore USDC route, and confirm the scope in which it can be treated as a UX / settlement rail rather than a JPYdf minter.

These are references for protocol selection; the active requirements for JPYdf are determined by this document, [JpydfToken](../../product/spec/JpydfToken.md), [Parameters](../../../Parameters.md), and the activation package.
