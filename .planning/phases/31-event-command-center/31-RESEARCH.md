# Phase 31: Event Command Center — Research

**Researched:** 2026-04-05
**Domain:** Flutter widget refresh + new settings screen (EventCommandCenter + EventSettingsScreen)
**Confidence:** HIGH

## Summary

Phase 31 is a targeted visual refresh of an existing, fully-functional screen (EventCommandCenter, 186 lines) plus the creation of a new EventSettingsScreen. All libraries are already installed, all patterns are established by Phase 28/29, and the EventService already exposes `updateEvent` and `deleteEvent`. There is no new infrastructure work.

The primary implementation task is: replace `Iconsax.more_circle` with `Iconsax.setting_2` in the header, add a second subtitle line (date range), add a route for EventSettingsScreen, and build two new section widgets (`EventInfoSection`, `EventDangerSection`) following the GroupInfoSection/GroupDangerSection patterns verbatim.

The balance-gate for event deletion uses the existing `eventExpensesProvider` + `eventSettlementsProvider` to compute whether net balances are non-zero. No new provider is required — the same pattern as GroupDangerSection (which reads expenses inline to determine unsettled state) applies.

**Primary recommendation:** Implement in 2 plans — P01 (EventCommandCenter refresh + route + new screen skeleton) and P02 (EventInfoSection + EventDangerSection + tests).

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Header & Event Info**
- Dark ModuleHeader (matches Phase 28 group detail hub pattern)
- Header shows: event name + type badge + date range + group name
- Refresh EventExpenseHero card with earthy color tokens (keep total expenses + member count as primary metrics)
- Settings entry point: gear icon in header action slot (mirrors GroupDetailScreen pattern)

**Module Grid & Navigation**
- Keep 2-column grid layout (existing EventModuleList pattern)
- Refresh SmartModuleCard with earthy color tokens and updated summary text
- Fixed module ordering: Ledger -> Gear -> Logistics -> Vault -> Activity -> Memories
- Show all enabled modules with descriptive empty state (tap still navigates)

**Event Settings Screen**
- Full screen with slide-right transition (matches GroupSettingsScreen from Phase 29)
- Editable fields: event name, dates, description (type and modules set at creation, not editable)
- Danger zone: delete event (creator-only, confirmation dialog, balance-gated like group delete)
- Layout pattern: ProfileScreen card sections with stagger animations (Phase 29 pattern)

### Claude's Discretion
- Exact spacing and padding values within earthy token system
- Animation timing for stagger effects
- Error state presentation details
- Loading skeleton specifics

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ECC-01 | Event command center displays event info, module grid, and quick actions | EventCommandCenter already implements this; refresh replaces more_circle with gear icon, adds date range subtitle, updates token usage |
| ECC-02 | Event settings are accessible and functional | New EventSettingsScreen with EventInfoSection (name/dates/description edit) + EventDangerSection (delete); EventService.updateEvent + deleteEvent already exist |
</phase_requirements>

---

## Standard Stack

### Core (all already installed — no pubspec changes)

| Library | Version | Purpose | Why |
|---------|---------|---------|------|
| `flutter_animate` | `^4.5.0` | Section stagger animations in EventSettingsScreen | `.fadeIn().slideY(begin: 0.1)` pattern — same as GroupSettingsScreen |
| `iconsax` | `^0.0.8` | `Iconsax.setting_2`, `Iconsax.trash`, `Iconsax.warning_2`, `Iconsax.arrow_left`, `Iconsax.calendar` | Primary icon library throughout the app |
| `go_router` | `^17.1.0` | New route `/group/:gid/event/:eid/settings` added as child of event hub route | Already wired; just add a sibling GoRoute under `event/:eid` |
| `flutter_riverpod` | `^2.x` | `eventDetailProvider`, `eventServiceProvider`, `currentUserIdProvider` | No new providers needed |
| `shimmer` | `^3.0.0` | `SkeletonLoader.generic(count: 3)` for EventSettingsScreen loading | Existing `SkeletonLoader` shared widget already uses this |

**No new packages. No pubspec.yaml changes required.**

---

## Architecture Patterns

### Recommended File Structure for New Code

```
lib/features/events/
├── screens/
│   ├── event_command_center.dart    (MODIFY — gear icon, date range subtitle)
│   └── event_settings_screen.dart   (NEW)
├── widgets/
│   ├── event_expense_hero.dart      (MODIFY — loading state, member count)
│   ├── event_info_section.dart      (NEW — mirrors group_info_section.dart)
│   └── event_danger_section.dart    (NEW — mirrors group_danger_section.dart)
├── keys/
│   └── event_keys.dart              (MODIFY — add settings screen keys)

lib/core/router/
└── app_router.dart                  (MODIFY — add 'settings' child route under event/:eid)
```

