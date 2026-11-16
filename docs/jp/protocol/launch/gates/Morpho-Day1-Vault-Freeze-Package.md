# Morpho Day-1 Vault Freeze Package

> 位置づけ: `dUSDC`（Day-1・Branch 1）の Morpho `erc4626` / `morpho-v2` Strategy slot を有効にする前に、
> 実採用 vault、curator、oracle、queue、bad debt、withdrawability を凍結する evidence package。
> 本書は [`Morpho-Operation-Policy.md`](../../operations/policies/Morpho-Operation-Policy.md) の実行手順であり、
> `Mainnet-Deploy-Env-Freeze-Runbook.md` の strategy venue evidence に添付する。

## 1. Scope

対象はEthereum mainnetのplanned active Morpho allocationのみ（Day-1はbranch 1 dUSDC）。inert branch 2–7は個別activation判断と同時に本packageの対象となる。

| Branch | Underlying | Required Strategy kind | Evidence target |
| ---: | --- | --- | --- |
| 1 `dUSDC` | USDC | `erc4626` / `morpho-v2` | USDC asset の Morpho / MetaMorpho vault、または専用 `MorphoV2Strategy` 経由の USDC asset Morpho Vaults V2 vault（Day-1 policy は branch 1 に `morpho-v2` slot を必須とする。V2 evidence 項目は §4a） |
| 0 `dwstETH` | wstETH | — | Day-1 は Aave のみ。Morpho evidence 対象は信頼できる wstETH 建て vault が存在する場合に限る（§4a の V2 注記を参照） |

この package は **実採用 vault の承認**であり、単なる候補調査ではない。`Strategy-Selection-Policy.md`
の planned active set に Morpho が入っていても、本 package が未完了なら Morpho allocation は freeze
完了として扱わない。

## 2. Required Artifacts

Freeze issue / PR には最低限次を添付する。

| Artifact | Required contents |
| --- | --- |
| `morpho-vault-freeze.json` | `contracts/utils/morpho-vault-freeze-evidence.ts` の出力。vault address、asset、role、pending config、allocation、queue index、oracle、IRM、LLTV、bad debt、API warning、任意の on-chain ERC-4626 readback |
| `morpho-vault-risk-memo.md` | 採用 vault ごとの curator / owner / guardian / fee / timelock / pending action、market collateral、oracle、LLTV、liquidity、bad debt、incident history の人間レビュー |
| `morpho-vault-fork-dryrun.json` | fork block、deposit amount、partial withdraw、full withdraw、`sendToVault`、`emergencyWithdrawFromERC4626`、残 principal / writeoff 判定 |
| `safe-calldata/` | allocation pause、cap / weight reduction、`sendToVault`、`emergencyWithdrawFromERC4626`、必要なら `writeoffStrategyPrincipal` の Safe / Timelock calldata |
| `monitoring-plan.md` | share price、`maxWithdraw`、`maxRedeem`、pending config、queue / cap change、bad debt、oracle warning、curator / allocator change の alert owner |

## 3. Evidence Command

採用候補が決まったら、同一 `FORK_BLOCK` で API snapshot と on-chain readback を取る。

```bash
export FORK_BLOCK=<MAINNET_BLOCK_NUMBER>
export MORPHO_WETH_VAULT=<MORPHO_WETH_ERC4626_VAULT>
export MORPHO_USDC_VAULT=<MORPHO_USDC_ERC4626_VAULT>

pnpm -C contracts exec tsx utils/morpho-vault-freeze-evidence.ts \
  --vault 0:$MORPHO_WETH_VAULT \
  --vault 1:$MORPHO_USDC_VAULT \
  --rpc-url "$MAINNET_RPC_URL" \
  --block "$FORK_BLOCK" \
  --fail-on-blockers \
  --output /path/to/morpho-vault-freeze.json
```

deploy 後または fork dry-run 後に Strategy address が分かる場合は、`maxWithdraw(strategy)` /
`maxRedeem(strategy)` の readback も同じ JSON に入れる。

