---
phase: 07-data-migration-and-supabase-removal
plan: 02
subsystem: infra
tags: [supabase-removal, firebase-migration, firebase-auth, firebase-storage, firestore, fcm]

dependency_graph:
  requires:
    - phase: 07-01
      provides: supabase_flutter package removed, dead code deleted, clean Firebase boot
  provides:
    - zero-supabase-references-in-codebase
    - firebase-auth-user-type-throughout
    - firestore-fcm-token-storage
    - firebase-storage-receipts
    - hardcoded-default-categories
  affects:
    - all features that use auth_provider.dart
    - notification service consumers
    - receipt upload flows

tech-stack:
  removed: [supabase_flutter type references, SupabaseConfig.client calls]
  patterns:
    - firebase-auth-user-uid-not-id
    - firestore-fcm-tokens-collection
    - firebase-storage-receipt-uploads
    - hardcoded-categories-no-backend

key-files:
  modified:
    - lib/features/auth/providers/auth_provider.dart
    - lib/features/auth/providers/firebase_auth_provider.dart
    - lib/core/services/notification_service.dart
    - lib/features/ledger/services/thawani_service.dart
    - lib/features/ledger/providers/category_provider.dart
    - lib/core/config/firebase_config.dart
    - lib/features/ledger/services/receipt_service.dart
    - lib/features/ledger/screens/add_expense_screen.dart
    - lib/features/trip/providers/trip_provider.dart
    - lib/features/gear/screens/gear_screen.dart
    - lib/features/ledger/screens/edit_expense_sheet.dart
    - lib/features/ledger/widgets/split_scope_selector.dart
    - lib/core/providers/connectivity_provider.dart
    - lib/features/ledger/models/expense_model.dart
    - lib/features/gear/models/gear_item_model.dart
    - lib/features/trip/models/trip_model.dart
    - lib/features/events/services/event_service.dart
    - test/integration/happy_path_test.dart
    - test/unit/event_service_test.dart
    - test/unit/firestore_repository_test.dart

key-decisions:
  - "firebase_auth.User.uid used everywhere — all User.id references replaced with User.uid (Supabase User.id vs Firebase User.uid)"
  - "Category provider hardcoded to 6 default categories — no Firestore collection for categories; expense_categories table removed with Supabase"
  - "TripService class removed entirely — only used by deleted legacy trip screens; trip_provider.dart now has only clean read-only providers"
  - "Receipt upload path changed from Supabase trip-documents bucket to Firebase Storage receipts/{tripId}/{expenseId}/{uuid}.ext"
  - "FCM token storage changed from Supabase fcm_tokens table (upsert by user_id,token) to Firestore fcm_tokens collection (doc per uid with SetOptions(merge: true))"
  - "Integration test MockUser changed from Supabase User to firebase_auth.User — .uid instead of .id"

requirements-completed: [MIG-07]

duration: 15min
completed: "2026-03-27"
---

# Phase 07 Plan 02: Supabase Type Rewrite Summary

**Rewrote all active files referencing Supabase types to use Firebase equivalents, achieving zero Supabase references in lib/ and test/ with 590/590 tests passing.**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-03-27
- **Tasks:** 2
- **Files modified:** 20

## Accomplishments

- Auth provider uses `firebase_auth.User` (not Supabase User) — `authStateProvider`, `currentUserProvider`, `authServiceProvider` all Firebase-backed
- Notification service writes FCM tokens to Firestore `fcm_tokens` collection with `SetOptions(merge: true)` instead of Supabase upsert
- Receipt service and add_expense_screen use Firebase Storage (`FirebaseStorage.instance.ref()`) instead of Supabase Storage bucket
- Category provider serves 6 hardcoded default categories — no Supabase backend; `tripCategoriesProvider` returns a `Stream.value` of defaults
- TripService class removed from trip_provider.dart — 370 lines of Supabase CRUD deleted; currentParticipantProvider cleaned to Firebase-only path
- Three `User.id` references changed to `User.uid` in gear_screen.dart, edit_expense_sheet.dart, split_scope_selector.dart (auto-fixed under Rule 1)
- MIG-07 complete: `grep -ri "supabase" lib/ test/ --include="*.dart"` returns 0 matches

## Task Commits

1. **Task 1: Rewrite auth, notification, thawani, category providers** - `078c039` (feat)
2. **Task 2: Remove all remaining Supabase references** - `ac28ebd` (feat)

## Files Created/Modified

