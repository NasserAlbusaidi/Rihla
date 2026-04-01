# Phase 25: Profile Screen Core - Research

**Researched:** 2026-04-01
**Domain:** Flutter profile screen — Riverpod state aggregation, Firestore batch writes, bottom sheet editing, cross-group stats
**Confidence:** HIGH

## Summary

Phase 25 builds the profile screen from scratch, replacing the existing `SettingsScreen` at `/settings` with a new `ProfileScreen` at `/profile`. The screen has two sections: an identity section (64px initials circle + display name + edit via bottom sheet) and a stats section (3 compact cards: group count, event count, total spending). Entry from home is via a 32px initials avatar in the home dashboard header.

The codebase is Firebase/Firestore-backed (not Supabase — CLAUDE.md confirms migration is complete). The critical technical challenges are: (1) deriving all three stats from existing providers without new Firestore queries, (2) the Firestore batch write for display name propagation across all participant records in all groups, and (3) the bottom sheet save flow with spinner → checkmark UX.

The app already has `userGroupsProvider` (group count), `groupEventsProvider.family` (events per group), and `groupBalancesProvider.family` with `totalSpent` per group (total spending). All three stats are derivable by composing these providers — no new Firestore reads needed. The initials circle uses `AppColorTokens.light.focusBorderWarm` (`#CC6B49`, the established terracotta color) — there is no dedicated `terracotta` token, but `focusBorderWarm` is the canonical terracotta already used in group cards and the onboarding screen.

**Primary recommendation:** Build a new `profileStatsProvider` as a `Provider<AsyncValue<ProfileStats>>` following the `crossGroupBalanceProvider` pattern — `ref.watch` in a loop is safe in `Provider` bodies. Extend `SettingsNotifier.setDeviceName()` to also trigger a Firestore batch write across all `groups/{gid}/members/{mid}` documents where `userId == currentUid`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Replace the existing `SettingsScreen` at `/settings` with a new profile screen at `/profile`. Delete the old settings screen entirely.
- **D-02:** Single screen built across two phases: Phase 25 builds identity + stats sections. Phase 26 adds settings + about/support sections.
- **D-03:** Route changes from `/settings` to `/profile`. Update any existing references.
- **D-04:** Large initials circle (64px) showing first letter(s) of display name. Terracotta background, white text.
- **D-05:** Display name shown below the initials circle.
- **D-06:** Tapping the name (or an edit affordance) opens a bottom sheet with text field + Save button.
- **D-07:** Name edit bottom sheet matches the earthy design language (not a plain AlertDialog).
- **D-08:** 3 compact stat cards in a horizontal row below the identity section.
- **D-09:** Each card: big number on top + label underneath. Cards use `cardSurface` background with earthy accent-colored numbers.
- **D-10:** Stats shown: Groups count (STATS-01), Events count (STATS-02), Total spending with "OMR" currency prefix e.g. "OMR 45.250" (STATS-03).
- **D-11:** Small initials circle (32px) in the top-right of the home dashboard header. Tapping navigates to `/profile`.
- **D-12:** Slide-right transition (standard `CustomTransitionPage` pattern).
- **D-13:** Save button shows spinner while Firestore batch writes complete, then brief success indicator (checkmark).
- **D-14:** Firestore propagation: batch update `display_name` on all participant records across all groups the user belongs to.
- **D-15:** Offline behavior: save to SharedPreferences + sync queue. Propagate to Firestore on reconnect. No error shown to user.
- **D-16:** Also update local SharedPreferences `deviceName` so the app stays consistent immediately.

