# Mainnet Launch Product Decision Record

| 項目 | 内容 |
| --- | --- |
| Status | Active |
| 役割 | Day-1 public launch における JPY DeFi プロダクト側の採用範囲・business target・launch requirement の正本 |
| 決定主体 | JPY DeFi Product。on-chain parameter change は本書だけで執行済みにならず、protocol governance の承認・Timelock 実行を要する |
| 会社資金 | [`Day1-Self-BS-Launch-Commitment.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Launch-Commitment.md) |
| 算定根拠 | [`Day1-Self-BS-Initial-Liquidity-Plan.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Initial-Liquidity-Plan.md) |
| 対象外 | DeltaForesight株式会社の自己資金コミットメント、Foundation 資産、実 address、実行手順、Go / No-Go、取引証跡 |

## 0. 意思決定主体と資産の境界

本書は「JPY DeFi をどの条件で Day-1 public launch するか」を定める。JPY DeFi protocol が
DeltaForesight株式会社または Foundation の資産を保有・拠出することを意味しない。

| 区分 | 正本・承認 |
| --- | --- |
| protocol / deploy parameter | [`Parameters.md`](../../../Parameters.md)。変更は protocol governance の承認と Timelock 実行を要する |
| product launch requirement | 本書。market open の最低条件として Gate が検査する |
| DeltaForesight株式会社の自己 B/S | [`Day1-Self-BS-Launch-Commitment.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Launch-Commitment.md)。会社が単独で承認・執行する |
| Foundation 資産 | Foundation 側の個別承認記録。会社自己 B/S と合算しない |
| 実行値・実績 | [`Mainnet-Launch-Operation-Gate.md`](../gates/Mainnet-Launch-Operation-Gate.md) の config / evidence package |

同じ金額であっても、product requirement、会社の拠出コミットメント、実行実績は別の事実として扱う。
Gate は実績が product requirement を満たし、かつ資金 owner の承認範囲内であることを照合する。

## 1. Public branch exposure

Day-1 の public exposure は dwstETH / dUSDC の 2 branch に限定する。

| Branch | dToken | Day-1 status | public exposure |
| ---: | --- | --- | --- |
| 0 | dwstETH | active（ETH 系優先） | あり |
| 1 | dUSDC | active | あり |
| 2 | dETH | inert | なし |
| 3 | dUSD-A | inert | なし |
| 4 | dBTC | inert | なし |
| 5 | dUSD-B | inert | なし |
| 6 | dJPY | inert | なし |
| 7 | dJGB | inert | なし |

inert branch（2–7）は frontend、ops dashboard、campaign、SP requirement、liquidity、liquidator launch scope
の対象にしない。active 化する場合は別の activation package として扱う。

[#1324](https://github.com/deltaforesight/jpydf-v2/issues/1324) と[#1454](https://github.com/deltaforesight/jpydf-v2/issues/1454)のOwner判断により、branch 0 / 1だけをactiveとし、branch 2–7をUnderlying未binding、placeholder PriceFeed、cap 0、Strategy / Zapperなしのinert slotとする。8 branch構成・index `0..7`・single-underlying / one-shot bindingは変更せず、activationは[Inert-Branch-Activation-Runbook.md](../../operations/runbooks/Inert-Branch-Activation-Runbook.md)に従う。branch 2のimmutable riskはOwner追補によりbranch 0と同じ保守側LST envelopeを用いる。

`mainnet-launch-operation.config.json` の `activeBranches` は `[0, 1]` とする。

## 2. SP readiness requirement / planned exposure

Day-1 launch gate は、SP coverage ratio ではなく、下表の絶対 SP target を最低 launch requirement とする。
資金源・拠出 owner は product requirement ではなく、資金 owner 側のコミットメントで管理する。

### 2.1 SP requirement

| Branch | `targetSpJpydf` |
| ---: | ---: |
| 0 dwstETH | 15,950,000 JPYdf |
| 1 dUSDC | 8,330,000 JPYdf |

### 2.2 Planned exposure

`plannedDebtJpydf` は、branch debt が 0 の場合に launch readiness の SP coverage 分母として使う
**Day-1 product exposure envelope**である。dToken `mintCap`、branch debt ceiling、会社の self-mint 額、
外部 borrower が実行可能な借入余力のいずれでもない。

| Branch | `plannedDebtJpydf` | 用途 |
| ---: | ---: | --- |
| 0 dwstETH | 35,000,000 JPYdf | dwstETH の launch planning / SP readiness 用 exposure envelope |
| 1 dUSDC | 100,000,000 JPYdf | dUSDC の launch planning / SP readiness 用 exposure envelope |

外部 borrower room を説明する場合は、freeze block の dToken `totalSupply`、担保価格、target LTV、
既存 debt、upfront fee から executable debt capacity を別途算定する。本表を借入可能額として表示しない。

## 3. JPYdf/USDC exit-liquidity requirement

Day-1 route は [`Liquidity-Route-Policy.md`](../../product/policies/Liquidity-Route-Policy.md) の JPYdf/USDC Uniswap v4
単独 route とし、market open 時の最低 liquidity requirement は次のとおりとする。

| 項目 | Product requirement |
| --- | ---: |
| initial notional | 100,000,000 円 |
| initial JPYdf | 50,000,000 JPYdf |
| initial USDC value | 50,000,000 円相当 |

LP position owner、資金源、会社拠出額、allowance cleanup owner は product requirement に含めず、
資金 owner 側のコミットメントと launch evidence で確認する。

## 4. 一般 borrower / operator-managed rate band

以下は一般 borrower 向けの business target と operator-managed 判断レンジであり、protocol による
固定金利・保証金利・自動 rate transaction ではない。会社 bootstrap Trove の rate commitment とは分ける。

| Branch | 通常時 business target | Risk-mode / emergency range | 適用条件 |
| --- | ---: | ---: | --- |
| dUSDC | ≤2.0% | 2.0%〜3.5% | SP coverage 低下、redemption pressure、または JPYdf/USDC peg の弱化を evidence 化した場合 |
| dwstETH | ≤2.0% | 4.0%〜5.5% | SP coverage 低下、redemption pressure、peg stress、wstETH 急落、清算候補増加、または LP depth 不足を evidence 化した場合 |

## 5. Shortfall / protocol parameter response

SP requirement 未達または launch 後の coverage 低下に対し、会社・Foundationからの追加拠出を
protocol guarantee としない。Gate / operation は、資金 owner が承認した top-up、cap reduction、
pause、または redistribution 受容を選択する。

cap reduction、Vault buffer、`withdrawDelay` の変更は protocol governance の GOV / Timelock operation
として扱う。再評価 trigger は、buffer 不足の継続、`pendingWithdrawals > bufferBalance`、
strategy withdrawal delay の変更、dToken redeem の peg exit 化、または exposure reduction 判断とする。

## 6. PIL activation boundary

Day-1 public launch では、`PILAllocator` / `UniV4MerklInitiative` の active routing を採用しない。
`InterestRouterForwarder` の初期 `recipient` は PIL 専用 holding Safe/address とする。
PIL stack を deploy-ready evidence として事前 deploy しても、`pil-activation-manifest.json` は
`DF_INTEREST_ROUTER_RECIPIENT=PILAllocator` または `setRecipient(PILAllocator)` の承認ではない。

active routing は、Merkl 公式 address、Uniswap v4 poolId、weights、campaign parameters、
fork simulation、Timelock / Safe bundle を含む別の activation package を Product / governance が
明示承認してから実行する。
