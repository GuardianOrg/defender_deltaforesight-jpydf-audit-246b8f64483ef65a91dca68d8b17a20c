# Anvil オンチェーン検証台帳（per-ID 実トランザクション）

> **目的**: jpydf-v2 の全要件（機能 FR / 不変 INV / セキュリティ SEC / ガバナンス GOV / イベント EVT / 失敗 ERR）を、**1 つずつ anvil（ローカルチェーン）の実トランザクション／実呼出で検証**し、各 ID に「実行方法・anvil 証跡（tx / revert selector / state / event）・結果」を残す。コード実装（forge build）・テスト（forge test）に続く **第3軸＝チェーン実行**の三重化を、要件単位で積み上げる。
>
> **位置づけ**: 本台帳は **検証固定点 `30d078b`（2026-06-20）で実施した anvil セッションの履歴スナップショット**である。forge スイートは同固定点で **1170 passed**（テスト軸は緑）。per-ID の forge マッピング（`PASS@tip` 約 592）は PR #258 の V1 campaign を参照するが、PR #258 が未マージの場合は本リポの主台帳 / Core 台帳の表示件数と一時的に食い違う。本台帳の役割はそれと重複せず、**「ローカルチェーン上で正常系・異常系が実際に再現するか」を実 tx で確かめる第3軸**。本 PR 時点で **約 191 ID を anvil で実証済み**（全 6 カテゴリ・SYS 中核フローの代表を網羅、未完了は §4）。current `develop` の実装・ID 母数は merge / rebase 時点で再確認する。

| 項目 | 値 |
| --- | --- |
| 検証固定点 | `deltaforesight/jpydf-v2` `develop` commit `30d078b`（2026-06-20 時点の履歴スナップショット） |
| 検証日 | 2026-06-20 |
| chain | anvil 31337（8 branch・5 active seed） |
| 進捗 | **約 191 / 約 1011 ID**（PR #258 V1 campaign 集計: 主台帳 594＋Core 417・概算）を anvil 実証。PR #258 未マージ時の本リポ表示件数とは一致しないことがある。残は §4 |
| 状態 | **継続中**（この固定点の続きは §1 から再現可能。current `develop` へ持ち込む場合は実装状態・ID 母数を再確認する） |

---

## 0. このPRを見た人へ（引き継ぎガイド）

**このPRは「途中まで」です。** 続きをやる人は次の順で読めば、環境を再構築して残りの ID を同じ方式で検証できます。

1. **何が終わっているか** → §0.1 完了サマリ ＋ §3 の証跡テーブル（ID 単位）。
2. **どう再現するか** → §1 の再現レシピ（anvil 起動 → deploy → seed をコピペで再現。アドレスは salt 固定で**決定論的に同一**）。
3. **どの語彙で記録するか** → §2 結果語彙。
4. **どこから続けるか** → §4 未完了マップ（component × 残カテゴリ。1 チャンクずつ担当できる粒度）。
5. **ハマりどころ** → §5 gotcha（troveId 公式・オラクル staleness・access-control revert の空 data など。**ここを読まないと同じ所で詰まる**）。

### 0.1 完了サマリ（約 191 ID・全 6 カテゴリ）

| カテゴリ | anvil で実証した代表 | 証跡 § |
| --- | --- | --- |
| **FR 機能** | 借入・現物償還・SP 入出金・**trove-lifecycle 全工程**（open/addColl/withdrawColl/借入/返済/close）・**Redemption**・**3層清算(SP offset)**・**Zapper 1-tx open**・**利息発生→IRTR/SP 分配**・branch param・Core view 群 | §3.5,3.8,3.15,3.17,3.18 |
| **INV 不変** | backingRatio=1e18・decimals=18・**SCR<MCR<CCR**・清算ペナルティ大小・供給経路単一性・ST size↔trove 数整合・利息保存則 | §3.1,3.10,3.11,3.15 |
| **SEC セキュリティ** | OnlyVault・Ownable・AccessControl・**Core caller 制限7関数**（sendColl/offset/insert 等 非権限→revert）・Strategy upgrade 非権限拒否・transfer protection | §3.2,3.14 |
| **GOV ガバナンス** | role 別操作・pause/unpause・**owner-renounce immutable**・timelock ceremony(drill) | §3.2,3.10 |
| **EVT イベント** | CapUpdated・Deposited・Redeemed・Paused・Transfer(mint) を **receipt の topic0 で発火実証** | §3.13 |
| **ERR 失敗** | DebtBelowMin・ICRBelowMCR・InterestRateTooHigh・空配列清算・NothingToLiquidate・EmptyManager・WrongETH・ZeroAmount・TokenInfoNotSet 他 | §3.16,3.18 |

