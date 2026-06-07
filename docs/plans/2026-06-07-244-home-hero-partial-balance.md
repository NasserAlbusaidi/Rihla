# #244 — home balance hero: graceful partial affordance (remaining box)

**Branch:** `fix/244-home-hero-partial-balance`
**Issue state:** #244 money-safety part already shipped (#253: `groupFailedEventIdsProvider` + settle-up banner on the OUTBOUND surface). This is the **remaining re-scoped box** from the issue comment: the **home balance hero** graceful-partial UX.
**Touches:** the money **once-path** (`groupBalancesOnceProvider` / `crossGroupBalanceOnceProvider`) → **Gate before code.** Client-only (Riverpod + UI + l10n).
**Bug-fix discipline:** failing regression test first (RED) per provider.

---

## 1. Problem, verified against `origin/main` (6af0594)

`lib/features/groups/providers/group_balance_provider.dart`:

- **`groupBalancesOnceProvider:621-652`** (FutureProvider.autoDispose.family<GroupBalances, String>) — the home one-shot. For each event it does `await expenseService.getExpenses(...)` / `getSettlements(...)` with **NO try/catch** (`:639-643`). `getExpenses`/`getSettlements` are bare `await …get()` (`expense_service.dart:55`, `settlement_service.dart:51`) that **throw** on permission-denied / uncached-while-offline. One event throw → the whole `FutureProvider` **rejects** → `AsyncValue.error`.
- **`crossGroupBalanceOnceProvider:660-699`** — awaits `groupBalancesOnceProvider(g).future` per group (`:678`); one group rejecting → the whole provider rejects → `AsyncValue.error`.
- **`balance_hero_card.dart:33-37`** — `error: (e,_) => _ErrorCard()`. So **any** single event read error blanks the **entire** home hero across all groups.

This is **loud-safe** (an error card, never a wrong number) but **blunt**: one transient read failure on one event in one group blanks the whole headline. The remaining work (issue comment): show "you're owed X (incomplete)" with a warning affordance instead of a full error card when only **some** events fail.

**Why this is NOT a money-safety regression:** the OUTBOUND surface (group settle-up, where the user acts on a number) already carries the #253 banner via the live `groupFailedEventIdsProvider`. The home hero is **INBOUND** — tapping it only scrolls to the journeys list (`balance_hero_card.dart:24-27`, #284); it drives no write. A clearly-labeled partial number there is acceptable; the actual settle-up re-warns.

## 2. Why the live `groupFailedEventIdsProvider` CANNOT be reused for home

