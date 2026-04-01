# Phase 24: Visual Density & Polish - Research

**Researched:** 2026-04-01
**Domain:** Flutter widget composition, Riverpod async family providers, custom bar chart rendering
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Group Card Enrichment**
- D-01: Add a "last event" context line below the balance showing event name + relative date (e.g., "Camping Trip — 2 days ago"). Data from `groupEventsProvider` (already exists).
- D-02: Include a small event type icon (16px) before the event name. Icons already exist in EventTypeConfig.
- D-03: Groups with zero events show "No events yet" in muted text as the context line.
- D-04: Keep member count badge as-is (icon + number). No avatar circles.
- D-05: Keep exact balance amounts ("You owe OMR 12.500"). No simplification.

**Card Visual Distinction**
- D-06: 4px vertical color accent strip on the left edge of each group card.
- D-07: Accent color assigned via hash of group ID, cycling through 5-6 earthy palette colors from AppColorTokens.
- D-08: Color accent is strip only — rest of card stays neutral card surface. No background tint.

**Chart Improvements**
- D-09: Add amount label at the end/top of each bar showing the day's spending (e.g., "12.5"). Non-zero bars only.
- D-10: Zero-spending days keep the 2px gray placeholder bar with no label.
- D-11: Chart title changes from "This Week" to "Weekly Spending (OMR)".

**Dashboard Density & Rhythm**
- D-12: Tighten inter-section spacing from current 16-24px to a consistent 12px between major sections.
- D-13: Add "Your Groups (N)" section header above the group card list, where N is the group count.
- D-14: Keep current section order: Balance Hero → Quick Actions → Groups → Activity → Chart.

### Claude's Discretion
- Exact earthy color palette for accent strips (pick 5-6 from existing AppColorTokens)
- Amount label formatting on chart bars (decimal places, font size)
- "Your Groups" header typography and styling
- Group card internal spacing adjustments to accommodate the new context line
- Event type icon selection and mapping logic

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CARD-01 | Group card shows visual differentiation between groups (color accent, event count, or member indicators) | D-06/D-07: 4dp accent strip using groupId.hashCode.abs() % 5 from AppColorTokens |
| CARD-02 | Group card displays richer context — last event name, recent activity hint, or total group spend | D-01/D-02/D-03: last-event context line via groupEventsProvider, EventTypeConfig icons |
| CHRT-01 | Weekly spending chart shows amount labels on bars or Y-axis so values are readable | D-09/D-10: amount label Text widget above non-zero bars, SizedBox height increases 80→96 |
| CHRT-02 | Chart title explicitly says "Weekly Spending" with currency context | D-11: change 'This Week' → 'Weekly Spending (OMR)' |
| LAYT-01 | Dashboard has improved visual density — tighter spacing, less dead whitespace | D-12: all inter-section gaps reduced to 12dp |
| LAYT-02 | Group list section has a clear header and visual separation from quick actions and activity | D-13: "Your Groups (N)" SliverToBoxAdapter inserted before group cards sliver |
</phase_requirements>

---

## Summary

Phase 24 is a pure widget-composition phase — no new providers, no new routes, no new screens, no data layer changes. All three target files (`group_card.dart`, `weekly_spending_card.dart`, `home_screen.dart`) are well-understood and have existing test coverage to extend.

The primary implementation risk is the GroupCard restructure: the card must gain a 4dp accent strip on its left edge while keeping `borderRadius: 16` and `clipBehavior: Clip.hardEdge` so the strip corners are flush with the card. Without `clipBehavior`, the strip bleeds outside the rounded card. The card currently uses a plain `Container` with `padding: all(16)` — that padding must be restructured to put the strip outside the padded content area.

The WeeklySpendingCard chart bar label addition is mechanical but has one sizing constraint: the outer `SizedBox(height: 80)` must grow to 96dp to prevent the label text from being clipped above the bar.

The dashboard spacing changes in `home_screen.dart` are straightforward but require auditing every `SizedBox` and padding value in the sliver list — the current code mixes explicit `SizedBox` heights (16dp) and padding-based gaps (24dp top in activity section).