⇒ **SYS 中核フローの代表経路を anvil 実 tx で実証**: 借入(SYS-FR-001)・現物償還(FR-002)・外部運用 push(FR-003)・**ペグ自律是正(FR-004)=Redemption＋Liquidation 両方**・JPY建てオラクル正常系(FR-005)・供給経路単一性(INV-003)。Oracle staleness の cast 単体再現など未完了の異常系は §4 に残す。

---

## 1. 環境・再現レシピ（コピペで同一環境を再構築）

> anvil の state は揮発（プロセス停止で消える）。salt を固定しているので、**再デプロイしても CREATE2 アドレスは同一**（§1.3 のアドレス表がそのまま使える）。

### 1.1 anvil 起動（常駐）
```bash
~/.foundry/bin/anvil --port 8545 --chain-id 31337 --base-fee 0 --gas-limit 60000000
```

### 1.2 デプロイ＋ seed（別シェルで）
```bash
cd <jpydf-v2 clone>/contracts          # ※ Google Drive 上で forge を走らせない。使い捨て clone を使う
DK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80   # anvil#0
DA=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
NONK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d # anvil#1（非権限テスト用）
CAP=115792089237316195423570985008687907853269984665640564039457584007913129639935

# deploy（salt 固定＝アドレス決定論）
DEPLOYER=$DK SALT=jpydf-drill-1 \
  DF_TREASURY=$DA DF_INTEREST_ROUTER_RECIPIENT=$DA DF_INTEREST_ROUTER_OWNER=$DA \
  DF_STRATEGY_KIND=aave DF_STRATEGY_WEIGHT_BPS=10000 DF_STRATEGY_CAP=$CAP \
  forge script DeployLiquity2Script --chain-id 31337 --rpc-url http://localhost:8545 --broadcast --slow

# seed（デモ trove / SP 預入を作る）
DEPLOYER=$DK forge script SeedLocalDemo --chain-id 31337 --rpc-url http://localhost:8545 --broadcast --slow

# Multicall3 を注入（frontend / MultiTroveGetter 用）
cast rpc anvil_setCode 0xcA11bde05977b3631167028862bE2a173976CA11 "$(cat utils/multicall3-runtime.hex)" -r http://localhost:8545
```
デプロイ後 `contracts/deployment-manifest.json` に全アドレスが出力される（§1.3 はその branch0 抜粋）。`ONCHAIN EXECUTION COMPLETE` が 2 回出れば deploy+seed 成功。

### 1.3 主要アドレス（branch0・salt `jpydf-drill-1`・決定論）
| 役割 | アドレス |
| --- | --- |
| collateralRegistry | `0x02b0b4efd909240fcb2eb5fae060dc60d112e3a4` |
| jpydfToken | `0x39b67ed1371cdf78cd0e6d4f0b78fa17a6dea663` |
| dToken(dETH) | `0x9a676e781a523b5d0c0e43731313a708cb607508` |
| collateralVault | `0x959922be3caee4b8cd9a407cc3ac1c251c2007b1` |
| strategy(AaveV3) | `0xe6e340d132b5f46d1e472debcd681b2abc16e57e` |
| WETH(underlying) | `0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0` |
| BorrowerOperations | `0xc9eda9ef65702d8d33b337890ef22e244424cd66` |
| TroveManager | `0xb6faae2bc2d55a9f041f255c8f373f2ff2bf7001` |
| StabilityPool | `0xcbc69577db47a4bf19b702f73a3ffdd1caa617ec` |
| sortedTroves | `0x61d7420ccee5db7680c68f59000320f7dde1d315` |
| priceFeed(branch0) | `0x96f3ce39ad2bfdcf92c0f6e2c2cabf83874660fc` |
| collUsdFeed(ETH/USD) | `0x59b670e9fa9d0a427751af201d676719a970857b` |
| jpyUsdFeed(JPY/USD) | `0x5fc8d32690cc91d4c39d9d3abcbd16989f875707` |
| interestRouter | `0x5b17e9f5ac8dae94731f7d8869d0d64f1a7f05c7` |
| zapper(CollateralYield) | `0x74cf9087ad26d541930bac724b7ab21ba8f00a27` |

> deployer/owner = anvil#0 `0xf39F…2266`（governance handover 前なので各 owner/role を保持）。非権限テスト用 = anvil#1 `0x7099…79C8`（key `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d`）。

### 1.4 検証の出し方（cast の最小形）
```bash
RPC=http://localhost:8545; C=~/.foundry/bin/cast
$C call  <addr> 'fn()(type)'            -r $RPC          # view 検証
$C send  <addr> 'fn(args)' <vals> --private-key $DK -r $RPC   # tx 検証（happy）
$C send  <addr> 'fn(args)' <vals> --private-key $NONK -r $RPC # 非権限→revert（異常系）
$C rpc evm_snapshot / evm_revert <id>   # 破壊的・時間依存テストの隔離
$C receipt <txhash> --json | jq .logs   # EVT: 発火イベントの topic0/data
```

