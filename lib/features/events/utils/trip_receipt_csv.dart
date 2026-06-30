import 'package:csv/csv.dart';
import 'package:decimal/decimal.dart';

import '../../../core/utils/formatters.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../ledger/utils/ledger_categories.dart';
import '../models/trip_receipt.dart';

/// Fixed-decimal money string for CSV — value only, no symbol/code (currency is
/// its own column). Precision via [AppFormatters.currencyConfig] (graceful 2dp
/// fallback — never throws on an off-allowlist code, unlike `fractionDigits`).
String formatAmountFixed(Decimal amount, String currency) {
  final digits = AppFormatters.currencyConfig[currency]?.decimals ?? 2;
  return amount.toStringAsFixed(digits);
}

/// Serializes a [TripReceipt] to a single, sectioned CSV (RFC-escaped via
/// `package:csv`). Display names only — NEVER a raw participant/auth uid. The
/// `l10n` resolves localized category names. (#704 Slice A)
String tripReceiptToCsv(TripReceipt r, AppLocalizations l10n) {
  final rows = <List<dynamic>>[];

  String amt(Decimal a, String c) => c.isEmpty ? '—' : formatAmountFixed(a, c);

  // META
  rows.add(['RIHLA TRIP RECEIPT']);
  rows.add(['Event', r.eventName]);
  rows.add(['Type', r.eventType.name]);
  rows.add(['Dates', _dateRange(r.startDate, r.endDate)]);
  rows.add(['Status', r.isClosed ? _closedLabel(r) : 'Open']);
  rows.add(['Generated', r.generatedAt.toIso8601String()]);
  rows.add([
    'Note',
    'Snapshot of current ledger truth; settlements recorded after this time are not included.',
  ]);
  rows.add([
    'Scope',
    'Event-scoped. Group-level (cross-event) settlements are not reflected here — see the group receipt.',
  ]);
  rows.add(['Audit coverage', _coverageLabel(r.correctionsCoverage)]);
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
      _date(e.date),
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
      _date(c.date),
      c.kind,
      c.expenseId,
      _correctionDetail(c),
      amt(c.amount, c.currency),
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
      _date(s.date),
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

String _coverageLabel(AuditCoverage c) => switch (c) {
  AuditCoverage.complete => 'complete',
  AuditCoverage.capped =>
    'capped — most-recent 500 audit entries; older corrections may be omitted',
  AuditCoverage.unverifiedOffline => 'unverified — audit log not loaded offline',
  AuditCoverage.unavailable => 'unavailable — audit log could not be read',
};

String _correctionDetail(ReceiptCorrection c) {
  if (c.kind == 'DELETE') {
    final desc = (c.description ?? '').trim();
    return c.detailsCaptured
        ? (desc.isEmpty ? 'deleted' : 'deleted: $desc')
        : 'deleted (details not captured)';
  }
  if (!c.detailsCaptured) return 'edited (details not captured)';
  final parts = <String>[];
  final ac = c.amountChange;
  if (ac != null) {
    parts.add(
      'amount ${formatAmountFixed(ac.before, c.currency)}→${formatAmountFixed(ac.after, c.currency)}',
    );
  }
  if (c.payerChange != null) {
    parts.add('payer ${c.payerChange!.before}→${c.payerChange!.after}');
  }
  if (c.descriptionChange != null) parts.add('description changed');
  return parts.isEmpty ? 'edited' : parts.join('; ');
}

String _date(DateTime d) => d.toIso8601String().split('T').first;

String _dateRange(DateTime? start, DateTime? end) {
  if (start == null && end == null) return '—';
  if (start != null && end != null) return '${_date(start)} – ${_date(end)}';
  return _date((start ?? end)!);
}

String _closedLabel(TripReceipt r) {
  final when = r.closedAt == null ? '' : ' ${_date(r.closedAt!)}';
  final by = (r.closedByName ?? '').isEmpty ? '' : ' by ${r.closedByName}';
  return 'Closed$when$by';
}