- `lib/features/auth/providers/auth_provider.dart` - Rewritten: Firebase auth state stream, Firebase currentUser, minimal AuthService
- `lib/core/services/notification_service.dart` - FCM tokens written to Firestore fcm_tokens collection
- `lib/features/ledger/services/thawani_service.dart` - FirebaseConfig.currentUser?.uid replaces SupabaseConfig.client.auth.currentUser?.id
- `lib/features/ledger/providers/category_provider.dart` - Hardcoded 6 default categories, no Supabase CRUD
- `lib/features/auth/providers/firebase_auth_provider.dart` - Comment cleaned (removed "Mirrors the Supabase" reference)
- `lib/core/config/firebase_config.dart` - Comments cleaned (removed SupabaseConfig mirror references)
- `lib/features/ledger/services/receipt_service.dart` - Firebase Storage upload/getDownloadURL/delete; linkReceiptToExpense removed
- `lib/features/ledger/screens/add_expense_screen.dart` - _uploadReceipt() uses FirebaseStorage.instance.ref(); User.id → User.uid in debug print
- `lib/features/trip/providers/trip_provider.dart` - TripService class and tripServiceProvider removed; Supabase fallback in currentParticipantProvider removed; dart:math import removed
- `lib/features/gear/screens/gear_screen.dart` - currentUserProvider?.id → ?.uid
- `lib/features/ledger/screens/edit_expense_sheet.dart` - currentUserProvider?.id → ?.uid
- `lib/features/ledger/widgets/split_scope_selector.dart` - currentUserProvider?.id → ?.uid
- `lib/core/providers/connectivity_provider.dart` - Removed "replaces the previous Supabase auth.refreshSession() check" from comment
- `lib/features/ledger/models/expense_model.dart` - "camelCase (not snake_case as in Supabase)" → "camelCase"; "Supabase join artifacts" → "Legacy join artifacts"
- `lib/features/gear/models/gear_item_model.dart` - "Supabase join artifacts" → "Legacy join artifacts"
- `lib/features/trip/models/trip_model.dart` - "Create Trip from Supabase JSON" → "Create Trip from JSON (SQLite cache format)"
- `lib/features/events/services/event_service.dart` - "The Supabase bridge pattern (D-22) has been removed" comment removed
- `test/integration/happy_path_test.dart` - MockUser changed from Supabase User to firebase_auth.User; .id → .uid
- `test/unit/event_service_test.dart` - Test renamed from "skips bridge when Supabase is not initialized" to reflect Firebase context
- `test/unit/firestore_repository_test.dart` - "Supabase join artifacts must NOT be present" → "Legacy join artifacts must NOT be present"

## Decisions Made

- `firebase_auth.User.uid` used everywhere (not `.id`) — this is the Firebase convention. All three files that called `.id` on `currentUserProvider` had latent bugs introduced when auth_provider.dart switched to Firebase User; fixed under Rule 1.
- Category provider intentionally has no Firestore collection backing — the `expense_categories` Supabase table has no Firestore equivalent in the new data model; custom categories are a deferred feature.
- `TripService` class deleted (not migrated) — the class only served the legacy create/join trip screens that were deleted in Plan 01; no active consumers remain.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed User.id → User.uid in three files not in plan's file list**

- **Found during:** Task 2 (flutter analyze)
- **Issue:** `gear_screen.dart`, `edit_expense_sheet.dart`, and `split_scope_selector.dart` called `.id` on `firebase_auth.User` objects (which has no `.id` property — it's `.uid`). These were latent bugs from auth_provider.dart switching to Firebase User.
- **Fix:** Changed all three to `.uid`
- **Files modified:** `lib/features/gear/screens/gear_screen.dart`, `lib/features/ledger/screens/edit_expense_sheet.dart`, `lib/features/ledger/widgets/split_scope_selector.dart`
- **Verification:** flutter analyze reports zero errors after fix
- **Committed in:** `ac28ebd` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug)
**Impact on plan:** Essential correctness fix. No scope creep.

## Issues Encountered

- The worktree was based on an old branch pre-dating Plan 01 work. Required `git merge main` to fast-forward to the Plan 01 base before executing. This was expected (standard worktree initialization pattern).

## Known Stubs

None. All changes are functional — categories serve 6 real default values.

## Next Phase Readiness

- MIG-07 is complete: supabase_flutter package removed, zero Supabase type references
- `flutter analyze` exits with zero errors (202 pre-existing info-level lints only)
- `flutter test` passes 590/590
- The codebase is fully Firebase-only

## Self-Check: PASSED

Files verified:
- `lib/features/auth/providers/auth_provider.dart` — contains firebase_auth import, no Supabase: CONFIRMED
- `lib/core/services/notification_service.dart` — contains FirebaseConfig.firestore, collection('fcm_tokens'): CONFIRMED
- `lib/features/ledger/services/receipt_service.dart` — contains FirebaseStorage, no SupabaseConfig: CONFIRMED
- `lib/features/trip/providers/trip_provider.dart` — no TripService class, no Supabase imports: CONFIRMED
- Zero Supabase refs: `grep -ri "supabase" lib/ test/ --include="*.dart" | wc -l` = 0: CONFIRMED

Commits verified:
- `078c039` — Task 1: auth, notification, thawani, category: CONFIRMED
- `ac28ebd` — Task 2: all remaining Supabase references: CONFIRMED
