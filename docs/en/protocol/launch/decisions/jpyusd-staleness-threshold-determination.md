# JPY/USD staleness threshold design


| Item | Value |
| ------- | ----------------------------------------------------------------------------------------------------------------- |
| Purpose | Determine the `stalenessThreshold` for JPY/USD (the leg common to all branches) |
| Scope | This document covers **only the value determination of the JPY/USD leg's staleness threshold** |
| Basis | Direct measurement of Chainlink JPY/USD's actual mainnet update history (2024-06-28 to 2026-06-16, approx. 6,871 updates) + cross-check against implementation code (Claude Opus 4.8, measured 2026-06-17) |
| Target feed | proxy `0xBcE206caE7f0ec07b545EddE332A47C2F75bbeb3` ("JPY / USD", 8 decimals, returns USD per JPY) |


---

## 1. Policy

The audit remediation uses a JPY/USD `stalenessThreshold` of **30h (108,000 seconds)** and a **24h cached-rate grace**, replacing the previous 72h threshold.

- At age 30h, stop new borrowing, debt increases, collateral withdrawals, normal redemption, and new permanent-shutdown decisions. Before permanent shutdown, `closeTrove` also falls under this restriction because it combines full repayment with collateral withdrawal.
- Pure repayments and collateral additions require no oracle quote; authorization, minimum debt, and permanent-shutdown restrictions remain.
- Liquidations may continue until age 54h, only while all other price inputs remain valid.
- After a fresh JPY update, reassess TCR including accrued debt and allow permanent shutdown if TCR is below SCR.

Values are canonical in [Parameters](../../../Parameters.md) `PRM-ORACLE-001/006/008`; behavior is in [Oracle](../../product/spec/Oracle.md) `ORCL-SEC-005`. The additional 24h grace is a policy under validation, not a claim of optimality or production risk approval.

---

## 2. Premise: heartbeat and staleness threshold are different things

To avoid misidentifying the decision target, distinguish two "periods."

- **heartbeat (24h)** … The cycle fixed on the Chainlink side: "updates are expected even with no price change." This does not guarantee delivery during an outage. **It is an external spec; we cannot change it.**
- **staleness threshold (the decision target of this document)** … The on-chain threshold we set in the PriceFeed for "how many seconds ago `updatedAt` is still considered healthy."

The determination formula (`MainnetPriceFeedBase`) is `block.timestamp - updatedAt < stalenessThreshold`. It is **strict `<`** (stale exactly at the elapsed threshold) and has no weekday / holiday calendar.

Market closure and feed silence are different. The observations in §3 show approximately 24h updates during weekends and holidays; nearly 72h of silence is not normal weekend behavior.

---

## 3. Empirical basis: it updates every 24h regardless of FX closures

The threshold is decided by measuring "how stale the feed can actually become during an FX closure." The only concern was "whether the 24h keepalive might break during the long FX closures of Christmas/New Year, becoming stickily stale for a long time." Direct measurement of Chainlink on mainnet refuted this.

**Verification target and method (reproducible)**

- Directly read the aggregator behind the target proxy `0xBcE206caE7f0ec07b545EddE332A47C2F75bbeb3` ("JPY / USD", 8 decimals). phase 5 aggregator `0xA0B5260BDfD1011C4bcdc7A099C75BFf6340B38C` (2024-06 to present), phase 4 aggregator `0x01A1F73b1f4726EB6EB189FFA5CBB91AF8E14025` (through 2024).
- Retrieve **all** `AnswerUpdated` events for each aggregator, and compute the **consecutive differences of `updatedAt`** (the time the price was actually posted on-chain) **= the maximum time the feed can become stale**. Directly measured on 2026-06-17 with an archive-capable RPC.

### 3.1 Scan of the observation period

phase 5 was scanned continuously from operation start (2024-06-28) to the latest.


| Range | Updates | Max update interval | Over 25h | Over 48h |
| ---------------------------------- | ------- | ---------- | ------- | ------- |
| 2024-06-28 to 2026-06-16 (approx. 1.9 years continuous) | approx. 6,871 | **24.02h** | **0** | **0** |


