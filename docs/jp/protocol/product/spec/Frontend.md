# 🖥 フロントエンド 要件定義（Frontend）

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Draft |
| Owner | DeltaForesight |
| 対象 | 🟡 ユーザーアプリ／🟢 Admin Control／🟢 Private Operations Monitor／🟢 Dune Public Analytics／browser 非依存 monitoring・public stats 共通基盤 |
| 関連doc | [Product-Overview](../Product-Overview.md)（SYS-FR/ARCH）/ [公開ユーザー向けフロントエンド操作要件](./Permissionless-User-Operations.md)（FRNT-FR-038）/ [dToken](./dToken.md) / [CollateralVault](./CollateralVault.md) / [Strategy](./strategies/Strategy.md) / [Oracle](./Oracle.md) / [Zapper](./Zapper.md) / [Treasury](../../roadmap/spec/Treasury.md) / [Parameters](../../../Parameters.md)（値の正本）/ [Public-Analytics-Private-Monitoring-Architecture](../../../contributors/deltaforesight/operations/Public-Analytics-Private-Monitoring-Architecture.md) / [Mainnet-Participant-Readiness-Gate](../../launch/gates/Mainnet-Participant-Readiness-Gate.md) |

> 本書は [要件定義ドキュメント標準](../../../Requirements-Spec-Standard.md) を**オフチェーン component に読み替えて適用**する。読み替え表:
>
> | 標準（コントラクト） | 本書（フロントエンド） |
> | --- | --- |
> | シグネチャ | 対象（サーフェス・画面・機能） |
> | 権限 | 対象ユーザー・到達制御 |
> | 事前条件（Checks）/ 動作（Effects） | 要件（番号付きの検証可能な振る舞い） |
> | revert / 早期 return | 異常時（縮退・ブロック・表示） |
> | 発火イベント | 計測（テレメトリ・監視） |
> | INV（オンチェーン不変条件） | 表示・構成の整合不変条件 |
>
> `Verification` の手段種別は §13 で定義する（`unit / component / e2e-local / build / ci-guard / visual / manual / monitor`）。

---

## 1. 目的・スコープ・非責務

**目的**: JPY DeFi プロトコル（🔵 Liquity v2 Core ＋ 🟢 dToken / Strategy / Oracle / Zapper / Treasury）に対する**オフチェーンの操作・可視化レイヤー**の要件を定義する。スマートコントラクト要件と同じ ID 規律（`FRNT-*`）で管理し、フロントエンドの実装変更が要件 ID へトレースできる状態を維持する。本書を `FRNT-*` 要件の正本とし、permissionless entrypoint と公開ユーザーアプリの操作カバレッジ・実行経路は FRNT-FR-038 およびその全件マトリクスである [公開ユーザー向けフロントエンド操作要件](./Permissionless-User-Operations.md) で管理する。

- **スコープ内（3 表示面＋共通基盤）**:
  - **(A) 🟡 ユーザーアプリ** — 借入・返済・dToken mint/redeem・Earn（SP）・Redemption・ポジション管理。上流 Liquity v2 app を継承し、DF 差分（JPY 建て・8 ブランチ・dToken 層・JPY DeFi / JPYdf ブランド）を加える。
  - **(B) 🟢 認証済み運用面** — GOV_MULTISIG / ALLOCATOR の操作準備を担う Admin Control と、全 branch の即時監視を担う Private Operations Monitor。鍵は持たず、monitor viewer と privileged operator を分離可能にする。
  - **(C) 🟢 公開分析** — Dune 上で on-chain の公開統計・履歴・Treasury flow を提供する。critical monitoring や User App runtime API の責務を持たない。
  - **共通基盤** — 設定・定数同期・ウォレット・トランザクション UX・データ取得・表示規約・セキュリティ・テレメトリに加え、browser 非依存の monitoring worker と DF-managed public stats publisher。
- **スコープ外**: コントラクト挙動そのもの（各 component spec が正本）／パラメータ値の決定（[Parameters.md](../../../Parameters.md)）／法務・規制文言の確定（表示枠のみ本書で定義）／マーケティングサイト（プロトコル操作を持たない静的サイト）。
- **非責務**: フロントエンドは**プロトコルの信頼根ではない**。コアと 🟢 各レイヤーはフロントエンド無しでも完全に稼働し（ARCH-005 と同型）、ユーザーはコントラクトを直接呼び出して同じ結果を得られる。フロントエンドの停止・改ざんは資産の安全性を直接毀損しない構造を保つ（毀損し得る経路は §9 SEC で統制する）。

---

## 2. 背景・設計方針

コアの「無改変フォーク」（ARCH-001/ADR-001）と同じ理由で、フロントエンドも**実戦検証済みの上流 Liquity v2 app を土台に最小差分で運用**する。上流は本家の利用実績によって UI ロジック（金利・LTV・hint 計算等）が検証済みであり、全面書き直しはその価値を捨てる。

- **FE 原則 1｜上流最小改変** — ユーザーアプリは上流 app の fork として保つが、JPYdf-owned frontend surface（表示文言・型・request schema・local storage key・query key・flow ID 等）は JPYdf 名へ正規化する。上流由来の package 名・vendor component 名・base protocol spec 参照は対象外とし、upstream の更新を取り込める形を維持する。
- **FE 原則 2｜オンチェーンが真実** — 表示する残高・価格・ポジションの信頼根は RPC 経由のコントラクト読み取り。subgraph・統計 API は補助インデックスであり、鮮度劣化を検出して縮退表示する（真実と混ぜない）。
- **FE 原則 3｜鍵を持たない** — フロントエンドはいかなる秘密鍵・特権も保持しない。ユーザー操作は本人のウォレット署名、特権操作（GOV/ALLOCATOR）は Safe 等のマルチシグで実行し、管理者コンソールは**準備・検証・可視化のみ**を担う。
- **FE 原則 4｜設定は成果物から生成** — コントラクトアドレス・ABI・定数は deploy 成果物／コントラクトソースから機械生成する。手書きの複製（ハードコードされたアドレス・ミラー定数）を残さない。複製が避けられない箇所は CI で原本と突合する。
- **FE 原則 5｜表現の規律** — 利回り・安全性を断定しない（市場連動・非保証を明記）。dToken 償還に即時保証があるかのような表現をしない（Buffer 不足時は遅延償還 = VAULT-FR-006）。Redemption 手数料は redeemer の負担として表示する。
- **FE 原則 6｜サーフェス分離** — ユーザーアプリ（公開）・管理者コンソール（限定公開）・運用ダッシュボード（読み取り）の 3 サーフェスを分離し、信頼境界・到達性・デプロイを混在させない。

---

## 3. 用語・外部依存・前提

| 用語 | 意味 |
| --- | --- |
| サーフェス | 独立して配信されるフロントエンド単位（ユーザーアプリ / 管理者コンソール / 運用ダッシュボード） |
| バインディング | フロントエンドが参照するチェーン ID・コントラクトアドレス・ABI の束 |
| 定数ミラー | コントラクト定数（MIN_DEBT 等）のフロントエンド側複製。原本は `Constants.sol` |
| 遅延償還キュー | Buffer 不足時の WithdrawRequest（VAULT-FR-006）の未請求一覧 |
| 読み取り専用モード | ウォレット未接続・任意アドレス注視（watch）での閲覧状態 |

**信頼する外部（フロントエンド固有）**: RPC プロバイダ（読み取りの可用性のみ信頼・複数系統）／ The Graph（subgraph インデックス・鮮度検証付き）／ ウォレット（EIP-1193 / EIP-6963 検出、WalletConnect、ハードウェアウォレット）／ Safe（特権 tx の実行基盤）／ 静的ホスティング・CDN・DNS（改ざん面として統制対象 = §9）。

**前提**: 配信物は静的ビルド（サーバ側に秘密を持たない）。対象chainとbranchは承認済みrelease Manifestからビルドごとに一意に固定する（SYS-CON-005）。署名規格は EIP-712 / EIP-2612（permit = DTKN-FR-007 / ZAP-FR-003,004 / VAULT-FR-003）。

---

## 4. アクター・ロール・信頼境界

| アクター | 主なサーフェス | 信頼 |
| --- | --- | --- |
| 借り手 / dToken 保有者 / Earner / Redeemer | (A) ユーザーアプリ | 敵対前提（自分のウォレットでのみ署名） |
| GOV_MULTISIG 署名者 | (B) 管理者コンソール → Safe | 信頼（ただしコンソールは鍵を持たず、最終承認は Safe 側） |
| ALLOCATOR | (B) 管理者コンソール | 限定信頼（許可された運用操作のみ。権限はオンチェーン側で強制） |
| GUARDIAN | (B) 管理者コンソール | 緊急停止に限定した信頼（直接実行。復旧は GOV / Timelock） |
| WRITEOFF | (B) 管理者コンソール | 高 quorum の限定信頼（不可逆な principal write-off） |
| Oracle / Strategy owner・upgrader | (B) 管理者コンソール → Safe | 対象コントラクトに限定した信頼（共有 Timelock 内外を操作単位で区別） |
| 運用担当・監視 | (C) 運用ダッシュボード | 読み取りのみ |
| 一般公開（未接続閲覧者） | (A)(C) | 読み取りのみ |
| RPC / subgraph / 統計 API | 全サーフェス | 半信頼（可用性のみ。値は鮮度・整合検証を経て表示） |
| ホスティング / CDN / DNS / 依存パッケージ | 全サーフェス | **改ざん面**（§9 SEC の統制対象） |

**信頼境界の要点**: 権限の強制はすべてオンチェーン（コントラクトの `onlyOwner` / role）で行われ、フロントエンドの到達制御（SEC-007）は**多層防御の追加層**にすぎない。フロントエンドを侵害しても、攻撃者が得られる最大値は「ユーザーに不正な tx を署名させる誘導」であり、これを §9（承認の明示・シミュレーション・アドレス検証）で縮小する。

---

## 5. 画面・ルート構成（terse・非規範）

実装ルートは変更され得るため本表は非規範。規範は §6 の FR。

| サーフェス | 画面（ルート例） | 主な対応 FR |
| --- | --- | --- |
| (A) ユーザーアプリ | ダッシュボード `/` | FRNT-FR-012,019,020 |
| (A) | 借入 `/borrow`・`/borrow/:coll`・ポジション `/loan` | FRNT-FR-013,014 |
| (A) | Vault withdrawal（dToken redeem・claim）`/vault` | FRNT-FR-015,016 |
| (A) | Earn `/earn/:pool` | FRNT-FR-017 |
| (A) | Redemption `/redeem`・shutdown redemption `/redeem/shutdown` | FRNT-FR-018 |
| (A) | 履歴 `/transactions`・アカウント `/account` | FRNT-FR-020 |
| (A) | 上流 Stake / Multiply surface の削除 | FRNT-FR-022,023 |
| (B) 管理者コンソール | 提案ビルダー / timelock キュー / allocate / pause | FRNT-FR-024..030 |
| (C) 運用ダッシュボード | ブランチ / オラクル / Vault・Strategy / Treasury / 公開統計 | FRNT-FR-031..036 |

---

## 6. 機能要件 FR

### 6.1 共通基盤

### FRNT-FR-001: チェーン・コントラクトバインディングの機械生成
- **Type**: Functional ｜ **Source**: FE 原則 4 / SYS-CON-005
- **対象**: 全サーフェス（ビルド・設定）
- **目的**: 参照するアドレス・チェーン構成を deploy 成果物から一意に導出し、手書き起因の誤接続を排除する。
- **要件**:
  1. コントラクトアドレス一式は deployment 成果物（manifest）から機械生成して環境設定に取り込む。手書きのアドレス定義をソースに置かない。
  2. 接続先チェーン ID を環境設定で宣言し、ウォレット・RPC の実チェーン ID と照合する（不一致時は FRNT-ERR-003）。接続済みウォレットの chain が対象 chain と異なる場合は、現在 chain と期待 chain を画面上で明示し、署名前に切替導線を提示する。
  3. 同一ビルド内に複数環境（mainnet / テスト環境）のバインディングを混在させない。環境はビルド時に一意に確定する。
