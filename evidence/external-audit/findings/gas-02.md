# Gas 02 — `getNewApproxAvgInterestRateFromTroveChange` Runs The `upfrontFee` Assert Even When Shut Down

| Item | Value |
| --- | --- |
| Reported severity | Gas |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | optimization rejected; regression evidence added |
| Candidate implementation | [jpydf-v2#1409](https://github.com/deltaforesight/jpydf-v2/pull/1409) (closed without merge; branch preserved as candidate patch) |

PR jpydf-v2#1409 reproduces the optimization against the actual `ActivePool`,
where the shutdown-path saving is 27 gas rather than the mock's 149 gas.
Reordering also changes the documented shutdown + nonzero `upfrontFee` result
from Panic 0x01 to a successful zero return. It keeps production code and Core
parity unchanged and pins both valid and malformed shutdown behavior.

## Candidate-patch review (2026-08-04)

Verdict: **approve**.

- The 27-gas delta and the Panic-0x01→zero-return behavioral flip were both
  independently reproduced by applying the audit's proposed reorder to
  `ActivePool` and re-running (baseline 1,466 gas → 1,439 gas; the malformed-
  shutdown test then fails as documented). The reorder was reverted after the
  A/B; the committed tree keeps production code unchanged.
- The committed tests run against the real `ActivePool` from the deployment
  harness (not a mock), use the exact `Panic(uint256) 0x01` expectation, and
  assert the shutdown precondition — non-vacuous on both the valid and
  malformed paths. Focused run: 2/2 pass.
- Note: the A/B itself is doc-recorded methodology rather than committed
  executable evidence — inherent, since committing the reorder is the thing
  being rejected.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved (as-is) |
| Approved diff | jpydf-v2 `4df6d902..5d455b0c` ([#1409](https://github.com/deltaforesight/jpydf-v2/pull/1409)) |
| Diff SHA-256 | `3f3e298b09fe63a6cad6e0ff4aff7bddd7c8ec5babedf73c7388b56dbfd865cf` |
| Diff size | 2 files changed, 185 insertions(+) |
| Test evidence | Focused tests 2/2; the 27-gas delta and the Panic-0x01-to-zero-return flip were independently reproduced via A/B. |
| Approved patch | [`patches/gas-02.patch`](../patches/gas-02.patch) |

Basis: the candidate-patch review above. The candidate branch diff is
adopted as the approved diff and lands in jpydf-v2 via the audit sync PR.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#69](https://github.com/deltaforesight/jpydf-audit/pull/69): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/gas-02.patch`](../patches/gas-02.patch).
