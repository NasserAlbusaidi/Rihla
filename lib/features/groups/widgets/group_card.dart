import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/group_model.dart';
import '../providers/group_balance_provider.dart';
import '../../events/models/event_type_config.dart';
import '../../events/providers/event_provider.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// A card widget for displaying a group summary in the home screen list.
///
/// Shows the group name, member count badge, and the current user's personal
/// net balance in this group (D-08/D-09). Uses `context.colors.errorText` for
/// negative (owes), `context.colors.successText` for positive (owed), and
/// `context.colors.textSecondary` for zero (settled).
///
/// Phase 24: Adds a 4dp colored accent strip on the left edge (CARD-01) and
/// an event context line showing the most recent event (CARD-02).
class GroupCard extends ConsumerWidget {
  final Group group;
  final VoidCallback onTap;

  const GroupCard({
    super.key,
    required this.group,
    required this.onTap,
  });

  // ---------------------------------------------------------------------------
  // Accent strip — resolves theme-aware via context.colors.groupAvatarSlot.
  // 5 deterministic slots backed by AppGroupAvatarColors.{lightSlots,darkSlots}.
  // (Plan 37-04 promotion from inline palette.)
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(groupBalancesProvider(group.id));
    final uid = ref.watch(currentUserIdProvider);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: context.colors.cardSurface,
          borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
          boxShadow: context.shadows.raised,
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 4dp accent strip on the left edge (CARD-01)
              Container(
                width: 4,
                color: context.colors.groupAvatarSlot(group.id),
              ),
              // Card content
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(context.spacing.space16),
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
                          SizedBox(width: context.spacing.space8),
                          // Member count badge
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: context.spacing.space8,
                              vertical: context.spacing.space4,
                            ),
                            decoration: BoxDecoration(
                              color: context.colors.inputFill,
                              borderRadius: BorderRadius.circular(
                                context.spacing.radiusSmall,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Iconsax.people,
                                  size: 14,
                                  color: context.colors.textSecondary,
                                ),
                                SizedBox(width: context.spacing.space4),
                                Text(
                                  '${group.memberIds.length}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: context.colors.textSecondary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: context.spacing.space8),
                      // Personal balance for current user (D-08/D-09)
                      balancesAsync.when(
                        data: (balances) {
                          final userBalance = balances.balances
                              .where((b) => b.participantId == uid)
                              .firstOrNull;
                          final net =
                              userBalance?.netBalance ?? Decimal.zero;
                          final (String label, Color color) =
                              switch (net.compareTo(Decimal.zero)) {
                            < 0 => (
                                'You owe OMR ${net.abs().toStringAsFixed(3)}',
                                context.colors.errorText,
                              ),
                            > 0 => (
                                'You are owed OMR ${net.toStringAsFixed(3)}',
                                context.colors.successText,
                              ),
                            _ => (
                                'Settled',
                                context.colors.textSecondary
                              ),
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
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: context.colors.textSecondary,
                              ),
                        ),
                        error: (e, _) => Text(
                          'Settled',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: context.colors.textSecondary,
                              ),
                        ),
                      ),
                      SizedBox(height: context.spacing.space4),
                      // Event context line — last event + type icon + relative date (CARD-02)
                      _buildEventContextLine(context, ref),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Event context line (CARD-02)
  // ---------------------------------------------------------------------------

  Widget _buildEventContextLine(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(groupEventsProvider(group.id));
    return eventsAsync.when(
      data: (events) {
        if (events.isEmpty) {
          return Text(
            'No events yet',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.colors.textSecondary,
                ),
          );
        }
        final latest = events.first; // already sorted by createdAt desc
        final config = EventTypeConfig.forType(latest.type);
        return Row(
          children: [
            // textMuted-decorative-justified: event type glyph in subtitle row, functional color carried by adjacent text
            Icon(config.icon, size: 16, color: context.colors.textMuted),
            SizedBox(width: context.spacing.space4),
            Expanded(
              child: Text(
                '${latest.name} \u2014 ${timeago.format(latest.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.colors.textSecondary,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
      loading: () => Text(
        'No events yet',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.colors.textSecondary,
            ),
      ),
      error: (e, _) => Text(
        'No events yet',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.colors.textSecondary,
            ),
      ),
    );
  }
}
