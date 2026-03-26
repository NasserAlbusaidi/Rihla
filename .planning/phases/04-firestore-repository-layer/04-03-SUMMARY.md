---
phase: 04-firestore-repository-layer
plan: "03"
subsystem: vault-memories-migration
tags: [firestore, firebase-storage, vault, memories, lazy-migration, migration]
dependency_graph:
  requires: ["04-01", "04-02"]
  provides: ["firebase_storage_integration", "DocumentService", "MemoryService", "LazyMigrationService"]
  affects: ["lib/features/vault", "lib/features/memories", "lib/core/services"]
tech_stack:
  added: ["firebase_storage: ^13.2.0"]
  patterns:
    - "DocumentService extends FirestoreRepository — consistent base class pattern"
    - "MemoryService extends FirestoreRepository — concrete ImagePicker + Storage upload"
    - "LazyMigrationService — detect-empty-and-backfill migration pattern"
    - "@visibleForTesting withFirestore constructor — test injection pattern"
key_files:
  created:
    - lib/features/vault/services/document_service.dart
    - lib/core/services/lazy_migration_service.dart
  modified:
    - pubspec.yaml
    - lib/features/vault/models/document_model.dart
    - lib/features/vault/providers/document_provider.dart
    - lib/features/vault/screens/vault_screen.dart
    - lib/features/memories/models/memory_model.dart
    - lib/features/memories/services/memory_service.dart
    - lib/features/memories/providers/memory_provider.dart
    - lib/features/memories/screens/memories_screen.dart
    - test/unit/document_service_test.dart
    - test/unit/memory_service_test.dart
    - test/unit/lazy_migration_service_test.dart
decisions:
  - "Document.fileUrl maps to storagePath in Firestore — backward compat with existing screen code"
  - "Memory model keeps signedUrl field — URL resolved at display time by calling getDownloadUrl"
  - "LazyMigrationService catches SupabaseConfig.isAuthenticated in try-catch per Phase 03 pattern"
  - "Screen files updated with deprecated shim consumers and empty groupId placeholder comments"
  - "tripDocumentsProvider and tripMemoriesProvider kept as deprecated shims for screen migration deferral"
metrics:
  duration_minutes: 9
  completed_date: "2026-03-26"
  tasks_completed: 2
  files_created: 2
  files_modified: 11
---

# Phase 04 Plan 03: Vault + Memories + LazyMigration Summary

Firebase Storage-backed DocumentService and MemoryService with Firestore metadata subcollections, plus LazyMigrationService for backfilling pre-migration event data from Supabase.

## What Was Built

### Task 1: Vault + Memories Firebase Migration

- **firebase_storage ^13.2.0** added to pubspec.yaml. `flutter pub get` succeeds.
- **DocumentService** created at `lib/features/vault/services/document_service.dart`. Extends `FirestoreRepository`. Methods: `watchDocuments`, `uploadFile`, `getDownloadUrl`, `deleteDocument`, `pickAndUpload`. Firebase Storage upload via `ref.putFile()`. Firestore metadata written to `groups/{groupId}/events/{eventId}/documents`.
- **Document model** updated with `fromFirestore`/`toFirestore`. `fileUrl` field maps to `storagePath` in Firestore for backward compatibility with screen code.
- **MemoryService** rewritten at `lib/features/memories/services/memory_service.dart`. Extends `FirestoreRepository`. Concrete implementation: `watchMemories`, `uploadPhoto` (ImagePicker → Firebase Storage → Firestore metadata), `deleteMemory`, `getDownloadUrl`. No Supabase imports.
- **Memory model** updated with `fromFirestore`/`toFirestore`. `eventId` maps to `tripId` for screen compatibility.
- **document_provider.dart** rewritten: `eventDocumentsProvider` (StreamProvider.family<List<Document>, EventRef>), deprecated `tripDocumentsProvider` shim.
- **memory_provider.dart** rewritten: `eventMemoriesProvider` (StreamProvider.family<List<Memory>, EventRef>), deprecated `tripMemoriesProvider` shim.
- **vault_screen.dart** and **memories_screen.dart** fixed to use new Firebase API (`getDownloadUrl` instead of `getSignedUrl`, named parameters `groupId`/`eventId` instead of `tripId`).

