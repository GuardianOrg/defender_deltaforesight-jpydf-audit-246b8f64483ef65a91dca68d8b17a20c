# コア検証台帳（Core Requirements Verification Ledger）— parity ローカルテスト実施記録

## 0. 目的と位置づけ

本書は、[Liquity-v2-Core-Spec.md](../../protocol/product/spec/Liquity-v2-Core-Spec.md)（コア継承仕様・正本。JpydfToken の `CORE-BT-*` は [JpydfToken.md](../../protocol/product/spec/JpydfToken.md) に分離・namespace 維持）に付与された**すべての `CORE-*` ID** が、ローカル環境の実装とテストで検証されていることを記録する台帳である。コアの検証目標は同 spec §13 のとおり 2 点に集約される:

1. **parity** — コアの全コントラクト・全関数・全状態変数が、フォーク元（リポジトリ内 `base` ブランチ = liquity/bold v1.11.0 凍結）と同一に機能すること。
2. **DF 差分の限定性** — DF がコアに加えた差分が差分台帳（spec §2.2 `CORE-MOD-*`）どおりに実装され、**それ以外の差分が存在しない**こと。

- **対象**: `CORE-<SCOPE>-<FR|INV|SEC|GOV|EVT|ERR>-NNN` の全 ID ＋ `CORE-MOD-*`（差分台帳）＋ spec §13.3 受け入れ基準（非 ID チェック行）＋ `CORE-*-TBD`（未決レジスタ）。**ID を振られているものは例外なく本書に 1 行を持つ**（検証対象外も理由付きで行として残す）。
- **根拠**: [要件定義ドキュメント標準](../../Requirements-Spec-Standard.md)のガードレール「テスト名・実行結果は仕様本文に書かない。ID 連携は一方向（テスト・台帳が doc の ID を参照する）」の受け側＝「ID × 実テスト × 実行結果」の正本が本書である（spec §13 末尾の規定と対）。
- **規範スタンスとの関係（重要）**: 🔵 要件は「base 実装挙動の記述的規範化」であり、**spec と実装の矛盾を発見した場合は base 実装が正＝spec 側を改訂する**（spec §2.4。component spec の「要件が正・実装を直す」と逆向き）。FAIL の扱いは §1.3 判定原則 8 を参照。
- **全体台帳との関係**: `documents/jp` 全体の要件検証台帳（Requirements-Verification-Ledger）が整備される場合、コア（`CORE-*`）の検証記録は**本書を正本**とし、全体台帳側のコア節は本書への参照とする（二重記録しない）。
- **監査人向け**: 本書から (1) 全 `CORE-*` ID の網羅、(2) ID ごとの正常系・異常系の実証、(3) 証跡（コミット SHA・実行コマンド・テスト名・結果）に遡れる。

> 検証対象の実装: `deltaforesight/jpydf-v2`（`develop`。検証時点の head SHA を §2 に記録する）。

---

## 1. 運用ルール（記入・判定）

### 1.1 行の構成（共通スキーマ）

列構成は全体台帳（Requirements-Verification-Ledger）と同一互換とする。

| 列 | 内容 |
| --- | --- |
| ID | `CORE-*` ID（正本 spec の ID をそのまま使う。台帳側で新 ID を発番しない） |
| 要件（要約） | spec の見出し・表記の短縮転記。**期待挙動の正本は spec の当該 ID 本文**（要約が spec と食い違う場合は spec を正とする） |
| 規定検証手段 | spec の各要件 `Verification` 指定の転記（`parity` / unit / fuzz / invariant=INV-ID / fork / integration / deploy 検証 / manual。語彙の定義は spec §13.1）。spec に指定が無い行は `（台帳定義）` を付す |
| 正常系 | `☐` → 実証済みなら `✅`、適用不能なら `N/A`（理由を備考へ） |
| 異常系 | 同上 |
| テスト実体 | `テストコントラクト::テスト関数`（複数可）または manual 検証記録への参照。**実行ログから転記する（実在しないテスト名を書かない）** |
| 結果 | `未実施` / `PASS` / `FAIL`（issue 参照必須） / `BLOCKED(理由)` / `N/A(理由)` |
| 備考 | キャンペーン ID（§2）・skip の正体・N/A 理由・欠番等 |

- 生成時の初期値はすべて `☐ / ☐ / 未実施`。**片系が存在しない行（view のみ・発火唯一条件等）の `N/A(理由)` 確定は初回キャンペーン（V1）で行い、空欄のまま完了扱いにしない。**

### 1.2 正常系・異常系のカテゴリ別定義（コア版）

全体台帳の定義を継承しつつ、🔵（parity 対象）に固有の読み替えを加える。

| カテゴリ | 正常系で実証すること | 異常系で実証すること |
| --- | --- | --- |
| FR 🔵 | 事前条件成立時に spec 記載の動作（Effects・戻り値・発火イベント）が成立する＝**base と同一挙動**（upstream 由来スイートの DF パラメータ下での全緑、または DF 追加テスト） | spec 記載の**各 revert / 早期 return / 境界条件**が 1 つ以上のテストで実際に発火する |
| FR 🟡 | base 挙動＋**台帳（CORE-MOD）どおりの差分のみ**が成立する（例: same-block 出金ガードの発火と翌ブロック成功） | 差分が「それ以外の挙動変化を持たない」こと（copy-parity: ガード以外の全挙動が StabilityPool と同一） |
| INV | 正常運用の操作列の下で不変条件が維持される（invariant / fuzz） | 違反を試みる操作が失敗する、または違反状態が定義上到達不能であることの根拠を示す |
| SEC | 正規の権限・経路での操作が成立する | 攻撃経路（非権限呼出・再入・偽装・donation・MEV 経路）が遮断される |
| GOV | デプロイ手順（配線→権限放棄）が成功し、構成が spec どおりになる | 放棄後の特権操作・再配線・追加登録が revert する |
| EVT | 規定のパラメータ・契機でイベントが発火する | 非発生条件で発火しない（constructor 限定イベントは runtime 非発火を含む） |
| ERR | （主検証は異常系）正常時に縮退・誤発動しないこと | 異常契機で spec 記載の縮退・revert・フェイルセーフが実際に起こる |
| MOD | 差分が台帳記載どおりに実装されている（expected-diff checker・値検証） | 台帳外差分の検出機構（Core JPYDF surface guard・expected-diff checker・parity テスト）が違反を検出する |
| TBD | — 検証対象外（未決ゲート）。Resolved 済みは反映先 ID の行で検証する | — |

### 1.3 判定原則（ガードレール）

全体台帳と同一の原則 1〜7 を適用する（実走のみが証跡／skip は PASS でない／flaky は反例確認／完了主張は全行クローズ後のみ／fork RPC 秘匿／未実装は BLOCKED／検証は head 固定）。コア固有の追加原則:

8. **FAIL の向き（spec §2.4）**: 🔵 行の FAIL は、まず「spec の記述が base 実装とずれている」可能性を疑い、base 実装・upstream テストとの三点照合を行う。実装と base が一致し spec だけが異なる場合は **spec 改訂（PR）→ 台帳更新**の順で処理する（実装を spec に合わせる修正はコア改変であり禁止）。実装が base とも異なる場合のみ実装バグとして issue 起票する。🟡/🟢 行の FAIL は通常どおり実装側 issue を起票する。
9. **upstream スイートの位置づけ**: upstream 由来のテストスイート（unit / invariant / fuzz）が DF パラメータ（`MIN_DEBT=300_000e18` 等）下で全緑であることは、🔵 行の広域 parity 証跡として複数行から参照してよい（その場合キャンペーン ID＋スイート名で参照し、行ごとの個別テストが存在する場合はそちらを優先転記する）。**実行時 skip された テストは行の証跡に数えない**。
10. **copy-parity（DFStabilityPool）**: SP スコープの 🔵 行は、**StabilityPool と DFStabilityPool の両方**で成立して初めて ✅ とする（デプロイ実体は DFStabilityPool であるため。spec §13.2 layer 2）。テスト実体には対象コントラクトを併記する。

### 1.4 標準実行手順（ローカル）

```bash
# 1) Google Drive 上では実行しない。使い捨てクローンに隔離する
git clone https://github.com/deltaforesight/jpydf-v2 /tmp/jpydf-v2-core-verify && cd /tmp/jpydf-v2-core-verify
git rev-parse HEAD   # → §2 に記録
git fetch origin base # parity 比較・guard 実行の前提

# 2) ツールチェーン記録
~/.foundry/bin/forge --version   # → §2 に記録

# 3) 静的 parity（§4 行）: JPYdf surface guard と DFStabilityPool diff 確認
bash .github/scripts/check-core-jpydf-surface.sh
# 参考: raw diff を出すだけ。期待差分があるため exit code は PASS/FAIL 判定に使わない。
# expected-diff checker 未整備の間は、この出力を manual review として扱う。
diff <(cat contracts/src/StabilityPool.sol) \
     <(sed 's/DFStabilityPool/StabilityPool/g' contracts/src/DFStabilityPool.sol)

# 4) クリーンビルド＋テスト全量（ログを保存して台帳へ転記。set -o pipefail を忘れない）
cd contracts && ~/.foundry/bin/forge clean && ~/.foundry/bin/forge build
set -o pipefail
~/.foundry/bin/forge test -vv 2>&1 | tee /tmp/forge-core-$(date +%Y%m%d).log

# 5) fork 系（RPC は環境変数で。URL を出力・台帳に残さない）
source ~/.config/deltaforesight/rpc.env
~/.foundry/bin/forge test --match-path 'test/*fork*' -vv 2>&1 | tee -a /tmp/forge-core-fork.log
```

- manual（構成レビュー・deploy 検証記録等）は実施者・日付・確認内容を `engineering/historical-reviews/` 配下に記録し、行から参照する。

---

## 2. 検証環境の記録（キャンペーン台帳）

検証キャンペーン（同一 commit SHA 上の一連の実行）ごとに 1 行追加し、各 ID 行の備考からキャンペーン ID で参照する。

| キャンペーン | 実施日 | repo / branch | commit SHA | forge / 環境 | fork RPC（種別のみ） | 実行コマンド・ログ | 実施者 | 結果サマリ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C1 | 2026-06-20 | deltaforesight/jpydf-v2 / develop | `30d078b`（origin/develop HEAD・clean） | forge 1.7.1 / macOS | archive（`DFPriceFeed` 実走・`OracleMainnet` skip） | CORE-* 意味マッピング（**per-row PASS**）= [`reviews/2026-06-20-V1-mapping/`](../historical-reviews/2026-06-20-V1-mapping/)（`CORE-1` / `CORE-BO` / `CORE-TM` / `CORE-SP`）／ 集約 = [campaign-V1](../historical-reviews/2026-06-20-requirements-verification-campaign-V1.md)／ メタ監査 = [completeness-audit](../historical-reviews/2026-06-20-ledger-completeness-audit.md) | Claude（4エージェント並列） | baseline ログで per-row `PASS` 実在確認（CORE-BO 42/55・CORE-TM 49/53・CORE-SP 148/170・CORE-1 48/74）。**ID 網羅 100%（417 行・欠落/orphan ゼロ）**。手薄: MultiTroveGetter 無検証・GasPool/HintHelpers 証跡薄・非権限 revert parity 委譲・イベント expectEmit。**§3 集計は 410 だが実数 417（FR-4/INV-1/SEC-1/EVT-1 過少）→ 本 PR で 417 に訂正**。Tier C で SYS 4/5 PASS |

---

## 3. 集計（カバレッジ・ダッシュボード）

