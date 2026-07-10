import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// Spec §4.8 / FR-OUT-2.
///
/// Confirms the user actually wants to sign out before we drop the local
/// session. Copy emphasizes that data is preserved in the cloud and
/// recoverable — via the linked email when one exists, otherwise via the
/// same Google account (#428: a Google-credentialed user may have no
/// linked email; the email-link instruction would be wrong advice).
class SignOutConfirmDialog extends StatelessWidget {
  const SignOutConfirmDialog({super.key, this.email});
  final String? email;

  static Future<bool?> show(BuildContext context, {String? email}) {
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.spacing.radiusCard),
      ),
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
          children: switch (email) {
            null || '' => [TextSpan(text: l10n.signOutContentGoogle)],
            final linked => [
              TextSpan(text: l10n.signOutContentPrefix),
              TextSpan(
                text: linked,
                style: AppTypography.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              TextSpan(text: l10n.signOutContentSuffix),
            ],
          },
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

class SignOutPendingWritesDialog extends StatelessWidget {
  const SignOutPendingWritesDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const SignOutPendingWritesDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return AlertDialog(
      backgroundColor: colors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.spacing.radiusCard),
      ),
      title: Text(
        l10n.signOutPendingWritesTitle,
        style: AppTypography.sans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
      ),
      content: Text(
        l10n.signOutPendingWritesBody,
        style: AppTypography.sans(
          fontSize: 14,
          color: colors.textSecondary,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          key: const Key('signOutPendingWrites.cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.signOutPendingWritesKeep),
        ),
        FilledButton(
          key: const Key('signOutPendingWrites.discard'),
          style: FilledButton.styleFrom(backgroundColor: colors.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.signOutPendingWritesDiscard),
        ),
      ],
    );
  }
}
