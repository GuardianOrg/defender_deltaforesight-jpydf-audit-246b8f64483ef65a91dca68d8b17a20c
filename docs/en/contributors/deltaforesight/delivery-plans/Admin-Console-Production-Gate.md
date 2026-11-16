# Admin Console Production Gate

Updated: 2026-08-03

This runbook defines the mainnet-specific gates for Admin Control and the authenticated Private Operations Monitor in `frontend/console`. It assumes the common decision in [Frontend Production Delivery Gate](Frontend-Production-Delivery-Gate.md) and does not repeat RPC credential, live-data, error-redaction, release, or rollback controls. The Japanese document is authoritative. This gate supports `FRNT-TBD-005`, `FRNT-FR-024..035`, `FRNT-SEC-007`, `FRNT-SEC-008`, and `FRNT-GOV-001`. [Public Analytics / Private Monitoring Architecture](../operations/Public-Analytics-Private-Monitoring-Architecture.md) owns the boundary with public analytics.

For routine post-launch work, use the Japanese-source [Admin Console Operator Manual](../../../../jp/protocol/operations/runbooks/Admin-Console-Operator-Manual.md). Do not repurpose this gate's evidence template or non-mainnet E2E as the daily procedure.

## 1. Scope

The authenticated operations surface has two views:

- **Admin Control** prepares and reviews GOV_MULTISIG / ALLOCATOR / GUARDIAN / WRITEOFF / oracle-owner / token-owner operations. It holds no private keys and provides calldata, current values, role/owner state, explicit Safe/explorer links, and evidence.
- **Private Operations Monitor** displays immediate state for all branches, monitoring degradation, critical alerts, acknowledgements, and escalation. It neither prepares nor submits privileged operations.

Monitor viewers, privileged operators, and signers may be separated so that a viewer cannot reach Admin Control. Admin Control derives authority, holder, execution route, effect timing, and recovery actor from the Action Registry and distinguishes Timelock workflow roles from the target contract authority. Execution occurs through Safe or the relevant role-holder wallet. GOV / DEFAULT_ADMIN / DToken owner / Strategy upgrader operations must pass through the shared TimelockController.

## 2. Day-1 Minimum Gate

| Gate | Admin-specific requirement | Evidence |
| --- | --- | --- |
| Authentication | Protect the surface with a company-managed IdP or access proxy. MFA is mandatory; a shared password alone is prohibited. Keep break-glass accounts only in internal operations material. | IdP/proxy, owner, MFA policy, allowed group |
| Monitor/operator separation | Separate reachability for monitor viewers, privileged operators, and signers. A viewer receives no calldata builder, Safe proposal, or privileged-operation route. | Group/route matrix, viewer negative test, operator positive test |
| Hosting separation | Use a hostname, project, and deployment separate from the User App. Do not link it from public marketing or the User App. | Console domain, hosting project, unreachable-from-User-App check |
| Search indexing | Reject indexing through multiple controls such as `X-Robots-Tag: noindex`, HTML `noindex`, and `robots.txt`. The bundle must not be readable without the auth wall. | Headers, robots, page source |
| Role visibility | Read role/owner state on-chain and list multiple holders. For non-enumerable roles, use declared holders plus `hasRole`; the governance handover and [Safe Role Assignment Gate](../../../protocol/launch/gates/Mainnet-Safe-Role-Assignment-Gate.md) prove no unknown holder remains. | Snapshot block, holder list, `hasRole`/owner reads, address-book hash |
| Safe/Timelock boundary | Deliver a simulated artifact as a one-outer-`CALL` Safe Transaction Builder JSON. Reconcile every signed proposal field, EIP-712 hash, and outcome against the official read-only API. Decode Timelock wrappers and reconcile the inner payload and operation state. Lookup must be bounded, killable, and self-recovering after dependency failure. | Sections 5.1/5.2 artifacts, payload diff, Timelock state, lookup health, monitor delivery |
| Privileged-operation UX | pause/unpause, cap, allocator, Strategy add/update, writeoff, oracle source replacement, and upgrade require impact preview and double confirmation. If preview is unavailable, state that explicitly and require operator-supplied guard values. | Operation evidence, impact preview, guard values |
| Operator readiness | Pin the `Admin Safe` / `Guardian Safe` / `Allocator Safe` labels and checksum addresses in one build-time configuration. Fix the routine path, Safe JSON import, pre-signature machine comparison, Timelock Schedule/Execute/Cancel, exceptions, and stop conditions in the Operator Manual. An operator and independent reviewer complete a production-like dry run. | Address-book hash, operator config, manual revision, training record, representative T1/D1 dry-run evidence |

