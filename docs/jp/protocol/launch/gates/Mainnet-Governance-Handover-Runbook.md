# Mainnet Governance Handover Runbook

> **位置づけ**: Ethereum mainnet Day-1 deploy 後、activation 前に
> `PrepareDFGovernanceHandover.s.sol` / `VerifyDFGovernanceHandover.s.sol`
> を本番 holder 値で dry-run / fork-run し、holder separation の証跡を残す
> runbook。deploy env freeze は
> [`Mainnet-Deploy-Env-Freeze-Runbook.md`](./Mainnet-Deploy-Env-Freeze-Runbook.md)、
> Safe / role 実アドレス package は
> [`Mainnet-Safe-Role-Assignment-Gate.md`](./Mainnet-Safe-Role-Assignment-Gate.md)、
> 権限設計は
> [`Governance-Roles-Timelock.md`](../../product/policies/Governance-Roles-Timelock.md)、
> deploy 構成は
> [`Deployment-Configuration-Spec.md`](../../../engineering/guides/Deployment-Configuration-Spec.md)
> を参照する。

---

## 1. Scope

対象は `DeployLiquity2.s.sol` が出力した mainnet Day-1 manifest の
governance handover。

- `contracts/deployment-manifest.json` を `DF_HANDOVER_MANIFEST` として読む。
- `currentAdmin` は deployer / 初期 admin で、activation 後に Vault roles を失う。
- 本 runbook は private key、Safe nonce、raw `MAINNET_RPC_URL`、RPC provider API key を記録しない。証跡に残す RPC 情報は provider label と redacted URL までに限定する。
- Liquity core fork surface と `contracts/lib/**` は対象外。
- 実値で fork-run していない段階では「dry-run 済み」と記録しない。

---

## 2. Required Inputs

### 2.1 Manifest / current admin

| Env                    | 意味                                                                                           |
| ---------------------- | ---------------------------------------------------------------------------------------------- |
| `DF_HANDOVER_MANIFEST` | handover 対象 manifest。通常は `deployment-manifest.json`                                      |
| `DF_DTOKEN_CAP_CONVERSION` | 承認済み `dtoken-cap-conversion.json` のパス。mainnet の Prepare / Verify で必須 |
| `DF_CURRENT_ADMIN`     | deploy 後に Vault role / 2-step owner を保持している admin address                             |
| `DEPLOYER`             | `DF_CURRENT_ADMIN` 未指定時の fallback public address。private key は拒否する。broadcast の signer は Foundry keystore / hardware wallet / KMS から供給する |
| `DF_HANDOVER_TOTAL_BRANCHES` | Day-1 は明示的に `8`。manifest の全 branch を ownership / inert-cap 検証対象にする |
| `DF_HANDOVER_ACTIVE_BRANCHES` | Day-1 は明示的に `2`。Vault parameter / Strategy handover を行う active-wired prefix（branch 0–1） |

`DF_CURRENT_ADMIN` は、特別に `DF_ALLOW_CURRENT_ADMIN_AS_TARGET=true` を明示しない限り
Timelock / Guardian / Allocator / Writeoff / PriceFeedOwner と一致させない。
handover / verify の bool env は `true` / `1` / `yes` だけを有効扱いにし、
`false` / `0` / unset は無効扱い。

Day-1 に Vault parameter / Strategy handover を行うのは Underlying binding 済みの
dwstETH / dUSDC（branch 0–1）であり、branch 2–7 は inert-cap 検証側で扱う。現行 handover scripts の
未指定時 fallback `5` は旧 topology 向けで production 承認値ではない。両 branch-count env の未指定、
`8 / 2` 以外、manifest の active / inert 境界との不一致は No-Go とする。

### 2.2 Holder values

Holder values は [`Mainnet-Safe-Role-Assignment-Gate`](./Mainnet-Safe-Role-Assignment-Gate.md) の address book と完全に一致させる。handover env だけを手書きで差し替えた証跡は Go 条件にしない。

| Env                            | Holder / role                                                                                  |
| ------------------------------ | ---------------------------------------------------------------------------------------------- |
| `DF_TIMELOCK`                  | Vault `DEFAULT_ADMIN_ROLE` / `GOV_ROLE`、DToken owner、InterestRouter owner、Strategy upgrader |
| `DF_TREASURY`                  | Vault treasury / yield retention recipient                                                     |
| `DF_INTEREST_ROUTER_RECIPIENT` | InterestRouterForwarder recipient                                                              |
| `DF_GUARDIAN`                  | Vault `GUARDIAN_ROLE`、Strategy owner                                                          |
| `DF_ALLOCATOR`                 | Vault `ALLOCATOR_ROLE`                                                                         |
| `DF_WRITEOFF`                  | Vault `WRITEOFF_ROLE`                                                                          |
| `DF_PRICE_FEED_OWNER`          | PriceFeedProxy owner                                                                           |
| `DF_STRATEGY_OWNER`            | Strategy owner。Day-1 policy は `DF_GUARDIAN` と同一                                           |
| `DF_STRATEGY_UPGRADER`         | Strategy upgrader。Day-1 policy は `DF_TIMELOCK` と同一                                        |

