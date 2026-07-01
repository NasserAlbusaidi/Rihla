# #633 — Event-driven connectivity: drop the 60s forced-read probe, resolve `syncing` on write replay

> Re-scoped issue (2026-06-26). The rebuild/dedupe half is **not real** (#623 already fixed it). The real
> work: replace the unconditional `Timer.periodic(60s)` forced `Source.server` probe with SDK signals, so
> `syncing` ("Saved — will sync") resolves when Firestore confirms outstanding writes reached the backend
> instead of lagging up to 60s (the #682 stale-probe-window bug class). Subsumes #682.

## Scope guard — single-file refactor, public API frozen

The **entire diff lives in `lib/core/providers/connectivity_provider.dart` + its tests.** The public surface
of `ConnectivityNotifier` is preserved byte-for-byte, so **no consumer is edited** — including the three
consumers that sit in `lib/features/events/` (`create_event_screen`, `event_danger_section`,
`event_info_section`), which another agent is actively editing for #704. Frozen surface:

- `enum ConnectivityStatus { online, offline, syncing }` — all three states keep their exact meaning.
- `connectivityProvider` (`StateNotifierProvider<ConnectivityNotifier, ConnectivityStatus>`).
- `.notifier` methods used by lib: `noteLocalWrite()` (offline→syncing only), `noteQueuedWrite()`
  (unconditional→syncing), `checkConnectivity()`.
- Test-facing methods: `setOnline()/setOffline()/setSyncing()` (no lib callers — only widget tests).
- Ctor params: `ConnectivityProbe? connectivityProbe`, `bool startPeriodicChecks` (kept; ~10 test files
  pass `startPeriodicChecks: false`).

Adding a constructor param and an internal mechanism is API-additive, not a break. **No `lib/` file outside
`connectivity_provider.dart` changes** ⇒ zero collision with #704.

**Test footprint (actual):** `connectivity_provider.dart` + its test, plus two setter-forced constructions
that must opt out of the now-immediate live mechanism — `widget_coverage_test.dart` (×2) and
`shared_widgets_theme_test.dart` (×1) switched to `ConnectivityNotifier(startPeriodicChecks: false)..setX()`.
`flutter_test_config.dart` does not init Firebase, but the construct-time probe/listener made those pumps
non-deterministic; `startPeriodicChecks:false` is the established idiom for a fixed-state notifier. All
test-only; no `lib/` collision with #704.

## The bug (verified against code)

- `ConnectivityNotifier` (`connectivity_provider.dart`) drives everything from a foreground
  `Timer.periodic(60s)` (L77) → `checkConnectivity()` (L110) → `_defaultConnectivityProbe()` (L56-73): a
  forced `get(GetOptions(source: Source.server))` on `fcm_tokens/{uid}`.
- That probe is the **sole resolver of `syncing`** — no app code calls `setOnline/setOffline`; only the
  60s tick or `didChangeAppLifecycleState(resumed)` runs `checkConnectivity` (L83-92). So after an offline
  money-write (`noteQueuedWrite` → `syncing`, L146-148), "Saved — will sync" can persist **up to 60s** past
  the actual reconnect. That lag IS #682.
- `snapshotsInSync()` / `metadata.isFromCache` / `metadata.hasPendingWrites`: **0 hits in `lib/`** (grep) —
  the SDK's own connectivity signals are unused.

## Who reads the state (the readers the refactor must keep correct)

| Reader | What it reads | Contract to preserve |
|---|---|---|
| `offline_banner.dart:14` | full enum (online/offline/syncing) | 3-way banner; `syncing` must still be reachable AND must clear promptly on reconnect (the fix) |
| `group_balance_provider.dart:833` | `.select((s)=>s==online)` | online→aggregate doc; **offline AND syncing→once-path**; bool select avoids #623 churn |
| 11 money-write callsites | `ref.read(connectivityProvider)` for `skipWait = status != online` | offline/syncing skip the 5s wait; online waits then `noteQueuedWrite` on timeout |
| `add_shadow_member_sheet.dart:89`, `create_group_screen.dart:426` | `== online` UI gate | unchanged |

## Design — chosen approach

Replace the internal mechanism; keep the state machine and public API.

### 1. Drop the periodic timer
Remove `Timer.periodic(60s)` and `_startPeriodicCheck()`. No unconditional per-minute `Source.server` read.

### 2. Persistent metadata listener (the new primary signal)
Subscribe to `fcm_tokens/{uid}.snapshots(includeMetadataChanges: true)` — same owner-only doc, no broad
perms, cheaper than a 60s forced GET. This proves reachability only, not replay of arbitrary
expense/settlement writes. Map each emission:

- `metadata.isFromCache == false` → **server reached** → `state = online` only when no queued-write replay
  barrier is active.
- `metadata.isFromCache == true` → **offline**, but ONLY after a server snapshot has been seen in this
  subscription (`_sawServer` latch). The cold-start cache-first emission (`isFromCache:true` before any
  server contact) must **not** false-flip to offline — leave state unchanged and let the init probe / a
  write-timeout drive offline. Firestore re-emits `isFromCache:true` when it detects a dropped backend
  connection on an active `includeMetadataChanges` listen, so a genuine drop (after server-seen) flips us
  offline.

`includeMetadataChanges:true` is required — metadata-only `isFromCache` flips are otherwise suppressed.

**Listener-builder safety (Gate P2/P3):**
- `.listen(..., onError: (_) {})` — a real `.snapshots()` emits **async error events** (permission-denied,
  transient) that a ctor try/catch cannot catch; the `onError` handler fails-open (keep current state).
- uid==null guard: the default builder returns `const Stream<bool>.empty()` when `FirebaseConfig.currentUser?.uid`
  is null (mirrors the probe's `if (uid==null) return null`) — never `.doc(null)`.
- `_sawServer` is an instance latch **reset on every (re-)subscribe** (so each resume subscription ignores
  its own cache-first `isFromCache:true`).

### 2b. Pending-write replay barrier (the `syncing` resolver)

`noteLocalWrite()` (offline→syncing) and `noteQueuedWrite()` (unconditional→syncing) start
`FirebaseFirestore.waitForPendingWrites()` through an injectable `ConnectivityPendingWritesBarrier`.
Only that barrier clears queued-write `syncing` to `online`; a metadata server snapshot or one-shot probe
does not. This preserves the `homeGroupBalanceProvider` contract: while queued expense/settlement writes
may not have replayed, `ConnectivityStatus.syncing` keeps home on the once-path instead of trusting the
server aggregate display cache.

If the barrier errors during a user swap, `syncing` falls back to `offline`; cache isolation also invalidates
`connectivityProvider`, so the old `fcm_tokens/{oldUid}` listener is disposed before the UID changes.

### 3. One-shot backstop probe on init + resume (sanctioned by acceptance)
Keep the existing `_connectivityProbe()` (`Source.server` GET) but fire it **once** on construct (cold
start) and once on `AppLifecycleState.resumed` — NOT on a loop. This gives prompt cold-start/resume offline
detection before the first write, covering the window before the listener has seen the server. The probe's
existing 3-way return (true/false/null; null = no change) is preserved.

### 4. Lifecycle
- `paused`/`inactive` → cancel the listener subscription (no background reads/radio wake). Mirrors today's
  timer cancel.
- `resumed` → re-subscribe the listener + fire one backstop probe.

### 5. Write-path signals unchanged
`noteQueuedWrite()` (unconditional→syncing) stays the **fast** offline signal for the money paths: a write
that times out at `kWriteAckTimeout` (5s) forces `syncing` immediately, so the *next* write `skipWait`s.
The pending-write barrier flips `syncing→online` after replay. `noteLocalWrite()` (offline→syncing)
unchanged except that it also starts the barrier.

### Rejected alternatives
- **`snapshotsInSync()` as the primary signal** — rejected: it fires after *every* local mutation (it's a
  UI-consistency signal, not a network one) and doesn't distinguish online/offline. The metadata listener
  covers reachability and `waitForPendingWrites()` covers replay; `snapshotsInSync` adds noise, not signal.
  (`hasPendingWrites` on `fcm_tokens` only tracks pending writes to *that* doc, not to expenses, so it's not
  a general replay detector either.)
- **Keep the listener alive while backgrounded** — rejected: defeats the battery goal (radio wake). Cancel
  on pause, re-subscribe + probe on resume.
- **Drop the one-shot probe entirely (listener-only)** — rejected: a cold-start-while-offline with no writes
  would stay falsely `online` until a write times out; the init probe restores prompt detection and lets the
  existing `connectivityProbe` test seam keep working.

## New injection seam (tests, no FakeFirebaseFirestore)

```dart
/// Emits the live "is this snapshot from cache?" signal — true = served from cache
/// (offline / not-yet-synced), false = served from the server (online).
typedef ConnectivitySyncSignals = Stream<bool> Function();

ConnectivityNotifier({
  ConnectivityProbe? connectivityProbe,            // unchanged — one-shot init/resume probe
  ConnectivitySyncSignals? syncSignals,            // NEW — default = fcm_tokens metadata listener
  ConnectivityPendingWritesBarrier? pendingWritesBarrier, // NEW — default = waitForPendingWrites()
  bool startPeriodicChecks = true,                 // unchanged name; now gates listener + init probe
});
```

- Default `syncSignals` builds `fcm_tokens/{uid}.snapshots(includeMetadataChanges:true).map((s)=>s.metadata.isFromCache)`.
- `startPeriodicChecks:false` ⇒ **no listener, no init probe** (current test contract — tests drive state via
  setters). Keeps every `startPeriodicChecks:false` test green unchanged.
- **No-Firebase-app safety:** building the default `syncSignals` / firing the init probe touches
  `FirebaseConfig.firestore`/`currentUser`, which **throws `[core/no-app]`** in unit tests (not returns null
  — CLAUDE.md gotcha). Wrap the subscription in try/catch → fail-open (no subscription; state stays as set),
  exactly like the existing `WidgetsBinding.addObserver` try/catch (L44-48). The probe is already internally
  try/catched (returns null). So `widget_coverage_test.dart` (`ConnectivityNotifier()..setOffline()`,
  default `startPeriodicChecks:true`) stays green: listener skipped, init probe returns null, `setOffline`
  wins.
- `isPeriodicCheckActive` getter (`@visibleForTesting`, only the connectivity test uses it) → rename to
  `isLiveCheckActive` (true when the listener subscription is active); update that one test.

## State machine (unchanged transitions, new triggers)

```
initial: online (optimistic, unchanged)
online  --listener isFromCache:true (after server seen) | probe false--> offline
online  --noteQueuedWrite (write timed out)------------------------------> syncing
offline --noteLocalWrite | noteQueuedWrite-------------------------------> syncing
offline --listener isFromCache:false | probe true------------------------> online
syncing --pending writes acknowledged-------------------------------------> online
syncing --pending writes rejected------------------------------------------> offline
*       --probe null (no uid / no-app / non-network error)---------------> unchanged
```

The behavioral change: `syncing→online` now fires on the pending-write barrier, not on the 60s probe or on
an unrelated owner-doc server snapshot. Every existing explicit setter/probe transition remains available
when no queued-write barrier is active.

## Verification principles (run at spec time — reported per Operating Contract)

1. **Classify callsites.** All 11 money-write callsites are INBOUND to the notifier (they *read*
   `connectivityProvider` for `skipWait` and *call* `noteLocalWrite/noteQueuedWrite`, which mutate in-memory
   UI state — **not** Firestore). The notifier's only Firestore interaction is READ (probe GET + metadata
   listen); it performs **no Firestore write**. No persistence OUTBOUND path changes. The refactor edits
   **zero** callsites (API frozen). Lowest-risk class for the consumers.
2. **Verify claims vs code.** Verified this session: `connectivity_provider.dart` L9/L43/L56-73/L77/L83-92/
   L110-119/L133-137/L146-148; `write_ack.dart` `skipWait` L49; `group_balance_provider.dart:833` `.select`;
   11 callsites (grep); `snapshotsInSync|hasPendingWrites|isFromCache` = 0 lib hits (grep). `FirebaseConfig`
   no-app throw — CLAUDE.md pitfall, applied to the try/catch design.
3. **Trace read-path per write-path.** No Firestore write-path changes (N/A for persistence). For the
   in-memory state "write": the new `syncing→online` (listener) path's readers are enumerated — `offline_banner`
   (clears "will sync"), `group_balance_provider` (re-evaluates online→aggregate), the next write's `skipWait`
   (resumes normal 5s wait). Each named.
4. **Enumerate from the type.** `ConnectivityStatus{online,offline,syncing}` — 3 values, all preserved with
   identical meaning. Notifier public methods enumerated from the file (frozen list above).
5. **Data contracts.** Exact ctor signature (above), the `ConnectivitySyncSignals = Stream<bool> Function()`
   contract (bool = `metadata.isFromCache`), the full state-transition table. Spelled out, not gestured.
6. **Arithmetic decomposition.** N/A — no money math, no `MoneySerializer`, no allocator. The balance
   read-source selection is unchanged (`.select((s)=>s==online)`: online→aggregate, offline/syncing→once-path).
   Oracle parity untouched (this file never computes balances).
7. **Adversarial orthogonal axis.** Fix axis = connectivity-detection mechanism (timer→event). The worked
   tests exercise orthogonal axes: **money-flow** (a queued money-write's `syncing` stays on the once-path
   after a reachability-only signal, then resolves to `online` only after the pending-write barrier, and
   #623 churn stays correct);
   **identity** (uid==null / no-app → listener can't build / probe null → safe no-crash, state sticky);
   **lifecycle/time** (pause cancels the listener → no background read; resume re-subscribes + one probe).

## TDD plan (RED first — `refactor` of a money-write-gating surface ⇒ table-driven)

Rewrite/extend `test/core/providers/connectivity_provider_test.dart` (and `test/unit/connectivity_provider_test.dart`):

1. **#682 fix (the defining RED test):** construct with injected `syncSignals` and
   `pendingWritesBarrier`; `noteQueuedWrite()` → `syncing`; push `false` (reachability) and verify it stays
   `syncing`; complete the pending-write barrier → state becomes `online` **without** any 60s timer /
   `checkConnectivity` call. RED today (no barrier seam exists; `syncing` only clears via probe).
2. **online/offline via listener:** push `false`→online; after server-seen, push `true`→offline.
3. **cold-start cache-first guard:** fresh notifier, push `true` first (no server seen) → stays `online`
   (no false-offline). Then `false`→online, then `true`→offline (server-seen latch works).
4. **one-shot probe on init/resume:** inject `connectivityProbe: ()=>false` → offline after init;
   `didChangeAppLifecycleState(resumed)` re-fires probe + re-subscribes (assert `isLiveCheckActive`).
5. **lifecycle:** `paused`/`inactive` → subscription cancelled (`isLiveCheckActive==false`), no leak;
   `resumed` → re-subscribed.
6. **no-Firebase-app fail-open:** default `syncSignals` with no Firebase initialized → ctor does not throw;
   `setOffline()` still works (covers `widget_coverage_test` default-true path).
7. **write signals unchanged:** `noteLocalWrite` offline→syncing only (no-op online/syncing);
   `noteQueuedWrite` unconditional→syncing.

Regression suites that MUST stay green unchanged (public API frozen):
- `test/core/utils/write_ack_test.dart` (no change to `write_ack.dart`).
- `test/unit/home_group_balance_provider_test.dart` — esp. the #623 churn test (offline→syncing must NOT
  re-evaluate the facade; syncing→online MUST).
- `test/features/**/*_offline_412_test.dart` (add/edit/create-group/event-settings) — `startPeriodicChecks:false`
  + setters, untouched.
- `test/shared/widgets/offline_banner_test.dart` — 3-state banner.

Run: `flutter test test/core/providers/connectivity_provider_test.dart test/unit/connectivity_provider_test.dart`
then the regression files, then `flutter analyze` + `bash tool/check_theme_purity.sh` (no widget change, but cheap).

## Acceptance → coverage

| Acceptance bullet | Met by |
|---|---|
| No unconditional per-minute forced `Source.server` read | timer dropped (§1); only init/resume one-shot probe + a cheap persistent listen |
| `syncing` resolves on actual write replay, small bound | pending-write barrier (§2b); test 1 |
| `skipWait` + balance source correct across offline→online; once-path while offline/syncing | API + `.select((s)=>s==online)` frozen; #623 churn regression test |
| Offline detection reliable — no false-online forcing a full-timeout wait | listener flip (seconds) + init/resume probe shrink the window; `noteQueuedWrite` 5s fallback remains for the brief SDK-detection window (existing safety net, not a regression) |
| Tests model real offline via injected signals, not FakeFirebaseFirestore | injected `syncSignals` StreamController + `connectivityProbe` |

## Out of scope
- Any consumer/callsite edit (API frozen).
- `snapshotsInSync` / `hasPendingWrites` adoption (rejected above).
- Changing `kWriteAckTimeout` or `awaitServerAck` semantics.
- Any rules / Functions / schema / routing / money-math change — none.

## Gate
Not strictly one of the four mandatory Gate categories (no money-math/rules/routing/schema-field change), but
the surface **gates every money-write's `skipWait` and the balance read-source**, and the issue flags
Gate-category care. Run a fresh-context Opus Gate on this spec before code; stop when no [P1].
