import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/ledger/models/settlement_model.dart';

/// #193 client tail (#220): `Settlement.fromFirestore` must not throw on an
/// unsupported currency. `MoneySerializer.fromSubunits` throws `ArgumentError`
/// for an unknown code, so a single pre-existing / forged settlement doc would
/// otherwise error the entire settle-up stream for every member. The read path
/// fences the currency with `isSupported` and falls back to OMR — mirroring the
/// expense read fence (#47).
void main() {
  Map<String, dynamic> doc({String? currency, required int amountFils}) {
    final m = <String, dynamic>{
      'id': 's1',
      'eventId': 'event-1',
      'payerParticipantId': 'p1',
      'recipientParticipantId': 'p2',
      'amountFils': amountFils,
      'settledAt': DateTime(2026).toIso8601String(),
      'createdBy': 'uid-1',
    };
    if (currency != null) m['currency'] = currency;
    return m;
  }

  group('Settlement.fromFirestore currency read fence (#193 / #220)', () {
    test('supported USD decodes at 2dp', () {
      final s = Settlement.fromFirestore(doc(currency: 'USD', amountFils: 999));
      expect(s.amount, Decimal.parse('9.99'));
    });

    test('supported OMR decodes at 3dp', () {
      final s = Settlement.fromFirestore(
        doc(currency: 'OMR', amountFils: 10500),
      );
      expect(s.amount, Decimal.parse('10.500'));
    });

    test('unsupported currency does NOT throw — OMR-scale fallback', () {
      expect(
        () => Settlement.fromFirestore(doc(currency: 'XYZ', amountFils: 5000)),
        returnsNormally,
      );
      final s = Settlement.fromFirestore(doc(currency: 'XYZ', amountFils: 5000));
      expect(s.amount, Decimal.parse('5.000'));
    });

    test('missing currency defaults to OMR', () {
      final s = Settlement.fromFirestore(doc(amountFils: 5000));
      expect(s.amount, Decimal.parse('5.000'));
    });

    test('lowercase supported code still decodes (case-insensitive)', () {
      final s = Settlement.fromFirestore(
        doc(currency: 'omr', amountFils: 10500),
      );
      expect(s.amount, Decimal.parse('10.500'));
    });
  });

  // #382 PR-0: the model retains the fence-validated currency the amount was
  // deserialized with, mirroring Expense (#47). The label can never disagree
  // with the scale: a fenced-to-OMR doc retains 'OMR', not its raw value.
  group('Settlement.currency retained from Firestore (#382 PR-0)', () {
    test('USD doc surfaces its currency', () {
      final s = Settlement.fromFirestore(doc(currency: 'USD', amountFils: 999));
      expect(s.currency, 'USD');
      expect(s.amount, Decimal.parse('9.99'));
    });

    test('missing currency retains the OMR default', () {
      final s = Settlement.fromFirestore(doc(amountFils: 5000));
      expect(s.currency, 'OMR');
    });

    test('unsupported currency retains the fence value, not the raw doc', () {
      final s = Settlement.fromFirestore(doc(currency: 'XYZ', amountFils: 5000));
      expect(s.currency, 'OMR');
      expect(s.amount, Decimal.parse('5.000'));
    });

    test('lowercase supported code is retained as-is (rules block it on write)',
        () {
      final s = Settlement.fromFirestore(
        doc(currency: 'omr', amountFils: 10500),
      );
      expect(s.currency, 'omr');
    });

    test('constructor defaults to OMR', () {
      final s = Settlement(
        id: 's1',
        tripId: 'event-1',
        amount: Decimal.zero,
        settledAt: DateTime(2026),
      );
      expect(s.currency, 'OMR');
    });
  });

  // #71: group settlements no longer carry `eventId` on the wire (the
  // eventId==groupId sentinel is retired) — the model's groupId fallback is
  // PERMANENT legacy tolerance and both shapes must decode identically. These
  // pins guard the fallback against future "cleanup".
  group('Settlement.fromFirestore group-scope eventId tolerance (#71)', () {
    Map<String, dynamic> groupDoc({bool legacySentinel = false}) {
      final m = <String, dynamic>{
        'id': 'gs1',
        'groupId': 'group-1',
        'scope': 'group',
        'payerParticipantId': 'p1',
        'recipientParticipantId': 'p2',
        'amountFils': 5000,
        'currency': 'OMR',
        'settledAt': DateTime(2026).toIso8601String(),
        'createdBy': 'uid-1',
      };
      if (legacySentinel) m['eventId'] = 'group-1';
      return m;
    }

    test('post-#71 shape (no eventId) decodes tripId == groupId', () {
      final s = Settlement.fromFirestore(groupDoc());
      expect(s.tripId, 'group-1');
      expect(s.groupId, 'group-1');
      expect(s.scope, 'group');
    });

    test('legacy sentinel shape (eventId == groupId) decodes identically', () {
      final legacy = Settlement.fromFirestore(groupDoc(legacySentinel: true));
      final modern = Settlement.fromFirestore(groupDoc());
      expect(legacy.tripId, modern.tripId);
      expect(legacy.groupId, modern.groupId);
      expect(legacy.scope, modern.scope);
      expect(legacy.amount, modern.amount);
    });
  });
}
