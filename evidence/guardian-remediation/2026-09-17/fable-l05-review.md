Review complete. Verdict first, then findings.

**Verdict: Approve for pinned head 0ab1f32.** No blockers. The code change resolves the root cause of L-05. The items below are optional polish and one deployment-ordering note. I did not execute tests. Everything below is static code review. The lead's test evidence (1815 passed, 169 Morpho/Vault Strategy tests incl. 256 fuzz rollbacks, size gate, Slither scans) is reported by them, not verified by me.

**Root-cause assessment**

The finding was that penalty and recovery lived in different roles and different transactions, so the penalty could commit while the freed idle liquidity went to someone else. The fix joins them in one call frame under a single role:

- `CollateralVault.sol:710-757` now requires a positive `_minReceived`, measures the Vault's own underlying balance delta across the Strategy call, and reverts with `RecoveryBelowMinimum` if short. Because the whole function is one transaction, the venue penalty, the share resync, the principal reduction and the incident pauses all roll back together.
- `MorphoV2Strategy.sol:381-382` withdraws up to `_assets` through the existing bounded-retry `_doWithdraw`, pushes it to the Vault by direct transfer, and reduces principal only by the measured Vault receipt.
- No interleaving by another shareholder is possible, so the specific L-05 window is closed. A send gate installed later, or a short adapter, now surfaces as a full rollback (covered by `test_GuardianL05_ClosedSendGateAndZeroMinimumCannotCommitPenalty`).
- Role separation is preserved. Only WRITEOFF_ROLE is needed. The handover script still requires distinct guardian, allocator and writeoff addresses and strategy owner equal to guardian, and nothing in the new path requires owner or ALLOCATOR_ROLE. `test_GuardianL05_RecoveryIsAtomicAcrossSeparatedRoles` exercises this with an independent writeoff address.
- No deallocation-only entry remains. The Strategy wrapper is still `onlyVault`, and the Vault rejects `_minReceived == 0`.

**Accounting review (all checked, no defects found)**

- Principal: reduced by actual Vault receipt via `_accountReturnedPrincipal(_sendUnderlyingToVault(...))`, clamped to principal. Matches `sendToVault` semantics.
- Shares: penalty resync first (`_ownShares = min(balanceAfter, ownShares)`), then the withdrawal frame subtracts actual burned shares. Donated shares still absorb the penalty first and are not charged for the withdrawal beyond the position.
- Cache: on live refresh failure, reduction by `valuationLossAssets + withdrawnAssets` is exact when estimate was below principal, and over-reduces (conservative) otherwise. Receipt/gross mismatch invalidates. No double count between raw Vault balance and Strategy cache.
- Backing floor: evaluated after receipt and after cache update, so it sees the recovered funds and the reduced position.
- FOT/receipt mismatch: gross vs. net distinguished (fourth Strategy return vs. Vault delta). The inner `withdrawFromMorphoVault` still requires exact asset delivery, so fee-on-transfer underlyings fail closed at the venue frame, as before.
- Partial receipt: halving retry returns the first successful partial. The operator's `_minReceived` decides whether partial is acceptable.
- Reentrancy: Vault entry is `nonReentrant`, Strategy entry is `nonReentrantStrategy`, the self-call frames are self-only, and the Vault push is a plain `safeTransfer`, so the locked `receiveFromStrategy` is never called. The reentering mock asserts both guards trip.
- Ordinary paths: `_sendUnderlyingYieldToVault` to `_sendUnderlyingToVault` is a pure rename at the three existing call sites. `sendToVault`, `sendProfitToVault`, Aave and Merkl paths are behaviorally unchanged.

**Findings**

1. **Low, deployment ordering.** The Vault now decodes four return words from `forceDeallocate` (`CollateralVault.sol:19-23`). If the Vault implementation is upgraded before the Strategy, the incident entry reverts on decode until the Strategy is upgraded (fail-closed). If the Strategy is upgraded first, the old Vault would accept the new Strategy's direct push but only reduce a fallback cache by `valuationLossAssets`, leaving a transient overcount if live refresh happened to fail. Recommend the two UUPS upgrades be executed in one timelock batch. Not a code change.

2. **Info, stale documentation.** These still describe the pre-fix flow or renamed symbols:
   - `docs/en/protocol/operations/policies/Morpho-Operation-Policy.md:271` omits `_minReceived`; the Japanese counterpart was updated.
   - `docs/en/protocol/launch/gates/Morpho-Day1-Vault-Freeze-Package.md:107` and the Japanese file line 104 still call for a "forceDeallocate + emergency-withdraw sequence" dry-run.
   - `Requirements-Verification-Ledger.md` (en lines 422, 924; jp lines 420, 923) cite the two renamed test names.
   - `Strategy.md` and `AaveV3Strategy.md` (en and jp) still name `_sendUnderlyingYieldToVault`.

3. **Info, input sanity.** `_minReceived > _assets` is accepted and will always revert. Harmless and fail-closed. An optional check would give a clearer error.

4. **Info, event reuse.** The Vault emits `ReceivedFromStrategy(strategy, withdrawnAssets, received)` from the incident path (`CollateralVault.sol:747`) even though no `receiveFromStrategy` call occurred. Monitoring that reconciles that event against calls should be told this path also emits it.

5. **Info, pre-existing.** `_assets` is not clamped to the Strategy's tracked value before the venue call, so an oversized request pays a venue penalty on more than the position (still bounded by the frozen bps against `_assets`). The mandatory `_minReceived` and dry-run policy mitigate. Not introduced by this change.

6. **Info, test coverage.** There is no test on the real Strategy where the full-size attempt fails and a halved partial is accepted under a lower `_minReceived`. The mock cannot express that without a new knob. Optional addition.

**Summary**

The remediation is a correct, minimal, atomic fix: penalty and recovery are one transaction, gated by a mandatory positive actual-receipt minimum, with principal, share and cache accounting consistent with the existing `sendToVault` and emergency paths. Approve. Follow-ups are documentation sync and a batched upgrade order for Vault and Strategy.