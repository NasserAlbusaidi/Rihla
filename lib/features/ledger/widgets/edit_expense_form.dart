import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/utils/formatters.dart';
import '../../events/models/event_model.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_model.dart';
import '../providers/category_provider.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../shared/widgets/module_header.dart';
import 'edit_expense_payer_selector.dart';
import 'edit_expense_scope_section.dart';

/// Main form body for editing an existing expense.
///
/// All mutable state (controllers, scope, category) lives on [EditExpenseScreen].
/// This widget is a controlled component — it delegates every user action to
/// the callbacks provided by the parent, keeping the screen as the single
/// source of truth.
class EditExpenseForm extends ConsumerWidget {
  final Expense initialExpense;
  final String groupId;
  final String eventId;
  final Event event;
  final String tripCurrency;
  final TextEditingController amountController;
  final TextEditingController noteController;
  final String? selectedCategoryId;
  final ValueChanged<String?> onCategoryChanged;
  final ExpenseScope scope;
  final ValueChanged<ExpenseScope> onScopeChanged;
  final String? selectedSubGroupId;
  final ValueChanged<String?> onSubGroupIdChanged;
  final Set<String> customSplitParticipants;
  final ValueChanged<Set<String>> onCustomSplitChanged;
  final String? selectedPayerId;
  final ValueChanged<String?> onPayerChanged;
  final VoidCallback onSubmit;
  final VoidCallback onDelete;
  final bool isSaving;

  const EditExpenseForm({
    super.key,
    required this.initialExpense,
    required this.groupId,
    required this.eventId,
    required this.event,
    required this.tripCurrency,
    required this.amountController,
    required this.noteController,
    required this.selectedCategoryId,
    required this.onCategoryChanged,
    required this.scope,
    required this.onScopeChanged,
    required this.selectedSubGroupId,
    required this.onSubGroupIdChanged,
    required this.customSplitParticipants,
    required this.onCustomSplitChanged,
    required this.selectedPayerId,
    required this.onPayerChanged,
    required this.onSubmit,
    required this.onDelete,
    required this.isSaving,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(tripCategoriesProvider(eventId));
    final decimals =
        AppFormatters.currencyConfig[tripCurrency]?.decimals ?? 3;

    return Scaffold(
      key: LedgerKeys.editExpenseSheet,
      backgroundColor: context.colors.scaffoldBackground,
      body: Column(
        children: [
          const ModuleHeader(title: 'Edit Expense', useDarkTheme: true),
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
                  // ── Header row with delete button ──────────────────────
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.colors.selectionFill,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Iconsax.edit,
                          color: context.colors.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit Expense',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: context.colors.textPrimary,
                              ),
                            ),
                            Text(
                              'Changes are tracked in history',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: isSaving ? null : onDelete,
                        icon: Icon(
                          Iconsax.trash,
                          color: context.colors.error,
                        ),
                        tooltip: 'Delete expense',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Amount field with diff view ─────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'AMOUNT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: context.colors.textSecondary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        'was ${initialExpense.amount.toStringAsFixed(decimals)} $tripCurrency',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) {
                      // No-op: parent rebuilds via setState already.
                      // ValueListenableBuilder pattern would remove this
                      // entirely in a future refactor.
                    },
                    decoration: InputDecoration(
                      hintText: '0.000',
                      suffixText: tripCurrency,
                      fillColor: context.colors.inputFill,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  // Diff indicator when amount changed
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: amountController,
                    builder: (context, value, _) {
                      final newAmount = Decimal.tryParse(value.text);
                      final hasChanged = newAmount != null &&
                          newAmount != initialExpense.amount;
                      if (!hasChanged) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: context.colors.warning
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: context.colors.warning
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Iconsax.arrow_swap_horizontal,
                                size: 16,
                                color: context.colors.warning,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                initialExpense.amount
                                    .toStringAsFixed(decimals),
                                style: TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                  color: context.colors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward,
                                size: 14,
                                color: context.colors.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${newAmount.toStringAsFixed(decimals)} $tripCurrency',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: context.colors.warning,
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

                  // ── Category selector ───────────────────────────────────
                  Text(
                    'CATEGORY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: context.colors.textSecondary,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  categoriesAsync.when(
                    loading: () => const SizedBox(height: 50),
                    error: (err, _) =>
                        const Text('Error loading categories'),
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
                            final isSelected =
                                cat.id == selectedCategoryId;
                            return GestureDetector(
                              onTap: () {
                                HapticService.lightClick();
                                onCategoryChanged(cat.id);
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? context.colors.primary
                                      : context.colors.inputFill,
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  cat.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : context.colors.textSecondary,
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

                  // ── Scope selector ──────────────────────────────────────
                  EditExpenseScopeSection(
                    groupId: groupId,
                    eventId: eventId,
                    scope: scope,
                    onScopeChanged: onScopeChanged,
                    selectedSubGroupId: selectedSubGroupId,
                    onSubGroupIdChanged: onSubGroupIdChanged,
                    customSplitParticipants: customSplitParticipants,
                    onCustomSplitChanged: onCustomSplitChanged,
                  ),
                  const SizedBox(height: 16),

                  // ── Payer selector (leaders only) ───────────────────────
                  EditExpensePayerSelector(
                    event: event,
                    eventId: eventId,
                    selectedPayerId: selectedPayerId,
                    onPayerChanged: onPayerChanged,
                  ),
                  const SizedBox(height: 16),

                  // ── Note field ──────────────────────────────────────────
                  Text(
                    'NOTE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: context.colors.textSecondary,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Add a note...',
                      fillColor: context.colors.inputFill,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Action buttons ──────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.pop(),
                          style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
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
                          onPressed: isSaving ? null : onSubmit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                context.colors.primary,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: isSaving
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
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
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
}
