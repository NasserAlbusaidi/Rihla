# Security & Performance Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all critical, high, and medium security vulnerabilities and performance issues identified in the code review.

**Architecture:** Fixes are organized in priority order -- critical security first, then critical performance, then high/medium issues. Each task is self-contained and can be committed independently. The app uses Flutter + Riverpod + Supabase + GoRouter + SQLite (sqflite).

**Tech Stack:** Flutter 3.x, Riverpod 2.x, Supabase Flutter 2.x, GoRouter 13.x, sqflite 2.x, connectivity_plus (new dep)

---

## Phase 1: Critical Security Fixes

### Task 1: Replace public URLs with storage paths in Vault

**Files:**
- Modify: `lib/features/vault/providers/document_provider.dart:120-180`

**Step 1: Fix uploadFile to store storage path instead of public URL**

In `document_provider.dart`, replace the `getPublicUrl` block (lines 150-153) and the insert (lines 158-169):

```dart
// BEFORE (lines 150-153):
// Get public URL
final fileUrl = _client.storage
    .from(_bucketName)
    .getPublicUrl(storagePath);

// AFTER: Store the storage path, not a public URL
final fileUrl = storagePath; // Store path, use signed URLs for access
```

**Step 2: Run the app to verify uploads still work**

Run: `flutter run` and test uploading a document.
Expected: Document uploads successfully, `file_url` column now contains a path like `tripId/timestamp-filename` instead of a full URL.

**Step 3: Commit**

```bash
git add lib/features/vault/providers/document_provider.dart
git commit -m "security: store storage paths instead of public URLs in vault"
```

---

### Task 2: Add authorization check to deleteTrip and updateTrip

**Files:**
- Modify: `lib/features/trip/providers/trip_provider.dart:269-331`

**Step 1: Add leader check to deleteTrip**

Replace the `deleteTrip` method (lines 317-331):

```dart
/// Delete a trip (leader only)
Future<bool> deleteTrip(String tripId) async {
  try {
    // Verify current user is the leader
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final trip = await getTripById(tripId);
    if (trip == null || trip.leaderId != userId) {
      _ref.read(tripErrorProvider.notifier).state = 'Only the trip leader can delete this trip';
      return false;
    }

    SupabaseConfig.log('deleteTrip: $tripId');
    await _client.from('trips').delete().eq('id', tripId);

    SupabaseConfig.log('deleteTrip: SUCCESS');
    return true;
  } catch (e) {
    SupabaseConfig.log('deleteTrip: FAILED', error: e);
    return false;
  }
}
```

**Step 2: Add leader check to updateTrip**

In the `updateTrip` method (lines 269-301), add a leader check at the top of the try block:

```dart
Future<bool> updateTrip(
  String tripId, {
  String? name,
  DateTime? startDate,
  DateTime? endDate,
  String? icon,
}) async {
  try {
    // Verify current user is the leader
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final trip = await getTripById(tripId);
    if (trip == null || trip.leaderId != userId) {
      _ref.read(tripErrorProvider.notifier).state = 'Only the trip leader can edit this trip';
      return false;
    }

    final updates = <String, dynamic>{};
    if (name != null && name.isNotEmpty) {
      updates['name'] = name;
    }
    if (startDate != null) {
      updates['start_date'] = startDate.toIso8601String().split('T').first;
    }
    if (endDate != null) {
      updates['end_date'] = endDate.toIso8601String().split('T').first;
    }
    if (icon != null && icon.isNotEmpty) {
      updates['icon'] = icon;
    }

    if (updates.isEmpty) return true;

    SupabaseConfig.log('Updating trip $tripId with: $updates');

    await _client.from('trips').update(updates).eq('id', tripId);
    SupabaseConfig.log('Trip update successful');
    return true;
  } catch (e) {
    SupabaseConfig.log('Trip update error', error: e);
    return false;
  }
}
```

**Step 3: Commit**

