# Ethereum Mainnet Day 1 Protocol Role Holder Manifest

| Field | Value |
| --- | --- |
| Domain | Protocol Governance |
| Lifecycle | Launch |
| Artifact Type | Manifest |
| Decision Authority | Protocol Governance |
| Maintainer | DeltaForesight (Contributor) |
| Environment | Ethereum mainnet (`chainId=1`) |
| Manifest State | Candidate |
| Status | Draft |

## 1. Scope

本Manifestは、Ethereum mainnet Day 1でProtocol roleを保持するcontractとSafeのexpected addressを記録する。権限の意味と対象関数は[`Governance.md`](../../../Governance.md)、holder間の分離条件は[`Mainnet-Role-Holder-Separation-Policy.md`](../gates/Mainnet-Role-Holder-Separation-Policy.md)、Safe構成とreadback条件は[`Mainnet-Safe-Role-Assignment-Gate.md`](../gates/Mainnet-Safe-Role-Assignment-Gate.md)を正本とする。

DeltaForesightの自己資金・launch operation holderとFoundation operating-asset holderはscope外であり、それぞれ別Manifestで管理する。

## 2. Candidate holder values

| Physical holder | Holder ID / env | Expected address | State |
| --- | --- | --- | --- |
| Admin multisig | `DF_WRITEOFF`, `DF_PRICE_FEED_OWNER`, `DF_TIMELOCK_PROPOSERS`, `DF_TIMELOCK_EXECUTORS`, `DF_TIMELOCK_CANCELLER`, `DF_BRIDGE_ADMIN` | `0xA8331cFA52BC67a468D6126b4A18419C6D830b4E` | `address-fixed` |
| Timelock | `DF_TIMELOCK`, `DF_STRATEGY_UPGRADER` | `<pending>` | `draft` |
| Guardian | `DF_GUARDIAN`, `DF_STRATEGY_OWNER` | `0xC89592b35278B6Bbba2b710acd463E7A3C8D0Eb0` | `address-fixed` |
| Allocator | `DF_ALLOCATOR` | `0x34b8Edd6E6B8032cCDb930722486edd2Ac9134B5` | `address-fixed` |
| Treasury | `DF_TREASURY` | `0x739b9e6BeB4C278DFc327523880fdBafe4BD129D` | `address-fixed` |
| PIL recipient | `DF_INTEREST_ROUTER_RECIPIENT` | `0x3CC1e7987a1459c7374AfBAEe104d1D65F07E658` | `address-fixed` |

`address-fixed`はchecksum addressの候補が承認済みであることだけを示す。Safe code、owner、threshold、module、guard、Timelock role、on-chain assignmentの検証完了を意味しない。`<pending>`を含む間、およびGateの`frozen`条件を満たすまではlaunchに使用しない。

## 3. Reconciliation

最終freezeでは、この表を手入力でcurrent stateへ上書きしない。Gateが生成する`holder-address-book.csv`、deploy / handover env、`deployment-manifest.json`、on-chain readbackを同一candidate commitとblockで照合し、そのEvidenceを保持する。mainnet activation後のcurrent stateはon-chain stateを正とする。
