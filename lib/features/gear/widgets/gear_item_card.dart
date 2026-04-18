import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../models/gear_item_model.dart';

/// Card widget for a single gear item in the packing checklist.
///
/// Displays the item name, packed checkbox, status chip, priority badge,
/// assignee avatar, and a popup menu for actions (priority toggle, claim,
/// unclaim, delete). Callbacks are passed from GearScreen.
class GearItemCard extends StatelessWidget {
  final GearItem item;
  final String? currentUserId;

  /// Called when the user taps the packed checkbox.
  final void Function(GearItem item, bool isMine) onTogglePacked;

  /// Called when the user selects a menu action (value, item).
  final void Function(String action, GearItem item) onMenuAction;

  const GearItemCard({
    super.key,
    required this.item,
    required this.currentUserId,
    required this.onTogglePacked,
    required this.onMenuAction,
  });

  @override
  Widget build(BuildContext context) {
    final isMine = item.assignedTo == currentUserId;

    return Container(
      padding: EdgeInsets.all(context.spacing.space16),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
        border: Border.all(
          color: item.isHighPriority
              ? context.colors.error.withValues(alpha: 0.3)
              : context.colors.inputFill,
          width: item.isHighPriority ? 2 : 1.5,
        ),
        boxShadow: context.shadows.raised,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticService.selection();
              onTogglePacked(item, isMine);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: item.isPacked
                    ? context.colors.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: item.isPacked
                      ? context.colors.primary
                      : context.colors.border,
                  width: 2,
                ),
                boxShadow: item.isPacked
                    ? [
                        BoxShadow(
                          color: context.colors.primary
                              .withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: item.isPacked
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          ),
          SizedBox(width: context.spacing.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.itemName.toUpperCase(),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          color: item.isPacked
                              ? context.colors.textSecondary
                              : context.colors.textPrimary,
                          decoration: item.isPacked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    if (item.isHighPriority) const _PriorityBadge(),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _StatusChip(status: item.status),
                    if (item.assignedTo != null) ...[
                      SizedBox(width: context.spacing.space12),
                      _AssigneeChip(
                        item: item,
                        isMine: isMine,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Iconsax.more,
              // textMuted-decorative-justified: popup "more" affordance icon
              color: context.colors.textMuted,
              size: 20,
            ),
            onSelected: (value) => onMenuAction(value, item),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'priority',
                child: Text('Toggle Priority'),
              ),
              if (item.assignedTo != null)
                const PopupMenuItem(
                  value: 'unclaim',
                  child: Text('Unclaim Item'),
                ),
              if (item.assignedTo == null)
                const PopupMenuItem(
                    value: 'claim', child: Text('Claim Item')),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete',
                  style:
                      TextStyle(color: context.colors.errorText),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private helpers (same file — avoids extra files for tiny components)
// ---------------------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  final GearStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      GearStatus.unclaimed => context.colors.textSecondary,
      GearStatus.claimed => context.colors.warning,
      GearStatus.packed => context.colors.moduleLedger,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        status.displayName.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Iconsax.flash,
              color: context.colors.errorText, size: 10),
          const SizedBox(width: 4),
          Text(
            'HIGH',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              color: context.colors.errorText,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssigneeChip extends StatelessWidget {
  final GearItem item;
  final bool isMine;

  const _AssigneeChip({required this.item, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.inputFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 8,
            backgroundColor: context.colors.textSecondary,
            child: Text(
              item.assigneeInitials,
              style: const TextStyle(
                fontSize: 6,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isMine
                ? 'YOU'
                : (item.assignedToName
                          ?.split(' ')[0]
                          .toUpperCase() ??
                      'NONE'),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