## 3. No-Go Conditions

Any failure in the common gate or Section 2 is No-Go. The following cannot be waived by an evidence note:

- authentication, delivery separation, or noindex is missing;
- a monitor viewer can reach Admin Control, calldata generation, a Safe proposal, or another privileged route;
- the role snapshot cannot represent multiple holders or conflicts with the role-assignment package;
- calldata requires manual transcription, the official read-only API cannot reconcile every proposal field / EIP-712 hash / outcome, or lookup is unbounded;
- Timelock target/operation or Pending Queue chain / Action / target / route / freshness cannot be revalidated;
- the console holds or submits with a key, or the operator and independent reviewer have not completed a production-like dry run.

## 4. Production Evidence Template

```text
Admin console production evidence
Date:
Operator:
Common production evidence ID:
Admin Control URL:
Private Operations Monitor URL:
Monitor viewer group:
Privileged operator group:
Viewer negative access evidence:
Auth provider / group:
Noindex evidence:
Role snapshot block:
Declared role holders:
hasRole / owner verification:
Safe artifact hash / simulation block:
Action ID / required authority / execution route:
Artifact integrity (valid / stale / invalid / superseded):
Safe Transaction Builder filename / checksum:
Generated / imported / proposed payload hash:
Safe transaction URL / ID / Safe tx hash:
Safe version:
Safe proposal verification result / diff:
Safe read-only API / proxy aggregate quota, rate / connection limit, 429 backoff:
Safe lookup timeout / active count / configured limit / oldest outstanding age / circuit / stuck probe:
Safe verification synthetic monitor / escalation / delivery test:
Governance execution path (derived from chainId / Timelock config):
Timelock address / deploy block:
Timelock minDelay / role snapshot:
Timelock operation ID / stage:
Dry-run / import evidence:
Known limitations:
Go / No-Go:
```

## 5. Machine Checks

Before production promotion, retain at least:

```bash
pnpm -C frontend/console check:hosting-env
pnpm -C frontend/console build
```

`check:hosting-env` verifies the generated binding's chain ID and RPC URL;
noindex; `VITE_CONSOLE_ENABLE_LOCAL_EXECUTION=false`;
`VITE_CONSOLE_OPERATOR_ACCOUNTS_JSON`; `VITE_CONSOLE_TIMELOCK_ADDRESS`; and
`VITE_CONSOLE_TIMELOCK_FROM_BLOCK >= 1`, which must be the Timelock deployment
block. The operator configuration has one source of truth and must replace the
example values below with the actual address book:

```bash
VITE_CONSOLE_OPERATOR_ACCOUNTS_JSON='[
  {"label":"Admin Safe","address":"0x..."},
  {"label":"Guardian Safe","address":"0x..."},
  {"label":"Allocator Safe","address":"0x..."}
]'
```

The production guard requires the three standard labels, non-empty labels,
nonzero addresses, and no duplicate label or address. It rejects simultaneous
use of the legacy `VITE_CONSOLE_OPERATOR_ADDRESSES`. That legacy variable is
compatibility input only for existing Hosted Anvil staging / local environment
writers and must not be used for production promotion. These values enter the
client bundle and therefore must not contain private keys, mnemonics, or
personal information about Safe owners.

