# Phase 2: Groups - Research

**Researched:** 2026-03-26
**Domain:** Flutter + Firestore groups feature — create, join, list, member view
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Home Screen Layout**
- D-01: Groups-first home screen. The home screen IS the groups list. No tabs, no split with legacy trips.
- D-02: No legacy trip section needed — starting fresh, no existing trip data to bridge.
- D-03: Group cards show: group name, member count, and user's net balance in the group (shows "0.000 OMR" until Phase 5 populates balances).
- D-04: FAB (Floating Action Button) for create/join actions. Tap opens bottom sheet with "Create Group" and "Join Group" options.

**Member Identity**
- D-05: Self-naming. No pre-populated name list. Each person who joins enters the group with their profile name.
- D-06: Profile name is the existing device name in `settingsProvider` (SharedPreferences). One name, one place. Automatically used when creating or joining any group.
- D-07: Members can change their display name in a group at any time from the group members screen.

**Group Creation Flow**
- D-08: Create group form: group name + currency selection. Creator's display name pulled automatically from device settings.
- D-09: On creation, creator is automatically added as a member with role CREATOR.
- D-10: Invite code generated on creation (6-char alphanumeric, same generation logic as existing trips, excluding confusing chars O/0/I/l).
- D-11: After creation, show the group with a share prompt for the invite code.

**Group Join Flow**
- D-12: Enter 6-char invite code. On valid code, joiner is added to the group with their device profile name and role MEMBER.
- D-13: No name claiming step (unlike trips). Joiner's identity comes from their device settings name.

**Group Detail Screen**
- D-14: Dashboard style. Group name + stats header (member count, creation date) + member list + empty event timeline placeholder.
- D-15: Creator can rename the group from a group settings screen.
- D-16: Group settings screen available: rename group, change currency.
- D-17: No member leaving in Phase 2. Once joined, you're in.
- D-18: No group deletion. Groups are persistent constructs (`allow delete: if false` already in security rules).

**Invite Code Lifecycle**
- D-19: Same 6-char alphanumeric format as existing trip codes. One pattern for the whole app.
- D-20: Permanent code — cannot be regenerated. One code per group, forever.
- D-21: No hard member limit. UI designed/optimized for small friend groups (5-15 people).
- D-22: Two sharing mechanisms: copy to clipboard (with toast) AND native OS share sheet with pre-written message.

### Claude's Discretion
- Group card visual design and layout
- Empty state when user has no groups
- Group detail screen exact layout and spacing
- Event timeline placeholder design
- Settings screen layout
- Share sheet message text
- Error handling and validation UX
- Firestore write batching for group creation (group doc + inviteCode doc + member doc)
- GoRouter route structure for new group screens

### Deferred Ideas (OUT OF SCOPE)
- Member leaving groups — needs product discussion on what happens to their financial history. Future phase.
- D-15 (group delete blocked) revisit — user flagged this for future discussion. May need soft-delete or archive.
- Group admin roles beyond CREATOR — the schema supports roles but Phase 2 only uses CREATOR and MEMBER.
- Invite code regeneration — kept permanent for simplicity, revisit if code leaking becomes a real problem.
- Group avatar/icon selection — not in Phase 2.
- Deep linking to groups — ENH-03 in requirements, separate from Phase 2.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GRP-01 | User can create a group with a name and invite code | Firestore batch write pattern (group + inviteCode doc + member doc); invite code generation from TripService; GroupService mirrors TripService create pattern |
| GRP-02 | User can join a group via invite link or code | inviteCodes collection is publicly readable (security rule confirmed); join = read inviteCode doc → get group → add member doc + update memberIds array atomically |
| GRP-03 | User can see all members in a group | watchGroupMembers StreamProvider.family pattern; Firestore subcollection /groups/{id}/members; SQLite group_members table already exists |
| GRP-06 | User can view list of groups they belong to on home screen | userGroupsProvider StreamProvider that queries Firestore where memberIds arrayContains current UID; replaces userTripsProvider on HomeScreen |
| GRP-07 | Group persists independently of events — members remain even when no active event | Firestore group doc has no event dependency; SQLite groups table has no foreign key to events; allow delete: if false rule already deployed |
</phase_requirements>

---

## Summary

Phase 2 is a greenfield Firestore feature: no Supabase involvement, no legacy data bridging. The data model is already defined (Firestore rules deployed, SQLite v6 schema live) — this phase implements the service layer (GroupService), the repository extensions (watchGroups/saveGroup/watchGroupMembers/saveGroupMember on OfflineRepository), the providers (userGroupsProvider, groupMembersProvider), the screens (CreateGroupScreen, JoinGroupScreen, GroupDetailScreen, GroupSettingsScreen), and replaces the home screen with a groups-first layout.

