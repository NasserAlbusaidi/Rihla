## ledger/ — Expense Tracking & Settlements

### models/
- **expense_model.dart**: `Expense`, `ExpenseScope` enum (global/subGroup/personal/custom). Amount as Decimal
- **settlement_model.dart**: Payment settlement record
- **expense_category_model.dart**: Categories (meals, transport, etc.)

### providers/
- **expense_provider.dart**: Expense list, CRUD, real-time streams
- **category_provider.dart**: Hardcoded list of built-in default categories (no backend, no cache)

### services/
- **expense_service.dart**: Firestore CRUD at `groups/{gid}/events/{eid}/expenses`. `Decimal` ↔ integer-subunit serialization via `MoneySerializer`, `isDeleted` + `deletedAt` soft delete, immutable `createdBy` ownership (B1). Supports `splitMode` + `splitDistribution` for non-equal splits.
- **settlement_service.dart**: Settlement recording at `groups/{gid}/events/{eid}/settlements` (event-scoped only). **Append-only** — corrections create new offsetting rows (B3). Group-scoped settlements (`groups/{gid}/settlements`) live in `features/groups/services/group_settlement_service.dart`, not here.

### screens/
- **add_expense_screen.dart**, **edit_expense_screen.dart**, **ledger_screen.dart**, **settle_up_screen.dart**

### widgets/
- **custom_split_sheet.dart**, **expense_editor_body.dart**, **expense_success_dialog.dart**, **ledger_category_strip.dart**, **ledger_day_card.dart**, **ledger_hero_block.dart**, **ledger_roster_strip.dart**, **ledger_search_sheet.dart**, **ledger_sticky_cta.dart**, **split_scope_selector.dart**
