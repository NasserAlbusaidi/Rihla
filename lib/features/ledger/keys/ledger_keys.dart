import 'package:flutter/material.dart';

abstract final class LedgerKeys {
  // Screen keys
  static const screen = Key('ledger_screen');
  static const addExpenseScreen = Key('ledger_add_expense_screen');
  static const editExpenseSheet = Key('ledger_edit_expense_sheet');
  static const settleUpScreen = Key('ledger_settle_up_screen');

  // Section label keys
  static const spendingLabel = Key('ledger_spending_label');
  static const payerSectionLabel = Key('ledger_payer_section_label');

  // App-bar actions
  static const activityButton = Key('ledger_activity_button');

  // Per-expense currency picker row (#382 PR-6)
  static const expenseCurrencyField = Key('ledger_expense_currency_field');

  // Soft fat-finger warning when the picked currency differs from the event's
  // dominant currency (#382 PR-6)
  static const expenseCurrencyWarning = Key('ledger_expense_currency_warning');

  // Search sheet (T3.L)
  static const searchField = Key('ledger_search_field');

  // #818 Wave 5.3: standalone settle-up → recap/export nav entry
  static const settleUpRecapCta = Key('settle_up_recap_cta');

  // #900 (PR-5 §1): editor "change destination" affordance, add mode only
  static const editorChangeDestinationButton = Key(
    'editor_change_destination_button',
  );

  // Parameterized keys for list items
  static Key expenseCard(String id) => Key('ledger_expense_card_$id');
}
