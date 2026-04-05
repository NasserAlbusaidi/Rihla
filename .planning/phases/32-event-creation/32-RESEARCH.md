# Phase 32: Event Creation - Research

**Researched:** 2026-04-05
**Domain:** Flutter visual refresh — earthy token system, ModuleHeader, card-section layout, stagger animations
**Confidence:** HIGH

## Summary

Both screens being refreshed (`EventTypePickerScreen`, 184 lines; `CreateEventScreen`, 605 lines) are fully functional. No backend, routing, or business logic changes are needed. The work is entirely styling: swap the system AppBar for a dark `ModuleHeader`, apply earthy `AppColorTokens` to every visual surface, align the event type indicator and card sections to the Phase 29 `GroupSettingsScreen` layout pattern, and fix the five hardcoded hex values in `EventTypeConfig` so they use token names.

The existing test suite in `test/features/events/create_event_test.dart` covers both screens with 10 widget tests. Tests use `find.byKey(EventKeys.*)` and `find.text(...)` — key-based assertions are safe across visual changes; text-based assertions referencing AppBar titles (`'New Trip Event'`, `'Choose Event Type'`) will need updating if the AppBar is replaced with a `ModuleHeader`.

**Primary recommendation:** Follow the `GroupSettingsScreen` (Phase 29) scaffold pattern exactly — dark `ModuleHeader` with back button, `SingleChildScrollView` with 24px horizontal padding, card sections as separate widgets with staggered `.animate().fadeIn().slideY()`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Type Picker Screen**
- Keep vertical card list layout with earthy token refresh
- Refresh card visuals: colored icon badge with type-specific accent, module chips below description, AppColorTokens
- Dark ModuleHeader ("New Event" + group name subtitle) — consistent with hub screens
- Staggered fade+slide entry animation per card (80ms delay, 400ms duration)

**Create Event Form**
- Card sections layout (ProfileScreen pattern from Phase 29) — event info card + participants card + modules card (custom only)
- Keep inline date fields with tap-to-pick showDatePicker
- Keep checkbox list with "Select All" for participant selection, pre-checks all members
- Fixed bottom "Create Event" button (52dp, primary teal)

**Template & Polish**
- Keep existing template pre-fill behavior — EventModules.forType() sets defaults, camping seeds gear, name field empty
- Navigate to event hub immediately with brief SnackBar "Event created"
- Refresh EventTypeConfig colors to use AppColorTokens (primary for Trip, successText for Camping, etc.)
- SnackBar for validation errors + inline field validation (existing pattern)

### Claude's Discretion
- Exact spacing and padding within earthy token system
- Animation timing details
- Card border radius and shadow values
- Loading state during event creation submission

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

## Standard Stack

### Core (already installed — no new dependencies)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter_animate` | `^4.5.0` | Card stagger fade+slide entrance | Already installed; `.animate().fadeIn().slideY()` pattern used in Phase 29 and 31 |
| `go_router` | `^17.1.0` | Navigation — no changes needed | Already in use; routes unchanged |
| `iconsax` | `^0.0.8` | Module toggle and nav icons | Already in use across all screens |

### Already-established shared widgets

| Widget | File | Purpose |
|--------|------|---------|
| `ModuleHeader` | `lib/shared/widgets/module_header.dart` | Dark gradient header with back button + subtitle |
| `TapBounce` | `lib/shared/animations/tap_bounce.dart` | 0.97 scale press animation, 120ms |
| `LoadingButton` | `lib/shared/widgets/loading_button.dart` | 52dp primary teal submit button with spinner |
| `SkeletonLoader` | `lib/shared/widgets/skeleton_loader.dart` | Loading state for members-not-yet-loaded case |

**No new packages required.** This is a visual refresh of existing code.

## Architecture Patterns

### Recommended Project Structure (no changes)

```
lib/features/events/
├── models/
│   └── event_type_config.dart   # FIX: 5 hardcoded hex → token names
├── screens/
│   ├── event_type_picker_screen.dart   # REFRESH: AppBar → ModuleHeader, token colors
│   └── create_event_screen.dart        # REFRESH: AppBar → ModuleHeader, card layout
├── keys/
│   └── event_keys.dart          # ADD: selectAllButton key for "Select All" row
```

### Pattern 1: Dark ModuleHeader replacing AppBar

**What:** `ModuleHeader(useDarkTheme: true, title: 'New Event', subtitle: groupName)` replaces the system `AppBar`. The screen wraps in `Scaffold(body: Column([ModuleHeader(...), Expanded(child: scrollContent)]))`.

