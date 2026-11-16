# JPYdf V2 External Audit Package

This repository contains the production Solidity differential and the English
supporting material needed for the additional audit. Access to the private
implementation repository is not required.

## Remediation review

[September 24 Round 2 update](./docs/audit/GUARDIAN_ROUND2_UPDATE.md): the Strategy gas-starvation fix is merged upstream and the Merkl funding fix is merged upstream; both are supplied as reviewable patches. Guardian re-review is pending for both.

[Guardian findings and remediation tracking](./docs/audit/GUARDIAN_REMEDIATION.md) records all 19 findings, merged PRs, four conditional non-code dispositions, Fable reviews, and the tested September 10 Oracle policy candidate. Use [remediation commit `1aeafc3`](https://github.com/deltaforesight/jpydf-audit/commit/1aeafc3d92af624eb994958d65ff902587ec445b) for the consolidated fixes. Original source/artifact identities below remain the audited baseline.

## Start here

1. [`SCOPE.md`](./SCOPE.md) — authoritative statement of work, exact review
   boundary, required unchanged context, non-scope, size, and requested schedule.
2. [Audit PR #107 — Files changed](https://github.com/deltaforesight/jpydf-audit/pull/107/files)
   — canonical complete Solidity differential.
3. [`KNOWN_RISKS_AND_CURRENT_POSITION.md`](./docs/audit/KNOWN_RISKS_AND_CURRENT_POSITION.md)
   — known risks and the project's current position. Guardian may report any
   listed item as a vulnerability with its own severity.
4. [`BUILD_AND_TEST.md`](./docs/audit/BUILD_AND_TEST.md) — public dependency setup and exact
   build, test, size, and artifact commands.
5. [`evidence/external-audit/final-2026-08/README.md`](./evidence/external-audit/final-2026-08/README.md)
   — prior Chain Defenders reports, hashes, and finding status.

[`AUDITOR_READING_GUIDE.md`](./docs/audit/AUDITOR_READING_GUIDE.md) lists additional files
to consult for specific review topics. [`SCOPE.ja.md`](./SCOPE.ja.md) is a
non-authoritative Japanese translation; the English `SCOPE.md` controls.

## Exact code identity

| Boundary | Upstream commit | `contracts/src` tree | Audit snapshot commit |
| --- | --- | --- | --- |
| Chain Defenders remediation base | `d4122704d08b521d832438c31c0ddccf202fea81` | `417fe3b995f3dec84fd611fcc2f5c3ebd62d5c7a` | `b5265f311abc524683561b79792eab2900823fa9` |
| Final production candidate | `1b453c10e3378390109cf42037a97b7f6de57b9e` | `84476d9086e89580c58918b203f4142ecd839765` | `2725216e0407a0ef4599e359a04094ae5f322624` |
| Final tests | same final candidate | `65edf44aaad8ee395fa9456151fed25f40a3dfde` | included in this repository |

The requested security review is the complete 25-file, 171-hunk Solidity
differential: `+745/-185` physical lines and 535 final-side changed-code nSLOC.
The 6,656 final whole-file nSLOC is surrounding context, not a request to
re-audit every line. Legacy, archive, inheritance, and cosmetic hunks remain in
scope; unchanged callers and dependencies needed to decide them are required
context. This is not a whole-Liquity re-audit.

## Why there are two audit PRs

- [PR #107](https://github.com/deltaforesight/jpydf-audit/pull/107) contains the
  exact production `contracts/src` endpoint and clean source-diff view.
- [PR #109](https://github.com/deltaforesight/jpydf-audit/pull/109) adds this SOW,
  the complete matching tests, build inputs, English context, prior reports, and
  machine-verifiable evidence. It adds no Solidity change relative to #107.

## Latest production parity

Upstream `develop@aac9cf2ffe53cfcf5ffdba8af33e2ac09bb199ac` was checked on
2026-08-31. Its `contracts/src` and `contracts/test` trees remain exactly
`84476d90` and `65edf44a`; deployment/build inputs also have no diff from the
pinned candidate. Later upstream changes are documentation, CI, frontend/ops,
or infrastructure only. The latest JPY/USD market-hours risk analysis is
incorporated into the English known-risk register with a
[self-contained data and model appendix](./docs/audit/JPYUSD_MARKET_HOURS_RISK_ANALYSIS.md).

## Package contents and boundaries

| Path | Purpose |
| --- | --- |
| `source-snapshot/contracts/src/` | Exact final production Solidity tree. |
| `source-snapshot/contracts/test/` | Exact complete final test and fixture tree. |
| `source-snapshot/contracts/script/` | Selected files needed to compile builds/tests; deployment-script review is excluded. |
| `FINAL_PRODUCTION_HUNK_PROVENANCE.tsv` | All 171 source hunks, exact IDs, and rationale. |
| `FINAL_PRODUCTION_ARTIFACTS.tsv` | Creation/runtime/ABI identities with and without Solidity metadata. |
| `FINAL_PRODUCTION_STORAGE_LAYOUTS.tsv` | Reproducible semantic storage-layout identities. |
| `docs/audit/` | Current audit handoff, evidence, risk, build, and dependency documents. |
| `docs/audit/history/` | Superseded point-in-time reviews and scope decisions retained as evidence. |
| `docs/audit/GUARDIAN_SCOPE_INVENTORY_2026-09-03.md` | Guardian's 25-file scope table and immutable-diff reconciliation. |
| `evidence/external-audit/` | Prior audit PDFs and finding evidence. |

Tests, build configuration, tools, specifications, and deployment files are
supporting material, not additional review targets. Initial production
parameters and wiring, deployment execution, frontend/backend/bots/subgraph,
on-chain readbacks, role handover, and alert delivery are outside the Solidity
SOW unless a revised written scope adds them.

Files named as historical reviews, scope deltas, cleanup reviews, maintainer
pre-audit notes, or workflows are optional provenance. They are not current
scope authorities or external-audit results.

## Verification

Run the package-integrity check:

```sh
./scripts/verify-production-companion.sh
```

See [`BUILD_AND_TEST.md`](./docs/audit/BUILD_AND_TEST.md) for the remaining public
reproduction commands and pinned tool versions.

## Secret policy

Do not commit private keys, signer exports, RPC credentials, API keys, generated
environment files, deployment broadcasts, or unredacted operational evidence.
Vendored dependencies, `node_modules`, `out`, and `cache` are also excluded.