```bash
pnpm -C contracts exec tsx utils/morpho-vault-freeze-evidence.ts \
  --vault 0:$MORPHO_WETH_VAULT \
  --vault 1:$MORPHO_USDC_VAULT \
  --strategy 0:<DEPLOYED_WETH_ERC4626_STRATEGY> \
  --strategy 1:<DEPLOYED_USDC_ERC4626_STRATEGY> \
  --rpc-url "$MAINNET_RPC_URL" \
  --block "$FORK_BLOCK" \
  --fail-on-blockers \
  --output /path/to/morpho-vault-freeze-postdeploy.json
```

`--fail-on-blockers` は Day-1 freeze 用では必須。候補調査だけを行う場合のみ外してよい。

## 4. Blocker Conditions

次のいずれかがある場合、Morpho allocation を freeze しない。

- branch 1 vault の `asset()` が USDC でない、または（cap / activation 判断後に対象を追加した場合）その branch vault の `asset()` が当該 branch の Underlying と一致しない。
- Morpho API `listed=false`、RED warning、deposit disabled、または official source で address を確認できない。
- vault owner / curator / guardian / fee recipient / timelock / pending action が説明できない。
- pending config が存在し、その内容・実行時刻・影響が risk owner に承認されていない。
- allocation 先 market の loan asset が branch underlying と一致しない。
- active market の oracle / IRM / LLTV / collateral / queue index が取得できない。
- `badDebt` または `realizedBadDebt` が nonzero。
- high utilization / low liquidity / queue 劣化に対して partial withdraw / emergency withdraw dry-run がない。
- kind `erc4626` で採用する vault が `maxWithdraw` / `maxRedeem` evidence を満たせない
  （常時 0 の Vault V2 型設計は `erc4626` blocker の例外ではなく、kind `morpho-v2` で採用し
  §4a の evidence 項目を満たすこと）。
- depeg / exploit / curator takeover 時の Safe calldata、writeoff / backstop / comms 手順がない。

`morpho-vault-freeze-evidence.ts` の `BLOCKER` は解消または明示承認されるまで Day-1 launch blocker。
`REVIEW` は risk owner が issue 上で accept / reject / cap down を判断する。

## 4a. MorphoV2（`morpho-v2`）Evidence 項目

`MorphoV2Strategy` 経由で採用する Morpho Vaults V2 vault では、`maxWithdraw` / `maxRedeem` の
readback は意味を持たない（設計上 0）。代わりに採用 vault ごとに、同一 `FORK_BLOCK` で次を記録する。
gate の normative な定義は [`Morpho-Operation-Policy.md`](../../operations/policies/Morpho-Operation-Policy.md)
の V2 Gate 表を正とする。

| 項目 | 必須内容 |
| --- | --- |
| Gates | 4 つの gate（receive-shares / send-shares / receive-assets / send-assets）を readback し、全て unset であることを確認 |
| Sentinel | Sentinel address が設定済みで、holder と escalation path を説明できる |
| Per-selector timelocks | selector ごとの timelock 値を readback（デフォルトは 0。nonzero は protocol 保証ではなく checklist 項目） |
| Adapter registry | 登録済み adapter（ID・address・対象 protocol）を列挙し、それぞれ説明できる |
| forceDeallocate penalty | adapter ごとの `forceDeallocatePenalty` readback。全て Strategy の init 凍結 `maxForceDeallocatePenaltyBps`（`DF_STRATEGY_MORPHOV2_MAX_PENALTY_BPS`、protocol 上限 200 bps）以下 |
| maxRate | `maxRate` readback。0（deploy デフォルト）は yield を全額留保するため、受容には risk owner の明示承認と監視が必要 |
| Adapter liquidity | vault idle 残高と adapter ごとの deallocatable liquidity readback |
| Withdrawability dry-run | deposit、partial / full withdraw、`sendToVault`、`emergencyWithdrawFromMorphoV2`、およびpenalty 上限・正の最低回収額・事後 backing 下限を指定した `forceDeallocateMorphoV2` の同一 transaction 内回収 の fork dry-run |