For a mainnet binding, runtime reads stop Timelock artifact generation when
`getMinDelay() != 86400` or `EXECUTOR_ROLE(address(0)) == true`. A non-mainnet
binding fails the production check; staging/local failures are expected only
outside production evidence and the check must be rerun with the mainnet
binding for production evidence.

### 5.1 Hosted Anvil / Local Timelock E2E

Deploy a real `TimelockController`; never substitute an EOA as the Timelock holder. Console routing is derived from chain ID and `VITE_CONSOLE_TIMELOCK_*`, not a retired governance-mode toggle. The `DEVNET_*` values below guard deploy/handover scripts only.

```bash
DEVNET_EXPECTED_CHAIN_ID=31337
DEVNET_EXPECTED_MANIFEST_HASH=0x...
VITE_CONSOLE_TIMELOCK_ADDRESS=0x...
VITE_CONSOLE_TIMELOCK_FROM_BLOCK=<positive CREATE receipt block>
```

Derive `DEVNET_EXPECTED_MANIFEST_HASH` with `cast keccak < deployment-manifest.json`, confirm the manifest matches the Console binding, freeze the reviewed literal hash in evidence, and pass that same value to Prepare and Finalize. Do not calculate and accept a new unreviewed hash immediately before broadcast.

After Anvil and `contracts/utils/local-stack.sh` bootstrap, run:

```bash
RPC_URL=http://127.0.0.1:8545 CHAIN_ID=31337 \
  frontend/console/scripts/e2e-local-anvil-timelock-safe.sh
```

The script writes JSON to `E2E_EVIDENCE_OUT` (default `/tmp/jpydf-console-timelock-safe-e2e.json`) and refuses `CHAIN_ID=1`. It performs:

1. Deploy a real Timelock with `DeployConsoleDevnetTimelock`, bootstrap delay 0, operator proposer/executor/canceller roles, no open executor, and no external `TIMELOCK_ADMIN_ROLE`. Use the CREATE receipt block—not a preflight block—for `VITE_CONSOLE_TIMELOCK_FROM_BLOCK`.
2. Use `PrepareConsoleDevnetTimelockHandover` to transfer only Vault `DEFAULT_ADMIN_ROLE` / `GOV_ROLE`, DToken owner, Strategy upgrader, and InterestRouterForwarder owner. It must not change caps, Vault operating values, Treasury, PriceFeed owner, Strategy owner, or Guardian/Allocator/Writeoff holders. The script verifies manifest hash, Timelock runtime, bootstrap delay, roles, self-admin, and closed executor before broadcast.
3. Use `FinalizeConsoleDevnetTimelockHandover` so the Timelock itself accepts DToken / InterestRouterForwarder ownership, then raises its own delay to at least one second. A second identical run acts as a no-change post-handover verifier. If only scheduling completed, resume the existing operation instead of re-scheduling the same ID.
4. With an identical payload / salt / predecessor, assert the operation lifecycle `unscheduled -> waiting -> ready -> done`, and separately `waiting -> cancel -> unscheduled` without post-state change. A schedule artifact has `earliestExecutionAt = null`; execute/cancel use the observed timestamp. Every stage is one outer Timelock `CALL` in Builder-compatible JSON, never an inner target promoted to the outer transaction. The Builder checksum and reconstructed proposal match the artifact; payload promotion or delay substitution fails verification; and execution changes the intended post-state (`withdrawDelay` in the test).
5. Manually verify only UI-specific behavior: execute is unavailable while waiting; saved Pending Queue artifacts survive reload; and stage, branch, and operation ID are identifiable.

