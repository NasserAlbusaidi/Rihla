# Phase 29: Group Management - Research

**Researched:** 2026-04-02
**Domain:** Flutter GroupSettingsScreen refactor — ProfileScreen visual pattern, Firestore leave/delete/remove operations, balance-gated member removal
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Visual polish of existing settings (name, currency, invite code) plus two new actions: leave group and delete group. No module toggles this phase.
- **D-02:** Leave group available to any member. Delete group available to creator only.
- **D-03:** Both leave and delete require confirmation dialog before executing.
- **D-04:** Members section lives inside GroupSettingsScreen as a new section — not a separate screen.
- **D-05:** Creator gets a visible "Creator" badge/chip next to their name in the member list.
- **D-06:** Creator can remove members from the group via the member list.
- **D-07:** Leave/remove is blocked if the member has a non-zero balance. User must settle up first. Show a clear message explaining why and link to settle-up.
- **D-08:** Follow Phase 26 ProfileScreen pattern exactly: grouped sections as separate widgets, uppercase section headers (icon + `letterSpacing: 1.5` + `textSecondary`), card containers with `cardSurface` bg + `raised` shadow + `borderRadius: 24`, staggered `.animate().fadeIn().slideY()` entrance.
- **D-09:** Horizontal padding 24px (matching ProfileScreen, not 16px from GroupDetailScreen).
- **D-10:** Skeleton loading on initial load, inline error with retry on failure (same pattern as Phase 28).
- **D-11:** Invite code section already exists in GroupSettingsScreen — visual polish only (apply card container pattern from D-08). No functional changes to copy/share behavior.

### Claude's Discretion

- Specific icon choices for section headers and member list items
- Exact layout of the member list within the card (ListTile vs custom Row)
- Confirmation dialog styling (AlertDialog vs BottomSheet)
- Animation delay values for stagger entrance
- How the "settle up first" blocking message is presented (inline text vs dialog)

### Deferred Ideas (OUT OF SCOPE)

- **Module toggles** — Let creator enable/disable event modules at group level.
- **Share invite via sheet** — Deep links, QR codes, or share sheet for invite codes.
</user_constraints>

---

## Summary

Phase 29 is a visual refresh and functional extension of `GroupSettingsScreen`. The screen currently has a plain `ListView` with `ListTile` items and a bare `AppBar`. This phase replaces that with the ProfileScreen section pattern (three separate section widgets, stagger animations, card containers) and adds two new sections: a member list with creator badge and remove capability, and a danger zone with leave/delete group actions.

The core complexity is not in Flutter widget patterns — those are fully established by Phase 26 and documented in UI-SPEC.md. The complexity lives in three areas: (1) the Firestore write operations for leave/remove/delete, (2) the balance check gate for remove/leave, and (3) test coverage for the new screen structure.

**All Firestore operations required (leave, remove, delete) must be written as new methods on `GroupService`** — none exist today. The `WriteBatch` pattern for atomic multi-doc writes is already established in `createGroup` and the delete operation requires cascade deletion across subcollections (Firestore does not auto-delete subcollections on parent document deletion).

**Primary recommendation:** Build three section widgets following `ProfileAboutSection` exactly (tile pattern, section header, card container), add `leaveGroup`, `removeMember`, and `deleteGroup` to `GroupService`, and test via provider overrides consistent with the existing `group_screens_test.dart` pattern.

---

## Standard Stack

### Core (all already in pubspec.yaml — no new dependencies)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter_animate` | `^4.5.0` | Stagger entrance animations on section widgets | Already installed — `.animate().fadeIn().slideY()` is the project-standard micro-interaction pattern, used in ProfileScreen |
| `iconsax` | `^0.0.8` | Section header icons, tile leading icons | Already installed — project primary icon library |
| `flutter_riverpod` | `^2.6.1` | Provider watches for group data, members, balances | Already installed — project state management |
| `cloud_firestore` | installed | Firestore writes for leave/remove/delete | Already installed — Firebase backend |
| `shimmer` | `^3.0.0` | Skeleton loading via `SkeletonLoader` shared widget | Already installed — `SkeletonLoader.generic()` covers settings card skeletons |

