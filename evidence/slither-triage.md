# Slither Triage

## Follow-up freeze triage — 2026-08-08

This section supersedes the historical July triage for current source freeze
`0a85b374015e2553d2985b4a3f454b6aee4514a5`. The execution record and raw
artifact identity are in
[`slither-audit-run.md`](./slither-audit-run.md).

### Current outcome

- Slither `0.11.5`: 187 contracts, 101 detectors, 1,439 results.
- Untriaged detector groups: 0.
- Confirmed source bugs from this rerun: 0.
- Source changes required before auditor handoff: 0.
- Independent adversarial scan: all 170 attack-vector prompts completed; four
  candidates reduced to three root causes, with no reportable finding after
  validation against the deployed implementation and Japanese source of truth.
- Retained auditor-attention item: a sufficiently large collateral/USD move
  while a Chainlink report is pending but not stale. This is an oracle-liveness
  and launch-parameter assumption, not a confirmed source defect from the
  submitted candidate.

The raw Slither JSON remains machine-local because it is 83,940,441 bytes. Its
SHA-256 is
`124d0e09cfb313ff5069c08ad9ac8e1b0d7cbc3b8fed28e9453d7fd38fe7c037`.

### Current detector counts

| Detector | Impact | Count | Disposition |
| --- | --- | ---: | --- |
| `arbitrary-send-erc20` | High | 2 | fixed GasPool allowance pattern |
| `arbitrary-send-eth` | High | 5 | fixed protocol integration targets |
| `reentrancy-balance` | High | 71 | guards, CEI, trusted endpoints, and balance-delta accounting |
| `divide-before-multiply` | Medium | 6 | inherited fixed-point math / display formatting |
| `incorrect-equality` | Medium | 74 | zero-work, sentinel, and exact-accounting checks |
| `reentrancy-no-eth` | Medium | 37 | guarded/trusted-call patterns and inherited hookless-token assumptions |
| `uninitialized-local` | Medium | 59 | intentional Solidity default-zero structs and counters |
| `unused-return` | Medium | 24 | intentional tuple components or separately validated effects |
| `calls-loop` | Low | 146 | bounded helper/core loops; gas review only |
| `missing-zero-check` | Low | 10 | cancellation/referral semantics or downstream validation |
| `reentrancy-benign` | Low | 62 | accepted call ordering; no conflicting state effect |
| `reentrancy-events` | Low | 80 | event-after-call ordering noise |
| `timestamp` | Low | 39 | protocol time, cooldown, and shutdown logic |
| `assembly` | Informational | 4 | audited helper implementations |
| `costly-loop` | Informational | 11 | bounded/inherited loops |
| `cyclomatic-complexity` | Informational | 5 | constructor/helper complexity |
| `dead-code` | Informational | 1 | no reachable production defect |
| `low-level-calls` | Informational | 1 | deliberate helper call with propagated failure |
| `missing-inheritance` | Informational | 1 | interface-inference noise |
| `naming-convention` | Informational | 714 | inherited/local naming noise |
| `too-many-digits` | Informational | 2 | readability only |
| `unimplemented-functions` | Informational | 2 | public mapping getter false positives |
| `unindexed-event-address` | Informational | 58 | event-query ergonomics only |
| `unused-state` | Informational | 8 | upgradeable storage gaps |
| `immutable-states` | Optimization | 17 | gas/style only; some storage-layout sensitive |

The High and Medium groups were reviewed at the reported function level. The
current Vault, Morpho, Sky, and wstETH/Zapper paths rely on role or reentrancy
guards plus post-call balance deltas and minimum-receipt checks. The remaining
core warnings are inherited CEI/hookless-token assumptions already called out
for auditor review below. No detector group was closed from count alone.

### Independent vector-scan reconciliation

The same 73-file production scope was supplied independently to four scanners,
covering vectors 1–42, 43–84, 85–126, and 127–170. Bundle SHA-256 values were:

| Vectors | Bundle SHA-256 |
| --- | --- |
| 1–42 | `79bcf343428bc627b6954e5ca67ebfaa3a8b407a2bba8689cea3c41a9123037f` |
| 43–84 | `cac51c25a9b34344df7f368e84f055cc64442ecc26357bcd04ad73d845deed53` |
| 85–126 | `8be3411ae2ab90f93e372a0f813d73bf7beb5ede7a52e0791797a5b3719144a9` |
| 127–170 | `4a71c69f184cb398cac25ced8538d314e89e52f37bef90f9ad37dec2dc7ce41d` |

Four formatted candidates reduced to these three root causes:

