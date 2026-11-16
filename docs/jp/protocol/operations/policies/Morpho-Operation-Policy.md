# Morpho 運用ポリシー

## 位置づけ

本書は、JPYdf が Morpho を担保運用先 Strategy venue として採用する場合の、
運用形態、vault / market 選定、配分、role、oracle / LLTV / IRM、監視、緊急対応を定める
設計ポリシーである。

関連文書の責務は次の通り。

| 文書 | 責務 |
| --- | --- |
| 本書 | Morpho 固有の運用 gate、role 設計、market / vault 選定、監視、incident 対応 |
| [`Strategy-Selection-Policy.md`](./Strategy-Selection-Policy.md) | 外部 Strategy venue を採用してよいかの横断 gate |
| [`Collateral-Asset-Management-Policy.md`](./Collateral-Asset-Management-Policy.md) | Day-1 branch 構成、候補 venue、既存 adapter の対応範囲 |
| [`../../spec/strategies/ERC4626Strategy.md`](../../product/spec/strategies/ERC4626Strategy.md) | `ERC4626Strategy` の contract 仕様、`asset()==underlying`、`maxWithdraw` / `maxRedeem` を使う回収モデル |
| [`../../spec/strategies/MorphoV2Strategy.md`](../../product/spec/strategies/MorphoV2Strategy.md) | Morpho Vaults V2 向け `MorphoV2Strategy` の contract 仕様: max\* view 非依存、fail-soft 回収、`forceDeallocate` wrapper、penalty 上限 |
| [`../../spec/strategies/Strategy.md`](../../product/spec/strategies/Strategy.md) | Strategy 共通仕様、push model、権限、会計、不変条件 |
| [`../../Parameters.md`](../../../Parameters.md) | branch mapping、mintCap、buffer、withdrawDelay 等の Day-1 値 |
| [`Deployment-Configuration-Spec.md`](../../../engineering/guides/Deployment-Configuration-Spec.md) | deploy mode、wiring shape、manifest schema、env validation |
| [`Mainnet-Deploy-Env-Freeze-Runbook.md`](../../launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md) | Day-1 の Strategy kind・cap・weightをenvへ凍結し、生成Manifestと照合する手順 |
| [`../runbooks/Morpho-Day1-Vault-Freeze-Package.md`](../../launch/gates/Morpho-Day1-Vault-Freeze-Package.md) | Day-1 実採用 vault、curator、oracle、queue、bad debt、withdrawability の freeze package |
| [`../runbooks/Strategy-Incident-Liquidation-Safety-Runbook.md`](../runbooks/Strategy-Incident-Liquidation-Safety-Runbook.md) | Strategy incident 時の allocation stop、回収、清算安全性の判断 |
| [`Vault-Buffer-Shortfall-User-Comms-Runbook.md`](../../../contributors/deltaforesight/operations/Vault-Buffer-Shortfall-User-Comms-Runbook.md) | Vault buffer 不足や delayed claim 時の user communication |

Morpho は `dUSDC`（Branch 1）の **Day-1 planned active venue（条件付き）** である。branch 2–7 は Day-1 実配分がないため、Morpho path は各 branch の cap 判断 / activation 判断と同時に検討する。
ただし本書は、特定 vault address / cap / weight を単独で承認するものではない。実 allocation
には、本書の gate、branch 運用値、Strategy deploy 値、preflight、fork evidence、ops / frontend gate、
Safe / Timelock evidence を揃えた activation package が必要である。deploy freeze までに evidence
が揃わない場合は、原則として launch blocker として扱う。安易な Aave-only launch や cap 引き下げを
fallback として採ることは、Day-1 の経済設計、流動性計画、監査 scope、ユーザー説明を崩すため
認めない。例外的に Morpho allocation を外す場合は、新しい Day-1 scope 変更として governance /
product / risk / contracts が明示承認し、branch 運用値、Strategy deploy 値、preflight、frontend / ops gate、
runbook、public explanation を更新する。

## 決定事項

1. **採用経路は `asset()==branch underlying` の vault-share adapter に限定する**。Morpho を Day-1
   から使う場合、`ERC4626Strategy`（V1 / MetaMorpho）または専用 `MorphoV2Strategy`（Vaults V2）で
   表現できる vault に限定する。USDC を別 asset に変換する route や、Morpho market を直接操作する
   adapter は本書では承認しない。