**スコープ**: [Liquity-v2-Core-Spec.md](../../protocol/product/spec/Liquity-v2-Core-Spec.md)（JpydfToken の `CORE-BT-*` は [JpydfToken.md](../../protocol/product/spec/JpydfToken.md) に分離）の全 `CORE-*` ID（計 **417**・下表）。このうち TBD 5 行（未決 1 件・解決済み 4 件）は状態管理対象、差分台帳 MOD 11 件は対応する各 ID 行と同一証跡のため重複計上しない。「検証済」列は全行 PASS または N/A となった ID 数で、キャンペーンごとに更新する。
> **V1 訂正（2026-06-20・develop 30d078b）**: 合計行は従来 410 と表記していたが、スコープ別 20 行の総和は **417**（typed 406 ＋ MOD 11）。MOD/EVT 増分後の合計行未再計算（FR-4/INV-1/SEC-1/EVT-1 過少）。下表合計行を 417 に訂正（行の網羅は 100%・欠落 0）。

| スコープ | FR | INV | SEC | GOV | EVT | ERR | TBD | ID 計 | 検証済 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 横断（SYS） | — | 14 | — | 4 | — | 5 | — | 23 | 0 |
| 差分台帳（MOD） | — | — | — | — | — | — | — | 11 | 0 |
| BorrowerOperations（BO） | 29 | 5 | 5 | — | 12 | 4 | — | 55 | 0 |
| TroveManager（TM） | 27 | 6 | 7 | — | 8 | 5 | — | 53 | 0 |
| StabilityPool / DFStabilityPool（SP） | 13 | 6 | 5 | — | 13 | 3 | — | 40 | 0 |
| ActivePool（AP） | 15 | 2 | 1 | — | 10 | 1 | 1 | 30 | 0 |
| DefaultPool（DP） | 6 | 1 | 1 | — | 5 | 1 | — | 14 | 0 |
| CollSurplusPool（CSP） | 4 | 1 | 1 | — | 4 | 1 | — | 11 | 0 |
| GasPool（GP） | 1 | — | 1 | — | — | — | — | 2 | 2 |
| SortedTroves（ST） | 10 | 4 | 2 | — | 2 | 1 | — | 19 | 0 |
| TroveNFT（TN） | 6 | 1 | 2 | — | 3 | 1 | 2 | 15 | 0 |
| JpydfToken（BT） | 16 | 3 | 4 | — | 10 | 1 | — | 34 | 0 |
| CollateralRegistry（CR） | 9 | 4 | 2 | — | 2 | 1 | — | 18 | 0 |
| AddressesRegistry（AR） | 4 | 2 | 1 | — | 19 | 1 | — | 27 | 0 |
| HintHelpers（HH） | 10 | 1 | 1 | — | — | 1 | — | 13 | 0 |
| MultiTroveGetter（MTG） | 3 | — | 1 | — | — | 1 | — | 5 | 0 |
| DebtInFrontHelper（DFH） | 3 | — | 1 | — | — | 1 | — | 5 | 0 |
| RedemptionHelper（RH） | 5 | 1 | 1 | — | — | 1 | — | 8 | 0 |
| LiquidationCandidateGetter（LCG） | 3 | 1 | — | — | — | 1 | 1 | 6 | 0 |
| 共通基盤（LIB） | 17 | 3 | 1 | — | 4 | 2 | 1 | 28 | 0 |
| **合計（MOD 11 を含む）** | **181** | **55** | **37** | **4** | **92** | **32** | **5** | **417** | **2** |

- ほかに非 ID チェック行 7 行（§4。spec §13.3 受け入れ基準の転記）。
- TBD 5 行のうち CORE-AP-TBD-001 / CORE-TN-TBD-001 / CORE-TN-TBD-002 / CORE-LCG-TBD-001 は解決済み、残り 1 件は未決ゲートとして検証対象外（各スコープ節の未決レジスタ参照）。

---

## 4. コア共通チェック（非 ID 行・spec §13.3 受け入れ基準）

spec §13.3 の受け入れ基準を実行可能なチェック行として転記する（行 1 が JPYdf surface guard、行 2 が広域 parity、行 3〜6 が網羅・整合の機械検証）。

| # | チェック項目 | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Core JPYDF surface guard が green（旧 BOLD public/API 名の再混入ゼロ） | ci-guard ＋ ローカル実行（§1.4 手順 3） | ☐ | ☐ | | 未実施 | 異常系=ダミー禁止語 / 禁止 path 注入で guard FAIL |
| 2 | upstream 由来テストスイートが DF パラメータ下で全緑（実行時 skip ゼロ件または正体記録） | forge test（全量・ローカル実走） | ☐ | N/A | | 未実施 | 🔵 行の広域 parity 証跡（§1.3 原則 9） |
| 3 | ABI 網羅: コア全コントラクトの全 external/public 関数が spec §6 のいずれかの FR に対応 | 機械照合（ABI 抽出 × spec) | ☐ | N/A | | 未実施 | |
| 4 | DFStabilityPool ⇔ StabilityPool のソース diff が CORE-MOD-004 記載の機能差分 3 点（＋コントラクト名置換・helper 定義）以外を含まない | expected-diff checker（未整備の間は raw diff 出力の manual review） | ☐ | ☐ | | 未実施 | raw diff の exit code は期待差分があっても 1 になるため PASS/FAIL 判定に使わない。異常系=台帳外差分の検出 |
| 5 | `MIN_DEBT` が Core Spec CORE-LIB-FR-002、`COLL_GAS_COMPENSATION_CAP` とブランチ別定数が [Parameters.md](../../Parameters.md) と一致（CORE-MOD-002/003/005） | unit / deploy 検証 | ☐ | ☐ | | 未実施 | |
| 6 | デプロイ検証: 配線・immutable 値・権限放棄（CORE-SYS-GOV-001/003 の実機検査） | deploy 検証（スクリプト） | ☐ | ☐ | | 未実施 | |
| 7 | rename / コメント / import-only cleanup を正規化した `base` 差分が spec §2.2 `CORE-MOD-*` 以外の非 rename 差分を含まない | expected-diff checker（未整備の間は normalized diff の manual review） | ☐ | ☐ | | 未実施 | 異常系=台帳外の非 rename 差分を検出 |

---

## 5. DF 差分台帳の検証（CORE-MOD）

正本: spec §2.2。正常系 = 差分が台帳どおり実装されている、異常系 = 台帳外差分・誤値の検出機構が機能する（§1.2 MOD 行）。

| ID | 差分（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-MOD-001 | JpydfToken `_NAME`/`_SYMBOL` = "JPYdf Stablecoin"/"JPYdf"（debt-token 命名 surface） | unit（name/symbol・EIP-712 ドメイン name）＋ ci-guard（行単位検査） | ☐ | ☐ | | 未実施 | CORE-BT-FR-010/011 行と同証跡可 |
| CORE-MOD-002 | `MIN_DEBT` = 300_000e18（base 2000e18） | unit（定数値・openTrove 境界）＋ Core Spec CORE-LIB-FR-002 突合 | ☐ | ☐ | | 未実施 | CORE-LIB-FR-002 行と同証跡可 |
| CORE-MOD-003 | `COLL_GAS_COMPENSATION_CAP` = 1_000 ether（base 2 ether。料率 0.5% 不変） | unit（定数値・清算補償計算の cap 発動） | ☐ | ☐ | | 未実施 | CORE-LIB-FR-003 / CORE-TM-FR-002 行と同証跡可 |
| CORE-MOD-004 | DFStabilityPool = StabilityPool コピー＋same-block 出金ガード（機能差分 3 点） | expected-diff checker（StabilityPool 正規化後の差分が期待diffと完全一致）＋ unit（ガード発火）＋ copy-parity | ☐ | ☐ | | 未実施 | checker 未整備の間は manual review として扱い、raw diff の exit code を PASS/FAIL 根拠にしない。CORE-SP-FR-004 / CORE-SP-SEC-004 行と同証跡可 |
| CORE-MOD-005 | Constants へのブランチ別定数 48 件の追記（upstream 定数不変・production 未参照） | unit（値 × [Parameters.md](../../Parameters.md) 突合）＋ 静的検査（未参照確認・upstream 定数の base 同値） | ☐ | ☐ | | 未実施 | CORE-LIB-FR-004 / CORE-LIB-INV-001 行と同証跡可。inert 値は CORE-LIB-TBD-001 ゲート |
| CORE-MOD-006 | `withdrawBold` / `repayBold` を `withdrawJpydf` / `repayJpydf` へ rename（user-facing ABI） | ABI inspection（旧名不在・新名存在）＋ unit（withdraw/repay 経路） | ☐ | ☐ | | 未実施 | CORE-BO-FR-006/007/008 行と同証跡可 |
| CORE-MOD-007 | JPYdf-branded TroveNFT / MetadataNFT deployment variant | deploy 検証（`AddressesRegistry.troveNFT` / `metadataNFT` が JPYdf variant）＋ unit/snapshot（name/symbol/tokenURI） | ☐ | ☐ | | 未実施 | CORE-TN-FR-001/002/003/006 行と同証跡可 |
| CORE-MOD-008 | JpydfToken bridge-ready dormant extension | unit（bridgeAdmin / minter registry / bridgeMint / self-burn bridgeBurn）＋ deploy manifest evidence | ✅ | ✅ | `JpydfTokenTest::test_BridgeReadinessIsDormantAfterCoreSetup`; `JpydfTokenTest::test_BridgeMinterLifecycleUsesTimelockAndSelfBurn`; `JpydfTokenTest::test_BridgeRolesMustBeContractsAndSeparated`; `JpydfTokenTest::test_BridgeReadinessEventsExposeLifecyclePayloads`; `DeployLiquity2StrategySelectorTest::test_ResolveBridgeAdminValidatesConfiguredContract` | PASS(unit) | final deploy manifest evidence は未実施。`DF_BRIDGE_ADMIN` resolver の zero / deployer / codeless reject は unit 済。CORE-BT-FR-013..016 / CORE-BT-INV-003..004 / CORE-BT-SEC-004..005 / CORE-BT-GOV-001 / CORE-BT-EVT-010 行と連動 |
| CORE-MOD-009 | JpydfToken core address registration hardening（setBranchAddresses / setCollateralRegistry の非ゼロ・contract-only） | unit（zero / codeless reject）＋ deploy wiring | ✅ | ✅ | `JpydfTokenTest::test_CoreAddressRegistrationRequiresContracts` | PASS(unit) | final deploy manifest evidence は未実施。CORE-BT-FR-002/003 / CORE-BT-SEC-002 / CORE-BT-ERR-001 行と同証跡 |
| CORE-MOD-010 | ERC-20 transfer / approval hardening（`forceApprove` / `safeTransfer` / `safeTransferFrom`） | unit / integration（zero-first token・失敗 transfer・WETH gas compensation・redemption refund）＋ normalized diff | ☐ | ☐ | | 未実施 | CORE-SYS-INV-007/008 / CORE-RH-SEC-001 / CORE-GP-SEC-001 行と同証跡可 |
| CORE-MOD-011 | ActivePool aggregate accounting events | unit（各 aggregate state 更新直後の event 発火・引数一致）＋ parity（state 更新式は base 同型） | ☐ | ☐ | | 未実施 | CORE-AP-EVT-* / SYS-NFR-005 行と同証跡可 |

---

## 6. コントラクト横断（CORE-SYS）

