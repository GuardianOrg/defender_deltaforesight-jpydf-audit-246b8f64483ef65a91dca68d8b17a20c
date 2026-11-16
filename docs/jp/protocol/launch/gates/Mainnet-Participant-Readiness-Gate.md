# Mainnet Participant Readiness Gate

> **位置づけ**: 借り手、SP depositor、清算者が JPYdf を使う理由とリスクを判断できる状態でなければ public launch しない。launch 操作そのものは [`Mainnet-Launch-Operation-Gate.md`](./Mainnet-Launch-Operation-Gate.md)、frontend delivery は [`Frontend-Production-Delivery-Gate.md`](../../../contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md)、UX 表示品質は [`Frontend-UX-Readiness-Gate.md`](../../../contributors/deltaforesight/delivery-plans/Frontend-UX-Readiness-Gate.md)、liquidation bot の実装境界は [`bots/liquidator/README.md`](../../../../../bots/liquidator/README.md) を正とする。
>
> 本書は参加者別 readiness の広い checklist を Day-1 / Day-2 / 未実装として分解する runbook であり、利回り・安全性を保証する文言を作るための資料ではない。

---

## 0. Day-1 方針

Day-1 の参加者別 positioning は次の通り。

| 参加者 | Day-1 の提供価値 | Day-1 の明示制約 |
| --- | --- | --- |
| 借り手 | JPY 建てで借りられる、user-set borrow rate、dUSDC / dwstETH を使った 1Tx borrow、JPYdf/USDC Uniswap v4 exit liquidity | JPYdf の市場流動性は launch seed 依存。低 borrow rate ほど redemption を受けやすい。dToken backing / buffer / strategy risk は担保価値に反映される（dwstETH は wstETH の native staking 増価が担保価値に残る） |
| SP depositor | Core Stability Pool の借入金利由来 yield 75% と清算担保 claim、branch ごとの coverage / outside debt の透明性 | Day-1 は SP 追加報酬・Treasury 分配を claimable reward として出さない。SP は dToken / Strategy 毀損の repair 原資ではない |
| 清算者 | permissionless liquidation と operator maintenance bot の dry-run / live evidence | 外部 profit seeker が自然に参加できる水準の disposal route、JIT inventory、private relay、profit model は Day-2。Day-1 は operator maintenance を前提にする |
| 運営 | branch health、SP coverage、oracle、backing、liquidity、liquidator execution を同じ evidence package で確認できる | ops の値が stale / snapshot / local fixture の場合は public launch gate を通さない |

Day-1 の直接 JPYdf DEX liquidity は JPYdf/USDC Uniswap v4 のみ。Curve、Balancer、Uniswap v3、USDT / USDS / WETH / XAUT direct JPYdf pool を launch 前提にしない。

---

## 1. Borrower Readiness

借り手が「いくらで借りるべきか」「どこで損をするか」「JPYdf をどう出るか」を判断できる状態を gate する。

### 1.1 必須表示

| 項目 | 必須内容 | Source of truth |
| --- | --- | --- |
| Effective APR / borrow rate | user-set rate、operator / policy anchor、borrowRate policy の根拠、rate review cadence。frontend fee や別途 cost を導入する場合は合算表示 | RPC / subgraph / public stats `borrowRatePolicies` / launch evidence |
| Redemption risk | debt in front、branch debt に対する ahead ratio、rate distribution、redemption fee / base rate、lowest-rate position への説明 | SortedTroves / subgraph / public stats / direct RPC |
| Liquidation risk | current ICR、liquidation price、MCR、TCR、CCR / SCR proximity、branch shutdown / safety mode | TroveManager / PriceFeedProxy / branch params |
| dToken risk | backing ratio、Vault buffer、withdraw delay、strategy exposure、pending withdraw、paused flags | CollateralVault / Strategy reads / public stats |
| 1Tx route | Underlying -> dToken -> Trove の Zapper route、cap、allowance、失敗時の fallback 表示 | generated bindings / manifest / Zapper config |
| JPYdf exit | JPYdf/USDC v4 pool、sample slippage、pool freshness、LP seed owner / allowance cleanup evidence | Uniswap v4 reads / launch operation evidence |

### 1.2 No-Go

- Borrow 画面で effective APR、redemption risk、liquidation price / ICR、dToken backing / buffer のいずれかが見えない。
- `mintCap = 0` または inert branch が borrowable branch として表示される。
- Borrow 画面が raw Underlying spot price だけを見せ、dToken backing ratio を担保価値に反映していない。
- JPYdf/USDC exit liquidity の route / slippage evidence がないのに、JPYdf を容易に exit できるように表現している。
- Curve、Balancer、Uniswap v3、または Day-1 方針外 direct pool を route 前提にしている。
- stats / subgraph が stale の時に、fresh な current value と同じ見た目で表示する。

