# JPY DeFi Multichain Expansion / JPYdf Bridge Research

> **Status**: Research memo / not an active requirement.
>
> 本書は、JPYdf の将来のマルチチェーン展開を検討するための比較調査メモである。現行 jpydf-v2 の正本は引き続き
> [Product-Overview](../../../product/Product-Overview.md) と各 component spec である。Day-1 active bridge adapter、
> 他チェーン発行、他チェーン full protocol 展開は active scope ではない。一方、token freeze 後の bridge 不可を避けるため、
> `JpydfToken` の dormant bridge-readiness（`bridgeAdmin` / bridge minter registry / `bridgeMint` / self-burn
> `bridgeBurn`）は Core token 要件として採用済み。
> Day-2 以降の bridge minter registration / route open / cap ramp gate は
> [Bridge-Minter-Activation-Gate](../../../operations/runbooks/Bridge-Minter-Activation-Gate.md) を正本とし、本書は protocol 比較の背景資料としてのみ扱う。

## 1. 現行 JPY DeFi / JPYdf の出発点

現行設計では Day-1 launch 時点の `JpydfToken.totalSupply` の実効増減経路は Liquity v2 Core に閉じる。増加は BorrowerOperations /
ActivePool 由来の borrow / interest / fee mint、減少は repay / redemption / liquidation offset などの Core 経路に限定する。
Token には dormant bridge-readiness として `bridgeMint` / self-burn `bridgeBurn` が存在するが、Day-1 は bridge minter 0 件・pending proposal なしで開始するため、active bridge supply path は存在しない。

したがって「Across や Stargate のように移動できるか」という問いへの現時点の答えは次の通り。

- **Day-1 launch state では不可**: bridge minter は 0 件で、bridge / router / OFT adapter はまだ登録されない。他チェーンに正規 JPYdf を発行する経路もない。
- **UX と発行設計は分けるべき**: Across のような高速 UX layer は、destination 側に有効な JPYdf 表現と流動性が存在して初めて機能する。
- **最初に決めるべき対象は JPYdf 本体のみ**: dToken、Trove debt、担保、Stability Pool deposit を横断移動させる設計は、清算・oracle・会計面の blast radius が大きすぎる。

## 2. Day1 Bridge-Readiness の論点

この調査の主眼は、Day1 時点で bridge を稼働させることではなく、**Day1 の token 形状が原因で、後から canonical bridge を作れなくなる状況を避けること**である。

### 2.1 Day1 で閉じる選択肢

Day1 に non-upgradeable な `JpydfToken` を Core mint/burn のみにして配線し、owner renounce 後に token-level extension を追加できない形で固定すると、後から次の選択肢は取りづらくなる。

- **token-native burn/mint**: source で JPYdf を burn し、destination の JPYdf を mint する canonical route は、source token と destination token の双方に bridge authority が必要になる。
- **Stargate / LayerZero MABA 型**: adapter が base token の `mint()` / `burn()` を呼ぶには、base token が外部 adapter を権限付与できる必要がある。
- **CCIP CCT burn/mint 型**: token pool に burn/mint authority を渡す設計は、token 側の権限設計なしには成立しない。

ただし、Day1 に bridge extension を入れなくても **bridge そのものが完全に不可能になるわけではない**。既存 token を lockbox / OFT Adapter に預け、destination 側で representation を mint/burn する経路は後から追加できる。その場合、destination token は厳密には「Ethereum locked JPYdf backed representation」であり、token-native な JPYdf supply とは別の説明・監視が必要になる。

### 2.2 Day1 の選択肢

| Day1 choice | 後からできること | Day1 の負荷 | 主な trade-off |
| --- | --- | --- | --- |
| No bridge extension | Lockbox / OFT Adapter 型、または token migration | 最小 | Core-only invariant は最も単純。ただし native burn/mint route は後から作りづらい |
| Dormant bridge extension | Bridge minter / MABA / CCIP CCT burn-mint / OFT burn-mint の有効化 | 中 | Day1 では minter 未登録で休眠できるが、強い将来権限を含むため token 監査範囲が増える |
| Upgradeable token | 後から任意の bridge logic を追加 | 大 | 柔軟だが、現行の non-upgradeable / Core 不変方針と相性が悪い |
| Pre-committed adapter route | Day1 token は不変のまま canonical adapter を後日有効化 | 中 | token-native ではなく lockbox representation として設計を固定する必要がある |

### 2.3 Dormant extension を選ぶ場合の最低条件

Day1 に bridge-readiness を入れるなら、稼働 bridge ではなく **未登録 minter の dormant extension** として扱うのが最小 blast radius になる。