---

## 2. 結果語彙
- `PASS@anvil(tx)` = 実 tx 成立＋期待 state/event 確認（正常系）。
- `PASS@anvil(revert)` / `PASS@anvil(revert:<selector>)` = 実 tx が期待どおり revert（異常系）。
- `PASS@anvil(view)` = view 呼出で期待値・相互整合を確認。
- `PASS@anvil(event)` = 実 tx receipt のログでイベント発火（topic0 一致）を確認。
- `PASS@tip` = 検証固定点 / PR #258 V1 campaign の forge スイート（テスト軸）で緑。本台帳では時間依存系の補助参照に使う（per-ID の forge 側参照元は PR #258）。
- `BLOCKED(未実装)` = 検証固定点 `30d078b` では実装が無い（SKY / Treasury）。 / `TODO` = 未着手。

---

## 3. 検証済み ID（証跡）

### 3.1 dToken（branch0 `0x9a676e…7508`）
| ID | カテゴリ | 実行内容 | 証跡 | 結果 |
| --- | --- | --- | --- | --- |
| DTKN-INV-001 | INV | `decimals()` | `=18` | PASS@anvil(view) |
| DTKN-FR-001 | FR | `name()`/`symbol()`/`cap()` | `"DToken dETH"`/`"dETH"`/設定済 | PASS@anvil(view) |
| DTKN-FR-003 / INV-006 | FR/INV | `convertToDToken(1e18)` | `=1e18`（18dec・倍率1） | PASS@anvil(view) |
| DTKN-FR-004 正常系 | FR | WETH→`vault.deposit(1e18)`→mint | balance `0→1e18` | PASS@anvil(tx) |
| DTKN-FR-004 / SEC-001 / INV-002 異常系 | FR/SEC | 非 vault `mint` | revert `OnlyVault 0x8d1af8bd` | PASS@anvil(revert) |
| DTKN-FR-005 / SEC-001 異常系 | FR/SEC | 非 vault `burn` | revert `OnlyVault 0x8d1af8bd` | PASS@anvil(revert) |
| DTKN-FR-006 正常系 | FR | owner `setCap` | cap 変更・tx 成立 | PASS@anvil(tx) |
| DTKN-FR-006 / SEC 異常系 | FR/SEC | 非 owner `setCap` | revert `Ownable` | PASS@anvil(revert) |
| DTKN-FR-009 / GOV-003 / SEC-006 異常系 | FR/GOV/SEC | `renounceOwnership()` | revert `RenounceOwnershipDisabled 0xffc0fd93` | PASS@anvil(revert) |
| DTKN-FR-002 / INV-010 異常系 | FR/INV/ERR | 確定後 `setAllowedUnderlying` | revert `TokenInfoAlreadySet 0xc60a4ce9` | PASS@anvil(revert) |

### 3.2 CollateralVault（branch0 `0x959922…`）
| ID | カテゴリ | 実行内容 | 証跡 | 結果 |
| --- | --- | --- | --- | --- |
| VAULT-FR-016 / INV-001/012 | INV | `backingRatio()` | `=1e18`（健全） | PASS@anvil(view) |
| VAULT-FR-013 | FR | `totalUnderlying()`/`bufferBalance()` | `5.7e19` | PASS@anvil(view) |
| VAULT-FR-014 / SEC-006 正常系 | FR/GOV | `pauseDeposit`(GUARDIAN)→`unpauseDeposit`(GOV) | paused→unpaused | PASS@anvil(tx) |
| VAULT-FR-001 / ERR-Paused 異常系 | FR/ERR | pause 中 `deposit` | revert(Paused) | PASS@anvil(revert) |
| VAULT-FR-014 / GOV-002 異常系 | SEC/GOV | 非 GUARDIAN `pauseDeposit` | revert（access・data `0x`※） | PASS@anvil(revert) |
| VAULT-FR-004 / SEC-005 異常系 | SEC | 非 ALLOCATOR `allocate` | revert（access） | PASS@anvil(revert) |
| VAULT-FR-004 正常系 | FR | `allocate()`(ALLOCATOR) → strategy push | strategy `estimatedTotalUnderlying=4.56e19` | PASS@anvil(tx) |
| VAULT-FR-012 正常系 / 異常系 | FR/GOV/SEC | `setTreasury`(GOV) 成立・非 GOV revert | 反映／revert | PASS@anvil(tx/revert) |
| VAULT-FR-002 正常系 | FR | `redeem(5e17)` 即時 | dToken `1e18→5e17`・WETH `+5e17` | PASS@anvil(tx) |
| VAULT-ERR ZeroAmount | ERR | `deposit(0)`/`redeem(0)` | revert `0x1f2a2005` | PASS@anvil(revert) |

※ access-control 系の revert は data 空（`0x`）で返る（`AccessControlUnauthorizedAccount 0xe2517d3f` ではない）。権限者成功×非権限者 revert の差分で制御を実証（§5 gotcha 参照）。

