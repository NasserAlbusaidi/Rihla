import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../trip/providers/trip_provider.dart';
import '../models/expense_category_model.dart';
import '../models/expense_model.dart';
import '../providers/category_provider.dart';
import 'split_scope_selector.dart';

enum ExpenseEditorMode { add, edit }

/// Snapshot of the form payload handed back to the parent on submit.
class ExpenseEditorPayload {
  final Decimal amount;
  final String? description;
  final ExpenseScope scope;
  final String? categoryId;
  final String payerParticipantId;
  final List<String>? customSplitParticipants;

  const ExpenseEditorPayload({
    required this.amount,
    required this.description,
    required this.scope,
    required this.categoryId,
    required this.payerParticipantId,
    required this.customSplitParticipants,
  });
}

/// Shared single-page expense form used by both Add and Edit screens.
///
/// Matches the `Hi_AddExpense` / `Hi_EditExpense` wireframes:
/// - Edit mode is the same form with title "Edit expense", trailing "Save",
///   and a soft delete card at the bottom.
class ExpenseEditorBody extends ConsumerStatefulWidget {
  final String groupId;
  final String eventId;
  final ExpenseEditorMode mode;

  /// Pre-fill values (edit mode only).
  final Expense? initial;

  /// Called when the user taps Add/Save with a valid payload. Should throw on
  /// failure — the body surfaces a snackbar with the error message.
  final Future<void> Function(ExpenseEditorPayload payload) onSubmit;

  /// Called when the user confirms deletion. Edit mode only.
  final Future<void> Function()? onDelete;

  const ExpenseEditorBody({
    super.key,
    required this.groupId,
    required this.eventId,
    required this.mode,
    required this.onSubmit,
    this.initial,
    this.onDelete,
  }) : assert(
         mode == ExpenseEditorMode.add || initial != null,
         'Edit mode requires an initial expense',
       );

  @override
  ConsumerState<ExpenseEditorBody> createState() => _ExpenseEditorBodyState();
}

class _ExpenseEditorBodyState extends ConsumerState<ExpenseEditorBody> {
  late final TextEditingController _noteController;
  late final TextEditingController _amountController;

  late String _amount;
  late ExpenseScope _scope;
  String? _selectedCategoryId;
  String? _selectedPayerId;
  late Set<String> _customSplitParticipants;

  bool _isSubmitting = false;

  bool get _isEdit => widget.mode == ExpenseEditorMode.edit;

