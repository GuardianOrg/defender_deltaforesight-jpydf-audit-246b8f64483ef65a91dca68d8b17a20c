# Mainnet Role Assignment Safe Threshold Policy

## 0. メタ情報

| 項目             | 値                                                                                                                                                                                      |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Status           | Draft                                                                                                                                                                                   |
| Domain           | Protocol Governance |
| Lifecycle        | Launch |
| Artifact Type    | Policy |
| Decision Authority | Protocol Governance |
| Maintainer       | DeltaForesight (Contributor) |
| 対象             | Ethereum mainnet Day 1のProtocol Safe threshold / signer count / signer control-domain / host device設計 |
| 文書の役割       | Protocol Role Holder ManifestのSafe holderについてtarget threshold、signer control block、host device方針を定める |
| 関連ドキュメント | [Protocol Role Holder Manifest](../manifests/Mainnet-Protocol-Role-Holder-Manifest.md) / [Role Holder Separation Policy](./Mainnet-Role-Holder-Separation-Policy.md) / [Governance](../../../Governance.md) / [Mainnet-Safe-Role-Assignment-Gate](./Mainnet-Safe-Role-Assignment-Gate.md) |

本書は Safe ごとの signer key holder / threshold / host device 方針を扱う。個人名、email、device serial、Safe nonce、raw signer list、host device の asset tag / serial / MDM ID は記録しない。signer list は launch evidence package で `signerListHash` と signer count / threshold により照合し、host device は `hostDeviceBindingHash` により照合する。

---

## 1. Safe Signer Matrix

各Protocol Safeのtarget threshold / signer setは次の表を正本とする。実signer addressと実行済み設定の証跡はprivate evidence packageで管理する。

Signer 列は物理 signer slot を表す。例えば `A DFKK HW-1` は DeltaForesight株式会社（DFKK）が管理する 1 つの hardware cold wallet signer であり、複数 Safe に `yes` が付く場合は同じ signer を各 Safe の owner に含める。`HW` は hardware cold wallet を署名専用 PC から操作する signer、`HSM` は dedicated Cloud HSM tenant / IAM path で操作する signer を意味する。実 signer address / host device binding / recovery material custody は evidence package で固定する。表中の `yes` はその Safe がその signer を使うこと、`-` は使わないことを表す。

Protocol系Safeのsigner setは共通のA-E（`4` HW signers + `1` HSM signer）とする。Day 1署名モデルでは、A-EはDFKKの2鍵（1署名ブロック：A/B）と独立Ecosystem Partnerの3鍵（各1ブロック：C/D/E）で構成し、FoundationはProtocol signer鍵を保持せず署名主体にならない。この構成はsigner-block governanceを定める[Day-1-Governance-Proposal-Execution-Policy](./Day-1-Governance-Proposal-Execution-Policy.md)と[Foundation-Entity-Setup-Requirements](../../../foundation/requirements/Foundation-Entity-Setup-Requirements.md)のnon-control要件に従う。

Safe contract addressとrole / custodyの分離は[Role Holder Separation Policy](./Mainnet-Role-Holder-Separation-Policy.md)、expected addressは[Protocol Role Holder Manifest](../manifests/Mainnet-Protocol-Role-Holder-Manifest.md)を正本とする。

| Safe holder | envName / holderId | Threshold | A DFKK HW-1 | B DFKK HSM-1 | C Ecosystem Partner A HW-1 | D Ecosystem Partner B HW-1 | E Ecosystem Partner C HW-1 | G DFKK HW-2 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Admin multisig | `DF_WRITEOFF`, `DF_PRICE_FEED_OWNER`, `DF_TIMELOCK_PROPOSERS`, `DF_TIMELOCK_EXECUTORS`, `DF_TIMELOCK_CANCELLER`, `DF_BRIDGE_ADMIN` | `3-of-5` | yes | yes | yes | yes | yes | - |
| Guardian | `DF_GUARDIAN`, `DF_STRATEGY_OWNER` | `2-of-5` | yes | yes | yes | yes | yes | - |
| Allocator | `DF_ALLOCATOR` | `2-of-3` | yes | yes | - | - | - | yes |
| Treasury | `DF_TREASURY` | `3-of-5` | yes | yes | yes | yes | yes | - |
| PIL recipient | `DF_INTEREST_ROUTER_RECIPIENT` | `3-of-5` | yes | yes | yes | yes | yes | - |

注記:

- Protocol 系 Safe は A-E を共有する。Admin / Guardian の分離対象は Safe contract address、threshold、on-chain role assignment であり、A-E の hardware wallet / signer address 共有自体は No-Go ではない。
- Protocol 系 Safe で **DFKK 支配鍵は A/B の 2 鍵のみ**であり、`3-of-5` の Admin / Treasury / PIL では DFKK 単独で threshold に到達できない（INV-1）。いかなる threshold 充足組合せにも独立 Ecosystem Partner の署名が最低 1 つ含まれる（INV-2）。Guardian（`2-of-5`）は例外で、可逆・保守方向の列挙済み protective action に限り DFKK 2 鍵で単独発動できる。任意宛先・protocol custody 外への資金移動、unpause、upgrade、損失 markdown はできない。
- Guardian は emergency availability を優先する `2-of-5` Safe とする。同じ 2 signers だけでは Admin multisig の `3-of-5` quorum は満たせない。
- Treasury / PIL間のsigner共有は、同じquorumが複数custodyを支配しない範囲でrisk-owner approvalを取る。
- DeltaForesightのLaunch / Ops finance Safeは[Contributor Holder Manifest](../../../contributors/deltaforesight/manifests/Mainnet-Launch-Operations-Holder-Manifest.md)、Foundation operating-asset Safeは[Foundation Holder Manifest](../../../foundation/manifests/Foundation-Operating-Asset-Holder-Manifest.md)で別管理する。

## 2. Evidence / No-Go

各 Safe は launch evidence package で次を凍結・照合する。

- Safe Signer Matrixのsigner count / threshold、`signerListHash`。
- Signer A-G の device count / control domain / host device policy に対応する `hostDeviceBindingHash`。Cloud HSM tenant・IAM path / 対象 role / custody / ops owner / last review date / status を hash 化し、raw asset tag、serial、OS account、browser profile 名、MDM device ID は public repo に書かない。
- threshold / signer change の calldata package。変更理由、変更前後の signer count / threshold、execution ordering、post-state readback を含める。
- Allocator以外の5-signer Safeでは、単一partyが3 signersを支配していないことの証跡。

No-Go:

- Safe Signer Matrix の `yes` / `-` と evidence package の signer set が一致しない、またはその Safe が使う signer が evidence package で特定・hash 化されていない。
- signer count または threshold が表の expected value と一致しない。
- Admin multisig と Guardian が同じ Safe contract address になっている、または threshold が Safe Signer Matrix の値と一致しない。
- Allocator以外の5-signer Safeで、DeltaForesight株式会社（DFKK）または単一のEcosystem Partnerが3 signers以上を支配している。
- Foundationが protocol signer 鍵を保持している、または Foundation operating-asset Safe を `DF_*` protocol role holder として使っている。
- `DF_BRIDGE_ADMIN` が real minter に対して `proposeBridgeMinter` を実行する前に Bridge activation 関連 secret / browser session を evidence 化していない。
- 署名専用 PC が日常用途と共用されている、作業用 PC・個人/共有/未管理 PC から署名している、または remote desktop / remote control 中に署名している。
- host device に seed phrase / private key / raw recovery material が保存されている。
- raw private key、seed phrase、raw signer list、hardware serial、Safe nonce、private RPC URL、API key、host device raw identifier が public evidence に残っている。
