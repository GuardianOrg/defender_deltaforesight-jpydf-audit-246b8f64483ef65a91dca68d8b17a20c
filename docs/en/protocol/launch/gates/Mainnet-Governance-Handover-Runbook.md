# Mainnet Governance Handover Runbook

> **Positioning**: runbook for dry-running / fork-running `PrepareDFGovernanceHandover.s.sol` / `VerifyDFGovernanceHandover.s.sol` with production holder values after Ethereum mainnet Day-1 deploy and before activation, and for recording holder-separation evidence. For deploy env freeze, see [`Mainnet-Deploy-Env-Freeze-Runbook.md`](Mainnet-Deploy-Env-Freeze-Runbook.md). For Safe / role real-address evidence, see [`Mainnet-Safe-Role-Assignment-Gate.md`](Mainnet-Safe-Role-Assignment-Gate.md). For permission design, see [`Governance-Roles-Timelock.md`](../../product/policies/Governance-Roles-Timelock.md). For deploy configuration, see [`Deployment-Configuration-Spec.md`](../../../engineering/guides/Deployment-Configuration-Spec.md).

---

## 1. Scope

The target is governance handover for the mainnet Day-1 manifest produced by `DeployLiquity2.s.sol`.

- Read `contracts/deployment-manifest.json` as `DF_HANDOVER_MANIFEST`.
- `currentAdmin` is the deployer / initial admin and loses Vault roles after activation.
- This runbook does not record private keys, Safe nonces, raw `MAINNET_RPC_URL`, or RPC provider API keys. RPC information in evidence is limited to provider labels and redacted URLs.
- Liquity core fork surfaces and `contracts/lib/**` are out of scope.
- Do not record "dry-run complete" before fork-running with real values.

---

## 2. Required Inputs

### 2.1 Manifest / current admin

| Env                    | Meaning                                                                                                |
| ---------------------- | ------------------------------------------------------------------------------------------------------ |
| `DF_HANDOVER_MANIFEST` | Manifest to hand over. Usually `deployment-manifest.json`                                              |
| `DF_DTOKEN_CAP_CONVERSION` | Path to the approved `dtoken-cap-conversion.json`; required by mainnet Prepare / Verify |
| `DF_CURRENT_ADMIN`     | Admin address holding Vault roles / 2-step ownership after deploy                                      |
| `DEPLOYER`             | Fallback public address when `DF_CURRENT_ADMIN` is omitted. Private keys are rejected; source the broadcast signer from a Foundry keystore, hardware wallet, or KMS. |
| `DF_HANDOVER_TOTAL_BRANCHES` | Explicitly `8` on Day-1; include every manifest branch in ownership/inert-cap verification |
| `DF_HANDOVER_ACTIVE_BRANCHES` | Explicitly `3` on Day-1; active-wired prefix for Vault parameter and Strategy handover (branches 0–2) |

`DF_CURRENT_ADMIN` must not equal Timelock / Guardian / Allocator / Writeoff / PriceFeedOwner unless `DF_ALLOW_CURRENT_ADMIN_AS_TARGET=true` is explicitly set.

`DF_HANDOVER_ACTIVE_BRANCHES` is not the number of public borrowable branches. Day-1 has three active-wired branches (dETH, dUSDC, dwstETH) and two borrowable branches (dUSDC, dwstETH). Omission, a value other than `8 / 3`, or mismatch with the manifest active/inert boundary is No-Go.

### 2.2 Holder values

Holder values must exactly match the address book in [`Mainnet-Safe-Role-Assignment-Gate`](Mainnet-Safe-Role-Assignment-Gate.md). A hand-edited handover env that is not reconciled to the address book is not a Go condition.

| Env                            | Holder / role                                                                                  |
| ------------------------------ | ---------------------------------------------------------------------------------------------- |
| `DF_TIMELOCK`                  | Vault `DEFAULT_ADMIN_ROLE` / `GOV_ROLE`, DToken owner, InterestRouter owner, Strategy upgrader |
| `DF_TREASURY`                  | Vault treasury / yield retention recipient                                                     |
| `DF_INTEREST_ROUTER_RECIPIENT` | InterestRouterForwarder recipient                                                              |
| `DF_GUARDIAN`                  | Vault `GUARDIAN_ROLE`, Strategy owner                                                          |
| `DF_ALLOCATOR`                 | Vault `ALLOCATOR_ROLE`                                                                         |
| `DF_WRITEOFF`                  | Vault `WRITEOFF_ROLE`                                                                          |
| `DF_PRICE_FEED_OWNER`          | PriceFeedProxy owner                                                                           |
| `DF_STRATEGY_OWNER`            | Strategy owner. Day-1 policy equals `DF_GUARDIAN`                                              |
| `DF_STRATEGY_UPGRADER`         | Strategy upgrader. Day-1 policy equals `DF_TIMELOCK`                                           |