### Claude's Discretion
- Exact bottom sheet styling for name edit (spacing, button style, validation)
- Initials extraction logic (first letter of first name vs first+last)
- Stat card internal spacing, font sizes, and accent color choice
- Loading/skeleton state for stats while data loads
- How to compute total spending (sum across all groups from existing providers or new query)
- Screen layout details (padding, section spacing, scroll behavior)
- Whether to show "Not set" placeholder or prompt when no name exists

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| IDENT-01 | User can view their current display name on the profile page | `settingsProvider` exposes `state.deviceName`; read via `ref.watch(settingsProvider).deviceName` |
| IDENT-02 | User can edit their display name from the profile page | Bottom sheet with `TextField` + Save button; calls `settingsProvider.notifier.setDeviceName()` then Firestore batch write |
| IDENT-03 | Display name change propagates to all group participant records | New `propagateDisplayName()` in `SettingsNotifier` or `GroupService`; queries `groups/{gid}/members` where `userId == uid` and batch-updates `displayName` field |
| STATS-01 | User can see total number of groups they belong to | `userGroupsProvider.valueOrNull?.length` — already reactive, no new query needed |
| STATS-02 | User can see total number of events they've participated in | Sum of `groupEventsProvider(gid).valueOrNull?.length` across all groups — compose in new `profileStatsProvider` |
| STATS-03 | User can see total spending across all groups | Sum of `groupBalancesProvider(gid).valueOrNull?.totalSpent` across all groups — compose in new `profileStatsProvider` |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter_riverpod` | `^2.x` (already installed) | State management for stats aggregation and settings | Project standard; `Provider` bodies support `ref.watch` in loops for variable-length aggregations |
| `cloud_firestore` | already installed | Batch write for display name propagation | Project standard; `WriteBatch` for multi-document atomic updates |
| `shared_preferences` | already installed | Local device name persistence | `settingsProvider` already uses this; `setDeviceName()` writes here first |
| `flutter_animate` | `^4.5.x` (already installed) | Entrance animations (fadeIn + slideY), checkmark animation | Project standard for all screen animations |
| `decimal` | already installed | Total spending arithmetic | All money math uses `Decimal` — project-wide rule |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `iconsax` | `^0.0.8` (already installed) | Section header icons (`Iconsax.user`, `Iconsax.chart`, `Iconsax.user_edit`) | Project standard icon set |
| `go_router` | `^17.1.0` (already installed) | Route `/profile` definition and navigation | All routes go through GoRouter |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| New `profileStatsProvider` (compose existing) | New Firestore query for stats | Composing existing providers is zero-cost Firestore reads; a new query adds latency and cost |
| `WriteBatch` for name propagation | Per-document `update()` calls in a loop | WriteBatch is atomic and faster; loop writes risk partial failure |

**Installation:** No new packages needed. All required packages are already in `pubspec.yaml`.

## Architecture Patterns

### Recommended Project Structure
```
lib/features/settings/
├── screens/
│   └── profile_screen.dart          # new — replaces settings_screen.dart
├── widgets/
│   └── edit_name_bottom_sheet.dart  # new — extracted bottom sheet
├── keys/
│   └── profile_keys.dart            # new — semantic test keys
└── providers/
    └── profile_stats_provider.dart  # new — ProfileStats aggregation
```

Note: The `settings/` feature folder is reused per D-02 (same folder, different screen). `settings_screen.dart` is deleted. The `settings_provider.dart` and `settings_service.dart` remain — they power the profile screen.

### Pattern 1: Profile Stats Provider (composing existing providers)

**What:** A `Provider<AsyncValue<ProfileStats>>` that aggregates group count, event count, and total spending by watching existing providers in a loop.

**When to use:** Whenever stats must aggregate over a variable-length list (same pattern as `crossGroupBalanceProvider` and `weeklyGroupSpendingProvider`).

**Example:**
```dart
// Source: group_balance_provider.dart crossGroupBalanceProvider pattern
typedef ProfileStats = ({
  int groupCount,
  int eventCount,
  Decimal totalSpent,
});