The dominant technical pattern for this phase is the Firestore batch write for group creation: group document + inviteCodes document + members subcollection document must be written atomically. A partial write (group created but inviteCode doc not written) breaks the join flow. The existing TripService uses sequential Supabase inserts; the Firestore equivalent uses `WriteBatch` or a single batch to guarantee all three documents land or none do.

The Riverpod pattern is `StreamProvider` for the groups list (listening to Firestore snapshot with `arrayContains` on memberIds) and `StreamProvider.family` for group members. Both follow the existing `userTripsProvider` / `tripParticipantsProvider` pattern but drive from Firestore listeners instead of SQLite polling. SQLite is populated as a side effect of the Firestore listener callback, not as the primary write path (confirmed in STATE.md).

**Primary recommendation:** Implement GroupService with a `WriteBatch` for group creation, extend OfflineRepository with group methods, and replace HomeScreen wholesale. Do not retrofit the trip home screen — start fresh.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `cloud_firestore` | `^6.2.0` (in pubspec, confirmed Phase 1) | Group documents, members subcollection, inviteCodes | Already initialized and tested in Phase 1 |
| `firebase_auth` | `^6.3.0` (in pubspec) | Current user UID for memberIds, security rule auth.uid | Already providing anonymous UID since Phase 1 |
| `flutter_riverpod` | `^2.4.9` (in pubspec, stay on 2.x) | StreamProvider for groups list, family for members | All existing providers use this version |
| `sqflite` | `^2.4.2` (in pubspec) | Local groups/group_members cache; SQLite v6 tables already exist | Cache layer for fast reads, offline fallback |
| `go_router` | `^13.2.0` (in pubspec) | Routes for /create-group, /join-group, /group/:id, /group/:id/settings | Already routing all top-level screens |
| `share_plus` | `^10.1.4` (in pubspec) | Native OS share sheet for invite code | Already used in trip export; `Share.share(text)` for plain text |
| `uuid` | `^4.3.3` (in pubspec) | Generate group and member document IDs | Already used in OfflineRepository |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `fake_cloud_firestore` | `^4.1.0+1` (dev dep) | Integration test GroupService without real Firebase | Every test that touches GroupService or group providers |
| `firebase_auth_mocks` | `^0.15.1` (dev dep) | Mock Firebase anonymous user in tests | Tests that read `FirebaseConfig.currentUser?.uid` |
| `mocktail` | `^1.0.4` (dev dep) | Mock OfflineRepository, SettingsService in widget tests | Widget tests for CreateGroupScreen, GroupDetailScreen |
| `sqflite_common_ffi` | `^2.3.4` (dev dep) | In-memory SQLite for unit/integration tests on desktop | All tests that exercise OfflineRepository group methods |
| `flutter_animate` | `^4.5.0` (in pubspec) | List entry animations on groups list, hero transitions | Group cards appearing; match existing home screen animation style |
| `iconsax` | `^0.0.8` (in pubspec) | Icons for group actions, member avatars | Match existing icon set throughout app |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Firestore `WriteBatch` for group creation | Sequential `set()` calls | Sequential writes can leave partial state (group exists, inviteCode doc missing). `WriteBatch` is atomic. Use batch. |
| `arrayContains` query for userGroupsProvider | Separate `groups_I_belong_to` collection | Extra collection adds write complexity. `arrayContains` on memberIds is the canonical Firestore membership pattern. |
| Extending OfflineRepository | Creating a separate GroupRepository | Consistency — all other data flows through OfflineRepository. Adding a parallel class fragments the pattern. Extend the existing class. |

---

## Architecture Patterns

### Recommended Project Structure
```
lib/features/groups/
├── models/
│   ├── group_model.dart         # Group data class with Firestore fromDoc/toDoc
│   └── group_member_model.dart  # GroupMember data class
├── providers/
│   └── group_provider.dart      # All group-related providers + GroupService
├── screens/
│   ├── create_group_screen.dart  # ConsumerStatefulWidget, mirrors CreateTripScreen
│   ├── join_group_screen.dart    # One-step flow (simpler than JoinTripScreen)
│   ├── group_detail_screen.dart  # Dashboard with members + event timeline placeholder
│   └── group_settings_screen.dart # Rename, currency change
└── widgets/
    ├── group_card.dart           # Card shown on HomeScreen
    └── group_member_tile.dart    # Member list item
```

