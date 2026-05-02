# Remove Auth: Anonymous Device Identity — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace email/password auth with silent Supabase anonymous sign-in so users never see a login screen. Trip members become name-based, devices claim names via invite codes.

**Architecture:** Supabase `signInAnonymously()` runs during app bootstrap. All 54 RLS policies stay intact because `auth.uid()` still works with anonymous users. Login/register/password screens are removed. Trip creation adds member names; joining a trip means picking an unclaimed name.

**Tech Stack:** Flutter, Riverpod 2.x, Supabase (anonymous auth), GoRouter, SharedPreferences

---

### Task 1: Enable Anonymous Auth in Supabase & Add Auto Sign-In

**Files:**
- Modify: `lib/core/config/supabase_config.dart`
- Modify: `lib/main.dart`

**Step 1: Add `ensureAnonymousSession()` to SupabaseConfig**

In `lib/core/config/supabase_config.dart`, add this method to the `SupabaseConfig` class after the `initialize()` method:

```dart
/// Ensure an anonymous session exists.
/// If no session, sign in anonymously. If session exists, do nothing.
static Future<void> ensureAnonymousSession() async {
  if (client.auth.currentSession != null) {
    log('Session already exists');
    return;
  }
  log('No session — signing in anonymously');
  await client.auth.signInAnonymously();
  log('Anonymous sign-in complete');
}
```

**Step 2: Call it in main.dart after Supabase init**

In `lib/main.dart`, add after line 27 (`await SupabaseConfig.initialize();`):

```dart
// Ensure device has an anonymous session
await SupabaseConfig.ensureAnonymousSession();
```

**Step 3: Verify it compiles**

Run: `flutter analyze`
Expected: No new errors

**Step 4: Commit**

```bash
git add lib/core/config/supabase_config.dart lib/main.dart
git commit -m "feat: add anonymous auto sign-in on app bootstrap"
```

---

### Task 2: Simplify Auth Provider — Remove Email/Password Logic

**Files:**
- Modify: `lib/features/auth/providers/auth_provider.dart`

**Step 1: Strip AuthService down to essentials**

Replace the entire file content with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';

/// Auth state provider - listens to Supabase auth changes
final authStateProvider = StreamProvider<User?>((ref) {
  return SupabaseConfig.client.auth.onAuthStateChange.map(
    (event) => event.session?.user,
  );
});

/// Current user provider
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

/// Auth service provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// Minimal auth service — anonymous sessions only
class AuthService {
  SupabaseClient get _client => SupabaseConfig.client;

  /// Get current session
  Session? get currentSession => _client.auth.currentSession;

  /// Check if user is authenticated (anonymous or otherwise)
  bool get isAuthenticated => _client.auth.currentUser != null;
}
```

**Step 2: Verify it compiles**

Run: `flutter analyze`
Expected: Errors in files that import removed providers (`authLoadingProvider`, `authModeProvider`, `authErrorProvider`, `signOut`, etc.) — these will be fixed in subsequent tasks.

**Step 3: Commit**

```bash
git add lib/features/auth/providers/auth_provider.dart
git commit -m "refactor: strip auth provider to anonymous-only essentials"
```

---

### Task 3: Remove Auth Screens

**Files:**
- Delete: `lib/features/auth/screens/login_screen.dart`
- Delete: `lib/features/auth/screens/forgot_password_screen.dart`
- Delete: `lib/features/auth/screens/reset_password_screen.dart`

**Step 1: Delete the three auth screens**

```bash
rm lib/features/auth/screens/login_screen.dart
rm lib/features/auth/screens/forgot_password_screen.dart
rm lib/features/auth/screens/reset_password_screen.dart
```

**Step 2: Commit**

```bash
git add -A lib/features/auth/screens/
git commit -m "chore: remove login, forgot-password, reset-password screens"
```

---

### Task 4: Simplify Router — Remove Auth Routes & Guards

**Files:**
- Modify: `lib/core/router/app_router.dart`

**Step 1: Rewrite the router**

Replace the entire file with:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/screens/home_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/trip/screens/create_trip_screen.dart';
import '../../features/trip/screens/join_trip_screen.dart';

/// Route names for type-safe navigation
class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String home = '/home';
  static const String createTrip = '/create-trip';
  static const String joinTrip = '/join-trip';
  static const String settings = '/settings';
}

/// Provider to track onboarding completion state
final onboardingCompleteProvider = FutureProvider<bool>((ref) async {
  return await OnboardingScreen.isCompleted();
});

/// Router provider — no auth guards, just onboarding check
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) {
      final isSplash = state.matchedLocation == AppRoutes.splash;
      final isOnboarding = state.matchedLocation == AppRoutes.onboarding;
      final onboardingDone =
          ref.read(onboardingCompleteProvider).valueOrNull ?? false;

      // Splash redirects based on onboarding state
      if (isSplash) {
        return onboardingDone ? AppRoutes.home : AppRoutes.onboarding;
      }

      // Allow onboarding screen
      if (isOnboarding) return null;

      return null;
    },
    routes: [
      // Splash - auto-redirects
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const _SplashScreen(),
      ),

      // Onboarding
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const OnboardingScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),

      // Home / Trip List
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const HomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),

      // Create Trip
      GoRoute(
        path: AppRoutes.createTrip,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const CreateTripScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: child,
            );
          },
        ),
      ),

      // Join Trip
      GoRoute(
        path: AppRoutes.joinTrip,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const JoinTripScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: child,
            );
          },
        ),
      ),

      // Settings
      GoRoute(
        path: AppRoutes.settings,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SettingsScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: child,
            );
          },
        ),
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.matchedLocation}')),
    ),
  );
});

/// Splash screen that auto-redirects
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF13EC92), Color(0xFF0BAE6B)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF13EC92).withAlpha(100),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(Icons.explore_rounded, size: 40, color: Colors.black),
            ),
            const SizedBox(height: 24),
            const Text(
              'Rihla',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 40),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF13EC92),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Step 2: Verify it compiles**

Run: `flutter analyze`
Expected: Clean (auth imports removed)

**Step 3: Commit**

```bash
git add lib/core/router/app_router.dart
git commit -m "refactor: simplify router — remove auth routes and guards"
```

---

### Task 5: Update Home Screen — Remove Email-Based Display Name

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart`

