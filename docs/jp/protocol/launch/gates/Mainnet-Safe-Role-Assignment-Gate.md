# Mainnet Safe / Role Assignment Gate

> **位置づけ**: Ethereum mainnet fresh deploy の前に、Protocol holderとDeltaForesight launch-operation holderの実アドレス、Safe / Timelock の閾値、role assignment、on-chain readback、frontend / ops / bot consumer 設定を同じ証跡 package で凍結・照合する gate。権限設計は
> [`Governance-Roles-Timelock.md`](../../product/policies/Governance-Roles-Timelock.md)、holder separation / threshold / allocator signer の mainnet 設計は
> [`Mainnet-Role-Holder-Separation-Policy.md`](./Mainnet-Role-Holder-Separation-Policy.md)、
> [`Mainnet-Role-Assignment-Safe-Threshold-Policy.md`](./Mainnet-Role-Assignment-Safe-Threshold-Policy.md)、
> [`Mainnet-Role-Assignment-Allocator-Signer-Policy.md`](./Mainnet-Role-Assignment-Allocator-Signer-Policy.md)、deploy env は
> [`Mainnet-Deploy-Env-Freeze-Runbook.md`](./Mainnet-Deploy-Env-Freeze-Runbook.md)、handover 実行は
> [`Mainnet-Governance-Handover-Runbook.md`](./Mainnet-Governance-Handover-Runbook.md)、launch operation は
> [`Mainnet-Launch-Operation-Gate.md`](./Mainnet-Launch-Operation-Gate.md)、post-launch の JIP approval は
> [`Day-1-Governance-Proposal-Execution-Policy.md`](./Day-1-Governance-Proposal-Execution-Policy.md) と
> [`Protocol-Governance-GitHub-Operations.md`](../../operations/runbooks/Protocol-Governance-GitHub-Operations.md) を参照する。
>
> delay値は [Day1 Parameter Manifest](../../../Parameters.md) `PRM-GOV-*`、Protocol holder実値は[Protocol Role Holder Manifest](../manifests/Mainnet-Protocol-Role-Holder-Manifest.md)、DeltaForesightのlaunch-operation holder実値は[Contributor Holder Manifest](../../../contributors/deltaforesight/manifests/Mainnet-Launch-Operations-Holder-Manifest.md)を使う。
>
> 本書は実アドレス表の **schema / gate / No-Go 条件**を定義する。Domain別Manifestがexpected addressを定義し、evidence packageはその値を複製して新しい正本を作らず、Manifest hash、owner / threshold / Safe configuration、review済みreadbackを凍結する。private key、seed phrase、raw signer list、Safe nonce、raw RPC URL、API key、未公開の個人情報はrepoに記録しない。signerは公開可能な場合を除き`signerListHash`とsigner count / thresholdで証跡化し、署名専用PC / 専用iPhoneは`hostDeviceBindingHash`で証跡化する。

---

## 1. Scope

対象は Ethereum mainnet `chainId=1` の Day-1 production deploy / handover / activation。

- Protocol holderとDeltaForesight launch-operation holderを、Domain別Manifestのscopeを保ったまま同じlaunch evidence packageで照合する。evidence package内の統合表は照合結果であり、holder値の正本ではない。
- Protocol holderの公開承認済みexpected addressは[Protocol Role Holder Manifest](../manifests/Mainnet-Protocol-Role-Holder-Manifest.md)、DeltaForesight holderは[Contributor Holder Manifest](../../../contributors/deltaforesight/manifests/Mainnet-Launch-Operations-Holder-Manifest.md)に一度だけ記録する。個人との対応、作業中transaction、未確定signer / device / recovery情報を含む完全なaddress bookは内部launch evidence packageに置く。
- すべての on-chain address は EIP-55 checksum 形式、`chainId=1`、`address(0)` ではないことを前提にする。
- Safe / Timelock / contract holder が必要な role に EOA を使う場合は No-Go。例外は liquidator gas wallet など、資金移動権限を持たない限定 operator wallet だけ。
- Day-1 dormant bridge 方針は `DF_BRIDGE_ADMIN` の contract-only freeze と `bridgeMinterCount == 0` / `proposedBridgeMinter == address(0)` の readback で確認する。
- Foundation operating-asset Safeは本Protocol launch Gateのrequired holder rowまたはGo / No-Go条件に含めない。Foundation側のholder・OA・Member・signer要件は[Foundation Operating-Asset Holder Manifest](../../../foundation/manifests/Foundation-Operating-Asset-Holder-Manifest.md)とFoundation Governanceの正本で管理する。Protocol / Contributor holderをFoundation Exhibit AのMember addressとして扱わない。

