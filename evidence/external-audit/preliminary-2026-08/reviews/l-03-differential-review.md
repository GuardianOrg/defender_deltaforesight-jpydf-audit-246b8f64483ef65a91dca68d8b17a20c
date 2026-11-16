# L-03 Differential Security Review

## Executive summary

| Severity | New findings |
| --- | ---: |
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |

**Recommendation:** Reject the report's timestamp-refresh change. Approve the
resolution test and specification clarification.

A follow-up independent review found that the first revision overstated the
incident writeoff path as an availability recovery mechanism. The corrected
specification and regression below distinguish accounting-loss finalization
from pricing-availability recovery; no production Solidity change is required.

## Root-cause review

The report conflates two facts:

- an exact receipt proves a known amount moved into the Vault; and
- a full live valuation proves the value of the Strategy position that remains.

Only the second fact can safely renew a last-good valuation TTL. The cache is a
bounded exception path for transient read failure, not a rolling principal
ledger whose age should follow every transfer.

## Adversarial state analysis

Assume a cache of 100 was last fully observed at T0. The Strategy later suffers
an unobservable loss, valuation views fail, and only 1 can be recovered. The
receipt safely changes the upper fallback value to 99. It does not prove that 99
still exists. Updating the timestamp at receipt time would grant the residual a
new full TTL. Repeating dust-sized recoveries could prevent expiry indefinitely.

Keeping T0 instead gives the intended bounded behavior: known receipts reduce
double counting, while uncertainty about the residual still expires on the
original deadline.

## Call-path review

`_reduceStrategyValuationCache` is used by exact `receiveFromStrategy`
receipts and as a fallback after incident writeoff / Morpho force-deallocation
when a full refresh fails. In each case the reduction is conservative, but none
of these fallback reductions establishes a full current valuation of all
remaining assets. A universal timestamp refresh would therefore widen the risk
beyond the report's repeated `sendToVault` example.

Declared/received mismatch continues to invalidate the cache. A successful
full `_refreshStrategyValuation` continues to write both value and timestamp.
No authority, storage, event, value-flow, or runtime production behavior is
changed by this resolution PR.

## Safety and liveness properties

- partial recovery cannot launder a stale residual value into a fresh cache;
- exact receipts still reduce double counting immediately;
- stale or unavailable residual valuation fails closed for pricing;
- recovery of both live valuation reads restores availability immediately and
  permits anyone to repopulate the cache;
- confirmed loss can be finalized through the bounded incident writeoff path,
  but writeoff alone does not make an unreadable valuation available;
- no permanent circuit or governance-only recovery latch is introduced.

## Test and mutation evidence

| Gate | Result |
| --- | --- |
| New boundary regression | Passed on unchanged production behavior |
| Stale-cache full-writeoff boundary | Passed: accounting loss finalized while pricing remained unavailable |
| Report recommendation mutation | Failed: timestamp advanced from `1` to `86400` |
| CollateralVaultStrategy focused suite | 126 passed / 0 failed / 0 skipped |
| Standard Foundry PR gate | 1,551 passed / 0 failed / 0 skipped, 81 suites |
| Format / source diff check | Passed |
| Production source diff | Empty |

## Residual risk

During a prolonged valuation outage, the branch can enter the oracle failure
path after the configured TTL even while funds are being recovered. This is an
intentional safety tradeoff: recovery activity alone cannot establish the value
of what remains. Operators should continue recovery, restore the Strategy view
when possible, and use permissionless refresh to repopulate the cache. Confirmed
loss follows the incident writeoff procedure, but even a full writeoff does not
restore pricing availability while valuation reads remain unavailable.
Monitoring the cache age and valuation availability remains a production
requirement.
