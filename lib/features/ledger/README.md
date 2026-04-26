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
- **expense_service.dart**: Firestore CRUD at `groups/{gid}/events/{eid}/expenses`. Decimal <> fils serialization, soft deletes
- **settlement_service.dart**: Settlement recording
- **receipt_service.dart**: Receipt image upload
- **ocr_service.dart**: Receipt OCR extraction

### screens/
- **add_expense_screen.dart**, **edit_expense_screen.dart**, **ledger_screen.dart**, **settle_up_screen.dart**

### widgets/
- **expense_card.dart**, **amount_input_section.dart**, **category_selection_step.dart**, **receipt_picker_section.dart**, **member_balances_section.dart**, **recent_expenses_section.dart**, **recorded_settlements_section.dart**, **settlement_row.dart**, **settlement_tile.dart**, **settlement_summary_card.dart**, **spending_summary_section.dart**, **split_scope_selector.dart**, **transaction_list.dart**, **ledger_hero_card.dart**, **expense_success_dialog.dart**