- `bridgeAdmin` は owner と別ロールにし、Core wiring 後の owner renounce に依存しない。
- Day1 launch 時点では bridge minter を 0 件にする。
- `bridgeAdmin` / bridge minter は contract address のみに限定し、admin と minter の兼任を禁止する。
- bridge minter 追加は timelock、削除は即時にする。
- bridge-specific code は token に import しない。CCIP / LayerZero / Stargate は minter / adapter 側で接続する。
- token-level cap は持たせず、bridge pool / adapter 側 cap を必須にする。後から token-level cap を追加できない前提で、cap / rate / pause を持たない adapter は登録しない。
- Day1 の test は「minter 未登録なら Core 以外の mint/burn が不可能」を明示する。
- `proposeBridgeMinter` 前に [Bridge-Minter-Activation-Gate](../../../operations/runbooks/Bridge-Minter-Activation-Gate.md) Stage A と `CORE-BT-*` verification ledger を満たす。operator-only canary / public route open / cap ramp は同 runbook の Stage B / C に従う。

この場合、現行の `SYS-INV-003` / `ADR-004` は「bridge なし」ではなく「bridge extension は存在するが dormant」に変更されるため、[Product Overview](../../../product/Product-Overview.md)、[Architecture Decision Records](../../../product/architecture/Architecture-Decision-Records.md)、verification ledgerのactive requirement更新が必要になる。単なる実装詳細ではなく、Day1 audit scopeの変更として扱う。

### 2.4 採用判断

「将来、JPYdf を Across / Stargate 風に自然に動かしたい」ことを優先し、Day1 で何も入れない選択は採らない。Day-1 では bridge を稼働させず、token に protocol 非依存の dormant bridge extension だけを入れる。

これにより Day-1 audit scope は増えるが、launch gate を `bridgeMinterCount == 0` / `proposedBridgeMinter == address(0)` に固定することで、実効 supply path は Core のまま維持する。

Day2 activation 前に改めて決めるべき問いは、**destination JPYdf を canonical burn/mint supply として扱うか、Ethereum locked JPYdf backed representation として扱うか**である。現時点の第一候補は前者だが、adapter / chain / cap / monitoring は別 spec で確定する。

## 3. 推奨 Bridge 手法（Arc / Hype / Base / Solana 想定）

### 3.1 推奨の骨子

推奨は、**Day1 に dormant な bridge-agnostic extension を `JpydfToken` へ入れ、Day2 以降の JPYdf 本体 bridge は Wormhole NTT を第一候補として検証する**ことである。前者は採用済み、後者は未実装の activation 検討である。

同時に、Arc / HyperEVM / Base / Solana はすべて Circle CCTP / Gateway の USDC 対応が強いため、JPYdf 本体 bridge と別に **USDC rail** を補助経路として使う。

- **JPYdf canonical rail**: Wormhole NTT を第一候補。Base / HyperEVM / Solana を優先し、Arc は NTT / OFT / CCIP CCT など custom token bridge support が明確になってから追加する。
- **USDC rail**: Circle CCTP / Gateway / App Kit。Arc / HyperEVM / Base / Solana 間の USDC 移動、liquidity funding、destination 側 swap / onboarding に使う。ただし USDC rail は JPYdf supply authority の代替ではない。
- **UX rail**: Across / Stargate / App Kit のような aggregator は、canonical JPYdf route と destination liquidity が固まった後に使う。

理由:

- Base / HyperEVM / Solana は Wormhole NTT の supported networks に含まれ、NTT は hub-and-spoke と burn-and-mint の両方、rate limit、Global Accountant を持つ。
- Solana は非 EVM なので、EVM-only bridge ではなく SVM 対応の token transfer framework が必要になる。
- HyperEVM は NTT の Hyperliquid deployment guide がある一方、experimental warning があるため、初期 cap を小さくする必要がある。
- Arc は Circle docs 上では CCTP / Gateway / App Kit の USDC 体験が強いが、JPYdf のような custom token を native に bridge する標準 route は別途確認が必要である。

### 3.2 Chain 別の推奨

| Chain | 推奨初期扱い | JPYdf 本体 bridge | USDC rail / UX | 主な注意点 |
| --- | --- | --- | --- | --- |
| Base | First pilot | Wormhole NTT または LayerZero OFT。EVM なので最も実装しやすい | CCTP / Gateway / App Kit 対応。USDC liquidity も作りやすい | Optimistic L2 の finality / withdrawal assumption と bridge cap を runbook 化する |
| HyperEVM / Hype | Second pilot | Wormhole NTT が Hyperliquid guide を持つため第一候補 | CCTP / Gateway 対応。HyperCore への展開は別設計 | HyperCore spot token / HyperEVM link は irreversible step が多い。experimental warning を前提に cap を小さく始める |
| Solana | Third pilot | Wormhole NTT または LayerZero Solana OFT。SPL mint / decimal / ATA / rent を設計する | CCTP / Gateway / App Kit 対応 | ERC20 18 decimals と SPL decimals の差、dust、u64 supply cap、program upgrade authority を明示する |
| Arc | Strategic target, not first canonical JPYdf bridge | Custom token bridge support が明確になるまで待つ。Day1 extension により後から minter / adapter を追加できるようにする | CCTP / Gateway / App Kit の USDC rail を優先 | Arc は USDC gas / Circle stack が強い。JPYdf bridge は USDC bridge と混同しない |

