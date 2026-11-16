# JPY DeFi Day-1 Liquidity / Route Policy

> **Positioning**: design memo that fixes the boundary for Day-1 JPYdf DEX liquidity, Zapper swap routes, frontend gates, and liquidity scripts. Collateral branch support is governed by [`Parameters.md`](../../../Parameters.md), Zapper contract requirements by [`Zapper.md`](../spec/Zapper.md), frontend gates by [`Frontend.md`](../spec/Frontend.md), and deploy configuration by [`Deployment-Configuration-Spec.md`](../../../engineering/guides/Deployment-Configuration-Spec.md).

---

## 1. Decision

Day-1 JPYdf liquidity is limited to **one JPYdf/USDC pair**.

- The standard venue is **Uniswap v4**.
- Liquidity broadcast happens only after the JPYdf token is deployed / issued. The pool-key token ordering is determined by the actual JPYdf / USDC addresses under Uniswap v4 rules and is fixed in evidence.
- Curve routes / adapters / liquidity scripts are out of Day-1 scope and are not adopted.
- Balancer is out of Day-1 scope and is not part of future route assumptions.
- The Uniswap v4 route is frozen as route config covering Universal Router / Permit2 / pool key / hook policy, and is not wired into production Zapper until fork/integration evidence is complete.
- `UniV4Exchange` is included in Day-1 audit scope for the JPYdf/USDC v4 final leg. This does not reintroduce swap-backed close, collateral-funded repay, or Multiply into the Day-1 ABI.
- Uniswap v3 routes / adapters are out of Day-1 scope and are not kept in the current contract tree.
- No direct JPYdf pools are created for USDT / sUSDS / WETH / XAUT / dToken.
- Reserving inert branches is separate from activating them as borrowable collateral or JPYdf liquidity pairs.

---

## 2. Scope Boundary

| Target | Day-1 policy |
| --- | --- |
| Collateral support | Deploy all 8 branches (`NUM_DF_ACTIVE_BRANCHES = 2`). Only dwstETH / dUSDC are active; Branches 2–7 are unbound, cap-0 inert branches |
| JPYdf liquidity | Only the JPYdf/USDC Uniswap v4 pool. Liquidity is added after JPYdf deploy / issuance |
| `UniV4Exchange` / `IExchange` adapter | Included in Day-1 audit scope. It is not wired into a user-facing Zapper until route config / fork evidence / manifest gates are complete |
| PIL / liquidity incentives | Designed around allocation to the JPYdf/USDC pool. The PIL recipient is frozen in a separate runbook |
| Zapper open / add / withdraw / close-with-JPYdf | Does not use JPYdf swaps and therefore does not depend on JPYdf/USDC liquidity |
| Collateral-funded repay / flash-close / Multiply | Not present in the Day-1 contract ABI. `UniV4Exchange` is included in Day-1 audit scope, but these future flows still require a new audited entrypoint with route config and fork evidence, without depending on Balancer or the removed Flash Loan callback |
| Non-USDC collateral reverse route | Do not create additional JPYdf pools. Add an Underlying -> USDC -> JPYdf adapter and evidence only if needed |

### 2.1 Implementation absorption / launch gates

Branches 2–7 remain inert and closed through an unbound Underlying, placeholder PriceFeed, cap/allocation 0, no Strategy or Zapper, and frontend gates.

- A cap-0 dToken cannot mint through `CollateralVault.deposit`; launch evidence checks cap and supply at zero.
- `allocateMaxMove = 0` prevents outbound Strategy allocation. Branches with no venue use `strategyKind=none`, weight 0, cap 0, and no registered Strategy.
- Freeze cap/allocation/Strategy at zero and use placeholder feeds with no Zapper for Branches 2–7.
- The user app treats only dwstETH and dUSDC as borrowable, based on both production config and on-chain state.

---

## 3. Zapper / Route Rules

1. Production open / add / withdraw / close-with-JPYdf through `CollateralYieldZapper` completes with only Underlying and dToken conversion, and does not require a DEX route.
2. Flash-close / collateral-funded repay / Multiply must not be submitted because they are absent from the Day-1 ABI. `UniV4Exchange` itself is included in Day-1 audit scope, but future user-facing flows still require a new audited entrypoint without depending on Balancer or the removed Flash Loan callback.
3. The only JPYdf swap leg treated as production-reviewed on Day-1 is JPYdf/USDC Uniswap v4. No direct routes are created from USDT / sUSDS / WETH / XAUT to JPYdf.
4. Even if a future inert-branch entry UX is centered on USDC, its JPYdf leg ultimately consolidates into JPYdf/USDC. Any asset-specific pre-leg or reverse adapter belongs to the activation audit.
5. The default Uniswap v4 route is a no-hook pool. If a hook route is allowed, hook allowlist, pool key, Universal Router / Permit2 addresses, allowance cleanup, and fork-run evidence must be fixed in route config before enablement.
6. Treat `UniV4Exchange` JPYdf -> collateral as an exact-output adapter: JPYdf is
   the maximum input, the specified collToken amount is the output target, and
   unused JPYdf is returned to the caller. Treat collateral -> JPYdf as an
   exact-input adapter that spends the specified collToken amount and checks the
   minimum JPYdf received.

---

## 4. Frontend Gates

- Keep `NEXT_PUBLIC_MULTIPLY_SCREEN` at the Day-1 default `false`.
- dToken-branch collateral-funded repay / flash-close / Multiply are absent from the Day-1 ABI. Even after the JPYdf/USDC final leg and any required asset-specific pre-leg are present in manifest / config / UI, submitting them requires a new audited entrypoint that does not depend on Balancer or the removed Flash Loan callback.
- Borrow / add collateral / repay with JPYdf / close with held JPYdf are treated as direct or CYZ flows that can be verified without a swap route.
- UI copy must not confuse deployed branches, active collateral, and DEX liquidity. Day-1 collateral is dwstETH / dUSDC; JPYdf DEX liquidity is USDC-only.

---

## 5. Liquidity Script Gates

Do not broadcast the production liquidity script / runbook unless all of the following are true.

- The token pair is JPYdf/USDC.
- The venue is Uniswap v4.
- JPYdf token deploy / issuance is complete, and the JPYdf amount and USDC amount for liquidity are frozen together with funding source and accounting owner.
- Evidence records USDC / JPYdf token addresses, fee, tick spacing, hook policy, pool key, position owner, and initial amounts.
- The script does not create USDT / USDS / WETH / XAUT / Curve / Balancer pools.
- Fork-run confirms pool address, token ordering, position owner, and minted liquidity.

If a legacy / rehearsal script handles WETH / wstETH / rETH pools, it is not a Day-1 JPYdf liquidity script and must not remain in the current contract tree. Production procedures should reference only scripts that match this policy.

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
```
