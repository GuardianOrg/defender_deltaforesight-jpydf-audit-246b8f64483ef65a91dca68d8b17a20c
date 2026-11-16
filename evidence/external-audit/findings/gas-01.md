# Gas 01 — Gas Exhaustion In Strategy Valuation Loop Can Revert All Redemptions

| Item | Value |
| --- | --- |
| Reported severity | Gas |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | gas growth accepted; global redemption DoS not demonstrated |
| Candidate implementation | [jpydf-v2#1417](https://github.com/deltaforesight/jpydf-v2/pull/1417) (closed without merge; branch preserved as candidate patch) |

PR jpydf-v2#1417 measures a real `CollateralVault` with 32 independent Sky
Strategy graphs at 1,332,387 gas cold and 261,884 gas warm. The current
eight-branch and protocol-maximum ten-branch two-pass valuation-only
extrapolations are 12,754,168 and 15,942,710 gas. It keeps
`MAX_STRATEGIES = 32`, rejects a stale within-block cache, leaves production
code unchanged, and adds quantitative regression and future-activation gates
without claiming a full-redemption gas bound. The venues behind the 32
Strategies are test fixtures (plain ERC-4626 vault, trivial converter), so
mainnet sUSDS/PSM cold accesses will cost more; fork replay is prescribed
before activation.

## Candidate-patch review (2026-08-04)

Verdict: **approve with nits**.

- Every disposition figure was reproduced by an actual test run, and the
  extrapolation arithmetic checks out ((cold + warm) × branch count). The
  two-pass premise is real in `CollateralRegistry` source.
- The 32-strategy fixture uses real `CollateralVault`/`DToken`/Strategy
  contracts behind real proxies with verified nonzero live positions; the
  cold measurement is correctly ordered first in the test transaction.
- The regression gate is enforced in code (`assertLt` ceilings of 2,000,000
  per-branch cold and 20,000,000 ten-branch two-pass); the future-activation
  gate is spec/process text.
- Nits: the mocked-venue optimism is now disclosed in this disposition (fork
  replay required before activation); exact gas figures hardcoded in the
  EN/JP spec prose will go stale under compiler drift, though the enforced
  ceilings remain the actual gate.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved (as-is) |
| Approved diff | jpydf-v2 `4df6d902..3f9aef8d` ([#1417](https://github.com/deltaforesight/jpydf-v2/pull/1417)) |
| Diff SHA-256 | `6cf2b979b4b3edfc41bda0b44ca9c9abe21d3f51167536a9f32ebf92f40fe76c` |
| Diff size | 4 files changed, 373 insertions(+), 4 deletions(-) |
| Test evidence | Focused test 1/1; every disposition gas figure reproduced; assertLt ceilings enforced in code. |
| Approved patch | [`patches/gas-01.patch`](../patches/gas-01.patch) |

Basis: the candidate-patch review above. The candidate branch diff is
adopted as the approved diff and lands in jpydf-v2 via the audit sync PR.

Closure condition retained from the disposition: a mainnet-fork replay of the valuation loop is required before any additional branch activation, because the measured venues are test fixtures.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#68](https://github.com/deltaforesight/jpydf-audit/pull/68): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/gas-01.patch`](../patches/gas-01.patch).

Deferred doc-mirror hunks (mirror drift; see the preserved patch): `documents/en .../spec/CollateralVault.md`.

## Fix-quality review addendum (2026-08-05)

Operational condition reviewed: the activation gate (same max-size replay +
target-chain block-gas estimate before any new Strategy type or 9th+ branch)
is applied in the JP spec's valuation-gas regression-boundary section, and
the fork-replay requirement is recorded in the audit decision above.
