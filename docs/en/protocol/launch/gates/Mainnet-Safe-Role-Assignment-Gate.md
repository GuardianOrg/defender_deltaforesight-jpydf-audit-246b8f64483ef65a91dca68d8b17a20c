# Mainnet Safe / Role Assignment Gate

> **Positioning**: gate for freezing and reconciling DeltaForesight-side real addresses, Safe / Timelock thresholds, role assignments, on-chain readbacks, and frontend / ops / bot consumer configuration before Ethereum mainnet fresh deploy. For the permission design, see
> [`Governance-Roles-Timelock.md`](../../product/policies/Governance-Roles-Timelock.md); for deploy env, see
> [`Mainnet-Deploy-Env-Freeze-Runbook.md`](Mainnet-Deploy-Env-Freeze-Runbook.md); for handover execution, see
> [`Mainnet-Governance-Handover-Runbook.md`](Mainnet-Governance-Handover-Runbook.md).
>
> This document defines the **schema, gate, and No-Go conditions** for the real address package. Mainnet design documents may identify approved physical holder addresses; the evidence package freezes owners, thresholds, Safe configuration, and review status. Do not commit private keys, seed phrases, raw signer lists, Safe nonces, raw RPC URLs, API keys, or unpublished personal information. Unless signers are intentionally public, record signer evidence as `signerListHash` plus signer count / threshold; bind dedicated signing devices through a non-reversible `hostDeviceBindingHash`.

---

## 1. Scope

Target: Day-1 production deploy / handover / activation on Ethereum mainnet `chainId=1`.

- Cover deployer, Treasury Safe, Timelock, Guardian, Allocator, Writeoff, PriceFeedOwner, Strategy owner / upgrader, bridge admin, LP / SP seed owner, bootstrap borrower owner, liquidator / keeper wallets, and frontend / ops / admin-console operator groups in one address book.
- Record approved physical holder addresses once in the holder-design source. Keep personal mapping, in-flight transactions, unfrozen signer/device/recovery details, and the complete address book in the internal package.
- Every on-chain address must be EIP-55 checksummed, on `chainId=1`, and nonzero.
- If a role requires a Safe / Timelock / contract holder, using an EOA is No-Go. Exceptions are limited operator wallets such as liquidator gas wallets that do not hold privileged fund-moving roles.
- Day-1 dormant bridge policy is verified through a contract-only `DF_BRIDGE_ADMIN` plus `bridgeMinterCount == 0` and `proposedBridgeMinter == address(0)` readbacks.

## 2. Evidence Package

The standard evidence package is `mainnet-safe-role-assignment/`. If it includes real addresses, keep it in private storage and include only redacted summaries and hashes in public PRs.

| File                                 | Contents                                                                                                    | Public repo policy                                 |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| `00-readme.md`                       | package scope, candidate commit, fork block, review owner, Go / No-Go summary                               | redacted allowed                                   |
| `holder-address-book.csv`            | holder ID, env name, checksum address, type, Safe threshold, signer hash, evidence ref                      | complete version private; approved addresses may appear in a public summary |
| `safe-thresholds.md`                 | signer count, threshold, owner group, and break-glass policy per Safe / Timelock                            | hash signer lists                                  |
| `host-device-bindings.md`            | dedicated signing device, custody/ops owner, last review, and status                                        | hash raw device identifiers                        |
| `allocator-signer-policy.md`         | Day-1 execution mode and evidence that future bot activation has not occurred                               | redacted allowed                                   |
| `role-assignment-matrix.csv`         | mapping from contract / function / role to expected holder                                                  | redacted allowed                                   |
| `env-manifest-diff.md`               | address diff across deploy env, handover env, manifest, and consumer config                                 | redacted allowed                                   |
| `onchain-role-snapshot.json`         | `owner()`, `pendingOwner()`, `hasRole()`, Timelock, and bridge dormant readbacks                            | private or redacted                                |
| `frontend-ops-operator-addresses.md` | reconciliation result for app / ops / console / bot holder addresses                                        | redacted allowed                                   |
| `bridge-dormant-evidence.md`         | `bridgeAdmin` code, minter count 0, pending minter 0, no active adapter                                     | redacted allowed                                   |
| `dry-run-calldata-review.md`         | target / value / selector / args review for prepare / accept / Timelock / Safe transactions                 | do not record Safe nonces                          |
| `secret-hygiene.md`                  | confirmation that no private keys, raw RPC URLs, API keys, Safe nonces, or private signer data are included | public allowed                                     |
| `no-go-summary.md`                   | unmet gates, owner, resolution condition, launch impact                                                     | public allowed                                     |

