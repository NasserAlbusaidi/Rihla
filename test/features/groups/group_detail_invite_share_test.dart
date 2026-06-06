import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_detail_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #291 — "invite a friend" must be reachable directly from the group screen,
/// not buried in Group Settings. The header action reuses the existing
/// link-bearing share message (#277).
void main() {
  const groupId = 'group-1';
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

  final testGroup = Group(
    id: groupId,
    name: 'Adventure Crew',
    inviteCode: 'ABC123',
    createdBy: 'uid-creator',
    memberIds: const ['uid-creator', 'uid-member'],
    createdAt: DateTime(2026, 1, 1),
  );

  final members = [
    GroupMember(
      id: 'member-1',
      groupId: groupId,
      userId: 'uid-creator',
      displayName: 'Alice',
      role: 'CREATOR',
      joinedAt: DateTime(2026, 1, 1),
    ),
  ];

  final balances = (
    balances: <UserBalance>[
      UserBalance(
        participantId: 'uid-creator',
        displayName: 'Alice',
        totalPaid: Decimal.zero,
        totalOwed: Decimal.zero,
        netBalance: Decimal.zero,
      ),
    ],
    totalSpent: Decimal.zero,
    eventCount: 0,
    perEventBreakdown: <String, Map<String, Decimal>>{},
    memberNames: <String, String>{'uid-creator': 'Alice'},
    memberRawNames: <String, String>{},
  );

  Future<void> pumpGroupDetail(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'device_name': 'Alice'});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/group/$groupId',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '/group/:gid',
          builder: (_, state) =>
              GroupDetailScreen(groupId: state.pathParameters['gid']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('uid-creator'),
          groupDetailProvider(
            groupId,
          ).overrideWith((ref) => Stream.value(testGroup)),
          groupMembersProvider(
            groupId,
          ).overrideWith((ref) => Stream.value(members)),
          groupEventsProvider(
            groupId,
          ).overrideWith((ref) => Stream.value(const [])),
          groupBalancesProvider(
            groupId,
          ).overrideWith((ref) => AsyncValue.data(balances)),
          groupActivityProvider(
            groupId,
          ).overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('group screen header invite action shares the join link',
      (tester) async {
    String? sharedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      shareChannel,
      (call) async {
        if (call.method == 'share') {
          sharedText = (call.arguments as Map)['text'] as String?;
        }
        return '';
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        shareChannel,
        null,
      ),
    );

    await pumpGroupDetail(tester);

    expect(find.byKey(GroupKeys.groupDetailInviteButton), findsOneWidget);

    await tester.tap(find.byKey(GroupKeys.groupDetailInviteButton));
    await tester.pumpAndSettle();

    expect(sharedText, isNotNull);
    expect(sharedText, contains('https://rihla-safar.web.app/join/ABC123'));
  });

  // Regression for the iOS-only crash: Share.share without a non-zero
  // sharePositionOrigin throws PlatformException('sharePositionOrigin:
  // argument must be set') on iOS/iPadOS, silently breaking every share path.
  // The mock-the-text test above can't catch it, so assert the origin rect is
  // present and non-zero on the wire.
  testWidgets('group screen header invite passes a non-zero share origin (iOS)',
      (tester) async {
    Map<Object?, Object?>? shareArgs;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      shareChannel,
      (call) async {
        if (call.method == 'share') {
          shareArgs = call.arguments as Map<Object?, Object?>;
        }
        return '';
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        shareChannel,
        null,
      ),
    );

    await pumpGroupDetail(tester);

    await tester.tap(find.byKey(GroupKeys.groupDetailInviteButton));
    await tester.pumpAndSettle();

    expect(shareArgs, isNotNull);
    expect(shareArgs!['originWidth'], isA<double>());
    expect(shareArgs!['originHeight'], isA<double>());
    expect((shareArgs!['originWidth'] as double) > 0, isTrue);
    expect((shareArgs!['originHeight'] as double) > 0, isTrue);
  });
}
