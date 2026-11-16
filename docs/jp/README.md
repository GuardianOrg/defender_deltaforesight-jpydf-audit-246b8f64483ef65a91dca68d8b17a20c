# JPY DeFi ドキュメント（`documents/jp`）

このディレクトリは、JPY DeFi の Protocol、Protocol Governance、Contributor、Foundation に関する日本語文書の索引です。JPYdf は JPY DeFi が発行する円建てステーブルコイン名です。

## 正本と執筆規約

- 文書の Domain、Lifecycle、Artifact Type、決定権、正本、配置、Status は [`Document-Governance.md`](./Document-Governance.md) に従います。
- 全文書の分類、Normative Source、移動・分割・外部化の判断は [`Document-Inventory.md`](./Document-Inventory.md) を参照します。
- component spec の章立て、要件 ID、記述規律は [`Requirements-Spec-Standard.md`](./Requirements-Spec-Standard.md) に従います。
- JIP / CDR / restricted recordのcross-repository referenceは[`Governance-Record-Reference-Spec.md`](./Governance-Record-Reference-Spec.md)に従います。

## ドキュメント一覧

本ディレクトリは用途別に以下のフォルダで構成します。

```text
documents/jp/
├── README.md                  地図（本ファイル）
├── Document-Governance.md     Domain・Lifecycle・Artifact Type・正本の方針
├── Document-Inventory.md      全文書の分類・正本・移動／分割対象
├── Governance-Record-Reference-Spec.md governance recordの最小参照schema
├── Requirements-Spec-Standard.md component spec の執筆規約
├── Parameters.md              Ethereum mainnet Day1 Parameter Manifest
├── Governance.md              ロール別の特権関数・holder・Timelock 横断索引
├── protocol/
│   ├── product/
│   │   ├── Product-Overview.md 全体像（最初に読む）
│   │   ├── spec/              component要件とStrategy要件
│   │   ├── parameters/        parameter ID・意味・単位・不変条件
│   │   └── policies/          Evergreenな選定基準
│   ├── launch/                Day1 固有のPolicy・Decision Record・Gate
│   ├── operations/            ローンチ後のPolicy・Runbook・template
│   └── roadmap/               Future候補・Policy・Spec・initiative
├── contributors/deltaforesight/
│   ├── commitments/           DeltaForesight固有の資金・流動性commitment
│   ├── policies/              DeltaForesight固有の判断基準
│   ├── manifests/             DeltaForesight固有の環境・holder値
│   ├── delivery-plans/        実装・監査・infraのDay1 delivery
│   └── operations/            監視・keeper・通知などのContributor運用
├── engineering/
│   ├── plans/                 activeな実装計画
│   ├── guides/                技術・検証手順と監査資料
│   ├── verification-ledgers/  要件検証台帳
│   └── historical-reviews/    日付つきreview・過去の検証Evidence（通常参照外）
├── foundation/                Foundation Governanceの文書（Manifestを含む）
└── archive/                   非対象・過去検討（Deprecated）
```

- **製品要件・component spec = [`Product-Overview.md`](./protocol/product/Product-Overview.md)・[`protocol/product/spec/`](./protocol/product/spec/)** — 実装・レビュー・監査が参照する Protocol 要件。Strategy 一族は [`protocol/product/spec/strategies/`](./protocol/product/spec/strategies/) に集約。
- **入口・横断** — 全体像は[`protocol/product/Product-Overview.md`](./protocol/product/Product-Overview.md)、Day1 Parameter Manifestと権限横断リファレンスはルート直下の[`Parameters.md`](./Parameters.md)・[`Governance.md`](./Governance.md)に置く。
- **将来候補 = [`protocol/roadmap/`](./protocol/roadmap/)** — 候補状態・再評価ゲート、Future Policy / Spec、initiative別の検討資料をまとめる。Day1または現行Runtimeの仕様として扱わない。
- **実装・検証・履歴 = [`engineering/`](./engineering/)** — activeな実装plan、技術Guide、監査資料、検証台帳、Historical Evidence。
- **非対象 = [`archive/`](./archive/)** — 現行で使わない過去検討を隔離。

### 製品仕様

