import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../keys/profile_keys.dart';

/// Hero pill that states whether the account is backed up (#487): sage when
/// durable (Google/email linked), amber when still anonymous.
class BackupStatusChip extends StatelessWidget {
  const BackupStatusChip({super.key, required this.isDurable});
  final bool isDurable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final accent = isDurable ? colors.success : colors.warning;
    return Container(
      key: ProfileKeys.backupStatusChip,
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.space12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.spacing.radiusPill),
        border: Border.all(color: accent.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDurable ? Iconsax.shield_tick : Iconsax.warning_2,
            size: 13,
            color: accent,
          ),
          SizedBox(width: context.spacing.space4),
          Text(
            isDurable
                ? l10n.profileBackupStatusBackedUp
                : l10n.profileBackupStatusNotBackedUp,
            style: AppTypography.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}
