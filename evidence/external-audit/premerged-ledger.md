# Pre-Merged Change Ledger

These ten jpydf-v2 pull requests were merged into `develop` before the
audit-repo review process in this repository completed. They are recorded here
as "merged ahead of audit approval": they are NOT bulk-reverted, because later
changes may depend on them and several are Medium/Low security fixes, but none
of them is treated as audit-accepted. After all per-finding audit PRs merge
and the audit SHA is fixed, each entry is mechanically compared against the
approved audit diff: matching changes are kept, mismatching or rejected
changes are fixed or reverted via the final audit sync PR.

| Finding | jpydf-v2 PR | Merge SHA | Change class | Title |
| --- | --- | --- | --- | --- |
| High 01 | [#1382](https://github.com/deltaforesight/jpydf-v2/pull/1382) | `af194a1a` | test/evidence only | test: close Sky refund audit finding |
| Mid 01 | [#1383](https://github.com/deltaforesight/jpydf-v2/pull/1383) | `a0a90c71` | docs + deploy preflight | docs(aave): close pool staleness finding |
| Mid 02 | [#1384](https://github.com/deltaforesight/jpydf-v2/pull/1384) | `e32d7d2c` | production fix | fix(oracle): enforce cached source continuity guard |
| Mid 03 | [#1385](https://github.com/deltaforesight/jpydf-v2/pull/1385) | `fe1c80f8` | production fix | fix(oracle): anchor JPY freeze to cached rate age |
| Low 01 | [#1396](https://github.com/deltaforesight/jpydf-v2/pull/1396) | `4535dfed` | production fix | fix(strategy): isolate rejected allocation deposits |
| Low 02 | [#1397](https://github.com/deltaforesight/jpydf-v2/pull/1397) | `5124599e` | production fix | fix(vault): fail closed on partial valuations |
| Low 03 | [#1398](https://github.com/deltaforesight/jpydf-v2/pull/1398) | `8bf86300` | production fix | fix(vault): make delayed claims permissionless |
| Low 04 | [#1404](https://github.com/deltaforesight/jpydf-v2/pull/1404) | `789466ee` | production fix | fix(oracle): coordinate JPY freeze state across branches |
| Low 05 | [#1405](https://github.com/deltaforesight/jpydf-v2/pull/1405) | `1adab166` | production fix | fix(governance): validate interest router recipients |
| Low 06 | [#1406](https://github.com/deltaforesight/jpydf-v2/pull/1406) | `4df6d902` | deploy-script fix | fix(deploy): remove production private key env paths |

The eleven remaining candidates (Low 07, Info 01–08, Gas 01–02; jpydf-v2
#1407–#1417) were closed without merge on 2026-08-05 and their branches are
preserved as candidate patches (`agent/audit-*`). No further changes land in
jpydf-v2 until the audit completes.
