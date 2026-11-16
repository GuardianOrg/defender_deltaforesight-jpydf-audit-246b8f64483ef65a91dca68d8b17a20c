# Mainnet Role Holder Separation Policy

| Field | Value |
| --- | --- |
| Domain | Protocol Governance |
| Lifecycle | Launch |
| Artifact Type | Policy |
| Decision Authority | Protocol Governance |
| Maintainer | DeltaForesight (Contributor) |
| Status | Draft |

## 1. Purpose

Ethereum mainnet Day 1のProtocol role、DeltaForesightのlaunch-operation custody、Foundation operating assetsを同一holderへ混在させないための判断条件を定める。具体的なaddressはDomain別Manifest、Safe構成・readback・Go / No-Go手順は[`Mainnet-Safe-Role-Assignment-Gate.md`](./Mainnet-Safe-Role-Assignment-Gate.md)へ分離する。

## 2. Required separation

| Rule | Requirement | Reason |
| --- | --- | --- |
| Admin != Guardian | Admin multisigとGuardianは別Safe contract addressとする | 不正writeoff等に対する即時mitigation pathを残す |
| Timelock CANCELLER = Admin | `DF_TIMELOCK_CANCELLER`はAdmin multisigが保持する | proposer / cancellerのDay 1構成を固定する |
| Treasury != PIL recipient | `DF_TREASURY`と`DF_INTEREST_ROUTER_RECIPIENT`は別Safe contract addressとする | 担保運用益とPIL原資のcustody / accountingを分離する |
| Allocator != Launch / Ops finance | `DF_ALLOCATOR`とDeltaForesightの`BOOTSTRAP_BORROWER_OWNER` / `LP_OWNER` / `SP_SEED_SOURCE_OWNER`は別Safe contract addressとする | Protocol roleとContributor自己資金custodyを分離する |
| Protocol Governance != Contributor custody | Protocol Admin / Guardian / Treasury / PIL recipientをDeltaForesight launch-operation Safeで代替しない | decision authorityと自己資金custodyのDomainが異なる |
| Protocol Governance != Foundation | Foundation operating-asset Safeを`DF_*` Protocol role holder、Protocol Treasury、PIL recipientとして使わない | Protocol GovernanceとFoundation Governanceの権限系統が異なる |
| Bridge admin isolation | `DF_BRIDGE_ADMIN`はcontract holderとし、deployer、token owner、future bridge minterと同一にしない | dormant bridge権限とdeploy権限・発行権限を分離する |
| Deployer retires | deployerはhandover後にprivileged roleを保持しない | deploy-time権限集中を一時的なものに限定する |

## 3. Source manifests

- Protocol role holder: [`Mainnet-Protocol-Role-Holder-Manifest.md`](../manifests/Mainnet-Protocol-Role-Holder-Manifest.md)
- DeltaForesight launch operation holder: [`Mainnet-Launch-Operations-Holder-Manifest.md`](../../../contributors/deltaforesight/manifests/Mainnet-Launch-Operations-Holder-Manifest.md)
- Foundation operating-asset holder: [`Foundation-Operating-Asset-Holder-Manifest.md`](../../../foundation/manifests/Foundation-Operating-Asset-Holder-Manifest.md)

Manifest間で同一addressが禁止ruleに該当する場合、GateはNo-Goとする。Foundation側のOA・Member・signer要件はFoundation Governanceの正本で判断し、本Policyは変更しない。
