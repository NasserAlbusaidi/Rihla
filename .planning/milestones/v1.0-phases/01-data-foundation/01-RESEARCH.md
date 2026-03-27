# Phase 1: Data Foundation - Research

**Researched:** 2026-03-26
**Domain:** Flutter + Firebase (Firestore, Auth) — dependency upgrade, emulator setup, SQLite migration, money serialization
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Money Serialization**
- D-01: Store monetary values as integer subunits in Firestore (fils for OMR, cents for USD/EUR, units for JPY). No doubles, no strings.
- D-02: Currency-aware scaling: OMR = 1000x, USD/EUR = 100x, JPY = 1x. The serializer takes currency code into account.
- D-03: Each expense/settlement document carries its own `{amount_fils: int, currency: String}` pair. Self-describing, not inherited from parent.
- D-04: `Decimal` package remains for all client-side math. Conversion to/from subunits happens at the Firestore boundary only.

**Auth Transition**
- D-05: Dual auth in Phase 1. Both Supabase and Firebase anonymous sessions active. Existing features keep talking to Supabase. Firebase auth is initialized and ready for Phase 2 group features.
- D-06: `main.dart` bootstrap becomes: Sentry → Firebase (already there) → Firebase anonymous auth → Supabase init → Supabase anonymous session → SharedPreferences → runApp.
- D-07: Firebase anonymous auth uses `FirebaseAuth.instance.signInAnonymously()` if no current user. Same silent pattern as Supabase.

**Firestore Emulator**
- D-08: Firebase Emulator configured for Firestore + Auth. Project root gets a `firebase.json` with emulator config.
- D-09: Security rule tests use the official JS `@firebase/rules-unit-testing` SDK for accurate rule validation. Separate from Dart tests.
- D-10: Dart tests use `fake_cloud_firestore` for unit/integration tests. No emulator dependency for CI speed.
- D-11: Both test ecosystems must pass: JS rule tests verify security, Dart tests verify app logic.

