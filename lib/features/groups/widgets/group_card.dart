import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../models/group_model.dart';
import '../providers/group_balance_provider.dart';

/// A card widget for displaying a group summary in the home screen list.
///
/// Shows the group name, member count badge, and the current user's personal
/// net balance in this group (D-08/D-09). Uses [AppColors.errorText] for
/// negative (owes), [AppColors.successText] for positive (owed), and
/// [AppColors.textSecondary] for zero (settled).
class GroupCard extends ConsumerWidget {
  final Group group;
  final VoidCallback onTap;

  const GroupCard({
    super.key,
    required this.group,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(groupBalancesProvider(group.id));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
          boxShadow: AppColors.shadowRaised,
        ),
        padding: const EdgeInsets.all(AppColors.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Group name
                Expanded(
                  child: Text(
                    group.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppColors.space8),
                // Member count badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppColors.space8,
                    vertical: AppColors.space4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Iconsax.people,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${group.memberIds.length}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppColors.space8),
            // Personal balance for current user (D-08/D-09)
            balancesAsync.when(
              data: (balances) {
                final uid = FirebaseConfig.currentUser?.uid;
                final userBalance = balances.balances
                    .where((b) => b.participantId == uid)
                    .firstOrNull;
                final net = userBalance?.netBalance ?? Decimal.zero;
                final (String label, Color color) =
                    switch (net.compareTo(Decimal.zero)) {
                  < 0 => (
                      'You owe OMR ${net.abs().toStringAsFixed(3)}',
                      AppColors.errorText,
                    ),
                  > 0 => (
                      'You are owed OMR ${net.toStringAsFixed(3)}',
                      AppColors.successText,
                    ),
                  _ => ('Settled', AppColors.textSecondary),
                };
                return Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: color),
                );
              },
              loading: () => Text(
                '...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                    ),
              ),
              error: (e, _) => Text(
                'Settled',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