**No new packages required for this phase.**

### Supporting Widgets (reuse from existing codebase)

| Widget | Path | Purpose |
|--------|------|---------|
| `InitialsCircle` | `lib/shared/widgets/initials_circle.dart` | Member list avatar (36dp size) |
| `SkeletonLoader` | `lib/shared/widgets/skeleton_loader.dart` | Loading state for sections |
| `HapticService` | `lib/core/services/haptic_service.dart` | Haptic on tile taps, confirmations |
| `InviteCodeDisplay` | `lib/features/groups/widgets/invite_code_display.dart` | Optional reuse inside invite code tile — or inline, Claude's discretion |

---

## Architecture Patterns

### Recommended File Structure

```
lib/features/groups/
  screens/
    group_settings_screen.dart      # refactored — remove AppBar, add scroll layout
  widgets/
    group_info_section.dart         # NEW — name, currency, invite code
    group_members_section.dart      # NEW — member list with badge + remove
    group_danger_section.dart       # NEW — leave + delete actions
  providers/
    group_provider.dart             # ADD leaveGroup(), removeMember(), deleteGroup() to GroupService
  keys/
    group_keys.dart                 # ADD new keys (see Test Key Contract section)

test/features/groups/
  group_settings_screen_test.dart   # NEW test file for Phase 29
```

### Pattern 1: Section Widget (replicate ProfileAboutSection exactly)

Each of the three new section widgets follows this structure. Source: `lib/features/settings/widgets/profile_about_section.dart`.

```dart
// Source: lib/features/settings/widgets/profile_about_section.dart
class GroupInfoSection extends ConsumerWidget {
  const GroupInfoSection({super.key, required this.group, required this.isCreator});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(),          // icon(16dp) + SizedBox(6) + uppercase label
        const SizedBox(height: 8),
        Container(                       // card container
          decoration: BoxDecoration(
            color: AppColorTokens.light.cardSurface,
            borderRadius: BorderRadius.circular(16),  // radiusLarge — matches actual code
            boxShadow: AppShadowTokens.standard.raised,
          ),
          child: Column(
            children: [
              _buildTile(...),
              Divider(height: 1, color: AppColorTokens.light.inputFill),
              _buildTile(...),
            ],
          ),
        ),
      ],
    );
  }
}
```

**Critical detail:** D-08 in CONTEXT.md says `borderRadius: 24` but the actual ProfileScreen implementation uses `BorderRadius.circular(16)`. The UI-SPEC confirms: follow the code, not the aspirational description. Use `BorderRadius.circular(16)`.

### Pattern 2: GroupSettingsScreen Layout (replicate ProfileScreen)

```dart
// Source: lib/features/settings/screens/profile_screen.dart
Scaffold(
  backgroundColor: AppColorTokens.light.scaffoldBackground,
  body: SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),  // D-09: 24px not 16px
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            _buildBackButton(context),   // inline back button, no AppBar
            const SizedBox(height: 16),
            GroupInfoSection(...).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),
            const SizedBox(height: 16),
            GroupMembersSection(...).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
            const SizedBox(height: 16),
            GroupDangerSection(...).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
            const SizedBox(height: 32),
          ],
        ),
      ),
    ),
  ),
)
```

**Remove the existing `AppBar`** — ProfileScreen uses an inline back button built with a `Container` + `IconButton`. GroupSettingsScreen must match this pattern.

### Pattern 3: Tile Pattern (replicate ProfileAboutSection._buildTile)

```dart
// Source: lib/features/settings/widgets/profile_about_section.dart lines 112-159
GestureDetector(
  key: tileKey,
  onTap: onTap,
  behavior: HitTestBehavior.opaque,
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppColorTokens.light.inputFill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: Icon(icon, size: 18, color: AppColorTokens.light.textSecondary)),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text(title, style: /* 14sp, w500, textPrimary */)),
        trailing,
      ],
    ),
  ),
)
```

### Pattern 4: Firestore Leave Group

