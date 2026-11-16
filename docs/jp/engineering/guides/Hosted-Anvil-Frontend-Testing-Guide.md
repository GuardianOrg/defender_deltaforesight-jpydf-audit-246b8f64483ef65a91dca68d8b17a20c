# Hosted Anvil Frontend Testing Guide（ホスト Anvil でのフロント検証・テストトークン供給手順）

> **目的**: AWS 上の **hosted Anvil（staging）** にデプロイ済みフロントエンド（borrow など）を、ブラウザのウォレットから実際に操作してテストできるようにする手順書。特に「担保トークン（wstETH / USDC）をテストアカウントへ供給する方法」を正本化する。
>
> ⚠️ 仕様の正本は [`protocol/product/spec/`](../../protocol/product/spec/) / [`Product-Overview.md`](../../protocol/product/Product-Overview.md)。本書は**操作手順のみ**を扱う。ローカル（localhost anvil）でのフルスタック起動は姉妹文書 [`Local-Setup-And-Verification-Guide.md`](./Local-Setup-And-Verification-Guide.md) を参照。
>
> エンドポイント・chain id の正本は [`../reviews/2026-06-22-AWS-Hosted-Anvil-Staging-Review.md`](../historical-reviews/2026-06-22-AWS-Hosted-Anvil-Staging-Review.md)。

---

## 0. 前提と安全上の位置づけ（必読）

このチェーンは **resettable / 非 value-bearing な staging 専用インフラ**であり、設計として次の性質を持つ。

- **RPC は公開**（CloudFront 経由・CORS `*`・全 JSON-RPC メソッド許可）。誰でも tx 送信・状態変更が可能。
- **mint は開放**。担保トークンは mock faucet で、その `owner`（= デプロイ実行アカウント）が `mint()` 権限を持つ。現行デプロイの owner は **anvil 既定アカウント #0**（Foundry の公開既定鍵から導出されるアドレス）であり、`cast call <token> "owner()"` で誰でも確認できる。つまり**第三者も任意 mint できる**。
- 本書で使う鍵はすべて **anvil/Foundry の公開既定鍵**であり**秘密情報ではない**（`anvil` 起動時に毎回表示される。下記 mnemonic から導出可能）。

結論として:

- **このチェーンには価値あるものを一切置かない。** テスト専用。
- 他者の mint / trove 作成で**状態が勝手に変わり得る**前提でテストする。
- mint を塞ぎたい場合は §6（鍵を隠すのではなく、非公開 deployer で再デプロイ）。

Public stats には state profile を付与する。profile と seed の組み合わせは固定し、表示名だけを差し替えてはならない。

| Profile | Seeder | 用途 | 永続状態 |
| --- | --- | --- | --- |
| `day1-review` | `SeedFrontendDay1Review` | 公開User appのデータ・UX・通常txレビュー | dwstETH / dUSDCはcap-open・bootstrap debt・SP seedあり。branch 2–7はcap / supply / debt / SP deposit 0 |
| `hosted-demo` / `local-demo` | `SeedLocalDemo` | active 2 branchのoracle / redemption / queue / SP統合回帰 | dwstETH / dUSDCだけにdemo debtを持つ。Day-1残高ではない |

公開 frontend は `day1-review` を使い、`SeedLocalDemo` の統合 fixture は local / ephemeral Anvil で使う。通常 wallet / persona smoke は `evm_snapshot` を作成して終了時に revert するため、公開 review state に債務や redemption 結果を累積させない。queue / reward-history preparation のように事前状態を変更するコマンドは `day1-review` では fail-closed になる。

`day1-review` の `withdrawDelay=0` は Hosted Anvil の Aave-only 構成専用であり、[Parameters](../../Parameters.md) の mainnet Day-1 値を上書きしない。Lido 等の非同期 Strategy を含む deployment へ同じ seed を適用しない。seed は active branch が Aave 1本であることを検査し、構成が変わった場合は fail-closed になる。既発行の WithdrawRequest は設定変更前の `claimableAt` を保持する。

Hosted Anvilの `LocalAaveVenue` は実Aaveと同様にUnderlying流動性をaToken contractへ保持する。pool contract自身に流動性を残すと `AaveV3Strategy` のreserve-liquidity guardが0を返し、`sendToVault` が成功receiptのまま0返却になるため、deploy後checkではaTokenのUnderlying残高と実際のbuffer補充量を検証する。

### Liquidator の実Tx E2E

Liquidator の `scan -> plan -> submit -> receipt -> PnL ledger` を hosted
devnet で確認する場合は、個別に価格feedやECS desired countを操作せず、次の
専用コマンドを使う。

```bash
HOSTED_LIQUIDATOR_E2E_CONFIRM=run-hosted-liquidator-e2e \
LIQUIDATOR_PRIVATE_KEY="$HOSTED_ANVIL_ONLY_SIGNER_KEY" \
  bots/liquidator/scripts/e2e-hosted-anvil.sh
```

このコマンドは branch 0（dETH）専用で、CloudFormation outputから対象RPC、
ECS service、EventBridge ruleを解決する。開始前にLiquidatorが1/1で安定し、
stats publisher / oracle refresh / frontend synthetic / route-interestがすべて
有効で、Backend CloudWatch alarmsがすべてOKであることを確認し、SSM
Parameter Storeのno-overwriteロックを取得する。
実行中は4 ruleと常駐Liquidatorを止め、外側の
`evm_snapshot` 内でfrontend Open Borrow smokeにより2件目のTroveを作成して
`OnlyOneTroveLeft()` を回避し、価格低下と実清算Txを通す。

終了時trapは成功・失敗を問わず次を検証する。

1. `evm_revert` が成功する。
2. collateral/USD feedの`latestRoundData`が実行前と一致する。
3. `SortedTroves.getSize()`が実行前と一致する。
4. 一時的な清算receiptが`null`へ戻る。
5. 4本のEventBridge ruleが再有効化される。
6. Liquidator ECS serviceが元のdesired countへ戻りstableになる。
7. SSM実行ロックが現在runの所有物であることを確認して解放する。

