# フロントエンド開発計画（Frontend Development Plan）

> **jpydf-v2 フロントエンド 3 サーフェスの実装計画・進捗トラッカー。**
> 要件の正本は [../Frontend.md](../../protocol/product/spec/Frontend.md)（`FRNT-*` ID）。本書は実装の分解・決定記録・ローカル検証手順のみを扱い、要件を再定義しない（FRNT-GOV-003）。
> 本書内の進捗記号は、✅ 完了 / 🟢 実装済 / 🟡 進行中 / 🔴 未着手とする。横断的な現行作業は [Development-Plan.md](./Development-Plan.md) を参照する。

---

## 0. スコープ・方針

- **対象**: (A) ユーザーアプリ `frontend/app`（上流 Liquity v2 app の最小差分フォーク）／(B) 管理者コンソール `frontend/console`（新規）／(C) 運用ダッシュボード `frontend/ops`（新規）。
- **最初のマイルストーン**: ローカル環境（anvil + Phase 4 dToken 配線デプロイ）で 3 サーフェスすべてが実データに対して動作し、主要フローが e2e で検証できること（Frontend.md §13「e2e-local を一級の受け入れ手段とする」）。
- **上流最小改変**（FE 原則 1）: (A) は上流 Liquity v2 app の fork として保つが、JPYdf-owned frontend surface（表示文言・型・request schema・local storage key・query key・flow ID 等）は JPYdf 名へ正規化する。上流由来の package 名・vendor component 名・base protocol spec 参照は対象外とし、upstream の更新を取り込める形を維持する。

## 1. 決定記録（本計画で確定した実装判断）

| # | 決定 | 根拠 / 影響 |
| --- | --- | --- |
| D-1 | **FRNT-TBD-005 の production gate 化**: (B)(C) はモノレポ内の独立パッケージ `frontend/console`（Vite, port 3001）/ `frontend/ops`（Vite, port 3002）として実装済み。管理者コンソールの本番公開条件は [Admin-Console-Production-Gate.md](../../contributors/deltaforesight/delivery-plans/Admin-Console-Production-Gate.md) に集約し、具体 domain / IdP / RPC key / noindex / role snapshot / Safe calldata evidence は launch evidence で採取する | local 開発速度を保ったまま、サーフェス分離（FE 原則 6 / FRNT-SEC-007）を production gate と証跡に接続する |
| D-2 | (B)(C) のバインディングは `frontend/df-shared/generate.ts` が deploy manifest + forge artifacts から機械生成（`generated/addresses.ts` / `abis.ts`） | FRNT-FR-001/003（手書きアドレス・ABI の排除） |
| D-3 | 借入フローは **Underlying 建て入力 + UI 多段ラップ**（approve → `Vault.deposit` → approve → `openTroveWithRawETH`）で暫定実装。`CollateralYieldZapper` は active branch の deploy / manifest / binding まで配線済みで、user app flow 採用後に 1 Tx へ集約 | FRNT-FR-013 の「Underlying 建て入力」は満たすが、「1 Tx 集約」は未充足。直接経路（ARCH-005）は維持しつつ、production PASS は CYZ の user app 採用・e2e 確認後に判定する |
| D-4 | ローカル e2e の署名は **dev wallet コネクタ**（`NEXT_PUBLIC_DEV_WALLET=true` 時のみ、anvil の unlocked アカウントへ JSON-RPC 委譲）。アプリは秘密鍵を一切保持しない | FRNT-INV-004 / FRNT-FR-005-2 を維持したまま e2e-local を自動化 |
| D-5 | inert ブランチ（5-7, underlying 未確定）は (A) では非表示（env 生成時に skip）、(C) では「準備中」表示 | FRNT-FR-012 要件 3 の両様運用 |
| D-6 | subgraph はローカル必須にしない（docker 不在環境を許容）。`SUBGRAPH_CHECK=false` + 劣化表示で運用し、一覧系は RPC + stored trove IDs でフォールバック | FRNT-ERR-002 の劣化動作をそのまま検証対象にする |
| D-7 | anvil は `--base-fee 0 --gas-limit 60000000` で起動し、deploy/seed の forge broadcast は `--slow` 必須 | anvil 1.5.x がバースト送信 tx を黙って破棄する実測問題への対策（運用ノート §4） |
| D-8 | **FRNT-TBD-004 の初期 backend**: `frontend/ops export-stats` が RPC snapshot から公開健全性 JSON を生成し、`frontend/app` は `NEXT_PUBLIC_PROTOCOL_STATS_URL` で同 JSON を読む。秘密・RPC URL・運用担当・runbook は出力しない。 | 上流 `api.liquity.org` を本番参照せず、FRNT-FR-036 の公開トランスペアレンシーを先に満たす。hosting/所有/runtime health は `Frontend-Production-Delivery-Gate.md` の evidence 対象、APR 時系列は Day-2 |