Leave group requires two atomic writes — remove from `memberIds` array and soft-delete the member document. **Firestore does not support `arrayRemove` + subcollection delete in a single batch for the member doc**, so the approach is:

```dart
// NEW method on GroupService
Future<void> leaveGroup({required String groupId}) async {
  final uid = FirebaseConfig.currentUser?.uid;
  if (uid == null) throw Exception('Not authenticated');

  // Find member document for this user
  final membersSnap = await db
      .collection('groups')
      .doc(groupId)
      .collection('members')
      .where('userId', isEqualTo: uid)
      .limit(1)
      .get();

  if (membersSnap.docs.isEmpty) throw Exception('Member not found');
  final memberDocId = membersSnap.docs.first.id;

  // Atomic batch: remove from memberIds + delete member document
  final batch = db.batch();
  batch.update(db.collection('groups').doc(groupId), {
    'memberIds': FieldValue.arrayRemove([uid]),
    'updatedAt': FieldValue.serverTimestamp(),
  });
  batch.delete(db.collection('groups').doc(groupId).collection('members').doc(memberDocId));
  await batch.commit();
}
```

**Confidence: HIGH** — `FieldValue.arrayRemove` is the Firestore standard for removing a UID from an array field. Verified from existing `joinGroup` which uses the inverse `FieldValue.arrayUnion`.

### Pattern 5: Firestore Remove Member (creator removes another member)

Identical to leaveGroup but targets a different userId:

```dart
// NEW method on GroupService
Future<void> removeMember({
  required String groupId,
  required String memberId,   // the member document ID (not userId)
  required String userId,     // the user's UID to remove from memberIds
}) async {
  final batch = db.batch();
  batch.update(db.collection('groups').doc(groupId), {
    'memberIds': FieldValue.arrayRemove([userId]),
    'updatedAt': FieldValue.serverTimestamp(),
  });
  batch.delete(db.collection('groups').doc(groupId).collection('members').doc(memberId));
  await batch.commit();
}
```

### Pattern 6: Firestore Delete Group (cascade)

**Critical pitfall:** Firestore does NOT auto-delete subcollections when a parent document is deleted. The delete operation must explicitly delete: the group document, all member documents in the `members` subcollection, and the invite code lookup document. Events and their subcollections are out of scope per D-01 (no cascade event deletion specified). However, the group document deletion means the group is inaccessible — events without a parent group will be orphaned but not surfaced.

```dart
// NEW method on GroupService
Future<void> deleteGroup({required String groupId}) async {
  // Step 1: Fetch members subcollection to delete each doc
  final membersSnap = await db
      .collection('groups')
      .doc(groupId)
      .collection('members')
      .get();

  // Step 2: Fetch the group to get invite code for cleanup
  final groupDoc = await db.collection('groups').doc(groupId).get();
  final inviteCode = (groupDoc.data()?['inviteCode'] as String?);

  // Step 3: Atomic batch delete
  // Note: Firestore batch limit is 500 operations.
  // For a group with <498 members, this fits in one batch.
  final batch = db.batch();
  for (final memberDoc in membersSnap.docs) {
    batch.delete(memberDoc.reference);
  }
  batch.delete(db.collection('groups').doc(groupId));
  if (inviteCode != null) {
    batch.delete(db.collection('inviteCodes').doc(inviteCode));
  }
  await batch.commit();
}
```

**Confidence: HIGH** — Firestore batch operation limit is 500 writes per batch (verified from Firebase documentation). Groups with >497 members would overflow a single batch; this is an edge case not worth handling now but worth noting.

### Pattern 7: Balance Check Gate (D-07)

`groupBalancesProvider` returns `AsyncValue<GroupBalances>` which includes `balances: List<UserBalance>`. To check if a specific member has a non-zero balance:

```dart
// Inside GroupMembersSection
final balancesAsync = ref.watch(groupBalancesProvider(groupId));
final balances = balancesAsync.valueOrNull?.balances ?? [];
final memberBalance = balances
    .where((b) => b.participantId == member.userId)
    .firstOrNull;
final hasBalance = memberBalance != null &&
    memberBalance.netBalance != Decimal.zero;
```

