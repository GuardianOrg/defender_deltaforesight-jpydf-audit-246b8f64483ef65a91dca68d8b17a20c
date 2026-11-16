# Info 02 — `DToken::setCap`: No Lower-bound Check Against `totalSupply`

| Item | Value |
| --- | --- |
| Reported severity | Informational |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | Informational code finding rejected |
| Candidate implementation | [jpydf-v2#1411](https://github.com/deltaforesight/jpydf-v2/pull/1411) (closed without merge; branch preserved as candidate patch) |

PR jpydf-v2#1411 confirms that a below-supply cap is the specified hard
issuance stop, not a violated global invariant. Existing balances remain
unchanged, burn/redemption remains live, and minting resumes automatically
after supply falls within the cap. It keeps production code unchanged and
extends the real `DToken` proxy regression evidence.

## Candidate-patch review (2026-08-04)

Verdict: **approve**.

- Spec-backed, not post-hoc: DTKN-FR-006 explicitly allows a cap below
  `totalSupply()` (new mint stops only), and DTKN-INV-005 explicitly excludes
  `totalSupply() <= cap` from global invariants.
- Test evidence is boundary-exact against the real `DToken` behind an
  `ERC1967Proxy`: mint above cap reverts with exact `CapExceeded` args, burn
  succeeds while supply exceeds cap, and a mint landing exactly at the cap
  succeeds — pinning strict `>` semantics and automatic resumption.
- Focused suite run: 45/45 pass. Adding the auditor's proposed lower-bound
  check would break the test at the `setCap` step, so the evidence would catch
  an accidental spec change. No discrepancies found.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved (as-is) |
| Approved diff | jpydf-v2 `4df6d902..1c38f89d` ([#1411](https://github.com/deltaforesight/jpydf-v2/pull/1411)) |
| Diff SHA-256 | `aa4b1c8aa15b96f9b0ed399cfd71c4e64cb80c64f34eac728053d9fed7930a80` |
| Diff size | 2 files changed, 115 insertions(+), 1 deletion(-) |
| Test evidence | DToken suite 45/45 including boundary-exact cap tests on the real proxy. |
| Approved patch | [`patches/info-02.patch`](../patches/info-02.patch) |

Basis: the candidate-patch review above. The candidate branch diff is
adopted as the approved diff and lands in jpydf-v2 via the audit sync PR.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#61](https://github.com/deltaforesight/jpydf-audit/pull/61): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/info-02.patch`](../patches/info-02.patch).
