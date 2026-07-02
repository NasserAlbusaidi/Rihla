# #204 Slice 1 — pre-settlement review: departed-payer trigger

**Date:** 2026-07-01
**Issue:** #204 (pre-settlement review — expansion). MVP shipped #514.
**Delivery:** PARTIAL → `Refs #204` (issue stays open, re-scoped). Not `Closes`.
**Gate:** Round 1 verdict NEEDS-REWORK ([P1] test-helper breakage from `uncategorized`; [P2] `uncategorized` fires on nearly every settle-up). Resolved by dropping `uncategorized` to a deferred product decision and scoping this slice to the one clean, rare, high-value trigger. Re-Gated (round 2) on this revised spec.

## Goal

Add ONE new `ReviewReason` to the pure detector `detectReviewWorthyExpenses`, surfaced in the existing event settle-up pre-settlement review sheet:

- **`payerNotInParticipants`** — a live expense whose payer is no longer an event participant (the departed-payer / #249 conservation-gap class). Rare (only after a member leaves), high-value (money attributed to someone gone), unambiguous.

No balance math changes. No new persisted field. No server/rules change. Sheet stays non-blocking and display-only.

## Explicitly deferred (documented so the loop won't re-pick blindly)

| Candidate | Why deferred |
|---|---|
| `uncategorized` | Reachable — **too** reachable. Category is optional at the write path (`expense_editor_body.dart:155,219,348` — `_selectedCategoryId` starts null, never force-defaulted), so a large fraction of real expenses carry `categoryId: null`. A raw `categoryId == null` trigger would pop the sheet on nearly every settle-up, converting a rare nudge into an almost-always modal — degrading the feature. Needs a product decision: gate on a fraction, make it an info-only count line (never a sheet-trigger on its own), or make category mandatory at write. Out of this slice. |
| `recentlyEdited` | **Blocked** — `Expense` has `lastEditedBy` (a UID) but **no edit timestamp**. Needs a new `updatedAt` field + Firestore rules + every write-path stamping `serverTimestamp`. Separate schema PR. |
| `softDeletedInHistory` | **Data not at callsite** — `ExpenseService.watchExpenses` appends `.where('isDeleted', isEqualTo: false)`; soft-deleted docs never reach the detector. Needs a deleted-inclusive read or the Trip-Receipt audit provider. Separate PR. |
| `participantExcludedFromGlobal` | Reachable (global exact/shares/percent allocate over `splitDistribution.keys` ignoring scope — `expense_provider.dart` `allocateExpenseOwed`) but **false-positive-prone** (intentional exclusions) and overlaps `exactSplit` for the exact case. Needs a product framing call. |
| `itemizedSplitMetadata` | **Redundant** — every itemized split is `SplitMode.exact`, already flagged by `exactSplit`. Net noise. |
| Group-level trigger (acceptance box #1) | Read-cost approach now **decided**: the O(G×E) streams are already open at `group_settle_up_screen` (via `groupBalancesProvider`); `computeGroupBalances` already holds the raw expenses but discards them from the `GroupBalances` record. Thread `allExpenses` through and run the detector at settle-up-open time → zero new reads. Cleanly separable follow-up (has a group-scope participant-universe wrinkle). |

## Design

### Detector signature (`lib/features/ledger/services/pre_settlement_review.dart`)

```dart
enum ReviewReason { exactSplit, customParticipants, personal, largeAmount, payerNotInParticipants }

List<ReviewFlag> detectReviewWorthyExpenses(
  List<Expense> expenses, {
  Decimal? largeFraction,
  Set<String> activeParticipantIds = const {},   // NEW — empty = "unknown", disables the payer check
}) { ... }
```

Inside the `for (final e in live)` loop, after the existing four `if` blocks:

```dart
// Empty set = caller didn't supply the universe → do NOT fire (avoids flagging
// every payer when participantIds is unknown, e.g. old callers / existing tests).
if (activeParticipantIds.isNotEmpty &&
    !activeParticipantIds.contains(e.payerParticipantId)) {
  flags.add(ReviewFlag(e, ReviewReason.payerNotInParticipants));
}
```

**Load-bearing guard:** `activeParticipantIds.isEmpty → skip`. With a default-empty set an unguarded `!contains(...)` would flag EVERY expense. The empty-set-means-unknown contract keeps existing single-arg detector calls and the member-error fallback from spuriously flagging every payer.

**Active-set contract (post-automerge Gate fix):** the callsite passes current event participants narrowed to live group members:

```dart
final activeParticipantIds = event.participantIds
    .toSet()
    .intersection(liveMemberIds);
```

This catches BOTH axes that make the payer inactive for this event:
- **left / removed from group:** member doc absent or tombstoned → excluded from `liveMemberIds`, even if old event data still carries the payer id.
- **removed from this event by an admin:** omitted from `event.participantIds`, even if still a live group member.

The earlier live-member-only contract missed the second case. Rules allow event admins to remove participants (`validEventAdminUpdate` allows `participantIds` mutation), so a live group member who paid and was later removed from the event must still surface in this display-only review sheet.

**Identity axis:** `event.participantIds`, `liveMemberIds` (member `userId`), and `payerParticipantId` share the same id-space — member `userId`, auth-uid or shadow-uuid alike. During member-load `liveMemberIds` is not authoritative; the callsite waits for a resolved member value before supplying the active set. If members error, the callsite uses the single-arg detector path so older exact/custom/personal/large warnings still render and only this membership-sensitive reason is skipped.

### Sheet (`lib/features/ledger/widgets/pre_settlement_review_sheet.dart`)

- `_reasonOrder` (const list, **no compiler guard** — runtime landmine): append `payerNotInParticipants` at the end (lowest priority — a departed-payer expense that is ALSO exact/large keeps its existing primary chip; no existing primary-chip changes):
  ```dart
  const _reasonOrder = [
    ReviewReason.largeAmount,
    ReviewReason.personal,
    ReviewReason.customParticipants,
    ReviewReason.exactSplit,
    ReviewReason.payerNotInParticipants,
  ];
  ```
  It MUST appear here or `_primaryReason`'s `firstWhere(reasons.contains)` (line 86, no `orElse`) throws `StateError` for an expense carrying only this reason, and the count line silently never renders.
- `_reasonLabel` switch (exhaustive — compiler enforces): add `ReviewReason.payerNotInParticipants => context.l10n.preSettleReviewReasonPayerLeft`.
- `_countLine` switch (exhaustive): add `ReviewReason.payerNotInParticipants => context.l10n.preSettleReviewPayerLeftCount(count)`.

### l10n (EN template + AR)

`lib/l10n/app_en.arb` — 2 new keys with `@` metadata mirroring existing `preSettleReview*` blocks:
- `preSettleReviewPayerLeftCount` = `{count, plural, =1{1 paid by someone who left} other{{count} paid by people who left}}` + `@` with `placeholders:{count:{type:int}}`
- `preSettleReviewReasonPayerLeft` = `Payer left` + `@` with `description`

`lib/l10n/app_ar.arb` — same 2 keys, **value-only (no `@` metadata** — AR carries none for `preSettleReview*`):
- `preSettleReviewPayerLeftCount` = `{count, plural, =1{مصروف دفعه شخص غادر} other{{count} مصاريف دفعها أشخاص غادروا}}`
- `preSettleReviewReasonPayerLeft` = `الدافع غادر`

Then `flutter gen-l10n` to regenerate `lib/l10n/generated/*` (committed files → regen+commit mandatory). Getters: `String get preSettleReviewReasonPayerLeft`, `String preSettleReviewPayerLeftCount(int count)`.

### Callsite (`lib/features/ledger/screens/settle_up_screen.dart`)

`_maybeShowReviewSheet(context, expenses)` (called inside `data:(expenses)`) → thread the active event-participant set (`event.participantIds ∩ liveMemberIds`, in scope at the callsite):

```dart
void _maybeShowReviewSheet(
  BuildContext context,
  List<Expense> expenses,
  Set<String> activeParticipantIds = const {},
) {
  ...
  final flags = detectReviewWorthyExpenses(
    expenses, activeParticipantIds: activeParticipantIds);
  ...
}
```
Caller passes `event.participantIds.toSet().intersection(liveMemberIds)`. Do not pass only `liveMemberIds` (misses event-admin removals) or only `event.participantIds` (misses departed/tombstoned group members).

**Latch-race/error guard — don't latch membership-sensitive detection before members resolve, but preserve existing warnings on member-load error.** `_maybeShowReviewSheet` is a one-shot (`_reviewSheetShown` latch), but the loader gate waits only on `eventDetail`+`groupDetail`, NOT `groupMembersProvider`. If expenses resolve before members, `liveMemberIds` is not authoritative; and if any OTHER reason fires, the sheet could latch and permanently drop the payer-left flag for the entry. Fix: capture the AsyncValue (`final groupMembersAsync = ref.watch(groupMembersProvider(widget.groupId)); final groupMembers = groupMembersAsync.valueOrNull ?? [];`) and branch:
```dart
if (groupMembersAsync.hasValue) {
  final activeParticipantIds = event.participantIds
      .toSet()
      .intersection(liveMemberIds);
  _maybeShowReviewSheet(context, expenses, activeParticipantIds);
} else if (groupMembersAsync.hasError) {
  _maybeShowReviewSheet(context, expenses);
}
```
This defers the one-shot while members are still loading, but on member-provider error it falls back to the old detector path. That means exact/custom/personal/large warnings still show, while `payerNotInParticipants` remains skipped because the active set is unknown.

## Verification principles (run now)

1. **Callsite classification** — detector is INBOUND/display-only (feeds a modal, never a write). `activeParticipantIds` read-only. No OUTBOUND path. ✔
2. **Concrete claims vs code** — `event.participantIds` is `List<String>` (`event_model.dart:82`, used at `settle_up_screen.dart:277-279`); `payerParticipantId` is `String` (`expense_model.dart:29`). ✔
3. **Read-path per write-path** — no write path; the only reader of the flags is the sheet. ✔
4. **Fields from the type** — enumerated from `expense_model.dart`; the departed-payer check needs only `payerParticipantId` (present) + the caller's participant set. ✔
5. **Data contracts** — `detectReviewWorthyExpenses(List<Expense>, {Decimal? largeFraction, Set<String> activeParticipantIds})`; fires iff `activeParticipantIds.isNotEmpty && !contains(payerParticipantId)`. ✔
6. **Arithmetic decomposition** — n/a (no aggregate; largeAmount per-currency math untouched). ✔
7. **Adversarial pass (membership-semantics axis)** — the correct "active" set is `event.participantIds ∩ liveMemberIds`: live-member-only misses event-admin removals, event-participant-only misses departed/tombstoned group members. Empty-set default means old callers can't spuriously flag every payer. ✔

## Test plan (RED first)

`test/unit/pre_settlement_review_test.dart` — extend `_exp` with a `payerParticipantId` override (currently hardcoded `'uid-a'`), then add under `group('detectReviewWorthyExpenses')`:
- **fires:** `detectReviewWorthyExpenses([_exp(id:'a', payerParticipantId:'uid-z'), _exp(id:'b', payerParticipantId:'uid-a')], activeParticipantIds:{'uid-a'})` → `payerNotInParticipants` on `'a'` only.
- **no-warning path (guards old callers):** same list with NO `activeParticipantIds` (default `{}`) → NO `payerNotInParticipants` flag even though `'uid-z'` is absent.
- **multi-reason:** an exact-split expense paid by a departed member carries `{exactSplit, payerNotInParticipants}` (and `largeAmount` if dominant).
- Existing 9 detector tests + `reviewItemList` tests need **NO edit** — they call the single-arg form → default empty set → payer check skipped (Gate round 1 confirmed). (No `_exp` `categoryId` change needed — `uncategorized` dropped.)

`test/features/ledger/pre_settlement_review_sheet_test.dart` — add a `testWidgets`: build a flag list where `payerNotInParticipants` is the **only** reason on the expense (plain global/equal, non-dominant → the last-in-`_reasonOrder` reason IS the primary chip); open the sheet; assert the EN count line `1 paid by someone who left` renders AND the `Payer left` chip appears.

**End-to-end assertions (the unit test can't catch wrong-set wiring, and fixtures must DISCRIMINATE):** add widget tests on `SettleUpScreen`:
- departed group member: `event.participantIds = ['stay', 'gone']`, `groupMembersProvider` yields only `stay`, a live expense paid by `gone` → catches participant-only wiring.
- event-admin removal: `event.participantIds = ['stay']`, `groupMembersProvider` yields `stay` and live `gone`, a live expense paid by `gone` → catches live-member-only wiring.
- member-provider error fallback: `groupMembersProvider` errors, exact-split expense still surfaces the sheet → catches whole-sheet suppression.

## Definition of done

- [ ] RED: new tests fail before implementation, for the right reason.
- [ ] Callsite passes `event.participantIds ∩ liveMemberIds` — end-to-end tests prove both departed group members and event-removed payers trigger.
- [ ] Detector + sheet + EN/AR ARB + generated l10n + callsite updated.
- [ ] `flutter gen-l10n` run; generated getters present + committed.
- [ ] `flutter analyze` clean; `bash tool/check_theme_purity.sh` clean (sheet edits touch no colors, but run it).
- [ ] `flutter test test/unit/pre_settlement_review_test.dart test/features/ledger/pre_settlement_review_sheet_test.dart` green, then full suite.
- [ ] Existing detector/sheet tests green with **zero edits** (empty-set default proves it).
- [ ] Commit body + PR body carry `Refs #204` (partial); PR names the deferred items (esp. the `uncategorized` product decision).
- [ ] #204 re-scoped comment posted (this slice done; `uncategorized` + remaining long-tail + group-level still open).
