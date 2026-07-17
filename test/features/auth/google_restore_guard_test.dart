import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/providers/shell_emptiness_gate.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/auth/widgets/google_restore_action.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

/// #648 — un-gating join makes a *populated anonymous shell* reachable, so the
/// irreversible Google "discard-shell swap" must be guarded at the swap point,
/// not on CTA visibility (which false-empties on the cold-start
/// firebaseUserProvider race). triggerGoogleRestore must call
/// restoreWithGoogle ONLY when the outgoing shell is provably empty.
class _MockAuthRecoveryService extends Mock implements AuthRecoveryService {}

class _MockGroupService extends Mock implements GroupService {}

class _MockUserCredential extends Mock implements UserCredential {}

const _kRestoreButton = Key('test.restore.button');

/// Default gate probe: server-confirmed empty → the proceed path stays live
/// (without an override the unbound default hits `[core/no-app]` → null →
/// block, so every proceed test would silently become a block test).
Future<bool?> _serverEmptyProbe(String uid) async => false;

Group _group(String id) => Group(
  id: id,
  name: 'Trip',
  inviteCode: 'ABC234',
  createdBy: 'anon-1',
  memberIds: const ['anon-1'],
  currency: 'OMR',
  createdAt: DateTime(2026),
);

void main() {
  late _MockAuthRecoveryService recovery;
  late _MockGroupService groupService;

  setUp(() {
    recovery = _MockAuthRecoveryService();
    groupService = _MockGroupService();
    when(() => recovery.restoreWithGoogle())
        .thenAnswer((_) async => _MockUserCredential());
  });

  Widget buildApp({
    required Stream<User?> userStream,
    Duration timeout = const Duration(seconds: 5),
    Future<bool?> Function(String uid) probe = _serverEmptyProbe,
  }) {
    return ProviderScope(
      overrides: [
        authRecoveryServiceProvider.overrideWithValue(recovery),
        // Drive the REAL userGroupsProvider via the auth + service seams (never
        // a direct userGroupsProvider override — that would mask the
        // cold-start false-empty race the guard exists to defeat).
        firebaseUserProvider.overrideWith((ref) => userStream),
        groupServiceProvider.overrideWithValue(groupService),
        shellEmptinessGateTimeoutProvider.overrideWithValue(timeout),
        shellEmptinessServerProbeProvider.overrideWithValue(probe),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              key: _kRestoreButton,
              onPressed: () => triggerGoogleRestore(context, ref),
              child: const Text('restore'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'populated shell BLOCKS the Google restore swap (#648 data-loss guard)',
    (tester) async {
      when(() => groupService.watchUserGroups(any()))
          .thenAnswer((_) => Stream.value([_group('g1')]));

      await tester.pumpWidget(
        buildApp(userStream: Stream.value(MockUser(isAnonymous: true, uid: 'anon-1'))),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kRestoreButton));
      await tester.pumpAndSettle();

      verifyNever(() => recovery.restoreWithGoogle());
      expect(
        find.text(AppLocalizationsEn().restoreBlockedHasData),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'unresolved user (cold-start false-empty) BLOCKS (fail-safe on timeout)',
    (tester) async {
      // firebaseUserProvider never emits → userGroupsProvider would false-empty
      // to [], but the gate awaits the USER first → times out → block.
      final never = StreamController<User?>();
      addTearDown(never.close);
      when(() => groupService.watchUserGroups(any()))
          .thenAnswer((_) => Stream.value(const []));

      await tester.pumpWidget(buildApp(
        userStream: never.stream,
        timeout: const Duration(milliseconds: 50),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kRestoreButton));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpAndSettle();

      verifyNever(() => recovery.restoreWithGoogle());
      expect(
        find.text(AppLocalizationsEn().restoreBlockedHasData),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'empty + resolved shell PROCEEDS with the Google restore',
    (tester) async {
      when(() => groupService.watchUserGroups(any()))
          .thenAnswer((_) => Stream.value(const []));

      await tester.pumpWidget(
        buildApp(userStream: Stream.value(MockUser(isAnonymous: true, uid: 'anon-1'))),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kRestoreButton));
      await tester.pumpAndSettle();

      verify(() => recovery.restoreWithGoogle()).called(1);
    },
  );

  testWidgets(
    'PendingWritesNotFlushedException surfaces the still-syncing snack '
    '(#1281)',
    (tester) async {
      when(() => groupService.watchUserGroups(any()))
          .thenAnswer((_) => Stream.value(const []));
      when(() => recovery.restoreWithGoogle())
          .thenThrow(PendingWritesNotFlushedException(const Duration(seconds: 5)));

      await tester.pumpWidget(
        buildApp(
          userStream: Stream.value(MockUser(isAnonymous: true, uid: 'anon-1')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kRestoreButton));
      await tester.pumpAndSettle();

      expect(
        find.text(AppLocalizationsEn().restorePendingWritesNotSynced),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'blocks restore when the stream is cache-empty but the server reports '
    'live data (#1091)',
    (tester) async {
      // Cold/reinstall device: local cache serves an EMPTY first snapshot, but
      // the server holds a live membership. Stream-empty is not account-empty —
      // the server probe must veto the swap.
      when(() => groupService.watchUserGroups(any()))
          .thenAnswer((_) => Stream.value(const []));

      await tester.pumpWidget(
        buildApp(
          userStream: Stream.value(MockUser(isAnonymous: true, uid: 'anon-1')),
          probe: (_) async => true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kRestoreButton));
      await tester.pumpAndSettle();

      verifyNever(() => recovery.restoreWithGoogle());
      expect(
        find.text(AppLocalizationsEn().restoreBlockedHasData),
        findsOneWidget,
      );
    },
  );
}