---

## 2. SP Depositor Readiness

SP depositor が「どの branch に、どの補償範囲と流動性前提で預けるか」を判断できる状態を gate する。

### 2.1 必須表示

| 項目 | 必須内容 | Source of truth |
| --- | --- | --- |
| Core SP yield | 借入金利由来 JPYdf yield、`SP_YIELD_SPLIT`、実績期間または policy anchor、保証ではない旨 | StabilityPool / public stats / launch evidence |
| Liquidation reward | claimable collateral、清算履歴、未 claim reward、dToken claim と Underlying redeem の違い | StabilityPool / subgraph / Vault |
| Coverage | branch debt、SP deposits、SP coverage bps、outside debt、covered / thin-SP state | ActivePool / StabilityPool / public stats |
| Branch risk | MCR / TCR / CCR / SCR、oracle freshness、shutdown risk、dToken backing ratio、Vault buffer、strategy exposure | RPC / public stats / ops exporter |
| Exit liquidity | JPYdf/USDC v4 pool price / depth / sample slippage、redemption fee / base rate | Uniswap v4 / CollateralRegistry / RedemptionHelper |
| Additional rewards | Day-1 は「未実装 / 未確定」と明示。SPAdditionalRewardDistributor 導入後だけ claimable として表示 | Treasury spec / future SPAdditionalRewardDistributor evidence |

### 2.2 No-Go

- SP 追加報酬、Treasury 分配、campaign reward を claimable / APR に混ぜているが、contract / distribution evidence がない。
- SP を dToken / Strategy 毀損の補填原資として説明している。
- branch debt / SP deposits / outside debt / coverage bps のいずれかが表示できない。
- SP coverage が薄い branch で、redistribution / JIT / operator top-up の判断 owner を launch evidence に残していない。
- JPYdf exit liquidity と redemption route を SP depositor が確認できない。
- claim / compound UX が未実装の報酬種別まで操作できるように見せている。

---

## 3. Liquidator Readiness

