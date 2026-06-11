// Gate-conflict switch flow (#428 PR-A2).
//
// On GoogleLinkConflictException the sheet offers "switch to that account"
// (discard-shell restore reusing the failed credential) ONLY when the live
// userGroupsProvider proves the current shell empty. Populated/error → the
// dead-end copy; loading → progress. The intent marker is persisted BEFORE
// restoreWithGoogle so the interrupted create/join replays after the
// restart. NEVER signOut (#213).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/extensions/build_context_l10n.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/auth/services/durable_credential_exception.dart';
import 'package:safar/features/auth/services/pending_gate_intent.dart';
import 'package:safar/features/auth/widgets/durable_credential_sheet.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuthRecoveryService extends Mock implements AuthRecoveryService {}

class _MockUserCredential extends Mock implements UserCredential {}

class _FakeAuthCredential extends Fake implements AuthCredential {}

Group _group() => Group(
  id: 'g1',
  name: 'Trip',
  inviteCode: 'ABCDEF',
  createdBy: 'u1',
  memberIds: const ['u1'],
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  late _MockAuthRecoveryService recovery;
  late SharedPreferences prefs;
  bool? result;

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    recovery = _MockAuthRecoveryService();
    result = null;
  });

  GoogleLinkConflictException conflict(AuthCredential credential) =>
      GoogleLinkConflictException(
        credential: credential,
        cause: FirebaseAuthException(code: 'credential-already-in-use'),
      );

  Widget harness({
    required Stream<List<Group>> groups,
    PendingGateIntent? intent,
  }) {
    return ProviderScope(
      overrides: [
        authRecoveryServiceProvider.overrideWithValue(recovery),
        sharedPreferencesProvider.overrideWithValue(prefs),
        userGroupsProvider.overrideWith((ref) => groups),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDurableCredentialSheet(
                  context,
                  intent: intent,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<AppLocalizations> openAndConflict(
    WidgetTester tester, {
    required Stream<List<Group>> groups,
    PendingGateIntent? intent,
    AuthCredential? credential,
  }) async {
    when(() => recovery.linkGoogleToCurrentUser())
        .thenThrow(conflict(credential ?? _FakeAuthCredential()));
    await tester.pumpWidget(harness(groups: groups, intent: intent));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n = tester.element(find.text('open')).l10n;
    await tester.tap(find.text(l10n.durableGateContinueGoogle));
    // Bounded pumps: conflict-loading / _restoring spinners animate forever,
    // so pumpAndSettle would time out on those states.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return l10n;
  }

  testWidgets('conflict + zero groups → switch offer', (tester) async {
    final l10n = await openAndConflict(tester, groups: Stream.value(const []));

    expect(find.byKey(const Key('durableGate.switch')), findsOneWidget);
    expect(find.text(l10n.durableGateConflictTitle), findsOneWidget);
    expect(find.text(l10n.durableGateConflictSwitchBody), findsOneWidget);
    expect(find.text(l10n.durableGateUseDifferent), findsOneWidget);
    expect(result, isNull);
    verifyNever(() => recovery.signOutCurrentDevice());
  });

  testWidgets(
    'switch persists the intent BEFORE restoreWithGoogle and reuses the '
    'failed credential',
    (tester) async {
      final credential = _FakeAuthCredential();
      var markerPresentAtCall = false;
      when(
        () => recovery.restoreWithGoogle(
          credential: any(named: 'credential'),
        ),
      ).thenAnswer((_) async {
        markerPresentAtCall = PendingGateIntent.read(prefs) != null;
        return _MockUserCredential();
      });

      final intent = PendingGateIntent.join(
        joinCode: 'ABC123',
        displayName: 'Nasser',
      );
      final l10n = await openAndConflict(
        tester,
        groups: Stream.value(const []),
        intent: intent,
        credential: credential,
      );

      await tester.tap(find.byKey(const Key('durableGate.switch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      verify(() => recovery.restoreWithGoogle(credential: credential))
          .called(1);
      expect(markerPresentAtCall, isTrue,
          reason: 'intent must be persisted before the restore restarts');
      expect(PendingGateIntent.read(prefs)?.joinCode, 'ABC123');
      expect(result, isNull,
          reason: 'sheet never pops — production restarts here');
      expect(l10n.durableGateSwitch, isNotEmpty);
      verifyNever(() => recovery.signOutCurrentDevice());
    },
  );

  testWidgets('switch with no intent writes no marker, still restores',
      (tester) async {
    final credential = _FakeAuthCredential();
    when(
      () => recovery.restoreWithGoogle(credential: any(named: 'credential')),
    ).thenAnswer((_) async => _MockUserCredential());

    await openAndConflict(
      tester,
      groups: Stream.value(const []),
      credential: credential,
    );
    await tester.tap(find.byKey(const Key('durableGate.switch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    verify(() => recovery.restoreWithGoogle(credential: credential)).called(1);
    expect(PendingGateIntent.read(prefs), isNull);
  });

  testWidgets('conflict + populated shell → dead-end copy, no switch',
      (tester) async {
    final l10n = await openAndConflict(
      tester,
      groups: Stream.value([_group()]),
    );

    expect(find.byKey(const Key('durableGate.switch')), findsNothing);
    expect(find.text(l10n.durableGateConflict), findsOneWidget);
    verifyNever(
      () => recovery.restoreWithGoogle(credential: any(named: 'credential')),
    );
  });

  testWidgets('conflict + groups error → dead-end copy (fail-safe)',
      (tester) async {
    final l10n = await openAndConflict(
      tester,
      groups: Stream.error(Exception('no-app')),
    );

    expect(find.byKey(const Key('durableGate.switch')), findsNothing);
    expect(find.text(l10n.durableGateConflict), findsOneWidget);
  });

  testWidgets('conflict + groups still loading → progress, no dead-end advice',
      (tester) async {
    // A stream that completes without emitting keeps the provider in loading.
    final l10n = await openAndConflict(
      tester,
      groups: const Stream<List<Group>>.empty(),
    );

    expect(find.byKey(const Key('durableGate.switch')), findsNothing);
    expect(find.text(l10n.durableGateConflict), findsNothing);
    expect(find.byKey(const Key('durableGate.conflictLoading')),
        findsOneWidget);
  });

  testWidgets('"Use a different account" returns to the initial state',
      (tester) async {
    final l10n = await openAndConflict(tester, groups: Stream.value(const []));

    await tester.tap(find.text(l10n.durableGateUseDifferent));
    await tester.pumpAndSettle();

    expect(find.text(l10n.durableGateTitle), findsOneWidget);
    expect(find.text(l10n.durableGateContinueGoogle), findsOneWidget);
    expect(find.byKey(const Key('durableGate.switch')), findsNothing);
    expect(result, isNull);
    verifyNever(() => recovery.signOutCurrentDevice());
  });

  testWidgets('provider-already-linked pops true (already durable)',
      (tester) async {
    when(() => recovery.linkGoogleToCurrentUser()).thenThrow(
      FirebaseAuthException(code: 'provider-already-linked'),
    );
    await tester.pumpWidget(harness(groups: Stream.value(const [])));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n = tester.element(find.text('open')).l10n;

    await tester.tap(find.text(l10n.durableGateContinueGoogle));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('failed restore (pre-isolation throw) resets to generic error',
      (tester) async {
    when(
      () => recovery.restoreWithGoogle(credential: any(named: 'credential')),
    ).thenThrow(StateError('fcm remove failed'));

    final l10n = await openAndConflict(tester, groups: Stream.value(const []));
    await tester.tap(find.byKey(const Key('durableGate.switch')));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text(l10n.durableGateError), findsOneWidget);
    verifyNever(() => recovery.signOutCurrentDevice());
  });
}
