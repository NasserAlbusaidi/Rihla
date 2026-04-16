import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';

/// Shows the "Record Payment" modal bottom sheet and returns [true] when the
/// user confirms, [null]/[false] when dismissed.
///
/// Extracted from [GroupSettleUpScreen._showRecordPaymentSheet]
/// (Phase 36 Plan 01) to reduce screen LOC.
Future<RecordPaymentResult?> showRecordPaymentSheet(
  BuildContext context, {
  required Group group,
  required String fromName,
  required String toName,
  required Decimal suggestedAmount,
}) {
  const spacing = AppSpacingTokens.standard;
  final amountController = TextEditingController(
    text: suggestedAmount.toStringAsFixed(3),
  );
  final noteController = TextEditingController();

  return showModalBottomSheet<RecordPaymentResult>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColorTokens.light.scaffoldBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColorTokens.light.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Record Payment',
              key: GroupKeys.settleUpRecordSheetTitle,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColorTokens.light.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$fromName paid ${AppFormatters.formatCurrency(suggestedAmount, group.currency)} to $toName.',
              style: TextStyle(
                fontSize: 14,
                color: AppColorTokens.light.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Amount field
            TextFormField(
              controller: amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d*\.?\d{0,3}'),
                ),
              ],
              decoration: InputDecoration(
                labelText: 'Amount (${group.currency})',
                filled: true,
                fillColor: AppColorTokens.light.inputFillWarm,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(spacing.radiusMedium),
                  borderSide: BorderSide(
                    color: AppColorTokens.light.borderWarm,
                    width: 1.5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(spacing.radiusMedium),
                  borderSide: BorderSide(
                    color: AppColorTokens.light.focusBorderWarm,
                    width: 2,
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(spacing.radiusMedium),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Note field
            TextFormField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: 'Optional note (e.g. Venmo, cash)',
                filled: true,
                fillColor: AppColorTokens.light.inputFillWarm,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(spacing.radiusMedium),
                  borderSide: BorderSide(
                    color: AppColorTokens.light.borderWarm,
                    width: 1.5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(spacing.radiusMedium),
                  borderSide: BorderSide(
                    color: AppColorTokens.light.focusBorderWarm,
                    width: 2,
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(spacing.radiusMedium),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Record Payment CTA
            SizedBox(
              width: double.infinity,
              height: spacing.buttonHeight,
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppColorTokens.light.primaryGradient,
                  borderRadius: BorderRadius.circular(spacing.radiusMedium),
                ),
                child: ElevatedButton(
                  key: GroupKeys.markAsPaidButton,
                  onPressed: () {
                    Navigator.pop(
                      sheetContext,
                      RecordPaymentResult(
                        amount: amountController.text.trim(),
                        note: noteController.text.trim(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(spacing.radiusMedium),
                    ),
                  ),
                  child: const Text(
                    'Record Payment',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: GroupKeys.notNowButton,
              onPressed: () => Navigator.pop(sheetContext),
              child: Text(
                'Not Now',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColorTokens.light.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

/// Result returned from [showRecordPaymentSheet].
class RecordPaymentResult {
  final String amount;
  final String note;

  const RecordPaymentResult({required this.amount, required this.note});
}
