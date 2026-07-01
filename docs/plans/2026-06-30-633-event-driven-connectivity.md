# #633 — Event-driven connectivity: drop the 60s forced-read probe, resolve `syncing` on write replay

> Re-scoped issue (2026-06-26). The rebuild/dedupe half is **not real** (#623 already fixed it). The real
> work: replace the unconditional `Timer.periodic(60s)` forced `Source.server` probe with SDK signals, so
> `syncing` ("Saved — will sync") resolves when Firestore confirms outstanding writes reached the backend
> instead of lagging up to 60s (the #682 stale-probe-window bug class). The PR also adds an aggregate
> freshness barrier so home does not trust async aggregate docs before they catch up. Subsumes #682.

## Scope guard — connectivity + aggregate freshness boundary

This PR is no longer a single-file connectivity refactor. Gate found that the connectivity fix crosses the
home balance display cache, because `waitForPendingWrites()` proves only that the client write reached
Firestore; it does **not** prove `groups/{gid}/aggregates/balance` has been refreshed by the async Functions
aggregator. The intended scope is:

- `lib/core/providers/connectivity_provider.dart`: replace the 60s forced-read loop with SDK-driven
  reachability plus a pending-write replay barrier. The public enum and provider stay stable. The notifier
  API changes additively: `noteLocalWrite({String? groupId})`, `noteQueuedWrite({String? groupId})`, and an
  injectable `markBalanceAggregateMayBeStale` callback.
- `lib/core/providers/balance_aggregate_freshness_provider.dart`: in-memory per-group dirty marker for
  aggregate docs that may lag behind local Firestore writes.
- `lib/features/groups/providers/group_balance_provider.dart`: when online but the group is dirty, compute the
  home balance from the once-path and keep doing so until the aggregate doc matches that once-path result;
  only then clear the dirty marker and trust the aggregate again.
- Balance-affecting write callsites pass `groupId` into `noteLocalWrite` / `noteQueuedWrite`. This includes
  expense and settlement writes, plus event writes that affect the aggregate event count.
- Cache-isolation/auth-swap paths invalidate the dirty-marker provider together with connectivity so a
  previous UID's aggregate freshness state cannot leak across users.

Non-goals remain unchanged: no Firestore rules changes, no Cloud Functions schema change, no money arithmetic
rewrite, and no custom offline cache or sync queue.

## The bug (verified against code)

- Before this PR, `ConnectivityNotifier` drove everything from a foreground `Timer.periodic(60s)` →
  `checkConnectivity()` → `_defaultConnectivityProbe()`: a forced
  `get(GetOptions(source: Source.server))` on `fcm_tokens/{uid}`.
- That probe is the **sole resolver of `syncing`** — no app code calls `setOnline/setOffline`; only the
  60s tick or `didChangeAppLifecycleState(resumed)` runs `checkConnectivity`. So after an offline money-write
  (`noteQueuedWrite` → `syncing`), "Saved — will sync" can persist **up to 60s** past the actual reconnect.
  That lag IS #682.
- `snapshotsInSync()` / `metadata.isFromCache` / `metadata.hasPendingWrites`: **0 hits in `lib/`** (grep) —
  the SDK's own connectivity signals are unused.
- The first connectivity fix exposed a second freshness bug: once status returned to `online`,
  `homeGroupBalanceProvider` trusted the aggregate stream immediately. That was wrong for both offline replay
  and normal online server-acked money writes, because `functions/src/triggers/balanceAggregator.ts` refreshes
  the aggregate doc asynchronously after the source expense/settlement/event write lands.

## Who reads the state (the readers the refactor must keep correct)

| Reader | What it reads | Contract to preserve |
|---|---|---|
| `offline_banner.dart:14` | full enum (online/offline/syncing) | 3-way banner; `syncing` must still be reachable AND must clear promptly on reconnect (the fix) |
| `group_balance_provider.dart` | `.select((s)=>s==online)` + `balanceAggregateFreshnessProvider` | offline/syncing→once-path; online→aggregate only when not dirty, otherwise once-path until aggregate equals once-path |
| Balance-affecting write callsites | `ref.read(connectivityProvider)` for `skipWait = status != online`, then `noteLocalWrite/QueuedWrite(groupId)` | offline/syncing skip the 5s wait; online waits; every balance-affecting local write marks the group aggregate dirty |
| `add_shadow_member_sheet.dart:89`, `create_group_screen.dart:426` | `== online` UI gate | unchanged |

## Design — chosen approach

Replace the internal mechanism while preserving the enum and existing method semantics. New data-flow is
additive: write callsites may pass `groupId` so the home balance aggregate cache can be invalidated.

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
does not. This preserves the first `homeGroupBalanceProvider` contract: while queued expense/settlement writes
may not have replayed, `ConnectivityStatus.syncing` keeps home on the once-path instead of trusting the
server aggregate display cache.

The barrier is **not** an aggregate freshness proof. Once the source write reaches Firestore, the aggregate
doc still depends on async Functions triggers. Balance-affecting writes therefore also mark the affected
group's aggregate dirty. The home facade keeps using the once-path while dirty and clears the marker only
after the aggregate result equals the once-path result.

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

### 5. Write-path signals + aggregate freshness
`noteQueuedWrite()` (unconditional→syncing) stays the **fast** offline signal for the money paths: a write
that times out at `kWriteAckTimeout` (5s) forces `syncing` immediately, so the *next* write `skipWait`s.
The pending-write barrier flips `syncing→online` after replay.

`noteLocalWrite({groupId})` keeps its connectivity-state contract: it only changes the enum from
`offline→syncing`. Its aggregate-freshness contract is broader: when `groupId` is supplied, it marks the group
dirty in every connectivity state, including ordinary online writes that receive a server ack. This closes the
stale-aggregate window between source-write acceptance and the Functions aggregate refresh. `noteQueuedWrite`
also marks the supplied group dirty before entering `syncing`.

Callsites that do not affect group balances can continue calling these methods without `groupId`.

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
  void Function(String groupId)? markBalanceAggregateMayBeStale, // NEW
  bool startPeriodicChecks = true,                 // unchanged name; now gates listener + init probe
});
```

- Default `syncSignals` builds `fcm_tokens/{uid}.snapshots(includeMetadataChanges:true).map((s)=>s.metadata.isFromCache)`.
- `startPeriodicChecks:false` ⇒ **no listener, no init probe** (current test contract — tests drive state via
  setters). Keeps every `startPeriodicChecks:false` test green unchanged.
- **No-Firebase-app safety:** building the default `syncSignals` / firing the init probe touches
  `FirebaseConfig.firestore`/`currentUser`, which **throws `[core/no-app]`** in unit tests (not returns null
  — CLAUDE.md gotcha). Wrap the subscription in try/catch → fail-open (no subscription; state stays as set),
  exactly like the existing `WidgetsBinding.addObserver` try/catch. The probe is already internally
  try/catched (returns null). So `widget_coverage_test.dart` (`ConnectivityNotifier()..setOffline()`,
  default `startPeriodicChecks:true`) stays green: listener skipped, init probe returns null, `setOffline`
  wins.
- `isPeriodicCheckActive` getter (`@visibleForTesting`, only the connectivity test uses it) → rename to
  `isLiveCheckActive` (true when the listener subscription is active); update that one test.

## State machine + dirty aggregate markers

```
initial: online (optimistic, unchanged)
online  --listener isFromCache:true (after server seen) | probe false--> offline
online  --noteLocalWrite(groupId)----------------------------------------> online + dirty aggregate
online  --noteQueuedWrite (write timed out)------------------------------> syncing
offline --noteLocalWrite | noteQueuedWrite-------------------------------> syncing
offline --listener isFromCache:false | probe true------------------------> online
syncing --pending writes acknowledged-------------------------------------> online
syncing --pending writes rejected------------------------------------------> offline
*       --probe null (no uid / no-app / non-network error)---------------> unchanged
```

The connectivity-state change: `syncing→online` now fires on the pending-write barrier, not on the 60s probe
or on an unrelated owner-doc server snapshot. The balance-display change: a supplied `groupId` marks the
aggregate dirty independently of connectivity state. Every existing explicit setter/probe transition remains
available when no queued-write barrier is active.

## Verification principles (run at spec time — reported per Operating Contract)

1. **Classify callsites.** Balance-affecting write callsites are still INBOUND to the notifier: they *read*
   `connectivityProvider` for `skipWait` and *call* `noteLocalWrite/noteQueuedWrite`, which mutate in-memory
   UI state. The callsites perform the Firestore writes; the notifier performs no Firestore write. The new
   `groupId` argument is an in-memory display-cache invalidation signal, not a persistence write.
2. **Verify claims vs code.** Verify `connectivity_provider.dart` for listener/probe/barrier behavior and
   dirty-marker callback calls; `write_ack.dart` for `skipWait`; `group_balance_provider.dart` for online bool
   selection plus aggregate-vs-once matching; write callsites for `groupId` propagation; cache-isolation code
   for provider invalidation.
3. **Trace read-path per write-path.** Source expense/settlement/event writes can make the aggregate stale.
   The in-memory dirty marker is read by `homeGroupBalanceProvider`; while dirty, the provider reads the
   once-path and compares it with the aggregate stream. `offline_banner` still reads only connectivity state,
   and the next write still reads connectivity state for `skipWait`.
4. **Enumerate from the type.** `ConnectivityStatus{online,offline,syncing}` — 3 values, all preserved with
   identical meaning. Notifier public methods are enumerated from the implementation and changed only
   additively for aggregate freshness.
5. **Data contracts.** Exact ctor signature (above), the `ConnectivitySyncSignals = Stream<bool> Function()`
   contract (bool = `metadata.isFromCache`), the `BalanceAggregateFreshnessNotifier` set contract (dirty group
   IDs only), and the full state-transition/dirty-marker table. Spelled out, not gestured.
6. **Arithmetic decomposition.** No money math, no `MoneySerializer`, no allocator. The balance read-source
   selection is refined, not recomputed: offline/syncing always use the once-path; online uses the aggregate
   only when the group is not dirty or the dirty aggregate matches the once-path result.
7. **Adversarial orthogonal axis.** Fix axes = connectivity-detection mechanism (timer→event) and aggregate
   freshness (source write→async aggregate trigger). The worked tests exercise orthogonal axes: **money-flow**
   (a queued money-write's `syncing` stays on the once-path after a reachability-only signal, resolves to
   `online` only after the pending-write barrier, and dirty aggregates keep using the once-path until catch-up);
   **identity** (uid==null / no-app → listener can't build / probe null → safe no-crash, state sticky);
   **lifecycle/time** (pause cancels the listener → no background read; resume re-subscribes + one probe).

## TDD plan (RED first — money-write-gating surface ⇒ table-driven)

Rewrite/extend `test/core/providers/connectivity_provider_test.dart`, `test/unit/home_group_balance_provider_test.dart`,
and the affected cache-isolation tests:

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
7. **write signals split state from freshness:** `noteLocalWrite` remains offline→syncing for connectivity
   state, but `noteLocalWrite(groupId)` marks that group dirty even while online; `noteQueuedWrite(groupId)`
   also marks dirty before entering `syncing`.
8. **aggregate freshness barrier:** online + dirty + stale aggregate returns once-path and leaves the dirty
   marker set; after the aggregate stream catches up to the once-path result, the provider returns aggregate
   data and clears the marker.
9. **cache isolation:** auth/cache isolation invalidates `balanceAggregateFreshnessProvider` with the other
   UID-sensitive providers.

Regression suites that MUST stay green:
- `test/core/utils/write_ack_test.dart` (no change to `write_ack.dart`).
- `test/unit/home_group_balance_provider_test.dart` — esp. the #623 churn test (offline→syncing must NOT
  re-evaluate the facade; syncing→online MUST) and the dirty-aggregate catch-up test.
- `test/features/**/*_offline_412_test.dart` (add/edit/create-group/event-settings) — `startPeriodicChecks:false`
  + setters.
- `test/shared/widgets/offline_banner_test.dart` — 3-state banner.

Run: `flutter test test/core/providers/connectivity_provider_test.dart test/unit/home_group_balance_provider_test.dart
test/unit/cache_isolation_controller_test.dart`, then the regression files, then `flutter analyze` +
`bash tool/check_theme_purity.sh`.

## Acceptance → coverage

| Acceptance bullet | Met by |
|---|---|
| No unconditional per-minute forced `Source.server` read | timer dropped (§1); only init/resume one-shot probe + a cheap persistent listen |
| `syncing` resolves on actual write replay, small bound | pending-write barrier (§2b); test 1 |
| `skipWait` + balance source correct across offline→online; once-path while offline/syncing | `.select((s)=>s==online)` retained; #623 churn regression test |
| Online server-acked balance writes do not briefly trust stale aggregate docs | `noteLocalWrite(groupId)` marks dirty in every state; home dirty-aggregate catch-up test |
| Offline detection reliable — no false-online forcing a full-timeout wait | listener flip (seconds) + init/resume probe shrink the window; `noteQueuedWrite` 5s fallback remains for the brief SDK-detection window (existing safety net, not a regression) |
| Tests model real offline via injected signals, not FakeFirebaseFirestore | injected `syncSignals` StreamController + `connectivityProbe` |

## Out of scope
- `snapshotsInSync` / `hasPendingWrites` adoption (rejected above).
- Changing `kWriteAckTimeout` or `awaitServerAck` semantics.
- Any rules / Functions / schema / routing / money-math change — none.
- Adding a new durable aggregate version field. This PR uses explicit aggregate-vs-once equality as the
  freshness barrier.

## Gate
Gate-required: the surface gates every money-write's `skipWait`, the home balance read source, and whether
money displayed on home may come from a stale aggregate cache. Run a fresh-context Gate on this spec before
auto-merge; stop when no [P1].
