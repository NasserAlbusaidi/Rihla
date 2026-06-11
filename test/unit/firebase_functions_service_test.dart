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
}

({
  FirebaseFunctions functions,
  HttpsCallable callable,
  FirebaseFunctionsService service,
})
_harness() {
  final functions = _MockFirebaseFunctions();
  final callable = _MockHttpsCallable();
  final result = _MockHttpsCallableResult();

  when(() => functions.httpsCallable(any())).thenReturn(callable);
  when(() => callable.call(captureAny())).thenAnswer((_) async => result);

  return (
    functions: functions,
    callable: callable,
    service: FirebaseFunctionsService(functions: functions),
  );
}
