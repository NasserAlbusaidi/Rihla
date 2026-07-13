import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/utils/a11y_announce.dart';
import '../../../core/utils/bidi.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/localized_decimal_input.dart';
import '../../../core/utils/localized_name_validators.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_avatar.dart';
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
  // #1168: payer userId — keys the payee card's avatar on stable identity
  // instead of the display name. Optional so existing/unwired callers still
  // fall back to hashing fromName.
  String? fromUserId,
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
      fromUserId: fromUserId,
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
    this.fromUserId,
    required this.suggestedAmount,
    this.perspective = RecordPaymentPerspective.paying,
    this.stepLabel,
  });

  final String currency;
  final String fromName;
  final String toName;
  final String? fromUserId;
  final Decimal suggestedAmount;
  final RecordPaymentPerspective perspective;
  final String? stepLabel;

  @override
  State<_MarkPaidSheet> createState() => _MarkPaidSheetState();
}

class _MarkPaidSheetState extends State<_MarkPaidSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  final FocusNode _amountFocusNode = FocusNode();
  bool _showAmountEditor = false;

  /// #1080: set when confirm is tapped with an unparseable or non-positive
  /// amount. Blocks the pop and drives the persistent inline error on the
  /// amount field; cleared on the next amount edit.
  String? _amountError;

  /// The controller also notifies on selection-only changes (e.g. the
  /// focus-attach after an invalid confirm), which must NOT clear the error —
  /// only a real text edit does. Tracks the last seen text to tell them apart.
  late String _lastAmountText;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.suggestedAmount.toStringAsFixed(
        AppFormatters.currencyConfig[widget.currency]?.decimals ?? 2,
      ),
    );
    _lastAmountText = _amountController.text;
    // #587: recompute the partial/full copy + remaining-after hint as the
    // amount changes.
    _amountController.addListener(_onAmountChanged);
    _noteController = TextEditingController();
    _noteController.addListener(_onNoteChanged);
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _noteController.removeListener(_onNoteChanged);
    _amountController.dispose();
    _noteController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  // Recompute the inline note error as the user types (#220).
  void _onNoteChanged() => setState(() {});

  // #587: recompute partial/full copy as the amount is edited.
  // #1080: a real text edit also clears the inline validation error.
  void _onAmountChanged() {
    final textChanged = _amountController.text != _lastAmountText;
    _lastAmountText = _amountController.text;
    setState(() {
      if (textChanged) _amountError = null;
    });
  }

  /// #1080: validate BEFORE the pop so an invalid amount keeps the sheet open
  /// with a persistent field-associated error (+ focus + announcement) instead
  /// of dismissing and flashing a transient snackbar on the host screen. An
  /// empty field stays legal — the callers treat it as "settle the full
  /// suggested amount". The over-pay cap and #719/#773 revalidation remain the
  /// callers' post-pop checks (they need live balance data).
  void _handleConfirm() {
    final text = _amountController.text.trim();
    final parsed = Decimal.tryParse(normalizeLocalizedDecimalInput(text));
    final String? error;
    if (parsed == null && text.isNotEmpty) {
      error = context.l10n.settleUpEnterValidAmount;
    } else if (parsed != null && parsed <= Decimal.zero) {
      error = context.l10n.settleUpAmountGreaterThanZero;
    } else {
      error = null;
    }
    if (error != null) {
      setState(() {
        _amountError = error;
        _showAmountEditor = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _amountFocusNode.requestFocus();
      });
      announceValidationError(context, error);
      return;
    }
    HapticService.medium();
    Navigator.pop(
      context,
      RecordPaymentResult(amount: text, note: _noteController.text.trim()),
    );
  }

  // #282/#595: title / banner / button copy reframe per the writer's
  // relationship to the transfer. The persisted settlement is identical in
  // every case (fromName=payer → toName=recipient).
  String _titleText(BuildContext context, bool isPartial) {
    // #587: a partial payment uses a single neutral title across all
    // perspectives — the banner still carries who-paid-whom framing.
    if (isPartial) return context.l10n.settleUpRecordPartialTitle;
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
        return context.l10n.settleUpRecordsReceivedImmediately(
          bidiIsolate(widget.fromName),
        );
      case RecordPaymentPerspective.recording:
        return context.l10n.settleUpRecordsForOthersImmediately(
          bidiIsolate(widget.fromName),
          bidiIsolate(widget.toName),
        );
      case RecordPaymentPerspective.paying:
        return context.l10n.settleUpRecordsImmediately(
          bidiIsolate(widget.toName),
        );
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

    // #587: detect a partial payment (edited strictly below the outstanding the
    // sheet presents) using the SAME parse the callers use, so the copy can
    // never disagree with the amount that gets recorded. Empty / zero / garbage
    // / full / over-pay all fall to full copy — matching the caller's
    // `?? suggestedAmount` fallback and the over-pay cap.
    final edited = Decimal.tryParse(
      normalizeLocalizedDecimalInput(_amountController.text),
    );
    final remaining =
        (edited != null &&
            edited > Decimal.zero &&
            edited < widget.suggestedAmount)
        ? widget.suggestedAmount - edited
        : null;
    final isPartial = remaining != null;

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
                      _titleText(context, isPartial),
                      textAlign: TextAlign.center,
                      key: GroupKeys.settleUpRecordSheetTitle,
                      style: AppTypography.displayOf(
                        context,
                        fontSize: 28,
                        color: colors.textPrimary,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isPartial
                          ? context.l10n.settleUpRecordPartialBody(
                              bidiIsolate(widget.fromName),
                              bidiIsolate(widget.toName),
                            )
                          : context.l10n.settleUpMarkThisPaidBody(
                              bidiIsolate(widget.fromName),
                              bidiIsolate(widget.toName),
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
                  fromUserId: widget.fromUserId,
                  suggestedAmount: widget.suggestedAmount,
                  showEditor: _showAmountEditor,
                  amountController: _amountController,
                  amountFocusNode: _amountFocusNode,
                  errorText: _amountError,
                  onToggleEditor: () =>
                      setState(() => _showAmountEditor = !_showAmountEditor),
                ),
              ),
              // #587: live remaining-after hint on a partial — what stays owed
              // once this smaller settlement is recorded (outstanding − edited,
              // same currency, per-currency decimals incl. JPY×1).
              if (remaining != null) ...[
                SizedBox(height: spacing.space8),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      context.l10n.settleUpRemainingAfter(
                        bidiIsolate(widget.fromName),
                        bidiIsolate(widget.toName),
                        AppFormatters.formatCurrency(
                          remaining,
                          widget.currency,
                        ),
                      ),
                      key: GroupKeys.settleUpRemainingAfter,
                      style: AppTypography.sans(
                        fontSize: 12,
                        color: colors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ],
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
                          onPressed: _handleConfirm,
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
    this.fromUserId,
    required this.suggestedAmount,
    required this.showEditor,
    required this.amountController,
    required this.amountFocusNode,
    required this.errorText,
    required this.onToggleEditor,
  });

  final String currency;
  final String fromName;
  final String toName;

  /// Payer userId (#1168) — keys the avatar's palette slot on stable
  /// identity instead of the display name.
  final String? fromUserId;
  final Decimal suggestedAmount;
  final bool showEditor;
  final TextEditingController amountController;
  final FocusNode amountFocusNode;
  final String? errorText;
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
              RAvatar(name: fromName, size: 42, colorKey: fromUserId),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.settleUpPays(
                        bidiIsolate(fromName),
                        bidiIsolate(toName),
                      ),
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
              focusNode: amountFocusNode,
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
                errorText: errorText,
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
