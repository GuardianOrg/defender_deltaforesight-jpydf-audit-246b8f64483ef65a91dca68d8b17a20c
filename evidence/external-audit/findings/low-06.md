# Low 06 — Deployer And Handover Holder Private Keys Loaded From Environment Variables

| Item | Value |
| --- | --- |
| Reported severity | Low |
| Status | Closed — audit-approved (2026-08-05) |
| Proposed disposition | Low accepted with claim correction |
| Candidate implementation | [jpydf-v2#1406](https://github.com/deltaforesight/jpydf-v2/pull/1406) (merged as `4df6d902` ahead of audit approval) |

Production-capable scripts and the deploy CLI unnecessarily accepted and
forwarded raw private keys, although the report overstated the production role
of the documented local/CI accept helper. PR jpydf-v2#1406 made `DEPLOYER`
public-address-only, moved signing to explicit Foundry
Ledger/keystore/KMS/Trezor modes, restricted unlocked signing to local/dev or
loopback fork RPCs, and fail-closed the remaining deterministic-key helpers to
chain 31337/31338. It merged after 1,453-test Foundry, a real 8-branch Anvil
deployment, signer-negative checks, and the standard review battery.

## Audit decision (2026-08-05)

| Item | Value |
| --- | --- |
| Verdict | Approved as merged ahead of audit approval |
| Approved diff | jpydf-v2 `1adab166..4df6d902` ([#1406](https://github.com/deltaforesight/jpydf-v2/pull/1406)) |
| Diff SHA-256 | `88c57b234a69432eeece381f72514bae5a307babcb2aaf3972fe979608f25111` |
| Diff size | 22 files changed, 407 insertions(+), 80 deletions(-) |
| Test evidence | Merge-time regression battery recorded in the proposed-disposition prose. |

Basis: the merge-time evidence cycle recorded in the proposed-disposition
prose. The merged diff is adopted as the approved diff; the sync step
verifies the merge commit remains reachable from jpydf-v2 `develop`.

## Snapshot application (2026-08-05)


Applied to this repository by PR [#58](https://github.com/deltaforesight/jpydf-audit/pull/58): the approved diff's `contracts/{src,script,test}` changes landed in `source-snapshot/contracts/`, plus doc-mirror hunks whose context matched exactly. The full approved diff remains authoritative at [`patches/low-06.patch`](../patches/low-06.patch).

Deferred doc-mirror hunks (mirror drift; see the preserved patch): `documents/en .../Mainnet-Deploy-Env-Freeze-Runbook.md`; `documents/en .../Mainnet-Governance-Handover-Runbook.md`; `documents/jp .../Mainnet-Governance-Handover-Runbook.md`.

Outside snapshot curation scope: `contracts/script/SeedLocalDemo.s.sol`; `documents/en+jp .../Deployment-Configuration-Spec.md`.

## Fix-quality review (2026-08-05)

Verdict: **approve with nits**. Two independent layers verified: the Solidity
`ScriptSecurityPolicy` chain-id allowlist (31337/31338, not spoofable — a
mainnet fork reporting chainid 1 is refused) plus `requirePublicAddress`
rejecting key-shaped `DEPLOYER` on all chains, and the deploy CLI's
one-signer rule with `--unlocked` restricted to local chain ids or loopback
RPC hosts. `privateKeyToAccount` is removed from the CLI; CI switched to a
public address + `--unlocked` against localhost. Signer-negative Foundry
tests pass; the CLI logic itself has no unit tests (follow-up).

Owner decision (2026-08-05): the Console devnet timelock scripts
(`DeployConsoleDevnetTimelock.s.sol`, `PrepareConsoleDevnetTimelockHandover`,
`FinalizeConsoleDevnetTimelockHandover`) still read raw env keys under a
weaker guard (`expectedChainId != 1` only), so they could broadcast with an
env key on non-mainnet public chains. **Accepted as a devnet-only residual**;
tightening them to the 31337/31338 allowlist is recorded as an optional
post-merge follow-up.
