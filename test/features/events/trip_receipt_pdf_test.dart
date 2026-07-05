import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/models/trip_receipt.dart';
import 'package:safar/features/events/utils/trip_receipt_pdf.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

/// The PDF renderer is a terminal display surface over the already-scrubbed
/// [TripReceipt] model (which carries display names only — no uids). These tests
/// pin: (1) valid PDF bytes, (2) no throw across every fixture shape incl. the
/// `''`-sentinel correction and an empty pack, (3) Arabic content renders
/// through the embedded Noto font (byte-level evidence the face is embedded),
/// and (4) the real bundled-asset load path works. (#704 Slice B)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Decimal d(String s) => Decimal.parse(s);
  final AppLocalizations l10n = AppLocalizationsEn();
  final gen = DateTime.utc(2026, 6, 30, 8, 30);

  // Load the bundled face straight off disk so the render tests don't depend on
  // the test asset bundle; a dedicated test below covers the rootBundle path.
  late final pw.Font font;

  setUpAll(() {
    final bytes = File('assets/fonts/NotoSansArabic-Regular.ttf').readAsBytesSync();
    font = pw.Font.ttf(ByteData.view(bytes.buffer));
  });

  TripReceipt receipt({
    String eventName = 'Desert Camp',
    List<ReceiptExpense> expenses = const [],
    List<ReceiptAllocation> allocations = const [],
    List<ReceiptCorrection> corrections = const [],
    AuditCoverage coverage = AuditCoverage.complete,
    List<ReceiptSettlement> settlements = const [],
    Map<String, List<ReceiptNet>> nets = const {},
    List<String> currencies = const [],
    List<String> participantNames = const ['Ahmed', 'Sara'],
    bool isClosed = true,
  }) => TripReceipt(
    eventId: 'e1',
    eventName: eventName,
    eventType: EventType.camping,
    startDate: DateTime.utc(2026, 6, 10),
    endDate: DateTime.utc(2026, 6, 12),
    isClosed: isClosed,
    closedAt: isClosed ? DateTime.utc(2026, 6, 13) : null,
    closedByName: isClosed ? 'Ahmed' : null,
    generatedAt: gen,
    participantNames: participantNames,
    expenses: expenses,
    allocations: allocations,
    corrections: corrections,
    correctionsCoverage: coverage,
    settlements: settlements,
    netsByCurrency: nets,
    currencies: currencies,
  );

  ReceiptExpense expense({
    String id = 'x1',
    String? description = 'Dinner',
    String payerName = 'Ahmed',
    String amount = '12.500',
    String currency = 'OMR',
  }) => (
    id: id,
    date: DateTime.utc(2026, 6, 10),
    description: description,
    categoryId: 'food',
    payerName: payerName,
    amount: d(amount),
    currency: currency,
    splitMode: 'equally',
  );

  bool isValidPdf(Uint8List bytes) {
    if (bytes.length < 200) return false;
    final head = latin1.decode(bytes.sublist(0, 5));
    final tail = latin1.decode(bytes.sublist(bytes.length - 32));
    return head == '%PDF-' && tail.contains('%%EOF');
  }

  test('produces a valid, non-trivial PDF for a full receipt', () async {
    final r = receipt(
      expenses: [expense()],
      allocations: [
        (expenseId: 'x1', personName: 'Ahmed', owed: d('6.250'), currency: 'OMR'),
        (expenseId: 'x1', personName: 'Sara', owed: d('6.250'), currency: 'OMR'),
      ],
      settlements: [
        (
          date: DateTime.utc(2026, 6, 14),
          fromName: 'Sara',
          toName: 'Ahmed',
          amount: d('6.250'),
          currency: 'OMR',
          isGroupLinked: false,
          note: 'cash',
        ),
      ],
      currencies: ['OMR'],
      nets: {
        'OMR': [
          (participantId: 'uid-1', personName: 'Ahmed', net: d('6.250')),
          (participantId: 'uid-2', personName: 'Sara', net: d('-6.250')),
        ],
      },
    );
    final bytes = await tripReceiptToPdf(r, l10n, fontOverride: font);
    expect(isValidPdf(bytes), isTrue);
  });

  test('renders every fixture shape without throwing', () async {
    final fixtures = <TripReceipt>[
      // multi-currency incl. JPY (0dp)
      receipt(
        expenses: [
          expense(amount: '12.500', currency: 'OMR'),
          expense(id: 'x2', amount: '8.00', currency: 'USD'),
          expense(id: 'x3', amount: '1500', currency: 'JPY'),
        ],
        currencies: ['OMR', 'USD', 'JPY'],
        nets: {
          'OMR': [(participantId: 'a', personName: 'A', net: d('1.5'))],
          'USD': [(participantId: 'a', personName: 'A', net: d('1.5'))],
          'JPY': [(participantId: 'a', personName: 'A', net: d('1500'))],
        },
      ),
      // corrections: edit + soft-delete + unreadable sentinel
      receipt(
        corrections: [
          (
            date: DateTime.utc(2026, 6, 15),
            kind: 'EDIT',
            expenseId: 'x1',
            description: null,
            actorName: 'Ahmed',
            detailsCaptured: true,
            amount: d('12.500'),
            currency: 'OMR',
            amountChange: (before: d('10.000'), after: d('12.500')),
            descriptionChange: null,
            payerChange: (before: 'Sara', after: 'Ahmed'),
          ),
          (
            date: DateTime.utc(2026, 6, 16),
            kind: 'DELETE',
            expenseId: 'x2',
            description: 'Snacks',
            actorName: 'Sara',
            detailsCaptured: true,
            amount: d('3.000'),
            currency: 'OMR',
            amountChange: null,
            descriptionChange: null,
            payerChange: null,
          ),
          (
            date: DateTime.utc(2026, 6, 17),
            kind: 'EDIT',
            expenseId: 'x9',
            description: null,
            actorName: 'Unknown',
            detailsCaptured: false,
            amount: Decimal.zero,
            currency: '', // sentinel — must render, not crash
            amountChange: null,
            descriptionChange: null,
            payerChange: null,
          ),
        ],
      ),
      // same display-name participants (non-uid ordinals from the builder)
      receipt(participantNames: const ['Mohammed', 'Mohammed (2)']),
      // open (not closed) event → null closedAt/closedBy
      receipt(isClosed: false),
      // fully empty pack
      receipt(participantNames: const []),
    ];
    for (final r in fixtures) {
      final bytes = await tripReceiptToPdf(r, l10n, fontOverride: font);
      expect(isValidPdf(bytes), isTrue);
    }
  });

  test('Arabic names/descriptions render through the embedded font', () async {
    final r = receipt(
      eventName: 'رحلة الصحراء',
      expenses: [
        expense(payerName: 'عبدالله', description: 'عشاء في المخيم', amount: '12.500'),
      ],
      participantNames: const ['عبدالله', 'سارة'],
      currencies: ['OMR'],
      nets: {
        'OMR': [
          (participantId: 'a', personName: 'عبدالله', net: d('6.250')),
          (participantId: 'b', personName: 'سارة', net: d('-6.250')),
        ],
      },
    );
    final bytes = await tripReceiptToPdf(r, l10n, fontOverride: font);
    expect(isValidPdf(bytes), isTrue);
    // The embedded (subset) Noto face appears in the font descriptor — byte-level
    // proof the Arabic glyphs were embedded, not silently dropped.
    expect(latin1.decode(bytes, allowInvalid: true), contains('NotoSansArabic'));
  });

  test('renders entirely with the embedded font — no Helvetica fallback', () async {
    // Regression: `fontWeight: bold` on the Regular-only face made the pdf pkg
    // fall back to the built-in Helvetica-Bold (no Unicode → Arabic blanks). A
    // clean render references only the embedded Noto face, never Helvetica.
    final r = receipt(
      eventName: 'رحلة',
      expenses: [expense(payerName: 'عبدالله')],
      corrections: [
        (
          date: DateTime.utc(2026, 6, 15),
          kind: 'EDIT',
          expenseId: 'x1',
          description: null,
          actorName: 'عبدالله',
          detailsCaptured: true,
          amount: d('12.500'),
          currency: 'OMR',
          amountChange: (before: d('10.000'), after: d('12.500')),
          descriptionChange: null,
          payerChange: null,
        ),
      ],
      currencies: ['OMR'],
      nets: {
        'OMR': [(participantId: 'a', personName: 'عبدالله', net: d('1.000'))],
      },
    );
    final text = latin1.decode(
      await tripReceiptToPdf(r, l10n, fontOverride: font),
      allowInvalid: true,
    );
    expect(text, contains('NotoSansArabic'));
    expect(text, isNot(contains('Helvetica')));
  });

  test('loads the bundled font via rootBundle (production asset path)', () async {
    // No fontOverride → exercises _loadReceiptFont / rootBundle wiring.
    final bytes = await tripReceiptToPdf(receipt(expenses: [expense()]), l10n);
    expect(isValidPdf(bytes), isTrue);
  });

  test('document-close ritual caption is present (text-only, no fork)', () {
    // The composite Noto face draws glyph IDs in the byte stream, not literal
    // ASCII, so this asserts against the widget tree (closeRitualSectionForTest)
    // rather than grepping the finished PDF bytes.
    final widgets = closeRitualSectionForTest(l10n);
    final texts = widgets.whereType<pw.Center>().map((c) => c.child).whereType<pw.Text>();
    final spanTexts = texts.map((t) => (t.text as pw.TextSpan).text);
    expect(spanTexts, contains('recorded in Rihla'));
  });
}