- **異常時**: 必須バインディング欠落はビルド失敗（FRNT-FR-004）。
- **Verification**: build / ci-guard / e2e-local

### FRNT-FR-002: オンチェーン定数の単一ソース化
- **Type**: Functional ｜ **Source**: FE 原則 4 / `Constants.sol` / Parameters.md
- **対象**: 全サーフェス（定数層）
- **目的**: MIN_DEBT 等のコントラクト定数と MCR/CCR/SCR 等のブランチパラメータについて、フロントエンド側ミラーと各原本（`Constants.sol` / オンチェーン値 / [Parameters.md](../../../Parameters.md)）の乖離を構造的に防ぐ。
- **要件**:
  1. ブランチ別パラメータ（MCR 等）は原則**オンチェーンから読み取る**（ビルド時固定にしない）。
  2. やむを得ず保持する定数ミラー（入力検証用 MIN_DEBT 等）は、原本からの自動生成または CI 突合（FRNT-INV-002）の対象とする。
  3. 定数ミラーを参照する表示文言（最小借入額の警告等）は、ミラー値から動的に描画する（文言への数値直書きを禁止）。
- **異常時**: CI 突合の不一致はマージブロック。
- **設計上のポイント**: ローカル検証で実証された「コントラクト側 MIN_DEBT 変更にフロントの定数・文言が追随しない」事故クラスを CI で恒久排除する。
- **Verification**: ci-guard / unit

### FRNT-FR-003: ABI・型の機械生成
- **Type**: Functional ｜ **Source**: FE 原則 4
- **対象**: 全サーフェス（ビルド）
- **要件**: 参照 ABI はコントラクトのビルド成果物から生成し、手書き ABI を持たない。subgraph スキーマ由来の型はコード生成で取得し、生成物の鮮度（スキーマ変更への追随）を CI で検証する。
- **Verification**: build / ci-guard

### FRNT-FR-004: 環境設定スキーマの fail-fast 検証
- **Type**: Functional ｜ **Source**: FE 原則 4
- **対象**: 全サーフェス（ビルド・起動）
- **要件**:
  1. 全環境変数を必須／任意・型・形式（アドレス / URL / フラグ）付きのスキーマで宣言し、ビルド時に検証して欠落・不正はビルド失敗にする。
  2. 任意項目の未設定は機能単位の明示的な無効化（画面非表示・バナー非表示）として扱い、実行時例外や warning 風の未設定ラベルにしない。例: `NEXT_PUBLIC_POOL_LIQUIDITY_HEALTH_URL` 未設定時は JPYdf/USDC exit liquidity UI を表示しない。
  3. 秘密情報（書き込み可能な API キー等）をクライアント公開環境変数に置かない。
- **Verification**: build / unit

### FRNT-FR-005: ウォレット接続
- **Type**: Functional ｜ **Source**: FE 原則 3
- **対象**: (A)(B)
- **要件**:
  1. EIP-1193 / EIP-6963 によるインジェクト型ウォレット検出、WalletConnect、ハードウェアウォレットを少なくとも 1 系統ずつサポートする。
  2. 秘密鍵・ニーモニックの入力欄を一切提供しない。
  3. 任意アドレスの**読み取り専用注視（watch）**を提供する（サポート・監査・自己確認用。署名操作は不可）。
  4. 未接続でも読み取り系画面（ダッシュボード・統計）は全機能表示する。
  5. resettable devnet では、接続中 wallet へテスト ETH / USDC を補充する導線を TopBar の運用導線と言語切替の間に表示してよい。この導線は devnet の chainId / deployment flavor の両方で制限し、mainnet build では表示・実行しない。ETH は既存残高を減らさず不足時だけ既定額まで補い、USDC mint は receipt 成功を確認してから完了表示にする。
  6. write 操作画面の未接続状態では、無効な transaction CTA と文章内リンクを併置せず、ウォレット接続を単一の全幅 primary CTA として表示する。ラベルは接続後に操作を継続できることを明示する。
  7. 任意アドレスの注視画面では、表示アドレスと接続 wallet を比較する。未接続または不一致の場合は読み取り専用であることをアドレス付近に明示し、write 操作が表示アドレスではなく接続 wallet を使うことを誤認させない。
  8. 任意アドレスの注視結果にポジションがない場合は、そのアドレスの空状態を表示し、本人 wallet 向けの新規借入・運用等の write 導線で置き換えない。
  9. Account の担保請求権ガイダンスは正の請求権残高がある場合だけ表示する。任意アドレスの注視中は残高を読み取り専用で表示し、担保償還リンクの代わりに当該アドレスの owner wallet 接続が必要であることを示す。
- **Verification**: e2e-local / manual

### FRNT-FR-006: トランザクションライフサイクル
- **Type**: Functional ｜ **Source**: FE 原則 2,3
- **対象**: (A)(B)
- **目的**: 送信前に失敗を検出し、送信後の状態をユーザーが追跡できるようにする。
- **要件**:
  1. 署名要求の前に必ずシミュレーション（`eth_call` / ガス見積り）を行い、失敗が予見される tx は送信 UI を無効化して理由を表示する（FRNT-INV-003）。
  2. pending / 確定 / 失敗の状態遷移を明示し、確定までの間も画面遷移・再読み込みに耐える（送信済み tx の追跡を失わない）。
  3. 失敗時はカスタムエラーをデコードして人間可読の理由を表示する（FRNT-ERR-004）。
  4. 多段フロー（approve → 本体等）は進捗ステップとして可視化し、途中離脱から再開できる。
  5. tx hash 等の送信済み artifact を保存した step で receipt / post-confirmation 検証が失敗した場合、再試行は同じ artifact の検証だけを行い、新しい tx を送信しない。画面には送信済み tx へのリンクと verify-only の再試行であることを明示する。
  6. 新規借入・債務増額・金利変更等で送信時に変動し得る前払い手数料は、見積値に明示的な許容幅を加えた有限上限を request に固定し、確認画面と全 entrypoint の `maxUpfrontFee` 引数で同じ値を使う。見積取得前は送信不可とし、無制限値を手数料上限として渡さない。債務増額後の LTV・清算価格・TCR プレビューには見積手数料を含める。
  7. Safe transaction へのリンクは対象 chain から Safe の chain prefix を導出し、mainnet を Sepolia 等の別 network へ固定しない。未対応 custom chain では誤った Safe URL を生成しない。
  8. 署名待ち・確認待ちの主操作には処理中であることと現在状態を即時表示し、同一処理の実行中は再試行を抑止する。再読み込み後に実行中処理が存在しない場合は、未送信 step の署名再開または保存済み artifact の verify-only 再開を許可する。`awaiting-verify` に artifact が無い不整合状態では新しい tx を送信せず、保存状態の破棄と操作のやり直しを案内する。状態文言は assistive technology に通知し、`prefers-reduced-motion` 下でも文言・色・進捗による判別を維持する。
- **Verification**: e2e-local / component / unit

### FRNT-FR-007: 承認（approve / permit）の最小化と明示
- **Type**: Functional ｜ **Source**: DTKN-FR-007 / ZAP-FR-003,004 / VAULT-FR-003
- **対象**: (A)
- **要件**:
  1. permit 署名から本体 entrypoint までを end-to-end で実装・検証したフローだけ permit を選択肢として表示する。Day-1 の未実装フローでは permit を既定または推奨と表示せず、必要額 approve を使う。旧 localStorage の承認方式設定（`permit`・無制限承認を含む）は読み捨て、保存済み loan ID を維持する。
  2. 本アプリが新規に発行する approve は常に**当該操作の必要額**（close は必要額＋0.1% 実行バッファを上限とする）に限定し、無制限承認は提供しない。承認方式の選択 UI を置かない。
  3. 承認 UI には spender アドレス・金額・対象資産を常に表示する。
  4. dToken と Underlying の decimals 変換または切り上げを伴う承認では、変換後の raw amount を request に固定し、承認 UI・allowance 判定・approve 引数・本体 tx が同じ値を使う。
  5. 本アプリが新規に発行した必要額承認により、本体操作の完了後に既知 spender へ残り得る allowance は、丸め・実行バッファ分（close は債務の 0.1% を上限）に有界化する。wallet・explorer 等で別途設定された既存 allowance はこの保証の対象外とする。バッファを含む承認では承認ステップでその根拠を説明し、未使用 allowance が自動的に消えると説明しない。
- **Verification**: e2e-local / component

### FRNT-FR-008: データソースの役割分離と鮮度管理
- **Type**: Functional ｜ **Source**: FE 原則 2
- **対象**: 全サーフェス
- **要件**:
  1. データ種別ごとに正のソースを §7 のマトリクスどおりに固定する（残高・価格・パラメータ = RPC ／ 履歴・一覧 = subgraph ／ 市況補助 = 統計 API）。
  2. subgraph の同期ブロックとチェーン先端の乖離を計測し、しきい値超過で鮮度警告を表示する（FRNT-ERR-002）。
  3. User App の current health は DF-managed public stats publisher だけを参照し、上流ベンダーや Dune を runtime API にしない。APR 実績等の時系列が提供されない項目は非表示とする。public stats が stale / unavailable / refresh-error の場合、数値を補完せず状態表示と再確認導線へ縮退する。stale 判定は production 既定 300 秒、devnet / staging 既定 1,800 秒とし、環境別 override は本番証跡へ記録する。
  4. 上級者向けに RPC / subgraph エンドポイントのユーザー上書き機能を提供してよい（既定は公式設定）。
  5. resettable devnet の public stats は state profile と実チェーン状態を一致させる。`day1-review` は dwstETH / dUSDC だけを cap-open とし、Branch 2–7 は Underlying 未 binding、cap・supply・debt・SP deposit が 0 の inert state を必須とする。全 branch の debt / queue / redemption 分配を使う統合 fixture は `local-demo` / `hosted-demo` として分離し、通常の wallet / persona smoke は Anvil snapshot へ revert して review state を累積変更しない。
  6. public stats / subgraph の失敗を、RPC を正とする価格・ブランチ債務・SP 預入額・ActivePool 集計値の query enable 条件にしてはならない。補助 endpoint が unavailable でも、直接 RPC 読み取りが成功する指標は表示を継続し、期間実績など補助 endpoint にしかない値だけを unavailable へ縮退する。
  7. Ops の event log 取得失敗を現在値 RPC の失敗として扱わない。snapshot が成功している間は現在値と block を更新し、イベント履歴は最終成功値または空状態へ縮退して、その最終成功時刻とイベント由来アラートが停止中であることを明示する。
  8. Ops の定期 event log 取得は、初回同期後に確定済み cursor の次 block から snapshot head までを明示範囲で取得する。同一 head では再取得せず、head 後退または前回 head の block hash 不一致を検知した場合は cache を破棄して全履歴を再同期する。取得失敗時は cursor を進めない。
- **Verification**: e2e-local / unit / monitor

