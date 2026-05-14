import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/features/auth/services/data_deletion_service.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  late _MockFirebaseAuth auth;
  late _MockUser user;

  setUp(() {
    auth = _MockFirebaseAuth();
    user = _MockUser();
    when(() => user.uid).thenReturn('uid-1');
  });

  test('returns noUser when there is no current user', () async {
    when(() => auth.currentUser).thenReturn(null);
    final service = DataDeletionService(auth: auth);

    expect(await service.deleteAccount(), DeletionResult.noUser);
  });

  test('returns ok when user.delete() succeeds', () async {
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.delete()).thenAnswer((_) async {});
    final service = DataDeletionService(auth: auth);

    expect(await service.deleteAccount(), DeletionResult.ok);
    verify(() => user.delete()).called(1);
  });

  test('maps requires-recent-login to its own enum case', () async {
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.delete()).thenThrow(
      FirebaseAuthException(code: 'requires-recent-login'),
    );
    final service = DataDeletionService(auth: auth);

    expect(
      await service.deleteAccount(),
      DeletionResult.requiresRecentLogin,
    );
  });

  test('returns error for any other FirebaseAuthException', () async {
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.delete()).thenThrow(
      FirebaseAuthException(code: 'network-request-failed'),
    );
    final service = DataDeletionService(auth: auth);

    expect(await service.deleteAccount(), DeletionResult.error);
  });

  test('returns error for unexpected throwables', () async {
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.delete()).thenThrow(StateError('boom'));
    final service = DataDeletionService(auth: auth);

    expect(await service.deleteAccount(), DeletionResult.error);
  });
}
