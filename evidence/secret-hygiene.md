# Secret Hygiene Review

Status: initial package review.

## Excluded From This Package

- Populated env files such as `contracts/.env` and `frontend/app/.env.local`.
- Generated deployment context / manifest files unless explicitly sanitized.
- Build and generated output directories such as `contracts/out`,
  `contracts/cache`, `contracts/broadcast`, frontend `.next`, and CDK
  `cdk.out`.
- Dated review snapshots under `documents/*/development/reviews`.

## Included Templates

- Non-secret evidence templates under `evidence/templates`

## Known Private-Key-Shaped Test Fixtures

This handoff repository includes a curated Solidity source snapshot, but it
does not include vendored dependency trees or local demo scripts with
private-key-shaped literals. In particular,
`contracts/script/SeedLocalDemo.s.sol` is excluded from the snapshot because it
contains a public Anvil test private key.

The copied test snapshot intentionally includes
`contracts/test/TestContracts/Accounts.sol`, which labels the first ten Hardhat
test account private keys. These are public deterministic test fixtures used by
the test suite, not operator secrets.

Certora specs in `source-snapshot/contracts/certora/` are copied with generated
external report `anonymousKey` query strings removed from comments.

A fresh source checkout may contain public Anvil / Foundry fixtures or 32-byte
test constants; treat those as source-review context only. Do not copy new
private-key-shaped literals into this handoff repository unless they have been
scanned and intentionally allowlisted.

## Redaction Rules For Future Evidence

Redact assignment values for keys matching:

- `*_PRIVATE_KEY`
- `*MNEMONIC*`
- `*SECRET*`
- `*_TOKEN`
- `*_API_KEY`
- `*_ACCESS_KEY`
- `*_PASSWORD`
- `*_WEBHOOK*`
- `*_DATABASE_URL`
- `*_RPC_URL`
- `FORK_URL`
- `MAINNET_RPC_URL`
- `ETHERSCAN_API_KEY`
- `DRPC_*`
- `ALCHEMY_*`
- `INFURA_*`

Frontend public-but-sensitive values should also be placeholdered unless the
audit scope intentionally includes an exact public deployment:

- `NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID`
- `NEXT_PUBLIC_CHAIN_RPC_URL`
- `NEXT_PUBLIC_SUBGRAPH_URL`
- `NEXT_PUBLIC_PROTOCOL_STATS_URL`
- `NEXT_PUBLIC_REFERRAL_REGISTRY_URL`
- `NEXT_PUBLIC_KNOWN_DELEGATES_URL`
- `NEXT_PUBLIC_SITE_URL`

For JSON manifests, drop or redact `options.rpcUrl` and any field named
`rpcUrl`, `forkUrl`, `mainnetRpcUrl`, `secretArn`, `roleArn`, or `kmsKeyArn`.
Keep contract addresses only when they are official audit deployment evidence.
