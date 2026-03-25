# Technology Stack

**Project:** Rihla v2 — Groups & Events (Supabase → Firestore migration)
**Researched:** 2026-03-26
**Research mode:** Ecosystem — existing Flutter app, adding groups/events layer + backend migration

---

## Context: What This Milestone Is Doing

This is NOT a greenfield Flutter project. The existing app runs Flutter 3.x with Riverpod 2.x, Supabase, and sqflite. This milestone:

1. Replaces Supabase with Firebase Firestore as the cloud backend
2. Adds a groups/events layer on top of the existing trip architecture
3. Keeps sqflite for fast local reads (hybrid offline architecture)
4. Migrates from anonymous Supabase auth to anonymous Firebase Auth

The current `pubspec.yaml` already has `firebase_core: ^3.12.1` and `firebase_messaging: ^15.2.4`. The Firebase project exists — FCM is live. This migration is additive, not a rewrite.

---

## Recommended Stack

### Backend — Firebase

| Technology | Recommended Version | Purpose | Why |
|------------|--------------------|---------|----|
| `firebase_core` | `^4.6.0` | Firebase app initialization | Required upgrade — current 3.x is incompatible with Firestore 6.x. All FlutterFire plugins now require firebase_core 4.x. Bump is mandatory. |
| `cloud_firestore` | `^6.2.0` | Primary cloud database | NoSQL with built-in offline persistence, real-time listeners, collection group queries for cross-event aggregation. Replaces Supabase PostgreSQL + Realtime. Latest as of 2026-03-24. |
| `firebase_auth` | `^6.3.0` | Anonymous authentication | Replaces `signInAnonymously()` on Supabase. Same UX: silently creates anonymous user on launch. UID persists across restarts on-device (but not across app reinstalls — same limitation as Supabase anonymous). |
| `firebase_storage` | `^13.2.0` | Document vault + memories | Replaces Supabase Storage buckets (`trip-documents`, `trip-memories`). Signed URL pattern stays; implementation switches to `getDownloadURL()`. |
| `firebase_messaging` | `^15.2.4` | Push notifications | Already in use. No version change needed — compatible with firebase_core 4.x. |

**Confidence:** HIGH — versions verified from pub.dev 2026-03-24. All published by verified firebase.google.com publisher.

**Critical:** Do NOT pin `firebase_core` to 3.x. The 6.x Firestore package requires `firebase_core ^4.6.0`. Mixing these versions causes build failures.

---

### State Management

| Technology | Recommended Version | Purpose | Why |
|------------|--------------------|---------|----|
| `flutter_riverpod` | Stay on `^2.4.9` for now, plan Riverpod 3.x upgrade separately | Provider-based state management | See rationale below. |

**Riverpod 2.x vs 3.x — DO NOT upgrade to 3.x in this milestone:**

Riverpod 3.0 shipped in September 2025. It has real improvements (auto-retry, `Ref.mounted`, experimental offline persistence, unified `Notifier` API). However, it also has breaking changes that affect every provider in the codebase:

- `StateProvider`, `StateNotifierProvider`, `ChangeNotifierProvider` are now legacy APIs
- `Ref` loses its type parameter — all `AutoDisposeRef`, `FutureProviderRef` etc. disappear
- All `updateShouldNotify` now use `==` (was `identical`) — silent behavior change for mutable state
- All provider failures rethrow as `ProviderException` — every `catch (e)` block may need updating
- Listeners in invisible widgets are auto-paused — can affect sync-on-background patterns

The Firestore migration + groups feature is already a large scope. Mixing in a Riverpod major-version migration creates compounding risk. Do Riverpod 3.x as its own milestone after Firestore is stable.

**For Firestore + Riverpod 2.x:** Use `StreamProvider.family` to wrap `FirebaseFirestore.instance.collection('...').snapshots()`. Firestore streams are hot and reconnect-aware — they work cleanly with Riverpod's `StreamProvider`. The existing `StreamProvider` and `StateNotifierProvider` patterns in the codebase transfer directly.

