# Frontend Mirror Delivery Policy

Updated: 2026-07-26

この runbook は `FRNT-TBD-006`（IPFS / ENS 等による mirror 配信）の
Day-1 方針と、Day-2 で採用する場合の gate を定義する。日本語版を source of
truth とし、Frontend spec の `FRNT-SEC-002` / `FRNT-SEC-005` /
`FRNT-SEC-008` / `FRNT-GOV-001` / `FRNT-GOV-002` / `FRNT-ERR-001` /
`FRNT-ERR-002` / `FRNT-ERR-006` と連動する。

Day-1 mainnet launch の canonical delivery は
[Frontend-Production-Delivery-Gate.md](./Frontend-Production-Delivery-Gate.md)
で定義する会社所有の公式 HTTPS origin とする。mirror 配信は Day-1 launch
gate の代替ではなく、Day-2 optional の resilience 手段に限定する。Day-2 の
mirror artifactにも同gateのlive-data、credential、redaction、monitoring、
release要件を適用し、本書はmirror固有の差分だけを規定する。

## 1. Decision

Day-1 では mirror 配信を採用しない。理由は以下。

- 公式 domain / hosting / RPC / stats の所有・監視・rollback 証跡を先に固定する必要がある。
- IPFS CID は immutable であり、誤配信・古い bundle・incident banner 更新漏れの回収が難しい。
- ENS / gateway 経由の URL は phishing、domain allowlist、wallet connection、RPC key
  restriction の運用を複雑にする。
- stats JSON / subgraph / RPC の stale 状態を mirror 上で live current value と誤認させるリスクがある。
- admin console、operator-only 情報、private endpoint が public bundle に混入した場合の blast
  radius が大きい。

Day-2 で採用する場合も、公式 HTTPS origin が primary / canonical であり続ける。mirror は
公式 origin 障害時の read-only fallback、または censorship/outage resilience の補助導線であり、
通常の product entrypoint にはしない。

## 2. Scope

mirror 対象にしてよいもの:

- `frontend/app` の public user app static bundle。
- public stats JSON。ただし `generatedAt`、source block、schema version、official origin
  metadata、freshness indicator を維持する場合に限る。
- official link ledger と build manifest の公開 copy。

mirror 対象外:

- `frontend/console` の Admin Control / Private Operations Monitor。
- Dune Public Analytics（外部analytics配信であり、mirror artifactの対象外）。
- Safe calldata draft、private role snapshot、operator-only runbook、incident-only dashboard。
- private RPC URL、API key fragment、subgraph private endpoint、secret-bearing environment。
- write-enabled admin/ops surface。
- production delivery gate を通っていない preview / staging / localhost build。

## 3. Adoption Gate

Day-2 で mirror を有効化する前に、以下をすべて満たす。

| Gate | Requirement | Evidence |
| --- | --- | --- |
| Canonical origin | 公式 HTTPS origin を primary とし、mirror は fallback と明示する。 | official URL table、mirror URL table、link ledger |
| Same commit | mirror bundle は公式 production と同一 commit / config / deployment manifest から build する。 | build commit、config hash、deployment manifest hash、bundle hash |
| Public metadata | mirror 画面に canonical origin、build commit または build hash、chainId、contract manifest hash を確認できる導線を置く。 | screenshot、runtime health JSON |
| Static-only boundary | public bundle に admin console、private endpoint、operator-only route が含まれない。 | bundle/env redaction check、route map |
| RPC and wallet safety | chainId、RPC provider、domain allowlist、wallet connection が mirror origin でも検証済み。未検証なら write UI は read-only に落とす。 | RPC health、wallet connect drill、domain allowlist evidence |
| Incident workflow | 公式 origin 障害時に mirror URL をどの公式 channel で告知するか、誰が承認するかを定義する。 | announcement template、approver list |
| Rollback model | CID / ENS contenthash 更新、旧 CID の扱い、cache / gateway purge 不可時の告知を記録する。 | rollback target、新 CID、ENS update tx、announcement copy |

## 4. No-Go Conditions

以下が残る場合、mirror を公開しない。

- mirror を Day-1 の first / only launch URL にする。
- 公式 production gate の domain / hosting / RPC / stats evidence が未完了。
- mirror build の commit、config hash、deployment manifest hash、CID が不明。
- admin console、private RPC URL、operator-only route、Safe draft が public bundle に含まれる。
- RPC provider の domain allowlist が mirror origin を想定していない。
- CID / ENS contenthash の rollback・告知手順がない。

## 5. Evidence Template

```
Frontend mirror delivery evidence
Date:
Operator:
Common production evidence ID:
Canonical user app URL:
Mirror type: IPFS / ENS / other
Mirror URL:
ENS name:
IPFS CID:
Bundle hash:
Canonical origin display evidence:
Allowed mirror domains:
Wallet connection drill:
Bundle/env redaction check:
Incident announcement channel:
Approver:
Rollback target:
ENS contenthash update tx:
Go / No-Go:
```

## 6. Operator Workflow

1. Confirm the canonical production delivery gate is complete.
2. Build the mirror bundle from the exact production commit and config.
3. Record deployment manifest hash, generated binding hash, bundle hash, and CID.
4. Run the common runtime health and negative drills against the mirror origin.
5. Verify the public bundle has no admin console URL, private RPC URL, operator-only route,
   Safe draft, key fragment, or private signer information.
6. Verify wallet connection and domain allowlist. If not fully verified, keep write UI disabled.
7. Record official announcement copy and rollback/new-CID procedure.
8. Publish mirror link only through official channels after approval.

## 7. Relationship To Other Gates

- Production domain / hosting / RPC / stats ownership:
  [Frontend-Production-Delivery-Gate.md](./Frontend-Production-Delivery-Gate.md)。
- i18n / mobile:
  [Frontend-UX-Readiness-Gate.md](./Frontend-UX-Readiness-Gate.md)。
- Admin console:
  [Admin-Console-Production-Gate.md](./Admin-Console-Production-Gate.md)。