証跡は既定で
`/private/tmp/jpydf-hosted-liquidator-e2e-<UTC timestamp>` に残る。
`summary.json`だけでPASSにせず、必ず`restoration.json.restoreOk=true`と
receipt/PnL ledgerの`confirmed-success`を合わせて確認する。snapshot revert後は
清算Tx hashがRPCから取得できなくなることが正常である。`restoration.json`が
falseの場合は通常テスト失敗として放置せず、EventBridge rules、ECS desired
count、oracle値、Trove数を直ちに手動確認する。強制終了等でSSMロックが残った
場合は、これらの復旧確認前にロックだけを削除して再実行してはならない。

stats publisher / one-shot export で profile を明示する例:

```bash
OPS_STATS_STATE_PROFILE=hosted-demo pnpm -C frontend/ops publish-stats-s3
pnpm -C frontend/ops export-stats -- --state-profile hosted-demo --out /private/tmp/jpydf-stats.json

# fresh deployment に公開 frontend review state を作る
DEPLOYER=$ANVIL_ACCOUNT_0_KEY forge script SeedFrontendDay1Review \
  --rpc-url https://d1idjvopviksk7.cloudfront.net --broadcast --slow
OPS_STATS_STATE_PROFILE=day1-review pnpm -C frontend/ops publish-stats-s3
```

---

## 0.9. Hosted Anvil への再デプロイ手順（2026-08-06 実施で確立）

devnet を wstETH 収束などで作り直す場合の手順。**この環境固有の制約が 2 つあり、知らないと必ず失敗する。**

### 制約 1: メモリ

anvil は devnet state を全てメモリに持つ。8 branch の full `DeployLiquity2` は約 416M gas あり、
**task memory 2 GiB では deploy 途中で OOM kill（exit 137）される**。ECS がタスクを再起動すると
EFS snapshot から復元されるため、**deploy が消えたうえにチェーンが巻き戻る**。2026-08-06 に
実際にこれが起き、213,080 → 99,771 の巻き戻りが発生した。#1456 で 8 GiB（1 vCPU での Fargate 上限）
へ引き上げ済み。それ未満に戻してはならない。

### 制約 2: 履歴 state の保持窓

このチェーンは直近 20〜99 ブロック程度しか履歴 state を保持しない（`--block-time 2` で数十秒分）。
`forge script` は fork をピン留めしたブロックの state を実行中ずっと読むため、**deploy / seed は
完走前に必ず `BlockOutOfRangeError` で落ちる**。script 実行フェーズだけ interval mining を止める。

```bash
RPC=https://d1idjvopviksk7.cloudfront.net
rpc() { curl -s -X POST "$RPC" -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}"; }

trap 'rpc anvil_setIntervalMining "[2]"' EXIT   # 失敗時も必ず戻す
rpc anvil_setIntervalMining '[0]'               # script 実行中は停止
rpc evm_setAutomine '[true]'                    # broadcast tx は個別に mine

DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 SALT=jpydf-hosted-1 \
  DF_TREASURY=$DEPLOYER DF_INTEREST_ROUTER_RECIPIENT=$DEPLOYER DF_INTEREST_ROUTER_OWNER=$DEPLOYER \
  DF_STRATEGY_KIND_0=aave DF_STRATEGY_WEIGHT_BPS_0=10000 DF_STRATEGY_CAP_0=<uint256 max> \
  DF_STRATEGY_KIND_1=aave DF_STRATEGY_WEIGHT_BPS_1=10000 DF_STRATEGY_CAP_1=<uint256 max> \
  DF_STRATEGY_KIND_2=none DF_STRATEGY_WEIGHT_BPS_2=0 DF_STRATEGY_CAP_2=0 \
  DF_STRATEGY_KIND_3=none DF_STRATEGY_WEIGHT_BPS_3=0 DF_STRATEGY_CAP_3=0 \
  DF_STRATEGY_KIND_4=none DF_STRATEGY_WEIGHT_BPS_4=0 DF_STRATEGY_CAP_4=0 \
  forge script DeployLiquity2Script --chain-id 31338 --rpc-url "$RPC" --broadcast --slow --unlocked
```

`SALT` は **`jpydf-hosted-1` に固定**する（2026-08-06 に採番。それ以前の値は記録が残っていない）。
同一 bytecode なら CREATE2 でアドレスが不変になる。ただし contract の bytecode や constructor が
変われば salt が同じでもアドレスは変わるため、**再デプロイ後は原則 3 surface の republish が必要**。

seed（`SeedFrontendDay1Review`）も同じ mining 停止処置が要る。`day1-review` は active branch が
Aave 1 本であることを検査するため、branch 0 / 1 は `aave` 単独で deploy すること。

### deploy 後に必要な作業

1. `frontend/df-shared/generate.ts deployment-manifest.json` で bindings 再生成
2. `frontend/app/.env.staging` を再生成し、**`NEXT_PUBLIC_COLL_<i>_CONTRACT_COLLATERAL_VAULT_DEPLOY_BLOCK` を手で入れる**。
   この値の生成器はリポジトリに存在せず、無いと `check:staging-hosting-env` が
   「claim queue が genesis から走査する」として fail する。broadcast receipt の最小ブロック
   （`broadcast/DeployLiquity2.s.sol/31338/run-latest.json`）を全 branch に入れてよい。
   branch 2–7 の vault は proxy 経由で broadcast に直接現れない
3. GitHub Environment `staging-infra` の `JPYDF_STAGING_APP_ENV` を更新
4. `Static Assets Staging Publish` を **`post_redeploy: true`** で dispatch。
   通常経路は「現行配信環境での baseline smoke 4 check 全 pass」を要求するが、
   再デプロイ直後は配信中バンドルが差し替え済み contract を指すため**構造上 pass しない**。
   `binding_recovery` は JPYdfToken 単独差し替え専用（baseline がちょうど 3 failure であることを要求）で
   full redeploy には使えない
5. ops worker image を rebuild / push し、**4 つの scheduled task の revision を差し替える**
   （StatsPublisher / OracleRefresh / RouteInterest / FrontendSynthetic）。
   task definition は image を digest で固定しているため、`:staging` タグを push しただけでは
   スケジュール実行は旧 image のまま動き続ける
