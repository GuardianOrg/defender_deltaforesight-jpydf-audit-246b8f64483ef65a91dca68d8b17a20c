# 🟢 SkyUsdcSUsdsStrategy 要件定義

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Active |
| Owner | DeltaForesight |
| 対象コントラクト | `contracts/src/Strategies/SkyUsdcSUsdsStrategy.sol` / `contracts/src/Strategies/SkyUsdcSUsdsConverter.sol` |
| 関連ドキュメント | [Strategy](./Strategy.md) / [CollateralVault](../CollateralVault.md) / [Zapper](../Zapper.md) / [Deployment Configuration Spec](../../../../engineering/guides/Deployment-Configuration-Spec.md) |

本書は `SkyUsdcSUsdsStrategy` の Sky / sUSDS 固有要件を規定する。Strategy 共通の
push model、`principal`、`sendToVault`、`sendProfitToVault`、`writeoffPrincipal`、
reward sweep、UUPS 権限は [Strategy](./Strategy.md) を正本とする。

---

## 1. 目的・スコープ

`SkyUsdcSUsdsStrategy` は dUSDC branch の Vault underlying を **USDC のまま**保ち、
Vault から配分された USDC を `USDC -> USDS -> sUSDS` に変換して運用する
asset-transforming Strategy である。

- `underlying()`: USDC（decimals = 6）
- position: sUSDS ERC-4626 share（`asset() == USDS`、decimals = 18）
- 中間 token: USDS（decimals = 18）
- converter: `ISkyUsdcSUsdsConverter`
- 回収時の最終 asset: USDC

archive済みcandidate collateral ingressである`SkyUsdcSUsdsYieldZapper`とは別レイヤーである。
同Zapperは履歴上のユーザー操作をUSDCからcandidate dTokenまでまとめるだけであり、
Vault 資産を運用する Strategy ではない。

---

## 2. 採用条件

この Strategy は dUSDC branch にだけ登録する。`DeployLiquity2` は
`sky-susds` を branch index 1 かつ deployment-wide `USDC` と同一 Underlying の場合にだけ
許可する。Vault の `addStrategy` は `strategy.underlying() == vault.underlying()` を
検証するため、sUSDS underlyingのcandidate collateral branchには登録できない。

mainnet 採用前に以下を freeze する。

| 項目 | env key |
| --- | --- |
| Strategy kind | `DF_STRATEGY_KIND_i=sky-susds` |
| USDS token | `DF_STRATEGY_SKY_USDS_i` |
| sUSDS vault | `DF_STRATEGY_SKY_SUSDS_VAULT_i` |
| Sky LitePSMWrapper-USDS-USDC | `DF_STRATEGY_SKY_USDC_USDS_PSM_WRAPPER_i` |
| 変換損失上限 | `DF_STRATEGY_SKY_MAX_CONVERSION_LOSS_BPS_i` |

`DF_STRATEGY_SKY_MAX_CONVERSION_LOSS_BPS_i` は実装上
`MAX_CONVERSION_LOSS_BPS = 1000` を超えられない。採用時の wrapper 正本は Sky 公式
`LitePSMWrapper-USDS-USDC` とし、Ethereum mainnet address
`0xA188EEC8F81263234dA3622A406892F3D630f98c` を一次資料・fork で再確認する。
deploy script は env から任意 converter を受け取らず、指定 wrapper を immutable に束縛した
`SkyUsdcSUsdsConverter` を新規 deploy する。変換損失上限は `tin` / `tout` と fork dry-run に
基づいて小さく freeze する。

---

## 3. 実装仕様

### 3.1 初期化

`initialize(vault, usdcUnderlying, owner, upgrader, usdsToken, susdsVault, converter, maxConversionLossBps)`
は以下を検証する。

- `usdcUnderlying.decimals() == 6`
- `usdsToken.decimals() == 18`
- `susdsVault.decimals() == 18`
- `susdsVault.asset() == usdsToken`
- `converter != address(0)`
- `converter.usdcToken() == usdcUnderlying`
- `converter.usdsToken() == usdsToken`
- `maxConversionLossBps <= MAX_CONVERSION_LOSS_BPS`

USDC の Vault 向け allowance は `BaseStrategy` が設定する。converter と sUSDS vault には
恒久 max approve を残さず、各変換で `forceApprove(amount)` 後に `forceApprove(0)` へ戻す。

`SkyUsdcSUsdsConverter` は admin / upgrader を持たない immutable adapter とする。constructor は
wrapper の `gem()` を 6 decimals USDC、互換 getter `dai()` を 18 decimals USDS として固定する。
USDC→USDS は `sellGem(receiver, usdcAmount)`、USDS→USDC は
`buyGem(receiver, usdcAmount)` を使い、`tin` / `tout == type(uint256).max` を halt として拒否する。
逆変換の preview と execution は同じ route-validity 判定を使い、halt または
`tout > 1e18` の invalid fee を数値 `0` に変換せず revert する。

