# Contract Business Catalog

## 0. このドキュメントの位置づけ

本書は、ビジネスサイド・非 Solidity レビュー担当者が「各コントラクトが何をしているか」を短時間で把握するための日本語カタログである。

- **対象**: `contracts/src` の production Solidity source のうち、Day-1 の product / audit / operation 理解に関係する主要コントラクト。
- **非目的**: 関数単位の仕様、パラメータ値、監査 finding、実装差分の網羅。
- **正本**: 厳密な仕様は [`Product-Overview.md`](../../protocol/product/Product-Overview.md)、[`Parameters.md`](../../Parameters.md)、各 [`spec/`](../../protocol/product/spec/) を正とする。本書と spec が食い違う場合は spec を正とする。
- **読み方**: まず §1 の全体像を読み、次に関心領域の表を見る。監査見積りや nSLOC は [`Contract-Audit-Scope-And-nSLOC.md`](./Contract-Audit-Scope-And-nSLOC.md) を参照する。

## 1. 全体像

JPYdf v2 は、大きく次の 5 つのレイヤーで構成される。

| レイヤー | ビジネス上の役割 | 主なコントラクト |
| --- | --- | --- |
| Liquity v2 Core | ユーザーが担保を入れて JPYdf を借りる、清算・償還される、金利が発生する基本システム | `BorrowerOperations`, `TroveManager`, `ActivePool`, `DFStabilityPool`, `CollateralRegistry` |
| JPYdf / dToken / Vault | 実資産や yield-bearing asset を Liquity Core が扱える 18 decimals の担保表現へ変換し、保管・運用・償還する | `JpydfToken`, `DToken`, `CollateralVault`, `Strategies/*` |
| Oracle | 担保価格を JPY 建てで Core に渡す。feed 差替や placeholder branch を扱う | `PriceFeedProxy`, `DFPriceFeedBase`, 担保別 price feed |
| Zapper / Route | ユーザー操作を1回のtransactionにまとめる。Day-1はgeneric ZapperとUniswap v4 final legを扱う | `CollateralYieldZapper`, `UniV4Exchange` |
| Interest / PIL / Operations | Core から発生する interest share や運用益を Day-1 の受け皿へ集め、PIL liquidity incentive を gate 付きで扱える形にする | `InterestRouterForwarder`, `PILAllocator`, `UniV4MerklInitiative`, strategy reward sweep |

### 1.1 Audit scope と Day-1 activation の読み分け

「監査対象に含む」は「Day-1 に user-facing / funded / active にする」と同じ意味ではない。Day-1 audit scope は、production `contracts/src` に残る資金・会計・権限・route・incentive 影響面を広めに含める。一方で、実際に有効化する surface は deploy manifest、preflight、Safe / Timelock 承認、fork evidence、strategy selection evidence で狭く gate する。

| 状態 | ビジネス上の読み方 | 例 |
| --- | --- | --- |
| Day-1 active / planned active | launch package の gate を満たせば本番で使う想定 | Core、`JpydfToken`、`DToken`、`CollateralVault`、active price feeds、`CollateralYieldZapper` |
| Audit 対象だが gated | コードは存在し監査に入れるが、route / PIL / branch / manifest gate までは本番導線に出さない | `UniV4Exchange`、`PILAllocator`、`UniV4MerklInitiative`、bridge-ready dormant minter surface、cap-0 branch 周辺 |
| Day-2 / 未実装 | Day-1 contract audit scope 外。別 PR・別 audit package が必要 | `Treasury.sol`、SP 追加報酬 distributor、referral distributor、active bridge adapter |
| 削除済み / 存在しない | fresh deploy なので後方互換 shim は残さない | Curve、Balancer、Uniswap v3 route、flash-close、collateral-funded repay、Multiply、direct non-USDC JPYdf pool |

Strategy venue の現在の採用分類は [`Strategy-Selection-Policy.md`](../../protocol/operations/policies/Strategy-Selection-Policy.md) を正本とし、本カタログでは各 adapter の機能とリスクだけを説明する。

## 2. Core: 借入・清算・償還の本体

このレイヤーは Liquity v2 由来の挙動をできるだけ保つ。ビジネス上は「JPYdf を借りるプロトコル本体」と理解すればよい。

