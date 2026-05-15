## ledger/ — Expense Tracking & Settlements

### models/
- **expense_model.dart**: `Expense`, `ExpenseScope` enum (global/subGroup/personal/custom). Amount as Decimal
- **settlement_model.dart**: Payment settlement record
- **transaction_model.dart**: Unified ledger line (expense + settlement)
- **expense_category_model.dart**: Categories (meals, transport, etc.)

### providers/
- **expense_provider.dart**: Expense list, CRUD, real-time streams
- **category_provider.dart**: Category list and cache
- **ledger_provider.dart**: Unified transaction ledger

### services/
- **expense_service.dart**: Firestore CRUD at `groups/{gid}/events/{eid}/expenses`. `Decimal` ↔ integer-subunit serialization via `MoneySerializer`, `isDeleted` + `deletedAt` soft delete, immutable `createdBy` ownership (B1). Supports `splitMode` + `splitDistribution` for non-equal splits.
- **settlement_service.dart**: Settlement recording at `groups/{gid}/events/{eid}/settlements` (event-scoped) or `groups/{gid}/settlements` (group-scoped). **Append-only** — corrections create new offsetting rows (B3).
- **ocr_service.dart**: Receipt OCR helper (no Firebase Storage SDK use — the Storage client surface was retired in v1.2).

### screens/
- **add_expense_screen.dart**, **edit_expense_screen.dart**, **ledger_screen.dart**, **settle_up_screen.dart**

### widgets/
- **expense_card.dart**, **amount_input_section.dart**, **category_selection_step.dart**, **member_balances_section.dart**, **recent_expenses_section.dart**, **recorded_settlements_section.dart**, **settlement_row.dart**, **settlement_tile.dart**, **settlement_summary_card.dart**, **spending_summary_section.dart**, **split_scope_selector.dart**, **custom_split_sheet.dart**, **ledger_search_sheet.dart**, **transaction_list.dart**, **ledger_hero_card.dart**, **expense_success_dialog.dart**
