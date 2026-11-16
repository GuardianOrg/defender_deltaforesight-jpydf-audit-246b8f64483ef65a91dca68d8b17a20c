# Info 06 — `setAddresses` Does Not Validate 18 Core Contract Addresses

| Item | Value |
| --- | --- |
| Reported severity | Informational |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | risk accepted; remediation adapted to deployment order |
| Candidate implementation | [jpydf-v2#1415](https://github.com/deltaforesight/jpydf-v2/pull/1415) (closed without merge; branch preserved as candidate patch) |

PR jpydf-v2#1415 preserves the CREATE2 constructor cycle, then reads back all
18 frozen registry fields after deployment and requires exact expected
identity, nonzero addresses, and runtime code. Dedicated tests reject field
swaps, zero, and EOAs; `contracts/src`, ABI, and storage remain unchanged.
Residual: the eight non-CREATE2 fields are compared against the same input
struct fed to `setAddresses`, so a construction-time swap between two
code-backed addresses in that struct remains undetected; accepted for lack of
an independent in-scope source.

## Candidate-patch review (2026-08-04)

Verdict: **approve with nits**. Only open remediation PR touching non-test
code (deploy script), so it received the deepest review.

- The 18-getter readback was counted against the registry contract — nothing
  missed; nonzero and `code.length` requires are real, and a `require` failure
  aborts the `forge script` simulation before any transaction broadcasts.
- The 10 CREATE2 fields are a genuine non-circular check: expected values are
  overwritten with the actually deployed instances before verification, so
  prediction/registration typos and registry-internal slot swaps are caught.
- The 8 non-CREATE2 fields are a store/read round-trip (catches slot swaps,
  zero, EOAs) but cannot catch a construction-time swap between two
  code-backed addresses — exactly the finding's threat class. Recorded above
  as an accepted residual; a stronger check would need per-contract semantic
  probes.
- Dedicated tests pass 4/4 and are non-vacuous (mismatch, zero, codeless, and
  an 18-distinct-stub happy path that cross-checks the getter↔field mapping).
  Nit: the "swap" case substitutes a fresh stub rather than swapping two
  registered fields; same code path, slightly loose naming.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved (as-is) |
| Approved diff | jpydf-v2 `4df6d902..fd0f8478` ([#1415](https://github.com/deltaforesight/jpydf-v2/pull/1415)) |
| Diff SHA-256 | `cd86d57e4a4e75cc00495a20be37353792fe7b11fa289a94a16047423cac0f38` |
| Diff size | 5 files changed, 292 insertions(+), 4 deletions(-) |
| Test evidence | Dedicated wiring tests 4/4 (accepts-all-18, mismatch, zero, codeless). |
| Approved patch | [`patches/info-06.patch`](../patches/info-06.patch) |

Basis: the candidate-patch review above. The candidate branch diff is
adopted as the approved diff and lands in jpydf-v2 via the audit sync PR.

The store/read circularity of the eight non-CREATE2 fields is recorded above as an accepted residual; no further check is required for closure.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#65](https://github.com/deltaforesight/jpydf-audit/pull/65): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/info-06.patch`](../patches/info-06.patch).