```bash
git add lib/features/trip/providers/trip_provider.dart
git commit -m "security: add leader authorization checks to deleteTrip and updateTrip"
```

---

### Task 3: Fix profile update to use authenticated user ID

**Files:**
- Modify: `lib/features/auth/services/profile_service.dart:24-41`

**Step 1: Replace user-supplied ID with authenticated user ID**

```dart
/// Update user profile
Future<UserProfile?> updateProfile(UserProfile profile) async {
  try {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final data = await _client
        .from('profiles')
        .update({
          'display_name': profile.displayName,
          'avatar_url': profile.avatarUrl,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId) // Always use authenticated user's ID
        .select()
        .single();

    return UserProfile.fromJson(data);
  } catch (e) {
    rethrow;
  }
}
```

**Step 2: Commit**

```bash
git add lib/features/auth/services/profile_service.dart
git commit -m "security: use authenticated user ID for profile updates"
```

---

### Task 4: Add document deletion authorization check

**Files:**
- Modify: `lib/features/vault/providers/document_provider.dart:182-210`

**Step 1: Add uploader check to deleteDocument**

```dart
/// Delete a document (uploader only)
Future<bool> deleteDocument(Document document) async {
  SupabaseConfig.log('deleteDocument: ${document.id}');

  try {
    // Verify current user is the uploader
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    if (document.uploaderId != userId) {
      _ref.read(documentErrorProvider.notifier).state = 'Only the uploader can delete this document';
      return false;
    }

    // Extract storage path from URL
    final storagePath = document.fileUrl;

    // If fileUrl is a full URL (legacy), extract path
    if (storagePath.startsWith('http')) {
      final uri = Uri.parse(storagePath);
      final pathSegments = uri.pathSegments;
      final bucketIndex = pathSegments.indexOf(_bucketName);
      if (bucketIndex >= 0 && bucketIndex < pathSegments.length - 1) {
        final extractedPath = pathSegments.sublist(bucketIndex + 1).join('/');
        SupabaseConfig.log('deleteDocument: Removing from storage: $extractedPath');
        await _client.storage.from(_bucketName).remove([extractedPath]);
      }
    } else {
      // New format: fileUrl is already the storage path
      SupabaseConfig.log('deleteDocument: Removing from storage: $storagePath');
      await _client.storage.from(_bucketName).remove([storagePath]);
    }

    // Delete database record
    await _client.from('documents').delete().eq('id', document.id);

    SupabaseConfig.log('deleteDocument: SUCCESS');
    return true;
  } catch (e) {
    SupabaseConfig.log('deleteDocument: FAILED', error: e);
    _ref.read(documentErrorProvider.notifier).state = e.toString();
    return false;
  }
}
```

**Step 2: Commit**

```bash
git add lib/features/vault/providers/document_provider.dart
git commit -m "security: add uploader authorization check on document deletion"
```

---

## Phase 2: Critical Performance Fixes

### Task 5: Eliminate duplicate Supabase queries in StreamProviders

**Files:**
- Modify: `lib/features/ledger/providers/expense_provider.dart:21-91`
- Modify: `lib/features/gear/providers/gear_provider.dart:12-41`
- Modify: `lib/features/vault/providers/document_provider.dart:19-53`
- Modify: `lib/features/trip/providers/trip_provider.dart:62-79`
- Modify: `lib/features/logistics/providers/sub_group_provider.dart` (similar pattern)

The core issue: every `.stream().asyncMap()` ignores the stream data and fires a second `.select()` query. Fix: use the stream data when possible, or switch to a manual Realtime subscription + single REST fetch.

**Step 1: Fix tripExpensesProvider**

Replace `expense_provider.dart` lines 21-55:

