# 要件検証台帳（Requirements Verification Ledger）— ローカルテスト実施記録

## 0. 目的と位置づけ

本書は、[`documents/jp`](../../README.md) の要件定義（正本）に付与された**すべての要件 ID** が、ローカル環境の実装とテストで検証されていることを記録する台帳である。

- **対象**: 機能要件（FR）/ 不変条件（INV）/ セキュリティ要件（SEC）/ ガバナンス・運用・アップグレード要件（GOV）/ イベント・監視要件（EVT）/ 失敗時・異常系挙動（ERR）/ 受け入れ基準（各 doc §13）/ 未決事項（TBD）。ID を振られているものは**例外なく**本書に 1 行を持つ（検証対象外とする場合も、その旨と理由を行として残す）。
- **根拠**: [要件定義ドキュメント標準](../../Requirements-Spec-Standard.md)は「テスト名・実行結果は仕様本文に書かない。ID 連携は一方向（テスト・台帳が doc の ID を参照する）」と定める。その一方向参照の受け側＝「ID × 実テスト × 実行結果」の正本が本書である。
- **各 doc §13（受け入れ基準・検証計画）との関係**: §13 の合格条件は「ID × 検証手段」で規定される。本書は各 ID 行の「規定検証手段」列に §13 ／各要件の `Verification` 指定を転記しており、**行の正常系・異常系が規定検証手段で実証されたとき、当該 ID の受け入れ基準を満たす**。
- **監査人向け**: 本書から (1) 全 ID の網羅、(2) ID ごとの正常系・異常系の実証、(3) 証跡（コミット SHA・実行コマンド・テスト名・結果）に遡れる。

