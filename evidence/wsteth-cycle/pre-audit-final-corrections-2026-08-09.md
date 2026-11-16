# Pre-Audit Multi-Skill Final Corrections — 2026-08-09

## Review identity

| Item | Value |
| --- | --- |
| Review input | Initial follow-up freeze `0a85b374015e2553d2985b4a3f454b6aee4514a5` |
| Final Solidity correction | `c1b34df3e5bf6be9d94e7f0bace224c03c859974` |
| Final handoff freeze | `fe3d3d0e182b8189202dee3a3db8103bd0df1de7` |
| Source merge | `03fa20a3a1e6971876185c2bc7889ee47f6608c1` |
| Public audit snapshot root | `source-snapshot/contracts` |
| Implementation inventory | 73 implementation files with `Interfaces/` directories excluded; 109 Solidity files in the full `contracts/src` reconciliation tree |

This record completes the earlier point-in-time review in
[`pre-audit-multi-skill-review-2026-08-08.md`](./pre-audit-multi-skill-review-2026-08-08.md).
It does not rewrite the Slither or 170-vector evidence produced at the earlier
freeze. It records the later independent findings, their skeptical validation,
and the exact corrected source identity.

This evidence is self-contained for external auditors. Private source-repository
PR numbers are intentionally omitted from the review navigation; inspect the
committed source and tests linked below and use the exact identities for
provenance.

## Procedure coverage and final disposition

| Procedure | Coverage | Final result |
| --- | --- | --- |
| Pashov | 170 / 170 attack-vector prompts | No reportable finding in that pass. |
| Trail of Bits | Existing repository procedure, constrained as recorded in the earlier evidence | No additional source correction. |
| QuillShield | Existing procedure and prior remediation reconciliation | Prior M2/L1 corrections retained. |
| Cyfrin Solidity standards | Production-standard gap review across source, tests, deployment, governance, and CI | No Critical/High/Medium/Low source defect; style/compiler/contact/modifier/key-handling items remain separate hardening work. |
| Forefy | Two independent experts followed by a skeptical triager | One Medium Stability Pool finding and one Low ERC-4626 emergency-accounting finding, both confirmed and fixed. |
| SC Auditor | Complete 370-item checklist | 219 applicable and OK, 151 not applicable with reasons, 0 additional issues. |
| Nemesis | Feynman Pass 1 → state-inconsistency Pass 2 → Feynman Pass 3 feedback | Confirmed the same Medium and Low; rejected the analogous Aave hypothesis in the final pass. |

## Verified findings and corrections

### M-01 — Same-block Stability Pool collateral-gain settlement

`withdrawFromSP` enforced the deposit-block boundary, but
`provideToSP(nonzero, true)` could settle current liquidation collateral gain
after a same-block offset without using the guarded withdrawal path. This
violated the documented anti-sniping objective even though realized atomic
profit still depended on JPYdf funding and collateral exit liquidity.

Correction: exact source identity
`27192de07bb26f87f6611deea5f326ad972c3ab2`, preserved by source-side merge
`ce3c8aca4feb555cfd43ce0a5114ffe3f1c0576f`. Review
[`DFStabilityPool.sol`](../../source-snapshot/contracts/src/DFStabilityPool.sol)
and its
[`stabilityPool.t.sol`](../../source-snapshot/contracts/test/stabilityPool.t.sol)
regression coverage in this repository.

The guard applies only when an existing depositor requests payout of current or
stashed collateral gain in the deposit block. New deposits, `_doClaim=false`
stashing, gain-free top-ups, JPYdf-yield-only settlement, and next-block
collateral settlement remain live. The focused Stability Pool suite passes
99 / 99 in the final snapshot.

### L-01 — ERC-4626 partial emergency recovery tracker

The donation-inclusive emergency path sized redemption from raw shares but
subtracted the full observed burn from `_ownShares`. With a repair donation and
venue-limited partial redemption, this could leave a persistent false-low owned
tracker and understate residual conservative backing.

Correction: exact source identity
`c1b34df3e5bf6be9d94e7f0bace224c03c859974`, preserved by source-side merge
`aa1e55e1fba5d24a351aa7dd5319439a57a02cb5`. Review
[`ERC4626Strategy.sol`](../../source-snapshot/contracts/src/Strategies/ERC4626Strategy.sol)
and its
[`ERC4626Strategy.t.sol`](../../source-snapshot/contracts/test/ERC4626Strategy.t.sol)
regression coverage in this repository.

The emergency path now preserves `ownAfter = min(ownBefore, rawAfter)`. The
ordinary owned-position withdrawal path is unchanged, so donation exclusion in
normal AUM and yield attribution remains intact. The final ERC-4626 suite
passes 24 / 24.

### Rejected Aave analogue

The final Nemesis feedback pass rejected changing Aave. Its scaled-balance
semantics and reviewed transition did not establish the same persistent
tracker defect under the proposed sequence. No Aave source change was made.

## Build-size reliability correction

The repeated nonzero `forge build --sizes` result was caused by stale tester
artifacts in the shared `out/` directory, not an oversized production
implementation. Source identity
`0f88975126cc0bfe1c929454d50f6299a5cdebf3` moved the size gate to fresh
temporary `out` and `cache` paths and disables cache reuse; it is preserved by
source-side merge `9f1cbf107cb3c1119296a3657b7ffdff78784b68`.

The same wrapper is committed in this public snapshot. It passes even when the
working tree's ordinary `out/` contains oversized test artifacts. The largest
production runtime is `BorrowerOperations` at 24,385 / 24,576 bytes.

## Final public-snapshot verification

- `scripts/sync-from-source.sh --verify`: drift 0 / missing 0 / undecided 0 /
  stated 0 at `fe3d3d0e`.
- `scripts/verify-audit-patches.sh`: 21 / 21.
- `source-snapshot/contracts/utils/check-contract-sizes.sh`: passed.
- standard Foundry gate: 1,541 / 0 / 0 across 81 suites.
- final correction Slither 0.11.5: 187 contracts / 93 detectors / 374
  repo-wide results; no new confirmed changed-line issue.
- `cloc 2.06`: 13,272 whole-tree nSLOC; normalized CSV-body SHA-256
  `388738f44cd4c8c345761404aecf889c24024bfec2d123499ffe74ef4f40f7f8`.

## Final conclusion

Confirmed open Critical / High / Medium / Low source findings from these
pre-audit procedures: **0**. This means the two verified findings above are
fixed in the final source freeze; it does not relabel the earlier runs as having
found them.

Deployment execution, final Safe/timelock readbacks, live venue manifests, and
alert delivery remain launch evidence. A large adverse Chainlink move while a
new report is pending but not stale remains an oracle-latency monitoring and
parameter assumption, not a confirmed validation bypass in the frozen source.