## 2. Evidence Package

標準 evidence package は `mainnet-safe-role-assignment/` とする。完全な signer / operations 情報を含む package は private storage に置き、public PR には承認済み holder address と redacted summary / hash だけを載せる。

| File                                 | 内容                                                                                      | Public repo 可否                 |
| ------------------------------------ | ----------------------------------------------------------------------------------------- | -------------------------------- |
| `00-readme.md`                       | package scope、candidate commit、fork block、review owner、Go / No-Go summary             | redacted 可                      |
| `holder-address-book.csv`            | Domain別Manifestのrow / hash、holder ID、env名、checksum address、type、Safe threshold、signer hash、evidence ref | 完全版はprivate。承認済みaddressはpublic summary可 |
| `safe-thresholds.md`                 | Safe / Timelock ごとの signer count、threshold、owner group、break-glass 方針             | signer list は hash 化           |
| `host-device-bindings.md`            | 署名専用 PC / 専用 iPhone、対象 role、custody、ops owner、last review date、status        | raw device ID は hash 化         |
| `allocator-signer-policy.md`         | `DF_ALLOCATOR` の Day-1 実行形態と将来 bot activation の未実行確認                       | redacted 可                      |
| `role-assignment-matrix.csv`         | contract / function / role と expected holder の対応表                                    | redacted 可                      |
| `env-manifest-diff.md`               | deploy env、handover env、manifest、consumer config の address 差分                       | redacted 可                      |
| `onchain-role-snapshot.json`         | `owner()`、`pendingOwner()`、`hasRole()`、Timelock、bridge dormant readback               | private or redacted              |
| `frontend-ops-operator-addresses.md` | app / ops / console / bot が参照する operator / holder address の照合結果                 | redacted 可                      |
| `bridge-dormant-evidence.md`         | `bridgeAdmin` contract code、minter count 0、pending minter 0、adapter 不在               | redacted 可                      |
| `dry-run-calldata-review.md`         | prepare / accept / Timelock / Safe transaction の target / value / selector / args review | Safe nonce は記録しない          |
| `governance-process-readiness.md`    | JIP policy commit、public repository、signer-block account / approval-address mapping、INV-1〜5、dummy JIP / restore test | redacted 可 |
| `secret-hygiene.md`                  | private key、raw RPC URL、API key、Safe nonce、個人 signer 情報が含まれないことの確認     | public 可                        |
| `no-go-summary.md`                   | 未達 gate、owner、解除条件、launch 影響                                                   | public 可                        |

## 3. Holder Address Book Schema

`holder-address-book.csv`はDomain別Manifestを入力として生成・照合し、次の列を持つ。Manifestと値が異なる場合はevidence側を修正し、evidence値をManifestへ逆流させない。