### FRNT-FR-009: JPY 建て表示・数値規約
- **Type**: Functional ｜ **Source**: SYS-FR-005（JPY 建て）/ FE 原則 5
- **対象**: 全サーフェス
- **要件**:
  1. 金額・価格は JPY 建てを既定とし、通貨記号・桁区切り・小数桁をロケール（ja-JP 基準）で統一する。USD 記号の流用を排除する。
  2. 18dec 値の演算は十進固定小数ライブラリで行い、浮動小数点で金額計算をしない。
  3. 表示丸めはユーザー不利益側に倒す（受取見込みは切り捨て・必要額/支払は切り上げ）。確定値はオンチェーン計算が正であることを注記する。
  4. 換算レート（Underlying ↔ dToken = DTKN-FR-003、担保 ↔ JPY）には出所と取得時点を表示できる。
  5. tx request の数量へ使う数値入力は、focus の有無にかかわらず parsed 値と同じ精度を表示する。blur 時に表示だけを丸めたり、`<0.01` 等の非数値 dust 表現へ置き換えたりしない。
  6. JPY 建ての通常表示は小数なしとする。清算価格と現在 LTV は安全性を過大表示しないよう表示桁で切り上げ、清算価格は整数 JPY、現在 LTV は小数第 2 位まで表示する。
  7. JPYdf 数量と JPY 建て評価額を区別し、JPYdf 数量へ換算なしで `¥` を付けない。JPYdf 価格を取得できない場合は 1 JPYdf = 1 JPY と仮定せず、JPY 評価額とそれを使う損益表示を unavailable へ縮退する。
  8. 価格 query の取得時刻をオラクル更新時刻として表示しない。担保価格を使う主要導線では、PriceFeedProxy のアクティブ source から JPY/USD soft-freeze 状態を直接読み、live / frozen / unavailable を区別する。新規借入画面では、入力判断時に確認できるよう担保価格の近傍へ価格読取時刻と source 状態を表示する。署名前の確認画面は資金の出入りの確認に集中させるため source 状態が live の間はこれを再表示せず、soft-freeze 中は非ブロッキングの注意を表示する。確認画面は source 状態の判定が完了するまで主操作を無効化し、unavailable なら理由を表示して fail-closed にする。新規借入 flow の各署名ステップは、ウォレット署名要求の直前に価格と source 状態を再読取し、読取不能または不正値なら fail-closed にする。
  9. compact 金額表記は選択中の UI ロケールに従い、英語では K / M / B、日本語では万 / 億 / 兆の桁体系を使う。日付の自然言語表記も同じロケールに従う。
  10. 金額・率・残高・リスク値・数値入力は tabular / lining figures を既定とし、更新や行間比較で桁幅が揺れないようにする。数値入力の letter spacing は 0 とし、金融数値の値更新に scale / count-up 等の装飾アニメーションを使用しない。
- **Verification**: unit / visual / component

### FRNT-FR-010: 国際化（i18n）
- **Type**: Functional ｜ Priority: Should ｜ **Source**: 市場特性（日本市場が一次）
- **対象**: (A)(C)
- **要件**:
  1. 表示文言を文言カタログに外部化し、日本語・英語の 2 ロケールを提供できる構造にする（提供順序は FRNT-TBD-008）。文言直書きの新規追加を lint で抑止する。
  2. branch / dToken / buffer / queued claim / Stability Pool / strategy / guardian / PIL / backstop reserve は、資金の帰属と通常請求に利用できる条件を含むユーザー向け定義を両ロケールで提供し、デスクトップ footer と mobile menu から到達可能にする。PIL は初回表示時に流動性 incentive 枠であることを展開し、Earn の claimable 報酬と誤認させない。
  3. ユーザー向けドキュメントリンクは選択中の UI ロケールに追従し、英語 UI から `documents/jp`、日本語 UI から `documents/en` へ遷移させない。外部または運用側から供給された非 JPYdf URL は書き換えない。
  4. user app の未保存時既定ロケールは英語とし、保存済みの明示的な選択がある場合はそれを優先する。ブラウザ言語だけでは初期ロケールを切り替えず、direct navigation と client navigation で同じ初期表示を保つ。
  5. wrong-network バナーの状態説明、切替中表示、切替ボタンを選択中の UI ロケールで表示し、接続先と期待ネットワークを chain ID 付きで明示する。
- **Verification**: build / component

### FRNT-FR-011: JPY DeFi / JPYdf ブランド表記
- **Type**: Functional ｜ **Source**: Development-Plan 横断バックログ（決定済み）/ Product-Overview §12
- **対象**: (A)(C)
- **要件**:
  1. サービス・プロトコル・アプリ・ドキュメント・管理 / 運用画面を指す表示名は **JPY DeFi** とする。ヘッダー、ページタイトル、frontend metadata、wallet 接続名、network label、agent discovery を含む。
  2. ステーブルコイン、token symbol、金額単位、Borrow / Repay / Redeem / Earn の対象、通貨ペアを指す表示名は **JPYdf** とする。
  3. 表示層の「BOLD」はトークン文脈では「JPYdf」へ置換する。owned frontend code の token/data model 名（例: request schema, local storage key, query key, flow ID, reward field）も JPYdf 名へ正規化し、不要な BOLD 互換名を残さない。
  4. 上流由来 package 名（例: `@liquity2/*`）、repository / package / environment variable、contract artifact / class、base protocol 参照などの技術識別子は表示名の置換対象に含めない。監査提出中の `contracts/` 配下と、その現行 runtime metadata も本変更の対象外とし、監査後に別途承認を得て変更する。
  5. 上流ブランド（Liquity ロゴ・外部リンク）を DF 公式（FRNT-SEC-005 のリンク台帳）へ差し替える。表記置換の完了判定は、対象 surface の全数 grep とレビューで確認する。
- **Verification**: visual / manual

### 6.2 (A) ユーザーアプリ

### FRNT-FR-012: release定義ブランチの動的サポート
- **Type**: Functional ｜ **Source**: SYS-CON-005 / release Manifest
- **対象**: (A) 全画面
- **目的**: 上流の 3 担保（ETH/wstETH/rETH）前提のハードコードを廃し、releaseで承認されたbranch set（inactive / placeholderを含む）を設定駆動で扱う。
- **要件**:
  1. ブランチ数・トークン識別子・アイコン・表示名はバインディング（FRNT-FR-001）とトークンレジストリから導出し、コード内の担保シンボル列挙（union 型・分岐）に依存しない。
  2. 担保ごとの差異（Underlying の decimals、ペグ種別、placeholder/inert 状態）を画面が解釈できる。
  3. inert（未活性）ブランチと cap 0 ブランチは、borrowable collateral 一覧から隠すか「準備中」として非操作表示する（ORCL-FR-008,009 の有効化と整合）。Day-1 は dwstETH / dUSDC だけを借入導線に出す。
  4. 同じ資産クラスの branch（例: ETH 系）が複数 active の場合、一方を推奨または初期選択せず、入出力資産、native staking 増価の帰属、実 Strategy 配分、venue / exit / loss risk、APR / MCR / liquidation price、branch-local SP coverage を並列表示する。
  5. WETH から wstETH への自動変換を前提にせず、保有資産、会計・税務方針、Strategy exposure の許容度で利用者が選べるようにする。
- **Verification**: e2e-local / component / unit

### FRNT-FR-013: 借入フロー（1 Tx 集約）
- **Type**: Functional ｜ **Source**: SYS-FR-001 / ZAP-FR-001..004 / VAULT-FR-001 / DTKN-FR-004
- **対象**: (A) 借入画面
- **実装同期メモ（2026-06-18 / 2026-06-23 / 2026-06-25 / 2026-06-29 / 2026-07-31）**: upstream 系 `LeverageLSTZapper` / `LeverageWETHZapper` route は production `contracts/src` から削除済みであり、FRNT-FR-013 の production PASS には数えない。production PASS 条件は `DeployLiquity2` が cap>0 の borrowable dToken branch（Day-1 は dwstETH / dUSDC）に `CollateralYieldZapper` を配線し、manifest / generated bindings / user app が同 Zapper を使って `Underlying -> dToken -> Trove` を 1 Tx で実行することである。WETH branch は存在しない。native ETH は、deploy パラメータで有効化した dwstETH branch の native-ETH on-ramp（ETH→Lido stETH→wstETH、[Zapper](./Zapper.md) ZAP-FR-015）でのみ受け入れ、user app は ETH 入力モードを提供して open と同一 Tx 内で wstETH へ変換し既存の dToken 経路へ合流させる。Zapper は native ETH を担保そのものとしては受け取らず、on-ramp 以外の `msg.value` は gas compensation 専用のままとする。inert branch（2–7）は borrowable branch として扱わない。`/borrow` は release 定義の先頭の公開担保を選択した Open Borrow 画面を直接描画し、フォーム内の担保 selector で他の公開担保へ切り替える。`/borrow/:collateral` は担保別の canonical deep link として維持する。未知 slug・複数値 param は先頭 branch へ補完せず 404 にする。
- **要件**:
  1. ユーザー入力は **Underlying 建て**を基本とし、内部の dToken ラップ（deposit → openTrove）は Zapper 経由の 1 Tx に集約する（ARCH-005 により直接経路も妨げない）。
  2. Borrow の入口・フォーム内の担保選択・Open Borrow 画面の主表示（ラベル / アイコン / canonical URL slug）は dToken branch でも Underlying を使う（例: 内部 `dwstETH` branch を `/borrow/wsteth`・`wstETH` 表示にする）。ページ見出しは選択中の担保だけでなく公開されている選択肢を列挙し、現在の wstETH / USDC 構成では `Borrow JPYdf with wstETH or USDC` と表示する。一方で `symbol` / branch key / contract lookup / oracle lookup / subgraph lookup は dToken symbol を維持し、Vault / Admin / Ops / 直接 dToken 管理画面では dToken 表示を維持する。
  3. Borrow 画面の「利用可能担保」は dToken branch でも `Underlying wallet balance` を Underlying 建てで表示する。dwstETH branch で native-ETH on-ramp（ZAP-FR-015）が有効な場合は、Underlying 入力とは別の ETH 入力モードを提供し、route が利用不可（staking pause / stake limit 等）の間は ETH モードを塞ぐ。送信時に不足分の Underlying を Zapper が dToken にラップする。既存 dToken balance の直接投入は Day-1 の Borrow open UI 経路に含めない。
  4. Borrow 画面の担保価格表示は raw Underlying spot ではなく、dToken backing ratio を反映した **有効担保価値**として表示する。backing ratio が 100% 未満の場合は、借入可能だが Core 上の dToken claim が残存 backing に対する請求権であることを警告する。
  5. 入力検証は MIN_DEBT（FRNT-FR-002 のミラー）・MCR/CCR・残高・承認状態・dToken cap を送信前に検査し、違反は理由つきで送信不可にする。`mintCap = 0` branch は、route 直打ちでも open request を生成しない。
  6. 金利はユーザー設定（手動・委任）を提供し、設定値に応じた effective APR、policy anchor、Redemption リスク指標（debt in front / branch debt に対する ahead ratio / rate distribution）を表示する。初期 policy anchor は public stats `borrowRatePolicies` と launch evidence の business input を出所として表示し、保証利回り・固定費用のように表現しない。
  7. 預け入れた担保がコア上は dToken であることを明細（折りたたみ可）で開示する（FE 原則 5 の透明性）。
  8. Referral は URL query（`ref` / `referral` / `referralCode`）から slug を capture し、JPYdf namespace の localStorage に保存できる。ただし frontend は任意 slug を bytes32 化しない。`NEXT_PUBLIC_REFERRAL_REGISTRY_URL` が未設定、取得失敗、または registry が active entry を返さない場合は `openTroveWithRawETHAndReferral` へ referral code を渡さず、通常の no-referral entrypoint を維持する。registry 導入後も active registry entry が返す canonical bytes32 だけを tx preview に表示し、unknown / expired / paused / not-started / cleared state は referral なしとして扱う。
  9. Day-1 の公開対象 dwstETH / dUSDC branch では、外部 Strategy 運用益が**プロトコル（Day-1 は Protocol retention Safe、Day-2 は Treasury）に帰属し**、借り手の Trove に記録された担保数量を増加させないこと、および Strategy 損失時は担保評価が下がりうること（ORCL-FR-014 の backing 反映）を、担保入力の判断文脈で明示する。dwstETH では Day-1 は Aave Strategy を whitelist 登録するが `allocateMaxMove = 0` のため外部運用への配分は行わず（[Parameters](../../../Parameters.md) §2-B）、wstETH の native staking 増価が borrower の担保価値に残ることと、将来配分を開始する場合の実配分・収益帰属・損失リスクを分けて表示する。
  10. Borrow amount は `MIN_DEBT` から導出した最小額の入力 shortcut を提供する。担保額と有効担保価格が確認でき、最低 Borrow amount である `MIN_DEBT` と取得済みの発行手数料を含む予定債務を最大 LTV 以下で成立させられる場合は、Liquidation / LTV 表示を pointer・touch・keyboard で操作できる range control とし、操作位置から Borrow amount を逆算する。range control の操作下限は Borrow amount が `MIN_DEBT` に一致する位置（発行手数料込みの予定債務では `MIN_DEBT + 取得済み発行手数料`）とし、同予定債務を最大 LTV 以下で成立させられない場合は range control を操作不可とする。それ未満の track 領域は無効領域として視覚的に区別して（境界の目印と最小ラベルを含む）drag では選択できない。直接入力が `MIN_DEBT` 未満の場合、range control は無効領域内の実位置を表示し、送信可否は項 5 に従う。Borrow amount の直接入力と range control は双方向に同期し、range から設定する予定債務には取得済みの発行手数料を含める。
