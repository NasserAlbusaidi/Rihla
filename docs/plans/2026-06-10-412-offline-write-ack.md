# #412 — Offline saves must not gate UI on Firestore server ack

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** On all five money write sites, give the user bounded-time feedback (success UI + honest "will sync" state) when the Firestore write is queued offline, instead of an indefinite spinner / silence — while preserving today's error surfacing for online failures.

**Architecture:** A single helper `awaitServerAck` races the write's server-ack future against a 5s timeout (skipping the wait entirely when connectivity already reads non-online). On ack → exactly today's flow. On timeout → the write is locally queued by the Firestore SDK (its persistence layer replays it on reconnect — this plan adds NO custom queue); proceed optimistically: bump `ledgerRevisionProvider` where required, set connectivity to `syncing` unconditionally via a new `noteQueuedWrite()`, and show a queued-flavored success UI. Errors thrown *within* the timeout (online rules rejection) propagate to the existing catch paths unchanged; errors *after* the timeout (rejection on replay) are observed best-effort (debugPrint + Sentry).

**Tech Stack:** Flutter 3.41.5, Riverpod 2.x, cloud_firestore, mocktail, FakeFirebaseFirestore.

**Issue:** #412. Root cause verified: `DocumentReference.set()/update()` futures resolve only on SERVER ack; offline they stay pending until reconnect, so the five handlers below never reach their post-await `noteLocalWrite()` (which is additionally a no-op unless `state == offline` — dead in the up-to-60s stale-probe window).

---

## Verified current state (all re-confirmed against code 2026-06-10)

The five write sites and their post-await sequences:

