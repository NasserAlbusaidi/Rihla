import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../ledger/providers/expense_provider.dart';
import '../keys/event_keys.dart';
import '../models/event_model.dart';
import '../providers/event_provider.dart';

/// Danger zone section for EventSettingsScreen.
///
/// Only visible when [isCreator] is true.
/// Shows a balance warning row when the event has unsettled expenses,
/// and a delete event tile with confirmation dialog.
///
/// Activity logging (event_deleted) is wrapped in try/catch per D-14:
/// logging failure must never crash the delete flow.
class EventDangerSection extends ConsumerWidget {
  const EventDangerSection({
    super.key,
    required this.groupId,
    required this.eventId,
    required this.event,
    required this.isCreator,
  });

  final String groupId;
  final String eventId;
  final Event event;
  final bool isCreator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isCreator) return const SizedBox.shrink();

    final eventRef = (groupId: groupId, eventId: eventId);
    final expenses =
        ref.watch(eventExpensesProvider(eventRef)).valueOrNull ?? const [];
    final settlements =
        ref.watch(eventSettlementsProvider(eventRef)).valueOrNull ?? const [];
    final hasUnsettled = expenses.isNotEmpty && settlements.isEmpty;

    return Column(
      key: EventKeys.dangerSection,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColorTokens.light.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColorTokens.light.error.withValues(alpha: 0.3),
            ),
            boxShadow: AppShadowTokens.standard.raised,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasUnsettled) _buildBalanceWarning(),
              if (hasUnsettled)
                Divider(height: 1, color: AppColorTokens.light.inputFill),
              _buildDeleteTile(context, ref, hasUnsettled),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader() {
    return Row(
      children: [
        Icon(
          Iconsax.warning_2,
          size: 16,
          color: AppColorTokens.light.errorText,
        ),
        const SizedBox(width: 6),
        Text(
          'DANGER ZONE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColorTokens.light.errorText,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceWarning() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            Iconsax.warning_2,
            size: 16,
            color: AppColorTokens.light.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This event has unsettled balances.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColorTokens.light.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteTile(
    BuildContext context,
    WidgetRef ref,
    bool hasUnsettled,
  ) {
    return GestureDetector(
      key: EventKeys.deleteEventTile,
      onTap: () {
        HapticService.selection();
        _showDeleteDialog(context, ref, hasUnsettled);
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColorTokens.light.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  Iconsax.trash,
                  size: 18,
                  color: AppColorTokens.light.errorText,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Delete event',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColorTokens.light.errorText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    bool hasUnsettled,
  ) {
    final body = hasUnsettled
        ? 'This will permanently delete the event and all its expenses, '
            'gear items, and documents. This cannot be undone.\n\n'
            'This event has unsettled balances. Settle up before deleting, '
            'or proceed anyway.'
        : 'This will permanently delete the event and all its expenses, '
            'gear items, and documents. This cannot be undone.';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: EventKeys.deleteEventDialog,
        title: Text(
          'Delete this event?',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColorTokens.light.textPrimary,
          ),
        ),
        content: Text(
          body,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColorTokens.light.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Keep event',
              style: TextStyle(color: AppColorTokens.light.textSecondary),
            ),
          ),
          TextButton(
            key: EventKeys.deleteEventConfirmButton,
            onPressed: () {
              Navigator.of(ctx).pop();
              HapticService.medium();
              _executeDelete(context, ref);
            },
            child: Text(
              'Delete event',
              style: TextStyle(
                color: AppColorTokens.light.errorText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _executeDelete(BuildContext context, WidgetRef ref) {
    // Log event_deleted activity (deferred from Phase 30 P01 per STATE.md D-14).
    // Wrapped in try/catch — logging failure must never crash the delete flow.
    try {
      final actorId = FirebaseConfig.currentUser?.uid ?? '';
      final actorName =
          FirebaseConfig.currentUser?.displayName ?? 'Someone';
      ref.read(groupActivityServiceProvider).logGroupEvent(
            groupId: groupId,
            type: 'event_deleted',
            actorId: actorId,
            actorName: actorName,
            description: 'deleted the event ${event.name}',
          );
    } catch (_) {
      // Activity logging failure must never crash the delete flow.
    }

    // Fire-and-forget delete — synchronous navigation per Phase 26 P01 decision.
    ref.read(eventServiceProvider).deleteEvent(
          groupId: groupId,
          eventId: eventId,
        );

    if (context.mounted) {
      context.go('/group/$groupId');
    }
  }
}
