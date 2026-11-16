# Hosted Anvil Frontend Testing Guide (frontend verification and test-token supply on the hosted Anvil)

> **Purpose**: a runbook that makes it possible to drive the frontend already deployed (borrow, etc.) on the AWS-hosted **hosted Anvil (staging)** from a browser wallet and actually test it. In particular, it establishes the source of truth for "how to supply collateral tokens (wstETH / USDC) to test accounts."
>
> ⚠️ The source of truth for the specification is [`../../protocol/product/spec/`](../../protocol/product/spec/) / [`../../protocol/product/Product-Overview.md`](../../protocol/product/Product-Overview.md). This document covers **operating procedures only**. For starting the full stack locally (localhost anvil), see [`Local-Setup-And-Verification-Guide.md`](Local-Setup-And-Verification-Guide.md).
>
> The source of truth for endpoints and chain id is [`2026-06-22-AWS-Hosted-Anvil-Staging-Review.md`](../historical-reviews/2026-06-22-AWS-Hosted-Anvil-Staging-Review.md).

---

## 0. Premises and safety positioning (must read)

This chain is **resettable / non-value-bearing staging-only infrastructure** and is designed to have the following properties.

- **The RPC is public** (via CloudFront, CORS `*`, all JSON-RPC methods allowed). Anyone can send transactions and change state.
- **Minting is open.** The collateral tokens are mock faucets, and their `owner` (= the account that ran the deploy) holds the `mint()` authority. The owner of the current deployment is **anvil default account #0** (the address derived from Foundry's public default key), and anyone can confirm it with `cast call <token> "owner()"`. In other words, **third parties can mint arbitrarily as well**.
- All keys used in this document are **anvil/Foundry public default keys** and are **not secrets** (they are printed every time `anvil` starts; they can be derived from the mnemonic below).

In conclusion:

- **Do not place anything of value on this chain.** It is for testing only.
- Test on the premise that **state can change on its own** through others' minting and trove creation.
- If you want to close off minting, see §6 (do not hide the keys; redeploy with a private deployer).

---

## 1. Environment (current staging)

| Item | Value |
| --- | --- |
| User app | `https://d2b8eew4spddv3.cloudfront.net` |
| RPC (shared by browser / cast) | `https://d1idjvopviksk7.cloudfront.net` |
| Ops dashboard | `https://d1ace8udcuxip3.cloudfront.net` |
| Public stats | `https://d2a7tsl4ibbvkb.cloudfront.net/jpydf-stats.json` |
| Chain id | **31338** (`0x7a6a`) |
| Composition | `anvil --accounts 20 --balance 1000000 --block-time 2` on ECS Fargate (not a mainnet fork, **in-memory**) |

> Direct ALB access is not possible (403). Always use the CloudFront URL above for the RPC.

## 2. Accounts (anvil defaults)

| Use | index | Address |
| --- | --- | --- |
| faucet owner (for mint) | #0 | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` |
| For testing | #1 | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` |

