# Info 01 — Euler Reward Streams Are Not Compatible With Current `ERC4626Strategy`

| Item | Value |
| --- | --- |
| Reported severity | Informational |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | future-integration gap accepted; activation gated |
| Candidate implementation | [jpydf-v2#1410](https://github.com/deltaforesight/jpydf-v2/pull/1410) (closed without merge; branch preserved as candidate patch) |

PR jpydf-v2#1410 confirms that the current adapter cannot pull rewards left in
an external distributor such as Euler Reward Streams, while Euler remains
outside the Day-1 scope. It keeps production code unchanged and gates
activation behind a documented No-Go policy — checklist-enforced during
activation review, not an on-chain check — until the reward path is proven
disabled or a venue-specific claim implementation, settlement tests, and
additional audit are complete.

## Candidate-patch review (2026-08-04)

Verdict: **approve with nits**.

- Docs-only diff confirmed: zero changes under `contracts/` or `script/`.
- The incapability claim was verified in source: the only reward entrypoints
  are `claimMerklRewards` and `sweepRewardToken` (balance-held tokens only);
  no `IRewardStreams`/`claimReward` surface exists, and
  `estimatedTotalUnderlying()` values only held vault shares.
- Nit: the activation gate is policy/documentation (Strategy-Selection-Policy
  No-Go row, hard-requirement row, spec item), with no code or deploy-tooling
  enforcement. Defensible for an Informational on an out-of-scope venue, and
  the disposition wording here states the process-gate nature explicitly.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved (as-is) |
| Approved diff | jpydf-v2 `4df6d902..102c23f7` ([#1410](https://github.com/deltaforesight/jpydf-v2/pull/1410)) |
| Diff SHA-256 | `0750d8783744370316ef45e7abfa5eee33e4b3e00c94ab783b9686abc47ab6ac` |
| Diff size | 5 files changed, 153 insertions(+), 2 deletions(-) |
| Test evidence | Docs-only; verified zero executable change (contracts/ and script/ untouched). |
| Approved patch | [`patches/info-01.patch`](../patches/info-01.patch) |

Basis: the candidate-patch review above. The candidate branch diff is
adopted as the approved diff and lands in jpydf-v2 via the audit sync PR.

The activation gate is procedural (documented No-Go policy), not an on-chain check; this is accepted for an Informational finding on an out-of-scope venue.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#60](https://github.com/deltaforesight/jpydf-audit/pull/60): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/info-01.patch`](../patches/info-01.patch).

Deferred doc-mirror hunks (mirror drift; see the preserved patch): `documents/en .../Strategy-Selection-Policy.md`; `documents/jp .../Strategy-Selection-Policy.md`.
