# JPY DeFi Day-1 Liquidity / Route Policy

> **位置づけ**: Day-1 の JPYdf DEX 流動性、Zapper の swap route、
> frontend gate、liquidity script の境界を固定する設計メモ。担保 branch の
> support は [`Parameters.md`](../../../Parameters.md)、Zapper の contract 要件は
> [`Zapper.md`](../spec/Zapper.md)、frontend gate は
> [`Frontend.md`](../spec/Frontend.md)、deploy mode・wiring shape・Manifest schemaは
> [`Deployment-Configuration-Spec.md`](../../../engineering/guides/Deployment-Configuration-Spec.md) を参照する。特定deployのroute値と実行結果は生成ManifestとEvidenceを正本とする。
> B/S 資金を LP seed / backstop / Vault buffer / Treasury 留保へ分類する方針は
> [`Balance-Sheet-Liquidity-Allocation-Policy.md`](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md)
> を参照する。
> Merkl campaign の採否・budget・KPI・停止条件は
> [`Merkl-Campaign-KPI-Policy.md`](../../roadmap/policies/Merkl-Campaign-KPI-Policy.md) を参照する。
> 清算 backstop / JIT の用語と責務境界は
> [`Liquidation-Backstop-And-JIT-Policy.md`](../../operations/policies/Liquidation-Backstop-And-JIT-Policy.md) を参照する。

---

## 1. Decision

Day-1 の JPYdf 流動性は **JPYdf/USDC の 1 ペアだけ**に限定する。

- Venue は **Uniswap v4** を標準とする。
- Pool fee は **static 0.05%（`fee = 500`）/ `tickSpacing = 10` / no hook** を Day-1 標準とする。
- liquidity broadcast は JPYdf token deploy / 発行後にだけ行う。pool key の token ordering は
  JPYdf / USDC の実アドレスから Uniswap v4 の規則で決まり、evidence に固定する。
- Curve 系 route / adapter / liquidity script は Day-1 scope 外とし、採用しない。
- Balancer は Day-1 scope 外であり、将来 route 前提にも含めない。
- Uniswap v4 route は Universal Router / Permit2 / pool key / hook policy を route config
  として freeze し、fork/integration evidence が揃うまで production Zapper には配線しない。
- `UniV4Exchange` は Day-1 audit scope に含める。これは JPYdf/USDC v4 final leg
  の adapter 監査を先に完了させるためであり、swap-backed close / collateral-funded repay /
  Multiply を Day-1 ABI に戻すことを意味しない。
- Uniswap v3 route / adapter は Day-1 scope 外であり、現行 contract tree には残さない。
- USDT / sUSDS / WETH / XAUT / dToken の JPYdf 直接 pool は作らない。
- inert branch の予約と、borrowable collateral または JPYdf liquidity pair としての activation は
  別の承認対象とする。
- JPYdf/JPYC poolは、条件付き採用済みのdormant routeとして§7で管理する。§7の発動条件が成立する
  まで、pool作成・fund・bot / LP運用を開始しない。

---

## 2. Scope Boundary

| 対象 | Day-1 方針 |
| --- | --- |
| Collateral support | 8 branch 全てを deploy する（`NUM_DF_ACTIVE_BRANCHES = 2`）。active は dwstETH / dUSDC のみで、branch 2–7 は Underlying 未 binding・cap 0 の inert branch |
| JPYdf liquidity | JPYdf/USDC の Uniswap v4 pool だけ。JPYdf deploy / 発行後に liquidity を入れる |
| `UniV4Exchange` / `IExchange` adapter | Day-1 audit scope に含める。route config / fork evidence / manifest gate が揃うまで user-facing Zapper には配線しない |
| PIL / liquidity incentives | JPYdf/USDC pool への配分を前提に設計する。PIL recipient は別 runbook で freeze する |
| JIT / liquidation backstop | JPYdf/USDC liquidity は JIT 用 JPYdf 調達を助けるが、SP top-up や liquidation 実行を自動化しない。Day-1 の JIT は運用 planning capacity であり contract guarantee ではない |
| Zapper open / add / withdraw / close-with-JPYdf | JPYdf swap を使わないため JPYdf/USDC liquidity の有無に依存しない |
| Collateral-funded repay / flash-close / Multiply | Day-1 contract ABI に存在しない。`UniV4Exchange` は Day-1 audit scope に含めるが、将来提供する場合も Balancer / 削除済み Flash Loan callback に依存せず、route config / fork evidence 付きの新しい audited entrypoint として追加 |
| Non-USDC collateral reverse route | 追加 JPYdf pool を作らず、必要な場合だけ Underlying -> USDC -> JPYdf の adapter と evidence を別途追加 |
| JPYdf/JPYC dormant route | Day-1 では作らない。§7 の発動条件成立まで監視のみ |

