import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../l10n/generated/app_localizations.dart';
import '../../ledger/utils/ledger_categories.dart';
import '../models/trip_receipt.dart';
import 'trip_receipt_format.dart';

/// The one embedded face. Static Noto Sans Arabic covers Latin, digits AND
/// Arabic (1000+ codepoints, with GSUB joining), so a single font renders a
/// mixed-script proof pack — fully offline, no CDN. Loaded once and cached.
const String _arabicFontAsset = 'assets/fonts/NotoSansArabic-Regular.ttf';
pw.Font? _cachedFont;

Future<pw.Font> _loadReceiptFont() async =>
    _cachedFont ??= pw.Font.ttf(await rootBundle.load(_arabicFontAsset));

/// Renders a [TripReceipt] to PDF bytes — the same sections, values and honesty
/// caveats as the CSV (shared via `trip_receipt_format.dart`), laid out as
/// tables. Display names only: the model carries no raw participant/auth uid, so
/// neither does this render. Arabic names/descriptions render correctly because
/// the embedded font covers them. (#704 Slice B)
///
/// [fontOverride] lets a caller/test inject a pre-loaded face; production loads
/// the bundled Noto asset.
Future<Uint8List> tripReceiptToPdf(
  TripReceipt r,
  AppLocalizations l10n, {
  pw.Font? fontOverride,
}) async {
  final font = fontOverride ?? await _loadReceiptFont();
  final theme = pw.ThemeData.withFont(base: font);
  final doc = pw.Document(
    theme: theme,
    title: 'Rihla Trip Receipt — ${r.eventName}',
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ),
      build: (ctx) => [
        ..._header(r),
        ..._participants(r),
        ..._expenses(r, l10n),
        ..._allocations(r),
        ..._corrections(r),
        ..._settlements(r),
        ..._balances(r),
      ],
    ),
  );

  return doc.save();
}

// ── Section builders ────────────────────────────────────────────────────────

List<pw.Widget> _header(TripReceipt r) => [
  pw.Text(
    'RIHLA TRIP RECEIPT',
    // No bold weight: the single embedded Noto face is Regular-only, and asking
    // for bold makes the pdf pkg fall back to the built-in Helvetica-Bold, which
    // has NO Unicode support (Arabic → blank). Hierarchy comes from size + the
    // grey section bars instead. (#704 Slice B)
    style: const pw.TextStyle(fontSize: 20, letterSpacing: 0.5),
  ),
  pw.SizedBox(height: 2),
  pw.Text(r.eventName, style: const pw.TextStyle(fontSize: 13)),
  pw.SizedBox(height: 10),
  _metaGrid([
    ('Type', r.eventType.name),
    ('Dates', receiptDateRange(r.startDate, r.endDate)),
    ('Status', r.isClosed ? closedLabel(r) : 'Open'),
    ('Generated', r.generatedAt.toIso8601String()),
    ('Audit coverage', coverageLabel(r.correctionsCoverage)),
    ('Currencies', r.currencies.join('; ')),
  ]),
  pw.SizedBox(height: 6),
  _caveat(receiptSnapshotNote),
  _caveat(receiptScopeNote),
  pw.SizedBox(height: 4),
];

List<pw.Widget> _participants(TripReceipt r) => [
  _sectionTitle('Participants'),
  if (r.participantNames.isEmpty)
    _emptyLine()
  else
    pw.Wrap(
      spacing: 12,
      runSpacing: 2,
      children: [
        for (final n in r.participantNames)
          pw.Text('• $n', style: const pw.TextStyle(fontSize: 9)),
      ],
    ),
  pw.SizedBox(height: 10),
];

List<pw.Widget> _expenses(TripReceipt r, AppLocalizations l10n) => [
  _sectionTitle('Expenses'),
  if (r.expenses.isEmpty)
    _emptyLine()
  else
    _table(
      headers: ['Date', 'Description', 'Category', 'Paid by', 'Amount', 'Cur', 'Split'],
      rows: [
        for (final e in r.expenses)
          [
            receiptDate(e.date),
            e.description ?? '',
            categoryNameForId(e.categoryId, l10n),
            e.payerName,
            formatAmountFixed(e.amount, e.currency),
            e.currency,
            e.splitMode,
          ],
      ],
      numericColumns: {4},
    ),
  pw.SizedBox(height: 10),
];

