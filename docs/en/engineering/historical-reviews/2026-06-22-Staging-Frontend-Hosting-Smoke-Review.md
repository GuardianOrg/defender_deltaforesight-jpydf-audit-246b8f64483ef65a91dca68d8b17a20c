# Staging Frontend Hosting Smoke Review

## 1. Scope

The targets are the static-sites stack in `infra/cdk`, the user app in `frontend/app`, and the
read-only ops dashboard / public stats publish path in `frontend/ops`. The goal is to build the
foundation of staging hosting on AWS and confirm that no local Anvil manifest or mock stats are
loaded onto the public frontend.

Sources of truth referenced:

- `documents/jp/Product-Overview.md`: Day-1 is a single chain, Ethereum mainnet.
- `documents/jp/development/runbooks/Frontend-Production-Delivery-Gate.md`: the public
  frontend fails closed on runtime config / stats / RPC failure.
- `documents/jp/development/runbooks/AWS-CDK-IAM-Evidence-Gate.md`: the IAM evidence gate for
  S3 / CloudFront / KMS / the stats publisher.

## 2. AWS Staging State

`Jpydf-staging-StaticSites` has been bootstrapped / deployed to `ap-northeast-1`.
The post-deploy `cdk diff` shows no differences.

| Output | Value |
| --- | --- |
| User app URL | `https://d2b8eew4spddv3.cloudfront.net` |
| User app distribution | `E2UR868ZDXPXWS` |
| Ops URL | `https://d1ace8udcuxip3.cloudfront.net` |
| Ops distribution | `E6X0JEM9VWI8R` |
| Stats URL | `https://d2a7tsl4ibbvkb.cloudfront.net` |
| Stats distribution | `E2EW2RNKJTPSE3` |

Note: at this point the frontend/static stats assets have not been uploaded to S3. This is because the current
`frontend/df-shared/generated/addresses.ts` and the app env point at local Anvil
(`chainId=31337`, localhost RPC), and publishing while there is no corresponding contract
manifest on Ethereum mainnet would create a misleading entry point.

## 3. Local Runtime Verification

| Surface | URL | Result |
| --- | --- | --- |
| user app | `http://127.0.0.1:3000/` | HTTP 200 |
| ops dashboard | `http://localhost:3002/` | HTTP 200 |

Playwright screenshot smoke:

- The desktop / mobile user app renders as the local JPYdf dashboard. No BOLD display, mock
  yield opportunity, or external strategy link appeared within the reviewed scope.
- On the mobile user app, the header / wallet / card layout wraps, with no overlap of key information.
- The ops dashboard renders the read-only dashboard and alert list on both desktop / mobile.
  The local build shows the localhost RPC, but the public hosting guard blocks upload of this configuration.

## 4. Publish Guard Result

Guards added:

- `pnpm -C frontend/app check:hosting-env`
- `pnpm -C frontend/ops check:hosting-env`

Expected results under the current local env:

- user app: fails on `no-local-chain`, `no-local-rpc`, `no-local-flavor`.
- ops dashboard: fails on `no-local-chain`, `no-local-rpc`.

This is an intended stop, and is treated as a negative config drill to keep local Anvil artifacts from being
published to CloudFront. Public upload will not be performed until the following are in place.

- The deployment manifest for Ethereum mainnet / a staging public chain.
- Updated chainId / contract address / RPC URL in the `frontend/df-shared` generated bindings.
- Public stats JSON being generatable from a real RPC.
- The user app's `NEXT_PUBLIC_PROTOCOL_STATS_URL` pointing at the deployed stats object.

## 5. Fixes Added

- `frontend/app`: pinned `outputFileTracingRoot` / `turbopack.root` to the repo root to suppress the
  Next workspace root warning.
- `frontend/app`: added a public hosting env guard.
- `frontend/ops`: added a public ops hosting env guard.
- `frontend/ops`: made the S3 publisher able to read the static shared credentials from `AWS_PROFILE`.
- `frontend/ops`: redact the full URL / key fragment from RPC / provider error logs.
- `frontend/ops`: lowered the default RPC batch size to 25, adjustable via `OPS_RPC_BATCH_SIZE`.
- `infra/cdk`: added the CloudFront distribution ID / domain / URL to the stack output.

## 6. Residual Risks / Next Gates

- The CDK bootstrap currently uses the default execution policy. The GitHub Actions OIDC
  deploy role and a least-privilege deploy boundary are not yet implemented.
- The public app / ops buckets remain empty. They will not be uploaded until a mainnet-ready manifest exists.
- Public stats generation is possible with the local Anvil manifest, but on the mainnet RPC there is no
  code at the current generated contract address and it fails. Do not overwrite with mock stats.
- Admin console hosting, ALB auth, the ECS scheduled stats worker, WAF / Route 53 / ACM, and the
  synthetic monitor are separate gates.

## 7. Commands

```sh
AWS_PROFILE=jpydf-staging pnpm -C infra/cdk exec cdk deploy Jpydf-staging-StaticSites
AWS_PROFILE=jpydf-staging pnpm -C infra/cdk exec cdk diff Jpydf-staging-StaticSites
curl -I http://127.0.0.1:3000/
curl -I http://localhost:3002/
pnpm -C frontend/app check:hosting-env
pnpm -C frontend/ops check:hosting-env
```
