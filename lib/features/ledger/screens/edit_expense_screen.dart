import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/models/split_mode.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/write_ack.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../events/providers/event_provider.dart';
import '../../groups/providers/group_balance_provider.dart';
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
      error: (_, _) => _ErrorScaffold(
        title: context.l10n.editorCouldNotLoadExpenseTitle,
        message: context.l10n.editorCouldNotLoadExpenseMessage,
      ),
      data: (expenses) {
        final expense = expenses.where((e) => e.id == expenseId).firstOrNull;
        if (expense == null) {
          return _ErrorScaffold(
            title: context.l10n.editorExpenseNotFoundTitle,
            message: context.l10n.editorExpenseNotFoundMessage,
          );
        }
        final currentUid = ref.watch(currentUserIdProvider);
        // #248 PR4: OPEN edit — any event participant may edit/delete. Rules
        // (validExpenseUpdate + the lastEditedBy==auth.uid pin) are the real gate;
        // this is UX only. Optimistic: if the event hasn't resolved
        // (loading/error/missing) show the editor and let rules reject a true
        // non-participant on save — a stream hiccup must not block a real participant.
        final event = ref
            .watch(eventDetailProvider((groupId: groupId, eventId: eventId)))
            .valueOrNull;
        final canEdit =
            currentUid == null ||
            event == null ||
            event.participantIds.contains(currentUid);
        if (!canEdit) {
          return _ErrorScaffold(
            title: context.l10n.editorViewOnlyTitle,
            message: context.l10n.editorViewOnlyMessage,
          );
        }
        return KeyedSubtree(
          key: LedgerKeys.editExpenseSheet,
          child: ExpenseEditorBody(
            groupId: groupId,
            eventId: eventId,
            mode: ExpenseEditorMode.edit,
            // #261: display the expense's own stored currency (label + input
            // decimals). The write preserves it via _save → updateExpense
            // (currency: original.currency), unchanged.
            currency: expense.currency,
            // #382 PR-6: edit mode never shows the picker/warning (body's
            // !_isEdit gate); the dominant signal is add-mode only.
            dominantCurrency: null,
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
    final splitChanged =
        payload.splitMode != (original.splitMode ?? SplitMode.equally) ||
        !_distributionEquals(
          payload.splitDistribution,
          original.splitDistribution,
        );
    final goingEqual = splitChanged && payload.splitMode == SplitMode.equally;

    // #104/#412: capture before the await so post-write effects survive a
    // disposal during the (now bounded) wait.
    final ledgerRevision = ref.read(ledgerRevisionProvider.notifier);
    final connectivity = ref.read(connectivityProvider.notifier);
    final connectivityStatus = ref.read(connectivityProvider);

    // #412: never gate the UI on the raw server-ack future — offline it stays
    // pending until reconnect. Race it; queued means the SDK will replay.
    final writeFuture = ref
        .read(expenseServiceProvider)
        .updateExpense(
          groupId: groupId,
          eventId: eventId,
          expenseId: original.id,
          amount: payload.amount != original.amount ? payload.amount : null,
          // #261: preserve the expense's own currency on every edit — never let
          // updateExpense default it to OMR (which would re-scale amountFils).
          currency: original.currency,
          description: payload.description != original.description
              ? payload.description ?? ''
              : null,
          scope: payload.scope != original.scope ? payload.scope : null,
          customSplitParticipants: payload.scope == ExpenseScope.custom
              ? payload.customSplitParticipants
              : null,
          splitMode: splitChanged && !goingEqual ? payload.splitMode : null,
          splitDistribution: splitChanged && !goingEqual
              ? payload.splitDistribution
              : null,
          clearSplit: goingEqual,
          categoryId: payload.categoryId != original.categoryId
              ? payload.categoryId
              : null,
          payerParticipantId:
              payload.payerParticipantId != original.payerParticipantId
              ? payload.payerParticipantId
              : null,
          lastEditedBy: ref.read(currentUserIdProvider), // #248
        );
    final outcome = await awaitServerAck(
      writeFuture,
      skipWait: connectivityStatus != ConnectivityStatus.online,
    );

    ledgerRevision.state++; // #104: refresh home balance
    if (outcome == WriteAck.acked) {
      connectivity.noteLocalWrite(); // #357
    } else {
      connectivity.noteQueuedWrite(); // #412: queued — force "will sync"
    }
    HapticService.success();

    final ctx = ref.context;
    if (ctx.mounted) {
      // Belt-and-braces only — the ledger stream updates from local snapshots.
      ref.invalidate(
        eventExpensesProvider((groupId: groupId, eventId: eventId)),
      );
      ctx.pop();
    }
  }

  bool _distributionEquals(Map<String, dynamic>? a, Map<String, dynamic>? b) {
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
    // #104/#412: capture before the await so post-write effects survive a
    // disposal during the (now bounded) wait.
    final ledgerRevision = ref.read(ledgerRevisionProvider.notifier);
    final connectivity = ref.read(connectivityProvider.notifier);
    final connectivityStatus = ref.read(connectivityProvider);

    final outcome = await awaitServerAck(
      ref
          .read(expenseServiceProvider)
          .deleteExpense(
            groupId: groupId,
            eventId: eventId,
            expenseId: expense.id,
            lastEditedBy: ref.read(currentUserIdProvider), // #248
          ),
      skipWait: connectivityStatus != ConnectivityStatus.online,
    );
    ledgerRevision.state++; // #104: refresh home balance
    if (outcome == WriteAck.acked) {
      connectivity.noteLocalWrite(); // #357
    } else {
      connectivity.noteQueuedWrite(); // #412: queued — force "will sync"
    }
    HapticService.success();
    if (context.mounted) {
      ref.invalidate(
        eventExpensesProvider((groupId: groupId, eventId: eventId)),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.editorExpenseDeleted),
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
          actionLabel: context.l10n.commonBack,
          onAction: () => context.pop(),
          iconColor: context.colors.textSecondary,
        ),
      ),
    );
  }
}