### 6.1 不変条件（CORE-SYS-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-SYS-INV-001 | ブランチ債務の分解恒等式 | invariant / parity | ☐ | ☐ | | 未実施 | |
| CORE-SYS-INV-002 | 加重債務和の整合 | invariant / parity | ☐ | ☐ | | 未実施 | |
| CORE-SYS-INV-003 | JPYdf 供給経路の閉性 | parity / 監査（Core mint/burn call site の全数確認）＋ unit（Day-1 dormant bridge state / bridge minter lifecycle） | ☐ | ☐ | `JpydfTokenTest::test_BridgeReadinessIsDormantAfterCoreSetup`; `JpydfTokenTest::test_BridgeMinterLifecycleUsesTimelockAndSelfBurn`; `JpydfTokenTest::test_BridgeMintRejectsProtocolRecipients` | PASS(unit) | Core mint/burn call site の全数 parity / deploy review は未実施 |
| CORE-SYS-INV-004 | redemption の会計整合 | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-SYS-INV-005 | 清算の担保保存則 | invariant / parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-SYS-INV-006 | redistribution 会計の整合 | invariant / parity | ☐ | ☐ | | 未実施 | |
| CORE-SYS-INV-007 | AP・DP 担保会計の保存 | invariant / parity | ☐ | ☐ | | 未実施 | |
| CORE-SYS-INV-008 | GasPool の WETH 整合 | invariant / parity | ☐ | ☐ | | 未実施 | |
| CORE-SYS-INV-009 | SortedTroves と Trove 集合の整合 | invariant / parity | ☐ | ☐ | | 未実施 | |
| CORE-SYS-INV-010 | TroveNFT と Trove 状態の整合 | invariant / parity | ☐ | ☐ | | 未実施 | |
| CORE-SYS-INV-011 | MIN_JPYDF_IN_SP の横断維持 | invariant / parity | ☐ | ☐ | | 未実施 | |
| CORE-SYS-INV-012 | MIN_DEBT と zombie の規律 | invariant / parity | ☐ | ☐ | | 未実施 | |
| CORE-SYS-INV-013 | shutdown の一回性（BO–TM 信頼境界） | parity / unit（二重 shutdown 不能） | ☐ | ☐ | | 未実施 | |
| CORE-SYS-INV-014 | troveId の sentinel 非衝突 | parity / unit | ☐ | ☐ | | 未実施 | |

### 6.2 ガバナンス・運用要件（CORE-SYS-GOV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-SYS-GOV-001 | デプロイ時配線と権限の自己放棄 | parity / deploy 検証（配線後に `owner() == address(0)` 相当・各 setter revert） | ☐ | ☐ | | 未実施 | |
| CORE-SYS-GOV-002 | 非アップグレード性・パラメータ不変性 | manual（コードレビュー: setter 不在・immutable 宣言）/ deploy 検証 | ☐ | ☐ | | 未実施 | |
| CORE-SYS-GOV-003 | デプロイゲート（値の機械検証）🟡 含む | deploy 検証（スクリプト）/ manual | ☐ | ☐ | | 未実施 | |
| CORE-SYS-GOV-004 | 運用上の能動操作はインセンティブ駆動の permissionless 操作のみ | manual（運用 runbook との整合） | ☐ | ☐ | | 未実施 | |

### 6.3 失敗時・異常系挙動（CORE-SYS-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-SYS-ERR-001 | オラクル障害カスケード | integration（Oracle 層と結合）/ parity | ☐ | ☐ | | 未実施 | |
| CORE-SYS-ERR-002 | クリティカルモード（TCR < CCR） | parity / unit（モードマトリクス） | ☐ | ☐ | | 未実施 | |
| CORE-SYS-ERR-003 | ブランチ shutdown（不可逆縮退） | parity / unit（shutdown 後マトリクス） | ☐ | ☐ | | 未実施 | |
| CORE-SYS-ERR-004 | SP 枯渇時の清算縮退 | parity / unit（3 分岐） | ☐ | ☐ | | 未実施 | |
| CORE-SYS-ERR-005 | zombie Trove のライフサイクル | parity / unit | ☐ | ☐ | | 未実施 | |


## 7. BorrowerOperations（CORE-BO）

### 7.1 機能要件（CORE-BO-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BO-FR-001 | openTrove（新規 Trove の開設） | parity / invariant=CORE-BO-INV-002, CORE-BO-INV-005 | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-002 | openTroveAndJoinInterestBatchManager（batch 同時加入の開設） | parity / invariant=CORE-BO-INV-002, CORE-BO-INV-003 | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-003 | adjustTrove（担保・債務の複合調整・共通調整パス） | parity / invariant=CORE-BO-INV-002 | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-004 | addColl（担保追加） | parity | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-005 | withdrawColl（担保引出） | parity | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-006 | withdrawJpydf（追加借入） | parity | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-007 | repayJpydf（返済） | parity | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-008 | adjustZombieTrove（zombie Trove の調整と active 復帰） | parity | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-009 | closeTrove（Trove の閉鎖） | parity / invariant=CORE-BO-INV-002 | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-010 | applyPendingDebt（利息・再分配の記録値への確定） | parity | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-011 | adjustTroveInterestRate（単独 Trove の金利変更） | parity / invariant=CORE-BO-INV-002 | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-012 | setInterestIndividualDelegate（個別 interest delegate の設定） | parity / invariant=CORE-BO-INV-002 | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-013 | removeInterestIndividualDelegate（個別 interest delegate の解除） | parity | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-014 | registerBatchManager（batch manager の登録） | parity / invariant=CORE-BO-INV-004 | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-015 | setBatchManagerAnnualInterestRate（batch 一括金利変更） | parity / invariant=CORE-BO-INV-004 | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-016 | lowerBatchManagementFee（batch 管理 fee の引下げ） | parity / invariant=CORE-BO-INV-004 | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-017 | setInterestBatchManager（既存 Trove の batch 加入） | parity / invariant=CORE-BO-INV-002, CORE-BO-INV-003 | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-018 | removeFromBatch（batch からの離脱） | parity / invariant=CORE-BO-INV-002 | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-019 | kickFromBatch（shares ratio 劣化 batch からの強制退去） | parity | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-020 | switchBatchManager（batch の乗り換え） | parity | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-021 | shutdown（TCR < SCR によるブランチ shutdown） | parity / invariant=CORE-BO-INV-001 | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-022 | shutdownFromOracleFailure（oracle 失敗による shutdown） | parity / invariant=CORE-BO-INV-001 | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-023 | onLiquidateTrove（清算時の BO 側状態クリア） | parity | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-024 | claimCollateral（清算余剰担保の引出） | parity | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-025 | setAddManager（AddManager の設定） | parity | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-026 | setRemoveManagerWithReceiver（RemoveManager と receiver の設定） | parity / SEC=CORE-BO-SEC-002 | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-027 | setRemoveManager（RemoveManager の設定・receiver は owner） | parity | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-028 | view 関数群 | parity | ☐ | ☐ | | 未実施 | |
| CORE-BO-FR-029 | constructor（デプロイ時配線・初期化） | parity / deploy 検証 | ☐ | ☐ | | 未実施 | |

### 7.2 不変条件（CORE-BO-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BO-INV-001 | `hasBeenShutDown` は単調（false → true の一回のみ。true へ遷移させる経路は `shutdown()` と `shutdownFromOracleFailur… | invariant | ☐ | ☐ | | 未実施 | |
| CORE-BO-INV-002 | 任意の Trove で `interestIndividualDelegateOf[t].account != 0` と `interestBatchManagerOf[t] != 0` は同… | invariant | ☐ | ☐ | | 未実施 | |
| CORE-BO-INV-003 | `interestBatchManagerOf[t] != 0` ならば、そのアドレスは登録済み batch manager（`interestBatchManagers[m].maxInte… | invariant | ☐ | ☐ | | 未実施 | |
| CORE-BO-INV-004 | 登録済み batch manager のレコード `(minInterestRate, maxInterestRate, minInterestRateChangePeriod)` は登録後不… | invariant | ☐ | ☐ | | 未実施 | |
| CORE-BO-INV-005 | 配線（troveManager / gasPoolAddress / collSurplusPool / jpydfToken / sortedTroves / collToken / WETH… | invariant / deploy 検証 | ☐ | ☐ | | 未実施 | |

### 7.3 セキュリティ要件（CORE-BO-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BO-SEC-001 | Trove 操作権限モデルの閉性 | parity / unit（権限マトリクス） | ☐ | ☐ | | 未実施 | |
| CORE-BO-SEC-002 | receiver redirection の制約 | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-BO-SEC-003 | 内部フックの呼出元限定 | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-BO-SEC-004 | upfront fee のスリッページ防御 | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-BO-SEC-005 | permissionless 操作の状態条件ゲート | parity / unit | ☐ | ☐ | | 未実施 | |

### 7.4 イベント・監視要件（CORE-BO-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BO-EVT-001 | `TroveManagerAddressChanged`（発火: constructor） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BO-EVT-002 | `GasPoolAddressChanged`（発火: constructor） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BO-EVT-003 | `CollSurplusPoolAddressChanged`（発火: constructor） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BO-EVT-004 | `SortedTrovesAddressChanged`（発火: constructor） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BO-EVT-005 | `JpydfTokenAddressChanged`（発火: constructor） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BO-EVT-006 | `ShutDown`（発火: `shutdown()`（TCR < SCR 経路のみ。oracle 失敗経路では発火しない）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BO-EVT-007 | `TroveNFTAddressChanged`（発火: constructor（AddRemoveManagers）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BO-EVT-008 | `AddManagerUpdated`（発火: `setAddManager` / `openTrove` 系（常に発火）/ `closeTro…） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BO-EVT-009 | `RemoveManagerAndReceiverUpdated`（発火: `setRemoveManager(WithReceiver)` / `openTrove` 系…） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BO-EVT-010 | `ActivePoolAddressChanged`（発火: constructor（LiquityBase）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BO-EVT-011 | `DefaultPoolAddressChanged`（発火: constructor（LiquityBase）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BO-EVT-012 | `PriceFeedAddressChanged`（発火: constructor（LiquityBase）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 7.5 失敗時・異常系挙動（CORE-BO-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BO-ERR-001 | TCR < CCR（クリティカル閾値未満）時の調整制限 | parity / unit（モード別マトリクス） | ☐ | ☐ | | 未実施 | |
| CORE-BO-ERR-002 | 返済額の silent cap | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-BO-ERR-003 | shutdown 後の関数可否 | parity / unit（shutdown 後マトリクス） | ☐ | ☐ | | 未実施 | |
| CORE-BO-ERR-004 | oracle 失敗時の挙動 | parity / unit | ☐ | ☐ | | 未実施 | |


## 8. TroveManager（CORE-TM）

### 8.1 機能要件（CORE-TM-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TM-FR-001 | batchLiquidateTroves（清算シーケンス） | parity / invariant=CORE-TM-INV-001, CORE-TM-INV-002 | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-002 | 単一 Trove 清算と清算値の配分（SP offset / redistribution / ガス補償 / 余剰担保） | parity / unit（3 分岐・cap 境界・surplus 食い込み） | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-003 | redistribution 会計（L_coll / L_jpydfDebt・error feedback・stake 規則） | parity / invariant=CORE-TM-INV-002, CORE-TM-INV-006 | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-004 | redeemCollateral（通常 Redemption） | parity / unit（zombie 遷移・fee 残置・batch 経路）/ invariant=CORE-TM-INV-005 | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-005 | urgentRedemption（shutdown 後の緊急 Redemption） | parity / unit（担保切り詰め分岐・_minCollateral 境界） | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-006 | shutdown（ブランチ shutdown の記録） | parity / unit（onlyBO） | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-007 | 利息発生期間の決定（shutdown による凍結） | parity / unit（3 分岐） | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-008 | getCurrentICR（現在 ICR の算出） | parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-009 | getLatestTroveData（最新 Trove 状態の導出） | parity / unit（batch 按分・redistribution 個別帰属） | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-010 | getLatestBatchData（最新 Batch 状態の導出） | parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-011 | getTroveAnnualInterestRate（実効年利の解決） | parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-012 | getUnbackedPortionPriceAndRedeemability（非裏付け債務と redeem 可否） | parity / unit（redeemable 境界） | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-013 | 自明 view getter 群 | parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-014 | onOpenTrove（Trove 開設の記録） | parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-015 | onOpenTroveAndJoinBatch（batch 加入付き開設） | parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-016 | setTroveStatusToActive（zombie からの復帰） | parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-017 | onAdjustTrove（Trove 調整の記録） | parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-018 | onAdjustTroveInterestRate（個別金利変更の記録） | parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-019 | onAdjustTroveInsideBatch（batch 内 Trove 調整の記録） | parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-020 | onApplyTroveInterest（利息・redistribution 適用の記録） | parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-021 | onCloseTrove（Trove 閉鎖の記録） | parity / invariant=CORE-TM-INV-001, CORE-TM-INV-003 | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-022 | onRegisterBatchManager（batch manager 登録） | parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-023 | onLowerBatchManagerAnnualFee（batch 管理fee引き下げ） | parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-024 | onSetBatchManagerAnnualInterestRate（batch 金利変更） | parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-025 | onSetInterestBatchManager（既存 Trove の batch 加入） | parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-026 | onRemoveFromBatch（Trove の batch 離脱） | parity / invariant=CORE-TM-INV-004 | ☐ | ☐ | | 未実施 | |
| CORE-TM-FR-027 | batch debt shares の更新規則（_updateBatchShares） | parity / unit（初期発行・全額償還・比率境界）/ invariant=CORE-TM-INV-004 | ☐ | ☐ | | 未実施 | |