| ファイル                                                                                | 内容                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`Product-Overview.md`](./protocol/product/Product-Overview.md)                                          | プロダクト全体像。Ethereum mainnet 単一チェーン前提、独自レイヤー（dToken / Strategy / Oracle / Zapper）・責務分離の原則・レイヤー別の登場人物                                                                                                                                                                                                                                                                                                |
| [`Governance.md`](./Governance.md)                                                      | GOV / Guardian / Allocator / Writeoff / Owner / Upgrader を起点に、holder と対象 Contract・特権関数を横断で引く索引。個別 gate・効果は各 component spec、delay値はDay1 Parameter Manifestを参照                                                                                                                                                                                                                                                             |
| [`Parameter-Catalog.md`](./protocol/product/parameters/Parameter-Catalog.md)             | parameter ID・意味・単位・オンチェーン表現・scope・mutability・decision authority・不変条件の正本 |
| [`Collateral-Parameter-Policy.md`](./protocol/product/policies/Collateral-Parameter-Policy.md) | 担保・dToken Layer parameter の Evergreen な選定基準・変更条件 |
| [`Day1-Parameter-Decision.md`](./protocol/launch/decisions/Day1-Parameter-Decision.md)   | Day1 担保・dToken Layer parameter の採用 model・入力・例外を記録する Decision Record |
| [`Liquity-v2-Core-Spec.md`](./protocol/product/spec/Liquity-v2-Core-Spec.md)                             | Liquity v2 コア継承仕様（`CORE-*`）。**§5.1 カタログのコア全コントラクト**の external/public 関数・状態変数・イベントを ID 付きで規範化（upstream 温存の PriceFeeds/Zappers 等は規範対象外＝同 §5.1）。DF 差分台帳（`CORE-MOD-*`）/ 横断不変条件 / parity（フォーク元同一性）検証計画。JpydfToken の `CORE-BT-*` は [`JpydfToken.md`](./protocol/product/spec/JpydfToken.md) に分離                                                                            |
| [`Permissionless-User-Operations.md`](./protocol/product/spec/Permissionless-User-Operations.md)         | 公開ユーザー向けフロントエンド操作要件。Core / JPYdf / dToken / Vault / Zapper / keeper / optional module の permissionless state-changing surface と、公開アプリの導線・採用 entrypoint・条件付き表示・意図的な非提供範囲を対応づける                                                                                                                                                       |
| [`JpydfToken.md`](./protocol/product/spec/JpydfToken.md)                                                 | JpydfToken 要件定義（`CORE-BT-*`）。債務トークン JPYdf の Core `mint`/`burn` 権限境界・SP 内部移転・受取人制限付き ERC-20/permit・デプロイ配線と owner renounce・🟡 bridge-ready dormant surface（`bridgeAdmin` / minter registry / `bridgeMint` / self-burn `bridgeBurn`）。bridge minter 登録前 gate は [`Bridge-Minter-Activation-Gate.md`](./protocol/operations/runbooks/Bridge-Minter-Activation-Gate.md)。Core Spec から分離（namespace 維持） |
| [`dToken.md`](./protocol/product/spec/dToken.md)                                                         | dToken 要件定義。dToken トークン（decimals / 換算 / 担保 Cap / setTokenInfo / EIP-2612 Permit / mint・burn 権限）                                                                                                                                                                                                                                                                                                                             |
| [`CollateralVault.md`](./protocol/product/spec/CollateralVault.md)                                       | CollateralVault 要件定義。Underlying 保管 / Mint・Redeem / buffer 会計 / allocate・push 受入 / 遅延償還 / Treasury 送付 / 権限・イベント・リスク                                                                                                                                                                                                                                                                                              |
| [`Strategy.md`](./protocol/product/spec/strategies/Strategy.md)                                          | Strategy 共通アーキテクチャ。IStrategy / push モデル / 権限・監視                                                                                                                                                                                                                                                                                                                                                                             |
| [`AaveV3Strategy.md`](./protocol/product/spec/strategies/AaveV3Strategy.md)                              | Aave V3 への個別 Strategy 実装（`Strategy.md` の子ドキュメント）                                                                                                                                                                                                                                                                                                                                                                              |
| [`LidoStrategy.md`](archive/LidoStrategy.md)                                  | **Archived / スコープ外**: 退役した Lido async Strategy の履歴要件。source は `contracts/src/Strategies/archive/` に保存。`0c7766e0` で監査済みだが、現行の実装・監査スコープではない                                                                                                                                                                                                                                                                                              |
| [`ERC4626Strategy.md`](./protocol/product/spec/strategies/ERC4626Strategy.md)                            | ERC-4626 準拠 vault への汎用 Strategy 実装（`Strategy.md` の子ドキュメント）                                                                                                                                                                                                                                                                                                                                                                  |
| [`SkySUsdsStrategy.md`](./protocol/product/spec/strategies/SkySUsdsStrategy.md)                          | dUSDC branch の Sky USDC -> USDS -> sUSDS Strategy（`Strategy.md` の子ドキュメント）                                                                                                                                                                                                                                                                                                                                                          |
| [`EtherfiWeETHStrategy.md`](archive/EtherfiWeETHStrategy.md)                  | **Archived / スコープ外**: 退役した Etherfi eETH / weETH async Strategy と withdraw adapter の履歴要件。source は `contracts/src/Strategies/archive/` に保存。`0c7766e0` で監査済みだが、現行の実装・監査スコープではない                                                                                                                                                                                                                                                                                                                                                          |
| [`Zapper.md`](./protocol/product/spec/Zapper.md)                                                         | Zapper UX Router / EIP-2612 Permit / Sky ingress / Uniswap v4 route gate（Flash Loan close は現行 ABI 外）                                                                                                                                                                                                                                                                                                                                    |
| [`Oracle.md`](./protocol/product/spec/Oracle.md)                                                         | PriceFeedProxy / Chainlink フィード / 担保別オラクル構成 / placeholder ブランチ                                                                                                                                                                                                                                                                                                                                                               |
| [`Treasury.md`](./protocol/roadmap/spec/Treasury.md)                                                     | 担保運用益を用途別固定宛先 / registered backstop Vault へ routing する revenue router の要件定義                                                                                                                                                                                                                                        |
| [`Reward-Distributors.md`](./protocol/roadmap/spec/Reward-Distributors.md) | SP 追加報酬・借入 Referral・SP-deposit Referral の3方式に共通する予算会計、buyback、root、claimと方式別差分 |
| [`InterestRouter.md`](./protocol/product/spec/InterestRouter.md)                                         | InterestRouter（InterestRouterForwarder）要件定義（`IRTR-*`）。借入金利の PIL 分（集計利息残余）を受ける単一 Forwarder。`route()` / `recipient` 差替 / 2-step owner（renounce 無効）・共通 Timelock handover                                                                                                                                                                                                                                  |
| [`PILAllocator.md`](./protocol/product/spec/PILAllocator.md)                                             | PILAllocator / IInitiative / UniV4MerklInitiative 要件定義（`PILA-*`）。InterestRouter から受けた PIL を admin weight で registered initiative に配分し、Uniswap v4 Merkl campaign へ接続する Phase-A liquidity incentive レイヤー                                                                                                                                                                                                            |
| [`Frontend.md`](./protocol/product/spec/Frontend.md)                                                     | フロントエンド要件定義（オフチェーン）。ユーザーアプリ / 管理者コンソール / 運用ダッシュボードの 3 サーフェス、設定・定数同期 / トランザクション UX / データ鮮度 / セキュリティ / 監視                                                                                                                                                                                                                                                        |
| [`Parameters.md`](./Parameters.md)                                                      | Ethereum mainnetのbranch scopeとDay1 parameter値を固定する人間可読Manifest |

