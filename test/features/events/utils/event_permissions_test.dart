import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/utils/event_permissions.dart';
import 'package:safar/features/groups/models/group_model.dart';

Group _group({
  String createdBy = 'uid-group-creator',
}) => Group(
      id: 'g1',
      name: 'Trip Squad',
      inviteCode: 'ABCDEF',
      createdBy: createdBy,
      memberIds: const [
        'uid-group-creator',
        'uid-event-creator',
        'uid-participant',
        'uid-outsider',
      ],
      createdAt: DateTime(2026, 1, 1),
    );

Event _event({
  String createdBy = 'uid-event-creator',
}) => Event(
      id: 'e1',
      name: 'Beach Day',
      type: EventType.trip,
      groupId: 'g1',
      createdBy: createdBy,
      participantIds: const ['uid-event-creator', 'uid-participant'],
      participantNames: const {
        'uid-event-creator': 'Bob',
        'uid-participant': 'Carol',
      },
      modules: EventModules.forType(EventType.trip),
      createdAt: DateTime(2026, 2, 1),
    );

void main() {
  group('EventPermissions.isEventAdmin', () {
    test('event creator is admin', () {
      expect(
        EventPermissions.isEventAdmin(
          event: _event(),
          group: _group(),
          currentUserId: 'uid-event-creator',
        ),
        isTrue,
      );
    });

    test('group creator is admin even when not event creator', () {
      expect(
        EventPermissions.isEventAdmin(
          event: _event(),
          group: _group(),
          currentUserId: 'uid-group-creator',
        ),
        isTrue,
      );
    });

    test('ordinary participant is NOT admin', () {
      expect(
        EventPermissions.isEventAdmin(
          event: _event(),
          group: _group(),
          currentUserId: 'uid-participant',
        ),
        isFalse,
      );
    });

    test('group member who is not a participant is NOT admin', () {
      expect(
        EventPermissions.isEventAdmin(
          event: _event(),
          group: _group(),
          currentUserId: 'uid-outsider',
        ),
        isFalse,
      );
    });

    test('null currentUserId is NOT admin', () {
      expect(
        EventPermissions.isEventAdmin(
          event: _event(),
          group: _group(),
          currentUserId: null,
        ),
        isFalse,
      );
    });

    test('empty currentUserId is NOT admin', () {
      expect(
        EventPermissions.isEventAdmin(
          event: _event(),
          group: _group(),
          currentUserId: '',
        ),
        isFalse,
      );
    });

    test('one user creating both group and event is admin once', () {
      final solo = _event(createdBy: 'uid-solo');
      final soloGroup = _group(createdBy: 'uid-solo');
      expect(
        EventPermissions.isEventAdmin(
          event: solo,
          group: soloGroup,
          currentUserId: 'uid-solo',
        ),
        isTrue,
      );
    });
  });
}