6. console の `.env.staging` は Timelock が EFS snapshot より前にデプロイされていれば変更不要

---

## 1. 環境（現行 staging）

| 項目 | 値 |
| --- | --- |
| User app | `https://d2b8eew4spddv3.cloudfront.net`（別名 `https://staging.jpydf.com`・Basic Auth 保護） |
| RPC（ブラウザ／cast 共通） | `https://d1idjvopviksk7.cloudfront.net` |
| Ops dashboard | `https://d1ace8udcuxip3.cloudfront.net` |
| Public stats | `https://d2a7tsl4ibbvkb.cloudfront.net/jpydf-stats.json` |
| Chain id | **31338**（`0x7a6a`） |
| 構成 | ECS Fargate 上の `anvil --accounts 20 --balance 1000000 --block-time 2`（mainnet フォークではない・EFS state snapshot 付きの resettable devnet） |

> ALB 直アクセスは不可（403）。RPC は必ず上記 CloudFront URL を使う。

User app は CloudFront Function の Basic Auth 下にあり、未認証は 401、KeyValueStore を
読めない場合は 503 になる（Ops dashboard / Admin console / public stats / RPC は対象外）。
そのため User app に触れる smoke（§1.2 の各 check と §1.3 の公開ゲート、および
`check:staging-frontend-live`）は、実行前に credential を環境変数へ入れる。値は
`username:password` でも、CloudFront KeyValueStore の `authorization` に入っている base64
token でもよい。未設定なら従来どおり無認証で動く（保護前の環境・ローカル向け）。

```bash
# 値はチャットや手順書へ書かず、自分の shell だけに入れる
read -rs STAGING_USER_APP_BASIC_AUTH && export STAGING_USER_APP_BASIC_AUTH
```

credential の経路は 2 つある。fetch 経路（`check:staging-frontend-live`）は User app
origin のリクエストにのみ `Authorization` を付ける。ブラウザ系 smoke（browser-smoke /
wallet 系 / user-home）は User app への遷移を CDP で行い、User app origin に scope した
`Fetch` interception の 401 チャレンジ応答だけで認証する（agent-browser の
`set credentials` は認証済みページの cross-origin fetch（preflight）を壊すため使わない）。
いずれの経路も credential を RPC・public stats・第三者 origin へ送らない。

### 1.1. ブラウザテスト前の live deployment preflight

フロントの表示確認・ウォレット操作・tx 送信テストに入る前に、必ず repo ルートから次を実行する。

```bash
pnpm -C frontend/ops write:staging-app-env
pnpm -C frontend/ops check:staging-app-env
pnpm -C frontend/ops check:df-shared-live
pnpm -C frontend/ops check:live-deployment -- \
  --public-stats-url https://d2a7tsl4ibbvkb.cloudfront.net/jpydf-stats.json
```

この preflight は次を確認する。

- ignored local `frontend/app/.env.staging` が live `AddressesRegistry` と
  `frontend/df-shared/generated` から再構成され、古い branch address / token id /
  strategy address を含まない。operator が manifest / broadcast receipt から設定した
  `NEXT_PUBLIC_COLL_<N>_CONTRACT_COLLATERAL_VAULT_DEPLOY_BLOCK` は保持され、各 active
  branch で正の値として hosting guard を通る。
- generated binding と live chain の全 target contract bytecode が一致する。
- live RPC の `chainId` が `frontend/df-shared/generated/addresses.ts` と一致する。
- `JpydfToken` / `CollateralRegistry` / getter / `RedemptionHelper` / 各 branch の core contract / active underlying / `Multicall3` に bytecode が存在する。
- public stats JSON の `schemaVersion` / `chainId` / `blockNumber` / `generatedAt` / branch id・symbol が live RPC と生成済み binding に整合する。

このコマンドが失敗する場合、User app や Ops dashboard が表示されても devnet は tx テスト可能な状態ではない。先に hosted Anvil へ再デプロイまたは再 seed し、`frontend/df-shared/generated` と public stats を同じ live chain から作り直す。

Hosted Anvil は `--block-time 2` なので、public stats は数十から数百 block 遅れることがある。`check:live-deployment` の既定は stats publisher の 5 分間隔と CloudFront TTL 5 分を含め、`generatedAt` 660秒以内、block lag 360以内。tx テスト後や seed 後に即時確認したい場合は public stats を再発行し、CloudFront の `/jpydf-stats.json` を invalidation してから表示確認する。

`generatedAt` / `sourceBlock` が新しい場合でも、`stateProfile=hosted-demo` の数値は
demo seed と smoke tx を含む。たとえば `check:staging-wallet-open-borrow` は既定で
branch 0 に `2 wstETH / 300,000 JPYdf` の borrow を作るため、reset せずに繰り返すと
branch debt と trove count は増える。

mock oracle の `updatedAt` が stale warning 閾値に近い場合、hosted Anvil の公開既定 account から
permissionless mock aggregator を更新してから stats を再発行する。

```bash
pnpm -C frontend/ops refresh:staging-oracles -- --dry-run
pnpm -C frontend/ops refresh:staging-oracles
```

チェーン reset 後は既存 S3 stats の blockNumber が新チェーンより大きくなるため、**resettable staging に限り** stable key の block regression を許可する。`OPS_STATS_STATE_PROFILE=day1-review|hosted-demo` かつ `OPS_ENV!=production` の scheduled publisher は、この block regression 許可と publish 前の heartbeat block mining を既定で有効にする。staging CDK の既定は公開 frontend 用の `day1-review` とする。手動 publish で明示する場合は `OPS_STATS_ALLOW_BLOCK_REGRESSION=1` / `--allow-block-regression` と `OPS_STATS_HEARTBEAT_BLOCK=1` / `--heartbeat-block` を使う。production / non-resettable 環境では block regression と heartbeat mining を許可しない。

