import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/money_serializer.dart';

/// End-to-end round-trip test: Decimal -> MoneySerializer -> FakeFirestore -> MoneySerializer -> Decimal.
///
/// Validates DATA-01 (integer subunit storage round-trips correctly through Firestore)
/// and TST-03 (fake_cloud_firestore is usable for integration testing).
///
/// Per D-01: amounts stored as integer subunits (amount_fils), never doubles.
/// Per D-03: each document carries {amount_fils: int, currency: String}.
/// Per D-10: Dart tests use fake_cloud_firestore, not the emulator.
void main() {
  group('Firestore money round-trip', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('OMR 10.500 round-trips without precision loss', () async {
      final original = Decimal.parse('10.500');
      const currency = 'OMR';

      // Serialize to integer subunits and write to Firestore
      final subunits = MoneySerializer.toSubunits(original, currency);
      await firestore
          .collection('test_expenses')
          .doc('omr_test')
          .set({'amount_fils': subunits, 'currency': currency});

      // Read back from Firestore
      final doc =
          await firestore.collection('test_expenses').doc('omr_test').get();
      final storedSubunits = doc.data()!['amount_fils'] as int;
      final storedCurrency = doc.data()!['currency'] as String;

      // Deserialize and compare
      final restored = MoneySerializer.fromSubunits(storedSubunits, storedCurrency);
      expect(restored, equals(original));
      expect(storedSubunits, equals(10500));
    });

    test('USD 9.99 round-trips without precision loss', () async {
      final original = Decimal.parse('9.99');
      const currency = 'USD';

      final subunits = MoneySerializer.toSubunits(original, currency);
      await firestore
          .collection('test_expenses')
          .doc('usd_test')
          .set({'amount_fils': subunits, 'currency': currency});

      final doc =
          await firestore.collection('test_expenses').doc('usd_test').get();
      final storedSubunits = doc.data()!['amount_fils'] as int;
      final storedCurrency = doc.data()!['currency'] as String;

      final restored = MoneySerializer.fromSubunits(storedSubunits, storedCurrency);
      expect(restored, equals(original));
      expect(storedSubunits, equals(999));
    });

    test('JPY 1000 round-trips without precision loss', () async {
      final original = Decimal.parse('1000');
      const currency = 'JPY';

      final subunits = MoneySerializer.toSubunits(original, currency);
      await firestore
          .collection('test_expenses')
          .doc('jpy_test')
          .set({'amount_fils': subunits, 'currency': currency});

      final doc =
          await firestore.collection('test_expenses').doc('jpy_test').get();
      final storedSubunits = doc.data()!['amount_fils'] as int;
      final storedCurrency = doc.data()!['currency'] as String;

      final restored = MoneySerializer.fromSubunits(storedSubunits, storedCurrency);
      expect(restored, equals(original));
      expect(storedSubunits, equals(1000));
    });

    test('multiple expense documents with different currencies all round-trip', () async {
      final expenses = [
        (id: 'exp1', amount: Decimal.parse('25.750'), currency: 'OMR'),
        (id: 'exp2', amount: Decimal.parse('14.99'), currency: 'USD'),
        (id: 'exp3', amount: Decimal.parse('500'), currency: 'JPY'),
        (id: 'exp4', amount: Decimal.parse('0.001'), currency: 'OMR'),
      ];

      // Write all documents
      for (final expense in expenses) {
        final subunits = MoneySerializer.toSubunits(expense.amount, expense.currency);
        await firestore
            .collection('test_expenses')
            .doc(expense.id)
            .set({'amount_fils': subunits, 'currency': expense.currency});
      }

      // Read and verify each document
      for (final expense in expenses) {
        final doc =
            await firestore.collection('test_expenses').doc(expense.id).get();
        final storedSubunits = doc.data()!['amount_fils'] as int;
        final storedCurrency = doc.data()!['currency'] as String;
        final restored = MoneySerializer.fromSubunits(storedSubunits, storedCurrency);
        expect(
          restored,
          equals(expense.amount),
          reason: '${expense.currency} ${expense.amount} round-trip failed',
        );
      }
    });

    test('Firestore document field is stored as int (not double, not String)', () async {
      final amount = Decimal.parse('10.500');
      const currency = 'OMR';

      final subunits = MoneySerializer.toSubunits(amount, currency);
      await firestore
          .collection('test_expenses')
          .doc('type_check')
          .set({'amount_fils': subunits, 'currency': currency});

      final doc =
          await firestore.collection('test_expenses').doc('type_check').get();
      final storedValue = doc.data()!['amount_fils'];

      // Must be int, never double or String
      expect(storedValue, isA<int>());
      expect(storedValue, isNot(isA<double>()));
      expect(storedValue, isNot(isA<String>()));
    });
  });
}