- **異常時**: ブランチ shutdown / oracle 障害時は新規借入を画面でブロック（FRNT-ERR-005）。
- **Verification**: e2e-local / component

### FRNT-FR-014: ポジション管理（調整・返済・クローズ・金利変更）
- **Type**: Functional ｜ **Source**: ZAP-FR-005..010 / 🔵 Core（Liquity-v2-Core-Spec）
- **対象**: (A) ポジション画面
- **実装同期メモ（2026-06-19 / 2026-06-29）**: dToken branch で upstream 系 `LeverageLSTZapper` を汎用操作 router として使う経路は production `contracts/src` から削除済みである。production PASS 条件は、減担保・JPYdf 保有時のクローズが `CollateralYieldZapper` 系の `withdrawCollToUnderlying` / `closeTroveToUnderlying` 経路、または明示的な dToken 受取 + Vault redeem の連続フローとして検証されることである。担保増加は ERC-20 Underlying（wstETH / USDC）の approve / adjust で実行する（WETH branch は存在せず、native-ETH on-ramp は open 経路の ZAP-FR-015 に限る）。`repayWithCollateral` / flash-close / collateral-funded repay / Multiply は fresh deploy 前提で Day-1 contract ABI から削除済みであり、user app から送信してはならない。`UniV4Exchange` は Day-1 audit scope に含めるが、これらの user-facing flow を将来提供する場合も Balancer や削除済み Flash Loan callback に依存せず、ZAP-TBD-010 と [`Liquidity-Route-Policy.md`](../policies/Liquidity-Route-Policy.md) の JPYdf/USDC Uniswap v4 final leg、および exact Underlying に必要な audited asset-specific pre-leg を持つ新しい entrypoint として追加する。
- **要件**:
  1. 担保増減・借入増減・同時調整・クローズ（JPYdf 保有時）を提供する。JPYdf 未保有時の Flash Loan クローズ / collateral-funded repay / Multiply は Day-1 UX では提供しない。
  2. 減担保・クローズの受取は Underlying 建て（ZAP-FR-006,010）を既定にする。Vault Buffer 不足時は `WithdrawRequest` として遅延化されるため、即時受領を保証する文言を表示しない。
  3. 金利調整・委任・batch 参加状態を表示し、zombie 状態（MIN_DEBT 未満）の制約文言は FRNT-FR-002 のミラー値から描画する。
  4. 調整後の ICR・清算価格・Redemption リスクのプレビューを送信前に表示する。
  5. クローズ画面の返済額・担保額・残高判定は、送信処理と同じ `getLatestTroveData` の RPC 値を使う。継続利息による実行時不足を避けるため JPYdf 必要残高には 0.1% の実行余裕を含め、実債務との差分は移転されず wallet に残ること、Day-1 は collateral-funded close を提供しないことを明示する。最新債務または wallet 残高を確認できない場合は送信不可にする。
  6. batch manager / delegate 一覧は loading、登録 0 件、取得失敗を区別する。登録 0 件では空状態と登録元の説明、取得失敗では再取得を表示し、`Custom delegate` モードでは有効な manager を選択できるまで request を生成しない。`Manual` モードの通常開設・個別金利変更は delegate 未選択を理由にブロックしない。
- **Verification**: e2e-local / component

### FRNT-FR-015: dToken Vault withdrawal（redeem / claim）
- **Type**: Functional ｜ **Source**: SYS-FR-002 / VAULT-FR-001,002,003 / DTKN-FR-003
- **対象**: (A) Vault withdrawal 画面
- **目的**: Trove と独立して保有する dToken を Underlying へ戻し、Buffer 不足時の delayed WithdrawRequest を追跡・claim できる操作面を提供する。
- **実装同期メモ（2026-06-23）**: Day-1 user app は standalone の `CollateralVault.deposit` mint UI を提供しない。Underlying から Core collateral への入口は Borrow/Zapper flow（FRNT-FR-013）へ集約し、`/vault` は dToken → Underlying の redeem / queued claim に絞る。直接 deposit は ARCH-005 により contract path として妨げないが、user app の主導線ではない。
- **要件**:
  1. dToken → Underlying の標準経路として plain `redeem` を提供し、即時支払分と delayed WithdrawRequest に分かれ得ることを表示する。`redeemWithPermit` は FRNT-FR-007 に従う end-to-end 実装・検証を追加するまで公開経路に採用しない。
  2. redeem 時は Buffer 充足状況に応じて「即時受取」か「遅延償還キュー入り」かの**見込み**を事前表示する。即時を保証する表現を用いない（FE 原則 5）。
  3. Buffer 残高・Backing 比・per-branch withdrawDelay（[Parameters.md](../../../Parameters.md)）と、未請求キューの状態を表示する。
  4. `/redeem` の標準 JPYdf 償還で collateral claim token が返る可能性がある branch は、Borrow / Earn の公開導線に出していない branch であっても、`CollateralVault` binding が存在する限り `/vault` の出口導線で redeem / queued claim を扱えるようにする。
  5. Strategy 資産額は `getStrategyStatuses().conservativeValue` の合計（live `min(estimate, principal)` または fresh fallback cache）を表示し、`estimatedUnderlying` をそのまま請求原資として表示しない。`estimateAvailable` または `principalAvailable` が false の Strategy がある場合は、表示額が利用可能な保守評価だけを含むことを警告する。
  6. 狭い画面でも redeem 見込みの即時受取額とキュー入り額を省略せず表示する。同じキュー説明をバナー・入力補助・本文へ重複表示せず、待機条件と再送不要の説明は入力直下の info tooltip から確認できるようにする。
- **Verification**: e2e-local / component

### FRNT-FR-016: 遅延償還キューと claim
- **Type**: Functional ｜ **Source**: VAULT-FR-006 / SYS-NFR-004
- **対象**: (A) Vault withdrawal 画面
- **要件**:
  1. 自分の WithdrawRequest 一覧（金額・成立時刻・claim 可能予定・状態）を表示する。イベントからの索引は呼出元 `user` ではなく、オンチェーンの request owner と一致する `WithdrawRequested.receiver` を使い、Zapper 等の代行コントラクト経由で作られた request も最終受領者が追跡できるようにする。
  2. claim 可能になったリクエストの claim 操作を提供し、原資不足等で claim が失敗し得ることを状態として表現する（無期限化があり得る前提の文言設計）。
  3. キュー全体の規模（未請求総額）を表示し、ユーザーが遅延の程度を見積もれるようにする。現在の buffer に収まる request 件数は各 request を個別評価したスナップショットであり、全件の同時請求を保証する表現にしない。
  4. buffer 待ち状態では、request がオンチェーンに残り、再送不要であることを明示する。`withdrawDelay > 0` はキュー発生時から `claimableAt` までのオンチェーン上のハードロックであり、strategy 資金または buffer が早期回復しても短縮されない。`withdrawDelay == 0` の同期回収構成では時間ロックなしと表示し、buffer 補充後すぐ請求可能であることを示す。いずれも buffer 回復時刻は保証せず、通常の着金予測として表示しない。
  5. buffer shortfall と backing shortfall を混同しない。`backingRatio() == 1e18` の一時流動性不足と、`backingRatio() < 1e18` の incident は別の文言・警告として表示する。
- **Verification**: e2e-local / component

### FRNT-FR-017: Earn（Stability Pool）
- **Type**: Functional ｜ **Source**: SYS-FR-004 / VAULT-FR-002/006 / FRNT-FR-021 / 🔵 Core SP
- **対象**: (A) Earn 画面
- **実装同期メモ（2026-06-25）**: `/earn` は pool 選択一覧であり、pool 画面は `/earn/:pool` または `/earn/:pool/:action` の public slug / action が一致した場合だけ描画する。pool slug 欠損・未知 slug・未知 action・複数値 param は先頭 pool / deposit tab へ補完せず 404 にする。
- **要件**:
  1. ブランチ別 SP への預入・引出・報酬（JPYdf 利回り＋清算担保）の claim / compound を提供する。
  2. 預入は保有 JPYdf 残高のみを上限とし、借入ポジションとの連動を示唆しない。
  3. APR 表示は出所（実績期間）を明示し、将来利回りの保証表現を用いない。SP 追加報酬（Treasury 由来）は確定まで表示しない（FRNT-TBD-003）。
  4. 借入金利 25% の PIL 原資（`InterestRouterForwarder` 残高 / routed amount）は Earn ユーザーの claimable 報酬として表示しない。Day-1 の Earn で表示できるのは Core SP 会計に入った 75% 分の JPYdf 利回りと清算担保に限る。
  5. SP coverage、outside debt、branch debt、covered / thin-SP state を branch ごとに表示し、SP がどの債務範囲を吸収し得るかを判断できるようにする。
  6. dToken branch では backing ratio、Vault buffer、withdraw delay、strategy exposure、JPYdf/USDC exit liquidity、redemption fee / base rate を同じ判断文脈で確認できるようにする。
  7. SP を dToken / Strategy 毀損の repair 原資として表現しない。毀損は backing ratio と担保価値に反映され、repair は strategy recovery / writeoff / backstop の領域である。
  8. 現在の金利由来 APR は ActivePool の集計債務・加重債務と SP 預入額から RPC で導出できる。7日実績など履歴集計が必要な APR は public stats の鮮度に従い、取得不能時に現在 APR で補完して同じ期間ラベルを付けない。
  9. dToken branch の清算担保報酬は原資産そのものではなく担保請求権として受け取り、原資産化には Vault の即時受取枠と遅延償還キュー条件が適用されることを、pool の報酬表示と同じ判断文脈で明示する。`withdrawDelay` は live contract 値を表示し、清算益の即時受領や確定利益を示唆しない。「同じ判断文脈」には claim / compound の操作パネルと報酬 tooltip を含む。即時バッファは先着消化であること、キュー待機中に担保の市場価値が変動しうることを、確定利益を示唆しない表現で伝える。
  10. 報酬 claim は、記録預金（`deposits[account].initialValue`。表示用の compounded deposit ではなく、`withdrawFromSP` / `claimAllCollGains` が caller 検証に使う値）が正の場合は `withdrawFromSP(0, true)`、ゼロかつ stashed collateral gain が正の場合は `claimAllCollGains()` を選択する。後者で `withdrawFromSP(0, true)` を生成せず、ネットワーク手数料見積り・tx preview・送信 calldata は同じ selector を使う。記録預金・gain の取得失敗時はどちらの request も生成しない。
- **Verification**: e2e-local / component

### FRNT-FR-018: Redemption
- **Type**: Functional ｜ **Source**: SYS-FR-004 / 🔵 Core Redemption / ORCL-FR-005
- **対象**: (A) Redemption 画面
- **実装同期メモ（2026-06-23 / 2026-06-25）**: 通常 redemption は `/redeem`、branch shutdown 時の urgent/shutdown redemption は `/redeem/shutdown` で提供する。旧互換 route は持たず、agent discovery / sitemap / public docs も canonical route のみを公開する。
- **要件**:
  1. 「1 JPYdf = ¥1 相当の担保」への償還を、見込み受取額・現在の redemption fee・対象ブランチ配分とともに提供する。
  2. 手数料は **redeemer の負担**として表示する（借り手のコストとして表現しない）。手数料は追加の JPYdf 支払いではなく、各 branch から受け取る担保の控除として実現することを明示する。複数担保へ配分される通常 redemption の集計表示では、現在の手数料率と額面ベースの JPY 相当額を示し、JPYdf トークンの支払いと誤認させるアイコン・単位を付けない。見積相当額はユーザー不利益側へ丸める。
  3. 借り手向けには（Redemption を受ける側の）影響説明を金利設定 UI 側に置く（FRNT-FR-013 の要件 3）。
  4. dToken branch の見込み受取・配分表示はユーザー向けには collateral claim（例: `wstETH claim`）として表現し、Underlying への変換は `/vault` の Vault withdrawal 導線として示す。
  5. 標準 redemption はオンチェーンの `CollateralRegistry` / `RedemptionHelper` が持つ active branch 配列に従う。Borrow / Earn に表示しない registry-only branch でも償還配分が非ゼロになり得るため、ユーザー向け表示では非ゼロ返却時だけ明示し、公開導線外 branch であることを説明する。tx 引数（`minCollRedeemed` 等）は registry branch 数と整合させ、表示上の非表示で calldata の branch 配列を短縮しない。
  6. 標準 redemption のスリッページ許容度はユーザーが 0.1% から 5% の範囲で設定でき、同じ値を推定 fee に加えた `maxFeePct` と各 branch の見込み受取に適用した `minCollRedeemed` の両方へ使う。入力画面と確認画面の双方に最大 fee と非ゼロ branch 別最小受取額を表示し、オンチェーンクォートが更新中または取得失敗の場合は保存値・ゼロ値へフォールバックせず送信不可にする。クォート取得後の受取配分は非ゼロ branch のみ表示するが、calldata の `minCollRedeemed` は registry branch 数を維持する。
  7. 狭い画面では既定のスリッページ許容度と最大 fee を常時要約表示し、調整用スライダーを disclosure control 内に収める。保護値を非表示にしたり、送信値と異なる要約値を表示したりしない。dToken branch の受取案内は内部用語の「フォローアップ」ではなく、受け取る underlying と次の操作を明示する。
