# Info 05 — `setBufferConfig` Does Not Check Consistency Between `bufferFloor` And `bufferTargetBps`

| Item | Value |
| --- | --- |
| Reported severity | Informational |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | observation accepted; consistency checks rejected |
| Candidate implementation | [jpydf-v2#1414](https://github.com/deltaforesight/jpydf-v2/pull/1414) (closed without merge; branch preserved as candidate patch) |

PR jpydf-v2#1414 confirms that percentage target and absolute floor are
independent controls: 0% plus a nonzero floor is a valid fixed-reserve policy,
and lowering the floor automatically resumes allocation. The proposed
`1_000_000e18` cap is invalid across 6/8/18-decimal Underlyings. It keeps
production code unchanged and records the real high-floor efficiency/overflow
risks.

## Candidate-patch review (2026-08-04)

Verdict: **approve**.

- Production code untouched; the fixed-reserve policy is exercised on a real
  `CollateralVault` proxy with an 8-decimal Underlying, asserting exact buffer
  retention, strategy principal, the full `Allocated` event payload, and
  automatic resumption after the floor is lowered — no migration involved.
- The overflow claim (`type(uint256).max` floor plus pending withdrawals) was
  verified against the actual `_requiredBuffer` arithmetic, and the high-floor
  risks are recorded as the disposition states.
- Focused test and full 121-test suite pass. Nit: the 6- and 18-decimal cases
  of the cap-invalidity argument are dimensional analysis in the review
  document only; the 8-decimal test demonstrates the denomination.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved (as-is) |
| Approved diff | jpydf-v2 `4df6d902..fff9251a` ([#1414](https://github.com/deltaforesight/jpydf-v2/pull/1414)) |
| Diff SHA-256 | `0abff154368180a486bc5a88052a2c36fe09c4e9b5304c9452fbffa221238138` |
| Diff size | 2 files changed, 157 insertions(+) |
| Test evidence | Focused test plus CollateralVaultStrategyTest 121/121. |
| Approved patch | [`patches/info-05.patch`](../patches/info-05.patch) |

Basis: the candidate-patch review above. The candidate branch diff is
adopted as the approved diff and lands in jpydf-v2 via the audit sync PR.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#64](https://github.com/deltaforesight/jpydf-audit/pull/64): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/info-05.patch`](../patches/info-05.patch).