**SQLite Schema Extension**
- D-12: SQLite version bumps to 6. New tables: `groups`, `group_members`, `group_ledger`. Added in `_onUpgrade` migration.
- D-13: Existing tables untouched in this phase. No renaming trips→events yet (that's Phase 3).

**Firestore Security Rules**
- D-14: Group membership checked via `memberIds` array field on the group document. Rules use `.hasAny([request.auth.uid])` for O(1) lookup.
- D-15: Rules deployed to the emulator first. Never deployed to production without passing JS rule tests.

### Claude's Discretion
- Money serializer implementation pattern (utility class vs extension vs repository-internal)
- FirebaseConfig wrapper class design (mirror SupabaseConfig or lighter approach)
- Emulator startup approach (script vs test-integrated)
- Exact SQLite table schemas for groups/group_members/group_ledger
- Firebase package version pinning strategy

### Deferred Ideas (OUT OF SCOPE)
- Renaming `trips` table to `events` in SQLite — Phase 3
- FirestoreRepository class — Phase 4 (this phase only sets up Firestore, doesn't migrate writes)
- Removing SupabaseConfig — Phase 7
- GoRouter upgrade — Phase 2 when adding group routes
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DATA-01 | All monetary values stored as integer fils (not doubles) in Firestore, with Decimal conversion at the boundary | MoneySerializer pattern, integer subunit strategy, currency-aware scaling |
| DATA-02 | Firestore security rules enforce group membership via `memberIds` map on group document | `memberIds` array approach, `in` operator rules syntax, rules_version 2 |
| DATA-03 | Firebase Emulator configured for local development and security rule testing | firebase.json structure, emulator port config, `@firebase/rules-unit-testing` ^5.0.0 |
| DATA-04 | SQLite schema extended with `groups`, `group_members`, `group_ledger` tables | `_databaseVersion` bump to 6, `_onUpgrade` pattern from existing code |
| DATA-05 | Firebase anonymous auth replaces Supabase anonymous auth with same frictionless UX | `FirebaseAuth.instance.signInAnonymously()`, currentUser check, UID persistence |
| DATA-06 | `firebase_core` bumped to 4.6.0+, all Firebase dependencies updated | Verified pub.dev versions, pubspec.yaml delta |
| TST-03 | Integration tests using `fake_cloud_firestore` — no real Firebase calls in tests | `FakeFirebaseFirestore`, injection pattern, `firebase_auth_mocks` |
| TST-04 | Firestore security rules tested via Firebase Emulator | JS test setup, `initializeTestEnvironment`, rule assertion patterns |
</phase_requirements>

---

## Summary

Phase 1 is a pure infrastructure phase with zero UI deliverables. It establishes four independent pillars: (1) Firebase package upgrade and Firestore initialization, (2) Firebase anonymous auth running in parallel with the existing Supabase session, (3) a `MoneySerializer` utility that enforces integer subunit storage at the Firestore boundary, and (4) a SQLite schema migration to version 6 adding three new tables.

The phase is gated on one non-negotiable: the money serialization pattern must be implemented and tested before any Firestore write ever happens. The IEEE 754 double-precision pitfall is well-documented and cannot be patched retroactively once financial data is in production. Everything else in this phase builds toward enabling Phase 2's group creation features.

The existing codebase already has Firebase initialized (`firebase_options.dart` exists, `firebase_core ^3.12.1` in pubspec). The upgrade path is additive — bump `firebase_core` to `^4.6.0`, add `cloud_firestore` and `firebase_auth`, configure settings before first use. The Supabase dependency remains untouched in this phase.

**Primary recommendation:** Implement MoneySerializer first as a standalone, fully-tested Dart class. Everything else depends on it being correct. The emulator and security rules can be set up in parallel by a separate task since they have no code dependencies on each other.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `firebase_core` | `^4.6.0` | Firebase app initialization | Mandatory upgrade — cloud_firestore 6.x requires firebase_core 4.x. Current in repo is `^3.12.1` (resolves to 3.15.2). |
| `cloud_firestore` | `^6.2.0` | Primary cloud database (Phase 1: init + rules only) | Latest stable, pub.dev confirmed 2026-03-24. Provides offline persistence, listeners, and the Firestore SDK for auth UID validation in rules. |
| `firebase_auth` | `^6.3.0` | Anonymous authentication | Replaces Supabase `signInAnonymously()`. pub.dev confirmed 2026-03-24. |
| `firebase_messaging` | `^15.2.4` | Push notifications (already active) | No version change — compatible with firebase_core 4.x. Currently resolves to 15.2.10. |

**Important version note:** `dart pub outdated` run on this repo today shows the current resolved version is `firebase_core 3.15.2`. The upgrade to `^4.6.0` is the critical blocker — without it, `cloud_firestore ^6.2.0` cannot be added.

### Supporting (Dev Dependencies)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `fake_cloud_firestore` | `^4.1.0+1` | In-memory Firestore for Dart tests | All Dart unit/integration tests that write or read Firestore data. pub.dev confirmed 2026-03-24. |
| `firebase_auth_mocks` | `^0.14.0` | `MockFirebaseAuth` for auth testing | Tests that exercise anonymous sign-in flow or need a `FirebaseAuth` instance |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Integer subunits for money | String representation (e.g., `"10.500"`) | CONTEXT.md locked to integer subunits (D-01). Strings require parsing and sort lexicographically wrong. Integers are native Firestore type with correct ordering. |
| `memberIds` array on group doc | Subcollection `get()` for membership | D-14 locked to array field. Array approach avoids cross-document `get()` in rules — O(1) vs 1 read credit per security rule eval. |
| `fake_cloud_firestore` | Real emulator for Dart tests | D-10 locked to fake. Emulator requires network, not CI-friendly. `fake_cloud_firestore` is faster and deterministic. |

**Installation (pubspec.yaml changes):**

```yaml
# Under dependencies: — upgrade
firebase_core: ^4.6.0        # was ^3.12.1

# Under dependencies: — add new
cloud_firestore: ^6.2.0
firebase_auth: ^6.3.0

# Under dev_dependencies: — add new
fake_cloud_firestore: ^4.1.0+1
firebase_auth_mocks: ^0.14.0
```

**Version verification:** Versions above verified against pub.dev on 2026-03-24 to 2026-03-26. `cloud_firestore 6.2.0` published 2026-03-24. `fake_cloud_firestore 4.1.0+1` published 2026-03-24. `firebase_auth 6.3.0` published 2026-03-24.

**After editing pubspec.yaml:**
```bash
flutter pub get
```

---

## Architecture Patterns

### Recommended Project Structure (new files only)

```
lib/
├── core/
│   ├── config/
│   │   ├── supabase_config.dart     # existing — untouched
│   │   └── firebase_config.dart     # NEW: mirrors SupabaseConfig pattern
│   ├── services/
│   │   ├── local_database.dart      # existing — extend _onUpgrade to v6
│   │   └── money_serializer.dart    # NEW: Decimal ↔ integer subunits
│   └── providers/
│       └── firebase_auth_provider.dart  # NEW: Firebase auth state providers
test/
├── unit/
│   └── money_serializer_test.dart   # NEW: round-trip precision tests
└── integration/
    └── firebase_auth_test.dart      # NEW: anonymous sign-in test with mock
security/
└── firestore.rules                  # NEW: group membership rules
firebase.json                        # NEW: emulator config
.firebaserc                          # NEW: project alias
test_rules/
└── firestore.test.js                # NEW: JS security rule tests
```

### Pattern 1: FirebaseConfig Wrapper (mirror of SupabaseConfig)

**What:** A static class that owns Firebase initialization, anonymous auth, and auth state stream — mirroring the existing `SupabaseConfig` pattern exactly.

**When to use:** Called from `main.dart` bootstrap, replacing the direct `Firebase.initializeApp()` call.

**Example:**
```dart
// lib/core/config/firebase_config.dart
import 'dart:developer' as dev;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../firebase_options.dart';

class FirebaseConfig {
  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;

  static Future<void> initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Configure Firestore offline persistence immediately after init
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    log('Firebase initialized with Firestore offline persistence');
  }

  static Future<void> ensureAnonymousSession() async {
    if (auth.currentUser != null) {
      log('Firebase session already active: ${auth.currentUser!.uid}');
      return;
    }
    log('No Firebase user — signing in anonymously');
    await auth.signInAnonymously();
    log('Firebase anonymous session established: ${auth.currentUser!.uid}');
  }

  static User? get currentUser => auth.currentUser;
  static bool get isAuthenticated => currentUser != null;
  static Stream<User?> get authStateChanges => auth.authStateChanges();

  static void log(String message, {Object? error, StackTrace? stackTrace}) {
    if (!kDebugMode) return;
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    dev.log('[$timestamp] $message', name: 'Firebase');
    if (error != null) {
      dev.log('[$timestamp] Error: $error', name: 'Firebase');
      if (stackTrace != null) dev.log('Stack: $stackTrace', name: 'Firebase');
    }
  }
}
```

### Pattern 2: main.dart Bootstrap Order (D-06)

**What:** Insert Firebase anonymous auth between `Firebase.initializeApp()` and `SupabaseConfig.initialize()`. Remove the bare `Firebase.initializeApp()` call and replace with `FirebaseConfig.initialize()`.

**Example:**
```dart
// lib/main.dart — updated bootstrap inside SentryFlutter.init appRunner
appRunner: () async {
  // 1. Firebase init + Firestore settings
  await FirebaseConfig.initialize();

  // 2. Firebase anonymous auth (new — D-06, D-07)
  await FirebaseConfig.ensureAnonymousSession();

  // 3. Supabase (unchanged — dual auth, D-05)
  await SupabaseConfig.initialize();
  await SupabaseConfig.ensureAnonymousSession();

  // 4. SharedPreferences (unchanged)
  final prefs = await SharedPreferences.getInstance();

  // ... SystemChrome, runApp unchanged
}
```

### Pattern 3: MoneySerializer (D-01, D-02, D-03, D-04)

**What:** A pure Dart utility class with no external dependencies. Converts `Decimal` to integer subunits and back, currency-aware. Lives at the Firestore boundary — called only when reading from or writing to Firestore documents.

**When to use:** Every Firestore document write of a monetary field. Every Firestore document read that deserializes a monetary field. Never called in `BalanceCalculator` or any other internal math.

```dart
// lib/core/services/money_serializer.dart
import 'package:decimal/decimal.dart';

/// Converts Decimal amounts to/from integer subunits for Firestore storage.
/// OMR uses 1000 subunits (fils). USD/EUR use 100 (cents). JPY uses 1 (units).
///
/// ONLY call at the Firestore read/write boundary. All internal math uses Decimal.
class MoneySerializer {
  static const Map<String, int> _currencyScale = {
    'OMR': 1000,
    'USD': 100,
    'EUR': 100,
    'GBP': 100,
    'SAR': 100,
    'AED': 100,
    'JPY': 1,
    'KWD': 1000,
    'BHD': 1000,
    'QAR': 100,
  };

  /// Convert a Decimal amount to integer subunits for Firestore storage.
  /// e.g. OMR 10.500 → 10500, USD 9.99 → 999
  static int toSubunits(Decimal amount, String currency) {
    final scale = _scale(currency);
    return (amount * Decimal.fromInt(scale)).toBigInt().toInt();
  }

  /// Convert integer subunits from Firestore to a Decimal amount.
  /// e.g. OMR: 10500 → Decimal('10.500'), USD: 999 → Decimal('9.99')
  static Decimal fromSubunits(int subunits, String currency) {
    final scale = _scale(currency);
    return Decimal.fromInt(subunits) / Decimal.fromInt(scale);
  }

  static int _scale(String currency) {
    final scale = _currencyScale[currency.toUpperCase()];
    if (scale == null) {
      throw ArgumentError('Unsupported currency: $currency');
    }
    return scale;
  }
}
```

**Test requirement (DATA-01 success criteria):**
```dart
// test/unit/money_serializer_test.dart
test('OMR round-trip preserves exact Decimal value', () {
  final amount = Decimal.parse('10.500');
  final subunits = MoneySerializer.toSubunits(amount, 'OMR');
  expect(subunits, equals(10500));
  final restored = MoneySerializer.fromSubunits(subunits, 'OMR');
  expect(restored, equals(amount));
});
```

### Pattern 4: SQLite Migration to Version 6 (D-12, D-13)

**What:** Extend `LocalDatabase._onUpgrade` with an `oldVersion < 6` branch. Bump `_databaseVersion` from 5 to 6. New tables: `groups`, `group_members`, `group_ledger`. Existing tables untouched.

**When to use:** `_onUpgrade` is called automatically by sqflite on first launch after version bump. Fresh installs go through `_onCreate` — add new tables there too.

```dart
// lib/core/services/local_database.dart — changes only
static const int _databaseVersion = 6; // was 5

// In _onCreate — add after existing CREATE TABLE statements:
await db.execute('''
  CREATE TABLE groups (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    invite_code TEXT NOT NULL,
    created_by TEXT NOT NULL,
    member_ids TEXT NOT NULL DEFAULT '[]',
    currency TEXT DEFAULT 'OMR',
    created_at TEXT NOT NULL,
    updated_at TEXT,
    synced_at TEXT
  )
''');

await db.execute('''
  CREATE TABLE group_members (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL,
    user_id TEXT,
    display_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'MEMBER',
    is_shadow INTEGER NOT NULL DEFAULT 0,
    joined_at TEXT NOT NULL,
    synced_at TEXT,
    FOREIGN KEY (group_id) REFERENCES groups (id) ON DELETE CASCADE
  )
''');

await db.execute('''
  CREATE TABLE group_ledger (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    counterparty_id TEXT NOT NULL,
    net_amount_subunits INTEGER NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'OMR',
    last_updated_at TEXT NOT NULL,
    event_id TEXT,
    synced_at TEXT,
    FOREIGN KEY (group_id) REFERENCES groups (id) ON DELETE CASCADE
  )
''');

await db.execute('CREATE INDEX idx_groups_invite ON groups(invite_code)');
await db.execute('CREATE INDEX idx_group_members_group ON group_members(group_id)');
await db.execute('CREATE INDEX idx_group_ledger_group ON group_ledger(group_id)');
await db.execute('CREATE INDEX idx_group_ledger_pair ON group_ledger(group_id, member_id, counterparty_id)');

// In _onUpgrade — add at end, after oldVersion < 5 block:
if (oldVersion < 6) {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS groups (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      invite_code TEXT NOT NULL,
      created_by TEXT NOT NULL,
      member_ids TEXT NOT NULL DEFAULT '[]',
      currency TEXT DEFAULT 'OMR',
      created_at TEXT NOT NULL,
      updated_at TEXT,
      synced_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS group_members (
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL,
      user_id TEXT,
      display_name TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'MEMBER',
      is_shadow INTEGER NOT NULL DEFAULT 0,
      joined_at TEXT NOT NULL,
      synced_at TEXT,
      FOREIGN KEY (group_id) REFERENCES groups (id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS group_ledger (
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL,
      member_id TEXT NOT NULL,
      counterparty_id TEXT NOT NULL,
      net_amount_subunits INTEGER NOT NULL DEFAULT 0,
      currency TEXT NOT NULL DEFAULT 'OMR',
      last_updated_at TEXT NOT NULL,
      event_id TEXT,
      synced_at TEXT,
      FOREIGN KEY (group_id) REFERENCES groups (id) ON DELETE CASCADE
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_groups_invite ON groups(invite_code)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_group_ledger_group ON group_ledger(group_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_group_ledger_pair ON group_ledger(group_id, member_id, counterparty_id)',
  );
}
```

**Schema design rationale:**
- `member_ids` stored as JSON string (TEXT column) on `groups` — mirrors the Firestore `memberIds` array for fast membership checks without a join. Updated atomically when group_members changes.
- `net_amount_subunits` stored as INTEGER in `group_ledger` — consistent with the integer subunit decision for Firestore. No precision loss in SQLite either.
- `group_ledger` indexes on `(group_id, member_id, counterparty_id)` — the group balance screen queries by group_id and resolves specific pairs.

### Pattern 5: Firebase Emulator Configuration (D-08, D-09)

**What:** `firebase.json` at project root configures Firestore and Auth emulators. A separate `test_rules/` directory holds the JS test suite using `@firebase/rules-unit-testing ^5.0.0`.

**firebase.json:**
```json
{
  "firestore": {
    "rules": "security/firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "emulators": {
    "auth": {
      "port": 9099
    },
    "firestore": {
      "port": 8080
    },
    "ui": {
      "enabled": true,
      "port": 4000
    }
  }
}
```

**package.json for JS rule tests (test_rules/package.json):**
```json
{
  "name": "rihla-security-rule-tests",
  "type": "module",
  "scripts": {
    "test": "node --experimental-vm-modules node_modules/.bin/jest"
  },
  "devDependencies": {
    "@firebase/rules-unit-testing": "^5.0.0",
    "firebase-admin": "^13.0.0",
    "jest": "^29.0.0"
  }
}
```

**Run security rule tests:**
```bash
# Start emulators in background
firebase emulators:start --only firestore,auth &

# Run JS rule tests
cd test_rules && npm test
```

### Pattern 6: Firestore Security Rules — Group Membership (D-14, D-15)

**What:** `firestore.rules` using `rules_version = '2'` with membership checked via `memberIds` array on the group document. No cross-document `get()` for the group document itself.

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Public: invite code lookup
    match /inviteCodes/{code} {
      allow read: if true;
      allow write: if request.auth != null;
    }

    match /groups/{groupId} {
      // In-document membership check — no get() call needed
      function isMember() {
        return request.auth != null &&
               request.auth.uid in resource.data.memberIds;
      }

      function isValidGroupCreate() {
        return request.auth != null &&
               request.resource.data.name is string &&
               request.resource.data.name.size() > 0 &&
               request.resource.data.memberIds is list &&
               request.resource.data.currency is string;
      }

      allow read: if isMember();
      allow create: if isValidGroupCreate();
      allow update: if isMember();
      allow delete: if false;

      // Subcollections — ONE get() call to parent for membership
      match /{subcollection}/{docId} {
        function isGroupMember() {
          return request.auth != null &&
            request.auth.uid in
              get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds;
        }
        allow read, write: if isGroupMember();
      }
    }
  }
}
```

### Anti-Patterns to Avoid

- **Storing Firestore amount as double:** Never call `.toDouble()` on a `Decimal`. Always go through `MoneySerializer.toSubunits()`. One bad call corrupts financial history permanently.
- **Calling `Firebase.initializeApp()` twice:** The existing `main.dart` already calls it. Replace the bare call with `FirebaseConfig.initialize()` — do not add a second `initializeApp`.
- **Setting Firestore settings after first use:** `FirebaseFirestore.instance.settings = ...` must be called before any Firestore read or write. If placed after any other Firestore call, it throws `Firestore has already been used`.
- **Skipping the `oldVersion < 6` guard in `_onUpgrade`:** Existing users have database version 5. Without the guard, the migration runs for all upgrades and will fail with "table already exists" errors.
- **Using `try/catch` to swallow `CREATE TABLE` errors in v6 migration:** Use `CREATE TABLE IF NOT EXISTS` instead (as established in v4 migration). Silent failures hide schema bugs.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Firestore in-memory testing | Custom Firestore mock | `fake_cloud_firestore ^4.1.0+1` | Firestore has too many internal collaborators to mock reliably; fake covers streams, transactions, batch writes |
| Firebase Auth mock | `MockFirebaseAuth` from scratch | `firebase_auth_mocks ^0.14.0` | Provides `MockFirebaseAuth` with pre-built `signInAnonymously()` simulation |
| Security rule testing | Custom rule parser | `@firebase/rules-unit-testing ^5.0.0` + emulator | Rules evaluation requires actual Firestore rule engine — only the emulator runs them correctly |
| Offline write queue | Custom retry/queue mechanism | Firestore SDK offline persistence | SDK handles write queuing, exponential backoff, and deduplication automatically |
| Money precision | Custom decimal storage | `decimal ^3.2.4` (already in project) + `MoneySerializer` | Decimal handles arbitrary precision; serializer is a thin boundary — don't add another library |

**Key insight:** The test infrastructure (fake + mocks) is where the most value from "don't hand-roll" applies. Firestore's internal API surface is too large to mock correctly by hand — every class that appears to be mockable has package-private state that will throw in tests.

---

## Common Pitfalls

### Pitfall 1: `firebase_core` Version Conflict Blocks `flutter pub get`

**What goes wrong:** Adding `cloud_firestore: ^6.2.0` to pubspec while `firebase_core` remains at `^3.12.1` causes a version conflict. `flutter pub get` fails with a dependency resolution error. The resolver cannot find a version of `cloud_firestore` that satisfies both `firebase_core ^3.x` and `cloud_firestore ^6.x`.

**Why it happens:** FlutterFire packages use strict cross-package version constraints. `cloud_firestore 6.x` requires `firebase_core ^4.6.0`. The packages are released together in lock-step.

**How to avoid:** Bump `firebase_core` to `^4.6.0` in the same pubspec edit that adds `cloud_firestore`. The two changes must be atomic. Also bump `firebase_messaging` — current `^15.2.4` resolves to 15.2.10 which needs to be verified against `firebase_core 4.x` compatibility.

**Warning signs:** `flutter pub get` outputs "Because X depends on firebase_core ^3.x and Y depends on firebase_core ^4.x, version solving failed."

### Pitfall 2: Firestore Settings Set After First Use Throws Unrecoverable Error

**What goes wrong:** `FirebaseFirestore.instance.settings = const Settings(...)` throws `FirebaseException: Firestore has already been used` if any Firestore read or listener was already active.

**Why it happens:** The existing `firebase_options.dart` and FCM setup have already called `Firebase.initializeApp()`. If anything in the app touches Firestore before `FirebaseConfig.initialize()` completes, the settings assignment fails.

**How to avoid:** Call `FirebaseFirestore.instance.settings = ...` immediately inside `FirebaseConfig.initialize()`, before returning. Ensure `FirebaseConfig.initialize()` is the first thing called after `WidgetsFlutterBinding.ensureInitialized()` in the Sentry appRunner.

**Warning signs:** Runtime crash on startup: `PlatformException: Firestore has already been used to make requests, so it cannot be modified.`

### Pitfall 3: SQLite `_onUpgrade` Runs When Already at Version 6

**What goes wrong:** If a device is already at version 5 and upgrades to 6, `_onUpgrade(db, 5, 6)` runs. But if someone later ships version 7, `_onUpgrade(db, 5, 7)` would run the `oldVersion < 6` block AND the `oldVersion < 7` block. This is correct. The risk is that the existing `try/catch` pattern (used in v4 migration for `sync_queue` columns) masks silently failing SQL.

**Why it happens:** The v4 migration used `try/catch` around `ALTER TABLE` because columns may already exist from v1 `_onCreate`. For the v6 new tables there is no such risk — use `CREATE TABLE IF NOT EXISTS` to be safe, not `try/catch`.

**How to avoid:** Use `CREATE TABLE IF NOT EXISTS` and `CREATE INDEX IF NOT EXISTS` in all v6 migration DDL. Never use `try/catch` to swallow schema errors.

**Warning signs:** App opens without error but `groups` table doesn't exist — inserts silently fail with "no such table".

### Pitfall 4: Firebase Anonymous Auth UID Changes on App Reinstall

**What goes wrong:** A user reinstalls the app. Their Firebase anonymous UID is gone (device keychain wiped). Firebase creates a new UID on `signInAnonymously()`. The new UID has no data associated with it.

**Why it happens:** Anonymous auth UIDs are stored in the device keychain/Keystore. Uninstall wipes this. This is the same limitation as the existing Supabase anonymous auth.

**How to avoid:** This is a known limitation documented in the project. Phase 1 does not solve it — the recovery path (join via group invite code) is the mitigation designed for Phase 2. Phase 1's job is to make anonymous auth work, not to solve UID persistence.

**Warning signs:** Users report "my data is gone after reinstall" — expected behavior with anonymous auth.

### Pitfall 5: Dual Auth Sessions Create Conflicting UIDs in Logs

**What goes wrong:** Both Firebase and Supabase create anonymous UIDs. `FirebaseConfig.log()` shows a Firebase UID. `SupabaseConfig.log()` shows a different Supabase UUID. Debugging gets confusing — log lines from different systems reference different user identifiers for the same person.

**Why it happens:** The dual-auth design deliberately runs two independent anonymous auth sessions (D-05). The UIDs will never match.

**How to avoid:** In logging, always prefix the system — `Firebase UID: ${firebaseUid}` vs `Supabase UID: ${supabaseUid}`. Do not mix UID references. Existing Supabase code uses Supabase UIDs for RLS — do not replace them with Firebase UIDs yet (that's Phase 4+).

**Warning signs:** Auth-related bugs in Phase 2 where Firebase group membership check uses the Supabase UID by mistake.

### Pitfall 6: Security Rule `in` Operator Requires `memberIds` to Be a List, Not a Map

**What goes wrong:** CONTEXT.md D-14 specifies `memberIds` as an array field. ARCHITECTURE.md describes it as a map (`members: { uid: role }`). STATE.md also mentions map. The decision was consolidated to array in D-14. Using `request.auth.uid in resource.data.memberIds` requires `memberIds` to be a Firestore array (list). If it's stored as a map, the `in` operator tests key membership in a list, not a map — the rule silently evaluates to `false`.

**Why it happens:** CONTEXT.md D-14 is the locked decision: `memberIds` is an array. This was chosen specifically for the `in` operator in security rules. The architecture doc's `members: map` design is for Phase 4+ with role data — Phase 1 uses the simpler array.

**How to avoid:** In Phase 1, the group document uses `memberIds: string[]` (Firebase UIDs as an array). When writing group documents to Firestore in Phase 2, populate this field as a Dart `List<String>`. Security rules test must assert this works.

**Warning signs:** All reads to group documents are denied with "Permission denied" — rule evaluation of `request.auth.uid in resource.data.memberIds` returns false because `memberIds` was stored as a map.

---

## Code Examples

Verified patterns from existing codebase and official Firebase Flutter docs.

### Firestore Offline Persistence Configuration

```dart
// Source: https://firebase.flutter.dev/docs/firestore/usage/
// Call immediately after Firebase.initializeApp() — before any other Firestore use
FirebaseFirestore.instance.settings = const Settings(
  persistenceEnabled: true,
  cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
);
```

### Firebase Anonymous Auth (mirroring existing Supabase pattern)

```dart
// Source: https://firebase.flutter.dev/docs/auth/anonymous-auth/
// Matches SupabaseConfig.ensureAnonymousSession() pattern exactly
final currentUser = FirebaseAuth.instance.currentUser;
if (currentUser == null) {
  await FirebaseAuth.instance.signInAnonymously();
}
```

### MoneySerializer Round-Trip Pattern

```dart
// Source: project decision D-01/D-02, verified via Decimal package docs
// Firestore write:
final doc = {
  'amount_fils': MoneySerializer.toSubunits(expense.amount, expense.currency),
  'currency': expense.currency,
};
// Firestore read:
final amount = MoneySerializer.fromSubunits(
  (doc['amount_fils'] as int),
  doc['currency'] as String,
);
```

### FakeFirebaseFirestore in Dart Tests (TST-03)

```dart
// Source: https://pub.dev/packages/fake_cloud_firestore
// Inject FakeFirebaseFirestore — never use FirebaseFirestore.instance in tests
final fakeFirestore = FakeFirebaseFirestore();
await fakeFirestore.collection('groups').doc('g1').set({
  'name': 'Weekend Trip',
  'memberIds': ['uid-123'],
  'currency': 'OMR',
});
final snapshot = await fakeFirestore.collection('groups').doc('g1').get();
expect(snapshot.data()!['name'], equals('Weekend Trip'));
```

### Security Rule Test Pattern (TST-04)

```javascript
// Source: https://firebase.google.com/docs/rules/unit-tests
// test_rules/firestore.test.js
import { initializeTestEnvironment, assertFails, assertSucceeds }
  from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'safar-test',
    firestore: {
      rules: readFileSync('../security/firestore.rules', 'utf8'),
    },
  });
});