### 8.2 不変条件（CORE-TM-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TM-INV-001 | totalStakes の整合 | invariant / parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-INV-002 | L 値の単調性 | invariant | ☐ | ☐ | | 未実施 | |
| CORE-TM-INV-003 | TroveIds / arrayIndex の整合 | invariant | ☐ | ☐ | | 未実施 | |
| CORE-TM-INV-004 | batch shares 会計の整合 | invariant | ☐ | ☐ | | 未実施 | |
| CORE-TM-INV-005 | lastZombieTroveId の整合 | invariant（通常運転）/ unit（shutdown 後の例外） | ☐ | ☐ | | 未実施 | |
| CORE-TM-INV-006 | redistribution 誤差の有界性 | invariant / unit | ☐ | ☐ | | 未実施 | |

### 8.3 セキュリティ要件（CORE-TM-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TM-SEC-001 | on* コールバックの BorrowerOperations 限定 | unit（全関数の caller 検査）/ parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-SEC-002 | redeemCollateral の CollateralRegistry 限定 | unit / parity | ☐ | ☐ | | 未実施 | |
| CORE-TM-SEC-003 | 清算条件の限定 | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-TM-SEC-004 | Redemption による CR 悪化の防止 | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-TM-SEC-005 | zombie 機構による Redemption griefing 耐性 | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-TM-SEC-006 | batch shares の希釈・rebase 攻撃耐性と Redemption 非ブロック | unit | ☐ | ☐ | | 未実施 | |
| CORE-TM-SEC-007 | shutdown の一回性は BorrowerOperations 依存 | parity（BO 経由の二重 shutdown 不能） | ☐ | ☐ | | 未実施 | |

### 8.4 イベント・監視要件（CORE-TM-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TM-EVT-001 | `Liquidation`（発火: `batchLiquidateTroves`（1 回/呼出）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-TM-EVT-002 | `Redemption`（発火: `redeemCollateral` / `urgentRedemption`（1 回/呼出）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-TM-EVT-003 | `TroveUpdated`（発火: Trove の状態変化全般（非 batch の調整・金利変更等。batch 所属でも `onAp…） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-TM-EVT-004 | `TroveOperation`（発火: Trove に対する全操作） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-TM-EVT-005 | `RedemptionFeePaidToTrove`（発火: `_applySingleRedemption`（Trove ごと）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-TM-EVT-006 | `BatchUpdated`（発火: batch に関わる全操作） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-TM-EVT-007 | `BatchedTroveUpdated`（発火: batch 所属 Trove の状態変化） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-TM-EVT-008 | アドレス配線イベント群: `TroveNFTAddressChanged` / `BorrowerOperationsA…（発火: constructor のみ（1 回限り）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 8.5 失敗時・異常系挙動（CORE-TM-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TM-ERR-001 | batchLiquidateTroves の失敗時挙動 | unit | ☐ | ☐ | | 未実施 | |
| CORE-TM-ERR-002 | redeemCollateral はゼロ償還でも成功する | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-TM-ERR-003 | urgentRedemption の失敗時挙動 | unit | ☐ | ☐ | | 未実施 | |
| CORE-TM-ERR-004 | 最後の 1 Trove の閉鎖禁止 | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-TM-ERR-005 | BatchSharesRatioTooHigh | unit | ☐ | ☐ | | 未実施 | |


## 9. StabilityPool / DFStabilityPool（CORE-SP）

### 9.1 機能要件（CORE-SP-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-SP-FR-001 | constructor（AddressesRegistry からの配線） | parity（配線・初期値の同一性） | ☐ | ☐ | | 未実施 | |
| CORE-SP-FR-002 | provideToSP（JPYdf 預入・トップアップとゲイン同時精算） | parity / unit（`_doClaim` 分岐・kept yield の複利算入・pending 振替・新規/トップアップ両経路）/ invariant=CORE-SP-INV-003, CORE-SP-INV-005, CORE-SP-INV-006 | ☑ | ☐ | `SPTest::testJpydfRewardsPendingDistributesWhenDepositReachesMinPoolSize`（2026-06-21） | 部分実施 | SP が `MIN_JPYDF_IN_SP` 到達時に pending yield を owed / B へ振替し、閾値復帰 depositor が参加することを確認。`_doClaim` 全分岐・snapshot lifecycle は継続 |
| CORE-SP-FR-003 | withdrawFromSP（JPYdf 引出とゲイン同時精算） | parity / unit（`min` 切り詰め・`_amount=0` 精算・`MIN_JPYDF_IN_SP` 境界・`newDeposit==0` の snapshot delete）/ invariant=CORE-SP-INV-002, CORE-SP-INV-003, CORE-SP-INV-006 | ☐ | ☐ | | 未実施 | |
| CORE-SP-FR-004 | lastDepositBlock（same-block 出金ガード）🟡 | unit（same-block revert・翌ブロック成功・トップアップによるブロック更新・`claimAllCollGains` 非対象）/ copy-parity（DFStabilityPool が本ガード以外で StabilityPool と同一挙動であること） | ☐ | ☐ | | 未実施 | |
| CORE-SP-FR-005 | claimAllCollGains（預金ゼロ利用者の stash 済み担保請求） | parity / unit（預金ありで revert・stash ゼロで revert・払出と stash クリア） | ☐ | ☐ | | 未実施 | |
| CORE-SP-FR-006 | triggerJpydfRewards（利息利回りの配分計上） | parity / unit（閾値未満での pending 積み増し・閾値以上での一括振替・ゼロ利回り早期 return）/ invariant=CORE-SP-INV-003, CORE-SP-INV-005 | ☑ | ☑ | `SPTest::testJpydfRewardsPendingDistributesWhenDepositReachesMinPoolSize`; `SPTest::testTriggerJpydfRewardsRevertsWhenCallerIsNotActivePool`（2026-06-21） | 部分実施 | 閾値未満 pending と閾値到達時の一括振替、非 ActivePool caller revert を確認。ゼロ利回り早期 return は継続 |
| CORE-SP-FR-007 | offset（清算オフセット: P/S 更新・debt 焼却・担保受入） | parity / unit（単一・複数 scale 跨ぎ、`newP > 0` 境界、S→P の更新順序、丸め方向）/ invariant=CORE-SP-INV-001〜004 | ☐ | ☐ | | 未実施 | |
| CORE-SP-FR-008 | getDepositorCollGain（未精算担保ゲインの計算） | parity / unit（同一 scale・1/2 scale 跨ぎ・SPAN 超過で打ち切り・クランプ発動） | ☐ | ☐ | | 未実施 | |
| CORE-SP-FR-009 | getDepositorYieldGain（未精算利回りゲインの計算） | parity / unit（scale 跨ぎ・クランプ・pending 非算入） | ☐ | ☐ | | 未実施 | |
| CORE-SP-FR-010 | getDepositorYieldGainWithPending（pending 利息込みの利回り見積） | parity / unit（閾値未満で 0・SPAN 内外の分岐・`triggerJpydfRewards` 直後との整合） | ☐ | ☐ | | 未実施 | |
| CORE-SP-FR-011 | getCompoundedJpydfDeposit（複利後預金の計算） | parity / unit（scale 差 0〜8・9 以上で 0・床除算の方向） | ☐ | ☐ | | 未実施 | |
| CORE-SP-FR-012 | 自明な view 関数群（トラッカー・定数・配線 getter） | parity | ☐ | ☐ | | 未実施 | |
| CORE-SP-FR-013 | getEntireBranchColl / getEntireBranchDebt（LiquityBase 継承 view） | parity | ☐ | ☐ | | 未実施 | |

### 9.2 不変条件（CORE-SP-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-SP-INV-001 | P の範囲と非ゼロ性 | invariant / parity | ☐ | ☐ | | 未実施 | |
| CORE-SP-INV-002 | MIN_JPYDF_IN_SP の単調維持 | invariant（SYS） | ☐ | ☐ | | 未実施 | |
| CORE-SP-INV-003 | JPYdf 会計恒等式 | invariant / parity | ☐ | ☐ | | 未実施 | |
| CORE-SP-INV-004 | 担保会計の整合 | invariant | ☐ | ☐ | | 未実施 | |
| CORE-SP-INV-005 | pending と閾値の排他 | invariant / unit | ☑ | N/A | `SPTest::testJpydfRewardsPendingDistributesWhenDepositReachesMinPoolSize`（2026-06-21） | PASS(unit) | `totalJpydfDeposits < MIN_JPYDF_IN_SP` では `yieldGainsPending > 0` かつ B/owed 未更新、閾値到達後は pending が 0 になり owed/B へ移ることを確認 |
| CORE-SP-INV-006 | 預金とスナップショットのライフサイクル整合 | invariant / unit | ☐ | ☐ | | 未実施 | |

### 9.3 セキュリティ要件（CORE-SP-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-SP-SEC-001 | offset の呼出元制限 | unit（非 TM 呼出の revert）/ parity | N/A | ☑ | `SPTest::testOffsetRevertsWhenCallerIsNotTroveManager`（2026-06-21） | PASS(unit) | 非 TroveManager caller が `"StabilityPool: Caller is not TroveManager"` で revert |
| CORE-SP-SEC-002 | triggerJpydfRewards の呼出元制限 | unit / parity | N/A | ☑ | `SPTest::testTriggerJpydfRewardsRevertsWhenCallerIsNotActivePool`（2026-06-21） | PASS(unit) | 非 ActivePool caller が `"StabilityPool: Caller is not ActivePool"` で revert |
| CORE-SP-SEC-003 | 内部トラッカーによる donation 耐性 | unit（直接 transfer 後の各 view 不変） | ☐ | ☐ | | 未実施 | |
| CORE-SP-SEC-004 | same-block flash 預入による清算益横取りの防止 🟡 | unit（same-block revert・翌ブロック成功・flash loan 経路の不成立） | ☐ | ☐ | | 未実施 | |
| CORE-SP-SEC-005 | 外部呼出面と再入の考慮 | parity / 設計レビュー（dToken 側仕様への依存を明記） | ☐ | ☐ | | 未実施 | |

### 9.4 イベント・監視要件（CORE-SP-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-SP-EVT-001 | `DepositOperation`（発火: provideToSP / withdrawFromSP / claimAllCollGains） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-SP-EVT-002 | `DepositUpdated`（発火: _updateDepositAndSnapshots（provideToSP / withdra…） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-SP-EVT-003 | `StabilityPoolJpydfBalanceUpdated`（発火: _updateTotalJpydfDeposits（provideToSP / withdrawF…） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-SP-EVT-004 | `StabilityPoolCollBalanceUpdated`（発火: _moveOffsetCollAndDebt（offset）/ _sendCollGainToD…） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-SP-EVT-005 | `P_Updated`（発火: offset） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-SP-EVT-006 | `S_Updated`（発火: offset） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-SP-EVT-007 | `B_Updated`（発火: _updateYieldRewardsSum（triggerJpydfRewards / prov…） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-SP-EVT-008 | `ScaleUpdated`（発火: offset（scale ループ内、繰り上げごと）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-SP-EVT-009 | `TroveManagerAddressChanged`（発火: constructor） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-SP-EVT-010 | `JpydfTokenAddressChanged`（発火: constructor） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-SP-EVT-011 | `ActivePoolAddressChanged`（発火: constructor（LiquityBase）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-SP-EVT-012 | `DefaultPoolAddressChanged`（発火: constructor（LiquityBase）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-SP-EVT-013 | `PriceFeedAddressChanged`（発火: constructor（LiquityBase）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 9.5 失敗時・異常系挙動（CORE-SP-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-SP-ERR-001 | 預金者操作の revert 一覧 | unit / parity | ☐ | ☐ | | 未実施 | |
| CORE-SP-ERR-002 | same-block 出金の revert 🟡 | unit | ☐ | ☐ | | 未実施 | |
| CORE-SP-ERR-003 | 特権関数の前提違反時挙動 | unit（境界呼出）/ parity | N/A | ☑ | `SPTest::testOffsetRevertsWhenCallerIsNotTroveManager`; `SPTest::testTriggerJpydfRewardsRevertsWhenCallerIsNotActivePool`（2026-06-21） | 部分実施 | caller guard 境界は直接確認。`offset` の `newP > 0` 境界呼出は継続 |