- **Verification**: e2e-local / component

### FRNT-FR-019: ブランチ健全性と backing 比の表示
- **Type**: Functional ｜ **Source**: ORCL-FR-014 / VAULT-FR-016,018 / SYS-INV-002
- **対象**: (A) ダッシュボード・各ブランチ画面
- **要件**:
  1. ブランチごとの TCR・総債務・SP 残高・Shield（redemption 遮蔽）状態・shutdown 状態を表示する。
  2. dToken の backing 比（裏付け率）を表示し、1 未満（元本毀損反映中）のブランチには操作画面で警告を出す。値の定義は VAULT-FR-016 / ORCL-FR-014 を正とし本書で再定義しない。
  3. 警告は事実（比率・出所・参照ブロック）を示し、回復可否の予測を述べない。
  4. dToken の預入上限は現在の claim token supply の担保価値と預入可能額を対比し、「担保価値 / アプリ上限」または「担保価値 / オンチェーン上限」と表示する。現在の JPYdf ブランチ債務は「JPYdf 借入残高」として表示し、同内容の説明文を直下に重複表示しない。担保価値と借入残高は過剰担保のため一致せず、その関係を TCR の説明で明示する。内部の Day-1 債務計画との比較はユーザー画面に出さず、dToken 預入上限を JPYdf のオンチェーン債務上限として表現しない。
  5. Vault の即時引出可能バッファと待機中の請求は、単位を付けた別項目として表示する。withdrawDelay が24時間の整数倍である場合は、72時間のような累積時間ではなく3日のように日数で表示する。
  6. Shield 状態は SP coverage と通常 redemption の配分状態として説明する。ユーザー向けバナーでは「未カバー債務」だけで説明せず、SP 預入額がブランチ借入残高を上回るため他の担保ブランチが先に償還対象になる、と平易に示す。`MIN_ANNUAL_INTEREST_RATE`（0.5%）は全 Trove に常時適用される共通下限であり、SP coverage により利用可能になる金利として表現しない。
  7. Home の Borrow / Earn 比較では、dToken 預入上限と SP coverage を同じ progress 表現で比較可能にする。預入上限は現在値・上限・預入可能額、SP coverage は SP 預入額・ブランチ借入残高・SP 未カバー債務を示し、同じ値を別列へ重複表示しない。progress はスクリーンリーダー向けの現在値を持つ。狭幅では branch ごとの Borrow / Earn 操作を独立した全幅 CTA とし、横スクロールなしで表示する。
- **Verification**: e2e-local / component / visual

### FRNT-FR-020: ポジション・履歴の一覧性
- **Type**: Functional ｜ **Source**: SYS-NFR-005
- **対象**: (A) ダッシュボード・履歴画面
- **要件**:
  1. 接続（または watch）アドレスの Trove・SP 預入・dToken 残高・遅延償還キューを横断一覧する。
  2. 操作履歴（借入・調整・清算・redemption 被弾・claim）を subgraph から時系列表示し、鮮度警告（FRNT-FR-008）に従う。
  3. 個別 Trove は譲渡可能 NFT である前提で、所有権移転後の表示整合を保つ。
  4. dToken branch の残高・余剰担保・履歴表示は collateral claim として表現し、Underlying への変換が別の Vault withdrawal 操作であることを示す。
  5. 個別 Trove の redemption 被弾日時は redemption により更新される subgraph `updatedAt` を用い、借り手自身の最終操作日時 `lastUserActionAt` で代用しない。
  6. 残高・ローン・SP 預入・担保請求権・遅延償還キューを横断する account 画面を主ナビゲーションから到達可能にする。`/transactions` は進行中または保存済み tx flow の確認・復帰を優先し、flow が無い場合の account activity 表示は補助導線として扱う。
  7. account のローン・Stability Pool 空状態には、対応する新規操作へ移動できる CTA を表示する。データ取得失敗は空状態とせず、再取得と support ID を維持する。
  8. 新規借入画面は、担保・借入入力とユーザー自身の担保評価額・予定債務・LTV・清算価格を、ブランチ全体の運用指標より前に表示する。予定債務とリスク指標は発行手数料を取得するまで確定値として表示しない。
  9. subgraph が未設定または利用不可の環境では、設定済み全 branch の TroveNFT `Transfer`（to=watch address）ログから候補 Trove ID を発見し、現在の `ownerOf`・Trove status・latest Trove data を RPC で再検証して開設中ローンを表示する。ブラウザ保存済み Trove ID は補助ヒントに留め、任意アドレス表示や別ブラウザでの完全性を依存させない。ログ探索または再検証に失敗した場合は0件として扱わず、再取得と support ID を表示する。
  10. account のローンカードから開いた詳細画面の戻り先は、最新ローンデータの現在 owner を指定した account 画面とする。カード全体をリンクにする場合、その内部に button / link 等の別の操作要素を入れない。
  11. 開設中ローンの詳細を未接続または owner 以外のウォレットで表示する場合は閲覧専用であることと owner を明示し、担保・債務・金利・クローズの write action を owner 一致まで無効にする。
  12. 開設中ローンの詳細は、オンチェーン JPY/USD ソースが frozen・stale・無効、または鮮度／凍結状態を取得できない場合にその状態を明示する。正常時および初回読込中は追加バナーを表示しない。
  13. redemption 順位の補助データを取得できない場合は「取得不可」、取得中は「確認中」と表示し、「対象外」や低リスクとして扱わない。この区別を Account、ローン詳細、借入、金利変更、delegate 選択、transaction preview で統一する。
  14. Home と Account はページを表す `h1` を1つだけ持ち、ポジション一覧・比較表等の主要領域を `h2`、その配下のポジション・操作カードを `h3` とする。見た目のサイズだけを理由に見出しレベルを飛ばさない。
  15. Stability Pool 詳細は表示中のプール名をページ `h1` とし、Pool 一覧では各プール名を一覧ページ `h1` 配下の `h2` とする。transaction preview 内で同じ summary を再利用する場合は、独立したページ見出しとして扱わない。
  16. モーダルは名前付き modal dialog として支援技術へ公開し、題名を `h1`、ダイアログ内の主要な節を `h2`、その配下の表グループ等を `h3` とする。読み取り専用の環境値フィールドも、表示中のキー名をアクセシブル名として持つ。閉じて再表示した際はスクロールを先頭へ戻し、題名と閉じる操作を直ちに確認できる状態にする。
  17. 狭幅のメインナビゲーションは名前付き modal dialog として開き、明示的な閉じる操作へ初期フォーカスを置く。背景はフォーカス対象にせず、Escape または閉じる操作の後は起動ボタンへフォーカスを戻す。現在のページはリンクの `aria-current="page"` で示す。
  18. 履歴クエリは NFT burn 後に borrower がゼロアドレスへ変わる owner close・清算を `previousOwner` から取得する。subgraph の `status=redeemed` は直近操作が redemption であることだけを表すため、Trove の終了または全額償還を示す状態として扱わず、redemption 被弾履歴だけを表示する。
  19. 履歴行の日時に対応する金額は、その時点のイベント値または履歴スナップショットをデータソースが保持する場合だけ表示する。最新 Trove entity の債務・担保を過去の開設・調整時点の値として表示せず、当時値を復元できない場合は取得不可であることを明示する。
  20. 現在ポジションの lifecycle（開設中・クローズ済み・清算済み）は RPC の Trove status を正本とする。subgraph の `status=redeemed` は現在状態へ上書きせず、`redemptionCount` 等の履歴情報から償還被弾を補足表示する。部分償還後もオンチェーンで active または zombie の Trove は開設中ローンの件数・一覧・操作導線に含める。
  21. account の残高・ローン・Stability Pool・清算余剰について、最後に成功した query cache を保持した状態で再取得に失敗した場合は、保持値を消さず「前回取得値」として警告、再取得、support ID を表示する。キャッシュ済みの空配列を正常な空状態へ縮退させず、新規借入・預入 CTA を表示しない。清算余剰を取得できない場合は余剰0または請求済みと判定せず、清算済みローンを表示したまま請求状態を未確定にする。
  22. Loan 詳細では、query cache に値が残っていても、担保価格・oracle 鮮度・branch shutdown・branch debt/TCR・upfront fee・最新 Trove data・操作に必要な wallet 残高の再取得失敗を成功として扱わない。保持値は参考表示に限定し、再取得と support ID を表示する。必要な read がすべて成功するまで担保/債務変更・金利変更・クローズの write request を生成しない。クローズの calldata に不要な参考価格だけの障害はクローズを妨げない。
- **Verification**: e2e-local / component

### FRNT-FR-021: リスク・免責表示
- **Type**: Functional ｜ **Source**: FE 原則 5 / SYS-NFR-002
- **対象**: (A) 全操作画面
- **要件**:
  1. 清算リスク（清算価格・ICR）・Redemption リスク・遅延償還の可能性・スマートコントラクトリスクを、該当操作の文脈内で表示する。
  2. 利回り・「リスクフリー」等の断定表現を禁止し、前提条件（市場連動・非保証）を本文に明記する。
  3. 法域別の利用制限が必要になった場合に備え、ジオブロック・ブロックリストを設定で有効化できる枠を維持する（既定は無効。発動判断は本書の非責務）。
  4. ユーザー向け文言に requirement ID や Core 内部語彙（Trove / ICR / zombie）を露出しない。Loan / 担保比率 / 最低債務未満等の判断可能な表現へ置き換え、比率には計算意味を同じ画面で説明する。
- **Verification**: visual / manual / component

### FRNT-FR-022: 上流ガバナンス UI（Stake）の削除
- **Type**: Functional ｜ **Source**: FE 原則 1 / Product-Overview §4.1（DFT）
- **対象**: (A)
- **要件**: 上流の LQTY staking / V1 連携 / 上流ガバナンス画面・バナー類は JPYdf user app surface から削除する。DFT のステーキング・ガバナンス UI は設計確定後に別要件として追加する（FRNT-TBD-001）。再導入する場合は JPYdf-owned governance source、contract address policy、user-facing copy、admin/runbook を別 spec で定義する。
- **Verification**: visual / build

### FRNT-FR-023: Multiply（レバレッジ）の削除
- **Type**: Functional ｜ **Source**: FE 原則 1 / ZAP-TBD-004（dToken leverage 未設計）
- **対象**: (A)
- **要件**: Day-1 user app は Multiply / レバレッジ UI、`/multiply` route、open/update leverage tx-flow、loan mode localStorage 互換、price-impact / slippage refund footer を持たない。dToken branch は ZAP-TBD-004（dToken leverage 設計）と ZAP-TBD-010（JPYdf/USDC only swap route 本番有効化）が解決し、専用 router と audited entrypoint が追加されるまで Multiply open / update を送信不可にする。将来提供する場合は設定フラグによる旧 route 復活ではなく、新しい spec / route config / fork evidence / UI copy として追加する。
- **Verification**: build / visual

