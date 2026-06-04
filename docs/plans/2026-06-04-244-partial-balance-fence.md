# #244 — groupBalancesProvider presents a partial balance as authoritative when an event read errors

**Branch:** `fix/money-correctness-cluster`
**Touches:** balance aggregation feeding the settle-up write → **Gate before code.** Client-only (Riverpod `AsyncValue` handling + UI).
**Bug-fix discipline:** failing regression test first.

> **Design note (Gate R1→R2):** the issue proposed adding `failedEventIds`/`partial` to the `GroupBalances`/`CrossGroupBalance` **records**. Verified that is a ~40-construction-site sweep (≈31 `GroupBalances` + ≈15 `CrossGroupBalance` literals across ~20 test files; Dart records cannot default their fields, so every literal is a compile break). Over-scoped + un-revertable for one money fix. This spec instead uses an **additive** provider — zero record change, zero existing-test churn — and **splits off** the home-hero polish (which already fails loud-safe) as a named follow-up.

## 1. Verified against `main` (post-#220)

`lib/features/groups/providers/group_balance_provider.dart`:
- **Live `groupBalancesProvider:147-160`** — per-event loop skips an event whose expense/settlement read **errors** (`hasError && !hasValue`, `:153-156`) with a bare `continue`, then returns `AsyncValue.data(computeGroupBalances(...))` (`:165`). A failed/permission-denied read is treated as **0** and the remaining sum is presented as **authoritative `data`** — no incomplete signal. The comment conflates **loading** with **errored**. **This is the money-wrong path** (in-group settle-up reads it).
- **Once `groupBalancesOnceProvider:610-614`** — `await getExpenses/getSettlements` with **no try/catch**; `expense_service.dart:54-62` / `settlement_service.dart:52-60` are bare `await …get()` that **throw** → the `FutureProvider` **rejects** → `AsyncValue.error`. **Correction to the issue body:** the once/home path does NOT "inherit the same partial result" — it **fails loud (total error)**, which is *safe* (shows `_ErrorCard`, never a wrong number). Verified.
- **Single-event `eventBalancesProvider:105-107`** correctly propagates `AsyncValue.error`.

So the only surface that shows a **silently-wrong** number is the live group path → in-group settle-up. That is what 1.0 must fence.

## 2. Fix — additive `groupFailedEventIdsProvider` (no record change)

Add to `group_balance_provider.dart`:
```dart
/// Event ids in [groupId] whose expense OR settlement read HARD-ERRORED (not
/// merely loading). Mirrors the error-skip in [groupBalancesProvider]:153-156
/// so the in-group settle-up surface can warn that the displayed balance is
/// incomplete instead of presenting a partial sum as authoritative (#244).
/// Loading ≠ partial: only `hasError && !hasValue` counts.
final groupFailedEventIdsProvider =
    Provider.family<Set<String>, String>((ref, groupId) {
  final events = ref.watch(groupEventsProvider(groupId)).valueOrNull ?? const [];
  final failed = <String>{};
  for (final event in events) {
    final eventRef = (groupId: groupId, eventId: event.id);
    final exp = ref.watch(eventExpensesProvider(eventRef));
    final set = ref.watch(eventSettlementsProvider(eventRef));
    if ((exp.hasError && !exp.hasValue) || (set.hasError && !set.hasValue)) {
      failed.add(event.id);
    }
  }
  return failed;
});
```
- Reuses the **same** `eventExpensesProvider`/`eventSettlementsProvider` instances the live balance provider already watches (Riverpod shares them — no extra Firestore listener, just an extra watcher).
- `groupEventsProvider` is the same soft-delete-filtered list the balance provider uses (so a soft-deleted event can never appear in `failed`).
- Purely additive: changes no record, no existing construction site, no existing test.