## 10. ActivePool（CORE-AP）

### 10.1 機能要件（CORE-AP-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AP-FR-001 | コンストラクタ（アドレス配線と DefaultPool への担保 approve） | parity / deployment テスト（配線・approve 値） | ☐ | ☐ | | 未実施 | |
| CORE-AP-FR-002 | calcPendingAggInterest（集計ペンディング利息の計算） | parity / invariant=CORE-SYS-INV-001 の基礎 | ☐ | ☐ | | 未実施 | |
| CORE-AP-FR-003 | calcPendingSPYield（ペンディング利息の SP 取り分） | parity | ☐ | ☐ | | 未実施 | |
| CORE-AP-FR-004 | calcPendingAggBatchManagementFee（集計ペンディング batch 管理フィーの計算） | parity / unit（shutdown 前後・lastUpdate > shutdownTime の境界） | ☐ | ☐ | | 未実施 | |
| CORE-AP-FR-005 | getNewApproxAvgInterestRateFromTroveChange（Trove 変更仮適用後の近似平均利率） | parity / unit（shutdown 時 0・分母 0・近似式） | ☐ | ☐ | | 未実施 | |
| CORE-AP-FR-006 | getJpydfDebt（アクティブ負債合計） | parity / invariant=CORE-SYS-INV-001 の基礎 | ☐ | ☐ | | 未実施 | |
| CORE-AP-FR-007 | mintAggInterest（集計利息の確定 mint・75/25 分配） | parity / unit（分配端数・spYield=0 境界・lastAggUpdateTime 更新） | ☐ | ☐ | | 未実施 | |
| CORE-AP-FR-008 | mintAggInterestAndAccountForTroveChange（利息 mint＋Trove 変化の集計反映） | parity / invariant=CORE-SYS-INV-001 | ☐ | ☐ | | 未実施 | |
| CORE-AP-FR-009 | mintBatchManagementFeeAndAccountForChange（batch 管理フィーの確定 mint・集計反映） | parity / unit（適用分の付け替え・mint 額） | ☐ | ☐ | | 未実施 | |
| CORE-AP-FR-010 | sendColl（担保の外部送付） | parity / invariant=CORE-AP-INV-001 | ☐ | ☐ | | 未実施 | |
| CORE-AP-FR-011 | sendCollToDefaultPool（redistribution 担保の DefaultPool 移送） | parity / invariant=CORE-AP-INV-001 / CORE-SYS-INV-007 | ☐ | ☐ | | 未実施 | |
| CORE-AP-FR-012 | receiveColl（担保受領: 会計加算＋pull） | parity / invariant=CORE-AP-INV-001 | ☐ | ☐ | | 未実施 | |
| CORE-AP-FR-013 | accountForReceivedColl（直接送付済み担保の会計反映） | parity / invariant=CORE-AP-INV-001 | ☐ | ☐ | | 未実施 | |
| CORE-AP-FR-014 | setShutdownFlag（shutdown 時刻の記録と利息累積の恒久停止） | parity / unit（shutdown 後の利息 0・batch フィー打ち切り） | ☐ | ☐ | | 未実施 | |
| CORE-AP-FR-015 | 自明 view 関数群 | parity | ☐ | ☐ | | 未実施 | |

### 10.2 不変条件（CORE-AP-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AP-INV-001 | 会計残高は実残高を超えない | invariant / parity | ☐ | ☐ | | 未実施 | |
| CORE-AP-INV-002 | shutdown 後の利息凍結 | unit / invariant | ☐ | ☐ | | 未実施 | |

### 10.3 セキュリティ要件（CORE-AP-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AP-SEC-001 | 状態変更面の呼出元限定 | unit（全関数の不正呼出元 revert）/ parity | ☐ | ☐ | | 未実施 | |

### 10.4 イベント・監視要件（CORE-AP-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AP-EVT-001 | `CollTokenAddressChanged`（発火: コンストラクタのみ） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AP-EVT-002 | `BorrowerOperationsAddressChanged`（発火: コンストラクタのみ） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AP-EVT-003 | `TroveManagerAddressChanged`（発火: コンストラクタのみ） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AP-EVT-004 | `DefaultPoolAddressChanged`（発火: コンストラクタのみ） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AP-EVT-005 | `StabilityPoolAddressChanged`（発火: コンストラクタのみ） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AP-EVT-007 | `ActivePoolCollBalanceUpdated`（発火: `_accountForSendColl` / `_accountForReceivedColl…） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AP-EVT-008 | `ActivePoolAggRecordedDebtUpdated`（発火: `mintAggInterestAndAccountForTroveChange` / `mintAggInterest` / batch fee accounting） | unit / monitoring（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AP-EVT-009 | `ActivePoolAggWeightedDebtSumUpdated`（発火: `mintAggInterestAndAccountForTroveChange`） | unit / monitoring（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AP-EVT-010 | `ActivePoolAggBatchManagementFeesUpdated`（発火: batch fee accounting） | unit / monitoring（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AP-EVT-011 | `ActivePoolAggWeightedBatchManagementFeeSumUpdated`（発火: batch fee accounting） | unit / monitoring（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AP-EVT-012 | `AggregateInterestMinted`（発火: aggregate interest/upfront fee mint。DeFiLlama fee/revenue 一次証跡） | unit / monitoring（台帳定義） | ✅ | N/A | `InterestRateAggregate::testOpenTroveEmitsAggregateInterestMintedForDefiLlamaAccounting` | PASS | 2026-06-25 focused: `forge test --match-contract InterestRateAggregate --match-test testOpenTroveEmitsAggregateInterestMintedForDefiLlamaAccounting -vvv` |
| CORE-AP-EVT-013 | `BatchManagementFeeMinted`（発火: batch 管理フィー mint。batch manager fee 一次証跡） | unit / monitoring（台帳定義） | ✅ | N/A | `BatchManagementFeeTest::testAdjustTroveEmitsBatchManagementFeeMintedForDefiLlamaAccounting` | PASS | 2026-06-25 focused: `forge test --match-contract BatchManagementFeeTest --match-test testAdjustTroveEmitsBatchManagementFeeMintedForDefiLlamaAccounting -vvv` |

### 10.5 失敗時・異常系挙動（CORE-AP-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AP-ERR-001 | 失敗時挙動（require 文字列・算術 revert） | unit / parity | ☐ | ☐ | | 未実施 | |

### 10.6 未決事項レジスタ（CORE-AP-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| CORE-AP-TBD-001 | 解決済 | Complete deploy では `InterestRouterForwarder` を `interestRouter` に束縛し、recipient / owner を env と handover/verify で管理する。`route()` keeper / 監視は InterestRouterForwarder Route Runbook で運用管理する。V2-gov / Governance address 直接束縛の fallback は Day-1 deploy path から削除済み | CORE-AP-FR-007/008 と `InterestRouterForwarder` 行で検証 |


## 11. DefaultPool（CORE-DP）

### 11.1 機能要件（CORE-DP-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-DP-FR-001 | コンストラクタ（アドレス配線と ActivePool への担保 approve） | parity / deployment テスト | ☐ | ☐ | | 未実施 | |
| CORE-DP-FR-002 | sendCollToActivePool（ペンディング担保の ActivePool への戻し） | parity / invariant=CORE-DP-INV-001 | ☐ | ☐ | | 未実施 | |
| CORE-DP-FR-003 | receiveColl（redistribution 担保の受領） | parity / invariant=CORE-DP-INV-001 | ☐ | ☐ | | 未実施 | |
| CORE-DP-FR-004 | increaseJpydfDebt（redistribution 負債の計上） | parity / invariant=CORE-SYS-INV-001 | ☐ | ☐ | | 未実施 | |
| CORE-DP-FR-005 | decreaseJpydfDebt（適用済み負債の取崩し） | parity | ☐ | ☐ | | 未実施 | |
| CORE-DP-FR-006 | 自明 view 関数群 | parity | ☐ | ☐ | | 未実施 | |

### 11.2 不変条件（CORE-DP-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-DP-INV-001 | 会計残高は実残高を超えない | invariant / parity | ☐ | ☐ | | 未実施 | |

### 11.3 セキュリティ要件（CORE-DP-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-DP-SEC-001 | 書込み面の呼出元限定 | unit（不正呼出元 revert）/ parity | ☐ | ☐ | | 未実施 | |

### 11.4 イベント・監視要件（CORE-DP-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-DP-EVT-001 | `CollTokenAddressChanged`（発火: コンストラクタのみ） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-DP-EVT-002 | `ActivePoolAddressChanged`（発火: コンストラクタのみ） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-DP-EVT-003 | `TroveManagerAddressChanged`（発火: コンストラクタのみ） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-DP-EVT-004 | `DefaultPoolJpydfDebtUpdated`（発火: increaseJpydfDebt / decreaseJpydfDebt） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-DP-EVT-005 | `DefaultPoolCollBalanceUpdated`（発火: sendCollToActivePool / receiveColl） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 11.5 失敗時・異常系挙動（CORE-DP-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-DP-ERR-001 | 失敗時挙動 | unit / parity | ☐ | ☐ | | 未実施 | |


## 12. CollSurplusPool（CORE-CSP）

### 12.1 機能要件（CORE-CSP-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CSP-FR-001 | コンストラクタ（アドレス配線） | parity / deployment テスト | ☐ | ☐ | | 未実施 | |
| CORE-CSP-FR-002 | accountSurplus（清算余剰の記帳） | parity / invariant=CORE-CSP-INV-001 | ☐ | ☐ | | 未実施 | |
| CORE-CSP-FR-003 | claimColl（余剰担保の請求・払い出し） | parity / unit（ゼロ残高 revert・全額払い出し・再請求 revert） | ☐ | ☐ | | 未実施 | |
| CORE-CSP-FR-004 | 自明 view 関数群 | parity | ☐ | ☐ | | 未実施 | |

### 12.2 不変条件（CORE-CSP-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CSP-INV-001 | 会計の整合 | invariant / parity | ☐ | ☐ | | 未実施 | |

### 12.3 セキュリティ要件（CORE-CSP-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CSP-SEC-001 | 請求権の本人限定 | unit（不正呼出元 revert）/ parity | ☐ | ☐ | | 未実施 | |

### 12.4 イベント・監視要件（CORE-CSP-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CSP-EVT-001 | `BorrowerOperationsAddressChanged`（発火: コンストラクタのみ） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-CSP-EVT-002 | `TroveManagerAddressChanged`（発火: コンストラクタのみ） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-CSP-EVT-003 | `CollBalanceUpdated`（発火: accountSurplus（記帳時）/ claimColl（ゼロ化時）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-CSP-EVT-004 | `CollSent`（発火: claimColl） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 12.5 失敗時・異常系挙動（CORE-CSP-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CSP-ERR-001 | 失敗時挙動 | unit / parity | ☐ | ☐ | | 未実施 | |


## 13. GasPool（CORE-GP）