**Primary recommendation:** Work in file order: `group_card.dart` → `weekly_spending_card.dart` → `home_screen.dart`. Tests before each file.

---

## Standard Stack

### Core (already installed — no installation needed)

| Library | Version | Purpose | Why Relevant |
|---------|---------|---------|--------------|
| `flutter_riverpod` | `^2.6.1` | Async provider for `groupEventsProvider(group.id)` in GroupCard | GroupCard becomes a ConsumerWidget watching a family provider |
| `iconsax` | `^0.0.8` | `EventTypeConfig.icon` values are all `Iconsax.*` constants | Already used in group_card.dart |
| `timeago` | already in pubspec | Relative timestamp for event context line | Already used in activity_row.dart — same pattern |
| `decimal` | already in pubspec | Amount formatting in chart bars | Already used in weekly_spending_card.dart |

### No New Dependencies
This phase introduces zero new packages. All required capabilities are already in the project.

---

## Architecture Patterns

### Pattern 1: Accent Strip via ClipRRect + Row

**What:** Wrap the card `Container` in a `ClipRRect` so the 4dp strip inherits the card's 16dp corner radius. The strip is a `Container(width: 4, color: accentColor)` in a `Row` alongside the padded content.

**When to use:** Whenever a colored left-edge strip must respect parent border radius.

**Example:**
```dart
// Source: UI-SPEC.md Component Inventory / CONTEXT.md D-06
ClipRRect(
  borderRadius: BorderRadius.circular(16),
  child: Container(
    decoration: BoxDecoration(
      color: AppColorTokens.light.cardSurface,
      borderRadius: BorderRadius.circular(16),
      boxShadow: AppShadowTokens.standard.raised,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(width: 4, color: _accentColor(group.id)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: /* existing Column content */,
          ),
        ),
      ],
    ),
  ),
)
```

Note: `BoxDecoration` with `borderRadius` on the outer `Container` and `ClipRRect` wrapping it both handle the clipping. Use `ClipRRect` as the outermost wrapper OR set `clipBehavior: Clip.hardEdge` on the `Container` itself. The UI-SPEC uses the latter. Either approach works — pick one and be consistent.

### Pattern 2: Hash-Based Deterministic Color (from ActivityRow)

**What:** `someString.hashCode.abs() % n` selects from a fixed list of colors.

**When to use:** When a set of items need distinct but stable visual identity without stored configuration.

**Example:**
```dart
// Source: lib/features/home/widgets/activity_row.dart (existing pattern)
// Adapted for group accent strips (D-07)
static const List<Color> _accentColors = [
  Color(0xFF0D7B74), // slot 0 — primary (AppColorTokens.light.primary)
  Color(0xFFCC6B49), // slot 1 — terracotta (AppColorTokens.light.focusBorderWarm)
  Color(0xFF10B981), // slot 2 — success (AppColorTokens.light.success)
  Color(0xFFF59E0B), // slot 3 — warning (AppColorTokens.light.warning)
  Color(0xFF7C6E5A), // slot 4 — warm umber (inline const — no token exists)
];

Color _accentColor(String groupId) =>
    _accentColors[groupId.hashCode.abs() % _accentColors.length];
```

Per UI-SPEC: slot 4 (`#7C6E5A`) is an inline const — do NOT add it as a new `AppColorTokens` field. The CI check blocks new `Color(0xFF...)` literals in theme files only, not in widget files.

### Pattern 3: ConsumerWidget Watching family Provider in GroupCard

**What:** GroupCard already watches `groupBalancesProvider(group.id)`. Adding `groupEventsProvider(group.id)` follows the same pattern.

**Example:**
```dart
// Source: existing group_card.dart lines 29-30 — extended for context line
final balancesAsync = ref.watch(groupBalancesProvider(group.id));
final eventsAsync = ref.watch(groupEventsProvider(group.id));  // NEW

// Context line rendering
eventsAsync.when(
  data: (events) {
    if (events.isEmpty) {
      return Text('No events yet', style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: AppColorTokens.light.textMuted,
      ));
    }
    final latest = events.first; // already sorted by createdAt desc per event_provider.dart
    final config = EventTypeConfig.forType(latest.type);
    return Row(
      children: [
        Icon(config.icon, size: 16, color: AppColorTokens.light.textMuted),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '${latest.name} — ${timeago.format(latest.createdAt)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColorTokens.light.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  },
  // Show same fallback while loading and on error — avoids layout shift
  loading: () => Text('No events yet', style: Theme.of(context).textTheme.bodySmall?.copyWith(
    color: AppColorTokens.light.textMuted,
  )),
  error: (_, __) => Text('No events yet', style: Theme.of(context).textTheme.bodySmall?.copyWith(
    color: AppColorTokens.light.textMuted,
  )),
)
```