> 検証対象の実装: `deltaforesight/jpydf-v2`（`develop`。検証時点の head SHA を §2 に記録する）。仕様と実装が食い違う場合は要件定義（jp/*.md）を正とし、FAIL として記録のうえ実装側の修正 issue を起票する。

> **ベースライン注記（2026-06-13・develop 基準化、2026-06-22 更新）**: 本台帳は **develop を基準**とし、`develop` 先行分の develop 固有 7 ID — STGY-INV-010 / STGY-SEC-008 / STGY-GOV-005 / STGY-EVT-009（Strategy upgrader 分離）・ZAP-FR-014 / ZAP-INV-009 / ZAP-TBD-009（Sky USDC ルート）— を反映済み。過去の governance docs 待ち参照は現行 `develop` では解決済みであり、**VAULT-FR-019**（emergencyDisableStrategy）、**Parameters**（ガバナンス遅延統制）、および共通 TimelockController 確定（2026-06-12）を織り込んだ governance 行（VAULT-GOV-004 / DTKN-GOV-004 / STGY-GOV-003 等）は現行 spec / design doc に到達済みとして扱う。現行の総 ID は §3 の集計を正とする。

---

## 1. 運用ルール（記入・判定）

### 1.1 行の構成（共通スキーマ）

| 列 | 内容 |
| --- | --- |
| ID | 要件 ID（正本 doc の ID をそのまま使う。台帳側で新 ID を発番しない） |
| 要件（要約） | 正本 doc の見出し・表記の短縮転記。**期待挙動の正本は doc の当該 ID 本文**（要約が doc と食い違う場合は doc を正とする） |
| 規定検証手段 | 正本 doc §13 ／各要件 `Verification` 指定の転記（unit / fuzz / invariant=INV-ID / fork / integration / e2e-local / build / ci-guard / manual 等）。doc に指定が無い行は `（台帳定義）` を付す。転記の正＝ID 個別の `Verification` 指定（INV は §8 表の検証列）。個別指定と §13 の per-ID 行が併存する場合は和集合を載せる。§13 の**範囲行**（「§N 記載どおり」等のサマリー）は per-ID 指定で読み替える。個別指定の無いカテゴリ（Frontend の SEC / ERR / INV）は §13 の領域主検証を適用する |
| 正常系 | `☐` → 実証済みなら `✅`、適用不能なら `N/A`（理由を備考へ） |
| 異常系 | 同上 |
| テスト実体 | `テストコントラクト::テスト関数`（複数可）または manual 検証記録への参照。**forge 等の実行ログから転記する（実在しないテスト名を書かない）** |
| 結果 | `未実施` / `PASS` / `FAIL`（issue 参照必須） / `BLOCKED(理由)`（未実装・未決ゲート等） / `N/A(理由)` |
| 備考 | キャンペーン ID（§2）・skip の正体・N/A 理由・欠番等 |

### 1.2 正常系・異常系のカテゴリ別定義

| カテゴリ | 正常系で実証すること | 異常系で実証すること |
| --- | --- | --- |
| FR | 事前条件成立時に doc 記載の動作（Effects・戻り値・発火イベント）が成立する | doc 記載の**各 revert / 早期 return / 境界条件**が 1 つ以上のテストで実際に発火する |
| INV | 正常運用の操作列の下で不変条件が維持される（invariant / fuzz） | 違反を試みる操作が失敗する、または違反状態が定義上到達不能であることの根拠を示す |
| SEC | 正規の権限・経路での操作が成立する | 攻撃経路（非権限呼出・再入・偽装・donation・操作系）が遮断される |
| GOV | 権限者が正しい手順（timelock 経過・2-step 等）で操作に成功する | 非権限者・手順違反（遅延未経過・1-step 放棄等）が revert する。manual 項目は構成レビュー記録で代替 |
| EVT | 規定のパラメータでイベントが発火する | 非発生条件で発火しない／操作失敗時に発火が巻き戻る |
| ERR | （主検証は異常系）誤発動しないこと（正常時に縮退しない） | 異常契機で doc 記載の縮退・revert・フェイルセーフが実際に起こる |
| TBD | — 検証対象外（未決ゲート）。Resolved 済みは反映先 ID の行で検証する | — |

- view のみ・オフチェーン運用のみ等で片系が存在しない場合は `N/A(理由)` とする（空欄のまま完了扱いにしない）。

### 1.3 判定原則（ガードレール）

1. **実走のみが証跡**: 構造チェック（コード・テストファイルの存在確認）は検証ではない。`forge test` 等の実行結果のみを PASS の根拠にできる。
2. **skip は PASS でない**: 実行時 skip（fork RPC 未設定・`vm.skip` 等）されたテストは PASS に数えず、skip の正体を備考に記録する。
3. **flaky の扱い**: retry で通ったテストは初回失敗の入力（fuzz seed / counterexample）を記録し、本物の反例でないことを確認してから PASS とする。fuzz cache（`cache/fuzz`）を削除して再実行した場合はその旨を記録する（失敗入力の隠蔽防止）。
4. **完了主張は検証範囲に限定**: FAIL・未実施・BLOCKED が 1 行でも残る間、集計を「完了」と書かない。「一致 / 問題なし」は全行 PASS/N/A の場合のみ。
5. **fork テスト**: 公開 archive RPC または社内 RPC を使う。**RPC URL・API キーは本書・ログ・エラー出力に書かない**（環境変数で渡す）。
6. **実装が存在しない要件**: `BLOCKED(未実装)` と記録する（テスト不能の隠蔽防止。Treasury 等、設計確定済み・実装未着手のモジュールで発生しうる）。
7. **検証は head 固定**: キャンペーン開始時に commit SHA を固定し、全行を同一 SHA 上で検証する。SHA が進んだら新キャンペーンとする。

### 1.4 標準実行手順（ローカル）

```bash
# 1) Google Drive 上では実行しない。使い捨てクローンに隔離する
git clone https://github.com/deltaforesight/jpydf-v2 /tmp/jpydf-v2-verify && cd /tmp/jpydf-v2-verify
git rev-parse HEAD   # → §2 に記録

# 2) ツールチェーン記録
~/.foundry/bin/forge --version   # → §2 に記録

# 3) クリーンビルド（out/ 残骸の誤検出防止）
cd contracts && ~/.foundry/bin/forge clean && ~/.foundry/bin/forge build

# 4) テスト実行（ログを保存して台帳へ転記。set -o pipefail を忘れない）
set -o pipefail
~/.foundry/bin/forge test -vv 2>&1 | tee /tmp/forge-test-$(date +%Y%m%d).log

# 5) fork 系（RPC は環境変数で。URL を出力・台帳に残さない）
source ~/.config/deltaforesight/rpc.env
~/.foundry/bin/forge test --match-path 'test/*fork*' -vv 2>&1 | tee -a /tmp/forge-test-fork.log
```

- フロントエンド（FRNT-*）の e2e-local は anvil → deploy → subgraph → frontend の一気通貫レシピ（社内手順）に従い、実施記録を §2 と該当行へ残す。
- manual（構成レビュー・runbook・storage layout review 等）は実施者・日付・確認内容を `engineering/historical-reviews/` 配下に記録し、行から参照する。

---

## 2. 検証環境の記録（キャンペーン台帳）

検証キャンペーン（同一 commit SHA 上の一連の実行）ごとに 1 行追加し、各 ID 行の備考からキャンペーン ID で参照する。

| キャンペーン | 実施日 | repo / branch | commit SHA | forge / 環境 | fork RPC（種別のみ） | 実行コマンド・ログ | 実施者 | 結果サマリ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| VAULT-RECERT-20260812 | 2026-08-12 | jpydf-v2 / `agent/recertify-vault-audit-invariants` | develop `8c8b4e31` + invariant / ledger overlay | forge 1.7.1 local | なし | focused 6 suites; `FOUNDRY_PROFILE=ci forge test -vv --no-match-contract 'Mainnet\|Invariant\|Anchored\|Initiative\|LocalParityDrill'`; `forge fmt --check`; `git diff --check` | Codex | PASS: focused 263、fast 1,572、全て 0 failed / 0 skipped。push-model invariant 7 本は各 500 runs / 25,000 calls / 0 reverts。Strategy update / emergency disable を操作列に加え、VAULT-INV-009/012/014 を再認証。MAINNET_RPC は未使用のため VAULT-FR-016 の fork 指定は未実施 |
| V1 | 2026-06-20 | jpydf-v2 / develop | 28808fd + working tree | forge 0.8.24 local | なし | `forge test --match-contract 'SkyUsdcSUsdsStrategyTest\|EtherfiWeETHStrategyTest\|DeployLiquity2StrategySelectorTest\|DFGovernanceHandoverXAUTGateTest'`; `forge build`; `git diff --check` | Codex | PASS: focused 44 tests、build、diff check |
| V1-MAP | 2026-06-20 | deltaforesight/jpydf-v2 / develop | `30d078b`（origin/develop HEAD・clean） | forge 1.7.1 / macOS | archive（`DFPriceFeed` 42 PASS・`OracleMainnet` は `rpc_endpoints` alias 未解決で skip） | 意味マッピング（全21 component・**per-row PASS 確認**）= [`reviews/2026-06-20-V1-mapping/`](../historical-reviews/2026-06-20-V1-mapping/) ／ baseline = [`_baseline-summary.md`](../historical-reviews/2026-06-20-V1-mapping/_baseline-summary.md) ／ 集約 = [`campaign-V1`](../historical-reviews/2026-06-20-requirements-verification-campaign-V1.md) ／ メタ監査 = [`completeness-audit`](../historical-reviews/2026-06-20-ledger-completeness-audit.md) | Claude（21エージェント並列） | **1170 passed / 0 failed / 2 skipped**。要件→テストを per-row で **`PASS`（ログの [PASS] 実在）まで確認**（約 592 ID）。**SKY は Day-1 に Sky 連携が確定した場合に採用する条件付き Strategy で、本キャンペーン対象外（別途検証）・TRSY は Day-2 未実装**、異常系/expectEmit/fork(mainnet) に系統的 GAP。Tier C（anvil 実デプロイ）で SYS 4/5 PASS。（Codex focused 検証 V1〜V3 とは別系統＝要件網羅マッピング。本表の `PASS(V1/V2)` 等は Codex 系を指す） |
| V2 | 2026-06-21 | jpydf-v2 / develop | b7280145 + working tree | forge 0.8.24 local | なし | `forge test --match-contract 'LidoStrategyTest\|EtherfiWeETHStrategyTest\|SkyUsdcSUsdsStrategyTest\|AaveV3StrategyTest\|ERC4626StrategyTest\|DeployLiquity2StrategySelectorTest'`; `git diff --check` | Codex | PASS: focused 115 tests、diff check |
| V3 | 2026-06-21 | jpydf-v2 / develop | 923b39d + working tree | node / pnpm local | なし | `pnpm --filter @jpydf/console build`; static `writeoffStrategyPrincipal` calldata-shape check; `git diff --check` | Codex | PASS: console build、calldata shape、diff check |
| V4 | 2026-06-21 | jpydf-v2 / develop | 9d395a7 + working tree | forge 0.8.24 local | なし | `forge test --match-path test/DeployLiquity2StrategySelector.t.sol --match-test 'test_DeployYieldLayer*'`; `forge test --match-path test/DeployLiquity2StrategySelector.t.sol --match-test test_UUPSImplementationsRejectDirectInitialization`; `forge test --match-path test/DeployLiquity2StrategySelector.t.sol`; `forge build --contracts script/DeployLiquity2.s.sol`; review = [`2026-06-21-Deploy-Proxy-Initialization-Differential-Review.md`](../historical-reviews/2026-06-21-Deploy-Proxy-Initialization-Differential-Review.md) | Codex | PASS: deploy helper focused 2 tests、implementation lock 1 test、DeployLiquity2 strategy/deploy selector 29 tests、deploy script build。dToken/Vault helper 初期化境界、inert branch cap 0 / fail-closed、Strategy proxy initializer calldata 化、implementation direct initialize 拒否を確認 |
| V5 | 2026-06-21 | jpydf-v2 / codex/handover-pending-owner-verification | b16485d + working tree | forge 0.8.24 local | なし | `pnpm -C contracts exec forge test --match-path test/DFGovernanceHandoverXAUTGate.t.sol -vvv`; `pnpm -C contracts exec forge build --contracts script/VerifyDFGovernanceHandover.s.sol`; review = [`2026-06-21-Handover-Final-Pending-Owner-Verification-Review.md`](../historical-reviews/2026-06-21-Handover-Final-Pending-Owner-Verification-Review.md) | Codex | PASS: 15 tests、verify script build。final handover verify で dToken / Strategy / generic 2-step owner の stale `pendingOwner` を拒否し、`DF_VERIFY_PENDING_OWNERSHIP=true` の中間状態でも current owner が currentAdmin であることを確認 |
| V6 | 2026-06-21 | jpydf-v2 / codex/vault-permit-evidence | de6884d + working tree | forge 1.2.3-nightly local | なし | `forge test --match-path test/CollateralVault.t.sol`; `git diff --check` | Codex | PASS: CollateralVault focused 55 tests、diff check。`redeemWithPermit` の permit success / front-run 済み nonce + allowance success / invalid permit + allowance 不足 `PermitFailed` / pre-permit revert を確認 |
| V7 | 2026-06-21 | jpydf-v2 / codex/sky-conversion-loss-floor | 83517a9 + working tree | forge 1.2.3-nightly local | なし | `forge test --match-path test/SkyUsdcSUsdsStrategy.t.sol`; `forge fmt --check src/Strategies/SkyUsdcSUsdsStrategy.sol test/SkyUsdcSUsdsStrategy.t.sol`; `git diff --check` | Codex | PASS: SkyUsdcSUsdsStrategy focused 9 tests、fmt check、diff check。通常 withdraw と 2-step / one-tx emergency 回収で `maxConversionLossBps` 下限が `minUsdcOut=0` でも緩和されないことを確認 |
| V8 | 2026-06-24 | jpydf-v2 / codex/security-dos-review-20260624 | a4dcf68 + working tree | forge 1.2.3-nightly local | なし | `forge fmt --check`; `git diff --check`; `forge test --match-path test/EtherfiWeETHStrategy.t.sol -vv`; `forge test --match-path 'test/*Strategy*.t.sol' -vv` | Codex | PASS: Etherfi focused 20 tests、Strategy suite 262 tests、fmt check、diff check。Etherfi raw ETH donation が claim delta / idle WETH / yield / valuation に混入しないこと、および EFWEETH-SEC-008..011 の既存テスト実体を確認 |
| V9 | 2026-06-24 | jpydf-v2 / codex/vault-buffer-shortfall-prep-20260624 | bfd5a4e + working tree | forge 1.2.3-nightly local | なし | `forge test --match-path test/AaveV3Strategy.t.sol`; `forge test --match-path test/ERC4626Strategy.t.sol`; `forge test --match-path test/SkyUsdcSUsdsStrategy.t.sol`; `forge test --match-path test/EtherfiWeETHStrategy.t.sol`; `forge test --match-path test/InvariantPushModel.t.sol`; `forge fmt --check src/Strategies/AaveV3Strategy.sol src/Strategies/ERC4626Strategy.sol src/Strategies/SkyUsdcSUsdsStrategy.sol test/AaveV3Strategy.t.sol test/ERC4626Strategy.t.sol test/SkyUsdcSUsdsStrategy.t.sol test/EtherfiWeETHStrategy.t.sol`; `git diff --check` | Codex | PASS: Aave focused 23 tests、ERC4626 focused 22 tests、Sky focused 12 tests、Etherfi focused 21 tests、push model invariant 4 tests、fmt check、diff check。zero-scaled / zero-share / zero-USDC dust / tiny weETH rounding の accounting guard を確認 |
| V10 | 2026-07-07 | jpydf-v2 / codex/etherfi-withdraw-adapter | 75021f57 + working tree | forge 1.2.3-nightly local | なし | `forge test --match-path test/EtherfiWeETHStrategy.t.sol -vv`; `forge test --match-path test/DeployLiquity2StrategySelector.t.sol -vv`; `forge build --skip test`; `forge fmt --check src/Strategies/EtherfiWeETHStrategy.sol src/Strategies/WeETHWithdrawAdapter.sol test/EtherfiWeETHStrategy.t.sol test/DeployLiquity2StrategySelector.t.sol script/DeployLiquity2.s.sol`; `git diff --check` | Codex | PASS: Etherfi focused 33 tests、DeployLiquity2StrategySelector 32 tests、build、fmt check、diff check。DeltaForesight first-party `WeETHWithdrawAdapter` が weETH を eETH に unwrap して Ether.fi native withdrawal request を作ること、venue graph / LiquidityPool reverse-binding mismatch、zero request、residual weETH / eETH 拒否、Strategy が approve 前に adapter binding を検証し request owner 検証を維持することを確認 |
| V11 | 2026-07-07 | jpydf-v2 / codex/etherfi-adapter-identity-marker | working tree | forge 1.2.3-nightly local | なし | `forge test --match-path test/EtherfiWeETHStrategy.t.sol -vv`; `forge test --match-path test/DeployLiquity2StrategySelector.t.sol -vv`; `forge build --skip test`; `forge fmt --check src/Strategies/EtherfiWeETHStrategy.sol src/Strategies/WeETHWithdrawAdapter.sol test/EtherfiWeETHStrategy.t.sol test/DeployLiquity2StrategySelector.t.sol script/DeployLiquity2.s.sol`; `git diff --check` | Codex | PASS: Etherfi focused 34 tests、DeployLiquity2StrategySelector 32 tests、build、fmt check、diff check。Strategy が approve 前に DF 固有 `dfWeETHWithdrawAdapterId()` marker を要求し、同名または ABI 互換でも marker を公開しない adapter を拒否することを確認 |
| V12 | 2026-07-14 | jpydf-v2 / codex/sky-usdc-usds-converter | `eed3edfa`（実装）/ `b789c6bd`（台帳訂正） | forge 1.2.3-nightly local + GitHub Actions | Ethereum mainnet RPC（URL 非記録） | focused commands; Actions `29349413077`（full local / mainnet / deploy / parity / handover）; Slither 0.10.2 audit config | Codex | PASS: converter 11 tests（unit 9 + mainnet fork 2）、Strategy 13、Zapper 31、deploy selector 32。Actions の full local・mainnet fork・deploy wiring・parity drill・handover が成功。公式 LitePSMWrapper token identity、USDC→USDS→USDC round-trip、fee/halt・6/18 decimals・reverse budget/refund・残高/allowance residue、Strategy actual-spend accounting、deploy concrete-adapter binding を確認。Slither は converter に実質的な指摘なし。coverage instrumentation は継承 test tree の stack/Yul depth 制約で失敗するため、required Foundry test から非 blocking 計測へ分離 |
| FE-STG-1 | 2026-06-23 | CloudFront staging frontend / AWS Staging Anvil | app `86bd169` / contracts `e81331c`（bundle metadata） | headless Chrome + injected EIP-1193 provider / chainId 31338 | staging Anvil RPC | frontend tx ledger = [`2026-06-23-frontend-contract-requirements-tx-verification.md`](../historical-reviews/2026-06-23-frontend-contract-requirements-tx-verification.md) | Codex | PASS/PARTIAL(frontend-tx): borrow open via CYZ, SP deposit/withdraw, redemption via RedemptionHelper, Vault dToken redeem, Ops read-only event rendering。FAIL/RISK: loan update button sends no tx, wrong-chain wallet is not blocked, Admin console has no auth wall, `/vault/:coll` route/mint UI gap |
| V13 | 2026-08-05 | jpydf-v2 / develop（origin/develop の docs worktree） | `629e1c05` | forge 1.7.1 local | なし | `forge test --match-path 'test/MorphoV2*.t.sol'`（30 passed）; `forge test --match-path test/DeployLiquity2StrategySelector.t.sol`（34 passed） | Claude | PASS: MorphoV2Strategy 29 tests、MorphoV2BackingRatio 1 test、deploy selector 34 tests。hard-zero max\* 下の動作、deposit 拒否 recovery（cap / receive gate / zero-share / 嘘の返り値）、fail-soft withdraw（liquidity short / send gate / 不一致 / zero burn）、donation 排除、損失の即時反映、`maxShares` 段階緊急回収と donated share 回収、上限付き `forceDeallocate` penalty と `_ownShares` resync、self-only isolated frame、reentrancy 遮断、`morpho-v2` deploy binding と Day-1 branch policy を確認 |

| V14 | 2026-08-06 | jpydf-v2 / develop | `90a784f2` | forge 1.7.1 local | なし | `forge test --match-path test/DFWstETHPriceFeed.t.sol`（36 passed）; `forge test --match-path test/DFWstETHPriceFeedProxyIntegration.t.sol`（10 passed）; `forge test --match-path test/CollateralYieldZapper.t.sol`（47 passed） | Claude | PASS: spec に存在するが台帳に行が無かった `ORCL-FR-015`（dwstETH composite feed）と、requirement ID 自体が無かった Zapper の native ETH on-ramp（新規 `ZAP-FR-015`）を追加。実装・テストは merge 済みで、欠けていたのは要件行と spec 記述のみ |
| V21 | 2026-08-08 | jpydf-v2 / `fix/preaudit-morpho-pricing-rails` | `825e9674` | forge 1.7.1 local | なし | affected 5 suites; fast PR gate; full local gate; `forge build --sizes`; `cloc 2.06`; `git diff --check` | Codex | PASS: affected 253、fast 1,536、full local 1,589、全て 0 failed / 0 skipped。fee-on-transfer receiver delta、Strategy receipt/cache ambiguity、Sky quote unavailable/recovery を確認。Vault runtime 23,047 bytes（margin 1,529）、full body 5,219 nSLOC |
| PRELIM-M02 | 2026-08-12 | jpydf-audit / `audit/preliminary-m02-remediation` | source `fe3d3d0` + M-01/M-02 overlays | forge 1.7.1 local | なし | Sky converter/strategy focused; compatibility mocks; fast PR gate; production size gate; pre-fix mutation; `forge fmt --check`; `git diff --check` | Codex | PASS: focused/compat 35、fast 1,547、全て 0 failed / 0 skipped。pre-fix では価格 feed 統合回帰が失敗し、remediation 後に成功。Sky Strategy runtime 20,173 bytes（margin 4,403）、converter runtime 5,596 bytes（margin 18,980） |
| PRELIM-L01 | 2026-08-12 | jpydf-audit / `audit/preliminary-l01-remediation` | source `fe3d3d0` + M-01/M-02/L-01 overlays | forge 1.7.1 local | なし | CollateralVault focused; push-model invariant; fast PR gate; production size gate; pre-fix mutation; production-source `forge fmt --check`; `git diff --check` | Codex | PASS: Vault focused 197、invariant 4、fast 1,547、全て 0 failed / 0 skipped。pre-fix では owner retry の idempotence 回帰が `RequestNotFound` で失敗し、remediation 後に成功。Vault runtime 23,032 bytes（margin 1,544）。既存 test file には本変更外の fmt drift があるため全ファイル fmt gate は適用せず、本変更ブロックと production source を個別確認 |
| PRELIM-L02 | 2026-08-12 | jpydf-audit / `audit/preliminary-l02-remediation` | source `fe3d3d0` + M-01/M-02/L-01/L-02 overlays | forge 1.7.1 local | なし | active feed constructor focused; deploy selector; fast PR gate; production size gate; pre-fix mutation; `forge fmt --check`; `git diff --check` | Codex | PASS: focused 129、fast 1,549、全て 0 failed / 0 skipped。pre-fix では expired shared provider に対する Standard feed deploy が成功して回帰テストが失敗し、remediation 後は Standard / dwstETH とも `InvalidInitialPrice`、fresh JPY recovery 後は deploy 成功。DFUSDC runtime 3,095 bytes（margin 21,481）、DFWstETH runtime 3,492 bytes（margin 21,084） |
| PRELIM-L03 | 2026-08-12 | jpydf-audit / `audit/preliminary-l03-disposition` | source `fe3d3d0` + M-01/M-02/L-01/L-02 overlays + L-03 resolution tests/docs | forge 1.7.1 local | なし | CollateralVaultStrategy focused; fast PR gate; report-recommendation mutation; `forge fmt --check`; `git diff --check` | Codex | PASS: focused 125、fast 1,550、全て 0 failed / 0 skipped。報告推奨の `updatedAt = block.timestamp` mutation は cache timestamp を `1 → 86400` へ進め、partial recovery 非更新回帰を意図どおり失敗させた。production source は変更せず、両 live read の復旧で pricing availability が直ちに回復し、permissionless refresh が cache を再格納することを確認 |
| PRELIM-L03-FU | 2026-08-12 | jpydf-audit / `agent/correct-l03-writeoff-recovery-evidence` | source `fe3d3d0` + M-01/M-02/L-01/L-02 + corrected L-03 overlay | forge 1.7.1 local | なし | stale-cache full-writeoff regression; CollateralVaultStrategy focused; fast PR gate; 5-overlay reconstruction; `forge fmt --check`; `git diff --check` | Codex | PASS: focused 126、fast 1,551、全て 0 failed / 0 skipped。全額 writeoff は確定損失を会計反映する一方、live valuation が読取不能なら pricing availability を回復しないことを確認。production source は変更なし、5 overlays は drift / missing / undecided 全て 0 |

---

## 3. 集計（カバレッジ・ダッシュボード）

**スコープ**: 正規要件 source 20 ファイル（18 Spec＋1 Launch Gate＋1 Decision Record、下表）。`CORE-*` は専用の [Core-Requirements-Verification-Ledger.md](./Core-Requirements-Verification-Ledger.md) を正本とし、本書では参照のみ（重複記録しない）。[Multichain.md](../../archive/Multichain.md)（MCHN-* 41 件）は ADR-004 / README により**履歴資料・現行スコープ外**＝検証対象から除外（§15 で明示宣言。省略ではなく除外）。[LidoStrategy.md](../../archive/LidoStrategy.md)（LIDO-* 47 件）と [EtherfiWeETHStrategy.md](../../archive/EtherfiWeETHStrategy.md)（EFWEETH-* 13 件）は Solidity source とともに **archived** となり、同様に active 合計から除外して合計行の下に記録する（§9B / §9D）。Day-1 の bridge-ready dormant extension は `CORE-BT-*` と SYS-FR-006 / SYS-CON-004 / SYS-INV-003 で扱い、MCHN-* を復活させない。

| 文書 | FR | INV | SEC | GOV | EVT | ERR(ID) | その他 ID | TBD | ID 計 | 非 ID チェック行 | 検証済 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| §4 System sources（Product Overview / Launch Risk Gate / ADR） | 8 | 5 | — | — | — | — | CON 5・NFR 6・RISK 9・ARCH 6・ADR 7 | 0 | 46 | 0 | 0 |
| §5 Liquity-v2-Core-Spec（🔵 CORE） | — | — | — | — | — | — | `CORE-*` は Core 専用台帳を正本 | 0 | 0 | 13 | 0 |
| §6 dToken（DTKN） | 10 | 10 | 7 | 5 | 5 | 0 | — | 3 | 40 | 13 | 0 |
| §7 CollateralVault（VAULT） | 19 | 14 | 9 | 4 | 15 | 0 | — | 3 | 64 | 40 | 8 |
| §8 Strategy（STGY） | 12 | 11 | 8 | 5 | 12 | 2 | — | 2 | 52 | 0 | 0 |
| §9 AaveV3Strategy（AAVE） | 7 | 5 | 5 | 3 | 4 | 5 | — | 8 | 37 | 0 | 0 |
| §9A ERC4626Strategy（E4626） | — | — | 8 | — | — | — | — | — | 8 | 0 | 0 |
| §9C SkyUsdcSUsdsStrategy（SKY） | — | — | 11 | — | — | — | — | 0 | 11 | 0 | 11 |
| §9E MorphoV2Strategy（MV2） | 5 | 3 | 7 | — | — | — | — | 0 | 15 | 0 | 15 |
| §10 Oracle（ORCL） | 15 | 12 | 7 | 5 | 9 | 0 | — | 6 | 54 | 15 | 6 |
| §11 Zapper（ZAP） | 15 | 9 | 7 | 3 | 1 | 0 | — | 10 | 45 | 11 | 33 |
| §12 Parameters（PRM） | — | 7 | — | — | — | — | パラメータ ID 15 | 0 | 22 | 15 | 5 |
| §13 Treasury（TRSY） | 9 | 6 | — | — | 8 | 0 | — | 3 | 26 | 6 | 0 |
| §13A Reward-Distributors（SPARD） | 9 | 8 | — | — | 7 | 0 | — | 4 | 28 | 0 | 0 |
| §13B Reward-Distributors（BRRD） | 9 | 9 | — | — | 7 | 0 | — | 5 | 30 | 0 | 0 |
| §13C Reward-Distributors（SPDRD） | 10 | 10 | — | — | 8 | 0 | — | 5 | 33 | 0 | 0 |
| §13D InterestRouter（IRTR） | 5 | 6 | 5 | 5 | 3 | 0 | — | 6 | 30 | 1 | 0 |
| §13E PILAllocator / UniV4MerklInitiative（PILA） | 16 | 8 | 6 | 6 | 7 | 0 | — | 8 | 51 | 0 | 38 |
| §14 Frontend（FRNT） | 36 | 4 | 8 | 5 | 3 | 6 | — | 9 | 71 | 3 | 1 |
| **合計（active）** | **185** | **127** | **88** | **41** | **89** | **13** | **48** | **72** | **663** | **117** | **117** |
| §9B LidoStrategy（LIDO・archived） | 9 | 10 | 8 | 3 | 5 | 5 | — | 7 | 47 | 0 | 39 |
| §9D EtherfiWeETHStrategy（EFWEETH・archived） | — | — | 13 | — | — | — | — | 0 | 13 | 0 | 13 |
| §15 Multichain（MCHN・対象外） | 13 | 8 | 6 | 5 | 6 | — | — | 3 | 41 | 1 | — |

- **検証対象 ID** = 663 −（未決 TBD）。active な TBD 72 件（archived の §9B が別途 7 件を持つが除外）の Resolved / 未決 / 条件付き / 延期の内訳は各文書の TBD レジスタを正本とし、未決ゲートは対象外として扱う。`CORE-*` の ID 総数・検証状況は [Core-Requirements-Verification-Ledger.md](./Core-Requirements-Verification-Ledger.md) を正本とし、本表の active 合計には含めない。
- 「検証済」列は全行 PASS または N/A となった ID 数。キャンペーンごとに更新する。
- **V19 更新（2026-08-06）**: §9B `LidoStrategy`（`LIDO-*` 47 件）と §9D `EtherfiWeETHStrategy`（`EFWEETH-*` 13 件）を archived とし、active ID 計を **718 → 658**、active 検証済を **158 → 106** に更新。これは**削除ではなくアーカイブ**である。Solidity source は `contracts/src/Strategies/archive/`、test は `contracts/test/archive/` へ移動し、いずれも compile / test（84 tests）は継続して通る。両 Strategy の underlying は構造的に WETH であり、それを束ねていた deploy selector は PR #1424 で削除済み。branch 0 の underlying も WETH → wstETH へ移行したため、WETH underlying を供給できる branch は存在しない。両 surface は 2026-08-05 完了の外部監査（監査対象 identity `0c7766e0`）の対象に含まれていたため、要件が監査トレーサビリティから消えないよう行と ID を active 合計の下に残す。`LIDO-*` / `EFWEETH-*` は履歴 ID として凍結し、再利用も active scope としての参照も禁止する。再有効化には新規 activation package と audit-scope 変更が必要。
- **V20 更新（2026-08-08）**: 外部監査開始前の是正として、MV2-FR-003 を bounded partial retry、MV2-FR-005 を Vault incident rails / donation-first penalty 会計へ更新し、focused 74 tests と fast Foundry gate で再確認した。pricing は valuation unavailable と measured zero を分離し、VAULT-FR-016 / ORCL-FR-014 に unit evidence を追加したが、fork / invariant / full integration 未実施のため両行は PARTIAL のままとした。既に PASS だった MV2 / ORCL-FR-015 の再実証であり、active ID 数・検証済集計は変更しない。
- **V21 更新（2026-08-08）**: security-skill 横断 review の追加 variant を是正した。VAULT-FR-002 は receiver 実着額、VAULT-FR-005 は declared/received 不一致時 cache 無効化、ZAP-FR-006 / ZAP-SEC-005 は fee-on-transfer 下限、SKY-SEC-011 は quote 不能と測定済み0の分離を追跡する。§9C 集計が既存 SKY-SEC-008..010 を未計上だったため、新規011と併せて 7→11へ訂正し、active SEC / ID / 検証済をそれぞれ +4 とした。
- **PRELIM-M02 更新（2026-08-12）**: SKY-SEC-011 を予備監査 M-02 に合わせて精緻化した。明示的な Sky 逆変換 route halt は principal-capped 1:1 valuation を継続し、停止中の未実現 yield を認識しない。invalid fee、status read failure、その他の quote failure は halt と推測せず従来どおり fail-closed とする。要件 ID 数・検証済集計は不変。
- **PRELIM-L01 更新（2026-08-12）**: VAULT-FR-006 を予備監査 L-01 に合わせて精緻化した。実在する settlement 済み request の再 claim は二重送金・二重減算・追加 event を行わず `0` を返し、未発行 ID は従来どおり `RequestNotFound` とする。permissionless trigger と owner 固定送金は維持する。VAULT-FR-006 の再認定により §7 / active 検証済を **2 → 3 / 110 → 111** に更新し、要件 ID 数は不変。
- **PRELIM-L02 更新（2026-08-12）**: active DF feed の初期 fetch が `primary` かつ nonzero `lastGoodPrice` を seed する constructor invariant を ORCL-INV-012 として追加した。shared JPY provider の unhealthy expiry 中は未登録 feed の shutdown call が catch されても deployment を拒否し、fresh recovery 後は再開する。§10 INV / ID / 非 ID check / 検証済を **11→12 / 53→54 / 14→15 / 5→6**、active 合計を **126→127 / 662→663 / 116→117 / 111→112** に更新し、stale だった検証対象 ID 式の基数も dashboard と同じ **663** に同期した。
- **PRELIM-L03 更新（2026-08-12）**: 予備監査 L-03 の timestamp refresh 提案は不採用。partial receipt は残存 Strategy position の full valuation ではなく、これで `updatedAt` を進めると未観測損失を含み得る古い高値 cache を少額回収で反復延命できる。VAULT-FR-005 / VAULT-INV-005 を精緻化し、TTL は最後の full valuation を基準に維持、期限後は fail-closed、両 live valuation read の復旧で availability が直ちに回復し、permissionless full refresh が cache を再格納する方針を回帰テストで固定した。incident writeoff は確定損失を会計へ反映するが、valuation が読取不能な間は availability を回復しない境界も follow-up unit test で固定した。要件 ID・dashboard 検証済集計は不変。
- **VAULT-RECERT-20260812 更新**: VAULT-FR-009 / FR-019 / INV-009 / INV-012 / INV-014 の 5 ID を unit + invariant で再認証し、VAULT 検証済を 3 → 8、active 合計を 112 → 117 に更新。VAULT-FR-016 は unit / invariant 完了、pinned mainnet fork のみ未実施の PARTIAL。
- **V1-MAP（2026-06-20）件数訂正**: メタ監査（[ledger-completeness-audit](../historical-reviews/2026-06-20-ledger-completeness-audit.md)）により Product-Overview（ARCH/ADR）・LIDO（INV/EVT）・Parameters（bridge-minter-timelock）の欠落 **5 行**を反映。develop の §3 集計（566）に +5 し ID 計 **571**。追加行 = **ARCH-006 / ADR-006 / LIDO-INV-010 / LIDO-EVT-005 / PRM-BRIDGE-MINTER-TIMELOCK**（うち bridge-minter は commit `756a736` 由来）。**合計行はセル和と一致するよう全面再計算済**。
- **台帳同期（2026-06-24）**: Strategy / Etherfi の追補 ID **6 行**（STGY-INV-011 / STGY-EVT-012 / EFWEETH-SEC-008..011）を反映し、active ID 計を **571 → 577** に更新。追加時点では検証実体未確認のため PASS にせず、未実施として扱った。
- **V8 更新（2026-06-24）**: EFWEETH-SEC-012 を追加し、active ID 計を **577 → 578** に更新。`test/*Strategy*.t.sol` の実走で EFWEETH-SEC-008..012 を PASS に更新した。
- **台帳同期（Protocol revenue allocation split）**: Treasury を purpose routing 専用に縮小し、SPAdditionalRewardDistributor / BorrowReferralRewardDistributor / SPDepositReferralRewardDistributor を独立 module として追加。Referral distributors は on-chain root / claim 型として集計し、さらに Treasury `BACKSTOP_DEPOSIT` / `emergencyBackstopDeposit` 拡張を反映して active ID 計を **578 → 615** に更新。
- **V10 更新（2026-07-07）**: EFWEETH-SEC-014 を追加し、active ID 計を **615 → 616** に更新。`WeETHWithdrawAdapter` を first-party adapter として production source / audit scope に追加し、Etherfi focused / deploy selector / build / diff check で PASS とした。
- **V11 更新（2026-07-07）**: active ID 計は **616 のまま**。`WeETHWithdrawAdapter` に DF 固有 identity marker を追加し、`EtherfiWeETHStrategy.initialize` が marker-less ABI-compatible adapter を approve 前に拒否することを focused tests / deploy selector / build / fmt / diff check で PASS とした。
- **台帳同期（2026-07-20）**: Product-Overview の既存欠落 `SYS-RISK-008` と、新規 `SYS-RISK-009` / `ADR-007` を追加し、active ID 計を **616 → 619** に更新した。追加時点では実運用 evidence 未確認のため PASS にせず、未実施として扱う。
- **台帳同期（2026-07-26）**: 統合後の Reward-Distributors 正本に存在する SPARD / BRRD / SPDRD の INV **6 行**と EVT **22 行**を追加し、active ID 計を **619 → 647** に更新した。3 module は未実装のため全追加行を `BLOCKED(未実装)` とする。
- **V13 更新（2026-08-05）**: §9E `MorphoV2Strategy`（MV2-FR 5 / MV2-SEC 7 / MV2-INV 3）を追加し、active ID 計を **647 → 662** に更新。merge 済みの `MorphoV2Strategy.t.sol` / `MorphoV2BackingRatio.t.sol` / `DeployLiquity2StrategySelector.t.sol` の実走に基づき全 15 行を PASS(V13) とする。
- **台帳同期（2026-08-05・LIDO 退役）**: WETH → wstETH branch swap に伴う `LidoStrategy` の Day-1 deploy surface 退役を反映し、§9B の `LIDO-GOV-001`（退役 gate・未実施のまま）と TBD レジスタを除く **39 行**を `N/A(退役)` とした。ID 計は不変（662）。検証済は 71 → **110**（§9B 0 → 39）。source / spec は削除せず archive へ退避する（監査済み成果物として保存）。
- **V14 更新（2026-08-06）**: auditor 向けスコープ delta 送付前の実装漏れ点検で、**spec にあるが台帳に行が無い / requirement ID 自体が無い** 2 件を補った。`ORCL-FR-015`（dwstETH composite feed。Oracle spec §ORCL-FR-015 は存在するが台帳は ORCL-FR-014 で止まっていた）と `ZAP-FR-015`（Zapper の native ETH on-ramp。実装・テストは merge 済みだが requirement ID が未採番で、Zapper spec は逆に「native ETH collateral flow は持たない」と記載したままだった）。あわせて JPY freeze 系の `ORCL-EVT-007` / `ORCL-EVT-008` / `ORCL-EVT-009`（`JpyUsdRateProvider` 発火、共有 `JpyFreezeLib` 抽出後も topic 不変）も spec にのみ存在していたため補った。active ID 計を **662 → 667**、検証済を **110 → 115** に更新。実装・テストの追加はなく、追加したのは要件行と spec 記述のみ。
- **V15 更新（2026-08-06）**: `PILAllocator.sol`（235 nSLOC）と `Initiatives/UniV4MerklInitiative.sol`（174 nSLOC）は [Contract-Audit-Scope-And-nSLOC](../guides/Contract-Audit-Scope-And-nSLOC.md) の「Audited but gated production code」として A full-review body に含まれるにもかかわらず、本台帳に 1 行も存在しなかった。§13E として `PILA-*` **51 ID**（FR 16 / INV 8 / SEC 6 / GOV 6 / EVT 7 / TBD 8）を追加し、active ID 計を **667 → 718**、検証済を **115 → 142** に更新。merge 済みの `PILAllocator.t.sol`（16 passed）/ `UniV4MerklInitiative.t.sol`（11 passed）/ `DeployPILAllocatorPhaseA.t.sol`（9 passed）の実走に基づき **27 行を PASS(V14)**、**直接の test を持たない 16 行は 未実施 のまま**とし、残る 8 行は TBD レジスタ（検証対象外）。未実施の内訳は EVT の `expectEmit` 欠落 6（EVT-001/002/003/005/006/007。状態遷移自体は他 test で確認済みだが event topic の実証が無い）、GOV の activation / 上流接続 5（GOV-002..006）、静的差分・manual レビュー証跡の欠落 2（INV-005 / INV-007）、Merkl mainnet 依存と被害境界レビュー 2（SEC-001 / SEC-002）、本家互換 epoch interface 1（FR-002）。実装・テストの追加は無い。
- **V16 更新（2026-08-06）**: §13E の 未実施 16 行のうち、テストで閉じられる **8 行**を PASS(V16) にした。新規 `test/PILAInitiativeParity.t.sol`（4 tests）が vendored upstream `lib/V2-gov` の `IInitiative` / `IGovernance` を直接 import して 4 hook の selector と tuple 展開後の canonical signature（PILA-INV-007）、および epoch surface の upstream selector と 1-indexed 起点・境界挙動（PILA-FR-002）を照合する。既存テストに `expectEmit` を追加して PILA-EVT-001 / 002 / 003 / 005 / 006 / 007 を実証。検証済を **142 → 150** に更新（ID 計 718 は不変）。変異確認: `IInitiative.UserState.unallocatedOffset` を `uint128` にすると parity test が FAIL、`GuardianUpdated` の引数順を入れ替えると EVT test が FAIL。残る 未実施 8 行はすべて activation / 上流接続 / 静的レビュー証跡（GOV-002..006・INV-005・SEC-001・SEC-002）であり、Day-1 のコードでは閉じられない。
- **V17 更新（2026-08-06）**: §13E の残り 8 行のうち、静的レビューで閉じられる **3 行**（PILA-INV-005 / SEC-002 / GOV-006）を PASS(V17) にした。いずれも規定検証手段が `manual / static` であり、実装は既に要件どおりだったがレビュー証跡が未記録だった項目。develop `a09d1620` に対して 外部呼び出しの全列挙（INV-005: 相互作用は safeTransfer / initiative への hook call / view の `requireValidRecipient` の 3 つのみ、forwarder・Core への参照 0 件）、認可マップの全列挙（SEC-002）、継承と upgrade surface の全列挙（GOV-006: proxy / UUPS / `delegatecall` いずれも 0）を実施し、結果を各行の備考へ転記した。検証済を **150 → 153** に更新（ID 計 718 は不変）。副産物として、spec §9 の SEC-002 statement が owner の実行可能操作から `setGuardian` / 2-step ownership を落としていたことが判明したため、EN/JP 両方を実装に合わせて訂正した（どちらも資金経路を持たないため主張自体は成立）。残る 未実施 5 行（GOV-002..005 / SEC-001）は activation package 側の作業であり、Day-1 のコードでは閉じられない。
- **V18 更新（2026-08-06）**: #1205 が #859 から引き継いでいた `PRM-INV-006` の deploy guard 不整合を修正し、§12 の PRM-INV 5 行を PASS(V18) にした。`DeployLiquity2.s.sol` の guard は `1 + URGENT_REDEMPTION_BONUS <= p.MCR` を検査していたが、Parameter-Catalog の正本は **SCR** に対する下限であり、`SCR < MCR`（PRM-INV-001）が別途強制されるぶん公開済み不変条件より弱い検査になっていた。`AddressesRegistry` も `SCR > 100%` しか見ないため 102% 下限は on-chain のどこにも強制されていなかった。guard を `p.SCR` へ修正し、invariant loop を `_requireBranchRiskInvariants` として抽出、新規 `test/DeployBranchRiskInvariants.t.sol`（8 tests）で境界ちょうどの受理・境界未満の拒否・各不変条件の拒否・後続 branch まで走査することを固定した。変異確認: guard を MCR 比較へ戻すと SCR 不足のケースが 2 件とも通過する。検証済を **153 → 158** に更新（ID 計 718 は不変）。
- **V1 マッピング状況（per-row 実 PASS 確認）**: 全 21 component を **develop 30d078b** で検証し、各要件の覆うテストを **baseline ログで `[PASS]` 実在確認**（`PASS` 約 592 ID）。ID 単位の結果は各 component の埋めた節（[reviews/2026-06-20-V1-mapping/](../historical-reviews/2026-06-20-V1-mapping/)）に記録。**SKY は Day-1 に Sky 連携が確定した場合に採用する条件付き Strategy で、本キャンペーン対象外（別途検証）・TRSY は Day-2 未実装**、異常系/EVT(expectEmit)/fork/governance-ceremony（skip → Tier C で 4/5 PASS）に系統的 GAP（[集約レポート](../historical-reviews/2026-06-20-requirements-verification-campaign-V1.md)）。

> **上表の合計の由来（最終 rebase 2026-08-06、`2e57cf76`）。** 本ブランチは当初、archive 前の
> baseline が 634 / 検証済 71 であった `develop` から派生した。その後 2 度 rebase しており、
> 現在の baseline は `develop`（`2e57cf76`）の **718 / 検証済 158**（§9B 検証済 39、§9D 検証済 13）である。
> 直前の rebase 時点（`f41f2db9`）は 662 / 検証済 110 で、その差は auditor 送付前の実装漏れ点検で
> 追加した §13E `PILA-*` 51 件と `ORCL-FR-015` / `ZAP-FR-015` / `ORCL-EVT-007..009` 5 件による。
>
> archived 行は次の不変条件で active 合計から除外した。**この 2 行は develop 側の合計が動くたびに
> 再計算が必要であり、git は dashboard を綺麗にマージするため衝突マーカーが出ない。**
>
> - `active ID 計 = 718 − 60 = 658`（§9B 47 + §9D 13）
> - `active 検証済 = 158 − 39 − 13 = 106`
>
> §9B と §9D は両方とも active 合計から外れるため、その検証済も一緒に外れる。§9D だけを引くと、
> 合計が「もはや含まない ID の検証済」を数えることになる。両行は検証済の値を保ったまま合計行の
> 直下に残してあり、カバレッジが黙って消えることはない。
>
> `LIDO-EVT-005` は両言語とも §9B 内の行として `N/A(retired)` で扱い、§15.1 には**重複させない**。
> 当該 delta-trace 行は upstream で削除済みであり、復活させると ID の二重計上になる。

---

## 4. システム要件・Launch Risk Gate・Architecture Decision

正本: `SYS-FR-*` / `SYS-CON-*` / `SYS-NFR-*` / `SYS-INV-*` / `ARCH-*` は [Product-Overview.md](../../protocol/product/Product-Overview.md)、`SYS-RISK-*` は [Mainnet-Launch-Risk-Gate.md](../../protocol/launch/gates/Mainnet-Launch-Risk-Gate.md)、`ADR-*` は [Architecture-Decision-Records.md](../../protocol/product/architecture/Architecture-Decision-Records.md)。システムレベル要件は component 要件へ分解される（Product Overview §13 トレーサビリティ）。本セクションの多くは「分解先 component 行の完了＋システム横断の integration / 検査」で検証する。

### 4.1 システム機能要件（SYS-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SYS-FR-001 | 過剰担保で JPYdf 発行（1 Tx 完結含む） | 分解先（DTKN-FR-004 / VAULT-FR-001,010,011 / ZAP-FR-001..004 / 🔵Core）＋ integration（台帳定義） | ☐ | ☐ | | 未実施 | |
| SYS-FR-002 | dToken の Underlying 現物償還（不足時は遅延償還＋claim） | 分解先（DTKN-FR-005 / VAULT-FR-002,003,006 / ZAP-FR-006,010）＋ integration（台帳定義） | ☐ | ☐ | | 未実施 | |
| SYS-FR-003 | 担保の外部運用と収益のプロトコル収益化（push モデル） | 分解先（VAULT-FR-004,005,007,008,009 / STGY-FR-001..005,010 / AAVE-FR-*）＋ integration（台帳定義） | ☐ | ☐ | | 未実施 | |
| SYS-FR-004 | JPYdf ペグの自律是正（Redemption / 3 層清算 / SP） | 🔵 Core 継承（§5 Core 行＋ upstream suite）（台帳定義） | ☐ | ☐ | | 未実施 | |
| SYS-FR-005 | JPY 建て価格取得・backing 比反映・failsafe 縮退 | 分解先（ORCL-FR-* / VAULT-FR-016..018 / 🔵 lastGoodPrice・shutdown）＋ integration（台帳定義） | ☐ | ☐ | | 未実施 | |
| SYS-FR-006 | JPYdf token はbridge-ready dormant extensionと、Coreから分離したminter lifecycleを持つ | Core 台帳 CORE-BT-FR-013..016 / CORE-BT-INV-003＋activation gate inspection | ☐ | ☐ | `JpydfTokenTest::test_BridgeReadinessIsDormantAfterCoreSetup`; `JpydfTokenTest::test_BridgeRolesMustBeContractsAndSeparated`; `JpydfTokenTest::test_BridgeMintRejectsProtocolRecipients`; `DeployLiquity2StrategySelectorTest::test_ResolveBridgeAdminValidatesConfiguredContract` | PASS | Day1のminter / pending / adapter状態はLaunch Manifest / Evidenceで別途検証。final deploy manifest evidenceは未実施 |
| SYS-FR-007 | GOV によるパラメータ・whitelist・upgrade・oracle source 制御 | 分解先（VAULT-FR-008,009,012,014,015 / DTKN-FR-006,008,009 / STGY-FR-011 / ORCL-FR-*）（台帳定義） | ☐ | ☐ | | 未実施 | |
| SYS-FR-008 | UX の 1 Tx 集約（補助・無くても中核稼働） | 分解先（ZAP-FR-001..010,013,014）＋ ARCH-005 行 | ☐ | ☐ | | 未実施 | |

### 4.2 制約（SYS-CON）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SYS-CON-001 | コア会計 parity と JPYdf canonical surface（旧 BOLD public/API 名の再混入禁止。base 差分は Core spec §2.2 / §5.1 で管理） | Core JPYDF surface guard ＋ Core 専用台帳の diff/parity 行（台帳定義） | ☐ | ☐ | | 未実施 | 異常系=旧 BOLD surface 再混入で guard FAIL |
| SYS-CON-002 | コアの外部 IF は担保 ERC-20（dToken）と PriceFeedProxy の 2 つのみ | inspection（コア参照アドレスの deploy 配線検査）（台帳定義） | ☐ | N/A | | 未実施 | N/A: 構成検査項目（依存先列挙の確認のみ・反例試行を定義しない） |
| SYS-CON-003 | 担保は 18dec ERC-20（非 18dec は dToken でラップ） | DTKN-INV-001 / DTKN-FR-003 行＋ deploy 検査 | ☐ | ☐ | | 未実施 | |
| SYS-CON-004 | JPYdf token は non-upgradeable。Core `mint` / `burn` は Core 専用、bridge supply は別名 `bridgeMint` / self-burn `bridgeBurn` と minter registry に限定 | inspection ＋ Core 台帳 CORE-BT-* | ☐ | ☐ | `JpydfTokenTest::test_BridgeMinterLifecycleUsesTimelockAndSelfBurn` | PASS | releaseごとの登録状態はManifest / Evidenceで別途検証 |
| SYS-CON-005 | productionのchain / branch / bridge routeは承認済みrelease scopeに固定し、未承認scopeを公開しない | Launch Decision / Parameters / deploy Manifest / frontend bindingの突合 | ☐ | N/A | | 未実施 | Day1のexpected scopeはLaunch artifact側で検証 |

### 4.3 品質特性・非機能要件（SYS-NFR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SYS-NFR-001 | セキュリティ（コア会計 parity・台帳化された JPYdf 差分・🟢 は §9 INV / §10 脅威モデル充足） | Core JPYDF surface guard ＋ Core 専用台帳 ＋ 本台帳の INV/SEC 行全体（台帳定義） | ☐ | ☐ | | 未実施 | |
| SYS-NFR-002 | 分散性（中核操作 permissionless・例外は dToken 層入口/出口の GUARDIAN pause のみ） | integration（permissionless 操作の無権限実行）＋ VAULT-FR-014 行 | ☐ | ☐ | | 未実施 | 異常系=GOV が中核操作を停止「できない」ことの確認 |
| SYS-NFR-003 | アップグレード性（dToken/Vault/Strategy=UUPS＋共通 Timelock 24h・PriceFeedProxy=非 upgrade・Core/JpydfToken=non-upgradeable） | DTKN-FR-008 / VAULT-FR-015 / STGY-FR-009 / ORCL 行＋ deploy 構成検査 | ☐ | ☐ | | 未実施 | |
| SYS-NFR-004 | 可用性（oracle 障害→lastGoodPrice→shutdown / Strategy 障害→writeoff・emergencyWithdraw / buffer 不足→遅延償還） | ORCL-FR-004 / VAULT-FR-002,006,009 / STGY-FR-004,005 行＋ integration | ☐ | ☐ | | 未実施 | |
| SYS-NFR-005 | 可観測性（*-EVT-* で off-chain 会計・監視・アラート構成可能） | 各 EVT 行の総合（台帳定義） | ☐ | N/A | | 未実施 | N/A: 各 EVT 行の総合（個別の異常系は各 EVT 行が持つ） |
| SYS-NFR-006 | コスト効率（1 Tx 集約・push モデル・固定宛先/固定比率） | ZAP 行・STGY 行＋ gas snapshot（任意）（台帳定義） | ☐ | N/A | | 未実施 | N/A: 性能特性（合否境界の異常系なし） |

### 4.4 システム不変条件（SYS-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SYS-INV-001 | 過剰担保（各 Trove は MCR 以上を維持。割れは清算） | 🔵 Core invariants（§13 トレース） | ☐ | ☐ | | 未実施 | |
| SYS-INV-002 | dToken 請求権整合（総供給の Underlying 換算 floor ≤ Vault＋Strategy 総 Underlying。毀損時は backingRatio<1e18 が価格へ伝播） | DTKN-INV-002,005,006 / VAULT-INV-*（§13 トレース） | ☐ | ☐ | | 未実施 | |
| SYS-INV-003 | JPYdf 供給経路の閉性（Core supply path と bridge supply path の分離。Day-1 は bridge minter 0 件） | 🔵 Core mint/burn 経路＋ bridge dormant unit＋ deployment review | ☐ | ☐ | `JpydfTokenTest::test_BridgeReadinessIsDormantAfterCoreSetup`; `JpydfTokenTest::test_BridgeMinterLifecycleUsesTimelockAndSelfBurn` | PASS | deployment review は未実施 |
| SYS-INV-004 | ブランチ隔離（限界付き。共通 JPYdf 債務トークン経由の相関は対象外と明示） | 🔵 Core ＋ §10 脅威モデル（隔離部分の integration） | ☐ | ☐ | | 未実施 | |
| SYS-INV-005 | コア差分境界（旧 BOLD surface は禁止、許容差分は Core spec `CORE-MOD-*` / §5.1 カタログに限定） | Core JPYDF surface guard ＋ manual diff review | ☐ | ☐ | | 未実施 | |

### 4.5 Launch Risk Register（SYS-RISK・Day-1 gate）

各行の「正常系」= gate 条件を満たす検査・テスト・runbook が存在し実走済み、「異常系」= リスク発火シナリオで規定の防御が働くこと。

| ID | リスクと gate（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SYS-RISK-001 | JPY/USD 全 branch 共通依存。gate: `PRM-ORACLE-001`、`ORCL-SEC-005`、source 差替 runbook、renounce 無効化 | ORCL-SEC-005 / ORCL-FR-007 行＋ manual（runbook） | ☐ | ☐ | | 未実施 | ORCL-TBD-001 は非 JPY のみ残 |
| SYS-RISK-002 | dToken backing 崩れをコアは直接知らない。gate: 全 active feed の正 Vault 参照・loss/writeoff/backstop deposit/release の価格下方・回復・reserve 先着不消費を integration＋監視で必須化 | VAULT-FR-016,017 / ORCL-FR-014 行＋ integration | ☐ | ☐ | | 未実施 | |
| SYS-RISK-003 | Treasury / SP 報酬経路。gate: 並行 Distributor 方式の設計確定（確定まで SP 追加報酬は非プロダクション扱い） | TRSY 行（§13）＋ manual | ☐ | ☐ | | 未実施 | TRSY 実装未着手なら BLOCKED(未実装) |
| SYS-RISK-004 | async Strategy 元本回収。active な Strategy に非同期のものは存在しない: `AsyncRequestStrategy` とその唯一の subclass 2 件（Lido / Etherfi）は archived であり、active な Strategy はすべて `BaseStrategy` を直接継承する。gate: 将来の async Strategy は新規 proposal として回収トリガ/pending principal/収益・元本分離/claimable/loss・writeoff、keeper / incident runbook、venue evidence、activation package、audit-scope 変更を満たす | Day-1: inert branch は cap / allocation / Strategy 0、`DeployLiquity2.s.sol` に `lido` / `etherfi` strategy kind 不在、承認済み Strategy set / Manifest の汎用照合、archive inventory、既存 instance がある場合の inventory / recovery evidence | ☐ | ☐ | | 未実施 | archived source の存在は再開承認ではない。source は `contracts/src/Strategies/archive/` に保存され `0c7766e0` で監査済み。将来 stETH 系 Strategy は新規提案・承認・監査が必要 |
| SYS-RISK-005 | branch risk param は immutable・余裕僅少。gate: PRM-INV-* の機械検証（SCR<MCR<CCR・1+penalty≤MCR・urgent redemption bonus・Constants エンコード一致）＋最終値 freeze review | §12 PRM-INV 行（forge / deploy script） | ☐ | ☐ | | 未実施 | |
| SYS-RISK-006 | Redemption 全 branch 走査・1 feed revert で全停止。gate: 全 active/inert source の no-revert / ABI 正常 / nonzero-nonmax / failure=false 構成検査（deploy 末尾＋integration） | ORCL-FR-002,008 行＋ integration（構成検査） | ☐ | ☐ | | 未実施 | |
| SYS-RISK-007 | XAUT candidateはDay-1不採用。再採用にはdownside depegをon-chain反映するOracleが必須 | ORCL-FR-013 / ORCL-SEC-006＋manual | ☑ | ☐ | candidate sourceはarchiveへ隔離 | PASS(scope) | off-chain監視やcapだけではactivation不可 |
| SYS-RISK-008 | dToken `mintCap` は branch debt ceiling ではない。gate: docs / UI / ops が cap を JPYdf 発行上限と表示せず、既存 dToken collateral の debt increase が cap reduction 後も残ることを test / inspection で確認し、露出を Core 制約・SP coverage・borrowable branch gate・監視で管理する | DTKN-FR-006 / CORE-BO-FR-001..003,006＋ manual（copy / ops gate inspection） | ☐ | ☐ | | 未実施 | `plannedDebtJpydf` もオンチェーン cap ではない |
| SYS-RISK-009 | JPYdf上方乖離に対称な自動供給機構がない。gate: live stateから既存担保のdebt room・dToken cap headroom・fee込み新規debt capacityを分離算出し、cap rampと短期premiumのresidual riskを確認する | Active-Branch-Cap-Ramp-Runbook＋Core supply-path inspection。特定Contributorの対応を前提にする場合は当該Policy / Commitment / Evidenceを追加 | ☐ | ☐ | | 未実施 | ProtocolはborrowerまたはContributorの追加借入・市場供給を保証しない。APR変更だけでは供給actionにならない |

### 4.6 アーキテクチャ原則（ARCH）・主要決定（ADR）

検査（inspection）中心。正常系 = 原則・決定が実装に反映されていることの確認、異常系 = 違反の検出機構（CI 等）が機能すること。

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ARCH-001 | コア会計 parity 原則（差替は担保 ERC-20 と価格フィード中心、JPYdf canonical surface と台帳化差分のみ許容） | Core JPYDF surface guard ＋ diff review（台帳定義） | ☐ | ☐ | | 未実施 | SYS-CON-001 と同根 |
| ARCH-002 | 責務分離（各レイヤーが他レイヤー内部実装を知らない） | inspection（依存方向のコードレビュー）（台帳定義） | ☐ | N/A | | 未実施 | N/A: 設計原則の検査（違反検出は ARCH-001 の CI が担う） |
| ARCH-003 | 一方向依存（コアの外部依存は 2 つの汎用 IF のみ） | inspection ＋ deploy 配線検査（台帳定義） | ☐ | N/A | | 未実施 | SYS-CON-002 と同根 |
| ARCH-004 | 変更は外側に閉じる（Core mint/burn 不変。bridge supply は別 surface に隔離し Day-1 休眠） | inspection ＋ ORCL-FR-001..003 / VAULT-FR-008 / CORE-BT-FR-013..016 行 | ☐ | ☐ | | 未実施 | |
| ARCH-005 | Zapper は補助（無くても Core / dToken 単独稼働・直接操作で同一結果） | integration（Zapper 非経由の直接操作で同等結果）（台帳定義） | ☐ | ☐ | | 未実施 | |
| ARCH-006 | 拡張境界の明示（将来拡張を UUPS upgrade／setter・whitelist 追加／参照先切替／再デプロイ に分類。変更可能性は外側レイヤーに閉じ、Core / JpydfToken / CollateralRegistry の immutable 前提を破らない） | inspection（拡張分類のコード/構成レビュー）（台帳定義） | ☐ | N/A | | 未実施 | **V1 追加（メタ監査・Product-Overview §6 L187）**。N/A: 設計境界の検査項目（違反検出は ARCH-001/004 と SYS-NFR-003 §6.1 拡張境界表が担う） |
| ADR-001 | Liquity v2 base-parity fork（拡張は外側。JPYdf canonical surface と台帳化差分は Core spec で管理） | ARCH-001 行と同一証跡 | ☐ | ☐ | | 未実施 | |
| ADR-002 | 担保外部運用は dToken＋Strategy 層で実現（コアの担保=dToken） | integration（dToken を担保に openTrove）＋ DTKN/VAULT 行 | ☐ | ☐ | | 未実施 | |
| ADR-003 | Strategy は push モデル（sendToVault / sendProfitToVault・Vault は pull しない） | STGY-FR-002,003 / VAULT-FR-005 行＋ inspection（pull 経路不在） | ☐ | ☐ | | 未実施 | |
| ADR-004 | bridge供給経路をCoreから分離し、tokenをbridge-readyにする（bridgeAdmin / minter registry / bridgeMint / self-burn bridgeBurn） | CORE-BT-FR-013..016 ＋ SYS-FR-006 / SYS-CON-004 行 | ☐ | ☐ | | 未実施 | releaseごとのdormant / active状態はLaunch artifactで検証 |
| ADR-005 | オラクルは PriceFeedProxy で差替可能化（コア固定参照・source 24h timelock） | ORCL-FR-001..004 / ORCL-INV-001,002 行 | ☐ | ☐ | | 未実施 | |
| ADR-006 | backing 毀損（dToken 裏付け<1）時の挙動（①確定損失を即時に担保価値へ反映 ②backing<1 でも 1:1 償還維持・実損時は償還一時停止→backstop 回復→再開 ③償還停止の自動発火は Day-1 なし＝手動運用＋strategy 別保守ガード。新規コード不要） | ORCL-FR-014 / VAULT-FR-014,017 / writeoffStrategyPrincipal 行＋ integration（台帳定義） | ☐ | ☐ | | 未実施 | **V1 追加（当時のメタ監査・Product-Overview §11 L317）**。現行正本は [ADR-006](../../protocol/product/architecture/Architecture-Decision-Records.md#adr-006)。[SYS-RISK-002](../../protocol/launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-002) が参照する確定方針。異常系=Strategy 毀損→backingRatio<1e18→価格下方→清算/償還停止 |
| ADR-007 | 上方ペグ乖離をPSM等の新規mint経路で防がず、既存Core借入経路と必要時のdToken cap rampに限定し、短期premiumをresidual riskとして受容する。APRは借入コスト / Redemption順位の別判断であり供給actionではない | SYS-RISK-008/009 行＋ inspection（PSM / reserve-backed mint path不在、cap ramp gate） | ☐ | ☐ | | 未実施 | Protocolは特定borrower / Contributorの市場供給を保証しない。#1101のJPYdf/JPYC routeは新しい供給能力を作らない |

---

## 5. Liquity-v2-Core-Spec.md（🔵 コア継承）

正本: [Liquity-v2-Core-Spec.md](../../protocol/product/spec/Liquity-v2-Core-Spec.md)。`CORE-*` の詳細検証は専用の [Core-Requirements-Verification-Ledger.md](./Core-Requirements-Verification-Ledger.md) を正本とする。本節は横断台帳からの参照用チェック行であり、検証は「**旧 BOLD surface 再混入がないこと**」＋「**DF パラメータ下で upstream / parity 検証資産が成立すること**」＋「**`CORE-MOD-*` 差分の個別検証**」で行う。

| # | チェック項目 | 規定検証手段（台帳定義） | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Core JPYDF surface guard が green（旧 BOLD public/API 名の再混入ゼロ）かつ base 差分が Core spec §2.2 / §5.1 と整合 | ci-guard ＋ Core 専用台帳の diff/parity 行 | ☐ | ☐ | | 未実施 | 異常系=旧 BOLD surface 再混入で guard FAIL |
| 2 | upstream テストスイート（unit / invariant / fuzz）が DF パラメータ下で全緑 | forge test（全量・ローカル実走） | ☐ | N/A | | 未実施 | 実行時 skipped はゼロ件か正体を記録 |
| 3 | 🟡 MIN_DEBT = 300,000 JPYdf（§1-3） | unit（Constants 値）＋ openTrove 境界 | ☐ | ☐ | | 未実施 | 異常系=MIN_DEBT 未満 open の revert |
| 4 | 🟡 清算実行者補償 上限：dwstETH 2 / dUSDC 1,000単位、予約枠は有効化前に一度確定（料率 0.5% は Core 標準・Gas Deposit 0.0375 WETH 標準のまま）（§0-1 / §5-6） | unit（Constants 値・補償計算） | ☐ | ☐ | | 未実施 | |
| 5 | 🟡 Denomination = JPYdf（JpydfToken name/symbol・JPY 建て価格）（§0-1） | unit（name/symbol）＋ ORCL-INV-007 行 | ☐ | N/A | | 未実施 | N/A: 命名・建値の一致確認のみ（異常系なし） |
| 6 | 🟢 Collateral = dToken wrapper（コアが dToken を通常 ERC-20 担保として扱う） | integration（deposit→openTrove→清算/償還の通し） | ☐ | ☐ | | 未実施 | ADR-002 と同根 |
| 7 | 🟢 Oracle = PriceFeedProxy 経由（フィード障害は lastGoodPrice＋shutdown へ縮退） | ORCL-FR-004 行＋ integration | ☐ | ☐ | | 未実施 | |
| 8 | §10-1 総債務恒等式（aggRecordedDebt＋pendingAggInterest＋aggBatchManagementFees＋DefaultPool.getJpydfDebt() == Σ entireTroveDebt） | invariant（upstream suite） | ☐ | ☐ | | 未実施 | |
| 9 | §10-2 CR 制約（ICR≥MCR 清算・TCR≥CCR 借入制限・TCR<SCR shutdown） | unit / invariant（upstream suite・DF 値） | ☐ | ☐ | | 未実施 | |
| 10 | §10-3 清算ペナルティ順序（SP ≤ Redistribution ≤ 10% ≤ MCR） | PRM-INV-003/004 行（§12） | ☐ | ☐ | | 未実施 | |
| 11 | §10-4 Batch invariant（debt:shares ≤ 1e9・違反時 kickFromBatch） | invariant（upstream suite） | ☐ | ☐ | | 未実施 | |
| 12 | §10-5 SP invariant（SP_JPYDF_balance ≥ MIN_JPYDF_IN_SP） | invariant（upstream suite） | ☐ | ☐ | | 未実施 | |
| 13 | §10-6 Trove 状態 invariant（debt≥MIN_DEBT=Active / 0<debt<MIN_DEBT=Zombie / 0=Closed・Liquidated） | unit / invariant（upstream suite・MIN_DEBT=300k 下） | ☐ | ☐ | | 未実施 | |

---

## 6. dToken.md（DTKN）

正本: [dToken.md](../../protocol/product/spec/dToken.md)。対象: `contracts/src/DToken.sol` / `IDToken.sol`。

### 6.1 機能要件（DTKN-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DTKN-FR-001 | initialize（placeholder 立ち上げ・vault/owner 固定・cap=max・再初期化不可） | unit | ☐ | ☐ | | 未実施 | |
| DTKN-FR-002 | setTokenInfo（一度きり・倍率確定・allowlist/decimals≤18/EOA 拒否 等各 revert） | unit, invariant=DTKN-INV-003/004 | ☐ | ☐ | | 未実施 | |
| DTKN-FR-003 | Underlying ↔ dToken 換算（乗算厳密・floor 安全側・境界） | unit, fuzz=DTKN-INV-006 | ☐ | ☐ | | 未実施 | |
| DTKN-FR-004 | mint（vault 限定・cap / 未確定ガード） | unit, invariant=DTKN-INV-002/005 | ☐ | ☐ | | 未実施 | |
| DTKN-FR-005 | burn（vault 限定・allowance 非依存・残高不足 revert） | unit, invariant=DTKN-INV-002 | ☐ | ☐ | | 未実施 | |
| DTKN-FR-006 | setCap（Owner 限定・現 supply 未満も可・既発行維持） | unit, invariant=DTKN-INV-005 | ☐ | ☐ | | 未実施 | |
| DTKN-FR-007 | permit（EIP-2612・DOMAIN_SEPARATOR が実 name() 追従・ERC-5267） | unit, integration | ☐ | ☐ | | 未実施 | integration=標準ウォレット署名の検証成立 |
| DTKN-FR-008 | アップグレード（UUPS・Owner 限定・storage 追記のみ） | unit, manual | ☐ | ☐ | | 未実施 | manual=storage layout review |
| DTKN-FR-009 | Owner 移譲（2-step）・pending cancel・renounce 無効化 | unit, manual | ☐ | ☐ | | 未実施 | |
| DTKN-FR-010 | Underlying allowlist（contract-only・bind 前のみ・イベント） | unit, manual | ☐ | ☐ | | 未実施 | |

### 6.2 不変条件（DTKN-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DTKN-INV-001 | decimals() は常に 18（確定前後とも） | unit | ☐ | N/A | | 未実施 | N/A: 定数 view（破壊操作が存在しない） |
| DTKN-INV-002 | mint/burn は vault のみ（Owner も不可） | invariant | ☐ | ☐ | | 未実施 | |
| DTKN-INV-003 | setTokenInfo は totalSupply==0 のときのみ・確定後 4 値不変 | invariant | ☐ | ☐ | | 未実施 | |
| DTKN-INV-004 | _decimalMultiplier は確定後 10**(18−dec)・確定前 0 | unit | ☐ | ☐ | | 未実施 | |
| DTKN-INV-005 | mint は totalSupply+amount ≤ cap のときのみ（totalSupply ≤ cap は大域不変でない点も確認） | invariant | ☐ | ☐ | | 未実施 | |
| DTKN-INV-006 | 換算整合（乗算厳密・floor 安全側・整数倍の往復 dust 0） | fuzz | ☐ | ☐ | | 未実施 | |
| DTKN-INV-007 | vault は initialize 後不変 | invariant | ☐ | ☐ | | 未実施 | |
| DTKN-INV-008 | 未確定中は convertTo*/mint が TokenInfoNotSet revert | unit | ☐ | ☐ | | 未実施 | |
| DTKN-INV-009 | Owner は acceptOwnership 成功時のみ変更・renounce では不変 | unit | ☐ | ☐ | | 未実施 | |
| DTKN-INV-010 | setTokenInfo は allowlist 済み・code>0 のみ成功・確定後 allowlist 更新不可 | unit | ☐ | ☐ | | 未実施 | |