## 2. ローカルスタック（再現手順）

```bash
# 1. チェーン
anvil --port 8545 --chain-id 31337 --base-fee 0 --gas-limit 60000000

# 2. デプロイ + Multicall3 注入 + デモデータ + app 用 env 生成 + (B)(C) バインディング生成
cd contracts && ./utils/local-stack.sh

# 3. ユーザーアプリ (A)  http://localhost:3000
cd frontend/app && pnpm build-deps && pnpm dev   # local URL は repo schema fallback。runtime data は subgraph 同期後に確認
# query/schema だけを別出力で検証する場合:
# SUBGRAPH_SCHEMA_FILE=../../subgraph/schema.graphql GRAPHQL_CODEGEN_OUT=/tmp/jpydf-app-graphql-codegen/ pnpm build-graphql

# 4. 管理者コンソール (B)  http://localhost:3001
cd frontend/console && pnpm dev

# 5. 運用ダッシュボード (C)  http://localhost:3002
cd frontend/ops && pnpm dev
```

- `local-stack.sh`は8 branchをdeployし、dwstETH / dUSDCだけへmock data sourceとseedを設定する。branch 2–7はinertのまま維持し、profileとseederの不一致は起動前に拒否する。`local-demo`はDay-1 launch初期残高のEvidenceではない。
- active branchのdemo価格: dwstETH ≈ ¥600,000.6 / dUSDC ≈ ¥150（USD/JPY ≈ 150）。

## 3. フェーズ別トラッカー

| Phase | 状態 | 内容 / 主な対象 FRNT-ID |
| --- | --- | --- |
| FE-0 ローカルスタック | ✅ | anvil + Phase 4 デプロイ + seed + env/バインディング生成 + app 起動（FRNT-FR-001, 003, 004） |
| FE-A1 (A) DF 化 | ✅ | JPY 表示（FR-009）/ JPYdf 表記置換・リンク台帳差替（FR-011）/ 8 ブランチ動的化（FR-012）/ Stake 無効化（FR-022）/ Multiply 削除（FR-023）。Stake / Multiply は Day-1 user app route / tx-flow / env flag を持たない |
| FE-A2 (A) Vault 画面 | 🟡 | dToken mint/redeem + 即時/遅延見込み表示（FR-015）/ WithdrawRequest 一覧・claim（FR-016）は実装済み。借入は Underlying 建て多段フローまでで、CYZ address / ABI は取得可能。FRNT-FR-013 の 1 Tx 集約と FRNT-FR-014 の Underlying 建て close/withdraw は user app flow 採用待ち |
| FE-A3 (A) 健全性表示 | ✅ | ブランチ TCR 列・backing 比警告（FR-019）。shutdown/pause の操作ブロックは upstream 機構 + Vault pause バナーで対応（ERR-005） |
| FE-B (B) コンソール | ✅ | 提案ビルダー（FR-025）/ オラクル source 差替（FR-026）/ pause（FR-027）/ ALLOCATOR 運用（FR-028）/ 保留キュー（FR-029）/ 証跡（FR-030）— 準備・可視化 + ローカル実行（FR-024） |
| FE-C (C) ダッシュボード | ✅ | ブランチ概況（FR-031）/ オラクル監視・JPY/USD 共通依存（FR-032）/ Vault・Strategy（FR-033）/ Treasury（FR-034）/ アラート表示（FR-035）/ 公開統計（FR-036） |
| FE-D e2e ドリル | ✅ | 借入→調整→Earn→redeem→claim ＋ 管理操作の反映（pause→(A) ブロック、allocate→(C) 反映、mock 価格変更→健全性変化） |
| FE-E 仕上げ | 🔴 | 残課題（§5）・CI ゲート（FRNT-INV-002 定数突合 / FR-004 env スキーマ / SEC-001 依存監査） |

