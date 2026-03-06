import 'package:decimal/decimal.dart';

import 'expense_model.dart';
import 'settlement_model.dart';

enum TransactionType { expense, settlement }

class Transaction {
  final String id;
  final TransactionType type;
  final DateTime date;
  final Decimal amount;
  final String description; // "Lunch", "Grocery", or "Payment to Bob"
  final String payerId;
  
  // Specific fields
  final Expense? expense;
  final Settlement? settlement;

  const Transaction({
    required this.id,
    required this.type,
    required this.date,
    required this.amount,
    required this.description,
    required this.payerId,
    this.expense,
    this.settlement,
  });

  factory Transaction.fromExpense(Expense expense) {
    return Transaction(
      id: expense.id,
      type: TransactionType.expense,
      date: expense.createdAt,
      amount: expense.amount,
      description: expense.description ?? 'Expense',
      payerId: expense.payerParticipantId,
      expense: expense,
    );
  }

  factory Transaction.fromSettlement(Settlement settlement) {
    return Transaction(
      id: settlement.id,
      type: TransactionType.settlement,
      date: settlement.settledAt,
      amount: Decimal.parse(settlement.amount.toString()),
      description: 'Settlement to ${settlement.recipientName ?? "Recipient"}',
      payerId: settlement.payerParticipantId ?? '',
      settlement: settlement,
    );
  }

  /// Helper to get the avatar/name for the "Actor" of this transaction
  /// For Expense: Payer
  /// For Settlement: Payer
  String get actorId => payerId;
}