## 3. Holder Address Book Schema

`holder-address-book.csv` has these columns.

| Column            | Required        | Contents                                                                      |
| ----------------- | --------------- | ----------------------------------------------------------------------------- |
| `holderId`        | yes             | stable ID, for example `DF_TIMELOCK`                                          |
| `envName`         | if applicable   | deploy / handover / consumer env name                                         |
| `holderType`      | yes             | `safe` / `timelock` / `contract` / `wallet` / `bot-wallet` / `operator-group` |
| `checksumAddress` | on-chain holder | EIP-55 checksum address. May be empty for operator groups                     |
| `chainId`         | on-chain holder | `1`                                                                           |
| `safeThreshold`   | Safe / multisig | execution threshold                                                           |
| `signerCount`     | Safe / multisig | signer count                                                                  |
| `signerListHash`  | Safe / multisig | hash of the signer list when the raw list is not public                       |
| `opsOwner`        | yes             | operations owner                                                              |
| `financeOwner`    | if funds        | finance owner                                                                 |
| `riskOwner`       | if privileged   | risk approval owner                                                           |
| `evidenceRef`     | yes             | reference to Safe UI, contract read, internal ticket, or snapshot             |
| `status`          | yes             | `draft` / `address-fixed` / `frozen` / `fork-verified` / `mainnet-verified` / `no-go` |

`address-fixed` means only that checksum address and physical-holder alias are approved. It does not approve Safe code/version/singleton, owners, threshold, fallback handler, guard, modules, `signerListHash`, or launch.

### 3.1 Required Holder Rows

| Holder ID                      | Env / consumer                      | Required type                          | Day-1 role                                                                                     |
| ------------------------------ | ----------------------------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `DEPLOYER`                     | `DEPLOYER` / signing method         | wallet or hardware-backed signer       | runs deploy / prepare and keeps no privileged role after activation                            |
| `DF_TIMELOCK`                  | `DF_TIMELOCK`                       | timelock contract                      | Vault `DEFAULT_ADMIN_ROLE` / `GOV_ROLE`, DToken owner, InterestRouter owner, Strategy upgrader |
| `DF_TIMELOCK_PROPOSERS`        | Timelock config                     | Admin multisig Safe                    | Admin multisig (`3-of-5`); raw signer list stays in private evidence                            |
| `DF_TIMELOCK_EXECUTORS`        | Timelock config                     | Admin multisig Safe                    | Admin multisig (`3-of-5`); `address(0)` open execution is prohibited                            |
| `DF_TIMELOCK_CANCELLER`        | Timelock config                     | Admin multisig Safe                    | Same Admin multisig as proposer / executor                                                      |
| `DF_GUARDIAN`                  | `DF_GUARDIAN` / `DF_STRATEGY_OWNER` | safe                                   | Vault pause / emergency disable, Strategy owner                                                |
| `DF_ALLOCATOR`                 | `DF_ALLOCATOR`                      | approved holder in the holder design   | Vault allocation / yield transfer; Safe configuration and execution mode follow their policies |
| `DF_WRITEOFF`                  | `DF_WRITEOFF`                       | high-quorum safe                       | Vault `WRITEOFF_ROLE`; not Timelock                                                            |
| `DF_PRICE_FEED_OWNER`          | `DF_PRICE_FEED_OWNER`               | safe                                   | PriceFeedProxy owner; not under Timelock because the proxy has an internal 12h source timelock |
| `DF_TREASURY`                  | `DF_TREASURY`                       | safe                                   | Vault treasury / yield retention recipient                                                     |
| `DF_INTEREST_ROUTER_RECIPIENT` | `DF_INTEREST_ROUTER_RECIPIENT`      | dedicated Day-1 Safe                    | PIL / borrow interest recipient; distinct from `DF_TREASURY`                                   |
| `DF_INTEREST_ROUTER_OWNER`     | `DF_INTEREST_ROUTER_OWNER`          | timelock or pre-handover owner         | deploy-time owner; final owner is `DF_TIMELOCK`                                                |
| `DF_STRATEGY_OWNER`            | `DF_STRATEGY_OWNER`                 | safe                                   | Day-1 explicitly equals `DF_GUARDIAN`                                                          |
| `DF_STRATEGY_UPGRADER`         | `DF_STRATEGY_UPGRADER`              | timelock contract                      | Day-1 explicitly equals `DF_TIMELOCK`                                                          |
| `DF_BRIDGE_ADMIN`              | `DF_BRIDGE_ADMIN`                   | safe or timelock contract              | dormant bridge admin; must not equal deployer / owner / EOA                                    |
| `BOOTSTRAP_BORROWER_OWNER`     | launch operation config             | safe                                   | company bootstrap Trove owner                                                                  |
| `LP_OWNER`                     | Uniswap v4 liquidity config         | safe                                   | JPYdf/USDC v4 position / allowance cleanup owner                                               |
| `SP_SEED_SOURCE_OWNER`         | launch operation config             | safe                                   | owner that executes and maintains SP seed JPYdf                                                |
| `LIQUIDATOR_GAS_WALLET`        | bot config                          | bot-wallet                             | liquidation maintenance bot gas wallet; fund cap / loss cap are separate evidence              |
| `KEEPER_OPS_WALLET`            | ops / keeper config                 | wallet or bot-wallet                   | routine keeper operations; do not confuse with privileged owner roles                          |
| `ADMIN_CONSOLE_OPERATOR_GROUP` | admin console config                | operator-group                         | console access group / IdP group; not an execution authority                                   |
| `FRONTEND_RELEASE_OWNER`       | frontend hosting config             | operator-group                         | User App / Private Operations Monitor release owner                                             |

