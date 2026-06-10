import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// Merge consent for restoring an account on a populated device (#427).
///
/// Shown when the user starts recovery while this device already has groups.
/// Confirming proceeds with recovery: the server's `cleanupAnonUidArtifacts`
/// migration MERGES this device's anon-UID data into the restored account —
/// nothing is signed out or orphaned. Supersedes the FR-REC-2 sign-out-first
/// flow (see docs/plans/2026-06-10-recovery-merge-reachable-restore.md).
class MergeOnRecoverDialog extends StatelessWidget {
  const MergeOnRecoverDialog({super.key});

  /// Returns `true` if the user consented to the merge, `false` or `null`
  /// otherwise.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const MergeOnRecoverDialog(),
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
        l10n.authMergeOnRecoverTitle,
        style: AppTypography.sans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
      ),
      content: Text(
        l10n.authMergeOnRecoverBody,
        style: AppTypography.sans(
          fontSize: 14,
          color: colors.textSecondary,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          key: const Key('mergeOnRecover.cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('mergeOnRecover.confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.authMergeOnRecoverConfirm),
        ),
      ],
    );
  }
}