| Column            | 必須            | 内容                                                                          |
| ----------------- | --------------- | ----------------------------------------------------------------------------- |
| `holderId`        | yes             | 安定 ID。例: `DF_TIMELOCK`                                                    |
| `sourceManifest`  | yes             | Domain別Manifestのpath / commit / hash                                        |
| `envName`         | if applicable   | deploy / handover / consumer env 名                                           |
| `holderType`      | yes             | `safe` / `timelock` / `contract` / `wallet` / `bot-wallet` / `operator-group` |
| `checksumAddress` | on-chain holder | EIP-55 checksum address。operator group は空欄可                              |
| `chainId`         | on-chain holder | `1`                                                                           |
| `safeThreshold`   | Safe / multisig | 実行 threshold                                                                |
| `signerCount`     | Safe / multisig | signer 数                                                                     |
| `signerListHash`  | Safe / multisig | signer list の hash。raw list を公開しない場合の監査用識別子                  |
| `opsOwner`        | yes             | 運用 owner                                                                    |
| `financeOwner`    | if funds        | 資金 owner                                                                    |
| `riskOwner`       | if privileged   | risk approval owner                                                           |
| `evidenceRef`     | yes             | Safe UI / contract read / internal ticket / snapshot への参照                 |
| `status`          | yes             | `draft` / `address-fixed` / `frozen` / `fork-verified` / `mainnet-verified` / `no-go` |

`address-fixed` は checksum address と物理 holder alias の選定だけが完了した状態である。Safe code、version / singleton、owner、threshold、fallback handler、guard、modules、`signerListHash` の review 完了を意味せず、`frozen` 以上を要求する launch gate は通過できない。

### 3.1 Required Holder Rows

| Holder ID                      | Env / consumer                      | Required type                          | Day-1 role                                                                                     |
| ------------------------------ | ----------------------------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `DEPLOYER`                     | `DEPLOYER` / signing method         | wallet or hardware-backed signer       | deploy / prepare 実行。activation 後に privileged role を残さない                              |
| `DF_TIMELOCK`                  | `DF_TIMELOCK`                       | timelock contract                      | Vault `DEFAULT_ADMIN_ROLE` / `GOV_ROLE`、DToken owner、InterestRouter owner、Strategy upgrader |
| `DF_TIMELOCK_PROPOSERS`        | Timelock config                     | operator-group                         | proposer group。raw signer list は private evidence                                            |
| `DF_TIMELOCK_EXECUTORS`        | Timelock config                     | operator-group or open executor policy | executor group / open executor の明示方針                                                      |
| `DF_TIMELOCK_CANCELLER`        | Timelock config                     | same Admin multisig as proposer        | pending proposal cancel owner                                                                  |
| `DF_GUARDIAN`                  | `DF_GUARDIAN` / `DF_STRATEGY_OWNER` | safe                                   | Vault pause / emergency disable、Strategy owner                                                |
| `DF_ALLOCATOR`                 | `DF_ALLOCATOR`                      | Protocol Role Holder Manifestの承認済みholder | Vault allocation / yield transfer。Safe構成と実行形態は各policyを正本とする |
| `DF_WRITEOFF`                  | `DF_WRITEOFF`                       | high-quorum safe                       | Vault `WRITEOFF_ROLE`。Timelock ではない                                                       |
| `DF_PRICE_FEED_OWNER`          | `DF_PRICE_FEED_OWNER`               | safe                                   | PriceFeedProxy owner。`PRM-GOV-PRICE-FEED-SOURCE-DELAY` は契約内蔵のため Timelock 配下に置かない |
| `DF_TREASURY`                  | `DF_TREASURY`                       | safe                                   | Vault treasury / yield retention recipient                                                     |
| `DF_INTEREST_ROUTER_RECIPIENT` | `DF_INTEREST_ROUTER_RECIPIENT`      | Day-1 dedicated safe                    | PIL / borrow interest recipient。`DF_TREASURY` とは別 address                                  |
| `DF_INTEREST_ROUTER_OWNER`     | `DF_INTEREST_ROUTER_OWNER`          | timelock or pre-handover owner         | deploy 時 owner。handover 後は `DF_TIMELOCK`                                                   |
| `DF_STRATEGY_OWNER`            | `DF_STRATEGY_OWNER`                 | safe                                   | Day-1 は `DF_GUARDIAN` と同一を明示                                                            |
| `DF_STRATEGY_UPGRADER`         | `DF_STRATEGY_UPGRADER`              | timelock contract                      | Day-1 は `DF_TIMELOCK` と同一を明示                                                            |
| `DF_BRIDGE_ADMIN`              | Admin multisig                      | high-quorum safe                       | dormant bridge admin。deployer / owner / EOA と同一不可                                        |
| `BOOTSTRAP_BORROWER_OWNER`     | launch operation config             | safe                                   | 自社 bootstrap Trove owner                                                                     |
| `LP_OWNER`                     | Uniswap v4 liquidity config         | safe                                   | JPYdf/USDC v4 position / allowance cleanup owner                                               |
| `SP_SEED_SOURCE_OWNER`         | launch operation config             | safe                                   | SP seed JPYdf の実行・維持 owner                                                               |
| `LIQUIDATOR_GAS_WALLET`        | bot config                          | bot-wallet                             | liquidation maintenance bot の gas wallet。資金 cap / loss cap を別 evidence 化                |
| `KEEPER_OPS_WALLET`            | ops / keeper config                 | wallet or bot-wallet                   | routine keeper 操作。privileged owner と混同しない                                             |
| `ADMIN_CONSOLE_OPERATOR_GROUP` | admin console config                | operator-group                         | console access group / IdP group。実行権限ではない                                             |
| `FRONTEND_RELEASE_OWNER`       | frontend hosting config             | operator-group                         | user app / ops dashboard release owner                                                         |

