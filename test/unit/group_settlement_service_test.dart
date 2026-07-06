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
          createdBy: 'test-uid',
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
          createdBy: 'test-uid',
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

    // #889: correctionOfSettlementId is Admin-only, written solely by the
    // server correction callables. addGroupSettlement has no such parameter,
    // so a normal forward write can never carry it — even when the caller's
    // note happens to equal the localized correction sentinel.
    test(
      'a normal write omits correctionOfSettlementId, even when note '
      'equals the correction sentinel',
      () async {
        final settlement = await service.addGroupSettlement(
          createdBy: 'test-uid',
          groupId: groupId,
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
          amount: Decimal.parse('10.500'),
          note: 'Correction of a recorded payment', // en sentinel
        );

        final snap = await fakeDb
            .collection('groups')
            .doc(groupId)
            .collection('settlements')
            .doc(settlement.id)
            .get();

        expect(snap.data(), isNot(contains('correctionOfSettlementId')));
        expect(settlement.isMarkedCorrection, isFalse);
      },
    );
  });

  // #929: buildGroupSettlementDoc is the SINGLE source of the group-settlement
  // write shape (addGroupSettlement AND the atomic decompose residual both call
  // it). These pin the exact 16-key map (with the eventId:groupId sentinel +
  // scope:'group') and that addGroupSettlement stays byte-identical to it.
  group('buildGroupSettlementDoc single-source shape (#929)', () {
    test('produces the exact 16-key group-settlement doc', () {
      final settledAt = DateTime.utc(2026, 4, 2, 8, 15);
      final doc = GroupSettlementService.buildGroupSettlementDoc(
        id: 'gset-1',
        groupId: 'g1',
        payerParticipantId: 'p1',
        recipientParticipantId: 'p2',
        amount: Decimal.parse('10.500'),
        createdBy: 'uid',
        currency: 'OMR',
        settledAtUtc: settledAt,
        payerName: 'Ali',
        recipientName: 'Sara',
        note: 'residual',
        groupSettleUpId: 'su-1',
      );

      expect(doc, {
        'id': 'gset-1',
        'groupId': 'g1',
        'eventId': 'g1', // sentinel — group settlements have no eventId
        'scope': 'group',
        'payerParticipantId': 'p1',
        'recipientParticipantId': 'p2',
        'amountFils': 10500,
        'currency': 'OMR',
        'note': 'residual',
        'payerName': 'Ali',
        'recipientName': 'Sara',
        'isDeleted': false,
        'deletedAt': null,
        'settledAt': settledAt.toIso8601String(),
        'createdBy': 'uid',
        'groupSettleUpId': 'su-1',
      });
    });

    test('omits groupSettleUpId when null', () {
      final doc = GroupSettlementService.buildGroupSettlementDoc(
        id: 'gset-1',
        groupId: 'g1',
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
      'addGroupSettlement persists exactly buildGroupSettlementDoc output '
      '(byte parity)',
      () async {
        final fakeDb = FakeFirebaseFirestore();
        final service = GroupSettlementService.withFirestore(fakeDb);
        final s = await service.addGroupSettlement(
          createdBy: 'uid',
          groupId: 'g1',
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
            .collection('settlements')
            .doc(s.id)
            .get();
        final persisted = snap.data()!;
        final expected = GroupSettlementService.buildGroupSettlementDoc(
          id: persisted['id'] as String,
          groupId: 'g1',
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
    test('fromFirestore reads groupSettleUpId when present', () {
      final s = Settlement.fromFirestore({
        'id': 's1',
        'eventId': 'e1',
        'payerParticipantId': 'p1',
        'recipientParticipantId': 'p2',
        'amountFils': 1000,
        'currency': 'OMR',
        'settledAt': DateTime.now().toUtc().toIso8601String(),
        'isDeleted': false,
        'deletedAt': null,
        'note': null,
        'groupSettleUpId': 'su-9',
      });
      expect(s.groupSettleUpId, equals('su-9'));
    });

    test('fromFirestore groupSettleUpId is null when absent (legacy)', () {
      final s = Settlement.fromFirestore({
        'id': 's1',
        'eventId': 'e1',
        'payerParticipantId': 'p1',
        'recipientParticipantId': 'p2',
        'amountFils': 1000,
        'currency': 'OMR',
        'settledAt': DateTime.now().toUtc().toIso8601String(),
        'isDeleted': false,
        'deletedAt': null,
        'note': null,
      });
      expect(s.groupSettleUpId, isNull);
    });

    test('addGroupSettlement writes groupSettleUpId when provided', () async {
      final fakeDb = FakeFirebaseFirestore();
      final service = GroupSettlementService.withFirestore(fakeDb);
      final s = await service.addGroupSettlement(
        createdBy: 'uid',
        groupId: 'g1',
        payerParticipantId: 'p1',
        recipientParticipantId: 'p2',
        amount: Decimal.parse('2.000'),
        groupSettleUpId: 'su-7',
      );
      final snap = await fakeDb
          .collection('groups')
          .doc('g1')
          .collection('settlements')
          .doc(s.id)
          .get();
      expect(snap.data()!['groupSettleUpId'], equals('su-7'));
      expect(s.groupSettleUpId, equals('su-7'));
    });

    test('addGroupSettlement omits groupSettleUpId key when null', () async {
      final fakeDb = FakeFirebaseFirestore();
      final service = GroupSettlementService.withFirestore(fakeDb);
      final s = await service.addGroupSettlement(
        createdBy: 'uid',
        groupId: 'g1',
        payerParticipantId: 'p1',
        recipientParticipantId: 'p2',
        amount: Decimal.parse('2.000'),
      );
      final snap = await fakeDb
          .collection('groups')
          .doc('g1')
          .collection('settlements')
          .doc(s.id)
          .get();
      expect(snap.data()!.containsKey('groupSettleUpId'), isFalse);
      expect(s.groupSettleUpId, isNull);
    });
  });
}