test('non-member cannot read group document', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection('groups').doc('g1').set({
      name: 'Test Group',
      memberIds: ['uid-member'],
      currency: 'OMR',
    });
  });

  const nonMember = testEnv.authenticatedContext('uid-outsider');
  await assertFails(
    nonMember.firestore().collection('groups').doc('g1').get()
  );
});

test('member can read group document', async () => {
  const member = testEnv.authenticatedContext('uid-member');
  await assertSucceeds(
    member.firestore().collection('groups').doc('g1').get()
  );
});

afterAll(async () => {
  await testEnv.cleanup();
});
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Store money as Supabase `decimal(12,3)` column | Store as integer subunits in Firestore (`amount_fils: int`) | Phase 1 of this migration | Eliminates all IEEE 754 floating-point precision risk |
| Supabase RLS via `SECURITY DEFINER` SQL function | Firestore security rules with `memberIds` array `in` operator | Phase 1 | Simpler rule logic, no stored procedures |
| `SyncService` polling Supabase for changes | Firestore SDK offline persistence + snapshot listeners | Phase 4 (not Phase 1) | SyncService kept in Phase 1 — removal is Phase 4 |
| `firebase_core: ^3.12.1` (FCM only) | `firebase_core: ^4.6.0` + Firestore + Auth | Phase 1 | Enables all cloud_firestore 6.x features |
| Manual `Firebase.initializeApp()` in main.dart | `FirebaseConfig.initialize()` wrapper | Phase 1 | Adds Firestore settings before first use |