### 3.3 Token 側の推奨 interface

Day1 に dormant extension を入れる場合でも、bridge minter に既存 `burn(address,uint256)` と同等の任意 burn 権限をそのまま渡すのは避ける。推奨は、Core 用 mint/burn と bridge 用 mint/burn を分けることである。

- Core 経路: 既存の `mint(address,uint256)` / `burn(address,uint256)` は BO / AP / CR / BO / TM / SP 限定のまま維持する。
- Bridge 経路: `bridgeMint(to, amount)` と、adapter / manager 自身の保有分だけを burn する `bridgeBurn(amount)` または同等の self-burn 型 interface を追加する。
- `bridgeMint(to, amount)` の `to` は通常 transfer と同じ protocol recipient blacklist を通し、誤って core protocol contract に直接 mint しない。
- Bridge adapter / NTT manager は、ユーザーから transfer / allowance で JPYdf を受け取り、自分の balance を burn して message を送る。任意ユーザー残高を直接 burn できる設計にしない。
- `bridgeAdmin` は bridge adapter / manager を登録・削除するだけにし、protocol-specific code は token に import しない。`bridgeAdmin` 自身を minter にしない。
- per-route cap / rate limit は bridge 側を第一候補にする。現行 token extension には per-minter hard cap を持たせず、activation PR 側の adapter / pool cap と monitoring で扱う。

この形なら、Day1 は bridge minter 0 件で Core-only 挙動を保ちつつ、Day2 に Wormhole NTT manager、LayerZero OFT Adapter、CCIP token pool などを bridge minter として plug-in できる。

### 3.4 Wormhole NTT を第一候補にする理由

Wormhole NTT は、JPYdf の初期 bridge 要件と相性がよい。

- hub-and-spoke と burn-and-mint の両方を選べる。
- ERC-20 と SPL token の両方を扱える。
- Base / HyperEVM / Solana が supported networks に含まれる。
- rate limit、access control、Global Accountant が protocol side の control として用意されている。
- Hyperliquid 向けに HyperEVM と HyperCore spot token を link する deployment guide がある。

一方、NTT は Arc を第一弾の supported target として前提にしない。Arc は Circle USDC rail の UX が強いため、最初は JPYdf bridge 対象ではなく、USDC funding / swap / payment の target として扱うのが現実的である。

### 3.5 LayerZero OFT / Stargate の位置づけ

LayerZero OFT は有力な backup である。Base / HyperEVM / Solana の endpoint があり、Solana OFT Program もある。Stargate / OFT route へ載せる余地もある。

ただし初期推奨を Wormhole NTT に寄せる理由は次の通り。

- JPYdf では bridge compromise 時の supply risk が大きく、NTT の Global Accountant / rate limit が設計上わかりやすい。
- Hyperliquid について NTT 側に具体的な deployment guide がある。
- Solana OFT は upgrade authority、ATA rent、shared decimals、one adapter per mesh など注意点が多く、採用する場合は別途 Solana-specific runbook が必要になる。

Stargate は「route / UX」として後段で評価する。JPYdf token authority を Stargate のためだけに固定するのは避ける。

### 3.6 Circle CCTP / Gateway の位置づけ

Circle CCTP / Gateway は JPYdf を直接 bridge するものではない。対象は USDC である。

ただし、Arc / HyperEVM / Base / Solana はいずれも CCTP / Gateway の supported chain に含まれるため、JPYdf のマルチチェーン展開では非常に重要な補助 rail になる。

- destination chain の JPYdf/USDC liquidity seed。
- treasury / market maker の USDC rebalance。
- user onboarding: USDC を CCTP / Gateway で運び、destination で JPYdf に swap。
- Arc: USDC gas / Circle App Kit / Gateway を活かした payment UX。

この rail は JPYdf の canonical supply を作らないため、仕様上は「USDC route」と「JPYdf bridge route」を分けて扱う。

Sources:

- Wormhole NTT overview: <https://wormhole.com/docs/products/token-transfers/native-token-transfers/overview/>
- Wormhole NTT supported networks: <https://wormhole.com/docs/products/token-transfers/native-token-transfers/reference/supported-networks/>
- Wormhole NTT Hyperliquid deployment: <https://wormhole.com/docs/products/token-transfers/native-token-transfers/guides/deploy-to-hyperliquid/>
- Circle CCTP overview: <https://developers.circle.com/cctp>
- Circle CCTP supported blockchains and domains: <https://developers.circle.com/cctp/concepts/supported-chains-and-domains>
- Circle Gateway supported blockchains: <https://developers.circle.com/gateway/references/supported-blockchains>
- Arc App Kit supported blockchains and tokens: <https://docs.arc.io/app-kit/references/supported-blockchains>
- LayerZero Solana OFT: <https://docs.layerzero.network/v2/developers/solana/oft/overview>
- LayerZero deployed endpoints: <https://docs.layerzero.network/v2/deployments/deployed-contracts>

