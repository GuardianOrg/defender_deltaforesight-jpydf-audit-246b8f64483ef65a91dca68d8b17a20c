# InterestRouterForwarder Route Runbook

## 0. Scope

Day-1 DF dToken wiring では ActivePool の residual interest / upfront fee 25% は `InterestRouterForwarder` に mint される。`route()` は permissionless で、Forwarder が保有する JPYdf 全額を現在の `recipient` へ送る。

本 runbook は、`route()` が呼ばれず residual が Forwarder に滞留する運用リスクを監視・解消する手順を定める。

`route()` はユーザー claim ではない。SP 預入者が Day-1 から受け取る借入金利 75% は Core の Stability Pool 会計に直接入る。Forwarder に来る 25% は PIL 原資であり、Day-1 は `recipient` への会計集約だけを行う。Earn UI や public stats でこの 25% を SP 追加報酬、claimable reward、または確定利回りとして表示してはならない。

## 1. Roles

| Role | Responsibility |
| --- | --- |
| Ops keeper | `route()` の定期実行、tx 成否確認 |
| Ops dashboard | Forwarder 残高・recipient・owner・最終 route 時刻の監視 |
| Timelock / GOV | `recipient` 変更、Forwarder owner handover 後の設定変更 |
| Finance / accounting owner | Routed amount を PIL bucket として分類し、SP/Treasury 追加報酬と混同しない |

`route()` 自体は permissionless。keeper key が停止しても、任意の運用者または監視 bot が同じ関数を実行できる。

## 2. Monitoring

Ops dashboard は少なくとも以下を表示・alert する。

| Signal | Alert condition |
| --- | --- |
| `JPYdf.balanceOf(InterestRouterForwarder)` | `> 0` が keeper cadence を超えて継続 |
| `recipient()` | expected Safe / Treasury と不一致 |
| `owner()` / `pendingOwner()` | expected Timelock handover 状態と不一致 |
| last successful `Routed` event | cadence 超過、または Forwarder 残高増加後に未発火 |
| routed PIL ledger | ActivePool mint 残余 25% と `Routed` / recipient 入金の突合が不一致 |

推奨初期値: 残高 `> 0` を検知したら 1 時間以内に route、24 時間超の滞留は incident として扱う。

## 3. Keeper Procedure

標準 keeper は `frontend/ops` の `route-interest` script を使う。script は各 branch の `AddressesRegistry.interestRouter()` を読み、全 branch が同一 Forwarder を指すこと、Forwarder の `jpydfToken()` が deployment の JPYdf と一致すること、RPC `chainId` が期待値と一致することを fail-fast で確認する。

```bash
# dry-run（既定）。残高・recipient・owner・simulation 結果を JSON 出力する。
pnpm --filter @jpydf/ops route-interest -- --dry-run

# live。IRTR_ROUTE_PRIVATE_KEY は keeper 用 EOA のみ。秘密鍵は出力しない。
IRTR_ROUTE_MODE=live \
IRTR_ROUTE_PRIVATE_KEY=0x... \
IRTR_EXPECTED_CHAIN_ID=31337 \
IRTR_EXPECTED_RECIPIENT=0x... \
pnpm --filter @jpydf/ops route-interest
```

本番では `IRTR_EXPECTED_RECIPIENT` を必須運用値として設定する。残高が `0` の場合は no-op、`IRTR_MIN_ROUTE_AMOUNT`（raw 18dec JPYdf）未満なら threshold skip とする。live mode は送信前に `simulateContract(route)` を実行し、戻り値が Forwarder 残高と一致しない場合は送信しない。

手順:

1. Run `route-interest --dry-run`.
2. If balance is zero, do nothing.
3. Confirm `recipient()` equals the expected Safe / Treasury. Mismatch の場合は `route()` せず、GOV/Timelock に escalate する。
4. Run live mode.
5. Verify:
   - Forwarder JPYdf balance is zero.
   - recipient JPYdf balance increased by the routed amount.
   - `Routed(recipient, amount)` event is emitted.

## 4. Failure Handling

- `route()` revert: tx hash / revert reason / current balances を保存し、same block retry はしない。token transfer failure、wrong token address、recipient issue を切り分ける。
- wrong recipient: Timelock で `setRecipient(expectedRecipient)` を queue / execute し、その後に `route()` する。
- owner mismatch: `PrepareDFGovernanceHandover` / `VerifyDFGovernanceHandover` の結果と manifest を確認し、pending ownership か完了状態かを切り分ける。

## 5. Non-Goals

Forwarder は分配ロジックを持たない。SP 追加報酬、buyback、Treasury split は Day-2 Treasury / SPAdditionalRewardDistributor の責務であり、Day-1 は recipient Safe への集約のみを行う。
