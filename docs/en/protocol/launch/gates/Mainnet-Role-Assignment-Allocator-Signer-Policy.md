# Mainnet Role Assignment Allocator Signer Policy

> Support translation. The Japanese source document
> [`documents/jp/protocol/launch/gates/Mainnet-Role-Assignment-Allocator-Signer-Policy.md`](../../../../jp/protocol/launch/gates/Mainnet-Role-Assignment-Allocator-Signer-Policy.md)
> is authoritative if this file conflicts with it.

## 0. Metadata

| Field | Value |
| --- | --- |
| Status | Active |
| Date | 2026-07-18 |
| Domain | Protocol Governance |
| Lifecycle | Launch |
| Artifact Type | Policy |
| Decision Authority | Protocol Governance |
| Maintainer | DeltaForesight (Contributor) |
| Scope | The Day-1 holder form of `DF_ALLOCATOR` / Vault `ALLOCATOR_ROLE` |
| Decision | Day 1 starts with an **Allocator Safe under manual operation**; migration to a hardened bot signer is a separate activation gate. |
| Related documents | [Protocol Role Holder Manifest](../../../../jp/protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md) / [Role Holder Separation Policy](../../../../jp/protocol/launch/gates/Mainnet-Role-Holder-Separation-Policy.md) / [Safe Threshold Policy](./Mainnet-Role-Assignment-Safe-Threshold-Policy.md) / [Governance](../../../Governance.md) |

---

## 1. Conclusion

`DF_ALLOCATOR` is a persistent privileged holder, but it is not authority to
withdraw funds to an arbitrary destination. The Vault's `allocate()` and
`transferYieldToTreasury()` have their transfer route fixed to a registered
Strategy or to `treasury`, and `setAllocatorConfig()` can only be executed by GOV.

Under this decision, automation is not enabled before the Day-1 signer roster
and bot custody are settled. The
[Protocol Role Holder Manifest](../../../../jp/protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md)
is authoritative for physical holder addresses, and the
[Safe Threshold Policy](./Mainnet-Role-Assignment-Safe-Threshold-Policy.md) for
owner / threshold / signer composition.

A hardened bot signer remains the future migration target. **Placing an
unprotected EOA directly as a production privileged holder is not acceptable.**
The Timelock migrates `ALLOCATOR_ROLE` only once an operational platform where
humans never handle the private key directly, operation auditing, immediate
suspension, and follow-on revoke / replacement are all in place, and a separate
activation package has been approved.

## 2. Decision axes

The form of the Allocator holder is determined by two things.

| Axis | Assessment |
| --- | --- |
| Blast radius | Transfers to an arbitrary destination are not possible; the main damage is temporary liquidity griefing by pushing the buffer toward Strategies. |
| Operating frequency | `allocate()` and `transferYieldToTreasury()` may be executed repeatedly, so routing every call through multisig signing makes operations heavy. |

Automation is therefore reasonable in future, but the Day-1 manual operating
burden is accepted as the cost of safely deferring the bot activation gate.

## 3. Code facts

The reconciliation target is `contracts/src/CollateralVault.sol`. Line numbers in
this section are operational pointers as of design time, not the authoritative
record for the audit freeze. In the freeze package, re-grep the same function /
guard / role facts from the source at the target commit and keep line-specific
evidence in the launch evidence package.

| Fact | Reference | Meaning |
| --- | --- | --- |
| `ALLOCATOR_ROLE` constant | role constant | Allocator role identity. |
| `allocate()` is `onlyRole(ALLOCATOR_ROLE)` + `whenNotPausedAllocation` | `allocate()` guard | A Guardian pause can stop allocator activity. |
| `allocatorCooldown` gate | `allocate()` guard | Frequency control. |
| Excess is capped by `allocateMaxMove` | allocation size logic | Per-move size control. |
| Default `allocateMaxMove = type(uint256).max` | initializer default | The deploy default is dangerous unless overwritten before launch. |
| `_allocateToStrategies()` uses registered enabled strategies | strategy allocation loop | The destination set is controlled by the GOV strategy registry. |
| `setAllocatorConfig()` is `onlyRole(GOV_ROLE)` | config setter guard | The Allocator cannot relax its own cap / cooldown. |
| `pauseAllocation()` is `onlyRole(GUARDIAN_ROLE)` | pause function guard | Immediate kill-switch. |