## 4. Role Assignment Matrix

`role-assignment-matrix.csv` は次の列を持つ。

| Column                | 内容                                                                                                     |
| --------------------- | -------------------------------------------------------------------------------------------------------- |
| `layer`               | `core` / `jpydf-token` / `vault` / `strategy` / `oracle` / `treasury` / `liquidity` / `bot` / `frontend` |
| `contractOrConsumer`  | contract name、consumer name、または manifest path                                                       |
| `roleOrFunction`      | `owner()`、`hasRole(GOV_ROLE)`、`bridgeAdmin()`、config field など                                       |
| `expectedHolderId`    | `holder-address-book.csv` の `holderId`                                                                  |
| `sourceEnvOrManifest` | env 名、manifest field、frontend / bot config field                                                      |
| `verifyMethod`        | fork read / mainnet read / Safe UI / config diff / calldata review                                       |
| `noGoIfMismatch`      | mismatch 時の停止理由                                                                                    |

### 4.1 Required Assignments

| Target                    | Role / value                                            | Expected holder                               | Verify method                                    |
| ------------------------- | ------------------------------------------------------- | --------------------------------------------- | ------------------------------------------------ |
| `JpydfToken`              | `bridgeAdmin()`                                         | `DF_BRIDGE_ADMIN`                             | on-chain read + holder code length               |
| `JpydfToken`              | `bridgeMinterCount()` / `proposedBridgeMinter()`        | `0` / `address(0)`                            | on-chain read                                    |
| `CollateralVault`         | `DEFAULT_ADMIN_ROLE` / `GOV_ROLE`                       | `DF_TIMELOCK`                                 | `hasRole()` read and current admin negative read |
| `CollateralVault`         | `GUARDIAN_ROLE`                                         | `DF_GUARDIAN`                                 | `hasRole()` read                                 |
| `CollateralVault`         | `ALLOCATOR_ROLE`                                        | `DF_ALLOCATOR`                                | `hasRole()` read                                 |
| `CollateralVault`         | `WRITEOFF_ROLE`                                         | `DF_WRITEOFF`                                 | `hasRole()` read                                 |
| `CollateralVault`         | treasury                                                | `DF_TREASURY`                                 | contract read / manifest read                    |
| `DToken`                  | `owner()` / `pendingOwner()`                            | `DF_TIMELOCK` / `address(0)` final            | on-chain read                                    |
| `InterestRouterForwarder` | `owner()`                                               | `DF_TIMELOCK` final                           | on-chain read                                    |
| `InterestRouterForwarder` | `recipient()`                                           | `DF_INTEREST_ROUTER_RECIPIENT`                | on-chain read                                    |
| `PriceFeedProxy`          | `owner()`                                               | `DF_PRICE_FEED_OWNER`                         | on-chain read                                    |
| Strategy proxies          | `owner()`                                               | `DF_STRATEGY_OWNER`                           | on-chain read                                    |
| Strategy proxies          | `upgrader()`                                            | `DF_STRATEGY_UPGRADER`                        | on-chain read                                    |
| Timelock                  | `minDelay` / proposers / executors / cancellers / admin | frozen Timelock config                        | on-chain read / Safe review                      |
| Uniswap v4 LP             | position owner / manager / allowance cleanup owner      | `LP_OWNER`                                    | liquidity evidence / allowance read              |
| SP seed                   | deposit source / maintenance owner                      | `SP_SEED_SOURCE_OWNER`                        | launch operation evidence                        |
| bootstrap Trove           | borrower owner / repayment owner                        | `BOOTSTRAP_BORROWER_OWNER`                    | launch operation evidence                        |
| liquidator bot            | gas wallet / max loss / max gas                         | `LIQUIDATOR_GAS_WALLET`                       | bot config + dry-run evidence                    |
| admin console             | declared holders / operator group                       | address book + `ADMIN_CONSOLE_OPERATOR_GROUP` | console evidence / IdP evidence                  |