Day-1 の清算は operator maintenance を前提にする。外部 profit seeker を集めるには、担保処分と inventory を含む利益推定まで必要だが、これは Day-2 hardening として扱う。profit-seeking 解禁条件の正本は
[`Liquidation-Management-Policy.md`](../../operations/policies/Liquidation-Management-Policy.md#day-2-profit-seeking-hardening-gate)
の hardening gate とする。

### 3.1 Day-1 必須

| 項目 | 必須内容 | Source of truth |
| --- | --- | --- |
| Bot mode | `dry-run` / `protocol-maintenance` のどちらで launch するか。Day-1 default は `protocol-maintenance`。`profit-seeking` は collateral disposal / inventory-aware profit model 実装まで Day-2 | bot config / launch evidence |
| Candidate scan | top candidate、min ICR、candidate count、branch priority、zombie append path、scanned branches | `bots/liquidator` JSON evidence |
| SP offset | branch SP deposit、SP offset capacity、SP-covered candidate count、minimum SP offset coverage bps | StabilityPool / bot evidence |
| Gas / loss caps | max gas cost、max loss per tx、gas stress multiplier、max submissions per cycle、submission cooldown blocks、high-gas escalation owner | bot config / launch evidence |
| Execution evidence | config hash、generatedAtBlock freshness、planned batch、stressed gas cost、decision / skipReason、receipt policy | bot JSON / launch checker |
| Manual JIT / top-up | JPYdf funding source、SP deposit account、decision owner、thin-SP / redistribution decision log | launch operation evidence |
| Collateral disposal | 清算で受けた dToken / Underlying の評価・退避・処分 owner。bot に自動処分がないこと | launch operation evidence |

### 3.2 Day-2 / profit seeker 条件

外部清算者に「利益目的で狙える」状態として見せるには、少なくとも次を別 PR / 別 gate で満たす。

- [`Liquidation-Management-Policy.md`](../../operations/policies/Liquidation-Management-Policy.md#day-2-profit-seeking-hardening-gate)
  の profit model / evidence schema / P0->P1->P2 有効化条件。
- 担保受領後の disposal route、slippage、inventory cost を含む profit model。
- gas / priority fee / base fee 予測。
- private relay / MEV protection。
- RPC quorum / fallback RPC / read timeout。
- event subscription または indexer cache による高速 candidate discovery。
- 複数 zombie Trove 検出方針。
- JIT 用 JPYdf inventory 管理、または permissionless JIT executor。
- branch priority を `ICR deficit`、`SP coverage`、`collateral liquidity`、`branch TCR`、`gas/tip` で決める policy。
- Prometheus metrics / alerts / receipt tracking / failed tx classification。

### 3.3 No-Go

- 現行 bot を外部 profit seeker ready と表示している。
- `profit-seeking` mode を Day-1 launch config で有効にしている。
- dry-run evidence が current manifest 由来の config と一致しない。
- dry-run evidence が stale block、または active branch を scan していない。
- SP offset capacity、gas / loss cap、stressed gas cost、skipReason のいずれかが evidence にない。
- JIT top-up / collateral disposal が bot に自動実装済みだと誤認させる。
- failed tx / on-chain revert / receipt timeout の classification と escalation owner がない。

---

## 4. Product Health Transparency

borrower / SP depositor / liquidator の判断材料を別々の画面に閉じず、ops と public transparency で同じ source から確認できるようにする。

| 領域 | 必須指標 |
| --- | --- |
| Branch health | TCR、SCR、CCR、MCR、shutdownTime、branch debt、SP deposits、outside debt、coverage bps |
| Oracle | current price、updatedAt、staleness margin、lastGoodPrice fallback、source proposal、JPY soft-freeze |
| dToken / Strategy | backing ratio、Vault buffer、pending withdraw、strategy exposure、writeoff、backstop reserve、paused flags |
| Liquidity | JPYdf/USDC v4 pool price / depth、sample sell / buy slippage、LP owner、allowance cleanup |
| Redemption | redemption fee、base rate、routing sample、lowest-rate distribution、urgent redemption state |
| Liquidation | top candidate、min ICR、candidate count、SP offset capacity、bot block lag、receipt status |
| Incidents | pause / cap freeze owner、liquidator stop / restart condition、public comms owner、status page / app banner state |

No-Go:

- User app と ops dashboard が別の stale source / local fixture / legacy snapshot を参照している。
- public stats に source block / generatedAt / schema version がない。
- branch health、SP coverage、oracle freshness、backing ratio、liquidity depth、liquidator scan のいずれかが launch window に読めない。
- incident 時に user app banner / status page / liquidation bot stop-restart runbook が同期していない。

---

## 5. Evidence Package

launch 前に、次を `mainnet-launch-participant-readiness` evidence package として残す。

| Evidence | 内容 |
| --- | --- |
| Borrower screenshots / JSON | Borrow 画面の effective APR、redemption risk、liquidation price、dToken backing / buffer、Zapper route、JPYdf exit liquidity 表示 |
| Earn screenshots / JSON | SP APY source、SP coverage、outside debt、branch risk、exit liquidity、SP 追加報酬が未実装である表示 |
| Ops dashboard evidence | branch health、oracle、Vault / Strategy、liquidity、redemption、liquidation、incident owner の表示 |
| Public stats JSON | schema version、source block、generatedAt、healthStatus、borrowRatePolicies、branch coverage / backing fields |
| Liquidator evidence | bot config hash、dry-run JSON、gas / loss caps、max submissions per cycle、submission cooldown blocks、SP offset capacity、planned batch、receipt policy |
| Route evidence | JPYdf/USDC v4 pool key、sample slippage、LP seed、allowance cleanup |
| Exception log | No-Go を例外承認で通す場合の risk owner、launch owner、期限、解消 issue |

Evidence には private key、raw RPC URL、未公開 Safe nonce、API key、個人 account の秘密情報を含めない。provider は label と redacted URL までにする。

---

## 6. Day-2 Backlog Boundary

次は Day-1 launch blocker ではないが、残 scope として issue / PR に分ける。

| 領域 | Day-2 候補 |
| --- | --- |
| SP incentive | Treasury / SPAdditionalRewardDistributor、campaign budget、Merkl 等との併用、auto-compound / claim UX |
| Borrower UX | APR 実績の時系列集計、rate distribution の詳細 visual、delegation marketplace、advanced redemption simulator |
| Liquidation | profit-seeking model、private relay、RPC quorum、JIT inventory、collateral disposal router、Prometheus / alerts |
| Public transparency | external-facing branch risk dashboard、historical APY / liquidation PnL、status page integration |
| Liquidity | JPYdf/USDC v4 depth ramp、additional route は別 audited route policy で判断。Curve / Balancer / direct USDT・USDS・WETH・XAUT pool を既定にしない |

---

## 7. Close / Continue Criteria

参加者別 readiness は広いテーマなので、次の状態になれば「Day-1 readiness scope は解決」として扱える。

1. 本 runbook が `develop` に入り、Frontend spec / data-source ledger / launch operation gate から参照されている。
2. Borrow / Earn / Ops / liquidator evidence package が launch 前に採取できる。
3. 未実装項目が UI と docs で利用可能な機能として扱われていない。
4. Day-2 backlog が個別 issue に分割され、Day-1 launch blocker と混同されていない。

Day-2 backlog が未完了であること自体は Day-1 close blocker ではない。ただし、UI / runbook / marketing copy が未実装項目を実装済みのように見せる場合は No-Go とする。
