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

  // Search sheet (T3.L)
  static const searchField = Key('ledger_search_field');

  // Parameterized keys for list items
  static Key expenseCard(String id) => Key('ledger_expense_card_$id');
}