**Deprecated/outdated in this phase's context:**
- `firebase_core ^3.x`: Incompatible with `cloud_firestore ^6.x`. Must be removed.
- The `@firebase/testing` npm package: Deprecated predecessor to `@firebase/rules-unit-testing`. Do not use it.
- `FirebaseFirestore.instance.settings.cacheSizeBytes = FirebaseFirestore.CACHE_SIZE_UNLIMITED`: Old constant name. Use `Settings.CACHE_SIZE_UNLIMITED` (verified from FlutterFire docs).

---

## Open Questions

1. **firebase_messaging version compatibility with firebase_core 4.x**
   - What we know: `firebase_messaging` is currently at `^15.2.4` (resolves to 15.2.10). The upgrade to `firebase_core ^4.6.0` may require bumping firebase_messaging.
   - What's unclear: `dart pub outdated` shows firebase_messaging 15.2.10 → latest is 16.1.3. Version 16.1.3 may require firebase_core 4.x. Need to verify during `flutter pub get` after bumping firebase_core.
   - Recommendation: When editing pubspec.yaml, also bump `firebase_messaging` to `^16.1.3` if the version resolver requires it. If 15.2.x is compatible with firebase_core 4.x, leave it.

2. **`firestore.indexes.json` initial content**
   - What we know: Phase 1 does not write any Firestore data — it only sets up the SDK, rules, and emulator. No compound queries are written in Phase 1.
   - What's unclear: Whether an empty `firestore.indexes.json` is needed now, or only when Phase 4 adds collection group queries.
   - Recommendation: Create a minimal `firestore.indexes.json` stub in Phase 1 to establish the file in the repo. Leave `indexes` and `fieldOverrides` arrays empty. Required by `firebase.json` config anyway.

