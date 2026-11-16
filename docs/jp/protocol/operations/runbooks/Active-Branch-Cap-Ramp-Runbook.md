# Active Branch Cap Ramp Runbook

## 0. Scope

稼働中 branch（Day-1 は dwstETH / dUSDC）の `mintCap` を、post-launch に段階的に引き上げるための運用手順を定める。

本runbookは [Parameter Catalog](../../product/parameters/Parameter-Catalog.md) `PRM-mintCap`、[Collateral Parameter Policy](../../product/policies/Collateral-Parameter-Policy.md) §3.1、[Day1 Parameter Decision](../../launch/decisions/Day1-Parameter-Decision.md) §3.1、`Mainnet-Launch-Operation-Gate.md`、`Liquidation-Management-Policy.md`、`Governance-Roles-Timelock.md`を運用手順へ落とす。`mintCap`はdToken supply / collateral exposure capであり、JPYdf debt ceilingではない。CoreにDay1 hard branch debt ceilingは追加しない（#301方針）。

対象:

- すでに borrowable collateral として public exposure を開けている branch。
- Day-1 は dwstETH / dUSDC。
- 将来 active 化済み branch は、この runbook に加えて当該 activation runbook / risk review を通す。

対象外:

- `mintCap = 0`のinert branch（Day-1はbranch 2–7）を0から開ける操作。[Inert Branch Activation Runbook](./Inert-Branch-Activation-Runbook.md)を使う。
- inert branch の初回 cap 引き上げ。先に Inert Branch Activation Runbook を完了する。
- Core の hard branch debt ceiling 実装。

## 1. Principles

1. `setCap` 単独で上げない。SP coverage、liquidation bot、JPYdf/USDC liquidity、ops monitoring、frontend表示を同時に確認する。
2. `dToken.setCap` は共通 Timelock 経由で、即時引き上げではない。delay は [Parameters](../../../Parameters.md) `PRM-GOV-COMMON-TIMELOCK-DELAY` を正本とする。需要が詰まってからではなく、80% utilization の段階で proposal 準備へ入る。
3. `mintCap` と `allocateMaxMove` は同じ proposal bundle でレビューする。Day-1 active branch の標準は同じ名目露出へ更新する。例外（Strategy allocation を抑える、または outbound allocation を止める）は decision log に理由を残す。
4. post-ramp の planned debt はオンチェーン cap ではなく、SP coverage / bot / liquidity を検査するための保守的な運用分母である。
5. cap reduction / `pauseDeposit` は新規 dToken mint を止めるだけで、既存 dToken collateral に対する Core debt increase は止めない。この残余リスクは cap ramp 承認時に明示する。

## 2. Quantitative Gates

### 2.1 Trigger

cap ramp proposal は、次のいずれかで準備を開始する。

| Trigger | Gate |
| --- | --- |
| cap utilization watch | `dToken.totalSupply / dToken.cap >= 8,000 bps` が 24h 継続、または ops alert `ALRT-MKT-007` が発火 |
| demand forecast | launch owner / sales owner が次の 48h に現 cap の 80% 超過を見込む |
| public campaign | campaign 開始前に想定流入が現 cap の 50% を超える |
| nominal exposure drift | Day1 active branchは[Day1 Parameter Decision](../../launch/decisions/Day1-Parameter-Decision.md) §3.1、以後のbranchは直近の承認済みDecision Record / proposalが定める再計算thresholdへ到達 |

`>= 9,500 bps` で Timelock executable な cap ramp が無い場合、campaign / UI exposure / sales push を一時停止するか、risk owner が exception を記録する。`>= 10,000 bps` は新規 dToken mint が詰まるため、user copy と cap ramp / campaign pause 判断を即時に行う。

cap ramp proposalの作成時はutilizationにかかわらず、Policy §3.1の方法で現行capとproposal後capの名目JPY exposureを再計算する。risk ownerがcap reductionを提案する場合も同じ換算Evidenceを使い、`totalSupply > newCap`でも既存供給とCore debt increaseを止めない残余リスクをproposalへ記載する。

