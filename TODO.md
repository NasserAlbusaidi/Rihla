# TODO

Release blockers and architectural follow-ups from the 2026-05-26 reviews.

## Release blockers — group/event management review

- [ ] **Seal removed-member event write access.**
  - Problem: `leaveGroup` / `removeMember` remove the UID from `groups/{gid}.memberIds` but do not remove it from existing event `participantIds`. Firestore event subcollection writes currently trust `isEventParticipant(...)`, so a former member can still blind-write expenses, settlements, and activity if they know the path.
  - Target: require current group membership and a non-deleted event for event expense/settlement/activity writes; also clean or tombstone event participants when a member leaves/is removed.
  - Touchpoints: `security/firestore.rules`, `lib/features/groups/providers/group_provider.dart`, `lib/features/events/services/event_service.dart`, group/member removal tests, rules tests if available.

- [ ] **Keep deleted-event financial records in group balance integrity checks.**
  - Problem: `deleteEvent` soft-deletes the event, but `groupEventsProvider` filters deleted events out before `groupBalancesProvider` aggregates expenses/settlements. A deleted event can therefore make outstanding balances disappear from group settle-up and summaries.
  - Target: either block event deletion unless event balances are fully loaded and zero, or include deleted events' financial records in group-level balance/deletion safety checks until they are explicitly resolved.
  - Touchpoints: `lib/features/events/services/event_service.dart`, `lib/features/events/providers/event_provider.dart`, `lib/features/groups/providers/group_balance_provider.dart`, `lib/features/events/widgets/event_danger_section.dart`, balance regression tests.

- [ ] **Fail closed on destructive group/member actions when balances are not verified.**
  - Problem: leave group, delete group, and remove member only block when `groupBalancesProvider(...).valueOrNull` is present and non-zero. Loading, errored, or partially skipped balance streams can fall through to destructive actions.
  - Target: destructive actions must require an explicit "balances loaded and complete" state before proceeding. If balance data is loading/error/partial, show a retryable blocking state instead of allowing the action.
  - Touchpoints: `lib/features/groups/widgets/group_danger_section.dart`, `lib/features/groups/widgets/group_members_section.dart`, `lib/features/groups/providers/group_balance_provider.dart`, `test/features/groups/group_settings_screen_test.dart`.

## Follow-up — group/event UX and lifecycle polish

- [ ] **Align group deletion implementation and copy.**
  - Current mismatch: service hard-deletes group/member/invite docs and does not cascade event subcollections, while UI copy says events/expenses/balances are erased, cannot be undone, and also says a copy is kept for 30 days.
  - Decide the product contract: real soft-delete/retention, real cascade/tombstone job, or honest irreversible delete copy.
  - Touchpoints: `lib/features/groups/providers/group_provider.dart`, `lib/features/groups/widgets/delete_group_sheet.dart`, `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`.

- [ ] **Validate event date ordering.**
  - Prevent saving an event where `endDate` is before `startDate`; reset or constrain end date when start date moves later.
  - Touchpoints: `lib/features/events/screens/create_event_screen.dart`, `lib/features/events/widgets/event_info_section.dart`, event form tests.

- [ ] **Resolve event navigation intent.**
  - Current mismatch: group event rows route to `EventCommandCenter`, while code comments and the Phase 39 shape say event cards should route straight to the ledger surface because ledger is the only visible event module.
  - Decide whether the event hub is intentionally active again or should be deep-link compatibility only.
  - Touchpoints: `lib/features/groups/screens/group_detail_screen.dart`, `lib/features/events/screens/event_command_center.dart`, router tests.

- [ ] **Separate group/event title validation from display-name validation.**
  - Current behavior caps group and event names at the display-name limit and applies person-name-specific rules such as rejecting `" (former member)"`.
  - Target: introduce title-specific validation and mirror it in Firestore rules.
  - Touchpoints: `lib/core/utils/display_name_validator.dart` or a new validator, `lib/features/groups/screens/create_group_screen.dart`, `lib/features/events/widgets/event_details_card.dart`, `security/firestore.rules`.

## P1 — financial-correctness trust hole