```dart
/// Stream of expenses for the current trip with offline caching
final tripExpensesProvider = StreamProvider.family<List<Expense>, String>((
  ref,
  tripId,
) {
  // Initial fetch
  Future<List<Expense>> fetchExpenses() async {
    final result = await SupabaseConfig.client
        .from('expenses')
        .select(
          '*, expense_categories(*), participants!payer_participant_id(*, profiles!user_id(display_name, avatar_url))',
        )
        .eq('trip_id', tripId)
        .eq('is_deleted', false)
        .order('created_at', ascending: false);

    final expenses = (result as List)
        .map((json) => Expense.fromJson(json as Map<String, dynamic>))
        .toList();

    await CacheService.cacheExpenses(tripId, expenses);
    return expenses;
  }

  // Listen to realtime changes, re-fetch only when data changes
  final controller = StreamController<List<Expense>>();

  // Do initial fetch
  fetchExpenses().then(controller.add).catchError((e) async {
    debugPrint('Network error, using cached expenses: $e');
    final cached = await CacheService.getCachedExpenses(tripId);
    controller.add(cached);
  });

  // Subscribe to realtime changes
  final channel = SupabaseConfig.client.channel('expenses-$tripId');
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'expenses',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'trip_id',
          value: tripId,
        ),
        callback: (payload) {
          // Re-fetch full data on any change
          fetchExpenses().then(controller.add);
        },
      )
      .subscribe();

  ref.onDispose(() {
    channel.unsubscribe();
    controller.close();
  });

  return controller.stream;
});
```

**Step 2: Apply the same pattern to tripSettlementsProvider**

Replace `expense_provider.dart` lines 57-91 with the same Realtime channel pattern, changing the table to `settlements` and the fetch query to match the existing settlements select.

**Step 3: Apply the same pattern to tripGearProvider**

Replace `gear_provider.dart` lines 12-41 with the Realtime channel pattern for the `gear_items` table.

**Step 4: Apply the same pattern to tripDocumentsProvider**

Replace `document_provider.dart` lines 19-53.

**Step 5: Apply the same pattern to tripLogisticsParticipantsProvider**

Replace `trip_provider.dart` lines 62-79.

**Step 6: Apply the same pattern to tripSubGroupsProvider**

Replace `sub_group_provider.dart` (same pattern).

**Step 7: Run the app and verify all screens still load data correctly**

Run: `flutter run` and navigate through Ledger, Gear, Vault, Logistics screens.
Expected: Data loads correctly, no duplicate network calls visible in logs.

**Step 8: Commit**

```bash
git add lib/features/ledger/providers/expense_provider.dart lib/features/gear/providers/gear_provider.dart lib/features/vault/providers/document_provider.dart lib/features/trip/providers/trip_provider.dart lib/features/logistics/providers/sub_group_provider.dart
git commit -m "perf: eliminate duplicate Supabase queries in all StreamProviders"
```

---

### Task 6: Fix tripBalancesProvider cascading rebuild

**Files:**
- Modify: `lib/features/ledger/providers/expense_provider.dart:260-278`

**Step 1: Convert tripBalancesProvider to a synchronous derived Provider**

Replace lines 260-278:

```dart
/// Provider for user balances in a trip (derived synchronously)
final tripBalancesProvider = Provider.family<AsyncValue<List<UserBalance>>, String>((
  ref,
  tripId,
) {
  final expensesAsync = ref.watch(tripExpensesProvider(tripId));
  final settlementsAsync = ref.watch(tripSettlementsProvider(tripId));
  final participantsAsync = ref.watch(tripLogisticsParticipantsProvider(tripId));
  final subGroupsAsync = ref.watch(tripSubGroupsProvider(tripId));

  // Only compute when all data is available
  return expensesAsync.when(
    data: (expenses) => settlementsAsync.when(
      data: (settlements) => participantsAsync.when(
        data: (participants) => subGroupsAsync.when(
          data: (subGroups) => AsyncValue.data(
            BalanceCalculator.calculateBalances(
              expenses: expenses,
              settlements: settlements,
              participants: participants,
              subGroups: subGroups,
            ),
          ),
          loading: () => const AsyncValue.loading(),
          error: (e, st) => AsyncValue.error(e, st),
        ),
        loading: () => const AsyncValue.loading(),
        error: (e, st) => AsyncValue.error(e, st),
      ),
      loading: () => const AsyncValue.loading(),
      error: (e, st) => AsyncValue.error(e, st),
    ),
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});
```

