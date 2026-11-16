# 清算 Bot 実装計画

## 目的

JPYdf/Liquity v2 Core の過少担保 Trove を継続的に検出し、必要に応じて運営主体が清算を実行できる Rust keeper を用意する。運営用途では清算の外部利益最大化を必須条件にせず、明示された gas / 損失予算内でプロトコル健全性を優先できることを要件に含める。

## モード

| Mode | 方針 |
| --- | --- |
| `profit-seeking` | Day-2 用。担保処分・在庫評価込みの profit model が入るまで live 起動を fail-closed する |
| `protocol-maintenance` | stress 後 gas cost を損失として扱い、推定損失が `max_loss_wei_per_tx` 以下で、かつ `max_gas_cost_wei` 以下なら送信可能にする |

どちらのモードでも `dry_run = true` が初期値。read-only / dry-run は署名鍵を読み込まず HTTP RPC Provider だけで動く。実送信は `execution.enabled = true`、`execution.dry_run = false`、`execution.private_key_env` に空でない env var 名が指定されていること、当該 env var の存在、RPC `eth_chainId` と `chain.chain_id` の一致、live policy の明示的な正の cap、`max_submissions_per_cycle > 0` をすべて満たした場合だけ許可する。launch 用 dry-run は `execution.enabled = true` のまま `execution.dry_run = true` にし、live と同じ policy 判定を通してから `dry run` で止める。現行実装の live 送信対象は `protocol-maintenance` のみであり、`profit-seeking` は positive `min_profit_wei` を設定しても起動時に拒否する。

## 初期実装範囲

1. `LiquidationCandidateGetter.getLiquidationCandidatesWithLastZombie` による branch 別 `SortedTroves` ページング探索と `lastZombieTroveId` の同時確認。
2. `IPriceFeed.fetchPrice()` で取得したプロトコル価格を使用する。
3. `IAddressesRegistry.MCR()` または設定値から MCR を取得する。
4. 候補 Trove は `TroveManager.getCurrentICR` で送信直前に再検証する。
5. `TroveManager.batchLiquidateTroves` の gas estimate を取り、operator policy で送信可否を決める。
   live 送信では、この判定に使った gas limit と gas price を tx に固定し、
   provider の送信時再見積もりで per-tx gas 予算が静かに上がらないようにする。
6. `SortedTroves` から外れる zombie Trove は LCG の `includeLastZombie` 経路で確認し、`entireDebt` / `entireColl` も同じ候補構造で扱う。
7. 初期版の収益推定は保守的に stress 後 gas cost を損失として扱う。担保受領・処分まで含む利益推定は後続で追加する。

## 捕捉モデル

初期 backend は HTTP RPC だけで動く `new-block` trigger を標準にする。`run` 起動中は `eth_blockNumber` を polling し、新ブロックを検知したときに branch cursor から `LiquidationCandidateGetter` を実行する。各 scan 後に `last_seen_block` と branch cursor を state file に保存し、再起動後も同じ範囲を過剰に繰り返さず巡回を継続する。state file は一時ファイルへ書いてから atomic replace するため、daemon 停止・再起動時に中途半端な cursor file を残しにくい。`run` 中の一時的な RPC read / scan / planning failure は、scan 前 cursor に戻して `chain.poll_interval_ms` 後に再試行し、429 / timeout 時に supervisor restart loop で RPC 圧を増やさない。

Liquity v2 では `SortedTroves` が ICR 順ではなく annual interest rate 順であり、清算探索で早期停止できない。そのため bot は branch ごとに巡回 scan を続ける。`batchLiquidateTroves` は配列内の非対象 Trove を skip し、`ICR < MCR` の active/zombie Trove だけを清算するが、bot 側でも送信直前に `getCurrentICR` で再確認する。

清算配分は Liquity Core の経路に従う。Stability Pool に利用可能な JPYdf があれば SP offset、足りない分は redistribution、余剰担保は CollSurplusPool に積まれる。JIT は実行前に第三者が SP へ預ける外部行動であり、`batchLiquidateTroves` 内部の分岐ではない。`TroveManager` は `MIN_JPYDF_IN_SP` を残して offset するため、bot は `getTotalJpydfDeposits()` から offset capacity をログに出す。

### JIT / backstop の責務境界