- [ ] **Cloud Function trigger to validate expense writes.** On `groups/{gid}/events/{eid}/expenses/{xid}` create/update:
  - sum of `splitDistribution` values equals `amountFils` (within remainder tolerance for `equally` mode)
  - every key in `splitDistribution` and `customSplitParticipants` is in the event's `participantIds`
  - `splitMode` ∈ allowed enum; `scope` ∈ allowed enum
  - reject with a deletion or `isDeleted=true` flip if invalid; log to Sentry
  - Why: Firestore rules currently check `createdBy` and field presence but not the math. A misbehaving client can silently redistribute money. This is the only server-side gap that costs real money.
  - Touchpoints: new `functions/src/triggers/validateExpense.ts`; add export in `functions/src/index.ts`; rule update if any cleanup writes are needed.

## P2 — FCM server-side push

- [ ] **Cloud Function trigger to fan out expense additions over FCM.** On expense create:
  - look up `groups/{gid}.memberIds`, exclude the creator
  - read each member's `fcm_tokens/{uid}` doc
  - send "Nasser added $50 to The Boys" via `messaging.sendEachForMulticast`
  - localize via the message's currency + actor name (resolved from `members/{uid}.displayName`)
  - retire bad tokens (clean up on `UNREGISTERED` / `INVALID_ARGUMENT`)
  - Why: client-side token registration + `NotificationService` exists but nothing fans out. This is the retention loop for a group-spending app.
  - Touchpoints: new `functions/src/triggers/onExpenseCreate.ts`; `notification_service.dart` foreground handler already exists.

## P3 — `BalanceCalculator` location

- [ ] **Extract `BalanceCalculator` to `lib/features/ledger/services/balance_calculator.dart`.**
  - It is pure logic, no Riverpod dependency — wrong file today.
  - CLAUDE.md has a footnote calling this out as a footgun. The footnote is good docs; the file move is the real fix.
  - After move: drop the footnote line from `CLAUDE.md` Financial Calculations section.
  - Touchpoints: `lib/features/ledger/providers/expense_provider.dart:163-481` → new file; update all importers.

## P4 — Settlement scope sealing

- [ ] **Replace `Settlement`'s sentinel-`tripId` with a discriminated type.**
  - Today: `Settlement.fromFirestore` falls back to `tripId = data['eventId'] ?? groupId ?? ''` (`settlement_model.dart:102-104`). Empty-string is a latent footgun.
  - Target: `sealed class Settlement` with `EventSettlement` (has non-null `eventId`) and `GroupSettlement` (has non-null `groupId`, no event); kill the `scope` string field; update `BalanceCalculator` and `groupBalancesProvider` to pattern-match.
  - Migration: read-path is back-compat (existing docs still parse); no Firestore data migration needed.
  - Touchpoints: `lib/features/ledger/models/settlement_model.dart`, `lib/features/groups/providers/group_balance_provider.dart`, `lib/features/ledger/providers/expense_provider.dart`, tests under `test/features/ledger/`.

## P5 — Aggregation performance budget

- [ ] **Set and enforce a recomputation budget for `groupBalancesProvider`.**
  - Target budget: balances for 100 events × 50 expenses each computed in < 16ms on a release-mode Android device.
  - Add a benchmark test under `test/performance/` (or `test/integration/`) with synthesized data.
  - Open question: incremental fold vs. memoized aggregation. Don't optimise without the test first.
  - Why: today's groups are small so the O(events) `ref.watch` loop works. A 5-year-old group with 80+ events will feel it. Catch the regression before users do.
  - Touchpoints: `lib/features/groups/providers/group_balance_provider.dart:141-159`.

---

## Lower-priority cleanup (not part of the review's top-5)

- [ ] OMR hardcoding sweep — `Settlement.toFirestore` (`settlement_model.dart:130`), and the ~15 other sites tracked in memory.
- [ ] Dead-code pass: `OnboardingScreen` (unmounted), `EventCommandCenter` (dead-but-kept), legacy `ExpenseScope.subGroup` fallback, unused `Expense.toJson`/`fromJson` Supabase methods.
- [ ] Cache-drift observability: replace the `catch (_)` in `expense_provider.dart:69-72` with a Sentry breadcrumb so silent SQLite drift becomes visible.
