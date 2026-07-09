import 'package:decimal/decimal.dart';

import '../../../core/models/split_mode.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';

/// Why an expense surfaced in the pre-settlement review sheet (#204). These are
/// display-only warnings — none of them change a balance.
enum ReviewReason {
  exactSplit,
  customParticipants,
  personal,
  largeAmount,

  /// The payer is no longer active in this event — either removed from the
  /// event roster or no longer a live group member. Only fires when the caller
  /// supplies the active-participant set (see [detectReviewWorthyExpenses]).
  payerNotInParticipants,
}

/// A single review-worthy finding: one [expense] flagged for one [reason]. An
/// expense can produce several flags (e.g. an exact split that is also large).
class ReviewFlag {
  final Expense expense;
  final ReviewReason reason;
  const ReviewFlag(this.expense, this.reason);
}

/// A single expense is "unusually large" when it exceeds this fraction of its
/// currency's total event spend (MVP heuristic, #204) — i.e. at >0.5 the one
/// expense is bigger than everything else in that currency combined, an
/// explainable "dominant expense" signal that doesn't fire on an even spread
/// (two equal expenses are each exactly 0.5, not above it). Only applied when
/// that currency has ≥2 live expenses — a lone expense is never an outlier.
final Decimal _largeFractionDefault = Decimal.parse('0.5');

/// Pure detection of review-worthy expenses for the pre-settlement review sheet
/// (#204). No money calculation, no I/O — purely classifies the passed list so
/// it is trivially testable. Soft-deleted expenses are ignored. An expense may
/// yield multiple [ReviewFlag]s (one per matched reason).
///
/// The large-amount heuristic is computed PER CURRENCY (#382 — never mix
/// currencies): an expense is large only relative to its own currency's total,
/// and only when that currency has ≥2 live expenses.
List<ReviewFlag> detectReviewWorthyExpenses(
  List<Expense> expenses, {
  Decimal? largeFraction,
  Set<String> activeParticipantIds = const {},
}) {
  final frac = largeFraction ?? _largeFractionDefault;
  final live = expenses.where((e) => !e.isDeleted).toList();

  final totalByCurrency = <String, Decimal>{};
  final countByCurrency = <String, int>{};
  for (final e in live) {
    totalByCurrency[e.currency] =
        (totalByCurrency[e.currency] ?? Decimal.zero) + e.amount;
    countByCurrency[e.currency] = (countByCurrency[e.currency] ?? 0) + 1;
  }

  final flags = <ReviewFlag>[];
  for (final e in live) {
    if (e.splitMode == SplitMode.exact) {
      flags.add(ReviewFlag(e, ReviewReason.exactSplit));
    }
    if (e.scope == ExpenseScope.custom) {
      flags.add(ReviewFlag(e, ReviewReason.customParticipants));
    }
    if (e.scope == ExpenseScope.personal) {
      flags.add(ReviewFlag(e, ReviewReason.personal));
    }
    // An empty [activeParticipantIds] means "active set unknown" (old single-arg
    // callers / tests, or member-load error fallback) — skip, so the check never
    // false-fires on every payer.
    if (activeParticipantIds.isNotEmpty &&
        !activeParticipantIds.contains(e.payerParticipantId)) {
      flags.add(ReviewFlag(e, ReviewReason.payerNotInParticipants));
    }
    final total = totalByCurrency[e.currency] ?? Decimal.zero;
    final count = countByCurrency[e.currency] ?? 0;
    if (count >= 2 && total > Decimal.zero && e.amount > total * frac) {
      flags.add(ReviewFlag(e, ReviewReason.largeAmount));
    }
  }
  return flags;
}

/// #898: drop flags whose expense currency has nothing outstanding. Suppression
/// is bucket-level on purpose — an individual expense's "contribution" is not
/// well-defined after netting, so a currency whose nets are all zero is the
/// signal that its history no longer matters to this settle-up. INBOUND-only:
/// callers pass outstanding currencies computed from the same balance basis
/// their screen displays; this file still does no money calculation.
///
/// Keep this aligned with the canonical settled definition used by
/// `nonZeroNetsGccFirst`: exact `netBalance != Decimal.zero`, no tolerance.
List<ReviewFlag> filterFlagsToOutstandingCurrencies(
  List<ReviewFlag> flags,
  Set<String> outstandingCurrencies,
) {
  return flags
      .where((f) => outstandingCurrencies.contains(f.expense.currency))
      .toList();
}

