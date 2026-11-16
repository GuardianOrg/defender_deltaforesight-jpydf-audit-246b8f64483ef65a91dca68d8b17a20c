# SPECA Audit Pilot Runbook

## 0. 目的

SPECA を JPYdf の外部監査準備に使うための pilot 手順を定義する。SPECA は自然言語仕様から property を抽出し、実装がそれを満たすか proof-attempt で確認する補助 audit tool である。出力は候補 finding であり、ChainDefenders 等の人間監査・既存 Foundry / Slither / 手動レビューを置き換えない。

## 1. 適用スコープ

初回 pilot は contracts の DeltaForesight 独自レイヤーを優先する。

- `contracts/src/JpydfToken.sol`
- `contracts/src/DToken.sol`
- `contracts/src/CollateralVault.sol`
- `contracts/src/Strategies/`
- `contracts/src/PriceFeeds/`
- `contracts/src/Zappers/`
- `contracts/src/InterestRouterForwarder.sol`
- `contracts/src/Dependencies/Constants.sol`
- 上記に対応する `contracts/src/Interfaces/`

Out of scope:

- `contracts/lib/`
- `contracts/test/`
- `frontend/`
- `subgraph/`
- `bots/`
- `documents/`
- build / cache / generated artifacts

コア Liquity v2 surface は、初回 pilot では `CORE-MOD-*` と JPYdf 差分境界の確認に限定する。コア全量の挙動検証は `Core-Requirements-Verification-Ledger.md` と upstream parity / Foundry suite を正本とする。

## 2. 仕様入力

SPECA に読ませる仕様の正本は `documents/jp` である。優先順は以下。

1. `documents/jp/protocol/product/Product-Overview.md`
2. `documents/jp/Parameters.md`
3. `documents/jp/protocol/product/spec/dToken.md`
4. `documents/jp/protocol/product/spec/CollateralVault.md`
5. `documents/jp/protocol/product/spec/strategies/Strategy.md`
6. `documents/jp/protocol/product/spec/strategies/AaveV3Strategy.md`
7. `documents/jp/protocol/product/spec/strategies/ERC4626Strategy.md`
8. `documents/jp/protocol/product/spec/Oracle.md`
9. `documents/jp/protocol/product/spec/Zapper.md`
10. `documents/jp/protocol/roadmap/spec/Treasury.md`
11. `documents/jp/protocol/product/spec/InterestRouter.md`
12. `documents/jp/protocol/product/spec/Liquity-v2-Core-Spec.md` の `CORE-MOD-*` / boundary sections

SPECA の property と finding は、要件 ID (`DTKN-*`, `VAULT-*`, `STGY-*`, `ORCL-*`, `ZAP-*`, `IRTR-*`, `CORE-MOD-*`) に戻せる形で triage する。

## 3. 事前条件

- audit 対象 commit を freeze する。dirty worktree や moving branch は使わない。
- RPC URL、private key、API key、`.env` は SPECA 入力・出力・issue 本文に含めない。
- `outputs/` と `target_workspace/` は生成物で、git 追跡しない。
- SPECA の結果は候補 finding として扱い、人間が exploitability / scope / severity を確認する。

## 4. セットアップ

公式 quickstart は `npx speca-cli@latest doctor`, `npx speca-cli@latest init`, `npx speca-cli@latest run --target 04` の順を推奨している。JPY DeFi では template を使う。

```bash
mkdir -p outputs
cp documents/jp/contributors/deltaforesight/delivery-plans/speca/TARGET_INFO.template.json outputs/TARGET_INFO.json
cp documents/jp/contributors/deltaforesight/delivery-plans/speca/BUG_BOUNTY_SCOPE.template.json outputs/BUG_BOUNTY_SCOPE.json
```

`outputs/TARGET_INFO.json` の `target_commit` を audit freeze commit に置き換える。

```bash
npx speca-cli@latest doctor
npx speca-cli@latest run --target 04 --workers 4 --budget 50
```

低コストの preliminary run では以下に落とす。

