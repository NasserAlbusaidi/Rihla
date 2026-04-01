import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/group_model.dart';
import '../providers/group_balance_provider.dart';
import '../../events/models/event_type_config.dart';
import '../../events/providers/event_provider.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

/// A card widget for displaying a group summary in the home screen list.
///
/// Shows the group name, member count badge, and the current user's personal
/// net balance in this group (D-08/D-09). Uses [AppColorTokens.light.errorText] for
/// negative (owes), [AppColorTokens.light.successText] for positive (owed), and
/// [AppColorTokens.light.textSecondary] for zero (settled).
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
  // Accent strip — 5 earthy colors, hash-selected per group ID (CARD-01)
  // ---------------------------------------------------------------------------

  static const List<Color> _accentColors = [
    Color(0xFF0D7B74), // slot 0 — primary teal
    Color(0xFFCC6B49), // slot 1 — terracotta (focusBorderWarm)
    Color(0xFF10B981), // slot 2 — success emerald
    Color(0xFFF59E0B), // slot 3 — warning amber
    Color(0xFF7C6E5A), // slot 4 — warm umber (inline const, no token)
  ];

  static Color _accentColor(String groupId) =>
      _accentColors[groupId.hashCode.abs() % _accentColors.length];

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
          color: AppColorTokens.light.cardSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadowTokens.standard.raised,
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 4dp accent strip on the left edge (CARD-01)
              Container(
                width: 4,
                color: _accentColor(group.id),
              ),
              // Card content
              Expanded(
                child: Padding(
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color:
                                            AppColorTokens.light.textSecondary,
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
                          final net =
                              userBalance?.netBalance ?? Decimal.zero;
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
                            _ => (
                                'Settled',
                                AppColorTokens.light.textSecondary
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
                                color: AppColorTokens.light.textMuted,
                              ),
                        ),
                        error: (e, _) => Text(
                          'Settled',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: AppColorTokens.light.textSecondary,
                              ),
                        ),
                      ),
                      const SizedBox(height: 4),
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
                  color: AppColorTokens.light.textMuted,
                ),
          );
        }
        final latest = events.first; // already sorted by createdAt desc
        final config = EventTypeConfig.forType(latest.type);
        return Row(
          children: [
            Icon(config.icon, size: 16, color: AppColorTokens.light.textMuted),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${latest.name} \u2014 ${timeago.format(latest.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColorTokens.light.textSecondary,
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
              color: AppColorTokens.light.textMuted,
            ),
      ),
      error: (e, _) => Text(
        'No events yet',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColorTokens.light.textMuted,
            ),
      ),
    );
  }
}
