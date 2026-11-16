# Local Setup & Verification Guide

> **Purpose**: enable a third party to start the full jpydf-v2 stack (blue Liquity v2 core + green dToken/Strategy/Oracle/Zapper contracts + subgraph + three frontend surfaces) from a clean checkout on a **local anvil chain without mainnet**, then verify the browser surfaces.
>
> The **specification source of truth is [`../../protocol/product/spec/`](../../protocol/product/spec/)** plus the entry points [`../../protocol/product/Product-Overview.md`](../../protocol/product/Product-Overview.md) / [`../../Parameters.md`](../../Parameters.md). This document is only a runbook; it does not restate architecture or parameters.
>
> The full procedure was executed on `develop` tip `9f2d6016` (2026-06-15). Core and frontend code can start without local patches.

---

## 0. Reference Environment

| Tool | Version | Purpose |
| --- | --- | --- |
| Foundry (`forge` / `anvil` / `cast`) | 1.7.1 | contract deploy and local chain |
| Node.js | **22.x** (contracts/frontend) + **20.18.1** (graph-cli only) | runtime |
| pnpm | 8+ (confirmed on 10.x) | monorepo package management |
| Docker | 28.x | graph-node / postgres / ipfs |
| graph-cli | 0.97.x (on Node 20) | subgraph codegen / deploy |

