import 'package:flutter/material.dart';

abstract final class LedgerKeys {
  // Screen keys
  static const screen = Key('ledger_screen');
  static const addExpenseScreen = Key('ledger_add_expense_screen');
  static const editExpenseSheet = Key('ledger_edit_expense_sheet');
  static const settleUpScreen = Key('ledger_settle_up_screen');

  // Parameterized keys for list items
  static Key expenseCard(String id) => Key('ledger_expense_card_$id');
}
