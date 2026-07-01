import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/error_message_translator.dart';
import '../../../core/utils/write_ack.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../ledger/providers/ledger_view_provider.dart';
import '../keys/event_keys.dart';
import '../models/event_model.dart';
import '../models/spending_snapshot.dart';
import '../providers/event_provider.dart';
import '../providers/event_recap_provider.dart';

/// Danger zone section for EventSettingsScreen.
///
/// Only visible when [isAdmin] is true. Under the C-Hierarchy permission model,
/// admin = event creator OR group creator (see `EventPermissions.isEventAdmin`).
/// Shows a balance warning row when the event has unsettled expenses, and a
/// delete event tile with confirmation dialog.
///
/// Activity logging (event_deleted) is wrapped in try/catch per D-14:
/// logging failure must never crash the delete flow.
class EventDangerSection extends ConsumerWidget {
  const EventDangerSection({
    super.key,
    required this.groupId,
    required this.eventId,
    required this.event,
    required this.isAdmin,
  });

  final String groupId;
  final String eventId;
  final Event event;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isAdmin) return const SizedBox.shrink();

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
        _buildSectionHeader(context),
        SizedBox(height: context.spacing.space8),
        Container(
          decoration: BoxDecoration(
            color: context.colors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.colors.error.withValues(alpha: 0.3),
            ),
            boxShadow: context.shadows.raised,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasUnsettled) _buildBalanceWarning(context),
              if (hasUnsettled)
                Divider(height: 1, color: context.colors.inputFill),
              _buildCloseReopenTile(context, ref),
              Divider(height: 1, color: context.colors.inputFill),
              _buildDeleteTile(context, ref, hasUnsettled),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context) {
    return Row(
      children: [
        Icon(Iconsax.warning_2, size: 16, color: context.colors.errorText),
        const SizedBox(width: 6),
        Text(
          context.l10n.eventDangerZone,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.colors.errorText,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceWarning(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.space16,
        vertical: 10,
      ),
      child: Row(
        children: [
          Icon(Iconsax.warning_2, size: 16, color: context.colors.warning),
          SizedBox(width: context.spacing.space8),
          Expanded(
            child: Text(
              context.l10n.eventUnsettledWarning,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// #723: Close (freeze spending, settlements stay live) / Reopen toggle.
  /// Not destructive, so it reads neutral rather than error-red.
  Widget _buildCloseReopenTile(BuildContext context, WidgetRef ref) {
    final closed = event.isClosed;
    return GestureDetector(
      key: EventKeys.closeEventTile,
      onTap: () {
        HapticService.selection();
        if (closed) {
          _showReopenDialog(context, ref);
        } else {
          _showCloseDialog(context, ref);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space16,
          vertical: 10,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  closed ? Iconsax.unlock : Iconsax.lock,
                  size: 18,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            SizedBox(width: context.spacing.space12),
            Expanded(
              child: Text(
                closed ? context.l10n.eventReopen : context.l10n.eventClose,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
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
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space16,
          vertical: 10,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.colors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  Iconsax.trash,
                  size: 18,
                  color: context.colors.errorText,
                ),
              ),
            ),
            SizedBox(width: context.spacing.space12),
            Expanded(
              child: Text(
                context.l10n.eventDelete,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.colors.errorText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCloseDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          context.l10n.eventCloseQuestion,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
          ),
        ),
        content: Text(
          context.l10n.eventCloseBody,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: context.colors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              context.l10n.eventKeepEvent,
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
          TextButton(
            key: EventKeys.closeEventConfirmButton,
            onPressed: () {
              Navigator.of(ctx).pop();
              HapticService.medium();
              _executeClose(context, ref);
            },
            child: Text(
              context.l10n.eventCloseConfirm,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showReopenDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          context.l10n.eventReopenQuestion,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
          ),
        ),
        content: Text(
          context.l10n.eventReopenBody,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: context.colors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              context.l10n.eventKeepEvent,
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
          TextButton(
            key: EventKeys.closeEventConfirmButton,
            onPressed: () {
              Navigator.of(ctx).pop();
              HapticService.medium();
              _executeReopen(context, ref);
            },
            child: Text(
              context.l10n.eventReopenConfirm,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeClose(BuildContext context, WidgetRef ref) async {
    final uid = FirebaseConfig.currentUser?.uid ?? '';
    final eventRef = (groupId: groupId, eventId: eventId);
    try {
      // #766: capture the frozen SPENDING half at close. Make sure the ledger
      // has loaded first so the snapshot reflects the real spend, not a cold
      // false-empty view. The section already subscribes this stream in build;
      // bounded so an offline stall can't hang the close (on timeout we fall
      // through → recap stays live, recoverable by reopen+close).
      try {
        await ref
            .read(eventExpensesProvider(eventRef).future)
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      final recap = ref.read(eventRecapProvider(eventRef));
      final view = ref.read(ledgerViewProvider(eventRef));
      final snapshot = recap.isEmpty
          ? null
          : SpendingSnapshot.from(
              recap: recap,
              balances: view.balances,
            ).toMap();

      final connectivity = ref.read(connectivityProvider.notifier);
      final connectivityStatus = ref.read(connectivityProvider);
      final outcome = await awaitServerAck(
        ref
            .read(eventServiceProvider)
            .closeEvent(
              groupId: groupId,
              eventId: eventId,
              closedBy: uid,
              spendingSnapshot: snapshot,
            ),
        skipWait: connectivityStatus != ConnectivityStatus.online,
      );
      if (outcome == WriteAck.acked) {
        connectivity.noteLocalWrite();
      } else {
        connectivity.noteQueuedWrite();
      }
    } catch (e, st) {
      if (context.mounted) {
        unawaited(Sentry.captureException(e, stackTrace: st));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.eventCloseFailed(friendlyMessageFor(context, e)),
            ),
          ),
        );
      }
    }
  }

  Future<void> _executeReopen(BuildContext context, WidgetRef ref) async {
    try {
      final connectivity = ref.read(connectivityProvider.notifier);
      final connectivityStatus = ref.read(connectivityProvider);
      final outcome = await awaitServerAck(
        ref
            .read(eventServiceProvider)
            .reopenEvent(groupId: groupId, eventId: eventId),
        skipWait: connectivityStatus != ConnectivityStatus.online,
      );
      if (outcome == WriteAck.acked) {
        connectivity.noteLocalWrite();
      } else {
        connectivity.noteQueuedWrite();
      }
    } catch (e, st) {
      if (context.mounted) {
        unawaited(Sentry.captureException(e, stackTrace: st));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.eventReopenFailed(friendlyMessageFor(context, e)),
            ),
          ),
        );
      }
    }
  }

  void _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    bool hasUnsettled,
  ) {
    final body = hasUnsettled
        ? context.l10n.eventDeleteBodyWithUnsettled
        : context.l10n.eventDeleteBody;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: EventKeys.deleteEventDialog,
        title: Text(
          context.l10n.eventDeleteQuestion,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
          ),
        ),
        content: Text(
          body,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: context.colors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              context.l10n.eventKeepEvent,
              style: TextStyle(color: context.colors.textSecondary),
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
              context.l10n.eventDelete,
              style: TextStyle(
                color: context.colors.errorText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeDelete(BuildContext context, WidgetRef ref) async {
    // Log event_deleted activity (deferred from Phase 30 P01 per STATE.md D-14).
    // Wrapped in try/catch — logging failure must never crash the delete flow.
    try {
      final actorId = FirebaseConfig.currentUser?.uid ?? '';
      final actorName = ref.read(settingsProvider).deviceName.isNotEmpty
          ? ref.read(settingsProvider).deviceName
          : 'Someone';
      ref
          .read(groupActivityServiceProvider)
          .logGroupEvent(
            groupId: groupId,
            type: 'event_deleted',
            actorId: actorId,
            actorName: actorName,
            description: 'deleted the event ${event.name}',
            metadata: {'eventId': event.id, 'eventName': event.name},
          );
    } catch (_) {
      // Activity logging failure must never crash the delete flow.
    }

    try {
      final connectivity = ref.read(connectivityProvider.notifier);
      final connectivityStatus = ref.read(connectivityProvider);
      final outcome = await awaitServerAck(
        ref
            .read(eventServiceProvider)
            .deleteEvent(groupId: groupId, eventId: eventId),
        skipWait: connectivityStatus != ConnectivityStatus.online,
      );
      if (outcome == WriteAck.acked) {
        connectivity.noteLocalWrite(groupId: groupId);
      } else {
        connectivity.noteQueuedWrite(groupId: groupId);
      }
      if (context.mounted) {
        context.go('/group/$groupId');
      }
    } catch (e, st) {
      if (context.mounted) {
        unawaited(Sentry.captureException(e, stackTrace: st));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.eventDeleteFailed(friendlyMessageFor(context, e)),
            ),
          ),
        );
      }
    }
  }
}
