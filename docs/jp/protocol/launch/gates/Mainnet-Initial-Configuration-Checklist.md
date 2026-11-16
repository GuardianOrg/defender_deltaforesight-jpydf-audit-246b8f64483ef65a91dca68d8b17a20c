# Mainnet Initial Configuration Checklist

| 項目 | 内容 |
| --- | --- |
| Status | Active |
| 役割 | 子 Gate の完了確認と Deploy Broadcast / Public Activation の段階別 Go / No-Go |
| 正本関係 | 値・手順・固有 No-Go・固有 evidence schema は各子文書が管理し、本書では再掲しない |
| 対象 | Ethereum mainnet の fresh deploy、handover、Day-1 public activation |

secret、未公開 Safe nonce、raw RPC URL、個人 signer 情報は記録しない。証跡には provider label と redacted URL だけを残す。

---

## 1. 使い方

1. §2 の各行について、`Deploy` は最初の mainnet broadcast 前、`Activation` は実 deploy と handover 後かつ public activation 前に、正本側の Gate を完了する。
2. 子 Gate の No-Go を本書で再判定しない。未解消項目が 1 件でもあれば親も No-Go とする。
3. §3・§4 で、同じ段階の証跡が同じ candidate、manifest、state を参照し、Activation evidence が承認済み Deploy Broadcast と実 deploy に接続することを確認する。
4. §5 の段階別 No-Go が 0 件で、§6 の該当列の承認が揃った場合に限り、その段階へ進む。

本書のチェックを完了しても、Day-2 の bridge minter、inert branch、PIL active routing、追加 liquidity route を有効化する承認にはならない。

---

## 2. Gate Completion Matrix

`Status` は `Pending` / `Go` / `No-Go` / `N/A` のいずれかとする。`Deploy` 行は Deploy Broadcast 判定、`Activation` 行は Public Activation 判定にだけ使用する。領域名に「条件付き」とある行だけ `N/A` を許可し、`Evidence` に非適用の理由と有効化する surface を記録する。それ以外の行は必須である。`Evidence` にはファイル、hash、ticket など再検証可能な識別子を 1 つ記録する。