### 3.2 Deposit

`_doDeposit(amount)` は Vault から受領済みの USDC を converter で USDS に変換し、
受領した USDS を sUSDS vault に deposit する。

- USDC -> USDS の最小受取は `USDC 1:1 換算 × (1 - maxConversionLossBps)`。
- converter の返り値と USDS 実残高差分が一致しない場合は revert。
- sUSDS vault の返り値と share 実残高差分が一致しない場合は revert。
- mint share が 0 の場合は revert。
- Strategy 自身の deposit で mint した share だけを `_ownSUsdsShares` に加算する。

第三者が sUSDS share を直接送っても `_ownSUsdsShares` は増えない。

### 3.3 Withdraw / Harvest

`_doWithdraw(amount)` は USDC 建ての要求額に対して、必要な USDS 分だけ sUSDS を
withdraw し、USDS を converter で USDC に戻す。

- converter の `previewUsdsToUsdc(USDC 1:1 分)` が要求 USDC を満たす場合、余分な
  loss buffer は取らない。
- preview 上 1:1 分で足りない場合だけ、`maxConversionLossBps` に基づく buffer 分の
  USDS を redeem する。
- USDS -> USDC の実受領が最小受取を下回る場合は revert。
- 逆変換の `usdsAmount` は最大支払予算として扱う。converter は `tout` を含めて購入可能な最大の
  6 decimals USDC 量を求め、未使用 USDS を同一 tx で Strategy へ返す。
- `_ownIdleUsds` は converter に渡した予算額ではなく、Strategy の実残高差分で確認した
  `actualUsdsSpent` だけ減らす。USDC 6 decimals の丸め残余は idle USDS として追跡を継続する。
- 非ゼロの USDS を変換して 0 USDC しか実受領できない場合は revert し、
  `_ownIdleUsds` を減らさない。
- `sendToVault` は Vault 実受領額だけ `principal` を減らす。
- `sendProfitToVault` は `principal` を減らさず、回収 USDC を Vault buffer の yield とする。

### 3.4 Valuation

Sky の USDS→USDC route が有効な間、`estimatedTotalUnderlying()` は以下を
USDC 建てで返す。

```text
min(
  converter.previewUsdsToUsdc(sUSDS.convertToAssets(effectiveOwnShares) + ownIdleUsds),
  oneToOneUsdc(sUSDS.convertToAssets(effectiveOwnShares) + ownIdleUsds)
)
```

`effectiveOwnShares = min(_ownSUsdsShares, susdsVault.balanceOf(this))` とする。
直接 donation された sUSDS / USDS / USDC は通常 valuation に含めない。
USDS(18 decimals) から USDC(6 decimals) への評価は `usdsAmount / 1e12` の切り捨てで
行う。さらに sUSDS の `convertToAssets` も share accounting 上の端数を切り捨て得るため、
USDS dust は `convertToAssets` と USDC scale の両方を超えるまで
`estimatedTotalUnderlying()` / `realizedYield()` に算入しない。両方の floor を超えた時点で
USDC 建て yield として `sendProfitToVault` で回収できる。

converter が `isUsdsToUsdcRouteHalted() == true` と明示した場合、conversion と preview は
従来どおり revert する一方、valuation は `min(oneToOneUsdc(position), principal)` を返す。
停止中に換金できない未実現 yield は認識せず、元本または現在の 1:1 position の小さい方に
限定する。この保守的な値は live measurement として Vault cache を更新できるため、停止が
`strategyValuationMaxAge` を超えても pricing unavailable や branch shutdown へ遷移させない。

invalid fee、route-status read failure、またはその他の preview failure は halt と推測してはならず、
`estimatedTotalUnderlying()` を revert させる。Vault は fresh cache がある間だけ直近の測定値を
使用し、cache が stale になれば pricing availability を false にする。未知の quote 障害を
1:1 と推定して過大評価してはならない。これと、正常 route 上で USDC 1 base unit 未満の
USDS dust が通常の切り捨てにより数値 `0` となる場合は区別する。

### 3.5 Emergency

緊急回収は 2 段階を許容する。

| 関数 | 役割 |
| --- | --- |
| `emergencyRedeemSUsdsToUsds(usdsAmount)` | sUSDS を USDS に redeem し、`_ownIdleUsds` として追跡する |
| `emergencyConvertIdleUsdsToVault(usdsAmount, minUsdcOut)` | idle USDS を USDC に戻し、Vault へ push して returned principal として記帳する |
| `emergencyWithdrawFromSky(maxUsdsToRedeem, minUsdcOut)` | redeem と convert/push を同一 tx で実行する |

