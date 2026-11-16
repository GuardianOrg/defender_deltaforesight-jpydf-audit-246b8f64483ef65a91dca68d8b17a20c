# DeltaForesight Mainnet Launch Operations Holder Manifest

| Field | Value |
| --- | --- |
| Domain | Contributor: DeltaForesight |
| Lifecycle | Launch |
| Artifact Type | Manifest |
| Decision Authority | DeltaForesight |
| Maintainer | DeltaForesight |
| Environment | Ethereum mainnet (`chainId=1`) |
| Manifest State | Candidate |
| Status | Draft |

## 1. Scope

本Manifestは、DeltaForesight株式会社が自己資金とlaunch operationのために管理するholderを記録する。Protocol role holderではなく、Foundation operating assetsも扱わない。

## 2. Candidate holder values

| Physical holder | Holder ID / consumer | Expected address | Expected control | State |
| --- | --- | --- | --- | --- |
| Deployer | `DEPLOYER`, pre-handover `DF_CURRENT_ADMIN`, deploy-time `DF_INTEREST_ROUTER_OWNER` | `<pending>` | hardware-backed signer | `draft` |
| Launch / Ops finance Safe | `BOOTSTRAP_BORROWER_OWNER`, `LP_OWNER`, `SP_SEED_SOURCE_OWNER` | `0xAb1c63a49E950619d983834CFDE006CDB643a5C1` | `2-of-3` DeltaForesight-controlled Safe | `address-fixed` |
| Liquidator bot | `LIQUIDATOR_GAS_WALLET` | `<pending>` | capped bot wallet | `draft` |
| Keeper bot | `KEEPER_OPS_WALLET` | `<pending>` | limited keeper wallet / bot wallet | `draft` |

`DF_ALLOCATOR`はDeltaForesightが運用を担当してもProtocol roleであるため、本Manifestへ複製せず[`Mainnet-Protocol-Role-Holder-Manifest.md`](../../../protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md)で管理する。

## 3. Reconciliation

自己資金額と用途は[`Day1-Self-BS-Launch-Commitment.md`](../commitments/Day1-Self-BS-Launch-Commitment.md)、holder separationは[`Mainnet-Role-Holder-Separation-Policy.md`](../../../protocol/launch/gates/Mainnet-Role-Holder-Separation-Policy.md)、実行前のaddress / consumer照合は[`Mainnet-Safe-Role-Assignment-Gate.md`](../../../protocol/launch/gates/Mainnet-Safe-Role-Assignment-Gate.md)に従う。