| Candidate | Disposition | Validation |
| --- | --- | --- |
| Same-block Stability Pool deposit → liquidation → withdrawal (reported twice) | False positive against the deployed surface | The scanners followed retained parity reference `StabilityPool.sol`; deployment instantiates `DFStabilityPool`, whose `lastDepositBlock` guard rejects same-block withdrawal. See `DeployLiquity2.s.sol:29,592,637`, `stabilityPool.t.sol:442`, and Japanese requirements `CORE-MOD-004`, `CORE-SP-FR-004`, and `CORE-SP-SEC-004`. |
| Trove NFT uses `_mint` instead of `_safeMint` | Explicit design; no involuntary victim-loss path | Japanese `CORE-TN-FR-002` specifies `_mint` to avoid an untrusted receiver callback, reentrancy, and receiver-refusal DoS during `openTrove`; non-receiver contracts may intentionally own Troves. The caller deliberately supplies the owner and collateral. |
| Pending adverse Chainlink update can be front-run | Not confirmed; retain as oracle/launch attention | The submission did not demonstrate a profitable price gap. For an account opened at MCR `m`, ignoring fees and liquidation costs, extracting more debt value than the post-update collateral requires `Pnew/Pold < 1/m`: a drop above about 18.82% for wstETH (`m = 1.2318`) or 10.38% for USDC (`m = 1.1158`). Exact non-JPY heartbeat/staleness and monitoring remain launch-gated parameters. A stalled-but-not-yet-stale move beyond this bound should be confirmed with the formal auditor, but no source change follows from the submitted scenario alone. |

The authoritative Japanese references are
[`Liquity-v2-Core-Spec.md`](../docs/jp/protocol/product/spec/Liquity-v2-Core-Spec.md)
and [`Parameters.md`](../docs/jp/Parameters.md). The wstETH MCR and feed
assumptions are independently recorded in
[`dwsteth-risk-parameter-derivation.md`](./wsteth-cycle/dwsteth-risk-parameter-derivation.md).

## Historical July triage

Status date: 2026-07-01

This document triages the Slither audit-config run recorded in
[`slither-audit-run.md`](./slither-audit-run.md).

## Scope

- Source commit: `693dff8a4b2eb96a2197b279804a1abc9837a8d9`
- Command context: `jpydf-v2/contracts`
- Config: [`config/slither-audit.config.json`](../config/slither-audit.config.json)
- Result: Slither completed Foundry compilation and reported 1256 results.
- Raw-output sha256:
  `ba892eeafd6cf91f2caa3e7f4f90ae17c415deda69f83119ee07eb036330d0fb`
- Tree note: the freeze commit changes documentation entrypoints after
  verification commit `93cdd67881447273e04f2521a60e03819dbb3ac5`; Solidity
  implementation files, tests, scripts, and build inputs are unchanged, so the
  Slither result remains applicable to the final Solidity source.

The raw Slither output is intentionally not committed. The committed audit
evidence is this reviewed detector-level triage.

## Triage Outcome

- Untriaged detector groups: 0.
- Confirmed source bugs from this Slither run: 0.
- Source followups resolved before this handoff freeze:
  `ITroveManager` ABI return-name typo, metadata utility pragma drift,
  CollateralVault allocation read-only reentry coverage, and JP/EN scope/spec
  synchronization.
- Accepted/design-noise groups: listed in the detector table and accepted
  findings below.
- Auditor-attention items: 4, listed in the dedicated section below.

## Detector Counts

| Detector | Count | Triage |
| --- | ---: | --- |
| `arbitrary-from-in-transferfrom` | 2 | accepted GasPool pattern |
| `functions-that-send-ether-to-arbitrary-destinations` | 4 | fixed-protocol ETH/WETH paths |
| `divide-before-multiply` | 6 | accepted math / metadata formatting |
| `dangerous-strict-equalities` | 58 | zero guards, sentinels, exact accounting |
| `reentrancy-vulnerabilities-1` | 28 | accepted core/SP patterns; auditor attention |
| `uninitialized-local-variables` | 59 | Solidity default-zero local structs/values |
| `unused-return` | 15 | intentional tuple discard / checked deltas |
| `missing-zero-address-validation` | 10 | mostly intentional cancellation/referral semantics |
| `calls-inside-a-loop` | 43 | bounded helper/core loops; gas review only |
| `reentrancy-vulnerabilities-2` | 50 | accepted trusted-call patterns; auditor attention |
| `reentrancy-vulnerabilities-3` | 64 | event-after-call noise; auditor attention |
| `block-timestamp` | 38 | protocol time/cooldown/shutdown logic |
| `assembly-usage` | 4 | Solady/JSON/min-gas/bubble helpers |
| `different-pragma-directives-are-used` | 7 pragma groups | dependency/interface variance |
| `costly-operations-inside-a-loop` | 10 | bounded loops / inherited redemption logic |
| `cyclomatic-complexity` | 4 | constructor/helper complexity, no direct finding |
| `incorrect-versions-of-solidity` | 7 pragma groups | dependency/interface pragma noise; source builds with 0.8.24 |
| `conformance-to-solidity-naming-conventions` | 673 | inherited/local style noise |
| `variable-names-too-similar` | 152 | mostly domain naming; ABI typo followup resolved |
| `too-many-digits` | 2 | inherited `525600000` cap readability |
| `unimplemented-functions` | 2 | public mapping getter false positives |
| `unused-state-variable` | 7 | upgradeable storage gaps |
| `state-variables-that-could-be-declared-immutable` | 17 | gas/style only |

