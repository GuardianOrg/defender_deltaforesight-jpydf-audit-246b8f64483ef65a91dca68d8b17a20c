# 形式検証監査計画

## 0. 目的

本書は、`develop` ブランチの現行コードを前提に、JPYdf v2 の形式検証監査をどの順序で進めるかを定義する計画書である。

形式検証では、プログラムを実行してエラーを探すのではなく、コードと外部依存を数学的なモデルとして扱い、任意の入力・任意の到達可能状態に対して守るべき性質を証明する。本計画では、dToken / CollateralVault / Strategy / Oracle / JpydfToken / Core integration を分け、各レイヤーの不変条件と証明対象を段階的に整理する。

## 1. スコープ

### 1.1 対象

形式検証の対象は、資金移動・供給量・担保価値・権限境界に影響する次の領域とする。

| 領域 | 主な対象 | 監査の焦点 |
| --- | --- | --- |
| dToken | `DToken` | mint / burn 権限、Underlying 換算、cap、token info binding |
| Vault | `CollateralVault` | deposit / redeem / claim、pending withdrawals、backstop reserve、backing ratio |
| Strategy | `BaseStrategy`, `AsyncRequestStrategy`, 各 Strategy 実装 | principal accounting、push model、async request、valuation、emergency recovery |
| Oracle | `PriceFeedProxy`, `DFPriceFeedBase`, 各 PriceFeed | source switching、invalid price、JPY freeze、dToken backing 乗算 |
| JPYdf token | `JpydfToken` | Core supply path と dormant bridge-ready supply path の分離 |
| Core integration | Liquity v2 Core との接続境界 | Core parity、dToken collateral、PriceFeedProxy、JPYdf supply path |

### 1.2 対象外

次は本計画の直接の証明対象にしない。

- Aave / Lido / Sky / Etherfi 等の外部 protocol 自体の完全証明
- Chainlink や外部 rate provider 自体の正しさ
- UI / subgraph / off-chain bot の完全性
- Liquity v2 Core 全体の再証明

外部 protocol や ERC20 は、Strategy / Vault が依存する interface と失敗モードだけを抽象モデルとして扱う。

## 2. 正本資料

仕様・モデル境界の正本は次の資料とする。

- `documents/jp/protocol/product/Product-Overview.md`
- `documents/jp/protocol/product/spec/*.md`
- `documents/jp/protocol/product/spec/strategies/*.md`
- `documents/jp/protocol/product/spec/Liquity-v2-Core-Spec.md`
- `contracts/src/Dependencies/Constants.sol`

実装 PR では、これらの資料から証明対象の要件 ID と不変条件を引用し、CVL 等の仕様へ落とす。

`documents/jp/engineering/guides/` の監査・実装ガイドや、`documents/jp/protocol/operations/policies/` の運用設計は、必要に応じて参考資料として読む。ただし、形式検証の proof obligation を直接定義する正本には含めない。

## 3. 進め方

### Phase 0: Model Boundary

最初に、検証対象のコード、外部依存、環境仮定を固定する。

- 外部 protocol は完全証明せず、Strategy が依存する戻り値・revert・残高変化・claim 可能状態を抽象化する。
- ERC20 は standard token、fee-on-transfer、transfer revert、no-return token など、Vault / Strategy が想定する境界を分けて扱う。
- Core は全体再証明せず、dToken collateral、PriceFeedProxy、JpydfToken supply path との接続境界を扱う。
- 証明仕様は、実装・仕様書・監査対象の責務境界が一致していることを確認してから追加する。

### Phase 1: Supply / Authority

最初に、状態空間が小さく影響が大きい supply と authority を証明する。

| ID | 対象 | 証明命題 |
| --- | --- | --- |
| FV-DTKN-001 | `DToken.mint` / `DToken.burn` | `vault` 以外は mint / burn できない |
| FV-DTKN-002 | `DToken.setTokenInfo` | token info は一度だけ設定でき、未設定状態では mint できない |
| FV-DTKN-003 | `DToken.convertTo*` | Underlying base unit に対する往復換算が正しく、silent rounding loss を起こさない |
| FV-DTKN-004 | `DToken.mint` | cap 超過 mint は必ず revert する |
| FV-JPYDF-001 | `JpydfToken.mint` / `burn` / `bridgeMint` / `bridgeBurn` | Core supply path と bridge supply path の caller set が交差しない |
| FV-JPYDF-002 | bridge minter registry | bridge minter は許可された contract address のみで、admin 系 role と兼任できない |
| FV-JPYDF-003 | bridge minter timelock | minter 追加は timelock 経過前に確定できず、削除時に count が正しく減る |

この phase の目的は、供給量を増減できる経路をすべて列挙し、権限境界が交差していないことを先に証明することである。

### Phase 2: Vault Accounting

次に、CollateralVault の資産・負債・請求権の会計を証明する。

| ID | 対象 | 証明命題 |
| --- | --- | --- |
| FV-VAULT-001 | `deposit` | 実着額 `received` を超える dToken を mint しない |
| FV-VAULT-002 | `redeem` / `redeemWithPermit` | dToken 端数を silent burn しない。exact conversion 不能なら burn 前に revert する |
| FV-VAULT-003 | `redeem` / `claim` | request 作成で `pendingWithdrawals` が増え、claim 成功で一度だけ減る。二重 claim は不可 |
| FV-VAULT-004 | `backstopDeposit` / `releaseBackstopToBuffer` | protected backstop reserve は明示 release まで redeem / claim / allocate / treasury 原資にならない |
| FV-VAULT-005 | `totalUnderlying` / `backingRatio` | Strategy value は保守的に評価され、`backingRatio <= 1e18` が保たれる |
| FV-VAULT-006 | `addStrategy` | `strategy.underlying() == vault.underlying()` でなければ登録できない |
| FV-VAULT-007 | `allocate` | pending withdrawals、buffer target、backstop reserve を侵食して Strategy へ送れない |
| FV-VAULT-008 | `writeoffStrategyPrincipal` | registered Strategy のみ writeoff でき、実行後 backing ratio guard を満たさなければ成立しない |

