import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/activity/screens/activity_feed_screen.dart';
import 'package:safar/features/activity/services/activity_service.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #928 — the event activity feed must render the GOOD rows even when one row is
/// malformed. Before the fence, `_loadPage`'s `.map` threw on a null `logText`
/// (an `as String` cast), the whole-page `catch (_)` set `_initialError`, and
/// the screen showed its error/empty state instead of the surviving rows.
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

  Future<void> seedGoodAndBad(FakeFirebaseFirestore db) async {
    final logs = db
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .collection('activity_logs');
    // Good row — newest (createdAt is the sort key, kept valid on both).
    await logs.doc('good').set({
      'id': 'good',
      'eventId': eventId,
      'category': 'MONEY',
      'eventType': 'CREATE',
      'logText': 'paid for dinner',
      'actorId': 'u1',
      'actorName': 'GoodActor',
      'metadata': <String, dynamic>{},
      'createdAt': DateTime.utc(2026, 2, 2).toIso8601String(),
    });
    // Malformed row — null logText (NOT the sort key) throws pre-fence.
    await logs.doc('bad').set({
      'id': 'bad',
      'eventId': eventId,
      'category': 'MONEY',
      'eventType': 'CREATE',
      'logText': null,
      'actorId': 'u1',
      'actorName': 'BadActor',
      'metadata': <String, dynamic>{},
      'createdAt': DateTime.utc(2026, 2, 1).toIso8601String(),
    });
  }

  Widget buildRoute(FakeFirebaseFirestore db) {
    final router = GoRouter(
      initialLocation: '/group/$groupId/event/$eventId/activity',
      routes: [
        GoRoute(
          path: '/group/:gid',
          builder: (c, s) =>
              Scaffold(body: Text('GroupDetail:${s.pathParameters['gid']}')),
          routes: [
            GoRoute(
              path: 'event/:eid',
              builder: (c, s) =>
                  Scaffold(body: Text('EventHub:${s.pathParameters['eid']}')),
              routes: [
                GoRoute(
                  path: 'activity',
                  builder: (c, s) => ActivityFeedScreen(
                    groupId: s.pathParameters['gid']!,
                    eventId: s.pathParameters['eid']!,
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
        eventDetailProvider(eventRef)
            .overrideWith((ref) => Stream<Event?>.value(event)),
        activityServiceProvider
            .overrideWithValue(ActivityService.withFirestore(db)),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  testWidgets('renders the good row and skips the malformed one', (tester) async {
    final db = FakeFirebaseFirestore();
    await seedGoodAndBad(db);

    await tester.pumpWidget(buildRoute(db));
    await tester.pump(const Duration(seconds: 1));

    // The surviving row's actor renders (a span inside Text.rich).
    expect(
      find.textContaining('GoodActor', findRichText: true),
      findsOneWidget,
    );
  });
}