| Contract | 何をするか | ビジネス上の意味 | 主なリスク・確認観点 |
| --- | --- | --- | --- |
| `BorrowerOperations` | ユーザーの Trove 操作窓口。open / add collateral / withdraw collateral / borrow / repay / close などを受ける | 借入 UX の入口。ユーザーが担保を入れて JPYdf を受け取る場所 | manager 権限、fee、Trove 状態遷移、Zapper 経由時の受取先 |
| `TroveManager` | 各 Trove の debt / collateral / stake / liquidation 状態を管理する | 借入ポジション台帳。清算可能性や担保率の計算元 | debt accounting、stake redistribution、liquidation / redemption の境界 |
| `ActivePool` | active Trove の担保と debt 合計を持つ pool | まだ清算されていない担保・債務の集計場所 | aggregate accounting、approval、interest share の発生 |
| `DefaultPool` | 清算後、再分配待ちの担保・債務を一時的に持つ | 清算損益が他 Trove に再分配されるまでの中継 | redistribution accounting |
| `CollSurplusPool` | 清算や redemption 後に余った担保をユーザーが claim するための pool | ユーザーに返すべき余剰担保の保管先 | claim 権限、余剰計算 |
| `DFStabilityPool` | JPYdf depositor が清算を吸収し、担保報酬を得る pool。DF 版は同一 block withdrawal guard を追加 | JPYdf の安全弁。清算時の primary backstop | withdrawal timing guard、deposit accounting、報酬分配 |
| `CollateralRegistry` | 複数担保 branch の一覧と redemption / urgent redemption の入口を持つ | branch catalog。どの担保が active か、償還がどこへ向かうかを管理 | branch index、redemption ordering、shutdown 境界 |
| `SortedTroves` | Trove を利率や ICR 順に並べる補助構造 | redemption / liquidation / UI 表示の効率化 | hint、並び順、edge case |
| `RedemptionHelper` | redemption の実処理を補助する | JPYdf を返して担保を受け取る処理の中核補助 | min receive、branch shutdown、skip 条件 |
| `HintHelpers` / `MultiTroveGetter` | UI / Bot が効率よく Trove を探すための read helper | frontend / liquidator の探索補助 | read-only であること、pagination |
| `JPYdfTroveNFT` / `JPYdfMetadataNFT` | Trove ownership を NFT として表現し、tokenURI metadata を返す | Trove の所有権表示。wallet / explorer / UI に見える | ownership authorization、metadata 表示の正確性 |

## 3. JPY DeFi / dToken / Vault: 独自ビジネスレイヤー

このレイヤーは JPYdf v2 の独自性が強い。実資産や yield-bearing asset を Core に載せるための custody / accounting / yield integration である。

| Contract | 何をするか | ビジネス上の意味 | 主なリスク・確認観点 |
| --- | --- | --- | --- |
| `JpydfToken` | Core が mint / burn する debt token。Day-1 は bridge minter 0 の dormant bridge readiness を持つ | ユーザーが借りる JPY 建て stablecoin。Core 発行と将来 bridge 発行を分離 | Core mint 権限、bridge minter timelock、Day-1 minter 0、permit domain |
| `DToken` | Underlying を 18 decimals の担保 token に変換する ERC20。Vault だけが mint / burn できる | Liquity Core が扱いやすい担保表現。例: wstETH や USDC を dToken 化 | Vault binding、cap、underlying allowlist、decimals conversion |
| `CollateralVault` | Underlying を保管し、dToken mint / redeem、buffer、delayed withdrawal、strategy allocation を管理する | 実資産 custody と運用会計の本体 | 1:1 backing、buffer / queue、strategy loss、writeoff、upgrade boundary |
| `InterestRouterForwarder` | ActivePool から受ける interest share を現在の recipient へ転送する | Day-1 の PIL / Treasury 受け皿への simple forwarder | recipient 権限、route keeper、stuck funds |
| `PILAllocator` | 借入金利の PIL 分を registered initiative へ admin weight で配分する | 接続・initiative 登録・weight 設定後に稼働する配分器 | initiative 登録、weight 合計、bounded loop、carry-over、pause / guardian |
| `UniV4MerklInitiative` | PILAllocator から受けた JPYdf を Merkl campaign 作成へ使う initiative | JPYdf/USDC Uniswap v4 liquidity incentive の候補受け皿 | Merkl trust boundary、campaign threshold、epoch alignment、allowance hygiene |
| `LiquidationCandidateGetter` | 清算 Bot / frontend が清算候補を page 単位で取得する read helper | liquidator の探索効率を上げる運用補助 | invalid branch、bounded scan、zombie handling |

## 4. Strategy: Vault から外部 yield source へ資産を動かす

