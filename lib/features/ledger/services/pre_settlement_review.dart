import 'package:decimal/decimal.dart';

import '../../../core/models/split_mode.dart';
import '../models/expense_model.dart';

/// Why an expense surfaced in the pre-settlement review sheet (#204). These are
/// display-only warnings — none of them change a balance.
enum ReviewReason { exactSplit, customParticipants, personal, largeAmount }

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
    final total = totalByCurrency[e.currency] ?? Decimal.zero;
    final count = countByCurrency[e.currency] ?? 0;
    if (count >= 2 && total > Decimal.zero && e.amount > total * frac) {
      flags.add(ReviewFlag(e, ReviewReason.largeAmount));
    }
  }
  return flags;
}

/// Distinct review-worthy expenses, newest first, for the sheet's item list —
/// deduped across reasons (an expense flagged twice appears once). Order is by
/// descending amount so the most consequential surfaces first.
List<Expense> distinctReviewExpenses(List<ReviewFlag> flags) {
  final seen = <String>{};
  final out = <Expense>[];
  for (final f in flags) {
    if (seen.add(f.expense.id)) out.add(f.expense);
  }
  out.sort((a, b) => b.amount.compareTo(a.amount));
  return out;
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