| Status | 適用段階 | 領域 | 正本 / Gate | 親 Checklist の完了条件 | Evidence |
| --- | --- | --- | --- | --- | --- |
| Pending | Deploy | 採用値・branch 構成 | [`Parameters.md`](../../../Parameters.md)、[`Mainnet-Launch-Product-Decision-Record.md`](../decisions/Mainnet-Launch-Product-Decision-Record.md) | immutable / mutable parameter と Day-1 launch 値が承認済み |  |
| Pending | Deploy | deploy mode・manifest schema | [`Deployment-Configuration-Spec.md`](../../../engineering/guides/Deployment-Configuration-Spec.md) | fresh `complete` deploy の形状と生成 manifest が確定 |  |
| Pending | Deploy | external address・env・toolchain | [`Mainnet-Deploy-Env-Freeze-Runbook.md`](./Mainnet-Deploy-Env-Freeze-Runbook.md) | address、env、salt、artifact、script、toolchain を freeze し preflight 完了 |  |
| Pending | Deploy | Strategy 採用 | [`Strategy-Selection-Policy.md`](../../operations/policies/Strategy-Selection-Policy.md) | branch × venue、none branch、cap / weight、activation 境界が承認済み |  |
| Pending | Deploy | fork stress | [`Mainnet-Fork-Stress-Gate.md`](./Mainnet-Fork-Stress-Gate.md) | 必須 scenario が同じ candidate と freeze 済み env で Go |  |
| Pending | Deploy | Safe・role・Timelock | [`Mainnet-Safe-Role-Assignment-Gate.md`](./Mainnet-Safe-Role-Assignment-Gate.md)、[`Mainnet-Timelock-Deploy-Runbook.md`](./Mainnet-Timelock-Deploy-Runbook.md) | holder、threshold、role、delay、admin renounce、consumer address が一致 |  |
| Pending | Activation | governance handover | [`Mainnet-Governance-Handover-Runbook.md`](./Mainnet-Governance-Handover-Runbook.md) | prepare、accept、final verify が完了し deployer 権限と pending owner が残らない |  |
| Pending | Activation | Proxy / UUPS | [`Deployment-Configuration-Spec.md`](../../../engineering/guides/Deployment-Configuration-Spec.md) | §4.1 の proxy 証跡が全対象で完了 |  |
| Pending | Activation | launch operation | [`Mainnet-Launch-Operation-Gate.md`](./Mainnet-Launch-Operation-Gate.md) | SP、bootstrap、LP、redemption、liquidation、monitoring、T+24h plan が Go |  |
| Pending | Activation | system risk・residual risk | [`Requirements-Verification-Ledger.md`](../../../engineering/verification-ledgers/Requirements-Verification-Ledger.md) §4.5、[`Incident-Notification-Policy.md`](../../../contributors/deltaforesight/operations/Incident-Notification-Policy.md)、[`Active-Branch-Cap-Ramp-Runbook.md`](../../operations/runbooks/Active-Branch-Cap-Ramp-Runbook.md) | `SYS-RISK-001..009` の launch evidence が揃い、特に 008/009 の cap 表示、実 capacity、追加借入 / 売却、APR の独立判断、cap-ramp handoff、residual-risk 承認が完了 |  |
| Pending | Activation | participant readiness | [`Mainnet-Participant-Readiness-Gate.md`](./Mainnet-Participant-Readiness-Gate.md) | borrower、SP depositor、liquidator の表示・運用条件が Go |  |
| Pending | Activation | frontend production | [`Frontend-Production-Delivery-Gate.md`](../../../contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md) | production data、security、rollback、monitoring が Go |  |
| Pending | Activation | surface 固有 frontend（条件付き） | [`Frontend-UX-Readiness-Gate.md`](../../../contributors/deltaforesight/delivery-plans/Frontend-UX-Readiness-Gate.md)、[`Frontend-Agent-Readiness-Gate.md`](../../../contributors/deltaforesight/delivery-plans/Frontend-Agent-Readiness-Gate.md)、[`Admin-Console-Production-Gate.md`](../../../contributors/deltaforesight/delivery-plans/Admin-Console-Production-Gate.md) | 有効化する surface の固有 Gate が Go。無効な surface は名称と非適用理由を記録 |  |
| Pending | Activation | treasury・accounting | [`Treasury-Safe-Retention-Runbook.md`](../../operations/runbooks/Treasury-Safe-Retention-Runbook.md) | Day-1 Safe-retention / read-only ledger mode、accounting owner、scan 起点、配分無効が freeze 済み |  |
| Pending | Deploy | audit scope・blocker | [`Contract-Audit-Scope-And-nSLOC.md`](../../../engineering/guides/Contract-Audit-Scope-And-nSLOC.md) | candidate 差分が監査 scope と一致し、launch blocker が未解消でない |  |
| Pending | Activation | dormant surface | [`Bridge-Minter-Activation-Gate.md`](../../operations/runbooks/Bridge-Minter-Activation-Gate.md)、PIL activation package | bridge は minter / pending proposal / active adapter なし、PIL active routing / campaign なし |  |

---

## 3. 共通 Completion Record

各子 Gate の evidence package は、少なくとも共通 field と該当段階の field を持つ。子 Gate 固有の field は各文書に置く。

| Field | 要件 |
| --- | --- |
| `candidateCommit` | review 対象の完全な Git SHA |
| `stage` | `Deploy` / `Activation` |
| `chainId` | mainnet は `1` |
| `forkBlock` | Deploy で必須。stateful dry-run を比較する固定 block |
| `deployTxHash` / `deployBlock` | Activation で必須。承認済み Deploy Broadcast に対応する実 deploy |
| `manifestSha256` | current `deployment-manifest.json` の hash |
| `artifactHash` | deploy 対象 artifact の hash または参照 |
| `applicableScope` | active / borrowable branch と有効化する frontend surface |
| `gateStatus` | `Go` / `No-Go` / `N/A` |
| `evidenceRef` | package、log、snapshot、ticket の参照 |
| `reviewers` / `reviewedAt` | 承認者 class と UTC 時刻 |

