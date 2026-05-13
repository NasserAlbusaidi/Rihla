import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/models/split_mode.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_model.dart';
import '../providers/expense_provider.dart';
import '../widgets/expense_editor_body.dart';

/// Thin host that loads the target expense and feeds [ExpenseEditorBody] in
/// edit mode. Owns the updateExpense and deleteExpense service calls so the
/// shared body stays free of save/delete plumbing.
class EditExpenseScreen extends ConsumerWidget {
  final String groupId;
  final String eventId;
  final String expenseId;

  const EditExpenseScreen({
    super.key,
    required this.groupId,
    required this.eventId,
    required this.expenseId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventRef = (groupId: groupId, eventId: eventId);
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));

    return expensesAsync.when(
      loading: () => Scaffold(
        key: LedgerKeys.editExpenseSheet,
        backgroundColor: context.colors.scaffoldBackground,
        body: SafeArea(child: SkeletonLoader.expenseList()),
      ),
      error: (_, _) => const _ErrorScaffold(
        title: 'Could not load expense',
        message: 'Something went wrong. Try again in a moment.',
      ),
      data: (expenses) {
        final expense = expenses
            .where((e) => e.id == expenseId)
            .firstOrNull;
        if (expense == null) {
          return const _ErrorScaffold(
            title: 'Expense not found',
            message: 'This expense may have been deleted.',
          );
        }
        return KeyedSubtree(
          key: LedgerKeys.editExpenseSheet,
          child: ExpenseEditorBody(
            groupId: groupId,
            eventId: eventId,
            mode: ExpenseEditorMode.edit,
            initial: expense,
            onSubmit: (payload) => _save(ref, expense, payload),
            onDelete: () => _delete(context, ref, expense),
          ),
        );
      },
    );
  }

  Future<void> _save(
    WidgetRef ref,
    Expense original,
    ExpenseEditorPayload payload,
  ) async {
    final splitChanged = payload.splitMode != (original.splitMode ?? SplitMode.equally) ||
        !_distributionEquals(payload.splitDistribution, original.splitDistribution);
    final goingEqual = splitChanged && payload.splitMode == SplitMode.equally;

    await ref
        .read(expenseServiceProvider)
        .updateExpense(
          groupId: groupId,
          eventId: eventId,
          expenseId: original.id,
          amount: payload.amount != original.amount ? payload.amount : null,
          description: payload.description != original.description
              ? payload.description ?? ''
              : null,
          scope: payload.scope != original.scope ? payload.scope : null,
          customSplitParticipants: payload.scope == ExpenseScope.custom
              ? payload.customSplitParticipants
              : null,
          splitMode: splitChanged && !goingEqual ? payload.splitMode : null,
          splitDistribution:
              splitChanged && !goingEqual ? payload.splitDistribution : null,
          clearSplit: goingEqual,
          categoryId: payload.categoryId != original.categoryId
              ? payload.categoryId
              : null,
          payerParticipantId:
              payload.payerParticipantId != original.payerParticipantId
              ? payload.payerParticipantId
              : null,
        );

    ref.invalidate(
      eventExpensesProvider((groupId: groupId, eventId: eventId)),
    );
    HapticService.success();

    final ctx = ref.context;
    if (ctx.mounted) ctx.pop();
  }

  bool _distributionEquals(
    Map<String, dynamic>? a,
    Map<String, dynamic>? b,
  ) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (b[entry.key].toString() != entry.value.toString()) return false;
    }
    return true;
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Expense expense,
  ) async {
    await ref
        .read(expenseServiceProvider)
        .deleteExpense(
          groupId: groupId,
          eventId: eventId,
          expenseId: expense.id,
        );
    ref.invalidate(
      eventExpensesProvider((groupId: groupId, eventId: eventId)),
    );
    HapticService.success();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Expense deleted'),
          backgroundColor: context.colors.success,
        ),
      );
      context.pop();
    }
  }
}

class _ErrorScaffold extends StatelessWidget {
  const _ErrorScaffold({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: LedgerKeys.editExpenseSheet,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: EmptyStateView(
          icon: Iconsax.warning_2,
          title: title,
          message: message,
          actionLabel: 'Go back',
          onAction: () => context.pop(),
          iconColor: context.colors.textSecondary,
        ),
      ),
    );
  }
}