### FRNT-FR-038: 公開ユーザー操作カバレッジと実行経路
- **Type**: Functional ｜ **Source**: ARCH-005 / production permissionless surface / FRNT-FR-006,007
- **対象**: (A) 全 write 操作・内部 read helper
- **要件**:
  1. production ABI と source caller check から、特権 caller を必要としない state-changing entrypoint を全件列挙し、[公開ユーザー向けフロントエンド操作要件](./Permissionless-User-Operations.md) で公開アプリ上の扱いへ対応づける。各行は対象 component と function name（overload がある場合は識別可能な signature）を安定キーとし、関連する本書の `FRNT-*` を参照する。
  2. 公開アプリが提供する操作は、ユーザー目的、到達導線、採用 entrypoint、条件付き表示、spender、asset、receiver が同マトリクスと一致する。direct Core と同じ目的を Underlying 建て Zapper または保護値付き Helper で提供する場合、重複した direct 操作 UI を設けない。
  3. non-view helper を見積り・切詰め・価格取得のためだけに使う場合は `eth_call` とし、ユーザー署名・送信 request を生成しない。
  4. standard token / NFT 管理、third-party manager、batch manager 自身の運用、keeper / bot、Strategy maintenance、incentive 配布、要件未整備の optional utility は、同マトリクスで明示した範囲では公開ユーザーアプリに standalone UI を設けない。UI 非提供をオンチェーンのアクセス制御として扱わない。
  5. permissionless entrypoint の追加・削除・caller 制限・公開標準経路を変更する場合は、同じ変更でマトリクス、関連 `FRNT-*`、tx-flow test、必要な E2E fixture を更新する。
- **Verification**: ci-guard / unit / component / e2e-local

### 6.3 (B) 管理者コンソール

mainnet 稼働後の画面操作、Safe JSON import、署名前照合、Timelock
Schedule / Execute / Cancel の運用手順は
[`Admin-Console-Operator-Manual`](../../operations/runbooks/Admin-Console-Operator-Manual.md)
を正とする。リリース前 gate は
[`Admin-Console-Production-Gate`](../../../contributors/deltaforesight/delivery-plans/Admin-Console-Production-Gate.md)
で分離して管理する。

### FRNT-FR-024: 特権操作の「準備と可視化」モデル
- **Type**: Functional ｜ **Source**: FE 原則 3 / SYS-FR-007
- **対象**: (B) 全機能
- **目的**: GOV_MULTISIG / GUARDIAN / ALLOCATOR / WRITEOFF / owner・upgrader の運用を、鍵を持たないコンソールで安全に準備・検証する。
- **要件**:
  1. コンソールは calldata の組み立て・シミュレーション・差分表示までを行い、実行は Safe（または役割保有者のウォレット）に委ねる。
  2. 操作対象の現在値とオンチェーン権限（Owner / role 保有者）を表示し、権限のないアドレスで実行不能な操作は準備段階で警告する。
  3. placeholder / inert branch でも、admin contracts（dToken / CollateralVault / PriceFeedProxy）がデプロイ済みなら Activation と Oracle 操作は利用できる。Vault state / ALLOCATOR など underlying 前提の表示と操作カタログカテゴリは未活性 branch では提供しない。active だが運用先なしの branch（manifest の `dfYield[i].strategies` が空）は Vault state を表示し、Strategy 一覧は空として扱う。
  4. renounce 系・権限放棄系の操作は UI に置かない（DTKN-FR-009 / ORCL-FR-007 の無効化方針と整合）。
  5. 選択中の branch / 画面（概況・操作・保留・証跡・構成）/ 操作カタログの選択エントリを URL query に保持し、レビュー・引継ぎ時に同じコンテキストを再表示できるようにする。不正な query は既定値へ正規化し、旧画面 ID は対応する新画面へ解決する。保留・証跡・構成は branch 横断画面として未活性 branch 選択中も到達可能とし、未活性 branch で利用不能な操作カタログエントリは選択不可として有効化カテゴリへ縮退する。
  6. RPC の実 `chainId` が deployment manifest の期待値と一致しない場合は、RPC 未確認と同様に simulation・local execution・Safe 向け export を fail-closed にする。環境名・実 chainId・期待 chainId は操作画面上で識別できるようにする。
  7. branch の運用状態は manifest の Underlying / Vault 設定だけで「稼働中」と判定しない。設定済み branch はオンチェーン `dToken.cap()` と Core `shutdownTime()` を読み、cap 0 は「休止中」、shutdown 済みは「停止」、読取失敗は「状態取得失敗」として fail-closed に表示する。休止中 branch の管理・有効化確認は利用可能なまま維持し、borrowable / live の意味と admin contracts configured の意味を混同しない。Vault 内の操作状態も pause flag だけでなく、預入は dToken cap、配分は `allocateMaxMove` を含む実効可否として表示する。
  8. 各 write action は、必要 authority（role / owner）、authority holder（共有 Timelock / role holder / owner）、実行経路（direct Safe / shared Timelock / contract-local delay / permissionless）、効果発現時期、復旧主体を同じ操作カード内に表示する。Timelock の stage role（PROPOSER / EXECUTOR / CANCELLER）を対象コントラクトの authority と混同せず、header・filter・保留キューでも同じ Action Registry を正本にする。
  9. 実行主体 selector は署名 wallet の接続ではなく、role / owner read と simulation `from` に使う caller の選択として表示する。本番の候補は build-time の単一構造化設定に label と checksum-compatible address の組で固定し、`Admin Safe` / `Guardian Safe` / `Allocator Safe` を区別する。欠落 label、不正・zero・重複 address、重複 label、旧 address-only 設定との併用は production build guard で拒否し、UI では label と checksum address の全桁を確認できるようにする。
- **Verification**: e2e-local / component / unit / build / manual

### FRNT-FR-025: パラメータ変更の提案ビルダー
- **Type**: Functional ｜ **Source**: DTKN-FR-006 / VAULT-FR-008,009,012 / STGY-FR-011
- **対象**: (B)
- **要件**:
  1. [Governance.md](../../../Governance.md) の正規ロール索引と各 component spec のうち Day-1 holder が存在する操作を Action Registry で管理し、現在値・提案値・必要 authority・実行経路・影響を表示する。対象は parameter / activation、Vault / Strategy 運用、pause / writeoff、Oracle source、ownership / role、UUPS、共有 Timelock の運営である。未採用 Strategy や報酬経路は採用要件の追加前に公開しない。
  2. branch 運用値は [Parameters.md](../../../Parameters.md)、Day-1のStrategy登録状態・cap / weightは[Mainnet Deploy Env Freeze Runbook](../../launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md)と生成Manifestを参照し、オンチェーンreadbackと合わせて入力時に検証する。[Deployment Configuration Spec](../../../engineering/guides/Deployment-Configuration-Spec.md)はManifest schemaの解釈に用いる。Strategy weight 合計、disable 時 weight、cap、writeoff 後の最低 backing ratio を含み、preview 不能時は guard の明示入力を要求する。
  3. simulation 成功後だけ、chain・target・value・calldata・decode 結果・simulation block・作成情報・hash を持つ versioned artifact と Safe Transaction Builder 互換 JSON を生成する。1 artifact は outer `CALL` 1件とし、Timelock 操作は Timelock を outer target に固定する。calldata の手動転記を通常導線にしない。
  4. Safe proposal は read-only API から取得し、artifact、Safe version、全署名対象 field、nonce、version 対応の EIP-712 hash と機械照合する。Timelock wrapper は stage、inner payload、operation ID、salt、predecessor、delay まで decode する。
     全項目一致時だけ検証済みにする。秘密credentialはbrowserへ配布せず、read-only endpointを限定したsame-origin proxyで付与する。lookup の deadline・同時実行上限・kill 可能性・障害回復、proxyの流量制限と外部監視は [Admin-Console-Production-Gate](../../../contributors/deltaforesight/delivery-plans/Admin-Console-Production-Gate.md) で判定する。
  5. one-shot activation は dToken allowlist → metadata bind → Vault underlying bind の順序と失敗条件を示す。upgrade は storage layout・bytecode・codehash の外部レビューを前提に `upgradeTo` だけを扱い、Owner と upgrader を区別する。
  6. 最後の role holder を失う `revokeRole`、mainnet で [Parameters.md](../../../Parameters.md) の `PRM-GOV-COMMON-TIMELOCK-DELAY` と不一致の `updateDelay`、renounce、未監査の `upgradeToAndCall` を生成しない。
  7. 現行 LidoStrategy は本番非採用のため Action Registry へ操作を追加せず、過去 snapshot に残る場合だけ `retired` / `unknown` として read-only 表示する。
- **Verification**: unit / component / e2e-local

### FRNT-FR-026: オラクル source 差替フロー
- **Type**: Functional ｜ **Source**: ORCL-FR-001,002,003 / ORCL-GOV-004
- **対象**: (B)
- **要件**:
  1. proposeSource → （timelock 経過） → confirmSource / confirmSourceEmergency → 必要時 cancelSourceProposal の一連を、提案中 source・残り待機時間・confirm 期限つきで可視化する。
  2. confirm 前検証（新 source の応答・価格の妥当域）をシミュレーションとして提供する。`confirmSourceEmergency` は timelock と smoke-test を維持し、価格乖離 guard のみ bypass する操作として通常 confirm から明確に分離して表示する。
  3. ブランチ横断の「現在の source / 提案中 source」一覧を提供する。
- **Verification**: e2e-local / component

### FRNT-FR-027: 緊急操作（pause / unpause）
- **Type**: Functional ｜ **Source**: VAULT-FR-014 / STGY 系 ERR
- **対象**: (B)
- **要件**: pause 系操作は、影響範囲（停止する機能・継続する機能）の説明表示と二重確認を伴って準備する。実行後はユーザーアプリの告知バナー（FRNT-ERR-006）への反映状態を確認できる。
- **Verification**: e2e-local / manual

### FRNT-FR-028: ALLOCATOR 運用画面
- **Type**: Functional ｜ **Source**: VAULT-FR-004,005 / STGY-FR-001..005
- **対象**: (B)
- **要件**:
  1. ブランチ別の buffer 現況（目標比・余剰）と Strategy 別の配分状況を表示し、allocate の数量入力に対して**実行後の buffer・backing 比への影響試算**を表示する。
  2. Strategy からの push（receiveFromStrategy）履歴・収益実績を参照でき、実現利益の push（`sendToVault` / `sendProfitToVault`）を FRNT-FR-025 の Action Registry から準備できる。
  3. 配分先は whitelist 登録済み Strategy のみを選択肢に出す。
  4. Strategy kind は `aave-v3` / `erc4626` / `morpho-v2` / `sky-susds` / `etherfi-weeth` / `retired` / `unknown` を区別して表示する。現行 `lido` は active kind として扱わず、過去 snapshot では `retired` / `unknown` の read-only 表示へ変換する。`etherfi-weeth` は pending request・claim 済み idle underlying、`sky-susds` は自己 sUSDS share・idle USDS・max conversion loss を同じ Strategy 行で確認できる。
  5. `cacheStale == true` でも live estimate と principal が利用可能で `usingCachedConservativeValue == false` の場合は、現在評価の障害ではなく fallback 用 backup cache の保守課題として表示し、保留操作キューへ valuation 障害として起票しない。実際の cache fallback、estimate/principal 読取不能、estimated loss とは操作警告の強度を分ける。
- **Verification**: e2e-local / component

### FRNT-FR-029: timelock・保留操作キュー
- **Type**: Functional ｜ **Source**: SYS-NFR-003 / DTKN-GOV-004 / ORCL-FR-002
- **対象**: (B)
- **要件**:
  1. dToken / Vault / Strategy / Oracle / Treasury / Timelock の保留操作を、期限、stage、必要 action、authority、担当とともに一覧する。
  2. 生成 artifact は直ちに補助台帳へ登録し、再読込時に chain、Action ID、target、現行実行経路、Timelock、simulation age を再検証する。不一致または1時間を超えた simulation は再生成を要求し、同じ semantic operation の旧 artifact は superseded とする。
  3. 検証済み proposal が `isExecuted && isSuccessful` かつ on-chain tx hash を持つ場合だけ操作証跡へ移す。失敗は未適用のままキューに残す。