### Domain・Lifecycle別の文書

仕様の正本は[`protocol/product/`](./protocol/product/)、実装・検証・Historical Evidenceは[`engineering/`](./engineering/)、DeltaForesight固有のPolicy・Manifest・commitment・delivery・operationsは[`contributors/deltaforesight/`](./contributors/deltaforesight/)に置きます。将来施策は[`protocol/roadmap/`](./protocol/roadmap/)で管理します。

| 区分 | 場所 | 内容 |
| --- | --- | --- |
| Engineering | [`engineering/`](./engineering/) | activeな実装plan、技術Guide、監査資料、検証台帳 |
| Historical Evidence | [`engineering/historical-reviews/`](./engineering/historical-reviews/) | 日付つきreview、過去の検証campaign、再構築の背景 |
| DeltaForesight Contributor | [`contributors/deltaforesight/`](./contributors/deltaforesight/) | DeltaForesight株式会社のPolicy、Manifest、自己資金コミットメント、production delivery・infra・audit準備、監視、export、keeper、user communicationを管理。Protocol仕様・Protocol Governance・Foundation Governanceと分離 |
| Foundation | [`foundation/`](./foundation/) | requirements、spec、policies、manifests、runbooks、templates、evidence、reference sourcesをFoundation GovernanceのDomain境界で管理 |
| Governance GitHub 運用 | [`Governance-Record-Reference-Spec.md`](./Governance-Record-Reference-Spec.md)・[`protocol/operations/`](./protocol/operations/)・[`foundation/runbooks/`](./foundation/runbooks/)・[`foundation/templates/governance/`](./foundation/templates/governance/) | cross-repository referenceの共通schemaと、Protocol Public / Foundation Privateのrunbook・templateを管理 |
| Protocol product | [`protocol/product/`](./protocol/product/) | Product Overview、component Spec、Parameter Catalog、Evergreen Policyを管理 |
| Protocol launch | [`protocol/launch/`](./protocol/launch/) | Protocol Governanceが承認するDay 1 Policy・Decision Record・Gate、configuration freeze、role assignment、handover、market open、participant readiness、fork stressを管理 |
| Protocol operations | [`protocol/operations/`](./protocol/operations/) | 担保・Strategy・清算・流動性・ReferralのPolicyと、JIP GitHub運用、cap ramp、route、incident、activation、sunsetのRunbookを管理 |
| Protocol roadmap | [`protocol/roadmap/`](./protocol/roadmap/) | Day 1に未採用で、将来activation時に再評価するPolicy・initiativeを管理 |
| Contributor delivery plan | [`contributors/deltaforesight/delivery-plans/`](./contributors/deltaforesight/delivery-plans/) | AWS CDK IAM evidence、frontend production・agent・UX、admin console production、SPECA audit pilotなどDeltaForesight担当のDay 1 delivery gate |
| 時点レビュー | [`engineering/historical-reviews/`](./engineering/historical-reviews/) | 日付つきの差分レビュー・検証記録 |