JIT の正本は [`Liquidation-Backstop-And-JIT-Policy.md`](../../protocol/operations/policies/Liquidation-Backstop-And-JIT-Policy.md) とする。本 bot の現行スコープは **候補検出・SP offset capacity の観測・清算 tx の計画/送信** までである。

- bot は JPYdf/USDC Uniswap v4 で JPYdf を調達しない。
- bot は `StabilityPool.provideToSP` を自動実行しない。
- bot は JPYdf 調達 -> SP deposit -> `batchLiquidateTroves` を 1 tx / bundle にまとめない。
- bot は清算で得た collateral gain の処分・会計・退避を扱わない。

したがって、配分計画で使う「SP + JIT capacity」は、現行 contracts / bot が予約・保証する値ではなく、operator が JPYdf を用意し、対象 branch の SP に deposit し、清算 tx を通せるという運用上の planning capacity である。Atomic JIT executor を将来追加する場合は、本 bot の設定追加ではなく新しい audited executor として扱う。

補助 trigger として `poll-interval` を残す。ローカル anvil やブロック生成が不規則な検証環境では、同一ブロックでも一定間隔で scan したい場合があるためである。

## Liquity v2 前提

| Core 挙動 | Bot への反映 |
| --- | --- |
| `ICR < MCR` の active/zombie Trove だけ清算対象 | bot の最終判定も `getCurrentICR(troveId, protocolPrice) < MCR` に統一する |
| `batchLiquidateTroves` は `priceFeed.fetchPrice()` を内部実行 | bot 側の価格は探索・再検証・ログ用。最終実行価格は Core に従う |
| SP offset 後、不足分は redistribution | SP deposits と offset capacity をログに残し、赤字許容判断の文脈に使う |
| `SortedTroves` は annual interest rate 順 | ICR 順の優先探索はしない。cursor 巡回と再検証を基本にする |
| zombie は `SortedTroves` から外れる | LCG の `getLiquidationCandidatesWithLastZombie(..., includeLastZombie=true)` で `lastZombieTroveId` を末尾候補として拾う。ただし複数 zombie の網羅は後続課題 |
| branch shutdown 後も残債務は urgent redemption / 返済 / 清算で巻き取る | liquidation keeper は shutdown branch を自動停止しない。urgent redemption keeper は別プロセスにする |

## 実装場所

- `bots/liquidator/`
  - Rust crate。
  - `config.example.toml` に local/dev 用設定例を置く。
  - 初期コマンドは `scan-once` と `run`。
  - `systemd/jpydf-liquidator.service.example` と `Dockerfile` を運用起動テンプレートとして置く。

## 段階

| Phase | 内容 | 完了条件 |
| --- | --- | --- |
| M1 | read-only scanner | 各 branch の price/MCR/candidates/cursor をログ出力できる |
| M2 | operator policy | `profit-seeking` と `protocol-maintenance` の送信判定を unit test で固定する |
| M3 | dry-run execution planning | batch ごとに gas estimate と送信可否を出せる |
| M3.5 | backend catch loop | 新ブロック検知・state 永続化・restart resume・read-only 鍵不要起動・RPC chainId fail-fast ができる |
| M4 | local fork live tx | Anvil/local deploy で `batchLiquidateTroves` を実送信できる |
| M5 | Day-1 production hardening | `protocol-maintenance` 用の private relay、RPC quorum、永続 cursor、gas-only PnL ledger、Prometheus、alert、runbook を追加する |
| M5.5 | profit-seeking evidence design | 担保処分 route、在庫、gas、relay、RPC quorum、receipt classification を含む evidence schema を固定する |
| M6 | JIT / backstop executor（将来） | JPYdf 調達・SP top-up・清算実行を束ねる場合は新規 audited executor として設計し、route / loss cap / fork evidence を固定する |

## 安全条件

- protocol price feed が oracle failure を返した branch は送信しない。
- DF price feed source の `jpyFrozenSince` が非ゼロの branch は、JPY/USD
  共有 leg が soft-freeze 中のため scan 段階で fail-closed する。これは
  `fetchPrice()` が 24h freeze window 内では `oracleFailed=false` を返し得る
  ため、清算 bot 側で明示的に stale FX 価格での清算を避けるための guard とする。
