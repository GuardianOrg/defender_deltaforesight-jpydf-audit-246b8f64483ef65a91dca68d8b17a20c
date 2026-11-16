# Bridge Minter Activation Gate

> **位置づけ**: Day-2 以降に `JpydfToken` の bridge minter を 1 件でも登録する前の activation gate。Day-1 mainnet launch は引き続き bridge minter 0 件・pending proposal なしで行う。本書は [JpydfToken](../../product/spec/JpydfToken.md) `CORE-BT-GOV-001` / `CORE-BT-SEC-005` / `CORE-BT-INV-004` の運用手順である。承認記録は [Day-1 Governance Proposal & Execution Policy](../../launch/gates/Day-1-Governance-Proposal-Execution-Policy.md) と [Protocol Governance GitHub Operations](../../../protocol/operations/runbooks/Protocol-Governance-GitHub-Operations.md) に従う。
>
> **原則**: `JpydfToken` は non-upgradeable で、token-level の chain cap / rate limit / route pause を持たない。したがって cap / rate / accounting / pause を持たない bridge adapter は、`bridgeAdmin` が `proposeBridgeMinter` してはならない。token-level control を後付けしたい場合は、新 token / wrapper / migration を含む別設計・別監査に戻す。

---

## 1. Scope

本 gate が対象にするのは、Ethereum mainnet の canonical `JpydfToken` に対して、任意の bridge adapter / minter を `bridgeMinterAddresses` に登録する判断である。

対象:

- Ethereum mainnet `JpydfToken.bridgeMint` / `bridgeBurn` を呼べる minter 登録。
- remote chain 上の canonical JPYdf 表現、bridge adapter、message endpoint、relayer / verifier / DVN / guardian。
- per-chain cap、per-route rate limit、global bridged supply cap、remote supply accounting、pause / remove / emergency response。
- frontend / ops / subgraph が active bridge route として表示・監視する条件。

対象外:

- Day-1 launch の dormant evidence。値のfreezeと生成Manifest照合は[Mainnet-Deploy-Env-Freeze-Runbook](../../launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md)、deploy mode・Manifest schema・validationは[Deployment Configuration Spec](../../../engineering/guides/Deployment-Configuration-Spec.md)が担い、[Mainnet Initial Configuration Checklist](../../launch/gates/Mainnet-Initial-Configuration-Checklist.md) は dormant surface の完了集約だけを行う。
- USDC の bridge / CCTP / Across route そのもの。USDC rail は JPYdf canonical supply authority ではない。
- dToken、Trove debt、Stability Pool deposit、yield-bearing representation の cross-chain 化。初期 bridge scope は JPYdf token-only に限定する。

## 2. Staged Activation Decision

bridge minter activation は、registration、canary / public route open、cap ramp を分けて扱う。Day-2 初動を止めすぎないため、cap 0 / paused adapter を minter 登録する gate と、ユーザー向け route を開ける gate を混同しない。

| Stage | 可能になること | 必須条件 |
| --- | --- | --- |
| A. minter registration | `bridgeAdmin.proposeBridgeMinter` / `confirmBridgeMinter`。adapter は route paused、runtime cap 0 で登録可 | 採用 bridge / framework / chain IDs / domain IDs / endpoint addresses / message origin policy が freeze 済み。adapter が per-destination cap、hourly / daily sliding-window mint limit、global bridged supply cap、route pause、replay protection、domain binding、remote token binding を on-chain 強制。`globalCanonicalJpydfSupply` と chain 別 `remoteCanonicalJpydfSupply` を再構成でき、pending / in-flight message を別 bucket で追跡できる。admin / minter / upgrader / guardian / relayer / accounting operator が分離済み。pause、`removeBridgeMinter`、pending proposal cancel、remote mint stop の incident path を rehearsal 済み。cap / pause / replay / accounting の unit・invariant・fork evidence と internal differential review が揃っている |
| B. canary / public route open | operator-only canary、または frontend / ops route flag の public open | Stage A 完了。operator-only canary は activation package に canary envelope（adapter / endpoint enforced allowlisted operator、max amount、expiry、public flag closed）、nonzero pilot cap / rate limit 値、monitoring threshold、subgraph / indexer field が揃っている。UI / ops flag だけで閉じる route は operator-only canary と扱わず third-party accessible route とみなす。public route open では risk disclosure、frontend / ops route flag、support response も揃える。public route、third-party accessible route、canary envelope 超過は external audit / independent review を完了。canary は route paused -> small-cap -> paused rollback を rehearsal 済み |
| C. cap ramp / scope expansion | pilot cap を超える引上げ、route / chain 追加 | Stage B 後の incident-free observation、accounting reconciliation、liquidity / support readiness。cap 引上げは、承認済み Class N の親 JIP に step / ceiling / interval が定義されていればその枠内で 72h 前公示し、枠外は新しい Class N JIP を要する。route / chain / minter の追加は新しい Class C JIP を要する。cap 引上げは [Active Branch Cap Ramp Runbook](./Active-Branch-Cap-Ramp-Runbook.md) と同等の business / risk / ops cadence に合わせる |

