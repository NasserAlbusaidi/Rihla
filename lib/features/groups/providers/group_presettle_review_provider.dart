import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../ledger/services/pre_settlement_review.dart';
import '../models/group_member_model.dart';
import 'group_balance_provider.dart';
import 'group_provider.dart';

/// Result of the group-scope pre-settlement review basis (#204).
///
/// [resolved] is false while the basis is still assembling (events list or
/// members unsettled, group balances unresolved, or ANY event's expense or
/// settlement stream still loading) — the one-shot review sheet must never
/// latch on a partial basis. A hard-errored expense stream is dropped WITHOUT
/// blocking resolution, mirroring the #244 OR-skip so an event absent from the
/// settle basis is absent here too. A hard-errored settlement stream is treated
/// as resolved here; `groupBalancesProvider` owns the WYSIWYG dropped-event
/// basis and the incomplete-balance banner.
typedef GroupPreSettleReview = ({List<ReviewFlag> flags, bool resolved});

/// Review-worthy expenses across the whole group settle basis (#204, group
/// trigger). Display-only sibling of `groupBalancesProvider` — a projection,
/// never a money source.
///
/// Iterates the SAME [groupEventsProvider] list and the SAME per-event
/// [eventExpensesProvider] and [eventSettlementsProvider] family instances the
/// live balance provider watches, so this adds NO new Firestore listeners (same
/// argument as `groupTaggedEventSettlementsProvider` /
/// `groupSpendingSummaryProvider`).
///
/// The detector runs PER EVENT with that event's
/// `participantIds ∩ liveMemberIds` — reproducing the event-level sheet's
/// semantics for payer universe and event-local largeAmount denominator. The
/// final suppression is GROUP-SCOPE aggregate-based: if a currency's group nets
/// are all zero, flags in that currency are hidden here even if an individual
/// event would still show them. A members error yields an empty active set →
/// the payer check is skipped while the other reasons still fire, mirroring the
/// event-level fallback in `settle_up_screen.dart`.
final groupPreSettleReviewProvider =
    Provider.family<GroupPreSettleReview, String>((ref, groupId) {
      final eventsAsync = ref.watch(groupEventsProvider(groupId));
      final membersAsync = ref.watch(groupMembersProvider(groupId));
      final balancesAsync = ref.watch(groupBalancesProvider(groupId));

      final membersSettled = membersAsync.hasValue || membersAsync.hasError;
      final balancesSettled = balancesAsync.hasValue || balancesAsync.hasError;
      if (!eventsAsync.hasValue || !membersSettled || !balancesSettled) {
        return (flags: const <ReviewFlag>[], resolved: false);
      }

      final liveMemberIds = <String>{
        for (final m in membersAsync.valueOrNull ?? const <GroupMember>[])
          if (!m.isTombstone) m.userId,
      };

      final flags = <ReviewFlag>[];
      var resolved = true;
      for (final event in eventsAsync.valueOrNull ?? const <Event>[]) {
        final eventRef = (groupId: groupId, eventId: event.id);
        final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
        final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));
        if (expensesAsync.isLoading && !expensesAsync.hasValue) {
          resolved = false;
          continue;
        }
        if (settlementsAsync.isLoading && !settlementsAsync.hasValue) {
          resolved = false;
          continue;
        }
        if (expensesAsync.hasError && !expensesAsync.hasValue) continue;
        flags.addAll(
          detectReviewWorthyExpenses(
            expensesAsync.valueOrNull ?? const <Expense>[],
            activeParticipantIds: event.participantIds.toSet().intersection(
              liveMemberIds,
            ),
          ),
        );
      }
      if (!resolved) return (flags: const <ReviewFlag>[], resolved: false);
      if (balancesAsync.hasError) {
        return (flags: List.unmodifiable(flags), resolved: true);
      }

      final outstandingCurrencies = {
        for (final entry in balancesAsync.valueOrNull!.balances.entries)
          if (entry.value.any((b) => b.netBalance != Decimal.zero)) entry.key,
      };
      return (
        flags: List.unmodifiable(
          filterFlagsToOutstandingCurrencies(flags, outstandingCurrencies),
        ),
        resolved: true,
      );
    });