## 4. 実装準備時の修正箇所

この方向性の準備は、「bridge を稼働させる PR」ではなく、**Day1 token freeze 前に dormant bridge-readiness を入れる PR**として扱う。

### 4.1 Active 要件への反映先

Day-2 bridge minter activation は、`JpydfToken` の `CORE-BT-*` と運用 runbook へ接続する。

| File | 位置づけ |
| --- | --- |
| `documents/jp/protocol/product/Product-Overview.md` | Day-1 は bridge 未稼働、Day-2 は staged activation gate 必須という上位判断を持つ |
| `documents/jp/protocol/product/spec/JpydfToken.md` | `CORE-BT-GOV-001` / `CORE-BT-SEC-005` / `CORE-BT-INV-004` が Stage A minter registration 条件、adapter fail-closed gate、global canonical supply accounting を規定する |
| `documents/jp/Parameters.md` | `PRM-BRIDGE-*` の approved cap / rate 値を Day-2 activation package で数値化し、未設定 route は minter registration / mint / unlock 不可として扱う |
| `documents/jp/engineering/verification-ledgers/Core-Requirements-Verification-Ledger.md` | `CORE-BT-*` の Day-2 adapter verification / incident rehearsal 行を追跡する |
| `documents/jp/protocol/operations/runbooks/Bridge-Minter-Activation-Gate.md` | bridge protocol、chain architecture、cap / rate、remote accounting、incident flow、tests / invariants、operator-only canary envelope、public route open、cap ramp の active runbook |
| `documents/jp/protocol/launch/gates/Mainnet-Initial-Configuration-Checklist.md` | Day-1 freeze checklist に `bridgeAdmin`、minter count = 0、pending minter proposal = none、Day-2 activation gate reference を残す |

English docs are support translations. Japanese docs should be changed first; English docs can follow after the Japanese source of truth stabilizes.

### 4.2 Contract changes

最小の contract 変更は `JpydfToken` と interface に限定する。Core contracts (`BorrowerOperations`, `TroveManager`, `StabilityPool`, `CollateralRegistry`, `ActivePool`) には手を入れない。

| File | 必要な変更 |
| --- | --- |
| `contracts/src/JpydfToken.sol` | `bridgeAdmin`、pending admin、bridge minter registry、proposal/timelock、immediate remove、bridge-specific mint/burn を追加する。constructor は `_owner` に加えて `_bridgeAdmin` を受ける |
| `contracts/src/Interfaces/IJpydfToken.sol` | `bridgeMint(to, amount)`、self-burn 型 `bridgeBurn(amount)`、minter/admin view、proposal/admin management events/functions を追加する |
| `contracts/src/Dependencies/Ownable.sol` | 原則変更しない。`bridgeAdmin` は Ownable と別ストレージ・別ロールとして `JpydfToken` 内に実装する |
| New adapter contracts | Day1 では実装しない。Wormhole NTT / LayerZero OFT / CCIP pool は Day2 activation PR の範囲に分ける |

推奨 interface:

- Existing Core functions stay unchanged: `mint(address,uint256)` and `burn(address,uint256)` remain Core-only.
- Add `bridgeMint(address to, uint256 amount)` callable only by registered bridge minter.
- Add `bridgeBurn(uint256 amount)` callable only by registered bridge minter and burning `msg.sender` balance only.
- Do not add `bridgeBurn(address from, uint256 amount)` unless a selected bridge cannot work without arbitrary burn. Arbitrary burn makes bridge minter compromise strictly worse.
- Add `isBridgeMinter(address)` and `bridgeAdmin()` views so deployment and monitoring can prove Day1 dormant state.

### 4.3 Deploy / CREATE2 changes

`JpydfToken` constructor bytecode changes will change the CREATE2 address. This is expected, but must be explicit before any address freeze.

| File | 必要な変更 |
| --- | --- |
| `contracts/script/DeployLiquity2.s.sol` | `JpydfToken` constructor args and `jpydfBytecode` preimage must include `_bridgeAdmin`. `DEPLOYMENT_MODE_USE_EXISTING_JPYDF` gate must verify `bridgeAdmin`, no registered minter, no pending proposal |
| `contracts/test/TestContracts/Deployment.t.sol` | test deploy helper has two `new JpydfToken{salt: SALT}(address(this))` paths and precomputed bytecode. Both must include bridge admin |
| `contracts/test/CollateralYieldZapper.t.sol` | local fixture creates `new JpydfToken`. Update constructor args |
| Deployment manifests | Day1 evidence should record `bridgeAdmin`, `bridgeMinterCount` or equivalent absence proof, and activation status |
| Governance handover scripts | Bridge admin handover must be separate from owner handover. Owner still renounces through `setCollateralRegistry`; bridge admin must survive |