  String get _tripCurrency => 'OMR';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _amount = initial.amount.toString();
      _amountController = TextEditingController(text: _amount);
      _noteController = TextEditingController(text: initial.description ?? '');
      _scope = initial.scope;
      _selectedCategoryId = initial.categoryId;
      _selectedPayerId = initial.payerParticipantId;
      _customSplitParticipants =
          initial.customSplitParticipants?.toSet() ?? <String>{};
    } else {
      _amount = '0';
      _amountController = TextEditingController(text: '0');
      _noteController = TextEditingController();
      _scope = ExpenseScope.global;
      _customSplitParticipants = <String>{};
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    Decimal amount;
    try {
      amount = Decimal.parse(_amount);
    } on FormatException {
      _showSnack('Please enter a valid amount');
      return;
    }

    if (amount <= Decimal.zero) {
      _showSnack('Amount must be greater than zero');
      return;
    }

    final currentParticipant = ref.read(
      currentEventParticipantProvider((
        groupId: widget.groupId,
        eventId: widget.eventId,
      )),
    );

    final payerId = _selectedPayerId ?? currentParticipant?.id;
    if (payerId == null) {
      _showSnack('Could not identify your participant record.');
      return;
    }

    HapticService.success();
    setState(() => _isSubmitting = true);

    try {
      final note = _noteController.text.trim();
      await widget.onSubmit(
        ExpenseEditorPayload(
          amount: amount,
          description: note.isNotEmpty ? note : null,
          scope: _scope,
          categoryId: _selectedCategoryId,
          payerParticipantId: payerId,
          customSplitParticipants: _scope == ExpenseScope.custom
              ? _customSplitParticipants.toList()
              : null,
        ),
      );
    } catch (e) {
      if (mounted) {
        final verb = _isEdit ? 'update' : 'add';
        _showSnack('Failed to $verb expense: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _confirmDelete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Iconsax.trash, color: context.colors.error),
            const SizedBox(width: 12),
            const Text('Delete expense?'),
          ],
        ),
        content: const Text(
          "Removing it updates everyone's balances for this event.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: context.colors.error)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      await onDelete();
    } catch (e) {
      if (mounted) _showSnack('Failed to delete expense: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openCustomiseSheet(Event event) async {
    HapticService.lightClick();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _SplitCustomiseSheet(
          event: event,
          initialScope: _scope,
          initialCustomSplit: _customSplitParticipants,
          initialPayerId: _selectedPayerId,
          onApply: ({
            required ExpenseScope scope,
            required Set<String> custom,
            required String? payerId,
          }) {
            setState(() {
              _scope = scope;
              _customSplitParticipants
                ..clear()
                ..addAll(custom);
              _selectedPayerId = payerId;
            });
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _ExpenseTopBar(
              title: _isEdit ? 'Edit expense' : 'Add expense',
              actionLabel: _isEdit ? 'Save' : 'Add',
              isLoading: _isSubmitting,
              onClose: () {
                HapticService.lightClick();
                context.pop();
              },
              onAction: _submit,
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
                        onAction: () => _openCustomiseSheet(event),
                        child: _SplitPreviewCard(
                          event: event,
                          amount: Decimal.tryParse(_amount) ?? Decimal.zero,
                          currency: _tripCurrency,
                          scope: _scope,
                          payerId: _selectedPayerId ?? currentParticipant?.id,
                          customSplitParticipants: _customSplitParticipants,
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
                    if (_isEdit && widget.onDelete != null)
                      _DeleteCard(
                        enabled: !_isSubmitting,
                        onDelete: _confirmDelete,
                      ),
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
    required this.title,
    required this.actionLabel,
    required this.isLoading,
    required this.onClose,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final bool isLoading;
  final VoidCallback onClose;
  final VoidCallback onAction;

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
              title,
              style: AppTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: isLoading ? null : onAction,
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
                    : Text(actionLabel),
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
    final colors = context.colors;

    // The label color is deliberately darker than textSecondary — at fontSize
    // 10 with extra letter spacing it can otherwise blend into the cream
    // background on iOS.
    final labelColor = colors.textPrimary.withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'AMOUNT · $currency',
                style: AppTypography.mono(
                  fontSize: 10,
                  letterSpacing: 1.6,
                  color: labelColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      currency,
                      style: AppTypography.mono(
                        fontSize: 20,
                        color: colors.textSecondary,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    whole,
                    style: AppTypography.mono(
                      fontSize: 64,
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                      height: 1.05,
                    ),
                  ),
                  if (fraction.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        fraction,
                        style: AppTypography.mono(
                          fontSize: 28,
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: 120,
                height: 2,
                decoration: BoxDecoration(
                  color: colors.primary,
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
                filled: false,
                fillColor: Colors.transparent,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
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
  const _Section({
    required this.title,
    required this.child,
    this.action,
    this.onAction,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
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
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onAction,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 4,
                      ),
                      child: Text(
                        action!,
                        style: AppTypography.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.colors.primaryDark,
                        ),
                      ),
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
          leading: _Avatar(name: payerName, size: 32),
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

class _SplitPreviewCard extends StatelessWidget {
  const _SplitPreviewCard({
    required this.event,
    required this.amount,
    required this.currency,
    required this.scope,
    required this.payerId,
    required this.customSplitParticipants,
  });

  final Event event;
  final Decimal amount;
  final String currency;
  final ExpenseScope scope;
  final String? payerId;
  final Set<String> customSplitParticipants;

  List<String> get _splitParticipantIds {
    switch (scope) {
      case ExpenseScope.global:
        return event.participantIds;
      case ExpenseScope.custom:
        final ids = customSplitParticipants.toList();
        if (payerId != null && !ids.contains(payerId)) ids.insert(0, payerId!);
        return ids;
      case ExpenseScope.personal:
        return payerId != null ? [payerId!] : const [];
      case ExpenseScope.subGroup:
        return event.participantIds;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = _splitParticipantIds;
    final count = ids.length;
    final each = count == 0
        ? Decimal.zero
        : (amount / Decimal.fromInt(count)).toDecimal(
            scaleOnInfinitePrecision: 3,
          );
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _CardShell(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      Text(
                        '${_scopeLabel(scope)} · $count way${count == 1 ? '' : 's'}',
                        style: AppTypography.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        '${AppFormatters.formatCurrency(each, currency)} each',
                        style: AppTypography.sans(
                          fontSize: 12,
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (scope == ExpenseScope.global)
                  Text(
                    'EVENT DEFAULT',
                    style: AppTypography.mono(
                      fontSize: 9,
                      letterSpacing: 1.6,
                      color: colors.textPrimary.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (count == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Tap Customise to pick who splits this.',
                  style: AppTypography.sans(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              )
            else
              SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: ids.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final id = ids[index];
                    final name =
                        event.participantNames[id] ?? 'Member';
                    final firstName = name.split(' ').first;
                    return _ParticipantSplitTile(
                      name: name,
                      firstName: firstName,
                      share: each,
                      currency: currency,
                      isPayer: id == payerId,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
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

class _ParticipantSplitTile extends StatelessWidget {
  const _ParticipantSplitTile({
    required this.name,
    required this.firstName,
    required this.share,
    required this.currency,
    required this.isPayer,
  });

  final String name;
  final String firstName;
  final Decimal share;
  final String currency;
  final bool isPayer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 78,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: colors.cardSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPayer
              ? colors.primary.withValues(alpha: 0.55)
              : colors.rule,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Avatar(name: name, size: 28),
          Text(
            firstName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.sans(
              fontSize: 11,
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            AppFormatters.formatCurrency(share, currency),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.mono(
              fontSize: 11,
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
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
        child: Column(
          children: [
            _InfoRow(title: 'Event', trailingText: event.name, dense: true),
            _InfoRow(
              title: 'Date',
              trailingText: AppFormatters.formatShortMonthDay(date),
              dense: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteCard extends StatelessWidget {
  const _DeleteCard({required this.enabled, required this.onDelete});

  final bool enabled;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
          border: Border.all(color: colors.error.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delete this expense',
                    style: AppTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Removes for everyone in this event.',
                    style: AppTypography.sans(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: enabled ? onDelete : null,
              icon: const Icon(Iconsax.trash, size: 14),
              label: const Text('Delete'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    context.spacing.radiusSmall,
                  ),
                ),
                textStyle: AppTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
  const _Avatar({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.colors.saffronTint,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: AppTypography.sans(
            fontSize: size * 0.38,
            fontWeight: FontWeight.w800,
            color: context.colors.primaryDark,
          ),
        ),
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

// ──────────────────────────────────────────────────────────── Customise sheet

typedef _SplitApply =
    void Function({
      required ExpenseScope scope,
      required Set<String> custom,
      required String? payerId,
    });

class _SplitCustomiseSheet extends StatefulWidget {
  const _SplitCustomiseSheet({
    required this.event,
    required this.initialScope,
    required this.initialCustomSplit,
    required this.initialPayerId,
    required this.onApply,
  });

  final Event event;
  final ExpenseScope initialScope;
  final Set<String> initialCustomSplit;
  final String? initialPayerId;
  final _SplitApply onApply;

  @override
  State<_SplitCustomiseSheet> createState() => _SplitCustomiseSheetState();
}

class _SplitCustomiseSheetState extends State<_SplitCustomiseSheet> {
  late ExpenseScope _scope;
  late Set<String> _custom;
  String? _payerId;

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope == ExpenseScope.subGroup
        ? ExpenseScope.global
        : widget.initialScope;
    _custom = Set<String>.from(widget.initialCustomSplit);
    _payerId = widget.initialPayerId;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.scaffoldBackground,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Customise split',
                        style: AppTypography.sans(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: () {
                        widget.onApply(
                          scope: _scope,
                          custom: _custom,
                          payerId: _payerId,
                        );
                        Navigator.of(context).pop();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.textOnPrimary,
                        minimumSize: const Size(64, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            context.spacing.radiusSmall,
                          ),
                        ),
                      ),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: SplitScopeSelector(
                    event: widget.event,
                    scope: _scope,
                    onScopeChanged: (s) => setState(() => _scope = s),
                    customSplitParticipants: _custom,
                    onCustomSplitChanged: (s) => setState(() {
                      _custom = s;
                    }),
                    selectedPayerId: _payerId,
                    onPayerChanged: (id) => setState(() => _payerId = id),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
