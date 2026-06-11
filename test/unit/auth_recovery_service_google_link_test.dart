import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/cache_isolation_controller.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockUserCredential extends Mock implements UserCredential {}

class _FakeAuthCredential extends Fake implements AuthCredential {}

/// Records isolation/restart events — linkGoogleToCurrentUser is same-UID by
/// construction and must NEVER touch the swap machinery.
class _RecordingController implements CacheIsolationController {
  final List<String> events = [];
  @override
  void engageIsolation() => events.add('engage');
  @override
  Future<void> restart() async => events.add('restart');
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
  });

  late _MockFirebaseAuth auth;
  late _MockUser anonUser;
  late SharedPreferences prefs;
  late _RecordingController isolation;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    auth = _MockFirebaseAuth();
    anonUser = _MockUser();
    isolation = _RecordingController();
    when(() => auth.currentUser).thenReturn(anonUser);
    when(() => auth.signOut()).thenAnswer((_) async {});
    when(() => anonUser.uid).thenReturn('anon-uid-123');
    when(() => anonUser.isAnonymous).thenReturn(true);
  });

  AuthRecoveryService buildService({
    GoogleCredentialFactory? googleCredentialFactory,
  }) {
    return AuthRecoveryService(
      auth: auth,
      prefs: prefs,
      cacheIsolationController: isolation,
      cleanupAnonUidArtifacts: ({required oldUid, required cleanupSecret}) =>
          throw StateError('merge engine must not be touched'),
      cleanupIntentFactory: (_) =>
          throw StateError('merge engine must not be touched'),
      googleCredentialFactory: googleCredentialFactory,
    );
  }

  group('linkGoogleToCurrentUser', () {
    test('links the factory credential to the current user '
        '(same UID, no isolation, no inFlightOp)', () async {
      final credential = _FakeAuthCredential();
      final userCredential = _MockUserCredential();
      when(() => userCredential.user).thenReturn(anonUser);
      when(
        () => anonUser.linkWithCredential(credential),
      ).thenAnswer((_) async => userCredential);
      final service = buildService(
        googleCredentialFactory: () async => credential,
      );

      final result = await service.linkGoogleToCurrentUser();

      expect(result, same(userCredential));
      verify(() => anonUser.linkWithCredential(credential)).called(1);
      verifyNever(() => auth.signOut());
      expect(isolation.events, isEmpty);
      expect(service.readInFlightOp(), isNull);
    });

    test('throws StateError without invoking the Google sheet '
        'when there is no current user', () async {
      when(() => auth.currentUser).thenReturn(null);
      var factoryInvoked = false;
      final service = buildService(
        googleCredentialFactory: () async {
          factoryInvoked = true;
          return _FakeAuthCredential();
        },
      );

      await expectLater(service.linkGoogleToCurrentUser, throwsStateError);
      expect(factoryInvoked, isFalse);
    });

    test('propagates credential-already-in-use unchanged and never '
        'signs out (the caller owns the conflict decision)', () async {
      when(() => anonUser.linkWithCredential(any())).thenThrow(
        FirebaseAuthException(code: 'credential-already-in-use'),
      );
      final service = buildService(
        googleCredentialFactory: () async => _FakeAuthCredential(),
      );

      await expectLater(
        service.linkGoogleToCurrentUser(),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            'credential-already-in-use',
          ),
        ),
      );
      verifyNever(() => auth.signOut());
      expect(isolation.events, isEmpty);
    });

    test('propagates a factory failure (e.g. sheet canceled) without '
        'attempting the link', () async {
      final service = buildService(
        googleCredentialFactory: () async =>
            throw StateError('canceled by user'),
      );

      await expectLater(service.linkGoogleToCurrentUser(), throwsStateError);
      verifyNever(() => anonUser.linkWithCredential(any()));
    });
  });
}