### 6.3 セキュリティ要件（DTKN-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DTKN-SEC-001 | mint/burn の vault 限定（OnlyVault） | unit, invariant=DTKN-INV-002 | ☐ | ☐ | | 未実施 | |
| DTKN-SEC-002 | allowance 非依存 burn の vault への閉じ込め | unit, manual | ☐ | ☐ | | 未実施 | |
| DTKN-SEC-003 | permit DOMAIN_SEPARATOR の実名追従（placeholder 固定による永久 revert 防止） | unit, integration | ☐ | ☐ | | 未実施 | |
| DTKN-SEC-004 | placeholder stranded 防止（未確定 mint 禁止） | unit, invariant=DTKN-INV-008 | ☐ | ☐ | | 未実施 | |
| DTKN-SEC-005 | アップグレード権限の Owner 限定 | unit, manual | ☐ | ☐ | | 未実施 | |
| DTKN-SEC-006 | Owner 権限喪失の防止（2-step・renounce 無効化） | unit | ☐ | ☐ | | 未実施 | |
| DTKN-SEC-007 | Underlying 誤 bind の防止（allowlist・EOA/未デプロイ拒否） | unit（DTKN-FR-010 / INV-010 と同） | ☐ | ☐ | | 未実施 | |

### 6.4 ガバナンス・運用・アップグレード要件（DTKN-GOV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DTKN-GOV-001 | Owner = GOV_MULTISIG（holder は共通 TimelockController 24h のみ・単一 EOA 禁止） | manual（デプロイ構成レビュー） | ☐ | N/A | | 未実施 | N/A: 構成レビュー項目（非権限系は DTKN-FR/SEC 行が持つ） |
| DTKN-GOV-002 | Owner 移譲は 2-step・誤指定は pending cancel | unit, manual | ☐ | ☐ | | 未実施 | |
| DTKN-GOV-003 | Owner 放棄のコード無効化（RenounceOwnershipDisabled） | unit | ☐ | ☐ | | 未実施 | |
| DTKN-GOV-004 | Owner timelock（内蔵せず holder=共通 Timelock 24h・緊急即時操作なし・pause は Vault 側） | manual（Owner=Timelock の assert） | ☐ | ☐ | | 未実施 | |
| DTKN-GOV-005 | allowlist の deploy レビュー（chainId・address・decimals・proxy・blacklist 権限） | manual（mainnet deploy checklist） | ☐ | N/A | | 未実施 | N/A: deploy checklist の実施記録項目 |

### 6.5 イベント・監視要件（DTKN-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DTKN-EVT-001 | TokenInfoSet（確定の検知・1 度のみ） | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| DTKN-EVT-002 | CapUpdated(oldCap, newCap) | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| DTKN-EVT-003 | ERC20 Transfer（mint: from=0 / burn: to=0） | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| DTKN-EVT-004 | OwnershipTransferStarted / OwnershipTransferred | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| DTKN-EVT-005 | AllowedUnderlyingUpdated(underlying, allowed) | unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 6.6 失敗時・異常系挙動（§12 ERR・ID なし）

placeholder 期挙動（各行 = doc §12 の表 1 行。発火実証列に ✅）:

| # | 事象 | 期待挙動（doc §12） | 発火実証 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | placeholder 期の name()/symbol() | placeholder 値 → 確定後は確定値 | ☐ | | 未実施 | |
| 2 | placeholder 期の decimals() | 常に 18 | ☐ | | 未実施 | DTKN-INV-001 と同証跡可 |
| 3 | placeholder 期の convertTo* | TokenInfoNotSet revert | ☐ | | 未実施 | |
| 4 | placeholder 期の mint | TokenInfoNotSet revert | ☐ | | 未実施 | |

エラーカタログ（各エラーが少なくとも 1 テストで実発火すること）:

| # | エラー | 契機（参照） | 発火実証 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | OnlyVault | vault 以外の mint/burn（DTKN-SEC-001） | ☐ | | 未実施 | |
| 2 | TokenInfoNotSet | 未確定での convert/mint（DTKN-INV-008） | ☐ | | 未実施 | |
| 3 | CapExceeded | cap 超過 mint（DTKN-FR-004） | ☐ | | 未実施 | |
| 4 | InvalidUnderlyingDecimals | setTokenInfo で decimals>18（DTKN-FR-002） | ☐ | | 未実施 | |
| 5 | NotContract | setAllowedUnderlying / setTokenInfo に EOA・未デプロイ | ☐ | | 未実施 | |
| 6 | UnderlyingNotAllowed | allowlist 未承認の setTokenInfo | ☐ | | 未実施 | |
| 7 | TokenInfoAlreadySet | setTokenInfo 再呼出／確定後の setAllowedUnderlying | ☐ | | 未実施 | |
| 8 | UnderlyingMismatch（Vault 側） | CollateralVault.setUnderlying の不一致（dToken-first 違反含む） | ☐ | | 未実施 | §7 Vault 行と同証跡可 |
| 9 | RenounceOwnershipDisabled | renounceOwnership 呼出（DTKN-FR-009 / SEC-006） | ☐ | | 未実施 | |

### 6.7 未決事項レジスタ（DTKN-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| DTKN-TBD-001 | Resolved（2026-06-12） | 反映先 DTKN-FR-008 / DTKN-GOV-004 の行で検証 | 共通 Timelock 採用 |
| DTKN-TBD-002 | Resolved（実装済・doc 除外） | 反映先 DTKN-FR-009 行で検証 | Owner 移譲 2-step 化 |
| DTKN-TBD-003 | Resolved（実装済・doc 除外） | 反映先 DTKN-FR-009 行で検証 | Owner 放棄の無効化 |

---

## 7. CollateralVault.md（VAULT）

正本: [CollateralVault.md](../../protocol/product/spec/CollateralVault.md)。対象: `contracts/src/CollateralVault.sol` ほか。

### 7.1 機能要件（VAULT-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| VAULT-FR-001 | deposit（Underlying→dToken。pause/ready/zero・実着額換算・mint） | unit, integration | ☐ | ☐ | | 未実施 | |
| VAULT-FR-002 | redeem（即時／遅延・先着総取り・CEI・exact amount 拒否・receiver 実着額返却） | unit, integration, invariant=VAULT-INV-002/003/014 | ☑ | ☑ | `test_Redeem_ImmediateWhenBufferSufficient`; `test_Redeem_ShortfallCreatesRequest`; `test_Redeem_QueuesShortfallBeforePartialBufferTransferHook`; `test_Redeem_FeeOnTransferReturnsReceiverBalanceDelta` | PASS(V21/unit) | fee-on-transfer Underlying でも返値は receiver 残高差分。integration / invariant は未実施 |
| VAULT-FR-003 | redeemWithPermit（exact check→permit→burn(self)・各 revert） | unit, integration | ☑ | ☑ | `forge test --match-path test/CollateralVault.t.sol`（V6 / 2026-06-21: 55 passed） | PASS(unit) | round-trip / permit front-run 済み nonce + allowance / invalid permit + allowance 不足 `PermitFailed` / zero amount / zero receiver / non-exact dust before permit を確認。integration は未実施 |
| VAULT-FR-004 | allocate（cooldown/pause/M==0・partial valuation 時は全 outbound 停止＋cooldown 非消費＋自動復旧・cap クランプ・固定 weights・deposit reject は完全回収時のみ skip・回収不一致は全体 revert・再配分なし） | unit, invariant=VAULT-INV-006 | ☐ | ☐ | | 未実施 | |
| VAULT-FR-005 | receiveFromStrategy（登録判定・残高差分計上・ゼロ短絡・exact partial recovery は cache 値のみ減額して TTL 非更新・declared/received 不一致時 cache 無効化） | unit, invariant=VAULT-INV-005 | ☑ | ☑ | `test_ReceiveFromStrategy_OnlyFromRegistered`; `test_ReceiveFromStrategy_ZeroAmountFromRegistered`; `test_FeeOnTransferToken_PrincipalMatchesSent`; `test_FeeOnTransferToken_InvalidatesCacheBeforeValuationOutage`; `test_SendToVault_PartialRecoveryDoesNotRenewValuationCache` | PASS(PRELIM-L03/unit) | receipt だけから残存 position の価値を再評価せず、期限後は fail-closed。両 live read の復旧で availability が直ちに回復し、permissionless refresh が cache を再格納。invariant は未実施 |
| VAULT-FR-006 | claim（permissionless trigger・owner 固定送金・settlement 済み retry は 0・未発行/時刻/buffer 各 revert・部分不可・無期限・pausedClaim 停止） | unit, invariant=VAULT-INV-004 | ☑ | ☑ | `test_Claim_FrontRunSettlementMakesOwnerRetryIdempotent`; `test_Claim_PermissionlessTriggerPaysContractRequestOwner`; `test_Claim_UnknownId_Reverts`; `forge test --match-path test/InvariantPushModel.t.sol` | PASS(PRELIM-L01) | 先行 settlement 後の owner retry は state / balance / event を再変更しない。ただし送信済み no-op tx のガス消費自体は防げない |
| VAULT-FR-007 | transferYieldToTreasury（M≤L 早期・buffer クランプ・min 評価・backstop 除外） | unit, invariant=VAULT-INV-001/005 | ☐ | ☐ | | 未実施 | |
| VAULT-FR-008 | whitelist / addStrategy / removeStrategy（ガード・Underlying 不変条件・principal==0・add=GOV / remove=GUARDIAN） | unit, invariant=VAULT-INV-007/008 | ☐ | ☐ | | 未実施 | |
| VAULT-FR-009 | updateStrategy（GOV）/ writeoffStrategyPrincipal・forceDeallocateMorphoV2（WRITEOFF・atomic incident pause・penalty / backing guard・tracked-loss cache 反映） | unit, invariant=VAULT-INV-009 | ☑ | ☑ | `CollateralVaultStrategyTest::test_UpdateStrategy_ReEnableAfterDisable`; `test_UpdateStrategy_DisableWithNonZeroWeight_Reverts`; `test_WriteoffStrategyPrincipal_RevertsWhileEnabledAndAllocationUnpaused`; `test_WriteoffStrategyPrincipal_DoesNotRestoreUnavailablePricing`; `test_ForceDeallocateMorphoV2_ReducesFallbackCacheByTrackedLossAndRecovery`; `MorphoV2StrategyTest` force-deallocation 群; `InvariantPushModelTest::invariant_disabledStrategiesHaveZeroWeightAndWeightSumMatches` | PASS(VAULT-RECERT-20260812) | update / disable / writeoff / Morpho force-deallocation の正常系・権限/保護ガードと、重み合計の持続を 500 runs / 25,000 calls で再認証 |
| VAULT-FR-010 | initialize（placeholder 化・4 ロール付与・既定値・ゼロ/再初期化 revert） | unit, manual | ☐ | ☐ | | 未実施 | |
| VAULT-FR-011 | setUnderlying（一度きり・dToken-first・whenUnderlyingReady 双方向ガード） | unit, invariant=VAULT-INV-010/011, manual | ☐ | ☐ | | 未実施 | |
| VAULT-FR-012 | GOV 設定 setter（setBufferConfig / setAllocatorConfig / setStrategyValuationMaxAge / setWithdrawDelay / setTreasury。限定・検証・即時反映） | unit | ☐ | ☐ | | 未実施 | |
| VAULT-FR-013 | View 群（bufferBalance / backstopBalance / totalUnderlying / Strategy 列挙。placeholder-safe・index・生値 vs min） | unit, manual | ☐ | ☐ | | 未実施 | |
| VAULT-FR-014 | Pause / Unpause（GUARDIAN/GOV 非対称・4 系統独立・claim 停止） | unit | ☐ | ☐ | | 未実施 | |
| VAULT-FR-015 | アップグレード（UUPS・GOV 限定・storage 追記のみ） | unit, manual | ☐ | ☐ | | 未実施 | |
| VAULT-FR-016 | operational backingRatio と pricing availability（取得不能 vs 実測0・下方専用・L_eff==0→1e18・liability dust 切り上げ・placeholder-safe） | unit, fork, invariant=VAULT-INV-012/014 | ☑ | ☑ | `CollateralVaultTest::test_BackingRatio_ZeroLiabilitiesAndHealthyReturnOne`; `test_BackingRatio_ImpairmentReturnsAssetOverLiability`; `test_ActualLiabilities_RoundsUpDTokenDust`; `test_PricingViewDistinguishesUnavailableValuationFromMeasuredZero`; `test_WriteoffStrategyPrincipal_DoesNotRestoreUnavailablePricing`; `InvariantPushModelTest::invariant_backingRatioMatchesDefinition`; `invariant_actualLiabilitiesUseCeilingAndIncludePending` | PARTIAL(VAULT-RECERT-20260812/unit+invariant) | unit / invariant は完了。pricing unavailable と live recovery の境界も維持。規定された pinned mainnet fork 証跡のみ未実施 |
| VAULT-FR-017 | backstopDeposit / releaseBackstopToBuffer（実着額計上・mint なし・backing 回復・GOV 明示解放） | unit, integration, invariant=VAULT-INV-013 | ☐ | ☐ | | 未実施 | |
| VAULT-FR-018 | backing ops views（liability / shortfall / 目標比率補填額・切り上げ・target>1e18 revert） | unit, integration, invariant=VAULT-INV-014 | ☐ | ☐ | | 未実施 | |
| VAULT-FR-019 | emergencyDisableStrategy（GUARDIAN 即時・weight 0 化・冪等・backing 不変・再有効化は updateStrategy のみ） | unit, invariant=VAULT-INV-009 | ☑ | ☑ | `CollateralVaultStrategyTest::test_EmergencyDisableStrategy_ZeroesWeightPausesAllocationWithoutChangingBacking`; `test_EmergencyDisableStrategy_RevertsForUnregisteredStrategy`; `test_UpdateStrategy_ReEnableAfterDisable`; `InvariantPushModelTest::invariant_disabledStrategiesHaveZeroWeightAndWeightSumMatches` | PASS(VAULT-RECERT-20260812) | guardian incident path と governance recovery を持続的な操作列で再認証 |

### 7.2 不変条件（VAULT-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| VAULT-INV-001 | ソルベンシー原則（健全時 totalUnderlying ≥ L_effective。毀損時は backingRatio<1e18 が Oracle 経由で清算機構へ伝播） | invariant | ☐ | ☐ | | 未実施 | |
| VAULT-INV-002 | redeem の CEI 順序・全量 burn・非 exact 額の InvalidDTokenAmount 拒否 | invariant | ☐ | ☐ | | 未実施 | |
| VAULT-INV-003 | 不足 redeem: 即時支払い＋request == needed・pendingWithdrawals が remaining 分増加 | invariant | ☐ | ☐ | | 未実施 | |
| VAULT-INV-004 | pendingWithdrawals == Σ 未 claim request・二重 claim 不可（claimed フラグ） | invariant | ☐ | ☐ | | 未実施 | |
| VAULT-INV-005 | totalUnderlying == raw 残高＋Σ 保守評価（min / fresh cache / 0 評価・outflow 増分・received 減額、partial receipt で cache TTL 非更新） | invariant | ☐ | ☐ | `test_SendToVault_PartialRecoveryDoesNotRenewValuationCache` | SUPPORT(PRELIM-L03/unit) | timestamp safety / liveness の unit 境界は確認。規定 invariant campaign は未実施 |
| VAULT-INV-006 | allocate の移動量 ≤ allocateMaxMove・配分 ≤ cap 残・削減分は buffer 残置 | invariant | ☐ | ☐ | | 未実施 | |
| VAULT-INV-007 | addToWhitelist / addStrategy のガード（EOA 拒否・whitelist・vault.underlying 確定・underlying 一致） | invariant | ☐ | ☐ | | 未実施 | |
| VAULT-INV-008 | removeStrategy は principal==0 のみ（StrategyHasPrincipal） | invariant | ☐ | ☐ | | 未実施 | |
| VAULT-INV-009 | disabled Strategy は weightBps==0・totalWeightBps == Σ ≤ 10000 | invariant | ☑ | ☑ | `InvariantPushModelTest::invariant_disabledStrategiesHaveZeroWeightAndWeightSumMatches`; `CollateralVaultStrategyTest::test_UpdateStrategy_DisableWithNonZeroWeight_Reverts`; `test_EmergencyDisableStrategy_ZeroesWeightPausesAllocationWithoutChangingBacking` | PASS(VAULT-RECERT-20260812) | update / emergency disable / unpause を含む 500 runs / 25,000 calls / 0 reverts |
| VAULT-INV-010 | setUnderlying 一度のみ・active 期は dToken.underlying == vault.underlying を利用時点強制 | invariant | ☐ | ☐ | | 未実施 | |
| VAULT-INV-011 | placeholder 期の全面封じ込め（deposit/redeem/backstop/addStrategy revert・view 0・allocate 早期 return） | invariant | ☐ | ☐ | | 未実施 | |
| VAULT-INV-012 | backingRatio の定義（L_eff==0→1e18・min(1e18, A/L)・view 非 revert） | invariant | ☑ | ☑ | `InvariantPushModelTest::invariant_backingRatioMatchesDefinition`; `CollateralVaultTest::test_BackingRatio_ZeroLiabilitiesAndHealthyReturnOne`; `test_BackingRatio_ImpairmentReturnsAssetOverLiability`; `test_BackingOpsViews_StrategyValuationRevertUsesFreshCacheThenExpires` | PASS(VAULT-RECERT-20260812) | operational / pricing view の定義一致を 500 runs / 25,000 calls / 0 reverts で確認 |
| VAULT-INV-013 | backstopDeposit/release の会計効果（supply・pendingWithdrawals 不変・backing 非低下） | invariant | ☐ | ☐ | | 未実施 | |
| VAULT-INV-014 | liability dust の Underlying base unit 切り上げ（過小評価しない） | unit / invariant | ☑ | ☑ | `InvariantPushModelTest::invariant_actualLiabilitiesUseCeilingAndIncludePending`; `CollateralVaultTest::test_ActualLiabilities_RoundsUpDTokenDust`; `test_BackingOpsViews_IncludePendingWithdrawalsAndRoundUp` | PASS(VAULT-RECERT-20260812) | supply 変動と queued claim を含む 500 runs / 25,000 calls / 0 reverts |

### 7.3 セキュリティ要件（VAULT-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| VAULT-SEC-001 | CEI / Reentrancy（再入遮断） | unit（再入テスト）, invariant=VAULT-INV-002/004 | ☐ | ☐ | | 未実施 | |
| VAULT-SEC-002 | Underlying 整合の利用時点強制（fail-closed・両パス） | unit, invariant=VAULT-INV-010 | ☐ | ☐ | | 未実施 | |
| VAULT-SEC-003 | 受領額は残高差分で計上（declared 非依存・fee-on-transfer 模擬） | unit, invariant=VAULT-INV-005 | ☐ | ☐ | | 未実施 | |
| VAULT-SEC-004 | 活性化前の資金封じ込め（多層防御） | unit, invariant=VAULT-INV-011 | ☐ | ☐ | | 未実施 | |
| VAULT-SEC-005 | ALLOCATOR の最小権限（固定宛先・固定比率・treasury 変更不可・pause 中 outbound 停止） | unit, manual | ☐ | ☐ | | 未実施 | |
| VAULT-SEC-006 | pause/unpause の非対称権限（pause=GUARDIAN・unpause=GOV・GUARDIAN 操作の backing 不変） | unit | ☐ | ☐ | | 未実施 | |
| VAULT-SEC-007 | アップグレード権限の限定（非 GOV 承認 revert） | unit, manual（storage layout review） | ☐ | ☐ | | 未実施 | |
| VAULT-SEC-008 | dToken dust の silent burn 防止（USDC6 / WBTC8 dust・permit nonce 未消費・permit front-run 許容） | unit, invariant=VAULT-INV-002/014 | ☑ | ☑ | `forge test --match-path test/CollateralVault.t.sol`（V6 / 2026-06-21: 55 passed） | PASS(unit) | non-exact dust は permit 前に revert し nonce を消費しない。permit が先に消費されても allowance が残っていれば `redeemWithPermit` は成功し、invalid permit かつ allowance 不足時のみ `PermitFailed` |
| VAULT-SEC-009 | blacklistable token の個別 revert 隔離（state rollback） | unit, manual（token risk review） | ☐ | ☐ | | 未実施 | |

### 7.4 ガバナンス・運用・アップグレード要件（VAULT-GOV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| VAULT-GOV-001 | ロール分離（初期集中 → 本番分離） | manual（デプロイ構成レビュー）＋ deploy script / integration の holder assert | ☐ | N/A | | 未実施 | N/A: 構成レビュー項目（非権限 revert は VAULT-GOV-002 行が持つ） |
| VAULT-GOV-002 | ロール × 操作マトリックス（全セルの権限強制） | manual（権限テストの網羅） | ☐ | ☐ | | 未実施 | 異常系=非権限ロールの全操作 revert 網羅 |
| VAULT-GOV-003 | ロール設計上の考察（GUARDIAN 可逆 fail-safe / WRITEOFF 高定足数の分離） | manual | ☐ | N/A | | 未実施 | N/A: 設計考察の確認項目（実体は GOV-002/004 行） |
| VAULT-GOV-004 | timelock と緊急 pause の分離（GOV 系 holder=共通 Timelock 24h・GUARDIAN 即時・unpause は Timelock） | manual（構成レビュー）＋ deploy script / integration の holder・Timelock assert | ☐ | ☐ | | 未実施 | |

### 7.5 イベント・監視要件（VAULT-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| VAULT-EVT-001 | Deposited(user, underlyingAmount, dTokenAmount) | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| VAULT-EVT-002 | Redeemed(user, receiver, dTokenAmount, underlyingPaidNow, requestId)（requestId==0 は即時） | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| VAULT-EVT-003 | WithdrawRequested(user, receiver, requestId, amount, claimableAt) | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| VAULT-EVT-004 | Allocated / StrategyAllocated / StrategyAllocationSkipped | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| VAULT-EVT-005 | ReceivedFromStrategy(strategy, declaredAmount, received) | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| VAULT-EVT-006 | WithdrawClaimed(user, requestId, amount) | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| VAULT-EVT-007 | YieldTransferredToTreasury(amount, treasury)（amount==0 でも発火） | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| VAULT-EVT-008 | StrategyWhitelisted / RemovedFromWhitelist / Added / Updated / EmergencyDisabled 系 | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| VAULT-EVT-009 | StrategyPrincipalWrittenOff / ValuationRefreshed / ValuationRefreshFailed 系 | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| VAULT-EVT-010 | UnderlyingSet(underlying)（一度だけ） | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| VAULT-EVT-011 | BufferConfigUpdated / AllocatorConfigUpdated / StrategyValuationMaxAgeUpdated 等 setter イベント | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| VAULT-EVT-012 | Deposit/Redeem/Claim/Allocation の Paused / Unpaused（8 種） | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| VAULT-EVT-013 | ERC1967 Upgraded(newImpl) | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| VAULT-EVT-014 | BackstopDeposited(backstop, declaredAmount, received) | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| VAULT-EVT-015 | BackstopReleased(caller, amount) | unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 7.6 失敗時・異常系挙動（§12 ERR・ID なし）

placeholder 期挙動:

| # | 事象 | 期待挙動（doc §12） | 発火実証 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | placeholder 期の deposit / redeem / redeemWithPermit | UnderlyingNotSet revert（whenUnderlyingReady） | ☐ | | 未実施 | |
| 2 | placeholder 期の backstopDeposit / releaseBackstopToBuffer | UnderlyingNotSet revert | ☐ | | 未実施 | |
| 3 | placeholder 期の addStrategy | UnderlyingNotSet revert | ☐ | | 未実施 | |
| 4 | placeholder 期の bufferBalance / backstopBalance / totalUnderlying | 0 を返す（placeholder-safe） | ☐ | | 未実施 | |
| 5 | placeholder 期の allocate | 早期 return（資金不動） | ☐ | | 未実施 | |

システムレベル異常シナリオ（doc §12 の各節。integration / fork / manual・runbook で検証）:

| # | シナリオ | 期待挙動（doc §12） | 発火実証 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Underlying 設定リスク（VAULT-SEC-002） | fail-closed（利用時点強制） | ☐ | | 未実施 | |
| 2 | 償還流動性リスク（在庫不足） | 遅延償還へ縮退（即時保証しない） | ☐ | | 未実施 | |
| 3 | Strategy リスク（スマコン・流動性・ペグ・アンボンド） | 段階的回収（sendToVault→emergency→writeoff） | ☐ | | 未実施 | |
| 4 | dToken backing 毀損のオラクル反映 | backingRatio 低下 → 担保価値下方伝播 | ☐ | | 未実施 | SYS-RISK-002 と同根 |
| 5 | ALLOCATOR 鍵侵害 | 固定宛先・固定比率で被害限定（VAULT-SEC-005） | ☐ | | 未実施 | |
| 6 | AUM 評価と収益化（取りすぎ）リスク | min 評価・M≤L 早期 return（VAULT-FR-007） | ☐ | | 未実施 | |
| 7 | 遅延償還の既知リスク（先着総取り・無期限 claim） | VAULT-TBD-002 確定仕様どおりの運用対処 | ☐ | | 未実施 | |
| 8 | blacklistable Underlying（USDC 等） | 個別 tx revert として隔離（batch push しない） | ☐ | | 未実施 | |

エラーカタログ（各エラーが少なくとも 1 テストで実発火すること）:

| # | エラー | 契機（参照） | 発火実証 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Paused | pause 中の deposit / redeem / redeemWithPermit / claim（VAULT-FR-001..003,006,014） | ☐ | | 未実施 | |
| 2 | UnderlyingNotSet | Underlying 未設定（whenUnderlyingReady / addStrategy） | ☐ | | 未実施 | |
| 3 | UnderlyingMismatch | Vault / dToken の Underlying 不一致（dToken 未初期化含む） | ☐ | | 未実施 | |
| 4 | UnderlyingAlreadySet | setUnderlying の二度目（VAULT-FR-011） | ☐ | | 未実施 | |
| 5 | UnderlyingNotAllowed | initialize / setUnderlying で dToken allowlist 未承認 | ☐ | | 未実施 | |
| 6 | ZeroAmount | 金額 0 の deposit / redeem / redeemWithPermit / backstopDeposit / release | ☐ | | 未実施 | |
| 7 | ZeroAddress | initialize / redeem receiver / setUnderlying / setTreasury のゼロ | ☐ | | 未実施 | |
| 8 | InvalidDTokenAmount | 非 exact dToken amount の redeem / redeemWithPermit | ☐ | | 未実施 | |
| 9 | NotContract | initialize の dToken・whitelist/addStrategy の EOA / 未デプロイ | ☐ | | 未実施 | |
| 10 | CapExceeded（dToken 側） | deposit 時の cap 超過（DTKN-FR-004） | ☐ | | 未実施 | §6 と同証跡可 |
| 11 | CooldownNotMet | allocate の cooldown 未経過（VAULT-FR-004） | ☐ | | 未実施 | |
| 12 | InvalidBufferConfig | setBufferConfig の targetBps>10000（VAULT-FR-012） | ☐ | | 未実施 | |
| 13 | NotRegisteredStrategy | 未登録 Strategy の receiveFromStrategy（VAULT-FR-005） | ☐ | | 未実施 | |
| 14 | NotWhitelisted | whitelist 未承認の addStrategy（VAULT-FR-008） | ☐ | | 未実施 | |
| 15 | StrategyAlreadyExists | 既登録の addStrategy | ☐ | | 未実施 | |
| 16 | WeightExceedsBps | totalWeightBps 10000 超過（addStrategy / updateStrategy） | ☐ | | 未実施 | |
| 17 | InvalidWeight | updateStrategy で enabled==false かつ weight>0（VAULT-FR-009） | ☐ | | 未実施 | |
| 18 | StrategyNotFound | updateStrategy / writeoff の対象検証失敗 | ☐ | | 未実施 | |
| 19 | StrategyHasPrincipal | principal!=0 の removeStrategy（VAULT-FR-008） | ☐ | | 未実施 | |
| 20 | RequestNotFound | claim の未発行 ID（settlement 済み ID は 0 を返す、VAULT-FR-006） | ☑ | `CollateralVaultTest::test_Claim_UnknownId_Reverts` | PASS(PRELIM-L01) | error selector は維持し、意味を未発行 ID に限定 |
| 21 | 廃止: NotRequestOwner | 削除済み。誰でも settlement を起動できるが、送金先は request owner 固定（VAULT-FR-006） | ☑ | `CollateralVaultTest::test_Claim_PermissionlessTriggerPaysContractRequestOwner` | PASS(unit) | error selector 削除済み |
| 22 | RequestNotReady | claimableAt 前の claim | ☐ | | 未実施 | |
| 23 | InsufficientBuffer | claim 時の buffer 不足（部分 claim 不可・後日再試行） | ☐ | | 未実施 | |
| 24 | InsufficientBackstop | release の amount > backstopBalance() | ☐ | | 未実施 | |
| 25 | InvalidBackingTarget | backstopRequiredForRatio の target>1e18（VAULT-FR-018） | ☐ | | 未実施 | |
| 26 | "Index out of bounds"（require 文字列） | getStrategyAt の範囲外 index（VAULT-FR-013） | ☐ | | 未実施 | |
| 27 | PermitFailed | `redeemWithPermit` の permit 失敗かつ allowance 不足（VAULT-FR-003 / VAULT-SEC-008） | ☑ | `forge test --match-path test/CollateralVault.t.sol`（V6 / 2026-06-21: 55 passed） | PASS(unit) | `test_RedeemWithPermit_RevertsWhenPermitFailsAndAllowanceIsMissing` |

