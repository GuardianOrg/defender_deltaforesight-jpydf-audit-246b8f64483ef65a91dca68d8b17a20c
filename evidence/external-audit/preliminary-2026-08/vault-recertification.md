# Vault invariant recertification

## Outcome

The post-remediation Vault campaign recertifies five requirements with
stateful evidence. It changes only `InvariantPushModel.t.sol` and the Japanese /
English verification ledgers; production Solidity, interfaces, and production
deployment behavior are unchanged.

| Item | Value |
| --- | --- |
| Campaign | `VAULT-RECERT-20260812` |
| Public overlay | [`patches/vault-recertification.patch`](./patches/vault-recertification.patch) |
| Overlay SHA-256 | `e19fd52e89a7dc539508e492ed4cb9eb49022d10eb61f3cacdca9d4d76848e8a` |
| Source provenance | head `d8c42087eaa77d7e827258a7801f9574e6d7d220`, merge `cf8319db143ebf480b2a2e9cdc22451cbd911d1f` (provenance only) |
| Foundry | `1.7.1` |
| Production Solidity diff | Empty |

Auditor verification does not require access to the private source repository.
The committed overlay, reconstructed snapshot, ledgers, and commands below are
the review artifacts.

## Recertified requirements

| Requirement | Result | Evidence added |
| --- | --- | --- |
| `VAULT-FR-009` | PASS | Governance strategy updates, emergency disable, zero disabled weight, and aggregate-weight accounting |
| `VAULT-FR-019` | PASS | Incident pause and bounded unpause recovery under sustained stateful traffic |
| `VAULT-INV-009` | PASS | Every disabled Strategy has zero weight; cached total equals the registered-weight sum |
| `VAULT-INV-012` | PASS | `backingRatio()` equals the downward-capped asset/liability definition |
| `VAULT-INV-014` | PASS | Effective liabilities use ceiling conversion and include pending claims |

`VAULT-FR-016` remains **PARTIAL(unit + invariant)**. The remaining evidence is
a public run against a pinned Ethereum mainnet fork that causes actual Strategy
loss and records the Vault backing ratio before and after the loss. A candidate
venue-only recovery run is not sufficient unless the published artifact proves
that ratio transition.

## Verification results

- Vault / Strategy / Oracle focused suites: 263 passed, 0 failed, 0 skipped.
- Push-model invariant suite: 7 passed; each invariant ran 500 times and made
  25,000 handler calls with 0 reverts.
- Auditor-snapshot fast Foundry gate: 1,551 passed, 0 failed, 0 skipped across
  81 suites.
- Source integration fast Foundry gate: 1,572 passed, 0 failed, 0 skipped
  across 82 suites. The 21-test difference consists of post-freeze deployment,
  governance-handover, and local-helper tests outside the frozen audit
  snapshot (15 + 4 + 2); it is not missing Vault evidence.
- `forge fmt --check contracts/test/InvariantPushModel.t.sol`: passed.
- `git diff --check`: passed.

## Reproduction

After installing the public dependencies from the repository-level
`BUILD_AND_TEST.md`, run from `source-snapshot/contracts/`:

```sh
forge test -vv --match-contract '^(CollateralVaultTest|CollateralVaultStrategyTest|MorphoV2StrategyTest|InvariantPushModelTest)$'
forge test -vv --match-contract '^(DFWstETHPriceFeedTest|MorphoV2BackingRatioTest)$'
FOUNDRY_PROFILE=ci forge test -vv --no-match-contract 'Mainnet|Invariant|Anchored|Initiative|LocalParityDrill'
```

To reconstruct and verify every copied source and documentation file from the
base handoff identity plus all ordered overlays:

```sh
./scripts/sync-from-source.sh --verify /path/to/jpydf-v2 fe3d3d0e182b8189202dee3a3db8103bd0df1de7
```

The maintainer-only source path in the final command is a reconciliation aid;
auditors can review and execute the committed snapshot without it.
