import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/activity/models/activity_log_model.dart';
import 'package:safar/features/activity/screens/activity_feed_screen.dart';
import 'package:safar/features/activity/services/activity_service.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';

void main() {
  const groupId = 'group-1';
  const eventId = 'event-1';
  const eventRef = (groupId: groupId, eventId: eventId);

  final event = Event(
    id: eventId,
    groupId: groupId,
    name: 'Beach Trip',
    type: EventType.trip,
    createdBy: 'uid-creator',
    participantIds: const ['uid-creator'],
    participantNames: const {'uid-creator': 'Alice'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 1, 1),
  );

  Widget buildRoute() {
    final router = GoRouter(
      initialLocation: '/group/$groupId/event/$eventId/activity',
      routes: [
        GoRoute(
          path: '/group/:gid',
          builder: (context, state) =>
              Scaffold(body: Text('GroupDetail:${state.pathParameters['gid']}')),
          routes: [
            GoRoute(
              path: 'event/:eid',
              builder: (context, state) =>
                  Scaffold(body: Text('EventHub:${state.pathParameters['eid']}')),
              routes: [
                GoRoute(
                  path: 'activity',
                  builder: (context, state) => ActivityFeedScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    return ProviderScope(
      overrides: [
        eventDetailProvider(
          eventRef,
        ).overrideWith((ref) => Stream<Event?>.value(event)),
        eventActivityProvider(
          eventRef,
        ).overrideWith((ref) => Stream.value(const <ActivityLog>[])),
      ],
      child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
    );
  }

  testWidgets('direct route back button returns to event hub', (tester) async {
    await tester.pumpWidget(buildRoute());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Iconsax.arrow_left));
    await tester.pumpAndSettle();

    expect(find.text('EventHub:$eventId'), findsOneWidget);
  });
}