`Decimal.zero` is the correct comparison — the project uses `package:decimal` for all money math (CLAUDE.md). Never use `== 0.0` with Decimal.

### Pattern 8: Test Provider Override (consistent with existing tests)

From `group_screens_test.dart`, the GroupSettingsScreen test in Phase 29 must override:
- `sharedPreferencesProvider` — required by `settingsProvider`
- `currentUserIdProvider` — controls isCreator checks
- `groupDetailProvider(groupId)` — group data
- `groupMembersProvider(groupId)` — member list
- `groupBalancesProvider(groupId)` — for balance gate testing

```dart
// Source pattern: test/features/groups/group_screens_test.dart
ProviderScope(
  overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    currentUserIdProvider.overrideWithValue('uid-creator'),
    groupDetailProvider('group-1').overrideWith((ref) => Stream.value(_testGroup)),
    groupMembersProvider('group-1').overrideWith((ref) => Stream.value(_testMembers)),
    groupBalancesProvider('group-1').overrideWith((ref) => AsyncValue.data(_membersWithZeroBalance)),
  ],
  child: MaterialApp(home: GroupSettingsScreen(groupId: 'group-1')),
)
```

### Anti-Patterns to Avoid

- **Do not use `AppBar` in the refreshed screen** — ProfileScreen uses an inline back button. GroupSettingsScreen must remove the existing AppBar.
- **Do not use `Divider(color: AppColorTokens.light.border)`** — tiles inside a card use `Divider(height: 1, color: AppColorTokens.light.inputFill)` (inputFill not border). Source: ProfileAboutSection line 57.
- **Do not use `BorderRadius.circular(24)` for card containers** — D-08 says 24 but all actual ProfileScreen widgets use 16. Follow the code.
- **Do not mutate the `Group.memberIds` list directly** — all updates go through `FieldValue.arrayRemove` on Firestore. Local state is driven by the `groupDetailProvider` stream.
- **Do not delete the group document first** — delete member docs first (or in the same batch), then the group doc. Firestore RLS on `members` subcollection requires `isGroupMember()` which reads the group document — if the group doc is deleted first, subsequent member reads fail.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Stagger animations | Manual `Future.delayed` + `setState` | `flutter_animate` `.animate().fadeIn(delay: X.ms).slideY()` | Already in pubspec, established in ProfileScreen. Manual delays are error-prone and harder to test. |
| Section header widget | Inline Row with text | Extract `_buildSectionHeader()` private method per section widget | ProfileScreen pattern. Keeps section widgets cohesive. |
| Atomic Firestore multi-doc writes | Sequential `await update(); await delete();` | `WriteBatch` — `db.batch()` + `batch.commit()` | Non-atomic sequential writes leave partial state on network failure. `WriteBatch` is already used in `createGroup` and `joinGroup`. |
| Firestore array removal | Load array, filter, re-write | `FieldValue.arrayRemove([uid])` | `arrayRemove` is atomic at the field level. Manual re-write creates a race condition with concurrent members joining. |
| Loading skeleton | Custom duplicate layout | `SkeletonLoader.generic(count: 2)` | Already in `lib/shared/widgets/skeleton_loader.dart`. Three generic cards adequately represent the three section stubs during load. |

---

## Common Pitfalls

### Pitfall 1: Firestore Subcollection Cascade
**What goes wrong:** Deleting the group document leaves `members` subcollection documents orphaned — they're still readable and billable until explicitly deleted.
**Why it happens:** Firestore does not cascade deletes to subcollections. This is a documented Firestore design decision.
**How to avoid:** `deleteGroup` must explicitly query and batch-delete all `members` subcollection documents before or alongside the group document deletion.
**Warning signs:** After a "delete group" flow, a fresh Firestore console shows the group doc is gone but the `members` subcollection still exists under the deleted document's path.

