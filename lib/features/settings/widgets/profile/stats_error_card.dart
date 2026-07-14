import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../keys/profile_keys.dart';
import '../../providers/profile_stats_provider.dart';

/// Compact, explicit error state for the stats grid with a retry (#488).
class StatsErrorCard extends ConsumerWidget {
  const StatsErrorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
      child: Container(
        key: ProfileKeys.statsErrorCard,
        padding: EdgeInsets.all(context.spacing.space16),
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: context.shadows.raised,
        ),
        child: Row(
          children: [
            Icon(Iconsax.warning_2, size: 18, color: colors.textSecondary),
            SizedBox(width: context.spacing.space12),
            Expanded(
              child: Text(
                context.l10n.profileStatsLoadFailed,
                style: AppTypography.sans(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(profileStatsProvider),
              child: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