3. **`firebase_auth_mocks ^0.14.0` compatibility with firebase_auth ^6.3.0**
   - What we know: STACK.md lists `firebase_auth_mocks ^0.14.0` as verified on pub.dev. The research says "version checked but may have minor patch updates."
   - What's unclear: Whether 0.14.0 is compatible with `firebase_auth ^6.3.0` specifically (0.14.x was listed for firebase_auth 5.x in older docs).
   - Recommendation: Run `flutter pub get` after adding both packages and check for version conflicts. If conflict exists, check pub.dev for the latest `firebase_auth_mocks` version that declares compatibility with `firebase_auth ^6.3.0`.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `flutter_test` (built-in) + `mocktail ^1.0.4` (existing) |
| Config file | None — standard Flutter test runner |
| Quick run command | `flutter test test/unit/money_serializer_test.dart` |
| Full suite command | `flutter test` |
| JS rule tests command | `cd test_rules && npm test` (requires emulator running) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| DATA-01 | OMR 10.500 → 10500 fils → 10.500 Decimal (exact round-trip) | unit | `flutter test test/unit/money_serializer_test.dart -x` | Wave 0 |
| DATA-01 | USD 9.99 → 999 cents → 9.99 Decimal (exact round-trip) | unit | `flutter test test/unit/money_serializer_test.dart -x` | Wave 0 |
| DATA-01 | JPY 100 → 100 units → 100 Decimal (scale=1 passthrough) | unit | `flutter test test/unit/money_serializer_test.dart -x` | Wave 0 |
| DATA-02 | Non-member cannot read group document | JS emulator | `cd test_rules && npm test` | Wave 0 |
| DATA-02 | Member can read group document | JS emulator | `cd test_rules && npm test` | Wave 0 |
| DATA-02 | Non-member cannot write subcollection | JS emulator | `cd test_rules && npm test` | Wave 0 |
| DATA-03 | Emulator starts on ports 8080 (Firestore), 9099 (Auth) | smoke | `firebase emulators:start --only firestore,auth` | Wave 0 (firebase.json) |
| DATA-04 | SQLite opens at version 6 without error (fresh install) | integration | `flutter test test/integration/local_database_migration_test.dart -x` | Wave 0 |
| DATA-04 | SQLite upgrades from version 5 to 6 with new tables present | integration | `flutter test test/integration/local_database_migration_test.dart -x` | Wave 0 |
| DATA-05 | Firebase anonymous auth completes silently on first launch | integration | `flutter test test/integration/firebase_auth_test.dart -x` | Wave 0 |
| DATA-05 | Firebase anonymous auth is idempotent (no second sign-in if session exists) | unit | `flutter test test/integration/firebase_auth_test.dart -x` | Wave 0 |
| DATA-06 | `flutter pub get` succeeds with no version conflicts | smoke | `flutter pub get` | N/A (pubspec change) |
| TST-03 | FakeFirebaseFirestore accepts a group document write without error | integration | `flutter test test/integration/firebase_auth_test.dart -x` | Wave 0 |
| TST-04 | JS rule tests pass: non-member denied, member allowed | JS emulator | `cd test_rules && npm test` | Wave 0 |

