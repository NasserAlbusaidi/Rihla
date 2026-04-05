# Phase 33: Ledger - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Visual refresh of the ledger module (4 screens, 17 widgets, ~4000 lines) to earthy design language. All screens are fully built and production-ready — LedgerScreen (401 lines), AddExpenseScreen (667 lines), EditExpenseScreen (786 lines), SettleUpScreen (554 lines). This phase updates styling to v2.x AppColorTokens, adds dark ModuleHeaders, and refreshes key widgets (LedgerHeroCard, ExpenseCard, MemberBalancesSection, SettlementSummaryCard).

</domain>

<decisions>
## Implementation Decisions

### Ledger Screen & Expense List
- Dark ModuleHeader ("Ledger" + event name subtitle)
- Refresh ExpenseCard with earthy color tokens — keep existing card-style rows
- Refresh LedgerHeroCard with earthy tokens — keep YOUR BALANCE + EVENT TOTAL hero layout
- Keep EmptyStateView with "No expenses yet" + "Add Expense" CTA

### Add/Edit Expense Forms
- Keep existing 3-step flow (category -> amount -> split) with earthy token refresh
- Dark ModuleHeader ("Add Expense" / "Edit Expense")
- Refresh AmountInputSection styling with tokens — keep existing OMR input behavior
- Refresh SplitScopeSelector styling — keep global/subgroup/custom functionality

### Settle Up Screen
- Refresh with earthy tokens — keep existing optimization display (SettlementSummaryCard + SettlementRow)
- Dark ModuleHeader ("Settle Up" + event name subtitle)
- Keep existing settle button with earthy primary color
- Refresh MemberBalancesSection with earthy tokens — keep grid layout

### Claude's Discretion
- Exact spacing and padding within earthy token system
- Animation timing for any entrance effects
- Loading/error state presentation details
- Widget-level token mapping decisions

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `LedgerScreen` (lib/features/ledger/screens/ledger_screen.dart, 401 lines)
- `AddExpenseScreen` (lib/features/ledger/screens/add_expense_screen.dart, 667 lines)
- `EditExpenseScreen` (lib/features/ledger/screens/edit_expense_screen.dart, 786 lines)
- `SettleUpScreen` (lib/features/ledger/screens/settle_up_screen.dart, 554 lines)
- `LedgerHeroCard` — summary card with balance + event total
- `ExpenseCard` — individual expense display
- `SettlementSummaryCard` — settlement optimization display
- `MemberBalancesSection` — balance grid
- `AmountInputSection` — numeric entry
- `SplitScopeSelector` — scope picker (16k lines, largest widget)
- `ModuleHeader` (lib/shared/widgets/module_header.dart) — dark/light gradient header

### Established Patterns
- Dark ModuleHeader for all module screens (Phase 28-32 pattern)
- AppColorTokens for all colors, AppSpacingTokens for spacing
- Firestore streams with SQLite side-write pipeline
- Decimal package for all money math (OMR, 3 decimal places)
- Soft deletes (is_deleted + deleted_at flags)

### Integration Points
- Route: /group/:gid/event/:eid/ledger (LedgerScreen)
- Route: /group/:gid/event/:eid/ledger/add (AddExpenseScreen)
- Route: /group/:gid/event/:eid/ledger/edit/:expId (EditExpenseScreen)
- Route: /group/:gid/event/:eid/ledger/settle-up (SettleUpScreen)
- Providers: eventExpensesProvider, eventSettlementsProvider, eventUnifiedLedgerProvider
- Services: ExpenseService, SettlementService

</code_context>

<specifics>
## Specific Ideas

- LedgerHeroCard balance amounts should use AnimatedCurrencyText for animated counter transitions
- ExpenseCard should use token colors for category indicators and amount display
- SettlementSummaryCard arrows/flow visualization should use primary teal accent

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>
