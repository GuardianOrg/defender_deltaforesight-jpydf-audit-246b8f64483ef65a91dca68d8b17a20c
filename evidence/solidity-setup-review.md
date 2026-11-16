# Solidity Setup Review

Status date: 2026-08-08

## 2026-08-08 wstETH / Morpho pre-audit freeze

- Source branch: `fix/preaudit-morpho-pricing-rails`; merged into `develop` by
  jpydf-v2 PR #1491 as merge commit `469b1265`.
- Source identity: `0a85b374015e2553d2985b4a3f454b6aee4514a5`.
- Current scope: the four pricing / withdrawal / incident-rail / minimum-receipt
  decisions plus fee-on-transfer receipt and cache variants, Sky reverse-quote
  availability, synchronized JP/EN requirements, and regression tests.
- Updated `contracts/src` nSLOC: 13,266 total (12,054 active + 1,212 archive);
  full-review body: 5,219. Normalized cloc CSV-body SHA-256:
  `22346dad9249af91af7639ab26da8db4f6031f6f2f45c2578b043f7f698cf49b`.
- Passed affected suites: 253 / 0 / 0 (Vault 57, VaultStrategy 124, Zapper 45,
  Sky Strategy 16, Sky Converter 11).
- Passed standard Foundry gate: 1,536 / 0 / 0 across 81 suites.
- Passed full local Foundry gate: 1,589 / 0 / 0 across 89 suites.
- PR #1491 remote Foundry, DF deploy wiring, Console, timelock E2E, and
  Liquidator bot checks passed. Frontend dependency audit failed on two current
  `nanoid` High advisories; the PR changed no package manifest or lockfile, so
  the dependency failure is recorded rather than hidden or repaired in this
  Solidity-scope change.
- Production `CollateralVault` runtime: 23,047 / 24,576 bytes, leaving 1,529
  bytes. `forge build --sizes` compiles successfully but exits nonzero when it
  includes the test-only `BorrowerOperationsTester` / `TroveManagerTester`
  artifacts because those fixtures exceed EIP-170.
- Foundry: 1.7.1; compiler: Solc 0.8.24; cloc: 2.06; submodule status hash:
  `4e4534c9de7e3250cb59e8bb4a27dc20c2a15d625cb510d28dea55132f889c2a`.
- Multi-skill review, follow-up findings, Chain Defenders PDF reconciliation,
  and limitations are recorded in
  [`wsteth-cycle/pre-audit-multi-skill-review-2026-08-08.md`](./wsteth-cycle/pre-audit-multi-skill-review-2026-08-08.md).
- Audit-config Slither `0.11.5` analyzed 187 contracts with 101 detectors and
  1,439 results. Detector-level review and an independent 170-vector
  adversarial scan found no confirmed source bug requiring a pre-handoff source
  change. The raw JSON SHA-256 is
  `124d0e09cfb313ff5069c08ad9ac8e1b0d7cbc3b8fed28e9453d7fd38fe7c037`.
- The committed audit snapshot was reconstructed with public dependencies only:
  production build passed and the standard Foundry gate passed 1,536 / 0 / 0
  across 81 suites. Auditor access to `jpydf-v2` is not required.
- Earlier results below remain historical evidence for their stated identities.

## 2026-07-14 Sky USDC/USDS Converter Scope Delta

