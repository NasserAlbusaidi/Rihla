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

  test('calls callable, wipes local cache, and signs out on success', () async {
    final calls = <String>[];
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.signOut()).thenAnswer((_) async {
      calls.add('signOut');
    });
    final service = DataDeletionService(
      auth: auth,
      deleteAccountCallable: () async {
        calls.add('callable');
      },
      wipeLocalCache: () async {
        calls.add('wipe');
      },
    );

    expect(await service.deleteAccount(), DeletionResult.ok);
    expect(calls, ['callable', 'wipe', 'signOut']);
    verify(() => auth.signOut()).called(1);
  });

  test('returns error when the callable fails', () async {
    final calls = <String>[];
    when(() => auth.currentUser).thenReturn(user);
    final service = DataDeletionService(
      auth: auth,
      deleteAccountCallable: () async {
        calls.add('callable');
        throw StateError('boom');
      },
      wipeLocalCache: () async {
        calls.add('wipe');
      },
    );

    expect(await service.deleteAccount(), DeletionResult.error);
    expect(calls, ['callable']);
    verifyNever(() => auth.signOut());
  });

  test('returns error when local cache wipe fails', () async {
    final calls = <String>[];
    when(() => auth.currentUser).thenReturn(user);
    final service = DataDeletionService(
      auth: auth,
      deleteAccountCallable: () async {
        calls.add('callable');
      },
      wipeLocalCache: () async {
        calls.add('wipe');
        throw StateError('wipe failed');
      },
    );

    expect(await service.deleteAccount(), DeletionResult.error);
    expect(calls, ['callable', 'wipe']);
    verifyNever(() => auth.signOut());
  });

  test('returns error when signOut fails', () async {
    final calls = <String>[];
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.signOut()).thenAnswer((_) async {
      calls.add('signOut');
      throw StateError('signOut failed');
    });
    final service = DataDeletionService(
      auth: auth,
      deleteAccountCallable: () async {
        calls.add('callable');
      },
      wipeLocalCache: () async {
        calls.add('wipe');
      },
    );

    expect(await service.deleteAccount(), DeletionResult.error);
    expect(calls, ['callable', 'wipe', 'signOut']);
  });
}
