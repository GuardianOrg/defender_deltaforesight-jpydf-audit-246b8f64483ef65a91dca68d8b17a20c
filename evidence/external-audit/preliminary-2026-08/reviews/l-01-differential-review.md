# L-01 Differential Security Review

## Executive summary

| Severity | New findings |
| --- | ---: |
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |

**Overall residual risk:** Low.

**Recommendation:** Approve the narrow idempotent-retry remediation. Describe
it as eliminating the revert-based failure, not as eliminating gas expenditure.

The functional production diff is one branch: a settled, existing withdrawal
request returns zero instead of reverting. No storage layout, external selector,
authority, beneficiary, transfer amount, or first-settlement path changes.

## Review scope

**Source baseline:** `fe3d3d0e182b8189202dee3a3db8103bd0df1de7` plus the
ordered M-01 and M-02 overlays.

**Audit-repository baseline:** `fa1479daf87dee8bfeb1454eb9c733f6970647cc`

**Review date:** 2026-08-12

| Area | Change | Risk |
| --- | --- | --- |
| Vault claim branch | Settled existing request returns `0` | Medium |
| Interface NatSpec | Documents the existing return value's new settled meaning | Low |
| Focused regression | Models third-party settlement followed by owner retry | Medium |
| JP/EN specifications and ledgers | Define idempotence and disclose the remaining gas cost | Low |
| Snapshot reconstruction and evidence | Adds the third ordered, hash-pinned preliminary overlay | Medium |

## Changed-state analysis

The check order is security-relevant:

1. load the request and cache its recorded owner;
2. reject `owner == address(0)` as an unissued ID;
3. return zero if the existing request is already claimed;
4. otherwise enforce maturity and buffer sufficiency;
5. mark claimed and decrement pending liabilities;
6. transfer only to the cached owner and emit one settlement event.

Because existence is checked before idempotence, arbitrary IDs do not become
successful no-ops. Because idempotence exits before any accounting or external
call, a retry cannot transfer twice, decrement twice, emit a duplicate indexer
signal, or depend on current buffer and maturity state.

The `whenNotPausedClaim` and `nonReentrant` modifiers still execute before the
function body. A paused settled retry therefore reverts with the existing pause
policy; the remediation does not bypass incident control. If the initial token
transfer reverts, EVM atomicity rolls back `claimed` and `pendingWithdrawals`, so
the request remains unsettled rather than being hidden by the new return path.

## Security invariants

- only an existing request can receive idempotent treatment;
- exactly one successful settlement transfers the recorded amount;
- all successful value goes to `req.owner`, never `msg.sender`;
- the front-runner receives no fee or entitlement;
- `pendingWithdrawals` decreases exactly once;
- the settled flag remains true after a retry;
- the retry emits no second `WithdrawClaimed` or ERC-20 transfer event;
- a failed first transfer leaves the request retryable;
- pause, maturity, buffer, and reentrancy behavior for unsettled requests is unchanged.

## Adversarial review

| Attempt | Result |
| --- | --- |
| Front-run an owner's matured claim | Owner is paid once; later owner call returns zero |
| Claim an invented ID | Still reverts `RequestNotFound` |
| Use a third-party caller to redirect payout | No receiver parameter; stored owner remains the only beneficiary |
| Reenter from the token transfer | Existing `nonReentrant` guard remains; idempotent branch makes no external call |
| Force the first transfer to revert | Entire transaction rolls back; request stays unclaimed and pending |
| Retry after buffer is later depleted | Settled request returns zero without inspecting or consuming buffer |
| Retry while claims are paused | Modifier preserves the existing `Paused` incident behavior |
| Depend on a duplicate event to refresh an indexer | No duplicate event is emitted; consumers must treat zero return/current state as already settled |

No fund-loss, privilege-escalation, reentrancy, storage-layout, or unbounded-work
defect was introduced.

## Alternative assessment

Requiring `msg.sender == owner` would stop third-party front-running but regress
the previous external-audit remediation that made fixed-payout claims callable
for contract receivers without arbitrary execution capability. That tradeoff is
not acceptable.

A caller fee does not repair the stated victim's gas cost when paid to the
request owner, and a fee paid to the executor would incentivize the exact race.
Either design also changes liabilities and token flows. The zero-return branch
is the smallest change consistent with the current permissionless fixed-payout
model.

## Tests and negative evidence

| Gate | Result |
| --- | --- |
| CollateralVault focused suites | 197 passed / 0 failed |
| Push-model invariant suite | 4 passed / 0 failed; 500 runs and 25,000 calls per invariant |
| Standard Foundry PR gate | 1,547 passed / 0 failed / 0 skipped, 81 suites |
| Production contract-size gate | Passed; CollateralVault 23,032 bytes, margin 1,544 bytes |
| Production-source format check | Passed |
| Test-file formatter inspection | Only unrelated pre-existing drift after the changed block |
| Source diff check | Passed |
| Pre-fix mutation | New regression reverted with `RequestNotFound` as expected |
| Post-fix rerun | Same regression passed and observed zero logs on retry |
| Overlay application | Applied after M-01/M-02 and reconstructed the changed snapshot/docs |

## Blast radius

The ABI remains `claim(uint256) returns (uint256)` and its selector is
unchanged. On first settlement, all branches and effects are byte-for-byte
unchanged. The only consumer-visible difference is that an existing settled ID
returns `0` instead of reverting `RequestNotFound`.

Frontend ABI regeneration is unnecessary because errors are not added or
removed and the function signature is unchanged. Off-chain code that used the
revert as a completion signal must accept the new documented zero result. This
repository explicitly does not preserve backward compatibility, and the JP
source-of-truth plus EN support text and verification ledger were updated in
the same overlay.

## Historical context

Source commit `02bc91f8` removed owner-only authorization and fixed the payout
to the stored request owner to address contract-receiver liveness. Its dated
differential review correctly records the behavior at that time, including a
double-claim revert. It remains unchanged as historical evidence; current
specifications and this L-01 review supersede only the settled-retry behavior.

## Residual risk and limitations

The on-chain function cannot prevent a public transaction from being copied or
prevent gas use by a transaction that was already submitted. A successful
zero-return receipt improves idempotent integration and avoids revert-based
failure handling, but the sender still pays execution gas. Wallets and relayers
should refresh request state, replace/cancel stale transactions where possible,
or use protected ordering if this cost matters.

This was a surgical differential review of L-01, not a re-audit of all Vault or
ERC-20 behavior. No live mainnet fork is required to reproduce a deterministic
local race between two calls on the same request.