2. **Day-1 採用は第三者 curated vault への supply を優先する**。DeltaForesight 自前 curated vault は
   role / allocator / cap / queue / market selection / incident response の運用 scope が大きいため、
   Day-2 以降または別 activation package とする。
3. **Morpho Vault V2 の rejection は supersede 済み（2026-08-05）: V2 は専用 `MorphoV2Strategy` 経由の
   条件付き採用とし、`ERC4626Strategy` 経由では引き続き No-Go**。Vault V2 は ERC-4626 interface を
   持つが、公式実装上 `maxDeposit` / `maxMint` / `maxWithdraw` / `maxRedeem` が常に 0 を返す設計で
   あり、`maxWithdraw(this)` / `maxRedeem(this)` を回収上限に使う `ERC4626Strategy` では通常回収・
   緊急回収の evidence を満たせない — 元決定のこの部分は有効なままである。ただしこの blocker は
   adapter 固有であり、merge 済みの
   [`MorphoV2Strategy`](../../product/spec/strategies/MorphoV2Strategy.md)（kind `morpho-v2`）は
   max\* view を参照せず、自身が追跡する share で clamp し、liquidity-short withdraw を fail-soft
   にし、`forceDeallocate` を init 凍結の penalty 上限付き wrapper で包む。従って V2 採用は一律
   rejection ではなく、下記 V2 gate 行、activation package、external audit を条件とする。
4. **MetaMorpho / Morpho Vault V1 系の conventional ERC-4626 vault を Day-1 互換系統にする**。ただし
   `asset()==underlying`、`convertToAssets`、`maxWithdraw` / `maxRedeem`、role、timelock、cap、
   queue、fee、underlying market の全てを activation package で freeze する。
5. **Public Allocator 依存は default off**。第三者が reallocation を実行できる仕組みは exit 補助に
   なりうるが、max flow、fee、admin、queue 変更、悪用時の影響を freeze するまで採用 evidence に
   含めない。
6. **vault / market の採用評価は 6 軸評価フレームワークで記録する**。軸ごとに
   `PASS / REVIEW / BLOCKER` を付け、`BLOCKER` が 1 つでもあれば Day-1 allocation を開けない。
   `REVIEW` は risk owner が issue 上で accept / cap-down / reject を明示するまで未承認として扱う。
   評価軸と分類ルールは「Market / 担保選定基準」の 6 軸評価フレームワークに定める。

## 運用形態

| 形態 | Day-1 方針 | 主な責務・リスク |
| --- | --- | --- |
| 第三者 curated MetaMorpho / Morpho Vault V1 へ supply | Day-1 planned active path（dUSDC のみ。他 branch は cap / activation 判断後）。`ERC4626Strategy` で `asset()==underlying` を満たし、activation evidence が揃う場合のみ | 外部 curator / owner / allocator / guardian を trust boundary として扱う。DF は Strategy cap / weight / buffer / monitoring / emergency withdraw を管理する |
| DeltaForesight 自前 curated vault | Day-2 または別 activation package | DF が market selection、cap、queue、allocator、guardian、incident response を直接負う。専用 role mapping、運用 bot、Safe calldata、market risk scoring、監視が必要 |
| Morpho Vault V2 | 専用 `MorphoV2Strategy`（kind `morpho-v2`）経由の条件付き採用。`ERC4626Strategy` 経由は引き続き No-Go | `maxWithdraw` / `maxRedeem` が設計上 0 のため `ERC4626Strategy` の回収 gate を満たせない。`MorphoV2Strategy` は max\* view に依存しない。採用には下記 V2 gate 行、activation package、external audit が必要。Day-1 対象は branch 1 dUSDC。branch 0（wstETH）は信頼できる wstETH 建て V2 vault を待つ |
| Morpho Blue market 直接操作 | 本書の scope 外 | ERC-4626 share 会計ではなく、直接 supply / withdraw / collateral / borrow surface を扱うため専用 Strategy と audit が必要 |

第三者 curated vault を使う場合でも、DF は「外部 curator が選んだ market に間接 exposure を持つ」
状態になる。従って、vault address だけではなく、実際に cap が設定されている market、supply queue、
withdraw queue、owner / curator / guardian / allocator、timelock pending action を監視対象に含める。

