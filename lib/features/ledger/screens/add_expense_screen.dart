import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../trip/providers/trip_provider.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_category_model.dart';
import '../models/expense_model.dart';
import '../providers/category_provider.dart';
import '../providers/expense_provider.dart';
import '../services/receipt_service.dart';
import '../widgets/expense_success_dialog.dart';
import '../widgets/receipt_picker_section.dart';
import '../widgets/split_scope_selector.dart';

/// Add Expense screen, aligned to the saffron hi-fi single-page form.
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
  final _noteController = TextEditingController();
  final _amountController = TextEditingController(text: '0');

  String _amount = '0';
  ExpenseScope _scope = ExpenseScope.global;
  String? _selectedCategoryId;
  String? _selectedSubGroupId;
  String? _selectedPayerId;
  final Set<String> _customSplitParticipants = {};

  String? _receiptPath;
  bool _isUploadingReceipt = false;

  String get _tripCurrency => 'OMR';

  @override
  void dispose() {
    _noteController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _autoSelectUserSubGroup() {}

  Future<void> _submit() async {
    Decimal amount;
    try {
      amount = Decimal.parse(_amount);
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid amount')),
        );
      }
      return;
    }

    if (amount <= Decimal.zero) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Amount must be greater than zero')),
        );
      }
      return;
    }

    HapticService.success();
    final note = _noteController.text.trim();
    final currentParticipant = ref.read(
      currentEventParticipantProvider((
        groupId: widget.groupId,
        eventId: widget.eventId,
      )),
    );

    if (currentParticipant == null) {
      ref.read(expenseErrorProvider.notifier).state =
          'Could not identify your participant record.';
      return;
    }

    ref.read(expenseLoadingProvider.notifier).state = true;

    try {
      String? receiptUrl;
      if (_receiptPath != null) {
        setState(() => _isUploadingReceipt = true);
        receiptUrl = await _uploadReceipt(_receiptPath!);
        if (!mounted) return;
        setState(() => _isUploadingReceipt = false);
      }

      final expense = await ref
          .read(expenseServiceProvider)
          .addExpense(
            groupId: widget.groupId,
            eventId: widget.eventId,
            payerParticipantId: _selectedPayerId ?? currentParticipant.id,
            actorId: currentParticipant.id,
            actorName: currentParticipant.displayName,
            amount: amount,
            description: note.isNotEmpty ? note : null,
            scope: _scope,
            subGroupId: _selectedSubGroupId,
            customSplitParticipants: _scope == ExpenseScope.custom
                ? _customSplitParticipants.toList()
                : null,
            receiptUrl: receiptUrl,
            categoryId: _selectedCategoryId,
          );

      if (mounted) _showSuccessDialog(expense);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add expense: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        ref.read(expenseLoadingProvider.notifier).state = false;
      }
    }
  }

  Future<void> _pickReceipt() async {
    HapticService.lightClick();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null &&
        result.files.isNotEmpty &&
        result.files.first.path != null) {
      setState(() => _receiptPath = result.files.first.path);
    }
  }

  Future<String?> _uploadReceipt(String filePath) async {
    final file = File(filePath);
    final expenseId = const Uuid().v4();
    return ref
        .read(receiptServiceProvider)
        .uploadReceipt(
          groupId: widget.groupId,
          eventId: widget.eventId,
          expenseId: expenseId,
          imageFile: file,
        );
  }

  void _showSuccessDialog(Expense expense) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ExpenseSuccessDialog(
        expense: expense,
        currency: _tripCurrency,
        onDone: () {
          Navigator.of(context).pop();
          context.pop(true);
        },
        onAddAnother: () {
          Navigator.of(context).pop();
          setState(() {
            _amount = '0';
            _amountController.text = '0';
            _noteController.clear();
            _selectedCategoryId = null;
            _scope = ExpenseScope.global;
            _customSplitParticipants.clear();
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(expenseLoadingProvider);
    final error = ref.watch(expenseErrorProvider);
    final categoriesAsync = ref.watch(tripCategoriesProvider(widget.eventId));
    final eventAsync = ref.watch(
      eventDetailProvider((groupId: widget.groupId, eventId: widget.eventId)),
    );
    final event = eventAsync.valueOrNull;
    final currentParticipant = ref.watch(
      currentEventParticipantProvider((
        groupId: widget.groupId,
        eventId: widget.eventId,
      )),
    );

    return Scaffold(
      key: LedgerKeys.addExpenseScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _ExpenseTopBar(
              isLoading: isLoading,
              onClose: () {
                HapticService.lightClick();
                context.pop();
              },
              onAdd: _submit,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AmountHero(
                      controller: _amountController,
                      amount: _amount,
                      currency: _tripCurrency,
                      onChanged: (value) =>
                          setState(() => _amount = _sanitizeAmount(value)),
                    ),
                    _DescriptionField(controller: _noteController),
                    _Section(
                      title: 'Category',
                      child: _CategoryStrip(
                        categoriesAsync: categoriesAsync,
                        selectedCategoryId: _selectedCategoryId,
                        onCategorySelected: (id) {
                          HapticService.selection();
                          setState(() => _selectedCategoryId = id);
                        },
                      ),
                    ),
                    if (event != null) ...[
                      _Section(
                        title: 'Paid by',
                        child: _PaidByCard(
                          event: event,
                          payerId: _selectedPayerId ?? currentParticipant?.id,
                        ),
                      ),
                      _Section(
                        title: 'Split between',
                        action: 'Customise',
                        child: _SplitCard(
                          event: event,
                          amount: Decimal.tryParse(_amount) ?? Decimal.zero,
                          scope: _scope,
                          selectedPayerId: _selectedPayerId,
                          customSplitParticipants: _customSplitParticipants,
                          selectedSubGroupId: _selectedSubGroupId,
                          onScopeChanged: (scope) =>
                              setState(() => _scope = scope),
                          onCustomSplitChanged: (participants) {
                            setState(() {
                              _customSplitParticipants
                                ..clear()
                                ..addAll(participants);
                            });
                          },
                          onPayerChanged: (value) =>
                              setState(() => _selectedPayerId = value),
                          onAutoSelectSubGroup: _autoSelectUserSubGroup,
                          onSubGroupIdCleared: (value) =>
                              setState(() => _selectedSubGroupId = value),
                        ),
                      ),
                      _Section(
                        title: 'Where',
                        child: _WhereCard(event: event),
                      ),
                    ] else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    _Section(
                      title: 'Receipt',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _CardShell(
                          padding: const EdgeInsets.all(16),
                          child: ReceiptPickerSection(
                            receiptPath: _receiptPath,
                            isUploading: _isUploadingReceipt,
                            onPick: _pickReceipt,
                            onRemove: () => setState(() => _receiptPath = null),
                          ),
                        ),
                      ),
                    ),
                    if (error != null) _ErrorBanner(error: error),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sanitizeAmount(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return '0';
    final parts = cleaned.split('.');
    if (parts.length == 1) return cleaned;
    final maxDecimals =
        AppFormatters.currencyConfig[_tripCurrency]?.decimals ?? 3;
    final fraction = parts.skip(1).join();
    final clampedFraction = fraction.substring(
      0,
      fraction.length.clamp(0, maxDecimals),
    );
    return '${parts.first.isEmpty ? '0' : parts.first}.$clampedFraction';
  }
}

class _ExpenseTopBar extends StatelessWidget {
  const _ExpenseTopBar({
    required this.isLoading,
    required this.onClose,
    required this.onAdd,
  });

  final bool isLoading;
  final VoidCallback onClose;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 20, 8),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Close',
                icon: const Icon(Iconsax.close_circle, size: 20),
                color: context.colors.textPrimary,
                onPressed: onClose,
              ),
            ),
            Text(
              'Add expense',
              style: AppTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: isLoading ? null : onAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: context.colors.textOnPrimary,
                  minimumSize: const Size(64, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      context.spacing.radiusSmall,
                    ),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountHero extends StatelessWidget {
  const _AmountHero({
    required this.controller,
    required this.amount,
    required this.currency,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String amount;
  final String currency;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final parts = amount.split('.');
    final whole = parts.first.isEmpty ? '0' : parts.first;
    final fraction = parts.length > 1 ? '.${parts.last}' : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            children: [
              Text(
                'AMOUNT · $currency',
                style: AppTypography.mono(
                  fontSize: 9,
                  letterSpacing: 2,
                  color: context.colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    currency,
                    style: AppTypography.mono(
                      fontSize: 22,
                      color: context.colors.textSecondary,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    whole,
                    style: AppTypography.mono(
                      fontSize: 64,
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w500,
                      height: 1,
                    ),
                  ),
                  if (fraction.isNotEmpty)
                    Text(
                      fraction,
                      style: AppTypography.mono(
                        fontSize: 32,
                        color: context.colors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: 120,
                height: 2,
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
          Positioned.fill(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.transparent),
              cursorColor: Colors.transparent,
              decoration: const InputDecoration(
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DescriptionField extends StatelessWidget {
  const _DescriptionField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: 'Description',
          hintText: 'What was it for?',
          filled: true,
          fillColor: context.colors.scaffoldBackground,
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.colors.rule2),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.colors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.action});

  final String title;
  final String? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
                if (action != null)
                  Text(
                    action!,
                    style: AppTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.colors.primaryDark,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.categoriesAsync,
    required this.selectedCategoryId,
    required this.onCategorySelected,
  });

  final AsyncValue<List<ExpenseCategory>> categoriesAsync;
  final String? selectedCategoryId;
  final ValueChanged<String> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    return categoriesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: LinearProgressIndicator(),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Could not load categories.',
          style: TextStyle(color: context.colors.errorText),
        ),
      ),
      data: (categories) => SizedBox(
        height: 42,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          scrollDirection: Axis.horizontal,
          itemCount: categories.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final category = categories[index];
            return _CategoryChip(
              category: category,
              selected: selectedCategoryId == category.id,
              onTap: () => onCategorySelected(category.id),
            );
          },
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final ExpenseCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(context, category.name);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        decoration: BoxDecoration(
          color: selected
              ? context.colors.textPrimary
              : context.colors.cardSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? context.colors.textPrimary : context.colors.rule2,
          ),
          boxShadow: selected ? context.shadows.flat : context.shadows.raised,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.18)
                    : context.colors.cardSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                category.iconData,
                size: 11,
                color: selected ? Colors.white : color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              category.name,
              style: AppTypography.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected
                    ? context.colors.scaffoldBackground
                    : context.colors.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaidByCard extends StatelessWidget {
  const _PaidByCard({required this.event, required this.payerId});

  final Event event;
  final String? payerId;

  @override
  Widget build(BuildContext context) {
    final effectivePayerId = payerId ?? event.participantIds.firstOrNull;
    final payerName =
        event.participantNames[effectivePayerId] ?? 'Selected payer';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _CardShell(
        child: _InfoRow(
          leading: _Avatar(name: payerName),
          title: payerName,
          subtitle: 'Selected · paid the full amount',
          trailing: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: context.colors.textPrimary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Iconsax.tick_circle,
              size: 14,
              color: context.colors.scaffoldBackground,
            ),
          ),
        ),
      ),
    );
  }
}

class _SplitCard extends StatelessWidget {
  const _SplitCard({
    required this.event,
    required this.amount,
    required this.scope,
    required this.selectedPayerId,
    required this.customSplitParticipants,
    required this.selectedSubGroupId,
    required this.onScopeChanged,
    required this.onCustomSplitChanged,
    required this.onPayerChanged,
    required this.onAutoSelectSubGroup,
    required this.onSubGroupIdCleared,
  });

  final Event event;
  final Decimal amount;
  final ExpenseScope scope;
  final String? selectedPayerId;
  final Set<String> customSplitParticipants;
  final String? selectedSubGroupId;
  final ValueChanged<ExpenseScope> onScopeChanged;
  final ValueChanged<Set<String>> onCustomSplitChanged;
  final ValueChanged<String?> onPayerChanged;
  final VoidCallback onAutoSelectSubGroup;
  final ValueChanged<String?> onSubGroupIdCleared;

  @override
  Widget build(BuildContext context) {
    final count = _splitCount;
    final each = count == 0
        ? Decimal.zero
        : (amount / Decimal.fromInt(count)).toDecimal(
            scaleOnInfinitePrecision: 3,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _CardShell(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_scopeLabel(scope)} · $count way${count == 1 ? '' : 's'}',
                    style: AppTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${AppFormatters.formatCurrency(each, 'OMR')} each',
                  style: AppTypography.sans(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SplitScopeSelector(
              event: event,
              scope: scope,
              onScopeChanged: onScopeChanged,
              customSplitParticipants: customSplitParticipants,
              onCustomSplitChanged: onCustomSplitChanged,
              selectedSubGroupId: selectedSubGroupId,
              onAutoSelectSubGroup: onAutoSelectSubGroup,
              onSubGroupIdCleared: onSubGroupIdCleared,
              selectedPayerId: selectedPayerId,
              onPayerChanged: onPayerChanged,
            ),
          ],
        ),
      ),
    );
  }

  int get _splitCount {
    return switch (scope) {
      ExpenseScope.personal => 1,
      ExpenseScope.custom => customSplitParticipants.length + 1,
      _ => event.participantIds.length,
    };
  }

  String _scopeLabel(ExpenseScope scope) {
    return switch (scope) {
      ExpenseScope.global => 'Equally',
      ExpenseScope.subGroup => 'Group split',
      ExpenseScope.custom => 'Custom',
      ExpenseScope.personal => 'Personal',
    };
  }
}

class _WhereCard extends StatelessWidget {
  const _WhereCard({required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final date = event.startDate ?? event.createdAt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _CardShell(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _InfoRow(title: 'Event', trailingText: event.name, dense: true),
            Divider(height: 1, color: context.colors.rule),
            _InfoRow(
              title: 'Date',
              trailingText: AppFormatters.formatShortMonthDay(date),
              dense: true,
            ),
            Divider(height: 1, color: context.colors.rule),
            const _InfoRow(
              title: 'Note',
              trailingText: 'Use description field',
              dense: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
        boxShadow: context.shadows.raised,
      ),
      padding: padding,
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.trailingText,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final String? trailingText;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 12 : 14),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTypography.sans(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (trailingText != null)
            Flexible(
              child: Text(
                trailingText!,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.sans(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: context.colors.saffronTint,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: AppTypography.sans(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: context.colors.primaryDark,
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
      ),
      child: Row(
        children: [
          Icon(Iconsax.warning_2, color: context.colors.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: context.colors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

Color _categoryColor(BuildContext context, String name) {
  final colors = context.colors;
  final normalized = name.toLowerCase();
  if (normalized.contains('food')) return colors.cat1;
  if (normalized.contains('lodg') || normalized.contains('hotel')) {
    return colors.cat2;
  }
  if (normalized.contains('trans') || normalized.contains('taxi')) {
    return colors.cat3;
  }
  if (normalized.contains('grocer')) return colors.cat4;
  if (normalized.contains('activ')) return colors.cat5;
  return colors.cat6;
}
