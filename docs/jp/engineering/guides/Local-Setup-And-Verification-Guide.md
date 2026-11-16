# Local Setup & Verification Guide（ローカル起動・検証手順）

> **目的**: 第三者がクリーンな環境から jpydf-v2 のフルスタック（🔵 Liquity v2 コア + 🟢 dToken/Strategy/Oracle/Zapper コントラクト + subgraph + フロントエンド3サーフェス）を **mainnet なしのローカル anvil** で立ち上げ、ブラウザで動作を確認できるようにする手順書（runbook）。
>
> ⚠️ **仕様の正本は [`protocol/product/spec/`](../../protocol/product/spec/)**（および入口の [`Product-Overview.md`](../../protocol/product/Product-Overview.md) / [`Parameters.md`](../../Parameters.md)）。本書は起動手順のみを扱い、アーキ・パラメータは再掲しません。
>
> 直近の時点検証は末尾の「検証記録」に残します。本書本文は特定 commit の状態を正本化せず、`develop` または検証対象ブランチで再実行できる手順として維持します。

---

## 0. 検証時の環境（参考バージョン）

| ツール | バージョン | 用途 |
| --- | --- | --- |
| Foundry（forge / anvil / cast） | 1.7.1 | コントラクト deploy・ローカルチェーン |
| Node.js | **22.x**（contracts/frontend）＋ **20.18.1**（graph-cli 専用） | — |
| pnpm | 8+（10.x で確認） | monorepo 依存管理 |
| Docker | 28.x | graph-node / postgres / ipfs |
| graph-cli | 0.97.x（node 20 で動作） | subgraph codegen / deploy |