## Adapter / Preflight Gate

Morpho vault を `ERC4626Strategy` として登録する前に、activation package で最低限以下を証跡化する。

| Gate | 必須内容 |
| --- | --- |
| Chain / source | Ethereum mainnet の公式 source から address を取得し、proxy / implementation / code hash / deployment source を freeze する |
| Asset match | `IERC4626.asset() == branch underlying`。branch 1 は USDC、他 branch は当該 branch に binding 済みの Underlying と完全一致すること |
| Decimals / token behavior | underlying decimals、share decimals、fee-on-transfer / rebasing / blacklist / transfer restriction の有無を確認する |
| Share price | `convertToAssets(10 ** decimals)` と `convertToShares` の readback を取り、bad debt / loss 反映モデルを説明する |
| Withdrawability | 正常時に `maxWithdraw(strategy)` / `maxRedeem(strategy)` が 0 ではなく、partial withdraw と full withdraw の fork dry-run が通ること |
| Emergency path | `sendToVault`、`emergencyWithdrawFromERC4626`、partial recovery、残 principal writeoff の dry-run を添付する |
| Governance / role | owner、curator、guardian / sentinel、allocator、fee recipient、timelock、pending action、upgrade / registry / gate 権限を freeze する |
| Market exposure | vault が供給する market の loanToken、collateralToken、oracle、IRM、LLTV、supply cap、current exposure、queue position を freeze する |
| Monitoring | share price、maxWithdraw、market utilization、oracle、role change、cap / queue change、bad debt、withdrawal failure の alert owner を決める |

`maxWithdraw` / `maxRedeem` が 0 の vault は、通常の流動性不足か仕様上の常時 0 かを切り分ける。
Vault V2 のように仕様上 0 の場合は `ERC4626Strategy` では採用せず、`MorphoV2Strategy` と下記の
V2 gate 行を経由する。単なる一時的な流動性不足の場合は、loss ではなく exit / allocation の
operational risk として扱い、cap / weight 引き下げ、allocation pause、withdraw queue 調整、
backstop の要否を判断する。

Morpho Vaults V2 vault を `MorphoV2Strategy`（kind `morpho-v2`）として登録する前には、
activation package に追加で最低限次を証跡化する。

| V2 Gate | 必須内容 |
| --- | --- |
| Adapter registry | 登録済み adapter set（ID・address・対象 protocol）を readback し、各 adapter を説明できること。説明できない adapter は blocker |
| Gates unset | 4 つの gate（receive-shares / send-shares / receive-assets / send-assets）が全て unset であること。設置は curator timelock 対象だが、設置済み gate の allowlist は address を即時凍結できるため unset を freeze 基準とする |
| Sentinel | Sentinel が設定され、holder / escalation path を説明できること |
| maxRate | `maxRate` が nonzero で監視されていること — deploy デフォルトは 0 で yield を全額留保する。zero-`maxRate` venue の受容は risk owner の明示承認が必要 |
| Per-selector timelocks | selector ごとの timelock 値を vault 単位で readback すること。**デフォルトは 0** であり、nonzero は protocol 保証ではなく freeze checklist 項目 |
| forceDeallocate penalty | 全 adapter の `forceDeallocatePenalty` が Strategy の init 凍結 `maxForceDeallocatePenaltyBps`（protocol 上限 2%）以下であること |
| Adapter liquidity | adapter ごとの deallocatable liquidity readback と vault idle 残高。idle + `forceDeallocate` dry-run が、ERC-4626 vault で使う max\* ベースの withdrawability evidence を代替する |

## Market / 担保選定基準

第三者 curated vault では、DF は market を直接設定しない。それでも、採用時点で実 exposure を持つ
market と cap が開いている market は DF の間接 risk であるため、以下を満たさない vault は採用しない。

