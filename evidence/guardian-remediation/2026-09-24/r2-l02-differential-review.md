# Guardian R2 L-02 differential review

## Result

No blocking defect found in the reviewed candidate. Engineering review supports the funding-safety correction; Guardian re-review, merge, live deployment/balance discovery, and activation remain separate. This is a review by the implementing agent, not independent external audit approval.

| Finding severity | New actionable findings |
| --- | ---: |
| Critical / High / Medium / Low | 0 |

Scope: baseline `09076b0c6e4b0df706b6779c54742f4e044b1860` to candidate `432e7015358dc060dc7bee2c2d6664e3c3fc6fc3`. Candidate production tree: `3f7ab10db30e6dc237bb9f4cbf8447393a69dca6`. Implementation commit: `11828df54c9ab5508db2fd0500b02d6b87bbfe32`; the final follow-up changes only Japanese/English specification tables and pause wording. The entire `contracts` and workflow trees are identical between these commits. All seven changed files reviewed. Money movement and registration semantics are high-risk surfaces despite the original finding's Low classification.

## Changes and history

| File | Change | Risk |
| --- | --- | --- |
| `contracts/src/PILAllocator.sol` | +46/-2: deferred reservations, withdrawals, retirement release, registration failure rollback | High |
| `contracts/src/Initiatives/UniV4MerklInitiative.sol` | +43/-4: allocator-bound atomic funding and post-retirement recovery | High |
| `contracts/test/PILAllocator.t.sol` | Real-JPYdf reservation/claim and registration rollback | Verification |
| `contracts/test/UniV4MerklInitiative.t.sol` | Collision model, repeated-epoch fuzz, isolation, retirement, pause, token mismatch, zero-ID rollback and deferred reentrancy | Verification |
| Japanese and English PILAllocator specs | Updated accounting, compatibility and migration requirements | Operational |
| Audit scope guide | Candidate identity and unchanged historical audited identity | Evidence |

Original push-before-hook behavior dates to `6ffa47a76a` (2026-06-26). Duplicate suppression was added in `1e1d7a064c`, and keeper/public timing in `5986f3aa17`. Those controls are preserved; neither prevents an external caller from pre-creating the expected Merkl ID. Existing gas-bounded best-effort ordinary claim hooks remain intact. Registration hooks now must succeed so Merkl cannot be registered in an unintended push mode after failed setup.

## Fund flow and threat model

An unauthenticated attacker can squat future campaign IDs, call public distribution and late-window creation, and donate tokens. Registered receivers can select deferred mode and withdraw only their own reservation. The owner controls membership and weights; the guardian pauses. JPYdf is the trusted fixed-balance, no-transfer-hook token; Merkl is an external dependency.

`distribute()` at `PILAllocator.sol:179` uses held balance minus reservations. Ordinary receivers keep push behavior. Deferred receivers get a per-address credit and an equal aggregate increment without an external campaign call. A failed Merkl creation therefore cannot block unrelated receivers or repeatedly redistribute the reserved share.

`claimDeferredFunding()` at `PILAllocator.sol:220` requires the same registered deferred caller as the fixed transfer destination, applies accounting before the transfer, and is non-reentrant. A reverting outer `createCampaign()` restores both accounting and token transfers. No allowance gives the initiative independent access to other allocator funds.

`createCampaign()` at `UniV4MerklInitiative.sol:109` checks registration/pause, combines direct and reserved funding, preserves threshold/local-duplicate/timing gates, then withdraws and creates atomically. Merkl failure and a zero campaign ID revert the entire sequence. Reentrant campaign calls are rejected; allowance clears after success.

`unregisterInitiative()` requires zero weight and releases unused reservations before its best-effort hook. `returnFundsToAllocator()` at `UniV4MerklInitiative.sol:158` accepts permissionless calls only while unregistered, returns only JPYdf and only to the fixed allocator, and is non-reentrant. It cannot siphon another initiative or remove active campaign funds.

## Concrete adversarial checks

1. Pre-create the same creator/token/type/start/duration/data with a different amount/caller. The regression model matches the public Merkl ID inputs, including chain ID. After three colliding epochs, each failure preserves allocator tokens and reservation accounting; the next unused epoch succeeds.
2. Fund a 60/40 Merkl/ordinary pair. The ordinary receiver gets exactly 40% once, including after failed campaign attempts and repeated distribution. Only new inflows create further allocations.
3. During Merkl execution, attempt reentrant `createCampaign()`. It reverts without double withdrawal; the first campaign succeeds once.
4. Return zero ID after token pull. All token movement, approval and reservation changes revert.
5. Try claiming another receiver's funding, opt-in while unregistered, and claiming without deferred mode. All reject before a transfer.
6. Revert registration after enabling deferred mode. Registry, indices and mode all revert, preventing partial setup.
7. Pause, retry, unpause and retry. Pause blocks distribution/claims/campaign creation; recovery works without manual state repair.
8. Retire, return direct funds, receive a late transfer, recover again, and re-register. The destination remains fixed and old reservations do not reappear.

