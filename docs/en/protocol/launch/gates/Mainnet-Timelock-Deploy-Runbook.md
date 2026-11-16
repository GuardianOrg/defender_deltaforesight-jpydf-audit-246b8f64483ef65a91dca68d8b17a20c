# Mainnet Production Timelock Deploy Runbook

> Support translation. The Japanese source document
> [`documents/jp/protocol/launch/gates/Mainnet-Timelock-Deploy-Runbook.md`](../../../../jp/protocol/launch/gates/Mainnet-Timelock-Deploy-Runbook.md)
> is authoritative if this file conflicts with it.
>
> Keep the pilot / canary Timelock
> `0xEd33edB1eA442475eFd076e1AE2C9da9EdaB86f6` at `minDelay=300`. Production
> must not use that address. Deploy a separate OZ v4.9.5 Timelock with
> `MIN_DELAY=43200` in its constructor.

This runbook does not handle private keys or seed phrases. Sign with a hardware
wallet, KMS/HSM, or managed custody. Broadcast only during a ceremony for which
Protocol Governance separately approved the production deployment.

| Field | Value |
| --- | --- |
| Status | Active |
| Domain | Protocol Governance |
| Lifecycle | Launch |
| Artifact Type | Runbook |
| Decision Authority | Protocol Governance |
| Maintainer | DeltaForesight (Contributor) |
| Visibility | Public |

---

## 0. Placeholders

| Placeholder | Meaning |
| --- | --- |
| `$ADMIN_SAFE` | Admin multisig; PROPOSER / EXECUTOR / CANCELLER holder. |
| `$GUARDIAN_SAFE` | Guardian Safe, used for the separation check. |
| `$DEPLOYER` | Public address of the hardware-backed deployer signer. |
| `$TIMELOCK` | Fresh-deployed production Timelock address. |
| `$DEPLOY_TX` | Production Timelock creation transaction hash. |
| `$RPC` | Ethereum mainnet RPC URL. |
| `$MIN_DELAY` | `43200`. |
| `$CANDIDATE_COMMIT` | Launch-candidate repository commit SHA. |

## 1. Pre-deploy checks

- [ ] `$CANDIDATE_COMMIT` matches the candidate SHA in the evidence package.
- [ ] The OpenZeppelin submodule is pinned to tag `v4.9.5` / commit
  `bd325d56b4c62c9c5c1aff048c37c6bb18ac0290`.
- [ ] `$ADMIN_SAFE == 0xA8331cFA52BC67a468D6126b4A18419C6D830b4E`.
- [ ] For every production Safe used by Admin / PriceFeedOwner, Guardian,
  Allocator, Treasury, and PIL recipient, the approved pre-deploy-hardening
  MultiSend receipt succeeded and the `getOwners()` / `getThreshold()` /
  signer-list-hash readback matches the target in the
  [Safe Threshold Policy](./Mainnet-Role-Assignment-Safe-Threshold-Policy.md).
  Do not deploy the production Timelock if any is unexecuted or mismatched.
- [ ] `$ADMIN_SAFE != $GUARDIAN_SAFE`.
- [ ] Only `$DEPLOYER`'s public address is passed through the environment; no
  signing key is placed in a plaintext environment variable.
- [ ] `$MIN_DELAY == 43200`.
- [ ] Read back `getMinDelay()==300` from the pilot / canary Timelock and confirm
  that no delay-change operation has been scheduled.
- [ ] Build the production artifact with
  `FOUNDRY_PROFILE=production-timelock` and no compiler metadata.
- [ ] Use the `production-timelock` profile only for this Timelock deployment,
  not for the protocol deployment.
- [ ] Production Timelock deployment has separate approval.

The read-only verified pilot history baseline contains zero `CallScheduled`
events from deploy block `25789231` through safe block `25856179` (hash
`0x014121edad170d52fe6449404280af297e52b6d38ecf9a2fc3b727a106ce3f67`).
`check-mainnet-canary-state` pins that checkpoint hash, scans later history in
10,000-block chunks, and rejects schedules targeting the pilot Timelock itself.

Record the candidate and submodule at repository root, then run the remaining
commands from `contracts/`.

