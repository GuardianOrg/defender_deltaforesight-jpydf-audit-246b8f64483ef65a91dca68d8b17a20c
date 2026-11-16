# JPYdf Liquity Liquidator

Rust keeper for scanning and liquidating undercollateralized JPYdf/Liquity v2 Troves.
The design follows Liquity v2 branch/Trove/Stability Pool mechanics first.

The first implementation target is an operator bot, not a pure profit-maximizing
liquidator. In `protocol-maintenance` mode the bot may submit an unprofitable
liquidation when it stays within explicit gas/loss budgets.

Participant-facing launch readiness treats this bot as operator maintenance
unless the Day-2 profit-seeking requirements in
`documents/jp/protocol/launch/gates/Mainnet-Participant-Readiness-Gate.md` are
met. Do not market the current bot as external-profit-seeker ready without
disposal route, inventory, relay, RPC quorum, and profit-model evidence.

## Current Scope

- Read deployment and policy settings from TOML.
- Fetch protocol price and MCR per branch.
- Skip a branch when its DF price feed source reports an active JPY/USD
  soft-freeze (`jpyFrozenSince != 0`), even if `fetchPrice()` has not yet
  escalated that shared-FX outage to `oracleFailed`.
- Scan `LiquidationCandidateGetter` with cursors over `SortedTroves` and the
  optional `lastZombieTroveId` append path.
- Revalidate candidate ICRs immediately before execution planning.
- Prioritize candidates by liquidation depth, then SP-offset friendliness, then
  last-zombie coverage before building batches.
- Report branch SP offset capacity for operator backstop/JIT decisions.
- Build branch-local batches.
- Dry-run by default.
- Optional transaction submission behind explicit config flags.
- Excludes JPYdf sourcing, automatic SP top-up, atomic JIT bundles, and
  collateral disposal.

## Code Map

- `src/main.rs`: CLI parsing/dispatch, config hashing, and tracing setup.
- `src/config.rs`: TOML parsing, defaults, and resolved runtime config.
- `src/config/validation.rs`: launch-safety validation and config primitive
  parsing helpers.
- `src/branch_contracts.rs`: direct branch contract config and registry fallback
  resolution.
- `src/scanner.rs`: branch reads, candidate discovery, ICR revalidation, batch
  planning, live submission, and receipt recording hooks.
- `src/liquidation_batch.rs`: per-batch candidate aggregation for liquidation
  planning.
- `src/liquidation_math.rs`: candidate model, liquidation priority ordering, SP
  offset coverage math, and gas compensation estimates.
- `src/numeric.rs`: checked and capped integer conversions for protocol values.
- `src/vault_safety.rs`: collateral-vault safety snapshot reads, blocker
  classification, and liquidation guard checks.
- `src/policy.rs`: dry-run / protocol-maintenance / profit-seeking execution
  decision policy.
- `src/evidence.rs`: `scan-once --json/--out` launch-gate evidence schema,
  builders, and JSON writer.
- `src/profit_evidence.rs`: unsupported profit-model evidence schema and
  builders for planned liquidation batches.
- `src/gas_market.rs`: latest-block base fee reads and gas-price snapshot
  derivation for liquidation planning evidence.
- `src/rpc_provider.rs`: HTTP provider construction, signer attachment, RPC URL
  parsing, and chain-id verification.
- `src/rpc_health.rs`: primary/fallback RPC health probing and quorum evidence
  aggregation.
- `src/rpc_timeout.rs`: shared bounded-RPC-read timeout wrapper.
- `src/runtime.rs`: daemon scan scheduling, live-submission cooldown tracking,
  and runtime-state load logging.
- `src/run_command.rs`: daemon `run` provider selection, poll loop, scan retry,
  planning retry, and state persistence.
- `src/scan_once_command.rs`: `scan-once` provider selection, one-shot scan
  execution, evidence emission, and state/cooldown persistence.
- `src/receipt_ledger.rs`: submitted transaction and receipt outcome JSONL
  append ledger.
- `src/receipt_ledger_reader.rs`: receipt JSONL reading and reconciliation target
  selection.