### 7.7 未決事項レジスタ（VAULT-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| VAULT-TBD-002 | Resolved（2026-06-11） | 先着総取り＋遅延償還・無期限 claim を Day-1 確定 → VAULT-FR-002/006・§7.6 シナリオ 7 で検証 | |
| VAULT-TBD-003 | Resolved（2026-06-12） | 共通 Timelock holder 方式 → VAULT-GOV-004 行で検証 | |
| VAULT-TBD-004 | Resolved（2026-06-11） | allocate の ALLOCATOR_ROLE 限定を恒久確定 → VAULT-FR-004 行で検証 | |
| （VAULT-TBD-001） | 欠番 | doc に不存在（append-only の欠番）。再利用しない | 網羅チェック時に欠番として扱う |

---

## 8. Strategy.md（STGY・共通アーキテクチャ）

正本: [Strategy.md](../../protocol/product/spec/strategies/Strategy.md)。対象: `IStrategy` / `BaseStrategy`。

### 8.1 機能要件（STGY-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| STGY-FR-001 | deposit（onlyVault・宣言額/純受取検証・外部運用 call 隔離・成功時 principal 加算・拒否時の完全回収と skip・回収不一致は全体 revert） | unit, integration（allocate→deposit 連携） | ☐ | ☐ | | 未実施 | |
| STGY-FR-002 | sendToVault（ALLOCATOR 限定・早期 return・sent ベース減算・principal-first） | unit, fork/integration | ☐ | ☐ | | 未実施 | |
| STGY-FR-003 | sendProfitToVault（ALLOCATOR 限定・yield==0/actual==0 早期 return・principal 不変） | unit, fork/integration | ☐ | ☐ | | 未実施 | |
| STGY-FR-004 | writeoffPrincipal（onlyVault・min クランプ・非負） | unit, invariant=STGY-INV-002 | ☐ | ☐ | | 未実施 | |
| STGY-FR-005 | emergencyWithdraw（onlyOwner・送金先 Vault 固定・principal 不変・_amount==0 no-op） | unit, integration | ☐ | ☐ | | 未実施 | |
| STGY-FR-006 | 派生 hook（_doDeposit / _doWithdraw / _estimatedTotalUnderlying） | unit, integration/fork（子 doc で外部 I/F 検証） | ☐ | ☐ | | 未実施 | AAVE 行が実体 |
| STGY-FR-007 | BaseStrategy 初期化（ゼロチェック・再初期化 revert・safeApprove(vault, max)・ownership 移譲） | unit, manual | ☐ | ☐ | | 未実施 | |
| STGY-FR-008 | view getter（principal / realizedYield 恒等・保守的評価・underlying 一致） | unit, integration | ☐ | ☐ | | 未実施 | |
| STGY-FR-009 | アップグレード（UUPS・upgrader 限定・Owner / 運用ロール revert・upgrader 再指定は upgrader のみ） | unit, manual | ☐ | ☐ | | 未実施 | |
| STGY-FR-010 | sweepRewardToken（非 Underlying・非 position 報酬のみ・送金先 current treasury・実着額・全量指定） | unit | ☐ | ☐ | | 未実施 | |
| STGY-FR-011 | Owner 移譲（2-step・pending cancel・renounce disabled・zero owner init revert） | unit, manual | ☐ | ☐ | | 未実施 | |
| STGY-FR-012 | claimMerklRewards（distributor 検証・recipient 固定・protected token claim 前拒否・Treasury 実着額） | unit | ☐ | ☐ | | 未実施 | |

### 8.2 不変条件（STGY-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| STGY-INV-001 | deposit / writeoffPrincipal は vault のみ・send 系は Vault の ALLOCATOR_ROLE 保持者のみ | invariant | ☐ | ☐ | | 未実施 | |
| STGY-INV-002 | principal は 0 未満にならない（min クランプ） | invariant | ☐ | ☐ | | 未実施 | |
| STGY-INV-003 | sendProfitToVault・emergencyWithdraw は principal を変えない | invariant | ☐ | ☐ | | 未実施 | |
| STGY-INV-004 | realizedYield() == max(estimatedTotalUnderlying() − principal, 0)（恒等） | unit | ☐ | ☐ | | 未実施 | |
| STGY-INV-005 | principal 減算は Vault 実受領額 sent ベース（declared 非依存） | invariant | ☐ | ☐ | | 未実施 | |
| STGY-INV-006 | underlying() は不変・対応 Vault の Underlying と一致（addStrategy が検証） | invariant | ☐ | ☐ | | 未実施 | |
| STGY-INV-007 | vault / underlyingToken は __BaseStrategy_init 後不変 | invariant | ☐ | ☐ | | 未実施 | |
| STGY-INV-008 | sweepRewardToken / claimMerklRewards は Underlying / 保護 position token を拒否し会計に影響しない | unit | ☐ | ☐ | | 未実施 | |
| STGY-INV-009 | Owner は acceptOwnership 成功時のみ変更・renounce では不変 | unit | ☐ | ☐ | | 未実施 | |
| STGY-INV-010 | UUPS upgrade は upgrader のみ承認・Owner/ALLOCATOR/vault 不可・upgrader はゼロアドレス不可 | unit | ☐ | ☐ | | 未実施 | develop追補（upgrader 分離） |
| STGY-INV-011 | nonReentrantStrategy が付いた Strategy entry point は同一 tx 内で nested 実行できず、外部 protocol / token callback から別の guarded entry point へ再入した場合は ReentrantCall で revert | unit | ☐ | ☐ | | 未実施 | develop追補（reentrancy guard） |

### 8.3 セキュリティ要件（STGY-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| STGY-SEC-001 | ALLOCATOR 鍵侵害時の被害境界（任意宛先へ送れない・deposit は onlyVault） | unit, manual | ☐ | ☐ | | 未実施 | |
| STGY-SEC-002 | Owner 鍵侵害時の被害境界（emergencyWithdraw 宛先固定・Owner から upgrade 不可） | unit, manual | ☐ | ☐ | | 未実施 | |
| STGY-SEC-003 | emergencyWithdraw の送金先 Vault 固定（任意アドレス送金不可） | unit | ☐ | ☐ | | 未実施 | |
| STGY-SEC-004 | AUM 過大評価への保守的会計（収益取りすぎ不可） | unit, integration | ☐ | ☐ | | 未実施 | |
| STGY-SEC-005 | 流動性不足の正常系扱い（actual<requested / actual==0 で revert しない・DoS 耐性） | unit, integration | ☐ | ☐ | | 未実施 | |
| STGY-SEC-006 | 報酬 sweep / Merkl claim の会計境界（Underlying / position token 拒否・宛先固定・recipient 固定・実着額） | unit, manual | ☐ | ☐ | | 未実施 | |
| STGY-SEC-007 | Owner 権限喪失の防止（2-step・renounce disabled・zero owner init revert） | unit | ☐ | ☐ | | 未実施 | |
| STGY-SEC-008 | Upgrader 鍵侵害時の被害境界（upgrader のみ upgrade/setUpgrader・zero upgrader revert） | unit, manual | ☐ | ☐ | | 未実施 | develop追補（upgrader 分離） |

### 8.4 ガバナンス・運用・アップグレード要件（STGY-GOV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| STGY-GOV-001 | Owner / upgrader の holder 構成 | manual（構成レビュー・holder assert） | ☐ | N/A | | 未実施 | N/A: holder 構成レビュー項目（非権限系は STGY-FR-009 行） |
| STGY-GOV-002 | 緊急時オペレーション（updateStrategy→緊急回収の runbook） | manual, integration | ☐ | ☐ | | 未実施 | |
| STGY-GOV-003 | Owner timelock（upgrader=共通 Timelock 24h・Owner=Guardian 即時の分離） | manual（構成レビュー・holder assert） | ☐ | ☐ | | 未実施 | |
| STGY-GOV-004 | Owner 移譲と放棄（2-step・renounce 無効） | unit, manual | ☐ | ☐ | | 未実施 | |
| STGY-GOV-005 | Upgrader は専用主体（Owner と分離した holder 構成） | manual（デプロイ構成レビュー） | ☐ | N/A | | 未実施 | develop追補。N/A: 構成レビュー項目（非権限 revert は STGY-INV-010/SEC-008 行が持つ） |

### 8.5 イベント・監視要件（STGY-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| STGY-EVT-001 | Deposited(amount, newPrincipal) | unit | ☐ | ☐ | | 未実施 | |
| STGY-EVT-002 | SentToVault(caller, requested, actual, newPrincipal) | unit | ☐ | ☐ | | 未実施 | |
| STGY-EVT-003 | ProfitSentToVault(caller, yield, actual) | unit | ☐ | ☐ | | 未実施 | |
| STGY-EVT-004 | PrincipalWrittenOff(amount, newPrincipal) | unit | ☐ | ☐ | | 未実施 | |
| STGY-EVT-005 | EmergencyWithdrawn(amount) | unit | ☐ | ☐ | | 未実施 | |
| STGY-EVT-006 | Emergency*Withdrawn（派生固有・推奨） | unit | ☐ | ☐ | | 未実施 | 派生実装に依存（AAVE-TBD-004 参照） |
| STGY-EVT-007 | RewardTokenSwept(token, treasury, requested, received) | unit | ☐ | ☐ | | 未実施 | |
| STGY-EVT-008 | OwnershipTransferStarted / OwnershipTransferred | unit | ☐ | ☐ | | 未実施 | |
| STGY-EVT-009 | UpgraderUpdated(oldUpgrader, newUpgrader) / ERC1967 Upgraded(newImpl) | unit | ☐ | ☐ | | 未実施 | develop追補（upgrader 分離） |
| STGY-EVT-010 | MerklRewardsClaimed(distributor, token, cumulativeAmount, swept) | unit | ☐ | ☐ | | 未実施 | Merkl claim 追加 |
| STGY-EVT-011 | PrincipalReturned(amount, newPrincipal) | unit | ☐ | ☐ | | 未実施 | 固有緊急回収の returned principal 記帳 |
| STGY-EVT-012 | PendingWithdrawalValuationBpsUpdated(oldBps, newBps) | unit | ☐ | ☐ | | 未実施 | async pending valuation bps 変更の監視 |

### 8.6 失敗時・異常系挙動（STGY-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| STGY-ERR-001 | 共通リスクと失敗時挙動（外部プロトコル障害・流動性不足・評価不能の縮退） | manual, integration | ☐ | ☐ | | 未実施 | |
| STGY-ERR-002 | 非同期な外部プロトコルの取り扱い（push モデルが同期/非同期を Strategy 内部に隠蔽） | manual, integration | ☐ | ☐ | | 未実施 | SYS-RISK-004 と同根 |

### 8.7 未決事項レジスタ（STGY-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| STGY-TBD-001 | Resolved（2026-06-12） | upgrader 分離＋共通 Timelock → STGY-FR-009 / STGY-GOV-003 行で検証 | |
| STGY-TBD-002 | Resolved（実装済み） | Strategy 別の保守的 withdraw cap（部分回収化）は各派生 Strategy に実装済み。流動性不足を confirmed loss と扱わず、評価は現在流動性で下げない | AAVE-TBD-008 / ERC4626Strategy と連動 |

---

## 9. AaveV3Strategy.md（AAVE）

正本: [AaveV3Strategy.md](../../protocol/product/spec/strategies/AaveV3Strategy.md)。対象: `AaveV3Strategy.sol`。fork 検証は実 Aave V3（mainnet fork）。

### 9.1 機能要件（AAVE-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AAVE-FR-001 | initialize（投資先固定・aToken underlying 検証・Pool max approve・ゼロ/多重 revert） | unit | ☐ | ☐ | | 未実施 | |
| AAVE-FR-002 | addStrategy 前提（whitelist→addStrategy・Underlying 一致検証） | integration, manual | ☐ | ☐ | | 未実施 | |
| AAVE-FR-003 | _doDeposit（supply(onBehalfOf=this)・scaled 差分計上・zero-scaled/cap 拒否を隔離 call frame で revert・完全回収後 skip） | unit, fork, invariant=AAVE-INV-001 | ☑ | ☑ | `test_Allocate_RecoversAndSkipsWhenAaveSupplyMintsZeroScaledBalance`; `test_Allocate_RecoversAndSkipsWhenAaveSupplyCapRejects`; `test_DonationDoesNotInflateRealizedYield` | PASS(unit V9 + Low-01) | fork=frozen/paused 拒否と invariant は未実施 |
| AAVE-FR-004 | _doWithdraw（withdraw(to=this)・scaled 減算・zero-scaled burn revert・0 下限・liquid reserve cap による partial / 0 回収） | unit, fork, invariant=AAVE-INV-001 | ☑ | ☑ | `test_SendToVault_RevertsWhenAaveWithdrawBurnsZeroScaledBalance`; `test_SendToVault_CapsAaveWithdrawalToLiquidUnderlying`; `test_SendToVault_AaveWithdrawalCreditsNetUnderlyingReceipt` | PASS(unit V9) | fork/invariant は未実施。AAVE-TBD-008 解決を反映 |
| AAVE-FR-005 | _estimatedTotalUnderlying（min・RAY 換算・donation 排除・effective==0→0） | unit, fork, invariant=AAVE-INV-002 | ☐ | ☐ | | 未実施 | |
| AAVE-FR-006 | emergencyWithdrawFromAave（onlyOwner・liquid reserve cap・同一 Tx で Vault 着金・returned principal 記帳） | unit, fork, integration, manual | ☑ | ☑ | `test_EmergencyWithdrawFromAave_DrainsResetsScaleAndPushesToVault`; `test_EmergencyWithdrawFromAave_PartialWhenReserveIlliquid`; `test_EmergencyWithdrawFromAave_RevertsWhenAaveWithdrawBurnsZeroScaledBalance` | PASS(unit V9) | fork/integration/manual は未実施 |
| AAVE-FR-007 | claimAaveRewards（assets=aToken 固定・Underlying reward は Vault buffer・非 Underlying reward は Treasury sweep・protected token 拒否） | unit, fork | ☐ | ☐ | | 未実施 | |

### 9.2 不変条件（AAVE-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AAVE-INV-001 | _ownScaledBalance は自関数（deposit 差分加算 / withdraw・emergency の実 burn 分減算 0 下限）のみで変化 | invariant | ☐ | ☐ | | 未実施 | |
| AAVE-INV-002 | 評価 = mulDiv(min(own, actual scaled), normalizedIncome, RAY)（donation を AUM に含めない） | invariant / fork | ☐ | ☐ | | 未実施 | |
| AAVE-INV-003 | aavePool / aToken は initialize 後不変（setter なし） | invariant | ☐ | ☐ | | 未実施 | |
| AAVE-INV-004 | supply は onBehalfOf==this・withdraw は to==this | unit | ☐ | ☐ | | 未実施 | |
| AAVE-INV-005 | sweepRewardToken(aToken) は CannotSweepProtectedToken revert・通常 reward は sweep 可 | unit | ☐ | ☐ | | 未実施 | |

### 9.3 セキュリティ要件（AAVE-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AAVE-SEC-001 | 投資先アドレスの initialize 時固定 | invariant=AAVE-INV-003, manual（setter 不在レビュー） | ☐ | ☐ | | 未実施 | |
| AAVE-SEC-002 | 第三者 donation による AUM 水増しの排除（donation 注入でも realizedYield 不変） | invariant=AAVE-INV-001/002, fork | ☐ | ☐ | | 未実施 | |
| AAVE-SEC-003 | 緊急回収の宛先固定と権限分離（ALLOCATOR 呼出 revert・同一 Tx Vault 着金） | unit, manual | ☐ | ☐ | | 未実施 | |
| AAVE-SEC-004 | Pool / aToken 誤設定の防止（UNDERLYING_ASSET_ADDRESS 検証・誤設定 revert） | unit, manual（deploy assert 手順） | ☐ | ☐ | | 未実施 | |
| AAVE-SEC-005 | aToken の reward sweep 禁止 | unit | ☐ | ☐ | | 未実施 | AAVE-INV-005 と同証跡可 |

### 9.4 ガバナンス・運用・アップグレード要件（AAVE-GOV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AAVE-GOV-001 | 投資先差し替えは Strategy 再作成（setter を設けない） | manual（運用 runbook） | ☐ | N/A | | 未実施 | N/A: 運用 runbook 項目（setter 不在は AAVE-INV-003 行で検証） |
| AAVE-GOV-002 | testnet 先行（Sepolia 統合テスト完了） | manual | ☐ | N/A | | 未実施 | N/A: 手順実施記録のみ（testnet 完了の事実確認） |
| AAVE-GOV-003 | 異常時の新規割当停止と緊急回収 | manual（監視・運用 runbook） | ☐ | ☐ | | 未実施 | |

### 9.5 イベント・監視要件（AAVE-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AAVE-EVT-001 | OwnScaledBalanceUpdated(ownScaledBalance) | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| AAVE-EVT-002 | EmergencyWithdrawn(amount)（BaseStrategy 共通イベント・emergencyWithdrawFromAave の Vault 直送額） | unit（台帳定義） | ☐ | ☐ | | 未実施 | AAVE-TBD-004 は Aave drain 額専用イベント追加の要否 |
| AAVE-EVT-003 | AaveRewardsClaimed(rewardsController, reward, requested, claimed, settled) | unit（台帳定義） | ☐ | ☐ | | 未実施 | 非 Underlying Aave reward settlement |
| AAVE-EVT-004 | AaveUnderlyingRewardsClaimed(rewardsController, reward, requested, claimed, sentToVault) | unit（台帳定義） | ☐ | ☐ | | 未実施 | Underlying Aave reward の Vault buffer settlement |

### 9.6 失敗時・異常系挙動（AAVE-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AAVE-ERR-001 | Aave reserve 設定変更（frozen / paused / supply cap）時の挙動 | fork（台帳定義） | ☐ | ☐ | | 未実施 | |
| AAVE-ERR-002 | utilization 100% 時は Strategy 側 cap で partial / 0 回収。reserve paused 等で Aave withdraw 自体が拒否する場合のみ revert 伝播 | fork（台帳定義） | ☐ | ☐ | | 未実施 | AAVE-TBD-008 解決を反映 |
| AAVE-ERR-003 | Aave 完全停止時の緊急回収不能（縮退・runbook） | manual / fork（台帳定義） | ☐ | ☐ | | 未実施 | |
| AAVE-ERR-004 | aToken 評価の前提崩れ | manual / fork（台帳定義） | ☐ | ☐ | | 未実施 | |
| AAVE-ERR-005 | 報酬トークン取りこぼし（Merkl + Aave RewardsController claim 実装、swap / 非 Underlying backing 補填は未対応） | manual（台帳定義） | ☐ | ☐ | | 未実施 | AAVE-FR-007 / AAVE-TBD-005 関連 |

### 9.7 未決事項レジスタ（AAVE-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| AAVE-TBD-001 | 未決 | safeApprove(max) 方針の最終確認 → 確定まで AAVE-FR-001 の approve 検証は現行仕様で実施 | |
| AAVE-TBD-002 | 未決 | referralCode 確定値（現状 0） | |
| AAVE-TBD-003 | 未決 | aToken 換算の追加保守補正の要否 | |
| AAVE-TBD-004 | 未決 | EmergencyAaveWithdrawn イベント追加の要否 → AAVE-EVT-002 行に連動 | |
| AAVE-TBD-005 | Scoped | Merkl は BaseStrategy.claimMerklRewards、Aave RewardsController は claimAaveRewards で解決。reward swap / 非 Underlying backing 補填は未決 | |
| AAVE-TBD-006 | Resolved（欠番扱い） | initialize の aToken underlying 整合チェックは実装済（AAVE-FR-001 / AAVE-SEC-004 行で検証）。ID は欠番として再利用しない | |
| AAVE-TBD-007 | 未決 | mainnet / Sepolia の Pool・aToken 確定アドレス → deploy 構成検査のゲート | |
| AAVE-TBD-008 | Resolved（2026-06-16） | reserve 流動性に基づく withdraw cap は実装済み。一時的流動性不足では revert せず partial / 0 を返し、valuation は現在流動性で cap しない | STGY-TBD-002 / AAVE-FR-004 と同根 |

---

## 9A. ERC4626Strategy.md（E4626）

正本: [ERC4626Strategy.md](../../protocol/product/spec/strategies/ERC4626Strategy.md)。対象: `ERC4626Strategy.sol`（汎用 ERC-4626 adapter・`BaseStrategy` 継承・UUPS）。FR / INV / GOV / EVT / ERR / TBD は共通 Strategy 仕様（§8 STGY）を継承し、本書固有の ID は ERC-4626 固有のセキュリティ要件（E4626-SEC）8 件のみ。AaveV3（§9）と同じく concrete Strategy であり、後追い追加のため既存番号を保つ §9A として挿入する。fork 検証は実 ERC-4626 vault（Morpho Vault / EulerEarn / sUSDS 等）。

### 9A.1 セキュリティ要件（E4626-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| E4626-SEC-001 | `initialize` は `erc4626Vault.asset() == underlying` を検証し mismatch を拒否 | unit | ☑ | ☑ | `test_Initialize_RevertsOnERC4626AssetMismatch` | PASS(V9) | |
| E4626-SEC-002 | share token donation は `estimatedTotalUnderlying()` / `realizedYield()` を増やさない | unit | ☑ | ☑ | `test_ShareDonationDoesNotInflateRealizedYield` | PASS(V9) | |
| E4626-SEC-003 | ERC-4626 share token は position token であり `sweepRewardToken` で Treasury へ送れない | unit | ☑ | ☑ | `test_SweepRewardToken_RejectsERC4626ShareToken` | PASS(V9) | |
| E4626-SEC-004 | `deposit()` が 0 shares を返す場合は隔離した外部運用 call frame を `ERC4626ZeroShares` で revert し、Underlying の完全回収後に当該 allocation を skip | unit | ☑ | ☑ | `test_Allocate_RecoversAndSkipsWhenERC4626MintsZeroShares` | PASS(V9 + Low-01) | |
| E4626-SEC-005 | ERC-4626 側の asset loss は `estimatedTotalUnderlying()` と Vault `totalUnderlying()` に下方反映 | unit | ☑ | ☑ | `test_AssetLossReflectedInEstimateAndVaultTotal` | PASS(V9) | |
| E4626-SEC-006 | 緊急回収は redeem 後の Underlying を同一 tx で Vault へ push し `backingRatio()` の一時的過小評価 window を作らない | unit | ☑ | ☑ | `test_EmergencyWithdrawFromERC4626_DoesNotTransientlyDiscountBacking`; `test_EmergencyWithdrawFromERC4626_PartialRecoveryAccountsReturnedPrincipal` | PASS(V9) | |
| E4626-SEC-007 | `deposit` / `withdraw` / `redeem` は share balance before/after と ERC-4626 返り値を照合し、通常 withdraw / emergency redeem は Underlying 実増分も照合する。deposit 不一致は隔離 call frame を revert し完全回収時のみ skip、withdraw 不一致は revert | unit | ☑ | ☑ | `test_Allocate_RecoversAndSkipsWhenERC4626ReturnDoesNotMatchShareDelta`; `test_SendToVault_RevertsWhenERC4626WithdrawReturnDoesNotMatchShareDelta`; `test_SendToVault_RevertsWhenERC4626WithdrawBurnsZeroShares`; `test_SendToVault_RevertsWhenERC4626WithdrawAssetDeltaMismatch`; `test_EmergencyWithdrawFromERC4626_RevertsWhenRedeemAssetDeltaMismatch` | PASS(V9 + Low-01) | |
| E4626-SEC-008 | Merkl / 外部 reward claim は非 Underlying・非 ERC-4626 share token の reward のみ許可し、claim 後は Treasury へ sweep。claim / sweep は `principal`、`estimatedTotalUnderlying()`、Vault buffer を変更しない | unit | ☑ | ☑ | `test_ClaimMerklRewards_SweepsERC4626RewardToTreasuryWithoutAccountingImpact`; `test_ClaimMerklRewards_RejectsERC4626ShareTokenBeforeDistributorCall` | PASS(V9) | |

---

## 9B. LidoStrategy.md（LIDO・Archived）

> **Archived / active 合計から除外。**`LidoStrategy` は 2026-08-06 に Solidity source
>（`contracts/src/Strategies/archive/`）および test（`contracts/test/archive/`）とともに
> archived となった。本 Strategy の underlying は構造的に WETH であり（`initialize` が `IWETH _weth` を
> 受け取り、deposit 経路は WETH を native ETH へ unwrap する）、非 WETH underlying を拒否していた
> deploy selector は PR #1424 で削除済み。branch 0 の underlying も WETH → wstETH へ移行したため、
> WETH underlying を供給できる branch は存在しない。
> 本 surface は **2026-08-05 完了の外部監査**（監査対象 identity `0c7766e0`）の対象に含まれて
> いたため、カバレッジの追跡可能性を保つ目的で以下の行を残す。ただし `LIDO-*` は
> **凍結された履歴 ID** であり、現行実装・監査の active 要件ではなく、再利用も active な監査
> スコープとしての参照も禁止する。これは省略ではなく明示的な除外である。再有効化には新規
> activation package と audit-scope 変更が必要。

正本: [LidoStrategy.md](../../archive/LidoStrategy.md)。対象: `contracts/src/Strategies/archive/LidoStrategy.sol`（WETH→ETH→stETH→wstETH、Withdrawal Queue による非同期回収）。共通 Strategy 要件（§8 STGY）を継承し、Lido 固有の async / pending / wstETH 会計を本節で追跡する。

> **退役・archive（2026-08-05）**: `LidoStrategy` は WETH → wstETH branch swap に伴い Day-1 deploy surface から退役し、source / spec は削除せず archive（監査済み成果物・active scope 外）へ退避する。退役・非 activation gate `LIDO-GOV-001` 以外の全行を `N/A(退役)` とする。ID は archive 済み成果物に対する監査 traceability のため保持する。

### 9B.1 機能要件（LIDO-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LIDO-FR-001 | initialize（投資先固定・upgrader 引数・wstETH/stETH 整合・Queue bounds・approve・ゼロ/多重 revert） | unit | N/A | N/A | | N/A(退役) | |
| LIDO-FR-002 | addStrategy 前提（whitelist→addStrategy・Underlying=WETH 一致・isAsync 非通知） | integration, manual | N/A | N/A | | N/A(退役) | |
| LIDO-FR-003 | _doDeposit（WETH→ETH→submit→wrap・wstETH 実残高差分計上・donation 非混入） | unit, fork, invariant=LIDO-INV-001 | N/A | N/A | | N/A(退役) | |
| LIDO-FR-004 | _doWithdraw（claim 済み idle WETH のみ返却・stETH 不接触） | unit, integration | N/A | N/A | | N/A(退役) | |
| LIDO-FR-005 | _estimatedTotalUnderlying（min・pending 算入・donation 排除・idle ETH 非算入） | unit, fork, invariant=LIDO-INV-002/005 | N/A | N/A | | N/A(退役) | |
| LIDO-FR-006 | requestLidoWithdrawal（ALLOCATOR・MIN/MAX 分割・自己保有上限・pending 記帳・wstETH 減算） | unit, fork, invariant=LIDO-INV-005 | N/A | N/A | | N/A(退役) | |
| LIDO-FR-007 | claimLidoWithdrawals（finalized claim・pending 減算・ETH→WETH idle 化・未知/二重 claim 拒否・hint batch） | unit, fork, invariant=LIDO-INV-005 | N/A | N/A | | N/A(退役) | |
| LIDO-FR-008 | emergencyWithdrawFromLido（onlyOwner・idle atomic push・残 wstETH 要求・即時全回収を約束しない） | unit, fork | N/A | N/A | | N/A(退役) | |
| LIDO-FR-009 | setReferral（onlyOwner・次回 submit 反映） | unit | N/A | N/A | | N/A(退役) | |

### 9B.2 不変条件（LIDO-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LIDO-INV-001 | `_ownWstETH` は自関数のみで増減し、第三者 stETH / wstETH donation では増えない | invariant | N/A | N/A | | N/A(退役) | |
| LIDO-INV-002 | 評価は `getStETHByWstETH(min(_ownWstETH, balance)) + pending + idle WETH`、donation 排除・slashing 反映・生 ETH 非算入 | invariant / fork | N/A | N/A | | N/A(退役) | |
| LIDO-INV-003 | lido / stETH / wstETH / withdrawalQueue / weth は initialize 後不変 | invariant | N/A | N/A | | N/A(退役) | |
| LIDO-INV-004 | _doWithdraw は idle WETH 残高を超えて返さず、同期 unstake しない | unit | N/A | N/A | | N/A(退役) | |
| LIDO-INV-005 | pendingWithdrawAmount は未 claim requestId の記録額合計と一致し、二重 claim しない | invariant | N/A | N/A | | N/A(退役) | |
| LIDO-INV-006 | request / claim は principal を変えず、principal 減算は Vault 実受領額ベースのみ | invariant | N/A | N/A | | N/A(退役) | |
| LIDO-INV-007 | sweepRewardToken は WETH / stETH / wstETH / unstETH を拒否する | unit | N/A | N/A | | N/A(退役) | |
| LIDO-INV-008 | underlying() は WETH 不変で、対応 Vault の Underlying と一致する | invariant | N/A | N/A | | N/A(退役) | |
| LIDO-INV-009 | wstETH.stETH() は lido と一致し、Withdrawal Queue bounds は初期化済み venue である | unit / manual | N/A | N/A | | N/A(退役) | |
| LIDO-INV-010 | `_ownIdleUnderlying` は Lido claim 由来のみで増え donation で増えず、stale 枠が後続 donation で再充填されない | unit / invariant | N/A | N/A | | N/A(退役) | **V1 追加（メタ監査・spec §8）**。台帳 §9B.2 に欠落していた行。検証記録（PASS・テスト実体）は V1 マッピング [LIDO.md §9B.2](../historical-reviews/2026-06-20-V1-mapping/LIDO.md) に記載 |

### 9B.3 セキュリティ要件（LIDO-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LIDO-SEC-001 | 投資先アドレスの initialize 時固定・setter 不在 | invariant=LIDO-INV-003, manual | N/A | N/A | | N/A(退役) | |
| LIDO-SEC-002 | donation / rebase による AUM 水増し排除 | invariant=LIDO-INV-001/002, fork | N/A | N/A | | N/A(退役) | |
| LIDO-SEC-003 | 緊急回収の宛先固定と権限分離 | unit | N/A | N/A | | N/A(退役) | |
| LIDO-SEC-004 | 非同期 keeper の権限と griefing 耐性 | unit | N/A | N/A | | N/A(退役) | |
| LIDO-SEC-005 | finalization 前 claim の拒否 | unit, fork | N/A | N/A | | N/A(退役) | |
| LIDO-SEC-006 | stETH / wstETH の 1-wei 丸め・会計の安全側処理 | unit | N/A | N/A | | N/A(退役) | |
| LIDO-SEC-007 | stETH / unstETH / WETH の reward sweep 禁止 | unit | N/A | N/A | | N/A(退役) | |
| LIDO-SEC-008 | venue 誤配線と wstETH 返り値不整合の fail-fast | unit, manual | N/A | N/A | | N/A(退役) | |

### 9B.4 ガバナンス・運用・アップグレード要件（LIDO-GOV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LIDO-GOV-001 | 非 activation / deploy surface ゲート（source / test残置・公式deploy wiring除外・generic unknown-kind fallback・既存instance回収） | manual, unit | ☐ | N/A | | 未実施 | |
| LIDO-GOV-002 | 非同期 keeper の運用 runbook | manual | N/A | N/A | | N/A(退役) | |
| LIDO-GOV-003 | 異常時の新規割当停止と緊急回収 | manual, integration | N/A | N/A | | N/A(退役) | |

### 9B.5 イベント・監視要件（LIDO-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LIDO-EVT-001 | ReferralUpdated(referral) | unit | N/A | N/A | | N/A(退役) | |
| LIDO-EVT-002 | WithdrawRequested(requestIds, stETHAmount) | unit | N/A | N/A | | N/A(退役) | |
| LIDO-EVT-003 | WithdrawClaimed(requestIds, ethReceived) | unit | N/A | N/A | | N/A(退役) | |
| LIDO-EVT-004 | OwnWstETHUpdated(ownWstETH) | unit | N/A | N/A | | N/A(退役) | |
| LIDO-EVT-005 | OwnIdleUnderlyingUpdated(ownIdleUnderlying) | unit | N/A | N/A | | N/A(退役) | **V1 追加（メタ監査・spec §11）**。台帳 §9B.5 に欠落していた行。検証記録（部分PASS・expectEmit GAP）は V1 マッピング [LIDO.md §9B.5](../historical-reviews/2026-06-20-V1-mapping/LIDO.md) に記載 |

### 9B.6 失敗時・異常系挙動（LIDO-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LIDO-ERR-001 | finalization 遅延・早期 claim 不可 | unit, fork, manual | N/A | N/A | | N/A(退役) | |
| LIDO-ERR-002 | MIN/MAX_STETH_WITHDRAWAL_AMOUNT による要求制約 | unit, fork | N/A | N/A | | N/A(退役) | |
| LIDO-ERR-003 | stETH slashing・元本毀損 | fork, manual | N/A | N/A | | N/A(退役) | |
| LIDO-ERR-004 | Lido / Withdrawal Queue 停止時の緊急回収限界 | fork, manual | N/A | N/A | | N/A(退役) | |
| LIDO-ERR-005 | stETH 二次市場デペグ（withdraw レートとの独立） | manual | N/A | N/A | | N/A(退役) | |