| # | Site | Awaited write | Post-await steps |
|---|---|---|---|
| 1 | `add_expense_screen.dart:55` `_handleSubmit` | `expenseService.addExpense(...)` → `Future<Expense>` (server ack at `expense_service.dart:158` `.set(data)`) | `:75` revision bump → `:76` `noteLocalWrite()` → `:78` success dialog (consumes returned `Expense`) → `finally` clears vestigial `expenseLoadingProvider`. Spinner = `_isSubmitting` in `ExpenseEditorBody._submit` (arms before `widget.onSubmit`, disarms in `finally`); its catch shows "Failed to add expense". Notifiers pre-captured at `:51-52` (#104 pattern). |
| 2 | `edit_expense_screen.dart:109` `_save` | `updateExpense(...)` → `Future<void>` | `:141` invalidate `eventExpensesProvider` → `:142` bump → `:143` `noteLocalWrite()` → `:144` haptic → `:147` `ctx.pop()`. NO pre-capture (uses widget `ref` post-await — `EditExpenseScreen` is a `ConsumerWidget`, `edit_expense_screen.dart:23`). Errors → `ExpenseEditorBody._submit` catch. |
| 3 | `edit_expense_screen.dart:166` `_delete` | `deleteExpense(...)` → `Future<void>` | `:174` invalidate → `:175` bump → `:176` `noteLocalWrite()` → `:177` haptic → `:179-185` snackbar + pop. Errors → `ExpenseEditorBody._confirmDelete` catch. |
| 4 | `settle_up_screen.dart:351` `_recordSettlement` | `addSettlement(...)` → `Future<Settlement>` (**return value unused**) | `:366` bump → `:367` `noteLocalWrite()` → `:369-378` `settleUpRecorded` snackbar. `catch` at `:380` → `classifySettlementWriteError` snackbar. NO spinner (payment sheet popped before the write). Haptic fires PRE-write at `:343` (out of scope, see below). |
| 5 | `group_settle_up_screen.dart:405` `_recordSettlement` | `addGroupSettlement(...)` → `Future<Settlement>` (**return value unused**) | `:419` `noteLocalWrite()` — **deliberately NO revision bump** (group settlements are live-watched: `groupSettlementsProvider` at `group_balance_provider.dart:711-712`) → `:425-435` fire-and-forget `logGroupEvent` (today: never issued while the await hangs; if the app dies mid-hang the activity entry is lost permanently) → `:437-447` `settleUpRecorded` snackbar. `catch` at `:449`. NO spinner. |

Connectivity (`lib/core/providers/connectivity_provider.dart`): states `online|offline|syncing`, starts `online`, 60s server-probe; `noteLocalWrite()` (`:133-137`) flips to `syncing` **only when already `offline`**; `checkConnectivity` (`:110-119`) is the sole resolver of `syncing`. Banner (`lib/shared/widgets/offline_banner.dart`, the sole `connectivityProvider` watcher) renders "Saved — will sync" (`bannerSavedWillSync`) on `syncing`; mounted on home / ledger / event-command-center only.

Read-path for the revision bump: `groupBalancesOnceProvider` watches `ledgerRevisionProvider` at `group_balance_provider.dart:713`; `crossGroupBalanceOnceProvider` derives from it. Offline, the one-shot reads are served from the SDK cache **including pending queued writes**, so bumping on the queued path shows the updated home balance.

`addExpense` lib callers: exactly one (`add_expense_screen.dart:57`). `expense_service_test.dart` has ~20 `await service.addExpense(...)` call sites against `FakeFirebaseFirestore` — the design below leaves that signature untouched.

l10n keys verified: `expenseSuccessSyncedToCloud` (`app_en.arb:1561` "SYNCED TO CLOUD" / `app_ar.arb:718`), `settleUpRecorded` (`app_en.arb:836` "Settlement recorded." / `app_ar.arb:335`), `bannerSavedWillSync` (en "Saved — will sync").

## Why CI never caught this

The #357/#403 tests seed the connectivity provider offline but write through `FakeFirebaseFirestore`, whose `set()` acks instantly — no test models a pending-forever write future. Every new RED test below injects a **never-completing future** through a mocked service (a `Completer` that is never completed), which `FakeFirebaseFirestore` cannot express.

## Design decisions (and rejected alternatives)

1. **Race, don't fire-and-forget.** Making services resolve on local acceptance (never awaiting `set()`) would kill online error surfacing — a rules rejection would never reach the existing catch paths. The race keeps the online path byte-identical (ack < 5s → today's flow, including error UX) and only diverges when the server is silent.
2. **`stageExpense` + delegating `addExpense`** (service-level, site 1 only). The success dialog consumes the returned `Expense`, which today is built AFTER the await (`expense_service.dart:169`) from the locally-constructed `data` map — i.e. it never needed the server. New method `stageExpense(...)` builds the SAME write-map, issues `.set()` WITHOUT awaiting, and returns `({Expense expense, Future<void> ack})`; `addExpense` becomes `final s = stageExpense(...); await s.ack; return s.expense;`. ONE write-map (no drift), zero churn in the ~20 `expense_service_test.dart` call sites, and the screen gets the dialog's `Expense` regardless of ack. Sites 2-5 need no service change: their return values are `void`/unused, so screens race the existing future.
3. **`noteQueuedWrite()` sets `syncing` unconditionally.** A timed-out write is stronger evidence of being offline than the up-to-60s-stale probe state, so it must not be gated on `state == offline` (that gate is exactly the second half of the #412 bug). The periodic/resume probe already resolves `syncing` → `online|offline`; no new timer. `noteLocalWrite()` keeps its existing semantics for the acked path (stale-offline correction).
4. **`skipWait` when connectivity is not `online`.** If the provider already says `offline` (or `syncing` — a prior queued write pending), don't burn the 5s; go straight to the queued path. If the state is stale-`syncing` while actually online, the write acks moments later and the next probe self-heals — honest enough.
5. **Late-error observation, no UI.** After timeout, attach an observer to the pending future: `debugPrint` + `Sentry.captureException`. Best-effort by nature (lost if the app dies first — the replayed write itself survives in the SDK queue; only the *report* is lost). Root-messenger snackbars for hours-later failures are deliberately out of scope (out-of-context UI, and the queued write is rules-valid in every non-adversarial flow since the client built it from the same validated form).
6. **Timeout = 5s** (`kWriteAckTimeout`). Single-doc acks on a working mobile link land well under 5s; an offline save feels responsive at ≤5s (or instant via `skipWait`). A write acking at t>5s after the queued path was taken is harmless: the UI said "will sync", and it did.

## Data contracts (exact)

```dart
// lib/core/utils/write_ack.dart
enum WriteAck { acked, queued }
const kWriteAckTimeout = Duration(seconds: 5);
Future<WriteAck> awaitServerAck(
  Future<void> ack, {                 // Future<T> upcasts fine
  Duration timeout = kWriteAckTimeout,
  bool skipWait = false,
  void Function(Object error, StackTrace stackTrace)? onLateError, // test seam; default observer = debugPrint + Sentry
});

// lib/features/ledger/services/expense_service.dart
({Expense expense, Future<void> ack}) stageExpense({ /* same named params as addExpense */ });

// lib/core/providers/connectivity_provider.dart
void noteQueuedWrite();               // state = ConnectivityStatus.syncing, unconditional

// lib/features/ledger/widgets/expense_success_dialog.dart
ExpenseSuccessDialog({ ..., bool synced = true });  // badge: synced ? expenseSuccessSyncedToCloud : expenseSuccessWillSync
```

New ARB keys (values only, both languages):

| Key | en | ar |
|---|---|---|
| `expenseSuccessWillSync` | `SAVED — WILL SYNC` | `تم الحفظ — ستتم المزامنة` |
| `settleUpRecordedWillSync` | `Settlement recorded — will sync when online.` | `تم تسجيل التسوية — ستتم المزامنة عند الاتصال.` |

## Out of scope (explicit, so the Gate doesn't have to guess)

- `HapticService.success()` firing pre-write at `settle_up_screen.dart:343` (pre-existing quirk; not part of the #412 repro).
- The vestigial `expenseLoadingProvider` (written, never watched) — left untouched.
- Mounting `OfflineBanner` on the editor/settle screens (the queued-flavored dialog/snackbar carry the message in-place; the banner shows after pop on ledger/hub/home).
- Settlement re-tap dedupe (the race shrinks the silent window from indefinite to ≤5s; sheet-level pending state is a separate design).
- `createGroup`'s batch commit (already has a 15s `.timeout` + full catch, `create_group_screen.dart:97`).
- Per-site late-error UI (decision 5).

---

## Task 1: `awaitServerAck` helper

**Files:**
- Create: `lib/core/utils/write_ack.dart`
- Test: `test/core/utils/write_ack_test.dart`

**Step 1: Write the failing tests**

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/write_ack.dart';

void main() {
  test('resolves acked when the write completes within the timeout', () {
    fakeAsync((async) {
      final completer = Completer<void>();
      WriteAck? outcome;
      awaitServerAck(completer.future).then((o) => outcome = o);
      async.elapse(const Duration(seconds: 1));
      completer.complete();
      async.flushMicrotasks();
      expect(outcome, WriteAck.acked);
    });
  });

  test('resolves queued when the write never completes (offline #412)', () {
    fakeAsync((async) {
      WriteAck? outcome;
      awaitServerAck(Completer<void>().future).then((o) => outcome = o);
      async.elapse(const Duration(seconds: 6));
      expect(outcome, WriteAck.queued);
    });
  });

  test('an error within the timeout propagates to the caller', () {
    fakeAsync((async) {
      final completer = Completer<void>();
      Object? caught;
      awaitServerAck(completer.future).catchError((Object e) {
        caught = e;
        return WriteAck.queued;
      });
      completer.completeError(StateError('rules rejection'));
      async.flushMicrotasks();
      expect(caught, isA<StateError>());
    });
  });

  test('an error after the timeout reaches onLateError, not the caller', () {
    fakeAsync((async) {
      final completer = Completer<void>();
      WriteAck? outcome;
      Object? late;
      awaitServerAck(
        completer.future,
        onLateError: (e, _) => late = e,
      ).then((o) => outcome = o);
      async.elapse(const Duration(seconds: 6));
      expect(outcome, WriteAck.queued);
      completer.completeError(StateError('rejected on replay'));
      async.flushMicrotasks();
      expect(late, isA<StateError>());
    });
  });

  test('skipWait returns queued immediately without waiting', () {
    fakeAsync((async) {
      WriteAck? outcome;
      awaitServerAck(
        Completer<void>().future,
        skipWait: true,
      ).then((o) => outcome = o);
      async.flushMicrotasks();
      expect(outcome, WriteAck.queued);
    });
  });

  test('skipWait still routes a later error to onLateError', () {
    fakeAsync((async) {
      final completer = Completer<void>();
      Object? late;
      awaitServerAck(
        completer.future,
        skipWait: true,
        onLateError: (e, _) => late = e,
      );
      async.flushMicrotasks();
      completer.completeError(StateError('boom'));
      async.flushMicrotasks();
      expect(late, isA<StateError>());
    });
  });
}
```

**Step 2: Run to verify failure**

Run: `flutter test test/core/utils/write_ack_test.dart`
Expected: FAIL — `write_ack.dart` does not exist.

**Step 3: Implement**

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Outcome of racing a Firestore write against a server-ack timeout (#412).
enum WriteAck { acked, queued }

/// Bounded wait for a server ack before treating the write as queued-offline.
const kWriteAckTimeout = Duration(seconds: 5);

/// Races [ack] — a Firestore write future, which resolves only on SERVER
/// acknowledgement — against [timeout].
///
/// Returns [WriteAck.acked] when the server confirmed in time: callers keep
/// today's success flow. Returns [WriteAck.queued] on timeout: the SDK has
/// already applied the write to its local cache and queued it for replay on
/// reconnect (#412) — callers proceed optimistically. The still-pending future
/// is then observed in the background; a terminal failure (e.g. a rules
/// rejection on replay) is logged + sent to Sentry and forwarded to
/// [onLateError] — best-effort: the report (not the queued write) is lost if
/// the app dies first.
///
/// An error raised WITHIN the timeout (online rules rejection, validation)
/// propagates to the caller unchanged, so existing error UX keeps working.
///
/// [skipWait] short-circuits straight to the queued path — used when the
/// connectivity provider already reads non-online, so the user isn't made to
/// wait out a timeout the probe has already predicted.
Future<WriteAck> awaitServerAck(
  Future<void> ack, {
  Duration timeout = kWriteAckTimeout,
  bool skipWait = false,
  void Function(Object error, StackTrace stackTrace)? onLateError,
}) async {
  void observeLate() {
    unawaited(
      ack.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Queued write failed on replay: $error');
          unawaited(Sentry.captureException(error, stackTrace: stackTrace));
          onLateError?.call(error, stackTrace);
        },
      ),
    );
  }

  if (skipWait) {
    observeLate();
    return WriteAck.queued;
  }
  try {
    await ack.timeout(timeout);
    return WriteAck.acked;
  } on TimeoutException {
    observeLate();
    return WriteAck.queued;
  }
}
```

(`Sentry.captureException` is a safe no-op when Sentry isn't initialized, as in tests. `Future.timeout` keeps its own listener on `ack`, so a post-timeout error is never an unhandled-zone error even before `observeLate` attaches.)

**Step 4: Run to verify pass** — `flutter test test/core/utils/write_ack_test.dart` → PASS.

**Step 5: Commit** — `git commit -m "feat(core): awaitServerAck — bounded race on Firestore server ack (#412)"`

## Task 2: `ConnectivityNotifier.noteQueuedWrite()`

**Files:**
- Modify: `lib/core/providers/connectivity_provider.dart` (after `noteLocalWrite`, ~`:137`)
- Test: `test/core/providers/connectivity_provider_test.dart`

**Step 1: Failing tests** — in the existing `#357` group's style:

```dart
test('#412: noteQueuedWrite sets syncing even when state is online '
    '(stale-probe window)', () {
  final notifier = ConnectivityNotifier(startPeriodicChecks: false);
  addTearDown(notifier.dispose);
  notifier.setOnline();
  notifier.noteQueuedWrite();
  expect(notifier.state, ConnectivityStatus.syncing);
});

test('#412: noteQueuedWrite sets syncing from offline', () {
  final notifier = ConnectivityNotifier(startPeriodicChecks: false);
  addTearDown(notifier.dispose);
  notifier.setOffline();
  notifier.noteQueuedWrite();
  expect(notifier.state, ConnectivityStatus.syncing);
});
```

**Step 2:** Run → FAIL (`noteQueuedWrite` undefined).

**Step 3: Implement**

```dart
/// Note that a write TIMED OUT waiting for the server ack (#412).
///
/// Unlike [noteLocalWrite], this is unconditional: a timed-out write is
/// stronger evidence of being offline than the probe state, which can lag
/// reality by up to 60s. The SDK has the write queued; surface
/// "Saved — will sync" regardless. The periodic/resume probe resolves
/// `syncing` back to `online`/`offline`, so no timer is added.
void noteQueuedWrite() {
  state = ConnectivityStatus.syncing;
}
```

**Step 4:** Run the file → PASS. **Step 5: Commit.**

## Task 3: l10n keys + queued-aware success dialog

**Files:**
- Modify: `lib/l10n/app_en.arb` (after `expenseSuccessSyncedToCloud`, `:1561`), `lib/l10n/app_ar.arb` (`:718`) — add `expenseSuccessWillSync`; after `settleUpRecorded` (en `:836` / ar `:335`) — add `settleUpRecordedWillSync` (values in the table above)
- Modify: `lib/features/ledger/widgets/expense_success_dialog.dart` — add `final bool synced;` (constructor param, `this.synced = true`); badge text at `:97` becomes `synced ? context.l10n.expenseSuccessSyncedToCloud : context.l10n.expenseSuccessWillSync`
- Run `flutter gen-l10n` after the ARB edits.

No standalone test here — Task 4's widget test pins the `synced: false` rendering; existing add-flow tests pin the default. Commit.

## Task 4: add-expense screen (site 1) + service `stageExpense`

**Files:**
- Modify: `lib/features/ledger/services/expense_service.dart:101-170` — extract `stageExpense` (same params/validation/`data` map; `final ack = eventSubcollection(groupId, eventId, 'expenses').doc(id).set(data); return (expense: Expense.fromFirestore(data), ack: ack);`); `addExpense` delegates: stage → `try { await staged.ack; } on FirebaseException catch (e) { debugPrint(...); rethrow; } return staged.expense;`

**Guard placement (Gate R1 P2):** the empty-`createdBy` `ArgumentError` guard (`expense_service.dart:118-125`) moves INTO `stageExpense` (it must protect both entry points), so `stageExpense` throws **synchronously**. `addExpense` stays `async`, so the sync throw surfaces as a rejected Future — preserving `expense_service_test.dart:107`'s `expectLater(..., throwsA(isA<ArgumentError>()))`. In the screen, `stageExpense` is called inside the async `_handleSubmit`, so the sync throw is wrapped into the handler's future and lands in `ExpenseEditorBody._submit`'s existing catch.
- Modify: `lib/features/ledger/screens/add_expense_screen.dart:55-78`
- Test: `test/features/ledger/add_expense_offline_412_test.dart` (new; harness modeled on the existing add-screen widget tests — mock `ExpenseService` via `expenseServiceProvider.overrideWithValue`, timer-free `ConnectivityNotifier(startPeriodicChecks: false)..setOffline()` override, `sharedPreferencesProvider` override, `groupDetailProvider` stream override for the currency gate)

**Step 1: Failing test (the core #412 RED)**

```dart
testWidgets('#412: offline add shows the queued success dialog within '
    'bounded time — no indefinite spinner', (tester) async {
  // stageExpense returns a locally-built expense + a NEVER-completing ack
  // (real offline: set() resolves only on reconnect).
  when(() => expenseService.stageExpense(/* any(named:) for every param */))
      .thenReturn((expense: _testExpense, ack: Completer<void>().future));

  // ...pump add screen, enter amount, tap Add...
  await tester.pump();                       // start the submit
  await tester.pump(const Duration(seconds: 6)); // past kWriteAckTimeout

  expect(find.text('SAVED — WILL SYNC'), findsOneWidget); // queued dialog
  expect(container.read(ledgerRevisionProvider), 1);       // bump fired
  expect(
    container.read(connectivityProvider),
    ConnectivityStatus.syncing,                             // banner state
  );
});
```

(Seeded offline → `skipWait` makes the dialog near-immediate; the 6s pump also covers the online-stale path. Assert through whichever of dialog text / revision / state the harness can reach — all three. Gate R1 P3 guardrail: `ExpenseSuccessDialog` runs a `flutter_animate` scale ticker (`expense_success_dialog.dart:60-64`) — pump fixed durations, never `pumpAndSettle` (ConnectivityNotifier trap), and drive the dialog fully closed or pump past the animation before teardown.)

**Step 2:** Run → FAIL on current code (no `stageExpense`; after the service exists but before the screen rewire: spinner forever, dialog never appears).

**Step 3: Rewire `_handleSubmit`**

```dart
final connectivityStatus = ref.read(connectivityProvider);
final staged = ref.read(expenseServiceProvider).stageExpense(/* same args */);
final outcome = await awaitServerAck(
  staged.ack,
  skipWait: connectivityStatus != ConnectivityStatus.online,
);

ledgerRevision.state++; // #104: refresh the one-shot home balance
if (outcome == WriteAck.acked) {
  connectivity.noteLocalWrite(); // #357: stale-offline correction
} else {
  connectivity.noteQueuedWrite(); // #412: write queued, force "will sync"
}
if (!mounted) return;
await _showSuccessDialog(staged.expense, synced: outcome == WriteAck.acked);
```

Errors within the timeout still throw out of `awaitServerAck` → `ExpenseEditorBody._submit`'s existing catch ("Failed to add expense") — unchanged.

**Step 4:** New test PASS; `flutter test test/unit/expense_service_test.dart test/features/ledger/` stays green (the delegating `addExpense` keeps every existing assertion intact). **Step 5: Commit.**

## Task 5: edit-expense screen (sites 2+3)

**Files:**
- Modify: `lib/features/ledger/screens/edit_expense_screen.dart` `_save` (`:96-148`) and `_delete` (`:161-187`)
- Test: `test/features/ledger/edit_expense_offline_412_test.dart` (new)

**Step 1: Failing tests** — never-completing `updateExpense` / `deleteExpense` (mocktail `thenAnswer((_) => Completer<void>().future)`), connectivity seeded offline. Assert: the screen pops (for `_save`) / shows `editorExpenseDeleted` + pops (for `_delete`) within a bounded pump, revision bumped, state `syncing`.

**Step 2:** Run → FAIL (hangs on the await; never pops).

**Step 3: Rewire** — both methods follow the same shape; `_save` shown:

```dart
// #104/#412: capture before the await so post-write effects survive disposal.
final ledgerRevision = ref.read(ledgerRevisionProvider.notifier);
final connectivity = ref.read(connectivityProvider.notifier);
final connectivityStatus = ref.read(connectivityProvider);

final outcome = await awaitServerAck(
  ref.read(expenseServiceProvider).updateExpense(/* unchanged args */),
  skipWait: connectivityStatus != ConnectivityStatus.online,
);

ledgerRevision.state++; // #104
outcome == WriteAck.acked
    ? connectivity.noteLocalWrite()   // #357
    : connectivity.noteQueuedWrite(); // #412
HapticService.success();

final ctx = ref.context;
if (ctx.mounted) {
  // Belt-and-braces only — the ledger stream updates from local snapshots.
  ref.invalidate(
    eventExpensesProvider((groupId: groupId, eventId: eventId)),
  );
  ctx.pop();
}
```

(The invalidate moves inside the mounted guard: with a bounded race the screen can now legitimately outlive the handler, and invalidating through a disposed `ConsumerWidget` ref throws. `_delete` keeps its snackbar inside the same guard.)

**Step 4:** New tests PASS; existing edit tests green. **Step 5: Commit.**

## Task 6: event settle-up (site 4)

**Files:**
- Modify: `lib/features/ledger/screens/settle_up_screen.dart` `_recordSettlement` (`:333-399`)
- Test: extend `test/features/ledger/settle_up_screen_test.dart` (reuse the existing #357 harness at `:259-290`)

**Step 1: Failing test** — mock `SettlementService.addSettlement` → `Completer<Settlement>().future`, seed offline. Tap Mark-as-paid. Assert within bounded pumps: `settleUpRecordedWillSync` snackbar text, revision bumped, state `syncing`.

**Step 2:** Run → FAIL (snackbar never appears).

**Step 3: Rewire** — inside the existing `try`:

```dart
final ledgerRevision = ref.read(ledgerRevisionProvider.notifier);
final connectivity = ref.read(connectivityProvider.notifier);
final connectivityStatus = ref.read(connectivityProvider);

final outcome = await awaitServerAck(
  ref.read(settlementServiceProvider).addSettlement(/* unchanged args */),
  skipWait: connectivityStatus != ConnectivityStatus.online,
);

ledgerRevision.state++; // #104
outcome == WriteAck.acked
    ? connectivity.noteLocalWrite()
    : connectivity.noteQueuedWrite(); // #412
if (context.mounted) {
  // existing success snackbar, content swaps on outcome:
  // acked → settleUpRecorded; queued → settleUpRecordedWillSync
}
```

Existing catch (`classifySettlementWriteError`) unchanged — in-timeout errors still land there. The existing `#357: an offline settlement flips connectivity to syncing` test stays green (offline + instant fake ack now goes `skipWait` → queued → `noteQueuedWrite()` → `syncing`).

**Step 4:** PASS + existing file green. **Step 5: Commit.**

## Task 7: group settle-up (site 5)

**Files:**
- Modify: `lib/features/groups/screens/group_settle_up_screen.dart` `_recordSettlement` (`:373-468`)
- Test: `test/features/groups/group_settle_up_offline_412_test.dart` (new; `_RecordingGroupActivityService` pattern from `group_delete_callable_test.dart:71-105`)

**Step 1: Failing test** — never-completing `addGroupSettlement`, seeded offline. Assert within bounded pumps: `settleUpRecordedWillSync` snackbar, state `syncing`, **`logGroupEvent` was called** (today it is sequenced after the hung await and never issued — on the queued path it must run so the SDK queues the activity entry alongside the settlement), and **no revision bump** (`ledgerRevisionProvider` stays 0 — group settlements are live-watched; pins the CLAUDE.md invariant).

**Step 2:** Run → FAIL.

**Step 3: Rewire** — same race shape as Task 6 but with NO revision bump; `noteLocalWrite/noteQueuedWrite` per outcome; the `logGroupEvent` block and the snackbar (content per outcome) run after the race exactly as they run after the await today.

**Step 4:** PASS + existing group settle-up tests green. **Step 5: Commit.**

## Task 8: full verification + docs

- `flutter analyze` → clean.
- `flutter test` → full suite green.
- CLAUDE.md Common Gotchas addition: "Firestore write futures (`set`/`update`) resolve on SERVER ack only — offline they stay pending until reconnect. Never gate UI progression on awaiting them raw; race via `awaitServerAck` (`lib/core/utils/write_ack.dart`, #412) and call `noteQueuedWrite()` on the queued path (`noteLocalWrite()` is gated on `state == offline` and misses the 60s stale-probe window). `FakeFirebaseFirestore` acks instantly, so a green widget test proves nothing about this — model real offline with a never-completing `Completer` through a mocked service."
- PR: `Closes #412`, `Spec: docs/plans/2026-06-10-412-offline-write-ack.md`, RED outputs pasted for Tasks 4-7.

---

## Verification principles — run + results

1. **Callsite classification:** every changed callsite is UI-flow/INBOUND. The only OUTBOUND-adjacent change is the `stageExpense` extraction, which moves the write-map construction VERBATIM (byte-identical `data` map, same `MoneySerializer.toSubunits`, same `_encodeDistribution`) — pinned by the untouched `expense_service_test.dart` suite running through the delegating `addExpense`. No write-map key changes anywhere; no rules/schema surface.
2. **Concrete claims:** all file:line references in "Verified current state" re-confirmed by grep/Read this session (not from the scout report): the five awaits, `noteLocalWrite:133-137`, `groupBalancesOnceProvider` watch at `group_balance_provider.dart:713`, `addExpense` single lib caller, l10n keys/lines, `EditExpenseScreen extends ConsumerWidget:23`, settlement return values unused (`:351`/`:405` bare awaits).
3. **Read-path per write-path:** revision bump (queued path) → `groupBalancesOnceProvider:713` → home `BalanceHeroCard`. `noteQueuedWrite` state → `offline_banner.dart` (sole watcher) → "Saved — will sync" on ledger/hub/home. Queued expense/settlement docs → live `eventExpensesProvider`/`eventSettlementsProvider`/`groupSettlementsProvider` streams serve local snapshots immediately (SDK persistence).
4. **Fields from the type:** no model/schema change. New params enumerated exhaustively: `ExpenseSuccessDialog.synced` (bool, default true); `awaitServerAck(ack, {timeout, skipWait, onLateError})`; `stageExpense` returns `({Expense expense, Future<void> ack})`.
5. **Data contracts:** spelled out in "Data contracts (exact)" above.
6. **Arithmetic decomposition:** none touched. Site 5 deliberately keeps NO bump (live-watched), site 4 keeps its bump — both now pinned by tests (Task 7 asserts revision stays 0).
7. **Orthogonal adversarial pass (fix is on the success/offline axis → probe the ERROR/online axis):** worked example — online client sends an expense whose `splitDistribution` the rules reject (`permission-denied` arrives at t≈300ms < 5s): `awaitServerAck` rethrows before the timeout → `ExpenseEditorBody._submit` catch shows "Failed to add expense", no revision bump, no dialog, no `noteQueuedWrite` — byte-identical to today. Pinned by helper test "an error within the timeout propagates to the caller" plus the untouched existing failure-path widget tests. Second example on the identity axis — user closes the editor during the ≤5s race: post-await effects use pre-captured notifiers (sites 1-3 now all follow the #104 pattern) and the pop/invalidate sit behind `mounted` guards, so no disposed-ref throw.
