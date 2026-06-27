import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/firebase_functions_service.dart';
import 'package:safar/core/services/notification_prompt.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/claim_models.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/join_group_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

// #278 PR9 — the join-screen claim flow: discover unclaimed shadows, offer a
// claim with a hard permanent confirmation (D3), wait for creator approval, or
// fall back to "I'm new". Discovery + request + poll route through the overridden
// firebaseFunctionsServiceProvider; the plain join routes through groupService.

class _FakeFns extends Mock implements FirebaseFunctionsService {}

class _NoopPrompt implements NotificationPrompt {
  @override
  Future<void> maybePrompt() async {}
}

void main() {
  late _FakeFns fns;
  late FakeFirebaseFirestore db;
  late bool joinCalled;

  const oneShadow = [UnclaimedShadow(shadowMemberId: 's1', displayName: 'Ali')];

  setUp(() {
    fns = _FakeFns();
    db = FakeFirebaseFirestore();
    joinCalled = false;
    when(
      () => fns.listUnclaimedShadows(inviteCode: any(named: 'inviteCode')),
    ).thenAnswer((_) async => const <UnclaimedShadow>[]);
  });

  Future<Widget> harness({String? initialInviteCode}) async {
    SharedPreferences.setMockInitialValues({'settings_device_name': 'Joiner'});
    final prefs = await SharedPreferences.getInstance();
    await db.collection('groups').doc('g1').set({
      'id': 'g1',
      'name': 'Trip',
      'inviteCode': 'ABC123',
      'createdBy': 'owner',
      'memberIds': ['owner', 'uid-joiner'],
      'currency': 'OMR',
      'createdAt': DateTime(2026, 1, 1),
      'isDeleted': false,
    });
    final router = GoRouter(
      initialLocation: '/join',
      routes: [
        GoRoute(
          path: '/join',
          builder: (c, s) =>
              JoinGroupScreen(initialInviteCode: initialInviteCode),
        ),
        GoRoute(
          path: '/group/:id',
          builder: (c, s) =>
              Scaffold(body: Text('GROUP ${s.pathParameters['id']}')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        groupLoadingProvider.overrideWith((ref) => false),
        groupErrorProvider.overrideWith((ref) => null),
        notificationPromptProvider.overrideWithValue(_NoopPrompt()),
        firebaseFunctionsServiceProvider.overrideWithValue(fns),
        groupServiceProvider.overrideWith(
          (ref) => GroupService.withFirestore(
            ref,
            db,
            currentUserId: 'uid-joiner',
            joinGroupCallableOverride:
                ({required inviteCode, required displayName}) async {
                  joinCalled = true;
                  return 'g1';
                },
          ),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  Future<void> enterCode(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).last, 'ABC123');
    await tester.pumpAndSettle();
  }

  void stubShadows() {
    when(
      () => fns.listUnclaimedShadows(inviteCode: any(named: 'inviteCode')),
    ).thenAnswer((_) async => oneShadow);
  }

  void stubRequestPending() {
    when(
      () => fns.requestClaimShadow(
        inviteCode: any(named: 'inviteCode'),
        shadowMemberId: any(named: 'shadowMemberId'),
        displayName: any(named: 'displayName'),
      ),
    ).thenAnswer(
      (_) async => const ClaimRequestResult(
        requestId: 'uid-joiner__s1',
        status: 'pending',
        groupId: 'g1',
      ),
    );
  }

  Future<void> reachWaiting(WidgetTester tester) async {
    stubShadows();
    stubRequestPending();
    await tester.pumpWidget(await harness());
    await tester.pump();
    await enterCode(tester);
    await tester.tap(find.byKey(GroupKeys.claimShadowTile('s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupKeys.claimConfirmButton));
    await tester.pumpAndSettle();
  }

  testWidgets('J1: a claimable shadow shows the picker (no auto-join)', (
    tester,
  ) async {
    stubShadows();
    await tester.pumpWidget(await harness());
    await tester.pump();
    await enterCode(tester);

    expect(find.byKey(GroupKeys.claimPicker), findsOneWidget);
    expect(find.text('Ali'), findsOneWidget);
    expect(find.byKey(GroupKeys.claimImNewButton), findsOneWidget);
    expect(joinCalled, isFalse);
  });

  testWidgets('route prefill is side-effect-free until the user acts (#368)', (
    tester,
  ) async {
    await tester.pumpWidget(await harness(initialInviteCode: 'ABC123'));
    await tester.pumpAndSettle();

    expect(joinCalled, isFalse);
    verifyNever(
      () => fns.listUnclaimedShadows(inviteCode: any(named: 'inviteCode')),
    );
    verifyNever(
      () => fns.requestClaimShadow(
        inviteCode: any(named: 'inviteCode'),
        shadowMemberId: any(named: 'shadowMemberId'),
        displayName: any(named: 'displayName'),
      ),
    );
    verifyNever(
      () => fns.listMyClaimRequests(inviteCode: any(named: 'inviteCode')),
    );
  });

  testWidgets('J2: no shadows runs the normal join (regression guard)', (
    tester,
  ) async {
    await tester.pumpWidget(await harness());
    await tester.pump();
    await enterCode(tester);

    expect(find.byKey(GroupKeys.claimPicker), findsNothing);
    expect(joinCalled, isTrue);
  });

  testWidgets('J3: tapping a shadow shows the permanent warning, no request', (
    tester,
  ) async {
    stubShadows();
    await tester.pumpWidget(await harness());
    await tester.pump();
    await enterCode(tester);

    await tester.tap(find.byKey(GroupKeys.claimShadowTile('s1')));
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.claimConfirmSheet), findsOneWidget);
    expect(find.textContaining('permanently merges'), findsOneWidget);
    expect(find.textContaining("can't be undone"), findsOneWidget);
    verifyNever(
      () => fns.requestClaimShadow(
        inviteCode: any(named: 'inviteCode'),
        shadowMemberId: any(named: 'shadowMemberId'),
        displayName: any(named: 'displayName'),
      ),
    );
  });

  testWidgets('J4: confirming requests the claim and shows waiting', (
    tester,
  ) async {
    await reachWaiting(tester);

    verify(
      () => fns.requestClaimShadow(
        inviteCode: 'ABC123',
        shadowMemberId: 's1',
        displayName: 'Joiner',
      ),
    ).called(1);
    expect(find.byKey(GroupKeys.claimWaiting), findsOneWidget);
  });

  testWidgets('J5: cancelling the warning sends no request, stays on picker', (
    tester,
  ) async {
    stubShadows();
    await tester.pumpWidget(await harness());
    await tester.pump();
    await enterCode(tester);

    await tester.tap(find.byKey(GroupKeys.claimShadowTile('s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupKeys.claimConfirmCancel));
    await tester.pumpAndSettle();

    verifyNever(
      () => fns.requestClaimShadow(
        inviteCode: any(named: 'inviteCode'),
        shadowMemberId: any(named: 'shadowMemberId'),
        displayName: any(named: 'displayName'),
      ),
    );
    expect(find.byKey(GroupKeys.claimPicker), findsOneWidget);
  });

  testWidgets(
    'J6: waiting + Check again with claimed navigates into the group',
    (tester) async {
      when(
        () => fns.listMyClaimRequests(inviteCode: any(named: 'inviteCode')),
      ).thenAnswer(
        (_) async => const [
          MyClaimRequest(
            requestId: 'uid-joiner__s1',
            shadowMemberId: 's1',
            shadowDisplayName: 'Ali',
            status: 'claimed',
          ),
        ],
      );
      await reachWaiting(tester);

      await tester.tap(find.byKey(GroupKeys.claimCheckAgainButton));
      await tester.pumpAndSettle();

      expect(find.text('GROUP g1'), findsOneWidget);
    },
  );

  testWidgets(
    'J7: waiting + Check again with declined shows the declined copy',
    (tester) async {
      when(
        () => fns.listMyClaimRequests(inviteCode: any(named: 'inviteCode')),
      ).thenAnswer(
        (_) async => const [
          MyClaimRequest(
            requestId: 'uid-joiner__s1',
            shadowMemberId: 's1',
            shadowDisplayName: 'Ali',
            status: 'declined',
          ),
        ],
      );
      await reachWaiting(tester);

      await tester.tap(find.byKey(GroupKeys.claimCheckAgainButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('declined your claim'), findsOneWidget);
    },
  );

  testWidgets('J8: "No, I\'m new" runs the normal join', (tester) async {
    stubShadows();
    await tester.pumpWidget(await harness());
    await tester.pump();
    await enterCode(tester);

    await tester.tap(find.byKey(GroupKeys.claimImNewButton));
    await tester.pumpAndSettle();

    expect(joinCalled, isTrue);
  });
}