### 3.3 Oracle（PriceFeedProxy branch0 `0x96f3ce…`）
| ID | カテゴリ | 実行内容 | 証跡 | 結果 |
| --- | --- | --- | --- | --- |
| ORCL-FR-001/004 正常系 | FR | `fetchPrice()` | `=6e23`・failed=false（JPY建て） | PASS@anvil(view) |
| ORCL-FR-002 正常系 | FR | `fetchRedemptionPrice()` | `=6e23` | PASS@anvil(view) |
| ORCL-INV lastGoodPrice | INV | `lastGoodPrice()` | `=6e23` | PASS@anvil(view) |
| ORCL-FR-004 / ERR staleness 異常系 | ERR | `+25h`→`fetchPrice`→failsafe（snapshot 隔離） | staleness failsafe は forge oracle fork-test が `PASS@tip`（テスト軸は緑）。**anvil cast 単体での縮退再現は未完了**で、§4 Oracle の残作業として継続 | TODO@anvil / PASS@tip |

### 3.4 Strategy（AaveV3Strategy branch0 `0xe6e340…`）
| ID | カテゴリ | 実行内容 | 証跡 | 結果 |
| --- | --- | --- | --- | --- |
| STGY-INV-008 underlying | INV | `strategy.underlying()==vault.underlying()` | 一致 | PASS@anvil(view) |
| STGY-FR estimatedTotalUnderlying | FR | allocate 後の運用残高 | `4.56e19`（push 反映） | PASS@anvil(tx,view) |
| STGY-GOV owner/upgrader | GOV | `owner()`/`upgrader()` | deployer 保持 | PASS@anvil(view) |
| STGY-FR-009 / SEC-002/008 異常系 | SEC | 非 upgrader `setUpgrader` | revert | PASS@anvil(revert) |

### 3.5 Core ユーザーフロー（borrow / SP / Redemption / JpydfToken・branch0）
| ID | カテゴリ | 実行内容 | 証跡 | 結果 |
| --- | --- | --- | --- | --- |
| SYS-FR-001 / BO-FR-001 正常系 | FR | `openTrove`（過剰担保で借入） | troves `4→5`・JPYdf `+400,000` | PASS@anvil(tx) |
| SP-FR provideToSP 正常系 | FR | `provideToSP(100k,false)` | SP `getCompoundedJpydfDeposit=2.112e24` | PASS@anvil(tx) |
| SP-FR withdrawFromSP 正常系 | FR | `withdrawFromSP(50k)` | deposit `2.112e24→2.062e24` | PASS@anvil(tx) |
| SYS-FR-004 / CR / TM redemption 正常系 | FR | `registry.redeemCollateral(10k,0,1e18)`（全8branch走査） | JPYdf burn・totalSupply `5.784e25→5.783e25` | PASS@anvil(tx) |
| SYS-INV-003 / 供給単一性 異常系 | INV/SEC | 非 Core から `JpydfToken.mint` | revert（Core mint/burn のみ） | PASS@anvil(revert) |
| BT-FR-008 transfer protection 異常系 | SEC | protocol アドレスへ `JpydfToken.transfer` | revert | PASS@anvil(revert) |

### 3.6 InterestRouterForwarder（PIL・branch0 `0x5b17e9…`）
| ID | カテゴリ | 実行内容 | 証跡 | 結果 |
| --- | --- | --- | --- | --- |
| IRTR-FR recipient/owner | GOV | `recipient()`/`owner()` | =deployer | PASS@anvil(view) |
| IRTR-FR-001 route 正常系 | FR | `route()`（PIL 25% を recipient へ） | recipient JPYdf `7.84e24→7.852e24` | PASS@anvil(tx) |
| IRTR-SEC-001 異常系 | SEC | 非 owner `setRecipient` | revert | PASS@anvil(revert) |

### 3.7 Zapper 配線（CollateralYieldZapper `0x74cf90…`）
| ID | カテゴリ | 実行内容 | 証跡 | 結果 |
| --- | --- | --- | --- | --- |
| ZAP-INV vault 配線 | INV | `collateralVault()==branch0 vault` | 一致 | PASS@anvil(view) |
| ZAP-SEC-007 receive 異常系 | SEC | zapper へ直接 ETH 送付 | revert `OnlyWETH` | PASS@anvil(revert) |

### 3.8 trove-lifecycle ＋ 清算（branch0・正しい troveId）
> troveId 公式 = `keccak256(abi.encode(msg.sender, _owner, _ownerIndex))`（**3引数**・`BorrowerOperations.sol:325`）。§5 gotcha 必読。

