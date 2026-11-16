# jpydf-v2 開発計画

| 項目 | 内容 |
| --- | --- |
| Status | Active |
| 役割 | 未完了の開発・launch・監査作業を横断して示す進捗トラッカー |
| 正本関係 | 要件は `protocol/product/spec/`、値は `Parameters.md`、判断理由は `decisions/`、実行手順と判定は Runbook / Gate、検証結果は ledger / review を正とする |
| 対象外 | 完了PR・コミット・解決済み判断の履歴、仕様や値の再掲 |

完了済み作業は Git 履歴と [`reviews/`](../historical-reviews/) に残す。本書には、現在の作業、依存関係、完了条件だけを置く。

## 1. 開発ガードレール

1. **仕様が規範である。** 実装・テスト・監査は `documents/jp` の要件 ID を基準にする。コードとの差分は監査所見として扱い、実装の現状だけを理由に承認済み仕様を書き換えない。とくに Strategy は文書を正とし、監査中のコードは本書の更新対象にしない。
2. **値を重複管理しない。** 担保、リスク、governance、oracle の確定値は [`Parameters.md`](../../Parameters.md) を参照する。
3. **Core 差分を限定する。** JPYdf canonical surface は CI guard、許容差分は [`Liquity-v2-Core-Spec.md`](../../protocol/product/spec/Liquity-v2-Core-Spec.md) の `CORE-MOD-*` 台帳と parity test で確認する。
4. **変更と検証を分離しない。** 各変更で影響する build、test、fork、E2E、guard を実行し、新規 skip や未説明の carve-out を残さない。
5. **本番構成を段階的に検証する。** local Anvil、mainnet fork、Sepolia、mainnet の順に、production contract と実際の権限分離を維持したまま外部依存と異常系を検証する。
6. **launch は証跡で判定する。** 実装済みという説明ではなく、対応する Gate の readback、negative drill、artifact を揃えて Go / No-Go を決める。

## 2. 現在の作業

| Workstream | 状態 | 残作業 | 完了判定 |
| --- | --- | --- | --- |
| 8 Branch 実装同期 | In progress | `Parameters.md`、Core 定数、deploy / manifest、frontend / ops metadata の branch 0–7 対応、active / inert 配線、dry-run、機械突合 CI | [`Parameters.md`](../../Parameters.md)、[`Deployment-Configuration-Spec.md`](../../engineering/guides/Deployment-Configuration-Spec.md)、[`Requirements-Verification-Ledger.md`](../verification-ledgers/Requirements-Verification-Ledger.md) |
| Phase 4 — Deploy / Wiring | In progress | mainnet 外部依存の凍結、holder / Timelock の確定、Sepolia rehearsal、active branch の最終 manifest と readback | [`Mainnet-Initial-Configuration-Checklist.md`](../../protocol/launch/gates/Mainnet-Initial-Configuration-Checklist.md) |
| Phase 5 — Zapper / user flow | In progress | 採用する Zapper の deploy / binding / user app flow と JPYdf/USDC route の審査 | [`Zapper.md`](../../protocol/product/spec/Zapper.md)、[`Frontend-Production-Delivery-Gate.md`](../../contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md) |
| LidoStrategy deploy surface exclusion | Blocked | 監査 freeze 解除後の8 Branch実装同期で、source / testを保持したまま公式deploy scriptのLido固有selector・deploy / register helper・env readerを削除する。`lido`はgeneric unknown-kind fallbackで失敗させ、preflight / manifestは承認済みStrategy setを汎用照合する | [`LidoStrategy.md`](../../archive/LidoStrategy.md)、[`Deployment-Configuration-Spec.md`](../guides/Deployment-Configuration-Spec.md) |
| Phase 7 — 監査準備 | In progress | 要件カバレッジ、不変条件、脅威モデル、Core parity、8 Branch 最終実装との差分分類、外部監査 package の完了 | [`formal-verification-audit-plan.md`](./formal-verification-audit-plan.md)、[`Requirements-Verification-Ledger.md`](../verification-ledgers/Requirements-Verification-Ledger.md) |
| Launch ops / peg response | In progress | Vault buffer refill planner、下方乖離の上限付き実行、上方乖離の Safe 手動例外、privileged signer、監視・停止・drill の完了 | [`Mainnet-Launch-Operation-Gate.md`](../../protocol/launch/gates/Mainnet-Launch-Operation-Gate.md)、[`Vault-Buffer-Refill-Keeper-Runbook.md`](../../contributors/deltaforesight/operations/Vault-Buffer-Refill-Keeper-Runbook.md)、[`Liquidity-Management-Policy.md`](../../protocol/operations/policies/Liquidity-Management-Policy.md)、[`Mainnet-Role-Assignment-Allocator-Signer-Policy.md`](../../protocol/launch/gates/Mainnet-Role-Assignment-Allocator-Signer-Policy.md) |
| 清算運用 | In progress | mainnet / Sepolia 設定、鍵管理、監視、ABI 整合、運用手順の凍結 | [`Liquidation-Bot-Plan.md`](./Liquidation-Bot-Plan.md)、[`Mainnet-Launch-Operation-Gate.md`](../../protocol/launch/gates/Mainnet-Launch-Operation-Gate.md) |
| Foundation readiness | In progress | 全5 holderの受諾・KYC/KYB・署名、nominee / 残るMIDAO package、Foundation Operating Multisig、DFKK 越境 service / transaction controls、private governance repository、closing package と非公開 evidence の整合。M1–M5 address、OA DOCX提出、RMI counsel review、日本法務・税務の社内分析は完了済み | [`Foundation-Entity-Setup-Requirements.md`](../../foundation/requirements/Foundation-Entity-Setup-Requirements.md)、[`Foundation-Entity-OA-Execution-Checklist.md`](../../foundation/runbooks/Foundation-Entity-OA-Execution-Checklist.md) |
| Day-2 revenue distribution | Future Draft | Treasury / Distributor の実装、テスト、監査、activation approval | [`Treasury.md`](../../protocol/roadmap/spec/Treasury.md)、[`Protocol-Revenue-Allocation-Policy.md`](../../protocol/roadmap/policies/Protocol-Revenue-Allocation-Policy.md) |