## Accepted Findings

### GasPool `transferFrom`

Slither flags the gas compensation paths because `BorrowerOperations` and
`TroveManager` pull WETH from `gasPoolAddress`:

- `source-snapshot/contracts/src/BorrowerOperations.sol:741`
- `source-snapshot/contracts/src/TroveManager.sol:544`

This is an accepted design pattern, not arbitrary user fund movement. The
`GasPool` constructor gives WETH allowance only to the configured
`BorrowerOperations` and `TroveManager`:

- `source-snapshot/contracts/src/GasPool.sol:22`
- `source-snapshot/contracts/src/GasPool.sol:28`
- `source-snapshot/contracts/src/GasPool.sol:30`

Tests cover the boundary:

- `source-snapshot/contracts/test/GasPool.t.sol:54`
- `source-snapshot/contracts/test/GasPool.t.sol:62`
- `source-snapshot/contracts/test/GasPool.t.sol:74`

### ETH-Sending Strategy Paths

The Lido and Etherfi ETH-value calls are to fixed protocol contracts or WETH,
not arbitrary user recipients:

- `source-snapshot/contracts/src/Strategies/LidoStrategy.sol:203`
- `source-snapshot/contracts/src/Strategies/LidoStrategy.sol:266`
- `source-snapshot/contracts/src/Strategies/EtherfiWeETHStrategy.sol:194`
- `source-snapshot/contracts/src/Strategies/EtherfiWeETHStrategy.sol:242`

The Strategy entry points are guarded with `nonReentrantStrategy`, and protocol
addresses are fixed during initialization:

- `source-snapshot/contracts/src/Strategies/BaseStrategy.sol:134`
- `source-snapshot/contracts/src/Strategies/LidoStrategy.sol:128`
- `source-snapshot/contracts/src/Strategies/EtherfiWeETHStrategy.sol:120`

Raw ETH donation is not counted as Strategy principal; only claim/deposit
balance deltas are accounted.

### Strict Equality

The strict-equality warnings are not price equality or oracle-threshold checks.
They are zero-work exits, sentinel checks, exact ID checks, or exact
token/share accounting guards. Representative examples:

- Vault zero and allocation guards:
  `source-snapshot/contracts/src/CollateralVault.sol:258`,
  `source-snapshot/contracts/src/CollateralVault.sol:373`,
  `source-snapshot/contracts/src/CollateralVault.sol:432`,
  `source-snapshot/contracts/src/CollateralVault.sol:1104`,
  `source-snapshot/contracts/src/CollateralVault.sol:1220`
- Strategy fail-closed accounting:
  `source-snapshot/contracts/src/Strategies/BaseStrategy.sol:292`,
  `source-snapshot/contracts/src/Strategies/AaveV3Strategy.sol:223`,
  `source-snapshot/contracts/src/Strategies/ERC4626Strategy.sol:83`,
  `source-snapshot/contracts/src/Strategies/LidoStrategy.sol:280`,
  `source-snapshot/contracts/src/Strategies/EtherfiWeETHStrategy.sol:252`,
  `source-snapshot/contracts/src/Strategies/SkyUsdcSUsdsStrategy.sol:336`
- Core shutdown/sentinel checks:
  `source-snapshot/contracts/src/TroveManager.sol:1167`,
  `source-snapshot/contracts/src/TroveManager.sol:1201`,
  `source-snapshot/contracts/src/TroveManager.sol:1511`

### Divide Before Multiply

The metadata findings are display-only:

- `source-snapshot/contracts/src/NFTMetadata/utils/JSON.sol:76`
- `source-snapshot/contracts/src/NFTMetadata/utils/Utils.sol:42`
- `source-snapshot/contracts/src/NFTMetadata/utils/Utils.sol:45`
- `source-snapshot/contracts/src/NFTMetadata/utils/Utils.sol:47`

The TroveManager findings are inherited fixed-point formulas:

- `source-snapshot/contracts/src/TroveManager.sol:692`
- `source-snapshot/contracts/src/TroveManager.sol:694`
- `source-snapshot/contracts/src/TroveManager.sol:1116`
- `source-snapshot/contracts/src/TroveManager.sol:1120`

Redistribution uses explicit floor-division error feedback immediately above the
flagged lines, so the remainder is tracked rather than silently discarded.

