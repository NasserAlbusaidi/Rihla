import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/notification_prompt.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/join_group_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// #1275: leaving the join screen while the joinGroup callable is in flight
// disposed the ConsumerState under _doJoin's awaited continuation. The
// unguarded post-await ref.read threw StateError('Cannot use "ref" after the
// widget was disposed.') — twice: the success path threw at :161, the catch
// swallowed it and threw again at :173 before its own mounted guard — and
// groupLoadingProvider (a plain global StateProvider, never autoDisposed) was
// stranded true, dead-locking the Join CTA app-wide until restart.

class _MockGroupService extends Mock implements GroupService {}

class _NoopPrompt implements NotificationPrompt {
  @override
  Future<void> maybePrompt() async {}
}

Group _joinedGroup() => Group(
  id: 'g1',
  name: 'Trip',
  inviteCode: 'ABCD23',
  createdBy: 'u1',
  memberIds: const ['u1'],
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  testWidgets(
    '#1275: leaving mid-join neither throws nor strands groupLoadingProvider',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final joinCompleter = Completer<Group>();
      final groupService = _MockGroupService();
      when(
        () => groupService.joinGroup(inviteCode: any(named: 'inviteCode')),
      ).thenAnswer((_) => joinCompleter.future);

      final router = GoRouter(
        initialLocation: '/join',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('Home')),
          ),
          GoRoute(path: '/join', builder: (_, _) => const JoinGroupScreen()),
          GoRoute(
            path: '/group/:id',
            builder: (_, _) => const Scaffold(body: Text('group-landing')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupServiceProvider.overrideWithValue(groupService),
            notificationPromptProvider.overrideWithValue(_NoopPrompt()),
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

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );

      // Name + a complete valid-alphabet code → the #293 auto-submit fires.
      // Plain pump()s from here: the in-flight LoadingButton spinner never
      // settles, so pumpAndSettle would time out.
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Tester');
      await tester.pump();
      await tester.enterText(fields.at(1), 'ABCD23');
      await tester.pump();
      await tester.pump();

      // In flight: the callable was invoked and has not resolved.
      verify(() => groupService.joinGroup(inviteCode: 'ABCD23')).called(1);
      expect(joinCompleter.isCompleted, isFalse);
      expect(container.read(groupLoadingProvider), isTrue);

      // Navigate away mid-join — disposes the screen (nothing blocks back
      // while the callable is pending).
      router.go('/home');
      await tester.pumpAndSettle();
      expect(find.byType(JoinGroupScreen), findsNothing);

      // The callable now succeeds against the disposed screen.
      joinCompleter.complete(_joinedGroup());
      await tester.pumpAndSettle();

      // RED before the fix: the framework reports 'Bad state: Cannot use
      // "ref" after the widget was disposed.' from _doJoin's continuation.
      expect(tester.takeException(), isNull);

      // And the global loading flag must be released — stranded true it
      // dead-locks every future join attempt until app restart.
      expect(
        container.read(groupLoadingProvider),
        isFalse,
        reason:
            'groupLoadingProvider stranded true dead-locks the Join CTA '
            'app-wide (#1275)',
      );

      // The user left before the route push — no navigation into the group.
      expect(find.text('group-landing'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    },
  );
}
