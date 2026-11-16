# 清算 Backstop / JIT 方針

## 位置づけ

本書は、JPYdf launch における Stability Pool（SP）清算、運営 backstop、JIT
（just-in-time）清算支援の境界を定義する設計メモである。

清算そのもののオンチェーン仕様は
[`../../spec/Liquity-v2-Core-Spec.md`](../../product/spec/Liquity-v2-Core-Spec.md)、清算 bot
の実装計画は [`../plans/Liquidation-Bot-Plan.md`](../../../engineering/plans/Liquidation-Bot-Plan.md)、
Day-1 の DEX liquidity / route は
[`Liquidity-Route-Policy.md`](../../product/policies/Liquidity-Route-Policy.md) を正本とする。本書は、それらを
横断する運用上の backstop 用語を固定する。

## 用語

| 用語 | 意味 |
| --- | --- |
| SP offset | `TroveManager.batchLiquidateTroves` 実行時、branch-local Stability Pool の JPYdf deposit を使って対象 Trove debt を相殺する Liquity core の経路 |
| redistribution | SP deposit で相殺しきれない debt/collateral が残存 Trove に再配分される Liquity core の経路 |
| Backstop | 運営または第三者が、清算が滞らないよう JPYdf・DEX liquidity・清算実行・担保処分を運用で補うこと |
| JIT | 清算候補が発生した後、または発生直前の短い時間窓で、SP offset capacity を増やすために JPYdf を調達・SP deposit してから清算する運用 |
| Atomic JIT | 1 tx / bundle 内で JPYdf 調達、SP deposit、清算、必要なら担保処分まで行う executor。Day-1 実装ではない |

## Day-1 の決定

Day-1 で実装済み・運用対象にするのは、次の 2 層までである。

1. **事前 SP**: launch 時点で運営が自己 mint した JPYdf を branch ごとの Stability Pool
   に deposit する。
2. **非原子的 JIT top-up**: 清算 bot / ops dashboard が SP offset capacity と候補 debt
   を観測し、必要に応じて運営が保有 JPYdf または DEX で調達した JPYdf を
   `StabilityPool.provideToSP` で追加 deposit する。

Day-1 では **Atomic JIT executor は実装しない**。したがって、配分表で使う
「SP + JIT capacity」はコントラクトが保証する capacity ではなく、運営が調達・SP
deposit・清算実行まで完了できることを前提にした **運用 planning capacity** である。

## 現行実装でできること

| 領域 | 現行対応 |
| --- | --- |
| 清算候補検出 | `bots/liquidator` が `LiquidationCandidateGetter` と `lastZombieTroveId` を使って branch ごとに巡回する |
| 清算直前の再検証 | bot が `TroveManager.getCurrentICR` で候補を再検証する |
| SP capacity 観測 | bot が `StabilityPool.getTotalJpydfDeposits()` から `MIN_JPYDF_IN_SP` 控除後の offset capacity をログに出す |
| 清算実行 | bot が branch-local `TroveManager.batchLiquidateTroves` を dry-run / live 設定に応じて送信できる |
| Vault incident guard | bot は Vault pause / backing ratio safety を scan 時と submit 前に再確認する |

## 現行実装でやらないこと

| 領域 | Day-1 非対応 |
| --- | --- |
| JPYdf 調達 | bot は Uniswap v4 で JPYdf を買わない。DEX LP は調達環境を支えるが bot の route ではない |
| SP top-up | bot は `provideToSP` を自動実行しない。SP deposit は operator runbook / Safe / 別 executor の責務 |
| atomic bundle | JPYdf 調達 -> SP deposit -> liquidation を 1 tx / bundle に束ねない |
| 担保処分 | 清算で得た担保の売却・退避・会計処理は bot 本体では扱わない |
| capacity guarantee | SP + JIT capacity をコントラクト上で予約・保証しない |

## 非原子的 JIT top-up の標準手順

1. bot / ops が liquidatable candidate、候補 debt、branch SP offset capacity を検知する。
2. operator は branch の Vault safety、oracle failure、shutdown 状態を確認する。
3. SP capacity が不足する場合、operator は保有 JPYdf、自己 mint 済み JPYdf、または
   JPYdf/USDC Uniswap v4 liquidity から調達した JPYdf を用意する。
4. operator は対象 branch の `StabilityPool.provideToSP(amount, false)` で SP を top-up
   する。
5. liquidator bot が `batchLiquidateTroves(troveIds)` を実行する。
6. 清算後、SP depositor の collateral gain、残 JPYdf deposit、必要な担保処分を別 runbook
   で会計処理する。

この手順は mempool / timing / 価格変動の影響を受けるため、大口清算では private relay、
明示的な loss cap、事後会計証跡を必要とする。

## Atomic JIT を将来入れる場合の gate

Atomic JIT executor を追加する場合は、既存 bot の設定追加ではなく、新しい audited
entrypoint / executor として扱う。最低限、以下を満たすまで production へ入れない。

- 資金源を明示する。operator inventory / flash liquidity / DEX swap / self-mint を混同しない。
- JPYdf/USDC Uniswap v4 route は pool key、hook policy、Universal Router / Permit2
  address、min-out、allowance cleanup を freeze する。
- executor は任意 route を受け取らず、allowlist 済み route のみ使う。
- SP deposit と清算対象 branch が一致することを on-chain / typed config で検証する。
- loss cap / max gas / min collateral gain / max slippage を必須にする。
- private relay / bundle 失敗時の再送・キャンセル・nonce 管理を runbook 化する。
- `batchLiquidateTroves` 内部価格は core の `priceFeed.fetchPrice()` に従うため、executor
  の swap quote を清算可否の oracle として扱わない。
- fork test で、SP 十分・SP 不足・route slippage・oracle failure・Vault pause・shutdown
  branch・zombie Trove を含める。

## ドキュメント上の表記ルール

- 「JIT flash 清算 max」のように flashloan / atomic bundle を連想させる表記は、実装が無い
  限り使わない。
- 配分表では **JIT backstop capacity** または **operator JIT capacity** と書き、脚注で
  「運用 planning capacity であり、コントラクト保証ではない」と明記する。
- DEX liquidity と JIT capacity は同じではない。JPYdf/USDC LP は JPYdf 調達・peg 防衛を
  助けるが、SP deposit や清算実行を自動化しない。
