# Inert Branch Activation Runbook

## 0. Scope

Day-1にUnderlying未binding・`mintCap = 0`で予約したBranch 2–7（`dETH` / `dUSD-A` / `dBTC` / `dUSD-B` / `dJPY` / `dJGB`）をactive collateralとして開放する手順を定める。全slotでexact Underlying、immutable risk適合Evidence、Owner承認、Oracle、Strategy / Zapper、audit scopeをactivation packageとして確定する。

対象外: Day1 active の Branch 0 `dwstETH` / Branch 1 `dUSDC`（product scopeは [Mainnet Launch Product Decision Record](../../launch/decisions/Mainnet-Launch-Product-Decision-Record.md) §1、risk gateは [Day1 Parameter Decision](../../launch/decisions/Day1-Parameter-Decision.md) §4。post-launchのcap変更は [Active Branch Cap Ramp Runbook](./Active-Branch-Cap-Ramp-Runbook.md) で扱う）。

本runbookは [Collateral Parameter Policy](../../product/policies/Collateral-Parameter-Policy.md) §2.4、`Oracle.md` ORCL-FR-009、`dToken.md`
DTKN-FR-002 / DTKN-FR-010、`CollateralVault.md` VAULT-FR-011 を運用手順へ落とす。

重要な前提:

- `setCap` だけで inert branch を開けてはならない。
- branch immutable parameter（MCR / CCR / SCR / BCR / liquidation penalty 等）はDay1確定のimmutable値。確定Underlyingのstress dataによる **go/no-go検証**が [Parameters.md](../../../Parameters.md) の値に収まらない場合は、[Collateral Parameter Policy](../../product/policies/Collateral-Parameter-Policy.md) §2.4に従ってactivationせず、**再デプロイ＝移行を検討**する（恒久inert据置もありうる。branch単位の差し替えはできない）。
- dToken / Vault の Underlying binding は one-shot。誤 token を設定した場合、同 branch 内では修正できない。
- activation 完了まで `mintCap = 0` を維持し、最後の `setCap(N)` だけを入金解放操作にする。

## 1. Activation Candidate Gates

次のどれかが満たせない場合、activation を止める。

| Gate | Required evidence |
| --- | --- |
| Underlying decision | token address、symbol、decimals、implementation/proxy、admin / pause / blacklist 権限、custody / redemption terms |
| Risk parameter go/no-go verification | 確定 Underlying のストレスが Day-1 immutable 値（LLTV / MCR / CCR / SCR / BCR / liquidation penalties）に収まると検証・承認済み（再導出ではなく検証。収まらなければ activation 不可） |
| Oracle design | Standard / Peg-monitored / Composite rate / Composite peg / fixed price のどれを使うか、feed address、staleness、weekend / market-hours handling |
| Liquidity / liquidation route | SP / JIT / liquidator が担保を処理できること、清算報酬が実運用上成立すること |
| dToken / Vault readiness | `dToken.totalSupply() == 0`、`dToken.cap() == 0`、`dToken.underlying() == 0`、`vault.underlying() == 0` |
| PriceFeedProxy readiness | current source が `PriceFeedPlaceholder`、owner / pending owner が expected holder |
| Frontend / ops readiness | user app は activation 前に非操作表示、admin/ops は branch state / cap / source / Underlying を読める |
| Governance readiness | Timelock proposal bundle、Guardian pause path、rollback criteria、execution window が承認済み |

Branch-specific minimum review:

| Branch | Extra review |
| --- | --- |
| 2 `dETH` | ETH 系候補（WETH / LST 等）。LST は secondary market depeg、slashing / negative rebase、withdrawal queue / exit、canonical rate provider を検証する。envelope は branch 0 と同一（LST 固有 depeg risk を含む保守側、[Parameters.md](../../../Parameters.md) §2-A） |
| 3 `dUSD-A` / 5 `dUSD-B` | permissionless / yield-bearing / RWA 等のカテゴリは事前に固定せず、候補ごとに issuer / protocol dependency、transfer restriction、freeze / blacklist、redemption、canonical rate / NAV、secondary liquidity を検証する |
| 4 `dBTC` | BTC wrapper peg / custody / withdrawal delay / staking slash or finality risk。WBTC/BTC 型 peg monitor の有無 |
| 6 `dJPY` | JPY 建て資産（regulated JPY asset 等）を候補とし、settlement delay、freeze / allowlist、issuer / custodian credit、reserve attestation、法的移転可能性、exit、SP / redemption / settlement capacity を検証する |
| 7 `dJGB` | tokenized JGB を候補とし、duration 上限3か月、NAV / oracle、金利 stress、償還 calendar、移転制限に加えて settlement delay、issuer / custodian credit、SP / redemption / settlement capacity を検証する |

## 2. Preflight Evidence

Activation PR / governance proposal には少なくとも次を添付する。