Updates to existing files:
```
lib/features/home/screens/home_screen.dart   # Replace trip list with groups list
lib/core/router/app_router.dart              # Add /create-group, /join-group, /group/:id routes
lib/core/services/offline_repository.dart   # Add watchGroups, saveGroup, watchGroupMembers, saveGroupMember
lib/core/services/cache_service.dart        # Add cacheGroup, getCachedGroups, cacheGroupMember, getCachedGroupMembers
```

### Pattern 1: Firestore WriteBatch for Atomic Group Creation

**What:** Group creation touches three Firestore documents — all must succeed or none.

**When to use:** Any Firestore operation that spans multiple documents and must be atomic.

```dart
// Source: cloud_firestore SDK, WriteBatch documentation
Future<Group?> createGroup({
  required String name,
  required String currency,
}) async {
  final uid = FirebaseConfig.currentUser?.uid;
  if (uid == null) throw Exception('User not authenticated');

  final groupId = const Uuid().v4();
  final memberId = const Uuid().v4();
  final inviteCode = _generateInviteCode();

  final db = FirebaseConfig.firestore;
  final batch = db.batch();

  // Document 1: the group itself
  final groupRef = db.collection('groups').doc(groupId);
  batch.set(groupRef, {
    'id': groupId,
    'name': name,
    'inviteCode': inviteCode,
    'createdBy': uid,
    'memberIds': [uid],           // creator's UID in memberIds immediately
    'currency': currency,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  // Document 2: inviteCodes lookup (publicly readable per security rules)
  final codeRef = db.collection('inviteCodes').doc(inviteCode);
  batch.set(codeRef, {
    'groupId': groupId,
    'createdAt': FieldValue.serverTimestamp(),
  });

  // Document 3: creator as first member in subcollection
  final memberRef = groupRef.collection('members').doc(memberId);
  batch.set(memberRef, {
    'id': memberId,
    'userId': uid,
    'displayName': displayName,    // from settingsProvider
    'role': 'CREATOR',
    'joinedAt': FieldValue.serverTimestamp(),
    'isShadow': false,
  });

  await batch.commit();

  // After Firestore write, cache to SQLite
  // (Firestore SDK cache is the read authority; SQLite is a side effect)
  return Group(id: groupId, name: name, inviteCode: inviteCode, ...);
}
```

### Pattern 2: Join Group — Read inviteCode, Then Atomic Member Add

**What:** Join requires reading the public inviteCode doc (no auth required), then adding the joiner to the group atomically (adds member doc + updates memberIds array).

**When to use:** All join flows.

```dart
// Source: cloud_firestore SDK, arrayUnion documentation
Future<Group?> joinGroup({
  required String inviteCode,
}) async {
  final uid = FirebaseConfig.currentUser?.uid;
  if (uid == null) throw Exception('User not authenticated');

  final db = FirebaseConfig.firestore;

  // Step 1: Look up group by invite code (inviteCodes is publicly readable)
  final codeDoc = await db.collection('inviteCodes').doc(inviteCode.toUpperCase()).get();
  if (!codeDoc.exists) throw Exception('Invalid invite code');

  final groupId = codeDoc.data()!['groupId'] as String;

  // Step 2: Check if already a member (prevent duplicate membership)
  final groupDoc = await db.collection('groups').doc(groupId).get();
  final memberIds = List<String>.from(groupDoc.data()!['memberIds'] as List);
  if (memberIds.contains(uid)) {
    // Already a member — navigate to the group instead of error
    return Group.fromDoc(groupDoc);
  }

  final memberId = const Uuid().v4();
  final batch = db.batch();

  // Add member document
  final memberRef = db.collection('groups').doc(groupId).collection('members').doc(memberId);
  batch.set(memberRef, {
    'id': memberId,
    'userId': uid,
    'displayName': displayName,    // from settingsProvider
    'role': 'MEMBER',
    'joinedAt': FieldValue.serverTimestamp(),
    'isShadow': false,
  });

  // Update memberIds array on group doc (security rules use this for future reads)
  final groupRef = db.collection('groups').doc(groupId);
  batch.update(groupRef, {
    'memberIds': FieldValue.arrayUnion([uid]),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  await batch.commit();

  // Fetch and return updated group
  final updatedDoc = await groupRef.get();
  return Group.fromDoc(updatedDoc);
}
```

### Pattern 3: StreamProvider for Groups List