### 13.1 機能要件（CORE-GP-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-GP-FR-001 | コンストラクタ（BO・TM への WETH 無限 approve） | parity / deployment テスト（approve 値 = type(uint256).max が BO・TM 双方に設定されること） | ☑ | ☑ | `forge test --match-path test/GasPool.t.sol`（2026-06-21: 4 passed） | PASS(unit) | BO / TM allowance が `type(uint256).max`、第三者 allowance が 0、設定済み core caller のみ transferFrom 可能 |

### 13.2 セキュリティ要件（CORE-GP-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-GP-SEC-001 | ゼロ攻撃面と approve の妥当性 | unit（ABI が空であること・approve 対象の検証）/ parity | ☑ | ☑ | `forge test --match-path test/GasPool.t.sol`（2026-06-21: 4 passed） | PASS(unit) | unprivileged transferFrom revert、未知 selector revert、第三者 allowance 0 を確認 |


## 14. SortedTroves（CORE-ST）

### 14.1 機能要件（CORE-ST-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-ST-FR-001 | constructor（アドレス束縛と番兵ノード初期化） | parity / deployment テスト | ☐ | ☐ | | 未実施 | |
| CORE-ST-FR-002 | insert（非 batch ノードの挿入） | parity, invariant=CORE-ST-INV-001 / CORE-ST-INV-002 / CORE-ST-INV-004 | ☐ | ☐ | | 未実施 | |
| CORE-ST-FR-003 | remove（非 batch ノードの除去） | parity, invariant=CORE-ST-INV-002 / CORE-ST-INV-004 | ☐ | ☐ | | 未実施 | |
| CORE-ST-FR-004 | reInsert（金利変更に伴う非 batch ノードの再挿入） | parity, invariant=CORE-ST-INV-001 / CORE-ST-INV-002 | ☐ | ☐ | | 未実施 | |
| CORE-ST-FR-005 | insertIntoBatch（batch へのノード追加） | parity, invariant=CORE-ST-INV-001 / CORE-ST-INV-003 / CORE-ST-INV-004 | ☐ | ☐ | | 未実施 | |
| CORE-ST-FR-006 | removeFromBatch（batch ノードの除去） | parity, invariant=CORE-ST-INV-002 / CORE-ST-INV-003 / CORE-ST-INV-004 | ☐ | ☐ | | 未実施 | |
| CORE-ST-FR-007 | reInsertBatch（batch slice 全体の再挿入） | parity, invariant=CORE-ST-INV-001 / CORE-ST-INV-003 | ☐ | ☐ | | 未実施 | |
| CORE-ST-FR-008 | validInsertPosition（hint 位置の有効性検証） | parity, unit（境界: 空リスト・先頭・末尾・同率・batch 境界） | ☐ | ☐ | | 未実施 | |
| CORE-ST-FR-009 | findInsertPosition（挿入位置の探索・hint fallback） | parity, unit（hint 無効化の 4 分岐・両方向探索の収束）, fuzz（任意 hint で結果位置が常に valid） | ☐ | ☐ | | 未実施 | |
| CORE-ST-FR-010 | 一覧系 view 関数・自動 getter 群 | parity | ☐ | ☐ | | 未実施 | |

### 14.2 不変条件（CORE-ST-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-ST-INV-001 | 金利降順整列 | invariant / parity（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-ST-INV-002 | 双方向リンク・番兵・size の整合 | invariant / parity（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-ST-INV-003 | batch slice の連続性 | invariant / parity（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-ST-INV-004 | exists とノード状態の整合 | invariant / parity（台帳定義） | ☐ | ☐ | | 未実施 | |

### 14.3 セキュリティ要件（CORE-ST-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-ST-SEC-001 | 書込み権限の限定とノード実在性の信頼委譲 | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-ST-SEC-002 | hint 非依存の健全性（hint griefing 耐性） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 14.4 イベント・監視要件（CORE-ST-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-ST-EVT-001 | `TroveManagerAddressChanged`（発火: constructor のみ（1 回）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-ST-EVT-002 | `BorrowerOperationsAddressChanged`（発火: constructor のみ（1 回）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 14.5 失敗時・異常系挙動（CORE-ST-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-ST-ERR-001 | revert 文字列一覧 | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |


## 15. TroveNFT（CORE-TN）

### 15.1 機能要件（CORE-TN-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TN-FR-001 | constructor（name/symbol の導出とアドレス束縛） | parity / deployment テスト | ☐ | ☐ | | 未実施 | |
| CORE-TN-FR-002 | mint（Trove 開設時の NFT 発行） | parity, unit（TM 限定・二重 mint 不可） | ☐ | ☐ | | 未実施 | |
| CORE-TN-FR-003 | burn（Trove クローズ・清算時の NFT 焼却） | parity, unit（TM 限定・不存在 burn の revert） | ☐ | ☐ | | 未実施 | |
| CORE-TN-FR-004 | tokenURI（MetadataNFT 委譲によるオンチェーンメタデータ） | parity, unit（status 別・zombie・不存在 revert） | ☐ | ☐ | | 未実施 | |
| CORE-TN-FR-005 | ERC-721 標準面（移転・承認・照会・ERC-165） | parity（ERC-721 標準挙動） | ☐ | ☐ | | 未実施 | |
| CORE-TN-FR-006 | MetadataNFT — オンチェーンメタデータ描画（catalog） | parity（uri 構造・属性・SVG 出力の同一性） | ☐ | ☐ | | 未実施 | |

### 15.2 不変条件（CORE-TN-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TN-INV-001 | NFT と Trove の 1:1 対応 | invariant / parity（台帳定義） | ☐ | ☐ | | 未実施 | |

### 15.3 セキュリティ要件（CORE-TN-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TN-SEC-001 | mint/burn の TroveManager 限定 | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-TN-SEC-002 | mint 時の受領者コールバック排除 | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 15.4 イベント・監視要件（CORE-TN-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TN-EVT-001 | `Transfer`（発火: mint（from=0）/ burn（to=0）/ 移転） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-TN-EVT-002 | `Approval`（発火: `approve`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-TN-EVT-003 | `ApprovalForAll`（発火: `setApprovalForAll`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 15.5 失敗時・異常系挙動（CORE-TN-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-TN-ERR-001 | revert 文字列一覧 | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 15.6 未決事項レジスタ（CORE-TN-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| CORE-TN-TBD-001 | 解決済 | active branch は dToken `setTokenInfo` 後に branch deploy して collection 名を確定。inert branch は placeholder collection 名の恒久化を許容し、product-facing 表示は frontend / indexer / marketplace metadata adapter の外部 alias で扱う。core source は改変しない | CORE-TN-FR-001 行の備考と連動 |
| CORE-TN-TBD-002 | 解決済 | JPYdfTroveNFT / JPYdfMetadataNFT deployment variant を採用し、deployed collection / tokenURI は JPYdf 表記を返す。upstream TroveNFT / MetadataNFT は参照・parity 用に温存する | |


## 16. JpydfToken（CORE-BT）

### 16.1 機能要件（CORE-BT-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BT-FR-001 | constructor（デプロイ初期化） | parity（デプロイ直後状態の base 同一性。name/symbol 値は CORE-MOD-001 差分として除外） | ☐ | ☐ | | 未実施 | |
| CORE-BT-FR-002 | setBranchAddresses（branch コントラクトの権限登録。CORE-MOD-009 により非ゼロ・contract-only） | parity / unit（onlyOwner・mapping 反映・イベント・zero/codeless reject） | ☐ | ☑ | `JpydfTokenTest::test_CoreAddressRegistrationRequiresContracts` | PASS(unit, exception) | 正常系 mapping/event は未実施 |
| CORE-BT-FR-003 | setCollateralRegistry（CR 設定と権限の恒久固定。CORE-MOD-009 により非ゼロ・contract-only） | parity / unit（設定値・renounce 後の owner==0・再呼出 revert・zero/codeless reject） | ☐ | ☑ | `JpydfTokenTest::test_CoreAddressRegistrationRequiresContracts` | PASS(unit, exception) | 正常系設定・renounce は既存 setup で暗黙実走。明示 event / 再呼出 unit は未実施 |
| CORE-BT-FR-004 | mint（発行） | parity / unit（権限 revert・残高/supply 反映）。供給と債務のコントラクト横断整合は CORE-SYS-INV-003 | ☐ | ☐ | | 未実施 | |
| CORE-BT-FR-005 | burn（償却） | parity / unit（4 系統の権限・残高不足 revert） | ☐ | ☐ | | 未実施 | |
| CORE-BT-FR-006 | sendToPool（SP への預入移転） | parity / unit（SP 限定・移転反映） | ☐ | ☐ | | 未実施 | |
| CORE-BT-FR-007 | returnFromPool（SP からの払戻移転） | parity / unit（SP 限定・移転反映） | ☐ | ☐ | | 未実施 | |
| CORE-BT-FR-008 | transfer / transferFrom（受取人制限付き ERC-20 移転） | parity / unit（制限 revert・標準移転） | ☐ | ☐ | | 未実施 | |
| CORE-BT-FR-009 | ERC-20 標準準拠（approve / allowance / 残高・供給 view ほか） | parity（標準挙動の base 同一性） | ☐ | ☐ | | 未実施 | |
| CORE-BT-FR-010 | name / symbol（トークン名・シンボル）🟡 | unit（固定値の検証）。parity 対象からは値を除外し、CORE-MOD-001 としてトレースする | ☐ | ☐ | | 未実施 | |
| CORE-BT-FR-011 | permit（EIP-2612）と EIP-712 ドメイン view 群 | parity（署名検証・nonce・revert 挙動）、unit（`DOMAIN_SEPARATOR` が name=`_NAME` から導出されること） | ☐ | ☐ | | 未実施 | |
| CORE-BT-FR-012 | 自明 view 関数群（owner / isOwner / collateralRegistryAddress） | parity | ☐ | ☐ | | 未実施 | |
| CORE-BT-FR-013 | bridgeAdmin と bridge readiness view 群 | unit（owner renounce 後の bridgeAdmin 存続、view の初期値、contract-only） | ✅ | ✅ | `JpydfTokenTest::test_BridgeReadinessIsDormantAfterCoreSetup`; `JpydfTokenTest::test_BridgeRolesMustBeContractsAndSeparated` | PASS | 実施コマンド: `forge test --match-contract JpydfTokenTest` |
| CORE-BT-FR-014 | bridge minter registry（propose / confirm / cancel / remove） | unit（timelock 境界、cancel、remove、count/view、admin/minter 分離） | ✅ | ✅ | `JpydfTokenTest::test_BridgeMinterLifecycleUsesTimelockAndSelfBurn`; `JpydfTokenTest::test_BridgeAdminCanCancelAndTransferTwoStep`; `JpydfTokenTest::test_BridgeRolesMustBeContractsAndSeparated` | PASS | 同上 |
| CORE-BT-FR-015 | bridgeMint / bridgeBurn（bridge supply path） | unit（非 minter revert、mint、self-burn、remove 後遮断、protocol recipient reject） | ✅ | ✅ | `JpydfTokenTest::test_BridgeMinterLifecycleUsesTimelockAndSelfBurn`; `JpydfTokenTest::test_BridgeReadinessIsDormantAfterCoreSetup`; `JpydfTokenTest::test_BridgeMintRejectsProtocolRecipients` | PASS | 同上 |
| CORE-BT-FR-016 | bridgeAdmin transfer / renounce | unit（2-step、非 pending reject、live minter renounce reject、minter 0 で renounce、admin/minter 分離） | ✅ | ✅ | `JpydfTokenTest::test_BridgeAdminCanCancelAndTransferTwoStep`; `JpydfTokenTest::test_BridgeAdminCannotRenounceWithLiveMinter`; `JpydfTokenTest::test_BridgeRolesMustBeContractsAndSeparated` | PASS | 同上 |

