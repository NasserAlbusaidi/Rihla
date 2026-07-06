import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/expense_model.dart';
import 'expense_provider.dart';
import 'ledger_view_provider.dart';

/// One roster entry with the display-name l10n fallback DEFERRED: a null
/// [displayName] ⇒ the widget substitutes `l10n.ledgerMemberFallback`. Mirrors
/// the [LedgerSettlementNames] null-deferral so this provider stays a pure,
/// `BuildContext`-free function of its data inputs (memoizable + unit-testable).
typedef LedgerRosterEntry = ({
  String participantId,
  String? displayName,
  Decimal signedAmount,
  String? currency,
});

/// The current user's filter-INDEPENDENT view of one event's balances: the
/// "You" lines, the per-person roster (one entry per non-zero currency bucket),
/// and the per-currency people-count the hero needs. Everything here is a pure
/// derivation of [ledgerViewProvider]'s balances + [currentPid] — it does NOT
/// depend on the ledger's category filter, so hoisting it here (#628) means a
/// category-chip `setState` no longer re-runs the per-person balance pivots.
///
/// Widget-layer enums (`LedgerRosterState`) are NOT returned: they are O(1)
/// assemblies the widget does from [myLines] + its own `hasExpenses`, which
/// keeps this provider free of any widget-layer import.
typedef LedgerPerspective = ({
  /// Raw resolved name of the current user; null ⇒ widget applies `l10n.ledgerYou`.
  String? myDisplayName,

  /// The current user's non-zero nets, GCC-first ([nonZeroNetsGccFirst]).
  List<({String currency, Decimal net})> myLines,

  /// One entry per (other person, non-zero bucket); a settled-everywhere person
  /// keeps a single `Decimal.zero` entry so their EVEN chip stays on the strip.
  /// Sorted by `|signedAmount|` descending. `signedAmount = -theirNet` (their
  /// debt to you → positive chip; your debt to them → negative chip).
  List<LedgerRosterEntry> roster,

  /// `currency → count of OTHER participants whose net in that bucket is non-zero`
  /// (the former `bucketPeopleCount`). The hero reads this by `[currency] ?? 0`.
  Map<String, int> peopleCountByCurrency,
});

/// Filter-independent ledger perspective for one event, memoized by
/// `(eventRef, currentPid)` (#628).
///
/// A category-chip tap in [LedgerScreen] is a `setState`; it does NOT change
/// this provider's key ([currentPid] is derived from the stable current uid +
/// the event's stable `participantIds`) nor the value of the watched
/// [ledgerViewProvider] (whose own key/streams are unchanged) — so Riverpod
/// serves the cached perspective instead of re-running the O(C×M²) per-person
/// `myNetByCurrency` pivots + the roster sort. Recompute fires only on a real
/// data change (the balances re-emit) or a `currentPid` change.
///
/// [currentPid] is the ALREADY-resolved participant id (the widget does the
/// cheap `event.participantIds.contains(uid) ? uid : null` membership check, as
/// it also needs `currentPid` for `LedgerDayCard.currentParticipantId`). A null
/// [currentPid] (viewer not in this event) yields an empty "self" + a roster of
/// everyone, reproducing the former inline behaviour exactly.
final ledgerPerspectiveProvider =
    Provider.family<LedgerPerspective, ({EventRef eventRef, String? currentPid})>(
  (ref, key) {
    final data = ref.watch(ledgerViewProvider(key.eventRef));
    final currentPid = key.currentPid;
    final balances = data.balances;
    final rosterDisplayNames = data.rosterDisplayNames;

    // myDisplayName — first balance bucket carrying the current user (the name
    // is resolved once per uid, so any bucket's copy is the same).
    String? myDisplayName;
    for (final bucket in balances.values) {
      for (final b in bucket) {
        if (b.participantId == currentPid) {
          myDisplayName = b.displayName;
          break;
        }
      }
      if (myDisplayName != null) break;
    }

    // #630: one O(C×M) pivot serves the "You" lines AND every roster row below,
    // replacing the former 1 + M separate O(C×M) myNetByCurrency passes.
    final pivot = pivotNetsByParticipant(balances);
    final myLines = nonZeroNetsGccFirst(
      (currentPid == null ? null : pivot[currentPid]) ?? const {},
    );

    final peopleCountByCurrency = <String, int>{
      for (final entry in balances.entries)
        entry.key: entry.value
            .where(
              (b) =>
                  b.participantId != currentPid &&
                  b.netBalance != Decimal.zero,
            )
            .length,
    };

    // One representative balance per OTHER participant (first bucket wins, just
    // for the fallback display name); the signed lines come from the full
    // per-currency pivot below.
    final othersByPid = <String, UserBalance>{};
    for (final bucket in balances.values) {
      for (final b in bucket) {
        if (b.participantId != currentPid) {
          othersByPid.putIfAbsent(b.participantId, () => b);
        }
      }
    }

    final roster = <LedgerRosterEntry>[];
    for (final other in othersByPid.values) {
      // l10n fallback (`ledgerMemberFallback`) DEFERRED to the widget → nullable.
      final displayName =
          rosterDisplayNames[other.participantId] ?? other.displayName;
      final otherLines = nonZeroNetsGccFirst(
        pivot[other.participantId] ?? const {},
      );
      if (otherLines.isEmpty) {
        roster.add((
          participantId: other.participantId,
          displayName: displayName,
          signedAmount: Decimal.zero,
          currency: null,
        ));
      } else {
        for (final line in otherLines) {
          roster.add((
            participantId: other.participantId,
            displayName: displayName,
            signedAmount: -line.net,
            currency: line.currency,
          ));
        }
      }
    }
    roster.sort(
      (a, b) => b.signedAmount.abs().compareTo(a.signedAmount.abs()),
    );

    return (
      myDisplayName: myDisplayName,
      myLines: myLines,
      roster: roster,
      peopleCountByCurrency: peopleCountByCurrency,
    );
  },
);
