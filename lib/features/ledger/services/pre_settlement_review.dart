import 'package:decimal/decimal.dart';

import '../../../core/models/split_mode.dart';
import '../models/expense_model.dart';

/// Why an expense surfaced in the pre-settlement review sheet (#204). These are
/// display-only warnings — none of them change a balance.
enum ReviewReason {
  exactSplit,
  customParticipants,
  personal,
  largeAmount,

  /// The payer is no longer a live member of the group — a departed-payer
  /// expense (the #249 conservation-gap class). Only fires when the caller
  /// supplies the live-member set (see [detectReviewWorthyExpenses]).
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
    // An empty [activeParticipantIds] means "live-member set unknown" (old
    // single-arg callers / tests) — skip, so the check never false-fires on
    // every payer. The caller MUST pass the LIVE-member set (never the
    // append-only event.participantIds, which never sheds a departed payer).
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
    if (bucket.length > perCurrencyCap) overflow += bucket.length - perCurrencyCap;
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