| ID | カテゴリ | 実行内容 | 証跡 | 結果 |
| --- | --- | --- | --- | --- |
| BO-FR-001 open 正常系 | FR | `openTrove`(6 dETH, 500k) | status `=1`(active) | PASS@anvil(tx) |
| BO-FR addColl / withdrawColl 正常系 | FR | `addColl(+2)`/`withdrawColl(-1)` | 実tx 成立 | PASS@anvil(tx) |
| BO-FR withdrawJpydf 正常系（借入） | FR | `withdrawJpydf(+100k)` | JPYdf `8e24→8.1e24` | PASS@anvil(tx) |
| BO-FR repayJpydf 正常系（返済） | FR | `repayJpydf(-100k)` | 実tx 成立 | PASS@anvil(tx) |
| BO-FR closeTrove 正常系 | FR | `closeTrove`（全返済→担保返却） | status `=2`(closedByOwner) | PASS@anvil(tx) |
| **TM-FR / SYS-FR-004 清算（3層 SP offset）** | FR | 低CR trove→価格18%下落→`batchLiquidateTroves`（snapshot 隔離） | status `=3`(closedByLiquidation)・**SP `5e24→2.497e24`（債務を SP offset で吸収）** | PASS@anvil(tx) |

### 3.9 branch 別パラメータ（branches 0–4）
| ID | 検証内容 | 証跡 | 結果 |
| --- | --- | --- | --- |
| DTKN-INV-001（全 branch） | dToken.decimals | 5/5 `=18` | PASS@anvil(view) |
| DTKN-FR-003 非18dec ラップ | `convertToDToken` | dUSDC/dUSDT/dXAUT(6dec)・dETH/dUSDS(18dec) すべて`→1e18` | PASS@anvil(view) |
| ORCL per-branch price | `fetchPrice()` failed=false | dETH`¥600k`/dUSDC・dUSDT`¥150`/dUSDS`¥160`/dXAUT`¥480k` | PASS@anvil(view) |

### 3.10 PRM 値突合（addressesRegistry・per branch）＋ JpydfToken
| ID | 検証内容 | 証跡 | 結果 |
| --- | --- | --- | --- |
| PRM-MCR/SCR/BCR/CCR（全 branch・絶対値） | `addressesRegistry` 取得 | dETH`119.18/110/10/132.61%`・dUSDC・dUSDT`111.58/105/10/124.5%`・dUSDS`114.71/105/10/131.58%`・dXAUT`129/110/10/152.93%` | PASS@anvil(view) |
| PRM-INV-001 SCR<MCR<CCR（全 branch） | 大小関係成立 | 例 dETH`110<119.18<132.61` | PASS@anvil(view) |
| PRM-BCR（mapping GAP 解消） | BCR=`10%` 全 branch | 実値取得 | PASS@anvil(view) |
| VAULT-INV-001 backingRatio（全 branch） | `=1e18` | 5/5 健全 | PASS@anvil(view) |
| BT-FR-010 / CORE-MOD-001（GAP 解消） | `JpydfToken.name/symbol/decimals` | `"JPYdf Stablecoin"`/`"JPYdf"`/`18` | PASS@anvil(view) |
| SYS-GOV-001 owner renounce | `JpydfToken.owner()` | `=0x0`（renounce 済＝immutable） | PASS@anvil(view) |

### 3.11 Core helpers / pools / 清算ペナルティ
| ID | 検証内容 | 証跡 | 結果 |
| --- | --- | --- | --- |
| MTG-FR-001（GAP 解消） | `MultiTroveGetter.getMultipleSortedTroves(0,0,3)` | 配列返却（frontend 直結 view） | PASS@anvil(view) |
| HH-FR getApproxHint | `HintHelpers.getApproxHint` | hint 返却 | PASS@anvil(view) |
| GP-FR-001（GAP 解消） | GasPool→BO の `WETH.allowance` | `=max`（`1.157e77`） | PASS@anvil(view) |
| PRM-INV-003（全 branch） | `LIQUIDATION_PENALTY_SP ≤ REDISTRIBUTION` | SP`5%`≤Redist`10%`（5/5） | PASS@anvil(view) |
| PRM-INV-004（全 branch） | `1+PENALTY_SP ≤ MCR` | `105%`≤MCR（5/5） | PASS@anvil(view) |

### 3.12 inert branch（5–7）placeholder 封じ込め
| ID | 検証内容 | 証跡 | 結果 |
| --- | --- | --- | --- |
| DTKN-FR-001 placeholder（5–7） | `cap()`/`name()` | `cap=0`・`"DToken Placeholder"`（3/3） | PASS@anvil(view) |
| DTKN-INV-008 異常系（5–7） | placeholder `convertToDToken` | TokenInfoNotSet revert（3/3） | PASS@anvil(revert) |
| VAULT-INV-011 封じ込め（5–7） | inert vault `deposit` | revert（3/3・活性化前は封じ込め） | PASS@anvil(revert) |
| SYS-GOV-001 異常系 | renounce 後 `setBranchAddresses` | revert（immutable 確定） | PASS@anvil(revert) |

