# PIL / InterestRouter Differential Review - 2026-06-16

## Executive Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 2 |
| Low | 1 |

**Overall Risk:** Medium before follow-up, Low after the follow-up fixes listed below.
**Recommendation:** Approve after the listed verification commands remain green on the final diff.

**Follow-up status:** The two Medium findings below were fixed in the same work session after this review. Prepare/Accept now run shared-router preflight before mutations, and the admin console now exposes split-router balances with an aggregate total.

**Scope reviewed:**
- `contracts/script/DeployLiquity2.s.sol`
- `contracts/script/PrepareDFGovernanceHandover.s.sol`
- `contracts/script/AcceptDFGovernanceHandover.s.sol`
- `contracts/script/VerifyDFGovernanceHandover.s.sol`
- `contracts/test/DFGovernanceHandoverXAUTGate.t.sol`
- `frontend/console/src/lib/reads.ts`
- `frontend/console/src/components/ContractMapPanel.tsx`

## What Changed

The change adds explicit InterestRouterForwarder checks to the deploy and DF handover scripts, adds tests for rejecting direct ownable receivers and token/recipient mismatches, and adds an admin console panel that shows where the 25% PIL share is minted.

## Findings

### Medium: Prepare/Accept can broadcast partial handover changes before proving all branches share the same router

**Files:**
- `contracts/script/PrepareDFGovernanceHandover.s.sol:80`
- `contracts/script/PrepareDFGovernanceHandover.s.sol:82`
- `contracts/script/PrepareDFGovernanceHandover.s.sol:84`
- `contracts/script/AcceptDFGovernanceHandover.s.sol:45`
- `contracts/script/AcceptDFGovernanceHandover.s.sol:47`
- `contracts/script/AcceptDFGovernanceHandover.s.sol:49`

**Description:**
Both scripts verify branch 0's InterestRouter and immediately mutate it (`transferOwnership` in Prepare, `acceptOwnership` in Accept) before the loop checks that every branch has the same router. With `forge script --broadcast`, transactions already sent before a later script revert are not rolled back as one atomic transaction. If the manifest is split or corrupted, branch 0's router can be partially handed over before the script fails on a later branch.

**Impact:**
Operational inconsistency during a governance ceremony. A malformed manifest could leave the InterestRouter pending owner or owner changed while the rest of the handover did not complete.

**Recommendation:**
Add a read-only preflight phase before any broadcasted mutation:
- load and validate all branch `interestRouter` values,
- validate Forwarder token/recipient,
- validate all required per-branch addresses and branch count,
- only then call `_startTwoStepHandover` / `_acceptIfPending`.

**Test Gap:**
No test currently models a split-router manifest and asserts that no mutation is attempted before the mismatch is detected.

### Medium: Admin console reports only the first router's JPYdf balance when routers are split

**Files:**
- `frontend/console/src/lib/reads.ts:178`
- `frontend/console/src/lib/reads.ts:179`
- `frontend/console/src/lib/reads.ts:205`
- `frontend/console/src/components/ContractMapPanel.tsx:340`
- `frontend/console/src/components/ContractMapPanel.tsx:341`

**Description:**
`readInterestRouterOverview()` detects multiple routers and adds a warning, but then selects the first unique router and reads only that router's JPYdf balance. The UI still shows a single "InterestRouter target" and "JPYdf held by router" value. In the exact failure mode operators care about, this can under-report PIL funds held by the other router addresses.

**Impact:**
Operators may see the split-router warning but still misread the displayed balance as the full 25% PIL balance. That weakens the "where did the 25% go?" diagnostic.

**Recommendation:**
When `uniqueRouters.size > 1`, display a per-router table with JPYdf balance per router and an aggregate total. Keep the branch table, but make the headline stat "split routers detected" instead of presenting one router as canonical.

**Test Gap:**
No frontend test or fixture covers split-router data and verifies balance rendering.

### Low: Handover Forwarder verification is ABI-shape based, not code-identity based

**Files:**
- `contracts/script/PrepareDFGovernanceHandover.s.sol:115`
- `contracts/script/AcceptDFGovernanceHandover.s.sol:78`
- `contracts/script/VerifyDFGovernanceHandover.s.sol:126`

**Description:**
The handover scripts classify a router as valid if it exposes `boldToken()` and `recipient()` with expected values, then rely on the generic owner/pendingOwner checks. A contract that mimics those view methods but does not implement the intended `route()` behavior could pass the handover checks.

**Impact:**
Low in the normal deploy path, because `DeployLiquity2` deploys `InterestRouterForwarder` itself. The risk is mainly manifest hygiene: the handover scripts can be pointed at arbitrary deployed bytecode.

**Recommendation:**
If this should be production-hard, add one more verification layer: either a codehash/runtime check for the expected Forwarder, or a zero-balance `staticcall` smoke test for `route()` plus explicit owner/pendingOwner checks in the Forwarder verifier.

## Positive Notes

- The new deploy-tail check rejects Governance/direct receivers for DF dToken wiring.
- Prepare/Accept/Verify now all require `DF_INTEREST_ROUTER_RECIPIENT`, so operators must state the intended final PIL destination.
- The admin console converts the current local direct-router state into an explicit warning instead of surfacing a raw ABI/RPC error.

## Verification Performed

- `forge test --match-contract DFGovernanceHandoverXAUTGateTest -vvv` from `contracts/`: 8 passed.
- `pnpm -C frontend/console build`: passed.
- `git diff --check` on reviewed files: passed.
- Browser check:
  - `http://localhost:3001/` Contracts view displayed `direct / legacy`, router balance, and no browser errors.
  - `http://localhost:3000/` initial page loaded without browser errors.

## Limitations

- Review focused on the current local diff and the PIL/InterestRouter handover path.
- The worktree contains unrelated pre-existing changes and generated `frontend/console/dist` changes; those were not treated as authored changes in this review.
- Full redeploy against a clean local chain was not performed during this review.
