import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/cache_isolation_controller.dart';
import 'package:safar/core/services/cache_uid_barrier.dart';
import 'package:safar/features/auth/services/data_deletion_service.dart';
import 'package:safar/features/auth/services/durable_account_marker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

/// The server throws this exact shape on a partial/convergent deletion. The
/// real plugin constructor is @protected; a subclass may invoke it.
class _FakeFunctionsException extends FirebaseFunctionsException {
  _FakeFunctionsException({required super.code, super.details})
    : super(message: 'test');
}

class _RecordingController implements CacheIsolationController {
  _RecordingController(this.events);
  final List<String> events;
  @override
  void engageIsolation() => events.add('engage');
  @override
  Future<void> restart() async => events.add('restart');
}

void main() {
  late _MockFirebaseAuth auth;
  late _MockUser user;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    auth = _MockFirebaseAuth();
    user = _MockUser();
    when(() => user.uid).thenReturn('uid-1');
  });

  DataDeletionService build({
    required List<String> events,
    DeleteAccountCallable? deleteAccountCallable,
  }) {
    return DataDeletionService(
      auth: auth,
      prefs: prefs,
      cacheIsolationController: _RecordingController(events),
      deleteAccountCallable: deleteAccountCallable,
    );
  }

  test('returns noUser when there is no current user', () async {
    when(() => auth.currentUser).thenReturn(null);

    expect(await build(events: <String>[]).deleteAccount(), DeletionResult.noUser);
  });

  test('cascade → engage → dirty before signOut → restart → ok', () async {
    final events = <String>[];
    bool? dirtyAtSignOut;
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.signOut()).thenAnswer((_) async {
      dirtyAtSignOut = prefs.getBool(kFirestorePersistenceDirtyKey);
      events.add('signOut');
    });
    final service = build(
      events: events,
      deleteAccountCallable: () async => events.add('callable'),
    );

    expect(await service.deleteAccount(), DeletionResult.ok);
    expect(events, ['callable', 'engage', 'signOut', 'restart']);
    expect(dirtyAtSignOut, isTrue);
  });

  test(
    'returns error when the callable fails — no engage, no sign-out, no restart',
    () async {
      final events = <String>[];
      when(() => auth.currentUser).thenReturn(user);
      final service = build(
        events: events,
        deleteAccountCallable: () async {
          events.add('callable');
          throw StateError('boom');
        },
      );

      expect(await service.deleteAccount(), DeletionResult.error);
      expect(events, ['callable']);
      verifyNever(() => auth.signOut());
    },
  );

  test(
    'post-cascade signOut failure is non-fatal: still restarts and returns ok',
    () async {
      final events = <String>[];
      when(() => auth.currentUser).thenReturn(user);
      when(() => auth.signOut()).thenAnswer((_) async {
        events.add('signOut');
        throw StateError('signOut failed');
      });
      final service = build(
        events: events,
        deleteAccountCallable: () async => events.add('callable'),
      );

      expect(await service.deleteAccount(), DeletionResult.ok);
      expect(events, ['callable', 'engage', 'signOut', 'restart']);
    },
  );

  // #77: a partial cascade (server throws an `internal` HttpsError carrying the
  // DeleteAccountOutput, whose `cascadeFailed` lists the unfinished groups) is
  // convergent on retry. It must surface as a distinct result AND, like a hard
  // error, must NOT tear down the still-valid session.
  test('returns partial on internal cascadeFailed error — no teardown', () async {
    final events = <String>[];
    when(() => auth.currentUser).thenReturn(user);
    final service = build(
      events: events,
      deleteAccountCallable: () async {
        events.add('callable');
        throw _FakeFunctionsException(
          code: 'internal',
          details: const <String, dynamic>{
            'cascadeFailed': <String>['group-1'],
          },
        );
      },
    );

    expect(await service.deleteAccount(), DeletionResult.partial);
    expect(events, ['callable']);
    verifyNever(() => auth.signOut());
  });

  // The "scrubbed but Auth alive" variant: the cascade finished but the final
  // Auth-user delete failed, so the server throws `internal` with an EMPTY
  // cascadeFailed and authUserDeleted:false. Still convergent → partial.
  test('returns partial on scrubbed-but-auth-alive error', () async {
    when(() => auth.currentUser).thenReturn(user);
    final service = build(
      events: <String>[],
      deleteAccountCallable: () async => throw _FakeFunctionsException(
        code: 'internal',
        details: const <String, dynamic>{
          'cascadeFailed': <String>[],
          'authUserDeleted': false,
        },
      ),
    );

    expect(await service.deleteAccount(), DeletionResult.partial);
  });

  // #469: a successful deletion removes the durable-account marker so the next
  // fresh-anon session is not falsely blocked from deleting.
  test('successful deletion clears the durable-account marker (#469)', () async {
    await prefs.setBool(kDurableAccountEstablishedKey, true);
    final events = <String>[];
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.signOut()).thenAnswer((_) async => events.add('signOut'));
    final service = build(
      events: events,
      deleteAccountCallable: () async => events.add('callable'),
    );

    expect(await service.deleteAccount(), DeletionResult.ok);
    expect(durableAccountEstablished(prefs), isFalse);
  });

  // A failed (non-convergent) deletion must NOT clear the marker — the durable
  // account still exists, so the gate must keep protecting it.
  test('failed deletion leaves the durable-account marker intact (#469)', () async {
    await prefs.setBool(kDurableAccountEstablishedKey, true);
    when(() => auth.currentUser).thenReturn(user);
    final service = build(
      events: <String>[],
      deleteAccountCallable: () async => throw StateError('boom'),
    );

    expect(await service.deleteAccount(), DeletionResult.error);
    expect(durableAccountEstablished(prefs), isTrue);
  });

  // A non-`internal` FunctionsException (rate limit, auth, bad input) is NOT a
  // convergent partial — it stays a generic error.
  test('returns error for a non-internal FunctionsException', () async {
    when(() => auth.currentUser).thenReturn(user);
    final service = build(
      events: <String>[],
      deleteAccountCallable: () async =>
          throw _FakeFunctionsException(code: 'resource-exhausted'),
    );

    expect(await service.deleteAccount(), DeletionResult.error);
  });

  // A malformed `internal` payload whose cascadeFailed is not a List must fail
  // loud as a generic error — never be mistaken for a retryable partial on a
  // destructive path.
  test('returns error when internal details.cascadeFailed is not a List', () async {
    when(() => auth.currentUser).thenReturn(user);
    final service = build(
      events: <String>[],
      deleteAccountCallable: () async => throw _FakeFunctionsException(
        code: 'internal',
        details: const <String, dynamic>{'cascadeFailed': 'oops'},
      ),
    );

    expect(await service.deleteAccount(), DeletionResult.error);
  });
}
