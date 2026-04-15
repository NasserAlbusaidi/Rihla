---
phase: quick-260415-ers
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/core/config/firebase_config.dart
  - lib/core/services/local_database.dart
  - lib/core/providers/connectivity_provider.dart
  - lib/features/home/screens/home_screen.dart
autonomous: true
---

<objective>
Fix 4 auth/infrastructure bugs from .planning/review/04-auth-infrastructure.md (Bugs 4, 20, 23, 24).

Purpose: Prevent silent auth failures, database init hangs, wasteful background reads, and GoRouter bypasses.
Output: 4 files patched with proper error propagation, completer safety, lifecycle-aware timers, and GoRouter navigation.
</objective>

<context>
@.planning/review/04-auth-infrastructure.md
@lib/core/config/firebase_config.dart
@lib/core/services/local_database.dart
@lib/core/providers/connectivity_provider.dart
@lib/features/home/screens/home_screen.dart
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix silent auth failure, database init hang, and connectivity timer</name>
  <files>lib/core/config/firebase_config.dart, lib/core/services/local_database.dart, lib/core/providers/connectivity_provider.dart</files>
  <action>
**Bug 4 — Silent auth failure (firebase_config.dart:51-58):**

The catch block at line 55 only calls `log()` which is gated behind `kDebugMode`. In production, auth failure is completely silent and the app continues with `currentUser == null`.

Fix: Rethrow the exception after logging so the caller (main.dart) can handle it. Change:

```dart
    } on FirebaseAuthException catch (e) {
      log('Firebase anonymous sign-in failed: ${e.code} — ${e.message}',
          error: e);
    }
```

To:

```dart
    } on FirebaseAuthException catch (e) {
      log('Firebase anonymous sign-in failed: ${e.code} — ${e.message}',
          error: e);
      rethrow;
    }
```

**Bug 20 — Database init hang (local_database.dart:14-21):**

If `_initDatabase()` throws, the Completer is never completed — all callers hang forever. Also `close()` doesn't reset the completer, so after close+reopen, the stale completer returns the closed database.

Fix the `database` getter:

```dart
  static Future<Database> get database async {
    if (_database != null) return _database!;
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<Database>();
    try {
      _database = await _initDatabase();
      _initCompleter!.complete(_database!);
    } catch (e, st) {
      _initCompleter!.completeError(e, st);
      _initCompleter = null; // Allow retry on next access
      rethrow;
    }
    return _database!;
  }
```

Fix `close()` to reset the completer:

```dart
  static Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
      _initCompleter = null;
    }
  }
```

**Bug 23 — Connectivity stale comment + background timer (connectivity_provider.dart):**

Fix the stale doc comment on `_isOnline` (line 42-44). The comment says "publicly readable per security rules" which is no longer true after security hardening. Update to reflect auth requirement.

Add `WidgetsBindingObserver` to pause the timer when app is backgrounded. Change the class to mix in `WidgetsBindingObserver`:

Add `import 'package:flutter/widgets.dart';` (for WidgetsBinding and AppLifecycleState).

In the constructor, register as observer. In dispose, unregister. Add `didChangeAppLifecycleState` override to pause/resume timer.
  </action>
  <verify>
    <automated>cd /Users/nasseralbusaidi/Desktop/Personal/Rihla && flutter analyze lib/core/config/firebase_config.dart lib/core/services/local_database.dart lib/core/providers/connectivity_provider.dart 2>&1 | tail -5</automated>
  </verify>
  <done>
    - ensureAnonymousSession rethrows FirebaseAuthException after logging
    - Database completer completes with error on init failure, resets for retry
    - close() resets _initCompleter
    - Connectivity timer pauses when backgrounded, resumes when foregrounded
    - Stale "publicly readable" comment updated
  </done>
</task>

<task type="auto">
  <name>Task 2: Replace OpenContainer with GoRouter navigation</name>
  <files>lib/features/home/screens/home_screen.dart</files>
  <action>
**Bug 24 — OpenContainer bypasses GoRouter (home_screen.dart:204-228):**

Replace the OpenContainer wrapper around GroupCard with standard GoRouter navigation. The current code at line 204 uses `OpenContainer<void>` which creates a route outside GoRouter's management.

Replace the OpenContainer block (lines 204-227) with:

```dart
child: GroupCard(
  group: group,
  onTap: () => context.push('/group/${group.id}'),
),
```

Check if `OpenContainer` / `animations` package import is used elsewhere in this file. If not, remove the `import 'package:animations/animations.dart';` line.

Also check if `GroupDetailScreen` import is still needed — it was only used as the `openBuilder` target. If not used elsewhere in the file, remove its import.
  </action>
  <verify>
    <automated>cd /Users/nasseralbusaidi/Desktop/Personal/Rihla && flutter analyze lib/features/home/screens/home_screen.dart 2>&1 | tail -5</automated>
  </verify>
  <done>
    - OpenContainer replaced with context.push GoRouter navigation
    - Unused animations import removed if applicable
    - GroupDetailScreen import removed if no longer needed
    - All navigation goes through GoRouter for deep link support
  </done>
</task>

</tasks>

<verification>
```bash
cd /Users/nasseralbusaidi/Desktop/Personal/Rihla && flutter analyze lib/core/ lib/features/home/screens/home_screen.dart 2>&1 | tail -10
```

```bash
cd /Users/nasseralbusaidi/Desktop/Personal/Rihla && flutter test test/ 2>&1 | tail -5
```
</verification>
