import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../keys/group_keys.dart';

/// #367 — post-record WhatsApp notify nudge. Shown ONLY to the debtor after a
/// settlement they made is recorded (the caller gates on perspective + path).
///
/// Pure presentation: it previews the exact prefilled [message] and returns
/// `true` when the user taps WhatsApp, `false` on dismiss / Not now. The caller
/// owns the [shareViaWhatsApp] handoff — keeping `url_launcher` out of the
/// widget makes the launch independently testable and this sheet a plain bool
/// collector. The settlement is already recorded; this is pure courtesy.
Future<bool> showSettleNotifySheet(
  BuildContext context, {
  required String recipientName,
  required String message,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: context.colors.scaffoldBackground,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) =>
        _SettleNotifySheet(recipientName: recipientName, message: message),
  );
  return result ?? false;
}

class _SettleNotifySheet extends StatelessWidget {
  const _SettleNotifySheet({required this.recipientName, required this.message});

  final String recipientName;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final sageSoft = Color.alphaBlend(
      colors.success.withValues(alpha: 0.18),
      colors.cardSurface,
    );

    return Padding(
      key: GroupKeys.settleNotifySheet,
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
              SizedBox(height: spacing.space16),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: sageSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.check_rounded,
                  size: 26,
                  color: colors.success,
                ),
              ),
              SizedBox(height: spacing.space12),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                child: Column(
                  children: [
                    Text(
                      context.l10n.settleNotifySheetTitle(recipientName),
                      textAlign: TextAlign.center,
                      style: AppTypography.display(
                        fontSize: 24,
                        color: colors.textPrimary,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.l10n.settleNotifySheetBody,
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
              // Message label + preview of the exact prefilled text.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    context.l10n.settleNotifyMessageLabel.toUpperCase(),
                    style: AppTypography.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
              SizedBox(height: spacing.space8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                child: Container(
                  key: GroupKeys.settleNotifyMessagePreview,
                  width: double.infinity,
                  padding: EdgeInsets.all(spacing.space16),
                  decoration: BoxDecoration(
                    color: colors.inputFillWarm,
                    borderRadius: const BorderRadiusDirectional.only(
                      topStart: Radius.circular(12),
                      topEnd: Radius.circular(12),
                      bottomStart: Radius.circular(4),
                      bottomEnd: Radius.circular(12),
                    ),
                    border: Border.all(color: colors.borderWarm),
                  ),
                  child: Text(
                    message,
                    style: AppTypography.sans(
                      fontSize: 13,
                      color: colors.textPrimary,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
              SizedBox(height: spacing.space8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    context.l10n.settleNotifyPickChat,
                    style: AppTypography.sans(
                      fontSize: 11,
                      color: colors.textSecondary,
                      height: 1.3,
                    ),
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
                          key: GroupKeys.settleNotifyNotNowButton,
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.rule2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            context.l10n.settleNotifyNotNow,
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
                          key: GroupKeys.settleNotifyWhatsAppButton,
                          onPressed: () {
                            HapticService.medium();
                            Navigator.pop(context, true);
                          },
                          icon: const Icon(Iconsax.message, size: 16),
                          label: Text(
                            context.l10n.settleNotifyWhatsApp,
                            style: AppTypography.sans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            // design-token-justified: WhatsApp brand green is a
                            // third-party constant, not a Rihla palette color —
                            // the recognizable CTA for the #367 handoff.
                            backgroundColor: const Color(0xFF25D366),
                            foregroundColor: Colors.white,
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