If Day1 keeps bridge minter 0, deploy order remains mostly the same:

1. Deploy `JpydfToken(owner, bridgeAdmin)`.
2. Deploy branches and call `setBranchAddresses`.
3. Deploy `CollateralRegistry`.
4. Call `setCollateralRegistry`, which renounces `owner`.
5. Verify `owner == address(0)` and `bridgeAdmin == Safe/Timelock holder`.
6. Verify no bridge minter is registered and no pending proposal exists.

### 4.4 Tests and invariants

New tests should prove both sides: dormant Day1 behavior is still Core-only, and future bridge activation works only through the intended path.

| Test area | 必要な検証 |
| --- | --- |
| `contracts/test/JpydfToken.t.sol` | constructor invariants: zero admin, EOA vs contract policy if required, owner != bridgeAdmin; bridge admin transfer; minter propose/confirm/cancel/remove; timelock boundary; minter count / view |
| Authorization tests | Non-Core cannot call `mint` / `burn`; non-minter cannot call `bridgeMint` / `bridgeBurn`; owner cannot register bridge minter unless owner is also bridgeAdmin by explicit design, which should be avoided |
| Dormant invariant | After normal deploy with no minter, totalSupply can change only through existing Core call sites. Existing Core paths must remain unchanged |
| Bridge self-burn | Registered minter can only burn its own balance. It cannot burn arbitrary user balances without transfer/allowance path |
| Owner renounce survival | After `setCollateralRegistry`, `owner == address(0)` but `bridgeAdmin` can still remove minters / manage proposals |
| Emergency controls | Removing a minter immediately prevents further `bridgeMint` / `bridgeBurn`; pending proposal cancellation works; renouncing bridge admin is safe only after all minters are removed |
| Invariants | Existing supply/debt invariant must be scoped to Ethereum active supply. If bridge minter is active in tests, global supply monitor must include cross-chain accounting mock or exclude bridge-active runs from Core-only invariant |

### 4.5 Security review focus

This change adds supply authority, so it is audit-significant even if Day1 has no active minter.

- Bridge minter compromise: max mint exposure, rate limits, immediate remove.
- Arbitrary burn risk: avoid `burn(from, amount)` for bridge path.
- Admin key risk: `bridgeAdmin` must be Safe / Timelock, not lost when owner renounces.
- Timelock bypass: minter addition must be delayed; removal must be immediate.
- Misconfiguration: wrong bridge admin, owner == bridgeAdmin, EOA admin/minter, admin-minter兼任, pending proposal left at launch.
- CREATE2 address drift: all precomputed address evidence must use final constructor args.
- Event coverage: every minter/admin/proposal state transition must be indexable.
- Monitoring: total supply by chain, registered minter set, per-route cap utilization, failed messages.

### 4.6 Out of scope for the readiness PR

Keep the first PR narrow.

- No Wormhole NTT manager deployment.
- No LayerZero OFT / Stargate / CCIP pool deployment.
- No Arc / Base / HyperEVM / Solana bridge activation.
- No dToken bridge.
- No Trove debt migration.
- No cross-chain Stability Pool or liquidation.
- No frontend bridge UI.

Those belong to Day2 activation specs and runbooks after the dormant token surface is audited.

## 5. 調査対象プロトコルの分類

| Protocol / route | 主要モデル | 参考になる点 | JPYdf への含意 |
| --- | --- | --- | --- |
| Circle CCTP | issuer-controlled burn/mint | native USDC を source burn / destination mint し、wrapped token や liquidity pool を不要にする | JPYdf が目指すなら token issuer 側の mint/burn authority と attestation / message verification が必要 |
| Aave GHO | facilitator + cap + CCIP | facilitator ごとに mint cap / bucket level を持ち、cross-chain は CCIP で Ethereum origin を前提に lock/burn/release/mint | 旧 `bridgeMinter` 案に「per-minter cap / bucket」の検討余地がある |
| Frax Fraxferry | slow optimistic bridge | 24-48h の遅延、pause / dispute、bridge contract 内 token amount で risk cap | 高速より安全を優先する exit / large transfer route の参考になる |
| Frax LayerZero/OFT | OFT / adapter | OFT は UX が良いが、Frax は一部 OFT を protocol liability ではなく bridge lockbox claim として明確化 | JPYdf で adapter 型を使うなら「canonical JPYdf」か「bridge-backed JPYdf representation」かを明示する必要がある |
| Sky USDS / SkyLink | OP Stack native bridge + LayerZero OFT Adapter | Base は escrow + mint/burn、Solana は Ethereum OFT Adapter + Solana OFT Program。Governance が bridge support / close / upgrade を管理 | 既存 token を変更せず adapter 化する現実解と、governance-controlled bridge の runbook が参考になる |
| LayerZero OFT / Stargate | OFT route layer | native OFT、OFT Adapter、Mint-and-Burn Adapter など複数パターンを提供。Stargate は route / API layer として抽象化 | JPYdf 本体に mint/burn を持たせるか、外部 adapter に権限を渡すかを選ぶ必要がある |
| Across | intent / relayer + CCTP/OFT routing | relayer が destination で先払いし、API が intent / CCTP / OFT を選択する | JPYdf の正規跨 chain supply ができた後の UX / routing layer として有効。canonical issuance の代替ではない |
| Aave V4 / Compound III | chain-local market deployment | lending marketを複数 chain に置くが、各 market は基本的に chain-local risk として扱う | JPYdf Day3 full protocol 展開は「各 chain 独立市場」として扱うべきで、Trove debt の移動ではない |

