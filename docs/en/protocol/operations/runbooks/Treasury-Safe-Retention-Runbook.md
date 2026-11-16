# Treasury Safe Retention Runbook

## 0. Scope

Day-1 does not implement `Treasury.sol` / `SPAdditionalRewardDistributor` / `BorrowReferralRewardDistributor` / `SPDepositReferralRewardDistributor`. Each Vault's `treasury` is set to the Foundation/GOV Safe, where operating yield is accumulated. If Day-2 introduces the Treasury implementation, `setTreasury` switches each Vault from the Safe to Treasury and migrates the accumulated balances.

This runbook defines accounting classification during Safe retention, monthly reconciliation, and the Day-2 cutover procedure.
For balance-sheet classification across JPYdf/USDC LP, Vault backstop, and Strategy caps, see the Japanese source-of-truth
[`Balance-Sheet-Liquidity-Allocation-Policy.md`](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md).

## 1. Accounting Buckets

Classify Safe inflows by token, source, and branch.

| Bucket | Source | Day-1 treatment |
| --- | --- | --- |
| Vault underlying yield | `CollateralVault.transferYieldToTreasury()` | Retained in the Safe by Underlying. No additional SP distribution |
| Strategy reward sweep | `BaseStrategy.sweepRewardToken()` | Retained in the Safe as non-Underlying reward tokens. Not automatically counted as backing |
| Interest residual JPYdf | `InterestRouterForwarder.route()` | Retained in the Safe as JPYdf. No distribution logic |
| Manual backstop funds | Funds used for `backstopDeposit()` | Counted as backing repair only for the amount explicitly deposited into the target Vault as its Underlying |
| Manual LP seed funds | Balance-sheet USDC / JPYdf | Separately classified for the JPYdf/USDC v4 position. Do not mix with Vault buffer, backstop, or protocol yield |

Day-1 specifies accumulation only. Do not promise Safe balances as additional SP rewards.
Funds used for JPYdf/USDC LP are market-liquidity funds and are not classified as dToken backing repair.

Assets used for `backstopDeposit` must be the target Vault's `underlying()`. JPYdf, dToken, Aave/Merkl reward tokens, and other Safe-held assets do not repair backing as-is. If they are used for backing repair, convert them into the target Underlying through an approved Foundation / Treasury procedure and classify the repair amount based on the `BackstopDeposited(backstop, declaredAmount, received)` event.

## 2. Monthly Reconciliation

1. Export Safe token balances and incoming transfers.
2. Export protocol-originated accounting events with the ops ledger:
   ```bash
   pnpm --filter @jpydf/ops export-treasury-ledger -- \
     --pretty \
     --from-block <period-start-block> \
     --out artifacts/treasury-ledger-YYYY-MM.json
   ```
3. The ledger includes active Vault `YieldTransferredToTreasury`, current and historically registered Strategy `RewardTokenSwept`, `InterestRouterForwarder.Routed`, current retention-address ERC20 balances, tx hash, block, token, amount, and branch/source labels.
4. Reconcile event totals against Safe balance deltas by token.
5. Label each unmatched Safe entry with source, tx hash, token, amount, and intended Day-2 handling.
6. Record manual transfers separately. Do not mix manual top-ups with protocol yield unless governance explicitly classifies them.
7. For any manual backstop repair, record the target Vault, target Underlying address/symbol/decimals, source token sold or transferred, conversion tx if any, `backstopDeposit` tx, declared amount, and received amount. JPYdf-denominated Safe balance must not be counted as repaired backing until the target Vault receives Underlying.

### 2.1 Ops Ledger Parameters

- `TREASURY_LEDGER_RPC_URL` (fallback: `OPS_RPC_URL`, generated deployment RPC): RPC endpoint.
- `TREASURY_LEDGER_EXPECTED_CHAIN_ID` (default: generated deployment chainId): RPC chain guard. Mismatch fails.
- `TREASURY_LEDGER_FROM_BLOCK` / `--from-block`: first block included in the event scan.
- `TREASURY_LEDGER_LOG_CHUNK_BLOCKS` / `--log-chunk-blocks`: `eth_getLogs` range size. Default is 250,000 blocks.
- `TREASURY_LEDGER_OUTPUT` / `--out`: output file. Writes atomically when set.
- `TREASURY_LEDGER_PRETTY=1` / `--pretty`: human-readable JSON.

