# 🟢 ERC4626Strategy 要件定義

## 0. メタ情報

| 項目 | 値 |
| --- | --- |
| Status | Draft（実装あり・要件の正本化中） |
| Owner | DeltaForesight |
| 対象コントラクト | `contracts/src/Strategies/ERC4626Strategy.sol`（汎用 ERC-4626 Strategy・`BaseStrategy` 継承・UUPS） |
| 関連ドキュメント | [Strategy](./Strategy.md)（`IStrategy` / `BaseStrategy` / push モデル・共通権限・共通リスクの正本）/ [CollateralVault](../CollateralVault.md)（whitelist / addStrategy / receiveFromStrategy 呼出側）/ [Product-Overview](../../Product-Overview.md) / [Morpho-Operation-Policy](../../../operations/policies/Morpho-Operation-Policy.md) |

> 本書は [要件定義ドキュメント標準](../../../../Requirements-Spec-Standard.md) に従う。`ERC4626Strategy` は Morpho Vault / EulerEarn / sUSDS 等、`asset()` が Strategy の Underlying と一致する ERC-4626 vault を扱うための汎用 adapter である。

---

## 1. 目的・スコープ・非責務

`ERC4626Strategy` は CollateralVault が配分した Underlying を **1 つの ERC-4626 vault** に預け、vault share を保持し、回収時に Underlying へ戻して Vault へ push する Strategy である。最初の対象候補は Morpho Vault / EulerEarn のような ERC-4626 形式の運用先とする。

- **本書が規定する**: ERC-4626 固有の追加ストレージ（`erc4626Vault` / `_ownShares`）、`initialize` の `asset()` 検証と Owner / Upgrader 引数、3 hook の ERC-4626 I/F へのマッピング、固有緊急回収 `emergencyWithdrawFromERC4626`、share token donation / zero-share mint / receipt token sweep の防止、Morpho / Euler 等で発生する外部 reward token / Merkl claim の会計境界。
- **本書が規定しない**: Vault 側の配分判断・`writeoffStrategyPrincipal`・Treasury 送付、Strategy の登録状態・cap / weight、個別の Morpho/Euler market 選定・curator/tranche risk・oracle/LTV 設計。これらは [CollateralVault](../CollateralVault.md) / [Strategy Selection Policy](../../../operations/policies/Strategy-Selection-Policy.md) / [Mainnet Deploy Env Freeze Runbook](../../../launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md) / 個別運用 runbook の責務。deploy mode・wiring shape・Manifest schemaは[Deployment Configuration Spec](../../../../engineering/guides/Deployment-Configuration-Spec.md)を参照する。
- **適用条件**: `IERC4626.asset() == underlying` が必須。USDC を USDS/sUSDS に変換するような asset-transforming strategy には使わない。その経路は Zapper または別 Strategy として明示設計する。

---

## 2. 設計方針

