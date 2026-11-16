# Requirements Verification Ledger - local test run record

## 0. Purpose and Positioning

This document is the ledger that records whether **every requirement ID** assigned in the requirements specifications (the source of truth) under [`documents/jp`](../../README.md) has been verified by implementation and tests in the local environment.

- **Scope**: functional requirements (FR) / invariants (INV) / security requirements (SEC) / governance, operations, and upgrade requirements (GOV) / event and monitoring requirements (EVT) / failure and exceptional behavior (ERR) / acceptance criteria (each doc §13) / open issues (TBD). Every assigned ID has **one row without exception** in this document; even rows excluded from verification remain with the fact and reason stated.
- **Basis**: the [Requirements Spec Standard](../../README.md#requirements-spec-standard) states that "test names and execution results are not written in the specification body; ID linkage is one-way (tests and ledgers reference doc IDs)." This document is the receiving side of that one-way reference: the source of truth for "ID x actual test x execution result."
- **Relationship to each doc §13 (acceptance criteria and verification plan)**: §13 defines pass conditions as "ID x verification method." This document transcribes each §13 and requirement-level `Verification` designation into the "Specified verification method" column. **When a row's happy path and exception path are evidenced by the specified verification method, the acceptance criteria for that ID are satisfied.**
- **For auditors**: this document lets reviewers trace (1) coverage of all IDs, (2) happy-path and exception-path evidence per ID, and (3) evidence artifacts (commit SHA, commands, test names, results).

> Implementation under verification: `deltaforesight/jpydf-v2` (`develop`; record the head SHA at verification time in §2). If specification and implementation differ, treat the requirements specifications (`jp/*.md`) as authoritative, record a FAIL, and file an implementation-side fix issue.

> **Baseline note (2026-06-13 develop baseline, updated 2026-06-22)**: this ledger is based on **develop** and already reflects 7 develop-specific IDs that landed ahead of docs: STGY-INV-010 / STGY-SEC-008 / STGY-GOV-005 / STGY-EVT-009 (Strategy upgrader separation) and ZAP-FR-014 / ZAP-INV-009 / ZAP-TBD-009 (Sky USDC route). The former governance-docs-pending references are resolved on current `develop`: **VAULT-FR-019** (`emergencyDisableStrategy`), **Parameters §2-D** (governance delay controls), and the governance rows incorporating the shared TimelockController decision (2026-06-12; VAULT-GOV-004 / DTKN-GOV-004 / STGY-GOV-003, etc.) are treated as present in the current specs / design docs. The current ID total is governed by the §3 aggregate.

---

## 1. Operating Rules (Entry and Judgment)

### 1.1 Row Structure (Common Schema)

| Column | Content |
| --- | --- |
| ID | Requirement ID (use the ID from the source-of-truth doc as-is; do not issue new IDs in the ledger) |
| Requirement (summary) | Short transcription of the source-of-truth doc heading/wording. **The source of truth for expected behavior is the body text of the corresponding ID in the doc** (if the summary conflicts with the doc, the doc is authoritative) |
| Specified verification method | Transcription of source-of-truth doc §13 and each requirement's `Verification` designation (unit / fuzz / invariant=INV-ID / fork / integration / e2e-local / build / ci-guard / manual, etc.). Rows without a doc designation are marked `(ledger-defined)`. The authoritative source is the per-ID `Verification` designation (for INV, the verification column in the §8 table). If a per-ID designation and a §13 per-ID row coexist, record the union. Interpret §13 **range rows** (summary rows such as "as stated in §N") through the per-ID designations. For categories with no per-ID designation (Frontend SEC / ERR / INV), apply the main area-level verification in §13 |
| Happy path | `☐` -> `✅` when evidenced, or `N/A` when not applicable (put the reason in Notes) |
| Exception path | Same as above |
| Test artifact | `TestContract::testFunction` (multiple allowed) or a reference to a manual verification record. **Transcribe from forge or other execution logs (do not write nonexistent test names)** |
| Result | `Not run` / `PASS` / `FAIL` (issue reference required) / `BLOCKED(reason)` (unimplemented, open gate, etc.) / `N/A(reason)` |
| Notes | Campaign ID (§2), actual skip cause, N/A reason, missing number, etc. |

### 1.2 Category Definitions for Happy Path and Exception Path

| Category | What the happy path evidences | What the exception path evidences |
| --- | --- | --- |
| FR | When preconditions hold, the behavior stated in the doc (Effects, return values, emitted events) holds | Each revert / early return / boundary condition stated in the doc actually fires in at least one test |
| INV | Invariants are maintained under normal operation sequences (invariant / fuzz) | Operations attempting to violate them fail, or evidence shows the violating state is unreachable by definition |
| SEC | Operations through authorized roles and paths succeed | Attack paths (unauthorized calls, reentrancy, spoofing, donation, operational paths) are blocked |
| GOV | Authorized parties succeed through the correct procedure (timelock elapsed, 2-step, etc.) | Unauthorized parties or procedure violations (delay not elapsed, 1-step renounce, etc.) revert. Manual items may be substituted with configuration review records |
| EVT | Events fire with specified parameters | Events do not fire under non-emission conditions / emissions roll back when the operation fails |
| ERR | (Primary verification is the exception path) no false trigger occurs (no degradation in normal cases) | The degradation, revert, or failsafe stated in the doc actually occurs under the exceptional trigger |
| TBD | - outside verification scope (open gate). Resolved items are verified in the destination ID row | - |

- If one side does not exist because the item is view-only, off-chain operation only, etc., use `N/A(reason)` (do not treat a blank as complete).

### 1.3 Judgment Principles (Guardrails)

1. **Only actual runs are evidence**: structural checks (presence of code/test files) are not verification. Only execution results such as `forge test` can support PASS.
2. **Skip is not PASS**: tests skipped at runtime (missing fork RPC, `vm.skip`, etc.) do not count as PASS; record the skip cause in Notes.
3. **Flaky handling**: if a retry passes, record the first failure input (fuzz seed / counterexample), confirm it is not a real counterexample, then mark PASS. If fuzz cache (`cache/fuzz`) was deleted before rerun, record that fact to avoid hiding failure inputs.
4. **Completion claims are scoped to verified range**: while even one row remains FAIL, Not run, or BLOCKED, do not write that the ledger is "complete." Write "matches / no issue" only when all rows are PASS/N/A.
5. **Fork tests**: use public archive RPC or internal RPC. **Do not write RPC URLs or API keys in this document, logs, or error output** (pass them through environment variables).
6. **Unimplemented requirements**: record `BLOCKED(unimplemented)` (prevents hiding untestability; may occur for modules whose design is finalized but implementation has not started, such as Treasury).
7. **Verification is pinned to head**: fix the commit SHA at campaign start and verify all rows on the same SHA. If SHA advances, start a new campaign.

### 1.4 Standard Local Run Procedure

```bash
# 1) Do not run on Google Drive. Isolate in a disposable clone
git clone https://github.com/deltaforesight/jpydf-v2 /tmp/jpydf-v2-verify && cd /tmp/jpydf-v2-verify
git rev-parse HEAD   # -> record in §2

# 2) Record toolchain
~/.foundry/bin/forge --version   # -> record in §2

# 3) Clean build (avoid false detections from stale out/)
cd contracts && ~/.foundry/bin/forge clean && ~/.foundry/bin/forge build

# 4) Test run (save logs and transcribe into ledger; remember set -o pipefail)
set -o pipefail
~/.foundry/bin/forge test -vv 2>&1 | tee /tmp/forge-test-$(date +%Y%m%d).log

# 5) Fork tests (RPC via environment variables. Do not print URLs or record them in the ledger)
source ~/.config/deltaforesight/rpc.env
~/.foundry/bin/forge test --match-path 'test/*fork*' -vv 2>&1 | tee -a /tmp/forge-test-fork.log
```

- Frontend (`FRNT-*`) e2e-local follows the end-to-end internal recipe: anvil -> deploy -> subgraph -> frontend. Record execution in §2 and the relevant rows.
- For manual work (configuration review, runbook, storage layout review, etc.), record executor, date, and checked content under `engineering/historical-reviews/`, then reference the record from rows.

---

## 2. Verification Environment Record (Campaign Ledger)

Add one row per verification campaign (a set of runs on the same commit SHA), and reference the campaign ID from Notes in each ID row.

| Campaign | Date run | repo / branch | commit SHA | forge / environment | fork RPC (type only) | Commands / logs | Executor | Result summary |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| VAULT-RECERT-20260812 | 2026-08-12 | jpydf-v2 / `agent/recertify-vault-audit-invariants` | develop `8c8b4e31` + invariant / ledger overlay | forge 1.7.1 local | none | 6 focused suites; `FOUNDRY_PROFILE=ci forge test -vv --no-match-contract 'Mainnet\|Invariant\|Anchored\|Initiative\|LocalParityDrill'`; `forge fmt --check`; `git diff --check` | Codex | PASS: focused 263 and fast 1,572, all with 0 failed / 0 skipped. All 7 push-model invariants ran 500 runs / 25,000 calls / 0 reverts each. Added Strategy update / emergency-disable actions and recertified VAULT-INV-009/012/014. MAINNET_RPC was not used, so VAULT-FR-016's specified fork evidence remains outstanding |
| V1 | 2026-06-20 | jpydf-v2 / develop | 28808fd + working tree | forge 0.8.24 local | none | `forge test --match-contract 'SkyUsdcSUsdsStrategyTest\|EtherfiWeETHStrategyTest\|DeployLiquity2StrategySelectorTest\|DFGovernanceHandoverXAUTGateTest'`; `forge build`; `git diff --check` | Codex | PASS: focused 44 tests, build, diff check |
| V2 | 2026-06-21 | jpydf-v2 / develop | b7280145 + working tree | forge 0.8.24 local | none | `forge test --match-contract 'LidoStrategyTest\|EtherfiWeETHStrategyTest\|SkyUsdcSUsdsStrategyTest\|AaveV3StrategyTest\|ERC4626StrategyTest\|DeployLiquity2StrategySelectorTest'`; `git diff --check` | Codex | PASS: focused 115 tests, diff check |
| V3 | 2026-06-21 | jpydf-v2 / develop | 923b39d + working tree | node / pnpm local | none | `pnpm --filter @jpydf/console build`; static `writeoffStrategyPrincipal` calldata-shape check; `git diff --check` | Codex | PASS: console build, calldata shape, diff check |
| V7 | 2026-06-21 | jpydf-v2 / codex/sky-conversion-loss-floor | 83517a9 + working tree | forge 1.2.3-nightly local | none | `forge test --match-path test/SkyUsdcSUsdsStrategy.t.sol`; `forge fmt --check src/Strategies/SkyUsdcSUsdsStrategy.sol test/SkyUsdcSUsdsStrategy.t.sol`; `git diff --check` | Codex | PASS: SkyUsdcSUsdsStrategy focused 9 tests, fmt check, diff check. Normal withdraw and 2-step / one-tx emergency recovery cannot relax the `maxConversionLossBps` floor even with `minUsdcOut=0` |
| V8 | 2026-06-24 | jpydf-v2 / codex/security-dos-review-20260624 | a4dcf68 + working tree | forge 1.2.3-nightly local | none | `forge fmt --check`; `git diff --check`; `forge test --match-path test/EtherfiWeETHStrategy.t.sol -vv`; `forge test --match-path 'test/*Strategy*.t.sol' -vv` | Codex | PASS: Etherfi focused 20 tests, Strategy suite 262 tests, fmt check, diff check. Etherfi raw ETH donations do not enter claim delta / idle WETH / yield / valuation, and existing EFWEETH-SEC-008..011 test artifacts were confirmed |
| V9 | 2026-06-24 | jpydf-v2 / codex/vault-buffer-shortfall-prep-20260624 | bfd5a4e + working tree | forge 1.2.3-nightly local | none | `forge test --match-path test/AaveV3Strategy.t.sol`; `forge test --match-path test/ERC4626Strategy.t.sol`; `forge test --match-path test/SkyUsdcSUsdsStrategy.t.sol`; `forge test --match-path test/EtherfiWeETHStrategy.t.sol`; `forge test --match-path test/InvariantPushModel.t.sol`; `forge fmt --check src/Strategies/AaveV3Strategy.sol src/Strategies/ERC4626Strategy.sol src/Strategies/SkyUsdcSUsdsStrategy.sol test/AaveV3Strategy.t.sol test/ERC4626Strategy.t.sol test/SkyUsdcSUsdsStrategy.t.sol test/EtherfiWeETHStrategy.t.sol`; `git diff --check` | Codex | PASS: Aave focused 23 tests, ERC4626 focused 22 tests, Sky focused 12 tests, Etherfi focused 21 tests, push model invariant 4 tests, fmt check, diff check. Confirmed accounting guards for zero-scaled / zero-share / zero-USDC dust / tiny weETH rounding |
| V10 | 2026-07-07 | jpydf-v2 / codex/etherfi-withdraw-adapter | 75021f57 + working tree | forge 1.2.3-nightly local | none | `forge test --match-path test/EtherfiWeETHStrategy.t.sol -vv`; `forge test --match-path test/DeployLiquity2StrategySelector.t.sol -vv`; `forge build --skip test`; `forge fmt --check src/Strategies/EtherfiWeETHStrategy.sol src/Strategies/WeETHWithdrawAdapter.sol test/EtherfiWeETHStrategy.t.sol test/DeployLiquity2StrategySelector.t.sol script/DeployLiquity2.s.sol`; `git diff --check` | Codex | PASS: Etherfi focused 33 tests, DeployLiquity2StrategySelector 32 tests, build, fmt check, diff check. Confirmed the DeltaForesight first-party `WeETHWithdrawAdapter` unwraps weETH to eETH, creates an Ether.fi native withdrawal request, rejects venue graph / LiquidityPool reverse-binding mismatch, zero request, and residual weETH / eETH, while the Strategy validates adapter binding before approval and preserves request-owner verification |
| V11 | 2026-07-07 | jpydf-v2 / codex/etherfi-adapter-identity-marker | working tree | forge 1.2.3-nightly local | none | `forge test --match-path test/EtherfiWeETHStrategy.t.sol -vv`; `forge test --match-path test/DeployLiquity2StrategySelector.t.sol -vv`; `forge build --skip test`; `forge fmt --check src/Strategies/EtherfiWeETHStrategy.sol src/Strategies/WeETHWithdrawAdapter.sol test/EtherfiWeETHStrategy.t.sol test/DeployLiquity2StrategySelector.t.sol script/DeployLiquity2.s.sol`; `git diff --check` | Codex | PASS: Etherfi focused 34 tests, DeployLiquity2StrategySelector 32 tests, build, fmt check, diff check. Confirmed the Strategy requires the DF-specific `dfWeETHWithdrawAdapterId()` marker before approval and rejects same-named or ABI-compatible adapters that do not expose the marker |
| V12 | 2026-07-14 | jpydf-v2 / codex/sky-usdc-usds-converter | `eed3edfa` (implementation) / `b789c6bd` (ledger correction) | forge 1.2.3-nightly local + GitHub Actions | Ethereum mainnet RPC (URL not recorded) | focused commands; Actions `29349413077` (full local / mainnet / deploy / parity / handover); Slither 0.10.2 audit config | Codex | PASS: converter 11 tests (9 unit + 2 mainnet fork), Strategy 13, Zapper 31, and deploy selector 32. Actions full local, mainnet fork, deploy wiring, parity drill, and handover passed. Confirmed official LitePSMWrapper token identity, USDC -> USDS -> USDC round trip, fee/halt and 6/18-decimal handling, reverse budget/refund, balance/allowance residue, Strategy actual-spend accounting, and concrete-adapter deploy binding. Slither reported no substantive converter finding. Coverage instrumentation fails on inherited test-tree stack/Yul depth limits, so it is separated from required Foundry tests as a non-blocking measurement |
| V13 | 2026-08-05 | jpydf-v2 / develop (docs worktree at origin/develop) | `629e1c05` | forge 1.7.1 local | none | `forge test --match-path 'test/MorphoV2*.t.sol'` (30 passed); `forge test --match-path test/DeployLiquity2StrategySelector.t.sol` (34 passed) | Claude | PASS: MorphoV2Strategy 29 tests, MorphoV2BackingRatio 1 test, deploy selector 34 tests. Confirmed hard-zero max\* operation, deposit rejection recovery (cap / receive gate / zero-share / lying return), fail-soft withdraw (liquidity short / send gate / mismatch / zero burn), donation exclusion, immediate loss reflection, staged emergency recovery with `maxShares` and donated-share recovery, bounded `forceDeallocate` penalty with `_ownShares` resync, self-only isolated frames, reentrancy blocking, and `morpho-v2` deploy binding with Day-1 branch policy |
| V21 | 2026-08-08 | jpydf-v2 / `fix/preaudit-morpho-pricing-rails` | `825e9674` | forge 1.7.1 local | none | affected 5 suites; fast PR gate; full local gate; `forge build --sizes`; `cloc 2.06`; `git diff --check` | Codex | PASS: affected 253, fast 1,536, full local 1,589; all with 0 failed / 0 skipped. Verified fee-on-transfer receiver delta, Strategy receipt/cache ambiguity, and unavailable/recovering Sky quotes. Vault runtime 23,047 bytes (margin 1,529); full body 5,219 nSLOC |
| PRELIM-M02 | 2026-08-12 | jpydf-audit / `audit/preliminary-m02-remediation` | source `fe3d3d0` + M-01/M-02 overlays | forge 1.7.1 local | none | Sky converter/strategy focused; compatibility mocks; fast PR gate; production size gate; pre-fix mutation; `forge fmt --check`; `git diff --check` | Codex | PASS: focused/compat 35, fast 1,547, all with 0 failed / 0 skipped. The price-feed integration regression failed before the fix and passed after remediation. Sky Strategy runtime 20,173 bytes (margin 4,403); converter runtime 5,596 bytes (margin 18,980) |
| PRELIM-L01 | 2026-08-12 | jpydf-audit / `audit/preliminary-l01-remediation` | source `fe3d3d0` + M-01/M-02/L-01 overlays | forge 1.7.1 local | none | CollateralVault focused; push-model invariant; fast PR gate; production size gate; pre-fix mutation; production-source `forge fmt --check`; `git diff --check` | Codex | PASS: Vault focused 197, invariant 4, fast 1,547; all with 0 failed / 0 skipped. Before the fix, the owner-retry idempotence regression failed with `RequestNotFound`; after remediation it passed. Vault runtime 23,032 bytes (margin 1,544). The test file has unrelated pre-existing fmt drift, so the full-file fmt gate was not applied; the changed block and production sources were checked separately |
| PRELIM-L02 | 2026-08-12 | jpydf-audit / `audit/preliminary-l02-remediation` | source `fe3d3d0` + M-01/M-02/L-01/L-02 overlays | forge 1.7.1 local | none | active-feed constructor focused; deploy selector; fast PR gate; production size gate; pre-fix mutation; `forge fmt --check`; `git diff --check` | Codex | PASS: focused 129, fast 1,549; all with 0 failed / 0 skipped. Before the fix, a Standard feed deployed against an expired shared provider and the regression failed; after remediation Standard / dwstETH both revert `InvalidInitialPrice`, while deployment succeeds after fresh JPY recovery. DFUSDC runtime 3,095 bytes (margin 21,481); DFWstETH runtime 3,492 bytes (margin 21,084) |
| PRELIM-L03 | 2026-08-12 | jpydf-audit / `audit/preliminary-l03-disposition` | source `fe3d3d0` + M-01/M-02/L-01/L-02 overlays + L-03 resolution tests/docs | forge 1.7.1 local | none | CollateralVaultStrategy focused; fast PR gate; report-recommendation mutation; `forge fmt --check`; `git diff --check` | Codex | PASS: focused 125 and fast 1,550, all with 0 failed / 0 skipped. The report's `updatedAt = block.timestamp` mutation advanced the cache timestamp from `1` to `86400` and made the partial-recovery non-renewal regression fail as intended. Production source is unchanged; recovery of both live reads restores pricing availability immediately, while permissionless refresh repopulates the cache |
| PRELIM-L03-FU | 2026-08-12 | jpydf-audit / `agent/correct-l03-writeoff-recovery-evidence` | source `fe3d3d0` + M-01/M-02/L-01/L-02 + corrected L-03 overlay | forge 1.7.1 local | none | stale-cache full-writeoff regression; CollateralVaultStrategy focused; fast PR gate; five-overlay reconstruction; `forge fmt --check`; `git diff --check` | Codex | PASS: focused 126 and fast 1,551, all with 0 failed / 0 skipped. A full writeoff reflects confirmed accounting loss but does not restore pricing availability while live valuation remains unreadable. Production source is unchanged; five-overlay reconstruction reports zero drift, missing, and undecided files |
| PRELIM-SOURCE-SYNC | 2026-08-12 | jpydf-v2 / `agent/sync-preliminary-audit-remediations` | develop `4f236e74` + M-01/M-02/L-01/L-02/corrected L-03 overlays | forge 1.7.1 local | none | 9 affected suites; push-model invariant; fast PR gate; production size gate; changed-source `forge fmt --check`; `git diff --check`; audit snapshot comparison | Codex | PASS: focused 276; invariant 4 (500 runs / 25,000 calls each); fast 1,572 across 82 suites; all with 0 failed / 0 skipped. Of 30 affected files, 23 including all contracts/tests byte-match the audit snapshot; 7 docs retain identified post-freeze source updates outside the overlay hunks. Runtime sizes: Vault 23,032 bytes (margin 1,544), Sky Strategy 20,173, converter 5,596, DFUSDC 3,095, DFWstETH 3,492 |
| VAULT-SOLVENCY-20260826 | 2026-08-26 | jpydf-v2 / `codex/fix-collateral-vault-solvency-guard` | base `3cde535c` + working tree | forge 1.7.1 local | none | Vault / Strategy / CollateralYieldZapper focused; push-model invariant; fast PR gate; production size gate; `forge fmt --check`; `git diff --check` | Codex | PASS: focused 234 (59 + 127 + 48), invariant 7 (500 runs / 25,000 calls each), and fast 1,650, all with 0 failed / 0 skipped. Vault runtime 23,270 bytes (margin 1,306); storage remains 34 entries ending at slot 321. Confirmed pre-state blocking of all four underbacked user flows without token, permit, queue, or request mutation; fresh-cache rejection; automatic resumption after backstop or live-valuation recovery; and Zapper queue compatibility |
| ORCL-JPY-AGE-20260830 | 2026-08-30 | jpydf-v2 / issue #1837 worktree | contract candidate `8a0640a1` (base `3ff65edd`) | forge 1.7.1, Node 23.5.0, pnpm 8.15.8 local | none | `forge test --match-path 'test/PriceFeedProxy*.t.sol'`; `forge test --match-path test/PriceFeedPlaceholder.t.sol`; `forge test --match-path test/RedemptionHelper.t.sol`; `forge test --match-path test/RedemptionHelperOracleFailure.t.sol`; `env VITE_DEPLOYMENT_BINDING_SCOPE=sepolia pnpm --filter @jpydf/ops test:snapshot-chain`; `pnpm --filter @jpydf/ops test:alerts`; `pnpm --filter @jpydf/ops typecheck` | Codex | **Automated PASS / gate PARTIAL**: Proxy 140, Placeholder 11, Helper 8 plus 2 failure-specific tests, totaling 161 Solidity tests with 0 failed / 0 skipped. Safe-head snapshot and alert-classification tests plus Ops typecheck passed. Covered exact 30h, 30h−1s, missing/malformed/aged/runtime-invalid/return-bomb provenance, fresh automatic recovery, real-failure precedence, cache isolation, normal/emergency source confirmation, direct Registry and Helper refund paths, and the multi-branch allocation denominator. Labeled test-incident delivery to the escalation target, human receipt, same-key resolution, and mainnet deployment-tail readback are **not run**, so SYS-RISK-001/006 remain No-Go |
| ORCL-STETH-AGE-20260831 | 2026-08-31 | jpydf-v2 / `codex/oracle-launch-followups` worktree | base `8ee30c8b` + working tree | Node 23.5.0, pnpm 8.15.8, forge 1.7.1 local | none | `pnpm --filter @jpydf/ops ci:test`; `pnpm --filter @jpydf/ops typecheck`; `pnpm --filter @jpydf/ops lint`; `forge test --match-path test/DFBranchRiskParams.t.sol`; `forge test --match-path test/DeployBranchRiskInvariants.t.sol`; `forge fmt --check src/PriceFeeds/PriceFeedProxy.sol`; `git diff --check` | Codex | **Automated PASS / gate PARTIAL**: Ops 90 scripts, typecheck, 11 focused Foundry tests, PriceFeedProxy fmt, and diff check passed. Lint reported 0 errors and 5 pre-existing warnings. Reads both redemption auxiliary feeds at one safe head and verifies the stETH/ETH age boundaries at 86,399 / 86,400 / 89,999 / 90,000 seconds, continued monitoring after shutdown, fresh-round resolution, and a stable fingerprint that prevents a second P0 when observation composition changes to the urgent synthetic. Candidate-bound fork evidence, external delivery, human receipt and resolution, and Product / Protocol Risk sign-off are **not run** |

---

## 3. Aggregation (Coverage Dashboard)

**Scope**: 20 canonical system sources (18 Specs, 1 Launch Gate, and 1 Decision Record; table below). `CORE-*` uses the dedicated [Core-Requirements-Verification-Ledger.md](Core-Requirements-Verification-Ledger.md) as the source of truth; this ledger only references it and does not duplicate its records. [Multichain.md](../../archive/Multichain.md) (41 `MCHN-*` items) is **historical material and out of current scope** per ADR-004 / README, so it is excluded from verification (§15 explicitly declares this; it is an exclusion, not an omission). [LidoStrategy.md](../../archive/LidoStrategy.md) (47 `LIDO-*` items) and [EtherfiWeETHStrategy.md](../../archive/EtherfiWeETHStrategy.md) (13 `EFWEETH-*` items) were **archived** with their Solidity sources; both are likewise excluded from the active total and recorded below it (§9B / §9D).

| Document | FR | INV | SEC | GOV | EVT | ERR(ID) | Other IDs | TBD | ID total | Non-ID check rows | Verified |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| §4 System sources (Product Overview / Launch Risk Gate / ADR) | 8 | 5 | - | - | - | - | CON 5, NFR 6, RISK 10, ARCH 6, ADR 7 | 0 | 47 | 0 | 0 |
| §5 Liquity-v2-Core-Spec (🔵 Core Inheritance) | - | - | - | - | - | - | `CORE-*` uses the dedicated Core ledger as source of truth | 0 | 0 | 13 | 0 |
| §6 dToken (DTKN) | 10 | 10 | 7 | 5 | 5 | 0 | - | 3 | 40 | 13 | 0 |
| §7 CollateralVault (VAULT) | 19 | 14 | 10 | 4 | 15 | 0 | - | 3 | 65 | 41 | 9 |
| §8 Strategy (STGY) | 12 | 11 | 8 | 5 | 12 | 2 | - | 2 | 52 | 0 | 0 |
| §9 AaveV3Strategy (AAVE) | 7 | 5 | 5 | 3 | 4 | 5 | - | 8 | 37 | 0 | 0 |
| §9A ERC4626Strategy (E4626) | - | - | 8 | - | - | - | - | - | 8 | 0 | 0 |
| §9C SkyUsdcSUsdsStrategy (SKY) | - | - | 11 | - | - | - | - | 0 | 11 | 0 | 11 |
| §9E MorphoV2Strategy (MV2) | 5 | 3 | 7 | - | - | - | - | 0 | 15 | 0 | 15 |
| §10 Oracle (ORCL) | 16 | 14 | 8 | 5 | 12 | 0 | - | 6 | 61 | 16 | 7 |
| §11 Zapper (ZAP) | 15 | 9 | 7 | 3 | 1 | 0 | - | 10 | 45 | 11 | 33 |
| §12 Parameters (PRM) | - | 7 | - | - | - | - | parameter IDs 16 | 0 | 23 | 15 | 6 |
| §13 Treasury (TRSY) | 9 | 6 | - | - | 8 | 0 | - | 3 | 26 | 6 | 0 |
| §13A SPAdditionalRewardDistributor (SPARD) | 9 | 8 | - | - | 7 | 0 | - | 4 | 28 | 0 | 0 |
| §13B BorrowReferralRewardDistributor (BRRD) | 9 | 9 | - | - | 7 | 0 | - | 5 | 30 | 0 | 0 |
| §13C SPDepositReferralRewardDistributor (SPDRD) | 10 | 10 | - | - | 8 | 0 | - | 5 | 33 | 0 | 0 |
| §13D InterestRouter (IRTR) | 5 | 6 | 5 | 5 | 3 | 0 | - | 6 | 30 | 1 | 0 |
| §13E PILAllocator / UniV4MerklInitiative (PILA) | 16 | 8 | 6 | 6 | 7 | 0 | - | 8 | 51 | 0 | 38 |
| §14 Frontend (FRNT) | 36 | 4 | 8 | 5 | 3 | 6 | - | 9 | 71 | 3 | 1 |
| **Total (active)** | **186** | **129** | **90** | **41** | **92** | **13** | **50** | **72** | **673** | **119** | **120** |
| §9B LidoStrategy (LIDO, archived) | 9 | 10 | 8 | 3 | 5 | 5 | - | 7 | 47 | 0 | 39 |
| §9D EtherfiWeETHStrategy (EFWEETH, archived) | - | - | 13 | - | - | - | - | 0 | 13 | 0 | 13 |
| §15 Multichain (MCHN, excluded) | 13 | 8 | 6 | 5 | 6 | - | - | 3 | 41 | 1 | - |

- **IDs under verification** = 673 - open TBD. The Resolved / open / conditional / deferred breakdown of the 72 active TBD items (the archived §9B contributes a further 7, excluded) is governed by each document's TBD register; open gates are outside verification scope. `CORE-*` ID totals and verification status are governed by [Core-Requirements-Verification-Ledger.md](Core-Requirements-Verification-Ledger.md) and are not included in this ledger's active total.
- The "Verified" column is the number of IDs whose rows are all PASS or N/A. Update per campaign.
- **ORCL-STETH-AGE-20260831 update**: Reconciled seven IDs that already existed in the authoritative Oracle specification but were missing from this ledger—`ORCL-FR-016`, `ORCL-INV-013..014`, `ORCL-SEC-008`, and `ORCL-EVT-010..012`—and added `SYS-RISK-010`. §10 FR / INV / SEC / EVT / ID total changes **15→16 / 12→14 / 7→8 / 9→12 / 54→61**; §4 RISK / ID total changes **9→10 / 46→47**; active ID total changes **665→673**. The existing campaign already exercised the success and failure paths for `ORCL-EVT-011`, so §10 / active Verified changes **6→7 / 119→120**. Automated safe-head age monitoring and the 86,400-second warning / exact 90,000-second P0 / fresh-round resolution tests pass, but candidate-bound fork evidence, external delivery, human receipt and resolution, and Product / Protocol Risk sign-off are not complete. Non-ID check-row counts are unchanged.
- **ORCL-JPY-AGE-20260830 update**: Added `PRM-ORACLE-008` as a full verification row. §12 parameter IDs / ID total change **15→16 / 22→23**, and active Other IDs / ID total change **48→49 / 664→665**. Added one non-ID Oracle ERR row for the 30h / invalid-provenance path, changing §10 / active non-ID checks **15→16 / 118→119**. Automated tests passed, but the requirement rows remain PARTIAL because human-delivery evidence is not run; Verified counts do not change.
- **VAULT-SOLVENCY-20260826 update**: Added `VAULT-SEC-010` and unit-verified the pre-state full-backing guard for all four user flows using confirmed assets without valuation cache. §7 SEC / IDs / non-ID / Verified change **9→10 / 64→65 / 40→41 / 8→9**; active totals change **88→89 / 663→664 / 117→118 / 118→119**. `SYS-RISK-002` remains No-Go until the Vault upgrade and active-feed price-propagation, reserve-protection, and external-monitor integration evidence are complete.
- **V21 update (2026-08-08)**: Remediated the additional variants from the cross-skill review. VAULT-FR-002 now tracks receiver delta, VAULT-FR-005 invalidates ambiguous declared/received cache state, ZAP-FR-006 / ZAP-SEC-005 cover fee-on-transfer minimums, and SKY-SEC-011 separates unavailable quotes from measured zero. The §9C dashboard had omitted existing SKY-SEC-008..010; reconciling those three plus new 011 changes 7→11 and adds four to active SEC / IDs / Verified.
- **V22 update (2026-08-19)**: Synced #1556 B-1 / B-2 (the two `FAIL_CURRENT_LEDGER_NORMATIVE_SOURCE_CONTRADICTION` rows) to their normative sources. `PRM-INV-007`'s former wording `bufferFloor <= bufferTarget` compared incompatible units, and the normative Parameter Catalog had already replaced it with the required-buffer formula `max(managedUnderlying * bufferTargetBps / 10000, bufferFloor) + pendingWithdrawals`. `E4626-SEC-008`'s former wording also routed Underlying rewards to Treasury, while the normative ERC4626Strategy spec pushes them to the Vault buffer. Neither is a contract defect: the implementation already matches the normative sources, and only the ledger wording lagged. Seven focused tests were re-run on develop 8be5bd43 and all passed (`test_SetBufferConfig_RevertAboveBpsAndState`; `test_Allocate_DistributesByWeightBps`; `test_Allocate_ZeroTargetBpsUsesAbsoluteFloorAndConfigCorrectionRecovers`; `test_TransferYieldToTreasury_ReservesConfiguredBufferTarget`; `test_ClaimMerklRewards_SweepsERC4626RewardToTreasuryWithoutAccountingImpact`; `test_ClaimMerklRewards_PushesUnderlyingRewardToVaultWithoutReducingPrincipal`; `test_ClaimMerklRewards_RejectsERC4626ShareTokenBeforeDistributorCall`). `PRM-INV-007` moved from Not run to PASS, so §12 Verified goes **5 to 6** and active Verified **117 to 118** (the active ID total of 663 is unchanged). No implementation or tests were added; only ledger wording and classification changed.
- **V23 update (2026-08-19)**: Adjudicated the remaining #1556 sections A / D / C and reflected them in the normative Zapper.md (jp/en) and this ledger (Owner-approved). **A-1**: the `VAULT-FR-004` cooldown finding is ruled **no contradiction** — the normative CollateralVault.md defines `M` as managed assets, not the moved amount (cooldown is only not consumed on the fail-closed `M == 0` early return; a normal run with `excess == 0` consumes it). No row or implementation change; the row returns to the ordinary verification queue (Not run). **A-2**: `ZAP-INV-001` / `ZAP-GOV-002` resolved by a normative revision that makes the `AddRemoveManagers`-inherited per-trove delegation authorizations (slot 0 `addManagerOf` / slot 1 `removeManagerReceiverOf`) an explicit exception. These mappings are a live authorization state read by seven guard sites; removing them would let any address exercise the manager permission the Zapper holds. `forge inspect` storage layout (exactly 3 slots, re-run 2026-08-19) is the machine evidence, and the verification means moved from manual to machine inspection after the 2026-06-21 manual review missed both mappings. **A-3 (Owner Decision)**: narrowed `ZAP-INV-008` / `ZAP-SEC-001` to user-facing functions that move value or make untrusted external calls, with `setAddManager` / `setRemoveManager` / `setRemoveManagerWithReceiver` as explicit exceptions. Rationale: (1) all three perform only the owner check with no untrusted external call and no value movement, (2) `AddRemoveManagers` is unmodified liquity/bold v1.11.0 upstream and drew no finding in the external audit (Zapper / route 865 nSLOC scope), (3) `setRemoveManager` calls `setRemoveManagerWithReceiver` internally so naive double-attachment self-locks, and editing the shared base also touches `BorrowerOperations`. **D-1**: revised the `ZAP-INV-003` / `ZAP-SEC-003` residue condition to "stETH residue carrying shares must be returned; only zero-share nominal dust of at most 2 wei may remain". stETH balances are share-derived: at share price > 1 a 1–2 wei nominal balance corresponds to 0 shares and cannot be removed by transfer (consistent with the 1-wei returns measured on Sepolia). **C-1**: recorded in the `FRNT-SEC-001` note that the `nanoid` GHSA-2v37-7h3g-55p8 detected 2026-08-13 is resolved by the 3.3.18 override from #1547 (outside the `<3.3.18` advisory range); the row itself stays Not run as a release gate. No PASS-count or dashboard changes (the six affected rows keep their status with evidence/wording updates only; `FRNT-SEC-001` / `VAULT-FR-004` remain Not run). No Solidity or test changes.
- **PRELIM-M02 update (2026-08-12)**: Refined SKY-SEC-011 for preliminary finding M-02. An explicit Sky reverse-route halt continues principal-capped 1:1 valuation without recognizing unrealized yield. Invalid fee, status-read failure, and every other quote failure remain fail-closed and are not inferred to be halts. Requirement and Verified totals are unchanged.
- **PRELIM-L01 update (2026-08-12)**: Refined VAULT-FR-006 for preliminary finding L-01. A retry for an existing, settled request returns `0` without a second transfer, accounting mutation, or event; an unissued ID still reverts with `RequestNotFound`. Permissionless triggering and fixed owner payout remain unchanged. Re-certifying VAULT-FR-006 updates §7 / active Verified from **2 to 3 / 110 to 111**; requirement-ID totals are unchanged.
- **PRELIM-L02 update (2026-08-12)**: Added ORCL-INV-012, requiring every active DF feed constructor to seed a primary, nonzero `lastGoodPrice`. An unhealthy expired shared-JPY episode rejects deployment even when an unregistered feed's shutdown call is caught, and fresh recovery restores deployability. §10 INV / IDs / non-ID checks / Verified change **11→12 / 53→54 / 14→15 / 5→6**; active totals change **126→127 / 662→663 / 116→117 / 111→112**. The stale base in the IDs-under-verification formula is also reconciled to the dashboard total, **663**.
- **PRELIM-L03 update (2026-08-12)**: Rejected preliminary L-03's timestamp-refresh proposal. A partial receipt is not a full valuation of the remaining Strategy position; advancing `updatedAt` would let repeated small recoveries indefinitely renew an old high cache that may include unobserved loss. VAULT-FR-005 / VAULT-INV-005 now state that TTL remains anchored to the last full valuation, expiry fails closed, availability returns immediately when both live valuation reads recover, and permissionless full refresh repopulates the cache. Incident writeoff reflects confirmed accounting loss but does not restore availability while valuation remains unreadable; a follow-up unit test fixes that boundary. Requirement-ID and dashboard Verified totals are unchanged.
- **VAULT-RECERT-20260812 update**: Recertified five IDs—VAULT-FR-009 / FR-019 / INV-009 / INV-012 / INV-014—with unit and invariant evidence, raising VAULT Verified from 3 to 8 and the active total from 112 to 117. VAULT-FR-016 has complete unit/invariant evidence and remains PARTIAL only for its pinned-mainnet-fork requirement.
- **V10 update (2026-07-07)**: Added EFWEETH-SEC-014 and updated the active ID total from **615 to 616**. `WeETHWithdrawAdapter` is now included as first-party production source / audit scope and marked PASS based on Etherfi focused tests, deploy selector tests, build, and diff check.
- **V11 update (2026-07-07)**: Active ID total remains **616**. Added a DF-specific identity marker to `WeETHWithdrawAdapter` and marked the `EtherfiWeETHStrategy.initialize` marker-less ABI-compatible adapter rejection PASS based on focused tests, deploy selector tests, build, fmt, and diff check.
- **Artifact-boundary sync (2026-07-31)**: Added the existing missing `SYS-RISK-008`, the new `SYS-RISK-009`, and `ADR-007`, updating the active ID total from **616 to 619**. The rows remain Not run because operational Evidence has not been collected.
- **Ledger sync (2026-07-26, applied to this English ledger 2026-08-05)**: Added the SPARD / BRRD / SPDRD INV rows (**6**) and EVT rows (**22**) that exist in the consolidated Reward-Distributors source of truth, matching the Japanese ledger baseline. All 28 added rows are `BLOCKED(unimplemented)` because the three modules are unimplemented. This does not change the V13 baseline: 634 + 28 = **662**. The interim §15.1 group-table placeholder for these IDs is removed in the same change.
- **V19 update (2026-08-06)**: Archived §9B `LidoStrategy` (`LIDO-*`, 47 IDs) and §9D `EtherfiWeETHStrategy` (`EFWEETH-*`, 13 IDs), moving the active ID total from **718 to 658** and active Verified from **158 to 106**. This is an **archival, not a deletion**. The Solidity sources moved to `contracts/src/Strategies/archive/` and their tests to `contracts/test/archive/`; both still compile and pass (84 tests). Both Strategies take a structurally WETH underlying; PR #1424 removed the deploy selector entries that bound them, and branch 0's underlying then moved WETH -> wstETH, so no branch can supply a WETH underlying. Both surfaces were covered by the external audit completed 2026-08-05 (audited identity `0c7766e0`); their rows and IDs are retained below the active total so no requirement silently disappears from audit traceability. `LIDO-*` and `EFWEETH-*` are frozen historical IDs and must not be reused or cited as active scope. Reactivation requires a new activation package and a fresh audit-scope change.
- **V13 update (2026-08-05)**: Added §9E `MorphoV2Strategy` (MV2-FR 5 / MV2-SEC 7 / MV2-INV 3), updating the active ID total from **619 to 634**. All 15 rows are marked PASS(V13) based on the merged `MorphoV2Strategy.t.sol` / `MorphoV2BackingRatio.t.sol` / `DeployLiquity2StrategySelector.t.sol` runs.
- **V14 update (2026-08-06)**: A pre-send implementation-gap check for the auditor scope delta found two requirements that existed in the implementation but not in this ledger. `ORCL-FR-015` (the dwstETH composite feed) is specified in the Oracle spec but the ledger stopped at ORCL-FR-014, and the Zapper's native-ETH on-ramp had no requirement ID at all while the Zapper spec still stated that DF has no native-ETH collateral flow. The JPY-freeze events `ORCL-EVT-007` / `ORCL-EVT-008` / `ORCL-EVT-009` (emitted by `JpyUsdRateProvider`, topics unchanged after the shared `JpyFreezeLib` extraction) were likewise specified but unrecorded. All are now tracked (`ORCL-FR-015`, `ORCL-EVT-007..009`, new `ZAP-FR-015`), taking the active ID total from **662 to 667** and Verified from **110 to 115**. No implementation or tests were added — only the requirement rows and the spec text.
- **V15 update (2026-08-06)**: `PILAllocator.sol` (235 nSLOC) and `Initiatives/UniV4MerklInitiative.sol` (174 nSLOC) sit inside the A full-review body as "Audited but gated production code" in [Contract-Audit-Scope-And-nSLOC](../guides/Contract-Audit-Scope-And-nSLOC.md), yet had no rows in this ledger at all. Section §13E now tracks the **51** `PILA-*` IDs (FR 16 / INV 8 / SEC 6 / GOV 6 / EVT 7 / TBD 8), taking the active ID total from **667 to 718** and Verified from **115 to 142**. Based on the merged `PILAllocator.t.sol` (16 passed) / `UniV4MerklInitiative.t.sol` (11 passed) / `DeployPILAllocatorPhaseA.t.sol` (9 passed) runs, **27 rows are PASS(V14)**, **16 rows with no directly targeting test stay Not run**, and the remaining 8 are TBD-register rows (outside verification). The Not-run rows are: 6 events lacking `expectEmit` (EVT-001/002/003/005/006/007 — the state transitions are covered elsewhere, but the topics are never asserted), 5 activation / upstream-connection governance rows (GOV-002..006), 2 missing static / manual review records (INV-005, INV-007), 2 Merkl-mainnet and blast-radius reviews (SEC-001, SEC-002), and the upstream-compatible epoch interface (FR-002). No implementation or tests were added.
- **V16 update (2026-08-06)**: Of the 16 Not-run rows in §13E, the **8** that a test can close are now PASS(V16). A new `test/PILAInitiativeParity.t.sol` (4 tests) imports the vendored upstream `IInitiative` / `IGovernance` from `lib/V2-gov` directly and compares the four hook selectors plus their tuple-expanded canonical signatures (PILA-INV-007), and the epoch surface's upstream selectors together with its 1-indexed origin and boundary behavior (PILA-FR-002). `expectEmit` assertions added to the existing tests close PILA-EVT-001 / 002 / 003 / 005 / 006 / 007. Verified goes from **142 to 150** (the 718 ID total is unchanged). Mutation checks: widening `IInitiative.UserState.unallocatedOffset` to `uint128` fails the parity tests, and swapping the `GuardianUpdated` argument order fails the event test. The remaining 8 Not-run rows are all activation, upstream-connection, or static-review-record items (GOV-002..006, INV-005, SEC-001, SEC-002) that Day-1 code cannot close.
- **V17 update (2026-08-06)**: Of the 8 remaining §13E rows, the **3** that a static review can close (PILA-INV-005 / SEC-002 / GOV-006) are now PASS(V17). All three prescribe `manual / static` verification; the implementation already matched the requirement and only the review record was missing. Against develop `a09d1620` we enumerated every external call (INV-005: the only interactions are `safeTransfer`, the initiative hook call, and the view `requireValidRecipient`; zero references to the forwarder or Core), the full authorization map (SEC-002), and the inheritance and upgrade surface (GOV-006: no proxy, no UUPS, zero `delegatecall`), transcribing each result into the row notes. Verified goes from **150 to 153** (the 718 ID total is unchanged). As a by-product, the §9 SEC-002 statement was found to omit `setGuardian` and 2-step ownership from what the owner can execute; both language specs are corrected to match the code (neither carries a fund path, so the claim itself still holds). The remaining 5 Not-run rows (GOV-002..005, SEC-001) are activation-package work that Day-1 code cannot close.
- **V18 update (2026-08-06)**: Fixed the `PRM-INV-006` deploy-guard mismatch that #1205 carried over from #859, and moved five §12 PRM-INV rows to PASS(V18). The guard in `DeployLiquity2.s.sol` checked `1 + URGENT_REDEMPTION_BONUS <= p.MCR`, but the Parameter-Catalog bound is on **SCR**; because PRM-INV-001 already forces `SCR < MCR`, the check was strictly weaker than the published invariant, and since `AddressesRegistry` only enforces `SCR > 100%`, the 102% floor was enforced nowhere on-chain. The guard now compares `p.SCR`, the invariant loop was extracted as `_requireBranchRiskInvariants`, and a new `test/DeployBranchRiskInvariants.t.sol` (8 tests) pins acceptance exactly at the bound, rejection below it, rejection for each other invariant, and that the loop reaches later branches. Mutation check: restoring the MCR comparison lets both under-bound SCR cases through. Verified goes from **153 to 158** (the 718 ID total is unchanged).
- **Ledger sync (2026-08-05, LIDO retirement)**: Reflecting the `LidoStrategy` retirement from the Day-1 deploy surface (WETH -> wstETH branch swap), the **39** §9B rows other than the retirement gate `LIDO-GOV-001` (still Not run) and the TBD register are marked `N/A(retired)`. This includes the newly added `LIDO-INV-010` and `LIDO-EVT-005` rows, which the §9B INV / EVT counts of 10 / 5 already assumed but which had no rows in this English ledger; both are now tracked in §9B (matching the Japanese ledger) instead of §15.1. Active ID total unchanged; Verified 71 -> **110** (§9B 0 -> 39), equal to the Japanese ledger. The source and spec will be archived (previously audited), not deleted.

> **Provenance of the totals above (final rebase 2026-08-06, `2e57cf76`).** This branch was
> originally cut from a `develop` whose pre-archive baseline was 634 / Verified 71. It has
> since been rebased twice, and its current baseline is `develop` at `2e57cf76`:
> **718 / Verified 158**, with §9B Verified 39 and §9D Verified 13. The previous rebase
> point (`f41f2db9`) was 662 / Verified 110; the difference is the 51 §13E `PILA-*` IDs and
> the 5 `ORCL-FR-015` / `ZAP-FR-015` / `ORCL-EVT-007..009` IDs added by the pre-send
> implementation-gap check for the auditor scope delta.
>
> The archived rows were removed from the active total by this invariant. **These two rows
> need recomputing every time the develop-side totals move, and git merges the dashboard
> cleanly, so no conflict marker will prompt it.**
>
> - `active ID total = 718 - 60 = 658` (§9B 47 + §9D 13)
> - `active Verified = 158 - 39 - 13 = 106`
>
> Both §9B and §9D leave the active total, so their Verified counts leave with them.
> Subtracting only §9D would leave the total counting Verified IDs it no longer contains.
> The two rows are retained immediately below the total, with their own Verified figures
> intact, so no coverage silently disappears.
>
> `LIDO-EVT-005` is an in-§9B row marked `N/A(retired)` in both languages and is **not**
> duplicated in §15.1; that duplicate delta-trace line was removed upstream and must not be
> reintroduced, or the ID is double-counted.

---

## 4. System Requirements, Launch Risk Gate, and Architecture Decisions

Sources of truth: [Product-Overview.md](../../protocol/product/Product-Overview.md) for `SYS-FR-*`, `SYS-CON-*`, `SYS-NFR-*`, `SYS-INV-*`, and `ARCH-*`; [Mainnet-Launch-Risk-Gate.md](../../protocol/launch/gates/Mainnet-Launch-Risk-Gate.md) for `SYS-RISK-*`; and [Architecture-Decision-Records.md](../../protocol/product/architecture/Architecture-Decision-Records.md) for `ADR-*`. System-level requirements decompose into component requirements (traceability in Product Overview §13). Many rows in this section are verified by "completion of decomposed component rows + cross-system integration / inspection."

### 4.1 System Functional Requirements (SYS-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SYS-FR-001 | Issue JPYdf against overcollateralization (including 1 Tx completion) | Decomposition (DTKN-FR-004 / VAULT-FR-001,010,011 / ZAP-FR-001..004 / 🔵Core) + integration (ledger-defined) | ☐ | ☐ | | Not run | |
| SYS-FR-002 | Physical Underlying redemption from dToken (shortfall uses delayed redemption + claim) | Decomposition (DTKN-FR-005 / VAULT-FR-002,003,006 / ZAP-FR-006,010) + integration (ledger-defined) | ☐ | ☐ | | Not run | |
| SYS-FR-003 | External collateral deployment and protocol monetization of yield (push model) | Decomposition (VAULT-FR-004,005,007,008,009 / STGY-FR-001..005,010 / AAVE-FR-*) + integration (ledger-defined) | ☐ | ☐ | | Not run | |
| SYS-FR-004 | Autonomous JPYdf peg correction (redemption / 3-layer liquidation / SP) | 🔵 Core inheritance (§5 Core rows + upstream suite) (ledger-defined) | ☐ | ☐ | | Not run | |
| SYS-FR-005 | JPY-denominated prices, backing-ratio reflection, and failsafe degradation | Decomposition (ORCL-FR-* / VAULT-FR-016..018 / 🔵 lastGoodPrice and shutdown) + integration (ledger-defined) | ☐ | ☐ | | Not run | |
| SYS-FR-006 | Dormant bridge-ready token surface; no active Day-1 bridge / other-chain issuance | Unit + deploy manifest evidence (`bridgeMinterCount == 0`, no pending proposal, no connected bridge adapter) | ☐ | ☐ | `JpydfTokenTest::test_BridgeReadinessIsDormantAfterCoreSetup`; `JpydfTokenTest::test_BridgeRolesMustBeContractsAndSeparated`; `JpydfTokenTest::test_BridgeMintRejectsProtocolRecipients` | PASS(unit) | Deploy manifest evidence remains open. Day-2+ minter registration / route open / cap ramp are not covered by this Day-1 row; they require [Bridge-Minter-Activation-Gate](../../protocol/operations/runbooks/Bridge-Minter-Activation-Gate.md) Stage A/B/C |
| SYS-FR-007 | GOV controls parameters, whitelist, upgrade, and oracle source | Decomposition (VAULT-FR-008,009,012,014,015 / DTKN-FR-006,008,009 / STGY-FR-011 / ORCL-FR-*) (ledger-defined) | ☐ | ☐ | | Not run | |
| SYS-FR-008 | UX 1 Tx aggregation (helper; core works without it) | Decomposition (ZAP-FR-001..010,013,014) + ARCH-005 row | ☐ | ☐ | | Not run | |

### 4.2 Constraints (SYS-CON)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SYS-CON-001 | Core accounting parity and JPYdf canonical surface (old BOLD public/API names are forbidden; base deltas are governed by Core spec §2.2 / §5.1) | Core JPYDF surface guard + Core ledger diff/parity rows (ledger-defined) | ☐ | ☐ | | Not run | Exception path = guard FAIL after old BOLD surface re-entry |
| SYS-CON-002 | Core external IFs are only two: collateral ERC-20 (dToken) and PriceFeedProxy | inspection (deploy wiring inspection of core reference addresses) (ledger-defined) | ☐ | N/A | | Not run | N/A: configuration inspection only (dependency enumeration, no counterexample trial defined) |
| SYS-CON-003 | Collateral is 18dec ERC-20 (non-18dec is wrapped by dToken) | DTKN-INV-001 / DTKN-FR-003 row + deploy inspection | ☐ | ☐ | | Not run | |
| SYS-CON-004 | JPYdf token is non-upgradeable; existing `mint` / `burn` authority is Core-only; bridge supply is isolated to dormant `bridgeMint` / self-burn `bridgeBurn` with zero Day-1 minters | inspection + mint authority enumeration + dormant bridge state evidence (ledger-defined) | ☐ | ☐ | `JpydfTokenTest::test_BridgeMinterLifecycleUsesTimelockAndSelfBurn` | PASS(unit) | Deploy manifest evidence remains open. Same root as SYS-INV-003 |
| SYS-CON-005 | Day-1 is Ethereum only with 8 collateral branches | deploy script / Parameters §1 cross-check (ledger-defined) | ☐ | N/A | | Not run | N/A: deploy configuration cross-check only |

### 4.3 Quality Attributes and Non-Functional Requirements (SYS-NFR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SYS-NFR-001 | Security (core accounting parity, ledgered JPYdf deltas; 🟢 satisfies §9 INV / §10 threat model) | Core JPYDF surface guard + Core ledger + all INV/SEC rows in this ledger (ledger-defined) | ☐ | ☐ | | Not run | |
| SYS-NFR-002 | Decentralization (core operations permissionless; only exception is GUARDIAN pause at dToken layer entry/exit) | integration (permissionless execution of operations) + VAULT-FR-014 row | ☐ | ☐ | | Not run | Exception path = confirm GOV cannot stop core operations |
| SYS-NFR-003 | Upgradeability (dToken/Vault/Strategy=UUPS + shared Timelock 12h; PriceFeedProxy=non-upgrade; Core/JpydfToken=non-upgradeable) | DTKN-FR-008 / VAULT-FR-015 / STGY-FR-009 / ORCL rows + deploy configuration inspection | ☐ | ☐ | | Not run | |
| SYS-NFR-004 | Availability (oracle failure -> lastGoodPrice -> shutdown / Strategy failure -> writeoff, emergencyWithdraw / buffer shortfall -> delayed redemption) | ORCL-FR-004 / VAULT-FR-002,006,009 / STGY-FR-004,005 rows + integration | ☐ | ☐ | | Not run | |
| SYS-NFR-005 | Observability (`*-EVT-*` enables off-chain accounting, monitoring, and alerting) | Aggregate of all EVT rows (ledger-defined) | ☐ | N/A | | Not run | N/A: aggregate of EVT rows; individual exception paths are in each EVT row |
| SYS-NFR-006 | Cost efficiency (1 Tx aggregation, push model, fixed destinations/fixed ratios) | ZAP rows and STGY rows + gas snapshot (optional) (ledger-defined) | ☐ | N/A | | Not run | N/A: performance attribute with no exception boundary |

### 4.4 System Invariants (SYS-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SYS-INV-001 | Overcollateralization (each Trove stays at or above MCR; undercollateralized Troves are liquidated) | 🔵 Core invariants (§13 trace) | ☐ | ☐ | | Not run | |
| SYS-INV-002 | dToken claim-right consistency (Underlying floor conversion of total supply <= Vault + Strategy total Underlying; impairment propagates as backingRatio<1e18 into price) | DTKN-INV-002,005,006 / VAULT-INV-* (§13 trace) | ☐ | ☐ | | Not run | |
| SYS-INV-003 | JPYdf supply-path closure (Core `mint` / `burn` remains Core-only; bridge minter count is zero on Day-1) | 🔵 Core mint/burn path + dormant bridge evidence + CORE-BT-INV-004 remote supply accounting gate + deployment review | ☐ | ☐ | `JpydfTokenTest::test_BridgeReadinessIsDormantAfterCoreSetup`; `JpydfTokenTest::test_BridgeMinterLifecycleUsesTimelockAndSelfBurn` | PASS(unit) | Deployment review remains open. Exception path = non-Core cannot call Core `mint`; non-minter cannot call `bridgeMint`. Day-2+ route/cap activation requires Stage A/B/C gate evidence |
| SYS-INV-004 | Branch isolation (bounded; correlation through shared JPYdf debt token is explicitly out of scope) | 🔵 Core + §10 threat model (integration for isolated parts) | ☐ | ☐ | | Not run | |
| SYS-INV-005 | Core delta boundary (old BOLD surface forbidden; allowed deltas limited to Core spec `CORE-MOD-*` / §5.1 catalog) | Core JPYDF surface guard + manual diff review | ☐ | ☐ | | Not run | |

### 4.5 Mainnet Launch Risk Gate (SYS-RISK)

For each row, "happy path" = the inspection/test/runbook satisfying the gate exists and has actually run; "exception path" = the specified defense works when the risk scenario fires.

| ID | Risk and gate (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SYS-RISK-001 | Shared JPY/USD dependency. Gate: `PRM-ORACLE-001` / `008`, normal-redemption-only 30h stop, provenance fail-closed behavior, safe-head synthetic, source-swap runbook, and disabled renounce | ORCL-FR-005 / ORCL-SEC-004,005, PRM-ORACLE-008 + monitor / manual | ☑ | ☑ | `PriceFeedProxyJpyRedemptionAgeTest`; `frontend/ops/src/lib/snapshot.test.ts`; `frontend/ops/scripts/alerts.test.ts` | PARTIAL(ORCL-JPY-AGE-20260830/automated; No-Go) | Automated tests and `ALRT-ORCL-016` code evidence passed. Labeled-incident escalation-target delivery, human receipt, and same-key resolution are not run. ORCL-TBD-001 retains non-JPY thresholds and JPY residual risks such as the maximum 96h window on normal and urgent paths |
| SYS-RISK-002 | Core does not directly know dToken backing breakage. Gate: pre-state blocking of all four user flows using live confirmed assets, correct Vault references for all active feeds, downward price propagation and recovery across loss/writeoff/backstop deposit/release, and protection against first-come reserve consumption require integration plus external monitoring | VAULT-SEC-010 / VAULT-FR-016,017 / ORCL-FR-014 rows + integration and external monitoring | ☑ | ☑ | `CollateralVaultTest::test_UserFlows_FailClosedWhenUnderbacked_AndResumeAfterBackstopRepair`; `test_UserFlowSolvencyGate_IgnoresFreshCacheAndRecoversFromConfirmedAssets` | PARTIAL(VAULT-SOLVENCY-20260826/unit; No-Go) | Unit evidence covers pre-state blocking, fresh-cache rejection, and backstop/live-valuation recovery. Remains No-Go until the Vault upgrade and all-active-feed price-propagation, reserve-protection, and external-monitor integration evidence are complete |
| SYS-RISK-003 | Treasury / SP reward path. gate: finalize parallel Distributor design (until finalized, additional SP rewards are treated as non-production) | TRSY rows (§13) + manual | ☐ | ☐ | | Not run | If TRSY is unimplemented, record BLOCKED(unimplemented) |
| SYS-RISK-004 | Async Strategy principal recovery. No active Strategy is asynchronous: `AsyncRequestStrategy` and its only two subclasses (Lido, Etherfi) are archived, and every active Strategy derives from `BaseStrategy` directly. Gate: a future async venue is a new proposal, activation package, and audit-scope change | Day-1 negative deploy/register inspection (no `lido` / `etherfi` strategy kind in `DeployLiquity2.s.sol`); archive inventory; legacy-instance recovery/unregister if inventory finds one | ☐ | ☐ | | Not run | Archived Lido / Etherfi code is not a reactivation candidate. Sources retained under `contracts/src/Strategies/archive/`, previously audited under `0c7766e0` |
| SYS-RISK-005 | Branch risk parameters are immutable after finalization and the margin is tight. Active branches finalize at deployment; for a reserved branch, the common Timelock finalizes the six risk values and compensation cap once after the exact Underlying is selected and before admission. Gate: mechanical verification of PRM-INV-* (SCR<MCR<CCR, 1+penalty<=MCR, urgent redemption bonus), finalizer / empty-state / shutdown-boundary checks, Registry / BO / TM synchronization, and final-value freeze review | §12 PRM-INV rows + Core ledger CORE-AR-FR-005 / INV-003 / SEC-002 (forge / deploy and activation scripts) | ☐ | ☐ | | Not run | Constants matching is the deploy gate for finalized active values and reserved bootstrap values. Verify reserved final values through the Manifest, `RiskParamsFinalized` receipt/event, Registry / BO getters, and TM block-pinned storage attestation or equivalent atomic-sync Evidence |
| SYS-RISK-006 | Redemption scans every branch and one feed fault can stop all. Gate: active/inert source no-revert / ABI / price / failure / JPY-provenance checks, path-specific Proxy fallback, and Helper failure propagation/refund | ORCL-FR-002,005,008 / ORCL-INV-006 + Proxy / Registry / Helper integration | ☑ | ☑ | `PriceFeedProxy*.t.sol` (140 passed); `PriceFeedPlaceholder.t.sol` (11 passed); `RedemptionHelper.t.sol` (8 passed); `RedemptionHelperOracleFailure.t.sol` (2 passed) | PARTIAL(ORCL-JPY-AGE-20260830/automated; No-Go) | Missing/malformed/aged provenance, real source failure, gas guard, source switch/emergency/resume, direct/Helper zero spend and refund, and the multi-branch denominator passed. Mainnet deployment-tail readback for every source and human alert delivery/resolution are not run |
| SYS-RISK-007 | A future XAUT candidate cannot be activated until wrapper/market depeg is reflected on-chain or an equivalently conservative package is approved. It has no current branch binding or Day-1 exposure | ORCL-FR-013 / ORCL-SEC-006 row + manual (activation package and monitoring) | ☐ | ☐ | | Not run | Candidate-only; no Day-1 authorization |
| SYS-RISK-008 | dToken `mintCap` is not a branch debt ceiling. Gate: docs, UI, and operations must not present cap as the JPYdf issuance limit; tests and inspection must confirm that debt increase against existing dToken collateral remains possible after a cap reduction | DTKN-FR-006 / CORE-BO-FR-001..003,006 + manual copy / operations-gate inspection | ☐ | ☐ | `frontend/ops/scripts/collect-market-liquidity-state.test.ts`; `frontend/ops/scripts/build-market-liquidity-plan.test.ts` | PARTIAL(tooling) | Removed legacy `borrowCapacity*` labels from the ops schema, fixed dToken cap headroom as nominal supply-cap headroom, and separated deposit pause into its own field and guard. Core debt increase after cap reduction and live UI / operations inspection remain open |
| SYS-RISK-009 | JPYdf has no symmetric automatic supply mechanism for upward deviation. Gate: calculate existing-collateral debt room, dToken cap headroom, and fee-inclusive new-debt capacity separately from live state, then assess cap-ramp delay and short-term premium as residual risk | Active Branch Cap Ramp Runbook + Core supply-path inspection. If a specific Contributor response is assumed, add its Policy, Commitment, and Evidence | ☐ | ☐ | `frontend/ops/scripts/collect-market-liquidity-state.test.ts`; `frontend/ops/scripts/build-market-liquidity-plan.test.ts` | PARTIAL(tooling) | Missing executable borrow capacity is explicit and fails closed to review / pause during an upward deviation. Borrower-specific live capacity, cap-ramp delay, and residual-risk approval remain open |
| SYS-RISK-010 | dwstETH redemption's `max(direct, derived)` can select a policy-fresh but stale-high derived leg from ETH/USD / stETH/ETH and reduce collateral delivered to the redeemer. Gate: `PRM-ORACLE-002` / `007`, the fail-closed policy, a 24.5h warning / exact 25h P0, and explicit Product / Protocol Risk approval | ORCL-FR-015 / ORCL-EVT-010, PRM-ORACLE-002 / 007 + monitor / manual | ☐ | ☑ | `frontend/ops/src/lib/snapshot.test.ts`; `frontend/ops/scripts/alerts.test.ts`; `frontend/ops/scripts/alert-delivery.test.ts` | PARTIAL(automated; No-Go) | Code evidence only for the age 88,200s warning, exact 90,000s P0, and resolution after a fresh round. Candidate-bound fork evidence, external delivery, human receipt, resolution, and Product / Protocol Risk sign-off are not complete |

### 4.6 Architecture Principles (ARCH) and Major Decisions (ADR)

Inspection-centered. Happy path = confirmation that principle/decision is reflected in implementation; exception path = detection mechanism for violations (CI, etc.) works.

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ARCH-001 | Core accounting parity principle (substitution centers on collateral ERC-20 and price feed; only JPYdf canonical surface and ledgered deltas are allowed) | Core JPYDF surface guard + diff review (ledger-defined) | ☐ | ☐ | | Not run | Same root as SYS-CON-001 |
| ARCH-002 | Separation of responsibilities (each layer does not know internals of other layers) | inspection (dependency-direction code review) (ledger-defined) | ☐ | N/A | | Not run | N/A: inspection of design principle; ARCH-001 CI handles violation detection |
| ARCH-003 | One-way dependency (core has only two generic external IFs) | inspection + deploy wiring inspection (ledger-defined) | ☐ | N/A | | Not run | Same root as SYS-CON-002 |
| ARCH-004 | Changes stay outside the core (Strategy replacement, source replacement, Zapper changes do not touch core; bridge supply is isolated to dormant token surface and zero Day-1 minters) | inspection + ORCL-FR-001..003 / VAULT-FR-008 rows + dormant bridge state evidence | ☐ | ☐ | | Not run | |
| ARCH-005 | Zapper is auxiliary (Core / dToken operate independently without it; direct operations produce the same result) | integration (equivalent direct operation without Zapper) (ledger-defined) | ☐ | ☐ | | Not run | |
| ARCH-006 | Explicit extension boundary: classify changes as UUPS upgrades, setter/whitelist additions, reference switches, or redeployment; keep mutability outside the non-upgradeable and post-finalization immutable assumptions of Core / JpydfToken / CollateralRegistry | inspection of code and configuration against the extension classification | ☐ | N/A | | Not run | The reserved-branch pre-activation one-shot finalization (CORE-MOD-013) is not a repeatable setter. N/A: design-boundary inspection; ARCH-001/004 and SYS-NFR-003 detect violations |
| ADR-001 | Liquity v2 base-parity fork (extensions outside; JPYdf canonical surface and ledgered deltas are governed by Core spec) | Same evidence as ARCH-001 row | ☐ | ☐ | | Not run | |
| ADR-002 | External collateral deployment is implemented in dToken + Strategy layers (core collateral = dToken) | integration (openTrove using dToken as collateral) + DTKN/VAULT rows | ☐ | ☐ | | Not run | |
| ADR-003 | Strategy uses push model (sendToVault / sendProfitToVault; Vault does not pull) | STGY-FR-002,003 / VAULT-FR-005 rows + inspection (no pull path) | ☐ | ☐ | | Not run | |
| ADR-004 | Day-1 has no active bridge; token remains bridge-ready | Dormant bridge state + SYS-CON-004 row | ☐ | ☐ | `JpydfTokenTest::test_BridgeReadinessIsDormantAfterCoreSetup`; `JpydfTokenTest::test_BridgeMinterLifecycleUsesTimelockAndSelfBurn`; `JpydfTokenTest::test_BridgeReadinessEventsExposeLifecyclePayloads` | PASS(unit) | Deploy manifest evidence remains open. Day-1 must have no registered bridge minter, no pending proposal, and no bridge adapter connection |
| ADR-005 | Oracle is replaceable via PriceFeedProxy (core fixed reference; source 12h timelock) | ORCL-FR-001..004 / ORCL-INV-001,002 rows | ☐ | ☐ | | Not run | |
| ADR-006 | On backing impairment, reflect confirmed loss immediately in price, preserve nominal 1:1 semantics while automatically blocking user flows that cannot prove full backing from live confirmed assets in the pre-state, resume automatically after backstop or Strategy recovery, and do not add Day-1 pro-rata settlement | ORCL-FR-014 / VAULT-SEC-010 / VAULT-FR-014,017 / `writeoffStrategyPrincipal` rows + integration | ☑ | ☑ | `CollateralVaultTest::test_UserFlows_FailClosedWhenUnderbacked_AndResumeAfterBackstopRepair`; `test_UserFlowSolvencyGate_IgnoresFreshCacheAndRecoversFromConfirmedAssets` | PARTIAL(VAULT-SOLVENCY-20260826/unit) | Automatic-guard unit evidence is complete. The Vault upgrade and price-propagation, reserve, and external-monitor integration evidence remain open No-Go conditions under [`SYS-RISK-002`](../../protocol/launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-002) |
| ADR-007 | Address upward peg deviation through existing Core borrowing and, when needed, a gated dToken cap ramp rather than a new reserve-backed mint path; accept a short-term premium as residual risk | SYS-RISK-008/009 + inspection for absence of a PSM/reserve-backed mint path and presence of cap-ramp gating | ☐ | ☐ | | Not run | The Protocol does not guarantee supply by a specific borrower or Contributor; APR changes borrowing cost and Redemption order but are not supply actions |

---

## 5. Liquity-v2-Core-Spec.md (🔵 Core Inheritance)

Source of truth: [Liquity-v2-Core-Spec.md](../../protocol/product/spec/Liquity-v2-Core-Spec.md). Detailed `CORE-*` verification uses [Core-Requirements-Verification-Ledger.md](Core-Requirements-Verification-Ledger.md) as the source of truth. This section only provides cross-ledger check rows. Verification is "no old BOLD surface re-entry" + "upstream/parity verification assets hold under DF parameters" + "individual verification of `CORE-MOD-*` deltas."

| # | Check item | Specified verification method (ledger-defined) | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Core JPYDF surface guard is green (zero old BOLD public/API names) and base deltas match Core spec §2.2 / §5.1 | ci-guard + Core ledger diff/parity rows | ☐ | ☐ | | Not run | Exception path = guard FAIL after old BOLD surface re-entry |
| 2 | upstream test suite (unit / invariant / fuzz) is all green under DF parameters | forge test (full actual local run) | ☐ | N/A | | Not run | Runtime skipped tests must be zero or have recorded identity |
| 3 | 🟡 MIN_DEBT = 100,000 JPYdf (§1-3) | unit (Constants value) + openTrove boundary | ☐ | ☐ | | Not run | Exception path = revert on open below MIN_DEBT |
| 4 | 🟡 Liquidation executor compensation cap: dwstETH 2 / dUSDC 1,000 units; reserved caps finalized before activation (0.5% rate remains Core standard; Gas Deposit remains standard 0.0375 WETH) (§0-1 / §5-6) | unit (Constants value and compensation calculation) | ☐ | ☐ | | Not run | |
| 5 | 🟡 Denomination = JPYdf (JpydfToken name/symbol and JPY-denominated price) (§0-1) | unit (name/symbol) + ORCL-INV-007 row | ☐ | N/A | | Not run | N/A: naming and quote-unit consistency check only |
| 6 | 🟢 Collateral = dToken wrapper (core treats dToken as normal ERC-20 collateral) | integration (deposit -> openTrove -> liquidation/redemption end to end) | ☐ | ☐ | | Not run | Same root as ADR-002 |
| 7 | 🟢 Oracle = through PriceFeedProxy (feed failure degrades to lastGoodPrice + shutdown) | ORCL-FR-004 row + integration | ☐ | ☐ | | Not run | |
| 8 | §10-1 Total debt identity (aggRecordedDebt + pendingAggInterest + aggBatchManagementFees + DefaultPool.getJpydfDebt() == sum entireTroveDebt) | invariant (upstream suite) | ☐ | ☐ | | Not run | |
| 9 | §10-2 CR constraints (ICR>=MCR liquidation, TCR>=CCR borrowing restriction, TCR<SCR shutdown) | unit / invariant (upstream suite, DF values) | ☐ | ☐ | | Not run | |
| 10 | §10-3 Liquidation penalty ordering (SP <= Redistribution <= 10% <= MCR) | PRM-INV-003/004 rows (§12) | ☐ | ☐ | | Not run | |
| 11 | §10-4 Batch invariant (debt:shares <= 1e9; kickFromBatch on violation) | invariant (upstream suite) | ☐ | ☐ | | Not run | |
| 12 | §10-5 SP invariant (SP_JPYDF_balance >= MIN_JPYDF_IN_SP) | invariant (upstream suite) | ☐ | ☐ | | Not run | |
| 13 | §10-6 Trove state invariant (debt>=MIN_DEBT=Active / 0<debt<MIN_DEBT=Zombie / 0=Closed or Liquidated) | unit / invariant (upstream suite under MIN_DEBT=100k) | ☐ | ☐ | | Not run | |

---

## 6. dToken.md (DTKN)

Source of truth: [dToken.md](../../protocol/product/spec/dToken.md). Target: `contracts/src/DToken.sol` / `IDToken.sol`.

### 6.1 Functional Requirements (DTKN-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DTKN-FR-001 | initialize (placeholder start, fixed vault/owner, cap=max, no reinitialization) | unit | ☐ | ☐ | | Not run | |
| DTKN-FR-002 | setTokenInfo (one-time, multiplier finalization, allowlist/decimals<=18/EOA rejection and all reverts) | unit, invariant=DTKN-INV-003/004 | ☐ | ☐ | | Not run | |
| DTKN-FR-003 | Underlying <-> dToken conversion (exact multiplication, floor on safe side, boundaries) | unit, fuzz=DTKN-INV-006 | ☐ | ☐ | | Not run | |
| DTKN-FR-004 | mint (vault-only, cap / unset guard) | unit, invariant=DTKN-INV-002/005 | ☐ | ☐ | | Not run | |
| DTKN-FR-005 | burn (vault-only, allowance-independent, insufficient-balance revert) | unit, invariant=DTKN-INV-002 | ☐ | ☐ | | Not run | |
| DTKN-FR-006 | setCap (Owner-only, can be below current supply, issued tokens preserved) | unit, invariant=DTKN-INV-005 | ☐ | ☐ | | Not run | |
| DTKN-FR-007 | permit (EIP-2612; DOMAIN_SEPARATOR follows actual name(); ERC-5267) | unit, integration | ☐ | ☐ | | Not run | integration = standard wallet signature verification succeeds |
| DTKN-FR-008 | Upgrade (UUPS, Owner-only, storage append-only) | unit, manual | ☐ | ☐ | | Not run | manual = storage layout review |
| DTKN-FR-009 | Owner transfer (2-step), pending cancel, renounce disabled | unit, manual | ☐ | ☐ | | Not run | |
| DTKN-FR-010 | Underlying allowlist (contract-only, before bind only, event) | unit, manual | ☐ | ☐ | | Not run | |

### 6.2 Invariants (DTKN-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DTKN-INV-001 | decimals() is always 18 (before and after finalization) | unit | ☐ | N/A | | Not run | N/A: constant view (no destructive operation exists) |
| DTKN-INV-002 | mint/burn are vault-only (Owner also cannot) | invariant | ☐ | ☐ | | Not run | |
| DTKN-INV-003 | setTokenInfo only when totalSupply==0; 4 values immutable after finalization | invariant | ☐ | ☐ | | Not run | |
| DTKN-INV-004 | _decimalMultiplier is 10**(18-dec) after finalization and 0 before finalization | unit | ☐ | ☐ | | Not run | |
| DTKN-INV-005 | mint only when totalSupply+amount <= cap (also confirm totalSupply <= cap is not a global invariant) | invariant | ☐ | ☐ | | Not run | |
| DTKN-INV-006 | Conversion consistency (exact multiplication, safe floor, zero dust on round trip for integer multiples) | fuzz | ☐ | ☐ | | Not run | |
| DTKN-INV-007 | vault immutable after initialize | invariant | ☐ | ☐ | | Not run | |
| DTKN-INV-008 | During unset phase, convertTo*/mint reverts with TokenInfoNotSet | unit | ☐ | ☐ | | Not run | |
| DTKN-INV-009 | Owner changes only on successful acceptOwnership and is unchanged by renounce | unit | ☐ | ☐ | | Not run | |
| DTKN-INV-010 | setTokenInfo succeeds only for allowlisted code>0; allowlist cannot be updated after finalization | unit | ☐ | ☐ | | Not run | |

### 6.3 Security Requirements (DTKN-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DTKN-SEC-001 | mint/burn restricted to vault (OnlyVault) | unit, invariant=DTKN-INV-002 | ☐ | ☐ | | Not run | |
| DTKN-SEC-002 | Allowance-independent burn is confined to vault | unit, manual | ☐ | ☐ | | Not run | |
| DTKN-SEC-003 | permit DOMAIN_SEPARATOR follows actual name (prevents permanent revert from placeholder fixation) | unit, integration | ☐ | ☐ | | Not run | |
| DTKN-SEC-004 | Prevent placeholder stranding (mint prohibited while unset) | unit, invariant=DTKN-INV-008 | ☐ | ☐ | | Not run | |
| DTKN-SEC-005 | Upgrade authority restricted to Owner | unit, manual | ☐ | ☐ | | Not run | |
| DTKN-SEC-006 | Prevent Owner authority loss (2-step and renounce disabled) | unit | ☐ | ☐ | | Not run | |
| DTKN-SEC-007 | Prevent incorrect Underlying bind (allowlist, EOA/undeployed rejection) | unit (same as DTKN-FR-010 / INV-010) | ☐ | ☐ | | Not run | |

### 6.4 Governance, Operations, and Upgrade Requirements (DTKN-GOV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DTKN-GOV-001 | Owner = GOV_MULTISIG (holder is only shared TimelockController 12h; single EOA prohibited) | manual (deploy configuration review) | ☐ | N/A | | Not run | N/A: configuration review item; unauthorized cases are covered by DTKN-FR/SEC rows |
| DTKN-GOV-002 | Owner transfer is 2-step; incorrect target can be canceled as pending | unit, manual | ☐ | ☐ | | Not run | |
| DTKN-GOV-003 | Owner renounce disabled in code (RenounceOwnershipDisabled) | unit | ☐ | ☐ | | Not run | |
| DTKN-GOV-004 | Owner timelock (not built in; holder=shared Timelock 12h; no emergency immediate operation; pause is Vault-side) | manual (assert Owner=Timelock) | ☐ | ☐ | | Not run | |
| DTKN-GOV-005 | allowlist deploy review (chainId, address, decimals, proxy, blacklist authority) | manual (mainnet deploy checklist) | ☐ | N/A | | Not run | N/A: deploy checklist execution record |

### 6.5 Event and Monitoring Requirements (DTKN-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DTKN-EVT-001 | TokenInfoSet (detect finalization, once only) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| DTKN-EVT-002 | CapUpdated(oldCap, newCap) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| DTKN-EVT-003 | ERC20 Transfer (mint: from=0 / burn: to=0) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| DTKN-EVT-004 | OwnershipTransferStarted / OwnershipTransferred | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| DTKN-EVT-005 | AllowedUnderlyingUpdated(underlying, allowed) | unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 6.6 Failure and Exceptional Behavior (§12 ERR, no ID)

Placeholder-phase behavior (each row = one row in doc §12 table; mark the firing evidence column ✅ when evidenced):

| # | Event | Expected behavior (doc §12) | Firing evidence | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | name()/symbol() in placeholder phase | placeholder values -> finalized values after finalization | ☐ | | Not run | |
| 2 | decimals() in placeholder phase | always 18 | ☐ | | Not run | May share evidence with DTKN-INV-001 |
| 3 | convertTo* in placeholder phase | TokenInfoNotSet revert | ☐ | | Not run | |
| 4 | mint in placeholder phase | TokenInfoNotSet revert | ☐ | | Not run | |

Error catalog (each error must actually fire in at least one test):

| # | Error | Trigger (reference) | Firing evidence | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | OnlyVault | mint/burn by non-vault (DTKN-SEC-001) | ☐ | | Not run | |
| 2 | TokenInfoNotSet | convert/mint while unset (DTKN-INV-008) | ☐ | | Not run | |
| 3 | CapExceeded | mint beyond cap (DTKN-FR-004) | ☐ | | Not run | |
| 4 | InvalidUnderlyingDecimals | decimals>18 in setTokenInfo (DTKN-FR-002) | ☐ | | Not run | |
| 5 | NotContract | EOA or undeployed target in setAllowedUnderlying / setTokenInfo | ☐ | | Not run | |
| 6 | UnderlyingNotAllowed | setTokenInfo for non-allowlisted Underlying | ☐ | | Not run | |
| 7 | TokenInfoAlreadySet | repeated setTokenInfo / setAllowedUnderlying after finalization | ☐ | | Not run | |
| 8 | UnderlyingMismatch (Vault side) | mismatch in CollateralVault.setUnderlying (including dToken-first violation) | ☐ | | Not run | May share evidence with §7 Vault rows |
| 9 | RenounceOwnershipDisabled | renounceOwnership call (DTKN-FR-009 / SEC-006) | ☐ | | Not run | |

### 6.7 Open Issue Register (DTKN-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| DTKN-TBD-001 | Resolved (2026-06-12) | Verify in destination rows DTKN-FR-008 / DTKN-GOV-004 | Shared Timelock adopted |
| DTKN-TBD-002 | Resolved (implemented, doc-excluded) | Verify in destination row DTKN-FR-009 | Owner transfer changed to 2-step |
| DTKN-TBD-003 | Resolved (implemented, doc-excluded) | Verify in destination row DTKN-FR-009 | Owner renounce disabled |

---

## 7. CollateralVault.md (VAULT)

Source of truth: [CollateralVault.md](../../protocol/product/spec/CollateralVault.md). Target: `contracts/src/CollateralVault.sol` and related files.

### 7.1 Functional Requirements (VAULT-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| VAULT-FR-001 | deposit (Underlying -> dToken; pause/ready/zero; live full-backing guard before transfer; actual-received conversion; mint) | unit, integration | ☑ | ☑ | `CollateralVaultTest::test_UserFlows_FailClosedWhenUnderbacked_AndResumeAfterBackstopRepair`; `test_UserFlowSolvencyGate_IgnoresFreshCacheAndRecoversFromConfirmedAssets` | PARTIAL(VAULT-SOLVENCY-20260826/unit) | Reverts before incoming transfer while underbacked; initial deposit and post-backstop/live-valuation recovery pass. Integration not run |
| VAULT-FR-002 | redeem (immediate/delayed, first-come all-or-nothing, pre-state live full backing, CEI, reject non-exact amount, return receiver delta) | unit, integration, invariant=VAULT-INV-002/003/014 | ☑ | ☑ | `test_Redeem_ImmediateWhenBufferSufficient`; `test_Redeem_ShortfallCreatesRequest`; `test_Redeem_QueuesShortfallBeforePartialBufferTransferHook`; `test_Redeem_FeeOnTransferReturnsReceiverBalanceDelta`; `test_UserFlows_FailClosedWhenUnderbacked_AndResumeAfterBackstopRepair` | PASS(V21+VAULT-SOLVENCY-20260826/unit) | Underbacking reverts before burn, transfer, or queue creation. Return value remains the receiver delta for fee-on-transfer Underlying; integration / invariant not run |
| VAULT-FR-003 | redeemWithPermit (exact check -> live full backing -> permit -> burn(self), all reverts) | unit, integration | ☑ | ☑ | `forge test --match-path test/CollateralVault.t.sol` (V6 / 2026-06-21: 55 passed); `CollateralVaultTest::test_UserFlows_FailClosedWhenUnderbacked_AndResumeAfterBackstopRepair` | PARTIAL(V6+VAULT-SOLVENCY-20260826/unit) | Underbacking reverts before permit nonce, allowance, or dToken balance changes. Existing permit success/front-run/failure boundaries remain intact; specified integration evidence remains open |
| VAULT-FR-004 | allocate (cooldown/pause/M==0, all-outbound stop plus no cooldown consumption and automatic recovery on partial valuation, cap clamp, fixed weights, exact-recovery deposit-reject skip, recovery-mismatch full revert, no reallocation) | unit, invariant=VAULT-INV-006 | ☐ | ☐ | | Not run | |
| VAULT-FR-005 | receiveFromStrategy (registration check, balance-delta accounting, zero short-circuit, exact partial recovery reduces cache value without renewing TTL, invalidate cache on declared/received mismatch) | unit, invariant=VAULT-INV-005 | ☑ | ☑ | `test_ReceiveFromStrategy_OnlyFromRegistered`; `test_ReceiveFromStrategy_ZeroAmountFromRegistered`; `test_FeeOnTransferToken_PrincipalMatchesSent`; `test_FeeOnTransferToken_InvalidatesCacheBeforeValuationOutage`; `test_SendToVault_PartialRecoveryDoesNotRenewValuationCache` | PASS(PRELIM-L03/unit) | Does not infer the remaining position's value from a receipt; fails closed after expiry. Recovery of both live reads restores availability immediately; permissionless refresh repopulates the cache. Invariant not run |
| VAULT-FR-006 | claim (permissionless trigger, fixed owner payout, pre-state live full backing for unsettled requests, settled retry returns 0, unissued/time/buffer reverts, no partial claim, no expiry, pausedClaim stop) | unit, invariant=VAULT-INV-004 | ☑ | ☑ | `test_Claim_FrontRunSettlementMakesOwnerRetryIdempotent`; `test_Claim_PermissionlessTriggerPaysContractRequestOwner`; `test_Claim_UnknownId_Reverts`; `forge test --match-path test/InvariantPushModel.t.sol`; `test_UserFlows_FailClosedWhenUnderbacked_AndResumeAfterBackstopRepair` | PASS(PRELIM-L01+VAULT-SOLVENCY-20260826/unit) | Underbacking reverts before `claimed`, `pendingWithdrawals`, or transfer changes, and the same request settles after backstop recovery. Settled-retry idempotence remains intact |
| VAULT-FR-007 | transferYieldToTreasury (M<=L early return, buffer clamp, min valuation, backstop excluded) | unit, invariant=VAULT-INV-001/005 | ☐ | ☐ | | Not run | |
| VAULT-FR-008 | whitelist / addStrategy / removeStrategy (guards, Underlying invariant, principal==0, add=GOV / remove=GUARDIAN) | unit, invariant=VAULT-INV-007/008 | ☐ | ☐ | | Not run | |
| VAULT-FR-009 | updateStrategy (GOV) / writeoffStrategyPrincipal and forceDeallocateMorphoV2 (WRITEOFF, atomic incident pause, penalty/backing guards, tracked-loss cache reflection) | unit, invariant=VAULT-INV-009 | ☑ | ☑ | `CollateralVaultStrategyTest::test_UpdateStrategy_ReEnableAfterDisable`; `test_UpdateStrategy_DisableWithNonZeroWeight_Reverts`; `test_WriteoffStrategyPrincipal_RevertsWhileEnabledAndAllocationUnpaused`; `test_WriteoffStrategyPrincipal_DoesNotRestoreUnavailablePricing`; `test_ForceDeallocateMorphoV2_ReducesFallbackCacheByTrackedLossAndRecovery`; `MorphoV2StrategyTest` force-deallocation suite; `InvariantPushModelTest::invariant_disabledStrategiesHaveZeroWeightAndWeightSumMatches` | PASS(VAULT-RECERT-20260812) | Recertified update / disable / writeoff / Morpho force-deallocation success and authorization/protection guards, plus sustained weight accounting over 500 runs / 25,000 calls |
| VAULT-FR-010 | initialize (placeholder mode, grant 4 roles, defaults, zero/reinitialize revert) | unit, manual | ☐ | ☐ | | Not run | |
| VAULT-FR-011 | setUnderlying (one-time, dToken-first, bidirectional whenUnderlyingReady guard) | unit, invariant=VAULT-INV-010/011, manual | ☐ | ☐ | | Not run | |
| VAULT-FR-012 | GOV configuration setters (setBufferConfig / setAllocatorConfig / setStrategyValuationMaxAge / setWithdrawDelay / setTreasury; restricted, validated, immediate effect) | unit | ☐ | ☐ | | Not run | |
| VAULT-FR-013 | View group (bufferBalance / backstopBalance / totalUnderlying / Strategy enumeration; placeholder-safe, index, raw value vs min) | unit, manual | ☐ | ☐ | | Not run | |
| VAULT-FR-014 | Pause / Unpause (GUARDIAN/GOV asymmetry, 4 independent lines, claim stop; independent of the VAULT-SEC-010 automatic guard) | unit | ☐ | ☐ | | Not run | The automatic guard provides containment before Guardian response; manual pause remains defense in depth for incident coordination and unobserved loss. The specified pause authority/independence unit verification is not run |
| VAULT-FR-015 | Upgrade (UUPS, GOV-only, storage append-only) | unit, manual | ☐ | ☐ | | Not run | |
| VAULT-FR-016 | operational backingRatio and pricing availability (unavailable vs measured zero, downward-only, L_eff==0 -> 1e18, liability dust rounded up, placeholder-safe) | unit, fork, invariant=VAULT-INV-012/014 | ☑ | ☑ | `CollateralVaultTest::test_BackingRatio_ZeroLiabilitiesAndHealthyReturnOne`; `test_BackingRatio_ImpairmentReturnsAssetOverLiability`; `test_ActualLiabilities_RoundsUpDTokenDust`; `test_PricingViewDistinguishesUnavailableValuationFromMeasuredZero`; `test_WriteoffStrategyPrincipal_DoesNotRestoreUnavailablePricing`; `InvariantPushModelTest::invariant_backingRatioMatchesDefinition`; `invariant_actualLiabilitiesUseCeilingAndIncludePending` | PARTIAL(VAULT-RECERT-20260812/unit+invariant) | Unit and invariant verification are complete, including the unavailable/live-recovery boundary. Only the specified pinned-mainnet-fork evidence remains outstanding |
| VAULT-FR-017 | backstopDeposit / releaseBackstopToBuffer (actual-received accounting, no mint, backing recovery, explicit GOV release, automatic-guard resumption) | unit, integration, invariant=VAULT-INV-013 | ☑ | ☑ | `CollateralVaultTest::test_UserFlows_FailClosedWhenUnderbacked_AndResumeAfterBackstopRepair`; `test_UserFlowSolvencyGate_IgnoresFreshCacheAndRecoversFromConfirmedAssets` | PARTIAL(VAULT-SOLVENCY-20260826/unit) | `backstopDeposit` remains callable while user flows are blocked, and recovery resumes them without another reset. Full release and integration/invariant boundaries are not run |
| VAULT-FR-018 | backing ops views (liability / shortfall / amount to top up target ratio, rounded up, target>1e18 revert) | unit, integration, invariant=VAULT-INV-014 | ☐ | ☐ | | Not run | |
| VAULT-FR-019 | emergencyDisableStrategy (GUARDIAN immediate, weight set to 0, idempotent, backing unchanged, re-enable only by updateStrategy) | unit, invariant=VAULT-INV-009 | ☑ | ☑ | `CollateralVaultStrategyTest::test_EmergencyDisableStrategy_ZeroesWeightPausesAllocationWithoutChangingBacking`; `test_EmergencyDisableStrategy_RevertsForUnregisteredStrategy`; `test_UpdateStrategy_ReEnableAfterDisable`; `InvariantPushModelTest::invariant_disabledStrategiesHaveZeroWeightAndWeightSumMatches` | PASS(VAULT-RECERT-20260812) | Recertified guardian incident response and governance recovery in sustained operation sequences |

### 7.2 Invariants (VAULT-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| VAULT-INV-001 | Solvency principle (healthy: totalUnderlying >= L_effective; impaired: backingRatio<1e18 propagates through Oracle to liquidation mechanism) | invariant | ☐ | ☐ | | Not run | |
| VAULT-INV-002 | redeem CEI order, full burn, InvalidDTokenAmount rejection for non-exact amount | invariant | ☐ | ☐ | | Not run | |
| VAULT-INV-003 | Shortfall redeem: immediate payment + request == needed; pendingWithdrawals increases by remaining amount | invariant | ☐ | ☐ | | Not run | |
| VAULT-INV-004 | pendingWithdrawals == sum of unclaimed requests; double claim impossible (`claimed` flag) | invariant | ☐ | ☐ | | Not run | |
| VAULT-INV-005 | totalUnderlying == raw balance + sum conservative valuations (min / fresh cache / 0 valuation, outflow increment, received decrement, no cache-TTL renewal on partial receipt) | invariant | ☐ | ☐ | `test_SendToVault_PartialRecoveryDoesNotRenewValuationCache` | SUPPORT(PRELIM-L03/unit) | Timestamp safety/liveness boundary covered by unit test; specified invariant campaign not run |
| VAULT-INV-006 | allocate movement <= allocateMaxMove; allocation <= cap remaining; reduction stays in buffer | invariant | ☐ | ☐ | | Not run | |
| VAULT-INV-007 | Guards for addToWhitelist / addStrategy (EOA rejection, whitelist, vault.underlying finalized, Underlying match) | invariant | ☐ | ☐ | | Not run | |
| VAULT-INV-008 | removeStrategy only when principal==0 (StrategyHasPrincipal) | invariant | ☐ | ☐ | | Not run | |
| VAULT-INV-009 | Disabled Strategy has weightBps==0; totalWeightBps == sum <= 10000 | invariant | ☑ | ☑ | `InvariantPushModelTest::invariant_disabledStrategiesHaveZeroWeightAndWeightSumMatches`; `CollateralVaultStrategyTest::test_UpdateStrategy_DisableWithNonZeroWeight_Reverts`; `test_EmergencyDisableStrategy_ZeroesWeightPausesAllocationWithoutChangingBacking` | PASS(VAULT-RECERT-20260812) | 500 runs / 25,000 calls / 0 reverts including update, emergency-disable, and unpause transitions |
| VAULT-INV-010 | setUnderlying one-time only; in active phase, dToken.underlying == vault.underlying is enforced at use time | invariant | ☐ | ☐ | | Not run | |
| VAULT-INV-011 | Full containment in placeholder phase (deposit/redeem/backstop/addStrategy revert, views return 0, allocate early return) | invariant | ☐ | ☐ | | Not run | |
| VAULT-INV-012 | backingRatio definition (L_eff==0 -> 1e18; min(1e18, A/L); view does not revert) | invariant | ☑ | ☑ | `InvariantPushModelTest::invariant_backingRatioMatchesDefinition`; `CollateralVaultTest::test_BackingRatio_ZeroLiabilitiesAndHealthyReturnOne`; `test_BackingRatio_ImpairmentReturnsAssetOverLiability`; `test_BackingOpsViews_StrategyValuationRevertUsesFreshCacheThenExpires` | PASS(VAULT-RECERT-20260812) | Confirmed operational/pricing view agreement over 500 runs / 25,000 calls / 0 reverts |
| VAULT-INV-013 | Accounting effect of backstopDeposit/release (supply and pendingWithdrawals unchanged; backing non-decreasing) | invariant | ☐ | ☐ | | Not run | |
| VAULT-INV-014 | Underlying base-unit rounding up of liability dust (no underestimation) | unit / invariant | ☑ | ☑ | `InvariantPushModelTest::invariant_actualLiabilitiesUseCeilingAndIncludePending`; `CollateralVaultTest::test_ActualLiabilities_RoundsUpDTokenDust`; `test_BackingOpsViews_IncludePendingWithdrawalsAndRoundUp` | PASS(VAULT-RECERT-20260812) | 500 runs / 25,000 calls / 0 reverts across supply changes and queued claims |

### 7.3 Security Requirements (VAULT-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| VAULT-SEC-001 | CEI / reentrancy (reentry blocked) | unit (reentrancy test), invariant=VAULT-INV-002/004 | ☐ | ☐ | | Not run | |
| VAULT-SEC-002 | Use-time enforcement of Underlying consistency (fail-closed, both paths) | unit, invariant=VAULT-INV-010 | ☐ | ☐ | | Not run | |
| VAULT-SEC-003 | Received amount is accounted by balance delta (declared independent; fee-on-transfer simulation) | unit, invariant=VAULT-INV-005 | ☐ | ☐ | | Not run | |
| VAULT-SEC-004 | Fund containment before activation (defense in depth) | unit, invariant=VAULT-INV-011 | ☐ | ☐ | | Not run | |
| VAULT-SEC-005 | ALLOCATOR least privilege (fixed destinations, fixed ratios, cannot change treasury, outbound stop while paused) | unit, manual | ☐ | ☐ | | Not run | |
| VAULT-SEC-006 | Asymmetric pause/unpause authority (pause=GUARDIAN, unpause=GOV, GUARDIAN operations keep backing unchanged) | unit | ☐ | ☐ | | Not run | |
| VAULT-SEC-007 | Upgrade authority restriction (non-GOV approval reverts) | unit, manual (storage layout review) | ☐ | ☐ | | Not run | |
| VAULT-SEC-008 | Prevent silent burn of dToken dust (USDC6 / WBTC8 dust, permit nonce not consumed) | unit, invariant=VAULT-INV-002/014 | ☐ | ☐ | | Not run | |
| VAULT-SEC-009 | Isolation of blacklistable-token individual reverts (state rollback) | unit, manual (token risk review) | ☐ | ☐ | | Not run | |
| VAULT-SEC-010 | Before token, permit, queue, or request mutation, all four user flows require full backing from live confirmed assets without cache; repair rails remain open and flows resume automatically after recovery | unit, invariant=VAULT-INV-001 | ☑ | ☑ | `CollateralVaultTest::test_UserFlows_FailClosedWhenUnderbacked_AndResumeAfterBackstopRepair`; `test_UserFlowSolvencyGate_IgnoresFreshCacheAndRecoversFromConfirmedAssets` | PASS(VAULT-SOLVENCY-20260826/unit) | Covers pre-state blocking and non-mutation for deposit / redeem / redeemWithPermit / unsettled claim, `L_effective==0`, fresh-cache rejection, and backstop/live-valuation recovery |

### 7.4 Governance, Operations, and Upgrade Requirements (VAULT-GOV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| VAULT-GOV-001 | Role separation (initial concentration -> production separation) | manual (deploy configuration review) + holder asserts in deploy script / integration | ☐ | N/A | | Not run | N/A: configuration review item; unauthorized reverts are in VAULT-GOV-002 row |
| VAULT-GOV-002 | Role x operation matrix (authority enforced for every cell) | manual (coverage of authorization tests) | ☐ | ☐ | | Not run | Exception path = all non-authorized role operations revert |
| VAULT-GOV-003 | Role-design rationale (GUARDIAN reversible fail-safe / separate WRITEOFF high-quorum role) | manual | ☐ | N/A | | Not run | N/A: design-rationale confirmation item; concrete tests are GOV-002/004 |
| VAULT-GOV-004 | Separation of timelock and emergency pause (GOV holders=shared Timelock 12h; GUARDIAN immediate; unpause through Timelock) | manual (configuration review) + holder and Timelock asserts in deploy script / integration | ☐ | ☐ | | Not run | |

### 7.5 Event and Monitoring Requirements (VAULT-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| VAULT-EVT-001 | Deposited(user, underlyingAmount, dTokenAmount) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| VAULT-EVT-002 | Redeemed(user, receiver, dTokenAmount, underlyingPaidNow, requestId) (requestId==0 means immediate) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| VAULT-EVT-003 | WithdrawRequested(user, receiver, requestId, amount, claimableAt) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| VAULT-EVT-004 | Allocated / StrategyAllocated / StrategyAllocationSkipped | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| VAULT-EVT-005 | ReceivedFromStrategy(strategy, declaredAmount, received) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| VAULT-EVT-006 | WithdrawClaimed(user, requestId, amount) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| VAULT-EVT-007 | YieldTransferredToTreasury(amount, treasury) (fires even when amount==0) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| VAULT-EVT-008 | StrategyWhitelisted / RemovedFromWhitelist / Added / Updated / EmergencyDisabled family | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| VAULT-EVT-009 | StrategyPrincipalWrittenOff / ValuationRefreshed / ValuationRefreshFailed family | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| VAULT-EVT-010 | UnderlyingSet(underlying) (once only) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| VAULT-EVT-011 | BufferConfigUpdated / AllocatorConfigUpdated / StrategyValuationMaxAgeUpdated and other setter events | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| VAULT-EVT-012 | Paused / Unpaused for Deposit/Redeem/Claim/Allocation (8 kinds) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| VAULT-EVT-013 | ERC1967 Upgraded(newImpl) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| VAULT-EVT-014 | BackstopDeposited(backstop, declaredAmount, received) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| VAULT-EVT-015 | BackstopReleased(caller, amount) | unit (ledger-defined) | ☐ | ☐ | | Not run | |

### 7.6 Failure and Exceptional Behavior (§12 ERR, no ID)

Placeholder-phase behavior:

| # | Event | Expected behavior (doc §12) | Firing evidence | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | deposit / redeem / redeemWithPermit in placeholder phase | UnderlyingNotSet revert (whenUnderlyingReady) | ☐ | | Not run | |
| 2 | backstopDeposit / releaseBackstopToBuffer in placeholder phase | UnderlyingNotSet revert | ☐ | | Not run | |
| 3 | addStrategy in placeholder phase | UnderlyingNotSet revert | ☐ | | Not run | |
| 4 | bufferBalance / backstopBalance / totalUnderlying in placeholder phase | returns 0 (placeholder-safe) | ☐ | | Not run | |
| 5 | allocate in placeholder phase | early return (funds do not move) | ☐ | | Not run | |

System-level exceptional scenarios (each doc §12 section; verified by integration / fork / manual runbook):

| # | Scenario | Expected behavior (doc §12) | Firing evidence | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Underlying configuration risk (VAULT-SEC-002) | fail-closed (use-time enforcement) | ☐ | | Not run | |
| 2 | Redemption liquidity risk (inventory shortage) | degrade to delayed redemption (no immediate guarantee) | ☐ | | Not run | |
| 3 | Strategy risk (smart contract, liquidity, peg, unbonding) | staged recovery (sendToVault -> emergency -> writeoff) | ☐ | | Not run | |
| 4 | Oracle reflection of dToken backing impairment | backingRatio decrease -> collateral value propagates downward | ☐ | | Not run | Same root as SYS-RISK-002 |
| 5 | ALLOCATOR key compromise | damage bounded by fixed destinations and fixed ratios (VAULT-SEC-005) | ☐ | | Not run | |
| 6 | AUM valuation and monetization (over-harvesting) risk | min valuation and M<=L early return (VAULT-FR-007) | ☐ | | Not run | |
| 7 | Known risk of delayed redemption (first-come all-or-nothing, no-expiry claim) | operational handling according to finalized VAULT-TBD-002 specification | ☐ | | Not run | |
| 8 | blacklistable Underlying (USDC, etc.) | isolated as individual tx revert (no batch push) | ☐ | | Not run | |

Error catalog (each error must actually fire in at least one test):

| # | Error | Trigger (reference) | Firing evidence | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Paused | deposit / redeem / redeemWithPermit / claim while paused (VAULT-FR-001..003,006,014) | ☐ | | Not run | |
| 2 | UnderlyingNotSet | Underlying unset (whenUnderlyingReady / addStrategy) | ☐ | | Not run | |
| 3 | UnderlyingMismatch | Vault / dToken Underlying mismatch (including uninitialized dToken) | ☐ | | Not run | |
| 4 | UnderlyingAlreadySet | second setUnderlying (VAULT-FR-011) | ☐ | | Not run | |
| 5 | UnderlyingNotAllowed | dToken allowlist not approved in initialize / setUnderlying | ☐ | | Not run | |
| 6 | ZeroAmount | amount 0 in deposit / redeem / redeemWithPermit / backstopDeposit / release | ☐ | | Not run | |
| 7 | ZeroAddress | zero address in initialize / redeem receiver / setUnderlying / setTreasury | ☐ | | Not run | |
| 8 | InvalidDTokenAmount | non-exact dToken amount in redeem / redeemWithPermit | ☐ | | Not run | |
| 9 | NotContract | EOA / undeployed dToken in initialize, whitelist, or addStrategy | ☐ | | Not run | |
| 10 | CapExceeded (dToken side) | cap exceeded during deposit (DTKN-FR-004) | ☐ | | Not run | May share evidence with §6 |
| 11 | CooldownNotMet | allocate before cooldown elapsed (VAULT-FR-004) | ☐ | | Not run | |
| 12 | InvalidBufferConfig | targetBps>10000 in setBufferConfig (VAULT-FR-012) | ☐ | | Not run | |
| 13 | NotRegisteredStrategy | receiveFromStrategy from unregistered Strategy (VAULT-FR-005) | ☐ | | Not run | |
| 14 | NotWhitelisted | addStrategy for non-whitelisted Strategy (VAULT-FR-008) | ☐ | | Not run | |
| 15 | StrategyAlreadyExists | addStrategy for already registered Strategy | ☐ | | Not run | |
| 16 | WeightExceedsBps | totalWeightBps exceeds 10000 (addStrategy / updateStrategy) | ☐ | | Not run | |
| 17 | InvalidWeight | updateStrategy with enabled==false and weight>0 (VAULT-FR-009) | ☐ | | Not run | |
| 18 | StrategyNotFound | target validation fails in updateStrategy / writeoff | ☐ | | Not run | |
| 19 | StrategyHasPrincipal | removeStrategy when principal!=0 (VAULT-FR-008) | ☐ | | Not run | |
| 20 | RequestNotFound | unissued claim ID (settled IDs return 0; VAULT-FR-006) | ☑ | `CollateralVaultTest::test_Claim_UnknownId_Reverts` | PASS(PRELIM-L01) | Selector retained; meaning narrowed to unissued IDs |
| 21 | Retired: NotRequestOwner | Removed; any caller may settle, but payment is fixed to request owner (VAULT-FR-006) | ☑ | `CollateralVaultTest::test_Claim_PermissionlessTriggerPaysContractRequestOwner` | PASS(unit) | Error selector removed |
| 22 | RequestNotReady | claim before claimableAt | ☐ | | Not run | |
| 23 | InsufficientBuffer | buffer shortage at claim (no partial claim; retry later) | ☐ | | Not run | |
| 24 | InsufficientBackstop | release amount > backstopBalance() | ☐ | | Not run | |
| 25 | InvalidBackingTarget | target>1e18 in backstopRequiredForRatio (VAULT-FR-018) | ☐ | | Not run | |
| 26 | "Index out of bounds" (require string) | out-of-range index in getStrategyAt (VAULT-FR-013) | ☐ | | Not run | |
| 27 | BackingRatioBelowMinimum | Pre-state confirmed assets are below effective liabilities for a user flow, or a caller-specified writeoff / force-deallocation backing guard fails (VAULT-SEC-010) | ☑ | `CollateralVaultTest::test_UserFlows_FailClosedWhenUnderbacked_AndResumeAfterBackstopRepair`; `test_UserFlowSolvencyGate_IgnoresFreshCacheAndRecoversFromConfirmedAssets` | PASS(VAULT-SOLVENCY-20260826/unit) | User-flow checks use `minimum=1e18` and live confirmed assets even when a fresh cache exists |

### 7.7 Open Issue Register (VAULT-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| VAULT-TBD-002 | Resolved (2026-06-11) | Finalized for Day-1 as first-come all-or-nothing + delayed redemption + no-expiry claim -> verify in VAULT-FR-002/006 and §7.6 scenario 7 | |
| VAULT-TBD-003 | Resolved (2026-06-12) | Shared Timelock holder method -> verify in VAULT-GOV-004 row | |
| VAULT-TBD-004 | Resolved (2026-06-11) | ALLOCATOR_ROLE-only allocate permanently finalized -> verify in VAULT-FR-004 row | |
| (VAULT-TBD-001) | Missing number | Does not exist in doc (append-only missing number). Do not reuse | Treat as missing number in coverage checks |

---

## 8. Strategy.md (STGY, Shared Architecture)

Source of truth: [Strategy.md](../../protocol/product/spec/strategies/Strategy.md). Target: `IStrategy` / `BaseStrategy`.

### 8.1 Functional Requirements (STGY-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| STGY-FR-001 | deposit (onlyVault, declared/net receipt validation, isolated upstream call, principal add on success, exact recovery and skip on rejection, recovery-mismatch full revert) | unit, integration (allocate -> deposit linkage) | ☐ | ☐ | | Not run | |
| STGY-FR-002 | sendToVault (ALLOCATOR-only, early return, sent-based decrement, principal-first) | unit, fork/integration | ☐ | ☐ | | Not run | |
| STGY-FR-003 | sendProfitToVault (ALLOCATOR-only, yield==0/actual==0 early return, principal unchanged) | unit, fork/integration | ☐ | ☐ | | Not run | |
| STGY-FR-004 | writeoffPrincipal (onlyVault, min clamp, non-negative) | unit, invariant=STGY-INV-002 | ☐ | ☐ | | Not run | |
| STGY-FR-005 | emergencyWithdraw (onlyOwner, destination fixed to Vault, principal unchanged, _amount==0 no-op) | unit, integration | ☐ | ☐ | | Not run | |
| STGY-FR-006 | Derived hooks (_doDeposit / _doWithdraw / _estimatedTotalUnderlying) | unit, integration/fork (external I/F verification in child docs) | ☐ | ☐ | | Not run | AAVE rows are concrete evidence |
| STGY-FR-007 | BaseStrategy initialization (zero checks, reinitialize revert, safeApprove(vault, max), ownership transfer) | unit, manual | ☐ | ☐ | | Not run | |
| STGY-FR-008 | view getter (principal / realizedYield identity, conservative valuation, Underlying match) | unit, integration | ☐ | ☐ | | Not run | |
| STGY-FR-009 | Upgrade (UUPS, upgrader-only, Owner / operations roles revert, only upgrader can reassign upgrader) | unit, manual | ☐ | ☐ | | Not run | |
| STGY-FR-010 | sweepRewardToken (only non-Underlying/non-position rewards, destination current treasury, actual receipt, full-amount request) | unit | ☐ | ☐ | | Not run | |
| STGY-FR-011 | Owner transfer (2-step, pending cancel, renounce disabled, zero owner init revert) | unit, manual | ☐ | ☐ | | Not run | |
| STGY-FR-012 | claimMerklRewards (distributor validation, fixed recipient, protected-token pre-claim rejection, Treasury actual receipt) | unit | ☐ | ☐ | | Not run | |

### 8.2 Invariants (STGY-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| STGY-INV-001 | deposit / writeoffPrincipal are vault-only; send functions only by holders of Vault ALLOCATOR_ROLE | invariant | ☐ | ☐ | | Not run | |
| STGY-INV-002 | principal never below 0 (min clamp) | invariant | ☐ | ☐ | | Not run | |
| STGY-INV-003 | sendProfitToVault and emergencyWithdraw do not change principal | invariant | ☐ | ☐ | | Not run | |
| STGY-INV-004 | realizedYield() == max(estimatedTotalUnderlying() - principal, 0) | unit | ☐ | ☐ | | Not run | |
| STGY-INV-005 | principal decrement is based on actual Vault received amount sent (declared independent) | invariant | ☐ | ☐ | | Not run | |
| STGY-INV-006 | underlying() is immutable and matches corresponding Vault Underlying (checked by addStrategy) | invariant | ☐ | ☐ | | Not run | |
| STGY-INV-007 | vault / underlyingToken are immutable after __BaseStrategy_init | invariant | ☐ | ☐ | | Not run | |
| STGY-INV-008 | sweepRewardToken / claimMerklRewards reject Underlying / protected position tokens and do not affect accounting | unit | ☐ | ☐ | | Not run | |
| STGY-INV-009 | Owner changes only on successful acceptOwnership and is unchanged by renounce | unit | ☐ | ☐ | | Not run | |
| STGY-INV-010 | UUPS upgrade is approved only by upgrader; Owner/ALLOCATOR/vault cannot; upgrader cannot be zero address | unit | ☐ | ☐ | | Not run | develop addition (upgrader separation) |

### 8.3 Security Requirements (STGY-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| STGY-SEC-001 | Damage boundary for ALLOCATOR key compromise (cannot send to arbitrary destination; deposit is onlyVault) | unit, manual | ☐ | ☐ | | Not run | |
| STGY-SEC-002 | Damage boundary for Owner key compromise (emergencyWithdraw destination fixed; Owner cannot upgrade) | unit, manual | ☐ | ☐ | | Not run | |
| STGY-SEC-003 | emergencyWithdraw destination fixed to Vault (cannot send to arbitrary address) | unit | ☐ | ☐ | | Not run | |
| STGY-SEC-004 | Conservative accounting for AUM overvaluation (no over-harvesting) | unit, integration | ☐ | ☐ | | Not run | |
| STGY-SEC-005 | Liquidity shortage treated as normal behavior (actual<requested / actual==0 does not revert; DoS resistance) | unit, integration | ☐ | ☐ | | Not run | |
| STGY-SEC-006 | Accounting boundary for reward sweep / Merkl claim (reject Underlying / position token, fixed destination, fixed recipient, actual receipt) | unit, manual | ☐ | ☐ | | Not run | |
| STGY-SEC-007 | Prevent Owner authority loss (2-step, renounce disabled, zero owner init revert) | unit | ☐ | ☐ | | Not run | |
| STGY-SEC-008 | Damage boundary for Upgrader key compromise (only upgrader can upgrade/setUpgrader; zero upgrader reverts) | unit, manual | ☐ | ☐ | | Not run | develop addition (upgrader separation) |

### 8.4 Governance, Operations, and Upgrade Requirements (STGY-GOV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| STGY-GOV-001 | Holder configuration for Owner / upgrader | manual (configuration review, holder assert) | ☐ | N/A | | Not run | N/A: holder configuration review; unauthorized cases are in STGY-FR-009 |
| STGY-GOV-002 | Emergency operation (updateStrategy -> emergency recovery runbook) | manual, integration | ☐ | ☐ | | Not run | |
| STGY-GOV-003 | Owner timelock (upgrader=shared Timelock 12h, Owner=Guardian immediate separation) | manual (configuration review, holder assert) | ☐ | ☐ | | Not run | |
| STGY-GOV-004 | Owner transfer and renounce (2-step, renounce disabled) | unit, manual | ☐ | ☐ | | Not run | |
| STGY-GOV-005 | Upgrader is a dedicated actor (holder configuration separated from Owner) | manual (deploy configuration review) | ☐ | N/A | | Not run | develop addition. N/A: configuration review item; unauthorized reverts are in STGY-INV-010/SEC-008 |

### 8.5 Event and Monitoring Requirements (STGY-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| STGY-EVT-001 | Deposited(amount, newPrincipal) | unit | ☐ | ☐ | | Not run | |
| STGY-EVT-002 | SentToVault(caller, requested, actual, newPrincipal) | unit | ☐ | ☐ | | Not run | |
| STGY-EVT-003 | ProfitSentToVault(caller, yield, actual) | unit | ☐ | ☐ | | Not run | |
| STGY-EVT-004 | PrincipalWrittenOff(amount, newPrincipal) | unit | ☐ | ☐ | | Not run | |
| STGY-EVT-005 | EmergencyWithdrawn(amount) | unit | ☐ | ☐ | | Not run | |
| STGY-EVT-006 | Emergency*Withdrawn (derived-specific, recommended) | unit | ☐ | ☐ | | Not run | Depends on derived implementation (see AAVE-TBD-004) |
| STGY-EVT-007 | RewardTokenSwept(token, treasury, requested, received) | unit | ☐ | ☐ | | Not run | |
| STGY-EVT-008 | OwnershipTransferStarted / OwnershipTransferred | unit | ☐ | ☐ | | Not run | |
| STGY-EVT-009 | UpgraderUpdated(oldUpgrader, newUpgrader) / ERC1967 Upgraded(newImpl) | unit | ☐ | ☐ | | Not run | develop addition (upgrader separation) |
| STGY-EVT-010 | MerklRewardsClaimed(distributor, token, cumulativeAmount, swept) | unit | ☐ | ☐ | | Not run | Merkl claim addition |
| STGY-EVT-011 | PrincipalReturned(amount, newPrincipal) | unit | ☐ | ☐ | | Not run | Returned-principal accounting for strategy-specific emergency recovery |

### 8.6 Failure and Exceptional Behavior (STGY-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| STGY-ERR-001 | Shared risks and failure behavior (external protocol failure, liquidity shortage, valuation unavailable degradation) | manual, integration | ☐ | ☐ | | Not run | |
| STGY-ERR-002 | Handling asynchronous external protocols (push model hides sync/async inside Strategy) | manual, integration | ☐ | ☐ | | Not run | Same root as SYS-RISK-004 |

### 8.7 Open Issue Register (STGY-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| STGY-TBD-001 | Resolved (2026-06-12) | Upgrader separation + shared Timelock -> verify in STGY-FR-009 / STGY-GOV-003 rows | |
| STGY-TBD-002 | Resolved (implemented) | Conservative withdraw caps for each Strategy are implemented. Temporary liquidity shortage is not treated as confirmed loss, and valuation is not capped by current liquidity | Linked with AAVE-TBD-008 / ERC4626Strategy |

---

## 9. AaveV3Strategy.md (AAVE)

Source of truth: [AaveV3Strategy.md](../../protocol/product/spec/strategies/AaveV3Strategy.md). Target: `AaveV3Strategy.sol`. Fork verification uses real Aave V3 (mainnet fork).

### 9.1 Functional Requirements (AAVE-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AAVE-FR-001 | initialize (fixed destination, aToken underlying validation, Pool max approve, zero/multiple revert) | unit | ☐ | ☐ | | Not run | |
| AAVE-FR-002 | addStrategy prerequisite (whitelist -> addStrategy, Underlying match validation) | integration, manual | ☐ | ☐ | | Not run | |
| AAVE-FR-003 | _doDeposit (supply(onBehalfOf=this), scaled delta accounting, zero-scaled/cap rejection in isolated frame, exact recovery skip) | unit, fork, invariant=AAVE-INV-001 | ☑ | ☑ | `test_Allocate_RecoversAndSkipsWhenAaveSupplyMintsZeroScaledBalance`; `test_Allocate_RecoversAndSkipsWhenAaveSupplyCapRejects`; `test_DonationDoesNotInflateRealizedYield` | PASS(unit V9 + Low-01) | fork frozen/paused rejection and invariant not run |
| AAVE-FR-004 | _doWithdraw (withdraw(to=this), scaled decrement, zero-scaled burn revert, 0 floor, partial / 0 recovery by liquid reserve cap) | unit, fork, invariant=AAVE-INV-001 | ☑ | ☑ | `test_SendToVault_RevertsWhenAaveWithdrawBurnsZeroScaledBalance`; `test_SendToVault_CapsAaveWithdrawalToLiquidUnderlying`; `test_SendToVault_AaveWithdrawalCreditsNetUnderlyingReceipt` | PASS(unit V9) | fork/invariant not run; reflects AAVE-TBD-008 resolution |
| AAVE-FR-005 | _estimatedTotalUnderlying (min, RAY conversion, donation exclusion, effective==0 -> 0) | unit, fork, invariant=AAVE-INV-002 | ☐ | ☐ | | Not run | |
| AAVE-FR-006 | emergencyWithdrawFromAave (onlyOwner, liquid reserve cap, Vault receives in same Tx, returned principal accounting) | unit, fork, integration, manual | ☑ | ☑ | `test_EmergencyWithdrawFromAave_DrainsResetsScaleAndPushesToVault`; `test_EmergencyWithdrawFromAave_PartialWhenReserveIlliquid`; `test_EmergencyWithdrawFromAave_RevertsWhenAaveWithdrawBurnsZeroScaledBalance` | PASS(unit V9) | fork/integration/manual not run |
| AAVE-FR-007 | claimAaveRewards (assets fixed to aToken, Underlying rewards settle to Vault buffer, non-Underlying rewards sweep to Treasury, protected tokens rejected) | unit, fork | ☐ | ☐ | | Not run | |

### 9.2 Invariants (AAVE-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AAVE-INV-001 | _ownScaledBalance changes only through own functions (deposit delta add / withdraw and emergency actual-burn decrement with 0 floor) | invariant | ☐ | ☐ | | Not run | |
| AAVE-INV-002 | Valuation = mulDiv(min(own, actual scaled), normalizedIncome, RAY) (donations excluded from AUM) | invariant / fork | ☐ | ☐ | | Not run | |
| AAVE-INV-003 | aavePool / aToken immutable after initialize (no setter) | invariant | ☐ | ☐ | | Not run | |
| AAVE-INV-004 | supply uses onBehalfOf==this and withdraw uses to==this | unit | ☐ | ☐ | | Not run | |
| AAVE-INV-005 | sweepRewardToken(aToken) reverts with CannotSweepProtectedToken; normal rewards can be swept | unit | ☐ | ☐ | | Not run | |

### 9.3 Security Requirements (AAVE-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AAVE-SEC-001 | Investment-target address fixed at initialize | invariant=AAVE-INV-003, manual (no-setter review) | ☐ | ☐ | | Not run | |
| AAVE-SEC-002 | Exclude AUM inflation by third-party donation (realizedYield unchanged after donation injection) | invariant=AAVE-INV-001/002, fork | ☐ | ☐ | | Not run | |
| AAVE-SEC-003 | Emergency recovery destination fixed and authority separated (ALLOCATOR call reverts, Vault receives in same Tx) | unit, manual | ☐ | ☐ | | Not run | |
| AAVE-SEC-004 | Prevent Pool / aToken misconfiguration (UNDERLYING_ASSET_ADDRESS validation, misconfiguration revert) | unit, manual (deploy assert procedure) | ☐ | ☐ | | Not run | |
| AAVE-SEC-005 | Prohibit reward sweep of aToken | unit | ☐ | ☐ | | Not run | May share evidence with AAVE-INV-005 |

### 9.4 Governance, Operations, and Upgrade Requirements (AAVE-GOV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AAVE-GOV-001 | Investment target replacement is by recreating Strategy (no setter) | manual (operations runbook) | ☐ | N/A | | Not run | N/A: operations runbook item; absence of setter verified in AAVE-INV-003 |
| AAVE-GOV-002 | testnet first (Sepolia integration test complete) | manual | ☐ | N/A | | Not run | N/A: procedure execution record only |
| AAVE-GOV-003 | Stop new allocation and recover in abnormal conditions | manual (monitoring and operations runbook) | ☐ | ☐ | | Not run | |

### 9.5 Event and Monitoring Requirements (AAVE-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AAVE-EVT-001 | OwnScaledBalanceUpdated(ownScaledBalance) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| AAVE-EVT-002 | EmergencyWithdrawn(amount) (BaseStrategy common event; amount sent directly to Vault by emergencyWithdrawFromAave) | unit (ledger-defined) | ☐ | ☐ | | Not run | AAVE-TBD-004 tracks whether to add a dedicated Aave-drain event |
| AAVE-EVT-003 | AaveRewardsClaimed(rewardsController, reward, requested, claimed, settled) | unit (ledger-defined) | ☐ | ☐ | | Not run | Non-Underlying Aave reward settlement |
| AAVE-EVT-004 | AaveUnderlyingRewardsClaimed(rewardsController, reward, requested, claimed, sentToVault) | unit (ledger-defined) | ☐ | ☐ | | Not run | Underlying Aave reward Vault-buffer settlement |

### 9.6 Failure and Exceptional Behavior (AAVE-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AAVE-ERR-001 | Behavior when Aave reserve configuration changes (frozen / paused / supply cap) | fork (ledger-defined) | ☐ | ☐ | | Not run | |
| AAVE-ERR-002 | At 100% utilization, Strategy-side cap returns partial / 0 recovery. Revert only propagates if Aave withdraw itself is rejected, such as reserve paused | fork (ledger-defined) | ☐ | ☐ | | Not run | Reflects AAVE-TBD-008 resolution |
| AAVE-ERR-003 | Emergency recovery impossible during complete Aave stop (degradation and runbook) | manual / fork (ledger-defined) | ☐ | ☐ | | Not run | |
| AAVE-ERR-004 | Breakdown of aToken valuation assumptions | manual / fork (ledger-defined) | ☐ | ☐ | | Not run | |
| AAVE-ERR-005 | Missed reward tokens (Merkl + Aave RewardsController claim implemented; reward swap / non-Underlying backing replenishment remains unsupported) | manual (ledger-defined) | ☐ | ☐ | | Not run | Related to AAVE-FR-007 / AAVE-TBD-005 |

### 9.7 Open Issue Register (AAVE-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| AAVE-TBD-001 | Open | Final confirmation of safeApprove(max) policy -> until finalized, verify AAVE-FR-001 approve under current specification | |
| AAVE-TBD-002 | Open | Final referralCode value (currently 0) | |
| AAVE-TBD-003 | Open | Whether additional conservative correction is needed for aToken conversion | |
| AAVE-TBD-004 | Open | Whether to add EmergencyAaveWithdrawn event -> linked to AAVE-EVT-002 row | |
| AAVE-TBD-005 | Scoped | Merkl is handled by BaseStrategy.claimMerklRewards, and Aave RewardsController by claimAaveRewards. Reward swap / non-Underlying backing replenishment remains open | |
| AAVE-TBD-006 | Resolved (treated as missing number) | initialize aToken underlying consistency check is implemented (verify in AAVE-FR-001 / AAVE-SEC-004); do not reuse this ID | |
| AAVE-TBD-007 | Open | Mainnet / Sepolia Pool and aToken final addresses -> deploy configuration inspection gate | |
| AAVE-TBD-008 | Resolved (2026-06-16) | Withdraw cap based on reserve liquidity is implemented. Temporary liquidity shortage does not revert; it returns partial / 0, and valuation is not capped by current liquidity | Same root as STGY-TBD-002 / AAVE-FR-004 |

---

## 9A. ERC4626Strategy.md (E4626)

Source of truth: [ERC4626Strategy.md](../../protocol/product/spec/strategies/ERC4626Strategy.md). Target: `ERC4626Strategy.sol` (generic ERC-4626 adapter, inherits `BaseStrategy`, UUPS). FR / INV / GOV / EVT / ERR / TBD inherit the shared Strategy specification (§8 STGY), and this document has only eight ERC-4626-specific security requirements (`E4626-SEC`). Like AaveV3 (§9), this is a concrete Strategy. Because it was added later, it is inserted as §9A while preserving existing numbering. Fork verification uses real ERC-4626 vaults (Morpho Vault / EulerEarn / sUSDS, etc.).

### 9A.1 Security Requirements (E4626-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| E4626-SEC-001 | `initialize` verifies `erc4626Vault.asset() == underlying` and rejects mismatch | unit | ☑ | ☑ | `test_Initialize_RevertsOnERC4626AssetMismatch` | PASS(V9) | |
| E4626-SEC-002 | Share token donation does not increase `estimatedTotalUnderlying()` / `realizedYield()` | unit | ☑ | ☑ | `test_ShareDonationDoesNotInflateRealizedYield` | PASS(V9) | |
| E4626-SEC-003 | ERC-4626 share token is a position token and cannot be sent to Treasury by `sweepRewardToken` | unit | ☑ | ☑ | `test_SweepRewardToken_RejectsERC4626ShareToken` | PASS(V9) | |
| E4626-SEC-004 | If `deposit()` returns 0 shares, the isolated upstream frame reverts with `ERC4626ZeroShares`; exact Underlying recovery then skips that allocation | unit | ☑ | ☑ | `test_Allocate_RecoversAndSkipsWhenERC4626MintsZeroShares` | PASS(V9 + Low-01) | |
| E4626-SEC-005 | ERC-4626 asset loss is reflected downward in `estimatedTotalUnderlying()` and Vault `totalUnderlying()` | unit | ☑ | ☑ | `test_AssetLossReflectedInEstimateAndVaultTotal` | PASS(V9) | |
| E4626-SEC-006 | Emergency recovery pushes redeemed Underlying to Vault in the same tx and does not create a temporary `backingRatio()` underestimation window | unit | ☑ | ☑ | `test_EmergencyWithdrawFromERC4626_DoesNotTransientlyDiscountBacking`; `test_EmergencyWithdrawFromERC4626_PartialRecoveryAccountsReturnedPrincipal` | PASS(V9) | |
| E4626-SEC-007 | `deposit` / `withdraw` / `redeem` compare share balance before/after with ERC-4626 return values, and normal withdraw / emergency redeem also compare actual Underlying deltas; a deposit mismatch reverts its isolated frame and is skipped only after exact recovery, while withdrawal mismatches revert | unit | ☑ | ☑ | `test_Allocate_RecoversAndSkipsWhenERC4626ReturnDoesNotMatchShareDelta`; `test_SendToVault_RevertsWhenERC4626WithdrawReturnDoesNotMatchShareDelta`; `test_SendToVault_RevertsWhenERC4626WithdrawBurnsZeroShares`; `test_SendToVault_RevertsWhenERC4626WithdrawAssetDeltaMismatch`; `test_EmergencyWithdrawFromERC4626_RevertsWhenRedeemAssetDeltaMismatch` | PASS(V9 + Low-01) | |
| E4626-SEC-008 | Merkl / external reward claims push an Underlying reward to the Vault buffer and sweep an ordinary non-Underlying, non-ERC-4626-share reward to Treasury. ERC-4626 share tokens / protected position tokens are rejected before the distributor call, and claim / sweep must not change `principal` or `estimatedTotalUnderlying()` | unit | ☑ | ☑ | `test_ClaimMerklRewards_SweepsERC4626RewardToTreasuryWithoutAccountingImpact`; `test_ClaimMerklRewards_PushesUnderlyingRewardToVaultWithoutReducingPrincipal`; `test_ClaimMerklRewards_RejectsERC4626ShareTokenBeforeDistributorCall` | PASS(V22) | The former wording also routed Underlying rewards to Treasury and required the Vault buffer to stay unchanged, while the normative ERC4626Strategy spec pushes Underlying rewards to the Vault buffer. This row is synced to that source and the matching production test is recorded |

---

## 9B. LidoStrategy.md (LIDO, Archived)

> **Archived / excluded from the active total.** `LidoStrategy` was archived on 2026-08-06
> together with its Solidity source (`contracts/src/Strategies/archive/`) and tests
> (`contracts/test/archive/`). Its underlying is structurally WETH, PR #1424 removed the
> deploy selector entry that bound it, and branch 0's underlying then moved
> WETH -> wstETH, so no branch can supply a WETH underlying. This surface **was covered by the external
> audit completed 2026-08-05** (audited identity `0c7766e0`); the rows below are
> retained so that coverage stays traceable, but `LIDO-*` are **frozen historical
> IDs**: they are not active requirements for implementation or audit, must not be
> reused, and must not be cited as active audit scope. This is an explicit exclusion,
> not an omission. Reactivation requires a new activation package and an explicit
> audit-scope change.

Source of truth: [LidoStrategy.md](../../archive/LidoStrategy.md). Target: `contracts/src/Strategies/archive/LidoStrategy.sol` (WETH -> ETH -> stETH -> wstETH, asynchronous recovery through the Withdrawal Queue). Shared Strategy requirements (§8 STGY) are inherited; this section tracks Lido-specific async / pending / wstETH accounting.

> **Retired / archived (2026-08-05)**: `LidoStrategy` is retired from the Day-1 deploy surface with the WETH -> wstETH branch swap, and its source and spec will be archived (previously audited, out of active scope) rather than deleted; the archive move lands in the separate retirement change. All rows except the retirement / non-activation gate `LIDO-GOV-001` are marked `N/A(retired)`; the IDs are retained for audit traceability against the archived artifact.

### 9B.1 Functional Requirements (LIDO-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LIDO-FR-001 | initialize (fixed venues, upgrader argument, wstETH/stETH consistency, Queue bounds, approve, zero/multiple revert) | unit | N/A | N/A | | N/A(retired) | |
| LIDO-FR-002 | addStrategy prerequisite (whitelist -> addStrategy, Underlying=WETH match, no isAsync notification) | integration, manual | N/A | N/A | | N/A(retired) | |
| LIDO-FR-003 | _doDeposit (WETH -> ETH -> submit -> wrap, actual wstETH balance delta accounting, no donation mixing) | unit, fork, invariant=LIDO-INV-001 | N/A | N/A | | N/A(retired) | |
| LIDO-FR-004 | _doWithdraw (return only claimed idle WETH, do not touch stETH) | unit, integration | N/A | N/A | | N/A(retired) | |
| LIDO-FR-005 | _estimatedTotalUnderlying (min, include pending, exclude donations, exclude idle ETH) | unit, fork, invariant=LIDO-INV-002/005 | N/A | N/A | | N/A(retired) | |
| LIDO-FR-006 | requestLidoWithdrawal (ALLOCATOR, MIN/MAX splitting, own-holding cap, pending accounting, wstETH decrement) | unit, fork, invariant=LIDO-INV-005 | N/A | N/A | | N/A(retired) | |
| LIDO-FR-007 | claimLidoWithdrawals (finalized claim, pending decrement, ETH -> WETH idle balance, reject unknown/double claim, hint batch) | unit, fork, invariant=LIDO-INV-005 | N/A | N/A | | N/A(retired) | |
| LIDO-FR-008 | emergencyWithdrawFromLido (onlyOwner, atomic idle push, request remaining wstETH, no promise of immediate full recovery) | unit, fork | N/A | N/A | | N/A(retired) | |
| LIDO-FR-009 | setReferral (onlyOwner, applies to next submit) | unit | N/A | N/A | | N/A(retired) | |

### 9B.2 Invariants (LIDO-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LIDO-INV-001 | `_ownWstETH` changes only through own functions and does not increase through third-party stETH / wstETH donation | invariant | N/A | N/A | | N/A(retired) | |
| LIDO-INV-002 | Valuation is `getStETHByWstETH(min(_ownWstETH, balance)) + pending + idle WETH`; donations are excluded, slashing is reflected, raw ETH is excluded | invariant / fork | N/A | N/A | | N/A(retired) | |
| LIDO-INV-003 | lido / stETH / wstETH / withdrawalQueue / weth are immutable after initialize | invariant | N/A | N/A | | N/A(retired) | |
| LIDO-INV-004 | _doWithdraw never returns more than idle WETH and does not perform synchronous unstake | unit | N/A | N/A | | N/A(retired) | |
| LIDO-INV-005 | pendingWithdrawAmount equals the recorded amount for unclaimed requestIds; no double claim | invariant | N/A | N/A | | N/A(retired) | |
| LIDO-INV-006 | request / claim do not change principal; principal decreases only by actual amount received by Vault | invariant | N/A | N/A | | N/A(retired) | |
| LIDO-INV-007 | sweepRewardToken rejects WETH / stETH / wstETH / unstETH | unit | N/A | N/A | | N/A(retired) | |
| LIDO-INV-008 | underlying() remains WETH and matches the corresponding Vault Underlying | invariant | N/A | N/A | | N/A(retired) | |
| LIDO-INV-009 | wstETH.stETH() matches lido, and Withdrawal Queue bounds belong to the initialized venue | unit / manual | N/A | N/A | | N/A(retired) | |
| LIDO-INV-010 | `_ownIdleUnderlying` increases only from Lido claims, never from donations, and a stale slot is not refilled by a later donation | unit / invariant | N/A | N/A | | N/A(retired) | Row added 2026-08-05 to match the §3 dashboard INV count of 10 (previously only cross-referenced) |

### 9B.3 Security Requirements (LIDO-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LIDO-SEC-001 | Investment venue addresses fixed at initialize; no setters | invariant=LIDO-INV-003, manual | N/A | N/A | | N/A(retired) | |
| LIDO-SEC-002 | Exclude AUM inflation by donation / rebase | invariant=LIDO-INV-001/002, fork | N/A | N/A | | N/A(retired) | |
| LIDO-SEC-003 | Emergency recovery destination fixed and authority separated | unit | N/A | N/A | | N/A(retired) | |
| LIDO-SEC-004 | Async keeper authority and griefing resistance | unit | N/A | N/A | | N/A(retired) | |
| LIDO-SEC-005 | Reject claim before finalization | unit, fork | N/A | N/A | | N/A(retired) | |
| LIDO-SEC-006 | Safe handling of stETH / wstETH 1-wei rounding and accounting | unit | N/A | N/A | | N/A(retired) | |
| LIDO-SEC-007 | Prohibit reward sweep of stETH / unstETH / WETH | unit | N/A | N/A | | N/A(retired) | |
| LIDO-SEC-008 | Fail fast on venue miswiring and wstETH return-value inconsistency | unit, manual | N/A | N/A | | N/A(retired) | |

### 9B.4 Governance, Operations, and Upgrade Requirements (LIDO-GOV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LIDO-GOV-001 | Retirement / non-activation deploy-surface gate (source/tests retained, official deploy wiring excluded, generic unknown-kind fallback, legacy-instance recovery) | manual, unit | ☐ | N/A | | Not run | |
| LIDO-GOV-002 | Async keeper operations runbook | manual | N/A | N/A | | N/A(retired) | |
| LIDO-GOV-003 | Stop new allocation and recover in abnormal conditions | manual, integration | N/A | N/A | | N/A(retired) | |

### 9B.5 Event and Monitoring Requirements (LIDO-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LIDO-EVT-001 | ReferralUpdated(referral) | unit | N/A | N/A | | N/A(retired) | |
| LIDO-EVT-002 | WithdrawRequested(requestIds, stETHAmount) | unit | N/A | N/A | | N/A(retired) | |
| LIDO-EVT-003 | WithdrawClaimed(requestIds, ethReceived) | unit | N/A | N/A | | N/A(retired) | |
| LIDO-EVT-004 | OwnWstETHUpdated(ownWstETH) | unit | N/A | N/A | | N/A(retired) | |
| LIDO-EVT-005 | OwnIdleUnderlyingUpdated(ownIdleUnderlying) | unit | N/A | N/A | | N/A(retired) | Row added 2026-08-06 to match the §3 dashboard EVT count of 5 and the Japanese ledger; previously only listed in §15.1 |

### 9B.6 Failure and Exceptional Behavior (LIDO-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LIDO-ERR-001 | Finalization delay and early-claim rejection | unit, fork, manual | N/A | N/A | | N/A(retired) | |
| LIDO-ERR-002 | Request constraints from MIN/MAX_STETH_WITHDRAWAL_AMOUNT | unit, fork | N/A | N/A | | N/A(retired) | |
| LIDO-ERR-003 | stETH slashing and principal loss | fork, manual | N/A | N/A | | N/A(retired) | |
| LIDO-ERR-004 | Emergency recovery limits when Lido / Withdrawal Queue is stopped | fork, manual | N/A | N/A | | N/A(retired) | |
| LIDO-ERR-005 | stETH secondary-market depeg, independent from withdrawal rate | manual | N/A | N/A | | N/A(retired) | |

### 9B.7 Open Issue Register (LIDO-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| LIDO-TBD-001 | Resolved (2026-06-16) | request is ALLOCATOR-only; claim is permissionless | LIDO-FR-006 / LIDO-FR-007 |
| LIDO-TBD-002 | Open | Final referral value | LIDO-FR-009 / LIDO-FR-003 |
| LIDO-TBD-003 | Resolved (2026-06-17 implementation) | `_ownIdleUnderlying` is claim-derived only. Direct WETH / raw ETH donations do not enter AUM, yield, or Lido-specific emergency principal return | LIDO-FR-005 / LIDO-SEC-002 / LIDO-INV-010 |
| LIDO-TBD-004 | Resolved (2026-06-14) | No-hint overload is single request; multiple requests use hint-provided batch claim | LIDO-FR-007 |
| LIDO-TBD-005 | Resolved | Use wstETH (non-rebasing) | Internal to Strategy |
| LIDO-TBD-006 | Resolved (2026-06-18) | Product / Strategy Lido wording unified to the current implementation (stETH / wstETH + Withdrawal Queue) | Product-Overview / LidoStrategy |
| LIDO-TBD-007 | Resolved | Current branch values, venue adoption status, and the non-activation / deploy-surface gate moved to their canonical documents | Parameters / Mainnet Deploy Env Freeze Runbook + generated Manifest / Strategy Selection Policy / LIDO-GOV-001 |

---

## 9C. SkyUsdcSUsdsStrategy.md (SKY)

Source of truth: [SkySUsdsStrategy.md](../../protocol/product/spec/strategies/SkySUsdsStrategy.md). Target:
`SkyUsdcSUsdsStrategy.sol`, `SkyUsdcSUsdsConverter.sol`, and the shared `ISkyUsdcSUsdsConverter` boundary. Shared Strategy requirements (§8 STGY) are inherited; this section tracks dUSDC branch `USDC -> USDS -> sUSDS -> USDC` operations.

### 9C.1 Security Requirements (SKY-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SKY-SEC-001 | Validate USDC / USDS / sUSDS decimals and `susdsVault.asset()` at initialization | unit | ☑ | ☑ | `test_Initialize_RevertsWhenUnderlyingDecimalsAreNotUsdc` | PASS(V1) | asset validation reviewed in initialize path |
| SKY-SEC-002 | converter / sUSDS vault approvals are per-call approve/reset | unit / manual | ☑ | N/A | `test_Allocate_ConvertsUsdcToSUsdsAndValuesInUsdc`; code review | PASS(V1) | permanent approval exists only for BaseStrategy USDC -> Vault |
| SKY-SEC-003 | sUSDS share donations do not inflate valuation / realizedYield | unit | ☑ | ☑ | `test_DonatedSUsdsSharesDoNotInflateValuation` | PASS(V1) | values `_ownSUsdsShares` only |
| SKY-SEC-004 | USDS / sUSDS are protected tokens and cannot be swept | unit | ☑ | ☑ | `test_SweepRejectsUsdsAndSUsds` | PASS(V1) | |
| SKY-SEC-005 | converter / sUSDS vault return values match actual balance deltas | unit / manual | ☑ | ☑ | `test_Allocate_ConvertsUsdcToSUsdsAndValuesInUsdc`; code review | PASS(V1) | mismatch revert path reviewed |
| SKY-SEC-006 | USDC recovery reverts below the `maxConversionLossBps` minimum receive | unit / manual | ☑ | ☑ | `test_SendToVault_RedeemsSUsdsAndReturnsUsdc`; `test_EmergencyConvertCannotBypassMaxConversionLoss`; `test_EmergencyWithdrawCannotBypassMaxConversionLoss`; code review | PASS(V7) | emergency `minUsdcOut` cannot relax the floor; fork route halt remains mainnet dry-run scope |
| SKY-SEC-007 | valuation uses the smaller of converter preview and 1:1 conversion | unit | ☑ | ☑ | `test_Allocate_ConvertsUsdcToSUsdsAndValuesInUsdc`; `test_DonatedSUsdsSharesDoNotInflateValuation` | PASS(V1) | |
| SKY-SEC-008 | Nonzero USDS conversion returning 0 USDC reverts and does not silently reduce tracked idle USDS | unit | ☑ | ☑ | `test_EmergencyConvertRevertsWhenUsdsDustWouldReturnZeroUsdc` | PASS(V9) | Sub-USDC USDS dust remains tracked in `_ownIdleUsds` until additional recovery or accumulation makes it convertible |
| SKY-SEC-009 | Converter token identity matches the route and deployment creates the audited concrete adapter | unit / integration | ☑ | ☑ | `test_ConstructorBindsWrapperTokens`; `test_MainnetFork_BindsCanonicalSkyWrapperAndTokens`; `test_MainnetFork_ExecutesRoundTripWhenRoutesAreActive`; `test_DeploySelector_DeploysSkyUsdcSUsdsStrategy` | PASS(V12) | Official wrapper identity and a live round trip were verified with `MAINNET_RPC_URL` |
| SKY-SEC-010 | Enforce the `tout`-inclusive USDS budget, refund unused USDS, and reduce idle accounting only by actual spend | unit | ☑ | ☑ | `test_ConvertUsdsToUsdc_UsesBudgetAndRefundsUnspentDust`; `test_PreviewUsdsToUsdc_AccountsForFeeFloorAtOneUsdcAtom`; `test_EmergencyConvertTracksActualUsdsSpentWhenConverterUsesBudget` | PASS(V12) | No unconvertible six-decimal USDC remainder is left in the adapter |
| SKY-SEC-011 | Continue principal-capped 1:1 valuation for an explicit route halt; invalid fee, status-read failure, and other quote failures become unavailable after fresh cache | unit / integration | ☑ | ☑ | `test_RouteHaltStatusDistinguishesExplicitHaltFromInvalidFee`; `test_PricingRemainsAvailablePastCacheWhileSkyRouteHalted`; `test_HaltedRouteValuationDoesNotRecognizeUnrealizedYield`; `test_PriceFeedDoesNotShutDownBranchAfterHaltedRouteCacheExpires`; `test_PricingUsesFreshCacheWhenSkyQuoteUnavailable` | PASS(PRELIM-M02) | Conversion / preview still revert on halt; only an explicit halt receives conservative live valuation, while unknown faults are not inferred to be halts |

## 9D. EtherfiWeETHStrategy.md (EFWEETH, Archived)

> **Archived / excluded from the active total.** `EtherfiWeETHStrategy` / `WeETHWithdrawAdapter` was archived on 2026-08-06
> together with its Solidity source (`contracts/src/Strategies/archive/`) and tests
> (`contracts/test/archive/`). Its underlying is structurally WETH, PR #1424 removed the
> deploy selector entry that bound it, and branch 0's underlying then moved
> WETH -> wstETH, so no branch can supply a WETH underlying. This surface **was covered by the external
> audit completed 2026-08-05** (audited identity `0c7766e0`); the rows below are
> retained so that coverage stays traceable, but `EFWEETH-*` are **frozen historical
> IDs**: they are not active requirements for implementation or audit, must not be
> reused, and must not be cited as active audit scope. This is an explicit exclusion,
> not an omission. Reactivation requires a new activation package and an explicit
> audit-scope change.

Source of truth: [EtherfiWeETHStrategy.md](../../archive/EtherfiWeETHStrategy.md). Target:
`contracts/src/Strategies/archive/EtherfiWeETHStrategy.sol` and Ether.fi LiquidityPool / weETH / WithdrawAdapter / WithdrawRequestNFT boundaries. Shared Strategy requirements (§8 STGY) are inherited; this section tracks dETH branch WETH -> eETH/weETH deployment and asynchronous recovery.

### 9D.1 Security Requirements (EFWEETH-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| EFWEETH-SEC-001 | Register only on a WETH branch; deploy selector requires WETH underlying | unit / integration | ☑ | ☑ | `test_DeploySelector_DeploysEtherfiWeETHStrategyForWethBranch`; code review | PASS(V1) | non-WETH revert path reviewed |
| EFWEETH-SEC-002 | weETH donations do not inflate valuation / realizedYield | unit | ☑ | ☑ | `test_DonatedWeETHDoesNotInflateValuation` | PASS(V1) | values `_ownWeETH` only |
| EFWEETH-SEC-003 | eETH / weETH / WithdrawRequestNFT are protected assets and cannot be swept | unit | ☑ | ☑ | `test_SweepRewardToken_RejectsPositionTokens` | PASS(V1) | |
| EFWEETH-SEC-004 | `onERC721Received` accepts only the configured WithdrawRequestNFT | unit / manual | ☑ | ☑ | `test_RequestClaimAndSendToVault_ReturnsClaimedWeth`; code review | PASS(V1) | unexpected NFT revert path reviewed |
| EFWEETH-SEC-005 | pending requests are tracked by request ID and unknown claims are rejected | unit | ☑ | ☑ | `test_RequestClaimAndSendToVault_ReturnsClaimedWeth` | PASS(V1) | unknown request revert path reviewed |
| EFWEETH-SEC-006 | `_doWithdraw` returns only claimed idle WETH | unit | ☑ | ☑ | `test_RequestClaimAndSendToVault_ReturnsClaimedWeth`; `test_ClaimUsesActualEthReceivedWhenEtherfiReturnsLessThanPending` | PASS(V1/V2) | pre-claim `sendToVault` returns 0; if actual received is below pending, only actual received can be returned |
| EFWEETH-SEC-007 | Initialization validates that `weETH` / `WithdrawRequestNFT` / `liquidityPool.withdrawRequestNFT()` / `withdrawAdapter` point to the configured `eETH` / `liquidityPool` / `weETH` / `withdrawRequestNFT` graph and that `withdrawAdapter` returns the DF-specific identity marker | unit | ☑ | ☑ | `test_Initialize_RevertsOnMismatchedWeETHEETH`; `test_Initialize_RevertsOnMismatchedWeETHLiquidityPool`; `test_Initialize_RevertsOnMismatchedWithdrawRequestNFTEETH`; `test_Initialize_RevertsOnMismatchedWithdrawRequestNFTLiquidityPool`; `test_Initialize_RevertsOnMismatchedLiquidityPoolWithdrawRequestNFT`; `test_Initialize_RevertsOnMismatchedAdapterLiquidityPool`; `test_Initialize_RevertsOnMismatchedAdapterEETH`; `test_Initialize_RevertsOnMismatchedAdapterWeETH`; `test_Initialize_RevertsOnMismatchedAdapterWithdrawRequestNFT`; `test_Initialize_RevertsWhenAdapterDoesNotExposeDfIdentity` | PASS(V2/V10/V11) | Venue graph consistency check aligned with Aave aToken, ERC4626 asset, and Lido stETH link checks; V10 extends it to the LiquidityPool reverse edge and adapter binding before max approval, and V11 adds marker-less ABI-compatible adapter rejection |
| EFWEETH-SEC-008 | The requestId returned by `withdrawAdapter.requestWithdraw` must be owned by the Strategy before entering pending accounting | unit | ☑ | ☑ | `test_RequestEtherfiWithdrawal_RevertsWhenAdapterDoesNotMintRequestToStrategy` | PASS(V8) | misrouting adapter mints the NFT to a third party |
| EFWEETH-SEC-009 | Permissionless claim `requestIds` array is capped at 32 per transaction | unit | ☑ | ☑ | `test_ClaimEtherfiWithdrawals_RevertsWhenBatchTooLarge` | PASS(V8) | reverts before touching the pending map |
| EFWEETH-SEC-010 | Pending valuation can be conservatively adjusted by `WRITEOFF_ROLE` bps; downward changes require `pausedAllocation == true` | unit | ☑ | ☑ | `test_SetPendingWithdrawalValuationBps_DiscountsAndRoundsEtherfiPendingValue`; `test_SetPendingWithdrawalValuationBps_RevertsAboveDenominator`; `test_SetPendingWithdrawalValuationBps_RequiresWriteoffRole`; `test_SetPendingWithdrawalValuationBps_RevertsDiscountBeforeAllocationPause` | PASS(V8) | 0..10000, floor rounding, pause guard |
| EFWEETH-SEC-011 | Unclaimed async requests are capped at 128 total | unit | ☑ | ☑ | `test_RequestEtherfiWithdrawal_RevertsWhenPendingRequestLimitReached` | PASS(V8) | bounds storage growth and pending request retrieval |
| EFWEETH-SEC-012 | Raw ETH donations do not enter claim delta / idle WETH / yield / valuation | unit | ☑ | ☑ | `test_RawEthDonationBeforeClaimDoesNotInflateIdleOrYield` | PASS(V8) | wraps only the ETH balance delta measured during claim |
| EFWEETH-SEC-013 | Nonzero eETH requests that floor to 0 weETH round up to 1 wei weETH, while pending records the NFT request data's net eETH | unit | ☑ | ☑ | `test_RequestEtherfiWithdrawal_RoundsTinyEETHRequestUpToOneWeETHAtom` | PASS(V9) | avoids stranded weETH dust while preserving `_ownWeETH` and `pendingWithdrawAmount` valuation consistency |
| EFWEETH-SEC-014 | `WeETHWithdrawAdapter` is a DeltaForesight first-party adapter with a DF-specific identity marker, immutable venue graph, LiquidityPool reverse binding, weETH / eETH balance-delta and residual-balance checks, and NFT owner checks, and has no admin / upgrade / rescue surface | unit / manual | ☑ | ☑ | `test_WeETHWithdrawAdapter_UnwrapsWeETHAndRequestsNativeEtherfiWithdrawal`; `test_WeETHWithdrawAdapter_RevertsOnMismatchedWeETHEETH`; `test_WeETHWithdrawAdapter_RevertsOnMismatchedLiquidityPoolWithdrawRequestNFT`; `test_WeETHWithdrawAdapter_RevertsOnZeroRequest`; `test_WeETHWithdrawAdapter_RevertsWhenUnwrapLeavesResidualWeETH`; `test_WeETHWithdrawAdapter_RevertsWhenPoolLeavesResidualEETH`; `test_WeETHWithdrawAdapter_DonationBaselineDoesNotAffectResidualChecks`; `test_Initialize_RevertsWhenAdapterDoesNotExposeDfIdentity`; code review | PASS(V10/V11) | adapter is not an Ether.fi official contract; it is the thin weETH -> eETH -> `LiquidityPool.requestWithdraw` conversion boundary. V11 adds the DF marker so initialization can distinguish it from same-named or ABI-compatible external adapters |

## 9E. MorphoV2Strategy.md (MV2)

Source of truth: [MorphoV2Strategy.md](../../protocol/product/spec/strategies/MorphoV2Strategy.md). Target: `MorphoV2Strategy.sol` (dedicated Morpho Vaults V2 adapter, inherits `BaseStrategy`, UUPS; kind `morpho-v2`, Day-1 branch 1 dUSDC). Shared Strategy requirements (§8 STGY) are inherited; unlike §9A ERC4626, this adapter never consults the max\* views, so it carries its own FR / SEC / INV rows for the isolated-frame fail-soft model, the `forceDeallocate` wrapper, and the emergency `maxShares` staging.

### 9E.1 Functional Requirements (MV2-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MV2-FR-001 | `initialize` rejects zero / non-contract vaults, `asset()` mismatch (`InvalidMorphoVaultAsset`), and penalty bound > 200 bps (`ForceDeallocatePenaltyAboveMax`); bound is init-frozen with no setter | unit | ☑ | ☑ | `test_Initialize_RevertsOnMorphoVaultAssetMismatch`; `test_Initialize_RevertsOnNonContractMorphoVault`; `test_Initialize_RevertsOnPenaltyBoundAboveProtocolMax` | PASS(V13) | |
| MV2-FR-002 | Isolated-frame deposit; venue rejection (cap / receive gate / zero-share / lying return) re-raises `MorphoV2DepositRejected` and BaseStrategy recovers the exact receipt and skips (Low-01); works despite hard-zero max\* views | unit | ☑ | ☑ | `test_AllocateAndSendToVault_WorkDespiteHardZeroMaxViews`; `test_Allocate_RecoversWhenLiquidityAdapterCapHit`; `test_Allocate_RecoversWhenReceiveGateCloses`; `test_Allocate_RecoversAndSkipsWhenMorphoVaultMintsZeroShares`; `test_Allocate_RecoversAndSkipsWhenMorphoDepositReturnDoesNotMatchShareDelta` | PASS(V13) | |
| MV2-FR-003 | `_doWithdraw` clamps to `min(_ownShares, shareBalance)` value and fail-softs untyped liquidity-short / send-gate reverts to `0` (ADR-006); success subtracts actual burned shares; yield harvest preserves principal | unit | ☑ | ☑ | `test_SendToVault_ReturnsZeroFailSoftWhenLiquidityShort`; `test_SendToVault_ReturnsZeroFailSoftWhenSendGateCloses`; `test_SendProfitToVault_HarvestsSharePriceYieldWithoutReducingPrincipal` | PASS(V13) | |
| MV2-FR-004 | `emergencyWithdrawFromMorphoV2(maxShares)` staged recovery: cap `min(shareBalance, maxShares)` incl. donated shares, redeem delta checks, same-tx Vault push, returned-principal accounting; residual routes to `writeoffStrategyPrincipal` | unit | ☑ | ☑ | `test_EmergencyWithdrawFromMorphoV2_FullDrainPushesToVaultSameTx`; `test_EmergencyWithdrawFromMorphoV2_PartialRecoveryViaMaxSharesAccountsReturnedPrincipal`; `test_EmergencyWithdrawFromMorphoV2_RecoversDonatedSharesAfterFullUnwind`; `test_EmergencyWithdrawFromMorphoV2_RevertsWhenRedeemAssetDeltaMismatch` | PASS(V13) | |
| MV2-FR-005 | Vault-only wrapper; WRITEOFF_ROLE atomically deallocates and recovers to the Vault, enforcing actual receipt, penalty and backing bounds. | unit | ☑ | ☑ | `test_GuardianL05_RecoveryIsAtomicAcrossSeparatedRoles`; `testFuzz_GuardianL05_InsufficientReceiptRollsBackEverything`; `test_GuardianL05_AtomicRecoveryRetainsStrategyReentrancyGuard`; `MorphoV2StrategyTest` | PASS (2026-09-17) | 169 Morpho/Vault tests; 256 fuzz cases |

### 9E.2 Security Requirements (MV2-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MV2-SEC-001 | Share token donation does not increase `estimatedTotalUnderlying()` / `realizedYield()` | unit | ☑ | ☑ | `test_ShareDonationDoesNotInflateRealizedYield` | PASS(V13) | |
| MV2-SEC-002 | Isolated frames are self-only; venue reentry during venue deposit / withdraw is blocked by `nonReentrantStrategy` | unit | ☑ | ☑ | `test_DepositIntoMorphoVault_SelfOnly`; `test_WithdrawFromMorphoVault_SelfOnly`; `test_Reentrancy_DuringVenueDepositIsBlocked`; `test_Reentrancy_DuringVenueWithdrawIsBlocked` | PASS(V13) | |
| MV2-SEC-003 | Hostile-venue delta checks: share balance before/after vs reported minted / burned shares, plus Underlying delta on withdraw / emergency redeem; mismatches revert inside the frame (deposit → recovered skip, withdraw → fail-soft 0, emergency → revert) | unit | ☑ | ☑ | `test_Allocate_RecoversAndSkipsWhenMorphoDepositReturnDoesNotMatchShareDelta`; `test_Allocate_RecoversAndSkipsWhenMorphoVaultMintsZeroShares`; `test_SendToVault_ReturnsZeroFailSoftWhenWithdrawReturnDoesNotMatchShareDelta`; `test_SendToVault_ReturnsZeroFailSoftWhenWithdrawBurnsZeroShares`; `test_EmergencyWithdrawFromMorphoV2_RevertsWhenRedeemAssetDeltaMismatch` | PASS(V13) | |
| MV2-SEC-004 | Penalty bound is fail-closed at `assets * maxBps / 10000 + 1` wei; venue round-up vs `convertToAssets` round-down can exceed at an exact-bound venue and reverts; operator remedy is retrying with smaller `assets` | unit | ☑ | ☑ | `test_ForceDeallocate_RevertsWhenPenaltyExceedsBound` | PASS(V13) | +1 wei boundary is deliberate: never accept above the frozen bound |
| MV2-SEC-005 | Deployment restricted to vaults with all four gates unset; a later-installed gate surfaces as recovered deposit rejection or fail-soft withdraw, never stranded funds | unit + venue freeze evidence | ☑ | ☑ | `test_Allocate_RecoversWhenReceiveGateCloses`; `test_SendToVault_ReturnsZeroFailSoftWhenSendGateCloses` | PASS(V13) | gates-unset venue readback is activation-package evidence (freeze package §4a), outside this campaign |
| MV2-SEC-006 | Morpho vault share token is a position token and cannot be swept to Treasury | unit | ☑ | ☑ | `test_SweepRewardToken_RejectsMorphoShareToken` | PASS(V13) | |
| MV2-SEC-007 | Venue asset loss reflects downward immediately in `estimatedTotalUnderlying()` and Vault `totalUnderlying()`; `maxRate` caps gains only (maxRate=0 withholds yield; monitoring item) | unit | ☑ | ☑ | `test_AssetLossReflectedImmediatelyInEstimateAndVaultTotal` | PASS(V13) | |

### 9E.3 Invariants (MV2-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MV2-INV-001 | Valuation / withdraw basis is `min(_ownShares, balanceOf(this))`; `_ownShares` changes only via own deposit / withdraw / emergency / penalty paths, floors at 0, and emits `OwnSharesUpdated` on every change | unit | ☑ | ☑ | `test_ShareDonationDoesNotInflateRealizedYield`; `test_EmergencyWithdrawFromMorphoV2_PartialRecoveryViaMaxSharesAccountsReturnedPrincipal`; `test_ForceDeallocate_WithinBoundResyncsOwnSharesAndDropsValuation`; `test_Max32MorphoV2StrategiesBackingRatioStaysWithinBoundedGas` | PASS(V13) | backing-ratio test also bounds the 32-Strategy view gas |
| MV2-INV-002 | Only Underlying arrives from venue withdraw / redeem (no in-kind redemption); no venue token other than the vault share is held; rewards are Merkl-only via the inherited BaseStrategy path | unit / code review | ☑ | N/A | `test_SweepRewardToken_RejectsMorphoShareToken`; code review | PASS(V13) | N/A: no in-kind path exists to exercise |
| MV2-INV-003 | Derived contract reserves exactly 50 storage slots (3 state variables + `uint256[47]` gap) | code review | ☑ | N/A | code review (`MorphoV2Strategy.sol` state layout) | PASS(V13) | N/A: layout review item |

---

## 10. Oracle.md (ORCL)

Source of truth: [Oracle.md](../../protocol/product/spec/Oracle.md). Target: `PriceFeedProxy` / DF PriceFeed implementations (Standard / Peg-monitored / Composite rate / Placeholder).

### 10.1 Functional Requirements (ORCL-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ORCL-FR-001 | proposeSource (Owner-only; reject address(0), EOA, self, and a direct marker; start timelock and record proposal. The marker is a one-level type screen) | unit, manual (ORCL-GOV-004 dependency evidence) | ☐ | ☐ | | Not run | |
| ORCL-FR-002 | confirmSource / confirmSourceEmergency (only after timelock, replacement reflected, price-difference guard, emergency bypass) | unit, manual | ☐ | ☐ | | Not run | |
| ORCL-FR-003 | cancelSourceProposal (Owner-only, proposal clear) | unit | ☐ | ☐ | | Not run | |
| ORCL-FR-004 | fetchPrice (failure transparency, shutdown proxying, gas-guard re-revert, brick fallback) | unit, fork, integration | ☐ | ☐ | | Not run | |
| ORCL-FR-005 | fetchRedemptionPrice (legacy handling for real source failures; normal-redemption-only fail-closed behavior at `PRM-ORACLE-008` or invalid provenance; automatic recovery on a fresh round) | unit, integration, monitor | ☑ | ☑ | `PriceFeedProxyJpyRedemptionAgeTest`; `RedemptionHelperOracleFailureTest`; `test_NormalRedemptionOracleFailure_DirectAndHelperSpendNothing`; `test_SimulationKeepsFailedBranchInCollateralRegistryAllocationDenominator` | PARTIAL(ORCL-JPY-AGE-20260830/automated) | 30h−1s / exact 30h, cache isolation, real-failure precedence, Helper failure propagation, and full refund passed. Mainnet safe-head and human-delivery evidence are not run |
| ORCL-FR-006 | 2-step ownership transfer (transferOwnership / acceptOwnership, prevent mistaken transfer) | unit, manual | ☐ | ☐ | | Not run | |
| ORCL-FR-007 | renounceOwnership disabled (always reverts; Owner/proposal/pendingOwner unchanged) | unit, manual | ☐ | ☐ | | Not run | |
| ORCL-FR-008 | PriceFeedPlaceholder (always (1e18, false), synthetic JPY provenance, no shutdown, multiple guard layers) | unit, integration | ☑ | ☑ | `forge test --match-path test/PriceFeedPlaceholder.t.sol` (11 passed) | PARTIAL(ORCL-JPY-AGE-20260830/automated) | Proxy acceptance, repeated redemption scans, and activation boundary passed. Deployment-tail readback for every inert branch is not run |
| ORCL-FR-009 | Post-launch Underlying finalization flow for unsettled branches (dToken-first order enforced, pre-cap check) | unit, integration, manual | ☐ | ☐ | | Not run | |
| ORCL-FR-010 | Standard pattern (USDC; collateral/USD failure=shutdown, JPY/USD failure=soft-freeze, substitution/recovery) | unit, fork, integration | ☐ | ☐ | | Not run | |
| ORCL-FR-011 | Peg-monitored pattern (WBTC; peg/collateral USD failure=shutdown, JPY=soft-freeze, synthetic calculation) | unit, fork, integration | ☑ | ☑ | `forge test --match-path 'test/DFWBTCPriceFeed*.t.sol'` (2026-06-21: 17 passed) | PASS(unit/integration) | `DFWBTCPriceFeed` / Proxy integration covers WBTC/BTC stale/down, BTC/USD stale/down, JPY soft-freeze, redemption price, and lastGoodPrice. Fork is not run |
| ORCL-FR-012 | Composite rate pattern (sUSDS; USDS/USD and canonical rate failure=shutdown, JPY=soft-freeze) | unit, fork, integration | ☐ | ☐ | | Not run | |
| ORCL-FR-013 | Composite peg pattern for the future XAUT candidate (on-chain downside-depeg reflection is a mandatory activation condition; no current branch binding or Day-1 exposure) | unit, fork, integration, manual | ☐ | ☐ | | Not run | Same root as SYS-RISK-007 |
| ORCL-FR-014 | Reflect dToken backing peg (shared final layer for every collateral; pricing unavailability/read failure shuts down, only a measured zero gets the 1-wei floor, symmetric consumers) | unit, fork, integration | ☐ | ☐ | `test_backingValuationUnavailableShutsDownAtLastGoodPrice`; `test_zeroBackingRatioReturnsNearZeroNonSentinelPrice`; `test_PricingViewDistinguishesUnavailableValuationFromMeasuredZero` | PARTIAL(unit) | V20 exercised the critical availability boundary. Fork/full integration and full recertification remain incomplete. Paired with VAULT-FR-016 |
| ORCL-FR-015 | dwstETH composite (normal price uses direct stETH/USD x `stEthPerToken()`; normal and urgent redemption select `max(direct stETH/USD, ETH/USD x stETH/ETH)`, then apply canonical rate -> JPY conversion -> backing ratio once in the same order) | unit, fork, integration, invariant | ☑ | ☑ | `forge test --match-path test/DFWstETHPriceFeed.t.sol` (37 passed); `forge test --match-path test/DFWstETHPriceFeedProxyIntegration.t.sol` (10 passed) | PASS(V20) | V20 added valuation-unavailable shutdown coverage. The JPY freeze / backing layer routes through the shared `JpyFreezeLib` |
| ORCL-FR-016 | fetchUrgentRedemptionPrice (composite-aware wind-down price after irreversible shutdown; policy-valid live inputs only, with no cache or direct-only fallback) | unit, fork, integration | ☑ | ☑ | `PriceFeedProxyTest::testFetchUrgentRedemptionPriceDelegatesToSource`; `PriceFeedProxyTest::testFetchUrgentRedemptionPriceRejectsOracleFailure`; `PriceFeedProxyGasGriefTest::test_fix_gasGuardRevert_isBubbled_notShutdown_urgentRedemption` | PARTIAL(ORCL-JPY-AGE-20260830/unit) | Proxy delegation, failure, and gas-guard unit paths passed. Full dwstETH inputs, Core wiring, and mainnet fork/integration recertification are not run |

### 10.2 Invariants (ORCL-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ORCL-INV-001 | PriceFeedProxy address as seen from core is immutable (only underlying source changes) | manual / integration | ☐ | ☐ | | Not run | |
| ORCL-INV-002 | source replacement only by propose -> 12h -> confirm/confirmEmergency (no immediate replacement) | invariant / unit | ☐ | ☐ | | Not run | |
| ORCL-INV-003 | confirmSource succeeds only at or after proposedAt + TIMELOCK_DELAY | unit | ☐ | ☐ | | Not run | |
| ORCL-INV-004 | source is always a nonzero real PriceFeed. Non-contracts, direct markers, and invalid JPY provenance are rejected, but the one-level marker does not prove dependency-graph acyclicity | unit / manual | ☐ | ☐ | | Not run | Combine with ORCL-GOV-004 dependency evidence |
| ORCL-INV-005 | Only gas-guard reverts (strict 4 bytes, selector match) are re-reverted; all others proxy shutdown | unit / integration | ☐ | ☐ | | Not run | |
| ORCL-INV-006 | Proxy returns path-specific caches when the source is bricked; a quote at/after 30h never replaces the redemption cache, and urgent does not settle from cache | unit | ☑ | ☑ | `test_agedQuoteNeverReplacesRedemptionCache`; `test_agedSourceCanBeEmergencySwitchedWithoutCachingItsQuote`; `test_resumeCanClearIndependentPauseWithoutCachingAgedQuote` | PARTIAL(ORCL-JPY-AGE-20260830/automated) | Focused tests passed; a mainnet source-brick rehearsal is not run |
| ORCL-INV-007 | All collateral prices are derived in JPY terms (collJpy = collUsd x 1e18 / jpyUsdRate, 18-dec normalization) | unit / fork | ☐ | ☐ | | Not run | |
| ORCL-INV-008 | Upstream price-fetching base diffs are managed (`MainnetPriceFeedBase` only has Chainlink response-validation hardening; `CompositePriceFeed` only removes LST secondary fallback unnecessary for sUSDS) | manual / static diff review | ☐ | ☐ | | Not run | |
| ORCL-INV-009 | placeholder is (1e18, false), does not trigger shutdown, and is consistent with Vault/dToken multi-layer guards | unit / integration | ☐ | ☐ | | Not run | |
| ORCL-INV-010 | standard / peg type / composite peg have only two states: primary and lastGoodPrice | unit | ☐ | ☐ | | Not run | |
| ORCL-INV-011 | Backing ratio is downward-only (0, 1e18] and multiplies into all collateral prices | unit / fork | ☐ | ☐ | | Not run | |
| ORCL-INV-012 | Active DF feed constructor succeeds only after an initial primary fetch seeds nonzero `lastGoodPrice`; expired shared-provider / unregistered-shutdown catch cannot deploy a zero cache, and fresh JPY recovery restores deployment | unit / integration | ☑ | ☑ | `test_expiredSharedProviderRejectsNewActiveFeedDeployments`; `test_activeFeedDeploymentRecoversAfterFreshJpyRound` | PASS(PRELIM-L02) | Covers Standard and dwstETH rejection plus recovery liveness |
| ORCL-INV-013 | Healthy dwstETH normal/urgent redemption uses `max(direct stETH/USD, ETH/USD x stETH/ETH)` and applies canonical / JPY / backing once in the same order; urgent has neither a third cache nor direct-only fallback | unit / integration / fork | ☐ | ☐ | | Not run | Re-certify the urgent composite paths in `DFWstETHPriceFeed.t.sol` / `DFWstETHPriceFeedProxyIntegration.t.sol` in the next campaign |
| ORCL-INV-014 | Continuously compare source/provider-pinned decimals with each live proxy's `decimals()` at an RPC safe head and externally notify all five feed roles as stable-key `ALRT-ORCL-015` P0 incidents | Ops unit / safe-block integration / labeled delivery | ☑ | ☑ | `frontend/ops/src/lib/snapshot.test.ts`; `frontend/ops/scripts/alerts.test.ts`; `frontend/ops/scripts/alert-delivery.test.ts` | PARTIAL(ORCL-STETH-AGE-20260831/automated; No-Go) | Safe-head collection, role isolation, stable keys, and resolution tests pass. External delivery, human receipt, and resolution are not run |

### 10.3 Security Requirements (ORCL-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ORCL-SEC-001 | Minimize upstream PriceFeed base diffs (`MainnetPriceFeedBase` hardening, sUSDS-pruned `CompositePriceFeed`, JPY/backing logic contained in DF files) | manual (inheritance configuration review), static diff review | ☐ | ☐ | | Not run | |
| ORCL-SEC-002 | Exact transparency of gas griefing protection (selector match, strict length, distinguish real failures) | unit, integration | ☐ | ☐ | | Not run | |
| ORCL-SEC-003 | MEV mitigation by source-replacement timelock (price-difference guard, unhealthy bypass, emergency bypass) | unit, manual | ☐ | ☐ | | Not run | |
| ORCL-SEC-004 | Shared defenses across all three consumer paths plus the explicit asymmetry that `PRM-ORACLE-008` stops only normal redemption and does not spread to fetchPrice or urgent | unit, integration | ☑ | ☑ | `test_exactBoundaryStopsOnlyNormalRedemptionWithoutFailureAlarmOrPause`; `test_realSourceFailureStillUsesExistingPausePathWhenAged`; `test_runtimeProvenanceReturnBombIsBoundedAndStopsOnlyNormalRedemption`; `PriceFeedProxyGasGriefTest` | PARTIAL(ORCL-JPY-AGE-20260830/automated) | Proxy 140 tests passed with 0 failed / 0 skipped. Live integration is not run |
| ORCL-SEC-005 | Shared JPY/USD failsafe (failure substitution, no shutdown, runtime-decimals drift fail-close, weekend boundary, soft freeze, 30h normal-redemption gate, source-bound provenance, external safe-head synthetic) | unit, fork, integration, monitor, manual | ☑ | ☑ | `PriceFeedProxyJpyRedemptionAgeTest`; `JpyUsdRateProvider.t.sol` runtime-decimals focused tests; `frontend/ops/src/lib/snapshot.test.ts`; `frontend/ops/scripts/alerts.test.ts` | PARTIAL(ORCL-JPY-AGE-20260830/automated; No-Go) | Unit coverage includes fresh/stale-new rejection on decimals drift, read revert, gas grief, and recovery at 8 decimals. Code/tests compare Proxy/source normal redemption, normal/urgent price, provider age, and BO pause at one safe-head block and classify `ALRT-ORCL-016`. Labeled-incident escalation-target delivery, human receipt, and same-key resolution are not run. `PRM-ORACLE-001` / `006` / `008` |
| ORCL-SEC-006 | Peg monitoring for centralized wrapped collateral (synthetic calculation, peg-stage shutdown, mainnet feed existence confirmation) | unit, fork, manual | ☐ | ☐ | | Not run | |
| ORCL-SEC-007 | Non-operability of placeholder branches (each guard reverts; all value flows impossible) | unit, integration | ☐ | ☐ | | Not run | |
| ORCL-SEC-008 | Urgent-redemption live-price safety (settle only with policy-valid inputs; no cache/direct-only fallback on input failure or source revert; pass through the gas guard) | unit, integration / adversarial review | ☑ | ☑ | `PriceFeedProxyTest::testFetchUrgentRedemptionPriceRejectsOracleFailure`; `PriceFeedProxyTest::testBrickedSourceFallsBackForNormalPathsButRejectsUrgentAfterSwitch`; `PriceFeedProxyGasGriefTest::test_fix_gasGuardRevert_isBubbled_notShutdown_urgentRedemption` | PARTIAL(ORCL-JPY-AGE-20260830/unit) | Proxy no-cache, revert, and gas-guard boundaries passed. Full dwstETH-input integration and candidate-bound adversarial evidence are not run |

### 10.4 Governance, Operations, and Upgrade Requirements (ORCL-GOV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ORCL-GOV-001 | Owner is governance / multisig (PriceFeedProxy Owner=GOV multisig directly) | manual (deploy/migration configuration review) | ☐ | N/A | | Not run | N/A: configuration review item; unauthorized cases are in ORCL-FR-001..003 |
| ORCL-GOV-002 | Owner transfer is 2-step | manual, unit (same as ORCL-FR-006) | ☐ | ☐ | | Not run | |
| ORCL-GOV-003 | Owner renounce disabled | manual, unit (same as ORCL-FR-007) | ☐ | ☐ | | Not run | |
| ORCL-GOV-004 | Source replacement operations (an independent reviewer checks the pinned dependency graph at proposal and immediately before confirmation as the sole semantic acyclicity evidence) | manual (dependency-graph evidence and replacement runbook), integration | ☐ | ☐ | | Not run | Addresses, codehashes, and routing state bind the graph to chain state. The 12h lifecycle and three smoke paths do not independently prove acyclicity. Cancel on unknown edges or drift |
| ORCL-GOV-005 | GOV procedure for Day 2 activation flow | manual (procedure review), integration | ☐ | ☐ | | Not run | |

### 10.5 Event and Monitoring Requirements (ORCL-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ORCL-EVT-001 | SourceProposed (new source, confirmable timestamp) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| ORCL-EVT-002 | SourceUpdated(oldSource, newSource) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| ORCL-EVT-003 | SourceProposalCancelled | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| ORCL-EVT-004 | shutdown observation event (trigger for shutdown proxying on source failure) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| ORCL-EVT-005 | OwnershipTransferStarted / OwnershipTransferred | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| ORCL-EVT-006 | SourceSwitchValidated (old/new price, oldSourceHealthy, priceGuardBypassed) | unit (ledger-defined) | ☐ | ☐ | | Not run | |
| ORCL-EVT-007 | `JpyRateFrozen(timestamp, frozenRate)` (JPY soft-freeze detection; `timestamp` is the earlier of first observation and the stored JPY rate's stale boundary) | unit | ☑ | ☑ | `forge test --match-path test/DFPriceFeed.t.sol` (50 passed); `forge test --match-path test/sUSDSPriceFeed.t.sol` (35 passed); `forge test --match-path test/DFWstETHPriceFeed.t.sol` (36 passed) | PASS(V14) | Emitted by `JpyUsdRateProvider`. The topic is unchanged after the shared `JpyFreezeLib` extraction, and the same event is observed from all three feeds |
| ORCL-EVT-008 | `JpyRateUnfrozen(timestamp, liveRate)` (return to a live JPY/USD rate) | unit | ☑ | ☑ | `forge test --match-path test/DFPriceFeed.t.sol` (50 passed); `forge test --match-path test/sUSDSPriceFeed.t.sol` (35 passed); `forge test --match-path test/DFWstETHPriceFeed.t.sol` (36 passed) | PASS(V14) | As above |
| ORCL-EVT-009 | `JpyFreezeExpired(timestamp, frozenRate)` (expiry of the current shared freeze episode; P0 signal for per-branch oracle pause and blocked user actions) | unit | ☑ | ☑ | `forge test --match-path test/JpyUsdRateProvider.t.sol`; `forge test --match-path test/DFPriceFeed.t.sol`; `forge test --match-path test/DFWstETHPriceFeedProxyIntegration.t.sol` | PASS(V15) | Expiry re-reports while unhealthy and a fresh response clears the episode latch. The active source can revalidate the live rate, but the BO pause flag remains set until the Proxy owner validates normal / redemption / urgent and explicitly resumes |
| ORCL-EVT-010 | `RedemptionReferenceUnavailable(oracle, stEthUsdPrice)` (P0 signal for an unavailable dwstETH ETH/USD or stETH/ETH normal-redemption reference) | unit (ledger-defined) | ☐ | ☐ | | Not run | Re-certify the event/fail-closed paths in `DFWstETHPriceFeed.t.sol` / `DFWstETHPriceFeedProxyIntegration.t.sol` in the next campaign |
| ORCL-EVT-011 | `OracleFailureShutdownResumed(source, validatedPrice, validatedRedemptionPrice)` (evidence that Owner validated all three price paths and cleared the BO oracle-failure pause) | unit (ledger-defined) | ☑ | ☑ | `PriceFeedProxyOracleFailureTest::testResumeRequiresHealthyCurrentSource`; `PriceFeedProxyJpyRedemptionAgeTest::test_resumeCanClearIndependentPauseWithoutCachingAgedQuote` | PASS(ORCL-JPY-AGE-20260830) | Exercised the healthy event payload, unhealthy resume revert, and non-caching of an aged redemption quote |
| ORCL-EVT-012 | `UrgentRedemptionReferenceUnavailable(oracle, stEthUsdPrice)` (direct source diagnostic; not a primary alert source because Proxy fail-closed transactions roll the log back) | unit (ledger-defined) | ☐ | ☐ | `frontend/ops/scripts/events.test.ts`; `frontend/ops/scripts/alert-routing.test.ts` | PARTIAL(ORCL-STETH-AGE-20260831/ops) | Diagnostic-event ingestion and routing to stable Proxy identity pass. Direct-source emission and rollback through Proxy revert await recertification |

### 10.6 Failure and Exceptional Behavior (§12 ERR, no ID)

Price-fetching path branches (fetchPrice / fetchRedemptionPrice):

| # | Trigger | Expected behavior (doc §12) | Firing evidence | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | source success and valid price | update _lastGoodPrice -> return (steady state) | ☐ | | Not run | |
| 2 | source success with JPY round age `>= 30h`, or runtime provenance invalid | normal redemption alone returns `(price, true)` with no cache write, `_handleFailedFetch`, event, or BO pause; normal and urgent are unchanged | ☑ | `PriceFeedProxyJpyRedemptionAgeTest` (14 passed) | PASS(ORCL-JPY-AGE-20260830/automated) | Covers exact 30h, 30h−1s, failed provenance read, bounded gas burn, and fresh recovery |
| 3 | gas guard revert (strict 4 bytes and selector match) | re-revert as-is (no shutdown) | ☐ | | Not run | |
| 4 | other revert / invalid price (0 / type(uint256).max) | proxy shutdownFromOracleFailure -> source lastGoodPrice or Proxy _lastGoodPrice | ☐ | | Not run | |

Placeholder-phase behavior:

| # | Layer | Expected behavior (doc §12) | Firing evidence | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | PriceFeedPlaceholder.fetchPrice() | (1e18, false) (does not trigger shutdown) | ☐ | | Not run | |
| 2 | Vault deposit / redeem | UnderlyingNotSet / UnderlyingMismatch revert | ☐ | | Not run | May share evidence with §7 |
| 3 | dToken convertTo* | TokenInfoNotSet revert | ☐ | | Not run | May share evidence with §6 |
| 4 | cap | 0 (mint impossible) -> setCap(N) releases | ☐ | | Not run | |

Error catalog:

| # | Error | Trigger (reference) | Firing evidence | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | InvalidSource | address(0), or missing/malformed/oversized-return/deploy-time-aged JPY provenance in constructor / confirmSource / confirmSourceEmergency | ☑ | `test_constructorRejectsMissingMalformedAndAgedProvenance`; `test_bothConfirmationPathsRejectMissingProvenanceAtomically`; `test_runtimeProvenanceReturnBombIsBoundedAndStopsOnlyNormalRedemption`; `PriceFeedProxySourceValidationTest` | PASS(ORCL-JPY-AGE-20260830/automated) | Covered by the 140-test Proxy run |
| 2 | RenounceOwnershipDisabled | renounceOwnership call (ORCL-FR-007 / GOV-003) | ☐ | | Not run | |
| 3 | InsufficientGasForExternalCall (re-revert) | gas griefing protection transparency (ORCL-FR-004) | ☐ | | Not run | |
| 4 | CallerNotPriceFeed (upstream) | direct shutdown call on underlying feed -> avoided by Proxy delegation (ORCL-FR-004) | ☐ | | Not run | |
| 5 | UnderlyingNotSet (Vault side) | placeholder branch deposit/redeem (ORCL-FR-008) | ☐ | | Not run | |
| 6 | UnderlyingMismatch (Vault side) | dToken-first order violation (ORCL-FR-009) | ☐ | | Not run | |
| 7 | TokenInfoNotSet (dToken side) | convertTo* in placeholder phase (ORCL-FR-008) | ☐ | | Not run | |
| 8 | InvalidInitialPrice | Initial active-feed constructor fetch cannot establish primary + nonzero price (ORCL-INV-012) | ☑ | `test_expiredSharedProviderRejectsNewActiveFeedDeployments` | PASS(PRELIM-L02) | Confirms custom errors for Standard and dwstETH |

### 10.7 Open Issue Register (ORCL-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| ORCL-TBD-001 | Partially resolved | Values are selected for `PRM-ORACLE-001` / `002` / `007`. However, approval and delivery evidence for the `PRM-ORACLE-002` / `007` stale-high settlement risk remain incomplete under `SYS-RISK-010`. The exact Day-1 candidate freeze, including `PRM-ORACLE-003` / `004`, is incomplete. Branch 2–7 thresholds belong to individual activation packages | SYS-RISK-001 / 010 gates |
| ORCL-TBD-002 | Resolved | Composite inheritance form is finalized (sUSDSPriceFeed inherits sUSDS-pruned CompositePriceFeed, LST secondary fallback removed) -> verify in ORCL-FR-012 / ORCL-SEC-001 rows | |
| ORCL-TBD-003 | Open | Feed-quality criteria and Composite peg implementation form for evaluating XAUT as a collateral candidate (no binding to the current branch map, no activation implied) -> verify ORCL-FR-013 as a future-candidate activation condition | |
| ORCL-TBD-004 | Open | Fallback feed when USDS/USD is deprecated | |
| ORCL-TBD-005 | Resolved | Additional mitigation for source replacement timelock (M-1 related; price guard adopted) -> verify in ORCL-FR-002 / SEC-003 rows | |
| ORCL-TBD-006 | Resolved | The Day-1 dToken backing-peg policy is reflected in ORCL-FR-014 / VAULT-INV-012 | |

---

## 11. Zapper.md (ZAP)

Source of truth: [Zapper.md](../../protocol/product/spec/Zapper.md). Target: `CollateralYieldZapper` (stateless, non-upgradeable).

### 11.1 Functional Requirements (ZAP-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ZAP-FR-001 | openTroveWithRawETH (delegate with referral=`bytes32(0)`, owner=msg.sender) | unit | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol` (2026-06-22: 31 passed) | PASS(unit) | Verified normal open and `_params.owner != msg.sender` revert. Integration/fork not run |
| ZAP-FR-002 | openTroveWithRawETHAndReferral (strict msg.value match, batch consistency, bytes32 referral firing condition, owner=msg.sender) | unit, integration | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol` (2026-06-22: 31 passed) | PASS(unit) | Verified `bytes32` referral emit, wrong ETH, owner mismatch, and rejection of batchManager + annualInterestRate. Integration/fork not run |
| ZAP-FR-003 | openTroveWithUnderlyingPermit (delegate with referral=`bytes32(0)`) | unit | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol` (2026-06-22: 31 passed) | PASS(unit) | Verified permit -> open -> Underlying pull -> dToken collateral without pre-approval. Front-run permit succeeds if allowance remains; invalid signature / insufficient allowance reverts with `PermitFailed` |
| ZAP-FR-004 | permit open + bytes32 referral (no pre-approve required, permit failure revert) | unit, integration | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol` (2026-06-22: 31 passed) | PASS(unit) | Verified `openTroveWithUnderlyingPermitAndReferral` emits `bytes32` referral and permit failure reverts. Integration/fork not run |
| ZAP-FR-005 | addCollWithUnderlying (owner/add manager only, Underlying -> dToken -> addColl) | unit, integration | ☐ | ☐ | | Not run | |
| ZAP-FR-006 | withdrawCollToUnderlying (owner/remove manager, receiver checks, redeem linkage, receiver-delta minimum) | unit, integration | ☑ | ☑ | `test_WithdrawCollToUnderlyingWithMin_UsesFeeTokenReceiverDelta`; `forge test --match-path test/CollateralYieldZapper.t.sol` | PASS(V21/unit) | Fee-on-transfer Underlying below the receiver's immediate floor reverts atomically; integration/fork not run |
| ZAP-FR-007 | withdrawJpydf (authorization, receiver checks, transfer) | unit, integration | ☐ | ☐ | | Not run | |
| ZAP-FR-008 | repayJpydf (add manager only, surplus return after over-repayment) | unit, integration | ☐ | ☐ | | Not run | |
| ZAP-FR-009 | adjustTroveWithUnderlying (4 quadrants: collateral increase/decrease x borrow/repay; authorization, transfers, residual return) | unit, integration | ☐ | ☐ | | Not run | |
| ZAP-FR-010 | closeTroveToUnderlying (authorization, receiver, gas compensation return, close -> redeem -> ETH return) | unit, integration | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol` (2026-06-19: 16 passed) | PASS(unit) | Verified immediate redeem, buffer-shortfall queueing, `WithMin` revert, and gas compensation return. Integration/fork not run |
| ZAP-FR-011 | Removed from Day-1 ABI (flash-loan close / collateral-funded close) | manual / build artifact review | ☑ | ☑ | `rg -n "DFDisabledExchange\|flashLoanProvider\|receiveFlashLoan\|IFlashLoan\|closeTroveFromCollateral\|Balancer" contracts/src contracts/test contracts/script frontend/app/src frontend/df-shared/generated` (2026-06-19: no matches) | PASS(manual/build) | Fresh-deploy policy. Verified absence from production ABI / deploy wiring / frontend flow. Balancer is not a future candidate |
| ZAP-FR-012 | Removed from Day-1 ABI (flash-loan callback) | manual / build artifact review | ☑ | ☑ | Same as above (2026-06-19: no matches) | PASS(manual/build) | Verified callback selector / provider dependency / interface / Balancer adapter absence |
| ZAP-FR-013 | Empty leverage callbacks + receive (state unchanged, receives ETH from WETH.withdraw) | unit | ☐ | ☐ | | Not run | |
| ZAP-FR-014 | ARCHIVED: Sky USDC collateral-ingress variant (slippage floor, zero residual, temporary allowance reset) | archive unit, integration | ☑ | ☑ | `forge test --match-path test/archive/SkyUsdcSUsdsYieldZapper.t.sol`; `forge test --match-path test/SkyUsdcSUsdsConverter.t.sol` | PASS(archive) | Excluded from the official deploy path and active audit scope |
| ZAP-FR-015 | native ETH on-ramp (ETH -> stETH -> wstETH -> dwstETH; route enabled only by an explicit deployment parameter, slippage floor, strict `msg.value` match, stETH rounding-residue sweep) | unit, integration | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol` (47 passed: `test_OpenTroveWithNativeEth_StakesWrapsAndOpensTrove`; `test_OpenTroveWithNativeEthAndReferral_EmitsReferralAndRouteEvents`; `test_OpenTroveWithNativeEth_RevertsWhenSubmitPausedAndPlainPathUnaffected`; `test_OpenTroveWithNativeEth_RevertsWhenMinWstEthOutNotMet`; `test_OpenTroveWithNativeEth_SweepsStEthRoundingResidueToCaller`; `test_OpenTroveWithNativeEth_RevertsOnWrongMsgValue`; `test_OpenTroveWithNativeEth_RevertsWhenRouteUnavailable`; `test_CloseTroveToUnderlying_AfterNativeEthZapReturnsWstEthAndGasComp`; `test_OpenTroveWithNativeEth_ReentrantSubmitIsBlockedByGuard`) | PASS(V14) | The route exists only on instances constructed with `_expectedStEth != address(0)`; a mismatch reverts at deployment. When staking is paused the call reverts with a typed error and the direct wstETH deposit path is unaffected |

### 11.2 Invariants (ZAP-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ZAP-INV-001 | No persistent protocol-configuration or accounting state (constructor-fixed references + `ReentrancyGuard` lock + `AddRemoveManagers` delegation authorizations only) | machine (`forge inspect` storage layout) | ☐ | N/A | | Not run | N/A: static storage layout confirmation (no runtime destructive path). V23 (#1556 A-2): the delegation mappings are a live authorization state made an explicit exception in the normative Zapper.md; verification means changed from manual to machine inspection |
| ZAP-INV-002 | collToken == dToken (derived from AddressesRegistry.collToken()) | unit / manual | ☐ | ☐ | | Not run | |
| ZAP-INV-003 | No underlying / collToken / jpydfToken balances remain after successful completion (residual return; stETH residue carrying shares must be returned, only zero-share nominal dust ≤ 2 wei may remain) | invariant | ☐ | ☐ | | Not run | V23 (#1556 D-1): stETH nominal dust corresponds to 0 shares and cannot be removed by transfer; allowance synced from the normative Zapper.md |
| ZAP-INV-004 | Asset-path consistency for open flow (Underlying -> dToken -> open -> JPYdf transfer) | unit | ☐ | ☐ | | Not run | |
| ZAP-INV-005 | ReferralDeposit fires exactly once only in open flows when _referralCode != `bytes32(0)`, and does not propagate to Vault / core | unit | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol` (2026-06-22: 31 passed) | PASS(unit) | Verified no `ReferralDeposit` for normal open with referral=`bytes32(0)`, exactly one Zapper-emitted event for normal referral open / permit referral open, and matching user/troveId/underlyingAmount/dTokenAmount/jpydfAmount/referralCode |
| ZAP-INV-006 | Three leverage callbacks are empty (no state changes or token movements) | unit | ☐ | ☐ | | Not run | |
| ZAP-INV-007 | Day-1 production ABI has no flash-loan callback / provider dependency / Balancer adapter / fail-fast exchange placeholder | manual (ABI / deploy wiring review) | ☑ | ☑ | `rg -n "DFDisabledExchange\|flashLoanProvider\|receiveFlashLoan\|IFlashLoan\|closeTroveFromCollateral\|Balancer" contracts/src contracts/test contracts/script frontend/app/src frontend/df-shared/generated` (2026-06-19: no matches) | PASS(manual/build) | `forge test --match-path test/DeployLiquity2StrategySelector.t.sol` (12 passed) also verifies active CYZ deploy dependencies exclude this surface |
| ZAP-INV-008 | All user-facing external state-changing functions that move value or make untrusted external calls are nonReentrant (the three `AddRemoveManagers`-inherited setters are explicit exceptions) | manual (modifier coverage) / unit | ☐ | ☐ | | Not run | V23 (#1556 A-3 Owner Decision): `setAddManager` / `setRemoveManager` / `setRemoveManagerWithReceiver` perform only the owner check with no untrusted external call and no value movement; unmodified liquity/bold upstream, no external-audit finding |
| ZAP-INV-009 | ARCHIVED: no route token, archived candidate dToken, or JPYdf remains after Sky-route completion | archive unit / invariant | ☑ | ☐ | archive Sky Zapper suite | PASS(unit) | Archive suite continues checking residue and allowance reset |

### 11.3 Security Requirements (ZAP-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ZAP-SEC-001 | nonReentrant on all user-facing external state-changing functions that move value or make untrusted external calls (reentrancy attack reverts; the three `AddRemoveManagers`-inherited setters are explicit exceptions) | manual (modifier coverage), unit, invariant=ZAP-INV-008 | ☐ | ☐ | | Not run | V23: the rationale for the three exceptions and the `setRemoveManager` self-lock constraint are recorded in the normative Zapper.md ZAP-SEC-001 |
| ZAP-SEC-002 | Beneficiary/executor consistency (owner / add / remove manager roles separated; third-party operations revert) | unit, manual | ☐ | ☐ | | Not run | |
| ZAP-SEC-003 | Return residuals and avoid lockup (over-repayment, dust; stETH residue carrying shares must be returned, only zero-share nominal dust ≤ 2 wei may remain) | unit, invariant=ZAP-INV-003 | ☐ | ☐ | | Not run | V23 (#1556 D-1): stETH nominal-dust allowance synced from the normative Zapper.md |
| ZAP-SEC-004 | Day-1 production ABI has no flash-loan callback / provider dependency / Balancer adapter | manual, invariant=ZAP-INV-007 | ☑ | ☑ | `rg -n "DFDisabledExchange\|flashLoanProvider\|receiveFlashLoan\|IFlashLoan\|closeTroveFromCollateral\|Balancer" contracts/src contracts/test contracts/script frontend/app/src frontend/df-shared/generated` (2026-06-19: no matches) | PASS(manual/build) | Surface removal, not caller-guard auditing, eliminates callback spoofing / provider misbinding |
| ZAP-SEC-005 | Slippage protection (receiver-delta floor revert, floor guarantee under swap price movement) | unit, fork | ☑ | ☑ | `test_WithdrawCollToUnderlyingWithMin_UsesFeeTokenReceiverDelta`; queued-floor violation tests | PARTIAL(V21/unit) | Immediate receiver delta including fee-on-transfer is verified; swap-price-movement fork not run |
| ZAP-SEC-006 | Approve targets restricted to trusted components (including Sky-route allowance reset) | unit, manual | ☐ | ☐ | | Not run | unit added in develop (allowance reset / re-swap for zero-first tokens) |
| ZAP-SEC-007 | Return value check for gas compensation ETH send (send failure reverts) | unit | ☐ | ☐ | | Not run | |

### 11.4 Governance, Operations, and Upgrade Requirements (ZAP-GOV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ZAP-GOV-001 | Non-invasive to Core, Vault, and dToken (diff review) | manual | ☐ | N/A | | Not run | N/A: static diff review item |
| ZAP-GOV-002 | Non-upgradeable, no protocol-configuration state (deploy configuration) | manual | ☐ | N/A | | Not run | N/A: static deploy-configuration confirmation. V23 (#1556 A-2): "stateless" wording aligned with the normative revision (the bound on mutable storage is ZAP-INV-001) |
| ZAP-GOV-003 | referralCode remains off-chain only (no referral argument to Vault / core) | unit / manual | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol` (2026-06-22: 31 passed) + source review (`ReferralDeposit` emit only) | PASS(unit/manual) | Same evidence as ZAP-INV-005 / ZAP-EVT-001. `referralCode` is only emitted through `ReferralDeposit` / Sky route event and is not passed to Vault / BorrowerOperations call arguments |

### 11.5 Event and Monitoring Requirements (ZAP-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ZAP-EVT-001 | ReferralDeposit (firing condition, index, non-propagation) | unit | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol` (2026-06-22: 31 passed) | PASS(unit) | Same evidence as ZAP-INV-005. Logs are decoded to verify `underlyingAmount` / `dTokenAmount` / `jpydfAmount` and indexed `referralCode` |

### 11.6 Failure and Exceptional Behavior (§12 ERR, no ID)

Error catalog (Zapper level):

| # | Error / trigger | Occurrence condition (reference) | Firing evidence | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | msg.value != ETH_GAS_COMPENSATION | ETH sent in open flow other than gas comp (ZAP-FR-002/004) | ☐ | | Not run | |
| 2 | batch consistency violation | batchManager != 0 && annualInterestRate != 0 (open flow) | ☐ | | Not run | |
| 3 | `CollateralYieldZapper__PermitFailed` | try/catch capture of permit failure (ZAP-FR-004) | ☐ | | Not run | Non-permit token may be uncapturable (ZAP-TBD-006) |
| 4 | Unauthorized | owner / add / remove manager mismatch (ZAP-SEC-002) | ☐ | | Not run | |
| 5 | Zapper is not receiver | _requireZapperIsReceiver fails in collateral withdrawal, borrowing, or close flow | ☐ | | Not run | |
| 6 | Callback spoofing | Flash-loan callback surface / Balancer adapter is absent from the Day-1 ABI (ZAP-SEC-004) | ☑ | `rg -n "DFDisabledExchange\|flashLoanProvider\|receiveFlashLoan\|IFlashLoan\|closeTroveFromCollateral\|Balancer" contracts/src contracts/test contracts/script frontend/app/src frontend/df-shared/generated` (2026-06-19: no matches) | PASS(manual/build) | |
| 7 | Slippage floor violation | collLeft < _minExpectedCollateral (ZAP-SEC-005) | ☐ | | Not run | |
| 8 | ETH send failure | gas comp call fails (ZAP-SEC-007) | ☐ | | Not run | |

Dependency-originated reverts (propagation; observable through Zapper):

| # | Trigger | Origin | Firing evidence | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | CapExceeded / TokenInfoNotSet | CollateralVault.deposit (placeholder branch) | ☐ | | Not run | |
| 2 | Below MIN_DEBT / _maxUpfrontFee exceeded / core checks | 🔵 BorrowerOperations | ☐ | | Not run | |
| 3 | swap-backed close / Flash Loan repayment impossible | Route removed from Day-1 Zapper ABI | ☑ | Same absence check as ZAP-FR-011 / ZAP-FR-012 / ZAP-INV-007 | PASS(manual/build) | CYZ does not depend on FlashLoanProvider / Balancer adapter / collateral-funded-close exchange |

### 11.7 Open Issue Register (ZAP-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| ZAP-TBD-001 | Resolved | Do not add requestId re-emit; use return values and Vault events | |
| ZAP-TBD-002 | Resolved | Collateral increases use the Vault deposit return value; collateral decreases still use `convertToDToken` | |
| ZAP-TBD-003 | Resolved | `DeployLiquity2` deploys CYZ for active branches and asserts Vault / dToken / Underlying / BO / JPYdf bindings | FlashLoanProvider / Balancer adapter / collateral-funded-close exchange / fail-fast exchange placeholder are not CYZ constructor dependencies |
| ZAP-TBD-004 | Deferred | Leverage support remains outside MVP; dToken Multiply is not exposed by the frontend | Future enablement must not depend on Balancer / removed Flash Loan callback; use a new contract / route selector design |
| ZAP-TBD-005 | Optional | Native ETH UX for WETH branch is convenience-only; current route treats WETH as ERC-20 Underlying | |
| ZAP-TBD-006 | Resolved | Non-permit tokens use prior approve path; frontend / SDK selects permit capability | |
| ZAP-TBD-007 | Resolved | zombie Trove adjustment is implemented through `adjustZombieTroveWithUnderlying` / `WithMin`; evidence still needed | |
| ZAP-TBD-008 | Frontend UX task | Placeholder branch cap / Underlying unset is dependency behavior; frontend hides/discloses inactive flows | |
| ZAP-TBD-009 | Resolved | `SkyUsdcSUsdsConverter` implements the audited Sky LitePSMWrapper USDC -> USDS route and is deployed by `DeployLiquity2` when `sky-susds` is selected | SkyZapper deploy / manifest / frontend binding remains separate FRNT-FR-013 / FRNT-FR-014 work |
| ZAP-TBD-010 | Conditional | JPYdf/USDC only liquidity / swap route production enablement is a prerequisite for future swap-backed close / collateral-funded repay / Multiply. `UniV4Exchange` itself is included in Day-1 audit scope | Not needed for base open / add / withdraw / close-with-JPYdf. Day-1 standard is JPYdf/USDC Uniswap v4. Curve and direct USDT/USDS/WETH/XAUT JPYdf pools are out of scope. Current ABI has no swap-backed dToken flow |

---

## 12. Parameters.md (PRM, Parameter Source of Truth)

The source of truth for IDs, meanings, units, and invariants is the [Parameter Catalog](../../../jp/protocol/product/parameters/Parameter-Catalog.md). [Parameters.md](../../Parameters.md) is the source of truth for finalized active Branch 0–1 values and deploy-time bootstrap values for reserved Branches 2–7. Verification = **mechanical cross-check of Parameters against deploy inputs / setter values** + forge / configuration checks for inter-parameter invariants (SYS-RISK-005 gate). CR and penalty values are finalized at deployment for active branches and once before activation of a reserved branch after its exact Underlying is selected; they cannot change afterward. In addition to the deploy-tail check, reserved activation requires the Manifest, `RiskParamsFinalized` receipt/event, Registry / BO getters, and TM's CCR getter plus block-pinned `eth_getStorageAt` for the four internal values (with compiler storage-layout and runtime-bytecode attestation), or equivalent atomic-sync Evidence.

### 12.1 Inter-Parameter Invariants (PRM-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PRM-INV-001 | Each branch satisfies SCR < MCR < CCR | forge / deploy and activation configuration inspection | ☑ | ☑ | `forge test --match-path test/DFBranchRiskParams.t.sol` (1 passed); `forge test --match-path test/DeployBranchRiskInvariants.t.sol` (10 passed) (`test_Day1BranchParamsSatisfyEveryInvariant`; `test_RevertWhen_CrOrderingBroken`) | PASS(V18) | Deploy inputs for all eight branches (finalized active values / reserved bootstrap values) are proven against constants and preflight. Reserved final values also use CORE-AR-FR-005 on-chain revalidation and activation readback |
| PRM-INV-002 | MCR = 1 / LLTV (reciprocal relationship) | forge / recalculation | ☐ | N/A | | Not run | N/A: arithmetic identity recalculation only |
| PRM-INV-003 | LIQUIDATION_PENALTY_SP <= LIQUIDATION_PENALTY_REDISTRIBUTION | forge / deploy configuration inspection | ☑ | ☑ | `forge test --match-path test/DFBranchRiskParams.t.sol` (1 passed); `forge test --match-path test/DeployBranchRiskInvariants.t.sol` (10 passed) (`test_RevertWhen_SpPenaltyExceedsRedistribution`) | PASS(V18) | JPY is 5%=5% equal |
| PRM-INV-004 | `MCR × 199 >= (1 + LIQUIDATION_PENALTY_SP) × 200`; `MCR >= 1 + LIQUIDATION_PENALTY_REDISTRIBUTION` | forge evidence | ☑ | ☑ | `RiskParamsFinalization`, `DeployBranchRiskInvariants`, `DFBranchRiskParams`: 34 combined L-03/L-04/I-06/I-09 focused tests pass | Combined candidate PASS; fast Foundry and size gates pass | dJPY/dJGB bootstrap MCR 105.53%; compensation deduction is included. The full premium is not guaranteed below MCR. |
| PRM-INV-005 | Code-enforced bounds (SP >= 5e16, Redist <= 20e16) | unit (Constants MIN/MAX) | ☑ | ☐ | `forge test --match-path test/DFBranchRiskParams.t.sol` (1 passed) | PASS(V18) | SP all 5%=exact lower bound. Out-of-range values are rejected by the `AddressesRegistry` constructor (`SPPenaltyTooLow` / `RedistPenaltyTooHigh`), but there is no DF-side rejection test |
| PRM-INV-006 | SCR satisfies urgent redemption bonus level (about 102%) | forge / deploy configuration inspection | ☑ | ☑ | `forge test --match-path test/DFBranchRiskParams.t.sol` (1 passed); `forge test --match-path test/DeployBranchRiskInvariants.t.sol` (10 passed) (`test_RevertWhen_ScrBelowUrgentRedemptionBonus`; `test_ScrExactlyAtTheBoundIsAccepted`) | PASS(V18) | Minimum JPY 103.30%. Until this campaign the deploy guard compared **MCR**, which is strictly weaker than the published invariant because PRM-INV-001 already forces SCR < MCR (carried over from #859 into #1205). It now compares `p.SCR`, and tests pin both acceptance exactly at the bound and rejection below it |
| PRM-INV-007 | `bufferTargetBps <= 10000`; the required buffer is `max(managedUnderlying * bufferTargetBps / 10000, bufferFloor) + pendingWithdrawals` | unit / deploy configuration inspection | ☑ | ☑ | `test_SetBufferConfig_RevertAboveBpsAndState`; `test_Allocate_DistributesByWeightBps`; `test_Allocate_ZeroTargetBpsUsesAbsoluteFloorAndConfigCorrectionRecovers`; `test_TransferYieldToTreasury_ReservesConfiguredBufferTarget` | PASS(V22) | The former wording `bufferFloor <= bufferTarget` compared incompatible units (`bufferTargetBps` is a ratio, `bufferFloor` an underlying amount); the normative Parameter Catalog explicitly replaced it with the required-buffer formula. This row is synced to that source |

### 12.2 Parameter Value Match Checks (PRM-* Registry)

For each row, happy path = at deployment, active Branches 0–1 match the finalized values in Parameters and reserved Branches 2–7 match its bootstrap values in the on-chain representation (`<X>` = dToken symbol such as DWSTETH); after reserved activation, the approved Manifest's final values match the Registry / BO getters and TM's CCR getter plus attested internal storage or equivalent atomic-sync Evidence. Exception path = encoding (WAD / bps / seconds / dec), boundary, admission rejection while unfinalized, and repeat-finalization rejection.

| ID | Parameter (on-chain constant / setter) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PRM-LLTV | LLTV (not stored on-chain; reciprocal of MCR) | Absorbed by PRM-INV-002 row | ☐ | N/A | | Not run | N/A: not stored on-chain (verification artifact is PRM-INV-002 row) |
| PRM-MCR | MCR (`MCR_D<X>` bootstrap / Registry, BO, and TM effective value) | unit / deploy and activation configuration inspection | ☐ | ☐ | | Not run | Branches 0–1 finalize at deployment. Branches 2–7 are unfinalized with Day-1 bootstrap values and finalize once after the exact Underlying is selected |
| PRM-CCR | CCR (`CCR_D<X>` bootstrap / Registry, BO, and TM effective value) | unit / deploy and activation configuration inspection | ☐ | ☐ | | Not run | Same as above |
| PRM-SCR | SCR (`SCR_D<X>` bootstrap / Registry, BO, and TM effective value) | unit / deploy and activation configuration inspection | ☐ | ☐ | | Not run | Same as above |
| PRM-BCR | BCR (`BCR_D<X>` bootstrap / Registry and BO effective value) | unit / deploy and activation configuration inspection | ☐ | ☐ | | Not run | Same as above |
| PRM-LIQPEN-SP | Liquidation Penalty SP (`LIQUIDATION_PENALTY_SP_D<X>` bootstrap / Registry and TM effective value) | unit / deploy and activation configuration inspection | ☐ | ☐ | | Not run | Same as above |
| PRM-LIQPEN-RD | Redistribution Penalty (`LIQUIDATION_PENALTY_REDISTRIBUTION_D<X>` bootstrap / Registry and TM effective value) | unit / deploy and activation configuration inspection | ☐ | ☐ | | Not run | Same as above |
| PRM-LIQ-KEEPER | Liquidation executor collateral compensation (divisor 0.5% / cap: dwstETH 2 / dUSDC 1,000 units; reserved caps finalized before activation) | unit (may share evidence with §5 Core row 4) | ☐ | ☐ | | Not run | |
| PRM-mintCap | mintCap (`dToken.setCap`, GOV mutable) | unit / deploy configuration inspection | ☐ | ☐ | | Not run | dwstETH=JPY 35M, dUSDC=JPY 100M, dETH=0, Br3–7=0. This is a dToken supply cap, not a direct JPYdf debt ceiling |
| PRM-allocCooldown | allocatorCooldown (`setAllocatorConfig`) | unit / deploy configuration inspection | ☐ | ☐ | | Not run | All 30m. Do not operate with initialize default unchanged (§2-D deploy gate) |
| PRM-allocMaxMove | allocateMaxMove (`setAllocatorConfig`) | unit / deploy configuration inspection | ☐ | ☐ | | Not run | dUSDC=JPY 100M; dwstETH=0 (no Day-1 Strategy); dETH=0; Br3–7=0 |
| PRM-withdrawDelay | withdrawDelay (`setWithdrawDelay`) | unit / deploy configuration inspection | ☐ | ☐ | | Not run | All eight branches use 3 days at Day 1; re-derive before asynchronous Strategy adoption or inert-branch activation |
| PRM-bufferTargetBps | bufferTargetBps (`setBufferConfig`) | unit / deploy configuration inspection | ☐ | ☐ | | Not run | All eight branches use 3.33% at Day 1; re-derive with `withdrawDelay` when the operating model changes |
| PRM-bufferFloor | bufferFloor (`setBufferConfig`) | unit / deploy configuration inspection | ☐ | ☐ | | Not run | All 0 |
| PRM-ORACLE-008 | `PriceFeedProxy.MAX_NORMAL_REDEMPTION_JPY_AGE = 108000` seconds (30h, normal redemption only) | constant / unit boundary / integration / monitor | ☑ | ☑ | `test_redemptionAllowedOneSecondBeforeBoundary`; `test_exactBoundaryStopsOnlyNormalRedemptionWithoutFailureAlarmOrPause`; `frontend/ops/src/lib/snapshot.test.ts`; `frontend/ops/scripts/alerts.test.ts` | PARTIAL(ORCL-JPY-AGE-20260830/automated) | Constant, 30h−1s / exact 30h, invalid provenance, fresh recovery, and safe-head classification code passed. Human delivery and resolution are not run |

### 12.3 Oracle Staleness (§2-C)

**For JPY/USD (row 5), verify equality with `PRM-ORACLE-001` and the strict `<` boundary normally. Day-1 non-JPY feeds are rows 1–4 under ORCL-TBD-001; stETH/ETH risk acceptance is additionally gated by SYS-RISK-010. The future row 6 remains blocked until Branch 4 (dBTC) activation.**

| # | Feed | Threshold | Firing evidence | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | ETH/USD | `PRM-ORACLE-002` | ☐ | | BLOCKED(ORCL-TBD-001) | |
| 2 | stETH/USD | `PRM-ORACLE-003` | ☐ | | BLOCKED(ORCL-TBD-001) | dwstETH market leg |
| 3 | USDC/USD | `PRM-ORACLE-004` | ☐ | | BLOCKED(ORCL-TBD-001) | |
| 4 | stETH/ETH (dwstETH redemption only) | `PRM-ORACLE-007` | ☑ | `frontend/ops/src/lib/snapshot.test.ts`; `frontend/ops/scripts/alerts.test.ts`; `frontend/ops/scripts/alert-delivery.test.ts` | PARTIAL(SYS-RISK-010; No-Go) | Code evidence only for the 88,200s warning / exact 90,000s P0 / resolution after a fresh round. Candidate freeze, risk sign-off, and human delivery are not complete |
| 5 | JPY/USD (common to all branches) | `PRM-ORACLE-001` | ☐ | | Not run | Verify strict `<` stale judgment and no calendar logic |
| 6 | WBTC/BTC (future candidate) | `PRM-ORACLE-005` | ☐ | | BLOCKED(Branch 4 (dBTC) activation) | Linked to Collateral Parameter Policy §2.4 |

### 12.4 Governance Delay Controls (§2-D, finalized 2026-06-12)

Verify by deploy configuration inspection (holder and delay asserts).

| # | Item | Final value | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Shared TimelockController minDelay | 12h (one shared controller for all layers) | ☐ | ☐ | | Not run | |
| 2 | Timelock PROPOSER / EXECUTOR / CANCELLER | GOV multisig / GOV multisig / same Admin multisig as PROPOSER / EXECUTOR; Timelock self-admin from construction, with negative external-admin readback | ☐ | ☐ | | Not run | Day-1 adopts the OZ `TimelockController` default in which the proposer is also granted `CANCELLER_ROLE`; constructor `admin=address(0)`, so no deployer-admin renounce transaction exists |
| 3 | Vault WRITEOFF_ROLE | High-quorum GOV multisig (direct, immediate) | ☐ | ☐ | | Not run | |
| 4 | GUARDIAN_ROLE / Strategy Owner | Guardian multisig (immediate) | ☐ | ☐ | | Not run | |
| 5 | Vault ALLOCATOR_ROLE | Operations bot / multisig | ☐ | N/A | | Not run | N/A: holder configuration only (no delay control) |
| 6 | PriceFeedProxy Owner | GOV multisig (direct, not under Timelock) | ☐ | ☐ | | Not run | Confirm avoidance of double delay and immediate cancel retained |
| 7 | deploy gate: set bounded values for allocateMaxMove / allocatorCooldown | Do not enter operations with initialize defaults (max / 0) | ☐ | ☐ | | Not run | |

### 12.5 Parameter Open Items and Notes (Verification Gates)

| # | Item | Handling | Result | Notes |
| --- | --- | --- | --- | --- |
| 1 | Branches 2–7 Underlying and final Core values are not finalized | Until the Underlying is finalized, verify the placeholder, cap 0, and `riskParamsFinalized == false` (ORCL-FR-008 / VAULT-INV-011 / CORE-AR-INV-003). The Day-1 values in §12.2 are deploy-time bootstrap values; at activation, re-derive all six values from the exact Underlying's stress and finalize them once through CORE-AR-FR-005. If the collateral does not qualify, keep the branch reserved (see the Japanese [Collateral Parameter Policy](../../../jp/protocol/product/policies/Collateral-Parameter-Policy.md) §2.4) | BLOCKED(Underlying / final values not finalized) | |
| 2 | Tight penalty margin for the JPY branch (Day1 Parameter Decision §4) | **forge evidence is mandatory** (same evidence as PRM-INV-004 row) | Not run | Remaining task explicitly stated in doc |
| 3 | Future XAUT candidate has no current branch binding or Day-1 exposure | Negative configuration inspection + activation-package review (same root as ORCL-FR-013 / SYS-RISK-007) | Not run | |

---

## 13. Treasury.md (TRSY, Treasury revenue router)

Source of truth: [Treasury.md](../../protocol/roadmap/spec/Treasury.md). **Note**: this Day-2 module is unimplemented (`contracts/src/Treasury.sol`). Treasury is purpose routing only; SP additional reward buyback / root / claim is verified in §13A, Referral reward budget handling is verified in §13B/§13C, and backstop reserve accounting is verified by CollateralVault / incident policy. Until implementation starts, record TRSY-* rows other than TBD as `BLOCKED(unimplemented)` (do not leave blanks).

### 13.1 Functional Requirements (TRSY-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TRSY-FR-001 | initialize (roles, Foundation Safe, initial purpose destinations / ratios, backstop Vaults, zero/reinitialize revert) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-FR-002 | splitYield (fixed-ratio routing of Underlying to purpose destinations / backstop Vault / Foundation Safe; notification / backstop revert reverts all) | unit, invariant=TRSY-INV-001/002/003 | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-FR-003 | forwardRewardToken (simple forwarding of non-Underlying reward tokens to Foundation Safe; reject Underlying) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-FR-004 | setPurposeShareBps (bounds, future-effective, structurally guarantees Foundation remainder) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-FR-005 | purpose destination / backstop Vault changes (propose/confirm/cancel, reject before delay, disable, underlying match) | unit, invariant=TRSY-INV-005 | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-FR-006 | pauseRouting / unpauseRouting (asymmetric, stop splitYield, keep forwardRewardToken available) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-FR-007 | emergencyBackstopDeposit (routing paused, registered Vault, underlying match, shortfall cap, no approval residue) | unit, invariant=TRSY-INV-006 | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-FR-008 | View group (unsplitBalance / purpose share / destination / backstop Vault / routed total / proposal) | unit | ☐ | N/A | | BLOCKED(unimplemented) | N/A: view-only |
| TRSY-FR-009 | UUPS upgrade (GOV-only, Timelock holder, storage append-only) | unit, manual | ☐ | ☐ | | BLOCKED(unimplemented) | |

### 13.2 Invariants (TRSY-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TRSY-INV-001 | Fund outflows from Treasury are limited to `{purposeDestination[p], backstopVault[token], foundationSafe}`. Treasury has no transfer function with arbitrary `to` | unit / manual (all-function review) | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-INV-002 | `sum(purposeShareBps) <= PURPOSE_SHARE_TOTAL_MAX_BPS` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-INV-003 | `splitYield` never silently reallocates an unset / disabled purpose to another purpose | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-INV-004 | Treasury does not directly transfer or call DEX routers, SP, or Referral participants. The only direct Vault call is the registered `backstopDeposit` path | static review | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-INV-005 | Destination changes cannot take effect before the timelock elapses | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-INV-006 | `emergencyBackstopDeposit` can execute only while routing is paused, `BACKSTOP_DEPOSIT` is active, Vault is registered, underlying matches, and amount is within the shortfall cap | unit / invariant | ☐ | ☐ | | BLOCKED(unimplemented) | |

### 13.3 Event and Monitoring Requirements (TRSY-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TRSY-EVT-001 | YieldRouted(token, amount, foundationAmount, purposes[], destinations[], purposeAmounts[]) | unit (ledger-defined) | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-EVT-002 | RewardTokenForwarded(token, amount) | unit (ledger-defined) | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-EVT-003 | PurposeShareBpsUpdated(purpose, oldBps, newBps) | unit (ledger-defined) | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-EVT-004 | PurposeDestinationChangeProposed/Changed/Cancelled(purpose, destination, readyAt) | unit (ledger-defined) | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-EVT-005 | PurposeDestinationDisabled(purpose, destination) | unit (ledger-defined) | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-EVT-006 | RoutingPaused(account) / RoutingUnpaused(account) | unit (ledger-defined) | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-EVT-007 | BackstopVaultChangeProposed/Changed/Cancelled(token, vault, readyAt) | unit (ledger-defined) | ☐ | ☐ | | BLOCKED(unimplemented) | |
| TRSY-EVT-008 | BackstopDepositedFromTreasury(token, vault, amount, received, emergency) | unit (ledger-defined) | ☐ | ☐ | | BLOCKED(unimplemented) | |

### 13.4 Failure and Exceptional Behavior (§9 ERR, no ID)

| # | Event | Expected behavior (doc §12) | Firing evidence | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Destination contract failure / revert | Entire `splitYield` reverts. Funds remain in Treasury and are not reallocated to another purpose | ☐ | | Not run | |
| 2 | Positive-share purpose destination unset / disabled | `splitYield` reverts. Funds remain unsplit until GOV repairs the destination or sets the share to 0 | ☐ | | Not run | |
| 3 | Positive-share backstop Vault unset / underlying mismatch | `splitYield` / `emergencyBackstopDeposit` reverts. Funds remain unsplit until GOV repairs registration or sets `BACKSTOP_DEPOSIT` share to 0 | ☐ | | Not run | |
| 4 | Ratio misconfiguration | Bounds violations revert. Wrong settings within bounds are detected by governance / monitoring and fixed for future splits | ☐ | | Not run | |
| 5 | Before Day-2 cutover | Vault treasury remains the Safe. Treasury routing does not occur | ☐ | | Not run | |
| 6 | Backing impairment | `pauseRouting` stops normal C/D/Foundation payments. `emergencyBackstopDeposit` can fund registered Vaults within the shortfall cap. Release / restart order is handled by incident policy / governance decision | ☐ | | Not run | |

### 13.5 Open Issue Register (TRSY-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| TRSY-TBD-001 | Open | Finalize `PURPOSE_SHARE_TOTAL_MAX_BPS`, initial `purposeShareBps`, and `TRSY_TIMELOCK_DELAY` values | |
| TRSY-TBD-002 | Open | Decide whether Day-1 Safe-retained funds are routed in one batch after Treasury introduction or gradually over a period | |
| TRSY-TBD-003 | Open | Post-emergency-backstop order for `releaseBackstopToBuffer`, redeem / claim restart, and routing restart (separate incident policy) | |

---

## 13A. SPAdditionalRewardDistributor.md (SPARD)

Source of truth: [Reward-Distributors.md](../../protocol/roadmap/spec/Reward-Distributors.md), SPARD section. **Note**: this Day-2 module is unimplemented (`contracts/src/SPAdditionalRewardDistributor.sol`). It receives the `SP_ADDITIONAL_REWARD` purpose budget from Treasury and handles buyback, TWAB, and Merkle claim.

### 13A.1 Functional Requirements (SPARD-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SPARD-FR-001 | initialize (roles, Treasury, initial reward asset, zero/reinitialize revert) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-FR-002 | Treasury revenue receipt (onlyTreasury, purpose validation, actual-received accounting, share-sum validation) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-FR-003 | executeBuyback (within budget, active reward asset, code-enforced min-out, reject price deviation) | unit, fork | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-FR-004 | notifyEpoch / cancelRoot (per-asset epoch, challenge window, escrow, cancellation) | unit, invariant=SPARD-INV-001/005 | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-FR-005 | claim (cumulative Merkle, no double claim, fixed payout account, CEI) | unit, fuzz, invariant=SPARD-INV-002 | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-FR-006 | governance configuration (reward asset addition, share / buyback config, immediate fail-safe) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-FR-007 | pause (separate buyback / claim pause, GUARDIAN pause, GOV unpause) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-FR-008 | View group | unit | ☐ | N/A | | BLOCKED(unimplemented) | N/A: view-only |
| SPARD-FR-009 | UUPS upgrade (GOV-only, storage append-only) | unit, manual | ☐ | ☐ | | BLOCKED(unimplemented) | |

### 13A.2 Invariants (SPARD-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SPARD-INV-001 | `totalClaimed[asset] <= totalFunded[asset]` | invariant | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-INV-002 | `claimed[account][asset]` monotonically increases | unit / fuzz | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-INV-003 | Buyback can execute only within `buybackBudget[token][asset]` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-INV-004 | Min-out is code-enforced and cannot be lowered arbitrarily by caller | unit / fork | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-INV-005 | A root cannot be used for claims until the challenge window elapses | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-INV-006 | This contract does not modify SP / Core state | static review | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-INV-007 | Cancel funding returns to rewardBudget and is not double-counted with totalFunded | unit / invariant | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-INV-008 | No outflow route through an arbitrary receiver / call / router | static review | ☐ | ☐ | | BLOCKED(unimplemented) | |

### 13A.3 Event and Monitoring Requirements (SPARD-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SPARD-EVT-001 | `SPAdditionalRevenueReceived(token, amount)` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-EVT-002 | `BuybackExecuted(token, asset, amountIn, amountOut, minOut)` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-EVT-003 | `EpochFunded(asset, epochId, root, amount, activatesAt)` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-EVT-004 | `RootCancelled(asset, epochId)` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-EVT-005 | `Claimed(asset, account, payout, cumulative)` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-EVT-006 | Reward asset / share / buyback config update events | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPARD-EVT-007 | Buyback / claim pause and unpause events | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |

### 13A.4 Open Issue Register (SPARD-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| SPARD-TBD-001 | Resolved | Seven-day epoch, 48-hour challenge, cancellation on pending-root disagreement, claim pause after activation | `sp-twab-v1`; Reward Distributors §4.1 / SP Additional Reward Root Runbook |
| SPARD-TBD-002 | Open | JPYdf buyback venue / clip / slippage / TWAP threshold | |
| SPARD-TBD-003 | Open | Conditions to add DFT or other reward assets | |
| SPARD-TBD-004 | Open | Additional controls to reduce loss ceiling if an invalid root passes (claim rate limit, etc.) | |

---

## 13B. BorrowReferralRewardDistributor.md (BRRD)

Source of truth: [Reward-Distributors.md](../../protocol/roadmap/spec/Reward-Distributors.md), BRRD section. **Note**: this Day-2 module is unimplemented (`contracts/src/BorrowReferralRewardDistributor.sol`). It receives the `BORROW_REFERRAL` purpose budget from Treasury and handles buyback, epoch roots, and referrer claim.

### 13B.1 Functional Requirements (BRRD-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BRRD-FR-001 | initialize (roles, Treasury, initial reward asset, zero/reinitialize revert) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-FR-002 | Treasury revenue receipt (onlyTreasury, `BORROW_REFERRAL` validation, actual-received accounting) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-FR-003 | executeBuyback (reward asset validation, within budget, reject price deviation, caller cannot lower min-out) | unit, fork | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-FR-004 | epoch root post / cancel (ROOT_POSTER post, challenge window, GUARDIAN cancelRoot) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-FR-005 | claim (Merkle proof, cumulative delta, CEI, fixed referrer payout) | unit, invariant=BRRD-INV-002/003/005 | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-FR-006 | governance configuration (reward asset addition, share / buyback config, future-effective) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-FR-007 | pause (separate buyback / claim pause, GOV unpause) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-FR-008 | View group | unit | ☐ | N/A | | BLOCKED(unimplemented) | N/A: view-only |
| BRRD-FR-009 | UUPS upgrade (GOV-only, storage append-only) | unit, manual | ☐ | ☐ | | BLOCKED(unimplemented) | |

### 13B.2 Invariants (BRRD-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BRRD-INV-001 | Does not receive Treasury purposes other than `BORROW_REFERRAL` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-INV-002 | `totalClaimed[asset] <= totalFunded[asset]` | invariant | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-INV-003 | `claimed[referrer][asset]` is monotonic | unit / fuzz | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-INV-004 | Buyback can execute only within `buybackBudget[token][asset]` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-INV-005 | Payout destination is fixed to the Merkle leaf `referrer`; no arbitrary payout address argument exists | unit / manual | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-INV-006 | No normal-flow manual payout route to the Foundation Safe exists | static review | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-INV-007 | Does not repurpose funds into SP-deposit Referral / SP additional reward / PIL budgets | manual / static review | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-INV-008 | Cancel funding returns to rewardBudget and is not double-counted with totalFunded | unit / invariant | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-INV-009 | No outflow route through an arbitrary receiver / call / router | static review | ☐ | ☐ | | BLOCKED(unimplemented) | |

### 13B.3 Event and Monitoring Requirements (BRRD-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BRRD-EVT-001 | `BorrowReferralRevenueReceived(token, amount)` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-EVT-002 | `BorrowReferralBuybackExecuted(token, asset, amountIn, amountOut, minOut)` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-EVT-003 | `BorrowReferralEpochFunded(asset, epochId, root, amount, campaignHash, activatesAt)` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-EVT-004 | `BorrowReferralRootCancelled(asset, epochId)` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-EVT-005 | `BorrowReferralClaimed(asset, referrer, payout, cumulative)` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-EVT-006 | Reward asset / share / buyback config update events | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| BRRD-EVT-007 | Buyback / claim pause and unpause events | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |

### 13B.4 Open Issue Register (BRRD-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| BRRD-TBD-001 | Open | Concrete Borrow Referral cap, campaign period, minimum holding, and clawback conditions | |
| BRRD-TBD-002 | Open | Epoch length, challenge window, and claim pause operation | |
| BRRD-TBD-003 | Open | Initial payout asset composition and price guards if assets other than JPYdf are used | |
| BRRD-TBD-004 | Open | Handling of unused budget: carryover / Foundation return / burn, etc. | |
| BRRD-TBD-005 | Open | Event / ledger revision if future rewardable volume uses something other than `jpydfAmount` | |

---

## 13C. SPDepositReferralRewardDistributor.md (SPDRD)

Source of truth: [Reward-Distributors.md](../../protocol/roadmap/spec/Reward-Distributors.md), SPDRD section. **Note**: this Day-2+ module is unimplemented (`contracts/src/SPDepositReferralRewardDistributor.sol`). It receives the `SP_DEPOSIT_REFERRAL` purpose budget from Treasury and handles SP-deposit attribution source gate, buyback, epoch roots, and referrer claim.

### 13C.1 Functional Requirements (SPDRD-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SPDRD-FR-001 | initialize (roles, Treasury, initial reward asset, zero/reinitialize revert) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-FR-002 | Treasury revenue receipt (onlyTreasury, `SP_DEPOSIT_REFERRAL` validation, registered source, actual-received accounting) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-FR-003 | attribution source gate (sourceHash registration, raw SP deposit source rejection, future roots only) | unit, manual | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-FR-004 | executeBuyback (reward asset validation, within budget, reject price deviation, caller cannot lower min-out) | unit, fork | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-FR-005 | epoch root post / cancel (sourceHash match, ROOT_POSTER post, challenge window, GUARDIAN cancelRoot) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-FR-006 | claim (Merkle proof, cumulative delta, CEI, fixed referrer payout) | unit, invariant=SPDRD-INV-003/004/005 | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-FR-007 | governance configuration (reward asset addition, share / buyback config, future-effective) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-FR-008 | pause (separate buyback / claim pause, GOV unpause) | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-FR-009 | View group | unit | ☐ | N/A | | BLOCKED(unimplemented) | N/A: view-only |
| SPDRD-FR-010 | UUPS upgrade (GOV-only, storage append-only) | unit, manual | ☐ | ☐ | | BLOCKED(unimplemented) | |

### 13C.2 Invariants (SPDRD-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SPDRD-INV-001 | Does not receive Treasury purposes other than `SP_DEPOSIT_REFERRAL` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-INV-002 | Does not receive Treasury revenue before source registration | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-INV-003 | `totalClaimed[asset] <= totalFunded[asset]` | invariant | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-INV-004 | `claimed[referrer][asset]` is monotonic | unit / fuzz | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-INV-005 | Payout destination is fixed to the Merkle leaf `referrer`; no arbitrary payout address argument exists | unit / manual | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-INV-006 | No normal-flow manual payout route to the Foundation Safe exists | static review | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-INV-007 | Does not change Core StabilityPool accounting / ABI | static review | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-INV-008 | Does not repurpose funds into Borrow Referral / SP additional reward / PIL budgets | manual / static review | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-INV-009 | Cancel funding returns to rewardBudget and is not double-counted with totalFunded | unit / invariant | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-INV-010 | No outflow route through an arbitrary receiver / call / router | static review | ☐ | ☐ | | BLOCKED(unimplemented) | |

### 13C.3 Event and Monitoring Requirements (SPDRD-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SPDRD-EVT-001 | `SPDepositReferralRevenueReceived(token, amount)` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-EVT-002 | `SPDepositReferralAttributionSourceUpdated(sourceHash)` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-EVT-003 | `SPDepositReferralBuybackExecuted(token, asset, amountIn, amountOut, minOut)` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-EVT-004 | `SPDepositReferralEpochFunded(asset, epochId, root, amount, sourceHash, activatesAt)` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-EVT-005 | `SPDepositReferralRootCancelled(asset, epochId)` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-EVT-006 | `SPDepositReferralClaimed(asset, referrer, payout, cumulative)` | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-EVT-007 | Reward asset / share / buyback config update events | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |
| SPDRD-EVT-008 | Buyback / claim pause and unpause events | unit | ☐ | ☐ | | BLOCKED(unimplemented) | |

### 13C.4 Open Issue Register (SPDRD-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| SPDRD-TBD-001 | Open | Adopt sJPYdf / wrapper / signed attribution model | |
| SPDRD-TBD-002 | Open | TWAB period, minimum holding, withdrawal / liquidation / self-referral exclusion conditions | |
| SPDRD-TBD-003 | Open | Epoch length, challenge window, and claim pause operation | |
| SPDRD-TBD-004 | Open | Initial payout asset composition and price guards if assets other than JPYdf are used | |
| SPDRD-TBD-005 | Open | Handling of unused budget: carryover / Foundation return / burn, etc. | |

---

## 13D. InterestRouter.md (IRTR, InterestRouterForwarder)

Source of truth: [InterestRouter.md](../../protocol/product/spec/InterestRouter.md). Target: `contracts/src/InterestRouterForwarder.sol`. This non-upgradeable helper module absorbs Liquity core's immutable `interestRouter` constraint through a thin external receiver and routes PIL funds (the remaining 25% of aggregated interest) to the final recipient.

### 13D.1 Functional Requirements (IRTR-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| IRTR-FR-001 | constructor (reject zero jpydfToken / recipient / owner, set initial values, emit initial events) | unit | ☐ | ☐ | | Not run | |
| IRTR-FR-002 | route (entire held JPYdf balance, fixed recipient, zero-balance no-op, permissionless, return value) | unit, invariant=IRTR-INV-001/002, integration | ☐ | ☐ | | Not run | |
| IRTR-FR-003 | setRecipient (owner-only, reject zero, future-effective) | unit | ☐ | ☐ | | Not run | |
| IRTR-FR-004 | 2-step ownership, pending cancellation, renounce disabled | unit | ☐ | ☐ | | Not run | |
| IRTR-FR-005 | View functions | unit | ☐ | N/A | | Not run | N/A: view-only |

### 13D.2 Invariants (IRTR-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| IRTR-INV-001 | Funds can flow only to recipient. There is no transfer function with destination argument and no rescue path | unit / manual | ☐ | ☐ | | Not run | |
| IRTR-INV-002 | route sends the entire held JPYdf balance to the current recipient and has no partial-transfer path | unit / invariant | ☐ | ☐ | | Not run | |
| IRTR-INV-003 | recipient changes are owner-only and cannot set zero | unit | ☐ | ☐ | | Not run | |
| IRTR-INV-004 | owner cannot renounce, so recipient-change authority cannot be stranded | unit | ☐ | ☐ | | Not run | |
| IRTR-INV-005 | Does not make state-changing calls into core | manual / CI | ☐ | ☐ | | Not run | |
| IRTR-INV-006 | In DF dToken wiring, every branch interestRouter points to the same Forwarder | deploy / handover verification | ☐ | ☐ | | Not run | |

### 13D.3 Security Requirements (IRTR-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| IRTR-SEC-001 | Owner key compromise blast radius (only recipient changes; route still sends funds to the fixed recipient) | unit / manual | ☐ | ☐ | | Not run | |
| IRTR-SEC-002 | Permissionless safety of route | unit | ☐ | ☐ | | Not run | |
| IRTR-SEC-003 | Prevent stranded funds from zero recipient or renounce | unit | ☐ | ☐ | | Not run | |
| IRTR-SEC-004 | Reentrancy / CEI | unit / manual | ☐ | ☐ | | Not run | |
| IRTR-SEC-005 | Abuse boundary for pending ownership cancellation | unit / manual | ☐ | ☐ | | Not run | |

### 13D.4 Governance, Operations, and Upgrade Requirements (IRTR-GOV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| IRTR-GOV-001 | Role configuration and handover | manual / deploy | ☐ | ☐ | | Not run | |
| IRTR-GOV-002 | Deploy inputs and fail-fast checks | deploy / manual | ☑ | ☑ | `DeployLiquity2._verifyDFInterestRouter`; `DFGovernanceHandoverTest::{test_InterestRouterVerifierAcceptsForwarder,test_InterestRouterVerifierRejectsDirectOwnableReceiver,test_InterestRouterVerifierRejectsWrongTokenOrRecipient,test_HandoverPreflightRejectsSplitRoutersBeforeMutation}` | PASS(manual/unit) | Deploy-tail checks token / recipient / owner / pendingOwner / all-branch sameness. handover/verify/accept also recheck manifest and recipient |
| IRTR-GOV-003 | Day-1 -> Day-2 recipient migration | manual | ☐ | N/A | | Not run | |
| IRTR-GOV-004 | Upgrade policy (non-upgradeable, redeploy) | manual | ☐ | N/A | | Not run | |
| IRTR-GOV-005 | Per-chain wiring gate | deploy / manual | ☐ | ☐ | | Not run | Gate before mainnet dToken wiring activation |

### 13D.5 Event and Monitoring Requirements (IRTR-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| IRTR-EVT-001 | Routed(recipient, amount) | unit | ☐ | ☐ | | Not run | |
| IRTR-EVT-002 | RecipientUpdated(oldRecipient, newRecipient) | unit | ☐ | ☐ | | Not run | Includes constructor initial value |
| IRTR-EVT-003 | OwnershipTransferStarted / OwnershipTransferred | unit | ☐ | ☐ | | Not run | Includes constructor initial owner |

### 13D.6 Failure and Exceptional Behavior (§12 ERR, no ID)

| # | Event | Expected behavior (doc §12) | Trigger demonstrated | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | recipient is wrong | owner / Timelock corrects it with setRecipient. Previously routed funds are handled at the moved-to destination | ☐ | | Not run | |
| 2 | route keeper outage | JPYdf remains in the Forwarder and anyone can call route. Only delivery is delayed | ☐ | | Not run | |
| 3 | non-JPYdf token accidentally sent | No rescue. The token remains stranded, and route transfers only jpydfToken | ☐ | | Not run | IRTR-TBD-003 |

### 13D.7 Open Issue Register (IRTR-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| IRTR-TBD-001 | Open | Concrete PIL address (Day-1 recipient) and mainnet value | Parameters freeze gate |
| IRTR-TBD-002 | Resolved (2026-06-15) | route is operated by keeper. Standard entrypoint is `frontend/ops route-interest` | Route Runbook is the operations source of truth |
| IRTR-TBD-003 | Open | Whether to support rescue for incorrectly sent tokens | Default is no rescue |
| IRTR-TBD-004 | Open | Day-2 distribution mechanism connection spec | Generally pass-through |
| IRTR-TBD-005 | Resolved (2026-06-22) | `SP_YIELD_SPLIT` is canonicalized as a Core inherited constant in `Constants.sol` and `Liquity-v2-Core-Spec.md` (CORE-AP-FR-003/007 plus constants table). Parameters.md is canonical only for DF-adjusted values and does not list `SP_YIELD_SPLIT` | InterestRouter references the value only as receiver context |
| IRTR-TBD-006 | Resolved (2026-06-18) | Deploy-tail binding verification is implemented | `DeployLiquity2._verifyDFInterestRouter` fail-fast checks token / recipient / owner / pendingOwner / all-branch sameness. handover/verify/accept scripts also recheck manifest and recipient |

---

## 13E. PILAllocator.md (PILA, PILAllocator / IInitiative / UniV4MerklInitiative)

Source of truth: [PILAllocator.md](../../protocol/product/spec/PILAllocator.md). Targets: `contracts/src/PILAllocator.sol` (235 nSLOC) and `contracts/src/Initiatives/UniV4MerklInitiative.sol` (174 nSLOC). This is the Phase-A liquidity-incentive layer: it takes the PIL received from `InterestRouterForwarder`, splits it across registered initiatives by admin weight, and connects to a Uniswap v4 Merkl campaign.

> **Audit-scope status**: both contracts are **inside the A full-review body** as "Audited but gated production code" in [Contract-Audit-Scope-And-nSLOC](../guides/Contract-Audit-Scope-And-nSLOC.md) — not user-facing or funded before the route / PIL gates are approved, but production source that can affect funds, routing, and authorization once configured. This section tracks their 51 IDs. Day-1 starts inert with a total weight of 0; activation is approved through a separate PIL activation package.

### 13E.1 Functional Requirements (PILA-FR)

| ID | Requirement (summary) | Prescribed verification | Normal | Abnormal | Test entity | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PILA-FR-001 | constructor (rejects a non-contract token and a zero `minDistribute`; establishes the epoch origin / duration and the owner / guardian) | unit | ☑ | ☑ | `test_RevertWhen_ConstructorTokenIsNotContract`; `test_RevertWhen_ConstructorMinDistributeIsZero`; `test_LoadConfigReadsJpydfManifestAndPilaEnv` | PASS(V14) | The normal path is exercised by every PILAllocator test's setUp and by the deploy-config test |
| PILA-FR-002 | epoch interface (`epoch()` and the epoch origin, compatible with upstream `liquity/V2-gov`) | unit, static | ☑ | ☑ | `test_EpochInterfaceAnswersUpstreamSelectors`; `test_EpochNumberingFollowsUpstreamSemantics` | PASS(V16) | The four vendored upstream `IGovernance` selectors (`EPOCH_START` / `EPOCH_DURATION` / `epoch` / `epochStart`) are staticcalled against a live allocator. Selector parity alone would pass on a 0-indexed or differently-anchored epoch, so the origin, both sides of a boundary, and `floor(elapsed/duration)+1` are pinned too |
| PILA-FR-003 | registerInitiative (admin-only, JPYdf recipient validation, registration hook, `MAX_INITIATIVES` bound) | unit | ☑ | ☑ | `test_RegisterInitiativeValidatesJpydfRecipientAndCallsHook`; `test_RevertWhen_RegisteringInvalidJpydfRecipient`; `test_RevertWhen_RegisteringMoreThanMaxInitiatives` | PASS(V14) | |
| PILA-FR-004 | unregisterInitiative (admin-only, removal from weights and the initiative array, unregistration hook) | unit | ☑ | ☑ | `test_UnregisterRemovesWeightAndInitiative` | PASS(V14) | |
| PILA-FR-005 | setWeights (admin-only, duplicates rejected, total is 0 or `1e18`) | unit | ☑ | ☑ | `test_SetWeightsRejectsDuplicatesAndInvalidTotalWeight`; `test_SetWeightsCanDeactivateBySettingAllWeightsZero` | PASS(V14) | |
| PILA-FR-006 | distribute (weight-proportional, permissionless, no double distribution) | unit, integration | ☑ | ☑ | `test_DistributePushesByFullWeightAndRepeatedCallNoops` | PASS(V14) | Includes the repeated call within one epoch being a no-op |
| PILA-FR-007 | threshold and carry-over (below `minDistribute`, or all weights zero, nothing is distributed and the PIL stays in the allocator) | unit | ☑ | ☑ | `test_DistributeReturnsZeroWhenBelowThresholdOrNoWeights` | PASS(V14) | |
| PILA-FR-008 | pause / unpause / setGuardian (emergency stop and guardian rotation) | unit | ☑ | ☑ | `test_PauseUnpauseAndOwnership`; `test_GuardianCanBeUpdatedByOwner` | PASS(V14) | |
| PILA-FR-009 | View surface (registered initiative array, weights, epoch views) | unit | ☑ | N/A | `test_UnregisterRemovesWeightAndInitiative`; `test_SetWeightsRejectsDuplicatesAndInvalidTotalWeight` | PASS(V14) | N/A: view-only. There is no test dedicated to the view surface; it is covered incidentally by the register / unregister / setWeights assertions |
| PILA-FR-010 | ownership (2-step, pending cancellation, renounce disabled) | unit | ☑ | ☑ | `test_PauseUnpauseAndOwnership`; `test_TransferOwnershipZeroCancelsPendingOwner` | PASS(V14) | |
| PILA-FR-101 | `IInitiative` (fully upstream-compatible, 4 hooks) | unit, static | ☑ | N/A | `test_HooksAreNoopAndPhaseBReusable` | PASS(V14) | N/A: the hooks are no-ops, so there is no abnormal path. Upstream signature parity itself is tracked as PILA-INV-007 |
| PILA-FR-102 | `onAfterAllocateLQTY` retained (unused in Phase-A, kept for Phase-B reuse) | unit, static | ☑ | N/A | `test_HooksAreNoopAndPhaseBReusable` | PASS(V14) | N/A: unused hook |
| PILA-FR-201 | UniV4MerklInitiative constructor (Merkl condition acceptance, argument validation) | unit | ☑ | ☑ | `test_ConstructorAcceptsMerklConditions`; `test_RevertWhen_ConstructorArgsInvalid` | PASS(V14) | |
| PILA-FR-202 | createCampaign (no-op below threshold, keeper priority with a public fallback window, suppression of duplicate campaigns, allowance cleared per call) | unit | ☑ | ☑ | `test_CreateCampaignNoopsBelowThreshold`; `test_CreateCampaignPullsAmountAndClearsAllowance`; `test_CreateCampaignRejectsPublicCallerBeforeFallbackWindow`; `test_CreateCampaignAllowsPublicCallerInsideFallbackWindow`; `test_CanCreateCampaignReflectsBalanceWindowAndExistingCampaign`; `test_CreateCampaignNoopsAfterCampaignForStartExists` | PASS(V14) | |
| PILA-FR-203 | getCampaignData (encoding of poolId / weights / blacklist) | unit | ☑ | N/A | `test_GetCampaignDataUsesEmptyWhitelistBlacklistAndHooks` | PASS(V14) | N/A: pure encoding. The Day-1 blacklist is empty (PILA-TBD-003) |
| PILA-FR-204 | initiative hook (lightweight no-op) | unit | ☑ | N/A | `test_HooksAreNoopAndPhaseBReusable` | PASS(V14) | N/A: no-op |

### 13E.2 Invariants (PILA-INV)

| ID | Requirement (summary) | Prescribed verification | Normal | Abnormal | Test entity | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PILA-INV-001 | `distribute()` can only pay registered initiatives; there is no function that takes a destination as an argument | unit / static | ☑ | N/A | `test_DistributePushesByFullWeightAndRepeatedCallNoops`; `test_UnregisterRemovesWeightAndInitiative`; code review (external surface of `PILAllocator.sol`) | PASS(V14) | N/A: no arbitrary-destination transfer API exists, so an abnormal path cannot be constructed |
| PILA-INV-002 | `Σweight` is 0 or `1e18`; partial sums never leave unallocated weight | unit | ☑ | ☑ | `test_SetWeightsRejectsDuplicatesAndInvalidTotalWeight`; `test_SetWeightsCanDeactivateBySettingAllWeightsZero` | PASS(V14) | |
| PILA-INV-003 | A revert or OOG in one initiative's hook does not block distribution to the others (`safeCallWithMinGas` isolation), and hook success is observable in the event | unit / fuzz | ☑ | ☑ | `test_DistributeIsolatesFailingHookAfterTransfer`; `test_DistributeIsolatesRevertBombHookAfterTransfer`; `test_DistributeBlocksReentrantHookAndContinues` | PASS(V14) | `hookSucceeded` on `Distributed` is asserted with `expectEmit` (same evidence as PILA-EVT-004) |
| PILA-INV-004 | With zero initiatives or all weights zero, all PIL stays in the allocator (activation-agnostic) | unit / integration | ☑ | N/A | `test_DistributeReturnsZeroWhenBelowThresholdOrNoWeights`; `test_SetWeightsCanDeactivateBySettingAllWeightsZero` | PASS(V14) | N/A: retention is the expected behavior |
| PILA-INV-005 | No state-changing calls into 🔵 Core / `JpydfToken` / `InterestRouterForwarder` (receive only) | manual / static | ☑ | N/A | Static check (full enumeration of external calls in `PILAllocator.sol`, develop `a09d1620`) | PASS(V17) | N/A: no such call exists, so there is no abnormal path. The complete set of external interactions is (1) `jpydfToken.safeTransfer`, the pass-through mandated by FR-006, (2) the assembly `call` in `_safeCallWithMinGas`, whose target is always a registered initiative, and (3) `IJpydfToken.requireValidRecipient`, read-only inside an `internal view` function. There are zero references to `InterestRouterForwarder` or any Liquity Core contract, and no privileged JpydfToken surface (mint / burn / `setBranchAddresses`) is touched |
| PILA-INV-006 | Registration, unregistration, weights, and unpause are executable only through the shared Timelock (only the GUARDIAN's pause is immediate) | unit / manual | ☑ | ☑ | `test_RequireConfigRejectsMainnetCodelessAdminRoles`; `test_RequireConfigAllowsMainnetContractAdminRoles`; `test_PauseUnpauseAndOwnership` | PASS(V14) | The deploy config enforces that mainnet admin roles are contracts (Timelock / Safe). Evidence of the actual handover is governed by the role handover work (#1150) |
| PILA-INV-007 | `IInitiative` matches upstream `liquity/V2-gov` signatures exactly, so Phase-B can reuse the same initiative unmodified | static / diff | ☑ | ☑ | `test_InitiativeHookSelectorsMatchUpstream`; `test_InitiativeHookSignaturesAreCanonical` | PASS(V16) | Imports upstream `IInitiative` from `lib/V2-gov` directly and compares all four hook selectors. DF redeclares the structs locally, so the tuple-expanded canonical signatures are pinned as well. Mutation check: widening `UserState.unallocatedOffset` from `uint256` to `uint128` fails both tests |
| PILA-INV-008 | Registered initiatives are bounded by `MAX_INITIATIVES=32`, so the `distribute()` loop cannot become unbounded | unit / manual | ☑ | ☑ | `test_RevertWhen_RegisteringMoreThanMaxInitiatives` | PASS(V14) | |

### 13E.3 Security Requirements (PILA-SEC)

| ID | Requirement (summary) | Prescribed verification | Normal | Abnormal | Test entity | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PILA-SEC-001 | Merkl trust boundary (authoritative `DistributionCreator`, condition acceptance, fee model) | manual / fork | ☐ | ☐ | | Not run | Confirming the mainnet Merkl address and the actual fee is the PILA-TBD-004 activation gate; the unit tests run against a mock |
| PILA-SEC-002 | Blast radius of an admin key compromise (no arbitrary-destination transfer, bounded set of payees) | manual / static | ☑ | N/A | Static review (full authorization map, develop `a09d1620`) plus `test_DistributePushesByFullWeightAndRepeatedCallNoops`; `test_RevertWhen_RegisteringInvalidJpydfRecipient` | PASS(V17) | N/A: no single-transaction theft path exists, so an abnormal path cannot be constructed. Authorization map: owner-only = `registerInitiative` / `unregisterInitiative` / `setWeights` / `unpause` / `setGuardian` / `transferOwnership` / `renounceOwnership` (disabled, `view`); guardian-only = `pause`; permissionless = `distribute` / `acceptOwnership`. No function takes a fund destination as a parameter (INV-001). A compromised owner still cannot steal in one transaction: it must register an initiative (which must pass `requireValidRecipient`), then set weights, then wait for someone to call `distribute()` — and the first two go through the Timelock (INV-006) while emitting EVT-001 / EVT-003. The §9 statement omitted `setGuardian` and ownership, corrected in this change |
| PILA-SEC-003 | Merkl approvals are per-call and limited to the campaign amount (hardened relative to upstream's max approval) | unit | ☑ | ☑ | `test_CreateCampaignPullsAmountAndClearsAllowance` | PASS(V14) | Asserts the allowance returns to 0 after the pull |
| PILA-SEC-004 | Initiative isolation (one initiative's failure does not propagate to the others) | unit | ☑ | ☑ | `test_DistributeIsolatesFailingHookAfterTransfer`; `test_DistributeIsolatesRevertBombHookAfterTransfer` | PASS(V14) | Includes a revert bomb (oversized returndata) |
| PILA-SEC-005 | Reentrancy / CEI | unit | ☑ | ☑ | `test_DistributeBlocksReentrantHookAndContinues`; `test_CreateCampaignBlocksReentrantMerklCallback` | PASS(V14) | Covers both the allocator hook and the Merkl callback direction |
| PILA-SEC-006 | Permissionless triggering with campaign front-running prevented (keeper priority window, no regeneration of an existing campaign) | unit | ☑ | ☑ | `test_CreateCampaignRejectsPublicCallerBeforeFallbackWindow`; `test_CreateCampaignAllowsPublicCallerInsideFallbackWindow`; `test_CreateCampaignNoopsAfterCampaignForStartExists` | PASS(V14) | |

### 13E.4 Governance, Operations, and Upgrade Requirements (PILA-GOV)

| ID | Requirement (summary) | Prescribed verification | Normal | Abnormal | Test entity | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PILA-GOV-001 | Role composition and handover (owner = Timelock, guardian separated) | unit / manual | ☑ | ☑ | `test_RequireConfigRejectsMainnetCodelessAdminRoles`; `test_RequireConfigAllowsMainnetContractAdminRoles`; `test_DeploymentSaltRequiresExplicitSaltOnMainnet` | PASS(V14) | Covers the deploy-config gate only; evidence of the executed handover is governed by #1150 |
| PILA-GOV-002 | Upstream connection (`forwarder.setRecipient(PILAllocator)`) | integration / manual | ☐ | ☐ | | Not run | The end-to-end forwarder -> allocator -> distribute -> Merkl integration has not been run |
| PILA-GOV-003 | Phase-A activation and activation-agnostic behavior | manual | ☐ | N/A | | Not run | Day-1 is inert with a total weight of 0; activation is approved in the PIL activation package |
| PILA-GOV-004 | Phase-A -> Phase-B (vote-based allocation) migration | manual | ☐ | N/A | | Not run | Day-2 item |
| PILA-GOV-005 | Extension boundary (adding initiatives; Curve-family initiatives are outside Phase-A scope) | manual | ☐ | N/A | | Not run | Day-2 item |
| PILA-GOV-006 | Upgrade policy (non-upgradeable; replacement means a new instance plus re-registration) | manual / static | ☑ | N/A | Static confirmation (full enumeration of inheritance and upgrade surface, develop `a09d1620`) | PASS(V17) | N/A: no upgrade path exists, so there is no abnormal case. The declarations are only `contract PILAllocator is ReentrancyGuard` and `contract UniV4MerklInitiative is IInitiative, ReentrancyGuard` — no `Initializable`, UUPS, or proxy inheritance, no `initialize` or `upgradeTo`, and zero `delegatecall` (the two assembly blocks are a `call` and gas arithmetic). Venue and configuration values are all `immutable` |

### 13E.5 Event and Monitoring Requirements (PILA-EVT)

| ID | Requirement (summary) | Prescribed verification | Emission proven | Test entity | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| PILA-EVT-001 | `InitiativeRegistered(initiative, atEpoch, hookSucceeded)` | unit | ☑ | `test_RegisterInitiativeValidatesJpydfRecipientAndCallsHook` (`expectEmit`) | PASS(V16) | |
| PILA-EVT-002 | `InitiativeUnregistered(initiative, atEpoch, hookSucceeded)` | unit | ☑ | `test_UnregisterRemovesWeightAndInitiative` (`expectEmit`) | PASS(V16) | |
| PILA-EVT-003 | `WeightsUpdated(initiatives, weights)` | unit | ☑ | `test_SetWeightsCanDeactivateBySettingAllWeightsZero` (`expectEmit`) | PASS(V16) | Asserted on the deactivating update, where both initiatives appear with weight 0 |
| PILA-EVT-004 | `Distributed(initiative, amount, epoch, hookSucceeded)` | unit | ☑ | `test_DistributeIsolatesFailingHookAfterTransfer` (`expectEmit` asserts both `hookSucceeded` false and true) | PASS(V14) | |
| PILA-EVT-005 | `NewMerklCampaign(epoch, amount, campaignId)` / `MerklCampaignAlreadyCreated(epoch, startTimestamp, amount, campaignId)` | unit | ☑ | `test_CreateCampaignPullsAmountAndClearsAllowance` (`expectEmit`); `test_CreateCampaignNoopsAfterCampaignForStartExists` (`expectEmit`) | PASS(V16) | On the duplicate-suppression branch `amount` is the initiative's balance at emission, not a cumulative total |
| PILA-EVT-006 | `Paused()` / `Unpaused()` | unit | ☑ | `test_PauseUnpauseAndOwnership` (`expectEmit` in both directions) | PASS(V16) | |
| PILA-EVT-007 | `GuardianUpdated(oldGuardian, newGuardian)` | unit | ☑ | `test_GuardianCanBeUpdatedByOwner` (`expectEmit`) | PASS(V16) | Mutation check: swapping the argument order fails the test |

### 13E.6 Open-Item Register (PILA-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| PILA-TBD-001 | Open | Target Uniswap v4 pool (Day-1 assumes the single `JPYdf/USDC` v4 pool; whether multiple pairs are needed) | Value-freeze gate in the PIL activation package |
| PILA-TBD-002 | Open | Allocation parameters (`EPOCH_DURATION` / `minDistribute` / campaign threshold / creator / window) | Candidate values live in Parameters.md `PRM-PILA-*`; the freeze is the activation package |
| PILA-TBD-003 | Open | Blacklist mechanism (empty on Day-1, no targets) | Default is immutable-empty |
| PILA-TBD-004 | Open | Merkl dependency (authoritative `DistributionCreator` address, condition acceptance, actual fee) | Activation gate for PILA-SEC-001 |
| PILA-TBD-005 | Open | Final scope of approvals (whether to keep per-call approval) | Decided once PILA-TBD-004 confirms the actual fee |
| PILA-TBD-006 | Resolved | Reflected in `PILA-GOV-003` | |
| PILA-TBD-007 | Resolved | Reflected in `PILA-FR-001` and the requirement-ID convention | |
| PILA-TBD-008 | Resolved | Reflected in `SYS-FR-009` and the documents indexes | |
---

## 14. Frontend.md (FRNT, Off-Chain)

Source of truth: [Frontend.md](../../protocol/product/spec/Frontend.md). Verification method types follow doc §13 (unit / component / e2e-local / build / ci-guard / visual / manual / monitor). e2e-local runs the full local stack: anvil -> deploy -> subgraph -> frontend. FR methods transcribe each FR's individual Verification (area-level §13 rows are summaries). SEC / ERR / INV apply the area-level primary verification from §13.

### 14.1 Functional Requirements (FRNT-FR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FRNT-FR-001 | Mechanically generated chain and contract bindings | build / ci-guard / e2e-local | ☐ | ☐ | | Not run | |
| FRNT-FR-002 | Single-source on-chain constants | ci-guard / unit | ☐ | ☐ | | Not run | |
| FRNT-FR-003 | Mechanically generated ABI and types | build / ci-guard | ☐ | ☐ | | Not run | |
| FRNT-FR-004 | fail-fast validation of environment config schema | build / unit | ☐ | ☐ | | Not run | Release gate (§14.7) |
| FRNT-FR-005 | Wallet connection | e2e-local / manual | ☐ | ☐ | | Not run | |
| FRNT-FR-006 | Transaction lifecycle | e2e-local / component / unit | ☐ | ☐ | | Not run | |
| FRNT-FR-007 | Minimized and explicit approvals (approve / permit) | e2e-local / component | ☐ | ☐ | | Not run | |
| FRNT-FR-008 | Data-source role separation and freshness management | e2e-local / unit / monitor | ☑ | ☐ | `frontend/ops/src/lib/publicStats.ts`; `frontend/ops/scripts/public-stats.test.ts`; `.github/workflows/frontend-tests.yml` | Partial | DF-managed public stats JSON is generated from RPC snapshots. subgraph freshness, user-app integration, and APR time series remain open |
| FRNT-FR-009 | JPY-denominated display and numeric conventions | unit / visual / component | ☐ | ☐ | | Not run | |
| FRNT-FR-010 | Internationalization (i18n) | build / component | ☐ | ☐ | | Not run | Delivery order is FRNT-TBD-008 |
| FRNT-FR-011 | JPY DeFi service / JPYdf token wording (upstream brand replacement, full grep) | visual / ci-guard (wording lint) / manual | ☐ | ☐ | | Not run | |
| FRNT-FR-012 | Dynamic support for 8 branches | e2e-local / component / unit | ☐ | ☐ | | Not run | |
| FRNT-FR-013 | Borrowing flow (1 Tx aggregation) | e2e-local / component | ☐ | ☐ | | Not run | production PASS requires CYZ / SkyZapper manifest, bindings, and user-app adoption. Current multi-step fallback is temporary UX |
| FRNT-FR-014 | Position management (adjust, repay, close, rate change) | e2e-local / component | ☐ | ☐ | | Not run | dToken branch collateral-funded repay / flash close are absent from the Day-1 ABI. Future support needs a new entrypoint satisfying ZAP-TBD-010 and asset-specific reverse route requirements |
| FRNT-FR-015 | dToken collateral management (mint / redeem) | e2e-local / component | ☐ | ☐ | | Not run | |
| FRNT-FR-016 | Delayed redemption queue and claim | e2e-local / component | ☐ | ☐ | | Not run | |
| FRNT-FR-017 | Earn (Stability Pool) | e2e-local / component | ☐ | ☐ | | Not run | Additional SP rewards hidden until FRNT-TBD-003 |
| FRNT-FR-018 | Redemption | e2e-local / component | ☐ | ☐ | | Not run | |
| FRNT-FR-019 | Branch health and backing-ratio display | e2e-local / component / visual | ☐ | ☐ | | Not run | |
| FRNT-FR-020 | Position and history listability | e2e-local / component | ☐ | ☐ | | Not run | |
| FRNT-FR-021 | Risk and disclaimer display | visual / manual / component | ☐ | ☐ | | Not run | |
| FRNT-FR-022 | Disable upstream governance UI (Stake) | visual / build | ☐ | ☐ | | Not run | |
| FRNT-FR-023 | Multiply (leverage) gate (hidden by flag) | build / visual | ☐ | ☐ | | Not run | FRNT-TBD-002 / ZAP-TBD-004 / ZAP-TBD-010 |
| FRNT-FR-024 | "Prepare and visualize" model for privileged operations | e2e-local / component / manual | ☐ | ☐ | | Not run | |
| FRNT-FR-025 | Parameter-change proposal builder | unit / component / e2e-local | ☑ | ☑ | `pnpm --filter @jpydf/console build`; static `writeoffStrategyPrincipal` calldata-shape check | PASS(V3) | 3-arg `writeoffStrategyPrincipal` calldata and Strategy weight/cap input guards checked |
| FRNT-FR-026 | Oracle source-replacement flow | e2e-local / component | ☐ | ☐ | | Not run | |
| FRNT-FR-027 | Emergency operations (pause / unpause, double confirmation, announcement banner) | e2e-local / manual | ☐ | ☐ | | Not run | |
| FRNT-FR-028 | ALLOCATOR operations screen | e2e-local / component | ☐ | ☐ | | Not run | |
| FRNT-FR-029 | timelock and pending-operation queue | component / e2e-local / manual | ☐ | ☐ | | Not run | |
| FRNT-FR-030 | Operation audit trail | e2e-local / manual | ☐ | ☐ | | Not run | |
| FRNT-FR-031 | Branch overview monitoring | e2e-local / visual / monitor | ☑ | ☑ | `frontend/ops/scripts/liquidation-risk.test.ts`; `frontend/console/src/components/MonitoringPanel.test.tsx` | Partial | Unit/component coverage verifies one-block scans, last zombie, ICR boundaries, ordering, and incomplete/stale/empty degradation. Production monitor and visual evidence remain open |
| FRNT-FR-032 | Oracle monitoring | e2e-local / monitor / visual | ☐ | ☐ | | Not run | |
| FRNT-FR-033 | Vault and Strategy monitoring | e2e-local / monitor / visual | ☐ | ☐ | | Not run | |
| FRNT-FR-034 | Treasury and revenue-flow monitoring | e2e-local / visual | ☐ | ☐ | | Not run | Hide unsettled items until spec finalization |
| FRNT-FR-035 | Alert integration | monitor / manual | ☐ | ☐ | | Not run | |
| FRNT-FR-036 | Public transparency | visual / manual | ☑ | ☐ | `frontend/ops export-stats`; `frontend/ops/scripts/public-stats.test.ts` | Partial | Generates public JSON for supply, collateral value, branch health, and backing ratio. Production delivery procedure is still open |

### 14.2 Consistency Invariants (FRNT-INV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FRNT-INV-001 | Display matches on-chain (amounts, rates, and fees on confirmation screens come from RPC at the same reference block) | unit / component / monitor | ☐ | ☐ | | Not run | |
| FRNT-INV-002 | Constant mirror match (CI mechanical cross-check with Constants.sol / Parameters.md) | build / ci-guard | ☐ | ☐ | | Not run | Release gate |
| FRNT-INV-003 | Do not request signature without simulation | e2e-local / component | ☐ | ☐ | | Not run | |
| FRNT-INV-004 | No secrets (no private keys, privileged API keys, or personal data in distribution, repo, or public env vars) | ci-guard / build / manual | ☐ | ☐ | | Not run | |

### 14.3 Security Requirements (FRNT-SEC)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FRNT-SEC-001 | Supply chain (lockfile pinned, dependency audit, no third-party domain code) | ci-guard / build / manual | ☐ | ☐ | | Not run | Release gate. The `nanoid` GHSA-2v37-7h3g-55p8 detected 2026-08-13 (advisory range `<3.3.18`) was resolved by the 3.3.18 override in #1547 (#1556 C-1); the full row is judged when the release gate runs |
| FRNT-SEC-002 | Delivery integrity (DNSSEC, company-managed, CSP / SRI) | ci-guard / build / manual | ☐ | ☐ | | Not run | |
| FRNT-SEC-003 | Display integrity (sanitize external strings, full address confirmation) | ci-guard / build / manual | ☐ | ☐ | | Not run | |
| FRNT-SEC-004 | Approval safety (spender limited to known contracts; no arbitrary-address approval) | ci-guard / build / manual | ☐ | ☐ | | Not run | |
| FRNT-SEC-005 | Phishing resistance (single ledger of official links, rel attributes) | ci-guard / build / manual | ☐ | ☐ | | Not run | |
| FRNT-SEC-006 | Privacy (analytics opt-in, addresses not linked to PII) | ci-guard / build / manual | ☐ | ☐ | | Not run | |
| FRNT-SEC-007 | Admin surface separation (not reachable from public app, separate delivery) + public Ops decommission guard | ci-guard / build / manual | ☐ | ☐ | | Not run | |
| FRNT-SEC-008 | Endpoint keys (browser read credentials may be shared; public treatment, all-domain restrictions, aggregate usage cap, revocable) | ci-guard / build / manual | ☐ | ☐ | | Not run | |

### 14.4 Governance, Operations, and Upgrade Requirements (FRNT-GOV)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FRNT-GOV-001 | Company ownership of assets (domain, hosting, RPC / subgraph, analytics, statistics API) | manual (ledger-defined) | ☐ | N/A | | Not run | N/A: asset ownership confirmation |
| FRNT-GOV-002 | Release management (version, source commit mapping, rollback procedure) | manual / build (ledger-defined) | ☐ | ☐ | | Not run | |
| FRNT-GOV-003 | Change management and requirement traceability (spec changes first go to FRNT-ID; implementation PR references IDs) | manual (ledger-defined) | ☐ | N/A | | Not run | N/A: process compliance confirmation |
| FRNT-GOV-004 | Upstream following (periodic Liquity v2 app intake, diff ledger) | manual (ledger-defined) | ☐ | N/A | | Not run | N/A: periodic operation process confirmation |
| FRNT-GOV-005 | Audit acceptance (implementation x verification-method ledger for FR / INV / SEC, zero uncovered items) | This ledger itself | ☐ | N/A | | Not run | Satisfied by completion of all §14 rows |

### 14.5 Telemetry and Monitoring Requirements (FRNT-EVT)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FRNT-EVT-001 | Client exception collection (no PII, release-level regression detection) | monitor / manual (ledger-defined) | ☐ | ☐ | | Not run | |
| FRNT-EVT-002 | Synthetic monitoring (liveness, RPC / subgraph response, key screen rendering) | monitor (ledger-defined) | ☐ | ☐ | | Not run | |
| FRNT-EVT-003 | tx success/failure measurement (submission count, failure rate, revert reason aggregation) | monitor (ledger-defined) | ☐ | ☐ | | Not run | |

### 14.6 Failure and Exceptional Behavior (FRNT-ERR)

| ID | Requirement (summary) | Specified verification method | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FRNT-ERR-001 | RPC failure (fallback, degraded display when all paths down, writes stopped) | e2e-local / component / manual | ☐ | ☐ | | Not run | |
| FRNT-ERR-002 | subgraph degradation (freshness warning, visual distinction from current-value data) | e2e-local / component / manual | ☐ | ☐ | | Not run | |
| FRNT-ERR-003 | Chain mismatch (write UI blocked, switch affordance) | e2e-local / component / manual | ☐ | ☐ | | Not run | |
| FRNT-ERR-004 | tx failure (custom error decode, human-readable reason, retry affordance) | e2e-local / component / manual | ☐ | ☐ | | Not run | |
| FRNT-ERR-005 | Branch abnormality (oracle failure, shutdown, or pause detected; new operations blocked) | e2e-local / component / manual | ☐ | ☐ | | Not run | |
| FRNT-ERR-006 | Incident announcement (full-screen banner without code change) | e2e-local / component / manual | ☐ | ☐ | | Not run | |

### 14.7 Acceptance Principles (doc §13)

| # | Principle | Satisfaction condition | Result | Notes |
| --- | --- | --- | --- | --- |
| 1 | docs <-> code parity | implementation, tests, and PRs reference FRNT-ID, and all FR / INV / SEC rows have zero uncovered items in this ledger (FRNT-GOV-005) | Not run | |
| 2 | e2e-local as first-class acceptance method | Major flows (borrow -> adjust -> Earn -> redeem -> claim) are reproducible in local end-to-end environment | Not run | |
| 3 | Release gate | FRNT-INV-002, FRNT-FR-004, and FRNT-SEC-001 are mandatory CI gates | Not run | |

### 14.8 Open Issue Register (FRNT-TBD)

| ID | Status | Handling | Notes |
| --- | --- | --- | --- |
| FRNT-TBD-001 | Open | DFT staking / governance UI (replacement for FRNT-FR-022) | |
| FRNT-TBD-002 | Open | Multiply activation conditions (JPYdf DEX liquidity, JPYdf/USDC Uniswap v4 final leg, asset-specific pre-legs, dToken leverage design) -> verify FRNT-FR-023 with gate OFF | Linked to ZAP-TBD-004 / ZAP-TBD-010 / Liquidity-Route-Policy. Curve and direct USDT/USDS/WETH/XAUT JPYdf pools are not Day-1 gate conditions; the gate is constrained sendable v4 routes / hooks |
| FRNT-TBD-003 | Open | Display of additional SP rewards / Treasury distribution (hidden until finalized) -> verify FRNT-FR-017/034 while hidden | |
| FRNT-TBD-004 | Partially resolved | Initial backend implemented as public health JSON from `frontend/ops export-stats`, and `frontend/app/src/protocol-stats.ts` reads it through `NEXT_PUBLIC_PROTOCOL_STATS_URL`. Production hosting/company ownership/runtime health moves to `Frontend-Production-Delivery-Gate.md` evidence. APR time series is Day-2 | Linked to FRNT-TBD-007 / FRNT-GOV-001 |
| FRNT-TBD-005 | Partially resolved | The Admin Console production hostname is pinned to `https://admin.jpydf.com`, and its gate is defined in `documents/jp/contributors/deltaforesight/delivery-plans/Admin-Console-Production-Gate.md`. Remaining open work is collecting concrete DNS / IdP / RPC key / noindex / role snapshot / Safe calldata evidence | Linked to FRNT-SEC-007 / FRNT-SEC-008 / FRNT-GOV-001 |
| FRNT-TBD-006 | Partially resolved | Mirror delivery (IPFS / ENS) is not adopted on Day 1. The official HTTPS origin remains canonical, and the optional Day-2 adoption gate / exclusions / No-Go / evidence are defined in `documents/jp/contributors/deltaforesight/delivery-plans/Frontend-Mirror-Delivery-Policy.md`. Remaining open work is collecting concrete mirror URL / CID / ENS / domain allowlist / incident announcement / rollback evidence | Linked to FRNT-SEC-002 / FRNT-SEC-005 / FRNT-SEC-008 / FRNT-GOV-001 |
| FRNT-TBD-007 | Partially resolved | The User App production hostname is pinned to `https://app.jpydf.com` and separated from the `https://jpydf.com` Product site delivery boundary. The production delivery gate is defined in `documents/jp/contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md`. Remaining open work is collecting concrete DNS / account / endpoint / monitoring / rollback evidence | Linked to FRNT-SEC-002 / FRNT-SEC-005 / FRNT-SEC-008 / FRNT-GOV-001 |
| FRNT-TBD-008 | Partially resolved | Mainnet i18n gate is defined in `documents/jp/contributors/deltaforesight/delivery-plans/Frontend-UX-Readiness-Gate.md`. Remaining open work is collecting primary locale / exposed locale switch / reachable screen copy evidence | Linked to FRNT-FR-009 / FRNT-FR-010 / FRNT-ERR-004 |
| FRNT-TBD-009 | Partially resolved | Mainnet mobile / in-wallet browser gate is defined in `documents/jp/contributors/deltaforesight/delivery-plans/Frontend-UX-Readiness-Gate.md`. Remaining open work is collecting viewport / wallet modal / tx confirmation / failure state evidence | Linked to FRNT-ERR-004 / FRNT-EVT-002 |

---

## 15. Multichain.md (MCHN, Explicit Exclusion from Verification)

[Multichain.md](../../archive/Multichain.md) is **Deprecated / Out of Scope historical material** (ADR-004 / SYS-FR-006 / README "frozen as historical IDs"). All `MCHN-*` IDs are **not active requirements for current implementation or audit and are excluded from verification**. This is an explicit exclusion, not an omission; do not reuse `MCHN-*` for future activation. Current Day-1 verification only covers the dormant `JpydfToken` bridge-ready surface and proves that no bridge minter or adapter is active at launch. Day-2+ minter registration, operator-only canary / public route open, and cap ramp use [Bridge-Minter-Activation-Gate](../../protocol/operations/runbooks/Bridge-Minter-Activation-Gate.md) Stage A/B/C and `CORE-BT-*` gates instead.

However, "not active on Day-1" itself is verified (one row below; same root as SYS-FR-006 / SYS-CON-004 / SYS-INV-003 / ADR-004):

| # | Check item | Specified verification method (ledger-defined) | Happy path | Exception path | Test artifact | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Implementation has dormant bridge-ready token surface but no active Day-1 bridge minter, pending proposal, adapter connection, or other-chain issuance path | Unit + deploy manifest evidence + JpydfToken supply-authority enumeration | ☐ | ☐ | `JpydfTokenTest::test_BridgeReadinessIsDormantAfterCoreSetup`; `JpydfTokenTest::test_BridgeRolesMustBeContractsAndSeparated`; `JpydfTokenTest::test_BridgeMintRejectsProtocolRecipients` | PASS(unit) | Deploy manifest evidence remains open. Exception path = non-Core cannot call Core `mint`; non-minter cannot call `bridgeMint`. This row does not approve Stage A/B/C activation |

---

## 15.1 Current-Spec Delta Trace

The following rows bring this auditor-facing ledger forward to the current source-of-truth specifications. They do not claim new test results; every result remains `Not run` unless an artifact is named.

`SYS-RISK-008` and `SYS-RISK-009` are tracked only in §4.5 and are intentionally not duplicated in this delta trace.

| ID | Requirement (summary) | Verification | Result |
| --- | --- | --- | --- |
| PRM-ORACLE-001 | JPY/USD staleness threshold | parameter/env/fork-boundary cross-check | Not run |
| PRM-ORACLE-002 | ETH/USD staleness threshold | parameter/env/fork-boundary cross-check | Not run |
| PRM-ORACLE-003 | stETH/USD staleness threshold | parameter/env/fork-boundary cross-check | Not run |
| PRM-ORACLE-004 | USDC/USD staleness threshold | parameter/env/fork-boundary cross-check | Not run |
| PRM-ORACLE-005 | future Branch 4 (dBTC) feed threshold is activation-package scoped | activation-package negative gate | Not run |
| PRM-ORACLE-006 | JPY soft-freeze maximum duration | parameter / constant / boundary cross-check | Not run |
| CORE-BO-FR-001 | open Trove including debt, fee, collateral, and ownership transition | parity / unit / integration | Not run |
| CORE-BT-FR-013 | bridge-admin and dormant-readiness views | unit / deploy manifest | Not run |
| CORE-BT-INV-003 | Day-1 bridge readiness remains dormant | unit / deploy manifest | Not run |
| CORE-BT-GOV-001 | bridge admin is separated from Core owner and assigned through the approved holder package | unit / governance handover evidence | Not run |
| STGY-INV-011 | a Strategy's dedicated external-venue boundary is explicit and cannot be bypassed by a generic selector | unit / static review | Not run |
| STGY-EVT-012 | Strategy-kind or venue-boundary lifecycle event required by current common Strategy spec | unit / event assertion | Not run |

The SPARD / BRRD / SPDRD invariant and event IDs formerly grouped here now have full rows in §13A–§13C (ledger sync 2026-07-26, applied 2026-08-05).

---

## 16. Completion Criteria and Revision Rules

### 16.1 Completion Criteria (Audit Acceptance)

Only when all of the following hold can the project claim that "everything defined as a requirement is implemented and verified in the local environment":

1. **Coverage**: all IDs extracted from source-of-truth docs (matching §3 aggregation) exist in this ledger; missing numbers and out-of-scope items (MCHN and open TBD) are explicitly stated with reasons.
2. **All rows closed**: every row result is `PASS` or `N/A(reason)`. Do not write "complete" while `Not run` / `FAIL` / `BLOCKED` remains (resume after gates are resolved).
3. **Happy path and exception path**: both sides for each ID are `✅` or `N/A(reason)`.
4. **Evidence**: every PASS row has a test artifact (transcribed from execution logs) and campaign ID, and §2 traces back to commit SHA and execution commands.
5. **Double-check**: for each campaign, re-confirm that the mechanical diff (grep-based) between the full ID set in docs and the full ID set in this ledger is empty (because docs continue to change).

### 16.2 Revision Rules

- When IDs are added or revised in source-of-truth docs, add or update rows in this ledger (**doc revision first, ledger follows**; do not define behavior in the reverse direction).
- IDs follow the append-only convention in docs. Do not issue independent IDs in the ledger (non-ID check rows are identified by # sequence and content text in the tables).
- Test names and results live only in this ledger. Do not write them back into source-of-truth docs (compliance with documentation-standard guardrails 1 and 2).
- If a conflict between spec and implementation is found during verification: record FAIL with the requirement definition as authoritative -> file issue -> reverify after fix. If the requirement is wrong, revise the doc first (PR), then update the ledger.

### 16.3 Related Documents

- [Requirements Spec Standard](../../README.md#requirements-spec-standard) - source of truth for ID conventions and the "do not write test names in docs" guardrail
- [Development-Plan.md](../plans/Development-Plan.md) - phase ToDo and audit acceptance
- [Governance-Roles-Timelock.md](../../protocol/product/policies/Governance-Roles-Timelock.md) - design source of truth for §12.4 governance delay controls
- `engineering/historical-reviews/` - location for manual verification records (configuration review and runbook review)