### Pattern 1: Dark Header with Second Subtitle Line

The current `ModuleHeader` widget accepts a single `subtitle` string. The date range must be displayed as a second line below the existing `type · group` line.

**Current subtitle API:** `ModuleHeader(subtitle: '${config.label} · ${group?.name ?? ''}')` — one string rendered in `_buildDark`.

**Issue:** `ModuleHeader` has no `secondSubtitle` parameter. Two options:
- Option A: Pass a `bottom` widget to `ModuleHeader` containing the date range text.
- Option B: Combine into a multi-line subtitle string (newline separator).
- Option C: Extend `ModuleHeader` to accept `subtitle2`.

**Recommendation (HIGH confidence):** Use `ModuleHeader`'s `bottom` parameter — it already exists and renders a widget below the title in both dark and light themes. Pass a `Text` widget with the date range. This is zero-risk, requires no changes to `ModuleHeader`, and matches its intended extension point.

```dart
// Source: lib/shared/widgets/module_header.dart (verified — bottom parameter exists)
ModuleHeader(
  title: event.name,
  subtitle: '${config.label} \u00B7 ${group?.name ?? ''}',
  bottom: Text(
    _formatDateRange(event.startDate, event.endDate),
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Colors.white.withValues(alpha: 0.5),
      letterSpacing: 0.5,
    ),
  ),
  actions: [/* gear icon */],
  useDarkTheme: true,
)
```

**Date range formatter helper** (new private method in `EventCommandCenter`):
```dart
String _formatDateRange(DateTime? start, DateTime? end) {
  if (start == null && end == null) return '';
  final now = DateTime.now();
  final sameYear = (start?.year ?? now.year) == now.year &&
                   (end?.year ?? now.year) == now.year;
  final months = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
  if (start == null) return '${months[end!.month - 1]} ${end.day}';
  if (end == null)   return '${months[start.month - 1]} ${start.day}';
  final startStr = '${months[start.month - 1]} ${start.day}';
  final endStr   = '${months[end.month - 1]} ${end.day}';
  return '$startStr \u2013 $endStr'; // en-dash U+2013
}
```

### Pattern 2: EventSettingsScreen (mirrors GroupSettingsScreen exactly)

Structure: `Scaffold` → `SafeArea` → `groupAsync.when(data:..., loading:..., error:...)`. The data branch renders `SingleChildScrollView` → `Padding(24)` → `Column` containing back button, page title, sections with stagger animations.

```dart
// Source: lib/features/groups/screens/group_settings_screen.dart (verified)
// Pattern: ConsumerWidget reading eventDetailProvider + groupDetailProvider
// Stagger delays: 100ms / 200ms, duration 400ms
EventInfoSection(...).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),
const SizedBox(height: 16),
EventDangerSection(...).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
```

### Pattern 3: EventInfoSection (mirrors GroupInfoSection)

`ConsumerStatefulWidget` with local `TextEditingController`s for name, start date, end date, description. Save button calls `ref.read(eventServiceProvider).updateEvent(...)`.

Key difference from GroupInfoSection: date fields show `DatePicker` on tap (not text input), description is multi-line.

**EventService.updateEvent signature (verified from codebase):**
```dart
// Source: lib/features/events/services/event_service.dart
Future<void> updateEvent({
  required String groupId,
  required String eventId,
  String? name,
  DateTime? startDate,
  DateTime? endDate,
  // Note: no description field in current signature
})
```

**Gap identified:** `EventService.updateEvent` does not accept a `description` field. The `Event` model also has no `description` field. Per the UI-SPEC, description is an editable field. This means either:
- The description field is a new field requiring a model/service change, OR
- The UI-SPEC description maps to an existing field (e.g., event name handles it via multi-line, or description is omitted for MVP)

**Recommendation:** Add `description` to `Event` model and `EventService.updateEvent` as a nullable `String?` field. This is a small model addition. The planner should create a separate wave-0 task for the model extension.

### Pattern 4: EventDangerSection (mirrors GroupDangerSection)

**Balance-gate logic:** Read `eventSettlementsProvider` and `eventExpensesProvider` inline. Compute whether any net balance is non-zero using `BalanceCalculator` or simple fold. If unsettled, show amber warning row; delete button remains tappable but dialog shows additional text.

**Creator check:** `currentUserIdProvider` (from `group_balance_provider.dart`) returns `FirebaseConfig.currentUser?.uid`. Compare with `event.createdBy`. Non-creators: entire `EventDangerSection` is omitted per UI-SPEC.