### Pattern 4: Chart Bar Label Column Layout

**What:** Add a `Text` label above the bar `Container`, wrapped in a `Column` with `mainAxisAlignment: MainAxisAlignment.end`. Increase outer `SizedBox` height from 80 to 96.

**When to use:** When a proportional bar chart needs value annotations above bars.

**Example:**
```dart
// Source: UI-SPEC.md Component Inventory / weekly_spending_card.dart line 78
SizedBox(
  height: 96,  // was 80 — 16dp added for label row
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: weekData.map((entry) {
      // ... existing fraction/barHeight computation unchanged ...
      final showLabel = entry.amount > Decimal.zero;
      final amountLabel = entry.amount.toStringAsFixed(1);

      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (showLabel)
              Text(
                amountLabel,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280), // textSecondary
                ),
              ),
            if (showLabel) const SizedBox(height: 4),
            Container(/* existing bar */),
            const SizedBox(height: 4),
            Text(dayLabel, /* existing */),
          ],
        ),
      );
    }).toList(),
  ),
)
```

Note: The 9sp font size is an implementation detail constrained by bar column geometry. Per UI-SPEC it is not a new type scale token — do not add it to the theme.

### Pattern 5: SliverToBoxAdapter Section Header

**What:** New sliver inserted between QuickActionTray and group card slivers in `home_screen.dart`.

**Example:**
```dart
// Source: UI-SPEC.md Component Inventory / CONTEXT.md D-13
SliverPadding(
  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
  sliver: SliverToBoxAdapter(
    child: Text(
      'Your Groups (${groups.length})',
      style: Theme.of(context).textTheme.titleMedium,
    ),
  ),
),
```

### Anti-Patterns to Avoid

- **Clip without ClipRRect:** Setting `borderRadius` on a `Container` does NOT clip child widgets. The accent strip will bleed outside the card corners unless `clipBehavior: Clip.hardEdge` is set on the outer `Container` OR a `ClipRRect` wraps it.
- **Padding on outer Container:** When adding the accent strip, the `padding: EdgeInsets.all(16)` must move from the outer `Container` to the `Expanded` child — otherwise the strip gets inset by the padding and doesn't touch the card edge.
- **New color token for slot 4:** `#7C6E5A` has no `AppColorTokens` field. Use an inline `const Color(0xFF7C6E5A)` directly in `group_card.dart`. Do not add a new field to `AppColorTokens` (breaks the constraint that new tokens require a design decision).
- **Hardcoded Color literals in tokens files:** CI blocks hardcoded `Color(0xFF...)` in theme token files. Widget files are exempt.
- **Mutation:** GroupCard must not modify the `events` list from the provider — `events.first` is a read, which is fine. `EventTypeConfig.forType()` returns a const object.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Relative timestamps | Custom date formatting logic | `timeago` package (already imported in `activity_row.dart`) | Handles edge cases (just now, minutes, hours, days, months) correctly |
| Event icon mapping | Custom switch/map | `EventTypeConfig.forType(event.type).icon` | Single source of truth already exists in `event_type_config.dart` |
| Deterministic color assignment | Complex hash distribution | `groupId.hashCode.abs() % 5` | Simple, stable, already used in `ActivityRow` for avatar colors |

---

## Common Pitfalls

### Pitfall 1: Accent Strip Corner Bleed
**What goes wrong:** The 4dp strip appears as a rectangle that ignores the card's rounded corners — the top-left and bottom-left strip corners are sharp squares that stick out past the card boundary.
**Why it happens:** `Container` with `borderRadius` clips its own background paint but not child widgets. A `Container(width: 4)` child inside the card ignores the parent's `borderRadius`.
**How to avoid:** Add `clipBehavior: Clip.hardEdge` to the outer `Container` (the card shell). This forces all children to be clipped to the container's decoration shape.
**Warning signs:** Visible sharp corners on the left edge of cards in the simulator.

