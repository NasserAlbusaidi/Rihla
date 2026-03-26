import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/groups/services/group_settlement_service.dart';

void main() {
  group('Settlement model scope fields', () {
    test(
      'fromFirestore with scope=group and groupId produces scope=group Settlement',
      () {
        final data = {
          'id': 'settle1',
          'eventId': 'groupId1',
          'groupId': 'groupId1',
          'scope': 'group',
          'payerParticipantId': 'p1',
          'recipientParticipantId': 'p2',
          'amountFils': 10500,
          'currency': 'OMR',
          'settledAt': DateTime.now().toUtc().toIso8601String(),
          'isDeleted': false,
          'deletedAt': null,
          'note': null,
        };

        final settlement = Settlement.fromFirestore(data);

        expect(settlement.scope, equals('group'));
        expect(settlement.groupId, equals('groupId1'));
      },
    );

    test(
      'fromFirestore with no scope field defaults to scope=event (backward compat)',
      () {
        final data = {
          'id': 'settle1',
          'eventId': 'event1',
          'payerParticipantId': 'p1',
          'recipientParticipantId': 'p2',
          'amountFils': 5000,
          'currency': 'OMR',
          'settledAt': DateTime.now().toUtc().toIso8601String(),
          'isDeleted': false,
          'deletedAt': null,
          'note': null,
        };

        final settlement = Settlement.fromFirestore(data);

        expect(settlement.scope, equals('event'));
        expect(settlement.groupId, isNull);
      },
    );

    test(
      'toFirestore for scope=group includes scope=group and groupId',
      () {
        final settlement = Settlement(
          id: 'settle1',
          tripId: 'groupId1',
          amount: Decimal.parse('10.500'),
          settledAt: DateTime.now().toUtc(),
          scope: 'group',
          groupId: 'groupId1',
        );

        final map = settlement.toFirestore();

        expect(map['scope'], equals('group'));
        expect(map['groupId'], equals('groupId1'));
      },
    );
  });

  group('GroupSettlementService (Firestore)', () {
    late FakeFirebaseFirestore fakeDb;
    late GroupSettlementService service;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      service = GroupSettlementService.withFirestore(fakeDb);
    });

    const groupId = 'g1';

    test(
      'watchGroupSettlements returns stream from groups/{groupId}/settlements path',
      () async {
        // Write a settlement directly to the expected path
        await fakeDb
            .collection('groups')
            .doc(groupId)
            .collection('settlements')
            .doc('settle1')
            .set({
          'id': 'settle1',
          'groupId': groupId,
          'eventId': groupId,
          'scope': 'group',
          'payerParticipantId': 'p1',
          'recipientParticipantId': 'p2',
          'amountFils': 10500,
          'currency': 'OMR',
          'note': null,
          'payerName': null,
          'recipientName': null,
          'isDeleted': false,
          'deletedAt': null,
          'settledAt': DateTime.now().toUtc().toIso8601String(),
        });

        final settlements =
            await service.watchGroupSettlements(groupId).first;

        expect(settlements, hasLength(1));
        expect(settlements.first.scope, equals('group'));
        expect(settlements.first.groupId, equals(groupId));
      },
    );

    test(
      'addGroupSettlement writes document with scope=group and groupId',
      () async {
        final settlement = await service.addGroupSettlement(
          groupId: groupId,
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
          amount: Decimal.parse('10.500'),
        );

        final snap = await fakeDb
            .collection('groups')
            .doc(groupId)
            .collection('settlements')
            .doc(settlement.id)
            .get();

        expect(snap.exists, isTrue);
        expect(snap.data()!['scope'], equals('group'));
        expect(snap.data()!['groupId'], equals(groupId));
      },
    );

    test(
      'addGroupSettlement stores amount via MoneySerializer.toSubunits',
      () async {
        // OMR 10.500 = 10500 fils
        final settlement = await service.addGroupSettlement(
          groupId: groupId,
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
          amount: Decimal.parse('10.500'),
        );

        final snap = await fakeDb
            .collection('groups')
            .doc(groupId)
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
}