**When to use:** All hub/entry screens (consistently applied in Phase 28–31).

**How ModuleHeader works:**
- `useDarkTheme: true` renders the gray-900 → gray-800 gradient header with grain texture overlay
- Includes its own `_DarkBackButton` (44×44dp, `context.pop()`)
- `subtitle` renders above `title` at 13px, 50% white opacity

**Current state:** Both screens use `AppBar` with default M3 styling. Replacing to `ModuleHeader` removes the system back button — the `ModuleHeader` back button (`_DarkBackButton`) becomes the only back affordance.

**Test impact:** Tests that `find.text('New Trip Event')` or `find.text('Choose Event Type')` as AppBar titles will pass only if those strings remain visible somewhere. With `ModuleHeader`, they appear in the dark header body — `find.text()` still works. The only risk: `find.byKey(EventKeys.eventTypePickerTitle)` is assigned to the AppBar `Text` widget. If AppBar is removed, this key needs to move to the `ModuleHeader` title text.

### Pattern 2: Card-Section Layout (Phase 29 GroupSettingsScreen)

**What:** `SingleChildScrollView` → `Padding(horizontal: 24)` → `Column` of section widgets separated by `SizedBox(height: 16)`. Each section is a self-contained widget (or `Container` with card decoration).

**Card decoration:**
```dart
BoxDecoration(
  color: AppColorTokens.light.cardSurface,    // #F8F9FA
  borderRadius: BorderRadius.circular(16),     // radiusSmall from theme
  boxShadow: AppShadowTokens.standard.raised,
)
```

`CreateEventScreen` already uses `BorderRadius.circular(24)`. The CONTEXT.md says "card border radius and shadow values" are Claude's discretion — maintain 24 for consistency with the current screen.

**Stagger animation — Phase 29 pattern:**
```dart
SectionWidget().animate().fadeIn(delay: 100.ms).slideY(begin: 0.1)
SectionWidget().animate().fadeIn(delay: 200.ms).slideY(begin: 0.1)
SectionWidget().animate().fadeIn(delay: 300.ms).slideY(begin: 0.1)
```

**Type picker stagger (from CONTEXT.md — 80ms delay, 400ms):**
```dart
card.animate()
  .fadeIn(delay: (80 * index).ms, duration: 400.ms)
  .slideY(begin: 0.05, end: 0, delay: (80 * index).ms, duration: 400.ms,
          curve: Curves.easeOutCubic)
```
Current code uses 40ms delay. CONTEXT.md locks 80ms — update required.

### Pattern 3: EventTypeConfig color token mapping

**What:** Five `EventTypeConfig._()` entries use inline `Color(0xFF...)` const literals because `const Map` cannot reference `ThemeExtension` fields at compile time. The comment already documents the intended mapping.

**Required changes per CONTEXT.md** ("primary for Trip, successText for Camping"):

