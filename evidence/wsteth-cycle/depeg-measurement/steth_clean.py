#!/usr/bin/env python3
"""Clean single-point anomalies from the stETH/ETH hourly ratio and recompute
window drawdowns. Mirrors the repo pipeline's outlier exclusion (JPY/USD
excluded 270 anomalies). A real depeg persists for many hours; a lone point
that jumps away from both neighbors is a data glitch."""
import json, datetime

ratio = json.load(open("ratio.json"))
n0 = len(ratio)

# 1. hard plausibility clip
ratio = [(h, r) for h, r in ratio if 0.85 <= r <= 1.05]

# 2. spike filter: drop points deviating >1.5% from the median of the
#    5-point neighborhood (repeat until stable)
def despike(series):
    out, dropped = [], 0
    for i, (h, r) in enumerate(series):
        lo = max(0, i - 2)
        neigh = [x[1] for x in series[lo:i + 3]]
        med = sorted(neigh)[len(neigh) // 2]
        if abs(r - med) / med > 0.015:
            dropped += 1
        else:
            out.append((h, r))
    return out, dropped

total_dropped = n0 - len(ratio)
while True:
    ratio, d = despike(ratio)
    total_dropped += d
    if d == 0:
        break
print(f"points kept {len(ratio)} / {n0} (dropped {total_dropped})")

def window_dd(series, w):
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

def pct(vals, q):
    return vals[min(len(vals) - 1, int(q * len(vals)))]

def fmt(h):
    return datetime.datetime.utcfromtimestamp(h * 3600).strftime("%Y-%m-%d %H:%M")

for w in (1, 2, 24, 168):
    dds = window_dd(ratio, w)
    vals = sorted(d for _, d in dds)
    print(f"\nwindow {w}h: maxDD {vals[-1]*100:.3f}% | p99.9 {pct(vals,0.999)*100:.3f}% | p99 {pct(vals,0.99)*100:.3f}%")
    if w == 2:
        # top events, deduped to >72h apart
        top = sorted(dds, key=lambda x: -x[1])
        shown = []
        for h, d in top:
            if all(abs(h - s) > 72 for s in shown):
                shown.append(h)
                print(f"  {fmt(h)}  2h DD {d*100:.3f}%")
            if len(shown) == 10:
                break

lo_h, lo_r = min(ratio, key=lambda x: x[1])
print(f"\nall-time min ratio: {lo_r:.4f} at {fmt(lo_h)}")
peak, worst, worst_h = 0, 0, 0
for h, r in ratio:
    peak = max(peak, r)
    if (peak - r) / peak > worst:
        worst, worst_h = (peak - r) / peak, h
print(f"full peak-to-trough: {worst*100:.3f}% (trough {fmt(worst_h)})")
recent = [x for x in ratio if x[0] * 3600 >= 1681257600]
lo_h, lo_r = min(recent, key=lambda x: x[1])
print(f"post-Shapella (2023-04-12+) min ratio: {lo_r:.4f} at {fmt(lo_h)}")
dds2 = window_dd(recent, 2)
vals2 = sorted(d for _, d in dds2)
print(f"post-Shapella 2h maxDD {vals2[-1]*100:.3f}% | p99.9 {pct(vals2,0.999)*100:.3f}%")
