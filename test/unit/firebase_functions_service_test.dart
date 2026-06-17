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