The script fails if the deployment is not using a single `InterestRouterForwarder`, if the Forwarder `jpydfToken()` does not match the generated JPYdf token, or if active underlying token metadata cannot be read. Reward token `symbol` / `decimals` are optional ERC20 metadata; when unavailable, the ledger preserves exact raw amounts and marks decimal display as `null`.

## 3. Day-2 Treasury Cutover

Before cutover:

1. Deploy and verify `Treasury.sol` / `SPAdditionalRewardDistributor` / `BorrowReferralRewardDistributor` / `SPDepositReferralRewardDistributor` according to their specs.
2. Confirm roles: Timelock holds GOV/admin, Guardian holds immediate fail-safe roles, and the Treasurer/keeper role is separate.
3. Queue `CollateralVault.setTreasury(newTreasury)` for every active Vault through Timelock.
4. Execute the queued `setTreasury` calls.
5. Verify every active Vault `treasury()` equals the new Treasury address.

### 3.1 Governance and Audit Acceptance Gate

`Treasury.sol` / `SPAdditionalRewardDistributor` / `BorrowReferralRewardDistributor` / `SPDepositReferralRewardDistributor` are not unimplemented blockers for the Day-1 audit scope. If introduced on Day-2, treat the implementation PR, audit package, and cutover proposal as the same activation gate. Do not execute `setTreasury(newTreasury)`, migrate Safe-retained funds, or enable additional SP / Referral rewards until all of the following pass.

- **Audit scope**: add `Treasury.sol` / `SPAdditionalRewardDistributor.sol` / `BorrowReferralRewardDistributor.sol` / `SPDepositReferralRewardDistributor.sol` / interfaces / deploy scripts / tests in a separate PR, and update `Contract-Audit-Scope-And-nSLOC.md` plus `contracts/src/README.md`. Do not silently mix them into the Day-1 SOW after the fact.
- **Admin holder**: on mainnet, `DEFAULT_ADMIN_ROLE` / `GOV_ROLE` must be held only by the common Timelock. Cutover is blocked if the deployer, an EOA, or a codeless address remains as admin.
- **Guardian holder**: `GUARDIAN_ROLE` is held only by the Guardian multisig. Immediate actions are limited to Treasury destination disable / route proposal cancel / `pauseRouting`, registered-Vault and shortfall-capped `emergencyBackstopDeposit`, reward asset disable, `cancelRoot`, `pauseBuyback`, and `pauseClaims`. Reject the implementation if Guardian can upgrade, add / confirm destinations, change shares, unpause, fund distributions, or perform arbitrary transfers.
- **Treasurer holder**: `TREASURER_ROLE` is a separate operational key from ALLOCATOR / Guardian / Timelock. It is limited to Treasury `splitYield` / `forwardRewardToken` / `emergencyBackstopDeposit`, SPARD / BRRD / SPDRD `executeBuyback`, and buyback / routing pause; it must not control destinations, ratios, root cancellation, or route changes.
- **Distributor boundary**: `notifyTreasuryRevenue` is Treasury-only, `notifyEpoch` is ROOT_POSTER-only, `claim` is permissionless, and `cancelRoot` is Guardian-only inside the challenge window. Unit / fork tests must show that a bad root can still be cancelled when `challengeWindow < Timelock delay`.
- **Asymmetric recovery**: `pauseBuyback` / `pauseClaims` are immediately stoppable, while only Timelock can unpause. Confirm each pause affects only the intended path.
- **Fixed destination**: Treasury / Distributor must not expose caller-specified arbitrary `to` transfers. Treasury routes only to Foundation Safe, purpose destinations, and registered backstop Vaults; Distributor claims pay the account / referrer fixed in the Merkle leaf. Destination / asset additions use propose -> delay -> confirm.
- **Cutover sequencing**: do not queue Vault `setTreasury`, migrate Safe funds, post roots, or enable buybacks until the role verifier plus storage-layout / upgrade tests pass.

After cutover:

1. Transfer classified Safe-held protocol yield to Treasury according to the approved migration proposal.
2. Keep manual top-ups / unrelated Safe assets out of Treasury unless explicitly approved.
3. Run Treasury / Distributor accounting tests and dry-run distribution before enabling any additional SP or Referral reward distribution.

## 4. Failure Handling

- If `setTreasury` is only partially executed, pause further Safe migration and first finish Vault treasury consistency.
- If Safe classification is incomplete, do not transfer ambiguous balances to Treasury.
- If Treasury / Distributor distribution logic is not yet audited, leave balances in Safe; Day-1 behavior remains valid.