### Pitfall 2: Missing SizedBox Height Increase in WeeklySpendingCard
**What goes wrong:** Amount labels are clipped or invisible — they render above the allocated `SizedBox(height: 80)` and get cut off.
**Why it happens:** The label row adds ~13dp (9sp text + 4dp gap) above each bar. The original 80dp container has no headroom for this.
**How to avoid:** Change `SizedBox(height: 80)` to `SizedBox(height: 96)` per UI-SPEC.
**Warning signs:** Bar labels invisible in the simulator even though the widget builds without errors.

### Pitfall 3: groupEventsProvider Import
**What goes wrong:** `groupEventsProvider` is defined in `lib/features/events/providers/event_provider.dart`, NOT in `group_provider.dart`. GroupCard currently does not import `event_provider.dart`.
**Why it happens:** The provider lives with events, not groups — intuitive location mismatch when modifying a groups widget.
**How to avoid:** Add `import '../../../features/events/providers/event_provider.dart'` (or correct relative path) to `group_card.dart`.
**Warning signs:** "Undefined name 'groupEventsProvider'" compile error.

### Pitfall 4: `timeago` Import in GroupCard
**What goes wrong:** `timeago.format()` is called but the package is not imported in `group_card.dart`.
**Why it happens:** `timeago` is used in `activity_row.dart` but group_card.dart doesn't currently use it.
**How to avoid:** Add `import 'package:timeago/timeago.dart' as timeago;` to `group_card.dart`.
**Warning signs:** "Undefined name 'timeago'" compile error.

### Pitfall 5: Left Padding Removal on Card Container
**What goes wrong:** The accent strip is indented 16dp from the left card edge because the outer `Container` still has `padding: EdgeInsets.all(16)`.
**Why it happens:** The existing card uses a single `Container` with uniform padding. When the strip is added as a `Row` child, it inherits the parent padding.
**How to avoid:** Remove the `padding` from the outer `Container`. Move `padding: EdgeInsets.all(16)` to a `Padding` widget wrapping the `Expanded` content column.
**Warning signs:** Strip appears inset rather than flush with the card's left edge.