**Step 1: Remove auth import and email-based display name**

Remove line 14:
```dart
import '../../auth/providers/auth_provider.dart';
```

In `build()` (line 26), remove:
```dart
final user = ref.watch(currentUserProvider);
```

Change the `_buildHeader` call (line 57) from:
```dart
_buildHeader(context, ref, user)
```
to:
```dart
_buildHeader(context, ref)
```

**Step 2: Simplify `_buildHeader`**

Change the method signature (line 158) from:
```dart
Widget _buildHeader(BuildContext context, WidgetRef ref, dynamic user) {
  final email = user?.email ?? 'Traveler';
  final displayName = email.split('@').first;
```
to:
```dart
Widget _buildHeader(BuildContext context, WidgetRef ref) {
  const displayName = 'Traveler';
```

**Step 3: Verify it compiles**

Run: `flutter analyze`

**Step 4: Commit**

```bash
git add lib/features/home/screens/home_screen.dart
git commit -m "refactor: remove email-based display name from home screen"
```

---

### Task 6: Update Settings Screen — Remove Profile & Sign Out

**Files:**
- Modify: `lib/features/settings/screens/settings_screen.dart`

**Step 1: Remove auth-related imports**

Remove these imports:
```dart
import '../../auth/providers/auth_provider.dart';
import '../../auth/providers/profile_provider.dart';
import '../../auth/services/profile_service.dart';
```

**Step 2: Remove from `build()` method**

Remove line 383:
```dart
final user = ref.watch(currentUserProvider);
```

**Step 3: Replace profile section with simple device info**

Replace the `_buildProfileSection` call and its method with a static card. Change the sliver at line 402-407 from `_buildProfileSection(context, user)` to a simple header card showing "Rihla" and app version. Remove the `_buildProfileSection` method (lines 541-635), the `_showEditProfileDialog` method (lines 65-181), and the `_getAvatarIcon` method (lines 38-63).

**Step 4: Remove Sign Out section**

Remove the `_buildSignOutButton` sliver (lines 448-452) and the `_buildSignOutButton` method (lines 822-892).

**Step 5: Verify it compiles**

Run: `flutter analyze`

**Step 6: Commit**

```bash
git add lib/features/settings/screens/settings_screen.dart
git commit -m "refactor: remove profile section and sign-out from settings"
```

---

### Task 7: Remove Profile Provider & Service

**Files:**
- Delete: `lib/features/auth/providers/profile_provider.dart`
- Delete: `lib/features/auth/services/profile_service.dart`
- Delete: `lib/features/auth/models/user_profile_model.dart`

**Step 1: Check for remaining imports of profile_provider**

Search for any files still importing these deleted modules. Fix any remaining references.

Run: `grep -r "profile_provider\|profile_service\|user_profile_model" lib/ --include="*.dart" -l`

**Step 2: Delete the files**

```bash
rm lib/features/auth/providers/profile_provider.dart
rm lib/features/auth/services/profile_service.dart
rm lib/features/auth/models/user_profile_model.dart
```

**Step 3: Fix any remaining imports**

Remove imports and usages in any files found in Step 1.

**Step 4: Verify it compiles**

