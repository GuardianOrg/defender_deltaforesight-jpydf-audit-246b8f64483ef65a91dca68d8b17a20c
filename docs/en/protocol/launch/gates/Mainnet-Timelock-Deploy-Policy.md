# Mainnet Timelock Deploy Policy

> Support translation. The Japanese source document
> [`documents/jp/protocol/launch/gates/Mainnet-Timelock-Deploy-Policy.md`](../../../../jp/protocol/launch/gates/Mainnet-Timelock-Deploy-Policy.md)
> is authoritative if this file conflicts with it.
>
> **Environment separation**: Keep the pilot / canary Timelock
> `0xEd33edB1eA442475eFd076e1AE2C9da9EdaB86f6` at `minDelay=300`. Production
> must not reuse that address. Fresh-deploy a separate OZ v4.9.5 Timelock with
> `minDelay=43200`.

## 0. Metadata

| Field | Value |
| --- | --- |
| Status | Active |
| Date | 2026-06-29 |
| Domain | Protocol Governance |
| Lifecycle | Launch |
| Artifact Type | Policy |
| Decision Authority | Protocol Governance |
| Maintainer | DeltaForesight (Contributor) |
| Visibility | Public |
| Scope | Deploy / role configuration policy for the production GOV Timelock (`DF_TIMELOCK`) |
| Decision | Deploy a production-only Timelock with a 12-hour delay and self-admin from its constructor; sharing the pilot address is prohibited. |
| Procedure | [Mainnet-Timelock-Deploy-Runbook](./Mainnet-Timelock-Deploy-Runbook.md) |

---

## 1. Conclusion

The Ethereum mainnet pilot / canary and production environments use different
Timelock instances. OpenZeppelin `TimelockController` has one `minDelay` per
instance, so one address cannot keep a five-minute pilot delay while enforcing a
12-hour production delay.

| Scope | Timelock address | Required delay |
| --- | --- | --- |
| pilot / canary | `0xEd33edB1eA442475eFd076e1AE2C9da9EdaB86f6` | `300` |
| production | A separate address frozen in the Protocol Role Holder Manifest after deployment | `43200` |

The production deploy script enforces all of the following:

- `DF_TIMELOCK` differs from the pilot / canary address.
- Metadata-free creation and runtime code hashes built with the
  `production-timelock` profile match repository-pinned values.
- `getMinDelay()==43200`.
- Only the Admin Safe holds PROPOSER / EXECUTOR / CANCELLER.
- Only the Timelock itself holds `TIMELOCK_ADMIN_ROLE`.
- `EXECUTOR_ROLE` is not granted to `address(0)`.

Do not use `updateDelay(43200)` on the pilot / canary Timelock as the production
migration path. The production Timelock starts with a delay of 43200 in its
constructor and does not depend on a post-deploy delay transition.

## 2. Adopted implementation

| Item | Adopted state / source |
| --- | --- |
| Implementation source | `TimelockController.sol` from `contracts/lib/openzeppelin-contracts` tag `v4.9.5` / commit `bd325d56b4c62c9c5c1aff048c37c6bb18ac0290` |
| Runtime code | `production-timelock` profile, 7,454 bytes, `0xfbb8dca0ef620c28593dafd8ead5162f233db640a9ebfdc4d47a7920cc06b2af` |
| `minDelay` | [Parameters](../../../Parameters.md) `PRM-GOV-COMMON-TIMELOCK-DELAY` = `43200` |
| PROPOSER / EXECUTOR / CANCELLER | Holder class is defined by the [authoritative Japanese Parameter Catalog](../../../../jp/protocol/product/parameters/Parameter-Catalog.md); the address is defined by the [English Protocol Role Holder Manifest](../manifests/Mainnet-Protocol-Role-Holder-Manifest.md) |
| Admin role | Timelock itself only; no external admin |

Do not treat another implementation or commit as equivalent. Any change
requires revising this policy and rebuilding the source review, runtime code
hash, constructor-role analysis, runbook, and complete role evidence for the new
candidate.

## 3. Design decisions

### 3.1 Fresh production instance

Fresh-deploy the production Timelock with
`DeployMainnetProductionTimelock.s.sol` under
`FOUNDRY_PROFILE=production-timelock`. Only the canonical artifact without
compiler metadata is accepted; the script checks creation and runtime hashes
before broadcasting starts. This profile is exclusively for the production
Timelock and must not be used for the protocol deployment.

