import 'package:csv/csv.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../ledger/utils/ledger_categories.dart';
import '../models/trip_receipt.dart';
import 'trip_receipt_format.dart';

/// Serializes a [TripReceipt] to a single, sectioned CSV (RFC-escaped via
/// `package:csv`). Display names only — NEVER a raw participant/auth uid. The
/// `l10n` resolves localized category names. Value/coverage/caveat formatting is
/// shared with the PDF via `trip_receipt_format.dart`. (#704 Slice A)
String tripReceiptToCsv(TripReceipt r, AppLocalizations l10n) {
  final rows = <List<dynamic>>[];

  // META
  rows.add(['RIHLA TRIP RECEIPT']);
  rows.add(['Event', r.eventName]);
  rows.add(['Type', r.eventType.name]);
  rows.add(['Dates', receiptDateRange(r.startDate, r.endDate)]);
  rows.add(['Status', r.isClosed ? closedLabel(r) : 'Open']);
  rows.add(['Generated', r.generatedAt.toIso8601String()]);
  rows.add(['Note', receiptSnapshotNote]);
  rows.add(['Scope', receiptScopeNote]);
  rows.add(['Audit coverage', coverageLabel(r.correctionsCoverage)]);
  rows.add(['Currencies', r.currencies.join('; ')]);

  // PARTICIPANTS
  rows.add([]);
  rows.add(['PARTICIPANTS']);
  for (final n in r.participantNames) {
    rows.add([n]);
  }

  // EXPENSES
  rows.add([]);
  rows.add(['EXPENSES']);
  rows.add(['Date', 'Description', 'Category', 'Paid by', 'Amount', 'Currency', 'Split']);
  for (final e in r.expenses) {
    rows.add([
      receiptDate(e.date),
      e.description ?? '',
      categoryNameForId(e.categoryId, l10n),
      e.payerName,
      formatAmountFixed(e.amount, e.currency),
      e.currency,
      e.splitMode,
    ]);
  }

  // ALLOCATIONS — per-expense per-person owed (the line-level proof)
  rows.add([]);
  rows.add(['ALLOCATIONS (who owed what, per expense)']);
  rows.add(['Expense', 'Person', 'Owed', 'Currency']);
  for (final a in r.allocations) {
    rows.add([
      a.expenseId,
      a.personName,
      formatAmountFixed(a.owed, a.currency),
      a.currency,
    ]);
  }

  // CORRECTIONS
  rows.add([]);
  rows.add(['CORRECTIONS']);
  rows.add(['Date', 'Type', 'Expense', 'Detail', 'Amount', 'Currency', 'By']);
  for (final c in r.corrections) {
    rows.add([
      receiptDate(c.date),
      c.kind,
      c.expenseId,
      correctionDetail(c),
      formatAmountOrDash(c.amount, c.currency),
      c.currency,
      c.actorName,
    ]);
  }

  // SETTLEMENTS
  rows.add([]);
  rows.add(['SETTLEMENTS']);
  rows.add(['Date', 'From', 'To', 'Amount', 'Currency', 'Group-linked', 'Note']);
  for (final s in r.settlements) {
    rows.add([
      receiptDate(s.date),
      s.fromName,
      s.toName,
      formatAmountFixed(s.amount, s.currency),
      s.currency,
      s.isGroupLinked ? 'yes' : 'no',
      s.note ?? '',
    ]);
  }

  // BALANCES — per currency, verbatim oracle nets
  rows.add([]);
  rows.add(['BALANCES (per currency; + owed to them, - they owe)']);
  rows.add(['Currency', 'Person', 'Net']);
  for (final cur in r.currencies) {
    for (final n in r.netsByCurrency[cur] ?? const <ReceiptNet>[]) {
      rows.add([cur, n.personName, formatAmountFixed(n.net, cur)]);
    }
  }

  return const ListToCsvConverter().convert(rows);
}