**Step 2: Update all consumers of tripBalancesProvider**

Search for `tripBalancesProvider` usage. Consumers that previously used `.when()` on a `FutureProvider` now get an `AsyncValue<List<UserBalance>>` directly from a `Provider`. Update usages accordingly -- most `.when()` calls should work the same since the value is already an `AsyncValue`.

Files likely affected:
- `lib/features/home/screens/command_center.dart`
- `lib/features/ledger/screens/ledger_screen.dart`
- `lib/features/ledger/screens/settle_up_screen.dart`

**Step 3: Commit**

```bash
git add lib/features/ledger/providers/expense_provider.dart lib/features/home/screens/command_center.dart lib/features/ledger/screens/ledger_screen.dart lib/features/ledger/screens/settle_up_screen.dart
git commit -m "perf: convert tripBalancesProvider to synchronous derived provider"
```

---

## Phase 3: High Security Fixes

### Task 7: Add file validation to vault uploads

**Files:**
- Modify: `lib/features/vault/providers/document_provider.dart:72-118`

**Step 1: Add constants and validation to pickAndUpload**

Add constants at the top of the `DocumentService` class and validation in `pickAndUpload`:

```dart
class DocumentService {
  final Ref _ref;
  static const String _bucketName = 'trip-documents';
  static const int _maxFileSizeBytes = 25 * 1024 * 1024; // 25MB
  static const List<String> _allowedExtensions = [
    'pdf', 'jpg', 'jpeg', 'png', 'gif', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'csv',
  ];

  // ... existing code ...

  Future<Document?> pickAndUpload({required String tripId}) async {
    _ref.read(documentLoadingProvider.notifier).state = true;
    _ref.read(documentErrorProvider.notifier).state = null;
    _ref.read(uploadProgressProvider.notifier).state = 0;

    try {
      SupabaseConfig.log('pickAndUpload: Opening file picker');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        SupabaseConfig.log('pickAndUpload: User cancelled');
        _ref.read(documentLoadingProvider.notifier).state = false;
        return null;
      }

      final file = result.files.first;
      if (file.path == null) {
        throw Exception('Could not access file');
      }

      // Validate file size
      if (file.size > _maxFileSizeBytes) {
        _ref.read(documentErrorProvider.notifier).state =
            'File too large. Maximum size is 25MB.';
        _ref.read(documentLoadingProvider.notifier).state = false;
        return null;
      }

      SupabaseConfig.log(
        'pickAndUpload: Selected ${file.name} (${file.size} bytes)',
      );

      final document = await uploadFile(
        tripId: tripId,
        filePath: file.path!,
        fileName: file.name,
        fileSize: file.size,
        mimeType: _getMimeType(file.extension ?? ''),
      );

      _ref.read(documentLoadingProvider.notifier).state = false;
      return document;
    } catch (e) {
      SupabaseConfig.log('pickAndUpload: FAILED', error: e);
      _ref.read(documentErrorProvider.notifier).state = e.toString();
      _ref.read(documentLoadingProvider.notifier).state = false;
      return null;
    }
  }
```

**Step 2: Commit**

```bash
git add lib/features/vault/providers/document_provider.dart
git commit -m "security: add file type restriction and 25MB size limit to vault uploads"
```

---

### Task 8: Add email and password validation to login screen

**Files:**
- Modify: `lib/features/auth/screens/login_screen.dart:223-248`

**Step 1: Add validation helpers and update form validators**

Add a helper method and update the validators in `_buildFormCard`:

