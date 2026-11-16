# Frontend Agent Readiness Gate

Updated: 2026-07-26

この runbook は public user app の agent / crawler discovery に固有の差分 gate
を定義する。[Frontend-Production-Delivery-Gate.md](./Frontend-Production-Delivery-Gate.md)
の共通判定を前提とし、対象は `frontend/app` だけとする。

## 1. Scope

対象:

- `frontend/app` の公開 user app。
- agent / crawler 向け discovery ファイル。
- canonical URL、metadata、sitemap、robots、LLM 向け説明文。

対象外:

- Admin Control / Private Operations Monitor。
- Dune Public Analytics。
- decommissionまで残るpublic Ops UI。公開transparency surfaceであってもuser app discovery metadataの対象にしない。

## 2. Day-1 Minimum Gate

| Gate | Day-1 要件 | Evidence |
| --- | --- | --- |
| Canonical URL | `NEXT_PUBLIC_SITE_URL` を HTTPS origin として設定する。path / query / fragment は入れない。 | `pnpm check:hosting-env`、generated `sitemap.xml` |
| Discoverability | `/robots.txt` と `/sitemap.xml` を生成し、user-state route を crawler 対象から外す。 | `curl /robots.txt`、`curl /sitemap.xml` |
| Bot access policy | user-initiated agent は public route を読めるが、training crawler には `Disallow: /` と `Content-Signal: ai-train=no` を返す。 | `curl /robots.txt` |
| LLM-readable docs | `/llms.txt` と `/llms-full.txt` を公開し、主要 route、データ鮮度、wallet 安全境界を短く説明する。 | `curl /llms.txt`、`curl /llms-full.txt` |
| Auth description | `/auth.md` で wallet 接続、transaction authorization、秘密鍵非取得を説明する。 | `curl /auth.md` |
| Metadata | root layout に description、canonical、Open Graph、agent/readiness meta を出す。 | page source / rendered head |
| No fake protocol card | MCP / Agent Skills / OAuth / commerce は実体がない限り available と書かない。 | `/.well-known/agent-readiness.json` |
| Surface separation | admin / ops URL、operator-only 情報、private RPC、Safe nonce、role holder private notes を user app discovery に含めない。 | bundle grep / content review |

## 3. No-Go Conditions

- `NEXT_PUBLIC_SITE_URL` が未設定、localhost、HTTP、または path 付き。
- `sitemap.xml` が staging / localhost / placeholder origin を指している。
- agent docs が dToken と underlying を混同して説明している。
- agent docs が APR / liquidation gains / redemption result を保証表現で説明している。
- `robots.txt` が user-state route を許可している、または training crawler を許可している。
- 実体のない MCP server、Agent Skills、OAuth、commerce endpoint を available として公開している。
- admin console や ops dashboard の restricted surface を user app の public route
  map へ混ぜている。

## 4. Verification

公開前に以下を確認する。

```sh
pnpm --filter @jpydf/app check:hosting-env
pnpm --filter @jpydf/app build
```

公開後に以下を確認する。

```sh
curl -fsS "$NEXT_PUBLIC_SITE_URL/robots.txt"
curl -fsS "$NEXT_PUBLIC_SITE_URL/sitemap.xml"
curl -fsS "$NEXT_PUBLIC_SITE_URL/llms.txt"
curl -fsS "$NEXT_PUBLIC_SITE_URL/llms-full.txt"
curl -fsS "$NEXT_PUBLIC_SITE_URL/auth.md"
curl -fsS "$NEXT_PUBLIC_SITE_URL/.well-known/agent-readiness.json"
```

`isitagentready.com` などの外部 scanner を使う場合は、結果を
Frontend Production Delivery evidence に添付し、実体のない protocol discovery
項目を無理に満たそうとしない。