## 5. Safe / Timelock Review Rules

Safe / Timelock review は address book freeze の一部であり、handover dry-run より前に完了する。

- Persistent privileged holder は原則 Safe / Timelock contract とする。EOA は deployer、gas wallet、limited keeper wallet だけに限定し、role を持たせない。Day-1 の `DF_ALLOCATOR` は [Allocator Signer Policy](./Mainnet-Role-Assignment-Allocator-Signer-Policy.md) の実行形態に従う。未保護 EOA は `DF_ALLOCATOR` でも No-Go。将来の hardened bot signer は別 activation gate でのみ許容する。
- `safeThreshold`、`signerCount`、`signerListHash`、ops owner、break-glass owner を holder ごとに記録する。
- `signerCount < safeThreshold`、`safeThreshold == 0`、または signer list が未レビューなら No-Go。
- 全 protocol 系 Safe で DFKK 支配鍵だけでは threshold に到達せず、threshold を満たす全組合せに独立 signer block が最低 1 つ含まれることを機械検証する（JIP policy INV-1 / INV-2）。走査組合せ 0 件を pass にしない。
- 独立 signer block の署名契約が「Approved JIP と一致する tx のみ署名する」こと、Timelock schedule も同じ gate に服すること、signer 変更後 7 日以内の register / readback 更新義務を evidence 化する（INV-3〜5）。
- Timelock は `PRM-GOV-COMMON-TIMELOCK-DELAY` と PROPOSER / EXECUTOR / CANCELLER holder、admin renounce の状態を evidence 化する。
- `DF_ALLOCATOR` の owner / threshold / signer 構成が [Safe Threshold Policy](./Mainnet-Role-Assignment-Safe-Threshold-Policy.md) と一致し、Day-1 の実行形態が Allocator Signer Policy と一致することを確認する。将来 bot 化する場合は同 policy の controls と role migration を別 evidence 化する。
- 署名専用 PC / 専用 iPhone は `hostDeviceBindingHash` で evidence 化する。raw asset tag、serial、OS account、browser profile 名、MDM device ID は public evidence に書かない。
- Safe owner / threshold の変更、Timelock role holder 変更、protocol role holder 変更を deploy / handover bundle と同時に行う場合は、calldata review に理由と実行順序を記録する。
- 同一 signer 集合のSafeを複数roleに使う場合は、role separationが形式だけにならないかrisk ownerが承認する。address separationは[Role Holder Separation Policy](./Mainnet-Role-Holder-Separation-Policy.md)と一致させる。
- signer 個人名、email、hardware key serial、Safe nonce、host device raw identifier は public evidence に書かない。