User app を AWS user app bucket へ同期する場合は、`frontend/app/out/jpydf-stats-local.json`
をアップロードしない。すでに上がっている場合は削除し、production の
`.github/workflows/static-assets-production-publish.yml` と同じく公開前に成果物から消して
`s3 sync --delete` の対象にする。hosted/staging/prod の user app は
`NEXT_PUBLIC_PROTOCOL_STATS_URL` で dedicated public stats endpoint を読む。

### 1.2. 自動 wallet / open-borrow transaction smoke

手動ブラウザ確認に入る前に、browser-enabled agent shell では次を実行する。

```bash
pnpm -C frontend/ops check:staging-user-home
pnpm -C frontend/ops check:staging-wallet-tx
pnpm -C frontend/ops check:staging-wallet-charge
pnpm -C frontend/ops check:staging-wallet-open-borrow
pnpm -C frontend/ops check:staging-wallet-open-borrow-oracle-failure
pnpm -C frontend/ops check:staging-wallet-open-borrow-rpc-failure
pnpm -C frontend/ops check:staging-user-personas
```

`check:staging-wallet-charge` は wallet 接続直後に user app の devnet `Charge`
（補充）ボタンを押し、mint confirm 後に `charged / 補充済み` 状態になることを確認する
on-connect faucet top-up の smoke。公開直前 / 公開直後の gate に必須で、これが落ちると
faucet top-up の regression を意味する。**静的資産の公開（`.github/workflows/static-assets-staging-publish.yml`
または手動 `s3 sync --delete` + CloudFront invalidation）の前後で必ず実行する。**
公開ゲートは 1 コマンドにまとめてある（下の §1.3）。

`check:staging-user-home` は user home の public stats 表示、live RPC 表示、CTA
route を確認する。wstETH / USDC の borrow / earn rows が public stats の dwstETH /
dUSDC と対応し、public stats freshness、oracle age、`priceDown=false`、JPY freeze
なし、live RPC の branch debt / Stability Pool deposits / vault backing / buffer /
pending withdrawals と一致していることを検査する。さらに desktop と compact viewport
で `/borrow/wsteth`、`/earn/wsteth`、`/borrow/usdc`、`/earn/usdc`、`/vault` に進めること、
browser console / page errors が空であることを確認する。

ローカル app server に devnet stats を差し替えて検証する場合は、stats JSON を一時出力して
別 shell の loopback HTTP から配信し、`--stats-url` と `--user-app-url` を指定する。Vault queue
shortfall のように public stats が意図的に `critical` の devnet evidence では
`--allow-critical-stats` を付ける。production / post-publish gate では付けない。

```bash
pnpm -C frontend/ops export-stats -- --out /private/tmp/jpydf-stats.json --pretty
pnpm -C frontend/ops serve-stats-json -- --file /private/tmp/jpydf-stats.json
pnpm -C frontend/ops check:staging-user-home \
  -- --user-app-url http://127.0.0.1:3003 \
  --stats-url http://127.0.0.1:3999/jpydf-stats.json \
  --allow-critical-stats
```

`check:staging-wallet-tx` は injected EIP-1193 provider で user app の ConnectKit
接続と微小額の self-transfer receipt を確認する。既定の送金額は実行時刻（ミリ秒）由来の wei 値で、
snapshot/revert 後に同じ nonce を再利用しても過去の tx hash と衝突しない。再現試験では
`STAGING_WALLET_TX_SEND_VALUE_WEI` または `--send-value-wei` で固定値を明示できる。`check:staging-wallet-open-borrow`
は同じ provider を使って user app の `/transactions` 画面へ
`openBorrowPosition` flow request を注入し、app 自身の transaction flow が
review 表示、必要な step の準備、`openTrove` 送信・confirm を通せることを確認する。
WETH 残高や allowance が不足している場合は `wrap ETH` / `approve underlying` も同じ
flow 内で送信される。既定では tx 送信直前に `evm_snapshot` を作り、成功・失敗にかかわらず終了時に `evm_revert` する。nonce・balance・Trove・SP・redemption state は常設状態へ残らない。状態を意図的に残す full integration run だけ `--keep-state` を明示する。

`check:staging-wallet-open-borrow-oracle-failure` は公開 app の HTTP transport に対し、
対象 branch の `PriceFeedProxy.source()` read だけをテストプロセス内で JSON-RPC error にする。
価格や branch state の他 read は通したまま、transaction review が `Status unavailable` を表示し、
主操作を無効化し、`eth_sendTransaction` と transaction artifact を一件も生成しないことを確認する。
注入はCDP session内だけで、hosted Anvilや公開bundleの状態を変更しない。

`check:staging-wallet-open-borrow-rpc-failure` は同じ review を保持したまま、RPC health probe の
`eth_blockNumber` だけを JSON-RPC error にする。global RPC health が `unavailable` へ遷移し、
review が RPC 回復待ちを表示して主操作を無効化すること、`eth_sendTransaction` と transaction
artifact が0件であることを確認する。永続RPC通知は `reserved` layoutかつ`position: relative`で
金融情報を覆わないことも検査する。Oracle fault と同時には指定できず、RPC endpoint、request
body、presigned URL は evidence に出力しない。

