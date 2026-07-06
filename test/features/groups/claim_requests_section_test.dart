import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/firebase_functions_service.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/claim_models.dart';
import 'package:safar/features/groups/widgets/claim_requests_section.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// #278 PR9 — the creator's approve/decline surface for pending claim requests.
// Reads via the creator-gated listGroupClaimRequests; acts via decideClaimRequest
// (the approval runs the re-key engine). A non-creator must never even query.

class _FakeFns extends Mock implements FirebaseFunctionsService {}

void main() {
  late _FakeFns fns;

  const pending = [
    GroupClaimRequest(
      requestId: 'rid',
      requesterUid: 'u1',
      requesterDisplayName: 'Khalid',
      shadowMemberId: 's1',
      shadowDisplayName: 'Ali',
      status: 'pending',
    ),
  ];

  setUp(() {
    fns = _FakeFns();
    when(() => fns.listGroupClaimRequests(groupId: any(named: 'groupId')))
        .thenAnswer((_) async => pending);
  });

  Widget harness({required bool isCreator, bool durable = true}) {
    return ProviderScope(
      overrides: [
        firebaseFunctionsServiceProvider.overrideWithValue(fns),
        // D6-R: the decide pre-gate reads durability; default the harness to
        // durable so C4-C6 keep exercising the direct decide path.
        isDurableUserProvider.overrideWithValue(durable),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ClaimRequestsSection(groupId: 'g1', isCreator: isCreator),
        ),
      ),
    );
  }

  testWidgets('C1: non-creator renders nothing and never queries', (
    tester,
  ) async {
    await tester.pumpWidget(harness(isCreator: false));
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.claimRequestsSection), findsNothing);
    verifyNever(
      () => fns.listGroupClaimRequests(groupId: any(named: 'groupId')),
    );
  });

  testWidgets('C2: creator + a pending request shows the row and actions', (
    tester,
  ) async {
    await tester.pumpWidget(harness(isCreator: true));
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.claimRequestsSection), findsOneWidget);
    // Both names render — in the headline and again in the merge-consequence
    // line (#573 design polish), so each appears more than once.
    expect(find.textContaining('Khalid'), findsWidgets);
    expect(find.textContaining('Ali'), findsWidgets);
    expect(find.byKey(GroupKeys.claimApprove('rid')), findsOneWidget);
    expect(find.byKey(GroupKeys.claimDecline('rid')), findsOneWidget);
    // #573 polish surfaces: a "Pending" badge and the irreversible-merge notice.
    expect(find.text('Pending'), findsOneWidget);
    expect(find.textContaining("can't be undone"), findsOneWidget);
  });

  testWidgets('C3: creator + no pending hides the section', (tester) async {
    when(() => fns.listGroupClaimRequests(groupId: any(named: 'groupId')))
        .thenAnswer((_) async => const <GroupClaimRequest>[]);
    await tester.pumpWidget(harness(isCreator: true));
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.claimRequestsSection), findsNothing);
  });

  testWidgets('C4: Approve calls decide(true) and shows the approved snackbar', (
    tester,
  ) async {
    when(
      () => fns.decideClaimRequest(
        groupId: any(named: 'groupId'),
        requestId: any(named: 'requestId'),
        approve: any(named: 'approve'),
      ),
    ).thenAnswer(
      (_) async => const ClaimDecisionResult(
        requestId: 'rid',
        status: 'claimed',
        alreadyClaimed: false,
      ),
    );
    await tester.pumpWidget(harness(isCreator: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(GroupKeys.claimApprove('rid')));
    await tester.pumpAndSettle();

    verify(
      () => fns.decideClaimRequest(
        groupId: 'g1',
        requestId: 'rid',
        approve: true,
      ),
    ).called(1);
    expect(find.textContaining('now holds'), findsOneWidget);
  });

  testWidgets('C5: Decline calls decide(false) and shows the declined snackbar', (
    tester,
  ) async {
    when(
      () => fns.decideClaimRequest(
        groupId: any(named: 'groupId'),
        requestId: any(named: 'requestId'),
        approve: any(named: 'approve'),
      ),
    ).thenAnswer(
      (_) async => const ClaimDecisionResult(
        requestId: 'rid',
        status: 'declined',
        alreadyClaimed: false,
      ),
    );
    await tester.pumpWidget(harness(isCreator: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(GroupKeys.claimDecline('rid')));
    await tester.pumpAndSettle();

    verify(
      () => fns.decideClaimRequest(
        groupId: 'g1',
        requestId: 'rid',
        approve: false,
      ),
    ).called(1);
    expect(find.textContaining('Request declined'), findsOneWidget);
  });

  testWidgets('C6: Approve with engine internal shows try-again, not success', (
    tester,
  ) async {
    when(
      () => fns.decideClaimRequest(
        groupId: any(named: 'groupId'),
        requestId: any(named: 'requestId'),
        approve: any(named: 'approve'),
      ),
    ).thenThrow(
      FirebaseFunctionsException(code: 'internal', message: 'inconsistent'),
    );
    await tester.pumpWidget(harness(isCreator: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(GroupKeys.claimApprove('rid')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Try again'), findsOneWidget);
    expect(find.textContaining('now holds'), findsNothing);
  });

  testWidgets(
    'C7 (D6-R): anonymous creator tapping Approve opens the link sheet, '
    'never calls decide, and the row recovers on cancel',
    (tester) async {
      await tester.pumpWidget(harness(isCreator: true, durable: false));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.claimApprove('rid')));
      // Bounded pumps: the sheet hosts a non-settling animation, so
      // pumpAndSettle would time out.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('durableGate.continue')), findsOneWidget);
      verifyNever(
        () => fns.decideClaimRequest(
          groupId: any(named: 'groupId'),
          requestId: any(named: 'requestId'),
          approve: any(named: 'approve'),
        ),
      );

      // Barrier-dismiss = "Not now" (sheet resolves false). The row's busy
      // state must clear so the creator can retry after linking — a stuck
      // spinner here was the Gate R1 adversary's P2.
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('durableGate.continue')), findsNothing);

      await tester.tap(find.byKey(GroupKeys.claimApprove('rid')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('durableGate.continue')), findsOneWidget);
      verifyNever(
        () => fns.decideClaimRequest(
          groupId: any(named: 'groupId'),
          requestId: any(named: 'requestId'),
          approve: any(named: 'approve'),
        ),
      );
    },
  );
}
