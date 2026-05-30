import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Build a minimal [Group] for testing.
Group _makeGroup({required String id, required String name}) {
  return Group(
    id: id,
    name: name,
    inviteCode: 'AAAAAA',
    createdBy: 'uid-user',
    memberIds: const ['uid-user'],
    createdAt: DateTime(2025, 1, 1),
  );
}

/// Build a [GroupActivityLog] with a given timestamp.
GroupActivityLog _makeLog({required String id, required DateTime timestamp}) {
  return GroupActivityLog(
    id: id,
    type: 'expense_added',
    actorId: 'uid-user',
    actorName: 'User',
    description: 'Added expense',
    timestamp: timestamp,
  );
}

/// Pump the provider container until the synchronous Provider body re-evaluates.
Future<void> _pump(ProviderContainer container) async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  // ---------------------------------------------------------------------------
  // crossGroupActivityProvider
  // ---------------------------------------------------------------------------
  group('crossGroupActivityProvider', () {
    test('returns empty list when no groups exist', () async {
      final container = ProviderContainer(
        overrides: [userGroupsProvider.overrideWith((_) => Stream.value([]))],
      );
      addTearDown(container.dispose);

      container.listen(
        crossGroupActivityProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await _pump(container);

      final result = container.read(crossGroupActivityProvider);
      expect(result, isA<AsyncData<List<CrossGroupActivityEntry>>>());
      expect(result.valueOrNull, isEmpty);
    });

    test(
      'merges 2 groups activity into chronological order (newest first)',
      () async {
        final group1 = _makeGroup(id: 'g1', name: 'Group 1');
        final group2 = _makeGroup(id: 'g2', name: 'Group 2');

        // g1 has an older entry, g2 has a newer entry
        final log1 = _makeLog(id: 'log-g1', timestamp: DateTime(2025, 1, 1));
        final log2 = _makeLog(id: 'log-g2', timestamp: DateTime(2025, 1, 2));

        final container = ProviderContainer(
          overrides: [
            userGroupsProvider.overrideWith(
              (_) => Stream.value([group1, group2]),
            ),
            groupActivityProvider(
              'g1',
            ).overrideWith((_) => Stream.value([log1])),
            groupActivityProvider(
              'g2',
            ).overrideWith((_) => Stream.value([log2])),
          ],
        );
        addTearDown(container.dispose);

        container.listen(
          crossGroupActivityProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await _pump(container);

        final result = container.read(crossGroupActivityProvider);
        expect(result, isA<AsyncData<List<CrossGroupActivityEntry>>>());
        final entries = result.valueOrNull!;

        expect(entries.length, equals(2));
        // newest first: log2 (Jan 2) before log1 (Jan 1)
        expect(entries[0].log.id, equals('log-g2'));
        expect(entries[1].log.id, equals('log-g1'));
      },
    );

    test('limits to 5 entries total', () async {
      final group1 = _makeGroup(id: 'g1', name: 'Group 1');

      // 7 log entries for a single group — result must be capped at 5
      final logs = List.generate(
        7,
        (i) => _makeLog(id: 'log-$i', timestamp: DateTime(2025, 1, i + 1)),
      );

      final container = ProviderContainer(
        overrides: [
          userGroupsProvider.overrideWith((_) => Stream.value([group1])),
          groupActivityProvider('g1').overrideWith((_) => Stream.value(logs)),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        crossGroupActivityProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await _pump(container);

      final result = container.read(crossGroupActivityProvider);
      expect(result, isA<AsyncData<List<CrossGroupActivityEntry>>>());
      expect(result.valueOrNull!.length, equals(5));
    });
  });
}
