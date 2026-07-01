import 'package:decimal/decimal.dart';

import '../../../core/utils/formatters.dart';
import '../models/trip_receipt.dart';

/// Shared, pure formatting for the Trip Receipt renderers (CSV + PDF, #704).
///
/// Both serializers import these so a value, a coverage stamp, or an honesty
/// caveat is stated the SAME way in every format — a PDF and a CSV of the same
/// event can never disagree on an amount or on how complete the audit is.
/// Display strings only; never emits a raw participant/auth uid.

/// Point-in-time note stamped in both formats' META — balances legitimately move
/// after this time as settlements are still recorded (#723 freezes expenses, not
/// settlements), so the pack is honest that it is a snapshot.
const String receiptSnapshotNote =
    'Snapshot of current ledger truth; settlements recorded after this time are not included.';

/// Scope caveat stamped in both formats' META — a non-decomposed/residual group
/// settlement settles debt at the group level only and is intentionally absent.
const String receiptScopeNote =
    'Event-scoped. Group-level (cross-event) settlements are not reflected here — see the group receipt.';

/// Fixed-decimal money string — value only, no symbol/code (currency is its own
/// column/field). Precision via [AppFormatters.currencyConfig] with a graceful
/// 2dp fallback — never throws on an off-allowlist code, unlike `fractionDigits`.
String formatAmountFixed(Decimal amount, String currency) {
  final digits = AppFormatters.currencyConfig[currency]?.decimals ?? 2;
  return amount.toStringAsFixed(digits);
}

/// [formatAmountFixed] except the `''` sentinel currency (an unreadable
/// correction) renders as an em dash and is never given a numeric value.
String formatAmountOrDash(Decimal amount, String currency) =>
    currency.isEmpty ? '—' : formatAmountFixed(amount, currency);

/// Human label for how much of the audit history the pack could load.
String coverageLabel(AuditCoverage c) => switch (c) {
  AuditCoverage.complete => 'complete',
  AuditCoverage.capped =>
    'capped — most-recent 500 audit entries; older corrections may be omitted',
  AuditCoverage.unverifiedOffline => 'unverified — audit log not loaded offline',
  AuditCoverage.unavailable => 'unavailable — audit log could not be read',
};

/// One-line description of a correction (edit or soft-delete). Names in
/// [ReceiptCorrection.payerChange] are already display-resolved by the builder.
String correctionDetail(ReceiptCorrection c) {
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

/// ISO date (no time) — the receipt's stable day stamp.
String receiptDate(DateTime d) => d.toIso8601String().split('T').first;

/// A `start – end` day range, tolerant of either bound being absent.
String receiptDateRange(DateTime? start, DateTime? end) {
  if (start == null && end == null) return '—';
  if (start != null && end != null) {
    return '${receiptDate(start)} – ${receiptDate(end)}';
  }
  return receiptDate((start ?? end)!);
}

/// `Closed <date> by <name>` (each clause omitted when absent).
String closedLabel(TripReceipt r) {
  final when = r.closedAt == null ? '' : ' ${receiptDate(r.closedAt!)}';
  final by = (r.closedByName ?? '').isEmpty ? '' : ' by ${r.closedByName}';
  return 'Closed$when$by';
}
