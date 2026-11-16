# JPY DeFi Architecture Decision Records

| Field | Value |
| --- | --- |
| Domain | Protocol |
| Lifecycle | Evergreen |
| Artifact Type | Decision Record |
| Decision Authority | Protocol Governance |
| Maintainer | DeltaForesight |
| Visibility | Repository |
| Status | Active |
| Normative Source | 本書（`ADR-*`の選択・理由）。現行要件はProduct / component Spec |

## 1. 目的

JPYdfの現行アーキテクチャを選択した理由、代替案、帰結を記録する。現行の機能・不変条件・制約を再定義せず、決定後の要件は[Product Overview](../Product-Overview.md)とcomponent Specを正本とする。

<a id="adr-001"></a>
## `ADR-001` Liquity v2をbase-parity forkする

- **文脈**: 既に監査・実戦検証されたCoreを継承できることがforkの価値であり、改変は検証済み状態をリセットして遠隔の不変条件を壊しうる。
- **決定**: Coreはbase-parityを基準にし、JPYdf canonical surfaceと`CORE-MOD-*`台帳化差分だけを明示的に持つ。拡張はCoreの外側に独立レイヤーとして実装する。
- **代替案**: 自前CDPのフルスクラッチ、またはCoreの直接改変。
- **帰結**: 拡張は外側へ閉じる（`ARCH-001` / `ARCH-004`）。Core `mint` / `burn`の権限条件にbridge minterを追加せず、bridge supply pathは`ADR-004`の別名関数へ分離する。

<a id="adr-002"></a>
## `ADR-002` 担保の外部運用をdToken + Strategy層で実現する

- **文脈**: Coreは担保をProtocol内に保持し、18 decimalsで扱う前提である。
- **決定**: UnderlyingとCoreの間にdToken層を置き、Coreが扱う担保をUnderlyingではなく請求権tokenにする。
- **代替案**: Coreへ担保運用hookを追加する、または非18 decimals assetを直接扱う。
- **帰結**: dTokenがCoreの担保となり、Underlyingの保管・運用・収益化は外側へ閉じる。

<a id="adr-003"></a>
## `ADR-003` Strategyはpush modelにする

- **文脈**: VaultがStrategyからpullする設計は、外部運用先の流動性逼迫・非同期引き出し時に危機時ほど詰まりうる。
- **決定**: Strategyが`sendToVault` / `sendProfitToVault`でVaultへpushし、Vaultはpullしない。Vaultは`receiveFromStrategy`で受領する。
- **代替案**: Vaultからのpull model。
- **帰結**: 同期 / 非同期の区別をStrategy内へ閉じ、自己scaled残高でdonationを分離する。

<a id="adr-004"></a>
## `ADR-004` bridge供給経路をCoreから分離し、tokenをbridge-readyにする

- **文脈**: bridge mint / burnは`JpydfToken`へ新しい供給権限を追加して信頼境界を広げる。一方、token freeze後にbridge不可の形で固定すると、将来展開時にtoken migrationまたはadapter lockboxへ依存する。
- **決定**:
  - `JpydfToken`にbridge protocol非依存の休眠拡張を実装する（独立`bridgeAdmin`、delay付きbridge minter registry、`bridgeMint`、self-burn型`bridgeBurn`）。
  - `bridgeAdmin` / bridge minterはcontract addressのみに限定し、兼任させない。
  - 既存Core `mint` / `burn`の権限条件にはbridge minterを追加しない。
- **代替案**: bridge非対応でtoken freezeする、初期releaseから特定bridge protocolへ結合する、またはminterに任意addressのburnを許す。
- **帰結**: token再デプロイなしでcanonical bridgeを検討できる。releaseごとのdormant / active状態は本書で固定せず、[Bridge Minter Activation Gate](../../operations/runbooks/Bridge-Minter-Activation-Gate.md)がregistration、route open、cap rampを別々に承認し、Manifest / Evidenceが実状態を記録する。

<a id="adr-005"></a>
## `ADR-005` OracleはPriceFeedProxyで差替可能にする

- **文脈**: upstreamはOracle addressをimmutableに直接参照し、feed deprecation・障害・担保構成変更時に差し替えられない。
- **決定**: Coreが固定参照する`PriceFeedProxy`を挟み、その裏のsourceをcontract内蔵delayで差替可能にする。
- **代替案**: Coreを改変してOracleを差し替える。
- **帰結**: source差替がCore不接触で完結し、価格取得・JPY合成はProxy / PriceFeed内へ閉じる。

<a id="adr-006"></a>
## `ADR-006` backing毀損（dToken裏付け < 1）時の挙動

- **文脈**: Strategy運用先の毀損でdTokenの裏付け（実保有`A` ÷ 実効負債`L`）が1を割ると、担保価値の即時下方反映で清算が起きやすくなり、1:1償還が有限bufferの取り付けを招く。`ARCH-001`のため、対応は外側レイヤー・運用へ閉じる。
- **決定**:
  - 確定損失は即時に担保価値へ反映し、価格平滑化・rate limitは採らない。
  - 一時的な流動性不足は損失として扱わない。
  - backing < 1でも1:1償還を維持する。実損時は「償還の一時停止 → backstop reserveで裏付けを回復 → 1:1のまま再開」で対応する。
  - 恒久損失時のpro-rata配分は自動化せず、Protocol Governance判断に留保する。
  - 償還停止の自動発火は現行Protocolでは設けず、手動運用とstrategyごとの保守guardで対応する。
- **代替案**: 価格平滑化、常時自動pro-rata償還、またはbacking thresholdによる自動停止。
- **帰結**:
  - 既存の`ORCL-FR-014`、`VAULT-FR-014` / `VAULT-FR-017`、`writeoffStrategyPrincipal`で充足する。
  - strategy別の扱いは各component Specが定義し、[`SYS-RISK-002`](../../launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-002)がlaunch時に検査する。
  - 償還停止の自動化要否は未決のまま維持する。

<a id="adr-007"></a>
## `ADR-007` 上方peg乖離は新しい自動供給機構で防がない

- **文脈**: Redemptionは下方向への名目価格圧力を作るが市場価格の床を保証せず、上方（JPYdf > ¥1）に対称な機構もない。PSM型の供給弾力を追加するにはCore外にmint経路を作る必要があり、base-parity原則と供給経路の信頼境界に衝突する。
- **決定**: 速いleverは任意の適格borrowerによる既存Core経路の追加借入と市場供給、遅いleverはProtocol Governanceによる追加dToken supply headroomのcap rampとする。借入余力は計画値ではなくlive collateral / debt / risk limit / dToken `totalSupply / cap`から算定する。APR変更は借入コストとRedemption順位を変える別判断であり、供給actionとは扱わない。
- **代替案**: Core外に準備資産型PSMを追加する、またはcapを事前に大幅引き上げる。
- **帰結**: 短期premiumを[`SYS-RISK-009`](../../launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-009)として受容する。追加供給はborrowerの意思、担保、risk limit、市場流動性に制約され、Protocolまたは特定Contributorが実行を保証しない。Contributorが自己資金対応を採用する場合、そのcommitment・承認・実行はContributor Domainのartifactで管理する。
