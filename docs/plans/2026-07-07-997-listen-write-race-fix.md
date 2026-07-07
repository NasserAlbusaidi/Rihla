# #997 Listen/Write Race Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** After an offline group creation, the SDK's re-established listens race the queued founding-batch replay on reconnect; the listens lose, get a terminal `PERMISSION_DENIED`, and four surfaces stick dead until app restart. Fix the root cause (recover terminally-denied listens after write replay) plus the facade's unbounded/lying failure modes.

**Architecture:** Two independent layers, two PRs sharing this spec.
- **PR1 (layer A, root cause):** a new stream utility `recoverDeniedListen` — on a `permission-denied` stream error, await `waitForPendingWrites()` (bounded), re-subscribe a bounded number of times, then surface the error. Adopted by all 9 group-scoped `watch*` methods via a `FirestoreRepository.recoverListen` helper. Client-only; no rules/Functions change.
- **PR2 (layer B, facade resilience):** four bounded/honest-display fixes in `group_balance_provider.dart` — D1 aggregate first-snapshot grace then once-path fall-through; D2 deadline on all once-path awaits; D3-narrow group-settlements-only degrade to `partial`; D5 `uid == null` → loading.

**Tech Stack:** Flutter/Dart, Riverpod 2.x `StreamProvider`/`FutureProvider` families, cloud_firestore, fake_cloud_firestore + Completer/fakeAsync test seams.

**Issue:** #997 (root cause + evidence in issue comments). Spin-offs #1017/#1018 are OUT of scope.

**Gate outcome (round 1, 2026-07-07):** rubric reviewer 0 P1 / 1 P2 / 4 P3; orthogonal adversary 0 P1 / 2 P2 / 2 P3 — both P1-clean in the same round → PASS. All three P2s + two actionable P3s folded into this revision: `profileStatsProvider` added to the once-provider consumer enumeration (+ its test file to the must-stay-green set); the composed #574 revocation-latency bound stated in A2; the settle-up warning gap during the retry window documented as an accepted bounded window; the stale-aggregate-branch timeout note added to Task 2.2; the principle-3 task pointer fixed.

---

## Root cause (one paragraph)

The SDK re-establishes listens and replays queued writes on separate gRPC streams. An offline-created group's listens reach the server ~5s before its founding batch commits; rules see no member doc; every group-scoped listen fails `PERMISSION_DENIED`, which is **terminal** for a listener (the SDK never retries). Every `StreamProvider` for that group is permanently errored. #874 made the WRITE side of this race atomic; the LISTEN side was uncovered. Proven live on-device (issue comments, logcat timeline).

## Design decisions (with rejected alternatives)

**A1 — recovery lives inside the stream, not in provider invalidation.** The issue sketch said "invalidate that gid's provider family once." Rejected: invalidation needs a `ref` and a registry of errored families per gid; a stream-level wrapper needs neither — the provider simply never sees the transient error, and every one of the ~13 consumer sites (scouted) heals at once. `StreamProvider.family` dedupes by argument, so the wrapper wraps exactly one Firestore listener per family instance.

**A2 — retry unconditionally on `permission-denied` (bounded), don't try to detect "gid has pending writes".** The SDK exposes no per-gid pending-write signal. `waitForPendingWrites()` resolves immediately when nothing is pending, so an unconditional barrier costs nothing in the genuine-revocation case; the bound (2 retries + 400ms backoff) means a real revocation surfaces ~1–2s later than today at the stream level. **Composed bound on `GroupDetailScreen` (Gate adversary):** the #574 staging retry re-invalidates the denied providers, and each invalidation spawns a fresh wrapper with a fresh budget — so a removed member's `_NoAccessState` arrives at ~`_maxStagingRetries × (wrapper budget + 800ms)` ≈ 5s on that screen. Accepted: UX latency only, no money/data effect; #574 stays untouched in this PR (candidate for simplification later, separate change).

**A3 — retry budget never resets within a subscription.** A genuinely-revoked user's re-listen emits cache data *then* re-denies; resetting the budget on data emissions would loop forever. Budget is per-wrapper-lifetime; external heals (pull-to-refresh, #574 staging retry, screen Reload) create a fresh wrapper with a fresh budget.

