---
jip: JIP-YYYY-NNN
template_version: 1
title: "<proposal title>"
visibility: public
class: N
status: Draft
proposer: "<proposer>"
sponsor: "<signer block or null>"
intake_issue: "<public GitHub issue URL>"
discussion: "<public GitHub discussion URL>"
governance_surface_ref: "<registry entry>"
review:
  opened_at: null
  closes_at: null
  external_security: not_required
notice:
  approved_at: null
  execution_not_before: null
  expires_at: null
package_sha256: null
verification:
  calldata_hash: null
  simulation_ref: null
  independent_reviewer: null
execution:
  safe_tx: null
  timelock_operation: null
  tx_hash: null
  status: not_started
readback: null
external_records: []
---

# JIP-YYYY-NNN: <Proposal Title>

<!-- BEGIN DECISION PACKAGE -->

## 1. Summary

<One-paragraph outcome.>

## 2. Motivation

<Problem, current state, and why action is needed.>

## 3. Class and Governance Surface

- Class and rationale:
- Role / holder:
- Governance Surface Register entry:
- Applicable policy / runbook:
- Pre-approval framework, if any:

## 4. Specification

| Order | Chain ID | Target | Value | Function / selector | Arguments | Expected calldata / hash |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | `<address / manifest ref>` | 0 | `<function>` | `<typed args>` | `<hash>` |

- Safe / Timelock path:
- Preconditions:
- Expected post-state:
- Operations expressly not authorized:

## 5. Stakeholder Impact and Exit

- Affected users / integrators:
- Economic / security effect:
- Available exit path:
- Longest exit duration, including `withdrawDelay`:
- Notice and execution-not-before calculation:

## 6. Security and Risk

- Threat model / failure modes:
- External review:
- Invariants:
- Residual risk:
- Conflicts / recusal:

## 7. Verification Plan

- Independent calldata decode:
- Fork block / state:
- Simulation command / evidence:
- Expected events:
- Post-state readback:

## 8. Rollback / Recovery

- Reversible elements:
- Irreversible elements:
- Cancellation path before execution:
- Recovery proposal required after execution:

## 9. Foundation Linkage

- Company-side off-chain act required: `<yes / no>`
- Required CDR: `<CDR ID / none>`
- Confirmation that the CDR does not approve the protocol transaction:

<!-- END DECISION PACKAGE -->

## 10. Approval Register

| Signer block | Keys counted | Vote | Package SHA-256 | Conflict / recusal | Reason / signature ref | Timestamp |
| --- | --- | --- | --- | --- | --- | --- |
| `<block>` | `<N>` | `<FOR / AGAINST / ABSTAIN / RECUSED>` | `<hash>` | `<none / ref>` | `<URL / ref>` | `<ISO-8601 UTC>` |

Approval record format:

```text
RECORD-TYPE: JIP-VOTE
ID: JIP-YYYY-NNN
PACKAGE-SHA256: <64 hex>
VOTER: <registered signer block>
CAPACITY: Protocol Signer Block
VOTE: FOR | AGAINST | ABSTAIN | RECUSED
CONFLICT: none | <disclosure ref>
REASON: <reason or stable URL>
TIMESTAMP: <ISO-8601 UTC>
SIGNATURE-REF: <EIP-191 / EIP-1271 evidence ref>
```

## 11. Objection and Response Register

| Objection | Raised by | Response | Materiality | Resolved at |
| --- | --- | --- | --- | --- |
| `<summary>` | `<actor>` | `<response / ref>` | `<material / non-material>` | `<timestamp or open>` |

## 12. Execution Record

- Executed by / capacity:
- Wallet / address or Safe reference:
- Authority source: `<Protocol Governance policy / authorized role>`
- Decision / authorization evidence: `<approved JIP ID + approved package hash>`
- Signature / execution reason:
- Approved package SHA-256:
- Safe transaction hash / URL:
- Timelock operation ID:
- Queue / execute timestamp:
- On-chain tx hash:
- Executed calldata hash:
- Approved package match: `<pass / fail>`

## 13. Readback and Close

- Readback block / timestamp:
- Expected vs actual post-state:
- Events:
- Deviation / incident:
- Closed by / at:
