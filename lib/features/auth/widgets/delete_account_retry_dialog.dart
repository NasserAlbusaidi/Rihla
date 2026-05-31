import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// Re-prompt shown when account deletion completed only partially (#77).
///
/// The server scrubbed some data but threw before finishing; the cascade is
/// idempotent and convergent, so the session stays valid and a retry will
/// finish the job. A durable dialog (not a transient snack) gives the user a
/// guaranteed way to retry. Returns `true` to retry, `false`/`null` to dismiss.
class DeleteAccountRetryDialog extends StatelessWidget {
  const DeleteAccountRetryDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const DeleteAccountRetryDialog(),
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
        l10n.deleteAccountRetryTitle,
        style: AppTypography.sans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
      ),
      content: Text(
        l10n.deleteAccountRetryContent,
        style: AppTypography.sans(
          fontSize: 14,
          color: colors.textSecondary,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          key: const Key('deleteAccount.partialDismiss'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('deleteAccount.partialRetry'),
          style: FilledButton.styleFrom(backgroundColor: colors.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.commonRetry),
        ),
      ],
    );
  }
}
