# Product Unwind And Sunset Runbook

## 0. Scope

本 runbook は、JPY DeFi の product / market / operation 継続が望ましくない場合に、
Core を改修せず、既存 contract の cap / pause / Strategy recovery / backstop /
writeoff を使って、段階的に縮退・終了する手順を定める。

対象は Ethereum mainnet の JPY DeFi protocol 全体、または active branch 単位の
soft wind-down である。任意の global shutdown contract、Core 改修、user balance
の強制 burn、discretionary JPYdf mint は前提にしない。

関連ドキュメント:

- [`Mainnet-Launch-Operation-Gate.md`](../../launch/gates/Mainnet-Launch-Operation-Gate.md):
  launch 前の unwind plan 証跡
- [`Strategy-Incident-Liquidation-Safety-Runbook.md`](./Strategy-Incident-Liquidation-Safety-Runbook.md):
  Strategy 損失・回収・writeoff・liquidation bot safety
- [`Vault-Buffer-Shortfall-User-Comms-Runbook.md`](../../../contributors/deltaforesight/operations/Vault-Buffer-Shortfall-User-Comms-Runbook.md):
  queued claim / buffer shortfall の user communication
- [`Treasury-Safe-Retention-Runbook.md`](./Treasury-Safe-Retention-Runbook.md):
  Safe 留保資金、backstop 原資、Day-2 Treasury cutover
- [`Incident-Notification-Policy.md`](../../../contributors/deltaforesight/operations/Incident-Notification-Policy.md):
  内部通知と user-facing 告知の severity
- [`Balance-Sheet-Liquidity-Allocation-Policy.md`](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md):
  B/S bucket と contract 強制範囲
- [`../../spec/CollateralVault.md`](../../product/spec/CollateralVault.md),
  [`../../spec/dToken.md`](../../product/spec/dToken.md),
  [`../../spec/Liquity-v2-Core-Spec.md`](../../product/spec/Liquity-v2-Core-Spec.md)

## 1. Principles

1. **Core は触らない**
   Product sunset は Liquity Core の任意停止ではない。Core branch shutdown は
   TCR < SCR または oracle failure の protocol safety path であり、事業判断の
   off switch として使わない。

2. **新規成長を止め、出口を優先する**
   既存ユーザーが close / repay / redeem / SP withdraw / Vault redeem / claim を
   進められる状態を優先する。通常の sunset では `pauseRedeem` / `pauseClaim` を
   使わない。これは backing incident、exploit、誤送金拡大などの incident 時に限る。

3. **contract で止められる範囲を過大表示しない**
   `DToken.setCap(0)` と `Vault.pauseDeposit` は新規 dToken 供給を止めるが、
   既存 dToken を持つユーザーが Core に担保投入する経路を Core 無改修で完全には
   止めない。`setCap(snapshotTotalSupply)` は redemptions で supply が減ると再 mint
   headroom が生じるため、hard stop ではなく net-growth limit としてだけ扱う。
   UI / ops はこの制約を user-facing / admin-facing に明記する。

4. **補填と writeoff を分ける**
   補填できる場合は対象 Vault の Underlying を `backstopDeposit` する。回収不能が
   確定した残額だけ `writeoffStrategyPrincipal` で backing に反映する。JPYdf、
   dToken、非 Underlying reward token をそのまま backing repair と表示しない。

5. **B/S seed と protocol user funds を混ぜない**
   LP seed、SP seed、bootstrap Trove、Treasury Safe、Vault backstop は bucket を
   分けて証跡化する。LP 撤退原資を Vault buffer / user claim 原資として二重計上しない。

## 2. Contract Boundary

