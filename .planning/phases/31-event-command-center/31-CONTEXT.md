# Phase 31: Event Command Center - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Visual refresh of EventCommandCenter screen with earthy design language, plus new EventSettingsScreen. Existing screen (186 lines) already works — this phase updates styling to v2.x tokens, refreshes EventExpenseHero and SmartModuleCard components, adds date range to header, and builds event settings with edit/delete capabilities.

</domain>

<decisions>
## Implementation Decisions

### Header & Event Info
- Dark ModuleHeader (matches Phase 28 group detail hub pattern)
- Header shows: event name + type badge + date range + group name
- Refresh EventExpenseHero card with earthy color tokens (keep total expenses + member count as primary metrics)
- Settings entry point: gear icon in header action slot (mirrors GroupDetailScreen pattern)

### Module Grid & Navigation
- Keep 2-column grid layout (existing EventModuleList pattern)
- Refresh SmartModuleCard with earthy color tokens and updated summary text
- Fixed module ordering: Ledger -> Gear -> Logistics -> Vault -> Activity -> Memories
- Show all enabled modules with descriptive empty state (tap still navigates)

### Event Settings Screen
- Full screen with slide-right transition (matches GroupSettingsScreen from Phase 29)
- Editable fields: event name, dates, description (type and modules set at creation, not editable)
- Danger zone: delete event (creator-only, confirmation dialog, balance-gated like group delete)
- Layout pattern: ProfileScreen card sections with stagger animations (Phase 29 pattern)

### Claude's Discretion
- Exact spacing and padding values within earthy token system
- Animation timing for stagger effects
- Error state presentation details
- Loading skeleton specifics

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `EventCommandCenter` (lib/features/events/screens/event_command_center.dart, 186 lines) — main screen to refresh
- `EventModuleList` (lib/features/events/widgets/event_module_list.dart, 327 lines) — 2x3 grid with stagger animations
- `EventExpenseHero` (lib/features/events/widgets/event_expense_hero.dart, 274 lines) — stats hero card
- `SmartModuleCard` (lib/shared/widgets/smart_module_card.dart, 160 lines) — module grid cards
- `ModuleHeader` (lib/shared/widgets/module_header.dart, 202 lines) — dark/light gradient header
- `EventKeys` (lib/features/events/keys/event_keys.dart, 52 lines) — test key constants
- `GroupSettingsScreen` — Phase 29 pattern for settings layout (card sections, danger zone, stagger)
- `GroupDangerSection` — reusable pattern for delete with confirmation dialog

### Established Patterns
- Dark ModuleHeader for hub screens (Phase 28 group detail)
- ProfileScreen card pattern for settings screens (Phase 29)
- StreamProvider.family for parameterized data (eventDetailProvider)
- OpenContainer ContainerTransform for module card navigation
- FadeInList + flutter_animate for entrance effects
- Stagger delays: 80ms between cards, 400ms duration
- AppColorTokens for all colors, AppSpacingTokens for spacing

### Integration Points
- Route: /group/:gid/event/:eid (existing, EventCommandCenter)
- New route: /group/:gid/event/:eid/settings (EventSettingsScreen — to be created)
- Provider: eventDetailProvider((groupId, eventId)) for event data
- Provider: groupDetailProvider(groupId) for group context
- EventService for mutations (updateEvent, deleteEvent)
- Navigation: gear icon in header -> context.push settings route

</code_context>

<specifics>
## Specific Ideas

- Gear icon in header mirrors GroupDetailScreen settings icon for consistency across hub screens
- Balance-gated delete: same pattern as GroupDangerSection — warn if event has unsettled balances
- Date range display in header subtitle: "Mar 15 - Mar 20" format alongside type badge

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>
