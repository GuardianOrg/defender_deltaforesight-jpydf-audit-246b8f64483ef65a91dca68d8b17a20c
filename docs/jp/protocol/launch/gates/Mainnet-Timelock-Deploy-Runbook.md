# Mainnet Timelock Deploy Runbook

> 共通 GOV Timelock (`DF_TIMELOCK`) を deploy・構成・検証し、mainnet deploy / governance handover に渡すための手順。`MIN_DELAY`は [Day1 Parameter Manifest](../../../Parameters.md) `PRM-GOV-COMMON-TIMELOCK-DELAY`、holder構成は [Protocol Role Holder Manifest](../../../protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md)、設計判断は [Mainnet-Timelock-Deploy-Policy](./Mainnet-Timelock-Deploy-Policy.md) を正本とする。

本 runbook は private key / seed phrase を扱わない。署名は hardware wallet、KMS/HSM、または managed custody 経由で実行する。

---

## 0. Placeholders

| Placeholder       | 意味                                                           |
| ----------------- | -------------------------------------------------------------- |
| `$ADMIN_SAFE`     | Admin multisig. PROPOSER / EXECUTOR / CANCELLER holder.        |
| `$GUARDIAN_SAFE`  | Guardian Safe, used for separation check.                      |
| `$DEPLOYER`       | Hardware-backed deployer signer. Temporary admin during setup. |
| `$TIMELOCK`       | Deployed TimelockController address.                           |
| `$RPC`            | Mainnet RPC URL.                                               |
| `$MIN_DELAY`      | `PRM-GOV-COMMON-TIMELOCK-DELAY` の秒数。                       |

## 1. Pre-Deploy Checks

- [ ] `$ADMIN_SAFE` and `$GUARDIAN_SAFE` are finalized under [Mainnet-Protocol-Role-Holder-Manifest](../../../protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md).
- [ ] `$ADMIN_SAFE != $GUARDIAN_SAFE`.
- [ ] `$DEPLOYER` uses hardware / KMS / managed signing and no plaintext private key.
- [ ] OpenZeppelin `TimelockController` の version と bytecode を記録済み。
- [ ] `$MIN_DELAY` が上記入力と一致する。

## 2. Deploy TimelockController

Constructor:

```solidity
constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
```

引数:

| Argument    | Value                                   |
| ----------- | --------------------------------------- |
| `minDelay`  | `$MIN_DELAY`                             |
| `proposers` | `[$ADMIN_SAFE]`                         |
| `executors` | `[$ADMIN_SAFE]`                         |
| `admin`     | `$DEPLOYER`, renounced after role setup |

Example command:

```bash
forge create \
  --rpc-url "$RPC" \
  --account deployer-hw \
  lib/openzeppelin-contracts/contracts/governance/TimelockController.sol:TimelockController \
  --constructor-args \
    "$MIN_DELAY" \
    "[$ADMIN_SAFE]" \
    "[$ADMIN_SAFE]" \
    "$DEPLOYER"
```

`Deployed to:` address を `$TIMELOCK` として記録する。

## 3. Read Role Constants

```bash
cast call "$TIMELOCK" "PROPOSER_ROLE()(bytes32)" --rpc-url "$RPC"
cast call "$TIMELOCK" "EXECUTOR_ROLE()(bytes32)" --rpc-url "$RPC"
cast call "$TIMELOCK" "CANCELLER_ROLE()(bytes32)" --rpc-url "$RPC"
cast call "$TIMELOCK" "TIMELOCK_ADMIN_ROLE()(bytes32)" --rpc-url "$RPC"
```

出力を `$PROPOSER_ROLE`、`$EXECUTOR_ROLE`、`$CANCELLER_ROLE`、`$ADMIN_ROLE` として扱う。

## 4. Verify Timelock Roles

OpenZeppelin `TimelockController` は construction 時に proposer へ `CANCELLER_ROLE` も grant する。Day-1 はこれを維持し、Admin multisig が PROPOSER / EXECUTOR / CANCELLER を保持する。

```bash
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$PROPOSER_ROLE" "$ADMIN_SAFE" --rpc-url "$RPC"
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$EXECUTOR_ROLE" "$ADMIN_SAFE" --rpc-url "$RPC"
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$CANCELLER_ROLE" "$ADMIN_SAFE" --rpc-url "$RPC"
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$EXECUTOR_ROLE" 0x0000000000000000000000000000000000000000 --rpc-url "$RPC"
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$CANCELLER_ROLE" "$GUARDIAN_SAFE" --rpc-url "$RPC"
```

期待値: Admin の PROPOSER / EXECUTOR / CANCELLER が `true`、open executor と Guardian CANCELLER が `false`。

## 5. Renounce External Admin

```bash
cast send "$TIMELOCK" "renounceRole(bytes32,address)" "$ADMIN_ROLE" "$DEPLOYER" \
  --rpc-url "$RPC" --account deployer-hw
```

この後の role / delay change は scheduled Timelock operation を通す必要がある。

## 6. Final Verification

Let `$P=$ADMIN_SAFE` and `$D=$DEPLOYER`.

```bash
# delay
cast call "$TIMELOCK" "getMinDelay()(uint256)" --rpc-url "$RPC"

# proposer / executor
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$PROPOSER_ROLE" "$P" --rpc-url "$RPC"
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$EXECUTOR_ROLE" "$P" --rpc-url "$RPC"
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$EXECUTOR_ROLE" 0x0000000000000000000000000000000000000000 --rpc-url "$RPC"

# canceller
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$CANCELLER_ROLE" "$P" --rpc-url "$RPC"
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$CANCELLER_ROLE" "$GUARDIAN_SAFE" --rpc-url "$RPC"

# admin
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$ADMIN_ROLE" "$TIMELOCK" --rpc-url "$RPC"
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$ADMIN_ROLE" "$D" --rpc-url "$RPC"
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$ADMIN_ROLE" "$P" --rpc-url "$RPC"
```

期待値:

| Check                                        | Expected |
| -------------------------------------------- | -------- |
| `getMinDelay()`                              | `$MIN_DELAY` |
| PROPOSER / EXECUTOR = `$ADMIN_SAFE`          | `true`   |
| EXECUTOR = `address(0)`                      | `false`  |
| CANCELLER = `$ADMIN_SAFE`                    | `true`   |
| CANCELLER = `$GUARDIAN_SAFE`                 | `false`  |
| ADMIN = `$TIMELOCK`                          | `true`   |
| ADMIN = `$DEPLOYER` / `$ADMIN_SAFE`          | `false`  |

いずれかが mismatch する場合、[Mainnet-Timelock-Deploy-Policy](./Mainnet-Timelock-Deploy-Policy.md) に基づき launch No-Go とする。

## 7. Handoff

1. Freeze `$TIMELOCK` as `DF_TIMELOCK`.
2. Update the launch evidence package for #1 Admin and #2 Timelock.
3. Attach the verification output from §6.
4. Continue with [Mainnet-Deploy-Env-Freeze-Runbook](./Mainnet-Deploy-Env-Freeze-Runbook.md), [Mainnet-Governance-Handover-Runbook](./Mainnet-Governance-Handover-Runbook.md), and `VerifyDFGovernanceHandover`.