## 4. Role Assignment Matrix

`role-assignment-matrix.csv` has these columns.

| Column                | Contents                                                                                                 |
| --------------------- | -------------------------------------------------------------------------------------------------------- |
| `layer`               | `core` / `jpydf-token` / `vault` / `strategy` / `oracle` / `treasury` / `liquidity` / `bot` / `frontend` |
| `contractOrConsumer`  | contract name, consumer name, or manifest path                                                           |
| `roleOrFunction`      | `owner()`, `hasRole(GOV_ROLE)`, `bridgeAdmin()`, config field, etc.                                      |
| `expectedHolderId`    | `holderId` in `holder-address-book.csv`                                                                  |
| `sourceEnvOrManifest` | env name, manifest field, frontend / bot config field                                                    |
| `verifyMethod`        | fork read / mainnet read / Safe UI / config diff / calldata review                                       |
| `noGoIfMismatch`      | stop reason on mismatch                                                                                  |

### 4.1 Required Assignments

| Target                    | Role / value                                            | Expected holder                               | Verify method                                    |
| ------------------------- | ------------------------------------------------------- | --------------------------------------------- | ------------------------------------------------ |
| `JpydfToken`              | `bridgeAdmin()`                                         | `DF_BRIDGE_ADMIN`                             | on-chain read + holder code length               |
| `JpydfToken`              | `bridgeMinterCount()` / `proposedBridgeMinter()`        | `0` / `address(0)`                            | on-chain read                                    |
| `CollateralVault`         | `DEFAULT_ADMIN_ROLE` / `GOV_ROLE`                       | `DF_TIMELOCK`                                 | `hasRole()` read and current-admin negative read |
| `CollateralVault`         | `GUARDIAN_ROLE`                                         | `DF_GUARDIAN`                                 | `hasRole()` read                                 |
| `CollateralVault`         | `ALLOCATOR_ROLE`                                        | `DF_ALLOCATOR`                                | `hasRole()` read                                 |
| `CollateralVault`         | `WRITEOFF_ROLE`                                         | `DF_WRITEOFF`                                 | `hasRole()` read                                 |
| `CollateralVault`         | treasury                                                | `DF_TREASURY`                                 | contract read / manifest read                    |
| `DToken`                  | `owner()` / `pendingOwner()`                            | `DF_TIMELOCK` / `address(0)` final            | on-chain read                                    |
| `InterestRouterForwarder` | `owner()`                                               | `DF_TIMELOCK` final                           | on-chain read                                    |
| `InterestRouterForwarder` | `recipient()`                                           | `DF_INTEREST_ROUTER_RECIPIENT`                | on-chain read                                    |
| `PriceFeedProxy`          | `owner()`                                               | `DF_PRICE_FEED_OWNER`                         | on-chain read                                    |
| Strategy proxies          | `owner()`                                               | `DF_STRATEGY_OWNER`                           | on-chain read                                    |
| Strategy proxies          | `upgrader()`                                            | `DF_STRATEGY_UPGRADER`                        | on-chain read                                    |
| Timelock                  | `getMinDelay()`                                         | `PRM-GOV-COMMON-TIMELOCK-DELAY`               | on-chain read                                    |
| Timelock                  | PROPOSER / EXECUTOR / CANCELLER                         | Admin multisig                                 | `hasRole()` read                                 |
| Timelock                  | `TIMELOCK_ADMIN_ROLE`                                   | Timelock itself only                           | `hasRole()` read + external-admin negative read  |
| Timelock                  | `EXECUTOR_ROLE` for `address(0)`                        | `false`                                        | `hasRole()` negative read                        |
| Uniswap v4 LP             | position owner / manager / allowance cleanup owner      | `LP_OWNER`                                    | liquidity evidence / allowance read              |
| SP seed                   | deposit source / maintenance owner                      | `SP_SEED_SOURCE_OWNER`                        | launch operation evidence                        |
| bootstrap Trove           | borrower owner / repayment owner                        | `BOOTSTRAP_BORROWER_OWNER`                    | launch operation evidence                        |
| liquidator bot            | gas wallet / max loss / max gas                         | `LIQUIDATOR_GAS_WALLET`                       | bot config + dry-run evidence                    |
| admin console             | declared holders / operator group                       | address book + `ADMIN_CONSOLE_OPERATOR_GROUP` | console evidence / IdP evidence                  |