同じ段階で `candidateCommit`、state block、`manifestSha256` のいずれかが Gate 間で異なる場合は、差分を解消して該当 Gate を再実行する。Activation では `candidateCommit` と `artifactHash` が承認済み Deploy Broadcast から不変で、`deployTxHash`、`deployBlock`、current manifest が同じ実 deploy を指すことを確認する。例外承認で異なる state を混在させない。

---

## 4. 親 Checklist 固有の照合

### 4.1 Proxy / UUPS

DToken、CollateralVault、nonzero Strategy について、次を 1 つの proxy inventory で確認する。

- proxy address、ERC1967 implementation address、implementation codehash、implementation slot が candidate artifact と一致する。
- Transparent Proxy 用 admin slot など、UUPS 構成と矛盾する state がない。
- implementation address への直接 `initialize` が拒否される。
- final owner / upgrader / role holder が handover evidence と一致し、`pendingOwner == address(0)`。
- inert / none 対象に未承認の Strategy proxy がない。

### 4.2 Cross-Gate Reconciliation

- Activation の handover、frontend、ops、bot が同じ current manifest と実 deploy を参照する。
- branch数・mapping・parameter値がDay1 Parameter Manifest、active / cap-0 / inert状態がProduct Decision Recordに一致する。
- Activation の candidate commit と artifact が Deploy Broadcast の最終結果から変わっていない。
- enabled frontend surface と各行の `Go` / `N/A` 判定が `applicableScope` に一致する。
- token-unit env と on-chain readback が承認値に一致する。
- holder address と launch operation owner の参照先が Safe / role package に一致する。
- exception は owner、理由、期限、解除条件を持ち、未承認の例外を Go として扱わない。

---

## 5. Stage-specific No-Go

子 Gate の No-Go が未解消、evidence を参照できない、または共有版 evidence から secret、raw RPC URL、未公開 signer 情報を除去できていない場合は、どちらの段階も No-Go とする。

### 5.1 Deploy Broadcast

次のいずれかに該当する場合は mainnet broadcast を行わない。

- §2 の `Deploy` 必須行に `Pending` / `No-Go` / `N/A` がある。
- candidate commit、fork block、manifest、artifact の対応が崩れている。
- §6 の Deploy Broadcast 承認列がすべて `Go` でない。

### 5.2 Public Activation

次のいずれかに該当する場合は public activation を行わない。

- §6 の Deploy Broadcast 最終結果が `Go` でない、または実 deploy の candidate commit / artifact がその結果と一致しない。
- §2 の `Activation` 必須行に `Pending` / `No-Go` / `N/A` がある、または条件付き行の `N/A` に理由と対象 surface がない。
- final on-chain readback が env、manifest、holder package、consumer config のいずれかと不一致。
- deployer 権限、unexpected pending owner、未承認 proxy / Strategy、active bridge / PIL route が残る。
- §6 の Public Activation 承認列がすべて `Go` でない。

---

## 6. Final Sign-off

| Role | Deploy Broadcast | Public Activation | Evidence / Comment |
| --- | --- | --- | --- |
| Product | Pending | Pending |  |
| Risk | Pending | Pending |  |
| Finance | Pending | Pending |  |
| Security / Audit | Pending | Pending |  |
| Engineering | Pending | Pending |  |
| Operations | Pending | Pending |  |
| Launch owner | Pending | Pending |  |

Deploy Broadcast は `Deploy` 必須行と Deploy Broadcast 承認列がすべて `Go` で、§5.1 の No-Go が 0 件の場合だけ `Go` とする。Public Activation は Deploy Broadcast の最終結果が `Go`、`Activation` 必須行と Public Activation 承認列がすべて `Go`、条件付き行が `Go` または根拠付き `N/A` で、§5.2 の No-Go が 0 件の場合だけ `Go` とする。

| Stage | Final result | Candidate commit | Manifest sha256 | Reference block | Approved at |
| --- | --- | --- | --- | --- | --- |
| Deploy Broadcast | Pending |  |  | `forkBlock`:  |  |
| Public Activation | Pending |  |  | `deployBlock`:  |  |
