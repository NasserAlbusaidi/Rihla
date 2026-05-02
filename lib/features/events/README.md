## events/ — Event Management (Hubs within Groups)

### models/
- **event_model.dart**: `Event`, `EventModules`, `EventType` enum (trip, camping, travel, nightDayOut, custom). Module visibility per type
- **event_type_config.dart**: Static UI metadata per event type (icon, color, label)

### providers/
- **event_provider.dart**: Event CRUD and stream providers

### services/
- **event_service.dart**: Firestore event operations

### screens/
- **create_event_screen.dart**, **event_type_picker_screen.dart**, **event_command_center.dart** (hub with module tabs), **event_settings_screen.dart**

### widgets/
- **event_card.dart**, **event_info_section.dart**, **event_danger_section.dart**, **event_module_list.dart**, **event_spending_hero.dart**, **event_expense_hero.dart**
