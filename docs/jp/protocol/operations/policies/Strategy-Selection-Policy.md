# Strategy 選定ポリシー

## 位置づけ

本書は、CollateralVault の Underlying を外部プロトコルで運用する Strategy venue を、
どのリスク基準で採用・継続・停止するかを定める設計方針である。

関連文書の責務は次の通り。

| 文書 | 責務 |
| --- | --- |
| 本書 | 外部運用先を採用してよいかの risk / governance / monitoring 基準 |
| [`Collateral-Asset-Management-Policy.md`](./Collateral-Asset-Management-Policy.md) | Day-1 branch 構成、候補 venue と既存 adapter の対応範囲 |
| [`Morpho-Operation-Policy.md`](./Morpho-Operation-Policy.md) | Morpho 採用時の vault / market / role / queue / oracle / emergency 運用 gate |
| [`../../spec/strategies/Strategy.md`](../../product/spec/strategies/Strategy.md) | Strategy contract 共通仕様、push model、権限、会計、不変条件 |
| [`../../../archive/LidoStrategy.md`](../../../archive/LidoStrategy.md) | **Archived** の Lido 履歴要件。active な実装・監査スコープではないが、source が `0c7766e0` の監査対象であったため保存する |
| [`../../../archive/EtherfiWeETHStrategy.md`](../../../archive/EtherfiWeETHStrategy.md) | **Archived** の Ether.fi weETH 履歴要件。active な実装・監査スコープではないが、source が `0c7766e0` の監査対象であったため保存する |
| [`../../Parameters.md`](../../../Parameters.md) | branch mapping、mintCap、buffer、withdrawDelay 等の Day-1 値 |
| [`Deployment-Configuration-Spec.md`](../../../engineering/guides/Deployment-Configuration-Spec.md) | deploy mode、wiring shape、manifest schema、env validation |
| [`Mainnet-Deploy-Env-Freeze-Runbook.md`](../../launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md) | Day-1 の Strategy kind・cap・weightをenvへ凍結し、生成Manifestと照合する手順 |

重要な境界として、**既存 adapter で技術的に表現できることは、その venue を採用してよいことを意味しない**。
例えば Morpho / EulerEarn の ERC-4626 vault が `asset()==underlying` を満たす場合でも、
本書の選定 gate、採用 evidence、継続監視、incident runbook を満たすまでは public exposure や
mainnet allocation の対象にしない。

## Day-1 方針

dwstETH（branch 0）は Aave V3 wstETH slot（aEthwstETH）だけを Day-1 set とする（`DF_STRATEGY_COUNT_0=1` / `DF_STRATEGY_KIND_0_0=aave`。`allocateMaxMove` の Day-1 値は Parameters に従う）。wstETH の native staking 増価は借り手の担保価値に残す。dUSDC は Aave V3 の同期回収構成を required baseline とし、Morpho Vault V2 slot（`morpho-v2`）を併設する。

Branch 2–7（dETH / dUSD-A / dBTC / dUSD-B / dJPY / dJGB）はUnderlying未bindingのinert slotである。`strategies[]`を空、weight / cap / `allocateMaxMove`を0で開始し、Strategyをdeploy / register / allocationしない。

Morpho を dUSDC に組み入れる場合は、特定 vault の Go 判断と本書の evidence gate を満たす。adapter の対応だけでは mainnet allocation を開けない（cap 0 の間は実配分の余地がない）。

Day-1 launch manifest は borrowable branch の承認済み Strategy set（branch 0 = aave のみ / branch 1 = aave + morpho-v2）と、Branch 2–7 の空の `strategies[]` を fail-closed で照合する。

## 採用分類

| 分類 | 意味 | 必要アクション |
| --- | --- | --- |
| Approved active | 現在の mainnet launch / production allocation 対象 | 本書の分類、deploy env、preflight、runbook、monitoring が一致していることを確認 |
| Conditional approved | 実装上は対応可能だが、activation evidence 完了まで inactive | 本書の gate を満たす activation package を作る |
| Candidate | 調査候補。adapter 適合、risk evidence、運用体制のいずれかが未確定 | 採用判断に使わず、調査 issue / doc に留める |
| Rejected / backlog | Day-1 または当面の採用対象外 | 理由を残し、public exposure / deploy env から除外する |