### 3.13 イベント発火（EVT・実 tx receipt の log）
> mapping で「expectEmit 欠落」が GAP だった EVT について、**on-chain では正しい topic0/param で emit される**ことを receipt で実証。

| ID | 実行内容 | 証跡 | 結果 |
| --- | --- | --- | --- |
| DTKN-EVT-002 CapUpdated | `setCap` receipt | topic0 `0xd363…` 発火 | PASS@anvil(event) |
| VAULT-EVT-001 Deposited | `deposit` receipt | topic0 `0x73a1…` 発火 | PASS@anvil(event) |
| VAULT-EVT-012 Paused | `pauseDeposit` receipt | log 発火（`0x35ed…`） | PASS@anvil(event) |
| VAULT-EVT-002 Redeemed | `redeem` receipt | topic0 `0x764a…` 発火 | PASS@anvil(event) |
| DTKN-EVT-003 Transfer(mint) | deposit tx | from=0x0 の Transfer log | PASS@anvil(event) |

### 3.14 Core caller 制限（SEC・非権限 anvil#1 から→revert）
> mapping で「非権限呼出 revert が base parity 委譲＝独自テスト無し」とされた内部呼出制限を anvil 実 tx で on-chain enforcement 実証。

| ID | 実行内容 | 結果 |
| --- | --- | --- |
| AP-SEC-001 ActivePool.sendColl(非BO/TM/SP) | anvil#1 から呼出 | PASS@anvil(revert) |
| AP-SEC-002 ActivePool.receiveColl | anvil#1 から呼出 | PASS@anvil(revert) |
| DP-SEC-001 DefaultPool.sendCollToActivePool(非TM) | anvil#1 から呼出 | PASS@anvil(revert) |
| CSP-SEC-001 CollSurplusPool.accountSurplus(非TM) | anvil#1 から呼出 | PASS@anvil(revert) |
| ST-SEC-001 SortedTroves.insert(非BO/TM) | anvil#1 から呼出 | PASS@anvil(revert) |
| SP-SEC-001 StabilityPool.offset(非TM) | anvil#1 から呼出 | PASS@anvil(revert) |
| TM-SEC-001 TroveManager.onRedeemCollateral(非CR) | anvil#1 から呼出 | PASS@anvil(revert) |

### 3.15 Core view / getter（相互整合突合）
| ID | 実呼出と値 | 結果 |
| --- | --- | --- |
| CR getToken(0) / getTroveManager(0) | branch0 collToken / TM と **一致** | PASS@anvil(view) |
| CR getRedemptionRate / WithDecay / baseRate | `1e18` / `9.992e17` / `1e18` | PASS@anvil(view) |
| TM getTroveIdsCount ↔ ST getSize | `4 == 4`（整合） | PASS@anvil(view) |
| ST isEmpty / getFirst / contains | `false` / 値 / contains 判定正 | PASS@anvil(view) |
| TM getCurrentICR(first) / status / 金利 | `1.686e18`(168.6%) / `1`(active) / `5.2e16` | PASS@anvil(view) |
| **BO MCR/CCR/SCR/BCR** | `1.1918`/`1.326`/`1.1`/`0.1` e18 → **SCR<MCR<CCR 成立** | PASS@anvil(view) |
| SP getTotalJpydfDeposits / getCompoundedJpydfDeposit | `5e24` / `2e24` | PASS@anvil(view) |
| AP getCollBalance / getJpydfDebt / calcPendingAggInterest | `56 dETH` / `2.02e25` / `3.38e18` | PASS@anvil(view) |

### 3.16 異常系（ERR）— BO/TM/CR の revert 経路
> error 定義同定: `BorrowerOperations.sol:137-146`（ICRBelowMCR / DebtBelowMin / InterestRateTooLow/High 他）。

| ID | 不正入力 | 結果 |
| --- | --- | --- |
| BO-ERR DebtBelowMin | open(debt 100k < MIN_DEBT 300k) | PASS@anvil(revert) |
| BO-ERR ICRBelowMCR | open(coll 0.1 dETH・debt 300k → ICR≈20%) | PASS@anvil(revert) |
| BO-ERR InterestRateTooHigh | open(rate 200% > max) → `0xfe4a4370` | PASS@anvil(revert) |
| TM-ERR 空配列清算 | batchLiquidateTroves(`[]`) | PASS@anvil(revert) |
| TM-ERR NothingToLiquidate | batchLiquidate(`[健全 trove]`) | PASS@anvil(revert) |
| CR-ERR 0償還 | redeemCollateral(`0`,…) | PASS@anvil(revert) |

### 3.17 利息発生・分配（時間依存・`evm_increaseTime` 隔離）
> anvil でしか観測できない時間依存系。snapshot 隔離 → `+365日` → 両 feed の `updatedAt` refresh（stale 回避）→ debt 更新 op で分配発火。

