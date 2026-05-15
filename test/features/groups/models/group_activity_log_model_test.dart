import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';

void main() {
  group('GroupActivityLog.fromFirestore', () {
    test('parses ISO 8601 string timestamp', () {
      final log = GroupActivityLog.fromFirestore({
        'id': 'a1',
        'type': 'event_created',
        'actorId': 'uid-1',
        'actorName': 'Alice',
        'description': 'Created event Beach Day',
        'metadata': {'eventId': 'e1'},
        'timestamp': '2026-03-01T12:00:00Z',
      });

      expect(log.id, 'a1');
      expect(log.type, 'event_created');
      expect(log.actorId, 'uid-1');
      expect(log.actorName, 'Alice');
      expect(log.description, 'Created event Beach Day');
      expect(log.metadata, {'eventId': 'e1'});
      expect(log.timestamp.toUtc(), DateTime.utc(2026, 3, 1, 12));
    });

    test('parses Firestore Timestamp objects', () {
      final source = DateTime.utc(2026, 4, 1);
      final ts = Timestamp.fromDate(source);
      final log = GroupActivityLog.fromFirestore({
        'id': 'a2',
        'type': 'member_joined',
        'actorId': 'uid-1',
        'actorName': 'Alice',
        'description': 'joined',
        'timestamp': ts,
      });

      expect(log.timestamp.toUtc(), source);
    });

    test('falls back to now() for null timestamp (pending writes)', () {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final log = GroupActivityLog.fromFirestore({
        'id': 'a3',
        'type': 'member_left',
        'actorId': 'uid-1',
        'actorName': 'Alice',
        'description': 'left',
        // timestamp omitted
      });
      final after = DateTime.now().add(const Duration(seconds: 1));
      expect(log.timestamp.isAfter(before), isTrue);
      expect(log.timestamp.isBefore(after), isTrue);
    });

    test('defaults actorName to "Unknown" when missing', () {
      final log = GroupActivityLog.fromFirestore({
        'id': 'a4',
        'type': 'event_deleted',
        'actorId': 'uid-1',
        'description': 'deleted',
        'timestamp': '2026-03-01T00:00:00Z',
      });
      expect(log.actorName, 'Unknown');
    });

    test('defaults metadata to empty when missing', () {
      final log = GroupActivityLog.fromFirestore({
        'id': 'a5',
        'type': 'group_settlement',
        'actorId': 'uid-1',
        'actorName': 'Alice',
        'description': 'paid',
        'timestamp': '2026-03-01T00:00:00Z',
      });
      expect(log.metadata, isEmpty);
    });
  });

  group('GroupActivityLog equality + toString', () {
    GroupActivityLog with_(String id) => GroupActivityLog(
          id: id,
          type: 'event_created',
          actorId: 'uid-1',
          actorName: 'Alice',
          description: 'd',
          timestamp: DateTime(2026, 3, 1),
        );

    test('equality is id-based', () {
      expect(with_('a') == with_('a'), isTrue);
      expect(with_('a') == with_('b'), isFalse);
      expect(with_('a').hashCode, with_('a').hashCode);
    });

    test('identical instances are equal', () {
      final log = with_('a');
      expect(log == log, isTrue);
    });

    test('toString includes id, type, description', () {
      final s = with_('xyz').toString();
      expect(s, contains('xyz'));
      expect(s, contains('event_created'));
      expect(s, contains('d'));
    });
  });
}
