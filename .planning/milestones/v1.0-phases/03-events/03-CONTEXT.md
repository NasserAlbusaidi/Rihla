# Phase 3: Events - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can create typed events inside groups. Event type controls module visibility and pre-fills content. Group members are selectable as event participants. The group detail screen shows an event timeline with past/upcoming events. A Supabase trip bridge enables existing module screens to work within events until Phase 4 migrates everything to Firestore. Pull-to-refresh on the home screen is fixed (carried from Phase 2 gap #8).

</domain>

<decisions>
## Implementation Decisions

### Event Creation Flow
- **D-01:** FAB on GroupDetailScreen is the entry point for creating events. Tap opens the event creation flow directly.
- **D-02:** Two-step flow: Step 1 is a full-screen type picker with visual cards (icon, name, description, enabled modules as chips). Step 2 is the creation form pre-filled based on selected type.
- **D-03:** Creation form fields: event name (required), optional start/end dates, participant picker. Currency inherited from group — no currency field on the form.
- **D-04:** Participant picker: checkbox list of all group members, all pre-checked by default. Creator deselects anyone who isn't joining. Creator is not locked — they can exclude themselves if needed (edge case).
- **D-05:** After creation, navigate directly to the event hub (adapted CommandCenter). No intermediate share screen.
- **D-06:** No event invite codes. Events are group-internal. Only group members participate.
- **D-07:** Any group member can create an event. No creator-only restriction.
- **D-08:** Name and dates are editable after creation. Event type is locked once created (changing type would invalidate modules and presets).
- **D-09:** Event creator can delete the event with a confirmation dialog. Soft delete (is_deleted flag) to preserve financial records.
- **D-10:** Event creator can add/remove participants after creation, picking only from existing group members.

### Event Types & Templates
- **D-11:** Five event types ship in Phase 3: Trip, Camping, Travel, Night/Day Out, Custom. All from requirements EVT-02.
- **D-12:** Module configuration per type (rich templates):
  - **Trip:** Ledger + Gear + Logistics + Vault + Memories (all modules)
  - **Camping:** Ledger + Gear + Logistics + Memories
  - **Travel:** Ledger + Logistics + Vault + Memories
  - **Night/Day Out:** Ledger only
  - **Custom:** User toggles modules on the creation form. Ledger on by default, rest off.
- **D-13:** Only Camping type gets preset content: tent, sleeping bag, cooler auto-added to gear list on creation. Other types start with empty module content.
- **D-14:** Ledger is always enabled for every event type. Even Custom events have it on by default (user can toggle off only for Custom).
- **D-15:** Each event type has a distinct icon used in the type picker and on event cards: Trip (airplane), Camping (tent/tree), Travel (car/suitcase), Night/Day Out (moon/sun), Custom (puzzle piece). Icons from Iconsax.
- **D-16:** Type picker shows visual cards with icon, type name, short description, and enabled modules as chips. Grid or vertical card layout.

### Event Hub Experience
- **D-17:** Adapt the existing CommandCenter for events. Refactor to accept event data instead of trip data. Module cards show/hide based on event type's module config. Reuses all existing module screens.
- **D-18:** Event hub header shows event name (large) with event type as a small badge/chip (icon + type name). Group name as subtitle. Uses existing ModuleHeader.
- **D-19:** Expense summary hero is shown in the event hub (total spent, your balance). Reads from the event's ledger data via the Supabase bridge.
- **D-20:** Navigation: tap event card in group detail timeline pushes the adapted CommandCenter via Navigator.push. Standard back arrow + system back gesture for return.
- **D-21:** Existing module screens (ledger, gear, logistics, vault, memories) reused as-is. They receive event ID (which maps to a Supabase trip ID via the bridge).
- **D-22:** **Supabase bridge:** When a Firestore event is created, also create a matching Supabase trip record with the same ID. Module screens use the trip ID to read/write via existing Supabase providers. This bridge remains until Phase 4 migrates all module data to Firestore.

