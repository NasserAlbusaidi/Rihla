# Phase 24: Visual Density & Polish - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Improve the home dashboard to feel information-dense, visually differentiated, and clearly structured. Enrich group cards with contextual data, make the weekly chart readable, add visual distinction between groups, and tighten dashboard spacing. No new features or navigation changes — purely visual and content improvements to existing screens.

</domain>

<decisions>
## Implementation Decisions

### Group Card Enrichment
- **D-01:** Add a "last event" context line below the balance showing event name + relative date (e.g., "Camping Trip — 2 days ago"). Data from `groupEventsProvider` (already exists).
- **D-02:** Include a small event type icon (16px) before the event name (tent for camping, plane for travel, etc.). Icons already exist in event type templates.
- **D-03:** Groups with zero events show "No events yet" in muted text as the context line.
- **D-04:** Keep member count badge as-is (icon + number). No avatar circles.
- **D-05:** Keep exact balance amounts ("You owe OMR 12.500"). No simplification.

### Card Visual Distinction
- **D-06:** 4px vertical color accent strip on the left edge of each group card.
- **D-07:** Accent color assigned via hash of group ID, cycling through 5-6 earthy palette colors (teal, terracotta, olive, sand, etc. from AppColorTokens).
- **D-08:** Color accent is strip only — rest of card stays neutral card surface. No background tint, no tinting other elements.

### Chart Improvements
- **D-09:** Add amount label at the end/top of each bar showing the day's spending (e.g., "12.5"). Non-zero bars only.
- **D-10:** Zero-spending days keep the 2px gray placeholder bar with no label.
- **D-11:** Chart title changes from "This Week" to "Weekly Spending (OMR)".

### Dashboard Density & Rhythm
- **D-12:** Tighten inter-section spacing from current 16-24px to a consistent 12px between major sections.
- **D-13:** Add "Your Groups (N)" section header above the group card list, where N is the group count.
- **D-14:** Keep current section order: Balance Hero → Quick Actions → Groups → Activity → Chart.

### Claude's Discretion
- Exact earthy color palette for accent strips (pick 5-6 from existing AppColorTokens)
- Amount label formatting on chart bars (decimal places, font size)
- "Your Groups" header typography and styling
- Group card internal spacing adjustments to accommodate the new context line
- Event type icon selection and mapping logic

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Group Card
- `lib/features/groups/widgets/group_card.dart` — Current GroupCard widget (name + member count + balance). Main modification target.
- `lib/features/groups/models/group_model.dart` — Group model fields (no lastEvent field — computed from providers)
- `lib/features/groups/providers/group_provider.dart` — `userGroupsProvider`, `groupEventsProvider` for event data

### Chart
- `lib/features/home/widgets/weekly_spending_card.dart` — Custom proportional bar chart. Title, bar rendering, and layout all here.

### Dashboard Layout
- `lib/features/home/screens/home_screen.dart` — Full dashboard structure, section ordering, spacing values, sliver layout

### Data Providers
- `lib/features/home/providers/dashboard_providers.dart` — `crossGroupActivityProvider`, `weeklyGroupSpendingProvider`, `DailySpending` model

### Design Tokens
- `lib/core/theme/tokens/color_tokens.dart` — AppColorTokens with earthy palette (source for accent strip colors)
- `lib/core/theme/tokens/spacing_tokens.dart` — AppSpacingTokens for consistent spacing values
- `lib/core/theme/app_theme.dart` — Spacing constants, border radii, elevation shadows

### Event Types
- `lib/features/trip/models/event_type.dart` — Event type enum with associated icons (or check event type template files for icon mapping)

### Requirements
- `.planning/REQUIREMENTS.md` — CARD-01, CARD-02, CHRT-01, CHRT-02, LAYT-01, LAYT-02

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `GroupCard` widget: Current card structure can be extended with one more Row for the event context line
- `groupEventsProvider(groupId)`: Already provides events per group — sort by date, take latest
- Event type icons: Already mapped in event type models/templates — reuse for the context line icon
- `AppColorTokens.light`: Earthy palette already defined — pick 5-6 for accent strip rotation
- `ActivityRow` widget: Uses hash-based color for avatar circles — same pattern for group accent colors

### Established Patterns
- Cards use `AppColorTokens.light.cardSurface` background with `AppSpacingTokens.standard` padding
- Text styles: `titleMedium` for names, `bodySmall` for secondary info, muted color for tertiary text
- Shadows: `shadowRaised` for cards
- All screens use token-based colors only (CI blocks hardcoded Color(0xFF...) values)

### Integration Points
- `group_card.dart` — add accent strip + event context line
- `weekly_spending_card.dart` — add bar labels + change title
- `home_screen.dart` — adjust section spacing + add group list header
- No new screens or routes needed

</code_context>

<specifics>
## Specific Ideas

- Accent strip mockup confirmed: 4px vertical bar on left edge of card, different earthy color per group
- Last event line format: "[type icon] Event Name — 2d ago"
- Chart bar labels show amounts like "12.5" at bar end, no label on zero bars
- "Your Groups (3)" header gives clear section delineation from quick actions above

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 24-visual-density-polish*
*Context gathered: 2026-04-01*
