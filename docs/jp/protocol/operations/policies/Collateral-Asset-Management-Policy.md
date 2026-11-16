# 担保資産運用方針

## 位置づけ

本書は、Underlying の asset flow と回収特性に対して、どの Strategy adapter で
技術的に表現できるかを整理する設計メモである。

担保・risk parameter・buffer / withdrawDelay の Day-1 値は
[`../../Parameters.md`](../../../Parameters.md)、Strategy venue の採用状態は
[`Strategy-Selection-Policy.md`](./Strategy-Selection-Policy.md)、Day-1 の登録値は
[`Mainnet-Deploy-Env-Freeze-Runbook.md`](../../launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md) と生成Manifestを正本とする。deploy mode・wiring shape・Manifest schemaは
[`Deployment-Configuration-Spec.md`](../../../engineering/guides/Deployment-Configuration-Spec.md)を参照する。Strategy 共通仕様は
[`../../spec/strategies/Strategy.md`](../../product/spec/strategies/Strategy.md)、個別 adapter の要件は
同ディレクトリの Strategy 子ドキュメントを正本とする。外部運用先を採用してよいかの
risk / governance / monitoring 基準も
[`Strategy-Selection-Policy.md`](./Strategy-Selection-Policy.md) を正本とする。Morpho 固有の
vault / market / role / queue / oracle / emergency 運用 gate は
[`Morpho-Operation-Policy.md`](./Morpho-Operation-Policy.md) を正本とする。

本書で「対応済み」「条件付き対応済み」と書く場合、それは既存 adapter で技術的に表現できる
という意味であり、mainnet allocation の承認ではない。

Day-1 の実登録は branch 0 dwstETH の Aave V3（aEthwstETH）と branch 1 dUSDC の
Aave V3 + Morpho Vault V2 である。native ETH の入金経路は `CollateralYieldZapper` の
staking route（ETH → Lido stETH → wstETH、frozen expected-stETH address で gate）が提供し、
protocol-level の WETH は gas compensation のみに使う。

## 必要十分性の基準

Strategy は venue ごとではなく、asset flow と回収特性に必要な adapter だけを使う。

| 判断 | 方針 |
| --- | --- |
| `asset()==underlying` の ERC-4626 vault | 既存 `ERC4626Strategy` で足りる。Morpho を採用する場合も asset 一致と回収 evidence を要求する |
| WETH を Lido wstETH で運用 | **retired**。`LidoStrategy` は `contracts/src/Strategies/archive/` に archived であり deploy 経路を持たない。将来の stETH venue は新規 proposal |
| wstETH を外部運用 | Day-1 baseline は `AaveV3Strategy`（aEthwstETH）。native canonical-rate 増価は borrower 担保価値に残し、Underlying 数量増加だけを Strategy 収益とする |
| WETH を Etherfi weETH で運用 | **retired**。`EtherfiWeETHStrategy` / `WeETHWithdrawAdapter` は `contracts/src/Strategies/archive/` に archived であり deploy 経路を持たない。将来の LRT venue は新規 proposal |
| USDC を Sky sUSDS で運用 | `SkyUsdcSUsdsStrategy` で対応済み。converter / min-out / USDS idle 監視が必要 |
| その他の Underlying と異なる asset へ変換する | 対応 Strategy がなければ新規 asset-transforming Strategy が必要。設定変更だけでは不可 |
| 外部運用しない | `strategyKind=none` が正しい。dummy Strategy は置かない |
| venue 名だけが異なる | 既存 adapter の条件を満たすなら専用 Strategy を作らない |

## 候補 venue 別の対応方針