## 4. 運用ノート（ローカル環境の既知の挙動）

1. **anvil の tx 破棄**: bursty な forge broadcast で一部 tx が pool から黙って消える（実測: 336 tx 中 58 件）。`--slow` で解消。base fee も 0 固定にする（EIP-1559 スパイラルで maxFee 不足が起きる）。
2. **demo trove path は `./deploy` から削除済み**。ローカルのデモデータは `SeedLocalDemo` で投入する。
3. **Multicall3**: 現行 deploy script はローカルに Multicall3 を配置しないため、`local-stack.sh` が canonical アドレスへ runtime code を注入する（app の batched read 前提）。
4. **wagmi 再接続**: dev wallet コネクタはページリロード後の再接続が `connecting` で停滞することがあり、dev wallet 有効時のみ自動昇格処理を入れている（`services/Ethereum.tsx`）。
5. **claim 可否判定はチェーン時刻基準**: wall clock で判定するとローカルの time warp と乖離する（実測バグ→修正済み。`useWithdrawRequests` が latest block timestamp で `ready` を返す）。
6. **subgraph 不在の影響**: 取引履歴・平均金利・金利分布ヒストグラム等の一覧系が「…」表示になる。操作系（RPC 由来）はすべて動作する。

## 5. 残課題（次スプリント候補）

- 🟡 **FRNT-FR-002 / INV-002**: `MIN_DEBT` ミラーは `300_000` に同期済みで `frontend/app/src/constants.test.ts` が回帰を防ぐ。残るのは全定数ミラー（MCR/CCR/SCR・decimals 等）の自動生成または CI 突合ゲート。
- 🔴 **FRNT-FR-013 / FRNT-FR-014**: `CollateralYieldZapper` の deploy manifest・`df-shared` binding・app env と Sky USDC→USDS converter 具象は完了。残るのは user app flow への採用、`SkyUsdcSUsdsYieldZapper` 自体の deploy manifest / `df-shared` binding / app env、JPYdf swap route の審査。現行の upstream 系 `Leverage*Zapper` 多段経路は local fallback であり、production 1 Tx 集約・Underlying 建て close/withdraw の完了条件ではない。
- 🟡 **FRNT-FR-010 / FRNT-TBD-008**: 文言カタログ外部化（ja/en）は継続課題。mainnet gate は [Frontend-UX-Readiness-Gate.md](../../contributors/deltaforesight/delivery-plans/Frontend-UX-Readiness-Gate.md) で定義済みで、primary locale / locale switch / JPYdf 用語・BOLD 残骸 / error copy evidence を採取する。
- 🔴 **FRNT-FR-020**: 取引履歴画面の subgraph 前提部分のローカル代替（graph-node を立てるか、軽量インデクサを足すか）。
- 🔴 **FRNT-FR-021 要件 3**: ジオブロック等の設定枠（既定無効のまま枠だけ用意）。
- 🔴 **FRNT-EVT-***: テレメトリ・外形監視（本番ホスティング確定後）。
- 🟡 **FRNT-TBD-004**: 公開健全性 JSON は `frontend/ops export-stats` で実装済み。`frontend/app` は `NEXT_PUBLIC_PROTOCOL_STATS_URL` で同 JSON を読める。production hosting/会社所有/runtime health は `Frontend-Production-Delivery-Gate.md` の evidence 採取へ移管。残る product work は APR 時系列 collector。
- 🟡 **FRNT-TBD-007**: 本番ドメイン・ホスティングは [Frontend-Production-Delivery-Gate.md](../../contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md) で gate 定義済み。残るのは実 domain / account / endpoint / monitor / rollback evidence の採取。
- 🟡 **FRNT-TBD-009**: mobile / in-wallet browser は [Frontend-UX-Readiness-Gate.md](../../contributors/deltaforesight/delivery-plans/Frontend-UX-Readiness-Gate.md) で gate 定義済み。残るのは viewport / wallet modal / tx confirmation / failure state evidence の採取。
- 🟡 **FRNT-TBD-006**: mirror 配信は Day-1 非採用、Day-2 optional gate として [Frontend-Mirror-Delivery-Policy.md](../../contributors/deltaforesight/delivery-plans/Frontend-Mirror-Delivery-Policy.md) で定義済み。残るのは実 mirror URL / CID / ENS / domain allowlist / incident announcement / rollback evidence の採取。
- 🔴 Multiply 再導入条件（FRNT-TBD-002）。
- 🔴 **RPC 既定値の迷い呼び出し排除**: ローカルで `eth.merkle.io`（viem の mainnet 既定 RPC）への CORS 失敗ログが出る。これは local-only の症状でも、本番では RPC 障害 / vendor leakage / user-visible error に直結するため mainnet blocker として扱う。production build / runtime health check は公式 RPC config が未設定、または viem public default へ到達可能な path が残る場合に fail-closed にする。
- 🟡 表示文言・owned data model の BOLD→JPYdf 正規化の**全数 grep 監査**（FRNT-FR-011 完了判定）: 到達可能画面は置換済み。無効化中の上流由来画面を再導入する場合は、事前に別 spec / route config / UI copy を定義し、旧 BOLD / upstream staking 系文言を残さない。