final profileStatsProvider = Provider<AsyncValue<ProfileStats>>((ref) {
  final groupsAsync = ref.watch(userGroupsProvider);
  if (groupsAsync.isLoading && !groupsAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (groupsAsync.hasError) {
    return AsyncValue.error(groupsAsync.error!, groupsAsync.stackTrace!);
  }
  final groups = groupsAsync.valueOrNull ?? [];

  var eventCount = 0;
  var totalSpent = Decimal.zero;
  var anyLoading = false;

  for (final group in groups) {
    final eventsAsync = ref.watch(groupEventsProvider(group.id));
    if (eventsAsync.isLoading && !eventsAsync.hasValue) {
      anyLoading = true;
      continue;
    }
    eventCount += eventsAsync.valueOrNull?.length ?? 0;

    final balancesAsync = ref.watch(groupBalancesProvider(group.id));
    if (balancesAsync.isLoading && !balancesAsync.hasValue) {
      anyLoading = true;
      continue;
    }
    totalSpent = totalSpent + (balancesAsync.valueOrNull?.totalSpent ?? Decimal.zero);
  }

  if (anyLoading && eventCount == 0 && totalSpent == Decimal.zero) {
    return const AsyncValue.loading();
  }

  return AsyncValue.data((
    groupCount: groups.length,
    eventCount: eventCount,
    totalSpent: totalSpent,
  ));
});
```

### Pattern 2: Firestore Batch Write for Display Name Propagation

**What:** Query all group member documents where `userId == currentUid`, then batch-update `displayName` across all of them.

**When to use:** IDENT-03 — after user saves a new display name.

**Example:**
```dart
// Source: GroupService.updateMemberDisplayName pattern in group_provider.dart
Future<void> propagateDisplayName(String uid, String displayName) async {
  // 1. Get all groups the user belongs to (already available from userGroupsProvider,
  //    but needed as a one-shot read here for the batch write context).
  final groupsSnap = await db.collection('groups')
      .where('memberIds', arrayContains: uid)
      .get();

  // 2. For each group, find the member document for this uid.
  final batch = db.batch();
  for (final groupDoc in groupsSnap.docs) {
    final membersSnap = await db
        .collection('groups')
        .doc(groupDoc.id)
        .collection('members')
        .where('userId', isEqualTo: uid)
        .get();
    for (final memberDoc in membersSnap.docs) {
      batch.update(memberDoc.reference, {'displayName': displayName});
    }
  }
  await batch.commit();
}
```

**Important:** Firestore `WriteBatch` has a 500-document limit. For a typical user (< 20 groups), this is not a concern. The query structure is: one `groups` collection query + N subcollection queries (one per group). This is sequential I/O — for 10 groups, that's 11 reads. Acceptable for this use case.

### Pattern 3: Bottom Sheet with Spinner → Checkmark Save Flow

**What:** `showModalBottomSheet` with a `StatefulWidget` that manages `_isSaving` and `_showCheck` booleans. Save button swaps between text, `CircularProgressIndicator`, and `Icon(Icons.check)`.

**When to use:** IDENT-02 + D-13 — the earthy bottom sheet design with visual save feedback.

**Example:**
```dart
// Source: home_screen.dart _showFabBottomSheet pattern
showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,  // allows keyboard resize
  backgroundColor: AppColorTokens.light.cardSurface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (context) => EditNameBottomSheet(
    currentName: ref.read(settingsProvider).deviceName,
    onSave: (newName) async { /* calls propagation */ },
  ),
);
```

### Pattern 4: Initials Circle Widget

**What:** A `Container` with circular decoration, terracotta background (`AppColorTokens.light.focusBorderWarm`), and centered white text showing extracted initials.

**When to use:** Both the 64px circle on profile screen and 32px circle in home header.

**Initials extraction:** Use the first character of the first word (always). If name has 2+ words, append first character of last word. If name is empty, show `?`.

```dart
// Recommended initials logic
String _extractInitials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
```

**Terracotta color:** `AppColorTokens.light.focusBorderWarm` (`Color(0xFFCC6B49)`) — this is the canonical terracotta already used in group cards (`group_card.dart` color slot 1) and onboarding screen gradient. There is no separate `terracotta` token — `focusBorderWarm` IS the terracotta token.

### Pattern 5: Initials Avatar in Home Dashboard Header

**What:** Add a `GestureDetector`-wrapped initials circle to the `Row` in `_DashboardContentState.build()`, positioned at the right end of the header row (replacing or supplementing the `FloatingActionButton.small`).

**When to use:** D-11 — 32px initials avatar tapping to `/profile`.

Per the home screen code, the header row currently has:
- Left: `Text('Your Groups')` (key: `HomeKeys.yourGroupsHeader`)
- Right: `FloatingActionButton.small` (key: `HomeKeys.createGroupFab`)

The initials circle needs to sit in the right area alongside or replacing the FAB. Given the FAB is for creating groups (core action), the recommended approach is to keep the FAB and add the initials avatar as a separate `GestureDetector` widget in the same row — e.g., via a `Stack` or expanding the row with an extra widget. Alternatively, a `Row` with spacing handles this cleanly.

### Pattern 6: Route Replacement

**What:** In `app_router.dart`, change the `/settings` route to `/profile` and update the `AppRoutes.settings` constant to `AppRoutes.profile`. Import `ProfileScreen` instead of `SettingsScreen`.

**When to use:** D-01, D-03.

**References to update:**
- `lib/core/router/app_router.dart`: route path, `AppRoutes.settings` constant, import
- Any `context.push(AppRoutes.settings)` or `context.go('/settings')` calls in the codebase

```bash
# Check all settings navigation references
grep -r "settings\|/settings" lib/ --include="*.dart" | grep -v "_screen\|_provider\|_keys\|_service\|_model\|settings_provider\|settings_service\|settings_keys"
```

### Anti-Patterns to Avoid
- **Calling `ref.watch` in a `StreamProvider` body over a variable-length list:** `StreamProvider` bodies cannot call `ref.watch` in loops. Use `Provider` (not `StreamProvider`) for stats aggregation — this is the established pattern in `crossGroupBalanceProvider`.
- **Mutating state directly:** All state changes must go through `copyWith()` — `SettingsNotifier` already enforces this.
- **Using `textMuted` for stat numbers:** `textMuted` (#9CA3AF) fails WCAG AA. Use `textPrimary` or `successText` for big numbers in stat cards.
- **Hardcoded `Color(0xFF...)` literals:** CI blocks these. All colors via `AppColorTokens.light.*`.
- **Using `AlertDialog` for name edit:** D-07 requires a bottom sheet, not a dialog.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cross-group event count | Custom Firestore query | Compose `groupEventsProvider.family` in `profileStatsProvider` | Already reactive, cached, and live |
| Cross-group total spending | Custom Firestore query | Compose `groupBalancesProvider.family` via `totalSpent` field | `GroupBalances.totalSpent` is already computed by `BalanceCalculator.calculateTotalExpenses` |
| Money formatting | Custom `toStringAsFixed(3)` | `AppFormatters.formatCurrency(amount, 'OMR')` | Handles OMR 3 decimal places, consistent formatting across the app |
| Batch write retry | Custom retry logic | Firestore offline persistence handles queuing | Firestore SDK automatically retries writes when connectivity is restored |

**Key insight:** All three stats are computable by watching providers already in memory (from the home screen's provider subscriptions). No additional Firestore round-trips are needed.

## Common Pitfalls

### Pitfall 1: WriteBatch 500-Document Limit
**What goes wrong:** If a user hypothetically belongs to 500+ groups, the batch write would fail silently or throw.
**Why it happens:** Firestore `WriteBatch` is limited to 500 operations.
**How to avoid:** For typical user scale (< 50 groups), this is safe. Add an assertion or chunked batch for robustness. In practice, one `batch.update()` per member document = one operation per group, well under the limit.
**Warning signs:** Exception in `batch.commit()` mentioning "maximum operations exceeded".

### Pitfall 2: Name Propagation Race Condition (Offline → Online)
**What goes wrong:** User edits name offline. SharedPreferences updates immediately. When online, the Firestore batch write runs — but if group data was also modified offline, Firestore offline queue ordering matters.
**Why it happens:** D-15 says save to SharedPreferences + sync queue, propagate on reconnect.
**How to avoid:** The Firestore SDK offline persistence queue handles ordering. The name update writes to Firestore when connectivity returns. No additional coordination needed.
**Warning signs:** Stale name appearing in group member lists after reconnect.

### Pitfall 3: Stats Provider Using StreamProvider Instead of Provider
**What goes wrong:** Stats aggregation calls `ref.watch(groupEventsProvider(gid))` inside a loop. `StreamProvider` does not support `ref.watch` calls inside the stream factory function.
**Why it happens:** Common mistake — assuming all async providers should be `StreamProvider`.
**How to avoid:** Use `Provider<AsyncValue<ProfileStats>>` — identical to `crossGroupBalanceProvider` and `weeklyGroupSpendingProvider`.
**Warning signs:** "ref.watch cannot be used inside a StreamProvider" runtime exception.

### Pitfall 4: Initials Circle Color Token Confusion
**What goes wrong:** Implementer uses a hardcoded terracotta hex or a non-existent `terracotta` token.
**Why it happens:** CONTEXT.md mentions "terracotta background" but the token is named `focusBorderWarm`.
**How to avoid:** Use `AppColorTokens.light.focusBorderWarm` (`#CC6B49`). This is confirmed as the canonical terracotta token used in `group_card.dart` and `onboarding_screen.dart`.
**Warning signs:** CI lint failure for hardcoded `Color(0xFF...)`.