| 項目 | 採用基準 |
| --- | --- |
| loan asset | branch underlying と同一。WETH branch なら WETH、USDC branch なら USDC |
| collateral asset | mainnet 流動性、発行体 / custody、oracle coverage、depeg / slashing / bridge risk を説明できる |
| oracle | source、scaling、staleness、upgrade / admin、fallback、異常値時の liveness を確認できる |
| LLTV | collateral volatility と liquidation liquidity に対して保守的で、急落時に bad debt を作りにくい |
| IRM | enabled IRM で、revert / extreme rate / admin change の liveness risk を説明できる |
| market health | utilization、available liquidity、bad debt history、liquidation path、supplier exit depth を確認できる |
| cap / queue | supply cap、withdraw queue、supply queue が採用目的と一致し、unsafe market を前方 queue に置かない |

自前 curated vault を運用する場合は、上記に加えて market を次の分類で扱う。

| 分類 | 方針 |
| --- | --- |
| Base market | ETH / BTC / major stable collateral など、流動性、oracle、清算実績、counterparty risk を説明できる market。初期候補にできる |
| Case-by-case market | LST、yield-bearing share、issuer / custody risk が強い stable、集中流動性の asset。個別 risk memo と低い cap が必要 |
| Rejected market | long-tail collateral、unverified oracle、bridge-only asset、illiquid collateral、share-token collateral を oracle review なしで使う market |

Vault share を別 market の collateral にする recursive 構造、または vault-share AUM oracle に依存する
構造は、oracle manipulation と bad debt 伝播の説明が完了するまで採用しない。

### 6 軸評価フレームワーク

採用候補の vault と market は、次の 6 軸で評価し、軸ごとに `PASS / REVIEW / BLOCKER` を記録する。

| 軸 | 評価対象 | PASS | REVIEW | BLOCKER |
| --- | --- | --- | --- | --- |
| A 監視リスク・コスト | curator / queue / role / market 構成の監視負荷 | 単純で dashboard / alert 化できる | 複合構造、Public Allocator、頻繁な queue / cap 変更があり owner 明確化が必要 | ブラックボックス、role / queue / cap 変更を追跡できない |
| B 発行体・curator 信用 | vault owner / curator / guardian / market collateral の実績 | 実績ある protocol / curator で holder と timelock を説明できる | 新興または外部依存が強いが監査・運用実績を説明できる | holder 不明、未監査、重大 incident 未解決、admin takeover risk を説明できない |
| C 価格安定・清算容易性 | collateral price、liquidation depth、loan asset 一致 | ETH / BTC / major stable 等で oracle と清算流動性を説明できる | LST、yield-bearing share、RWA、governance token 等で haircut / low cap が必要 | long-tail / bridge-only / illiquid collateral、清算経路が説明不能 |
| D 構造健全性 | recursive exposure、share collateral、oracle / AUM dependency | 単純な overcollateralized market | 複合戦略、recursive でない share / structured exposure、Morpho API の非 RED warning | recursive vault share、AUM oracle 依存、unsupported collateral、Morpho API の RED warning、重大な構造欠陥 |
| E 時間制約・exit | maturity、withdraw queue、utilization、`maxWithdraw` | 即時または withdrawDelay と整合する exit path | high utilization、queue 劣化、maturity / lock があるが dry-run と buffer で吸収可能 | exit block、期限切れ・満期直前、`maxWithdraw` / `maxRedeem` evidence 不可 |
| F 検証可能性 | on-chain / API / official source / fork dry-run | official source と fork readback で完全に検証可能 | off-chain / API / curator 説明を一部含むが証跡化可能 | current source が取れない、fork dry-run 不可、検証不能 |

分類は軸単位で行い、`REVIEW` / `BLOCKER` の件数は該当する軸の数で数える。

- `PASS` のみ、または `REVIEW` 1 件まで: base candidate。通常 cap / weight の議論に進める。
- `REVIEW` 2 件以上: capped candidate。採用する場合は cap-down、weight-down、追加 monitoring、
  withdraw dry-run、Safe calldata を条件にする。
- `BLOCKER` 1 件以上: No-Go。scope change として明示承認されない限り allocation を開けない。

この分類は market 単位と vault 単位の両方で行う。第三者 curated vault では vault 自体が PASS でも、
供給先 market の一部が REVIEW / BLOCKER なら、その exposure、cap、queue position、withdraw path を
別行で記録する。`morpho-vault-freeze-evidence.ts` の BLOCKER / REVIEW findings は、この 6 軸の
該当軸に紐付けて記録する。

