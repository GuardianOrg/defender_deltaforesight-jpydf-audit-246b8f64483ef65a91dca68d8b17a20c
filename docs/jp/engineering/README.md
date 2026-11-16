# Engineering Documents

JPYdfの実装・検証を担当するContributorが使用する、計画、技術Guide、検証台帳を置く。

このフォルダの文書は、Protocol Governanceが決定する機能・Policy・parameterや、DeltaForesight株式会社が自社資金・担当者・運用体制について行うcommitmentを定めない。Protocolの正本は[`../protocol/`](../protocol/)、DeltaForesight固有の正本は[`../contributors/deltaforesight/`](../contributors/deltaforesight/)を参照する。

## フォルダ構成

| フォルダ | Artifact | 扱うもの |
| --- | --- | --- |
| [`plans/`](./plans/) | Runbook / delivery plan | 実装順序、担当範囲、完了条件 |
| [`guides/`](./guides/) | Spec / Runbook / Evidence | deployment実装仕様、開発・検証手順、監査scope・usage map |
| [`verification-ledgers/`](./verification-ledgers/) | Evidence | requirementと検証結果の対応 |
| [`historical-reviews/`](./historical-reviews/) | Historical / Evidence | 日付つきreview、過去の検証campaign、再構築の背景。現行の正本として使用しない |

将来施策は[`../protocol/roadmap/`](../protocol/roadmap/)、Day 1 gateは[`../protocol/launch/`](../protocol/launch/)または[`../contributors/deltaforesight/delivery-plans/`](../contributors/deltaforesight/delivery-plans/)で管理する。

## Plans

| 文書 | 対象 |
| --- | --- |
| [`Development-Plan.md`](./plans/Development-Plan.md) | 横断的な実装・launch・監査作業と依存順序 |
| [`AWS-CDK-Hosting-Plan.md`](./plans/AWS-CDK-Hosting-Plan.md) | AWS CDK hosting |
| [`AWS-Devnet-Frontend-Test-Plan.md`](./plans/AWS-Devnet-Frontend-Test-Plan.md) | hosted Anvil frontend検証 |
| [`Frontend-AWS-Refactor-Plan.md`](./plans/Frontend-AWS-Refactor-Plan.md) | frontend / AWS refactor |
| [`Frontend-Development-Plan.md`](./plans/Frontend-Development-Plan.md) | frontend実装 |
| [`Liquidation-Bot-Plan.md`](./plans/Liquidation-Bot-Plan.md) | liquidator backend実装 |
| [`Hyperliquid-Market-Data-Compatibility-API-Implementation-Plan.md`](./plans/Hyperliquid-Market-Data-Compatibility-API-Implementation-Plan.md) | 東京non-validator node、L4再構成、欠損修復、0xArchive互換REST / WS API |
| [`Public-Docs-Content-Plan.md`](./plans/Public-Docs-Content-Plan.md) | public docs整備 |
| [`Redemption-Risk-Monitoring-Implementation-Plan.md`](./plans/Redemption-Risk-Monitoring-Implementation-Plan.md) | redemption risk monitoring実装 |
| [`formal-verification-audit-plan.md`](./plans/formal-verification-audit-plan.md) | 形式検証・監査準備 |
| [`Day-2-Follow-Ups.md`](./plans/Day-2-Follow-Ups.md) | Day 1 launch後に着手する確定済み技術follow-up |

## Guides / Audit Evidence

| 文書 | 対象 |
| --- | --- |
| [`Local-Setup-And-Verification-Guide.md`](./guides/Local-Setup-And-Verification-Guide.md) | local full-stack起動・検証 |
| [`Hosted-Anvil-Frontend-Testing-Guide.md`](./guides/Hosted-Anvil-Frontend-Testing-Guide.md) | hosted Anvil操作・復旧 |
| [`Redemption-Risk-Monitoring-Integration-Guide.md`](./guides/Redemption-Risk-Monitoring-Integration-Guide.md) | monitoringのpublic read仕様 |
| [`Deployment-Configuration-Spec.md`](./guides/Deployment-Configuration-Spec.md) | deploy mode、wiring、生成Manifest schema、`Candidate → Deployed → Verified` lifecycle、env validation |
| [`Contract-Audit-Scope-And-nSLOC.md`](./guides/Contract-Audit-Scope-And-nSLOC.md) | current Solidity audit scope・nSLOC |
| [`Contract-Audit-Usage-Map.md`](./guides/Contract-Audit-Usage-Map.md) | actor・entrypoint・admin経路 |
| [`Contract-Business-Catalog.md`](./guides/Contract-Business-Catalog.md) | contractのbusiness文脈を示す補助資料 |

## Verification Ledgers

| 文書 | 対象 |
| --- | --- |
| [`Requirements-Verification-Ledger.md`](./verification-ledgers/Requirements-Verification-Ledger.md) | 全requirementの検証台帳 |
| [`Core-Requirements-Verification-Ledger.md`](./verification-ledgers/Core-Requirements-Verification-Ledger.md) | `CORE-*`検証台帳 |
| [2026-06-20 Anvil on-chain verification](./historical-reviews/2026-06-20-Anvil-Onchain-Verification/README.md) | 旧5-active構成の履歴検証台帳（現行launch evidenceには使用しない） |
| [`Frontend-Data-Source-Ledger.md`](./verification-ledgers/Frontend-Data-Source-Ledger.md) | frontend data source検証台帳 |
