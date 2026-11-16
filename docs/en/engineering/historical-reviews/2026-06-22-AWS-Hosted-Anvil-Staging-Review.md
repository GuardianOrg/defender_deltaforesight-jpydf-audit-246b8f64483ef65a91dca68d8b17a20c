# AWS Hosted Anvil Staging Review

Date: 2026-06-22

Scope:

- CDK stack: `Jpydf-staging-HostedAnvil`
- AWS account: `692137657272`
- Region: `ap-northeast-1`
- Purpose: staging UX / deploy / reset drill RPC, not production or value-bearing
  network.

## Deployed Endpoint

| Item | Value |
| --- | --- |
| CloudFront RPC URL | `https://d1idjvopviksk7.cloudfront.net` |
| CloudFront distribution id | `ECU99VBYZMBI5` |
| Chain id | `31338` (`0x7a6a`) |
| User app URL | `https://d2b8eew4spddv3.cloudfront.net` |
| Ops dashboard URL | `https://d1ace8udcuxip3.cloudfront.net` |
| Public stats URL | `https://d2a7tsl4ibbvkb.cloudfront.net/jpydf-stats.json` |

The ALB DNS is intentionally not a supported output. Direct ALB access must not
be used by frontend or ops configs.

## Architecture Check

- Anvil runs as one ECS Fargate task behind an internet-facing ALB.
- CloudFront is the only supported browser RPC endpoint.
- The ALB listener defaults to `403`.
- Requests are forwarded to Anvil only when CloudFront adds the origin
  verification header.
- The header is a routing guard, not authentication. This chain remains
  resettable staging infrastructure only.
- Public stats are served from the static stats bucket through CloudFront OAC.
  The stable stats object must be written with the CDK stats bucket CMK. Using
  only `--sse aws:kms` can select the AWS-managed `aws/s3` key, which CloudFront
  cannot decrypt through the stack key policy.

## Verification

Commands run:

```sh
pnpm --filter @jpydf/infra-cdk build
pnpm --filter @jpydf/infra-cdk test
pnpm --filter @jpydf/infra-cdk synth
AWS_PROFILE=jpydf-staging JPYDF_HOSTED_ANVIL_ENABLED=true pnpm -C infra/cdk exec cdk synth Jpydf-staging-HostedAnvil
AWS_PROFILE=jpydf-staging JPYDF_HOSTED_ANVIL_ENABLED=true pnpm -C infra/cdk exec cdk deploy Jpydf-staging-HostedAnvil --require-approval never --outputs-file /private/tmp/jpydf-hosted-anvil-outputs.json
forge fmt --check script/DeployLiquity2.s.sol
SUBGRAPH_SCHEMA_FILE=../../subgraph/schema.graphql pnpm -C frontend/app build
pnpm -C frontend/ops build
```

Runtime probes:

```sh
curl -sS -X POST https://d1idjvopviksk7.cloudfront.net \
  -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'
```

Result:

```json
{"jsonrpc":"2.0","id":1,"result":"0x7a6a"}
```

```sh
curl -sS -X POST https://d1idjvopviksk7.cloudfront.net \
  -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":2,"method":"eth_blockNumber","params":[]}'
```

Result at probe time:

```json
{"jsonrpc":"2.0","id":2,"result":"0x44"}
```

Direct ALB negative probe returned:

```http
HTTP/1.1 403 Forbidden
```

Public stats probe after CMK re-publish:

```sh
curl -I -H 'Origin: https://d2b8eew4spddv3.cloudfront.net' \
  https://d2a7tsl4ibbvkb.cloudfront.net/jpydf-stats.json
```

Result:

- `HTTP/2 200`
- `content-type: application/json`
- `access-control-allow-origin: *`
- `x-amz-server-side-encryption: aws:kms`
- `x-amz-server-side-encryption-aws-kms-key-id`: CDK stats bucket CMK
- `x-amz-meta-block-number: 1336`

Final browser QA was run through Chrome DevTools Protocol against the deployed
CloudFront URLs.

| Surface | Viewport | Console errors | Page errors | 4xx / 5xx responses | Horizontal overflow | Key visible state |
| --- | --- | ---: | ---: | ---: | --- | --- |
| User app | 1440x900 | 0 | 0 | 0 | No | `AWS STAGING ANVIL`, branch tables, stats values |
| User app | 390x844 | 0 | 0 | 0 | No | `AWS STAGING ANVIL`, mobile branch tables |
| Ops dashboard | 1440x900 | 0 | 0 | 0 | No | `chainId 31338`, read-only, branch / oracle status |

The earlier CloudFront user app build included Vercel Analytics client
references, which caused `_vercel/insights/script.js` 403 / MIME errors on S3
hosting. The static layout no longer imports or renders Vercel Analytics.

The local development stats snapshot `jpydf-stats-local.json` was removed from
the deployed user app bucket. Staging user app reads only the dedicated public
stats CloudFront URL.

## Current Remaining Work

- Add a reset/redeploy runbook so chain reset, contract redeploy, stats publish,
  frontend rebuild, and CloudFront invalidation are performed as one operation.
- Move manual stats publish to an EventBridge / ECS worker with
  `OPS_STATS_S3_KMS_KEY_ID` set to the CDK stats bucket CMK.
- Add CI/CD artifact evidence so the uploaded frontend bundle can be traced to a
  manifest hash and build command.