### Task 2: LazyMigrationService

- **LazyMigrationService** created at `lib/core/services/lazy_migration_service.dart`.
- `migrateModuleIfNeeded(groupId, eventId, bridgeTripId, module)` checks Firestore subcollection emptiness first (skip if non-empty), then reads from Supabase and writes to Firestore via `WriteBatch`.
- Supported modules: `expenses`, `settlements`, `gear_items`, `sub_groups`, `activity_logs`.
- Expense/settlement amounts converted via `MoneySerializer.toSubunits` (snake_case Supabase → camelCase Firestore).
- Non-fatal: all errors caught with `debugPrint`, returns `false` on failure.
- Supabase availability check wrapped in try-catch per Phase 03 decision.

## Tests

| Test File | Tests | Status |
|-----------|-------|--------|
| test/unit/document_service_test.dart | 7 | Passing |
| test/unit/memory_service_test.dart | 7 | Passing |
| test/unit/lazy_migration_service_test.dart | 8 | Passing |
| **Total** | **22** | **All passing** |

## Verification

```
flutter pub get                  -> OK (firebase_storage 13.2.0 installed)
flutter analyze lib/features/vault/ lib/features/memories/ -> no errors
flutter test test/unit/document_service_test.dart -> 7 tests passed
flutter test test/unit/memory_service_test.dart -> 7 tests passed
flutter test test/unit/lazy_migration_service_test.dart -> 8 tests passed
grep -rn 'SupabaseClient' lib/features/vault/services/ lib/features/memories/services/ -> no matches
grep -c 'extends FirestoreRepository' lib/features/vault/services/document_service.dart -> 1
grep -c 'extends FirestoreRepository' lib/features/memories/services/memory_service.dart -> 1
grep -c 'firebase_storage' pubspec.yaml -> 1
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed vault_screen.dart and memories_screen.dart broken API calls**
- **Found during:** Task 1 `flutter analyze`
- **Issue:** Both screens called old Supabase-era APIs that no longer exist: `service.deleteDocument(doc)` (positional arg), `service.uploadPhoto(tripId: ...)` (old param name), `service.getSignedUrl(...)` (renamed to `getDownloadUrl`)
- **Fix:** Updated both screens to use new named parameter signatures. Added deprecated `// ignore:` suppressions for shim providers. Added TODO comments where `groupId` is not yet available from the `Trip` object.
- **Files modified:** `lib/features/vault/screens/vault_screen.dart`, `lib/features/memories/screens/memories_screen.dart`
- **Commit:** 667c7f7

## Known Stubs

The following stubs exist and are intentional — they will be resolved in the EventRef migration plan:

| Location | Stub | Reason |
|----------|------|--------|
| vault_screen.dart:_deleteDocument | `groupId: ''` | Trip-layer screen has no groupId; EventRef migration deferred |
| vault_screen.dart:_uploadDocument | `groupId: ''` | Same |
| memories_screen.dart:_addPhoto | `groupId: ''` | Same — TODO comment added |
| memories_screen.dart:_showFullScreen | `groupId: ''` | Same |
| tripDocumentsProvider | returns `Stream.empty()` | Shim returns empty; migrate callers to eventDocumentsProvider |
| tripMemoriesProvider | returns `[]` | Shim returns empty; migrate callers to eventMemoriesProvider |

These stubs prevent Vault and Memories from showing data in the app until screens are migrated to use EventRef. This is intentional per the phased migration strategy — screens are being migrated in a future plan.

## Commits

| Hash | Message |
|------|---------|
| 667c7f7 | feat(04-03): migrate Vault + Memories to Firebase Storage + Firestore |
| 1376e4e | feat(04-03): add LazyMigrationService for backfilling pre-migration event data |

## Self-Check: PASSED