| Venue / asset | 現行対応 | 採用条件 |
| --- | --- | --- |
| Aave V3 | 対応済み。`AaveV3Strategy` | branch underlying の reserve / aToken を primary source で freeze し、reserve active / not frozen / not paused を fork block で確認する |
| Morpho ERC-4626 vault | 条件付き候補。`ERC4626Strategy` | target vault の `asset()` が branch underlying と完全一致し、`Morpho-Operation-Policy.md` の gate を満たすこと |
| EulerEarn / その他 ERC-4626 | 条件付き対応済み。`ERC4626Strategy` | Morpho と同じく `asset()==underlying` が必須。採用時は venue runbook、audit scope / preflight 更新が必要 |
| USDC branch -> USDS -> sUSDS 運用 | 実装済み・条件付き採用候補。`SkyUsdcSUsdsStrategy` | dUSDC/USDC branch 専用。採用時に USDS / sUSDS / converter / max conversion loss を freeze し、fork dry-run、route halt 監視を満たす |
| Etherfi / weETH | **retired・source archived** | `EtherfiWeETHStrategy` / `WeETHWithdrawAdapter` は 2026-08-06 に `contracts/src/Strategies/archive/` へ移動。WETH underlying は到達不能で deploy surface は PR #1424 で削除済み。`0c7766e0` の監査対象であったため保存する。将来の LRT venue は新規 proposal |

## Morpho の扱い

Morpho は「Morpho だから専用 adapter が必要」ではなく、採用する vault が ERC-4626 として
標準的に振る舞い、`asset()` が branch underlying と一致するなら既存 `ERC4626Strategy` の範囲に
入る。

採用時の追加 gate:

- `DF_STRATEGY_KIND_i=erc4626`、`DF_STRATEGY_ERC4626_VAULT_i`、weight / cap を freeze する。
- `mainnet-preflight` に対象 ERC-4626 vault の code、`asset()`、`convertToAssets(1eDecimals)`、
  `maxWithdraw` / `maxRedeem` の観測、採用 source を追加する。
- curator / market selection / oracle / bad debt 監視は Strategy code ではなく
  [`Morpho-Operation-Policy.md`](./Morpho-Operation-Policy.md) の運用 gate で管理する。
- `convertToAssets` に反映されない未確定 risk を即 writeoff しない。confirmed loss と一時的な
  liquidity limit を分けて扱う。
- Morpho Vault V2 のように `maxWithdraw` / `maxRedeem` が仕様上 0 の vault は、現行
  `ERC4626Strategy` の通常回収・緊急回収 gate を満たせないため `ERC4626Strategy` 経由では登録しない。
  Morpho Vault V2 は専用の監査済み `MorphoV2Strategy`（kind `morpho-v2`・Day-1 は branch 1 dUSDC）で
  [`Morpho-Operation-Policy.md`](./Morpho-Operation-Policy.md) の gate に従って採用する。

## Etherfi / LRT の扱い（retired・source archived）

> `EtherfiWeETHStrategy` / `WeETHWithdrawAdapter` は `contracts/src/Strategies/archive/` に
> **archived**（2026-08-06）。deploy 経路を持たず、採用候補でもない。以下は将来の LRT proposal が
> 再導出・再監査すべき設計記録として残す。

Etherfi / weETH は、`EtherfiWeETHStrategy` で対応していた。現行 `ERC4626Strategy` には乗せない。
理由は次の通り。

- `EtherfiWeETHStrategy` の対象 branch underlying は WETH であり、weETH / eETH は別 asset である。
- deposit / withdrawal に ETH unwrap、LRT mint、request、claim、wrap などの中間状態が入る。
- valuation は WETH 建ての保守 quote、LRT exchange rate、depeg / slashing / withdrawal queue を
  分けて扱う必要がある。
- donation 耐性のため、自己由来 LRT share / pending request / claimed idle WETH を個別に
  追跡する必要がある。

採用する場合は `LidoStrategy` と同じ async Strategy として、少なくとも以下を運用 gate にする。

- `underlying() == WETH` を維持し、Vault / Core には WETH 建て評価だけを返す。
- `estimatedTotalUnderlying()` は自己由来 position のみを WETH 建てに保守換算する。
- `sendToVault` は claim 済み idle WETH だけを返し、未 finalization 分を損失扱いしない。
- 固有 `requestEtherfiWithdrawal` / `claimEtherfiWithdrawals` / `emergencyWithdrawFromEtherfi` を運用 runbook に入れる。
- direct donation、route residue、rebasing / share accounting、withdrawal NFT / request id を
  監査対象に含める。

## Self-appreciating Underlying と Strategy の境界

dwstETH や将来の yield-bearing USD を採用する場合、Underlying の canonical rate による増価は
borrower の担保価値に残す。外部 Strategy による Underlying 数量の増加だけを Strategy 収益として
扱い、venue、会計、回収、monitoring は activation package で別途承認する。