### Event Timeline in Group
- **D-23:** Events section in GroupDetailScreen shows a vertical list of event cards. Replaces the current EmptyStateView placeholder.
- **D-24:** Event card content: type icon, event name, date range (or "No dates"), participant count, total spent (shows "0.000 OMR" until financials exist).
- **D-25:** Sorted by date descending (newest first). Events without dates sorted to the top.
- **D-26:** Past events (end date before today) have subtle dimming (reduced opacity). Still tappable and functional.
- **D-27:** Section header shows count chip: "Events (3)". Empty state: calendar icon + "No events yet" + CTA text pointing to the FAB. Reuses EmptyStateView.
- **D-28:** Tap on event card navigates to the event hub (adapted CommandCenter) via Navigator.push.

### Firestore Data Model
- **D-29:** Events stored as subcollection: `groups/{groupId}/events/{eventId}`. Security rules inherit group membership check.
- **D-30:** Event participants stored as array field on event document: `participantIds: [uid1, uid2, ...]`. Same pattern as group memberIds.
- **D-31:** Participant display names stored as map field on event document: `participantNames: {uid1: "Nasser", uid2: "Ahmed"}`. Denormalized for fast rendering.
- **D-32:** Security rules: any group member can read all events in the group (transparency over privacy). Only event participants can write to event data.
- **D-33:** Event document fields: id, name, type, groupId, createdBy, participantIds, participantNames, modules (map), startDate, endDate, currency, isDeleted, deletedAt, createdAt, updatedAt, bridgeTripId (Supabase trip ID for the bridge).

### Event Status/Lifecycle
- **D-34:** No explicit status field. State derived from dates: upcoming (start date in future), active (today between start/end), past (end date in past). Same logic as existing Trip model (isOngoing, isPast).
- **D-35:** Events without dates are treated as ongoing/active — never dimmed in timeline, sorted to the top.

### Pull-to-Refresh Fix (Phase 2 Gap #8)
- **D-36:** Pull-to-refresh on home screen invalidates the Firestore stream provider (ref.invalidate on userGroupsProvider), forcing re-fetch from Firestore server.

### Offline Behavior
- **D-37:** Event data uses Firestore offline persistence only. No SQLite caching for events in Phase 3. Same approach that worked for groups in Phase 2.
- **D-38:** Users can create events while offline. Firestore queues the write and syncs when back online. Optimistic UI — user sees the event immediately.

### Claude's Discretion
- Event card visual design and spacing in the timeline
- Type picker card layout (grid vs vertical list) and visual treatment
- Creation form layout and validation UX
- Module toggle design for Custom events
- Bridge trip creation implementation details (timing, field mapping)
- Firestore security rule implementation for events subcollection
- Camping preset gear item details (names, categories, priorities)
- Error handling for failed event creation or bridge sync

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Event types and modules
- `.planning/REQUIREMENTS.md` lines 29-36 — EVT-01 through EVT-08 acceptance criteria
- `.planning/ROADMAP.md` Phase 3 section — success criteria and requirement mapping

### Existing trip/event models
- `lib/features/trip/models/trip_model.dart` — Trip model with TripModules (module visibility pattern to mirror for events), Participant model, date-derived status (isOngoing, isPast)
- `lib/features/home/screens/command_center.dart` — CommandCenter to adapt for events (module cards, expense hero, FAB, seed provider pattern)

### Group model and screens
- `lib/features/groups/models/group_model.dart` — Group model with Firestore + SQLite serialization, memberIds array pattern
- `lib/features/groups/screens/group_detail_screen.dart` — GroupDetailScreen with events section placeholder (_buildEventsSection) to replace
- `lib/features/groups/providers/group_provider.dart` — Provider patterns (StreamProvider.family) to mirror for events