### 16.2 不変条件（CORE-BT-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BT-INV-001 | 権限構成の恒久固定 | invariant / parity（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BT-INV-002 | ERC-20 会計整合 | invariant / parity（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BT-INV-003 | bridge readiness の休眠性 | unit / deploy manifest evidence | ✅ | N/A | `JpydfTokenTest::test_BridgeReadinessIsDormantAfterCoreSetup` | PASS | deploy manifest evidence は未実施 |
| CORE-BT-INV-004 | bridge 有効化後の global canonical supply accounting | adapter invariant / off-chain accounting replay / fork・integration test / monitoring dry-run | ☐ | ☐ | | PLANNED | Day-2 bridge minter Stage A package before `proposeBridgeMinter` |

### 16.3 セキュリティ要件（CORE-BT-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BT-SEC-001 | mint 権限の信頼境界 | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BT-SEC-002 | 登録の不可逆性（デプロイ手順依存。zero/codeless は token 側で拒否） | parity / unit（zero/codeless reject）＋ deploy manifest review | ☐ | ☑ | `JpydfTokenTest::test_CoreAddressRegistrationRequiresContracts` | PASS(unit, exception) | branch 種別・registry 意味整合は deploy review が残る |
| CORE-BT-SEC-003 | allowance 非依存の burn / 内部移転 | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BT-SEC-004 | bridge minter 信頼境界 | unit（minter 追加 timelock / self-burn / remove 後遮断） | ✅ | ✅ | `JpydfTokenTest::test_BridgeMinterLifecycleUsesTimelockAndSelfBurn` | PASS | bridge adapter 側 rate limit / message verification は CORE-BT-SEC-005 / CORE-BT-GOV-001 と [Bridge-Minter-Activation-Gate](../../protocol/operations/runbooks/Bridge-Minter-Activation-Gate.md) Stage A で登録前に扱う |
| CORE-BT-SEC-005 | bridge adapter cap / rate / pause fail-closed gate | adapter unit / invariant / integration / incident dry-run | ☐ | ☐ | | PLANNED | adapter が cap / rate / global bridged supply cap / pause / replay・domain binding を持たない場合は bridge minter 登録不可。承認済み package があれば runtime cap 0 / paused で Stage A 登録可 |

### 16.4 ガバナンス・運用・アップグレード要件（CORE-BT-GOV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BT-GOV-001 | bridge minter activation gate | manual governance review / Safe・Timelock transaction evidence / adapter verification package / incident rehearsal | ☐ | ☐ | | PLANNED | [Bridge-Minter-Activation-Gate](../../protocol/operations/runbooks/Bridge-Minter-Activation-Gate.md) Stage A 完了前に `proposeBridgeMinter` しない。operator-only canary は adapter / endpoint enforced envelope 内、UI flag only / public route open / cap ramp は Stage B / C。post-confirm drift は Stage A evidence 失効 |

### 16.5 イベント・監視要件（CORE-BT-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BT-EVT-001 | `CollateralRegistryAddressChanged`（発火: `setCollateralRegistry`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BT-EVT-002 | `TroveManagerAddressAdded`（発火: `setBranchAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BT-EVT-003 | `StabilityPoolAddressAdded`（発火: `setBranchAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BT-EVT-004 | `BorrowerOperationsAddressAdded`（発火: `setBranchAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BT-EVT-005 | `ActivePoolAddressAdded`（発火: `setBranchAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BT-EVT-006 | ERC-20 `Transfer(address from, address to, uint256 value)`（発火: mint（from=0）/ burn（to=0）/ 各移転） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BT-EVT-007 | ERC-20 `Approval(address owner, address spender, uint256 val…（発火: `approve` / `permit` / allowance 変動） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BT-EVT-008 | `OwnershipTransferred`（発火: constructor / `_renounceOwnership`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BT-EVT-009 | `EIP712DomainChanged()`（発火: 発火しない（ERC-5267 宣言のみ・ドメイン不変）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-BT-EVT-010 | bridge readiness events | unit（admin transfer / minter lifecycle / bridge mint-burn event emission）＋ Day-2 adapter accounting monitor | ✅ | N/A | `JpydfTokenTest::test_BridgeReadinessEventsExposeLifecyclePayloads` | PASS(unit) | proposal / cancel / confirm / mint / burn / remove / admin transfer / renounce の event payload を検証。Day-2 は CORE-BT-INV-004 の accounting alert と連動 |

### 16.6 失敗時・異常系挙動（CORE-BT-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-BT-ERR-001 | 失敗時挙動（require 文字列） | parity / unit（台帳定義） | ☐ | ☑ | `JpydfTokenTest::test_CoreAddressRegistrationRequiresContracts`; bridge role tests | PASS(unit, partial) | core address zero/codeless と bridge role 系は検証済み。既存 base require 群の全量は未実施 |


## 17. CollateralRegistry（CORE-CR）

### 17.1 機能要件（CORE-CR-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CR-FR-001 | constructor（branch 構成の固定と baseRate bootstrap） | parity / unit（境界 1・10・11、初期 baseRate、未使用 slot のゼロ） | ☐ | ☐ | | 未実施 | |
| CORE-CR-FR-002 | redeemCollateral（branch 横断 redemption） | parity（配分・truncation・fallback・rate 計算・burn 額）、invariant=CORE-CR-INV-001〜003 | ☐ | ☐ | | 未実施 | |
| CORE-CR-FR-003 | getRedemptionRate（現 baseRate での実効 rate） | parity | ☐ | ☐ | | 未実施 | |
| CORE-CR-FR-004 | getRedemptionRateWithDecay（decay 適用後の実効 rate） | parity | ☐ | ☐ | | 未実施 | |
| CORE-CR-FR-005 | getRedemptionRateForRedeemedAmount（指定額 redeem 時の rate 見積り） | parity | ☐ | ☐ | | 未実施 | |
| CORE-CR-FR-006 | getRedemptionFeeWithDecay（数量に対する fee 計算） | parity | ☐ | ☐ | | 未実施 | |
| CORE-CR-FR-007 | getEffectiveRedemptionFeeInJpydf（JPYdf 建て実効 fee） | parity | ☐ | ☐ | | 未実施 | |
| CORE-CR-FR-008 | getToken / getTroveManager（index → branch 参照） | parity / unit（10 以上 revert・未使用 slot のゼロ返却） | ☐ | ☐ | | 未実施 | |
| CORE-CR-FR-009 | 自明 view 関数群（baseRate / lastFeeOperationTime / totalCollaterals / jpydfToken） | parity | ☐ | ☐ | | 未実施 | |

### 17.2 不変条件（CORE-CR-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CR-INV-001 | baseRate の上限 | invariant / parity（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-CR-INV-002 | 実効 rate の範囲 | invariant / parity（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-CR-INV-003 | lastFeeOperationTime の単調性 | invariant / parity（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-CR-INV-004 | branch 構成の不変性 | invariant / parity（台帳定義） | ☐ | ☐ | | 未実施 | |

### 17.3 セキュリティ要件（CORE-CR-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CR-SEC-001 | 配分の厳密性と truncation | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-CR-SEC-002 | 価格・redeemability の外部依存 | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 17.4 イベント・監視要件（CORE-CR-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CR-EVT-001 | `BaseRateUpdated`（発火: constructor（初期値）/ `redeemCollateral`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-CR-EVT-002 | `LastFeeOpTimeUpdated`（発火: `redeemCollateral`（経過 1 分以上の場合のみ）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 17.5 失敗時・異常系挙動（CORE-CR-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-CR-ERR-001 | 失敗時挙動（require 文字列） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |


## 18. AddressesRegistry（CORE-AR）

### 18.1 機能要件（CORE-AR-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AR-FR-001 | constructor（branch リスクパラメータの検証と固定） | parity / unit（各境界値でのカスタムエラー・immutable 反映） | ☐ | ☐ | | 未実施 | |
| CORE-AR-FR-002 | setAddresses（アドレス一括配線と ownership renounce） | parity / unit（onlyOwner・18 値反映・18+1 イベント・renounce 後の再呼出 revert） | ☐ | ☐ | | 未実施 | |
| CORE-AR-FR-003 | branch リスクパラメータ getter 群（CCR / SCR / MCR / BCR / 清算ペナルティ） | parity | ☐ | ☐ | | 未実施 | |
| CORE-AR-FR-004 | アドレス getter 群（全 18 アドレス＋owner / isOwner） | parity（`setAddresses` 前後の値） | ☐ | ☐ | | 未実施 | |

### 18.2 不変条件（CORE-AR-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AR-INV-001 | リスクパラメータの範囲と不変性 | invariant / parity（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-INV-002 | 配線の一回性 | invariant / parity（台帳定義） | ☐ | ☐ | | 未実施 | |

### 18.3 セキュリティ要件（CORE-AR-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AR-SEC-001 | 配線値の無検証（デプロイ手順依存） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 18.4 イベント・監視要件（CORE-AR-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AR-EVT-001 | `CollTokenAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-002 | `BorrowerOperationsAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-003 | `TroveManagerAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-004 | `TroveNFTAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-005 | `MetadataNFTAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-006 | `StabilityPoolAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-007 | `PriceFeedAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-008 | `ActivePoolAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-009 | `DefaultPoolAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-010 | `GasPoolAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-011 | `CollSurplusPoolAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-012 | `SortedTrovesAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-013 | `InterestRouterAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-014 | `HintHelpersAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-015 | `MultiTroveGetterAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-016 | `CollateralRegistryAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-017 | `JpydfTokenAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-018 | `WETHAddressChanged`（発火: `setAddresses`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-AR-EVT-019 | `OwnershipTransferred`（発火: constructor / `_renounceOwnership`） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 18.5 失敗時・異常系挙動（CORE-AR-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-AR-ERR-001 | 失敗時挙動（カスタムエラー） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |


## 19. HintHelpers（CORE-HH）

### 19.1 機能要件（CORE-HH-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-HH-FR-001 | getApproxHint（乱択サンプリングによる近似 hint 探索） | parity（base 同一挙動。シード固定で決定的）/ unit | ☐ | ☐ | | 未実施 | |
| CORE-HH-FR-002 | predictOpenTroveUpfrontFee（openTrove の fee 試算） | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-HH-FR-003 | predictAdjustInterestRateUpfrontFee（金利調整の fee 試算） | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-HH-FR-004 | forcePredictAdjustInterestRateUpfrontFee（無条件の金利調整 fee 試算） | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-HH-FR-005 | predictAdjustTroveUpfrontFee（債務増額調整の fee 試算） | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-HH-FR-006 | predictAdjustBatchInterestRateUpfrontFee（バッチ金利変更の fee 試算） | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-HH-FR-007 | predictOpenTroveAndJoinBatchUpfrontFee（バッチ加入開設の fee 試算） | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-HH-FR-008 | predictJoinBatchInterestRateUpfrontFee（バッチ加入の fee 試算） | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-HH-FR-009 | predictRemoveFromBatchUpfrontFee（バッチ離脱の fee 試算） | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-HH-FR-010 | 定数・参照 view 関数群 | parity | ☐ | ☐ | | 未実施 | |

### 19.2 不変条件（CORE-HH-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-HH-INV-001 | fee 試算と実請求の一致 | parity（BO 実行結果との突合） | ☐ | ☐ | | 未実施 | |

### 19.3 セキュリティ要件（CORE-HH-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-HH-SEC-001 | 非保持・非干渉 | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 19.4 失敗時・異常系挙動（CORE-HH-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-HH-ERR-001 | 無効な _collIndex | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |


## 20. MultiTroveGetter（CORE-MTG）

### 20.1 機能要件（CORE-MTG-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-MTG-FR-001 | getMultipleSortedTroves（金利順の Trove 一括取得） | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-MTG-FR-002 | getDebtPerInterestRateAscending（金利昇順の債務分布取得） | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-MTG-FR-003 | 参照 view 関数群 | parity | ☐ | ☐ | | 未実施 | |

### 20.2 セキュリティ要件（CORE-MTG-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-MTG-SEC-001 | 非保持・非干渉 | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 20.3 失敗時・異常系挙動（CORE-MTG-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-MTG-ERR-001 | 無効な _collIndex | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |


