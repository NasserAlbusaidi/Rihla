import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../models/group_model.dart';
import '../providers/group_balance_provider.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

/// A card widget for displaying a group summary in the home screen list.
///
/// Shows the group name, member count badge, and the current user's personal
/// net balance in this group (D-08/D-09). Uses [AppColorTokens.light.errorText] for
/// negative (owes), [AppColorTokens.light.successText] for positive (owed), and
/// [AppColorTokens.light.textSecondary] for zero (settled).
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
    final uid = ref.watch(currentUserIdProvider);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColorTokens.light.cardSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadowTokens.standard.raised,
        ),
        padding: const EdgeInsets.all(16),
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
                const SizedBox(width: 8),
                // Member count badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColorTokens.light.inputFill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Iconsax.people,
                        size: 14,
                        color: AppColorTokens.light.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${group.memberIds.length}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColorTokens.light.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Personal balance for current user (D-08/D-09)
            balancesAsync.when(
              data: (balances) {
                final userBalance = balances.balances
                    .where((b) => b.participantId == uid)
                    .firstOrNull;
                final net = userBalance?.netBalance ?? Decimal.zero;
                final (String label, Color color) =
                    switch (net.compareTo(Decimal.zero)) {
                  < 0 => (
                      'You owe OMR ${net.abs().toStringAsFixed(3)}',
                      AppColorTokens.light.errorText,
                    ),
                  > 0 => (
                      'You are owed OMR ${net.toStringAsFixed(3)}',
                      AppColorTokens.light.successText,
                    ),
                  _ => ('Settled', AppColorTokens.light.textSecondary),
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
                      color: AppColorTokens.light.textMuted,
                    ),
              ),
              error: (e, _) => Text(
                'Settled',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColorTokens.light.textSecondary,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
