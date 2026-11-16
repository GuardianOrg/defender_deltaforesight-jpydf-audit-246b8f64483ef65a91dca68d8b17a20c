# Info 08 — `lastDepositBlock` Comment Overstates Guard Guarantee

| Item | Value |
| --- | --- |
| Reported severity | Informational |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | Informational accepted; wording corrected |
| Candidate implementation | [jpydf-v2#1408](https://github.com/deltaforesight/jpydf-v2/pull/1408) (closed without merge; branch preserved as candidate patch) |

PR jpydf-v2#1408 aligns the Solidity comment and JP/EN core spec with the
actual guarantee: the deposit persists across a block boundary, but an
intervening `offset()` or a full block of liquidation exposure is not
guaranteed. The guard logic remains unchanged; focused same-block/next-block
tests and metadata-stripped runtime bytecode comparison confirm no executable
change.

## Candidate-patch review (2026-08-04)

Verdict: **approve**.

- The `contracts/src` diff is exactly three comment lines; the
  `lastDepositBlock < block.number` guard condition is untouched.
- No-executable-change was independently confirmed: patched and baseline
  `DFStabilityPool` runtime bytecode hash identically after stripping the
  CBOR metadata trailer.
- JP and EN spec edits are semantically synchronized, and a grep for leftover
  overstated wording ("one block of pool risk" variants) outside historical
  reviews returns no hits. The same-block revert and next-block success tests
  both pass.
- Nit: the review document publishes a specific bytecode hash without the
  exact stripping command, so the printed value is not reproducible as-is;
  the equality claim is what matters and holds under an independent method.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved (as-is) |
| Approved diff | jpydf-v2 `4df6d902..49808c45` ([#1408](https://github.com/deltaforesight/jpydf-v2/pull/1408)) |
| Diff SHA-256 | `c326b841e2fc20cc69ddd7292df755744cc6177d493c8f4293895643c6316082` |
| Diff size | 4 files changed, 140 insertions(+), 9 deletions(-) |
| Test evidence | Same-block/next-block tests 2/2; metadata-stripped runtime bytecode identical to baseline. |
| Approved patch | [`patches/info-08.patch`](../patches/info-08.patch) |

Basis: the candidate-patch review above. The candidate branch diff is
adopted as the approved diff and lands in jpydf-v2 via the audit sync PR.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#67](https://github.com/deltaforesight/jpydf-audit/pull/67): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/info-08.patch`](../patches/info-08.patch).