## 5. Safe / Timelock Review Rules

Safe / Timelock review is part of address book freeze and must finish before handover dry-run.

- Persistent privileged holders are Safe / Timelock contracts. EOAs are limited to deployers, gas wallets, and limited keeper wallets, and must not hold privileged roles. Day-1 `DF_ALLOCATOR` follows the allocator-signer policy; a future hardened bot signer requires a separate activation gate.
- Record `safeThreshold`, `signerCount`, `signerListHash`, ops owner, and break-glass owner for every holder.
- `signerCount < safeThreshold`, `safeThreshold == 0`, or an unreviewed signer list is No-Go.
- Timelock evidence matches `PRM-GOV-COMMON-TIMELOCK-DELAY`, records the Admin multisig as PROPOSER / EXECUTOR / CANCELLER, confirms the Timelock is self-admin, and includes negative admin-role readbacks for the Admin Safe and deployer. The production constructor uses `admin=address(0)`, so there is no deployer-admin renounce transaction.
- If Safe owner / threshold changes, Timelock proposer / canceller changes, or role holder changes occur in the deploy / handover window, record the reason and execution order in calldata review. Reused production Safes must atomically add owners and set their target threshold before production Timelock deployment; required accepts run later from the already-hardened Safe after protocol deployment and Prepare.
- If multiple role Safes share the same signer set, risk owner must approve that separation is not merely formal. Guardian, Allocator, and Writeoff in particular must not use the same address.
- Do not publish signer personal names, emails, hardware key serials, or Safe nonces.

## 6. Env / Manifest / Consumer Reconciliation

Address book values must match these consumers.

| Consumer                   | Required reconciliation                                                                                       |
| -------------------------- | ------------------------------------------------------------------------------------------------------------- |
| deploy env                 | `DF_BRIDGE_ADMIN`, `DF_TREASURY`, InterestRouter recipient / owner                                            |
| handover env               | `DF_TIMELOCK`, `DF_GUARDIAN`, `DF_ALLOCATOR`, `DF_WRITEOFF`, `DF_PRICE_FEED_OWNER`, Strategy owner / upgrader |
| `deployment-manifest.json` | JPYdf token, Vault, DToken, Strategy, PriceFeed, InterestRouter, treasury, bridge admin, envFreeze fields     |
| app env / public manifest  | contract addresses and active branch metadata read by the public app                                          |
| Private Operations Monitor config | holder / branch / liquidity / bot monitoring targets                                                     |
| admin console config       | declared holders, role snapshot block, Safe calldata export target                                            |
| liquidator config          | active branches, gas wallet, loss / gas caps, manifest hash                                                   |
| launch operation config    | SP seed owner, LP owner, bootstrap borrower owner, redemption / liquidation owner                             |

No-Go:

- A consumer references a checked-in old snapshot, local mock, staging Anvil address, or old manifest hash.
- Env and manifest disagree for the same role name.
- The admin console collapses role holders into a single-address assumption.
- A production config with `chainId != 1` is used as mainnet launch evidence.

## 7. Review Phases