| Event Type | Current Hex | Current Comment | Correct Token |
|-----------|-------------|-----------------|---------------|
| `trip` | `0xFF0D7B74` | `// AppColorTokens.light.primary` | `primary` (#0D7B74) — UNCHANGED value, same hex |
| `camping` | `0xFF10B981` | `// AppColorTokens.light.success` | `successText` (#047857) — VALUE CHANGES from #10B981 to #047857 |
| `travel` | `0xFF6B7280` | `// AppColorTokens.light.textSecondary` | `textSecondary` (#6B7280) — UNCHANGED value |
| `nightDayOut` | `0xFF6B7280` | `// AppColorTokens.light.textSecondary` | `textSecondary` (#6B7280) — UNCHANGED value |
| `custom` | `0xFFF59E0B` | `// AppColorTokens.light.warning` | `warning` (#F59E0B) — UNCHANGED value |

**Key insight:** Camping color changes from `success` (#10B981 — display-only per token doc) to `successText` (#047857 — WCAG-safe 4.56:1 on white). The doc comment on `success` reads "Display only (badges, icons). For text use successText." Since `config.color` is used on the icon background fill (at 10% alpha) AND as the icon color itself, using `successText` gives better text contrast. Update the const hex and the comment.

**Implementation constraint:** These remain inline `Color(0xFF...)` consts — cannot reference `AppColorTokens.light.*` in a `const Map`. Update the hex value and update the comment to note the correct token name and the reason (const map limitation).

### Pattern 4: "Select All" toggle for participants

CONTEXT.md says "Keep checkbox list with 'Select All' for participant selection, pre-checks all members." The current `CreateEventScreen` does NOT have a "Select All" toggle — it only pre-checks all members on load. Adding a "Select All" row above the participant list is required. This is new UI (not a visual refresh of existing) but is small and within scope.

**Implementation:** A row above the member list with a `Checkbox` whose value is `_selectedParticipantIds.length == members.length`. `onChanged` sets `_selectedParticipantIds` to all member IDs (select all) or empty set (deselect all) immutably.

### Anti-Patterns to Avoid

- **`AppColorTokens.light.textMuted` for functional text:** textMuted (#9CA3AF) is documented "decorative use only — never use for functional text, labels, or amounts (fails WCAG AA at 2.86:1 on white)." Current code uses `textMuted` for the description text on type picker cards. This is borderline — description text is secondary/decorative, not a label or amount, so textMuted is acceptable there. Do NOT use textMuted for participant names, section headers, or error messages.
- **`moduleLedgerLight` hardcoded in CreateEventScreen event type indicator:** Current code uses `AppColorTokens.light.moduleLedgerLight` + `moduleLedger` colors for the event type indicator badge regardless of event type. This should use `config.color` with 10% alpha tint for the background and `config.color` for the icon, matching the type-specific accent decided in CONTEXT.md.
- **Mutating `_selectedParticipantIds` in place:** Current code correctly uses `Set.unmodifiable()` on updates. Keep this pattern for the "Select All" toggle.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Press-scale feedback on type cards | Custom GestureDetector + AnimationController | `TapBounce` | Already built, tested, 120ms / 0.97 scale |
| Card entrance animations | Custom AnimatedBuilder / AnimatedOpacity | `flutter_animate` `.animate().fadeIn().slideY()` | Already the project standard |
| Submit button loading state | Custom StatefulWidget with loading flag | `LoadingButton` | 52dp, primary teal, CircularProgressIndicator — already exists |
| Loading skeleton for member list | Custom shimmer | `SkeletonLoader.generic(count: N)` | Already used in GroupSettingsScreen |

## Common Pitfalls

### Pitfall 1: AppBar title key migration
**What goes wrong:** `EventKeys.eventTypePickerTitle` is assigned to the `AppBar` `Text` widget. If the AppBar is replaced by `ModuleHeader`, the key must migrate to the `ModuleHeader` title text widget. Tests asserting `find.byKey(EventKeys.eventTypePickerTitle)` will fail if the key is not present in the new widget.
**Why it happens:** `ModuleHeader` builds the title internally as an unstyled `Text` with no provision for a widget key on the title.
**How to avoid:** Pass the key as a `Key` on the `Text` inside `ModuleHeader`'s build — or add a `titleKey` parameter to `ModuleHeader`, or accept that the test changes to `find.text('New Event')` instead.
**Warning signs:** `find.byKey(EventKeys.eventTypePickerTitle)` returns `findsNothing` after the AppBar swap.

### Pitfall 2: groupName not available in EventTypePickerScreen (StatelessWidget)
**What goes wrong:** CONTEXT.md says the picker header should show "New Event" + group name subtitle. `EventTypePickerScreen` is a `StatelessWidget` with only `groupId`. It does not currently watch `groupDetailProvider`.
**Why it happens:** The group name requires an async provider watch — converting to `ConsumerWidget` or wrapping the header in a `Consumer`.
**How to avoid:** Convert `EventTypePickerScreen` to `ConsumerWidget`. Watch `groupDetailProvider(groupId).valueOrNull?.name ?? ''` for the subtitle. If null (loading), show empty subtitle — the header still renders.
**Warning signs:** Subtitle is always empty or the widget crashes because `ref` is unavailable.

### Pitfall 3: Scaffold body layout breaks with ModuleHeader
**What goes wrong:** `ModuleHeader` is not an `AppBar` — it does not interact with `Scaffold.appBar`. It must be placed in `Scaffold.body` inside a `Column` with the scrollable content in an `Expanded` child.
**Why it happens:** Developers place `ModuleHeader` in `appBar:` slot, which expects a `PreferredSizeWidget`.
**How to avoid:**
```dart
Scaffold(
  body: Column(
    children: [
      ModuleHeader(useDarkTheme: true, title: 'New Event', subtitle: groupName),
      Expanded(child: ListView.separated(...)),
    ],
  ),
)
```
**Warning signs:** Overflow errors, header not visible, content scrolls behind safe area.

### Pitfall 4: const Map constraint forces duplicate hex values
**What goes wrong:** Developer tries `color: AppColorTokens.light.successText` inside `EventTypeConfig._()` and gets a compile error — `ThemeExtension` fields are not `const`.
**Why it happens:** `const Map<EventType, EventTypeConfig>` requires all values to be const.
**How to avoid:** Keep inline `Color(0xFF...)` literals. Update the hex to match the target token value. Update the comment to document which token it represents.
**Warning signs:** `The value of the field 'color' must be constant` compile error.

### Pitfall 5: "Select All" creates observable mutable state divergence
**What goes wrong:** "Select All" checkbox uses `members.length == _selectedParticipantIds.length` to determine its checked state. But `_selectedParticipantIds` is a `Set.unmodifiable()`. Trying to call `.add()` / `.remove()` on it will throw.
**Why it happens:** The immutable pattern requires creating a new `Set.from()` before modification, then wrapping in `Set.unmodifiable()` for storage.
**How to avoid:** Always follow the established pattern: `setState(() => _selectedParticipantIds = Set.unmodifiable(Set<String>.from(members.map((m) => m.userId))))`.

## Code Examples

### ModuleHeader with group name subtitle (ConsumerWidget pattern)

```dart
// Source: lib/shared/widgets/module_header.dart + Phase 28/29 usage
class EventTypePickerScreen extends ConsumerWidget {
  final String groupId;
  const EventTypePickerScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupName = ref.watch(groupDetailProvider(groupId)).valueOrNull?.name ?? '';
    final types = EventTypeConfig.allTypes;
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      key: EventKeys.eventTypePickerScreen,
      backgroundColor: AppColorTokens.light.scaffoldBackground,
      body: Column(
        children: [
          ModuleHeader(
            useDarkTheme: true,
            title: 'New Event',
            subtitle: groupName.isEmpty ? null : groupName,
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: types.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                // ... card with 80ms stagger
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

### Type-specific icon badge (token-mapped color)

```dart
// Replaces config.color.withValues(alpha: 0.1) background + config.color icon
// config.color is already the correct token value from EventTypeConfig
Container(
  width: 48,
  height: 48,
  decoration: BoxDecoration(
    color: config.color.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(14),
  ),
  child: Icon(config.icon, size: 24, color: config.color),
)
```

### Select All row (immutable pattern)

```dart
// Above members.map(...) in Participants card
Row(
  children: [
    Expanded(
      child: Text('Select All', style: Theme.of(context).textTheme.titleSmall),
    ),
    Checkbox(
      value: _selectedParticipantIds.length == members.length,
      checkColor: Colors.white,
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColorTokens.light.primary
            : null,
      ),
      onChanged: (v) {
        final allIds = Set<String>.from(members.map((m) => m.userId));
        setState(() => _selectedParticipantIds =
            Set.unmodifiable(v == true ? allIds : <String>{}));
      },
    ),
  ],
),
```

### Card-section stagger (Phase 29 pattern)

```dart
// In CreateEventScreen build(), inside SingleChildScrollView column:
_EventInfoCard(
  nameController: _nameController,
  startDate: _startDate,
  endDate: _endDate,
  onPickStart: _pickStartDate,
  onPickEnd: _pickEndDate,
  typeConfig: typeConfig,
).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),

const SizedBox(height: 16),

_ParticipantsCard(
  members: members,
  selectedIds: _selectedParticipantIds,
  onToggle: ...,
).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
```

### EventTypeConfig camping color fix

```dart
// In event_type_config.dart — change camping from success to successText hex:
EventType.camping: EventTypeConfig._(
  type: EventType.camping,
  label: 'Camping',
  description: 'Outdoor adventure with gear tracking',
  icon: Iconsax.tree,
  color: Color(0xFF047857), // AppColorTokens.light.successText — WCAG 4.56:1 on white
                             // (const map cannot reference ThemeExtension fields)
),
```

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| System `AppBar` | Dark `ModuleHeader` (Phase 28+) | Consistent dark gradient entry pattern across all hub/entry screens |
| Hardcoded spacing | `AppColorTokens.*` tokens | Color changes are single-source |
| `success` for camping icon | `successText` for camping icon | WCAG AA compliance on icon color |

## Open Questions

1. **`eventTypePickerTitle` key migration**
   - What we know: Key is currently on the AppBar `Text('Choose Event Type', key: EventKeys.eventTypePickerTitle)`. The test `find.byKey(EventKeys.eventTypePickerTitle)` expects to find it.
   - What's unclear: `ModuleHeader` does not expose a key parameter for the title text. Either add one, skip the key in tests (switch to `find.text('New Event')`), or keep the old text with a different key approach.
   - Recommendation: Add a `Key? titleKey` parameter to `ModuleHeader` and pass `EventKeys.eventTypePickerTitle`. Update the test if the title text changes from "Choose Event Type" to "New Event".

2. **"Select All" scope**
   - What we know: CONTEXT.md says "Keep checkbox list with 'Select All' for participant selection". The current screen has no "Select All" row.
   - What's unclear: Should "Select All" deselect all when all are already selected (toggle behavior), or always select all?
   - Recommendation: Standard toggle: if all selected → deselect all; if any unselected → select all.

## Environment Availability

Step 2.6: SKIPPED — purely visual/code changes, no external dependencies. `flutter test` and `flutter analyze` are the only tools needed; both confirmed available from project setup.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (Flutter SDK) + mocktail |
| Config file | none — standard `flutter test` |
| Quick run command | `flutter test test/features/events/create_event_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Behavior | Test Type | Automated Command | File Exists? |
|----------|-----------|-------------------|-------------|
| EventTypePickerScreen shows dark ModuleHeader with "New Event" title | widget | `flutter test test/features/events/create_event_test.dart -N "shows"` | ✅ needs update |
| All 5 event type cards visible with type-specific accent colors | widget | `flutter test test/features/events/create_event_test.dart` | ✅ existing covers label/description |
| Staggered entrance animation (80ms delay, respect disableAnimations) | widget | `flutter test test/features/events/create_event_test.dart` | ✅ disableAnimations path in code |
| CreateEventScreen shows dark ModuleHeader with event type subtitle | widget | `flutter test test/features/events/create_event_test.dart -N "AppBar"` | ✅ needs title assertion update |
| Card-section layout: event info card + participants card + modules card | widget | `flutter test test/features/events/create_event_test.dart` | ✅ existing covers key-based sections |
| "Select All" checkbox pre-checks all members | widget | `flutter test test/features/events/create_event_test.dart -N "Select All"` | ❌ Wave 0 — new test needed |
| EventTypeConfig camping color uses successText hex (#047857) | unit | `flutter test test/unit/event_model_test.dart` | ❌ Wave 0 — add color assertion |
| Navigation to event hub after creation | widget | `flutter test test/features/events/create_event_test.dart` | ✅ (navigation test exists via GoRouter) |

### Sampling Rate
- **Per task commit:** `flutter test test/features/events/create_event_test.dart`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] Add test: "Select All" row appears in Participants card → select/deselect behavior
- [ ] Add test: EventTypeConfig camping color == Color(0xFF047857)
- [ ] Update test: "shows AppBar title with event type name" → update for ModuleHeader
- [ ] Update test: "shows AppBar title 'Choose Event Type'" → update for "New Event"

## Sources

### Primary (HIGH confidence)
- Direct code read: `lib/features/events/screens/event_type_picker_screen.dart` — current state, 184 lines
- Direct code read: `lib/features/events/screens/create_event_screen.dart` — current state, 605 lines
- Direct code read: `lib/features/events/models/event_type_config.dart` — color mappings, const map constraint
- Direct code read: `lib/core/theme/tokens/color_tokens.dart` — all token values, WCAG annotations
- Direct code read: `lib/shared/widgets/module_header.dart` — exact ModuleHeader API
- Direct code read: `lib/shared/widgets/loading_button.dart` — 52dp button, existing API
- Direct code read: `lib/shared/animations/tap_bounce.dart` — 0.97/120ms animation
- Direct code read: `lib/features/groups/screens/group_settings_screen.dart` — Phase 29 card-section + stagger pattern
- Direct code read: `test/features/events/create_event_test.dart` — existing test coverage, assertion patterns
- Direct code read: `lib/features/events/keys/event_keys.dart` — all declared widget keys
- `.planning/phases/32-event-creation/32-CONTEXT.md` — locked decisions and discretion areas

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already installed and in use
- Architecture patterns: HIGH — Phase 29 GroupSettingsScreen is a direct reference implementation in the same codebase
- Pitfalls: HIGH — identified from actual current code divergences (const map, key migration, groupName missing from picker)
- Token mapping: HIGH — read directly from color_tokens.dart with inline WCAG annotations

**Research date:** 2026-04-05
**Valid until:** Stable — no external dependencies; valid until codebase changes