**Delete mutation:** `ref.read(eventServiceProvider).deleteEvent(groupId: groupId, eventId: eventId)` — already soft-deletes (sets `isDeleted: true`). After delete, navigate `context.go('/group/$groupId')`.

**Activity logging:** Per STATE.md Phase 30 P01 decision, `event_deleted` logging was deferred to Phase 31+. Add activity log call here:
```dart
// Source: STATE.md Phase 30 P01 decisions
try {
  ref.read(groupActivityServiceProvider).logGroupEvent(
    groupId: groupId,
    type: 'event_deleted',
    actorId: actorId,
    actorName: actorName,
    description: 'deleted the event ${event.name}',
  );
} catch (_) {
  // Never crash the delete flow
}
```

### Pattern 5: Router — Add Settings Route

The new settings route is a sibling of `ledger`, `gear`, etc. under `event/:eid`:

```dart
// Source: lib/core/router/app_router.dart lines 254-440 (verified)
// Add inside the event/:eid routes list, alongside ledger, gear, etc.
GoRoute(
  path: 'settings',
  pageBuilder: (context, state) => CustomTransitionPage(
    key: state.pageKey,
    child: EventSettingsScreen(
      groupId: state.pathParameters['gid']!,
      eventId: state.pathParameters['eid']!,
    ),
    transitionsBuilder: _slideRightTransition,
  ),
),
```

Also add to `AppRoutes` constants:
```dart
static const String eventSettings = '/group/:gid/event/:eid/settings';
```

### Pattern 6: EventExpenseHero Loading State Refresh

Replace `CircularProgressIndicator` in the `loading:` branch with `SkeletonLoader` shimmer:

```dart
// Current (lib/features/events/screens/event_expense_hero.dart line 134):
loading: () => SizedBox(
  height: 80,
  child: Center(child: CircularProgressIndicator(...)),
),

// Replace with:
loading: () => SkeletonLoader.generic(count: 1),  // height ~80dp
```

### Anti-Patterns to Avoid

- **Do not change `EventModuleList` stagger logic** — the existing 80ms per-card delay with `flutter_animate` is working and tested.
- **Do not use `Navigator.push` for the settings route** — `context.push('/group/$groupId/event/$eventId/settings')` is the correct GoRouter pattern.
- **Do not add `description` as a hardcoded text field without updating the Event model** — the planner must include the model extension as a prerequisite wave task.
- **Do not omit `context.mounted` check before navigation after async mutation** — see GroupDangerSection._executeDelete pattern.
- **Do not use `Colors.white.withOpacity()` — use `Colors.white.withValues(alpha: X)`** — project convention (verified from module_header.dart).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Settings screen layout | Custom scaffold pattern | GroupSettingsScreen pattern (card sections + stagger) | Already battle-tested, matches visual design contract |
| Danger section | Custom delete flow | GroupDangerSection pattern (AlertDialog + fire-and-forget nav) | Exact same UX shape; deviation adds inconsistency |
| Date picker | Custom date input | Flutter `showDatePicker()` built-in (material) | Standard, handles locale/accessibility |
| Balance check | Custom balance computation | `eventExpensesProvider` + `eventSettlementsProvider` fold | Providers already established; same data used by EventExpenseHero |
| Skeleton loading | Custom shimmer widget | `SkeletonLoader.generic(count: N)` shared widget | Already installed and used throughout the app |

---

## Common Pitfalls

### Pitfall 1: ModuleHeader Has No `subtitle2` Parameter

**What goes wrong:** Developer tries to show date range as a separate subtitle but discovers `ModuleHeader` only accepts one `subtitle` string. Either concatenates with `\n` (which may break styling) or modifies `ModuleHeader` (risky shared widget change).

**How to avoid:** Use the existing `bottom` parameter — it accepts a `Widget` and renders below the title in both dark and light themes.

**Warning signs:** Checking the widget signature and seeing only one `subtitle` String parameter.

### Pitfall 2: Event Model Missing `description` Field

**What goes wrong:** EventInfoSection is built with a description `TextEditingController`, but `event.description` doesn't exist. Compile error or silent data loss.

**How to avoid:** Add `description` to the `Event` model and `EventService.updateEvent` in wave 0 (before any UI work on EventInfoSection).

**Warning signs:** `event.description` throws "getter not found" at compile time.

### Pitfall 3: Test Router Missing `settings` Route

**What goes wrong:** The test `_wrapEventHub` helper in `event_command_center_test.dart` builds a local GoRouter that doesn't include the `settings` route. Tapping the gear icon causes a navigation assertion or silent failure in tests.

