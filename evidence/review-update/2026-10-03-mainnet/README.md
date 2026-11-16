# Mainnet deployment source — Review Update request, October 3, 2026

This package supplies the exact production Solidity source used for both the September 29 token deployment and the September 30 protocol deployment. The planned public launch is **October 15, 2026**. It is a new Review Update request; it does not replace the historical SOW or claim Guardian acceptance.

## Exact identities

- Deployment source commit (implementation repository): `e26b2088546c68a84ff84375aa5fd8d638f47eb7`.
- Deployed source `contracts/src` tree: `e44ff296fa1fa4a6929e047b548a6d17b490bd47`.
- Guardian baseline source commit: `6add59dfe50dbfe871802a29c8653e0b09fa9ca2`, tree `4d461638a27fccd2f749f7086ec955985d04c2a0`.
- Historical audit repository package: `5723a6d76279ec13c7cd57e081faf8493db34f15`.
- Latest release observed for this handoff: `539332e0c3e88986d6901a153c554bb99f549b73`. Its production source tree is identical to the deployment source. This later release SHA is not presented as the deployment commit.

The commit containing this package is the **audit repository handoff commit**, a separate identity from the deployment commit. Auditor access to the private implementation repository is not required to read the source or verify the patch.

## Files and requested review

[Complete source snapshot](source/contracts/src), [complete differential](guardian-to-deployed.patch), [per-file line counts](delta-numstat.txt), [identity](identity.json), and [deployment wiring](deployment-manifest.json) are provided together. The differential is **9 files, +169/−23**; these are ordinary Git line counts, not an nSLOC estimate.

The changes include:

1. Round 2 L-01: independently budget each Strategy valuation probe, rethrow the gas-guard error through JpyFreezeLib, and allow governance to set the valuation probe budget. See the historical [Round 2 handoff](../../../docs/audit/GUARDIAN_ROUND2_UPDATE.md).
2. Round 2 L-02: reserve Merkl incentives until atomic campaign creation, rather than transfer funding before a campaign can be created.
3. Three additional launch changes: dwstETH redistribution penalty 10% → 20%; split Treasury transfer, withdrawal and harvesting authorization into operation-specific roles; add a test-only token name/symbol constructor flag (production uses `false`).

The earlier September 24 handoff remains historical evidence. Inclusion here does not assert that every change has already been reviewed. Please confirm the accepted Review Update boundary, estimate, and treatment of the earlier Round 2 fixes.

## Mainnet and operational context

Ethereum mainnet, chain ID `1`:

- JPYdf Stablecoin / JPYdf: [`0xB122f4A154f84708407213D6A715181180012f45`](https://etherscan.io/address/0xB122f4A154f84708407213D6A715181180012f45).
- Token deployment: [`0x8577410f6f7a6308ee1334de3cd6fcd5c9813ab0f5cf5a0020d60a040a9822ed`](https://etherscan.io/tx/0x8577410f6f7a6308ee1334de3cd6fcd5c9813ab0f5cf5a0020d60a040a9822ed), block `26081524`.
- Timelock: [`0xf27de84F11E089B838769EDFcFf9872BC45c84Fe`](https://etherscan.io/address/0xf27de84F11E089B838769EDFcFf9872BC45c84Fe), 12-hour delay.
- Protocol deployment receipt verification recorded 215 successful finalized receipts, blocks `26088848`–`26089085`. This is transaction/finality evidence, not source/runtime equality.
- Deployment manifest lists all eight branches, Vaults, Strategies, feeds and helper addresses. Day 1 uses dwstETH and dUSDC; later branches remain inactive. Cap changes, governance handover and liquidity activation are separate operations; the manifest is deployment-time wiring and does not certify their current state.

The user intends to open caps for pre-launch real-fund tests. Contract access can therefore precede public website launch. Contest setup and urgent reporting should account for that exposure. A requested 30-day Critical Defender Contest followed by the Post-Launch Bug Bounty is subject to Guardian confirming scope and dates.

## Verification and build context

Run from this audit checkout:

```sh
python3 evidence/review-update/2026-10-03-mainnet/verify.py
```

The check verifies every exported file hash, reconstructs the deployed source by applying the complete patch to this repository's baseline snapshot, and verifies the resulting source Git tree. Dependencies were initialized recursively in a detached deployment-source checkout before export; no `.git`, environment files, private keys, wallet data or raw broadcast logs are exported.

Build inputs are copied verbatim in `source/contracts/`. Dependency revisions, including recursive dependencies, are recorded in [dependency-pins.txt](dependency-pins.txt). Public dependency retrieval follows the existing [build guide](../../../docs/audit/BUILD_AND_TEST.md); initialize the recorded dependencies under this package's `source/contracts/lib`, and fail if any required dependency is empty before running Forge. Both a fresh detached deployment-source build and an independent build of only this exported source with the pinned dependencies (`forge build --skip test --skip script`) completed with Solc 0.8.24; compiler/lint warnings remain. This does not constitute an audit or on-chain bytecode comparison. After retrieving the pinned public dependencies through that guide, an isolated build of this new source uses:

```sh
cp -R source-snapshot/contracts/lib evidence/review-update/2026-10-03-mainnet/source/contracts/lib
forge build --root evidence/review-update/2026-10-03-mainnet/source/contracts --skip test --skip script
```

Do not copy the old snapshot's source, tests or deployment scripts into the new package. The source snapshot intentionally contains production source and build inputs only; tests and deployment scripts are not proposed as audited production Solidity.

Source identity does not prove compiler-input, creation-bytecode or runtime-bytecode equality on mainnet. This handoff does not claim explorer source verification or an on-chain bytecode comparison, and does not expand the original SOW without Guardian agreeing to the new boundary.

Exact upstream whitespace is preserved in the source and patch. Whitespace checks on those immutable copies may report inherited trailing whitespace; do not normalize it, as that changes source identity. Newly authored handoff prose and JSON are checked separately.