`groupFailedEventIdsProvider` (`:189-204`) re-watches the **live** `eventExpensesProvider`/`eventSettlementsProvider` streams. The home tree deliberately holds **zero** per-event listeners (#104 — that is the entire point of the once-path). Watching `groupFailedEventIdsProvider` from the hero would re-open O(G×E) live listeners → reintroduce the #104 leak. So the once-path needs its **own** failed-event channel, computed from the **same one-shot `.get()` reads** that produce the balance (so the "incomplete" flag can never disagree with the number — the property #253 valued).

## 3. Why NOT add a field to a record

Adding `partial`/`failedEventIds` to **`GroupBalances`** = 28 literal construction sites (`grep -c memberRawNames:`; `profile_stats_provider.dart:63` reads the **live** `groupBalancesProvider.totalSpent` — a `GroupBalances` reader, not `CrossGroupBalance`). Adding to **`CrossGroupBalance`** = 31 literal sites across lib (live `crossGroupBalanceProvider` ×4) + non-home tests (`sign_out_tile`, `delete_account_tile`, `profile_screen`). Dart records can't default fields → every literal is a compile break. This is exactly the wide churn the #244/#253 plan rejected. **Use a wrapper return type on the once-providers only** — the live `CrossGroupBalance`/`GroupBalances` records and all 31/28 literals stay untouched.

## 4. Fix

### 4a. `groupBalancesOnceProvider` → carry the failed set (per-event tolerant)

New typedef in `group_balance_provider.dart`:
```dart
/// Once-path balance plus the ids of events whose one-shot money read FAILED
/// (and were therefore dropped from [balances]). [failedEventIds] non-empty ⇒
/// [balances] is a partial sum (#244). Mirrors the live error-skip in
/// [groupBalancesProvider]:153-156 / [groupFailedEventIdsProvider], but computed
/// from the SAME one-shot reads so the flag can never disagree with the number.
typedef GroupBalancesOnce = ({GroupBalances balances, Set<String> failedEventIds});
```

`groupBalancesOnceProvider` body changes:
```dart
final allExpenses = <Expense>[];
final allEventSettlements = <Settlement>[];
final failedEventIds = <String>{};
for (final event in events) {
  try {
    final exp = await expenseService.getExpenses(groupId, event.id);
    final set = await settlementService.getSettlements(groupId, event.id);
    allExpenses.addAll(exp);
    allEventSettlements.addAll(set);
  } catch (_) {
    failedEventIds.add(event.id);   // drop the event, flag partial
  }
}
return (
  balances: computeGroupBalances(events: events, members: members,
      allExpenses: allExpenses, allEventSettlements: allEventSettlements,
      groupSettlements: groupSettlements),
  failedEventIds: failedEventIds,
);
```
- **Drop semantics mirror the live path exactly**: an event whose expense OR settlement read fails contributes 0 and is flagged (live: `hasError && !hasValue` → `continue`). Computed via `computeGroupBalances` from the survivors — same pure reducer, no divergence.
- **Coarse list reads stay loud-safe**: `events`/`members`/`groupSettlements` futures + `ledgerRevisionProvider` are still awaited up front (`:625-633`), OUTSIDE the try. If a whole group's list read fails, the provider still **rejects** (hard-fail that group) — a whole unknown group is too coarse to silently drop, and the issue's scope is a "failed *event* read." Cross-group then stays loud (error card) for that case (§4b).
- **`try` wraps BOTH reads together**: if `getExpenses` succeeds but `getSettlements` throws, neither is added (the OR semantics — an event with partial money is treated as fully failed, matching the live OR at `:153-156`). No half-counted event.

### 4b. `crossGroupBalanceOnceProvider` → aggregate the partial flag (atomic with the number)

New typedef:
```dart
/// Home cross-group summary plus whether ANY group's one-shot dropped an event
/// (#244). [partial] ⇒ [balance] omits one or more events' money; render the
/// "may be incomplete" affordance. Atomic: number + flag from one computation.
typedef CrossGroupBalanceOnce = ({CrossGroupBalance balance, bool partial});
```
`crossGroupBalanceOnceProvider` returns `CrossGroupBalanceOnce`. Per group it reads the `GroupBalancesOnce` wrapper, sums `result.balances.balances` exactly as today, and sets `partial |= result.failedEventIds.isNotEmpty`. `CrossGroupBalance` is built unchanged (incl. vestigial `isLoading: false`) and nested in the wrapper. **The `uid == null` early-return (`group_balance_provider.dart:662-671`) must ALSO be wrapped** as `(balance: (net: 0, owedToUser: 0, userOwes: 0, groupCount: 0, isLoading: false), partial: false)` — every return site conforms to the new type.
- A whole-group reject (§4a coarse failure) still propagates → provider rejects → `_ErrorCard` (loud-safe preserved for the coarse case). Only the per-event-drop case yields `partial: true` + a number.

### 4c. Consumers of `groupBalancesOnceProvider` (now returns the wrapper)

Exactly **3 lib reads** (`grep`):
- `active_journeys_provider.dart:154` → `.valueOrNull?.balances.perEventBreakdown` (was `.valueOrNull?.perEventBreakdown`).
- `home_screen.dart:618` → `final balances = balancesAsync.valueOrNull?.balances;` (was `.valueOrNull`).
- `crossGroupBalanceOnceProvider:678` → uses `result.balances.balances` (updated in 4b).

### 4d. UI — `balance_hero_card.dart`

`data:` now yields `CrossGroupBalanceOnce`:
```dart
data: (result) => _LoadedCard(
  balance: result.balance, partial: result.partial, onTap: onTap),
```
`_LoadedCard` gains `final bool partial;`. When `partial`, append a subtle warning row beneath the legend (icon `Iconsax.warning_2`, `colors.warning`, l10n `homeBalanceIncompleteNotice`) — the same visual language as the settle-up banner but compact (single row, no border box) so the hero stays glanceable. The number still renders (the "you're owed X (incomplete)" goal). `_ErrorCard` is unchanged — it still shows on a coarse/total failure. **Add `import 'package:iconsax/iconsax.dart';`** to `balance_hero_card.dart` (currently absent; precedent `core/theme/error_widgets.dart:157`) — do NOT use `Icons.warning`.

### 4e. l10n

Add `homeBalanceIncompleteNotice` to `app_en.arb` + `app_ar.arb` (e.g. EN "Some data couldn't load — balance may be incomplete", AR mirrored), then `flutter gen-l10n` (or run the build) to regenerate `app_localizations*.dart`. **ARB parity is enforced by the CI step `dart run tool/check_arb_completeness.dart` (`.github/workflows/readiness_check.yml:61`), NOT by `check_arb_completeness_test.dart`** (that unit test only exercises the comparator on fixtures and would pass with a missing AR key) — so both ARBs MUST get the key or CI (not local `flutter test`) goes red. Run `dart run tool/check_arb_completeness.dart` locally before pushing.

## 5. Verification principles (run now, reported)

1. **Callsite classification — consumers of the changed once-providers:**
   - `balance_hero_card.dart` (`crossGroupBalanceOnceProvider`) → **INBOUND** display (tap = scroll only). Gets the affordance. *The fix.*
   - `active_journeys_provider.dart:154` (`groupBalancesOnceProvider`) → INBOUND (per-event journey totals); reads `.perEventBreakdown` via the `.balances` accessor. **Residual silent-0 (accepted, named):** `activeJourneysProvider` iterates the LIVE `activeEvents` list and does `userEventBalances[event.id] ?? Decimal.zero` (`:171`). A *dropped* event still in the active window renders a journey ticket with `userBalance: 0.000` and NO per-ticket failure signal. This is **a net improvement over today** (today the whole group's once-read rejects → every ticket in the group reads 0/absent) and the hero's global `partial` flag warns the user something didn't load. A per-ticket badge is out of scope (§7) — the hero flag is the #244 box. No regression; explicitly accepted.
   - `home_screen.dart:618` (`groupBalancesOnceProvider`) → INBOUND (per-group card net); `.balances` accessor. Out of scope to badge per-card (issue = the hero); a per-card partial badge is a possible follow-up, not this box.
   - The **live** `groupBalancesProvider`/`crossGroupBalanceProvider` and `GroupBalances`/`CrossGroupBalance` records are **untouched** — no OUTBOUND surface changes.
2. **Claims verified against branch HEAD:** no-try/catch once loop (`:639-643`); `getExpenses`/`getSettlements` throw, no swallow (`expense_service.dart:55`, `settlement_service.dart:51`); hero `error→_ErrorCard` (`:35`); live failed-set re-watches live streams (`:196-197`) → can't reuse for home (#104). Re-grep at code time.
3. **Read-path per write-path:** this fix adds **no write path**. The once-path is read-only (home display). The OUTBOUND settle-up write already fenced (#253). Explicit: nothing here feeds a settlement write.
4. **Fields from the type:** `GroupBalances` (28 literals) and `CrossGroupBalance` (31 literals) are NOT modified — that is the design. Only two NEW wrapper typedefs are added; their construction sites are the two once-providers (lib) + the once-path tests. Fully enumerated in §6 (5 existing test files migrate, not 3 — Gate R1 correction).
5. **Data contracts (exact):**
   - `GroupBalancesOnce = ({GroupBalances balances, Set<String> failedEventIds})`. `failedEventIds` ⊆ `events.map((e)=>e.id)`; empty on all-success and on a coarse reject (because then the provider rejects, never returns this record).
   - `CrossGroupBalanceOnce = ({CrossGroupBalance balance, bool partial})`. `partial == OR over groups of (failedEventIds.isNotEmpty)`.
6. **Arithmetic decomposition:** untouched. `balances` still produced by `computeGroupBalances` from the surviving events; the cross-group sum still folds `UserBalance.netBalance` (settlement-inclusive) per group — identical reduction to today. The fix only **labels** the result and **drops** failed events (it already dropped them by rejecting; now it drops just the event, not the whole hero). No money field added or recomputed.
7. **Adversarial pass (orthogonal axes = loading vs errored; event-drop vs group-reject; multi-group):**
   - **Loading ≠ partial:** a still-resolving once-read is `AsyncValue.loading` (FutureProvider), not in `failedEventIds`. The hero shows the skeleton, not a false "incomplete." Covered by the FutureProvider lifecycle (no event added to failed unless its `.get()` throws).
   - **One event fails in a 2-event group:** balance = the other event's; `failedEventIds == {failed}`; cross-group `partial == true`; net = surviving sum (the failed event's money is genuinely excluded — the number is partial *by construction*, hence the badge). Test it.
   - **Group A all-ok, Group B one-event-fails:** net = A + B-partial; `partial == true`. Test (multi-group orthogonal).
   - **Whole-group list read fails (coarse):** provider rejects → `_ErrorCard` (loud-safe preserved, NOT a silent 0-group). Test that `groupBalancesOnceProvider` still throws on a members/events list error.
   - **Settlement-only failure (expenses ok):** `try` wraps both → event dropped + flagged (OR). Test it.
   - **ledgerRevision bump / live event-list refresh:** unchanged — list deps still watched synchronously before the try; the home_balance_once_104 liveness tests (revision bump, live event add) must stay green with `.balances` accessor.

## 6. Tests (table-driven; clean / partial / coarse-fail / loading)

**NEW `test/unit/home_balance_partial_244_test.dart`** (own `ProviderContainer`, override `expenseServiceProvider`/`settlementServiceProvider` with a fake whose `getExpenses`/`getSettlements` THROW for a chosen eventId; override list providers with `Stream.value`):
- one event's expense read throws → `groupBalancesOnceProvider(gid)` resolves; `.failedEventIds == {bad}`; `.balances` net = the good event only.
- one event's **settlement** read throws (expenses ok) → flagged (OR branch).
- all reads succeed → `.failedEventIds` empty (regression fence).
- `crossGroupBalanceOnceProvider`: group with a failed event → `.partial == true`, `.balance.net` = surviving sum; all-ok → `.partial == false`.
- multi-group: A ok + B one-fail → `.partial == true`, net = A + B-survivors.
- **coarse:** `groupMembersProvider(gid)` or `groupEventsProvider(gid)` errors → `groupBalancesOnceProvider(gid)` **throws** (loud-safe; `expectLater(...future, throwsA)`).

**UPDATE existing test files for the wrapper return types.** `grep -rn 'crossGroupBalanceOnceProvider\|groupBalancesOnceProvider' test/` → **5** files touch the once-providers' values; ALL need migration (Gate R1 caught that the first draft listed only 3):

`crossGroupBalanceOnceProvider` → `CrossGroupBalanceOnce` consumers:
- `test/unit/home_balance_once_104_test.dart` — `.future` reads at `:184,252,290,300` yield `CrossGroupBalanceOnce`; the assertions `result.net`/`result.owedToUser`/`result.userOwes`/`result.groupCount` at **`:196-199, 254-256, 291, 301`** become `result.balance.net` etc. (Gate R1 found these sites the first draft missed; Gate R2 added `:199 result.groupCount` → `result.balance.groupCount`.) Also `groupBalancesOnceProvider(gid).requireValue` at `:338` (+ `netA(GroupBalances)` helper `:341-342`) → `.balances`. Liveness/no-leak/`getCount==1` assertions unchanged.
- `test/features/home/balance_hero_card_test.dart:27-32` — bridge override: `data: (d) => (balance: d, partial: false)` and `Completer<CrossGroupBalance>()` → `Completer<CrossGroupBalanceOnce>()`.
- `test/features/home/balance_hero_card_tap_test.dart:35-40` — same bridge change as above.
- `test/features/home/home_hero_scroll_to_journeys_test.dart:62-69` — direct `Future.value((net:…, isLoading:false))` → `Future.value((balance: (net:…, isLoading:false), partial: false))`.
- `test/features/home/home_screen_dashboard_test.dart:121-131` — bridge: `data: (d) => (balance: d, partial: false)` + `Completer<CrossGroupBalanceOnce>()`.

`groupBalancesOnceProvider` → `GroupBalancesOnce` consumers:
- `test/features/home/home_screen_dashboard_test.dart:127-131` — bridge: `data: (d) => (balances: d, failedEventIds: const <String>{})` + `Completer<GroupBalancesOnce>()`.
- `test/unit/active_journeys_provider_test.dart` — `:126-128` override returns `_makeGroupBalances(...)` → wrap `(balances: <that>, failedEventIds: const <String>{})`. The `:93-95` site is a `fail(...)` sentinel (returns `Never`) — **no value change** (it throws before returning).
- (`home_balance_once_104_test.dart:338` covered above.)

`home_screen.dart:116` `ref.invalidate(crossGroupBalanceOnceProvider)` is type-agnostic — no change.

**NEW widget `test/features/home/balance_hero_card_partial_test.dart`** (override `crossGroupBalanceOnceProvider` → `AsyncValue.data((balance: <CrossGroupBalance>, partial: true))`):
- `partial: true` → the net amount STILL renders AND `homeBalanceIncompleteNotice` is present.
- `partial: false` → notice absent, number renders. End with `pumpAndSettle()` (EmptyState/animation teardown landmine; hero has no EmptyState but settle for safety).

## 7. Out of scope (named)
- Per-group **card** partial badge (`home_screen.dart:618`) — issue box is the hero; file as follow-up if wanted.
- Coarse whole-group-failure graceful affordance — kept loud-safe by design (too coarse to drop silently).
- Any live-path / OUTBOUND change — already fenced (#253).
