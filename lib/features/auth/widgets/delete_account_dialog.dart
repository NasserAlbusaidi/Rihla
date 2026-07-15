import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// Strong confirmation before in-app account deletion.
///
/// Account-recovery spec §6.2 + Play policy. Deletion is destructive and
/// irreversible — the dialog spells that out plainly before the user can
/// confirm.
///
/// #469: when the live session is an anonymous shell ([isAnonymous]) the
/// deletion only removes that guest session — any Google/email account the user
/// linked lives under a *different* UID and is untouched unless they sign in to
/// it first. The copy is identity-honest about that so a "deleted" durable
/// account can't silently survive a delete the user believed was final.
class DeleteAccountDialog extends StatelessWidget {
  const DeleteAccountDialog({super.key, this.isAnonymous = false});

  final bool isAnonymous;

  static Future<bool?> show(BuildContext context, {bool isAnonymous = false}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => DeleteAccountDialog(isAnonymous: isAnonymous),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final title =
        isAnonymous ? l10n.deleteGuestSessionTitle : l10n.deleteAccountTitle;
    // #1256 D6.4: on iOS the linkable providers include Apple, so the guest
    // copy names it; Android keeps the existing key byte-identical.
    final content = isAnonymous
        ? (defaultTargetPlatform == TargetPlatform.iOS
              ? l10n.deleteGuestSessionContentIos
              : l10n.deleteGuestSessionContent)
        : l10n.deleteAccountContent;
    final confirmLabel =
        isAnonymous ? l10n.deleteGuestSessionConfirm : l10n.deleteAccountConfirm;
    return AlertDialog(
      backgroundColor: colors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.spacing.radiusCard)),
      title: Text(
        title,
        style: AppTypography.sans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
      ),
      content: Text(
        content,
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
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