Strategy は「Vault が保管する Underlying の一部を外部 protocol に預け、利回りを得るための adapter」である。production source に存在する adapter は監査対象だが、実装済みであることは mainnet allocation の承認を意味しない。実際の active set は deploy manifest / preflight で gate する。

| Contract | 何をするか | ビジネス上の意味 | 主なリスク・確認観点 |
| --- | --- | --- | --- |
| `BaseStrategy` | 共通の push model、principal accounting、owner / upgrader、reward sweep を提供 | すべての strategy の標準運用ルール | onlyVault、principal tracking、emergency withdraw、upgrade authority |
| `AaveV3Strategy` | Underlying を Aave V3 に供給し、aToken position を持つ | Aave 経由の低摩擦な運用先 | aToken accounting、withdraw failure、Aave / Merkl reward |
| `ERC4626Strategy` | ERC-4626 vault に Underlying を預ける汎用 adapter | venue 固有コントラクトを増やさず ERC-4626 vault を接続する（Morpho Vault V2 は `MorphoV2Strategy` を使う） | share rounding、preview/convert assumptions、vault compatibility |
| `MorphoV2Strategy` | Morpho Vaults V2 vault に Underlying を預ける専用 adapter（max\* view 非依存・fail-soft 回収・上限付き `forceDeallocate` penalty） | Day-1 branch 1 の Morpho Vault V2 slot 用の監査済み専用 adapter | curator / queue 挙動、penalty 上限（200 bps 以下）、donation 排除、share resync |
| `LidoStrategy` | WETH を Lido に stake し、wstETH / Withdrawal Queue の非同期回収を扱う | 退役・archive 退避予定（監査済み成果物として保存） | pending withdrawal、claimable ETH、loss/writeoff、donation 分離、回収・登録解除 |
| `SkyUsdcSUsdsStrategy` | dUSDC の USDC を USDS / sUSDS に変換して運用し、USDC で回収する | asset 変換を伴う Sky 運用を USDC 建て会計へ戻す | converter trust、USDS/sUSDS rate、min-out、idle USDS、donation 無視 |
| `EtherfiWeETHStrategy` | WETH underlying branch の WETH を Ether.fi eETH / weETH に変換し、WithdrawRequestNFT 経由で非同期回収する | 退役・archive 退避予定（wstETH branch swap に伴う。監査済み成果物として保存） | pending NFT、claimable ETH、LRT/slashing/depeg、keeper、donation 無視 |

## 5. Oracle: JPY 建て価格を Core に渡す

Oracle は「担保が JPYdf debt に対して十分か」を決める。価格 feed が間違うと、借入上限、清算、償還がすべて影響を受ける。

| Contract | 何をするか | ビジネス上の意味 | 主なリスク・確認観点 |
| --- | --- | --- | --- |
| `PriceFeedProxy` | Core に固定される feed address。裏側の source を timelock 付きで差し替える | Core を再 deploy せずに oracle source を交換する安全弁 | source replacement、smoke test、owner handover、no-renounce |
| `DFPriceFeedBase` | collateral/USD と USD/JPY を合成し、JPY 建て価格を出す DF 共通基底 | JPYdf のための価格変換ロジック | stale price、invalid response、lastGoodPrice |
| `DFUSDCPriceFeed` / `DFWstETHPriceFeed` | Day-1 active collateralのJPY価格feed | dUSDC / dwstETH branchの価格 | depeg / wrapper rate、staleness、JPY freeze |
| `CompositePriceFeed` | canonical rateとmarket feedを合成する共通基底 | activeなdwstETH feedを支える部品 | canonical rate、lastGoodPrice fallback |
| `PriceFeedPlaceholder` | inert branch 用の placeholder feed | 未使用 branch を accidental activation しにくくする | active branch に誤配線しないこと |
| `MainnetPriceFeedBase` | upstream 由来 feed base | base-parity を保った価格取得部品。deploy されない upstream WETH wrapper と WSTETH / RETH collateral feed は削除済み | upstream parity、rate source |

## 6. Zapper / Route: ユーザー操作をまとめる

Zapperは「ユーザーが複数stepを理解しなくても、安全な順序で操作できるようにするUX router」である。Day-1ではopen / add / withdraw / close-with-JPYdfが中心で、swap-backed close / MultiplyはABIに存在しない。