```bash
npx speca-cli@latest run --target 03 --workers 2 --budget 15
```

### 4.1 JPY DeFi private/local 実行時の注意

2026-06-19 時点の pilot では、Claude Code subscription 認証で `speca auth status` / `doctor` は通る。一方、private repository / local docs を使う場合は次に注意する。

- `npx speca-cli@latest run` は target repository cwd から phase runner を解決できず、SPECA repository clone 直下での `uv run python3 scripts/run_phase.py --phase ...` 実行が必要になる場合がある。
- GitHub fetch MCP は private repository の raw/spec URL で 404 になる場合がある。その場合は SPECA clone に `target_workspace -> /path/to/jpydf-v2` を置き、`outputs/01a_STATE.json` に `local_path` 付きで `documents/jp` の正本 spec を列挙する。
- `outputs/` は SPECA の intermediate / final artifacts を含むため git ignore する。レビュー記録へは要約と triage 結果だけを転記し、巨大 JSON や認証情報を含むログはコミットしない。
- spec 内の抽象表記は literal function name として扱わない。例: `emergencyWithdrawFrom{Protocol}` は `IStrategy` 共通関数ではなく、`emergencyWithdrawFromAave` / `emergencyWithdrawFromLido` / `emergencyWithdrawFromERC4626` 等の派生固有関数へ対応付ける。
- Phase 03 は `--min-severity` を受け付けても queue 作成に severity gate が効かない場合がある。High 以上だけを回すときは、別 output dir に `02c_PARTIAL_*.json` を severity filter 済みでコピーして `--output-dir` を指定する。
- severity filter 済みの別 output dir で Phase 04 を実行する場合も、Phase 04 は severity calibration / spec cross-reference のため `01b_SUBGRAPH_INDEX.json` を読む。元の output dir から同ファイルをコピーしてから実行する。

結果閲覧:

```bash
npx speca-cli@latest browse outputs/04_PARTIAL_*.json
npx speca-cli@latest browse --filter "severity:High AND verdict:CONFIRMED_*"
```

## 5. Triage 方針

SPECA finding は次の順で分類する。

| 判定                    | 取扱い                                                                                                            |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Confirmed vulnerability | code / test / spec のいずれかに修正を起票する。資金損失・権限逸脱・oracle / liquidation / redeem failure は P0/P1 |
| Spec gap                | 正本 spec に ID 付きで要件を追加し、必要なら実装とテストを追従する                                                |
| Test gap                | `Requirements-Verification-Ledger.md` に未検証として記録し、Foundry / fork / integration test を追加する          |
| False positive          | 不変条件・信頼境界・到達不能理由を runbook または dated review に残す                                             |

特に確認する観点:

- Donation / share inflation / accounting drift
- Strategy loss / delayed redeem / backstop reserve release
- `allocate()` 一括移動、cooldown、buffer 100% 構成、deposit / redeem pause
- `sendToVault` / `sendProfitToVault` が清算や borrow rate jump を誘発しないか
- Oracle stale / backing ratio / source timelock / branch shutdown
- Stability Pool offset / liquidation / redistribution / urgent redemption の縮退
- Governance role の複数 holder、Timelock、Guardian emergency action
- Zapper slippage / approval / removed Flash Loan close surface / receiver routing
- InterestRouter 25% PIL route と recipient handover

## 6. 記録場所

- 実行結果の時点記録: `documents/jp/engineering/historical-reviews/YYYY-MM-DD-SPECA-Audit-Pilot.md`
- 要件検証への反映: `documents/jp/engineering/verification-ledgers/Requirements-Verification-Ledger.md`
- コア境界への反映: `documents/jp/engineering/verification-ledgers/Core-Requirements-Verification-Ledger.md`
- 修正 PR: finding ごとに範囲を狭く分ける

## 7. 公式参照

- SPECA repository: https://github.com/NyxFoundation/speca
- Documentation: https://speca.pages.dev/
- Config schema: https://speca.pages.dev/docs/getting-started/config-files
- Quickstart: https://speca.pages.dev/docs/getting-started/quickstart