- `ICR + buffer >= MCR` の候補は送信 batch から除外する。
- 空 batch は送信しない。
- branch ごとの enable flag を持つ。
- live execution は RPC chainId 一致と署名鍵 env var を必須にする。read-only / dry-run では署名鍵を読まない。`chain.rpc_read_timeout_ms` は初期値 15000 とし、block number / scan / chainId / RPC health / pre-submit planning read が返らない場合は daemon を詰まらせず retry path に戻す。
- branch config は空、重複 index、有効 branch の不完全設定を起動前に fail-fast する。
- `protocol-maintenance` でも無制限赤字清算はしない。live 起動時に正の `max_loss_wei_per_tx` と `max_gas_cost_wei` を必須にし、batch ごとにも両方を満たす必要がある。
- live `profit-seeking` は現行実装で fail-closed する。担保処分 route、inventory cost、slippage、gas、relay、RPC quorum を含む profit model が実装されるまで、正の `min_profit_wei` と `max_gas_cost_wei` があっても live 送信条件を満たさない。
- `gas_cost_stress_multiplier_bps` は `10000` 以上にし、`max_gas_cost_wei` / `max_loss_wei_per_tx` 判定前に gas cost へ適用する。`min_sp_offset_coverage_bps` は `10000` を初期値とし、下げる場合は partial SP offset と redistribution / JIT 判断を明示的に受け入れた扱いにする。
- `max_submissions_per_cycle` は初期値 1 とし、高 gas / candidate backlog 時に 1 catch cycle が無制限の live tx burst にならないようにする。上げる場合は tx 数ぶんの gas / loss budget と receipt escalation owner を launch evidence に含める。
- `submission_cooldown_blocks` は初期値 3 とし、live submission 後はその block 数だけ catch cycle を skip する。replacement / cancellation tracking が bot 外で確立していない限り、0 に下げない。
- policy 判定順は `execution.enabled`、SP offset coverage、stressed gas cap、`dry_run`、mode 別 profit/loss の順にする。dry-run でも高 gas / thin-SP の blocker を先に出すことで、launch 証跡が単なる `dry run` skip で埋まらないようにする。
- public launch gate では dry-run であっても `max_gas_cost_wei` / `max_loss_wei_per_tx` / `gas_cost_stress_multiplier_bps` / `min_sp_offset_coverage_bps` / `max_submissions_per_cycle` / `submission_cooldown_blocks` / `rpc_quorum_required` / `rpc_max_block_lag` / `rpc_read_timeout_ms` / `receipt_timeout_secs` の policy 値、high-gas escalation owner、SP shortfall / redistribution 判断 owner、JIT funding source、collateral disposal owner、failed receipt escalation owner を config evidence に含める。Maker Black Thursday 型の失敗は「清算候補がある」ことではなく「高 gas / thin-SP / keeper 失敗時に誰が何を許容するか」が未定なことなので、これらが placeholder のままなら No-Go とする。
- launch dry-run evidence は branch ごとの `totalJpydfDeposits`、`spOffsetCapacity`、`spOffsetCoveredCandidates`、planned batch の `gas` / `gasPrice` / `baseFeePerGas` / `priorityFeePerGas` / `maxFeePerGas` / `gasCost` / `stressedGasCost` / `spOffsetCoverageBps` / `decision`、top-level `rpcQuorum` を含まなければならない。各 planned batch は `profitEvidence.status = "unsupported"` と、未実装の担保処分・inventory・market depth・relay 理由も含める。`profitEvidence.liquidatorGasCompensation` は Core の WETH gas compensation と SP offset 部分の collateral gas compensation だけを計算し、SP/JIT gain・担保売却・inventory cost は含めない。`profitEvidence.gasForecast` は base fee / priority fee / max fee と stress multiplier の証跡であり、live 送信では同じ gas limit / gas price を tx に固定する。ただし private relay / replacement / cancellation / bundle failure handling の実装済みを意味しない。`profitEvidence.rpcQuorum` は provider health / block lag の partial evidence であり、scanner routing、provider voting、price-source quorum の実装済みを意味しない。`profitEvidence.receipt` は receipt timeout と live outcome classification set の証跡であり、dry-run では `not-submitted` のままにする。live submission は `state.receipt_ledger_path` または `state.path` 隣接の JSONL receipt ledger に `submitted` / `receipt-outcome` を append し、`submitted` には後続照合用の tx from / nonce / block metadata を best-effort で記録する。`state.pnl_ledger_path` または `state.path` 隣接の JSONL PnL ledger は receipt outcome ごとに gas-only row を append し、`gasUsed * planned maxFeePerGas` の gas-cost upper bound と classification を残す。ただし担保 gain 回収、inventory cost、処分 route 収益、effective gas price、full replacement / cancellation handling を含む disposal-aware PnL accounting の実装済みを意味しない。候補 0 の branch でも SP capacity と candidate count を証跡化する。
- `receipt-timeout` / `submit-and-forget` / `receipt-wait-error` は `reconcile-receipts` で後続照合できる。照合は configured receipt ledger を読み、receipt と best-effort `txFrom` / `txNonce` を read-only RPC で確認し、`confirmed-late-*` または `replacement-candidate` の証跡だけを JSONL に追記する。PnL ledger が設定されている場合は同じ outcome を gas-only row として追記し、receipt outcome 書込後に PnL 追記だけ失敗した場合は非 terminal の `pnl-ledger-error` marker を receipt ledger に残して再照合対象にする。送信・置換・cancel は行わず、replacement candidate は operator escalation / Safe runbook 側で扱う。cron / monitoring では `--fail-on-alert` を使い、`confirmed-late-reverted`、unknown / missing status、`replacement-candidate`、`pnl-ledger-error`、reconciliation `error` を非ゼロ終了として通知 path に載せる。
- live 実行では `safety.require_vault_guard = true` を標準とし、有効 branch ごとの `collateral_vault` を必須にする。Vault user flow pause 中、または `backingRatio() < safety.min_backing_ratio_wei` の branch では、運営 bot は liquidation tx を送信しない。
- Vault safety は scan 時と submit 計画時の両方で再確認する。scan 後に `emergencyDisableStrategy` / `writeoffStrategyPrincipal` が実行された場合も、submit 直前の再チェックで該当 branch を skip する。
- Strategy incident 時の writeoff / bot 再開判断は [Strategy Incident / Liquidation Safety Runbook](../../protocol/operations/runbooks/Strategy-Incident-Liquidation-Safety-Runbook.md) に従う。Aave / ERC4626(Morpho・Euler) / Lido / asset-transforming Strategy では、会計に出る損失と一時的な流動性制約の意味が異なるため、branch symbol ではなく登録 Strategy kind で判定する。
- hot key は gas 用 ETH だけを持つ運用にする。受領担保の処分・退避は bot 本体ではなく後続 executor / Safe runbook で扱う。