The top gaps are all ~24.02h and are not biased to a specific season or weekday (e.g. `2026-06-05 12:54→06-06 12:55`, `2025-09-05→09-06`, `2025-03-14→03-15`, all 24.02h). On trading days it updates sub-hourly according to price movement, and a continued no-update occurs only during FX closures. Even during those closures the last healthy rate keeps being posted every 24h, and no multi-day silence occurs.

### 3.2 By year-end/New-Year season (direct verification of the concern)

Including the worst condition where FX closes for a 3-day weekend (Sat-Sun-Mon), the past 5 year-end/New-Year seasons were individually measured.


| Season | aggregator | Updates | Max gap | Over 25h | New Year's Day `12/31→1/1` |
| ------- | ---------- | --- | ------ | ----- | -------------- |
| 2021/22 | phase 4 | 38 | 24.03h | 0 | 24.01h |
| 2022/23 | phase 4 | 445 | 24.01h | 0 | ~24.0h |
| 2023/24 | phase 4 | 193 | 24.01h | 0 | 24.01h |
| 2024/25 | phase 5 | 184 | 24.01h | 0 | 24.01h |
| 2025/26 | phase 5 | 94 | 24.01h | 0 | 24.01h |


- **On none of Christmas (12/24→25), New Year's Day (12/31→1/1), or the 3-day weekend did the 24h-interval keepalive break even once.** E.g. `2023-12-30 16:14 → 12-31 16:15 → 2024-01-01 16:15` (each 24.01h). The heartbeat fires regardless of market open/close.
- Zero over-25h across all 5 seasons. The concern that "multi-day silence occurs during the long year-end/New-Year closure" was refuted by actual data.

Observed maxima were near 24h: 24.02h in the continuous phase-5 scan and up to 24.03h in the separate holiday samples. These are sample maxima, not future outage bounds.

---

## 4. The 30h restriction and 24h liquidation grace

The historical sample in §3 observed a maximum interval near 24h. A 30h cutoff allows margin over normal updates while restricting additional borrowing exposure after missed updates. This sample does not bound future update gaps or FX movements.

During 30–54h, cached FX can miss liquidations when JPY strengthens and wrongfully liquidate healthy Troves when JPY weakens. Stopping liquidation at 30h can instead increase uncovered debt during collateral price declines. Compare both FX directions near MCR and shortfalls under suspended liquidation, including continued debt accrual and delayed urgent redemption while necessary shutdown is postponed.

## 5. Grace anchoring and recovery

All active branches share one `JpyUsdRateProvider`. `jpyFrozenSince` is the earlier of first failure observation and `lastGoodJpyUpdatedAt + 30h`; a later access cannot restart the 24h window. A staleness-only episode therefore expires exactly at age 54h; an earlier invalid response can expire sooner.

Collateral, peg, canonical-rate, and backing validation remain mandatory during grace. Oracle pause is recoverable and distinct from permanent TCR/SCR shutdown. A fresh valid quote can restart liquidation, but a latched borrowing pause requires Owner-validated resume. The age gate alone does not latch pause and clears automatically after fresh provenance is observed.

See [Mainnet Deploy Env Freeze Runbook](../gates/Mainnet-Deploy-Env-Freeze-Runbook.md) §3.1.1 for operations.

---

## 6. Risks and Premises

- **External dependency**: Chainlink's heartbeat changes and feed deprecate / migration remain as external factors. Detect them early by monitoring `data.chain.link` and on-chain `updatedAt`.
- **Monitoring responsiveness is a premise**: direct feed monitoring and prompt source-replacement operations must accompany this value.
- **Handling of secondary information**: The deviation threshold ≈ 0.15% is a reference value derived from the public data page (original not obtained). This decision does not depend on it and is based on primary information (the on-chain-measured 24h keepalive). The measured behavior (sub-hourly on trading days, 24h interval on closed days) is consistent with this value.

---

*Verification / authoring: Claude Opus 4.8 (2026-06-17). The measurements in this document are based on read-only measurement of mainnet Chainlink contracts and cross-checking of implementation code.*