`proposeBridgeMinter` は Stage A の evidence package が揃った後にだけ実行する。48h timelock 経過後の `confirmBridgeMinter` 前にも Stage A evidence を再確認し、chain halt、adapter upgrade、remote token owner change、verification provider compromise があれば proposal を cancel する。Stage A は public bridge route の承認ではない。

`confirmBridgeMinter` 後から Stage B 前までに adapter / remote program codehash、endpoint config、remote token authority、owner / upgrader / guardian holder、cap / rate config が変わった場合、Stage A evidence は失効する。route は paused / runtime cap 0 のまま Stage A verification を再実施し、未承認 drift は `removeBridgeMinter` まで進める。

operator-only canary は frontend / ops flag ではなく adapter / endpoint 側の allowlist、amount cap、expiry で強制する。これを証明できない route は public 表示を閉じていても third-party accessible route として扱い、external audit / independent review を Stage B 前に完了する。

## 3. Required Adapter Controls

adapter / minter は次を fail-closed に強制する。

| Control | 要件 |
| --- | --- |
| per-chain cap | destination chain ごとの canonical JPYdf outstanding 上限。approved pilot cap は activation package と対応 JIP で明示し、runtime は 0 / paused から開始して承認済み cap schedule または新しい JIP ごとに ramp する |
| per-route cap | `(sourceChain, destinationChain, token)` route ごとの上限。route 追加時は既存 cap を共有しない |
| hourly / daily mint limit | rolling window で destination mint を制限。window reset や chain reorg で超過しない実装にする |
| global bridged supply cap | 全 remote canonical supply の合計上限。per-chain cap の総和が global cap を超えても、global cap を優先 |
| route pause | chain 単位・route 単位・global の pause を分離。pause 中は mint / unlock / message execution が revert または no-op で止まる |
| message origin binding | endpoint、source chain/domain、source adapter address、remote token address / codehash を固定し、unknown origin を reject |
| replay / idempotency | message nonce / GUID / burn id を 1 度だけ消費。same message の再実行、different route replay、cross-chain replay を reject |
| decimal / dust handling | remote decimals、rounding、minimum amount、dust burn / refund policy を固定。u64 amount 系 chain では overflow / truncation を invariant 化 |
| upgrade gate | adapter / remote token / remote program が upgradeable なら timelock、codehash allowlist、pre-upgrade pause、post-upgrade smoke test を必須化 |

`JpydfToken` 側は「登録済み minter かどうか」だけを判定する。adapter が上記 control を持たない場合、token 側の `bridgeMint` を使って補完してはならない。

## 4. Supply Accounting

activation package は、少なくとも次の accounting view を生成できなければならない。

```text
globalCanonicalJpydfSupply
  = ethereumJpydfToken.totalSupply()
  - ethereumBridgeEscrowedCanonical
  + sum(remoteCanonicalJpydfSupply[chain])

remoteCanonicalJpydfSupply[chain]
  = remote canonical token totalSupply
  - non-canonical wrapped / escrowed / test balances
```

運用上の bucket:

| Bucket | 内容 | 扱い |
| --- | --- | --- |
| local Ethereum supply | mainnet `JpydfToken.totalSupply()` | Core debt token supply と bridge burn / mint の結果を含む |
| Ethereum bridge escrow | lock/unlock 型 adapter が mainnet で保管する canonical JPYdf | remote canonical supply と二重計上しないよう `globalCanonicalJpydfSupply` から控除。burn/mint 型では 0 |
| remote canonical supply | approved remote token / program が発行した canonical JPYdf | per-chain cap と global cap の対象 |
| in-flight debit | source burn / lock は済んだが destination mint / unlock が未 final | cap 計算では conservatively outstanding として扱う |
| failed / expired message | debit と credit が対応しない message | incident queue に入り、manual refund / burn / reconcile 判断まで route を止める |
| non-canonical representation | DEX LP token、wrapped JPYdf、test token、unapproved token | canonical supply に含めず UI で canonical と表示しない |

正常時の invariant:

- finalized source debit と destination credit は 1:1 に対応する。
- `remoteCanonicalJpydfSupply[chain] <= perChainCap[chain]`。
- `sum(remoteCanonicalJpydfSupply) <= globalBridgedSupplyCap`。
- cap / rate limit により reject された message は destination mint を発生させない。
- emergency burn / admin mint など manual action がある場合、incident ID と対応 JIP ID / Class / status（Class E に該当する場合は JIP-E）を accounting ledger に残す。

## 5. Chain Architecture Recommendation

初期採用は「どこでも同じ adapter」ではなく、chain ごとの実行環境と user flow を分けて判断する。

| Destination | 推奨初期方針 | 理由 / 注意点 |
| --- | --- | --- |
| Base | EVM pilot の第一候補。LayerZero OFT / MintBurn adapter または Wormhole NTT 型を候補にし、small cap で開始 | EVM contract / monitoring / fork test を再利用しやすい。Base-Solana bridge は wrapped / twin / proof flow を含むため、JPYdf canonical bridge の初期 minter としては別監査扱い |
| HyperEVM | EVM pilot の第二候補。HyperCore 直結ではなく HyperEVM token と bridge adapter を先に検証 | HyperCore spot asset linking は system address 残高や ERC20 妥当性を bridge 側で自動保証しないため、HyperCore credit は別 gate にする |
| Solana | non-EVM pilot。SPL / Token Extensions、program upgrade authority、PDA / ATA、u64 amount、decimal dust、finality を別監査 | EVM と同じ invariant では不十分。remote supply reader と emergency authority の rehearsal が必須 |
| Arc | USDC rail 先行。JPYdf canonical bridge は Arc の token / domain / adapter support が production evidence で固まるまで deferred | CCTP は USDC burn/mint rail であり、JPYdf の supply authority ではない。Arc UX は USDC conversion と JPYdf canonical mint を混同しない |

Protocol family の扱い:

| Family | JPYdf bridge minter としての扱い |
| --- | --- |
| CCTP / Gateway | USDC 用 rail。JPYdf bridge minter ではない |
| Across | 高速 UX / intents / USDC route として有用。underlying settlement が CCTP / OFT 等で、JPYdf adapter controls が満たされる場合だけ canonical JPYdf route として扱う |
| Stargate | liquidity transport / compose UX layer。JPYdf canonical supply authority を渡すには別途 approved adapter / pool control が必要 |
| LayerZero OFT | 候補。ただし single DVN 依存は禁止し、multiple required DVNs、rate limit、adapter-only mint authority、domain binding、config evidence を必須化 |
| Wormhole NTT 型 | 候補。manager / transceiver / token authority / pause / rate limit / chain registry を JPYdf の cap/accounting model に合わせて監査する |

## 6. Governance And Role Separation

最低限の holder 分離:

| Role | Holder | 禁止事項 |
| --- | --- | --- |
| `bridgeAdmin` | mainnet Safe / Timelock contract | adapter minter と同一、deployer EOA、relayer key と同一は禁止 |
| adapter owner / upgrader | Timelock contract | immediate upgrade、unreviewed implementation、pause なし upgrade は禁止 |
| pause guardian | Guardian Safe / contract | cap 引上げ・upgrade・minter confirm 権限を持たない |
| accounting operator | read-only / dashboard operator | mint / upgrade / pause 権限を持たない |
| relayer / verifier / DVN | protocol-specific set | `bridgeAdmin` / adapter owner と同一 secret 管理は禁止 |

