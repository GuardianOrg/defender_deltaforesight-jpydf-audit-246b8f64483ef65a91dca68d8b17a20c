# Mainnet Role Assignment Safe Threshold Policy

> Support translation. The Japanese source document
> [`documents/jp/protocol/launch/gates/Mainnet-Role-Assignment-Safe-Threshold-Policy.md`](../../../../jp/protocol/launch/gates/Mainnet-Role-Assignment-Safe-Threshold-Policy.md)
> is authoritative if this file conflicts with it.

## 0. Metadata

| Field | Value |
| --- | --- |
| Status | Draft |
| Domain | Protocol Governance |
| Lifecycle | Launch |
| Artifact Type | Policy |
| Decision Authority | Protocol Governance |
| Maintainer | DeltaForesight (Contributor) |
| Scope | Protocol Safe threshold / signer count / signer control-domain / host device design for Ethereum mainnet Day 1 |
| Role of this document | Defines the target threshold, signer control blocks, and host device policy for the Safe holders in the Protocol Role Holder Manifest |
| Related documents | [Protocol Role Holder Manifest](../../../../jp/protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md) / [Role Holder Separation Policy](../../../../jp/protocol/launch/gates/Mainnet-Role-Holder-Separation-Policy.md) / [Governance](../../../Governance.md) / [Mainnet-Safe-Role-Assignment-Gate](./Mainnet-Safe-Role-Assignment-Gate.md) |

This document covers the signer key holder, threshold, and host device policy
for each Safe. It does not record personal names, email addresses, device
serials, Safe nonces, raw signer lists, or the asset tag / serial / MDM ID of a
host device. Signer lists are reconciled in the launch evidence package by
`signerListHash` together with signer count and threshold; host devices are
reconciled by `hostDeviceBindingHash`.

---

## 1. Safe Signer Matrix

The table below is authoritative for the target threshold and signer set of each
Protocol Safe. Actual signer addresses and evidence of the applied configuration
are managed in the private evidence package.

The Signer columns represent physical signer slots. `A DFKK HW-1`, for example,
is a single hardware cold wallet signer managed by DeltaForesight K.K. (DFKK);
where several Safes carry `yes`, the same signer is included as an owner of each
of those Safes. `HW` denotes a signer operating a hardware cold wallet from a
signing-only PC; `HSM` denotes a signer operating through a dedicated Cloud HSM
tenant / IAM path. Actual signer addresses, host device bindings, and custody of
recovery material are fixed in the evidence package. In the table, `yes` means
the Safe uses that signer and `-` means it does not.

Protocol Safes share a common signer set A–E (`4` HW signers + `1` HSM signer).
In the Day-1 signing model, A–E consists of two DFKK keys (one signing block:
A/B) and three keys held by independent Ecosystem Partners (one block each:
C/D/E). The Foundation holds no Protocol signer key and is not a signing party.
This composition follows the signer-block governance defined in
[Day-1-Governance-Proposal-Execution-Policy](../../../../jp/protocol/launch/gates/Day-1-Governance-Proposal-Execution-Policy.md)
and the non-control requirements in
[Foundation-Entity-Setup-Requirements](../../../foundation/requirements/Foundation-Entity-Setup-Requirements.md).

The [Role Holder Separation Policy](../../../../jp/protocol/launch/gates/Mainnet-Role-Holder-Separation-Policy.md)
is authoritative for Safe contract addresses and role / custody separation; the
[Protocol Role Holder Manifest](../../../../jp/protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md)
is authoritative for expected addresses.

