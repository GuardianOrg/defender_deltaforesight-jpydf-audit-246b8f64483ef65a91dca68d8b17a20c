# Liquidation Zombie Candidate Differential Review (2026-06-14)

The scope covers the zombie support in `LiquidationCandidateGetter`, the scan path of the Rust liquidator, and the Core spec / verification ledger / bot docs.

## Findings

### Fixed: zombie Troves did not appear in the LCG candidates, and the bot-side interim candidates had debt/coll of 0

In Liquity v2, a Trove that drops below `MIN_DEBT` via redemption becomes a zombie and drops out of `SortedTroves`. On the other hand, the liquidation core itself can target both active and zombie Troves. Previously the LCG scanned only SortedTroves, and the Rust bot was designed to read `TroveManager.lastZombieTroveId()` via a separate ABI, so there was a weakness where a zombie candidate's `entireDebt` / `entireColl` entered the planning log while still 0.

Actions:

- Kept the existing `getLiquidationCandidates` compatible, and added `getLastZombieLiquidationCandidate`.
- Added `getLiquidationCandidatesWithLastZombie` so that a liquidatable `lastZombieTroveId` can be optionally appended to the tail of the SortedTroves paging result.
- The zombie candidate is returned only when `lastZombieTroveId != 0`, the status is `zombie`, and `ICR < MCR`, and `entireDebt` / `entireColl` are filled in via `getLatestTroveData`.
- When `include_last_zombie=true`, the Rust liquidator uses the new combined API and treats the tail-appended candidate as `CandidateSource::LastZombie`.
- Added `CORE-LCG-FR-003` to the Core spec and moved `CORE-LCG-TBD-001` to resolved. In the verification ledger, the missing reflection of `CORE-AP-TBD-001`'s resolution was also fixed together.

## Residual Risks / Operational Assumptions

- The zombie that the LCG picks up is only the single `lastZombieTroveId` held by the core. Complete coverage of multiple zombies remains in the Liquidation Bot plan as a follow-up task via events/indexer.
- The bot continues to re-verify with `getCurrentICR` before sending. Because the final price follows the protocol price feed inside `batchLiquidateTroves`, the LCG's candidacy is an aid to execution eligibility and not the final decision.

## Verification

- `forge test --match-contract LiquidationCandidateGetterTest` (3 passed)
- `cargo test` in `bots/liquidator` (14 passed)
- `forge build` (succeeded; existing Foundry lint notes remain)
- `git diff --check` (succeeded)