`bridgeAdmin` は token-level minter の propose / confirm / remove だけを担う。adapter の cap 変更、route 追加、upgrade は adapter 側 governance で別に timelock し、token-level minter registration と同じ Safe transaction bundle に混ぜない。

## 7. Incident Runbook

次の trigger は route pause と incident declaration の対象にする。

- expected cap / rate limit を超える `BridgeMint`、または cap 計算不能。
- unknown source chain / source adapter / remote token からの message。
- remote canonical supply と accounting exporter の不一致。
- bridge endpoint、DVN、validator、relayer、remote admin、program upgrade authority の compromise 疑い。
- destination chain halt、sequencer fault、finality regression、bridge message stuck。
- frontend / indexer が non-canonical representation を canonical と表示した疑い。

初動:

| Time | Action |
| --- | --- |
| T+0 | adapter global pause / affected route pause。frontend route flag を inactive。ops alert を incident mode に変更 |
| T+15m | `bridgeAdmin` が pending proposal を cancel、または live minter を `removeBridgeMinter`。必要に応じて remote adapter owner が remote mint / unlock を停止 |
| T+30m | accounting snapshot を freeze。source debit、destination credit、in-flight、failed message、remote token supply を chain 別に採取 |
| T+1h | emergency burn / refund / manual reconcile の governance 判断。user balances を直接 burn できる前提を置かず、adapter-owned / escrowed / remote admin-controlled balance だけを対象にする |
| T+24h | postmortem、cap reset、route re-enable proposal、frontend / support update |

`JpydfToken.bridgeBurn` は self-burn だけであり、mainnet 上の任意ユーザー残高を emergency burn する機能ではない。この制約を incident plan に明記する。

## 8. Verification Matrix

adapter implementation / remote program は次を test / invariant として提出する。

| Area | Required checks |
| --- | --- |
| minter lifecycle | unregistered minter cannot mint、remove 後 mint 不可、pending proposal cancel、48h timelock 境界 |
| cap | per-chain cap、per-route cap、global cap、cap ramp、cap decrease、cap exhausted edge |
| rate limit | hourly / daily rolling window、window boundary、multi-message batch、reorg / retry |
| pause | global pause、route pause、source-only / destination-only pause、paused message execution |
| message auth | source chain/domain binding、source adapter binding、remote token binding、endpoint spoof reject |
| replay | same message replay、cross-route replay、cross-chain replay、nonce gap、idempotent retry |
| accounting | source debit vs destination credit、in-flight bucket、failed message bucket、remote supply reader、dashboard export |
| decimals | 18dec EVM、non-18 remote、u64 overflow、dust rounding、minimum amount |
| upgrade | timelock schedule / execute、codehash allowlist、pre-upgrade pause、post-upgrade smoke |
| incident | pause + remove minter rehearsal、emergency accounting snapshot、frontend route disable |

Stage A の最低限 evidence:

- adapter source commit、compiler / build hash、deployed bytecode hash。
- remote token / adapter / endpoint addresses、chain ID / domain ID、source and destination codehash。
- approved pilot cap / rate limit values、global cap、initial route state（runtime cap 0 / paused 可）。
- holder separation table、Safe / Timelock transaction hashes、guardian contact path。
- unit / integration / fork / invariant logs。
- internal differential review for adapter and remote program。
- accounting exporter JSON sample、dry-run incident record。

Stage B の最低限 evidence:

- canary envelope（adapter / endpoint enforced allowlisted operator、max amount、expiry、public flag closed）。UI / ops flag だけで閉じる route、public / third-party accessible route、または canary envelope 超過では external audit report or independent review。
- current codehash / config snapshot と Stage A evidence の再照合。drift があれば Stage A からやり直す。
- monitoring dashboard screenshot / JSON export、alert thresholds。
- subgraph / indexer field。public route open では frontend / ops route flag、risk disclosure、support response。
- operator-only canary transfer result、rollback / pause rehearsal。

