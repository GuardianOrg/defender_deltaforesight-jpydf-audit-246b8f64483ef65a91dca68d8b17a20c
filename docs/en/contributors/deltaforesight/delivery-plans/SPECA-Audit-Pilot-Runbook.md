# SPECA Audit Pilot Runbook

## 0. Purpose

This runbook defines the pilot procedure for using SPECA in JPYdf external audit preparation. SPECA is an auxiliary audit tool that extracts properties from natural-language specifications and attempts to prove whether the implementation satisfies them. Its output is candidate findings; it does not replace ChainDefenders or other human audits, existing Foundry / Slither coverage, or manual review.

## 1. Scope

The first pilot prioritizes DeltaForesight original layers in contracts.

- `contracts/src/JpydfToken.sol`
- `contracts/src/DToken.sol`
- `contracts/src/CollateralVault.sol`
- `contracts/src/Strategies/`
- `contracts/src/PriceFeeds/`
- `contracts/src/Zappers/`
- `contracts/src/InterestRouterForwarder.sol`
- `contracts/src/Dependencies/Constants.sol`
- Corresponding `contracts/src/Interfaces/`

Out of scope:

- `contracts/lib/`
- `contracts/test/`
- `frontend/`
- `subgraph/`
- `bots/`
- `documents/`
- build / cache / generated artifacts

For the first pilot, the Liquity v2 core surface is limited to checking `CORE-MOD-*` and the JPY DeFi extension boundary. Full core behavior verification remains governed by `Core-Requirements-Verification-Ledger.md` plus upstream parity and the Foundry suite.

## 2. Specification Inputs

The canonical specifications read by SPECA are in `documents/jp`. Priority order:

1. `documents/jp/protocol/product/Product-Overview.md`
2. `documents/jp/Parameters.md`
3. `documents/jp/protocol/product/spec/dToken.md`
4. `documents/jp/protocol/product/spec/CollateralVault.md`
5. `documents/jp/protocol/product/spec/strategies/Strategy.md`
6. `documents/jp/protocol/product/spec/strategies/AaveV3Strategy.md`
7. `documents/jp/protocol/product/spec/strategies/ERC4626Strategy.md`
8. `documents/jp/protocol/product/spec/Oracle.md`
9. `documents/jp/protocol/product/spec/Zapper.md`
10. `documents/jp/protocol/roadmap/spec/Treasury.md`
11. `documents/jp/protocol/product/spec/InterestRouter.md`
12. `CORE-MOD-*` / boundary sections in `documents/jp/protocol/product/spec/Liquity-v2-Core-Spec.md`

SPECA properties and findings are triaged so they can map back to requirement IDs (`DTKN-*`, `VAULT-*`, `STGY-*`, `ORCL-*`, `ZAP-*`, `IRTR-*`, `CORE-MOD-*`).

## 3. Preconditions

- Freeze the audit target commit. Do not use a dirty worktree or moving branch.
- Do not include RPC URLs, private keys, API keys, or `.env` values in SPECA inputs, outputs, or issue text.
- `outputs/` and `target_workspace/` are generated artifacts and are not tracked by git.
- Treat SPECA results as candidate findings. A human must confirm exploitability, scope, and severity.

## 4. Setup

The official quickstart recommends `npx speca-cli@latest doctor`, `npx speca-cli@latest init`, then `npx speca-cli@latest run --target 04`. JPY DeFi uses templates.

```bash
mkdir -p outputs
cp documents/jp/contributors/deltaforesight/delivery-plans/speca/TARGET_INFO.template.json outputs/TARGET_INFO.json
cp documents/jp/contributors/deltaforesight/delivery-plans/speca/BUG_BOUNTY_SCOPE.template.json outputs/BUG_BOUNTY_SCOPE.json
```

Replace `target_commit` in `outputs/TARGET_INFO.json` with the audit freeze commit.

```bash
npx speca-cli@latest doctor
npx speca-cli@latest run --target 04 --workers 4 --budget 50
```

For low-cost preliminary runs:

```bash
npx speca-cli@latest run --target 03 --workers 2 --budget 15
```

### 4.1 Notes for JPY DeFi private/local execution

As of the 2026-06-19 pilot, `speca auth status` / `doctor` pass with Claude Code subscription authentication. For private repositories / local docs, note the following.

- `npx speca-cli@latest run` may fail to resolve phase runners from the target repository cwd; running `uv run python3 scripts/run_phase.py --phase ...` from the SPECA repository clone may be required.
- GitHub fetch MCP may return 404 for private repository raw/spec URLs. In that case, create `target_workspace -> /path/to/jpydf-v2` in the SPECA clone and enumerate the canonical `documents/jp` specs in `outputs/01a_STATE.json` with `local_path`.
- `outputs/` contains SPECA intermediate / final artifacts and should be git ignored. Commit only summaries and triage results into review records; do not commit large JSON files or logs that may include authentication context.
- Do not treat abstract spec notation as literal function names. Example: `emergencyWithdrawFrom{Protocol}` is not a common `IStrategy` function; it maps to derived-specific functions such as `emergencyWithdrawFromAave` / `emergencyWithdrawFromLido` / `emergencyWithdrawFromERC4626`.
- Phase 03 may accept `--min-severity` while not applying the severity gate to queue creation. To run only High and above, copy severity-filtered items from `02c_PARTIAL_*.json` into a separate output dir and pass `--output-dir`.

Browse results:

```bash
npx speca-cli@latest browse outputs/04_PARTIAL_*.json
npx speca-cli@latest browse --filter "severity:High AND verdict:CONFIRMED_*"
```

## 5. Triage Policy

Classify SPECA findings in this order.

| Judgment | Handling |
| --- | --- |
| Confirmed vulnerability | Open a fix for code / test / spec as appropriate. Fund loss, authority escape, oracle / liquidation / redeem failure are P0/P1 |
| Spec gap | Add an ID-based requirement to the canonical spec and follow through with implementation / tests if needed |
| Test gap | Record as unverified in `Requirements-Verification-Ledger.md` and add Foundry / fork / integration tests |
| False positive | Record the invariant, trust boundary, or reachability reason in a runbook or dated review |

Focus especially on:

- Donation / share inflation / accounting drift
- Strategy loss / delayed redeem / backstop reserve release
- `allocate()` bulk movement, cooldown, 100% buffer configuration, deposit / redeem pause
- Whether `sendToVault` / `sendProfitToVault` can induce liquidation or borrow-rate jumps
- Oracle stale / backing ratio / source timelock / branch shutdown
- Stability Pool offset / liquidation / redistribution / urgent redemption degradation
- Governance role multiple holders, Timelock, Guardian emergency action
- Zapper slippage / approval / removed Flash Loan close surface / receiver routing
- InterestRouter 25% PIL route and recipient handover

## 6. Record Locations

- Point-in-time run record: `documents/jp/engineering/historical-reviews/YYYY-MM-DD-SPECA-Audit-Pilot.md`
- Requirements verification reflection: `documents/jp/engineering/verification-ledgers/Requirements-Verification-Ledger.md`
- Core boundary reflection: `documents/jp/engineering/verification-ledgers/Core-Requirements-Verification-Ledger.md`
- Fix PR: split narrowly per finding

## 7. Official References

- SPECA repository: https://github.com/NyxFoundation/speca
- Documentation: https://speca.pages.dev/
- Config schema: https://speca.pages.dev/docs/getting-started/config-files
- Quickstart: https://speca.pages.dev/docs/getting-started/quickstart