### Firestore security and data
- `security/firestore.rules` — Existing Firestore security rules for groups (extend for events subcollection)
- `.planning/phases/01-data-foundation/1-CONTEXT.md` — Phase 1 money serialization decisions (D-01 to D-04), memberIds security pattern (D-14)
- `.planning/research/PITFALLS.md` — WriteBatch ordering issue (resolved in Phase 2), security rule get() limit

### UI patterns and shared widgets
- `lib/shared/widgets/` — EmptyStateView, ModuleHeader, SmartModuleCard, LoadingButton, OfflineBanner
- `lib/core/theme/app_theme.dart` — Design tokens for spacing, radii, shadows
- `lib/core/utils/page_transitions.dart` — AppPageRoute for Navigator.push transitions

### Phase 2 context (carried decisions)
- `.planning/phases/02-groups/2-CONTEXT.md` — Group creation/join patterns, FAB pattern, self-naming from device settings
- `.planning/phases/02-groups/02-HUMAN-UAT.md` — Gap #8 (pull-to-refresh) carried to Phase 3

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CommandCenter` — per-trip hub with module cards, expense summary hero, FAB. Adapt for events by passing event data instead of trip data
- `TripModules` class — module visibility booleans (docs, gear, itinerary, logistics). Extend or create EventModules with memories field added
- `GroupDetailScreen._buildEventsSection()` — placeholder ready for event list replacement
- `SmartModuleCard` — module cards used in CommandCenter, reuse in event hub
- `EmptyStateView` — consistent empty states with optional CTA
- `CreateGroupScreen` pattern — ConsumerStatefulWidget form with loading/error providers. Mirror for CreateEventScreen
- Invite code generation in GroupService — reuse ID generation pattern for event IDs
- `Group.fromDoc()` / `Group.toMap()` — Firestore + SQLite serialization pattern to mirror for Event model

### Established Patterns
- `StreamProvider.family` for reactive Firestore data (groupDetailProvider, groupMembersProvider) — use same for events
- Feature-first directory structure: `lib/features/events/{models,providers,screens,services,widgets}/`
- Navigator.push for sub-screens (not GoRouter) inside group/event detail
- `AppPageRoute` for slide transitions between screens
- `ConsumerStatefulWidget` for forms with `StateProvider` for loading/error state
- Firestore security via parent document memberIds array

### Integration Points
- `GroupDetailScreen` — replace events placeholder with real event list, add FAB
- `CommandCenter` — refactor to accept event data (Event model instead of Trip)
- Firestore: `groups/{groupId}/events` subcollection with security rules
- Supabase bridge: event creation also writes a trip record for module compatibility
- `lib/features/groups/providers/group_provider.dart` — add event providers alongside group providers (or create separate event provider file)

</code_context>

<specifics>
## Specific Ideas

- The Supabase bridge (D-22) is the key pragmatic decision — it lets events feel fully functional immediately without waiting for Phase 4's Firestore migration. Bridge trip records should have a `source: 'event_bridge'` marker so Phase 4 knows which trips to migrate.
- Type picker should feel like a deliberate moment — visual cards with descriptions help users understand what each type provides, not just pick a label.
- Participant picker with all-pre-checked and deselect pattern optimizes for the common case (most people join most events) while giving the creator control.
- Date-derived lifecycle keeps things simple and mirrors the existing Trip model exactly. No status management overhead.

</specifics>

<deferred>
## Deferred Ideas

- Event archive/complete action — manually marking an event as done regardless of dates. Future phase.
- Event notifications — push notifications when an event is created or modified. ENH-04 in requirements.
- Budget tracking per event — budget field on creation form with spending tracking. Nice-to-have for future.
- Event description/notes field — optional context field. Could add later without breaking changes.
- Non-group-member event participants — invite codes for events. Would require rethinking security model.
- Event duplication — "create another like this" for recurring group activities.
- Group-level event search/filter — searching events by type, date range, or keyword. Future phase.

</deferred>

---

*Phase: 03-events*
*Context gathered: 2026-03-26*