### 9B.7 未決事項レジスタ（LIDO-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| LIDO-TBD-001 | Resolved（2026-06-16） | request は ALLOCATOR 限定、claim は permissionless | LIDO-FR-006 / LIDO-FR-007 |
| LIDO-TBD-002 | 未決 | referral の確定値 | LIDO-FR-009 / LIDO-FR-003 |
| LIDO-TBD-003 | 解決済み（2026-06-17 実装） | `_ownIdleUnderlying` は Lido claim 由来のみ。直接 WETH / raw ETH donation は AUM・yield・Lido 固有 emergency principal return に混入しない | LIDO-FR-005 / LIDO-SEC-002 / LIDO-INV-010 |
| LIDO-TBD-004 | Resolved（2026-06-14） | hint なし overload は単一 request、複数は hint 付き batch claim | LIDO-FR-007 |
| LIDO-TBD-005 | Resolved | wstETH（非 rebasing）を採用 | Strategy 内部に閉じる |
| LIDO-TBD-006 | Resolved（2026-06-18） | Product / Strategy の Lido 表記を現行実装（stETH・wstETH + Withdrawal Queue）へ統一 | Product-Overview / LidoStrategy |
| LIDO-TBD-007 | 解決済み | WETH underlying branch の現行値、venue 採用状態、非 activation / deploy surface gate は各正本へ移管済み | Parameters / Mainnet Deploy Env Freeze Runbook・生成Manifest / Strategy Selection Policy / LIDO-GOV-001 |

---

## 9C. SkyUsdcSUsdsStrategy.md（SKY）

正本: [SkySUsdsStrategy.md](../../protocol/product/spec/strategies/SkySUsdsStrategy.md)。対象:
`SkyUsdcSUsdsStrategy.sol`、`SkyUsdcSUsdsConverter.sol` と共有 `ISkyUsdcSUsdsConverter` 境界。共通 Strategy 要件（§8 STGY）を継承し、dUSDC branch の `USDC -> USDS -> sUSDS -> USDC` 運用を本節で追跡する。

### 9C.1 セキュリティ要件（SKY-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SKY-SEC-001 | USDC / USDS / sUSDS decimals と `susdsVault.asset()` を初期化時に検証 | unit | ☑ | ☑ | `test_Initialize_RevertsWhenUnderlyingDecimalsAreNotUsdc` | PASS(V1) | asset 検証は initialize path review |
| SKY-SEC-002 | converter / sUSDS vault allowance は per-call approve/reset | unit / manual | ☑ | N/A | `test_Allocate_ConvertsUsdcToSUsdsAndValuesInUsdc`; code review | PASS(V1) | 恒久承認は BaseStrategy の Vault 向け USDC のみ |
| SKY-SEC-003 | sUSDS share donation は valuation / realizedYield を増やさない | unit | ☑ | ☑ | `test_DonatedSUsdsSharesDoNotInflateValuation` | PASS(V1) | `_ownSUsdsShares` のみ評価 |
| SKY-SEC-004 | USDS / sUSDS は protected token で sweep 不可 | unit | ☑ | ☑ | `test_SweepRejectsUsdsAndSUsds` | PASS(V1) | |
| SKY-SEC-005 | converter / sUSDS vault 返り値と実残高差分を照合 | unit / manual | ☑ | ☑ | `test_Allocate_ConvertsUsdcToSUsdsAndValuesInUsdc`; code review | PASS(V1) | mismatch revert path は code review |
| SKY-SEC-006 | USDC 回収時は `maxConversionLossBps` 下限を下回ったら revert | unit / manual | ☑ | ☑ | `test_SendToVault_RedeemsSUsdsAndReturnsUsdc`; `test_EmergencyConvertCannotBypassMaxConversionLoss`; `test_EmergencyWithdrawCannotBypassMaxConversionLoss`; code review | PASS(V7) | emergency minUsdcOut は下限を緩和できない。fork route halt は別途 mainnet dry-run |
| SKY-SEC-007 | valuation は converter preview と 1:1 換算の小さい方を使う | unit | ☑ | ☑ | `test_Allocate_ConvertsUsdcToSUsdsAndValuesInUsdc`; `test_DonatedSUsdsSharesDoNotInflateValuation` | PASS(V1) | |
| SKY-SEC-008 | 非ゼロ USDS の変換が 0 USDC 実受領になる場合は revert し、tracked idle USDS を silent に減らさない | unit | ☑ | ☑ | `test_EmergencyConvertRevertsWhenUsdsDustWouldReturnZeroUsdc` | PASS(V9) | USDC base unit 未満の USDS dust は `_ownIdleUsds` として維持し、追加回収や累積後に変換する |
| SKY-SEC-009 | converter token identity を route と一致させ、deploy script が監査済み concrete adapter を生成する | unit / integration | ☑ | ☑ | `test_ConstructorBindsWrapperTokens`; `test_MainnetFork_BindsCanonicalSkyWrapperAndTokens`; `test_MainnetFork_ExecutesRoundTripWhenRoutesAreActive`; `test_DeploySelector_DeploysSkyUsdcSUsdsStrategy` | PASS(V12) | `MAINNET_RPC_URL` 付き fork で公式 wrapper identity と実 round-trip を確認 |
| SKY-SEC-010 | `tout` 込みUSDS予算、未使用refund、実消費量だけのidle減算 | unit | ☑ | ☑ | `test_ConvertUsdsToUsdc_UsesBudgetAndRefundsUnspentDust`; `test_PreviewUsdsToUsdc_AccountsForFeeFloorAtOneUsdcAtom`; `test_EmergencyConvertTracksActualUsdsSpentWhenConverterUsesBudget` | PASS(V12) | 6 decimals USDCへ変換できない残余をadapterに残さない |
| SKY-SEC-011 | 明示的な route halt は principal-capped 1:1 valuation を継続し、invalid fee / status read / その他の quote failure は fresh cache 後に unavailable | unit / integration | ☑ | ☑ | `test_RouteHaltStatusDistinguishesExplicitHaltFromInvalidFee`; `test_PricingRemainsAvailablePastCacheWhileSkyRouteHalted`; `test_HaltedRouteValuationDoesNotRecognizeUnrealizedYield`; `test_PriceFeedDoesNotShutDownBranchAfterHaltedRouteCacheExpires`; `test_PricingUsesFreshCacheWhenSkyQuoteUnavailable` | PASS(PRELIM-M02) | conversion / preview の halt revert は維持。未知の障害を halt と推測せず、明示的 halt だけが保守的 live valuation を使う |

## 9D. EtherfiWeETHStrategy.md（EFWEETH・Archived）

> **Archived / active 合計から除外。**`EtherfiWeETHStrategy` / `WeETHWithdrawAdapter` は 2026-08-06 に Solidity source
>（`contracts/src/Strategies/archive/`）および test（`contracts/test/archive/`）とともに
> archived となった。本 Strategy の underlying は構造的に WETH であり（`initialize` が `IWETH _weth` を
> 受け取り、deposit 経路は WETH を native ETH へ unwrap する）、非 WETH underlying を拒否していた
> deploy selector は PR #1424 で削除済み。branch 0 の underlying も WETH → wstETH へ移行したため、
> WETH underlying を供給できる branch は存在しない。
> 本 surface は **2026-08-05 完了の外部監査**（監査対象 identity `0c7766e0`）の対象に含まれて
> いたため、カバレッジの追跡可能性を保つ目的で以下の行を残す。ただし `EFWEETH-*` は
> **凍結された履歴 ID** であり、現行実装・監査の active 要件ではなく、再利用も active な監査
> スコープとしての参照も禁止する。これは省略ではなく明示的な除外である。再有効化には新規
> activation package と audit-scope 変更が必要。

正本: [EtherfiWeETHStrategy.md](../../archive/EtherfiWeETHStrategy.md)。対象:
`contracts/src/Strategies/archive/EtherfiWeETHStrategy.sol` と Ether.fi LiquidityPool / weETH / WithdrawAdapter / WithdrawRequestNFT 境界。共通 Strategy 要件（§8 STGY）を継承し、dETH branch の WETH -> eETH/weETH と非同期回収を本節で追跡する。

### 9D.1 セキュリティ要件（EFWEETH-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| EFWEETH-SEC-001 | WETH branch 以外に登録しない。deploy selector は WETH underlying を要求 | unit / integration | ☑ | ☑ | `test_DeploySelector_DeploysEtherfiWeETHStrategyForWethBranch`; code review | PASS(V1) | non-WETH revert path は deploy script review |
| EFWEETH-SEC-002 | weETH donation は valuation / realizedYield を増やさない | unit | ☑ | ☑ | `test_DonatedWeETHDoesNotInflateValuation` | PASS(V1) | `_ownWeETH` のみ評価 |
| EFWEETH-SEC-003 | eETH / weETH / WithdrawRequestNFT は protected asset で sweep 不可 | unit | ☑ | ☑ | `test_SweepRewardToken_RejectsPositionTokens` | PASS(V1) | |
| EFWEETH-SEC-004 | `onERC721Received` は設定済み `withdrawRequestNFT` からだけ受け付ける | unit / manual | ☑ | ☑ | `test_RequestClaimAndSendToVault_ReturnsClaimedWeth`; code review | PASS(V1) | unexpected NFT revert path は code review |
| EFWEETH-SEC-005 | pending request は requestId map で追跡し、未知 request claim を拒否 | unit | ☑ | ☑ | `test_RequestClaimAndSendToVault_ReturnsClaimedWeth` | PASS(V1) | unknown request revert path は code review |
| EFWEETH-SEC-006 | `_doWithdraw` は claim 済み idle WETH だけを返す | unit | ☑ | ☑ | `test_RequestClaimAndSendToVault_ReturnsClaimedWeth`; `test_ClaimUsesActualEthReceivedWhenEtherfiReturnsLessThanPending` | PASS(V1/V2) | claim 前 `sendToVault` は 0。実受領額が pending を下回る場合も実受領額だけを返す |
| EFWEETH-SEC-007 | 初期化時に `weETH` / `WithdrawRequestNFT` / `liquidityPool.withdrawRequestNFT()` / `withdrawAdapter` が設定済み `eETH` / `liquidityPool` / `weETH` / `withdrawRequestNFT` graph を参照し、`withdrawAdapter` が DF 固有 identity marker を返すことを検証する | unit | ☑ | ☑ | `test_Initialize_RevertsOnMismatchedWeETHEETH`; `test_Initialize_RevertsOnMismatchedWeETHLiquidityPool`; `test_Initialize_RevertsOnMismatchedWithdrawRequestNFTEETH`; `test_Initialize_RevertsOnMismatchedWithdrawRequestNFTLiquidityPool`; `test_Initialize_RevertsOnMismatchedLiquidityPoolWithdrawRequestNFT`; `test_Initialize_RevertsOnMismatchedAdapterLiquidityPool`; `test_Initialize_RevertsOnMismatchedAdapterEETH`; `test_Initialize_RevertsOnMismatchedAdapterWeETH`; `test_Initialize_RevertsOnMismatchedAdapterWithdrawRequestNFT`; `test_Initialize_RevertsWhenAdapterDoesNotExposeDfIdentity` | PASS(V2/V10/V11) | Aave aToken / ERC4626 asset / Lido stETH link と同じ venue graph consistency check。V10 で LiquidityPool reverse edge と approve 前 adapter binding 検証を追加し、V11 で marker-less ABI-compatible adapter 拒否を追加 |
| EFWEETH-SEC-008 | `withdrawAdapter.requestWithdraw` が返した requestId は Strategy 自身が owner でなければ pending 会計に入れない | unit | ☑ | ☑ | `test_RequestEtherfiWithdrawal_RevertsWhenAdapterDoesNotMintRequestToStrategy` | PASS(V8) | misrouting adapter が第三者に NFT を mint するケース |
| EFWEETH-SEC-009 | permissionless claim の requestIds 配列は 1 tx 32 件上限 | unit | ☑ | ☑ | `test_ClaimEtherfiWithdrawals_RevertsWhenBatchTooLarge` | PASS(V8) | pending map に触れる前に revert |
| EFWEETH-SEC-010 | pending valuation は `WRITEOFF_ROLE` 限定 bps で保守調整。下方変更は `pausedAllocation == true` 必須 | unit | ☑ | ☑ | `test_SetPendingWithdrawalValuationBps_DiscountsAndRoundsEtherfiPendingValue`; `test_SetPendingWithdrawalValuationBps_RevertsAboveDenominator`; `test_SetPendingWithdrawalValuationBps_RequiresWriteoffRole`; `test_SetPendingWithdrawalValuationBps_RevertsDiscountBeforeAllocationPause` | PASS(V8) | 0〜10000、切り捨て、pause guard |
| EFWEETH-SEC-011 | 未 claim async request は総数 128 件上限 | unit | ☑ | ☑ | `test_RequestEtherfiWithdrawal_RevertsWhenPendingRequestLimitReached` | PASS(V8) | storage 増大と pending request 取得不能化を防ぐ |
| EFWEETH-SEC-012 | raw ETH donation は claim delta / idle WETH / yield / valuation に混入しない | unit | ☑ | ☑ | `test_RawEthDonationBeforeClaimDoesNotInflateIdleOrYield` | PASS(V8) | claim 前 balance を基準に差分だけ wrap |
| EFWEETH-SEC-013 | 非ゼロ eETH request が 0 weETH に floor される場合は 1 wei weETH に切り上げ、pending は NFT request data の実 net eETH で記録 | unit | ☑ | ☑ | `test_RequestEtherfiWithdrawal_RoundsTinyEETHRequestUpToOneWeETHAtom` | PASS(V9) | dust weETH 固定化を避けつつ、`_ownWeETH` 減少と `pendingWithdrawAmount` の valuation 整合を確認 |
| EFWEETH-SEC-014 | `WeETHWithdrawAdapter` は DeltaForesight first-party adapter として DF 固有 identity marker、immutable venue graph、LiquidityPool reverse binding、weETH / eETH balance-delta と residual-balance、NFT owner を検証し、admin / upgrade / rescue surface を持たない | unit / manual | ☑ | ☑ | `test_WeETHWithdrawAdapter_UnwrapsWeETHAndRequestsNativeEtherfiWithdrawal`; `test_WeETHWithdrawAdapter_RevertsOnMismatchedWeETHEETH`; `test_WeETHWithdrawAdapter_RevertsOnMismatchedLiquidityPoolWithdrawRequestNFT`; `test_WeETHWithdrawAdapter_RevertsOnZeroRequest`; `test_WeETHWithdrawAdapter_RevertsWhenUnwrapLeavesResidualWeETH`; `test_WeETHWithdrawAdapter_RevertsWhenPoolLeavesResidualEETH`; `test_WeETHWithdrawAdapter_DonationBaselineDoesNotAffectResidualChecks`; `test_Initialize_RevertsWhenAdapterDoesNotExposeDfIdentity`; code review | PASS(V10/V11) | adapter は Ether.fi 公式 contract ではなく、weETH -> eETH -> `LiquidityPool.requestWithdraw` の薄い変換境界。V11 で DF marker を追加し、同名または ABI 互換の外部 adapter との差別化を初期化時に検証 |

## 9E. MorphoV2Strategy.md（MV2）

正本: [MorphoV2Strategy.md](../../protocol/product/spec/strategies/MorphoV2Strategy.md)。対象: `MorphoV2Strategy.sol`（Morpho Vaults V2 専用 adapter・`BaseStrategy` 継承・UUPS。kind `morpho-v2`・Day-1 は branch 1 dUSDC）。Strategy 共通要件（§8 STGY）を継承する。§9A ERC4626 と異なり max\* view を一切参照しないため、isolated-frame fail-soft モデル、`forceDeallocate` wrapper、緊急 `maxShares` 段階回収について独自の FR / SEC / INV 行を持つ。

### 9E.1 機能要件（MV2-FR）

| ID | 要件（要約） | 指定検証方法 | 正常系 | 異常系 | Test artifact | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MV2-FR-001 | `initialize` は zero / 非 contract vault、`asset()` mismatch（`InvalidMorphoVaultAsset`）、200 bps 超の penalty bound（`ForceDeallocatePenaltyAboveMax`）を拒否。上限は init 凍結・setter なし | unit | ☑ | ☑ | `test_Initialize_RevertsOnMorphoVaultAssetMismatch`; `test_Initialize_RevertsOnNonContractMorphoVault`; `test_Initialize_RevertsOnPenaltyBoundAboveProtocolMax` | PASS(V13) | |
| MV2-FR-002 | isolated-frame deposit。venue 拒否（cap / receive gate / zero-share / 嘘の返り値）は `MorphoV2DepositRejected` として再送出され、BaseStrategy が受領額をそのまま回収して skip（Low-01）。hard-zero max\* view 下でも動作 | unit | ☑ | ☑ | `test_AllocateAndSendToVault_WorkDespiteHardZeroMaxViews`; `test_Allocate_RecoversWhenLiquidityAdapterCapHit`; `test_Allocate_RecoversWhenReceiveGateCloses`; `test_Allocate_RecoversAndSkipsWhenMorphoVaultMintsZeroShares`; `test_Allocate_RecoversAndSkipsWhenMorphoDepositReturnDoesNotMatchShareDelta` | PASS(V13) | |
| MV2-FR-003 | `_doWithdraw` は `min(_ownShares, shareBalance)` の評価額に clamp し、全額失敗後は半減して合計8回まで bounded partial retry。最初の成功額を返し全失敗時だけ 0（ADR-006）。成功時は実 burn shares を減算 | unit | ☑ | ☑ | `test_SendToVault_RetriesSmallerAmountWhenRequestedLiquidityIsShort`; `test_SendToVault_ReturnsZeroFailSoftWhenLiquidityShort`; `test_SendToVault_ReturnsZeroFailSoftWhenSendGateCloses`; `test_SendProfitToVault_HarvestsSharePriceYieldWithoutReducingPrincipal` | PASS(V20) | |
| MV2-FR-004 | `emergencyWithdrawFromMorphoV2(maxShares)` の段階回収: `min(shareBalance, maxShares)`（donated shares 含む）・redeem delta 検証・同一 tx Vault push・returned principal 記帳。残余は `writeoffStrategyPrincipal` へ | unit | ☑ | ☑ | `test_EmergencyWithdrawFromMorphoV2_FullDrainPushesToVaultSameTx`; `test_EmergencyWithdrawFromMorphoV2_PartialRecoveryViaMaxSharesAccountsReturnedPrincipal`; `test_EmergencyWithdrawFromMorphoV2_RecoversDonatedSharesAfterFullUnwind`; `test_EmergencyWithdrawFromMorphoV2_RevertsWhenRedeemAssetDeltaMismatch` | PASS(V13) | |
| MV2-FR-005 | Vault-only wrapper。WRITEOFF_ROLE の入口で penalty・引出し・Vault 着金を一括実行し、最低実受領額と backing 下限で全体を保護する。 | unit | ☑ | ☑ | `test_GuardianL05_RecoveryIsAtomicAcrossSeparatedRoles`; `testFuzz_GuardianL05_InsufficientReceiptRollsBackEverything`; `test_GuardianL05_AtomicRecoveryRetainsStrategyReentrancyGuard`; `MorphoV2StrategyTest` | PASS (2026-09-17) | 169 Morpho/Vault tests; 256 fuzz cases |

### 9E.2 セキュリティ要件（MV2-SEC）

| ID | 要件（要約） | 指定検証方法 | 正常系 | 異常系 | Test artifact | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MV2-SEC-001 | share token donation は `estimatedTotalUnderlying()` / `realizedYield()` を増やさない | unit | ☑ | ☑ | `test_ShareDonationDoesNotInflateRealizedYield` | PASS(V13) | |
| MV2-SEC-002 | isolated frame は self-only。venue deposit / withdraw 中の reentry は `nonReentrantStrategy` で遮断 | unit | ☑ | ☑ | `test_DepositIntoMorphoVault_SelfOnly`; `test_WithdrawFromMorphoVault_SelfOnly`; `test_Reentrancy_DuringVenueDepositIsBlocked`; `test_Reentrancy_DuringVenueWithdrawIsBlocked` | PASS(V13) | |
| MV2-SEC-003 | hostile venue delta check: share 残高 before/after と返り値 minted / burned、withdraw / 緊急 redeem では Underlying 実増分も照合。不一致は frame 内 revert（deposit → recovered skip・withdraw → fail-soft 0・緊急 → revert） | unit | ☑ | ☑ | `test_Allocate_RecoversAndSkipsWhenMorphoDepositReturnDoesNotMatchShareDelta`; `test_Allocate_RecoversAndSkipsWhenMorphoVaultMintsZeroShares`; `test_SendToVault_ReturnsZeroFailSoftWhenWithdrawReturnDoesNotMatchShareDelta`; `test_SendToVault_ReturnsZeroFailSoftWhenWithdrawBurnsZeroShares`; `test_EmergencyWithdrawFromMorphoV2_RevertsWhenRedeemAssetDeltaMismatch` | PASS(V13) | |
| MV2-SEC-004 | penalty 上限は `assets * maxBps / 10000 + 1` wei で fail-closed。venue の切り上げと `convertToAssets` の切り捨てにより上限ちょうどの venue では超過 revert しうる。operator の対処は `assets` を小さくして再試行 | unit | ☑ | ☑ | `test_ForceDeallocate_RevertsWhenPenaltyExceedsBound` | PASS(V13) | +1 wei boundary は意図的: 凍結上限超の penalty を受容しない |
| MV2-SEC-005 | deploy は 4 gate 全て unset の vault に限定。後から設置された gate は recovered deposit rejection または fail-soft withdraw として現れ、資金滞留にならない | unit + venue freeze evidence | ☑ | ☑ | `test_Allocate_RecoversWhenReceiveGateCloses`; `test_SendToVault_ReturnsZeroFailSoftWhenSendGateCloses` | PASS(V13) | gates-unset の venue readback は activation package evidence（freeze package §4a）であり本 campaign の対象外 |
| MV2-SEC-006 | Morpho vault share token は position token であり Treasury へ sweep できない | unit | ☑ | ☑ | `test_SweepRewardToken_RejectsMorphoShareToken` | PASS(V13) | |
| MV2-SEC-007 | venue 側 asset loss は `estimatedTotalUnderlying()` と Vault `totalUnderlying()` に即時下方反映。`maxRate` は利益側のみ cap（maxRate=0 は yield 留保・監視項目） | unit | ☑ | ☑ | `test_AssetLossReflectedImmediatelyInEstimateAndVaultTotal` | PASS(V13) | |

### 9E.3 不変条件（MV2-INV）

| ID | 要件（要約） | 指定検証方法 | 正常系 | 異常系 | Test artifact | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MV2-INV-001 | 評価 / withdraw 基準は `min(_ownShares, balanceOf(this))`。`_ownShares` は自身の deposit / withdraw / 緊急 / penalty 経路でのみ変化、0 で floor、変化ごとに `OwnSharesUpdated` を emit | unit | ☑ | ☑ | `test_ShareDonationDoesNotInflateRealizedYield`; `test_EmergencyWithdrawFromMorphoV2_PartialRecoveryViaMaxSharesAccountsReturnedPrincipal`; `test_ForceDeallocate_WithinBoundResyncsOwnSharesAndDropsValuation`; `test_Max32MorphoV2StrategiesBackingRatioStaysWithinBoundedGas` | PASS(V13) | backing-ratio test は 32 Strategy 時の view gas 上限も確認 |
| MV2-INV-002 | venue withdraw / redeem から届くのは Underlying のみ（in-kind redemption なし）。vault share 以外の venue token を保持せず、reward は継承 BaseStrategy 経路の Merkl のみ | unit / code review | ☑ | N/A | `test_SweepRewardToken_RejectsMorphoShareToken`; code review | PASS(V13) | N/A: in-kind 経路が存在しないため異常系なし |
| MV2-INV-003 | 派生 contract はちょうど 50 storage slot（state 3 + `uint256[47]` gap）を確保 | code review | ☑ | N/A | code review（`MorphoV2Strategy.sol` state layout） | PASS(V13) | N/A: layout レビュー項目 |

---

## 10. Oracle.md（ORCL）

正本: [Oracle.md](../../protocol/product/spec/Oracle.md)。対象: `PriceFeedProxy` / DF PriceFeed 実装（Standard / Peg-monitored / Composite rate / Placeholder）。

### 10.1 機能要件（ORCL-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ORCL-FR-001 | proposeSource（Owner 限定・address(0) 拒否・timelock 開始・proposal 記録） | unit | ☐ | ☐ | | 未実施 | |
| ORCL-FR-002 | confirmSource / confirmSourceEmergency（timelock 経過後のみ・差替反映・価格差 guard・emergency bypass） | unit, manual | ☐ | ☐ | | 未実施 | |
| ORCL-FR-003 | cancelSourceProposal（Owner 限定・proposal クリア） | unit | ☐ | ☐ | | 未実施 | |
| ORCL-FR-004 | fetchPrice（障害透過・shutdown 代行・gas guard 再 revert・brick フォールバック） | unit, fork, integration | ☐ | ☐ | | 未実施 | |
| ORCL-FR-005 | fetchRedemptionPrice（fetchPrice と同等分岐・redemption consumer 経路） | unit, integration | ☐ | ☐ | | 未実施 | 両 consumer 対称（ORCL-SEC-004） |
| ORCL-FR-006 | 所有権の 2 段階移転（transferOwnership / acceptOwnership・誤移転防止） | unit, manual | ☐ | ☐ | | 未実施 | |
| ORCL-FR-007 | renounceOwnership 無効化（常に revert・Owner/proposal/pendingOwner 不変） | unit, manual | ☐ | ☐ | | 未実施 | |
| ORCL-FR-008 | PriceFeedPlaceholder（常に (1e18, false)・shutdown 非誘発・多重ガード） | unit, integration | ☐ | ☐ | | 未実施 | |
| ORCL-FR-009 | Post-launch 未確定ブランチの Underlying 確定フロー（dToken-first 順序強制・cap 事前確認） | unit, integration, manual | ☐ | ☐ | | 未実施 | |
| ORCL-FR-010 | Standard パターン（USDC。担保/USD 障害=shutdown・JPY/USD 障害=soft-freeze・代用/回復） | unit, fork, integration | ☐ | ☐ | | 未実施 | |
| ORCL-FR-011 | Peg-monitored パターン（WBTC。peg/担保 USD 障害=shutdown・JPY=soft-freeze・合成計算） | unit, fork, integration | ☑ | ☑ | `forge test --match-path 'test/DFWBTCPriceFeed*.t.sol'`（2026-06-21: 17 passed） | PASS(unit/integration) | `DFWBTCPriceFeed` / proxy integration で WBTC/BTC stale/down・BTC/USD stale/down・JPY soft-freeze・redemption price・lastGoodPrice を確認。fork は未実施 |
| ORCL-FR-012 | Composite rate パターン（sUSDS。USDS/USD・canonical rate 障害=shutdown・JPY=soft-freeze） | unit, fork, integration | ☐ | ☐ | | 未実施 | |
| ORCL-FR-013 | XAUT 将来候補の Composite peg パターン（on-chain downside depeg 反映を activation の必須条件とする。現行 branch binding・Day-1 露出なし） | unit, fork, integration, manual | ☐ | ☐ | | 未実施 | SYS-RISK-007 と同根 |
| ORCL-FR-014 | dToken backing peg の反映（全担保共通の後段層。pricing availability・取得不能は shutdown・実測0だけ1 wei floor・両 consumer 対称） | unit, fork, integration | ☐ | ☐ | `test_backingValuationUnavailableShutsDownAtLastGoodPrice`; `test_zeroBackingRatioReturnsNearZeroNonSentinelPrice`; `test_PricingViewDistinguishesUnavailableValuationFromMeasuredZero` | PARTIAL(unit) | V20 で critical availability 境界を実走。fork / full integration と要件全体の再認定は未実施。VAULT-FR-016 と対 |
| ORCL-FR-015 | dwstETH composite（stETH/USD market feed × `stEthPerToken()` canonical rate → JPY 換算 → backing ratio）。単一 market feed 構成のため ETH/USD 乖離ガードを持たず、redemption も同一 composite を使う | unit, fork, integration, invariant | ☑ | ☑ | `forge test --match-path test/DFWstETHPriceFeed.t.sol`（37 passed）; `forge test --match-path test/DFWstETHPriceFeedProxyIntegration.t.sol`（10 passed） | PASS(V20) | V20 で valuation unavailable shutdown を追加。JPY freeze / backing 層は共有 `JpyFreezeLib` を通る |

### 10.2 不変条件（ORCL-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ORCL-INV-001 | コアから見た PriceFeedProxy アドレス不変（差替は裏の source のみ） | manual / integration | ☐ | ☐ | | 未実施 | |
| ORCL-INV-002 | source 差替は propose→24h→confirm/confirmEmergency のみ（即時差替不能） | invariant / unit | ☐ | ☐ | | 未実施 | |
| ORCL-INV-003 | confirmSource は proposedAt + TIMELOCK_DELAY 以降のみ成功 | unit | ☐ | ☐ | | 未実施 | |
| ORCL-INV-004 | source は常に非ゼロ（InvalidSource 拒否） | unit | ☐ | ☐ | | 未実施 | |
| ORCL-INV-005 | gas guard revert（厳密 4 バイト・セレクタ一致）のみ再 revert・他は shutdown 代行 | unit / integration | ☐ | ☐ | | 未実施 | |
| ORCL-INV-006 | source brick でも Proxy _lastGoodPrice 返却（permanent DoS なし） | unit | ☐ | ☐ | | 未実施 | |
| ORCL-INV-007 | 全担保価格は JPY 建て導出（collJpy = collUsd × 1e18 / jpyUsdRate・18 桁正規化） | unit / fork | ☐ | ☐ | | 未実施 | |
| ORCL-INV-008 | upstream 価格取得基底との差分管理（`MainnetPriceFeedBase` は Chainlink 応答検証硬化のみ、`CompositePriceFeed` は sUSDS に不要な LST secondary fallback 削除のみ） | manual / static diff review | ☐ | ☐ | | 未実施 | |
| ORCL-INV-009 | placeholder は (1e18, false)・shutdown 非誘発・Vault/dToken 多重ガードと整合 | unit / integration | ☐ | ☐ | | 未実施 | |
| ORCL-INV-010 | standard / peg 型 / composite peg は primary と lastGoodPrice の 2 状態のみ | unit | ☐ | ☐ | | 未実施 | |
| ORCL-INV-011 | backing 比は下方専用 (0, 1e18]・全担保価格へ乗算 | unit / fork | ☐ | ☐ | | 未実施 | |
| ORCL-INV-012 | active DF feed constructor は初回 fetch 後に primary + nonzero `lastGoodPrice` の場合だけ成功。expired shared provider / 未登録 shutdown catch で zero cache を deploy せず、fresh JPY recovery 後は再開 | unit / integration | ☑ | ☑ | `test_expiredSharedProviderRejectsNewActiveFeedDeployments`; `test_activeFeedDeploymentRecoversAfterFreshJpyRound` | PASS(PRELIM-L02) | Standard / dwstETH 両方を拒否し、fresh recovery の liveness を確認 |

### 10.3 セキュリティ要件（ORCL-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ORCL-SEC-001 | upstream PriceFeed 基底の差分最小化（`MainnetPriceFeedBase` 硬化差分、`CompositePriceFeed` sUSDS 用 pruning、JPY/backing は DF ファイルに閉じる） | manual（継承構成レビュー）, static diff review | ☐ | ☐ | | 未実施 | |
| ORCL-SEC-002 | gas griefing 保護の透過の正確性（セレクタ一致・長さ厳格・本物障害との判別） | unit, integration | ☐ | ☐ | | 未実施 | |
| ORCL-SEC-003 | source 差替 timelock による MEV 緩和（価格差 guard・不健全時 bypass・emergency bypass） | unit, manual | ☐ | ☐ | | 未実施 | |
| ORCL-SEC-004 | 両 consumer 経路（fetchPrice / fetchRedemptionPrice）の対称な防御 | unit, integration | ☐ | ☐ | | 未実施 | |
| ORCL-SEC-005 | JPY/USD 共通依存のフェイルセーフ（障害時代用・no-shutdown・週末相当 updatedAt 境界・凍結中の挙動） | unit, fork, integration, manual | ☐ | ☐ | | 未実施 | `PRM-ORACLE-001` / `PRM-ORACLE-006` |
| ORCL-SEC-006 | 中央集権ラッパー担保のペグ監視（合成計算・ペグ段 shutdown・mainnet フィード実在確認） | unit, fork, manual | ☐ | ☐ | | 未実施 | |
| ORCL-SEC-007 | placeholder ブランチの操作不能性（各ガード revert・価値フロー全不能） | unit, integration | ☐ | ☐ | | 未実施 | |

### 10.4 ガバナンス・運用・アップグレード要件（ORCL-GOV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ORCL-GOV-001 | Owner は governance / multisig（PriceFeedProxy Owner=GOV multisig 直） | manual（デプロイ・移行構成レビュー） | ☐ | N/A | | 未実施 | N/A: 構成レビュー項目（非権限系は ORCL-FR-001..003 行） |
| ORCL-GOV-002 | Owner 移譲は 2-step | manual, unit（ORCL-FR-006 と同） | ☐ | ☐ | | 未実施 | |
| ORCL-GOV-003 | Owner 放棄の無効化 | manual, unit（ORCL-FR-007 と同） | ☐ | ☐ | | 未実施 | |
| ORCL-GOV-004 | source 差替の運用（feed 単位の入れ替え・JPY/USD source swap） | manual（差替手順書）, integration | ☐ | ☐ | | 未実施 | |
| ORCL-GOV-005 | Day 2 有効化フローの GOV 手順 | manual（手順書レビュー）, integration | ☐ | ☐ | | 未実施 | |