- `src/receipt_outcome_writer.rs`: shared receipt outcome, gas-only PnL, and
  PnL retry-marker append flow.
- `src/receipt_reconcile_command.rs`: `reconcile-receipts` CLI option handling,
  read-only provider setup, and human-readable report output.
- `src/receipt_reconciler.rs`: read-only late receipt and replacement-candidate
  reconciliation.
- `src/receipt_status.rs`: receipt classification constants, status bucketing,
  and terminal classification shared by live, evidence, and reconciliation paths.
- `src/pnl_ledger.rs`: gas-only PnL JSONL ledger for receipt outcomes.
- `src/ledger_io.rs`: append-only JSONL file preparation and append helpers.
- `src/ledger_setup.rs`: live-mode receipt/PnL ledger preparation and operator
  warnings shared by scan-once and run.
- `src/eth.rs`: primitive aliases and compatibility helpers for Alloy values.
- `src/contracts.rs`: generated Alloy bindings used by the scanner.
- `src/state.rs`: scan cursor and daemon submission-cooldown state persistence.

## Run

```sh
cp bots/liquidator/config.example.toml bots/liquidator/config.local.toml
cargo run --manifest-path bots/liquidator/Cargo.toml -- \
  --config bots/liquidator/config.local.toml \
  scan-once
```

Machine-readable launch gate evidence can be emitted with `scan-once --json --out`:

```sh
cargo run --manifest-path bots/liquidator/Cargo.toml -- \
  --config bots/liquidator/config.local.toml \
  scan-once \
  --json \
  --out /path/to/evidence-dir/liquidator-scan-evidence.json
```

When `--out` is a directory path, the bot writes
`liquidator-scan-evidence.json` under that directory. The payload includes the
chain ID, generated block number, config hash, enabled branches, branch-level SP
offset capacity, top candidate, planned batch, gas estimate, and execution
decision. Each planned batch also includes `profitEvidence.status = "unsupported"`
until collateral-disposal routes, inventory-aware valuation, market depth, relay
policy, and RPC quorum are implemented. The nested
`profitEvidence.liquidatorGasCompensation` field is computed from the Core gas
compensation rules only; it is not a full liquidation PnL model. The nested
`profitEvidence.gasForecast` records the latest block base fee, the provider gas
price, the derived priority fee, and the stressed gas cost. Live submissions
bind the planned gas limit and gas price to the transaction so a later provider
fee refresh cannot silently raise the per-tx gas budget; it still does not model
private relay, replacement, cancellation, or bundle failure handling. The
top-level `rpcQuorum` evidence records primary/fallback provider health, chain
ID agreement, block lag, and read timeout without writing raw RPC URLs; the nested
`profitEvidence.rpcQuorum` remains partial until scanner routing, provider
voting, and price-source quorum are implemented. The nested
`profitEvidence.receipt` records the receipt timeout and supported live outcome
classifications, but remains `not-submitted` in dry-run evidence until
persistent disposal-aware PnL accounting exists. Live submissions append
`submitted` and `receipt-outcome` events to the JSONL receipt ledger when
`state.path` or `state.receipt_ledger_path` is configured, and append gas-only
PnL rows when `state.path` or `state.pnl_ledger_path` is configured. Gas-only
PnL rows record the receipt classification and a gas-cost upper bound from
`gasUsed * planned maxFeePerGas`; collateral gain, inventory cost, disposal
proceeds, effective gas price, and relay costs remain unsupported.

Receipt timeouts and submit-and-forget outcomes can be reconciled later with a
read-only RPC pass:

```sh
cargo run --manifest-path bots/liquidator/Cargo.toml -- \
  --config bots/liquidator/config.local.toml \
  reconcile-receipts \
  --min-age-ms 60000 \
  --fail-on-alert \
  --json
```