---

## 2.1 Implementation Absorption / Launch Gates

Day-1の非公開branch 2–7はUnderlying未binding、placeholder PriceFeed、cap / allocation 0、Strategy / Zapperなし、frontend非公開の多重条件で閉じる。

- **Contract layer**: `DToken.cap = 0` の branch は `CollateralVault.deposit()` 経由の `DToken.mint()` が cap check で revert するため、新規 dToken mint はできない。launch evidence では inert branch の `cap == 0` と `totalSupply == 0` を確認する。
- **Vault allocation**: `allocateMaxMove = 0` の branch は `allocate()` で excess 移動量が 0 に丸められるため、Strategy への outbound allocation は発生しない。Strategy を deploy しない場合は `DF_STRATEGY_KIND_i=none` / weight 0 / cap 0 を evidence 化する。
- **Handover env**: branch 2–7のcap / allocation / Strategyを0でfreezeし、branch 2–7の全PriceFeedをplaceholder・Zapperなしとする。
- **Frontend gate**: user app は inert branch / cap 0 branch を borrowable collateral として送信対象にしない。production launch config と on-chain state の双方で dwstETH / dUSDC だけを borrowable と判定する。

---

## 3. Zapper / Route Rules

1. `CollateralYieldZapper` の production open / add / withdraw / close-with-JPYdf は
   Underlying と dToken の変換だけで完結し、DEX route を必要としない。
2. flash-close / collateral-funded repay / Multiply は Day-1 ABI に存在しないため送信不可にする。`UniV4Exchange`
   自体は Day-1 audit scope に含めるが、将来これらの user-facing flow を提供する場合も Balancer /
   削除済み Flash Loan callback に依存せず、新しい audited entrypoint として追加する。
3. Day-1 に production-reviewed として扱える JPYdf swap leg は JPYdf/USDC Uniswap v4
   のみ。USDT / sUSDS / WETH / XAUT から JPYdf へ直接 swap する route は作らない。
4. inert branch の入口 UX を USDC に寄せる場合でも、JPYdf leg は最終的に JPYdf/USDC
   に集約する。asset-specific pre-leg / reverse adapter は activation audit の対象にする。
5. Uniswap v4 route は、hook なし pool を既定とする。hook 付き route を許す場合は、
   hook allowlist、pool key、Universal Router / Permit2 address、allowance cleanup、
   fork-run evidence を route config に固定してから有効化する。
6. `UniV4Exchange` の JPYdf -> collateral 側は exact-output adapter として扱う。
   入力 JPYdf は最大支払額、指定 collToken 量が実際の output target であり、余った
   JPYdf は adapter から caller に返す。collateral -> JPYdf 側は exact-input adapter
   として扱い、指定 collToken 全量を入力して JPYdf の最低受取量を検査する。

---

## 4. Frontend Gates

- Day-1 frontend は Multiply route / open-update leverage tx-flow / `NEXT_PUBLIC_MULTIPLY_SCREEN`
  env flag を持たない。将来提供する場合は旧 flag 復活ではなく、新しい audited entrypoint
  と route config / fork evidence を伴う spec 追加として扱う。
- dToken branch の collateral-funded repay / flash-close / Multiply は Day-1 ABI に存在しない。JPYdf/USDC
  final leg と必要な asset-specific pre-leg が manifest / config / UI に揃った後でも、送信には Balancer / 削除済み Flash Loan callback に依存しない新しい audited entrypoint が必要。
