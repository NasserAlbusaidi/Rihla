import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/groups/services/group_settlement_service.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';

// Hand-rolled spy WriteBatch. mocktail cannot cleanly match the generic
// `set<T>` with its optional [SetOptions] (the group_service #874 test hit the
// same wall), so we implement set<T> directly, capture (ref, data) pairs, count
// commit(), and return a caller-supplied future to model offline/never-acking.
class _SpyWriteBatch implements WriteBatch {
  _SpyWriteBatch(this._commit);
  final Future<void> _commit;
  final sets =
      <({DocumentReference<Object?> ref, Map<String, dynamic> data})>[];
  int commitCount = 0;

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    sets.add((ref: document, data: data as Map<String, dynamic>));
  }

  @override
  Future<void> commit() {
    commitCount++;
    return _commit;
  }

  @override
  void delete(DocumentReference<Object?> document) {}

  @override
  void update(DocumentReference<Object?> document, Map<Object, Object?> data) {}
}

void main() {
  late FakeFirebaseFirestore fake;
  late GroupSettlementService service;
  late _SpyWriteBatch batch;
  late Completer<void> commitCompleter;

  setUp(() {
    fake = FakeFirebaseFirestore();
    service = GroupSettlementService.withFirestore(fake);
    commitCompleter = Completer<void>();
    batch = _SpyWriteBatch(commitCompleter.future);
    service.batchFactoryOverride = () => batch;
  });

  group('stageDecomposedSettleUp mechanism pin (#929)', () {
    test(
      '2 event legs + residual → exactly 3 batch.set + ONE commit; ack IS the '
      'commit future; every doc came from the shared builders + one settledAt',
      () {
        final result = service.stageDecomposedSettleUp(
          groupId: 'g1',
          eventLegs: [
            (eventId: 'e1', amount: Decimal.parse('4.000')),
            (eventId: 'e2', amount: Decimal.parse('3.000')),
          ],
          residual: Decimal.parse('2.000'),
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
          currency: 'OMR',
          createdBy: 'uid',
          groupSettleUpId: 'su-1',
          payerName: 'Ali',
          recipientName: 'Sara',
          note: 'n',
        );

        // The caller races the commit future directly — no awaiting inside.
        expect(identical(result.ack, commitCompleter.future), isTrue);
        expect(result.staged, hasLength(3));
        expect(batch.commitCount, 1);
        expect(batch.sets, hasLength(3));

        final data1 = batch.sets[0].data;
        final data2 = batch.sets[1].data;
        final data3 = batch.sets[2].data;

        // 2 event subcollection paths (in eventOrder) + 1 group settlements path.
        expect(
          batch.sets[0].ref.path,
          'groups/g1/events/e1/settlements/${data1['id']}',
        );
        expect(
          batch.sets[1].ref.path,
          'groups/g1/events/e2/settlements/${data2['id']}',
        );
        expect(
          batch.sets[2].ref.path,
          'groups/g1/settlements/${data3['id']}',
        );

        // Every staged doc is byte-equal to its single-source builder output.
        expect(
          data1,
          SettlementService.buildSettlementDoc(
            id: data1['id'] as String,
            eventId: 'e1',
            payerParticipantId: 'p1',
            recipientParticipantId: 'p2',
            amount: Decimal.parse('4.000'),
            createdBy: 'uid',
            currency: 'OMR',
            settledAtUtc: DateTime.parse(data1['settledAt'] as String),
            payerName: 'Ali',
            recipientName: 'Sara',
            note: 'n',
            groupSettleUpId: 'su-1',
          ),
        );
        expect(
          data3,
          GroupSettlementService.buildGroupSettlementDoc(
            id: data3['id'] as String,
            groupId: 'g1',
            payerParticipantId: 'p1',
            recipientParticipantId: 'p2',
            amount: Decimal.parse('2.000'),
            createdBy: 'uid',
            currency: 'OMR',
            settledAtUtc: DateTime.parse(data3['settledAt'] as String),
            payerName: 'Ali',
            recipientName: 'Sara',
            note: 'n',
            groupSettleUpId: 'su-1',
          ),
        );

        // ONE shared settledAt across all N+1 legs.
        expect(data2['settledAt'], data1['settledAt']);
        expect(data3['settledAt'], data1['settledAt']);
      },
    );

    test('zero residual → exactly 2 set + ONE commit, staged length 2', () {
      final result = service.stageDecomposedSettleUp(
        groupId: 'g1',
        eventLegs: [
          (eventId: 'e1', amount: Decimal.parse('4.000')),
          (eventId: 'e2', amount: Decimal.parse('3.000')),
        ],
        residual: Decimal.zero,
        payerParticipantId: 'p1',
        recipientParticipantId: 'p2',
        currency: 'OMR',
        createdBy: 'uid',
        groupSettleUpId: 'su-1',
      );

      expect(result.staged, hasLength(2));
      expect(batch.sets, hasLength(2));
      expect(batch.commitCount, 1);
    });

    test('empty createdBy → synchronous ArgumentError, zero batch interaction',
        () {
      expect(
        () => service.stageDecomposedSettleUp(
          groupId: 'g1',
          eventLegs: [(eventId: 'e1', amount: Decimal.parse('1.000'))],
          residual: Decimal.zero,
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
          currency: 'OMR',
          createdBy: '',
          groupSettleUpId: 'su-1',
        ),
        throwsArgumentError,
      );
      expect(batch.sets, isEmpty);
      expect(batch.commitCount, 0);
    });

    test(
      'over-cap eventLegs (> kMaxDecomposeLegsAtomic) → ArgumentError, no batch',
      () {
        final tooManyLegs = [
          for (var i = 0; i < kMaxDecomposeLegsAtomic + 1; i++)
            (eventId: 'e$i', amount: Decimal.parse('1.000')),
        ];
        expect(
          () => service.stageDecomposedSettleUp(
            groupId: 'g1',
            eventLegs: tooManyLegs,
            residual: Decimal.zero,
            payerParticipantId: 'p1',
            recipientParticipantId: 'p2',
            currency: 'OMR',
            createdBy: 'uid',
            groupSettleUpId: 'su-1',
          ),
          throwsArgumentError,
        );
        expect(batch.sets, isEmpty);
        expect(batch.commitCount, 0);
      },
    );
  });
}