## 6. 検証ログ（e2e-local 実績）

| 日付 | 検証 | 結果 |
| --- | --- | --- |
| 2026-06-12 | (A) Vault deposit: 2 WETH → 2 dETH mint（approve→deposit、¥1,200,001.20 表示 = 2×オンチェーン価格） | ✅ tx 確定・残高反映 |
| 2026-06-12 | (A) Vault redeem: 1 dETH → 1 WETH 即時受取（buffer 58 WETH 表示・非保証文言） | ✅ tx 確定 |
| 2026-06-12 | (A) 借入 4 ステップ: Approve WETH → Wrap 4 WETH→dETH → Approve dETH → Open Position（5 dETH 担保 / 1,501,240 JPYdf 借入） | ✅ トローブ生成・ダッシュボード表示 |
| 2026-06-12 | (A) ダッシュボード: TVL ¥91M・供給 31M JPYdf・deploy 済み dToken branch の TCR 列・subgraph 劣化バナー | ✅ シード値と一致 |
| 2026-06-12 | seed: dUSDT 遅延償還キュー（9,000 USDT pending）・backingRatio=1.0・dETH 価格 ¥600,000.6（当時の dUSDT branch構成での記録・#1454前） | ✅ cast で確認 |
| 2026-06-12 | (C) 20/20 read 検証（deploy 済み dToken branch の価格・債務・TCR・queue・backing 全一致）＋ mock ETH/USD 4000→3000 で「TCR 126.4% < CCR 133%」警告発報→復元で正常化 | ✅ |
| 2026-06-12 | (B) 変更往復（setBufferConfig 2000→1500→2000）・権限なし署名者の拒否（decoded AccessControl revert）・オラクル propose→countdown→cancel・証跡表示 | ✅ |
| 2026-06-12 | 統合ドリル: deposit 7 WETH → (B) UI で setBufferConfig 1% + allocate（buffer 68→0.68）→ (A) redeem 7 dETH（見込み 0.68 即時+6.32 キュー表示どおり）→ Strategy push 補充 + 25h warp → (A) claim 成功 → 設定復元・queue 0 | ✅ |
| 2026-06-12 | guardian pause → (A) バナー表示・deposit 無効化 → unpause 復帰 | ✅ |
