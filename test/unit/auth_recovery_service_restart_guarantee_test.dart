import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/cache_isolation_controller.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockPrefs extends Mock implements SharedPreferences {}

/// Records the order of isolation calls so we can prove restart() always runs.
class _RecordingController implements CacheIsolationController {
  final calls = <String>[];
  @override
  void engageIsolation() => calls.add('engage');
  @override
  Future<void> restart() async => calls.add('restart');
}

void main() {
  late _MockFirebaseAuth auth;
  late _MockUser anonUser;
  late _MockUser recoveredUser;
  late _MockFirestore firestore;
  late _MockPrefs prefs;
  late _RecordingController controller;

  setUp(() {
    auth = _MockFirebaseAuth();
    anonUser = _MockUser();
    recoveredUser = _MockUser();
    firestore = _MockFirestore();
    prefs = _MockPrefs();
    controller = _RecordingController();

    when(() => auth.currentUser).thenReturn(anonUser);
    when(() => anonUser.uid).thenReturn('anon-uid');
    when(() => anonUser.isAnonymous).thenReturn(true);
    when(() => auth.signOut()).thenAnswer((_) async {});
    when(() => recoveredUser.uid).thenReturn('linked-uid');
    when(firestore.waitForPendingWrites).thenAnswer((_) async {});

    // Dirty-flag write + pending-email clear succeed; the inFlightOp clear
    // FAILS — a broken prefs write must never skip the guaranteed restart.
    when(() => prefs.setBool(any(), any())).thenAnswer((_) async => true);
    when(
      () => prefs.remove('auth.pendingLinkEmail'),
    ).thenAnswer((_) async => true);
    when(
      () => prefs.remove('auth.inFlightOp'),
    ).thenThrow(Exception('prefs remove failed'));
  });

  AuthRecoveryService buildService() => AuthRecoveryService(
    auth: auth,
    prefs: prefs,
    cacheIsolationController: controller,
    firestore: firestore,
    cleanupAnonUidArtifacts: ({required oldUid, required cleanupSecret}) async {},
    cleanupIntentFactory: (_) async => 'secret',
  );

  test(
    'completeRecovery still restarts when clearing op-state throws — a prefs '
    'failure must never strand the overlay (#45 plan [P2])',
    () async {
      final cred = _MockUserCredential();
      when(
        () => auth.signInWithEmailLink(
          email: any(named: 'email'),
          emailLink: any(named: 'emailLink'),
        ),
      ).thenAnswer((_) async => cred);
      when(() => cred.user).thenReturn(recoveredUser);

      try {
        await buildService().completeRecovery(
          'https://example/link',
          overrideEmail: 'foo@example.com',
        );
      } catch (_) {
        // Before the fix the prefs throw propagates; after the fix it is
        // swallowed. Either way the guarantee under test is that restart() ran.
      }

      expect(controller.calls, contains('restart'));
      expect(controller.calls.first, 'engage');
      expect(controller.calls.last, 'restart');
    },
  );
}