## Validation

- Baseline reproducer: using the exact prior source with only contract names changed, 100 JPYdf remains in the initiative after ID collision and retirement. Calling the new recovery selector against the old instance fails.
- Focused suites: 48 passed, zero failures/skips. The repeated-collision fuzz regression ran 256 cases.
- Existing `df-ops` coverage shard: 67 passed, zero failures/skips, fuzz budget 32. Allocator line coverage 142/149; initiative 96/100. This is measured file coverage, not a claim of complete adversarial coverage.
- Production size gate: allocator 7,788 bytes; initiative 6,713 bytes; all production artifacts passed EIP-170.
- Formatting, whitespace, preserved requirement IDs, changed relative links and Japanese lint passed.
- Full CI at implementation commit: local 1,873 passed / 0 failed / 2 intentional duplicate skips; mainnet 27 passed / 0 failed / 1 intentional duplicate skip. Timelock (5), CCIP entrypoint (1), and CCIP mainnet (1) passed separately. All 11 `Invariants.t.sol` tests passed. DF deploy wiring and bot/surface/source-tree checks passed. The final documentation-only head has identical contracts and workflow trees; its ordinary checks also passed (1,802 fast tests, DF deploy wiring, bot tests and source/surface guards). Utility/mainnet-operation scope skips and unselected CI coverage are intentional; local coverage passed as recorded above.

## Slither triage

Slither completed on 188 contracts with 93 detectors; output was filtered to the two changed production paths (8 reports):

| Reports | Disposition |
| --- | --- |
| Three High `reentrancy-balance` reports in `createCampaign` | No exploit found: `nonReentrant` covers campaign creation/recovery; the token is fixed JPYdf without callbacks; the flagged post-call zero-ID check uses the returned ID, not a stale balance. The deferred reentrant-Merkl regression passes. |
| One Medium ignored return from `claimDeferredFunding` | The withdrawal is the same immutable allocator's reservation just read, with no intervening mutable external call; the atomic amount is fixed. Collision/zero-ID rollback and real-JPYdf single-claim tests verify the accounting. |
| One Low missing zero check in `transferOwnership` | Inherited behavior: zero pending owner cannot accept ownership; the current owner remains. Unchanged by this patch. |
| Two Informational assembly reports | Inherited bounded-return low-level call and minimum-gas arithmetic, unchanged. |
| One Informational costly loop | Required reservation accounting within the existing maximum of 32 initiatives. No venue execution is added to the loop. |

This is not a warning-free whole-repository Slither result.

## Blast radius and migration

Two production contracts change; the existing production deployment script constructs both and its nine tests pass. The shared four-hook interface and Merkl venue interface do not change. Search found no tracked frontend ABI for these contracts requiring regeneration. Existing `df-ops` and `df-deploy-2` coverage shards already own these suites, so no new workflow is needed.

Registration semantics intentionally tighten for every receiver: a contract/Safe that rejects its registration hook can no longer be registered. EOAs still work. Deferred opt-in is receiver-controlled and persistent until removal. New allocator storage appends two mappings and one aggregate; these are immutable deployments, so no proxy storage-upgrade compatibility is claimed.

Residual conditions: ID squatting can still suppress incentives until a later epoch or retirement. A new allocator and Merkl instance must be deployed together; already-deployed immutable instances do not acquire a recovery path. Discover old addresses/balances and settle them before migration. Setting weight to zero alone does not cancel a reservation; pause or batch zero-weight and unregister if stopping consumption is required. A future VotingAllocator needs a new initiative bound to it. No live deployment, recipient, weight, balance or alert-delivery state was verified here.

## Method and evidence

Manual differential review, baseline tracing and git blame, full changed-function control/data-flow review, public caller search, executable adversarial regressions, isolated production build, coverage and static analysis. No sub-agent or external reviewer was used. The venue was modeled from its public source, not exercised against a deployed Merkl instance in this work.

Public reference: https://github.com/AngleProtocol/merkl-contracts/blob/main/contracts/DistributionCreator.sol

Evidence summaries and exact implementation/test patch are included alongside this report. Local raw logs were inspected by the implementing agent.