- **Verification**: component / e2e-local / manual

### FRNT-FR-030: 操作証跡
- **Type**: Functional ｜ **Source**: SYS-NFR-005
- **対象**: (B)
- **要件**: 特権操作を `prepared`、Safe / Timelock の各 stage、`executed-safe`、`failed-safe` として時系列表示する。オンチェーン event / receipt を正本、FRNT-FR-025 の artifact と FRNT-FR-029 の補助台帳を引き渡し証跡とし、Action ID・authority・outer / inner target・payload hash・実行 tx を突合する。AccessControl role は既知名へ decode する。Safe Service の transaction hash だけで実行成功と判定しない。
- **Verification**: e2e-local / manual

### 6.4 (B) Private Operations Monitor / (C) Dune Public Analytics

本節はtarget requirementを定義する。実装済み・production-readyを意味しない。
各surfaceの現在状態は
[Frontend Data Source Ledger](../../../engineering/verification-ledgers/Frontend-Data-Source-Ledger.md)、
要件ごとの実装・検証状態は
[Requirements Verification Ledger](../../../engineering/verification-ledgers/Requirements-Verification-Ledger.md)
を正とする。Duneはquery registry、実query / dashboard、Dune上のcompile・成功execution、
RPC / event照合、freshness、実測creditsが揃うまで未実装として扱う。

### FRNT-FR-031: ブランチ概況の監視
- **Type**: Functional ｜ **Source**: SYS-NFR-005 / SYS-INV-001,004
- **対象**: (B) Private Operations Monitor
- **要件**: 全ブランチの TCR・SCR・CCR・MCR・総債務・SP 残高・SP coverage・outside debt・清算/redemption 発生状況・shutdown / shield 状態を単一画面で俯瞰でき、TCR と CCR の差分を併記してしきい値接近を判断できるようにする。SP coverage 100% 未満と outside debt 正値を thin-SP state として視覚的に強調する。
- **Verification**: e2e-local / visual / monitor

### FRNT-FR-032: オラクル監視
- **Type**: Functional ｜ **Source**: ORCL-SEC-005 / SYS-RISK-001 / Day1 Parameter Manifest `PRM-ORACLE-*`
- **対象**: (B) Private Operations Monitor
- **要件**:
  1. ブランチ別に現在価格・最終更新からの経過時間・staleness しきい値に対する余裕・lastGoodPrice fallback / shutdown 状態を表示する。
  2. JPY/USD など**全ブランチ共通依存フィード**を独立した監視対象として明示する。
  3. source 差替（提案中・確定済み）の状態を Admin Control と同じデータ源から表示する。
- **Verification**: e2e-local / monitor / visual

### FRNT-FR-033: Vault・Strategy 監視
- **Type**: Functional ｜ **Source**: VAULT-FR-016,017,018 / STGY-FR-006..009
- **対象**: (B) Private Operations Monitor（現在値・異常）＋ (C) Dune Public Analytics（公開履歴）
- **要件**: Private Operations Monitor は、ブランチ別に buffer 残高（目標比）・割当元本・Strategy 評価額・valuation 失敗・backstop reserve・backing 比・pending withdrawal を表示し、`A < L_effective` 方向の変化を強調する。Strategy 緊急停止と valuation 失敗/cache 無効化は通知対象とし、設定変更 tx と直後の状態を同じ認証済み運用面で確認できること。Dune は Strategy 追加/更新/緊急停止/削除・push（収益/元本返却）・writeoff・backing 比の公開履歴を、event から再構築できる範囲で表示する。Strategy 種別集計は `aave-v3` / `erc4626` / `morpho-v2` / `sky-susds` / `etherfi-weeth` / `retired` / `unknown` を分け、Sky / Etherfi が `unknown` に落ちず、過去の Lido snapshot が active kind に復帰しないこと。
- **Verification**: e2e-local / monitor / visual

### FRNT-FR-034: Treasury・収益フロー監視
- **Type**: Functional ｜ **Source**: VAULT-FR-007 / TRSY-FR 系
- **対象**: (C) Dune Public Analytics＋operations evidence
- **要件**: Day-1 は `transferYieldToTreasury`、Strategy `RewardTokenSwept`、`InterestRouterForwarder.Routed` を branch / token / tx hash 単位でDuneに公開し、Safe外部exportとの突合はbrowser bundle外の運用証跡で行う。Day-2 Treasury導入後は分配実績へ拡張し、未確定のSP追加報酬経路をlive表示しない。
- **Verification**: e2e-local / visual

### FRNT-FR-035: アラート連携
- **Type**: Functional ｜ **Source**: SYS-NFR-005 / 各 component の EVT 系要件
- **対象**: (B) Private Operations Monitor（表示）＋ browser 非依存の通知基盤
- **要件**:
  1. FRNT-FR-031..034 の異常を alert key で重複排除し、severity、owner、通知先、ACK期限、status（triggered / acknowledged / escalated / resolved）を持つ通知へ変換する。
  2. しきい値、routing、public 告知境界、payload、状態遷移、永続化、配送証跡は [Incident-Notification-Policy.md](../../../contributors/deltaforesight/operations/Incident-Notification-Policy.md) を正本とし、通知は on-chain action を自動実行しない。
  3. イベント履歴が取得できない場合、現在値由来の異常なしと監視縮退を分け、「全システム正常」と表示しない。
  4. 公開面は承認済みの影響・状態・継続可能操作だけを表示し、内部 owner、channel、ACK / escalation、secret を認証済み運用面と分離する。
  5. Dune schedule / alert を critical alert、ACK state、public comms の発報源にしない。
- **Verification**: monitor / manual

### FRNT-FR-036: Dune 公開トランスペアレンシー
- **Type**: Functional ｜ Priority: Should ｜ **Source**: SYS-NFR-002,005
- **対象**: (C) Dune Public Analytics
- **要件**: 公開 on-chain 指標（供給量・担保構成・債務・金利・SP・liquidation / redemption・dToken・Vault / Strategy flow・Revenue / Treasury）をDuneで一般公開する。各metricはquery registryにdata source、SQL、owner、freshness、credit cost、RPC等との照合方法を持つ。dashboardはreal-time monitorではないことと最終実行時刻を明示し、内部alert・owner・channel・ACK / escalation・運用手順・private endpointを含めない。User App current healthはDune APIに依存させない。
- **Verification**: visual / manual

### FRNT-FR-037: 操作フィードバックとモーション抑制
- **Type**: Functional ｜ Priority: Should ｜ **Source**: SYS-NFR-002
- **対象**: (A)(B) 共通 UI 基盤
- **要件**:
  1. 主要 command control は、layout shift を起こさない即時の押下フィードバックを持つ。disabled control は押下状態を表示しない。
  2. 金融数値、価格、残高、リスクグラフの更新に装飾目的のモーションを追加しない。モーションは command feedback、画面遷移、処理待機、エラー出現など状態理解を助ける場合に限定する。
  3. `prefers-reduced-motion: reduce` では CSS transition / animation と JavaScript spring を抑止する。色、文言、進捗、エラーなど状態を伝える非モーション表現は維持する。
  4. transition easing は UI kit の共有 token を使用し、画面ごとの任意カーブを増やさない。
- **Verification**: uikit gallery build / compiled CSS artifact check / visual

---

## 7. 状態・データソースモデル

| データ種別 | 正のソース | 補助 | 備考 |
| --- | --- | --- | --- |
| 残高・許可額・ポジション現在値 | RPC（コントラクト読み取り） | — | 表示ブロック高を保持 |
| 価格・backing 比 | RPC（PriceFeedProxy / Vault） | — | ORCL-FR-004,005,014 |
| ブランチパラメータ（MCR 等） | RPC（オンチェーン値） | Parameters.md（突合） | FRNT-FR-002 |
| 入力検証用定数（MIN_DEBT 等） | 生成された定数ミラー | CI 突合 | FRNT-INV-002 |
| 一覧・履歴（Trove 一覧・操作履歴・金利分布） | subgraph | — | 鮮度検証つき（FRNT-FR-008） |
| User App current health | DF-managed public stats publisher | RPC snapshot | Duneをruntime APIとして使用しない（FRNT-TBD-004） |
| 公開統計・履歴・Treasury flow | Dune decoded/raw on-chain data | query registryの照合先 | 秒単位SLA、critical alert、任意view readを前提にしない |
| 保留操作・timelock 状態 | RPC＋イベント索引 | subgraph | (B) Admin Control / Private Operations Monitor共用 |
| UI 状態（入力途中・設定） | クライアントローカル | — | 資産情報を永続化しない |

---

## 8. 整合不変条件 INV

- **FRNT-INV-001（表示とオンチェーンの一致）**: 操作確認画面に表示される金額・レート・手数料は、同一参照ブロックの RPC 読み取りから導出され、表示丸め（FRNT-FR-009 の要件 3）以外の差異を持たない。
- **FRNT-INV-002（定数ミラー一致）**: フロントエンドが保持する全ての定数ミラーは、コントラクト定数なら `Constants.sol`、ブランチパラメータならオンチェーン値と [Parameters.md](../../../Parameters.md) を原本として CI 上で機械突合され、不一致のままリリースされない。
- **FRNT-INV-003（シミュレーションなしに署名要求しない）**: 全ての書き込み操作は、直前のシミュレーション成功なしにウォレット署名要求へ進めない。
- **FRNT-INV-004（秘密の不在）**: フロントエンドの配布物・リポジトリ・クライアント公開環境変数に、秘密鍵・特権 API キー・個人情報を含まない。

---

## 9. セキュリティ要件 SEC

- **FRNT-SEC-001（サプライチェーン）**: 依存パッケージは lockfile で固定し、依存追加・更新はレビューと脆弱性監査を経る。実行時に第三者ドメインのスクリプトを読み込まない（ウォレット接続ライブラリ等の外部通信は既知エンドポイントに限定）。ビルドは再現可能とし、配布物とソースの対応を検証できるようにする。
- **FRNT-SEC-002（配信完全性）**: 公式ドメインに DNSSEC を適用し、ホスティング・DNS・CDN の管理権限を会社管理（FRNT-GOV-001）に置く。CSP・SRI 等で改ざんスクリプトの実行面を縮小する。ミラー配信（IPFS / ENS 等）の Day-1 方針と Day-2 採用 gate は FRNT-TBD-006 / [Frontend-Mirror-Delivery-Policy.md](../../../contributors/deltaforesight/delivery-plans/Frontend-Mirror-Delivery-Policy.md) を正とする。
- **FRNT-SEC-003（表示の完全性）**: 外部由来文字列（ENS 名・referral 等）は無害化して表示する。アドレスは全桁確認手段（コピー・explorer リンク）を常に提供し、紛らわしい省略表示だけで承認させない。
- **FRNT-SEC-004（承認の安全）**: spender は自プロトコルの既知コントラクト（バインディング由来）に限定し、任意アドレスへの承認をフローとして提供しない。無制限承認は提供しない（FRNT-FR-007）。
- **FRNT-SEC-005（フィッシング耐性）**: 公式リンク（ドメイン・SNS・ドキュメント）はリポジトリ管理の単一ページ台帳から生成し、説明対象へ直接リンクする。公開 hosting では JP / EN の公開 root を対で必須とし、未設定を拒否する。local / test の authoring fallback を公開導線として扱わず、公開コンテンツから内部仕様へ直接リンクしない。operator 向け導線は公開 UI と明確に分離する。外部リンクは `rel="noopener noreferrer"` を強制し、偽サイト発生時の告知手段を運用 runbook に持つ。
- **FRNT-SEC-006（プライバシー）**: 解析・計測はオプトイン（または同意バナー付き）とし、アドレスと個人情報の紐付け収集をしない。テレメトリ（§11）は PII を含まない。
- **FRNT-SEC-007（管理サーフェス分離）**: Admin Control と Private Operations Monitor は公開面から到達不可とし、閲覧にも認証を要求する。monitor viewer と privileged operator / signer は別 role にでき、viewerへ特権操作を付与しない。準備機能はオンチェーン権限を再検証し、権限強制はオンチェーン側にある前提を崩さない。Dune、User App、移行中のpublic Ops bundleにはprivate endpoint、admin runtime config、operator routing、worker command、source map、key materialを含めない。public Opsのpublic-bundle guardはbuild / publish workflowのdecommission完了までfail-closedで維持し、guard削除をworkflow撤去と同じreview単位にする。
- **FRNT-SEC-008（エンドポイント鍵）**: browser向けread-only RPC / subgraph credentialはUser App、移行中のpublic Ops、Admin Controlで共有してよいが、公開credentialとして全利用domainのallowlist、合算rate / capacity、rotation / revocation ownerを持つ。provider契約上secretとして扱うread-only API keyはbrowser bundleへ入れず、会社管理secret storeからread-only endpointと流量を制限したsame-origin proxyへ注入する。認証済み運用面の境界をRPC URL / keyの秘匿性に依存させず、worker-only / archive / write / signing credentialはbrowser credentialと分離する（FRNT-GOV-001）。