### Pitfall 5: Bottom Sheet Keyboard Overlap
**What goes wrong:** The name edit text field is hidden by the software keyboard when the bottom sheet opens.
**Why it happens:** Default `showModalBottomSheet` does not resize for keyboard.
**How to avoid:** Pass `isScrollControlled: true` to `showModalBottomSheet`. Inside the bottom sheet, use `Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom))` to push content above the keyboard.
**Warning signs:** Text field not visible when keyboard appears.

### Pitfall 6: Settings Route References Not Updated
**What goes wrong:** Some screen still navigates to `/settings` after the route is renamed to `/profile`.
**Why it happens:** The route rename (D-03) requires updating all callers, not just the route definition.
**How to avoid:** Search for all `/settings` navigation references: `context.push('/settings')`, `context.go('/settings')`, `AppRoutes.settings`. Also check the `BottomNavShell` — the Profile tab (index 3) currently shows `_PlaceholderTab()`; Phase 25 wires it to `ProfileScreen`.
**Warning signs:** 404 error page on settings navigation, or the profile tab still shows "Coming soon".

## Code Examples

### Stat Card Widget
```dart
// Source: established card pattern from settings_screen.dart + group_balance_hero.dart
Widget _buildStatCard({
  required String value,
  required String label,
  required Color accent,
}) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColorTokens.light.cardSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadowTokens.standard.raised,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: accent,   // AppColorTokens.light.primary or successText
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColorTokens.light.textSecondary,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
```

