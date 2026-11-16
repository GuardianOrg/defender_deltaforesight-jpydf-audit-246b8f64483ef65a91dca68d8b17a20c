# Merkl campaign / launch KPI policy

## 0. 位置づけ

本書は、Merkl を使う外部 liquidity campaign の候補、採否、予算分類、launch KPI、停止条件を定める設計メモである。

`PILAllocator.md` / `UniV4MerklInitiative` は **Merkl campaign を作るコントラクト要件**を規定する。本書はその上位で、**どの campaign を、どの原資で、何を達成するために有効化するか**を扱う。

本書が規定しないもの:

- Uniswap v4 pool / route の contract 仕様: [`Liquidity-Route-Policy.md`](../../product/policies/Liquidity-Route-Policy.md)
- PILAllocator / UniV4MerklInitiative の contract 要件: [`../../spec/PILAllocator.md`](../../product/spec/PILAllocator.md)
- 会社 B/S による LP / SP seed 採用額: [`Day1-Self-BS-Launch-Commitment.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Launch-Commitment.md)
- 担保運用益の Day-1 Safe 留保、Day-2 Treasury / SP 追加報酬: [`Protocol-Revenue-Allocation-Policy.md`](./Protocol-Revenue-Allocation-Policy.md)
- 確定パラメータ値: [`../../Parameters.md`](../../../Parameters.md)

## 1. 基本方針

Day-1 / Phase-A の Merkl campaign は **JPYdf/USDC Uniswap v4 LP incentive だけ**を候補にする。これは JPYdf の初期 exit liquidity、価格発見、peg 周辺 depth を作るための campaign であり、SP 追加報酬や担保運用益の分配ではない。

USDT pool、dToken LP、外部 lending market は Day-1 では採用しない。明確な利用需要、partner、route / oracle / liquidation / accounting gate がそろった場合だけ Day-2 以降の候補にする。

資金 bucket は混ぜない。少なくとも次を別会計で扱う。

| Bucket | 用途 | 本書での扱い |
| --- | --- | --- |
| PIL | 借入金利 25% 由来の流動性 incentive | JPYdf/USDC Phase-A の主候補 |
| Merkl campaign budget | PIL 以外に明示承認された短期 incentive | 個別承認がある場合のみ |
| B/S LP seed | 会社自己資金による JPYdf/USDC 初期 LP | campaign budget ではない |
| B/S SP seed | 会社自己資金による事前 SP 預入 | Merkl 対象外 |
| backstop funds | Vault backing repair 用の protected reserve | Merkl 対象外 |
| Safe-retained collateral yield | Day-1 担保運用益の Safe 留保 | Day-2 Treasury 承認まで Merkl / SP 報酬に使わない |

## 2. campaign 分類

| Campaign | Phase | 方針 | 理由 / gate |
| --- | --- | --- | --- |
| JPYdf/USDC Uniswap v4 LP | Day-1 / Phase-A candidate | 採用候補 | Day-1 の唯一の JPYdf DEX pair。`PILAllocator` / `UniV4MerklInitiative` / 承認済みactivation packageと整合させる |
| JPYdf/USDT LP | Day-2 candidate | 条件付き | Day-1 route は USDC に集約。USDT demand / partner / liquidity need が出た場合に別 pool / initiative として検討 |
| JPYdf/JPYC LP | Day-2 candidate | 条件付き | dormant route（[Liquidity-Route-Policy](../../product/policies/Liquidity-Route-Policy.md) §7）の発動が前提。発動後もcampaign化は別途個別承認とし、Day-1 / Phase-Aの候補にしない |
| JPYdf/dToken LP | Backlog | Day-1 非採用 | dToken は担保受益権であり、JPYdf exit liquidity とは目的が違う。利用需要とリスク説明が固まるまで候補化しない |
| External lending market | Day-2 candidate | 条件付き | supply / borrow の実需要、oracle、liquidation、market admin、claim UX がそろった場合だけ採用 |
| SP additional reward via Merkl | Not adopted | 非採用 | 恒常的な SP 追加報酬は Day-2 の protocol-native distributor で扱う。Merkl は外部 LP / lending / bootstrap に限定 |

## 3. JPYdf/USDC Phase-A initial policy

Phase-A は「まず 1 epoch だけ有効化し、実績で継続判断する」方式を標準とする。自動で長期 campaign にしない。

| 項目 | Phase-A 初期 policy |
| --- | --- |
| 対象 pair | JPYdf/USDC Uniswap v4 のみ |
| Funding source | PIL のみ。PIL 以外の Merkl campaign budget は個別 governance 承認がある場合だけ使う |
| Initial funding rule | 現行 contract では、`createCampaign()` 時点で `UniV4MerklInitiative` が保持する JPYdf 残高を campaign amount にする |
| Campaign cap | Phase-A では absolute cap を置かない。`UniV4MerklInitiative` / `PILAllocator` は per-campaign cap を強制しない |
| Budget control | active routing しない、weight を 0 にする、reserve initiative へ weight を割る、campaign 作成を遅らせる、のいずれかで制御する |
| Reserve / carry-over | 閾値未満、campaign 作成後に追加で入った PIL、reserve initiative へ配分した PIL は次回以降へ carry-over |
| Duration | 初回は 1 epoch。2 epoch 目以降は KPI review 後に継続承認 |
| Review cadence | funded epoch ごと |
| User segment | external LP、arbitrageur、market maker、partner LP。DF controlled LP seed は user acquisition KPI に含めない |
| Day-1 non-goals | SP 追加報酬、Referral、dToken LP、external lending market の incentive 化 |

```text
campaignAmount = UniV4MerklInitiative.JPYdf.balanceOf(address(this))
```

campaign amount が `CAMPAIGN_JPYDF_AMOUNT_THRESHOLD` 未満なら campaign は作成せず、残高は次回へ carry-over する。同じ `campaignStart` の campaign 作成後に追加 PIL が入った場合も、現行 `UniV4MerklInitiative` では次 campaignStart へ carry-over する。

Phase-A で absolute cap を不要とする理由は、PIL が protocol revenue のうち DEX liquidity incentive として設計された bucket であり、1 epoch ごとの KPI review、weight 変更、pause、reserve initiative で停止・縮小できるためである。将来、per-campaign absolute cap が必要になった場合は、現行 `UniV4MerklInitiative` の運用ではなく、新しい initiative / allocator を deploy して `InterestRouterForwarder` の recipient または registered initiative を差し替える。

## 4. KPI definitions

KPI は「APR を高く見せること」ではなく、**JPYdf の exit liquidity と peg 周辺 depth を改善すること**を目的に置く。B/S LP seed は初期市場を作るための自己資金であり、Merkl campaign の成果として二重計上しない。

| KPI | 初期基準 / 算定ルール | 継続判断 |
| --- | --- | --- |
| Campaign efficiency | `totalPoolVolume / postFeeRewardAmount`。既知の DF 自己取引、wash volume、明確な circular volume は検出できる範囲で控除し、控除できない分は limitation として記録 | 2 funded epochs 連続で `10x` 未満なら継続再承認 |
| External eligible TVL | Merkl eligible TVL から DF controlled LP seed を除いた残高。除外不能な場合は address list と limitation を evidence に残す | 2 funded epochs 連続で増加なし、または実質 0 なら継続再承認 |
| Spread | JPYdf/USDC implied JPY price の peg 乖離。oracle / redemption / pool incident を別注記する | 通常時に median ±0.5% 外、または p95 ±1.0% 外なら要レビュー |
| Depth 0.1% | 0.1% price impact depth。Day-1 1 億円 LP seed の beta 目安は約 108 万円。LP seed が変わる場合は notional 比で再計算 | beta 目安を大きく下回る状態が続くなら要レビュー |
| Depth 0.5% | 0.5% price impact depth。Day-1 1 億円 LP seed の beta 目安は約 522 万円 | redemption fee line の実務 proxy として重視 |
| Depth 1.0% | 1.0% price impact depth。Day-1 1 億円 LP seed の beta 目安は約 757 万円 | large swap / JIT 調達余力の補助指標 |
| Campaign execution | `route -> distribute -> createCampaign` が予定 epoch で成功し、post-fee distribution が Merkl に反映される | 失敗時は次 epoch 前に原因を解消するまで更新停止 |

Depth 目安は [`Liquidity-Management-Policy.md`](../../operations/policies/Liquidity-Management-Policy.md) の beta 案を参照する。実 pool の LP notional、range、fee tier、IPOR / manual 管理の採否が変わった場合は、activation package で再計算した値を使う。

## 5. activation gate

JPYdf/USDC Merkl campaign を active にする前に、次を満たす。

1. `Liquidity-Route-Policy.md` の JPYdf/USDC Uniswap v4 pool が作成済みで、pool key / poolId / hook policy / fee / tick spacing が evidence 化されている。
2. 承認済みactivation packageの`pil-activation-manifest.json`に`PRM-PILA-*`相当の投入値がfreeze済みである。
3. retained PIL balance、`distribute()` 後の initiative 予想残高、campaign amount、post-fee expected distribution を evidence 化している。
4. Merkl `DistributionCreator` 公式 address、fee model、terms / KYC 要否、claim UX、unclaimed rewards policy を確認済みである。
5. `InterestRouterForwarder.setRecipient(PILAllocator)`、initiative 登録、weight 設定、campaign 作成の Safe / Timelock action が別々に確認できる。
6. B/S LP seed、SP seed、backstop funds、Safe-retained collateral yield と campaign budget を二重計上していない。
7. fork / dry-run で `route -> distribute -> createCampaign` の一気通貫と no-op / carry-over path を確認している。
8. KPI dashboard / artifact が §4 の各指標を epoch ごとに再計算できる。

## 6. 停止条件

以下のいずれかに該当したら、新規 campaign 作成または次 epoch 更新を止める。

| 条件 | 対応 |
| --- | --- |
| JPYdf/USDC pool の価格・depth が異常 | campaign 更新を止め、LP / oracle / redemption 状態を確認 |
| §4 の KPI が 2 funded epochs 連続で未達 | campaign 継続を再承認制にする |
| wash trading / self-dealing / 明確な incentive farming | blacklist 方式または新 initiative の要否を検討。Day-1 は in-place blacklist しない |
| Merkl engine / API / Distributor / dispute に incident | `PILAllocator.pause()` または campaign 作成停止 |
| campaign fee を含む費用対効果が悪化 | budget を減額、終了、または別 channel に移す |
| Safe-retained yield や backstop funds との混同が発生 | campaign を止め、会計分類を修正してから再開 |

## 7. Merkl 固有の扱い

2026-07-01 時点の Merkl official docs では、standard campaign fee は 3% で、fee は campaign に deposit した token から控除される。追加 token を fee 用に送る前提にしない。規模に応じた degressive fee、commitment model、unclaimed rewards policy は activation package で最新条件を確認する。

Merkl は off-chain engine で activity を計算し、Merkle root を on-chain に投稿し、ユーザーは Merkl app / API などで claim する。これは JPY DeFi protocol-native claim ではなく、外部 trust boundary である。UI / ops では Core SP reward、Day-2 SP additional reward、Merkl LP reward を混同しない。

## 8. 参照

- Issue #649: Merkl campaign 候補と launch KPI policy を整理する
- [`../../spec/PILAllocator.md`](../../product/spec/PILAllocator.md)
- [`Liquidity-Route-Policy.md`](../../product/policies/Liquidity-Route-Policy.md)
- [`Liquidity-Management-Policy.md`](../../operations/policies/Liquidity-Management-Policy.md)
- [`Balance-Sheet-Liquidity-Allocation-Policy.md`](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md)
- [`Protocol-Revenue-Allocation-Policy.md`](./Protocol-Revenue-Allocation-Policy.md)
- Merkl Technical Overview: https://docs.merkl.xyz/merkl-mechanisms/technical-overview
- Merkl Fee Model: https://docs.merkl.xyz/distribute-with-merkl/fee-model
