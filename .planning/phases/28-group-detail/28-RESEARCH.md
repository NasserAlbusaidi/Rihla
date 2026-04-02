# Phase 28: Group Detail - Research

**Researched:** 2026-04-02
**Domain:** Flutter widget refresh — GroupDetailScreen visual polish, animation, provider cleanup
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Visual refresh + provider cleanup. No layout restructure or functional additions.
- **D-02:** Touch widgets, spacing, styling, animations, and refactor providers for efficiency (unnecessary rebuilds, missing caching).
- **D-03:** All sections get the earthy design language polish pass — spacing, density, consistency, micro-interactions.
- **D-04:** Keep current section order: Header → Stats Grid → Settle-Up CTA (conditional) → Events → Members & Balances → Activity.
- **D-05:** Remove invite code section from this screen. Invite code display moves to Phase 29 (Group Management/Settings).
- **D-06:** Stats grid stays as 2x2 layout: YOUR BALANCE (color-coded), GROUP TOTAL, ACTIVE MEMBERS, EVENTS. Visual refresh only.
- **D-07:** Keep type-specific card design from Phase 20. Polish spacing, shadows, typography.
- **D-08:** Add staggered fade-in entrance animations on event cards using FadeInList pattern (already used elsewhere in the app via flutter_animate).
- **D-09:** Keep accordion pattern for member balance cards (tap to expand per-event breakdown). Visual refresh on card styling, colors, typography.
- **D-10:** Settle-up CTA stays conditional — only shows when user has non-zero balance.
- **D-11:** Skeleton loading on initial load (existing pattern). Add pull-to-refresh to force re-fetch from Firestore.
- **D-12:** Inline error state with retry button when group data fails to load. Keep screen structure visible — don't replace with full-screen error.
- **D-13:** Keep dark gradient ModuleHeader with group name and creation date. Polish typography, spacing, and ensure grain texture is present.
- **D-14:** Keep FloatingActionButton as primary "Create Event" entry point. Visual refresh on FAB styling.
- **D-15:** Navigation transitions to sub-screens: Claude's discretion. Evaluate whether OpenContainer (card → detail) or slide-right is more appropriate per navigation type.

### Claude's Discretion

- Navigation transition type per sub-screen (D-15) — Claude evaluates OpenContainer vs slide-right based on context
- Specific provider refactoring decisions (which providers to optimize, caching strategy)
- Exact spacing/density values within the earthy design token system

### Deferred Ideas (OUT OF SCOPE)

- Invite code display — Moves to Phase 29 (Group Management/Settings screen) per D-05
</user_constraints>

---

## Summary

Phase 28 is a visual refresh and provider cleanup of the existing `GroupDetailScreen` (built in Phase 20). The screen structure is solid and well-tested. The work is purely cosmetic + performance: applying the earthy design language consistently, adding entrance animations, wiring pull-to-refresh, replacing the full-screen error with an inline retry pattern, removing the invite code section, and auditing providers for unnecessary rebuilds.

The existing codebase already has every tool needed: `FadeInList` (staggered animation), `AppColorTokens.light` (earthy palette), `AppShadowTokens.standard` (raised/floating elevations), `OpenContainer` from `animations` package (already used for event card → EventCommandCenter), and `AppSpacingTokens.standard` (spacing scale). No new packages are required.

The main complexity is the `groupBalancesProvider` dependency chain: it watches events, then per-event expenses and settlements in a loop. The `_buildContent` method calls `ref.watch(groupBalancesProvider)` at the top level of `Scaffold.body`, which means the entire content tree rebuilds on any balance change. Scoping the balance watch to only `_buildMembersBalancesSection` and `_buildEventsSection` (which both need it) will reduce the rebuild surface. The stats grid rebuild can be decoupled from the member card expansion state.

**Primary recommendation:** Work section by section — remove invite code, then apply design tokens systematically per section, then add FadeInList to event cards, then wire pull-to-refresh, then address provider rebuild scoping.

---

## Standard Stack