### 2.1 Phase 4 — Deploy / Wiring

残作業は次の証跡 package で管理する。

- feed address、外部 protocol、fork block、artifact は [`Mainnet-Deploy-Env-Freeze-Runbook.md`](../../protocol/launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md)。
- Safe / Timelock / deployer / bot wallet の holder、threshold、consumer readback は [`Mainnet-Safe-Role-Assignment-Gate.md`](../../protocol/launch/gates/Mainnet-Safe-Role-Assignment-Gate.md)。
- dUSDC Morpho を有効にする条件は [`Morpho-Day1-Vault-Freeze-Package.md`](../../protocol/launch/gates/Morpho-Day1-Vault-Freeze-Package.md)。
- branchのactive / inert状態は [Mainnet Launch Product Decision Record](../../protocol/launch/decisions/Mainnet-Launch-Product-Decision-Record.md)、parameter値は [Day1 Parameter Manifest](../../Parameters.md)、Strategy選定は [`Strategy-Selection-Policy.md`](../../protocol/operations/policies/Strategy-Selection-Policy.md) を正本とする。
- dwstETH をlaunch対象に含める条件は [Day1 Parameter Decision](../../protocol/launch/decisions/Day1-Parameter-Decision.md) §4と [Oracle](../../protocol/product/spec/Oracle.md) `ORCL-FR-015` / `ORCL-SEC-001`に従う。
- branch 0–7 の symbol、immutable parameter、dToken / Vault / PriceFeed、deploy manifest、frontend / ops metadata は同じ構成へ同期し、機械突合を通す。

Phase 4 は、8 Branch の実装同期と deploy dry-run が完了し、最終 manifest と on-chain readback が一致し、未確定値、暫定 holder、未説明の route がなく、Checklist の全必須 Gate が完了した時点で完了とする。

### 2.2 Phase 5 — Zapper / user flow

対象は Day-1 に採用する経路だけとする。

