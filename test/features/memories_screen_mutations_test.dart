import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/types/event_ref.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/memories/providers/memory_provider.dart';
import 'package:safar/features/memories/screens/memories_screen.dart';
import 'package:safar/shared/widgets/offline_banner.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

final _testEvent = Event(
  id: 'event-1',
  name: 'Camping Trip',
  type: EventType.camping,
  groupId: 'group-1',
  createdBy: 'uid-creator',
  participantIds: const ['uid-creator', 'test-user-uid'],
  participantNames: const {
    'uid-creator': 'Alice',
    'test-user-uid': 'Bob',
  },
  modules: const EventModules(
    ledger: true,
    gear: false,
    logistics: false,
    vault: false,
    memories: true,
  ),
  currency: 'OMR',
  createdAt: DateTime(2026, 3, 1),
);

final EventRef _testEventRef = (groupId: 'group-1', eventId: 'event-1');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrapMemoriesScreen() {
  return ProviderScope(
    overrides: [
      eventDetailProvider(_testEventRef).overrideWith(
        (ref) => Stream.value(_testEvent),
      ),
      eventMemoriesProvider(_testEventRef).overrideWith(
        (ref) => Stream.value([]),
      ),
    ],
    child: const MaterialApp(
      home: MemoriesScreen(groupId: 'group-1', eventId: 'event-1'),
    ),
  );
}

void main() {
  group('MemoriesScreen — offline banner', () {
    testWidgets('MemoriesScreen — OfflineBanner renders in body',
        (tester) async {
      await tester.pumpWidget(_wrapMemoriesScreen());
      await tester.pumpAndSettle();

      expect(find.byType(OfflineBanner), findsOneWidget);
    });
  });
}
