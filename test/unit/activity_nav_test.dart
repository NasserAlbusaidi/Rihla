import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/activity/utils/activity_nav.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';

GroupActivityLog _log({
  required String type,
  Map<String, dynamic> metadata = const {},
}) => GroupActivityLog(
  id: 'log-1',
  type: type,
  actorId: 'uid-1',
  actorName: 'Alice',
  description: 'desc',
  metadata: metadata,
  timestamp: DateTime(2026, 1, 1),
);

void main() {
  group('activityRowTarget event_settlement (#831)', () {
    test('with eventId → the event settle-up screen', () {
      expect(
        activityRowTarget(
          groupId: 'g1',
          log: _log(
            type: 'event_settlement',
            metadata: const {'eventId': 'e1', 'fromName': 'Ali'},
          ),
        ),
        '/group/g1/event/e1/ledger/settle-up',
      );
    });

    test('missing/empty/forged eventId degrades to group detail', () {
      expect(
        activityRowTarget(groupId: 'g1', log: _log(type: 'event_settlement')),
        '/group/g1',
      );
      expect(
        activityRowTarget(
          groupId: 'g1',
          log: _log(type: 'event_settlement', metadata: const {'eventId': ''}),
        ),
        '/group/g1',
      );
      expect(
        activityRowTarget(
          groupId: 'g1',
          log: _log(type: 'event_settlement', metadata: const {'eventId': 7}),
        ),
        '/group/g1',
      );
    });

    test('group_settlement keeps its group settle-up target (unchanged)', () {
      expect(
        activityRowTarget(groupId: 'g1', log: _log(type: 'group_settlement')),
        '/group/g1/settle-up',
      );
    });
  });

  group('activityRowTarget member_resplit (#1059)', () {
    test('with eventId (single affected event) → that event ledger, where the '
        're-split money lives', () {
      expect(
        activityRowTarget(
          groupId: 'g1',
          log: _log(
            type: 'member_resplit',
            metadata: const {'eventId': 'e1', 'eventName': 'Trip'},
          ),
        ),
        '/group/g1/event/e1/ledger',
      );
    });

    test('missing/empty/forged eventId (multi-event or malformed-name row) '
        'degrades to group detail', () {
      expect(
        activityRowTarget(groupId: 'g1', log: _log(type: 'member_resplit')),
        '/group/g1',
      );
      expect(
        activityRowTarget(
          groupId: 'g1',
          log: _log(type: 'member_resplit', metadata: const {'eventId': ''}),
        ),
        '/group/g1',
      );
      expect(
        activityRowTarget(
          groupId: 'g1',
          log: _log(type: 'member_resplit', metadata: const {'eventId': 42}),
        ),
        '/group/g1',
      );
    });
  });
}