### Core (all already in pubspec.yaml — no new dependencies)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter_animate` | `^4.5.0` | `FadeInList` staggered entrance, `.animate().fadeIn()` on sections | Already installed. `FadeInList` widget is already the project pattern used in vault, logistics, activity feed, ledger. |
| `animations` | `^2.1.2` | `OpenContainer` for event card → `EventCommandCenter` (already wired) | Already installed. `OpenContainer` wrapping EventCard is already in GroupDetailScreen. |
| `flutter_riverpod` | `^2.x` | `ConsumerStatefulWidget`, `Provider.family`, `StreamProvider.family` | Already installed. All providers exist. |
| `go_router` | `^17.1.0` | Navigation for settings, settle-up, activity, create-event routes | Already installed. All routes are defined in `app_router.dart`. |
| `iconsax` | `^0.0.8` | Icon set used throughout the screen | Already installed. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `haptic_feedback` | `^0.6.4+3` | Micro-interaction on FAB tap, settle-up CTA tap | Used via `HapticService.success()` which already wraps `HapticFeedback` — use existing service. |
| `intl` | `^0.19.0` | Date formatting in header subtitle | Already imported in group_detail_screen.dart. |

**No new packages needed.** This phase is a polish pass on existing infrastructure.

---

## Architecture Patterns

### Pattern 1: `ref.watch` Scoping in `ConsumerStatefulWidget`

**What:** The current `_buildContent` calls `ref.watch(groupBalancesProvider(groupId))` once and passes the result down to `_buildEventsSection` and `_buildMembersBalancesSection`. This means any balance change rebuilds the entire `_buildContent` subtree including the stats grid and settle-up CTA.

**Improvement:** Move `ref.watch(groupBalancesProvider(groupId))` into `_buildMembersBalancesSection` and extract the current-user balance watch for stats grid into a tightly-scoped `Consumer` widget. This limits rebuilds to only the widget that actually changed.

**Pattern:**
```dart
// BEFORE: rebuilds all of _buildContent on any balance change
Widget _buildContent(BuildContext context, Group group) {
  final balancesAsync = ref.watch(groupBalancesProvider(groupId)); // too high
  ...
}

// AFTER: balance-dependent subtrees watch locally
Widget _buildContent(BuildContext context, Group group) {
  // Stats grid uses a Consumer to isolate its rebuild
  return Column(children: [
    ModuleHeader(...),
    Consumer(builder: (context, ref, _) {
      final balancesAsync = ref.watch(groupBalancesProvider(groupId));
      return GroupStatsGrid(...);
    }),
    ...
  ]);
}
```

**Confidence:** HIGH — this is standard Riverpod rebuild isolation.

### Pattern 2: FadeInList for Event Cards

**What:** Wrap the event cards column in a `FadeInList` widget instead of a bare `Column`. The `FadeInList` pattern is already used in:
- `VaultScreen` (line 222)
- `LogisticsScreen` (line 206)
- `ActivityFeedScreen` (line 178)

**Current code** (group_detail_screen.dart line 269–299): `Column` with a bare `for` loop over event cards.

**Replacement:**
```dart
// Source: lib/shared/animations/fade_in_list.dart
FadeInList(
  children: [
    for (int i = 0; i < events.length; i++)
      OpenContainer<void>(
        // existing OpenContainer wrapping EventCard
        ...
      ),
  ],
)
```

Note: `FadeInList` wraps children in a `Column` internally. Remove the outer `Column` in the events loop — `FadeInList` provides the layout.

**Confidence:** HIGH — FadeInList accepts any List<Widget>, OpenContainer is a widget.

### Pattern 3: Pull-to-Refresh with `RefreshIndicator`

**What:** Wrap `SingleChildScrollView` (already in `_buildContent`) in a `RefreshIndicator`. The `onRefresh` callback needs to invalidate the Firestore-backed providers to trigger a fresh stream.

**Pattern:**
```dart
// Riverpod provider invalidation on pull-to-refresh
RefreshIndicator(
  color: AppColorTokens.light.primary,
  backgroundColor: AppColorTokens.light.cardSurface,
  onRefresh: () async {
    ref.invalidate(groupDetailProvider(groupId));
    ref.invalidate(groupEventsProvider(groupId));
    ref.invalidate(groupBalancesProvider(groupId));
    ref.invalidate(groupActivityProvider(groupId));
    // Wait briefly for streams to re-establish
    await Future.delayed(const Duration(milliseconds: 500));
  },
  child: SingleChildScrollView(...),
)
```