## 6. Protocol Notes

### 6.1 Circle CCTP

Circle CCTP は USDC の source burn / destination mint を issuer-controlled に実行する。資料上も、wrapped token や
traditional bridge liquidity pool を使わず native USDC を 1:1 移転する設計とされている。

JPYdf への読み替え:

- JPYdf で同型を採るには、issuer / governance が管理する bridge minter または token pool が必要。
- Circle の強みは Circle 自身が USDC issuer であり、各 chain の native USDC を直接 mint できる点にある。JPYdf ではこの前提を自前で作る必要がある。
- CCTP は「USDC 用の完成品」であって、JPYdf をそのまま CCTP に乗せるものではない。設計パターンとして参照する。

Source: <https://developers.circle.com/cctp>

### 6.2 Aave GHO

Aave GHO は facilitator model を採る。Governance が facilitator を承認し、facilitator ごとに `bucketCapacity` と
`bucketLevel` を持つ。GHO の cross-chain 展開では、全 GHO が Ethereum mainnet originated とされ、CCIP が approved bridge
として使われる。Ethereum 側では lock、他 chain 側では burn、destination では release または mint という流れになる。

JPYdf への読み替え:

- 旧 `bridgeMinter` 案は「誰が bridge minter か」を token 側で管理し、rate limit は minter 側に置く設計だった。
- GHO は token-level bucket を持つため、JPYdf でも `bridgeMinter` ごとに supply bucket を持たせるかは再検討に値する。
- ただし、GHO の facilitator は mint authority を複数用途に広げる前提なので、JPYdf が Core supply invariant を重視するなら、bridge facilitator は bridge-only に限定すべき。

Source: <https://aave.com/docs/ecosystem/gho>

### 6.3 Frax

Frax は複数の bridge model を併用している。

Fraxferry は 24-48h の遅い bridge で、bridge hacks / infinite mint risk を避けるため、risk を bridge contract 内 token amount
に限定する設計を採る。batch proposal、24h wait、dispute、pause / cancel などを備える。

LayerZero x Stargate 側では、Frax assets が複数 chain で OFT として表現される。ただし docs は、LayerZero OFT Frax Assets は
Frax Protocol の native liability ではなく、LayerZero lockbox 内の underlying Frax asset に対する redeemability であることを明記している。

JPYdf への読み替え:

- 「高速 route」と「安全重視 route」を分ける発想は有用。large transfer / treasury transfer は slow route を採用する余地がある。
- OFT Adapter 型を採るなら、ユーザーに見える token が JPY DeFi protocol liability なのか、bridge lockbox claim なのかを仕様で明記する必要がある。
- Frax の multi-bridge 併用は強力だが、JPYdf 初期段階では運用・監視・accounting が重くなりすぎる。

Sources:

- <https://docs.frax.finance/cross-chain/bridge>
- <https://docs.frax.finance/cross-chain/layerzero-x-stargate>

### 6.4 Sky USDS / SkyLink

Sky は複数の chain / bridge context に応じて方式を分けている。

Base では OP Stack native bridge をカスタムし、Ethereum 側 escrow、Base 側 mint、Base から Ethereum への burn + security delay +
release という構成を採る。Governance は token support、bridge upgrade、bridge close、withdraw limit を管理できる。

Ethereum-Solana では Wormhole から LayerZero へ migration する資料があり、Ethereum 側は既存 USDS を OFT Adapter に lock、
Solana 側は OFT Program が mint/burn する。USDS on Solana は Ethereum 上の USDS に 1:1 backed と説明され、sUSDS は初期 bridge
対象外とされている。

JPYdf への読み替え:

- 既存 token を変更しない adapter 型は、Day1 token を bridge 非対応で出した後の現実的な選択肢になりうる。
- ただし adapter 型は source chain escrow / lockbox への依存を生む。Core supply invariant は崩さないが、circulating supply と locked supply の監視が必須になる。
- sUSDS を初期 bridge 対象外にした判断は、JPYdf でも dToken / yield-bearing token を bridge 初期 scope から外す根拠になる。

