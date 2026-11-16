# Low 03 — Contract Receiver In `redeem` Creates Permanently Unclaimable `WithdrawRequest`

| Item | Value |
| --- | --- |
| Reported severity | Low |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | Low accepted; impact and recommendations corrected |
| Candidate implementation | [jpydf-v2#1398](https://github.com/deltaforesight/jpydf-v2/pull/1398) (merged as `8bf86300` ahead of audit approval) |

A receiver without arbitrary-call integration could not trigger its delayed
settlement, although Safe-style/integrated contracts were not permanently
blocked. The report's original-sender override could break beneficiary
semantics, and owner-initiated request transfer would not help an incapable
owner. PR jpydf-v2#1398 instead made settlement permissionless while fixing
payout to the recorded request owner and deleting the obsolete ownership error.
It merged after baseline reproduction, fixed-payout/blacklist rollback tests,
and 1,434-test local and remote full Foundry runs plus the standard review
battery.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved as merged ahead of audit approval |
| Approved diff | jpydf-v2 `8f0efd94..8bf86300` ([#1398](https://github.com/deltaforesight/jpydf-v2/pull/1398)) |
| Diff SHA-256 | `f3ba3dc7cadbf654d6e1ae1da6e5811bcab19062d273cdd30e07fda95cf1abeb` |
| Diff size | 12 files changed, 231 insertions(+), 62 deletions(-) |
| Test evidence | Merge-time regression battery recorded in the proposed-disposition prose. |

Basis: the merge-time evidence cycle recorded in the proposed-disposition
prose. The merged diff is adopted as the approved diff; the sync step
verifies the merge commit remains reachable from jpydf-v2 `develop`.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#55](https://github.com/deltaforesight/jpydf-audit/pull/55): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/low-03.patch`](../patches/low-03.patch).

Deferred doc-mirror hunks (mirror drift; see the preserved patch): `documents/en .../spec/CollateralVault.md`; `documents/jp .../spec/CollateralVault.md`.

Outside snapshot curation scope: `documents/jp .../Peg-Defense-Bot-Security-Gate.md`; `documents/jp .../Peg-Defense-Redemption-Runbook.md`.

## Fix-quality review (2026-08-05)

Verdict: **approve**. Payout amount is fixed at request creation and the
recipient is strictly the recorded owner (`msg.sender` unused), so
permissionless settlement has no griefing lever; a blacklisted owner reverts
the whole claim atomically and the request stays claimable (tested with a
third-party trigger). One semantic change acknowledged: settlement is now
forced receipt — an owner cannot defer receiving matured funds. Nit: the
blacklist rollback test uses a bare expectRevert.