**Note:** `StreamProvider.family` providers backed by Firestore `snapshots()` automatically re-subscribe when invalidated via `ref.invalidate`. The 500ms delay gives streams time to re-emit before the refresh indicator dismisses.

**Confidence:** HIGH — `ref.invalidate` on StreamProvider forces re-subscription. Verified pattern in Flutter/Riverpod docs.

### Pattern 4: Inline Error State with Retry (D-12)

**Current:** `error: (e, st) => const Center(child: Text('Error loading group'))` — full screen replacement.

**Required:** Keep screen structure visible, show inline error + retry.

**Pattern:**
```dart
error: (e, st) => Column(
  children: [
    ModuleHeader(title: 'Group', subtitle: '', useDarkTheme: true),
    Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Iconsax.warning_2, size: 48, color: AppColorTokens.light.textMuted),
            const SizedBox(height: 16),
            Text('Failed to load group', style: ...),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(groupDetailProvider(groupId)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    ),
  ],
),
```

**Confidence:** HIGH — standard Flutter error UX pattern.

### Pattern 5: FAB Visual Refresh

**Current FAB:**
```dart
FloatingActionButton(
  backgroundColor: AppColorTokens.light.primary,
  shape: const CircleBorder(),
  child: const Icon(Iconsax.add, color: Colors.black),
)
```

**Note:** Icon color `Colors.black` is incorrect — should be `AppColorTokens.light.textOnPrimary` (white). The primary teal has `textOnPrimary = Color(0xFFFFFFFF)` per color_tokens.dart. This is a design token compliance fix.

**Confidence:** HIGH — verified in color_tokens.dart.

### Anti-Patterns to Avoid

- **Hardcoded Color(0xFF...):** All colors must come from `AppColorTokens.light`. CI blocks hardcoded hex literals.
- **Mutating provider state:** Never `setState` inside `onRefresh` to track loading — use RefreshIndicator's own loading indicator.
- **Animating the entire screen rebuild:** `FadeInList` should only wrap the stable list of items, not the outer `Column` that re-renders on balance changes. If the outer scaffold rebuilds, animation replays annoyingly.
- **Spacing magic numbers:** Use `AppSpacingTokens.standard.space*` constants, not raw integers. The existing screen uses `const SizedBox(height: 24)` — these are fine as they match the token values exactly (space24 = 24.0). Keep using literal values when they exactly match token constants — no need to refactor to token references if they're already correct.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Staggered list entrance | Custom AnimationController per card | `FadeInList` in `lib/shared/animations/fade_in_list.dart` | Already built, handles `disableAnimations`, used in 3 other screens |
| Card-to-screen transition | `Navigator.push` with custom route | `OpenContainer` from `animations` package | Already wired in the screen for event cards; ContainerTransform gives shared-element feel |
| Pull-to-refresh | Custom scroll listener + loading state | Flutter's built-in `RefreshIndicator` | No package needed; `ref.invalidate` handles re-fetch |
| Balance color coding | Custom color logic | Existing `switch(netBalance.compareTo(Decimal.zero))` pattern | Already correct in `GroupStatsGrid` and `GroupMemberBalanceCard` |
| Accordion expand animation | Custom AnimationController | `AnimatedCrossFade` + `RotationTransition` | Already in `GroupMemberBalanceCard` — keep, only restyle the card container |

---

## Common Pitfalls

### Pitfall 1: Breaking Existing Widget Tests on Invite Code Removal

**What goes wrong:** `group_detail_screen_test.dart` line 278–293 has a test that explicitly asserts `GroupKeys.inviteCodeSection` is visible and positioned below `GroupKeys.eventsSection`. Removing the invite code section will fail this test.

**Why it happens:** D-05 removes the invite code section but the existing test was written against Phase 20 which had it.

**How to avoid:** Update the existing test in `test/features/group_detail_screen_test.dart` — remove the `inviteCodeSection` position test and add a test asserting the invite code section is NOT present.