**UI — `group_settle_up_screen.dart` (OUTBOUND, the fix's whole point):** in the screen's `data:` branch (where `groupBalancesProvider` resolves, around `:110`), `ref.watch(groupFailedEventIdsProvider(widget.groupId))`; when non-empty, render a non-dismissible banner ("This balance may be incomplete — some event data couldn't be loaded.") **above** `SettleUpPageBody` (the field is in scope in the screen's `data:` Column — do NOT thread it into the shared `SettleUpPageBody` widget). Warn, don't hard-block — a user offline for one event still legitimately settles the rest; the bar is "never present a partial number as complete," not "forbid settling."

## 3. Verification principles
1. **Callsite classification (consumers of the live `groupBalancesProvider`):**
   - `group_settle_up_screen.dart:86` → drives a **settlement write**. **OUTBOUND** → must get the banner. (P0, the fix.)
   - `group_danger_section.dart:183/203/264` (3 reads) → delete-group affordance; advisory only (the authoritative gate is the server `deleteGroup` recompute, #190). **Out of scope** here — server guards it.
   - `group_members_section.dart:151` → settle-before-remove-member gate; advisory, server-independent guard not in this issue. **Out of scope.**
   - `profile_stats_provider.dart:63`, `group_detail_screen.dart:91/~200` → **INBOUND** display.
   - Home hero `balance_hero_card.dart:26` (`crossGroupBalanceOnceProvider`) → once path, already fails loud-safe. **Follow-up (§5).**
   The new `groupFailedEventIdsProvider` is consumed by exactly one site: `group_settle_up_screen` (named).
2. **Claims verified:** live error-skip `group_balance_provider.dart:153-156`; loading-skip `:147-150` (separate branch); `getExpenses`/`getSettlements` throw (no swallow) `expense_service.dart:54-62`, `settlement_service.dart:52-60`. Re-grepped on branch HEAD.
3. **Read-path per write-path:** write = group settle-up; the new provider is read there and only there.
4. **Fields from the type:** NO record changed → no construction-site enumeration needed. (This is the whole point of the redesign vs Gate R1's 40-literal P1.)
5. **Data contract:** `groupFailedEventIdsProvider` returns `Set<String>` of `event.id` with `hasError && !hasValue` on expense OR settlement. Empty on all-success and on loading.
6. **Arithmetic decomposition:** untouched — no money field added; balances still computed by `computeGroupBalances` from the events that succeeded. The fix only *labels* the result incomplete.
7. **Adversarial pass (orthogonal axis = loading vs errored, and soft-delete):**
   - An event still **loading** (stream emitted nothing) → `hasError` false → NOT in `failed` (no false "incomplete"). Test it.
   - A **soft-deleted** event never enters `groupEventsProvider`'s list → never in `failed`.
   - An event with a **settlement** error but expenses fine → still flagged (OR condition). Test it.

## 4. Tests (table-driven; clean / warning / loading)
`test/unit/group_balance_provider_test.dart` (reuse its `ProviderContainer` + `overrideWith(Stream.error(...))` harness):
- one event's expense stream errors → `groupFailedEventIdsProvider(gid) == {eventB.id}`; the other event absent.
- one event's **settlement** stream errors (expenses fine) → flagged (OR branch).
- all succeed → empty set (regression fence).
- one event **loading** (a `StreamController` with no emit) → empty set (loading ≠ partial, orthogonal axis).
- widget (`group_settle_up_screen_test.dart`): override BOTH `groupBalancesProvider(gid)` → `AsyncValue.data(...)` (so the screen lands on the `data:` branch, not loading/error) AND `groupFailedEventIdsProvider(gid)`; banner present when the latter is `{...}`, absent when `{}`. End with `pumpAndSettle()` per the EmptyState/animation teardown landmine.

## 5. Out of scope (named follow-ups)
- **Home-hero graceful partial (once path):** `groupBalancesOnceProvider`/`crossGroupBalanceOnceProvider` currently total-fail on a per-event read error (safe but blunt — one transient blanks the whole hero). Upgrading to a graceful per-group "incomplete" affordance is UX polish, not money-safety (no wrong number is shown today). File as a follow-up; it can adopt the same `groupFailedEventIdsProvider` pattern (or a one-shot sibling). Re-scope note added to #244.
- delete-group / remove-member advisory reads (server-authoritative): not in this issue.
- #249 (deferred coordinated), #250, #247 — separate specs.
