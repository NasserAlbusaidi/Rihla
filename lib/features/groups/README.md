## groups/ — Group Management & Balances

### models/
- **group_model.dart**: `Group` — persistent group entity (parent of events). Firestore serialization (`fromDoc`). (The `fromMap`/`toMap` SQLite row helpers are dead leftovers from the #50 cache removal — only exercised by tests; do not treat SQLite as a live store.)
- **group_member_model.dart**: `GroupMember` — member with role (CREATOR/MEMBER)
- **group_activity_log_model.dart**: Audit log for group actions

### providers/
- **group_provider.dart**: Group CRUD and list state
- **group_balance_provider.dart**: Computed group-level and cross-group balances. `crossGroupBalanceProvider`, `groupBalancesProvider`

### services/
- **group_activity_service.dart**: Group activity log operations
- **group_settlement_service.dart**: Multi-event settlement calculations
- **member_name_resolver.dart**: `MemberNameResolver` / `MemberDisplay` — resolves member display names (including former-member handling).

### screens/
- **create_group_screen.dart**, **group_detail_screen.dart**, **group_activity_screen.dart**, **group_settings_screen.dart**, **group_settle_up_screen.dart**, **join_group_screen.dart**

### widgets/
- **group_members_section.dart**, **group_info_section.dart**, **group_danger_section.dart**, **group_settlement_tile.dart**, **group_settlement_summary.dart**, **invite_code_display.dart**
- **all_settled_state.dart**, **delete_group_sheet.dart**, **qr_invite_sheet.dart**, **record_payment_sheet.dart**, **settings_section_header.dart**, **settle_up_page_body.dart**

### keys/
- **group_keys.dart**: Stable widget keys for the groups feature (used by widget tests).