**Warning signs:** `expect(find.byKey(GroupKeys.inviteCodeSection), findsOneWidget)` failing.

### Pitfall 2: FadeInList Replays on Provider Rebuild

**What goes wrong:** If `FadeInList` is placed inside a widget that rebuilds when balance data changes, the stagger animation replays every time the balance updates (e.g., when Firestore emits a new snapshot).

**Why it happens:** `AnimateList` from `flutter_animate` re-runs effects when the widget is rebuilt with a new child list. If the parent rebuilds, the animation replays.

**How to avoid:** Place `FadeInList` for events inside a `widget.build` path that only rebuilds when `groupEventsProvider` emits. The events list and the balances list are separate providers — keep them separate. Don't nest `FadeInList` inside the `balancesAsync.when(data: ...)` block.

**Warning signs:** Event cards flash/fade on every settle-up CTA visibility change.

### Pitfall 3: `ref.invalidate` on `Provider.family` (not `StreamProvider.family`)

**What goes wrong:** `groupBalancesProvider` is a `Provider.family<AsyncValue<GroupBalances>>`, NOT a `StreamProvider.family`. Calling `ref.invalidate(groupBalancesProvider(groupId))` on pull-to-refresh will invalidate this computed provider but it will immediately recompute from already-cached stream values.

**Why it happens:** `Provider.family` re-evaluates synchronously on invalidation. The underlying data (expenses, settlements) lives in `StreamProvider.family` providers. To actually force a Firestore re-fetch you need to invalidate the underlying stream providers (`groupEventsProvider`, `eventExpensesProvider`, etc.) — not the computed aggregation provider.

**How to avoid:** On pull-to-refresh, invalidate the Firestore-backed stream providers:
```dart
ref.invalidate(groupDetailProvider(groupId));
ref.invalidate(groupEventsProvider(groupId));
ref.invalidate(groupMembersProvider(groupId));
ref.invalidate(groupActivityProvider(groupId));
ref.invalidate(groupSettlementsProvider(groupId));
// groupBalancesProvider will recompute automatically
```

**Warning signs:** Pull-to-refresh completes instantly without any network activity; balance data doesn't update.

### Pitfall 4: `currentUid == null` in Tests

**What goes wrong:** Adding new UI behavior gated on `currentUid != null` (e.g., "your balance" emphasis) will silently not render in tests that override `currentUserIdProvider` with `null`.

**Why it happens:** `group_detail_events_test.dart` sets `currentUserIdProvider.overrideWithValue(null)` explicitly. `group_detail_screen_test.dart` sets it to `'uid-creator'`.

**How to avoid:** Any new conditional UI that depends on `currentUid` must have test coverage in both test files. Check both `_wrap` helpers when writing tests.

**Warning signs:** A new widget visible in manual testing but not found by `expect(find.byKey(...))` in tests.

### Pitfall 5: Stats Grid `childAspectRatio` on Long Currency Values

**What goes wrong:** The `GroupStatsGrid` uses `childAspectRatio: 1.6` in a `GridView.count`. OMR values with 3 decimal places (e.g., "123.456 OMR") may overflow the stat card at this aspect ratio.

**Why it happens:** The current implementation has `maxLines: 1, overflow: TextOverflow.ellipsis` for the value text, which masks the overflow. A visual refresh that increases font size or adds more padding could make the ellipsis more noticeable.

**How to avoid:** Keep `childAspectRatio: 1.6` or decrease it slightly to 1.4 if adding more padding. Test with a mock value of `123.456 OMR` during development. The `Flexible` wrapper on the value `Text` handles overflow correctly — don't remove it.

---

## Code Examples

### Verified pattern: FadeInList wrapping OpenContainer cards