Chain IDs 31338/31337 have no official Safe Transaction Service. This section proves Timelock transitions, Builder files, and non-authoritative pasted-JSON comparison only. It must never label pasted JSON as `Safe transaction verified`. The next section closes authoritative lookup on Sepolia. The mainnet-only 24h delay and closed-executor gate do not prevent short non-mainnet E2E delays, but this exception cannot be reused as production evidence.

### 5.2 Sepolia Safe Proposal Authoritative E2E

Close Issue #1188 once Safe-compatible artifact generation, proposal verification, and Hosted Anvil / local E2E satisfy their acceptance criteria. Track Sepolia (`11155111`) real-Safe functional evidence and production-monitor evidence separately in Issue #1201. The authenticated monitor, workflow delivery / recovery, and human-operator requirements that remain in #1201 are mandatory before production promotion, but do not block closure of #1188.

1. Freeze the review Safe, Timelock, and target test contract in the evidence package.
2. Import direct / schedule / execute / cancel Builder files in the Safe UI and create each proposal as one outer transaction.
3. Retrieve each proposal from the official read-only API and verify every comparison field, the Safe-info version, zero-gas/refund policy, current Safe nonce, and the EIP-712 Safe transaction hash recomputed with the version-appropriate domain. Record `Safe transaction verified`.
4. Fault-inject missing or malformed Safe version, missing or different response `safeTxHash`, every signed-field mutation, a never-settling lookup, and more than two normal concurrent lookups. Verify fail-closed behavior, total physical work capped at three, worker termination, a bounded half-open probe, a stuck probe, and automatic recovery to closed after the dependency returns.
5. Reload the browser, reopen the saved Pending Queue artifact, and revalidate the same proposal. Transition to `Executed (Safe)` only when `isExecuted=true` and `isSuccessful=true`; retain a failed execution as `Safe execution failed (not applied)` in Pending Queue.

**Progress record (2026-07-26)**: Issue #1201 verified a dedicated Sepolia Safe,
Timelock, and harmless test target; direct / schedule / execute / cancel imports
through the official Safe UI; comparison of every official proposal field,
payload, and EIP-712 hash; resume after reload; fail-closed behavior; and the
Timelock lifecycle. Safe API connectivity, forced-failure classification,
notification text, and issue operations were also preflighted. However, Issue
#1245 was created and recovered manually, not by the GitHub Actions test-incident
delivery / recovery path. The raw result and reproduction evidence are
authoritative in
[2026-07-25 Issue #1201 Sepolia Evidence](../../../../jp/engineering/historical-reviews/2026-07-25-Issue-1201-Sepolia-Evidence/README.md).
Production promotion for Issue #1201 remains **Pending** until the authenticated
monitor runs on the default branch through the deployed Admin Console
same-origin proxy and proves workflow-created delivery / recovery plus the human
operator requirements.

Never elevate an arbitrary URL or operator-entered service base into an
authoritative source. Do not expose official Safe API credentials to the
browser; add them at the same-origin proxy. The proxy allowlists chain and
read-only endpoints, does not forward operator-session headers upstream, and
enforces server-side request-rate and concurrent-connection limits. Capacity
rejection returns `429` with backoff guidance.

The synthetic uses its own identity to traverse the deployed Admin Console
proxy, not a direct Safe API connection. It obtains the URL from the Admin
Console stack output and authentication from a fixed-name Secrets Manager secret
at runtime through a least-privilege GitHub OIDC role; do not copy either into a
GitHub variable or secret. Enable the hourly schedule only after proving that a
never-settling probe is physically terminated, the next healthy probe
automatically recovers, monitor-bootstrap failure still creates an escalation
issue, and authenticated aggregate quota, escalation recipient, and
workflow-driven delivery / recovery are verified. Do not copy the Safe API key
into the monitor.

## 6. Day-2 Enhancements

These may be added later but do not replace the Day-1 gate:

- deep Safe App integration;
- internal audit-log storage;
- approval workflow / change-request integration;
- searchable operation history;
- finer per-operation RBAC beyond the authentication gate.