現在の採用分類は次の通り。**下表を現在の採用状態の正本**とし、他文書は固有の仕様・設定・手順だけを記載して本表を参照する。

| Venue / branch | 分類 | 理由 |
| --- | --- | --- |
| Aave V3 wstETH / dwstETH | Approved active | 同期回収、既存 Strategy（aEthwstETH）、Day-1 の branch 0 required set |
| Aave V3 USDC / dUSDC | Approved active | 同期回収、既存 Strategy、mainnet preflight / launch evidence 対象 |
| Morpho ERC-4626 for dUSDC | Conditional approved | 特定 vault の Go 判断と vault / curator / market / oracle / bad debt evidence の freeze 後に限り allocation を開ける |
| Morpho Vault V2 / dUSDC | Conditional approved（専用 `MorphoV2Strategy` 経由） | `ERC4626Strategy` 経由では不適格（max\* view が設計上 0）だが、専用 `MorphoV2Strategy`（kind `morpho-v2`）がその blocker を解消する。allocation は activation package（`Morpho-Operation-Policy.md` の V2 gate 行）と external audit の完了後に限る。Day-1 対象は branch 1 USDC。branch 0（wstETH）は信頼できる wstETH 建て V2 vault が存在するまで延期 |
| EulerEarn / other ERC-4626 | Conditional approved | deposit / withdraw の adapter fit は既存 `ERC4626Strategy` で評価できるが、Day-1 expected scope ではない。Euler Reward Streams 等の pull-based native reward が有効な vault は、現行 adapter に claim 経路がないため、reward 無効の evidence または venue 固有 claim 実装・追加 audit が完了するまで No-Go |
| Lido / WETH underlying branch | **Retired・source archived** | `LidoStrategy` の source は 2026-08-06 に `contracts/src/Strategies/archive/` へ移動。underlying は構造的に WETH であり、それを束ねていた deploy selector（`lido` strategy kind / venue struct / helper / env key）は PR #1424 で削除済み。branch 0 の underlying も wstETH となり、WETH underlying を供給できる branch は存在しない。deploy / register / allocation は不可。archived source は 2026-08-05 完了の外部監査（`0c7766e0`）の対象であったため保存しているのであり、再開候補ではない。再有効化には deploy selector への再登録と新規 activation package・audit-scope 変更が必要 |
| Etherfi / WETH underlying branch | **Retired・source archived** | `EtherfiWeETHStrategy` / `WeETHWithdrawAdapter` も同じ理由で 2026-08-06 に archive へ移動（WETH underlying が到達不能、deploy surface は PR #1424 で削除済み）。`0c7766e0` で監査済みの履歴 artifact として保存する。将来の LRT venue は新規 proposal であり、async request / NFT / LRT risk package が必要 |
| Sky USDC -> USDS -> sUSDS | Conditional approved / backlog | 実装済みだが Day-1 expected scope ではない。converter / route halt / min-out / partnership / activation evidence が必要 |
| dwstETH external Strategy | Candidate / Day-2 | Day-1 は外部 Strategy を採用しない。native staking 増価は担保価値に残す。leveraged loop / Ride-on 等は DD・仕様化・開発・追加監査を経た Day-2 候補とし、採否・venue・会計・exit・監査は個別 package で確定 |
| inert slot external Strategy | Candidate / activation-specific | exact Underlyingの承認・binding・追加監査要否の判断と同時に個別評価する |

## 採用フロー

1. **分類**: 新規 venue か、既存 approved venue の cap / weight / branch 変更か、既存 adapter の別 vault かを切り分ける。
2. **adapter 適合確認**: `Strategy.md` と `Collateral-Asset-Management-Policy.md` に従い、既存 Strategy kind で足りるか、新規 Strategy が必要かを判定する。
3. **hard requirement 確認**: 下記の必須条件を 1 つでも満たさない場合は production allocation 対象にしない。
4. **risk review**: 評価軸ごとに evidence を揃え、risk owner / contracts owner / ops owner が採否をレビューする。
5. **activation package**: branch 運用値、Strategy の kind / cap / weight、deploy env、preflight、runbook、frontend / ops 表示、monitoring、audit scope を同じ PR / issue で接続する。
6. **governance execution**: mainnet 変更は Safe / Timelock bundle と on-chain readback evidence を残す。
7. **post-activation monitoring**: 採用後の monitoring と再評価 trigger を有効化する。