| 分類 | 使う contract surface | holder / owner | sunset での標準扱い |
| --- | --- | --- | --- |
| 新規 dToken 供給停止 | `DToken.setCap(0)` | dToken owner / Timelock | hard stop の標準。cap を下げても既存 supply は burn されない |
| dToken net growth 制限 | `DToken.setCap(snapshotTotalSupply)` | dToken owner / Timelock | hard stop ではない。redeem で `totalSupply` が下がると差分だけ再 mint headroom が生じるため、意図がある場合だけ使う |
| Vault deposit 停止 | `CollateralVault.pauseDeposit()` | GUARDIAN | user の新規 underlying deposit を止める |
| 新規 allocation 停止 | `CollateralVault.pauseAllocation()` | GUARDIAN | Strategy への新規 outbound と treasury sweep を止める |
| buffer 優先化 | `setBufferConfig(10000, floor)` | GOV / Timelock | 新規 allocation より user exit liquidity を優先 |
| Strategy weight 停止 | `updateStrategy(strategy, 0, cap, false)` | GOV / Timelock | 通常の計画縮退で使用 |
| Strategy 即時無害化 | `emergencyDisableStrategy(strategy)` | GUARDIAN | incident / external venue risk 時に使用 |
| 回収 | `sendToVault`, protocol-specific emergency withdraw | ALLOCATOR / Strategy owner | 返せる分だけ Vault へ戻す。illiquidity を即 loss と見なさない |
| 補填 | `backstopDeposit(amount)` | funding owner / anyone | 対象 Vault の Underlying のみ。dToken は mint しない |
| 損失確定 | `writeoffStrategyPrincipal(strategy, amount, minBackingRatioAfter)` | WRITEOFF | 回収不能額が確定した後だけ |
| user exit 停止 | `pauseRedeem()`, `pauseClaim()` | GUARDIAN | 通常 sunset では使わない。incident 時のみ |
| Day-2 bridge route 停止 | adapter route pause、runtime cap 0、必要なら `removeBridgeMinter` | bridge adapter admin / bridgeAdmin | bridge minter が active な場合だけ。remote canonical supply reconciliation を完了するまで route を再開しない |

### 2.1 Explicit Non-Goals

- Governance が任意に全 Core branch を shutdown する仕組みを追加しない。
- Core の `openTrove` / debt increase を新規 governance flag で止める変更は入れない。
- User の JPYdf / dToken / Trove debt を運営が一方的に burn / settle しない。
- JPYdf を protocol reward /補填目的で discretionary mint しない。
- Fixed ETA、全額即時 exit、redemption 回避、特定 borrower protection を約束しない。

### 2.2 Bridge-Active Caveat

Day-1 launch は bridge minter 0 件を前提にするため、通常の product unwind は
Ethereum mainnet の Core / dToken / Vault / Strategy / LP / SP を対象にすれば足りる。
Day-2 以降に bridge minter を 1 件でも登録した後は、product-wide sunset の前に
[`Bridge-Minter-Activation-Gate.md`](./Bridge-Minter-Activation-Gate.md) の incident
path を使い、次を evidence に残す。

1. 対象 route / chain の pause 状態、runtime cap、hourly / daily rate limit を確認する。
2. Public route / frontend route flag / ops route flag を閉じる。
3. Adapter 側で route pause と runtime cap 0 を実行する。
4. `globalCanonicalJpydfSupply`、chain 別 `remoteCanonicalJpydfSupply`、in-flight /
   failed / expired message を reconciliation する。
5. Adapter drift、remote chain incident、accounting 不一致がある場合は、route を
   paused / cap 0 のまま `removeBridgeMinter` または adapter-specific revoke を検討する。

`JpydfToken` は token-level の route pause / per-chain cap / remote accounting を持たない。
bridge active 後の sunset を token-local action だけで完了したように扱ってはならない。

## 3. Trigger Classification

| Trigger | 代表例 | 最初の判断 owner | 標準モード |
| --- | --- | --- | --- |
| Product soft wind-down | demand 不足、経済性悪化、public launch 継続判断の撤回 | Product / governance | Soft wind-down |
| Branch-specific wind-down | particular branch の流動性・oracle・strategy economics が悪化 | Risk / governance | Branch soft wind-down |
| Strategy / backing incident | external protocol loss、withdraw halt、valuation failure | Ops / guardian / writeoff | Incident recovery |
| B/S seed exit | bootstrap Trove / LP / SP seed を撤退する会計判断 | Finance / ops | B/S bootstrap exit |
| Insolvent / loss case | 補填不能な backing shortfall、confirmed strategy loss | Governance / writeoff | Loss handling |

