import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// Spec §4.8 / FR-OUT-2.
///
/// Confirms the user actually wants to sign out before we drop the local
/// session. Copy emphasizes that data is preserved in the cloud and
/// recoverable via the same email — the operation is reversible.
class SignOutConfirmDialog extends StatelessWidget {
  const SignOutConfirmDialog({super.key, required this.email});
  final String email;

  static Future<bool?> show(BuildContext context, {required String email}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => SignOutConfirmDialog(email: email),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return AlertDialog(
      backgroundColor: colors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        l10n.signOutTitle,
        style: AppTypography.sans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
      ),
      content: Text.rich(
        TextSpan(
          style: AppTypography.sans(
            fontSize: 14,
            color: colors.textSecondary,
            height: 1.4,
          ),
          children: [
            TextSpan(text: l10n.signOutContentPrefix),
            TextSpan(
              text: email,
              style: AppTypography.sans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            TextSpan(text: l10n.signOutContentSuffix),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('signOutConfirm.cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('signOutConfirm.confirm'),
          style: FilledButton.styleFrom(backgroundColor: colors.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.signOutConfirm),
        ),
      ],
    );
  }
}