## 6. Env / Manifest / Consumer Reconciliation

address book の値は次の consumer と一致しなければならない。

| Consumer                   | Required reconciliation                                                                                       |
| -------------------------- | ------------------------------------------------------------------------------------------------------------- |
| deploy env                 | `DF_BRIDGE_ADMIN`、`DF_TREASURY`、InterestRouter recipient / owner                                            |
| handover env               | `DF_TIMELOCK`、`DF_GUARDIAN`、`DF_ALLOCATOR`、`DF_WRITEOFF`、`DF_PRICE_FEED_OWNER`、Strategy owner / upgrader |
| `deployment-manifest.json` | JPYdf token、Vault、DToken、Strategy、PriceFeed、InterestRouter、treasury、bridge admin、envFreeze fields     |
| app env / public manifest  | public app が読む contract address と active branch metadata                                                  |
| ops dashboard config       | holder / branch / liquidity / bot monitoring targets                                                          |
| admin console config       | declared holders、role snapshot block、Safe calldata export target                                            |
| liquidator config          | active branches、gas wallet、loss / gas caps、manifest hash                                                   |
| launch operation config    | SP seed owner、LP owner、bootstrap borrower owner、redemption / liquidation owner                             |

No-Go:

- consumer が checked-in old snapshot、local mock、staging Anvil address、または古い manifest hash を参照している。
- env と manifest の address が同じ role 名で一致しない。
- admin console が role holder を単一 address 前提で collapse している。
- app / ops / bot / console の chainId が `1` ではない production config を mainnet launch evidence として扱っている。

## 7. Review Phases

| Phase                     | 完了条件                                                                                                       | 次に進める先                           |
| ------------------------- | -------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| 0. Draft address book     | required holder rows がすべて存在し、owner / evidence ref が埋まっている                                       | physical address selection             |
| 1. Address fixed          | checksum address と holder alias が承認済み。Safe hardening 未完了なら status=`address-fixed`                 | Safe / Timelock review                 |
| 2. Safe / Timelock freeze | threshold、signer count、signer hash、Timelock config、INV-1〜5、governance process readiness が review 済み | deploy env freeze                      |
| 3. Env freeze             | deploy / handover / consumer env が address book と一致する                                                    | fork deploy / handover dry-run         |
| 4. Fork role snapshot     | `mainnet-fork-evidence` と `VerifyDFGovernanceHandover` が同一 fork state で role readback を通す              | mainnet broadcast / prepare            |
| 5. Mainnet final readback | accept 後に pending owner 0、expected holder、bridge dormant、consumer config hash が mainnet block で一致する | activation / liquidity / public launch |
| 6. T+24h watch            | holder / Timelock / bot / console / ops dashboard が launch window で読める                                    | issue / gate close                     |

## 8. No-Go Conditions

次のいずれかが true なら mainnet broadcast、handover prepare、activation、liquidity add、public launch を止める。