**Confidence:** HIGH for "stay on 2.x for this milestone" recommendation. MEDIUM for Riverpod 3.x details (verified from official riverpod.dev docs, but the upgrade path has known early bugs per community reports).

---

### Local Storage (Keep Both)

| Technology | Recommended Version | Purpose | Why |
|------------|--------------------|---------|----|
| `sqflite` | `^2.4.2` (current) | Fast local reads, sync queue | Keep alongside Firestore. See architecture rationale below. |
| `path` | `^1.9.1` (current) | File path utilities for sqflite | No change needed. |

**Firestore offline persistence vs sqflite — keep both, different roles:**

Firestore has built-in offline persistence (enabled by default on Android/iOS, 40 MB cache). It handles read-through caching and queued writes automatically. This eliminates the need for the `SyncService` upload-queue pattern for Firestore-managed data.

However, sqflite is still justified for:
- **Fast, synchronous local reads** without going through Firestore's async snapshot API
- **The existing sync queue** for data that hasn't been migrated yet during the phased rollout
- **Complex local aggregations** (balance calculations) that are expensive to recompute from Firestore streams on every UI frame
- **Migration buffer** — during the Supabase → Firestore cutover, sqflite is the safety net

The existing `OfflineRepository → CacheService → SyncService` pipeline stays for sqflite-managed local state. The Firestore SDK owns its own offline cache independently. These do not conflict.

