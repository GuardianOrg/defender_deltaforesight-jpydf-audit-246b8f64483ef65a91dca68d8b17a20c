# Mainnet Timelock Deploy Policy

## 0. メタ情報

| 項目   | 値                                                                                                                                                                                                                                                                             |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Status | Active                                                                                                                                                                                                                                                                         |
| Date   | 2026-06-29                                                                                                                                                                                                                                                                     |
| Owner  | DeltaForesight                                                                                                                                                                                                                                                                 |
| 対象   | Common GOV Timelock (`DF_TIMELOCK`) の deploy / role configuration 方針                                                                                                                                                                                                        |
| 決定   | 共通 GOV Timelock は protocol deploy より先に構成し、`DF_TIMELOCK` として handover script へ渡す。delay値は [Day1 Parameter Manifest](../../../Parameters.md) `PRM-GOV-COMMON-TIMELOCK-DELAY`、holder構成は [Protocol Role Holder Manifest](../../../protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md) に従う。 |
| 実手順 | [Mainnet-Timelock-Deploy-Runbook](./Mainnet-Timelock-Deploy-Runbook.md)                                                                                                                                                                                              |

---

## 1. 結論

`jpydf-v2` の contracts / deploy scripts は TimelockController 本体を deploy しない。`DF_TIMELOCK` は既存の external address として受け取り、Vault / dToken / Strategy upgrader / InterestRouter owner などの final holder に使う。

したがって、Timelock 本体の safety は本 policy と [Mainnet-Timelock-Deploy-Runbook](./Mainnet-Timelock-Deploy-Runbook.md) で担保する。

最終 state:

| Item | Value source |
| --- | --- |
| Implementation | OpenZeppelin `TimelockController` v4.9.5 or reviewed equivalent |
| `minDelay` | `PRM-GOV-COMMON-TIMELOCK-DELAY` |
| PROPOSER | `PRM-GOV-TIMELOCK-PROPOSER-HOLDER` |
| EXECUTOR | `PRM-GOV-TIMELOCK-EXECUTOR-HOLDER` |
| CANCELLER | `PRM-GOV-TIMELOCK-CANCELLER-HOLDER` |
| Admin role | `PRM-GOV-TIMELOCK-EXTERNAL-ADMIN` |

## 2. Boundary

`VerifyDFGovernanceHandover` checks protocol-side holder assignment after handover. It does not assert:

- Timelock `minDelay`;
- PROPOSER / EXECUTOR / CANCELLER holders;
- CANCELLER = Admin multisig;
- external admin renounce;
- absence of open executor.

これらは mainnet launch prerequisites であり、本 policy、runbook、[Mainnet-Safe-Role-Assignment-Gate](./Mainnet-Safe-Role-Assignment-Gate.md) が要求する evidence package で確認する。

## 3. Design Decisions

### 3.1 Admin Multisig as PROPOSER / EXECUTOR / CANCELLER

Admin multisig は GOV operation を schedule し、共通 delay 後に execute する。OpenZeppelin `TimelockController` は constructor で proposer に `CANCELLER_ROLE` も grant するため、Day-1 は schedule と cancel を同じ governance authority に置く。

`EXECUTOR_ROLE` は `address(0)` に付与しない。open execution にすると delay expiry 後の execution timing を third party が選べるためである。

### 3.2 Accepted Risk: No Independent Canceller

独立cancellerを置かない受容リスクとholder分離条件は[Role Holder Separation Policy](./Mainnet-Role-Holder-Separation-Policy.md)が持つ。

### 3.3 No External Admin Remains

Deployer が admin を保持できるのは setup 中だけである。Timelock role readback 後に admin を renounce する。以後の role / delay change は scheduled Timelock operation を通す。

## 4. Deploy Timing

Timelock は protocol mainnet deploy / handover の前に deploy する。

```text
Admin / Guardian Safe creation
  -> TimelockController deploy
  -> Timelock role readback
  -> external admin renounce
  -> Timelock deploy runbook verification
  -> freeze DF_TIMELOCK in Protocol holder Manifest and deploy env
  -> jpydf-v2 Deploy / Prepare / Accept / Verify
```

## 5. Launch No-Go

Any of the following blocks protocol deploy / handover:

| No-Go                                        | Reason                                                       |
| -------------------------------------------- | ------------------------------------------------------------ |
| PROPOSER / EXECUTOR / CANCELLER が `PRM-GOV-*` と不一致 | Timelock role holder mismatch.                     |
| `EXECUTOR_ROLE` is granted to `address(0)`             | Open execution not accepted for Day-1 governance.  |
| `getMinDelay()` が `PRM-GOV-COMMON-TIMELOCK-DELAY` と不一致 | Parameter mismatch.                                |
| External deployer/admin still has admin role           | Delay-free role / delay mutation remains possible. |
| Admin multisig is a hot EOA                            | Holder policy violation.                           |
| #1 Admin or #2 Timelock remains draft                  | Role evidence is not frozen.                       |

## 6. References

- [Mainnet Protocol Role Holder Manifest](../manifests/Mainnet-Protocol-Role-Holder-Manifest.md)
- [Mainnet Role Holder Separation Policy](./Mainnet-Role-Holder-Separation-Policy.md)
- [Mainnet-Role-Assignment-Safe-Threshold-Policy](./Mainnet-Role-Assignment-Safe-Threshold-Policy.md)
- [Mainnet-Timelock-Deploy-Runbook](./Mainnet-Timelock-Deploy-Runbook.md)
- [Governance](../../../Governance.md)
- [Mainnet-Governance-Handover-Runbook](./Mainnet-Governance-Handover-Runbook.md)