`reconcile-receipts` reads the configured receipt ledger, rechecks transaction
receipts, and uses recorded `txFrom` / `txNonce` metadata to detect replacement
candidates when the original hash still has no receipt. It appends only
confirmed-late or replacement-candidate evidence to the local JSONL ledger and
never submits, replaces, or cancels transactions. When a PnL ledger path is
configured, the same late or replacement outcome also appends a gas-only PnL
row. If that PnL append fails after the receipt outcome is written,
`reconcile-receipts` records a non-terminal `pnl-ledger-error` retry marker in
the receipt ledger and reports the entry as an alerting error. Use
`--pnl-ledger /path/to/pnl-ledger.jsonl` to override the configured path for
this reconciliation pass.
Use `--fail-on-alert` in cron or monitoring jobs to exit non-zero when default
operator alert classifications are observed: `confirmed-late-reverted`,
`confirmed-late-missing-status`, `confirmed-late-unknown-status`,
`replacement-candidate`, `pnl-ledger-error`, or reconciliation `error`. Repeat
`--alert-classification CLASS` to replace that default set for a specific
environment.

For mainnet launch evidence, `contracts/utils/mainnet-launch-operation-check.ts`
also requires the operator launch config to pin `maxGasCostWei`,
`maxLossWeiPerTx`, `gasCostStressMultiplierBps`,
`minSpOffsetCoverageBps`, `rpcQuorumRequired`, `rpcMaxBlockLag`,
`rpcReadTimeoutMs`, `receiptTimeoutSecs`, `maxSubmissionsPerCycle`,
`submissionCooldownBlocks`, `maxDryRunEvidenceAgeBlocks`, high-gas escalation
owner, JIT/top-up owner and funding source, SP-shortfall / redistribution
decision owners, collateral disposal owner, and failed-receipt escalation owner.
This is the
Black-Thursday-style readiness gate: a dry-run scan is not sufficient unless it
proves the current SP capacity, planned-batch stressed gas cost, and explicit
human decision path for thin-SP / high-gas conditions, and the scan evidence is
fresh against the current RPC block.

Set `execution.enabled = true`, `execution.dry_run = false`, and provide a
private key environment variable only after validating the read-only output on
the intended chain.

Read-only and dry-run modes do not load a signing key. Live mode fails fast
unless `execution.private_key_env` is set to a non-empty environment variable
name, that environment variable exists, the RPC `eth_chainId` equals
`chain.chain_id`, and the live policy has positive gas/loss caps. Live
`profit-seeking` is still rejected until collateral disposal and
inventory-aware profit modeling are implemented. The `run` daemon logs
transient RPC read / scan / planning failures, restores the pre-scan cursor, and
retries after `chain.poll_interval_ms` instead of relying on a supervisor
restart loop. Read-only RPC calls are bounded by `chain.rpc_read_timeout_ms`.

## Dependency Audit

Run the liquidator dependency audit through the wrapper:

```sh
./bots/liquidator/scripts/audit-deps.sh
```

The wrapper runs plain `cargo audit --file bots/liquidator/Cargo.lock` without
RustSec ignores. The liquidator provider/signing stack uses Alloy instead of
ethers-rs, so the previous
`ethers-providers -> jsonwebtoken -> ring 0.16.20` advisory path is no longer in
the bot dependency graph.

## Backend Mode

```sh
RUST_LOG=info \
cargo run --manifest-path bots/liquidator/Cargo.toml -- \
  --config bots/liquidator/config.local.toml \
  run
```

The `run` command polls the latest block. With `catcher.trigger = "new-block"`
it runs one catch cycle per block, persists `last_seen_block` and branch cursors
to `state.path`, and resumes from that cursor after restart.

`chain.rpc_read_timeout_ms` applies separately to the collateral registry read
and to each enabled branch scan. A slow branch therefore cannot consume one
aggregate timeout and prevent every later branch from being checked. A failed
branch scan also restores that branch's cursor before later branches continue.

State writes use a temporary file and atomic replace so a daemon restart is less
likely to leave a partially written cursor file.

Run only one live liquidator task per state path and signer. The AWS ECS service
uses a non-overlapping singleton rollout (`minimumHealthyPercent=0`,
`maximumPercent=100`) so old and new keepers cannot write the shared EFS state or
submit liquidations concurrently.