## 4. Blast radius

| Area | If the allocator signer is compromised | What it cannot do |
| --- | --- | --- |
| Asset theft | An arbitrary recipient cannot be chosen; funds move only to a registered Strategy or to `treasury`. | Send Vault assets to an attacker-controlled address. |
| Availability | Within `allocateMaxMove` and the cooldown, it can push excess buffer toward Strategies and temporarily reduce instant redeem / claim liquidity. | Directly impair backing, or change the strategy registry. |
| Recovery | Guardian can call `pauseAllocation`. The Timelock can revoke / replace `ALLOCATOR_ROLE`. | Unpause itself, or grant itself additional roles. |

The Allocator is therefore a materially different role from GOV, WRITEOFF,
Guardian, Treasury, Bridge admin, and PriceFeed owner. Those remain Safe /
Timelock / contract holders.

## 5. Future bot activation controls

`DF_ALLOCATOR` may become a hardened bot signer only when all of the following
controls are true.

| Control | Requirement |
| --- | --- |
| Key custody | KMS / HSM / managed custody. Operators never handle a plaintext key. |
| IAM | Grant only the least privilege required to sign the approved function set. |
| Audit logs | Record and retain every signature and caller identity. |
| Balance cap | Limit the gas / funding balance to a documented loss budget. |
| Function scope | The bot submits only allocator operations and the strategy push / withdrawal operations it needs. |
| On-chain cap | `allocateMaxMove` is a positive bounded value, not `type(uint256).max`. |
| Cooldown | `allocatorCooldown` is positive unless the risk owner explicitly approves a temporary exception. |
| Pause path | Guardian `pauseAllocation()` is live and monitored. |
| Rotation | Key rotation and Timelock-based revoke / replacement are documented. |
| Monitoring | Unexpected allocation size, cadence, strategy target, and revert patterns alert ops. |

If any item is missing, keep the current holder and treat allocator bot
activation as No-Go.

## 6. Alternatives

| Form | Role holder | Automation | Consequence if compromised | Position |
| --- | --- | --- | --- | --- |
| Full Safe | Safe | Manual | Strong holder control, but a high operating burden. | **Adopted for Day 1.** |
| Safe with module / guard | Safe | Automated within allow-list | Defence in depth. The Safe retains the owner plane. | Upgrade path. |
| Hardened bot signer | Bot signer | Automated | Arbitrary asset theft is not possible; griefing is bounded by the cap. | Candidate after a separate activation gate. |
| Unprotected EOA | EOA | Automated | A key directly controls the allocator role with no operational hardening. | Not permitted in production. |

## 7. Changeability

`CollateralVault` uses `AccessControlUpgradeable`, and grant / revoke of
`ALLOCATOR_ROLE` is controlled after handover by the `DEFAULT_ADMIN_ROLE` held by
the Timelock. Therefore:

- The Safe holder can later be replaced by a Safe + module, or by an approved
  hardened bot signer.
- A compromised or stale signer can be paused immediately by the Guardian and
  revoked through the Timelock.
- Role migration does not require a protocol redeploy.
- Roles cannot be enumerated from the Vault, so the launch evidence must confirm
  that the old allocator has been revoked.

## 8. Launch gate

Before public launch, the evidence package must show:

1. `DF_ALLOCATOR` matches the approved physical holder address in the Protocol
   Role Holder Manifest.
2. Owner / threshold / signer composition matches the Safe Threshold Policy.
3. The Allocator Safe and the Launch / Ops finance Safe are different contract
   addresses.
4. Readback of `allocateMaxMove` and `allocatorCooldown`.
5. Guardian `pauseAllocation()` holder readiness.
6. The Timelock revoke / replacement procedure.
7. `ALLOCATOR_ROLE` is not granted to a hardened bot signer, and bot activation
   remains behind a separate gate.
