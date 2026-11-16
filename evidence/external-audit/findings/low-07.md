# Low 07 — `SCALE_SPAN = 2` Permanently Loses Depositor Gains After 3+ Scale Changes

| Item | Value |
| --- | --- |
| Reported severity | Low |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | Low rejected; downgraded to Informational |
| Candidate implementation | [jpydf-v2#1407](https://github.com/deltaforesight/jpydf-v2/pull/1407) (closed without merge; branch preserved as candidate patch) |

The cutoff is mechanically real, but PR jpydf-v2#1407 measures the omitted tail
against the actual `DFStabilityPool`: an extreme four-scale replay loses only
12,500 wei of collateral and 125 wei of yield, while realistic amounts round
both paths to zero. It keeps the upstream/spec `SCALE_SPAN = 2`, makes no
production-code change, and adds regression evidence for the dust bound.

## Candidate-patch review (2026-08-04)

Verdict: **approve**.

- The evidence test runs against the real deployed `DFStabilityPool` and
  reproduced both tail figures (12,500 wei coll / 125 wei yield extreme; 0/0
  realistic) in a fresh run; `SCALE_SPAN = 2` is unchanged in production
  source.
- Fault injection independently confirmed sensitivity: setting
  `SCALE_SPAN = 3` makes the extreme-tail test fail exactly as the review
  document claims, so the test is genuinely coupled to the truncation.
- Setup cannot silently under-shoot: each round asserts a scale increase and
  the final scale is asserted `>= 4`.
- Nit (non-blocking): the exact tail values are console-logged; the asserts
  pin "nonzero and < 1e-20 relative", which is the defensible, non-brittle
  form.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved (as-is) |
| Approved diff | jpydf-v2 `4df6d902..07b8baac` ([#1407](https://github.com/deltaforesight/jpydf-v2/pull/1407)) |
| Diff SHA-256 | `b2eb5d78a2e5fd28934e4b8cbc0a67e8da98c2c009c20e4436209c94fb2badef` |
| Diff size | 2 files changed, 285 insertions(+) |
| Test evidence | Focused suite 2/2; SCALE_SPAN=3 fault injection flips the test to failure as documented. |
| Approved patch | [`patches/low-07.patch`](../patches/low-07.patch) |

Basis: the candidate-patch review above. The candidate branch diff is
adopted as the approved diff and lands in jpydf-v2 via the audit sync PR.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#59](https://github.com/deltaforesight/jpydf-audit/pull/59): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/low-07.patch`](../patches/low-07.patch).