`PrepareDFGovernanceHandover` fails fast on holder nonzero and separation. In particular, `DF_PRICE_FEED_OWNER` is separated from Timelock / Guardian / Allocator, and `DF_GUARDIAN` is separated from `DF_ALLOCATOR` / `DF_WRITEOFF`.

### 2.3 Branch policy values

| Env group                            | Meaning                                                      |
| ------------------------------------ | ------------------------------------------------------------ |
| `DF_DTOKEN_CAP_0..7`                 | per-branch dToken cap in dToken 18-decimal units              |
| `DF_ALLOCATE_MAX_MOVE_0..7`          | per-branch allocation maximum in Underlying-decimal units     |
| `DF_ALLOCATOR_COOLDOWN_0..7`         | per-branch allocator cooldown                                 |
| `DF_WITHDRAW_DELAY_0..7`             | per-branch withdrawal delay                                   |
| `DF_BUFFER_TARGET_BPS_0..7`          | per-branch buffer target                                      |
| `DF_BUFFER_FLOOR_0..7`               | per-branch buffer floor                                       |

`DF_DTOKEN_CAP_i` and `DF_ALLOCATE_MAX_MOVE_i` are token-unit values, not USD notation. dETH (branch 0) and inert branches 3–7 must have cap/allocation/supply 0. dUSDC and dwstETH caps must match `dtoken-cap-conversion.json`; dwstETH allocation remains 0.

On mainnet, Prepare / Verify read that evidence from `DF_DTOKEN_CAP_CONVERSION`, recompute both values from the nominal JPY limits, and match the env values plus the dToken / Underlying addresses and decimals.

---

## 3. Holder Separation Matrix

| Holder         | Expected permissions                                                                           | Forbidden permissions / notes                              |
| -------------- | ---------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Timelock       | Vault `DEFAULT_ADMIN_ROLE` / `GOV_ROLE`, DToken owner, InterestRouter owner, Strategy upgrader | Must not equal Guardian / Allocator / Writeoff             |
| Guardian       | Vault `GUARDIAN_ROLE`, Strategy owner                                                          | Must not equal Timelock / Allocator / Writeoff             |
| Allocator      | Vault `ALLOCATOR_ROLE`                                                                         | Must not equal Timelock / Guardian / Writeoff              |
| Writeoff       | Vault `WRITEOFF_ROLE`                                                                          | Must not equal Timelock / Guardian / Allocator             |
| PriceFeedOwner | PriceFeedProxy owner                                                                           | Must not equal Timelock / Guardian / Allocator             |
| Treasury       | Vault treasury / yield recipient                                                               | Being treasury does not itself mean admin role             |
| CurrentAdmin   | Runs prepare and loses role / ownership after activation                                       | Must not retain Vault roles. Must not equal target holders |

`CollateralVault` is not `AccessControlEnumerable`, so role members cannot be fully enumerated on-chain to prove uniqueness. `VerifyDFGovernanceHandover` confirms that declared holders have required roles and that Timelock / Guardian / Allocator / Writeoff / currentAdmin lack roles they must not have. The absence of unknown extra holders is covered by prepare transaction review and Safe / multisig review.

---

## 4. Fork Dry-Run Sequence

1. Fix `MAINNET_RPC_URL` and fork block number, and record them in evidence.
2. Load the deploy env from `Mainnet-Deploy-Env-Freeze-Runbook.md` and the holder / branch-policy env from this runbook in the same shell session.
3. Run the deploy script without broadcast and confirm deploy-tail verification passes.

```bash
forge script contracts/script/DeployLiquity2.s.sol:DeployLiquity2Script \
  --rpc-url "$MAINNET_RPC_URL"
```

4. Set the generated manifest as `DF_HANDOVER_MANIFEST` and run prepare without broadcast.

```bash
export DF_HANDOVER_MANIFEST=deployment-manifest.json

forge script contracts/script/PrepareDFGovernanceHandover.s.sol:PrepareDFGovernanceHandover \
  --rpc-url "$MAINNET_RPC_URL"
```

5. Verify the intermediate pre-accept state as pending ownership.

```bash
DF_VERIFY_PENDING_OWNERSHIP=true \
forge script contracts/script/VerifyDFGovernanceHandover.s.sol:VerifyDFGovernanceHandover \
  --rpc-url "$MAINNET_RPC_URL"
```

