# Foundation Operating-Asset Holder Manifest

| Field | Value |
| --- | --- |
| Domain | Foundation |
| Lifecycle | Launch |
| Artifact Type | Manifest |
| Decision Authority | Foundation Governance |
| Maintainer | Foundation service provider |
| Environment | Ethereum mainnet (`chainId=1`) |
| Manifest State | Candidate |
| Status | Draft |

## 1. Scope

本ManifestはFoundation operating assetsの受領・管理に用いるexpected Safe addressを記録する。FoundationのMember、OA、signer、threshold、法人内部承認は[`Foundation-Entity-Member-Signer-Requirements.md`](../requirements/Foundation-Entity-Member-Signer-Requirements.md)とrestricted corporate recordを正本とし、本Manifestへ複製しない。

## 2. Candidate holder value

| Physical holder | Holder ID / use | Expected address | Candidate threshold | State |
| --- | --- | --- | --- | --- |
| Foundation operating-asset Safe | `FOUNDATION_OPERATING_SAFE`; future `foundationSafe` recipient | `0x585842936dFdCab5b2F83627A5eDDe763c2A7b7D` | `3-of-5`（OA / Foundation Governance approval pending） | `address-fixed` |

このSafeはDay 1の`DF_*` Protocol role、Protocol Treasury、DeltaForesightのlaunch-operation custodyを保持しない。将来`Treasury.sol`の`foundationSafe`としてactivationする場合は、その時点のFoundation Governance承認とon-chain Evidenceで確定する。

## 3. State boundary

`address-fixed`はSafeの法人内部承認、signer / threshold review、OA evidence、on-chain activationの完了を意味しない。それらを満たすまで本ManifestはCandidateである。
