# M-01 Differential Security Review

## Executive summary

| Severity | New findings |
| --- | ---: |
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |

**Overall residual risk:** Low.

**Recommendation:** Approve M-01 remediation.

The change restores provider liveness after a fresh JPY/USD response without
weakening expiry during an unhealthy episode. All 27 changed paths were
reviewed. There are no untested production-code changes, no removed
authorization or value-transfer checks, and no newly exposed public function.
The shared provider has deployment-wide reach, but the new transition is gated
by the existing strict Chainlink freshness validator.

## What changed

**Source baseline:** `fe3d3d0e182b8189202dee3a3db8103bd0df1de7`

**Audit-repository baseline:** `472e1643ae34e70542a309d0ac208d1e6853b8d2`

**Review date:** 2026-08-12

| Area | Change | Risk |
| --- | --- | --- |
| `JpyUsdRateProvider.fetchJpyUsdRate()` | Reads the oracle before consulting the episode-expiry latch; a fresh round clears the episode | High |
| `DFPriceFeedBase`, `DFWstETHPriceFeed`, `JpyFreezeLib` | Comments align branch-local shutdown with provider recovery | Low |
| Provider / feed / proxy tests | Cover fresh recovery, stale non-recovery, later re-expiry, and branch split | Low |
| JP/EN specification and operations policy | Define per-episode expiry and require branch-state inventory after recovery | Medium |
| Snapshot reconstruction scripts and evidence | Pin and reproduce the one-finding patch on the source baseline | Medium |

The only functional production-code change is at
`source-snapshot/contracts/src/PriceFeeds/JpyUsdRateProvider.sol:63-81`.
There is no storage-layout, constructor, interface, authority, or transfer-path
change.

## Security analysis

The changed state flow is:

1. Any caller enters `fetchJpyUsdRate()`.
2. The immutable oracle is read through `_getCurrentChainlinkResponse()`.
3. Only `_isFresh()` success can update the live rate and clear
   `jpyFreezeExpired` (`JpyUsdRateProvider.sol:64-75`).
4. If the response is not fresh, the existing expiry latch still returns
   `(lastGoodJpyRate, true)` (`JpyUsdRateProvider.sol:78-81`).
5. A later unhealthy episode starts from a cleared `jpyFrozenSince` and can
   independently reach the unchanged 24-hour bound.

The following invariants remain intact:

- invalid, zero, future, stale, superseded, and reverting rounds cannot clear
  expiry;
- a gas-starved oracle call still reverts with
  `InsufficientGasForExternalCall` instead of being misclassified;
- an already-shut branch remains pinned to its branch-local `lastGoodPrice`;
- while the oracle remains unhealthy, repeated calls keep reporting failure;
- no caller can supply a rate, choose an oracle, shorten the 24-hour bound, or
  clear state directly.

Moving the external read ahead of the latch means an expired provider again
incurs one Chainlink read per fetch. That work is transaction-bounded, contains
no loop or retry, catches ordinary dependency reverts, and is necessary for
automatic recovery. This is a deliberate low residual gas/availability cost,
not an unbounded-work path.

## Adversarial review

**Attacker model:** an unprivileged account or contract that can permissionlessly
call the provider or a price feed. The attacker cannot change the immutable
Chainlink aggregator or manufacture a response that passes `_isFresh()`.

| Attempt | Result |
| --- | --- |
| Call repeatedly while the oracle remains stale or reverts | Expiry remains latched and branches continue to receive failure; no state reset |
| Publish or replay a merely decodable stale round | `_isFresh()` rejects it; the new stale regression test confirms no reset |
| Call immediately after a genuine fresh oracle round | Provider recovery is allowed by design; the fresh rate and timestamp become the new cache |
| Recover, then cause another outage | A new episode starts and expires after the unchanged bound |
| Use provider recovery to reactivate a shut branch | Fails; branch-local `priceSource == lastGoodPrice` remains terminal |

No concrete fund-loss, privilege-escalation, price-injection, or safety-bound
bypass scenario was found.

## Test coverage

| Gate | Result |
| --- | --- |
| Provider suite | 12 passed / 0 failed |
| Composite `DFPriceFeed` suite | 43 passed / 0 failed |
| Shared shutdown-latch suite | 3 passed / 0 failed |
| Proxy integration suite | 10 passed / 0 failed |
| Standard Foundry PR gate | 1,543 passed / 0 failed / 0 skipped, 81 suites |
| Production contract-size gate | Passed; provider runtime 1,741 bytes |
| Format check | Passed; pre-existing lint warnings only |
| Snapshot reconstruction | Passed; one overlay, zero drift/missing/undecided/stale identities |
| Patch-hash verification | Passed; 21 closed plus one preliminary patch |
| Maintainer checkout reconstruction | Passed from local source origin; pinned submodules initialized and one overlay applied |

Before the production change, the new fresh-recovery and later-outage
expectations failed against the report source identity. After the change, every
modified state transition has positive and negative coverage. No test gap was
identified for the functional diff.

## Blast radius

`fetchJpyUsdRate()` has one direct production caller,
`JpyFreezeLib.convertUsdPriceToJpyWithFreeze()`. That helper fans out to six
compiled feed implementations. The Day-1 manifest activates two of them:
`DFWstETHPriceFeed` and `DFUSDCPriceFeed`; the other candidate feeds are archived
or inert. Because one provider is shared across active branches, operational
blast radius is high even though the direct call graph is small.

The cross-branch test demonstrates the intended asymmetric end state: a branch
that already observed expiry stays pinned, while a branch still on `primary`
uses the recovered live rate. The JP source-of-truth specification and incident
policy now make this explicit.

## Historical context

The removed early-return latch was introduced in source commit `4f44b813`
(`fix(oracle): coordinate JPY freeze state across branches`, 2026-08-04). Its
purpose was to prevent a failure signal from being consumed or different
branches from seeing different states during one unhealthy episode. M-01 showed
that placing it before the oracle read accidentally made that episode permanent.

The remediation preserves the original coordination purpose by moving the
latch after the fresh-response branch, rather than deleting it. No prior CVE,
authorization fix, or fund-safety guard is reintroduced or removed.

## Recommendations

### Blocking

None.

### Before production

- Monitor `JpyRateUnfrozen` together with every active branch's shutdown and
  `priceSource`; provider recovery alone is not full protocol recovery.
- Retain the 24-hour outage, fresh recovery, and later re-expiry scenarios in
  deployment smoke evidence.

### Follow-up

Handle M-02 and each Low finding in separate PRs so their acceptance decisions,
patch hashes, and regression evidence remain independently reviewable.

## Methodology and limitations

**Strategy:** Surgical, risk-first differential review of a shared oracle state
transition in a large Solidity snapshot.

All changed files were inspected; the modified function, its direct library
caller, active feed consumers, branch-local shutdown state, git history, and
new tests received deep review. Adversarial cases covered permissionless calls,
stale/reverting/fresh dependency behavior, repeated outages, and cross-branch
state divergence.

The review did not rerun a live Ethereum mainnet fork because M-01 is a local
provider state-machine defect and its boundary is fully represented by the
Chainlink mock. External Chainlink implementation code and unrelated contracts
were not re-audited. Confidence is high for the M-01 diff and medium for the
repository outside that scope.