**How to avoid:** Update `_wrapEventHub` to add the `settings` stub route under `event/:eid`:
```dart
GoRoute(
  path: 'settings',
  builder: (_, state) => Scaffold(body: Text('EventSettings:${state.pathParameters['eid']}')),
),
```

**Warning signs:** `_wrapEventHub` test helper not updated when new routes are added.

### Pitfall 4: `currentUserIdProvider` Returns `String?` (Nullable)

**What goes wrong:** Comparing `currentUserId == event.createdBy` silently returns `false` when user is null (e.g., in tests). The danger section is hidden for all users in tests.

**How to avoid:** Use `final currentUserId = ref.watch(currentUserIdProvider)` and guard with `currentUserId != null && currentUserId == event.createdBy`.

**Warning signs:** EventDangerSection always hidden; balance-gate tests can't trigger the delete flow.

### Pitfall 5: Date Picker Returns Local Time, Firestore Expects UTC

**What goes wrong:** `showDatePicker` returns a `DateTime` in local time. `EventService.updateEvent` passes this to `Timestamp.fromDate(startDate)`. Depending on timezone, stored date drifts by hours.

**How to avoid:** Normalize to UTC before passing to EventService: `startDate.toUtc()`. Same pattern as `EventService.createEvent` which uses `DateTime.now().toUtc()`.

### Pitfall 6: `onChanged`/`onTap` Must Be Synchronous (Phase 26 P01 Decision)

**What goes wrong:** Async callbacks on interactive widgets (haptics, state updates) cause `pumpAndSettle` to hang in tests.

**How to avoid:** Per STATE.md Phase 26 P01 decision — fire haptics fire-and-forget (`HapticService.medium()` with no await), synchronous `setState()` calls. Do not `await` anything in `onTap` handlers directly; use `Future.microtask` or `unawaited` if needed.

---

## Code Examples

### Gear Icon in Dark Header (Action Slot)

```dart
// Source: EventCommandCenter modification (mirrors GroupDetailScreen pattern)
// Replace Iconsax.more_circle with Iconsax.setting_2
Semantics(
  label: 'Event settings',
  button: true,
  child: IconButton(
    icon: const Icon(Iconsax.setting_2, color: Colors.white, size: 22),
    onPressed: () {
      HapticService.medium();
      context.push('/group/$groupId/event/$eventId/settings');
    },
  ),
),
```

### AlertDialog for Delete Confirmation (from GroupDangerSection pattern)

```dart
// Source: lib/features/groups/widgets/group_danger_section.dart (verified)
showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: Text(
      'Delete this event?',
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600,
                       color: AppColorTokens.light.textPrimary),
    ),
    content: Text(
      'This will permanently delete the event and all its expenses, '
      'gear items, and documents. This cannot be undone.',
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400,
                       color: AppColorTokens.light.textSecondary),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(ctx).pop(),
        child: Text('Keep event',
          style: TextStyle(color: AppColorTokens.light.textSecondary)),
      ),
      TextButton(
        onPressed: () {
          Navigator.of(ctx).pop();
          HapticService.medium();
          _executeDelete(context, ref);
        },
        child: Text('Delete event',
          style: TextStyle(color: AppColorTokens.light.errorText,
                           fontWeight: FontWeight.w600)),
      ),
    ],
  ),
);
```

### Date Range Display (Header Bottom Widget)

```dart
// Source: UI-SPEC.md date range format + ModuleHeader bottom parameter
static String _formatDateRange(DateTime? start, DateTime? end) {
  const months = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
  if (start == null && end == null) return '';
  if (start == null) return '${months[end!.month-1]} ${end.day}';
  if (end == null)   return '${months[start.month-1]} ${start.day}';
  return '${months[start.month-1]} ${start.day}'
       ' \u2013 '   // en-dash U+2013
       '${months[end.month-1]} ${end.day}';
}
```

---

## Runtime State Inventory

Step 2.5 does not apply — this phase is a screen refresh and new screen creation. No rename, refactor, or migration involved.

---

## Environment Availability