## 9. Activation Procedure

1. Design freeze: chain / protocol / adapter / remote token / cap model / accounting model を review し、activation package を作る。
2. Adapter deploy: adapter と remote token / program を deploy し、initial cap 0、route paused で始める。
3. Stage A verification: §8 の cap / pause / replay / accounting tests、fork / invariant、internal differential review、incident dry-run を通す。public / third-party accessible route、または canary envelope 超過に進む場合は external audit / independent review を Stage B までに完了する。
4. Governance staging: adapter owner / upgrader / guardian / accounting operator を分離し、codehash / config snapshot を evidence 化する。Stage A の target / calldata / Stage B envelope / rollback を含む Class C JIP を `Approved` にし、Decision Package hash と activation package hash を固定する。
5. Token proposal: Approved Class C JIP と一致する `bridgeAdmin.proposeBridgeMinter(adapter)` を実行し、proposal event と `confirmableAt` を当該 JIP に追記する。
6. Timelock watch: 48h の間に adapter upgrade、remote admin change、chain incident、verification drift がないことを確認する。問題があれば cancel。
7. Confirm: `confirmBridgeMinter()` を実行する。adapter は route paused / runtime cap 0 のまま登録してよい。
8. Stage B route open: current codehash / config snapshot が Stage A evidence と一致し、approved pilot cap / rate limit、monitoring、subgraph / indexer field が揃ってから pilot value までだけ開ける。operator-only canary は public flag closed のまま、adapter / endpoint enforced allowlist と canary envelope 内で実行する。Stage B が Class C JIP の承認済み envelope 内なら同 JIP の execution step とし、含まれない public route open は Class N JIP、route / chain / minter の追加は Class C JIP とする。
9. Ramp: cap 引上げは承認済み Class N の親 JIP の枠内で 72h 前公示して行う。枠外は新しい Class N JIP とし、[Active Branch Cap Ramp Runbook](./Active-Branch-Cap-Ramp-Runbook.md) と同等の business / risk / ops cadence に合わせる。

## 10. External Reference Baseline

activation package は review 時点の official docs を再取得し、少なくとも次を evidence に含める。

- [Circle CCTP](https://developers.circle.com/cctp) / [supported chains and domains](https://developers.circle.com/cctp/concepts/supported-chains-and-domains): CCTP は USDC burn/mint rail であり、Arc / Base / HyperEVM / Solana の support と domain ID を確認する。JPYdf supply authority とは別物として扱う。
- [Base network docs](https://docs.base.org/base-chain/quickstart/connecting-to-base) / [Base-Solana bridge docs](https://docs.base.org/base-chain/quickstart/base-solana-bridge): Base chain ID、Base-Solana bridge の lock / burn / mint / unlock semantics、validator / Merkle proof / wrapped token 境界を確認する。
- [Hyperliquid HyperEVM docs](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm) / [HyperCore <> HyperEVM transfer docs](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/hypercore-less-than-greater-than-hyperevm-transfers): HyperEVM chain ID、HyperCore spot asset link、system address balance / ERC20 validity caveat を確認する。
- [LayerZero OFT docs](https://docs.layerzero.network/v2/developers/evm/oft/quickstart): OFT / OFTAdapter / MintBurn adapter、multiple required DVNs、rate-limit configuration を確認する。
- [Stargate docs](https://stargateprotocol.gitbook.io/stargate/v2-developer-docs/integrate-with-stargate/composability): liquidity transport / composability scope と JPYdf canonical supply authority の分離を確認する。
- [Across docs](https://docs.across.to/introduction) / [stablecoin settlement](https://docs.across.to/introduction/stablecoins) / [HyperCore route](https://docs.across.to/introduction/hypercore): intents / CCTP / OFT settlement と HyperCore USDC route を確認し、JPYdf minter ではなく UX / settlement rail として扱える範囲を確認する。

これらはprotocol selectionの参考であり、JPYdfのactive要件は本書、[JpydfToken](../../product/spec/JpydfToken.md)、承認済みactivation packageによって確定する。