## 後続課題

- Anvil/local deploy で過少担保 Trove を作り、dry-run から live tx までの清算動線を検証する。
- liquidation event / Trove update event を購読して候補 cache を高速化する。
- gas-only PnL ledger を、collateral 受領、swap、在庫評価、effective gas price、relay / replacement cost を含む disposal-aware PnL 台帳へ拡張し、[`Liquidation-Management-Policy.md`](../../protocol/operations/policies/Liquidation-Management-Policy.md) の Day-2 profit-seeking hardening gate を満たす。
- Stability Pool 枯渇時の redistribution 収益差分を分類する。
- JIT top-up を自動化する場合は、SP deposit executor と atomic JIT executor を分けて設計し、[`Liquidation-Backstop-And-JIT-Policy.md`](../../protocol/operations/policies/Liquidation-Backstop-And-JIT-Policy.md) の gate を満たす。
- 複数 zombie Trove を網羅する indexer を追加する（LCG は core が保持する `lastZombieTroveId` 1 件のみを扱う）。
- shutdown / urgent redemption keeper は liquidation keeper から分離して追加する。

## 補助参考（正本ではない）

- Liquity v2 Core: `contracts/src/TroveManager.sol`
- LiquidationCandidateGetter: `contracts/src/LiquidationCandidateGetter.sol`
- Aave V3 Pool `liquidationCall`: https://aave.com/docs/aave-v3/smart-contracts/pool
- Compound III Liquidation / `isLiquidatable` / `absorb`: https://docs.compound.finance/liquidation/
- Maker Liquidation 2.0 keeper wallet security: https://docs.makerdao.com/smart-contract-modules/dog-and-clipper-detailed-documentation
- Chainlink Automation interfaces: https://docs.chain.link/chainlink-automation/reference/automation-interfaces