### 10.5 イベント・監視要件（ORCL-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ORCL-EVT-001 | SourceProposed（new source・確定可能時刻） | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| ORCL-EVT-002 | SourceUpdated(oldSource, newSource) | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| ORCL-EVT-003 | SourceProposalCancelled | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| ORCL-EVT-004 | shutdown 観測イベント（source 障害での shutdown 代行契機） | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| ORCL-EVT-005 | OwnershipTransferStarted / OwnershipTransferred | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| ORCL-EVT-006 | SourceSwitchValidated（old/new 価格・oldSourceHealthy・priceGuardBypassed） | unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| ORCL-EVT-007 | `JpyRateFrozen(timestamp, frozenRate)`（JPY soft-freeze の検知。`timestamp` は初回観測と保存済み JPY rate の stale 境界の早い方） | unit | ☑ | ☑ | `forge test --match-path test/DFPriceFeed.t.sol`（50 passed）; `forge test --match-path test/sUSDSPriceFeed.t.sol`（35 passed）; `forge test --match-path test/DFWstETHPriceFeed.t.sol`（36 passed） | PASS(V14) | 発火元は `JpyUsdRateProvider`。共有 `JpyFreezeLib` 抽出後も topic は不変で、3 feed すべてから同一 event を観測 |
| ORCL-EVT-008 | `JpyRateUnfrozen(timestamp, liveRate)`（live JPY/USD への復帰検知） | unit | ☑ | ☑ | `forge test --match-path test/DFPriceFeed.t.sol`（50 passed）; `forge test --match-path test/sUSDSPriceFeed.t.sol`（35 passed）; `forge test --match-path test/DFWstETHPriceFeed.t.sol`（36 passed） | PASS(V14) | 同上 |
| ORCL-EVT-009 | `JpyFreezeExpired(timestamp, frozenRate)`（当該 shared freeze episode の expiry。branch ごとの shutdown / user action block の P0 signal） | unit | ☑ | ☑ | `forge test --match-path test/JpyUsdRateProvider.t.sol`; `forge test --match-path test/DFPriceFeed.t.sol`; `forge test --match-path test/DFWstETHPriceFeedProxyIntegration.t.sol` | PASS(V15) | unhealthy 中は expiry を再通知し、fresh recovery は episode latch を解除する。既 shutdown branch は pinned、未観測 branch は live rate を再開 |

### 10.6 失敗時・異常系挙動（§12 ERR・ID なし）

価格取得経路の分岐（fetchPrice / fetchRedemptionPrice）:

| # | 契機 | 期待挙動（doc §12） | 発火実証 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | source success かつ有効価格 | _lastGoodPrice 更新 → 返却（定常） | ☐ | | 未実施 | |
| 2 | gas guard revert（厳密 4 バイト・セレクタ一致） | そのまま再 revert（shutdown しない） | ☐ | | 未実施 | |
| 3 | その他 revert / 無効価格（0 / type(uint256).max） | shutdownFromOracleFailure 代行 → source lastGoodPrice か Proxy _lastGoodPrice | ☐ | | 未実施 | |

placeholder 期挙動:

| # | 層 | 期待挙動（doc §12） | 発火実証 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | PriceFeedPlaceholder.fetchPrice() | (1e18, false)（shutdown 非誘発） | ☐ | | 未実施 | |
| 2 | Vault deposit / redeem | UnderlyingNotSet / UnderlyingMismatch revert | ☐ | | 未実施 | §7 と同証跡可 |
| 3 | dToken convertTo* | TokenInfoNotSet revert | ☐ | | 未実施 | §6 と同証跡可 |
| 4 | cap | 0（mint 不能）→ setCap(N) で解放 | ☐ | | 未実施 | |

エラーカタログ:

| # | エラー | 契機（参照） | 発火実証 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | InvalidSource | constructor / proposeSource の address(0)（ORCL-FR-001 / INV-004） | ☐ | | 未実施 | |
| 2 | RenounceOwnershipDisabled | renounceOwnership 呼出（ORCL-FR-007 / GOV-003） | ☐ | | 未実施 | |
| 3 | InsufficientGasForExternalCall（再 revert） | gas griefing 保護の透過（ORCL-FR-004） | ☐ | | 未実施 | |
| 4 | CallerNotPriceFeed（upstream） | underlying feed の直接 shutdown 呼出 → Proxy 代行で回避（ORCL-FR-004） | ☐ | | 未実施 | |
| 5 | UnderlyingNotSet（Vault 側） | placeholder ブランチの deposit/redeem（ORCL-FR-008） | ☐ | | 未実施 | |
| 6 | UnderlyingMismatch（Vault 側） | dToken-first 順序違反（ORCL-FR-009） | ☐ | | 未実施 | |
| 7 | TokenInfoNotSet（dToken 側） | placeholder 期の convertTo*（ORCL-FR-008） | ☐ | | 未実施 | |
| 8 | InvalidInitialPrice | active feed constructor の初回 fetch が primary + nonzero price を確立できない（ORCL-INV-012） | ☑ | `test_expiredSharedProviderRejectsNewActiveFeedDeployments` | PASS(PRELIM-L02) | Standard / dwstETH の custom error を確認 |

### 10.7 未決事項レジスタ（ORCL-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| ORCL-TBD-001 | 一部Resolved | `PRM-ORACLE-001`は確定済み。Day-1残件は`PRM-ORACLE-003` / `004`。branch 2–7のthresholdは個別activation時に扱う | SYS-RISK-001ゲート |
| ORCL-TBD-002 | Resolved | composite 継承形は確定（sUSDSPriceFeed=sUSDS 用に pruning した CompositePriceFeed 継承、LST secondary fallback 削除）→ ORCL-FR-012 / ORCL-SEC-001 行で検証 | |
| ORCL-TBD-003 | 未決 | XAUT を担保候補として評価する場合の feed 品質基準・Composite peg 実装形（現行 branch map への binding や activation を意味しない）→ ORCL-FR-013 は将来候補の activation 条件として検証 | |
| ORCL-TBD-004 | 未決 | USDS/USD deprecate 時のフォールバック feed | |
| ORCL-TBD-005 | Resolved | source 差替 timelock の追加緩和（M-1 関連・価格 guard 採用）→ ORCL-FR-002 / SEC-003 行で検証 | |
| ORCL-TBD-006 | Resolved | dToken backing peg の Day-1 方針は ORCL-FR-014 / VAULT-INV-012 に反映済み | |

---

## 11. Zapper.md（ZAP）

正本: [Zapper.md](../../protocol/product/spec/Zapper.md)。対象: `CollateralYieldZapper`（stateless・非アップグレード）。

### 11.1 機能要件（ZAP-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ZAP-FR-001 | openTroveWithRawETH（referral=`bytes32(0)` 委譲・owner=msg.sender） | unit | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-22: 31 passed） | PASS(unit) | 通常 open と `_params.owner != msg.sender` revert を確認。integration/fork は未実施 |
| ZAP-FR-002 | openTroveWithRawETHAndReferral（msg.value 厳格一致・batch 整合・bytes32 referral 発火条件・owner=msg.sender） | unit, integration | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-22: 31 passed） | PASS(unit) | `bytes32` referral emit / wrong ETH / owner mismatch / batch manager と annualInterestRate の併用拒否を確認。integration/fork は未実施 |
| ZAP-FR-003 | openTroveWithUnderlyingPermit（referral=`bytes32(0)` 委譲） | unit | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-22: 31 passed） | PASS(unit) | 事前 allowance なしで permit→open→Underlying pull→dToken 担保化を確認。permit が先に消費されても allowance が残っていれば成功し、invalid signature / allowance 不足は `PermitFailed` |
| ZAP-FR-004 | permit open ＋ bytes32 referral（事前 approve 不要・permit 失敗 revert） | unit, integration | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-22: 31 passed） | PASS(unit) | `openTroveWithUnderlyingPermitAndReferral` の `bytes32` referral emit と permit 失敗 revert を確認。integration/fork は未実施 |
| ZAP-FR-005 | addCollWithUnderlying（owner/add manager 限定・Underlying→dToken→addColl） | unit, integration | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-21: 31 passed） | PASS(unit) | owner/add manager 経路の Underlying→dToken→addColl、add manager 解除後の第三者 revert、残余ゼロを確認。integration/fork は未実施 |
| ZAP-FR-006 | withdrawCollToUnderlying（owner/remove manager・receiver 検査・redeem 連携・receiver 実着額 min） | unit, integration | ☑ | ☑ | `test_WithdrawCollToUnderlyingWithMin_UsesFeeTokenReceiverDelta`; `forge test --match-path test/CollateralYieldZapper.t.sol` | PASS(V21/unit) | 即時 redeem・buffer 不足 queue・6/8dec dust に加え、fee-on-transfer Underlying の実着額下限違反が全体 revert することを確認。integration/fork は未実施 |
| ZAP-FR-007 | withdrawJpydf（権限・receiver 検査・transfer） | unit, integration | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-21: 31 passed） | PASS(unit) | remove manager → receiver への JPYdf transfer、権限なし caller の revert、残余ゼロを確認。integration/fork は未実施 |
| ZAP-FR-008 | repayJpydf（add manager 限定・過剰返済の残余返却） | unit, integration | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-21: 31 passed） | PASS(unit) | add manager 経路の repay、権限なし caller の revert、MIN_DEBT cap 超過分の user 返却、JPYdf 残余ゼロを確認。integration/fork は未実施 |
| ZAP-FR-009 | adjustTroveWithUnderlying（4 象限: 増減担保 × 借入返済の権限・受渡・残余返却） | unit, integration | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-08-01: 37 passed） | PASS(unit) | 通常 adjust の4象限、remove manager receiver、`WithMin` revert、`adjustZombieTroveWithUnderlying` の zombie→active happy path、共通 redeem helper の6/8dec dust返却を確認。`adjustZombieTroveWithUnderlyingWithMin` / integration は未実施 |
| ZAP-FR-010 | closeTroveToUnderlying（権限・receiver・gas comp 返却・close→redeem→ETH 返却） | unit, integration | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-08-01: 37 passed） | PASS(unit) | 即時 redeem・buffer 不足 queue・`WithMin` revert・gas comp・ETH 送付失敗に加え、6dec Underlying branchでredemption後に生じた非整数担保をcloseし最大UnderlyingとdToken dustを返却できることを確認。integration/fork は未実施 |
| ZAP-FR-011 | Day-1 ABI から削除済み（Flash Loan close / collateral-funded close） | manual / build artifact review | ☑ | ☑ | `rg -n "DFDisabledExchange\|flashLoanProvider\|receiveFlashLoan\|IFlashLoan\|closeTroveFromCollateral\|Balancer" contracts/src contracts/test contracts/script frontend/app/src frontend/df-shared/generated`（2026-06-19: no matches） | PASS(manual/build) | fresh deploy 方針。production ABI / deploy wiring / frontend flow に存在しないことを確認。Balancer は将来候補にも戻さない |
| ZAP-FR-012 | Day-1 ABI から削除済み（Flash Loan callback） | manual / build artifact review | ☑ | ☑ | 同上（2026-06-19: no matches） | PASS(manual/build) | callback selector / provider dependency / interface / Balancer adapter が存在しないことを確認 |
| ZAP-FR-013 | receive（WETH.withdraw の ETH 受領・WETH 以外の直接 ETH 拒否） | unit | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-21: 31 passed） | PASS(unit) | close 経路で WETH unwrap を確認し、直接 ETH transfer は `CollateralYieldZapper__OnlyWETH` で拒否 |
| ZAP-FR-014 | ARCHIVED: Sky USDC collateral-ingress variant（slippage下限・残余ゼロ・temporary allowanceゼロ戻し） | archive unit, integration | ☑ | ☑ | `forge test --match-path test/archive/SkyUsdcSUsdsYieldZapper.t.sol`; `forge test --match-path test/SkyUsdcSUsdsConverter.t.sol` | PASS(archive) | official deploy pathとactive audit scopeから除外 |
| ZAP-FR-015 | native ETH on-ramp（ETH→stETH→wstETH→dwstETH・deploy パラメータでの明示的有効化・slippage 下限・`msg.value` 厳格一致・stETH 丸め残余の sweep） | unit, integration | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（47 passed。`test_OpenTroveWithNativeEth_StakesWrapsAndOpensTrove`; `test_OpenTroveWithNativeEthAndReferral_EmitsReferralAndRouteEvents`; `test_OpenTroveWithNativeEth_RevertsWhenSubmitPausedAndPlainPathUnaffected`; `test_OpenTroveWithNativeEth_RevertsWhenMinWstEthOutNotMet`; `test_OpenTroveWithNativeEth_SweepsStEthRoundingResidueToCaller`; `test_OpenTroveWithNativeEth_RevertsOnWrongMsgValue`; `test_OpenTroveWithNativeEth_RevertsWhenRouteUnavailable`; `test_CloseTroveToUnderlying_AfterNativeEthZapReturnsWstEthAndGasComp`; `test_OpenTroveWithNativeEth_ReentrantSubmitIsBlockedByGuard`） | PASS(V14) | route は `_expectedStEth != address(0)` の instance にのみ存在し、不一致は deploy 時 revert。staking 停止時は typed revert となり wstETH 直接投入経路は影響を受けない |

### 11.2 不変条件（ZAP-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ZAP-INV-001 | 永続 business state なし（constructor 固定参照 + `ReentrancyGuard` lock のみ） | manual（storage layout） | ☑ | N/A | manual review（2026-06-21: `CollateralYieldZapper` / `SkyUsdcSUsdsYieldZapper` / `UniV4Exchange`） | PASS(manual) | 可変 storage は OpenZeppelin `ReentrancyGuard` の lock 状態に限定。route/core 参照は immutable |
| ZAP-INV-002 | collToken == dToken（AddressesRegistry.collToken() から導出） | unit / manual | ☐ | ☐ | | 未実施 | |
| ZAP-INV-003 | 正常終了後に underlying / collToken / jpydfToken 残高が滞留しない（残余返却） | unit / invariant | ☑ | ☐ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-08-01: 37 passed） | PASS(unit) | open/add/withdraw/repay/adjust/zombie-adjust/close/Skyに加え、6/8dec・only-dust・queue+dustでreceiver返却とZapper残余ゼロを確認。invariant/fork は未実施 |
| ZAP-INV-004 | open フローの資産経路整合（Underlying→dToken→open→JPYdf 転送） | unit | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-21: 31 passed） | PASS(unit) | 通常 open と permit open で user が dToken を受け取らず、Trove collateral と JPYdf 受領が一致することを確認 |
| ZAP-INV-005 | ReferralDeposit は open 系で _referralCode != `bytes32(0)` のときのみ 1 度発火・Vault / コアへ非伝播 | unit | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-22: 31 passed） | PASS(unit) | referral=`bytes32(0)` の通常 open で未発火、通常 referral open / permit referral open で Zapper emitter の `ReferralDeposit` が 1 回だけ発火し、user/troveId/underlyingAmount/dTokenAmount/jpydfAmount/referralCode が一致することを確認 |
| ZAP-INV-006 | 旧 leverage callback / router surface は production `src` に存在しない | manual / build artifact review | ☑ | ☑ | `rg -n "LeverageWETHZapper\|LeverageLSTZapper\|ILeverageZapper\|receiveFlashLoan\|IFlashLoan\|flashLoanProvider\|closeTroveFromCollateral\|DFDisabledExchange\|Balancer" contracts/src contracts/script frontend/app/src frontend/df-shared/generated`（2026-06-21: no matches） | PASS(manual/build) | fresh deploy 方針。旧 callback を空実装で残すのではなく、Day-1 production surface から削除済み |
| ZAP-INV-007 | Day-1 production ABI に Flash Loan callback / provider dependency / Balancer adapter / fail-fast exchange placeholder が存在しない | manual（ABI・deploy wiring review） | ☑ | ☑ | `rg -n "DFDisabledExchange\|flashLoanProvider\|receiveFlashLoan\|IFlashLoan\|closeTroveFromCollateral\|Balancer" contracts/src contracts/test contracts/script frontend/app/src frontend/df-shared/generated`（2026-06-19: no matches） | PASS(manual/build) | `forge test --match-path test/DeployLiquity2StrategySelector.t.sol`（12 passed）で active CYZ deploy dependency からも除外確認 |
| ZAP-INV-008 | 全 user-facing 外部状態変更関数が nonReentrant | manual（修飾子網羅）/ unit | ☑ | ☑ | `forge test --match-path test/ExchangeApprovalHygiene.t.sol`（2026-06-21: 9 passed） | PASS(unit/manual) | CYZ / Sky / UniV4 の user-facing mutation は `nonReentrant`。v4 adapter は router 再入 mock で `swapFromJpydf` / `swapToJpydf` の再入 revert を確認 |
| ZAP-INV-009 | ARCHIVED: Sky route正常終了後にroute token / archived candidate dToken / JPYdfが滞留しない | archive unit / invariant | ☑ | ☐ | archive Sky Zapper suite | PASS(unit) | archive suiteでresidueとconverter/vault allowance 0を継続確認 |

### 11.3 セキュリティ要件（ZAP-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ZAP-SEC-001 | 全 user-facing 外部状態変更関数の nonReentrant（再入攻撃 revert） | manual（修飾子網羅）, unit, invariant=ZAP-INV-008 | ☑ | ☑ | `forge test --match-path test/ExchangeApprovalHygiene.t.sol`（2026-06-21: 9 passed） | PASS(unit/manual) | Universal Router / hook 相当の外部 call 中に同じ `UniV4Exchange` へ再入しても `ReentrancyGuard` で停止 |
| ZAP-SEC-002 | 受益者と実行者の整合（open owner / add / remove manager の役割分離・第三者操作 revert） | unit, manual | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-21: 31 passed） | PASS(unit) | open 系は `_params.owner != msg.sender` を拒否。通常 route / Sky route の owner mismatch、add/remove manager の許可・拒否、receiver 不一致 revert を確認 |
| ZAP-SEC-003 | 残余の返却・固定化回避（過剰返済・端数） | unit, invariant=ZAP-INV-003 | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-08-01: 37 passed） | PASS(unit) | `repayJpydf` の MIN_DEBT cap 超過分に加え、6/8dec Underlyingの非償還可能dToken端数をreceiverへ返し、Vault exact guardを維持することを確認。invariant は ZAP-INV-003 側で未実施 |
| ZAP-SEC-004 | Day-1 production ABI に Flash Loan callback / provider dependency / Balancer adapter が存在しない | manual, invariant=ZAP-INV-007 | ☑ | ☑ | `rg -n "DFDisabledExchange\|flashLoanProvider\|receiveFlashLoan\|IFlashLoan\|closeTroveFromCollateral\|Balancer" contracts/src contracts/test contracts/script frontend/app/src frontend/df-shared/generated`（2026-06-19: no matches） | PASS(manual/build) | caller guard を監査するのではなく surface removal で callback spoofing / provider misbinding を排除 |
| ZAP-SEC-005 | スリッページ保護（receiver 実着額の下限割れ revert・swap 価格変動下の下限保証） | unit, fork | ☑ | ☑ | `test_WithdrawCollToUnderlyingWithMin_UsesFeeTokenReceiverDelta`; queue 下限違反テスト群 | PARTIAL(V21/unit) | fee-on-transfer を含む immediate receiver delta は検証済み。swap 価格変動下の fork は未実施 |
| ZAP-SEC-006 | approve 先の信頼コンポーネント限定（Sky/v4 の allowance reset 含む） | unit, manual | ☑ | ☑ | `forge test --match-path test/ExchangeApprovalHygiene.t.sol`（2026-06-21: 9 passed） | PASS(unit) | zero-first token、Permit2→Universal Router allowance reset、exact-output 未使用 input 返却、router 再入中の一時承認境界を確認 |
| ZAP-SEC-007 | gas compensation ETH 送付の戻り値検査（送付失敗 revert） | unit | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-21: 31 passed） | PASS(unit) | remove manager 経由で ETH 拒否 receiver を設定し、`SafeTransferLib.ETHTransferFailed` revert と close/redeem の巻き戻りを確認 |

### 11.4 ガバナンス・運用・アップグレード要件（ZAP-GOV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ZAP-GOV-001 | コア・Vault・dToken への非侵襲（Zapper 専用 hook / signature / state 不追加） | manual | ☑ | N/A | manual review（2026-06-21: `contracts/src/Zappers/**`） | PASS(manual) | Zapper 差分は Core / Vault / dToken に Zapper 専用 IF や状態を追加せず interface 経由で呼び出す。なお本 PR の Vault 汎用 `redeemWithPermit` hardening は VAULT-SEC-008 で別管理し、Liquity core / `DToken` は変更なし |
| ZAP-GOV-002 | stateless / 非アップグレード（デプロイ構成） | manual | ☑ | ☑ | `rg -n "UUPSUpgradeable\|Initializable\|ERC1967\|upgradeTo\|upgradeToAndCall\|reinitializer\|onlyProxy\|initializer" contracts/src/Zappers`（2026-06-21: no matches） | PASS(manual) | `CollateralYieldZapper` / `SkyUsdcSUsdsYieldZapper` / `UniV4Exchange` は proxy/upgrade initializer surface を持たない。可変 business storage はなく、参照は constructor immutable |
| ZAP-GOV-003 | referralCode のオフチェーン閉域（Vault / コアへ referral 引数なし） | unit / manual | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-22: 31 passed）＋ source review（`ReferralDeposit` emit only） | PASS(unit/manual) | ZAP-INV-005 / ZAP-EVT-001 と同証跡。`referralCode` は `ReferralDeposit` / Sky route event にのみ出力され、Vault / BorrowerOperations call 引数へ渡さない |

### 11.5 イベント・監視要件（ZAP-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ZAP-EVT-001 | ReferralDeposit（発火条件・index・非伝播） | unit | ☑ | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-22: 31 passed） | PASS(unit) | ZAP-INV-005 と同証跡。実ログを decode し `underlyingAmount` / `dTokenAmount` / `jpydfAmount` と indexed `referralCode` を確認 |

### 11.6 失敗時・異常系挙動（§12 ERR・ID なし）

エラーカタログ（Zapper レベル）:

| # | エラー / 契機 | 発生条件（参照） | 発火実証 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | msg.value != ETH_GAS_COMPENSATION | open 系で gas comp 以外の ETH 送付（ZAP-FR-002/004） | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-21: 31 passed） | PASS(unit) | `test_RevertWhen_OpenReceivesWrongETH` |
| 2 | batch 整合違反 | batchManager != 0 && annualInterestRate != 0（open 系） | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-21: 31 passed） | PASS(unit) | `test_OpenTrove_RevertsWhenBatchManagerAndInterestRateAreBothSet` |
| 3 | `CollateralYieldZapper__PermitFailed` | permit 失敗の try/catch 捕捉（ZAP-FR-004） | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-21: 31 passed） | PASS(unit) | `test_OpenTroveWithUnderlyingPermitAndReferral_EmitsReferralAndRejectsInvalidSignature` |
| 4 | 権限なし | open owner / add / remove manager 不一致（ZAP-SEC-002） | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-21: 31 passed） | PASS(unit) | `test_OpenTrove_RevertsWhenOwnerIsNotSender` / `test_SkyRoute_RevertsWhenOwnerIsNotSender` / `test_AddCollWithUnderlying_RespectsAddManagerRestriction` / `test_WithdrawJpydf_RevertsForUnauthorizedRemoveManager` / `test_RepayJpydf_RespectsAddManagerRestriction` |
| 5 | Zapper が receiver でない | 担保引出・借入・close 系の _requireZapperIsReceiver 不成立 | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-21: 31 passed） | PASS(unit) | `test_RevertWhen_CoreRemoveManagerReceiverIsNotZapper` |
| 6 | コールバック偽装 | Flash Loan callback surface / Balancer adapter が Day-1 ABI に存在しないこと（ZAP-SEC-004） | ☑ | `rg -n "DFDisabledExchange\|flashLoanProvider\|receiveFlashLoan\|IFlashLoan\|closeTroveFromCollateral\|Balancer" contracts/src contracts/test contracts/script frontend/app/src frontend/df-shared/generated`（2026-06-19: no matches） | PASS(manual/build) | |
| 7 | スリッページ下限割れ | collLeft < _minExpectedCollateral（ZAP-SEC-005） | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-21: 31 passed） | PASS(unit) | `withdraw/close/adjust` の `WithMin` queue revert を確認。swap 価格変動下の fork 証跡は ZAP-SEC-005 側で未実施 |
| 8 | ETH 送付失敗 | gas comp の call 失敗（ZAP-SEC-007） | ☑ | `forge test --match-path test/CollateralYieldZapper.t.sol`（2026-06-21: 31 passed） | PASS(unit) | `test_CloseTroveToUnderlying_RevertsWhenGasCompensationReceiverRejectsETH` |

依存先由来の revert（伝播。Zapper 経由で観測できること）:

| # | 契機 | 由来 | 発火実証 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | CapExceeded / TokenInfoNotSet | CollateralVault.deposit（placeholder ブランチ） | ☐ | | 未実施 | |
| 2 | MIN_DEBT 未満 / _maxUpfrontFee 超過 / コア検査 | 🔵 BorrowerOperations | ☐ | | 未実施 | |
| 3 | swap-backed close / Flash Loan 返済不能 | Day-1 Zapper ABI から経路削除済み | ☑ | ZAP-FR-011 / ZAP-FR-012 / ZAP-INV-007 と同じ不在確認 | PASS(manual/build) | CYZ は FlashLoanProvider / Balancer adapter / collateral-funded-close exchange に依存しない |

### 11.7 未決事項レジスタ（ZAP-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| ZAP-TBD-001 | 解決 | requestId 再 emit は追加しない。Zapper 戻り値＋Vault `Redeemed` / `WithdrawRequested` / `WithdrawClaimed` を正本 event とする | contract 変更不要 |
| ZAP-TBD-002 | 解決 | adjust 増担保は `deposit` 戻り値を `dTokenChange` に使用済み。減担保の `convertToDToken` は必要 | contract 変更不要 |
| ZAP-TBD-003 | 解決 | `DeployLiquity2` active branch で CYZ を deploy し、`collToken == dToken` / `vault.underlying == underlying` / CYZ 依存先（Vault・dToken・Underlying・BorrowerOperations・JPYdf）を deploy-tail で assert。inert branch は CYZ zero を assert | FlashLoanProvider / Balancer adapter / collateral-funded-close exchange / fail-fast exchange placeholder は CYZ constructor dependency ではない |
| ZAP-TBD-004 | 延期 | dToken Leverage は MVP 必須ではない。frontend は dToken branch Multiply を公開しない | 将来有効化時も Balancer / 削除済み Flash Loan callback に依存せず、別コントラクト / route selector として新規設計 |
| ZAP-TBD-005 | 任意 | WETH native ETH 入力は UX 追加。現行は WETH ERC-20 Underlying 経路を正とする | protocol blocker ではない |
| ZAP-TBD-006 | 解決 | permit 非対応 token は事前 approve 経路を使う。permit entrypoint は EIP-2612 対応 token 専用 | frontend / SDK route selection |
| ZAP-TBD-007 | 解決（unit 検証済・integration 一部未完） | `adjustZombieTroveWithUnderlying` / `...WithMin` は ZAP-FR-009 として実装済み。通常 adjust 4象限と zombie→active happy path の unit 証跡は追加済み | `adjustZombieTroveWithUnderlyingWithMin` 専用 unit / integration 証跡は未完 |
| ZAP-TBD-008 | UI対応 | `CapExceeded` / `TokenInfoNotSet` は依存先 revert をそのまま伝播。追加 contract guard は不要 | frontend / console で inactive / cap zero を明示 |
| ZAP-TBD-009 | 解決済み | `SkyUsdcSUsdsConverter` が Sky LitePSMWrapper の USDC→USDS route を具象化し、`sky-susds` 選択時に `DeployLiquity2` が deploy する | SkyZapper の deploy / manifest / frontend binding は別途 FRNT-FR-013 / FRNT-FR-014 の残作業 |
| ZAP-TBD-010 | 条件付き | JPYdf/USDC only liquidity / swap route 本番有効化は将来の swap-backed close / collateral-funded repay / Multiply の前提。`UniV4Exchange` 自体は Day-1 audit scope に含める | base open / add / withdraw / close-with-JPYdf には不要。Day-1 標準は JPYdf/USDC Uniswap v4。Curve と USDT/USDS/WETH/XAUT JPYdf 直接 pool は scope 外。現行 ABI に swap-backed dToken flow は存在しない |

---

## 12. Parameter Catalog / Parameters.md（PRM・定義／値検証）

ID・意味・単位・不変条件の正本は [Parameter Catalog](../../protocol/product/parameters/Parameter-Catalog.md)、現行Day1値の正本は [Parameters.md](../../Parameters.md) である。検証 = **Parameters の確定値と deploy 投入値 / setter 設定値の機械突合**＋パラメータ間不変条件の forge / 構成検査（SYS-RISK-005 の gate）。CR・ペナルティ系は branch immutable（誤投入は再デプロイでしか直らない）ため、deploy script 末尾の構成検査を必須とする。

### 12.1 パラメータ間不変条件（PRM-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PRM-INV-001 | 各ブランチ SCR < MCR < CCR | forge / deploy 構成検査 | ☑ | ☑ | `forge test --match-path test/DFBranchRiskParams.t.sol`（2 passed）; `forge test --match-path test/DeployBranchRiskInvariants.t.sol`（8 passed）（`test_Day1BranchParamsSatisfyEveryInvariant`; `test_RevertWhen_CrOrderingBroken`） | PASS(V18) | 全 8 ブランチ。constants 側と deploy preflight 側の両方を実証 |
| PRM-INV-002 | MCR = 1 / LLTV（逆数関係） | forge / 検算 | ☐ | N/A | | 未実施 | N/A: 算術恒等（逆数）の検算のみ |
| PRM-INV-003 | LIQUIDATION_PENALTY_SP ≤ LIQUIDATION_PENALTY_REDISTRIBUTION | forge / deploy 構成検査 | ☑ | ☑ | `forge test --match-path test/DFBranchRiskParams.t.sol`（2 passed）; `forge test --match-path test/DeployBranchRiskInvariants.t.sol`（8 passed）（`test_RevertWhen_SpPenaltyExceedsRedistribution`） | PASS(V18) | JPY は 5%=5% 等値 |
| PRM-INV-004 | `MCR × 199 >= (1 + LIQUIDATION_PENALTY_SP) × 200`; `MCR >= 1 + LIQUIDATION_PENALTY_REDISTRIBUTION` | forge実証 | ☑ | ☑ | L-04修正候補の`RiskParamsFinalization`、`DeployBranchRiskInvariants`、`DFBranchRiskParams`：L-03/L-04/I-06/I-09の関連34テスト成功 | 関連34テスト・通常Foundry検証・サイズ検証PASS | dJPY/dJGBの初期MCRは105.53%。担保補償の控除を含む。MCR未満の清算で満額のpenaltyを保証する条件ではない。 |
| PRM-INV-005 | コード強制境界（SP ≥ 5e16・Redist ≤ 20e16） | unit（Constants MIN/MAX） | ☑ | ☐ | `forge test --match-path test/DFBranchRiskParams.t.sol`（2 passed） | PASS(V18) | SP 全 5%=下限ちょうど（境界）。範囲外を拒否する経路は `AddressesRegistry` constructor（`SPPenaltyTooLow` / `RedistPenaltyTooHigh`）が強制するが、DF 側に拒否 test は無い |
| PRM-INV-006 | SCR ≥ URGENT_REDEMPTION_BONUS 充足水準（≈102%） | forge / deploy 構成検査 | ☑ | ☑ | `forge test --match-path test/DFBranchRiskParams.t.sol`（2 passed）; `forge test --match-path test/DeployBranchRiskInvariants.t.sol`（8 passed）（`test_RevertWhen_ScrBelowUrgentRedemptionBonus`; `test_ScrExactlyAtTheBoundIsAccepted`） | PASS(V18) | 最小 JPY 103.30%。deploy guard は本 campaign まで **MCR** と比較しており、`SCR < MCR`（PRM-INV-001）が別途強制されるぶん公開済み不変条件より弱い検査になっていた（#859 → #1205 の引継ぎ事項）。`p.SCR` へ修正し、境界ちょうどの受理と境界未満の拒否を test で固定した |
| PRM-INV-007 | bufferFloor ≤ bufferTarget | unit / deploy 構成検査 | ☐ | ☐ | | 未実施 | |

### 12.2 パラメータ値の一致検査（PRM-* レジストリ）

各行の「正常系」= Parameters.mdの確定値とオンチェーン表現（`<X>` = DWSTETH 等のdToken記号別）が全ブランチで一致すること。「異常系」= エンコード（WAD / bps / 秒 / dec）と境界の検証。

| ID | パラメータ（オンチェーン定数・setter） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PRM-LLTV | LLTV（オンチェーン非保持・MCR の逆数） | PRM-INV-002 行で吸収 | ☐ | N/A | | 未実施 | N/A: オンチェーン非保持（検証実体は PRM-INV-002 行） |
| PRM-MCR | MCR（`MCR_D<X>`・deploy immutable） | unit / deploy 構成検査 | ☐ | ☐ | | 未実施 | 全 Br 確定（Br2–7 も値は Day-1 確定・Underlying のみ TBD） |
| PRM-CCR | CCR（`CCR_D<X>`） | unit / deploy 構成検査 | ☐ | ☐ | | 未実施 | 同上 |
| PRM-SCR | SCR（`SCR_D<X>`） | unit / deploy 構成検査 | ☐ | ☐ | | 未実施 | 同上 |
| PRM-BCR | BCR（`BCR_D<X>`） | unit / deploy 構成検査 | ☐ | ☐ | | 未実施 | 同上 |
| PRM-LIQPEN-SP | Liquidation Penalty SP（`LIQUIDATION_PENALTY_SP_D<X>`） | unit / deploy 構成検査 | ☐ | ☐ | | 未実施 | |
| PRM-LIQPEN-RD | Redistribution Penalty（`LIQUIDATION_PENALTY_REDISTRIBUTION_D<X>`） | unit / deploy 構成検査 | ☐ | ☐ | | 未実施 | |
| PRM-LIQ-KEEPER | 清算実行者担保補償（divisor 0.5% / 上限：dwstETH 2 / dUSDC 1,000単位、予約枠は有効化前に一度確定） | unit（§5 Core 行 4 と同証跡可） | ☐ | ☐ | | 未実施 | |
| PRM-mintCap | mintCap（dToken 総供給 cap・`dToken.setCap`・GOV 可変） | unit / deploy 構成検査 | ☐ | ☐ | | 未実施 | 値はParameters.mdと突合。JPYdf債務の直接capではない |
| PRM-allocCooldown | allocatorCooldown（`setAllocatorConfig`） | unit / deploy 構成検査 | ☐ | ☐ | | 未実施 | 全 30m。initialize 既定のまま運用に入らない（Parameters.mdのdeploy gate） |
| PRM-allocMaxMove | allocateMaxMove（`setAllocatorConfig`） | unit / deploy 構成検査 | ☐ | ☐ | | 未実施 | 値はParameters.mdと突合。同上deploy gate |
| PRM-withdrawDelay | withdrawDelay（`setWithdrawDelay`） | unit / deploy 構成検査 | ☐ | ☐ | | 未実施 | 運用先依存 |
| PRM-bufferTargetBps | bufferTargetBps（`setBufferConfig`） | unit / deploy 構成検査 | ☐ | ☐ | | 未実施 | withdrawDelay 連動 |
| PRM-bufferFloor | bufferFloor（`setBufferConfig`） | unit / deploy 構成検査 | ☐ | ☐ | | 未実施 | 全 0 |
| PRM-BRIDGE-MINTER-TIMELOCK | `BRIDGE_MINTER_TIMELOCK` = 48h（bridge minter 追加の timelock）・Day-1 gate `bridgeMinterCount==0`（bridge 未稼働） | unit / deploy 構成検査 | ☐ | ☐ | | 未実施 | **V1 追加（メタ監査・commit `756a736` 由来）**。JpydfToken bridge-ready dormant surface（CORE-BT / SYS-FR-006）に直結 |

