# Info 03 — `setAllocatorConfig` Accepts Unvalidated `cooldown` And `maxMove` Values

| Item | Value |
| --- | --- |
| Reported severity | Informational |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | observation accepted; remediation rejected |
| Candidate implementation | [jpydf-v2#1412](https://github.com/deltaforesight/jpydf-v2/pull/1412) (closed without merge; branch preserved as candidate patch) |

PR jpydf-v2#1412 confirms that `allocateMaxMove = 0` is the specified and
observable outbound stop used by no-Strategy branches, while cooldown zero
intentionally disables the interval guard. A high cooldown does block
allocation, but the same Vault recovers immediately after GOV correction. It
keeps production code unchanged and records the remaining
governed-misconfiguration risk.

## Candidate-patch review (2026-08-04)

Verdict: **approve**.

- Production code untouched; diff is test + review document only.
- "Specified" is real: VAULT-FR-012 states no validation and the zero-as-stop
  semantics; the Parameters tables show `allocateMaxMove = 0` on all
  inert/TBD branches.
- Recovery is exercised, not asserted in prose: the test blocks allocation
  under a 365-day cooldown (`CooldownNotMet` revert), then corrects config and
  allocates successfully at the same timestamp, attributing recovery to the
  governance change.
- Focused tests and the full 121-test `CollateralVaultStrategyTest` suite
  pass. Nits are prose-only (an off-by-one line reference in the review doc).

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved (as-is) |
| Approved diff | jpydf-v2 `4df6d902..f0b82f0c` ([#1412](https://github.com/deltaforesight/jpydf-v2/pull/1412)) |
| Diff SHA-256 | `d9673b2e06d55414d6585303743f2ffb9068b94739b6561222f4e96cb8ab487a` |
| Diff size | 2 files changed, 157 insertions(+) |
| Test evidence | Focused pair plus CollateralVaultStrategyTest 121/121. |
| Approved patch | [`patches/info-03.patch`](../patches/info-03.patch) |

Basis: the candidate-patch review above. The candidate branch diff is
adopted as the approved diff and lands in jpydf-v2 via the audit sync PR.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#62](https://github.com/deltaforesight/jpydf-audit/pull/62): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/info-03.patch`](../patches/info-03.patch).
