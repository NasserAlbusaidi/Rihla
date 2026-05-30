import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/cache_isolation_controller.dart';
import 'package:safar/core/services/cache_uid_barrier.dart';
import 'package:safar/features/auth/services/data_deletion_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

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
}