### 12.3 Oracle staleness（Parameters.md）

**JPY/USD（#4）は `PRM-ORACLE-001` との一致と境界 strict `<` を通常検証する。Day-1 非 JPY feed（#1-3）は ORCL-TBD-001、将来候補（#5）は Branch 4（dBTC）の exact Underlying 未決のため BLOCKED。**

| # | Feed | しきい値 | 発火実証 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | ETH/USD | `PRM-ORACLE-002` | ☐ | | BLOCKED(ORCL-TBD-001) | |
| 2 | stETH/USD | `PRM-ORACLE-003` | ☐ | | BLOCKED(ORCL-TBD-001) | dwstETH market leg |
| 3 | USDC/USD | `PRM-ORACLE-004` | ☐ | | BLOCKED(ORCL-TBD-001) | |
| 4 | JPY/USD（全ブランチ共通） | `PRM-ORACLE-001` | ☐ | | 未実施 | stale 判定は strict `<`・カレンダーなし、の挙動検証を含む |
| 5 | WBTC/BTC（将来候補） | `PRM-ORACLE-005` | ☐ | | BLOCKED(Branch 4（dBTC）activation) | Collateral Parameter Policy §2.4 連動 |

### 12.4 ガバナンス遅延統制（Parameters.md・2026-06-12 確定）

deploy 構成検査（holder・delay の assert）で検証する。

| # | 項目 | 確定値 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 共通 TimelockController minDelay | 24h（全レイヤー共用 1 本） | ☐ | ☐ | | 未実施 | |
| 2 | Timelock PROPOSER / EXECUTOR / CANCELLER | GOV multisig / GOV multisig / PROPOSER・EXECUTOR と同一の Admin multisig（admin renounce 済） | ☐ | ☐ | | 未実施 | OZ `TimelockController` が proposer に `CANCELLER_ROLE` も付与する既定形を Day-1 採用 |
| 3 | Vault WRITEOFF_ROLE | 高定足数 GOV multisig（直接・即時） | ☐ | ☐ | | 未実施 | |
| 4 | GUARDIAN_ROLE / Strategy Owner | Guardian multisig（即時） | ☐ | ☐ | | 未実施 | |
| 5 | Vault ALLOCATOR_ROLE | 運用 Bot / マルチシグ | ☐ | N/A | | 未実施 | N/A: holder 構成の確認のみ（遅延統制なし） |
| 6 | PriceFeedProxy Owner | GOV multisig（直。Timelock 配下に置かない） | ☐ | ☐ | | 未実施 | 二重遅延回避・即時 cancel 維持の確認 |
| 7 | deploy gate: allocateMaxMove / allocatorCooldown 有界値設定 | initialize 既定（max / 0）のまま運用に入らない | ☐ | ☐ | | 未実施 | |

### 12.5 パラメータ未確定事項・留意事項（検証ゲート）

| # | 項目 | 扱い | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| 1 | Branch 2–7 の Underlying 未確定（値は Day-1 確定 immutable） | Underlying 確定までは placeholder 検証（ORCL-FR-008 / VAULT-INV-011）で代替。Br2–7 の §12.2 値は Day-1 で確定済み（immutable）。Underlying 確定時にその確定値をストレスで検証し、Day-1 値が妥当でなければ再デプロイ＝移行を検討（詳細は [Collateral Parameter Policy](../../protocol/product/policies/Collateral-Parameter-Policy.md) §2.4） | BLOCKED(Underlying 未確定) | |
| 2 | JPY ブランチのペナルティ余裕（等号近傍。Day1 Parameter Decision §4） | **forge 実証が必須**（PRM-INV-004 行と同証跡） | 未実施 | doc 明記の残課題 |
| 3 | XAUT 将来候補（現行 branch binding・Day-1 露出なし） | 負の構成検査＋ activation package review（ORCL-FR-013 / SYS-RISK-007 行と同根） | 未実施 | |

---

## 13. Treasury.md（TRSY・Treasury revenue router）

正本: [Treasury.md](../../protocol/roadmap/spec/Treasury.md)。**注意**: 本モジュールは Day-2 仕様で、`contracts/src/Treasury.sol` は未実装（SYS-RISK-003 / TRSY-TBD 参照）。Treasury は purpose routing 専用であり、SP 追加報酬の buyback / root / claim は §13A、Referral reward budget は §13B/§13C、backstop reserve の会計は CollateralVault / incident policy で検証する。TBD レジスタを除く TRSY-* 行は実装着手まで `BLOCKED(未実装)` と記録する（空欄のまま放置しない）。

### 13.1 機能要件（TRSY-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TRSY-FR-001 | initialize（role・Foundation Safe・初期 purpose 宛先/比率・backstop Vault・ゼロ/再初期化 revert） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-FR-002 | splitYield（Distributor は exact pull・allowance 残ゼロ、backstop Vault / Foundation Safe は固定比率 routing、いずれかの失敗時は全体 revert） | unit, invariant=TRSY-INV-001/002/003/004 | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-FR-003 | forwardRewardToken（非 Underlying 報酬トークンを Foundation Safe へ単純転送・Underlying 拒否） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-FR-004 | setPurposeShareBps（bounds・将来効・Foundation 残余の構造保証） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-FR-005 | purpose destination / backstop Vault 変更（propose/confirm/cancel・delay 未経過拒否・disable・underlying 一致） | unit, invariant=TRSY-INV-005 | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-FR-006 | pauseRouting / unpauseRouting（非対称・splitYield 停止・forwardRewardToken 継続） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-FR-007 | emergencyBackstopDeposit（routing pause 中・登録 Vault・underlying 一致・不足額上限・approve 残ゼロ） | unit, invariant=TRSY-INV-006 | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-FR-008 | View 群（unsplitBalance / purpose share / destination / backstop Vault / routed total / proposal） | unit | ☐ | N/A | | BLOCKED(未実装) | N/A: view のみ |
| TRSY-FR-009 | UUPS アップグレード（GOV 限定・Timelock holder・storage 追記のみ） | unit, manual | ☐ | ☐ | | BLOCKED(未実装) | |

### 13.2 不変条件（TRSY-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TRSY-INV-001 | Treasury からの資金流出先は `{purposeDestination[p], backstopVault[token], foundationSafe}` のみ。任意 `to` を指定する送金関数を持たない | unit / manual（全関数レビュー） | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-INV-002 | `Σ purposeShareBps <= PURPOSE_SHARE_TOTAL_MAX_BPS` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-INV-003 | `splitYield` は destination unset / disabled の purpose を黙って他用途へ流用しない | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-INV-004 | Treasury は DEX router、SP、Referral participant へ直接送金・呼び出しせず、Distributor allowance は purpose amount 限定・通知後 0。Vault への直接呼び出しは登録済み `backstopDeposit` のみ | unit / static review | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-INV-005 | destination 変更は timelock 経過前に効力を持たない | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-INV-006 | `emergencyBackstopDeposit` は routing pause 中、`BACKSTOP_DEPOSIT` 有効時、登録 Vault、underlying 一致、不足額上限内でしか実行できない | unit / invariant | ☐ | ☐ | | BLOCKED(未実装) | |

### 13.3 イベント・監視要件（TRSY-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TRSY-EVT-001 | YieldRouted(token, amount, foundationAmount, purposes[], destinations[], purposeAmounts[]) | unit（台帳定義） | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-EVT-002 | RewardTokenForwarded(token, amount) | unit（台帳定義） | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-EVT-003 | PurposeShareBpsUpdated(purpose, oldBps, newBps) | unit（台帳定義） | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-EVT-004 | PurposeDestinationChangeProposed/Changed/Cancelled(purpose, destination, readyAt) | unit（台帳定義） | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-EVT-005 | PurposeDestinationDisabled(purpose, destination) | unit（台帳定義） | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-EVT-006 | RoutingPaused(account) / RoutingUnpaused(account) | unit（台帳定義） | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-EVT-007 | BackstopVaultChangeProposed/Changed/Cancelled(token, vault, readyAt) | unit（台帳定義） | ☐ | ☐ | | BLOCKED(未実装) | |
| TRSY-EVT-008 | BackstopDepositedFromTreasury(token, vault, amount, received, emergency) | unit（台帳定義） | ☐ | ☐ | | BLOCKED(未実装) | |

### 13.4 失敗時・異常系挙動（§9 ERR・ID なし）

| # | 事象 | 期待挙動（doc §12） | 発火実証 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | destination contract 障害 / revert | `splitYield` 全体を revert。資金は Treasury に残り、他用途へ流用しない | ☐ | | 未実施 | |
| 2 | 正 share の purpose destination 未設定 / disabled | `splitYield` revert。GOV が destination を修復するか share を 0 にするまで未処理残として滞留 | ☐ | | 未実施 | |
| 3 | 正 share の backstop Vault 未設定 / underlying 不一致 | `splitYield` / `emergencyBackstopDeposit` revert。GOV が登録を修復するか `BACKSTOP_DEPOSIT` share を 0 にするまで未処理残として滞留 | ☐ | | 未実施 | |
| 4 | 比率変更ミス | bounds 違反は revert。bounds 内の誤設定は governance / monitoring で検知し、以後の split から修正 | ☐ | | 未実施 | |
| 5 | Day-2 切替前 | Vault treasury は Safe のまま。Treasury routing は発生しない | ☐ | | 未実施 | |
| 6 | backing 毀損 | `pauseRouting` で C/D/Foundation への通常支払いを止め、登録 Vault の不足額上限内で `emergencyBackstopDeposit` を実行できる。補填後の release / 再開順序は incident policy / governance decision で扱う | ☐ | | 未実施 | |

### 13.5 未決事項レジスタ（TRSY-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| TRSY-TBD-001 | 未決 | `PURPOSE_SHARE_TOTAL_MAX_BPS`、初期 `purposeShareBps`、`TRSY_TIMELOCK_DELAY` の確定値 | |
| TRSY-TBD-002 | 未決 | Day-1 Safe 留保分を Treasury 導入後に一括 routing するか、一定期間で分割 routing するか | |
| TRSY-TBD-003 | 未決 | 緊急 backstop 補填後の `releaseBackstopToBuffer`、redeem / claim / routing 再開順序（別 incident policy） | |

---

## 13A–13C. Reward-Distributors.md

正本: [Reward-Distributors.md](../../protocol/roadmap/spec/Reward-Distributors.md)。3コントラクトはいずれも未実装で current audit scope 外。SPARD / BRRD は Day-2、SPDRD は Day-2+ の仕様である。

### 13A. SP 追加報酬（SPARD）

#### 13A.1 機能要件（SPARD-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SPARD-FR-001 | initialize（role・Treasury・初期 reward asset・ゼロ/再初期化 revert） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-FR-002 | Treasury revenue 受領（onlyTreasury・purpose 検証・exact pull・donation 未会計・share 合計検証） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-FR-003 | executeBuyback（予算内・有効 reward asset・min-out コード強制・価格乖離拒否） | unit, fork | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-FR-004 | notifyEpoch / cancelRoot（asset 別 epoch・challenge window・escrow・取消） | unit, invariant=SPARD-INV-001/005 | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-FR-005 | claim（cumulative Merkle・二重 claim 不可・payout 先固定・CEI） | unit, fuzz, invariant=SPARD-INV-002 | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-FR-006 | governance 設定（reward asset 追加・share / buyback config・即時 fail-safe） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-FR-007 | pause（buyback / claim 分離・GUARDIAN 停止・GOV 再開） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-FR-008 | View 群 | unit | ☐ | N/A | | BLOCKED(未実装) | N/A: view のみ |
| SPARD-FR-009 | UUPS アップグレード（GOV 限定・storage 追記のみ） | unit, manual | ☐ | ☐ | | BLOCKED(未実装) | |

#### 13A.2 不変条件（SPARD-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SPARD-INV-001 | `totalClaimed[asset] <= totalFunded[asset]` | invariant | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-INV-002 | `claimed[account][asset]` は単調増加 | unit / fuzz | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-INV-003 | buyback は `buybackBudget[token][asset]` 内でのみ実行できる | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-INV-004 | min-out はコード強制で、呼び出し元が任意に下げられない | unit / fork | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-INV-005 | root は challenge window 経過まで claim に使えない | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-INV-006 | 本コントラクトは SP / Core 状態を変更しない | static review | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-INV-007 | cancel funding は rewardBudget に戻り、totalFunded と二重計上されない | unit / invariant | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-INV-008 | 任意 receiver / call / router による流出経路を持たない | static review | ☐ | ☐ | | BLOCKED(未実装) | |

#### 13A.3 イベント・監視要件（SPARD-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SPARD-EVT-001 | `SPAdditionalRevenueReceived(token, amount)` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-EVT-002 | `BuybackExecuted(token, asset, amountIn, amountOut, minOut)` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-EVT-003 | `EpochFunded(asset, epochId, root, amount, activatesAt)` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-EVT-004 | `RootCancelled(asset, epochId)` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-EVT-005 | `Claimed(asset, account, payout, cumulative)` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-EVT-006 | reward asset / share / buyback config 更新イベント | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPARD-EVT-007 | buyback / claim の pause・unpause イベント | unit | ☐ | ☐ | | BLOCKED(未実装) | |

#### 13A.4 未決事項レジスタ（SPARD-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| SPARD-TBD-001 | 未決 | epoch 長・challenge window・claim pause 運用 | |
| SPARD-TBD-002 | 未決 | JPYdf buyback の venue / clip / slippage / TWAP 閾値 | |
| SPARD-TBD-003 | 未決 | DFT 等を reward asset に追加する条件 | |
| SPARD-TBD-004 | 未決 | 不正 root 通過時の被害上限を縮小する追加統制（claim rate limit 等） | |

---

### 13B. Borrow Referral（BRRD）

#### 13B.1 機能要件（BRRD-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BRRD-FR-001 | initialize（role・Treasury・初期 reward asset・ゼロ/再初期化 revert） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-FR-002 | Treasury revenue 受領（onlyTreasury・`BORROW_REFERRAL` 検証・exact pull・donation 未会計） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-FR-003 | executeBuyback（reward asset 検証・予算内・価格乖離拒否・min-out を caller が下げられない） | unit, fork | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-FR-004 | epoch root 投稿・取消（ROOT_POSTER 投稿、challenge window、GUARDIAN cancelRoot） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-FR-005 | claim（Merkle proof・cumulative 差分・CEI・referrer 固定 payout） | unit, invariant=BRRD-INV-002/003/005 | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-FR-006 | governance 設定（reward asset 追加・share / buyback config・将来効） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-FR-007 | pause（buyback / claim 分離・GOV 再開） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-FR-008 | View 群 | unit | ☐ | N/A | | BLOCKED(未実装) | N/A: view のみ |
| BRRD-FR-009 | UUPS アップグレード（GOV 限定・storage 追記のみ） | unit, manual | ☐ | ☐ | | BLOCKED(未実装) | |

#### 13B.2 不変条件（BRRD-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BRRD-INV-001 | `BORROW_REFERRAL` 以外の Treasury purpose を受けない | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-INV-002 | `totalClaimed[asset] <= totalFunded[asset]` | invariant | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-INV-003 | `claimed[referrer][asset]` は単調増加 | unit / fuzz | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-INV-004 | buyback は `buybackBudget[token][asset]` 内でのみ実行できる | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-INV-005 | payout 先は Merkle leaf の `referrer` 固定。任意 payout address を引数に取らない | unit / manual | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-INV-006 | Foundation Safe への手作業支払経路を通常フローに持たない | static review | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-INV-007 | SP-deposit Referral / SP 追加報酬 / PIL budget へ流用しない | manual / static review | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-INV-008 | cancel funding は rewardBudget に戻り、totalFunded と二重計上されない | unit / invariant | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-INV-009 | 任意 receiver / call / router による流出経路を持たない | static review | ☐ | ☐ | | BLOCKED(未実装) | |

#### 13B.3 イベント・監視要件（BRRD-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BRRD-EVT-001 | `BorrowReferralRevenueReceived(token, amount)` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-EVT-002 | `BorrowReferralBuybackExecuted(token, asset, amountIn, amountOut, minOut)` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-EVT-003 | `BorrowReferralEpochFunded(asset, epochId, root, amount, campaignHash, activatesAt)` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-EVT-004 | `BorrowReferralRootCancelled(asset, epochId)` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-EVT-005 | `BorrowReferralClaimed(asset, referrer, payout, cumulative)` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-EVT-006 | reward asset / share / buyback config 更新イベント | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| BRRD-EVT-007 | buyback / claim の pause・unpause イベント | unit | ☐ | ☐ | | BLOCKED(未実装) | |

#### 13B.4 未決事項レジスタ（BRRD-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| BRRD-TBD-001 | 未決 | 借入 Referral の具体 cap、campaign period、minimum holding / clawback 条件 | |
| BRRD-TBD-002 | 未決 | epoch 長・challenge window・claim pause 運用 | |
| BRRD-TBD-003 | 未決 | payout asset の初期構成・JPYdf 以外を使う場合の価格ガード | |
| BRRD-TBD-004 | 未決 | unused budget の繰越 / Foundation 返戻 / burn 等の扱い | |
| BRRD-TBD-005 | 未決 | 将来 `jpydfAmount` 以外を rewardable volume に使う場合の event / ledger 改訂 | |

---

### 13C. SP-deposit Referral（SPDRD）

#### 13C.1 機能要件（SPDRD-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SPDRD-FR-001 | initialize（role・Treasury・初期 reward asset・ゼロ/再初期化 revert） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-FR-002 | Treasury revenue 受領（onlyTreasury・`SP_DEPOSIT_REFERRAL` 検証・source 登録・exact pull・donation 未会計） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-FR-003 | attribution source gate（sourceHash 登録・raw SP deposit source 拒否・将来 ledger のみ適用・TWAB / holding 前後 artifact） | unit, manual | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-FR-004 | executeBuyback（reward asset 検証・予算内・価格乖離拒否・min-out を caller が下げられない） | unit, fork | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-FR-005 | epoch root 投稿・取消（sourceHash 一致、ROOT_POSTER 投稿、challenge window、GUARDIAN cancelRoot） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-FR-006 | claim（Merkle proof・cumulative 差分・CEI・referrer 固定 payout） | unit, invariant=SPDRD-INV-003/004/005 | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-FR-007 | governance 設定（reward asset 追加・share / buyback config・将来効） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-FR-008 | pause（buyback / claim 分離・GOV 再開） | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-FR-009 | View 群 | unit | ☐ | N/A | | BLOCKED(未実装) | N/A: view のみ |
| SPDRD-FR-010 | UUPS アップグレード（GOV 限定・storage 追記のみ） | unit, manual | ☐ | ☐ | | BLOCKED(未実装) | |

#### 13C.2 不変条件（SPDRD-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SPDRD-INV-001 | `SP_DEPOSIT_REFERRAL` 以外の Treasury purpose を受けない | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-INV-002 | source 未登録では Treasury revenue を受けない | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-INV-003 | `totalClaimed[asset] <= totalFunded[asset]` | invariant | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-INV-004 | `claimed[referrer][asset]` は単調増加 | unit / fuzz | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-INV-005 | payout 先は Merkle leaf の `referrer` 固定。任意 payout address を引数に取らない | unit / manual | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-INV-006 | Foundation Safe への手作業支払経路を通常フローに持たない | static review | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-INV-007 | Core StabilityPool の accounting / ABI を変更しない | static review | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-INV-008 | 借入 Referral / SP 追加報酬 / PIL budget へ流用しない | manual / static review | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-INV-009 | cancel funding は rewardBudget に戻り、totalFunded と二重計上されない | unit / invariant | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-INV-010 | 任意 receiver / call / router による流出経路を持たない | static review | ☐ | ☐ | | BLOCKED(未実装) | |

#### 13C.3 イベント・監視要件（SPDRD-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SPDRD-EVT-001 | `SPDepositReferralRevenueReceived(token, amount)` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-EVT-002 | `SPDepositReferralAttributionSourceUpdated(sourceHash)` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-EVT-003 | `SPDepositReferralBuybackExecuted(token, asset, amountIn, amountOut, minOut)` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-EVT-004 | `SPDepositReferralEpochFunded(asset, epochId, root, amount, sourceHash, activatesAt)` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-EVT-005 | `SPDepositReferralRootCancelled(asset, epochId)` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-EVT-006 | `SPDepositReferralClaimed(asset, referrer, payout, cumulative)` | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-EVT-007 | reward asset / share / buyback config 更新イベント | unit | ☐ | ☐ | | BLOCKED(未実装) | |
| SPDRD-EVT-008 | buyback / claim の pause・unpause イベント | unit | ☐ | ☐ | | BLOCKED(未実装) | |

#### 13C.4 未決事項レジスタ（SPDRD-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| SPDRD-TBD-001 | 未決 | sJPYdf / wrapper / signed attribution の採用方式 | |
| SPDRD-TBD-002 | 未決 | TWAB 期間、minimum holding、withdrawal / liquidation / self-referral 除外条件 | |
| SPDRD-TBD-003 | 未決 | epoch 長・challenge window・claim pause 運用 | |
| SPDRD-TBD-004 | 未決 | payout asset の初期構成・JPYdf 以外を使う場合の価格ガード | |
| SPDRD-TBD-005 | 未決 | unused budget の繰越 / Foundation 返戻 / burn 等の扱い | |

---

## 13D. InterestRouter.md（IRTR・InterestRouterForwarder）

正本: [InterestRouter.md](../../protocol/product/spec/InterestRouter.md)。対象: `contracts/src/InterestRouterForwarder.sol`。Liquity core の immutable `interestRouter` 制約を外側の薄い受け口で吸収し、PIL 原資（集計利息残余 25%）を最終 recipient へ配送する非アップグレード補助モジュール。

### 13D.1 機能要件（IRTR-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| IRTR-FR-001 | constructor（jpydfToken / recipient / owner ゼロ拒否・初期値・初期イベント） | unit | ☐ | ☐ | | 未実施 | |
| IRTR-FR-002 | route（保持 JPYdf 全額・固定宛先・残高 0 no-op・permissionless・戻り値） | unit, invariant=IRTR-INV-001/002, integration | ☐ | ☐ | | 未実施 | |
| IRTR-FR-003 | setRecipient（owner 限定・ゼロ拒否・将来効） | unit | ☐ | ☐ | | 未実施 | |
| IRTR-FR-004 | 2-step ownership・pending 取消・renounce 無効 | unit | ☐ | ☐ | | 未実施 | |
| IRTR-FR-005 | View 群 | unit | ☐ | N/A | | 未実施 | N/A: view-only |

### 13D.2 不変条件（IRTR-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| IRTR-INV-001 | 資金流出先は recipient のみ。宛先を引数に取る送金関数・rescue は存在しない | unit / manual | ☐ | ☐ | | 未実施 | |
| IRTR-INV-002 | route は保持 JPYdf 全額を現 recipient へ送り、部分送金経路がない | unit / invariant | ☐ | ☐ | | 未実施 | |
| IRTR-INV-003 | recipient 変更は owner のみ・ゼロ不可 | unit | ☐ | ☐ | | 未実施 | |
| IRTR-INV-004 | owner は renounce 不可で、付け替え能力が strand しない | unit | ☐ | ☐ | | 未実施 | |
| IRTR-INV-005 | core への状態変更呼び出しを行わない | manual / CI | ☐ | ☐ | | 未実施 | |
| IRTR-INV-006 | DF dToken wiring では全 branch の interestRouter が同一 Forwarder を指す | deploy / handover 検証 | ☐ | ☐ | | 未実施 | |

### 13D.3 セキュリティ要件（IRTR-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| IRTR-SEC-001 | owner 鍵侵害の被害境界（recipient 変更のみ・資金流出は route の固定宛先） | unit / manual | ☐ | ☐ | | 未実施 | |
| IRTR-SEC-002 | route の permissionless 安全性 | unit | ☐ | ☐ | | 未実施 | |
| IRTR-SEC-003 | recipient ゼロ・renounce による strand 防止 | unit | ☐ | ☐ | | 未実施 | |
| IRTR-SEC-004 | reentrancy / CEI | unit / manual | ☐ | ☐ | | 未実施 | |
| IRTR-SEC-005 | pending ownership 取消の悪用境界 | unit / manual | ☐ | ☐ | | 未実施 | |

### 13D.4 ガバナンス・運用・アップグレード要件（IRTR-GOV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| IRTR-GOV-001 | ロール構成と handover | manual / deploy | ☐ | ☐ | | 未実施 | |
| IRTR-GOV-002 | deploy 入力と fail-fast | deploy / manual | ☑ | ☑ | `DeployLiquity2._verifyDFInterestRouter`; `DFGovernanceHandoverTest::{test_InterestRouterVerifierAcceptsForwarder,test_InterestRouterVerifierRejectsDirectOwnableReceiver,test_InterestRouterVerifierRejectsWrongTokenOrRecipient,test_HandoverPreflightRejectsSplitRoutersBeforeMutation}` | PASS(manual/unit) | deploy 末尾で token / recipient / owner / pendingOwner / 全 branch 同一性を検査。handover/verify/accept でも manifest と recipient を再検査 |
| IRTR-GOV-003 | Day-1 → Day-2 の配送先移行 | manual | ☐ | N/A | | 未実施 | |
| IRTR-GOV-004 | アップグレード方針（非アップグレード・再デプロイ） | manual | ☐ | N/A | | 未実施 | |
| IRTR-GOV-005 | チェーン別配線ゲート | deploy / manual | ☐ | ☐ | | 未実施 | mainnet dToken wiring 有効化前ゲート |

### 13D.5 イベント・監視要件（IRTR-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| IRTR-EVT-001 | Routed(recipient, amount) | unit | ☐ | ☐ | | 未実施 | |
| IRTR-EVT-002 | RecipientUpdated(oldRecipient, newRecipient) | unit | ☐ | ☐ | | 未実施 | constructor 初期値も含む |
| IRTR-EVT-003 | OwnershipTransferStarted / OwnershipTransferred | unit | ☐ | ☐ | | 未実施 | constructor 初期 owner も含む |

### 13D.6 失敗時・異常系挙動（§12 ERR・ID なし）

| # | 事象 | 期待挙動（doc §12） | 発火実証 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | recipient が誤っている | owner / Timelock が setRecipient で修正。過去 route 分は移動済み先で会計処理 | ☐ | | 未実施 | |
| 2 | route keeper 停止 | JPYdf は Forwarder に滞留し、誰でも route 可能。配送遅延のみ | ☐ | | 未実施 | |
| 3 | JPYdf 以外のトークン誤送付 | rescue なし。対象 token は滞留し、route は jpydfToken のみ転送 | ☐ | | 未実施 | IRTR-TBD-003 |

### 13D.7 未決事項レジスタ（IRTR-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| IRTR-TBD-001 | 未決 | PIL 専用アドレス（Day-1 recipient）の実体・mainnet 実値 | 承認済みPIL activation packageの値確定ゲート |
| IRTR-TBD-002 | Resolved（2026-06-15） | route は keeper 運用。標準入口は `frontend/ops route-interest` | Route Runbook が運用正本 |
| IRTR-TBD-003 | 未決 | 誤送トークンの rescue 有無 | 既定は rescue なし |
| IRTR-TBD-004 | 未決 | Day-2 配分機構との接続仕様 | 原則 pass-through |
| IRTR-TBD-005 | Resolved（2026-06-22） | `SP_YIELD_SPLIT` 実値は Core inherited constant として `Constants.sol` と `Liquity-v2-Core-Spec.md`（CORE-AP-FR-003/007・定数表）に正本化済み。Parameters.md は DF 調整値のみの正本で、`SP_YIELD_SPLIT` は載せない | InterestRouter は受け口仕様として参照のみ |
| IRTR-TBD-006 | Resolved（2026-06-18） | deploy 末尾の束縛検証強化は実装済み | `DeployLiquity2._verifyDFInterestRouter` が token / recipient / owner / pendingOwner / 全 branch 同一性を fail-fast。handover/verify/accept scripts も manifest と recipient を再検査 |

---

## 13E. PILAllocator.md（PILA・PILAllocator / IInitiative / UniV4MerklInitiative）

正本: [PILAllocator.md](../../protocol/product/spec/PILAllocator.md)。対象: `contracts/src/PILAllocator.sol`（235 nSLOC）・`contracts/src/Initiatives/UniV4MerklInitiative.sol`（174 nSLOC）。InterestRouterForwarder から受けた PIL を admin weight で registered initiative へ配分し、Uniswap v4 Merkl campaign へ接続する Phase-A liquidity incentive レイヤー。

> **監査スコープ上の位置づけ**: 両 contract は [Contract-Audit-Scope-And-nSLOC](../guides/Contract-Audit-Scope-And-nSLOC.md) の「Audited but gated production code」として **A full-review body に含まれる**（route / PIL gate 承認前は user-facing でも funded でもないが、設定後は資金・routing・認可に影響しうる production source であるため）。本節はその 51 ID を追跡する。Day-1 は weight 合計 0 の inert 構成で開始し、活性化は別の PIL activation package で承認する。

### 13E.1 機能要件（PILA-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PILA-FR-001 | constructor（token 非 contract・`minDistribute` ゼロ拒否、epoch 起点 / duration、owner / guardian の確立） | unit | ☑ | ☑ | `test_RevertWhen_ConstructorTokenIsNotContract`; `test_RevertWhen_ConstructorMinDistributeIsZero`; `test_LoadConfigReadsJpydfManifestAndPilaEnv` | PASS(V14) | 正常系は全 PILAllocator test の setUp と deploy config test が構築を通す |
| PILA-FR-002 | epoch インターフェース（本家 `liquity/V2-gov` 互換の `epoch()` / epoch 起点） | unit, static | ☑ | ☑ | `test_EpochInterfaceAnswersUpstreamSelectors`; `test_EpochNumberingFollowsUpstreamSemantics` | PASS(V16) | vendored upstream `IGovernance` の 4 selector（`EPOCH_START` / `EPOCH_DURATION` / `epoch` / `epochStart`）を実 allocator へ staticcall して照合。selector 一致だけでは 0-indexed や別起点でも通るため、epoch 1 の起点・境界の 1 秒前後・`floor(elapsed/duration)+1` も固定 |
| PILA-FR-003 | registerInitiative（admin 限定・JPYdf recipient 検証・登録 hook 呼び出し・`MAX_INITIATIVES` 上限） | unit | ☑ | ☑ | `test_RegisterInitiativeValidatesJpydfRecipientAndCallsHook`; `test_RevertWhen_RegisteringInvalidJpydfRecipient`; `test_RevertWhen_RegisteringMoreThanMaxInitiatives` | PASS(V14) | |
| PILA-FR-004 | unregisterInitiative（admin 限定・weight と配列からの除去・解除 hook） | unit | ☑ | ☑ | `test_UnregisterRemovesWeightAndInitiative` | PASS(V14) | |
| PILA-FR-005 | setWeights（admin 限定・重複拒否・合計 0 または `1e18`） | unit | ☑ | ☑ | `test_SetWeightsRejectsDuplicatesAndInvalidTotalWeight`; `test_SetWeightsCanDeactivateBySettingAllWeightsZero` | PASS(V14) | |
| PILA-FR-006 | distribute（weight 按分・permissionless・二重配分しない） | unit, integration | ☑ | ☑ | `test_DistributePushesByFullWeightAndRepeatedCallNoops` | PASS(V14) | 同一 epoch での再呼び出しが no-op になることを含む |
| PILA-FR-007 | 閾値・carry-over（`minDistribute` 未満と weight 全 0 では配分せず allocator に滞留） | unit | ☑ | ☑ | `test_DistributeReturnsZeroWhenBelowThresholdOrNoWeights` | PASS(V14) | |
| PILA-FR-008 | pause / unpause / setGuardian（緊急停止と担当変更） | unit | ☑ | ☑ | `test_PauseUnpauseAndOwnership`; `test_GuardianCanBeUpdatedByOwner` | PASS(V14) | |
| PILA-FR-009 | View 群（登録 initiative 配列・weight・epoch 系） | unit | ☑ | N/A | `test_UnregisterRemovesWeightAndInitiative`; `test_SetWeightsRejectsDuplicatesAndInvalidTotalWeight` | PASS(V14) | N/A: view-only。view 面だけを対象にした専用 test は無く、register / unregister / setWeights の assertion で間接的に確認している |
| PILA-FR-010 | ownership（2-step・pending 取消・renounce 無効） | unit | ☑ | ☑ | `test_PauseUnpauseAndOwnership`; `test_TransferOwnershipZeroCancelsPendingOwner` | PASS(V14) | |
| PILA-FR-101 | `IInitiative`（本家完全互換・4 hook） | unit, static | ☑ | N/A | `test_HooksAreNoopAndPhaseBReusable` | PASS(V14) | N/A: hook は no-op のため異常系なし。upstream signature parity 自体は PILA-INV-007 で追跡 |
| PILA-FR-102 | `onAfterAllocateLQTY` の保持（Phase-A 未使用だが Phase-B 流用のため残す） | unit, static | ☑ | N/A | `test_HooksAreNoopAndPhaseBReusable` | PASS(V14) | N/A: 未使用 hook |
| PILA-FR-201 | UniV4MerklInitiative constructor（Merkl 条件受諾・引数検証） | unit | ☑ | ☑ | `test_ConstructorAcceptsMerklConditions`; `test_RevertWhen_ConstructorArgsInvalid` | PASS(V14) | |
| PILA-FR-202 | createCampaign（閾値未満 no-op・keeper 優先と public fallback window・campaign 重複生成の抑止・allowance の都度クリア） | unit | ☑ | ☑ | `test_CreateCampaignNoopsBelowThreshold`; `test_CreateCampaignPullsAmountAndClearsAllowance`; `test_CreateCampaignRejectsPublicCallerBeforeFallbackWindow`; `test_CreateCampaignAllowsPublicCallerInsideFallbackWindow`; `test_CanCreateCampaignReflectsBalanceWindowAndExistingCampaign`; `test_CreateCampaignNoopsAfterCampaignForStartExists` | PASS(V14) | |
| PILA-FR-203 | getCampaignData（poolId / weight / blacklist の符号化） | unit | ☑ | N/A | `test_GetCampaignDataUsesEmptyWhitelistBlacklistAndHooks` | PASS(V14) | N/A: pure encode。Day-1 blacklist は空（PILA-TBD-003） |
| PILA-FR-204 | initiative hook（軽量 no-op） | unit | ☑ | N/A | `test_HooksAreNoopAndPhaseBReusable` | PASS(V14) | N/A: no-op |

