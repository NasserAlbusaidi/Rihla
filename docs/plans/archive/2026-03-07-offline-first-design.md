# Offline-First Architecture Design

## Goal

Make Rihla work fully offline by using SQLite as the single source of truth, with Supabase as a background sync target. Eliminate all "connection lost" error pages.

## Architecture

**Data flow:**
- READS: UI -> Provider -> SQLite (always, instant)
- WRITES: UI -> Provider -> SQLite (immediate) -> SyncQueue -> Supabase (when online)
- SYNC: Supabase -> SQLite (background download on connectivity)

**Key principle:** The UI never talks to Supabase directly. Providers read from SQLite and return data instantly. A background sync engine handles pushing local changes up and pulling remote changes down.

## SQLite Schema Changes

Expand the local database to cache all feature data:

| Table | Status | Notes |
|-------|--------|-------|
| trips | Exists | No change |
| expenses | Exists | No change |
| settlements | Exists | No change |
| gear_items | Exists | No change |
| sync_queue | Exists | Add retry_count, last_error, conflict_data columns |
| participants | New | Trip members + display names |
| sub_groups | New | Sub-group definitions |
| sub_group_members | New | Sub-group membership |
| activity_logs | New | Activity feed cache |
| categories | New | Expense categories |

**Not cached:** Documents/vault (binary files too large), memories (photo-heavy). These show "unavailable offline" instead of error pages.

Every cached table gets a `last_synced_at` timestamp for incremental sync.

## Sync Engine

One `SyncEngine` class with three jobs:

### 1. Push (upload local changes)
- Triggered on connectivity change (offline -> online)
- Process sync queue items sequentially
- On success: remove from queue
- On conflict: last-write-wins using `updated_at` timestamps, log conflict to activity
- On failure: increment retry_count, store last_error, skip to next
- Items with 5+ retries flagged but not discarded

### 2. Pull (download remote changes)
- Runs after push completes
- Uses `last_synced_at` for incremental fetches (not full download)
- Writes to SQLite, updates `last_synced_at`

### 3. Real-time listener (live updates while online)
- Keep existing Supabase real-time streams
- Change target: stream -> write to SQLite (not directly to UI)
- Providers reactively watch SQLite, so UI updates automatically

### Sync triggers
- Connectivity: offline -> online
- App resume from background
- Manual pull-to-refresh
- Periodic: every 5 minutes while online

### Notifications
- Brief toast: "X changes synced" after push completes (auto-dismiss)

## Provider Refactor

Every feature provider changes from streaming Supabase to watching SQLite:

```dart
// OLD: Stream from Supabase, cache as side effect
final tripExpensesProvider = StreamProvider.family((ref, tripId) {
  return supabase.from('expenses').stream(...)
    .asyncMap((data) async {
      await CacheService.cacheExpenses(tripId, expenses);
      return expenses;
    })
    .handleError((e) => CacheService.getCachedExpenses(tripId));
});

// NEW: Read from SQLite always. Sync engine keeps it fresh.
final tripExpensesProvider = StreamProvider.family((ref, tripId) {
  return ref.read(offlineRepositoryProvider).watchExpenses(tripId);
});
```

### OfflineRepository

Wraps SQLite with reactive streams. Provides:
- `watchExpenses(tripId)`, `watchGearItems(tripId)`, `watchParticipants(tripId)`, etc.
- `addExpense(expense)` — writes to SQLite + adds to sync queue
- `updateExpense(expense)` — same pattern
- `deleteExpense(id)` — soft delete in SQLite + queue

## Conflict Resolution

- Strategy: Last-write-wins using `updated_at` timestamps
- Conflicts logged to activity (visible but not disruptive)
- No user-facing conflict dialogs

## Error Page Elimination

1. Cached features (expenses, gear, sub-groups, etc.): No error pages possible — data always from SQLite
2. Non-cached features (documents, memories): Replace error/crash with "unavailable offline" empty state using EmptyStateView

## Constraints

- No queue size limits — trust the user
- No background sync while app is closed (add later if easy)
- No hard offline indicators that block usage

## Features Affected

| Feature | Offline Reads | Offline Writes |
|---------|--------------|----------------|
| Trips | Yes (cached) | Yes (create/update queued) |
| Expenses | Yes (cached) | Yes (add/edit/delete queued) |
| Settlements | Yes (cached) | Yes (create queued) |
| Gear | Yes (new cache) | Yes (add/claim/pack/delete queued) |
| Sub-groups | Yes (new cache) | Yes (create/update queued) |
| Activity | Yes (new cache) | No (server-side triggers) |
| Participants | Yes (new cache) | Read-only offline |
| Documents | No — "unavailable offline" | No |
| Memories | No — "unavailable offline" | No |