## 4. Soft Wind-Down Flow

Soft wind-down は「新規成長を止め、既存 exit を優先する」モードである。

1. **Decision freeze**
   対象 branch、対象 frontend surface、cap lowering、LP / SP seed の扱い、user
   communication owner を decision log に記録する。

2. **Vault deposit / allocation 即時停止**
   GUARDIAN が `pauseDeposit()` と `pauseAllocation()` を実行する。redeem / claim は
   原則開けたままにする。`DToken.setCap` は Timelock delay を持つため、先に
   Guardian の即時 pause で deposit window を閉じる。

3. **新規供給 hard stop**
   active dToken ごとに `setCap(0)` を queue / execute する。既存 supply は burn
   されない。`setCap(snapshotTotalSupply)` を使う場合は、redeem で `totalSupply` が
   下がると再 mint headroom が生じるため、hard stop ではなく net-growth limit として
   decision log に明記する。

4. **Strategy exposure 低下**
   通常縮退なら Timelock で `updateStrategy(strategy, 0, cap, false)` を使う。
   incident なら `emergencyDisableStrategy(strategy)` と Strategy-specific recovery を使う。

5. **buffer 優先化**
   必要に応じて `setBufferConfig(10000, floor)` を使い、Vault が回収資産を user exit
   liquidity として保持しやすい設定に寄せる。floor は pending claims / expected
   redemptions / token decimals を踏まえて決める。

6. **frontend / ops 切替**
   User app は Borrow / Earn growth messaging を弱め、Close / Repay / Redeem JPYdf /
   Redeem collateral / SP withdraw を主導線にする。Admin console は active branch ごとの
   cap、paused flags、buffer、pending withdrawals、strategy exposure、LP / SP seed state を
   同じ画面で見せる。

7. **watch window**
   T+24h / T+72h / T+7d で branch debt、SP deposits、outside debt、redemption volume、
   pending withdrawals、bufferBalance、backingRatio、LP depth を記録する。

No-Go:

- `pauseRedeem` / `pauseClaim` を通常 sunset の標準手順にしている。
- dToken cap lowering を既存 Core borrow の完全停止として説明している。
- Strategy の一時 illiquidity を confirmed loss として即 writeoff している。
- Public comms が fixed ETA / guaranteed full exit を示している。

## 5. B/S Bootstrap Exit

Bootstrap Trove、SP seed、JPYdf/USDC LP seed は contract safety ではなく B/S
operation である。撤退時は user exit liquidity と liquidation coverage を同時に見て、
一括撤退で market depth を消さない。

1. **bucket reconciliation**
   LP seed、SP seed、bootstrap Trove collateral/debt、Treasury Safe retained funds、
   manual backstop funds を token / owner / branch ごとに分ける。

2. **LP exit planning**
   LP を抜く前に JPYdf/USDC depth、redemption pressure、SP coverage、borrower close
   demand を確認する。LP 撤退により JPYdf exit route が消える場合は user-facing
   sunset banner と代替 redemption route を先に用意する。

3. **SP seed handling**
   SP seed を引き出す場合、対象 branch の debt、liquidation candidate、outside debt、
   third-party SP deposits、manual JIT/top-up owner を確認する。SP seed を抜いた後の
   redistribution risk を decision log に残す。

4. **Bootstrap Trove repay / close**
   bootstrap Trove の JPYdf repayment source、collateral release destination、rate
   adjustment owner、redemption-in-front を記録し、LP / SP seed 解除と二重に JPYdf を
   使わない。

5. **post-exit monitoring**
   LP / SP / Trove exit 後、最低 72h は JPYdf price、redemption fee/base rate、
   branch TCR/SCR、SP coverage、liquidation candidate を監視する。

## 6. Strategy Incident / Loss Handling

