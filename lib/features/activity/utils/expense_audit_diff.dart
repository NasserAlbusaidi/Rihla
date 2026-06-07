import 'package:decimal/decimal.dart';

import '../../../core/services/money_serializer.dart';

/// One side (before/after) of an expense audit entry's money snapshot, as
/// written by the `expenseAuditLogger` trigger into `metadata.before`/
/// `metadata.after` (#248 PR 2).
///
/// Parsed defensively via [tryParse]: any malformed/legacy/forged shape returns
/// `null` rather than throwing, because legacy entries (`metadata: {}`) and the
/// old client-writer's metadata both reach this reader.
class ExpenseAuditSnap {
  const ExpenseAuditSnap({
    required this.amount,
    required this.currency,
    this.payerParticipantId,
    this.description,
  });

  /// Display amount, converted from the stored subunits via [MoneySerializer]
  /// (read-only — no balance math here).
  final Decimal amount;
  final String currency;

  /// Payer uid; resolved to a name at render via the event participantNames map.
  final String? payerParticipantId;

  /// Free-text description; `null` when absent/empty.
  final String? description;

  /// Returns a snapshot only when [raw] is a map carrying a numeric `amountFils`
  /// and a non-empty `currency` — otherwise `null` (the render gate).
  static ExpenseAuditSnap? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final amountFils = raw['amountFils'];
    final currency = raw['currency'];
    if (amountFils is! num || currency is! String || currency.isEmpty) {
      return null;
    }
    final description = raw['description'];
    final payer = raw['payerParticipantId'];
    return ExpenseAuditSnap(
      amount: MoneySerializer.fromSubunits(amountFils.toInt(), currency),
      currency: currency,
      payerParticipantId: payer is String && payer.isNotEmpty ? payer : null,
      description: description is String && description.trim().isNotEmpty
          ? description
          : null,
    );
  }
}

/// Parsed before/after view of an expense audit log's `metadata`, plus per-field
/// change flags. [after] is present for every trigger-written entry; [before] is
/// `null` on CREATE and on legacy entries with empty metadata.
class ExpenseAuditDiff {
  const ExpenseAuditDiff({this.before, this.after});

  final ExpenseAuditSnap? before;
  final ExpenseAuditSnap? after;

  /// True when there is a money snapshot to render. Legacy/empty/malformed
  /// metadata yields `false` → the row falls back to the verb line alone.
  bool get hasDetail => after != null;

  bool get amountChanged =>
      before != null && after != null && before!.amount != after!.amount;

  bool get descriptionChanged =>
      before != null &&
      after != null &&
      before!.description != after!.description;

  bool get payerChanged =>
      before != null &&
      after != null &&
      before!.payerParticipantId != after!.payerParticipantId;

  /// True for an UPDATE that changed at least one *rendered* field. False on
  /// CREATE (no before) and on edits that only touched fields the money
  /// snapshot doesn't carry (e.g. split/category) — caller renders a summary.
  bool get hasFieldChange =>
      amountChanged || descriptionChanged || payerChanged;

  static ExpenseAuditDiff fromMetadata(Map<String, dynamic> metadata) {
    return ExpenseAuditDiff(
      before: ExpenseAuditSnap.tryParse(metadata['before']),
      after: ExpenseAuditSnap.tryParse(metadata['after']),
    );
  }
}