## Hard Requirements

以下は minimum gate であり、満たさない venue は採用しない。

| 項目 | 必須条件 |
| --- | --- |
| Chain / venue | Ethereum mainnet 上の直接 venue である。Day-1 Strategy に外部 bridge / 他チェーン依存を入れない |
| Contract address | 公式 source から取得した contract address / implementation / proxy admin / upgrade path を freeze できる |
| Underlying accounting | Strategy が Vault underlying 建てで保守的に評価し、Vault へ同じ underlying を push 回収できる |
| Adapter fit | `strategy.underlying() == vault.underlying()` を満たす。異なる asset へ変換する場合は asset-transforming Strategy として spec / tests / audit が必要 |
| Withdraw path | 正常時と incident 時の withdrawal / redeem / claim / queue の経路が説明できる。temporary illiquidity と confirmed loss を分けられる |
| Valuation | `estimatedTotalUnderlying()` が過大評価しない。外部 share price / exchange rate / oracle / quote の信頼境界が説明できる |
| Governance risk | venue admin / upgrader / guardian / pause / blacklist / fee setter 等の権限 holder と timelock / multisig 構成を確認できる |
| Oracle / market risk | price source、conversion route、bad debt、depeg、slashing、reserve deficit 等の監視項目を定義できる |
| Emergency controls | `pauseAllocation`、`sendToVault`、固有 emergency withdraw、writeoff、backstop の運用 owner と runbook がある |
| Reward path | 有効な incentive / reward distributor ごとに claim、forfeit / expiry、Underlying / Treasury settlement、protected token 拒否を説明できる。現行 adapter が pull claim を呼べない reward 経路は、無効であることを証明するか、venue 固有実装・unit / fork test・追加 audit 完了まで allocation を禁止する |
| Audit scope | 新規 adapter または新しい asset-transforming route は Day-1 audit scope に追加する。既存 adapter の別 vault でも fork evidence と config review は必須 |

dwstETH では、wstETH の canonical rate 上昇と外部 Strategy による wstETH 数量増加を会計上分ける。native staking 増価は borrower の担保価値に残し、Strategy profit として sweep しない。

## 評価軸

採用レビューでは、少なくとも次の評価軸を記録する。

| 評価軸 | 確認内容 |
| --- | --- |
| Protocol maturity | mainnet 稼働期間、TVL、利用実績、過去 incident と対応履歴 |
| Smart-contract risk | audit、bug bounty、upgradeability、proxy admin、timelock、有害な privileged function |
| Governance / admin risk | owner / guardian / emergency admin の holder、threshold、timelock、pause / freeze / blacklist 権限 |
| Asset / counterparty risk | underlying 発行体、redeemability、depeg、slashing、reserve deficit、custody / bridge 依存 |
| Oracle / valuation risk | Chainlink / TWAP / share price / exchange rate / converter quote、stale / paused / manipulated quote の扱い |
| Liquidity / exit risk | `maxWithdraw`、reserve liquidity、queue finalization、withdrawDelay との整合、stress 時の partial recovery |
| Accounting fit | principal / yield / pending / idle / reward token / donation residue を既存 Strategy 会計で表現できるか |
| Operational readiness | preflight、monitoring、alerts、keeper、明示的な emergency action、Safe calldata / runbook、incident owner |
| User / frontend impact | borrowable branch gate、public exposure 表示、risk disclosure、ops dashboard の data source |

## Evidence Package

採用または cap / weight 引き上げの PR / issue には、最低限以下を添付する。

- venue 名、chain、公式 address source、contract address、proxy / implementation / admin 情報
- 採用 Strategy kind、対象 branch、underlying、cap、weight、buffer / withdrawDelay への影響
- `asset()` / `underlying()` / `decimals()` / `convertToAssets` / `maxWithdraw` / reserve status 等の fork readback
- normal deposit / withdraw / partial withdraw / emergency withdraw / pause / writeoff dry-run
- oracle / quote / share price / exchange rate の source と stale / failure handling
- incentive / reward distributor の種類、有効化状態、claim / forfeit / expiry、受領先、Underlying / Treasury settlement の dry-run
- privileged holder / timelock / pause / upgrade / fee / blacklist 権限の整理
- monitoring metrics、alert threshold、owner / backup owner、incident runbook
- frontend / ops / launch gate / deploy manifest / branch 運用値の更新差分
- residual risk と採用しない代替案

