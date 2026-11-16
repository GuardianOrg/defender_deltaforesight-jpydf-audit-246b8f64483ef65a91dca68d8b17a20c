# Frontend UX Readiness Gate

Updated: 2026-07-26

この runbook は User App と、監視アーキテクチャのdecommission完了まで公開される移行中のpublic Ops UIについて、i18n、mobile、wallet、tx failure表示に固有のmainnet差分gateを定義する。[Frontend-Production-Delivery-Gate.md](./Frontend-Production-Delivery-Gate.md) の共通判定を前提とし、live-data、error redaction、release / rollbackは再掲しない。日本語版をsource of truthとし、Frontend specの `FRNT-FR-009` / `FRNT-FR-010` / `FRNT-ERR-004` / `FRNT-TBD-008` / `FRNT-TBD-009` と連動する。

## 1. Scope

対象:

- User Appの主要導線、primary locale、数値、error copy。
- mobile viewportとwallet / tx confirmation / failure states。
- public Ops UIが移行中に公開されている場合、その公開導線とcritical health表示。

対象外:

- Admin Control / Private Operations Monitor。これは [Admin-Console-Production-Gate.md](./Admin-Console-Production-Gate.md) を正とする。
- Dune Public Analyticsのquery / dashboard受け入れ。これは [監視アーキテクチャ](../operations/Public-Analytics-Private-Monitoring-Architecture.md) を正とする。
- 全localeの完全提供。Day-1はprimary locale完成をgateとし、未完成locale switchは出さない。
- wallet内browser固有の高度な最適化。署名導線と戻り導線の破綻はDay-1 gate。

## 2. Day-1 Minimum Gate

| Gate | Day-1 要件 | Evidence |
| --- | --- | --- |
| Primary locale freeze | primary locale を launch evidence で明示する。全到達可能画面の CTA、見出し、説明、empty/error/loading copy を primary locale で揃える。 | locale decision、screen inventory、copy review |
| Incomplete locale switch | secondary locale が未完成なら locale switch を表示しない。混在 locale を user-facing default にしない。 | locale switch state、route screenshot |
| JPYdf terminology | 到達可能画面で `BOLD` / `sBOLD` / upstream staking / Liquity-only reward copy を残さない。base package name や vendored code 名は対象外。 | grep evidence、screen spot check |
| JPY formatting | 金額・価格・担保価値は JPY 表示を primary とし、桁区切り、小数桁、rounding direction を FRNT-FR-009 と一致させる。 | amount snapshot、rounding spot check |
| Unknown tx failure | 共通 gate で redaction 済みの error id、tx hash、safe retry action、copyable support context を表示する。 | unknown failure drill |
| Mobile viewport matrix | 少なくとも 360x740、390x844、430x932、768x1024、desktop baseline を確認する。横スクロール、重なり、切れ、CTA 不可視を No-Go とする。 | screenshot set、visual review |
| Wallet modal | connect / chain mismatch / reject signature / pending / success / failure を mobile 幅で確認する。wallet modal が CTA や error text を隠さない。 | wallet state screenshots |
| Tx confirmation | borrow、deposit、redeem、claim、repay / adjust の確認画面で金額、asset、chain、recipient、fee / gas compensation、警告文が mobile 幅で読める。 | tx confirmation screenshots |
| In-wallet browser minimum | MetaMask / Rabby / Safe 等の in-app browser 固有対応は Day-2 可。ただし戻る導線、署名後の復帰、長文エラー、chain switch failure が破綻しないことを最低確認する。 | in-wallet smoke evidence or documented blocker |
| Transitional public Ops scanning | public Ops UIが公開中の場合、mobileでcritical health / oracle / stats stale / incident bannerを読めるようにし、数値tableのhorizontal scrollを明示する。 | public Ops mobile screenshots |

## 3. No-Go Conditions

以下が残る場合、mainnet User Appまたは移行中のpublic Ops UIを公開しない。

- 到達可能画面に upstream user-facing `BOLD` / `sBOLD` / Liquity staking / fake
  reward copy が残る。
- locale switch があり、選択先が未翻訳または JPYdf 用語に未統一。
- 主要 CTA や tx confirmation の金額・asset・recipient が mobile 幅で読めない。
- error / wallet modal / banner が他の操作要素を覆い、閉じられない。
- mobile で borrow / deposit / redeem / claim の開始・キャンセル・失敗後復帰ができない。

## 4. Evidence Template

```
Frontend UX readiness evidence
Date:
Operator:
Common production evidence ID:
Primary locale:
Secondary locales exposed:
Screen inventory:
BOLD / upstream copy grep:
JPY formatting check:
Viewport screenshots:
Wallet modal screenshots:
Tx confirmation screenshots:
Unknown tx failure drill:
In-wallet smoke:
Ops dashboard mobile check:
Known limitations:
Go / No-Go:
```

## 5. Operator Workflow

1. Freeze primary locale and exposed locale switch state.
2. Run copy grep for upstream user-facing terms and review reachable screens.
3. Build production candidate with production-like env.
4. Capture viewport matrix screenshots for user app and critical ops dashboard.
5. Drill wallet states and tx confirmation states on mobile widths.
6. Drill unknown tx failure layout and recovery action.
7. Record any known limitation as Day-2 only if it does not violate No-Go.
8. Attach evidence to launch evidence and record Go / No-Go.

## 6. Day-2 Enhancements

Day-2 として追加してよいが、Day-1 gate の代替にはしない。

- Full ja/en catalog coverage and locale switch.
- Additional locale support.
- Wallet-specific polished flows for in-app browsers.
- Automated visual regression for the full screen inventory.
- Accessibility audit beyond the Day-1 visual/interaction smoke.