```dart
// Add as a static method or at top of _LoginScreenState
String? _validateEmail(String? v) {
  if (v == null || v.isEmpty) return 'REQUIRED';
  final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
  if (!emailRegex.hasMatch(v.trim())) return 'INVALID EMAIL FORMAT';
  return null;
}

String? _validatePassword(String? v, bool isSignUp) {
  if (v == null || v.isEmpty) return 'REQUIRED';
  if (isSignUp && v.length < 8) return 'MINIMUM 8 CHARACTERS';
  return null;
}
```

Then update the form fields in `_buildFormCard` (around lines 223-248):

```dart
_buildTextField(
  controller: _emailController,
  label: 'IDENTIFIER',
  hint: 'EMAIL ADDRESS',
  icon: Iconsax.sms,
  keyboardType: TextInputType.emailAddress,
  validator: _validateEmail,
),
const SizedBox(height: 20),
_buildTextField(
  controller: _passwordController,
  label: 'ACCESS CODE',
  hint: 'PASSWORD',
  icon: Iconsax.lock,
  obscureText: _obscurePassword,
  validator: (v) => _validatePassword(v, isSignUp),
  suffix: IconButton(
    icon: Icon(
      _obscurePassword ? Iconsax.eye_slash : Iconsax.eye,
      size: 20,
      color: Colors.white.withValues(alpha: 0.3),
    ),
    onPressed: () =>
        setState(() => _obscurePassword = !_obscurePassword),
  ),
),
```

**Step 2: Clear password controller after successful auth**

In `_submit()` method, clear the password after extracting it:

```dart
Future<void> _submit() async {
  if (!_formKey.currentState!.validate()) return;

  final email = _emailController.text.trim();
  final password = _passwordController.text;
  _passwordController.clear(); // Clear immediately after reading

  final authService = ref.read(authServiceProvider);
  final mode = ref.read(authModeProvider);

  bool success;
  if (mode == AuthMode.signUp) {
    success = await authService.signUp(email, password);
  } else {
    success = await authService.signIn(email, password);
  }

  if (success && mounted) {
    context.go('/home');
  }
}
```

**Step 3: Commit**

```bash
git add lib/features/auth/screens/login_screen.dart
git commit -m "security: add email format and password strength validation to login"
```

---

### Task 9: Sanitize auth error messages

**Files:**
- Modify: `lib/features/auth/providers/auth_provider.dart:44-101`

**Step 1: Add error message sanitizer and apply to all auth methods**

Add a helper method to `AuthService`:

```dart
/// Map Supabase auth errors to user-friendly messages
String _sanitizeAuthError(AuthException e) {
  final msg = e.message.toLowerCase();
  if (msg.contains('user already registered') || msg.contains('already exists')) {
    return 'Could not create account. Please try again.';
  }
  if (msg.contains('invalid login') || msg.contains('invalid password') || msg.contains('not found')) {
    return 'Invalid email or password';
  }
  if (msg.contains('rate limit') || msg.contains('too many')) {
    return 'Too many attempts. Please wait and try again.';
  }
  if (msg.contains('email not confirmed')) {
    return 'Please confirm your email before signing in.';
  }
  return 'Authentication failed. Please try again.';
}
```

Then replace all `e.message` usages with `_sanitizeAuthError(e)`:

- Line 66: `_ref.read(authErrorProvider.notifier).state = _sanitizeAuthError(e);`
- Line 92 (signIn): `_ref.read(authErrorProvider.notifier).state = _sanitizeAuthError(e);`
- Line 130 (resetPassword): `_ref.read(authErrorProvider.notifier).state = _sanitizeAuthError(e);`
- Line 151 (updatePassword): `_ref.read(authErrorProvider.notifier).state = _sanitizeAuthError(e);`

**Step 2: Commit**

```bash
git add lib/features/auth/providers/auth_provider.dart
git commit -m "security: sanitize auth error messages to prevent user enumeration"
```

---

## Phase 4: High Performance Fixes

### Task 10: Fix GoRouter recreation on auth state change

**Files:**
- Modify: `lib/core/router/app_router.dart:27-33`