Sources:

- <https://developers.skyeco.com/guides/skylink/base-eth-native-bridge/>
- <https://developers.skyeco.com/guides/skylink/usds-ethereum-solana-bridge/>

### 6.5 LayerZero OFT / Stargate

LayerZero OFT は unified supply を維持しながら複数 chain に fungible token を存在させる標準で、基本は source debit /
destination credit である。native OFT では burn/mint、既存 token 向け OFT Adapter では lock/release を使う。

Stargate は route layer として OFT、CCTP、Stargate V1/V2 などを抽象化する。OFT route には native OFT、lockbox adapter、
mint-and-burn adapter などがあり、MABA 型では base token が external `mint()` / `burn()` と adapter への authorization を持つ必要がある。

JPYdf への読み替え:

- Day1 前に token を変更できるなら、native burn/mint または bridge minter registry が canonical supply には最も素直。
- Day1 後に token を変更できないなら、OFT Adapter / lockbox 型が現実的。ただし canonical 性は「Ethereum locked JPYdf backed representation」として説明する必要がある。
- MABA 型は旧 `bridgeMinter` 案と近い。JPYdf token が adapter/minter を登録できるなら、Stargate / LayerZero route に乗せやすい。

Sources:

- <https://docs.layerzero.network/v2/developers/evm/oft/quickstart>
- <https://docs.stargate.finance/introduction/architecture>
- <https://docs.stargate.finance/primitives/routes/oft>

### 6.6 Across

Across は intent / relayer 型を主軸に、stablecoin route では intents、CCTP、OFT を API が選択する。relayer は destination 側で
自己資本により高速 fill し、後で settlement を受ける。資料上、stablecoin settlement は relayer fill、Circle mint/burn、LayerZero
mint/burn の 3 経路が整理されている。

JPYdf への読み替え:

- Across は「JPYdf をどう発行するか」の答えではない。destination chain 上に JPYdf または JPYdf representation と route liquidity がある前提の UX layer。
- 将来は JPYdf bridge の上に Across-like API / relayer UX を載せると、ユーザー体験は最も良くなる。
- ただし relayer capacity、refund settlement、optimistic verification への依存を別 risk として扱う。

Sources:

- <https://docs.across.to/introduction/stablecoins>
- <https://docs.across.to/introduction/actors>

## 7. JPY DeFi / JPYdf の候補アーキテクチャ

### Option A: Token-native burn/mint

JPYdf token に bridge minter / bridge adapter を登録し、source で burn、destination で mint する。

Pros:

- wrapped token を避けやすい。
- chain 全体の circulating supply を設計上そろえやすい。
- LayerZero OFT / CCIP CCT / Stargate MABA と相性が良い。

Cons:

- `JpydfToken` の active requirement を変更する必要がある。
- bridge minter compromise 時の arbitrary mint risk が最大。
- Day1 の「Core mint/burn のみ」という invariant を変更するため、監査範囲が大きい。

必要な control:

- bridge admin は Safe + timelock。
- bridge minter 追加は timelock、削除は即時。
- adapter-side per-chain / per-route cap、rate limit、pause、emergency remove。
- cross-chain supply monitor。
- bridge-specific runbook と incident drill。

### Option B: Existing-token lockbox / OFT Adapter

Ethereum JPYdf は変更せず、adapter が Ethereum JPYdf を lock し、destination representation を mint/burn する。

Pros:

- Ethereum Core の mint/burn invariant を崩さない。
- Day1 後でも導入しやすい。
- Sky USDS / Frax OFT のように既存 token を横展開できる。

Cons:

- destination token は厳密には Ethereum locked JPYdf backed representation であり、native JPYdf と説明しづらい。
- lockbox balance、destination supply、failed messages、bridge close 時の exit を監視する必要がある。
- 複数 adapter を置くと liquidity / accounting が分断され、permanent loss 相当の operational risk が出る。

必要な control:

- adapter は chain pair / route ごとに 1 つに限定。
- locked JPYdf >= destination minted representation を常時監視。
- bridge UI / token list で canonical route を明示。
- bridge close / migration / pending transfer finalization の runbook。

### Option C: CCIP CCT-style token pool

Chainlink CCIP CCT の token pool と admin registry を使い、lock/release または burn/mint の token pool として構成する。

Pros:

- token pool、admin、rate limit、registration という運用単位が明確。
- GHO の CCIP 採用例と近い。
- Safe からの registration / administration flow を設計しやすい。

Cons:

- CCIP 採用に lock-in する。
- CCIP supported chain / token pool capability に依存する。
- JPYdf token 側で external mint/burn を許すか、lock/release に寄せるかの選定が必要。

### Option D: Across-like UX layer only

JPYdf bridge issuance は別方式で解決し、その上に Across / intent / relayer 型の UX を載せる。

