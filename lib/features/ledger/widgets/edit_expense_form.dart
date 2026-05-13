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
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/module_header.dart';
import '../models/expense_category_model.dart';
import 'category_picker_sheet.dart';
import 'custom_split_sheet.dart';
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
    final decimals = AppFormatters.currencyConfig[tripCurrency]?.decimals ?? 3;

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
                        icon: Icon(Iconsax.trash, color: context.colors.error),
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
                      final hasChanged =
                          newAmount != null &&
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
                            color: context.colors.warning.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: context.colors.warning.withValues(
                                alpha: 0.3,
                              ),
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
                                initialExpense.amount.toStringAsFixed(decimals),
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
                    loading: () => const SizedBox(height: 56),
                    error: (err, _) => const Text('Error loading categories'),
                    data: (categories) {
                      if (categories.isEmpty) {
                        return const Text('No categories');
                      }
                      final selected = categories.firstWhere(
                        (c) => c.id == selectedCategoryId,
                        orElse: () => categories.first,
                      );
                      return _CategoryPickerTile(
                        category: selected,
                        onTap: () async {
                          HapticService.selection();
                          final picked = await showCategoryPickerSheet(
                            context,
                            tripId: eventId,
                            selectedCategoryId: selectedCategoryId,
                          );
                          if (picked != null) {
                            onCategoryChanged(picked);
                          }
                        },
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
                    customSplitParticipants: customSplitParticipants,
                    onCustomSplitChanged: onCustomSplitChanged,
                  ),
                  const SizedBox(height: 12),
                  _SplitPreviewLink(onTap: () => _openSplitPreview(context)),
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
                          onPressed: isSaving ? null : onSubmit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
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

  void _openSplitPreview(BuildContext context) {
    final raw = amountController.text.trim();
    final amount = Decimal.tryParse(raw.isEmpty ? '0' : raw) ?? Decimal.zero;
    if (amount == Decimal.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter an amount first to preview the split.'),
        ),
      );
      return;
    }

    final included = _participantsForScope();
    if (included.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add participants to preview the split.')),
      );
      return;
    }

    showCustomSplitSheet(
      context,
      title: noteController.text.trim().isNotEmpty
          ? noteController.text.trim()
          : 'This expense',
      total: amount,
      currency: tripCurrency,
      participants: included
          .map(
            (id) => SplitParticipant(
              id: id,
              name: event.participantNames[id] ?? 'Member',
              role: id == selectedPayerId ? 'Paid' : null,
            ),
          )
          .toList(),
    );
  }

  List<String> _participantsForScope() {
    switch (scope) {
      case ExpenseScope.global:
      case ExpenseScope.subGroup:
        return event.participantIds;
      case ExpenseScope.custom:
        return customSplitParticipants.toList();
      case ExpenseScope.personal:
        return selectedPayerId != null ? [selectedPayerId!] : const [];
    }
  }
}

class _SplitPreviewLink extends StatelessWidget {
  const _SplitPreviewLink({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.inputFillWarm,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.borderWarm),
        ),
        child: Row(
          children: [
            Icon(Iconsax.calculator, size: 16, color: colors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Preview split',
                style: AppTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPickerTile extends StatelessWidget {
  const _CategoryPickerTile({required this.category, required this.onTap});

  final ExpenseCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: context.shadows.raised,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: category.resolveColor(colors),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                category.name.isNotEmpty ? category.name[0].toUpperCase() : '·',
                style: AppTypography.display(fontSize: 18, color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                category.name,
                style: AppTypography.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