```dart
// Source: lib/features/vault/screens/vault_screen.dart:222
// Source: lib/shared/animations/fade_in_list.dart
FadeInList(
  children: [
    for (final event in events)
      OpenContainer<void>(
        closedColor: Colors.transparent,
        openColor: AppColorTokens.light.scaffoldBackground,
        closedElevation: 0,
        openElevation: 0,
        closedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppSpacingTokens.standard.radiusLarge,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 400),
        transitionType: ContainerTransitionType.fade,
        useRootNavigator: false,
        closedBuilder: (context, openContainer) => EventCard(
          event: event,
          personalBalance: ...,
          onTap: openContainer,
        ),
        openBuilder: (context, _) => EventCommandCenter(
          groupId: groupId,
          eventId: event.id,
        ),
      ),
  ],
)
```

### Verified pattern: Inline provider-scoped rebuild isolation

```dart
// Source: Riverpod 2.x pattern — Consumer widget inside ConsumerStatefulWidget
Consumer(
  builder: (context, ref, _) {
    final balancesAsync = ref.watch(groupBalancesProvider(groupId));
    final balancesData = balancesAsync.valueOrNull;
    // Only this subtree rebuilds on balance change
    return GroupStatsGrid(
      userNetBalance: currentUserBalance?.netBalance ?? Decimal.zero,
      groupTotal: balancesData?.totalSpent ?? Decimal.zero,
      activeMembers: group.memberIds.length,
      eventCount: balancesData?.eventCount ?? 0,
      currency: group.currency,
    );
  },
)
```

### Verified pattern: Settle-up CTA with gradient (earthy polish)

```dart
// Source: AppColorTokens.light — primaryGradient getter
SizedBox(
  width: double.infinity,
  height: AppSpacingTokens.standard.buttonHeight,
  child: DecoratedBox(
    decoration: BoxDecoration(
      gradient: AppColorTokens.light.primaryGradient,
      borderRadius: BorderRadius.circular(AppSpacingTokens.standard.radiusMedium),
    ),
    child: ElevatedButton(
      key: GroupKeys.settleUpCta,
      onPressed: () => context.push('/group/$groupId/settle-up'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacingTokens.standard.radiusMedium),
        ),
      ),
      child: const Text('Settle Up', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    ),
  ),
)
```

### Verified pattern: Section header with consistent typography

```dart
// Source: app_theme.dart Theme.of(context).textTheme.titleMedium
// textTheme.titleMedium is already used for all section headers in the screen
// For earthy refresh: add consistent bottom border on section header rows
Row(
  children: [
    Text('Events', style: Theme.of(context).textTheme.titleMedium),
    const Spacer(),
    // count chip or actions
  ],
)
```

---

## Navigation Transition Recommendation (D-15)

The CONTEXT.md leaves the navigation transition type to Claude's discretion. Research finding:

| Route | Current | Recommendation | Rationale |
|-------|---------|----------------|-----------|
| `event/$eid` (event card tap) | `OpenContainer` (ContainerTransform) | Keep `OpenContainer` | Card → detail feels like spatial expansion. Already correct. |
| `settings` (settings icon in header) | GoRouter `context.push` (slide-right) | Keep slide-right | Settings is a peer screen, not a detail of a list item. |
| `settle-up` (Settle Up CTA tap) | GoRouter `context.push` (slide-right) | Keep slide-right | CTA action is a flow, not a spatial drill-down. |
| `activity` (See all activity tap) | GoRouter `context.push` (slide-right) | Keep slide-right | Standard list → full list pattern. |
| `create-event` (FAB tap) | GoRouter `context.push` (slide-up) | Keep slide-up per router definition | FAB actions conventionally slide up from the bottom. Check `app_router.dart` — create-event uses slide-up per CLAUDE.md. |

**Decision:** No navigation transition changes needed. The existing mix of `OpenContainer` for card drilldowns and GoRouter slide-right/slide-up for actions is already the correct pattern. This is NOT a task in the plan.

---

## Invite Code Removal: Impact Analysis

The existing `group_detail_screen_test.dart` has one test that directly asserts `GroupKeys.inviteCodeSection` is present and positioned correctly (line 278–293). Removing the invite code section requires:

1. Remove `_buildInviteSection` method from `GroupDetailScreen`
2. Remove the `_buildInviteSection` call in `_buildContent`
3. Remove `import 'package:share_plus/share_plus.dart'` if it's only used in `_buildInviteSection` — check for other usages first
4. Remove `import 'package:flutter/services.dart'` if `Clipboard` is only used there
5. Remove `import '../widgets/invite_code_display.dart'`
6. Update `test/features/group_detail_screen_test.dart`: remove the `inviteCodeSection` layout test, add a `inviteCodeSection: findsNothing` assertion
7. Remove `GroupKeys.inviteCodeSection` key usages from this screen (key itself stays in `group_keys.dart` for Phase 29 to use)

**Confidence:** HIGH — all imports and usages identified from code audit.

---

## Provider Cleanup: Specific Opportunities

From reading `group_detail_screen.dart` and `group_balance_provider.dart`:

### Opportunity 1: Move `groupBalancesProvider` watch down

**Location:** `_buildContent` line 87 — `final balancesAsync = ref.watch(groupBalancesProvider(groupId))`

**Problem:** Any balance update causes the full `_buildContent` Column to rebuild, including the stats grid, all event cards (even though events haven't changed), and all member balance cards.

**Fix:** Move the `ref.watch(groupBalancesProvider(groupId))` call into the individual section builders (`_buildEventsSection` and `_buildMembersBalancesSection`). Or use `Consumer` widgets to isolate.

### Opportunity 2: Double-watch of `groupEventsProvider`

**Location:** `_buildContent` calls `_buildEventsSection` and `_buildMembersBalancesSection`. Both sections call `ref.watch(groupEventsProvider(groupId))` independently (lines 210 and 324).

**Problem:** The events stream is watched twice. In Riverpod, this is safe (same provider instance) but it means `_buildMembersBalancesSection` subscribes to events separately from `_buildEventsSection`, which is unnecessary overhead. The events watch in `_buildMembersBalancesSection` only needs event names — consider passing `eventNames` as a parameter from the parent.

**Fix (minimal):** Keep as-is. Riverpod deduplicates watches of the same provider — both calls share one subscription. The overhead is minimal for a small events list. Document as known duplicate, not a bug.

### Opportunity 3: `currentUid` and `currentUserBalance` computed high up

**Location:** `_buildContent` lines 89–103.

**Problem:** `currentUid` and `currentUserBalance` are computed by watching two providers. If either changes (rare), the entire content tree rebuilds.

**Fix:** These two values are needed in `_buildContent` to pass to both `_buildEventsSection` (for `userEventBreakdown`) and the settle-up CTA. Extracting them isn't worth the complexity. Mark as acceptable — `currentUserIdProvider` is a sync `Provider<String?>` that never changes after auth, and `groupBalancesProvider` is the performance concern, not this.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (built-in Flutter SDK) |
| Config file | None — flutter test auto-discovers |
| Quick run command | `flutter test test/features/group_detail_screen_test.dart test/features/events/group_detail_events_test.dart test/features/group_balance_card_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

Phase 28 has no formal requirement IDs — it is a visual refresh + provider cleanup. The behaviors map as follows:

| Behavior | Test Type | Automated Command | File Exists? |
|----------|-----------|-------------------|-------------|
| Invite code section removed (D-05) | widget | quick run above | Needs update in existing test file |
| Stats grid always visible (D-06 visual refresh) | widget | quick run above | Existing test covers |
| Settle-up CTA conditional on non-zero balance (D-10) | widget | quick run above | Existing test covers |
| Section order: Stats → Events → Members → Activity (D-04) | widget | quick run above | Existing test covers (section order test) |
| Event cards have FadeInList wrapper (D-08) | widget | quick run above | New test needed |
| Pull-to-refresh present on scroll view (D-11) | widget | quick run above | New test needed |
| Inline error with retry when group fails to load (D-12) | widget | quick run above | New test needed |
| FAB icon color uses textOnPrimary (design token fix) | widget | quick run above | New test needed (or visual only) |
| Member balance cards visual refresh (D-09) | widget | `flutter test test/features/group_balance_card_test.dart` | Existing test covers accordion |

### Sampling Rate

- **Per task commit:** `flutter test test/features/group_detail_screen_test.dart test/features/group_balance_card_test.dart`
- **Per wave merge:** `flutter test test/features/`
- **Phase gate:** `flutter test` (full suite green before `/gsd:verify-work`)

### Wave 0 Gaps

- [ ] Update `test/features/group_detail_screen_test.dart` — remove `inviteCodeSection` present test, add `inviteCodeSection: findsNothing` assertion
- [ ] Add `test/features/group_detail_screen_test.dart` — test for `RefreshIndicator` presence
- [ ] Add `test/features/group_detail_screen_test.dart` — test for inline error state with retry button
- [ ] Add `test/features/events/group_detail_events_test.dart` — test that FadeInList wraps event cards (check `find.byType(FadeInList)`)

---

## Project Constraints (from CLAUDE.md)

Directives the planner must enforce:

1. **No hardcoded Color(0xFF...) literals** — CI blocks them. All colors via `AppColorTokens.light.*`
2. **TDD mandatory** — update/write tests before or alongside implementation
3. **Immutability** — create new objects, never mutate existing ones (applies to provider override maps, widget trees)
4. **File size limit** — `group_detail_screen.dart` is currently 609 lines. After removing invite code section (~70 lines) it drops to ~540. If visual refresh adds complexity, watch the 800-line ceiling.
5. **Financial precision** — `Decimal` package for all money; no `double`. Already respected throughout.
6. **Test coverage** — existing widget tests must remain green; new behaviors need new test cases
7. **GSD workflow** — no direct edits outside plan execution

---

## Environment Availability

Step 2.6: SKIPPED — this phase is purely code changes to existing Flutter files. No external CLI tools, services, or databases are introduced. The project's existing Flutter SDK and Firebase connection are unchanged.

---

## Open Questions

1. **`groupActivityProvider` limit**
   - What we know: `GroupActivityService.watchRecentActivity` streams "default 5" entries per the docstring in `group_balance_provider.dart`
   - What's unclear: Whether the service hardcodes a limit of 5 or passes it as a parameter. The screen currently shows `activities.take(5)` after fetching, implying the service may return more than 5.
   - Recommendation: Verify in `lib/features/groups/services/group_activity_service.dart` before planning the activity section refresh. If the service already limits to 5, the `.take(5)` in the screen is redundant noise.

2. **FAB tap haptic feedback**
   - What we know: `HapticService.success()` is called in several places. The FAB `onPressed` currently just calls `context.push(...)`.
   - What's unclear: Whether adding `HapticService.lightImpact()` (or similar) on FAB tap is in scope for D-14 ("Visual refresh on FAB styling").
   - Recommendation: Add haptic on FAB tap — it's a single line and aligns with D-03 ("micro-interactions").

---

## Sources

### Primary (HIGH confidence)

- `lib/features/groups/screens/group_detail_screen.dart` — Full Phase 20 implementation, 609 lines
- `lib/features/groups/providers/group_balance_provider.dart` — Provider architecture, rebuild scoping
- `lib/features/groups/providers/group_provider.dart` — groupDetailProvider, groupMembersProvider
- `lib/shared/animations/fade_in_list.dart` — FadeInList pattern implementation
- `lib/core/theme/tokens/color_tokens.dart` — AppColorTokens.light palette (all hex values)
- `lib/core/theme/tokens/spacing_tokens.dart` — AppSpacingTokens.standard scale
- `lib/core/theme/tokens/shadow_tokens.dart` — AppShadowTokens raised/floating elevations
- `test/features/group_detail_screen_test.dart` — Existing widget test coverage
- `test/features/events/group_detail_events_test.dart` — Event section widget test coverage
- `test/features/group_balance_card_test.dart` — Balance card widget test coverage

### Secondary (MEDIUM confidence)

- Riverpod 2.x `ref.invalidate` behavior on `StreamProvider.family` — verified via pattern used in other screens in this codebase

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages already in pubspec.yaml, verified in running code
- Architecture: HIGH — all patterns verified from existing codebase files
- Pitfalls: HIGH — identified from direct reading of the current screen code and existing tests
- Provider cleanup opportunities: MEDIUM — identifying rebuild scope requires running the app with Flutter DevTools; the analysis here is based on static code reading

**Research date:** 2026-04-02
**Valid until:** 2026-05-02 (stable Flutter + Riverpod versions, no moving dependencies)
