import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';

void main() {
  group('SettlementService (Firestore)', () {
    late FakeFirebaseFirestore fakeDb;
    late SettlementService service;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      service = SettlementService.withFirestore(fakeDb);
    });

    group('addSettlement', () {
      test(
        'writes settlement document to groups/{groupId}/events/{eventId}/settlements',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          final settlement = await service.addSettlement(
            createdBy: 'test-uid',
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: 'p1',
            recipientParticipantId: 'p2',
            amount: Decimal.parse('10.500'),
          );

          final snap = await fakeDb
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('settlements')
              .doc(settlement.id)
              .get();

          expect(snap.exists, isTrue);
          expect(snap.data()!['eventId'], equals(eventId));
          expect(snap.data()!['payerParticipantId'], equals('p1'));
          expect(snap.data()!['recipientParticipantId'], equals('p2'));
          expect(snap.data()!['isDeleted'], isFalse);
        },
      );

      // #889: correctionOfSettlementId is Admin-only, written solely by the
      // server correction callables. addSettlement has no such parameter, so
      // a normal forward write can never carry it — even when the caller's
      // note happens to equal the localized correction sentinel (a normal
      // payment note is NOT a safe discriminator, which is the whole reason
      // #889 exists).
      test(
        'a normal write omits correctionOfSettlementId, even when note '
        'equals the correction sentinel',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          final settlement = await service.addSettlement(
            createdBy: 'test-uid',
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: 'p1',
            recipientParticipantId: 'p2',
            amount: Decimal.parse('10.500'),
            note: 'Correction of a recorded payment', // en sentinel
          );

          final snap = await fakeDb
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('settlements')
              .doc(settlement.id)
              .get();

          expect(snap.data(), isNot(contains('correctionOfSettlementId')));
          expect(settlement.isMarkedCorrection, isFalse);
        },
      );

      test('uses MoneySerializer.toSubunits to store amountFils', () async {
        const groupId = 'g1';
        const eventId = 'e1';

        // OMR 10.500 = 10500 fils
        final settlement = await service.addSettlement(
          createdBy: 'test-uid',
          groupId: groupId,
          eventId: eventId,
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
          amount: Decimal.parse('10.500'),
        );

        final snap = await fakeDb
            .collection('groups')
            .doc(groupId)
            .collection('events')
            .doc(eventId)
            .collection('settlements')
            .doc(settlement.id)
            .get();

        expect(snap.data()!['amountFils'], equals(10500));
        expect(snap.data()!['currency'], equals('OMR'));

        // Verify round-trip
        expect(settlement.amount, equals(Decimal.parse('10.500')));
      });
    });

    group('watchSettlements', () {
      test(
        'returns a stream of settlements from Firestore subcollection',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          await service.addSettlement(
            createdBy: 'test-uid',
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: 'p1',
            recipientParticipantId: 'p2',
            amount: Decimal.parse('5.000'),
            note: 'Test settlement',
          );

          final settlements = await service
              .watchSettlements(groupId, eventId)
              .first;

          expect(settlements, hasLength(1));
          expect(settlements.first.note, equals('Test settlement'));
          expect(settlements.first.amount, equals(Decimal.parse('5.000')));
        },
      );

      test('round-trips payer and recipient names through Firestore', () async {
        const groupId = 'g1';
        const eventId = 'e1';

        await service.addSettlement(
          createdBy: 'test-uid',
          groupId: groupId,
          eventId: eventId,
          payerParticipantId: 'uid-ali',
          recipientParticipantId: 'uid-sara',
          payerName: 'Ali',
          recipientName: 'Sara',
          amount: Decimal.parse('7.250'),
        );

        final settlements = await service
            .watchSettlements(groupId, eventId)
            .first;

        expect(settlements, hasLength(1));
        expect(settlements.first.payerName, equals('Ali'));
        expect(settlements.first.recipientName, equals('Sara'));
      });

      test(
        'filters out legacy soft-deleted settlements (isDeleted=true)',
        () async {
          // E3 / B3: addSettlement no longer pairs with a deleteSettlement
          // method — settlements are append-only at the rules layer. This
          // test still asserts the watchSettlements stream filters any
          // pre-B3 records that legitimately had isDeleted set, by
          // writing such a row directly through the fake DB.
          const groupId = 'g1';
          const eventId = 'e1';

          final settlement = await service.addSettlement(
            createdBy: 'test-uid',
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: 'p1',
            recipientParticipantId: 'p2',
            amount: Decimal.parse('5.000'),
          );

          await fakeDb
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('settlements')
              .doc(settlement.id)
              .update({
                'isDeleted': true,
                'deletedAt': DateTime.now().toUtc().toIso8601String(),
              });

          final settlements = await service
              .watchSettlements(groupId, eventId)
              .first;

          expect(settlements, isEmpty);
        },
      );
    });

    group('Settlement serialization', () {
      test(
        'fromFirestore and toFirestore round-trip produces equivalent Settlement',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          final original = await service.addSettlement(
            createdBy: 'test-uid',
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: 'p1',
            recipientParticipantId: 'p2',
            amount: Decimal.parse('10.500'),
            note: 'Round trip test',
          );

          final snap = await fakeDb
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('settlements')
              .doc(original.id)
              .get();

          final restored = Settlement.fromFirestore({
            ...snap.data()!,
            'id': snap.id,
          });

          expect(restored.id, equals(original.id));
          expect(restored.amount, equals(original.amount));
          expect(restored.note, equals('Round trip test'));
          expect(restored.isDeleted, isFalse);
        },
      );
    });

    // #929: buildSettlementDoc is the SINGLE source of the event-settlement
    // write shape (addSettlement AND the atomic decompose batch both call it).
    // These pin the exact 14-key map and that addSettlement stays byte-identical
    // to the builder — a revert that inlines a second map turns them red.
    group('buildSettlementDoc single-source shape (#929)', () {
      test('produces the exact 14-key event-settlement doc', () {
        final settledAt = DateTime.utc(2026, 4, 1, 9, 30);
        final doc = SettlementService.buildSettlementDoc(
          id: 'set-1',
          eventId: 'e1',
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
          amount: Decimal.parse('10.500'),
          createdBy: 'uid',
          currency: 'OMR',
          settledAtUtc: settledAt,
          payerName: 'Ali',
          recipientName: 'Sara',
          note: 'dinner',
          groupSettleUpId: 'su-1',
        );

        expect(doc, {
          'id': 'set-1',
          'eventId': 'e1',
          'payerParticipantId': 'p1',
          'recipientParticipantId': 'p2',
          'payerName': 'Ali',
          'recipientName': 'Sara',
          'amountFils': 10500,
          'currency': 'OMR',
          'note': 'dinner',
          'isDeleted': false,
          'deletedAt': null,
          'settledAt': settledAt.toIso8601String(),
          'createdBy': 'uid',
          'groupSettleUpId': 'su-1',
        });
      });

      test('omits groupSettleUpId when null', () {
        final doc = SettlementService.buildSettlementDoc(
          id: 'set-1',
          eventId: 'e1',
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
          amount: Decimal.parse('1.000'),
          createdBy: 'uid',
          currency: 'OMR',
          settledAtUtc: DateTime.utc(2026),
        );
        expect(doc.containsKey('groupSettleUpId'), isFalse);
      });

      test(
        'addSettlement persists exactly buildSettlementDoc output (byte parity)',
        () async {
          final s = await service.addSettlement(
            createdBy: 'uid',
            groupId: 'g1',
            eventId: 'e1',
            payerParticipantId: 'p1',
            recipientParticipantId: 'p2',
            amount: Decimal.parse('7.250'),
            currency: 'OMR',
            payerName: 'Ali',
            recipientName: 'Sara',
            note: 'n',
            groupSettleUpId: 'su-9',
          );
          final snap = await fakeDb
              .collection('groups')
              .doc('g1')
              .collection('events')
              .doc('e1')
              .collection('settlements')
              .doc(s.id)
              .get();
          final persisted = snap.data()!;
          // Rebuild with the id + settledAt addSettlement stamped, then assert
          // the persisted doc equals the builder output field-for-field.
          final expected = SettlementService.buildSettlementDoc(
            id: persisted['id'] as String,
            eventId: 'e1',
            payerParticipantId: 'p1',
            recipientParticipantId: 'p2',
            amount: Decimal.parse('7.250'),
            createdBy: 'uid',
            currency: 'OMR',
            settledAtUtc: DateTime.parse(persisted['settledAt'] as String),
            payerName: 'Ali',
            recipientName: 'Sara',
            note: 'n',
            groupSettleUpId: 'su-9',
          );
          expect(persisted, equals(expected));
        },
      );
    });

    group('groupSettleUpId field (#752)', () {
      test('addSettlement writes groupSettleUpId when provided', () async {
        final s = await service.addSettlement(
          createdBy: 'uid',
          groupId: 'g1',
          eventId: 'e1',
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
          amount: Decimal.parse('3.000'),
          groupSettleUpId: 'su-123',
        );
        final snap = await fakeDb
            .collection('groups')
            .doc('g1')
            .collection('events')
            .doc('e1')
            .collection('settlements')
            .doc(s.id)
            .get();
        expect(snap.data()!['groupSettleUpId'], equals('su-123'));
        expect(s.groupSettleUpId, equals('su-123'));
      });

      test('addSettlement omits groupSettleUpId key when null', () async {
        final s = await service.addSettlement(
          createdBy: 'uid',
          groupId: 'g1',
          eventId: 'e1',
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
          amount: Decimal.parse('3.000'),
        );
        final snap = await fakeDb
            .collection('groups')
            .doc('g1')
            .collection('events')
            .doc('e1')
            .collection('settlements')
            .doc(s.id)
            .get();
        expect(snap.data()!.containsKey('groupSettleUpId'), isFalse);
        expect(s.groupSettleUpId, isNull);
      });
    });
  });
}
