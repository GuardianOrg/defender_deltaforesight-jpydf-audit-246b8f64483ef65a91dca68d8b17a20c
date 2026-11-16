# Final Production Source Snapshot

This directory contains the self-contained Solidity/build/test portion of the
additional production audit package.

## Immutable Identity

| Boundary | Commit | Tree |
| --- | --- | --- |
| Chain Defenders remediation base source | `d4122704d08b521d832438c31c0ddccf202fea81` | `contracts/src` `417fe3b995f3dec84fd611fcc2f5c3ebd62d5c7a` |
| Final production source | `1b453c10e3378390109cf42037a97b7f6de57b9e` | `contracts/src` `84476d9086e89580c58918b203f4142ecd839765` |
| Final tests | same final commit | `contracts/test` `65edf44aaad8ee395fa9456151fed25f40a3dfde` |

The complete 25-file / 171-hunk `contracts/src` differential preserves exact
candidate identity and is the requested review scope in `SCOPE.md`. Legacy,
archive, inheritance, and cosmetic hunks are included. It includes the earlier
remediation and every surviving runtime-decimals, recovery/resume, and 30-hour
normal-redemption change. The package also includes the later
production-cleanup delta and final
endpoint-absence evidence. `ActivePool.sol` is base/head identical, so its
cleanup removal correctly leaves no priced base-to-final hunk.

## Included

- `contracts/src/`: exact complete final production Solidity tree;
- `contracts/test/`: exact complete final test and fixture tree;
- `contracts/script/`: selected exact deploy/test import closure;
- `contracts/utils/`: size, rollback, manifest-policy, native-ETH-route, and
  deploy-CLI closure needed by the recorded checks;
- exact Foundry configuration, remappings, and dependency lock; curated
  standalone package metadata/pnpm lock exposing only committed commands; the
  executable deploy wrapper; and
- `config/`: exact Day-1 branch manifest and schema required by snapshot-local
  build/test permissions.

Only `contracts/src` is priced as changed production Solidity. Tests, scripts,
tools, and configuration are required reproduction/context material unless the
statement of work explicitly adds their review.

## Excluded

- vendored public dependencies under `contracts/lib`;
- `node_modules`, `out`, `cache`, `broadcast`, generated ABIs, and coverage
  output;
- `.env` files, RPC credentials, signer/private-key material, production
  manifests, and unredacted on-chain evidence;
- unrelated operational scripts and tools not required by the recorded audit
  commands; and
- `contracts/script/SeedLocalDemo.s.sol`, whose public Anvil test-key literal is
  unnecessary for production or the selected audit closure.

Public dependencies are installed at exact commits using
[`BUILD_AND_TEST.md`](../docs/audit/BUILD_AND_TEST.md). Access to the private
implementation repository is not required.

## Verify And Review

Run the committed hash-only verifier from the audit repository root:

```sh
./scripts/verify-production-companion.sh
```

The exact mapping for the complete source/test trees and every
selected/refreshed candidate-derived companion item is
[`PRODUCTION_COMPANION_MAPPING.tsv`](../PRODUCTION_COMPANION_MAPPING.tsv).
Inherited audit-repository context outside that ledger is not asserted to match
the final candidate.
Review scope is controlled by [`SCOPE.md`](../SCOPE.md), and the complete
English narrative is
[`GUARDIAN_ADDITIONAL_AUDIT_HANDOFF.md`](../docs/audit/GUARDIAN_ADDITIONAL_AUDIT_HANDOFF.md).

Historical Chain Defenders evidence remains under `../evidence`. It establishes
the baseline and prior decisions but does not override the final identity above.

The copied `contracts/README.md`, `contracts/src/README.md`, and
`contracts/test/README.md` are workspace maps from the implementation repository
and may link to intentionally unbundled `AGENTS.md` or Japanese/internal paths.
Those links are not auditor prerequisites. Use the audit-root `README.md`,
`SCOPE.md`, and current `docs/en` files as the handoff authority.