| Contract | 何をするか | ビジネス上の意味 | 主なリスク・確認観点 |
| --- | --- | --- | --- |
| `BaseZapper` | Trove manager 権限、receiver guard、共通 helper を提供 | Zapper 操作の authorization 基盤 | manager / receiver mismatch、owner vs automation |
| `AddRemoveManagers` | Trove の add manager / remove manager + receiver を管理する | cold wallet / bot / automation に権限を委任する仕組み | manager 権限の範囲、receiver 設定 |
| `LeftoversSweep` | Zapper / exchange の操作後に余った token を返す helper | ユーザー資産の取り残し防止 | leftover accounting、unexpected residue |
| `CollateralYieldZapper` | Underlying deposit -> Vault -> dToken collateral -> Core 操作を 1 tx にまとめる | dToken branch の主要 user UX | allowance、leftover、min underlying、receiver、reentrancy |
| `UniV4Exchange` | JPYdf/USDC Uniswap v4 final leg の `IExchange` adapter | 将来の swap route / evidence 対象。Day-1 audit scope には含めるが user-facing route は gate 後 | Universal Router / Permit2 allowance、pool key、hook policy、JPYdf->coll exact-output / coll->JPYdf exact-input |
| `V4RouterCodec` | Universal Router / v4 action command の byte 定義 | adapter が v4 router に渡す command の部品 | command byte correctness |

Candidate固有の`DFUSDTPriceFeed` / `DFWBTCPriceFeed` / `DFXAUTPriceFeed` / `sUSDSPriceFeed` / `SkyUsdcSUsdsYieldZapper`は`contracts/src/**/archive/`へ隔離され、official deploy pathとactive audit scopeには含まれない。

## 7. Interface / Library / Helper の見方

| 種類 | 例 | ビジネス上の扱い |
| --- | --- | --- |
| Interface | `I*` files | 実装ではなく ABI と意味の約束。監査では interface consistency として見る |
| Types | `TroveId`, `LatestTroveData`, `TroveChange` など | Core / frontend / helper が同じ data shape を共有するための型 |
| Math / Dependencies | `LiquityMath`, `Constants`, `SignedMath` など | パラメータ・計算・共通 guard。値は `Parameters.md` と照合する |
| Vendored libraries | `contracts/lib/**` | dependency。通常は JPYdf audit nSLOC には含めない |

## 8. Day-1 で「存在しない」または「まだ user-facing ではない」もの

| 項目 | Day-1 の扱い |
| --- | --- |
| Active bridge protocol / other-chain deployment | 実装・接続しない。`JpydfToken` は dormant readiness のみ |
| dToken / yield-bearing token の bridge | 初期 bridge scope 外 |
| Curve / Balancer / Uniswap v3 route | 採用しない。production `src` には戻さない |
| USDT / USDS / WETH / XAUT などの JPYdf 直接 pool | Day-1 liquidity policy では作らない |
| JPYdf/USDC Uniswap v4 | Day-1 の標準 liquidity。ただし `UniV4Exchange` の user-facing 配線は route config / fork evidence / manifest gate 後 |
| flash-close / collateral-funded repay / Multiply | Day-1 contract ABI に存在しない。将来提供する場合は新しい audited entrypoint として追加 |
| Day-2 Treasury / reward distributors | `Treasury.sol` / SP 追加報酬 distributor / referral distributor は Day-1 production implementation ではない。Safe 留保から切り替える場合は別 PR・別 audit package |

## 9. 読むべき詳細仕様

| 知りたいこと | 詳細仕様 |
| --- | --- |
| 全体の事業・scope・非 scope | [`Product-Overview.md`](../../protocol/product/Product-Overview.md) |
| 担保・リスクパラメータ | [`Parameters.md`](../../Parameters.md) |
| Core の関数仕様 | [`Liquity-v2-Core-Spec.md`](../../protocol/product/spec/Liquity-v2-Core-Spec.md) |
| dToken / Vault / Strategy | [`dToken.md`](../../protocol/product/spec/dToken.md), [`CollateralVault.md`](../../protocol/product/spec/CollateralVault.md), [`Strategy.md`](../../protocol/product/spec/strategies/Strategy.md) |
| Oracle | [`Oracle.md`](../../protocol/product/spec/Oracle.md) |
| Zapper / route | [`Zapper.md`](../../protocol/product/spec/Zapper.md), [`Liquidity-Route-Policy.md`](../../protocol/product/policies/Liquidity-Route-Policy.md) |
| Treasury / Interest | [`Treasury.md`](../../protocol/roadmap/spec/Treasury.md), [`InterestRouter.md`](../../protocol/product/spec/InterestRouter.md) |
| Audit scope / nSLOC | [`Contract-Audit-Scope-And-nSLOC.md`](./Contract-Audit-Scope-And-nSLOC.md) |