- required holder row が無い、または `status` が `frozen` 以上でない。`address-fixed` は launch Go 条件ではない。
- checksum address、chainId、holder type、ops owner、evidence ref が欠けている。
- Safe / Timelock が必要な holder に EOA、codeless address、deployer、または current admin を入れている。
- `DF_CURRENT_ADMIN` が activation 後も Vault role、DToken owner、Strategy owner / upgrader、PriceFeed owner、InterestRouter owner を保持する。
- [Role Holder Separation Policy](./Mainnet-Role-Holder-Separation-Policy.md)を満たさない。
- `DF_WRITEOFF` が Timelock になっている、または low-quorum operational wallet になっている。
- `DF_PRICE_FEED_OWNER` が Timelock 配下で、PriceFeedProxy 内蔵 delay と二重遅延になる。
- `DF_BRIDGE_ADMIN` が未確定、deployer / owner と同一、EOA、codeless address、または `bridgeMinterCount != 0` / `proposedBridgeMinter != address(0)`。
- Safe threshold / signer count / signer hash が evidence に無い、または signer count が threshold を下回る。
- JIP policy INV-1〜5 の signer-control 組合せ検証が無い、DFKK 支配鍵だけで threshold に到達する、または threshold 組合せに独立 signer block を含まないものがある。
- `jpydf-governance` の public repository、JIP template、Governance Surface Register、permissions ledger、branch rules、required checks、backup / restore、signer-block account / approval-address mapping が go-live していない。
- dummy JIP で Intake → Review → Voting → Approved → Queued → Executed → Closed を通していない、または stale vote / threshold 不足 / recusal / package 改変 / expiry / secret 混入が fail しない。
- launch 1 回性 gate 完了後の Class N/C transaction に Approved JIP ID / `package_sha256` がなく、Safe / Timelock payload が JIP Specification と一致する independent review も無い。
- host device binding evidence が無い、署名専用 PC / 専用 iPhone が日常用途と共用されている、または作業用 PC・個人/共有/未管理 PC・remote desktop / remote control 中の署名を前提にしている。
- deploy env、handover env、manifest、frontend / ops / admin console / bot config の address が一致しない。
- Safe calldata review で target / value / function / args / caller / execution order が確認されていない。
- raw private key、seed phrase、raw signer list、Safe nonce、raw RPC URL、API key、host device raw identifier が public evidence に残っている。
- admin console が declared holder と on-chain role snapshot を表示できない、または Safe / wallet 外で privileged tx を送れる。

## 9. Templates

### 9.1 `holder-address-book.csv`

```csv
sourceManifest,holderId,envName,holderType,checksumAddress,chainId,safeThreshold,signerCount,signerListHash,opsOwner,financeOwner,riskOwner,evidenceRef,status
<protocol-manifest>,DF_TIMELOCK,DF_TIMELOCK,timelock,<checksum>,1,,,,governance,,security,<evidence>,draft
<protocol-manifest>,DF_GUARDIAN,DF_GUARDIAN,safe,<checksum>,1,<threshold>,<count>,<hash>,ops,,security,<evidence>,draft
<protocol-manifest>,DF_BRIDGE_ADMIN,DF_BRIDGE_ADMIN,safe,<admin-multisig-checksum>,1,<threshold>,<count>,<admin-multisig-signer-hash>,governance,,security,<evidence>,draft
<contributor-manifest>,LP_OWNER,LP_OWNER,safe,<checksum>,1,<threshold>,<count>,<hash>,ops,deltaforesight,operations,<evidence>,draft
```

### 9.2 `role-assignment-matrix.csv`

```csv
layer,contractOrConsumer,roleOrFunction,expectedHolderId,sourceEnvOrManifest,verifyMethod,noGoIfMismatch
vault,CollateralVault,DEFAULT_ADMIN_ROLE,DF_TIMELOCK,DF_TIMELOCK,hasRole read,current admin keeps admin role
jpydf-token,JpydfToken,bridgeAdmin,DF_BRIDGE_ADMIN,DF_BRIDGE_ADMIN,on-chain read,bridge admin mismatch
frontend,admin-console,declaredHolders,holder-address-book,console config,config diff,console shows stale holders
```

### 9.3 Mainnet Final Readback Checklist

```text
Candidate commit:
Manifest sha256:
Fork block:
Mainnet verification block:
Address book hash:
Signer list hash set:
Safe threshold review:
Timelock minDelay / role review:
Deploy env hash:
Handover env hash:
Consumer config hashes:
On-chain role snapshot:
Bridge dormant snapshot:
Admin console role snapshot:
Liquidator config snapshot:
Secret hygiene review:
Go / No-Go:
```
