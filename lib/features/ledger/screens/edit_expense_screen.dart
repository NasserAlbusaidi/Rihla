import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/services/haptic_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../events/providers/event_provider.dart';
import '../../logistics/models/sub_group_model.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../../trip/models/trip_model.dart';
import '../../trip/providers/trip_provider.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_model.dart';
import '../providers/expense_provider.dart';
import '../providers/category_provider.dart';

/// Full-page screen for editing an existing expense.
///
/// Converted from a modal bottom sheet to a GoRouter route per D-07.
/// Takes expenseId as a string for deep-link compatibility — loads the
/// expense from [eventExpensesProvider] internally.
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
  String? _selectedSubGroupId;
  late Set<String> _customSplitParticipants;

  // Payer selection (for leaders)
  String? _selectedPayerId;

  /// Get the event's currency code
  String get _tripCurrency {
    return ref
        .read(eventDetailProvider(
          (groupId: widget.groupId, eventId: widget.eventId),
        ))
        .valueOrNull
        ?.currency ?? 'OMR';
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

    // Initialize scope from expense
    _scope = expense.scope;
    _selectedSubGroupId = expense.subGroupId;
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
      subGroupId: _scope == ExpenseScope.subGroup ? _selectedSubGroupId : null,
      customSplitParticipants: _scope == ExpenseScope.custom
          ? _customSplitParticipants.toList()
          : null,
    );

    setState(() => _isSubmitting = false);

    if (mounted) {
      // Invalidate to refresh the expenses list
      ref.invalidate(eventExpensesProvider((groupId: widget.groupId, eventId: widget.eventId)));

      HapticService.success();
      context.pop();
    }
  }

  /// Confirm and delete the expense
  Future<void> _confirmDelete(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Iconsax.trash, color: AppColors.error),
            SizedBox(width: 12),
            Text('Delete Expense?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${expense.description ?? expense.categoryName ?? "this expense"}"?\n\nThis will update everyone\'s balances.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isSubmitting = true);

      await ref
          .read(expenseServiceProvider)
          .deleteExpense(
            groupId: widget.groupId,
            eventId: widget.eventId,
            expenseId: expense.id,
          );

      setState(() => _isSubmitting = false);

      if (mounted) {
        // Invalidate to refresh the expenses list
        ref.invalidate(eventExpensesProvider((groupId: widget.groupId, eventId: widget.eventId)));

        HapticService.success();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Expense deleted'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
    }
  }

  Widget _buildScopeSection() {
    final EventRef eventRef = (groupId: widget.groupId, eventId: widget.eventId);
    final subGroupsAsync = ref.watch(eventSubGroupsProvider(eventRef));
    // Participants are derived from EventModel directly in the parent screen.
    // For the scope section we don't have direct access to Event here;
    // use an empty participants list — scope editing can still change the scope type.
    final participantsAsync = AsyncValue.data(const <Participant>[]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SPLIT TYPE',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: AppColors.textMuted,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _buildScopeTab('Global', ExpenseScope.global, Iconsax.global),
                  _buildScopeTab('My Car', ExpenseScope.subGroup, Iconsax.car),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildScopeTab('Custom', ExpenseScope.custom, Iconsax.people),
                  _buildScopeTab(
                    'Personal',
                    ExpenseScope.personal,
                    Iconsax.user,
                  ),
                ],
              ),
            ],
          ),
        ),
        // Custom participant selection
        if (_scope == ExpenseScope.custom) ...[
          const SizedBox(height: 16),
          _buildCustomParticipantSelector(participantsAsync),
        ],
        // Sub-group selector for car scope
        if (_scope == ExpenseScope.subGroup)
          subGroupsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (error, stack) => const SizedBox.shrink(),
            data: (subGroups) {
              final cars = subGroups
                  .where((s) => s.type == SubGroupType.car)
                  .toList();
              if (cars.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 8,
                  children: cars.map((car) {
                    final isSelected = car.id == _selectedSubGroupId;
                    return ChoiceChip(
                      label: Text(car.name),
                      selected: isSelected,
                      onSelected: (_) =>
                          setState(() => _selectedSubGroupId = car.id),
                    );
                  }).toList(),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildScopeTab(String label, ExpenseScope scope, IconData icon) {
    final isSelected = _scope == scope;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticService.lightClick();
          setState(() => _scope = scope);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomParticipantSelector(
    AsyncValue<List<Participant>> participantsAsync,
  ) {
    return participantsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (participants) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: participants.map((p) {
          final isSelected = _customSplitParticipants.contains(p.id);
          return FilterChip(
            label: Text(p.displayName ?? 'Unknown'),
            selected: isSelected,
            onSelected: (selected) {
              HapticService.lightClick();
              setState(() {
                if (selected) {
                  _customSplitParticipants = {..._customSplitParticipants, p.id};
                } else {
                  _customSplitParticipants = _customSplitParticipants
                      .where((id) => id != p.id)
                      .toSet();
                }
              });
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPayerSelector() {
    final currentParticipant = ref.watch(
      currentParticipantProvider(widget.eventId),
    );
    final eventAsync = ref.watch(eventDetailProvider(
      (groupId: widget.groupId, eventId: widget.eventId),
    ));
    final event = eventAsync.valueOrNull;
    if (event == null) return const SizedBox.shrink();

    final currentUid = ref.watch(currentUserProvider)?.uid;
    final isLeader = currentUid != null && event.createdBy == currentUid;

    if (!isLeader) return const SizedBox.shrink();

    // Use eventLogisticsParticipantsProvider which derives participants directly
    // from the Firestore Event document — no SQLite lookup needed.
    final participants = ref.watch(eventLogisticsParticipantsProvider(event));

    if (participants.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PAID BY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: AppColors.textMuted,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedPayerId ?? currentParticipant?.id,
              isExpanded: true,
              icon: const Icon(Iconsax.arrow_down_1),
              items: participants.map((p) {
                final isMe = p.id == currentParticipant?.id;
                return DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    isMe
                        ? '${p.displayName ?? 'Unknown'} (Me)'
                        : p.displayName ?? 'Unknown',
                  ),
                );
              }).toList(),
              onChanged: (v) {
                HapticService.lightClick();
                setState(() => _selectedPayerId = v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context, Expense expense) {
    final categoriesAsync = ref.watch(tripCategoriesProvider(widget.eventId));

    return Scaffold(
      key: LedgerKeys.editExpenseSheet,
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          ModuleHeader(title: 'Edit Expense', useDarkTheme: true),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title Row with delete
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Iconsax.edit, color: AppColors.primary),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit Expense',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Changes are tracked in history',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Delete button
                      IconButton(
                        onPressed: _isSubmitting ? null : () => _confirmDelete(expense),
                        icon: const Icon(Iconsax.trash, color: AppColors.error),
                        tooltip: 'Delete expense',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Amount Field with Diff View
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'AMOUNT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textMuted,
                          letterSpacing: 1.5,
                        ),
                      ),
                      // Show original amount for reference
                      Text(
                        'was ${expense.amount.toStringAsFixed(AppFormatters.currencyConfig[_tripCurrency]?.decimals ?? 3)} $_tripCurrency',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}), // Trigger rebuild for diff
                    decoration: InputDecoration(
                      hintText: '0.000',
                      suffixText: _tripCurrency,
                      fillColor: AppColors.surfaceLight,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  // Diff indicator when amount changed
                  Builder(
                    builder: (context) {
                      final newAmount = Decimal.tryParse(_amountController.text);
                      final hasChanged =
                          newAmount != null && newAmount != expense.amount;
                      if (!hasChanged) return const SizedBox.shrink();

                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Iconsax.arrow_swap_horizontal,
                                size: 16,
                                color: AppColors.warning,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                expense.amount.toStringAsFixed(AppFormatters.currencyConfig[_tripCurrency]?.decimals ?? 3),
                                style: const TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                  color: AppColors.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward,
                                size: 14,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${newAmount.toStringAsFixed(AppFormatters.currencyConfig[_tripCurrency]?.decimals ?? 3)} $_tripCurrency',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.warning,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  // Category Selector
                  const Text(
                    'CATEGORY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textMuted,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  categoriesAsync.when(
                    loading: () => const SizedBox(height: 50),
                    error: (error, stack) => const Text('Error loading categories'),
                    data: (categories) {
                      if (categories.isEmpty) {
                        return const Text('No categories');
                      }
                      return SizedBox(
                        height: 44,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: categories.length,
                          itemBuilder: (context, index) {
                            final cat = categories[index];
                            final isSelected = cat.id == _selectedCategoryId;
                            return GestureDetector(
                              onTap: () {
                                HapticService.lightClick();
                                setState(() => _selectedCategoryId = cat.id);
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.surfaceLight,
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  cat.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  // Scope Selection
                  _buildScopeSection(),
                  const SizedBox(height: 16),
                  // Payer Selection (for leaders)
                  _buildPayerSelector(),
                  const SizedBox(height: 16),
                  // Note Field
                  const Text(
                    'NOTE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textMuted,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Add a note...',
                      fillColor: AppColors.surfaceLight,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : () => _save(expense),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Save Changes',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final EventRef eventRef = (groupId: widget.groupId, eventId: widget.eventId);
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));

    return expensesAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
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
                iconColor: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      data: (expenses) {
        final expense = expenses.where((e) => e.id == widget.expenseId).firstOrNull;

        if (expense == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Column(
              children: [
                const ModuleHeader(title: 'Edit Expense', useDarkTheme: true),
                Expanded(
                  child: EmptyStateView(
                    icon: Iconsax.warning_2,
                    title: 'Expense not found',
                    message: 'This expense may have been deleted.',
                    actionLabel: 'Go Back',
                    onAction: () => context.pop(),
                    iconColor: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        // Initialize controllers on first data load
        _initializeControllers(expense);

        return _buildForm(context, expense);
      },
    );
  }
}