`check:staging-user-personas` は user home からの主要 persona をまとめて検査する。
borrower persona は `/borrow/wsteth` の market state / collateral / loan / interest rate を確認して
`openBorrowPosition` を実行し、同じポジションに対する JPYdf の一部返済と金利変更も実行する。
yield seeker persona は受け取った JPYdf を wstETH Stability Pool に `earnUpdate` で deposit し、
その一部を withdraw する。Home / Account / Activity では loan と Earn position の捕捉を確認する。
redeemer persona は `/redeem` の redemption fee / slippage tolerance / receive summary /
net value estimate を確認し、transaction review の最大 fee と branch 別最小受取額を検査して `redeemCollateral` を実行する。wstETH claim が残る場合は `/vault` から
`vaultRedeem` で underlying redemption まで実行する。protocol redemption 後に redeem 可能な
dToken claim が見つからない場合も失敗として扱う。最後に、手数料を含む全債務を返済するため、
devnet の流動性口座から実 ERC20 transfer で JPYdf を調達する。調達後に実際の `/loan/close` を開き、RPC 最新債務、wallet 残高、0.1% 実行余裕込み必要残高、担保返却、送信ボタンを確認してから、承認と `closeLoanPosition` を実行する。
各 transaction review の金額・金利・承認対象 token / spender / allowance、全 receipt の成功を必須とする。
WalletConnect / browser extension / 秘密鍵は使わず、同じ injected provider と hosted Anvil unlocked account
だけを使う。外部 JPYdf 調達を含む全状態変更は外側の snapshot 内に限定され、終了時に revert される。
Vault queue shortfall UX を必ず踏む evidence が必要な場合は
`STAGING_WALLET_TX_REQUIRE_VAULT_QUEUE=1` を付ける。このモードは
`expectedQueued > 0` の redeem preview がない devnet 状態では fail し、instant-only redeem を
queue evidence として扱わない。
queue shortfall の状態も自動で用意する場合は `prepare:staging-vault-queue` を使う。既定では
branch 0 の smoke account に dToken を持たせ、Vault buffer を Strategy 側へ寄せてから
`expectedQueued > 0` を確認する。この preparation 単体は状態を残し、`day1-review` では拒否されるため、
`hosted-demo` / local integration state で実行する。

公開 `day1-review` のAave-only構成では、キュー作成直後は buffer 不足で claim が失敗し、Allocator が Aave から `sendToVault` で補充した後は追加の時間ロックなしで claim できる。非同期 Strategy を有効化する場合は、その回収期間に合わせた `withdrawDelay` と queue smoke を別profileで定義する。

```bash
pnpm -C frontend/ops prepare:staging-vault-queue
STAGING_WALLET_TX_REQUIRE_VAULT_QUEUE=1 pnpm -C frontend/ops check:staging-user-personas
```

準備から persona smoke までの一括 command は preparation 前に外側の `evm_snapshot` を作り、
成功・失敗にかかわらず最後に `evm_revert` する。queue deposit は既定で borrow collateral の
2 倍になるため、前段の borrow が buffer を補充しても queued withdrawal を作れる。Aave-onlyかつ
`withdrawDelay=0` のprofileでは、実際のWithdrawRequest作成後に `sendToVault` でbufferを補充し、
同じrequest IDの `claim` 成功、`pendingWithdrawals=0`、Underlying受取額まで検証する。
`day1-review` で一時実行する場合は明示承認用 flag が必要になる。

```bash
STAGING_ALLOW_DAY1_REVIEW_MUTATION=1 \
STAGING_CONFIRM_DAY1_REVIEW_MUTATION=day1-review \
pnpm -C frontend/ops check:staging-user-personas-queue
```

Stability Pool の reward history evidence が必要な場合は
`prepare:staging-sp-reward-history` を使う。これは hosted Anvil の実 deposit
account を探し、必要に応じて `evm_increaseTime` / `evm_mine` で時間を進めた上で
`withdrawFromSP(0,false)` を送って、元本を引き出さずに実際の SP JPYdf reward
mint event を作る。公開 stats の `stabilityPoolRewardHistory` はこの event と
`StabilityPoolJpydfBalanceUpdated` から計算され、mock 値は使わない。この preparation も `day1-review` では拒否される。

```bash
pnpm -C frontend/ops prepare:staging-sp-reward-history -- --dry-run
pnpm -C frontend/ops prepare:staging-sp-reward-history
```

既定は branch 0 / 1 と 1時間 mine。対象を増やす場合は
`--branch-id 2 --branch-id 3`、時間幅を変える場合は `--mine-seconds <sec>` を付ける。
この stats を定期更新で維持するには、Backend stack の scheduled publisher が読む
`frontend/ops/Dockerfile.worker` の image も同じ frontend/ops 実装で rebuild/push
しておく。

既定は branch 0、`2 wstETH`、`300,000 JPYdf`、10% interest rate。状態が汚れて
ownerIndex 衝突が疑われる場合は次のように明示する。

```bash
STAGING_WALLET_TX_FLOW_OWNER_INDEX=1234567 \
pnpm -C frontend/ops check:staging-wallet-open-borrow
```

Backend stack の stats publisher は 5分ごとの EventBridge/ECS task で動くが、task は ECR の ops worker image に含まれる `frontend/df-shared/generated` を読む。再デプロイで contract address が変わった場合は、User app、静的 Ops dashboard、静的 Admin console、`frontend/ops/Dockerfile.worker` の image をすべて同じ generated bindings で rebuild/publish する。`pnpm -C frontend/ops check:staging-frontend-live -- --pretty` は3つの公開 frontend bundle に現行 chain ID、RPC、CollateralRegistry、JPYdfToken が含まれることを検証する。CloudWatch Logs に `getEntireBranchDebt returned no data ("0x")` が出る場合、scheduled publisher が旧 generated bindings を持っている。

緊急復旧で新しい task definition revision を登録した場合、`aws events put-targets`
だけを実行してはならない。CDK が生成する EventBridge 実行 role の
`ecs:RunTask` は revision 固定のため、target だけを更新すると全 schedule が
`FailedInvocations` になる。次の同期 CLI は旧・新 revision を一時許可してから
target を更新し、最後に新 revision だけへ戻して両方を検証する。

```bash
pnpm -C infra/cdk sync:scheduled-ecs-target -- \
  --profile jpydf-staging \
  --rule <eventbridge-rule-name> \
  --task-definition <new-task-definition-arn>
```

Stats Publisher、Oracle Refresh、Route Interest の revision を更新した場合は、各 rule
に対して実行する。通常の image 更新は CDK deploy で task definition、target、IAM
policy をまとめて更新する。

### 1.3. 静的資産 公開ゲート（faucet を含む一括 smoke）

静的資産（user app / admin console / ops）を公開する前後で実行する必須ゲート。browser-enabled
agent shell で 1 コマンドにまとめてある。

```bash
pnpm -C frontend/ops check:staging-publish-smoke -- --phase baseline-live
```

evidence と commit の対応を保証するため tracked worktree が clean でなければ、この command は開始前に失敗する。