**Morpho Vaults V2（`morpho-v2`）に対する軸 E の carve-out**: `maxWithdraw` / `maxRedeem` が 0 を
返すのは V2 の設計であり evidence 欠落ではないため、`MorphoV2Strategy` 候補ではそれ単独を軸 E の
BLOCKER にしない。V2 の軸 E evidence は、vault idle 残高、adapter ごとの deallocatable liquidity
readback、`forceDeallocate` dry-run とする。`erc4626` 候補には元のルールを維持し、max\* evidence
不可は引き続き BLOCKER である。

## 配分ポリシー

Morpho allocation は Morpho vault 側の cap だけで制御しない。JPYdf 側では少なくとも次を
同時に freeze する。

- branch mintCap、CollateralVault buffer、withdrawDelay、Strategy cap、Strategy weight
- `DF_STRATEGY_KIND_i=erc4626` と `DF_STRATEGY_ERC4626_VAULT_i`、または `DF_STRATEGY_KIND_i=morpho-v2`
  と `DF_STRATEGY_MORPHOV2_VAULT_i` / `DF_STRATEGY_MORPHOV2_MAX_PENALTY_BPS_i`、および
  `DF_STRATEGY_CAP_i` / `DF_STRATEGY_WEIGHT_BPS_i`
- activation block / fork block、normal withdraw dry-run amount、stress withdraw dry-run amount
- Vault buffer から見た即時ユーザー claim 可能額と、Morpho 側から回収できる expected amount

初期 allocation は、Aave baseline と Vault buffer を優先したうえで、Morpho の observed liquidity と
withdraw dry-run に対して保守的に置く。cap / weight 引き上げは、`Active-Branch-Cap-Ramp-Runbook.md`
と同じく SP coverage、DEX liquidity、liquidation bot、fork stress、ops monitoring が揃ってから行う。

Morpho share price が上昇した場合の yield は `ERC4626Strategy` の accounting に従う。外部 incentive /
Merkl reward は Underlying reward なら Vault buffer、非 Underlying / 非 share token reward なら
Treasury sweep として扱い、share token reward は claim 前に拒否する。

## Role Mapping

第三者 curated vault では、Morpho 側 role は外部 trust boundary であり、DF は holder を変更できない。
それでも adoption package では holder、threshold、timelock、pending action、fee recipient、queue /
cap 変更権限を readback し、monitoring 対象にする。

自前 curated vault を運用する場合の role mapping は次を原則にする。

| Morpho role | DF holder 原則 | 方針 |
| --- | --- | --- |
| Owner | `GOV_MULTISIG` + `TimelockController` | curator / guardian / allocator / fee / timelock など上位設定。即時 hot key で持たない |
| Curator | `GOV_MULTISIG` + `TimelockController` または Risk Safe | supply cap、market removal、allocator 権限。cap increase / market追加は Timelock 対象 |
| Guardian / Sentinel | Guardian Safe | pending cap increase、market追加、timelock変更、unsafe action の revoke / emergency deallocation を担当 |
| Allocator | Allocator Safe または hardened allocator bot | supply / withdraw queue、reallocation。bot は cap、allowlist、kill-switch、monitoring、manual fallback が揃うまで使わない |
| Fee recipient | Treasury Safe | performance / management fee を設定する場合の受け口。fee は activation package で明示承認する |

`MorphoV2Strategy` 経由で Vault V2 を採用する場合、activation package は次の全てを freeze
しなければならない（normative。「Adapter / Preflight Gate」の V2 Gate 表と対応する）。

- owner / curator / sentinel / allocator の holder と Sentinel の escalation path
- adapter registry のエントリ（ID・address・対象 protocol）
- 4 つの gate（receive-shares / send-shares / receive-assets / send-assets）が unset であることの
  確認 — 設置は curator timelock 対象でも、設置済み gate の allowlist は address を即時凍結できる
- vault 単位の per-selector timelock 値（デフォルトは 0。nonzero は protocol 保証ではなく
  checklist 項目）
- `maxRate`（deploy デフォルト 0 は yield を留保する。監視対象の knob）
- adapter ごとの `forceDeallocatePenalty` ≤ Strategy の init 凍結 `maxForceDeallocatePenaltyBps`
- liquidity adapter とその deallocatable liquidity readback

Vault V2 を `ERC4626Strategy` 経由で登録することはない。

