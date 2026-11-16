# M-02 Differential Security Review

## Executive summary

| Severity | New findings |
| --- | ---: |
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |

**Overall residual risk:** Low for the remediation diff; Medium operational risk
until the Sky activation package proves the real halt/recovery and monitoring
paths.

**Recommendation:** Approve M-02 remediation. Keep Sky outside the active
Strategy manifest until its existing activation gates are complete.

The change prevents an explicit Sky reverse-route halt from expiring into
terminal dUSDC branch shutdown, while preserving fail-closed behavior for
invalid fees and unknown quote failures. All production and test changes were
reviewed. No authorization, storage-layout, upgrade, token-transfer, or
conversion-execution guard was weakened.

## Review scope

**Source baseline:** `fe3d3d0e182b8189202dee3a3db8103bd0df1de7` plus the
ordered M-01 overlay.

**Audit-repository baseline:** `05c11c0264dbb609a1dd7ea1931757fa87526ffd`

**Review date:** 2026-08-12

| Area | Change | Risk |
| --- | --- | --- |
| Converter interface / concrete adapter | Adds an explicit reverse-route halt view | Medium |
| Strategy valuation | Uses principal-capped 1:1 value only for the explicit halt sentinel | High |
| Converter / Strategy / feed integration tests | Separates halt, invalid fee, generic failure, yield, cache, and branch shutdown | Medium |
| Compatibility mocks | Implements the new view as false | Low |
| JP/EN spec, ledger, and incident runbook | Defines the narrower halt-only valuation policy | Medium |
| Snapshot reconstruction and evidence | Adds the second ordered, hash-pinned preliminary overlay | Medium |

## Changed-state analysis

The nonzero valuation path now performs these steps:

1. value only owned sUSDS shares plus tracked idle USDS;
2. floor that USDS position to six-decimal 1:1 USDC;
3. read `isUsdsToUsdcRouteHalted()`;
4. if true, return the smaller of the 1:1 amount and tracked principal;
5. otherwise call the existing `previewUsdsToUsdc()` and return the smaller of
   preview and 1:1 value.

The halt predicate is exact: `psmWrapper.tout() == type(uint256).max`. A fee
above `1e18` but below the sentinel is not a halt; the subsequent preview keeps
reverting with `InvalidFee`. A wrapper read that reverts also propagates, so an
unknown dependency fault does not receive numeric fallback treatment.

Principal capping is defense in depth. `CollateralVault` already clamps each
Strategy's contribution to principal, but applying the cap inside the Strategy
also makes `realizedYield()` return zero during a halt. This prevents callers
from treating sUSDS accrual as harvestable USDC while the reverse route is not
available.

The cap is not a market-price oracle. It assumes USDS par during the explicit
halt. If USDS depegs at the same time, book value can exceed secondary-market
exit value up to the tracked-principal ceiling. The halted LitePSM cannot supply
a trustworthy executable quote, and this patch does not add an independent
USDS/USD oracle. This disclosed residual is why Sky remains activation-gated
and the operational residual risk is Medium even though the remediation diff
has no additional blocking defect.

## Security invariants

The following properties remain intact:

- conversion and preview revert on the Sky halt sentinel;
- invalid fees do not receive a 1:1 valuation fallback;
- unknown converter and wrapper failures remain subject to bounded cache and
  pricing unavailability;
- value never exceeds either the tracked principal or 1:1 USDS-to-USDC amount
  during a halt;
- donation-resistant owned-share and idle-USDS accounting is unchanged;
- USDS/USDC decimals, max-conversion-loss, min-out, balance-delta, allowance
  reset, refund, and dust protections are unchanged;
- no permissionless caller can set the route state, principal, or valuation
  policy.

The new status read and the existing preview are two separate external views.
Sky governance cannot mutate `tout` between them within one EVM transaction.
If the route changes between transactions, each new valuation observes the
current wrapper state. The path has no loop, retry, callback, or unresolved
asynchronous work.

## Adversarial review