これは現在配信中の環境に対するbaseline確認である。`check:staging-frontend-live -- --pretty` → `check:staging-browser-smoke`
→ `check:staging-wallet-tx` → `check:staging-wallet-charge` を順に実行する。最後の
`check:staging-wallet-charge` が on-connect faucet top-up（devnet `Charge` / 補充）
の regression を捕捉する。どれかが落ちたら公開しない（fail-closed）。結果は既定で
`/tmp/jpydf-staging-publish-smoke-evidence.json` にschema v2 JSONとして保存される。このJSONを
evidence保存先へuploadし、6時間以内に失効するS3 presigned GET URLなどのdirect HTTPS URLを
保持する。JSONは各checkの構造化結果とSHA-256、対象URL、観測した配信commitを保持する。

`.github/workflows/static-assets-staging-publish.yml` は CI 上で agent-browser を
起動できないため、この browser smoke 自体は実行しない。代わりに dispatch 時に
`pre_publish_smoke_commit`（workflowのcommit SHA）、
`pre_publish_smoke_evidence_url`（上記baseline JSONのdirect HTTPS URL）、および
`post_publish_smoke_evidence_url`（まだ存在しないpost evidence object用のpresigned GET URL）を
必須入力とする。post用には同じobject keyへ書くpresigned PUT URLもoperator側で保持する。
workflowはupload前にbaseline evidenceを取得し、現commit、6時間以内、4 check全passを
fail-closedで検証する。CI側が続けて実行する非ブラウザguardは
（`check:staging-hosting-env` / `check:staging-protocol-stats` /
`check:staging-built-app-bundle` / `check:df-shared-live`）と `s3 sync --delete` +
CloudFront invalidation、および `check:live-deployment` である。build時は3 surfaceへworkflowの
full SHAを埋め込み、upload前のartifact guardでも一致を確認する。
3 surfaceのcommit driftを作らないため、このworkflowの`target`は`all`固定である。

CloudFront invalidation完了後、workflowがpost evidenceを待っている間に同じcommitのclean checkoutで
次を実行し、生成JSONを事前に用意したPUT URLへuploadする。

```bash
STAGING_PUBLISH_SMOKE_EVIDENCE_PATH=/tmp/jpydf-staging-post-publish-smoke-evidence.json \
pnpm -C frontend/ops check:staging-publish-smoke -- --phase post-publish

curl --fail --request PUT --upload-file /tmp/jpydf-staging-post-publish-smoke-evidence.json \
  "$POST_PUBLISH_SMOKE_EVIDENCE_PUT_URL"
```

workflowは最大30分待機し、`startedAt`がpublish完了後、`sourceCommit`と`deployedCommit`が
workflow SHA、3 target URLがstack output、4 checkの詳細結果が全passの場合だけ成功する。
未実行をsuccessとして扱わない。

Admin console の static publish を初めて使う前に、更新済み `Jpydf-staging-StaticSites` を
CDK deploy し、`AdminConsoleBucketKmsKeyArn` output と Admin bucket/KMS/CloudFront 権限を持つ
OIDC publish role を反映する。`staging-infra` Environment には
`JPYDF_STAGING_CONSOLE_ENV`（`frontend/console/.env.staging` の内容）も設定する。
このenvは `VITE_CONSOLE_TIMELOCK_ADDRESS` と、CREATE receiptの正のblock番号を入れた
`VITE_CONSOLE_TIMELOCK_FROM_BLOCK` を必須とする。どちらかが欠けるdirect modeのenvは
`check:staging-hosting-env` が拒否し、Admin consoleを公開しない。
CDKのstaging既定subjectは
`repo:deltaforesight/jpydf-v2:environment:staging-infra`である。

## 2. アカウント（anvil 既定）

| 用途 | index | アドレス |
| --- | --- | --- |
| faucet owner（mint 用） | #0 | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` |
| Day-1 review bootstrap / LP 在庫 | #1 | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` |
| ブラウザ E2E 用 | #7 | `0x14dc79964Da2c08B23698B3D3Cc7Ca32193d9955` |

- hosted Anvil は `--mnemonic` 未指定のため、**anvil / Foundry 標準の既定アカウント**をそのまま使う（#0 が faucet owner）。
- **秘密保護のため、鍵・mnemonic の値は本書に記載しない**。既定鍵はローカルで `anvil` を一度起動すれば同じ accounts / private keys が表示される（Foundry の公開既定値）。取得した鍵は環境変数か foundry keystore（`cast wallet import`）経由で渡し、ファイル・チャットに残さない。
- owner の確認: `cast call <token> "owner()(address)" --rpc-url $RPC`（= #0 アドレスが返る）。

## 3. 担保トークン（chain 31338）

borrow で**預けるのは underlying トークン**。dToken は Vault が自動 mint するのでユーザーは直接触らない。

| Branch | 預ける underlying | dec | tap 公開？ |
| --- | --- | ---: | --- |
| dwstETH | wstETH | 18 | 100/日 |
| dUSDC | USDC | 6 | **無効（owner mint のみ）** |
| dETH / dUSD-A / dBTC / dUSD-B / dJPY / dJGB | TBD | — | inert・faucetなし |

コントラクトアドレスは本書に固定値を書かない。正本は現行 devnet bindings `frontend/df-shared/generated/addresses.ts`（chainId 31338）で、再デプロイのたびに再生成されて変わる。

> **アドレスが変わったら（再デプロイ後など）の取り直し方**: 同じ deployer + salt なら CREATE2 でアドレスは不変。変わった場合は `frontend/df-shared/generated/addresses.ts` を再生成するか、`deployment-manifest.json`（`.dfYield[i].underlying`）から候補アドレスを集め、各々に `cast call <addr> "symbol()(string)"` を投げて wstETH/USDC を同定する（owner も `owner()` で確認）。

## 4. テストトークンの供給

