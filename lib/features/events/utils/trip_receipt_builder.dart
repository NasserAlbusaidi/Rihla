import 'package:decimal/decimal.dart';

import '../../../core/models/split_mode.dart';
import '../../activity/models/activity_log_model.dart';
import '../../activity/utils/expense_audit_diff.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/models/settlement_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../trip/models/trip_model.dart';
import '../models/event_model.dart';
import '../models/trip_receipt.dart';

/// The #196 render-only uid discriminator, e.g. " (#a1b2)". Stripped from every
/// exported name so the portable CSV carries zero uid-derived bytes — but the
/// " (former member)" suffix is preserved (no PII).
final RegExp _uidDiscriminator = RegExp(r' \(#[^)]*\)$');

/// Currencies a GCC-first audience expects to see first; the rest follow
/// alphabetically. Keeps the per-currency sections in a stable, sensible order.
const List<String> _gccFirst = ['OMR', 'SAR', 'AED', 'QAR', 'KWD', 'BHD'];

/// Pure projection of one event's ledger truth into a [TripReceipt]. Re-derives
/// NO balances — [balancesByCurrency] is the verbatim `calculateBalances` oracle
/// output. The only arithmetic is the canonical per-expense allocator (over the
/// SAME [participants] universe the oracle used) and per-currency grouping; no
/// `DateTime.now()`, no l10n, no Firestore — deterministic and table-testable.
/// (#704 Slice A)
TripReceipt buildTripReceipt({
  required Event event,
  required List<Expense> expenses,
  required List<Settlement> settlements,
  required List<Participant> participants,
  required List<ActivityLog> auditLogs,
  required AuditCoverage correctionsCoverage,
  required Map<String, List<UserBalance>> balancesByCurrency,
  required Map<String, String> roster,
  required DateTime generatedAt,
  String unknownName = 'Unknown',
}) {
  final universeIds = participants.map((p) => p.id).toList();
  final universeSet = universeIds.toSet();

  // Stripped (no-uid) display name for an id, or the placeholder — never the
  // raw id, never null. Keeps any " (former member)" label.
  String stripped(String? id) {
    if (id == null) return unknownName;
    final raw = roster[id];
    if (raw == null || raw.isEmpty) return unknownName;
    return raw.replaceFirst(_uidDiscriminator, '');
  }

  // Resolve the universe with a NON-uid ordinal appended to any colliding
  // stripped name, so two same-display-name members stay distinct in the export
  // without leaking uid bytes (replaces the #196 uid discriminator).
  final resolvedUniverse = _resolveWithOrdinals(universeIds, stripped);

  String nameForId(String? id) {
    if (id == null) return unknownName;
    return resolvedUniverse[id] ?? stripped(id);
  }

  // --- Expenses + per-person allocations -----------------------------------
  final expenseRows = <ReceiptExpense>[];
  final allocationRows = <ReceiptAllocation>[];
  for (final e in expenses) {
    expenseRows.add((
      id: e.id,
      date: e.createdAt,
      description: e.description,
      categoryId: e.categoryId,
      payerName: nameForId(e.payerParticipantId),
      amount: e.amount,
      currency: e.currency,
      splitMode: (e.splitMode ?? SplitMode.equally).name,
    ));

    final owed = BalanceCalculator.allocateExpenseOwed(
      amount: e.amount,
      splitMode: e.splitMode,
      splitDistribution: e.splitDistribution,
      scope: e.scope,
      customSplitParticipants: e.customSplitParticipants,
      payerId: e.payerParticipantId,
      participantIds: universeIds,
      currency: e.currency,
    );
    for (final entry in owed.entries) {
      // Drop-guard parity with the oracle: an owed key outside the balance
      // universe (a forged/legacy distribution key) is dropped, so ALLOCATIONS
      // sum-reconciles with BALANCES across all split modes.
      if (!universeSet.contains(entry.key)) continue;
      if (entry.value == Decimal.zero) continue;
      allocationRows.add((
        expenseId: e.id,
        personName: nameForId(entry.key),
        owed: entry.value,
        currency: e.currency,
      ));
    }
  }

  // --- Corrections (audit UPDATE/DELETE) -----------------------------------
  final correctionRows = <ReceiptCorrection>[];
  for (final log in auditLogs) {
    final kind = log.isDelete ? 'DELETE' : 'EDIT';
    final expenseId = (log.metadata['expenseId'] as String?) ?? '';
    final actor = (log.actorName != null && log.actorName!.trim().isNotEmpty)
        ? log.actorName!
        : nameForId(log.actorId);

    ExpenseAuditDiff? diff;
    try {
      diff = ExpenseAuditDiff.fromMetadata(log.metadata);
    } catch (_) {
      diff = null; // off-allowlist currency throws in fromSubunits → unreadable
    }
    final after = diff?.after;

    if (after == null) {
      // Legacy/empty metadata or a throwing parse — surface, never drop.
      correctionRows.add((
        date: log.createdAt,
        kind: kind,
        expenseId: expenseId,
        description: null,
        actorName: actor,
        detailsCaptured: false,
        amount: Decimal.zero,
        currency: '', // sentinel — excluded from per-currency math
        amountChange: null,
        descriptionChange: null,
        payerChange: null,
      ));
      continue;
    }

    if (log.isDelete) {
      correctionRows.add((
        date: log.createdAt,
        kind: 'DELETE',
        expenseId: expenseId,
        description: after.description,
        actorName: actor,
        detailsCaptured: true,
        amount: after.amount, // a soft-delete leaves the amount unchanged
        currency: after.currency,
        amountChange: null,
        descriptionChange: null,
        payerChange: null,
      ));
      continue;
    }

    final before = diff!.before;
    correctionRows.add((
      date: log.createdAt,
      kind: 'EDIT',
      expenseId: expenseId,
      description: after.description,
      actorName: actor,
      detailsCaptured: diff.hasFieldChange,
      amount: after.amount,
      currency: after.currency,
      amountChange: diff.amountChanged
          ? (before: before!.amount, after: after.amount)
          : null,
      descriptionChange: diff.descriptionChanged
          ? (before: before!.description ?? '', after: after.description ?? '')
          : null,
      payerChange: diff.payerChanged
          ? (
              before: nameForId(before!.payerParticipantId),
              after: nameForId(after.payerParticipantId),
            )
          : null,
    ));
  }

  // --- Settlements (live, append-only) -------------------------------------
  final settlementRows = settlements
      .map(
        (s) => (
          date: s.settledAt,
          fromName: s.payerParticipantId != null
              ? nameForId(s.payerParticipantId)
              : (s.payerName ?? unknownName),
          toName: s.recipientParticipantId != null
              ? nameForId(s.recipientParticipantId)
              : (s.recipientName ?? unknownName),
          amount: s.amount,
          currency: s.currency,
          isGroupLinked: s.groupSettleUpId != null,
          note: s.note,
        ),
      )
      .toList();

  // --- Balances (verbatim oracle output) -----------------------------------
  final nets = <String, List<ReceiptNet>>{
    for (final entry in balancesByCurrency.entries)
      entry.key: [
        for (final b in entry.value)
          (
            participantId: b.participantId,
            personName: nameForId(b.participantId),
            net: b.netBalance,
          ),
      ],
  };

  // --- Currencies (union, GCC-first; '' sentinel excluded) -----------------
  final currencySet = <String>{
    ...expenseRows.map((e) => e.currency),
    ...settlementRows.map((s) => s.currency),
    ...balancesByCurrency.keys,
  }..removeWhere((c) => c.isEmpty);

  return TripReceipt(
    eventId: event.id,
    eventName: event.name,
    eventType: event.type,
    startDate: event.startDate,
    endDate: event.endDate,
    isClosed: event.isClosed,
    closedAt: event.closedAt,
    closedByName: event.closedBy == null ? null : nameForId(event.closedBy),
    generatedAt: generatedAt,
    participantNames: [for (final id in universeIds) nameForId(id)],
    expenses: expenseRows,
    allocations: allocationRows,
    corrections: correctionRows,
    correctionsCoverage: correctionsCoverage,
    settlements: settlementRows,
    netsByCurrency: nets,
    currencies: _orderCurrencies(currencySet),
  );
}

