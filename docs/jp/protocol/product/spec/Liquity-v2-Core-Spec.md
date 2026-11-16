# 🔵 Liquity v2 コア仕様（Liquity v2 Core Spec）

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Draft（コア継承仕様の正本化中） |
| Owner | DeltaForesight |
| 対象コントラクト | `contracts/src/` の Liquity v2 コア一式（§5.1 カタログ参照）。規範ソースは不変上流参照ブランチ **`base`**（liquity/bold **v1.11.0**）、ならびに §2.2 `CORE-MOD-*` 台帳で明示する DF 差分 |
| 文書の役割 | 🔵 コアの**継承仕様の正本**。コアの全コントラクト・全 external/public 関数・全状態変数・全イベントを ID 付きで規範化し、フォーク元同一性（parity）検証と DF 差分管理のトレース基盤を提供する |
| 関連ドキュメント | [Product-Overview](../Product-Overview.md)（システム要求・アーキ）/ [Parameters](../../../Parameters.md)（パラメータ値の正本）/ [dToken](./dToken.md)・[CollateralVault](./CollateralVault.md)・[Strategy](./strategies/Strategy.md)・[Oracle](./Oracle.md)・[Zapper](./Zapper.md)（🟢 独自レイヤー）/ [要件定義ドキュメント標準](../../../Requirements-Spec-Standard.md) |

> 本書は [要件定義ドキュメント標準](../../../Requirements-Spec-Standard.md)に従う（コア継承仕様としての読み替えは §2.4）。要件・不変条件・セキュリティ要件には永続 ID（`CORE-…`）を付し、相互参照は ID で行う。
>
> **マーカー凡例** — 🔵 Core: `base` と同型に継承する挙動（JPYdf canonical surface への rename は差分台帳で管理し、単独の会計差分とは扱わない）／ 🟡 Modified: DF が変更した箇所（§2.2 `CORE-MOD-*` 台帳）／ 🟢 Original: DF 独自追加・surface 整理（本書スコープでは LiquidationCandidateGetter と Constants の Day-1 ブランチ定数 surface。独自レイヤー本体は各 component spec）。

---

## 1. 目的・スコープ・非責務

本書は、DeltaForesight が Liquity v2（BOLD）からフォークして **base-parity を基準に継承するコアコントラクト群**の規範仕様である。

- **本書が規定する**:
  1. コア全コントラクトの責務・インターフェース・機能要件（全 external/public 関数）・状態変数・イベント・不変条件・セキュリティ性質・異常系（§5〜§12）
  2. **DF がコアに加えた差分の完全な台帳**（§2.2 `CORE-MOD-*`。旧 BOLD surface の再混入は CI が機械検出し、挙動差分・コピー変種・Constants 等は本台帳と parity 検証〔§13〕が管理する）
  3. フォーク元同一性（parity）の受け入れ基準・検証計画（§13）— 「すべての関数・状態変数がフォーク元と同じように機能していること」をテストで確認するためのトレース基盤
- **本書が規定しない（非責務・他文書）**:
  - 🟢 独自レイヤーの要件 — dToken / CollateralVault / Strategy / Oracle（PriceFeedProxy・DF PriceFeed）/ Zapper / Treasury / Frontend → 各 component spec
  - 担保ブランチごとのパラメータ**確定値**（MCR/CCR/SCR/BCR/penalty/mintCap 等）→ [Parameters.md](../../../Parameters.md)（本書は意味と制約のみ規定）
  - upstream ガバナンス（V2-gov / ve-LQTY / PIL 投票）— 本リポジトリのコアコントラクト外であり、jpydf では未採用。利息残余 25% の受け口は `InterestRouterForwarder` 方針で解決済み（CORE-AP-TBD-001）
  - デプロイ手順・アドレス・進捗 → `development/` と deployment 資料
- **読み方**: 全体像と機構の直観は §2.3、規範の本体は §6（機能要件）。テスト・監査は §8〜§13 を起点に各 ID へ。

---

## 2. 背景・設計方針

### 2.1 採用方針 — base-parity fork と「外側で解く」

JPY DeFi は Liquity v2 の会計・清算・Redemption ロジックを base 同型で継承する（[Product-Overview](../Product-Overview.md) `ARCH-001` / [Architecture Decision Records](../architecture/Architecture-Decision-Records.md#adr-001)）。一方、現行 protocol は **JPYdf を正式な debt-token / public API surface** として扱うため、BOLD 命名 surface は JPYdf 命名へ置換し、Day-1 方針から外れた legacy exchange surface は削除する。挙動のカスタマイズは次の経路に限定し、差分は §2.2 の台帳で管理する:

1. **汎用インターフェースの差し替え** — 担保 ERC-20 に dToken、価格フィードに PriceFeedProxy を与える（コアは相手が DF 独自レイヤーであることを知らない）。
2. **パラメータ値** — `Constants.sol` の定数値と、branch ごとの constructor 引数（AddressesRegistry の immutable 群）。
3. **新規ファイル / deployment variant の追加** — インターフェース互換のコピー＋最小差分（DFStabilityPool、JPYdfTroveNFT / JPYdfMetadataNFT）または新規ヘルパー（LiquidationCandidateGetter）として足す。
4. **JPYdf 命名 surface** — debt token / BorrowerOperations API / NFT metadata など、integrator が触る名前を JPYdf へ統一する。

現行 CI の機械ガードは **Core JPYDF surface guard**（`.github/scripts/check-core-jpydf-surface.sh`）であり、owned protocol surface に旧 BOLD public/API 名が再混入することを禁止する。旧来の blanket な upstream byte-identity gate は、BOLD 互換を残す方針では有効だったが、現行の JPYdf canonical surface / legacy route pruning 方針とは競合するため採用しない。base との静的 parity は、§2.2 台帳・diff review・parity/unit test で確認する。

### 2.2 DF 差分台帳（CORE-MOD-*）🟡

**DF がコアに対して加えた差分のすべて**を以下に列挙する（append-only。upstream 由来の挙動差分がここに無ければ spec / parity 違反として扱い、現行 CI は旧 BOLD surface の再混入を別途検出する）。各 🟡 要件は本台帳を参照する。

> **台帳の対象範囲**: 本台帳が管理するのは「**コアの挙動・コード面への差分**」（upstream ファイルの値変更・コピー変種・upstream ファイルへの追記・deployment で upstream counterpart と置き換えるインターフェース互換 variant）に限る。base に無い**純粋な新規追加ファイル**はコアを変更しないため本台帳の対象外であり、🟢 独自レイヤー（dToken / CollateralVault / Strategy / Oracle / Zapper 等）は各 component spec が、本書スコープの 🟢（LiquidationCandidateGetter）は `CORE-LCG-*` が管理する。

#### CORE-MOD-001: 債務トークンの JPYdf 命名化 🟡

- **対象**: debt-token 命名 surface（`JpydfToken.sol` / `IJpydfToken` / `jpydfToken()` / `JpydfTokenAddressChanged` / `_NAME` / `_SYMBOL` など）
- **base**: `BoldToken` / `IBoldToken` / `boldToken` / `BOLD Stablecoin` / `BOLD` → **DF**: `JpydfToken` / `IJpydfToken` / `jpydfToken` / `JPYdf Stablecoin` / `JPYdf`
- **種別**: 識別子・ABI getter/event・ERC-20 metadata の rename（既存 Core `mint` / `burn` / permit / permission のロジックは base 同型。bridge-ready 追加 surface は CORE-MOD-008）
- **理由**: プロダクト命名（JPYdf）と integrator が触る debt-token surface の一貫化。
- **ガード**: 命名差分は CORE-MOD-001 として台帳管理し、挙動差分が混入しないことを parity / unit で検証する。
- **規定**: CORE-BT-FR-010（規範本文は [JpydfToken.md](./JpydfToken.md)）

#### CORE-MOD-002: MIN_DEBT の再スケール 🟡

- **対象**: `Constants.sol` の `MIN_DEBT`
- **base**: `2000e18`（2,000 BOLD ≒ $2,000） → **DF**: `300_000e18`（300,000 JPYdf）
- **種別**: 定数の値変更
- **理由**: 債務単位が USD 建て BOLD から JPY 建て JPYdf に変わるため、base と同水準の経済的最小債務（スパム Trove 防止・清算採算性の確保）を円建てで再設定する。確定値の正本は [Parameters.md](../../../Parameters.md)。
- **影響範囲**: 開設・調整時の最小債務検査、返済の silent cap、zombie 判定閾値（CORE-BO-FR-001 ほか、CORE-TM-FR-004）。
- **規定**: CORE-LIB-FR-002

#### CORE-MOD-003: 清算担保補償 cap の緩和 🟡

- **対象**: TroveManagerのconstructor、予約ブランチのrisk finalization、`Constants.sol`。
- **計算**: `min(SP相殺分の担保 / COLL_GAS_COMPENSATION_DIVISOR, branch cap)`。料率0.5%は維持する。Day1の上限は[Parameters.md](../../../Parameters.md)に定める。
- **理由**: ETH系担保とドル連動担保では1単位の価値が異なるため、上限をブランチごとに設定する。
- **仕様**: CORE-LIB-FR-003。

#### CORE-MOD-004: DFStabilityPool（same-block 精算ガード付き SP 変種）🟡

- **対象**: 新規ファイル `DFStabilityPool.sol`（`StabilityPool.sol` の全文コピー＋最小差分）。**デプロイされる Stability Pool はこちら**であり、`StabilityPool.sol` は JPYdf canonical surface rename 後の behavior-parity 規範として温存する（byte-identical な base copy ではない）。
- **機能差分（全 4 点・これがすべて）**:
  1. 状態変数 `mapping(address => uint256) public lastDepositBlock` の追加（設計意図を述べるコメント付き）
  2. `provideToSP` で既存預金者が `_doClaim=true` により current または stash 済み担保ゲインを受け取る場合、`_requireCollGainClaimAfterDeposit()` で預入ブロックより後であることを検査
  3. `provideToSP` 内（`DepositOperation` emit 直後・状態更新群の先頭）で `lastDepositBlock[msg.sender] = block.number` を記録
  4. `withdrawFromSP` 冒頭（`_requireUserHasDeposit` 直後）で `_requireWithdrawalAfterDeposit()` を検査（コントラクト末尾に追加された internal helper。`require(lastDepositBlock[msg.sender] < block.number, "StabilityPool: Withdrawal must wait after deposit")`）
  （機械 diff 上はこのほかにコントラクト名の置換と helper 関数定義の追加ハンクを含む）
- **種別**: コピー＋追加ガード（既存の Product-Sum 会計は変更せず、担保ゲイン払出と出金に同じ block boundary を要求する）
- **理由**: 清算と同一ブロックで flash loan 等により `provideToSP` → 清算益の比例配分取得 → `withdrawFromSP`、または `provideToSP(nonzero, true)` で担保ゲインを受け取って外部換価する「清算益横取り」を遮断する（CORE-SP-SEC-004）。
- **ガード**: Core JPYDF surface guard 上は「新規追加ファイル」として通過するため、**コピー元との差分が上記 4 点に限られることの管理は本台帳と parity テスト（§13）が担う**。
- **規定**: CORE-SP-FR-004 / CORE-SP-SEC-004 / CORE-SP-ERR-002

#### CORE-MOD-005: Constants の Day-1 ブランチ定数 surface 化 🟢

- **対象**: `Constants.sol` の DF ブランチ別定数（`MCR_DWSTETH` 等、8 ブランチ × 6 種 = 48 定数）
- **種別**: Day-1 production deploy で使う定数 surface の明確化。production 未参照の upstream fixture 定数（`*_WETH` / `*_SETH` / `BCR_ALL`）と補助別名（`ZERO_ADDRESS` / `MAX_UINT256`）は `contracts/src` から削除し、inherited test fixture 側に閉じ込める。
- **理由**: Day-1 8 ブランチのデプロイ配線（branch constructor 引数）用。inert ブランチ（Br2–7）の値も immutable のため Day-1 で確定（Underlying のみ TBD。CORE-LIB-TBD-001）。
- **値の正本**: [Parameters.md](../../../Parameters.md)（本書は再掲しない）。
- **規定**: CORE-LIB-FR-004

#### CORE-MOD-006: 債務トークン表面 API の JPYdf 命名化 🟡

- **対象**: `BorrowerOperations.sol` / `IBorrowerOperations.sol` の債務トークン操作名
- **base**: `withdrawBold(uint256,uint256,uint256)` / `repayBold(uint256,uint256)` → **DF**: `withdrawJpydf(uint256,uint256,uint256)` / `repayJpydf(uint256,uint256)`
- **種別**: ABI / 識別子の rename（債務増減・upfront fee・silent cap・burn/mint の挙動は base と同型）
- **理由**: 外部 integrator / Zapper / Frontend が触る user-facing ABI を JPYdf ブランドに揃え、BOLD 由来の名前を新規 integration 面から排除する。
- **影響範囲**: BorrowerOperations の user-facing 追加借入・返済関数、Zapper の wrapper 関数、Frontend / SDK / ABI 参照。内部会計の意味（debt token amount）は不変。
- **規定**: CORE-BO-FR-006 / CORE-BO-FR-007

#### CORE-MOD-007: JPYdf TroveNFT / MetadataNFT deployed surface 🟡

- **対象**: `JPYdfTroveNFT.sol`、`Interfaces/IMetadataNFT.sol`、`NFTMetadata/JPYdfMetadataNFT.sol`、`NFTMetadata/utils/JPYdfBaseSVG.sol`。デプロイスクリプトはこれらを `AddressesRegistry.troveNFT()` / `metadataNFT()` に配線する。fresh deploy 方針に合わせ、未deployの upstream `TroveNFT.sol` / `MetadataNFT.sol` / `baseSVG.sol` は production `src` から削除済み。
- **base**: Collection `name = "Liquity V2 - " + collToken.name()`、`symbol = "LV2_" + collToken.symbol()`、JSON metadata の name / description は Liquity 文言。→ **DF deployed variant**: collection `name = "JPYdf - " + collToken.name()`、`symbol = "JPYdf_" + collToken.symbol()`、JSON metadata name / description と SVG の固定 debt 表記は JPYdf 文言。
- **種別**: プロダクト表示・metadata rendering の最小差分。Trove 所有権、mint/burn 権限、tokenURI のデータ取得、ERC-721 標準面は base 同型。
- **理由**: active deployment の NFT collection / marketplace / on-chain metadata が実プロダクト名 JPYdf と一致するようにするため。外部 alias 前提ではなく、deployed contract 自体が JPYdf 表示を返す。
- **影響範囲**: TroveNFT collection metadata、tokenURI JSON/SVG rendering、非 TM mint/burn の error style（upstream require string ではなく `JPYdfTroveNFT__CallerIsNotTroveManager()` custom error）。会計・権限への影響はない。
- **規定**: CORE-TN-FR-001 / CORE-TN-FR-002 / CORE-TN-FR-003 / CORE-TN-FR-006 / CORE-TN-ERR-001。

#### CORE-MOD-008: JpydfToken bridge-ready dormant extension 🟡

- **対象**: `JpydfToken.sol` / `IJpydfToken`
- **base**: `BoldToken` は owner renounce 後に供給権限集合が完全固定され、bridge 用 admin / minter registry / mint-burn entrypoint を持たない。→ **DF**: 既存 Core `mint` / `burn` の権限条件は base 同型のまま維持し、別 surface として `bridgeAdmin`、pending admin、bridge minter registry、48h timelock proposal、即時 removal、`bridgeMint(address,uint256)`、self-burn 型 `bridgeBurn(uint256)` を追加する。`bridgeAdmin` / bridge minter は contract address のみに限定し、兼任を禁止する。
- **種別**: additive ABI / state / events / authorization。既存 Core `mint` / `burn` には bridge minter を OR 追加しない。
- **理由**: Day1 token freeze 後に canonical bridge が不可能になる状態を避けつつ、Day-1 production scope は Ethereum 単一チェーン・bridge minter 0 件で休眠させるため。
- **影響範囲**: `JpydfToken` constructor args / CREATE2 preimage / deploy manifest / governance handover evidence / token supply monitoring。Core branch ロジック、BO/TM/SP/AP の mint/burn 呼出、dToken collateral logic には影響しない。
- **規定**: CORE-BT-FR-013 / CORE-BT-FR-014 / CORE-BT-FR-015 / CORE-BT-FR-016 / CORE-BT-INV-003 / CORE-BT-SEC-004 / CORE-BT-EVT-010（規範本文は [JpydfToken.md](./JpydfToken.md)）。

#### CORE-MOD-009: JpydfToken core address registration hardening 🟡

- **対象**: `JpydfToken.setBranchAddresses` / `setCollateralRegistry`
- **base**: branch core addresses と `CollateralRegistry` address は `onlyOwner` 以外の入力検証なしで登録される。→ **DF**: 登録対象は非ゼロかつ `code.length > 0` の contract address に限定する。
- **種別**: deploy-time hardening。正常な fresh deploy wiring では挙動不変、ゼロアドレス / codeless address の誤配線だけを早期 revert にする。
- **理由**: `setCollateralRegistry` 実行後は owner が renounce され、誤った core address 登録を取り消せない。監査前に、デプロイスクリプト外の手順ミスでも token 側で最低限の配線不変条件を強制するため。
- **影響範囲**: `JpydfToken` の一度きり owner 配線関数。BO/TM/SP/AP/CR の通常 call path、Core `mint` / `burn` の権限条件、bridge-ready surface には影響しない。
- **規定**: CORE-BT-FR-002 / CORE-BT-FR-003 / CORE-BT-SEC-002 / CORE-BT-ERR-001（規範本文は [JpydfToken.md](./JpydfToken.md)）。

#### CORE-MOD-010: ERC-20 transfer / approval hardening 🟡

- **対象**: `ActivePool.sol` / `BorrowerOperations.sol` / `DefaultPool.sol` / `GasPool.sol` / `RedemptionHelper.sol` / `TroveManager.sol`
- **base**: OpenZeppelin ERC-20 の `approve` / typed token `transfer` / `transferFrom` 直接呼出。→ **DF**: `SafeERC20` の `forceApprove` / `safeTransfer` / `safeTransferFrom` を使用する。
- **種別**: token integration hardening。正常な標準 ERC-20 / WETH / JPYdf では資産移動の意味は base と同一で、zero-first approval token や return bool 非準拠 token への互換性・失敗検出を強化する。
- **理由**: コアが扱う担保は dToken であり、将来 branch / adapter の ERC-20 実装差に依存しにくくするため。WETH gas compensation と RedemptionHelper の JPYdf 受払も safe wrapper 経由にして、失敗時を明確な revert に寄せる。
- **影響範囲**: allowance 設定、担保移転、WETH gas compensation、RedemptionHelper の JPYdf pull / refund。会計式・権限条件・mint/burn 条件は変更しない。
- **規定**: CORE-SYS-INV-007 / CORE-SYS-INV-008 / CORE-RH-SEC-001 / CORE-GP-SEC-001。

#### CORE-MOD-011: ActivePool aggregate accounting events 🟡

- **対象**: `ActivePool.sol`
- **base**: aggregate debt / weighted debt / batch management fee 系 state 更新はイベントを発火しない。→ **DF**: `ActivePoolAggRecordedDebtUpdated`、`ActivePoolAggWeightedDebtSumUpdated`、`ActivePoolAggBatchManagementFeesUpdated`、`ActivePoolAggWeightedBatchManagementFeeSumUpdated` を state 更新直後に発火する。
- **種別**: observability-only event addition。state 更新式・丸め・呼出順は base と同型で、イベントを追加するだけで会計結果は変えない。
- **理由**: ops dashboard / subgraph / audit trail が O(1) 集計 debt と batch fee の変化を追跡できるようにするため。
- **影響範囲**: event ABI と log emission gas。状態変数、会計式、外部呼出権限、返り値には影響しない。
- **規定**: CORE-AP-EVT-* / SYS-NFR-005。

> **差分一覧（要約表）** — 上記の詳細に対する一覧性のための要約。
>
> | ID | 対象ファイル | 差分 | 挙動への影響 |
> | --- | --- | --- | --- |
> | CORE-MOD-001 🟡 | debt-token naming surface | `BoldToken`/`boldToken`/表示名を JPYdf 系へ rename | ABI 名・metadata（ロジック同型） |
> | CORE-MOD-002 🟡 | `Dependencies/Constants.sol` | `MIN_DEBT` 値 | 最小債務・zombie 閾値 |
> | CORE-MOD-003 🟡 | `Dependencies/Constants.sol` | `COLL_GAS_COMPENSATION_CAP` 値 | 清算補償の上限 |
> | CORE-MOD-004 🟡 | `DFStabilityPool.sol`（新規） | SP コピー＋same-block 精算ガード | SP の担保ゲイン払出・出金に block boundary 制約 |
> | CORE-MOD-005 🟢 | `Dependencies/Constants.sol` | DF ブランチ別定数 48 件 + 未参照 fixture 定数削除 | Day-1 deploy の branch params |
> | CORE-MOD-006 🟡 | `BorrowerOperations.sol` / `IBorrowerOperations.sol` | `withdrawBold`/`repayBold` を `withdrawJpydf`/`repayJpydf` に rename | user-facing ABI 名 |
> | CORE-MOD-007 🟡 | `JPYdfTroveNFT.sol` / `IMetadataNFT.sol` / `JPYdfMetadataNFT.sol` / `JPYdfBaseSVG.sol` | JPYdf-branded TroveNFT and metadata deployed surface | product-facing collection / tokenURI rendering のみ |
> | CORE-MOD-008 🟡 | `JpydfToken.sol` / `IJpydfToken` | bridge-ready dormant extension（bridgeAdmin / minter registry / bridgeMint / self-burn bridgeBurn） | additive token ABI・供給権限 surface（Day-1 は minter 0 件） |
> | CORE-MOD-009 🟡 | `JpydfToken.sol` | core address registration hardening（非ゼロ・contract-only） | deploy-time 誤配線を早期 revert |
> | CORE-MOD-010 🟡 | core token transfer / approval call sites | `forceApprove` / `safeTransfer` / `safeTransferFrom` への hardening | token integration 互換性・失敗検出（会計式は同型） |
> | CORE-MOD-011 🟡 | `ActivePool.sol` | aggregate accounting state 更新イベントの追加 | 可観測性のみ（state 更新式は同型） |
>
> **rename を無視した監査上の読み方**: BOLD→JPYdf の識別子・ABI・表示 rename は `CORE-MOD-001/006/007` として interface review 対象にするが、単独では core accounting の再監査理由にしない。`origin/base` との差分レビューでは rename / コメント / import-only cleanup を正規化し、上記 `CORE-MOD-*` 以外の非 rename 差分が出た場合だけ台帳漏れまたは実装逸脱として扱う。
>
> このほかの「Liquity v2 標準とのプロダクトレベルの差」は、コア改変ではなく**外側の与え方**による: 担保＝dToken（[dToken.md](./dToken.md)）、価格＝PriceFeedProxy による JPY 建て合成（[Oracle.md](./Oracle.md)）、Redemption の換算が「1 JPYdf = ¥1 相当の担保」になるのはオラクルが JPY 建て価格を返すことの帰結であり、コアの式は base と同一。

### 2.3 機構の全体像（読み物・非規範）

> 規範は §6 以降。本節は初読者向けの圧縮サマリで、詳細は各 ID を参照。

- **Branch（担保別市場）** — 担保ごとに BorrowerOperations / TroveManager / StabilityPool（DFStabilityPool）/ ActivePool / DefaultPool / CollSurplusPool / GasPool / SortedTroves / TroveNFT / PriceFeed の一式が独立にデプロイされ、AddressesRegistry が配線とリスクパラメータ（MCR/CCR/SCR/BCR/清算ペナルティ＝immutable）を保持する。全ブランチは singleton（JpydfToken / CollateralRegistry / HintHelpers / MultiTroveGetter / DebtInFrontHelper / RedemptionHelper）が束ねる。
- **Trove（借入ポジション）** — 担保を預けて JPYdf を借りる ERC-721（TroveNFT）ポジション。`troveId = keccak256(msg.sender, owner, ownerIndex)`。状態は nonExistent / active / closedByOwner / closedByLiquidation / zombie（CORE-TM）。開設時に `ETH_GAS_COMPENSATION` 相当の WETH を GasPool にロックする（清算実行者へのガス補償原資。担保が dToken でも WETH 建てで固定）。
- **ユーザー設定金利と集計利息** — 借り手は年利を `[MIN_ANNUAL_INTEREST_RATE, MAX_ANNUAL_INTEREST_RATE]` で自由設定する。利息は「加重債務和 × 経過時間」で **O(1)** に集計され（CORE-AP-FR-002）、任意のコア操作時に JPYdf として mint、**75%（`SP_YIELD_SPLIT`）が SP へ、残余 25% が interestRouter へ**配分される（CORE-AP-FR-007。jpydf の DF dToken wiring では `InterestRouterForwarder` に束縛し、最終 recipient / owner は必須 env と handover/verify で管理する。CORE-AP-TBD-001 は解決済み）。
- **Upfront fee / premature adjustment fee** — 新規借入とクールダウン内の金利変更に「ブランチ平均金利 × 7 日分」の手数料を債務に加算し、redemption 回避の極端な低金利設定・直前変更を経済的に抑止する（CORE-BO-FR-001/011、試算は CORE-HH）。
- **Redemption（ペグ下方乖離の自律是正）** — 誰でも JPYdf を「¥1 相当の担保」と交換できる。CollateralRegistry が全ブランチへ unbacked（SP で覆われない債務）比例で配分し（CORE-CR-FR-002）、各ブランチ内では**金利の低い Trove から**充当する（CORE-TM-FR-004）。手数料は `baseRate` のスパイク＋半減期 6h の指数減衰（CORE-CR-FR-003〜006）。償還で `MIN_DEBT` を割った Trove は **zombie** となり SortedTroves から外れる（次回償還は `lastZombieTroveId` を例外的に優先）。
- **清算（3 分岐）** — `ICR < MCR` の Trove を誰でも清算できる（CORE-TM-FR-002）。SP 残高で賄える分は **SP offset**（清算ペナルティ付き担保を SP 預金者へ）、不足分は**同一ブランチの他 Trove へ redistribution**（より高いペナルティ）。SP が薄い時に清算者がその場で JPYdf を SP へ入れて offset を成立させる JIT も可能。実行者は「担保の 0.5%（cap 🟡 CORE-MOD-003）＋ WETH ガス補償」を受け取り、ペナルティ控除後の余剰担保は CollSurplusPool で借り手が claim できる。
- **Stability Pool** — JPYdf を預けて「利息 75% ＋清算担保（ペナルティ分のディスカウント）」を得る。会計は P-S-B の積和スナップショット方式で O(1)（CORE-SP）。**デプロイ実体は DFStabilityPool**（同一ブロック入出金の横取り防止ガード付き 🟡 CORE-MOD-004）。追加報酬（Treasury 由来）はCore外で設計し、[Mainnet Launch Risk Gate](../../launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-003)で未接続時の表示を検査する。
- **安全装置** — 個別清算閾値 MCR ／ ブランチ健全性閾値 CCR（割り込むと新規借入等を制限＝CORE-BO-ERR-001）／ 緊急停止閾値 SCR（`TCR < SCR` で誰でも当該ブランチを**不可逆 shutdown**。オラクル障害でも shutdown）。shutdown 後は利息停止・借入系凍結（closeTrove は可）・**urgent redemption**（手数料 0・担保ボーナス `URGENT_REDEMPTION_BONUS`）で債務を巻き取る（CORE-BO-FR-021/022、CORE-TM-FR-005）。
- **委任** — 入金系（addColl/repay）の AddManager、出金系（withdraw/close）の RemoveManager＋受取先固定、金利調整の Individual Delegate、複数 Trove の金利を束ねる Batch Manager（管理 fee 付き・O(1) 一括変更）を Trove 単位で設定できる（CORE-BO-FR-012〜020 / 025〜027）。

### 2.4 規範スタンス — 「正は base 実装」と本書の使い方

- 🔵 の各要件は、DF が新規に設計した要求ではなく **`base` の実装挙動を記述的に規範化したもの**（descriptive normative）。本書と base 実装が矛盾する場合は **base 実装が正**であり、本書を改訂する（実装を本書に合わせない）。
- 🟡 / 🟢 の要件は DF が設計責任を持つ規範（prescriptive）であり、矛盾時は通常の要件定義と同様に扱う（実装バグか要件改訂かを判断）。
- 本書の ID は (a) parity テスト（§13）、(b) コードの NatSpec `@custom:requirement`、(c) 監査所見・PR レビューから参照される。**ID は append-only・再利用禁止**（[標準](../../../Requirements-Spec-Standard.md)と同一の規約。スコープごとに連番）。
- 仕様の粒度は「関数の外部から観測可能な挙動（状態変化・revert・イベント・返り値）」を基準とし、内部実装の最適化（unchecked 等）は挙動に影響する場合のみ記す。

---

## 3. 用語・外部依存・前提

**用語**（[Product-Overview](../Product-Overview.md) §14 を継承し、コア固有を追加）

| 用語 | 意味 |
| --- | --- |
| `base` | 不変上流参照ブランチ。liquity/bold v1.11.0 を凍結したもの。byte-identity と parity の規範 |
| parity | 「フォーク元と同一に機能すること」。旧 BOLD surface 再混入禁止（Core JPYDF surface guard）・§2.2 台帳 / diff review・挙動同一性（テスト）の組み合わせで検証する（§13） |
| BOLD / JPYdf | 上流 base の概念名は BOLD だが、DF 実装の debt-token 識別子・getter・イベント・metadata は JPYdf 系（`JpydfToken` / `IJpydfToken` / `jpydfToken` 等）へ rename 済み（🟡 CORE-MOD-001）。本書では実装識別子を指すときは JPYdf 系名を使い、上流仕様・base との差分説明では BOLD と書く |
| Branch / ブランチ | 担保 1 種につき一式デプロイされる独立市場（§2.3） |
| Trove | 借入ポジション。`troveId`（uint256）で識別され、所有権は TroveNFT |
| zombie | redemption の結果 `debt < MIN_DEBT` となった Trove の状態。SortedTroves から除外され通常 redemption の対象外（清算・利息・redistribution は継続） |
| batch | Batch Manager が金利を一括管理する Trove の集合。SortedTroves 上では slice（連続区間）として保たれる |
| ICR / TCR | 個別 Trove ／ ブランチ全体の担保比率（価格は PriceFeed が返す JPY 建て） |
| MCR / CCR / SCR / BCR | 清算閾値 ／ クリティカル閾値 ／ shutdown 閾値 ／ batch 加入時の ICR 上乗せバッファ（いずれも branch ごとの immutable。値は [Parameters.md](../../../Parameters.md)） |
| upfront fee | 新規借入・premature 金利変更時に債務へ加算される「平均金利 × `UPFRONT_INTEREST_PERIOD`（7 日）」分の手数料 |
| baseRate | redemption 量に応じてスパイクし指数減衰する system-wide の償還手数料率成分（CollateralRegistry 管理） |
| offset / redistribution | 清算債務の SP 相殺 ／ 同一ブランチ他 Trove への按分転嫁 |
| P, S, B | SP の積和会計トラッカー（預金減耗積 P・担保ゲイン和 S・利回りゲイン和 B） |
| `ETH_GAS_COMPENSATION` | Trove 開設時に WETH でロックする清算ガス補償（担保種別によらず WETH 建て） |
| interestRouter | 集計利息の残余 25% の送付先（immutable。DF dToken wiring では `InterestRouterForwarder`。CORE-AP-TBD-001 は解決済み） |

**外部依存（コアが信頼する外部）**

| 依存 | コアからの見え方 | DF での実体 |
| --- | --- | --- |
| 担保 ERC-20（`collToken`） | ごく普通の 18dec ERC-20。`transfer`/`transferFrom` が標準どおり成功・失敗する | dToken（[dToken.md](./dToken.md)）。fee-on-transfer / rebasing でないことを dToken 側が保証 |
| 価格フィード（`priceFeed`） | `fetchPrice()` / `fetchRedemptionPrice()` が「担保 1 unit の JPY 建て価格（18dec）」と oracle 健全性フラグを返す | PriceFeedProxy（[Oracle.md](./Oracle.md)）。障害時は `shutdownFromOracleFailure` を呼ぶ責務を持つ |
| WETH | ガス補償のロック・返還・支払いに使う ERC-20 | canonical WETH9 |
| OpenZeppelin v4.9.5 | ERC20Permit（JpydfToken）・ERC721（TroveNFT）等の標準実装 | lib（バージョン固定） |

**前提**

- コアは Ethereum mainnet 単一チェーン・8 ブランチ構成でデプロイされる（[Parameters.md](../../../Parameters.md) §1）。
- コア・JpydfToken は **non-upgradeable**。branch リスクパラメータと配線はデプロイ後変更不能（§10）。
- 価格・担保の信頼性はコアの外（Oracle / dToken レイヤー）で担保される。コアはそれらを所与として動く。

---

## 4. アクター・ロール・信頼境界

**外部アクター**

| アクター | 主な操作 | 信頼 |
| --- | --- | --- |
| Borrower（Trove owner） | openTrove / 調整 / closeTrove / claimCollateral / 委任設定 | 敵対前提（permissionless。検査とインセンティブで整合） |
| AddManager / RemoveManager / receiver | 入金系操作 ／ 出金系操作（受取先は receiver 固定可） | owner が選任（CORE-BO-SEC-001/002） |
| Individual Delegate / Batch Manager | 金利調整 ／ batch 金利・fee 管理 | owner が選任。レート範囲・変更間隔で制限 |
| SP depositor | provideToSP / withdrawFromSP / claimAllCollGains | 敵対前提（🟡 same-block ガード＝CORE-MOD-004） |
| Redeemer | CollateralRegistry.redeemCollateral（RedemptionHelper 経由を含む） | 敵対前提（手数料・ルーティングで整合） |
| Liquidator | batchLiquidateTroves / urgentRedemption | 敵対前提（補償で誘引） |
| 任意の第三者 | shutdown（TCR<SCR 時）/ kickFromBatch / applyPendingDebt 等の状態条件付き permissionless 操作 | 敵対前提（CORE-BO-SEC-005） |
| Deployer | デプロイ・配線（AddressesRegistry.setAddresses / JpydfToken.setBranchAddresses 等） | **配線完了と同時に owner を放棄**し、以後の特権は消滅（§10） |
| bridgeAdmin | bridge minter の提案・取消・削除・admin 移譲 | Core owner と独立。Day-1 は minter 0 件・pending なしを launch gate とする |
| bridge minter | `bridgeMint` / self-burn 型 `bridgeBurn` | Day-1 は存在しない。Day-2 以降に登録する場合は完全信頼 bridge adapter として扱う |

**コントラクト間信頼境界（only-X 呼出グラフの要約）** — 規範は各 SEC。

| 呼出先 ← 呼出元 | 制限 |
| --- | --- |
| TroveManager の `on*` フック ← BorrowerOperations のみ | CORE-TM-SEC-001 |
| TroveManager.redeemCollateral ← CollateralRegistry のみ | CORE-TM-SEC-002 |
| BorrowerOperations.onLiquidateTrove ← TroveManager のみ | CORE-BO-SEC-003 |
| BorrowerOperations.shutdownFromOracleFailure ← priceFeed のみ | CORE-BO-SEC-003 |
| StabilityPool.offset ← TroveManager のみ ／ triggerJpydfRewards ← ActivePool のみ | CORE-SP-SEC-001/002 |
| ActivePool の資金・会計操作 ← BO / TM / SP（関数ごとに限定） | CORE-AP-SEC-001 |
| DefaultPool ← ActivePool / TroveManager のみ | CORE-DP-SEC-001 |
| CollSurplusPool.accountSurplus ← TM ／ claimColl ← BO | CORE-CSP-SEC-001 |
| SortedTroves の書込 ← BO / TM のみ | CORE-ST-SEC-001 |
| TroveNFT.mint/burn ← TroveManager のみ | CORE-TN-SEC-001 |
| JpydfToken.mint ← BO / AP のみ。burn ← CR / 登録済み BO・TM・SP。sendToPool/returnFromPool ← SP のみ。bridgeMint/bridgeBurn ← 登録済み bridge minter のみ | CORE-BT-SEC-001 / CORE-BT-SEC-004 |

- コアは **dToken の中身（Underlying・Strategy 運用）を知らず**、`collToken` の ERC-20 面だけを信頼する（[Product-Overview](../Product-Overview.md) ARCH-002/003）。dToken の裏付け毀損は価格（backing 比の乗算）として伝わり、コアの清算・shutdown 機構で処理される。
- **再入面**: コアは外部トークンとして collToken（dToken）・WETH・JPYdf のみに触れ、いずれも転送フックを持たない前提（dToken 側で保証）。コア内に nonReentrant guard は存在せず、CEI 順序と呼出元制限が再入防御の根拠（各 SEC）。

---

## 5. コントラクト構成・インターフェース仕様

### 5.1 コントラクトカタログ（コア全体）

コアを構成する全コントラクトと本書の ID スコープ。**デプロイ単位**: branch＝担保ブランチごとに 1 つ ／ singleton＝システムに 1 つ。

| コントラクト | デプロイ単位 | マーカー | ID スコープ | 概要 |
| --- | --- | --- | --- | --- |
| BorrowerOperations | branch | 🔵 | `CORE-BO-*` | 借り手・委任者の操作の単一エントリポイント |
| TroveManager | branch | 🔵 | `CORE-TM-*` | Trove 状態台帳・清算・redemption・shutdown |
| StabilityPool（規範）/ **DFStabilityPool（デプロイ実体）** | branch | 🔵/🟡 | `CORE-SP-*` | 清算オフセット原資の JPYdf 預金プール（🟡 CORE-MOD-004） |
| ActivePool | branch | 🔵 | `CORE-AP-*` | アクティブ担保・集計債務・利息 mint の中心会計 |
| DefaultPool | branch | 🔵 | `CORE-DP-*` | redistribution 待ち担保・債務の保管庫 |
| CollSurplusPool | branch | 🔵 | `CORE-CSP-*` | 清算余剰担保の請求権保管庫 |
| GasPool | branch | 🔵 | `CORE-GP-*` | WETH ガス補償のロック保管庫 |
| SortedTroves | branch | 🔵 | `CORE-ST-*` | 金利降順の双方向連結リスト（redemption 順序の基盤） |
| **JPYdfTroveNFT deployed surface**（＋`IMetadataNFT` / **JPYdfMetadataNFT**） | branch | 🔵/🟡 | `CORE-TN-*` | Trove 所有権 ERC-721・on-chain メタデータ（🟡 CORE-MOD-007 は product-facing collection / tokenURI rendering） |
| JpydfToken | singleton | 🔵/🟡 | `CORE-BT-*` | 債務トークン JPYdf。規範は [JpydfToken.md](./JpydfToken.md)（🟡 CORE-MOD-001 命名 / CORE-MOD-008 bridge-ready / CORE-MOD-009 hardening） |
| CollateralRegistry | singleton | 🔵 | `CORE-CR-*` | branch 横断 redemption の入口・baseRate 管理 |
| AddressesRegistry | branch | 🔵 | `CORE-AR-*` | 配線と immutable リスクパラメータの保持 |
| HintHelpers | singleton | 🔵 | `CORE-HH-*` | hint 探索・upfront fee 試算 view |
| MultiTroveGetter | singleton | 🔵 | `CORE-MTG-*` | Trove 一括取得 view |
| DebtInFrontHelper | singleton | 🔵 | `CORE-DFH-*` | debt-in-front（redemption リスク）計算 view |
| RedemptionHelper | singleton | 🔵 | `CORE-RH-*` | redemption のスリッページ保護ラッパー・シミュレーション |
| LiquidationCandidateGetter | singleton | 🟢 | `CORE-LCG-*` | 清算候補のページング走査 view（DF 追加） |
| Dependencies（Constants / LiquityBase / LiquityMath / Ownable）・Types | （ライブラリ/基底） | 🔵（一部 🟡/🟢） | `CORE-LIB-*` | 定数（🟡 CORE-MOD-002/003・🟢 005）・共通会計・数学・型 |

**production `src` に残る周辺 surface / カタログ扱いのファイル**（旧 BOLD surface の再混入は Core JPYDF surface guard が検出）:

| パス | 扱い |
| --- | --- |
| `PriceFeeds/`（upstream 系: CompositePriceFeed / MainnetPriceFeedBase） | DF ブランチのオラクルは DF 実装（PriceFeedProxy ＋ DF*PriceFeed）を用いる。規範は [Oracle.md](./Oracle.md)。deploy されない upstream WETH wrapper と、Day-1 で使わない WSTETH / RETH collateral feed は production `src` から削除済み。`CompositePriceFeed` も sUSDS 用の primary → `lastGoodPrice` 経路に pruning 済みで、WSTETH/RETH 用 LST secondary fallback は残さない |
| `Zappers/`（DF 追加 Zapper + 必要 interface/module） | DF の Zapper 要件は [Zapper.md](./Zapper.md)。WETH / GasComp / Leverage 系 upstream-derived Zapper と legacy Curve / Hybrid / Uniswap v3 exchange adapter surface は Day-1 方針から外れたため production `src` から削除済み。mainnet 配線の正本は deployment 資料 |
| `Interfaces/`（現行 protocol surface の IF） | 各コントラクトの規定 IF は §5 の該当節で扱う。未使用の upstream LQTY / BOLD IF（`ILQTYToken` / `ILQTYStaking` / `ICommunityIssuance` / `IBoldToken` / `IBoldRewardsReceiver`）は、未使用分を削除し、debt-token surface は `IJpydfToken` / `IJpydfRewardsReceiver` へ置換済み。Day-1 deploy / test path から V2-gov / LQTY staking surface は削除済みで、`contracts/lib/V2-gov` は vendored dependency tree として規範対象に含めない。未使用の WSTETH / RETH price feed IF も production `src` から削除済み |
| `NFTMetadata/utils/`（SVG / JSON / JPYdfBaseSVG / bauhaus / FixedAssets / Utils） | TroveNFT 節（CORE-TN-FR-006）で catalog 扱い。未deployの upstream `baseSVG.sol` は削除済み |

> **網羅（取りこぼし無しの確認）**: `base`（liquity/bold v1.11.0・凍結）の `contracts/src` は **102** ファイル（内訳: ルート 16 / `Dependencies` 6 / `Types` 5 / `Interfaces` 31 / `NFTMetadata` 7 / `PriceFeeds` 5 / `Zappers` 32）である。現行 `contracts/src` は **97** Solidity ファイル（ルート 21 / `Dependencies` 6 / `Types` 4 / `Interfaces` 30 / `NFTMetadata` 7 / `PriceFeeds` 11 / `Zappers` 11 / `Strategies` 7、`README.md` は除外）。path 単位の差分は、BOLD/LQTY 命名 surface と legacy Curve / Hybrid / Uniswap v3 exchange surface、WETH / GasComp / Leverage upstream Zapper surface、WETH / WSTETH / RETH collateral feed surface、未deploy upstream NFT renderer surface、未参照 `Types/TroveId.sol` helper などの削除・置換、および JPYdf token / dToken / CollateralVault / Strategy 群 / DF Oracle / Uniswap v4 / Sky / CollateralYieldZapper / `IMetadataNFT` interface 抽出などの追加・置換で構成される。本書が規範化するコア（ルートのコアコントラクト＋ `Dependencies` / `Types` ＝ `CORE-*` / `CORE-LIB-*`）、DF Oracle / Zapper / NFT deployed surface、および必要 interface に分かれ、未計上は無い。`contracts/` 配下の `test` / `script` / `certora` はいずれの spec の規範対象でもない（テスト・デプロイ・形式検証）。

> 以降の各節は、コントラクトごとに「概要＋インターフェース一覧（非規範）」を示す。挙動の規範は §6 機能要件。

### BorrowerOperations（借り手操作の単一エントリポイント） 🔵

BorrowerOperations（以下 BO）は、借り手（および借り手が委任した manager / delegate）が Trove を操作するための唯一のエントリポイント。担保ブランチごとに 1 つデプロイされ、AddressesRegistry 経由で同一ブランチの TroveManager / ActivePool / DefaultPool / SortedTroves / CollSurplusPool / GasPool / TroveNFT / JpydfToken / PriceFeed と配線される。`LiquityBase`（ブランチ合計の coll/debt 取得・TCR 計算）と `AddRemoveManagers`（Trove 単位の操作委任: AddManager / RemoveManager / receiver）を継承し、本節は AddRemoveManagers の継承面（`setAddManager` / `setRemoveManager` / `setRemoveManagerWithReceiver` / `addManagerOf` / `removeManagerReceiverOf`）も BO スコープとして規定する。

責務は「入力検証と健全性検査（ICR/TCR/MIN_DEBT/upfront fee）を行ったうえで、状態更新を TroveManager のフック（`onOpenTrove` / `onAdjustTrove` 等）と ActivePool の集計（`mintAggInterestAndAccountForTroveChange`）に指示し、トークン移転（担保 = dToken・JPYdf mint/burn・WETH ガス補償）を実行する」こと。Trove の状態そのもの（coll/debt/金利の記録、NFT、batch の shares 会計）は TroveManager（CORE-TM 系）が保持する。担保トークンはこのブランチの dToken（[dToken.md](./dToken.md)）、価格取得は PriceFeedProxy（[Oracle.md](./Oracle.md)）への `fetchPrice()` 呼出で行う。

本コントラクト（AddRemoveManagers 含む）は base と byte-identical（🔵）。ただし参照する定数 `MIN_DEBT` の値は DF が変更している（🟡 CORE-MOD-002 / CORE-LIB-FR-002）。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `openTrove(address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,address,address) → uint256` | external ｜ permissionless | 新規 Trove 開設（単独金利） | CORE-BO-FR-001 |
| `openTroveAndJoinInterestBatchManager(OpenTroveAndJoinInterestBatchManagerParams) → uint256` | external ｜ permissionless | 新規 Trove 開設＋batch 同時加入 | CORE-BO-FR-002 |
| `adjustTrove(uint256,uint256,bool,uint256,bool,uint256)` | external ｜ owner / managers（変更方向による） | 担保・債務の複合調整 | CORE-BO-FR-003 |
| `addColl(uint256,uint256)` | external ｜ owner / AddManager 系 | 担保追加 | CORE-BO-FR-004 |
| `withdrawColl(uint256,uint256)` | external ｜ owner / RemoveManager | 担保引出 | CORE-BO-FR-005 |
| `withdrawJpydf(uint256,uint256,uint256)` | external ｜ owner / RemoveManager | 追加借入（JPYdf mint） | CORE-BO-FR-006 |
| `repayJpydf(uint256,uint256)` | external ｜ owner / AddManager 系 | 返済（JPYdf burn） | CORE-BO-FR-007 |
| `adjustZombieTrove(uint256,uint256,bool,uint256,bool,uint256,uint256,uint256)` | external ｜ owner / managers（変更方向による） | zombie Trove の調整と active 復帰 | CORE-BO-FR-008 |
| `closeTrove(uint256)` | external ｜ owner / RemoveManager | Trove 閉鎖（全額返済） | CORE-BO-FR-009 |
| `applyPendingDebt(uint256,uint256,uint256)` | public ｜ permissionless | 利息・再分配・batch fee の記録値への確定 | CORE-BO-FR-010 |
| `adjustTroveInterestRate(uint256,uint256,uint256,uint256,uint256)` | external ｜ owner / 個別 interest delegate | 単独 Trove の金利変更 | CORE-BO-FR-011 |
| `setInterestIndividualDelegate(uint256,address,uint128,uint128,uint256,uint256,uint256,uint256,uint256)` | external ｜ owner | 個別 interest delegate の設定 | CORE-BO-FR-012 |
| `removeInterestIndividualDelegate(uint256)` | external ｜ owner | 個別 interest delegate の解除 | CORE-BO-FR-013 |
| `registerBatchManager(uint128,uint128,uint128,uint128,uint128)` | external ｜ permissionless（自己登録） | batch manager の登録 | CORE-BO-FR-014 |
| `setBatchManagerAnnualInterestRate(uint128,uint256,uint256,uint256)` | external ｜ 登録済み batch manager | batch 一括金利変更 | CORE-BO-FR-015 |
| `lowerBatchManagementFee(uint256)` | external ｜ 登録済み batch manager | batch 管理 fee の引下げ | CORE-BO-FR-016 |
| `setInterestBatchManager(uint256,address,uint256,uint256,uint256)` | public ｜ owner | 既存 Trove の batch 加入 | CORE-BO-FR-017 |
| `removeFromBatch(uint256,uint256,uint256,uint256,uint256)` | public ｜ owner | batch からの離脱（金利を自己設定へ） | CORE-BO-FR-018 |
| `kickFromBatch(uint256,uint256,uint256)` | external ｜ permissionless | shares ratio が劣化した batch からの強制退去 | CORE-BO-FR-019 |
| `switchBatchManager(uint256,uint256,uint256,address,uint256,uint256,uint256)` | external ｜ owner | batch の乗り換え（離脱＋加入） | CORE-BO-FR-020 |
| `shutdown()` | external ｜ permissionless | TCR < SCR 時のブランチ shutdown | CORE-BO-FR-021 |
| `shutdownFromOracleFailure()` | external ｜ PriceFeed のみ | oracle 失敗時の shutdown | CORE-BO-FR-022 |
| `onLiquidateTrove(uint256)` | external ｜ TroveManager のみ | 清算時の BO 側マッピング消去 | CORE-BO-FR-023 |
| `claimCollateral()` | external ｜ permissionless | 清算余剰担保の引出（CollSurplusPool へ委譲） | CORE-BO-FR-024 |
| `setAddManager(uint256,address)` | external ｜ owner | AddManager の設定（AddRemoveManagers 継承） | CORE-BO-FR-025 |
| `setRemoveManagerWithReceiver(uint256,address,address)` | public ｜ owner | RemoveManager＋receiver の設定（同上） | CORE-BO-FR-026 |
| `setRemoveManager(uint256,address)` | external ｜ owner | RemoveManager の設定（receiver=owner、同上） | CORE-BO-FR-027 |
| `CCR() → uint256` | public view | クリティカル閾値 CCR（immutable） | CORE-BO-FR-028 |
| `SCR() → uint256` | public view | shutdown 閾値 SCR（immutable） | CORE-BO-FR-028 |
| `MCR() → uint256` | public view | 個別 Trove 最低担保率（immutable） | CORE-BO-FR-028 |
| `BCR() → uint256` | public view | batch 所属 Trove の追加バッファ（immutable） | CORE-BO-FR-028 |
| `hasBeenShutDown() → bool` | public view | shutdown 済みフラグ | CORE-BO-FR-028 |
| `interestBatchManagerOf(uint256) → address` | public view | Trove の所属 batch manager | CORE-BO-FR-028 |
| `getInterestBatchManager(address) → InterestBatchManager` | external view | batch manager 登録レコード | CORE-BO-FR-028 |
| `getInterestIndividualDelegateOf(uint256) → InterestIndividualDelegate` | external view | 個別 interest delegate レコード | CORE-BO-FR-028 |
| `checkBatchManagerExists(address) → bool` | external view | batch manager 登録済み判定 | CORE-BO-FR-028 |
| `addManagerOf(uint256) → address` | public view（自動 getter） | AddManager 照会（AddRemoveManagers 継承） | CORE-BO-FR-028 |
| `removeManagerReceiverOf(uint256) → (address,address)` | public view（自動 getter） | RemoveManager と receiver の照会（同上） | CORE-BO-FR-028 |
| `activePool() → address` | public view | ActivePool 参照（LiquityBase 継承。規定は LIB 担当） | CORE-BO-FR-028 |
| `getEntireBranchColl() → uint256` | public view | ブランチ総担保（AP+DP。LiquityBase 継承） | CORE-BO-FR-028 |
| `getEntireBranchDebt() → uint256` | public view | ブランチ総債務（AP+DP。LiquityBase 継承） | CORE-BO-FR-028 |


### TroveManager（Trove 状態台帳・清算・Redemption の中核） 🔵

TroveManager は担保ブランチごとに 1 つデプロイされる、Trove の状態台帳と清算・Redemption の実行エンジン。ユーザー向けエントリポイントは持たず、(1) 誰でも呼べる清算 `batchLiquidateTroves` と shutdown 後の `urgentRedemption`、(2) CollateralRegistry のみが呼ぶ `redeemCollateral`、(3) BorrowerOperations のみが呼ぶ `on*` コールバック群・`shutdown`・`setTroveStatusToActive` の 3 系統で構成される。Trove 構造体・Batch 構造体・redistribution 会計（`L_coll` / `L_jpydfDebt` / `rewardSnapshots` / `totalStakes`）を保持し、利息込みの最新 Trove/Batch 状態（`LatestTroveData` / `LatestBatchData`）を導出して BorrowerOperations・HintHelpers 等に提供する。資金移動は ActivePool / DefaultPool / StabilityPool / CollSurplusPool / GasPool を介して行い、自身はトークンを保持しない。担保トークンは dToken（[dToken.md](./dToken.md)）、価格取得（`fetchPrice` / `fetchRedemptionPrice`）は PriceFeedProxy（[Oracle.md](./Oracle.md)）に委ねる。債務トークンは JpydfToken（DF では JPYdf。[JpydfToken.md](./JpydfToken.md)）。Trove の所有権は TroveNFT（ERC-721）が表現し、開設時 mint・終了時 burn を TroveManager が指示する。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `batchLiquidateTroves(uint256[])` | external（permissionless） | 指定 Trove 群のうち ICR < MCR のものを清算 | CORE-TM-FR-001 / 002 / 003 |
| `redeemCollateral(address,uint256,uint256,uint256,uint256) → uint256` | external（onlyCollateralRegistry） | 通常 Redemption（APR 昇順走査） | CORE-TM-FR-004 |
| `urgentRedemption(uint256,uint256[],uint256)` | external（permissionless・shutdown 後のみ） | shutdown 後の緊急 Redemption（ボーナス付き） | CORE-TM-FR-005 |
| `shutdown()` | external（onlyBorrowerOperations） | ブランチ shutdown の記録と ActivePool への伝播 | CORE-TM-FR-006 |
| `getUnbackedPortionPriceAndRedeemability() → (uint256,uint256,bool)` | external（**nonpayable**・permissionless） | 非裏付け債務・価格・redeem 可否（`fetchPrice` を呼ぶため view ではない） | CORE-TM-FR-012 |
| `getCurrentICR(uint256,uint256) → uint256` | public view | redistribution・利息込みの現在 ICR | CORE-TM-FR-008 |
| `getLatestTroveData(uint256) → LatestTroveData` | external view | 利息・redistribution 込みの最新 Trove 状態 | CORE-TM-FR-009 |
| `getLatestBatchData(address) → LatestBatchData` | external view | 利息・管理fee込みの最新 Batch 状態 | CORE-TM-FR-010 |
| `getTroveAnnualInterestRate(uint256) → uint256` | external view | Trove の実効年利（batch 所属なら batch 金利） | CORE-TM-FR-011 |
| `onOpenTrove(address,uint256,TroveChange,uint256)` | external（onlyBorrowerOperations） | Trove 開設の状態記録 | CORE-TM-FR-014 |
| `onOpenTroveAndJoinBatch(address,uint256,TroveChange,address,uint256,uint256)` | external（onlyBorrowerOperations） | batch 加入付き Trove 開設 | CORE-TM-FR-015 |
| `setTroveStatusToActive(uint256)` | external（onlyBorrowerOperations） | zombie Trove の active 復帰 | CORE-TM-FR-016 |
| `onAdjustTrove(uint256,uint256,uint256,TroveChange)` | external（onlyBorrowerOperations） | Trove 調整の状態記録 | CORE-TM-FR-017 |
| `onAdjustTroveInterestRate(uint256,uint256,uint256,uint256,TroveChange)` | external（onlyBorrowerOperations） | 個別金利変更の状態記録 | CORE-TM-FR-018 |
| `onAdjustTroveInsideBatch(uint256,uint256,uint256,TroveChange,address,uint256,uint256)` | external（onlyBorrowerOperations） | batch 内 Trove 調整 | CORE-TM-FR-019 |
| `onApplyTroveInterest(uint256,uint256,uint256,address,uint256,uint256,TroveChange)` | external（onlyBorrowerOperations） | 未収利息・redistribution の適用記録 | CORE-TM-FR-020 |
| `onCloseTrove(uint256,TroveChange,address,uint256,uint256)` | external（onlyBorrowerOperations） | Trove 閉鎖（closedByOwner） | CORE-TM-FR-021 |
| `onRegisterBatchManager(address,uint256,uint256)` | external（onlyBorrowerOperations） | batch manager 登録 | CORE-TM-FR-022 |
| `onLowerBatchManagerAnnualFee(address,uint256,uint256,uint256)` | external（onlyBorrowerOperations） | batch 管理fee引き下げ | CORE-TM-FR-023 |
| `onSetBatchManagerAnnualInterestRate(address,uint256,uint256,uint256,uint256)` | external（onlyBorrowerOperations） | batch 金利変更 | CORE-TM-FR-024 |
| `onSetInterestBatchManager(OnSetInterestBatchManagerParams)` | external（onlyBorrowerOperations） | 既存 Trove の batch 加入 | CORE-TM-FR-025 |
| `onRemoveFromBatch(uint256,uint256,uint256,TroveChange,address,uint256,uint256,uint256)` | external（onlyBorrowerOperations） | Trove の batch 離脱 | CORE-TM-FR-026 |
| `CCR() → uint256` | public view（immutable getter） | ブランチの CCR | CORE-TM-FR-013 |
| `Troves(uint256) → (uint256,uint256,uint256,uint8,uint64,uint64,uint64,uint256,address,uint256)` | public view | Trove 構造体の生値（pending 未反映） | CORE-TM-FR-013 |
| `rewardSnapshots(uint256) → (uint256,uint256)` | public view | Trove の L_coll / L_jpydfDebt スナップショット | CORE-TM-FR-013 |
| `batchIds(uint256) → address` | public view | batch manager アドレス配列 | CORE-TM-FR-013 |
| `lastZombieTroveId() → uint256` | public view | 直近の部分 redeem 済み zombie Trove ポインタ | CORE-TM-FR-013 |
| `shutdownTime() → uint256` | public view | shutdown 時刻（0 = 未 shutdown） | CORE-TM-FR-013 |
| `getTroveIdsCount() → uint256` | external view | TroveIds 配列長 | CORE-TM-FR-013 |
| `getTroveFromTroveIdsArray(uint256) → uint256` | external view | TroveIds 配列の index アクセス | CORE-TM-FR-013 |
| `getTroveStatus(uint256) → Status (uint8)` | external view | Trove の Status | CORE-TM-FR-013 |
| `troveNFT() → address` | public view | 接続先 TroveNFT | CORE-TM-FR-013 |
| `borrowerOperations() → address` | public view | 接続先 BorrowerOperations | CORE-TM-FR-013 |
| `stabilityPool() → address` | public view | 接続先 StabilityPool | CORE-TM-FR-013 |
| `sortedTroves() → address` | public view | 接続先 SortedTroves | CORE-TM-FR-013 |
| `activePool() → address` | public view（LiquityBase 継承） | 接続先 ActivePool | CORE-TM-FR-013 |
| `getEntireBranchColl() → uint256` | public view（LiquityBase 継承） | ActivePool + DefaultPool の担保合計 | CORE-TM-FR-013 |
| `getEntireBranchDebt() → uint256` | public view（LiquityBase 継承） | ActivePool + DefaultPool の債務合計 | CORE-TM-FR-013 |

（ABI 全 38 関数。`MCR` / `SCR` / `LIQUIDATION_PENALTY_*` は internal immutable のため getter なし）


### StabilityPool / DFStabilityPool（清算オフセットを吸収する JPYdf 預金プール） 🔵/🟡

StabilityPool（SP）は、預金者が預け入れた JPYdf を保有し、清算時に TroveManager からの `offset` で清算 Trove の debt を預金で相殺（JPYdf 焼却）し、引き換えに清算担保（dToken、[dToken.md](./dToken.md)）を預金者へ比例配分するプール。加えて、Trove 利息のうち `SP_YIELD_SPLIT`（75%。値は §7）分の JPYdf 利回りを ActivePool 経由で受け取り、預金者へ配分する。branch ごとに 1 つデプロイされる。

会計は O(1) の Product-Sum 方式: 清算ごとに全預金者の残高を書き換える代わりに、running product `P`（預金の減耗率）と P 加重 running sum `S`（担保ゲイン）・`B`（利回りゲイン）のみを更新する。預金者は預入時のスナップショット（`P_t`, `S_t`, `B_t`, `scale_t`）と現在値の差分から、複利後預金・累積ゲインを O(1) で導出する（導出は upstream の論文 *Scalable Reward Distribution with Compounding Stakes* に基づく）。`P` の床除算による 0 到達を防ぐため、`P` が `P_PRECISION / SCALE_FACTOR` を下回る前に `SCALE_FACTOR` 倍して `currentScale` を繰り上げる scale 機構を持つ。

**二重構造（最重要）**: `StabilityPool.sol` は JPYdf canonical surface rename 後の behavior-parity 規範対象として温存される。一方、**実際にデプロイされる SP は `DFStabilityPool.sol`**（🟡 CORE-MOD-004（§2 DF 差分台帳））である。DFStabilityPool は StabilityPool の全文コピーに、(1) 状態変数 `lastDepositBlock`、(2) `provideToSP` の same-block 担保ゲイン claim ガード、(3) `provideToSP` での記録、(4) `withdrawFromSP` 冒頭の same-block 出金ガード、の 4 点のみを追加したもの（rename を除く機能差分はこの 4 点に限る）。本節の規範本文（🔵）は StabilityPool の挙動を記述し、DF 差分は CORE-SP-FR-004 および各 FR の「Base との差分」注記に隔離する。ABI は `lastDepositBlock(address)` の追加を除き両者同一。

主な相互作用: TroveManager（`offset` の唯一の呼出元）/ ActivePool（預金者操作時に `mintAggInterest` を呼出し、`triggerJpydfRewards` を受信、`sendColl` で清算担保を受領）/ JpydfToken（`sendToPool` / `returnFromPool` / `burn`）/ collToken=dToken（ゲイン払出の `safeTransfer`）。SP 自身は PriceFeed を呼ばない（LiquityBase の `priceFeed` は保持するが未使用）。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `provideToSP(uint256 _topUp, bool _doClaim)` | external（permissionless） | JPYdf 預入・トップアップ。ゲインの claim/stash 同時精算 | CORE-SP-FR-002 |
| `withdrawFromSP(uint256 _amount, bool _doClaim)` | external（要・既存預金） | JPYdf 引出（`_amount=0` でゲイン精算のみも可）。事後に `MIN_JPYDF_IN_SP` 検査 | CORE-SP-FR-003 |
| `claimAllCollGains()` | external（要・預金ゼロ） | 預金 0 の利用者が stash 済み担保ゲインを請求 | CORE-SP-FR-005 |
| `triggerJpydfRewards(uint256 _jpydfYield)` | external（onlyActivePool） | 利息由来 JPYdf 利回りの配分計上（`B` 更新 / pending 積み増し） | CORE-SP-FR-006 |
| `offset(uint256 _debtToOffset, uint256 _collToAdd)` | external（onlyTroveManager） | 清算オフセット: `S`/`P` 更新・scale 処理・JPYdf 焼却・担保受入 | CORE-SP-FR-007 |
| `getDepositorCollGain(address)` | public view | 未精算担保ゲインの計算（scale 跨ぎ対応） | CORE-SP-FR-008 |
| `getDepositorYieldGain(address)` | public view | 未精算 JPYdf 利回りゲインの計算（scale 跨ぎ対応） | CORE-SP-FR-009 |
| `getDepositorYieldGainWithPending(address)` | external view | 未 mint 利息（pending SP yield）込みの利回り見積 | CORE-SP-FR-010 |
| `getCompoundedJpydfDeposit(address)` | public view | 複利後（清算減耗後）預金額の計算 | CORE-SP-FR-011 |
| `getCollBalance()` | external view | 担保の内部トラッカー `collBalance` | CORE-SP-FR-012 |
| `getTotalJpydfDeposits()` | external view | 預金総額トラッカー `totalJpydfDeposits` | CORE-SP-FR-012 |
| `getYieldGainsOwed()` | external view | 配分計上済み・未払いの利回り総額 | CORE-SP-FR-012 |
| `getYieldGainsPending()` | external view | 未配分（pending）の利回り総額 | CORE-SP-FR-012 |
| `deposits(address) → uint256` | public view（自動生成） | 預金者の `initialValue`（最終操作時点の預金額） | CORE-SP-FR-012 |
| `depositSnapshots(address) → (uint256 S, uint256 P, uint256 B, uint256 scale)` | public view（自動生成） | 預金者のスナップショット | CORE-SP-FR-012 |
| `stashedColl(address) → uint256` | public view（自動生成） | stash（未送金で留保）された担保ゲイン | CORE-SP-FR-012 |
| `P()` | public view（自動生成） | running product 現在値 | CORE-SP-FR-012 |
| `currentScale()` | public view（自動生成） | 現在の scale | CORE-SP-FR-012 |
| `scaleToS(uint256)` / `scaleToB(uint256)` | public view（自動生成） | scale 別の累積和 S / B | CORE-SP-FR-012 |
| `NAME()` / `P_PRECISION()` / `SCALE_FACTOR()` / `MAX_SCALE_FACTOR_EXPONENT()` / `SCALE_SPAN()` | public view（定数 getter） | コントラクト定数 | CORE-SP-FR-012 |
| `collToken()` / `troveManager()` / `jpydfToken()` | public view（immutable getter） | 配線アドレス | CORE-SP-FR-012 |
| `activePool()` | public view（LiquityBase 継承） | ActivePool アドレス | CORE-SP-FR-012 |
| `getEntireBranchColl()` / `getEntireBranchDebt()` | public view（LiquityBase 継承） | branch 全体の担保・債務合計 | CORE-SP-FR-013 |
| `lastDepositBlock(address) → uint256` 🟡 | public view（自動生成。**DFStabilityPool のみ**） | 預金者の最終預入ブロック番号 | CORE-SP-FR-004 |


### ActivePool（アクティブ Trove の担保・集計負債の中心会計）🔵

ActivePool は、ブランチごとにデプロイされ、アクティブな全 Trove の担保（collToken = dToken、[dToken.md](./dToken.md)）と、ブランチ全体の JPYdf 建て集計負債を保持する会計コントラクト。Liquity v2 の利息モデルの中核であり、Trove ごとに利息を都度 mint する代わりに、**利率加重負債和（aggWeightedDebtSum, "S"）から集計ペンディング利息を線形計算し、任意の状態変更操作のタイミングでまとめて JPYdf を mint する「集計利息会計」**を実装する。mint した利息（＋upfront fee）は `SP_YIELD_SPLIT`（75%）が StabilityPool へ（`triggerJpydfRewards` で通知）、残余 25% が `interestRouter` へ分配される。batch management fee も同型の集計会計（aggBatchManagementFees / aggWeightedBatchManagementFeeSum）で処理する。

清算時には担保・負債が StabilityPool（offset 分）／ DefaultPool（redistribution 分）へ移転され、redemption・担保引出では担保が受領者へ直接送付される。ブランチ shutdown 時は TroveManager 経由で `shutdownTime` が記録され、以後の集計利息の累積が恒久停止する。

すべての状態変更関数は BorrowerOperations / TroveManager / StabilityPool / DefaultPool に呼出元を限定しており、permissionless な状態変更面を持たない。アドレス配線はコンストラクタで AddressesRegistry から取得し、全て immutable。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `NAME() → string` | external view（public constant） | コントラクト名 `"ActivePool"` | CORE-AP-FR-015 |
| `collToken() → address` | external view（public immutable） | ブランチ担保トークン（dToken） | CORE-AP-FR-015 |
| `borrowerOperationsAddress() → address` | external view（public immutable） | BorrowerOperations アドレス | CORE-AP-FR-015 |
| `troveManagerAddress() → address` | external view（public immutable） | TroveManager アドレス | CORE-AP-FR-015 |
| `defaultPoolAddress() → address` | external view（public immutable） | DefaultPool アドレス | CORE-AP-FR-015 |
| `jpydfToken() → address` | external view（public immutable） | JpydfToken（JPYdf）アドレス | CORE-AP-FR-015 |
| `interestRouter() → address` | external view（public immutable） | 利息残余 25% の送付先（DF dToken wiring では `InterestRouterForwarder`） | CORE-AP-FR-015 / CORE-AP-TBD-001 |
| `stabilityPool() → address` | external view（public immutable） | SP（`IJpydfRewardsReceiver` として参照） | CORE-AP-FR-015 |
| `getCollBalance() → uint256` | external view | 会計上の担保残高 `collBalance` | CORE-AP-FR-015 |
| `aggRecordedDebt() → uint256` | external view（public 変数） | 集計記録負債 "D" | CORE-AP-FR-015 |
| `aggWeightedDebtSum() → uint256` | external view（public 変数） | 利率加重負債和 "S" | CORE-AP-FR-015 |
| `lastAggUpdateTime() → uint256` | external view（public 変数） | 集計利息の最終確定時刻 | CORE-AP-FR-015 |
| `shutdownTime() → uint256` | external view（public 変数） | shutdown 時刻（0 = 未 shutdown） | CORE-AP-FR-015 |
| `aggBatchManagementFees() → uint256` | external view（public 変数） | 確定済み・未適用の集計 batch 管理フィー | CORE-AP-FR-015 |
| `aggWeightedBatchManagementFeeSum() → uint256` | external view（public 変数） | batch 管理フィー率加重負債和 | CORE-AP-FR-015 |
| `lastAggBatchManagementFeesUpdateTime() → uint256` | external view（public 変数） | batch フィー集計の最終確定時刻 | CORE-AP-FR-015 |
| `calcPendingAggInterest() → uint256` | public view | 集計ペンディング利息の計算 | CORE-AP-FR-002 |
| `calcPendingSPYield() → uint256` | external view | ペンディング利息のうち SP 取り分 | CORE-AP-FR-003 |
| `calcPendingAggBatchManagementFee() → uint256` | public view | 集計ペンディング batch 管理フィーの計算 | CORE-AP-FR-004 |
| `getNewApproxAvgInterestRateFromTroveChange(TroveChange) → uint256` | external view | Trove 変更を仮適用した近似平均利率 | CORE-AP-FR-005 |
| `getJpydfDebt() → uint256` | external view | アクティブ負債合計（ペンディング利息・フィー込み） | CORE-AP-FR-006 |
| `mintAggInterest()` | external ｜ BO または SP | 集計利息の確定 mint・75/25 分配 | CORE-AP-FR-007 |
| `mintAggInterestAndAccountForTroveChange(TroveChange, address)` | external ｜ BO または TM | 利息 mint＋Trove 変化の集計反映 | CORE-AP-FR-008 |
| `mintBatchManagementFeeAndAccountForChange(TroveChange, address)` | external ｜ TM のみ | batch 管理フィーの確定 mint・集計反映 | CORE-AP-FR-009 |
| `sendColl(address, uint256)` | external ｜ BO・TM・SP | 担保の外部送付（会計減算＋transfer） | CORE-AP-FR-010 |
| `sendCollToDefaultPool(uint256)` | external ｜ TM のみ | redistribution 担保の DefaultPool 移送 | CORE-AP-FR-011 |
| `receiveColl(uint256)` | external ｜ BO または DP | 担保受領（会計加算＋呼出元から pull） | CORE-AP-FR-012 |
| `accountForReceivedColl(uint256)` | public ｜ BO または DP | 直接送付済み担保の会計反映のみ | CORE-AP-FR-013 |
| `setShutdownFlag()` | external ｜ TM のみ | shutdown 時刻の記録（利息累積停止） | CORE-AP-FR-014 |
| `hasBeenShutDown() → bool` | external view | shutdown 済みか（`shutdownTime != 0`） | CORE-AP-FR-015 |

**イベント（監視）**: constructor wiring は `CollTokenAddressChanged` / `BorrowerOperationsAddressChanged` / `TroveManagerAddressChanged` / `DefaultPoolAddressChanged` / `StabilityPoolAddressChanged`、担保会計は `ActivePoolCollBalanceUpdated`、集計利息会計は `ActivePoolAggRecordedDebtUpdated` / `ActivePoolAggWeightedDebtSumUpdated` / `ActivePoolAggBatchManagementFeesUpdated` / `ActivePoolAggWeightedBatchManagementFeeSumUpdated` で追跡する（CORE-AP-EVT-001〜005 / 007〜011）。


### DefaultPool（redistribution 待ち担保・負債の保管庫）🔵

DefaultPool は、ブランチごとにデプロイされ、清算の redistribution によってアクティブ Trove 群へ再分配されたが**まだ各 Trove のストラクトに「適用」されていない**ペンディング担保・JPYdf 負債を保管する会計コントラクト。Trove がペンディング分を適用する操作（清算・redemption・BO 経由の各 Trove 操作・applyPendingDebt）を行うと、当該 Trove の取り分が DefaultPool から ActivePool へ戻される。

書込みは TroveManager（負債増減・担保戻し）と ActivePool（担保受領）に限定。担保（collToken = dToken）の実トークンは ActivePool との間でのみ移動し、外部アドレスへ直接出ていく経路はない。配線はコンストラクタで AddressesRegistry から取得し全て immutable。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `NAME() → string` | external view（public constant） | コントラクト名 `"DefaultPool"` | CORE-DP-FR-006 |
| `collToken() → address` | external view（public immutable） | ブランチ担保トークン（dToken） | CORE-DP-FR-006 |
| `troveManagerAddress() → address` | external view（public immutable） | TroveManager アドレス | CORE-DP-FR-006 |
| `activePoolAddress() → address` | external view（public immutable） | ActivePool アドレス | CORE-DP-FR-006 |
| `getCollBalance() → uint256` | external view | 会計上のペンディング担保残高 | CORE-DP-FR-006 |
| `getJpydfDebt() → uint256` | external view | redistribution 待ち JPYdf 負債残高 | CORE-DP-FR-006 |
| `sendCollToActivePool(uint256)` | external ｜ TM のみ | ペンディング担保の ActivePool への戻し | CORE-DP-FR-002 |
| `receiveColl(uint256)` | external ｜ AP のみ | redistribution 担保の受領（AP から pull） | CORE-DP-FR-003 |
| `increaseJpydfDebt(uint256)` | external ｜ TM のみ | redistribution 負債の計上 | CORE-DP-FR-004 |
| `decreaseJpydfDebt(uint256)` | external ｜ TM のみ | 適用済み負債の取崩し | CORE-DP-FR-005 |


### CollSurplusPool（清算余剰担保の請求権保管庫）🔵

CollSurplusPool は、ブランチごとにデプロイされ、清算時にペナルティ等を控除してなお残った**余剰担保（collateral surplus）**を、元 Trove owner が後から請求（claim）できる形で保管するコントラクト。余剰の発生・金額決定は TroveManager の清算ロジック（TM スコープ）が行い、本コントラクトは「owner 別残高の記帳」と「claim 時の払い出し」のみに責任を持つ。

記帳（accountSurplus）は TroveManager、払い出し（claimColl）は BorrowerOperations に限定される。実トークンは記帳とは別経路（TM が `ActivePool.sendColl` で本コントラクトへ送付）で搬入され、払い出しは本コントラクトから請求者本人へ直接 transfer される。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `NAME() → string` | external view（public constant） | コントラクト名 `"CollSurplusPool"` | CORE-CSP-FR-004 |
| `collToken() → address` | external view（public immutable） | ブランチ担保トークン（dToken） | CORE-CSP-FR-004 |
| `borrowerOperationsAddress() → address` | external view（public immutable） | BorrowerOperations アドレス | CORE-CSP-FR-004 |
| `troveManagerAddress() → address` | external view（public immutable） | TroveManager アドレス | CORE-CSP-FR-004 |
| `getCollBalance() → uint256` | external view | 会計上の余剰担保総額 | CORE-CSP-FR-004 |
| `getCollateral(address) → uint256` | external view | 指定アカウントの請求可能残高 | CORE-CSP-FR-004 |
| `accountSurplus(address, uint256)` | external ｜ TM のみ | 清算余剰の記帳 | CORE-CSP-FR-002 |
| `claimColl(address)` | external ｜ BO のみ | 余剰担保の請求・払い出し | CORE-CSP-FR-003 |


### GasPool（清算ガス補償用 WETH の保管庫）🔵

GasPool は、ブランチごとにデプロイされる、**コンストラクタのみ・関数ゼロ・状態変数ゼロ**の最小コントラクト。Trove 開設時に借り手から徴収される固定額のガス補償 WETH（`ETH_GAS_COMPENSATION`、値は §7）を保管し、Trove close 時の借り手への返金（BorrowerOperations 経由）と、清算時の liquidator への支払い（TroveManager 経由）を、コンストラクタで設定する無限 approve によって可能にする。担保トークンがどの dToken のブランチであっても、ガス補償は常に WETH 建てである。

WETH の入庫（open 時の `WETH.transferFrom(borrower, gasPool, …)`）・出庫（close/清算時の `WETH.transferFrom(gasPool, …)`）はいずれも BO / TM 側のロジックで実行され、GasPool 自身は一切のロジックを持たない。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| （external / public 関数なし。ABI は空） | — | — | CORE-GP-FR-001 |


### SortedTroves（annualInterestRate 降順の双方向連結リスト） 🔵

SortedTroves は、ブランチ内の active な Trove（zombie を除く）を **年利 `annualInterestRate` の降順**で保持する双方向連結リスト。**head＝最高金利、tail＝最低金利**であり、`nextId` 方向＝より低金利側、`prevId` 方向＝より高金利側（`getFirst()` が最大金利、`getLast()` が最小金利のノードを返す）。Redemption は TroveManager が `getLast()` から `getPrev()` で tail 側（最低金利）から順に処理するため、本リストの順序がそのまま redemption 順を規定する。ブランチごとに 1 つデプロイされる。

- ノード ID は `troveId`（uint256。TroveNFT の tokenId と同一）。金利値自体はノードに保持せず、順序判定のたびに `troveManager.getTroveAnnualInterestRate(id)` を参照する。ノードの再挿入が必要になるのは金利変更時のみで、他のシステム操作では順序が保存される。
- **batch 対応**: 同一 batch（一括金利管理。batch manager のアドレスを `BatchId` とする）に属するノードは、リスト上で**連続した slice**（`batches[id].head`〜`batches[id].tail`）を構成する。slice 単位の移動・スキップにより、batch のサイズによらず O(1) で batch を跨いだ走査ができる。
- 挿入位置 hint（`_prevId`/`_nextId`）を任意で受け付ける。hint が無効でも revert せず、hint を起点に正しい位置を必ず再探索する（CORE-ST-FR-009）。
- 実装は Livepeer の audited SortedDoublyLinkedList の改変版（ノードからキーを除去・順序判定を TroveManager 参照に変更・主要関数を internal 化し external ラッパーを提供）。
- 注: ソース冒頭のコメント「the ID property is the address of a Trove owner」は v1 の名残であり、実際の ID は troveId（owner アドレスではない）。
- `BatchId` は `address` の user-defined value type（`Types/BatchId.sol`。`==`/`!=`/`isZero`/`isNotZero` を global using で付与。`BATCH_ID_ZERO = address(0)`）。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `insert(uint256 _id, uint256 _annualInterestRate, uint256 _prevId, uint256 _nextId)` | external（BO のみ） | 非 batch ノードの挿入 | CORE-ST-FR-002 |
| `remove(uint256 _id)` | external（BO / TM） | 非 batch ノードの除去 | CORE-ST-FR-003 |
| `reInsert(uint256 _id, uint256 _newAnnualInterestRate, uint256 _prevId, uint256 _nextId)` | external（BO のみ） | 金利変更に伴う非 batch ノードの再挿入 | CORE-ST-FR-004 |
| `insertIntoBatch(uint256 _troveId, BatchId _batchId, uint256 _annualInterestRate, uint256 _prevId, uint256 _nextId)` | external（BO のみ） | batch へのノード追加（batch tail に連結） | CORE-ST-FR-005 |
| `removeFromBatch(uint256 _id)` | external（BO / TM） | batch ノードの除去 | CORE-ST-FR-006 |
| `reInsertBatch(BatchId _id, uint256 _newAnnualInterestRate, uint256 _prevId, uint256 _nextId)` | external（BO のみ） | batch slice 全体の再挿入 | CORE-ST-FR-007 |
| `validInsertPosition(uint256 _annualInterestRate, uint256 _prevId, uint256 _nextId) → bool` | external view | hint 位置の有効性検証 | CORE-ST-FR-008 |
| `findInsertPosition(uint256 _annualInterestRate, uint256 _prevId, uint256 _nextId) → (uint256, uint256)` | external view | 挿入位置の探索（hint 起点） | CORE-ST-FR-009 |
| `contains(uint256 _id) → bool` | public view | ノードの存在判定 | CORE-ST-FR-010 |
| `isBatchedNode(uint256 _id) → bool` | public view | batch 所属判定 | CORE-ST-FR-010 |
| `isEmptyBatch(BatchId _id) → bool` | external view | batch の空判定 | CORE-ST-FR-010 |
| `isEmpty() → bool` | external view | リストの空判定 | CORE-ST-FR-010 |
| `getSize() → uint256` | external view | ノード数（`size` と同値） | CORE-ST-FR-010 |
| `getFirst() → uint256` | external view | 先頭（最高金利）ノード ID | CORE-ST-FR-010 |
| `getLast() → uint256` | external view | 末尾（最低金利）ノード ID | CORE-ST-FR-010 |
| `getNext(uint256 _id) → uint256` | external view | 次（より低金利側）ノード ID | CORE-ST-FR-010 |
| `getPrev(uint256 _id) → uint256` | external view | 前（より高金利側）ノード ID | CORE-ST-FR-010 |
| `NAME() → string` | public（constant getter） | `"SortedTroves"` | CORE-ST-FR-010 |
| `size() → uint256` | public（自動 getter） | 現在のリストサイズ | CORE-ST-FR-010 |
| `nodes(uint256) → (uint256 nextId, uint256 prevId, BatchId batchId, bool exists)` | public（自動 getter） | ノード構造体の参照 | CORE-ST-FR-010 |
| `batches(BatchId) → (uint256 head, uint256 tail)` | public（自動 getter） | batch slice の両端参照 | CORE-ST-FR-010 |
| `borrowerOperationsAddress() → address` | public（immutable getter） | 書込み権限者（BO） | CORE-ST-FR-001 |
| `troveManager() → address` | public（immutable getter） | 書込み権限者・金利参照先（TM） | CORE-ST-FR-001 |


### TroveNFT / JPYdfTroveNFT（Trove 所有権を表す ERC-721・MetadataNFT を含む） 🔵/🟡

TroveNFT は、Trove の所有権を表す ERC-721 トークン。**tokenId ＝ troveId**（1 Trove : 1 NFT）であり、NFT の保有者が Trove の所有者の正本となる（BO/TM の所有者検証は `ownerOf` を参照する。検証規則自体は BO/TM 節）。mint/burn は TroveManager のみが行い、Trove のライフサイクル（開設で mint、クローズ・清算で burn）に同期する。`tokenURI` は MetadataNFT へ委譲され、**フルオンチェーン**（base64 data URI）の JSON メタデータ＋SVG 画像を返す。ブランチごとに 1 つデプロイされ、name/symbol はデプロイ時に担保トークン（jpydf では dToken。[dToken.md](./dToken.md)）の name/symbol から導出される。実装は OpenZeppelin Contracts **v4.9** の `ERC721` を継承する。

DF の active deployment は、`AddressesRegistry` 経由で `JPYdfTroveNFT` / `JPYdfMetadataNFT` を配線する（🟡 CORE-MOD-007）。未deployの upstream `TroveNFT` / `MetadataNFT` / `baseSVG` surface は fresh deploy 方針に合わせて production `src` から削除済みであり、branch deploy の実体は JPYdf surface のみである。ERC-721 所有権と Trove 連携の挙動は base 同型で、DF 差分は product-facing な collection name/symbol、tokenURI JSON/SVG 文言、非 TM custom error style に限られる。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `mint(address _owner, uint256 _troveId)` | external（TM のみ） | Trove 開設時の NFT 発行 | CORE-TN-FR-002 |
| `burn(uint256 _troveId)` | external（TM のみ） | Trove クローズ・清算時の NFT 焼却 | CORE-TN-FR-003 |
| `tokenURI(uint256 _tokenId) → string` | public view | オンチェーンメタデータ（MetadataNFT へ委譲） | CORE-TN-FR-004 |
| `transferFrom(address,address,uint256)` | public（ERC-721） | NFT 移転＝Trove 所有権移転 | CORE-TN-FR-005 |
| `safeTransferFrom(address,address,uint256)` | public（ERC-721） | 受領確認付き移転 | CORE-TN-FR-005 |
| `safeTransferFrom(address,address,uint256,bytes)` | public（ERC-721） | 同上（data 付き） | CORE-TN-FR-005 |
| `approve(address,uint256)` | public（ERC-721） | 個別承認 | CORE-TN-FR-005 |
| `setApprovalForAll(address,bool)` | public（ERC-721） | 包括承認 | CORE-TN-FR-005 |
| `getApproved(uint256) → address` | public view | 個別承認の照会 | CORE-TN-FR-005 |
| `isApprovedForAll(address,address) → bool` | public view | 包括承認の照会 | CORE-TN-FR-005 |
| `balanceOf(address) → uint256` | public view | 保有 NFT 数（＝保有 Trove 数） | CORE-TN-FR-005 |
| `ownerOf(uint256) → address` | public view | Trove 所有者の正本 | CORE-TN-FR-005 |
| `name() → string` | public view | `"JPYdf - " + collToken.name()`（deployed variant。デプロイ時固定） | CORE-TN-FR-001 |
| `symbol() → string` | public view | `"JPYdf_" + collToken.symbol()`（deployed variant。デプロイ時固定） | CORE-TN-FR-001 |
| `supportsInterface(bytes4) → bool` | public view | ERC-165（IERC721 / IERC721Metadata / IERC165） | CORE-TN-FR-005 |
| `troveManager() → address` | public（immutable getter） | mint/burn 権限者 | CORE-TN-FR-001 |
| `metadataNFT() → address` | public（immutable getter） | メタデータ描画の委譲先 | CORE-TN-FR-001 |

（MetadataNFT 側の external 面 — `uri(TroveData)` / `attributes(TroveData)` / `dynamicTextComponents(TroveData)` / `assetReader()` — は CORE-TN-FR-006 にまとめて規定）


### JpydfToken（システム唯一のステーブルコイン JPYdf。Core mint/burn と bridge-ready dormant surface を分離した non-upgradeable ERC-20 + EIP-2612 singleton） 🔵/🟡

システム全体（全 branch 共有）で 1 つだけデプロイされるステーブルコイン本体。Core 供給（`mint` / `burn`）は登録済み BO / AP / TM / SP / CR に限定され、プロトコルの債務会計にのみ連動する。DF 差分は debt-token 命名（CORE-MOD-001）、bridge-ready dormant extension（CORE-MOD-008）、core address registration hardening（CORE-MOD-009）。

> **規範・全要件は [JpydfToken.md](./JpydfToken.md)**（インターフェース一覧／機能要件 `CORE-BT-FR-*`／状態変数／不変条件 `CORE-BT-INV-*`／セキュリティ `CORE-BT-SEC-*`／イベント `CORE-BT-EVT-*`／異常系 `CORE-BT-ERR-*` を集約）。本節は Core からの位置づけのみを残す。`CORE-BT-*` namespace は維持し、本書内の ID 参照はそのまま解決する。

### CollateralRegistry（branch 横断 redemption の単一入口。unbacked 比例ルーティングと system-wide baseRate を管理する non-upgradeable singleton） 🔵

システム全体で 1 つだけデプロイされる redemption ルーター。JPYdf 保有者はここから `redeemCollateral` を呼び、要求額は各 branch の「unbacked portion」（branch 債務 − SP 預入額）に比例して全 redeemable branch へ配分され、各 TroveManager が実際の Trove 償還を行う。redemption fee の基礎となる `baseRate` は branch 共通の単一状態としてここで管理され、時間経過による指数減衰（半減期 6h）と redemption 規模による増加で更新される。デプロイ時に `INITIAL_BASE_RATE`（100%）で初期化することで、稼働直後の redemption を経済的に成立させない bootstrap 期間を作る。branch 構成（担保トークンと TroveManager の対、最大 10）はすべて immutable で、デプロイ後の追加・削除・差替は不可。Owner を持たず（Ownable 非継承）、管理機能は一切ない。担保トークンは DF 構成では dToken（[dToken.md](./dToken.md)）。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `redeemCollateral(uint256,uint256,uint256)` | external（permissionless） | branch 横断 redemption の実行 | CORE-CR-FR-002 |
| `getRedemptionRate() → uint256` | external view | 現 `baseRate` での実効 rate（decay 未適用） | CORE-CR-FR-003 |
| `getRedemptionRateWithDecay() → uint256` | public view | decay 適用後の実効 rate | CORE-CR-FR-004 |
| `getRedemptionRateForRedeemedAmount(uint256) → uint256` | external view | 指定額 redeem 時の実効 rate 見積り | CORE-CR-FR-005 |
| `getRedemptionFeeWithDecay(uint256) → uint256` | external view | decay 適用 rate × 指定数量の fee | CORE-CR-FR-006 |
| `getEffectiveRedemptionFeeInJpydf(uint256) → uint256` | external view | 指定額 redeem 時の JPYdf 建て実効 fee | CORE-CR-FR-007 |
| `getToken(uint256) → IERC20Metadata` | external view | index → 担保トークン | CORE-CR-FR-008 |
| `getTroveManager(uint256) → ITroveManager` | public view | index → TroveManager | CORE-CR-FR-008 |
| `totalCollaterals() → uint256` | public view（immutable getter） | branch 数 | CORE-CR-FR-009 |
| `jpydfToken() → IJpydfToken` | public view（immutable getter） | JPYdf トークン | CORE-CR-FR-009 |
| `baseRate() → uint256` | public view（自動生成 getter） | 現在の baseRate（最終更新時点値） | CORE-CR-FR-009 |
| `lastFeeOperationTime() → uint256` | public view（自動生成 getter） | 最終 fee 操作時刻（分単位で前進） | CORE-CR-FR-009 |


### AddressesRegistry（branch 1 本分のアドレス配線と immutable リスクパラメータ（CCR/MCR/SCR/BCR/清算ペナルティ）を保持するデプロイ時設定レジストリ） 🔵

branch ごとに 1 つデプロイされる設定コントラクト。constructor で当該 branch のリスクパラメータ（CCR / MCR / SCR / BCR / 清算ペナルティ 2 種)をレンジ検証つきの immutable として固定し、`setAddresses` で branch を構成する全コントラクト＋共有コントラクト（JpydfToken / CollateralRegistry / WETH 等）のアドレスを 1 度だけ設定して ownership を renounce する。各 core コントラクトは自身の constructor で AddressesRegistry から参照を読み取り **自分の immutable に取り込む**ため、本コントラクトはデプロイ配線の単一情報源（single source of truth）であり、稼働後の参照解決には使われない（getter は off-chain・周辺ツール向け）。結果として branch のパラメータ・配線はデプロイ後いっさい変更できない。担保トークン（`collToken`）は DF 構成では dToken（[dToken.md](./dToken.md)）、`priceFeed` は PriceFeedProxy（[Oracle.md](./Oracle.md)）。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `setAddresses(AddressVars)` | external（onlyOwner） | 全 18 アドレスを 1 度だけ設定し ownership renounce | CORE-AR-FR-002 |
| `CCR() → uint256` | public view（immutable getter） | branch の Critical CR | CORE-AR-FR-003 |
| `SCR() → uint256` | public view（immutable getter） | branch の Shutdown CR | CORE-AR-FR-003 |
| `MCR() → uint256` | public view（immutable getter） | Trove 個別の最小 CR | CORE-AR-FR-003 |
| `BCR() → uint256` | public view（immutable getter） | batch 参加・batch 内調整時の追加バッファ CR | CORE-AR-FR-003 |
| `LIQUIDATION_PENALTY_SP() → uint256` | public view（immutable getter） | SP offset 清算ペナルティ | CORE-AR-FR-003 |
| `LIQUIDATION_PENALTY_REDISTRIBUTION() → uint256` | public view（immutable getter） | 再分配清算ペナルティ | CORE-AR-FR-003 |
| `collToken() → IERC20Metadata` | public view | 担保トークン（DF では dToken） | CORE-AR-FR-004 |
| `borrowerOperations() → IBorrowerOperations` | public view | branch の BO | CORE-AR-FR-004 |
| `troveManager() → ITroveManager` | public view | branch の TM | CORE-AR-FR-004 |
| `troveNFT() → ITroveNFT` | public view | branch の TroveNFT | CORE-AR-FR-004 |
| `metadataNFT() → IMetadataNFT` | public view | TroveNFT 用メタデータ生成 | CORE-AR-FR-004 |
| `stabilityPool() → IStabilityPool` | public view | branch の SP（DF デプロイでは DFStabilityPool） | CORE-AR-FR-004 |
| `priceFeed() → IPriceFeed` | public view | branch の PriceFeed（DF では PriceFeedProxy） | CORE-AR-FR-004 |
| `activePool() → IActivePool` | public view | branch の AP | CORE-AR-FR-004 |
| `defaultPool() → IDefaultPool` | public view | branch の DP | CORE-AR-FR-004 |
| `gasPoolAddress() → address` | public view | branch の GasPool | CORE-AR-FR-004 |
| `collSurplusPool() → ICollSurplusPool` | public view | branch の CollSurplusPool | CORE-AR-FR-004 |
| `sortedTroves() → ISortedTroves` | public view | branch の SortedTroves | CORE-AR-FR-004 |
| `interestRouter() → IInterestRouter` | public view | 利息残余の送付先 | CORE-AR-FR-004 |
| `hintHelpers() → IHintHelpers` | public view | 共有 HintHelpers | CORE-AR-FR-004 |
| `multiTroveGetter() → IMultiTroveGetter` | public view | 共有 MultiTroveGetter | CORE-AR-FR-004 |
| `collateralRegistry() → ICollateralRegistry` | public view | 共有 CollateralRegistry | CORE-AR-FR-004 |
| `jpydfToken() → IJpydfToken` | public view | 共有 JpydfToken | CORE-AR-FR-004 |
| `WETH() → IWETH` | public view | ガス補償（`ETH_GAS_COMPENSATION`）用 WETH | CORE-AR-FR-004 |
| `owner() → address` | public view | 現 Owner（`setAddresses` 後は `address(0)`） | CORE-AR-FR-004 |
| `isOwner() → bool` | public view | `msg.sender == owner` 判定 | CORE-AR-FR-004 |

（注: `IAddressesRegistry` ではパラメータ getter が `view` 修飾なしで宣言されているが、実体は public immutable の自動生成 view getter。）


### HintHelpers（SortedTroves hint 探索・upfront fee 試算ヘルパー）🔵

全ブランチ共通の **singleton** read-only ヘルパー。`collateralRegistry` を起点に `_collIndex` で対象ブランチ（TroveManager / ActivePool / SortedTroves）を解決する。責務は 2 つ。

1. **hint 探索**: `getApproxHint` が Trove ID 配列の乱択サンプリングで「目標金利に最も近い Trove」の近似を返す。off-chain でこれを `SortedTroves.findInsertPosition`（ST 節）に渡して正確な挿入位置 `(prevId, nextId)` を求め、`openTrove` / `adjustTroveInterestRate` 等の `_upperHint` / `_lowerHint` として使う 2 段構えの前段。
2. **upfront fee 試算**: BorrowerOperations の各操作（BO 節）が請求する upfront fee を、操作前に同一ロジックで試算する view 8 種（`predict*` 7 種＋ `force` 変種 1 種）。frontend の手数料表示・`_maxUpfrontFee` 設定の基礎となる。

全関数 view で状態を一切書かず、資産も保持しない。イベントなし。AddressesRegistry に `hintHelpers` として登録される（AR 節）。base v1.11.0 と byte-identical。なお `IHintHelpers` インターフェースに宣言されるのは 7 関数のみで、`predictOpenTroveAndJoinBatchUpfrontFee` / `predictRemoveFromBatchUpfrontFee` はコントラクト（ABI）にのみ存在する。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `NAME() → string` | external view（constant） | コントラクト識別子 `"HintHelpers"` | CORE-HH-FR-010 |
| `collateralRegistry() → ICollateralRegistry` | external view（immutable） | 参照する CollateralRegistry | CORE-HH-FR-010 |
| `getApproxHint(uint256 _collIndex, uint256 _interestRate, uint256 _numTrials, uint256 _inputRandomSeed) → (uint256 hintId, uint256 diff, uint256 latestRandomSeed)` | external view・permissionless | 乱択サンプリングによる近似 hint 探索 | CORE-HH-FR-001 |
| `predictOpenTroveUpfrontFee(uint256 _collIndex, uint256 _borrowedAmount, uint256 _interestRate) → uint256` | external view・permissionless | `openTrove` の upfront fee 試算 | CORE-HH-FR-002 |
| `predictAdjustInterestRateUpfrontFee(uint256 _collIndex, uint256 _troveId, uint256 _newInterestRate) → uint256` | external view・permissionless | `adjustTroveInterestRate`（premature 調整）の fee 試算 | CORE-HH-FR-003 |
| `forcePredictAdjustInterestRateUpfrontFee(uint256 _collIndex, uint256 _troveId, uint256 _newInterestRate) → uint256` | external view・permissionless | 同上の無条件試算（0 短絡なし） | CORE-HH-FR-004 |
| `predictAdjustTroveUpfrontFee(uint256 _collIndex, uint256 _troveId, uint256 _debtIncrease) → uint256` | external view・permissionless | 債務増額調整（`adjustTrove` 系）の fee 試算 | CORE-HH-FR-005 |
| `predictAdjustBatchInterestRateUpfrontFee(uint256 _collIndex, address _batchAddress, uint256 _newInterestRate) → uint256` | external view・permissionless | `setBatchManagerAnnualInterestRate` の fee 試算 | CORE-HH-FR-006 |
| `predictOpenTroveAndJoinBatchUpfrontFee(uint256 _collIndex, uint256 _borrowedAmount, address _batchAddress) → uint256` | external view・permissionless（`IHintHelpers` 未宣言） | `openTroveAndJoinInterestBatchManager` の fee 試算 | CORE-HH-FR-007 |
| `predictJoinBatchInterestRateUpfrontFee(uint256 _collIndex, uint256 _troveId, address _batchAddress) → uint256` | external view・permissionless | `setInterestBatchManager`（バッチ加入）の fee 試算 | CORE-HH-FR-008 |
| `predictRemoveFromBatchUpfrontFee(uint256 _collIndex, uint256 _troveId, uint256 _newInterestRate) → uint256` | external view・permissionless（`IHintHelpers` 未宣言） | `removeFromBatch`（バッチ離脱）の fee 試算 | CORE-HH-FR-009 |


### MultiTroveGetter（Trove 一括取得の frontend ヘルパー）🔵

全ブランチ共通の **singleton** view ヘルパー。SortedTroves の並び（金利順）に沿って複数 Trove の状態を 1 回の eth_call でまとめて取得する frontend 用ユーティリティ（コード冒頭コメント: 「Not part of the core Liquity system」）。`collateralRegistry` から `_collIndex` でブランチを解決する。状態書込みなし・資産非保持・イベントなし。base v1.11.0 と byte-identical。AddressesRegistry に `multiTroveGetter` として登録される（AR 節）。ループ上限は引数依存（unbounded）であり on-chain からの利用は想定しない。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `collateralRegistry() → ICollateralRegistry` | external view（immutable） | 参照する CollateralRegistry | CORE-MTG-FR-003 |
| `getMultipleSortedTroves(uint256 _collIndex, int256 _startIdx, uint256 _count) → CombinedTroveData[]` | external view・permissionless | 金利順に Trove 詳細を一括取得（正: 先頭から降順／負: 末尾から昇順） | CORE-MTG-FR-001 |
| `getDebtPerInterestRateAscending(uint256 _collIndex, uint256 _startId, uint256 _maxIterations) → (DebtPerInterestRate[], uint256 currId)` | external view・permissionless | 金利昇順の (バッチ, 金利, 債務) 列挙（カーソル式ページング） | CORE-MTG-FR-002 |


### DebtInFrontHelper（debt-in-front 精密計算ヘルパー）🔵

全ブランチ共通の **singleton** view ヘルパー（コード冒頭コメント: 「frontend が debt-in-front を精密に計算するためのヘルパー。Not part of the core Liquity system」）。償還（redemption）は SortedTroves の最低金利側から債務を消化するため、**ある Trove より先に償還される債務の総量（debt-in-front）**がその Trove の償還リスク指標になる。本コントラクトは金利帯を指定した債務合計を、ソート済みリストの実走査で正確に算出する 2 関数を提供する。`hintHelpers`（CORE-HH-FR-001）を走査開始点の探索に利用する。状態書込みなし・資産非保持・イベントなし。base v1.11.0 と byte-identical。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `collateralRegistry() → ICollateralRegistry` | external view（immutable） | 参照する CollateralRegistry | CORE-DFH-FR-003 |
| `hintHelpers() → IHintHelpers` | external view（immutable） | hint 探索の委譲先 HintHelpers | CORE-DFH-FR-003 |
| `getDebtBetweenInterestRates(uint256 _collIndex, uint256 _interestRateLo, uint256 _interestRateHi, uint256 _excludedTroveId, uint256 _hintId, uint256 _numTrials) → (uint256 debt, uint256 blockTimestamp)` | external view・permissionless | 金利帯 [lo, hi) の債務合計（指定 Trove を除外） | CORE-DFH-FR-001 |
| `getDebtBetweenInterestRateAndTrove(uint256 _collIndex, uint256 _interestRateLo, uint256 _interestRateHi, uint256 _troveIdToStopAt, uint256 _hintId, uint256 _numTrials) → (uint256 debt, uint256 blockTimestamp)` | external view・permissionless | 金利 lo から特定 Trove 直前までの債務合計（同率内の位置も反映） | CORE-DFH-FR-002 |


### RedemptionHelper（償還ラッパー・償還シミュレーション）🔵

**singleton**。CollateralRegistry の償還（CR 節）を取り巻く 3 機能を提供する。(1) `redeemCollateral`: `CollateralRegistry.redeemCollateral` の **on-chain ラッパー**で、ブランチ別の最低受領担保量によるスリッページ保護と未償還 JPYdf の自動返還を追加する。(2) `simulateRedemption` / (3) `truncateRedemption`: 償還のブランチ配分・Trove 走査をトレースする **off-chain 専用シミュレーション**。後 2 者は内部の価格取得（`PriceFeed.fetchPrice` / `fetchRedemptionPrice`。[Oracle.md](./Oracle.md) PriceFeedProxy）が状態書込みを伴うため **view ではなく nonpayable**（コード内コメント: 「Meant to be called off-chain / Not a view because price fetching has side-effects」）であり、eth_call での利用を想定する。想定利用者は償還を行う arbitrageur / bot / frontend。コントラクトは tx をまたいで資産を保持しない。イベントなし。base v1.11.0 と behavior-parity（JPYdf rename と SafeERC20 hardening は CORE-MOD-001/010）。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `numBranches() → uint256` | external view（immutable） | ブランチ数（= `totalCollaterals`） | CORE-RH-FR-004 |
| `collateralRegistry() → ICollateralRegistry` | external view（immutable） | 参照する CollateralRegistry | CORE-RH-FR-004 |
| `jpydfToken() → IJpydfToken` | external view（immutable） | JPYdf トークン | CORE-RH-FR-004 |
| `addresses(uint256) → IAddressesRegistry` | external view（storage 配列） | ブランチ i の AddressesRegistry | CORE-RH-FR-004 |
| `redeemCollateral(uint256 _jpydf, uint256 _maxIterationsPerCollateral, uint256 _maxFeePct, uint256[] _minCollRedeemed)` | external nonpayable・permissionless | min-out 付き償還ラッパー | CORE-RH-FR-001 |
| `simulateRedemption(uint256 _jpydf, uint256 _maxIterationsPerCollateral) → (SimulationContext[] branch, uint256 totalProportions)` | public nonpayable・permissionless（off-chain 専用） | ブランチ配分と償還可能量の試算 | CORE-RH-FR-002 |
| `truncateRedemption(uint256 _jpydf, uint256 _maxIterationsPerCollateral) → (uint256 truncatedJpydf, uint256 feePct, Redeemed[] redeemed)` | external nonpayable・permissionless（off-chain 専用） | iteration 上限内で比例償還しきれる最大量・fee 率・期待受領担保の算出 | CORE-RH-FR-003 |


### LiquidationCandidateGetter（清算候補スキャナ・DF 独自）🟢

**base（liquity/bold v1.11.0）に存在しない DF 追加の view ヘルパー**（🟢 Original）。清算 bot・監視系が「いま清算可能な Trove」を列挙するための read-only ページングスキャナで、**core の状態は読むだけで一切書かない**（全関数 view。core 側も本コントラクトを参照しない一方向依存であり、デプロイ有無が core の挙動に影響しない）。SortedTroves を金利順に走査し、呼出者が与えた価格・MCR に対して ICR が下回る Trove を返す。必要に応じて SortedTroves から外れる `lastZombieTroveId` も同じ候補形式で取得できる。全ブランチ共通の **singleton**。資産非保持・イベントなし。コード冒頭コメント: 「Helper contract for liquidation bots and monitoring. Not part of the core Liquity system」。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `collateralRegistry() → ICollateralRegistry` | external view（immutable） | 参照する CollateralRegistry | CORE-LCG-FR-002 |
| `getLiquidationCandidates(uint256 _collIndex, uint256 _startId, uint256 _maxIterations, uint256 _price, uint256 _mcr) → (LiquidationCandidate[] candidates, uint256 currId)` | external view・permissionless | ICR < `_mcr` の Trove をページング走査で列挙 | CORE-LCG-FR-001 |
| `getLiquidationCandidatesWithLastZombie(uint256 _collIndex, uint256 _startId, uint256 _maxIterations, uint256 _price, uint256 _mcr, bool _includeLastZombie) → (LiquidationCandidate[] candidates, uint256 currId, bool includedLastZombie)` | external view・permissionless | SortedTroves 走査結果に liquidatable な `lastZombieTroveId` を任意で追記 | CORE-LCG-FR-003 |
| `getLastZombieLiquidationCandidate(uint256 _collIndex, uint256 _price, uint256 _mcr) → (bool found, LiquidationCandidate candidate)` | external view・permissionless | `lastZombieTroveId` 単体の清算候補判定 | CORE-LCG-FR-003 |


### Constants.sol（システム定数） 🔵/🟡

コンパイル単位で共有される file-level 定数の集合。担保比率・清算ペナルティ・利率レンジ・redemption パラメータ・利回り分配率など、core 全体の経済パラメータの宣言箇所。コントラクトではなくファイルレベル定数（Solidity の file-level `constant`）であり、参照側コントラクトのバイトコードへコンパイル時にインライン展開される（ストレージ・getter を持たない。値の変更＝参照側コントラクトの再コンパイル・再デプロイ）。

DF 差分はこのファイルに集中して 3 種ある: `MIN_DEBT` の変更（🟡 CORE-MOD-002）、`COLL_GAS_COMPENSATION_CAP` の変更（🟡 CORE-MOD-003）、ブランチ別定数群の**追記**（CORE-MOD-005。upstream 定数は不変）。`MIN_DEBT` は `Constants.sol` / CORE-LIB-FR-002、清算者補償とブランチ別値は [Parameters.md](../../../Parameters.md) を正本とする。

**インターフェース一覧（非規範・挙動の規範は §6）**

file-level 定数は ABI を持たない。


### LiquityBase（ブランチ共通会計ベース） 🔵

TroveManager・BorrowerOperations・StabilityPool（および 🟡 DFStabilityPool）が継承する共通ベースコントラクト。ブランチ（担保単位デプロイ）ごとの ActivePool / DefaultPool / PriceFeed への参照を constructor で AddressesRegistry から解決・保持し、ブランチ全体の担保・負債の集計、TCR 計算、Critical Threshold 判定、単利計算プリミティブを提供する。規定インターフェースは `ILiquityBase`（`activePool()` / `getEntireBranchDebt()` / `getEntireBranchColl()` の 3 関数のみ。NatSpec なし）。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `activePool() → IActivePool` | public view（自動 getter） | ブランチの ActivePool 参照 | CORE-LIB-FR-005 |
| `getEntireBranchColl() → uint256` | public view | ブランチ全体の担保合計（Active + Default） | CORE-LIB-FR-006 |
| `getEntireBranchDebt() → uint256` | public view | ブランチ全体の負債合計（Active + Default） | CORE-LIB-FR-006 |

（internal: `_getTCR` / `_checkBelowCriticalThreshold` = CORE-LIB-FR-007、`_calcInterest` = CORE-LIB-FR-008。ABI には現れないが継承側の挙動の基底となるため FR 化する）


### LiquityMath（数学ライブラリ） 🔵

internal pure 関数のみからなる数学ライブラリ（デプロイ単位を持たず、参照側へインライン化される）。大小比較・差分・担保比率（CR）計算と、18 桁固定小数の累乗（redemption baseRate の時間減衰用）を提供する。

**インターフェース一覧（非規範・挙動の規範は §6）**

ABI なし（全関数 internal）。提供関数: `_min` / `_max` / `_sub_min_0` / `decMul` / `_decPow` / `_getAbsoluteDifference` / `_computeCR`（規定 ID: CORE-LIB-FR-009 / 010）。


### Ownable（one-shot 配線用の独自 Ownable） 🔵

OpenZeppelin Ownable を基にした upstream 独自の軽量 Ownable。**OZ と異なり `transferOwnership` を持たず（移譲不能）、public な `renounceOwnership` も持たない**。所有権の放棄は internal `_renounceOwnership()` のみで、継承側がデプロイ直後の一回限りの配線関数の末尾で呼ぶ「使い捨て owner」パターンを意図する。継承者は JpydfToken（`setCollateralRegistry` 末尾で放棄。CORE-BT）と AddressesRegistry（`setAddresses` 末尾で放棄。CORE-AR）の 2 つ。

**インターフェース一覧（非規範・挙動の規範は §6）**

| 関数 | 可視性・権限 | 要約 | 規定 ID |
| --- | --- | --- | --- |
| `owner() → address` | public view | 現在の owner（放棄後は address(0)） | CORE-LIB-FR-011 |
| `isOwner() → bool` | public view | `msg.sender == _owner` | CORE-LIB-FR-011 |

（modifier `onlyOwner` = CORE-LIB-FR-011、internal `_renounceOwnership()` = CORE-LIB-FR-012）


### Types（共有型定義） 🔵

`contracts/src/Types/` 配下の 5 ファイル。user-defined value type 2 種（TroveId / BatchId）と、利息会計の差分・スナップショット受け渡しに使う struct 3 種（TroveChange / LatestTroveData / LatestBatchData）。いずれもロジックを持たない型定義（value type の演算子・述語は pure な free function）であり、デプロイ単位を持たない。

**インターフェース一覧（非規範・挙動の規範は §6）**

該当なし（ABI を持たない型定義のみ。value type の演算子 `==` / `!=` と述語 `isEndOfList` / `isNotEndOfList` / `isZero` / `isNotZero` はコンパイル時に解決される free function）。

**AggregatorV3Interface**

Chainlink AggregatorV3 の最小インターフェース転載（`decimals()` / `latestRoundData()` のみ）。PriceFeed 系の依存であり、規範は [Oracle.md](./Oracle.md) スコープ（本書では仕様化しない）。


---

## 6. 機能要件（FR）

> 規範の本体。コントラクトごとに全 external/public 関数を FR として規定する（自明な view getter は「view 関数群」FR に集約）。各 FR の **Verification** は §13 の検証手段語彙（`parity` / `unit` / `fuzz` / `invariant` / `fork` / `manual`）を用いる。🔵 の規範スタンス（base 実装が正）は §2.4。


### BorrowerOperations の機能要件（CORE-BO-FR-*）

#### CORE-BO-FR-001: openTrove（新規 Trove の開設）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `openTrove(address _owner, uint256 _ownerIndex, uint256 _collAmount, uint256 _jpydfAmount, uint256 _upperHint, uint256 _lowerHint, uint256 _annualInterestRate, uint256 _maxUpfrontFee, address _addManager, address _removeManager, address _receiver) → uint256`
- **目的**: 担保 `_collAmount` を預け、`_jpydfAmount` の JPYdf を借りて、自己選択金利 `_annualInterestRate` の新規 Trove を開設する。Trove ID を返す。
- **権限**: permissionless（呼出者が担保・WETH ガス補償を負担。NFT は `_owner` に発行される）。
- **事前条件（Checks）**（コードの検査順）:
  1. `_annualInterestRate` が `[MIN_ANNUAL_INTEREST_RATE, MAX_ANNUAL_INTEREST_RATE]` 内（値は §7）
  2. 未 shutdown（`hasBeenShutDown == false`）
  3. `priceFeed.fetchPrice()` が oracle 失敗を検出しない（PriceFeedProxy。[Oracle.md](./Oracle.md)）
  4. `troveId = keccak256(abi.encode(msg.sender, _owner, _ownerIndex))` が未使用（status == `nonExistent`）
  5. upfront fee = `_calcUpfrontFee(_jpydfAmount, avgInterestRate)`（ブランチ平均金利 `UPFRONT_INTEREST_PERIOD`＝7 日分。平均金利は ActivePool の近似値で、この時点では fee を含めず概算）が `_maxUpfrontFee` 以下
  6. `entireDebt = _jpydfAmount + upfrontFee ≥ MIN_DEBT`（🟡 DF 値、CORE-MOD-002 / CORE-LIB-FR-002）
  7. `ICR = computeCR(_collAmount, entireDebt, price) ≥ MCR`（fee 込み債務で判定）
  8. 開設後のブランチ TCR（fee 込み）≥ CCR
- **動作（Effects）**（実行順）:
  1. `addManagerOf[troveId] = _addManager`・`removeManagerReceiverOf[troveId] = (_removeManager, _receiver)` を設定（`AddManagerUpdated` / `RemoveManagerAndReceiverUpdated` 発火。`_removeManager == 0` かつ `_receiver != 0` は不可）
  2. `activePool.mintAggInterestAndAccountForTroveChange(change, address(0))`（ブランチ集計の更新。CORE-AP 系）
  3. 担保を `collToken.safeTransferFrom(msg.sender → ActivePool)` で移転し `accountForReceivedColl`（担保 = dToken。[dToken.md](./dToken.md)）
  4. `jpydfToken.mint(msg.sender, _jpydfAmount)`（**mint 先は msg.sender**。`_owner` ではない）
  5. `WETH.transferFrom(msg.sender, gasPool, ETH_GAS_COMPENSATION)`（清算ガス補償のロック。値は §7。事前に WETH approve が必要）
  6. `troveManager.onOpenTrove(_owner, troveId, change, _annualInterestRate)`（Trove 記録の作成・TroveNFT を `_owner` に mint。CORE-TM 系）
  7. `sortedTroves.insert(troveId, _annualInterestRate, _upperHint, _lowerHint)`（CORE-ST 系）
  8. `troveId` を返す
- **revert / 早期 return**: 金利範囲外 → `InterestRateTooLow` / `InterestRateTooHigh`；shutdown 済み → `IsShutDown`；oracle 失敗検出 → `NewOracleFailureDetected`；ID 重複 → `TroveExists`；fee 超過 → `UpfrontFeeTooHigh`；`MIN_DEBT` 未満 → `DebtBelowMin`；ICR < MCR → `ICRBelowMCR`；TCR < CCR → `TCRBelowCCR`；`_removeManager == 0` かつ `_receiver != 0` → `EmptyManager`；担保・WETH の transferFrom 失敗 → 各トークンの revert。
- **発火イベント**: `AddManagerUpdated`（CORE-BO-EVT-008）、`RemoveManagerAndReceiverUpdated`（CORE-BO-EVT-009）。Trove 状態系イベントは TroveManager 側（CORE-TM 系）。
- **設計上のポイント**: Trove ID は `(msg.sender, _owner, _ownerIndex)` から決定的に導出され、同一組での再開設は（closed 後も status が残るため）`TroveExists` になる。upfront fee はブランチ**平均**金利の 7 日分であり、自身の選択金利ではない（金利選択の出入りでシステム合計利息を即時に薄められないようにする設計）。ICR・TCR 検証はいずれも fee 込み債務で行う。
- **Verification**: parity / invariant=CORE-BO-INV-002, CORE-BO-INV-005

#### CORE-BO-FR-002: openTroveAndJoinInterestBatchManager（batch 同時加入の開設）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `openTroveAndJoinInterestBatchManager(OpenTroveAndJoinInterestBatchManagerParams calldata _params) → uint256`（params: `owner, ownerIndex, collAmount, jpydfAmount, upperHint, lowerHint, interestBatchManager, maxUpfrontFee, addManager, removeManager, receiver`）
- **目的**: 新規 Trove を開設し、同時に既存の interest batch に加入する。金利は batch の現行金利を適用。
- **権限**: permissionless（FR-001 と同じ負担構造）。
- **事前条件（Checks）**:
  1. `_params.interestBatchManager` が登録済み batch manager（`maxInterestRate > 0`）
  2. 以降 FR-001 の Checks 2〜6・8 と同一（金利は batch の `annualInterestRate` を使用。upfront fee の平均金利近似には batch の既存債務＋新規借入を加味）
  3. ICR は **`MCR + BCR` 以上**（batch 所属 Trove は MCR に BCR を上乗せした強い要求）
- **動作（Effects）**: FR-001 の Effects 1〜5 と同一の後、
  6. `interestBatchManagerOf[troveId] = _params.interestBatchManager`
  7. `troveManager.onOpenTroveAndJoinBatch(...)`（Trove 記録・NFT mint・batch shares への参入。CORE-TM 系）
  8. `sortedTroves.insertIntoBatch(troveId, batchId, batch.annualInterestRate, hints)`
  9. `troveId` を返す
- **revert / 早期 return**: 未登録 manager → `InvalidInterestBatchManager`；ICR < MCR+BCR → `ICRBelowMCRPlusBCR`；ほか FR-001 と同一。
- **発火イベント**: FR-001 と同一（CORE-BO-EVT-008 / 009）。
- **設計上のポイント**: BCR 上乗せは「batch 加入時の状態更新（join/adjust）が清算境界ぎりぎりで行われ、redemption・清算の計算と干渉する」ことへのバッファ。batch の管理 fee は TroveChange の weighted 値（`newWeightedRecordedBatchManagementFee`）として同時に集計へ反映される。
- **Verification**: parity / invariant=CORE-BO-INV-002, CORE-BO-INV-003

#### CORE-BO-FR-003: adjustTrove（担保・債務の複合調整・共通調整パス）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol `_adjustTrove`）
- **シグネチャ**: `adjustTrove(uint256 _troveId, uint256 _collChange, bool _isCollIncrease, uint256 _jpydfChange, bool _isDebtIncrease, uint256 _maxUpfrontFee)`
- **目的**: active な Trove の担保増減と債務増減を 1 トランザクションで行う。本 FR の Checks/Effects は内部共通パス `_adjustTrove` の規定であり、FR-004〜FR-008 はこのパスの特殊化。
- **権限**: 変更内容で分岐（AddRemoveManagers 継承面）。
  - **出金系**（`collDecrease > 0` または `debtIncrease > 0`）: owner または RemoveManager のみ。RemoveManager 本人の呼出時のみ登録 receiver（非ゼロなら）が受取先になり、それ以外は owner が受取先。
  - **入金系のみ**（担保追加・返済のみ）: owner / AddManager / RemoveManager。**`addManagerOf` がゼロなら誰でも可**（既定で入金系は開放）。
- **事前条件（Checks）**（コードの検査順）:
  1. （external wrapper）Trove が active（zombie 不可）
  2. 未 shutdown
  3. 担保引出または債務増加を含む場合のみ、oracle pause中でないこと、`fetchPrice()` が有効な価格と30h未満のJPY更新を返すことを要求する。返済・担保追加だけなら価格を取得しない
  4. Trove が open（active or zombie。wrapper 側の検査と合わせ実効は active、zombie は FR-008 経由のみ）
  5. 上記権限検査
  6. 返済（`debtDecrease > 0`）の場合: 返済額を `entireDebt − MIN_DEBT` に **silent cap**（revert せず縮小。`entireDebt ≤ MIN_DEBT` なら 0。MIN_DEBT は 🟡 DF 値、CORE-MOD-002 / CORE-LIB-FR-002）し、cap 後の額について `jpydfToken.balanceOf(msg.sender) ≥ debtDecrease`
  7. cap 適用後に 4 成分（collIncrease/collDecrease/debtIncrease/debtDecrease）がすべて 0 でない
  8. 担保引出は `collDecrease ≤ entireColl`
  9. 借入（`debtIncrease > 0`）の場合: upfront fee（ブランチ平均金利 7 日分、`debtIncrease` ベース）が `_maxUpfrontFee` 以下。fee は新債務に加算
  10. 調整後 `newDebt ≥ MIN_DEBT`（返済 cap により active Trove では常に成立。実質 FR-008 の zombie 復帰要件）
  11. **担保引出または債務増加を含む場合の許可条件**（`_requireValidAdjustmentInCurrentMode`）。返済・担保追加だけならICR/TCR検査を省略し、MCRやMCR+BCR未満でも改善を許可する:
      - 両モード共通: 調整後 ICR ≥ MCR（batch 所属なら ≥ MCR + BCR）
      - 通常モード（調整前 TCR ≥ CCR）: 調整後 TCR ≥ CCR
      - クリティカル（調整前 TCR < CCR）: 借入は調整後 TCR ≥ CCR を回復する場合のみ可。担保引出は同価値以上の返済を伴う場合のみ可（`debtDecrease × 1e18 ≥ collDecrease × price`）。TCR を CCR 以上へ戻すことまでは要求しない
- **動作（Effects）**（実行順）:
  1. batch 所属なら `troveManager.onAdjustTroveInsideBatch(...)`、単独なら `troveManager.onAdjustTrove(...)`（記録 coll/debt の更新。batch では shares 再計算。CORE-TM 系）
  2. `activePool.mintAggInterestAndAccountForTroveChange(change, batchManager)`（再分配適用分・batch fee を含む集計更新）
  3. トークン移転（`_moveTokensFromAdjustment`）: `debtIncrease` → JPYdf を receiver に mint ／ `debtDecrease` → msg.sender から burn ／ `collIncrease` → msg.sender から ActivePool へ移転 ／ `collDecrease` → ActivePool から receiver へ送付
- **revert / 早期 return**: shutdown 済み → `IsShutDown`；oracle 失敗 → `NewOracleFailureDetected`；非 open → `TroveNotOpen`（wrapper では `TroveNotActive`）；権限なし → `NotOwnerNorRemoveManager` / `NotOwnerNorAddManager`；JPYdf 残高不足 → `NotEnoughJpydfBalance`；全成分ゼロ（cap で 0 化した場合を含む）→ `ZeroAdjustment`；引出超過 → `CollWithdrawalTooHigh`；fee 超過 → `UpfrontFeeTooHigh`；`MIN_DEBT` 未満 → `DebtBelowMin`；ICR 不足 → `ICRBelowMCR` / `ICRBelowMCRPlusBCR`；TCR 違反 → `TCRBelowCCR`；クリティカル時の担保引出条件違反 → `RepaymentNotMatchingCollWithdrawal`。
- **発火イベント**: なし（BO 自体は発火しない。Trove 状態系は CORE-TM 系）。
- **設計上のポイント**: 返済の silent cap により「全額返済」は adjustTrove ではできず `closeTrove` のみで行う（Trove を MIN_DEBT 未満の生存状態にしない）。batch 所属 Trove では TroveChange の weighted 値が batch 全体（債務＋管理 fee）で構成される。upfront fee は借入時のみで、担保操作・返済には課されない。
- **Verification**: parity / invariant=CORE-BO-INV-002

#### CORE-BO-FR-004: addColl（担保追加）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `addColl(uint256 _troveId, uint256 _collAmount)`
- **目的**: active な Trove に担保を追加する。
- **権限**: 入金系（FR-003 参照。`addManagerOf` 未設定なら誰でも可）。
- **事前条件（Checks）/ 動作（Effects）**: Trove が active であることを検査後、`collIncrease = _collAmount`・`_maxUpfrontFee = 0` で FR-003 の共通パスを実行（fee は発生しない）。
- **revert / 早期 return**: 非 active → `TroveNotActive`；ほか FR-003 に同じ。
- **発火イベント**: なし。
- **Verification**: parity

#### CORE-BO-FR-005: withdrawColl（担保引出）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `withdrawColl(uint256 _troveId, uint256 _collWithdrawal)`
- **目的**: active な Trove から担保を引き出す。
- **権限**: 出金系（owner / RemoveManager。受取先は FR-003 の receiver 規則）。
- **事前条件（Checks）/ 動作（Effects）**: Trove が active であることを検査後、`collDecrease = _collWithdrawal`・`_maxUpfrontFee = 0` で FR-003 を実行（fee は発生しない。ICR/TCR・モード別条件は FR-003 のとおり）。
- **revert / 早期 return**: 非 active → `TroveNotActive`；ほか FR-003 に同じ。
- **発火イベント**: なし。
- **Verification**: parity

#### CORE-BO-FR-006: withdrawJpydf（追加借入）🟡
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）＋ DF rename（CORE-MOD-006）
- **シグネチャ**: `withdrawJpydf(uint256 _troveId, uint256 _jpydfAmount, uint256 _maxUpfrontFee)`
- **目的**: active な Trove の債務を増やし、JPYdf を新規 mint する。
- **権限**: 出金系（owner / RemoveManager。mint 先は FR-003 の receiver 規則）。
- **事前条件（Checks）/ 動作（Effects）**: Trove が active であることを検査後、`debtIncrease = _jpydfAmount` で FR-003 を実行。upfront fee（平均金利 7 日分）が債務に上乗せされ、`_maxUpfrontFee` で上限を指定する。
- **revert / 早期 return**: 非 active → `TroveNotActive`；fee 超過 → `UpfrontFeeTooHigh`；ほか FR-003 に同じ（クリティカル時は TCR 回復借入のみ可）。
- **発火イベント**: なし。
- **Verification**: parity

#### CORE-BO-FR-007: repayJpydf（返済）🟡
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）＋ DF rename（CORE-MOD-006）
- **シグネチャ**: `repayJpydf(uint256 _troveId, uint256 _jpydfAmount)`
- **目的**: active な Trove の債務を JPYdf の burn により減らす。
- **権限**: 入金系（FR-003 参照。`addManagerOf` 未設定なら第三者も返済可能）。
- **事前条件（Checks）/ 動作（Effects）**: Trove が active であることを検査後、`debtDecrease = _jpydfAmount`・`_maxUpfrontFee = 0` で FR-003 を実行。返済額は `entireDebt − MIN_DEBT` に silent cap される（MIN_DEBT は 🟡 DF 値、CORE-MOD-002 / CORE-LIB-FR-002）。burn 元は常に msg.sender。
- **revert / 早期 return**: 非 active → `TroveNotActive`；cap 後 0 → `ZeroAdjustment`；残高不足 → `NotEnoughJpydfBalance`；ほか FR-003 に同じ。
- **発火イベント**: なし。
- **Verification**: parity

#### CORE-BO-FR-008: adjustZombieTrove（zombie Trove の調整と active 復帰）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `adjustZombieTrove(uint256 _troveId, uint256 _collChange, bool _isCollIncrease, uint256 _jpydfChange, bool _isDebtIncrease, uint256 _upperHint, uint256 _lowerHint, uint256 _maxUpfrontFee)`
- **目的**: redemption で `MIN_DEBT` 未満となり zombie 化した Trove を調整し、active に復帰させてソートリストに再挿入する。
- **権限**: FR-003 と同一の方向別権限。
- **事前条件（Checks）**: Trove が zombie であること（active は不可）。以降 FR-003 の共通パス全件。特に調整後 `newDebt ≥ MIN_DEBT` が必須（🟡 DF 値、CORE-MOD-002 / CORE-LIB-FR-002）。zombie の `entireDebt ≤ MIN_DEBT` の間は返済が 0 に cap されるため、復帰には実質的に債務増（または再分配による債務回復後の調整）が必要。
- **動作（Effects）**: FR-003 の Effects の後、
  1. `troveManager.setTroveStatusToActive(_troveId)`（CORE-TM 系）
  2. batch 所属なら batch の現行金利で `sortedTroves.insertIntoBatch`、単独なら Trove の金利で `sortedTroves.insert`（`_upperHint`/`_lowerHint` 使用）
- **revert / 早期 return**: 非 zombie → `TroveNotZombie`；調整後 `MIN_DEBT` 未満 → `DebtBelowMin`；ほか FR-003 に同じ。
- **発火イベント**: なし（状態遷移イベントは CORE-TM 系）。
- **設計上のポイント**: zombie はソートリスト外のため通常の `adjustTrove` を拒否し、復帰時のリスト再挿入（hints 付き）を強制するための専用エントリポイント。
- **価格を使わない復帰**: 利息や再分配で債務がMIN_DEBT以上へ戻ったzombieは、返済・担保追加だけの調整ならICR検査なしでactiveへ復帰できる。MCR未満でも改善を許可し、清算対象であることは変わらない。
- **Verification**: parity

#### CORE-BO-FR-009: closeTrove（Trove の閉鎖）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `closeTrove(uint256 _troveId)`
- **目的**: 債務全額（利息・batch fee・再分配分込み）を返済して Trove を閉鎖し、担保と WETH ガス補償を回収する。
- **権限**: owner または RemoveManager（receiver 規則は FR-003 と同一。担保とガス補償は receiver へ、JPYdf の burn は msg.sender から）。
- **事前条件（Checks）**（コードの検査順）:
  1. `troveNFT.ownerOf(_troveId)` で owner 取得（不存在 Trove は ERC-721 側で revert）・権限/receiver 判定
  2. Trove が open（active または zombie）
  3. `jpydfToken.balanceOf(msg.sender) ≥ trove.entireDebt`
  4. `priceFeed.fetchPrice()`（**oracle 失敗でも revert しない**。失敗時は fetchPrice 内の連鎖で本ブランチが shutdown 済みになる）
  5. 未 shutdown のときのみ: 閉鎖後ブランチ TCR ≥ CCR（**shutdown 後は TCR 検査なしで閉鎖可能**）
- **動作（Effects）**（実行順）:
  1. `troveManager.onCloseTrove(...)`（status → `closedByOwner`、NFT burn、batch からの退出。CORE-TM 系）
  2. batch 所属だった場合 `interestBatchManagerOf[_troveId]` を消去
  3. `activePool.mintAggInterestAndAccountForTroveChange(change, batchManager)`
  4. `WETH.transferFrom(gasPool, receiver, ETH_GAS_COMPENSATION)`（ガス補償の返還）
  5. `jpydfToken.burn(msg.sender, trove.entireDebt)`
  6. `activePool.sendColl(receiver, trove.entireColl)`（担保 = dToken の返還。[dToken.md](./dToken.md)）
  7. `_wipeTroveMappings`: 個別 delegate・batch 紐付け・AddManager/RemoveManager を消去（`AddManagerUpdated(0)` / `RemoveManagerAndReceiverUpdated(0,0)` 発火）
- **revert / 早期 return**: 権限なし → `NotOwnerNorRemoveManager`；非 open → `TroveNotOpen`；残高不足 → `NotEnoughJpydfBalance`；TCR < CCR（未 shutdown 時）→ `TCRBelowCCR`。
- **発火イベント**: `AddManagerUpdated`（CORE-BO-EVT-008）、`RemoveManagerAndReceiverUpdated`（CORE-BO-EVT-009）。
- **設計上のポイント**: 閉鎖は shutdown 後も可能（shutdown 後の債務削減経路は closeTrove と urgent redemption）。ただし**非 shutdown では最後の 1 Trove は閉じられない**（`_closeTrove` の `OnlyOneTroveLeft` ガード＝redistribution の受け皿〔`totalStakes > 0`〕を確保するため。CORE-TM-FR-021 / CORE-TM-ERR-004）。shutdown 後に最後の 1 件でも閉鎖できるのは、当該ガードが回避され、かつ `closeTrove` が TCR 検査をスキップする（`if (!hasBeenShutDown) _requireNewTCRisAboveCCR`）ためである。batch 閉鎖時は batch 集計から当該 Trove 分を控除した weighted 値で AP 集計を更新する。
- **Verification**: parity / invariant=CORE-BO-INV-002

#### CORE-BO-FR-010: applyPendingDebt（利息・再分配の記録値への確定）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `applyPendingDebt(uint256 _troveId, uint256 _lowerHint, uint256 _upperHint)`（public）
- **目的**: 任意の Trove の未確定分（発生利息・batch 管理 fee・再分配 gains）を記録 coll/debt に確定（compound）させる。zombie が `MIN_DEBT` 以上に回復していれば active に復帰させる。
- **権限**: permissionless（誰でも任意の Trove に対して実行可能）。
- **事前条件（Checks）**: 未 shutdown；Trove が open（active or zombie）；`entireDebt != 0`。
- **動作（Effects）**:
  1. `troveManager.onApplyTroveInterest(...)`（記録 coll/debt・batch 集計の更新。CORE-TM 系）
  2. `activePool.mintAggInterestAndAccountForTroveChange(change, batchManager)`
  3. zombie かつ `entireDebt ≥ MIN_DEBT`（🟡 DF 値、CORE-MOD-002 / CORE-LIB-FR-002）なら `setTroveStatusToActive` し、（batch 所属なら batch として）ソートリストへ再挿入
- **revert / 早期 return**: shutdown 済み → `IsShutDown`；非 open → `TroveNotOpen`；債務ゼロ → `TroveWithZeroDebt`。
- **発火イベント**: なし（BO 側）。
- **設計上のポイント**: 長期間操作されない Trove の「記録債務と実債務の乖離」を第三者が解消できる仕組み（redemption 順序や清算の前提を正しく保つ）。シグネチャは hints 付きの 1 本のみ（hints は zombie 復帰時の SortedTroves 再挿入に必要）。
- **Verification**: parity

#### CORE-BO-FR-011: adjustTroveInterestRate（単独 Trove の金利変更）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `adjustTroveInterestRate(uint256 _troveId, uint256 _newAnnualInterestRate, uint256 _upperHint, uint256 _lowerHint, uint256 _maxUpfrontFee)`
- **目的**: batch 非所属の active な Trove の年利を変更し、ソートリスト上の位置を更新する。
- **権限**: owner または `interestIndividualDelegateOf[_troveId].account`（個別 interest delegate）。**delegate の場合のみ**追加制約（rate 範囲・変更間隔）を受け、owner は受けない。
- **事前条件（Checks）**(コードの検査順):
  1. 未 shutdown
  2. `_newAnnualInterestRate` が `[MIN_ANNUAL_INTEREST_RATE, MAX_ANNUAL_INTEREST_RATE]` 内
  3. batch 非所属
  4. 呼出者が owner または delegate
  5. Trove が active
  6. 呼出者が delegate の場合: rate が delegate 設定の `[minInterestRate, maxInterestRate]` 内、かつ `lastInterestRateAdjTime + minInterestRateChangePeriod` 経過
  7. 新 rate ≠ 現 rate
  8. **premature 変更**（`block.timestamp < lastInterestRateAdjTime + INTEREST_RATE_ADJ_COOLDOWN`、cooldown は 7 日）の場合のみ: oracle live・upfront fee（`entireDebt` ベース・平均金利 7 日分）≤ `_maxUpfrontFee`・fee 加算後 ICR ≥ MCR・fee 加算後 TCR ≥ CCR。**cooldown 経過後の変更は無料で、ICR/TCR/oracle 検査なし**
- **動作（Effects）**:
  1. `activePool.mintAggInterestAndAccountForTroveChange(change, address(0))`（再分配 gains の適用を含む）
  2. `sortedTroves.reInsert(_troveId, _newAnnualInterestRate, hints)`
  3. `troveManager.onAdjustTroveInterestRate(...)`（記録値・`lastInterestRateAdjTime` 更新。CORE-TM 系）
- **revert / 早期 return**: `IsShutDown`；`InterestRateTooLow` / `InterestRateTooHigh`；`TroveInBatch`；`NotOwnerNorInterestManager`；`TroveNotActive`；`InterestNotInRange`（delegate 範囲外）；`DelegateInterestRateChangePeriodNotPassed`；`InterestRateNotNew`；premature 時 `NewOracleFailureDetected` / `UpfrontFeeTooHigh` / `ICRBelowMCR` / `TCRBelowCCR`。
- **発火イベント**: なし（BO 側）。
- **設計上のポイント**: premature fee は「redemption 回避のための直前の金利引き上げ」を有料化する仕組み。fee は debt に複利で乗る（mint されるのは AP 集計上の利息としてであり、借り手が JPYdf を受け取るわけではない）。
- **Verification**: parity / invariant=CORE-BO-INV-002

#### CORE-BO-FR-012: setInterestIndividualDelegate（個別 interest delegate の設定）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `setInterestIndividualDelegate(uint256 _troveId, address _delegate, uint128 _minInterestRate, uint128 _maxInterestRate, uint256 _newAnnualInterestRate, uint256 _upperHint, uint256 _lowerHint, uint256 _maxUpfrontFee, uint256 _minInterestRateChangePeriod)`
- **目的**: Trove の金利変更権限を第三者（cold/hot wallet 構成や自動運用 bot）に、許容 rate 範囲・最短変更間隔つきで委任する。delegate は金利のみ変更でき、債務・担保には触れない。
- **権限**: owner のみ（manager 不可）。
- **事前条件（Checks）**: 未 shutdown；Trove が active；呼出者が owner；`_minInterestRate`/`_maxInterestRate` がそれぞれグローバル範囲内；`_minInterestRate < _maxInterestRate`。`_minInterestRateChangePeriod` に下限はない（batch manager と異なり `MIN_INTEREST_RATE_CHANGE_PERIOD` の強制なし。0 も設定可能）。
- **動作（Effects）**:
  1. `interestIndividualDelegateOf[_troveId] = (_delegate, _minInterestRate, _maxInterestRate, _minInterestRateChangePeriod)`
  2. batch 所属中なら `removeFromBatch(_troveId, _newAnnualInterestRate, hints, _maxUpfrontFee)` を内部呼出（個別委任と batch は排他。離脱条件・fee は FR-018 のとおり）
- **revert / 早期 return**: `IsShutDown`；`TroveNotActive`；`NotBorrower`；`InterestRateTooLow` / `InterestRateTooHigh`；`MinGeMax`；batch 離脱時は FR-018 の revert 群。
- **発火イベント**: なし。
- **Verification**: parity / invariant=CORE-BO-INV-002

#### CORE-BO-FR-013: removeInterestIndividualDelegate（個別 interest delegate の解除）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `removeInterestIndividualDelegate(uint256 _troveId)`
- **目的**: 個別 interest delegate を解除する。
- **権限**: owner のみ。
- **事前条件（Checks）**: 呼出者が owner であることのみ（**shutdown 後・zombie でも実行可能**）。
- **動作（Effects）**: `delete interestIndividualDelegateOf[_troveId]`。
- **revert / 早期 return**: `NotBorrower`。
- **発火イベント**: なし。
- **Verification**: parity

#### CORE-BO-FR-014: registerBatchManager（batch manager の登録）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `registerBatchManager(uint128 _minInterestRate, uint128 _maxInterestRate, uint128 _currentInterestRate, uint128 _annualManagementFee, uint128 _minInterestRateChangePeriod)`
- **目的**: msg.sender を interest batch manager として登録する。登録時に自身の運用レンジ（min/max rate）・初期金利・年間管理 fee・最短金利変更間隔をコミットする。
- **権限**: permissionless（自己登録。1 アドレス 1 回のみ）。
- **事前条件（Checks）**(コードの検査順):
  1. 未 shutdown
  2. msg.sender が未登録（`interestBatchManagers[msg.sender].maxInterestRate == 0`）
  3. `_minInterestRate`/`_maxInterestRate` がグローバル範囲内、かつ `_minInterestRate < _maxInterestRate`
  4. `_currentInterestRate` が `[_minInterestRate, _maxInterestRate]` 内
  5. `_annualManagementFee ≤ MAX_ANNUAL_BATCH_MANAGEMENT_FEE`（10%。値は Constants.sol）
  6. `_minInterestRateChangePeriod ≥ MIN_INTEREST_RATE_CHANGE_PERIOD`（1 時間。値は Constants.sol）
- **動作（Effects）**:
  1. `interestBatchManagers[msg.sender] = (min, max, period)`（**以後変更・削除する手段はない**）
  2. `troveManager.onRegisterBatchManager(msg.sender, _currentInterestRate, _annualManagementFee)`（batch レコード作成。CORE-TM 系）
- **revert / 早期 return**: `IsShutDown`；`BatchManagerExists`；`InterestRateTooLow` / `InterestRateTooHigh`；`MinGeMax`；`InterestNotInRange`；`AnnualManagementFeeTooHigh`；`MinInterestRateChangePeriodTooLow`。
- **発火イベント**: なし（BO 側。batch レコード系は CORE-TM 系）。
- **設計上のポイント**: min/max/period の不変性は「加入後にレンジを広げて委任者の想定外の金利を設定する」rug を構造的に防ぐ。管理 fee はここでコミットした値から**引き下げのみ**可能（FR-016）。`maxInterestRate > 0` が登録済み判定の sentinel（グローバル最小金利 > 0 のため登録済みなら必ず正）。
- **Verification**: parity / invariant=CORE-BO-INV-004

#### CORE-BO-FR-015: setBatchManagerAnnualInterestRate（batch 一括金利変更）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `setBatchManagerAnnualInterestRate(uint128 _newAnnualInterestRate, uint256 _upperHint, uint256 _lowerHint, uint256 _maxUpfrontFee)`
- **目的**: batch manager が自分の batch 全体の年利を一括変更する。
- **権限**: 登録済み batch manager（msg.sender 自身の batch のみ）。
- **事前条件（Checks）**(コードの検査順):
  1. 未 shutdown
  2. msg.sender が登録済み
  3. 新 rate が**登録時にコミットした自身の `[minInterestRate, maxInterestRate]`** 内
  4. `batch.lastInterestRateAdjTime + minInterestRateChangePeriod`（登録時コミット値）経過
  5. **premature 変更**（rate が実際に変わり、かつ `block.timestamp < batch.lastInterestRateAdjTime + INTEREST_RATE_ADJ_COOLDOWN`）の場合のみ: oracle live・upfront fee（**batch 全債務** `entireDebtWithoutRedistribution` ベース）≤ `_maxUpfrontFee`・fee 込み TCR ≥ CCR（個別 ICR は検査しない）
- **動作（Effects）**:
  1. `activePool.mintAggInterestAndAccountForTroveChange(batchChange, msg.sender)`
  2. batch が空でなければ `sortedTroves.reInsertBatch(batchId, _newAnnualInterestRate, hints)`
  3. `troveManager.onSetBatchManagerAnnualInterestRate(...)`（batch 記録更新・fee は batch debt に複利。CORE-TM 系）
- **revert / 早期 return**: `IsShutDown`；`InvalidInterestBatchManager`；`InterestNotInRange`；`BatchInterestRateChangePeriodNotPassed`；premature 時 `NewOracleFailureDetected` / `UpfrontFeeTooHigh` / `TCRBelowCCR`。
- **発火イベント**: なし（BO 側）。
- **設計上のポイント**: 同率での再設定は `InterestRateNotNew` に相当する検査が**なく**許容される（その場合 premature 条件も成立せず fee なし。`lastInterestRateAdjTime` は TM 側仕様に従い更新される）。premature fee が batch 全債務に乗るため、頻繁な変更は batch 参加者全員のコストになる（`minInterestRateChangePeriod` のコミットが委任者への保護）。
- **Verification**: parity / invariant=CORE-BO-INV-004

#### CORE-BO-FR-016: lowerBatchManagementFee（batch 管理 fee の引下げ）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `lowerBatchManagementFee(uint256 _newAnnualManagementFee)`
- **目的**: batch manager が自身の年間管理 fee を引き下げる（引き上げは不可能）。
- **権限**: 登録済み batch manager。
- **事前条件（Checks）**: 未 shutdown；msg.sender が登録済み；`_newAnnualManagementFee < batch.annualManagementFee`（厳密に小さい）。
- **動作（Effects）**:
  1. `troveManager.onLowerBatchManagerAnnualFee(...)`（旧 fee での累積分を確定後、新 fee を記録。CORE-TM 系）
  2. `activePool.mintAggInterestAndAccountForTroveChange(batchChange, msg.sender)`（累積管理 fee の mint・weighted 値の付け替え）
- **revert / 早期 return**: `IsShutDown`；`InvalidInterestBatchManager`；`NewFeeNotLower`。
- **発火イベント**: なし（BO 側）。
- **設計上のポイント**: fee の単調減少により、加入時に見た fee が事後に不利化しないことを保証する（登録時 `MAX_ANNUAL_BATCH_MANAGEMENT_FEE` 以下＝以後常に上限以下）。
- **Verification**: parity / invariant=CORE-BO-INV-004

#### CORE-BO-FR-017: setInterestBatchManager（既存 Trove の batch 加入）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `setInterestBatchManager(uint256 _troveId, address _newBatchManager, uint256 _upperHint, uint256 _lowerHint, uint256 _maxUpfrontFee)`（public）
- **目的**: batch 非所属の active な Trove を登録済み batch に加入させ、金利を batch の現行値に切り替える。
- **権限**: owner のみ。
- **事前条件（Checks）**(コードの検査順):
  1. 未 shutdown
  2. Trove が active
  3. 呼出者が owner
  4. `_newBatchManager` が登録済み
  5. batch 非所属
  6. **upfront fee を常時徴収**（cooldown 経過の有無を問わない。Trove の `entireDebt` ベース・平均金利 7 日分）: oracle live・fee ≤ `_maxUpfrontFee`・fee 加算後 ICR ≥ **MCR + BCR**・fee 加算後 TCR ≥ CCR
- **動作（Effects）**:
  1. `interestBatchManagerOf[_troveId] = _newBatchManager`
  2. 個別 interest delegate が設定済みなら削除（排他）
  3. `activePool.mintAggInterestAndAccountForTroveChange(newBatchTroveChange, _newBatchManager)`（Trove 債務を batch の weighted 集計へ編入）
  4. `troveManager.onSetInterestBatchManager(...)`（Trove 記録のゼロ化と batch shares への編入。CORE-TM 系）
  5. `sortedTroves.remove(_troveId)` → `sortedTroves.insertIntoBatch(...)`（単独ノード → batch ノードへ移動）
- **revert / 早期 return**: `IsShutDown`；`TroveNotActive`；`NotBorrower`；`InvalidInterestBatchManager`；`TroveInBatch`；`NewOracleFailureDetected`；`UpfrontFeeTooHigh`；`ICRBelowMCRPlusBCR`；`TCRBelowCCR`。
- **発火イベント**: なし（BO 側）。
- **設計上のポイント**: fee を**無条件**に課すのは、自分が管理する batch への加入・離脱を繰り返すことで premature fee 判定を迂回し実質無料の金利変更を得る gaming の防止（コード内コメントの設計意図）。加入後の Trove は ICR 要求が MCR+BCR に強化される。
- **Verification**: parity / invariant=CORE-BO-INV-002, CORE-BO-INV-003

#### CORE-BO-FR-018: removeFromBatch（batch からの離脱）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol `_removeFromBatch(_kick=false)`）
- **シグネチャ**: `removeFromBatch(uint256 _troveId, uint256 _newAnnualInterestRate, uint256 _upperHint, uint256 _lowerHint, uint256 _maxUpfrontFee)`（public）
- **目的**: batch 所属 Trove を離脱させ、自己選択金利 `_newAnnualInterestRate` の単独 Trove に戻す。
- **権限**: owner のみ。
- **事前条件（Checks）**(コードの検査順):
  1. 未 shutdown
  2. Trove が active（zombie は不可。zombie はまず FR-008 で復帰させる）
  3. 呼出者が owner
  4. `_newAnnualInterestRate` がグローバル範囲内
  5. batch 所属であること
  6. **premature 変更**（`_newAnnualInterestRate ≠ batch.annualInterestRate` かつ `block.timestamp < trove.lastInterestRateAdjTime + INTEREST_RATE_ADJ_COOLDOWN`）の場合のみ: oracle live・upfront fee（Trove `entireDebt` ベース）≤ `_maxUpfrontFee`・fee 加算後 ICR ≥ **MCR**（離脱後は単独なので BCR 不要）・fee 加算後 TCR ≥ CCR
- **動作（Effects）**:
  1. `delete interestBatchManagerOf[_troveId]`
  2. zombie でなければ `sortedTroves.removeFromBatch(_troveId)` → `sortedTroves.insert(_troveId, _newAnnualInterestRate, hints)`
  3. `activePool.mintAggInterestAndAccountForTroveChange(batchChange, batchManager)`（batch weighted 値から Trove 分を分離し、新金利の単独 weighted 値を計上）
  4. `troveManager.onRemoveFromBatch(...)`（shares 清算・Trove 記録の独立化・新金利記録。CORE-TM 系）
- **revert / 早期 return**: `IsShutDown`；`TroveNotActive`；`NotBorrower`；`InterestRateTooLow` / `InterestRateTooHigh`；`TroveNotInBatch`；premature 時 `NewOracleFailureDetected` / `UpfrontFeeTooHigh` / `ICRBelowMCR` / `TCRBelowCCR`。
- **発火イベント**: なし（BO 側）。
- **設計上のポイント**: batch の現行金利と同率で離脱（または cooldown 経過後）なら fee なし。premature 判定の基準時刻は **Trove 側** `lastInterestRateAdjTime`（FR-015 の batch 側基準と異なる）。
- **Verification**: parity / invariant=CORE-BO-INV-002

#### CORE-BO-FR-019: kickFromBatch（shares ratio 劣化 batch からの強制退去）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol `_removeFromBatch(_kick=true)`）
- **シグネチャ**: `kickFromBatch(uint256 _troveId, uint256 _upperHint, uint256 _lowerHint)`
- **目的**: batch の「債務/shares 比」が `MAX_BATCH_SHARES_RATIO`（1e9。値は Constants.sol）を超えて劣化した場合に、第三者が Trove を batch から退去させられるようにする。
- **権限**: permissionless。
- **事前条件（Checks）**:
  1. 未 shutdown
  2. Trove が open（**zombie も対象**。FR-018 と異なり owner 検査・金利指定なし）
  3. batch 所属であること
  4. `batch.totalDebtShares × MAX_BATCH_SHARES_RATIO < batch.entireDebtWithoutRedistribution`（劣化していなければ revert）
- **動作（Effects）**: FR-018 の Effects と同一。ただし新金利は **batch の現行金利を引き継ぐ**ため premature 条件が成立せず、upfront fee・ICR/TCR 検査・oracle 取得は発生しない。zombie の場合はソートリスト操作をスキップ（batch 紐付けの解除と会計分離のみ）。
- **revert / 早期 return**: `IsShutDown`；`TroveNotOpen`；`TroveNotInBatch`；`BatchSharesRatioTooLow`（比が劣化していない）。
- **発火イベント**: なし（BO 側）。
- **設計上のポイント**: 債務/shares 比が上限に達した batch は TM 側の検査により新規参加・調整が不能になりうるため、permissionless な退去手段で「詰んだ batch」から Trove を救出する。金利・債務は変化しないため owner に不利益はない。
- **Verification**: parity

#### CORE-BO-FR-020: switchBatchManager（batch の乗り換え）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `switchBatchManager(uint256 _troveId, uint256 _removeUpperHint, uint256 _removeLowerHint, address _newBatchManager, uint256 _addUpperHint, uint256 _addLowerHint, uint256 _maxUpfrontFee)`
- **目的**: batch 所属 Trove を別の batch へ 1 トランザクションで乗り換えさせる。
- **権限**: owner のみ（内部の FR-018 / FR-017 の検査に従う）。
- **事前条件（Checks）**: batch 所属であること；`_newBatchManager ≠ 旧 batch manager`；以降は内部呼出の FR-018（旧 batch の**現行金利**で離脱 → premature 不成立で fee なし）と FR-017（新 batch へ加入 → **fee 常時徴収**・ICR ≥ MCR+BCR・TCR ≥ CCR）の全検査。
- **動作（Effects）**: `removeFromBatch(_troveId, oldBatch.annualInterestRate, removeHints, 0)` → `setInterestBatchManager(_troveId, _newBatchManager, addHints, _maxUpfrontFee)` の順に実行。
- **revert / 早期 return**: `TroveNotInBatch`；`BatchManagerNotNew`；ほか FR-018 / FR-017 の revert 群（shutdown 検査も内部呼出経由で実効）。
- **発火イベント**: なし（BO 側）。
- **設計上のポイント**: upfront fee は加入側で 1 回だけ徴収される（離脱は同率のため無料）。
- **Verification**: parity

#### CORE-BO-FR-021: shutdown（TCR < SCR によるブランチ shutdown）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `shutdown()`
- **目的**: ブランチ TCR が SCR を下回ったとき、誰でもブランチを恒久 shutdown できる。shutdown 後は closeTrove・claimCollateral 等を除く借入系操作が全停止し、TroveManager 側で urgent redemption が有効化される。
- **権限**: permissionless（ただし TCR < SCR の状態条件でゲート）。
- **事前条件（Checks）**:
  1. 未 shutdown（`hasBeenShutDown == false`。**一回性**）
  2. `priceFeed.fetchPrice()` が失敗を返す場合は**早期 return**。JPY更新が30h以上古い場合も対象だが、経過時間制限だけではoracle pauseを立てない。恒久shutdownは実行せず、利息は継続しurgent redemptionもまだ有効にならない。新しいJPY更新後に累積債務を含むTCRを再評価する
  3. `TCR = computeCR(ブランチ総 coll, 総 debt, price) < SCR`
- **動作（Effects）**（`_applyShutdown`）:
  1. `activePool.mintAggInterest()`（shutdown 時点までの集計利息を確定。以後ブランチの利息発生は停止。CORE-AP 系）
  2. `hasBeenShutDown = true`
  3. `troveManager.shutdown()`（`shutdownTime` 記録・ActivePool の shutdown フラグ設定。CORE-TM 系）
  4. `ShutDown(TCR)` を発火
- **revert / 早期 return**: shutdown 済み → `IsShutDown`；TCR ≥ SCR → `TCRNotBelowSCR`；oracle 失敗検出 → revert せず return（イベントなし）。
- **発火イベント**: `ShutDown`（CORE-BO-EVT-006）。
- **設計上のポイント**: TCRによるshutdownは不可逆。oracle失敗によるpause（FR-022）は `hasBeenShutDown` を立てず、利息も停止しない。
- **Verification**: parity / invariant=CORE-BO-INV-001

#### CORE-BO-FR-022: oracle失敗によるpauseと回復
- **Type**: Functional ｜ **Source**: BorrowerOperations.sol
- **シグネチャ**: `shutdownFromOracleFailure()` / `resumeFromOracleFailure()`
- **目的**: オラクル障害を恒久shutdownと分け、健全な価格を確認して再開する。
- **権限**: 登録済み `priceFeed` のみ。Owner権限と価格検証はPriceFeedProxyが担う。
- **動作（Effects）**: 障害時に `isOracleFailureShutdown = true` とする。既にpauseまたは恒久shutdownならno-op。resumeは同フラグを解除する。`hasBeenShutDown`、TroveManagerの `shutdownTime`、利息発生は変更しない。
- **利用制限**: 返済・担保追加だけの調整は価格取得なしで許可する。借入・担保引出・通常償還はresumeを待つ。清算は現在のsourceが有効な価格を返せば再開できる。`closeTrove` と恒久shutdown判定は、30h未満のJPY更新を含む現在の価格を要する。
- **revert / 早期 return**: 非priceFeed → `CallerNotPriceFeed`。
- **発火イベント**: BOではなし。Proxyの `SourceFailureHandled` / `OracleFailureShutdownResumed` を監視する。
- **Verification**: unit / integration / invariant=CORE-BO-INV-001

#### CORE-BO-FR-023: onLiquidateTrove（清算時の BO 側状態クリア）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `onLiquidateTrove(uint256 _troveId)`
- **目的**: TroveManager が Trove を清算した際、BO 側に残る Trove 単位の権限・委任状態を消去する。
- **権限**: `troveManager` のみ。
- **事前条件（Checks）**: 呼出者が troveManager であること。
- **動作（Effects）**: `_wipeTroveMappings(_troveId)` — `interestIndividualDelegateOf`・`interestBatchManagerOf`・`addManagerOf`・`removeManagerReceiverOf` を削除し、`AddManagerUpdated(_troveId, 0)`・`RemoveManagerAndReceiverUpdated(_troveId, 0, 0)` を発火。
- **revert / 早期 return**: 非 troveManager → `CallerNotTroveManager`。
- **発火イベント**: `AddManagerUpdated`（CORE-BO-EVT-008）、`RemoveManagerAndReceiverUpdated`（CORE-BO-EVT-009）。
- **設計上のポイント**: Trove ID は `(msg.sender, _owner, _ownerIndex)` 決定的のため再利用は通常起きないが、清算済み Trove に旧 manager 設定が残ると照会系・将来拡張で誤用されうるため明示的に消去する。
- **Verification**: parity

#### CORE-BO-FR-024: claimCollateral（清算余剰担保の引出）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol）
- **シグネチャ**: `claimCollateral()`
- **目的**: 清算ペナルティ超過分として CollSurplusPool に積まれた msg.sender 名義の余剰担保を引き出す。
- **権限**: permissionless（自分名義の surplus のみ。引出先は msg.sender）。
- **事前条件（Checks）/ 動作（Effects）**: BO は検査を行わず `collSurplusPool.claimColl(msg.sender)` へ委譲するのみ。残高検証・ゼロ残高時の revert・送金は CollSurplusPool 側の規定（CORE-CSP 系）。**shutdown 後も実行可能**。
- **revert / 早期 return**: CollSurplusPool 側の規定に従う。
- **発火イベント**: なし（BO 側）。
- **Verification**: parity

#### CORE-BO-FR-025: setAddManager（AddManager の設定）🔵
- **Type**: Functional ｜ **Source**: base 実装（Dependencies/AddRemoveManagers.sol）
- **シグネチャ**: `setAddManager(uint256 _troveId, address _manager)`
- **目的**: Trove への入金系操作（担保追加・返済）の許可先を設定する。
- **権限**: owner のみ。
- **事前条件（Checks）**: 呼出者が owner（`troveNFT.ownerOf(_troveId)`）であること（**shutdown 後も実行可能だが、NFT が存在する Trove＝active / zombie に限る**。closed / liquidated は NFT burn 済みのため `ownerOf` が revert する。ゼロアドレスも設定可）。
- **動作（Effects）**: `addManagerOf[_troveId] = _manager`；`AddManagerUpdated(_troveId, _manager)` 発火。
- **revert / 早期 return**: 非 owner → `NotBorrower`；NFT 不在（closed / liquidated / 未開設） → ERC721 `"ERC721: invalid token ID"`（`ownerOf` 内）。
- **設計上のポイント**: セマンティクスが特殊で、**ゼロ = 誰でも入金系操作可（既定）**・非ゼロ = owner＋当該アドレス（＋RemoveManager）のみ。第三者の操作を完全に拒否したい場合は owner 自身を設定する（コード内コメントの想定運用）。
- **発火イベント**: `AddManagerUpdated`（CORE-BO-EVT-008）。
- **Verification**: parity

#### CORE-BO-FR-026: setRemoveManagerWithReceiver（RemoveManager と receiver の設定）🔵
- **Type**: Functional ｜ **Source**: base 実装（Dependencies/AddRemoveManagers.sol）
- **シグネチャ**: `setRemoveManagerWithReceiver(uint256 _troveId, address _manager, address _receiver)`（public）
- **目的**: Trove からの出金系操作（担保引出・借入・閉鎖）の許可先と、引き出した資金の受取先を設定する。
- **権限**: owner のみ。
- **事前条件（Checks）**: 呼出者が owner；`_manager == 0` の場合は `_receiver == 0` であること（manager なしで receiver だけ残す状態を禁止）。
- **動作（Effects）**: `removeManagerReceiverOf[_troveId] = (_manager, _receiver)`；`RemoveManagerAndReceiverUpdated(_troveId, _manager, _receiver)` 発火。`(0,0)` 設定で解除（既定の「owner 以外不可」に戻る）。
- **revert / 早期 return**: `NotBorrower`；`EmptyManager`。
- **設計上のポイント**: receiver が実際に使われるのは **RemoveManager 本人が呼び出し、かつ receiver 非ゼロのときのみ**。owner 自身の呼出では常に owner が受取先（受取先の固定により、manager 権限が漏えいしても資金送付先は owner が指定した receiver に限定される）。RemoveManager は AddManager 権限を包含する。
- **発火イベント**: `RemoveManagerAndReceiverUpdated`（CORE-BO-EVT-009）。
- **Verification**: parity / SEC=CORE-BO-SEC-002

#### CORE-BO-FR-027: setRemoveManager（RemoveManager の設定・receiver は owner）🔵
- **Type**: Functional ｜ **Source**: base 実装（Dependencies/AddRemoveManagers.sol）
- **シグネチャ**: `setRemoveManager(uint256 _troveId, address _manager)`
- **目的**: receiver を現時点の owner に固定して RemoveManager を設定する簡易版。
- **権限**: owner のみ。
- **事前条件（Checks）/ 動作（Effects）**: `setRemoveManagerWithReceiver(_troveId, _manager, troveNFT.ownerOf(_troveId))` への委譲。receiver には**呼出時点の owner アドレスが明示的に格納**される（以後 NFT を譲渡しても receiver は自動追従しない）。
- **revert / 早期 return**: `NotBorrower`；`_manager == 0` は receiver（=owner、非ゼロ）が残るため `EmptyManager` で revert。**解除は本関数では不可能**で、FR-026 の `(0,0)` 設定でのみ行う。
- **発火イベント**: `RemoveManagerAndReceiverUpdated`（CORE-BO-EVT-009）。
- **Verification**: parity

#### CORE-BO-FR-028: view 関数群 🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol / AddRemoveManagers.sol / LiquityBase.sol）
- **目的**: ブランチパラメータ・委任状態・batch 登録状態の照会。すべて状態変更なし。
- **権限**: なし（view）。

| 関数 | 返り値の意味 |
| --- | --- |
| `CCR()` / `SCR()` / `MCR()` / `BCR()` | ブランチ別の閾値（immutable。AddressesRegistry 由来。値は [Parameters.md](../../../Parameters.md)） |
| `hasBeenShutDown()` | shutdown 済みなら true（不可逆） |
| `interestBatchManagerOf(troveId)` | 所属 batch manager（ゼロ = 非所属） |
| `getInterestBatchManager(account)` | batch manager 登録レコード `(minInterestRate, maxInterestRate, minInterestRateChangePeriod)`（未登録は全ゼロ） |
| `getInterestIndividualDelegateOf(troveId)` | 個別 delegate レコード `(account, minInterestRate, maxInterestRate, minInterestRateChangePeriod)`（未設定は全ゼロ） |
| `checkBatchManagerExists(account)` | `interestBatchManagers[account].maxInterestRate > 0`（登録済み判定。Zapper 等の外部参照用） |
| `addManagerOf(troveId)` | AddManager（ゼロ = 入金系は誰でも可） |
| `removeManagerReceiverOf(troveId)` | `(RemoveManager, receiver)`（ゼロ = owner 以外出金系不可） |
| `activePool()` | ブランチ ActivePool アドレス（LiquityBase 継承。規定は LIB 担当） |
| `getEntireBranchColl()` | ActivePool + DefaultPool の合計担保（LiquityBase 継承。TCR 計算の分子） |
| `getEntireBranchDebt()` | ActivePool + DefaultPool の合計債務（LiquityBase 継承。TCR 計算の分母） |

- **Verification**: parity

#### CORE-BO-FR-029: constructor（デプロイ時配線・初期化）🔵
- **Type**: Functional ｜ **Source**: base 実装（BorrowerOperations.sol / AddRemoveManagers.sol / LiquityBase.sol）
- **シグネチャ**: `constructor(IAddressesRegistry _addressesRegistry)`
- **目的**: AddressesRegistry からブランチ構成を一括取得して配線し、以後不変とする。
- **権限**: デプロイヤ（デプロイ手順の一部。CORE-AR 系の配線規定に従う）。
- **事前条件（Checks）**: `assert(MIN_DEBT > 0)`（ゼロ債務 Trove の開設を構造的に不能にする。🟡 DF 値でも成立（CORE-MOD-002 / CORE-LIB-FR-002））。
- **動作（Effects）**（継承 constructor 含む実行順）:
  1. （LiquityBase）`activePool` / `defaultPool` / `priceFeed` を取得し配線イベント発火
  2. （AddRemoveManagers）`troveNFT` を取得し `TroveNFTAddressChanged` 発火
  3. `collToken` / `WETH` / `CCR` / `SCR` / `MCR` / `BCR` / `troveManager` / `gasPoolAddress` / `collSurplusPool` / `sortedTroves` / `jpydfToken` を取得し、各 AddressChanged イベント発火
  4. `collToken.approve(address(activePool), type(uint256).max)`（BO 経由の担保移転を AP が pull できるようにする無限 allowance）
- **revert / 早期 return**: なし（assert 失敗時のみ Panic）。
- **発火イベント**: CORE-BO-EVT-001〜005, 007, 010〜012（配線系全件）。
- **設計上のポイント**: `troveManager` 等は immutable ではなく storage だが、setter が存在しないため事実上 constructor 後不変（CORE-BO-INV-005）。
- **Verification**: parity / deploy 検証


### TroveManager の機能要件（CORE-TM-FR-*）

#### CORE-TM-FR-001: batchLiquidateTroves（清算シーケンス）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol）
- **シグネチャ**: `batchLiquidateTroves(uint256[] memory _troveArray)`
- **目的**: 呼出側が指定した Trove 列のうち清算条件（ICR < MCR）を満たすものを一括清算し、SP offset・redistribution・余剰担保・ガス補償を確定させる。
- **権限**: permissionless（誰でも呼べる。清算 keeper を想定）。
- **事前条件（Checks）**:
  - `_troveArray.length > 0`
  - 個々の Trove は `status ∈ {active, zombie}` のもののみ対象（それ以外はスキップ）
  - `getCurrentICR(troveId, price) < MCR` のもののみ清算（満たさないものはスキップ）
- **動作（Effects）**:
  1. `priceFeed.fetchPrice()` で価格取得（state-changing。PriceFeedProxy＝[Oracle.md](./Oracle.md)）
  2. SP の利用可能額を決定: `jpydfInSPForOffsets = totalJpydfDeposits − min(MIN_JPYDF_IN_SP, totalJpydfDeposits)`。すなわち SP には常に最大 `MIN_JPYDF_IN_SP`（値は §7）を残し、それ以下しかなければ全額残す
  3. `_troveArray` を順に走査し、対象 Trove ごとに単一清算（CORE-TM-FR-002）を実行。`remainingJpydfInSPForOffsets` を各 Trove の `debtToOffset` 分減算しつつ、清算値・`TroveChange` を累計する（累計対象: `collGasCompensation`、Trove 1 件あたり固定の `ETH_GAS_COMPENSATION`、`debtDecrease += entireDebt`、`collDecrease += entireColl`、`appliedRedistJpydfDebtGain`、`oldWeightedRecordedDebt` / `newWeightedRecordedDebt`、`debtToOffset`、`collToSendToSP`、`debtToRedistribute`、`collToRedistribute`、`collSurplus`）
  4. `activePool.mintAggInterestAndAccountForTroveChange(troveChange, address(0))` で集計債務・加重債務を一括更新（CORE-AP 節）
  5. `totals.debtToOffset > 0 || totals.collToSendToSP > 0` なら `stabilityPool.offset(debtToOffset, collToSendToSP)`
  6. `_redistributeDebtAndColl` で redistribution 分を反映（CORE-TM-FR-003。0 なら no-op）
  7. `totals.collSurplus > 0` なら `activePool.sendColl(collSurplusPool, collSurplus)` で余剰担保を CollSurplusPool へ
  8. システムスナップショット更新: `totalStakesSnapshot = totalStakes`、`totalCollateralSnapshot = AP残高 − collGasCompensation + DP残高`（ガス補償分を除外）
  9. `Liquidation` イベント発火（CORE-TM-EVT-001）
  10. ガス補償支払: WETH `ETH_GAS_COMPENSATION × 清算件数` を GasPool から `msg.sender` へ `transferFrom`、担保ガス補償 `collGasCompensation` を ActivePool から `msg.sender` へ送付
- **revert / 早期 return**: 空配列 → `EmptyData`。1 件も清算されなかった（`troveChange.debtDecrease == 0`）→ `NothingToLiquidate`。
- **発火イベント**: `Liquidation`（CORE-TM-EVT-001）、Trove ごとに `TroveUpdated` / `TroveOperation`（CORE-TM-EVT-003/004）、batch 所属 Trove には `BatchUpdated(exitBatch)`（CORE-TM-EVT-006）。
- **設計上のポイント**: SP に `MIN_JPYDF_IN_SP` を残すのは SP の内部精度（P 値）保護のため。対象選定はすべて呼出側責務で、コントラクトは順序やソートを前提としない（LiquidationCandidateGetter＝CORE-LCG 節が off-chain 選定を補助）。担保ガス補償は SP offset 対象部分からのみ控除される（CORE-TM-FR-002）一方、WETH 補償は清算 1 件ごとに定額で支払われる。
- **Verification**: parity / invariant=CORE-TM-INV-001, CORE-TM-INV-002

#### CORE-TM-FR-002: 単一 Trove 清算と清算値の配分（SP offset / redistribution / ガス補償 / 余剰担保）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol 内部関数 `_liquidate` / `_getOffsetAndRedistributionVals` / `_getCollPenaltyAndSurplus` / `_getCollGasCompensation`）
- **シグネチャ**: internal（`batchLiquidateTroves` から Trove ごとに呼ばれる）
- **目的**: 1 Trove の entire 債務・担保（redistribution gain・未収利息込み）を、SP offset 分・redistribution 分・ガス補償・借り手への余剰担保に正確に分解し、Trove を閉鎖する。
- **権限**: internal のみ。
- **事前条件（Checks）**: 呼出側（FR-001）で status・ICR 検査済み。
- **動作（Effects）**:
  1. `_getLatestTroveData` で entire 値を確定し、batch 所属なら `_getLatestBatchData` も取得
  2. Trove の pending redistribution gain（債務・担保）を DefaultPool から ActivePool へ移動
  3. **配分計算**（`_getOffsetAndRedistributionVals(entireDebt, entireColl, jpydfInSPForOffsets, price)`）。結果は次の 3 分岐に帰着する:
     - **全額 SP offset**（`entireDebt ≤ jpydfInSPForOffsets`）: `debtToOffset = entireDebt`、`collSPPortion = entireColl`、redistribution なし
     - **部分 offset + redistribution**（`0 < jpydfInSPForOffsets < entireDebt`）: `debtToOffset = jpydfInSPForOffsets`、`collSPPortion = entireColl × debtToOffset / entireDebt`（担保は offset 債務比で按分）、残り `debtToRedistribute = entireDebt − debtToOffset` と残担保を redistribution へ
     - **全額 redistribution**（`jpydfInSPForOffsets == 0`）: offset なし、全債務・全担保を redistribution へ。**この場合、担保ガス補償は 0**（補償は SP 按分からのみ控除されるため）
  4. **担保ガス補償**: `collGasCompensation = min(collSPPortion / COLL_GAS_COMPENSATION_DIVISOR, COLL_GAS_COMPENSATION_CAP)`。divisor は 0.5% 相当。**`COLL_GAS_COMPENSATION_CAP` の値は DF 変更（🟡 CORE-MOD-003。値は [Parameters.md](../../../Parameters.md)）**。控除後の `collToOffset = collSPPortion − collGasCompensation` がペナルティ計算へ
  5. **ペナルティと余剰**（`_getCollPenaltyAndSurplus`）: `maxSeizedColl = debt × (1e18 + penaltyRatio) / price`、押収担保は `min(対象担保, maxSeizedColl)`、超過分が `collSurplus`。SP 分には `LIQUIDATION_PENALTY_SP`、redistribution 分には `LIQUIDATION_PENALTY_REDISTRIBUTION` を適用（値は [Parameters.md](../../../Parameters.md)）。redistribution 段では「offset 段で生じた surplus + 残担保」を入力とするため、**offset 由来の余剰が redistribution ペナルティに食われ得る**
  6. `_closeTrove(..., Status.closedByLiquidation)` で台帳から除去（TroveIds から swap-and-pop、SortedTroves から除去、stake を `totalStakes` から減算、`Troves` / `rewardSnapshots` を delete し status のみ `closedByLiquidation` を残す、TroveNFT burn。CORE-TM-FR-021 の内部規則と共通）
  7. 加重債務の差分計上: 非 batch は `oldWeightedRecordedDebt = trove.weightedRecordedDebt`、batch 所属は `old = batch.weightedRecordedDebt + (entireDebt − redistJpydfDebtGain) × batch.annualInterestRate`、`new = batch.entireDebtWithoutRedistribution × batch.annualInterestRate`（batch 側の記録債務には Trove 分が重複計上されているため加算 1 回・減算 2 回で正味 1 回の控除になる構造）。batch 所属はさらに管理feeの加重値を更新し `activePool.mintBatchManagementFeeAndAccountForChange` を呼ぶ
  8. `collSurplus > 0` なら `collSurplusPool.accountSurplus(owner, collSurplus)` で **NFT 所有者**に紐づけて余剰を記帳（CORE-CSP 節。後で所有者が claim）
  9. `borrowerOperations.onLiquidateTrove(troveId)` で BO 側の add/remove manager 等の付帯状態を消去（CORE-BO 節）
- **revert / 早期 return**: なし（呼出側で選別済み）。
- **発火イベント**: `TroveUpdated`（全フィールド 0）、`TroveOperation(liquidate)`、batch 所属なら `BatchUpdated(exitBatch)`。
- **設計上のポイント**: ペナルティ超過分を借り手に返す（collSurplus）ことで、清算が「ペナルティ付き精算」であり没収ではないという v2 の設計を実現。`ownerOf` は閉鎖前に取得される（burn 後は revert するため順序が本質的）。
- **Verification**: parity / unit（3 分岐・cap 境界・surplus 食い込み）

#### CORE-TM-FR-003: redistribution 会計（L_coll / L_jpydfDebt・error feedback・stake 規則）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol 内部関数 `_redistributeDebtAndColl` / `_updateStakeAndTotalStakes` / `_computeNewStake` / `_updateSystemSnapshots_excludeCollRemainder`）
- **シグネチャ**: internal
- **目的**: SP で吸収できなかった清算債務・担保を、全 active Trove に stake 比例で帰属させる遅延配賦（lazy distribution）の会計規則を定める。
- **権限**: internal のみ。
- **事前条件（Checks）**: `_debtToRedistribute == 0` なら即 return（このとき担保も必ず 0）。
- **動作（Effects）**:
  1. **error feedback 付き per-unit 計算**: `collNumerator = collToRedistribute × 1e18 + lastCollError_Redistribution`、`jpydfDebtNumerator = debtToRedistribute × 1e18 + lastJpydfDebtError_Redistribution` を作り、`perUnit = numerator / totalStakes`（床除算）、`lastError = numerator − perUnit × totalStakes` を保存。前回の床除算誤差を次回の分子に繰り越すことで累積誤差を 1 wei 未満/回に抑える
  2. `L_coll += collRewardPerUnitStaked`、`L_jpydfDebt += jpydfDebtRewardPerUnitStaked`（単調非減少）
  3. `defaultPool.increaseJpydfDebt(debtToRedistribute)`、`activePool.sendCollToDefaultPool(collToRedistribute)` — pending 分は DefaultPool に隔離される
  4. **Trove への帰属**は遅延適用: 各 Trove の未適用 gain は `stake × (L − rewardSnapshots[troveId]) / 1e18` で読み出し（CORE-TM-FR-009）、状態更新時に `rewardSnapshots` を現在値へ進めて確定する
  5. **stake 規則**: Trove の stake は `totalCollateralSnapshot == 0` なら `coll` そのもの、それ以外は `coll × totalStakesSnapshot / totalCollateralSnapshot`。両スナップショットは清算直後にのみ更新され（FR-001 step 8）、清算で失われた担保見合いで以後の stake が割り引かれる
- **revert / 早期 return**: 上記の 0 早期 return のみ。
- **発火イベント**: なし（`Liquidation` イベントが更新後の `L_coll` / `L_jpydfDebt` を運ぶ）。
- **設計上のポイント**: redistribution gain の配分は stake（≒担保）比例であり債務比例ではない。`stake` / `totalStakes` / `L_coll` / `L_jpydfDebt` は当該 TroveManager が担当する **branch-local** 状態であり、他担保ブランチとの共有・価格正規化・横断 redistribution は行わない。batch 所属 Trove も stake は個別に持つため、redistribution は batch 会計を経由せず Trove 個別に帰属する（FR-009 の按分規則と対応）。
- **Verification**: parity / invariant=CORE-TM-INV-002, CORE-TM-INV-006

#### CORE-TM-FR-004: redeemCollateral（通常 Redemption）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol、内部 `_redeemCollateralFromTrove` / `_applySingleRedemption` / `_updateBatchInterestPriorToRedemption`）
- **シグネチャ**: `redeemCollateral(address _redeemer, uint256 _jpydfAmount, uint256 _price, uint256 _redemptionRate, uint256 _maxIterations) → uint256 _redeemedAmount`
- **目的**: CollateralRegistry から委譲され、JPYdf `_jpydfAmount` 相当の担保を年利の低い Trove から順に償還する。ペッグ下方乖離の裁定経路。
- **権限**: CollateralRegistry のみ（`_requireCallerIsCollateralRegistry`）。fee 率 `_redemptionRate`・ブランチ間配分は CollateralRegistry が決定済み（CORE-CR 節）。
- **事前条件（Checks）**:
  - `msg.sender == collateralRegistry`
  - Trove 単位の適格性: `getCurrentICR(troveId, _price) < 100%`（`_100pct`）の Trove はスキップ（償還が当該 Trove の CR をさらに悪化させないため）。ICR 判定には通常価格 `_price` を使用
- **動作（Effects）**:
  1. 走査開始点の決定: `lastZombieTroveId != 0` なら**例外的にその zombie Trove から**開始（前回 Redemption の食べ残し優先消化）。それ以外は `sortedTroves.getLast()`（= 年利最低の Trove）
  2. `priceFeed.fetchRedemptionPrice()` で償還用価格を取得（通常価格と別系統。[Oracle.md](./Oracle.md)）
  3. `_maxIterations == 0` は無制限扱い。`troveId != 0 && remainingJpydf > 0 && _maxIterations > 0` の間ループ:
     a. 次候補を先に保存（zombie 開始時は `getLast()`、通常は `getPrev(troveId)` = 年利昇順で次）
     b. ICR < 100% ならスキップ
     c. batch 所属 Trove なら、同一 batch につき 1 回だけ `_updateBatchInterestPriorToRedemption` を実行（batch の記録債務を利息込みに確定し `lastDebtUpdateTime` 更新、ActivePool の加重債務・管理feeを更新）
     d. **lot 計算**: `jpydfLot = min(remainingJpydf, entireDebt)`、`correspondingColl = jpydfLot × 1e18 / redemptionPrice`、`collFee = correspondingColl × _redemptionRate / 1e18`、`collLot = correspondingColl − collFee`。**redemption fee は redeemer に渡らず担保として Trove に残る**（fee 分だけ当該 Trove の CR が改善する）
     e. **単一償還の適用**（`_applySingleRedemption`）: `newDebt = entireDebt − jpydfLot`、`newColl = entireColl − collLot`。非 batch は `Troves` の debt/coll/`lastDebtUpdateTime` を直接更新し加重債務差分（`old = trove.weightedRecordedDebt`、`new = newDebt × annualInterestRate`）を計上。batch 所属は batch データ再取得のうえ `newAmountForWeightedDebt = batch.entireDebtWithoutRedistribution + redistJpydfDebtGain − jpydfLot` で加重債務・管理feeを計上し、`mintBatchManagementFeeAndAccountForChange` 後、`_updateBatchShares` を **`_checkBatchSharesRatio = false`** で実行（`BatchSharesRatioTooHigh` による Redemption 阻害を防ぐ）。続けて stake 更新・pending redistribution gain の AP 移動・`rewardSnapshots` 更新
     f. **zombie 化**: `newDebt < MIN_DEBT`（値は `Constants.sol` / CORE-LIB-FR-002。🟡 CORE-MOD-002 で DF が引き上げ）なら、未 zombie の場合 `status = zombie` とし SortedTroves から除去（batch 所属は `removeFromBatch`）。さらに `newDebt > 0` なら `lastZombieTroveId = troveId`（次回最優先）。既に zombie で `newDebt == 0` になった場合はポインタを 0 にリセット
     g. 累計値更新後、次候補へ（`isZombieTrove` フラグは初回のみ）
  4. `Redemption` イベント発火（CORE-TM-EVT-002）
  5. `activePool.mintAggInterestAndAccountForTroveChange(totalsTroveChange, address(0))` で集計更新
  6. `activePool.sendColl(_redeemer, 総 collLot)` で担保（dToken、[dToken.md](./dToken.md)）を redeemer へ送付
  7. 償還実額 `totalsTroveChange.debtDecrease` を返す。**JPYdf の burn は行わない**（CollateralRegistry がブランチ横断で一括 burn する）
- **revert / 早期 return**: 呼出元不正 → `CallerNotCollateralRegistry`。償還 0 件でも revert しない（base が意図的に require を除去。ブランチ間配分の一部として空振りを許容）。
- **発火イベント**: Trove ごとに `TroveUpdated` または `BatchedTroveUpdated`、`TroveOperation(redeemCollateral)`、batch 所属なら `BatchUpdated(troveChange)`、`RedemptionFeePaidToTrove`（CORE-TM-EVT-005）。最後に `Redemption`。
- **設計上のポイント**: 走査は SortedTroves の年利昇順（リスト末尾＝最低金利から `getPrev` で遡上）であり、担保比率順ではない。低金利 Trove ほど償還リスクを負う、という v2 の金利設計の根幹。zombie 機構は「`MIN_DEBT` 未満の微小 Trove を列に放置すると逐次 Redemption が gas griefing される」ことへの対策で、zombie はリストから外れ通常walk に現れない。redistribution により zombie の債務が `MIN_DEBT` 以上に回復しても自動再 activate はされない（再挿入ヒントが必要なため。BO の `adjustZombieTrove`、または permissionless な `applyPendingDebt`〔CORE-BO-FR-008/010〕→ CORE-TM-FR-016 で復帰）。
- **Verification**: parity / unit（zombie 遷移・fee 残置・batch 経路）/ invariant=CORE-TM-INV-005

#### CORE-TM-FR-005: urgentRedemption（shutdown 後の緊急 Redemption）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol、内部 `_urgentRedeemCollateralFromTrove`）
- **シグネチャ**: `urgentRedemption(uint256 _jpydfAmount, uint256[] calldata _troveIds, uint256 _minCollateral)`
- **目的**: ブランチ shutdown 後に、ボーナス付き・順序自由の Redemption で当該ブランチの債務を速やかに解消させる。
- **権限**: permissionless（ただし shutdown 済みブランチのみ）。呼出者は自分の JPYdf を burn して担保を受け取る。
- **事前条件（Checks）**:
  - `shutdownTime != 0`（未 shutdown → `NotShutDown`）
  - `_jpydfAmount > 0`（→ `ZeroAmount`）
  - `jpydfToken.balanceOf(msg.sender) ≥ _jpydfAmount`（→ `NotEnoughJpydfBalance`）
  - Trove 単位: `status ∈ {active, zombie}` かつ `entireDebt > 0` のもののみ処理（それ以外はスキップ）。**ICR 下限チェックはない**（CR < 100% でも償還可）
- **動作（Effects）**:
  1. `priceFeed.fetchPrice()`（通常価格。shutdown 後は微小裁定を許容するため redemption price を使わない）
  2. 呼出側指定の `_troveIds` を**指定順に**処理（ソート前提なし）。`remainingJpydf == 0` で打ち切り。batch 所属 Trove は毎回 `_updateBatchInterestPriorToRedemption`（順序保証がないため batch 単位の重複排除はしない）
  3. **lot 計算（ボーナス付き）**: `jpydfLot = min(remainingJpydf, entireDebt)`、`collLot = jpydfLot × (1e18 + URGENT_REDEMPTION_BONUS) / price`（`URGENT_REDEMPTION_BONUS` の値は本書の定数表 / `Constants.sol`）。`collLot > entireColl` なら担保全量に切り詰め、`jpydfLot = entireColl × price / (1e18 + URGENT_REDEMPTION_BONUS)` へ逆算（CR がボーナス込み 100% 未満の Trove に対応）
  4. `_applySingleRedemption` を適用（FR-004 step e と同一規則・イベント）。**zombie 化は行わない**（順序自由なので微小 Trove による griefing が成立しない）
  5. 受領担保合計が `_minCollateral` 未満なら revert（スリッページ保護）
  6. `Redemption(_jpydfAmount, debtDecrease, collDecrease, 0, price, price)` 発火（fee は常に 0、redemptionPrice フィールドにも通常価格）
  7. `activePool.mintAggInterestAndAccountForTroveChange(totalsTroveChange, address(0))`（shutdown 後のため利息 mint は 0。集計債務・加重債務トラッカーの更新のみ）
  8. `activePool.sendColl(msg.sender, collDecrease)` で担保送付、`jpydfToken.burn(msg.sender, debtDecrease)` で **TroveManager 自身が JPYdf を burn**（通常 Redemption と異なる）
- **revert / 早期 return**: `NotShutDown` / `ZeroAmount` / `NotEnoughJpydfBalance` / `MinCollNotReached(uint256 実受領担保)`。
- **発火イベント**: Trove ごとに FR-004 と同じ組（`TroveOperation` は `redeemCollateral`）、最後に `Redemption`。
- **設計上のポイント**: ボーナス（プレミアム）は shutdown ブランチからの早期退出インセンティブ。balance 事前検査（`NotEnoughJpydfBalance`）は burn 失敗より明確なエラーを返すための先行ガード。
- **Verification**: parity / unit（担保切り詰め分岐・_minCollateral 境界）

#### CORE-TM-FR-006: shutdown（ブランチ shutdown の記録）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol）
- **シグネチャ**: `shutdown()`
- **目的**: ブランチ shutdown の時刻を記録し、ActivePool に shutdown フラグを伝播する。以後、利息発生は `shutdownTime` で凍結され（CORE-TM-FR-007）、`urgentRedemption` が解禁され、通常 Redemption の対象から外れる（CORE-TM-FR-012）。
- **権限**: BorrowerOperations のみ（`_requireCallerIsBorrowerOperations`）。shutdown 判定（TCR < SCR）と一回性の保証は BO 側の責務（CORE-BO 節）。
- **事前条件（Checks)**: `msg.sender == borrowerOperations` のみ。**TroveManager 自身は `shutdownTime == 0` を検査しない**（多重呼出防止は BO の require に依存）。
- **動作（Effects）**:
  1. `shutdownTime = block.timestamp`
  2. `activePool.setShutdownFlag()`（CORE-AP 節。利息集計の停止フラグ）
- **revert / 早期 return**: 呼出元不正 → `CallerNotBorrowerOperations`。
- **発火イベント**: なし（TroveManager からは無発火。BO 側のイベントで観測）。
- **Verification**: parity / unit（onlyBO）

#### CORE-TM-FR-007: 利息発生期間の決定（shutdown による凍結）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol 内部関数 `_getInterestPeriod`）
- **シグネチャ**: internal（`_getLatestTroveData` / `_getLatestBatchData` から使用）
- **目的**: Trove / Batch の未収利息（および batch 管理fee）の発生期間を定義し、shutdown 後の利息を凍結する。
- **権限**: internal のみ。
- **事前条件（Checks）**: なし。
- **動作（Effects）**: 期間は次の 3 分岐。
  1. `shutdownTime == 0`（稼働中）: `block.timestamp − lastDebtUpdateTime`
  2. `shutdownTime > 0` かつ `lastDebtUpdateTime < shutdownTime`: `shutdownTime − lastDebtUpdateTime`（shutdown 時点までの利息のみ）
  3. `shutdownTime > 0` かつ `lastDebtUpdateTime ≥ shutdownTime`: `0`（shutdown 後の更新以降は無利息）
  利息額は `weightedRecordedDebt × period / ONE_YEAR / 1e18`（LiquityBase `_calcInterest`。単利）。
- **revert / 早期 return**: なし。
- **発火イベント**: なし。
- **Verification**: parity / unit（3 分岐）

#### CORE-TM-FR-008: getCurrentICR（現在 ICR の算出）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol）
- **シグネチャ**: `getCurrentICR(uint256 _troveId, uint256 _price) → uint256`（public view）
- **目的**: 未適用 redistribution gain・未収利息・batch 管理feeをすべて織り込んだ entire 値で Trove の担保比率を返す。清算判定（FR-001）・Redemption 適格性判定（FR-004）の基準値。
- **権限**: なし（view）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**: `_getLatestTroveData` の `entireColl` / `entireDebt` に対し `LiquityMath._computeCR(coll, debt, price)` を返す（`debt == 0` のとき `type(uint256).max`）。
- **revert / 早期 return**: なし。
- **発火イベント**: なし。
- **Verification**: parity

#### CORE-TM-FR-009: getLatestTroveData（最新 Trove 状態の導出）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol、内部 `_getLatestTroveData` / `_getLatestTroveDataFromBatch`）
- **シグネチャ**: `getLatestTroveData(uint256 _troveId) → LatestTroveData`（external view）
- **目的**: 記録値（`Troves`）に未適用 redistribution gain・未収利息・batch 管理feeを合成した「いま精算した場合の Trove 状態」を返す。BO・HintHelpers・周辺レイヤーの基準 view。
- **権限**: なし（view）。
- **事前条件（Checks）**: なし（存在しない Trove はゼロ値）。
- **動作（Effects）**:
  1. **redistribution gain**（batch 共通）: `redistJpydfDebtGain = stake × (L_jpydfDebt − rewardSnapshots.jpydfDebt) / 1e18`、`redistCollGain = stake × (L_coll − rewardSnapshots.coll) / 1e18`
  2. **非 batch**: `recordedDebt = Troves.debt`、`weightedRecordedDebt = recordedDebt × annualInterestRate`、`accruedInterest = _calcInterest(weighted, period)`（period は CORE-TM-FR-007）。`entireDebt = recordedDebt + redistJpydfDebtGain + accruedInterest`、`entireColl = Troves.coll + redistCollGain`
  3. **batch 所属**: batch の最新値（FR-010）を取得し、`totalDebtShares > 0` のとき `recordedDebt` / `accruedInterest` / `accruedBatchManagementFee` を **batchDebtShares 比で按分**。`annualInterestRate` は batch 金利。`entireDebt = recordedDebt + redistJpydfDebtGain + accruedInterest + accruedBatchManagementFee`、`entireColl = Troves.coll + redistCollGain`（**redistribution gain は shares 按分ではなく Trove 個別の stake 基準** — 配賦が担保比例のため）。`lastInterestRateAdjTime = max(batch 側, Trove 側)`
- **返り値（LatestTroveData 構造体）**:

  | フィールド | 意味 |
  | --- | --- |
  | `entireDebt` | 記録債務 + redistribution 債務 gain + 未収利息（+ batch 管理fee） |
  | `entireColl` | 記録担保 + redistribution 担保 gain |
  | `redistJpydfDebtGain` / `redistCollGain` | 未適用 redistribution gain |
  | `accruedInterest` | 未収単利 |
  | `recordedDebt` | 記録上の債務（batch は shares 按分値） |
  | `annualInterestRate` | 実効年利（batch は batch 金利） |
  | `weightedRecordedDebt` | `recordedDebt × annualInterestRate`（集計利息の重み） |
  | `accruedBatchManagementFee` | 未収 batch 管理fee（非 batch は 0） |
  | `lastInterestRateAdjTime` | 直近金利変更時刻（batch は Trove と batch の大きい方） |
- **revert / 早期 return**: なし。
- **発火イベント**: なし。
- **Verification**: parity / unit（batch 按分・redistribution 個別帰属）

#### CORE-TM-FR-010: getLatestBatchData（最新 Batch 状態の導出）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol、内部 `_getLatestBatchData`）
- **シグネチャ**: `getLatestBatchData(address _batchAddress) → LatestBatchData`（external view）
- **目的**: batch の記録値に未収利息・未収管理feeを合成した最新状態を返す。
- **権限**: なし（view）。
- **事前条件（Checks）**: なし（未登録 batch はゼロ値）。
- **動作（Effects）**: `recordedDebt = batches.debt`、`weightedRecordedDebt = recordedDebt × annualInterestRate`、`accruedInterest = _calcInterest(weighted, period)`、`weightedRecordedBatchManagementFee = recordedDebt × annualManagementFee`、`accruedManagementFee = _calcInterest(同, period)`（period は batch の `lastDebtUpdateTime` 起点で CORE-TM-FR-007 に従う）。`entireDebtWithoutRedistribution = recordedDebt + accruedInterest + accruedManagementFee`、`entireCollWithoutRedistribution = batches.coll`。
- **返り値（LatestBatchData 構造体）**: `totalDebtShares` / `entireDebtWithoutRedistribution` / `entireCollWithoutRedistribution` / `accruedInterest` / `recordedDebt` / `annualInterestRate` / `weightedRecordedDebt` / `annualManagementFee` / `accruedManagementFee` / `weightedRecordedBatchManagementFee` / `lastDebtUpdateTime` / `lastInterestRateAdjTime`。**redistribution gain は含まない**（WithoutRedistribution の名のとおり。redistribution は Trove 個別に帰属するため batch 集計には現れない）。
- **revert / 早期 return**: なし。
- **発火イベント**: なし。
- **Verification**: parity

#### CORE-TM-FR-011: getTroveAnnualInterestRate（実効年利の解決）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol）
- **シグネチャ**: `getTroveAnnualInterestRate(uint256 _troveId) → uint256`（external view）
- **目的**: batch 所属なら batch 金利、非所属なら Trove 個別金利を返す（個別金利フィールドは batch 所属時 0 のため、生値ではなくこの view が実効金利の正）。
- **権限**: なし（view）。
- **動作（Effects）**: `interestBatchManager != address(0)` なら `batches[batch].annualInterestRate`、それ以外は `Troves[_troveId].annualInterestRate`。
- **revert / 早期 return**: なし。
- **発火イベント**: なし。
- **Verification**: parity

#### CORE-TM-FR-012: getUnbackedPortionPriceAndRedeemability（非裏付け債務と redeem 可否）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol）
- **シグネチャ**: `getUnbackedPortionPriceAndRedeemability() → (uint256 unbackedPortion, uint256 price, bool redeemable)`
- **目的**: CollateralRegistry がブランチ間で Redemption 量を配分する際の入力（SP で裏付けられていない債務量・現在価格・当該ブランチが redeem 対象か）を 1 回の呼び出しで返す。
- **権限**: permissionless。**view ではない**（`priceFeed.fetchPrice()` が state-changing のため nonpayable）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**:
  1. `unbackedPortion = max(getEntireBranchDebt() − SP.getTotalJpydfDeposits(), 0)`
  2. `price = fetchPrice()`（[Oracle.md](./Oracle.md)）
  3. `redeemable = （TCR ≥ SCR）かつ（shutdownTime == 0）`。TCR 判定には通常価格を使用。**この条件を満たさないブランチは通常 Redemption の配分から除外される**（unredeemable 条件。CORE-CR 節が参照）
- **revert / 早期 return**: なし（fetchPrice の失敗はそのまま伝播）。
- **発火イベント**: なし（PriceFeed 側のイベントは別）。
- **設計上のポイント**: SCR を下回った（または shutdown 済みの）ブランチを redeem 対象から外すことで、危機状態ブランチの担保流出を urgentRedemption（FR-005）側の経路に限定する。
- **Verification**: parity / unit（redeemable 境界）

#### CORE-TM-FR-013: 自明 view getter 群 🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol / LiquityBase.sol）
- **シグネチャ**: 下表（すべて view）
- **目的**: 状態変数・接続先の素朴な読み出し。
- **権限**: なし。
- **動作（Effects）**:

  | 関数 | 返り値の意味 |
  | --- | --- |
  | `CCR()` | ブランチ CCR（immutable。値は [Parameters.md](../../../Parameters.md)） |
  | `Troves(uint256)` | Trove 構造体の生値 10 フィールド（**pending 利息・redistribution 未反映**。実効値は FR-009） |
  | `rewardSnapshots(uint256)` | `(coll, jpydfDebt)` = 当該 Trove の L 値スナップショット |
  | `batchIds(uint256)` | 登録済み batch manager のアドレス（登録順・削除なし） |
  | `lastZombieTroveId()` | 部分 redeem 済み zombie ポインタ（0 = なし） |
  | `shutdownTime()` | shutdown 時刻（0 = 稼働中） |
  | `getTroveIdsCount()` | `TroveIds.length`（active + zombie 件数） |
  | `getTroveFromTroveIdsArray(uint256)` | `TroveIds[i]`（範囲外は revert。off-chain ヒント計算用） |
  | `getTroveStatus(uint256)` | `Status`（uint8。0 nonExistent / 1 active / 2 closedByOwner / 3 closedByLiquidation / 4 zombie） |
  | `troveNFT()` / `borrowerOperations()` / `stabilityPool()` / `sortedTroves()` / `activePool()` | 接続先アドレス（constructor 固定） |
  | `getEntireBranchColl()` | ActivePool + DefaultPool の担保残高合計（LiquityBase 継承） |
  | `getEntireBranchDebt()` | ActivePool + DefaultPool の JPYdf 債務合計（LiquityBase 継承） |
- **revert / 早期 return**: 配列 getter の範囲外アクセスのみ。
- **発火イベント**: なし。
- **Verification**: parity

#### CORE-TM-FR-014: onOpenTrove（Trove 開設の記録）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol）
- **シグネチャ**: `onOpenTrove(address _owner, uint256 _troveId, TroveChange memory _troveChange, uint256 _annualInterestRate)`
- **目的**: BO で検証済みの開設を台帳に記録する（検証・資金移動・SortedTroves への挿入は BO 側。CORE-BO 節）。
- **権限**: BorrowerOperations のみ。
- **事前条件（Checks）**: `msg.sender == borrowerOperations` のみ（入力検証は BO を信頼）。
- **動作（Effects）**:
  1. `stake = _computeNewStake(collIncrease)`（CORE-TM-FR-003 の規則）
  2. `Troves[_troveId]` を設定: `debt = debtIncrease + upfrontFee`、`coll = collIncrease`、`stake`、`status = active`、`arrayIndex = TroveIds.length`、`lastDebtUpdateTime = lastInterestRateAdjTime = block.timestamp`、`annualInterestRate = _annualInterestRate`
  3. `TroveIds.push`、`totalStakes += stake`
  4. `troveNFT.mint(_owner, _troveId)`（CORE-TN 節）
  5. `rewardSnapshots` を現在の L 値に設定
- **revert / 早期 return**: `CallerNotBorrowerOperations`。
- **発火イベント**: `TroveUpdated`、`TroveOperation(openTrove)`（upfrontFee は `_debtIncreaseFromUpfrontFee` で別掲）。
- **設計上のポイント**: SortedTroves への挿入は BO が行う（TM は台帳のみ）。upfront fee は記録債務に算入される。
- **Verification**: parity

#### CORE-TM-FR-015: onOpenTroveAndJoinBatch（batch 加入付き開設）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol）
- **シグネチャ**: `onOpenTroveAndJoinBatch(address _owner, uint256 _troveId, TroveChange memory _troveChange, address _batchAddress, uint256 _batchColl, uint256 _batchDebt)`
- **目的**: 開設と同時に batch に加入する Trove の記録。債務は Trove に直接記録せず batch shares として持たせる。
- **権限**: BorrowerOperations のみ。
- **事前条件（Checks）**: `msg.sender == borrowerOperations`。内部 `assert(_troveChange.debtIncrease > 0)`。
- **動作（Effects）**:
  1. `Troves[_troveId]`: `coll = collIncrease`、`stake`、`status = active`、`arrayIndex`、`interestBatchManager = _batchAddress`、`lastInterestRateAdjTime = block.timestamp`（**`debt` と `lastDebtUpdateTime` は設定しない** — batch 側で管理）
  2. `rewardSnapshots` 設定、`TroveIds.push`
  3. `_updateBatchShares(..., _checkBatchSharesRatio = true)` で shares 発行・batch 債務/担保更新（CORE-TM-FR-027）
  4. `totalStakes += stake`、`troveNFT.mint`
- **revert / 早期 return**: `CallerNotBorrowerOperations`／shares 比率超過 → `BatchSharesRatioTooHigh`（FR-027）。
- **発火イベント**: `BatchedTroveUpdated`、`TroveOperation(openTroveAndJoinBatch)`、`BatchUpdated(joinBatch)`（加入 Trove の upfront fee は個別費用のため `_debtIncreaseFromUpfrontFee = 0`）。
- **Verification**: parity

#### CORE-TM-FR-016: setTroveStatusToActive（zombie からの復帰）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol）
- **シグネチャ**: `setTroveStatusToActive(uint256 _troveId)`
- **目的**: BO の `adjustZombieTrove`（債務を `MIN_DEBT` 以上に戻し SortedTroves に再挿入する操作）および `applyPendingDebt`（redistribution 等で `entireDebt ≥ MIN_DEBT` に回復した zombie を第三者が permissionless に復帰させる経路。CORE-BO-FR-010）から呼ばれ、status を active に戻す。
- **権限**: BorrowerOperations のみ。
- **事前条件（Checks）**: `msg.sender == borrowerOperations`（zombie であることの検証は BO 側）。
- **動作（Effects）**: `status = active`。`lastZombieTroveId == _troveId` ならポインタを 0 にリセット。
- **revert / 早期 return**: `CallerNotBorrowerOperations`。
- **発火イベント**: なし（BO 側の操作イベントで観測）。
- **Verification**: parity

#### CORE-TM-FR-017: onAdjustTrove（Trove 調整の記録）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol）
- **シグネチャ**: `onAdjustTrove(uint256 _troveId, uint256 _newColl, uint256 _newDebt, TroveChange calldata _troveChange)`
- **目的**: 非 batch Trove の担保・債務調整（redistribution gain・利息適用済みの確定値）を記録する。
- **権限**: BorrowerOperations のみ。
- **事前条件（Checks）**: `msg.sender == borrowerOperations`。
- **動作（Effects）**:
  1. `coll = _newColl`、`debt = _newDebt`、`lastDebtUpdateTime = block.timestamp`
  2. pending redistribution gain（`appliedRedist*`）を DefaultPool → ActivePool へ移動
  3. stake 再計算（`_updateStakeAndTotalStakes`）、`rewardSnapshots` 更新
- **revert / 早期 return**: `CallerNotBorrowerOperations`。
- **発火イベント**: `TroveUpdated`、`TroveOperation(adjustTrove)`。
- **Verification**: parity

#### CORE-TM-FR-018: onAdjustTroveInterestRate（個別金利変更の記録）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol）
- **シグネチャ**: `onAdjustTroveInterestRate(uint256 _troveId, uint256 _newColl, uint256 _newDebt, uint256 _newAnnualInterestRate, TroveChange calldata _troveChange)`
- **目的**: 非 batch Trove の年利変更（利息・redistribution 適用後の確定値と新金利）を記録する。
- **権限**: BorrowerOperations のみ。
- **事前条件（Checks）**: `msg.sender == borrowerOperations`。
- **動作（Effects）**:
  1. `coll` / `debt` / `annualInterestRate` を更新、`lastDebtUpdateTime = lastInterestRateAdjTime = block.timestamp`
  2. pending redistribution gain を AP へ移動、`rewardSnapshots` 更新（**stake は再計算しない** — BO 側で担保変化を伴わない操作のため）
- **revert / 早期 return**: `CallerNotBorrowerOperations`。
- **発火イベント**: `TroveUpdated`、`TroveOperation(adjustTroveInterestRate)`（`_debtChangeFromOperation` / `_collChangeFromOperation` は 0、upfront fee は `_debtIncreaseFromUpfrontFee`）。
- **Verification**: parity

#### CORE-TM-FR-019: onAdjustTroveInsideBatch（batch 内 Trove 調整の記録）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol）
- **シグネチャ**: `onAdjustTroveInsideBatch(uint256 _troveId, uint256 _newTroveColl, uint256 _newTroveDebt, TroveChange memory _troveChange, address _batchAddress, uint256 _newBatchColl, uint256 _newBatchDebt)`
- **目的**: batch 所属 Trove の担保・債務調整を、Trove の担保と batch shares の両面で記録する。`_newBatchColl` / `_newBatchDebt` は Trove 変更前の batch 全体値（利息・管理fee適用後）。
- **権限**: BorrowerOperations のみ。
- **事前条件（Checks）**: `msg.sender == borrowerOperations`。内部 `assert(_newTroveDebt > 0)`。
- **動作（Effects）**:
  1. `Troves.coll = _newTroveColl`、`rewardSnapshots` 更新、stake 再計算
  2. `_updateBatchShares(..., true)` で shares・batch 債務/担保を更新（FR-027）
  3. pending redistribution gain を AP へ移動
- **revert / 早期 return**: `CallerNotBorrowerOperations` / `BatchSharesRatioTooHigh`。
- **発火イベント**: `BatchedTroveUpdated`、`TroveOperation(adjustTrove)`（年利は batch 金利）、`BatchUpdated(troveChange)`。
- **Verification**: parity

#### CORE-TM-FR-020: onApplyTroveInterest（利息・redistribution 適用の記録）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol）
- **シグネチャ**: `onApplyTroveInterest(uint256 _troveId, uint256 _newTroveColl, uint256 _newTroveDebt, address _batchAddress, uint256 _newBatchColl, uint256 _newBatchDebt, TroveChange calldata _troveChange)`
- **目的**: BO の `applyPendingDebt`（permissionless な利息・redistribution の確定操作）の状態記録。zombie の債務復元にも使われる。
- **権限**: BorrowerOperations のみ。
- **事前条件（Checks）**: `msg.sender == borrowerOperations`。batch 経路では内部 `assert(_newTroveDebt > 0)`。
- **動作（Effects）**:
  1. `Troves.coll = _newTroveColl`
  2. batch 所属: `_updateBatchShares(..., true)`、`BatchUpdated(applyBatchInterestAndFee)`（イベントの debt/coll は引数の batch 全体値）。非 batch: `Troves.debt = _newTroveDebt`、`lastDebtUpdateTime = block.timestamp`
  3. pending redistribution gain を AP へ移動、`rewardSnapshots` 更新
- **revert / 早期 return**: `CallerNotBorrowerOperations` / `BatchSharesRatioTooHigh`。
- **発火イベント**: （batch 時）`BatchUpdated(applyBatchInterestAndFee)`、`TroveUpdated`、`TroveOperation(applyPendingDebt)`。
- **Verification**: parity

#### CORE-TM-FR-021: onCloseTrove（Trove 閉鎖の記録）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol、内部 `_closeTrove` / `_removeTroveId`）
- **シグネチャ**: `onCloseTrove(uint256 _troveId, TroveChange memory _troveChange, address _batchAddress, uint256 _newBatchColl, uint256 _newBatchDebt)`
- **目的**: 借り手による Trove 閉鎖（debt 全額返済済み）を台帳から除去する。
- **権限**: BorrowerOperations のみ。
- **事前条件（Checks）**:
  - `msg.sender == borrowerOperations`
  - 「ブランチ未 shutdown または清算による閉鎖」の場合、最後の 1 Trove は閉じられない（`TroveIds.length == 1` → `OnlyOneTroveLeft`）。**shutdown 後の owner 閉鎖は最後の 1 件でも可**
- **動作（Effects）**（`_closeTrove(..., Status.closedByOwner)`）:
  1. `TroveIds` から swap-and-pop で除去（末尾 Trove の `arrayIndex` を付け替え）
  2. batch 所属: active なら `sortedTroves.removeFromBatch`、zombie でポインタ一致なら `lastZombieTroveId = 0`、`_removeTroveSharesFromBatch` で batch から控除（`batchDebtDecrease = newTroveDebt − upfrontFee − appliedRedistJpydfDebtGain`、`batchCollDecrease = newTroveColl − appliedRedistCollGain` を引数の batch 全体値から減算し、Trove の shares を全消去・`interestBatchManager = 0`）。非 batch: active なら `sortedTroves.remove`、zombie ポインタ一致ならリセット
  3. `totalStakes −= stake`
  4. `delete Troves[_troveId]` 後に `status = closedByOwner` のみ再設定、`delete rewardSnapshots[_troveId]`
  5. `troveNFT.burn(_troveId)`
  6. pending redistribution gain を AP へ移動
- **revert / 早期 return**: `CallerNotBorrowerOperations` / `OnlyOneTroveLeft`。
- **発火イベント**: `TroveUpdated`（全 0）、`TroveOperation(closeTrove)`、batch 所属なら `BatchUpdated(exitBatch)`。
- **設計上のポイント**: 「最後の 1 Trove」制約は redistribution の受け皿（totalStakes > 0）を常に確保するため。閉鎖後も `status` だけは残り、TroveNFT の再 mint 防止・履歴判別に使われる。
- **Verification**: parity / invariant=CORE-TM-INV-001, CORE-TM-INV-003

#### CORE-TM-FR-022: onRegisterBatchManager（batch manager 登録）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol）
- **シグネチャ**: `onRegisterBatchManager(address _account, uint256 _annualInterestRate, uint256 _annualManagementFee)`
- **目的**: BO で検証済みの batch manager 登録（金利・管理fee・金利レンジは BO 側で検証）を記録する。
- **権限**: BorrowerOperations のみ。
- **事前条件（Checks）**: `msg.sender == borrowerOperations`。
- **動作（Effects）**: `batches[_account]` に `arrayIndex = batchIds.length`、`annualInterestRate`、`annualManagementFee`、`lastInterestRateAdjTime = block.timestamp` を設定し、`batchIds.push(_account)`。
- **revert / 早期 return**: `CallerNotBorrowerOperations`。
- **発火イベント**: `BatchUpdated(registerBatchManager, debt=0, coll=0, totalDebtShares=0)`。
- **Verification**: parity

#### CORE-TM-FR-023: onLowerBatchManagerAnnualFee（batch 管理fee引き下げ）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol）
- **シグネチャ**: `onLowerBatchManagerAnnualFee(address _batchAddress, uint256 _newColl, uint256 _newDebt, uint256 _newAnnualManagementFee)`
- **目的**: 管理feeの引き下げ（引き下げのみ許す検証は BO 側）を、利息・fee適用後の batch 確定値とともに記録する。
- **権限**: BorrowerOperations のみ。
- **事前条件（Checks）**: `msg.sender == borrowerOperations`。
- **動作（Effects）**: `batches[_batchAddress]` の `coll` / `debt` / `annualManagementFee` を更新、`lastDebtUpdateTime = block.timestamp`（`lastInterestRateAdjTime` は変更しない）。
- **revert / 早期 return**: `CallerNotBorrowerOperations`。
- **発火イベント**: `BatchUpdated(lowerBatchManagerAnnualFee)`。
- **Verification**: parity

#### CORE-TM-FR-024: onSetBatchManagerAnnualInterestRate（batch 金利変更）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol）
- **シグネチャ**: `onSetBatchManagerAnnualInterestRate(address _batchAddress, uint256 _newColl, uint256 _newDebt, uint256 _newAnnualInterestRate, uint256 _upfrontFee)`
- **目的**: batch 金利変更を記録する。`_upfrontFee` は premature adjustment 時に batch 債務へ課された fee（イベント表示用に受け取る）。
- **権限**: BorrowerOperations のみ。
- **事前条件（Checks）**: `msg.sender == borrowerOperations`。
- **動作（Effects）**: `coll` / `debt` / `annualInterestRate` を更新、`lastDebtUpdateTime = lastInterestRateAdjTime = block.timestamp`。
- **revert / 早期 return**: `CallerNotBorrowerOperations`。
- **発火イベント**: `BatchUpdated(setBatchManagerAnnualInterestRate, _debtIncreaseFromUpfrontFee = _upfrontFee)`（batch 全体に課された upfront fee を唯一ここで batch イベントに含める）。
- **Verification**: parity

#### CORE-TM-FR-025: onSetInterestBatchManager（既存 Trove の batch 加入）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol）
- **シグネチャ**: `onSetInterestBatchManager(OnSetInterestBatchManagerParams calldata _params)`（params: `troveId, troveColl, troveDebt, troveChange, newBatchAddress, newBatchColl, newBatchDebt`）
- **目的**: 既存の非 batch Trove を batch に加入させる。個別債務の記録を消し、batch shares に移管する。
- **権限**: BorrowerOperations のみ。
- **事前条件（Checks）**: `msg.sender == borrowerOperations`。内部 `assert(_params.troveDebt > 0)`。
- **動作（Effects）**:
  1. `rewardSnapshots` 更新
  2. Trove の個別債務状態を消去: `debt = 0`、`annualInterestRate = 0`、`lastDebtUpdateTime = 0`、`coll = troveColl`（entire 値）
  3. `interestBatchManager = newBatchAddress`、`lastInterestRateAdjTime = block.timestamp`
  4. `troveChange.collIncrease = troveColl − appliedRedistCollGain`、`troveChange.debtIncrease = troveDebt − appliedRedistJpydfDebtGain − upfrontFee` を構成して `_updateBatchShares(..., true)`（FR-027。Trove の entire 債務全量分の shares が発行される）
  5. pending redistribution gain を AP へ移動
- **revert / 早期 return**: `CallerNotBorrowerOperations` / `BatchSharesRatioTooHigh`。
- **発火イベント**: `BatchedTroveUpdated`、`TroveOperation(setInterestBatchManager)`（debt/coll の `ChangeFromOperation` は 0）、`BatchUpdated(joinBatch)`。
- **Verification**: parity

#### CORE-TM-FR-026: onRemoveFromBatch（Trove の batch 離脱）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol、内部 `_removeTroveSharesFromBatch`）
- **シグネチャ**: `onRemoveFromBatch(uint256 _troveId, uint256 _newTroveColl, uint256 _newTroveDebt, TroveChange memory _troveChange, address _batchAddress, uint256 _newBatchColl, uint256 _newBatchDebt, uint256 _newAnnualInterestRate)`
- **目的**: batch 所属 Trove を離脱させ、個別金利の Trove として債務記録を復元する。
- **権限**: BorrowerOperations のみ。
- **事前条件（Checks）**: `msg.sender == borrowerOperations`。
- **動作（Effects）**:
  1. `_removeTroveSharesFromBatch`: batch から `totalDebtShares −= trove.batchDebtShares`、`debt = _newBatchDebt − (newTroveDebt − upfrontFee − appliedRedistJpydfDebtGain)`、`coll = _newBatchColl − (newTroveColl − appliedRedistCollGain)`、`lastDebtUpdateTime = block.timestamp`。Trove 側 `interestBatchManager = 0`、`batchDebtShares = 0`（redistribution 分は shares 化→即控除が相殺されるため省略。利息・管理feeは shares 比例ゆえ shares 控除で完結する）
  2. Trove の個別状態を復元: `debt = _newTroveDebt`（entire 値）、`coll = _newTroveColl`、`lastDebtUpdateTime = lastInterestRateAdjTime = block.timestamp`、`annualInterestRate = _newAnnualInterestRate`
  3. `rewardSnapshots` 更新、pending redistribution gain を AP へ移動
- **revert / 早期 return**: `CallerNotBorrowerOperations`。
- **発火イベント**: `TroveUpdated`、`TroveOperation(removeFromBatch)`、`BatchUpdated(exitBatch)`。
- **Verification**: parity / invariant=CORE-TM-INV-004

#### CORE-TM-FR-027: batch debt shares の更新規則（_updateBatchShares）🔵
- **Type**: Functional ｜ **Source**: base 実装（TroveManager.sol 内部関数 `_updateBatchShares` / `_requireBelowMaxSharesRatio`）
- **シグネチャ**: internal（FR-004/015/019/020/025 から使用）
- **目的**: batch 債務に対する Trove 持分を shares で管理する際の発行・償却・整合規則を定める。
- **権限**: internal のみ。
- **事前条件（Checks）**: 債務**増加**時（`_batchDebt > 0`）かつ `_checkBatchSharesRatio == true` のとき、`currentShares × MAX_BATCH_SHARES_RATIO < _batchDebt` なら revert（debt/shares 比が `MAX_BATCH_SHARES_RATIO`、値は §7、を超えた batch への追加を拒否）。
- **動作（Effects）**:
  1. 正味債務変化を算出: `増分 = debtIncrease + upfrontFee + appliedRedistJpydfDebtGain` と `debtDecrease` を相殺して片側に正規化
  2. 変化なし: `batches.debt = _batchDebt`（利息・管理fee込みの最新値へ refresh のみ）
  3. 増加: `_batchDebt == 0` なら `sharesDelta = 増分`（初期 1:1）、それ以外は比率検査後 `sharesDelta = currentShares × 増分 / _batchDebt`。Trove の `batchDebtShares` と batch の `totalDebtShares` に加算、`debt = _batchDebt + 増分`
  4. 減少: `_newTroveDebt == 0` のとき（Redemption による全額償還のみ発生）は丸め残りを避けるため **Trove の shares を全消去**し `totalDebtShares` から控除（Trove は batch に残留 — 離脱させると UX が悪いため）。それ以外は `sharesDelta = currentShares × 減少分 / _batchDebt` を控除
  5. `lastDebtUpdateTime = block.timestamp`
  6. 担保も同様に正味変化を計算し、`batches.coll` を加減算（shares は使わない）
- **revert / 早期 return**: `BatchSharesRatioTooHigh`（増加かつ検査有効時のみ。Redemption 経路は検査無効＝FR-004）。
- **発火イベント**: なし（呼出元のイベントで観測）。
- **設計上のポイント**: shares 制は利息・管理feeの按分を O(1) にするための仕組み。debt/shares 比は利息累積で単調に上がり、`MAX_BATCH_SHARES_RATIO` 到達後は当該 batch への債務追加が恒久不能（base コメント: 年率 10% 複利でも上限到達まで 200 年超）。その場合 batch は新アドレスへ移行する運用。
- **Verification**: parity / unit（初期発行・全額償還・比率境界）/ invariant=CORE-TM-INV-004


### StabilityPool / DFStabilityPool の機能要件（CORE-SP-FR-*）

#### CORE-SP-FR-001: constructor（AddressesRegistry からの配線）🔵
- **Type**: Functional ｜ **Source**: base 実装（StabilityPool.sol / Dependencies/LiquityBase.sol）
- **シグネチャ**: `constructor(IAddressesRegistry _addressesRegistry)`
- **目的**: branch の AddressesRegistry から関連コントラクトのアドレスを 1 度だけ取得・固定する。
- **権限**: デプロイ時のみ。
- **事前条件（Checks）**: なし（registry の値を無検証で採用。配線の正しさは AddressesRegistry 側＝AR スコープで担保）。
- **動作（Effects）**:
  1. （LiquityBase）`activePool` / `defaultPool` / `priceFeed` を registry から取得し storage に保存。`ActivePoolAddressChanged` / `DefaultPoolAddressChanged` / `PriceFeedAddressChanged` を発火
  2. `collToken` / `troveManager` / `jpydfToken` を registry から取得し immutable に固定。`TroveManagerAddressChanged` / `JpydfTokenAddressChanged` を発火
  3. `P` は宣言時初期化により `P_PRECISION`（=1e36）で開始。`currentScale`・各トラッカーは 0
- **revert / 早期 return**: なし。
- **発火イベント**: CORE-SP-EVT-009〜013。
- **設計上のポイント**: setter は一切なく、配線はデプロイ時に不変確定。`collToken` は dToken（[dToken.md](./dToken.md)）。DFStabilityPool の constructor も同一（追加状態 `lastDepositBlock` は mapping のため初期化不要）。
- **Verification**: parity（配線・初期値の同一性）。

#### CORE-SP-FR-002: provideToSP（JPYdf 預入・トップアップとゲイン同時精算）🔵
- **Type**: Functional ｜ **Source**: base 実装（StabilityPool.sol）
- **シグネチャ**: `provideToSP(uint256 _topUp, bool _doClaim)`
- **目的**: JPYdf を預け入れる（新規・トップアップ共通）。同時に、前回操作以降の担保ゲイン・利回りゲインを精算し（claim または stash/複利）、スナップショットを最新値へ更新する。
- **権限**: permissionless（誰でも自分の預金として実行可。預金が無くても新規預入できる）。
- **事前条件（Checks）**:
  - `_topUp > 0`（ゼロ預入は不可）
  - 呼出者が `_topUp` 以上の JPYdf 残高を持つ（`jpydfToken.sendToPool` の transfer が前提。allowance は不要＝JpydfToken の pool 送金は残高直接移転。BT スコープ）
- **動作（Effects）**（コードの実行順）:
  1. `activePool.mintAggInterest()` を呼ぶ。ActivePool が保留中の集計利息を mint し、SP 取り分（`SP_YIELD_SPLIT`=75%）を SP へ mint のうえ `triggerJpydfRewards` を呼び返す（AP スコープ）。**これにより以降のゲイン計算は直前までの利息利回りを含む**
  2. 現在値を計算: `currentCollGain`（CORE-SP-FR-008）、`currentYieldGain`（CORE-SP-FR-009）、`compoundedJpydfDeposit`（CORE-SP-FR-011）
  3. `_doClaim` により利回りの行き先を決定（`_getYieldToKeepOrSend`）: `true` → 全額送金（`yieldGainToSend`）、`false` → 全額を預金へ複利（`keptYieldGain`）
  4. 新預金額 `newDeposit = compoundedJpydfDeposit + _topUp + keptYieldGain`
  5. `_doClaim` により担保の行き先を決定（`_getNewStashedCollAndCollToSend`）: `true` → `stashedColl[msg.sender] + currentCollGain` を全額送金・stash を 0 に、`false` → 今回ゲインを stash へ積み増し送金 0
  6. `DepositOperation(msg.sender, Operation.provideToSP, initialDeposit - compoundedJpydfDeposit, int256(_topUp), currentYieldGain, yieldGainToSend, currentCollGain, collToSend)` を発火
  7. `_updateDepositAndSnapshots`: `deposits` / `stashedColl` を更新し、スナップショットを現在の `P` / `scaleToS[currentScale]` / `scaleToB[currentScale]` / `currentScale` に更新（`newDeposit > 0` のため delete 分岐には入らない）。`DepositUpdated` を発火
  8. `jpydfToken.sendToPool(msg.sender, address(this), _topUp)` で JPYdf を受領
  9. `totalJpydfDeposits += _topUp + keptYieldGain`（`StabilityPoolJpydfBalanceUpdated` 発火）。kept yield は SP 内移動のため transfer なしで預金総額へ算入
  10. `yieldGainsOwed -= currentYieldGain`（claim/stash いずれでも未払い計上から消し込む）
  11. `yieldGainToSend > 0` なら `jpydfToken.returnFromPool` で送金
  12. `collToSend > 0` なら `collBalance` を減算し（`StabilityPoolCollBalanceUpdated` 発火）`collToken.safeTransfer(msg.sender, collToSend)`（dToken の払出）
  13. `_updateYieldRewardsSum(0)`: 今回の預入で `totalJpydfDeposits >= MIN_JPYDF_IN_SP` に達した場合、`yieldGainsPending` を `yieldGainsOwed` へ振替えて `scaleToB[currentScale]` を加算（`B_Updated` 発火。CORE-SP-FR-006 と同一ロジック）
- **revert / 早期 return**: `_topUp == 0` → `"StabilityPool: Amount must be non-zero"`；JPYdf 残高不足 → JpydfToken 側 revert。
- **発火イベント**: `DepositOperation`、`DepositUpdated`、`StabilityPoolJpydfBalanceUpdated`、（claim 時）`StabilityPoolCollBalanceUpdated`、（pending 振替時）`B_Updated`。
- **設計上のポイント**:
  - **ゲインは必ず全額同時精算**される（部分精算は不可）。`_doClaim=false` は「受け取らない」ではなく、利回りは預金へ複利・担保は `stashedColl` へ留保という退避先の選択。
  - スナップショット更新（手順 7）は pending 振替（手順 13）より**前**のため、閾値到達をもたらした預入者自身も、直後に配分される pending 利回りの按分に参加する。
  - 預入に `MIN_JPYDF_IN_SP` 制約はない（制約は引出側のみ。CORE-SP-FR-003）。
  - 🟡 **Base との差分**（CORE-MOD-004（§2 DF 差分台帳））: base ではゲイン計算に same-block 制約はない。DF（DFStabilityPool）は、既存預金者の `_doClaim=true` で `currentCollGain > 0 || stashedColl[msg.sender] > 0` の場合、手順 2 の担保ゲイン計算直後に `lastDepositBlock[msg.sender] < block.number` を要求し、満たさなければ `"StabilityPool: Coll gain claim must wait after deposit"` で revert する。新規預入、担保ゲインのない same-block top-up、`_doClaim=false` は制約しない。また、手順 6 の直後・手順 7 の直前に `lastDepositBlock[msg.sender] = block.number;` を記録する（CORE-SP-FR-004）。それ以外の挙動・イベント・引数は base と同一。根拠: same-block の flash 預入 → 清算 → `provideToSP(nonzero, true)` による担保ゲイン払出という即時精算 bypass の防止（CORE-SP-SEC-004）。
- **Verification**: parity / unit（`_doClaim` 分岐・kept yield の複利算入・pending 振替・新規/トップアップ両経路）/ invariant=CORE-SP-INV-003, CORE-SP-INV-005, CORE-SP-INV-006。

#### CORE-SP-FR-003: withdrawFromSP（JPYdf 引出とゲイン同時精算）🔵
- **Type**: Functional ｜ **Source**: base 実装（StabilityPool.sol）
- **シグネチャ**: `withdrawFromSP(uint256 _amount, bool _doClaim)`
- **目的**: 複利後預金から最大 `_amount` の JPYdf を引き出す。同時にゲインを精算し、スナップショットを更新する。`_amount = 0` の呼出は「ゲイン精算のみ」の操作として有効。
- **権限**: permissionless（ただし既存預金が必要）。
- **事前条件（Checks）**:
  - `deposits[msg.sender].initialValue > 0`（預金者であること）
  - **事後条件**として、引出後の `totalJpydfDeposits >= MIN_JPYDF_IN_SP`（=1 JPYdf。値は §7）。関数末尾で検査
- **動作（Effects）**（コードの実行順）:
  1. `activePool.mintAggInterest()`（CORE-SP-FR-002 手順 1 と同じ。ゲイン計算前に利息を確定）
  2. `currentCollGain` / `currentYieldGain` / `compoundedJpydfDeposit` を計算
  3. `jpydfToWithdraw = min(_amount, compoundedJpydfDeposit)`（過大要求は全額引出に切り詰め）
  4. `_doClaim` により利回り・担保の claim/stash を決定（CORE-SP-FR-002 手順 3・5 と同一の分岐）
  5. 新預金額 `newDeposit = compoundedJpydfDeposit - jpydfToWithdraw + keptYieldGain`
  6. `DepositOperation(msg.sender, Operation.withdrawFromSP, initialDeposit - compoundedJpydfDeposit, -int256(jpydfToWithdraw), currentYieldGain, yieldGainToSend, currentCollGain, collToSend)` を発火
  7. `_updateDepositAndSnapshots`: `newDeposit == 0` の場合は `depositSnapshots` を delete し `DepositUpdated(_depositor, 0, newStashedColl, 0, 0, 0, 0)` を発火、`> 0` の場合は最新スナップショットを記録
  8. `yieldGainsOwed -= currentYieldGain`
  9. `totalJpydfDeposits = totalJpydfDeposits + keptYieldGain - jpydfToWithdraw`（`StabilityPoolJpydfBalanceUpdated` 発火。戻り値を `newTotalJpydfDeposits` として保持）
  10. `jpydfToken.returnFromPool` で `jpydfToWithdraw + yieldGainToSend` を送金
  11. claim 時は担保を払出（`collBalance` 減算・`StabilityPoolCollBalanceUpdated`・`safeTransfer`）
  12. `require(newTotalJpydfDeposits >= MIN_JPYDF_IN_SP, ...)` を検査
- **revert / 早期 return**: 預金なし → `"StabilityPool: User must have a non-zero deposit"`；引出後総額が閾値未満 → `"Withdrawal must leave totalJpydfDeposits >= MIN_JPYDF_IN_SP"`。
- **発火イベント**: `DepositOperation`、`DepositUpdated`、`StabilityPoolJpydfBalanceUpdated`、（claim 時）`StabilityPoolCollBalanceUpdated`。
- **設計上のポイント**:
  - `MIN_JPYDF_IN_SP` 検査は**プール総額**への事後条件であり、個別預金にではない。プールが一度 `MIN_JPYDF_IN_SP` 以上になると、最後の 1 JPYdf 相当は誰も引き出せない（オフセットでも空にならない＝CORE-SP-INV-002 とあわせて `P > 0` を保証する基盤）。逆に、総額が一度も閾値に達していない極小プールでは引出自体が常に revert する（先に閾値超まで預入が必要）。
  - `_amount = 0`・`_doClaim = true` が「全ゲイン claim のみ」の定型操作（`jpydfToWithdraw = 0` で預金は維持）。
  - 全額引出でも `_doClaim = false` なら kept yield が新預金として残り、預金は 0 にならない場合がある。
  - 🟡 **Base との差分**（CORE-MOD-004（§2 DF 差分台帳））: base では預入と同一ブロック内の引出が可能。DF（DFStabilityPool）では冒頭（`_requireUserHasDeposit` の直後・`mintAggInterest` の前）で `_requireWithdrawalAfterDeposit()` を検査し、`lastDepositBlock[msg.sender] < block.number` でなければ `"StabilityPool: Withdrawal must wait after deposit"` で revert する（CORE-SP-FR-004）。それ以外の挙動は base と同一。根拠: CORE-SP-SEC-004。
- **Verification**: parity / unit（`min` 切り詰め・`_amount=0` 精算・`MIN_JPYDF_IN_SP` 境界・`newDeposit==0` の snapshot delete）/ invariant=CORE-SP-INV-002, CORE-SP-INV-003, CORE-SP-INV-006。

#### CORE-SP-FR-004: lastDepositBlock（same-block 担保ゲイン claim・出金ガード）🟡
- **Type**: Functional ｜ **Source**: DF 設計（CORE-MOD-004（§2 DF 差分台帳）。DFStabilityPool.sol）
- **シグネチャ**: `lastDepositBlock(address) → uint256`（public mapping の自動 getter）＋ internal ガード `_requireCollGainClaimAfterDeposit()` / `_requireWithdrawalAfterDeposit()`
- **目的**: 同一ブロック内での「flash 預入 → 清算（offset）発生 → 担保ゲインを受領・外部換価して原資を回収」という清算益横取りを、預入ブロックでの担保ゲイン払出と出金の禁止により遮断する。
- **権限**: getter は permissionless（view）。記録・検査は `provideToSP` / `withdrawFromSP` の内部動作。
- **事前条件（Checks）**: —（状態変数仕様）。
- **動作（Effects）**:
  1. `provideToSP` 実行時、`lastDepositBlock[msg.sender] = block.number` を記録（新規・トップアップとも。`DepositOperation` 発火直後、状態更新群の先頭）
  2. `provideToSP` で既存預金者が `_doClaim=true` かつ current または stash 済み担保ゲインを持つ場合、`require(lastDepositBlock[msg.sender] < block.number, "StabilityPool: Coll gain claim must wait after deposit")` を検査
  3. `withdrawFromSP` 冒頭で `require(lastDepositBlock[msg.sender] < block.number, "StabilityPool: Withdrawal must wait after deposit")` を検査
  4. 未預入アドレスは初期値 0 のため検査を常に通過する（が、withdraw は預金が無いため `_requireUserHasDeposit` で revert）
- **revert / 早期 return**: 同一ブロック内の預入→担保ゲイン claim → `"StabilityPool: Coll gain claim must wait after deposit"`。同一ブロック内の預入→引出 → `"StabilityPool: Withdrawal must wait after deposit"`。
- **発火イベント**: なし（専用イベントは追加されていない）。
- **設計上のポイント**:
  - 拘束は**翌ブロック以降の解除**のみ（タイムロックではない）。預入状態は少なくとも 1 つの block boundary を跨ぐが、block N の末尾で預入し block N+1 の先頭で精算できるため、途中の `offset()` や「1 block 全体の清算減耗リスク」は保証しない。一方、同一 tx 内で返済が必要な flash loan は、清算担保の払出・換価と預金の出金の双方を実行できない。
  - `provideToSP(..., false)` は同一ブロックでも許可し、current 担保ゲインを `stashedColl` に留保する。その後の同一ブロック `provideToSP(..., true)` は stash 条件により拒否される。担保ゲインがない `_doClaim=true` top-up と JPYdf yield のみの精算は許可する。
  - `claimAllCollGains` は預金 0（過去操作で確定済みの stash 残）にしか作用しないため、same-block 預入と組み合わせた横取り経路にはならない。
  - StabilityPool.sol（base 規範）にはこの状態・ガードは存在しない。デプロイ実体が DFStabilityPool であることと、両者の差分がこの FR と CORE-SP-FR-002/003 の注記に列挙した 4 点に限られることを、フォーク元同一性テストの対象とする。
- **Verification**: unit（same-block の current/stash 担保 claim revert・no-claim stash 成功・担保ゲインなし top-up 成功・新規預入成功・翌ブロック claim/withdraw 成功・`claimAllCollGains` 非対象）/ copy-parity（DFStabilityPool が本ガード以外で StabilityPool と同一挙動であること）。

#### CORE-SP-FR-005: claimAllCollGains（預金ゼロ利用者の stash 済み担保請求）🔵
- **Type**: Functional ｜ **Source**: base 実装（StabilityPool.sol）
- **シグネチャ**: `claimAllCollGains()`
- **目的**: 預金を全額引き出した後に `stashedColl` だけが残っている利用者が、留保担保を受け取るための専用関数。
- **権限**: permissionless（ただし**預金が 0 であること**が必須。預金保有者は CORE-SP-FR-002/003 の `_doClaim=true` で精算する）。
- **事前条件（Checks）**:
  - `deposits[msg.sender].initialValue == 0`
  - `stashedColl[msg.sender] > 0`
- **動作（Effects）**:
  1. `activePool.mintAggInterest()`（他の預金者操作と同様、ActivePool の利息集計を最新化）
  2. `collToSend = stashedColl[msg.sender]` を読み、`stashedColl[msg.sender] = 0`
  3. `DepositOperation(msg.sender, Operation.claimAllCollGains, 0, 0, 0, 0, 0, collToSend)` と `DepositUpdated(msg.sender, 0, 0, 0, 0, 0, 0)` を発火
  4. `collBalance` を減算（`StabilityPoolCollBalanceUpdated` 発火）し `collToken.safeTransfer(msg.sender, collToSend)`（dToken の払出。[dToken.md](./dToken.md)）
- **revert / 早期 return**: 預金あり → `"StabilityPool: User must have no deposit"`；stash が 0 → `"StabilityPool: Amount must be non-zero"`。
- **発火イベント**: `DepositOperation`、`DepositUpdated`、`StabilityPoolCollBalanceUpdated`。
- **設計上のポイント**: 預金が 0 になった時点でスナップショットは delete 済み（CORE-SP-FR-003 手順 7）のため、本関数はゲイン計算を行わず stash 残高の払出のみを行う。DF ガード（CORE-SP-FR-004）の対象外。
- **Verification**: parity / unit（預金ありで revert・stash ゼロで revert・払出と stash クリア）。

#### CORE-SP-FR-006: triggerJpydfRewards（利息利回りの配分計上）🔵
- **Type**: Functional ｜ **Source**: base 実装（StabilityPool.sol）
- **シグネチャ**: `triggerJpydfRewards(uint256 _jpydfYield)`
- **目的**: ActivePool が集計利息を mint した際、SP 取り分の JPYdf 利回り（`SP_YIELD_SPLIT`=75% 分。AP スコープ）を預金者への配分として計上する。
- **権限**: **ActivePool のみ**（`require(msg.sender == address(activePool))`）。
- **事前条件（Checks）**: 呼出元検査のみ。`_jpydfYield = 0` も許容（pending の振替契機になり得る）。
- **動作（Effects）**（`_updateYieldRewardsSum(_jpydfYield)`）:
  1. `accumulatedYieldGains = yieldGainsPending + _jpydfYield`。0 なら何もせず return
  2. `totalJpydfDeposits < MIN_JPYDF_IN_SP` の場合: `yieldGainsPending = accumulatedYieldGains` として**配分を保留**し return（`B` は更新しない。JPYdf 実体は ActivePool が SP へ mint 済みで SP 残高に滞留）
  3. それ以外: `yieldGainsOwed += accumulatedYieldGains`、`yieldGainsPending = 0`、`scaleToB[currentScale] += P * accumulatedYieldGains / totalJpydfDeposits` を加算し `B_Updated(scaleToB[currentScale], currentScale)` を発火
- **revert / 早期 return**: 非 ActivePool → `"StabilityPool: Caller is not ActivePool"`；`accumulatedYieldGains == 0` → 早期 return（イベントなし）。
- **発火イベント**: （配分時のみ）`B_Updated`。
- **設計上のポイント**:
  - 預金総額が極小（閾値未満）のとき配分すると、わずかな預金が利回りを独占し `B` の加算値も発散しうるため、閾値回復まで pending として保留する。pending は次の本関数呼出または `provideToSP` 末尾の内部呼出（CORE-SP-FR-002 手順 13）で一括配分される。
  - `yieldGainsOwed` は増えるが `totalJpydfDeposits` は増えない。利回りが預金総額へ入るのは、各預金者が `_doClaim=false` で複利した時点（kept yield）。
- **Verification**: parity / unit（閾値未満での pending 積み増し・閾値以上での一括振替・ゼロ利回り早期 return）/ invariant=CORE-SP-INV-003, CORE-SP-INV-005。

#### CORE-SP-FR-007: offset（清算オフセット: P/S 更新・debt 焼却・担保受入）🔵
- **Type**: Functional ｜ **Source**: base 実装（StabilityPool.sol）
- **シグネチャ**: `offset(uint256 _debtToOffset, uint256 _collToAdd)`
- **目的**: 清算 Trove の debt `_debtToOffset` をプール預金と相殺（JPYdf 焼却）し、清算担保 `_collToAdd` を ActivePool から受け入れて預金者へ比例配分する。配分は `S`（担保）と `P`（預金減耗率）の更新のみで表現する（O(1)）。
- **権限**: **TroveManager のみ**（`require(msg.sender == address(troveManager))`）。
- **事前条件（Checks）**: ローカル検査は `newP > 0` のみ。**以下は呼出元 TroveManager の清算ロジックが保証する前提**（TM スコープ）: `totalJpydfDeposits > 0`（ゼロ除算回避）、`_debtToOffset <= totalJpydfDeposits - MIN_JPYDF_IN_SP`（プールを空にしない）。
- **動作（Effects）**（コードの実行順）:
  1. `scaleToS[currentScale] += P * _collToAdd / totalJpydfDeposits` を加算し `S_Updated(scaleToS[currentScale], currentScale)` を発火（**P 更新前**の P で加重。床除算の端数は配分されず、担保は手順 7 で全額受け入れるため誤差分は `collBalance` 側に滞留＝預金者へ過大配分しない方向）
  2. `numerator = P * (totalJpydfDeposits - _debtToOffset)`、`newP = numerator / totalJpydfDeposits` を計算（床除算。預金の複利評価は厳密値以下となり、誤差は預金者側に不利・プール側に残る方向）
  3. `require(newP > 0, "P must never decrease to 0")`。`MIN_JPYDF_IN_SP` により `totalJpydfDeposits - _debtToOffset >= 1e18`、かつ `P >= P_PRECISION / SCALE_FACTOR = 1e27` が保たれるため、`newP = 0` には `totalJpydfDeposits > 1e45`（octillion 規模の JPYdf）が必要であり実際上は到達しない（コード内コメントの解析）
  4. **scale 処理**: `newP < P_PRECISION / SCALE_FACTOR`（=1e27）の間、`numerator *= SCALE_FACTOR; newP = numerator / totalJpydfDeposits; currentScale += 1` を繰り返し、毎回 `ScaleUpdated(currentScale)` を発火。除算済みの `newP` ではなく**元の `numerator` に倍率を乗じて再除算**することで丸め誤差の累積を避ける。1 回のオフセットで複数 scale を跨ぐ場合もこのループで処理される。オーバーフローは `numerator <= 1e36 * totalJpydfDeposits / SCALE_FACTOR` が各反復の上界となるため実際上生じない（コード内コメントの解析）
  5. `P_Updated(newP)` を発火し `P = newP`（ループ後の P は必ず `[1e27, 1e36]` に収まる）
  6. `totalJpydfDeposits -= _debtToOffset`（`StabilityPoolJpydfBalanceUpdated` 発火）し、`jpydfToken.burn(address(this), _debtToOffset)` で相殺分を焼却
  7. `collBalance += _collToAdd` とし、`activePool.sendColl(address(this), _collToAdd)` で担保（dToken）を ActivePool から受領。`StabilityPoolCollBalanceUpdated` を発火
- **revert / 早期 return**: 非 TroveManager → `"StabilityPool: Caller is not TroveManager"`；`newP == 0` → `"P must never decrease to 0"`；`totalJpydfDeposits == 0` で呼ばれた場合は除算 panic（前提条件違反。TM 側で到達しない）。
- **発火イベント**: `S_Updated`、（scale 跨ぎ時 0 回以上）`ScaleUpdated`、`P_Updated`、`StabilityPoolJpydfBalanceUpdated`、`StabilityPoolCollBalanceUpdated`。
- **設計上のポイント**:
  - `S` 加算（手順 1）が `P` 更新（手順 2〜5）より先である順序は本方式の前提: ゲインはオフセット**前**の預金価値（P 加重）で配られ、減耗はその後に反映される。
  - `scaleToS` / `scaleToB` は P 加重和のため、預金者ゲインは `initialDeposit * (S - S_t) / P_t` の形で snapshot `P_t` により正規化される（CORE-SP-FR-008/009）。
  - 担保受入は内部トラッカー `collBalance` の加算と `activePool.sendColl` の実 transfer を対で行い、直接送金との混同を避ける（CORE-SP-SEC-003）。
- **Verification**: parity / unit（単一・複数 scale 跨ぎ、`newP > 0` 境界、S→P の更新順序、丸め方向）/ invariant=CORE-SP-INV-001〜004。

#### CORE-SP-FR-008: getDepositorCollGain（未精算担保ゲインの計算）🔵
- **Type**: Functional ｜ **Source**: base 実装（StabilityPool.sol）
- **シグネチャ**: `getDepositorCollGain(address _depositor) → uint256`（public view）
- **目的**: 預金者が前回スナップショット以降に獲得した担保ゲインを返す。`provideToSP` / `withdrawFromSP` の精算額算定にも内部使用される。
- **権限**: なし（view）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**:
  1. `deposits[_depositor].initialValue == 0` なら 0
  2. 同一 scale 分: `normalizedGains = scaleToS[snapshots.scale] - snapshots.S`
  3. scale 跨ぎ分: `i = 1..SCALE_SPAN`（=2）について `normalizedGains += scaleToS[snapshots.scale + i] / SCALE_FACTOR**i`（後続 scale の累積和は全額が当該預金の在籍期間に発生したものとして、`SCALE_FACTOR` の冪で減衰換算）
  4. `min(initialDeposit * normalizedGains / snapshots.P, collBalance)` を返す（プール実保有を超える払出を防ぐ上限クランプ）
- **revert / 早期 return**: なし（預金 0 → 0）。
- **発火イベント**: なし（view）。
- **設計上のポイント**: スナップショット scale から `SCALE_SPAN`（=2）を超えて scale が進んだ分のゲインは計算対象外（未操作のまま放置された預金はゲイン受領を停止する）。2 scale 跨ぎ時点で預金は元本の高々 1e-9〜1e-18 倍に減耗しており、切り捨てる経済的影響は無視できる、というのが upstream の設計判断。
- **Verification**: parity / unit（同一 scale・1/2 scale 跨ぎ・SPAN 超過で打ち切り・クランプ発動）。

#### CORE-SP-FR-009: getDepositorYieldGain（未精算利回りゲインの計算）🔵
- **Type**: Functional ｜ **Source**: base 実装（StabilityPool.sol）
- **シグネチャ**: `getDepositorYieldGain(address _depositor) → uint256`（public view）
- **目的**: 預金者が前回スナップショット以降に獲得した JPYdf 利回りゲイン（Trove 利息由来）を返す。
- **権限**: なし（view）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**: CORE-SP-FR-008 と同形で、`scaleToS`/`snapshots.S` を `scaleToB`/`snapshots.B` に、上限クランプを `yieldGainsOwed` に読み替える:
  `min(initialDeposit * ((scaleToB[scale] - B_t) + Σ_{i=1..2} scaleToB[scale+i] / 1e9^i) / snapshots.P, yieldGainsOwed)`
- **revert / 早期 return**: なし（預金 0 → 0）。
- **発火イベント**: なし（view）。
- **設計上のポイント**: クランプ先が `yieldGainsOwed`（配分計上済み未払い総額）である点が担保ゲインとの違い。`yieldGainsPending` は含まない（未配分のため。見積りは CORE-SP-FR-010）。
- **Verification**: parity / unit（scale 跨ぎ・クランプ・pending 非算入）。

#### CORE-SP-FR-010: getDepositorYieldGainWithPending（pending 利息込みの利回り見積）🔵
- **Type**: Functional ｜ **Source**: base 実装（StabilityPool.sol）
- **シグネチャ**: `getDepositorYieldGainWithPending(address _depositor) → uint256`（external view）
- **目的**: 「いま利息が mint されたら `getDepositorYieldGain` がいくらになるか」のフロントエンド向け見積り。状態変化経路では使用されない。
- **権限**: なし（view）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**:
  1. `totalJpydfDeposits < MIN_JPYDF_IN_SP` なら 0（pending は配分されないため）
  2. 預金 0 なら 0
  3. CORE-SP-FR-009 と同じ `normalizedGains`（確定分）を計算
  4. `pendingSPYield = activePool.calcPendingSPYield()`（未 mint の集計利息の SP 取り分。AP スコープ）を `newYieldGainsOwed = yieldGainsOwed + pendingSPYield` として上限に加算
  5. `currentScale <= snapshots.scale + SCALE_SPAN` の場合のみ、`normalizedGains += P * pendingSPYield / totalJpydfDeposits / SCALE_FACTOR**(currentScale - snapshots.scale)`（pending を現 scale の `B` 加算として模擬し、預金者の scale へ減衰換算）
  6. `min(initialDeposit * normalizedGains / snapshots.P, newYieldGainsOwed)` を返す
- **revert / 早期 return**: なし。
- **発火イベント**: なし（view）。
- **設計上のポイント**: 既存 `yieldGainsPending` は手順 4・5 の対象に**含まれない**（`calcPendingSPYield` は ActivePool 側の未 mint 利息のみ）。閾値未満時に 0 を返す仕様とあわせ、あくまで「閾値以上で稼働中のプール」に対する見積り関数。
- **Verification**: parity / unit（閾値未満で 0・SPAN 内外の分岐・`triggerJpydfRewards` 直後との整合）。

#### CORE-SP-FR-011: getCompoundedJpydfDeposit（複利後預金の計算）🔵
- **Type**: Functional ｜ **Source**: base 実装（StabilityPool.sol）
- **シグネチャ**: `getCompoundedJpydfDeposit(address _depositor) → uint256`（public view）
- **目的**: 一連の清算による減耗を反映した預金者の現在預金額を返す。
- **権限**: なし（view）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**:
  1. `deposits[_depositor].initialValue == 0` なら 0
  2. `scaleDiff = currentScale - snapshots.scale`
  3. `scaleDiff <= MAX_SCALE_FACTOR_EXPONENT`（=8）なら `initialDeposit * P / snapshots.P / SCALE_FACTOR**scaleDiff` を返す
  4. それ以外は 0（`SCALE_FACTOR**scaleDiff` が uint256 を超えるため、オーバーフローさせず直接 0 と評価。9 scale 跨ぎの預金は元本の 1e-81 倍以下であり実質 0）
- **revert / 早期 return**: なし。
- **発火イベント**: なし（view）。
- **設計上のポイント**: ゲイン側の追跡上限（`SCALE_SPAN`=2。CORE-SP-FR-008/009）と預金額側の追跡上限（`MAX_SCALE_FACTOR_EXPONENT`=8）は独立の定数。前者は経済的打ち切り、後者はオーバーフロー回避が目的。
- **Verification**: parity / unit（scale 差 0〜8・9 以上で 0・床除算の方向）。

#### CORE-SP-FR-012: 自明な view 関数群（トラッカー・定数・配線 getter）🔵
- **Type**: Functional ｜ **Source**: base 実装（StabilityPool.sol）
- **目的**: 内部トラッカー・公開状態変数・定数・配線アドレスの読み出し。いずれも保存値の単純返却で計算を含まない。
- **権限**: なし（すべて view）。

  | 関数 | 返り値の意味 |
  | --- | --- |
  | `getCollBalance()` | `collBalance`（担保内部トラッカー。直接 transfer 分は含まない） |
  | `getTotalJpydfDeposits()` | `totalJpydfDeposits` |
  | `getYieldGainsOwed()` | `yieldGainsOwed` |
  | `getYieldGainsPending()` | `yieldGainsPending` |
  | `deposits(address)` | 預金者の `initialValue`（最終操作時点の預金額。現在値は CORE-SP-FR-011） |
  | `depositSnapshots(address)` | `(S, P, B, scale)` スナップショット |
  | `stashedColl(address)` | 留保中の担保ゲイン |
  | `P()` / `currentScale()` | running product / 現在 scale |
  | `scaleToS(uint256)` / `scaleToB(uint256)` | scale 別累積和 |
  | `NAME()` | `"StabilityPool"`（**DFStabilityPool でも同一文字列**） |
  | `P_PRECISION()` / `SCALE_FACTOR()` / `MAX_SCALE_FACTOR_EXPONENT()` / `SCALE_SPAN()` | 定数（状態変数表参照） |
  | `collToken()` / `troveManager()` / `jpydfToken()` / `activePool()` | 配線アドレス（`activePool` は LiquityBase 継承） |

- **revert / 早期 return**: なし。
- **Verification**: parity。

#### CORE-SP-FR-013: getEntireBranchColl / getEntireBranchDebt（LiquityBase 継承 view）🔵
- **Type**: Functional ｜ **Source**: base 実装（Dependencies/LiquityBase.sol）
- **シグネチャ**: `getEntireBranchColl() → uint256` ／ `getEntireBranchDebt() → uint256`（public view）
- **目的**: branch 全体の担保合計（`activePool.getCollBalance() + defaultPool.getCollBalance()`）・債務合計（`activePool.getJpydfDebt() + defaultPool.getJpydfDebt()`）を返す共通ヘルパ。SP の ABI 面にも現れるため本表に含める。
- **権限**: なし（view）。
- **動作（Effects）**: 上記 2 項の単純合算。
- **revert / 早期 return**: なし。
- **設計上のポイント**: 実装は LiquityBase 共通（規範は LIB スコープ＝CORE-LIB 側で一元規定。本 FR は SP インターフェースとしての存在確認に留める）。
- **Verification**: parity。


### ActivePool の機能要件（CORE-AP-FR-*）

#### CORE-AP-FR-001: コンストラクタ（アドレス配線と DefaultPool への担保 approve）🔵
- **Type**: Functional ｜ **Source**: base 実装（ActivePool.sol）
- **シグネチャ**: `constructor(IAddressesRegistry _addressesRegistry)`
- **目的**: ブランチの AddressesRegistry から関連コントラクトアドレスを取得して immutable に固定し、DefaultPool との担保移転経路を開通させる。
- **権限**: デプロイ時 1 回。
- **事前条件（Checks）**: なし（AddressesRegistry の値を無検証で信頼。配線の正しさはデプロイ手順の責務）。
- **動作（Effects）**:
  1. `collToken` / `borrowerOperationsAddress` / `troveManagerAddress` / `stabilityPool` / `defaultPoolAddress` / `interestRouter` / `jpydfToken` を AddressesRegistry から取得し immutable に設定
  2. アドレス変更イベント 5 件を発火（CollToken / BorrowerOperations / TroveManager / StabilityPool / DefaultPool の順）
  3. `collToken.approve(defaultPoolAddress, type(uint256).max)` — DefaultPool が `safeTransferFrom` で担保を pull できるようにする無限 approve（CORE-DP-FR-003 の対向）
- **revert / 早期 return**: なし（approve が false を返す非標準トークンは想定外。担保は dToken に限られる）。
- **発火イベント**: CORE-AP-EVT-001〜005。
- **設計上のポイント**: 全配線が immutable のため、デプロイ後のアドレス差し替え・upgrade 経路は存在しない。Pool 間の担保移動は「受領側が pull」方式で統一されており、その前提となる approve を双方（AP→DP はここ、DP→AP は DefaultPool コンストラクタ）が自分のコンストラクタで設定する。
- **Verification**: parity / deployment テスト（配線・approve 値）

#### CORE-AP-FR-002: calcPendingAggInterest（集計ペンディング利息の計算）🔵
- **Type**: Functional ｜ **Source**: base 実装（ActivePool.sol）
- **シグネチャ**: `calcPendingAggInterest() → uint256`（public view）
- **目的**: 前回確定時刻 `lastAggUpdateTime` から現在までに発生した、ブランチ全体の未確定（ペンディング）集計利息を返す。
- **権限**: なし（view）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**:
  1. `shutdownTime != 0` なら 0 を返す（shutdown 後は利息が一切発生しない）
  2. それ以外は `ceilDiv(aggWeightedDebtSum × (block.timestamp − lastAggUpdateTime), ONE_YEAR × DECIMAL_PRECISION)` を返す（単利の線形按分）
- **revert / 早期 return**: shutdown 済み → 早期 return 0。
- **発火イベント**: なし（view）。
- **設計上のポイント**: **切り上げ除算（ceilDiv）**を用いるのは、個別 Trove の利息計算（TroveManager 側）が floor 除算であるのに対し、システム側に正の誤差を持たせ「システム負債 ≥ Σ Trove 負債」を常に保つため。全 Trove の負債が返済されてもシステム負債が負にならないことを保証する。誤差は利息 mint イベント回数に比例する微小量。
- **Verification**: parity / invariant=CORE-SYS-INV-001 の基礎

#### CORE-AP-FR-003: calcPendingSPYield（ペンディング利息の SP 取り分）🔵
- **Type**: Functional ｜ **Source**: base 実装（ActivePool.sol）
- **シグネチャ**: `calcPendingSPYield() → uint256`（external view）
- **目的**: ペンディング集計利息のうち StabilityPool へ分配される取り分を返す。SP の `getDepositorYieldGainWithPending`（未確定利回りを含む預金者ゲインの試算）が参照する。
- **権限**: なし（view）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**: `calcPendingAggInterest() × SP_YIELD_SPLIT / DECIMAL_PRECISION` を返す（`SP_YIELD_SPLIT` = 75%。値は §7）。
- **revert / 早期 return**: なし。
- **発火イベント**: なし（view）。
- **設計上のポイント**: floor 除算であり、実際の mint 時（CORE-AP-FR-007）の `spYield` 計算と同一式。
- **Verification**: parity

#### CORE-AP-FR-004: calcPendingAggBatchManagementFee（集計ペンディング batch 管理フィーの計算）🔵
- **Type**: Functional ｜ **Source**: base 実装（ActivePool.sol）
- **シグネチャ**: `calcPendingAggBatchManagementFee() → uint256`（public view）
- **目的**: 前回確定時刻から現在（shutdown 済みなら shutdown 時刻）までに発生した、全 batch の未確定管理フィー合計を返す。
- **権限**: なし（view）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**:
  1. `periodEnd = shutdownTime != 0 ? shutdownTime : block.timestamp`
  2. `periodStart = min(lastAggBatchManagementFeesUpdateTime, periodEnd)`
  3. `ceilDiv(aggWeightedBatchManagementFeeSum × (periodEnd − periodStart), ONE_YEAR × DECIMAL_PRECISION)` を返す
- **revert / 早期 return**: なし。
- **発火イベント**: なし（view）。
- **設計上のポイント**: 集計利息（CORE-AP-FR-002、shutdown 後は即 0）と異なり、batch 管理フィーは **shutdown 時刻までの発生分が shutdown 後も計算に残る**。集計利息は shutdown 処理の同一 tx 内で mint され尽くす（CORE-AP-FR-014）のに対し、batch フィーは shutdown 時に自動確定されないため、計算式側で「shutdown 時点まで」を期間上限として保存する。`min(...)` は、shutdown 後の batch 操作で `lastAggBatchManagementFeesUpdateTime` が `shutdownTime` を超えた場合に減算が underflow しないためのガード（その場合の期間はゼロ）。切り上げ除算の趣旨は CORE-AP-FR-002 と同じ。
- **Verification**: parity / unit（shutdown 前後・lastUpdate > shutdownTime の境界）

#### CORE-AP-FR-005: getNewApproxAvgInterestRateFromTroveChange（Trove 変更仮適用後の近似平均利率）🔵
- **Type**: Functional ｜ **Source**: base 実装（ActivePool.sol）
- **シグネチャ**: `getNewApproxAvgInterestRateFromTroveChange(TroveChange calldata _troveChange) → uint256`（external view）
- **目的**: 与えられた Trove 変更（debt 増減・加重負債和の new/old）を仮適用した場合のブランチ近似平均利率を返す。BorrowerOperations / HintHelpers が upfront fee（平均利率 × 7 日分）の算定に用いる。
- **権限**: なし（view）。呼出規約として `_troveChange.upfrontFee == 0` を要求（assert）。
- **事前条件（Checks）**: `assert(_troveChange.upfrontFee == 0)` — upfront fee 確定**前**の TroveChange で呼ぶこと。
- **動作（Effects）**:
  1. `shutdownTime != 0` なら 0 を返す
  2. `newAggRecordedDebt = aggRecordedDebt + calcPendingAggInterest() + appliedRedistJpydfDebtGain + debtIncrease + batchAccruedManagementFee − debtDecrease`
  3. `newAggWeightedDebtSum = aggWeightedDebtSum + newWeightedRecordedDebt − oldWeightedRecordedDebt`
  4. `newAggRecordedDebt > 0` なら `newAggWeightedDebtSum / newAggRecordedDebt`、0 なら 0 を返す
- **revert / 早期 return**: `upfrontFee != 0` → assert 失敗（Panic 0x01）。shutdown 済み → 0。分母 0（最初の借入者が 0 JPYdf を試行する経路。`debt ≥ MIN_DEBT` 検証は upfront fee 計算より後段のため到達しうる）→ 0。
- **発火イベント**: なし（view）。
- **設計上のポイント**: upfront fee を意図的に無視するのは「fee は平均利率に依存 → 平均利率は負債で加重 → 負債は fee を含む」という循環を単純に断ち切るための**近似**だから（関数名の Approx の由来）。結果は 1e18 スケールの年利率。
- **Verification**: parity / unit（shutdown 時 0・分母 0・近似式）

#### CORE-AP-FR-006: getJpydfDebt（アクティブ負債合計）🔵
- **Type**: Functional ｜ **Source**: base 実装（ActivePool.sol）
- **シグネチャ**: `getJpydfDebt() → uint256`（external view）
- **目的**: ブランチのアクティブ側エンタイア負債（記録負債＋ペンディング集計利息＋確定済み・ペンディングの batch 管理フィー）を返す。`LiquityBase` の `getEntireBranchDebt`（= AP.getJpydfDebt() + DP.getJpydfDebt()）の構成要素。
- **権限**: なし（view）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**: `aggRecordedDebt + calcPendingAggInterest() + aggBatchManagementFees + calcPendingAggBatchManagementFee()` を返す。
- **revert / 早期 return**: なし。
- **発火イベント**: なし（view）。
- **設計上のポイント**: redistribution 待ちのペンディング負債は含まない（DefaultPool の `getJpydfDebt`＝CORE-DP-FR-006 が保持）。batch 管理フィー 2 項を足すのは、各 batched Trove のエンタイア負債に accrue 済み管理フィーが含まれるため、システム視点の負債にも対応分を計上する必要があるから。
- **Verification**: parity / invariant=CORE-SYS-INV-001 の基礎

#### CORE-AP-FR-007: mintAggInterest（集計利息の確定 mint・75/25 分配）🔵
- **Type**: Functional ｜ **Source**: base 実装（ActivePool.sol）
- **シグネチャ**: `mintAggInterest()`
- **目的**: Trove 構成（加重負債和）を変えない操作（SP への預入・引出等）の際に、ペンディング集計利息を確定して JPYdf として mint・分配し、`aggRecordedDebt` に繰り入れる。
- **権限**: BorrowerOperations または StabilityPool のみ（`_requireCallerIsBOorSP`）。実際の呼出元: SP の `provideToSP` / `withdrawFromSP` / `claimAllCollGains`、および BO の shutdown 処理（`_applyShutdown`）。
- **事前条件（Checks）**: 呼出元検証のみ。
- **動作（Effects）**: `aggRecordedDebt += _mintAggInterest(0)`。内部処理 `_mintAggInterest(_upfrontFee)` は:
  1. `mintedAmount = calcPendingAggInterest() + _upfrontFee`（本 FR では `_upfrontFee = 0`）
  2. `mintedAmount > 0` の場合:
     - `spYield = SP_YIELD_SPLIT × mintedAmount / DECIMAL_PRECISION`（75%・floor）、`remainderToLPs = mintedAmount − spYield`（残余 25%・切り上げ側）
     - `jpydfToken.mint(interestRouter, remainderToLPs)`
     - `spYield > 0` なら `jpydfToken.mint(stabilityPool, spYield)` し、続けて `stabilityPool.triggerJpydfRewards(spYield)` で SP に利回り計上を通知
  3. `AggregateInterestMinted(jpydfToken, stabilityPool, interestRouter, pendingAggInterest, upfrontFee, mintedAmount, spYield, remainderToLPs)` を発火（`mintedAmount > 0` の場合のみ）
  4. `lastAggUpdateTime = block.timestamp`（mintedAmount が 0 でも必ず更新）
- **revert / 早期 return**: 呼出元不正 → `"ActivePool: Caller is not BorrowerOperations nor StabilityPool"`。
- **発火イベント**: `AggregateInterestMinted`（ActivePool）。加えて JpydfToken の Transfer と SP 側イベントが発生。
- **設計上のポイント**: 利息は負債側（aggRecordedDebt 増）と資産側（JPYdf mint）が同時に確定する。分配は SP 優先の 75/25 固定比率（`SP_YIELD_SPLIT`）で、floor 計算上 `mintedAmount > 0` なら router 側は必ず正、SP 側は極小額時のみ 0 になりうる（その場合 `triggerJpydfRewards` も呼ばれない）。ActivePool が JpydfToken の mint 権限を持つ前提（JpydfToken 側の AP 限定 mint は BT スコープで規定）。`AggregateInterestMinted` は DeFiLlama 等の外部 fee/revenue 集計の一次証跡であり、`mintedAmount` が gross fees、`spYield` が supply-side、`remainderToLPs` が PIL / InterestRouter 側の配分として復元できる。
- **Verification**: parity / unit（分配端数・spYield=0 境界・lastAggUpdateTime 更新）

#### CORE-AP-FR-008: mintAggInterestAndAccountForTroveChange（利息 mint＋Trove 変化の集計反映）🔵
- **Type**: Functional ｜ **Source**: base 実装（ActivePool.sol）
- **シグネチャ**: `mintAggInterestAndAccountForTroveChange(TroveChange calldata _troveChange, address _batchAddress)`
- **目的**: Trove の状態を変更するすべての操作（開設・調整・close・清算・redemption・batch 操作・ペンディング適用）の最後に呼ばれ、集計利息の確定 mint と、当該操作による負債・加重負債和の正味変化の集計トラッカーへの反映を 1 か所で行う。
- **権限**: BorrowerOperations または TroveManager のみ（`_requireCallerIsBOorTroveM`）。実際の呼出元: BO の全 Trove 操作（openTrove 系 / adjustTrove 系 / closeTrove / applyPendingDebt / 利率調整 / batch 参加・離脱 / interest batch 管理操作）、TM の `batchLiquidateTroves` / `redeemCollateral` / `urgentRedemption`。
- **事前条件（Checks）**: 呼出元検証のみ（TroveChange の整合性は呼出元 BO/TM の責務）。
- **動作（Effects）**（コードの実行順）:
  1. `_batchAddress != address(0)` の場合、先に batch 管理フィー処理（CORE-AP-FR-009 の内部処理 `_mintBatchManagementFeeAndAccountForChange`）を実行（`aggRecordedDebt += batchAccruedManagementFee` を含む）
  2. `_mintAggInterest(_troveChange.upfrontFee)` を実行し（CORE-AP-FR-007 の内部処理と同一。ペンディング集計利息＋upfront fee を 75/25 で mint・分配、`lastAggUpdateTime` 更新）、その返り値（mint 総額）を集計負債へ加算開始
  3. `aggRecordedDebt = aggRecordedDebt + mintedAmount + appliedRedistJpydfDebtGain + debtIncrease − debtDecrease`（underflow 回避のため増分→減分の 2 段階で演算し、SLOAD/SSTORE 各 1 回に最適化）
  4. `aggWeightedDebtSum = aggWeightedDebtSum + newWeightedRecordedDebt − oldWeightedRecordedDebt`
- **revert / 早期 return**: 呼出元不正 → `"ActivePool: Caller is neither BorrowerOperations nor TroveManager"`。減分が増分側を上回る場合は Solidity 0.8 checked 演算で revert（Panic 0x11。正しい TroveChange では発生しない）。
- **発火イベント**: CORE-AP-FR-007 の `_mintAggInterest` 経由で `AggregateInterestMinted`（`mintedAmount > 0` の場合）、および CORE-AP-FR-009 経由で `BatchManagementFeeMinted`（`batchAccruedManagementFee > 0` の場合）が発生しうる。加えて tracker 更新イベントが発生する。
- **設計上のポイント**: ① 正味 Trove 負債変化は「発行/返済（debtIncrease/debtDecrease）＋適用された redistribution 負債ゲイン（appliedRedistJpydfDebtGain）」で構成され、**Trove 個別の accrued 利息は含めない**（個別利息は集計利息側で一括処理されるため二重計上しない）。② 返済操作では redistribution ゲインと返済額の大小により正味が正にも負にもなりうるため、符号付き整数を避けて増分・減分の両方を受け取る。③ upfront fee は借り手の負債に乗ると同時に、トークンとしては利息と同じ 75/25 分配で即時 mint される。④ batch フィー処理（手順 1）が先行するのは、その中で `aggRecordedDebt` が更新されるため（手順 3 はその更新後の値を読む）。
- **Verification**: parity / invariant=CORE-SYS-INV-001

#### CORE-AP-FR-009: mintBatchManagementFeeAndAccountForChange（batch 管理フィーの確定 mint・集計反映）🔵
- **Type**: Functional ｜ **Source**: base 実装（ActivePool.sol）
- **シグネチャ**: `mintBatchManagementFeeAndAccountForChange(TroveChange calldata _troveChange, address _batchAddress)`
- **目的**: batch（interest batch manager 管理下の Trove 群）の accrue 済み管理フィーを確定し、batch manager へ JPYdf として mint するとともに、batch フィー集計トラッカーを更新する。
- **権限**: external 入口は TroveManager のみ（`_requireCallerIsTroveManager`）。呼出箇所: TM の清算（batched Trove の清算時）および redemption（batched Trove への償還時）。同一の内部処理は CORE-AP-FR-008 経由（BO/TM、`_batchAddress != 0` の場合）でも実行される。
- **事前条件（Checks）**: 呼出元検証のみ。
- **動作（Effects）**（内部処理 `_mintBatchManagementFeeAndAccountForChange`）:
  1. `aggRecordedDebt += _troveChange.batchAccruedManagementFee` — 当該 batch に適用（記録負債へ繰入れ）されたフィーを集計負債に計上
  2. `aggBatchManagementFees = aggBatchManagementFees + calcPendingAggBatchManagementFee() − batchAccruedManagementFee` — 全 batch のペンディングフィーを確定計上しつつ、今回適用分を「未適用」残高から除去（増分→減分の 2 段階演算）
  3. `aggWeightedBatchManagementFeeSum = aggWeightedBatchManagementFeeSum + newWeightedRecordedBatchManagementFee − oldWeightedRecordedBatchManagementFee`
  4. `batchAccruedManagementFee > 0` なら `jpydfToken.mint(_batchAddress, batchAccruedManagementFee)` — フィーを batch manager へ即時 mint
  5. `batchAccruedManagementFee > 0` なら `BatchManagementFeeMinted(jpydfToken, _batchAddress, batchAccruedManagementFee)` を発火
  6. `lastAggBatchManagementFeesUpdateTime = block.timestamp`
- **revert / 早期 return**: 呼出元不正 → `"ActivePool: Caller is not TroveManager"`。checked 演算の underflow は CORE-AP-FR-008 と同様。
- **発火イベント**: `BatchManagementFeeMinted`（ActivePool）。加えて JpydfToken の Transfer が発生。
- **設計上のポイント**: batch 管理フィーは借り手の負債（batch の記録負債）を増やし、その同額が batch manager の JPYdf 収入になる。`aggBatchManagementFees` は「確定済みだが Trove 記録負債に未適用」のフィー残高で、適用の瞬間に `aggRecordedDebt` へ付け替えられる（システム負債合計＝CORE-AP-FR-006 は不変に保たれる）。利息（75/25 分配）と異なり、batch フィーは全額が batch manager 個人に mint される。`BatchManagementFeeMinted` は DeFiLlama 等で batch manager fee を別カテゴリとして含める/除外する際の一次証跡であり、protocol revenue と混同しない。
- **Verification**: parity / unit（適用分の付け替え・mint 額）

#### CORE-AP-FR-010: sendColl（担保の外部送付）🔵
- **Type**: Functional ｜ **Source**: base 実装（ActivePool.sol）
- **シグネチャ**: `sendColl(address _account, uint256 _amount)`
- **目的**: アクティブ担保を指定アドレスへ送付し、会計残高を減算する。担保がブランチから「外へ」出る唯一の汎用経路。
- **権限**: BorrowerOperations・TroveManager・StabilityPool のみ（`_requireCallerIsBOorTroveMorSP`）。実際の呼出元と移転方向:
  - BO: 担保引出・closeTrove 時の借り手（受領者指定先）への送付
  - TM: 清算時の liquidator への coll gas compensation 送付、清算 surplus の CollSurplusPool への移送、redemption / urgent redemption の償還者への担保送付
  - SP: 清算 offset 時の SP 自身への担保取り込み（`sendColl(address(this), …)` を SP が呼ぶ）
- **事前条件（Checks）**: 呼出元検証。`_amount ≤ collBalance`（checked 演算で暗黙に強制）。
- **動作（Effects）**:
  1. `collBalance -= _amount` し、`ActivePoolCollBalanceUpdated(newCollBalance)` を発火（内部関数 `_accountForSendColl`）
  2. `collToken.safeTransfer(_account, _amount)` で実トークンを送付
- **revert / 早期 return**: 呼出元不正 → `"ActivePool: Caller is neither BorrowerOperations nor TroveManager nor StabilityPool"`。`_amount > collBalance` → Panic 0x11（underflow）。トークン transfer 失敗 → SafeERC20 revert。
- **発火イベント**: CORE-AP-EVT-007（ActivePoolCollBalanceUpdated）。
- **設計上のポイント**: 会計減算（Effects）→ 外部送付（Interactions）の順で CEI に従う。担保トークンは dToken（[dToken.md](./dToken.md)）であり、転送フックを持たない標準 ERC-20 として扱われる。
- **Verification**: parity / invariant=CORE-AP-INV-001

#### CORE-AP-FR-011: sendCollToDefaultPool（redistribution 担保の DefaultPool 移送）🔵
- **Type**: Functional ｜ **Source**: base 実装（ActivePool.sol）
- **シグネチャ**: `sendCollToDefaultPool(uint256 _amount)`
- **目的**: 清算の redistribution で、再分配対象の担保をアクティブ会計から外し DefaultPool へ移す。
- **権限**: TroveManager のみ（`_requireCallerIsTroveManager`）。呼出箇所: TM の `_redistributeDebtAndColl`（SP offset しきれない清算分の再分配。負債側の `DefaultPool.increaseJpydfDebt`＝CORE-DP-FR-004 と対で呼ばれる）。
- **事前条件（Checks）**: 呼出元検証。`_amount ≤ collBalance`（checked 演算）。
- **動作（Effects）**:
  1. `collBalance -= _amount`、`ActivePoolCollBalanceUpdated` 発火（CORE-AP-FR-010 と同じ内部関数）
  2. `IDefaultPool(defaultPoolAddress).receiveColl(_amount)` を呼ぶ — DefaultPool 側が会計加算し、コンストラクタの approve（CORE-AP-FR-001）を使って `safeTransferFrom` で ActivePool から実トークンを pull（CORE-DP-FR-003）
- **revert / 早期 return**: 呼出元不正 → `"ActivePool: Caller is not TroveManager"`。残高不足 → Panic 0x11。
- **発火イベント**: CORE-AP-EVT-007。続けて DefaultPool 側で CORE-DP-EVT-005。
- **設計上のポイント**: 移転は「送付側の会計減算 → 受領側の会計加算＋pull」の 2 段で、両 Pool の会計トラッカーが同一 tx 内で整合する。
- **Verification**: parity / invariant=CORE-AP-INV-001 / CORE-SYS-INV-007

#### CORE-AP-FR-012: receiveColl（担保受領: 会計加算＋pull）🔵
- **Type**: Functional ｜ **Source**: base 実装（ActivePool.sol）
- **シグネチャ**: `receiveColl(uint256 _amount)`
- **目的**: 呼出元から担保を受け取り（pull）、会計残高に加算する。
- **権限**: BorrowerOperations または DefaultPool のみ（`_requireCallerIsBorrowerOperationsOrDefaultPool`）。実コードでの呼出元は DefaultPool の `sendCollToActivePool`（CORE-DP-FR-002。redistribution ゲイン適用時の担保戻し）のみ。BO は許可されているが直接 transfer＋CORE-AP-FR-013 の経路を使う。
- **事前条件（Checks）**: 呼出元検証。呼出元が ActivePool へ `_amount` 以上の approve を持つこと（DefaultPool はコンストラクタで無限 approve 済み）。
- **動作（Effects）**:
  1. `collBalance += _amount`、`ActivePoolCollBalanceUpdated` 発火（内部関数 `_accountForReceivedColl`）
  2. `collToken.safeTransferFrom(msg.sender, address(this), _amount)` で呼出元から実トークンを pull
- **revert / 早期 return**: 呼出元不正 → `"ActivePool: Caller is neither BO nor Default Pool"`。allowance / 残高不足 → SafeERC20 revert。
- **発火イベント**: CORE-AP-EVT-007。
- **Verification**: parity / invariant=CORE-AP-INV-001

#### CORE-AP-FR-013: accountForReceivedColl（直接送付済み担保の会計反映）🔵
- **Type**: Functional ｜ **Source**: base 実装（ActivePool.sol）
- **シグネチャ**: `accountForReceivedColl(uint256 _amount)`（public）
- **目的**: 実トークンが**既に** ActivePool へ直接 transfer 済みである前提で、会計残高だけを加算する。トークン移動を伴わない receiveColl の会計版。
- **権限**: BorrowerOperations または DefaultPool のみ（CORE-AP-FR-012 と同一 require）。実コードでの呼出元は BO の `_pullCollAndSendToActivePool`（借り手からの担保預入: BO が `collToken.safeTransferFrom(borrower, activePool, amount)` で直接送付した直後に本関数で会計を同期）のみ。
- **事前条件（Checks）**: 呼出元検証。対応する実トークンが同一 tx 内で送付済みであること（呼出元の責務。ActivePool 自身は実残高を検証しない）。
- **動作（Effects）**: `collBalance += _amount`、`ActivePoolCollBalanceUpdated` 発火。
- **revert / 早期 return**: 呼出元不正 → `"ActivePool: Caller is neither BO nor Default Pool"`。
- **発火イベント**: CORE-AP-EVT-007。
- **設計上のポイント**: borrower → AP の 1 回の transferFrom で済ませ、borrower → BO → AP の 2 段転送や approve 往復を省くガス最適化。会計と実残高の整合は信頼済み呼出元（BO）に委ねる設計で、これが「collBalance は実残高の追跡値であり実残高そのものではない」（CORE-AP-INV-001）という会計方針の根拠。
- **Verification**: parity / invariant=CORE-AP-INV-001

#### CORE-AP-FR-014: setShutdownFlag（shutdown 時刻の記録と利息累積の恒久停止）🔵
- **Type**: Functional ｜ **Source**: base 実装（ActivePool.sol）
- **シグネチャ**: `setShutdownFlag()`
- **目的**: ブランチ shutdown を ActivePool の利息会計に伝搬し、以後の集計利息の発生を止める。
- **権限**: TroveManager のみ（`_requireCallerIsTroveManager`）。呼出経路は `BO.shutdown()`（TCR < SCR 時）または `BO.shutdownFromOracleFailure()`（PriceFeed からのオラクル障害通知）→ `BO._applyShutdown()` → `TM.shutdown()` → 本関数、の 1 本のみ。
- **事前条件（Checks）**: 呼出元検証のみ。ActivePool 自身は二重設定ガードを持たない（BO 側の `hasBeenShutDown` ガードにより実際には 1 回しか到達しない。TM.shutdown は BO 限定）。
- **動作（Effects）**: `shutdownTime = block.timestamp`。
- **revert / 早期 return**: 呼出元不正 → `"ActivePool: Caller is not TroveManager"`。
- **発火イベント**: なし。
- **設計上のポイント**: shutdown 後の利息会計はコード上次のとおり振る舞う。① `BO._applyShutdown` は**フラグ設定前に** `mintAggInterest()`（CORE-AP-FR-007）を呼ぶため、shutdown 時点までのペンディング集計利息は同一 tx 内で確定 mint 済みで取りこぼしがない。② フラグ設定後は `calcPendingAggInterest()` が恒久的に 0（CORE-AP-FR-002）となり、以後 `mintAggInterest` / `mintAggInterestAndAccountForTroveChange` が呼ばれても新規利息は mint されない（`lastAggUpdateTime` の更新と、TroveChange の負債・加重和反映自体は引き続き動作する）。③ batch 管理フィーは shutdown 時に自動確定されず、`calcPendingAggBatchManagementFee()` が shutdown 時刻を期間上限として以後も「shutdown までの発生分」を返す（CORE-AP-FR-004）。④ TroveManager 側の個別 Trove 利息も shutdown 時刻で打ち切られる（TM スコープで規定）。
- **Verification**: parity / unit（shutdown 後の利息 0・batch フィー打ち切り）

#### CORE-AP-FR-015: 自明 view 関数群🔵
- **Type**: Functional ｜ **Source**: base 実装（ActivePool.sol）
- **シグネチャ**: 下表（いずれも view・引数なし・権限なし）
- **目的**: 公開状態変数の自動 getter および単純な読み出し関数を提供する。

| 関数 | 返り値の意味 |
| --- | --- |
| `NAME()` | 固定文字列 `"ActivePool"` |
| `collToken()` / `borrowerOperationsAddress()` / `troveManagerAddress()` / `defaultPoolAddress()` / `jpydfToken()` / `interestRouter()` / `stabilityPool()` | コンストラクタで固定した配線アドレス（CORE-AP-FR-001） |
| `getCollBalance()` | 会計上の担保残高 `collBalance`。実トークン残高とは一致しない場合がある（直接 transfer は反映されない） |
| `aggRecordedDebt()` / `aggWeightedDebtSum()` / `lastAggUpdateTime()` | 集計利息会計のトラッカー（状態変数表参照） |
| `aggBatchManagementFees()` / `aggWeightedBatchManagementFeeSum()` / `lastAggBatchManagementFeesUpdateTime()` | batch 管理フィー会計のトラッカー |
| `shutdownTime()` | shutdown 時刻（0 = 未 shutdown） |
| `hasBeenShutDown()` | `shutdownTime != 0` |

- **Verification**: parity


### DefaultPool の機能要件（CORE-DP-FR-*）

#### CORE-DP-FR-001: コンストラクタ（アドレス配線と ActivePool への担保 approve）🔵
- **Type**: Functional ｜ **Source**: base 実装（DefaultPool.sol）
- **シグネチャ**: `constructor(IAddressesRegistry _addressesRegistry)`
- **目的**: 配線アドレスを immutable に固定し、ActivePool との担保移転経路を開通させる。
- **権限**: デプロイ時 1 回。
- **事前条件（Checks）**: なし（AddressesRegistry を信頼）。
- **動作（Effects）**:
  1. `collToken` / `troveManagerAddress` / `activePoolAddress` を取得し固定
  2. アドレス変更イベント 3 件を発火（CollToken / TroveManager / ActivePool の順）
  3. `collToken.approve(activePoolAddress, type(uint256).max)` — ActivePool が `receiveColl`（CORE-AP-FR-012）で DefaultPool から担保を pull できるようにする無限 approve
- **revert / 早期 return**: なし。
- **発火イベント**: CORE-DP-EVT-001〜003。
- **Verification**: parity / deployment テスト

#### CORE-DP-FR-002: sendCollToActivePool（ペンディング担保の ActivePool への戻し）🔵
- **Type**: Functional ｜ **Source**: base 実装（DefaultPool.sol）
- **シグネチャ**: `sendCollToActivePool(uint256 _amount)`
- **目的**: Trove のペンディング redistribution 担保ゲインが適用される際、当該分を DefaultPool の会計から外し ActivePool へ移す。
- **権限**: TroveManager のみ（`_requireCallerIsTroveManager`）。呼出箇所: TM の `_movePendingTroveRewardsToActivePool`（清算・redemption・BO 経由の全 Trove 操作・applyPendingDebt 等、ペンディング適用を伴うすべての経路。負債側の CORE-DP-FR-005 と対）。
- **事前条件（Checks）**: 呼出元検証。`_amount ≤ collBalance`（checked 演算）。
- **動作（Effects）**:
  1. `collBalance -= _amount`、`DefaultPoolCollBalanceUpdated(newCollBalance)` を発火
  2. `IActivePool(activePoolAddress).receiveColl(_amount)` を呼ぶ — ActivePool 側が会計加算し、本コントラクトの approve（CORE-DP-FR-001）を使って実トークンを pull（CORE-AP-FR-012）
- **revert / 早期 return**: 呼出元不正 → `"DefaultPool: Caller is not the TroveManager"`。残高不足 → Panic 0x11。
- **発火イベント**: CORE-DP-EVT-005。続けて ActivePool 側で CORE-AP-EVT-007。
- **設計上のポイント**: CORE-AP-FR-011（AP→DP）と対称の「送付側会計減算 → 受領側会計加算＋pull」2 段構造。
- **Verification**: parity / invariant=CORE-DP-INV-001

#### CORE-DP-FR-003: receiveColl（redistribution 担保の受領）🔵
- **Type**: Functional ｜ **Source**: base 実装（DefaultPool.sol）
- **シグネチャ**: `receiveColl(uint256 _amount)`
- **目的**: 清算 redistribution で ActivePool から移送される担保を受領し、会計残高に加算する。
- **権限**: ActivePool のみ（`_requireCallerIsActivePool`）。呼出箇所: `ActivePool.sendCollToDefaultPool`（CORE-AP-FR-011）のみ。
- **事前条件（Checks）**: 呼出元検証。ActivePool が DefaultPool へ `_amount` 以上の approve を持つこと（CORE-AP-FR-001 で無限 approve 済み）。
- **動作（Effects）**:
  1. `collBalance += _amount`
  2. `collToken.safeTransferFrom(msg.sender, address(this), _amount)` で ActivePool から実トークンを pull
  3. `DefaultPoolCollBalanceUpdated(newCollBalance)` を発火
- **revert / 早期 return**: 呼出元不正 → `"DefaultPool: Caller is not the ActivePool"`。allowance/残高不足 → SafeERC20 revert。
- **発火イベント**: CORE-DP-EVT-005。
- **Verification**: parity / invariant=CORE-DP-INV-001

#### CORE-DP-FR-004: increaseJpydfDebt（redistribution 負債の計上）🔵
- **Type**: Functional ｜ **Source**: base 実装（DefaultPool.sol）
- **シグネチャ**: `increaseJpydfDebt(uint256 _amount)`
- **目的**: 清算 redistribution の負債分を「未適用ペンディング負債」として計上する。
- **権限**: TroveManager のみ。呼出箇所: TM の `_redistributeDebtAndColl`（担保側の CORE-AP-FR-011 と対。同時に TM 側で L_jpydfDebt 等の per-unit-staked 累積子が更新される）。
- **事前条件（Checks）**: 呼出元検証のみ。
- **動作（Effects）**: `JpydfDebt += _amount`、`DefaultPoolJpydfDebtUpdated(JpydfDebt)` を発火。
- **revert / 早期 return**: 呼出元不正 → `"DefaultPool: Caller is not the TroveManager"`。
- **発火イベント**: CORE-DP-EVT-004。
- **設計上のポイント**: JpydfDebt は純粋な会計数値であり、対応する JPYdf トークンは存在しない（清算で焼却・SP offset 済みの負債の再配分簿価）。ActivePool の `aggRecordedDebt` から外れた分がここに計上され、適用時に書き戻される（CORE-AP-FR-008 の `appliedRedistJpydfDebtGain`）。
- **Verification**: parity / invariant=CORE-SYS-INV-001

#### CORE-DP-FR-005: decreaseJpydfDebt（適用済み負債の取崩し）🔵
- **Type**: Functional ｜ **Source**: base 実装（DefaultPool.sol）
- **シグネチャ**: `decreaseJpydfDebt(uint256 _amount)`
- **目的**: Trove がペンディング redistribution 負債ゲインを適用（自身の記録負債へ繰入れ）した際、当該分を未適用残高から取り崩す。
- **権限**: TroveManager のみ。呼出箇所: TM の `_movePendingTroveRewardsToActivePool`（担保側の CORE-DP-FR-002 と対）。
- **事前条件（Checks）**: 呼出元検証。`_amount ≤ JpydfDebt`（checked 演算）。
- **動作（Effects）**: `JpydfDebt -= _amount`、`DefaultPoolJpydfDebtUpdated(JpydfDebt)` を発火。
- **revert / 早期 return**: 呼出元不正 → `"DefaultPool: Caller is not the TroveManager"`。超過取崩し → Panic 0x11。
- **発火イベント**: CORE-DP-EVT-004。
- **Verification**: parity

#### CORE-DP-FR-006: 自明 view 関数群 🔵
- **Type**: Functional ｜ **Source**: base 実装（DefaultPool.sol）
- **シグネチャ**: 下表（いずれも view・権限なし）

| 関数 | 返り値の意味 |
| --- | --- |
| `NAME()` | 固定文字列 `"DefaultPool"` |
| `collToken()` / `troveManagerAddress()` / `activePoolAddress()` | コンストラクタで固定した配線アドレス |
| `getCollBalance()` | 会計上のペンディング担保残高 `collBalance`（実トークン残高とは一致しない場合がある） |
| `getJpydfDebt()` | redistribution 待ち JPYdf 負債 `JpydfDebt`。`LiquityBase.getEntireBranchDebt` の第 2 項 |

- **Verification**: parity


### CollSurplusPool の機能要件（CORE-CSP-FR-*）

#### CORE-CSP-FR-001: コンストラクタ（アドレス配線）🔵
- **Type**: Functional ｜ **Source**: base 実装（CollSurplusPool.sol）
- **シグネチャ**: `constructor(IAddressesRegistry _addressesRegistry)`
- **目的**: 配線アドレスを immutable に固定する。
- **権限**: デプロイ時 1 回。
- **事前条件（Checks）**: なし（AddressesRegistry を信頼）。
- **動作（Effects）**: `collToken` / `borrowerOperationsAddress` / `troveManagerAddress` を取得し固定。アドレス変更イベント 2 件（BO / TM）を発火。**approve は行わない**（払い出しは push 型 transfer のため不要）。
- **revert / 早期 return**: なし。
- **発火イベント**: CORE-CSP-EVT-001〜002。
- **Verification**: parity / deployment テスト

#### CORE-CSP-FR-002: accountSurplus（清算余剰の記帳）🔵
- **Type**: Functional ｜ **Source**: base 実装（CollSurplusPool.sol）
- **シグネチャ**: `accountSurplus(address _account, uint256 _amount)`
- **目的**: 清算で発生した余剰担保を `_account`（清算時点の Trove owner）の請求可能残高として記帳する。
- **権限**: TroveManager のみ（`_requireCallerIsTroveManager`）。呼出箇所: TM の清算処理（`_liquidate`。余剰金額の算定は TM の offset/redistribution 計算による）。
- **事前条件（Checks）**: 呼出元検証のみ（`_amount > 0` の保証は TM 側の分岐による）。
- **動作（Effects）**:
  1. `balances[_account] += _amount`
  2. `collBalance += _amount`
  3. `CollBalanceUpdated(_account, newAmount)` を発火
- **revert / 早期 return**: 呼出元不正 → `"CollSurplusPool: Caller is not TroveManager"`。
- **発火イベント**: CORE-CSP-EVT-003。
- **設計上のポイント**: 本関数は**記帳のみ**で実トークンを受け取らない。対応する実トークンは同一清算 tx 内で TM が `ActivePool.sendColl(collSurplusPool, totalCollSurplus)`（CORE-AP-FR-010）によりバッチ送付するため、tx 完了時点で会計と実残高が整合する（tx 途中では記帳が先行する）。残高は累積型で、同一 owner が複数回清算されれば加算される。
- **Verification**: parity / invariant=CORE-CSP-INV-001

#### CORE-CSP-FR-003: claimColl（余剰担保の請求・払い出し）🔵
- **Type**: Functional ｜ **Source**: base 実装（CollSurplusPool.sol）
- **シグネチャ**: `claimColl(address _account)`
- **目的**: `_account` の請求可能残高全額を本人へ払い出す。
- **権限**: BorrowerOperations のみ（`_requireCallerIsBorrowerOperations`）。呼出経路は `BO.claimCollateral()` のみで、BO は `msg.sender` を `_account` として渡す——すなわち**受益者本人だけが自分の残高を、自分のアドレス宛にのみ**請求できる（受取先指定は提供されない）。
- **事前条件（Checks）**:
  - 呼出元が BO
  - `claimableColl = balances[_account] > 0`
- **動作（Effects）**:
  1. `balances[_account] = 0`、`CollBalanceUpdated(_account, 0)` を発火（全額請求のみ。部分請求は不可）
  2. `collBalance -= claimableColl`、`CollSent(_account, claimableColl)` を発火
  3. `collToken.safeTransfer(_account, claimableColl)` で実トークンを送付
- **revert / 早期 return**: 呼出元不正 → `"CollSurplusPool: Caller is not Borrower Operations"`。残高ゼロ → `"CollSurplusPool: No collateral available to claim"`。transfer 失敗 → SafeERC20 revert。
- **発火イベント**: CORE-CSP-EVT-003 / CORE-CSP-EVT-004。
- **設計上のポイント**: 残高ゼロ化（Effects）→ transfer（Interactions）の CEI 順序により再入で二重請求できない（担保 dToken は転送フックを持たない ERC-20 だが、順序自体も安全側）。請求期限はなく、無期限に保管される。
- **Verification**: parity / unit（ゼロ残高 revert・全額払い出し・再請求 revert）

#### CORE-CSP-FR-004: 自明 view 関数群 🔵
- **Type**: Functional ｜ **Source**: base 実装（CollSurplusPool.sol）
- **シグネチャ**: 下表（いずれも view・権限なし）

| 関数 | 返り値の意味 |
| --- | --- |
| `NAME()` | 固定文字列 `"CollSurplusPool"` |
| `collToken()` / `borrowerOperationsAddress()` / `troveManagerAddress()` | コンストラクタで固定した配線アドレス |
| `getCollBalance()` | 会計上の余剰担保総額 `collBalance`（実トークン残高とは一致しない場合がある） |
| `getCollateral(_account)` | `_account` の請求可能残高 `balances[_account]`。フロントエンドの「claim 可能額」表示に使用 |

- **Verification**: parity


### GasPool の機能要件（CORE-GP-FR-*）

#### CORE-GP-FR-001: コンストラクタ（BO・TM への WETH 無限 approve）🔵
- **Type**: Functional ｜ **Source**: base 実装（GasPool.sol）
- **シグネチャ**: `constructor(IAddressesRegistry _addressesRegistry)`
- **目的**: ガス補償 WETH の払い出し経路を、デプロイ時の approve 設定だけで恒久的に確立する。
- **権限**: デプロイ時 1 回。
- **事前条件（Checks）**: なし（AddressesRegistry を信頼）。
- **動作（Effects）**:
  1. `WETH = _addressesRegistry.WETH()`、BorrowerOperations / TroveManager のアドレスを取得（いずれもローカル変数。ストレージには何も保存しない）
  2. `WETH.approve(borrowerOperations, type(uint256).max)` — BO が Trove close 時にガス補償を借り手（受領者）へ返金できるようにする
  3. `WETH.approve(troveManager, type(uint256).max)` — TM が清算時にガス補償を liquidator へ支払えるようにする
- **revert / 早期 return**: なし。
- **発火イベント**: なし（GasPool 自身はイベントを定義しない。WETH 側の Approval のみ）。
- **設計上のポイント**: 関数・状態を一切持たないため、デプロイ後の攻撃面はゼロ。WETH を動かせるのは approve を受けた BO / TM のみで、両者の transferFrom 呼出条件（close 時返金・清算時支払い）が事実上のアクセス制御になる。approve の取り消し・再設定手段は存在しない（コア配線が immutable である前提と整合）。誤って直接送付された WETH や他トークンの回収手段もない。残高の入出金フロー（open で +`ETH_GAS_COMPENSATION` / close・清算で −`ETH_GAS_COMPENSATION`）の規定は BO / TM スコープ。
- **Verification**: parity / deployment テスト（approve 値 = type(uint256).max が BO・TM 双方に設定されること）


### SortedTroves の機能要件（CORE-ST-FR-*）

#### CORE-ST-FR-001: constructor（アドレス束縛と番兵ノード初期化）🔵
- **Type**: Functional ｜ **Source**: base 実装（SortedTroves.sol）
- **シグネチャ**: `constructor(IAddressesRegistry _addressesRegistry)`
- **目的**: AddressesRegistry から書込み権限者（BO/TM）を immutable に束縛し、番兵ノードを初期化する。
- **権限**: デプロイ手順の一部。
- **事前条件（Checks）**: なし（入力検証なし。AddressesRegistry の配線正しさはデプロイ手順に依存）。
- **動作（Effects）**:
  1. `nodes[ROOT_NODE_ID].nextId = nodes[ROOT_NODE_ID].prevId = ROOT_NODE_ID`（番兵の自己ループ＝空リスト。ROOT_NODE_ID が 0 である限り技術的には冗長だが明示的に設定）
  2. `troveManager` / `borrowerOperationsAddress` を AddressesRegistry から読み取り immutable に固定
  3. `TroveManagerAddressChanged` / `BorrowerOperationsAddressChanged` を発火
- **revert / 早期 return**: なし。
- **発火イベント**: CORE-ST-EVT-001 / CORE-ST-EVT-002。
- **Verification**: parity / deployment テスト。

#### CORE-ST-FR-002: insert（非 batch ノードの挿入）🔵
- **Type**: Functional ｜ **Source**: base 実装（SortedTroves.sol）
- **シグネチャ**: `insert(uint256 _id, uint256 _annualInterestRate, uint256 _prevId, uint256 _nextId)`
- **目的**: 新規 Trove（非 batch）を金利順の正しい位置にリストへ追加する。利用箇所: BO `openTrove` / batch 離脱（`_removeFromBatch`）/ zombie Trove の通常復帰（`_reInsertIntoSortedTroves`）。
- **権限**: **BorrowerOperations のみ**（`_requireCallerIsBorrowerOperations`）。
- **事前条件（Checks）**:
  - `!contains(_id)`（既存ノードでない）
  - `_id != ROOT_NODE_ID`（0 は番兵 ID のため不可）
  - `_id` が実在する Trove かどうかは検証しない（呼出元 BO を信頼）
- **動作（Effects）**:
  1. hint `(_prevId, _nextId)` を `_validInsertPosition`（CORE-ST-FR-008）で検証。無効なら `_findInsertPosition`（CORE-ST-FR-009）で hint を起点に正しい位置を再探索（**hint 無効でも revert しない**。hint はガス節約のためだけに働く）
  2. 確定位置に単一ノード slice（head=tail=`_id`）としてリンクを張替え挿入（`_insertSliceIntoVerifiedPosition`: prev.next→id、id.prev→prev、id.next→next、next.prev→id の 4 リンク更新）
  3. `nodes[_id].exists = true`、`++size`（`batchId` は 0 のまま＝非 batch）
- **revert / 早期 return**: 非 BO → `"SortedTroves: Caller is not BorrowerOperations"`；既存ノード → `"SortedTroves: List already contains the node"`；`_id == 0` → `"SortedTroves: _id cannot be the root node's ID"`。
- **発火イベント**: なし。
- **設計上のポイント**: **同率金利の挿入位置** — 位置の有効条件が「prev 側は `rate(prev) >= 新金利`（同率可）、next 側は `新金利 > rate(next)`（厳密）」と非対称なため、既存の同率ノードの**前（head 側）には挿入できず、同率ノード群の直後（tail 側）に必ず入る**。Redemption は tail（最低金利）から処理されるため、**同率では後から入った Trove が先に redemption を受ける**（last-in, first-redeemed）。後発者が既存の同率 Trove の後ろ（redemption 的に安全な側）へ割り込めない順序規律であり、既存ポジションの redemption 保護順位を保つ。
- **Verification**: parity, invariant=CORE-ST-INV-001 / CORE-ST-INV-002 / CORE-ST-INV-004。

#### CORE-ST-FR-003: remove（非 batch ノードの除去）🔵
- **Type**: Functional ｜ **Source**: base 実装（SortedTroves.sol）
- **シグネチャ**: `remove(uint256 _id)`
- **目的**: 非 batch ノードをリストから取り除く。利用箇所: BO は batch 加入時の付替え（`setInterestBatchManager`）のみ。TM は redemption による zombie 化（残債が `MIN_DEBT` 未満。値は CORE-LIB-FR-002）と清算・クローズ（`_closeTrove`。owner の `closeTrove` もこの経路）。
- **権限**: **BorrowerOperations または TroveManager**（`_requireCallerIsBOorTM`）。
- **事前条件（Checks）**:
  - `contains(_id)`（リストに存在）
  - `!isBatchedNode(_id)`（batch ノードは `removeFromBatch()` を使う）
- **動作（Effects）**:
  1. 前後ノードのリンクを直結して slice（単一ノード）をリストから外す（`_removeSlice`）
  2. `delete nodes[_id]`（exists を含め全消去）、`--size`
- **revert / 早期 return**: 非 BO/TM → `"SortedTroves: Caller is not BorrowerOperations nor TroveManager"`；不存在 → `"SortedTroves: List does not contain the id"`；batch ノード → `"SortedTroves: Must use removeFromBatch() to remove batched node"`。
- **発火イベント**: なし。
- **Verification**: parity, invariant=CORE-ST-INV-002 / CORE-ST-INV-004。

#### CORE-ST-FR-004: reInsert（金利変更に伴う非 batch ノードの再挿入）🔵
- **Type**: Functional ｜ **Source**: base 実装（SortedTroves.sol）
- **シグネチャ**: `reInsert(uint256 _id, uint256 _newAnnualInterestRate, uint256 _prevId, uint256 _nextId)`
- **目的**: 金利変更後の Trove を新金利に対応する位置へ移動する。利用箇所: BO `adjustTroveInterestRate`。
- **権限**: **BorrowerOperations のみ**。
- **事前条件（Checks）**:
  - `contains(_id)`
  - `!isBatchedNode(_id)`（batch ノードの個別 reInsert は不可。batch 全体は CORE-ST-FR-007）
- **動作（Effects）**:
  1. hint を検証し、無効なら再探索（CORE-ST-FR-002 と同じ規則。新金利 `_newAnnualInterestRate` 基準）
  2. 確定位置が現位置と同じ（確定 `nextId` が自分自身、または確定 `prevId` が自分自身＝slice の直前/直後）なら**リンク張替えを行わず no-op**
  3. 位置が変わる場合のみ、slice を外して（`_removeSlice`。外した slice 内部のリンクは保持）新位置へ挿入
- **revert / 早期 return**: 非 BO → `"SortedTroves: Caller is not BorrowerOperations"`；不存在 → `"SortedTroves: List does not contain the id"`；batch ノード → `"SortedTroves: Must not reInsert() batched node"`。
- **発火イベント**: なし。
- **設計上のポイント**: 同率金利時の位置決め規則は CORE-ST-FR-002 と同一であり、金利を同率帯へ変更した Trove も既存同率ノード群の tail 側（redemption 先頭側）に置かれる。なお、呼出時点で TM 側の金利はまだ旧値でもよい。位置探索は slice をリストから外す**前**に行われるため走査中に自ノードの旧金利が参照され得るが、自ノード隣接位置に確定した場合は no-op 判定が吸収し、最終的な順序は引数 `_newAnnualInterestRate` に対して整合する。
- **Verification**: parity, invariant=CORE-ST-INV-001 / CORE-ST-INV-002。

#### CORE-ST-FR-005: insertIntoBatch（batch へのノード追加）🔵
- **Type**: Functional ｜ **Source**: base 実装（SortedTroves.sol）
- **シグネチャ**: `insertIntoBatch(uint256 _troveId, BatchId _batchId, uint256 _annualInterestRate, uint256 _prevId, uint256 _nextId)`
- **目的**: Trove を batch の slice に追加する。利用箇所: BO `openTroveAndJoinInterestBatchManager` / `setInterestBatchManager` / zombie Trove の batch 復帰（`_reInsertIntoSortedTroves`）。
- **権限**: **BorrowerOperations のみ**。
- **事前条件（Checks）**:
  - `!contains(_troveId)`
  - `_troveId != ROOT_NODE_ID`
  - `_batchId.isNotZero()`（BatchId=0 は「非 batch」の意味で予約）
- **動作（Effects）**:
  1. **batch が空（`batches[_batchId].tail == UNINITIALIZED_ID`）の場合**: hint と `_annualInterestRate`（batch の金利）に基づき通常の位置探索で単一ノード slice として挿入し、`batches[_batchId].head = _troveId` を設定（batch の初期化）
  2. **batch が非空の場合**: 現 batch tail の直後（`batchTail` と `nodes[batchTail].nextId` の間）へ**検証なしで直接**連結（このパスでは `_annualInterestRate` と hint は使用されない。batch メンバーは全員 batch の金利を共有するため、tail 直後への追記が順序を保つ）
  3. いずれの場合も `batches[_batchId].tail = _troveId`（**新メンバーは常に batch slice の末尾＝tail 側**）
  4. `nodes[_troveId].batchId = _batchId`、`exists = true`、`++size`
- **revert / 早期 return**: 非 BO → `"SortedTroves: Caller is not BorrowerOperations"`；既存ノード → `"SortedTroves: List already contains the node"`；`_troveId == 0` → `"SortedTroves: _troveId cannot be the root node's ID"`；`_batchId == 0` → `"SortedTroves: _batchId cannot be zero"`。
- **発火イベント**: なし。
- **設計上のポイント**: batch 内も「新規参加者が tail 側」＝リスト全体の同率規律（CORE-ST-FR-002）と同方向。batch slice の tail はリスト末尾（最低金利端）に近い側なので、**同一 batch 内では後から加入した Trove が先に redemption を受ける**。
- **Verification**: parity, invariant=CORE-ST-INV-001 / CORE-ST-INV-003 / CORE-ST-INV-004。

#### CORE-ST-FR-006: removeFromBatch（batch ノードの除去）🔵
- **Type**: Functional ｜ **Source**: base 実装（SortedTroves.sol）
- **シグネチャ**: `removeFromBatch(uint256 _id)`
- **目的**: batch に属するノードをリストおよび batch から取り除く。利用箇所: BO batch 離脱（`_removeFromBatch`）、TM redemption による zombie 化 / 清算・クローズ（`_closeTrove`）。
- **権限**: **BorrowerOperations または TroveManager**。
- **事前条件（Checks）**:
  - `nodes[_id].batchId.isNotZero()`（batchId 非ゼロが存在判定を兼ねる。非 batch ノード・不存在ノードはともにここで弾かれる）
- **動作（Effects）**:
  1. 単独メンバー（`batch.head == _id && batch.tail == _id`）なら `delete batches[batchId]`（batch を空に戻す。同じ BatchId で後日 `insertIntoBatch` により再初期化可能）
  2. `_id` が batch head なら `batches[batchId].head = nodes[_id].nextId`、batch tail なら `batches[batchId].tail = nodes[_id].prevId`（slice の端を内側に詰める）
  3. slice からノードを外し（`_removeSlice`）、`delete nodes[_id]`、`--size`
- **revert / 早期 return**: 非 BO/TM → `"SortedTroves: Caller is not BorrowerOperations nor TroveManager"`；非 batch ノード（不存在含む） → `"SortedTroves: Must use remove() to remove non-batched node"`。
- **発火イベント**: なし。
- **Verification**: parity, invariant=CORE-ST-INV-002 / CORE-ST-INV-003 / CORE-ST-INV-004。

#### CORE-ST-FR-007: reInsertBatch（batch slice 全体の再挿入）🔵
- **Type**: Functional ｜ **Source**: base 実装（SortedTroves.sol）
- **シグネチャ**: `reInsertBatch(BatchId _id, uint256 _newAnnualInterestRate, uint256 _prevId, uint256 _nextId)`
- **目的**: batch manager の金利変更時に、batch の全メンバー（slice `[head..tail]`）を**内部の隣接関係・順序を保ったまま一括で**新金利位置へ移動する。利用箇所: BO `setBatchManagerAnnualInterestRate`（batch が空でない場合のみ呼ばれる）。
- **権限**: **BorrowerOperations のみ**。
- **事前条件（Checks）**:
  - `batches[_id].head != UNINITIALIZED_ID`（batch が存在＝非空）
- **動作（Effects）**:
  1. hint を新金利で検証し、無効なら再探索（CORE-ST-FR-008/009）
  2. 確定位置が現位置と同じ（確定 `nextId == slice head` または確定 `prevId == slice tail`）なら no-op
  3. 位置が変わる場合、slice `[batch.head .. batch.tail]` を丸ごと外し（メンバー間リンクは保持）、新位置へ一括挿入。`batches[_id]` の head/tail は不変（slice 内部は変化しないため）
- **revert / 早期 return**: 非 BO → `"SortedTroves: Caller is not BorrowerOperations"`；batch 不存在（空） → `"SortedTroves: List does not contain the batch"`。
- **発火イベント**: なし。
- **設計上のポイント**: slice 移動は端 4 本のリンク張替えだけで完了し、**batch メンバー数に依存しない O(1)**。これが「batch の金利一括変更が安価」という batch 機構のガス設計の核。同率規律も CORE-ST-FR-002 と同一（同率の既存ノード・既存 batch の tail 側に入る）。
- **Verification**: parity, invariant=CORE-ST-INV-001 / CORE-ST-INV-003。

#### CORE-ST-FR-008: validInsertPosition（hint 位置の有効性検証）🔵
- **Type**: Functional ｜ **Source**: base 実装（SortedTroves.sol）
- **シグネチャ**: `validInsertPosition(uint256 _annualInterestRate, uint256 _prevId, uint256 _nextId) → bool`（external view。内部判定 `_validInsertPosition` の external ラッパー）
- **目的**: `(_prevId, _nextId)` の間が金利 `_annualInterestRate` のノードの挿入位置として有効かを判定する。挿入・再挿入系（CORE-ST-FR-002/004/005/007）の hint 検証の規範。
- **権限**: なし（view）。
- **動作（判定規則）**: 以下を**すべて**満たすとき true:
  1. **隣接**: `nodes[_prevId].nextId == _nextId` かつ `nodes[_nextId].prevId == _prevId`
  2. **batch 内部でない**: `_prevId` と `_nextId` が同一の非ゼロ batch に属さない（`prevBatchId != nextBatchId || prevBatchId == 0`。batch slice の途中に他ノードを挟むと連続性（CORE-ST-INV-003）が壊れるため）
  3. **金利順**: `_prevId == ROOT_NODE_ID`（先頭挿入）または `rate(_prevId) >= _annualInterestRate`、**かつ** `_nextId == ROOT_NODE_ID`（末尾挿入）または `_annualInterestRate > rate(_nextId)`（rate は `troveManager.getTroveAnnualInterestRate`）
- **revert / 早期 return**: なし（bool を返すのみ）。
- **設計上のポイント**: 金利条件の**非対称性（prev 側 `>=`・next 側 `>`）が同率時の位置を一意に規定**する: 新ノードは同率の既存ノードを `prev` にはできるが `next` にはできない＝**同率ノード群の直後（tail 側）のみが有効位置**。また空リストでは番兵の自己ループにより `(0, 0)` が有効。番兵（ROOT）は金利比較を免除されるため先頭・末尾への挿入も同一規則で扱える。
- **Verification**: parity, unit（境界: 空リスト・先頭・末尾・同率・batch 境界）。

#### CORE-ST-FR-009: findInsertPosition（挿入位置の探索・hint fallback）🔵
- **Type**: Functional ｜ **Source**: base 実装（SortedTroves.sol）
- **シグネチャ**: `findInsertPosition(uint256 _annualInterestRate, uint256 _prevId, uint256 _nextId) → (uint256 prevId, uint256 nextId)`（external view。内部探索 `_findInsertPosition` の external ラッパー）
- **目的**: hint を起点に、金利 `_annualInterestRate` の有効な挿入位置を返す。「元の隣接ノードのうち高々 1 つが移動/削除された」想定で最適化されているが、**hint の良否や他者の介入によらず必ず正しい位置を返す**。external ラッパーは主にオフチェーン（フロントエンド。`HintHelpers.getApproxHint` で得た近似 hint の精密化）用。
- **権限**: なし（view）。
- **動作（探索手順）**:
  1. `_prevId == ROOT_NODE_ID`（「先頭の前」hint）→ 直ちに head から**下降探索**（`_nextId` は参照しない）
  2. そうでなく `_prevId` が不存在、または `rate(_prevId) < _annualInterestRate` → `_prevId` を無効化（`BAD_HINT`）
  3. `_nextId == ROOT_NODE_ID`（「末尾の後」hint）→ tail から**上昇探索**（このとき `_prevId` の良否は使われない）
  4. そうでなく `_nextId` が不存在、または `_annualInterestRate <= rate(_nextId)` → `_nextId` を無効化
  5. 両 hint 無効 → head から下降探索（**fallback の全走査**。最悪 O(n)）
  6. `_prevId` のみ無効 → `_nextId` の属する batch の head から上昇探索
  7. `_nextId` のみ無効 → `_prevId` の属する batch の tail から下降探索
  8. 両 hint 有効 → 下降（`_prevId` の batch tail 起点）と上昇（`_nextId` の batch head 起点）を**交互に 1 ステップずつ**進め、先に位置を確定した側を返す（どちらかの hint が正解に近いことへの賭け）
- **停止条件**: 下降＝「next が ROOT、または `_annualInterestRate > rate(next)`」／上昇＝「prev が ROOT、または `rate(prev) >= _annualInterestRate`」（CORE-ST-FR-008 の金利条件と同値。よって返る位置は常に有効、かつ同率では同率群の直後に確定）。
- **走査単位**: 1 ステップは batch を 1 単位として跳ぶ（`_skipToBatchTail`/`_skipToBatchHead`）。batch メンバーは金利が共通なので batch 内部は比較不要であり、探索コストはノード総数ではなく「非 batch ノード数 ＋ batch 数」に比例。1 ステップごとに TM への金利照会（外部 staticcall）が 1 回発生する。
- **revert / 早期 return**: なし（`_descendAndAscendList` 末尾の `assert(false)` は到達不能の防御）。
- **Verification**: parity, unit（hint 無効化の 4 分岐・両方向探索の収束）, fuzz（任意 hint で結果位置が常に valid）。

#### CORE-ST-FR-010: 一覧系 view 関数・自動 getter 群 🔵
- **Type**: Functional ｜ **Source**: base 実装（SortedTroves.sol）
- **シグネチャ**: 下表（すべて view。状態変化なし・revert なし）
- **目的**: リスト走査・存在判定・構造参照を外部（TM の redemption ループ、BO、HintHelpers / MultiTroveGetter / DebtInFrontHelper / RedemptionHelper、フロントエンド）へ提供する。

| 関数 | 返り値の意味 |
| --- | --- |
| `contains(_id)` | `nodes[_id].exists`。リスト所属判定（zombie Trove は false） |
| `isBatchedNode(_id)` | `nodes[_id].batchId != 0`。batch 所属判定 |
| `isEmptyBatch(_id)` | `batches[_id].head == 0`。batch が空（未初期化含む）か |
| `isEmpty()` | `size == 0` |
| `getSize()` | `size`（public 変数 `size()` getter と同値） |
| `getFirst()` | `nodes[0].nextId`＝先頭（**最高金利**）。空リストでは 0 |
| `getLast()` | `nodes[0].prevId`＝末尾（**最低金利**）。空リストでは 0 |
| `getNext(_id)` | `nodes[_id].nextId`＝次（より低金利側）。末尾では 0（ROOT） |
| `getPrev(_id)` | `nodes[_id].prevId`＝前（より高金利側）。先頭では 0（ROOT） |
| `NAME()` | 定数 `"SortedTroves"` |
| `size()` / `nodes(uint256)` / `batches(BatchId)` / `borrowerOperationsAddress()` / `troveManager()` | public 状態変数の自動 getter（§7 の表を参照） |

- **設計上のポイント**: 走査の終端判定は「`getNext`/`getPrev` が `ROOT_NODE_ID`（=0）を返したら停止」。`getFirst`/`getLast` も空リストでは 0 を返すため、呼出側は 0 を「ノードなし」として扱う必要がある。
- **Verification**: parity。


### TroveNFT の機能要件（CORE-TN-FR-*）

#### CORE-TN-FR-001: constructor（name/symbol の導出とアドレス束縛）🔵/🟡
- **Type**: Functional ｜ **Source**: OZ ERC721 + DF deployed surface（JPYdfTroveNFT.sol; CORE-MOD-007）
- **シグネチャ**: `constructor(IAddressesRegistry _addressesRegistry)`
- **目的**: AddressesRegistry から TM・担保トークン・MetadataNFT・JpydfToken を immutable に束縛し、コレクション名を担保トークン由来で確定する。
- **権限**: デプロイ手順の一部。
- **動作（Effects）**:
  1. DF deployed surface は ERC721 コンストラクタに `name = "JPYdf - " + collToken.name()`、`symbol = "JPYdf_" + collToken.symbol()` を渡す（**デプロイ時点の担保トークンの name()/symbol() を読み取り、以後固定**）。
  2. `troveManager` / `collToken` / `metadataNFT` / `jpydfToken` を immutable に固定
- **revert / 早期 return**: なし（collToken の name()/symbol() 呼出が失敗すればデプロイ失敗）。
- **発火イベント**: なし。
- **設計上のポイント**: jpydf では collToken ＝ dToken（[dToken.md](./dToken.md)）であり、コレクション名は dToken の name/symbol に従う。dToken 側の名称は `setTokenInfo` で確定する遅延初期化のため、**active branch は dToken の `setTokenInfo` 完了後に TroveNFT を deploy し、collection を確定名で固定しなければならない**。Underlying 未 binding の inert branch は `setTokenInfo` を行わず、deploy 時の placeholder collection name/symbol が恒久化することを許容する。固定されるのは ERC-721 collection の `name()` / `symbol()` のみで、`JPYdfMetadataNFT` が生成する JSON/SVG は [CORE-TN-FR-006](#core-tn-fr-006-jpydfmetadatanft--オンチェーンメタデータ描画catalog) の動的参照により後続の dToken 名称確定へ追従する。DF deployed surface は collection metadata だけを変更し、所有権 semantics は変更しない。
- **Verification**: parity / deployment テスト（active は `setTokenInfo` 後に deploy、inert は placeholder 固定を許容）、🟡 delta test（JPYdf name/symbol）。

#### CORE-TN-FR-002: mint（Trove 開設時の NFT 発行）🔵/🟡
- **Type**: Functional ｜ **Source**: OZ v4.9 ERC721 + DF deployed surface（JPYdfTroveNFT.sol; CORE-MOD-007）
- **シグネチャ**: `mint(address _owner, uint256 _troveId)`
- **目的**: Trove 開設時に所有者へ tokenId＝troveId の NFT を発行する。呼出箇所: TM `onOpenTrove` / `onOpenTroveAndJoinBatch`（いずれも BO 起点）。
- **権限**: **TroveManager のみ**（`_requireCallerIsTroveManager`）。
- **事前条件（Checks）**（OZ `_mint` 由来）:
  - `_owner != address(0)`
  - tokenId `_troveId` が未発行
- **動作（Effects）**:
  1. `_mint(_owner, _troveId)`: `_balances[_owner] += 1`、`_owners[_troveId] = _owner`
  2. `Transfer(address(0), _owner, _troveId)` を発火
- **revert / 早期 return**: 非 TM → `JPYdfTroveNFT__CallerIsNotTroveManager()`；`_owner == 0` → `"ERC721: mint to the zero address"`；既発行 → `"ERC721: token already minted"`。
- **発火イベント**: CORE-TN-EVT-001（Transfer, from=0）。
- **設計上のポイント**: `_safeMint` ではなく **`_mint`** を使用＝mint 時に受領者の `onERC721Received` を呼ばない。openTrove フローに受領者コールバック（reentrancy・受領拒否による開設 DoS）を持ち込まないための選択であり、ERC721Receiver 未実装のコントラクトも Trove を所有できる。
- **Verification**: parity, unit（TM 限定・二重 mint 不可）、🟡 delta test（非 TM custom error）。

#### CORE-TN-FR-003: burn（Trove クローズ・清算時の NFT 焼却）🔵/🟡
- **Type**: Functional ｜ **Source**: OZ v4.9 ERC721 + DF deployed surface（JPYdfTroveNFT.sol; CORE-MOD-007）
- **シグネチャ**: `burn(uint256 _troveId)`
- **目的**: Trove の終端（owner によるクローズ／清算）で NFT を焼却する。呼出箇所: TM `_closeTrove`（status が `closedByOwner` / `closedByLiquidation` になる経路）。zombie 化では焼却されない。
- **権限**: **TroveManager のみ**。
- **事前条件（Checks）**（OZ `_burn` 由来）: tokenId `_troveId` が存在（`ownerOf` 解決可能）。
- **動作（Effects）**:
  1. `_burn(_troveId)`: 個別承認をクリアし、`_balances[owner] -= 1`、`delete _owners[_troveId]`
  2. `Transfer(owner, address(0), _troveId)` を発火
- **revert / 早期 return**: 非 TM → `JPYdfTroveNFT__CallerIsNotTroveManager()`；不存在 token → `"ERC721: invalid token ID"`。
- **発火イベント**: CORE-TN-EVT-001（Transfer, to=0）。
- **Verification**: parity, unit（TM 限定・不存在 burn の revert）、🟡 delta test（非 TM custom error）。

#### CORE-TN-FR-004: tokenURI（MetadataNFT 委譲によるオンチェーンメタデータ）🔵
- **Type**: Functional ｜ **Source**: DF deployed surface（JPYdfTroveNFT.sol）
- **シグネチャ**: `tokenURI(uint256 _tokenId) → string`（public view、`ERC721`/`IERC721Metadata` の override）
- **目的**: Trove の現況を反映したメタデータ URI を**外部依存なし（フルオンチェーン）**で返す。
- **権限**: なし（view）。
- **事前条件（Checks）**: `_tokenId` が存在する NFT であること（`ownerOf` が revert しない）。
- **動作（Effects）**:
  1. `troveManager.getLatestTroveData(_tokenId)` で最新の Trove 状態（利息・再分配込みの `entireColl` / `entireDebt` / `annualInterestRate`）を取得
  2. `IMetadataNFT.TroveData` を組み立てる: `_tokenId`、`_owner = ownerOf(_tokenId)`、`_collToken`（dToken アドレス）、`_jpydfToken`、`_collAmount = entireColl`、`_debtAmount = entireDebt`、`_interestRate = annualInterestRate`、`_status = troveManager.getTroveStatus(_tokenId)`
  3. `metadataNFT.uri(troveData)` の返り値（`data:application/json;base64,…`。CORE-TN-FR-006）をそのまま返す
- **revert / 早期 return**: 不存在 token → `"ERC721: invalid token ID"`（`ownerOf` 由来）。
- **発火イベント**: なし（view）。
- **設計上のポイント**: 値は呼出時点で動的に算出されるため、同じ token でも debt/coll/金利/status の変化に追従する（zombie 状態でも NFT は存続し status が "Below Min Debt" と表示される）。担保数量は dToken 建て（18 decimals。[dToken.md](./dToken.md)）の生値が表示される。
- **Verification**: parity, unit（status 別・zombie・不存在 revert）。

#### CORE-TN-FR-005: ERC-721 標準面（移転・承認・照会・ERC-165）🔵
- **Type**: Functional ｜ **Source**: base 実装（OZ v4.9 ERC721 継承）
- **シグネチャ**: `transferFrom` / `safeTransferFrom`（2 オーバーロード）/ `approve` / `setApprovalForAll` / `getApproved` / `isApprovedForAll` / `balanceOf` / `ownerOf` / `name` / `symbol` / `supportsInterface`
- **目的**: ERC-721 標準に完全準拠した所有・承認・移転を提供する。**NFT の移転＝Trove 所有権の移転そのもの**（移転後は新保有者だけが BO 経由で Trove を操作できる。所有者検証・add/remove manager の扱いは BO 節を参照）。
- **権限**: ERC-721 標準どおり（owner / approved / operator）。
- **動作（Effects）**: OZ v4.9 `ERC721` の標準実装そのまま。オーバーライドによる挙動変更・転送フック・一時停止機構は**ない**。`supportsInterface` は `IERC721` / `IERC721Metadata` / `IERC165` に true。
- **revert / 早期 return**: OZ v4.9 標準の require 文字列（`"ERC721: caller is not token owner or approved"`、`"ERC721: invalid token ID"`、`"ERC721: transfer to non ERC721Receiver implementer"`（safe 系）等）。
- **設計上のポイント**: 非標準点なし。Trove 固有の制約（クローズ済み Trove の NFT は burn 済みで移転不能、など）はすべて mint/burn のライフサイクル同期（CORE-TN-FR-002/003）から導かれ、transfer 経路には独自検証を追加しない。
- **Verification**: parity（ERC-721 標準挙動）。

#### CORE-TN-FR-006: JPYdfMetadataNFT — オンチェーンメタデータ描画（catalog）🔵/🟡
- **Type**: Functional ｜ **Source**: DF deployed metadata surface（`Interfaces/IMetadataNFT.sol` / `NFTMetadata/JPYdfMetadataNFT.sol` / `JPYdfBaseSVG.sol`; CORE-MOD-007）
- **シグネチャ**: `uri(TroveData memory _troveData) → string`（public view）
- **目的**: TroveData を入力として、ERC-721 メタデータ JSON（SVG 画像込み）を完全オンチェーンで生成する。TroveNFT から `tokenURI` ごとに呼ばれる描画専用コントラクト（状態変化なし）。
- **入力**: `IMetadataNFT.TroveData { uint256 _tokenId; address _owner; address _collToken; address _jpydfToken; uint256 _collAmount; uint256 _debtAmount; uint256 _interestRate; ITroveManager.Status _status }`
- **出力**: `data:application/json;base64,<base64(JSON)>`。JSON の内容:
  - `name`: `"JPYdf - " + collToken.name()`（呼出時に動的取得）。
  - `description`: JPYdf 文言の固定文（"JPYdf is a collateralized debt protocol. Users can lock up <symbol> to mint JPYdf …"）。
  - `image`: `data:image/svg+xml;base64,<base64(SVG)>` — 300×484 のカード型 SVG。固定要素（背景・SSTORE2 から読み出す Geist フォント・"Collateral"/"Debt"/"Interest Rate"/"Owner" のラベル。deployed variant は固定 debt 表記を "JPYdf" とする）＋ 担保 symbol hash と tokenId から決定論的に生成される bauhaus 幾何パターン ＋ 動的テキスト（省略形 troveId `0x1234…abcd`・owner アドレス・登録済み asset がある場合のみ表示する担保ロゴ・status 表示・debt/coll/金利の数値）
  - `attributes`: 6 項目 — `Collateral Token`（アドレス hex）/ `Collateral Amount`（10 進生値）/ `Debt Token`（アドレス hex）/ `Debt Amount`（10 進生値）/ `Interest Rate`（1e18 スケール生値）/ `Status`（文字列）
- **Status 文字列マップ**（`_status2Str`）: `active` → `"Active"`、`closedByOwner` → `"Closed"`、`closedByLiquidation` → `"Liquidated"`、`zombie` → `"Below Min Debt"`、その他（`nonExistent`）→ `""`（tokenURI 経由では burn 済み token が先に revert するため実質到達しない）。
- **revert / 早期 return**: なし（view。collToken の name()/symbol() 呼出失敗時を除く）。
- **構成（catalog）**: `utils/` 配下は描画ライブラリであり個別仕様化しない — `JSON.sol`（json: メタデータ JSON 組立・base64 encode）/ `SVG.sol`（svg: SVG 要素 DSL）/ `JPYdfBaseSVG.sol`（カードの固定レイアウト・動的テキスト配置）/ `bauhaus.sol`（幾何パターン生成）/ `Utils.sol`（utils/numUtils: 文字列・数値整形。Solady `LibString` 利用）/ `FixedAssets.sol`（`FixedAssetReader`: constructor で nonzero SSTORE2 ポインタと `bytes4 → {start, end}` の範囲表を登録し、Geist フォント、JPYdf ロゴ、登録済み collateral ロゴ等の固定アセットを `readAsset(bytes4)` で読み出す。未登録 collateral ロゴは描画しない）。
- **補助 view**: `attributes(TroveData)`（public pure。attributes JSON 断片）/ `dynamicTextComponents(TroveData)`（public view。SVG 動的部分）— `uri` の内部部品が public で露出しているもの。`assetReader()`（immutable getter）。
- **設計上のポイント**: MetadataNFT は AddressesRegistry 経由で TroveNFT に immutable 注入され、TroveNFT 側から差替え不可。描画はすべて pure/view 合成であり、コア会計へ影響する経路はない。
- **Verification**: `JPYdfMetadataNFT` output の deployment/unit テスト、🟡 delta test（JPYdf 文言）、data source と status/attribute shape の parity。


### JpydfToken の機能要件（CORE-BT-FR-*）

→ 規範は [JpydfToken.md](./JpydfToken.md) §6（`CORE-BT-FR-001..016`）。namespace 維持につき ID 参照は不変。

### CollateralRegistry の機能要件（CORE-CR-FR-*）

#### CORE-CR-FR-001: constructor（branch 構成の固定と baseRate bootstrap）🔵
- **Type**: Functional ｜ **Source**: base 実装（CollateralRegistry.sol）
- **シグネチャ**: `constructor(IJpydfToken _jpydfToken, IERC20Metadata[] memory _tokens, ITroveManager[] memory _troveManagers)`
- **目的**: branch 構成（担保トークン × TroveManager、最大 10 対）と JPYdf 参照を immutable に固定し、baseRate を bootstrap 値で初期化する。
- **権限**: デプロイ時 1 度のみ。
- **事前条件（Checks）**:
  - `_tokens.length > 0`（空リスト不可）
  - `_tokens.length <= 10`（上限 10 branch）
  - `_troveManagers` の長さは明示検証されない（`_tokens` より短いと配列範囲外 panic で revert。長い場合の超過分は無視）
- **動作（Effects）**:
  1. `totalCollaterals = _tokens.length`
  2. `jpydfToken = _jpydfToken`
  3. `token0..token9` / `troveManager0..troveManager9` に各 index の値を固定（`numTokens` 以上の slot は `address(0)`）
  4. `baseRate = INITIAL_BASE_RATE`（=100%。値は §7）→ `BaseRateUpdated` 発火
  5. `lastFeeOperationTime` は宣言時初期化子によりデプロイ時刻で初期化
- **revert / 早期 return**: 空リスト → `"Collateral list cannot be empty"`；11 以上 → `"Collateral list too long"`。
- **発火イベント**: `BaseRateUpdated`（CORE-CR-EVT-001）。
- **設計上のポイント**: `INITIAL_BASE_RATE = 100%` は bootstrap 機構。デプロイ直後は実効 redemption rate ≈ 100%（fee が redeem 額をほぼ食い潰す）となり redemption が経済的に成立しない。baseRate は半減期 6h（`REDEMPTION_MINUTE_DECAY_FACTOR`）で指数減衰するため、数日かけて floor（`REDEMPTION_FEE_FLOOR` = 0.5%）付近へ収束し、システムが安定的に立ち上がるまで peg 圧力を遮断する（Constants.sol コメント: 「BOLD が 0.95 を下回るまで redemption を防ぐ」）。
- **Verification**: parity / unit（境界 1・10・11、初期 baseRate、未使用 slot のゼロ）。

#### CORE-CR-FR-002: redeemCollateral（branch 横断 redemption）🔵
- **Type**: Functional ｜ **Source**: base 実装（CollateralRegistry.sol）
- **シグネチャ**: `redeemCollateral(uint256 _jpydfAmount, uint256 _maxIterationsPerCollateral, uint256 _maxFeePercentage)`
- **目的**: JPYdf を額面（1 JPYdf = 1 単位の対象通貨建て価値）で担保に交換する peg 維持機構の単一入口。要求額を unbacked portion 比例で各 branch にルーティングし、baseRate を更新し、実際に償還できた分の JPYdf を burn する。
- **権限**: permissionless（実行者は burn される JPYdf 残高を保有している必要がある）。
- **事前条件（Checks）**:
  - `REDEMPTION_FEE_FLOOR <= _maxFeePercentage <= DECIMAL_PRECISION`（`_requireValidMaxFeePercentage`）
  - `_jpydfAmount > 0`（`_requireAmountGreaterThanZero`）
  - 事前計算した実効 rate が `_maxFeePercentage` 以下
- **動作（Effects）**（コードの実行順）:
  1. 全 branch をループし、各 TM の `getUnbackedPortionPriceAndRedeemability()` を呼ぶ（**非 view**。PriceFeed の `fetchPrice` を伴う → [Oracle.md](./Oracle.md)）。返り値は (unbacked portion = branch 全債務 − SP 預入額の正部分, price, redeemable = TCR ≥ SCR かつ未 shutdown)。redeemable な branch のみ `unbackedPortions[index]` と合計 `unbacked` に計上し、price は全 branch 分保存
  2. **fallback**: 合計 unbacked が 0（redeemable な全 branch が SP で full back）の場合、redeemable branch の `getEntireBranchDebt()`（branch 債務総額）を重みとして再計算（branch サイズ比例配分に切替）
  3. **truncation**: 合計 unbacked が正の場合、`_jpydfAmount > unbacked` なら `_jpydfAmount = unbacked` に切詰め（unbacked 超の一括 redemption による不均衡な配分を防ぐ。Certora 指摘 CS-BOLD-013 対応。残額は再度の呼出で redeem 可能）
  4. `jpydfSupplyAtStart = jpydfToken.totalSupply()` を保存（redemption による減少前の値）
  5. **rate 事前計算**: `redemptionRate = _calcRedemptionRate(_getUpdatedBaseRateFromRedemption(_jpydfAmount, jpydfSupplyAtStart))`＝decay 後 baseRate に「要求額（切詰め後）/総供給 ÷ REDEMPTION_BETA」を加算（上限 100%）し、`REDEMPTION_FEE_FLOOR` を加えた値（上限 100%）。`redemptionRate > _maxFeePercentage` なら revert
  6. **配分実行**: 各 branch について `redeemAmount = _jpydfAmount × unbackedPortions[index] / unbacked` を計算し、正なら `troveManager.redeemCollateral(msg.sender, redeemAmount, prices[index], redemptionRate, _maxIterationsPerCollateral)` を呼び、実際に償還された額（`redeemedAmount` ≤ `redeemAmount`）を合算。ループ毎に `_jpydfAmount -= redeemAmount`・`unbacked -= unbackedPortions[index]` と残差を更新し、丸め誤差込みで配分合計が要求額に厳密一致するようにする（fee の担保側控除と Trove 単位の償還は TM 担当節参照）
  7. **baseRate 確定**: `_updateBaseRateAndGetRedemptionRate(実償還合計, jpydfSupplyAtStart)` で baseRate を「実際に償還できた額」基準で再計算・保存し `BaseRateUpdated` を発火。続けて `_updateLastFeeOpTime` が経過を丸め分単位で `lastFeeOperationTime` に加算（1 分未満なら更新しない）し、更新時は `LastFeeOpTimeUpdated` を発火
  8. 実償還合計が正なら `jpydfToken.burn(msg.sender, 実償還合計)`（CORE-BT-FR-005）
- **revert / 早期 return**:
  - `_maxFeePercentage` 範囲外 → `"Max fee percentage must be between 0.5% and 100%"`
  - `_jpydfAmount == 0` → `"CollateralRegistry: Amount must be greater than zero"`
  - 実効 rate 超過 → `"CR: Fee exceeded provided maximum"`
  - 残高不足（burn 時） → `"ERC20: burn amount exceeds balance"`
  - redeemable な branch が 1 つもない場合も**早期 return はしない**。このとき truncation（手順 3）は働かないため、rate 事前計算（手順 5）は**要求額全量**を基準に行われ、`_maxFeePercentage` が低ければ**実償還 0 でも** `"CR: Fee exceeded provided maximum"` で revert し得る。fee 検査を通過した場合は、配分ゼロ・baseRate は decay のみで更新（`BaseRateUpdated` 発火）・burn スキップで正常終了する
- **発火イベント**: `BaseRateUpdated`（CORE-CR-EVT-001）、`LastFeeOpTimeUpdated`（CORE-CR-EVT-002）。Trove 単位の償還イベントは各 TM が発火。
- **設計上のポイント**:
  - **unbacked 比例配分**: SP で back されていない債務が多い branch ほど多く redeem される。redemption を「リスクの高い branch の debt 圧縮」に向け、branch 間の健全性を均す v2 の中核設計。
  - **rate の二段計算**: fee 判定用 rate は「要求額」で事前計算して `_maxFeePercentage` と比較し、状態としての baseRate は「実償還額」で確定する。要求額より実償還が少ない場合、redeemer は事前計算分の rate を払う（最適額の見積りは redeemer 責務とコードコメントに明記）。
  - `_maxIterationsPerCollateral = 0` は TM 側で「無制限」として扱われる（TM 担当節参照）。branch あたりの Trove 走査数を制限して gas を抑える用途。
  - baseRate を更新する操作は本関数のみ（`lastFeeOperationTime` の宣言コメントに「redemption or new Bold issuance」とあるのは v1 由来の名残で、v2 では借入操作は baseRate に影響しない）。
  - decay の分単位丸め（`_updateLastFeeOpTime`）は、1 分未満の連続 redemption で decay を細切れに稼ぐ baseRate griefing を防ぐ。
- **Verification**: parity（配分・truncation・fallback・rate 計算・burn 額）、invariant=CORE-CR-INV-001〜003。

#### CORE-CR-FR-003: getRedemptionRate（現 baseRate での実効 rate）🔵
- **Type**: Functional ｜ **Source**: base 実装（CollateralRegistry.sol）
- **シグネチャ**: `getRedemptionRate() → uint256`（external view）
- **目的**: decay を適用しない「最終更新時点の baseRate」に基づく実効 redemption rate を返す。
- **動作（Effects）**: `min(REDEMPTION_FEE_FLOOR + baseRate, DECIMAL_PRECISION)` を返す。
- **revert / 早期 return**: なし。
- **Verification**: parity。

#### CORE-CR-FR-004: getRedemptionRateWithDecay（decay 適用後の実効 rate）🔵
- **Type**: Functional ｜ **Source**: base 実装（CollateralRegistry.sol）
- **シグネチャ**: `getRedemptionRateWithDecay() → uint256`（public view）
- **目的**: 現時点で redemption した場合の rate の時間成分を見積もる（額による増分は含まない）。
- **動作（Effects）**: `decayedBaseRate = baseRate × REDEMPTION_MINUTE_DECAY_FACTOR^(経過分) / 1e18`（経過分は `lastFeeOperationTime` からの floor 分数）を計算し、`min(REDEMPTION_FEE_FLOOR + decayedBaseRate, DECIMAL_PRECISION)` を返す。
- **revert / 早期 return**: なし。
- **設計上のポイント**: `REDEMPTION_MINUTE_DECAY_FACTOR` は半減期 6h（=360 分）に対応する毎分減衰係数（値は §7）。
- **Verification**: parity。

#### CORE-CR-FR-005: getRedemptionRateForRedeemedAmount（指定額 redeem 時の rate 見積り）🔵
- **Type**: Functional ｜ **Source**: base 実装（CollateralRegistry.sol）
- **シグネチャ**: `getRedemptionRateForRedeemedAmount(uint256 _redeemAmount) → uint256`（external view）
- **目的**: `_redeemAmount` を今 redeem した場合に適用される実効 rate（decay ＋ 額による増分込み）を見積もる。
- **動作（Effects）**: 現在の `jpydfToken.totalSupply()` を分母に `_getUpdatedBaseRateFromRedemption(_redeemAmount, totalSupply)`（= decayed baseRate + `_redeemAmount × 1e18 / totalSupply / REDEMPTION_BETA`、上限 100%）を計算し、`_calcRedemptionRate` を適用して返す。
- **revert / 早期 return**: `totalSupply == 0` の場合はゼロ除算 panic（運用上、供給ゼロでの呼出は想定外）。
- **設計上のポイント**: 実行時（CORE-CR-FR-002）は truncation 後の要求額・実行前供給で計算されるため、見積りと厳密一致しない場合がある。off-chain 見積り用 view（core 内に呼出元なし）。
- **Verification**: parity。

#### CORE-CR-FR-006: getRedemptionFeeWithDecay（数量に対する fee 計算）🔵
- **Type**: Functional ｜ **Source**: base 実装（CollateralRegistry.sol）
- **シグネチャ**: `getRedemptionFeeWithDecay(uint256 _ETHDrawn) → uint256`（external view）
- **目的**: decay 適用後 rate を所与の数量に乗じた fee を返す（`rate × _ETHDrawn / 1e18`）。
- **動作（Effects）**: `_calcRedemptionFee(getRedemptionRateWithDecay(), _ETHDrawn)` を返す。
- **revert / 早期 return**: なし。
- **設計上のポイント**: 引数名 `_ETHDrawn` は v1 由来の命名で、単位は呼び手の渡す数量に従う（担保数量を渡せば担保建て fee）。off-chain 見積り用 view（core 内に呼出元なし）。
- **Verification**: parity。

#### CORE-CR-FR-007: getEffectiveRedemptionFeeInJpydf（JPYdf 建て実効 fee）🔵
- **Type**: Functional ｜ **Source**: base 実装（CollateralRegistry.sol）
- **シグネチャ**: `getEffectiveRedemptionFeeInJpydf(uint256 _redeemAmount) → uint256`（external view）
- **目的**: `_redeemAmount` を今 redeem した場合に徴収される fee を JPYdf 建てで見積もる。
- **動作（Effects）**: 現在供給で更新後 baseRate を見積り（CORE-CR-FR-005 と同じ計算）、`_calcRedemptionFee(_calcRedemptionRate(newBaseRate), _redeemAmount)` を返す。
- **revert / 早期 return**: `totalSupply == 0` でゼロ除算 panic（同上）。
- **Verification**: parity。

#### CORE-CR-FR-008: getToken / getTroveManager（index → branch 参照）🔵
- **Type**: Functional ｜ **Source**: base 実装（CollateralRegistry.sol）
- **シグネチャ**: `getToken(uint256 _index) → IERC20Metadata`（external view） ／ `getTroveManager(uint256 _index) → ITroveManager`（public view）
- **目的**: branch index から担保トークン / TroveManager の immutable 参照を返す。
- **動作（Effects）**: `_index` 0〜9 に対応する `tokenN` / `troveManagerN` を分岐で返す。
- **revert / 早期 return**: `_index >= 10` → `"Invalid index"`（require 文字列ではなく `revert("Invalid index")`）。**`totalCollaterals <= _index <= 9` の未使用 slot は revert せず `address(0)` を返す**点に注意（呼び手は `totalCollaterals` で範囲を制御する前提）。
- **発火イベント**: なし。
- **Verification**: parity / unit（10 以上 revert・未使用 slot のゼロ返却）。

#### CORE-CR-FR-009: 自明 view 関数群（baseRate / lastFeeOperationTime / totalCollaterals / jpydfToken）🔵
- **Type**: Functional ｜ **Source**: base 実装（public 変数の自動生成 getter）
- **シグネチャ・返り値**:

  | 関数 | 返り値の意味 |
  | --- | --- |
  | `baseRate() → uint256` | 最終更新時点の baseRate（decay 未適用の生値） |
  | `lastFeeOperationTime() → uint256` | decay 基準時刻（分単位でのみ前進） |
  | `totalCollaterals() → uint256` | branch 数（デプロイ後不変） |
  | `jpydfToken() → IJpydfToken` | JPYdf トークンアドレス |
- **権限**: permissionless（view）。
- **Verification**: parity。


### AddressesRegistry の機能要件（CORE-AR-FR-*）

#### CORE-AR-FR-001: constructor（branch リスクパラメータの検証と固定）🔵
- **Type**: Functional / Governance ｜ **Source**: base 実装（AddressesRegistry.sol）
- **シグネチャ**: `constructor(address _owner, uint256 _ccr, uint256 _mcr, uint256 _bcr, uint256 _scr, uint256 _liquidationPenaltySP, uint256 _liquidationPenaltyRedistribution)`
- **目的**: branch のリスクパラメータをデプロイ時にレンジ検証し、immutable として恒久固定する。
- **権限**: デプロイ時 1 度のみ。
- **事前条件（Checks）**（カスタムエラー。判定はコードの順）:
  1. `1e18 < _ccr < 2e18`（両端排他）でなければ `InvalidCCR()`
  2. `1e18 < _mcr < 2e18` でなければ `InvalidMCR()`
  3. `5e16 <= _bcr < 50e16` でなければ `InvalidBCR()`
  4. `1e18 < _scr < 2e18` でなければ `InvalidSCR()`
  5. `_liquidationPenaltySP >= MIN_LIQUIDATION_PENALTY_SP`（5%）でなければ `SPPenaltyTooLow()`
  6. `_liquidationPenaltySP <= _liquidationPenaltyRedistribution` でなければ `SPPenaltyGtRedist()`
  7. `_liquidationPenaltyRedistribution <= MAX_LIQUIDATION_PENALTY_REDISTRIBUTION`（20%）でなければ `RedistPenaltyTooHigh()`
- **動作（Effects）**:
  1. `Ownable(_owner)`: Owner 設定＋`OwnershipTransferred(address(0), _owner)` 発火
  2. `CCR / SCR / MCR / BCR / LIQUIDATION_PENALTY_SP / LIQUIDATION_PENALTY_REDISTRIBUTION` を immutable に固定
- **revert / 早期 return**: 上記カスタムエラー。
- **発火イベント**: `OwnershipTransferred`（CORE-AR-EVT-019）。
- **設計上のポイント**: 検証は各パラメータの個別レンジと「SP ペナルティ ≤ 再分配ペナルティ ≤ 20%」の順序のみで、**CCR / MCR / SCR 相互の大小関係は検証されない**（例: SCR > CCR でも revert しない。妥当な組合せの選定はデプロイ手順の責務）。jpydf の実パラメータ値は [Parameters.md](../../../Parameters.md) を正とする。
- **Verification**: parity / unit（各境界値でのカスタムエラー・immutable 反映）。

#### CORE-AR-FR-002: setAddresses（アドレス一括配線と ownership renounce）🔵
- **Type**: Functional / Governance ｜ **Source**: base 実装（AddressesRegistry.sol）
- **シグネチャ**: `setAddresses(AddressVars memory _vars)`（`AddressVars` は collToken〜WETH の 18 フィールド struct。`IAddressesRegistry` 定義）
- **目的**: branch を構成する全コントラクト＋共有コントラクトのアドレスを 1 度だけ設定し、同一 tx で ownership を放棄して配線を凍結する。
- **権限**: `onlyOwner`。
- **事前条件（Checks）**: caller が Owner であること以外なし（**ゼロアドレス・相互整合性の検証なし**）。
- **動作（Effects）**:
  1. struct の 18 フィールドをそれぞれ対応する storage 変数へ代入（collToken, borrowerOperations, troveManager, troveNFT, metadataNFT, stabilityPool, priceFeed, activePool, defaultPool, gasPoolAddress, collSurplusPool, sortedTroves, interestRouter, hintHelpers, multiTroveGetter, collateralRegistry, jpydfToken, WETH）
  2. 各アドレスに対応する `…AddressChanged` イベントを 18 件発火
  3. `_renounceOwnership()`: `OwnershipTransferred(旧 owner, address(0))` を発火し Owner を消去
- **revert / 早期 return**: 非 Owner → `"Ownable: caller is not the owner"`。
- **発火イベント**: CORE-AR-EVT-001〜018 の全件＋CORE-AR-EVT-019。
- **設計上のポイント**: 「1 度限り」は ownership renounce により強制される（再呼出は恒久に不能）。デプロイ手順上は、各 core コントラクトが constructor で本レジストリを参照して自身の immutable を確定するより**前に**呼ばれている必要がある（典型的には AR デプロイ → `setAddresses`（事前計算したアドレスで） → 各コントラクトデプロイ、の順）。この時点の CREATE2 予定アドレスにはまだ runtime code がないため、`setAddresses` 内での `code.length` 検査は正規手順と両立しない。設定値の正しさを検証する機構はコントラクト内にないため、配線検証はデプロイスクリプト・デプロイ後検証の責務（CORE-AR-SEC-001）。
- **Verification**: parity / unit（onlyOwner・18 値反映・18+1 イベント・renounce 後の再呼出 revert）。

#### CORE-AR-FR-003: branch リスクパラメータ getter 群（CCR / SCR / MCR / BCR / 清算ペナルティ）🔵
- **Type**: Functional ｜ **Source**: base 実装（public immutable の自動生成 getter）
- **シグネチャ・返り値**:

  | 関数 | 返り値の意味（利用箇所） |
  | --- | --- |
  | `CCR() → uint256` | TCR がこれ未満で借入操作制限（BO） |
  | `SCR() → uint256` | TCR がこれ未満で shutdown 可能・redemption 配分から除外（BO/TM/CR） |
  | `MCR() → uint256` | Trove 個別の清算閾値・調整時の最低 ICR（BO/TM） |
  | `BCR() → uint256` | batch 参加・batch 内調整時に MCR に上乗せされるバッファ（BO） |
  | `LIQUIDATION_PENALTY_SP() → uint256` | SP offset 清算のペナルティ率（TM） |
  | `LIQUIDATION_PENALTY_REDISTRIBUTION() → uint256` | 再分配清算のペナルティ率（TM） |
- **権限**: permissionless（view）。
- **設計上のポイント**: 各 core コントラクトは constructor でこれらを読み取り自身の immutable に複製するため、稼働時の判定はコントラクト側のコピーで行われる（値は常に一致。レンジは CORE-AR-FR-001 で保証）。
- **Verification**: parity。

#### CORE-AR-FR-004: アドレス getter 群（全 18 アドレス＋owner / isOwner）🔵
- **Type**: Functional ｜ **Source**: base 実装（public 変数の自動生成 getter / Ownable.sol）
- **シグネチャ**: `collToken` / `borrowerOperations` / `troveManager` / `troveNFT` / `metadataNFT` / `stabilityPool` / `priceFeed` / `activePool` / `defaultPool` / `gasPoolAddress` / `collSurplusPool` / `sortedTroves` / `interestRouter` / `hintHelpers` / `multiTroveGetter` / `collateralRegistry` / `jpydfToken` / `WETH`（各 `→ 対応 interface 型`、public view）、および `owner() → address` / `isOwner() → bool`
- **目的**: 配線結果の参照（`setAddresses` 前はすべて `address(0)`）。各 core コントラクトの constructor がデプロイ時に読み取るほか、off-chain ツール・周辺コントラクトの参照解決に使う。
- **権限**: permissionless（view）。
- **revert / 早期 return**: なし。
- **Verification**: parity（`setAddresses` 前後の値）。


### HintHelpers の機能要件（CORE-HH-FR-*）

**fee 試算 8 種の共通仕様**（CORE-HH-FR-002〜009 に共通。各 FR から参照）:

- **fee 式**: `upfrontFee = debt × avgInterestRate × UPFRONT_INTEREST_PERIOD / ONE_YEAR / DECIMAL_PRECISION`。`UPFRONT_INTEREST_PERIOD`（7 日。値は本書の定数表 / `Constants.sol`）分の平均金利相当の利息であり、`BorrowerOperations._calcUpfrontFee` と同式。
- **平均金利の取得**: `avgInterestRate = ActivePool.getNewApproxAvgInterestRateFromTroveChange(c)`（AP 節）。試算対象の操作を模した `TroveChange c` を集計値（`aggRecordedDebt` ＋未 mint 利息、`aggWeightedDebtSum`）に仮適用した**操作後**のブランチ加重平均金利近似 `Σ(debt×rate) / Σdebt` を返す。branch shutdown 後は 0。upfront fee 自体は循環（fee → 平均金利 → fee）回避のため平均計算に反映しない（`c.upfrontFee == 0` を AP 側で assert）。各 predict 関数の差は「`c` のどのフィールドにどの債務・金利を載せるか」と「fee 基数」に集約される。
- **一致性**: 各 predict は BO 実装と同一の `TroveChange` を構築するため、**同一チェーン状態に対しては実際に請求される upfront fee と一致する**（CORE-HH-INV-001）。誤差要因は試算〜実行間の状態変化（時間経過による利息累積・他操作）のみ。
- **非責務**: fee 額の試算のみを行い、操作自体の成立性（ICR / TCR / `MIN_DEBT` / 権限・cooldown 検証等）は確認しない。predict が値を返しても実操作は revert しうる。

| 関数 | 試算対象の操作（BO 節） | fee 基数 | 0 を返す条件 |
| --- | --- | --- | --- |
| `predictOpenTroveUpfrontFee` | `openTrove` | `_borrowedAmount` | なし（開設は常に課金） |
| `predictAdjustInterestRateUpfrontFee` | `adjustTroveInterestRate` | Trove 全債務 `entireDebt` | 同率指定、または cooldown 経過後 |
| `forcePredictAdjustInterestRateUpfrontFee` | 同上（無条件版） | Trove 全債務 `entireDebt` | なし |
| `predictAdjustTroveUpfrontFee` | `adjustTrove` 系の債務増額 | `_debtIncrease` | `_debtIncrease == 0` |
| `predictAdjustBatchInterestRateUpfrontFee` | `setBatchManagerAnnualInterestRate` | バッチ全債務 `entireDebtWithoutRedistribution` | 同率指定、または batch cooldown 経過後 |
| `predictOpenTroveAndJoinBatchUpfrontFee` | `openTroveAndJoinInterestBatchManager` | `_borrowedAmount` | なし（開設は常に課金） |
| `predictJoinBatchInterestRateUpfrontFee` | `setInterestBatchManager` | Trove 全債務 `entireDebt` | なし（バッチ加入は常に課金） |
| `predictRemoveFromBatchUpfrontFee` | `removeFromBatch` | Trove 全債務 `entireDebt` | バッチ現行率と同率指定、または Trove cooldown 経過後 |

#### CORE-HH-FR-001: getApproxHint（乱択サンプリングによる近似 hint 探索）🔵

- **Type**: Functional ｜ **Source**: base 実装（HintHelpers.sol）
- **シグネチャ**: `getApproxHint(uint256 _collIndex, uint256 _interestRate, uint256 _numTrials, uint256 _inputRandomSeed) → (uint256 hintId, uint256 diff, uint256 latestRandomSeed)`（external view）
- **目的**: SortedTroves（金利降順リスト）への挿入位置探索の出発点として、目標金利 `_interestRate` に年率が最も近い Trove の近似を、Trove ID 配列からの擬似乱数サンプリングで求める。
- **権限**: permissionless（view）。
- **事前条件（Checks）**: 明示の検証なし。`_collIndex` が無効な場合は CollateralRegistry / ゼロアドレス呼出側で revert（CORE-HH-ERR-001）。
- **動作（Effects）**:
  1. `collateralRegistry.getTroveManager(_collIndex)` で TroveManager、その `sortedTroves()` で SortedTroves を解決
  2. `arrayLength = getTroveIdsCount()`。0 なら `(0, 0, _inputRandomSeed)` を返す（早期 return）
  3. 初期候補: `hintId = sortedTroves.getLast()`（最低金利 Trove）、`diff = |_interestRate − getTroveAnnualInterestRate(hintId)|`（`LiquityMath._getAbsoluteDifference`）
  4. `i = 1` から `_numTrials − 1` 回反復: `latestRandomSeed = keccak256(latestRandomSeed)` → `arrayIndex = seed % arrayLength` → `currentId = getTroveFromTroveIdsArray(arrayIndex)`
  5. `sortedTroves.contains(currentId)` が false（zombie 等でソート済みリスト外）の ID はスキップ
  6. `|現在率 − _interestRate| < diff` なら候補を更新
  7. 最良候補 `hintId`・その `diff`・最終 `latestRandomSeed` を返す
- **revert / 早期 return**: Trove 数 0 → `(0, 0, _inputRandomSeed)`。`_numTrials <= 1` ではサンプリングせずリスト末尾を候補のまま返す。
- **発火イベント**: なし。
- **設計上のポイント**: 確率的探索であり、出力は平均で `リスト長 / _numTrials` 位置、最悪 O(n) 位置ずれる（NatSpec）。`_numTrials = 15 × sqrt(リスト長)` で高信頼に `sqrt(リスト長)` 位置以内（NatSpec 推奨値）。`latestRandomSeed` を次回呼出の `_inputRandomSeed` に渡すことで試行を複数回の eth_call に分割できる。返り値 `diff` は hint の品質比較に使える（DebtInFrontHelper が利用、CORE-DFH-FR-001）。on-chain 利用は想定せず、off-chain で `SortedTroves.findInsertPosition` と組み合わせる。
- **Verification**: parity（base 同一挙動。シード固定で決定的）/ unit。

#### CORE-HH-FR-002: predictOpenTroveUpfrontFee（openTrove の fee 試算）🔵

- **Type**: Functional ｜ **Source**: base 実装（HintHelpers.sol）
- **シグネチャ**: `predictOpenTroveUpfrontFee(uint256 _collIndex, uint256 _borrowedAmount, uint256 _interestRate) → uint256`（external view）
- **目的**: 金利 `_interestRate` で `_borrowedAmount` を借りて Trove を開設（バッチ非加入）する際の upfront fee を試算する。
- **権限**: permissionless（view）。
- **事前条件（Checks）**: なし（共通仕様の非責務参照）。
- **動作（Effects）**:
  1. `TroveChange{ debtIncrease = _borrowedAmount, newWeightedRecordedDebt = _borrowedAmount × _interestRate }` を構築（開設なので old 側はなし）
  2. 共通仕様の平均金利を取得し、fee 基数 `_borrowedAmount` で fee 式を適用
- **revert / 早期 return**: なし（開設は常に課金。shutdown ブランチでは平均金利 0 のため 0 を返す）。
- **発火イベント**: なし。
- **Verification**: parity / unit。

#### CORE-HH-FR-003: predictAdjustInterestRateUpfrontFee（金利調整の fee 試算）🔵

- **Type**: Functional ｜ **Source**: base 実装（HintHelpers.sol）
- **シグネチャ**: `predictAdjustInterestRateUpfrontFee(uint256 _collIndex, uint256 _troveId, uint256 _newInterestRate) → uint256`（external view）
- **目的**: バッチ非加入 Trove の `adjustTroveInterestRate` が premature 調整（前回調整から `INTEREST_RATE_ADJ_COOLDOWN` 未経過）として請求する upfront fee を試算する。
- **権限**: permissionless（view）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**:
  1. `getLatestTroveData(_troveId)` で現在状態（利息・再分配込み）を取得
  2. `_newInterestRate == 現行年率`、または `block.timestamp >= lastInterestRateAdjTime + INTEREST_RATE_ADJ_COOLDOWN`（cooldown 経過＝無償調整）なら **0 を返す**
  3. それ以外は `TroveChange{ appliedRedistJpydfDebtGain = 再分配ゲイン, newWeightedRecordedDebt = entireDebt × _newInterestRate, oldWeightedRecordedDebt = trove.weightedRecordedDebt }` を構築し、fee 基数 `entireDebt`（全債務）で fee 式を適用
- **revert / 早期 return**: 上記 2 条件で 0。
- **発火イベント**: なし。
- **設計上のポイント**: BO 側の課金条件（`block.timestamp < lastInterestRateAdjTime + INTEREST_RATE_ADJ_COOLDOWN` のときのみ `_applyUpfrontFee`）を忠実に鏡映する。fee 基数が借入額ではなく**全債務**である点が openTrove 系との違い。
- **Verification**: parity / unit。

#### CORE-HH-FR-004: forcePredictAdjustInterestRateUpfrontFee（無条件の金利調整 fee 試算）🔵

- **Type**: Functional ｜ **Source**: base 実装（HintHelpers.sol）
- **シグネチャ**: `forcePredictAdjustInterestRateUpfrontFee(uint256 _collIndex, uint256 _troveId, uint256 _newInterestRate) → uint256`（external view）
- **目的**: CORE-HH-FR-003 の 0 短絡（同率・cooldown 経過）を行わない変種。「いま premature 調整を行ったと仮定した場合」の fee を常に計算して返す。
- **権限**: permissionless（view）。
- **動作（Effects)**: CORE-HH-FR-003 のステップ 3 と同一の内部計算（`_predictAdjustInterestRateUpfrontFee`）を無条件に実行する。
- **revert / 早期 return**: なし。
- **発火イベント**: なし。
- **設計上のポイント**: 実操作で 0 になるケースでも仮定額を返すため、UI の保守的な見積り表示や「cooldown 明け前に調整した場合のコスト」提示に使える。実際の請求有無の判定は CORE-HH-FR-003 側。
- **Verification**: parity / unit。

#### CORE-HH-FR-005: predictAdjustTroveUpfrontFee（債務増額調整の fee 試算）🔵

- **Type**: Functional ｜ **Source**: base 実装（HintHelpers.sol）
- **シグネチャ**: `predictAdjustTroveUpfrontFee(uint256 _collIndex, uint256 _troveId, uint256 _debtIncrease) → uint256`（external view）
- **目的**: `adjustTrove` 系操作（`withdrawJpydf` 等）で債務を `_debtIncrease` 増やす際の upfront fee を試算する。債務増額以外の調整（返済・担保のみの増減）は fee 対象外。
- **権限**: permissionless（view）。
- **動作（Effects）**:
  1. `_debtIncrease == 0` なら **0 を返す**
  2. `getLatestTroveData(_troveId)` と `Troves(_troveId)` の `interestBatchManager` を取得
  3. バッチ非加入: `TroveChange{ appliedRedistJpydfDebtGain, debtIncrease = _debtIncrease, newWeightedRecordedDebt = (entireDebt + _debtIncrease) × trove.annualInterestRate, oldWeightedRecordedDebt = trove.weightedRecordedDebt }`
  4. バッチ加入中: `getLatestBatchData(batchManager)` を取得し `TroveChange{ appliedRedistJpydfDebtGain, debtIncrease, batchAccruedManagementFee = batch.accruedManagementFee, newWeightedRecordedDebt = (batch.entireDebtWithoutRedistribution + trove.redistJpydfDebtGain + _debtIncrease) × batch.annualInterestRate, oldWeightedRecordedDebt = batch.weightedRecordedDebt }`（バッチ全体を batch 金利で再重み付け）
  5. fee 基数 **`_debtIncrease` のみ**で fee 式を適用
- **revert / 早期 return**: `_debtIncrease == 0` → 0。
- **発火イベント**: なし。
- **設計上のポイント**: fee 基数は増分のみ（全債務ではない）。バッチ加入 Trove では金利がバッチ金利になり、平均金利計算もバッチ全債務の再重み付けで行う点を BO `_adjustTrove` と同形に再現する。
- **Verification**: parity / unit。

#### CORE-HH-FR-006: predictAdjustBatchInterestRateUpfrontFee（バッチ金利変更の fee 試算）🔵

- **Type**: Functional ｜ **Source**: base 実装（HintHelpers.sol）
- **シグネチャ**: `predictAdjustBatchInterestRateUpfrontFee(uint256 _collIndex, address _batchAddress, uint256 _newInterestRate) → uint256`（external view）
- **目的**: バッチマネージャの `setBatchManagerAnnualInterestRate` が premature 変更時にバッチ全体へ請求する upfront fee を試算する。
- **権限**: permissionless（view）。
- **動作（Effects）**:
  1. `getLatestBatchData(_batchAddress)` を取得
  2. `_newInterestRate == batch.annualInterestRate`、または `block.timestamp >= batch.lastInterestRateAdjTime + INTEREST_RATE_ADJ_COOLDOWN` なら **0 を返す**
  3. それ以外は `TroveChange{ batchAccruedManagementFee, newWeightedRecordedDebt = batch.entireDebtWithoutRedistribution × _newInterestRate, oldWeightedRecordedDebt = batch.weightedRecordedDebt }` を構築し、fee 基数 `batch.entireDebtWithoutRedistribution`（再分配ゲインを除くバッチ全債務。累積利息・管理 fee 込み）で fee 式を適用
- **revert / 早期 return**: 上記 2 条件で 0。
- **発火イベント**: なし。
- **設計上のポイント**: cooldown の基準が Trove ではなく**バッチ**の `lastInterestRateAdjTime` である点が CORE-HH-FR-003 と異なる。BO 側の課金条件（率変更かつ cooldown 内）と一致。
- **Verification**: parity / unit。

#### CORE-HH-FR-007: predictOpenTroveAndJoinBatchUpfrontFee（バッチ加入開設の fee 試算）🔵

- **Type**: Functional ｜ **Source**: base 実装（HintHelpers.sol）
- **シグネチャ**: `predictOpenTroveAndJoinBatchUpfrontFee(uint256 _collIndex, uint256 _borrowedAmount, address _batchAddress) → uint256`（external view・`IHintHelpers` 未宣言）
- **目的**: `openTroveAndJoinInterestBatchManager`（バッチ加入と同時に Trove 開設）の upfront fee を試算する。
- **権限**: permissionless（view）。
- **動作（Effects）**:
  1. `getLatestBatchData(_batchAddress)` を取得
  2. `TroveChange{ debtIncrease = _borrowedAmount, batchAccruedManagementFee, oldWeightedRecordedDebt = batch.weightedRecordedDebt, newWeightedRecordedDebt = (batch.entireDebtWithoutRedistribution + _borrowedAmount) × batch.annualInterestRate }` を構築
  3. fee 基数 `_borrowedAmount` で fee 式を適用
- **revert / 早期 return**: なし（開設は常に課金）。
- **発火イベント**: なし。
- **設計上のポイント**: 借入分が個別金利ではなく**バッチ金利**で重み付けされる点が CORE-HH-FR-002 との差。
- **Verification**: parity / unit。

#### CORE-HH-FR-008: predictJoinBatchInterestRateUpfrontFee（バッチ加入の fee 試算）🔵

- **Type**: Functional ｜ **Source**: base 実装（HintHelpers.sol）
- **シグネチャ**: `predictJoinBatchInterestRateUpfrontFee(uint256 _collIndex, uint256 _troveId, address _batchAddress) → uint256`（external view）
- **目的**: 既存 Trove が `setInterestBatchManager` でバッチへ加入する際の upfront fee を試算する。加入は cooldown と無関係に**常に課金**される（base のコメント: バッチを自営する借り手が無償の金利更新を得る fee 回避を防ぐ）ため、0 短絡を持たない。
- **権限**: permissionless（view）。
- **動作（Effects）**:
  1. `getLatestTroveData(_troveId)` と `getLatestBatchData(_batchAddress)` を取得
  2. `TroveChange{ appliedRedistJpydfDebtGain = trove.redistJpydfDebtGain, batchAccruedManagementFee, oldWeightedRecordedDebt = batch.weightedRecordedDebt + trove.weightedRecordedDebt, newWeightedRecordedDebt = (batch.entireDebtWithoutRedistribution + trove.entireDebt) × batch.annualInterestRate }` を構築（Trove の旧重みとバッチの旧重みを除き、合算債務をバッチ金利で再重み付け）
  3. fee 基数 `trove.entireDebt` で fee 式を適用
- **revert / 早期 return**: なし。
- **発火イベント**: なし。
- **Verification**: parity / unit。

#### CORE-HH-FR-009: predictRemoveFromBatchUpfrontFee（バッチ離脱の fee 試算）🔵

- **Type**: Functional ｜ **Source**: base 実装（HintHelpers.sol）
- **シグネチャ**: `predictRemoveFromBatchUpfrontFee(uint256 _collIndex, uint256 _troveId, uint256 _newInterestRate) → uint256`（external view・`IHintHelpers` 未宣言）
- **目的**: バッチ加入中の Trove が `removeFromBatch` で離脱し個別金利 `_newInterestRate` を設定する際の upfront fee を試算する。
- **権限**: permissionless（view）。
- **動作（Effects）**:
  1. `getLatestTroveData(_troveId)`・`Troves(_troveId)` の所属バッチ・`getLatestBatchData(batchManager)` を取得
  2. `_newInterestRate == batch.annualInterestRate`（離脱後も同率）、または `block.timestamp >= trove.lastInterestRateAdjTime + INTEREST_RATE_ADJ_COOLDOWN`（Trove 基準の cooldown 経過）なら **0 を返す**
  3. それ以外は `TroveChange{ appliedRedistJpydfDebtGain, batchAccruedManagementFee, oldWeightedRecordedDebt = batch.weightedRecordedDebt, newWeightedRecordedDebt = (batch.entireDebtWithoutRedistribution − (trove.entireDebt − trove.redistJpydfDebtGain)) × batch.annualInterestRate + trove.entireDebt × _newInterestRate }` を構築（離脱後のバッチ残債はバッチ金利、離脱 Trove は新金利で重み付け。BO `_removeFromBatch` の `batchFutureDebt` 計算と同形）
  4. fee 基数 `trove.entireDebt` で fee 式を適用
- **revert / 早期 return**: 上記 2 条件で 0。
- **発火イベント**: なし。
- **設計上のポイント**: 0 短絡の比較対象が「バッチの現行率」（離脱して同じ率を選ぶ＝実質金利不変なら無償）かつ cooldown 基準が「Trove 側」という非対称な組合せ。BO 側の課金条件（`batch.annualInterestRate != _newAnnualInterestRate && block.timestamp < trove.lastInterestRateAdjTime + INTEREST_RATE_ADJ_COOLDOWN`）と一致。
- **Verification**: parity / unit。

#### CORE-HH-FR-010: 定数・参照 view 関数群 🔵

- **Type**: Functional ｜ **Source**: base 実装（HintHelpers.sol）
- **目的**: 自明な公開 getter。

| 関数 | 返り値の意味 |
| --- | --- |
| `NAME()` | 定数 `"HintHelpers"` |
| `collateralRegistry()` | constructor で固定した CollateralRegistry アドレス |

- **Verification**: parity。


### MultiTroveGetter の機能要件（CORE-MTG-FR-*）

#### CORE-MTG-FR-001: getMultipleSortedTroves（金利順の Trove 一括取得）🔵

- **Type**: Functional ｜ **Source**: base 実装（MultiTroveGetter.sol）
- **シグネチャ**: `getMultipleSortedTroves(uint256 _collIndex, int256 _startIdx, uint256 _count) → CombinedTroveData[] _troves`（external view）
- **目的**: SortedTroves の並び順で `_count` 件の Trove 詳細（`CombinedTroveData`）を取得する。`_startIdx` の符号で走査方向を切り替える。
- **権限**: permissionless（view）。
- **事前条件（Checks）**: `getTroveManager(_collIndex) != address(0)`（require `"Invalid collateral index"`）。`sortedTroves != address(0)`（assert）。
- **動作（Effects）**:
  1. **`_startIdx >= 0`**: 先頭（`getFirst()` = 最高金利）から金利**降順**に走査し、添字 `_startIdx` の位置から `_count` 件を返す
  2. **`_startIdx < 0`**: `startIdx = uint256(−(_startIdx + 1))` と解釈（`−1` → 末尾から 0 番目、`−2` → 末尾から 1 番目、…）し、末尾（`getLast()` = 最低金利）から金利**昇順**（償還が消化する順）に走査して `_count` 件を返す
  3. `startIdx >= リストサイズ` なら空配列。`_count` は `リストサイズ − startIdx` に切詰め
  4. 各 Trove について `CombinedTroveData` を構成する。フィールドの出所:
     - `entireDebt` / `entireColl` / `redistJpydfDebtGain` / `redistCollGain` / `accruedInterest` / `recordedDebt` / `annualInterestRate` / `accruedBatchManagementFee` / `lastInterestRateAdjTime` ← `TroveManager.getLatestTroveData`（利息・再分配込みの最新値。TM 節）
     - `stake` / `lastDebtUpdateTime` / `interestBatchManager` / `batchDebtShares` ← `Troves` ストレージ（記録値）
     - `snapshotETH` / `snapshotJpydfDebt` ← `rewardSnapshots`（再分配スナップショット。`snapshotETH` は base の歴史的命名で実体は担保スナップショット）
- **revert / 早期 return**: 無効 index → `"Invalid collateral index"`。範囲外 `startIdx` → 空配列。
- **発火イベント**: なし。
- **設計上のポイント**: zombie Trove はソート済みリスト外のため出力に現れない。負の `_startIdx` 走査（昇順）は「償還で先に消化される側から」の閲覧に対応する。走査コストはリスト先頭/末尾から `startIdx` 分の線形スキップを含む。
- **Verification**: parity / unit。

#### CORE-MTG-FR-002: getDebtPerInterestRateAscending（金利昇順の債務分布取得）🔵

- **Type**: Functional ｜ **Source**: base 実装（MultiTroveGetter.sol）
- **シグネチャ**: `getDebtPerInterestRateAscending(uint256 _collIndex, uint256 _startId, uint256 _maxIterations) → (DebtPerInterestRate[] data, uint256 currId)`（external view）
- **目的**: 金利**昇順**（償還順）に各 Trove の（所属バッチ、現在年率、全債務）を列挙する。金利帯ごとの債務分布（redemption リスクの可視化・delegate 戦略 UI）の構築用。
- **権限**: permissionless（view）。
- **事前条件（Checks）**: CORE-MTG-FR-001 と同じ（require `"Invalid collateral index"` / assert）。
- **動作（Effects）**:
  1. 開始点: `_startId == 0` なら `getLast()`（最低金利）、それ以外は指定 Trove ID から
  2. 最大 `_maxIterations` 件、`currId != 0` の間: `sortedTroves.nodes(currId)` から `prevId`（次に金利が高いノード）と `batchId` を読み、`data[i] = { interestBatchManager = batchId（非バッチは 0）, interestRate = getLatestTroveData(currId).annualInterestRate, debt = entireDebt }` を記録して `currId = prevId` へ進む
  3. 返り値 `data` は**長さ `_maxIterations` 固定**（リスト末端で早期終了した場合、残り要素はゼロ値のまま）
  4. 返り値 `currId` は次の未処理ノード ID（カーソル）。`0` なら先頭（最高金利）まで走査完了
- **revert / 早期 return**: 無効 index → `"Invalid collateral index"`。
- **発火イベント**: なし。
- **設計上のポイント**: ページングは「返った `currId` を次回の `_startId` に渡す」カーソル方式（CORE-LCG-FR-001 と同型）。`_maxIterations` がそのままメモリ確保量になるため過大値はコスト増。バッチ加入 Trove も 1 Trove = 1 ノードとして個別に現れ、`interestRate` はバッチ現行率を反映する。
- **Verification**: parity / unit。

#### CORE-MTG-FR-003: 参照 view 関数群 🔵

- **Type**: Functional ｜ **Source**: base 実装（MultiTroveGetter.sol）

| 関数 | 返り値の意味 |
| --- | --- |
| `collateralRegistry()` | constructor で固定した CollateralRegistry アドレス |

- **Verification**: parity。


### DebtInFrontHelper の機能要件（CORE-DFH-FR-*）

#### CORE-DFH-FR-001: getDebtBetweenInterestRates（金利帯の債務合計）🔵

- **Type**: Functional ｜ **Source**: base 実装（DebtInFrontHelper.sol）
- **シグネチャ**: `getDebtBetweenInterestRates(uint256 _collIndex, uint256 _interestRateLo, uint256 _interestRateHi, uint256 _excludedTroveId, uint256 _hintId, uint256 _numTrials) → (uint256 debt, uint256 blockTimestamp)`（external view）
- **目的**: 年率が `[_interestRateLo, _interestRateHi)`（**lo 含む・hi 含まない**。インターフェース注記どおり）に入る全 Trove の `entireDebt` 合計を返す。`_excludedTroveId` は合算から除外する（走査は継続）。自 Trove を除いた金利帯滞留債務＝償還バッファの算出が典型用途。
- **権限**: permissionless（view）。
- **事前条件（Checks）**: `getTroveManager(_collIndex) != address(0)`（require `"Invalid collateral index"`）。`sortedTroves != address(0)`（assert）。
- **動作（Effects）**:
  1. **hint 改善（`_numTrials > 0` のとき）**: `keccak256(abi.encode(block.timestamp, 全引数))` を擬似乱数シードとして `hintHelpers.getApproxHint(_collIndex, _interestRateLo, _numTrials, seed)` を実行。新 hint の `diff`（目標金利との差）が呼出側提供の `_hintId` の差より小さければ採用（`_hintId == 0` は差 `type(uint256).max` 扱い＝必ず新 hint 採用）。`_numTrials == 0` なら `_hintId` をそのまま使う
  2. **開始点の確定**: `sortedTroves.findInsertPosition(_interestRateLo, hint, hint)` の第 1 返り値（prev 側）＝「年率 ≥ lo を満たす最も末尾（低金利）寄りのノード」を `currId` とする（ST 節。挿入位置は同率グループの末尾側に決まるため、**同率 lo の Trove も全て走査対象に含まれる**）
  3. **走査**: `currId != 0` の間、`getLatestTroveData(currId)` を取得し、(a) `annualInterestRate >= _interestRateHi` なら break、(b) `currId == _excludedTroveId` ならスキップ、(c) それ以外は `debt += entireDebt`。`currId = sortedTroves.getPrev(currId)`（金利昇順＝先頭方向）へ進む
  4. `blockTimestamp = block.timestamp` を添えて返す（off-chain 利用時にどの時点の状態かを識別するための値）
- **revert / 早期 return**: 無効 index → `"Invalid collateral index"`。lo を満たすノードがなければ走査ゼロ件で `debt = 0`。
- **発火イベント**: なし。
- **設計上のポイント**: 債務は `entireDebt`（利息・再分配込み）で合算するため償還が実際に消化する量と整合する。hint は `findInsertPosition` の先頭からの全降下を避けるための最適化で、結果の正しさには影響しない。`_interestRateLo = 0` とすればリスト末尾からの全走査＝当該金利までの完全な debt-in-front になる。zombie Trove はリスト外であり合算に含まれない（償還では `lastZombieTroveId` が優先消化される。TM 節）。ループは unbounded であり off-chain（eth_call）専用。
- **Verification**: parity / unit。

#### CORE-DFH-FR-002: getDebtBetweenInterestRateAndTrove（特定 Trove 直前までの債務合計）🔵

- **Type**: Functional ｜ **Source**: base 実装（DebtInFrontHelper.sol）
- **シグネチャ**: `getDebtBetweenInterestRateAndTrove(uint256 _collIndex, uint256 _interestRateLo, uint256 _interestRateHi, uint256 _troveIdToStopAt, uint256 _hintId, uint256 _numTrials) → (uint256 debt, uint256 blockTimestamp)`（external view）
- **目的**: CORE-DFH-FR-001 と同一の走査を行うが、`_troveIdToStopAt` に**到達した時点で走査を打ち切る**（当該 Trove の債務は不算入）。これにより「特定 Trove の真の debt-in-front」を、**同率 Trove が多数いる場合のリスト内順序まで反映して**算出できる（償還はリスト順に消化するため、同率でも自分より末尾側にいる Trove は先に償還される）。
- **権限**: permissionless（view）。
- **事前条件（Checks）**: CORE-DFH-FR-001 と同じ。
- **動作（Effects）**: 内部共通関数 `_getDebtBetween` を `_stopAfterExludedTrove = true` で呼ぶ。走査中 `currId == _troveIdToStopAt` に達したら break（FR-001 はスキップして継続、本関数は停止、の違いのみ）。
- **revert / 早期 return**: CORE-DFH-FR-001 と同じ。`_troveIdToStopAt` が範囲内に現れない場合は FR-001 と同値（hi または リスト先頭まで合算）。
- **発火イベント**: なし。
- **設計上のポイント**: 自 Trove の償還順位評価では `_interestRateLo = 0`（または下限金利）・`_interestRateHi = 自 Trove 年率 + ε`・`_troveIdToStopAt = 自 Trove` のように使う。シード由来（`block.timestamp` 入り）の hint 選択は結果値に影響しない（開始点最適化のみ）。
- **Verification**: parity / unit。

#### CORE-DFH-FR-003: 参照 view 関数群 🔵

- **Type**: Functional ｜ **Source**: base 実装（DebtInFrontHelper.sol）

| 関数 | 返り値の意味 |
| --- | --- |
| `collateralRegistry()` | constructor で固定した CollateralRegistry アドレス |
| `hintHelpers()` | constructor で固定した HintHelpers アドレス |

- **Verification**: parity。


### RedemptionHelper の機能要件（CORE-RH-FR-*）

#### CORE-RH-FR-001: redeemCollateral（min-out 付き償還ラッパー）🔵

- **Type**: Functional ｜ **Source**: base 実装（RedemptionHelper.sol）
- **シグネチャ**: `redeemCollateral(uint256 _jpydf, uint256 _maxIterationsPerCollateral, uint256 _maxFeePct, uint256[] _minCollRedeemed)`（external・nonpayable）
- **目的**: `CollateralRegistry.redeemCollateral(_jpydf, _maxIterationsPerCollateral, _maxFeePct)`（CR 節）のラッパー。CR 直接呼出に対して追加するのは **(a) ブランチ別の最低受領担保量 `_minCollRedeemed` によるスリッページ保護**と **(b) 未償還 JPYdf 残余の自動返還**。`_maxIterationsPerCollateral`（ブランチ毎の Trove 走査上限）と `_maxFeePct`（許容 fee 率上限）は CR の既存パラメータの素通しであり、本ラッパーが新設するものではない。
- **権限**: permissionless。呼出者は事前に本コントラクトへ `_jpydf` 以上の JPYdf approve が必要（`transferFrom` で引き落とすため）。
- **事前条件（Checks）**:
  - `_jpydf > 0`（require `"Redeemed amount must be non-zero"`）
  - `_minCollRedeemed.length == numBranches`（require `"Wrong _minCollRedeemed length"`）
- **動作（Effects）**:
  1. 各ブランチの担保トークン（`collateralRegistry.getToken(i)`。実体は dToken。[dToken.md](./dToken.md)）と、その本コントラクト残高（before）を記録
  2. 本コントラクトの JPYdf 残高（before）を記録
  3. `jpydfToken.transferFrom(msg.sender → 本コントラクト, _jpydf)`
  4. `collateralRegistry.redeemCollateral(_jpydf, _maxIterationsPerCollateral, _maxFeePct)` を呼出（**本コントラクトが redeemer になる**: 焼却は本コントラクト残高から行われ、各ブランチの償還担保は本コントラクトに届く。fee 率超過は CR 側 require `"CR: Fee exceeded provided maximum"` で revert）
  5. 各ブランチ: `collRedeemed = 残高（after）− 残高（before）` を算出し、`collRedeemed >= _minCollRedeemed[i]` を require（`"Insufficient collateral redeemed"`）。`collRedeemed > 0` なら `safeTransfer` で `msg.sender` へ送付
  6. `jpydfRemaining = JPYdf 残高（after）− 残高（before）`（焼却されなかった未償還分）。`> 0` なら `msg.sender` へ返還
- **revert / 早期 return**: 上記 require 2 件＋ステップ 5 の min-out 違反。加えて `transferFrom` 失敗（approve/残高不足）、CR・ブランチ側の revert が伝播。
- **発火イベント**: なし（JPYdf / collToken の `Transfer`、CR・TM 側イベントは各節）。
- **設計上のポイント**: CR の償還は (a) unbacked 合計への要求額切詰め、(b) `_maxIterationsPerCollateral` による走査打切り、(c) ICR < 100% Trove のスキップ、により**要求額未満で終わりうる**（CR 節・TM 節）。直接呼出では受領担保量を事前に拘束できないため、本ラッパーが per-branch min-out を提供する。`_minCollRedeemed` の基礎値は CORE-RH-FR-003 `truncateRedemption` の `redeemed[i].coll` から得る想定（インターフェース NatSpec）。残余 JPYdf 返還により、部分約定でも呼出者資金が本コントラクトに滞留しない。
- **Verification**: parity / unit（min-out 違反 revert・残余返還）/ invariant=CORE-RH-INV-001。

#### CORE-RH-FR-002: simulateRedemption（償還シミュレーション）🔵

- **Type**: Functional ｜ **Source**: base 実装（RedemptionHelper.sol）
- **シグネチャ**: `simulateRedemption(uint256 _jpydf, uint256 _maxIterationsPerCollateral) → (SimulationContext[] branch, uint256 totalProportions)`（public・**nonpayable**・off-chain 専用）
- **目的**: `_jpydf` を償還要求した場合の CR のブランチ配分（unbacked 比例）と、各ブランチで `_maxIterationsPerCollateral` 以内に実際へ充当できる償還量 `redeemedJpydf` を、実装と同じ規則の走査で試算する。
- **権限**: permissionless。**view でない理由**: 各ブランチの `TroveManager.getUnbackedPortionPriceAndRedeemability`（TM 節）が内部で `PriceFeed.fetchPrice`（[Oracle.md](./Oracle.md)）を呼び、価格取得が状態書込みを伴うため。on-chain から呼べば実際にオラクル状態が更新される。eth_call での利用を想定。
- **動作（Effects）**:
  1. 各ブランチ: `troveManager` / `sortedTroves` アドレスと、`getUnbackedPortionPriceAndRedeemability()` の `(proportion = unbacked debt（ブランチ全債務 − SP 預入。下限 0）, price = 通常価格, redeemable = TCR ≥ SCR かつ未 shutdown)` を取得。redeemable なブランチの `proportion` 合計を `totalProportions` に集計
  2. `0 < totalProportions < _jpydf` なら `_jpydf` を `totalProportions` に切詰め（unbacked 超過分の比例崩れ防止。CR 実装と同じ規則。コード内コメント: CS-BOLD-013）
  3. `totalProportions == 0` なら fallback: 各ブランチの `proportion` を `getEntireBranchDebt()`（ブランチ全債務）に置き換え、redeemable のみ再集計（CR の fallback と同じ）
  4. それでも `totalProportions == 0` なら早期 return
  5. 各 redeemable ブランチ: `attemptedJpydf = _jpydf × proportion / totalProportions`（0 ならスキップ）。Trove 走査は実償還と同順——`lastZombieTroveId` が非零ならそれを最初に検査（次は `sortedTroves.getLast()`）、なければ `getLast()`（最低金利）から `getPrev` で金利昇順。各反復で `redeemedJpydf == attemptedJpydf` または `troveId == 0` なら打切り。`entireColl × price / entireDebt >= _100pct`（ICR ≥ 100%。通常価格判定）の Trove のみ `min(attemptedJpydf − redeemedJpydf, entireDebt)` を `redeemedJpydf` に加算し、**ICR < 100% の Trove は加算せずスキップ**（実装の skip 規則と同じ。スキップも iteration を消費）。反復回数上限は `_maxIterationsPerCollateral`（**0 = 無制限**）
  6. ブランチ毎の `SimulationContext{ troveManager, sortedTroves, redeemable, price, proportion, attemptedJpydf, redeemedJpydf, iterations }` と `totalProportions` を返す
- **revert / 早期 return**: `totalProportions == 0` で早期 return（branch 配列と 0）。
- **発火イベント**: なし（オラクル側のイベントは [Oracle.md](./Oracle.md)）。
- **設計上のポイント**: 配分・切詰め・走査順（zombie 優先→最低金利から）・ICR 100% 判定（通常価格）まで CR/TM の実装規則をなぞるため、同一状態での `redeemedJpydf` は実償還の充当量と整合する。本関数は JPYdf/担保の額面計算（fee・redemption price 換算）は行わない（それは CORE-RH-FR-003）。fallback 時、redeemable でないブランチにも `proportion` が上書き設定されるが、配分段階で `redeemable == false` はスキップされるため結果に影響しない。
- **Verification**: parity / unit。

#### CORE-RH-FR-003: truncateRedemption（最適償還量への切詰めと受領見積り）🔵

- **Type**: Functional ｜ **Source**: base 実装（RedemptionHelper.sol）
- **シグネチャ**: `truncateRedemption(uint256 _jpydf, uint256 _maxIterationsPerCollateral) → (uint256 truncatedJpydf, uint256 feePct, Redeemed[] redeemed)`（external・**nonpayable**・off-chain 専用）
- **目的**: `_maxIterationsPerCollateral` の範囲内で**比例配分どおりに償還しきれる最大の JPYdf 量** `truncatedJpydf` を求め、その場合の fee 率と各ブランチの期待受領担保量を返す。CR の redemption fee **率**は per-branch 償還の実行前に「要求額」から確定する（CR 節）ため、走査上限で処理しきれない過大要求は「実際に償還できた量に対して必要以上に高い fee 率」を支払うことになる。これを避ける要求サイズを与えるのが目的（インターフェース NatSpec）。
- **権限**: permissionless。nonpayable の理由は CORE-RH-FR-002 と同じ（加えて本関数は `fetchRedemptionPrice` も呼ぶ）。
- **動作（Effects）**:
  1. `simulateRedemption(_jpydf, _maxIterationsPerCollateral)` を実行（CORE-RH-FR-002）
  2. `totalProportions == 0` なら `(0, 0, 空配列)` を返す
  3. `truncatedJpydf = _jpydf` を初期値に、各 redeemable かつ `proportion > 0` のブランチについて `extrapolatedJpydf = redeemedJpydf × totalProportions / proportion`（このブランチの充当実績から逆算した「比例配分が成立する全体要求量」）を計算し、その**最小値**まで `truncatedJpydf` を切詰める（iteration 上限に当たらなかったブランチでは `extrapolatedJpydf ≈ _jpydf` となり切詰めなし）
  4. `feePct = collateralRegistry.getRedemptionRateForRedeemedAmount(truncatedJpydf)`（CR 節。baseRate の時間減衰＋当該償還量による上昇を織り込んだ償還 fee 率。下限 `REDEMPTION_FEE_FLOOR`・上限 100%。値は §7）
  5. 各 redeemable かつ `proportion > 0` のブランチ: `addresses[i].priceFeed().fetchRedemptionPrice()`（償還用価格。[Oracle.md](./Oracle.md)）を取得し、`redeemed[i].jpydf = truncatedJpydf × proportion / totalProportions`、`redeemed[i].coll = redeemed[i].jpydf × (DECIMAL_PRECISION − feePct) / redemptionPrice`（fee 控除後の期待受領担保。TM の `collLot = jpydfLot/価格 − fee` と同形）
- **revert / 早期 return**: `totalProportions == 0` → `(0, 0, 空配列)`。
- **発火イベント**: なし。
- **設計上のポイント**: `redeemed[i].coll` は CORE-RH-FR-001 の `_minCollRedeemed` の基礎値（呼出者は許容スリッページ分を割り引いて指定する想定）。試算の ICR 判定は通常価格、担保換算は redemption price という価格の使い分けも TM 実装（TM 節）と同じ。eth_call 時点と実行 tx 時点の状態差（価格・baseRate・リスト変動）は呼出者のリスクであり、それを吸収するのが FR-001 の min-out である。
- **Verification**: parity / unit。

#### CORE-RH-FR-004: 参照 view 関数群 🔵

- **Type**: Functional ｜ **Source**: base 実装（RedemptionHelper.sol）

| 関数 | 返り値の意味 |
| --- | --- |
| `numBranches()` | ブランチ数（デプロイ時の `totalCollaterals` と一致） |
| `collateralRegistry()` | constructor で固定した CollateralRegistry |
| `jpydfToken()` | CR から取得した JPYdf トークン |
| `addresses(uint256 i)` | ブランチ i の AddressesRegistry（範囲外 index は配列境界 revert） |

- **Verification**: parity。

#### CORE-RH-FR-005: constructor（デプロイ時整合性検証）🔵

- **Type**: Functional ｜ **Source**: base 実装（RedemptionHelper.sol）
- **シグネチャ**: `constructor(ICollateralRegistry _collateralRegistry, IAddressesRegistry[] _addresses)`
- **目的**: ブランチ構成のスナップショットを取り、CR との不整合デプロイを拒否する。
- **事前条件（Checks）**:
  - `_addresses.length == _collateralRegistry.totalCollaterals()`（require `"Wrong number of registries"`）
  - 各 i について `_collateralRegistry.getTroveManager(i) == _addresses[i].troveManager()`（require `"TroveManager mismatch"`）
- **動作（Effects）**: `numBranches` / `collateralRegistry` / `jpydfToken`（`= collateralRegistry.jpydfToken()`）を immutable 固定し、`addresses` 配列へ push。
- **設計上のポイント**: CR の `totalCollaterals` は immutable（CR 節）のため、デプロイ後にブランチ数が変わって不整合になることはない。
- **Verification**: unit（不一致 constructor revert）。


### LiquidationCandidateGetter の機能要件（CORE-LCG-FR-*）

#### CORE-LCG-FR-001: getLiquidationCandidates（清算候補のページング走査）🟢

- **Type**: Functional ｜ **Source**: DF 実装（LiquidationCandidateGetter.sol。base に存在しない）
- **シグネチャ**: `getLiquidationCandidates(uint256 _collIndex, uint256 _startId, uint256 _maxIterations, uint256 _price, uint256 _mcr) → (LiquidationCandidate[] candidates, uint256 currId)`（external view）
- **目的**: ブランチ `_collIndex` の SortedTroves を金利順に最大 `_maxIterations` ノード走査し、`getCurrentICR(troveId, _price) < _mcr` を満たす Trove を `LiquidationCandidate{ id, ICR, entireDebt, entireColl }` として列挙する。清算（`TroveManager.batchLiquidateTroves`。TM 節）の対象候補抽出・監視用。
- **権限**: permissionless（view）。
- **事前条件（Checks）**: `getTroveManager(_collIndex) != address(0)`（`LiquidationCandidateGetter__InvalidCollateralIndex`）。`sortedTroves != address(0)`（assert）。
- **動作（Effects）**:
  1. 作業バッファ `LiquidationCandidate[_maxIterations]` を確保
  2. 走査開始点: `_startId == 0` なら `sortedTroves.getFirst()`（先頭＝最高金利）、それ以外は `_startId` から
  3. 最大 `_maxIterations` 回、`currId != 0` の間反復: `troveId = currId` とし、**先に** `currId = sortedTroves.getNext(troveId)`（金利降順方向）へ進める → 返り値 `currId` は常に「次の未走査ノード」になる
  4. `icr = troveManager.getCurrentICR(troveId, _price)`（`entireColl × _price / entireDebt`。利息・再分配込み。TM 節）を計算し、`icr >= _mcr` なら continue
  5. 該当 Trove は `getLatestTroveData` から `entireDebt` / `entireColl` を取得してバッファへ追加
  6. ヒット件数ちょうどの配列に詰め直して返す
- **revert / 早期 return**: 無効 index → `LiquidationCandidateGetter__InvalidCollateralIndex`。リスト末尾到達（`currId == 0`）でループ終了。
- **発火イベント**: なし。
- **設計上のポイント**:
  - **ページング**: 返り値 `currId` を次回呼出の `_startId` に渡すカーソル方式（CORE-MTG-FR-002 と同型）。`currId == 0` が全走査完了の合図。SortedTroves の並びは金利順で **ICR とは無相関**のため、候補を漏れなく得るには全リスト走査が必要であり、そのページング手段を提供するのが本関数。`_maxIterations` はバッファのメモリ確保量を兼ねるため過大値はコスト増。
  - **`_price` / `_mcr` を引数で受ける理由**: `PriceFeed.fetchPrice` は状態書込みを伴い view にできないため、価格は呼出者が off-chain で取得して渡す（[Oracle.md](./Oracle.md) PriceFeedProxy）。MCR もブランチ定数（AddressesRegistry / [Parameters.md](../../../Parameters.md)）を呼出者が渡す。実際の清算判定（`ICR < MCR`。TM 節）と同形になる値を渡すのは呼出者の責任であり、仮想価格を渡したストレス走査（「価格が X なら何件落ちるか」）にも使える。
  - **zombie Trove は本関数では対象外**: 走査対象はソート済みリストのみ。zombie Trove（償還で `MIN_DEBT` 未満となりリストから除去。TM 節）は **`_isActiveOrZombie` により清算可能だが本関数の候補には現れない**。`lastZombieTroveId` の監視は CORE-LCG-FR-003 を使う。
  - **`_startId` の前提**: 実在のリスト内 Trove ID を渡す前提。ページング間にリストから外れた ID（償還・清算・調整で除去）を渡すと `getNext == 0` となり走査が即終了する（revert はしない）。ページング間のリスト変動による取りこぼし・重複は呼出側で許容・再走査する設計。
- **Verification**: unit（🟢 DF 独自のため parity 対象外。ICR 境界・ページング・空リスト・zombie 除外）。

#### CORE-LCG-FR-003: lastZombieTroveId の清算候補化 🟢

- **Type**: Functional ｜ **Source**: DF 実装（LiquidationCandidateGetter.sol。base に存在しない）
- **シグネチャ**: `getLastZombieLiquidationCandidate(uint256 _collIndex, uint256 _price, uint256 _mcr) → (bool found, LiquidationCandidate candidate)`（external view）／`getLiquidationCandidatesWithLastZombie(..., bool _includeLastZombie) → (LiquidationCandidate[] candidates, uint256 currId, bool includedLastZombie)`（external view）
- **目的**: SortedTroves から外れる zombie Trove のうち、TroveManager が直近ポインタとして保持する `lastZombieTroveId` を清算 bot の候補に含める。bot が TroveManager を別 ABI で読んで debt/coll=0 の暫定候補を作る必要をなくす。
- **権限**: permissionless（view）。
- **事前条件（Checks）**: `getTroveManager(_collIndex) != address(0)`（`LiquidationCandidateGetter__InvalidCollateralIndex`）。
- **動作（Effects）**:
  1. `lastZombieTroveId == 0` なら `found=false`
  2. `getTroveStatus(lastZombieTroveId) != zombie` なら stale pointer として `found=false`
  3. `getCurrentICR(lastZombieTroveId, _price) >= _mcr` なら清算対象外として `found=false`
  4. 条件を満たす場合、`getLatestTroveData` から `entireDebt` / `entireColl` を取得し、`LiquidationCandidate{ id, ICR, entireDebt, entireColl }` と `found=true` を返す
  5. `getLiquidationCandidatesWithLastZombie` は CORE-LCG-FR-001 の SortedTroves ページング結果に、`_includeLastZombie == true` かつ step 4 が成立した候補を末尾へ 1 件だけ追記し、`includedLastZombie=true` を返す。`currId` は SortedTroves ページングの次 cursor のまま。
- **revert / 早期 return**: 無効 index → `LiquidationCandidateGetter__InvalidCollateralIndex`。liquidatable な last zombie がなければ空 / `found=false`（revert しない）。
- **設計上のポイント**: Liquity v2 の core は `lastZombieTroveId` 1 件のみを次回 redemption 優先対象として保持するため、本ヘルパーもその 1 件を扱う。複数 zombie の完全網羅はイベント/indexer 側の後続課題であり、本関数は「core が明示的に保持する zombie pointer を清算監視から漏らさない」ための最小拡張。
- **Verification**: unit（last zombie あり/なし・stale pointer 相当・ICR 境界・debt/coll 取得・combined API の末尾追記）。

#### CORE-LCG-FR-002: 参照 view 関数群 🟢

- **Type**: Functional ｜ **Source**: DF 実装（LiquidationCandidateGetter.sol）
- **事前条件（Checks）**: constructor の `_collateralRegistry != address(0)`。zero registry は `LiquidationCandidateGetter__InvalidCollateralRegistry`。

| 関数 | 返り値の意味 |
| --- | --- |
| `collateralRegistry()` | constructor で固定した CollateralRegistry アドレス |

- **Verification**: unit。


### Constants.sol の機能要件（CORE-LIB-FR-*）

#### CORE-LIB-FR-001: file-level システム定数の提供 🔵
- **Type**: Functional ｜ **Source**: base 実装（Constants.sol）
- **シグネチャ**: なし（file-level `constant` 宣言群）
- **目的**: core 全体で共有する経済・時間パラメータを単一ファイルに集約し、参照側コントラクトへコンパイル時に定数として埋め込む。
- **権限**: なし（オンチェーンの設定操作は存在しない）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**: 状態変化なし。各定数は参照側バイトコードへインライン展開される。
- **revert / 早期 return**: なし。
- **発火イベント**: なし。
- **設計上のポイント**: 定数はストレージを持たないため、値の変更＝参照コントラクト群の再デプロイを意味する（パラメータは事実上 immutable）。ブランチ別の CR・ペナルティは Constants の値そのものではなく、デプロイ時に AddressesRegistry の immutable（`CCR`/`MCR`/`BCR`/`SCR`/`LIQUIDATION_PENALTY_*`）へ注入された値が実効値となる（注入経路はデプロイスクリプト。CORE-AR 参照）。
- **Verification**: parity（🟡 2 件を除く全定数の base 同値性 = CORE-LIB-INV-001）

#### CORE-LIB-FR-002: MIN_DEBT（最小負債の変更）🟡
- **Type**: Functional ｜ **Source**: CORE-MOD-002 / `Constants.sol`
- **シグネチャ**: `uint256 constant MIN_DEBT = 300_000e18`
- **目的**: Trove が維持すべき最小負債（JPYdf 建て・entire debt 基準）を定める。小口 Trove の乱立による清算・redemption の不経済化（ガスコスト > 期待利得）と、逐次 redemption への grief を防ぐ。
- **権限**: なし（定数）。
- **事前条件（Checks）**: BorrowerOperations constructor が `assert(MIN_DEBT > 0)` を検証（ゼロ借入での開設を構造的に不能化）。
- **動作（Effects）**: 主な enforcement（規範は各スコープの FR）:
  1. 開設・調整時: entire debt が `MIN_DEBT` 未満なら revert（BorrowerOperations `_requireAtLeastMinDebt` → `DebtBelowMin`。CORE-BO 参照）
  2. 返済時: 返済上限を `entireDebt - MIN_DEBT` にキャップ（CORE-BO 参照）
  3. redemption 後: 残債が `MIN_DEBT` 未満となった Trove は zombie 化され、ソートリストから除外（TroveManager。CORE-TM 参照）
  4. zombie Trove の復帰: entire debt ≥ `MIN_DEBT` への調整で再 activate（CORE-BO 参照）
- **revert / 早期 return**: `DebtBelowMin`（BorrowerOperations 側）。
- **発火イベント**: なし。
- **Base との差分**: base では `2000e18`（2,000 BOLD・USD 建て）、DF では `300_000e18`（300,000 JPYdf）。根拠: ステーブルコインが USD 建て BOLD から JPY 建て JPYdf に変わることに伴い、base と同水準の経済的下限を円建てで維持する再スケール（正本: CORE-MOD-002 / CORE-LIB-FR-002）。
- **Verification**: unit（境界値: `MIN_DEBT` ちょうど / 未満）、🟡 差分テスト（値が 300_000e18 であること）

#### CORE-LIB-FR-003: COLL_GAS_COMPENSATION_CAP（担保ガス補償上限の変更）🟡
- **Type**: Functional ｜ **Source**: CORE-MOD-003 / [Parameters.md](../../../Parameters.md)
- **入力**: TroveManagerのconstructor引数`_collGasCompensationCap`。18桁のdToken単位で、0より大きく`COLL_GAS_COMPENSATION_CAP`（1,000 ether）以下とする。
- **動作**: SP相殺分の担保の0.5%を計算し、ブランチの上限を適用する。再分配のみの場合は担保建て報酬を支払わない。固定額のWETH報酬は維持する。
- **設定期間**: 稼働ブランチはデプロイ時に確定する。予約ブランチは、MCRなどと同じ`finalizeRiskParams`で一度だけ確定する。Registryは`RiskParams.COLL_GAS_COMPENSATION_CAP`の範囲を検証し、構造体を受け取る`TroveManager.syncRiskParams`へ渡す。cap・供給量・Core残高がゼロであることなど、既存の有効化前条件を満たす必要がある。同期失敗時は全更新を戻し、確定後の変更は認めない。
- **デプロイ**: CREATE2アドレス予測と実際のデプロイに同じ上限を渡す。予約ブランチの初期上限は1,000単位とし、有効化前に担保ごとの値へ一度だけ更新する。
- **検証**: 上限前後の境界、SP相殺の有無と部分相殺、担保配分の保存、デプロイ配線、storage layout、実行時コードサイズ。

#### CORE-LIB-FR-004: DF ブランチ別定数群 🟢
- **Type**: Functional ｜ **Source**: CORE-MOD-005 / [Parameters.md](../../../Parameters.md) / [Collateral Parameter Policy](../policies/Collateral-Parameter-Policy.md) §2.4
- **シグネチャ**: `MCR_<BR>` / `CCR_<BR>` / `SCR_<BR>` / `BCR_<BR>` / `LIQUIDATION_PENALTY_SP_<BR>` / `LIQUIDATION_PENALTY_REDISTRIBUTION_<BR>`（8 ブランチ × 6 種 = 48 の `uint256 constant`。suffix は状態変数表 (b) を参照）
- **目的**: DFのDay-1 8担保ブランチ（`NUM_DF_ACTIVE_BRANCHES = 2`、dwstETH / dUSDCだけがactive、branch 2–7はinert）ごとのCR・ペナルティ値を、dToken名で命名した定数として宣言する（coreの担保 = dToken）。
- **権限**: なし（定数）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**: 宣言のみ。コードコメントに即した規範事項:
  1. **production constant surface の限定**: `contracts/src` には generic precision / liquidation bound / gas compensation / debt cap / interest cap と、DF dToken branch 定数だけを置く。production 未参照の upstream `*_WETH` / `*_SETH` / `BCR_ALL` と補助別名 `ZERO_ADDRESS` / `MAX_UINT256` は置かない。inherited multicollateral test は `TEST_*` fixture 定数をローカルに持ち、テスト用別名は `address(0)` / `type(uint256).max` を直接使う。
  2. **DF dToken wiring で実消費**: 現行 `DeployLiquity2` は `_dfBranchParams()` で本定数群を `TroveManagerParams` に注入し、DF 8 branch deploy の `AddressesRegistry` constructor へ渡す。non-mainnet では DF dToken wiring が既定、mainnet では `DF_ENABLE_MAINNET_DTOKEN_WIRING=true` を明示した場合のみこの経路を使う。legacy / upstream 3 branch deploy path は Day-1 方針と manifest consumer の前提から外れたため削除済み。
  3. **表現の厳密性**: 小数点つき％は `<pct*100> * _1pct / 100` で表現され、`_1pct`（= 1e16）が 100 で割り切れるため誤差ゼロで厳密（Parameters.md の値は小数 2 桁以内。CORE-LIB-INV-002）。
  4. **inert ブランチ（Br2–7）の値も Day-1 確定**: ブランチパラメータはデプロイ後 immutable のため、Underlying が TBD でも Parameters.md の値をDay1で確定投入する。activation前にexact Underlyingが [Collateral Parameter Policy](../policies/Collateral-Parameter-Policy.md) §2.4へ適合することを検証し、適合しなければinertのまま維持する。
- **revert / 早期 return**: なし。
- **発火イベント**: なし。
- **設計上のポイント**: 値の正本は [Parameters.md](../../../Parameters.md)。dJPY / dJGB は BCR・再分配ペナルティが5%の特例（他ブランチは10%）。
- **Verification**: unit（各 DF 定数とコメント値・Parameters.md の一致）、absence review（`*_WETH` / `*_SETH` / `BCR_ALL` / `ZERO_ADDRESS` / `MAX_UINT256` が production `src` に残らないこと）、deploy / integration（DF dToken wiring の branch params へ注入されること、mainnet `complete` が `DF_ENABLE_MAINNET_DTOKEN_WIRING=true` なしで fail-closed すること）


### LiquityBase の機能要件（CORE-LIB-FR-*）

#### CORE-LIB-FR-005: constructor（AddressesRegistry からの参照解決）🔵
- **Type**: Functional ｜ **Source**: base 実装（LiquityBase.sol）
- **シグネチャ**: `constructor(IAddressesRegistry _addressesRegistry)`
- **目的**: ブランチの AddressesRegistry から ActivePool / DefaultPool / PriceFeed の参照を 1 度だけ解決して保持する。
- **権限**: デプロイ時のみ（継承コントラクトの constructor 経由）。
- **事前条件（Checks）**: なし（ゼロアドレス検証なし。配線の正しさはデプロイ手順に依存）。
- **動作（Effects）**:
  1. `activePool = _addressesRegistry.activePool()`
  2. `defaultPool = _addressesRegistry.defaultPool()`
  3. `priceFeed = _addressesRegistry.priceFeed()`
  4. `ActivePoolAddressChanged` / `DefaultPoolAddressChanged` / `PriceFeedAddressChanged` を発火
- **revert / 早期 return**: なし。
- **発火イベント**: CORE-LIB-EVT-001 / 002 / 003（デプロイ時に 1 回のみ）。
- **設計上のポイント**: 3 変数とも setter を持たず事後変更不能（storage だが事実上 immutable）。継承側（BO / TM / SP / DFStabilityPool）はブランチ単位でデプロイされるため、参照はそのブランチの Pool 群・PriceFeedProxy を指す。
- **Verification**: parity / deploy 検証（配線一致）

#### CORE-LIB-FR-006: getEntireBranchColl / getEntireBranchDebt（ブランチ全体の集計）🔵
- **Type**: Functional ｜ **Source**: base 実装（LiquityBase.sol）/ ILiquityBase
- **シグネチャ**: `getEntireBranchColl() → uint256 entireSystemColl` ／ `getEntireBranchDebt() → uint256 entireSystemDebt`（いずれも public view）
- **目的**: ブランチ全体の担保・負債を「ActivePool ＋ DefaultPool」の和として返す。TCR 計算・shutdown 判定・redemption 配分の基礎値。
- **権限**: なし（permissionless view）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**:
  1. Coll: `activePool.getCollBalance() + defaultPool.getCollBalance()`
  2. Debt: `activePool.getJpydfDebt() + defaultPool.getJpydfDebt()`。`activePool.getJpydfDebt()` は集計記帳負債に加え pending の集計利息・バッチ運用報酬を含む（構成の規範は CORE-AP）。`defaultPool.getJpydfDebt()` は再分配の未適用負債（規範は CORE-DP）
- **revert / 早期 return**: なし。
- **発火イベント**: なし（view）。
- **設計上のポイント**: 「branch」単位の集計であり、マルチブランチ全体の合算ではない（全体は CollateralRegistry 経由で各ブランチを走査）。
- **Verification**: parity / invariant=CORE-SYS-INV-001

#### CORE-LIB-FR-007: _getTCR / _checkBelowCriticalThreshold（TCR と CT 判定）🔵
- **Type**: Functional ｜ **Source**: base 実装（LiquityBase.sol）
- **シグネチャ**: `_getTCR(uint256 _price) → uint256 TCR` ／ `_checkBelowCriticalThreshold(uint256 _price, uint256 _CCR) → bool`（いずれも internal view）
- **目的**: ブランチの Total Collateral Ratio（TCR）を計算し、Critical Threshold（TCR < CCR）判定を提供する。借入制限（CT 下の新規借入・担保引出の制限等。CORE-BO）と shutdown 判定（TCR < SCR。CORE-BO）の基礎。
- **権限**: internal（継承コントラクトのみ）。
- **事前条件（Checks）**: なし。`_price` は呼出側が PriceFeed（DF では PriceFeedProxy。[Oracle.md](./Oracle.md)）の fetch 結果を渡す。
- **動作（Effects）**:
  1. `_getTCR`: `LiquityMath._computeCR(getEntireBranchColl(), getEntireBranchDebt(), _price)`（負債 0 なら type(uint256).max = 「無限 CR」）
  2. `_checkBelowCriticalThreshold`: `_getTCR(_price) < _CCR` を返す（CCR は AddressesRegistry 由来の immutable を呼出側が渡す）
- **revert / 早期 return**: なし。
- **発火イベント**: なし。
- **Verification**: parity / unit（負債 0 ブランチで false になること）

#### CORE-LIB-FR-008: _calcInterest（単利計算プリミティブ）🔵
- **Type**: Functional ｜ **Source**: base 実装（LiquityBase.sol）
- **シグネチャ**: `_calcInterest(uint256 _weightedDebt, uint256 _period) → uint256`（internal pure）
- **目的**: 「重み付き負債（debt × 年利、1e36 スケール）× 経過秒 ÷ 1 年」の単利（非複利）を返す、利息会計の最小プリミティブ。Trove・バッチの accrued interest / 運用報酬、upfront fee（7 日分の前払い利息）の計算基底。
- **権限**: internal pure。
- **事前条件（Checks）**: なし。
- **動作（Effects）**: `_weightedDebt * _period / ONE_YEAR / DECIMAL_PRECISION` を返す（**floor 除算**）。
- **revert / 早期 return**: なし（乗算 overflow 時は Solidity 0.8 Panic。CORE-LIB-ERR-001）。
- **設計上のポイント**: 個別 Trove の利息は floor、ActivePool 側の集計利息は ceil（`Math.ceilDiv`。CORE-AP）という丸めの非対称により「集計負債 ≥ Σ 個別負債」の正方向誤差を恒常的に保つ（システム負債が負にならない。CORE-SYS-INV-001）。
- **Verification**: parity / unit（丸め方向）


### LiquityMath の機能要件（CORE-LIB-FR-*）

#### CORE-LIB-FR-009: 比較・差分・担保比率ヘルパー 🔵
- **Type**: Functional ｜ **Source**: base 実装（LiquityMath.sol）
- **シグネチャ**: `_min(uint256,uint256) → uint256` / `_max(uint256,uint256) → uint256` / `_sub_min_0(uint256 _a, uint256 _b) → uint256` / `_getAbsoluteDifference(uint256,uint256) → uint256` / `_computeCR(uint256 _coll, uint256 _debt, uint256 _price) → uint256`（すべて internal pure）
- **目的**: core 全域で使う基本数値演算。特に `_computeCR` は ICR / TCR 計算の唯一の実装点。
- **権限**: internal pure。
- **事前条件（Checks）**: なし。
- **動作（Effects）**:
  1. `_min` / `_max`: 小さい方 / 大きい方を返す（`_max` は `>=` で a 優先）
  2. `_sub_min_0`: `a > b ? a - b : 0`（下限 0 の飽和減算）。**現状 production コードから未参照**
  3. `_getAbsoluteDifference`: `|a - b|`（HintHelpers のヒント近接度評価で使用）
  4. `_computeCR`: `_debt > 0` なら `_coll * _price / _debt`（floor。coll は 18dec 担保数量、price は 1e18 スケール、結果も 1e18 スケールの比率）。**`_debt == 0` なら `2**256 - 1`（type(uint256).max）を「無限 CR」として返す**
- **revert / 早期 return**: なし（`_coll * _price` の overflow 時は Panic。CORE-LIB-ERR-001）。
- **発火イベント**: なし。
- **設計上のポイント**: 無限 CR の規約により、負債 0（空ブランチ・完全 redeem 済み zombie 等）はあらゆる閾値比較（< MCR / < CCR / < SCR）で「健全」側に倒れる。
- **Verification**: parity / unit（debt=0 → max uint、丸め方向）

#### CORE-LIB-FR-010: decMul / _decPow（18 桁固定小数の累乗）🔵
- **Type**: Functional ｜ **Source**: base 実装（LiquityMath.sol）
- **シグネチャ**: `decMul(uint256 x, uint256 y) → uint256 decProd` ／ `_decPow(uint256 _base, uint256 _minutes) → uint256`（いずれも internal pure）
- **目的**: redemption baseRate の分単位指数減衰 `decayFactor^minutes`（CollateralRegistry `_calcDecayedBaseRate` が唯一の利用箇所）のための固定小数累乗。
- **権限**: internal pure。
- **事前条件（Checks）**: なし。
- **動作（Effects）**:
  1. `decMul`: 1e18 スケール同士の乗算 `(x*y + 1e18/2) / 1e18`。**四捨五入**（19 桁目 ≥ 5 で切り上げ）。`_decPow` 内部専用
  2. `_decPow`: 指数を **525,600,000 分（= 1,000 年）でキャップ**（overflow 回避。キャップ超の入力は減衰結果が実質 0 のため結果差は無視可能、とのコードコメント）。`_minutes == 0` なら `DECIMAL_PRECISION`（= 1.0）。それ以外は**二乗法（exponentiation by squaring）**で O(log n) 回の `decMul` を反復（偶数指数: `x = x²、n = n/2`、奇数指数: `y = x·y、x = x²、n = (n-1)/2`、最後に `x·y`）
- **revert / 早期 return**: なし。
- **発火イベント**: なし。
- **設計上のポイント**: 丸めが四捨五入（決定的）であるため、同一入力に対し逐次乗算と二乗法の結果は実装固有に確定する。parity テストは値の完全一致で検証可能。
- **Verification**: parity / unit（n=0 / n=1 / 偶奇 / キャップ境界 525,600,000）


### Ownable の機能要件（CORE-LIB-FR-*）

#### CORE-LIB-FR-011: 所有者モデル（constructor / owner / isOwner / onlyOwner）🔵
- **Type**: Functional ｜ **Source**: base 実装（Ownable.sol）
- **シグネチャ**: `constructor(address initialOwner)` / `owner() → address` / `isOwner() → bool` / `modifier onlyOwner`
- **目的**: デプロイ時に定めた単一 owner にのみ特定関数（継承側の配線関数）の呼出を許す最小アクセス制御。
- **権限**: `onlyOwner` 付与関数は現 owner のみ。
- **事前条件（Checks）**: constructor に **ゼロアドレス検証なし**（`initialOwner = address(0)` でもデプロイ可能。その場合 onlyOwner 関数は最初から呼出不能）。
- **動作（Effects）**:
  1. constructor: `_owner = initialOwner` とし `OwnershipTransferred(address(0), initialOwner)` を発火
  2. `owner()` / `isOwner()`: 参照のみ
  3. `onlyOwner`: `require(isOwner(), "Ownable: caller is not the owner")`
- **revert / 早期 return**: 非 owner の onlyOwner 呼出 → require 文字列 `"Ownable: caller is not the owner"`。
- **発火イベント**: CORE-LIB-EVT-004。
- **設計上のポイント**: `transferOwnership` が存在しないため owner の差し替えは不可能（OZ との明確な差異）。所有権の遷移は「初期設定 → （継承側ロジックによる）放棄」の一方向のみ。
- **Verification**: parity / unit（非 owner revert・文字列一致）

#### CORE-LIB-FR-012: _renounceOwnership（配線完了後の所有権放棄）🔵
- **Type**: Functional ｜ **Source**: base 実装（Ownable.sol）
- **シグネチャ**: `_renounceOwnership()`（internal）
- **目的**: 一回限りの初期配線が済んだコントラクトを恒久的に ownerless 化し、以後の設定変更を構造的に不能にする（trust 最小化）。
- **権限**: internal。**呼出元検証なし**（NatSpec が「owner チェックをしない・呼出側で確認せよ」と明記）。
- **事前条件（Checks）**: なし（継承側の責務）。
- **動作（Effects）**:
  1. `OwnershipTransferred(_owner, address(0))` を発火
  2. `_owner = address(0)`
- **revert / 早期 return**: なし。
- **発火イベント**: CORE-LIB-EVT-004。
- **設計上のポイント**: 現行の継承 2 箇所はいずれも `onlyOwner` 関数（JpydfToken `setCollateralRegistry` / AddressesRegistry `setAddresses`）の末尾で呼ぶため、実効的には owner 自身の操作によってのみ放棄が起こる（CORE-LIB-SEC-001）。放棄後は `owner() == address(0)`・`isOwner()` は常に false となり、onlyOwner 関数は呼出不能。
- **Verification**: parity / unit（放棄後の onlyOwner 恒久 revert・イベント引数）


### Types の機能要件（CORE-LIB-FR-*）

#### CORE-LIB-FR-013: TroveId 型（Deprecated: production `src` から削除）🔵
- **Type**: Functional (Deprecated) ｜ **Source**: base 実装（旧 `Types/TroveId.sol`）
- **シグネチャ**: 旧 `type TroveId is uint256` ＋ global operator/述語 `==` / `!=` / `isEndOfList` / `isNotEndOfList`
- **目的**: Trove 識別子（uint256）の型安全ラッパー。終端判定述語を備える。
- **権限**: なし（pure）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**: Deprecated。現行 production コントラクトは Trove ID を全域で素の `uint256` として受け渡し、`TroveId` 型ヘルパーを参照しない。
- **revert / 早期 return**: なし。
- **発火イベント**: なし。
- **設計上のポイント**:
  - fresh deploy / audit surface 最小化方針により、未参照の production helper `contracts/src/Types/TroveId.sol` は `src` から削除済み。`SortedTroves` の fuzz test だけが型付き helper を必要とするため、同等の型・述語は test source 内に閉じる。
  - Trove ID 値の導出は BorrowerOperations の開設処理で `uint256(keccak256(abi.encode(msg.sender, _owner, _ownerIndex)))`（規範は CORE-BO。`msg.sender` を含むため (owner, ownerIndex) だけでは定まらない点に注意）。256bit ハッシュ値のため `0`（= ルートノード予約値）との衝突確率は無視できる。
- **Verification**: unit（`SortedTroves` test-local helper）/ static（production `src` に `Types/TroveId.sol` が存在しない）

#### CORE-LIB-FR-014: BatchId 型 🔵
- **Type**: Functional ｜ **Source**: base 実装（Types/BatchId.sol）
- **シグネチャ**: `type BatchId is address` ＋ global operator/述語 `==` / `!=` / `isZero` / `isNotZero`
- **目的**: バッチ識別子（= batch manager のアドレス）の型安全ラッパー。「バッチ無所属」（`BATCH_ID_ZERO`）の判定述語を備える。
- **権限**: なし（pure）。
- **事前条件（Checks）**: なし。
- **動作（Effects）**: `==` / `!=` は unwrap 値の比較。`isZero(x)` は `x == BATCH_ID_ZERO`、`isNotZero` はその否定。
- **revert / 早期 return**: なし。
- **発火イベント**: なし。
- **設計上のポイント**: TroveId と異なり production で実使用される: SortedTroves のノード（`nodes[*].batchId`）・バッチ連結リスト（`batches` mapping のキー）、ISortedTroves のシグネチャ、MultiTroveGetter が参照（規範は CORE-ST / CORE-MTG）。
- **Verification**: parity

#### CORE-LIB-FR-015: TroveChange 構造体（操作差分の受け渡し）🔵
- **Type**: Functional ｜ **Source**: base 実装（Types/TroveChange.sol）/ ActivePool の集計会計
- **シグネチャ**: `struct TroveChange`（uint256 × 12 フィールド、memory/calldata 渡し）
- **目的**: 1 回の操作（開設・調整・close・清算・redemption・バッチ操作）が Trove に与える変化量を**符号なしの増減ペア**で表現し、ActivePool の集計会計（`mintAggInterestAndAccountForTroveChange` / `mintBatchManagementFeeAndAccountForChange` / `getNewApproxAvgInterestRateFromTroveChange`。規範は CORE-AP）へ受け渡す中核型。生成側は BorrowerOperations・TroveManager。
- **権限**: なし（データ型）。
- **事前条件（Checks）**: なし（型自体は検証を持たない。利用側の規範参照）。
- **動作（Effects）**: 全フィールドの意味と集計会計上の役割:

| フィールド | 意味 | 集計会計上の役割（CORE-AP） |
| --- | --- | --- |
| `appliedRedistJpydfDebtGain` | この操作で Trove に適用（確定）した再分配由来の負債ゲイン | `aggRecordedDebt` に加算（DefaultPool → ActivePool への負債付け替えと対） |
| `appliedRedistCollGain` | 同・再分配由来の担保ゲイン | DefaultPool → ActivePool の担保移動量（TroveManager `_movePendingTroveRewardsToActivePool`） |
| `collIncrease` / `collDecrease` | 操作による担保の増加 / 減少（符号なし 2 本） | 担保トークン（dToken。[dToken.md](./dToken.md)）の pull / send 量の決定（CORE-BO / CORE-TM） |
| `debtIncrease` / `debtDecrease` | 操作による負債の発行 / 返済（符号なし 2 本） | `aggRecordedDebt` へ加算 / 減算 |
| `newWeightedRecordedDebt` | 操作**後**の `recordedDebt × annualInterestRate`（1e36 スケール） | `aggWeightedDebtSum` へ加算（旧値の減算と対） |
| `oldWeightedRecordedDebt` | 操作**前**の同値 | `aggWeightedDebtSum` から減算 |
| `upfrontFee` | 操作で課された前払い利息（7 日分。CORE-BO） | `aggRecordedDebt` に加算し、その場で SP / interestRouter へ mint（利息と同じ分配） |
| `batchAccruedManagementFee` | バッチの未収運用報酬のうち本操作で確定（mint）される分 | `aggRecordedDebt` に加算・pending バケット `aggBatchManagementFees` から控除・batch manager へ mint |
| `newWeightedRecordedBatchManagementFee` | 操作**後**の `recordedDebt × annualManagementFee` | `aggWeightedBatchManagementFeeSum` へ加算 |
| `oldWeightedRecordedBatchManagementFee` | 操作**前**の同値 | `aggWeightedBatchManagementFeeSum` から減算 |

- **revert / 早期 return**: なし（型）。
- **発火イベント**: なし。
- **設計上のポイント**:
  - 増減を符号なし 2 フィールドで持つのは signed int との変換を避けるため（返済操作では再分配ゲインと返済額の大小により正味が正にも負にもなり得る、との base コメント）。
  - **Trove 個別の accrued interest は含まれない**: 個別利息は集計側（pending aggregate interest）で別途計上されるため、TroveChange は「発行/返済 ＋ 適用再分配ゲイン」のみを運ぶ。new/oldWeightedRecordedDebt の差し替えが将来利息の発生レートを更新する。
  - 平均利率見積もり（`getNewApproxAvgInterestRateFromTroveChange`）は `upfrontFee == 0` を assert する（fee ↔ 平均利率の循環参照の単純化。CORE-AP）。
- **Verification**: parity / invariant=CORE-SYS-INV-002

#### CORE-LIB-FR-016: LatestTroveData 構造体（Trove 最新状態スナップショット）🔵
- **Type**: Functional ｜ **Source**: base 実装（Types/LatestTroveData.sol）/ TroveManager `_getLatestTroveData`
- **シグネチャ**: `struct LatestTroveData`（uint256 × 10 フィールド）
- **目的**: 未適用の再分配ゲイン・未収利息・バッチ按分をすべて織り込んだ Trove の「いま時点」の全量ビュー。算出規範は CORE-TM（`getLatestTroveData` / `_getLatestTroveDataFromBatch`）。BO の調整検証・清算・redemption・view 系の共通入力。
- **権限**: なし（データ型）。
- **動作（Effects）**: 全フィールドの意味（非バッチ Trove ／ バッチ所属 Trove での算出差）:

| フィールド | 意味 | 算出（非バッチ） | 算出（バッチ所属） |
| --- | --- | --- | --- |
| `entireDebt` | 全負債 | `recordedDebt + redistJpydfDebtGain + accruedInterest` | 左記 ＋ `accruedBatchManagementFee` |
| `entireColl` | 全担保 | `Troves[id].coll + redistCollGain` | 同左 |
| `redistJpydfDebtGain` | 未適用の再分配負債ゲイン | `stake × (L_jpydfDebt − snapshot) / 1e18` | 同左（Trove 単位） |
| `redistCollGain` | 未適用の再分配担保ゲイン | `stake × (L_coll − snapshot) / 1e18` | 同左（Trove 単位） |
| `accruedInterest` | 未収利息 | `_calcInterest(weightedRecordedDebt, 経過)` | バッチ未収利息の debt shares 按分 |
| `recordedDebt` | 記帳負債 | `Troves[id].debt` | `batch.recordedDebt × batchDebtShares / totalDebtShares` |
| `annualInterestRate` | 年利 | Trove 個別値 | バッチの率 |
| `weightedRecordedDebt` | `recordedDebt × annualInterestRate` | 同式 | 同式（バッチ率） |
| `accruedBatchManagementFee` | 未収バッチ運用報酬（Trove 按分） | 0（フィールド未設定） | バッチ未収報酬の shares 按分 |
| `lastInterestRateAdjTime` | 利率の最終調整時刻 | Trove 個別値 | `max(batch, trove)` |

- **設計上のポイント**: バッチの entire 値を Trove へ按分する際、再分配ゲインだけは debt shares 比例にできない（再分配は担保 stake 比例）ため Trove 単位で別計算する（base コメント）。`totalDebtShares == 0` のバッチでは按分系フィールドは 0 のまま。
- **Verification**: parity / unit（バッチ・非バッチの一致性）

#### CORE-LIB-FR-017: LatestBatchData 構造体（バッチ最新状態スナップショット）🔵
- **Type**: Functional ｜ **Source**: base 実装（Types/LatestBatchData.sol）/ TroveManager `_getLatestBatchData`
- **シグネチャ**: `struct LatestBatchData`（uint256 × 12 フィールド）
- **目的**: バッチ（batch manager 単位の共同利率管理）の「いま時点」の全量ビュー。Trove 按分（CORE-LIB-FR-016）とバッチ操作検証の共通入力。算出規範は CORE-TM（`getLatestBatchData`）。
- **権限**: なし（データ型）。
- **動作（Effects）**: 全フィールドの意味:

| フィールド | 意味 |
| --- | --- |
| `totalDebtShares` | バッチ債務シェア総量（Trove への按分の分母。`MAX_BATCH_SHARES_RATIO` で比率上限を検証＝CORE-TM/CORE-BO） |
| `entireDebtWithoutRedistribution` | 再分配ゲインを**除く**全負債 = `recordedDebt + accruedInterest + accruedManagementFee`（再分配は Trove 単位のためバッチ集計に含めない） |
| `entireCollWithoutRedistribution` | 再分配ゲインを除く全担保 = `batch.coll` |
| `accruedInterest` | バッチ未収利息 = `_calcInterest(weightedRecordedDebt, lastDebtUpdateTime からの経過)` |
| `recordedDebt` | バッチ記帳負債 = `batch.debt` |
| `annualInterestRate` | バッチ年利 |
| `weightedRecordedDebt` | `recordedDebt × annualInterestRate` |
| `annualManagementFee` | バッチ運用報酬の年率（上限 `MAX_ANNUAL_BATCH_MANAGEMENT_FEE`） |
| `accruedManagementFee` | 未収運用報酬 = `_calcInterest(weightedRecordedBatchManagementFee, 同経過)` |
| `weightedRecordedBatchManagementFee` | `recordedDebt × annualManagementFee` |
| `lastDebtUpdateTime` | 負債の最終更新時刻（未収分の起点） |
| `lastInterestRateAdjTime` | 利率の最終調整時刻（クールダウン判定の起点） |

- **Verification**: parity / unit


---

## 7. 状態変数・会計モデル

> コントラクトごとの全状態変数（immutable / constant / storage。internal 含む）と会計上の役割。**コアの会計恒等式**（コントラクト横断）は §8.1 を参照。
>
> **定数の値の正本**: `base` から無改変で継承する定数（`ETH_GAS_COMPENSATION` / `SP_YIELD_SPLIT` / `MIN_JPYDF_IN_SP` / `REDEMPTION_FEE_FLOOR` / `INITIAL_BASE_RATE` / `REDEMPTION_MINUTE_DECAY_FACTOR` / `MAX_BATCH_SHARES_RATIO` / `MIN_ANNUAL_INTEREST_RATE` 等）と`MIN_DEBT`（CORE-MOD-002）の値は`Constants.sol`を正とし、本節末尾の定数表に掲載する。[Parameters.md](../../../Parameters.md) はDF branch CR / penaltyと`PRM-LIQ-KEEPER`のDay1値を保持し、`base`継承定数は載せない。本文中で`base`継承定数に「値は §7」とあるのはこの定数表を指す。


### BorrowerOperations の状態変数

継承順（C3 線形化: LiquityBase → AddRemoveManagers → BorrowerOperations）・コードの宣言順。

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `activePool` | `IActivePool` public（LiquityBase 継承） | constructor（AddressesRegistry） | ブランチの ActivePool。集計・担保保管先。規定は LIB 担当 |
| `defaultPool` | `IDefaultPool` internal（LiquityBase 継承） | constructor（同上） | 再分配分の coll/debt 保管。規定は LIB 担当 |
| `priceFeed` | `IPriceFeed` internal（LiquityBase 継承） | constructor（同上） | 価格取得先（DF 構成では PriceFeedProxy。[Oracle.md](./Oracle.md)） |
| `troveNFT` | `ITroveNFT` internal immutable（AddRemoveManagers 継承） | constructor（同上） | Trove 所有者（owner）の判定基準。`ownerOf(troveId)` |
| `addManagerOf` | `mapping(uint256 => address)` public（AddRemoveManagers 継承） | openTrove / setAddManager で設定 | Trove への「入金系」操作（担保追加・返済）の委任先。**ゼロのときは誰でも入金系操作が可能**（既定）。owner 自身を設定すると owner 限定に絞れる |
| `removeManagerReceiverOf` | `mapping(uint256 => RemoveManagerReceiver{manager,receiver})` public（AddRemoveManagers 継承） | openTrove / setRemoveManager(WithReceiver) で設定 | Trove からの「出金系」操作（担保引出・借入・閉鎖）の委任先と、引き出した資金の受取先。**ゼロのときは owner 以外誰も出金系操作不可**（既定）。receiver がゼロなら owner が受取先 |
| `collToken` | `IERC20` internal immutable | constructor（AddressesRegistry） | このブランチの担保トークン（= dToken。[dToken.md](./dToken.md)） |
| `troveManager` | `ITroveManager` internal | constructor で設定（以後変更経路なし） | 状態更新フックの呼び先・呼出元検証（`onLiquidateTrove`） |
| `gasPoolAddress` | `address` internal | constructor（同上） | WETH ガス補償（`ETH_GAS_COMPENSATION`）の保管先 |
| `collSurplusPool` | `ICollSurplusPool` internal | constructor（同上） | 清算余剰担保の保管先（`claimCollateral` の委譲先） |
| `jpydfToken` | `IJpydfToken` internal | constructor（同上） | JPYdf の mint/burn 先 |
| `sortedTroves` | `ISortedTroves` internal | constructor（同上） | 金利順リストへの挿入・削除・再挿入 |
| `WETH` | `IWETH` internal immutable | constructor（同上） | 清算ガス補償としてロックする WETH |
| `CCR` | `uint256` public immutable | constructor（AddressesRegistry。ブランチ別値は [Parameters.md](../../../Parameters.md)） | クリティカル閾値。TCR < CCR で借入等を制限 |
| `SCR` | `uint256` public immutable | constructor（同上） | shutdown 閾値。TCR < SCR で `shutdown()` 可能 |
| `hasBeenShutDown` | `bool` public | `false` → `_applyShutdown()` で `true` | shutdown 済みフラグ。一度 true になると戻す経路はない |
| `MCR` | `uint256` public immutable | constructor（同上） | 個別 Trove の最低担保率 |
| `BCR` | `uint256` public immutable | constructor（同上） | batch 所属 Trove に課す MCR 上乗せバッファ |
| `interestIndividualDelegateOf` | `mapping(uint256 => InterestIndividualDelegate{account,minInterestRate,maxInterestRate,minInterestRateChangePeriod})` private | setInterestIndividualDelegate で設定 | Trove 単位の金利変更委任（債務・担保は触れない）。照会は `getInterestIndividualDelegateOf` |
| `interestBatchManagerOf` | `mapping(uint256 => address)` public | openTroveAndJoin… / setInterestBatchManager で設定、close/remove/kick/清算で消去 | Trove の所属 batch manager（ゼロ = 非所属） |
| `interestBatchManagers` | `mapping(address => InterestBatchManager{minInterestRate,maxInterestRate,minInterestRateChangePeriod})` private | registerBatchManager で設定（以後不変・削除不能） | batch manager の登録レコード。`maxInterestRate > 0` を「登録済み」の判定に使う。照会は `getInterestBatchManager` / `checkBatchManagerExists` |


### TroveManager の状態変数

宣言順（LiquityBase 継承分を先頭に記載。LiquityBase 自体の規定は CORE-LIB 節）。

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `activePool` | `IActivePool` public（継承） | constructor（AddressesRegistry から） | 利息集計・担保送付の窓口 |
| `defaultPool` | `IDefaultPool` internal（継承） | constructor | redistribution された pending 債務・担保の保管先 |
| `priceFeed` | `IPriceFeed` internal（継承） | constructor | 価格取得先（PriceFeedProxy、[Oracle.md](./Oracle.md)） |
| `troveNFT` | `ITroveNFT` public | constructor | Trove 所有権 NFT。開設で mint・閉鎖/清算で burn |
| `borrowerOperations` | `IBorrowerOperations` public | constructor | `on*` の唯一の呼出元。清算時に `onLiquidateTrove` を逆向きに呼ぶ |
| `stabilityPool` | `IStabilityPool` public | constructor | 清算 offset 先 |
| `gasPoolAddress` | `address` internal | constructor | WETH ガス補償の保管元（CORE-GP 節） |
| `collSurplusPool` | `ICollSurplusPool` internal | constructor | 清算余剰担保の保管先 |
| `jpydfToken` | `IJpydfToken` internal | constructor | `urgentRedemption` での burn・残高検査に使用 |
| `sortedTroves` | `ISortedTroves` public | constructor | 年利順の双方向リスト。Redemption 走査・閉鎖時の除去に使用 |
| `collateralRegistry` | `ICollateralRegistry` internal | constructor | `redeemCollateral` の唯一の呼出元 |
| `WETH` | `IWETH` internal immutable | constructor | ガス補償（`ETH_GAS_COMPENSATION`）の支払いトークン |
| `CCR` | `uint256` public immutable | constructor（AddressesRegistry から） | ブランチ Critical 比率。値は [Parameters.md](../../../Parameters.md) |
| `MCR` | `uint256` internal immutable | constructor | 個別 Trove の清算閾値。値は [Parameters.md](../../../Parameters.md) |
| `SCR` | `uint256` internal immutable | constructor | shutdown 閾値（redeemability 判定にも使用）。値は [Parameters.md](../../../Parameters.md) |
| `LIQUIDATION_PENALTY_SP` | `uint256` internal immutable | constructor | SP offset 分の清算ペナルティ率。値は [Parameters.md](../../../Parameters.md) |
| `LIQUIDATION_PENALTY_REDISTRIBUTION` | `uint256` internal immutable | constructor | redistribution 分の清算ペナルティ率。値は [Parameters.md](../../../Parameters.md) |
| `Troves` | `mapping(uint256 => Trove)` public | 各 `on*` / 清算 / Redemption | Trove 台帳（下表） |
| `batches` | `mapping(address => Batch)` internal | batch 系 `on*` / 清算 / Redemption | Batch 台帳（下表）。外部読み出しは `getLatestBatchData` 経由のみ |
| `totalStakes` | `uint256` internal | 開設/調整/閉鎖/清算/Redemption で増減 | 全 active・zombie Trove の stake 合計。redistribution の分母 |
| `totalStakesSnapshot` | `uint256` internal | 清算直後に更新 | 直近清算直後の `totalStakes`。新規 stake 算定の分子係数 |
| `totalCollateralSnapshot` | `uint256` internal | 清算直後に更新 | 直近清算直後の総担保（AP + DP、ガス補償除く）。新規 stake 算定の分母 |
| `L_coll` | `uint256` internal | `_redistributeDebtAndColl` で単調増加 | stake 1 単位あたり累計 redistribution 担保。Trove の取り分は `stake × (L_coll − snapshot.coll) / 1e18` |
| `L_jpydfDebt` | `uint256` internal | 同上 | stake 1 単位あたり累計 redistribution 債務。取り分は `stake × (L_jpydfDebt − snapshot.jpydfDebt) / 1e18` |
| `rewardSnapshots` | `mapping(uint256 => RewardSnapshot)` public | Trove 状態更新の都度 | Trove ごとの `L_coll` / `L_jpydfDebt` 取得基準点。差分が未適用 redistribution gain |
| `TroveIds` | `uint256[]` internal | 開設で push・閉鎖/清算で swap-and-pop | 全 active・zombie Trove の ID 配列（off-chain ヒント計算用） |
| `batchIds` | `address[]` public | `onRegisterBatchManager` で push（削除なし） | 全 batch manager の列挙用配列 |
| `lastZombieTroveId` | `uint256` public | Redemption / 復帰 / 閉鎖で更新 | 部分 redeem で zombie 化した Trove のポインタ。次回 Redemption が最優先で消化（0 = なし） |
| `lastCollError_Redistribution` | `uint256` internal | `_redistributeDebtAndColl` | redistribution 担保の床除算誤差の繰越（error feedback） |
| `lastJpydfDebtError_Redistribution` | `uint256` internal | 同上 | redistribution 債務の床除算誤差の繰越 |
| `shutdownTime` | `uint256` public | `shutdown()` で `block.timestamp` | ブランチ shutdown 時刻。0 = 未 shutdown。利息凍結・urgentRedemption 解禁の基準 |

**Trove 構造体**（`Troves[troveId]`）

| フィールド | 型 | 意味 |
| --- | --- | --- |
| `debt` | `uint256` | 記録上の債務（直近更新時点の利息込み元本）。**batch 所属 Trove では 0**（債務は batch shares で管理） |
| `coll` | `uint256` | 記録上の担保（未適用 redistribution gain を含まない） |
| `stake` | `uint256` | redistribution 配分用の stake（CORE-TM-FR-003 の規則で担保から導出） |
| `status` | `Status` (uint8) | `0 nonExistent / 1 active / 2 closedByOwner / 3 closedByLiquidation / 4 zombie` |
| `arrayIndex` | `uint64` | `TroveIds` 配列内の自身の位置 |
| `lastDebtUpdateTime` | `uint64` | `debt` を最後に確定した時刻（利息発生の起点）。batch 所属では未使用（batch 側で管理） |
| `lastInterestRateAdjTime` | `uint64` | 金利を最後に変更した時刻（BO の premature adjustment fee 判定に使用） |
| `annualInterestRate` | `uint256` | 個別年利。**batch 所属 Trove では 0**（batch 金利が適用） |
| `interestBatchManager` | `address` | 所属 batch manager（`address(0)` = 非所属） |
| `batchDebtShares` | `uint256` | batch 債務に対する持分 shares |

**Batch 構造体**（`batches[batchManager]`）— batch は「1 つの大きな Trove」として扱われ、債務は shares 按分・担保は Trove ごとに保持しつつ合計値も記録する。

| フィールド | 型 | 意味 |
| --- | --- | --- |
| `debt` | `uint256` | batch の記録上債務（利息・管理fee適用済み元本） |
| `coll` | `uint256` | batch 内 Trove の担保合計 |
| `arrayIndex` | `uint64` | `batchIds` 配列内の位置 |
| `lastDebtUpdateTime` | `uint64` | batch 債務の最終確定時刻（利息・管理feeの起点） |
| `lastInterestRateAdjTime` | `uint64` | batch 金利の最終変更時刻 |
| `annualInterestRate` | `uint256` | batch 年利（所属 Trove 全員に適用） |
| `annualManagementFee` | `uint256` | batch manager の年間管理fee率 |
| `totalDebtShares` | `uint256` | 発行済み debt shares 総量 |

**RewardSnapshot 構造体**（`rewardSnapshots[troveId]`）: `coll`（取得時 `L_coll`）/ `jpydfDebt`（取得時 `L_jpydfDebt`）。


### StabilityPool / DFStabilityPool の状態変数

構造体: `Deposit { uint256 initialValue }`（預金者の最終操作時点の預金額）/ `Snapshots { uint256 S; uint256 P; uint256 B; uint256 scale }`（預入時点の累積値スナップショット）。

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `activePool` | `IActivePool` public（LiquityBase 継承・storage） | constructor（AddressesRegistry から） | 利息 mint 依頼（`mintAggInterest`）先・清算担保の供給元・`triggerJpydfRewards` の唯一の許可呼出元 |
| `defaultPool` | `IDefaultPool` internal（LiquityBase 継承・storage） | constructor | `getEntireBranchColl/Debt` の合算にのみ使用 |
| `priceFeed` | `IPriceFeed` internal（LiquityBase 継承・storage） | constructor | **SP では未使用**（LiquityBase の TCR 系内部関数も SP からは呼ばれない）。PriceFeed 実体は PriceFeedProxy（[Oracle.md](./Oracle.md)） |
| `NAME` | `string` public constant | `"StabilityPool"`（**DFStabilityPool でも同値**） | 識別用名称 |
| `collToken` | `IERC20` public immutable | constructor（registry の `collToken()`） | branch の担保トークン＝dToken（[dToken.md](./dToken.md)）。ゲイン払出の transfer 先トークン |
| `troveManager` | `ITroveManager` public immutable | constructor | `offset` の唯一の許可呼出元 |
| `jpydfToken` | `IJpydfToken` public immutable | constructor | 預入受領（`sendToPool`）・払出（`returnFromPool`）・オフセット焼却（`burn`） |
| `collBalance` | `uint256` internal | 0 / `offset` で増・ゲイン送付で減 | SP が保有すべき担保の内部トラッカー。直接 transfer や self-destruct 受領を会計から除外する |
| `totalJpydfDeposits` | `uint256` internal | 0 / 預入・kept yield 複利で増、引出・オフセットで減 | プール預金総額。`P`/`S`/`B` 更新の分母 |
| `yieldGainsOwed` | `uint256` internal | 0 / `_updateYieldRewardsSum` で増・ゲイン精算で減 | `B` に配分計上済みで未払いの利回り総額。`getDepositorYieldGain` の上限クランプに使用 |
| `yieldGainsPending` | `uint256` internal | 0 / 閾値未満時の受領で増・閾値回復時に 0 へ | `totalJpydfDeposits < MIN_JPYDF_IN_SP` の間に受領し、まだ `B` に配分していない利回り。JPYdf 実体は SP 残高に滞留 |
| `deposits` | `mapping(address => Deposit)` public | `_updateDepositAndSnapshots` | 預金者ごとの預金額（最終操作時点値。現在値は CORE-SP-FR-011 で導出） |
| `depositSnapshots` | `mapping(address => Snapshots)` public | `_updateDepositAndSnapshots`（預金 0 化で delete） | 預金者の `P`/`S`/`B`/`scale` スナップショット |
| `stashedColl` | `mapping(address => uint256)` public | `_updateDepositAndSnapshots` / `claimAllCollGains` | `_doClaim=false` で受取らず留保した担保ゲインの累積 |
| `P` | `uint256` public | `P_PRECISION`（宣言時） / `offset` で更新 | running product。預入時点比の預金減耗率を表す（36 桁精度） |
| `P_PRECISION` | `uint256` public constant | `1e36` | `P` の「1.0」表現 |
| `SCALE_FACTOR` | `uint256` public constant | `1e9` | scale 繰り上げ時に `P` に乗じる倍率。1 scale ＝ 1e9 分の 1 の減耗 |
| `MAX_SCALE_FACTOR_EXPONENT` | `uint256` public constant | `8` | `SCALE_FACTOR` をオーバーフローなく累乗できる最大指数（`1e9^8 = 1e72 < 2^256`、9 乗は不可）。これを超える scale 差の預金は 0 と評価 |
| `SCALE_SPAN` | `uint256` public constant | `2` | 未操作の預金がゲインを受け取り続けられる scale 跨ぎ数の上限 |
| `currentScale` | `uint256` public | 0 / `offset` の scale ループで +1 | `P` が `SCALE_FACTOR` 倍された累積回数 |
| `scaleToS` | `mapping(uint256 => uint256)` public | `offset` で加算 | scale 別の担保ゲイン累積和（P 加重: `+= P * coll / totalJpydfDeposits`） |
| `scaleToB` | `mapping(uint256 => uint256)` public | `_updateYieldRewardsSum` で加算 | scale 別の JPYdf 利回りゲイン累積和（同上） |
| `lastDepositBlock` 🟡 | `mapping(address => uint256)` public（**DFStabilityPool のみ**） | 0 / `provideToSP` で `block.number` | same-block 担保ゲイン claim・出金ガード用の最終預入ブロック番号（CORE-SP-FR-004、CORE-MOD-004（§2 DF 差分台帳）） |


### ActivePool の状態変数

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `NAME` | `string public constant` | `"ActivePool"` | コントラクト識別名 |
| `collToken` | `IERC20 public immutable` | コンストラクタ（`AddressesRegistry.collToken()`） | ブランチ担保トークン。jpydf では dToken（[dToken.md](./dToken.md)） |
| `borrowerOperationsAddress` | `address public immutable` | コンストラクタ（AddressesRegistry） | 呼出元制限・配線用 |
| `troveManagerAddress` | `address public immutable` | コンストラクタ（AddressesRegistry） | 呼出元制限・配線用 |
| `defaultPoolAddress` | `address public immutable` | コンストラクタ（AddressesRegistry） | redistribution 担保の移送先。コンストラクタで無限 approve |
| `jpydfToken` | `IJpydfToken public immutable` | コンストラクタ（AddressesRegistry） | 利息・batch フィーの mint 先トークン（JPYdf） |
| `interestRouter` | `IInterestRouter public immutable` | コンストラクタ（AddressesRegistry） | 集計利息の残余 25% の mint 先。`IInterestRouter` は関数を持たない空インターフェース（受け口は任意のアドレスでよい）。DF dToken wiring では `InterestRouterForwarder` に束縛し、recipient / owner を env と handover/verify で管理する（CORE-AP-TBD-001 は解決済み） |
| `stabilityPool` | `IJpydfRewardsReceiver public immutable` | コンストラクタ（AddressesRegistry） | SP 取り分 75% の mint 先＋`triggerJpydfRewards` 通知先。依存循環回避のため `IStabilityPool` ではなく `IJpydfRewardsReceiver` 型で保持 |
| `collBalance` | `uint256 internal` | 0 | **会計上の**担保残高。実トークン残高とは独立に増減を記帳（直接 transfer された担保は反映されない）。`getCollBalance()` で公開 |
| `aggRecordedDebt` | `uint256 public` | 0 | 集計記録負債（spec 中の "D"）。全アクティブ Trove の記録負債＋確定済み集計利息＋確定済み upfront fee＋適用済み batch 管理フィーの総和。Trove の負債が触られるたび、および集計利息 mint のたびに更新。redistribution 待ち負債（DefaultPool 側）は含まない |
| `aggWeightedDebtSum` | `uint256 public` | 0 | 各 Trove の記録負債 × 各自の選択年利率の総和（spec 中の "S"、1e18 スケール積）。個別 Trove 操作時に new/old 加重負債の差分で更新。ペンディング利息の線形計算の基礎 |
| `lastAggUpdateTime` | `uint256 public` | 0 | 集計利息を最後に確定（mint）した時刻。`_mintAggInterest` 実行のたびに `block.timestamp` へ更新 |
| `shutdownTime` | `uint256 public` | 0 | ブランチ shutdown 時刻。0 なら未 shutdown。一度設定されると（コア配線上）リセット経路なし。設定後は `calcPendingAggInterest()` が恒久的に 0 |
| `aggBatchManagementFees` | `uint256 public` | 0 | 確定（記帳）済みだが、まだいずれの batch の記録負債にも適用されていない集計 batch 管理フィー。適用時に `aggRecordedDebt` 側へ移動 |
| `aggWeightedBatchManagementFeeSum` | `uint256 public` | 0 | 各 batched Trove の記録負債 × 各 batch の年率管理フィーの総和。batched Trove 操作時に new/old の差分で更新 |
| `lastAggBatchManagementFeesUpdateTime` | `uint256 public` | 0 | batch 管理フィー集計を最後に確定した時刻 |


### DefaultPool の状態変数

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `NAME` | `string public constant` | `"DefaultPool"` | コントラクト識別名 |
| `collToken` | `IERC20 public immutable` | コンストラクタ（`AddressesRegistry.collToken()`） | ブランチ担保トークン（dToken、[dToken.md](./dToken.md)） |
| `troveManagerAddress` | `address public immutable` | コンストラクタ（AddressesRegistry） | 呼出元制限用 |
| `activePoolAddress` | `address public immutable` | コンストラクタ（AddressesRegistry） | 呼出元制限・担保移転の対向。コンストラクタで無限 approve |
| `collBalance` | `uint256 internal` | 0 | 会計上のペンディング担保残高（redistribution 済み・未適用分の総和）。`getCollBalance()` で公開 |
| `JpydfDebt` | `uint256 internal` | 0 | redistribution 済み・未適用の JPYdf 負債総和（変数名の大文字 B は base 由来の表記）。`getJpydfDebt()` で公開 |


### CollSurplusPool の状態変数

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `NAME` | `string public constant` | `"CollSurplusPool"` | コントラクト識別名 |
| `collToken` | `IERC20 public immutable` | コンストラクタ（`AddressesRegistry.collToken()`） | ブランチ担保トークン（dToken、[dToken.md](./dToken.md)） |
| `borrowerOperationsAddress` | `address public immutable` | コンストラクタ（AddressesRegistry） | claimColl の呼出元制限用 |
| `troveManagerAddress` | `address public immutable` | コンストラクタ（AddressesRegistry） | accountSurplus の呼出元制限用 |
| `collBalance` | `uint256 internal` | 0 | 会計上の余剰担保総額（= 全アカウントの balances 合計）。`getCollBalance()` で公開 |
| `balances` | `mapping(address => uint256) internal` | 空 | アカウント（清算時点の Trove owner）別の請求可能担保残高。`getCollateral()` で公開 |


### GasPool の状態変数

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| （なし。ストレージ未使用。WETH / BorrowerOperations / TroveManager はコンストラクタ内ローカル変数） | — | — | — |


### SortedTroves の状態変数

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `ROOT_NODE_ID` | `uint256 constant`（ファイルレベル） | `0` | head/tail を保持する番兵（root）ノードの ID。`getNext()`/`getPrev()` 走査はこの ID で終端 |
| `NAME` | `string public constant` | `"SortedTroves"` | コントラクト名 |
| `UNINITIALIZED_ID` | `uint256 constant`（internal） | `0` | 「未初期化 ID」を表す documentation 用定数（値は ROOT_NODE_ID と同じ 0） |
| `BAD_HINT` | `uint256 constant`（internal） | `0` | 「無効 hint」を表す documentation 用定数（同上） |
| `borrowerOperationsAddress` | `address public immutable` | constructor（`AddressesRegistry.borrowerOperations()`） | 挿入・再挿入系の唯一の呼出元。除去系では TM と並ぶ呼出元 |
| `troveManager` | `ITroveManager public immutable` | constructor（`AddressesRegistry.troveManager()`） | 順序判定の金利参照先（`getTroveAnnualInterestRate`）。除去系の呼出元 |
| `size` | `uint256 public` | `0` | 現在のノード数（active な非 zombie Trove 数と一致） |
| `nodes` | `mapping(uint256 => Node) public` | constructor で `nodes[0]` を自己ループ初期化 | 各ノードの前後リンク・batchId・存在フラグ。`nodes[ROOT_NODE_ID]` は head（`nextId`）と tail（`prevId`）を保持する番兵で、空リスト・先頭/末尾・単一要素の特別扱いを不要にする |
| `batches` | `mapping(BatchId => Batch) public` | — | batch manager アドレス → slice の `head`/`tail` |

構造体（ISortedTroves 規定ではなく実装内定義）:

- `Node { uint256 nextId（次＝より低金利側）, uint256 prevId（前＝より高金利側）, BatchId batchId（非 batch ノードは 0）, bool exists }`
- `Batch { uint256 head, uint256 tail }`
- `Position { uint256 prevId, uint256 nextId }`（探索中の現在位置を持ち回る in-memory 構造体）


### TroveNFT の状態変数

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `troveManager` | `ITroveManager public immutable` | constructor（`AddressesRegistry.troveManager()`） | mint/burn の唯一の呼出元。tokenURI の Trove データ参照先 |
| `collToken` | `IERC20Metadata internal immutable` | constructor（`AddressesRegistry.collToken()`） | ブランチ担保トークン（jpydf では dToken）。name/symbol 導出とメタデータ表示に使用。**getter なし（internal）** |
| `jpydfToken` | `IJpydfToken internal immutable` | constructor（`AddressesRegistry.jpydfToken()`） | メタデータの Debt Token 欄に表示するアドレス。**getter なし（internal）** |
| `metadataNFT` | `IMetadataNFT public immutable` | constructor（`AddressesRegistry.metadataNFT()`） | tokenURI 描画の委譲先（差替不可） |
| （継承: OZ v4.9 `ERC721`） | `string private _name` / `string private _symbol` / `mapping _owners` / `mapping _balances` / `mapping _tokenApprovals` / `mapping _operatorApprovals` | constructor / 各 ERC-721 操作 | ERC-721 標準の所有・承認台帳 |

MetadataNFT（別コントラクト・branch 間共有可能な描画専用）:

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味 |
| --- | --- | --- | --- |
| `assetReader` | `FixedAssetReader public immutable` | constructor | SSTORE2 に格納された固定アセット（Geist フォント・JPYdf ロゴ・登録済み collateral ロゴ等）の読出し器 |


### JpydfToken の状態変数

→ 規範は [JpydfToken.md](./JpydfToken.md) §7。

### CollateralRegistry の状態変数

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `totalCollaterals` | `uint256 public immutable` | constructor（`_tokens.length`、1〜10） | branch 数。ループ上限 |
| `token0` 〜 `token9` | `IERC20Metadata internal immutable` × 10 | constructor（未使用 slot は `address(0)`） | 各 branch の担保トークン（DF では dToken）。Solidity が immutable 配列を持てないため 10 本の個別変数で表現 |
| `troveManager0` 〜 `troveManager9` | `ITroveManager internal immutable` × 10 | constructor（未使用 slot は `address(0)`） | 各 branch の TroveManager。redemption の実行先 |
| `jpydfToken` | `IJpydfToken public immutable` | constructor | redemption で burn する JPYdf |
| `baseRate` | `uint256 public` | constructor で `INITIAL_BASE_RATE`（値は §7）、以後 `redeemCollateral` でのみ更新 | system-wide の redemption 基礎レート（全 branch 共通） |
| `lastFeeOperationTime` | `uint256 public` | 宣言時初期化子 `block.timestamp`（=デプロイ時刻） | baseRate decay の基準時刻。丸め分単位でのみ前進 |


### AddressesRegistry の状態変数

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `collToken` | `IERC20Metadata public` | `setAddresses` で 1 度 | branch の担保トークン（DF では dToken） |
| `borrowerOperations` | `IBorrowerOperations public` | 同上 | branch BO |
| `troveManager` | `ITroveManager public` | 同上 | branch TM |
| `troveNFT` | `ITroveNFT public` | 同上 | branch TroveNFT |
| `metadataNFT` | `IMetadataNFT public` | 同上 | TroveNFT メタデータ |
| `stabilityPool` | `IStabilityPool public` | 同上 | branch SP |
| `priceFeed` | `IPriceFeed public` | 同上 | branch PriceFeed（[Oracle.md](./Oracle.md)） |
| `activePool` | `IActivePool public` | 同上 | branch AP |
| `defaultPool` | `IDefaultPool public` | 同上 | branch DP |
| `gasPoolAddress` | `address public` | 同上 | branch GasPool |
| `collSurplusPool` | `ICollSurplusPool public` | 同上 | branch CollSurplusPool |
| `sortedTroves` | `ISortedTroves public` | 同上 | branch SortedTroves |
| `interestRouter` | `IInterestRouter public` | 同上 | 利息残余（非 SP 分）の受け手 |
| `hintHelpers` | `IHintHelpers public` | 同上 | 共有 helper |
| `multiTroveGetter` | `IMultiTroveGetter public` | 同上 | 共有 helper |
| `collateralRegistry` | `ICollateralRegistry public` | 同上 | 共有 CR |
| `jpydfToken` | `IJpydfToken public` | 同上 | 共有 JPYdf |
| `WETH` | `IWETH public` | 同上 | ガス補償用 WETH |
| `CCR` | `uint256 public immutable` | constructor（検証つき） | TCR がこれを下回ると借入操作に制限（値は [Parameters.md](../../../Parameters.md)） |
| `SCR` | `uint256 public immutable` | constructor（検証つき） | TCR がこれを下回ると branch shutdown 可能 |
| `MCR` | `uint256 public immutable` | constructor（検証つき） | Trove 個別の最小担保率 |
| `BCR` | `uint256 public immutable` | constructor（検証つき） | batch 参加・batch 内調整時に MCR へ上乗せするバッファ |
| `LIQUIDATION_PENALTY_SP` | `uint256 public immutable` | constructor（検証つき） | SP offset 清算時のペナルティ率 |
| `LIQUIDATION_PENALTY_REDISTRIBUTION` | `uint256 public immutable` | constructor（検証つき） | 再分配清算時のペナルティ率 |
| （継承: Ownable）`_owner` | `address private` | constructor で `_owner` 引数、`setAddresses` 内の `_renounceOwnership()` で `address(0)` | デプロイ配線期間のみ有効な管理者 |


### HintHelpers の状態変数

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `NAME` | `string public constant` | `"HintHelpers"` | コントラクト識別子 |
| `collateralRegistry` | `ICollateralRegistry public immutable` | constructor | 全ブランチの入口。`getTroveManager(_collIndex)` でブランチ解決 |


### MultiTroveGetter の状態変数

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `collateralRegistry` | `ICollateralRegistry public immutable` | constructor | ブランチ解決の入口 |


### DebtInFrontHelper の状態変数

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `collateralRegistry` | `ICollateralRegistry public immutable` | constructor | ブランチ解決の入口 |
| `hintHelpers` | `IHintHelpers public immutable` | constructor | `getApproxHint` の委譲先（走査開始点の高速化） |


### RedemptionHelper の状態変数

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `numBranches` | `uint256 public immutable` | constructor（`_addresses.length`） | ブランチ数。CR の `totalCollaterals()` と一致することを constructor で検証 |
| `collateralRegistry` | `ICollateralRegistry public immutable` | constructor | 償還の実行先・ブランチ解決の入口 |
| `jpydfToken` | `IJpydfToken public immutable` | constructor（`collateralRegistry.jpydfToken()`） | 償還で焼却される JPYdf（JPYdf） |
| `addresses` | `IAddressesRegistry[] public`（storage） | constructor で push | ブランチ毎の AddressesRegistry。`troveManager` / `sortedTroves` / `priceFeed` の解決に使用。シミュレーションが off-chain 専用のため storage コストを許容（コード内コメント） |


### LiquidationCandidateGetter の状態変数

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `collateralRegistry` | `ICollateralRegistry public immutable` | constructor | ブランチ解決の入口 |


### Constants.sol の状態変数

すべて `constant`（宣言順）。「参照箇所」は production コード（`contracts/src/` 配下、テスト・スクリプト除く）における参照先。

**(a) upstream 由来定数（🟡 2 件を除き base と同値）**

| 定数 | 型 | 値 | 意味・会計上の役割 | 参照箇所 |
| --- | --- | --- | --- | --- |
| `DECIMAL_PRECISION` | uint256 | `1e18` | 18 桁固定小数のスケール基準。CR・利率・分配率等すべての比率計算の分母 | LiquityBase / LiquityMath / TroveManager / BorrowerOperations / ActivePool / CollateralRegistry / HintHelpers / RedemptionHelper / Zappers / PriceFeeds |
| `_100pct` | uint256 | `DECIMAL_PRECISION` | 100%（= 1e18） | TroveManager / RedemptionHelper |
| `_1pct` | uint256 | `DECIMAL_PRECISION / 100` | 1%（= 1e16）。％建て定数の導出基底 | Constants.sol 内の派生定数のみ |
| `ETH_GAS_COMPENSATION` | uint256 | `0.0375 ether` | Trove 開設時に GasPool へロックされる WETH 額（清算時に清算者へ支払う固定ガス補償）。**担保ブランチを問わず WETH 建て**（担保＝dToken でも補償は WETH。[dToken.md](./dToken.md) スコープ外） | BorrowerOperations / TroveManager / Zappers |
| `MIN_LIQUIDATION_PENALTY_SP` | uint256 | `5e16`（5%） | ブランチ毎 `LIQUIDATION_PENALTY_SP` の下限。AddressesRegistry constructor が検証（`SPPenaltyTooLow`） | AddressesRegistry |
| `MAX_LIQUIDATION_PENALTY_REDISTRIBUTION` | uint256 | `20e16`（20%) | ブランチ毎 `LIQUIDATION_PENALTY_REDISTRIBUTION` の上限。AddressesRegistry constructor が検証（`RedistPenaltyTooHigh`） | AddressesRegistry |
| `COLL_GAS_COMPENSATION_DIVISOR` | uint256 | `200` | 清算者への担保ガス補償率（担保の 1/200 = 0.5%） | TroveManager |
| `COLL_GAS_COMPENSATION_CAP` / `COLL_GAS_COMPENSATION_CAP_DWSTETH` 🟡 | uint256 | `1_000 ether` / `2 ether` | CORE-LIB-FR-003 / CORE-MOD-003 | TroveManager constructor / DeployLiquity2 |
| `MIN_DEBT` 🟡 | uint256 | base: `2000e18` → **DF: `300_000e18`** | Trove が維持すべき最小負債（JPYdf 建て entire debt）。CORE-LIB-FR-002 / CORE-MOD-002 | BorrowerOperations / TroveManager |
| `MIN_ANNUAL_INTEREST_RATE` | uint256 | `_1pct / 2`（0.5%） | Trove 年利の下限 | BorrowerOperations |
| `MAX_ANNUAL_INTEREST_RATE` | uint256 | 250% | Trove 年利の上限 | BorrowerOperations |
| `MAX_ANNUAL_BATCH_MANAGEMENT_FEE` | **uint128** | 10% | バッチ運用報酬（年率）の上限（batch manager 登録時に検証） | BorrowerOperations |
| `MIN_INTEREST_RATE_CHANGE_PERIOD` | **uint128** | `1 hours` | batch manager が宣言する利率変更間隔の下限（バッチ Trove のみに適用） | BorrowerOperations |
| `REDEMPTION_FEE_FLOOR` | uint256 | `_1pct / 2`（0.5%） | redemption 手数料率の下限 | CollateralRegistry |
| `MAX_BATCH_SHARES_RATIO` | uint256 | `1e9` | バッチの debt/shares 比の上限。share インフレ攻撃で比を吊り上げて以後の参加者の取り分を毀損する攻撃の遮断（上限到達には年率 10% 複利でも 217 年超を要する、とのコードコメント） | TroveManager / BorrowerOperations |
| `REDEMPTION_MINUTE_DECAY_FACTOR` | uint256 | `998076443575628800` | baseRate の毎分減衰係数（半減期 6 時間 = 360 分、`(1/2)^(1/360)`） | CollateralRegistry |
| `REDEMPTION_BETA` | uint256 | `1` | redemption による baseRate 上昇の除数（ホワイトペーパーの 1/ALPHA） | CollateralRegistry |
| `INITIAL_BASE_RATE` | uint256 | `_100pct`（100%） | デプロイ直後の baseRate 初期値。立ち上げ期の redemption を事実上抑止（深いデペグ時を除き不採算化） | CollateralRegistry |
| `URGENT_REDEMPTION_BONUS` | uint256 | `2e16`（2%） | ブランチ shutdown 後の urgent redemption に付く担保ボーナス | TroveManager |
| `ONE_MINUTE` | uint256 | `1 minutes` | 時間単位（baseRate 減衰の分単位換算） | CollateralRegistry |
| `ONE_YEAR` | uint256 | `365 days` | 年利→経過期間按分の分母 | LiquityBase / ActivePool / HintHelpers |
| `UPFRONT_INTEREST_PERIOD` | uint256 | `7 days` | 借入・早期利率変更時に前払いする利息の対象期間（平均利率 × 7 日分） | BorrowerOperations / HintHelpers |
| `INTEREST_RATE_ADJ_COOLDOWN` | uint256 | `7 days` | 利率調整のクールダウン。期間内の再調整は upfront fee 課金対象 | BorrowerOperations / HintHelpers |
| `SP_YIELD_SPLIT` | uint256 | 75% | 集計利息 mint 時の Stability Pool への分配率（残余は interestRouter 経由で LP へ） | ActivePool |
| `MIN_JPYDF_IN_SP` | uint256 | `1e18` | SP 総預金の下限（1 JPYdf）。これを割り込む引き出しを禁止し、空プール境界・初期化攻撃の端点を回避 | StabilityPool / DFStabilityPool / TroveManager |
**(b) DF 追記分: ブランチ別定数群（CORE-MOD-005。upstream 定数は不変）**

ブランチごとに 6 種の定数 `MCR_<BR>` / `CCR_<BR>` / `SCR_<BR>` / `BCR_<BR>` / `LIQUIDATION_PENALTY_SP_<BR>` / `LIQUIDATION_PENALTY_REDISTRIBUTION_<BR>`（`<BR>` は下表 suffix、全 8 ブランチ × 6 種 = 48 定数、すべて uint256 constant）。**確定値の正本は [Parameters.md](../../../Parameters.md)**（Constants.sol のコメント値と一致）であり、本書では再掲しない。詳細は CORE-LIB-FR-004。

| Branch | suffix `<BR>` | dToken（Underlying） | 確定状況 |
| --- | --- | --- | --- |
| 0 | `DWSTETH` | dwstETH（wstETH） | confirmed・Day-1 active（ETH 系優先） |
| 1 | `DUSDC` | dUSDC（USDC） | confirmed |
| 2 | `DETH` | dETH（TBD） | immutable値確定・inert。branch 0と同じ保守側LST envelope |
| 3 | `DUSD_A` | dUSD-A（TBD） | immutable値確定・inert |
| 4 | `DBTC` | dBTC（TBD） | immutable値確定・inert |
| 5 | `DUSD_B` | dUSD-B（TBD） | immutable値確定・inert |
| 6 | `DJPY` | dJPY（TBD） | immutable値確定・inert |
| 7 | `DJGB` | dJGB（TBD） | immutable値確定・inert（BCR・再分配ペナルティ = 5%） |


### LiquityBase の状態変数

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `activePool` | `IActivePool` public | constructor（AddressesRegistry から解決） | ブランチの ActivePool。アクティブ Trove の担保・集計負債の保管先 |
| `defaultPool` | `IDefaultPool` internal | 同上 | ブランチの DefaultPool。清算再分配の未適用分（pending）の保管先。getter なし |
| `priceFeed` | `IPriceFeed` internal | 同上 | ブランチの価格フィード。DF では PriceFeedProxy が注入される（[Oracle.md](./Oracle.md)）。getter なし |


### LiquityMath の状態変数

該当なし（library・状態を持たない）。


### Ownable の状態変数

| 変数 | 型・可視性 | 初期値/設定箇所 | 意味・会計上の役割 |
| --- | --- | --- | --- |
| `_owner` | `address` private | constructor で `initialOwner`／`_renounceOwnership` で `address(0)` | onlyOwner 権限の保持者。配線完了後はゼロ化され権限関数は恒久無効 |


### Types の状態変数

型定義に付随する file-level 定数のみ。

| 定数 | 型 | 値 | 意味 |
| --- | --- | --- | --- |
| `TROVE_ID_ZERO` | `TroveId` | `TroveId.wrap(0)` | ゼロ値（未設定） |
| `TROVE_ID_END_OF_LIST` | `TroveId` | `TroveId.wrap(ROOT_NODE_ID)`＝`wrap(0)` | SortedTroves 連結リストの終端（ルートノード）。`TROVE_ID_ZERO` と同値（CORE-LIB-INV-003） |
| `BATCH_ID_ZERO` | `BatchId` | `BatchId.wrap(address(0))` | 「バッチ無所属」を表すゼロ値 |


---

## 8. 不変条件（INV）

> 不変条件は invariant テスト・監査の基準。まず **8.1 コントラクト横断（CORE-SYS-INV-*）**、続いてコントラクト内に閉じる不変条件をスコープ別に規定する。🔵 不変条件は base 実装が満たす性質の記述であり、parity 検証の対象でもある。

### 8.1 コントラクト横断の不変条件（CORE-SYS-INV-*）

#### CORE-SYS-INV-001: ブランチ債務の分解恒等式 🔵
- ブランチの総債務は常に次で分解される（`LiquityBase.getEntireBranchDebt` の定義そのもの）:
  `entireBranchDebt == AP.aggRecordedDebt + AP.calcPendingAggInterest() + AP.aggBatchManagementFees + AP.calcPendingAggBatchManagementFee() + DP.getJpydfDebt()`
- さらに個別 Trove との関係は `entireBranchDebt ≥ Σ_troves getLatestTroveData(i).entireDebt`。等号からの乖離は丸めの非対称（Trove 個別利息は floor＝CORE-LIB-FR-008、集計利息は ceil＝CORE-AP-FR-002）による正方向の dust に限られ、システム債務がΣ個別を下回ることはない。
- **Verification**: invariant / parity
#### CORE-SYS-INV-002: 加重債務和の整合 🔵
- `AP.aggWeightedDebtSum == Σ（batch 非所属 Trove の recordedDebt × annualInterestRate）+ Σ（batch の recordedDebt × batch annualInterestRate）`。batch 管理 fee 側も同型（`aggWeightedBatchManagementFeeSum == Σ batch recordedDebt × managementFee`）。
- すべての債務変更操作（BO 経由・清算・redemption）が TroveChange（CORE-LIB-FR-015）の old/new 対で AP の和を更新することで保たれる。
- **Verification**: invariant / parity
#### CORE-SYS-INV-003: JPYdf 供給経路の閉性 🔵
- `JpydfToken.totalSupply` を Core debt accounting として変化させる既存経路は次に限られる。**増加**: BO の借入元本 mint（CORE-BO-FR-001/002/003 ほか）／ AP の集計利息・upfront fee の確定 mint（CORE-AP-FR-007/008。upfront fee は債務に加算され AP の集計 mint 経由で供給化される）・batch 管理 fee mint（CORE-AP-FR-009）。**減少**: BO の返済・close での burn（CORE-BO-FR-003/007/009 ほか）／ CR の redemption burn（CORE-CR-FR-002）／ TM の urgent redemption burn（CORE-TM-FR-005）／ SP の offset burn（CORE-SP-FR-007）。
- bridge supply path は Core `mint` / `burn` ではなく `bridgeMint` / `bridgeBurn` に分離され、登録済み bridge minter のみが呼べる（CORE-BT-FR-015）。Day-1 では `bridgeMinterCount == 0` / pending proposal なしのため、実効供給変化は Core debt accounting 経路だけに閉じる（[Product-Overview](../Product-Overview.md) SYS-INV-003）。
- **Verification**: parity / 監査（Core mint/burn call site の全数確認）＋ unit（Day-1 dormant bridge state / bridge minter lifecycle）
#### CORE-SYS-INV-004: redemption の会計整合 🔵
- 1 回の `CollateralRegistry.redeemCollateral` において、CR が redeemer から burn する JPYdf 総額は、各 branch TM が減らした債務減少額の合計と一致する（`redeemedAmount == Σ_branches troveChange.debtDecrease`）。手数料は JPYdf ではなく**担保の控除**として実現する（redeemer の受取担保が減り、その分が Trove に残る）。
- **Verification**: parity / unit
#### CORE-SYS-INV-005: 清算の担保保存則 🔵
- 各 Trove の清算において `collToSendToSP + collToRedistribute + collSurplus + collGasCompensation == entireColl`（TM `_liquidate` の分解。dust は math 上発生しない）。ブランチ全体でも、清算前後で「AP＋DP＋SP＋CSP＋清算者受取」の担保総量は保存される。
- **Verification**: invariant / parity / unit
#### CORE-SYS-INV-006: redistribution 会計の整合 🔵
- `DP.getJpydfDebt() == Σ（全 active/zombie Trove の未適用 redistribution 債務ゲイン）± 端数誤差`、担保側も同型。誤差は TM の error feedback トラッカー（`lastJpydfDebtError_Redistribution` / `lastCollError_Redistribution`）が次回清算で補正し、累積発散しない。
- **Verification**: invariant / parity
#### CORE-SYS-INV-007: AP・DP 担保会計の保存 🔵
- ブランチが保有する担保（オープン中 Trove の担保合計）は常に `AP.getCollBalance() + DP.getCollBalance()` に等しい（`LiquityBase.getEntireBranchColl`）。SP 保有担保（清算ゲイン）と CSP 保有担保（surplus）はオープン中 Trove の担保ではなく、この恒等式の外側の別勘定。
- 各 Pool の内部トラッカー（`collBalance`）は実残高 `collToken.balanceOf` 以下（直接送付された会計外トークンの分だけ実残高が上回りうる。会計には影響しない＝donation 耐性、各 SEC）。
- **Verification**: invariant / parity
#### CORE-SYS-INV-008: GasPool の WETH 整合 🔵
- `WETH.balanceOf(gasPool) ≥ オープン中（active＋zombie）Trove 数 × ETH_GAS_COMPENSATION`。等号は直接送付（寄付）が無い場合。入庫は open（CORE-BO-FR-001/002）、出庫は close（返還）と清算（実行者へ支払い）のみ。
- **Verification**: invariant / parity
#### CORE-SYS-INV-009: SortedTroves と Trove 集合の整合 🔵
- SortedTroves のノード集合 ＝ 当該 branch の `status == active` の Trove 集合（zombie / closed / liquidated は不在）。リストは金利の降順（同率は後入りが tail 側＝先に redemption を受ける）で、batch 所属ノードは連続 slice を保つ。
- 金利・batch 所属の変更とリスト再挿入は、BO の各操作内で**同一 tx で原子的に**行われる（リスト位置と実金利の乖離が観測される状態は存在しない）。
- **Verification**: invariant / parity
#### CORE-SYS-INV-010: TroveNFT と Trove 状態の整合 🔵
- `∀ troveId`: TroveNFT が存在する（`ownerOf` が解決できる）⇔ `TM.getTroveStatus(troveId) ∈ {active, zombie}`。mint は Trove 開設、burn は close / 清算時のみ（TM 経由限定＝CORE-TN-SEC-001）。
- **Verification**: invariant / parity
#### CORE-SYS-INV-011: MIN_JPYDF_IN_SP の横断維持 🔵
- 一度 `totalJpydfDeposits ≥ MIN_JPYDF_IN_SP` に達した SP は、以後どの操作後もこれを下回らない。出金側は SP の事後 require（CORE-SP-FR-003）、清算側は TM が offset 可能額を `totalJpydfDeposits − MIN_JPYDF_IN_SP` に制限すること（CORE-TM-FR-001）で、両コントラクトの規律が合わさって成立する。
- **Verification**: invariant / parity
#### CORE-SYS-INV-012: MIN_DEBT と zombie の規律 🔵
- `status == active` の Trove は常に `entireDebt ≥ MIN_DEBT`（🟡 値は CORE-MOD-002 / CORE-LIB-FR-002）。`entireDebt < MIN_DEBT` の生成経路は redemption による部分償還のみ（→ zombie 化）。BO 操作は調整後債務に MIN_DEBT を要求し、zombie の復帰（adjustZombieTrove）も MIN_DEBT 以上への回復を要求する。
- **Verification**: invariant / parity
#### CORE-SYS-INV-013: shutdown の一回性（BO–TM 信頼境界） 🔵
- ブランチ shutdown は一度だけ起こる。`TM.shutdown()` 自体は `shutdownTime` の上書きを防御せず、一回性は BO 側の `hasBeenShutDown` 検査（CORE-BO-FR-021/022）と「TM.shutdown の呼出元は BO のみ」（CORE-TM-SEC-007）の組で担保される。`AP.setShutdownFlag` 以後 `calcPendingAggInterest() == 0`（利息恒久停止）。
- **Verification**: parity / unit（二重 shutdown 不能）
#### CORE-SYS-INV-014: troveId の sentinel 非衝突 🔵
- `troveId == 0` の Trove は存在しない（0 は SortedTroves の ROOT / リスト終端 sentinel）。`troveId = uint256(keccak256(abi.encode(msg.sender, owner, ownerIndex)))` の衝突・ゼロ値は実用上発生せず、既存 Trove との重複は BO が `TroveExists`（status 検査）で拒否する。
- **Verification**: parity / unit


### BorrowerOperations の不変条件（CORE-BO-INV-*）

#### CORE-BO-INV-001: hasBeenShutDown の単調性 🔵
`hasBeenShutDown` は単調（false → true の一回のみ。true へ遷移させる経路は `shutdown()` と `shutdownFromOracleFailure()` の 2 つだけで、false へ戻す経路は存在しない）。Verification: invariant。

#### CORE-BO-INV-002: delegate と batch 所属の排他 🔵
任意の Trove で `interestIndividualDelegateOf[t].account != 0` と `interestBatchManagerOf[t] != 0` は同時に成立しない（batch 加入時に delegate を削除、delegate 設定時に batch を離脱）。Verification: invariant。

#### CORE-BO-INV-003: batch 所属先の登録済み保証 🔵
`interestBatchManagerOf[t] != 0` ならば、そのアドレスは登録済み batch manager（`interestBatchManagers[m].maxInterestRate > 0`）である。Verification: invariant。

#### CORE-BO-INV-004: batch manager レコードの不変性 🔵
登録済み batch manager のレコード `(minInterestRate, maxInterestRate, minInterestRateChangePeriod)` は登録後不変・削除不能。batch の管理 fee は登録時値から単調非増加（引き上げ関数が存在しない）。Verification: invariant。

#### CORE-BO-INV-005: 配線・ブランチパラメータの constructor 後不変 🔵
配線（troveManager / gasPoolAddress / collSurplusPool / jpydfToken / sortedTroves / collToken / WETH / troveNFT / activePool / defaultPool / priceFeed）とブランチパラメータ（CCR / SCR / MCR / BCR）、および collToken → ActivePool の無限 allowance は constructor 以後変更されない（setter 不在）。Verification: invariant / deploy 検証。

> コントラクト横断: 「active Trove の `entireDebt ≥ MIN_DEBT`」は CORE-SYS-INV-012、「GasPool の WETH 整合」は CORE-SYS-INV-008、「TCR < CCR 時の操作制限」は CORE-SYS-ERR-002（規範は CORE-BO-ERR-001）を参照。


### TroveManager の不変条件（CORE-TM-INV-*）

#### CORE-TM-INV-001: totalStakes の整合 🔵
`totalStakes` は常に全 active・zombie Trove の `stake` の総和に等しい（開設 +、調整は差分、閉鎖・清算 −）。redistribution の分母であるため、これが破れると配賦が成立しない。Verification: invariant / parity。

#### CORE-TM-INV-002: L 値の単調性 🔵
`L_coll` / `L_jpydfDebt` は単調非減少。各 Trove の `rewardSnapshots` は常に現在の L 値以下であり、差分（未適用 gain）は非負。Verification: invariant。

#### CORE-TM-INV-003: TroveIds / arrayIndex の整合 🔵
`status ∈ {active, zombie}` ⇔ `TroveIds` に含まれる。`TroveIds[Troves[id].arrayIndex] == id`。swap-and-pop（`_removeTroveId`）後も保持される。Verification: invariant。

#### CORE-TM-INV-004: batch shares 会計の整合 🔵
各 batch について `batches[b].totalDebtShares == Σ（所属 Trove の batchDebtShares）`。所属 Trove の `Troves.debt == 0` かつ `annualInterestRate == 0`（債務は shares のみで表現）。`_newTroveDebt == 0` への減少時は shares が完全に 0 となり端数 shares が残らない。Verification: invariant。

#### CORE-TM-INV-005: lastZombieTroveId の整合 🔵
`lastZombieTroveId != 0` ならば当該 Trove は `status == zombie` かつ（通常運転下で）`entireDebt > 0`（設定時点で 0 < newDebt < MIN_DEBT）。リセット経路は通常 redemption での全額償還・閉鎖（`_closeTrove`）・active 復帰（`setTroveStatusToActive`）。**例外**: shutdown 後の `urgentRedemption` は zombie ポインタを処理しないため、ポインタ先 zombie を全額償還すると `entireDebt == 0` のままポインタが残存しうる（shutdown 後は通常 redemption が来ないため実害はない）。Verification: invariant（通常運転）/ unit（shutdown 後の例外）。

#### CORE-TM-INV-006: redistribution 誤差の有界性 🔵
`lastCollError_Redistribution` / `lastJpydfDebtError_Redistribution` は、**直近の redistribution 実行時点の** `totalStakes` 未満（除算剰余であるため。その後 Trove 閉鎖等で totalStakes が縮小すると現在値を上回りうる）。error feedback により配賦合計と `L` 増分 × `totalStakes` の乖離は累積しない。Verification: invariant / unit。


### StabilityPool / DFStabilityPool の不変条件（CORE-SP-INV-*）

#### CORE-SP-INV-001: P の範囲と非ゼロ性 🔵
- 任意の時点で `P ∈ [P_PRECISION / SCALE_FACTOR, P_PRECISION]`（=[1e27, 1e36]）かつ `P > 0`。実効減耗率 `P / SCALE_FACTOR^currentScale` は単調非増加。`currentScale` は単調非減少。
- 根拠: 初期値 `P = P_PRECISION`、`offset` の `require(newP > 0)` と scale ループ（CORE-SP-FR-007 手順 3〜5）。
- Verification: invariant / parity。

#### CORE-SP-INV-002: MIN_JPYDF_IN_SP の単調維持 🔵
- 一度 `totalJpydfDeposits >= MIN_JPYDF_IN_SP` が成立したら、以後どの操作後も維持される。
- SP 側の担保根拠: `withdrawFromSP` の事後 require（CORE-SP-FR-003 手順 12）。`offset` 側は TroveManager が `_debtToOffset <= totalJpydfDeposits - MIN_JPYDF_IN_SP` を保証する前提（TM スコープ）であり、完全な不変条件はコントラクト横断で成立する（CORE-SYS-INV-011）。
- Verification: invariant（SYS）。

#### CORE-SP-INV-003: JPYdf 会計恒等式 🔵
- `jpydfToken.balanceOf(SP) == totalJpydfDeposits + yieldGainsOwed + yieldGainsPending`。外部から SP へ JPYdf を直接 transfer した場合のみ左辺が大きくなる（会計外で滞留し、どの経路でも払い出されない）。
- 根拠: すべてのトラッカー増減（預入・引出・複利・オフセット焼却・利回り mint）が同額の transfer/mint/burn と対で行われる（CORE-SP-FR-002/003/006/007）。なお個別預金者の取り分合計は床除算により各トラッカー以下となり、端数 dust はプール内に残置される（過払いは CORE-SP-FR-008/009 のクランプでも遮断）。
- Verification: invariant / parity。

#### CORE-SP-INV-004: 担保会計の整合 🔵
- `collToken.balanceOf(SP) >= collBalance >= Σ stashedColl + Σ 未精算担保ゲイン`。左の不等号は直接 transfer 分（会計外）、右の不等号は床除算 dust による。
- 根拠: `collBalance` は `offset` の受入と精算払出のみで増減（CORE-SP-FR-005/007、`_sendCollGainToDepositor`）。
- Verification: invariant。

#### CORE-SP-INV-005: pending と閾値の排他 🔵
- `yieldGainsPending > 0` ならば `totalJpydfDeposits < MIN_JPYDF_IN_SP`。閾値回復を伴う最初の `provideToSP` / `triggerJpydfRewards` で pending は必ず 0 に戻る（owed へ振替）。
- 根拠: CORE-SP-FR-002 手順 13・CORE-SP-FR-006 手順 2〜3、および INV-002（閾値以上から未満へは戻らない）。
- Verification: invariant / unit。

#### CORE-SP-INV-006: 預金とスナップショットのライフサイクル整合 🔵
- `deposits[d].initialValue > 0` ⇔ `depositSnapshots[d]` が設定済み（`P_t ∈ [1e27, 1e36]`）。預金が 0 になる操作では必ず snapshot が delete される。
- 根拠: `_updateDepositAndSnapshots` の分岐（CORE-SP-FR-003 手順 7）。
- Verification: invariant / unit。


### ActivePool の不変条件（CORE-AP-INV-*）

#### CORE-AP-INV-001: 会計残高は実残高を超えない 🔵
`collBalance ≤ collToken.balanceOf(activePool)` がトランザクション境界で常に成立する。会計加算は必ず同一 tx 内の実トークン受領（pull または直接 transfer）と対で行われ、減算は transfer に先行する。直接 transfer による寄付（donation）は collBalance に反映されず、超過分は会計上存在しない（取り出す経路もない）。
- **Verification**: invariant / parity

#### CORE-AP-INV-002: shutdown 後の利息凍結 🔵
`shutdownTime != 0` となった以後、`calcPendingAggInterest() == 0` が恒久成立し、`aggRecordedDebt` が集計利息によって増加することはない（TroveChange 起因の増減・batch フィー繰入れは除く）。
- **Verification**: unit / invariant

- **コントラクト横断**: 負債の分解と正誤差は CORE-SYS-INV-001、担保の保存は CORE-SYS-INV-007、加重和の整合は CORE-SYS-INV-002 を参照。


### DefaultPool の不変条件（CORE-DP-INV-*）

#### CORE-DP-INV-001: 会計残高は実残高を超えない 🔵
`collBalance ≤ collToken.balanceOf(defaultPool)` がトランザクション境界で常に成立する（受領は pull と同時、送出は減算先行）。直接 transfer による寄付は会計に反映されず取り出し経路もない。
- **Verification**: invariant / parity

- **コントラクト横断（CORE-SYS-INV-006）**: `DP.JpydfDebt == Σ(全アクティブ Trove の未適用 redistribution 負債ゲイン) ± redistribution 端数誤差（TM の lastJpydfDebtError_Redistribution で補正）`、同様に `DP.collBalance` と未適用担保ゲインの対応。負債分解（AP＋DP）は CORE-SYS-INV-001。


### CollSurplusPool の不変条件（CORE-CSP-INV-*）

#### CORE-CSP-INV-001: 会計の整合 🔵
トランザクション境界で `collBalance == Σ balances[a]`（記帳と総額は常に同時更新）かつ `collBalance ≤ collToken.balanceOf(collSurplusPool)`（実トークンは同一清算 tx 内に AP から搬入される。直接 transfer の寄付は会計外で取り出し経路なし）。
- **Verification**: invariant / parity


### SortedTroves の不変条件（CORE-ST-INV-*）

#### CORE-ST-INV-001: 金利降順整列 🔵
head から tail へ `nextId` を辿ると、各ノードの `troveManager.getTroveAnnualInterestRate(id)` は**非増加**（降順。同率を許す）。同率ノード間の相対順序は挿入順（後に挿入されたものほど tail 側）。ただし本不変条件が成立するのは「金利変更時に必ず reInsert / reInsertBatch が呼ばれる」（BO 側の規律）前提であり、TM 上の金利更新とリスト位置更新の間に原子性が要求される（コントラクト横断の規定は CORE-SYS-INV-009）。

#### CORE-ST-INV-002: 双方向リンク・番兵・size の整合 🔵
任意のノード i（番兵含む）について `nodes[nodes[i].nextId].prevId == i` かつ `nodes[nodes[i].prevId].nextId == i`（番兵 ROOT を含む単一の循環リスト）。`exists == true` のノード集合 ＝ 番兵から到達可能なノード集合（番兵除く）であり、その要素数 ＝ `size`。空リストでは `nodes[0].nextId == nodes[0].prevId == 0`。

#### CORE-ST-INV-003: batch slice の連続性 🔵
任意の非空 batch B について: `batches[B].head` から `nextId` を辿ると batch B のメンバーだけが連続して並び、`batches[B].tail` で終わる。すなわち同一 batch のメンバーはリスト上の連続区間（slice）を成し、区間内の全ノードの `batchId == B`。`validInsertPosition` の「同一 batch の内部は挿入位置として無効」（CORE-ST-FR-008）と、batch への追加が常に tail 直後である（CORE-ST-FR-005）ことで維持される。

#### CORE-ST-INV-004: exists とノード状態の整合 🔵
`contains(id) == true` ⇔ そのノードがリスト上に存在。除去時は `delete nodes[id]` により batchId・リンクごと消去される。`size` の増減は挿入（+1）・除去（−1）と 1:1 に対応する。ノード集合と TM 状態のコントラクト横断整合は CORE-SYS-INV-009 を参照。


### TroveNFT の不変条件（CORE-TN-INV-*）

#### CORE-TN-INV-001: NFT と Trove の 1:1 対応 🔵
tokenId ＝ troveId であり、NFT が存在する（`ownerOf` が解決できる）⇔ 対応する Trove の status が `active` または `zombie`。mint は TM の Trove 開設（`onOpenTrove` / `onOpenTroveAndJoinBatch`）、burn は TM の `_closeTrove` のみで行われ、TroveNFT 単独で対応関係を崩す経路はない。`ownerOf(troveId)` が Trove 所有者の唯一の正本。（コントラクト横断の規定は CORE-SYS-INV-010）


### JpydfToken の不変条件（CORE-BT-INV-*）

→ 規範は [JpydfToken.md](./JpydfToken.md) §8（`CORE-BT-INV-001..003`）。

### CollateralRegistry の不変条件（CORE-CR-INV-*）

#### CORE-CR-INV-001: baseRate の上限 🔵
常に `baseRate <= DECIMAL_PRECISION`（`_getUpdatedBaseRateFromRedemption` が 100% で cap。constructor 初期値も 100%）。

#### CORE-CR-INV-002: 実効 rate の範囲 🔵
redemption に適用される rate は常に `[REDEMPTION_FEE_FLOOR, DECIMAL_PRECISION]` の範囲（`_calcRedemptionRate` が floor 加算と 100% cap を保証）。

#### CORE-CR-INV-003: lastFeeOperationTime の単調性 🔵
`lastFeeOperationTime` は単調非減少で、増分は常に `ONE_MINUTE` の整数倍、かつ `lastFeeOperationTime <= block.timestamp`。1 分未満の経過では更新されない（decay 刻み獲得の griefing 防止）。

#### CORE-CR-INV-004: branch 構成の不変性 🔵
`totalCollaterals`・`token0..9`・`troveManager0..9`・`jpydfToken` はすべて immutable。branch の追加・削除・差替は CollateralRegistry の再デプロイ（および JpydfToken 側 burn 権限の再配線＝事実上システム再デプロイ）なしには不可能。


### AddressesRegistry の不変条件（CORE-AR-INV-*）

#### CORE-AR-INV-001: リスクパラメータの範囲と不変性 🔵
`1e18 < CCR, MCR, SCR < 2e18`、`5e16 <= BCR < 50e16`、`MIN_LIQUIDATION_PENALTY_SP <= LIQUIDATION_PENALTY_SP <= LIQUIDATION_PENALTY_REDISTRIBUTION <= MAX_LIQUIDATION_PENALTY_REDISTRIBUTION`。すべて immutable のためデプロイ後不変（branch パラメータの変更＝branch 再デプロイ）。

#### CORE-AR-INV-002: 配線の一回性 🔵
`setAddresses` 実行後は `owner() == address(0)` となり、全 18 アドレスは以後変更不能。`setAddresses` 実行前に各アドレスは `address(0)`。


### HintHelpers の不変条件（CORE-HH-INV-*）

#### CORE-HH-INV-001: fee 試算と実請求の一致 🔵
同一チェーン状態（同一ブロック・介在操作なし）において、`predict*` 各関数の返り値は、対応する BorrowerOperations 操作が実際に請求する `upfrontFee` と一致する。0 短絡条件（同率・cooldown 経過・増分ゼロ）も BO の課金条件と同値。
- **Verification**: parity（BO 実行結果との突合）。


### RedemptionHelper の不変条件（CORE-RH-INV-*）

#### CORE-RH-INV-001: 資金パススルー（残高不変）🔵
`redeemCollateral` の実行前後で、本コントラクトの JPYdf 残高および全ブランチ collToken 残高は変化しない（引き落とした JPYdf は焼却または返還、受領担保は全額 `msg.sender` へ送付）。
- **Verification**: invariant / unit。


### LiquidationCandidateGetter の不変条件（CORE-LCG-INV-*）

#### CORE-LCG-INV-001: core 非干渉 🟢
全関数 view であり、core の状態を変更する経路を持たない。core 側コントラクトは本コントラクトを参照しない（一方向依存）。本コントラクトの追加・撤去・障害は core の挙動・安全性に影響しない（DF 独自追加を core 無改変方針と両立させる前提条件）。
- **Verification**: unit / コードレビュー（mutability・依存方向）。


### Constants.sol の不変条件（CORE-LIB-INV-*）

#### CORE-LIB-INV-001: upstream 定数の base 同値性 🔵
`MIN_DEBT`（CORE-MOD-002）と `COLL_GAS_COMPENSATION_CAP`（CORE-MOD-003）を除き、Constants.sol に残る upstream 由来定数は base（liquity/bold v1.11.0）と同値である。production 未参照の upstream fixture 定数（`*_WETH` / `*_SETH` / `BCR_ALL`）と補助別名（`ZERO_ADDRESS` / `MAX_UINT256`）は audit surface 削減のため production `src` から削除済みであり、必要な inherited test はローカル fixture 値または Solidity の組み込み表現を使う。
- **Verification**: parity（残存定数値の base との突き合わせ）/ absence review

#### CORE-LIB-INV-002: 派生定数の厳密性 🔵
`_1pct = 1e16` は 100 で割り切れるため、`<pct*100> * _1pct / 100` 形式の全ブランチ別定数（小数 2 桁以内の％）は丸め誤差ゼロの厳密な整数として確定する。また `_100pct == DECIMAL_PRECISION`、`_1pct == DECIMAL_PRECISION / 100` が恒等に成り立つ。
- **Verification**: unit（定数式の評価値検査）

補足: `MIN_LIQUIDATION_PENALTY_SP ≤ LIQUIDATION_PENALTY_SP_<BR> ≤ LIQUIDATION_PENALTY_REDISTRIBUTION_<BR> ≤ MAX_LIQUIDATION_PENALTY_REDISTRIBUTION` の順序関係は AddressesRegistry constructor（`SPPenaltyTooLow` / `SPPenaltyGtRedist` / `RedistPenaltyTooHigh`）が enforce する（CORE-AR-FR-001）。DF 全 8 ブランチの追記値がこの境界を満たすことのデプロイ前検証は CORE-SYS-GOV-003 が要求する。


### LiquityMath の不変条件（CORE-LIB-INV-*）

該当なし（失敗モードは CORE-LIB-ERR-001 に包含）。


### Types の不変条件（CORE-LIB-INV-*）

#### CORE-LIB-INV-003: リスト終端規約の同値性 🔵
`TROVE_ID_END_OF_LIST` は SortedTroves の `ROOT_NODE_ID`（= 0）を wrap した値であり、`TROVE_ID_ZERO` と同値。troveId = 0 はソートリストのルートノードとして予約され、有効 Trove の ID には使われない（ID は keccak256 由来の擬似乱数 256bit。衝突確率は無視できる）。
- **Verification**: unit（定数同値）／ コントラクト横断の規定は CORE-SYS-INV-014


---

## 9. セキュリティ要件（SEC）

> コアのセキュリティ性質。呼出元制限（信頼境界の要約表は §4）・権限モデル・操作排除（griefing / MEV / donation）を規定する。コアは監査済み・実戦検証済みコードを base-parity で継承し、JPYdf canonical surface と台帳化された `CORE-MOD-*` 差分だけを明示的に持つ（[Product-Overview](../Product-Overview.md) SYS-NFR-001）。本節は「何が守られているか」をテスト・監査が検証できる形に固定するためのもの。


### BorrowerOperations のセキュリティ要件（CORE-BO-SEC-*）

#### CORE-BO-SEC-001: Trove 操作権限モデルの閉性 🔵

- Type: Security
- Statement: 出金系操作（担保引出・借入・閉鎖）は owner と RemoveManager 以外が実行できてはならない（`NotOwnerNorRemoveManager`）。入金系操作（担保追加・返済）は `addManagerOf` 設定時は owner / AddManager / RemoveManager に限定され、未設定時は誰でも可という**既定の開放**が仕様である（入金系は Trove の健全性を改善する方向のみで、返済は MIN_DEBT cap により zombie 化攻撃に使えない）。RemoveManager は AddManager 権限を包含する。
- Verification: parity / unit（権限マトリクス）

#### CORE-BO-SEC-002: receiver redirection の制約 🔵

- Type: Security
- Statement: 出金系の資金受取先に登録 receiver が使われるのは「RemoveManager 本人の呼出かつ receiver 非ゼロ」の場合のみで、owner の呼出では常に owner が受取先でなければならない。これにより RemoveManager の鍵が漏えいしても、資金の送付先は owner が事前に固定した receiver に限定される。
- Verification: parity / unit

#### CORE-BO-SEC-003: 内部フックの呼出元限定 🔵

- Type: Security
- Statement: `onLiquidateTrove` は troveManager のみ（`CallerNotTroveManager`）、`shutdownFromOracleFailure` は priceFeed のみ（`CallerNotPriceFeed`）が呼び出せること。これが破れると第三者が任意 Trove の委任状態消去や恣意的 shutdown を行える。
- Verification: parity / unit

#### CORE-BO-SEC-004: upfront fee のスリッページ防御 🔵

- Type: Security
- Statement: upfront fee を徴収するすべての経路（開設・借入・premature 金利変更・batch 加入・premature batch 離脱・batch 一括金利変更）で、ユーザー指定の `_maxUpfrontFee` を超える fee は `UpfrontFeeTooHigh` で拒否されなければならない（fee はブランチ平均金利に依存し、tx の前後で第三者操作により変動しうるため）。
- Verification: parity / unit

#### CORE-BO-SEC-005: permissionless 操作の状態条件ゲート 🔵

- Type: Security
- Statement: permissionless な `shutdown` は TCR < SCR、`kickFromBatch` は債務/shares 比 > `MAX_BATCH_SHARES_RATIO`、`applyPendingDebt` は「記録値の確定」のみ（金利・債務条件を変えない）に制約され、第三者がこれらを通じて borrower に経済的不利益を与えられないこと。
- Verification: parity / unit


### TroveManager のセキュリティ要件（CORE-TM-SEC-*）

#### CORE-TM-SEC-001: on* コールバックの BorrowerOperations 限定 🔵
全 `on*`・`setTroveStatusToActive`・`shutdown` は `msg.sender == borrowerOperations` を要求（`CallerNotBorrowerOperations`）。これらは入力検証を持たない「信頼された書込み口」であり、BO 以外から呼べると台帳を任意改変できる。Verification: unit（全関数の caller 検査）/ parity。

#### CORE-TM-SEC-002: redeemCollateral の CollateralRegistry 限定 🔵
fee 率・ブランチ配分の計算を CollateralRegistry に強制するため、直接呼出を禁止（`CallerNotCollateralRegistry`）。これが破れると fee 0 での償還が可能になる。Verification: unit / parity。

#### CORE-TM-SEC-003: 清算条件の限定 🔵
清算は permissionless だが、`status ∈ {active, zombie}` かつ `getCurrentICR < MCR`（entire 値基準）の Trove のみが対象。健全な Trove は配列に混ぜられても黙ってスキップされる。Verification: parity / unit。

#### CORE-TM-SEC-004: Redemption による CR 悪化の防止 🔵
通常 Redemption は `ICR < 100%` の Trove をスキップする（償還は債務と等価値の担保を抜くため、ICR < 100% の Trove では CR をさらに悪化させる）。urgentRedemption はこの保護を持たない代わりに担保全量キャップで対応する。Verification: parity / unit。

#### CORE-TM-SEC-005: zombie 機構による Redemption griefing 耐性 🔵
`MIN_DEBT` 未満へ償還された Trove は zombie 化して SortedTroves から外れるため、微小 Trove を並べて逐次 Redemption を gas 枯渇させる攻撃が成立しない。部分償還の食べ残しは `lastZombieTroveId` で次回最優先消化。Verification: parity / unit。

#### CORE-TM-SEC-006: batch shares の希釈・rebase 攻撃耐性と Redemption 非ブロック 🔵
debt/shares 比の上限検査（`BatchSharesRatioTooHigh`）で shares の極端な希釈を防ぐ一方、Redemption 経路では検査を無効化し、batch 状態を理由に償還が止まらないことを保証する。Verification: unit。

#### CORE-TM-SEC-007: shutdown の一回性は BorrowerOperations 依存 🔵
`shutdown()` 自体は `shutdownTime` の上書きを禁止していない。一回性（再呼出不可）は BO 側 require で担保される前提（コントラクト横断の規定は CORE-SYS-INV-013）。Verification: parity（BO 経由の二重 shutdown 不能）。

- **コントラクト横断**: ① ブランチ債務整合は CORE-SYS-INV-001、② 清算の担保保存則は CORE-SYS-INV-005、③ SortedTroves との所属整合は CORE-SYS-INV-009、④ shutdown 後に通常 redemption が来ないこと（redeemable=false の尊重）は CORE-CR-FR-001 / CORE-SYS-ERR-003 を参照。


### StabilityPool / DFStabilityPool のセキュリティ要件（CORE-SP-SEC-*）

#### CORE-SP-SEC-001: offset の呼出元制限 🔵
- `offset` は TroveManager のみ。任意の呼出者が `P`/`S`/`totalJpydfDeposits` を操作して全預金者の会計を破壊する経路を遮断する（`"StabilityPool: Caller is not TroveManager"`）。
- Verification: unit（非 TM 呼出の revert）/ parity。

#### CORE-SP-SEC-002: triggerJpydfRewards の呼出元制限 🔵
- `triggerJpydfRewards` は ActivePool のみ。`yieldGainsOwed` / `scaleToB` の不正積み増し（JPYdf 実体の裏付けなく利回り請求権を膨らませ、他者の owed を横取りする攻撃）を遮断する（`"StabilityPool: Caller is not ActivePool"`）。
- Verification: unit / parity。

#### CORE-SP-SEC-003: 内部トラッカーによる donation 耐性 🔵
- 残高会計は `collBalance` / `totalJpydfDeposits` 等の内部トラッカーに基づき、`balanceOf` を参照しない。collToken・JPYdf の直接送付（または self-destruct による強制送付）は会計に影響せず、配分計算を歪められない（内部トラッカー会計の帰結。AP/DP/CSP の donation 耐性〔CORE-AP-INV-001 ほか〕と同型）。
- Verification: unit（直接 transfer 後の各 view 不変）。

#### CORE-SP-SEC-004: same-block flash 預入による清算益横取りの防止 🟡
- 攻撃シナリオ（base で可能）: 清算が同一ブロックで発生することを予見した攻撃者が、flash loan 等で調達した大量 JPYdf を `provideToSP` → `offset` で担保ゲインの大半を比例配分で獲得（清算担保は通常ディスカウント付きで分配されるため即時利益）→ 同一ブロック内に `withdrawFromSP` で元本＋ゲインを回収。プール在籍リスクをほぼ負わず、既存預金者の取り分を希釈する。
- DF の対策（CORE-MOD-004（§2 DF 差分台帳））: DFStabilityPool は `withdrawFromSP` と、`provideToSP(..., true)` による current/stash 担保ゲイン払出を `lastDepositBlock[msg.sender] < block.number` に制限する（CORE-SP-FR-004）。同一 tx 返済が必須の flash loan は、預金の出金だけでなく清算担保の受領・換価にも進めず、自己資金による預入も少なくとも 1 つの block boundary を跨いで存続する。
- 残余リスク: block N の末尾で預入し block N+1 の先頭で出金する ordering では、間に `offset()` が発生せず清算減耗リスクを負わない可能性がある。翌ブロック以降の出金と複数ブロックにわたる MEV は残り、本ガードは「リスクフリーの原子的横取り」の排除だけを目的とする。
- Verification: unit（same-block revert・翌ブロック成功・flash loan 経路の不成立）。

#### CORE-SP-SEC-005: 外部呼出面と再入の考慮 🔵
- SP の外部呼出先は `activePool` / `jpydfToken` / `collToken` のみ。前二者は系内コントラクト、`collToken` は dToken（[dToken.md](./dToken.md)）であり、いずれも transfer フック（ERC-777 型）を持たない前提。預金者操作は状態更新（snapshot・トラッカー）を transfer より先に行う（CORE-SP-FR-002/003 の手順順序）ため、仮にフックがあっても古い状態での再入は成立しにくい構造。`provideToSP` 中の `mintAggInterest` → `triggerJpydfRewards` の系内再入（SP 自身への callback）は設計上の正規経路であり、ゲイン計算前に完了する。
- Verification: parity / 設計レビュー（dToken 側仕様への依存を明記）。


### ActivePool のセキュリティ要件（CORE-AP-SEC-*）

#### CORE-AP-SEC-001: 状態変更面の呼出元限定 🔵
全 8 つの状態変更入口（mintAggInterest / mintAggInterestAndAccountForTroveChange / mintBatchManagementFeeAndAccountForChange / sendColl / sendCollToDefaultPool / receiveColl / accountForReceivedColl / setShutdownFlag）は require によりコア コントラクト（BO / TM / SP / DP）に限定され、第三者が会計トラッカー・担保移転・JPYdf mint を直接駆動する経路はない。JPYdf の mint 自体は JpydfToken 側の minter 制限（BT スコープ）と二重の防壁になる。
- **Verification**: unit（全関数の不正呼出元 revert）/ parity


### DefaultPool のセキュリティ要件（CORE-DP-SEC-*）

#### CORE-DP-SEC-001: 書込み面の呼出元限定 🔵
状態変更 4 関数はすべて TroveManager / ActivePool に限定され、第三者がペンディング会計を操作する経路はない。担保の実トークンが DefaultPool から出る唯一の経路は `sendCollToActivePool` 経由の ActivePool 向け pull であり、任意アドレスへの送付関数を持たない。
- **Verification**: unit（不正呼出元 revert）/ parity


### CollSurplusPool のセキュリティ要件（CORE-CSP-SEC-*）

#### CORE-CSP-SEC-001: 請求権の本人限定 🔵
記帳は TM、払い出しは BO に限定され、BO 経由の唯一の経路（`claimCollateral`）が `msg.sender` を渡すため、第三者が他人の余剰担保を請求・横取りする経路はコード上存在しない。受取先も `_account` 本人固定であり、承認・委任の概念がない。
- **Verification**: unit（不正呼出元 revert）/ parity


### GasPool のセキュリティ要件（CORE-GP-SEC-*）

#### CORE-GP-SEC-001: ゼロ攻撃面と approve の妥当性 🔵
GasPool は external / public 関数を持たず、デプロイ後に直接呼び出せる操作が存在しない。WETH の無限 approve は immutable 配線済みの BO / TM の 2 アドレスに限定され、第三者が GasPool 保有 WETH を移転する経路はない。
- **Verification**: unit（ABI が空であること・approve 対象の検証）/ parity

- **コントラクト横断（CORE-SYS-INV-008）**: `WETH.balanceOf(gasPool) == オープン中（zombie 含む）Trove 数 × ETH_GAS_COMPENSATION`（open で入庫・close/清算で出庫。直接送付の寄付があると ≥ に緩む）。


### SortedTroves のセキュリティ要件（CORE-ST-SEC-*）

#### CORE-ST-SEC-001: 書込み権限の限定とノード実在性の信頼委譲 🔵
状態変化関数 6 つの呼出元は BO（insert / reInsert / insertIntoBatch / reInsertBatch / remove / removeFromBatch）と TM（remove / removeFromBatch のみ）に限定される（require 実装: `_requireCallerIsBorrowerOperations` / `_requireCallerIsBOorTM`）。SortedTroves 自身は `_id` が実在 Trove かを検証せず、ID の正当性・金利引数の正しさは呼出元（BO/TM）に完全委譲する（信頼境界）。第三者が直接リスト順序を書き換える経路はない。

#### CORE-ST-SEC-002: hint 非依存の健全性（hint griefing 耐性）🔵
hint はガス節約のみに作用し、**結果の正しさに影響しない**: 無効 hint は検証で弾かれ必ず再探索される（CORE-ST-FR-009）。悪意の hint・front-running（hint 取得後〜tx 実行までの間の他者の挿入/削除）によって誤位置への挿入を引き起こすことはできず、起こり得るのは探索ステップ増（最悪、リスト全走査 O(n)・各ステップ TM への外部 view 呼出）によるガス増のみ。ガス増は当該 tx の送信者自身が負担する。


### TroveNFT のセキュリティ要件（CORE-TN-SEC-*）

#### CORE-TN-SEC-001: mint/burn の TroveManager 限定 🔵
`mint` / `burn` は `msg.sender == address(troveManager)` を require する（`_requireCallerIsTroveManager`）。NFT の発行・焼却＝Trove 所有権の創出・消滅であるため、TM の Trove ライフサイクル管理に完全同期させ、他のいかなるアドレス（owner 自身を含む）にも許さない。

#### CORE-TN-SEC-002: mint 時の受領者コールバック排除 🔵
mint は `_safeMint` ではなく `_mint` を使うため、受領者へのコールバック（`onERC721Received`）が発生しない。openTrove フローでの reentrancy・受領拒否 DoS のベクタを排除する（CORE-TN-FR-002）。なお `safeTransferFrom` による移転時は ERC-721 標準どおりコールバックが発生する（これは標準挙動であり、コア状態はこの時点で変化済み）。


### JpydfToken のセキュリティ要件（CORE-BT-SEC-*）

→ 規範は [JpydfToken.md](./JpydfToken.md) §9（`CORE-BT-SEC-001..004`）。

### CollateralRegistry のセキュリティ要件（CORE-CR-SEC-*）

#### CORE-CR-SEC-001: 配分の厳密性と truncation 🔵
合計 unbacked が正の通常経路では、per-branch 配分額の合計は `min(要求額, 合計 unbacked)` に厳密一致する（ループ内の残差更新による）。unbacked 合計を超える要求は切詰められ、不均衡な比例配分を防ぐ（upstream コード内コメント: CS-BOLD-013）。全 redeemable branch の unbacked が 0 の fallback（全債務比例）では切詰めは適用されず、要求額全量が配分される（CORE-CR-FR-002）。
burn 総額と債務減少総額のコントラクト横断整合は CORE-SYS-INV-004 を参照。

#### CORE-CR-SEC-002: 価格・redeemability の外部依存 🔵
配分の重み（unbacked portion）・適用価格・redeemable 判定は各 TM / PriceFeed（[Oracle.md](./Oracle.md)）の返り値に依存する。shutdown 済みまたは TCR < SCR の branch は配分から除外される。oracle 障害時の挙動は TM / PriceFeed 側の仕様に従う（本コントラクトは結果を信頼する）。


### AddressesRegistry のセキュリティ要件（CORE-AR-SEC-*）

#### CORE-AR-SEC-001: 配線値の無検証（デプロイ手順依存）🔵
`setAddresses` はゼロアドレス・コントラクト実在性・相互整合性（例: troveManager が当該 branch のものか）を一切検証しない。誤配線はそのまま各 core コントラクトの immutable に伝播し恒久化するため、デプロイスクリプトでの事前計算（CREATE2 アドレス予測）と、デプロイ後の突合検証が必須。正規 `DeployLiquity2` 手順は各 CREATE2 target の配備後、branch-local の期待値を実際に配備された instance へ置き換え、`AddressesRegistry` の全 18 getter を読み戻して期待アドレスとの一致・非ゼロ・runtime code の存在を確認してから次の registration へ進む。generic な重複禁止ではなく field ごとの期待 identity を照合するため、取り違え・ゼロ・EOA を検出しつつ constructor dependency cycle を維持する。CCR/MCR/SCR の相互順序が無検証である点も同様（CORE-AR-FR-001）。


### HintHelpers のセキュリティ要件（CORE-HH-SEC-*）

#### CORE-HH-SEC-001: 非保持・非干渉 🔵
全関数 view であり、core の状態を変更する経路・資産を保持する経路を持たない。HintHelpers の障害・誤設定が core の安全性に影響しない（hint が劣化しても `findInsertPosition` は正しい位置に到達する。ST 節）。


### MultiTroveGetter のセキュリティ要件（CORE-MTG-SEC-*）

#### CORE-MTG-SEC-001: 非保持・非干渉 🔵
全関数 view。core 状態への書込み経路・資産保持なし。表示系の障害が core に波及しない。


### DebtInFrontHelper のセキュリティ要件（CORE-DFH-SEC-*）

#### CORE-DFH-SEC-001: 非保持・非干渉 🔵
全関数 view。core 状態への書込み経路・資産保持なし。


### RedemptionHelper のセキュリティ要件（CORE-RH-SEC-*）

#### CORE-RH-SEC-001: 資金非保持・rescue なし 🔵
本コントラクトは資金保管を想定せず、引出・rescue 機構を持たない。**直接 transfer で送り込まれたトークンは恒久ロック**される（残高差分会計のため、呼出前から存在する残高は以後の払い出しにも乗らない）。ユーザー資金が触れるのは `transferFrom` 〜返還の単一 tx 内のみ。`transferFrom` は `msg.sender` の残高からのみ引くため、本コントラクトへの JPYdf approve を残しても第三者が他人の資金で償還することはできない（償還の成果物も `msg.sender` にのみ送られる）。担保（dToken）・JPYdf とも transfer hook を持たない ERC-20 であり再入面はない（[dToken.md](./dToken.md)・BT 節）。


### Ownable のセキュリティ要件（CORE-LIB-SEC-*）

#### CORE-LIB-SEC-001: _renounceOwnership の呼出元無検証 🔵
`_renounceOwnership()` は internal だが呼出元チェックを持たない（NatSpec 警告どおり）。継承コントラクトが認可外パスからこれを呼ぶ実装を加えると、第三者が配線前に owner を放棄させ初期化を恒久不能化（bricking）できる。現行コードベースの呼出 2 箇所（JpydfToken / AddressesRegistry）はいずれも onlyOwner 関数内で要件を満たす。新規継承時のレビュー観点として維持する。
- **Verification**: 静的検査（全呼出箇所が onlyOwner 文脈であること）


---

## 10. ガバナンス・運用・アップグレード要件（GOV）


コアの統治面の最大の特徴は「**デプロイ後にガバナンスが存在しない**」こと。upgrade・パラメータ変更・凍結・資金引出のいかなる管理権限も残らない（[Product-Overview](../Product-Overview.md) SYS-NFR-002/003 のコア側根拠）。

#### CORE-SYS-GOV-001: デプロイ時配線と権限の自己放棄 🔵
- **Type**: Governance ｜ **Source**: base 実装（AddressesRegistry / JpydfToken / Ownable）
- 配線用の owner 権限は 2 箇所のみ: `AddressesRegistry.setAddresses`（branch 配線、CORE-AR-FR-002。**実行と同時に `_renounceOwnership()`**）と `JpydfToken.setBranchAddresses` / `setCollateralRegistry`（mint/burn 権限の登録、CORE-BT-FR-002/003。`setBranchAddresses` は branch 数だけ反復可能で、**`setCollateralRegistry` の実行と同時に renounce** され全登録が恒久固定となる）。renounce 後は再実行・追加登録が恒久に不能（branch の後付け追加も不能）。
- **デプロイ後に残る特権的呼出関係はコントラクト間の only-X 制限（§4）のみ**で、EOA・マルチシグが持つ管理権限はゼロ。
- **Verification**: parity / deploy 検証（配線後に `owner() == address(0)` 相当・各 setter revert）
#### CORE-SYS-GOV-002: 非アップグレード性・パラメータ不変性 🔵
- コア全コントラクトと JpydfToken は non-upgradeable（proxy を用いない直デプロイ）。branch リスクパラメータ（MCR/CCR/SCR/BCR/清算ペナルティ）とコントラクト間配線は immutable / 一回設定で、デプロイ後の変更手段が存在しない。
- 帰結: パラメータ修正・コントラクト差替は**新ブランチの再デプロイ**でのみ可能。Day1値はbroadcast前にfreeze reviewを完了する。
- **Verification**: manual（コードレビュー: setter 不在・immutable 宣言）/ deploy 検証
#### CORE-SYS-GOV-003: デプロイゲート（値の機械検証） 🔵/🟡
- AddressesRegistry constructor の検証（`InvalidCCR/MCR/SCR/BCR`・ペナルティ順序、CORE-AR-FR-001）に加えて、デプロイ前に次を機械検証する: (a) `MIN_DEBT` が CORE-LIB-FR-002、`COLL_GAS_COMPENSATION_CAP` と DF ブランチ別値（CORE-MOD-003/005）が [Parameters.md](../../../Parameters.md) と一致、(b) [Parameter Catalog §4](../parameters/Parameter-Catalog.md#4-parameter-invariants) の`PRM-INV-*`、(c) 配線後の AddressesRegistry 全 getter が意図したアドレスを返すこと。
- **Verification**: deploy 検証（スクリプト）/ manual
#### CORE-SYS-GOV-004: 運用上の能動操作はインセンティブ駆動の permissionless 操作のみ 🔵
- コアの維持運用（清算・redemption・利息 mint・shutdown）はすべて permissionless で、運営の介入を前提としない。DF の運用責務は**監視と外部レイヤー側の対応**（清算 bot の LCG 走査＝CORE-LCG-FR-001、oracle 監視と source 差替＝[Oracle.md](./Oracle.md)、SP 流動性の確保）に限られる。
- **Verification**: manual（運用 runbook との整合）

---

## 11. イベント・監視要件（EVT）

> コントラクトごとの全イベント。off-chain（subgraph / 監視 / フロントエンド）はここを正本に index を構成する。コアのイベントは base と同一（🟡 差分はイベントに影響しない。DFStabilityPool のイベント面も StabilityPool と同一）。


### BorrowerOperations のイベント（CORE-BO-EVT-*）

| ID | Event | 発火箇所 | indexed | off-chain 用途 |
| --- | --- | --- | --- | --- |
| CORE-BO-EVT-001 | `TroveManagerAddressChanged(address)` | constructor | なし | デプロイ配線の監査 |
| CORE-BO-EVT-002 | `GasPoolAddressChanged(address)` | constructor | なし | 同上 |
| CORE-BO-EVT-003 | `CollSurplusPoolAddressChanged(address)` | constructor | なし | 同上 |
| CORE-BO-EVT-004 | `SortedTrovesAddressChanged(address)` | constructor | なし | 同上 |
| CORE-BO-EVT-005 | `JpydfTokenAddressChanged(address)` | constructor | なし | 同上 |
| CORE-BO-EVT-006 | `ShutDown(uint256 _tcr)` | `shutdown()`（TCR < SCR 経路のみ。oracle 失敗経路では発火しない） | なし | ブランチ shutdown の即時アラート・shutdown 時 TCR の記録 |
| CORE-BO-EVT-007 | `TroveNFTAddressChanged(address)` | constructor（AddRemoveManagers） | なし | デプロイ配線の監査 |
| CORE-BO-EVT-008 | `AddManagerUpdated(uint256 indexed _troveId, address _newAddManager)` | `setAddManager` / `openTrove` 系（常に発火）/ `closeTrove`・`onLiquidateTrove`（ゼロ化） | `_troveId` | Trove 委任状態の追跡（フロントエンド表示・委任監査） |
| CORE-BO-EVT-009 | `RemoveManagerAndReceiverUpdated(uint256 indexed _troveId, address _newRemoveManager, address _newReceiver)` | `setRemoveManager(WithReceiver)` / `openTrove` 系（常に発火）/ `closeTrove`・`onLiquidateTrove`（ゼロ化） | `_troveId` | 同上（receiver 変更の監視は資金流出先の監査に重要） |
| CORE-BO-EVT-010 | `ActivePoolAddressChanged(address)` | constructor（LiquityBase） | なし | デプロイ配線の監査 |
| CORE-BO-EVT-011 | `DefaultPoolAddressChanged(address)` | constructor（LiquityBase） | なし | 同上 |
| CORE-BO-EVT-012 | `PriceFeedAddressChanged(address)` | constructor（LiquityBase） | なし | 同上 |

Trove のライフサイクル系イベント（開設・調整・閉鎖・金利変更・batch 操作）は BO からは発火されず、TroveManager 側（CORE-TM 系の `TroveOperation` / `TroveUpdated` / `BatchUpdated` 等）で観測する。


### TroveManager のイベント（CORE-TM-EVT-*）

| ID | Event | 発火箇所 | indexed | off-chain 用途 |
| --- | --- | --- | --- | --- |
| CORE-TM-EVT-001 | `Liquidation(uint256 _debtOffsetBySP, uint256 _debtRedistributed, uint256 _jpydfGasCompensation, uint256 _collGasCompensation, uint256 _collSentToSP, uint256 _collRedistributed, uint256 _collSurplus, uint256 _L_ETH, uint256 _L_jpydfDebt, uint256 _price)` | `batchLiquidateTroves`（1 回/呼出） | なし | 清算規模・配分の監視、redistribution 累計値の追跡 |
| CORE-TM-EVT-002 | `Redemption(uint256 _attemptedJpydfAmount, uint256 _actualJpydfAmount, uint256 _ETHSent, uint256 _ETHFee, uint256 _price, uint256 _redemptionPrice)` | `redeemCollateral` / `urgentRedemption`（1 回/呼出） | なし | 償還量・fee・使用価格の監視 |
| CORE-TM-EVT-003 | `TroveUpdated(uint256 indexed _troveId, uint256 _debt, uint256 _coll, uint256 _stake, uint256 _annualInterestRate, uint256 _snapshotOfTotalCollRedist, uint256 _snapshotOfTotalDebtRedist)` | Trove の状態変化全般（非 batch の調整・金利変更等。**batch 所属でも** `onApplyTroveInterest` では発火〔このとき `_annualInterestRate` は Trove 個別保持値＝batch 所属では 0〕、閉鎖・清算では全 Trove で全ゼロ値発火） | `_troveId` | Trove 状態のインデックス（subgraph の正） |
| CORE-TM-EVT-004 | `TroveOperation(uint256 indexed _troveId, Operation _operation, uint256 _annualInterestRate, uint256 _debtIncreaseFromRedist, uint256 _debtIncreaseFromUpfrontFee, int256 _debtChangeFromOperation, uint256 _collIncreaseFromRedist, int256 _collChangeFromOperation)` | Trove に対する全操作 | `_troveId` | 操作履歴・変化要因の分解（操作/redistribution/upfront fee） |
| CORE-TM-EVT-005 | `RedemptionFeePaidToTrove(uint256 indexed _troveId, uint256 _ETHFee)` | `_applySingleRedemption`（Trove ごと） | `_troveId` | Trove に残置された redemption fee の追跡 |
| CORE-TM-EVT-006 | `BatchUpdated(address indexed _interestBatchManager, BatchOperation _operation, uint256 _debt, uint256 _coll, uint256 _annualInterestRate, uint256 _annualManagementFee, uint256 _totalDebtShares, uint256 _debtIncreaseFromUpfrontFee)` | batch に関わる全操作 | `_interestBatchManager` | batch 状態のインデックス |
| CORE-TM-EVT-007 | `BatchedTroveUpdated(uint256 indexed _troveId, address _interestBatchManager, uint256 _batchDebtShares, uint256 _coll, uint256 _stake, uint256 _snapshotOfTotalCollRedist, uint256 _snapshotOfTotalDebtRedist)` | batch 所属 Trove の状態変化 | `_troveId` | batch 所属 Trove の状態（debt は shares から導出） |
| CORE-TM-EVT-008 | アドレス配線イベント群: `TroveNFTAddressChanged` / `BorrowerOperationsAddressChanged` / `StabilityPoolAddressChanged` / `GasPoolAddressChanged` / `CollSurplusPoolAddressChanged` / `JpydfTokenAddressChanged` / `SortedTrovesAddressChanged` / `CollateralRegistryAddressChanged`（TroveManager）+ `ActivePoolAddressChanged` / `DefaultPoolAddressChanged` / `PriceFeedAddressChanged`（LiquityBase 継承）— 各 `(address)` | constructor のみ（1 回限り） | なし | デプロイ時の配線検証 |

**CORE-TM-EVT-001 `Liquidation` のフィールド意味**（`batchLiquidateTroves` の累計値）

| フィールド | 意味 |
| --- | --- |
| `_debtOffsetBySP` | SP offset で消滅した債務合計（`totals.debtToOffset`） |
| `_debtRedistributed` | redistribution された債務合計 |
| `_jpydfGasCompensation` | 清算者へ支払われた **WETH** ガス補償合計（`ETH_GAS_COMPENSATION × 清算件数`。フィールド名は v1 由来で BOLD ではない） |
| `_collGasCompensation` | 清算者へ支払われた担保ガス補償合計 |
| `_collSentToSP` | SP へ送られた担保合計（ガス補償控除・ペナルティ適用後） |
| `_collRedistributed` | redistribution された担保合計 |
| `_collSurplus` | CollSurplusPool に記帳された借り手返還分合計 |
| `_L_ETH` / `_L_jpydfDebt` | 更新**後**の `L_coll` / `L_jpydfDebt`（フィールド名 `_L_ETH` は v1 由来、実体は担保） |
| `_price` | 清算判定に使用した価格（`fetchPrice` の返り値） |

**CORE-TM-EVT-002 `Redemption` のフィールド意味**

| フィールド | 意味 |
| --- | --- |
| `_attemptedJpydfAmount` | 要求された償還額（`_jpydfAmount` / `_jpydfAmount`） |
| `_actualJpydfAmount` | 実際に償還された債務合計（要求未達あり得る） |
| `_ETHSent` | redeemer へ送られた担保合計（fee 控除後） |
| `_ETHFee` | Trove 群に残置された redemption fee 合計（urgentRedemption では常に 0） |
| `_price` | 通常価格（ICR 判定用に渡された値。urgent では fetchPrice 値） |
| `_redemptionPrice` | 担保換算に使った償還価格（urgent では通常価格と同値） |

**CORE-TM-EVT-003/004/005/006/007 の補足**

- `TroveUpdated`: 操作後の絶対値スナップショット。`_snapshotOfTotal*Redist` は当該 Trove の `rewardSnapshots` 新値（= 発火時点の `L_coll` / `L_jpydfDebt`）。閉鎖・清算時は全フィールド 0。
- `TroveOperation._operation`（enum `Operation`、uint8）: `0 openTrove / 1 closeTrove / 2 adjustTrove / 3 adjustTroveInterestRate / 4 applyPendingDebt / 5 liquidate / 6 redeemCollateral / 7 openTroveAndJoinBatch / 8 setInterestBatchManager / 9 removeFromBatch`。`_debtChangeFromOperation` / `_collChangeFromOperation` は int256（清算では entire 値のマイナス、redemption では lot のマイナス）。redistribution 由来増分・upfront fee 由来増分は別フィールドに分解される。
- `RedemptionFeePaidToTrove._ETHFee`: 当該 Trove の担保に残った fee（collLot から控除された分。Trove の CR を改善）。
- `BatchUpdated._operation`（enum `BatchOperation`、uint8）: `0 registerBatchManager / 1 lowerBatchManagerAnnualFee / 2 setBatchManagerAnnualInterestRate / 3 applyBatchInterestAndFee / 4 joinBatch / 5 exitBatch / 6 troveChange`。`_debtIncreaseFromUpfrontFee` は batch 全体に課された upfront fee のみ非 0（`setBatchManagerAnnualInterestRate` 時。個別 Trove の fee は含めない）。`_debt` / `_coll` は原則 `batches` の更新後生値（`applyBatchInterestAndFee` のみ引数の確定値）。
- `BatchedTroveUpdated`: batch 所属 Trove は記録債務を持たないため `_debt` の代わりに `_batchDebtShares` を運ぶ。


### StabilityPool / DFStabilityPool のイベント（CORE-SP-EVT-*）

`DepositOperation` の `Operation` enum は `provideToSP = 0` / `withdrawFromSP = 1` / `claimAllCollGains = 2`（IStabilityPoolEvents.sol）。

| ID | Event | 発火箇所 | indexed | off-chain 用途 |
| --- | --- | --- | --- | --- |
| CORE-SP-EVT-001 | `DepositOperation(address _depositor, Operation _operation, uint256 _depositLossSinceLastOperation, int256 _topUpOrWithdrawal, uint256 _yieldGainSinceLastOperation, uint256 _yieldGainClaimed, uint256 _ethGainSinceLastOperation, uint256 _ethGainClaimed)` | provideToSP / withdrawFromSP / claimAllCollGains | `_depositor` | 預金者操作の履歴・PnL 集計（清算損・入出金・利回り・担保ゲインの内訳）。担保フィールド名は legacy の `ethGain` 表記だが内容は collToken（dToken）量 |
| CORE-SP-EVT-002 | `DepositUpdated(address _depositor, uint256 _newDeposit, uint256 _stashedColl, uint256 _snapshotP, uint256 _snapshotS, uint256 _snapshotB, uint256 _snapshotScale)` | _updateDepositAndSnapshots（provideToSP / withdrawFromSP）/ claimAllCollGains | `_depositor` | 預金者の現在預金・stash・スナップショットの追跡（subgraph の口座状態再構築） |
| CORE-SP-EVT-003 | `StabilityPoolJpydfBalanceUpdated(uint256 _newBalance)` | _updateTotalJpydfDeposits（provideToSP / withdrawFromSP / offset） | — | `totalJpydfDeposits` の時系列監視 |
| CORE-SP-EVT-004 | `StabilityPoolCollBalanceUpdated(uint256 _newBalance)` | _moveOffsetCollAndDebt（offset）/ _sendCollGainToDepositor（各精算） | — | `collBalance` の時系列監視 |
| CORE-SP-EVT-005 | `P_Updated(uint256 _P)` | offset | — | 減耗率の追跡・オフチェーンでのゲイン再計算 |
| CORE-SP-EVT-006 | `S_Updated(uint256 _S, uint256 _scale)` | offset | — | scale 別担保ゲイン累積和の追跡 |
| CORE-SP-EVT-007 | `B_Updated(uint256 _B, uint256 _scale)` | _updateYieldRewardsSum（triggerJpydfRewards / provideToSP 末尾） | — | scale 別利回りゲイン累積和の追跡 |
| CORE-SP-EVT-008 | `ScaleUpdated(uint256 _currentScale)` | offset（scale ループ内、繰り上げごと） | — | scale 変化の検知（ゲイン計算の scale 跨ぎ判定） |
| CORE-SP-EVT-009 | `TroveManagerAddressChanged(address)` | constructor | — | デプロイ時配線の確認 |
| CORE-SP-EVT-010 | `JpydfTokenAddressChanged(address)` | constructor | — | 同上 |
| CORE-SP-EVT-011 | `ActivePoolAddressChanged(address)` | constructor（LiquityBase） | — | 同上 |
| CORE-SP-EVT-012 | `DefaultPoolAddressChanged(address)` | constructor（LiquityBase） | — | 同上 |
| CORE-SP-EVT-013 | `PriceFeedAddressChanged(address)` | constructor（LiquityBase） | — | 同上 |

（DFStabilityPool のイベント集合は StabilityPool と完全に同一。ガード由来の追加イベントはない）


### ActivePool のイベント（CORE-AP-EVT-*）

| ID | Event | 発火箇所 | indexed | off-chain 用途 |
| --- | --- | --- | --- | --- |
| CORE-AP-EVT-001 | `CollTokenAddressChanged(address _newCollTokenAddress)` | コンストラクタのみ | なし | デプロイ配線の監査 |
| CORE-AP-EVT-002 | `BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress)` | コンストラクタのみ | なし | 同上 |
| CORE-AP-EVT-003 | `TroveManagerAddressChanged(address _newTroveManagerAddress)` | コンストラクタのみ | なし | 同上 |
| CORE-AP-EVT-004 | `DefaultPoolAddressChanged(address _newDefaultPoolAddress)` | コンストラクタのみ | なし | 同上 |
| CORE-AP-EVT-005 | `StabilityPoolAddressChanged(address _newStabilityPoolAddress)` | コンストラクタのみ | なし | 同上 |
| CORE-AP-EVT-007 | `ActivePoolCollBalanceUpdated(uint256 _collBalance)` | `_accountForSendColl` / `_accountForReceivedColl`（sendColl / sendCollToDefaultPool / receiveColl / accountForReceivedColl の全担保会計変更） | なし | ブランチ担保残高の追跡・監視 |
| CORE-AP-EVT-008 🟡 | `ActivePoolAggRecordedDebtUpdated(uint256 _aggRecordedDebt)` | `mintAggInterestAndAccountForTroveChange` / `mintAggInterest` / `_mintBatchManagementFeeAndAccountForChange` | なし | 集計記録債務の追跡・監視（CORE-MOD-011） |
| CORE-AP-EVT-009 🟡 | `ActivePoolAggWeightedDebtSumUpdated(uint256 _aggWeightedDebtSum)` | `mintAggInterestAndAccountForTroveChange` | なし | 加重債務和の追跡・監視（CORE-MOD-011） |
| CORE-AP-EVT-010 🟡 | `ActivePoolAggBatchManagementFeesUpdated(uint256 _aggBatchManagementFees)` | `_mintBatchManagementFeeAndAccountForChange` | なし | batch 管理 fee 集計の追跡・監視（CORE-MOD-011） |
| CORE-AP-EVT-011 🟡 | `ActivePoolAggWeightedBatchManagementFeeSumUpdated(uint256 _aggWeightedBatchManagementFeeSum)` | `_mintBatchManagementFeeAndAccountForChange` | なし | batch 管理 fee 加重和の追跡・監視（CORE-MOD-011） |
| CORE-AP-EVT-012 🟡 | `AggregateInterestMinted(address indexed _jpydfToken, address indexed _stabilityPool, address indexed _interestRouter, uint256 _pendingAggInterest, uint256 _upfrontFee, uint256 _mintedAmount, uint256 _spYield, uint256 _interestRouterYield)` | `_mintAggInterest`（`mintedAmount > 0`） | `_jpydfToken`, `_stabilityPool`, `_interestRouter` | 外部 fee/revenue 集計（DeFiLlama 等）。`_mintedAmount = gross fees`、`_spYield = supply-side`、`_interestRouterYield = PIL / InterestRouter 側` |
| CORE-AP-EVT-013 🟡 | `BatchManagementFeeMinted(address indexed _jpydfToken, address indexed _batchManager, uint256 _batchManagementFee)` | `_mintBatchManagementFeeAndAccountForChange`（`batchAccruedManagementFee > 0`） | `_jpydfToken`, `_batchManager` | batch manager fee の外部集計・分類。protocol revenue と混同せず、必要時に別カテゴリとして扱う |


### DefaultPool のイベント（CORE-DP-EVT-*）

| ID | Event | 発火箇所 | indexed | off-chain 用途 |
| --- | --- | --- | --- | --- |
| CORE-DP-EVT-001 | `CollTokenAddressChanged(address _newCollTokenAddress)` | コンストラクタのみ | なし | デプロイ配線の監査 |
| CORE-DP-EVT-002 | `ActivePoolAddressChanged(address _newActivePoolAddress)` | コンストラクタのみ | なし | 同上 |
| CORE-DP-EVT-003 | `TroveManagerAddressChanged(address _newTroveManagerAddress)` | コンストラクタのみ | なし | 同上 |
| CORE-DP-EVT-004 | `DefaultPoolJpydfDebtUpdated(uint256 _jpydfDebt)` | increaseJpydfDebt / decreaseJpydfDebt | なし | redistribution 待ち負債の追跡 |
| CORE-DP-EVT-005 | `DefaultPoolCollBalanceUpdated(uint256 _collBalance)` | sendCollToActivePool / receiveColl | なし | redistribution 待ち担保の追跡 |


### CollSurplusPool のイベント（CORE-CSP-EVT-*）

| ID | Event | 発火箇所 | indexed | off-chain 用途 |
| --- | --- | --- | --- | --- |
| CORE-CSP-EVT-001 | `BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress)` | コンストラクタのみ | なし | デプロイ配線の監査 |
| CORE-CSP-EVT-002 | `TroveManagerAddressChanged(address _newTroveManagerAddress)` | コンストラクタのみ | なし | 同上 |
| CORE-CSP-EVT-003 | `CollBalanceUpdated(address indexed _account, uint256 _newBalance)` | accountSurplus（記帳時）/ claimColl（ゼロ化時） | `_account` | アカウント別 claim 可能残高の追跡・claim 可否の通知 |
| CORE-CSP-EVT-004 | `CollSent(address indexed _to, uint256 _amount)` | claimColl | `_to` | 払い出しの記録 |


### GasPool のイベント（CORE-GP-EVT-*）

| ID | Event | 発火箇所 | indexed | off-chain 用途 |
| --- | --- | --- | --- | --- |
| （定義なし） | — | — | — | — |


### SortedTroves のイベント（CORE-ST-EVT-*）

| ID | Event | 発火箇所 | indexed | off-chain 用途 |
| --- | --- | --- | --- | --- |
| CORE-ST-EVT-001 | `TroveManagerAddressChanged(address _troveManagerAddress)` | constructor のみ（1 回） | なし | デプロイ時の配線（TM アドレス）確認 |
| CORE-ST-EVT-002 | `BorrowerOperationsAddressChanged(address _borrowerOperationsAddress)` | constructor のみ（1 回） | なし | デプロイ時の配線（BO アドレス）確認 |

- 注: **リスト操作（insert/remove/reInsert 系）はイベントを発火しない**。リスト状態の off-chain 再構成は BO / TM 側のイベント（TroveOperation 等）から行う。


### TroveNFT のイベント（CORE-TN-EVT-*）

| ID | Event | 発火箇所 | indexed | off-chain 用途 |
| --- | --- | --- | --- | --- |
| CORE-TN-EVT-001 | `Transfer(address indexed from, address indexed to, uint256 indexed tokenId)` | mint（from=0）/ burn（to=0）/ 移転 | from / to / tokenId | Trove 所有権の index（subgraph・フロントの保有 Trove 一覧） |
| CORE-TN-EVT-002 | `Approval(address indexed owner, address indexed approved, uint256 indexed tokenId)` | `approve` | 3 引数すべて | 承認状態の追跡 |
| CORE-TN-EVT-003 | `ApprovalForAll(address indexed owner, address indexed operator, bool approved)` | `setApprovalForAll` | owner / operator | operator 承認の追跡 |

（いずれも OZ v4.9 ERC721 標準イベント。TroveNFT・MetadataNFT 固有のイベントはない）


### JpydfToken のイベント（CORE-BT-EVT-*）

→ 規範は [JpydfToken.md](./JpydfToken.md) §11（`CORE-BT-EVT-001..010`）。

### CollateralRegistry のイベント（CORE-CR-EVT-*）

| ID | Event | 発火箇所 | indexed | off-chain 用途 |
| --- | --- | --- | --- | --- |
| CORE-CR-EVT-001 | `BaseRateUpdated(uint256 _baseRate)` | constructor（初期値）/ `redeemCollateral` | なし | redemption rate の推移監視・fee 見積りの基礎 |
| CORE-CR-EVT-002 | `LastFeeOpTimeUpdated(uint256 _lastFeeOpTime)` | `redeemCollateral`（経過 1 分以上の場合のみ） | なし | decay 基準時刻の追跡（rate 再現計算用） |


### AddressesRegistry のイベント（CORE-AR-EVT-*）

| ID | Event | 発火箇所 | indexed | off-chain 用途 |
| --- | --- | --- | --- | --- |
| CORE-AR-EVT-001 | `CollTokenAddressChanged(address)` | `setAddresses` | なし | branch 配線の監査・subgraph 初期化（以下同） |
| CORE-AR-EVT-002 | `BorrowerOperationsAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-003 | `TroveManagerAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-004 | `TroveNFTAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-005 | `MetadataNFTAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-006 | `StabilityPoolAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-007 | `PriceFeedAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-008 | `ActivePoolAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-009 | `DefaultPoolAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-010 | `GasPoolAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-011 | `CollSurplusPoolAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-012 | `SortedTrovesAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-013 | `InterestRouterAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-014 | `HintHelpersAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-015 | `MultiTroveGetterAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-016 | `CollateralRegistryAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-017 | `JpydfTokenAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-018 | `WETHAddressChanged(address)` | `setAddresses` | なし | 〃 |
| CORE-AR-EVT-019 | `OwnershipTransferred(address previousOwner, address newOwner)` | constructor / `_renounceOwnership` | previousOwner, newOwner | Owner 設定・renounce（newOwner=0、配線完了の指標）の検知 |


### HintHelpers のイベント（CORE-HH-EVT-*）

該当なし（本コントラクトはイベントを定義・発火しない）。


### MultiTroveGetter のイベント（CORE-MTG-EVT-*）

該当なし（本コントラクトはイベントを定義・発火しない）。


### DebtInFrontHelper のイベント（CORE-DFH-EVT-*）

該当なし（本コントラクトはイベントを定義・発火しない）。


### RedemptionHelper のイベント（CORE-RH-EVT-*）

該当なし（本コントラクトはイベントを定義・発火しない。償還の観測は CR / TM / JpydfToken のイベントによる）。


### LiquidationCandidateGetter のイベント（CORE-LCG-EVT-*）

該当なし（本コントラクトはイベントを定義・発火しない）。


### Constants.sol のイベント（CORE-LIB-EVT-*）

該当なし（file-level 定数はイベントを定義・発火しない）。


### LiquityBase のイベント（CORE-LIB-EVT-*）

| ID | Event | 発火箇所 | indexed | off-chain 用途 |
| --- | --- | --- | --- | --- |
| CORE-LIB-EVT-001 | `ActivePoolAddressChanged(address _newActivePoolAddress)` | constructor（CORE-LIB-FR-005） | なし | デプロイ時の配線記録（継承コントラクト = BO/TM/SP/DFStabilityPool それぞれから 1 回発火） |
| CORE-LIB-EVT-002 | `DefaultPoolAddressChanged(address _newDefaultPoolAddress)` | 同上 | なし | 同上 |
| CORE-LIB-EVT-003 | `PriceFeedAddressChanged(address _newPriceFeedAddress)` | 同上 | なし | 同上（AddressesRegistry も同名イベントを持つが別宣言。CORE-AR） |


### LiquityMath のイベント（CORE-LIB-EVT-*）

該当なし。


### Ownable のイベント（CORE-LIB-EVT-*）

| ID | Event | 発火箇所 | indexed | off-chain 用途 |
| --- | --- | --- | --- | --- |
| CORE-LIB-EVT-004 | `OwnershipTransferred(address indexed previousOwner, address indexed newOwner)` | constructor（0 → initialOwner）／ `_renounceOwnership`（owner → 0） | previousOwner, newOwner | デプロイ・配線完了（ownerless 化）の監視。`newOwner == address(0)` の観測 = 配線確定の合図 |


### Types のイベント（CORE-LIB-EVT-*）

該当なし（型定義のみ）。


---

## 12. 失敗時・異常系挙動（ERR）

> まずシステムレベルの異常系シナリオ（CORE-SYS-ERR-*）を規定し、続いてコントラクト別の異常系（revert 一覧・縮退挙動）を示す。

### 12.1 システムレベルの異常系（CORE-SYS-ERR-*）

#### CORE-SYS-ERR-001: オラクル障害カスケード 🔵
- priceFeed（PriceFeedProxy。[Oracle.md](./Oracle.md)）が `fetchPrice()` で新規障害を検出すると、priceFeed が `BO.shutdownFromOracleFailure()` を呼び、当該ブランチは shutdown する（CORE-BO-FR-022）。同 tx 内の借入系操作は `NewOracleFailureDetected` で revert する（CORE-BO-ERR-004）。
- 障害検出後の価格は lastGoodPrice 系の縮退値となり（Oracle 層の責務）、コアは shutdown 後モード（CORE-SYS-ERR-003）で動き続ける。`closeTrove` は oracle 障害下でも実行可能（撤退経路の確保）。
- **Verification**: integration（Oracle 層と結合）/ parity
#### CORE-SYS-ERR-002: クリティカルモード（TCR < CCR） 🔵
- ブランチ TCR が CCR を下回ると、BO は「TCR を悪化させる調整」を拒否する制限モードに入る（規範は CORE-BO-ERR-001: 借入は TCR ≥ CCR 回復時のみ・担保引出は同価値以上の返済併用時のみ・upfront fee 検査の適用継続）。清算・redemption・SP 操作は通常どおり。金利調整はクールダウン経過後の無料変更のみ通常どおりで、upfront fee を伴う経路（premature 変更・batch 加入等）は fee 込み TCR ≥ CCR 要求により実質不可（CORE-BO-FR-011/017）。
- モードは価格回復・債務返済・清算により TCR ≥ CCR へ戻れば自動解除される（フラグではなく都度判定）。
- **Verification**: parity / unit（モードマトリクス）
#### CORE-SYS-ERR-003: ブランチ shutdown（不可逆縮退） 🔵
- トリガーは 2 経路: `TCR < SCR` での permissionless `BO.shutdown()`（CORE-BO-FR-021）と oracle 障害（CORE-SYS-ERR-001）。効果: 利息 accrual の恒久停止（CORE-AP-FR-014）・借入系操作の凍結（CORE-BO-ERR-003 の可否マトリクス）・通常 redemption の対象外化（CORE-TM-FR-012 の redeemable=false）・**urgent redemption の解禁**（手数料 0・`URGENT_REDEMPTION_BONUS` 付き、CORE-TM-FR-005）。
- 復旧手段は存在しない（不可逆）。残債務は urgent redemption・返済・清算で巻き取り、借り手は `closeTrove` / `claimCollateral` で撤退する。
- **Verification**: parity / unit（shutdown 後マトリクス）
#### CORE-SYS-ERR-004: SP 枯渇時の清算縮退 🔵
- 清算時に SP の利用可能残高（`totalJpydfDeposits − MIN_JPYDF_IN_SP`）が不足する場合、不足分は redistribution（より高いペナルティ）へフォールバックする（CORE-TM-FR-002 の分岐）。SP が完全に空でも清算は止まらない（pure redistribution）。清算者がその場で `provideToSP` してから清算する JIT 経路も常に開いている（🟡 DFStabilityPool でも同一 tx 内の「預入→清算」は可能。禁止されるのは同一ブロック内の**担保ゲイン払出と出金**＝CORE-MOD-004）。
- **Verification**: parity / unit（3 分岐）
#### CORE-SYS-ERR-005: zombie Trove のライフサイクル 🔵
- redemption の部分償還で `debt < MIN_DEBT`（🟡 CORE-MOD-002）となった Trove は zombie となり、SortedTroves から除外される（通常 redemption の対象外。直近の発生 1 件のみ `lastZombieTroveId` として次回 redemption で優先処理される）。zombie は利息 accrual・redistribution 受領・清算対象であり続け、`adjustZombieTrove`（または redistribution 回復後の permissionless `applyPendingDebt`）で MIN_DEBT 以上へ回復すれば active へ復帰、全額返済で close できる（CORE-BO-FR-008/009/010、CORE-TM-FR-016/021）。
- 監視上の注意: zombie は SortedTroves 走査だけでは現れない。清算監視は LCG の `getLiquidationCandidatesWithLastZombie` または `getLastZombieLiquidationCandidate` で `lastZombieTroveId` も確認する（CORE-LCG-FR-003）。
- **Verification**: parity / unit


### BorrowerOperations の異常系（CORE-BO-ERR-*）

#### CORE-BO-ERR-001: TCR < CCR（クリティカル閾値未満）時の調整制限 🔵

- Type: Error-handling
- Statement: 調整前 TCR < CCR のとき、`_requireValidAdjustmentInCurrentMode` により次のとおり制限される。
  - 借入（debtIncrease > 0）は調整後 TCR ≥ CCR に回復する場合のみ許可（違反は `TCRBelowCCR`）
  - 担保引出は同価値以上の債務返済を伴う場合のみ許可（`debtDecrease × 1e18 ≥ collDecrease × price`。違反は `RepaymentNotMatchingCollWithdrawal`）
  - ICR 要求（MCR / MCR+BCR）は通常時と同一に適用
  - 通常時に要求される「調整後 TCR ≥ CCR」はクリティカル時には課されない（担保追加・返済等で TCR が CCR 未満のまま改善する操作を許す）
- Verification: parity / unit（モード別マトリクス）

#### CORE-BO-ERR-002: 返済額の silent cap 🔵

- Type: Error-handling
- Statement: 返済（debtDecrease）は `entireDebt − MIN_DEBT` を超える指定をしても revert せず自動縮小される（MIN_DEBT は 🟡 DF 値、CORE-MOD-002 / CORE-LIB-FR-002）。`entireDebt ≤ MIN_DEBT`（zombie 等）では 0 に縮小され、他成分もゼロなら `ZeroAdjustment` に帰着する。全額返済は `closeTrove` のみで可能。フロントエンド・Zapper は「指定額より少なく返済される」ケースを前提にすること。
- Verification: parity / unit

#### CORE-BO-ERR-003: shutdown 後の関数可否 🔵

- Type: Error-handling
- Statement: `hasBeenShutDown == true` の間、次のとおり振る舞う。
  - **可能**: `closeTrove`（TCR 検査免除）/ `claimCollateral` / `setAddManager` / `setRemoveManager(WithReceiver)` / `removeInterestIndividualDelegate` / `onLiquidateTrove` / view 全件
  - **`IsShutDown` で revert**: `openTrove` / `openTroveAndJoinInterestBatchManager` / `adjustTrove`・`addColl`・`withdrawColl`・`withdrawJpydf`・`repayJpydf` / `adjustZombieTrove` / `adjustTroveInterestRate` / `applyPendingDebt` / `setInterestIndividualDelegate` / `registerBatchManager` / `lowerBatchManagementFee` / `setBatchManagerAnnualInterestRate` / `setInterestBatchManager` / `removeFromBatch` / `kickFromBatch` / `switchBatchManager`（内部呼出経由）/ `shutdown`（再実行）
  - **no-op return**: `shutdownFromOracleFailure`
- Verification: parity / unit（shutdown 後マトリクス）

#### CORE-BO-ERR-004: oracle 失敗時の挙動 🔵

- Type: Error-handling
- Statement: `fetchPrice()` が新規 oracle 失敗を検出した場合（PriceFeedProxy。[Oracle.md](./Oracle.md)）、価格を要する借入系操作（開設・調整・premature 金利変更・batch 加入/離脱の fee 経路・batch 一括金利変更の fee 経路）は `NewOracleFailureDetected` で revert する。このとき fetchPrice の内部連鎖（PriceFeed → FR-022）で当該ブランチは shutdown 済みとなる。例外として `closeTrove` は oracle 失敗でも revert せず（shutdown 連鎖後は TCR 検査も免除され）閉鎖を継続でき、`shutdown()` は oracle 失敗検出時に revert ではなく早期 return する。
- Verification: parity / unit


### TroveManager の異常系（CORE-TM-ERR-*）

#### CORE-TM-ERR-001: batchLiquidateTroves の失敗時挙動 🔵
空配列 → `EmptyData`。走査の結果 1 件も清算できなかった → `NothingToLiquidate`（部分成功は許容: 1 件でも清算されれば残りのスキップは成功扱い）。Verification: unit。

#### CORE-TM-ERR-002: redeemCollateral はゼロ償還でも成功する 🔵
全候補が ICR < 100% 等で 0 件償還に終わっても revert しない（base が意図的に require を撤去）。CollateralRegistry のブランチ横断処理を 1 ブランチの空振りで止めないため。呼出側は返り値（償還実額）で判定する。Verification: parity / unit。

#### CORE-TM-ERR-003: urgentRedemption の失敗時挙動 🔵
未 shutdown → `NotShutDown`、`_jpydfAmount == 0` → `ZeroAmount`、呼出者 JPYdf 残高不足 → `NotEnoughJpydfBalance`、受領担保が `_minCollateral` 未満 → `MinCollNotReached(実受領額)`。対象外 Trove（非 active/zombie・entireDebt 0）はスキップであり revert しない。Verification: unit。

#### CORE-TM-ERR-004: 最後の 1 Trove の閉鎖禁止 🔵
未 shutdown ブランチでの owner 閉鎖、および（shutdown 有無によらず）清算による閉鎖は、`TroveIds.length == 1` のとき `OnlyOneTroveLeft` で失敗する。shutdown 後の owner 閉鎖のみ最後の 1 件を許す。Verification: parity / unit。

#### CORE-TM-ERR-005: BatchSharesRatioTooHigh 🔵
debt/shares 比が上限を超えた batch への債務追加（開設加入・調整・利息適用・batch 加入）は `BatchSharesRatioTooHigh` で失敗する。Redemption は対象外（CORE-TM-SEC-006）。Verification: unit。


### StabilityPool / DFStabilityPool の異常系（CORE-SP-ERR-*）

#### CORE-SP-ERR-001: 預金者操作の revert 一覧 🔵
| 関数 | 条件 | revert 文字列 |
| --- | --- | --- |
| provideToSP | `_topUp == 0` | `"StabilityPool: Amount must be non-zero"` |
| withdrawFromSP | 預金なし | `"StabilityPool: User must have a non-zero deposit"` |
| withdrawFromSP | 引出後 `totalJpydfDeposits < MIN_JPYDF_IN_SP` | `"Withdrawal must leave totalJpydfDeposits >= MIN_JPYDF_IN_SP"` |
| claimAllCollGains | 預金あり | `"StabilityPool: User must have no deposit"` |
| claimAllCollGains | stash が 0 | `"StabilityPool: Amount must be non-zero"` |
- Verification: unit / parity。

#### CORE-SP-ERR-002: same-block 担保ゲイン claim・出金の revert 🟡
- DFStabilityPool の `provideToSP(..., true)` は、同一ブロック内に `provideToSP` 済みで current または stash 済み担保ゲインを持つ既存預金者に対し `"StabilityPool: Coll gain claim must wait after deposit"` で revert する。`withdrawFromSP` は同じ呼出者に対し `"StabilityPool: Withdrawal must wait after deposit"` で revert する（CORE-SP-FR-004、CORE-MOD-004（§2 DF 差分台帳））。StabilityPool（base 規範）にはこれらの revert は存在しない。
- Verification: unit。

#### CORE-SP-ERR-003: 特権関数の前提違反時挙動 🔵
- `offset` / `triggerJpydfRewards` の非許可呼出はそれぞれ `"StabilityPool: Caller is not TroveManager"` / `"StabilityPool: Caller is not ActivePool"` で revert。
- `offset` を `totalJpydfDeposits == 0` で呼んだ場合は除算 panic（Panic 0x12）、`_debtToOffset == totalJpydfDeposits` で呼んだ場合は `"P must never decrease to 0"` で revert する。いずれも TroveManager の清算ロジックが到達させない前提条件違反であり、SP 単体では入力検証を持たない（コントラクト横断の整合は CORE-SYS-INV-011）。
- Verification: unit（境界呼出）/ parity。


### ActivePool の異常系（CORE-AP-ERR-*）

#### CORE-AP-ERR-001: 失敗時挙動（require 文字列・算術 revert）🔵
| 経路 | 条件 | revert |
| --- | --- | --- |
| receiveColl / accountForReceivedColl | 呼出元が BO/DP 以外 | `"ActivePool: Caller is neither BO nor Default Pool"` |
| sendColl | 呼出元が BO/TM/SP 以外 | `"ActivePool: Caller is neither BorrowerOperations nor TroveManager nor StabilityPool"` |
| mintAggInterest | 呼出元が BO/SP 以外 | `"ActivePool: Caller is not BorrowerOperations nor StabilityPool"` |
| mintAggInterestAndAccountForTroveChange | 呼出元が BO/TM 以外 | `"ActivePool: Caller is neither BorrowerOperations nor TroveManager"` |
| sendCollToDefaultPool / mintBatchManagementFeeAndAccountForChange / setShutdownFlag | 呼出元が TM 以外 | `"ActivePool: Caller is not TroveManager"` |
| getNewApproxAvgInterestRateFromTroveChange | `upfrontFee != 0` | assert 失敗（Panic 0x01） |
| 会計演算全般 | 減算が残高・トラッカーを超過 | Panic 0x11（Solidity 0.8 checked） |

- **Verification**: unit / parity


### DefaultPool の異常系（CORE-DP-ERR-*）

#### CORE-DP-ERR-001: 失敗時挙動 🔵
| 経路 | 条件 | revert |
| --- | --- | --- |
| receiveColl | 呼出元が AP 以外 | `"DefaultPool: Caller is not the ActivePool"` |
| sendCollToActivePool / increaseJpydfDebt / decreaseJpydfDebt | 呼出元が TM 以外 | `"DefaultPool: Caller is not the TroveManager"` |
| sendCollToActivePool / decreaseJpydfDebt | 減算超過 | Panic 0x11（checked 演算） |

- **Verification**: unit / parity


### CollSurplusPool の異常系（CORE-CSP-ERR-*）

#### CORE-CSP-ERR-001: 失敗時挙動 🔵
| 経路 | 条件 | revert |
| --- | --- | --- |
| accountSurplus | 呼出元が TM 以外 | `"CollSurplusPool: Caller is not TroveManager"` |
| claimColl | 呼出元が BO 以外 | `"CollSurplusPool: Caller is not Borrower Operations"` |
| claimColl | `balances[_account] == 0` | `"CollSurplusPool: No collateral available to claim"` |

- **Verification**: unit / parity


### SortedTroves の異常系（CORE-ST-ERR-*）

#### CORE-ST-ERR-001: revert 文字列一覧 🔵
カスタムエラーは未使用。すべて require 文字列:

| 文字列 | 発生箇所 |
| --- | --- |
| `"SortedTroves: Caller is not BorrowerOperations"` | insert / reInsert / insertIntoBatch / reInsertBatch |
| `"SortedTroves: Caller is not BorrowerOperations nor TroveManager"` | remove / removeFromBatch |
| `"SortedTroves: List already contains the node"` | insert / insertIntoBatch |
| `"SortedTroves: _id cannot be the root node's ID"` | insert |
| `"SortedTroves: _troveId cannot be the root node's ID"` | insertIntoBatch |
| `"SortedTroves: _batchId cannot be zero"` | insertIntoBatch |
| `"SortedTroves: List does not contain the id"` | remove / reInsert |
| `"SortedTroves: Must use removeFromBatch() to remove batched node"` | remove |
| `"SortedTroves: Must not reInsert() batched node"` | reInsert |
| `"SortedTroves: Must use remove() to remove non-batched node"` | removeFromBatch |
| `"SortedTroves: List does not contain the batch"` | reInsertBatch |


### TroveNFT の異常系（CORE-TN-ERR-*）

#### CORE-TN-ERR-001: revert 文字列 / custom error 一覧 🔵/🟡
Deployed DF surface は非 TM の mint/burn に 1 つの custom error を使う。継承した OZ v4.9 ERC-721 の失敗は require string のまま。

| 文字列 / error | 発生箇所 |
| --- | --- |
| `JPYdfTroveNFT__CallerIsNotTroveManager()` | mint / burn（非 TM 呼出） |
| `"ERC721: mint to the zero address"` | mint（owner=0） |
| `"ERC721: token already minted"` | mint（重複 troveId） |
| `"ERC721: invalid token ID"` | burn / ownerOf / tokenURI / getApproved 等（不存在 token） |
| `"ERC721: caller is not token owner or approved"` ほか OZ v4.9 標準文字列 | transfer / approve 系 |


### JpydfToken の異常系（CORE-BT-ERR-*）

→ 規範は [JpydfToken.md](./JpydfToken.md) §12（`CORE-BT-ERR-001`）。

### CollateralRegistry の異常系（CORE-CR-ERR-*）

#### CORE-CR-ERR-001: 失敗時挙動（require 文字列）🔵
| 条件 | revert |
| --- | --- |
| `_maxFeePercentage` 範囲外 | `"Max fee percentage must be between 0.5% and 100%"` |
| `_jpydfAmount == 0` | `"CollateralRegistry: Amount must be greater than zero"` |
| 実効 rate > `_maxFeePercentage` | `"CR: Fee exceeded provided maximum"` |
| `getToken` / `getTroveManager` の index ≥ 10 | `"Invalid index"` |
| constructor: 空リスト / 11 以上 | `"Collateral list cannot be empty"` / `"Collateral list too long"` |
| burn 時残高不足 | `"ERC20: burn amount exceeds balance"`（JpydfToken 側） |


### AddressesRegistry の異常系（CORE-AR-ERR-*）

#### CORE-AR-ERR-001: 失敗時挙動（カスタムエラー）🔵
| 条件 | revert |
| --- | --- |
| `_ccr <= 1e18 || _ccr >= 2e18` | `InvalidCCR()` |
| `_mcr <= 1e18 || _mcr >= 2e18` | `InvalidMCR()` |
| `_bcr < 5e16 || _bcr >= 50e16` | `InvalidBCR()` |
| `_scr <= 1e18 || _scr >= 2e18` | `InvalidSCR()` |
| `_liquidationPenaltySP < MIN_LIQUIDATION_PENALTY_SP` | `SPPenaltyTooLow()` |
| `_liquidationPenaltySP > _liquidationPenaltyRedistribution` | `SPPenaltyGtRedist()` |
| `_liquidationPenaltyRedistribution > MAX_LIQUIDATION_PENALTY_REDISTRIBUTION` | `RedistPenaltyTooHigh()` |
| 非 Owner の `setAddresses` | `"Ownable: caller is not the owner"` |


### HintHelpers の異常系（CORE-HH-ERR-*）

#### CORE-HH-ERR-001: 無効な _collIndex 🔵
`_collIndex` が CollateralRegistry の登録ブランチ範囲外の場合: スロット上限以上は `CollateralRegistry.getTroveManager` の revert（`"Invalid index"`）、スロット範囲内の未登録 index は `address(0)` への view 呼出失敗として revert する（明示エラーなし）。


### MultiTroveGetter の異常系（CORE-MTG-ERR-*）

#### CORE-MTG-ERR-001: 無効な _collIndex 🔵
`getTroveManager(_collIndex)` が `address(0)` を返すスロット → require `"Invalid collateral index"` で revert。スロット上限以上は CollateralRegistry 側の revert（`"Invalid index"`）。`sortedTroves` 未設定は assert（Panic）であり通常到達しない。


### DebtInFrontHelper の異常系（CORE-DFH-ERR-*）

#### CORE-DFH-ERR-001: 無効な _collIndex 🔵
`getTroveManager(_collIndex)` が `address(0)` → require `"Invalid collateral index"`。スロット上限以上は CollateralRegistry 側 revert（`"Invalid index"`）。


### RedemptionHelper の異常系（CORE-RH-ERR-*）

#### CORE-RH-ERR-001: 失敗時挙動 🔵
| 条件 | 挙動 |
| --- | --- |
| `_jpydf == 0` | require `"Redeemed amount must be non-zero"` |
| `_minCollRedeemed.length != numBranches` | require `"Wrong _minCollRedeemed length"` |
| ブランチ受領担保 < `_minCollRedeemed[i]` | require `"Insufficient collateral redeemed"`（全体 revert＝all-or-nothing） |
| fee 率 > `_maxFeePct` | CR 側 require `"CR: Fee exceeded provided maximum"` が伝播 |
| approve / JPYdf 残高不足 | `transferFrom` の revert が伝播 |
| constructor 不整合 | `"Wrong number of registries"` / `"TroveManager mismatch"` |


### LiquidationCandidateGetter の異常系（CORE-LCG-ERR-*）

#### CORE-LCG-ERR-001: 無効な _collIndex 🟢
constructor の registry zero → `LiquidationCandidateGetter__InvalidCollateralRegistry`。`getTroveManager(_collIndex)` が `address(0)` → `LiquidationCandidateGetter__InvalidCollateralIndex`。スロット上限以上は CollateralRegistry 側 revert（`"Invalid index"`）。


### LiquityBase の異常系（CORE-LIB-ERR-*）

#### CORE-LIB-ERR-001: 算術 Panic のみ（カスタムエラーなし） 🔵
LiquityBase（および LiquityMath）はカスタムエラー・require を持たず、失敗モードは Solidity 0.8 checked 算術の Panic（乗算 overflow 等）に限られる。`_calcInterest` は `_weightedDebt * _period` が uint256 を超えるパラメータ域で revert するが、上流の利率上限（`MAX_ANNUAL_INTEREST_RATE` = 250%）・現実的な経過時間の範囲では到達しない。
- **Verification**: fuzz（境界域での Panic 確認）

「ブランチ集計負債 ≥ Σ Trove entireDebt」（_calcInterest の floor と ActivePool ceilDiv の組み合わせで成立）は CORE-SYS-INV-001 が規定する。


### Ownable の異常系（CORE-LIB-ERR-*）

#### CORE-LIB-ERR-002: onlyOwner 違反の revert 🔵
`onlyOwner` 違反はカスタムエラーではなく require 文字列 `"Ownable: caller is not the owner"` で revert する（core 内の他コントラクトのカスタムエラー方針と異なる点に注意）。
- **Verification**: unit（文字列一致）


---

## 13. 受け入れ基準・検証計画


本仕様の受け入れ基準は「**コアがフォーク元（base）と同一に機能していること**」と「**DF 差分が台帳どおりに限定されていること**」の 2 点に集約される。検証は次の 4 層で行う。

### 13.1 検証手段の語彙（各 FR の Verification 行が使う）

| 手段 | 意味 |
| --- | --- |
| `parity` | **フォーク元同一性検証**。(a) 静的: base との差分が §2.2 台帳・§5.1 カタログと一致することの diff review / script 照合、(b) 動的: 当該関数・状態変数の挙動（状態変化・revert・イベント・返り値）が base 実装または台帳化された差分と一致することのテスト。🔵 要件の既定 |
| `unit` | 関数単位の正常系・境界・revert テスト |
| `fuzz` | 入力をランダム化した性質テスト |
| `invariant` | §8 の不変条件を対象とした invariant テスト（操作列をランダム実行して恒等式を検査） |
| `fork` | mainnet fork 上での実コントラクト結合テスト |
| `integration` | 🟢 独自レイヤー（dToken / Oracle 等）と結合した経路テスト |
| `deploy 検証` | デプロイスクリプト・デプロイ後検査での機械検証（CORE-SYS-GOV-003） |
| `manual` | コードレビュー・運用手順との突合 |

### 13.2 4 層の保証構造

1. **静的 parity（diff review / script 照合）** — 現行 CI の Core JPYDF surface guard は旧 BOLD public/API 名の再混入を機械検出する。base との差分そのものは、§2.2 CORE-MOD 台帳・§5.1 カタログ・ソース diff により確認し、許容差分（Constants 値・debt-token JPYdf 命名 surface・deployment variant・SafeERC20 hardening・observability event・legacy route pruning・新規追加ファイル）だけで構成されることをレビュー / 補助スクリプトで担保する。
2. **挙動 parity（テスト）** — 本書の全 FR を対象に、🔵 は base 挙動との同一性、🟡 は「base 挙動＋台帳どおりの差分のみ」を検証する。特に DFStabilityPool は (a) StabilityPool と同一の挙動（ガード以外の全 FR・全 INV が同値に成立）、(b) CORE-MOD-004 の 4 点差分が意図どおり機能（same-block 担保ゲイン claim/出金 revert・no-claim stash 成功・担保ゲインなし top-up と新規預入の成功・翌ブロック成功・flash loan 経路不成立）、(c) 差分がこの 4 点に限られること（ソース diff の機械確認）を要する。
3. **不変条件（invariant テスト）** — §8 の CORE-SYS-INV-* とコントラクト別 INV を invariant suite で常時検査する。
4. **デプロイゲート** — CORE-SYS-GOV-003 の機械検証（Constants ⇔ Parameters.md 一致・関係式・配線・権限放棄）。

### 13.3 受け入れ基準

- [ ] CI: Core JPYDF surface guard が green（旧 BOLD public/API 名の再混入ゼロ）
- [ ] 本書の全 FR / INV / SEC / ERR が、対応する Verification 手段のテストまたはレビュー記録でカバーされている（ID 参照によるトレース。テスト名は本書に書かない＝[標準](../../../Requirements-Spec-Standard.md)ガードレール）
- [ ] §5.1 カタログの全コントラクトについて、ABI 上の全 external/public 関数が §6 のいずれかの FR に対応している（網羅性の機械照合）
- [ ] DFStabilityPool ⇔ StabilityPool のソース diff が CORE-MOD-004 記載の機能差分 4 点（＋コントラクト名置換・helper 定義）以外を含まない
- [ ] `MIN_DEBT` が CORE-LIB-FR-002、`COLL_GAS_COMPENSATION_CAP` とブランチ別値が [Parameters.md](../../../Parameters.md) と一致（CORE-MOD-002/003/005）
- [ ] rename / コメント / import-only cleanup を正規化した `base` 差分が §2.2 `CORE-MOD-*` 以外の非 rename 差分を含まない
- [ ] デプロイ検証: 配線・immutable 値・権限放棄（CORE-SYS-GOV-001/003）

> 個別 FR ⇔ テストの対応台帳は本書には置かない（揮発情報の排除）。テスト側が `@custom:requirement CORE-…` 等で ID を参照する一方向リンクを正とする。

---

## 14. 未決事項（TBD）

> コアは base 凍結のため「仕様自体の未決」は原則発生しない。本節の TBD は **DF としての採用・運用判断**が残っている事項に限られる。

#### CORE-AP-TBD-001: interestRouter の宛先（利息残余 25% の行き先）
Resolved: `CORE-AP-FR-007`、`CORE-AP-FR-008`、`IRTR-FR-001` に反映済み。

---

#### CORE-TN-TBD-001: コレクション name/symbol のデプロイ順序依存
Resolved: `CORE-TN-FR-001`、`CORE-TN-FR-006` に反映済み。

#### CORE-TN-TBD-002: NFT メタデータの deployment 文言
Resolved: `CORE-TN-FR-001`、`CORE-TN-FR-004`、`CORE-TN-FR-006` に反映済み。

#### CORE-LCG-TBD-001: zombie Trove の清算監視の責務分担 🟢
Resolved: `CORE-LCG-FR-001`、`CORE-LCG-FR-003` に反映済み。

#### CORE-LIB-TBD-001: inert ブランチ（Br2–7）の Day-1 確定値の activation 検証
dETH / dUSD-A / dBTC / dUSD-B / dJPY / dJGB の各定数は、Underlying 未 binding の inert 構成でも Day-1 に確定投入する。activation前にexact Underlyingのstressが [Collateral Parameter Policy](../policies/Collateral-Parameter-Policy.md) §2.4へ適合することを検証し、適合しないbranchはcapを開けずinertのまま維持する。

---


---

## 15. 参考資料


- [Liquity v2 Bold GitHub](https://github.com/liquity/bold) — フォーク元（`base` = v1.11.0 凍結）
- [Liquity Docs](https://docs.liquity.org/) — upstream の概念解説
- [Liquity Friendly Forks Program](https://www.liquity.org/forks)
- Scalable Reward Distribution with Compounding Stakes（Stability Pool の P-S-B 会計の数学的根拠。liquity/dev リポジトリ収載）

### DeltaForesight 関連ページ

- [Product-Overview](../Product-Overview.md) — システム要求・アーキテクチャ・ARCH・SYS-INV（Core parity / 差分境界の上位根拠）
- [Architecture Decision Records](../architecture/Architecture-Decision-Records.md) — Core parity等の設計理由
- [Parameters](../../../Parameters.md) — ブランチ別パラメータと `Constants.sol` 値の正本
- [dToken 要件定義](./dToken.md) — コアの担保トークン（DTKN-*）
- [CollateralVault 要件定義](./CollateralVault.md) — Underlying 保管・mint/redeem・backing 比（VAULT-*）
- [Strategy 要件定義](./strategies/Strategy.md) / [AaveV3Strategy](./strategies/AaveV3Strategy.md) — 担保運用（STGY-* / AAVE-*）
- [オラクル 要件定義](./Oracle.md) — PriceFeedProxy・JPY 建て合成・障害時 failsafe（ORCL-*）
- [Zapper 要件定義](./Zapper.md) — UX Router（ZAP-*）
- [Frontend 要件定義](./Frontend.md) — オフチェーン 3 サーフェス（FRNT-*）
