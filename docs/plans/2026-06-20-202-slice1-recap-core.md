# Slice 1 — Recap data core + tracer screen (#202)

**Parent roadmap:** `docs/plans/2026-06-20-202-event-recap-roadmap.md`
**PR carries:** `Refs #202`
**Classification:** display-only money surface (INBOUND). Reuses `BalanceCalculator` output; the only
derived number is per-currency `settled = net − (paid − owed)` (exact Decimal subtraction, no
division, no cross-currency fold). Gate run as the epic's foundational money-display contract.

**Gate round 1 findings applied (3 P1s):** (1) settlement reconciliation — `net ≠ paid − share`
when a settlement touched the user, so the screen now shows a reconciling `settled` row; (2) uid
source — use the reactive, test-injectable `currentUserIdProvider`, NOT `FirebaseConfig.currentUser`;
(3) `participantCount` defined as the live roster (`event.participantIds.length`), not the balance
universe (which inflates the count with departed/tombstoned members per #249).

## Goal
A pure, on-demand recap of one event showing its core money story, computed live from the
ledger. No event-closure state, no snapshot, no sharing yet (later slices). End-to-end and
user-visible: an entry point opens a `RecapScreen` showing total spent, expense count, and the
current user's paid / share / settled / net — all per currency.

## Data contract — `EventRecap` (new pure value object)

File: `lib/features/events/models/event_recap.dart` (closeout/recap is an event-lifecycle concern;
Phase B slices 5–6 extend `Event` itself, so it lives under `events/`).

```
class EventRecap {
  final String eventId;
  final String eventName;
  final DateTime? startDate;        // from Event; may be null (fuzzy dates)
  final DateTime? endDate;
  final int participantCount;       // = event.participantIds.length (LIVE roster; see Gate P1#3)
  final int expenseCount;           // non-deleted (watchExpenses already filters isDeleted==false)
  final Map<String, Decimal> totalSpentByCurrency;   // = BalanceCalculator.calculateTotalExpensesByCurrency(expenses)
  final Map<String, Decimal> userPaidByCurrency;     // current user's UserBalance.totalPaid per ccy (pre-settlement)
  final Map<String, Decimal> userShareByCurrency;    // current user's UserBalance.totalOwed per ccy (pre-settlement)
  final Map<String, Decimal> userSettledByCurrency;  // net − (paid − owed) per ccy; settlements given(+)/received... see sign note
  final Map<String, Decimal> userNetByCurrency;      // current user's UserBalance.netBalance per ccy (folds settlements)
  final bool isEmpty;               // expenseCount == 0
}
```

**Shared key set (Gate R2 P1):** all four user maps (`userPaid/userShare/userSettled/userNet`)
share ONE key set = currencies where the current user is **present** in `view.balances` AND not
entirely zero (i.e. `totalPaid != 0 || totalOwed != 0 || settlementAdj != 0`). `net` is carried for
those keys **even when it is 0**. Do NOT key the paid/share maps on `net != 0` — a participant who
paid exactly their share is square (`net == 0`) but DID spend, and the recap must still show their
Paid/Share. (This is why `myNetByCurrency`, whose filter is `net != 0`, is the WRONG helper here.)

**Reconciliation invariant (pinned by test):** for every key,
`userNetByCurrency[ccy] == userPaidByCurrency[ccy] − userShareByCurrency[ccy] + userSettledByCurrency[ccy]`.
Derived from `expense_provider.dart:417-422`: `netBalance = (totalPaid + settlementAdj) − totalOwed`,
so `settlementAdj = net − paid + owed`. `userSettledByCurrency[ccy]` = that `settlementAdj` (sign:
positive = the user GAVE settlements; `adjMap += amount` for a payer at `expense_provider.dart:397`,
`-= amount` for a recipient at `:401` → received settlements are negative). Screen labels it
neutrally ("settlements") and only renders it when non-zero.

All `Decimal`. NEVER summed across currencies — every money field is a per-currency map keyed by
currency code. The recap **selects** from already-bucketed `BalanceCalculator` output.

## Build path (reuse, don't recompute)

`eventRecapProvider = Provider.family<EventRecap, EventRef>` that watches:
- `ledgerViewProvider(eventRef)` → `eventTotal` (Map<ccy,Decimal>) + `balances` (Map<ccy,List<UserBalance>>).
- `eventExpensesProvider(eventRef)` → `.length` for `expenseCount` (already isDeleted-filtered).
- `eventDetailProvider(eventRef)` → name / dates / `participantIds`.
- `currentUserIdProvider` (`group_balance_provider.dart:528`) → `uid` (reactive + test-injectable
  via `overrideWith`; the blessed source every peer money surface uses — `ledger_screen.dart:101`,
  `settle_up_screen.dart:166`, etc.). Do NOT read `FirebaseConfig.currentUser`.

Assembly:
- `totalSpentByCurrency = view.eventTotal`.
- Single pass over `view.balances` (do NOT use `myNetByCurrency` — wrong filter, see above). For
  each `ccy`, find the `UserBalance` where `participantId == uid`. Include `ccy` in all four user
  maps iff that balance is present AND `totalPaid != 0 || totalOwed != 0 || (net − paid + owed) != 0`.
  For an included key: `userPaid[ccy]=totalPaid`, `userShare[ccy]=totalOwed`,
  `userSettled[ccy]=netBalance − totalPaid + totalOwed`, `userNet[ccy]=netBalance` (carried even if 0).
- `participantCount = event.participantIds.length`. `expenseCount = expenses.length`.
- Null `uid` (logged-out / non-member viewer) → all four user maps `{}`, totals still present.
- **Null/loading/soft-deleted event** (`eventDetailProvider(eventRef).valueOrNull == null`, Gate R3
  P2) → provider returns an empty recap (`isEmpty: true`, `eventName: ''`, `participantCount: 0`, all
  maps `{}`); `ledgerViewProvider` already returns empty maps for a null event
  (`ledger_view_provider.dart:63-77`), so this is consistent. The **screen** watches
  `eventDetailProvider` and renders a not-found state for a hard-missing event (deep-link to a
  deleted event), mirroring `ledger_screen.dart:85`.

### Design: pure builder for testability
`EventRecap.from({required String eventName, DateTime? startDate, DateTime? endDate, required
List<String> participantIds, required int expenseCount, required Map<String,Decimal>
totalSpentByCurrency, required Map<String,List<UserBalance>> balances, required String? uid})` — a
**pure static factory** (no Riverpod, no Firestore) holding ALL the assembly logic above. The table
tests call it directly with hand-built inputs (mirrors how `myNetByCurrency`/`allocateExpenseOwed`
are pure + unit-tested). `eventRecapProvider` is a thin wrapper that watches the four providers and
calls `EventRecap.from`.

### Currency-key contract (verified, Gate-confirmed)
`view.eventTotal` is keyed by **expense** currencies; `view.balances` is keyed by
**paid ∪ settlementAdj** currencies (`expense_provider.dart:409-412`). They can differ:
- **Settlement-only currency** (EUR settlement, no EUR expense): in `balances`, not in `eventTotal`
  (proven by `balance_calculations_test.dart:574`). → user net/settled show for EUR; no EUR
  total-spent line. The screen iterates the union of currency keys and tolerates a missing total.
- **Expense currency with no current-user involvement**: in `eventTotal`, omitted from user maps.

## Entry point
- New route constant `AppRoutes.eventRecap = '/group/:gid/event/:eid/recap'` in
  `lib/core/router/app_router.dart` (every path is a static `AppRoutes.*` constant — no inline
  literal, no `goNamed`, no `extra`; params from path). Add a `GoRoute(path: 'recap', …)` to the
  `event/:eid` `routes:` list, exactly mirroring the existing nested `'ledger'`/`'activity'`/
  `'settings'` children (whose constants are `AppRoutes.eventLedger`/`eventActivity`/`eventSettings`;
  hub is `eventHub`). Back-guard: nested ⇒ `canPop()` always true ⇒ bare
  `if (GoRouter.of(context).canPop()) pop()` (the #243 nested convention; verified both
  `EventCommandCenter:1324` and `LedgerScreen:505` do exactly this).
- Entry button with a stable test key (`EventKeys.recapButton`) on the `EventCommandCenter` hub
  actions — the canonical "this event" landing. Gated visible only when the event has ≥1 expense
  (passed `onRecap: expenses.isEmpty ? null : …`; the header hides the button when `onRecap == null`).
  **Scope note (as-built):** the secondary `LedgerScreen` app-bar button is DEFERRED to a fast-follow
  to keep this slice focused — the hub entry already makes the recap reachable. One entry point, fully
  tested, beats threading a second callback through the ledger `_CoverHeader` in the same PR.
- **Empty-state reachability (Gate P2):** since both buttons hide at 0 expenses, the `isEmpty`
  branch is reachable ONLY via cold deep-link to `/recap`. Keep a minimal empty state for that
  edge; do NOT add a widget test that expects to reach it via a button (it can't).

## Tracer screen (`event_recap_screen.dart`)
Read-only. Renders:
- Header: event name + date range (if both non-null) + `participantCount` / `expenseCount`.
- "Total spent" — one `RAmount(value:, currency:)` row per currency in `totalSpentByCurrency`
  (pass the per-bucket ccy code, never `group.currency`).
- "You" block — per currency in the user-map key set: render Net always; render Paid / Your share /
  Settlements only when that value `!= 0`. The shown rows reconcile (`net = paid − share + settled`),
  so a square participant sees Paid 100 · Share 100 · Net 0 (not a blank block), and a
  settlement-only currency sees Settlements ∓X · Net ∓X (Paid/Share suppressed as 0).
- Empty event (`isEmpty`, deep-link only) → `EmptyStateView` ("Nothing to wrap up yet").
- l10n EN + AR (RTL): all strings via `context.l10n`; `EdgeInsetsDirectional` / directional layout.

## Tests (money rigor — table-driven; RED first)
`test/features/events/event_recap_test.dart` (pure provider; inject uid via
`currentUserIdProvider.overrideWith((_) => uid)` + `FakeFirebaseFirestore`/seeded streams or a
`ledgerViewProvider` override) + a thin widget test.
Cases:
1. Empty event (0 expenses) → `isEmpty`, all maps empty.
2. Single currency, unsettled → totals + paid/share/net; `settled == 0`; reconciliation holds.
2b. **Square-but-active participant (the Gate R2 P1 regression guard)** — user paid exactly their
   own share (paid 100, share 100, NO settlement) → `net == 0` but the bucket is KEPT (paid≠0) and
   Paid 100 / Share 100 still render. The "You" block must NOT be blank for a settled-up spender.
3. **Settled scenario (the Gate R1 P1#1 trap)** — user paid 100, share 50, received a 50 settlement →
   net 0; assert the screen/model surface `settled` and that `net == paid − share + settled` (0 == 100−50+(−50)). The displayed rows must reconcile.
4. **Multi-currency** (USD + OMR) → two keys in every map; values bucketed, never cross-summed.
5. **JPY (×1 subunit scale)** present → integer yen, no fractional drift.
6. **Settlement-only currency** (EUR settlement, no EUR expense) → EUR in user net/settled maps,
   absent from `totalSpentByCurrency`; no throw.
7. **Current user null / not a participant** → totals present, all user maps empty; no throw.
8. **Departed/tombstoned former member with residual balance (Gate P1#3, identity axis)** →
   `participantCount == event.participantIds.length` (NOT inflated by the #249 universe fold);
   pin that a member removed from `participantIds` doesn't bump the count even though they appear
   in `view.balances`.
9. Widget: entry button hidden at 0 expenses, shown at ≥1 (target via `LedgerKeys.recapButton`);
   screen renders per-currency rows; reconciliation visible in a settled case; EN + AR.

## Out of scope (later slices)
Biggest expense, top payer, category/payer breakdowns, participant-balance list, settlement-status
CTA (Slice 2) · polished "wrapped" card + chart (Slice 3) · share-as-image (Slice 4) · close
lifecycle + snapshot (Slices 5–6).