> **上方ペグ乖離（JPYdf > ¥1）対応の注意**: 上方乖離の解消を目的とする cap raise も本 runbook の同一手順に従い、**`setCap` Owner = 共通 TimelockController の delay は運用側で短縮できない**。既存 dToken collateral / 現 cap headroom 内の借入はこの delay の対象外である。上方乖離への速い供給反応は任意の適格borrowerによる既存Core経路の追加借入と市場供給であり、Protocolまたは特定Contributorの実行を保証しない。Contributorが自己B/S対応を採用する場合は、そのPolicy / Commitment / 承認Evidenceを別途要する。追加 cap の ramp は遅いレバーとして扱う（[Mainnet Launch Risk Gate](../../launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-009) / [Architecture Decision Records](../../product/architecture/Architecture-Decision-Records.md#adr-007)）。borrow APR の変更は借入コストと Redemption 順位を変える付随判断であり、APR 引き下げだけを供給対応の完了と扱わない。`plannedDebtJpydf` や cap の名目円額を即時 debt room として扱わない。提案 evidence には branch ごとの dToken `totalSupply / cap`、既存 Trove の entire collateral / debt、使用価格、target LTV / LLTV、既存担保の追加借入余力、cap headroom で受け入れられる新規担保と upfront fee 込み debt capacity を分けて記録する。borrowerが実行した場合のevidenceには追加借入額、max upfront fee、実行後 ICR / LTV、Redemption exposure、当該borrowerの承認、debt increase tx、市場供給tx、post-action price / depthを記録する。

### 2.2 Step and Cooldown

Day-1 active branch の通常 step は次を上限とする。これを超える場合は新しい risk-owner review と stress evidence を必要とする。

| Branch | Initial cap | Normal step max | Unreviewed ramp ceiling | Cooldown |
| --- | ---: | ---: | ---: | --- |
| dwstETH | 35 百万円 | `min(12.5 百万円, current cap × 25%)` | 50 百万円 | 実行後 72h |
| dUSDC | 1 億円 | `min(25 百万円, current cap × 50%)` | 2 億円 | 実行後 24h |

Cooldown 中に次の proposal を queue してよいが、前回 ramp の T+24h / T+72h watch が green になるまで execute しない。

### 2.3 SP Coverage

cap ramp の SP coverage は、次の conservative denominator で計算する。

```text
coverageDebtJpydf = max(currentBranchDebtJpydf, proposedMintCapJpyNotional)
requiredSpJpydf = coverageDebtJpydf * minSpCoverageBps / 10_000
```

`proposedMintCapJpyNotional` は JPYdf hard cap ではない。dToken collateral exposure cap を JPY 名目に直した運用分母であり、actual debt がこれを上回る場合は actual debt を使う。

Minimum:

| Branch | minSpCoverageBps | Target note |
| --- | ---: | --- |
| dwstETH | 5,000 bps | wstETH 高ボラ branch（ETH 系）。cap ramp 前に SP seed / JIT concentration owner を確認する |
| dUSDC | 1,250 bps | absolute minimum。bootstrap economics / public APR policy では 3,750 bps target を別途参照する |

No-Go:

- `spDeposits < requiredSpJpydf`。
- SP top-up source が LP seed / Treasury留保 / backstop と二重計上されている。
- `minSpCoverageBps` を満たすが、bot dry-run の planned batch が 100% offset coverage を満たせない。

### 2.4 JPYdf/USDC Liquidity and JIT

cap ramp 前に、次を current block で evidence 化する。

| Gate | Required evidence |
| --- | --- |
| JPYdf/USDC pool | StateView / Quoter direct RPC で sample sell / buy slippage が launch envelope 内 |
| JIT capacity | operator JPYdf inventory、USDC inventory、self-mint availability、または SP top-up tx owner |
| 25% event | `coverageDebtJpydf * 25%` の liquidation cluster を想定し、SP + confirmed JIT capacity が decision log 上で不足しない |
| liquidator dry-run | enabled branches、SP offset capacity、candidate count、planned batch gas、stressed gas cost、skipReason が current policy と一致 |

DEX liquidity は JIT 調達を助けるが、SP top-up や liquidation execution を保証しない。Atomic JIT executor は Day-1 scope 外。

## 3. Governance Procedure

### 3.1 Proposal Bundle

cap ramp は次を 1 bundle として review する。

1. `dToken.setCap(newCap)`.
2. `CollateralVault.setAllocatorConfig(newAllocateMaxMove, allocatorCooldown)`。
3. 必要に応じて `CollateralVault.setBufferConfig(...)` / Strategy cap update。
4. frontend / ops config、public stats、campaign copy の更新 evidence。

`newAllocateMaxMove` は `newCap` と同じ名目露出を標準とする。ただし Strategy capacity、buffer、market condition の理由で小さくする場合は、decision log に `newAllocateMaxMove < newCap` の理由を書く。`newAllocateMaxMove > newCap` は不可。

### 3.2 Timeline

| Timing | Action |
| --- | --- |
| T-48h to T-24h | risk owner が step、coverageDebt、SP/JIT、liquidity、bot dry-runを承認 |
| Timelock queue | Safe tx / calldata hash / expected new values を記録 |
| T-0 | execute 前に `ALRT-MKT-001..007`、oracle、backing、SP coverage、liquidity monitor が green であることを再確認 |
| T+1h | dToken cap、allocateMaxMove、frontend/ops表示、public stats JSON を direct RPC / artifact で確認 |
| T+24h / T+72h | branch別 cooldown watch。SP coverage、liquidation candidates、redemption activity、JPYdf/USDC slippage、cap utilization を decision log に記録 |

## 4. Evidence Template

```text
Active branch cap ramp evidence

Branch:
Current cap (token units / JPY notional):
Proposed cap (token units / JPY notional):
Approved nominal target:
Underlying price source / round / block:
Current estimated cap notional:
Proposed estimated cap notional:
Notional drift bps:
Recalculation trigger:
Current dToken supply:
Cap utilization bps:
Current branch debt:
Coverage debt denominator:
minSpCoverageBps:
Current SP deposits:
Required SP deposits:
SP top-up source / owner:

Current allocateMaxMove:
Proposed allocateMaxMove:
Allocator cooldown:
Strategy cap / weight impact:
Buffer target / floor impact:

JPYdf/USDC sample sell size / slippage:
JPYdf/USDC sample buy size / slippage:
Operator JIT inventory:
25% event size:
SP + JIT capacity:

Liquidator dry-run artifact:
Stress evidence artifact / fork block:
Alerts reviewed:
Frontend/app cap warning reviewed:
Ops alert ALRT-MKT-007 status:
Public stats artifact:

Timelock proposal tx:
Safe tx hash:
Queued at:
Executable at:
Executed at:
T+watch owner:
Decision log:
```

## 5. No-Go

以下のいずれかが true なら cap ramp を実行しない。

- `mintCap` を JPYdf issuance cap / branch debt ceiling と誤記した docs / UI / ops copy が残っている。
- SP coverage が §2.3 を満たさない。
- JPYdf/USDC liquidity monitor または liquidator dry-run が stale / unavailable。
- `ALRT-BACK-*`、`ALRT-ORCL-002/003/005/006/007`、`ALRT-MKT-001/002/003/005` が未解決。
- Policy §3.1で必要な名目JPY exposureの再計算Evidenceが無い、または使用価格がstale。
- cap utilization 95% 以上にもかかわらず、Timelock proposal、campaign pause、user copy のどれも準備されていない。
- `setCap` と `allocateMaxMove` の proposal bundle が分離され、execution order / mismatch の理由が decision log に無い。
- inert branch をこの runbook だけで開けようとしている。

## 6. Frontend / Ops Expectations

- User app は cap=0 branch を borrowable route として出さない。
- User app は dToken cap が near-full の branch で claim capacity / conversion capacity warning を出す。
- Ops は active public branch の `dToken.totalSupply / dToken.cap >= 8,000 bps` を `ALRT-MKT-007` として検知し、risk owner が cap ramp / campaign pause / SP top-up を判断する。
- Ops dashboard / public stats は `dTokenSupply`、`dTokenCap`、SP coverage、branch debt、JPYdf/USDC liquidity を同じ current manifest から読む。
- Admin console / Safe proposal は current value -> proposed value diff、token unit、JPY notional、calldata hash を表示する。

## 7. References

- [`Parameter-Catalog.md`](../../product/parameters/Parameter-Catalog.md) — `PRM-mintCap`の意味・mutability
- [`../../Parameters.md`](../../../Parameters.md) — Day1値
- [`Collateral-Parameter-Policy.md`](../../product/policies/Collateral-Parameter-Policy.md) §3.1 — cap選定・変更基準
- [`Day1-Parameter-Decision.md`](../../launch/decisions/Day1-Parameter-Decision.md) §3.1 — Day1 active branchの初回再計算threshold
- [`Mainnet-Launch-Operation-Gate.md`](../../launch/gates/Mainnet-Launch-Operation-Gate.md)
- [`Liquidation-Management-Policy.md`](../policies/Liquidation-Management-Policy.md)
- [`Day1-Self-BS-Initial-Liquidity-Plan.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Initial-Liquidity-Plan.md)
- [`Governance-Roles-Timelock.md`](../../product/policies/Governance-Roles-Timelock.md)
- [`Inert-Branch-Activation-Runbook.md`](./Inert-Branch-Activation-Runbook.md)
