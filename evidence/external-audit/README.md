# External Audit Findings Intake

This directory preserves external audit material as non-authoritative,
point-in-time evidence. A finding is not accepted merely because it appears in
the imported report. Acceptance requires reproduction against the frozen source,
impact review against the JP source-of-truth specifications, and a remediation
decision with regression tests.

The second Chain Defenders engagement is preserved in two states:

- the original
  [preliminary report and remediation evidence](./preliminary-2026-08/README.md);
- the [final auditor-issued report](./final-2026-08/README.md), which records
  four findings `Fixed` and one `Acknowledged`.

Those five findings are not part of the closed 21-finding ledger below. The
final report, not the preliminary PDF, controls statements about their auditor
statuses.

## Imported Artifact

| Item | Value |
| --- | --- |
| Artifact | [`jpydf-aug-2026-findings.md`](./jpydf-aug-2026-findings.md) |
| Original report | [`jpydf-aug-2026.pdf`](./jpydf-aug-2026.pdf), Chain Defenders, 43 pages |
| Original PDF SHA-256 | `a488541d3204c149adc9d0d7b80f4fa340f71a80f42d5e357899b74112e1b18a` |
| Report source identities | Start `4649e1bb03039ad5c6bd1e5a051e3cde245fa677`; Update 1 `5e504a8310b07e8eef535d61f79a10adcb40c9fa`; Update 2 `abad4a7cecce290bb447f8abe4e9a223055fd4ad` |
| Source SHA-256 | `0e097a0b7ec4f4edd64260e36aac93d0f04867dc1f03b2a29aa7480be4cb1361` |
| Import note | Body preserved; the repository copy adds the conventional final newline. |
| Intake date | 2026-08-03 |
| Comparison target | Freeze commit `dab4dbe5251f980a3af347cba20351513b026e7b` (audit base). `source-snapshot/contracts/` now carries the approved remediation diffs on top, applied per finding via PRs #49–#69; see [`audit-ledger.md`](./audit-ledger.md). |
| Authority | Non-normative audit input; JP specifications remain authoritative for intended behavior. |

The PDF is the immutable source artifact for the closed August engagement. It
is preserved here as prior external-review evidence and does **not** indicate
that the new wstETH / Morpho follow-up audit has started. Its High 01 is the
historical Sky refund issue, not the later valuation-unavailable pricing defect.