Strategy / backing incident は soft wind-down より強いモードである。詳細手順は
[`Strategy-Incident-Liquidation-Safety-Runbook.md`](./Strategy-Incident-Liquidation-Safety-Runbook.md)
を正とし、本 runbook では product-level sequencing だけを定める。

1. GUARDIAN が対象 Vault / Strategy の user flow と allocation を止める。
2. 運営 liquidation bot が対象 branch を skip していることを確認する。
3. Strategy-specific recovery で回収できる分を Vault へ戻す。
4. 補填できる場合は対象 Underlying を `backstopDeposit` する。
5. 回収不能が確定した residual だけを writeoff する。
6. `backingRatio`、PriceFeed、MCR 近傍 Trove、pending claims への影響を記録する。
7. full backing 復帰後にだけ、GOV が必要な user flow を段階的に unpause する。

No-Go:

- 回収・補填前に大きく writeoff して liquidation window を作っている。
- JPYdf、dToken、reward token をそのまま backing repair として分類している。
- live valuation に既に反映された loss と manual writeoff が二重計上になっている。
- Bot が Vault pause / backingRatio guard を無視して liquidation を送る。

## 7. Product Sunset User Surface

Product sunset 時の user app / public status / docs は、操作可能な出口を最短で示す。

| User state | 主導線 | 表示方針 |
| --- | --- | --- |
| Borrower with active Trove | repay / close / manage interest | 新規 borrow 推奨を消し、close / repay の必要 JPYdf と redemption risk を表示 |
| JPYdf holder | redeem JPYdf / DEX exit | redemption fee、route、受け取る dToken / collateral redeem 導線を表示 |
| dToken holder | redeem collateral | buffer 不足時は queued claim と `claimableAt`、固定 ETA なしを表示 |
| SP depositor | withdrawFromSP / claim collateral gains | branch SP coverage、remaining liquidation risk、dToken gain の redeem 導線を表示 |
| LP / campaign participant | withdraw LP / end campaign | campaign end、unclaimed rewards、LP owner / manager action を分ける |

Public banner は「何が止まっているか」よりも「何がまだできるか」を先に示す。
例: "New deposits and new allocations are paused. Existing users can repay, close,
withdraw from SP, redeem JPYdf, and redeem collateral unless a branch-specific
incident banner says otherwise."

## 8. Evidence Template

```text
Decision:
Scope: protocol-wide / branch-specific / strategy-specific
Reason:
Decision owner:
Governance proposal / Safe tx:
Public communication owner:

Affected branches:
Affected dTokens:
Affected Vaults:
Affected Strategies:

Cap action:
Cap before:
TotalSupply before:
Cap after:
TotalSupply after:
Deposit paused:
Vault pause action:
Strategy action:
Buffer config action:
Backstop / writeoff action:
Frontend / admin mode:
Bridge route state:
Remote canonical supply reconciliation:

Current branch debt:
Current SP deposits:
Current outside debt:
Current JPYdf/USDC depth:
Current redemption fee / base rate:
Current bufferBalance:
Current pendingWithdrawals:
Current backingRatio:

B/S LP seed state:
B/S SP seed state:
Bootstrap Trove state:
Repayment source:
Backstop source:

Allowed user actions:
Paused user actions:
Known limitations:

T+24h review:
T+72h review:
T+7d review:
```

## 9. Follow-Up Surface

- **Admin console**: branch wind-down checklist、cap/pause/buffer/strategy exposure、
  LP/SP/bootstrap Trove state、Safe calldata evidence を 1 画面で見せる。
- **User app**: sunset mode を追加し、Borrow / Earn growth CTA より Close / Repay /
  Redeem / SP withdraw / Vault redeem を優先する。
- **Ops dashboard**: `product_sunset`, `branch_wind_down`, `strategy_incident`,
  `loss_handling` の alert key を `Incident-Notification-Policy` と揃える。
- **Docs**: launch evidence の `Unwind plan` は本 runbook を参照し、branch ごとの
  repayment source / LP exit / SP seed exit を記録する。
