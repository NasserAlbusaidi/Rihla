# #898 Pre-Settlement Review: Settled-Bucket Suppression — Implementation Plan

> **For the executor:** work task-by-task, RED before GREEN, commit after each task.
> Spec-verified via the Gate (fresh-context review) before implementation.

**Goal:** The pre-settlement review sheet (#204) stops warning about suspicious expenses whose currency bucket is already fully settled, at BOTH event and group settle-up entry (P1, `1.7.4+32` QA finding).

**Architecture:** Detection stays pure and expense-only (`detectReviewWorthyExpenses` untouched). A new pure filter suppresses flags whose expense currency has no outstanding balance. Each scope supplies its own "outstanding currencies" set from the SAME balance basis its screen already displays — event scope from the `BalanceCalculator.calculateBalances` result computed in the same build callback; group scope from `groupBalancesProvider` inside `groupPreSettleReviewProvider` (zero new listeners — the screen already watches it).

**Tech stack:** Flutter/Riverpod 2.x, `decimal`, existing test helpers (`FakeFirebaseFirestore` not needed — provider overrides, see reference tests).

---

## Locked decisions (do not re-litigate)

1. **"Outstanding" is defined per currency bucket: ∃ participant with `netBalance != Decimal.zero` in that bucket.**
   Rationale: available identically at both scopes (the group provider has nets, not optimizer output), conservative (any imbalance keeps the warning), and equivalent to "optimizer emits ≥1 transfer" in all conserving cases. Strict `!= Decimal.zero` matches the app's canonical settled definition — `nonZeroNetsGccFirst` (`expense_provider.dart`, documented "EXACT `!= Decimal.zero` — no tolerance"); cross-reference it in the new filter's dartdoc so a future tolerance change can't silently diverge the two. The issue's "stronger fix" (per-expense contribution filtering) is REJECTED: an individual expense's contribution is not well-defined after netting — a settled-out expense still shaped the net. Bucket-zero is the crisp, explainable signal.
2. **Suppression is a display filter, INBOUND-only.** `pre_settlement_review.dart` keeps its "no money calculation" contract — the filter takes a pre-computed `Set<String>` of outstanding currencies; it never computes balances itself.
3. **The one-shot latch must not fire on a partial basis.**
   - Event scope: the sheet currently latches with `settlementsAsync.valueOrNull ?? const []` — after this change it must NOT latch while `eventSettlementsProvider` is still loading (a slow settlement stream would make a settled bucket look outstanding and false-fire the sheet — the exact bug in another costume). Latch only when settlements are resolved (`hasValue` or `hasError`).
   - Group scope: `groupPreSettleReviewProvider` returns `resolved: false` until `groupBalancesProvider` has a value or an error, same as its existing events/members gating.
   - **Group scope, per-event settlements (Gate R1 P1):** `groupBalancesProvider.hasValue` does NOT imply settlement-completeness — `group_balance_provider.dart:171-174` `continue`s past any event whose settlement stream is still loading yet still returns `AsyncValue.data`, so its `balances` map can be missing a whole currency bucket. Filtering against that incomplete map would drop a GENUINE flag (outstanding USD event whose settlements resolve late) and the one-shot would latch with it suppressed forever. Therefore `groupPreSettleReviewProvider` must ALSO watch each event's `eventSettlementsProvider` and return `resolved: false` while any is `isLoading && !hasValue`, mirroring its existing per-event expense gate. Settlement stream `hasError && !hasValue` → treat that event's settlements as resolved (fail-open, decision 4) — do not block resolution. Zero-listener argument still holds: `groupBalancesProvider` already watches the same `eventSettlementsProvider` family instances.
4. **Fail-open on errors (money-trust: prefer a spurious warning over a hidden one).**
   - Event scope, settlements stream `hasError`: compute balances with empty settlements — the same basis the screen displays — and filter against that.
   - Group scope, `groupBalancesProvider` `hasError`: skip suppression entirely; flags pass through unfiltered. (Note: this branch is near-unreachable in production — `groupBalancesProvider` only errors when `groupEventsProvider` errors, which the review provider's own events gate already catches. Keep it as cheap defensive code; the test for it exercises the filter logic via a synthetic override, nothing more.)
   - Group scope, a single event's settlement stream `hasError && !hasValue`: keep going (decision 3's gate only blocks on *loading*). **Accepted consequence (Gate R2 P2, resolved):** `groupBalancesProvider` DROPS a settlement-errored event entirely (`group_balance_provider.dart:177-180` `continue`) — it does not zero its settlements — so a currency held only by that event is absent from `balances` and its flags get suppressed. This is deliberate WYSIWYG: the group settle-up screen shows NO transfer for that currency (same dropped basis), so a review flag would point at a bucket the user cannot see or settle; the #244 `failedEventIds` "balance may be incomplete" banner is the safety net that already covers this state. Do NOT try to reconstruct per-event fail-open from the pre-aggregated provider.
5. **All five `ReviewReason`s are filtered identically** — a departed-payer or personal flag in a settled bucket is just as moot as a large-amount flag.

## Callsite classification (verification principle 1)

| Surface | Class | Note |
|---|---|---|
| `detectReviewWorthyExpenses` + new filter | INBOUND | display-only; no write path |
| `settle_up_screen.dart` `_maybeShowReviewSheet` | INBOUND | sheet trigger only; `bucketed`/`buckets`/`userRawNames` (OUTBOUND, feed the settlement write) are NOT touched by this change — only the trigger's position/inputs move |
| `group_presettle_review_provider.dart` | INBOUND | "projection, never a money source" contract preserved |
| `groupBalancesProvider` | untouched | read-only consumption |

No write path, no schema, no rules change. `BalanceCalculator` itself is untouched.

---

### Task 1: Pure filter function (RED → GREEN)

**Files:**
- Modify: `lib/features/ledger/services/pre_settlement_review.dart`
- Test: `test/unit/pre_settlement_review_test.dart`

**Step 1 — failing tests.** Add a new `group('filterFlagsToOutstandingCurrencies', ...)` to `test/unit/pre_settlement_review_test.dart` (reuse the file's existing expense-fixture helpers):

- flags whose expense currency ∈ outstanding set pass through, order preserved;
- flags whose currency ∉ outstanding set are dropped (mixed OMR-settled/USD-outstanding list → only USD flags remain — this is the #898 QA scenario);
- empty outstanding set → empty result;
- all five `ReviewReason`s in a settled currency are all dropped (no reason-specific exemption).

**Step 2 — run:** `flutter test test/unit/pre_settlement_review_test.dart` → new group FAILS (function undefined).

**Step 3 — implement** in `pre_settlement_review.dart`:

```dart
/// #898: drop flags whose expense currency has nothing outstanding. Suppression
/// is bucket-level on purpose — an individual expense's "contribution" is not
/// well-defined after netting, so a currency whose nets are all zero is the
/// signal that its history no longer matters to this settle-up. INBOUND-only:
/// callers pass outstanding currencies computed from the same balance basis
/// their screen displays; this file still does no money calculation.
List<ReviewFlag> filterFlagsToOutstandingCurrencies(
  List<ReviewFlag> flags,
  Set<String> outstandingCurrencies,
) {
  return flags
      .where((f) => outstandingCurrencies.contains(f.expense.currency))
      .toList();
}
```

**Step 4 — run:** same command → PASS.

**Step 5 — commit:** `feat(ledger): pure settled-bucket filter for pre-settlement review flags (Refs #898)`

### Task 2: Event-scope suppression (RED → GREEN)

**Files:**
- Modify: `lib/features/ledger/screens/settle_up_screen.dart` (the `expensesAsync.when(data:)` callback, currently ~L227-310, and `_maybeShowReviewSheet` ~L87-112)
- Test: create `test/features/ledger/settle_up_review_suppression_test.dart`

**Step 1 — failing tests.** New widget-test file; copy the provider-override boot pattern from `test/features/groups/group_settle_up_review_sheet_test.dart` (it overrides `groupDetailProvider`, `groupMembersProvider`, etc.) adapted to the event providers used by `SettleUpScreen` (`eventDetailProvider`, `groupDetailProvider`, `eventExpensesProvider`, `eventSettlementsProvider`, `groupMembersProvider`, `currentUserIdProvider`; remember `sharedPreferencesProvider` must be overridden in every app-booting test). Cases:

1. **Settled false-positive (the #898 repro):** one exact-split OMR expense (review-worthy) + an offsetting OMR settlement so every OMR net is zero → pump → **no** review sheet.
2. **Still-outstanding flags fire:** same expense, no settlement → sheet appears.
3. **Mixed buckets:** settled OMR exact-split + outstanding USD large-amount pair → sheet appears and shows only the USD rows (assert the OMR row's text is absent, USD row present).
4. **No latch on loading settlements:** `eventSettlementsProvider` overridden with a never-emitting stream (`StreamController` never added to) → pump → no sheet, and no latch: complete the stream with the offsetting settlement afterwards → still no sheet (settled). *(This pins locked decision 3.)*
5. **Settlements error → fail-open:** `eventSettlementsProvider` overridden with `Stream.error(...)` → flags computed against empty settlements → sheet appears.

End every case that renders an empty/error state with the drain pattern the repo uses (see gotcha: `EmptyStateView` ticker), and do NOT `pumpAndSettle` after `pumpRihlaApp` if that helper is used — follow the reference test's pump idiom exactly.

**Step 2 — run:** `flutter test test/features/ledger/settle_up_review_suppression_test.dart` → cases 1, 3, 4 FAIL (sheet fires today regardless of nets).

**Step 3 — implement** in `settle_up_screen.dart`:

- Move the `_maybeShowReviewSheet` call from its current pre-balance position (~L234-241) to AFTER `bucketed` is computed, inside the same `data:` callback.
- Compute `final outstandingCurrencies = { for (final e in bucketed.entries) if (e.value.any((b) => b.netBalance != Decimal.zero)) e.key };`
- Change `_maybeShowReviewSheet` to accept the set and apply `filterFlagsToOutstandingCurrencies` after `detectReviewWorthyExpenses`; empty filtered list → return without latching.
- Gate the call: only invoke `_maybeShowReviewSheet` when `settlementsAsync.hasValue || settlementsAsync.hasError` (in addition to the existing `groupMembersAsync` gating, which keeps its two branches — members-error fallback still passes the empty active-set). **Both branches — the happy path AND the members-error fallback — must pass `outstandingCurrencies`**; a fallback branch that skips the filter reintroduces #898 on the members-error path.
- Keep the existing one-shot `_reviewSheetShown` contract: the guard means an early return before latch lets a later rebuild retry once the basis resolves.

**Step 4 — run:** new file passes; then `flutter test test/features/ledger/ test/features/events/event_tabs_test.dart`. Regression guards that must stay green as-is (all use genuinely unsettled/outstanding buckets — if one goes red the suppression basis is wrong, not the test): the #204 tab-activation test at `event_tabs_test.dart:291`, and the fire-expecting #204 tests in `settle_up_screen_test.dart` (L349/L378/L408/L483/L557 — including `member-provider errors do not suppress existing review reasons` at L376ish, which stays green only because `eventBalanceUniverse` unions `event.participantIds` so the members-error branch still has counterparties; don't "simplify" that union away).

Test-fixture caution: `filterFlagsToOutstandingCurrencies` compares the RAW `expense.currency` getter against bucket keys that are currency-fenced at Firestore load. Identical for every production expense; but a directly-constructed test `Expense` with an unsupported currency code would mismatch its fenced bucket key and get wrongly dropped — build fixtures with supported codes (OMR/USD/etc.) only.

**Step 5 — commit:** `fix(settle-up): suppress event pre-settlement review for settled currency buckets (Refs #898)`

### Task 3: Group-scope suppression (RED → GREEN)

**Files:**
- Modify: `lib/features/groups/providers/group_presettle_review_provider.dart`
- Test: `test/features/groups/group_settle_up_review_sheet_test.dart`

**Step 1 — failing tests.** This file's `_settledBalances` fixture (all-zero OMR nets) currently documents "the sheet trigger is independent of net amounts" — that is exactly the #898 bug. Rework:

- Add an `_outstandingBalances` fixture (same shape, one participant `netBalance: Decimal.parse('5')`, another `-5`, currency `OMR`) and switch the existing fire-expecting tests (`fires the review sheet once when any event has flags`, `discriminating: departed payer flags at group level`, `review-all CTA is hidden at group scope`, `row tap deep-links...`) to override `groupBalancesProvider` with it.
- Add: **`no sheet when every flagged currency is already settled`** — flags exist (exact-split OMR expense) but `_settledBalances` (all-zero nets) → no sheet. Update the fixture's doc comment to say the opposite of what it says today.
- Add: **`no sheet while balances are unresolved`** — `groupBalancesProvider` overridden with `const AsyncValue.loading()` → `resolved` stays false → no sheet.
- Add: **`no latch while any event's settlements are loading`** (Gate R1 P1 pin) — two events: E1's `eventSettlementsProvider` resolved, E2's overridden with a never-emitting stream; E2 holds a genuinely outstanding flagged expense → no sheet AND no latch (complete E2's stream afterwards → sheet fires with E2's flag). This pins that an incomplete balances map can never suppress-and-latch.
- Add: **`balances error fails open`** — `AsyncValue.error(...)` → flags pass through → sheet fires.
- Add: **`mixed: settled OMR suppressed, outstanding USD fires`** — balances map with zeroed OMR bucket + non-zero USD bucket, one flagged expense in each currency → sheet fires, only the USD row visible.

**Step 2 — run:** `flutter test test/features/groups/group_settle_up_review_sheet_test.dart` → new cases FAIL.

**Step 3 — implement** in `group_presettle_review_provider.dart`:

- `final balancesAsync = ref.watch(groupBalancesProvider(groupId));`
- Resolution gate: `if (!balancesAsync.hasValue && !balancesAsync.hasError) return (flags: const [], resolved: false);` alongside the existing events/members gates.
- **Per-event settlements gate (Gate R1 P1):** inside the existing per-event loop, also `ref.watch(eventSettlementsProvider(eventRef))`; if it is `isLoading && !hasValue` → `resolved = false` (mirror the expense gate at L57-60). `hasError && !hasValue` → proceed (fail-open, decision 4). Without this, `groupBalancesProvider`'s data can be missing a whole currency bucket while a settlement stream cold-starts, and the filter would suppress a genuine flag before latching.
- After assembling `flags`: if `balancesAsync.hasValue`, compute `outstandingCurrencies` from `balancesAsync.valueOrNull!.balances` (same non-zero-net rule) and apply `filterFlagsToOutstandingCurrencies`; on `hasError`, skip the filter (fail-open).
- Rewrite the provider dartdoc, specifically the L30-34 claim that the group sheet shows "precisely the union of what each event's own settle-up sheet would" — after aggregate-based suppression this is FALSE in the reverse-offset case (event A OMR outstanding, event B OMR offsetting → group OMR aggregate zero → suppressed at group scope, still shown at event scope — correct per-scope behavior, no longer a union). Extend the zero-listener argument: `groupBalancesProvider` and `eventSettlementsProvider` family instances are already watched by the same screen / balance provider.

**Step 4 — run:** file passes; then `flutter test test/features/groups/`.

**Step 5 — commit:** `fix(settle-up): suppress group pre-settlement review for settled currency buckets (Refs #898)`

### Task 4: Full verification + PR

- `flutter analyze` → clean.
- `flutter test` → full suite green.
- `bash tool/check_theme_purity.sh` (touched `lib/` widgets) → clean.
- PR body: `Closes #898`, `Spec: docs/plans/2026-07-05-898-presettle-settled-suppression.md`, with RED evidence — paste the failing-before-fix output of Task 2 Step 2 and Task 3 Step 2.

## Acceptance criteria (from #898, restated against this design)

- [ ] Event settle-up shows no review sheet when all flagged expenses' currency buckets net to zero.
- [ ] Group settle-up shows no review sheet in the same condition.
- [ ] A genuinely unsettled large/exact/custom/personal/departed-payer expense still triggers the sheet at both scopes.
- [ ] Mixed case: settled-bucket flags are hidden while outstanding-bucket flags still show (both scopes).
- [ ] The one-shot never latches on an unresolved settlement/balance basis — including the group-scope case where `groupBalancesProvider` has data but an event's settlement stream is still loading.
- [ ] Tests cover event-scope and group-scope settled false-positives, mixed buckets, loading, and error fail-open.