- active branch の Zapper を deploy manifest、generated binding、user app flow へ一貫して接続する。
- JPYdf/USDC route は [`Liquidity-Route-Policy.md`](../../protocol/product/policies/Liquidity-Route-Policy.md) に従って審査する。
- 直接経路を残す場合も、表示、quote、approval、署名、receipt、failure recovery を production Gate で検証する。

未採用 route や将来候補を Day-1 完了条件へ混在させない。

### 2.3 Phase 7 — 監査準備

監査準備は次をすべて満たした時点で完了とする。

- current audit scope の FR / INV / SEC / GOV / EVT / ERR が verification ledger に一意に対応し、未カバーがない。
- invariant、fork、integration、negative test の必要な組合せが実走済みである。
- actor、権限、外部依存、upgrade、emergency path の threat model が current code と一致する。
- `base` との差分が `CORE-MOD-*` と一致し、Core JPYdf surface guard が通る。
- 8 Branch の最終実装差分を file 単位で分類し、外部追加監査、auditor delta review、internal parity review、operational review、将来 activation のいずれで扱うかが確定している。
- dwstETH BranchとOracleの確定実装差分を2026年8月中に外部追加監査へ戻す。実装差分の確定後にSOWをfreezeし、launch-blocking findingの対応完了をgo / no-go evidenceへ残す。
- LidoStrategy の公式 deploy surface 除外を確認し、source / test、async 基底の test coverage、履歴要件 ID を維持する。
- audit scope、対象 commit、既知事項、除外範囲を外部監査人へ渡せる。

`TRSY` / `SPARD` / `BRRD` / `SPDRD` は Day-2、`MCHN` は履歴 ID のため current audit coverage に含めない。

### 2.4 横断バックログ

各項目の実装詳細は所管計画・台帳に置き、本書では完了条件だけを追う。

- frontend owned surface から不要な BOLD 互換名がなく、上流由来の識別子と区別できる。
- RPC、indexer、hosting、repository の所有と秘密管理が production policy に一致する。
- required CI check と flaky test の扱いが監査前に確定している。
- [`Requirements-Verification-Ledger.md`](../verification-ledgers/Requirements-Verification-Ledger.md) の検証キャンペーンが current commit に対して完了している。

## 3. 依存順序

1. 8 Branch の仕様を Core 定数、deploy、manifest、frontend / ops へ同期し、機械突合と dry-run を完了する。
2. mainnet 外部依存、holder、Strategy venue evidence を凍結する。
3. deploy / wiring を完了し、mainnet fork と Sepolia で同じ manifest を検証する。
4. user app、ops、admin の binding、Day-1 route、buffer refill、peg response、privileged signer を確定し、production Gate を完了する。
5. current audit scope のカバレッジ、8 Branch delta の分類、LidoStrategy の非 activation / deploy surface 境界、外部監査 package を完了する。
6. Foundation closing package と非公開 evidence の整合を確認する。
7. [`Mainnet-Initial-Configuration-Checklist.md`](../../protocol/launch/gates/Mainnet-Initial-Configuration-Checklist.md) で最終 Go / No-Go を判定する。

Day-2 の Treasury / Distributor、cap 0 branch の Strategy、有効化前の将来 route はこの順序の外に置き、それぞれの activation gate で扱う。

## 4. 未解決の設計判断

本書で管理する未解決の設計判断はない。新しい判断が必要になった場合は、所管する spec、`Parameters.md`、design、Decision Record のいずれかで確定し、本書には blocker と完了条件だけを記載する。

## 5. PR 完了条件

- 変更対象の仕様 ID と実装・テストの対応を示せる。
- 影響範囲の build、test、fork、E2E、CI guard が green である。
- `git diff --check` が通り、意図しない scope の差分がない。
- security、異常系、rollback、readback の必要な証跡が Gate / ledger に残る。
- active plan に完了PR一覧や解決済み判断を追記しない。

## 参照

- 背景と過去の教訓: [`Retrospective.md`](../historical-reviews/Retrospective.md)
- 製品の上位要件と launch blocker: [`Product-Overview.md`](../../protocol/product/Product-Overview.md)
- 文書索引: [`engineering/README.md`](../README.md)
