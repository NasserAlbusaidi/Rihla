import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../trip/providers/trip_provider.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_model.dart';
import '../providers/expense_provider.dart';
import '../widgets/expense_editor_body.dart';
import '../widgets/expense_success_dialog.dart';

/// Thin host for the shared [ExpenseEditorBody] in add mode. Owns the
/// addExpense service call and the success dialog flow.
class AddExpenseScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String eventId;

  const AddExpenseScreen({
    super.key,
    required this.groupId,
    required this.eventId,
  });

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  /// Bumped after each "Add another" tap to remount [ExpenseEditorBody] with
  /// fresh state without coupling the body to the parent's lifecycle.
  int _formGeneration = 0;

  String get _tripCurrency => 'OMR';

  Future<void> _handleSubmit(ExpenseEditorPayload payload) async {
    final currentParticipant = ref.read(
      currentEventParticipantProvider((
        groupId: widget.groupId,
        eventId: widget.eventId,
      )),
    );

    ref.read(expenseLoadingProvider.notifier).state = true;
    try {
      final expense = await ref
          .read(expenseServiceProvider)
          .addExpense(
            groupId: widget.groupId,
            eventId: widget.eventId,
            payerParticipantId: payload.payerParticipantId,
            actorId: currentParticipant?.id,
            actorName: currentParticipant?.displayName,
            amount: payload.amount,
            description: payload.description,
            scope: payload.scope,
            customSplitParticipants: payload.customSplitParticipants,
            splitMode: payload.splitMode,
            splitDistribution: payload.splitDistribution,
            categoryId: payload.categoryId,
          );

      if (!mounted) return;
      await _showSuccessDialog(expense);
    } finally {
      if (mounted) {
        ref.read(expenseLoadingProvider.notifier).state = false;
      }
    }
  }

  Future<void> _showSuccessDialog(Expense expense) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ExpenseSuccessDialog(
        expense: expense,
        currency: _tripCurrency,
        onDone: () {
          Navigator.of(dialogContext).pop();
          context.pop(true);
        },
        onAddAnother: () {
          Navigator.of(dialogContext).pop();
          setState(() => _formGeneration++);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: LedgerKeys.addExpenseScreen,
      child: ExpenseEditorBody(
        key: ValueKey(_formGeneration),
        groupId: widget.groupId,
        eventId: widget.eventId,
        mode: ExpenseEditorMode.add,
        onSubmit: _handleSubmit,
      ),
    );
  }
}