converter が停止している場合でも、まず sUSDS を USDS に戻して Strategy 内で追跡できる。
ただし Vault backing に戻るのは USDC として `receiveFromStrategy` に成功した分だけである。
`minUsdcOut` は追加の厳格化として扱い、`maxConversionLossBps` 由来の最小受取を緩和できない。
USDC の最小単位未満の USDS dust を変換しようとして 0 USDC になる場合は revert し、
追跡済みの `_ownIdleUsds` と `principal` を維持する。dust は追加回収や累積により
1 USDC base unit 以上として変換可能になるまで Strategy 内で追跡する。

---

## 4. セキュリティ要件

| ID | 要件 |
| --- | --- |
| SKY-SEC-001 | USDC / USDS / sUSDS の decimals と `susdsVault.asset()` を初期化時に検証する |
| SKY-SEC-002 | converter / sUSDS vault への allowance は per-call approve/reset とし、恒久承認を残さない |
| SKY-SEC-003 | sUSDS share donation は valuation / realizedYield を増やしてはならない |
| SKY-SEC-004 | USDS / sUSDS は protected token であり `sweepRewardToken` できない |
| SKY-SEC-005 | converter 返り値と実残高差分、sUSDS share 返り値と実残高差分を照合する |
| SKY-SEC-006 | USDC 回収時は通常・emergency のどちらでも `maxConversionLossBps` による最小受取を下回ったら revert する |
| SKY-SEC-007 | valuation は converter preview と 1:1 換算の小さい方を使い、過大評価を避ける |
| SKY-SEC-008 | 非ゼロ USDS の変換が 0 USDC 実受領になる場合は revert し、追跡済み idle USDS を silent に減らさない |
| SKY-SEC-009 | converter の USDC / USDS identity は Strategy 初期化時に route token と一致させ、deploy script は任意 converter ではなく監査済み concrete adapter を deploy する |
| SKY-SEC-010 | USDS→USDC は `tout` 込み最大支払予算として計算し、未使用 USDS を返却して実消費量だけ `_ownIdleUsds` から減らす |
| SKY-SEC-011 | 明示的な逆変換 route halt は conversion / preview を revert させたまま、valuation だけを `min(1:1 position, principal)` として継続する。invalid fee・status read failure・その他の quote failure は halt と推測せず、fresh cache 後に pricing unavailable とする |

---

## 5. Verification

`contracts/test/SkyUsdcSUsdsStrategy.t.sol` が以下を検証する。

- allocate で USDC が sUSDS 化され、USDC 建てで評価される
- `sendToVault` が sUSDS -> USDS -> USDC で Vault に戻す
- sUSDS yield を `sendProfitToVault` で USDC として harvest し、`principal` を減らさない
- USDS/sUSDS yield dust が `convertToAssets` / USDC scale の floor 未満では valuation / realizedYield を水増しせず、floor を超えた後だけ回収できる
- sUSDS share donation が valuation を増やさない
- emergency redeem / convert / Vault push が returned principal を記帳する
- emergency convert / withdraw は `minUsdcOut=0` でも `maxConversionLossBps` 下限を緩和しない
- emergency convert は USDS dust が 0 USDC に floor される場合に revert し、`_ownIdleUsds` と `principal` を維持する
- USDS / sUSDS sweep が拒否される
- USDC decimals mismatch が初期化時に拒否される
- converter が予算の一部だけを消費した場合、未使用 USDS が `_ownIdleUsds` に残る
- 明示的な Sky 逆変換 route halt が cache 期限を超えても principal-capped valuation を継続し、価格 feed が branch shutdown しない
- route halt 中の未実現 sUSDS yield を認識しない
- invalid fee / generic quote failure は halt と誤分類せず、fresh cache 後は pricing unavailable、quote 回復後は live valuation が自動復旧する

`contracts/test/SkyUsdcSUsdsConverter.t.sol` は Sky 公式 LitePSMWrapper と同じ
`sellGem` / `buyGem` / `tin` / `tout` 意味論を持つ mock に対し、fee floor、halt / invalid fee 時の preview revert、最小受取、
wrapper 返り値と実残高差分、逆変換 refund、残余 token と allowance がゼロへ戻ることを検証する。
`MAINNET_RPC_URL` が設定されている場合は同 test file の fork test が公式 wrapper の
`gem()==USDC` / `dai()==USDS`、`tout` / preview の整合、および実際の
USDC→USDS→USDC round-trip を確認する。

## 6. 一次資料

- [Sky Protocol Docs: LitePSM](https://developers.skyeco.com/guides/psm/litepsm/) — wrapper address、`sellGem` / `buyGem`、fee、halt、流動性上限
- [Sky `usds-wrappers`](https://github.com/sky-ecosystem/usds-wrappers/blob/dev/src/UsdsPsmWrapper.sol) — deployed wrapper 実装のAPI・fee計算
- [Sky `dss-lite-psm`](https://github.com/sky-ecosystem/dss-lite-psm) — underlying LitePSM の設計・既知制約