**Do NOT replace sqflite with only Firestore's offline cache.** Firestore's cache is read-only (you can't query it independently without network) and limited to 40 MB by default. For this app's read-heavy financial calculations and offline-first mandate, the hybrid approach is correct.

Configure Firestore offline cache explicitly:
```dart
FirebaseFirestore.instance.settings = const Settings(
  persistenceEnabled: true,
  cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
);
```
Call this before any other Firestore operation, immediately after `Firebase.initializeApp()`.

**Confidence:** HIGH for hybrid approach rationale. HIGH for Firestore settings API (verified from firebase.flutter.dev official docs).

---

### Financial Precision

| Technology | Recommended Version | Purpose | Why |
|------------|--------------------|---------|----|
| `decimal` | `^3.2.4` (current) | Arbitrary-precision arithmetic | Keep as-is. All OMR amounts stored as strings in Firestore (e.g., `"10.500"`), deserialized to `Decimal` in the app. Never use Firestore's `num` type for money. |

**Firestore serialization for money — store as String, not double:**

Firestore's native number type is a 64-bit IEEE 754 double. Storing OMR amounts (3 decimal places) as doubles will cause precision loss (e.g., 10.125 stored as 10.124999... ). The correct approach:

- Serialize: `expense.amount.toString()` → stored as Firestore string field
- Deserialize: `Decimal.parse(doc.data()['amount'] as String)`

This is identical to how amounts should be handled with any JSON-based backend. No library change needed — the existing `Decimal` package handles this correctly.

**Confidence:** HIGH — IEEE 754 double precision loss is a well-documented fact, not a guess.

---

### Testing

| Technology | Recommended Version | Purpose | Why |
|------------|--------------------|---------|----|
| `fake_cloud_firestore` | `^4.1.0+1` | Firestore unit testing | Provides a full in-memory Firestore implementation. Use instead of mocking individual document/collection references. Maintains a 1-to-1 version compatibility with `cloud_firestore` — version 4.x maps to cloud_firestore 6.x. Published 2026-03-24. |
| `mocktail` | `^1.0.4` (current) | Non-Firestore mocking | Keep for mocking `firebase_auth`, services, notifiers. |
| `firebase_auth_mocks` | `^0.14.0` | firebase_auth mocking | Provides `MockFirebaseAuth` for testing anonymous sign-in flows. Use alongside `fake_cloud_firestore`. |

**Testing strategy for Firestore:**

Do NOT mock `FirebaseFirestore.instance` directly. The class has too many internal collaborators. Instead:
1. Inject `FirebaseFirestore` as a constructor parameter into repositories/services
2. In tests, pass `FakeFirebaseFirestore()` — it behaves like real Firestore including streams, transactions, and batch writes
3. Wrap each test with a fresh `FakeFirebaseFirestore()` instance — it does not persist between tests

**Confidence:** MEDIUM for `firebase_auth_mocks` version (verified pub.dev exists, version checked but may have minor patch updates). HIGH for `fake_cloud_firestore` (version table explicitly confirmed on pub.dev page).

---

### Navigation

| Technology | Recommended Version | Purpose | Why |
|------------|--------------------|---------|----|
| `go_router` | `^17.1.0` | Top-level routing | Upgrade from current `^13.2.0`. GoRouter 17.x is the current stable. Major version bumps in GoRouter are generally non-breaking for standard route definitions. The groups layer adds new top-level routes (`/groups`, `/groups/:id`, `/groups/:id/events/:eventId`) that fit GoRouter's declarative model. |

**Note on Navigator.push:** The existing pattern of using `Navigator.push` for CommandCenter and sub-feature screens is intentional and documented in CLAUDE.md. Keep it. GoRouter handles deep links and the groups/events top-level shell. Navigator.push handles the per-event module navigation within that shell.

**Confidence:** MEDIUM — GoRouter 17.x version verified on pub.dev. Migration risk from 13.x is LOW for standard route definitions but should be validated against the existing `GoRouter` configuration.

---

### Monitoring

| Technology | Recommended Version | Purpose | Why |
|------------|--------------------|---------|----|
| `sentry_flutter` | `^9.0.0` (current) | Error tracking | No change. Sentry captures Firestore exceptions just like Supabase exceptions. The existing `SentryNavigatorObserver` works without modification. |

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Cloud DB | Firestore | Firebase Realtime Database | Less querying capability (no compound queries), less suited to the groups-of-events document model. The project context explicitly chose Firestore. |
| Cloud DB | Firestore | Keep Supabase | Supabase Realtime is cited as unreliable in the project's pain points. The migration is a stated requirement in PROJECT.md. |
| Local DB | sqflite (keep) | Replace with Firestore-only | Firestore's offline cache is 40 MB by default, read-through only, and not independently queryable. Insufficient for this app's offline-first mandate. |
| Local DB | sqflite (keep) | Migrate to Drift | Drift offers type-safe queries and code generation over sqflite, but migrating the existing sqflite schema during a Firestore migration adds unnecessary scope. Revisit in a future milestone. |
| State Mgmt | Riverpod 2.x | Riverpod 3.x | Breaking changes (unified Notifier API, `ProviderException`, equality semantics) compound risk with the Firestore migration. Separate milestone. |
| State Mgmt | Riverpod 2.x | Bloc/Cubit | No migration rationale. Riverpod is already embedded across ~100 files. |
| Auth | Firebase anonymous | Full user accounts | PROJECT.md explicitly rules this out: "Anonymous auth works, adding login adds friction." |
| Financial precision | `decimal` package | `money2` package | `money2` is a valid alternative with built-in currency handling, but migrating the precision layer during a backend migration is unwarranted risk. The existing `decimal` package is correct. |
| Testing | `fake_cloud_firestore` | Mock `FirebaseFirestore` directly | Firestore's internal API surface is too large to mock reliably. `fake_cloud_firestore` is the standard community approach. |

---

## Complete Dependency Delta

What changes in `pubspec.yaml` for this milestone:

**Add:**
```yaml
cloud_firestore: ^6.2.0
firebase_auth: ^6.3.0
firebase_storage: ^13.2.0
fake_cloud_firestore: ^4.1.0+1  # dev_dependency
firebase_auth_mocks: ^0.14.0     # dev_dependency
```

**Upgrade:**
```yaml
firebase_core: ^4.6.0      # was ^3.12.1 — mandatory for Firestore 6.x compatibility
go_router: ^17.1.0         # was ^13.2.0 — new group/event routes
```

**Remove (when Supabase migration is complete, not before):**
```yaml
supabase_flutter: ^2.3.4   # remove only after full data migration verified
```

**Keep unchanged:**
```yaml
flutter_riverpod: ^2.4.9
sqflite: ^2.4.2
decimal: ^3.2.4
firebase_messaging: ^15.2.4
sentry_flutter: ^9.0.0
# ... all other existing UI and utility packages
```

---

## Firestore Data Modeling Decisions (Affects Stack Usage)

These shape how the Firestore SDK is used.

**Groups → Events → Expenses hierarchy:**
```
/groups/{groupId}
  /members/{memberId}
  /events/{eventId}          ← was "trips" in Supabase
    /expenses/{expenseId}
    /settlements/{settlementId}
    /gear_items/{gearItemId}
    /participants/{participantId}
/group_balances/{groupId}    ← running cross-event net balances (write-time aggregation)
```

**Cross-event balance tracking** uses write-time aggregation via `FieldValue.increment` on the `/group_balances/{groupId}` document. This is the correct pattern — Firestore's `count()`, `sum()`, and `average()` aggregation queries work at read-time and do not support real-time listeners. For the group dashboard showing live running balances, write-time aggregation (update the balance document on every expense write) is the only pattern that supports real-time listeners.

**Collection group queries** (e.g., query all `expenses` subcollections across all events in a group) are available via `FirebaseFirestore.instance.collectionGroup('expenses').where('groupId', isEqualTo: groupId)`. Requires a Firestore composite index — must be created in Firebase Console or via `firestore.indexes.json` before deploying.

**Security rules** replace Supabase RLS. Group membership is checked via a `get()` call in rules:
```
allow read: if get(/databases/$(database)/documents/groups/$(groupId)/members/$(request.auth.uid)).data != null;
```
Note: Firestore rules have a hard limit of 10 `get()` operations per rule evaluation. Do not chain more than 10 membership lookups in a single rule.

---

## Sources

- [cloud_firestore pub.dev](https://pub.dev/packages/cloud_firestore) — version 6.2.0 confirmed 2026-03-24
- [firebase_auth pub.dev](https://pub.dev/packages/firebase_auth) — version 6.3.0 confirmed 2026-03-24
- [firebase_storage pub.dev](https://pub.dev/packages/firebase_storage) — version 13.2.0 confirmed 2026-03-24
- [firebase_core pub.dev](https://pub.dev/packages/firebase_core) — version 4.6.0 confirmed 2026-03-24
- [flutter_riverpod pub.dev](https://pub.dev/packages/flutter_riverpod) — version 3.3.1 is latest (stay on 2.x for this milestone)
- [fake_cloud_firestore pub.dev](https://pub.dev/packages/fake_cloud_firestore) — version 4.1.0+1, cloud_firestore 6.x compatibility confirmed
- [go_router pub.dev](https://pub.dev/packages/go_router) — version 17.1.0 confirmed
- [Riverpod 3.0 What's New](https://riverpod.dev/docs/whats_new) — breaking changes documented
- [Riverpod 2.0 to 3.0 Migration Guide](https://riverpod.dev/docs/3.0_migration)
- [FlutterFire Firestore Usage](https://firebase.flutter.dev/docs/firestore/usage/) — offline persistence config
- [Firebase Firestore Offline Docs](https://firebase.google.com/docs/firestore/manage-data/enable-offline)
- [Firebase Anonymous Auth Best Practices](https://firebase.blog/posts/2023/07/best-practices-for-anonymous-authentication/)
- [Firestore Aggregation Queries](https://firebase.google.com/docs/firestore/query-data/aggregation-queries)
- [Firestore Write-time Aggregations](https://firebase.google.com/docs/firestore/solutions/aggregation)
- [Firestore Group-based Security Rules](https://medium.com/firebase-developers/patterns-for-security-with-firebase-group-based-permissions-for-cloud-firestore-72859cdec8f6)
- [Firestore Secure Role-based Access](https://firebase.google.com/docs/firestore/solutions/role-based-access)
