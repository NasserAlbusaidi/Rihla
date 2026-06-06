import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// Strong confirmation before in-app account deletion.
///
/// Account-recovery spec §6.2 + Play policy. Deletion is destructive and
/// irreversible — the dialog spells that out plainly before the user can
/// confirm.
class DeleteAccountDialog extends StatelessWidget {
  const DeleteAccountDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const DeleteAccountDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return AlertDialog(
      backgroundColor: colors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.spacing.radiusCard)),
      title: Text(
        l10n.deleteAccountTitle,
        style: AppTypography.sans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
      ),
      content: Text(
        l10n.deleteAccountContent,
        style: AppTypography.sans(
          fontSize: 14,
          color: colors.textSecondary,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          key: const Key('deleteAccount.cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('deleteAccount.confirm'),
          style: FilledButton.styleFrom(backgroundColor: colors.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.deleteAccountConfirm),
        ),
      ],
    );
  }
}