### Pitfall 2: RLS Read Failure After Group Doc Deletion
**What goes wrong:** If the group document is deleted first, any subsequent Firestore read that hits `isGroupMember()` (which reads the group's `memberIds`) fails with permission denied.
**Why it happens:** The security rule checks `get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds.hasAny([request.auth.uid])`. If the group doc is gone, `get()` returns null and the hasAny check throws.
**How to avoid:** In `deleteGroup`, use a single WriteBatch that deletes member documents AND the group document simultaneously. The batch commit is atomic — no intermediate state.

### Pitfall 3: Decimal Zero Comparison
**What goes wrong:** `memberBalance.netBalance == 0` or `memberBalance.netBalance == 0.0` fails with `Decimal` type — Dart's `==` on `Decimal` is defined correctly but using numeric literals creates implicit `int`/`double` comparisons that don't compile.
**Why it happens:** `Decimal` is not a primitive type. Comparison must use `Decimal.zero`.
**How to avoid:** Always `memberBalance.netBalance != Decimal.zero`. Source: CLAUDE.md financial precision rule.

### Pitfall 4: onTap Callback Async in Tests
**What goes wrong:** Tapping a tile in a test hangs or causes `pumpAndSettle` timeout if the `onTap` handler is `async` and performs Firestore calls.
**Why it happens:** Phase 26 P01 decisions document: "onChanged/onTap must be synchronous for test compatibility: pumpAndSettle cannot await async callbacks".
**How to avoid:** For tile taps that trigger async operations (save, leave, delete), fire-and-forget: `onTap: () { HapticService.selection(); _doLeaveGroup(); }` where `_doLeaveGroup` is a private `async` method called without `await`. Tests verify the UI state change (dialog appearing, navigation), not the async completion.

### Pitfall 5: Missing Provider Override in Tests
**What goes wrong:** `GroupSettingsScreen` in test throws `ProviderException` or renders error state because a required provider isn't overridden.
**Why it happens:** The new screen watches `groupMembersProvider` and `groupBalancesProvider` in addition to the existing `groupDetailProvider`. Tests that worked before Phase 29 won't have these overrides.
**How to avoid:** The test `_wrap` helper must include all five overrides: `sharedPreferencesProvider`, `currentUserIdProvider`, `groupDetailProvider`, `groupMembersProvider`, `groupBalancesProvider`. Update `group_screens_test.dart`'s `_wrap` function before writing Phase 29 tests.

### Pitfall 6: AppBar Removal Breaking Navigation Test
**What goes wrong:** Existing test `'shows Group Settings appbar title'` finds `GroupKeys.settingsTitle` on the AppBar. After removing the AppBar, this test fails — the title key no longer exists.
**Why it happens:** The current `GroupSettingsScreen` has an `AppBar` with `title: const Text('Group Settings', key: GroupKeys.settingsTitle)`. The new layout removes the AppBar.
**How to avoid:** Update the existing test to assert the back button is present (`GroupKeys.settingsBackButton`) rather than the AppBar title. The `settingsTitle` key is no longer applicable and should be removed from `GroupKeys` or left unused.

---

## Code Examples

### Section Header Pattern
```dart
// Source: lib/features/settings/widgets/profile_about_section.dart lines 90-109
Widget _buildSectionHeader() {
  return Row(
    children: [
      Icon(
        Iconsax.info_circle,    // replace with section-specific icon
        size: 16,
        color: AppColorTokens.light.textSecondary,
      ),
      const SizedBox(width: 6),
      Text(
        'ABOUT',                // replace with section label in UPPERCASE
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColorTokens.light.textSecondary,
          letterSpacing: 1.5,
        ),
      ),
    ],
  );
}
```

### Creator Badge
```dart
// Source: UI-SPEC.md GroupMembersSection spec
Widget _buildCreatorBadge() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColorTokens.light.selectionFill,   // #E6F5F3
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      'Creator',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColorTokens.light.primary,
      ),
    ),
  );
}
```

### Danger Zone Tile (destructive style)
```dart
// Derived from tile pattern — errorText color, error-tinted icon bg
_buildDangerTile(
  key: GroupKeys.leaveGroupTile,
  icon: Iconsax.logout,
  label: 'Leave Group',
  onTap: () {
    HapticService.selection();
    _showLeaveDialog(context);
  },
)

// Icon container for danger tiles
Container(
  width: 36, height: 36,
  decoration: BoxDecoration(
    color: const Color(0x1AEF4444),   // error at 10% opacity
    borderRadius: BorderRadius.circular(8),
  ),
  child: Center(
    child: Icon(Iconsax.logout, size: 18, color: AppColorTokens.light.errorText),
  ),
),
```

### Balance Gate Check
```dart
// Inside remove member tap handler
final balancesAsync = ref.read(groupBalancesProvider(widget.groupId));
final memberBalance = balancesAsync.valueOrNull?.balances
    .where((b) => b.participantId == member.userId)
    .firstOrNull;
final hasBalance = memberBalance != null &&
    memberBalance.netBalance != Decimal.zero;

if (hasBalance) {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Settle up with ${member.displayName} before removing them.'),
        action: SnackBarAction(
          label: 'Settle Up',
          onPressed: () => context.push('/group/${widget.groupId}/settle-up'),
        ),
      ),
    );
  }
  return;
}
// proceed with remove...
```

---

## State of the Art

| Old Approach | Current Approach | Notes |
|--------------|------------------|-------|
| `AppBar` title in GroupSettingsScreen | Inline back button (ProfileScreen pattern) | Phase 29 removes AppBar — matches profile screen visual language |
| Plain `ListView` + `ListTile` | Section widgets with card containers + stagger animations | Phase 29 brings GroupSettingsScreen to Phase 26 design standard |
| No leave/delete functionality | `GroupService.leaveGroup()`, `removeMember()`, `deleteGroup()` | Three new service methods required |
| No member management UI | `GroupMembersSection` with creator badge + remove button | Phase 29 addition |

---

## Open Questions

1. **Event orphaning on group delete**
   - What we know: `deleteGroup` removes the group doc and member docs. Events under `groups/{groupId}/events/` are not deleted.
   - What's unclear: Whether the product intends cascading event delete or accepts orphaned event data. D-01 says "no module toggles this phase" but doesn't address event cascade.
   - Recommendation: Do not cascade-delete events. Just delete the group doc + member docs + invite code. Orphaned events are invisible (no group membership to query them through). Flag for a future cleanup phase if needed.

2. **Leave group when user is the last member**
   - What we know: The last member leaving produces an empty group (no members, but group doc still exists with no memberIds).
   - What's unclear: Whether this should be treated as an implicit delete.
   - Recommendation: Allow it. Empty groups are invisible in `userGroupsProvider` (filtered by `arrayContains: uid`) and harmless. The group creator can always delete explicitly.

3. **`settingsTitle` key deprecation**
   - What we know: Existing test `'shows Group Settings appbar title'` uses `GroupKeys.settingsTitle` which is the AppBar title. AppBar is removed in this phase.
   - Recommendation: Keep `settingsTitle` in `GroupKeys` but remove its assignment from the new screen. Update the test to check for `GroupKeys.settingsBackButton` instead. Preserves backward compatibility without breaking other potential test references.

---

## Environment Availability

Step 2.6: SKIPPED — Phase 29 is purely code/widget changes with no new external dependencies. All required packages (`flutter_animate`, `iconsax`, `flutter_riverpod`, `cloud_firestore`, `shimmer`) are already in `pubspec.yaml`.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `flutter_test` (built-in Flutter SDK) |
| Config file | `pubspec.yaml` (flutter test section) |
| Quick run command | `flutter test test/features/groups/group_settings_screen_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Behavior | Test Type | Automated Command | File Status |
|----------|-----------|-------------------|-------------|
| GroupSettingsScreen renders with card sections (not plain ListView) | widget | `flutter test test/features/groups/group_settings_screen_test.dart` | Wave 0 — new file |
| GroupInfoSection shows group name, currency, invite code | widget | same | Wave 0 |
| GroupMembersSection shows member names with creator badge | widget | same | Wave 0 |
| Creator badge renders for creator member only | widget | same | Wave 0 |
| Non-creator does not see delete tile | widget | same | Wave 0 |
| All members see leave tile | widget | same | Wave 0 |
| Leave dialog appears on tap | widget | same | Wave 0 |
| Delete dialog appears on tap (creator view) | widget | same | Wave 0 |
| Remove blocked by non-zero balance shows SnackBar | widget | same | Wave 0 |
| Existing group_screens_test.dart GroupSettingsScreen tests still pass | widget | `flutter test test/features/groups/group_screens_test.dart` | Exists — update required |

### Sampling Rate

- **Per task commit:** `flutter test test/features/groups/group_settings_screen_test.dart`
- **Per wave merge:** `flutter test test/features/groups/`
- **Phase gate:** `flutter test` full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/features/groups/group_settings_screen_test.dart` — new test file covering Phase 29 behaviors above
- [ ] Update `test/features/groups/group_screens_test.dart` — fix `'shows Group Settings appbar title'` test (AppBar removed), update `_wrap` helper to include `groupMembersProvider` and `groupBalancesProvider` overrides

---

## Project Constraints (from CLAUDE.md)

| Directive | Impact on This Phase |
|-----------|---------------------|
| **Immutability** — always create new objects, never mutate | `GroupService` methods must not mutate Group model. Firestore updates go through `FieldValue.arrayRemove`, not local object mutation. |
| **File size <800 lines** | GroupSettingsScreen stays lean by extracting three section widgets into separate files. |
| **Functions <50 lines** | `deleteGroup` will approach this limit — keep the batch operations inline but don't add extra logic. |
| **No hardcoded Color literals** | The danger tile icon bg uses `const Color(0x1AEF4444)`. This is acceptable — it's the `error` token at 10% opacity, which is not a named token. Alternatively derive as `AppColorTokens.light.error.withValues(alpha: 0.1)` to avoid the hex literal. Use `withValues` approach. |
| **TDD mandatory** | Write `group_settings_screen_test.dart` before implementing the new section widgets. Red → Green → Refactor. |
| **80%+ test coverage** | All three new section widgets need widget tests. The danger zone requires creator vs non-creator views tested. |
| **Firebase stack** | This phase touches Firestore only — no SQLite, no other services. All writes go through `GroupService extends FirestoreRepository`. |
| **Anonymous auth** | `FirebaseConfig.currentUser?.uid` may be null in edge cases — all new service methods must null-guard the UID check with `throw Exception('Not authenticated')`. |

---

## Sources

### Primary (HIGH confidence)

- `lib/features/settings/screens/profile_screen.dart` — screen layout pattern, stagger animation pattern
- `lib/features/settings/widgets/profile_about_section.dart` — tile pattern, section header pattern, card container (borderRadius: 16)
- `lib/features/settings/widgets/profile_notifications_section.dart` — ConsumerWidget section, card container
- `lib/features/groups/screens/group_settings_screen.dart` — current screen to replace
- `lib/features/groups/providers/group_provider.dart` — GroupService WriteBatch pattern, Firestore API usage
- `lib/features/groups/providers/group_balance_provider.dart` — groupBalancesProvider API, UserBalance type
- `lib/features/groups/models/group_member_model.dart` — GroupMember fields, isCreator getter
- `lib/features/groups/keys/group_keys.dart` — existing keys, new key names to add
- `.planning/phases/29-group-management/29-UI-SPEC.md` — approved visual contract
- `test/features/groups/group_screens_test.dart` — test mock pattern to replicate

### Secondary (MEDIUM confidence)

- Firebase Firestore documentation (WriteBatch, FieldValue.arrayRemove, subcollection behavior) — behavior consistent with existing GroupService implementation patterns
- `.planning/phases/29-group-management/29-CONTEXT.md` — all decisions sourced from user session

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages already in pubspec.yaml, verified in code
- Architecture patterns: HIGH — directly derived from ProfileScreen source code
- Firestore operations: HIGH — derived from existing GroupService WriteBatch patterns + documented Firestore behavior
- Pitfalls: HIGH — derived from Phase 26 STATE.md decisions and direct code analysis
- Test patterns: HIGH — derived from existing test file structure

**Research date:** 2026-04-02
**Valid until:** 2026-05-02 (stable — all sources are in-repo code)
