import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// The user's choice from the [DurableShellDeleteDialog].
enum DurableShellDeleteChoice { signIn, deleteGuest, cancel }

/// #469 prevention — shown when an ANONYMOUS session taps Delete but a durable
/// account was established on this device (the `auth.durableAccountEstablished`
/// marker).
///
/// Deleting the anon shell would silently leave the durable account + its data
/// intact under a different uid. #546 already disclosed this; the prevention
/// steers the user away from the footgun: the primary action is to sign in to
/// the saved account first (the account options live on the same screen), with
/// an explicit, clearly-labelled escape to delete only the guest session. No
/// silent wrong-delete, and never a dead-end (the link affordance is always
/// rendered for an anon session).
class DurableShellDeleteDialog extends StatelessWidget {
  const DurableShellDeleteDialog({super.key});

  static Future<DurableShellDeleteChoice?> show(BuildContext context) {
    return showDialog<DurableShellDeleteChoice>(
      context: context,
      builder: (_) => const DurableShellDeleteDialog(),
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
        l10n.durableShellDeleteTitle,
        style: AppTypography.sans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
      ),
      content: Text(
        l10n.durableShellDeleteContent,
        style: AppTypography.sans(
          fontSize: 14,
          color: colors.textSecondary,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          key: const Key('durableShellDelete.cancel'),
          onPressed: () =>
              Navigator.of(context).pop(DurableShellDeleteChoice.cancel),
          child: Text(l10n.durableShellDeleteCancel),
        ),
        TextButton(
          key: const Key('durableShellDelete.deleteGuest'),
          style: TextButton.styleFrom(foregroundColor: colors.error),
          onPressed: () =>
              Navigator.of(context).pop(DurableShellDeleteChoice.deleteGuest),
          child: Text(l10n.durableShellDeleteGuest),
        ),
        FilledButton(
          key: const Key('durableShellDelete.signIn'),
          onPressed: () =>
              Navigator.of(context).pop(DurableShellDeleteChoice.signIn),
          child: Text(l10n.durableShellDeleteSignIn),
        ),
      ],
    );
  }
}