### Missing Zero Address

Most zero-address warnings are intentional semantics:

- `DToken.transferOwnership(0)` cancels a pending transfer:
  `source-snapshot/contracts/src/DToken.sol:214`
- `InterestRouterForwarder.transferOwnership(0)` cancels a pending transfer:
  `source-snapshot/contracts/src/InterestRouterForwarder.sol:68`
- `PILAllocator.transferOwnership(0)` cancels a pending transfer:
  `source-snapshot/contracts/src/PILAllocator.sol:208`
- `BaseStrategy.transferOwnership(0)` mirrors the same two-step cancellation
  behavior: `source-snapshot/contracts/src/Strategies/BaseStrategy.sol:218`
- Lido/Etherfi referral can intentionally be zero:
  `source-snapshot/contracts/src/Strategies/LidoStrategy.sol:234`,
  `source-snapshot/contracts/src/Strategies/EtherfiWeETHStrategy.sol:229`

The `JpydfToken.setCollateralRegistry` warning is a false positive:
`_requireCoreContract` rejects zero and codeless addresses:

- `source-snapshot/contracts/src/JpydfToken.sol:92`
- `source-snapshot/contracts/src/JpydfToken.sol:296`

### Unimplemented Functions

Both findings are public mapping getter false positives:

- `ICollateralVault.strategyValuationCaches(IStrategy)` is implemented by the
  public mapping at `source-snapshot/contracts/src/CollateralVault.sol:106`.
- `ISortedTroves.batches(BatchId)` is implemented by the public mapping at
  `source-snapshot/contracts/src/SortedTroves.sol:78`.

### Storage Gaps And Immutable Suggestions

The `__gap` warnings are accepted upgradeability storage reservations in the
Vault, dToken, and Strategy proxies. They should remain unused by design until a
separately reviewed storage layout expansion.

The immutable suggestions are gas/style only. Several flagged variables are in
inherited Liquity core contracts or storage-layout-sensitive components. Do not
change them during audit handoff unless a scoped source PR re-freezes the
package and re-runs build/tests.

## Auditor Attention

These are not confirmed bugs, but they are worth explicit review by auditors.

1. `CollateralVault.allocate()` has a transient read-only observation window
   while `underlying.safeTransfer(strategy, amount)` and `strategy.deposit(...)`
   run before the strategy valuation cache is refreshed:
   `source-snapshot/contracts/src/CollateralVault.sol:369`,
   `source-snapshot/contracts/src/CollateralVault.sol:1240`,
   `source-snapshot/contracts/src/CollateralVault.sol:1243`,
   `source-snapshot/contracts/src/CollateralVault.sol:1244`.
   The path is `onlyRole(ALLOCATOR_ROLE)` and `nonReentrant`; auditors should
   still confirm that read-only reentrancy into `totalUnderlying()`,
   `backingRatio()`, and strategy status views cannot create an exploitable
   overvaluation. The freeze commit adds
   `test_Allocate_ReadOnlyReentryDuringDepositCannotInflateVaultViews` to cover
   conservative read-only observation and state-mutating reentry rejection.

2. Liquity core does not use `nonReentrant`; it relies on CEI, caller
   restrictions, and hookless tokens. This assumption is documented in the
   Japanese source of truth:
   `docs/jp-source-of-truth/spec/Liquity-v2-Core-Spec.md:260` and
   `docs/jp-source-of-truth/spec/Liquity-v2-Core-Spec.md:273`.
   Auditors should confirm that all configured production `collToken`, WETH, and
   JPYdf paths remain hookless and that any token with callbacks is out of scope
   unless separately reviewed.

3. `TroveManager.urgentRedemption` sends collateral before burning JPYdf:
   `source-snapshot/contracts/src/TroveManager.sol:936` and
   `source-snapshot/contracts/src/TroveManager.sol:938`. This is acceptable
   under the hookless-collateral assumption above, but it should remain an
   auditor-reviewed invariant.

4. Strategy adapters rely on fixed upstream venue contracts and balance-delta
   accounting. New ERC4626/Morpho/Sky/Lido/Etherfi venues must not be registered
   or allocated to without a venue-specific activation package proving decimals,
   fee-on-transfer/rebasing/blacklist behavior, oracle/curator/queue evidence,
   and loss/writeoff handling.

## Resolved Source Followups

- `source-snapshot/contracts/src/Interfaces/ITroveManager.sol:64` now names the
  selector-neutral return value `_redeemedAmount`, matching
  `source-snapshot/contracts/src/TroveManager.sol:760` and generated ABI
  output expectations.
- `docs/jp-source-of-truth/spec/CollateralVault.md` and
  `docs/en/spec/CollateralVault.md` now include `allocate()` in
  `VAULT-SEC-001`, and the source snapshot includes the corresponding
  allocation read-only reentry regression test.