Run: `flutter analyze`

**Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove profile provider, service, and model"
```

---

### Task 8: Update App Bootstrap Provider

**Files:**
- Modify: `lib/core/providers/app_bootstrap_provider.dart`

**Step 1: Simplify bootstrap — remove auth state listener dependency**

The bootstrap currently listens to `currentUserProvider` changes to sync notifications. With anonymous auth, the user is always present after bootstrap. Simplify to:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../services/notification_service.dart';

/// Keeps opt-in services in sync with persisted settings.
final appBootstrapProvider = Provider<void>((ref) {
  Future<void> syncNotifications() async {
    final settings = ref.read(settingsProvider);
    final notificationService = ref.read(notificationServiceProvider);

    if (!settings.pushNotificationsEnabled) {
      await notificationService.removeToken();
      return;
    }

    final enabled = await notificationService.initialize();
    if (!enabled && ref.read(settingsProvider).pushNotificationsEnabled) {
      await ref
          .read(settingsProvider.notifier)
          .setPushNotificationsEnabled(false);
    }
  }

  ref.listen<bool>(
    settingsProvider.select((value) => value.pushNotificationsEnabled),
    (previous, next) {
      unawaited(syncNotifications());
    },
    fireImmediately: true,
  );
});
```

**Step 2: Verify it compiles**

Run: `flutter analyze`

**Step 3: Commit**

```bash
git add lib/core/providers/app_bootstrap_provider.dart
git commit -m "refactor: simplify bootstrap — remove auth state dependency"
```

---

### Task 9: Fix Remaining Auth References Across Codebase

**Files:**
- Various files that still import removed auth providers

**Step 1: Find all remaining references**

```bash
grep -r "authLoadingProvider\|authErrorProvider\|authModeProvider\|AuthMode\|signOut\|signUp\|signIn\|sendPasswordResetEmail\|updatePassword\|currentUserProvider\|authServiceProvider" lib/ --include="*.dart" -l
```

**Step 2: For each file found, decide action:**

- `currentUserProvider` usage in data providers (trip_provider, etc.): **Keep** — the anonymous user still has a valid `auth.uid()`
- `authServiceProvider.signOut()` references (settings): **Already removed** in Task 6
- `authLoadingProvider` / `authErrorProvider`: **Already removed** in Task 2
- Any remaining imports of deleted screens: **Remove**

**Step 3: Verify everything compiles**

Run: `flutter analyze`
Expected: 0 errors

**Step 4: Commit**

```bash
git add -A
git commit -m "fix: clean up remaining auth references across codebase"
```

---

### Task 10: Update Existing Tests

**Files:**
- Modify: `test/features/command_center_test.dart`
- Modify: `test/features/ledger_test.dart`
- Modify: `test/integration/happy_path_test.dart`
- Modify: `test/widget_test.dart`

**Step 1: Remove auth-related provider overrides from tests**

Any test that overrides `authStateProvider` or `currentUserProvider` needs updating. Replace with a simple anonymous user mock or remove the override if the provider no longer guards behavior.

Remove overrides for deleted providers: `authLoadingProvider`, `authErrorProvider`, `profileNotifierProvider`.

**Step 2: Remove test imports of deleted files**

Remove imports for `login_screen.dart`, `forgot_password_screen.dart`, `reset_password_screen.dart`, `profile_provider.dart`.

**Step 3: Update router-related tests**

Tests that reference `AppRoutes.login`, `AppRoutes.forgotPassword`, or `AppRoutes.resetPassword` need those references removed.

**Step 4: Run all tests**

Run: `flutter test`
Expected: All tests pass

**Step 5: Commit**

```bash
git add test/
git commit -m "test: update tests for anonymous auth model"
```

---

### Task 11: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update documentation to reflect new auth model**

- Change "Auth" section: remove PKCE flow, deep link scheme. Add "Anonymous auth via `signInAnonymously()`"
- Update features list: note that `auth` feature is simplified (no login screens)
- Update routing section: remove `/login`, `/forgot-password`, `/reset-password`
- Update key technical details: remove password reset, add anonymous auth note
- Remove `profiles` table from database section (or mark as unused)

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for anonymous auth model"
```

---

### Task 12: Final Verification

**Step 1: Run full analysis**

Run: `flutter analyze`
Expected: 0 issues

**Step 2: Run all tests**

Run: `flutter test`
Expected: All tests pass

**Step 3: Test the app manually**

Run: `flutter run --dart-define-from-file=config.json`

Verify:
- App opens directly to onboarding (first launch) or home (subsequent)
- No login screen appears
- Can create a trip
- Can join a trip with invite code
- Settings shows preferences (no profile section, no sign out)

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete auth removal — anonymous device identity model"
```
