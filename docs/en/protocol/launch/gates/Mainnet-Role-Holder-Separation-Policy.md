# Mainnet Role Holder Separation Policy

> Support translation. The Japanese source document
> [`documents/jp/protocol/launch/gates/Mainnet-Role-Holder-Separation-Policy.md`](../../../../jp/protocol/launch/gates/Mainnet-Role-Holder-Separation-Policy.md)
> is authoritative if this file conflicts with it.

| Field | Value |
| --- | --- |
| Domain | Protocol Governance |
| Lifecycle | Launch |
| Artifact Type | Policy |
| Decision Authority | Protocol Governance |
| Maintainer | DeltaForesight (Contributor) |
| Status | Draft |

## 1. Purpose

Defines the criteria that keep Ethereum mainnet Day-1 Protocol roles,
DeltaForesight's launch-operation custody, and Foundation operating assets from
being mixed into the same holder. Specific addresses live in the per-Domain
Manifests, and Safe composition, readback, and the Go / No-Go procedure are
separated into
[`Mainnet-Safe-Role-Assignment-Gate.md`](./Mainnet-Safe-Role-Assignment-Gate.md).

## 2. Required separation

| Rule | Requirement | Reason |
| --- | --- | --- |
| Admin != Guardian | The Admin multisig and Guardian are different Safe contract addresses | Preserves an immediate mitigation path against an improper writeoff and similar |
| Timelock CANCELLER = Admin | `DF_TIMELOCK_CANCELLER` is held by the Admin multisig | Fixes the Day-1 proposer / canceller composition |
| Treasury != PIL recipient | `DF_TREASURY` and `DF_INTEREST_ROUTER_RECIPIENT` are different Safe contract addresses | Separates custody and accounting of collateral yield from PIL funding |
| Allocator != Launch / Ops finance | `DF_ALLOCATOR` and DeltaForesight's `BOOTSTRAP_BORROWER_OWNER` / `LP_OWNER` / `SP_SEED_SOURCE_OWNER` are different Safe contract addresses | Separates Protocol roles from Contributor own-funds custody |
| Protocol Governance != Contributor custody | Protocol Admin / Guardian / Treasury / PIL recipient are not substituted by a DeltaForesight launch-operation Safe | Decision authority and own-funds custody are different Domains |
| Protocol Governance != Foundation | A Foundation operating-asset Safe is not used as a `DF_*` Protocol role holder, as the Protocol Treasury, or as the PIL recipient | Protocol Governance and Foundation Governance are different lines of authority |
| Bridge admin isolation | `DF_BRIDGE_ADMIN` is a contract holder and is not the same as the deployer, the token owner, or a future bridge minter | Separates dormant bridge authority from deploy and issuance authority |
| Deployer retires | The deployer holds no privileged role after handover | Keeps the deploy-time concentration of authority temporary |

## 3. Source manifests

- Protocol role holder: [`Mainnet-Protocol-Role-Holder-Manifest.md`](../manifests/Mainnet-Protocol-Role-Holder-Manifest.md)
- DeltaForesight launch operation holder: [`Mainnet-Launch-Operations-Holder-Manifest.md`](../../../../jp/contributors/deltaforesight/manifests/Mainnet-Launch-Operations-Holder-Manifest.md)
- Foundation operating-asset holder: [`Foundation-Operating-Asset-Holder-Manifest.md`](../../../../jp/foundation/manifests/Foundation-Operating-Asset-Holder-Manifest.md)

Where the same address appears across Manifests in a way that triggers a
prohibited rule, the Gate is No-Go. Foundation-side OA, Member, and signer
requirements are judged against the authoritative Foundation Governance
documents; this Policy does not change them.
