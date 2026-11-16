# High 01 — PSM Fee (`tout > 0`) Bricks All `SkyUsdcSUsdsStrategy` Withdrawal Paths

| Item | Value |
| --- | --- |
| Reported severity | High |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | historically valid, resolved on current `develop` |
| Candidate implementation | [jpydf-v2#1052](https://github.com/deltaforesight/jpydf-v2/pull/1052) (merged ahead of audit approval), [jpydf-v2#1382](https://github.com/deltaforesight/jpydf-v2/pull/1382) (merged ahead of audit approval) |

The strict full-budget predicate is vulnerable at the audited freeze commit
`528ac15f`: the converter refunds unspent USDS when the PSM charges `tout > 0`,
so the strategy's `_requireTokenBalance` strict equality check reverts on all
three withdrawal paths. PR jpydf-v2#1052 already changed Strategy accounting to
actual USDS spend before the report was received, and PR jpydf-v2#1382 merged
regression evidence for all three withdrawal paths after A/B reproduction and
side-effect review. No additional production-code change was warranted.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved as merged ahead of audit approval |
| Approved diff | jpydf-v2 `95c7086f..af194a1a` ([#1382](https://github.com/deltaforesight/jpydf-v2/pull/1382)) |
| Diff SHA-256 | `6d3ebbc1803a01728f13ee0c2e99859127988788388709e557ae2cc8a62f06ca` |
| Diff size | 3 files changed, 204 insertions(+), 3 deletions(-) |
| Test evidence | Merge-time regression battery recorded in the proposed-disposition prose. |

Basis: the merge-time evidence cycle recorded in the proposed-disposition
prose. The merged diff is adopted as the approved diff; the sync step
verifies the merge commit remains reachable from jpydf-v2 `develop`.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#49](https://github.com/deltaforesight/jpydf-audit/pull/49): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/high-01.patch`](../patches/high-01.patch).

## Fix-quality review (2026-08-05)

Verdict: **approve**. The current strategy tolerates a nonzero converter
refund (`InvalidUsdsSpent` only on zero or over-budget spend) and accounts by
actual spend; the pre-fix strict-equality predicate is confirmed vulnerable at
the freeze commit and fixed by `eed3edfa` (PR #1052) before the report
arrived. Regression tests inject refunds on all three exit paths and fail on
the old predicate (A/B verified). The two remaining strict balance checks are
correctly input-denominated. Operational note (reviewed, covered): a Sky
`tout` hike above `maxConversionLossBps` reverts on the slippage bound until
`setMaxConversionLossBps` clears the timelock; the Strategy incident runbook's
Sky row monitors converter preview/halt and `maxConversionLossBps`.
