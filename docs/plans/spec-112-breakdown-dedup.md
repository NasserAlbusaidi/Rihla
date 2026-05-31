# Spec: #112 — drop redundant `ref.watch` in `_buildPerEventBreakdown`

Repo: `/Users/nasseralbusaidi/Desktop/Personal/Rihla-perf` (worktree, branch off `main` @ 5dd963a).

## Goal
`_buildPerEventBreakdown` (`group_balance_provider.dart:373–414`) re-`ref.watch`es `eventExpensesProvider`/`eventSettlementsProvider` (`:383,385`) — data the main aggregation loop already watched (`:143–144`) and bucketed into `expensesByEvent`/`eventSettlementsByEvent` (`:198–209`). Pass those maps in; drop the redundant watch. **KEEP both `calculateBalances` calls** — the breakdown's participant set is `event.participantIds` ONLY (`:388`); the main loop's is `participantIds + formerActors` (`:237–240`). Unifying would drop former-actor shares and regress per-event nets (the issue's explicit ⚠️).

## Changes (`group_balance_provider.dart` only)
- **Signature:** `_buildPerEventBreakdown(List<Event> events, Map<String, List<Expense>> expensesByEvent, Map<String, List<Settlement>> eventSettlementsByEvent)` — drop `Ref ref` and `String groupId`.
- **Body:** replace the two `ref.watch(...)` lines + the `eventRef` local with:
  ```dart
  final expenses = expensesByEvent[event.id] ?? const <Expense>[];
  final settlements = eventSettlementsByEvent[event.id] ?? const <Settlement>[];
  ```
  Keep UNCHANGED: `participants = event.participantIds.map(...)`, `if (participants.isEmpty) continue;`, the `calculateBalances` call, the breakdown fill.
- **Call site (`:335`):** `_buildPerEventBreakdown(events, expensesByEvent, eventSettlementsByEvent)`.
- Update the doc comment (`:371–372`) — no longer calls `ref.watch`.

## Why behavior-neutral
`expensesByEvent[event.id]` is built from the same per-event `eventExpensesProvider` watch (`allExpenses`, `:157`) bucketed by `expense.tripId` (`:204–206`), which equals `event.id` for in-event data; loading/errored events → empty in both paths. No subscription is dropped: the main loop already watches the same providers, so the breakdown's watches were pure redundancy. The participant construction is untouched, so the participantIds-only-vs-formerActors distinction is preserved by construction.

## Regression test (`test/unit/group_balance_provider_test.dart`)
NEW case proving the two participant sets stay distinct after the refactor:
- Group with one event; a FORMER member (in expenses as payer, NOT in `liveMemberIds`, NOT in `event.participantIds`) plus a current participant; include a group-scoped settlement or a second event to exercise aggregation.
- Assert: aggregate `balances` includes the former actor's net (formerActors path), but `perEventBreakdown[formerUid]` is ABSENT (participantIds-only excludes them); a current participant's breakdown net matches their event-local net.
- This fails if the breakdown is ever re-sourced from a formerActors-inclusive participant set.
