# L-02 Differential Security Review

## Executive summary

| Severity | New findings |
| --- | ---: |
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |

**Overall residual risk:** Low.

**Recommendation:** Approve the source-level constructor guard. Record that the
current `PriceFeedProxy` already blocks the report's production zero-price path.

The change rejects active feed deployments that did not establish a primary,
nonzero last-good price. It adds no storage, runtime selector, authority, value
flow, or live-price behavior. Two inherited formatter drifts in the changed
source files are corrected without semantic effect.

## Review scope

**Source baseline:** `fe3d3d0e182b8189202dee3a3db8103bd0df1de7` plus the
ordered M-01, M-02, and L-01 overlays.

**Audit-repository baseline:** `49637b0c8ae24c2c069024c08105b5bbee96c3aa`

**Review date:** 2026-08-12

| Area | Change | Risk |
| --- | --- | --- |
| Standard active-feed base constructor | Rejects non-primary or zero initial state | Medium |
| dwstETH active-feed constructor | Applies the same invariant | Medium |
| Shared shutdown regression | Models expiry before registration and later recovery | Medium |
| JP/EN Oracle spec and verification ledger | Adds append-only ORCL-INV-012 and exact evidence | Low |
| Snapshot reconstruction | Adds the fourth ordered preliminary overlay | Medium |

## Root-cause and topology analysis

The source constructor runs before it can be registered as the branch price
feed. On shared-JPY expiry, the source-level shutdown call therefore fails the
BorrowerOperations caller check and is intentionally caught so the registered
Proxy can normally perform shutdown. In a constructor there is no Proxy caller,
so the catch leaves `priceSource` at its enum default, `primary`, while
`lastGoodPrice` remains zero. The former assertion checked only the enum and
missed the actual safety invariant.

However, the configured production consumer is `PriceFeedProxy`, not the source
directly. Its constructor rejects invalid `source.lastGoodPrice()` including
zero before wiring the source, and smoke-tests normal and redemption fetches.
Its source-switch path likewise validates the candidate. The report's chain from
bad standalone source deployment to a configured branch serving healthy zero is
therefore interrupted by existing defenses.

The new source guard is still valuable: each deployable artifact is valid on its
own boundary, operator tooling fails at the earliest component, and safety no
longer depends solely on a downstream integration guard.

## Changed-state analysis

Both active constructors call their existing initial fetch, then evaluate:

```text
priceSource == primary && lastGoodPrice != 0
```

Any failure reverts construction atomically. If that first fetch newly mutated
the shared provider in the same transaction, the provider mutation also rolls
back; if the provider was already expired, its prior state remains. No partially
deployed source or partial local state survives.

On a healthy response, the existing fetch has already applied collateral price,
JPY conversion, and backing ratio. A measured zero backing is floored to one in
the existing library, so valid catastrophic impairment remains representable as
a nonzero near-zero price and is not confused with uninitialized state.

## Safety and liveness properties

- no active source deploys with `lastGoodPrice == 0`;
- the enum default alone cannot satisfy constructor validity;
- both Day-1 source families enforce identical initialization semantics;
- normal runtime fetch and shutdown branches are unchanged;
- a fresh JPY response after expiry clears the provider episode and deployment
  automatically succeeds;
- the guard introduces no governance action or permanent latch;
- Proxy constructor and source-switch validation remain independent downstream
  defenses;
- no new external call, callback, loop, or unbounded work is added.

## Adversarial review

| Attempt | Result |
| --- | --- |
| Deploy Standard feed during expired JPY episode | `InvalidInitialPrice` |
| Deploy dwstETH feed during expired JPY episode | `InvalidInitialPrice` |
| Rely on caught `CallerNotPriceFeed` to keep enum at primary | Zero cache independently fails the constructor |
| Recover JPY/USD with a fresh moved round and retry | Provider clears expiry; deployment succeeds with nonzero price |
| Return measured zero backing | Existing one-wei floor remains valid and passes nonzero initialization |
| Trigger collateral/canonical/backing failure at construction | Non-primary state or zero cache rejects deployment |
| Register a pre-fix zero source behind PriceFeedProxy | Existing Proxy `lastGoodPrice` validation rejects it |

## Tests and negative evidence

| Gate | Result |
| --- | --- |
| Five active-feed/deploy focused suites | 129 passed / 0 failed |
| Standard Foundry PR gate | 1,549 passed / 0 failed / 0 skipped, 81 suites |
| Production contract-size gate | Passed; DFUSDC 3,095 bytes and DFWstETH 3,492 bytes runtime |
| Format / source diff check | Passed |
| Pre-fix mutation | Standard source unexpectedly deployed; expected-revert regression failed |
| Post-fix rejection | Standard and dwstETH both reverted with their exact custom error |
| Recovery liveness | Fresh JPY round cleared expiry and deployed a nonzero primary source |
| Overlay reconstruction | Applied after M-01/M-02/L-01 with zero snapshot drift |

## Blast radius

The new custom errors exist in constructor bytecode and ABI metadata but add no
callable selector. Runtime behavior and storage layout are unchanged. The
constructor checks add negligible initcode and active runtime sizes remain far
below EIP-170.

Standard implementations inherit the base guard. The dwstETH composite has its
own copy because it inherits `CompositePriceFeed`. Frontend bindings do not need
regeneration: users never call these constructor-only errors through the app.

## Residual risk and limitations

Deployment scripts must still verify canonical addresses, provider equality,
freshness parameters, and Proxy wiring. This patch proves only that active
source constructors cannot finish with an uninitialized price; it does not make
an unhealthy oracle safe to activate.

Archived composite candidate feeds were not changed. Their reactivation would
expand production scope and requires an activation package and renewed audit.
No live mainnet fork was required to reproduce the deterministic constructor
state machine; current mainnet address and heartbeat evidence remains a separate
deployment gate.
