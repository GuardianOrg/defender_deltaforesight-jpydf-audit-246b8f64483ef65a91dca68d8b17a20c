# August 2026 Preliminary Enhancement Findings

This directory preserves the preliminary follow-up report separately from the
closed 21-finding August engagement in the parent directory. The report is
non-authoritative input: Japanese specifications remain the source of truth,
and each finding requires reproduction, an impact decision, and regression
evidence.

> The [final Chain Defenders report](../final-2026-08/README.md) is now
> preserved separately. It supersedes this preliminary PDF for auditor status:
> M-01, M-02, L-01, and L-02 are `Fixed`; L-03 is `Acknowledged`. This directory
> remains the immutable preliminary artifact and repository-side remediation
> record.

| Item | Value |
| --- | --- |
| Artifact | [`jpydf-enhancement-aug-2026-preliminary.pdf`](./jpydf-enhancement-aug-2026-preliminary.pdf) |
| Author | Chain Defenders |
| Report state | Preliminary |
| Report pages | 30 |
| Source SHA-256 | `255a3824c1c4896aa14f5857c5a876246a3237f0459e67b077779c7befed2e52` |
| Report source identity | `469b12652c799085e386151445949f1b1da4eb32` |
| Current audit snapshot | `fe3d3d0e182b8189202dee3a3db8103bd0df1de7` |
| Source landing provenance | head `d4122704d08b521d832438c31c0ddccf202fea81`, merged as `8c8b4e31625d9e7e5f686ee33183ed575ef4f6e2` (provenance only; private access is not required) |
| Intake date | 2026-08-12 |

The report contains two Medium and three Low findings. They are intentionally
handled one finding per PR; no finding is accepted solely because it appears in
the report.

**Preliminary status:** this PDF lists all five findings as `New`. The table
below records the repository-side decisions made from that preliminary intake.
Use the final report linked above for the later auditor dispositions.

| ID | Report title | Repository status |
| --- | --- | --- |
| [M-01](./findings/m-01.md) | Shared JPY Freeze-Expiry Latch Is Permanent | Accepted; remediation and repository-side review complete |
| [M-02](./findings/m-02.md) | Sky PSM Route Halt Is Classified As A Permanent Protocol Fault | Accepted; remediation and repository-side review complete |
| [L-01](./findings/l-01.md) | Permissionless `claim` Allows Front-Run Gas-Griefing | Accepted in part; idempotent-retry remediation and repository-side review complete |
| [L-02](./findings/l-02.md) | Feed Constructor Silently Deploys With `lastGoodPrice = 0` | Accepted in part; source-level defense-in-depth remediation and repository-side review complete |
| [L-03](./findings/l-03.md) | `_reduceStrategyValuationCache` Does Not Refresh `updatedAt` | Rejected; proposed timestamp refresh is unsafe, resolution tests and repository-side review complete |

## Repository-side post-resolution verification

The finding dispositions are followed by a test/docs-only
[Vault invariant recertification](./vault-recertification.md). Its
[`vault-recertification.patch`](./patches/vault-recertification.patch) is pinned
at SHA-256
`e19fd52e89a7dc539508e492ed4cb9eb49022d10eb61f3cacdca9d4d76848e8a`.
It adds stateful evidence for five Vault requirements without changing
production Solidity. `VAULT-FR-016` remains partial until public, pinned
mainnet-fork evidence demonstrates an actual Strategy loss and the corresponding
backing-ratio decrease.