**Step 1: Use refreshListenable pattern instead of ref.watch**

```dart
/// Auth state notifier for GoRouter refresh
final _authChangeNotifierProvider = Provider<ValueNotifier<bool>>((ref) {
  final notifier = ValueNotifier<bool>(false);
  ref.listen(authStateProvider, (_, __) {
    notifier.value = !notifier.value; // Toggle to trigger refresh
  });
  return notifier;
});

/// Router provider with auth-aware redirects
final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.watch(_authChangeNotifierProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: kDebugMode, // Fix: only log in debug
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isLoggedIn = authState.valueOrNull != null;
      // ... rest of redirect logic stays the same
```

This ensures the router is created once and uses `refreshListenable` to re-evaluate redirects without destroying the router instance.

**Step 2: Add `import 'package:flutter/foundation.dart';` at top of file**

**Step 3: Commit**

```bash
git add lib/core/router/app_router.dart
git commit -m "perf: use refreshListenable instead of recreating GoRouter on auth changes"
```

---

### Task 11: Replace Supabase connectivity check with connectivity_plus

**Files:**
- Modify: `lib/core/providers/connectivity_provider.dart`
- Modify: `lib/core/services/sync_service.dart:132-141`
- Modify: `pubspec.yaml` (add dependency)

**Step 1: Add connectivity_plus dependency**

Run: `flutter pub add connectivity_plus`

**Step 2: Rewrite ConnectivityNotifier to use connectivity_plus**

```dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cache_service.dart';
import '../services/sync_service.dart';

enum ConnectivityStatus { online, offline, syncing }

final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, ConnectivityStatus>((ref) {
      return ConnectivityNotifier();
    });

final pendingSyncCountProvider = FutureProvider<int>((ref) async {
  return await CacheService.getSyncQueueCount();
});

class ConnectivityNotifier extends StateNotifier<ConnectivityStatus> {
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  ConnectivityNotifier() : super(ConnectivityStatus.online) {
    _init();
  }

  void _init() {
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (state != ConnectivityStatus.syncing) {
        state = hasConnection ? ConnectivityStatus.online : ConnectivityStatus.offline;
      }
    });
  }

  void setSyncing() => state = ConnectivityStatus.syncing;
  void setOnline() => state = ConnectivityStatus.online;
  void setOffline() => state = ConnectivityStatus.offline;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
```

**Step 3: Remove isOnline() from SyncService**

Delete `sync_service.dart` lines 132-141 (the `isOnline()` method). It is no longer needed.

**Step 4: Commit**

```bash
git add pubspec.yaml lib/core/providers/connectivity_provider.dart lib/core/services/sync_service.dart
git commit -m "perf: replace Supabase DB query connectivity check with connectivity_plus"
```

---

### Task 12: Reduce Sentry sample rates for production

**Files:**
- Modify: `lib/main.dart:17-24`

**Step 1: Gate sample rates by build mode**

```dart
await SentryFlutter.init(
  (options) {
    options.dsn = const String.fromEnvironment('SENTRY_DSN');
    options.tracesSampleRate = kDebugMode ? 1.0 : 0.1;
    options.profilesSampleRate = kDebugMode ? 1.0 : 0.1;
  },
```

Add `import 'package:flutter/foundation.dart';` at the top if not already imported.

**Step 2: Commit**

```bash
git add lib/main.dart
git commit -m "perf: reduce Sentry sample rates to 10% in production builds"
```

---

## Phase 5: Medium Issues

### Task 13: Fix TextEditingController memory leak in LogisticsScreen

**Files:**
- Modify: `lib/features/logistics/screens/logistics_screen.dart:37-39`

**Step 1: Add controller disposal**

In the `dispose()` method (around line 37):

```dart
@override
void dispose() {
  _tabController.dispose();
  _nameController.dispose();
  _capacityController.dispose();
  super.dispose();
}
```

**Step 2: Commit**

