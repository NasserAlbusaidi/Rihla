import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/services/haptic_service.dart';
import '../../events/providers/event_provider.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../models/expense_model.dart';
import '../providers/expense_provider.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../widgets/edit_expense_form.dart';

/// Full-page screen for editing an existing expense.
///
/// Converted from a modal bottom sheet to a GoRouter route per D-07.
/// Takes expenseId as a string for deep-link compatibility — loads the
/// expense from [eventExpensesProvider] internally.
///
/// This screen is an orchestrator: it owns all mutable state, the submit
/// handler, and the delete handler. The form UI is delegated to
/// [EditExpenseForm], which is a stateless controlled component.
class EditExpenseScreen extends ConsumerStatefulWidget {
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
  ConsumerState<EditExpenseScreen> createState() => _EditExpenseScreenState();
}

class _EditExpenseScreenState extends ConsumerState<EditExpenseScreen> {
  late TextEditingController _amountController;
  late TextEditingController _noteController;
  late String? _selectedCategoryId;
  bool _isSubmitting = false;
  bool _initialized = false;

  // Scope editing
  late ExpenseScope _scope;
  late Set<String> _customSplitParticipants;

  // Payer selection (for leaders)
  String? _selectedPayerId;

  /// Currency code for this event.
  String get _tripCurrency {
    return ref
            .read(
              eventDetailProvider(
                (groupId: widget.groupId, eventId: widget.eventId),
              ),
            )
            .valueOrNull
            ?.currency ??
        'OMR';
  }

  void _initializeControllers(Expense expense) {
    if (_initialized) return;
    _amountController = TextEditingController(
      text: expense.amount.toString(),
    );
    _noteController = TextEditingController(
      text: expense.description ?? '',
    );
    _selectedCategoryId = expense.categoryId;
    _scope = expense.scope;
    _customSplitParticipants =
        expense.customSplitParticipants?.toSet() ?? {};
    _selectedPayerId = expense.payerParticipantId;
    _initialized = true;
  }

  @override
  void dispose() {
    if (_initialized) {
      _amountController.dispose();
      _noteController.dispose();
    }
    super.dispose();
  }

  Future<void> _save(Expense expense) async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);
    HapticService.lightClick();

    final newAmount = Decimal.tryParse(_amountController.text);
    if (newAmount == null || newAmount <= Decimal.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      setState(() => _isSubmitting = false);
      return;
    }

    final expenseService = ref.read(expenseServiceProvider);
    await expenseService.updateExpense(
      groupId: widget.groupId,
      eventId: widget.eventId,
      expenseId: expense.id,
      amount: newAmount != expense.amount ? newAmount : null,
      description: _noteController.text.trim() != expense.description
          ? _noteController.text.trim()
          : null,
      scope: _scope != expense.scope ? _scope : null,
      customSplitParticipants: _scope == ExpenseScope.custom
          ? _customSplitParticipants.toList()
          : null,
      categoryId: _selectedCategoryId != expense.categoryId
          ? _selectedCategoryId
          : null,
      payerParticipantId:
          _selectedPayerId != expense.payerParticipantId
              ? _selectedPayerId
              : null,
    );

    setState(() => _isSubmitting = false);

    if (mounted) {
      ref.invalidate(
        eventExpensesProvider(
          (groupId: widget.groupId, eventId: widget.eventId),
        ),
      );
      HapticService.success();
      context.pop();
    }
  }

  /// Shows a confirmation dialog then deletes the expense.
  Future<void> _confirmDelete(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Iconsax.trash, color: context.colors.error),
            const SizedBox(width: 12),
            const Text('Delete Expense?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete '
          '"${expense.description ?? expense.categoryName ?? "this expense"}"?\n\n'
          "This will update everyone's balances.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(color: context.colors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isSubmitting = true);

      await ref.read(expenseServiceProvider).deleteExpense(
            groupId: widget.groupId,
            eventId: widget.eventId,
            expenseId: expense.id,
          );

      setState(() => _isSubmitting = false);

      if (mounted) {
        ref.invalidate(
          eventExpensesProvider(
            (groupId: widget.groupId, eventId: widget.eventId),
          ),
        );
        HapticService.success();
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

  @override
  Widget build(BuildContext context) {
    final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final eventAsync = ref.watch(eventDetailProvider(eventRef));

    return expensesAsync.when(
      loading: () => Scaffold(
        backgroundColor: context.colors.scaffoldBackground,
        body: Column(
          children: [
            const ModuleHeader(title: 'Edit Expense', useDarkTheme: true),
            Expanded(child: SkeletonLoader.expenseList()),
          ],
        ),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: context.colors.scaffoldBackground,
        body: Column(
          children: [
            const ModuleHeader(title: 'Edit Expense', useDarkTheme: true),
            Expanded(
              child: EmptyStateView(
                icon: Iconsax.warning_2,
                title: 'Error loading expense',
                message: 'Could not load the expense data.',
                actionLabel: 'Go Back',
                onAction: () => context.pop(),
                iconColor: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      data: (expenses) {
        final expense =
            expenses.where((e) => e.id == widget.expenseId).firstOrNull;

        if (expense == null) {
          return Scaffold(
            backgroundColor: context.colors.scaffoldBackground,
            body: Column(
              children: [
                const ModuleHeader(
                  title: 'Edit Expense',
                  useDarkTheme: true,
                ),
                Expanded(
                  child: EmptyStateView(
                    icon: Iconsax.warning_2,
                    title: 'Expense not found',
                    message: 'This expense may have been deleted.',
                    actionLabel: 'Go Back',
                    onAction: () => context.pop(),
                    iconColor: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        _initializeControllers(expense);

        final event = eventAsync.valueOrNull;
        if (event == null) {
          return Scaffold(
            backgroundColor: context.colors.scaffoldBackground,
            body: Column(
              children: [
                const ModuleHeader(
                  title: 'Edit Expense',
                  useDarkTheme: true,
                ),
                Expanded(child: SkeletonLoader.expenseList()),
              ],
            ),
          );
        }

        return EditExpenseForm(
          initialExpense: expense,
          groupId: widget.groupId,
          eventId: widget.eventId,
          event: event,
          tripCurrency: _tripCurrency,
          amountController: _amountController,
          noteController: _noteController,
          selectedCategoryId: _selectedCategoryId,
          onCategoryChanged: (id) => setState(() => _selectedCategoryId = id),
          scope: _scope,
          onScopeChanged: (s) => setState(() => _scope = s),
          customSplitParticipants: _customSplitParticipants,
          onCustomSplitChanged: (set) =>
              setState(() => _customSplitParticipants = set),
          selectedPayerId: _selectedPayerId,
          onPayerChanged: (id) => setState(() => _selectedPayerId = id),
          onSubmit: () => _save(expense),
          onDelete: () => _confirmDelete(expense),
          isSaving: _isSubmitting,
        );
      },
    );
  }
}