| ID | 実行内容と値 | 結果 |
| --- | --- | --- |
| 利息累積（時間依存） | `+365日` で `calcPendingAggInterest` `0→1,662,345 JPYdf` | PASS@anvil(tx) |
| **IRTR-FR InterestRouter 受領** | trigger 後 IR 残高 **+415,728 JPYdf** | PASS@anvil(tx) |
| **SP yield split** | trigger 後 SP `getYieldGainsOwed` **+1,247,186 JPYdf** | PASS@anvil(tx) |
| 分配比・保存則 | IR:SP ≈ **25:75**・合計 ≈ 累積利息（一致） | PASS@anvil(tx) |

### 3.18 Zapper 1-tx open（DF独自・ETH→dToken→trove）
> "RawETH" = ガス補償のみ raw ETH（`msg.value==ETH_GAS_COMPENSATION` 固定・`L405`）、担保は underlying(WETH) を `transferFrom`。

| ID | 実行内容 | 結果 |
| --- | --- | --- |
| ZAP-FR openTroveWithRawETH | collAmount=6 WETH＋msg.value=gas comp・managers=owner → **trove数 `5→6`・success** | PASS@anvil(tx) |
| ZAP-ERR EmptyManager | managers=`0x0` で open → revert `0x22359217` | PASS@anvil(revert) |
| ZAP-ERR WrongETH | msg.value≠gas comp → revert | PASS@anvil(revert) |

---

## 4. 未完了 ID マップ（ここから続ける）

> 残の**大半は検証固定点 `30d078b` の forge スイート（1170 passed）が既にカバー済み**＝実装・テストは緑。本台帳の残作業は「それを anvil 実 tx でも再現する第3軸」。優先度は **(A) 各 component の代表異常系/EVT を実 tx で → (B) Core 詳細関数 → (C) branch 固有 → (D) frontend**。件数は概算（per-ID インベントリは PR #258 V1 campaign の主台帳／Core 台帳を参照。current `develop` では実装状態・ID 母数が変わり得る）。

| component / namespace | anvil 完了 | anvil 残（主な内容） | forge | 着手メモ |
| --- | --- | --- | --- | --- |
| dToken `DTKN` | ~10 | permit(EIP-712 署名 tx)・UUPS upgrade(新impl→upgradeTo)・2-step owner(transfer→accept)・残 EVT(TokenInfoSet/Ownership/AllowedUnderlyingUpdated)・ERR(CapExceeded/NotContract/InvalidUnderlyingDecimals) | PASS@tip | placeholder dToken を使うと未確定状態の ERR を出せる |
| CollateralVault `VAULT` | ~12 | harvest/skim・残 role 操作(GOV/GUARDIAN 網羅)・emergencyDisableStrategy(VAULT-FR-019)・残 EVT/ERR・遅延償還+claim 経路 | PASS@tip | 遅延償還は buffer 不足を作って誘発 |
| Strategy `STGY`/`AAVE`/`E4626`/`LIDO` | ~4 | deposit/withdraw/harvest 実額・allocator cooldown(時間依存)・残 SEC/EVT・LIDO 固有(stETH rebase) | PASS@tip | cooldown は `evm_increaseTime` 隔離 |
| Oracle `ORCL` | ~4 | 各 branch の staleness/失敗縮退の cast 単体再現・redemption price 分岐 | PASS@tip(+drill) | 時間依存は §5 の feed refresh 手順 |
| Zapper `ZAP` | ~5 | close/adjust/addColl WithUnderlying・Sky USDC ルート・残 SEC(leftover sweep) | PASS@tip | open は §3.18 で確立済。close は troveNFT owner 認可が要る |
| Parameters `PRM` | ~10 | 残 INV(per-branch 網羅)・bridge-minter-timelock | PASS@tip | view 中心・横展開で稼げる |
| InterestRouter `IRTR` | ~3 | 残 route 分岐・owner handover ceremony | PASS@tip | |
| **Core BO** `CORE-BO` | ~10 | adjustZombieTrove・applyPendingDebt・interestIndividualDelegate・batch 操作・shutdown 経路・残 ERR(~60) | PASS@tip | open/close/adjust は §3.8 で確立。残は派生関数 |
| **Core TM** `CORE-TM` | ~8 | urgentRedemption・redistribution 層(SP 枯渇時)・batch 清算・getLatestTroveData 系・残 view(~70) | PASS@tip | redistribution は SP を空にして誘発 |
| **Core SP** `CORE-SP` | ~6 | collGain claim・epoch/scale 遷移・残 EVT | PASS@tip | 清算後の collGain を §3.8 の続きで |
| Core CR/AP/DP/CSP/ST/HH/MTG ほか | ~12 | 各 getter/分岐の網羅・CollSurplus claim・SortedTroves 再挿入 | PASS@tip | view 横展開＋清算余剰の claim |
| **SKY Strategy** `SKY` | 0 | **全 ID BLOCKED(未実装)** | — | `30d078b` 固定点では未実装。current `develop` では実装状態が変わり得るため、継続時に再確認する |
| **Treasury** `TRSY` | 0 | **全 ID BLOCKED(未実装)** | — | `30d078b` 固定点では未実装。実装まで対象外 |
| Frontend `FRNT` | 0 | console/ops で admin 操作・app は subgraph 復旧後に Playwright で borrow/redeem/earn | e2e-local | subgraph(graph-node Docker)が要復旧。§5 参照 |