---

## 10. ガバナンス・運用・アップグレード要件 GOV

- **FRNT-GOV-001（資産の会社所有）**: ドメイン・ホスティング・RPC / subgraph アカウント・解析基盤・統計 API は会社アカウントで所有し、アクセス権を役割ベースで管理する（個人アカウント依存の排除。Development-Plan 横断バックログと整合）。
- **FRNT-GOV-002（リリース管理）**: 本番リリースはバージョン付与とソースコミットの対応（フッター等での出自表示）を持ち、ロールバック手順を整備する。本番環境変数の変更は通常のコード変更と同等のレビューを経る。
- **FRNT-GOV-003（変更管理と要件トレース）**: フロントエンドの仕様変更はまず本書（FRNT-ID）に反映し、実装 PR・コード・テストが該当 ID を参照する（標準ガードレール「ID 連携は一方向」のフロントエンド適用。コード側はコメント注釈 `@requirement FRNT-FR-NNN` 相当、PR は本文で ID を引用）。doc 側に PR/SHA を書かない。
- **FRNT-GOV-004（上流追随）**: 上流 Liquity v2 app の更新は、DF 差分（FRNT-FR-011 等）との衝突を確認のうえ定期的に取り込む。取り込み判断と差分台帳を運用に持つ（フォーク乖離の無制御な拡大を防ぐ）。
- **FRNT-GOV-005（監査受け入れ）**: FRNT の FR / INV / SEC を「実装 × 検証手段」のカバレッジ台帳（Development-Plan の監査受け入れと同型）に組み込み、未カバー 0 を確認してからリリース判定する。

---

## 11. テレメトリ・監視要件 EVT

- **FRNT-EVT-001（クライアント例外）**: 未捕捉例外・描画エラーを PII なしで収集し、リリース単位で回帰を検知する。
- **FRNT-EVT-002（合成監視）**: 公開サーフェスの死活・RPC / subgraph 応答・主要画面の描画成功を外形監視し、障害時に運用へ通知する。RPC probe は静的 HTML の HTTP 取得とは分離し、設定済み read-only endpoint に `eth_chainId` と `eth_blockNumber` を送って期待 chain と現在 block の双方を検証する。FRNT-SEC-008 の共有 browser credential を利用してもよいが、URL・query・credential は alert / log に残さない。
- **FRNT-EVT-003（tx 成否計測）**: フロント経由 tx の送信数・失敗率・主要 revert 理由を集計し、UX 起因の失敗（検証漏れ・定数乖離）を検出する。アドレス単位の行動追跡は行わない（FRNT-SEC-006）。

---

## 12. 失敗時・異常系挙動 ERR

- **FRNT-ERR-001（RPC 障害）**: 読み取りはフォールバック系統へ切り替え、全系統不通時は「最終取得時点」を明示した縮退表示にする。書き込み操作は不通時に無効化する。user app は `eth_chainId` と最新 block の runtime probe が一度成功するまで write を開始せず、各 tx step の直前にも同じ probe を再実行する。失敗中は新規 flow、既存 flow の次 step、devnet faucet を一括で fail-closed にする。RPC 障害表示には最終成功時刻と再確認導線を含める。Ops は前回取得値を live 値として扱わず、Admin は RPC 未確認中の simulation と local execution を停止する。AWS synthetic worker も同じ期待 chain の read-only RPC を再試行付きで probe し、全系統不通を `ALRT-FRNT-002` として通知する。
- **FRNT-ERR-002（subgraph 劣化）**: 同期遅延がしきい値を超えた場合、履歴・一覧画面に鮮度警告を表示し、現在値系（RPC 由来）と視覚的に区別する。完全停止時は一覧系のみ縮退し、操作系（RPC ベース）は維持する。
- **FRNT-ERR-003（チェーン不一致）**: ウォレットの接続チェーンが対象チェーンと異なる場合、全ての書き込み UI をブロックし、現在 chain と期待 chain を表示した全画面バナーで切替導線を表示する。tx 失敗表示にも chain ID を残し、mainnet wallet で devnet app を操作している等の誤接続をユーザーとサポートが識別できるようにする。
- **FRNT-ERR-004（tx 失敗）**: 失敗 tx はデコード済みの理由（カスタムエラー名と人間可読説明の対応表）と再試行・サポート導線を表示する。理由不明の失敗は error id / tx hash / redacted details を提示し、raw stack、private RPC URL、API key fragment、DataAPIError 詳細は user-visible にしない。
- **FRNT-ERR-005（ブランチ異常）**: oracle 障害・branch shutdown・pause（VAULT-FR-014）を検出した場合、該当ブランチの新規操作（借入・mint 等）を画面でブロックし、許される操作（返済・claim〔`pauseClaim` 中は claim も停止〕・urgent redemption 等）のみ提示する。`PriceFeed.fetchPrice()` が返す `newOracleFailureDetected` を価格値と一緒に検査し、last-good price の正値だけを見て正常扱いしない。価格・TCR/CCR・branch debt・Vault・shutdown の必須 RPC 読み取りが失敗または未確定の間も新規借入を fail-closed にする。コントラクト側の防御が正であり、フロントのブロックは UX 上の先回りにすぎない。
- **FRNT-ERR-006（インシデント告知）**: 運用判断で全画面バナー（注意喚起・メンテナンス・読み取り専用化）を、コード変更なしの設定変更で掲出できる。

---

## 13. 受け入れ基準・検証計画

**検証手段の種別**: `unit`（純関数・ユーティリティ）/ `component`（UI コンポーネント・画面単位）/ `e2e-local`（ローカルチェーン＋subgraph＋アプリの一気通貫）/ `build`（ビルド・型・環境スキーマ）/ `ci-guard`（原本突合・文言 lint 等の自動ゲート）/ `visual`（表示確認）/ `manual`(運用手順) / `monitor`（本番外形監視）。

| 領域 | ID | 主検証 |
| --- | --- | --- |
| バインディング・定数・ABI | FRNT-FR-001..004, FRNT-INV-002 | build / ci-guard |
| ウォレット・tx・承認 | FRNT-FR-005..007, FRNT-INV-003 | e2e-local / component |
| データソース・表示規約 | FRNT-FR-008..011, FRNT-INV-001 | unit / component / monitor |
| ユーザーアプリ機能 | FRNT-FR-012..023,038 | e2e-local / component / visual |
| 管理者コンソール | FRNT-FR-024..030 | e2e-local / component / manual |
| Private Operations Monitor / Dune Public Analytics | FRNT-FR-031..036 | e2e-local / visual / monitor / query reconciliation |
| セキュリティ | FRNT-SEC-001..008, FRNT-INV-004 | ci-guard / build / manual |
| 異常系 | FRNT-ERR-001..006 | e2e-local / component / manual |

**受け入れの原則**:
1. **docs ↔ code parity** — 実装・テスト・PR は FRNT-ID を参照し、全 FR / INV / SEC が「実装状況 × 検証手段」の台帳で未カバー 0 になる（FRNT-GOV-005）。
2. **e2e-local を一級の受け入れ手段とする** — ローカルチェーンへの deploy＋subgraph＋アプリの一気通貫環境で、主要ユーザーフロー（借入→調整→Earn→redeem→claim）が再現可能であること。
3. **リリースゲート** — FRNT-INV-002（定数突合）・FRNT-FR-004（環境スキーマ）・FRNT-SEC-001（依存監査）を CI の必須ゲートとする。本番判定は [Frontend Production Delivery Gate](../../../contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md) を共通正本とし、UX / Agent / Admin は対象 surface の差分だけを追加する。

---

## 14. 未決事項 TBD

| ID | 状態 | 未決または移管先 |
| --- | --- | --- |
| FRNT-TBD-001 | 未決 | DFT トークノミクス・PIL 投票確定後の Stake / governance UI |
| FRNT-TBD-002 | 未決 | Multiply 再導入。dToken leverage、audited entrypoint、JPYdf / USDC v4 route、fork evidence を要する |
| FRNT-TBD-003 | 未決 | SP 追加報酬・Treasury 分配の表示。確定まで非表示 |
| FRNT-TBD-004 | Gateへ移管 | stats endpoint の本番証跡は [Production Gate](../../../contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md)。APR時系列はDay-2 |
| FRNT-TBD-005 | Gateへ移管 | console本番証跡は [Admin Gate](../../../contributors/deltaforesight/delivery-plans/Admin-Console-Production-Gate.md) |
| FRNT-TBD-006 | 解決 | Day-1は公式HTTPS originのみ。Day-2 mirrorは [Mirror Policy](../../../contributors/deltaforesight/delivery-plans/Frontend-Mirror-Delivery-Policy.md) |
| FRNT-TBD-007 | Gateへ移管 | domain・hosting・runtime・monitoring・rollbackは [Production Gate](../../../contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md)。Dune / Private Operations Monitorへのdual-run・cutover・decommissionは [監視アーキテクチャ](../../../contributors/deltaforesight/operations/Public-Analytics-Private-Monitoring-Architecture.md) |
| FRNT-TBD-008 | 解決 | primary locale は英語。user app は英語・日本語の全画面を提供し、未保存時は英語、保存済みの明示的な選択だけを初期表示へ反映する。 |
| FRNT-TBD-009 | Gateへ移管 | mobile / in-wallet最低条件は [UX Gate](../../../contributors/deltaforesight/delivery-plans/Frontend-UX-Readiness-Gate.md) |
| FRNT-TBD-010 | Gateへ移管 | borrower / SP depositor / liquidator証跡は [Participant Gate](../../launch/gates/Mainnet-Participant-Readiness-Gate.md) |
| FRNT-TBD-011 | 未決 | paid Referral activation。registry・abuse・budget・root / claim evidenceを要する |

---

## 15. 参考資料

- 上位要求・アーキテクチャ: [Product-Overview.md](../Product-Overview.md)（SYS-FR-001..008 / ARCH-001..005）
- launch risk gate: [Mainnet-Launch-Risk-Gate.md](../../launch/gates/Mainnet-Launch-Risk-Gate.md)（SYS-RISK-001..009）
- 操作対象の規範仕様: [dToken.md](./dToken.md) / [CollateralVault.md](./CollateralVault.md) / [Strategy.md](./strategies/Strategy.md) / [Oracle.md](./Oracle.md) / [Zapper.md](./Zapper.md) / [Treasury.md](../../roadmap/spec/Treasury.md)
- 値の正本: [Parameters.md](../../../Parameters.md)
- 🔵 コア挙動: [Liquity-v2-Core-Spec.md](./Liquity-v2-Core-Spec.md)
- 社内計画: [development/Development-Plan.md](../../../engineering/plans/Development-Plan.md)（現在の作業と完了条件）
- 公開分析・private monitoringの責務と移行: [Public-Analytics-Private-Monitoring-Architecture.md](../../../contributors/deltaforesight/operations/Public-Analytics-Private-Monitoring-Architecture.md)
- 参加者別 launch readiness: [Mainnet-Participant-Readiness-Gate.md](../../launch/gates/Mainnet-Participant-Readiness-Gate.md)
- 書式標準: [要件定義ドキュメント標準](../../../Requirements-Spec-Standard.md)