| Safe holder | envName / holderId | Threshold | A DFKK HW-1 | B DFKK HSM-1 | C Ecosystem Partner A HW-1 | D Ecosystem Partner B HW-1 | E Ecosystem Partner C HW-1 | G DFKK HW-2 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Admin multisig | `DF_WRITEOFF`, `DF_PRICE_FEED_OWNER`, `DF_TIMELOCK_PROPOSERS`, `DF_TIMELOCK_EXECUTORS`, `DF_TIMELOCK_CANCELLER`, `DF_BRIDGE_ADMIN` | `3-of-5` | yes | yes | yes | yes | yes | - |
| Guardian | `DF_GUARDIAN`, `DF_STRATEGY_OWNER` | `2-of-5` | yes | yes | yes | yes | yes | - |
| Allocator | `DF_ALLOCATOR` | `2-of-3` | yes | yes | - | - | - | yes |
| Treasury | `DF_TREASURY` | `3-of-5` | yes | yes | yes | yes | yes | - |
| PIL recipient | `DF_INTEREST_ROUTER_RECIPIENT` | `3-of-5` | yes | yes | yes | yes | yes | - |

Notes:

- Protocol Safes share A–E. What must be separated between Admin and Guardian is
  the Safe contract address, the threshold, and the on-chain role assignment;
  sharing the A–E hardware wallets / signer addresses is not itself a No-Go.
- Across Protocol Safes, **only two keys — A and B — are under DFKK control**, so
  for the `3-of-5` Admin / Treasury / PIL Safes, DFKK alone cannot reach the
  threshold (INV-1). Every combination that satisfies a threshold includes at
  least one signature from an independent Ecosystem Partner (INV-2). Guardian
  (`2-of-5`) is the exception: the two DFKK keys alone may trigger the enumerated
  protective actions, limited to reversible, conservative-direction ones. They
  cannot move funds to an arbitrary destination or outside protocol custody, and
  cannot unpause, upgrade, or mark down a loss.
- Guardian is a `2-of-5` Safe that prioritises emergency availability. Those same
  two signers alone cannot satisfy the Admin multisig's `3-of-5` quorum.
- Signer sharing between Treasury and PIL requires risk-owner approval, and only
  to the extent that one quorum does not control multiple custodies.
- DeltaForesight's Launch / Ops finance Safes are managed separately in the
  [Contributor Holder Manifest](../../../../jp/contributors/deltaforesight/manifests/Mainnet-Launch-Operations-Holder-Manifest.md),
  and the Foundation operating-asset Safe in the
  [Foundation Holder Manifest](../../../../jp/foundation/manifests/Foundation-Operating-Asset-Holder-Manifest.md).

## 2. Evidence / No-Go

For each Safe, the launch evidence package freezes and reconciles:

- The signer count / threshold from the Safe Signer Matrix, and `signerListHash`.
- `hostDeviceBindingHash`, corresponding to the device count / control domain /
  host device policy of signers A–G. The Cloud HSM tenant, IAM path, target role,
  custody, ops owner, last review date, and status are hashed; raw asset tags,
  serials, OS accounts, browser profile names, and MDM device IDs are not written
  to the public repository.
- The calldata package for any threshold / signer change, including the reason
  for the change, the signer count / threshold before and after, the execution
  ordering, and the post-state readback.
- For every 5-signer Safe other than Allocator, evidence that no single party
  controls 3 signers.

No-Go:

- The `yes` / `-` entries in the Safe Signer Matrix do not match the signer set in
  the evidence package, or a signer used by that Safe is not identified and
  hashed in the evidence package.
- The signer count or threshold does not match the expected value in the table.
- The Admin multisig and Guardian share a Safe contract address, or a threshold
  does not match the value in the Safe Signer Matrix.
- In a 5-signer Safe other than Allocator, DeltaForesight K.K. (DFKK) or a single
  Ecosystem Partner controls 3 or more signers.
- The Foundation holds a protocol signer key, or a Foundation operating-asset
  Safe is used as a `DF_*` protocol role holder.
- `DF_BRIDGE_ADMIN` executes `proposeBridgeMinter` against the real minter before
  the Bridge activation secrets / browser session have been recorded as evidence.
- A signing-only PC is shared with everyday use, signing is performed from a work
  PC or a personal / shared / unmanaged PC, or signing occurs during a remote
  desktop / remote control session.
- A seed phrase, private key, or raw recovery material is stored on a host device.
- A raw private key, seed phrase, raw signer list, hardware serial, Safe nonce,
  private RPC URL, API key, or raw host device identifier remains in public
  evidence.
