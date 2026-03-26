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

      test(
        'uses MoneySerializer.toSubunits to store amountFils',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          // OMR 10.500 = 10500 fils
          final settlement = await service.addSettlement(
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
        },
      );
    });

    group('watchSettlements', () {
      test(
        'returns a stream of settlements from Firestore subcollection',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          await service.addSettlement(
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

      test(
        'filters out soft-deleted settlements (isDeleted=true)',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          final settlement = await service.addSettlement(
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: 'p1',
            recipientParticipantId: 'p2',
            amount: Decimal.parse('5.000'),
          );

          await service.deleteSettlement(
            groupId: groupId,
            eventId: eventId,
            settlementId: settlement.id,
          );

          final settlements = await service
              .watchSettlements(groupId, eventId)
              .first;

          expect(settlements, isEmpty);
        },
      );
    });

    group('deleteSettlement', () {
      test(
        'uses soft-delete pattern (sets isDeleted=true, deletedAt timestamp)',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          final settlement = await service.addSettlement(
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: 'p1',
            recipientParticipantId: 'p2',
            amount: Decimal.parse('5.000'),
          );

          await service.deleteSettlement(
            groupId: groupId,
            eventId: eventId,
            settlementId: settlement.id,
          );

          final snap = await fakeDb
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('settlements')
              .doc(settlement.id)
              .get();

          expect(snap.data()!['isDeleted'], isTrue);
          expect(snap.data()!['deletedAt'], isNotNull);
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
  });
}