The report contains 21 entries: 1 High, 3 Medium, 7 Low, 8
Informational, and 2 Gas findings. The final PDF records 10 findings `Fixed`
and 11 `Acknowledged`. The separately imported Markdown intake captured an
earlier state in which each entry said `Status: New`; the table below records
the subsequent repository-side triage. Dispositions were initialized as
`Proposed` (candidate implementations only) and each was individually closed by
its own audit-decision PR (#27–#47) and snapshot-application PR (#49–#69); the
table now shows the final reviewed state. The audit identities are pinned in
[`audit-ledger.md`](./audit-ledger.md).

Each triage row links to a per-finding evidence note under
[`findings/`](./findings/).

## Initial Triage

| ID | Disposition (initialized as Proposed; closed per finding by audit PRs) | Reason / next check |
| --- | --- | --- |
| [High 01](./findings/high-01.md) | Closed — historically valid, resolved on current `develop` | The strict full-budget predicate is vulnerable at `528ac15f`, but PR [jpydf-v2#1052](https://github.com/deltaforesight/jpydf-v2/pull/1052) already changed Strategy accounting to actual USDS spend. PR [jpydf-v2#1382](https://github.com/deltaforesight/jpydf-v2/pull/1382) merged regression evidence for all three withdrawal paths after A/B reproduction and side-effect review. No additional production-code change was warranted. |
| [Mid 01](./findings/mid-01.md) | Closed — Medium code finding rejected; operational migration risk accepted | Aave's normal `setPoolImpl` retains the Pool proxy, while Core/Lido/EtherFi are separate markets with separate Pool/aToken positions. Dynamic provider following would misconnect the old aToken position. PR [jpydf-v2#1383](https://github.com/deltaforesight/jpydf-v2/pull/1383) kept the immutable Strategy boundary, added a fail-closed provider→Pool mainnet preflight, and documented old-Strategy recovery/new-Strategy activation after full side-effect review. |
| [Mid 02](./findings/mid-02.md) | Closed — Medium accepted with claim correction | The baseline allowed normal `confirmSource` to accept a 50% jump when the old source became unhealthy. The trigger remained owner-only and timelocked, but the normal path silently changed to emergency semantics. PR [jpydf-v2#1384](https://github.com/deltaforesight/jpydf-v2/pull/1384) now compares both price paths against their separate last-good caches, reserves bypass for explicit `confirmSourceEmergency`, and merged after full side-effect review and CI. |
| [Mid 03](./findings/mid-03.md) | Closed — Medium accepted with claim correction | Both JPY freeze implementations restarted the 24-hour window on the first post-dormancy failure. Zero traffic did not itself consume a stale price, but returning activity could use an already-expired cached FX rate. PR [jpydf-v2#1385](https://github.com/deltaforesight/jpydf-v2/pull/1385) now stores the timestamp paired with `lastGoodJpyRate`, anchors the freeze to the earlier of observation and the cached rate's stale boundary, and merged after direct/Proxy regressions, full side-effect review, CI, and a newly surfaced dependency-advisory unblock. |
| [Low 01](./findings/low-01.md) | Closed — Low accepted; recommendation corrected | One Strategy deposit revert did roll back the full allocation. The report's proposed catch-and-strand behavior would have left untracked Underlying in the rejected Strategy, so PR [jpydf-v2#1396](https://github.com/deltaforesight/jpydf-v2/pull/1396) instead isolates the upstream deposit, proves exact same-transaction recovery to the Vault, fails closed when recovery is not exact, and continues to later healthy Strategies. It merged as `4535dfed` after full local/mainnet Foundry, deployment-wiring, frontend, bot, storage-layout, size, selector, and fault-injection review. |
| [Low 02](./findings/low-02.md) | Closed — Low accepted; recommendation corrected | The partial live-or-zero sum did understate the buffer target and moved 40 from the exact reported 100/800/200 example. The report's cache fallback claim was unsafe because a pre-loss cache can exceed current recoverable value. PR [jpydf-v2#1397](https://github.com/deltaforesight/jpydf-v2/pull/1397) instead requires a full live preflight, stops allocation and Treasury outbound movement on any unavailable registered Strategy, preserves solvency-only cache behavior, and automatically resumes after recovery without consuming cooldown. It merged as `5124599e` after A/B reproduction, allocation/Treasury recovery tests, full local/mainnet Foundry, deployment-wiring, frontend, bot, storage-layout, size, selector, and review-thread checks. |
| [Low 03](./findings/low-03.md) | Closed — Low accepted; impact and recommendations corrected | A receiver without arbitrary-call integration could not trigger its delayed settlement, although Safe-style/integrated contracts were not permanently blocked. The report's original-sender override could break beneficiary semantics, and owner-initiated request transfer would not help an incapable owner. PR [jpydf-v2#1398](https://github.com/deltaforesight/jpydf-v2/pull/1398) instead made settlement permissionless while fixing payout to the recorded request owner and deleting the obsolete ownership error. It merged as `8bf86300` after baseline reproduction, fixed-payout/blacklist rollback tests, 1,434-test local and remote full Foundry runs, Zapper, invariant, deployment-wiring, frontend, bot, storage-layout, size, selector, merge-tree, and review-thread checks. |
| [Low 04](./findings/low-04.md) | Closed — Low accepted; recommendation corrected | Feed instances did keep separate JPY state, while the proposed shared inheritance would still create per-instance storage. PR [jpydf-v2#1404](https://github.com/deltaforesight/jpydf-v2/pull/1404) instead introduced one shared JPY/USD rate provider, injected it into every active branch, latched expiry globally before branch-local shutdown handling, and added deployment, frontend, ops, monitoring, runbook, and cross-branch recovery coverage. It merged as `789466ee` after A/B reproduction, 1,445-test Foundry, frontend, ops, deployment-wiring, selector, size, latest-`develop`, CI, and review-thread checks. |
| [Low 05](./findings/low-05.md) | Closed — Low accepted; impact corrected | A nonzero Core protocol recipient could be stored and make `route()` revert, but governance could restore a valid recipient, so the report's “permanently bricked” claim was incorrect. PR [jpydf-v2#1405](https://github.com/deltaforesight/jpydf-v2/pull/1405) now reuses `JpydfToken.requireValidRecipient` in the constructor and setter, preserves the prior live route on rejection, and repeats validation after Core wiring and during all handover phases. It merged as `1adab166` after production-token coverage for every forbidden class, 1,449-test full Foundry, deployment, ABI, size, latest-`develop`, CI, and review-thread checks. |
| [Low 06](./findings/low-06.md) | Closed — Low accepted with claim correction | Production-capable scripts and the deploy CLI unnecessarily accepted and forwarded raw private keys, although the report overstated the production role of the documented local/CI accept helper. PR [jpydf-v2#1406](https://github.com/deltaforesight/jpydf-v2/pull/1406) made `DEPLOYER` public-address-only, moved signing to explicit Foundry Ledger/keystore/KMS/Trezor modes, restricted unlocked signing to local/dev or loopback fork RPCs, and fail-closed the remaining deterministic-key helpers to chain 31337/31338. It merged as `4df6d902` after 1,453-test Foundry, real 8-branch Anvil deployment, signer-negative, deployment-wiring, console, bot, latest-`develop`, CI, and side-effect checks. |
| [Low 07](./findings/low-07.md) | Closed — Low rejected; downgraded to Informational | The cutoff is mechanically real, but PR [jpydf-v2#1407](https://github.com/deltaforesight/jpydf-v2/pull/1407) measures the omitted tail against the actual `DFStabilityPool`: an extreme four-scale replay loses only 12,500 wei of collateral and 125 wei of yield, while realistic amounts round both paths to zero. It keeps the upstream/spec `SCALE_SPAN = 2`, makes no production-code change, and adds regression evidence for the dust bound. |
| [Info 01](./findings/info-01.md) | Closed — future-integration gap accepted; activation gated | PR [jpydf-v2#1410](https://github.com/deltaforesight/jpydf-v2/pull/1410) confirms that the current adapter cannot pull rewards left in an external distributor such as Euler Reward Streams, while Euler remains outside the Day-1 scope. It keeps production code unchanged and gates activation behind a documented No-Go policy — checklist-enforced during activation review, not an on-chain check — until the reward path is proven disabled or a venue-specific claim implementation, settlement tests, and additional audit are complete. |
| [Info 02](./findings/info-02.md) | Closed — Informational code finding rejected | PR [jpydf-v2#1411](https://github.com/deltaforesight/jpydf-v2/pull/1411) confirms that a below-supply cap is the specified hard issuance stop, not a violated global invariant. Existing balances remain unchanged, burn/redemption remains live, and minting resumes automatically after supply falls within the cap. It keeps production code unchanged and extends the real `DToken` proxy regression evidence. |
| [Info 03](./findings/info-03.md) | Closed — observation accepted; remediation rejected | PR [jpydf-v2#1412](https://github.com/deltaforesight/jpydf-v2/pull/1412) confirms that `allocateMaxMove = 0` is the specified and observable outbound stop used by no-Strategy branches, while cooldown zero intentionally disables the interval guard. A high cooldown does block allocation, but the same Vault recovers immediately after GOV correction. It keeps production code unchanged and records the remaining governed-misconfiguration risk. |
| [Info 04](./findings/info-04.md) | Closed — observation accepted; fixed bounds rejected | PR [jpydf-v2#1413](https://github.com/deltaforesight/jpydf-v2/pull/1413) confirms that TTL 0 is the specified fail-closed mode and pre-cache proxy default: healthy live valuation is still used, while a live failure contributes zero without reverting. Restoring a nonzero TTL immediately restores a still-fresh cache. It keeps production code unchanged, rejects the ungrounded universal 1-hour/7-day bounds, and records the real high-TTL stale-value risk. |
| [Info 05](./findings/info-05.md) | Closed — observation accepted; consistency checks rejected | PR [jpydf-v2#1414](https://github.com/deltaforesight/jpydf-v2/pull/1414) confirms that percentage target and absolute floor are independent controls: 0% plus a nonzero floor is a valid fixed-reserve policy, and lowering the floor automatically resumes allocation. The proposed `1_000_000e18` cap is invalid across 6/8/18-decimal Underlyings. It keeps production code unchanged and records the real high-floor efficiency/overflow risks. |
| [Info 06](./findings/info-06.md) | Closed — risk accepted; remediation adapted to deployment order | PR [jpydf-v2#1415](https://github.com/deltaforesight/jpydf-v2/pull/1415) preserves the CREATE2 constructor cycle, then reads back all 18 frozen registry fields after deployment and requires exact expected identity, nonzero addresses, and runtime code. Dedicated tests reject field swaps, zero, and EOAs; `contracts/src`, ABI, and storage remain unchanged. Residual: the eight non-CREATE2 fields are compared against the same input struct fed to `setAddresses`, so a construction-time swap between two code-backed addresses in that struct remains undetected; accepted for lack of an independent in-scope source. |
| [Info 07](./findings/info-07.md) | Closed — observation accepted; blanket setters rejected | PR [jpydf-v2#1416](https://github.com/deltaforesight/jpydf-v2/pull/1416) confirms that venue addresses are intentionally fixed per Strategy instance, while hard replacement uses a fresh proxy alongside the disabled old Strategy rather than requiring an old-proxy upgrade. A two-venue ERC-4626 replay drains, removes, and replaces the old Strategy with its implementation slot unchanged and full backing preserved; generic setters would not migrate venue-bound shares, allowances, or async request state. |
| [Info 08](./findings/info-08.md) | Closed — Informational accepted; wording corrected | PR [jpydf-v2#1408](https://github.com/deltaforesight/jpydf-v2/pull/1408) aligns the Solidity comment and JP/EN core spec with the actual guarantee: the deposit persists across a block boundary, but an intervening `offset()` or a full block of liquidation exposure is not guaranteed. The guard logic remains unchanged; focused same-block/next-block tests and metadata-stripped runtime bytecode comparison confirm no executable change. |
| [Gas 01](./findings/gas-01.md) | Closed — gas growth accepted; global redemption DoS not demonstrated | PR [jpydf-v2#1417](https://github.com/deltaforesight/jpydf-v2/pull/1417) measures a real `CollateralVault` with 32 independent live Sky Strategy graphs at 1,332,387 gas cold and 261,884 gas warm. The current eight-branch and protocol-maximum ten-branch two-pass valuation-only extrapolations are 12,754,168 and 15,942,710 gas. It keeps `MAX_STRATEGIES = 32`, rejects a stale within-block cache, leaves production code unchanged, and adds quantitative regression and future-activation gates without claiming a full-redemption gas bound. The venues behind the 32 Strategies are test fixtures (plain ERC-4626 vault, trivial converter), so mainnet sUSDS/PSM cold accesses will cost more; fork replay is prescribed before activation. |
| [Gas 02](./findings/gas-02.md) | Closed — optimization rejected; regression evidence added | PR [jpydf-v2#1409](https://github.com/deltaforesight/jpydf-v2/pull/1409) reproduces the optimization against the actual `ActivePool`, where the shutdown-path saving is 27 gas rather than the mock's 149 gas. Reordering also changes the documented shutdown + nonzero `upfrontFee` result from Panic 0x01 to a successful zero return. It keeps production code and Core parity unchanged and pins both valid and malformed shutdown behavior. |

## Status

All 21 findings are `Closed — audit-approved (2026-08-05)`. Each was closed
by its own audit-decision PR (#27–#47) and its approved remediation diff was
applied by its own snapshot PR (#49–#69). The eleven previously unmerged
candidates were closed without merge in jpydf-v2 (branches preserved as
`agent/audit-*`) and land there via the single audit sync PR
[jpydf-v2#1418](https://github.com/deltaforesight/jpydf-v2/pull/1418); the
ten changes merged ahead of audit approval are recorded in
[premerged-ledger.md](./premerged-ledger.md) and were mechanically verified
reachable with matching hashes. The pinned audit identities (decision
closure, snapshot closure, audited remediation identity) live in
[`audit-ledger.md`](./audit-ledger.md).