**A4 — wrap the 9 group-scoped listens only; leave `watchUserGroups` bare.** The groups list is a collection query (`memberIds arrayContains uid`) — an unreplayed group doc is simply not matched (empty result, self-heals on next snapshot), not a rule-evaluation error. (Scouted: `group_provider.dart:552-567`.)

**A5 — barrier failures are swallowed and the retry proceeds.** Precedent: `auth_recovery_service.dart` `waitForPendingWrites().timeout(5s)` swallow-and-proceed (3 sites). Also load-bearing for tests: `fake_cloud_firestore` 4.1.0 does not implement `waitForPendingWrites` (verified in pub cache) — any test driving a wrapped service through a fake that somehow errors must not crash on the barrier.

**A6 — keep the #574 UI staging retry and the #358 `_NoAccessState` untouched.** #574's `ref.invalidate` becomes a complementary external heal (fresh wrapper budget). Its widget test and the two #358 tests override at the *provider* level, bypassing the wrapper entirely — they pin UI handling of an already-terminal error, which is unchanged. Verified: `group_detail_no_access_test.dart` feeds `Stream.error(denied)` straight into `groupDetailProvider`.

**B1 — D3 is NARROW: only the group-settlements coarse await degrades to partial; events/members failures stay loud.** The issue checklist said "catch the three coarse awaits." Rejected for two verified reasons:
1. *Money correctness:* `eventBalanceUniverse` (`expense_provider.dart:106-151`) folds departed-member split recipients via `splitRecipientKeys.intersection(allMemberIds)`. With `members = []` that intersection is empty → departed recipients drop out of the universe → the calculator's drop-guard zeroes their owed → **wrong number**, re-opening the #249 conservation gap. A members-failure number is not "incomplete", it is incorrect.
2. *Display honesty:* a coarse-failed compute would emit `data(eventCount: 0, userNet: {})` — the row would render "N members · 0 events · settled" (the exact #997 lie, mitigated only by a 10sp "Incomplete" caption) and the journey ticket would render a **real zero amount with no affordance at all** (`ActiveJourneyEntry` has no `partial` field; `unresolvedBalance` checks only loading/error — `active_journeys_provider.dart:379-411`). Post-#1005 the AsyncError rendering ("Balance unavailable" + ticket dash) is *more* honest than partial zeros.
Missing group settlements, by contrast, is the same class as the existing #244 per-event drop (a sum missing some settlement folds, flagged "may be incomplete"), and group settlements never appear in `userPerEventNet` (they are net-only), so the ticket's per-event display is unaffected.

**B2 — D1 uses a grace window, not an immediate once-path consult.** Consulting the once-path the moment the aggregate is loading would re-add G×E one-shot reads on every cold home load, partially undoing #366's stated win. A 3s grace (`aggregateFirstSnapshotGraceProvider`) keeps the normal path clean (aggregate lands in well under 3s) and converts only the wedge case (listener established but no snapshot and no error — the DNS-blackhole enabler) into a once-path fall-through.

**B3 — D2 deadline = 8s on every once-path await** (three coarse `.future`s + per-event `get()`s). Per-event timeout lands in the existing `catch` → `failedEventIds` → partial. Coarse events/members timeout rethrows (facade error — honest per B1); coarse group-settlements timeout degrades per D3. 8s: deliberately longer than `kWriteAckTimeout` (5s) — a slow-but-succeeding read beats a spurious partial; the point is bounding *eternal*, not optimizing latency.

**B4 — D5 applies to both `homeGroupBalanceProvider` AND `crossGroupHomeBalanceProvider`.** Both have the identical `uid == null → data(zeros)` shape (`:909-917`, `:976-986`). `_AuthGate` guarantees an anon session before `SafarApp` mounts, so a null uid at render time is always "auth stream still resolving" — loading is the only honest state, and `data(zeros)` bypasses the #1005 display hardening.

**Accepted bounded windows (Gate adversary, documented not fixed):**
- *Settle-up incomplete-warning gap during the retry window:* `groupFailedEventIdsProvider` flags only `hasError` events ("Loading ≠ partial" is its documented, deliberate semantic), and `groupBalancesProvider` proceeds on still-loading events by design (`group_balance_provider.dart:186-197`). With the wrapper, a race-denied event spends ~1s in `isLoading` instead of erroring instantly, so a user settling inside that reconnect window sees a partial balance without the #244 notice. Pre-existing root (any slow listen already does this), self-healing, OUTBOUND-safe (the event recovers and re-includes). Not widening `groupFailedEventIdsProvider` to loading events — that would flag every normal cold load.
- *`activeJourneysProvider` uid-null:* stays `data([])` while D5 makes the balance facades loading — a microtask-bounded skeleton/empty mismatch guaranteed short by `_AuthGate`. Out of D5 scope by design.

**Out of scope (follow-ups, do not bundle):**
- `EventCommandCenter` hub header never checks `hasError` on expenses/settlements (renders "settled" during any error window) — file as a new issue (the #1005 class, hub edition).
- `settle_up_screen.dart` swallows settlements-stream errors asymmetrically — same follow-up issue.
- #1017 (skeleton ids leak listens), #1018 (offline-create activity write dropped) — already filed.
- Connectivity probe hardening (D4 in the issue's investigation comment) — explicitly deferred by the issue.

## Verification-principles report (run against code, 2026-07-07)

1. **Callsite classification:** every touched surface is INBOUND (display). `groupBalancesOnceProvider`/`homeGroupBalanceProvider`/`crossGroupHomeBalanceProvider` feed home display only; the #366 aggregate stays a display cache; settle-up (OUTBOUND) keeps computing from the untouched live `groupBalancesProvider`. The wrapper changes error/retry *timing* on streams, never data content. No write path is modified.
2. **Concrete claims re-verified in-session:** coarse awaits `group_balance_provider.dart:726-735`; uid-null branches `:909-917`/`:976-986`; aggregate bare-loading `:933-935`; `getExpenses` unbounded `expense_service.dart:129-133`; `watchGroup` `group_provider.dart:607-616`; `_isPermissionDenied` `group_detail_screen.dart:1045-1048`; all 9 stream constructions + `FirestoreRepository.db` reachability (scout table, spot-checked).
3. **Read-path per write-path:** no schema/field write changes. The only shape change is the in-memory `GroupBalancesOnce` record (+`groupSettlementsFailed`); its readers are `_homeBalanceFromOnce` (updated), **`profileStatsProvider` (`profile_stats_provider.dart:103` — reads `.balances` by named field, unaffected by the field addition, but D2's deadline reaches it: a real ≥8s hang that used to leave lifetime-spend in eternal loading now rejects at 8s and that group's spend is dropped from the fold — bounded-partial over eternal-loading, accepted; its #517 flicker tests join the must-stay-green set)**, and test literals (enumerated in Task 2.3).
4. **Fields enumerated from the type:** `HomeGroupBalance` = userNet, userPerEventNet, eventCount, partial, fromAggregate — D5 replaces a fabricated all-defaults record with loading. `GroupBalancesOnce` = balances, failedEventIds (+ new groupSettlementsFailed). Every constructor site of both records is listed in the tasks.
5. **Data contracts spelled out:** wrapper signature, constants, and the exact record shape are written below, not gestured at.
6. **Arithmetic decomposition:** the partial number remains `sum(readable slices)` under the existing #244 semantics; group-settlements-failed omits only the group-settlement fold and flags partial. The client↔server oracle (`recomputeNet`) is untouched — no server change, no parity surface.
7. **Orthogonal-axis adversarial pass (self-run):** money-flow axis exposed the members-failure hazard (→ B1); identity axis exposed the cross-group uid-null twin (→ B4); scope axis bounded the wrapper blast radius (9 streams, not `watchUserGroups`); time axis bounded every await (B2/B3). The Gate's fresh reviewers take the next pass.

---

# PR1 — layer A: `recoverDeniedListen` + adoption

Branch: `fix/997-listen-recovery`. Commit + PR body: **`Refs #997`** (partial delivery — commit message too, not just the body; squash-merge closes from the commit message).

### Task 1.1: the utility (RED first)

**Files:**
- Create: `test/unit/listen_recovery_test.dart`
- Create: `lib/core/utils/listen_recovery.dart`

**Step 1: Write the failing tests** (`test/unit/listen_recovery_test.dart`):

```dart
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/listen_recovery.dart';

FirebaseException _denied() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

void main() {
  group('recoverDeniedListen (#997)', () {
    test('permission-denied then success → recovers, emissions preserved', () async {
      var subscribes = 0;
      final barrierCalls = <int>[];
      final out = recoverDeniedListen<int>(
        () {
          subscribes++;
          if (subscribes == 1) {
            return Stream<int>.error(_denied());
          }
          return Stream.fromIterable([1, 2]);
        },
        pendingWritesBarrier: () async => barrierCalls.add(subscribes),
        backoff: Duration.zero,
      );
      expect(await out.toList(), [1, 2]);
      expect(subscribes, 2);
      expect(barrierCalls, [1]); // barrier awaited before the re-listen
    });

    test('genuine revocation → error surfaces after the budget', () async {
      var subscribes = 0;
      final out = recoverDeniedListen<int>(
        () {
          subscribes++;
          return Stream<int>.error(_denied());
        },
        pendingWritesBarrier: () async {},
        backoff: Duration.zero,
      );
      await expectLater(out.toList(), throwsA(isA<FirebaseException>()));
      expect(subscribes, 1 + kListenRecoveryMaxRetries);
    });

    test('cache-emit-then-deny loop cannot retry forever (budget never resets)',
        () async {
      var subscribes = 0;
      final seen = <int>[];
      final out = recoverDeniedListen<int>(
        () {
          subscribes++;
          return Stream<int>.multi((c) {
            c.add(subscribes); // cached emission
            c.addError(_denied());
            c.close();
          });
        },
        pendingWritesBarrier: () async {},
        backoff: Duration.zero,
      );
      await expectLater(
        out.forEach(seen.add),
        throwsA(isA<FirebaseException>()),
      );
      expect(subscribes, 1 + kListenRecoveryMaxRetries);
      expect(seen, [1, 2, 3]); // data still flowed through each attempt
    });

    test('non-permission error rethrows immediately, no retry', () async {
      var subscribes = 0;
      final out = recoverDeniedListen<int>(
        () {
          subscribes++;
          return Stream<int>.error(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          );
        },
        pendingWritesBarrier: () async {},
        backoff: Duration.zero,
      );
      await expectLater(out.toList(), throwsA(isA<FirebaseException>()));
      expect(subscribes, 1);
    });

    test('barrier throw/timeout is swallowed — retry still happens', () async {
      var subscribes = 0;
      final out = recoverDeniedListen<int>(
        () {
          subscribes++;
          if (subscribes == 1) return Stream<int>.error(_denied());
          return Stream.value(7);
        },
        pendingWritesBarrier: () async => throw UnimplementedError(),
        backoff: Duration.zero,
      );
      expect(await out.toList(), [7]);
    });

    test('clean close completes without resubscribe', () async {
      var subscribes = 0;
      final out = recoverDeniedListen<int>(
        () {
          subscribes++;
          return Stream.fromIterable([1]);
        },
        pendingWritesBarrier: () async {},
        backoff: Duration.zero,
      );
      expect(await out.toList(), [1]);
      expect(subscribes, 1);
    });
  });
}
```

**Step 2: Run to verify RED**

Run: `flutter test test/unit/listen_recovery_test.dart`
Expected: FAIL — `Target of URI doesn't exist ... listen_recovery.dart` (compile error = RED for a new unit).

**Step 3: Implement** (`lib/core/utils/listen_recovery.dart`):

```dart
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

/// Re-listen attempts after a `permission-denied` stream error before the
/// error is surfaced. Bounded so a GENUINE access revocation still reaches
/// the UI (#358 no-access state) — it just arrives ~1-2s later than before.
const kListenRecoveryMaxRetries = 2;

/// Cap on waiting for queued writes to replay before re-listening. Offline,
/// `waitForPendingWrites()` never resolves — the timeout keeps the recovery
/// loop bounded; the re-listen then serves from cache without error.
const kListenRecoveryBarrierTimeout = Duration(seconds: 10);

/// Small settle delay between the replay barrier and the re-listen.
const kListenRecoveryBackoff = Duration(milliseconds: 400);

/// Waits for Firestore writes that were pending when called to reach the
/// backend (`FirebaseFirestore.waitForPendingWrites`). Injected in tests.
typedef ListenPendingWritesBarrier = Future<void> Function();

/// #997: a Firestore listen rejected with `permission-denied` is TERMINAL —
/// the SDK never retries it. After an offline group creation, the SDK's
/// re-established listens race the queued founding-batch replay on reconnect;
/// when the listens lose, every group-scoped stream dies permanently even
/// though the very next listen would be accepted. This wrapper re-subscribes
/// [subscribe] after awaiting the pending-write replay, a bounded number of
/// times, so the transient race heals invisibly while genuine revocation
/// still surfaces (the budget never resets within one subscription — a
/// revoked listen that emits cache data before each denial must not loop).
///
/// Non-permission errors are never retried (the SDK handles transient
/// unavailability itself). Barrier failures (timeout, unimplemented fake) are
/// swallowed and the retry proceeds — precedent: the recovery flows'
/// `waitForPendingWrites().timeout(...)` swallow-and-proceed.
Stream<T> recoverDeniedListen<T>(
  Stream<T> Function() subscribe, {
  required ListenPendingWritesBarrier pendingWritesBarrier,
  int maxRetries = kListenRecoveryMaxRetries,
  Duration backoff = kListenRecoveryBackoff,
  Duration barrierTimeout = kListenRecoveryBarrierTimeout,
}) async* {
  var retries = 0;
  while (true) {
    try {
      await for (final value in subscribe()) {
        yield value;
      }
      return;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied' || retries >= maxRetries) rethrow;
      retries++;
      try {
        await pendingWritesBarrier().timeout(barrierTimeout);
      } catch (_) {
        // Barrier timeout / not supported — re-listen anyway; cache serves.
      }
      await Future<void>.delayed(backoff);
    }
  }
}
```

**Step 4: Run to verify GREEN**

Run: `flutter test test/unit/listen_recovery_test.dart`
Expected: all PASS.

**Step 5: Commit**

```bash
git add lib/core/utils/listen_recovery.dart test/unit/listen_recovery_test.dart
git commit -m "feat(core): bounded permission-denied listen recovery utility

Refs #997"
```

### Task 1.2: `FirestoreRepository.recoverListen` helper + adoption in all 9 watch methods

**Files:**
- Modify: `lib/core/services/firestore_repository.dart` (add helper)
- Modify: `lib/features/groups/providers/group_provider.dart` — `watchGroup` (:607), `watchMembers` (:570), `watchBalanceAggregate` (:596)
- Modify: `lib/features/events/services/event_service.dart` — `watchGroupEvents` (:35), `watchEvent` (:66)
- Modify: `lib/features/groups/services/group_settlement_service.dart` — `watchGroupSettlements` (:57)
- Modify: `lib/features/groups/services/group_activity_service.dart` — `watchRecentActivity` (:40)
- Modify: `lib/features/ledger/services/expense_service.dart` — `watchExpenses` (:39)
- Modify: `lib/features/ledger/services/settlement_service.dart` — `watchSettlements` (:34)
- Test: existing suites must stay green (wrapper is pass-through for fakes, which never emit permission-denied).

**Step 1: Add the helper to `FirestoreRepository`:**

```dart
/// Wraps a Firestore listen with the #997 bounded permission-denied
/// recovery (see [recoverDeniedListen]). Every group-scoped `watch*` in the
/// app goes through this; `watchUserGroups` deliberately does not (a
/// collection query returns an empty match set instead of a rule error, so
/// it self-heals on the next snapshot).
@protected
Stream<T> recoverListen<T>(Stream<T> Function() subscribe) {
  return recoverDeniedListen(
    subscribe,
    pendingWritesBarrier: () => _db.waitForPendingWrites(),
  );
}
```

**Step 2: Wrap each of the 9 constructions.** Pattern (note: any per-subscription state, like `watchExpenses`' doc-diff `cache`, moves INSIDE the closure so each re-listen starts clean — it already is created per-call today):

```dart
Stream<List<Expense>> watchExpenses(String groupId, String eventId) {
  return recoverListen(() {
    final cache = <String, Expense>{};
    return eventSubcollection(groupId, eventId, 'expenses')
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => _reconcileExpenses(cache, snap));
  });
}
```

Same mechanical wrap for the other 8 (no query/mapping changes).

**Step 3: Provider-layer regression test** (the test that would have caught #997) — add to `test/unit/listen_recovery_test.dart`:

A `ProviderContainer` test that overrides `groupEventsProvider(gid)` with a `recoverDeniedListen`-wrapped scripted source (denied once → then emits one event), plus the standard `makeContainer`-style overrides from `home_group_balance_provider_test.dart` (counting services, connectivity online, seeded aggregate ABSENT), and asserts `homeGroupBalanceProvider(gid)` ends in `AsyncData` (not the pre-fix sticky `AsyncError`). Reuse the 12-pump `settle()` idiom.

**Step 4: Full verification**

Run: `flutter analyze` → clean.
Run: `flutter test` → green (watch for `group_detail_staging_retry_574_test.dart` and `group_detail_no_access_test.dart` — both override at provider level and must pass unchanged; if either fails, stop and re-read A6).

**Step 5: Commit**

```bash
git add -A lib test
git commit -m "fix(groups): recover permission-denied listens after write replay

All 9 group-scoped watch* streams re-listen (bounded) once queued writes
replay, healing the reconnect listen/write race after offline group create.

Refs #997"
```

**Step 6: PR** — body: what/why, `Refs #997`, RED evidence (Task 1.1 Step 2 output pasted), test plan. Then `/automerge <N>`.

---

# PR2 — layer B: facade resilience (D1/D2/D3-narrow/D5)

Branch: `fix/997-facade-resilience` (branch from origin/main after PR1 merges, or independently — files don't overlap PR1). Commit + PR body: **`Closes #997`** (checklist item 6, overview error-vs-revoked, is satisfied by PR1's recovery — genuine revocation is now the only state that reaches `_NoAccessState`; note this in the PR body).

### Task 2.1: D5 — uid == null → loading (RED first)

**Files:**
- Modify: `test/unit/home_group_balance_provider_test.dart:375-397` (rewrite the pinned test)
- Modify: `lib/features/groups/providers/group_balance_provider.dart:909-917` and `:976-986`

**Step 1:** Rewrite `'null uid → zeros without touching either source'` → `'null uid (auth resolving) → loading without touching either source'`: assert `container.read(homeGroupBalanceProvider(gid)).isLoading` is true, keep `expFake.getCount == 0` / `setFake.getCount == 0`. Add a sibling for `crossGroupHomeBalanceProvider` (uid-null → `isLoading`).

**Step 2:** Run: `flutter test test/unit/home_group_balance_provider_test.dart` → the rewritten test FAILS (facade returns data today).

**Step 3:** Replace both uid-null `AsyncValue.data(...)` records with `return const AsyncValue.loading();` (keep a one-line comment: `// uid null ⇒ auth stream still resolving (_AuthGate guarantees an anon session) — loading, never a fabricated zero (#997 D5).`).

**Step 4:** Re-run file → PASS. **Step 5:** Commit `fix(home): uid-null facade state is loading, not fabricated zeros (Refs #997)`.

### Task 2.2: D2 — bounded deadlines in the once-path (RED first)

**Files:**
- Modify: `lib/features/groups/providers/group_balance_provider.dart` (once-provider `:722-772`)
- Test: `test/unit/home_group_balance_provider_test.dart`

**Step 1: RED test** — the field-mechanism repro from the issue: online, aggregate doc absent, events/members/settlements streams emit, but `getExpenses` hangs forever (a `_HangingExpenseService` whose `getExpenses` returns `Completer<List<Expense>>().future`). Use `fakeAsync` (elapse `kOnceReadDeadline + 1s`); assert the facade lands in `AsyncData` with `partial == true` (event dropped into `failedEventIds`), NOT eternal loading. (If `fakeAsync` + container proves flaky, fall back to a short injectable deadline via `@visibleForTesting` parameter — but try `fakeAsync` first.)

**Step 2:** Run → FAIL (stays loading forever today).

**Step 3: Implement.** New const at the top of the once-provider section:

```dart
/// Upper bound on every await inside [groupBalancesOnceProvider] (#997 D2).
/// A hung SDK read (gRPC wedge under DNS blackhole — the SDK never flips
/// offline) must degrade to the honest #244 partial/error states, never hold
/// home in a skeleton forever. Deliberately longer than [kWriteAckTimeout]:
/// a slow-but-succeeding read beats a spurious partial.
const kOnceReadDeadline = Duration(seconds: 8);
```

- Per-event gets: `.timeout(kOnceReadDeadline)` on both `getExpenses`/`getSettlements` awaits (TimeoutException lands in the existing `catch (_)` → `failedEventIds`).
- Coarse awaits: `final events = await eventsFut.timeout(kOnceReadDeadline);` and same for members (timeout REJECTS the future — facade error, honest per B1); group settlements handled in Task 2.3.
- **Stale-aggregate branch note (Gate adversary):** in the `aggregateMayBeStale` reconciliation branch (`:942-953`), a once-path timeout now propagates AsyncError where it previously hung. That is INTENDED — do NOT "helpfully" fall back to the stale aggregate value there; the aggregate is flagged stale precisely because it may not reflect local writes.
- Must stay green: `profile_stats_provider_test.dart` (a `groupBalancesOnceProvider` consumer — #517 flicker guard tests).

**Step 4:** Run file → PASS. **Step 5:** Commit `fix(home): bound every once-path read with kOnceReadDeadline (Refs #997)`.

### Task 2.3: D3-narrow — group-settlements failure degrades to partial (RED first)

**Files:**
- Modify: `lib/features/groups/providers/group_balance_provider.dart` (`GroupBalancesOnce` typedef `:697-700`, once-provider, `_homeBalanceFromOnce` `:827-848`)
- Modify: every `GroupBalancesOnce` record literal (compile-driven): `grep -rn "failedEventIds:" test/ lib/` — per the Gate rubric review the ~15 sites span `cross_group_balance_test.dart`, `profile_stats_provider_test.dart` (:134/:137/:211/:217), `active_journeys_provider_test.dart`, `cross_group_currency_buckets_test.dart`, `home_identity_polish_test.dart`, `home_recently_deeplink_test.dart`, `home_screen_dashboard_test.dart`, `bell_tab_select_test.dart` — let the compiler find them all, then re-run the grep to confirm none left

**Step 1: RED tests** (once-provider level, via `makeContainer` with `groupSettlementsProvider(gid).overrideWith((_) => Stream.error(FirebaseException(...permission-denied)))`):
- group-settlements stream errored → facade `AsyncData`, `partial == true`, event-nets still summed (seed one expense so the net is non-zero — proves the number survives).
- events stream errored → facade `AsyncError` (pin the loud path).
- members stream errored → facade `AsyncError` (pin the B1 universe hazard — comment WHY in the test).

**Step 2:** Run → first test FAILS (facade AsyncError today), other two already pass (they pin current behavior against future "helpful" widening — state this in comments).

**Step 3: Implement:**

```dart
typedef GroupBalancesOnce = ({
  GroupBalances balances,
  Set<String> failedEventIds,
  bool groupSettlementsFailed,
});
```

In the once-provider, replace the raw group-settlements await:

```dart
var groupSettlements = const <Settlement>[];
var groupSettlementsFailed = false;
try {
  groupSettlements = await groupSettlementsFut.timeout(kOnceReadDeadline);
} catch (_) {
  // #997 D3 (narrow): a missing group-settlement fold is the same class as
  // a dropped event (#244) — an INCOMPLETE sum, flagged partial. Events and
  // members failures stay loud: members=[] re-opens the #249 universe gap
  // (wrong money, not incomplete money) and eventCount would fabricate the
  // "0 events · settled" lie this issue exists to kill.
  groupSettlementsFailed = true;
}
```

`_homeBalanceFromOnce`: `partial: once.failedEventIds.isNotEmpty || once.groupSettlementsFailed`. Fix every record literal the compiler flags (`groupSettlementsFailed: false`).

**Step 4:** `flutter test test/unit/` → green. **Step 5:** Commit `fix(home): group-settlements read failure degrades to honest partial (Refs #997)`.

### Task 2.4: D1 — aggregate first-snapshot grace + once-path fall-through (RED first)

**Files:**
- Modify: `lib/features/groups/providers/group_balance_provider.dart` (`:931-935` region + new grace provider)
- Modify: `test/unit/home_group_balance_provider_test.dart:460-501` (re-scope Test A)
- Modify: `test/unit/cross_group_balance_test.dart:335-396` (re-frame docstring only — see below)

**Step 1: RED test** — re-scope `'stays loading until EVERY group resolves (no false settled-zero flash)'` into two:
- `'aggregate with no first snapshot: facade stays loading through the grace window'` — same setup (g2 aggregate `Stream.empty()`), override `aggregateFirstSnapshotGraceProvider('g2')` with a never-completing future, assert fold `isLoading` after 12 pumps (preserves the no-false-zero-flash pin).
- `'aggregate with no first snapshot: falls through to once-path after the grace'` — override the grace provider with a completed future; g2's once-path resolves from the (empty) fake streams → fold reaches `AsyncData` and g2 contributes its once-computed value.

**Step 2:** Run → second test FAILS (`:933-935` returns bare loading forever).

**Step 3: Implement:**

```dart
/// #997 D1: how long the online facade waits for the aggregate stream's
/// FIRST snapshot before consulting the once-path. Keeps the #366 zero-
/// per-event-read win on the normal path (the aggregate lands well inside
/// the window) while bounding the wedge case (listener up, no snapshot, no
/// error) that previously held home in a skeleton indefinitely.
const kAggregateFirstSnapshotGrace = Duration(seconds: 3);

final aggregateFirstSnapshotGraceProvider =
    FutureProvider.autoDispose.family<void, String>((ref, groupId) {
  return Future<void>.delayed(kAggregateFirstSnapshotGrace);
});
```

In the facade:

```dart
if (!aggregateMayBeStale && aggAsync.isLoading && !aggAsync.hasValue) {
  final grace = ref.watch(aggregateFirstSnapshotGraceProvider(groupId));
  if (grace.isLoading) return const AsyncValue.loading();
  final onceAsync = ref.watch(groupBalancesOnceProvider(groupId));
  return onceAsync.whenData((once) => _homeBalanceFromOnce(once, uid));
}
```

**Step 4:** For `cross_group_balance_test.dart:335-396` (hung `groupBalancesOnceProvider` future): the assertion stays valid — the fold's "loading until every group resolves" barrier is unchanged and correct; what changed is that production can no longer *produce* an unbounded once-path (D2). Re-write its doc comment to say exactly that (it pins fold semantics, not unbounded-loading-as-a-feature).

**Step 5:** `flutter analyze` + `flutter test test/unit/` → green. **Step 6:** Commit `fix(home): consult once-path when the aggregate withholds its first snapshot (Refs #997)`.

### Task 2.5: full suite, PR, close-out

- `flutter analyze` clean; `bash tool/check_theme_purity.sh` (no widget changes expected, but run it); `flutter test` full.
- PR body: `Closes #997` + spec line (`Spec: docs/plans/2026-07-07-997-listen-write-race-fix.md`) + RED evidence pasted for 2.1/2.2/2.3/2.4 + the B1 rationale (why D3 is narrower than the issue checklist) + note that checklist item 6 (overview error-vs-revoked) is delivered by PR1's recovery semantics.
- The commit that closes must carry `Closes #997` in the squash body.
- `/automerge <N>`.
- After merge: comment on #997 mapping each checklist box → PR1/PR2/rationale; file the hub-header `hasError` follow-up issue.

## Test matrix (what proves what)

| Concern | Test | State |
|---|---|---|
| Wrapper recovers race | `listen_recovery_test.dart` recover test | new, RED-first |
| Revocation still surfaces | budget-exhaustion + cache-emit-loop tests | new |
| Facade heals end-to-end | provider-layer regression (Task 1.2.3) | new |
| #358 no-access unchanged | `group_detail_no_access_test.dart` | existing, must stay green |
| #574 staging unchanged | `group_detail_staging_retry_574_test.dart` | existing, must stay green |
| uid-null honest | rewritten null-uid tests ×2 | re-scoped, RED-first |
| Hang → bounded partial | `_HangingExpenseService` + fakeAsync | new, RED-first |
| Settlements-only degrade | D3 trio (partial / loud events / loud members) | new, RED-first |
| Grace fall-through | re-scoped Test A pair | re-scoped, RED-first |
| Fold barrier intact | `cross_group_balance_test.dart` partial-loading | doc re-frame only |
