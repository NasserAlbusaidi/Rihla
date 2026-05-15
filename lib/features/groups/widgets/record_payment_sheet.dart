import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/r_amount.dart';
import '../keys/group_keys.dart';

/// Bottom-sheet "Mark paid" confirmation aligned with Hi_Sheet_MarkPaid
/// (tier 6 · sheets & pickers).
///
/// Shows a sage check badge, italic display title, payee card with the
/// suggested amount, method chips (Cash / Bank transfer / Other), and a
/// saffron-tinted notification banner. Returns a [RecordPaymentResult] on
/// confirm; null on dismiss.
Future<RecordPaymentResult?> showRecordPaymentSheet(
  BuildContext context, {
  required String currency,
  required String fromName,
  required String toName,
  required Decimal suggestedAmount,
}) {
  return showModalBottomSheet<RecordPaymentResult>(
    context: context,
    backgroundColor: context.colors.scaffoldBackground,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _MarkPaidSheet(
      currency: currency,
      fromName: fromName,
      toName: toName,
      suggestedAmount: suggestedAmount,
    ),
  );
}

class _MarkPaidSheet extends StatefulWidget {
  const _MarkPaidSheet({
    required this.currency,
    required this.fromName,
    required this.toName,
    required this.suggestedAmount,
  });

  final String currency;
  final String fromName;
  final String toName;
  final Decimal suggestedAmount;

  @override
  State<_MarkPaidSheet> createState() => _MarkPaidSheetState();
}

class _MarkPaidSheetState extends State<_MarkPaidSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  PaymentMethod _method = PaymentMethod.cash;
  bool _showAmountEditor = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.suggestedAmount.toStringAsFixed(
        widget.currency == 'OMR' ? 3 : 2,
      ),
    );
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final sageSoft = Color.alphaBlend(
      colors.success.withValues(alpha: 0.18),
      colors.cardSurface,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: spacing.space12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.rule2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: spacing.space12),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: sageSoft,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.check_rounded,
                        size: 28,
                        color: colors.success,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Mark this paid?',
                      textAlign: TextAlign.center,
                      key: GroupKeys.settleUpRecordSheetTitle,
                      style: AppTypography.display(
                        fontSize: 28,
                        color: colors.textPrimary,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "We'll close out the balance between "
                      '${widget.fromName} and ${widget.toName}.',
                      textAlign: TextAlign.center,
                      style: AppTypography.sans(
                        fontSize: 13,
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.space20),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                child: _PayeeCard(
                  currency: widget.currency,
                  fromName: widget.fromName,
                  toName: widget.toName,
                  suggestedAmount: widget.suggestedAmount,
                  showEditor: _showAmountEditor,
                  amountController: _amountController,
                  onToggleEditor: () =>
                      setState(() => _showAmountEditor = !_showAmountEditor),
                ),
              ),
              SizedBox(height: spacing.space16),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                child: Row(
                  children: [
                    for (final m in PaymentMethod.values) ...[
                      _MethodChip(
                        method: m,
                        active: _method == m,
                        onTap: () {
                          HapticService.selection();
                          setState(() => _method = m);
                        },
                      ),
                      if (m != PaymentMethod.values.last)
                        const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              SizedBox(height: spacing.space12),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                child: TextField(
                  controller: _noteController,
                  style: AppTypography.sans(
                    fontSize: 13,
                    color: colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Add a note (optional)',
                    isDense: true,
                    filled: true,
                    fillColor: colors.inputFillWarm,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.borderWarm),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.borderWarm),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: colors.focusBorderWarm,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: spacing.space12),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colors.saffronTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.notifications_active_outlined,
                        size: 16,
                        color: colors.primaryDark,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${widget.toName} will be notified to confirm.',
                          style: AppTypography.sans(
                            fontSize: 12,
                            color: colors.primaryDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: spacing.space20),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  spacing.space24,
                  0,
                  spacing.space24,
                  spacing.space20,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          key: GroupKeys.notNowButton,
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.rule2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Not yet',
                            style: AppTypography.sans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          key: GroupKeys.markAsPaidButton,
                          onPressed: () {
                            HapticService.medium();
                            Navigator.pop(
                              context,
                              RecordPaymentResult(
                                amount: _amountController.text.trim(),
                                note: _noteController.text.trim(),
                                method: _method,
                              ),
                            );
                          },
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: Text(
                            'Mark paid',
                            style: AppTypography.sans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: colors.textOnPrimary,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.primary,
                            foregroundColor: colors.textOnPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayeeCard extends StatelessWidget {
  const _PayeeCard({
    required this.currency,
    required this.fromName,
    required this.toName,
    required this.suggestedAmount,
    required this.showEditor,
    required this.amountController,
    required this.onToggleEditor,
  });

  final String currency;
  final String fromName;
  final String toName;
  final Decimal suggestedAmount;
  final bool showEditor;
  final TextEditingController amountController;
  final VoidCallback onToggleEditor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
        boxShadow: context.shadows.raised,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.selectionFill,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  fromName.isNotEmpty ? fromName[0].toUpperCase() : '·',
                  style: AppTypography.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$fromName pays $toName',
                      style: AppTypography.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: onToggleEditor,
                      child: Text(
                        showEditor
                            ? 'Hide amount editor'
                            : 'Tap to edit amount',
                        style: AppTypography.sans(
                          fontSize: 12,
                          color: colors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              RAmount(
                value: suggestedAmount,
                currency: currency,
                size: 20,
                tone: AmountTone.sage,
              ),
            ],
          ),
          if (showEditor) ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
              ],
              style: AppTypography.mono(
                fontSize: 15,
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                labelText: 'Amount ($currency)',
                filled: true,
                fillColor: colors.inputFillWarm,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.borderWarm),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.borderWarm),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colors.focusBorderWarm,
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Suggested: ${AppFormatters.formatCurrency(suggestedAmount, currency)}',
                style: AppTypography.sans(
                  fontSize: 11,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({
    required this.method,
    required this.active,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? colors.cardSurface : colors.inputFill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? colors.textPrimary : colors.rule,
              width: 0.5,
            ),
            boxShadow: active ? context.shadows.raised : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (active) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  method.label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active ? colors.textPrimary : colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Payment methods surfaced on the Mark Paid sheet.
enum PaymentMethod {
  cash('Cash'),
  bank('Bank'),
  other('Other');

  const PaymentMethod(this.label);
  final String label;
}

/// Result returned from [showRecordPaymentSheet].
class RecordPaymentResult {
  const RecordPaymentResult({
    required this.amount,
    required this.note,
    this.method = PaymentMethod.cash,
  });

  final String amount;
  final String note;
  final PaymentMethod method;
}