### Profile Route Addition to app_router.dart
```dart
// Replace the settings GoRoute with:
static const String profile = '/profile';

GoRoute(
  path: AppRoutes.profile,
  pageBuilder: (context, state) => CustomTransitionPage(
    key: state.pageKey,
    child: const ProfileScreen(),
    transitionsBuilder: _slideRightTransition,
  ),
),
```

### Entrance Animations (established pattern)
```dart
// Source: settings_screen.dart animation pattern
_buildIdentitySection()
    .animate()
    .fadeIn(delay: 100.ms)
    .slideY(begin: 0.1),
_buildStatsSection()
    .animate()
    .fadeIn(delay: 200.ms)
    .slideY(begin: 0.1),
```

### Name Validation in Bottom Sheet
```dart
// Recommended: trim + non-empty check, no complex validation
final trimmed = _controller.text.trim();
if (trimmed.isEmpty) return; // disable Save button when empty
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `SettingsScreen` at `/settings` | `ProfileScreen` at `/profile` (Phase 25) | Now | Delete `settings_screen.dart`, keep `settings_provider.dart` |
| AlertDialog for name edit | Bottom sheet with earthy design | Now | Matches design language, `isScrollControlled: true` required |
| Name stored only in SharedPreferences | Name in SharedPreferences + Firestore members | Now | Adds Firestore batch write to `setDeviceName` flow |

**Deprecated/outdated:**
- `settings_screen.dart`: Deleted as part of Phase 25. Its preferences + about sections move to Phase 26.
- `SettingsKeys.screen`: Replace with `ProfileKeys.screen` (new file).
- `AppRoutes.settings`: Rename to `AppRoutes.profile`, value changes from `/settings` to `/profile`.

## Open Questions

1. **BottomNavShell Profile Tab Wiring**
   - What we know: `BottomNavShell` has 4 tabs; the Profile tab (index 3) shows `_PlaceholderTab()`. D-11 says navigate to `/profile` route.
   - What's unclear: Should the Profile tab in `BottomNavShell` replace the placeholder with `ProfileScreen()` directly (making it a persistent tab), or should it trigger `context.push('/profile')` (making it a separate route)?
   - Recommendation: Replace `_PlaceholderTab()` with `ProfileScreen()` at index 3 in `BottomNavShell` — this aligns with the persistent tab pattern. The `/profile` route entry point (D-11 says initials avatar in header) still uses `context.push('/profile')` for users who navigate from the header avatar, not the nav bar.
   - **Implication:** `ProfileScreen` must work both as a routed screen (from header avatar, with back button) and as a tab (from bottom nav, without back button). Use `GoRouter.of(context).canPop()` to conditionally show a back button.

2. **Display Name "Not Set" State**
   - What we know: `settingsProvider` initializes `deviceName` to `''` (empty string). The old `settings_screen.dart` shows "Not set" as subtitle when empty.
   - What's unclear: Should the profile screen show the initials circle with `?` and a prompt CTA, or a generic "Not set" text?
   - Recommendation: Show `?` in the initials circle when name is empty, and a tappable "Set your name" label (instead of the name display) that triggers the edit bottom sheet immediately. This is more inviting than a static "Not set" text.

3. **Total Spending Scope**
   - What we know: `groupBalancesProvider(gid).valueOrNull?.totalSpent` gives the total spending for a single group across all events in that group. STATS-03 says "total spending across all groups".
   - What's unclear: Does this mean all expenses paid by anyone in any group the user belongs to (absolute total), or only expenses where the current user is a payer?
   - Recommendation: Sum `totalSpent` across all groups (absolute total — all expenses in all groups the user belongs to). This matches the "group trip planner" mental model and is simpler. The user's personal share is shown elsewhere (in the balance hero card).

## Environment Availability

Step 2.6: SKIPPED (no external dependencies — all required packages already in `pubspec.yaml`, Firestore/Firebase SDK already initialized in app bootstrap).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test + mocktail |
| Config file | `pubspec.yaml` (dev_dependencies section) |
| Quick run command | `flutter test test/unit/profile_stats_provider_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| IDENT-01 | Profile screen shows current device name | Widget | `flutter test test/features/profile/profile_screen_test.dart::shows_device_name` | Wave 0 |
| IDENT-02 | Tapping name opens bottom sheet with text field | Widget | `flutter test test/features/profile/profile_screen_test.dart::opens_edit_bottom_sheet` | Wave 0 |
| IDENT-03 | Saving new name triggers Firestore batch write (mocked) | Unit | `flutter test test/unit/settings_notifier_test.dart::propagates_display_name` | Wave 0 (extend existing) |
| STATS-01 | Profile screen shows group count | Widget | `flutter test test/features/profile/profile_screen_test.dart::shows_group_count` | Wave 0 |
| STATS-02 | Profile screen shows event count | Widget | `flutter test test/features/profile/profile_screen_test.dart::shows_event_count` | Wave 0 |
| STATS-03 | Profile screen shows total spending in OMR format | Widget | `flutter test test/features/profile/profile_screen_test.dart::shows_total_spending` | Wave 0 |

