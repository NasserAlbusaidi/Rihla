import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/firebase_functions_service.dart';

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<dynamic> {}

void main() {
  test(
    'deleteAccount calls the deleteAccount callable with an empty payload',
    () async {
      final (:functions, :callable, :service) = _harness();

      await service.deleteAccount();

      verify(() => functions.httpsCallable('deleteAccount')).called(1);
      final payload = verify(() => callable.call(captureAny())).captured.single;
      expect(payload, isEmpty);
    },
  );

  test(
    'deleteGroup calls the deleteGroup callable with the group id',
    () async {
      final (:functions, :callable, :service) = _harness();

      await service.deleteGroup(groupId: 'group-1');

      verify(() => functions.httpsCallable('deleteGroup')).called(1);
      final payload = verify(() => callable.call(captureAny())).captured.single;
      expect(payload, {'groupId': 'group-1'});
    },
  );

  // -------------------------------------------------------------------------
  // #278 PR9 — claim/merge callables. Each test pins the OUTBOUND payload keys
  // (a wrong key = a callable that fails) AND the INBOUND parse into a typed
  // model (a wrong key = a wrong/blank field in the UI).
  // -------------------------------------------------------------------------
  group('claim/merge callables (#278 PR9)', () {
    test('listUnclaimedShadows sends {inviteCode} and parses shadows', () async {
      final (:functions, :callable, :service) = _harness(
        data: {
          'shadows': [
            {'shadowMemberId': 's1', 'displayName': 'Ali'},
            {'shadowMemberId': 's2', 'displayName': 'Sara'},
          ],
        },
      );

      final shadows = await service.listUnclaimedShadows(inviteCode: 'ABC123');

      verify(() => functions.httpsCallable('listUnclaimedShadows')).called(1);
      final payload = verify(() => callable.call(captureAny())).captured.single;
      expect(payload, {'inviteCode': 'ABC123'});
      expect(
        shadows.map((s) => (s.shadowMemberId, s.displayName)).toList(),
        [('s1', 'Ali'), ('s2', 'Sara')],
      );
    });

    test('requestClaimShadow sends {inviteCode,shadowMemberId,displayName} and parses result', () async {
      final (:functions, :callable, :service) = _harness(
        data: {'requestId': 'claimer__s1', 'status': 'pending', 'groupId': 'g1'},
      );

      final res = await service.requestClaimShadow(
        inviteCode: 'ABC123',
        shadowMemberId: 's1',
        displayName: 'Khalid',
      );

      verify(() => functions.httpsCallable('requestClaimShadow')).called(1);
      final payload = verify(() => callable.call(captureAny())).captured.single;
      expect(payload, {
        'inviteCode': 'ABC123',
        'shadowMemberId': 's1',
        'displayName': 'Khalid',
      });
      expect((res.requestId, res.status, res.groupId), ('claimer__s1', 'pending', 'g1'));
    });

    test('decideClaimRequest sends {groupId,requestId,approve} and parses alreadyClaimed', () async {
      final (:functions, :callable, :service) = _harness(
        data: {'requestId': 'claimer__s1', 'status': 'claimed', 'alreadyClaimed': false},
      );

      final res = await service.decideClaimRequest(
        groupId: 'g1',
        requestId: 'claimer__s1',
        approve: true,
      );

      verify(() => functions.httpsCallable('decideClaimRequest')).called(1);
      final payload = verify(() => callable.call(captureAny())).captured.single;
      expect(payload, {'groupId': 'g1', 'requestId': 'claimer__s1', 'approve': true});
      expect((res.status, res.alreadyClaimed), ('claimed', false));
    });

    test('listMyClaimRequests sends {inviteCode} and parses requests incl. null createdAtMillis', () async {
      final (:functions, :callable, :service) = _harness(
        data: {
          'requests': [
            {
              'requestId': 'r1',
              'shadowMemberId': 's1',
              'shadowDisplayName': 'Ali',
              'status': 'pending',
              'createdAtMillis': 1700000000000,
            },
            {
              'requestId': 'r2',
              'shadowMemberId': 's2',
              'shadowDisplayName': 'Sara',
              'status': 'declined',
              'createdAtMillis': null,
            },
          ],
        },
      );

      final reqs = await service.listMyClaimRequests(inviteCode: 'ABC123');

      verify(() => functions.httpsCallable('listMyClaimRequests')).called(1);
      expect(
        verify(() => callable.call(captureAny())).captured.single,
        {'inviteCode': 'ABC123'},
      );
      expect(
        reqs.map((r) => (r.requestId, r.status, r.createdAtMillis)).toList(),
        [('r1', 'pending', 1700000000000), ('r2', 'declined', null)],
      );
    });

    test('listGroupClaimRequests sends {groupId} and parses requester fields', () async {
      final (:functions, :callable, :service) = _harness(
        data: {
          'requests': [
            {
              'requestId': 'r1',
              'requesterUid': 'u1',
              'requesterDisplayName': 'Khalid',
              'shadowMemberId': 's1',
              'shadowDisplayName': 'Ali',
              'status': 'pending',
              'createdAtMillis': 1700000000000,
            },
          ],
        },
      );

      final reqs = await service.listGroupClaimRequests(groupId: 'g1');

      verify(() => functions.httpsCallable('listGroupClaimRequests')).called(1);
      expect(
        verify(() => callable.call(captureAny())).captured.single,
        {'groupId': 'g1'},
      );
      expect(
        (reqs.single.requesterDisplayName, reqs.single.shadowDisplayName),
        ('Khalid', 'Ali'),
      );
    });
  });

  // -------------------------------------------------------------------------
  // #1129 — recordSettlement, the ONLY settlement CREATE path. Pins the
  // OUTBOUND payload (including that ABSENT optionals are OMITTED, not sent
  // as nulls — the TS callable validates the map shape) AND the INBOUND
  // parse into RecordSettlementResult.
  // -------------------------------------------------------------------------
  group('recordSettlement callable (#1129)', () {
    test(
      'mode=event sends every provided field and parses the result',
      () async {
        final (:functions, :callable, :service) = _harness(
          data: {
            'alreadyRecorded': false,
            'eventScopeWrites': 1,
            'groupScopeWrites': 0,
            'shouldBumpLedgerRevision': true,
            'settledAt': '2026-07-11T12:00:00.000Z',
          },
        );

        final result = await service.recordSettlement(
          groupId: 'g1',
          mode: 'event',
          eventId: 'e1',
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
          amountFils: 10500,
          currency: 'OMR',
          note: 'lunch',
          payerName: 'Ali',
          recipientName: 'Sara',
          observedPairEpoch: 3,
        );

        verify(() => functions.httpsCallable('recordSettlement')).called(1);
        final payload =
            verify(() => callable.call(captureAny())).captured.single;
        expect(payload, {
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
        });
        expect(result.alreadyRecorded, isFalse);
        expect(result.eventScopeWrites, 1);
        expect(result.shouldBumpLedgerRevision, isTrue);
        expect(result.settledAt, '2026-07-11T12:00:00.000Z');
      },
    );

    test(
      'mode=group OMITS absent optionals (eventId/note/names/legs) from the '
      'payload entirely',
      () async {
        final (:functions, :callable, :service) = _harness(
          data: {
            'alreadyRecorded': true,
            'eventScopeWrites': 0,
            'groupScopeWrites': 0,
            'shouldBumpLedgerRevision': false,
            'settledAt': '2026-07-11T12:00:00.000Z',
          },
        );

        final result = await service.recordSettlement(
          groupId: 'g1',
          mode: 'group',
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
          amountFils: 5000,
          currency: 'OMR',
          observedPairEpoch: 0,
        );

        final payload =
            verify(() => callable.call(captureAny())).captured.single;
        expect(payload, {
          'groupId': 'g1',
          'mode': 'group',
          'payerParticipantId': 'p1',
          'recipientParticipantId': 'p2',
          'amountFils': 5000,
          'currency': 'OMR',
          'observedPairEpoch': 0,
        });
        expect(payload, isNot(contains('eventId')));
        expect(payload, isNot(contains('legs')));
        // Idempotent replay flag round-trips (#1093 → alreadyRecorded copy).
        expect(result.alreadyRecorded, isTrue);
        expect(result.shouldBumpLedgerRevision, isFalse);
      },
    );

    test(
      'mode=groupSettleUp sends the legs list in caller order (#752 WYSIWYG)',
      () async {
        final (:functions, :callable, :service) = _harness(
          data: {
            'alreadyRecorded': false,
            'eventScopeWrites': 2,
            'groupScopeWrites': 1,
            'shouldBumpLedgerRevision': true,
            'settledAt': '2026-07-11T12:00:00.000Z',
          },
        );

        await service.recordSettlement(
          groupId: 'g1',
          mode: 'groupSettleUp',
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
          amountFils: 7000,
          currency: 'OMR',
          observedPairEpoch: 5,
          legs: [
            {'eventId': 'e2', 'amountFils': 3000},
            {'eventId': 'e1', 'amountFils': 2500},
          ],
        );

        final payload =
            verify(() => callable.call(captureAny())).captured.single;
        expect(payload['mode'], 'groupSettleUp');
        expect(payload['legs'], [
          {'eventId': 'e2', 'amountFils': 3000},
          {'eventId': 'e1', 'amountFils': 2500},
        ]);
      },
    );

    test('a malformed result degrades fail-safe (never throws)', () async {
      final (:functions, :callable, :service) = _harness(
        data: <String, dynamic>{},
      );

      final result = await service.recordSettlement(
        groupId: 'g1',
        mode: 'event',
        eventId: 'e1',
        payerParticipantId: 'p1',
        recipientParticipantId: 'p2',
        amountFils: 1000,
        currency: 'OMR',
        observedPairEpoch: 0,
      );

      expect(result.alreadyRecorded, isFalse);
      expect(result.eventScopeWrites, 0);
      // Fail toward bumping: a missed bump is a money-wrong home balance.
      expect(result.shouldBumpLedgerRevision, isTrue);
      expect(result.settledAt, '');
    });
  });

  // -------------------------------------------------------------------------
  // #889 — settlement correction callables. Each test pins the OUTBOUND
  // payload keys AND the INBOUND parse into the typed CorrectSettlementResult
  // (the wire shape is shared by both callables).
  // -------------------------------------------------------------------------
  group('settlement correction callables (#889)', () {
    test(
      'correctSettlement sends {groupId,scope,eventId,settlementId,'
      'correctionNote} and parses the result',
      () async {
        final (:functions, :callable, :service) = _harness(
          data: {
            'eventScopeWrites': 1,
            'groupScopeWrites': 0,
            'repaired': false,
            'noop': false,
            'shouldBumpLedgerRevision': true,
          },
        );

        final result = await service.correctSettlement(
          groupId: 'g1',
          scope: 'event',
          eventId: 'e1',
          settlementId: 's1',
          correctionNote: 'Correction of a recorded payment',
        );

        verify(() => functions.httpsCallable('correctSettlement')).called(1);
        final payload =
            verify(() => callable.call(captureAny())).captured.single;
        expect(payload, {
          'groupId': 'g1',
          'scope': 'event',
          'eventId': 'e1',
          'settlementId': 's1',
          'correctionNote': 'Correction of a recorded payment',
        });
        expect(result.eventScopeWrites, 1);
        expect(result.groupScopeWrites, 0);
        expect(result.repaired, isFalse);
        expect(result.noop, isFalse);
        expect(result.shouldBumpLedgerRevision, isTrue);
      },
    );

    test(
      'correctSettlement omits eventId from the payload for scope: group',
      () async {
        final (:functions, :callable, :service) = _harness(
          data: {
            'eventScopeWrites': 0,
            'groupScopeWrites': 1,
            'repaired': false,
            'noop': false,
            'shouldBumpLedgerRevision': false,
          },
        );

        final result = await service.correctSettlement(
          groupId: 'g1',
          scope: 'group',
          settlementId: 's1',
          correctionNote: 'Correction of a recorded payment',
        );

        final payload =
            verify(() => callable.call(captureAny())).captured.single;
        expect(payload, {
          'groupId': 'g1',
          'scope': 'group',
          'settlementId': 's1',
          'correctionNote': 'Correction of a recorded payment',
        });
        expect(payload, isNot(contains('eventId')));
        expect(result.shouldBumpLedgerRevision, isFalse);
      },
    );

    test(
      'correctLogicalSettleUp sends {groupId,groupSettleUpId,correctionNote} '
      'and parses a partial-repair result',
      () async {
        final (:functions, :callable, :service) = _harness(
          data: {
            'eventScopeWrites': 2,
            'groupScopeWrites': 1,
            'repaired': true,
            'noop': false,
            'shouldBumpLedgerRevision': true,
          },
        );

        final result = await service.correctLogicalSettleUp(
          groupId: 'g1',
          groupSettleUpId: 'su-1',
          correctionNote: 'Correction of a recorded payment',
        );

        verify(
          () => functions.httpsCallable('correctLogicalSettleUp'),
        ).called(1);
        final payload =
            verify(() => callable.call(captureAny())).captured.single;
        expect(payload, {
          'groupId': 'g1',
          'groupSettleUpId': 'su-1',
          'correctionNote': 'Correction of a recorded payment',
        });
        expect(result.eventScopeWrites, 2);
        expect(result.groupScopeWrites, 1);
        expect(result.repaired, isTrue);
        expect(result.shouldBumpLedgerRevision, isTrue);
      },
    );

    test(
      'a missing/malformed result field degrades to a safe default, never '
      'throws',
      () async {
        final (:functions, :callable, :service) = _harness(data: <String, dynamic>{});

        final result = await service.correctSettlement(
          groupId: 'g1',
          scope: 'event',
          eventId: 'e1',
          settlementId: 's1',
          correctionNote: 'note',
        );

        expect(result.eventScopeWrites, 0);
        expect(result.groupScopeWrites, 0);
        expect(result.repaired, isFalse);
        expect(result.noop, isFalse);
        expect(result.shouldBumpLedgerRevision, isFalse);
      },
    );
  });
}

({
  FirebaseFunctions functions,
  HttpsCallable callable,
  FirebaseFunctionsService service,
})
_harness({Object? data}) {
  final functions = _MockFirebaseFunctions();
  final callable = _MockHttpsCallable();
  final result = _MockHttpsCallableResult();

  when(() => functions.httpsCallable(any())).thenReturn(callable);
  when(() => callable.call(captureAny())).thenAnswer((_) async => result);
  if (data != null) {
    when(() => result.data).thenReturn(data);
  }

  return (
    functions: functions,
    callable: callable,
    service: FirebaseFunctionsService(functions: functions),
  );
}