### 13E.2 不変条件（PILA-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PILA-INV-001 | `distribute()` の流出先は登録 initiative のみ。送金先を引数に取る関数を持たない | unit / static | ☑ | N/A | `test_DistributePushesByFullWeightAndRepeatedCallNoops`; `test_UnregisterRemovesWeightAndInitiative`; code review（`PILAllocator.sol` の external surface） | PASS(V14) | N/A: 任意宛先への送金 API 自体が存在しないため異常系を作れない |
| PILA-INV-002 | `Σweight` は 0 または `1e18`。部分合計による未割当 weight を作らない | unit | ☑ | ☑ | `test_SetWeightsRejectsDuplicatesAndInvalidTotalWeight`; `test_SetWeightsCanDeactivateBySettingAllWeightsZero` | PASS(V14) | |
| PILA-INV-003 | initiative hook の revert / OOG が他 initiative への配分を阻害しない（`safeCallWithMinGas` 隔離）。hook 成否はイベントで観測できる | unit / fuzz | ☑ | ☑ | `test_DistributeIsolatesFailingHookAfterTransfer`; `test_DistributeIsolatesRevertBombHookAfterTransfer`; `test_DistributeBlocksReentrantHookAndContinues` | PASS(V14) | `Distributed` の `hookSucceeded` を `expectEmit` で確認（PILA-EVT-004 と同一証跡） |
| PILA-INV-004 | initiative 0 件 / weight 全 0 のとき全 PIL は allocator に滞留する（活性化非依存） | unit / integration | ☑ | N/A | `test_DistributeReturnsZeroWhenBelowThresholdOrNoWeights`; `test_SetWeightsCanDeactivateBySettingAllWeightsZero` | PASS(V14) | N/A: 滞留が期待挙動そのもの |
| PILA-INV-005 | 🔵 Core / `JpydfToken` / `InterestRouterForwarder` への状態変更呼び出しを行わない（受領のみ） | manual / static | ☑ | N/A | 静的検査（`PILAllocator.sol` の外部呼び出し全列挙、develop `a09d1620`） | PASS(V17) | N/A: 呼び出し自体が存在しないため異常系なし。外部との相互作用は次の 3 つで全部: (1) `jpydfToken.safeTransfer`（FR-006 が規定する pass-through）、(2) `_safeCallWithMinGas` の assembly `call`（宛先は登録 initiative のみ）、(3) `IJpydfToken.requireValidRecipient`（`internal view` 内の read-only）。`InterestRouterForwarder` / Liquity Core contract への参照は grep 0 件で、mint / burn / `setBranchAddresses` 等の特権 surface も呼ばない |
| PILA-INV-006 | 登録・解除・weight・unpause は共通 Timelock 経由でしか実行できない（即時は GUARDIAN の pause のみ） | unit / manual | ☑ | ☑ | `test_RequireConfigRejectsMainnetCodelessAdminRoles`; `test_RequireConfigAllowsMainnetContractAdminRoles`; `test_PauseUnpauseAndOwnership` | PASS(V14) | deploy config 側で mainnet の admin ロールが contract（= Timelock / Safe）であることを強制。実 handover の証跡は role handover evidence（#1150）の所管 |
| PILA-INV-007 | `IInitiative` は本家 `liquity/V2-gov` とシグネチャ完全一致（Phase-B で同一 initiative を無改変流用できる） | static / 差分検査 | ☑ | ☑ | `test_InitiativeHookSelectorsMatchUpstream`; `test_InitiativeHookSignaturesAreCanonical` | PASS(V16) | `lib/V2-gov` の upstream `IInitiative` を直接 import して 4 hook の selector を照合。DF は struct をローカル再宣言するため、tuple 展開後の canonical signature も固定。変異確認: `UserState.unallocatedOffset` を `uint256`→`uint128` にすると両 test が FAIL |
| PILA-INV-008 | 登録 initiative 数は `MAX_INITIATIVES=32` 以下。`distribute()` のループが unbounded にならない | unit / manual | ☑ | ☑ | `test_RevertWhen_RegisteringMoreThanMaxInitiatives` | PASS(V14) | |

### 13E.3 セキュリティ要件（PILA-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PILA-SEC-001 | Merkl 依存の信頼境界（`DistributionCreator` の正本化・条件受諾・手数料モデル） | manual / fork | ☐ | ☐ | | 未実施 | mainnet Merkl アドレスと手数料実額の確認は PILA-TBD-004 の activation gate。unit test は mock 相手 |
| PILA-SEC-002 | admin 鍵侵害の被害境界（任意宛先送金不可・上限つき配分先のみ） | manual / static | ☑ | N/A | 静的レビュー（認可マップ全列挙、develop `a09d1620`）＋ `test_DistributePushesByFullWeightAndRepeatedCallNoops`; `test_RevertWhen_RegisteringInvalidJpydfRecipient` | PASS(V17) | N/A: 単一 tx の窃取経路が存在しないため異常系を作れない。認可マップ: owner 限定 = `registerInitiative` / `unregisterInitiative` / `setWeights` / `unpause` / `setGuardian` / `transferOwnership` / `renounceOwnership`（無効化・`view`）、guardian 限定 = `pause`、permissionless = `distribute` / `acceptOwnership`。資金の宛先を引数に取る関数は存在しない（INV-001）。侵害された owner でも 1 tx では奪えず、initiative 登録（`requireValidRecipient` 通過が必要）→ weight 設定 → 誰かの `distribute()` を要し、前 2 者は Timelock 経由（INV-006）かつ EVT-001 / EVT-003 で観測できる。spec §9 の列挙が `setGuardian` / ownership を落としていたため本 PR で追記 |
| PILA-SEC-003 | Merkl approve は都度・キャンペーン額限定（本家の max approve からのハードニング） | unit | ☑ | ☑ | `test_CreateCampaignPullsAmountAndClearsAllowance` | PASS(V14) | pull 後に allowance が 0 に戻ることを確認 |
| PILA-SEC-004 | initiative 隔離（1 つの initiative の失敗が他へ波及しない） | unit | ☑ | ☑ | `test_DistributeIsolatesFailingHookAfterTransfer`; `test_DistributeIsolatesRevertBombHookAfterTransfer` | PASS(V14) | revert bomb（巨大 returndata）を含む |
| PILA-SEC-005 | reentrancy / CEI | unit | ☑ | ☑ | `test_DistributeBlocksReentrantHookAndContinues`; `test_CreateCampaignBlocksReentrantMerklCallback` | PASS(V14) | allocator 側 hook と Merkl callback の双方向 |
| PILA-SEC-006 | permissionless 起動と campaign 早押し防止（keeper 優先 window・生成済み campaign の再生成抑止） | unit | ☑ | ☑ | `test_CreateCampaignRejectsPublicCallerBeforeFallbackWindow`; `test_CreateCampaignAllowsPublicCallerInsideFallbackWindow`; `test_CreateCampaignNoopsAfterCampaignForStartExists` | PASS(V14) | |

### 13E.4 ガバナンス・運用・アップグレード要件（PILA-GOV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PILA-GOV-001 | ロール構成と handover（owner = Timelock / guardian 分離） | unit / manual | ☑ | ☑ | `test_RequireConfigRejectsMainnetCodelessAdminRoles`; `test_RequireConfigAllowsMainnetContractAdminRoles`; `test_DeploymentSaltRequiresExplicitSaltOnMainnet` | PASS(V14) | deploy config gate まで。実 handover 実行の evidence は #1150 の所管 |
| PILA-GOV-002 | 上流接続（`forwarder.setRecipient(PILAllocator)`） | integration / manual | ☐ | ☐ | | 未実施 | Forwarder→allocator→distribute→Merkl の一気通貫 integration が未実施 |
| PILA-GOV-003 | Phase-A 稼働（activation）と activation-agnostic 性 | manual | ☐ | N/A | | 未実施 | Day-1 は weight 合計 0 の inert 構成。活性化承認は PIL activation package |
| PILA-GOV-004 | Phase-A → Phase-B（投票型配分）移行 | manual | ☐ | N/A | | 未実施 | Day-2 事項 |
| PILA-GOV-005 | 拡張境界（initiative の追加・Curve 系は Phase-A スコープ外） | manual | ☐ | N/A | | 未実施 | Day-2 事項 |
| PILA-GOV-006 | アップグレード方針（非 upgradeable・差し替えは新 instance ＋ 登録替え） | manual / static | ☑ | N/A | 静的確認（継承・upgrade surface の全列挙、develop `a09d1620`） | PASS(V17) | N/A: upgrade 経路が存在しないため異常系なし。`contract PILAllocator is ReentrancyGuard` / `contract UniV4MerklInitiative is IInitiative, ReentrancyGuard` のみで、`Initializable` / UUPS / proxy 継承なし、`initialize` / `upgradeTo` なし、`delegatecall` 0 件（assembly 2 箇所は `call` と gas 算術）。venue / 設定値は全て `immutable` |

### 13E.5 イベント・監視要件（PILA-EVT）

| ID | 要件（要約） | 規定検証手段 | 発火実証 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- |
| PILA-EVT-001 | `InitiativeRegistered(initiative, atEpoch, hookSucceeded)` | unit | ☑ | `test_RegisterInitiativeValidatesJpydfRecipientAndCallsHook`（`expectEmit`） | PASS(V16) | |
| PILA-EVT-002 | `InitiativeUnregistered(initiative, atEpoch, hookSucceeded)` | unit | ☑ | `test_UnregisterRemovesWeightAndInitiative`（`expectEmit`） | PASS(V16) | |
| PILA-EVT-003 | `WeightsUpdated(initiatives, weights)` | unit | ☑ | `test_SetWeightsCanDeactivateBySettingAllWeightsZero`（`expectEmit`） | PASS(V16) | weight 全 0 への非活性化更新で、両 initiative と weight 配列が載ることを確認 |
| PILA-EVT-004 | `Distributed(initiative, amount, epoch, hookSucceeded)` | unit | ☑ | `test_DistributeIsolatesFailingHookAfterTransfer`（`expectEmit` で `hookSucceeded` false / true の両方を確認） | PASS(V14) | |
| PILA-EVT-005 | `NewMerklCampaign(epoch, amount, campaignId)` / `MerklCampaignAlreadyCreated(epoch, startTimestamp, amount, campaignId)` | unit | ☑ | `test_CreateCampaignPullsAmountAndClearsAllowance`（`expectEmit`）; `test_CreateCampaignNoopsAfterCampaignForStartExists`（`expectEmit`） | PASS(V16) | 重複抑止側の `amount` は累計ではなく発火時点の initiative 残高 |
| PILA-EVT-006 | `Paused()` / `Unpaused()` | unit | ☑ | `test_PauseUnpauseAndOwnership`（両方向 `expectEmit`） | PASS(V16) | |
| PILA-EVT-007 | `GuardianUpdated(oldGuardian, newGuardian)` | unit | ☑ | `test_GuardianCanBeUpdatedByOwner`（`expectEmit`） | PASS(V16) | 変異確認: 引数順を入れ替えると FAIL |

### 13E.6 未決事項レジスタ（PILA-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| PILA-TBD-001 | 未決 | 対象 Uniswap v4 プール（Day-1 は `JPYdf/USDC` 1 プール前提。複数ペアの要否） | PIL activation package の値確定ゲート |
| PILA-TBD-002 | 未決 | 配分パラメータ（`EPOCH_DURATION` / `minDistribute` / campaign 閾値 / creator / window） | 候補値は Parameters.md `PRM-PILA-*`。freeze は activation package |
| PILA-TBD-003 | 未決 | blacklist の方式（Day-1 は空・対象者なし） | 既定は immutable-empty |
| PILA-TBD-004 | 未決 | Merkl 依存の確定（`DistributionCreator` 正本アドレス・条件受諾・手数料実額） | PILA-SEC-001 の activation gate |
| PILA-TBD-005 | 未決 | approve 範囲の最終確定（都度 approve のまま固定するか） | PILA-TBD-004 の手数料実額確認を反映して判断 |
| PILA-TBD-006 | Resolved | `PILA-GOV-003` に反映済み | |
| PILA-TBD-007 | Resolved | `PILA-FR-001` と要件 ID 規約に反映済み | |
| PILA-TBD-008 | Resolved | `SYS-FR-009` と各 documents index に反映済み | |
---

## 14. Frontend.md（FRNT・オフチェーン）

正本: [Frontend.md](../../protocol/product/spec/Frontend.md)。検証手段の種別は同 doc §13 の定義（unit / component / e2e-local / build / ci-guard / visual / manual / monitor）。e2e-local は anvil → deploy → subgraph → frontend の一気通貫環境で行う。FR の規定検証手段は各 FR の個別 Verification を転記（§13 の領域行はサマリー）。SEC / ERR / INV は §13 の領域主検証を適用する。

### 14.1 機能要件（FRNT-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FRNT-FR-001 | チェーン・コントラクトバインディングの機械生成 | build / ci-guard / e2e-local | ☐ | ☐ | | 未実施 | |
| FRNT-FR-002 | オンチェーン定数の単一ソース化 | ci-guard / unit | ☐ | ☐ | | 未実施 | |
| FRNT-FR-003 | ABI・型の機械生成 | build / ci-guard | ☐ | ☐ | | 未実施 | |
| FRNT-FR-004 | 環境設定スキーマの fail-fast 検証 | build / unit | ☐ | ☐ | | 未実施 | リリースゲート（§14.7） |
| FRNT-FR-005 | ウォレット接続 | e2e-local / manual | ☐ | ☐ | | 未実施 | |
| FRNT-FR-006 | トランザクションライフサイクル | e2e-local / component / unit | ☐ | ☐ | | 未実施 | |
| FRNT-FR-007 | 承認（approve / permit）の最小化と明示 | e2e-local / component | ☐ | ☐ | | 未実施 | |
| FRNT-FR-008 | データソースの役割分離と鮮度管理 | e2e-local / unit / monitor | ☑ | ☐ | `frontend/ops/src/lib/publicStats.ts`; `frontend/ops/scripts/public-stats.test.ts`; `.github/workflows/frontend-tests.yml` | 部分実施 | DF 管理の公開 stats JSON を RPC snapshot から生成。subgraph 鮮度・app 接続・APR 時系列は継続 |
| FRNT-FR-009 | JPY 建て表示・数値規約 | unit / visual / component | ☐ | ☐ | | 未実施 | |
| FRNT-FR-010 | 国際化（i18n） | build / component | ☐ | ☐ | | 未実施 | 提供順序は FRNT-TBD-008 |
| FRNT-FR-011 | JPY DeFi / JPYdf ブランド表記（上流ブランド差替・全数 grep） | visual / ci-guard（文言 lint）/ manual | ☐ | ☐ | | 未実施 | |
| FRNT-FR-012 | 8 ブランチの動的サポート | e2e-local / component / unit | ☐ | ☐ | | 未実施 | |
| FRNT-FR-013 | 借入フロー（1 Tx 集約） | e2e-local / component | ☐ | ☐ | | 未実施 | production PASS は CYZ / SkyZapper の manifest・binding・user app 採用後。現行 multi-step fallback は暫定 UX |
| FRNT-FR-014 | ポジション管理（調整・返済・クローズ・金利変更） | e2e-local / component | ☐ | ☐ | | 未実施 | dToken branch の collateral-funded repay / flash close は Day-1 ABI に存在しない。将来提供時は ZAP-TBD-010 と asset-specific reverse route を満たす新 entrypoint / adapter が必要 |
| FRNT-FR-015 | dToken 担保管理（mint / redeem） | e2e-local / component | ☐ | ☐ | | 未実施 | |
| FRNT-FR-016 | 遅延償還キューと claim | e2e-local / component | ☐ | ☐ | | 未実施 | |
| FRNT-FR-017 | Earn（Stability Pool） | e2e-local / component | ☐ | ☐ | | 未実施 | SP 追加報酬は FRNT-TBD-003 まで非表示 |
| FRNT-FR-018 | Redemption | e2e-local / component | ☐ | ☐ | | 未実施 | |
| FRNT-FR-019 | ブランチ健全性と backing 比の表示 | e2e-local / component / visual | ☐ | ☐ | | 未実施 | |
| FRNT-FR-020 | ポジション・履歴の一覧性 | e2e-local / component | ☐ | ☐ | | 未実施 | |
| FRNT-FR-021 | リスク・免責表示 | visual / manual / component | ☐ | ☐ | | 未実施 | |
| FRNT-FR-022 | 上流ガバナンス UI（Stake）の無効化 | visual / build | ☐ | ☐ | | 未実施 | |
| FRNT-FR-023 | Multiply（レバレッジ）の削除（route / tx-flow / env flag なし） | build / visual | ☐ | ☐ | | 未実施 | FRNT-TBD-002 / ZAP-TBD-004 / ZAP-TBD-010 |
| FRNT-FR-024 | 特権操作の「準備と可視化」モデル | e2e-local / component / manual | ☐ | ☐ | | 未実施 | |
| FRNT-FR-025 | パラメータ変更の提案ビルダー | unit / component / e2e-local | ☑ | ☑ | `pnpm --filter @jpydf/console build`; static `writeoffStrategyPrincipal` calldata-shape check | PASS(V3) | `writeoffStrategyPrincipal` の 3 引数 calldata、Strategy weight/cap 入力 guard を確認 |
| FRNT-FR-026 | オラクル source 差替フロー | e2e-local / component | ☐ | ☐ | | 未実施 | |
| FRNT-FR-027 | 緊急操作（pause / unpause・二重確認・告知バナー） | e2e-local / manual | ☐ | ☐ | | 未実施 | |
| FRNT-FR-028 | ALLOCATOR 運用画面 | e2e-local / component | ☐ | ☐ | | 未実施 | |
| FRNT-FR-029 | timelock・保留操作キュー | component / e2e-local / manual | ☐ | ☐ | | 未実施 | |
| FRNT-FR-030 | 操作証跡 | e2e-local / manual | ☐ | ☐ | | 未実施 | |
| FRNT-FR-031 | ブランチ概況の監視 | e2e-local / visual / monitor | ☐ | ☐ | | 未実施 | |
| FRNT-FR-032 | オラクル監視 | e2e-local / monitor / visual | ☐ | ☐ | | 未実施 | |
| FRNT-FR-033 | Vault・Strategy 監視 | e2e-local / monitor / visual | ☐ | ☐ | | 未実施 | |
| FRNT-FR-034 | Treasury・収益フロー監視 | e2e-local / visual | ☑ | ☐ | `frontend/ops export-treasury-ledger`; `frontend/ops/scripts/treasury-ledger.test.ts` | 部分実施 | Day-1 Safe 留保台帳を実装。Treasury.sol / SPAdditionalRewardDistributor / BorrowReferralRewardDistributor / SPDepositReferralRewardDistributor 導入後の分配表示は Day-2 残タスク |
| FRNT-FR-035 | アラート連携 | monitor / manual | ☐ | ☐ | | 未実施 | |
| FRNT-FR-036 | 公開トランスペアレンシー | visual / manual | ☑ | ☐ | `frontend/ops export-stats`; `frontend/ops/scripts/public-stats.test.ts` | 部分実施 | 供給量・担保価値・ブランチ健全性・backing 比の公開 JSON を生成。production 配信手順は未確定 |

### 14.2 整合不変条件（FRNT-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FRNT-INV-001 | 表示とオンチェーンの一致（確認画面の金額・レート・手数料は同一参照ブロックの RPC 由来） | unit / component / monitor | ☐ | ☐ | | 未実施 | |
| FRNT-INV-002 | 定数ミラー一致（Constants.sol / Parameters.md と CI 機械突合） | build / ci-guard | ☐ | ☐ | | 未実施 | リリースゲート |
| FRNT-INV-003 | シミュレーションなしに署名要求しない | e2e-local / component | ☐ | ☐ | | 未実施 | |
| FRNT-INV-004 | 秘密の不在（配布物・リポ・公開環境変数に秘密鍵・特権 API キー・個人情報なし） | ci-guard / build / manual | ☐ | ☐ | | 未実施 | |

### 14.3 セキュリティ要件（FRNT-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FRNT-SEC-001 | サプライチェーン（lockfile 固定・依存監査・第三者ドメインコード排除） | ci-guard / build / manual | ☐ | ☐ | | 未実施 | リリースゲート |
| FRNT-SEC-002 | 配信完全性（DNSSEC・会社管理・CSP / SRI） | ci-guard / build / manual | ☐ | ☐ | | 未実施 | |
| FRNT-SEC-003 | 表示の完全性（外部由来文字列の無害化・アドレス全桁確認） | ci-guard / build / manual | ☐ | ☐ | | 未実施 | |
| FRNT-SEC-004 | 承認の安全（spender は既知コントラクト限定・任意アドレス承認の不提供） | ci-guard / build / manual | ☐ | ☐ | | 未実施 | |
| FRNT-SEC-005 | フィッシング耐性（公式リンク単一台帳・rel 属性） | ci-guard / build / manual | ☐ | ☐ | | 未実施 | |
| FRNT-SEC-006 | プライバシー（解析オプトイン・アドレスと PII の非紐付け） | ci-guard / build / manual | ☐ | ☐ | | 未実施 | |
| FRNT-SEC-007 | 管理サーフェス分離（公開アプリから到達不可・別配信）+ 公開 Ops bundle 境界 | ci-guard / build / manual | ☐ | ☐ | | 未実施 | |
| FRNT-SEC-008 | エンドポイント鍵（browser read credential は共有可・公開扱い・全 domain 制限・合算利用量上限・失効可能） | ci-guard / build / manual | ☐ | ☐ | | 未実施 | |

### 14.4 ガバナンス・運用・アップグレード要件（FRNT-GOV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FRNT-GOV-001 | 資産の会社所有（ドメイン・ホスティング・RPC / subgraph・解析・統計 API） | manual（台帳定義） | ☐ | N/A | | 未実施 | N/A: 資産所有の確認項目 |
| FRNT-GOV-002 | リリース管理（バージョン・ソースコミット対応・ロールバック手順） | manual / build（台帳定義） | ☐ | ☐ | | 未実施 | |
| FRNT-GOV-003 | 変更管理と要件トレース（仕様変更はまず FRNT-ID へ・実装 PR が ID 参照） | manual（台帳定義） | ☐ | N/A | | 未実施 | N/A: プロセス遵守の確認項目 |
| FRNT-GOV-004 | 上流追随（Liquity v2 app 更新の定期取り込み・差分台帳） | manual（台帳定義） | ☐ | N/A | | 未実施 | N/A: 定期運用プロセスの確認項目 |
| FRNT-GOV-005 | 監査受け入れ（FR / INV / SEC の「実装 × 検証手段」台帳・未カバー 0） | 本台帳そのもの | ☐ | N/A | | 未実施 | §14 全行の完了で充足 |

### 14.5 テレメトリ・監視要件（FRNT-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FRNT-EVT-001 | クライアント例外収集（PII なし・リリース単位の回帰検知） | monitor / manual（台帳定義） | ☐ | ☐ | | 未実施 | |
| FRNT-EVT-002 | 合成監視（死活・RPC / subgraph 応答・主要画面描画） | monitor（台帳定義） | ☐ | ☐ | | 未実施 | |
| FRNT-EVT-003 | tx 成否計測（送信数・失敗率・revert 理由集計） | monitor（台帳定義） | ☐ | ☐ | | 未実施 | |

### 14.6 失敗時・異常系挙動（FRNT-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FRNT-ERR-001 | RPC 障害（フォールバック・全系統不通時の縮退表示・書き込み停止） | e2e-local / component / manual | ☐ | ☐ | | 未実施 | |
| FRNT-ERR-002 | subgraph 劣化（鮮度警告・現在値系との視覚区別） | e2e-local / component / manual | ☐ | ☐ | | 未実施 | |
| FRNT-ERR-003 | チェーン不一致（書き込み UI ブロック・切替導線） | e2e-local / component / manual | ☐ | ☐ | | 未実施 | |
| FRNT-ERR-004 | tx 失敗（カスタムエラーデコード・人間可読理由・再試行導線） | e2e-local / component / manual | ☐ | ☐ | | 未実施 | |
| FRNT-ERR-005 | ブランチ異常（oracle 障害・shutdown・pause 検出で新規操作ブロック） | e2e-local / component / manual | ☐ | ☐ | | 未実施 | |
| FRNT-ERR-006 | インシデント告知（コード変更なしの全画面バナー） | e2e-local / component / manual | ☐ | ☐ | | 未実施 | |

### 14.7 受け入れの原則（doc §13）

| # | 原則 | 充足条件 | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| 1 | docs ↔ code parity | 実装・テスト・PR が FRNT-ID を参照し、全 FR / INV / SEC が本台帳で未カバー 0（FRNT-GOV-005） | 未実施 | |
| 2 | e2e-local を一級の受け入れ手段とする | ローカル一気通貫環境で主要フロー（借入→調整→Earn→redeem→claim）が再現可能 | 未実施 | |
| 3 | リリースゲート | FRNT-INV-002・FRNT-FR-004・FRNT-SEC-001 を CI 必須ゲート化 | 未実施 | |

### 14.8 未決事項レジスタ（FRNT-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| FRNT-TBD-001 | 未決 | DFT ステーキング・ガバナンス UI（FRNT-FR-022 の置き換え） | |
| FRNT-TBD-002 | 未決 | Multiply 再導入条件（JPYdf DEX 流動性・JPYdf/USDC Uniswap v4 final leg・asset-specific pre-leg・dToken leverage 設計）→ FRNT-FR-023 は route / tx-flow / env flag 不在で検証 | ZAP-TBD-004 / ZAP-TBD-010 / Liquidity-Route-Policy と連動。Curve と USDT/USDS/WETH/XAUT JPYdf 直接 pool は Day-1 gate 条件に含めない |
| FRNT-TBD-003 | 未決 | SP 追加報酬・Treasury 分配の表示（確定まで非表示）→ FRNT-FR-017/034 は非表示状態で検証 | |
| FRNT-TBD-004 | 部分解決 | 初期 backend として `frontend/ops export-stats` の公開健全性 JSON を実装し、`frontend/app/src/protocol-stats.ts` が `NEXT_PUBLIC_PROTOCOL_STATS_URL` から同 JSON を読める。production hosting/会社所有/runtime health は `Frontend-Production-Delivery-Gate.md` の evidence 採取へ移管。APR 時系列は Day-2 | FRNT-TBD-007 / FRNT-GOV-001 と連動 |
| FRNT-TBD-005 | 部分解決 | 管理者コンソール production gate は `documents/jp/contributors/deltaforesight/delivery-plans/Admin-Console-Production-Gate.md` で定義済み。残る未決は実 production domain / IdP / RPC key / noindex / role snapshot / Safe calldata evidence の採取 | FRNT-SEC-007 / FRNT-SEC-008 / FRNT-GOV-001 と連動 |
| FRNT-TBD-006 | 部分解決 | ミラー配信（IPFS / ENS）は Day-1 採用しない。公式 HTTPS origin を canonical とし、Day-2 optional の採用 gate / 対象外 / No-Go / evidence は `documents/jp/contributors/deltaforesight/delivery-plans/Frontend-Mirror-Delivery-Policy.md` で定義済み。残る未決は実 mirror URL / CID / ENS / domain allowlist / incident announcement / rollback evidence の採取 | FRNT-SEC-002 / FRNT-SEC-005 / FRNT-SEC-008 / FRNT-GOV-001 と連動 |
| FRNT-TBD-007 | 部分解決 | user app / ops / public stats JSON の production delivery gate は `documents/jp/contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md` で定義済み。残る未決は実 production domain / account / endpoint / monitoring / rollback evidence の採取 | FRNT-SEC-002 / FRNT-SEC-005 / FRNT-SEC-008 / FRNT-GOV-001 と連動 |
| FRNT-TBD-008 | 部分解決 | i18n の mainnet gate は `documents/jp/contributors/deltaforesight/delivery-plans/Frontend-UX-Readiness-Gate.md` で定義済み。残る未決は primary locale / exposed locale switch / reachable screen copy evidence の採取 | FRNT-FR-009 / FRNT-FR-010 / FRNT-ERR-004 と連動 |
| FRNT-TBD-009 | 部分解決 | mobile / in-wallet browser の mainnet gate は `documents/jp/contributors/deltaforesight/delivery-plans/Frontend-UX-Readiness-Gate.md` で定義済み。残る未決は viewport / wallet modal / tx confirmation / failure state evidence の採取 | FRNT-ERR-004 / FRNT-EVT-002 と連動 |

---

## 15. Multichain.md（MCHN・検証対象外の明示宣言）

[Multichain.md](../../archive/Multichain.md) は **Deprecated / Out of Scope の履歴資料**（ADR-004 / SYS-FR-006 / README「履歴 ID として凍結」）。`MCHN-*` 全 41 ID（MCHN-FR-001..013 / MCHN-INV-001..008 / MCHN-SEC-001..006 / MCHN-GOV-001..005 / MCHN-EVT-001..006 / MCHN-TBD-001..003）は**現行実装・監査の active 要件ではないため検証対象外**とする。これは省略ではなく明示的な除外であり、将来マルチチェーン要件が active 化された場合は本台帳に専用セクションを追加する。Day-1 の bridge-ready dormant extension は `CORE-BT-*`、Product Overview の `SYS-*`、Architecture Decision Records の `ADR-*` が正本であり、MCHN-* を再利用しない。

ただし「active bridge / 他チェーン発行が未稼働であること」自体は検証対象（下記 1 行。SYS-FR-006 / SYS-CON-004 / SYS-INV-003 / ADR-004 行と同根）:

| # | チェック項目 | 規定検証手段（台帳定義） | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Day-1 manifest / deploy state で bridge minter 0 件・pending proposal なし。他チェーン発行経路・adapter 接続なし | manifest / deploy state review ＋ JpydfToken supply path unit | ☐ | ☐ | `JpydfTokenTest::test_BridgeReadinessIsDormantAfterCoreSetup` | PASS | MCHN-* は対象外のまま。Day-2 以降の minter registration / route open / cap ramp は [Bridge-Minter-Activation-Gate](../../protocol/operations/runbooks/Bridge-Minter-Activation-Gate.md) Stage A/B/C と CORE-BT-GOV-001 / CORE-BT-INV-004 の対象 |

---

## 16. 完了基準・改訂規則

### 16.1 完了基準（監査受け入れ）

以下をすべて満たしたとき、「要件定義されているものがすべてローカル環境で実装・検証されている」と主張できる:

1. **網羅**: 正本 doc から抽出した全 ID（§3 の集計と一致）が本台帳に存在し、欠番・対象外（MCHN・未決 TBD）はすべて理由付きで明示されている。
2. **全行クローズ**: 全行の結果が `PASS` または `N/A(理由)`。`未実施` / `FAIL` / `BLOCKED` が残る間は完了と書かない（BLOCKED はゲート解消後に再開）。
3. **正常系・異常系**: 各 ID の正常系・異常系がともに `✅` または `N/A(理由)`。
4. **証跡**: 全 PASS 行にテスト実体（実行ログ転記）とキャンペーン ID があり、§2 から commit SHA・実行コマンドへ遡れる。
5. **二重チェック**: docs の ID 全集合と本台帳の ID 全集合の機械 diff（grep ベース）が空であることを、キャンペーンごとに再確認する（doc は更新され続けるため）。

### 16.2 改訂規則

- 正本 doc に ID が追加・改訂されたら、本台帳に行を追加・更新する（**doc 側の改訂が先・台帳が追随**。逆方向の規定はしない）。
- ID は doc の append-only 規約に従う。台帳側で独自 ID を発番しない（非 ID チェック行は表内の # 連番と内容文で識別する）。
- テスト名・結果は本台帳のみが持つ。正本 doc へ書き戻さない（ドキュメント標準ガードレール 1・2 の遵守）。
- 検証中に仕様と実装の矛盾を発見した場合: 要件定義を正として FAIL を記録 → issue 起票 → 修正後に再検証。要件側が誤っている場合は doc 改訂（PR）を先に行い、その後台帳を更新する。

### 16.3 関連文書

- [要件定義ドキュメント標準](../../Requirements-Spec-Standard.md) — ID 規約・「テスト名は doc に書かない」ガードレールの正本
- [Development-Plan.md](../plans/Development-Plan.md) — 現在の作業・監査完了条件
- [Governance-Roles-Timelock.md](../../protocol/product/policies/Governance-Roles-Timelock.md) — §12.4 ガバナンス遅延統制の設計正本
- `engineering/historical-reviews/` — manual 検証（構成レビュー・runbook レビュー）の記録置き場
