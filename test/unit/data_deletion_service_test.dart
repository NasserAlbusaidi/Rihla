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

  test('calls the server callable then signs out on success', () async {
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
    );

    expect(await service.deleteAccount(), DeletionResult.ok);
    // Local SQLite wipe removed in #50 — Firestore is the source of truth and
    // the SDK offline cache is handled by the UID-isolation barrier (PR 2).
    expect(calls, ['callable', 'signOut']);
    verify(() => auth.signOut()).called(1);
  });

  test('returns error when the callable fails (no sign-out)', () async {
    final calls = <String>[];
    when(() => auth.currentUser).thenReturn(user);
    final service = DataDeletionService(
      auth: auth,
      deleteAccountCallable: () async {
        calls.add('callable');
        throw StateError('boom');
      },
    );

    expect(await service.deleteAccount(), DeletionResult.error);
    expect(calls, ['callable']);
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
    );

    expect(await service.deleteAccount(), DeletionResult.error);
    expect(calls, ['callable', 'signOut']);
  });
}
