# Bridge Readiness Differential Review - 2026-06-19

> Scope: the Day-1 dormant bridge-readiness additions diff (`JpydfToken` / deploy / tests / docs).
> This review is not an audit of an active bridge adapter / other-chain issuance. Day-1 was confirmed on the premise of a dormant state with 0 bridge minters.

## Executive Summary

| Severity | Count |
| --- | ---: |
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |

**Overall Risk**: Medium (because it adds a new future supply-authority surface)

**Recommendation**: Conditional approve for Day-1 dormant launch, provided deployment evidence shows `bridgeMinterCount == 0` and `proposedBridgeMinter == address(0)`.

## What Changed

| Area | Risk | Review Result |
| --- | --- | --- |
| `JpydfToken` bridge admin / minter registry | High | Fixed. Made admin/minter contract-only and added a prohibition on holding both roles |
| `bridgeMint` / `bridgeBurn` | High | Fixed. Kept as a separate surface from the core `mint` / `burn`; `bridgeBurn` is the self-burn type and `bridgeMint` applies the protocol recipient guard |
| Core address registration hardening | Medium | `setBranchAddresses` / `setCollateralRegistry` reject zero / codeless addresses |
| Deploy / CREATE2 / manifest | Medium | `DF_BRIDGE_ADMIN` is included in the constructor preimage / manifest / deploy-tail check, and a contract address is required |
| Test coverage | Medium | Added dormant state, timelock, self-burn, role separation, protocol recipient reject, and event payload to `JpydfTokenTest`. Also added input validation for the deploy resolver's `DF_BRIDGE_ADMIN` |
| Docs / ledgers / runbooks | Medium | Updated Product / Core spec / Parameters / deploy config / runbook / ledgers |

## Issues Fixed During Review

### 1. Bridge role addresses were not constrained to contracts

**Risk**: An EOA could be configured as `bridgeAdmin` or bridge minter, weakening operational control and making adapter assumptions unenforceable.

**Fix**:
- `JpydfToken` constructor requires `_bridgeAdmin.code.length > 0`.
- `proposeBridgeMinter`, `confirmBridgeMinter`, `transferBridgeAdmin`, and `acceptBridgeAdmin` require contract addresses.
- Deploy script checks `DF_BRIDGE_ADMIN` with `_requireContract`.
- Tests added: `test_BridgeRolesMustBeContractsAndSeparated`.

### 2. Bridge admin and bridge minter could overlap

**Risk**: A single contract could hold both governance and supply authority, increasing blast radius if compromised or misconfigured.

**Fix**:
- `proposeBridgeMinter` / `confirmBridgeMinter` reject current and pending `bridgeAdmin`.
- `transferBridgeAdmin` / `acceptBridgeAdmin` reject registered or proposed bridge minters.
- Tests cover current-admin, pending-admin, and proposed-minter separation.

### 3. `bridgeMint` did not reuse protocol recipient protection

**Risk**: A future bridge minter could mint directly to core protocol contracts such as StabilityPool / ActivePool / BorrowerOperations, creating balances outside the intended user flow.

**Fix**:
- `bridgeMint` calls `_requireValidRecipient(_account)` before `_mint`.
- Test added: `test_BridgeMintRejectsProtocolRecipients`.

### 4. Event payloads and deploy resolver guards were not fully pinned

**Risk**: Bridge lifecycle monitoring or launch evidence could drift if event payloads or `DF_BRIDGE_ADMIN` validation changed without failing tests.

**Fix**:
- Event payload tests cover proposal, cancel, confirm, mint, burn, remove, admin transfer, and renounce.
- Deploy resolver tests cover configured contract admin, zero admin, deployer-as-admin, and codeless admin.

### 5. Core address registration accepted zero / codeless addresses

**Risk**: A deployment mistake could permanently register a zero or undeployed core address before owner renounce.

**Fix**:
- `setBranchAddresses` and `setCollateralRegistry` now require non-zero contract addresses.
- Test added: `test_CoreAddressRegistrationRequiresContracts`.

## Residual Risks

| Risk | Status | Required Before Activation |
| --- | --- | --- |
| Registered bridge minter can mint arbitrary JPYdf | Accepted for dormant Day-1 because minter count is 0 | Activation spec must define adapter verification, cap/rate limit, monitoring, and emergency removal |
| Token has no per-minter hard cap | Accepted for Day-1 | Day-2 bridge PR must decide whether cap lives in adapter/pool only or also token-side |
| Destination token semantics are undefined | Out of Day-1 scope | New active bridge spec must define canonical burn/mint vs lockbox representation |
| Deploy manifest evidence is still required for the final mainnet address set | Open until final deploy | Manifest now emits `launchEvidence`; final launch package must attach it proving `bridgeMinterCount == 0`, `proposedBridgeMinter == address(0)`, and no connected bridge adapter |

## Test Coverage

Executed:

```bash
forge test --match-contract JpydfTokenTest
forge test --match-contract DeployLiquity2StrategySelectorTest
forge test --match-contract CollateralYieldZapperTest
forge test --match-contract ExchangeApprovalHygieneTest
forge test --match-contract Deployment
forge test -vv --no-match-contract 'Mainnet|Invariant|Anchored|E2E|Initiative'
pnpm -C contracts exec tsc --noEmit --pretty false
forge build
git diff --check
```

Results:

- `JpydfTokenTest`: 11 passed
- `DeployLiquity2StrategySelectorTest`: 16 passed
- `CollateralYieldZapperTest`: 16 passed
- `ExchangeApprovalHygieneTest`: 5 passed
- `Deployment`: 18 passed
- fast Foundry PR suite: 1180 passed, 0 failed, 1 skipped
- contracts TypeScript check: passed
- `forge build`: passed with existing warnings / lint notes
- `git diff --check`: passed

## Methodology

- Differential review of changed Solidity, deploy, tests, and Japanese source-of-truth docs.
- Risk focus: access control, supply authority, role separation, CREATE2/deploy drift, and Day-1 launch evidence.
- Adversarial model: malicious/compromised bridge admin, misconfigured bridge minter, and future bridge adapter compromise.
- Scope limit: no live bridge adapter, Wormhole / LayerZero / CCIP implementation, destination chain token, relayer, rate-limit, or cross-chain supply monitor was reviewed.