- Borrow / add collateral / repay with JPYdf / close with held JPYdf は、swap route なしで
  検証できる direct or CYZ flow として扱う。
- UI copy は「branch deploy」「active collateral」「DEX liquidity support」を混同しない。Day-1 に担保として利用できるのは dwstETH / dUSDC、JPYdf DEX 流動性は USDC だけである。

---

## 5. Liquidity Script Gates

Production liquidity script / runbook は以下を満たさない限り broadcast しない。

- token pair が JPYdf/USDC である。
- venue が Uniswap v4 である。
- JPYdf token deploy / 発行が完了し、liquidity に使う JPYdf amount と USDC amount が
  funding source / accounting owner とともに freeze 済みである。
- liquidity に使う B/S 資金は Vault buffer / backstop / Treasury 留保と会計 bucket が分離されている。
- USDC / JPYdf token address、fee、tick spacing、hook policy、pool key、position owner、
  initial amounts を evidence に残す。
- script が USDT / USDS / WETH / XAUT / Curve / Balancer pool を作らない。
- fork-run で pool address、token ordering、position owner、minted liquidity を確認する。

legacy / rehearsal script が WETH / wstETH / rETH 等の pool を扱う場合、それは
Day-1 JPYdf liquidity script ではないため現行 contract tree には残さない。production
手順からは本ポリシーに合う script だけを参照する。

本節の gates（token pair = JPYdf/USDC）は Day-1 script に適用する。JPYdf/JPYC pool 用の
script は、§7 の発動条件が成立した場合にのみ、本節と同型の evidence（pool key、position
owner、initial amounts、fork-run）を伴って broadcast する。

---

## 6. Audit Evidence

```text
Liquidity policy commit:
Pool venue:
Pool pair:
USDC address:
JPYdf address:
Fee:
Tick spacing:
Hook policy:
Pool key:
UniV4Exchange address:
UniV4Exchange bytecode hash:
Universal Router address:
Permit2 address:
Position owner:
Initial USDC raw amount:
Initial USDC JPY notional:
Initial JPYdf amount:
Fork block:
Pool address:
Broadcast tx:

Negative checks:
- No Curve pool/script used:
- No Balancer pool/script/adapter used:
- No USDT/USDS/WETH/XAUT JPYdf direct pool:
- Multiply/collateral-funded repay entrypoints are absent from Day-1 ABI:
- Zapper exchange route for non-reviewed branches is absent from Day-1 ABI:
- No JPYdf/JPYC pool created or funded before §7 activation conditions:
```

---

## 7. JPYdf/JPYC Dormant Route

本 route の導出経緯は
[2026-07-16-JPYC-Peg-Anchor-Proposal](../../../engineering/historical-reviews/2026-07-16-JPYC-Peg-Anchor-Proposal.md)
に point-in-time evidence として保存する。現行の判断条件・運用境界は本節を正本とし、
JPYdf/JPYC を円建て価格基準点 route として dormant 状態のまま登録する。

- 位置づけ: JPYC の担保棄却は維持する。円建て 1:1 価格基準点および会社 B/S 介入手段に限定
  し、pool 在庫の損失想定はシード総額を上限とする。LP 採用実績を担保採用 evidence に流用しない。
- venue: Uniswap v4。fee / tickSpacing / pool key 等の route config は発動時に freeze し、
  §6 と同型の evidence を残す。

発動には次の3条件をすべて必要とする。1つでも未達なら監視のみを継続し、pool 作成・fund・
bot / LP 運用を開始しない。

1. fair price 比 −0.5% 以下の median が 72h 継続、または Merkl-KPI 下方バンド逸脱が成立している。
2. [JPYC-LP-Inventory-Recycling-Activation-Gate](../../../contributors/deltaforesight/operations/JPYC-LP-Inventory-Recycling-Activation-Gate.md)
   が PASS かつ current である。
3. 再配分額、損失上限、owner を会社 B/S 決裁で承認している。

- 資金: 発動時は JPYdf/USDC pool からの再配分プリセット（¥2,000万相当）。Day-1 の現金配分
  は変えない。B/S 分類は
  [Balance-Sheet-Liquidity-Allocation-Policy](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md)
  §2 に従う。