Pros:

- ユーザー体験が最も速い。
- API 側で route selection / fee estimation / destination delivery を抽象化できる。

Cons:

- canonical supply を作る手段ではない。
- relayer liquidity が thin な初期段階では成立しにくい。
- bridge settlement と relayer settlement の二層 risk になる。

### Option E: Full protocol per chain

各 chain に Core / dToken / Oracle / Zapper / liquidation infra を独立展開し、JPYdf は chain 間 burn/mint で横断させる。

Pros:

- 各 chain で local collateral から JPYdf を発行できる。
- Aave / Compound 型の multi-market DeFi として自然。

Cons:

- Oracle、清算 bot、SP liquidity、governance、treasury accounting を chain ごとに持つ必要がある。
- Trove debt は移動できない。各 chain は独立市場として risk parameter を持つ。
- Day2 token-only に比べて監査・運用コストが大きい。

## 8. 推奨する検討順

1. **Day1 は protocol operation として single-chain のまま維持する。** 他 chain transfer を Day1 に開けない。
2. **ただし token freeze 前に bridge-readiness を決める。** Arc / Hype / Base / Solana を将来対象にするなら、dormant bridge extension を入れる方向を第一候補にする。
3. **Day2 token-only を最小 scope として再設計する。** 他 chain には JPYdf だけを置き、Core / dToken / Trove / SP は置かない。
4. **Bridge protocol は Wormhole NTT を第一候補にする。** Base pilot → HyperEVM pilot → Solana pilot の順で検証し、Arc は custom token bridge support が明確になってから追加する。
5. **Circle CCTP / Gateway は USDC rail として組み込む。** JPYdf bridge ではなく、liquidity funding / treasury rebalance / user onboarding の補助 route として扱う。
6. **最初の分岐は token-native burn/mint か lockbox adapter か。**
   - canonical JPYdf を優先するなら Option A。
   - Day1 token 不変を優先するなら Option B。
7. **dToken / sUSDS-like yield-bearing representation は初期 bridge scope から除外する。** Sky が sUSDS を初期 USDS Solana bridge 対象外にしたのと同じく、yield / share accounting を bridge 初期設計に混ぜない。
8. **Across / Stargate は protocol choice ではなく route / UX choice として扱う。** JPYdf 側の supply authority と canonical route が固まってから検討する。

## 9. Open Questions

- destination token を「JPYdf」と呼ぶ条件をどう定義するか。native burn/mint のみか、Ethereum locked JPYdf backed representation も含めるか。
- bridge minter cap / rate limit は、どの adapter / pool / monitoring で enforce するか。
- activation 後の governance は bridge admin / bridge adapter admin / emergency council をどう分離するか。
- initial chain は Base でよいか。HyperEVM / Solana / Arc では bridge standard、finality、wallet UX、liquidity venue が異なる。
- Arc の custom JPYdf bridge は NTT / OFT / CCIP CCT / custom minter のどれが production-ready か。
- Solana 側 JPYdf mint の decimals を何桁にするか。ERC20 18 decimals との dust / u64 cap をどう扱うか。
- bridge migration 時の pending transfer、deprecation、UI disable、token list update をどの runbook で管理するか。
- cross-chain supply monitor はどの invariant を見るか。例: `Ethereum locked + Ethereum circulating + Sum(destination minted) == Ethereum JPYdf totalSupply + adapter-accounted minted` のようなモデル別定義が必要。

## 10. First Draft Decision

現時点の判断は次の通り。

**JPYdf は Day1 token freeze 前に dormant bridge extension を入れる。Day2 token-only bridge は Wormhole NTT を第一候補にする。Base → HyperEVM → Solana の順で検証し、Arc は当面 USDC rail として扱い、custom JPYdf bridge support が明確になってから追加する。full protocol per chain は後回しにする。**

理由:

- ユーザーが求める「移動」は、まず JPYdf 本体の chain 間移動で足りる。
- Day1 で no extension を選ぶと、将来の canonical burn/mint は token migration なしには作りづらくなる。
- Arc / HyperEVM / Base / Solana は USDC rail が強いため、JPYdf bridge と USDC movement を分けると UX と supply risk を混同しにくい。
- Wormhole NTT は Base / HyperEVM / Solana をまとめて扱いやすく、rate limit / Global Accountant が JPYdf の supply risk 管理に合う。
- Arc は USDC gas / CCTP / Gateway の戦略的価値が高いが、JPYdf custom token bridge の第一弾にすると不確定要素が大きい。
- Trove debt / dToken / collateral を動かすと Liquity core risk model を chain 横断に拡張することになり、初期 scope として過大。
- 他 protocol も、stablecoin 本体の bridge と lending / collateral market の multi-chain 展開を分けている。
- Across-like UX は後段で有効だが、canonical supply / lockbox backing / bridge governance が先に必要。