```bash
git rev-parse HEAD
git submodule status contracts/lib/openzeppelin-contracts
cd contracts
cast chain-id --rpc-url "$RPC"
FOUNDRY_PROFILE=production-timelock forge build script/DeployMainnetProductionTimelock.s.sol
FOUNDRY_PROFILE=production-timelock forge inspect --use 0.8.24 TimelockController bytecode | cast keccak
FOUNDRY_PROFILE=production-timelock forge inspect --use 0.8.24 TimelockController deployedBytecode | cast keccak
```

Expected values are repository SHA = `$CANDIDATE_COMMIT`, submodule SHA =
`bd325d56b4c62c9c5c1aff048c37c6bb18ac0290`, chain ID = `1`, creation-code
hash = `0xb63901a8ebd9631adedb9726668993ad7857d8a765ab21994e5b9d5d381c50b9`,
and runtime-code hash =
`0xfbb8dca0ef620c28593dafd8ead5162f233db640a9ebfdc4d47a7920cc06b2af`.
Pin the compiler to Solidity 0.8.24 and the profile to `production-timelock`;
record both hashes in private evidence. Do not deploy on any mismatch.

## 2. Dry-run and deploy

`DeployMainnetProductionTimelock.s.sol` creates only this constructor state:

| Argument | Value |
| --- | --- |
| `minDelay` | `43200` |
| `proposers` | `[$ADMIN_SAFE]` |
| `executors` | `[$ADMIN_SAFE]` |
| `admin` | `address(0)` |

The OZ constructor grants admin to the Timelock itself and PROPOSER / EXECUTOR /
CANCELLER to the Admin Safe. It never creates deployer admin, so no post-deploy
renounce transaction is needed.

Simulate without broadcasting first.

```bash
FOUNDRY_PROFILE=production-timelock \
DF_MAINNET_PRODUCTION_TIMELOCK_ACK=JPYDF_MAINNET_PRODUCTION_TIMELOCK_12_HOURS \
DEPLOYER="$DEPLOYER" \
forge script script/DeployMainnetProductionTimelock.s.sol:DeployMainnetProductionTimelock \
  --rpc-url "$RPC" --sender "$DEPLOYER"
```

The script checks canonical creation and runtime hashes before
`vm.startBroadcast` and reverts under the wrong profile. Review calldata,
sender, nonce, estimated address, constructor arguments, and runtime hash.
During the separately approved ceremony, use the same candidate, profile,
sender, and nonce, then provide `--broadcast` and the hardware / managed signer
in accordance with repository wallet procedures. Do not use `--resume`: it may
send an existing broadcast artifact without rerunning script preflight. Produce
a fresh simulation and fresh broadcast artifact from the same candidate and
profile. This runbook is not broadcast approval.

After the receipt succeeds, record `$TIMELOCK` and `$DEPLOY_TX`. Do not adopt an
address unless all of these are true:

- `$TIMELOCK != 0x0000000000000000000000000000000000000000`
- `$TIMELOCK != 0xEd33edB1eA442475eFd076e1AE2C9da9EdaB86f6`
- the creation receipt has `status == 1`
- the receipt contract address equals `$TIMELOCK`

## 3. Pinned evidence

Pin the finalized block number and hash. Read runtime, delay, roles, and Safe
state at that same block tag. Retrieve the block hash again at the end; discard
all reads and repeat if it changed.

```bash
cast code "$TIMELOCK" --rpc-url "$RPC" | cast keccak
cast call "$TIMELOCK" "getMinDelay()(uint256)" --rpc-url "$RPC"
cast call "$TIMELOCK" "PROPOSER_ROLE()(bytes32)" --rpc-url "$RPC"
cast call "$TIMELOCK" "EXECUTOR_ROLE()(bytes32)" --rpc-url "$RPC"
cast call "$TIMELOCK" "CANCELLER_ROLE()(bytes32)" --rpc-url "$RPC"
cast call "$TIMELOCK" "TIMELOCK_ADMIN_ROLE()(bytes32)" --rpc-url "$RPC"
```

Treat the role constants as `$PROPOSER_ROLE`, `$EXECUTOR_ROLE`,
`$CANCELLER_ROLE`, and `$ADMIN_ROLE`, then run:

```bash
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$PROPOSER_ROLE" "$ADMIN_SAFE" --rpc-url "$RPC"
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$EXECUTOR_ROLE" "$ADMIN_SAFE" --rpc-url "$RPC"
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$CANCELLER_ROLE" "$ADMIN_SAFE" --rpc-url "$RPC"
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$ADMIN_ROLE" "$TIMELOCK" --rpc-url "$RPC"
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$ADMIN_ROLE" "$ADMIN_SAFE" --rpc-url "$RPC"
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$ADMIN_ROLE" "$DEPLOYER" --rpc-url "$RPC"
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$EXECUTOR_ROLE" 0x0000000000000000000000000000000000000000 --rpc-url "$RPC"
cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$CANCELLER_ROLE" "$GUARDIAN_SAFE" --rpc-url "$RPC"
```

Expected values:

| Check | Expected |
| --- | --- |
| runtime hash | Matches the candidate build |
| `getMinDelay()` | `43200` |
| PROPOSER / EXECUTOR / CANCELLER = `$ADMIN_SAFE` | `true` |
| ADMIN = `$TIMELOCK` | `true` |
| ADMIN = `$ADMIN_SAFE` / `$DEPLOYER` | `false` |
| EXECUTOR = `address(0)` | `false` |
| CANCELLER = `$GUARDIAN_SAFE` | `false` |

## 4. Governance evidence checker

Record the candidate commit, build profile, and expected OZ creation / runtime
hashes as separate artifacts in the private governance evidence package. The
schema in `check-mainnet-governance-transition.ts` and its tests is
authoritative for the JSON consumed by the checker, which contains:

- production Timelock address and `$DEPLOY_TX`
- pinned block number / hash
- addresses, signer counts, thresholds, and sorted signer-list hashes for Admin
  / Guardian / Allocator / Treasury / PIL-recipient Safes
- a production Admin Safe EIP-1271 signature over the owner-matrix digest

The EIP-1271 digest binds the Timelock address, deployment transaction, pinned
block number / hash, and Safe matrix. The candidate commit and expected runtime
hash are not digest fields. The checker independently compares the deployment
input and on-chain code with repository-pinned creation / runtime hash
constants.

```console
cd contracts
pnpm mainnet-governance-transition:check -- \
  --evidence <PRIVATE_GOVERNANCE_EVIDENCE_JSON> --rpc-url <RPC_URL>
```

At the pinned block and a runtime safe block, the checker verifies the direct
creation transaction's candidate creation-code hash and constructor arguments,
receipt, production address inequality with the pilot, runtime hash, 43200-second
delay, Timelock roles, Safe owners / thresholds, Safe proxy code hash,
singleton, fallback handler, absence of guards and modules, and EIP-1271. It
re-reads both block hashes after the checks. Do not freeze the Manifest or
deploy environment before a complete pass.

## 5. Handoff

1. Replace `<pending-production-timelock>` in the Protocol Role Holder Manifest
   with verified `$TIMELOCK` and advance its state to `address-fixed`.
2. Verify that deploy env, production protocol manifest, handover artifact, and
   production-cap artifact reference the same `$TIMELOCK` and governance
   evidence digest.
3. Continue to the
   [Mainnet-Deploy-Env-Freeze-Runbook](./Mainnet-Deploy-Env-Freeze-Runbook.md)
   and
   [Mainnet-Governance-Handover-Runbook](./Mainnet-Governance-Handover-Runbook.md).
4. Because the fresh production Timelock starts at 43200 seconds, wait 12 hours
   for its first ownership-accept or role operation.

## 6. Abort / recovery

- Pre-deploy mismatch: correct the values or repository state and restart at
  section 1.
- Deployment receipt / constructor / runtime / role / delay mismatch: remove
  that address from the candidate and do not write it to the Manifest or deploy
  env. Do not repair and adopt it with a self-admin operation; redeploy the
  correct candidate.
- Evidence-checker mismatch: do not proceed to production protocol deployment,
  ownership handover, or cap scheduling. Correct the cause and create fresh
  pinned evidence.
- Post-handoff mismatch: use Guardian controls to stop the affected surface and
  enter the Protocol Governance incident / recovery procedure. Do not resume
  launch until every gate passes again.

## 7. References

- [Mainnet Timelock Deploy Policy](./Mainnet-Timelock-Deploy-Policy.md)
- [Mainnet Protocol Role Holder Manifest](../../../../jp/protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md)
- [Mainnet Governance Handover Runbook](./Mainnet-Governance-Handover-Runbook.md)
- [Mainnet Deploy Env Freeze Runbook](./Mainnet-Deploy-Env-Freeze-Runbook.md)