> **Node を 2 系統使う点に注意**。frontend/contracts は Node 22 で動くが、`graph-cli`（subgraph）は Node ≥ 20.18.1 必須。[nvm](https://github.com/nvm-sh/nvm) で両方入れておき、subgraph 操作時のみ `nvm use 20.18.1`（または PATH 先頭に 20.18.1 を置く）。

以降のコマンドは、クローン先リポジトリのルートを `$REPO` と書きます（例: `export REPO=~/work/jpydf-v2`）。**Foundry のルートは `$REPO/contracts`**。

---

## 1. リポジトリ取得 & 依存インストール

```bash
# サブモジュール（forge-std / OpenZeppelin / Solady / V2-gov）も同時取得
git clone --recurse-submodules https://github.com/deltaforesight/jpydf-v2 "$REPO"
cd "$REPO"
git checkout develop          # または検証対象のブランチ/タグ

# monorepo 全 workspace を一括インストール（ルートで実行）
pnpm install
```

- submodule が空になる場合は `git submodule update --init --recursive` を実行。
- `corepack` が署名鍵エラーで落ちる環境では `npx -y pnpm@8.15.8 install` で代替（pnpm 10 が使えるなら不要）。

---

## 2. ローカルチェーン（anvil）

別ターミナルで常駐させる:

```bash
~/.foundry/bin/anvil --host 127.0.0.1 --port 8545 --chain-id 31337 --base-fee 0 --gas-limit 60000000
```

- deployer / デモ操作にはすべて anvil の標準テストアカウント #0 を使う（公開鍵なので秘匿不要）:
  - address `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
  - private key `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

---

## 3. コントラクト deploy（8 ブランチ）

```bash
cd "$REPO/contracts"
PATH=~/.foundry/bin:$PATH ./deploy local --skip-confirmation
```

- `local` プリセットで chain-id 31337 / deployer = anvil#0 / RPC = `http://127.0.0.1:8545` が自動設定される。
- 8ブランチをdeployする。dwstETH / dUSDCだけがactive配線され、dETH / dUSD-A / dBTC / dUSD-B / dJPY / dJGBはinertとなる。`Deployment complete.`が出れば成功。
- demo trove path は `./deploy` から削除済み。データは用途に応じて `SeedFrontendDay1Review` または `SeedLocalDemo` で投入する。
- ⚠️ **salt 未指定だとデプロイのたびに `block.timestamp` を salt に使うため、全コントラクトアドレスが毎回変わる**。再デプロイしたら §6 の env 生成を必ずやり直すこと。固定したい場合は `--salt <任意文字列>` を付ける。
- 生成物: `contracts/deployment-manifest.json`（フロント env の元）と `contracts/deployment-context-latest.json`（subgraph が JpydfToken を読む元）。

---

## 4. Multicall3 を注入

フロントは `0xcA11bde05977b3631167028862bE2a173976CA11` の Multicall3 を前提とするが、ローカル deploy には含まれない。mainnet のバイトコードを取得して anvil に流し込む（public RPC で可）:

```bash
MC=0xcA11bde05977b3631167028862bE2a173976CA11
CODE=$(~/.foundry/bin/cast code $MC --rpc-url https://eth.llamarpc.com)   # 任意の mainnet RPC
~/.foundry/bin/cast rpc anvil_setCode $MC "$CODE" --rpc-url http://127.0.0.1:8545
# 確認（長いバイトコードが返れば OK）
~/.foundry/bin/cast code $MC --rpc-url http://127.0.0.1:8545 | head -c 20; echo
```

---

## 5. profile 別データ投入

公開frontendと同じDay-1 review stateを使う場合は、dwstETH / dUSDCのbootstrapとSP seedだけを作る。branch 2–7はUnderlying未binding、cap / supply / debt / SP deposit 0のinert stateに保つ。

```bash
cd "$REPO/contracts"
DEPLOYER=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  PATH=~/.foundry/bin:$PATH \
  forge script SeedFrontendDay1Review --rpc-url http://127.0.0.1:8545 --broadcast
```

active 2 branch の redemption / oracle / queue をまとめて検証する integration state では `SeedLocalDemo` を使う。

配線済み active 2 branch（dwstETH / dUSDC）に demo の Trove / Stability Pool 預入 / Strategy 配分 / 遅延出金予約を作る:

```bash
cd "$REPO/contracts"
DEPLOYER=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  PATH=~/.foundry/bin:$PATH \
  forge script SeedLocalDemo --rpc-url http://127.0.0.1:8545 --broadcast
```

- MIN_DEBT 300k / gas compensation 0.0375 ETH を織り込み済み。`Seed complete.` が出れば成功。
- これにより各ブランチに demo 価格も設定される（別途 `setPrice` は不要）。

---

## 6. フロントエンド env 生成（`.env.local` ＋ bindings）

frontend は **app（Next.js）**と **console/ops（Vite）**で参照経路が異なる。両方を deployment-manifest から生成する。

### 6-1. app 用 `.env.local`

env 生成スクリプトは**コントラクトアドレスのみ**を出力する。チェーン設定（RPC / Multicall / WalletConnect / Subgraph URL / 画面フラグ）は別途必要なので、**下記の設定ブロックを先頭に置き、その後ろにアドレスを追記**する:

```bash
cd "$REPO"
# (a) 設定ヘッダーを書き出す（付録B の内容）
cat > frontend/app/.env.local <<'EOF'
NEXT_PUBLIC_ACCOUNT_SCREEN=true
NEXT_PUBLIC_DEPLOYMENT_FLAVOR=Local
NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID=local-dev
NEXT_PUBLIC_CHAIN_BLOCK_EXPLORER=Anvil|http://127.0.0.1:8545
NEXT_PUBLIC_CHAIN_CURRENCY=Ether|ETH|18
NEXT_PUBLIC_CHAIN_ID=31337
NEXT_PUBLIC_CHAIN_NAME=Anvil
NEXT_PUBLIC_CHAIN_RPC_URL=http://127.0.0.1:8545
NEXT_PUBLIC_CHAIN_CONTRACT_MULTICALL=0xcA11bde05977b3631167028862bE2a173976CA11
NEXT_PUBLIC_AIRDROP_VAULTS=false
NEXT_PUBLIC_SAFETY_MODE_CHECK=false
NEXT_PUBLIC_SUBGRAPH_CHECK=false
NEXT_PUBLIC_SUBGRAPH_URL=http://localhost:8000/subgraphs/name/jpydf/jpydf
NEXT_PUBLIC_DEV_WALLET=true
NEXT_PUBLIC_SAFE_API_URL=
NEXT_PUBLIC_SHOW_DATA_SOURCES=true
EOF

# (b) deploy 済みアドレスを追記
cd "$REPO/contracts"
pnpm tsx utils/deployment-manifest-to-app-env.ts deployment-manifest.json >> ../frontend/app/.env.local
```

- `NEXT_PUBLIC_DEV_WALLET=true` でブラウザから anvil アカウントを直接「接続」できる（WalletConnect 不要・`local-dev` のダミー ID で動く）。
- ⚠️ **`NEXT_PUBLIC_SUBGRAPH_URL` は `.../name/jpydf/jpydf`**。短い形式や古い `liquity2/version/latest` 形式では graph-node が解決できない。
- アドレス生成時に inert ブランチ（5/6/7）は `Skipping inert branch …` と stderr に出るが正常。
- mainnet / AWS staging の公開配信では、Vault の delayed claim event scan を genesis から始めないため、各 active branch の `NEXT_PUBLIC_COLL_<N>_CONTRACT_COLLATERAL_VAULT_DEPLOY_BLOCK` が必要。manifest の `dfYield[N].collateralVaultDeployBlock` があれば `deployment-manifest-to-app-env.ts` が自動出力する。local 開発では未設定でも app は fallback するが、公開 hosting guard は未設定を失敗扱いにする。

### 6-2. console / ops 用 bindings

```bash
cd "$REPO/contracts"
pnpm tsx ../frontend/df-shared/generate.ts        # 既定で deployment-manifest.json を読む
```

- ⚠️ **必ず `contracts/` ディレクトリから実行**。リポジトリルートで `pnpm tsx …` すると `ERR_PNPM_RECURSIVE_EXEC_FIRST_FAIL: Command "tsx" not found` になる（root には tsx が無い）。スクリプトは自身の位置から repo ルートを解決するので、どの作業ディレクトリでも manifest/ABI を見つけられる。
- `frontend/df-shared/generated/{addresses,abis}.ts` が 8 ブランチ分生成されれば成功。

---

## 7. subgraph 起動

graph-cli は Node 20.18.1 で実行する。

```bash
nvm use 20.18.1          # もしくは export PATH=~/.nvm/versions/node/v20.18.1/bin:$PATH
cd "$REPO/subgraph"

# (a) graph-node を起動（Docker。--reset で旧 volume を消去しジェネシス不一致を防ぐ）
./start-graph --reset    # docker compose up（フォアグラウンド常駐 → 別ターミナル or バックグラウンド）

# (b) コード生成（deploy 前に必須。怠ると AssemblyScript parse error）
pnpm graph codegen

# (c) subgraph を作成 & デプロイ
printf 'y\n' | ./deploy-subgraph local --create --version v1
```

- `(a)` は常駐プロセス。別ターミナルで起動するか、`./start-graph --reset > /tmp/graph.log 2>&1 &` で背景化。`graph-node` のログに `Starting GraphQL HTTP server at: http://localhost:8000` が出れば準備完了。
- `(c)` で新しい JpydfToken を検出すると `Update networks.json? [Y/n]` と聞かれるので `y`（上の `printf` で自動応答）。
- 同期確認:
  ```bash
  curl -s -X POST http://localhost:8000/subgraphs/name/jpydf/jpydf \
    -H 'Content-Type: application/json' \
    -d '{"query":"{_meta{block{number}hasIndexingErrors}}"}'
  # => {"data":{"_meta":{"block":{"number":<anvilのブロック>},"hasIndexingErrors":false}}}
  ```

---

## 8. フロントエンド起動（3 サーフェス）

Node 22 に戻して（`nvm use 22`）実行:

```bash
# app（Next.js, :3000）— local URL では build-deps が repo 内 schema に fallback
cd "$REPO/frontend/app"
pnpm build-deps          # graphql codegen → uikit ビルド → panda。runtime data には subgraph 同期が必要
pnpm dev                 # http://localhost:3000

# console（Vite, :3001）— 別ターミナル
cd "$REPO/frontend/console" && pnpm dev

# ops（Vite, :3002）— 別ターミナル
cd "$REPO/frontend/ops" && pnpm dev
```

- `build-graphql` は `NEXT_PUBLIC_SUBGRAPH_URL` が `localhost` / `127.0.0.1` / `[::1]` の場合、`../../subgraph/schema.graphql` が存在すれば自動で repo 内 schema を使う。これにより subgraph 未起動でも `build-deps` は完了できる。
- remote subgraph の live introspection を使う場合は、その URL が codegen 時に到達可能である必要がある。repo 内 schema との整合だけを別出力で検証する場合は、`SUBGRAPH_SCHEMA_FILE=../../subgraph/schema.graphql GRAPHQL_CODEGEN_OUT=/tmp/jpydf-app-graphql-codegen/ pnpm build-graphql` を使う。これは検証専用であり、runtime の `NEXT_PUBLIC_SUBGRAPH_URL` は置き換えない。
- console / ops は `df-shared` の生成済み bindings を直接読むため build-deps 不要。

---

## 9. アクセス & 動作確認チェックリスト

| サーフェス | URL | 期待される表示（develop tip） |
| --- | --- | --- |
| **app**（ユーザー） | http://localhost:3000 | Borrow テーブルは Day-1 public active の dwstETH/dUSDC のみ、価格が **¥建て**、JPYdf ≈ ¥1.00。ヘッダーに anvil#0 が接続済み |
| **Admin Console** | http://localhost:3001 | `chainId 31337 · block N`、署名者の権限（GOV / ALLOCATOR / GUARDIAN / WRITEOFF / Oracle owner / DToken owner）、Vault の backingRatio 100% |
| **運用ダッシュボード** | http://localhost:3002 | 「全システム正常」、active 2 / inert 6 のブランチ状態、各ブランチの価格/TCR/SP、Vault/Strategy、実トランザクション履歴（READ-ONLY） |

参考: SeedLocalDemo後のactive branch demo価格はdwstETH ¥600,000 / dUSDC ¥150（JPY/USD ≈ 150）。

> **RPC ログ確認**: ブラウザのコンソールに `eth.merkle.io` など未設定の public RPC への CORS エラーが出る場合は、local stack の RPC URL が `http://127.0.0.1:8545` に固定されているか、wallet / data-source override に古い RPC が残っていないかを確認する。

### 9-1. Launch operation smoke check

mainnet の launch gate は [`Mainnet-Launch-Operation-Gate`](../../protocol/launch/gates/Mainnet-Launch-Operation-Gate.md) が正本。local stack では、同 gate で使う読み口が壊れていないことだけを確認する。

```bash
# Admin Console の direct-RPC reads: SP coverage、liquidation scan、redemption routing を確認
cd "$REPO/frontend/console"
pnpm verify:reads

# Ops surface の read checks（package 側 script がある場合）
cd "$REPO/frontend/ops"
pnpm verify-reads

# Liquidator bot config を current manifest から生成し、dry-run scan を実行
cd "$REPO"
pnpm -C contracts exec tsx ../bots/liquidator/scripts/config-from-df-shared.ts \
  > bots/liquidator/config.local.toml
cargo run --manifest-path bots/liquidator/Cargo.toml -- \
  --config bots/liquidator/config.local.toml \
  scan-once
```

期待値:

- `frontend/console` read check が branch health、SP coverage、liquidation scan、redemption routing を取得できる。
- liquidator bot が current manifest 由来の branch address を使い、dry-run のまま候補 scan と SP offset capacity を表示できる。
- ここで見る SP / redemption / liquidation の値は demo seed の検証値であり、mainnet launch の seed target や slippage target ではない。

---

## 10. トラブルシューティング

| 症状 | 原因 / 対処 |
| --- | --- |
| remote/live introspection の `build-deps` が `ECONNREFUSED ::1:8000` で失敗 | `NEXT_PUBLIC_SUBGRAPH_URL` が local URL なのに `../../subgraph/schema.graphql` が見つからない、または remote URL が未到達。local では repo 内 schema の存在を確認し、remote では subgraph 到達性か `SUBGRAPH_SCHEMA_FILE` の検証コマンドを使う。 |
| `deploy-subgraph` が AssemblyScript の parse error | `pnpm graph codegen` を実行していない。§7(b) を先に。 |
| `ERR_PNPM_RECURSIVE_EXEC_FIRST_FAIL: Command "tsx" not found` | `df-shared/generate.ts` をルートで実行した。`contracts/` から `pnpm tsx ../frontend/df-shared/generate.ts`。 |
| graph-cli が Node バージョンエラー | Node 20.18.1 を使う（`nvm use 20.18.1`）。 |
| `graph-node` コンテナが `Exited(137)`（OOM） | `./start-graph --reset` で再起動。Docker のメモリ割当も確認。 |
| フロントのアドレスが古い / 残高ゼロ | 再 deploy で salt（=アドレス）が変わった。§6 の env 生成と §7(c) の subgraph 再デプロイをやり直す。 |
| Earn / 一部画面が subgraph エラー | subgraph 未同期。`_meta` の block が anvil に追いつくまで待つ。 |

---

## 11. 停止・クリーンアップ

```bash
# フロント / anvil（フォアグラウンドは Ctrl-C、背景は kill）
pkill -f 'next dev'; pkill -f 'vite'; pkill -f 'anvil .*--port 8545'

# graph-node スタック（subgraph ディレクトリで）
cd "$REPO/subgraph" && docker compose down          # データも消すなら ./start-graph --reset で作り直し
```

---

## 付録A. 起動順序のまとめ（依存関係）

```
anvil 起動
  └─ ./deploy local --skip-confirmation         （manifest 生成）
       └─ Multicall3 注入（anvil_setCode）
            └─ forge script SeedLocalDemo        （demo データ＋価格）
                 └─ .env.local 生成 ＋ df-shared bindings 生成
                      └─ subgraph: start-graph(--reset) → codegen → deploy-subgraph
                           └─ frontend: build-deps → dev（app / console / ops）
```

重要な順序制約は 2 つ: **(1) Multicall3 と Seed は deploy の後**、**(2) app の runtime data 確認は subgraph 同期の後**。local URL の `build-deps` は repo 内 schema fallback により Graph Node なしでも実行できる。`SUBGRAPH_SCHEMA_FILE` の Codegen check は検証専用なので runtime URL は置き換えない。

## 付録B. `.env.local` 設定ヘッダー（§6-1 で使用）

§6-1 のコードブロックに同じ内容を記載済み。アドレス部（`NEXT_PUBLIC_*_CONTRACT_*` / `NEXT_PUBLIC_COLL_*`）は `deployment-manifest-to-app-env.ts` の出力を追記して完成させる（手書きしない）。

---

## 検証記録（時点スナップショット）

- 2026-06-15: 当時の `develop` tip で本手順を全て実走し、app(:3000) / console(:3001) / ops(:3002) の 3 サーフェスが正常レンダリング・JPY 建て価格・demo データ表示まで確認。コア/フロント無改変で起動可能（コード修正は不要）。
