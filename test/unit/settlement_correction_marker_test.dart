import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/ledger/models/settlement_model.dart';

/// #889: `correctionOfSettlementId` is written ONLY by the server-authoritative
/// correction callables (Admin SDK) — `Settlement.fromFirestore` must read it
/// defensively (a non-string/absent value degrades to null/non-marked, never
/// throws) so a forged/legacy doc can never error the settlement stream, the
/// same fence discipline as the currency read fence (#193/#220).
void main() {
  Map<String, dynamic> doc({Object? correctionOfSettlementId}) {
    final m = <String, dynamic>{
      'id': 's1',
      'eventId': 'event-1',
      'payerParticipantId': 'p1',
      'recipientParticipantId': 'p2',
      'amountFils': 5000,
      'currency': 'OMR',
      'settledAt': DateTime(2026).toIso8601String(),
      'createdBy': 'uid-1',
    };
    if (correctionOfSettlementId != null) {
      m['correctionOfSettlementId'] = correctionOfSettlementId;
    }
    return m;
  }

  group('Settlement.fromFirestore correctionOfSettlementId (#889)', () {
    test('a string marker reads through and marks the row', () {
      final s = Settlement.fromFirestore(
        doc(correctionOfSettlementId: 'original-1'),
      );
      expect(s.correctionOfSettlementId, 'original-1');
      expect(s.isMarkedCorrection, isTrue);
    });

    test('absent marker reads as null / non-marked', () {
      final s = Settlement.fromFirestore(doc());
      expect(s.correctionOfSettlementId, isNull);
      expect(s.isMarkedCorrection, isFalse);
    });

    test('a non-string marker value reads as null, never throws', () {
      expect(
        () => Settlement.fromFirestore(doc(correctionOfSettlementId: 42)),
        returnsNormally,
      );
      final s = Settlement.fromFirestore(
        doc(correctionOfSettlementId: 42),
      );
      expect(s.correctionOfSettlementId, isNull);
      expect(s.isMarkedCorrection, isFalse);
    });

    test('an empty-string marker reads through but does NOT mark the row', () {
      final s = Settlement.fromFirestore(doc(correctionOfSettlementId: ''));
      expect(s.correctionOfSettlementId, '');
      expect(s.isMarkedCorrection, isFalse);
    });

    test('a whitespace-only marker does NOT mark the row', () {
      final s = Settlement.fromFirestore(doc(correctionOfSettlementId: '   '));
      expect(s.isMarkedCorrection, isFalse);
    });
  });

  group('Settlement constructor / isMarkedCorrection', () {
    test('constructor defaults correctionOfSettlementId to null', () {
      final s = Settlement(
        id: 's1',
        tripId: 'event-1',
        amount: Decimal.zero,
        settledAt: DateTime(2026),
      );
      expect(s.correctionOfSettlementId, isNull);
      expect(s.isMarkedCorrection, isFalse);
    });

    test('a non-blank constructor value marks the row', () {
      final s = Settlement(
        id: 's1',
        tripId: 'event-1',
        amount: Decimal.zero,
        settledAt: DateTime(2026),
        correctionOfSettlementId: 'original-1',
      );
      expect(s.isMarkedCorrection, isTrue);
    });
  });
}