- Because the hosted Anvil does not specify `--mnemonic`, it uses the **anvil / Foundry standard default accounts** as-is (#0 is the faucet owner).
- **For secret protection, the values of keys and mnemonics are not recorded in this document**. The default keys are shown with the same accounts / private keys if you start `anvil` locally once (Foundry's public defaults). Pass any keys you obtain via environment variables or the foundry keystore (`cast wallet import`); do not leave them in files or chat.
- Confirming the owner: `cast call <token> "owner()(address)" --rpc-url $RPC` (returns the #0 address).

## 3. Collateral tokens (chain 31338)

In borrow, **what you deposit is the underlying token**. The dToken is auto-minted by the Vault, so the user does not touch it directly.

| Branch | Underlying deposited | dec | tap open? |
| --- | --- | ---: | --- |
| dwstETH | wstETH | 18 | 100/day |
| dUSDC | USDC | 6 | **disabled (owner mint only)** |
| dETH / dUSD-A / dBTC / dUSD-B / dJPY / dJGB | TBD | — | inert; no faucet |

This document does not hardcode contract addresses. The source of truth is the current devnet bindings `frontend/df-shared/generated/addresses.ts` (chainId 31338), which are regenerated and change on every redeploy.

> **How to re-derive addresses if they change (e.g. after a redeploy)**: with the same deployer + salt, CREATE2 keeps the address unchanged. If they do change, regenerate `frontend/df-shared/generated/addresses.ts`, or gather candidate addresses from `deployment-manifest.json` (`.dfYield[i].underlying`), then send `cast call <addr> "symbol()(string)"` to each to identify wstETH/USDC (also confirm the owner with `owner()`).

## 4. Supplying test tokens

```bash
RPC=https://d1idjvopviksk7.cloudfront.net
ME=0x70997970C51812dc3A010C7d01b50e0d17dc79C8

# Do not put key values in this document. Each person sets the anvil default #0(owner)/#1 keys in their own environment
# (starting `anvil` locally once prints the same default keys):
#   export OWNER_KEY=<private key of anvil default #0>
#   export ME_KEY=<private key of anvil default #1>

# Token addresses change on every redeploy, so this document does not hardcode them.
# Take the branch 0 / branch 1 underlying (wstETH / USDC) addresses from the current
# devnet bindings frontend/df-shared/generated/addresses.ts (chainId 31338) and set them:
#   export WSTETH=<wstETH address from the bindings>
#   export USDC=<USDC address from the bindings>
```

**A. Mint an arbitrary amount as owner (recommended; required for USDC)** — amounts are in the smallest unit (USDC=6dec, wstETH=18dec):

```bash
cast send $USDC   "mint(address,uint256)" $ME 5000000000000            --rpc-url $RPC --private-key $OWNER_KEY  # 5,000,000 USDC
cast send $WSTETH "mint(address,uint256)" $ME 10000000000000000000000  --rpc-url $RPC --private-key $OWNER_KEY  # 10,000 wstETH
```

**B. Public tap (no owner needed; for small amounts)** — has a cooldown, USDC is disabled:

```bash
cast send $WSTETH "tap()" --rpc-url $RPC --private-key $ME_KEY    # +100 wstETH (once/day)
```

**Checking balance**:

```bash
cast call $USDC "balanceOf(address)(uint256)" $ME --rpc-url $RPC
```

## 5. Connect a wallet and test on the frontend

1. Add the network to the wallet (MetaMask, etc.): **RPC `https://d1idjvopviksk7.cloudfront.net` / Chain ID `31338` / currency ETH**.
2. **Import the private key of account #1** (§2: anvil default #1; obtain the key value in your own environment). Each account holds 1,000,000 ETH.
3. App → **Borrow** → pick a collateral and deposit.
   - Minimum borrow amount **MIN_DEBT = 300,000 JPYdf**.
   - Opening a trove requires **WETH gas compensation worth ~0.0375 ETH** (satisfied if you hold WETH; in some cases the Zapper wraps ETH).
   - Demo price guideline: 1 ETH ≈ 600,000 JPY / 1 USD ≈ 150 JPY.

The automated `check:staging-wallet-tx` command connects through an injected EIP-1193 provider and confirms a
small self-transfer receipt. Its default transfer value is derived from the execution time in milliseconds so that
reusing a nonce after snapshot/revert does not collide with a transaction hash from an earlier run. Set
`STAGING_WALLET_TX_SEND_VALUE_WEI` or `--send-value-wei` only when a reproducible fixed value is required.

The hosted-wallet verification set also includes:

```bash
pnpm -C frontend/ops check:staging-wallet-open-borrow
pnpm -C frontend/ops check:staging-wallet-open-borrow-oracle-failure
pnpm -C frontend/ops check:staging-wallet-open-borrow-rpc-failure
pnpm -C frontend/ops check:staging-user-personas
```

`check:staging-wallet-open-borrow` injects an `openBorrowPosition` flow into the app's `/transactions` screen, verifies review/step preparation and `openTrove` confirmation, and creates an `evm_snapshot` immediately before sending. Unless `--keep-state` is explicitly selected for a full integration run, it reverts the snapshot on both success and failure.

The oracle-failure variant injects a JSON-RPC error only for the selected branch's `PriceFeedProxy.source()` read. The review must show `Status unavailable`, disable the primary action, and create neither `eth_sendTransaction` nor a transaction artifact. The RPC-failure variant instead fails only the health probe's `eth_blockNumber`; global RPC health must become unavailable with the same no-send result. Injection is confined to the CDP session and does not mutate hosted Anvil or the public bundle. Do not combine both fault modes or expose endpoints, request bodies, or presigned URLs in evidence.

Before publishing the Admin console, the staging environment must set `VITE_CONSOLE_TIMELOCK_ADDRESS` and `VITE_CONSOLE_TIMELOCK_FROM_BLOCK`, where the latter is the positive CREATE-receipt block number. A direct-mode environment missing either value must fail `check:staging-hosting-env`.

## 6. When the chain is reset / when you want to lock minting

- **If state is lost**: the hosted Anvil is in-memory, so the chain is reinitialized when the Fargate task restarts. Contracts return to the same addresses via CREATE2 with the same deployer + salt, but **token balances and troves are gone**. Re-running §4 restores them.
- **If you want to close off third-party minting**: hiding the public default key is meaningless (it is a public key). **Redeploy with a private deployer key / custom mnemonic** so that the faucet's `owner()` is an address whose key only you hold. If needed, also restrict the RPC side with authentication at the level of origin-verify or above. That said, given staging's purpose (a disposable UX demo anyone can touch), leaving it open is often fine.

---

## Verification record (point-in-time snapshot)

- **2026-06-24 / chain 31338**: ran this procedure (§4 A+B) and confirmed that account #1 (`0x7099…79C8`) can be supplied with WETH 10,000 / USDC 5,000,000 / USDT 5,000,000 / sUSDS 5,000,000 / XAUT 10,000 (before all 0 → after reflected, all txs `status=0x1`). Confirmed via `owner()` that every faucet owner is #0 (`0xf39F…2266`).
