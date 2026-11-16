# Audit Ledger

Fixed at completion of the per-finding audit PRs. All 21 findings are
`Closed — audit-approved (2026-08-05)`.

This ledger covers only that closed 21-finding engagement. The separate August
2026 preliminary enhancement cycle, whose report still labels all five findings
`New`, is tracked in the
[preliminary review index](./preliminary-2026-08/README.md).

| Item | Value |
| --- | --- |
| Decision closure SHA (jpydf-audit `main` at closure of all 21 findings) | `3f6ba016e2fa7a07b89e16cb63f6051333bd243b` |
| Snapshot closure SHA (jpydf-audit `main` after snapshot PRs #49–#69) | `4ea72f51fa180247688736f7bd9372885ebd4d68` |
| Audited remediation identity (jpydf-v2 PR #1418 head; base + all 21 approved diffs) | `10cf5efcf787fd8b1d2f5e35ed22b0064e637258` |
| jpydf-v2 `develop` / PR #1418 base | `4df6d902f270c4352ea3f80590aed89bdf4a425a` |
| Sync merge commit (jpydf-v2 `develop`, PR #1418, 2026-08-05) | `0c7766e0a935b3dd99111349ef84e69c1a07da38` |
| July freeze base (audit base) | `dab4dbe5251f980a3af347cba20351513b026e7b` |

PR #1418 merged on 2026-08-05 as `0c7766e0`; its tree is identical to the
audited identity `10cf5efc` (the base did not move). The jpydf-audit `main`
containing this ledger update is tagged `audit-handoff-2026-08-05` as the
authoritative handoff identity.

Every approved diff — all 21, including the ten pre-merged changes — is
preserved verbatim in this repository at [`patches/`](./patches/) (jpydf-v2 is
not visible to auditors; the jpydf-v2 links are maintainer conveniences). Each
patch file's SHA-256 equals the Diff SHA-256 pinned in its finding note, so
the correspondence is verifiable without jpydf-v2 access; run
`../../scripts/verify-audit-patches.sh` to check all 21 mechanically. Note:
the Mid 03 per-branch freeze-anchor hunks were later superseded by Low 04's
shared `JpyUsdRateProvider`; the sync comparison treats Mid 03 as
semantically carried by Low 04 rather than textually present in the branch
feeds. The Snapshot PR column is the per-issue audit-review
surface: it applies the approved remediation to `source-snapshot/contracts/`
(plus doc-mirror hunks whose context matches exactly; drifted doc hunks stay
in the preserved patch, listed per PR).

| Finding | Audit PR | Snapshot PR | Approved diff (jpydf-v2) | Diff SHA-256 (prefix) | Landing |
| --- | --- | --- | --- | --- | --- |
| [High 01](./findings/high-01.md) | [#27](https://github.com/deltaforesight/jpydf-audit/pull/27) | [#49](https://github.com/deltaforesight/jpydf-audit/pull/49) | [`95c7086f..af194a1a`](https://github.com/deltaforesight/jpydf-v2/pull/1382) | `6d3ebbc1803a` | merged `af194a1a` |
| [Mid 01](./findings/mid-01.md) | [#28](https://github.com/deltaforesight/jpydf-audit/pull/28) | [#50](https://github.com/deltaforesight/jpydf-audit/pull/50) | [`af194a1a..a0a90c71`](https://github.com/deltaforesight/jpydf-v2/pull/1383) | `1923aebc0106` | merged `a0a90c71` |
| [Mid 02](./findings/mid-02.md) | [#29](https://github.com/deltaforesight/jpydf-audit/pull/29) | [#51](https://github.com/deltaforesight/jpydf-audit/pull/51) | [`a0a90c71..e32d7d2c`](https://github.com/deltaforesight/jpydf-v2/pull/1384) | `b88e9e05f8f4` | merged `e32d7d2c` |
| [Mid 03](./findings/mid-03.md) | [#30](https://github.com/deltaforesight/jpydf-audit/pull/30) | [#52](https://github.com/deltaforesight/jpydf-audit/pull/52) | [`e32d7d2c..fe1c80f8`](https://github.com/deltaforesight/jpydf-v2/pull/1385) | `e90e571c3c73` | merged `fe1c80f8` |
| [Low 01](./findings/low-01.md) | [#31](https://github.com/deltaforesight/jpydf-audit/pull/31) | [#53](https://github.com/deltaforesight/jpydf-audit/pull/53) | [`fe1c80f8..4535dfed`](https://github.com/deltaforesight/jpydf-v2/pull/1396) | `f7bc98e02e57` | merged `4535dfed` |
| [Low 02](./findings/low-02.md) | [#32](https://github.com/deltaforesight/jpydf-audit/pull/32) | [#54](https://github.com/deltaforesight/jpydf-audit/pull/54) | [`3c2ee613..5124599e`](https://github.com/deltaforesight/jpydf-v2/pull/1397) | `bf1fa737d9de` | merged `5124599e` |
| [Low 03](./findings/low-03.md) | [#33](https://github.com/deltaforesight/jpydf-audit/pull/33) | [#55](https://github.com/deltaforesight/jpydf-audit/pull/55) | [`8f0efd94..8bf86300`](https://github.com/deltaforesight/jpydf-v2/pull/1398) | `f3ba3dc7cadb` | merged `8bf86300` |
| [Low 04](./findings/low-04.md) | [#34](https://github.com/deltaforesight/jpydf-audit/pull/34) | [#56](https://github.com/deltaforesight/jpydf-audit/pull/56) | [`409dfdec..789466ee`](https://github.com/deltaforesight/jpydf-v2/pull/1404) | `5edda6d94a36` | merged `789466ee` |
| [Low 05](./findings/low-05.md) | [#35](https://github.com/deltaforesight/jpydf-audit/pull/35) | [#57](https://github.com/deltaforesight/jpydf-audit/pull/57) | [`789466ee..1adab166`](https://github.com/deltaforesight/jpydf-v2/pull/1405) | `bf7bbc3a6474` | merged `1adab166` |
| [Low 06](./findings/low-06.md) | [#36](https://github.com/deltaforesight/jpydf-audit/pull/36) | [#58](https://github.com/deltaforesight/jpydf-audit/pull/58) | [`1adab166..4df6d902`](https://github.com/deltaforesight/jpydf-v2/pull/1406) | `88c57b234a69` | merged `4df6d902` |
| [Low 07](./findings/low-07.md) | [#37](https://github.com/deltaforesight/jpydf-audit/pull/37) | [#59](https://github.com/deltaforesight/jpydf-audit/pull/59) | [`4df6d902..07b8baac`](https://github.com/deltaforesight/jpydf-v2/pull/1407) | `b2eb5d78a2e5` | merged `0c7766e0` ([sync PR #1418](https://github.com/deltaforesight/jpydf-v2/pull/1418)) |
| [Info 01](./findings/info-01.md) | [#38](https://github.com/deltaforesight/jpydf-audit/pull/38) | [#60](https://github.com/deltaforesight/jpydf-audit/pull/60) | [`4df6d902..102c23f7`](https://github.com/deltaforesight/jpydf-v2/pull/1410) | `0750d8783744` | merged `0c7766e0` ([sync PR #1418](https://github.com/deltaforesight/jpydf-v2/pull/1418)) |
| [Info 02](./findings/info-02.md) | [#39](https://github.com/deltaforesight/jpydf-audit/pull/39) | [#61](https://github.com/deltaforesight/jpydf-audit/pull/61) | [`4df6d902..1c38f89d`](https://github.com/deltaforesight/jpydf-v2/pull/1411) | `aa4b1c8aa15b` | merged `0c7766e0` ([sync PR #1418](https://github.com/deltaforesight/jpydf-v2/pull/1418)) |
| [Info 03](./findings/info-03.md) | [#40](https://github.com/deltaforesight/jpydf-audit/pull/40) | [#62](https://github.com/deltaforesight/jpydf-audit/pull/62) | [`4df6d902..f0b82f0c`](https://github.com/deltaforesight/jpydf-v2/pull/1412) | `d9673b2e06d5` | merged `0c7766e0` ([sync PR #1418](https://github.com/deltaforesight/jpydf-v2/pull/1418)) |
| [Info 04](./findings/info-04.md) | [#41](https://github.com/deltaforesight/jpydf-audit/pull/41) | [#63](https://github.com/deltaforesight/jpydf-audit/pull/63) | [`4df6d902..f59f9533`](https://github.com/deltaforesight/jpydf-v2/pull/1413) | `df879c5aac75` | merged `0c7766e0` ([sync PR #1418](https://github.com/deltaforesight/jpydf-v2/pull/1418)) |
| [Info 05](./findings/info-05.md) | [#42](https://github.com/deltaforesight/jpydf-audit/pull/42) | [#64](https://github.com/deltaforesight/jpydf-audit/pull/64) | [`4df6d902..fff9251a`](https://github.com/deltaforesight/jpydf-v2/pull/1414) | `0abff1543681` | merged `0c7766e0` ([sync PR #1418](https://github.com/deltaforesight/jpydf-v2/pull/1418)) |
| [Info 06](./findings/info-06.md) | [#43](https://github.com/deltaforesight/jpydf-audit/pull/43) | [#65](https://github.com/deltaforesight/jpydf-audit/pull/65) | [`4df6d902..fd0f8478`](https://github.com/deltaforesight/jpydf-v2/pull/1415) | `cd86d57e4a4e` | merged `0c7766e0` ([sync PR #1418](https://github.com/deltaforesight/jpydf-v2/pull/1418)) |
| [Info 07](./findings/info-07.md) | [#44](https://github.com/deltaforesight/jpydf-audit/pull/44) | [#66](https://github.com/deltaforesight/jpydf-audit/pull/66) | [`4df6d902..d0402e1a`](https://github.com/deltaforesight/jpydf-v2/pull/1416) | `fcb11765ba4e` | merged `0c7766e0` ([sync PR #1418](https://github.com/deltaforesight/jpydf-v2/pull/1418)) |
| [Info 08](./findings/info-08.md) | [#45](https://github.com/deltaforesight/jpydf-audit/pull/45) | [#67](https://github.com/deltaforesight/jpydf-audit/pull/67) | [`4df6d902..49808c45`](https://github.com/deltaforesight/jpydf-v2/pull/1408) | `c326b841e2fc` | merged `0c7766e0` ([sync PR #1418](https://github.com/deltaforesight/jpydf-v2/pull/1418)) |
| [Gas 01](./findings/gas-01.md) | [#46](https://github.com/deltaforesight/jpydf-audit/pull/46) | [#68](https://github.com/deltaforesight/jpydf-audit/pull/68) | [`4df6d902..3f9aef8d`](https://github.com/deltaforesight/jpydf-v2/pull/1417) | `6cf2b979b4b3` | merged `0c7766e0` ([sync PR #1418](https://github.com/deltaforesight/jpydf-v2/pull/1418)) |
| [Gas 02](./findings/gas-02.md) | [#47](https://github.com/deltaforesight/jpydf-audit/pull/47) | [#69](https://github.com/deltaforesight/jpydf-audit/pull/69) | [`4df6d902..5d455b0c`](https://github.com/deltaforesight/jpydf-v2/pull/1409) | `3f3e298b09fe` | merged `0c7766e0` ([sync PR #1418](https://github.com/deltaforesight/jpydf-v2/pull/1418)) |

## Sync verification (2026-08-05)

- The ten pre-merged diffs: merge commits all reachable from jpydf-v2
  `develop`, recomputed diff hashes all match the pinned values (10/10).
- The eleven candidate patches: recomputed SHA-256 all match (11/11).
- Audit sync PR [jpydf-v2#1418](https://github.com/deltaforesight/jpydf-v2/pull/1418)
  merges the eleven candidate branches plus the Info 07 required amendment;
  focused suites 257/257 passed, full CI green. Merged 2026-08-05 as
  `0c7766e0` after the differential re-review cleared the HOLD.
- Snapshot end-state check: `source-snapshot/contracts/{src,script,test}`
  equals the sync-branch state except four non-audit drift files
  (`src/GasPool.sol`, `src/README.md`, `test/README.md`,
  `test/TestContracts/InvariantsTestHandler.t.sol` — outside every approved
  diff, deliberately not applied) and nine curation-excluded files.

## Post-merge follow-ups (recorded 2026-08-05; none block PR #1418)

Fix-quality review of all 21 approved diffs completed 2026-08-05 with zero
rejections (verdicts and evidence in each finding note). Tracked follow-ups:

1. Low 02: end-to-end rehearsal test and runbook entry for the
   bricked-strategy exit (brick views → Timelock-driven UUPS upgrade →
   writeoff → remove); optional dedicated `AllocationBlocked` event.
2. Low 01: optional Vault-side balance recheck on the allocation skip path
   (defense in depth for future non-BaseStrategy implementations).
3. Low 06: optional tightening of the Console devnet timelock scripts to the
   31337/31338 allowlist (currently accepted devnet-only residual); unit
   tests for the deploy CLI signer logic.
4. Mid 01: automated watcher for Aave `provider.getPool()` drift
   (AAVE-GOV-003 is currently a documented manual duty).
5. Gas 01: mainnet-fork replay of the valuation loop before any additional
   branch or new Strategy-type activation (spec-gated).
6. After PR #1418 merges: tag the final identities per the identity table
   above and refresh Slither/nSLOC/source-manifest evidence at the merged
   identity.