---

## 5. 既知の gotcha / lessons（これを読まないと同じ所で詰まる）

1. **troveId 公式は 3 引数**: `uint256(keccak256(abi.encode(msg.sender, _owner, _ownerIndex)))`（`BorrowerOperations.sol:325`）。`msg.sender` は openTrove の**呼び出し元**。EOA 直叩きなら EOA、Zapper 経由なら Zapper アドレス。2 引数で計算すると status=0（存在しない）になり、lifecycle/清算が全部詰まる。
2. **access-control の revert は空 data(`0x`)** で返ることがある（`AccessControlUnauthorizedAccount 0xe2517d3f` のセレクタが乗らない）。「権限者は成功・非権限者は revert」の**差分**で実証する。
3. **時間を進めるとオラクルが stale 化**: `evm_increaseTime` の後は `block.timestamp` が進むので、deploy 時の feed `updatedAt` が古くなり `fetchPrice` 系が縮退/revert する。**両 feed**（`collUsdFeed`＝ETH/USD・`jpyUsdFeed`＝JPY/USD）に `setUpdatedAt(<新 timestamp>)` を打って refresh してから操作する。価格を変えるのは `LocalChainlinkAggregator.setAnswer(int256)`（`setPrice`/`updateAnswer` ではない）。
4. **破壊的・時間依存テストは `evm_snapshot`→…→`evm_revert`** で必ず隔離（清算・価格操作・時間進行）。共有 anvil の seed state を壊さない。
5. **BOLD→JPYdf リネーム**: SP は `getTotalJpydfDeposits`/`getCompoundedJpydfDeposit`（`…BoldDeposits` は revert）。借入/返済は `withdrawJpydf`/`repayJpydf`。
6. **getter の所在**: `MCR/SCR/BCR/LIQUIDATION_PENALTY_*` は **TroveManager では revert**、`addressesRegistry`（または BO の `MCR()/CCR()/SCR()/BCR()`）から取る。`CCR()` だけは TM にもある。
7. **Zapper openTroveWithRawETH**: `msg.value` は **ETH_GAS_COMPENSATION ちょうど**（`0.0375 ETH`）。担保は underlying(WETH)を別途 `approve`＋`transferFrom`。`addManager`/`removeManager` を `0x0` にすると `EmptyManager(0x22359217)` で revert する（owner を入れる）。
8. **deploy は CLI `./deploy local` ではなく `forge script DeployLiquity2Script` を直叩き**（CLI は `DF_INTEREST_ROUTER_RECIPIENT`/`DF_STRATEGY_KIND_0` 不足で失敗した）。env は §1.2 のレシピ。
9. **Google Drive 上で forge を走らせない**（パス空白・同期で壊れる）。使い捨て clone（`/tmp/...`）で実行し、台帳だけ Drive/リポに戻す。
10. **frontend app は subgraph 必須**: graph-node の Docker（port 8020）が落ちていると subgraph deploy が `ECONNREFUSED`。app 経由フローは graph-node 復旧後に Playwright で。admin 系は subgraph 不要なので console/ops から先に進められる。

---

## 6. 関連文書
- [Requirements-Verification-Ledger.md](../../verification-ledgers/Requirements-Verification-Ledger.md) — 主台帳（本リポ上の現行表示。PR #258 未マージ時は V1 campaign 集計 594 ID と異なる場合がある）。
- [Core-Requirements-Verification-Ledger.md](../../verification-ledgers/Core-Requirements-Verification-Ledger.md) — Core(BO/TM/SP/…) 台帳（本リポ上の現行表示。PR #258 未マージ時は V1 campaign 集計 ~417 ID と異なる場合がある）。
- **PR #258**（`docs/requirements-verification-campaign-v1`）— V1 マッピング campaign（forge baseline **1170 passed**・per-row `PASS@tip` 約 592・2026-06-20 の review 群を収録）。本台帳の **forge 側カバレッジ参照元**。未マージの場合は本台帳を `30d078b` 固定点の履歴スナップショットとして扱う。
- 時間依存系（staleness/shutdown 等）は同一 anvil deploy 上で fork-test 形式の drill を流して確認できる（§5 の手順）。drill テスト自体はローカル作業物で本リポには未収録。
