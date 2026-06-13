import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/write_ack.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
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

  Future<void> _handleSubmit(ExpenseEditorPayload payload) async {
    final currentUid = ref.read(currentUserIdProvider);
    if (currentUid == null || currentUid.isEmpty) {
      throw StateError('Cannot add expense without an authenticated user.');
    }

    // #104: captured before the await so the home-balance refresh fires even if
    // this screen is disposed during the write.
    final ledgerRevision = ref.read(ledgerRevisionProvider.notifier);
    final connectivity = ref.read(connectivityProvider.notifier);
    final connectivityStatus = ref.read(connectivityProvider);
    ref.read(expenseLoadingProvider.notifier).state = true;
    try {
      // #412: the write future acks only when the SERVER confirms — offline it
      // stays pending until reconnect. Stage the write (local cache + queued
      // replay) and race the ack instead of blocking the UI on it.
      final staged = ref
          .read(expenseServiceProvider)
          .stageExpense(
            groupId: widget.groupId,
            eventId: widget.eventId,
            payerParticipantId: payload.payerParticipantId,
            amount: payload.amount,
            // #382 PR-6: write the per-expense currency the user picked (smart
            // default = last-used-in-event → group default). amountFils is
            // scaled by this code; rules now require only a supported code, not
            // an exact group match.
            currency: payload.currency,
            description: payload.description,
            scope: payload.scope,
            customSplitParticipants: payload.customSplitParticipants,
            splitMode: payload.splitMode,
            splitDistribution: payload.splitDistribution,
            categoryId: payload.categoryId,
            createdBy: currentUid,
          );
      final outcome = await awaitServerAck(
        staged.ack,
        skipWait: connectivityStatus != ConnectivityStatus.online,
      );

      ledgerRevision.state++; // #104: refresh the one-shot home balance
      if (outcome == WriteAck.acked) {
        connectivity.noteLocalWrite(); // #357: stale-offline correction
      } else {
        connectivity.noteQueuedWrite(); // #412: queued — force "will sync"
      }
      if (!mounted) return;
      await _showSuccessDialog(staged.expense, synced: outcome == WriteAck.acked);
    } finally {
      if (mounted) {
        ref.read(expenseLoadingProvider.notifier).state = false;
      }
    }
  }

  Future<void> _showSuccessDialog(Expense expense, {required bool synced}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ExpenseSuccessDialog(
        expense: expense,
        // The created expense already carries its currency (#261).
        currency: expense.currency,
        synced: synced,
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
    // #261: the expense currency is the owning group's currency. Gate the
    // editor on the group resolving — never default to 'OMR' for an unloaded
    // group (a non-OMR group would mis-scale 10× and be rules-rejected).
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));

    return groupAsync.when(
      loading: () => Scaffold(
        key: LedgerKeys.addExpenseScreen,
        backgroundColor: context.colors.scaffoldBackground,
        body: SafeArea(child: SkeletonLoader.expenseList()),
      ),
      error: (_, _) => _ErrorScaffold(
        title: context.l10n.editorCouldNotLoadExpenseTitle,
        message: context.l10n.editorCouldNotLoadExpenseMessage,
      ),
      data: (group) {
        if (group == null) {
          return _ErrorScaffold(
            title: context.l10n.editorCouldNotLoadExpenseTitle,
            message: context.l10n.editorCouldNotLoadExpenseMessage,
          );
        }
        return KeyedSubtree(
          key: LedgerKeys.addExpenseScreen,
          child: ExpenseEditorBody(
            key: ValueKey(_formGeneration),
            groupId: widget.groupId,
            eventId: widget.eventId,
            mode: ExpenseEditorMode.add,
            currency: group.currency,
            onSubmit: _handleSubmit,
          ),
        );
      },
    );
  }
}

class _ErrorScaffold extends StatelessWidget {
  const _ErrorScaffold({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: LedgerKeys.addExpenseScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: EmptyStateView(
          icon: Iconsax.warning_2,
          title: title,
          message: message,
          actionLabel: context.l10n.commonBack,
          onAction: () => context.pop(),
          iconColor: context.colors.textSecondary,
        ),
      ),
    );
  }
}