```bash
git add lib/features/logistics/screens/logistics_screen.dart
git commit -m "fix: dispose TextEditingControllers in LogisticsScreen"
```

---

### Task 14: Add server-side filtering for transaction activity

**Files:**
- Modify: `lib/features/activity/services/activity_service.dart` (the tripTransactionActivityProvider)

**Step 1: Move MONEY filter to the Supabase query**

Find the `tripTransactionActivityProvider` and add `.eq('category', 'MONEY')` to the stream query, removing the client-side `.where()` filter:

```dart
final tripTransactionActivityProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, tripId) {
  return SupabaseConfig.client
      .from('activity_logs')
      .stream(primaryKey: ['id'])
      .eq('trip_id', tripId)
      // Add server-side filter instead of client-side
      .order('created_at', ascending: false)
      .asyncMap((data) async {
        // Filter at query level instead of client-side
        final result = await SupabaseConfig.client
            .from('activity_logs')
            .select('*, profiles!user_id(display_name, avatar_url)')
            .eq('trip_id', tripId)
            .eq('category', 'MONEY') // Server-side filter
            .order('created_at', ascending: false)
            .limit(20);
        return result;
      });
});
```

Note: This still has the duplicate query issue from Task 5. If Task 5 has already been applied, use the Realtime channel pattern instead.

**Step 2: Commit**

```bash
git add lib/features/activity/services/activity_service.dart
git commit -m "perf: filter MONEY transactions server-side instead of client-side"
```

---

### Task 15: Fix shrinkWrap + NeverScrollableScrollPhysics anti-pattern

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart` (trip list)
- Modify: `lib/features/home/screens/command_center.dart` (member lists)
- Modify: `lib/features/trip/screens/create_trip_screen.dart` (member list)

**Step 1: In home_screen.dart, replace ListView.builder with Column**

Since trips are typically a small list (< 20), replace the `shrinkWrap: true` + `NeverScrollableScrollPhysics()` ListView with a simple `Column`:

```dart
// Replace:
// ListView.builder(
//   shrinkWrap: true,
//   physics: const NeverScrollableScrollPhysics(),
//   itemCount: trips.length,
//   itemBuilder: (context, index) => _buildTripCard(trips[index], index),
// )