- **1 Strategy = 1 Underlying = 1 ERC-4626 vault**: `erc4626Vault` は `initialize` で固定し、setter は設けない。投資先を変える場合は Strategy を作り直し、Vault whitelist / addStrategy を更新する。
- **自己 mint share のみを通常評価**: ERC-4626 share token は ERC-20 なので、第三者が直接 Strategy へ transfer できる。`balanceOf(this)` をそのまま評価すると donation が `realizedYield()` を水増しするため、Strategy 自身の `deposit` で mint された `_ownShares` を別途追跡する。
- **share / asset 残高差分を真実とする**: ERC-4626 は `deposit` / `withdraw` / `redeem` の返り値を定義するが、adapter は外部 vault の返り値だけを信頼しない。`balanceOf(this)` の before/after 差分と返り値を照合し、不一致なら fail-fast する。通常 `withdraw` でも、share burn が 0 なら `ERC4626ZeroShares`、要求 asset 量と Underlying 実増分が一致しないなら `ERC4626AssetAmountMismatch` で revert する。`emergencyWithdrawFromERC4626()` でも `redeem` の返り値 asset 量と Underlying 実増分を照合する。Aave adapter が aToken / scaled balance の差分を基準にするのと同じく、position token と asset token の実残高差分を会計の根拠にする。
- **share donation は通常会計に入れないが緊急時は回収する**: `estimatedTotalUnderlying()` は `min(_ownShares, shareBalance)` のみ評価する。一方、`emergencyWithdrawFromERC4626()` は保有 share 全体を可能なだけ redeem し、回収できた Underlying を Vault へ即時 push する。raw share を対象とする緊急 redeem 後は `_ownShares = min(ownSharesBefore, shareBalanceAfter)` とし、donation share を先に消費して残存自己 share の評価を保つ。Vault 実受領額は returned principal として `principal` から減算する。
- **zero-share deposit は禁止**: ERC-4626 vault が `deposit()` で 0 shares を返す場合、principal だけ増えて AUM が増えないため inner frame を `ERC4626ZeroShares` で revert する。BaseStrategy が Underlying を完全回収できれば当該 Strategy だけ skip し、回収不一致時だけ allocate 全体を revert する。
- **緊急回収は atomic push**: ERC-4626 から redeem して Strategy に Underlying が滞留したまま tx を終えない。`receiveFromStrategy` 経由で Vault buffer へ push し、Vault 側 valuation cache も同時に減額する。部分回収後に残額が損失確定した場合、残 `principal` を `writeoffStrategyPrincipal` で落とせば backing が二重計上されない。
- **外部 reward は backing 会計に混ぜない**: Morpho / Euler の incentive や Merkl reward は、Underlying でも ERC-4626 share token でもない reward token のみ `sweepRewardToken` / `claimMerklRewards` で Treasury へ送る。Underlying reward は `claimMerklRewards` で Vault buffer へ push し、ERC-4626 share token / protected position token は Merkl distributor 呼び出し前に拒否する。
- **流動性不足を損失扱いしない（ADR-006 の strategy 別ガード）**: `_doWithdraw` は `min(amount, convertToAssets(_ownShares), maxWithdraw(this))` で保守的に引き出し（§3）、`maxWithdraw` / `maxRedeem` が liquidity limit を返しても revert ではなくその時点の withdrawable amount まで抑える（§5-4）。これは[Architecture Decision Records](../../architecture/Architecture-Decision-Records.md#adr-006)の「一時的流動性不足を損失扱いしない」strategy 別保守ガードを ERC4626 で満たすもの。一方、share price 低下（bad debt 等の confirmed loss）は `convertToAssets` 経由で `estimatedTotalUnderlying()` / Vault `totalUnderlying()` に即時下方反映する（`E4626-SEC-005`）。

---

## 3. インターフェース仕様

| 関数 | 可視性 | 要約 |
| --- | --- | --- |
| `initialize(address vault, IERC20 underlying, address owner, address upgrader, IERC4626 erc4626Vault)` | external initializer | BaseStrategy 初期化、Owner / Upgrader 分離、`asset()` 検証、ERC-4626 vault への max approve |
| `_doDeposit(uint256 amount)` | internal | `erc4626Vault.deposit(amount, this)` を実行し、share 残高増分と返り値を照合して `_ownShares` に加算。0 shares / 不一致は revert |
| `_doWithdraw(uint256 amount)` | internal | `min(amount, convertToAssets(_ownShares), maxWithdraw(this))` を withdraw し、share 残高減分・返り値・Underlying 実増分を照合して `_ownShares` から減算 |
| `_estimatedTotalUnderlying()` | internal view | `convertToAssets(min(_ownShares, erc4626Vault.balanceOf(this)))` を返す |
| `emergencyWithdrawFromERC4626()` | external onlyOwner | `maxRedeem(this)` の範囲で raw share を redeem し、`_ownShares` を残存 raw share にクランプして donation-first 会計を保ち、idle Underlying を `receiveFromStrategy` で Vault へ push、Vault 実受領額を returned principal として記帳 |
| `_isSweepProtectedToken(address token)` | internal view | Underlying に加えて ERC-4626 share token を sweep 禁止にする |
| `claimMerklRewards(...)` | external onlyOwner（BaseStrategy 継承） | ERC-4626 share token / protected position token を claim 前に拒否し、Underlying reward は Vault buffer、通常 reward token は Treasury へ精算 |

---

## 4. セキュリティ要件

| ID | 要件 | 検証 |
| --- | --- | --- |
| E4626-SEC-001 | `initialize` は `erc4626Vault.asset() == underlying` を検証し、mismatch を `InvalidERC4626Asset` で拒否する | unit |
| E4626-SEC-002 | share token donation は `estimatedTotalUnderlying()` / `realizedYield()` を増やしてはならない | unit |
| E4626-SEC-003 | ERC-4626 share token は position token であり、`sweepRewardToken` で Treasury へ送れない | unit |
| E4626-SEC-004 | `deposit()` が 0 shares を返す場合は `ERC4626ZeroShares` で revert する | unit |
| E4626-SEC-005 | ERC-4626 側の asset loss は `estimatedTotalUnderlying()` と Vault `totalUnderlying()` に下方反映される | unit |
| E4626-SEC-006 | 緊急回収は redeem 後の Underlying を同一 tx 内で Vault へ push し、Vault 実受領額を returned principal として記帳し、`backingRatio()` の一時的な過小評価 window と部分回収後 writeoff の二重計上を作らない | unit |
| E4626-SEC-007 | `deposit` / `withdraw` / `redeem` は share balance before/after と ERC-4626 返り値を照合し、不一致を `ERC4626ShareBalanceMismatch` で会計不整合として revert する。通常 `withdraw` / `emergencyWithdrawFromERC4626` は要求 asset 量または `redeem` 返り値 asset 量と Underlying 実増分も照合し、不一致を `ERC4626AssetAmountMismatch` で revert する。通常 `withdraw` で asset が来たのに share burn が 0 の場合は `ERC4626ZeroShares` で revert する | unit |
| E4626-SEC-008 | Merkl / 外部 reward claim は、Underlying reward を Vault buffer へ push し、非 Underlying・非 ERC-4626 share token の通常 reward を Treasury へ sweep する。ERC-4626 share token / protected position token は distributor 呼び出し前に拒否し、claim / sweep は `principal`、`estimatedTotalUnderlying()` を変更してはならない | unit |
| E4626-SEC-009 | donation を含む raw share の部分緊急 redeem 後は `_ownShares = min(ownSharesBefore, shareBalanceAfter)` とし、donation share を owned share より先に消費する。share price 低下後の repair donation と部分回収を組み合わせても、残存自己 share を tracker 上だけ追加毀損させてはならない | unit |

---

## 5. Morpho / Euler への適用条件

`ERC4626Strategy` を Morpho Vault / EulerEarn に適用する場合、登録前に最低限以下を確認する。

1. `asset()` が Vault の Underlying と完全一致すること。
2. share token が transfer 可能でも、通常評価は `_ownShares` に限定されること。
3. `convertToAssets` が実現済み bad debt / share price loss を下方反映すること。Morpho 系では collateral depeg や oracle 遅延だけでは即時に下がらず、清算・bad debt 確定後に supply asset 側へ反映される点を前提に、別途 venue / oracle / market health 監視を置くこと。
4. `maxWithdraw` / `maxRedeem` が liquidity limit を返す場合でも、`sendToVault` は revert ではなくその時点の withdrawable amount までに抑えること。
5. curator / allocator / market selection / oracle / liquidation risk は Strategy code ではなく、採用 vault の governance・cap・weight・runbook で制御すること。
6. Merkl 等の外部 reward は、Underlying reward なら Vault buffer へ push し、非 Underlying・非 share token の通常 reward なら Treasury sweep として扱えるものに限定すること。ERC-4626 share token / protected position-token rewards は distributor 呼び出し前に拒否されること。
7. Morpho Vault V2 のように `maxWithdraw` / `maxRedeem` が仕様上 0 の vault は、本 adapter の回収
   上限が常に 0 になるため、`ERC4626Strategy` の採用対象にしない。Morpho Vaults V2 は max\* view に
   依存しない専用の [`MorphoV2Strategy`](./MorphoV2Strategy.md)（kind `morpho-v2`）経由で採用し、
   activation gate は [Morpho-Operation-Policy](../../../operations/policies/Morpho-Operation-Policy.md)
   に定める。
8. Euler Reward Streams のように reward が外部 distributor に留まり pull claim を要する場合、現行
   `ERC4626Strategy` の `claimMerklRewards` / `sweepRewardToken` では回収できない。対象 vault でその
   reward 経路が無効であることを activation evidence で確認するか、venue 固有 claim 実装、settlement
   unit / fork test、追加 audit を完了するまで登録・allocation してはならない。未 claim reward は
   `estimatedTotalUnderlying()` や backing に算入しない。

---

## 6. Verification

- `ERC4626StrategyTest`
  - asset mismatch reject
  - share token sweep reject / reward sweep allow
  - share donation does not inflate AUM/yield
  - zero-share deposit reject
  - ERC-4626 return value / share balance delta mismatch reject
  - ERC-4626 withdraw zero-share burn / asset delta mismatch reject
  - ERC-4626 emergency redeem reported assets / actual Underlying delta mismatch reject
  - asset loss reflected in Strategy and Vault totals
  - withdrawal respects ERC-4626 maxWithdraw
  - share-price yield harvest preserves principal
  - emergency redeem + atomic Vault push + returned principal accounting
  - partial emergency recovery followed by residual writeoff
  - asset loss + share donation + partial emergency recovery preserves remaining owned-share valuation
  - emergency path does not transiently discount `backingRatio()`
  - Merkl reward claim sweeps ordinary reward token to Treasury without changing Strategy / Vault accounting
  - Merkl Underlying reward claim pushes actual received amount to Vault buffer
  - Merkl claim rejects ERC-4626 share token before distributor call
