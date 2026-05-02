## groups/ — Group Management & Balances

### models/
- **group_model.dart**: `Group` — persistent group entity (parent of events). Firestore/SQLite serialization
- **group_member_model.dart**: `GroupMember` — member with role (CREATOR/MEMBER)
- **group_activity_log_model.dart**: Audit log for group actions

### providers/
- **group_provider.dart**: Group CRUD and list state
- **group_balance_provider.dart**: Computed group-level and cross-group balances. `crossGroupBalanceProvider`, `groupBalancesProvider`

### services/
- **group_activity_service.dart**: Group activity log operations
- **group_settlement_service.dart**: Multi-event settlement calculations

### screens/
- **create_group_screen.dart**, **group_detail_screen.dart**, **group_activity_screen.dart**, **group_settings_screen.dart**, **group_settle_up_screen.dart**, **join_group_screen.dart**

### widgets/
- **group_card.dart**, **group_balance_hero.dart**, **group_member_tile.dart**, **group_member_balance_card.dart**, **group_members_section.dart**, **group_info_section.dart**, **group_danger_section.dart**, **group_settlement_tile.dart**, **group_settlement_summary.dart**, **group_spending_stats.dart**, **group_stats_grid.dart**, **invite_code_display.dart**
