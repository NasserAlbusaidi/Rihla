import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/models/settlement_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../ledger/services/pre_settlement_review.dart';
import '../models/group_member_model.dart';
import 'group_balance_provider.dart';
import 'group_provider.dart';

/// Result of the group-scope pre-settlement review basis (#204).
///
/// [resolved] is false while the basis is still assembling (events list or
/// members unsettled, group balances unresolved, group settlement stream
/// unresolved, or ANY event's expense or settlement stream still loading) —
/// the one-shot review sheet must never latch on a partial basis. A
/// hard-errored expense stream is dropped WITHOUT blocking resolution,
/// mirroring the #244 OR-skip so an event absent from the settle basis is
/// absent here too. A hard-errored settlement stream is treated as resolved
/// here; `groupBalancesProvider` owns the WYSIWYG dropped-event basis and the
/// incomplete-balance banner.
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
///
/// #1058: flags the viewer settled past are suppressed in two stages: stage A
/// event-local (that event's settlements — mirrors the event screen), stage B
/// group-engagement (group-level docs + groupSettleUpId-tagged legs, applied
/// group-wide). An untagged event settlement NEVER suppresses another event's
/// flags — intentional asymmetry, Gate R1.
final groupPreSettleReviewProvider =
    Provider.family<GroupPreSettleReview, String>((ref, groupId) {
      final eventsAsync = ref.watch(groupEventsProvider(groupId));
      final membersAsync = ref.watch(groupMembersProvider(groupId));
      final balancesAsync = ref.watch(groupBalancesProvider(groupId));
      // #1058: watermark inputs. Zero new Firestore listeners — the only
      // consumer (group_settle_up_screen.dart) already watches both.
      final groupSettlementsAsync = ref.watch(
        groupSettlementsProvider(groupId),
      );
      final viewerUid = ref.watch(currentUserIdProvider);

      final membersSettled = membersAsync.hasValue || membersAsync.hasError;
      final balancesSettled = balancesAsync.hasValue || balancesAsync.hasError;
      // #1058: a still-loading group-settlement stream reads as "viewer never
      // settled" and would false-fire the one-shot sheet — block resolution,
      // mirroring the per-event settlement gate. A hard error proceeds
      // without those rows (less suppression = fail toward warning).
      final groupSettlementsSettled =
          groupSettlementsAsync.hasValue || groupSettlementsAsync.hasError;
      if (!eventsAsync.hasValue ||
          !membersSettled ||
          !balancesSettled ||
          !groupSettlementsSettled) {
        return (flags: const <ReviewFlag>[], resolved: false);
      }

      final liveMemberIds = <String>{
        for (final m in membersAsync.valueOrNull ?? const <GroupMember>[])
          if (!m.isTombstone) m.userId,
      };

      final flags = <ReviewFlag>[];
      // #1058 stage B basis: ONLY settlements proving the viewer went through
      // the GROUP review sheet — group-level docs plus #752
      // groupSettleUpId-tagged decomposed legs. The group/event ASYMMETRY is
      // intentional (Gate R1): an untagged settlement in Event A proves the
      // viewer passed Event A's sheet, never Event B's — it suppresses only
      // event-locally (stage A below), so a viewer who settled one event
      // still sees another event's unreviewed flags. Marked corrections ride
      // along so cross-collection targets stay disarmed. A #244 OR-dropped
      // event contributes neither flags nor watermark (fail toward warning).
      final groupWideSettlements = <Settlement>[
        ...?groupSettlementsAsync.valueOrNull,
      ];
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
        final eventSettlements =
            settlementsAsync.valueOrNull ?? const <Settlement>[];
        groupWideSettlements.addAll(
          eventSettlements.where(
            (s) => s.groupSettleUpId != null || s.isMarkedCorrection,
          ),
        );
        // #1058 stage A: event-local suppression — same semantics as the
        // event settle-up screen, so the two surfaces agree per flag.
        flags.addAll(
          suppressFlagsSettledPastByViewer(
            detectReviewWorthyExpenses(
              expensesAsync.valueOrNull ?? const <Expense>[],
              activeParticipantIds: event.participantIds.toSet().intersection(
                liveMemberIds,
              ),
            ),
            settlements: eventSettlements,
            viewerUid: viewerUid,
          ),
        );
      }
      if (!resolved) return (flags: const <ReviewFlag>[], resolved: false);

      // #1058 stage B: group-engagement suppression across all events.
      // Applies on BOTH exits — settled-past flags stay suppressed even when
      // balances errored and the #922 bucket filter cannot run.
      final visibleFlags = suppressFlagsSettledPastByViewer(
        flags,
        settlements: groupWideSettlements,
        viewerUid: viewerUid,
      );
      if (balancesAsync.hasError) {
        return (flags: List.unmodifiable(visibleFlags), resolved: true);
      }

      final outstandingCurrencies = {
        for (final entry in balancesAsync.valueOrNull!.balances.entries)
          if (entry.value.any((b) => b.netBalance != Decimal.zero)) entry.key,
      };
      return (
        flags: List.unmodifiable(
          filterFlagsToOutstandingCurrencies(
            visibleFlags,
            outstandingCurrencies,
          ),
        ),
        resolved: true,
      );
    });
