# Info 04 — `setStrategyValuationMaxAge` Accepts Unvalidated `maxAge` Value

| Item | Value |
| --- | --- |
| Reported severity | Informational |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | observation accepted; fixed bounds rejected |
| Candidate implementation | [jpydf-v2#1413](https://github.com/deltaforesight/jpydf-v2/pull/1413) (closed without merge; branch preserved as candidate patch) |

PR jpydf-v2#1413 confirms that TTL 0 is the specified fail-closed mode and
pre-cache proxy default: healthy live valuation is still used, while a live
failure contributes zero without reverting. Restoring a nonzero TTL
immediately restores a still-fresh cache. It keeps production code unchanged,
rejects the ungrounded universal 1-hour/7-day bounds, and records the real
high-TTL stale-value risk.

## Candidate-patch review (2026-08-04)

Verdict: **approve**.

- Production code untouched; the audit's "forces live reads on every solvency
  call" framing is confirmed wrong in source — cache/TTL is only consulted
  when the live read fails.
- All three behaviors are exercised: healthy live valuation used at TTL 0,
  reverting strategy contributing zero without view reverts (with exact
  `totalUnderlying`/`backingRatio`/`backingShortfall` values discriminating
  fail-closed from cache fallback), and TTL restore bringing the cached value
  back on the same Vault with no migration.
- Focused test and full 56-test `CollateralVaultTest` suite pass. Nit: the
  restore test does not warp within the TTL window first, so cache freshness
  is trivially satisfied; staleness expiry is covered by neighboring tests.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved (as-is) |
| Approved diff | jpydf-v2 `4df6d902..f59f9533` ([#1413](https://github.com/deltaforesight/jpydf-v2/pull/1413)) |
| Diff SHA-256 | `df879c5aac75c4f2f4e94fb4ce7eb163a40a82b0a0e904abaeeab841578c39d0` |
| Diff size | 2 files changed, 147 insertions(+) |
| Test evidence | Focused test plus CollateralVaultTest 56/56. |
| Approved patch | [`patches/info-04.patch`](../patches/info-04.patch) |

Basis: the candidate-patch review above. The candidate branch diff is
adopted as the approved diff and lands in jpydf-v2 via the audit sync PR.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#63](https://github.com/deltaforesight/jpydf-audit/pull/63): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/info-04.patch`](../patches/info-04.patch).