## 読む順序の目安

1. [`Product-Overview.md`](./protocol/product/Product-Overview.md) — 全体像と用語
2. [`Contract-Audit-Usage-Map.md`](./engineering/guides/Contract-Audit-Usage-Map.md) — 監査人向けの actor / entrypoint / keeper・admin 経路 / 無効 route 一覧
3. [`Contract-Audit-Scope-And-nSLOC.md`](./engineering/guides/Contract-Audit-Scope-And-nSLOC.md) — Solidity scope / nSLOC / fork parity 境界
4. [`Permissionless-User-Operations.md`](./protocol/product/spec/Permissionless-User-Operations.md) — permissionless state-changing surface と公開ユーザーアプリの操作カバレッジ・実行経路
5. [`Liquity-v2-Core-Spec.md`](./protocol/product/spec/Liquity-v2-Core-Spec.md) — 無改変で継承するコア ＋ [`JpydfToken.md`](./protocol/product/spec/JpydfToken.md)（債務トークン JPYdf。Core Spec から分離した `CORE-BT-*`）
6. レイヤー別: [`dToken.md`](./protocol/product/spec/dToken.md) → [`CollateralVault.md`](./protocol/product/spec/CollateralVault.md) → [`Strategy.md`](./protocol/product/spec/strategies/Strategy.md) / [`AaveV3Strategy.md`](./protocol/product/spec/strategies/AaveV3Strategy.md) / [`ERC4626Strategy.md`](./protocol/product/spec/strategies/ERC4626Strategy.md) / [`MorphoV2Strategy.md`](./protocol/product/spec/strategies/MorphoV2Strategy.md) / [`SkySUsdsStrategy.md`](./protocol/product/spec/strategies/SkySUsdsStrategy.md) → [`Oracle.md`](./protocol/product/spec/Oracle.md) → [`Zapper.md`](./protocol/product/spec/Zapper.md) → [`InterestRouter.md`](./protocol/product/spec/InterestRouter.md) → [`PILAllocator.md`](./protocol/product/spec/PILAllocator.md)。収益 routing / distribution を確認する場合は [`Treasury.md`](./protocol/roadmap/spec/Treasury.md) → [`Reward-Distributors.md`](./protocol/roadmap/spec/Reward-Distributors.md) を読む。
7. parameter を確認する場合は [`Parameter-Catalog.md`](./protocol/product/parameters/Parameter-Catalog.md)（意味・制約）→ [`Parameters.md`](./Parameters.md)（Ethereum mainnet Day1 Manifest）。Day1の入力・例外・採用理由は[`Day1-Parameter-Decision.md`](./protocol/launch/decisions/Day1-Parameter-Decision.md)、将来の担保追加またはlaunch後の変更基準は[`Collateral-Parameter-Policy.md`](./protocol/product/policies/Collateral-Parameter-Policy.md)を読む
8. [`Governance.md`](./Governance.md) — ロール別の holder・対象 Contract・特権関数・Timelock 境界の横断索引。外部JIP / CDR参照は[`Governance-Record-Reference-Spec.md`](./Governance-Record-Reference-Spec.md)を使う
9. [`Frontend.md`](./protocol/product/spec/Frontend.md) — オフチェーン（ユーザーアプリ / 管理者コンソール / 運用ダッシュボード）の要件
10. frontend / AWS 横断 refactor の順序を決める場合は [`Frontend-AWS-Refactor-Plan.md`](./engineering/plans/Frontend-AWS-Refactor-Plan.md) → [`AWS-CDK-Hosting-Plan.md`](./engineering/plans/AWS-CDK-Hosting-Plan.md) → [`Frontend-Development-Plan.md`](./engineering/plans/Frontend-Development-Plan.md)
11. 任意: [`Contract-Business-Catalog.md`](./engineering/guides/Contract-Business-Catalog.md) — product / business 文脈の補助資料。監査 scope や entrypoint 判断の正本ではない

> 実装・進捗を追う場合は[`engineering/`](./engineering/)、再構築の背景や過去時点の証跡を追う場合は[`engineering/historical-reviews/`](./engineering/historical-reviews/)を参照してください。
