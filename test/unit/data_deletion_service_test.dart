import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/features/auth/models/delete_account_output.dart';
import 'package:safar/features/auth/services/data_deletion_service.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

const _output = DeleteAccountOutput(
  groupsProcessed: 1,
  tombstoneIds: ['deleted-1'],
  expensesScrubbed: 2,
  settlementsScrubbed: 3,
  activityLogsScrubbed: 4,
  membersDeleted: 1,
  groupsOrphanedAndSoftDeleted: 0,
  fcmTokenDeleted: true,
  joinAttemptsDeleted: true,
  authUserDeleted: true,
);

void main() {
  late _MockFirebaseAuth auth;
  late _MockUser user;

  setUp(() {
    auth = _MockFirebaseAuth();
    user = _MockUser();
    when(() => user.uid).thenReturn('uid-1');
    when(() => auth.signOut()).thenAnswer((_) async {});
  });

  test('returns noUser when there is no current user', () async {
    when(() => auth.currentUser).thenReturn(null);
    final service = DataDeletionService(auth: auth);

    expect(await service.deleteAccount(), isA<DeletionNoUser>());
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
        return _output;
      },
      wipeLocalCache: () async {
        calls.add('wipe');
      },
    );

    expect(await service.deleteAccount(), isA<DeletionOk>());
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

    expect(await service.deleteAccount(), isA<DeletionError>());
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
        return _output;
      },
      wipeLocalCache: () async {
        calls.add('wipe');
        throw StateError('wipe failed');
      },
    );

    expect(await service.deleteAccount(), isA<DeletionLocalCleanupFailed>());
    expect(calls, ['callable', 'wipe']);
    verify(() => auth.signOut()).called(1);
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
        return _output;
      },
      wipeLocalCache: () async {
        calls.add('wipe');
      },
    );

    expect(await service.deleteAccount(), isA<DeletionLocalSignOutFailed>());
    expect(calls, ['callable', 'wipe', 'signOut']);
  });

  test(
    'returns partial result when server scrubbed data but auth delete failed',
    () async {
      final calls = <String>[];
      when(() => auth.currentUser).thenReturn(user);
      final service = DataDeletionService(
        auth: auth,
        deleteAccountCallable: () async {
          calls.add('callable');
          throw const DeleteAccountPartialFailure(
            output: _output,
            code: 'internal',
            message: 'auth delete failed',
          );
        },
        wipeLocalCache: () async {
          calls.add('wipe');
        },
      );

      expect(
        await service.deleteAccount(),
        isA<DeletionServerScrubbedAuthDeleteFailed>(),
      );
      expect(calls, ['callable']);
      verifyNever(() => auth.signOut());
    },
  );
}
