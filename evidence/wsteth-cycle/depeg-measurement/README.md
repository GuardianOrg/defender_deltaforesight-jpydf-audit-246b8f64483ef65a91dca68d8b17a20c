# stETH/ETH depeg 実測スクリプト（dwstETH risk parameter）

[dwstETH risk parameter の導出と判断根拠](../../dwsteth-risk-parameter-derivation.md) §4 の Depeg レッグ 3.25% を再現するための取得・統計スクリプト。

```bash
python3 steth_dd.py       # DefiLlama 時間足を取得し ratio.json を生成、生の統計を出力
python3 steth_clean.py    # ratio.json をクレンジングし、採用値の統計を出力
```

- `steth_dd.py` は `coins.llama.fi` から stETH / WETH の時間足 USD 価格を 2022-01-01 以降取得し、比率と window 最大 DD・パーセンタイルを出力する。中間生成物 `ratio.json`（約 800KB）はコミットしない。
- `steth_clean.py` は妥当性クリップ `[0.85, 1.05]` と 5 点近傍中央値からの 1.5% 乖離除去（反復）を適用し、採用値の統計を出力する。
- 取得時点（2026-08-05）の出力: joint 27,694 点、除去 486 点、2h 最大 DD **3.25%**（2022-06-01）、p99.9 2.08%。DefiLlama は過去値を後日補正しうるため、再実行値が末尾桁で動くことはある。