```bash
RPC=https://d1idjvopviksk7.cloudfront.net
ME=0x70997970C51812dc3A010C7d01b50e0d17dc79C8

# 署名鍵は本書に値を載せない。anvil 既定 #0(owner)/#1 の鍵を各自の環境にセットする
# （ローカルで `anvil` を一度起動すると同じ既定鍵が表示される）:
#   export OWNER_KEY=<anvil 既定 #0 の private key>
#   export ME_KEY=<anvil 既定 #1 の private key>

# トークンアドレスは再デプロイごとに変わるため本書に固定値を書かない。
# 現行 devnet bindings frontend/df-shared/generated/addresses.ts（chainId 31338）から
# branch 0 / branch 1 の underlying（wstETH / USDC）のアドレスを取得してセットする:
#   export WSTETH=<bindings の wstETH アドレス>
#   export USDC=<bindings の USDC アドレス>
```

**A. owner で任意額 mint（推奨・USDC は必須）** — 金額は最小単位（USDC=6dec、wstETH=18dec）:

```bash
cast send $USDC   "mint(address,uint256)" $ME 5000000000000            --rpc-url $RPC --private-key $OWNER_KEY  # 5,000,000 USDC
cast send $WSTETH "mint(address,uint256)" $ME 10000000000000000000000  --rpc-url $RPC --private-key $OWNER_KEY  # 10,000 wstETH
```

**B. 公開 tap（owner 不要・少額向け）** — クールダウンあり、USDC は無効:

```bash
cast send $WSTETH "tap()" --rpc-url $RPC --private-key $ME_KEY    # +100 wstETH（1回/日）
```

**残高確認**:

```bash
cast call $USDC "balanceOf(address)(uint256)" $ME --rpc-url $RPC
```

## 5. ウォレット接続してフロントでテスト

1. ウォレット（MetaMask 等）にネットワーク追加: **RPC `https://d1idjvopviksk7.cloudfront.net` / Chain ID `31338` / 通貨 ETH**。
2. **アカウント #1 の秘密鍵をインポート**（§2：anvil 既定 #1。鍵の値は各自の環境で取得）。各アカウントは 1,000,000 ETH を持つ。
3. App → **Borrow** → 担保を選んで deposit。
   - 最低借入額 **MIN_DEBT = 300,000 JPYdf**。
   - trove を開くと **~0.0375 ETH 相当の WETH gas compensation** が必要（WETH を持っていれば充足。Zapper が ETH を wrap するケースもある）。
   - デモ価格の目安: 1 ETH ≈ 600,000 JPY / 1 USD ≈ 150 JPY。

AWS Staging Devnet の user app では、wallet 接続後に TopBar の運用導線と言語切替の間にある **Charge / 補充**
ボタンから接続中 wallet へテスト資産を補充できる。このボタンは
`chainId=31338` かつ deployment flavor が Devnet の build にのみ表示され、
ETH が 1000 ETH 未満のときだけ `anvil_setBalance` で 1000 ETH まで補充し、
mock USDC owner から 1,000,000 USDC を mint する。USDC mint は receipt 成功まで待ってから
完了表示にする。WETH は Borrow flow の wrap step で ETH から用意する。

自動ブラウザ E2E では hosted app の dev wallet connector を使える。`localStorage["jpydf-v2:dev-wallet-account"]` に account index（例: `"7"`）を入れると、WalletConnect を使わず anvil unlocked account で `eth_sendTransaction` まで進められる。

## 6. チェーンがリセットされたとき / mint をロックしたいとき

- **状態が消えた場合**: hosted Anvil は staging 専用の resettable devnet であり、Fargate タスク再起動・stack 更新・手動 reset の直後はチェーン状態が初期化されることがある。単なる wallet 残高不足なら §4 の mint / tap だけで足りるが、`check:live-deployment` が bytecode missing、または stats publisher が `returned no data ("0x")` を出す場合は、**contract code も消えている**ため §4 だけでは復旧しない。
- **公開 frontend の contract code が消えた場合の復旧順**: `contracts/deployment-context-latest.json` の `salt` と同じ deployer で `./deploy hosted-anvil --rpc-url https://d1idjvopviksk7.cloudfront.net --salt <salt> --skip-confirmation --slow` を実行し、fresh deployment に `SeedFrontendDay1Review` を broadcast する。その後 `OPS_ENV=staging OPS_STATS_STATE_PROFILE=day1-review OPS_STATS_ALLOW_BLOCK_REGRESSION=1 OPS_STATS_HEARTBEAT_BLOCK=1 pnpm -C frontend/ops publish-stats-s3` で public stats を再発行し、`pnpm -C frontend/ops check:live-deployment -- --public-stats-url https://d2a7tsl4ibbvkb.cloudfront.net/jpydf-stats.json` と `STAGING_USER_HOME_EXPECTED_STATE_PROFILE=day1-review pnpm -C frontend/ops check:staging-user-home` を通す。統合 fixture が必要な場合は別の local / ephemeral Anvil に `SeedLocalDemo` を使う。再デプロイで address が変わった場合は User app、Ops dashboard、Admin console、ops worker image の `frontend/df-shared/generated` を更新し、全 frontend を再配信して `check:staging-frontend-live` と `check:staging-browser-smoke` を通す。
- **EFS state 保存中の RPC liveness**: Anvil は 60 秒ごとの state を task-local file へ書き、background copier が1秒間変化しないcopyを完全なJSONとしてparseできた場合だけ、変更済みsnapshotを `state.json.next` から EFS `state.json` へ atomic rename する。末尾文字だけで完成判定してはならず、EFS へ直接 `--state` を向けてもならない。変更後は少なくとも state interval 2 周以上、`eth_blockNumber` の増加、FrontendSynthetic の連続成功、Anvil log の block-time gap が caller timeout を超えないことを確認する。
- **ECS task restart への備え**: HostedAnvil stack は1 vCPU / 2GBでAnvilの `--state /tmp/anvil-state.json --state-interval 60` を使い、上記background copierだけが EFS mount を更新する。stateful singletonのrolling replacementは旧taskを停止してから新taskを起動し、同じsnapshotから分岐した2 chainをALBへ同時登録しない。旧targetのconnection drainは15秒に固定するため、deploy時は短いRPC downtimeを許容する。ALBは30秒間隔・10回連続失敗までtaskを置換せず、長いintegration smoke中の一時的な無応答でtaskを終了しない。起動wrapperは移行中に残ったwriterを考慮し、EFS stateを完全なJSONとしてparseできるまで最大3分待つ。それでも不完全なら `state.json.corrupt-<UTC timestamp>` へ自動退避し、正常なEFS snapshotはtask-local fileへcopyしてからAnvilを起動する。正常なtask restartではsnapshotからcontract code / trove / stats sourceをloadする。自動退避でfresh起動した場合は上のcontract redeploy手順で復旧する。
- **第三者 mint を塞ぎたい場合**: 公開既定鍵を隠すのは無意味（公開鍵のため）。**非公開の deployer 鍵 / カスタム mnemonic で再デプロイ**し、faucet の `owner()` を自分だけが鍵を持つアドレスにする。必要なら RPC 側も origin-verify 以上の認証で絞る。ただし staging の目的（誰でも触れる使い捨て UX デモ）上、開放のままで問題ないことが多い。