List<pw.Widget> _allocations(TripReceipt r) => [
  _sectionTitle('Allocations (who owed what, per expense)'),
  if (r.allocations.isEmpty)
    _emptyLine()
  else
    _table(
      headers: ['Expense', 'Person', 'Owed', 'Cur'],
      rows: [
        for (final a in r.allocations)
          [
            a.expenseId,
            a.personName,
            formatAmountFixed(a.owed, a.currency),
            a.currency,
          ],
      ],
      numericColumns: {2},
    ),
  pw.SizedBox(height: 10),
];

List<pw.Widget> _corrections(TripReceipt r) => [
  _sectionTitle('Corrections'),
  if (r.corrections.isEmpty)
    _emptyLine()
  else
    _table(
      headers: ['Date', 'Type', 'Expense', 'Detail', 'Amount', 'Cur', 'By'],
      rows: [
        for (final c in r.corrections)
          [
            receiptDate(c.date),
            c.kind,
            c.expenseId,
            // The single glyph the Arabic font lacks is `→` (U+2192); render it
            // as ASCII in the PDF (the CSV keeps `→`). Everything else — en/em
            // dash, bullet, ellipsis — is covered by Noto.
            correctionDetail(c).replaceAll('→', '->'),
            formatAmountOrDash(c.amount, c.currency),
            c.currency,
            c.actorName,
          ],
      ],
      numericColumns: {4},
    ),
  pw.SizedBox(height: 10),
];

List<pw.Widget> _settlements(TripReceipt r) => [
  _sectionTitle('Settlements'),
  if (r.settlements.isEmpty)
    _emptyLine()
  else
    _table(
      headers: ['Date', 'From', 'To', 'Amount', 'Cur', 'Group-linked', 'Note'],
      rows: [
        for (final s in r.settlements)
          [
            receiptDate(s.date),
            s.fromName,
            s.toName,
            formatAmountFixed(s.amount, s.currency),
            s.currency,
            s.isGroupLinked ? 'yes' : 'no',
            s.note ?? '',
          ],
      ],
      numericColumns: {3},
    ),
  pw.SizedBox(height: 10),
];

List<pw.Widget> _balances(TripReceipt r) => [
  _sectionTitle('Balances (per currency; + owed to them, - they owe)'),
  if (r.currencies.isEmpty)
    _emptyLine()
  else
    _table(
      headers: ['Currency', 'Person', 'Net'],
      rows: [
        for (final cur in r.currencies)
          for (final n in r.netsByCurrency[cur] ?? const <ReceiptNet>[])
            [cur, n.personName, formatAmountFixed(n.net, cur)],
      ],
      numericColumns: {2},
    ),
];

// ── Shared primitives ───────────────────────────────────────────────────────

pw.Widget _sectionTitle(String text) => pw.Container(
  width: double.infinity,
  margin: const pw.EdgeInsets.only(bottom: 4),
  padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
  child: pw.Text(text, style: const pw.TextStyle(fontSize: 11)),
);

pw.Widget _metaGrid(List<(String, String)> pairs) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    for (final (label, value) in pairs)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 1),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 90,
              child: pw.Text(
                label,
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ),
            pw.Expanded(
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
            ),
          ],
        ),
      ),
  ],
);

pw.Widget _caveat(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 2),
  child: pw.Text(
    text,
    style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
  ),
);

pw.Widget _emptyLine() => pw.Text(
  'None.',
  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
);

pw.Widget _table({
  required List<String> headers,
  required List<List<String>> rows,
  Set<int> numericColumns = const {},
}) {
  final alignments = <int, pw.Alignment>{
    for (var i = 0; i < headers.length; i++)
      i: numericColumns.contains(i)
          ? pw.Alignment.centerRight
          : pw.Alignment.centerLeft,
  };
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    headerStyle: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
    cellStyle: const pw.TextStyle(fontSize: 8.5),
    cellAlignments: alignments,
    cellPadding: const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 4),
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
  );
}