Constructor arguments are `minDelay=43200`, Admin Safe as proposers and
executors, and `address(0)` as admin. The OZ constructor also grants
`CANCELLER_ROLE` to the proposer. No extra role mutation and no deployer-admin
renounce transaction are needed: the production instance is self-admin only
from inception.

### 3.2 Closed execution

Do not grant `EXECUTOR_ROLE` to `address(0)`. Third parties must not be able to
choose execution timing after the delay expires. The accepted risk of not
having an independent canceller and the holder-separation conditions are owned
by the [Role Holder Separation Policy](./Mainnet-Role-Holder-Separation-Policy.md).

### 3.3 Evidence before use

Do not predict or manually freeze the production Timelock address before
deployment. Pin the deployment receipt, constructor arguments, runtime hash,
delay, roles, and Safe owner / threshold matrix to the same candidate commit and
pinned block. Only after the governance checker passes may the address be added
to the Manifest and deploy environment.

No `CallScheduled` event is permitted before the first evidence-pinned block.
A Timelock is not "unused" if an operation targeting a future protocol address
was queued early to consume part of the delay; the evidence checker must fail.
From the first evidence block through the launch safe block, only operation IDs
derived from approved governance artifacts are permitted. Until a checker that
closes the complete event inventory exists, separate receipt / event review is
a Launch No-Go release condition.

`VerifyDFGovernanceHandover` checks the Timelock runtime, delay, known roles, and
absence of an open executor at execution time in addition to protocol-side
holder assignment. It does not prove the constructor or direct deployment
receipt, absence of additional holders across the complete event history, or
the Safe matrix. Those are verified by this policy and the runbook evidence
package.

## 4. Launch sequence

```text
all production Safe owner / threshold hardening
  -> fresh production Timelock deploy at 43200s
  -> receipt / runtime / delay / roles / Safe matrix evidence
  -> freeze production Timelock address in manifest and deploy env
  -> fresh production protocol deploy / bounded test / cleanup / Prepare
  -> required ownership accept through the 43200s production Timelock
  -> schedule production cap operation with 43200s delay
  -> cap execute + bootstrap / SP, then LP and final verify
```

The bounded-user-operation test, cleanup, residual baseline, cap zero, and
large-asset-deposit boundaries for the fresh production protocol follow the
[Mainnet Launch Operation Gate](./Mainnet-Launch-Operation-Gate.md) and
[Governance Handover Runbook](./Mainnet-Governance-Handover-Runbook.md).

## 5. Launch No-Go

| No-Go | Reason |
| --- | --- |
| Production `DF_TIMELOCK` equals the pilot / canary address | A five-minute pilot and 12-hour production delay cannot be separated. |
| Deployment receipt, constructor arguments, candidate commit, and block number / hash are not in the same evidence package | The deployed instance cannot be identified uniquely. |
| The submodule commit, compiled runtime code hash, or on-chain `extcodehash` differs from the adopted implementation | The reviewed implementation cannot be identified. |
| `getMinDelay()!=43200` | Production parameter mismatch. |
| PROPOSER / EXECUTOR / CANCELLER differ from the approved Admin Safe, or an unknown holder has a role | Timelock role-holder mismatch. |
| `EXECUTOR_ROLE` is granted to `address(0)` | Open execution is not approved for Day 1. |
| Any account other than the Timelock itself holds `TIMELOCK_ADMIN_ROLE` | Delay-free role or delay mutation remains possible. |
| Between the first evidence block and launch safe block, an unapproved `CallScheduled` exists or the complete event inventory has not been reviewed | An unapproved operation may be queued in the same Timelock. |
| Any production Safe lacks a successful pre-deploy hardening receipt, or its owners / threshold differ from Safe Threshold Policy | Holder-policy violation. |
| Production Timelock remains `<pending-production-timelock>` / `deploy-pending` in the Protocol Role Holder Manifest | Address evidence is not frozen. |
| A production protocol / handover / cap artifact references the pilot Timelock or differs from the production evidence address / digest | Wrong-environment governance target. |

## 6. References

- [Mainnet Protocol Role Holder Manifest](../manifests/Mainnet-Protocol-Role-Holder-Manifest.md)
- [Mainnet Role Holder Separation Policy](./Mainnet-Role-Holder-Separation-Policy.md)
- [Mainnet-Role-Assignment-Safe-Threshold-Policy](./Mainnet-Role-Assignment-Safe-Threshold-Policy.md)
- [Mainnet-Timelock-Deploy-Runbook](./Mainnet-Timelock-Deploy-Runbook.md)
- [Governance](../../../Governance.md)
- [Mainnet-Governance-Handover-Runbook](./Mainnet-Governance-Handover-Runbook.md)
