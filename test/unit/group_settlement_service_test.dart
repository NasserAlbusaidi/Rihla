import 'package:cloud_functions/cloud_functions.dart';
import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/groups/services/group_settlement_service.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';

import '../helpers/recording_functions_service.dart';

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

  group('GroupSettlementService → recordSettlement wire contract (#1129)', () {
    late RecordingFunctionsService functions;
    late GroupSettlementService service;

    setUp(() {
      functions = RecordingFunctionsService();
      service = GroupSettlementService.withFirestore(
        FakeFirebaseFirestore(),
        functionsService: functions,
      );
    });

    test('addGroupSettlement sends mode=group with NO eventId and NO legs', () async {
      final result = await service.addGroupSettlement(
        groupId: 'g1',
        payerParticipantId: 'p1',
        recipientParticipantId: 'p2',
        amount: Decimal.parse('10.500'),
        currency: 'OMR',
        observedPairEpoch: 2,
        note: 'group settle',
        payerName: 'Ali',
        recipientName: 'Sara',
      );

      expect(functions.recordSettlementCalls, hasLength(1));
      expect(functions.lastCall, {
        'groupId': 'g1',
        'mode': 'group',
        'eventId': null,
        'payerParticipantId': 'p1',
        'recipientParticipantId': 'p2',
        'amountFils': 10500,
        'currency': 'OMR',
        'note': 'group settle',
        'payerName': 'Ali',
        'recipientName': 'Sara',
        'observedPairEpoch': 2,
        'legs': null,
      });
      expect(result.alreadyRecorded, isFalse);
    });

    test(
      'recordDecomposedSettleUp sends mode=groupSettleUp with the TOTAL and '
      'per-leg integer subunits in caller (eventOrder) order',
      () async {
        await service.recordDecomposedSettleUp(
          groupId: 'g1',
          eventLegs: [
            (eventId: 'e2', amount: Decimal.parse('3.000')),
            (eventId: 'e1', amount: Decimal.parse('2.500')),
          ],
          amount: Decimal.parse('7.000'),
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
          currency: 'OMR',
          observedPairEpoch: 5,
          payerName: 'Ali',
          recipientName: 'Sara',
          note: 'trip settle',
        );

        expect(functions.recordSettlementCalls, hasLength(1));
        final call = functions.lastCall;
        expect(call['mode'], 'groupSettleUp');
        expect(call['eventId'], isNull);
        // The total, not Σ legs — the server derives the residual (1.500 here)
        // and re-verifies conservation.
        expect(call['amountFils'], 7000);
        expect(call['observedPairEpoch'], 5);
        // WYSIWYG (#752): legs cross the wire in the caller's eventOrder.
        expect(call['legs'], [
          {'eventId': 'e2', 'amountFils': 3000},
          {'eventId': 'e1', 'amountFils': 2500},
        ]);
      },
    );

    test('recordDecomposedSettleUp JPY legs convert at scale 1', () async {
      await service.recordDecomposedSettleUp(
        groupId: 'g1',
        eventLegs: [(eventId: 'e1', amount: Decimal.parse('250'))],
        amount: Decimal.parse('250'),
        payerParticipantId: 'p1',
        recipientParticipantId: 'p2',
        currency: 'JPY',
        observedPairEpoch: 0,
      );
      expect(functions.lastCall['amountFils'], 250);
      expect(functions.lastCall['legs'], [
        {'eventId': 'e1', 'amountFils': 250},
      ]);
    });

    test('propagates FirebaseFunctionsException unchanged (screens classify it)', () async {
      functions.error = FirebaseFunctionsException(
        message: 'stale',
        code: 'failed-precondition',
        details: const {'kind': 'stale-decomposition'},
      );
      await expectLater(
        service.recordDecomposedSettleUp(
          groupId: 'g1',
          eventLegs: [(eventId: 'e1', amount: Decimal.parse('1.000'))],
          amount: Decimal.parse('1.000'),
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
          currency: 'OMR',
          observedPairEpoch: 0,
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );
    });
  });

  group('GroupSettlementService.watchGroupSettlements (Firestore)', () {
    late FakeFirebaseFirestore fakeDb;
    late GroupSettlementService service;

    Map<String, dynamic> doc(String id, {bool isDeleted = false, String? gsuId}) => {
          'id': id,
          'groupId': 'g1',
          'eventId': 'g1', // sentinel — group settlements have no eventId
          'scope': 'group',
          'payerParticipantId': 'p1',
          'recipientParticipantId': 'p2',
          'amountFils': 10500,
          'currency': 'OMR',
          'note': null,
          'payerName': 'Ali',
          'recipientName': 'Sara',
          'isDeleted': isDeleted,
          'deletedAt': isDeleted ? '2026-07-11T10:00:00.000Z' : null,
          'settledAt': '2026-07-11T09:00:00.000Z',
          'createdBy': 'test-uid',
          'groupSettleUpId': ?gsuId,
        };

    Future<void> seed(Map<String, dynamic> data) => fakeDb
        .collection('groups')
        .doc('g1')
        .collection('settlements')
        .doc(data['id'] as String)
        .set(data);

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      // No functions fake on purpose: the read path must never touch the
      // callable seam (the lazy default would throw [core/no-app] here).
      service = GroupSettlementService.withFirestore(fakeDb);
    });

    test('streams non-deleted group settlements with scope/groupId intact', () async {
      await seed(doc('gs1'));

      final settlements = await service.watchGroupSettlements('g1').first;

      expect(settlements, hasLength(1));
      expect(settlements.first.scope, 'group');
      expect(settlements.first.groupId, 'g1');
      expect(settlements.first.amount, Decimal.parse('10.500'));
    });

    test('filters out legacy soft-deleted rows (isDeleted=true)', () async {
      await seed(doc('gs2', isDeleted: true));

      final settlements = await service.watchGroupSettlements('g1').first;

      expect(settlements, isEmpty);
    });

    test('surfaces groupSettleUpId on decomposed residual rows (#752)', () async {
      await seed(doc('gs3', gsuId: 'sd1abc'));

      final settlements = await service.watchGroupSettlements('g1').first;

      expect(settlements.single.groupSettleUpId, 'sd1abc');
    });
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
  });
}
