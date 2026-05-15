import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../events/providers/event_provider.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/widgets/record_payment_sheet.dart';
import '../../groups/widgets/settle_up_page_body.dart';
import '../../trip/models/trip_model.dart';
import '../keys/ledger_keys.dart';
import '../providers/expense_provider.dart';

/// Event-scoped Settle Up screen.
///
/// Mirrors the Group Settle-Up wireframe (Hi_GroupSettle): italic intro,
/// summary chips, optimized transfer cards, "Each person's net", and a
/// payment-history footer. Routed at `/group/:gid/event/:eid/ledger/settle-up`.
class SettleUpScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String eventId;

  const SettleUpScreen({
    super.key,
    required this.groupId,
    required this.eventId,
  });

  @override
  ConsumerState<SettleUpScreen> createState() => _SettleUpScreenState();
}

class _SettleUpScreenState extends ConsumerState<SettleUpScreen> {
  final Map<int, GlobalKey> _tileKeys = {};

  @override
  Widget build(BuildContext context) {
    final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
    final eventAsync = ref.watch(eventDetailProvider(eventRef));

    if (eventAsync.isLoading) {
      return Scaffold(
        backgroundColor: context.colors.scaffoldBackground,
        body: SafeArea(
          child: Column(
            children: [
              _SettleUpTopBar(groupId: widget.groupId, eventId: widget.eventId),
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          ),
        ),
      );
    }

    final event = eventAsync.valueOrNull;

    if (event == null) {
      return Scaffold(
        backgroundColor: context.colors.scaffoldBackground,
        body: SafeArea(
          child: Column(
            children: [
              _SettleUpTopBar(groupId: widget.groupId, eventId: widget.eventId),
              Expanded(
                child: EmptyStateView(
                  icon: Iconsax.warning_2,
                  title: 'This event no longer exists',
                  message:
                      'It may have been deleted. Tap below to go back to your groups.',
                  actionLabel: 'Go Home',
                  onAction: () => context.go('/home'),
                  iconColor: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));
    final currentUid = ref.watch(currentUserIdProvider);

    final participants = event.participantIds.map((id) {
      return Participant(
        id: id,
        tripId: event.id,
        role: ParticipantRole.member,
        joinedAt: event.createdAt,
        displayName: event.participantNames[id],
      );
    }).toList();

    return Scaffold(
      key: LedgerKeys.settleUpScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _SettleUpTopBar(groupId: widget.groupId, eventId: widget.eventId),
            Expanded(
              child: expensesAsync.when(
                data: (expenses) {
                  final settlements = settlementsAsync.valueOrNull ?? const [];

                  final balances = BalanceCalculator.calculateBalances(
                    expenses: expenses,
                    settlements: settlements,
                    participants: participants,
                  );

                  final userNames = <String, String>{
                    for (final p in participants)
                      p.id: p.displayName ?? 'Unknown',
                  };

                  final optimalSettlements =
                      BalanceCalculator.calculateOptimalSettlements(
                        balances: balances,
                        userNames: userNames,
                      );

                  return SettleUpPageBody(
                    subjectName: event.name,
                    currency: 'OMR',
                    optimalSettlements: optimalSettlements,
                    balances: balances,
                    settlementsAsync: settlementsAsync,
                    currentUid: currentUid,
                    tileKeys: _tileKeys,
                    onRecord:
                        ({
                          required settlement,
                          required fromName,
                          required toName,
                          required fromUserId,
                          required toUserId,
                          required suggestedAmount,
                        }) => _showRecordPaymentSheet(
                          context,
                          settlement: settlement,
                          fromName: fromName,
                          toName: toName,
                          fromUserId: fromUserId,
                          toUserId: toUserId,
                          suggestedAmount: suggestedAmount,
                        ),
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Iconsax.warning_2,
                          size: 40,
                          color: context.colors.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Couldn't load balances.",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(eventExpensesProvider(eventRef)),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRecordPaymentSheet(
    BuildContext context, {
    required Map<String, dynamic> settlement,
    required String fromName,
    required String toName,
    required String fromUserId,
    required String toUserId,
    required Decimal suggestedAmount,
  }) async {
    const currency = 'OMR';

    final result = await showRecordPaymentSheet(
      context,
      currency: currency,
      fromName: fromName,
      toName: toName,
      suggestedAmount: suggestedAmount,
    );

    if (!context.mounted || result == null) return;

    final editedAmount = Decimal.tryParse(result.amount) ?? suggestedAmount;
    final noteText = result.note.isEmpty ? null : result.note;

    if (editedAmount <= Decimal.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount must be greater than zero')),
      );
      return;
    }
    if (editedAmount > suggestedAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Amount cannot exceed the outstanding balance of '
            '${AppFormatters.formatCurrency(suggestedAmount, currency)}',
          ),
        ),
      );
      return;
    }

    await _recordSettlement(
      context,
      fromUserId: fromUserId,
      toUserId: toUserId,
      amount: editedAmount,
      note: noteText,
      currency: currency,
    );
  }

  Future<void> _recordSettlement(
    BuildContext context, {
    required String fromUserId,
    required String toUserId,
    required Decimal amount,
    required String currency,
    String? note,
  }) async {
    HapticService.success();
    final currentUid = ref.read(currentUserIdProvider);
    if (currentUid == null || currentUid.isEmpty) {
      throw StateError(
        'Cannot record settlement without an authenticated user.',
      );
    }
    try {
      await ref
          .read(settlementServiceProvider)
          .addSettlement(
            groupId: widget.groupId,
            eventId: widget.eventId,
            payerParticipantId: fromUserId,
            recipientParticipantId: toUserId,
            amount: amount,
            currency: currency,
            createdBy: currentUid,
            note: note,
          );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Settlement recorded.'),
            backgroundColor: context.colors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "Couldn't record settlement. Check your connection and try again.",
            ),
            backgroundColor: context.colors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }
}

class _SettleUpTopBar extends StatelessWidget {
  const _SettleUpTopBar({required this.groupId, required this.eventId});

  final String groupId;
  final String eventId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 20, 8),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back',
                icon: const Icon(Iconsax.arrow_left_2, size: 20),
                color: context.colors.textPrimary,
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/group/$groupId/event/$eventId/ledger');
                  }
                },
              ),
            ),
            Text(
              'Settle Up',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