---

## 検証記録（時点スナップショット）

- **2026-06-24 / chain 31338**: 本手順（§4 A+B）を実行し、アカウント #1（`0x7099…79C8`）に WETH 10,000・USDC 5,000,000・USDT 5,000,000・sUSDS 5,000,000・XAUT 10,000 を供給できることを確認（before 全 0 → after 反映、全 tx `status=0x1`）。faucet owner はすべて #0（`0xf39F…2266`）であることを `owner()` で確認。
- **2026-07-05 / chain 31338**: HostedAnvil flavor で再デプロイ・seed し、`check:live-deployment` で chainId 31338 / bytecode 100/100 / public stats schemaVersion 3 / block 8264 / health ok を確認。ECS stats publisher の staging worker も現行 generated binding と ops source に更新し、scheduled/manual task が schemaVersion 3 の stats を S3 に publish できることを CloudWatch log と CloudFront で確認。User app は `Stats block 8264`、`58M JPYdf`、TVL `¥91M` を表示。dev wallet #7（`0x14d…955`）で WETH 1 / JPYdf 300,000 の borrow flow を実行し、Approve WETH `0x3fb495d576b97bc79613fc5646fa87e3e4bfce544b43b45aa9cb8602d2e505ef` と Open Position `0xdd9c385cf1f8eaba3abb05a1a3d3777dc51932fb5d99d37a941a24b3756ed2c7` の receipt がどちらも `status=0x1`。Ops dashboard で dETH troveCount 5 / 総合担保率 157.2% / 稼働ブランチ 5/8 を確認。
- **2026-07-10 / chain 31338**: ECS Anvil task restart 後に chain head が old stats block より低くなり、stats publisher が `totalSupply returned no data ("0x")` / `getEntireBranchDebt returned no data ("0x")` で失敗して public stats が stale 化した。同一 salt `staging-20260708-stats-reset-1` で再デプロイし、`SeedLocalDemo`、manual `publish-stats-s3 --state-profile hosted-demo --allow-block-regression --heartbeat-block` を実行。`check:live-deployment` は bytecode 100/100、price feeds 8/8、public stats block 3993 / age 40s / health ok で通過。`check:staging-user-home` は desktop/compact と `/borrow/weth`、`/earn/weth`、`/borrow/usdc`、`/earn/usdc`、`/vault` route、public stats freshness、oracle age、live branch debt / Stability Pool / vault buffer 整合を確認して通過。
- **2026-07-11 / chain 31338**: EFS の `state.json` が 1,048,576 bytes で途中終了し、Anvil task が `EOF while parsing a string` で再起動を繰り返して RPC が 504 になった。service を停止して破損 snapshot を `state.corrupt-20260711T0037Z.json` として保持し、fresh state で再起動。同一 salt `staging-20260710-day1-review-1` から再デプロイしたが現行 source の生成結果では一部 address が以前と変わったため、manifest から `frontend/df-shared/generated` と staging app env を再生成した。`SeedFrontendDay1Review`、public stats block-regression publish、CloudFront invalidation を実行し、`check:df-shared-live` は 99 contract address、`check:live-deployment` は bytecode 100/100・price feed 8/8 を確認して通過した。ops worker image `day1-1211b361`（digest `sha256:a18483918d6d1ed2a3983a097198d76dced8e659e0bb27d2e5fa304bd432815e`）へ Stats Publisher / Oracle Refresh / Route Interest の EventBridge target を更新し、Oracle Refresh は 6 feed 更新・exit 0、Stats Publisher revision 7 は public stats block 1214 / source lag 2 秒・exit 0 を確認した。その後、target は新 revision、EventBridge role の `ecs:RunTask` は旧 revision のままという不整合で schedule が全件失敗していたため、3 worker の role を同期して復旧した。以降の緊急 revision 更新は `sync:scheduled-ecs-target` を使用する。
- **2026-07-11 / chain 31338 / queue 即時請求**: integration smoke 中の task 置換で EFS `state.json` が 4,194,304 bytes で再び途中終了したため、HostedAnvil task を 1 vCPU / 2GB、state interval 60秒、ALB 連続失敗10回へ更新し、起動時の破損 JSON 退避を追加した。同一 salt で再デプロイし、Aave-only dETH / dUSDC を `withdrawDelay=0` で seed。ops worker image `day1-queue-sync-20260711`（digest `sha256:05aa3d380631a5d9095dbb07422ba60031c0eacf17bf632d7a960aefac894586`）を Stats Publisher revision 8 / Oracle Refresh revision 4 / Route Interest revision 4 へ同期した。`check:df-shared-live` は 99 address、`check:live-deployment` は bytecode 100/100・price feed 8/8、`check:staging-user-home` は両 branch の `vaultWithdrawDelaySec=0` を確認。外側 snapshot 内で 2 WETH の request `1` を作り、Aave refill `0xbb18e62bcf8dc87bde0eb17ba3df29125a9f2c690af5b60ec59c89832dfbaef7` 後に claim `0x9af75b4941441fd1323c4113c91f19c9b4bf5192b303f9e844801c1a5736246f` が成功し、pending 0・受取額 2 WETH を確認して state を revert した。