`PrepareDFGovernanceHandover` は holder の nonzero と分離を fail-fast する。特に
`DF_PRICE_FEED_OWNER` は Timelock / Guardian / Allocator と分離し、`DF_GUARDIAN` と
`DF_ALLOCATOR` / `DF_WRITEOFF` も分離する。

### 2.3 Branch policy values

| Env group                            | 意味                                                      |
| ------------------------------------ | --------------------------------------------------------- |
| `DF_DTOKEN_CAP_0..7`                 | branch ごとの dToken cap。dToken の 18 decimals で投入する |
| `DF_ALLOCATE_MAX_MOVE_0..7`          | branch ごとの allocate max move。Underlying decimals で投入する |
| `DF_ALLOCATOR_COOLDOWN_0..7`         | branch ごとの allocator cooldown                       |
| `DF_WITHDRAW_DELAY_0..7`             | branch ごとの withdraw delay                           |
| `DF_BUFFER_TARGET_BPS_0..7`          | branch ごとの buffer target                            |
| `DF_BUFFER_FLOOR_0..7`               | branch ごとの buffer floor                             |

`DF_DTOKEN_CAP_i` と `DF_ALLOCATE_MAX_MOVE_i` は USD 表記ではなく、対象 dToken /
Underlying の decimals に合わせた token unit で freeze する。Day-1 の inert branch
（index 2–7）は `DF_DTOKEN_CAP_i=0`、`DF_ALLOCATE_MAX_MOVE_i=0`、dToken `totalSupply()=0`
を freeze する。Day-1 dwstETH / dUSDC の `DF_DTOKEN_CAP_0/1`
は deploy env freeze package の `dtoken-cap-conversion.json`（freeze block、
backingRatio 適用前の oracle price、計算式、丸め、reviewer sign-off）と一致させる。
mainnet の Prepare / Verify は `DF_DTOKEN_CAP_CONVERSION` からこの evidence を読み、
名目JPY上限から両値を再計算して env・dToken・Underlying address / decimals と照合する。

---

## 3. Holder Separation Matrix

| Holder         | 持つべき権限                                                                                   | 持ってはいけない権限 / 注意                          |
| -------------- | ---------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| Timelock       | Vault `DEFAULT_ADMIN_ROLE` / `GOV_ROLE`、DToken owner、InterestRouter owner、Strategy upgrader | Guardian / Allocator / Writeoff と同一にしない       |
| Guardian       | Vault `GUARDIAN_ROLE`、Strategy owner                                                          | Timelock / Allocator / Writeoff と同一にしない       |
| Allocator      | Vault `ALLOCATOR_ROLE`                                                                         | Timelock / Guardian / Writeoff と同一にしない        |
| Writeoff       | Vault `WRITEOFF_ROLE`                                                                          | Timelock / Guardian / Allocator と同一にしない       |
| PriceFeedOwner | PriceFeedProxy owner                                                                           | Timelock / Guardian / Allocator と同一にしない       |
| Treasury       | Vault treasury / yield recipient                                                               | treasury であること自体は admin role を意味しない    |
| CurrentAdmin   | prepare を実行し、activation 後は role / ownership を失う                                      | Vault roles を残さない。target holder と同一にしない |

`CollateralVault` は `AccessControlEnumerable` ではないため、on-chain から role member
を全列挙して「唯一 holder」を完全証明できない。`VerifyDFGovernanceHandover` は
宣言 holder が必要 role を持つこと、Timelock / Guardian / Allocator / Writeoff /
currentAdmin が持ってはいけない role を持たないことを確認する。未知の余分な holder を
作らないことは prepare transaction review と Safe / multisig review で補完する。

---

## 4. Fork Dry-Run Sequence

1. `MAINNET_RPC_URL` と `FORK_BLOCK` を固定し、evidence に記録する。
2. `Mainnet-Deploy-Env-Freeze-Runbook.md` の deploy env と、本 runbook の holder /
   branch policy env を同じ shell session に読み込む。
3. stateful fork evidence helper を実行する。`PrepareDFGovernanceHandover` は
   pending ownership を fork state に書くため、public RPC への broadcast なし dry-run と
   次の verify を別プロセスで実行しても pending state は残らない。helper は pinned
   anvil fork にだけ broadcast し、同じ fork state で pending verify する。

```bash
export FORK_BLOCK=<MAINNET_BLOCK_NUMBER>

pnpm -C contracts --silent mainnet-fork-evidence \
  --out /path/to/evidence-dir
```

4. `deployment-manifest.json` の `branches.length == 8`、`dfYield.length == 8`、
   active-wired 2 branch の `underlying` / `strategies[]` / `collateralYieldZapper`、
   branch 2–7 の inert state、holder separation matrix、branch policy values を
   evidence に記録する。

---

## 5. Mainnet Broadcast / Accept / Verify

### 5.1 Prepare broadcast gate

mainnet で `PrepareDFGovernanceHandover` を broadcast する前に、以下をすべて満たす。

