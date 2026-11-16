# Frontend Agent Readiness Gate

Updated: 2026-07-26

This runbook defines the agent/crawler-discovery delta gate for the public User App. It assumes the common decision in [Frontend Production Delivery Gate](Frontend-Production-Delivery-Gate.md) and applies only to `frontend/app`.

## 1. Scope

In scope:

- The public user app of `frontend/app`.
- Discovery files for agents / crawlers.
- Canonical URL, metadata, sitemap, robots, and LLM-facing descriptions.

Out of scope:

- Admin Control and the Private Operations Monitor.
- Dune Public Analytics.
- The legacy public Ops UI during its decommission period. Even while public, it is not part of User App discovery metadata.

## 2. Day-1 Minimum Gate

| Gate | Day-1 requirement | Evidence |
| --- | --- | --- |
| Canonical URL | Set `NEXT_PUBLIC_SITE_URL` as an HTTPS origin. Do not include path / query / fragment. | `pnpm check:hosting-env`, generated `sitemap.xml` |
| Discoverability | Generate `/robots.txt` and `/sitemap.xml`, and exclude user-state routes from crawler targets. | `curl /robots.txt`, `curl /sitemap.xml` |
| Bot access policy | A user-initiated agent can read public routes, but training crawlers receive `Disallow: /` and `Content-Signal: ai-train=no`. | `curl /robots.txt` |
| LLM-readable docs | Publish `/llms.txt` and `/llms-full.txt`, briefly explaining the main routes, data freshness, and wallet safety boundaries. | `curl /llms.txt`, `curl /llms-full.txt` |
| Auth description | In `/auth.md`, explain wallet connection, transaction authorization, and non-acquisition of private keys. | `curl /auth.md` |
| Metadata | Output description, canonical, Open Graph, and agent/readiness meta in the root layout. | page source / rendered head |
| No fake protocol card | Do not write MCP / Agent Skills / OAuth / commerce as available unless there is a real implementation. | `/.well-known/agent-readiness.json` |
| Surface separation | Do not include admin / ops URLs, operator-only information, private RPC, Safe nonces, or role holder private notes in the user app discovery. | bundle grep / content review |

## 3. No-Go Conditions

- `NEXT_PUBLIC_SITE_URL` is unset, localhost, HTTP, or has a path.
- `sitemap.xml` points to a staging / localhost / placeholder origin.
- The agent docs explain dToken and underlying in a way that conflates them.
- The agent docs explain APR / liquidation gains / redemption result with guarantee-style wording.
- `robots.txt` allows user-state routes, or allows training crawlers.
- An MCP server, Agent Skills, OAuth, or commerce endpoint with no real implementation is published as available.
- A restricted surface of the admin console or ops dashboard is mixed into the
  user app's public route map.

## 4. Verification

Confirm the following before publishing.

```sh
pnpm --filter @jpydf/app check:hosting-env
pnpm --filter @jpydf/app build
```

Confirm the following after publishing.

```sh
curl -fsS "$NEXT_PUBLIC_SITE_URL/robots.txt"
curl -fsS "$NEXT_PUBLIC_SITE_URL/sitemap.xml"
curl -fsS "$NEXT_PUBLIC_SITE_URL/llms.txt"
curl -fsS "$NEXT_PUBLIC_SITE_URL/llms-full.txt"
curl -fsS "$NEXT_PUBLIC_SITE_URL/auth.md"
curl -fsS "$NEXT_PUBLIC_SITE_URL/.well-known/agent-readiness.json"
```

If you use an external scanner such as `isitagentready.com`, attach the result to
the Frontend Production Delivery evidence, and do not force yourself to satisfy
protocol discovery items that have no real implementation.