## Generate Config

Frontend addresses are generated from deployment artifacts. Use them as the bot
config source instead of hand-copying branch addresses:

```sh
pnpm -C contracts exec tsx ../bots/liquidator/scripts/config-from-df-shared.ts \
  > bots/liquidator/config.local.toml
```

Set `ENABLED_BRANCHES=0,1,...` to emit only selected generated branch IDs as
enabled. The generator rejects empty, duplicate, non-integer, or unknown branch
IDs so bad devnet input fails before a daemon starts. The generated config also
pins RPC quorum defaults and execution policy fields such as
`gas_cost_stress_multiplier_bps`, `min_sp_offset_coverage_bps`,
`max_submissions_per_cycle`, `submission_cooldown_blocks`, and
`receipt_timeout_secs`; review these before using the file outside local
dry-runs.

`contracts/utils/local-stack.sh` runs this after regenerating `df-shared`, so a
fresh local stack writes `bots/liquidator/config.local.toml` automatically.

Generated address files must include `liquidationCandidateGetter`; regenerate
from a current deployment manifest if it is missing.

## Local Anvil E2E

After starting Anvil and running `contracts/utils/local-stack.sh`, the local E2E
scripts exercise the live `scan-once` path against the seeded stack:

```sh
bots/liquidator/scripts/e2e-local-anvil.sh
bots/liquidator/scripts/e2e-local-anvil-race.sh
```

The normal E2E lowers the branch-0 collateral/USD feed, submits a liquidation,
and verifies `confirmed-success` in the receipt and gas-only PnL ledgers. The
race E2E pauses Anvil automining, lets the bot submit, sends a higher-gas-price
competitor liquidation for the same Troves, mines both transactions, and verifies
the bot records `confirmed-reverted` instead of losing the receipt/PnL trail.

## AWS Hosted Anvil E2E

The hosted staging E2E connects the existing frontend Open Borrow smoke to a
real liquidator submission while keeping the public review state unchanged:

```sh
HOSTED_LIQUIDATOR_E2E_CONFIRM=run-hosted-liquidator-e2e \
LIQUIDATOR_PRIVATE_KEY="$HOSTED_ANVIL_ONLY_SIGNER_KEY" \
  bots/liquidator/scripts/e2e-hosted-anvil.sh
```

The command is staging-only and branch-0-only. It resolves the RPC URL, ECS
cluster/service, and EventBridge rule names from CloudFormation outputs; refuses
to start unless the singleton liquidator is stable, every backend alarm is OK,
and every scheduled backend reader is enabled; acquires a no-overwrite SSM
execution lock; then stops those
workers before taking an Anvil snapshot. It
opens a second dwstETH Trove through the deployed frontend, lowers the collateral
feed, submits one liquidation, and verifies the scan evidence plus receipt/PnL
ledgers. The exit trap always reverts the snapshot, verifies the feed and Trove
count, confirms the temporary liquidation receipt disappeared, restores all
rules, and returns ECS to its original desired count.
The lock is released only when its value still matches the current run ID. A
leftover lock therefore blocks later runs until an operator verifies chain and
backend restoration before deleting it.

Evidence is written outside the repository under
`/private/tmp/jpydf-hosted-liquidator-e2e-<UTC timestamp>` by default. Override
that location with `HOSTED_LIQUIDATOR_E2E_OUT_DIR`. A successful transaction
hash in this evidence is intentionally no longer queryable after the snapshot
revert; `restoration.json` is the required proof that the public review state
was restored. Never point this script at mainnet or a value-bearing chain, and
never use a signer key that is valid outside the hosted Anvil test environment.

## Catch Model

- `LiquidationCandidateGetter` is the primary source of active Trove discovery.
- Because Liquity v2 zombie Troves are removed from `SortedTroves`, the bot calls
  `getLiquidationCandidatesWithLastZombie(..., includeLastZombie=true)` when
  `include_last_zombie = true`.
- Each catch cycle fetches the Liquity protocol price, branch MCR, shutdown time,
  JPY soft-freeze state, and Stability Pool deposits.