**What:** Firestore snapshot listener scoped to current user's groups. Uses `arrayContains` on memberIds.

**When to use:** Home screen groups list. Replaces `userTripsProvider` pattern.

```dart
// Source: cloud_firestore SDK, StreamProvider Riverpod 2.x pattern
final userGroupsProvider = StreamProvider<List<Group>>((ref) {
  final uid = FirebaseConfig.currentUser?.uid;
  if (uid == null) return Stream.value([]);

  return FirebaseConfig.firestore
      .collection('groups')
      .where('memberIds', arrayContains: uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(Group.fromDoc).toList());
});

final groupMembersProvider = StreamProvider.family<List<GroupMember>, String>((ref, groupId) {
  return FirebaseConfig.firestore
      .collection('groups')
      .doc(groupId)
      .collection('members')
      .orderBy('joinedAt')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(GroupMember.fromDoc).toList());
});
```

### Pattern 4: OfflineRepository Extension for Groups

**What:** watchGroups() serves from SQLite cache, same pattern as watchTrips().

**When to use:** All group data consumption in providers (if offline fallback from SQLite is needed alongside Firestore stream).

**Note on dual-cache strategy:** Per STATE.md decision: "Firestore SDK cache is the read authority; SQLite populated as side effect of listener events only — never write to SQLite as the primary write path." For Phase 2, the Firestore `StreamProvider` is the primary data source. SQLite caching of groups is a side effect triggered by the Firestore snapshot listener, not by the write path. This means `watchGroups()` from OfflineRepository is used as a *fallback* when the Firestore listener hasn't fired yet (e.g., cold start), not as the primary stream.

```dart
// Extend OfflineRepository — mirror of watchTrips() pattern
Stream<List<Group>> watchGroups() async* {
  yield await CacheService.getCachedGroups();
  yield* _getNotifier('groups').stream
      .asyncMap((_) => CacheService.getCachedGroups());
}

Future<void> saveGroup(Group group) async {
  final db = await LocalDatabase.database;
  await db.insert('groups', {
    'id': group.id,
    'name': group.name,
    'invite_code': group.inviteCode,
    'created_by': group.createdBy,
    'member_ids': jsonEncode(group.memberIds),
    'currency': group.currency,
    'created_at': group.createdAt.toIso8601String(),
    'updated_at': group.updatedAt?.toIso8601String(),
    'synced_at': DateTime.now().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  notifyChange('groups');
}

Stream<List<GroupMember>> watchGroupMembers(String groupId) async* {
  yield await CacheService.getCachedGroupMembers(groupId);
  yield* _getNotifier('group_members:$groupId').stream
      .asyncMap((_) => CacheService.getCachedGroupMembers(groupId));
}

Future<void> saveGroupMember(GroupMember member) async {
  final db = await LocalDatabase.database;
  await db.insert('group_members', {
    'id': member.id,
    'group_id': member.groupId,
    'user_id': member.userId,
    'display_name': member.displayName,
    'role': member.role,
    'is_shadow': member.isShadow ? 1 : 0,
    'joined_at': member.joinedAt.toIso8601String(),
    'synced_at': DateTime.now().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  notifyChange('group_members', groupId);
}
```

### Pattern 5: GoRouter Group Routes

**What:** Four new GoRouter routes, all using slide-up transition (AppBottomSheetRoute pattern).

**When to use:** Navigation to group screens.

```dart
// Add to AppRoutes class constants:
static const String createGroup = '/create-group';
static const String joinGroup = '/join-group';
static const String groupDetail = '/group/:id';
static const String groupSettings = '/group/:id/settings';

// In GoRouter routes list:
GoRoute(
  path: '/create-group',
  pageBuilder: (context, state) => CustomTransitionPage(
    key: state.pageKey,
    child: const CreateGroupScreen(),
    transitionsBuilder: _slideUp,
  ),
),
GoRoute(
  path: '/join-group',
  pageBuilder: (context, state) => CustomTransitionPage(
    key: state.pageKey,
    child: const JoinGroupScreen(),
    transitionsBuilder: _slideUp,
  ),
),
GoRoute(
  path: '/group/:id',
  pageBuilder: (context, state) => CustomTransitionPage(
    key: state.pageKey,
    child: GroupDetailScreen(groupId: state.pathParameters['id']!),
    transitionsBuilder: _slideRight,
  ),
  routes: [
    GoRoute(
      path: 'settings',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: GroupSettingsScreen(groupId: state.pathParameters['id']!),
        transitionsBuilder: _slideRight,
      ),
    ),
  ],
),
```