> Use two Node versions. The contracts/frontend work on Node 22, but `graph-cli` requires Node >= 20.18.1. Install both with [nvm](https://github.com/nvm-sh/nvm) and use `nvm use 20.18.1` only for subgraph operations.

Commands below refer to the repository root as `$REPO` (for example, `export REPO=~/work/jpydf-v2`). The Foundry root is `$REPO/contracts`.

---

## 1. Clone and Install Dependencies

```bash
# Fetch submodules (forge-std / OpenZeppelin / Solady / V2-gov) at clone time.
git clone --recurse-submodules https://github.com/deltaforesight/jpydf-v2 "$REPO"
cd "$REPO"
git checkout develop          # or the branch/tag under review

# Install all monorepo workspaces from the repository root.
pnpm install
```

- If submodules are empty, run `git submodule update --init --recursive`.
- If `corepack` fails with a signing-key error, use `npx -y pnpm@8.15.8 install` instead. pnpm 10 works when available.

---

## 2. Local Chain (anvil)

Run this in a separate terminal:

```bash
~/.foundry/bin/anvil --host 127.0.0.1 --port 8545 --chain-id 31337 --base-fee 0 --gas-limit 60000000
```

Use anvil account #0 for the deployer and demo actions:

- address `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
- private key `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

---

## 3. Deploy Contracts (8 Branches)

```bash
cd "$REPO/contracts"
PATH=~/.foundry/bin:$PATH ./deploy local --skip-confirmation
```

- The `local` preset sets chain-id 31337, deployer = anvil #0, and RPC = `http://127.0.0.1:8545`.
- Eight branches are deployed. Only dwstETH / dUSDC are actively wired; dETH / dUSD-A / dBTC / dUSD-B / dJPY / dJGB are inert. `Deployment complete.` means success.
- The demo trove path has been removed from `./deploy`. Demo data is seeded by `SeedLocalDemo` below.
- Without a fixed salt, deployment uses `block.timestamp` as salt and contract addresses change on every deploy. After redeploying, regenerate frontend env in §6. Use `--salt <string>` if addresses should be stable.
- Outputs: `contracts/deployment-manifest.json` for frontend env, and `contracts/deployment-context-latest.json` for subgraph JpydfToken lookup.

---

## 4. Inject Multicall3

The frontend expects Multicall3 at `0xcA11bde05977b3631167028862bE2a173976CA11`, but local deploy does not include it. Copy mainnet bytecode into anvil:

```bash
MC=0xcA11bde05977b3631167028862bE2a173976CA11
CODE=$(~/.foundry/bin/cast code $MC --rpc-url https://eth.llamarpc.com)
~/.foundry/bin/cast rpc anvil_setCode $MC "$CODE" --rpc-url http://127.0.0.1:8545

# Confirm non-empty bytecode.
~/.foundry/bin/cast code $MC --rpc-url http://127.0.0.1:8545 | head -c 20; echo
```

---

## 5. Seed Demo Data

Create demo Troves, Stability Pool deposits, Strategy allocation, and delayed withdrawal requests for the two active branches:

```bash
cd "$REPO/contracts"
DEPLOYER=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  PATH=~/.foundry/bin:$PATH \
  forge script SeedLocalDemo --rpc-url http://127.0.0.1:8545 --broadcast
```

- The script accounts for MIN_DEBT 300k and 0.0375 ETH gas compensation. `Seed complete.` means success.
- Demo prices are also set by this script; no separate `setPrice` is required.

---

## 6. Generate Frontend Env (`.env.local` + Bindings)

The frontend has two consumers: **app (Next.js)** and **console/ops (Vite)**. Generate both from the deployment manifest.

### 6-1. app `.env.local`

The env generator emits only contract addresses. Chain configuration (RPC / Multicall / WalletConnect / Subgraph URL / feature flags) must be prepended manually:

```bash
cd "$REPO"
cat > frontend/app/.env.local <<'EOF'
NEXT_PUBLIC_ACCOUNT_SCREEN=true
NEXT_PUBLIC_DEPLOYMENT_FLAVOR=Local
NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID=local-dev
NEXT_PUBLIC_CHAIN_BLOCK_EXPLORER=Anvil|http://127.0.0.1:8545
NEXT_PUBLIC_CHAIN_CURRENCY=Ether|ETH|18
NEXT_PUBLIC_CHAIN_ID=31337
NEXT_PUBLIC_CHAIN_NAME=Anvil
NEXT_PUBLIC_CHAIN_RPC_URL=http://127.0.0.1:8545
NEXT_PUBLIC_CHAIN_CONTRACT_MULTICALL=0xcA11bde05977b3631167028862bE2a173976CA11
NEXT_PUBLIC_AIRDROP_VAULTS=false
NEXT_PUBLIC_SAFETY_MODE_CHECK=false
NEXT_PUBLIC_SUBGRAPH_CHECK=false
NEXT_PUBLIC_SUBGRAPH_URL=http://localhost:8000/subgraphs/name/jpydf/jpydf
NEXT_PUBLIC_MULTIPLY_SCREEN=false
NEXT_PUBLIC_DEV_WALLET=true
NEXT_PUBLIC_SAFE_API_URL=
NEXT_PUBLIC_SHOW_DATA_SOURCES=true
EOF

cd "$REPO/contracts"
pnpm tsx utils/deployment-manifest-to-app-env.ts deployment-manifest.json >> ../frontend/app/.env.local
```

- `NEXT_PUBLIC_DEV_WALLET=true` lets the browser connect to the anvil account directly. WalletConnect is not needed; `local-dev` is a dummy ID.
- `NEXT_PUBLIC_SUBGRAPH_URL` must be `.../name/jpydf/jpydf`. Shorter or stale `liquity2/version/latest` forms do not resolve in graph-node.
- The generator writes `Skipping inert branch ...` to stderr for inert branches 5/6/7. That is expected.

### 6-2. console / ops bindings

```bash
cd "$REPO/contracts"
pnpm tsx ../frontend/df-shared/generate.ts
```

- Run this from `contracts/`. Running from the repository root can fail with `ERR_PNPM_RECURSIVE_EXEC_FIRST_FAIL: Command "tsx" not found` because root does not have `tsx`.
- Success generates `frontend/df-shared/generated/{addresses,abis}.ts` for all eight branches.

---

## 7. Start and Deploy the Subgraph

Use Node 20.18.1 for graph-cli:

```bash
nvm use 20.18.1
cd "$REPO/subgraph"

# Start graph-node. --reset clears old volumes and avoids genesis mismatch.
./start-graph --reset

# Required before deploy; otherwise AssemblyScript parse errors can occur.
pnpm graph codegen

# Create and deploy.
printf 'y\n' | ./deploy-subgraph local --create --version v1
```

- `./start-graph --reset` is long-running. Use a separate terminal, or background it with `./start-graph --reset > /tmp/graph.log 2>&1 &`.
- When a new JpydfToken is detected, `deploy-subgraph` asks `Update networks.json? [Y/n]`; the `printf` above answers `y`.
- Sync check:

```bash
curl -s -X POST http://localhost:8000/subgraphs/name/jpydf/jpydf \
  -H 'Content-Type: application/json' \
  -d '{"query":"{_meta{block{number}hasIndexingErrors}}"}'
```

Expected shape: `{"data":{"_meta":{"block":{"number":<anvil block>},"hasIndexingErrors":false}}}`.

---

## 8. Start the Frontend Surfaces

Switch back to Node 22 (`nvm use 22`) and run:

```bash
# app (Next.js, :3000). on a local URL, build-deps falls back to the in-repo schema.
cd "$REPO/frontend/app"
pnpm build-deps          # graphql codegen -> uikit build -> panda. runtime data requires the subgraph to sync
pnpm dev

# Admin console (Vite, :3001), in another terminal.
cd "$REPO/frontend/console" && pnpm dev

# Ops dashboard (Vite, :3002), in another terminal.
cd "$REPO/frontend/ops" && pnpm dev
```

- When `NEXT_PUBLIC_SUBGRAPH_URL` is `localhost` / `127.0.0.1` / `[::1]`, `build-graphql` automatically uses the in-repo schema if `../../subgraph/schema.graphql` exists. This lets `build-deps` complete even when the subgraph is not running.
- To use remote-subgraph live introspection, that URL must be reachable at codegen time. To validate just the consistency against the in-repo schema in a separate output, run `SUBGRAPH_SCHEMA_FILE=../../subgraph/schema.graphql GRAPHQL_CODEGEN_OUT=/tmp/jpydf-app-graphql-codegen/ pnpm build-graphql`. This is validation-only and does not replace the runtime `NEXT_PUBLIC_SUBGRAPH_URL`.
- console / ops read the generated `df-shared` bindings directly and do not need `build-deps`.

---

## 9. Access and Verification Checklist

| Surface | URL | Expected display |
| --- | --- | --- |
| **app** (user) | http://localhost:3000 | Borrow table with only the Day-1 public active dwstETH/dUSDC branches, JPY prices, JPYdf approximately ¥1.00, and anvil #0 connected in the header |
| **Admin Console** | http://localhost:3001 | `chainId 31337 · block N`, signer roles (GOV / ALLOCATOR / GUARDIAN / WRITEOFF / Oracle owner / DToken owner), Vault backingRatio 100% |
| **Ops Dashboard** | http://localhost:3002 | "All systems normal", active 2 / inert 6 branch state, branch price/TCR/SP, Vault/Strategy, and real transaction history (read-only) |

Reference active-branch demo prices after `SeedLocalDemo`: dwstETH ¥600,000 / dUSDC ¥150 (JPY/USD around 150).

RPC log check: if the browser console shows CORS errors for an unconfigured public RPC such as `eth.merkle.io`, verify that the local stack RPC URL is pinned to `http://127.0.0.1:8545` and that no stale wallet or data-source override is active.

---

## 10. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| remote/live-introspection `build-deps` fails with `ECONNREFUSED ::1:8000` | `NEXT_PUBLIC_SUBGRAPH_URL` is a local URL but `../../subgraph/schema.graphql` is not found, or the remote URL is unreachable. For local, confirm the in-repo schema exists; for remote, ensure subgraph reachability or use the `SUBGRAPH_SCHEMA_FILE` validation command. |
| `deploy-subgraph` fails with AssemblyScript parse errors | `pnpm graph codegen` was not run first. |
| `ERR_PNPM_RECURSIVE_EXEC_FIRST_FAIL: Command "tsx" not found` | `df-shared/generate.ts` was run from repo root. Run `pnpm tsx ../frontend/df-shared/generate.ts` from `contracts/`. |
| graph-cli reports a Node version error | Use Node 20.18.1 (`nvm use 20.18.1`). |
| `graph-node` exits with code 137 (OOM) | Restart with `./start-graph --reset` and check Docker memory allocation. |
| Frontend addresses are stale / balances are zero | Redeploy changed salts and addresses. Regenerate §6 env and redeploy the subgraph in §7(c). |
| Earn or some screens show subgraph errors | Subgraph is not synced. Wait until `_meta.block` catches up with anvil. |

---

## 11. Stop and Clean Up

```bash
# Foreground processes: Ctrl-C. Background helpers:
pkill -f 'next dev'; pkill -f 'vite'; pkill -f 'anvil .*--port 8545'

# graph-node stack, from subgraph/
cd "$REPO/subgraph" && docker compose down
```

---

## Appendix A. Startup Order

```text
start anvil
  -> ./deploy local --skip-confirmation        (generate manifest)
       -> inject Multicall3 (anvil_setCode)
            -> forge script SeedLocalDemo      (demo data + prices)
                 -> generate .env.local + df-shared bindings
                      -> subgraph: start-graph(--reset) -> codegen -> deploy-subgraph
                           -> frontend: build-deps -> dev (app / console / ops)
```

The two important ordering constraints are: **(1) Multicall3 and Seed happen after deploy**, and **(2) the app's runtime-data check happens after the subgraph syncs**. With a local URL, `build-deps` can run even without Graph Node thanks to the in-repo schema fallback. The `SUBGRAPH_SCHEMA_FILE` Codegen check is validation-only and does not replace the runtime URL.

## Appendix B. `.env.local` Header

The same block is included in §6-1. Address lines (`NEXT_PUBLIC_*_CONTRACT_*` / `NEXT_PUBLIC_COLL_*`) are appended by `deployment-manifest-to-app-env.ts`; do not hand-write them.

---

## Verification Record

- 2026-06-15: executed the full procedure on `develop` tip `9f2d6016`, and confirmed app (:3000), console (:3001), and ops (:3002) render correctly.