/// Maps each universe id to its stripped display name, appending a stable,
/// NON-uid ordinal (" (2)", " (3)") to any name shared by more than one id so
/// same-named members stay distinct without uid bytes. Ordinals are assigned by
/// sorted id for determinism.
Map<String, String> _resolveWithOrdinals(
  List<String> ids,
  String Function(String) stripped,
) {
  final byName = <String, List<String>>{};
  for (final id in ids) {
    byName.putIfAbsent(stripped(id).toLowerCase(), () => []).add(id);
  }
  final out = <String, String>{};
  for (final group in byName.values) {
    if (group.length == 1) {
      out[group.first] = stripped(group.first);
      continue;
    }
    final sorted = [...group]..sort();
    for (var i = 0; i < sorted.length; i++) {
      final id = sorted[i];
      out[id] = i == 0 ? stripped(id) : '${stripped(id)} (${i + 1})';
    }
  }
  return out;
}

List<String> _orderCurrencies(Set<String> currencies) {
  final list = currencies.toList()
    ..sort((a, b) {
      final ra = _gccFirst.indexOf(a);
      final rb = _gccFirst.indexOf(b);
      final pa = ra == -1 ? _gccFirst.length : ra;
      final pb = rb == -1 ? _gccFirst.length : rb;
      return pa != pb ? pa.compareTo(pb) : a.compareTo(b);
    });
  return list;
}