6. Record `deployment-manifest.json` fields: `branches.length == 8`, `dfYield.length == 8`, active-wired branches 0–2 `underlying` / `strategies[]` / `collateralYieldZapper`, branches 3–7 inert state, holder separation matrix, and branch policy values.

---

## 5. Mainnet Broadcast / Accept / Verify

### 5.1 Prepare broadcast gate

Before broadcasting `PrepareDFGovernanceHandover` on mainnet, all of the following must be true.

- deploy env freeze and handover env freeze were dry-run at the same fork block.
- Holder values have been reviewed in Safe / Timelock / risk sheet and match the `holder-address-book.csv`, `role-assignment-matrix.csv`, Safe threshold review, and consumer config diff from the Safe role assignment package.
- Production accept plan has been reviewed down to signers / calldata / target contract / order.
- `DF_DTOKEN_CAP_i` and `DF_ALLOCATE_MAX_MOVE_i` are frozen in token units.
- dETH and branches 3–7 have cap/allocation/supply 0; dwstETH has the frozen JPY 35M token-unit cap and allocation 0.
- `strategyKind == "none"` branches are product / security approved.

### 5.2 Production accept

`AcceptDFGovernanceHandover.s.sol` is a local / CI helper and is not used for production Safe / Timelock control planes. On mainnet, each holder calls `acceptOwnership()` from its own control plane. The helper itself reverts on any chain other than 31337 / 31338 before reading a manifest or private-key environment variable.

| Target                                   | accept caller            |
| ---------------------------------------- | ------------------------ |
| shared `branches[i].interestRouter`      | Timelock                 |
| `dfYield[i].dToken`                      | Timelock                 |
| `branches[i].priceFeed`                  | PriceFeedOwner           |
| each `dfYield[i].strategies[j].strategy` | StrategyOwner / Guardian |

Branches with empty `dfYield[i].strategies` are not accept targets. Confirm the Vault registered Strategy count is also 0 from manifest and prepare/verify output.

### 5.3 Final verify

After all accepts are complete, verify without pending ownership mode.

```bash
forge script contracts/script/VerifyDFGovernanceHandover.s.sol:VerifyDFGovernanceHandover \
  --rpc-url "$MAINNET_RPC_URL"
```

`DF_VERIFY_PENDING_OWNERSHIP=true` is only for the intermediate pre-accept state. Even in that mode, a target whose current owner is neither `DF_CURRENT_ADMIN` nor `DEPLOYER` must fail. Remove the flag from final evidence; final verification also rejects any nonzero pending owner on the InterestRouter, PriceFeed, dToken, or Strategy.

---

## 6. Failure Gates

Stop broadcast / activation if any of the following are true.

- A required holder env is zero address or missing.
- `DF_HANDOVER_TOTAL_BRANCHES=8` and `DF_HANDOVER_ACTIVE_BRANCHES=3` are not explicit or disagree with the manifest boundary.
- The Safe role assignment package is missing, No-Go, stale, or inconsistent with handover env.
- Timelock / Guardian / Allocator / Writeoff / PriceFeedOwner separation is not satisfied.
- `currentAdmin` equals a target holder, or still has Vault roles after activation.
- `dfYield.length != branches.length`.
- Per-branch `interestRouter` does not point to one shared `InterestRouterForwarder`.
- InterestRouterForwarder token / recipient / owner / pending owner differs from expectation.
- Active branch cap / allocate max move / buffer / withdraw delay is not frozen or has unclear units.
- dETH or branches 3–7 have nonzero cap/allocation/supply, or dwstETH has a nonzero Strategy allocation.
- `strategyKind == "none"` lacks product / security approval.
- Production accept plan calldata / caller / order has not been reviewed.

---

## 7. Evidence Template

```text
Repository commit:
Manifest file:
Manifest sha256:
Chain id:
Fork block:
RPC label:

Deploy dry-run command:
Deploy dry-run result:
Deploy tx hash:

Prepare dry-run command:
Prepare dry-run result:
Prepare tx hash:

Pending verify command:
Pending verify result:

Accept transactions:
- InterestRouter owner accept:
- DToken owner accepts:
- PriceFeed owner accepts:
- Strategy owner accepts:

Final verify command:
Final verify result:

Holder separation:
| Holder | Address | Expected role / ownership | Evidence |
| --- | --- | --- | --- |

Branch policy values:
| Branch | dToken cap | allocate max move | cooldown | withdraw delay | buffer target bps | buffer floor | strategy count / env kind |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |

Known limitation:
- CollateralVault is not AccessControlEnumerable, so unknown extra role holders
  are not enumerable on-chain. Review prepare transaction inputs and multisig
  history to ensure no extra holders were granted.
```