### Pitfall 6: Section Spacing Regression in Home Screen
**What goes wrong:** After reducing spacing, the `SliverToBoxAdapter` with `SizedBox(height: 16)` between BalanceHeroCard and QuickActionTray needs to be reduced to 12dp. Missing this leaves one section with the old spacing while others are tightened.
**Why it happens:** Spacing in the current `home_screen.dart` is split between explicit `SizedBox` separators AND padding within section widgets (e.g., the activity section's `fromLTRB(16, 24, ...)` top padding).
**How to avoid:** Audit all spacing points:
  - Line ~135: `SizedBox(height: 16)` before BalanceHeroCard → reduce to 12
  - QuickActionTray → group cards: use `SliverPadding` top padding of 12
  - Activity section padding top: `24` → `12`
**Warning signs:** Visually uneven rhythm — some gaps still feel large after the change.

---

## Code Examples

### GroupCard — Full Restructured Build Method Skeleton
```dart
// Source: analysis of existing group_card.dart + UI-SPEC.md
@override
Widget build(BuildContext context, WidgetRef ref) {
  final balancesAsync = ref.watch(groupBalancesProvider(group.id));
  final eventsAsync = ref.watch(groupEventsProvider(group.id));
  final uid = ref.watch(currentUserIdProvider);
  final accentColor = _accentColor(group.id);

  return GestureDetector(
    onTap: onTap,
    child: Container(
      clipBehavior: Clip.hardEdge,   // KEY: clips strip to card border radius
      decoration: BoxDecoration(
        color: AppColorTokens.light.cardSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadowTokens.standard.raised,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 4, color: accentColor),  // accent strip
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row: group name + member count badge (unchanged)
                  // SizedBox(8) (unchanged)
                  // Balance text from balancesAsync.when(...) (unchanged)
                  const SizedBox(height: 4),
                  // Context line from eventsAsync.when(...)
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
```

### WeeklySpendingCard — Bar Column with Label
```dart
// Source: analysis of existing weekly_spending_card.dart + UI-SPEC.md
// Outer SizedBox changes: height: 80 → height: 96
SizedBox(
  height: 96,
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: weekData.map((entry) {
      final fraction = maxAmount > Decimal.zero
          ? (entry.amount / maxAmount).toDouble()
          : 0.0;
      final barHeight = 60 * fraction;
      final dayLabel = DateFormat.E().format(entry.date).substring(0, 3);
      final showLabel = entry.amount > Decimal.zero;

      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (showLabel)
              Text(
                entry.amount.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280), // textSecondary
                ),
              ),
            if (showLabel) const SizedBox(height: 4),
            Container(
              height: barHeight > 0 ? barHeight : 2,
              decoration: BoxDecoration(
                color: barHeight > 0
                    ? AppColorTokens.light.primary
                    : AppColorTokens.light.inputFill,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(dayLabel, style: TextStyle(fontSize: 10, color: AppColorTokens.light.textMuted)),
          ],
        ),
      );
    }).toList(),
  ),
)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Custom `AnimatedSwitcher` for card transitions | `OpenContainer` from `animations` package | Phase 18/19 | No impact — accent strip rides inside `closedBuilder`, animates with card on open |
| Padding on outer Container | Padding on inner content, strip outside | This phase | Required to flush-align the accent strip |

---

## Open Questions

1. **`timeago` locale initialization**
   - What we know: `timeago.format()` works with English by default. The app does not currently configure a locale.
   - What's unclear: Whether the Omani locale matters here or English relative timestamps are acceptable.
   - Recommendation: Use English (default) — the pattern is identical to `activity_row.dart`, which also uses default timeago without locale setup.

2. **Provider import path for groupEventsProvider in GroupCard**
   - What we know: `groupEventsProvider` is in `lib/features/events/providers/event_provider.dart`. GroupCard is at `lib/features/groups/widgets/group_card.dart`.
   - What's unclear: Relative path depth — `../../../features/events/...` vs `../../events/...`.
   - Recommendation: The relative path from `lib/features/groups/widgets/` to `lib/features/events/providers/` is `../../events/providers/event_provider.dart`. Verify with `flutter analyze` immediately after adding the import.

---

## Environment Availability

Step 2.6: SKIPPED — this phase is purely widget code changes with no external tooling, services, or CLI dependencies beyond the existing Flutter SDK.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (Flutter SDK built-in) |
| Config file | none — standard `flutter test` discovery |
| Quick run command | `flutter test test/features/home/ test/features/groups/` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CARD-01 | GroupCard renders 4dp accent strip with color from hash | widget | `flutter test test/features/home/home_screen_dashboard_test.dart` | Yes — extend existing |
| CARD-01 | Different groupIds produce different accent colors | unit | `flutter test test/features/home/widgets_test.dart` | Yes — extend existing |
| CARD-02 | GroupCard shows last event name + relative date | widget | `flutter test test/features/home/home_screen_dashboard_test.dart` | Yes — extend existing |
| CARD-02 | GroupCard shows "No events yet" when events list is empty | widget | `flutter test test/features/home/home_screen_dashboard_test.dart` | Yes — extend existing |
| CHRT-01 | WeeklySpendingCard renders amount labels on non-zero bars | widget | `flutter test test/features/home/widgets_test.dart` | Yes — extend existing |
| CHRT-01 | Zero bars show no label | widget | `flutter test test/features/home/widgets_test.dart` | Yes — extend existing |
| CHRT-02 | WeeklySpendingCard title is "Weekly Spending (OMR)" | widget | `flutter test test/features/home/widgets_test.dart` | Yes — extend existing |
| LAYT-01 | Dashboard inter-section spacing is 12dp or less | widget/golden | `flutter test test/features/home/home_screen_dashboard_test.dart` | Yes — extend existing |
| LAYT-02 | "Your Groups (N)" header renders above card list | widget | `flutter test test/features/home/home_screen_dashboard_test.dart` | Yes — extend existing |

### Sampling Rate
- **Per task commit:** `flutter test test/features/home/ test/features/groups/`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

Existing test files cover all phase requirements and only need new test cases added, not new files created.

Test cases to add (tests do not exist yet, files do):

- [ ] `test/features/home/home_screen_dashboard_test.dart` — group card accent strip renders; group card shows event context line; "Your Groups (N)" header present
- [ ] `test/features/home/widgets_test.dart` — WeeklySpendingCard title is "Weekly Spending (OMR)"; amount labels appear on non-zero bars; no label on zero bars
- [ ] `test/features/home/home_screen_groups_test.dart` — GroupCard with events shows context line; GroupCard with no events shows "No events yet"

Provider overrides required in new GroupCard tests:
- `groupEventsProvider.overrideWith((ref, groupId) => Stream.value([/* mock events */]))` — needed wherever GroupCard is rendered in tests (adds to existing `groupBalancesProvider` and `currentUserIdProvider` overrides)

---

## Project Constraints (from CLAUDE.md)

All directives relevant to this phase:

| Directive | Impact on Phase 24 |
|-----------|-------------------|
| Immutability: always create new objects, never mutate | `events.first` is a read. `EventTypeConfig.forType()` returns const. No mutations needed. |
| No hardcoded Color(0xFF...) literals in theme token files | Slot 4 `#7C6E5A` goes in `group_card.dart` (widget file), NOT in `color_tokens.dart`. CI blocks literals in theme files only. |
| All colors via AppColorTokens | Slots 0-3 use named AppColorTokens fields (primary, focusBorderWarm, success, warning). Slot 4 is an inline const because no warm-umber token exists — document this explicitly. |
| TDD mandatory: write test first | Each test case in Wave 0 Gaps must be written before the implementation that makes it pass. |
| 80%+ test coverage | New widget code in all three files must have corresponding tests. |
| Functions < 50 lines, files < 800 lines | `group_card.dart` (131 lines) will grow ~30-40 lines — stays well under 800. `weekly_spending_card.dart` (137 lines) grows ~10 lines. `home_screen.dart` (483 lines) grows ~15 lines. |
| No deep nesting (>4 levels) | The accent strip `Row → Container → Expanded → Padding → Column` is 5 levels but all are single-child containers, not decision branches. Acceptable. |
| Use `flutter analyze` | Run after each file change. |

---

## Sources

### Primary (HIGH confidence)
- Codebase scan: `lib/features/groups/widgets/group_card.dart` — current widget structure, padding, providers in use
- Codebase scan: `lib/features/home/widgets/weekly_spending_card.dart` — chart structure, SizedBox height, title string
- Codebase scan: `lib/features/home/screens/home_screen.dart` — sliver structure, spacing values, QuickActionTray → groups layout
- Codebase scan: `lib/core/theme/tokens/color_tokens.dart` — all AppColorTokens.light hex values
- Codebase scan: `lib/features/events/models/event_type_config.dart` — EventTypeConfig.forType(), all icon and color values
- Codebase scan: `lib/features/home/widgets/activity_row.dart` — hash-color pattern reference implementation
- Codebase scan: `lib/features/events/providers/event_provider.dart` — groupEventsProvider API and sort order
- `.planning/phases/24-visual-density-polish/24-CONTEXT.md` — all locked decisions D-01 through D-14
- `.planning/phases/24-visual-density-polish/24-UI-SPEC.md` — visual contract, exact widget structures, color slots, typography

### Secondary (MEDIUM confidence)
- Codebase scan: `test/features/home/home_screen_dashboard_test.dart` — existing override patterns for groupEventsProvider tests
- Flutter documentation (Container.clipBehavior): ClipRRect / clipBehavior: Clip.hardEdge behavior for rounded corners with child overflow

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages already installed and in use in the project
- Architecture patterns: HIGH — derived from existing code (activity_row.dart, group_card.dart) and approved UI-SPEC
- Pitfalls: HIGH — all identified from direct code analysis of the three target files

**Research date:** 2026-04-01
**Valid until:** 2026-05-01 (stable Flutter/Riverpod — low churn domain)