/// #1058: drop flags the viewer has already settled past. A flag survives
/// unless the viewer was PARTY (payer or recipient — never mere creator) to a
/// live settlement in the flag's currency recorded strictly after the expense
/// was created. Live excludes soft-deleted rows, #889 server-marked correction
/// rows, and the originals those corrections reverse — a corrected payment is
/// not evidence the viewer reviewed the ledger. Null [viewerUid], a tie at the
/// watermark, or a missing basis all fail toward warning (flag kept).
///
/// Timestamps are client-stamped ([Settlement.settledAt] vs
/// [Expense.createdAt]); cross-device clock skew near the boundary is accepted
/// for a display-only nudge. Expenses carry no edit timestamp, so an expense
/// edited after the viewer's last settlement stays suppressed (#799's
/// recentlyEdited trigger is the future home for re-arming). INBOUND-only,
/// like the rest of this file: no money calculation, no I/O.
List<ReviewFlag> suppressFlagsSettledPastByViewer(
  List<ReviewFlag> flags, {
  required List<Settlement> settlements,
  required String? viewerUid,
}) {
  if (viewerUid == null || flags.isEmpty || settlements.isEmpty) return flags;

  final correctedIds = <String>{
    for (final s in settlements)
      if (s.isMarkedCorrection) s.correctionOfSettlementId!,
  };

  final watermarkByCurrency = <String, DateTime>{};
  for (final s in settlements) {
    if (s.isDeleted || s.isMarkedCorrection) continue;
    if (correctedIds.contains(s.id)) continue;
    if (s.payerParticipantId != viewerUid &&
        s.recipientParticipantId != viewerUid) {
      continue;
    }
    final current = watermarkByCurrency[s.currency];
    if (current == null || s.settledAt.isAfter(current)) {
      watermarkByCurrency[s.currency] = s.settledAt;
    }
  }
  if (watermarkByCurrency.isEmpty) return flags;

  return flags.where((f) {
    final watermark = watermarkByCurrency[f.expense.currency];
    return watermark == null || !f.expense.createdAt.isBefore(watermark);
  }).toList();
}

/// Max review rows shown PER currency (#521). A single-currency event still
/// shows up to this many (no regression vs the old flat cap); in a mixed-currency
/// event each currency is capped INDEPENDENTLY, so a high-value row in one
/// currency can never be hidden behind a flood of cheaper-but-numerically-larger
/// rows in another (e.g. JPY 1000 must not bury OMR 5.000).
const kReviewPerCurrencyCap = 5;

/// The sheet's item list: distinct review-worthy expenses bucketed by currency,
/// each bucket capped at [perCurrencyCap], plus the count hidden by the cap (#521).
///
/// Raw cross-currency amount comparison is meaningless (JPY 1000 is not "bigger"
/// than OMR 5.000), so we NEVER sort or cap across currencies. Buckets are
/// emitted in alphabetical currency order; within a bucket — where amounts share
/// a unit and ARE comparable — expenses sort by amount descending, then createdAt
/// descending, then id ascending for a deterministic tiebreak.
({List<Expense> shown, int overflow}) reviewItemList(
  List<ReviewFlag> flags, {
  int perCurrencyCap = kReviewPerCurrencyCap,
}) {
  final seen = <String>{};
  final byCurrency = <String, List<Expense>>{};
  for (final f in flags) {
    if (seen.add(f.expense.id)) {
      (byCurrency[f.expense.currency] ??= <Expense>[]).add(f.expense);
    }
  }

  final shown = <Expense>[];
  var overflow = 0;
  // Alphabetical currency order — never compare amounts ACROSS currencies.
  for (final currency in byCurrency.keys.toList()..sort()) {
    final bucket = byCurrency[currency]!
      ..sort((a, b) {
        // Same currency → amounts are comparable.
        final byAmount = b.amount.compareTo(a.amount);
        if (byAmount != 0) return byAmount;
        final byDate = b.createdAt.compareTo(a.createdAt);
        if (byDate != 0) return byDate;
        return a.id.compareTo(b.id);
      });
    shown.addAll(bucket.take(perCurrencyCap));
    if (bucket.length > perCurrencyCap) {
      overflow += bucket.length - perCurrencyCap;
    }
  }
  return (shown: shown, overflow: overflow);
}

/// Count of flags per reason (for the grouped summary lines). Reasons with a
/// zero count are omitted.
Map<ReviewReason, int> reviewReasonCounts(List<ReviewFlag> flags) {
  final counts = <ReviewReason, int>{};
  for (final f in flags) {
    counts[f.reason] = (counts[f.reason] ?? 0) + 1;
  }
  return counts;
}
