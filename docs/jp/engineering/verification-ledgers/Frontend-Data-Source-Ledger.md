# Frontend Data Source Ledger

目的: frontend production surface から擬似データ、stale snapshot、上流 Liquity API fallback を段階的に外し、JPYdf の contract / subgraph / backend / ops exporter を source of truth にする。

本 ledger は現在の source-of-truth 対応表として維持する。日付つきの確認結果や差分レビューは `documents/jp/engineering/historical-reviews/` に残す。

## 判定基準

| 区分 | 扱い |
| --- | --- |
| Production data | ユーザーまたは運営が意思決定に使う数値・状態。contract / subgraph / backend / ops exporter のいずれかを必須 source とする。 |
| Local-only data | `local-stack`、test、fixture のための値。production build の default にはしない。 |
| UI fallback | loading、empty state、error state の表示。数値・残高・APR を推定して埋めない限り許容。 |

## Ledger

`ID / 論点` を行キーとする。基礎 ID は維持し、複数の source や判定を持つ項目だけ論点別に分ける。

| ID / 論点 | Data source | Requirement | Current result | Evidence / gate |
| --- | --- | --- | --- | --- |
| FRNT-DATA-001 / stats schema | JPYdf public stats v3 | `generatedAt`、source block、`healthStatus`、freshness summaryを必須とし、旧Liquity payloadを拒否する | Ops exporterとuser app adapterがv3だけを受理 | [Production Delivery Gate](../../contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md) |
| FRNT-DATA-001 / current aggregates | branch RPC | debt、SP deposits、ActivePool aggregate、現在SP APR・平均借入金利はstats成功に依存せずRPCから導出する | User app queryとadapterがRPCを正本にする | RPC / stats differential test |
| FRNT-DATA-001 / history | public stats v3 | 7日APR等の履歴期間だけstatsを使う | current valueとhistoryを分離済み | stats schema / adapter test |
| FRNT-DATA-001 / oracle | PriceFeedProxy RPC | active source、JPY/USD soft-freeze、`priceSource`、終端fallbackを区別し、live price欠落時は新規借入を止める | `lastGoodPrice`をlive priceとして補完しない | oracle failure E2E |
| FRNT-DATA-001 / freshness | public stats v3 | stale / unavailable / refresh-errorは状態表示へ縮退し、数値補完に使わない | production既定300秒、devnet / staging既定1,800秒。明示override可 | stale drill |
| FRNT-DATA-001 / devnet profile | resettable devnet state | `stateProfile`を必須とし、`day1-review`のactive / inert branch状態をpublish前に検証する | dwstETH / dUSDCだけがactive。branch 2–7はUnderlying未binding、cap・supply・debt・SP deposit 0 | staging publish evidence |
| FRNT-DATA-001 / alerts | public stats alert payload | public bannerは`publicMessageRequired=true`だけを表示する | internal alertは数値・tx導線を遮らない | alert / banner test |
| FRNT-DATA-001 / borrow policy | `borrowRatePolicies` | subgraph平均金利未形成時の表示・初期候補だけに使い、rate tx automationへ流用しない | Ops exporterが生成 | [Day-1 liquidity plan](../../contributors/deltaforesight/commitments/Day1-Self-BS-Initial-Liquidity-Plan.md)、launch evidence、`check-borrow-rate-policy` |
| FRNT-DATA-002 / delegates | JPYdf-owned metadata | 所有endpointがない間は補助表示を無効化する | default empty | production data-source guard |
| FRNT-DATA-003 / governance snapshots | N/A | Day-1はDFT staking / allocation UIを持たない | app / subgraphから削除済み | 旧env名の再導入guard |
| FRNT-DATA-004 / airdrop vaults | JPYdf-operated endpoint | 所有endpointなしでproduction表示しない | default disabled | production data-source guard |
| FRNT-DATA-005 / legacy snapshots | N/A | legacy migration / recoveryを再導入する場合は別specとJPYdf-owned sourceを要する | production appから削除済み | production data-source guard |
| FRNT-DATA-006 / console reads | RPC + generated bindings | Vault / Strategy / role / ownerをcurrent manifestと同一chainから読む | production mockなし | [Admin Console Gate](../../contributors/deltaforesight/delivery-plans/Admin-Console-Production-Gate.md) |
| FRNT-DATA-006 / operator routing | labeled build-time config + on-chain role read | Admin / Guardian / Allocator Safeをlabelとchecksum addressの組で固定し、選択値をrole readとsimulation callerに使う。consoleは署名walletや秘密鍵を保持しない | production guardはaddress-only設定、欠落label、不正・zero・重複address / labelを拒否 | [Admin Console Gate](../../contributors/deltaforesight/delivery-plans/Admin-Console-Production-Gate.md) |
| FRNT-DATA-006 / simulation | operator input | simulation inputをlive metricへ混ぜない | 将来追加時の制約 | Admin E2E |
| FRNT-DATA-007 / ops verification | seeded local fixture | local read verificationだけに使う | production dashboard sourceではない | `verify-reads.ts` |
| FRNT-DATA-008 / UI gallery | dev fixture | production bundleへ含めない | galleryだけで使用 | bundle guard |
| FRNT-DATA-009 / Earn | SP contract / subgraph | Core SP報酬75%だけをclaimable reward / APRに含める | User appでPILと分離 | Earn E2E |
| FRNT-DATA-009 / PIL | InterestRouterForwarder RPC / events + ops ledger | PIL 25%をForwarder残高・`Routed`・recipient入金として表示する | Ops / Adminの別accounting bucket | PIL ledger evidence |
| FRNT-DATA-010 / borrower | RPC + public stats v3 | effective APR、redemption / liquidation riskをsource block / generatedAt付きで示す | Borrow surfaceで表示 | [Participant Readiness Gate](../../protocol/launch/gates/Mainnet-Participant-Readiness-Gate.md) |
| FRNT-DATA-010 / SP | branch RPC + public stats v3 | SP coverage / outside debtをBorrow / Earnに表示し、RPC現在値を優先する | RPC欠落時だけfreshなstatsへ縮退 | Participant evidence / adapter test |
| FRNT-DATA-010 / Vault | Vault / dToken RPC | backing ratioとbuffer状態をcurrent blockで示す | User app / Opsで表示 | Participant evidence |
| FRNT-DATA-010 / exit liquidity | `NEXT_PUBLIC_POOL_LIQUIDITY_HEALTH_URL` | 設定環境だけ表示し、取得失敗はunavailable、未設定は非表示とする | fixtureやwarning風ラベルで補完しない | liquidity health evidence |
| FRNT-DATA-010 / liquidator and future | launch / liquidator JSON evidence | liquidator dry-runを証跡化し、SP追加報酬・profit-seeking liquidation・auto-compoundは実装までlive表示しない | Gateで判定 | Participant evidence |
| FRNT-DATA-011 / capture | URL query + localStorage + registry | active registryのcanonical `bytes32`だけをtxに使い、その他はno-referralとする | 任意slugをhash化しない | registry adapter test |
| FRNT-DATA-011 / activation | registry + campaign / budget / fraud / root evidence | paid campaign表示はactivation packet完了後に限る | productionは未活性 | Referral activation evidence |
| FRNT-DATA-012 / browser health | browser RPC probe | `eth_chainId`と`eth_blockNumber`を周期・各tx step直前に確認し、初回成功前と失敗中はwrite / simulationを止める | Appは10秒周期・5秒timeout・1 retry。Ops / Adminは保持値を前回値と明示する | runtime health drill |
| FRNT-DATA-012 / synthetic health | Secrets Manager管理のread-only RPC | endpointをlogへ出さず、2回失敗またはchain不一致を通知する | `ALRT-FRNT-002` / CloudWatch alarmへ接続 | synthetic monitor evidence |
| FRNT-DATA-013 / candidate discovery | subgraphまたはTroveNFT event RPC | 全branchの候補Trove IDを発見し、browser hintと重複排除する | subgraph停止時もeventへ縮退 | account discovery test |
| FRNT-DATA-013 / current loan | TroveNFT `ownerOf` + TroveManager / BorrowerOperations RPC | owner、status、debt、coll、rateを再検証し、transfer-out / close済みを除外する | log失敗を0件扱いせずsupport IDを表示 | RPC failure E2E |
| FRNT-DATA-014 / link catalog | `frontend/app/src/docs-url.ts` | product docs URLをページ台帳から生成し、生URLを画面へ置かない | 各説明ページへdirect link。operator向けdevnet guideだけを明示allowlistで分離 | CI guard |
| FRNT-DATA-014 / hosting | GitBook JP / EN public roots | public hostingは両rootを必須、repository fallbackはlocal / testだけにする | env guardで強制 | hosting env check |
| FRNT-DATA-015 / public analytics | Dune decoded/raw on-chain data | 公開統計・履歴・Treasury flowをquery registry付きで提供し、real-time monitorやruntime APIとして扱わない | 未実装。Dune SQL、query registry、実query / dashboard、compile / execution、RPC照合、実測credit evidenceが揃うまで移行未完了 | [Analytics / Monitoring Architecture](../../contributors/deltaforesight/operations/Public-Analytics-Private-Monitoring-Architecture.md)、[Requirements Verification Ledger](./Requirements-Verification-Ledger.md) |
| FRNT-DATA-015 / private monitoring | RPC / event ingestion + browser非依存worker | 即時current state、critical alert、ACK / escalationを認証済み面へ提供し、monitor viewerとprivileged operatorを分離する | 移行中。private monitor artifact生成は実装済みだが、認証済み配信、viewer / operator分離、browser非依存workerのproduction delivery evidenceは未完了 | architecture dual-run evidence、[Requirements Verification Ledger](./Requirements-Verification-Ledger.md) |
| FRNT-DATA-015 / user health | DF-managed public stats publisher | User App current healthをDuneやpublic Ops UIの可用性から独立させる | public stats v3は`frontend/ops` exporterに同居中。publisherとproduction deliveryをpublic Ops UIから独立させる移行は未完了 | stats freshness / runtime evidence、architecture decommission evidence |
| FRNT-DATA-015 / transition | 移行中のpublic Ops build / publish workflow | Dune・Private Monitor・publisherのdual-run完了までpublic-bundle guardをfail-closedで維持し、cutover後に公開UIと配信資産だけを撤去する | decommission gate未完了中は移行面として扱う | architecture cutover / decommission evidence |

## CI Guard

`frontend/app/scripts/check-production-data-sources.ts` は `frontend/app`、`frontend/console/src`、`frontend/console/scripts`、`frontend/ops/src`、`frontend/ops/scripts` から次を検出する。

- `frontend/app` production surface の `api.liquity.org` 参照
- `NEXT_PUBLIC_LIQUITY_STATS_URL` による旧 stats fallback の再導入
- root `frontend/app/public/*snapshot*.json`
- `/initiatives-snapshot-*.json` / `/troves-snapshot-*.json` への root path 参照
- `frontend/app/src/docs-url.ts` を経由しない product documentation の直接 URL（明示 allowlist の devnet 運用ガイドを除く）

この guard は intentionally narrow で、`fixture` や loading fallback の語には反応しない。擬似データ排除の対象は production の数値・状態 source に限定する。