### Sampling Rate

- **Per task commit:** `flutter test test/unit/money_serializer_test.dart`
- **Per wave merge:** `flutter test`
- **Phase gate:** `flutter test` (green) + `cd test_rules && npm test` (green) before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/unit/money_serializer_test.dart` — covers DATA-01 round-trip for OMR, USD, JPY, unsupported currency exception
- [ ] `test/integration/local_database_migration_test.dart` — covers DATA-04 (fresh install v6 schema, upgrade from v5)
- [ ] `test/integration/firebase_auth_test.dart` — covers DATA-05 with `MockFirebaseAuth`, TST-03 with `FakeFirebaseFirestore`
- [ ] `test_rules/package.json` + `test_rules/firestore.test.js` — covers DATA-02, TST-04
- [ ] `security/firestore.rules` — the rules file itself (needed by both emulator and JS tests)
- [ ] `firebase.json` + `firestore.indexes.json` + `.firebaserc` — covers DATA-03 emulator config
- [ ] Install `@firebase/rules-unit-testing`: `cd test_rules && npm install`

---

## Sources

### Primary (HIGH confidence)

- pub.dev cloud_firestore — version 6.2.0, published 2026-03-24, verified publisher firebase.google.com
- pub.dev fake_cloud_firestore — version 4.1.0+1, published 2026-03-24, cloud_firestore 6.2.0 compatibility confirmed
- pub.dev firebase_auth — version 6.3.0, published 2026-03-24, verified publisher firebase.google.com
- pub.dev firebase_core — version 4.6.0, published 2026-03-24, verified publisher firebase.google.com
- [FlutterFire Firestore Usage](https://firebase.flutter.dev/docs/firestore/usage/) — `Settings` API, `CACHE_SIZE_UNLIMITED`, offline persistence
- [FlutterFire Anonymous Auth](https://firebase.flutter.dev/docs/auth/anonymous-auth/) — `signInAnonymously()` pattern
- [Firebase Rules Unit Testing](https://firebase.google.com/docs/rules/unit-tests) — `initializeTestEnvironment`, `assertFails`, `assertSucceeds`
- [Test Firestore Security Rules](https://firebase.google.com/docs/firestore/security/test-rules-emulator) — emulator-based rule testing workflow
- `.planning/research/STACK.md` — comprehensive package version and architecture research (2026-03-24)
- `.planning/research/PITFALLS.md` — documented pitfalls with citations (2026-03-24)
- `.planning/research/ARCHITECTURE.md` — Firestore collection structure, security rules patterns (2026-03-24)
- `dart pub outdated` on this repo — confirmed firebase_core resolves to 3.15.2 currently (run 2026-03-26)

### Secondary (MEDIUM confidence)

- npm search: `@firebase/rules-unit-testing ^5.0.0` — latest version confirmed via WebSearch (2026-03-26)
- `firebase --version` on project machine — firebase-tools 15.8.0 installed at `/opt/homebrew/bin/firebase`
- `pub.dev firebase_auth_mocks ^0.14.0` — version listed in STACK.md; compatibility with firebase_auth 6.3.0 flagged as open question pending `flutter pub get` validation

### Tertiary (LOW confidence)

- firebase_messaging 16.1.3 compatibility with firebase_core 4.x — inferred from FlutterFire release cadence; must be validated during `flutter pub get`

---

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — all package versions verified against pub.dev within 48 hours
- Architecture: HIGH — patterns derived from existing codebase (SupabaseConfig, LocalDatabase) and official FlutterFire docs
- Pitfalls: HIGH — critical pitfalls (double precision, settings order, dual UID confusion) all derive from documented behaviors, not speculation
- SQLite schema: MEDIUM — schema design is Claude's discretion per CONTEXT.md; `member_ids` as JSON TEXT is a design choice, not a proven pattern
- JS rule test setup: MEDIUM — `@firebase/rules-unit-testing ^5.0.0` confirmed to exist; exact Jest configuration for ESM modules may require iteration

**Research date:** 2026-03-26
**Valid until:** 2026-04-25 (stable Firebase/Flutter ecosystem — 30 days)
