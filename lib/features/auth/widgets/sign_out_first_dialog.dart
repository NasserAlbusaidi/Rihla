import 'package:flutter/material.dart';

import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// Spec §4.3 / FR-REC-2.
///
/// Shown when the user attempts recovery on a device that already has a
/// populated session. Two outcomes: confirm sign-out (orphans the local
/// anon UID's data, just like clearing app data does today) or cancel.
class SignOutFirstDialog extends StatelessWidget {
  const SignOutFirstDialog({super.key});

  /// Returns `true` if the user confirmed sign-out, `false` or `null`
  /// otherwise.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const SignOutFirstDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'This device is already in use',
        style: AppTypography.sans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
      ),
      content: Text(
        "To restore a different account, you'll lose the trips and "
        "expenses on this device. They'll stay in the cloud only if "
        "they're tied to a different linked email — otherwise they'll be "
        'orphaned.',
        style: AppTypography.sans(
          fontSize: 14,
          color: colors.textSecondary,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          key: const Key('signOutFirst.cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('signOutFirst.confirm'),
          style: FilledButton.styleFrom(backgroundColor: colors.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sign out and continue'),
        ),
      ],
    );
  }
}
