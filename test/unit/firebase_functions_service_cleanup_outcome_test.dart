import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/firebase_functions_service.dart';

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<dynamic> {}

void main() {
  ({HttpsCallable callable, FirebaseFunctionsService service}) harness(
    Object? data,
  ) {
    final functions = _MockFirebaseFunctions();
    final callable = _MockHttpsCallable();
    final result = _MockHttpsCallableResult();

    when(() => functions.httpsCallable(any())).thenReturn(callable);
    when(() => callable.call(captureAny())).thenAnswer((_) async => result);
    when(() => result.data).thenReturn(data);

    return (
      callable: callable,
      service: FirebaseFunctionsService(functions: functions),
    );
  }

  test('empty cascadeFailed parses as a complete outcome', () async {
    final (:callable, :service) = harness({
      'groupsProcessed': 2,
      'cascadeFailed': <dynamic>[],
      'authUserDeleted': true,
    });

    final outcome = await service.cleanupAnonUidArtifacts(
      oldUid: 'anon-uid',
      cleanupSecret: 'secret-123',
    );

    expect(outcome.complete, isTrue);
    expect(outcome.cascadeFailed, isEmpty);
    final payload = verify(() => callable.call(captureAny())).captured.single;
    expect(payload, {'oldUid': 'anon-uid', 'cleanupSecret': 'secret-123'});
  });

  test('non-empty cascadeFailed parses as incomplete with the group ids', () async {
    final (:service, callable: _) = harness({
      'groupsProcessed': 2,
      'cascadeFailed': ['g1'],
      'authUserDeleted': false,
    });

    final outcome = await service.cleanupAnonUidArtifacts(
      oldUid: 'anon-uid',
      cleanupSecret: 'secret-123',
    );

    expect(outcome.complete, isFalse);
    expect(outcome.cascadeFailed, ['g1']);
  });

  test('missing cascadeFailed key is tolerated as complete', () async {
    final (:service, callable: _) = harness({'groupsProcessed': 0});

    final outcome = await service.cleanupAnonUidArtifacts(
      oldUid: 'anon-uid',
      cleanupSecret: 'secret-123',
    );

    expect(outcome.complete, isTrue);
    expect(outcome.cascadeFailed, isEmpty);
  });

  test('non-list cascadeFailed is tolerated as complete', () async {
    final (:service, callable: _) = harness({'cascadeFailed': 'oops'});

    final outcome = await service.cleanupAnonUidArtifacts(
      oldUid: 'anon-uid',
      cleanupSecret: 'secret-123',
    );

    expect(outcome.complete, isTrue);
    expect(outcome.cascadeFailed, isEmpty);
  });

  test('non-map response data is tolerated as complete', () async {
    final (:service, callable: _) = harness(null);

    final outcome = await service.cleanupAnonUidArtifacts(
      oldUid: 'anon-uid',
      cleanupSecret: 'secret-123',
    );

    expect(outcome.complete, isTrue);
    expect(outcome.cascadeFailed, isEmpty);
  });

  test('non-string entries in cascadeFailed are dropped', () async {
    final (:service, callable: _) = harness({
      'cascadeFailed': ['g1', 42, null, 'g2'],
    });

    final outcome = await service.cleanupAnonUidArtifacts(
      oldUid: 'anon-uid',
      cleanupSecret: 'secret-123',
    );

    expect(outcome.complete, isFalse);
    expect(outcome.cascadeFailed, ['g1', 'g2']);
  });
}
