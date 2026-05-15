## events/ — Event Management (within Groups)

### models/
- **event_model.dart**: `Event`, `EventModules` (carries only `ledger: true` after Phase 39 — legacy keys silently ignored), `EventType` enum (trip, camping, travel, nightDayOut, custom).
- **event_type_config.dart**: Static UI metadata per event type (icon, accent, label, default cover variant).

### providers/
- **event_provider.dart**: Event CRUD and stream providers (`eventDetailProvider`, `groupEventsProvider`).

### services/
- **event_service.dart**: Firestore event CRUD at `groups/{gid}/events/{eid}` with soft-delete (`isDeleted` + `deletedAt`).

### utils/
- **event_permissions.dart**: `EventPermissions.isEventAdmin` — light/admin split per C-Hierarchy. Event creator or group creator is admin; other participants get light access (rename, dates, add participants).

### screens/
- **create_event_screen.dart**, **event_type_picker_screen.dart**, **event_settings_screen.dart**
- **event_command_center.dart**: Module hub. Reachable in the router at `/group/:gid/event/:eid`, but the UI never navigates to it — event cards jump straight to `/event/:eid/ledger` after Phase 39 reduced events to a single visible module. Treat as dead-but-not-orphaned.

### widgets/
- **event_card.dart**, **event_info_section.dart**, **event_danger_section.dart**, **event_module_list.dart**, **event_spending_hero.dart**, **event_expense_hero.dart**, **event_details_card.dart**
