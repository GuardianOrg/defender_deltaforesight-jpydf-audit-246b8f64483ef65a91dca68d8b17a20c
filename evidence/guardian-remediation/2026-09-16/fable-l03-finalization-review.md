## Verdict: APPROVE, no blocking finding

I could not execute Foundry, the size gate, or the storage-layout comparison. All test counts, the 24,547-byte figure, and the 29-byte margin are the lead's claims. Everything below comes from tracing the code at head b1743a7 in the isolated snapshot.

The Medium design gap from my previous review is resolved. Reserved branches no longer inherit the 1,000-unit cap permanently. The cap now follows the same one-shot lifecycle as the six risk values, and I found no remaining path that lets the cap change after finalization or lets the bootstrap cap pay a liquidator.

## What the code proves

- **Shared struct and ABI.** `RiskParams` is a file-level seven-field struct in `Types/RiskParams.sol`, imported by both interfaces. No stale interface-scoped references remain anywhere in src, script, or test. Moving the struct to file scope does not change tuple encoding. The added field changes the selectors of the registry finalization function, the TroveManager sync function, and the event topic. The BorrowerOperations sync selector is unchanged. The PR body correctly says manifests and activation calldata must be regenerated.
- **Registry validation order.** The cap range check runs after the risk-value checks and before the branch-readiness check, and before any storage write. A bad cap reverts with the dedicated error and leaves the flag false. All prior guards for cap, supply, Troves, debt, collateral, SP deposits, oracle pause, and shutdown are unchanged.
- **One-shot lock.** Active branches set the finalized flag in the constructor, so the finalization function is permanently unreachable and their cap is fixed from construction. Reserved branches flip the flag once. The TroveManager cap has exactly two writers: the constructor and the registry-only sync, gated by an immutable registry address. The registry is not upgradeable and has no other call site into the sync. No recurring setter exists.
- **Rollback.** Both child syncs are plain external calls with no try/catch, so any failure reverts the registry values, the flag, and the earlier BorrowerOperations sync.
- **Bootstrap cap is unreachable economically.** Both Trove-opening entry points route through the internal open path that reverts before finalization. Both Stability Pool variants reject deposits before finalization. Liquidation needs an open Trove, so no liquidation can ever pay the 1,000-unit bootstrap cap on a reserved branch.
- **Consumer.** The cap is read in one place, applied to the SP-offset portion only. Redistribution-only collateral still earns nothing.
- **Deployment.** CREATE2 prediction and the actual deployment encode the same constructor pair. The test deployer and tester constructor forward the cap identically.
- **Storage.** I counted 3 inherited fields and 27 TroveManager fields ending with `shutdownTime` at slot 29, cap at slot 30. This matches the lead's storage-gate claim and is unchanged from the previously reviewed head.

## Tests and docs

The tests cover what they claim. The finalization test reads the bootstrap cap from the TroveManager, then the finalized cap. The fuzz test proves a second finalization reverts and the cap stays. The rollback test mocks the new struct selector. The partial-offset case now lands strictly below the cap, and the constructor test has positive controls. My earlier statement about the "deployed cap remains fixed" assertion was wrong. It reads the existing TroveManager after changing deployer state, which is a valid if trivial check.

Remaining items, all low and non-blocking:

- **Storage-table order is wrong.** The EN spec TroveManager storage table is labeled "Declaration order" but places the cap row right after the redistribution penalty, implying slot 15. The contract declares it last, at slot 30. The deployment gate relies on storage readback with layout attestation, so this row should move after `shutdownTime`. See `docs/en/protocol/product/spec/Liquity-v2-Core-Spec.md:3959`.
- **"Six values" survives in three places.** The bootstrap-values requirement in the EN spec, the matching ledger row, and the D-4 runbook row in the September 3 assessment still say six values. The finalization tuple is now seven. See `docs/en/protocol/product/spec/Liquity-v2-Core-Spec.md:5495`.
- **No production getter for the effective cap.** The TroveManager field is internal and the registry does not store it. Reserved branches get the event. Active branches are observable only through constructor calldata and slot 30. Acceptable given the size margin, but disclose it in the Guardian response.
- **Deploy invariant test covers two indices.** The helper is asserted for indices 0 and 1 only. Asserting the bootstrap value for indices 2 through 7 would pin the helper cheaply. Optional.
- **Verification ledgers predate the split.** Both language ledgers still describe the keeper cap as 1,000 units. Pre-existing and outside this diff.

The JP Core spec has no finalization sections at all, so nothing there is stale. The two JP sections that exist were updated correctly. L-04 and I-09 are untouched here and are not regressions. The bare require in the TroveManager sync is retained, so I-06 remains open and any fix must rebase onto the new struct signature.