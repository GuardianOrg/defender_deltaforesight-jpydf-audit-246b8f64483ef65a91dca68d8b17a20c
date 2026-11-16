# Info 07 — Strategy Contracts Store External Protocol Addresses Without Update Functions

| Item | Value |
| --- | --- |
| Reported severity | Informational |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | observation accepted; blanket setters rejected |
| Candidate implementation | [jpydf-v2#1416](https://github.com/deltaforesight/jpydf-v2/pull/1416) (closed without merge; branch preserved as candidate patch) |

PR jpydf-v2#1416 confirms that venue addresses are intentionally fixed per
Strategy instance, while hard replacement uses a fresh proxy alongside the
disabled old Strategy rather than requiring an old-proxy upgrade. A two-venue
ERC-4626 replay drains, removes, and replaces the old Strategy with its
implementation slot unchanged and full backing preserved; generic setters
would not migrate venue-bound shares, allowances, or async request state.

## Candidate-patch review (2026-08-04)

Verdict: **approve with nits**.

- The replay's claims are all asserted, not narrated: emergency drain to zero
  principal and venue balance, removal (strategy count/order), fresh-proxy
  replacement funded to full principal, ERC-1967 implementation slot compared
  before/after via `vm.load`, and `totalUnderlying`/`backingRatio` proving
  full backing. `removeStrategy`'s on-chain zero-principal/zero-asset gates
  were verified in production source.
- Full 23-test `ERC4626StrategyTest` suite passes.
- Nits: (1) no `assertNotEq(implSlotBefore, 0)` guard — a wrong slot constant
  would let the unchanged-slot assertion pass vacuously as `0 == 0`; one-line
  hardening suggested on the PR branch. (2) The review document's "real
  ERC-4626 venues" are OZ mocks — fine for a unit replay, wording slightly
  strong. (3) Async-venue coexistence is argued, not replayed; the disposition
  does not overclaim it.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved with required amendment |
| Approved diff | jpydf-v2 `4df6d902..d0402e1a` ([#1416](https://github.com/deltaforesight/jpydf-v2/pull/1416)) |
| Diff SHA-256 | `fcb11765ba4e744d7990e4e667578f9d7a58474db3559e854765eb7184f0640c` |
| Diff size | 4 files changed, 203 insertions(+), 2 deletions(-) |
| Test evidence | ERC4626StrategyTest 23/23. |
| Approved patch | [`patches/info-07.patch`](../patches/info-07.patch) |

Basis: the candidate-patch review above. The candidate branch diff is
adopted as the approved diff and lands in jpydf-v2 via the audit sync PR.

Required amendment, carried into the audit sync PR: add `assertNotEq(oldImplementationBefore, bytes32(0))` before the unchanged-slot assertion so a wrong slot constant cannot pass vacuously as `0 == 0`.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#66](https://github.com/deltaforesight/jpydf-audit/pull/66): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/info-07.patch`](../patches/info-07.patch).

Includes the audit-required `assertNotEq` slot-guard amendment.