1. Collateral Parameter Policy §2.4に基づくgo/no-go検証memo（確定資産のstressが [Parameters.md](../../../Parameters.md) のDay1 immutable値に収まることの確認。収まらなければactivation不可）。
2. 確定 token の `decimals()` / `symbol()` / `name()` / implementation / proxy admin の RPC evidence。
3. feed の `latestRoundData()`、decimals、heartbeat / staleness 根拠、`secondsToStale`。
4. `dToken.totalSupply == 0`、`cap == 0`、`underlying == 0`。
5. `vault.underlying == 0`、`bufferBalance == 0`、`backstopBalance == 0`、strategy count / config。
6. `PriceFeedProxy` current source が placeholder で、owner が expected holder。
7. fork dry-run で activation calls を同じ fork state に順序実行した log。
8. user app / admin / ops の branch 表示が activation 前後で意図どおり変わる screenshot または component/e2e evidence。

## 3. Execution Order

各 branch ごとに、以下の順序を崩さない。

1. Keep cap closed:
   - Confirm `dToken.cap() == 0`.
   - If not zero, queue `dToken.setCap(0)` first and wait until confirmed.
2. Allowlist intended Underlying:
   - `dToken.setAllowedUnderlying(underlying, true)`.
   - Do not allowlist multiple alternatives in the same proposal unless one will be removed before binding.
3. Bind dToken first:
   - `dToken.setTokenInfo(name, symbol, underlying)`.
   - Requires `totalSupply() == 0` and `allowedUnderlying[underlying] == true`.
4. Bind Vault second:
   - `vault.setUnderlying(underlying)`.
   - This must observe `dToken.underlying() == underlying`; otherwise it reverts with `UnderlyingMismatch`.
5. Deploy and smoke-test real price feed:
   - Verify feed code, constructor args, source addresses, staleness, decimals, and sample price.
6. Queue source replacement:
   - `priceFeedProxy.proposeSource(realFeed)`.
   - Wait the required timelock.
7. Confirm source replacement:
   - Placeholder `(1e18, false)` to real feed normally exceeds the price-difference guard, so use the emergency confirmation path only with pre-approved evidence and private submission policy.
   - Keep cap at 0 during and after this step until post-confirm smoke tests pass.
8. Configure Vault operations:
   - Set buffer target/floor, withdraw delay, allocator cooldown/max move, strategy whitelist/config if applicable.
   - If no Strategy is approved, leave strategy count/config empty and `allocateMaxMove = 0`.
9. Frontend / ops release:
   - Update generated deployment/app env and branch metadata.
   - User app can show the branch only after Underlying, source, and cap release are all confirmed.
   - 同じ資産クラスの branch が複数 active になる場合は、一方を推奨または初期選択せず並列表示する。
10. Open cap:
    - Convert the approved USD nominal exposure to dToken 18-dec token units using the final launch price and decimals.
    - Execute `dToken.setCap(N)`.
    - Record tx hash, cap units, nominal reference price, and reviewer sign-off.

## 4. Post-Activation Checks

After `setCap(N)`, verify:

| Check | Expected |
| --- | --- |
| `dToken.underlying()` | exact intended token |
| `vault.underlying()` | same token |
| `dToken.cap()` | approved nonzero token-unit cap |
| `PriceFeedProxy.fetchPrice()` | non-placeholder price and `oracleFailure == false` |
| `backingRatio()` | `1e18` before deposits |
| user app branch state | active and uses real token copy, not TBD / placeholder |
| admin/ops branch state | source, cap, roles, strategy config visible |
| liquidation tooling | branch included only after price and Trove reads are healthy |

## 5. Failure Handling

| Failure point | Handling |
| --- | --- |
| Confirmed-asset stress does not fit Day-1 immutable values | Stop activation. Params cannot be edited in place; the only path is a full system redeploy (a migration) or keeping the branch inert (no branch-level swap; see Collateral Parameter Policy §2.4). Do not compensate with dToken cap only |
| Wrong Underlying allowlisted before binding | Remove allowlist entry if possible, re-run preflight, and restart proposal |
| Wrong `setTokenInfo` executed | Stop. The branch is not safely recoverable in-place because Underlying binding is one-shot |
| `vault.setUnderlying` reverts | Do not retry blindly. Confirm dToken-first state and token address equality |
| Price feed smoke test fails | Keep cap at 0, do not confirm source or open deposits |
| Source confirmed but post-confirm checks fail | Keep cap at 0, pause user/app activation, queue source remediation |
| Cap opened with wrong units | Immediately Guardian-pause deposits where available, queue corrected cap / incident response, and assess whether any deposits occurred |

## 6. Non-Goals

- This runbook does not add new core branches or change immutable Liquity branch parameters.
- This runbook does not approve a specific Branch 2–7 Underlying, Strategy, PriceFeed, cap, or SP seed.
- This runbook does not define new frontend copy beyond the rule that activation must not expose TBD / placeholder branches as usable collateral.
