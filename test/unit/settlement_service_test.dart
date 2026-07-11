import 'package:cloud_functions/cloud_functions.dart';
import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';

import '../helpers/recording_functions_service.dart';

Map<String, dynamic> _settlementDoc({
  required String id,
  required String eventId,
  String payer = 'p1',
  String recipient = 'p2',
  int amountFils = 5000,
  String currency = 'OMR',
  String? payerName,
  String? recipientName,
  String? note,
  bool isDeleted = false,
}) {
  return {
    'id': id,
    'eventId': eventId,
    'payerParticipantId': payer,
    'recipientParticipantId': recipient,
    'payerName': payerName,
    'recipientName': recipientName,
    'amountFils': amountFils,
    'currency': currency,
    'note': note,
    'isDeleted': isDeleted,
    'deletedAt': isDeleted ? '2026-07-11T10:00:00.000Z' : null,
    'settledAt': '2026-07-11T09:00:00.000Z',
    'createdBy': 'test-uid',
  };
}

void main() {
  group('SettlementService.addSettlement → recordSettlement wire contract (#1129)', () {
    late RecordingFunctionsService functions;
    late SettlementService service;

    setUp(() {
      functions = RecordingFunctionsService();
      service = SettlementService.withFirestore(
        FakeFirebaseFirestore(),
        functionsService: functions,
      );
    });

    test('sends mode=event with every field and integer-subunit amount (OMR 3dp)', () async {
      final result = await service.addSettlement(
        groupId: 'g1',
        eventId: 'e1',
        payerParticipantId: 'p1',
        recipientParticipantId: 'p2',
        amount: Decimal.parse('10.500'),
        currency: 'OMR',
        observedPairEpoch: 3,
        payerName: 'Ali',
        recipientName: 'Sara',
        note: 'lunch',
      );

      expect(functions.recordSettlementCalls, hasLength(1));
      expect(functions.lastCall, {
        'groupId': 'g1',
        'mode': 'event',
        'eventId': 'e1',
        'payerParticipantId': 'p1',
        'recipientParticipantId': 'p2',
        'amountFils': 10500,
        'currency': 'OMR',
        'note': 'lunch',
        'payerName': 'Ali',
        'recipientName': 'Sara',
        'observedPairEpoch': 3,
        'legs': null,
      });
      // The callable's result is returned verbatim — the screens branch on it.
      expect(result.alreadyRecorded, isFalse);
      expect(result.shouldBumpLedgerRevision, isTrue);
    });

    test('JPY converts at scale 1 (no fractional subunits invented)', () async {
      await service.addSettlement(
        groupId: 'g1',
        eventId: 'e1',
        payerParticipantId: 'p1',
        recipientParticipantId: 'p2',
        amount: Decimal.parse('250'),
        currency: 'JPY',
        observedPairEpoch: 0,
      );
      expect(functions.lastCall['amountFils'], 250);
      expect(functions.lastCall['currency'], 'JPY');
    });

    test('optional fields default to null on the wire', () async {
      await service.addSettlement(
        groupId: 'g1',
        eventId: 'e1',
        payerParticipantId: 'p1',
        recipientParticipantId: 'p2',
        amount: Decimal.parse('1.000'),
        currency: 'OMR',
        observedPairEpoch: 0,
      );
      expect(functions.lastCall['note'], isNull);
      expect(functions.lastCall['payerName'], isNull);
      expect(functions.lastCall['recipientName'], isNull);
    });

    test('propagates FirebaseFunctionsException unchanged (screens classify it)', () async {
      functions.error = FirebaseFunctionsException(
        message: 'cap',
        code: 'failed-precondition',
        details: const {
          'kind': 'over-outstanding',
          'outstandingFils': 400,
          'currency': 'OMR',
        },
      );
      await expectLater(
        service.addSettlement(
          groupId: 'g1',
          eventId: 'e1',
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
          amount: Decimal.parse('1.000'),
          currency: 'OMR',
          observedPairEpoch: 0,
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      // The doomed payload was still well-formed — nothing was half-sent.
      expect(functions.recordSettlementCalls, hasLength(1));
    });
  });

  group('SettlementService.directedPairEpoch', () {
    Settlement s(String payer, String recipient) =>
        Settlement.fromFirestore(_settlementDoc(
          id: 'sid-$payer-$recipient-x',
          eventId: 'e1',
          payer: payer,
          recipient: recipient,
        ));

    test('counts only the DIRECTED pair — reverse direction excluded', () {
      final rows = [s('a', 'b'), s('a', 'b'), s('b', 'a'), s('a', 'c')];
      expect(
        SettlementService.directedPairEpoch(
          rows,
          payerParticipantId: 'a',
          recipientParticipantId: 'b',
        ),
        2,
      );
      expect(
        SettlementService.directedPairEpoch(
          rows,
          payerParticipantId: 'b',
          recipientParticipantId: 'a',
        ),
        1,
      );
    });

    test('empty basis → epoch 0', () {
      expect(
        SettlementService.directedPairEpoch(
          const <Settlement>[],
          payerParticipantId: 'a',
          recipientParticipantId: 'b',
        ),
        0,
      );
    });

    test('pure: counts exactly the list given (no hidden isDeleted filter)', () {
      // Callers feed provider-filtered rows; the function itself must not
      // second-guess them or two devices could diverge on the epoch.
      final deleted = Settlement.fromFirestore(_settlementDoc(
        id: 'sid-del',
        eventId: 'e1',
        payer: 'a',
        recipient: 'b',
        isDeleted: true,
      ));
      expect(
        SettlementService.directedPairEpoch(
          [deleted],
          payerParticipantId: 'a',
          recipientParticipantId: 'b',
        ),
        1,
      );
    });
  });

  group('SettlementService reads (Firestore)', () {
    late FakeFirebaseFirestore fakeDb;
    late SettlementService service;

    Future<void> seed(Map<String, dynamic> doc) => fakeDb
        .collection('groups')
        .doc('g1')
        .collection('events')
        .doc('e1')
        .collection('settlements')
        .doc(doc['id'] as String)
        .set(doc);

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      // No functions fake on purpose: the read paths must never touch the
      // callable seam (constructing the default lazily would throw
      // [core/no-app] here if they did).
      service = SettlementService.withFirestore(fakeDb);
    });

    test('watchSettlements streams non-deleted settlements', () async {
      await seed(_settlementDoc(
        id: 's1',
        eventId: 'e1',
        amountFils: 5000,
        note: 'Test settlement',
      ));

      final settlements = await service.watchSettlements('g1', 'e1').first;

      expect(settlements, hasLength(1));
      expect(settlements.first.note, 'Test settlement');
      expect(settlements.first.amount, Decimal.parse('5.000'));
    });

    test('round-trips payer and recipient names', () async {
      await seed(_settlementDoc(
        id: 's2',
        eventId: 'e1',
        payer: 'uid-ali',
        recipient: 'uid-sara',
        payerName: 'Ali',
        recipientName: 'Sara',
        amountFils: 7250,
      ));

      final settlements = await service.watchSettlements('g1', 'e1').first;

      expect(settlements, hasLength(1));
      expect(settlements.first.payerName, 'Ali');
      expect(settlements.first.recipientName, 'Sara');
      expect(settlements.first.amount, Decimal.parse('7.250'));
    });

    test('filters out legacy soft-deleted settlements (isDeleted=true)', () async {
      // E3 / B3: settlements are append-only; this pins that the stream still
      // filters any pre-B3 records that legitimately had isDeleted set.
      await seed(_settlementDoc(id: 's3', eventId: 'e1', isDeleted: true));

      final settlements = await service.watchSettlements('g1', 'e1').first;

      expect(settlements, isEmpty);
    });

    test('getSettlements one-shot matches the stream query (#104)', () async {
      await seed(_settlementDoc(id: 's4', eventId: 'e1', amountFils: 1250));
      await seed(_settlementDoc(id: 's5', eventId: 'e1', isDeleted: true));

      final settlements = await service.getSettlements('g1', 'e1');

      expect(settlements, hasLength(1));
      expect(settlements.first.id, 's4');
    });

    test('fromFirestore round-trip preserves id/amount/note', () async {
      await seed(_settlementDoc(
        id: 's6',
        eventId: 'e1',
        amountFils: 10500,
        note: 'Round trip test',
      ));

      final snap = await fakeDb
          .collection('groups')
          .doc('g1')
          .collection('events')
          .doc('e1')
          .collection('settlements')
          .doc('s6')
          .get();
      final restored = Settlement.fromFirestore({...snap.data()!, 'id': snap.id});

      expect(restored.id, 's6');
      expect(restored.amount, Decimal.parse('10.500'));
      expect(restored.note, 'Round trip test');
      expect(restored.isDeleted, isFalse);
    });
  });
}