### Sampling Rate
- **Per task commit:** `flutter test test/unit/settings_notifier_test.dart test/features/profile/ --reporter=compact`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/features/profile/profile_screen_test.dart` — covers IDENT-01, IDENT-02, STATS-01, STATS-02, STATS-03
- [ ] `test/unit/profile_stats_provider_test.dart` — unit test for `profileStatsProvider` aggregation logic
- [ ] `lib/features/settings/keys/profile_keys.dart` — semantic test keys for profile screen
- [ ] Extend `test/unit/settings_notifier_test.dart` — add test for `propagateDisplayName` (mocked Firestore)

## Sources

### Primary (HIGH confidence)
- `lib/features/settings/screens/settings_screen.dart` — existing screen structure, `_showDeviceNameDialog` pattern to replace with bottom sheet
- `lib/core/providers/settings_provider.dart` — `SettingsNotifier.setDeviceName()` — needs Firestore propagation added
- `lib/features/groups/providers/group_balance_provider.dart` — `crossGroupBalanceProvider` — canonical pattern for stats aggregation
- `lib/features/home/providers/dashboard_providers.dart` — `weeklyGroupSpendingProvider` — second reference for aggregation pattern
- `lib/features/groups/providers/group_provider.dart` — `userGroupsProvider`, `groupMembersProvider`, `GroupService.updateMemberDisplayName()`
- `lib/features/events/providers/event_provider.dart` — `groupEventsProvider.family`
- `lib/core/theme/tokens/color_tokens.dart` — all tokens; `focusBorderWarm` confirmed as terracotta
- `lib/features/home/screens/home_screen.dart` — header structure for initials avatar placement
- `lib/features/home/widgets/bottom_nav_shell.dart` — Profile tab is currently `_PlaceholderTab()` at index 3

### Secondary (MEDIUM confidence)
- `lib/features/groups/widgets/group_card.dart` — confirms `focusBorderWarm` as slot-1 terracotta color
- `lib/features/onboarding/screens/onboarding_screen.dart` — confirms `0xFFCC6B49` as terracotta gradient start

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already installed, confirmed in pubspec.yaml
- Architecture: HIGH — all patterns observed directly in codebase (crossGroupBalanceProvider, weeklyGroupSpendingProvider)
- Pitfalls: HIGH — derived from direct code inspection (WriteBatch, StreamProvider loop restriction confirmed)
- Stats derivation: HIGH — `groupBalancesProvider.totalSpent` and `groupEventsProvider` exist and are in use

**Research date:** 2026-04-01
**Valid until:** 2026-05-01 (stable Flutter/Firestore patterns)
