# Pre-audit multi-skill review — 2026-08-08

## Status and identity

This is pre-audit hardening evidence. The new external audit has **not**
started. The review run preceded publication; its exact final source freeze was
later merged by jpydf-v2 PR #1491 as merge commit `469b1265`.

| Item | Identity |
| --- | --- |
| Initial four-fix implementation | `e2cb17a1e70ab139d00141e44a42061ac729e896` |
| Read-only skill review target | `dc71cfb601ea749c4fa8f00a368e5032720b2557` |
| Follow-up remediation implementation | `825e96749be34e95bbccc32e6b197978cff5e3b8` |
| Final source freeze | `0a85b374015e2553d2985b4a3f454b6aee4514a5` |

The Japanese remediation record is copied through the source snapshot's
documentation mapping. The frozen production source and tests are under
[`source-snapshot/contracts/`](../../source-snapshot/contracts/).

## Review procedures

| Review | Exact skill revision | Procedure and limitation |
| --- | --- | --- |
| Trail of Bits | `7b9bd5f950f89a9ba71b249b9801c1a95be3928e` | Full `spec-to-code-compliance` and `variant-analysis` procedures. Independent requirement checker completed for valuation availability and bounded retry at confidence 0.97. The other two requirements were traced and tested, but did not receive a fresh independent checker because of the concurrency limit. |
| QuillShield | `8bdd3c058704cd855ce29b8e2385708b59152606` | Full `external-call-safety`, `semantic-guard-analysis`, and `state-invariant-detection` procedures. Read-only review at `dc71cfb6`. |
| Nemesis Auditor | `75cecc6dbd798f82ed8928d1a906078be9c575de` | The independent child path was blocked twice by the platform safety filter. It is not claimed as an independent review. The parent applied the skill's attacker recon, asset/state coupling, complex-path, and failure/recovery workflow and retained this limitation. |

## Original four decisions

| Requirement | Result at `dc71cfb6` | Final status |
| --- | --- | --- |
| Valuation unavailable is distinct from measured zero on pricing | Implemented; no pricing consumer bypass found | Frozen unchanged |
| Morpho `_doWithdraw` full request plus seven bounded halving probes | Implemented; first success returned, all failures return zero | Frozen unchanged |
| `forceDeallocate` must pass Vault `WRITEOFF_ROLE` incident rails | Implemented; Vault-only wrapper, atomic pauses, penalty cap, cache handling, and post-backing floor | Frozen unchanged |
| `_minUnderlyingReceived` means immediate Underlying only | Implemented for queue/dust separation | Semantics retained; receiver-delta accounting strengthened below |

Trail of Bits verified no Critical, High, or Medium finding in these four
requirements. It confirmed one Low comment drift in the Morpho recovery map.

## Verified follow-up findings and disposition

| ID | Review severity | Finding | Final disposition and regression |
| --- | --- | --- | --- |
| Q-01 | Medium | Vault redeem returned the nominal transfer amount. A fee-on-transfer Underlying could increase the receiver by less than `_minUnderlyingReceived` while the Zapper accepted the nominal value. | `CollateralVault.redeem` now returns the receiver's measured balance delta. `test_Redeem_FeeOnTransferReturnsReceiverBalanceDelta` and `test_WithdrawCollToUnderlyingWithMin_UsesFeeTokenReceiverDelta` prove the return and atomic rollback. |
| Q-02 | Medium | A Strategy principal return with a transfer fee reduced upstream position by more than the Vault receipt. Reducing the fresh cache only by receipt could overstate backing during a simultaneous live-valuation outage. | Exact declared/received delivery reduces cache by receipt; any mismatch invalidates the cache. Live valuation remains immediately usable, outage fails closed, and live recovery restores availability. `test_FeeOnTransferToken_InvalidatesCacheBeforeValuationOutage` covers the sequence. |
| Q-03 / TOB-L01 | Low | `MorphoV2Strategy`'s top recovery map still described owner `forceDeallocate` and incompletely described retry. | NatSpec now names `WRITEOFF_ROLE` through `CollateralVault.forceDeallocateMorphoV2` and the bounded retry. No executable guard changed. |
| N-01 | Variant | Sky `previewUsdsToUsdc` converted halt / invalid `tout` into numeric zero. With a tracked nonzero position, pricing could treat quote failure as measured total loss. | Halt and invalid fee now revert. A fresh Vault cache may bridge the outage; stale cache reports pricing unavailable; route recovery restores live valuation. Covered by `test_PreviewAndConversionFailClosedWhenBuyRouteHaltedOrFeeInvalid` and `test_PricingUsesFreshCacheWhenSkyQuoteUnavailable`. Normal sub-USDC-atom rounding on a valid route may still return zero. |

QuillShield's read-only result at `dc71cfb6` was C0/H0/M2/L1. Trail of Bits was
C0/H0/M0/L1. The table above records the remediation applied after those
reports; the original findings are not being relabeled as if the review had
examined the later code.

## Chain Defenders report reconciliation

The original 43-page report is preserved at
[`evidence/external-audit/jpydf-aug-2026.pdf`](../external-audit/jpydf-aug-2026.pdf),
SHA-256
`a488541d3204c149adc9d0d7b80f4fa340f71a80f42d5e357899b74112e1b18a`.
It contains 1 High, 3 Medium, 7 Low, 8 Informational, and 2 Gas findings for an
older source identity.

- Its High 01 is the historical Sky refund defect and is not the later
  valuation-unavailable pricing defect.
- Its Gas 01 valuation-loop concern maps to the current 32-Strategy cold and
  10-branch/two-pass quantitative regression guards.
- The PDF is prior external-review evidence, not proof that the new formal audit
  has started.

## Final verification

| Gate | Result |
| --- | --- |
| Follow-up affected suites | 253 passed / 0 failed / 0 skipped: Vault 57, VaultStrategy 124, Zapper 45, Sky Strategy 16, Sky Converter 11 |
| Fast Foundry PR gate | 1,536 passed / 0 failed / 0 skipped, 81 suites |
| Full local Foundry gate | 1,589 passed / 0 failed / 0 skipped, 89 suites |
| Production `CollateralVault` runtime | 23,047 / 24,576 bytes; 1,529-byte margin |
| Full-review body | 5,219 nSLOC |
| Full `contracts/src` | 13,266 nSLOC: active 12,054 + archive 1,212 |
| cloc evidence | [`contracts-src-cloc-0a85b374.csv`](./contracts-src-cloc-0a85b374.csv), normalized body SHA-256 `22346dad9249af91af7639ab26da8db4f6031f6f2f45c2578b043f7f698cf49b` |

`forge build --sizes` compiles successfully but exits nonzero when test-only
`BorrowerOperationsTester` / `TroveManagerTester` are included because those
fixtures exceed EIP-170. The production Vault is below the limit as recorded
above.
