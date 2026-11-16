# Slither Audit Config Run

## Follow-up freeze rerun — 2026-08-08

The audit configuration was rerun against exact source freeze
`0a85b374015e2553d2985b4a3f454b6aee4514a5`. Before triage, the mapping-aware
snapshot verifier reported `drift 0`, `missing 0`, `undecided 0`, and
`stated 0` against that commit.

Command, run from the byte-identical frozen contracts checkout:

```sh
slither . \
  --compile-force-framework foundry \
  --config-file <audit-repo>/config/slither-audit.config.json \
  --json /private/tmp/slither-0a85b374.json
```

Tools and result:

- Slither `0.11.5`; Foundry `1.7.1`; Solc `0.8.24`.
- `187 contracts` analyzed with `101 detectors`.
- `1,439 results`; the JSON reports `success: true`. The CLI's nonzero finding
  status is expected and is not a compilation failure.
- Impact totals: High 78, Medium 200, Low 337, Informational 807,
  Optimization 17.
- Raw JSON size: `83,940,441` bytes.
- Raw JSON SHA-256:
  `124d0e09cfb313ff5069c08ad9ac8e1b0d7cbc3b8fed28e9453d7fd38fe7c037`.

The 80 MiB machine-local JSON is intentionally not committed. Its complete
detector counts and reviewed disposition are in
[`slither-triage.md`](./slither-triage.md). A separate fresh reference-script
compile also succeeded: 256 files, Solc 0.8.24, exit 0.

The same committed snapshot was independently reconstructed using only the
public dependency commits in `BUILD_AND_TEST.md`: production build succeeded,
and the standard fast Foundry gate passed 1,536 / 0 / 0 across 81 suites. This
proves the auditor path does not depend on access to `jpydf-v2`.

## Historical July run

Status date: 2026-07-01

## Command

Run from `jpydf-v2/contracts` for the Solidity source tree frozen at merge
commit `693dff8a4b2eb96a2197b279804a1abc9837a8d9`:

```sh
slither . \
  --compile-force-framework foundry \
  --config-file <audit-repo>/config/slither-audit.config.json
```

The raw output was written to a temporary local file:

```text
<tmpdir>/jpydf-slither-audit-foundry-93cdd678.txt
```

Raw Slither output is not committed because it is noisy and should be triaged
into findings / accepted-risk notes before becoming audit evidence.

The temporary filename keeps the verification short hash `93cdd678`. The final
freeze commit only changes documentation entrypoints after that verification
commit; Solidity implementation files, tests, scripts, and build inputs are
unchanged, so this Slither run applies to the final Solidity source.

Local tool version for this run: `slither 0.10.2`. The source repository
`contracts/requirements.txt` pins `slither-analyzer==0.10.0` for venv
reproduction.

Raw output metadata:

- sha256:
  `ba892eeafd6cf91f2caa3e7f4f90ae17c415deda69f83119ee07eb036330d0fb`
- line count: `3653`

## Result

Slither compiled through Foundry and completed analysis. It exited non-zero
because findings were present:

```text
Slither:. analyzed (176 contracts with 95 detectors), 1256 result(s) found
```

Representative detector groups in the raw output included:

- arbitrary `transferFrom` from GasPool compensation paths
- ETH-send detector hits in Lido / Etherfi strategy deposit and claim flows
- divide-before-multiply warnings in core/NFT math
- strict-equality warnings across vault, strategy, and core guards
- reentrancy-pattern warnings in `CollateralVault` allocation and
  `TroveManager` batch/redemption flows
- similar-name warnings in Sky, UniV4, and domain parameter names
- unused storage gap warnings in upgradeable contracts
- immutable-suggestion warnings in inherited core references

## Followup

This is the execution/readiness record. The reviewed detector-level triage is
now recorded in [`slither-triage.md`](./slither-triage.md). That document
classifies accepted findings, false positives, auditor-facing questions, and
source-repository hygiene followups.
