#!/usr/bin/env python3
"""stETH/ETH ratio drawdown stats from DefiLlama hourly prices.

Fetches hourly stETH & WETH USD prices, computes the stETH/ETH ratio,
then window max-drawdowns (1h/2h/24h) and percentiles, matching the
repo's Collateral-Parameter-Rationale pipeline (which used 5-min data;
hourly is the finest DefiLlama offers this far back)."""
import json, time, urllib.request, sys

STETH = "ethereum:0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84"
WETH = "ethereum:0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
START = 1609459200  # 2021-01-01
END = int(time.time())
SPAN = 500

def fetch(coin, start):
    url = (f"https://coins.llama.fi/chart/{coin}"
           f"?start={start}&span={SPAN}&period=1h")
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                return json.load(r)["coins"]
        except Exception as e:
            print(f"retry {attempt} @{start}: {e}", file=sys.stderr)
            time.sleep(2 * (attempt + 1))
    return None

steth, weth = {}, {}
START = 1640995200  # 2022-01-01, hourly coverage starts ~Jan 2022
for key, store in ((STETH, steth), (WETH, weth)):
    t = START
    while t < END:
        coins = fetch(key, t)
        if coins:
            for p in coins.get(key, {}).get("prices", []):
                store[p["timestamp"] // 3600] = p["price"]
        t += SPAN * 3600
        time.sleep(0.25)

hours = sorted(set(steth) & set(weth))
print(f"joint hourly points: {len(hours)}", file=sys.stderr)
if not hours:
    sys.exit(1)
ratio = [(h, steth[h] / weth[h]) for h in hours]

with open("ratio.json", "w") as f:
    json.dump(ratio, f)

import datetime

def window_dd(series, w):
    """max decline (start->min) over forward windows of w hours"""
    dds = []
    n = len(series)
    for i in range(n):
        h0, r0 = series[i]
        lo = r0
        j = i + 1
        while j < n and series[j][0] - h0 <= w:
            lo = min(lo, series[j][1])
            j += 1
        dds.append((h0, (r0 - lo) / r0))
    return dds

def pct(sorted_vals, q):
    idx = min(len(sorted_vals) - 1, int(q * len(sorted_vals)))
    return sorted_vals[idx]

for w in (1, 2, 24, 168):
    dds = window_dd(ratio, w)
    vals = sorted(d for _, d in dds)
    worst = max(dds, key=lambda x: x[1])
    ts = datetime.datetime.utcfromtimestamp(worst[0] * 3600)
    print(f"window {w:>3}h: maxDD {worst[1]*100:.3f}% at {ts:%Y-%m-%d %H:%M} | "
          f"p99.9 {pct(vals, 0.999)*100:.3f}% | p99 {pct(vals, 0.99)*100:.3f}%")

lo_h, lo_r = min(ratio, key=lambda x: x[1])
ts = datetime.datetime.utcfromtimestamp(lo_h * 3600)
print(f"all-time min ratio: {lo_r:.4f} at {ts:%Y-%m-%d %H:%M}")
hi_from_start = ratio[0][1]
# full peak-to-trough
peak = 0
worst_ptt = 0
for _, r in ratio:
    peak = max(peak, r)
    worst_ptt = max(worst_ptt, (peak - r) / peak)
print(f"full peak-to-trough: {worst_ptt*100:.3f}%")
# recent era (post-Shapella 2023-04-12)
recent = [x for x in ratio if x[0] * 3600 >= 1681257600]
if recent:
    lo_h, lo_r = min(recent, key=lambda x: x[1])
    ts = datetime.datetime.utcfromtimestamp(lo_h * 3600)
    print(f"post-Shapella min ratio: {lo_r:.4f} at {ts:%Y-%m-%d %H:%M}")
