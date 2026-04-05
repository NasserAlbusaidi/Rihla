# Phase 32: Event Creation - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Visual refresh of EventTypePickerScreen (184 lines) and CreateEventScreen (605 lines) to earthy design language. Both screens already work — type selection, form fields, participant selection, Firestore persistence, and template-driven module defaults are all functional. This phase updates styling to v2.x tokens, refreshes layout to card-section pattern, and ensures type-specific colors use AppColorTokens.

</domain>

<decisions>
## Implementation Decisions

### Type Picker Screen
- Keep vertical card list layout with earthy token refresh
- Refresh card visuals: colored icon badge with type-specific accent, module chips below description, AppColorTokens
- Dark ModuleHeader ("New Event" + group name subtitle) — consistent with hub screens
- Staggered fade+slide entry animation per card (80ms delay, 400ms duration)

### Create Event Form
- Card sections layout (ProfileScreen pattern from Phase 29) — event info card + participants card + modules card (custom only)
- Keep inline date fields with tap-to-pick showDatePicker
- Keep checkbox list with "Select All" for participant selection, pre-checks all members
- Fixed bottom "Create Event" button (52dp, primary teal)

### Template & Polish
- Keep existing template pre-fill behavior — EventModules.forType() sets defaults, camping seeds gear, name field empty
- Navigate to event hub immediately with brief SnackBar "Event created"
- Refresh EventTypeConfig colors to use AppColorTokens (primary for Trip, successText for Camping, etc.)
- SnackBar for validation errors + inline field validation (existing pattern)

### Claude's Discretion
- Exact spacing and padding within earthy token system
- Animation timing details
- Card border radius and shadow values
- Loading state during event creation submission

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `EventTypePickerScreen` (lib/features/events/screens/event_type_picker_screen.dart, 184 lines) — type card list
- `CreateEventScreen` (lib/features/events/screens/create_event_screen.dart, 605 lines) — event form
- `EventTypeConfig` (lib/features/events/models/event_type_config.dart, 82 lines) — type metadata (labels, icons, colors)
- `EventModules.forType()` — default module sets per event type
- `EventService.createEvent()` — Firestore write + camping gear seeding
- `ModuleHeader` (lib/shared/widgets/module_header.dart) — dark/light gradient header
- GroupSettingsScreen card-section pattern from Phase 29

### Established Patterns
- Dark ModuleHeader for hub/entry screens
- Card-section layout with stagger animations (Phase 29 GroupSettingsScreen)
- AppColorTokens for all colors
- FadeInList + flutter_animate for entrance effects
- Fixed-bottom button pattern (52dp height, primary teal)

### Integration Points
- Route: /group/:gid/create-event (EventTypePickerScreen)
- Route: /group/:gid/create-event/:type (CreateEventScreen)
- On submit: context.go('/group/$groupId/event/$eventId') → EventCommandCenter
- EventService.createEvent() for Firestore persistence
- GroupDetailScreen FAB → create-event route

</code_context>

<specifics>
## Specific Ideas

- EventTypeConfig.color values should map to AppColorTokens equivalents instead of hardcoded hex
- Module chips on type cards should use muted token colors for consistency
- Participant checkbox list should use token colors for selected/unselected states

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>
