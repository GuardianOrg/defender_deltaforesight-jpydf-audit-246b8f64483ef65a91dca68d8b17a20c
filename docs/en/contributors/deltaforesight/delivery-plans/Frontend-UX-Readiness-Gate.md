# Frontend UX Readiness Gate

Updated: 2026-07-26

This runbook defines the mainnet delta gate specific to i18n, mobile, wallet, and transaction-failure layout for the User App and, until monitoring decommission completes, the transitional public Ops UI. It assumes the common decision in [Frontend Production Delivery Gate](Frontend-Production-Delivery-Gate.md); live-data, redaction, release, and rollback controls are not repeated. The Japanese version is the source of truth. This document supports Frontend spec
`FRNT-FR-009`, `FRNT-FR-010`, `FRNT-ERR-004`, `FRNT-TBD-008`, and
`FRNT-TBD-009`.

## 1. Scope

In scope:

- Critical User App flows, primary-locale display copy, numbers, and error copy.
- Mobile viewport and wallet / tx confirmation / failure states.
- If the transitional public Ops UI remains published, its public routes and critical-health display.

Out of scope:

- Admin Control / Private Operations Monitor, which are governed by
  [Admin-Console-Production-Gate.md](Admin-Console-Production-Gate.md).
- Dune Public Analytics query/dashboard acceptance, governed by [Public Analytics / Private Monitoring Architecture](../operations/Public-Analytics-Private-Monitoring-Architecture.md).
- Complete coverage for every locale. Day-1 gates on primary-locale completion;
  do not expose incomplete locale switches.
- Advanced wallet in-app browser optimization. Broken signing or return flows are
  still Day-1 blockers.

## 2. Day-1 Minimum Gate

| Gate | Day-1 requirement | Evidence |
| --- | --- | --- |
| Primary locale freeze | Declare the primary locale in launch evidence. Align CTAs, headings, descriptions, empty/error/loading copy for all reachable screens in the primary locale. | Locale decision, screen inventory, copy review |
| Incomplete locale switch | If a secondary locale is incomplete, do not expose a locale switch. Do not make mixed locales the user-facing default. | Locale switch state, route screenshot |
| JPYdf terminology | Do not leave reachable-screen `BOLD` / `sBOLD` / upstream staking / Liquity-only reward copy. Base package names and vendored code names are out of scope. | Grep evidence, screen spot check |
| JPY formatting | Amounts, prices, and collateral values use JPY as primary display, with grouping, decimals, and rounding direction aligned to FRNT-FR-009. | Amount snapshot, rounding spot check |
| Unknown tx failure | Show the error ID, transaction hash, safe retry action, and support context already redacted by the common gate. | Unknown failure drill |
| Mobile viewport matrix | Check at least 360x740, 390x844, 430x932, 768x1024, and desktop baseline. Horizontal page scroll, overlap, clipping, or invisible CTAs are No-Go. | Screenshot set, visual review |
| Wallet modal | Verify connect / chain mismatch / reject signature / pending / success / failure at mobile widths. Wallet modals must not hide CTAs or error text. | Wallet state screenshots |
| Tx confirmation | On borrow, deposit, redeem, claim, repay / adjust confirmation screens, amount, asset, chain, recipient, fee / gas compensation, and warning copy remain readable on mobile. | Tx confirmation screenshots |
| In-wallet browser minimum | MetaMask / Rabby / Safe in-app browser polish is Day-2, but back navigation, post-signature return, long error copy, and chain-switch failure must not break. | In-wallet smoke evidence or documented blocker |
| Transitional public Ops scanning | If still published, its critical health / oracle / stale-stats / incident banner remains readable on mobile; numeric tables may use explicit horizontal scroll. | Public Ops mobile screenshots |

## 3. No-Go Conditions

Do not publish the mainnet User App or transitional public Ops UI if any of the following remain true.

- Reachable screens still show upstream user-facing `BOLD` / `sBOLD` / Liquity
  staking / fake reward copy.
- A locale switch exists and the target locale is untranslated or not normalized
  to JPYdf terminology.
- Critical CTA or tx confirmation amount / asset / recipient is unreadable on
  mobile widths.
- Error / wallet modal / banner covers other controls and cannot be dismissed.
- On mobile, borrow / deposit / redeem / claim cannot be started, canceled, or
  recovered after failure.

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
6. Drill unknown transaction-failure layout and recovery action.
7. Record any known limitation as Day-2 only if it does not violate No-Go.
8. Attach evidence to launch evidence and record Go / No-Go.

## 6. Day-2 Enhancements

These may be added on Day-2, but they do not replace the Day-1 gate.

- Full ja/en catalog coverage and locale switch.
- Additional locale support.
- Wallet-specific polished flows for in-app browsers.
- Automated visual regression for the full screen inventory.
- Accessibility audit beyond the Day-1 visual/interaction smoke.
