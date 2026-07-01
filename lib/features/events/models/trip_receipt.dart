import 'package:decimal/decimal.dart';

import 'event_model.dart';

/// How much of the event's correction/audit history the receipt could load.
///
/// The audit log has no live stream (only a one-shot, cache-first fetch), so a
/// proof pack must state its coverage honestly rather than present a partial or
/// offline-empty audit as a clean, complete one. (#704 Slice A)
enum AuditCoverage {
  /// Every audit entry for the event was read.
  complete,

  /// The fetch cap was hit — older corrections may be omitted.
  capped,

  /// Offline with nothing cached: the audit log could not be verified.
  unverifiedOffline,

  /// The audit fetch errored (parse/permission/transient) — not necessarily offline.
  unavailable,
}

/// One current (non-deleted) expense row of the proof pack. [categoryId] stays
/// raw — the CSV/UI layer resolves it to a display name with `AppLocalizations`,
/// keeping this projection pure and l10n-free.
typedef ReceiptExpense = ({
  String id,
  DateTime date,
  String? description,
  String? categoryId,
  String payerName,
  Decimal amount,
  String currency,
  String splitMode,
});

/// A per-expense, per-person owed share — the line-level proof that ties back to
/// the verbatim balances. Computed via the canonical `allocateExpenseOwed` over
/// the SAME universe the oracle used, then filtered to that universe so it
/// sum-reconciles with [TripReceipt.netsByCurrency].
typedef ReceiptAllocation = ({
  String expenseId,
  String personName,
  Decimal owed,
  String currency,
});

/// One correction (edit or soft-delete) reconstructed from the server audit log.
///
/// [amount]/[currency] are ALWAYS populated (from the audit `after` snapshot,
/// which equals `before` for a soft-delete) so a removed/edited expense never
/// loses its magnitude. An entry whose metadata can't be read (legacy empty /
/// off-allowlist currency that throws) is surfaced as [detailsCaptured] `false`
/// with a `''` sentinel currency that is excluded from per-currency math.
typedef ReceiptCorrection = ({
  DateTime date,
  String kind, // 'EDIT' | 'DELETE'
  String expenseId,
  String? description,
  String actorName,
  bool detailsCaptured,
  Decimal amount,
  String currency,
  ({Decimal before, Decimal after})? amountChange,
  ({String before, String after})? descriptionChange,
  ({String before, String after})? payerChange,
});

/// One append-only settlement row. [isGroupLinked] flags the per-event docs a
/// #752 group settle-up decomposes into (the residual group settlement lives in
/// the group collection and is intentionally absent from an event receipt).
typedef ReceiptSettlement = ({
  DateTime date,
  String fromName,
  String toName,
  Decimal amount,
  String currency,
  bool isGroupLinked,
  String? note,
});

/// One participant's net for one currency, copied verbatim from the oracle.
/// [participantId] is model-internal only (test assertions / dedup) — the CSV
/// serializer NEVER emits it.
typedef ReceiptNet = ({
  String participantId,
  String personName,
  Decimal net,
});

/// A pure, immutable, oracle-derived projection of one event's ledger truth,
/// ready to serialize to CSV (Slice A) or PDF (Slice B). Per-currency throughout
/// — there is no cross-currency summation anywhere. (#704)
class TripReceipt {
  const TripReceipt({
    required this.eventId,
    required this.eventName,
    required this.eventType,
    required this.startDate,
    required this.endDate,
    required this.isClosed,
    required this.closedAt,
    required this.closedByName,
    required this.generatedAt,
    required this.participantNames,
    required this.expenses,
    required this.allocations,
    required this.corrections,
    required this.correctionsCoverage,
    required this.settlements,
    required this.netsByCurrency,
    required this.currencies,
  });

  final String eventId;
  final String eventName;
  final EventType eventType;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isClosed;
  final DateTime? closedAt;
  final String? closedByName;

  /// The point-in-time the snapshot was taken (passed in — never `DateTime.now()`
  /// inside the pure builder, so tests stay deterministic).
  final DateTime generatedAt;

  final List<String> participantNames;
  final List<ReceiptExpense> expenses;
  final List<ReceiptAllocation> allocations;
  final List<ReceiptCorrection> corrections;
  final AuditCoverage correctionsCoverage;
  final List<ReceiptSettlement> settlements;
  final Map<String, List<ReceiptNet>> netsByCurrency;
  final List<String> currencies;

  bool get isEmpty =>
      expenses.isEmpty && settlements.isEmpty && corrections.isEmpty;
}
