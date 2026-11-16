# Docs Staleness / Discussion Gap Review (2026-06-21)

## Purpose

As a pre-mainnet docs cleanup, separate out the progress metadata that tends to go stale from the TBD / risk areas where discussion is still thin. The source of truth for the specification is `documents/jp/spec`, `Product-Overview.md`, and `Parameters.md`; this file is a point-in-time review.

## Stale docs expressions found this time

| Type | Target | Action |
| --- | --- | --- |
| A procedure doc readable as treating a specific commit as "currently verified" | `Local-Setup-And-Verification-Guide.md` | Remove the old develop-tip pin from the body and move it to a point-in-time verification record at the end |
| A design memo where a PR number / old baseline appears at the top of a permanent design | `Governance-Roles-Timelock.md` | Move the current authority into the component spec / §4 / §5, and explicitly mark the old baseline as historical analysis |
| Risk of misreading a dated review as the current state | `development/reviews/*` | Per the policy of `documents/README.md` and `development/README.md`, treat it as point-in-time evidence. Only move it to a spec / ledger when promoting it to the source of truth |

## Priority areas to deepen discussion

| Priority | Area | Current state | Why look at it before mainnet | Next improvement target |
| --- | --- | --- | --- | --- |
| P1 | Aave recoverable amount vs valuation | `AAVE-TBD-003` still leaves the divergence between AUM and actual recoverable amount during reserve anomalies | `scaledBalance × normalizedIncome` is an accounting claim and can diverge from the immediately recoverable amount during reserve pause / freeze / bad debt | `AaveV3Strategy.md` already documents the boundary between temporary liquidity shortage and confirmed loss. Next, further concretize the detection items and operator judgment on the admin / monitoring side |
| P1 | Treasury Safe reserve and 25% PIL / SP additional reward | Day-1 is a Safe reserve; the Day-2 Treasury / Distributor is unimplemented | If the explanation of user display, accounting, and the funding source for operational top-ups is vague, the confusion over "where does the 25% flow to" will recur | `InterestRouter.md` / route runbook / `Frontend.md` / data-source ledger already document the Day-1 75%/25% and claim boundary. Next, reconcile against the actual UI copy and the ops/admin display |
| P1 | Frontend production ownership / auth / stats backend | `FRNT-TBD-004/005/007/008/009` still leave production hosting, authentication, the stats API, i18n, and the mobile scope | Because the admin console / user app become the mainnet operation surface, authentication, display freshness, and the removal of external URLs need to be closed in both the spec and the implementation | `Frontend.md` already documents the boundary between mainnet-required and Day-2-acceptable. Next, reconcile the console / ops implementation against the ledger item by item |
| P2 | Oracle staleness finalization / monitoring | ETH 24h, branch-local 48h, and JPY 72h already have candidate values and rationale documented | `jpyFrozenSince` is set at the first observation block, so if the keeper does not watch it, the start of the soft-freeze is delayed | `Mainnet-Deploy-Env-Freeze-Runbook.md` already documents the `updatedAt` remaining time, `JpyRateFrozen`, and the shutdown event alert evidence. Next, reconcile against the ops monitoring implementation |
| P2 | Lido async launch gate | LidoStrategy is implemented, but finalization / hint / keeper runbook is a launch gate | If async recovery gets stuck, it affects buffer recovery, the claim experience, and backing repair | Added operational bounds to `LidoStrategy.md` and the incident runbook |
| P2 | Branch 5-7 inert activation | Parameters already specifies the provisional immutable branch values | Branch risk parameters are immutable after deploy. They cannot necessarily be opened later with just `setCap` | `Inert-Branch-Activation-Runbook.md` already adds the Day-2 activation gate, risk re-derivation, one-shot Underlying binding, PriceFeedProxy replacement, and the final cap-release ordering |

## Expressions that may intentionally remain

- `BOLD` is needed in the context of explaining the upstream / base fork, or legacy surface pruning. Returning it to the user-facing / owned API surface is a separate matter.
- `mock` is needed when explaining external data source substitution in local production-parity. However, displaying actual yield / external strategy as a mock in the user-facing frontend or mainnet docs is not allowed.
- `TBD` remains as an append-only ID. If resolved, write Resolved in the body and do not reuse the ID.

## Next small improvement candidates

1. Reconcile the items that admin / monitoring should watch during Aave reserve anomalies (reserve pause/freeze, liquid reserve, scaled balance, normalized income, external incident report, actual recovery tx) against the frontend/ops display and alerts.
2. Reconcile the production admin / stats backend gate in `Frontend.md` against the current console / ops implementation, and if unimplemented, add it to `Frontend-Data-Source-Ledger.md` as an explicit gap.
3. Add the alert threshold for oracle stale monitoring and the freeze/shutdown response to `Mainnet-Deploy-Env-Freeze-Runbook.md`.
4. Check the User app's Earn copy / APR source, and reconcile on the implementation side whether any display showing PIL 25% as a claimable reward remains.