// With:
Column(
  children: [
    for (int i = 0; i < trips.length; i++)
      _buildTripCard(trips[i], i),
  ],
)
```

**Step 2: Apply the same pattern to command_center.dart and create_trip_screen.dart**

For any `ListView.builder` with `shrinkWrap: true` + `NeverScrollableScrollPhysics()` where the list is small (< 20 items), replace with `Column` + `for` loop.

**Step 3: Commit**

```bash
git add lib/features/home/screens/home_screen.dart lib/features/home/screens/command_center.dart lib/features/trip/screens/create_trip_screen.dart
git commit -m "perf: replace shrinkWrap ListView anti-pattern with Column for small lists"
```

---

### Task 16: Fix sequential trip caching

**Files:**
- Modify: `lib/core/services/cache_service.dart` (add batch method)
- Modify: `lib/features/trip/providers/trip_provider.dart:48-51`

**Step 1: Add batch cacheTrips method to CacheService**

Add a new method to `CacheService`:

```dart
/// Cache multiple trips in a single batch
static Future<void> cacheTrips(List<Trip> trips) async {
  final db = await LocalDatabase.database;
  final batch = db.batch();
  for (final trip in trips) {
    batch.insert(
      'trips',
      trip.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  await batch.commit(noResult: true);
}
```

**Step 2: Use batch method in trip_provider.dart**

Replace lines 48-51:

```dart
// BEFORE:
for (final trip in trips) {
  await CacheService.cacheTrip(trip);
}

// AFTER:
await CacheService.cacheTrips(trips);
```

**Step 3: Commit**

```bash
git add lib/core/services/cache_service.dart lib/features/trip/providers/trip_provider.dart
git commit -m "perf: batch trip caching instead of sequential inserts"
```

---

### Task 17: Remove unnecessary setState in LedgerScreen tab listener

**Files:**
- Modify: `lib/features/ledger/screens/ledger_screen.dart` (initState tab listener)

**Step 1: Remove the setState call from tab controller listener**

Find the `initState` method where the tab controller listener is added. The `TabBarView` already handles switching content -- the `setState(() {})` is unnecessary and forces a full rebuild.

```dart
// BEFORE:
_tabController.addListener(() {
  setState(() {});
});

// AFTER: Remove the listener entirely, or if needed for specific logic:
// _tabController.addListener(() {
//   // Only update if specific state needs to change
// });
```

**Step 2: Commit**

```bash
git add lib/features/ledger/screens/ledger_screen.dart
git commit -m "perf: remove unnecessary setState in LedgerScreen tab listener"
```

---

### Task 18: Add input length limits to text fields

**Files:**
- Modify: `lib/features/trip/screens/create_trip_screen.dart` (trip name field)
- Modify: `lib/features/logistics/screens/logistics_screen.dart` (group name field)

**Step 1: Add maxLength to trip name TextField**

Find the trip name TextFormField in `create_trip_screen.dart` and add:

```dart
TextFormField(
  maxLength: 50,
  // ... existing props
)
```

**Step 2: Add maxLength to logistics group name TextField**

In the `_showCreateDialog` in `logistics_screen.dart`:

```dart
TextFormField(
  controller: _nameController,
  maxLength: 40,
  // ... existing props
)
```

**Step 3: Commit**

```bash
git add lib/features/trip/screens/create_trip_screen.dart lib/features/logistics/screens/logistics_screen.dart
git commit -m "security: add input length limits to trip and group name fields"
```

---

## Phase 6: Final Verification

### Task 19: Full app smoke test

**Step 1: Run flutter analyze**

Run: `flutter analyze`
Expected: No new warnings or errors introduced by the changes.

**Step 2: Run existing tests**

Run: `flutter test`
Expected: All tests pass.

**Step 3: Manual smoke test**

Test each flow:
1. Login/signup with invalid email -> should show validation error
2. Login with short password on signup -> should show validation error
3. Upload a document to vault -> should work with valid file types
4. Try to upload a .exe file -> should be blocked by file picker
5. Navigate between tabs in ledger -> should not lag
6. Check network tab in DevTools -> should see single queries per data fetch, not doubles

**Step 4: Commit any final fixes**

```bash
git add -A
git commit -m "chore: final verification fixes"
```

---

## Summary of All Changes

| Task | Type | Severity | Files Changed |
|------|------|----------|---------------|
| 1 | Security | CRITICAL | document_provider.dart |
| 2 | Security | CRITICAL | trip_provider.dart |
| 3 | Security | HIGH | profile_service.dart |
| 4 | Security | HIGH | document_provider.dart |
| 5 | Performance | CRITICAL | 6 provider files |
| 6 | Performance | CRITICAL | expense_provider.dart + 3 screens |
| 7 | Security | HIGH | document_provider.dart |
| 8 | Security | HIGH | login_screen.dart |
| 9 | Security | MEDIUM | auth_provider.dart |
| 10 | Performance | HIGH | app_router.dart |
| 11 | Performance | HIGH | connectivity_provider.dart, sync_service.dart |
| 12 | Performance | HIGH | main.dart |
| 13 | Performance | MEDIUM | logistics_screen.dart |
| 14 | Performance | MEDIUM | activity_service.dart |
| 15 | Performance | MEDIUM | home_screen.dart, command_center.dart, create_trip_screen.dart |
| 16 | Performance | MEDIUM | cache_service.dart, trip_provider.dart |
| 17 | Performance | MEDIUM | ledger_screen.dart |
| 18 | Security | MEDIUM | create_trip_screen.dart, logistics_screen.dart |
| 19 | Verification | - | Full app |

**New dependency:** `connectivity_plus` (Task 11)