- Candidates are revalidated with `TroveManager.getCurrentICR` before planning.
- Batches are built per Liquity branch and estimated before any transaction is sent.
- Logs include SP offset capacity using the same `MIN_JPYDF_IN_SP` convention as
  `TroveManager.batchLiquidateTroves`.
- Scan logs include the current top candidate, minimum ICR, liquidation deficit,
  and how many verified candidates are individually covered by current SP
  offset capacity.
- Planned batch logs include the selected Trove IDs, SP-offset coverage bps, raw
  gas cost, and stressed gas cost.
- Launch evidence must include branch-level SP deposits / offset capacity /
  SP-covered candidate count and planned-batch gas / gas price / gas cost /
  stressed gas cost / execution decision, so the operator can prove high-gas and
  thin-SP behavior before public launch.
- JIT/backstop is outside the current bot. The bot does not buy JPYdf, call
  `provideToSP`, or bundle top-up with liquidation. It only surfaces the
  capacity and candidate data that an operator or future audited executor would
  use.
- `protocol-maintenance` mode treats stressed gas cost as an allowed operator
  expense within explicit per-tx caps until collateral disposal modeling is
  added.
- `gas_cost_stress_multiplier_bps` must be at least `10000` and is applied
  before `max_gas_cost_wei` / `max_loss_wei_per_tx`; dry-run uses the same
  policy ordering before returning `dry run`.
- `min_sp_offset_coverage_bps` defaults to `10000`. Lowering it means the
  operator has explicitly accepted partial SP offset and possible
  redistribution/JIT handling.
- `chain.rpc_read_timeout_ms` defaults to `15000` and bounds block-number,
  scan, chain-id, RPC health, and pre-submit planning reads so overloaded
  providers do not stall the daemon loop.
- `max_submissions_per_cycle` defaults to `1` so a high-gas window or candidate
  backlog cannot turn one catch cycle into an unbounded live tx burst.
- `submission_cooldown_blocks` defaults to `3`; after a live submission the
  daemon skips catch cycles for that many blocks to avoid immediate duplicate
  sends while replacement/cancellation tracking is still outside the bot.
- When `state.path` is set, both `run` and live `scan-once` persist
  `last_submission` after tx submission so the cooldown survives restarts and
  post-submit planning errors.
- Live `protocol-maintenance` requires positive `max_loss_wei_per_tx` and
  `max_gas_cost_wei`.
- Live `profit-seeking` is rejected until collateral disposal and
  inventory-aware profit modeling are implemented. Keep `mode =
  "protocol-maintenance"` for Day-1 live operation.
- Live submissions wait up to `execution.receipt_timeout_secs` for a receipt and
  log a structured classification (`confirmed-success`, `confirmed-reverted`,
  `receipt-missing`, `receipt-wait-error`, `receipt-timeout`, or
  `submit-and-forget`) with gas used and block number when available. Later
  `reconcile-receipts` checks may append `confirmed-late-*` or
  `replacement-candidate` outcomes. Set `receipt_timeout_secs` to `0` for
  submit-and-forget operation.
- Live submissions append JSONL receipt ledger events after tx hash assignment
  and after the receipt wait outcome. The submitted event includes a
  best-effort `txFrom` / `txNonce` / `txBlockNumber` lookup for later
  dropped-or-replaced reconciliation; lookup failure is recorded as metadata
  status and never triggers a resubmit. If `state.receipt_ledger_path` is
  unset, the daemon writes `receipt-ledger.jsonl` next to `state.path`.
- Live receipt outcomes also append gas-only JSONL PnL rows when
  `state.pnl_ledger_path` is set, or to `pnl-ledger.jsonl` next to `state.path`
  by default. If the receipt outcome is written but the PnL row fails, the bot
  appends a non-terminal `pnl-ledger-error` marker so `reconcile-receipts` can
  retry and `--fail-on-alert` can page operators. This is accounting scaffolding
  only: collateral gain recovery, inventory cost, disposal route proceeds, and
  full replacement/cancellation handling remain Day-2 profit-seeking work.