この phase では、単純な token balance だけではなく、liquid buffer、pending withdrawals、protected backstop reserve、Strategy conservative value を分けて扱う。

### Phase 3: Strategy Family

Strategy は、共通基底と個別 adapter を分けて証明する。

| ID | 対象 | 証明命題 |
| --- | --- | --- |
| FV-STGY-001 | `BaseStrategy.deposit` | `onlyVault`。deposit 成功時に principal は `_amount` だけ増える |
| FV-STGY-002 | `BaseStrategy.sendToVault` | Vault 実受領額を超えて principal を減らさず、underflow しない |
| FV-STGY-003 | `BaseStrategy.sendProfitToVault` | yield-only push は principal を減らさない |
| FV-STGY-004 | `BaseStrategy.emergencyWithdraw` | 送金先は常に Vault であり、任意アドレスへ送れない |
| FV-STGY-005 | `AsyncRequestStrategy` | pending request amount と request id 集合が二重計上・二重 claim されない |
| FV-STGY-006 | `AaveV3Strategy` / `ERC4626Strategy` | 外部 protocol の観測値が不利に動いても、自己 tracking 分を超えて過大 valuation しない |
| FV-STGY-007 | `LidoStrategy` / `EtherfiWeETHStrategy` | async claim 前の pending と claim 済み idle underlying が同時に二重 valuation されない |
| FV-STGY-008 | `SkyUsdcSUsdsStrategy` | USDC -> USDS -> sUSDS の変換で min-out / max-loss guard を下回る場合は state を進めない |

この phase では、外部 protocol の正しさを仮定しすぎない。外部 protocol が illiquid、revert、低い回収額を返す、claim 待ちになる等の状態でも、Strategy 側の principal / valuation / push accounting が破綻しないことを証明する。

### Phase 4: Oracle / PriceFeed

Oracle は、「正常価格を返す」ことよりも「壊れた source が不正価格を cache / serve できない」ことを中心に証明する。

| ID | 対象 | 証明命題 |
| --- | --- | --- |
| FV-ORCL-001 | `PriceFeedProxy.fetchPrice` / `fetchRedemptionPrice` | source が invalid price / failure flag / revert を返しても invalid price を `_lastGoodPrice` に保存しない |
| FV-ORCL-002 | `PriceFeedProxy.confirmSource` | timelock 経過前は source 変更不可。新 source smoke test 失敗時は source が変わらない |
| FV-ORCL-003 | `PriceFeedProxy.confirmSourceEmergency` | emergency は価格差 guard のみ bypass し、timelock と smoke test は bypass しない |
| FV-ORCL-004 | `PriceFeedProxy` | source 変更成功時、cache は新 source の価格で再初期化され、旧 source の last good を使い回さない |
| FV-ORCL-005 | `DFPriceFeedBase` | JPY/USD failure 時の freeze は有界であり、期限超過後は failure として扱う |
| FV-ORCL-006 | `DFPriceFeedBase._applyBackingRatio` | `backingRatio <= 1e18` のとき、dToken price は market price を超えない |

この phase では、source の ABI 不整合、revert、invalid sentinel、failure flag、stale 状態を明示的にモデル化する。

### Phase 5: Core Integration

最後に、Liquity v2 Core と JPYdf 独自レイヤーの接続境界を証明する。

| ID | 対象 | 証明命題 |
| --- | --- | --- |
| FV-CORE-001 | `Liquity-v2-Core-Spec.md` `CORE-MOD-*` | documented modified surface 以外を proof scope に混ぜない |
| FV-CORE-002 | dToken collateral integration | Core は dToken を普通の 18dec ERC20 collateral として扱い、Vault 内部会計へ依存しない |
| FV-CORE-003 | Oracle integration | Core の price source は `PriceFeedProxy` 固定で、source 差替は Proxy 内に閉じる |
| FV-CORE-004 | JpydfToken integration | Core supply path と bridge supply path の totalSupply 変化は entrypoint ごとに分離される |

この phase では、Core の全機能を再証明するのではなく、外側レイヤーを接続しても Core parity と責務分離が崩れないことを扱う。

## 4. PR 化の優先順位

形式検証の実装 PR は、次の順に小さく分ける。

1. dToken + JpydfToken の supply / authority 仕様追加
2. PriceFeedProxy の source switching / invalid price 仕様追加
3. CollateralVault の deposit / redeem / claim / backstop 仕様追加
4. BaseStrategy + AsyncRequestStrategy の principal / request accounting 仕様追加
5. 個別 Strategy の protocol model 追加
6. Core integration / parity boundary の接続仕様追加

この順序にする理由は、初期 PR では状態空間が小さく仕様の読み替えが少ない対象から始め、Vault / Strategy のように広い状態空間を持つ対象を分割して扱うためである。

## 5. 未実施事項

本書は計画書であり、CVL 仕様、harness、外部 protocol model、実際の proof run はまだ追加しない。

次の実作業では、Phase 1 の `DToken` / `JpydfToken` から仕様と harness を追加する。