## Oracle / LLTV / IRM

Morpho market は少なくとも `loanToken`、`collateralToken`、`oracle`、`irm`、`lltv` で risk が決まる。
採用時は、market ごとに以下を evidence package に入れる。

- oracle address、source、scaling、admin / upgrade、stale / pause / revert 時の挙動
- collateral price が急落した場合に、oracle 遅延や liquidation latency が supplier loss へどう伝播するか
- LLTV と liquidation incentive が collateral volatility / DEX depth / oracle cadence に対して保守的か
- IRM が enabled で、極端な utilization 時に supply / withdraw liveness を壊さないか
- market に既存 bad debt、isolated liquidation bottleneck、oracle controversy、admin incident がないか

担保 depeg や oracle 異常は、すぐに `convertToAssets` に反映されない場合がある。JPYdf 側では
`convertToAssets` による confirmed loss と、market health 上の未確定 risk を分けて扱い、
未確定 risk の段階では cap / weight 引き下げ、allocation pause、withdraw dry-run、Safe calldata
準備を先に行う。

## 監視

Morpho 採用時は、ops dashboard / alert / runbook で最低限以下を監視する。

| 対象 | 監視項目 | Action trigger |
| --- | --- | --- |
| ERC-4626 vault | totalAssets、totalSupply、share price、`convertToAssets`、`maxWithdraw`、`maxRedeem` | share price 下落、maxWithdraw 急低下、redeem revert、totalAssets 急減 |
| Vault role | owner、curator、guardian / sentinel、allocator、fee recipient、timelock、pending action | holder 変更、timelock 短縮、fee 上昇、cap increase、unsafe market 追加 |
| Queue / cap | supply queue、withdraw queue、market cap、current exposure、idle market | unsafe market が withdraw queue 後方に残る、cap 0 market に exposure が残る、queue 変更 |
| Market | utilization、available liquidity、bad debt、collateral price、liquidation volume | utilization 高止まり、liquidity 枯渇、bad debt 発生、liquidation 停滞 |
| Oracle / IRM / LLTV | oracle price、staleness、revert、IRM rate、enabled status、LLTV | oracle stale / revert、LLTV 変更、IRM 変更、rate 異常 |
| JPYdf side | Strategy principal、estimatedTotalUnderlying、buffer、queued claim、cap / weight | Strategy estimate と回収可能額の乖離、buffer shortfall、claim 遅延 |

## Emergency / Writeoff 接続

Morpho incident は次の 3 段階で扱う。

| レベル | 状況 | 初動 |
| --- | --- | --- |
| Watch | utilization 高騰、maxWithdraw 低下、queue / cap 変更、oracle warning、role pending action | new allocation 停止準備、withdraw dry-run、cap / weight 引き下げ案、Safe calldata 準備 |
| Action | unsafe market exposure、withdraw queue 劣化、curator / allocator compromise 疑い、oracle stale / revert | `pauseAllocation`、`sendToVault`、Morpho V2 は bounded partial retry の実受取を確認、緊急回収 dry-run / 実行判断、frontend / ops warning |
| Incident | bad debt 確定、share price 下落、withdraw 不可、gate による exit block、oracle exploit、curator takeover | allocation stop、回収実行、必要時は `WRITEOFF_ROLE` の `forceDeallocateMorphoV2`（atomic pause + penalty / backing guard）、backstop 判断、`writeoffStrategyPrincipal`、buffer shortfall comms、post-mortem |

`convertToAssets` が下落した confirmed loss は `estimatedTotalUnderlying()` に下方反映されるため、
回収できない残 principal は `writeoffStrategyPrincipal` の対象にする。一方、`maxWithdraw` 低下や
market liquidity 枯渇は temporary liquidity limit の可能性があり、即 writeoff せず、withdraw queue、
Public Allocator、allocator reallocation、backstop、buffer shortfall comms の順で運用判断する。

緊急時の標準順序は次の通り。

