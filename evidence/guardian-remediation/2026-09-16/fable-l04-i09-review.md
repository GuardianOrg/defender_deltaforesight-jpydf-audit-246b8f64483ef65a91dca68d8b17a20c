I've finished reading; all evidence is in hand. Writing up the verdicts now.

## Verdicts

| PR | Finding | Verdict |
| --- | --- | --- |
| 122 | L-04 | CONDITIONAL |
| 123 | I-09 | CONDITIONAL |

Both contract changes are correct and exact. The conditions are stale live docs, an unrebased overlap between the two PRs, and provenance pins that neither PR regenerates. I did not run any tests or verifiers; everything below is from reading.

## PR 122 (L-04)

**Root cause matches the fix.** `TroveManager.sol:396-402` takes gas compensation only from the SP portion, as `min(floor(collSPPortion/200), cap)`, and then applies the SP penalty to the remainder. At ICR equal to MCR this requires `MCR × 199 ≥ (1 + SP) × 200`. The floor and the cap only reduce the deduction, so the new check is sufficient and never over-rejects. The partial-offset case preserves the same ratio, so it holds there too.

**Boundary arithmetic is exact.** The minimum MCR is ceil(2.1e20 / 199) = 1.0552763819…e18. In units of 1e14, dJPY gives 10553 × 199 = 2,100,047 against the required 2,100,000. The old 10530 gives 2,095,470 and fails. Both boundary tests compute the ceiling the same way and check `boundary`, `boundary - 1`, and the old value, so they pin the inequality correctly. LLTV 94.76 is the two-decimal rounding of 100/1.0553, matching the convention used for 94.97.

**All callers covered.** The registry has two write paths: the constructor and `finalizeRiskParams`. TroveManager and BorrowerOperations copies are only set from the registry. The deploy preflight at `DeployLiquity2.s.sol:1319-1323` is called once from `_dfBranchParams()` and the Day-1 harness test exercises all eight branches through it. The symbol reaches the script through the transitive imports of `AddressesRegistry.sol` and `TroveManager.sol`, which I checked by reading, not compiling.

**Deployment consistency.** Constants, both manifests, the en and jp Parameters tables, the Core spec, and the jp Parameter Catalog all say 105.53 / 94.76 and the new formula.

**Conditions before merge:**
- `test/DFBranchRiskParams.t.sol:218` still locks the old weaker bound under the label "liquidation coverage". It passes, but it no longer expresses PRM-INV-004.
- `docs/{en,jp}/engineering/verification-ledgers/Requirements-Verification-Ledger.md` PRM-INV-004 rows still state the old formula and "JPY 1.05 ≤ 1.0530 is tight".
- `docs/jp/protocol/roadmap/Roadmap.md:164` still cites MCR 105.30% as the Branch 6 immutable value.
- The historical parameter rationale says 105.30% "matches the current value" in several places. Acceptable as an archive, but that phrase is now false.

## PR 123 (I-09)

**Correct and exact.** The redistribution path at `TroveManager.sol:406-416` deducts no gas compensation and additionally receives any surplus from the offset, so the plain `1 + redist ≤ MCR` bound is the right one. The 200/199 factor must not be applied here. Tests hit `110%`, `120% - 1`, and `120%` with a 20% penalty and confirm the value reaches TroveManager.

**Conditions before merge:**
- The Core spec lines 3193 and 4538, the error table, and the jp Parameter Catalog row restate the old SP bound. Merged after PR 122 without a rebase, this text would reintroduce the pre-fix formula.
- The per-branch lock in DFBranchRiskParams gets no redistribution assertion. The harness test covers Day-1 values, so this is minor.

## Interaction and shared residual limits

- **Neither check implies the other.** Redist ≥ SP means I-09 alone makes the old SP check redundant, but not the gas-aware one. L-04 binds for dJPY/dJGB, I-09 binds for the six 10% branches. All Day-1 sets pass both.
- **Test compatibility is fine.** The SP check runs before the redistribution check in both files. I-09 tests use SP 5% with MCR ≥ 110%, which clears the gas-aware bound. L-04 tests use redist 5%, which clears I-09 at the boundary. I still recommend a combined run.
- **Six files conflict textually:** `AddressesRegistry.sol`, `DeployLiquity2.s.sol`, the Core spec, the jp Parameter Catalog, and both test files insert at the same point. The second PR needs a manual rebase.
- **Constructor bypass is pre-existing and outside both PRs.** `AddressesRegistry.sol:122-131` runs only range checks and marks a branch finalized when the finalizer is zero. For Branches 0 and 1 the on-chain gate never applies. Coverage rests entirely on the script preflight, and test deployers construct registries directly.
- **Provenance pins break on both heads.** `PRODUCTION_COMPANION_MAPPING.tsv` and `scripts/verify-production-companion.sh` pin the manifest, Parameters.md, the deploy script, and both trees to the frozen production commit. Neither PR regenerates them, so the hash-only verifier will fail. The audit workflow doc says any source change needs a new immutable head and an explicit scope decision.
- **Inherent limit.** Liquidation triggers strictly below MCR, so the full premium is never exactly achieved. The cap issue in L-03 only increases coverage for large positions and is untouched here.
- **Test count.** Counting functions gives 17 + 11 + 1 = 29, consistent with the claim, but I did not execute them.