# InterestRouterForwarder Route Runbook

## 0. Scope

In Day-1 DF dToken wiring, the ActivePool residual interest / upfront fee 25% is minted to `InterestRouterForwarder`. `route()` is permissionless and sends the full JPYdf balance held by the Forwarder to the current `recipient`.

This runbook defines the procedure for monitoring and resolving the operational risk that residual JPYdf remains in the Forwarder because `route()` has not been called.

`route()` is not a user claim. The 75% of borrow interest that SP depositors receive from Day-1 goes directly into the Core Stability Pool accounting. The 25% that reaches the Forwarder is PIL funding, and Day-1 only performs accounting aggregation to the `recipient`. The Earn UI and public stats must not present this 25% as an SP additional reward, a claimable reward, or a guaranteed yield.

## 1. Roles

| Role | Responsibility |
| --- | --- |
| Ops keeper | Periodically execute `route()` and confirm transaction success |
| Ops dashboard | Monitor Forwarder balance, recipient, owner, and last route timestamp |
| Timelock / GOV | Change `recipient` and perform post-handover Forwarder owner configuration |
| Finance / accounting owner | Classify the routed amount as a PIL bucket and do not confuse it with SP / Treasury additional rewards |

`route()` itself is permissionless. If the keeper key stops, any operator or monitoring bot can call the same function.

## 2. Monitoring

The ops dashboard should display and alert on at least the following signals.

| Signal | Alert condition |
| --- | --- |
| `JPYdf.balanceOf(InterestRouterForwarder)` | `> 0` persists beyond keeper cadence |
| `recipient()` | Mismatch with expected Safe / Treasury |
| `owner()` / `pendingOwner()` | Mismatch with expected Timelock handover state |
| Last successful `Routed` event | Cadence exceeded, or not emitted after the Forwarder balance increased |
| routed PIL ledger | Mismatch when reconciling the ActivePool mint residual 25% against `Routed` / recipient deposits |

Recommended initial values: route within 1 hour after detecting balance `> 0`; treat retention longer than 24 hours as an incident.

## 3. Keeper Procedure

The standard keeper uses the `route-interest` script in `frontend/ops`. The script reads each branch's `AddressesRegistry.interestRouter()` and fails fast unless all branches point to the same Forwarder, the Forwarder's `jpydfToken()` matches the deployment JPYdf token, and the RPC `chainId` matches the expected value.

```bash
# Dry-run by default. Prints balance, recipient, owner, and simulation result as JSON.
pnpm --filter @jpydf/ops route-interest -- --dry-run

# Live mode. IRTR_ROUTE_PRIVATE_KEY is only the keeper EOA. Do not print the private key.
IRTR_ROUTE_MODE=live \
IRTR_ROUTE_PRIVATE_KEY=0x... \
IRTR_EXPECTED_CHAIN_ID=31337 \
IRTR_EXPECTED_RECIPIENT=0x... \
pnpm --filter @jpydf/ops route-interest
```

In production, set `IRTR_EXPECTED_RECIPIENT` as a required operational value. If balance is `0`, the script is a no-op. If the balance is below `IRTR_MIN_ROUTE_AMOUNT` (raw 18-decimal JPYdf), the script threshold-skips it. Live mode runs `simulateContract(route)` before sending and refuses to submit if the return value does not match the Forwarder balance.

Procedure:

1. Run `route-interest --dry-run`.
2. If balance is zero, do nothing.
3. Confirm `recipient()` equals the expected Safe / Treasury. If it mismatches, do not call `route()`; escalate to GOV/Timelock.
4. Run live mode.
5. Verify:
   - Forwarder JPYdf balance is zero.
   - Recipient JPYdf balance increased by the routed amount.
   - `Routed(recipient, amount)` event was emitted.

## 4. Failure Handling

- `route()` revert: save tx hash / revert reason / current balances, and do not retry in the same block. Separate token transfer failure, wrong token address, and recipient issues.
- Wrong recipient: queue / execute `setRecipient(expectedRecipient)` through Timelock, then call `route()`.
- Owner mismatch: compare `PrepareDFGovernanceHandover` / `VerifyDFGovernanceHandover` output with the manifest and determine whether ownership is pending or complete.

## 5. Non-Goals

The Forwarder has no distribution logic. SP additional rewards, buybacks, and Treasury splits are Day-2 Treasury / SPAdditionalRewardDistributor responsibilities. Day-1 only aggregates to the recipient Safe.