### Pattern 6: Invite Code Sharing — Clipboard + Share Sheet

**What:** Two share mechanisms from D-22. Clipboard already used in trip_header.dart. Share sheet already used in trip_export_service.dart.

**When to use:** After group creation (in success view) and from group settings/detail.

```dart
// Clipboard copy (from existing home_screen.dart pattern)
await Clipboard.setData(ClipboardData(text: inviteCode));
HapticService.success();
ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(content: Text('Invite code copied!')),
);

// Native share sheet (from existing trip_export_service.dart pattern)
// share_plus is already in pubspec
await Share.share(
  'Join my group on Rihla! Code: $inviteCode',
  subject: 'Join ${group.name}',
);
```

### Anti-Patterns to Avoid

- **Sequential Firestore writes for group creation:** Writing group doc, then inviteCode doc, then member doc as separate `set()` calls can partially fail. Use `WriteBatch`. The batch commits atomically or not at all.
- **Querying groups by invite code with a where clause:** The inviteCodes collection exists specifically as a lookup index. Do NOT do `where('inviteCode', isEqualTo: code)` on the groups collection — that requires a composite index and scans all groups. Read the inviteCodes doc directly by ID.
- **Storing memberIds as a map for security rules:** The current security rules use `request.auth.uid in resource.data.memberIds` which works with an array. The ARCHITECTURE.md research mentions map-based membership but the deployed `firestore.rules` and STATE.md decision (Phase 01-data-foundation D-14) confirm array. Use array. The `in` operator works on arrays in Firestore rules.
- **Driving the home screen from SQLite watchGroups():** The new home screen should drive from the Firestore `userGroupsProvider` (StreamProvider with Firestore listener). SQLite is an offline cache. Use Firestore as the primary stream — it already works offline thanks to SDK persistence.
- **Duplicate membership guard in UI only:** Always check server-side (read groupDoc, check memberIds) before adding a member. UI guards are not sufficient — two devices can join simultaneously.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Atomic multi-document write | Transaction with manual rollback | `WriteBatch` (Firestore SDK) | WriteBatch commits atomically. Manual rollback is error-prone and doesn't handle network failures |
| Invite code uniqueness | Retry loop querying all groups | Write inviteCode doc with `set()` — if the code exists Firestore returns an error; use `create()` semantics via precondition or check inviteCodes collection directly | 32-char alphabet with 6 chars = ~1 billion combinations; collision probability at 10k groups is < 0.001%. But: write the inviteCode as the document ID and handle AlreadyExists as the retry signal |
| Offline write queueing | Custom sync queue for group writes | Firestore SDK offline persistence (already configured with `persistenceEnabled: true` in FirebaseConfig.initialize()) | Phase 1 set `cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED`. Firestore queues writes automatically offline. SyncService is deleted per STATE.md. |
| Membership array update | Manual array read, append, write | `FieldValue.arrayUnion([uid])` | arrayUnion is idempotent and handles concurrent adds without races |
| Native OS share sheet | Custom share dialog | `share_plus` `Share.share(text)` | Already in pubspec; tested in trip_export_service.dart |
| Clipboard copy | Platform channel | `Clipboard.setData(ClipboardData(text: code))` | Already in home_screen.dart; part of Flutter core services |

**Key insight:** Firestore's SDK handles all the hard offline/sync problems that SyncService was solving manually. The only hand-rolled logic needed is the invite code generation (already exists in TripService — extract to a shared utility).

---

## Common Pitfalls

### Pitfall 1: Partial Group Creation (No WriteBatch)

**What goes wrong:** Group document written, then network drops before inviteCode doc is written. The group exists but is unjoinable — the invite code printed on screen doesn't resolve to anything.