- Source branch: `codex/sky-usdc-usds-converter`.
- Source identity: `dab4dbe5251f980a3af347cba20351513b026e7b` (merged by jpydf-v2 PR #1052 as `60e6e0a84bc3355ff39509515dfa5d965e37ae63`).
- Added production source: `contracts/src/Strategies/SkyUsdcSUsdsConverter.sol` and `contracts/src/Interfaces/ISkyUsdcSUsdsConverter.sol`.
- Updated integration: Sky Strategy, Sky Zapper interface binding, and concrete deployment from the configured LitePSMWrapper.
- Updated `contracts/src` nSLOC: `12,656`; normalized cloc CSV-body sha256: `48517fbc37bec29afa0ddd8d706ddd263b4e643c56b2063a50b0a23f7b355b59`.
- Passed focused verification: converter 11 tests (9 unit + 2 Ethereum mainnet fork), Sky Strategy 13, CollateralYieldZapper 31, and deploy selector 32. The fork confirmed official wrapper/token identity and executed USDC -> USDS -> USDC.
- `forge build --offline`, targeted `forge fmt --check`, and `git diff --check` passed.
- PR #1052 checks passed at implementation commit `eed3edfa`. Actions run `29349413077` against `b789c6bd` passed full local and mainnet Foundry, deploy wiring, parity drill, handover, and console checks.
- The final handoff head adds a fail-closed mainnet evidence guard: selected evidence jobs now fail explicitly when `MAINNET_RPC_URL` is unavailable.
- Audit-config Slither 0.10.2 analyzed 178 contracts with 95 detectors. Converter output was limited to informational naming/similar-name findings; no substantive converter finding remained after triage.
- Foundry coverage instrumentation cannot currently compile the inherited full test tree because of stack/Yul depth limits. Coverage remains visible but non-blocking; required full local and mainnet Foundry jobs are independent. Follow-up: jpydf-v2 issue #1053.

## 2026-07-07 Etherfi Adapter Identity Marker Delta

- Source branch: `develop`.
- Source identity: `7fe9ec026dc53c0d5b6e26665580de42baec8778` (jpydf-v2 PR #915).
- Added production source: `contracts/src/Strategies/WeETHWithdrawAdapter.sol`.
- Updated source snapshot files: Etherfi strategy, first-party adapter, focused Etherfi / deploy selector tests, and JP/EN scope / ledger / strategy docs.
- Updated `contracts/src` nSLOC: `12,466`; normalized cloc CSV-body sha256: `3f00962a63971b1e2586aa7972f9f80a034e204c258fa09d76f761504e04125c`.
- Passed focused verification: `forge test --match-path test/EtherfiWeETHStrategy.t.sol -vv` (34 tests), `forge test --match-path test/DeployLiquity2StrategySelector.t.sol -vv` (32 tests), `forge build --skip test`, targeted `forge fmt --check`, and `git diff --check`. The focused Etherfi suite covers adapter venue graph, LiquidityPool reverse-binding, residual weETH/eETH, Strategy-side adapter binding before approval, and rejection of marker-less ABI-compatible adapters.
- GitHub PR #915 checks passed: Foundry tests, DF deploy wiring, console imports, Core JPYDF surface check, and Liquidator bot tests.
- Full local Foundry and Slither evidence below remain from the previous 2026-07-01 clean freeze and should be refreshed if the SOW requires a static-analysis rerun for this adapter identity marker delta.


## Source Freeze

- Implementation repository: `https://github.com/deltaforesight/jpydf-v2`
- Freeze branch: `develop`
- Freeze commit: `693dff8a4b2eb96a2197b279804a1abc9837a8d9`
- Local source checkout status at review time: clean source checkout. The
  verification runs were executed on source commit
  `93cdd67881447273e04f2521a60e03819dbb3ac5`. The final freeze commit only
  changes documentation entrypoints after that verification commit; Solidity
  implementation files, tests, scripts, and build inputs are unchanged.
- Foundry version at review time:
  `forge Version: 1.2.3-nightly`
  (`109f2645ecd650fe0811945691ffa92bdf395213`,
  build timestamp `2025-07-09T06:05:29.484850000Z`).
- Compiler observed during the current local Foundry run: Solc `0.8.24`
  through Foundry auto-detection from source pragmas.
- `cloc --version`: `2.06`.
- `cloc --by-file --csv --quiet --include-lang=Solidity contracts/src`
  normalized CSV-body sha256 (`tail -n +2`):
  `9ff1f5322550006ecda0ef88889d46b5e5fe6d31827af498cdcdeff0e95c2295`.
- `git submodule status --recursive` output sha256:
  `4e4534c9de7e3250cb59e8bb4a27dc20c2a15d625cb510d28dea55132f889c2a`.

Submodule status:

```text
362b2efd20f38aea7252b391e5e016633ff79641 contracts/lib/Solady (v0.0.243)
b880481d701d2b07236f2e04842c79b4fe77e5fd contracts/lib/V2-gov (audit-chainsecurity-v2-326-gb880481)
d5cf52bc5bbf75f988f8aada23fd12d0bcf7798a contracts/lib/V2-gov/lib/chimera (0.1.3)
f73c73d2018eb6a111f35e4dae7b4f27401e9421 contracts/lib/V2-gov/lib/chimera/lib/forge-std (v1.7.1)
e282159d5170298eb2455a6c05280ab5a73a4ef0 contracts/lib/V2-gov/lib/chimera/lib/forge-std/lib/ds-test (heads/master)
2b59872eee0b8088ddcade39fe8c041e17bb79c0 contracts/lib/V2-gov/lib/forge-std (v1.9.4-3-g2b59872)
dbb6104ce834628e473d2173bbc9d47f81a9eec3 contracts/lib/V2-gov/lib/openzeppelin-contracts (v5.0.0-12-gdbb6104c)
8b1d7c2ac248c33c3506b1bff8321758943c5e11 contracts/lib/V2-gov/lib/openzeppelin-contracts/lib/erc4626-tests (v0.1.0)
eb980e1d4f0e8173ec27da77297ae411840c8ccb contracts/lib/V2-gov/lib/openzeppelin-contracts/lib/forge-std (v1.2.0)
cd98eff28324bfac652e63a239a60632a761790b contracts/lib/V2-gov/lib/openzeppelin-contracts/lib/forge-std/lib/ds-test (remotes/origin/windows-compat-17-gcd98eff)
726a6ee5fc8427a0013d6f624e486c9130c0e336 contracts/lib/forge-std (v1.9.5-2-g726a6ee)
bd325d56b4c62c9c5c1aff048c37c6bb18ac0290 contracts/lib/openzeppelin-contracts (v4.9.5)
8b1d7c2ac248c33c3506b1bff8321758943c5e11 contracts/lib/openzeppelin-contracts/lib/erc4626-tests (v0.1.0)
c2236853aadb8e2d9909bbecdc490099519b70a4 contracts/lib/openzeppelin-contracts/lib/forge-std (v1.5.0)
6da7dd8f7395f83e1fb6fa88a64ba9a030f85d4f contracts/lib/openzeppelin-contracts/lib/forge-std/lib/ds-test (remotes/origin/windows-compat-26-g6da7dd8)
2d081f24cac1a867f6f73d512f2022e1fa987854 contracts/lib/openzeppelin-contracts-upgradeable (v4.9.6)
8b1d7c2ac248c33c3506b1bff8321758943c5e11 contracts/lib/openzeppelin-contracts-upgradeable/lib/erc4626-tests (v0.1.0)
c2236853aadb8e2d9909bbecdc490099519b70a4 contracts/lib/openzeppelin-contracts-upgradeable/lib/forge-std (v1.5.0)
6da7dd8f7395f83e1fb6fa88a64ba9a030f85d4f contracts/lib/openzeppelin-contracts-upgradeable/lib/forge-std/lib/ds-test (remotes/origin/windows-compat-26-g6da7dd8)
```

## Snapshot Linkage

The audit repository includes a curated Solidity review snapshot at:

- `source-snapshot/contracts/`

The snapshot is for source review and navigation. Reproducible build and test
commands must use a full checkout created by:

- `scripts/checkout-source.sh`

That checkout initializes the implementation repository and submodules at the
recorded freeze commit.

The snapshot includes:

- `contracts/src/`
- `contracts/script/`
- `contracts/test/`
- `contracts/certora/`, with generated Certora report `anonymousKey` query
  strings removed from comments
- `contracts/README.md`, `foundry.toml`, `remappings.txt`,
  `slither.config.json`, `package.json`, and `requirements.txt`

The snapshot intentionally excludes:

- `contracts/lib/`
- `contracts/out/`
- `contracts/cache/`
- `contracts/broadcast/`
- deployment manifests
- `.env` files and local credential material
- `contracts/script/SeedLocalDemo.s.sol`

`SeedLocalDemo.s.sol` is excluded because it contains a public Anvil test
private key literal and is not required for audit source review.

## Reconciliation Checks

The copied snapshot was compared against the freeze checkout.

Passed:

```sh
diff -qr contracts/src <audit-repo>/source-snapshot/contracts/src
diff -qr contracts/test <audit-repo>/source-snapshot/contracts/test
```

For `contracts/script`, the only allowed difference was the documented exclusion
of `SeedLocalDemo.s.sol`.

Passed with only the allowed exclusion:

```sh
diff -qr contracts/script <audit-repo>/source-snapshot/contracts/script \
  | awk '$0 != "Only in contracts/script: SeedLocalDemo.s.sol" { print; bad=1 } END { exit bad }'
```

For `contracts/certora`, the snapshot intentionally differs only by stripping
generated external report `anonymousKey` query strings from comments. The audit
snapshot check is:

```sh
rg -n "anonymousKey=" <audit-repo>/source-snapshot/contracts/certora
```

Result: no output.

## Build Evidence

Command:

```sh
forge build \
  --root contracts \
  --out <tmpdir>/jpydf-v2-forge-out-ci-build-93cdd678 \
  --cache-path <tmpdir>/jpydf-v2-forge-cache-ci-build-93cdd678 \
  --sizes \
  --skip test \
  --skip scripts
```

Result: passed. Foundry emitted lint notes, but the build exited successfully.

Reference deploy / handover script compile command:

```sh
forge build \
  --root contracts \
  --out <tmpdir>/jpydf-v2-forge-out-script-build-93cdd678 \
  --cache-path <tmpdir>/jpydf-v2-forge-cache-script-build-93cdd678 \
  --sizes \
  --skip test
```

Result: passed. This confirms the deployment reference scripts compile; they
remain outside Solidity audit scope and implementation nSLOC unless deployment
ceremony / execution is separately scoped.

## Standard Foundry Gate Evidence

Command (run from `jpydf-v2/contracts`):

```sh
forge test \
  --match-contract CollateralVaultStrategyTest

forge test \
  --no-match-contract 'Mainnet|Invariant|Anchored|Initiative|LocalParityDrill'
```

Result: passed.

Focused `CollateralVaultStrategyTest` summary:

```text
Ran 1 test suite in 160.87ms (22.23ms CPU time):
114 tests passed, 0 failed, 0 skipped (114 total tests)
```

Standard gate summary:

```text
Ran 63 test suites in 12.42s (41.11s CPU time):
1331 tests passed, 0 failed, 0 skipped (1331 total tests)
```

## Full Local Foundry Gate Evidence

Command:

```sh
forge test \
  --root contracts \
  --out <tmpdir>/jpydf-v2-forge-out-full-local-93cdd678 \
  --cache-path <tmpdir>/jpydf-v2-forge-cache-full-local-93cdd678 \
  --no-match-contract 'Mainnet|LocalParityDrill'
```

Result: passed.

Summary:

```text
Ran 69 test suites in 98.18s (333.07s CPU time):
1370 tests passed, 0 failed, 0 skipped (1370 total tests)
```

## Hygiene Notes

`git diff --check` was run for audit handoff documents touched in this review.
It was not used as a whole-snapshot gate because the copied Solidity and
Certora source preserves upstream formatting exactly, including existing
trailing whitespace in some source files. Audit handoff docs should stay clean;
source files should stay byte-for-byte aligned with the freeze commit unless the
implementation repository changes.

Secret-pattern scans over the audit repository had no findings for mnemonic,
RPC, Etherscan, AWS, Slack, or GitHub token patterns after excluding the local
demo seed script from the snapshot. Public deterministic Hardhat test private
keys in `contracts/test/TestContracts/Accounts.sol` are intentionally included
as source-test fixtures and documented in `secret-hygiene.md`.