branch 1 USDC slot の候補選定 pool（2026-08 時点の調査 snapshot。freeze には採用 `FORK_BLOCK` での
再 readback が必要）:

- Steakhouse Prime USDC `0xbeef088055857739C12CD3765F20b7679Def0f51`（約 $107M TVL）
- Gauntlet USDC Prime `0x8c106EEDAd96553e64287A5A6839c3Cc78afA3D0`（約 $79M TVL）
- ほか同一 scan で listed の USDC V2 vault 4 件。full scan は freeze issue に記録する

現時点で信頼できる wstETH 建て V2 vault は存在しない（唯一の候補は TVL $0.23 で unlisted）。
従って branch 0（`dwstETH`）は market が成熟するまで `morpho-v2` evidence target を持たない。

## 5. Risk Memo Checklist

実採用 vault ごとに、issue コメントまたは PR description に次を残す。

- vault name / symbol / address / official source / listed status / code hash / deployment source
- curator / owner / guardian / fee recipient / timelock / pending owner / pending configs
- public allocator config、flow cap、third-party allocator の有無
- supply queue / withdraw queue の順序、cap 0 market の残 exposure、removableAt
- market ごとの collateral、oracle、IRM、LLTV、utilization、liquidity、bad debt、realized bad debt
- oracle source と admin / upgrade / stale / revert 時挙動
- collateral depeg / price crash / liquidation latency が supplier loss に伝播する経路
- normal / partial / full / emergency withdraw dry-run amount と result
- Strategy cap / weight、CollateralVault buffer / withdrawDelay、即時 claim 可能額への影響
- monitoring owner、backup owner、alert thresholds、incident escalation

## 6. Issue Gate

実採用 vault の freeze は、#569 のような policy issue ではなく、新しい Day-1 blocker issue として管理する。
issue title は次の形にする。

```text
mainnet: freeze Morpho vault evidence for dUSDC (Day-1)
```

必須 label:

- `Day1`
- `priority high`

Close 条件:

- `morpho-vault-freeze.json` と fork dry-run evidence が添付されている。
- `BLOCKER` が 0、または product / risk / contracts / ops が明示的に scope change として承認済み。
- Day1 Parameter Manifestの関連値、deploy env skeleton、manifest preflight、frontend / ops表示が、実採用vaultの構成と一致している。
- Safe / Timelock calldata と monitoring owner が確定している。

## 7. Handoff To Deploy Env Freeze

この package が PASS したら、`Mainnet-Deploy-Env-Freeze-Runbook.md` の env skeleton に次を反映する。

- `DF_STRATEGY_ERC4626_VAULT_0_2=<MORPHO_WETH_ERC4626_VAULT>`
- `DF_STRATEGY_CAP_0_2`
- `DF_STRATEGY_WEIGHT_BPS_0_2`
- `DF_STRATEGY_ERC4626_VAULT_1_1=<MORPHO_USDC_ERC4626_VAULT>`
- `DF_STRATEGY_CAP_1_1`
- `DF_STRATEGY_WEIGHT_BPS_1_1`

`morpho-v2` slot の場合、対応する key は `DF_STRATEGY_MORPHOV2_VAULT_<branch>_<index>` と
`DF_STRATEGY_MORPHOV2_MAX_PENALTY_BPS_<branch>_<index>`（deploy デフォルト 200）であり、
`DF_STRATEGY_CAP` / `DF_STRATEGY_WEIGHT_BPS` は同じ key を使う。

env freeze から broadcast までに vault role、pending config、queue、market cap、bad debt、share price、
または `maxDeposit` / `maxWithdraw` が materially 変わった場合は、古い freeze package を superseded
として残し、新しい `FORK_BLOCK` で package を再生成する。
