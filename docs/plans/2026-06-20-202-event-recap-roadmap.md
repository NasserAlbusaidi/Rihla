# Event Closeout & Shareable Recap — incremental roadmap (#202)

**Source issue:** #202 (`enhancement, P2, money, design, post-release, cluster:settlement-ux`)
**Date:** 2026-06-20
**Decision:** Split the epic into small, independently-shippable tracer-bullet slices. Each slice
leaves the tree green and ships standalone value; the later slices accrete into the *full original
scope* of #202 (close-lifecycle + frozen snapshot). No big-bang.

---

## Why split (the decision the issue's `decision` label is for)

The issue as written assumes an **explicit event-closure lifecycle state that does not exist**:
`Event` (lib/features/events/models/event_model.dart) has only `startDate`/`endDate`/`isPast` —
no `closedAt`/`closedBy`/read-only flag. The issue itself says "if event lifecycle work has not
landed yet, this issue should depend on it." So the full feature = a **backend epic** (schema +
firestore.rules + write path + snapshot-freeze + deploy) **plus** the recap UI.

The *picked value* — the shareable recap card (adoption viral-loop + portfolio showpiece) — does
**not** need any of that backend machinery if the recap is a **live, on-demand view**. So we ship
the value first (client-only, no deploy), then complete the original scope (lifecycle + snapshot).
The shared recap card looks identical in both; the lifecycle/snapshot is invisible backend.

## Reuse map (verified against code, 2026-06-20 — do not re-derive from memory)

| Need | Reuse | Anchor |
|---|---|---|
| per-person net, who-owes-who | `BalanceCalculator` (greedy min-transactions) | `lib/features/ledger/providers/expense_provider.dart:253`, debtors/creditors ~`:706` |
| memoized balances for an event | `ledgerViewProvider` | `lib/features/ledger/providers/ledger_view_provider.dart:51` |
| event expenses / settlements | `eventExpensesProvider`, `eventSettlementsProvider` | `expense_provider.dart:67,76` |
| event meta (name, dates, participants) | `eventDetailProvider` | `lib/features/events/providers/event_provider.dart:47` |
| money display | `RAmount` | (shared widget) |
| expense fields for folds | `amount` `_currency` `payerParticipantId` `payerName` `categoryId/Name/Icon` | `lib/features/ledger/models/expense_model.dart` |
| categories | `categoryProvider` / `ExpenseCategory` | `lib/features/ledger/providers/category_provider.dart` |
| text share | `shareText` (iOS `sharePositionOrigin`-safe chokepoint) | `lib/core/utils/share_helper.dart:13` |
| image share | `share_plus ^10.1.4` → `shareXFiles` (net-new wrapper) | `pubspec.yaml:60` |
| entry-point host | `EventCommandCenter` actions, ledger app bar | `event_command_center.dart:51`, `ledger_screen.dart` |

**Money invariant carried through every slice:** NEVER sum `Decimal`s across currencies — every
aggregate (total spent, biggest expense, top payer, breakdowns) is **per-currency bucketed**.
The recap consumes `BalanceCalculator` output; it does **not** change the oracle.

---

## Phase A — the recap value (client-only, no deploy)

### Slice 1 — Recap data core + tracer screen  ·  Gate: YES (money aggregation)
- Pure `EventRecap` value object: `totalSpentByCurrency`, `expenseCount`, current-user
  `shareByCurrency`/`paidByCurrency`/`netByCurrency`. Built from event expenses+settlements,
  reusing `ledgerViewProvider`/`BalanceCalculator` for net.
- `RecapScreen` rendering those core numbers (read-only, on-demand).
- Entry point: action on `EventCommandCenter` (+ ledger app bar), visible when event has ≥1 expense.
- l10n EN/AR/RTL.
- Tests (money rigor, table-driven): empty event, single-currency, **multi-currency**, **JPY×1**,
  settled vs unsettled. End-to-end user-visible.

### Slice 2 — Full money summary  ·  Gate: YES
- Enrich model + screen: biggest expense, top payer, **category breakdown**, **payer breakdown**,
  participant net balances, **settlement status** enum (everyone-even / outstanding / settle-event /
  settle-at-group) + event-vs-group settlement CTA copy ("settle this event" vs "settle at group").
- Tests extend the table; add the CTA-copy/path cases from the issue AC.

### Slice 3 — Polished recap moment + chart  ·  Gate: EXEMPT (display)
- "Wrapped" hero card: `{Event} wrapped`, participant count, date range (if any), total, biggest
  expense, top payer, category highlight + a small bar/category chart. Tasteful, no jokey superlatives.
- **Design-first:** rihla.css mockup gallery (current-vs-proposed) → lock the look → build.

### Slice 4 — Shareable recap card  ·  Gate: EXEMPT
- `shareImage(context, …)` util: `RepaintBoundary` → PNG → `shareXFiles`, mirroring `shareText`'s
  non-zero `sharePositionOrigin` (iOS landmine #308/#309). "Share recap" renders the card off-screen
  and shares it.
- Tests: mock the share channel; assert a file is shared **and** a non-zero origin is supplied.

→ **End of Phase A = the full lean recap is shipped.** No schema, no rules, no deploy.

## Phase B — complete the original #202 scope (backend, Gate, deploy)

### Slice 5 — Event close lifecycle  ·  Gate: YES · Deploy: rules
- Add `closedAt`/`closedBy` to `Event` (+ `fromDoc`/`toFirestoreMap`/`copyWith`).
- firestore.rules: who may close (creator/admin); closed event → read-only for new expense writes.
- "Close trip" action + client read-only enforcement. Recap gains "wrapped" finality for closed events.

### Slice 6 — Snapshot freeze  ·  Gate: YES · Deploy: rules (+ maybe a Function — decide in slice spec)
- On close, persist `spendingSnapshot` (frozen recap numbers) so the spending story is immutable
  post-close, while **settlement status stays live**. Recap reads snapshot for closed events, live
  otherwise. Completes #202 (`closedAt/closedBy/spendingSnapshot/recapSnapshot`).
- Tests: recap snapshot does not change from later settlement writes (issue AC).

---

## Process per slice
- Money/rules/schema slices (1, 2, 5, 6): **run the Gate on the slice spec before coding** (`/run-the-gate`).
- Bug-fix discipline N/A (feature) but each slice is RED→GREEN: write the defining test first.
- `flutter analyze` clean + relevant tests green before "done". Conventional commits. `/automerge` per PR.
- Phase B PRs that touch rules/Functions → `deploy-ceremony` after merge.

## Out of scope (from #202, all phases)
Full memories module · AI-generated narratives · social feed · receipt OCR · automatic
date-based closure · changing group-level settlement math.
