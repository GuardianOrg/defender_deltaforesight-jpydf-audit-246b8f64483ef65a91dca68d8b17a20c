# Core Verification Ledger - parity local test run record

## 0. Purpose and Positioning

This document is the ledger that records whether **every `CORE-*` ID** assigned in [Liquity-v2-Core-Spec.md](../../protocol/product/spec/Liquity-v2-Core-Spec.md) (the core inheritance specification and source of truth) has been verified by implementation and tests in the local environment. The core verification goals are the following two points, as summarized in spec §13:

1. **parity** - every core contract, function, and state variable functions identically to the fork source (the in-repository `base` branch = liquity/bold v1.11.0 frozen).
2. **Limited DF differences** - differences DF added to the core are implemented exactly as listed in the modification ledger (spec §2.2 `CORE-MOD-001` through `007`), and **no other differences exist**.

- **Scope**: all IDs of the form `CORE-<SCOPE>-<FR|INV|SEC|GOV|EVT|ERR>-NNN`, plus `CORE-MOD-*` (modification ledger), spec §13.3 acceptance criteria (non-ID check rows), and `CORE-*-TBD` (open issue registers). **Every assigned ID has exactly one row in this document**, with rows retained and reasons stated even when an item is outside verification scope.
- **Basis**: this document is the receiving side of the guardrail in the [Requirements Spec Standard](../../README.md#requirements-spec-standard): "Do not write test names or execution results in the specification body. ID linkage is one-way: tests and ledgers reference doc IDs." In other words, this document is the source of truth for "ID x actual test x execution result" and pairs with the rule at the end of spec §13.
- **Relationship to normative stance (important)**: 🔵 requirements are the "descriptive normalization of base implementation behavior." If a conflict is found between the spec and implementation, **the base implementation is authoritative and the spec is revised** (spec §2.4). This is the opposite direction from component specs, where "requirements are authoritative and implementation is fixed." For FAIL handling, see §1.3 judgment principle 8.
- **Relationship to the overall ledger**: if an overall requirements verification ledger (Requirements-Verification-Ledger) is maintained for all of `documents/jp`, the verification record for core (`CORE-*`) uses **this document as the source of truth**, and the core section of the overall ledger should reference this document instead of duplicating records.
- **For auditors**: this document lets reviewers trace (1) coverage of all `CORE-*` IDs, (2) happy-path and exception-path evidence for each ID, and (3) evidence artifacts (commit SHA, commands, test names, results).

> Implementation under verification: `deltaforesight/jpydf-v2` (`develop`; record the head SHA at verification time in §2).

---

## 1. Operating Rules (Entry and Judgment)

### 1.1 Row Structure (Common Schema)

Columns are compatible with the overall ledger (Requirements-Verification-Ledger).

| Column | Content |
| --- | --- |
| ID | `CORE-*` ID (use the ID from the source-of-truth spec as-is; do not issue new IDs in the ledger) |
| Requirement (summary) | Short transcription of the spec heading/wording. **The source of truth for expected behavior is the body text of the corresponding ID in the spec** (if the summary conflicts with the spec, the spec is authoritative) |
| Specified verification method | Transcription of each requirement's `Verification` designation in the spec (`parity` / unit / fuzz / invariant=INV-ID / fork / integration / deploy verification / manual. Vocabulary is defined in spec §13.1). Rows without a spec designation are marked `(ledger-defined)` |
| Happy path | `☐` -> `✅` when evidenced, or `N/A` when not applicable (put the reason in Notes) |
| Exception path | Same as above |
| Test artifact | `TestContract::testFunction` (multiple allowed) or a reference to a manual verification record. **Transcribe from execution logs (do not write nonexistent test names)** |
| Result | `Not run` / `PASS` / `FAIL` (issue reference required) / `BLOCKED(reason)` / `N/A(reason)` |
| Notes | Campaign ID (§2), actual skip cause, N/A reason, missing number, etc. |

- Initial generated values are all `☐ / ☐ / Not run`. **Rows with only one applicable side (view-only, sole emitted-event condition, etc.) must be finalized as `N/A(reason)` in the first campaign (V1); do not treat blanks as complete.**

### 1.2 Category Definitions for Happy Path and Exception Path (Core Version)

This inherits the overall-ledger definitions and adds core-specific readings for 🔵 parity targets.

| Category | What the happy path evidences | What the exception path evidences |
| --- | --- | --- |
| FR 🔵 | When preconditions hold, the behavior stated in the spec (Effects, return values, emitted events) holds, meaning **behavior is identical to base** (all green upstream-derived suites under DF parameters, or DF-added tests) | Each revert / early return / boundary condition stated in the spec actually fires in at least one test |
| FR 🟡 | Base behavior plus **only the differences listed in the ledger (CORE-MOD)** hold (for example, same-block withdrawal guard fires and the next block succeeds) | The difference has no other behavior changes (copy-parity: all behavior other than the guard is identical to StabilityPool) |
| INV | Invariants are maintained under normal operation sequences (invariant / fuzz) | Operations attempting to violate them fail, or evidence shows the violating state is unreachable by definition |
| SEC | Operations through authorized roles and paths succeed | Attack paths (unauthorized calls, reentrancy, spoofing, donation, MEV paths) are blocked |
| GOV | Deployment procedure (wiring -> renounce authority) succeeds and configuration matches the spec | Privileged operations, rewiring, and additional registrations revert after renounce |
| EVT | Events fire with specified parameters and triggers | Events do not fire under non-emission conditions (constructor-only events include no runtime emission) |
| ERR | (Primary verification is the exception path) no unintended fallback or false trigger occurs during normal behavior | The degradation, revert, or failsafe stated in the spec actually occurs under the exceptional trigger |
| MOD | The difference is implemented exactly as described in the ledger (expected-diff checker and value checks) | Detection mechanisms for out-of-ledger differences (Core JPYDF surface guard, expected-diff checker, parity tests) detect violations |
| TBD | - outside verification scope (open gate). Resolved items are verified in the destination ID row | - |

### 1.3 Judgment Principles (Guardrails)

Apply the same principles 1 through 7 as the overall ledger: only actual runs are evidence; skips are not PASS; flaky tests require counterexample review; completion claims only after all rows are closed; fork RPC is kept secret; unimplemented items are BLOCKED; verification is pinned to a head commit. Additional core-specific principles:

8. **Direction of FAIL (spec §2.4)**: for 🔵 rows, a FAIL first raises the possibility that "the spec wording differs from the base implementation." Cross-check the base implementation, upstream tests, and the spec. If the implementation matches base and only the spec differs, process it as **spec revision (PR) -> ledger update** (fixing implementation to match the spec would be a forbidden core modification). Treat it as an implementation bug only if the implementation also differs from base. FAIL in 🟡/🟢 rows follows the normal process of filing an implementation issue.
9. **Position of upstream suites**: upstream-derived test suites (unit / invariant / fuzz) passing under DF parameters (`MIN_DEBT=100_000e18`, etc.) may be referenced as broad parity evidence for 🔵 rows (reference by campaign ID + suite name; prefer row-specific tests where they exist). **Runtime-skipped tests do not count as evidence for a row.**
10. **copy-parity (DFStabilityPool)**: 🔵 SP-scope rows become ✅ only when they hold for **both StabilityPool and DFStabilityPool** (because the deployed instance is DFStabilityPool; spec §13.2 layer 2). State the target contract in Test artifact.

### 1.4 Standard Local Run Procedure

```bash
# 1) Do not run on Google Drive. Isolate in a disposable clone
git clone https://github.com/deltaforesight/jpydf-v2 /tmp/jpydf-v2-core-verify && cd /tmp/jpydf-v2-core-verify
git rev-parse HEAD   # -> record in §2
git fetch origin base # prerequisite for parity comparison and guard execution

# 2) Record toolchain
~/.foundry/bin/forge --version   # -> record in §2

# 3) Static parity (§4 rows): JPYdf surface guard and DFStabilityPool diff review
bash .github/scripts/check-core-jpydf-surface.sh
# Reference only: emits raw diff. Because expected differences exist, do not use its exit code for PASS/FAIL.
# Until an expected-diff checker exists, treat this output as manual review.
diff <(cat contracts/src/StabilityPool.sol) \
     <(sed 's/DFStabilityPool/StabilityPool/g' contracts/src/DFStabilityPool.sol)

# 4) Clean build + full test run (save logs and transcribe into ledger; remember set -o pipefail)
cd contracts && ~/.foundry/bin/forge clean && ~/.foundry/bin/forge build
set -o pipefail
~/.foundry/bin/forge test -vv 2>&1 | tee /tmp/forge-core-$(date +%Y%m%d).log

# 5) Fork tests (RPC via environment variables. Do not print URLs or record them in the ledger)
source ~/.config/deltaforesight/rpc.env
~/.foundry/bin/forge test --match-path 'test/*fork*' -vv 2>&1 | tee -a /tmp/forge-core-fork.log
```

- For manual work (configuration review, deploy verification records, etc.), record executor, date, and checked content under `engineering/historical-reviews/`, then reference the record from the relevant rows.

---

## 2. Verification Environment Record (Campaign Ledger)

Add one row per verification campaign (a set of runs on the same commit SHA), and reference the campaign ID from Notes in each ID row.

| Campaign | Date run | repo / branch | commit SHA | forge / environment | fork RPC (type only) | Commands / logs | Executor | Result summary |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C1 | (Not run) | | | | | | | |
| C2 | 2026-08-30 | deltaforesight/jpydf-v2 / `fix/issue-1837-normal-redemption-jpy-age` | contract candidate `8a0640a1` (base `3ff65eddf0d4`) | forge 1.7.1 / macOS | none | `forge test --match-path 'test/PriceFeedProxy*.t.sol'`<br>`forge test --match-path test/PriceFeedPlaceholder.t.sol`<br>`forge test --match-path test/RedemptionHelperOracleFailure.t.sol`<br>`forge test --match-path test/RedemptionHelper.t.sol` | Codex | **All PASS (161 tests)**: PriceFeedProxy family 140, PriceFeedPlaceholder 11, RedemptionHelper standalone 2, full RedemptionHelper file 8. Covered the 30h boundary, fixed-size return-bomb reads, normal/emergency source confirmation, all-unavailable / mixed-denominator / second-read failure, direct/Helper refunds, and existing regressions |

---

## 3. Aggregation (Coverage Dashboard)

**Scope**: all `CORE-*` IDs in [Liquity-v2-Core-Spec.md](../../protocol/product/spec/Liquity-v2-Core-Spec.md) (with JpydfToken `CORE-BT-*` split into [JpydfToken.md](../../protocol/product/spec/JpydfToken.md); total **437**, shown below). Of these, the 5 TBD rows (1 open, 4 resolved) are state-managed, and 15 MOD ledger items share evidence with the corresponding ID rows and are not double-counted. The "Verified" column is the number of IDs whose rows are all PASS or N/A, updated per campaign.
> **Reserved lifecycle / count supplement (2026-08-29)**: Added 13 items already present in the Core spec: CORE-MOD-012/013, 1 SYS, 4 AR, 3 BO, and 3 TM items. Also reflected 5 previously uncounted existing rows (2 AP EVT rows and 1 each of BT INV / SEC / GOV). The current total is **435**: 422 typed IDs + 13 MOD. Existing PASS counts are unchanged.
> **Oracle-recovery and normal-redemption supplements (2026-08-30)**: Appended CORE-MOD-014 and CORE-MOD-015. The typed count remains 422; MOD is 15 and the total is **437**. Focused tests fully pass both MOD deltas, so MOD Verified is 2 and overall Verified is 4. CORE-RH-FR-002/003/ERR-001 have passing #1837 delta evidence but remain PARTIAL because the full base-parity surface was not rerun.

| Scope | FR | INV | SEC | GOV | EVT | ERR | TBD | ID total | Verified |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Cross-cutting (SYS) | - | 15 | - | 4 | - | 5 | - | 24 | 0 |
| Modification ledger (MOD) | - | - | - | - | - | - | - | 15 | 2 |
| BorrowerOperations (BO) | 30 | 5 | 6 | - | 12 | 5 | - | 58 | 0 |
| TroveManager (TM) | 28 | 6 | 8 | - | 8 | 6 | - | 56 | 0 |
| StabilityPool / DFStabilityPool (SP) | 13 | 6 | 5 | - | 13 | 3 | - | 40 | 0 |
| ActivePool (AP) | 15 | 2 | 1 | - | 12 | 1 | 1 | 32 | 0 |
| DefaultPool (DP) | 6 | 1 | 1 | - | 5 | 1 | - | 14 | 0 |
| CollSurplusPool (CSP) | 4 | 1 | 1 | - | 4 | 1 | - | 11 | 0 |
| GasPool (GP) | 1 | - | 1 | - | - | - | - | 2 | 2 |
| SortedTroves (ST) | 10 | 4 | 2 | - | 2 | 1 | - | 19 | 0 |
| TroveNFT (TN) | 6 | 1 | 2 | - | 3 | 1 | 2 | 15 | 0 |
| JpydfToken (BT) | 16 | 4 | 5 | 1 | 10 | 1 | - | 37 | 0 |
| CollateralRegistry (CR) | 9 | 4 | 2 | - | 2 | 1 | - | 18 | 0 |
| AddressesRegistry (AR) | 5 | 3 | 2 | - | 20 | 1 | - | 31 | 0 |
| HintHelpers (HH) | 10 | 1 | 1 | - | - | 1 | - | 13 | 0 |
| MultiTroveGetter (MTG) | 3 | - | 1 | - | - | 1 | - | 5 | 0 |
| DebtInFrontHelper (DFH) | 3 | - | 1 | - | - | 1 | - | 5 | 0 |
| RedemptionHelper (RH) | 5 | 1 | 1 | - | - | 1 | - | 8 | 0 |
| LiquidationCandidateGetter (LCG) | 3 | 1 | - | - | - | 1 | 1 | 6 | 0 |
| Shared foundations (LIB) | 17 | 3 | 1 | - | 4 | 2 | 1 | 28 | 0 |
| **Total (including MOD 15)** | **184** | **58** | **41** | **5** | **95** | **34** | **5** | **437** | **4** |

- There are also 6 non-ID check rows (§4, transcribed from spec §13.3 acceptance criteria).
- Of the 5 TBD rows, CORE-AP-TBD-001 / CORE-TN-TBD-001 / CORE-TN-TBD-002 / CORE-LCG-TBD-001 are resolved; the remaining 1 is outside verification scope as an open gate (see the open issue register in each scope section).

---

## 4. Core Common Checks (Non-ID Rows, spec §13.3 Acceptance Criteria)

Transcribe spec §13.3 acceptance criteria as executable check rows (row 1 is the JPYdf surface guard, row 2 is broad parity, and rows 3-6 are mechanical coverage and consistency checks).

| # | Check item | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Core JPYDF surface guard is green (zero old BOLD public/API names reintroduced) | ci-guard + local run (§1.4 step 3) | ☐ | ☐ | | Not run | Exception path = guard FAIL after dummy forbidden string / forbidden path injection |
| 2 | upstream-derived test suite is all green under DF parameters (zero runtime skips or recorded skip causes) | forge test (full, actual local run) | ☐ | N/A | | Not run | Broad parity evidence for 🔵 rows (§1.3 principle 9) |
| 3 | ABI coverage: every external/public function of every core contract maps to some FR in spec §6 | mechanical cross-check (ABI extraction x spec) | ☐ | N/A | | Not run | |
| 4 | Source diff between DFStabilityPool and StabilityPool contains only the 4 functional differences listed in CORE-MOD-004 (+ contract-name replacement and helper definition) | expected-diff checker (manual review of raw diff until checker exists) | ☐ | ☐ | | Not run | The raw diff exit code becomes 1 when expected differences exist, so do not use it for PASS/FAIL. Exception path = detection of out-of-ledger difference |
| 5 | `MIN_DEBT` matches Core Spec CORE-LIB-FR-002, while `COLL_GAS_COMPENSATION_CAP`, finalized active-branch values, and reserved-branch bootstrap values match [Parameters.md](../../Parameters.md) (CORE-MOD-002/003/005) | unit / deploy verification | ☐ | ☐ | | Not run | Final reserved-branch values are cross-checked separately during the CORE-MOD-013 activation verification |
| 6 | Deploy verification: wiring, risk lifecycle, and authority renounce (live inspection of CORE-SYS-GOV-001/003) | deploy / activation verification (script) | ☐ | ☐ | | Not run | active=`finalizer 0 / finalized true`; reserved=`common Timelock / finalized false`; after activation=`finalized true` |

---

## 5. Verification of the DF Modification Ledger (CORE-MOD)

Source of truth: spec §2.2. Happy path = the difference is implemented as written in the ledger; exception path = the detection mechanism for out-of-ledger differences or incorrect values works (§1.2 MOD rows).

| ID | Difference (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-MOD-001 | JpydfToken `_NAME`/`_SYMBOL` = "JPYdf Stablecoin"/"JPYdf" (debt-token naming surface) | unit (name/symbol and EIP-712 domain name) + ci-guard (line-level inspection) | ☐ | ☐ | | Not run | May share evidence with CORE-BT-FR-010/011 rows |
| CORE-MOD-002 | `MIN_DEBT` = 100_000e18 (base 2000e18) | unit (constant value and openTrove boundary) + [Parameters.md](../../Parameters.md) cross-check | ☐ | ☐ | | Not run | May share evidence with CORE-LIB-FR-002 row |
| CORE-MOD-003 | `COLL_GAS_COMPENSATION_CAP` = 1_000 ether (base 2 ether; 0.5% rate unchanged) | unit (constant value and liquidation compensation cap trigger) | ☐ | ☐ | | Not run | May share evidence with CORE-LIB-FR-003 / CORE-TM-FR-002 rows |
| CORE-MOD-004 | DFStabilityPool = StabilityPool copy + same-block withdrawal guard (4 functional differences) | expected-diff checker (diff after normalizing StabilityPool must exactly equal expected diff) + unit (guard firing) + copy-parity | ☐ | ☐ | | Not run | Treat as manual review until checker exists; do not use raw diff exit code as PASS/FAIL evidence. May share evidence with CORE-SP-FR-004 / CORE-SP-SEC-004 rows |
| CORE-MOD-005 | Adds 48 branch-specific constants to Constants (finalized active-branch values and bootstrap values for reserved-branch deployment) | unit (values x [Parameters.md](../../Parameters.md) cross-check) + static inspection (upstream constants equal base values) | ☐ | ☐ | | Not run | May share evidence with CORE-LIB-FR-004 / CORE-LIB-INV-001 rows. Final reserved-branch values are gated by CORE-MOD-013 / CORE-LIB-TBD-001 |
| CORE-MOD-006 | Rename `withdrawBold` / `repayBold` to `withdrawJpydf` / `repayJpydf` (user-facing ABI) | ABI inspection (old names absent, new names present) + unit (withdraw/repay paths) | ☐ | ☐ | | Not run | May share evidence with CORE-BO-FR-006/007/008 rows |
| CORE-MOD-007 | JPYdf-branded TroveNFT / MetadataNFT deployment variant | deploy verification (`AddressesRegistry.troveNFT` / `metadataNFT` point to JPYdf variants) + unit/snapshot (name/symbol/tokenURI) | ☐ | ☐ | | Not run | May share evidence with CORE-TN-FR-001/002/003/006 rows |
| CORE-MOD-008 | JpydfToken bridge-ready dormant extension | unit (bridgeAdmin / minter registry / bridgeMint / self-burn bridgeBurn) + deploy manifest evidence | ✅ | ✅ | `JpydfTokenTest::test_BridgeReadinessIsDormantAfterCoreSetup`; `JpydfTokenTest::test_BridgeMinterLifecycleUsesTimelockAndSelfBurn`; `JpydfTokenTest::test_BridgeRolesMustBeContractsAndSeparated`; `JpydfTokenTest::test_BridgeReadinessEventsExposeLifecyclePayloads`; `DeployLiquity2StrategySelectorTest::test_ResolveBridgeAdminValidatesConfiguredContract` | PASS(unit) | Final deploy manifest evidence not run. `DF_BRIDGE_ADMIN` resolver zero / deployer / codeless reject done in unit. Linked with CORE-BT-FR-013..016 / CORE-BT-INV-003..004 / CORE-BT-SEC-004..005 / CORE-BT-GOV-001 / CORE-BT-EVT-010 rows |
| CORE-MOD-009 | JpydfToken core address registration hardening (setBranchAddresses / setCollateralRegistry non-zero, contract-only) | unit (zero / codeless reject) + deploy wiring | ✅ | ✅ | `JpydfTokenTest::test_CoreAddressRegistrationRequiresContracts` | PASS(unit) | Final deploy manifest evidence not run. Shares evidence with CORE-BT-FR-002/003 / CORE-BT-SEC-002 / CORE-BT-ERR-001 rows |
| CORE-MOD-010 | ERC-20 transfer / approval hardening (`forceApprove` / `safeTransfer` / `safeTransferFrom`) | unit / integration (zero-first token, failing transfer, WETH gas compensation, redemption refund) + normalized diff | ☐ | ☐ | | Not run | May share evidence with CORE-SYS-INV-007/008 / CORE-RH-SEC-001 / CORE-GP-SEC-001 rows |
| CORE-MOD-011 | ActivePool aggregate accounting events | unit (event emission and argument match immediately after each aggregate state update) + parity (state update formulas base-identical) | ☐ | ☐ | | Not run | May share evidence with CORE-AP-EVT-* / SYS-NFR-005 rows |
| CORE-MOD-012 | Dedicated price consumer for urgent redemption | unit (dedicated path, invalid-price rejection, non-regression of the 3 normal paths) + interface parity | ☐ | ☐ | | Not run | May share evidence with CORE-TM-FR-005 / ORCL-FR-016 rows |
| CORE-MOD-013 | Timelock-only one-shot finalization of reserved-branch risk parameters | unit / invariant (authorization, one-shot property, empty Trove / debt / collateral / SP-deposit state, rejection of SP deposits while unfinalized, shutdown boundary, atomic synchronization) + deploy / activation verification | ☑ | ☑ | `RiskParamsFinalizationTest::test_FinalizerIsAuthorizedAndFinalizationIsOneShot`; `RiskParamsFinalizationTest::test_FinalizationSynchronizesAllSixParams`; `RiskParamsFinalizationTest::test_FinalizationRejectsNonemptyCoreState`; `RiskParamsFinalizationTest::test_UnfinalizedBranchCannotAcceptStabilityPoolDeposit` (2026-08-29) | PARTIAL | Unit evidence exists. Live deploy / activation evidence remains outstanding. Linked to CORE-AR-FR-005, CORE-BO-FR-030, CORE-TM-FR-028, and CORE-SP-FR-002 |
| CORE-MOD-014 | Allow only risk-reducing adjustments against a live normal price during an oracle pause | unit (addColl / repay / combined, rejection of risk increases, unhealthy oracle, irreversible shutdown, batch / manager / Zapper / zombie boundaries) | ☑ | ☑ | `ShutdownTest::testRecoveredOracleAllowsCombinedRiskReducingAdjustmentBeforeResume`; `ShutdownTest::testRecoveredOracleRejectsEveryRiskIncreasingAdjustmentBeforeResume`; `ShutdownTest::testRiskReducingAdjustmentStillRequiresLiveOracle`; `ShutdownTest::testCannotMakeCombinedRiskReducingAdjustmentAfterPermanentShutdown`; `ShutdownTest::testRecoveredOracleAllowsRiskReductionInsideBatchBeforeResume`; `ShutdownTest::testRecoveredOracleDoesNotAllowZombieDebtIncreaseBeforeResume`; `ShutdownTest::testRecoveredOracleAllowsRiskReducingZombieReactivationAfterDebtRecovers`; `CollateralYieldZapperTest::test_RiskReducingManagerAdjustmentWorksAfterOracleRecoveryBeforeResume` (2026-08-30) | PASS(unit) | The only behavior change is in shared `_adjustTrove`; two PriceFeed source comments are synchronized to the new boundary. Owner resume, normal redemption, and liquidation are unchanged. Linked to CORE-BO-FR-003/004/007/008/022 and CORE-BO-ERR-004 |
| CORE-MOD-015 | RedemptionHelper normal-redemption failure-bool parity (exclude failure branches from scanning while retaining the CR denominator; zero-fill the whole estimate on reread failure) | unit / integration (all unavailable, mixed-branch denominator, second-read failure, direct CR / Helper zero spend and full refund) | ✅ | ✅ | `RedemptionHelperOracleFailureTest::test_simulationExcludesRedemptionFailureBeforeComputingProportions`; `RedemptionHelperOracleFailureTest::test_truncateReturnsZeroIfSecondRedemptionReadFails`; `RedemptionHelperTest::test_NormalRedemptionOracleFailure_DirectAndHelperSpendNothing`; `RedemptionHelperTest::test_SimulationKeepsFailedBranchInCollateralRegistryAllocationDenominator`; `RedemptionHelperTest::test_HelperMixedRedemptionRefundsUnavailableBranchShare` | PASS(unit/integration) | C2. The 140 PriceFeedProxy-family and 11 PriceFeedPlaceholder tests also pass, confirming the connection to the failure bool produced by the normal-redemption 30h JPY/USD age/provenance gate. Shares evidence with CORE-RH-FR-002/003/ERR-001 |

---

## 6. Cross-Contract (CORE-SYS)

### 6.1 Invariants (CORE-SYS-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-SYS-INV-001 | Branch debt decomposition identity | invariant / parity | ☐ | ☐ | | Not run | |
| CORE-SYS-INV-002 | Weighted debt-sum consistency | invariant / parity | ☐ | ☐ | | Not run | |
| CORE-SYS-INV-003 | Closure of JPYdf supply paths | parity / audit (complete review of mint/burn call sites) | ☐ | ☐ | | Not run | |
| CORE-SYS-INV-004 | Redemption accounting consistency | parity / unit | ☐ | ☐ | | Not run | |
| CORE-SYS-INV-005 | Collateral conservation rule in liquidation | invariant / parity / unit | ☐ | ☐ | | Not run | |
| CORE-SYS-INV-006 | Redistribution accounting consistency | invariant / parity | ☐ | ☐ | | Not run | |
| CORE-SYS-INV-007 | AP and DP collateral accounting conservation | invariant / parity | ☐ | ☐ | | Not run | |
| CORE-SYS-INV-008 | GasPool WETH consistency | invariant / parity | ☐ | ☐ | | Not run | |
| CORE-SYS-INV-009 | SortedTroves and Trove set consistency | invariant / parity | ☐ | ☐ | | Not run | |
| CORE-SYS-INV-010 | TroveNFT and Trove state consistency | invariant / parity | ☐ | ☐ | | Not run | |
| CORE-SYS-INV-011 | Cross-contract maintenance of MIN_JPYDF_IN_SP | invariant / parity | ☐ | ☐ | | Not run | |
| CORE-SYS-INV-012 | Discipline of MIN_DEBT and zombie Troves | invariant / parity | ☐ | ☐ | | Not run | |
| CORE-SYS-INV-013 | One-time shutdown (BO-TM trust boundary) | parity / unit (double shutdown impossible) | ☐ | ☐ | | Not run | |
| CORE-SYS-INV-014 | troveId sentinel non-collision | parity / unit | ☐ | ☐ | | Not run | |
| CORE-SYS-INV-015 | Atomic risk finalization and agreement among the Registry / BO / TM consumers | unit / invariant (rollback on child-sync failure, rejection of opening / SP deposits while unfinalized, empty-state gate) | ☑ | ☑ | `RiskParamsFinalizationTest::test_FinalizationSynchronizesAllSixParams`; `RiskParamsFinalizationTest::test_ChildSyncFailureRollsBackRegistryAndOtherChild`; `RiskParamsFinalizationTest::test_UnfinalizedBranchCannotOpenTrove`; `RiskParamsFinalizationTest::test_UnfinalizedBranchCannotAcceptStabilityPoolDeposit` (2026-08-29) | PARTIAL | The invariant campaign remains outstanding. Verify TM's 4 internal values other than CCR through block-pinned `eth_getStorageAt` (with compiler storage layout and runtime bytecode attestation) or atomic-sync evidence; do not assume getters exist |

### 6.2 Governance and Operations Requirements (CORE-SYS-GOV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-SYS-GOV-001 | Deploy-time wiring and self-renounce of authority | parity / deploy verification (`owner() == address(0)` equivalent after wiring; each setter reverts) | ☐ | ☐ | | Not run | |
| CORE-SYS-GOV-002 | Non-upgradeability and immutability after parameter finalization | manual (code review: no repeatable setter, one-shot flag) / deploy and activation verification | ☐ | ☐ | | Not run | Active branches are finalized at deployment; reserved branches are finalized once before activation |
| CORE-SYS-GOV-003 | Deploy / reserved-activation gate (mechanical value and lifecycle verification), including 🟡 | deploy / activation verification (script) / manual | ☐ | ☐ | | Not run | |
| CORE-SYS-GOV-004 | Active operations are only incentive-driven permissionless operations | manual (alignment with operations runbook) | ☐ | ☐ | | Not run | |

### 6.3 Failure and Exceptional Behavior (CORE-SYS-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-SYS-ERR-001 | Oracle failure cascade | integration (combined with Oracle layer) / parity | ☐ | ☐ | | Not run | |
| CORE-SYS-ERR-002 | Critical mode (TCR < CCR) | parity / unit (mode matrix) | ☐ | ☐ | | Not run | |
| CORE-SYS-ERR-003 | Branch shutdown (irreversible degradation) | parity / unit (post-shutdown matrix) | ☐ | ☐ | | Not run | |
| CORE-SYS-ERR-004 | Liquidation degradation when SP is depleted | parity / unit (3 branches) | ☐ | ☐ | | Not run | |
| CORE-SYS-ERR-005 | Zombie Trove lifecycle | parity / unit | ☐ | ☐ | | Not run | |


## 7. BorrowerOperations (CORE-BO)

### 7.1 Functional Requirements (CORE-BO-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BO-FR-001 | openTrove (opening a new Trove) | parity / invariant=CORE-BO-INV-002, CORE-BO-INV-005 | ☐ | ☐ | | Not run | |
| CORE-BO-FR-002 | openTroveAndJoinInterestBatchManager (opening while joining a batch) | parity / invariant=CORE-BO-INV-002, CORE-BO-INV-003 | ☐ | ☐ | | Not run | |
| CORE-BO-FR-003 | adjustTrove (combined collateral/debt adjustment and common adjustment path) | parity / invariant=CORE-BO-INV-002 | ☑ | ☑ | `ShutdownTest::testRecoveredOracleAllowsCombinedRiskReducingAdjustmentBeforeResume`; `ShutdownTest::testRecoveredOracleRejectsEveryRiskIncreasingAdjustmentBeforeResume`; `ShutdownTest::testRiskReducingAdjustmentStillRequiresLiveOracle`; `CollateralYieldZapperTest::test_RiskReducingManagerAdjustmentWorksAfterOracleRecoveryBeforeResume` (2026-08-30) | PARTIAL | CORE-MOD-014 oracle-pause delta covered by unit tests; broad parity / invariant remains |
| CORE-BO-FR-004 | addColl (add collateral) | parity | ☑ | ☑ | `ShutdownTest::testRecoveredOracleAllowsAddCollBeforeResume`; `ShutdownTest::testRiskReducingAdjustmentStillRequiresLiveOracle`; `ShutdownTest::testCannotAddCollAfterShutdown` (2026-08-30) | PARTIAL | Oracle-pause / irreversible-shutdown boundary covered |
| CORE-BO-FR-005 | withdrawColl (withdraw collateral) | parity | ☐ | ☐ | | Not run | |
| CORE-BO-FR-006 | withdrawJpydf (additional borrowing) | parity | ☐ | ☐ | | Not run | |
| CORE-BO-FR-007 | repayJpydf (repayment) | parity | ☑ | ☑ | `ShutdownTest::testRecoveredOracleAllowsRepayBeforeResume`; `ShutdownTest::testRiskReducingAdjustmentStillRequiresLiveOracle`; `ShutdownTest::testCannotRepayBoldAfterShutdown` (2026-08-30) | PARTIAL | Oracle-pause / irreversible-shutdown boundary covered |
| CORE-BO-FR-008 | adjustZombieTrove (adjust zombie Trove and return to active) | parity | ☐ | ☑ | `ShutdownTest::testRecoveredOracleDoesNotAllowZombieDebtIncreaseBeforeResume`; `ShutdownTest::testRecoveredOracleAllowsRiskReducingZombieReactivationAfterDebtRecovers` (2026-08-30) | PARTIAL | A zombie below `MIN_DEBT` cannot reactivate without a blocked debt increase; one already restored to `entireDebt >= MIN_DEBT` by interest or redistribution can reactivate through a risk-reducing adjustment |
| CORE-BO-FR-009 | closeTrove (close Trove) | parity / invariant=CORE-BO-INV-002 | ☐ | ☐ | | Not run | |
| CORE-BO-FR-010 | applyPendingDebt (commit interest and redistribution into recorded values) | parity | ☐ | ☐ | | Not run | |
| CORE-BO-FR-011 | adjustTroveInterestRate (change interest rate for an individual Trove) | parity / invariant=CORE-BO-INV-002 | ☐ | ☐ | | Not run | |
| CORE-BO-FR-012 | setInterestIndividualDelegate (set individual interest delegate) | parity / invariant=CORE-BO-INV-002 | ☐ | ☐ | | Not run | |
| CORE-BO-FR-013 | removeInterestIndividualDelegate (remove individual interest delegate) | parity | ☐ | ☐ | | Not run | |
| CORE-BO-FR-014 | registerBatchManager (register batch manager) | parity / invariant=CORE-BO-INV-004 | ☐ | ☐ | | Not run | |
| CORE-BO-FR-015 | setBatchManagerAnnualInterestRate (batch interest-rate change) | parity / invariant=CORE-BO-INV-004 | ☐ | ☐ | | Not run | |
| CORE-BO-FR-016 | lowerBatchManagementFee (lower batch management fee) | parity / invariant=CORE-BO-INV-004 | ☐ | ☐ | | Not run | |
| CORE-BO-FR-017 | setInterestBatchManager (join existing Trove to batch) | parity / invariant=CORE-BO-INV-002, CORE-BO-INV-003 | ☐ | ☐ | | Not run | |
| CORE-BO-FR-018 | removeFromBatch (leave batch) | parity / invariant=CORE-BO-INV-002 | ☐ | ☐ | | Not run | |
| CORE-BO-FR-019 | kickFromBatch (forced removal from batch with degraded shares ratio) | parity | ☐ | ☐ | | Not run | |
| CORE-BO-FR-020 | switchBatchManager (switch batch manager) | parity | ☐ | ☐ | | Not run | |
| CORE-BO-FR-021 | shutdown (branch shutdown when TCR < SCR) | parity / invariant=CORE-BO-INV-001 | ☐ | ☐ | | Not run | |
| CORE-BO-FR-022 | shutdownFromOracleFailure (shutdown due to oracle failure) | parity / invariant=CORE-BO-INV-001 | ☑ | ☑ | `ShutdownTest::testRecoveredOracleAllowsCombinedRiskReducingAdjustmentBeforeResume`; `ShutdownTest::testRecoveredOracleRejectsEveryRiskIncreasingAdjustmentBeforeResume`; `ShutdownTest::testRiskReducingAdjustmentStillRequiresLiveOracle`; `ShutdownTest::testOracleFailureShutdownBlocksLiquidationUntilSourceRecovers` (2026-08-30) | PARTIAL | Confirms live-price carve-out while the pause latch remains set; invariant remains |
| CORE-BO-FR-023 | onLiquidateTrove (BO-side state clearing during liquidation) | parity | ☐ | ☐ | | Not run | |
| CORE-BO-FR-024 | claimCollateral (withdraw liquidation surplus collateral) | parity | ☐ | ☐ | | Not run | |
| CORE-BO-FR-025 | setAddManager (set AddManager) | parity | ☐ | ☐ | | Not run | |
| CORE-BO-FR-026 | setRemoveManagerWithReceiver (set RemoveManager and receiver) | parity / SEC=CORE-BO-SEC-002 | ☐ | ☐ | | Not run | |
| CORE-BO-FR-027 | setRemoveManager (set RemoveManager; receiver is owner) | parity | ☐ | ☐ | | Not run | |
| CORE-BO-FR-028 | View function group | parity | ☐ | ☐ | | Not run | |
| CORE-BO-FR-029 | constructor (deploy-time wiring and initialization) | parity / deploy verification | ☐ | ☐ | | Not run | |
| CORE-BO-FR-030 | syncRiskParams (one-shot synchronization of CCR / MCR / BCR / SCR from the Registry) | unit (caller restriction, synchronization of 4 values, atomic rollback) | ☐ | ☐ | | Not run | |

### 7.2 Invariants (CORE-BO-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BO-INV-001 | `hasBeenShutDown` is monotonic (false -> true only once; transition paths are `shutdown()` and `shutdownFromOracleFailur...`) | invariant | ☐ | ☐ | | Not run | |
| CORE-BO-INV-002 | For any Trove, `interestIndividualDelegateOf[t].account != 0` and `interestBatchManagerOf[t] != 0` cannot both hold | invariant | ☐ | ☐ | | Not run | |
| CORE-BO-INV-003 | If `interestBatchManagerOf[t] != 0`, that address is a registered batch manager (`interestBatchManagers[m].maxInte...`) | invariant | ☐ | ☐ | | Not run | |
| CORE-BO-INV-004 | Registered batch manager record `(minInterestRate, maxInterestRate, minInterestRateChangePeriod)` is immutable after registration | invariant | ☐ | ☐ | | Not run | |
| CORE-BO-INV-005 | Wiring (troveManager / gasPoolAddress / collSurplusPool / jpydfToken / sortedTroves / collToken / WETH...) | invariant / deploy verification | ☐ | ☐ | | Not run | |

### 7.3 Security Requirements (CORE-BO-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BO-SEC-001 | Closure of Trove operation authorization model | parity / unit (authorization matrix) | ☐ | ☐ | | Not run | |
| CORE-BO-SEC-002 | Constraints on receiver redirection | parity / unit | ☐ | ☐ | | Not run | |
| CORE-BO-SEC-003 | Caller restriction for internal hooks | parity / unit | ☐ | ☐ | | Not run | |
| CORE-BO-SEC-004 | Slippage defense for upfront fee | parity / unit | ☐ | ☐ | | Not run | |
| CORE-BO-SEC-005 | State-condition gates for permissionless operations | parity / unit | ☐ | ☐ | | Not run | |
| CORE-BO-SEC-006 | Registry-only risk synchronization and blocking Trove opening on an unfinalized branch | unit (caller restriction and pre-state guard on both open entrypoints) | ☐ | ☐ | | Not run | |

### 7.4 Event and Monitoring Requirements (CORE-BO-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BO-EVT-001 | `TroveManagerAddressChanged` (fires: constructor) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BO-EVT-002 | `GasPoolAddressChanged` (fires: constructor) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BO-EVT-003 | `CollSurplusPoolAddressChanged` (fires: constructor) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BO-EVT-004 | `SortedTrovesAddressChanged` (fires: constructor) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BO-EVT-005 | `JpydfTokenAddressChanged` (fires: constructor) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BO-EVT-006 | `ShutDown` (fires: `shutdown()` only on TCR < SCR path; does not fire on oracle-failure path) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BO-EVT-007 | `TroveNFTAddressChanged` (fires: constructor (AddRemoveManagers)) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BO-EVT-008 | `AddManagerUpdated` (fires: `setAddManager` / `openTrove` family (always fires) / `closeTro...`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BO-EVT-009 | `RemoveManagerAndReceiverUpdated` (fires: `setRemoveManager(WithReceiver)` / `openTrove` family...) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BO-EVT-010 | `ActivePoolAddressChanged` (fires: constructor (LiquityBase)) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BO-EVT-011 | `DefaultPoolAddressChanged` (fires: constructor (LiquityBase)) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BO-EVT-012 | `PriceFeedAddressChanged` (fires: constructor (LiquityBase)) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 7.5 Failure and Exceptional Behavior (CORE-BO-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BO-ERR-001 | Adjustment restrictions when TCR < CCR (below critical threshold) | parity / unit (per-mode matrix) | ☐ | ☐ | | Not run | |
| CORE-BO-ERR-002 | Silent cap on repayment amount | parity / unit | ☐ | ☐ | | Not run | |
| CORE-BO-ERR-003 | Function availability after shutdown | parity / unit (post-shutdown matrix) | ☐ | ☐ | | Not run | |
| CORE-BO-ERR-004 | Behavior on oracle failure | parity / unit | ☑ | ☑ | `ShutdownTest::testRecoveredOracleAllowsAddCollBeforeResume`; `ShutdownTest::testRecoveredOracleAllowsRepayBeforeResume`; `ShutdownTest::testRecoveredOracleRejectsEveryRiskIncreasingAdjustmentBeforeResume`; `ShutdownTest::testRiskReducingAdjustmentStillRequiresLiveOracle`; `ShutdownTest::testCannotMakeCombinedRiskReducingAdjustmentAfterPermanentShutdown` (2026-08-30) | PASS(unit) | CORE-MOD-014 allow/reject/live-oracle boundary |
| CORE-BO-ERR-005 | Rejection under the reserved-risk lifecycle (open while unfinalized / invalid sync caller) | unit | ☐ | ☐ | | Not run | |


## 8. TroveManager (CORE-TM)

### 8.1 Functional Requirements (CORE-TM-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TM-FR-001 | batchLiquidateTroves (liquidation sequence) | parity / invariant=CORE-TM-INV-001, CORE-TM-INV-002 | ☐ | ☐ | | Not run | |
| CORE-TM-FR-002 | Single Trove liquidation and liquidation-value distribution (SP offset / redistribution / gas compensation / surplus collateral) | parity / unit (3 branches, cap boundary, surplus intrusion) | ☐ | ☐ | | Not run | |
| CORE-TM-FR-003 | Redistribution accounting (L_coll / L_jpydfDebt, error feedback, stake rules) | parity / invariant=CORE-TM-INV-002, CORE-TM-INV-006 | ☐ | ☐ | | Not run | |
| CORE-TM-FR-004 | redeemCollateral (normal redemption) | parity / unit (zombie transition, fee retention, batch path) / invariant=CORE-TM-INV-005 | ☐ | ☐ | | Not run | |
| CORE-TM-FR-005 | urgentRedemption (emergency redemption after shutdown) | parity / unit (collateral truncation branch, _minCollateral boundary) | ☐ | ☐ | | Not run | |
| CORE-TM-FR-006 | shutdown (record branch shutdown) | parity / unit (onlyBO) | ☐ | ☐ | | Not run | |
| CORE-TM-FR-007 | Determination of interest accrual period (freeze by shutdown) | parity / unit (3 branches) | ☐ | ☐ | | Not run | |
| CORE-TM-FR-008 | getCurrentICR (calculate current ICR) | parity | ☐ | ☐ | | Not run | |
| CORE-TM-FR-009 | getLatestTroveData (derive latest Trove state) | parity / unit (batch apportionment, individual attribution of redistribution) | ☐ | ☐ | | Not run | |
| CORE-TM-FR-010 | getLatestBatchData (derive latest Batch state) | parity | ☐ | ☐ | | Not run | |
| CORE-TM-FR-011 | getTroveAnnualInterestRate (resolve effective annual rate) | parity | ☐ | ☐ | | Not run | |
| CORE-TM-FR-012 | getUnbackedPortionPriceAndRedeemability (unbacked debt and redeemability) | parity / unit (redeemable boundary) | ☐ | ☐ | | Not run | |
| CORE-TM-FR-013 | Trivial view getter group | parity | ☐ | ☐ | | Not run | |
| CORE-TM-FR-014 | onOpenTrove (record Trove opening) | parity | ☐ | ☐ | | Not run | |
| CORE-TM-FR-015 | onOpenTroveAndJoinBatch (opening with batch join) | parity | ☐ | ☐ | | Not run | |
| CORE-TM-FR-016 | setTroveStatusToActive (return from zombie) | parity | ☐ | ☐ | | Not run | |
| CORE-TM-FR-017 | onAdjustTrove (record Trove adjustment) | parity | ☐ | ☐ | | Not run | |
| CORE-TM-FR-018 | onAdjustTroveInterestRate (record individual rate change) | parity | ☐ | ☐ | | Not run | |
| CORE-TM-FR-019 | onAdjustTroveInsideBatch (record Trove adjustment inside batch) | parity | ☐ | ☐ | | Not run | |
| CORE-TM-FR-020 | onApplyTroveInterest (record application of interest and redistribution) | parity | ☐ | ☐ | | Not run | |
| CORE-TM-FR-021 | onCloseTrove (record Trove closure) | parity / invariant=CORE-TM-INV-001, CORE-TM-INV-003 | ☐ | ☐ | | Not run | |
| CORE-TM-FR-022 | onRegisterBatchManager (register batch manager) | parity | ☐ | ☐ | | Not run | |
| CORE-TM-FR-023 | onLowerBatchManagerAnnualFee (lower batch management fee) | parity | ☐ | ☐ | | Not run | |
| CORE-TM-FR-024 | onSetBatchManagerAnnualInterestRate (batch rate change) | parity | ☐ | ☐ | | Not run | |
| CORE-TM-FR-025 | onSetInterestBatchManager (join existing Trove to batch) | parity | ☐ | ☐ | | Not run | |
| CORE-TM-FR-026 | onRemoveFromBatch (Trove leaves batch) | parity / invariant=CORE-TM-INV-004 | ☐ | ☐ | | Not run | |
| CORE-TM-FR-027 | Update rules for batch debt shares (`_updateBatchShares`) | parity / unit (initial issuance, full redemption, ratio boundary) / invariant=CORE-TM-INV-004 | ☐ | ☐ | | Not run | |
| CORE-TM-FR-028 | syncRiskParams (one-shot synchronization of CCR / MCR / SCR / 2 liquidation penalties from the Registry) | unit (caller restriction, synchronization of 5 values, atomic rollback) | ☐ | ☐ | | Not run | |

### 8.2 Invariants (CORE-TM-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TM-INV-001 | totalStakes consistency | invariant / parity | ☐ | ☐ | | Not run | |
| CORE-TM-INV-002 | Monotonicity of L values | invariant | ☐ | ☐ | | Not run | |
| CORE-TM-INV-003 | TroveIds / arrayIndex consistency | invariant | ☐ | ☐ | | Not run | |
| CORE-TM-INV-004 | Batch shares accounting consistency | invariant | ☐ | ☐ | | Not run | |
| CORE-TM-INV-005 | lastZombieTroveId consistency | invariant (normal operation) / unit (post-shutdown exception) | ☐ | ☐ | | Not run | |
| CORE-TM-INV-006 | Bounded redistribution error | invariant / unit | ☐ | ☐ | | Not run | |

### 8.3 Security Requirements (CORE-TM-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TM-SEC-001 | on* callbacks are restricted to BorrowerOperations | unit (caller check for all functions) / parity | ☐ | ☐ | | Not run | |
| CORE-TM-SEC-002 | redeemCollateral is restricted to CollateralRegistry | unit / parity | ☐ | ☐ | | Not run | |
| CORE-TM-SEC-003 | Liquidation condition restriction | parity / unit | ☐ | ☐ | | Not run | |
| CORE-TM-SEC-004 | Prevention of CR worsening by redemption | parity / unit | ☐ | ☐ | | Not run | |
| CORE-TM-SEC-005 | Redemption griefing resistance by zombie mechanism | parity / unit | ☐ | ☐ | | Not run | |
| CORE-TM-SEC-006 | Batch shares dilution/rebase attack resistance and redemption non-blocking | unit | ☐ | ☐ | | Not run | |
| CORE-TM-SEC-007 | Shutdown one-time property depends on BorrowerOperations | parity (double shutdown impossible through BO) | ☐ | ☐ | | Not run | |
| CORE-TM-SEC-008 | Registry-only risk synchronization | unit (invalid-caller rejection and value agreement within the finalization transaction) | ☐ | ☐ | | Not run | |

### 8.4 Event and Monitoring Requirements (CORE-TM-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TM-EVT-001 | `Liquidation` (fires: `batchLiquidateTroves` once per call) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-TM-EVT-002 | `Redemption` (fires: `redeemCollateral` / `urgentRedemption` once per call) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-TM-EVT-003 | `TroveUpdated` (fires: all Trove state changes, including non-batch adjustments and rate changes; even when in batch, `onAp...`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-TM-EVT-004 | `TroveOperation` (fires: all operations on Troves) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-TM-EVT-005 | `RedemptionFeePaidToTrove` (fires: `_applySingleRedemption`, per Trove) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-TM-EVT-006 | `BatchUpdated` (fires: all batch-related operations) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-TM-EVT-007 | `BatchedTroveUpdated` (fires: state changes for Troves in batch) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-TM-EVT-008 | Address wiring event group: `TroveNFTAddressChanged` / `BorrowerOperationsA...` (fires: constructor only, once) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 8.5 Failure and Exceptional Behavior (CORE-TM-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TM-ERR-001 | Failure behavior of batchLiquidateTroves | unit | ☐ | ☐ | | Not run | |
| CORE-TM-ERR-002 | redeemCollateral succeeds even with zero redemption | parity / unit | ☐ | ☐ | | Not run | |
| CORE-TM-ERR-003 | Failure behavior of urgentRedemption | unit | ☐ | ☐ | | Not run | |
| CORE-TM-ERR-004 | Closing the last remaining Trove is prohibited | parity / unit | ☐ | ☐ | | Not run | |
| CORE-TM-ERR-005 | BatchSharesRatioTooHigh | unit | ☐ | ☐ | | Not run | |
| CORE-TM-ERR-006 | Invalid caller for risk synchronization | unit | ☐ | ☐ | | Not run | |


## 9. StabilityPool / DFStabilityPool (CORE-SP)

### 9.1 Functional Requirements (CORE-SP-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-SP-FR-001 | constructor (wiring from AddressesRegistry) | parity (identical wiring and initial values) | ☐ | ☐ | | Not run | |
| CORE-SP-FR-002 | provideToSP (JPYdf deposit/top-up with simultaneous gain settlement) 🔵/🟡 | parity / unit (`_doClaim` branches, kept-yield compounding, pending transfer, new/top-up paths, rejection on an unfinalized branch, passage on a finalized branch) / invariant=CORE-SP-INV-003, CORE-SP-INV-005, CORE-SP-INV-006 | ☑ | ☑ | `SPTest::testJpydfRewardsPendingDistributesWhenDepositReachesMinPoolSize` (2026-06-21); `RiskParamsFinalizationTest::test_UnfinalizedBranchCannotAcceptStabilityPoolDeposit`; `RiskParamsFinalizationTest::test_FinalizedBranchPassesStabilityPoolLifecycleGuard` (2026-08-29) | PARTIAL | A new deposit on an unfinalized branch is rejected before any state change; an actual deposit succeeds after finalization. Full `_doClaim` branch and snapshot-lifecycle coverage remains outstanding |
| CORE-SP-FR-003 | withdrawFromSP (JPYdf withdrawal with simultaneous gain settlement) | parity / unit (`min` truncation, `_amount=0` settlement, `MIN_JPYDF_IN_SP` boundary, snapshot delete when `newDeposit==0`) / invariant=CORE-SP-INV-002, CORE-SP-INV-003, CORE-SP-INV-006 | ☐ | ☐ | | Not run | |
| CORE-SP-FR-004 | lastDepositBlock (same-block withdrawal guard) 🟡 | unit (same-block revert, next-block success, block update on top-up, `claimAllCollGains` unaffected) / copy-parity (DFStabilityPool behavior is identical to StabilityPool except this guard) | ☐ | ☐ | | Not run | |
| CORE-SP-FR-005 | claimAllCollGains (claim stashed collateral for zero-deposit user) | parity / unit (revert when deposit exists, revert when stash is zero, payout and stash clear) | ☐ | ☐ | | Not run | |
| CORE-SP-FR-006 | triggerJpydfRewards (account interest-yield distribution) | parity / unit (pending accumulation below threshold, batch transfer at/above threshold, early return for zero yield) / invariant=CORE-SP-INV-003, CORE-SP-INV-005 | ☐ | ☐ | | Not run | |
| CORE-SP-FR-007 | offset (liquidation offset: P/S update, debt burn, collateral receipt) | parity / unit (single and multi-scale crossing, `newP > 0` boundary, S then P update order, rounding direction) / invariant=CORE-SP-INV-001-004 | ☐ | ☐ | | Not run | |
| CORE-SP-FR-008 | getDepositorCollGain (calculate unsettled collateral gain) | parity / unit (same scale, 1/2-scale crossing, cutoff beyond SPAN, clamp trigger) | ☐ | ☐ | | Not run | |
| CORE-SP-FR-009 | getDepositorYieldGain (calculate unsettled yield gain) | parity / unit (scale crossing, clamp, pending excluded) | ☐ | ☐ | | Not run | |
| CORE-SP-FR-010 | getDepositorYieldGainWithPending (yield estimate including pending interest) | parity / unit (0 below threshold, inside/outside SPAN branches, consistency immediately after `triggerJpydfRewards`) | ☐ | ☐ | | Not run | |
| CORE-SP-FR-011 | getCompoundedJpydfDeposit (calculate compounded deposit) | parity / unit (scale difference 0-8, 0 at 9 or more, floor-division direction) | ☐ | ☐ | | Not run | |
| CORE-SP-FR-012 | Trivial view function group (trackers, constants, wiring getters) | parity | ☐ | ☐ | | Not run | |
| CORE-SP-FR-013 | getEntireBranchColl / getEntireBranchDebt (LiquityBase inherited view) | parity | ☐ | ☐ | | Not run | |

### 9.2 Invariants (CORE-SP-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-SP-INV-001 | P range and nonzero property | invariant / parity | ☐ | ☐ | | Not run | |
| CORE-SP-INV-002 | Monotonic maintenance of MIN_JPYDF_IN_SP | invariant (SYS) | ☐ | ☐ | | Not run | |
| CORE-SP-INV-003 | JPYdf accounting identity | invariant / parity | ☐ | ☐ | | Not run | |
| CORE-SP-INV-004 | Collateral accounting consistency | invariant | ☐ | ☐ | | Not run | |
| CORE-SP-INV-005 | Mutual exclusion of pending and threshold | invariant / unit | ☐ | ☐ | | Not run | |
| CORE-SP-INV-006 | Lifecycle consistency of deposits and snapshots | invariant / unit | ☐ | ☐ | | Not run | |

### 9.3 Security Requirements (CORE-SP-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-SP-SEC-001 | Caller restriction for offset | unit (revert on non-TM call) / parity | ☐ | ☐ | | Not run | |
| CORE-SP-SEC-002 | Caller restriction for triggerJpydfRewards | unit / parity | ☐ | ☐ | | Not run | |
| CORE-SP-SEC-003 | Donation resistance through internal trackers | unit (each view unchanged after direct transfer) | ☐ | ☐ | | Not run | |
| CORE-SP-SEC-004 | Prevention of liquidation-gain capture by same-block flash deposit 🟡 | unit (same-block revert, next-block success, flash-loan path impossible) | ☐ | ☐ | | Not run | |
| CORE-SP-SEC-005 | External-call surface and reentrancy considerations | parity / design review (state dependency on dToken-side specification) | ☐ | ☐ | | Not run | |

### 9.4 Event and Monitoring Requirements (CORE-SP-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-SP-EVT-001 | `DepositOperation` (fires: provideToSP / withdrawFromSP / claimAllCollGains) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-SP-EVT-002 | `DepositUpdated` (fires: _updateDepositAndSnapshots (provideToSP / withdra...)) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-SP-EVT-003 | `StabilityPoolJpydfBalanceUpdated` (fires: _updateTotalJpydfDeposits (provideToSP / withdrawF...)) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-SP-EVT-004 | `StabilityPoolCollBalanceUpdated` (fires: _moveOffsetCollAndDebt (offset) / _sendCollGainToD...) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-SP-EVT-005 | `P_Updated` (fires: offset) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-SP-EVT-006 | `S_Updated` (fires: offset) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-SP-EVT-007 | `B_Updated` (fires: _updateYieldRewardsSum (triggerJpydfRewards / prov...)) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-SP-EVT-008 | `ScaleUpdated` (fires: offset, inside scale loop, on each carry) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-SP-EVT-009 | `TroveManagerAddressChanged` (fires: constructor) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-SP-EVT-010 | `JpydfTokenAddressChanged` (fires: constructor) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-SP-EVT-011 | `ActivePoolAddressChanged` (fires: constructor (LiquityBase)) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-SP-EVT-012 | `DefaultPoolAddressChanged` (fires: constructor (LiquityBase)) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-SP-EVT-013 | `PriceFeedAddressChanged` (fires: constructor (LiquityBase)) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 9.5 Failure and Exceptional Behavior (CORE-SP-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-SP-ERR-001 | Revert catalog for depositor operations 🔵/🟡 | unit / parity | ☐ | ☑ | `RiskParamsFinalizationTest::test_UnfinalizedBranchCannotAcceptStabilityPoolDeposit` (2026-08-29) | PARTIAL | Confirmed `RiskParamsNotFinalized()` when `riskParamsFinalized == false` on both StabilityPool and DFStabilityPool. Existing string-revert cases remain outstanding |
| CORE-SP-ERR-002 | Revert on same-block withdrawal 🟡 | unit | ☐ | ☐ | | Not run | |
| CORE-SP-ERR-003 | Behavior when privileged-function preconditions are violated | unit (boundary calls) / parity | ☐ | ☐ | | Not run | |


## 10. ActivePool (CORE-AP)

### 10.1 Functional Requirements (CORE-AP-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AP-FR-001 | constructor (address wiring and collateral approve to DefaultPool) | parity / deployment test (wiring and approve value) | ☐ | ☐ | | Not run | |
| CORE-AP-FR-002 | calcPendingAggInterest (calculate aggregate pending interest) | parity / basis of invariant=CORE-SYS-INV-001 | ☐ | ☐ | | Not run | |
| CORE-AP-FR-003 | calcPendingSPYield (SP share of pending interest) | parity | ☐ | ☐ | | Not run | |
| CORE-AP-FR-004 | calcPendingAggBatchManagementFee (calculate aggregate pending batch management fee) | parity / unit (before/after shutdown, boundary where lastUpdate > shutdownTime) | ☐ | ☐ | | Not run | |
| CORE-AP-FR-005 | getNewApproxAvgInterestRateFromTroveChange (approximate average rate after applying Trove change) | parity / unit (0 at shutdown, denominator 0, approximation formula) | ☐ | ☐ | | Not run | |
| CORE-AP-FR-006 | getJpydfDebt (total active debt) | parity / basis of invariant=CORE-SYS-INV-001 | ☐ | ☐ | | Not run | |
| CORE-AP-FR-007 | mintAggInterest (commit aggregate interest mint and 75/25 distribution) | parity / unit (distribution dust, spYield=0 boundary, lastAggUpdateTime update) | ☐ | ☐ | | Not run | |
| CORE-AP-FR-008 | mintAggInterestAndAccountForTroveChange (mint interest + reflect Trove change in aggregates) | parity / invariant=CORE-SYS-INV-001 | ☐ | ☐ | | Not run | |
| CORE-AP-FR-009 | mintBatchManagementFeeAndAccountForChange (commit batch management fee mint and reflect aggregate change) | parity / unit (reassignment of applied portion, minted amount) | ☐ | ☐ | | Not run | |
| CORE-AP-FR-010 | sendColl (external collateral send) | parity / invariant=CORE-AP-INV-001 | ☐ | ☐ | | Not run | |
| CORE-AP-FR-011 | sendCollToDefaultPool (move redistribution collateral to DefaultPool) | parity / invariant=CORE-AP-INV-001 / CORE-SYS-INV-007 | ☐ | ☐ | | Not run | |
| CORE-AP-FR-012 | receiveColl (collateral receipt: accounting add + pull) | parity / invariant=CORE-AP-INV-001 | ☐ | ☐ | | Not run | |
| CORE-AP-FR-013 | accountForReceivedColl (account for directly sent collateral) | parity / invariant=CORE-AP-INV-001 | ☐ | ☐ | | Not run | |
| CORE-AP-FR-014 | setShutdownFlag (record shutdown time and permanently stop interest accumulation) | parity / unit (0 interest after shutdown, batch-fee cutoff) | ☐ | ☐ | | Not run | |
| CORE-AP-FR-015 | Trivial view function group | parity | ☐ | ☐ | | Not run | |

### 10.2 Invariants (CORE-AP-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AP-INV-001 | Accounting balance does not exceed actual balance | invariant / parity | ☐ | ☐ | | Not run | |
| CORE-AP-INV-002 | Interest freeze after shutdown | unit / invariant | ☐ | ☐ | | Not run | |

### 10.3 Security Requirements (CORE-AP-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AP-SEC-001 | Caller restriction on state-changing surface | unit (all unauthorized callers revert) / parity | ☐ | ☐ | | Not run | |

### 10.4 Event and Monitoring Requirements (CORE-AP-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AP-EVT-001 | `CollTokenAddressChanged` (fires: constructor only) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AP-EVT-002 | `BorrowerOperationsAddressChanged` (fires: constructor only) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AP-EVT-003 | `TroveManagerAddressChanged` (fires: constructor only) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AP-EVT-004 | `DefaultPoolAddressChanged` (fires: constructor only) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AP-EVT-005 | `StabilityPoolAddressChanged` (fires: constructor only) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AP-EVT-007 | `ActivePoolCollBalanceUpdated` (fires: `_accountForSendColl` / `_accountForReceivedColl...`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AP-EVT-008 | `ActivePoolAggRecordedDebtUpdated` (fires: `mintAggInterestAndAccountForTroveChange` / `mintAggInterest` / batch fee accounting) | unit / monitoring (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AP-EVT-009 | `ActivePoolAggWeightedDebtSumUpdated` (fires: `mintAggInterestAndAccountForTroveChange`) | unit / monitoring (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AP-EVT-010 | `ActivePoolAggBatchManagementFeesUpdated` (fires: batch fee accounting) | unit / monitoring (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AP-EVT-011 | `ActivePoolAggWeightedBatchManagementFeeSumUpdated` (fires: batch fee accounting) | unit / monitoring (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AP-EVT-012 | `AggregateInterestMinted` (fires: aggregate interest/upfront fee mint; primary DeFiLlama fee/revenue evidence) | unit / monitoring (ledger-defined) | ✅ | N/A | `InterestRateAggregate::testOpenTroveEmitsAggregateInterestMintedForDefiLlamaAccounting` | PASS | 2026-06-25 focused: `forge test --match-contract InterestRateAggregate --match-test testOpenTroveEmitsAggregateInterestMintedForDefiLlamaAccounting -vvv` |
| CORE-AP-EVT-013 | `BatchManagementFeeMinted` (fires: batch management fee mint; primary batch manager fee evidence) | unit / monitoring (ledger-defined) | ✅ | N/A | `BatchManagementFeeTest::testAdjustTroveEmitsBatchManagementFeeMintedForDefiLlamaAccounting` | PASS | 2026-06-25 focused: `forge test --match-contract BatchManagementFeeTest --match-test testAdjustTroveEmitsBatchManagementFeeMintedForDefiLlamaAccounting -vvv` |

### 10.5 Failure and Exceptional Behavior (CORE-AP-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AP-ERR-001 | Failure behavior (require strings and arithmetic reverts) | unit / parity | ☐ | ☐ | | Not run | |

### 10.6 Open Issue Register (CORE-AP-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| CORE-AP-TBD-001 | Resolved | In complete deploys, `InterestRouterForwarder` is bound to `interestRouter`, and recipient / owner are managed via env and handover/verify. The V2-gov / direct Governance-address fallback is removed from the Day-1 deploy path | Verified in CORE-AP-FR-007/008 and `InterestRouterForwarder` rows |


## 11. DefaultPool (CORE-DP)

### 11.1 Functional Requirements (CORE-DP-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-DP-FR-001 | constructor (address wiring and collateral approve to ActivePool) | parity / deployment test | ☐ | ☐ | | Not run | |
| CORE-DP-FR-002 | sendCollToActivePool (return pending collateral to ActivePool) | parity / invariant=CORE-DP-INV-001 | ☐ | ☐ | | Not run | |
| CORE-DP-FR-003 | receiveColl (receive redistribution collateral) | parity / invariant=CORE-DP-INV-001 | ☐ | ☐ | | Not run | |
| CORE-DP-FR-004 | increaseJpydfDebt (record redistribution debt) | parity / invariant=CORE-SYS-INV-001 | ☐ | ☐ | | Not run | |
| CORE-DP-FR-005 | decreaseJpydfDebt (draw down applied debt) | parity | ☐ | ☐ | | Not run | |
| CORE-DP-FR-006 | Trivial view function group | parity | ☐ | ☐ | | Not run | |

### 11.2 Invariants (CORE-DP-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-DP-INV-001 | Accounting balance does not exceed actual balance | invariant / parity | ☐ | ☐ | | Not run | |

### 11.3 Security Requirements (CORE-DP-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-DP-SEC-001 | Caller restriction on write surface | unit (unauthorized caller reverts) / parity | ☐ | ☐ | | Not run | |

### 11.4 Event and Monitoring Requirements (CORE-DP-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-DP-EVT-001 | `CollTokenAddressChanged` (fires: constructor only) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-DP-EVT-002 | `ActivePoolAddressChanged` (fires: constructor only) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-DP-EVT-003 | `TroveManagerAddressChanged` (fires: constructor only) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-DP-EVT-004 | `DefaultPoolJpydfDebtUpdated` (fires: increaseJpydfDebt / decreaseJpydfDebt) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-DP-EVT-005 | `DefaultPoolCollBalanceUpdated` (fires: sendCollToActivePool / receiveColl) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 11.5 Failure and Exceptional Behavior (CORE-DP-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-DP-ERR-001 | Failure behavior | unit / parity | ☐ | ☐ | | Not run | |


## 12. CollSurplusPool (CORE-CSP)

### 12.1 Functional Requirements (CORE-CSP-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CSP-FR-001 | constructor (address wiring) | parity / deployment test | ☐ | ☐ | | Not run | |
| CORE-CSP-FR-002 | accountSurplus (record liquidation surplus) | parity / invariant=CORE-CSP-INV-001 | ☐ | ☐ | | Not run | |
| CORE-CSP-FR-003 | claimColl (claim and pay surplus collateral) | parity / unit (zero-balance revert, full payout, repeat-claim revert) | ☐ | ☐ | | Not run | |
| CORE-CSP-FR-004 | Trivial view function group | parity | ☐ | ☐ | | Not run | |

### 12.2 Invariants (CORE-CSP-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CSP-INV-001 | Accounting consistency | invariant / parity | ☐ | ☐ | | Not run | |

### 12.3 Security Requirements (CORE-CSP-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CSP-SEC-001 | Claim right restricted to the claimant | unit (unauthorized caller reverts) / parity | ☐ | ☐ | | Not run | |

### 12.4 Event and Monitoring Requirements (CORE-CSP-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CSP-EVT-001 | `BorrowerOperationsAddressChanged` (fires: constructor only) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-CSP-EVT-002 | `TroveManagerAddressChanged` (fires: constructor only) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-CSP-EVT-003 | `CollBalanceUpdated` (fires: accountSurplus (on record) / claimColl (on zeroing)) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-CSP-EVT-004 | `CollSent` (fires: claimColl) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 12.5 Failure and Exceptional Behavior (CORE-CSP-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CSP-ERR-001 | Failure behavior | unit / parity | ☐ | ☐ | | Not run | |


## 13. GasPool (CORE-GP)

### 13.1 Functional Requirements (CORE-GP-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-GP-FR-001 | constructor (infinite WETH approve to BO and TM) | parity / deployment test (approve value = type(uint256).max is set for both BO and TM) | ☐ | ☐ | | Not run | |

### 13.2 Security Requirements (CORE-GP-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-GP-SEC-001 | Zero attack surface and validity of approve | unit (ABI is empty and approve targets are verified) / parity | ☐ | ☐ | | Not run | |


## 14. SortedTroves (CORE-ST)

### 14.1 Functional Requirements (CORE-ST-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-ST-FR-001 | constructor (address binding and sentinel-node initialization) | parity / deployment test | ☐ | ☐ | | Not run | |
| CORE-ST-FR-002 | insert (insert non-batch node) | parity, invariant=CORE-ST-INV-001 / CORE-ST-INV-002 / CORE-ST-INV-004 | ☐ | ☐ | | Not run | |
| CORE-ST-FR-003 | remove (remove non-batch node) | parity, invariant=CORE-ST-INV-002 / CORE-ST-INV-004 | ☐ | ☐ | | Not run | |
| CORE-ST-FR-004 | reInsert (reinsert non-batch node after rate change) | parity, invariant=CORE-ST-INV-001 / CORE-ST-INV-002 | ☐ | ☐ | | Not run | |
| CORE-ST-FR-005 | insertIntoBatch (add node to batch) | parity, invariant=CORE-ST-INV-001 / CORE-ST-INV-003 / CORE-ST-INV-004 | ☐ | ☐ | | Not run | |
| CORE-ST-FR-006 | removeFromBatch (remove batch node) | parity, invariant=CORE-ST-INV-002 / CORE-ST-INV-003 / CORE-ST-INV-004 | ☐ | ☐ | | Not run | |
| CORE-ST-FR-007 | reInsertBatch (reinsert entire batch slice) | parity, invariant=CORE-ST-INV-001 / CORE-ST-INV-003 | ☐ | ☐ | | Not run | |
| CORE-ST-FR-008 | validInsertPosition (validate hint position) | parity, unit (boundaries: empty list, head, tail, same rate, batch boundary) | ☐ | ☐ | | Not run | |
| CORE-ST-FR-009 | findInsertPosition (search insertion position and hint fallback) | parity, unit (4 invalid-hint branches and convergence of bidirectional search), fuzz (result position is always valid for arbitrary hint) | ☐ | ☐ | | Not run | |
| CORE-ST-FR-010 | Listing view functions and automatic getter group | parity | ☐ | ☐ | | Not run | |

### 14.2 Invariants (CORE-ST-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-ST-INV-001 | Descending rate ordering | invariant / parity (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-ST-INV-002 | Doubly-linked list, sentinel, and size consistency | invariant / parity (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-ST-INV-003 | Batch slice continuity | invariant / parity (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-ST-INV-004 | Consistency of exists and node state | invariant / parity (ledger-defined) | ☐ | ☐ | | Not run | |

### 14.3 Security Requirements (CORE-ST-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-ST-SEC-001 | Write authority restriction and trusted delegation for node existence | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-ST-SEC-002 | Hint-independent soundness (hint griefing resistance) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 14.4 Event and Monitoring Requirements (CORE-ST-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-ST-EVT-001 | `TroveManagerAddressChanged` (fires: constructor only, once) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-ST-EVT-002 | `BorrowerOperationsAddressChanged` (fires: constructor only, once) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 14.5 Failure and Exceptional Behavior (CORE-ST-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-ST-ERR-001 | Revert string catalog | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |


## 15. TroveNFT (CORE-TN)

### 15.1 Functional Requirements (CORE-TN-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TN-FR-001 | constructor (derive name/symbol and bind addresses) | parity / deployment test | ☐ | ☐ | | Not run | |
| CORE-TN-FR-002 | mint (issue NFT on Trove opening) | parity, unit (TM-only, no double mint) | ☐ | ☐ | | Not run | |
| CORE-TN-FR-003 | burn (burn NFT on Trove close/liquidation) | parity, unit (TM-only, nonexistent burn reverts) | ☐ | ☐ | | Not run | |
| CORE-TN-FR-004 | tokenURI (on-chain metadata delegated to MetadataNFT) | parity, unit (by status, zombie, nonexistent revert) | ☐ | ☐ | | Not run | |
| CORE-TN-FR-005 | ERC-721 standard surface (transfer, approval, query, ERC-165) | parity (standard ERC-721 behavior) | ☐ | ☐ | | Not run | |
| CORE-TN-FR-006 | MetadataNFT - on-chain metadata rendering (catalog) | parity (identity of URI structure, attributes, and SVG output) | ☐ | ☐ | | Not run | |

### 15.2 Invariants (CORE-TN-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TN-INV-001 | 1:1 correspondence between NFT and Trove | invariant / parity (ledger-defined) | ☐ | ☐ | | Not run | |

### 15.3 Security Requirements (CORE-TN-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TN-SEC-001 | mint/burn restricted to TroveManager | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-TN-SEC-002 | Recipient callback excluded during mint | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 15.4 Event and Monitoring Requirements (CORE-TN-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TN-EVT-001 | `Transfer` (fires: mint (from=0) / burn (to=0) / transfer) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-TN-EVT-002 | `Approval` (fires: `approve`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-TN-EVT-003 | `ApprovalForAll` (fires: `setApprovalForAll`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 15.5 Failure and Exceptional Behavior (CORE-TN-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TN-ERR-001 | Revert string catalog | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 15.6 Open Issue Register (CORE-TN-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| CORE-TN-TBD-001 | Open | Collection name/symbol depends on deploy order. After operational decision is finalized (dToken `setTokenInfo` -> branch deploy ordering constraint, or acceptance of permanent placeholder), verify through deploy checklist | Linked to notes in CORE-TN-FR-001 row |
| CORE-TN-TBD-002 | Resolved | Adopt the JPYdfTroveNFT / JPYdfMetadataNFT deployment variants, so the deployed collection / tokenURI returns JPYdf wording. Upstream TroveNFT / MetadataNFT remain in the repository for reference and parity. | |


## 16. JpydfToken (CORE-BT)

### 16.1 Functional Requirements (CORE-BT-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BT-FR-001 | constructor (deploy initialization) | parity (base-identical state immediately after deploy; name/symbol values excluded as CORE-MOD-001 difference) | ☐ | ☐ | | Not run | |
| CORE-BT-FR-002 | setBranchAddresses (authorize branch contracts) | parity / unit (onlyOwner, mapping reflection, events) | ☐ | ☐ | | Not run | |
| CORE-BT-FR-003 | setCollateralRegistry (set CR and permanently lock authority) | parity / unit (set value, owner==0 after renounce, repeat call reverts) | ☐ | ☐ | | Not run | |
| CORE-BT-FR-004 | mint (issuance) | parity / unit (authorization revert, balance/supply reflection). Cross-contract supply/debt consistency is CORE-SYS-INV-003 | ☐ | ☐ | | Not run | |
| CORE-BT-FR-005 | burn (redemption/burn) | parity / unit (4 authorization paths, insufficient-balance revert) | ☐ | ☐ | | Not run | |
| CORE-BT-FR-006 | sendToPool (deposit transfer to SP) | parity / unit (SP-only, transfer reflected) | ☐ | ☐ | | Not run | |
| CORE-BT-FR-007 | returnFromPool (withdrawal transfer from SP) | parity / unit (SP-only, transfer reflected) | ☐ | ☐ | | Not run | |
| CORE-BT-FR-008 | transfer / transferFrom (ERC-20 transfer with recipient restrictions) | parity / unit (restriction revert, standard transfer) | ☐ | ☐ | | Not run | |
| CORE-BT-FR-009 | ERC-20 standard compliance (approve / allowance / balance and supply views, etc.) | parity (base-identical standard behavior) | ☐ | ☐ | | Not run | |
| CORE-BT-FR-010 | name / symbol (token name and symbol) 🟡 | unit (fixed-value verification). Exclude the values from parity target and trace as CORE-MOD-001 | ☐ | ☐ | | Not run | |
| CORE-BT-FR-011 | permit (EIP-2612) and EIP-712 domain view group | parity (signature verification, nonce, revert behavior), unit (`DOMAIN_SEPARATOR` is derived from name=`_NAME`) | ☐ | ☐ | | Not run | |
| CORE-BT-FR-012 | Trivial view function group (owner / isOwner / collateralRegistryAddress) | parity | ☐ | ☐ | | Not run | |
| CORE-BT-FR-013 | bridge-admin and bridge-readiness views | unit (initial state, contract-only admin, state survives Core-owner renounce) | ✅ | ✅ | `JpydfTokenTest::test_BridgeReadinessIsDormantAfterCoreSetup`; `JpydfTokenTest::test_BridgeRolesMustBeContractsAndSeparated` | PASS(unit) | Final manifest evidence remains open |
| CORE-BT-FR-014 | bridge-minter registry propose / confirm / cancel / remove | unit (48h boundary, cancel/remove, count/views, admin/minter separation) | ✅ | ✅ | `JpydfTokenTest::test_BridgeMinterLifecycleUsesTimelockAndSelfBurn` | PASS(unit) | Day-1 manifest must retain zero minters and no proposal |
| CORE-BT-FR-015 | bridgeMint / self-burn bridgeBurn | unit (non-minter rejection, mint, self-burn only, post-removal rejection, protocol-recipient rejection) | ✅ | ✅ | `JpydfTokenTest::test_BridgeMinterLifecycleUsesTimelockAndSelfBurn`; `JpydfTokenTest::test_BridgeMintRejectsProtocolRecipients` | PASS(unit) | Activation remains Day-2 gated |
| CORE-BT-FR-016 | two-step bridge-admin transfer / safe renounce | unit (pending-admin acceptance, invalid caller, renounce only with no minter/proposal) | ✅ | ✅ | `JpydfTokenTest::test_BridgeMinterLifecycleUsesTimelockAndSelfBurn` | PASS(unit) | Holder/manifest evidence remains open |

### 16.2 Invariants (CORE-BT-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BT-INV-001 | Permanent fixation of authorization configuration | invariant / parity (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BT-INV-002 | ERC-20 accounting consistency | invariant / parity (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BT-INV-003 | Dormancy of bridge readiness | unit / deploy manifest evidence | ✅ | N/A | `JpydfTokenTest::test_BridgeReadinessIsDormantAfterCoreSetup` | PASS | deploy manifest evidence not run |
| CORE-BT-INV-004 | Global canonical supply accounting after bridge activation | adapter invariant / off-chain accounting replay / fork & integration test / monitoring dry-run | ☐ | ☐ | | PLANNED | Day-2 bridge minter Stage A package before `proposeBridgeMinter` |

### 16.3 Security Requirements (CORE-BT-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BT-SEC-001 | Trust boundary of mint authority | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BT-SEC-002 | Irreversibility of registration (deployment-procedure dependent) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BT-SEC-003 | burn / internal transfer independent of allowance | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BT-SEC-004 | Trust boundary of bridge minter | unit (minter add timelock / self-burn / blocked after remove) | ✅ | ✅ | `JpydfTokenTest::test_BridgeMinterLifecycleUsesTimelockAndSelfBurn` | PASS | Bridge adapter-side rate limit / message verification is handled before registration in CORE-BT-SEC-005 / CORE-BT-GOV-001 and [Bridge-Minter-Activation-Gate](../../protocol/operations/runbooks/Bridge-Minter-Activation-Gate.md) Stage A |
| CORE-BT-SEC-005 | bridge adapter cap / rate / pause fail-closed gate | adapter unit / invariant / integration / incident dry-run | ☐ | ☐ | | PLANNED | If the adapter lacks cap / rate / global bridged supply cap / pause / replay & domain binding, bridge minter registration is not allowed. With an approved package, Stage A registration is allowed with runtime cap 0 / paused |

### 16.4 Governance, Operations, and Upgrade Requirements (CORE-BT-GOV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BT-GOV-001 | bridge minter activation gate | manual governance review / Safe & Timelock transaction evidence / adapter verification package / incident rehearsal | ☐ | ☐ | | PLANNED | Do not `proposeBridgeMinter` before [Bridge-Minter-Activation-Gate](../../protocol/operations/runbooks/Bridge-Minter-Activation-Gate.md) Stage A is complete. operator-only canary is within the adapter / endpoint enforced envelope; UI flag only / public route open / cap ramp are Stage B / C. post-confirm drift invalidates Stage A evidence |

### 16.5 Event and Monitoring Requirements (CORE-BT-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BT-EVT-001 | `CollateralRegistryAddressChanged` (fires: `setCollateralRegistry`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BT-EVT-002 | `TroveManagerAddressAdded` (fires: `setBranchAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BT-EVT-003 | `StabilityPoolAddressAdded` (fires: `setBranchAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BT-EVT-004 | `BorrowerOperationsAddressAdded` (fires: `setBranchAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BT-EVT-005 | `ActivePoolAddressAdded` (fires: `setBranchAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BT-EVT-006 | ERC-20 `Transfer(address from, address to, uint256 value)` (fires: mint (from=0) / burn (to=0) / each transfer) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BT-EVT-007 | ERC-20 `Approval(address owner, address spender, uint256 val...` (fires: `approve` / `permit` / allowance change) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BT-EVT-008 | `OwnershipTransferred` (fires: constructor / `_renounceOwnership`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BT-EVT-009 | `EIP712DomainChanged()` (fires: does not fire; ERC-5267 declaration only, domain immutable) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-BT-EVT-010 | bridge readiness events | unit (admin transfer / minter lifecycle / bridge mint-burn event emission) + Day-2 adapter accounting monitor | ✅ | N/A | `JpydfTokenTest::test_BridgeReadinessEventsExposeLifecyclePayloads` | PASS(unit) | Verifies event payloads for proposal / cancel / confirm / mint / burn / remove / admin transfer / renounce. Day-2 links with the accounting alert of CORE-BT-INV-004 |

### 16.6 Failure and Exceptional Behavior (CORE-BT-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BT-ERR-001 | Failure behavior (require strings) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |


## 17. CollateralRegistry (CORE-CR)

### 17.1 Functional Requirements (CORE-CR-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CR-FR-001 | constructor (fix branch configuration and bootstrap baseRate) | parity / unit (boundaries 1, 10, 11; initial baseRate; zero unused slots) | ☐ | ☐ | | Not run | |
| CORE-CR-FR-002 | redeemCollateral (cross-branch redemption) | parity (allocation, truncation, fallback, rate calculation, burn amount), invariant=CORE-CR-INV-001-003 | ☐ | ☐ | | Not run | |
| CORE-CR-FR-003 | getRedemptionRate (effective rate at current baseRate) | parity | ☐ | ☐ | | Not run | |
| CORE-CR-FR-004 | getRedemptionRateWithDecay (effective rate after decay) | parity | ☐ | ☐ | | Not run | |
| CORE-CR-FR-005 | getRedemptionRateForRedeemedAmount (rate estimate when redeeming specified amount) | parity | ☐ | ☐ | | Not run | |
| CORE-CR-FR-006 | getRedemptionFeeWithDecay (fee calculation for amount) | parity | ☐ | ☐ | | Not run | |
| CORE-CR-FR-007 | getEffectiveRedemptionFeeInJpydf (effective fee in JPYdf terms) | parity | ☐ | ☐ | | Not run | |
| CORE-CR-FR-008 | getToken / getTroveManager (index -> branch reference) | parity / unit (revert at 10 or more, zero return for unused slot) | ☐ | ☐ | | Not run | |
| CORE-CR-FR-009 | Trivial view function group (baseRate / lastFeeOperationTime / totalCollaterals / jpydfToken) | parity | ☐ | ☐ | | Not run | |

### 17.2 Invariants (CORE-CR-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CR-INV-001 | Upper bound of baseRate | invariant / parity (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-CR-INV-002 | Range of effective rate | invariant / parity (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-CR-INV-003 | Monotonicity of lastFeeOperationTime | invariant / parity (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-CR-INV-004 | Immutability of branch configuration | invariant / parity (ledger-defined) | ☐ | ☐ | | Not run | |

### 17.3 Security Requirements (CORE-CR-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CR-SEC-001 | Exactness of allocation and truncation | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-CR-SEC-002 | External dependency on price and redeemability | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 17.4 Event and Monitoring Requirements (CORE-CR-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CR-EVT-001 | `BaseRateUpdated` (fires: constructor (initial value) / `redeemCollateral`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-CR-EVT-002 | `LastFeeOpTimeUpdated` (fires: `redeemCollateral`, only when at least 1 minute has elapsed) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 17.5 Failure and Exceptional Behavior (CORE-CR-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CR-ERR-001 | Failure behavior (require strings) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |


## 18. AddressesRegistry (CORE-AR)

### 18.1 Functional Requirements (CORE-AR-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AR-FR-001 | constructor (set initial risk values and the active / reserved lifecycle) | parity / unit (each boundary and lifecycle initial values for zero/nonzero finalizer) | ☐ | ☐ | | Not run | |
| CORE-AR-FR-002 | setAddresses (batch address wiring and ownership renounce) | parity / unit (onlyOwner, reflection of 18 values, 18+1 events, repeat-call revert after renounce) | ☐ | ☐ | | Not run | |
| CORE-AR-FR-003 | Branch risk parameter getter group (CCR / SCR / MCR / BCR / liquidation penalties) | parity | ☐ | ☐ | | Not run | |
| CORE-AR-FR-004 | Address getter group (all 18 addresses + owner / isOwner) | parity (values before and after `setAddresses`) | ☐ | ☐ | | Not run | |
| CORE-AR-FR-005 | finalizeRiskParams (one-shot finalization of the exact Underlying and 6 values for a reserved branch, synchronized to BO / TM) | unit / invariant (authorization, one-shot property, all preconditions, synchronization, rollback) + event / getter / attested storage or atomic-sync evidence | ☑ | ☑ | `RiskParamsFinalizationTest::test_FinalizerIsAuthorizedAndFinalizationIsOneShot`; `RiskParamsFinalizationTest::test_FinalizationSynchronizesAllSixParams`; `RiskParamsFinalizationTest::test_FinalizationRejectsNonemptyCoreState`; `RiskParamsFinalizationTest::test_ChildSyncFailureRollsBackRegistryAndOtherChild` (2026-08-29) | PARTIAL | Unit evidence exists. Live activation event / readback evidence remains outstanding. Do not assume getters exist for TM's 4 internal values other than CCR |

### 18.2 Invariants (CORE-AR-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AR-INV-001 | Range and post-finalization immutability of risk parameters | invariant / unit (initial ranges, finalization cross-conditions, and rejection of repeat finalization) | ☐ | ☐ | | Not run | |
| CORE-AR-INV-002 | One-time wiring | invariant / parity (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-INV-003 | Monotonic risk lifecycle (exactly one false -> true transition) | invariant / unit | ☐ | ☐ | | Not run | |

### 18.3 Security Requirements (CORE-AR-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AR-SEC-001 | Wiring values are not validated (dependent on deployment procedure) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-SEC-002 | Finalization target, empty-state, oracle-pause, and terminal-shutdown boundaries | unit / adversarial review | ☑ | ☑ | `RiskParamsFinalizationTest::test_FinalizationRequiresDTokenAndVaultBoundToExpectedUnderlying`; `RiskParamsFinalizationTest::test_FinalizationRejectsNonzeroCapOrSupply`; `RiskParamsFinalizationTest::test_FinalizationRejectsNonemptyCoreState`; `RiskParamsFinalizationTest::test_FinalizationRejectsEveryShutdownState`; `RiskParamsFinalizationTest::test_ReversibleOraclePauseCanRecoverThenFinalize`; `RiskParamsFinalizationTest::test_EmptyReservedBranchCannotEnterTerminalShutdown` (2026-08-29) | PARTIAL | Unit / adversarial-boundary evidence exists. Activation-fork evidence remains outstanding |

### 18.4 Event and Monitoring Requirements (CORE-AR-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AR-EVT-001 | `CollTokenAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-002 | `BorrowerOperationsAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-003 | `TroveManagerAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-004 | `TroveNFTAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-005 | `MetadataNFTAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-006 | `StabilityPoolAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-007 | `PriceFeedAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-008 | `ActivePoolAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-009 | `DefaultPoolAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-010 | `GasPoolAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-011 | `CollSurplusPoolAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-012 | `SortedTrovesAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-013 | `InterestRouterAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-014 | `HintHelpersAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-015 | `MultiTroveGetterAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-016 | `CollateralRegistryAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-017 | `JpydfTokenAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-018 | `WETHAddressChanged` (fires: `setAddresses`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-019 | `OwnershipTransferred` (fires: constructor / `_renounceOwnership`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-AR-EVT-020 | `RiskParamsFinalized` (fires once when `finalizeRiskParams` succeeds) | unit (topic, exact Underlying, and final 6 values) / activation monitoring | ☐ | ☐ | | Not run | |

### 18.5 Failure and Exceptional Behavior (CORE-AR-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AR-ERR-001 | Failure behavior (custom errors) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |


## 19. HintHelpers (CORE-HH)

### 19.1 Functional Requirements (CORE-HH-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-HH-FR-001 | getApproxHint (approximate hint search by random sampling) | parity (base-identical behavior; deterministic with fixed seed) / unit | ☐ | ☐ | | Not run | |
| CORE-HH-FR-002 | predictOpenTroveUpfrontFee (fee estimate for openTrove) | parity / unit | ☐ | ☐ | | Not run | |
| CORE-HH-FR-003 | predictAdjustInterestRateUpfrontFee (fee estimate for rate adjustment) | parity / unit | ☐ | ☐ | | Not run | |
| CORE-HH-FR-004 | forcePredictAdjustInterestRateUpfrontFee (unconditional fee estimate for rate adjustment) | parity / unit | ☐ | ☐ | | Not run | |
| CORE-HH-FR-005 | predictAdjustTroveUpfrontFee (fee estimate for debt-increase adjustment) | parity / unit | ☐ | ☐ | | Not run | |
| CORE-HH-FR-006 | predictAdjustBatchInterestRateUpfrontFee (fee estimate for batch rate change) | parity / unit | ☐ | ☐ | | Not run | |
| CORE-HH-FR-007 | predictOpenTroveAndJoinBatchUpfrontFee (fee estimate for opening while joining batch) | parity / unit | ☐ | ☐ | | Not run | |
| CORE-HH-FR-008 | predictJoinBatchInterestRateUpfrontFee (fee estimate for joining batch) | parity / unit | ☐ | ☐ | | Not run | |
| CORE-HH-FR-009 | predictRemoveFromBatchUpfrontFee (fee estimate for leaving batch) | parity / unit | ☐ | ☐ | | Not run | |
| CORE-HH-FR-010 | Constants and reference view function group | parity | ☐ | ☐ | | Not run | |

### 19.2 Invariants (CORE-HH-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-HH-INV-001 | Fee estimates match actual charges | parity (cross-check with BO execution result) | ☐ | ☐ | | Not run | |

### 19.3 Security Requirements (CORE-HH-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-HH-SEC-001 | Non-custodial and non-interfering | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 19.4 Failure and Exceptional Behavior (CORE-HH-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-HH-ERR-001 | Invalid _collIndex | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |


## 20. MultiTroveGetter (CORE-MTG)

### 20.1 Functional Requirements (CORE-MTG-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-MTG-FR-001 | getMultipleSortedTroves (batch fetch Troves ordered by interest rate) | parity / unit | ☐ | ☐ | | Not run | |
| CORE-MTG-FR-002 | getDebtPerInterestRateAscending (fetch debt distribution in ascending interest-rate order) | parity / unit | ☐ | ☐ | | Not run | |
| CORE-MTG-FR-003 | Reference view function group | parity | ☐ | ☐ | | Not run | |

### 20.2 Security Requirements (CORE-MTG-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-MTG-SEC-001 | Non-custodial and non-interfering | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 20.3 Failure and Exceptional Behavior (CORE-MTG-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-MTG-ERR-001 | Invalid _collIndex | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |


## 21. DebtInFrontHelper (CORE-DFH)

### 21.1 Functional Requirements (CORE-DFH-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-DFH-FR-001 | getDebtBetweenInterestRates (total debt in interest-rate band) | parity / unit | ☐ | ☐ | | Not run | |
| CORE-DFH-FR-002 | getDebtBetweenInterestRateAndTrove (total debt before a specific Trove) | parity / unit | ☐ | ☐ | | Not run | |
| CORE-DFH-FR-003 | Reference view function group | parity | ☐ | ☐ | | Not run | |

### 21.2 Security Requirements (CORE-DFH-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-DFH-SEC-001 | Non-custodial and non-interfering | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 21.3 Failure and Exceptional Behavior (CORE-DFH-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-DFH-ERR-001 | Invalid _collIndex | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |


## 22. RedemptionHelper (CORE-RH)

### 22.1 Functional Requirements (CORE-RH-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-RH-FR-001 | redeemCollateral (redemption wrapper with min-out) | parity / unit (min-out violation revert, residual return) / invariant=CORE-RH-INV-001 | ☐ | ☐ | | Not run | |
| CORE-RH-FR-002 | simulateRedemption (exclude failure branches while retaining the CR allocation denominator) | parity / unit / integration | ☑ | ☑ | `RedemptionHelperOracleFailureTest::test_simulationExcludesRedemptionFailureBeforeComputingProportions`; `RedemptionHelperTest::test_NormalRedemptionOracleFailure_DirectAndHelperSpendNothing`; `RedemptionHelperTest::test_SimulationKeepsFailedBranchInCollateralRegistryAllocationDenominator` | PARTIAL | C2. The CORE-MOD-015 delta passes; full parity reruns for existing base scanning, fallback, and iteration boundaries remain outstanding |
| CORE-RH-FR-003 | truncateRedemption (zero-fill every branch when the second read fails) | parity / unit / integration | ☐ | ☑ | `RedemptionHelperOracleFailureTest::test_truncateReturnsZeroIfSecondRedemptionReadFails` | PARTIAL | C2. The second-read failure delta passes; the full normal truncate / fee / collateral-conversion base parity surface was not rerun |
| CORE-RH-FR-004 | Reference view function group | parity | ☐ | ☐ | | Not run | |
| CORE-RH-FR-005 | constructor (deploy-time consistency verification) | unit (mismatch constructor revert) | ☐ | ☐ | | Not run | |

### 22.2 Invariants (CORE-RH-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-RH-INV-001 | Funds pass-through (balance invariant) | invariant / unit | ☐ | ☐ | | Not run | |

### 22.3 Security Requirements (CORE-RH-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-RH-SEC-001 | No custody and no rescue function | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 22.4 Failure and Exceptional Behavior (CORE-RH-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-RH-ERR-001 | Failure behavior (including the normal-redemption failure bool) | parity / unit / integration | ☑ | ☑ | `RedemptionHelperOracleFailureTest::test_simulationExcludesRedemptionFailureBeforeComputingProportions`; `RedemptionHelperOracleFailureTest::test_truncateReturnsZeroIfSecondRedemptionReadFails`; `RedemptionHelperTest::test_NormalRedemptionOracleFailure_DirectAndHelperSpendNothing`; `RedemptionHelperTest::test_SimulationKeepsFailedBranchInCollateralRegistryAllocationDenominator` | PARTIAL | C2. The #1837 all-unavailable / mixed-denominator / second-read / zero-spend cases all pass; existing require and constructor failure cases were not rerun |


## 23. LiquidationCandidateGetter (CORE-LCG)

### 23.1 Functional Requirements (CORE-LCG-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-LCG-FR-001 | getLiquidationCandidates (paged scan for liquidation candidates) 🟢 | unit (🟢 DF-specific, outside parity target. ICR boundary, paging, empty list, zombie exclusion) | ☐ | ☐ | | Not run | |
| CORE-LCG-FR-002 | Reference view function group 🟢 | unit | ☐ | ☐ | | Not run | |
| CORE-LCG-FR-003 | Making lastZombieTroveId a liquidation candidate 🟢 | unit (last zombie present/absent, ICR boundary, debt/coll retrieval, appending to the end of the combined API) + bot scan unit/integration | ☐ | ☐ | | Not run | Resolves CORE-LCG-TBD-001 |

### 23.2 Invariants (CORE-LCG-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-LCG-INV-001 | Core non-interference 🟢 | unit / code review (mutability and dependency direction) | ☐ | ☐ | | Not run | |

### 23.3 Failure and Exceptional Behavior (CORE-LCG-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-LCG-ERR-001 | Invalid _collIndex 🟢 | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 23.4 Open Issue Register (CORE-LCG-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| CORE-LCG-TBD-001 | Resolved | The LCG extension makes `lastZombieTroveId` a candidate, and the Rust bot uses `getLiquidationCandidatesWithLastZombie` with `include_last_zombie=true`. Covering multiple zombies is a follow-up indexer task | Linked to CORE-LCG-FR-003 |


## 24. Shared Foundations Dependencies / Types (CORE-LIB)

### 24.1 Functional Requirements (CORE-LIB-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-LIB-FR-001 | Provide file-level system constants | parity (all constants except 2 🟡 items equal base values = CORE-LIB-INV-001) | ☐ | ☐ | | Not run | |
| CORE-LIB-FR-002 | MIN_DEBT (minimum debt change) 🟡 | unit (boundary: exactly `MIN_DEBT` / below), 🟡 difference test (value is 100_000e18) | ☐ | ☐ | | Not run | |
| CORE-LIB-FR-003 | COLL_GAS_COMPENSATION_CAP (collateral gas compensation cap change) 🟡 | unit (cap reached / not reached boundary), 🟡 difference test (value is 1_000 ether) | ☐ | ☐ | | Not run | |
| CORE-LIB-FR-004 | DF branch-specific constants (finalized active values and bootstrap values for reserved deployment) 🟢 | unit (each constant matches its commented value and [Parameters.md](../../Parameters.md); `*_WETH`/`*_SETH`/`BCR_ALL` maintain base equality) | ☐ | ☐ | | Not run | Final reserved-branch values are set through CORE-AR-FR-005 |
| CORE-LIB-FR-005 | constructor (resolve references from AddressesRegistry) | parity / deploy verification (wiring match) | ☐ | ☐ | | Not run | |
| CORE-LIB-FR-006 | getEntireBranchColl / getEntireBranchDebt (branch-wide aggregation) | parity / invariant=CORE-SYS-INV-001 | ☐ | ☐ | | Not run | |
| CORE-LIB-FR-007 | _getTCR / _checkBelowCriticalThreshold (TCR and CT judgment) | parity / unit (false when branch debt is 0) | ☐ | ☐ | | Not run | |
| CORE-LIB-FR-008 | _calcInterest (simple-interest calculation primitive) | parity / unit (rounding direction) | ☐ | ☐ | | Not run | |
| CORE-LIB-FR-009 | Comparison, difference, and collateral-ratio helpers | parity / unit (debt=0 -> max uint, rounding direction) | ☐ | ☐ | | Not run | |
| CORE-LIB-FR-010 | decMul / _decPow (power operation for 18-decimal fixed point) | parity / unit (n=0 / n=1 / odd/even / cap boundary 525,600,000) | ☐ | ☐ | | Not run | |
| CORE-LIB-FR-011 | Owner model (constructor / owner / isOwner / onlyOwner) | parity / unit (non-owner revert and string match) | ☐ | ☐ | | Not run | |
| CORE-LIB-FR-012 | _renounceOwnership (renounce ownership after wiring completes) | parity / unit (onlyOwner permanently reverts after renounce, event args) | ☐ | ☐ | | Not run | |
| CORE-LIB-FR-013 | TroveId type (Deprecated: removed from production `src`) | unit (`SortedTroves` test-local helper) / static (`Types/TroveId.sol` absent) | ☐ | ☐ | | Not run | Withdrawn from production scope because the helper is unreferenced in fresh deploy code |
| CORE-LIB-FR-014 | BatchId type | parity | ☐ | ☐ | | Not run | |
| CORE-LIB-FR-015 | TroveChange struct (passing operation deltas) | parity / invariant=CORE-SYS-INV-002 | ☐ | ☐ | | Not run | |
| CORE-LIB-FR-016 | LatestTroveData struct (latest Trove state snapshot) | parity / unit (batch/non-batch consistency) | ☐ | ☐ | | Not run | |
| CORE-LIB-FR-017 | LatestBatchData struct (latest batch state snapshot) | parity / unit | ☐ | ☐ | | Not run | |

### 24.2 Invariants (CORE-LIB-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-LIB-INV-001 | Upstream constants equal base values | parity (constant-value cross-check with base) | ☐ | ☐ | | Not run | |
| CORE-LIB-INV-002 | Exactness of derived constants | unit (evaluation-value check of constant expressions) | ☐ | ☐ | | Not run | |
| CORE-LIB-INV-003 | Equivalence of list-termination convention | unit (constant equality) / cross-contract rule is CORE-SYS-INV-014 | ☐ | ☐ | | Not run | |

### 24.3 Security Requirements (CORE-LIB-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-LIB-SEC-001 | `_renounceOwnership` has no caller check | static inspection (all call sites are in onlyOwner context) | ☐ | ☐ | | Not run | |

### 24.4 Event and Monitoring Requirements (CORE-LIB-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-LIB-EVT-001 | `ActivePoolAddressChanged` (fires: constructor (CORE-LIB-FR-005)) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-LIB-EVT-002 | `DefaultPoolAddressChanged` (fires: same as above) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-LIB-EVT-003 | `PriceFeedAddressChanged` (fires: same as above) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |
| CORE-LIB-EVT-004 | `OwnershipTransferred` (fires: constructor (0 -> initialOwner) / `_renounceOwnersh...`) | parity / unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 24.5 Failure and Exceptional Behavior (CORE-LIB-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-LIB-ERR-001 | Arithmetic Panic only (no custom errors) | fuzz (Panic confirmation in boundary domain) | ☐ | ☐ | | Not run | |
| CORE-LIB-ERR-002 | onlyOwner violation revert | unit (string match) | ☐ | ☐ | | Not run | |

### 24.6 Open Issue Register (CORE-LIB-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| CORE-LIB-TBD-001 | Open (reserved) | Constants for Branches 2–7 are deployment bootstrap values, not approved values for the exact Underlying. Before activation, rederive all 6 values from collateral stress and finalize them once through CORE-AR-FR-005 only if they comply with [Collateral Parameter Policy](../../protocol/product/policies/Collateral-Parameter-Policy.md) §2.4. Otherwise keep cap 0 / reserved; any change after finalization requires redeployment and migration | Linked to CORE-MOD-005 / CORE-MOD-013 rows |

---

## 25. Completion Criteria and Revision Rules

### 25.1 Completion Criteria (parity acceptance)

Only when all of the following hold can the project claim that "all core functions and state variables function identically to the fork source, and DF differences are limited exactly to the ledger" (paired with spec §13.3):

1. **Coverage**: all `CORE-*` IDs extracted from the spec (matching the §3 totals) exist in this ledger; missing numbers and out-of-scope items (open TBD) are explicitly stated with reasons.
2. **All rows closed**: every row result is `PASS` or `N/A(reason)`. Do not write "complete" while `Not run` / `FAIL` / `BLOCKED` remains.
3. **Happy path and exception path**: both sides for each ID are `✅` or `N/A(reason)`.
4. **Static parity**: §4 row 1 (guard), row 4 (DFStabilityPool diff), and row 5 (Constants cross-check) are PASS.
5. **Evidence**: every PASS row has a test artifact (transcribed from execution logs) and campaign ID, and §2 traces back to commit SHA and execution commands.
6. **Double-check**: for each campaign, re-confirm that the mechanical diff (grep-based) between the full `CORE-*` ID set in the spec and the full ID set in this ledger is empty (because the spec continues to change).

### 25.2 Revision Rules

- When IDs are added or revised in the source-of-truth spec, add or update rows in this ledger (**spec revision first, ledger follows**; do not define behavior in the reverse direction).
- IDs follow the append-only convention in the spec. Do not issue independent IDs in the ledger (non-ID check rows are identified by the # sequence and content text in §4).
- Test names and results live only in this ledger. Do not write them back into the source-of-truth spec (compliance with documentation-standard guardrails 1 and 2).
- If a conflict between spec and implementation is found in a 🔵 row, follow §1.3 judgment principle 8 (base is authoritative; spec revision first).

### 25.3 Related Documents

- [Liquity-v2-Core-Spec.md](../../protocol/product/spec/Liquity-v2-Core-Spec.md) - source of truth under verification (`CORE-*` IDs, modification ledger `CORE-MOD-*`, and §13 acceptance criteria)
- [Requirements Spec Standard](../../README.md#requirements-spec-standard) - source of truth for ID conventions and the "do not write test names in docs" guardrail
- [Parameters.md](../../Parameters.md) - source of truth for `Constants.sol` values and branch parameters (cross-check target for §4 row 5 and CORE-MOD-005)
- [Development-Plan.md](../plans/Development-Plan.md) - phase ToDo and position of the verification phase
- `engineering/historical-reviews/` - location for manual verification records (configuration review and deploy verification)