1. 新規 allocation / cap ramp を止める。
2. Morpho vault の role / queue / cap / market / oracle 状態を readback する。
3. `maxWithdraw` / `maxRedeem` と `convertToAssets` を fork / read-only で確認する。
4. 回収可能額がある場合は `sendToVault` または Strategy 固有緊急回収を Safe で実行する。Morpho V2 の `sendToVault` は要求全額失敗時に bounded partial retry するため、`SentToVault.actual` を確認して残額を再計画する。
5. Morpho V2 で penalty 付き deallocation が必要な場合は、高定足数 `WRITEOFF_ROLE` が `CollateralVault.forceDeallocateMorphoV2` を呼ぶ。Strategy wrapper を直接呼ばず、dry-run で正の `_minReceived` と `_minBackingRatioAfter` を固定する。同一 transaction 内で allocation / deposit / redeem / claim を pause し、資金を Vault へ回収する。実受領額または事後 backing が下限を満たさなければ、penalty も含めて全体が revert する。

   既存環境の Vault と MorphoV2Strategy は、共通 Timelock の同一バッチで更新し、途中で回収を実行しない。旧 Vault と新 Strategy の組合せでは、評価読取が失敗すると回収分が cache に残り得る。回収の監視には、この経路からも発火する `ReceivedFromStrategy` を含める。
6. 回収後、Vault buffer、queued claim、SP / DEX liquidity、liquidation safety を確認する。
7. confirmed loss が残る場合だけ writeoff と backstop release を governance で判断する。
8. frontend / ops / public comms を更新し、再 allocation は post-mortem と再 activation package 後に限定する。

## Activation Evidence Package

Morpho の Day-1 allocation を freeze する PR / issue には最低限以下を添付する。

- [`../runbooks/Morpho-Day1-Vault-Freeze-Package.md`](../../launch/gates/Morpho-Day1-Vault-Freeze-Package.md)
  に従った `morpho-vault-freeze.json`。`BLOCKER` が残る場合は launch blocker として扱う
- 採用 vault、chain、official source、code hash、proxy / implementation、version、audits / bug bounty
- Strategy kind、branch、underlying、cap、weight、buffer / withdrawDelay 影響
- `asset()`、`decimals()`、`convertToAssets`、`maxWithdraw`、`maxRedeem`、normal / partial / emergency withdraw dry-run
- vault role、timelock、fee、pending action、supply / withdraw queue、market cap、current exposure
- market ごとの loanToken、collateralToken、oracle、IRM、LLTV、utilization、available liquidity、bad debt
- oracle / LLTV / IRM / curator / allocator / Public Allocator の residual risk
- monitoring dashboard / alert / owner / backup owner / escalation path
- Safe / Timelock calldata、on-chain readback plan、rollback / pause / writeoff plan
- frontend / ops / deploy manifest / `mainnet-preflight` / branch 運用値の更新差分

## No-Go 条件

以下のいずれかに該当する場合、Morpho allocation を開けない。

- `asset()!=branch underlying`
- official address source、code、implementation、role holder、timelock が freeze できない
- `ERC4626Strategy` 経由で登録する vault が `maxWithdraw` / `maxRedeem` evidence を満たせない
  （常時 0 の Vault V2 型設計は専用 `MorphoV2Strategy` を使い、上記 V2 Gate 行を満たすこと）
- normal / partial / emergency withdraw dry-run がない
- curator / allocator / guardian / sentinel の holder や pending action が不明
- fee、gate、registry、queue、cap 変更により Strategy の exit が一方的に壊れうる
- market が unsupported collateral、unverified oracle、bridge-only asset、illiquid collateral、recursive share collateral に依存している
- depeg / exploit / bad debt 時の owner、Safe calldata、writeoff / backstop / comms 手順がない

## 未確定値の扱い

本書は Morpho 採用時の運用方針を定める。具体的な vault address、market cap、Strategy cap、
weight、fee 許容値、role holder address、alert threshold は、採用する vault と fork block が決まった
activation package で、branch 運用値、Strategy deploy 値、外部依存値を上表の各正本、
deploy env / verified manifest、preflight evidence へ落とす。これらの値が未確定である
ことを理由に、Day-1 Morpho allocation を freeze 完了として扱ってはならない。

## 参考資料

- Morpho MetaMorpho repository: https://github.com/morpho-org/metamorpho
- Morpho Vault V2 repository: https://github.com/morpho-org/vault-v2
- Morpho Blue repository: https://github.com/morpho-org/morpho-blue
- Morpho Public Allocator repository: https://github.com/morpho-org/public-allocator