| Phase                     | Completion condition                                                                                                       | Next step                              |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| 0. Draft address book     | all required holder rows exist and owner / evidence ref are filled                                                         | physical address selection             |
| 1. Address fixed          | checksum address and alias approved; incomplete Safe hardening remains `address-fixed`                                     | Safe / Timelock review                 |
| 2. Safe / Timelock freeze | threshold, signer count/hash, Timelock config, and governance-process controls are reviewed                                | deploy env freeze                      |
| 3. Env freeze             | deploy / handover / consumer env matches the address book                                                                  | fork deploy / handover dry-run         |
| 4. Fork role snapshot     | `mainnet-fork-evidence` and `VerifyDFGovernanceHandover` pass role readback in the same fork state                         | mainnet broadcast / prepare            |
| 5. Mainnet final readback | after accept, pending owner 0, expected holders, bridge dormant state, and consumer config hashes match at a mainnet block | activation / liquidity / public launch |
| 6. T+24h watch            | holders / Timelock / bot / console / Private Operations Monitor are readable during the launch window                      | issue / gate closure                   |

## 8. No-Go Conditions

Stop mainnet broadcast, handover prepare, activation, liquidity add, or public launch if any of the following are true.

- A required holder row is missing or its `status` is not at least `frozen`; `address-fixed` is not launch-ready.
- checksum address, chainId, holder type, ops owner, or evidence ref is missing.
- A holder that must be Safe / Timelock uses an EOA, codeless address, deployer, or current admin.
- `DF_CURRENT_ADMIN` still holds Vault roles, DToken owner, Strategy owner / upgrader, PriceFeed owner, or InterestRouter owner after activation.
- Timelock / Guardian / Allocator / Writeoff / PriceFeedOwner separation is not satisfied.
- `DF_WRITEOFF` is Timelock or a low-quorum operational wallet.
- `DF_PRICE_FEED_OWNER` is under Timelock, creating double delay with the PriceFeedProxy internal 12h delay.
- `DF_BRIDGE_ADMIN` is missing, equals deployer / owner, is an EOA, is codeless, or `bridgeMinterCount != 0` / `proposedBridgeMinter != address(0)`.
- Safe threshold / signer count / signer hash is missing, or signer count is below threshold.
- deploy env, handover env, manifest, frontend / ops / admin console / bot config addresses do not match.
- Safe calldata review has not confirmed target / value / function / args / caller / execution order.
- public evidence contains a raw private key, seed phrase, raw signer list, Safe nonce, raw RPC URL, or API key.
- the admin console cannot show declared holders and on-chain role snapshots, or can send privileged transactions outside Safe / wallet execution.

## 9. Templates

### 9.1 `holder-address-book.csv`

```csv
holderId,envName,holderType,checksumAddress,chainId,safeThreshold,signerCount,signerListHash,opsOwner,financeOwner,riskOwner,evidenceRef,status
DF_TIMELOCK,DF_TIMELOCK,timelock,<checksum>,1,,,,governance,,security,<evidence>,draft
DF_GUARDIAN,DF_GUARDIAN,safe,<checksum>,1,<threshold>,<count>,<hash>,ops,,security,<evidence>,draft
DF_BRIDGE_ADMIN,DF_BRIDGE_ADMIN,safe,<checksum>,1,<threshold>,<count>,<hash>,governance,,security,<evidence>,draft
```

### 9.2 `role-assignment-matrix.csv`

```csv
layer,contractOrConsumer,roleOrFunction,expectedHolderId,sourceEnvOrManifest,verifyMethod,noGoIfMismatch
vault,CollateralVault,DEFAULT_ADMIN_ROLE,DF_TIMELOCK,DF_TIMELOCK,hasRole read,current admin keeps admin role
jpydf-token,JpydfToken,bridgeAdmin,DF_BRIDGE_ADMIN,DF_BRIDGE_ADMIN,on-chain read,bridge admin mismatch
frontend,admin-console,declaredHolders,holder-address-book,console config,config diff,console shows stale holders
```

### 9.3 Mainnet Final Readback Checklist

```text
Candidate commit:
Manifest sha256:
Fork block:
Mainnet verification block:
Address book hash:
Signer list hash set:
Safe threshold review:
Timelock minDelay / role review:
Deploy env hash:
Handover env hash:
Consumer config hashes:
On-chain role snapshot:
Bridge dormant snapshot:
Admin console role snapshot:
Liquidator config snapshot:
Secret hygiene review:
Go / No-Go:
```
