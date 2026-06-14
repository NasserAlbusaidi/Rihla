import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/ledger/models/expense_model.dart';

/// #515: `Expense.fromFirestore` must not throw on an unsupported currency.
/// `MoneySerializer.fromSubunits` throws `ArgumentError` for an unknown code, so
/// a single pre-existing / forged expense doc would otherwise error the entire
/// `watchExpenses` stream for every member — taking out the ledger screen AND
/// the home balance once-path. The read path fences the currency with
/// `isSupported` and falls back to OMR, mirroring the deployed settlement read
/// fence (#193/#220) and the BalanceCalculator fence (#47).
void main() {
  Map<String, dynamic> doc({
    String? currency,
    required int amountFils,
    String? splitMode,
    Map<String, int>? splitDistribution,
  }) {
    final m = <String, dynamic>{
      'id': 'e1',
      'eventId': 'event-1',
      'payerParticipantId': 'p1',
      'amountFils': amountFils,
      'createdAt': DateTime.utc(2026, 5, 13, 10).toIso8601String(),
      'createdBy': 'uid-1',
    };
    if (currency != null) m['currency'] = currency;
    if (splitMode != null) m['splitMode'] = splitMode;
    if (splitDistribution != null) m['splitDistribution'] = splitDistribution;
    return m;
  }

  group('Expense.fromFirestore currency read fence (#515)', () {
    test('supported USD decodes at 2dp', () {
      final e = Expense.fromFirestore(doc(currency: 'USD', amountFils: 999));
      expect(e.amount, Decimal.parse('9.99'));
      expect(e.currency, 'USD');
    });

    test('supported OMR decodes at 3dp', () {
      final e = Expense.fromFirestore(doc(currency: 'OMR', amountFils: 10500));
      expect(e.amount, Decimal.parse('10.500'));
      expect(e.currency, 'OMR');
    });

    test('missing currency defaults to OMR', () {
      final e = Expense.fromFirestore(doc(amountFils: 5000));
      expect(e.amount, Decimal.parse('5.000'));
      expect(e.currency, 'OMR');
    });

    test('unsupported currency does NOT throw — OMR-scale amount, OMR retained',
        () {
      expect(
        () => Expense.fromFirestore(doc(currency: 'XYZ', amountFils: 5000)),
        returnsNormally,
      );
      final e = Expense.fromFirestore(doc(currency: 'XYZ', amountFils: 5000));
      expect(e.amount, Decimal.parse('5.000'));
      // The retained label can never disagree with the scale the amount was
      // decoded at: a fenced-to-OMR doc retains 'OMR', not its raw value.
      expect(e.currency, 'OMR');
    });

    // Orthogonal axis (#515 principle 7): an `exact`-split doc with a bad
    // currency reaches _splitValueFromPersisted -> MoneySerializer.fromSubunits,
    // a SECOND throw site the top-level amount fence must also cover. Settlements
    // have no splitDistribution, so this path is unique to expenses.
    test('unsupported currency on an exact-split expense does NOT throw', () {
      final badExactDoc = doc(
        currency: 'XYZ',
        amountFils: 5000,
        splitMode: SplitMode.exact.storageKey,
        splitDistribution: const {'p1': 2250, 'p2': 2750},
      );
      expect(() => Expense.fromFirestore(badExactDoc), returnsNormally);
      final e = Expense.fromFirestore(badExactDoc);
      // Exact values decode at the fenced OMR scale (2250 fils -> 2.250).
      expect(e.splitDistribution?['p1'], Decimal.parse('2.250'));
      expect(e.splitDistribution?['p2'], Decimal.parse('2.750'));
    });

    test('lowercase supported code is retained as-is (rules block it on write)',
        () {
      final e = Expense.fromFirestore(doc(currency: 'omr', amountFils: 10500));
      expect(e.amount, Decimal.parse('10.500'));
      expect(e.currency, 'omr');
    });
  });
}