**Why it happens:** Instinct from the existing TripService which does sequential Supabase inserts (they're in the same transaction implicitly via PostgreSQL; Firestore has no implicit transactions).

**How to avoid:** Use `WriteBatch` for all three documents (group, inviteCode, creator member doc) in `GroupService.createGroup()`. Batch either fully commits or fully fails — partial state is impossible.

**Warning signs:** Any `GroupService` method that calls `db.collection(...).set()` more than once without a batch.

---

### Pitfall 2: memberIds Array vs Map Confusion

**What goes wrong:** Writing `memberIds` as a Dart `Map` instead of a `List` (array) makes the security rule `request.auth.uid in resource.data.memberIds` fail silently — it returns false for all members.

**Why it happens:** The pre-Phase-2 research documents (ARCHITECTURE.md) described a map-based approach (`members: { uid: role }`), but the deployed security rules (confirmed in `security/firestore.rules`) and STATE.md decision D-14 (Phase 01-data-foundation) use an **array**. The rules file uses `request.auth.uid in resource.data.memberIds` (array `in` operator).

**How to avoid:** Always write `memberIds` as a Dart `List<String>`. When adding members, use `FieldValue.arrayUnion([uid])` to update, not a map merge.

**Warning signs:** Security rules tests fail with "permission denied" even though user is in the group. Check the Firestore document and confirm `memberIds` is a JSON array `[]`, not a map `{}`.

---

### Pitfall 3: Firestore Listener Not Updating After Join

**What goes wrong:** User joins a group, but the groups list on home screen doesn't update to show the new group immediately.

**Why it happens:** `userGroupsProvider` uses `arrayContains: uid` query. When the user joins, `FieldValue.arrayUnion([uid])` updates the group doc. Firestore listeners for `arrayContains` queries DO re-evaluate when the queried document is updated — BUT only if the Firestore listener is active. If the provider was auto-disposed (Riverpod auto-dispose behavior), the listener is torn down and needs to be re-established.

**How to avoid:** Use `keepAlive: true` on `userGroupsProvider` or ensure the HomeScreen keeps the provider alive. Alternatively, invalidate `userGroupsProvider` after a successful join to force a re-fetch:

```dart
ref.invalidate(userGroupsProvider);
```

**Warning signs:** Groups list shows stale data after join. Adding `debugPrint` to the snapshot stream shows no new event fired.

---

### Pitfall 4: Duplicate Join on Double-Tap

**What goes wrong:** User taps "Join" button twice quickly. Two join operations execute concurrently. Both read the group before either updates memberIds. Both pass the "already a member" check. Result: duplicate member documents in the subcollection.

**Why it happens:** Button debouncing not applied. Member uniqueness check is in-memory only, not enforced by Firestore.

**How to avoid:** Two layers:
1. Disable the join button while the operation is in-flight (use `isLoadingProvider` StateProvider pattern, same as tripLoadingProvider).
2. The `FieldValue.arrayUnion([uid])` call on memberIds is idempotent (adding same UID twice has no effect). For the member subcollection doc, use the Firebase UID as the document ID rather than a UUID: `members/{uid}`. Then concurrent writes upsert the same document rather than creating duplicates.

**Warning signs:** `group_members` subcollection has two documents with the same `userId`.

---

### Pitfall 5: inviteCode Case Sensitivity

**What goes wrong:** User types invite code in lowercase or mixed case. Lookup against inviteCodes collection fails because the document ID is uppercase.

**Why it happens:** The existing `_generateInviteCode()` in TripService generates uppercase codes. The document ID in inviteCodes is the code itself. If the join lookup does `inviteCodes.doc(userInput)` without normalizing case, lowercase input misses.

**How to avoid:** Always normalize the invite code to uppercase before any Firestore lookup:

```dart
final normalizedCode = inviteCode.trim().toUpperCase();
final codeDoc = await db.collection('inviteCodes').doc(normalizedCode).get();
```

The existing JoinTripScreen already does `_codeController.text.trim().toUpperCase()` — carry this pattern into JoinGroupScreen.

**Warning signs:** "Invalid invite code" error when the code is visually correct but entered lowercase.

---

### Pitfall 6: GoRouter Path Parameter Extraction

**What goes wrong:** GroupDetailScreen receives groupId via route parameter, but the parameter key name in `path: '/group/:id'` doesn't match the extraction key `state.pathParameters['groupId']`.

**Why it happens:** Typo in path parameter name (`':id'` vs `':groupId'`).

**How to avoid:** Use a consistent naming convention. Prefer `':groupId'` as the path parameter name so extraction is self-documenting:

```dart
// Define:
path: '/group/:groupId'
// Extract:
groupId: state.pathParameters['groupId']!
```

**Warning signs:** `state.pathParameters['groupId']` returns null; app crashes with null assertion.

---

## Code Examples

Verified patterns from existing codebase:

### Invite Code Generation (from TripService — exact chars to reuse)
```dart
// Source: lib/features/trip/providers/trip_provider.dart:78-82
// Extract this to a shared utility: lib/core/utils/invite_code_generator.dart
String generateInviteCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Removed O/0/I/l
  final random = Random.secure();
  return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
}
```

### OfflineRepository notifyChange with table+groupId
```dart
// Source: lib/core/services/offline_repository.dart:43-51
// The notifyChange method already handles table-level and table+key-level notification.
// For groups, pass groupId as the second argument:
void notifyChange(String table, [String? tripId]) {
  // This method already exists — pass groupId as tripId argument
  // notifyChange('group_members', groupId) → notifies 'group_members:${groupId}'
}
```

### ConsumerStatefulWidget with loading/error StateProviders
```dart
// Source: lib/features/trip/screens/create_trip_screen.dart:14-86
// Exact pattern to mirror for CreateGroupScreen:
// - ConsumerStatefulWidget + ConsumerState
// - _formKey = GlobalKey<FormState>()
// - WidgetsBinding.instance.addPostFrameCallback to read settingsProvider
// - Call service via ref.read(groupServiceProvider)
// - Check ref.read(groupLoadingProvider) / ref.read(groupErrorProvider)
```

### RefreshIndicator on groups list
```dart
// Source: lib/features/home/screens/home_screen.dart:69-73
// Exact pattern for the new home screen groups list:
RefreshIndicator(
  onRefresh: () async {
    ref.invalidate(userGroupsProvider);
  },
  color: AppColors.primary,
  child: _buildContent(context, ref, groups),
),
```

### FieldValue.arrayUnion for memberIds update
```dart
// Source: cloud_firestore SDK (confirmed via pubspec ^6.2.0)
// Used in joinGroup batch:
batch.update(groupRef, {
  'memberIds': FieldValue.arrayUnion([uid]),
  'updatedAt': FieldValue.serverTimestamp(),
});
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Supabase sequential inserts for trip creation | Firestore WriteBatch for atomic group creation | Phase 2 (this phase) | Eliminates partial-write state |
| `userTripsProvider` driving home screen from SQLite | `userGroupsProvider` driving home screen from Firestore stream | Phase 2 (this phase) | Firestore SDK cache handles offline automatically |
| Two-step join (code entry + name claim) | One-step join (code entry only, name from device settings) | Phase 2 design decision | Simpler UX; identity comes from device profile |
| SyncService polling for realtime updates | Firestore `snapshots()` stream | Phase 2 starts this; Phase 4 completes migration | No polling; Firestore pushes changes |

**Deprecated/outdated patterns for this phase:**
- `userTripsProvider`: home screen will no longer watch this; it watches `userGroupsProvider`
- `tripSeedProvider` (FutureProvider that seeds SQLite from Supabase on home screen load): not used for groups; the groups home screen seeds from Firestore listener, not from Supabase

---

## Open Questions

1. **inviteCode document ID uniqueness strategy at scale**
   - What we know: 32-char alphabet, 6 chars = ~1.07 billion combinations. Collision at 10,000 groups is < 0.001%.
   - What's unclear: Whether to retry on collision (check `AlreadyExists` exception from batch commit) or pre-check inviteCodes collection.
   - Recommendation: Use the same retry pattern as TripService (generate → check inviteCodes doc existence → retry if exists). At this group scale, 1-2 attempts are sufficient. Cap at 5 retries with an error state.

2. **Firestore listener vs SQLite for home screen data source**
   - What we know: STATE.md locks in "Firestore SDK cache is the read authority." userGroupsProvider should use Firestore `snapshots()`.
   - What's unclear: Whether to also populate SQLite groups table as a side-effect of the Firestore listener (for future offline balance queries in Phase 5).
   - Recommendation: Yes, populate SQLite as a side effect of the snapshot callback. Do it in the GroupService/provider layer, not in the write path. This mirrors how Phase 4 will handle all data.

3. **GroupDetail navigation: GoRouter vs Navigator.push**
   - What we know: CLAUDE.md documents that CommandCenter and all feature screens below it use Navigator.push, not GoRouter. GroupDetail is analogous to CommandCenter.
   - What's unclear: Whether to follow the same pattern or start GroupDetail on GoRouter (enabling deep links later per ENH-03).
   - Recommendation: Put GroupDetail on GoRouter since the route is simple (`/group/:groupId`) and enables ENH-03 without a refactor. Use `AppPageRoute` slide transition via the `pageBuilder` pattern already in app_router.dart.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (SDK built-in) |
| Config file | None — uses default Flutter test runner |
| Quick run command | `flutter test test/unit/ test/features/ --no-pub` |
| Full suite command | `flutter test --no-pub` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GRP-01 | Group creation writes group + inviteCode + member docs atomically | Integration | `flutter test test/integration/group_creation_test.dart -x --no-pub` | ❌ Wave 0 |
| GRP-01 | GroupModel serializes/deserializes Firestore doc correctly | Unit | `flutter test test/unit/group_model_test.dart -x --no-pub` | ❌ Wave 0 |
| GRP-02 | Join by invite code adds member doc + updates memberIds | Integration | `flutter test test/integration/group_join_test.dart -x --no-pub` | ❌ Wave 0 |
| GRP-02 | Join with invalid code returns error | Integration | (same file, separate test case) | ❌ Wave 0 |
| GRP-02 | Join when already a member navigates to group, no duplicate | Integration | (same file, separate test case) | ❌ Wave 0 |
| GRP-03 | GroupMembersProvider streams members from Firestore subcollection | Integration | `flutter test test/integration/group_members_test.dart -x --no-pub` | ❌ Wave 0 |
| GRP-06 | userGroupsProvider streams only groups where user is a member | Integration | `flutter test test/integration/user_groups_provider_test.dart -x --no-pub` | ❌ Wave 0 |
| GRP-06 | HomeScreen renders group cards list | Widget | `flutter test test/features/home_screen_groups_test.dart -x --no-pub` | ❌ Wave 0 |
| GRP-07 | Group persists with no events (no foreign key constraint) | Unit | `flutter test test/unit/group_model_test.dart -x --no-pub` | ❌ Wave 0 (same file as GRP-01 model test) |

### Sampling Rate
- **Per task commit:** `flutter test test/unit/ --no-pub`
- **Per wave merge:** `flutter test --no-pub`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/integration/group_creation_test.dart` — covers GRP-01 Firestore atomic write
- [ ] `test/integration/group_join_test.dart` — covers GRP-02 join flow (valid, invalid, duplicate)
- [ ] `test/integration/group_members_test.dart` — covers GRP-03 members stream
- [ ] `test/integration/user_groups_provider_test.dart` — covers GRP-06 filtered groups list
- [ ] `test/unit/group_model_test.dart` — covers GRP-01/GRP-07 model serialization + event-independence
- [ ] `test/features/home_screen_groups_test.dart` — covers GRP-06 widget rendering

All integration tests MUST use `FakeFirebaseFirestore` (already in dev deps) and `MockFirebaseAuth` from `firebase_auth_mocks`. `sqflite_common_ffi` for any test that exercises OfflineRepository group methods.

---

## Sources

### Primary (HIGH confidence)
- `security/firestore.rules` — Confirmed: memberIds is array, `in` operator, inviteCodes public read, group delete blocked
- `lib/core/services/local_database.dart:204-281` — Confirmed: groups, group_members, group_ledger table schemas, indexes
- `.planning/STATE.md` — Confirmed: Firestore SDK cache is read authority, SQLite is side-effect, memberIds is array (D-14)
- `.planning/research/ARCHITECTURE.md` — Firestore collection structure, batch write patterns, memberIds security pattern
- `.planning/research/PITFALLS.md` — WriteBatch necessity, arrayUnion idempotency, double-join race condition patterns
- `lib/core/config/firebase_config.dart` — Confirmed: FirebaseFirestore initialized with `persistenceEnabled: true`
- `lib/features/trip/providers/trip_provider.dart:78-82` — Confirmed: invite code generation logic (exact chars to reuse)
- `pubspec.yaml` — Confirmed: all package versions, share_plus present, fake_cloud_firestore in dev deps
- `test/integration/firebase_money_roundtrip_test.dart` — Confirmed: FakeFirebaseFirestore integration test pattern works (tests pass)

### Secondary (MEDIUM confidence)
- `lib/features/home/screens/home_screen.dart` — Clipboard.setData pattern and home screen structure to replace
- `lib/features/trip/services/trip_export_service.dart` — Share.share() call pattern for share sheet

### Tertiary (LOW confidence)
- None — all findings verified against in-repo source files

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages confirmed in pubspec.yaml with versions
- Architecture: HIGH — Firestore rules confirmed, data model confirmed in SQLite schema, patterns confirmed from existing service code
- Pitfalls: HIGH — WriteBatch necessity confirmed from architecture research; memberIds array vs map confirmed from deployed rules; other pitfalls derived from existing codebase patterns
- Test patterns: HIGH — fake_cloud_firestore integration test pattern confirmed working (tests pass)

**Research date:** 2026-03-26
**Valid until:** 2026-04-26 (stable libraries, rules already deployed; no fast-moving dependencies)