| Attempt | Result |
| --- | --- |
| Set `tout` to the halt sentinel and wait beyond cache expiry | Conservative principal-capped valuation remains live; the feed stays primary |
| Set an invalid non-sentinel fee | Halt view is false and preview reverts; stale cache becomes unavailable |
| Make `tout()` itself revert | Status read reverts; no catch-all 1:1 fallback |
| Donate USDS or sUSDS during halt | Existing owned-accounting excludes direct donations; halt value remains principal capped |
| Accrue sUSDS yield during halt | Position may grow, but estimated value remains capped and `realizedYield()` stays zero |
| USDS depegs while the route is halted | Valuation remains at par up to principal; depeg monitoring, allocation limits, and incident response remain required before activation |
| Front-run a valuation with route recovery | The next transaction uses live preview; no user-supplied quote or state is trusted |
| Use halt valuation to withdraw USDC | Conversion still reverts; valuation does not create liquidity or bypass min-out |

No additional blocking fund-loss, privilege-escalation, reentrancy, or
unbounded-work defect was found in the remediation diff. The explicit par-value
residual above is not eliminated by M-02 and remains part of the Sky activation
risk decision.

## Tests and negative evidence

| Gate | Result |
| --- | --- |
| Converter + Strategy focused suites | 31 passed / 0 failed |
| Gas-bound and archived compatibility suites | 4 passed / 0 failed |
| Standard Foundry PR gate | 1,547 passed / 0 failed / 0 skipped, 81 suites |
| Production contract-size gate | Passed; Strategy 20,173 bytes, converter 5,596 bytes |
| Format / source diff check | Passed |
| Pre-fix mutation | Price-feed integration regression failed as expected |
| Post-fix rerun | Same integration regression passed |
| Overlay application | Applied cleanly after M-01 and reconstructed every changed file |
| Maintainer checkout | Pinned submodules initialized; M-01 then M-02 applied successfully |

The new tests cover both safety and liveness: explicit halt cannot inflate
yield, generic failure cannot inherit halt fallback, cache expiry no longer
shuts down the branch for an explicit halt, and a recovered generic quote
automatically restores live valuation.

## Blast radius

The interface has one production implementation and four in-repository test
implementations. The Strategy valuation feeds `CollateralVault` backing, which
feeds `DFUSDCPriceFeed`, so the downstream branch impact is high once Sky is
activated. Conversion functions are not changed.

The expected Day-1 manifest uses Aave plus Morpho V2 for dUSDC; Sky is a
conditional/backlog candidate. The remediation therefore changes an auditable
activation surface but not the currently expected Day-1 allocation set.

## Historical context

Source commit `825e9674` intentionally changed halted and invalid-fee previews
from a numeric zero into reverts so an unavailable quote could not masquerade
as measured total loss. M-02 exposed a liveness consequence when explicit halt
and every other quote fault shared the same Vault-cache path.

This remediation preserves that security correction for invalid and unknown
states. It adds a separate, exact halt predicate instead of reverting to numeric
zero or catching every preview failure.

## Recommendations

### Blocking

None for this remediation PR.

### Before Sky activation

- Run a mainnet-fork drill against the canonical wrapper covering active →
  halted → active status, cache expiry, price-feed state, and recovery.
- Alert on the explicit route-halt state, idle USDS, failed status reads,
  Strategy valuation cache age, USDS depeg, and any price-feed source transition.
- Freeze an allocation limit and explicitly accept or replace the USDS-par
  assumption used during an explicit halt.
- Keep the existing activation requirement for converter identity, min-out,
  partnership, and operational evidence.

## Methodology and limitations

This was a surgical, security-focused differential review of the second
preliminary finding. The production diff, interface implementations, direct and
downstream callers, source history, activation policy, specifications, and tests
were inspected. Adversarial analysis covered sentinel collision, invalid fees,
dependency reverts, donations, yield accrual, route-state timing, cache expiry,
and price-feed shutdown.

The review did not execute a live Ethereum mainnet fork because no credentialed
RPC was needed to reproduce the code-level defect and Sky is not in the expected
Day-1 Strategy set. External Sky contracts and unrelated JPYdf surfaces were not
re-audited. Confidence is high for the M-02 diff and medium for future Sky
activation until the real-wrapper drill is recorded.