## 継続監視・再評価

Approved active venue は採用後も固定ではない。次の場合は即時再レビューし、必要であれば cap / weight
引き下げ、allocation pause、emergency withdraw、writeoff、branch cap ramp 停止を検討する。

- external protocol の upgrade / admin holder 変更 / timelock 変更
- reserve pause / freeze / withdrawal queue 停滞 / `maxWithdraw` 急低下
- oracle stale、share price 異常、exchange rate 異常、converter halt
- depeg、slashing、bad debt、reserve deficit、bridge / custody incident
- TVL / liquidity の急減、利用率急上昇、withdrawal cost の急上昇
- Strategy の `estimatedTotalUnderlying` と実回収可能額の乖離
- frontend / ops / bot が古い config を参照している疑い

通常レビューは少なくとも四半期ごとに実施し、年 1 回は採用根拠を full review する。重大 incident
または governance 変更がある場合は周期を待たずに再評価する。

## Governance / 承認

| 役割 | 責務 |
| --- | --- |
| proposer | venue 候補、採用目的、cap / weight、expected yield、代替案を提出 |
| risk owner | hard requirements、評価軸、residual risk、cap / weight 妥当性をレビュー |
| contracts owner | adapter fit、storage / upgrade / preflight / fork evidence / audit scope をレビュー |
| ops owner | monitoring、keeper、Safe calldata、incident / withdrawal runbook をレビュー |
| governance owner | Safe / Timelock bundle、role assignment、on-chain readback evidence を承認 |

承認済み venue でも、deploy env 変更や Safe transaction だけで allocation を開けない。activation package と on-chain readback evidence を揃える。Day-1 baseline 外の venue を追加する場合は audit scope を再確認する。

## Morpho / ERC-4626 の扱い

Morpho / EulerEarn などは、採用 vault が `asset()==underlying` の ERC-4626 として標準動作するなら
`ERC4626Strategy` の範囲に入る。ただしこれは **adapter fit** の結論であり、venue selection の結論ではない。
Morpho を採用できる対象は branch 1 `dUSDC` の `erc4626` / `morpho-v2` とし、それ以外の ERC-4626 venue / branch への採用は別の activation package で扱う。

Morpho を採用する場合は、本書の gate に加えて、
[`Morpho-Operation-Policy.md`](./Morpho-Operation-Policy.md) に従い、curator、market selection、
oracle、LLTV、bad debt、supply / withdraw queue、role design、emergency / writeoff 接続を
確定する。自前 curated vault を運用する場合は、第三者 curated vault に supply する場合よりも
governance / ops / monitoring の scope が大きくなるため、別 activation package とする。

また、Morpho Vault V2 は ERC-4626 interface を持つが、公式実装上 `maxWithdraw` / `maxRedeem` が
常に 0 を返す設計である。現行 `ERC4626Strategy` はこれらを回収上限として使うため、Vault V2 は
**`ERC4626Strategy` 経由では不適格**とする。Vault V2 の採用は専用の
[`MorphoV2Strategy`](../../product/spec/strategies/MorphoV2Strategy.md)（kind `morpho-v2`）経由で行う。
同 Strategy は max\* view を参照せず独自の回収・緊急モデルを持ち、venue gate と evidence 項目は
[`Morpho-Operation-Policy.md`](./Morpho-Operation-Policy.md) に定める。Day-1 対象は branch 1 `dUSDC` のみ、
branch 0（`dwstETH`）は信頼できる wstETH 建て V2 vault が存在するまで延期する。

## 非責務

- 本書は Strategy contract の関数仕様を再定義しない。contract 仕様は `Strategy.md` と子ドキュメントを正とする。
- 本書は branch risk parameter の数値や Strategy の deploy 値を決めない。参照先は冒頭の責務表を正とする。
- 本書は新規 venue の採用を承認しない。採用には issue / PR / evidence / governance execution が必要である。