- deploy env freeze と handover env freeze が同一 `FORK_BLOCK` で dry-run 済み。
- handover 対象 manifest の path と sha256 が deploy evidence と一致する。
- handover 対象 manifest が `mainnet-preflight --manifest` を通過している。
- holder values は Safe / Timelock / risk sheet でレビュー済み。
- holder values は Safe role assignment package の `holder-address-book.csv` / `role-assignment-matrix.csv` / Safe threshold review / consumer config diff と一致している。
- production accept plan が署名者 / calldata / target contract / order までレビュー済み。
- `DF_DTOKEN_CAP_i` と `DF_ALLOCATE_MAX_MOVE_i` は token unit で freeze 済み。
- inert branch（2–7）は `DF_DTOKEN_CAP_i == 0`、`DF_ALLOCATE_MAX_MOVE_i == 0`、dToken `totalSupply() == 0`。branch 0（dwstETH）は cap = 3,500 万円の token unit 換算値 / `DF_ALLOCATE_MAX_MOVE_0 == 0`。
- `strategyKind == "none"` の branch は product / security 的に承認済み。

### 5.2 Production accept

`AcceptDFGovernanceHandover.s.sol` は local / CI helper であり、production の Safe /
Timelock control plane には使わない。mainnet では各 holder が自分の control plane から
`acceptOwnership()` を実行する。helper 自体も chain ID 31337 / 31338 以外では、manifest や
private-key env を読む前に revert する。

| Target                                   | accept caller            |
| ---------------------------------------- | ------------------------ |
| shared `branches[i].interestRouter`      | Timelock                 |
| `dfYield[i].dToken`                      | Timelock                 |
| `branches[i].priceFeed`                  | PriceFeedOwner           |
| each `dfYield[i].strategies[j].strategy` | StrategyOwner / Guardian |

`dfYield[i].strategies` が空の branch は accept target ではない。Vault 登録 Strategy 数も
0 であることを manifest と prepare/verify output で確認する。

### 5.3 Final verify

すべての accept 完了後、pending ownership mode なしで verify する。

```bash
forge script contracts/script/VerifyDFGovernanceHandover.s.sol:VerifyDFGovernanceHandover \
  --rpc-url "$MAINNET_RPC_URL"
```

`DF_VERIFY_PENDING_OWNERSHIP=true` は accept 前の中間状態専用であり、この mode でも current
owner が `DF_CURRENT_ADMIN` / `DEPLOYER` と一致しない対象は fail する（期待 pending owner を
持つだけの任意 owner を pass させない）。final evidence では flag を外して実行する。flag なしの
verify は、`owner()` が期待 holder と一致していても interest router / price feed / dToken /
Strategy に nonzero `pendingOwner` が残っていれば reject する。

---

## 6. Failure Gates

以下のいずれかに該当する場合は broadcast / activation を止める。

- required holder env が zero address または未指定。
- `DF_HANDOVER_TOTAL_BRANCHES=8` / `DF_HANDOVER_ACTIVE_BRANCHES=2` が明示されていない、または manifest の active-wired / inert 境界と一致しない。
- Safe role assignment package が missing / No-Go / stale、または holder address book と handover env が一致しない。
- Timelock / Guardian / Allocator / Writeoff / PriceFeedOwner の分離条件を満たさない。
- `currentAdmin` が target holder と一致する、または activation 後も Vault role を持つ。
- `dfYield.length != branches.length`。
- branch ごとの `interestRouter` が単一 `InterestRouterForwarder` ではない。
- InterestRouterForwarder の token / recipient / owner / pending owner が期待値と違う。
- active branch の cap / allocate max move / buffer / withdraw delay が未 freeze または単位不明。
- branch 2–7 の cap / allocate max move が 0 でない、branch 0（dwstETH）の allocate max move が 0 でない、または handover 前に想定外の dToken supply が残っている。
- `strategyKind == "none"` の product / security 承認がない。
- production accept plan の calldata / caller / order がレビューされていない。
- manifest sha256 が deploy evidence と一致しない。
- dry-run の fork block が deploy env freeze evidence と一致しない。

---

## 7. Evidence Template

```text
Repository commit:
Manifest file:
Manifest sha256:
Chain id:
Fork block:
RPC label:
Handover total branches:
Handover active-wired branches:

Deploy dry-run command:
Deploy dry-run result:
Deploy tx hash:

Prepare dry-run command:
Prepare dry-run result:
Prepare tx hash:

Pending verify command:
Pending verify result:

Accept transactions:
- InterestRouter owner accept:
- DToken owner accepts:
- PriceFeed owner accepts:
- Strategy owner accepts:

Final verify command:
Final verify result:

Holder separation:
| Holder | Address | Expected role / ownership | Evidence |
| --- | --- | --- | --- |

Branch policy values:
| Branch | dToken cap | allocate max move | cooldown | withdraw delay | buffer target bps | buffer floor | strategy count / env kind |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |

Known limitation:
- CollateralVault is not AccessControlEnumerable, so unknown extra role holders
  are not enumerable on-chain. Review prepare transaction inputs and multisig
  history to ensure no extra holders were granted.
```
