import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/localized_decimal_input.dart';
import '../../../core/utils/localized_name_validators.dart';
import '../../../shared/widgets/r_amount.dart';
import '../keys/group_keys.dart';

/// Who the current user is relative to the transfer being recorded — drives the
/// sheet copy only (the persisted settlement is identical in every case:
/// fromName=payer → toName=recipient). (#282, #595)
enum RecordPaymentPerspective {
  /// Current user is the payer (debtor) confirming a payment they made.
  paying,

  /// Current user is the recipient (creditor) logging a payment they received.
  receiving,

  /// Current user is neither party — an organizer/member recording a payment
  /// between two other people on the group's behalf (#595).
  recording,
}

/// Bottom-sheet "Mark paid" confirmation aligned with Hi_Sheet_MarkPaid
/// (tier 6 · sheets & pickers).
///
/// Shows a sage check badge, italic display title, payee card with the
/// suggested amount, and a saffron-tinted banner noting that recording is
/// immediate (no confirmation step — #281). Returns a [RecordPaymentResult]
/// on confirm; null on dismiss.
Future<RecordPaymentResult?> showRecordPaymentSheet(
  BuildContext context, {
  required String currency,
  required String fromName,
  required String toName,
  required Decimal suggestedAmount,
  // #282/#595: framing only — the write is identical (fromName=payer →
  // toName=recipient); only the copy reframes per the writer's relationship to
  // the transfer.
  RecordPaymentPerspective perspective = RecordPaymentPerspective.paying,
  // #382 PR-5: pre-formatted "k of N" overline shown above the title during a
  // stepped multi-currency walk; null on the single-tile path.
  String? stepLabel,
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
      perspective: perspective,
      stepLabel: stepLabel,
    ),
  );
}

class _MarkPaidSheet extends StatefulWidget {
  const _MarkPaidSheet({
    required this.currency,
    required this.fromName,
    required this.toName,
    required this.suggestedAmount,
    this.perspective = RecordPaymentPerspective.paying,
    this.stepLabel,
  });

  final String currency;
  final String fromName;
  final String toName;
  final Decimal suggestedAmount;
  final RecordPaymentPerspective perspective;
  final String? stepLabel;

  @override
  State<_MarkPaidSheet> createState() => _MarkPaidSheetState();
}

class _MarkPaidSheetState extends State<_MarkPaidSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  bool _showAmountEditor = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.suggestedAmount.toStringAsFixed(
        AppFormatters.currencyConfig[widget.currency]?.decimals ?? 2,
      ),
    );
    _noteController = TextEditingController();
    _noteController.addListener(_onNoteChanged);
  }

  @override
  void dispose() {
    _noteController.removeListener(_onNoteChanged);
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // Recompute the inline note error as the user types (#220).
  void _onNoteChanged() => setState(() {});

  // #282/#595: title / banner / button copy reframe per the writer's
  // relationship to the transfer. The persisted settlement is identical in
  // every case (fromName=payer → toName=recipient).
  String _titleText(BuildContext context) {
    switch (widget.perspective) {
      case RecordPaymentPerspective.receiving:
        return context.l10n.settleUpMarkThisReceivedTitle;
      case RecordPaymentPerspective.recording:
        return context.l10n.settleUpRecordThisTitle;
      case RecordPaymentPerspective.paying:
        return context.l10n.settleUpMarkThisPaidTitle;
    }
  }

  String _bannerText(BuildContext context) {
    switch (widget.perspective) {
      case RecordPaymentPerspective.receiving:
        return context.l10n.settleUpRecordsReceivedImmediately(widget.fromName);
      case RecordPaymentPerspective.recording:
        return context.l10n.settleUpRecordsForOthersImmediately(
          widget.fromName,
          widget.toName,
        );
      case RecordPaymentPerspective.paying:
        return context.l10n.settleUpRecordsImmediately(widget.toName);
    }
  }

  String _buttonLabel(BuildContext context) {
    switch (widget.perspective) {
      case RecordPaymentPerspective.receiving:
        return context.l10n.settleUpMarkReceived;
      case RecordPaymentPerspective.recording:
        return context.l10n.settleUpRecordPayment;
      case RecordPaymentPerspective.paying:
        return context.l10n.settleUpMarkPaid;
    }
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
                    if (widget.stepLabel != null) ...[
                      Text(
                        widget.stepLabel!,
                        key: GroupKeys.settleUpRecordSheetStepIndicator,
                        textAlign: TextAlign.center,
                        style: AppTypography.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: spacing.space12),
                    ],
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
                      _titleText(context),
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
                      context.l10n.settleUpMarkThisPaidBody(
                        widget.fromName,
                        widget.toName,
                      ),
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
                    hintText: context.l10n.settleUpNoteHint,
                    errorText: validateFreeTextLocalized(
                      context,
                      _noteController.text,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: colors.inputFillWarm,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: context.spacing.space12,
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
                  padding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: context.spacing.space12,
                  ),
                  decoration: BoxDecoration(
                    color: colors.saffronTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: colors.primaryDark,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _bannerText(context),
                              style: AppTypography.sans(
                                fontSize: 12,
                                color: colors.primaryDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // #351: Rihla records, it does not move money — set
                            // the expectation so no one waits for a transfer.
                            Text(
                              context.l10n.settleUpDoesntMoveMoney,
                              style: AppTypography.sans(
                                fontSize: 11,
                                color: colors.primaryDark.withValues(
                                  alpha: 0.8,
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
                            context.l10n.settleUpNotYet,
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
                              ),
                            );
                          },
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: Text(
                            _buttonLabel(context),
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
      padding: EdgeInsets.all(context.spacing.space16),
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
                      context.l10n.settleUpPays(fromName, toName),
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
                            ? context.l10n.settleUpHideAmountEditor
                            : context.l10n.settleUpTapToEditAmount,
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
              textDirection: TextDirection.ltr,
              inputFormatters: [
                LocalizedDecimalTextInputFormatter(
                  decimalDigits:
                      AppFormatters.currencyConfig[currency]?.decimals ?? 3,
                ),
              ],
              style: AppTypography.mono(
                fontSize: 15,
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                labelText: context.l10n.settleUpAmountLabel(currency),
                filled: true,
                fillColor: colors.inputFillWarm,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: context.spacing.space12,
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
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                context.l10n.settleUpSuggestedAmount(
                  AppFormatters.formatCurrency(suggestedAmount, currency),
                ),
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

/// Result returned from [showRecordPaymentSheet].
class RecordPaymentResult {
  const RecordPaymentResult({required this.amount, required this.note});

  final String amount;
  final String note;
}