## 21. DebtInFrontHelper（CORE-DFH）

### 21.1 機能要件（CORE-DFH-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-DFH-FR-001 | getDebtBetweenInterestRates（金利帯の債務合計） | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-DFH-FR-002 | getDebtBetweenInterestRateAndTrove（特定 Trove 直前までの債務合計） | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-DFH-FR-003 | 参照 view 関数群 | parity | ☐ | ☐ | | 未実施 | |

### 21.2 セキュリティ要件（CORE-DFH-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-DFH-SEC-001 | 非保持・非干渉 | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 21.3 失敗時・異常系挙動（CORE-DFH-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-DFH-ERR-001 | 無効な _collIndex | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |


## 22. RedemptionHelper（CORE-RH）

### 22.1 機能要件（CORE-RH-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-RH-FR-001 | redeemCollateral（min-out 付き償還ラッパー） | parity / unit（min-out 違反 revert・残余返還）/ invariant=CORE-RH-INV-001 | ☐ | ☐ | | 未実施 | |
| CORE-RH-FR-002 | simulateRedemption（償還シミュレーション） | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-RH-FR-003 | truncateRedemption（最適償還量への切詰めと受領見積り） | parity / unit | ☐ | ☐ | | 未実施 | |
| CORE-RH-FR-004 | 参照 view 関数群 | parity | ☐ | ☐ | | 未実施 | |
| CORE-RH-FR-005 | constructor（デプロイ時整合性検証） | unit（不一致 constructor revert） | ☐ | ☐ | | 未実施 | |

### 22.2 不変条件（CORE-RH-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-RH-INV-001 | 資金パススルー（残高不変） | invariant / unit | ☐ | ☐ | | 未実施 | |

### 22.3 セキュリティ要件（CORE-RH-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-RH-SEC-001 | 資金非保持・rescue なし | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 22.4 失敗時・異常系挙動（CORE-RH-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-RH-ERR-001 | 失敗時挙動 | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |


## 23. LiquidationCandidateGetter（CORE-LCG）

### 23.1 機能要件（CORE-LCG-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-LCG-FR-001 | getLiquidationCandidates（清算候補のページング走査）🟢 | unit（🟢 DF 独自のため parity 対象外。ICR 境界・ページング・空リスト・zombie 除外） | ☐ | ☐ | | 未実施 | |
| CORE-LCG-FR-002 | 参照 view 関数群 🟢 | unit | ☐ | ☐ | | 未実施 | |
| CORE-LCG-FR-003 | lastZombieTroveId の清算候補化 🟢 | unit（last zombie あり/なし・ICR 境界・debt/coll 取得・combined API の末尾追記）＋ bot scan unit/integration | ☐ | ☐ | | 未実施 | CORE-LCG-TBD-001 解決 |

### 23.2 不変条件（CORE-LCG-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-LCG-INV-001 | core 非干渉 🟢 | unit / コードレビュー（mutability・依存方向） | ☐ | ☐ | | 未実施 | |

### 23.3 失敗時・異常系挙動（CORE-LCG-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-LCG-ERR-001 | 無効な _collIndex 🟢 | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 23.4 未決事項レジスタ（CORE-LCG-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| CORE-LCG-TBD-001 | 解決済 | LCG 拡張で `lastZombieTroveId` を候補化し、Rust bot は `include_last_zombie=true` で `getLiquidationCandidatesWithLastZombie` を使う。複数 zombie 網羅は indexer 後続課題 | CORE-LCG-FR-003 と連動 |


## 24. 共通基盤 Dependencies / Types（CORE-LIB）

### 24.1 機能要件（CORE-LIB-FR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-LIB-FR-001 | file-level システム定数の提供 | parity（🟡 2 件を除く全定数の base 同値性 = CORE-LIB-INV-001） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-FR-002 | MIN_DEBT（最小負債の変更）🟡 | unit（境界値: `MIN_DEBT` ちょうど / 未満）、🟡 差分テスト（値が 300_000e18 であること） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-FR-003 | COLL_GAS_COMPENSATION_CAP（担保ガス補償上限の変更）🟡 | unit（cap 到達 / 非到達の境界）、🟡 差分テスト（値が 1_000 ether であること） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-FR-004 | DF ブランチ別定数群の追記 🟢 | unit（各定数とコメント値・[Parameters.md](../../Parameters.md) の一致、`*_WETH`/`*_SETH`/`BCR_ALL` の base 同値性維持）、静的検査（production コードからの未参照確認） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-FR-005 | constructor（AddressesRegistry からの参照解決） | parity / deploy 検証（配線一致） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-FR-006 | getEntireBranchColl / getEntireBranchDebt（ブランチ全体の集計） | parity / invariant=CORE-SYS-INV-001 | ☐ | ☐ | | 未実施 | |
| CORE-LIB-FR-007 | _getTCR / _checkBelowCriticalThreshold（TCR と CT 判定） | parity / unit（負債 0 ブランチで false になること） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-FR-008 | _calcInterest（単利計算プリミティブ） | parity / unit（丸め方向） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-FR-009 | 比較・差分・担保比率ヘルパー | parity / unit（debt=0 → max uint、丸め方向） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-FR-010 | decMul / _decPow（18 桁固定小数の累乗） | parity / unit（n=0 / n=1 / 偶奇 / キャップ境界 525,600,000） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-FR-011 | 所有者モデル（constructor / owner / isOwner / onlyOwner） | parity / unit（非 owner revert・文字列一致） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-FR-012 | _renounceOwnership（配線完了後の所有権放棄） | parity / unit（放棄後の onlyOwner 恒久 revert・イベント引数） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-FR-013 | TroveId 型（Deprecated: production `src` から削除） | unit（`SortedTroves` test-local helper）/ static（`Types/TroveId.sol` 不在） | ☐ | ☐ | | 未実施 | production 未参照 helper のため fresh deploy / audit surface 最小化として撤回 |
| CORE-LIB-FR-014 | BatchId 型 | parity | ☐ | ☐ | | 未実施 | |
| CORE-LIB-FR-015 | TroveChange 構造体（操作差分の受け渡し） | parity / invariant=CORE-SYS-INV-002 | ☐ | ☐ | | 未実施 | |
| CORE-LIB-FR-016 | LatestTroveData 構造体（Trove 最新状態スナップショット） | parity / unit（バッチ・非バッチの一致性） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-FR-017 | LatestBatchData 構造体（バッチ最新状態スナップショット） | parity / unit | ☐ | ☐ | | 未実施 | |

### 24.2 不変条件（CORE-LIB-INV）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-LIB-INV-001 | upstream 定数の base 同値性 | parity（base との定数値突き合わせ） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-INV-002 | 派生定数の厳密性 | unit（定数式の評価値検査） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-INV-003 | リスト終端規約の同値性 | unit（定数同値）／ コントラクト横断の規定は CORE-SYS-INV-014 | ☐ | ☐ | | 未実施 | |

### 24.3 セキュリティ要件（CORE-LIB-SEC）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-LIB-SEC-001 | _renounceOwnership の呼出元無検証 | 静的検査（全呼出箇所が onlyOwner 文脈であること） | ☐ | ☐ | | 未実施 | |

### 24.4 イベント・監視要件（CORE-LIB-EVT）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-LIB-EVT-001 | `ActivePoolAddressChanged`（発火: constructor（CORE-LIB-FR-005）） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-EVT-002 | `DefaultPoolAddressChanged`（発火: 同上） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-EVT-003 | `PriceFeedAddressChanged`（発火: 同上） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-EVT-004 | `OwnershipTransferred`（発火: constructor（0 → initialOwner）／ `_renounceOwnersh…） | parity / unit（台帳定義） | ☐ | ☐ | | 未実施 | |

### 24.5 失敗時・異常系挙動（CORE-LIB-ERR）

| ID | 要件（要約） | 規定検証手段 | 正常系 | 異常系 | テスト実体 | 結果 | 備考 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CORE-LIB-ERR-001 | 算術 Panic のみ（カスタムエラーなし） | fuzz（境界域での Panic 確認） | ☐ | ☐ | | 未実施 | |
| CORE-LIB-ERR-002 | onlyOwner 違反の revert | unit（文字列一致） | ☐ | ☐ | | 未実施 | |

### 24.6 未決事項レジスタ（CORE-LIB-TBD）

| ID | 状態 | 扱い | 備考 |
| --- | --- | --- | --- |
| CORE-LIB-TBD-001 | 未決 | inert ブランチ（Br2–7）の Day-1 確定 immutable 値（Underlying のみ TBD）を、Day-2 有効化前に確定 Underlying のストレスで**検証**し、Day-1 値が妥当でなければ（値は immutable で in-place 変更不可のため）再デプロイ＝移行を検討（恒久 inert 据置もありうる。「再導出して置換」ではない。[Collateral Parameter Policy](../../protocol/product/policies/Collateral-Parameter-Policy.md) §2.4）。Day-1 検証は「mintCap=0 で inert」のみ | CORE-MOD-005 行と連動 |

---

## 25. 完了基準・改訂規則

### 25.1 完了基準（parity 受け入れ）

以下をすべて満たしたとき、「コアの全関数・全状態変数がフォーク元と同一に機能し、DF 差分が台帳どおりに限られている」と主張できる（spec §13.3 と対）:

1. **網羅**: spec から抽出した全 `CORE-*` ID（§3 の集計と一致）が本台帳に存在し、欠番・対象外（未決 TBD）はすべて理由付きで明示されている。
2. **全行クローズ**: 全行の結果が `PASS` または `N/A(理由)`。`未実施` / `FAIL` / `BLOCKED` が残る間は完了と書かない。
3. **正常系・異常系**: 各 ID の正常系・異常系がともに `✅` または `N/A(理由)`。
4. **静的 parity**: §4 行 1（guard）・行 4（DFStabilityPool diff）・行 5（Constants 突合）が PASS。
5. **証跡**: 全 PASS 行にテスト実体（実行ログ転記）とキャンペーン ID があり、§2 から commit SHA・実行コマンドへ遡れる。
6. **二重チェック**: spec の `CORE-*` 全集合と本台帳の ID 全集合の機械 diff（grep ベース）が空であることを、キャンペーンごとに再確認する（spec は更新され続けるため）。

### 25.2 改訂規則

- 正本 spec に ID が追加・改訂されたら、本台帳に行を追加・更新する（**spec 側の改訂が先・台帳が追随**。逆方向の規定はしない）。
- ID は spec の append-only 規約に従う。台帳側で独自 ID を発番しない（非 ID チェック行は §4 の # 連番と内容文で識別する）。
- テスト名・結果は本台帳のみが持つ。正本 spec へ書き戻さない（ドキュメント標準ガードレール 1・2 の遵守）。
- 🔵 行で spec と実装の矛盾を発見した場合の処理は §1.3 判定原則 8（base が正・spec 改訂が先）に従う。

### 25.3 関連文書

- [Liquity-v2-Core-Spec.md](../../protocol/product/spec/Liquity-v2-Core-Spec.md) — 検証対象の正本（`CORE-*` ID・差分台帳 `CORE-MOD-*`・§13 受け入れ基準・`MIN_DEBT`）
- [JpydfToken.md](../../protocol/product/spec/JpydfToken.md) — Core Spec から分離した JpydfToken の `CORE-BT-*` 規範本文（namespace 維持・本台帳の ID 行と同証跡）
- [要件定義ドキュメント標準](../../Requirements-Spec-Standard.md) — ID 規約・「テスト名は doc に書かない」ガードレールの正本
- [Parameters.md](../../Parameters.md) — `COLL_GAS_COMPENSATION_CAP`・ブランチパラメータの値正本（§4 行 5・CORE-MOD-003/005 の突合先）
- [Development-Plan.md](../plans/Development-Plan.md) — 現在の作業・監査完了条件
- `engineering/historical-reviews/` — manual 検証（構成レビュー・deploy 検証）の記録置き場