Step 2.6: SKIPPED — phase is purely Flutter UI code. No external services, CLIs, or databases beyond the existing Firebase project are required. All tools confirmed present in prior phases.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Flutter Test (flutter_test SDK) |
| Config file | none — standard `flutter test` |
| Quick run command | `flutter test test/features/events/event_command_center_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ECC-01 | Gear icon visible in header | widget | `flutter test test/features/events/event_command_center_test.dart` | Modify existing |
| ECC-01 | Gear icon tap navigates to settings route | widget | `flutter test test/features/events/event_command_center_test.dart` | Modify existing |
| ECC-01 | Date range shown when event has startDate/endDate | widget | `flutter test test/features/events/event_command_center_test.dart` | Modify existing |
| ECC-01 | Date range hidden when dates are null | widget | `flutter test test/features/events/event_command_center_test.dart` | Modify existing |
| ECC-02 | EventSettingsScreen renders event name in input | widget | `flutter test test/features/events/event_settings_screen_test.dart` | New — Wave 0 |
| ECC-02 | Save Changes calls eventService.updateEvent | widget | `flutter test test/features/events/event_settings_screen_test.dart` | New — Wave 0 |
| ECC-02 | Delete event button hidden for non-creator | widget | `flutter test test/features/events/event_settings_screen_test.dart` | New — Wave 0 |
| ECC-02 | Delete event shows confirmation dialog | widget | `flutter test test/features/events/event_settings_screen_test.dart` | New — Wave 0 |
| ECC-02 | Delete calls eventService.deleteEvent on confirm | widget | `flutter test test/features/events/event_settings_screen_test.dart` | New — Wave 0 |

### Sampling Rate

- **Per task commit:** `flutter test test/features/events/`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/features/events/event_settings_screen_test.dart` — covers ECC-02 requirements (new file)
- [ ] `_wrapEventHub` helper in `event_command_center_test.dart` needs `settings` stub route added

*(Existing `event_command_center_test.dart` is modified in-place to cover ECC-01 additions. No new framework config needed.)*

---

## Open Questions

1. **Event `description` field**
   - What we know: UI-SPEC requires an editable description field; `Event` model has no `description` field; `EventService.updateEvent` has no `description` parameter
   - What's unclear: Was description intentionally omitted (scope decision) or an oversight?
   - Recommendation: Planner should include a wave-0 task to add `description: String?` to `Event.fromDoc`, `Event.toFirestoreMap`, `Event.copyWith`, and `EventService.updateEvent`. This is a 1-hour task. If out of scope, EventInfoSection simply omits the description field.

2. **Balance-gate computation for event delete**
   - What we know: UI-SPEC says "balance-gated like group delete"; GroupDangerSection does NOT actually check balances — it just always shows the warning. The "balance-gate" in group is UI-only (shows amber row but doesn't block deletion).
   - What's unclear: Should EventDangerSection actually compute unsettled balances, or just mirror the structural pattern from GroupDangerSection?
   - Recommendation: Compute actual unsettled balances for events (more correct than group pattern) using `eventSettlementsProvider` + `eventExpensesProvider`. If net balance is non-zero, show amber warning row. Keep the "proceed anyway" path available per UI-SPEC dialog copy.

---

## Sources

### Primary (HIGH confidence)

- Codebase: `lib/features/events/screens/event_command_center.dart` — current 186-line implementation, confirmed structure
- Codebase: `lib/features/events/services/event_service.dart` — `updateEvent`, `deleteEvent` signatures verified
- Codebase: `lib/features/groups/screens/group_settings_screen.dart` — settings screen pattern to mirror
- Codebase: `lib/features/groups/widgets/group_danger_section.dart` — danger section pattern
- Codebase: `lib/features/groups/widgets/group_info_section.dart` — info section pattern
- Codebase: `lib/shared/widgets/module_header.dart` — `bottom` parameter confirmed; dark theme pattern
- Codebase: `lib/core/router/app_router.dart` — route tree structure for adding settings sub-route
- Codebase: `lib/features/events/models/event_model.dart` — `description` field confirmed absent
- Codebase: `lib/core/theme/tokens/color_tokens.dart` — `inputFillWarm`, `borderWarm`, `focusBorderWarm`, `primaryGradient` all verified
- Codebase: `test/features/events/event_command_center_test.dart` — existing test patterns and provider overrides
- `.planning/phases/31-event-command-center/31-CONTEXT.md` — locked decisions
- `.planning/phases/31-event-command-center/31-UI-SPEC.md` — component contracts, color/spacing tokens, copywriting

### Secondary (MEDIUM confidence)

- STATE.md Phase 30 P01 decisions — `event_deleted` activity logging deferred to Phase 31+
- STATE.md Phase 26 P01 decisions — `onChanged`/`onTap` must be synchronous for test compatibility

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages verified installed, no new dependencies
- Architecture: HIGH — all patterns verified from working code in Phase 28/29
- Pitfalls: HIGH — verified from codebase patterns and STATE.md decisions
- Open question (description field): MEDIUM — model gap confirmed but resolution is a judgment call

**Research date:** 2026-04-05
**Valid until:** 2026-05-05 (stable Flutter/Riverpod/GoRouter — no fast-moving packages)
