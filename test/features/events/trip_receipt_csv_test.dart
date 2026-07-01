import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/models/trip_receipt.dart';
import 'package:safar/features/events/utils/trip_receipt_csv.dart';
import 'package:safar/features/events/utils/trip_receipt_format.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

void main() {
  Decimal d(String s) => Decimal.parse(s);
  final AppLocalizations l10n = AppLocalizationsEn();
  final gen = DateTime.utc(2026, 6, 30, 8, 30);

  TripReceipt receipt({
    List<ReceiptExpense> expenses = const [],
    List<ReceiptAllocation> allocations = const [],
    List<ReceiptCorrection> corrections = const [],
    AuditCoverage coverage = AuditCoverage.complete,
    List<ReceiptSettlement> settlements = const [],
    Map<String, List<ReceiptNet>> nets = const {},
    List<String> currencies = const [],
    List<String> participantNames = const ['Ahmed', 'Sara'],
  }) =>
      TripReceipt(
        eventId: 'e1',
        eventName: 'Desert Camp',
        eventType: EventType.camping,
        startDate: DateTime.utc(2026, 6, 10),
        endDate: DateTime.utc(2026, 6, 12),
        isClosed: true,
        closedAt: DateTime.utc(2026, 6, 13),
        closedByName: 'Ahmed',
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

  test('all sections + coverage stamp present; deterministic', () {
    final r = receipt(
      expenses: [
        (
          id: 'x1',
          date: DateTime.utc(2026, 6, 10),
          description: 'Dinner',
          categoryId: 'food',
          payerName: 'Ahmed',
          amount: d('12.500'),
          currency: 'OMR',
          splitMode: 'equally',
        ),
      ],
      currencies: ['OMR'],
      nets: {
        'OMR': [
          (participantId: 'uid-secret-1', personName: 'Ahmed', net: d('6.250')),
          (participantId: 'uid-secret-2', personName: 'Sara', net: d('-6.250')),
        ],
      },
    );
    final csv = tripReceiptToCsv(r, l10n);

    for (final header in [
      'RIHLA TRIP RECEIPT',
      'PARTICIPANTS',
      'EXPENSES',
      'ALLOCATIONS',
      'CORRECTIONS',
      'SETTLEMENTS',
      'BALANCES',
      'Audit coverage',
    ]) {
      expect(csv, contains(header));
    }
    // localized category name resolved (not the raw id)
    expect(csv, contains(l10n.categoryFood));
    // deterministic
    expect(tripReceiptToCsv(r, l10n), csv);
  });

  test('NEVER emits a participantId / raw uid', () {
    final r = receipt(
      currencies: ['OMR'],
      nets: {
        'OMR': [
          (participantId: 'uid-secret-1', personName: 'Ahmed', net: d('1.000')),
        ],
      },
    );
    final csv = tripReceiptToCsv(r, l10n);
    expect(csv, contains('Ahmed'));
    expect(csv, isNot(contains('uid-secret')));
  });

  test('per-currency fraction digits (OMR 3 / USD 2 / JPY 0)', () {
    final r = receipt(
      currencies: ['OMR', 'USD', 'JPY'],
      nets: {
        'OMR': [(participantId: 'a', personName: 'A', net: d('1.5'))],
        'USD': [(participantId: 'a', personName: 'A', net: d('1.5'))],
        'JPY': [(participantId: 'a', personName: 'A', net: d('1500'))],
      },
    );
    final csv = tripReceiptToCsv(r, l10n);
    expect(csv, contains('1.500')); // OMR
    expect(csv, contains('1.50')); // USD
    expect(csv, contains('1500')); // JPY (0dp)
  });

  test('RFC-escapes comma / quote / newline in free text', () {
    final r = receipt(
      expenses: [
        (
          id: 'x1',
          date: DateTime.utc(2026, 6, 10),
          description: 'Lunch, "the good one"\nday 2',
          categoryId: 'food',
          payerName: 'Ahmed',
          amount: d('5.000'),
          currency: 'OMR',
          splitMode: 'equally',
        ),
      ],
      currencies: ['OMR'],
    );
    final csv = tripReceiptToCsv(r, l10n);
    // The embedded quote is doubled and the field is wrapped — the raw
    // unescaped form must NOT appear, the escaped form must.
    expect(csv, contains('"Lunch, ""the good one""'));
  });

  test('coverage states render distinct stamps', () {
    String stamp(AuditCoverage c) => tripReceiptToCsv(receipt(coverage: c), l10n);
    final complete = stamp(AuditCoverage.complete);
    final capped = stamp(AuditCoverage.capped);
    final offline = stamp(AuditCoverage.unverifiedOffline);
    final unavailable = stamp(AuditCoverage.unavailable);
    expect(complete, contains('complete'));
    expect(capped, contains('capped'));
    expect(offline, contains('unverified'));
    expect(unavailable, contains('unavailable'));
    // all four are different
    expect({complete, capped, offline, unavailable}, hasLength(4));
  });

  test('unreadable correction (sentinel currency) renders "—", no throw', () {
    final r = receipt(
      corrections: [
        (
          date: DateTime.utc(2026, 6, 15),
          kind: 'EDIT',
          expenseId: 'old',
          description: null,
          actorName: 'Unknown',
          detailsCaptured: false,
          amount: Decimal.zero,
          currency: '',
          amountChange: null,
          descriptionChange: null,
          payerChange: null,
        ),
      ],
    );
    final csv = tripReceiptToCsv(r, l10n);
    expect(csv, contains('details not captured'));
    expect(csv, contains('—'));
  });

  test('formatAmountFixed falls back to 2dp on off-allowlist currency (no throw)', () {
    expect(formatAmountFixed(d('1.5'), 'XYZ'), '1.50');
    expect(formatAmountFixed(d('1.5'), 'OMR'), '1.500');
    expect(formatAmountFixed(d('1500'), 'JPY'), '1500');
  });
}
