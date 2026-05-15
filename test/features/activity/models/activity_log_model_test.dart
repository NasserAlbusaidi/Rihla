import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/activity/models/activity_log_model.dart';

void main() {
  group('ActivityLog.fromJson', () {
    test('parses minimal payload without actor', () {
      final log = ActivityLog.fromJson({
        'id': 'a1',
        'trip_id': 't1',
        'category': 'MONEY',
        'event_type': 'CREATE',
        'log_text': 'Expense added',
        'created_at': '2026-03-01T12:00:00Z',
      });

      expect(log.id, 'a1');
      expect(log.tripId, 't1');
      expect(log.actorId, isNull);
      expect(log.targetParticipantId, isNull);
      expect(log.category, 'MONEY');
      expect(log.eventType, 'CREATE');
      expect(log.logText, 'Expense added');
      expect(log.metadata, isEmpty);
      expect(log.createdAt.toUtc(), DateTime.utc(2026, 3, 1, 12));
      expect(log.actorName, isNull);
      expect(log.actorAvatar, isNull);
    });

    test('parses all optional fields when present', () {
      final log = ActivityLog.fromJson({
        'id': 'a1',
        'trip_id': 't1',
        'actor_id': 'uid-1',
        'target_participant_id': 'uid-2',
        'category': 'MONEY',
        'event_type': 'UPDATE',
        'log_text': 'Updated expense',
        'metadata': {'amount': '12.50'},
        'created_at': '2026-03-01T12:00:00Z',
        'actor': {
          'display_name': 'Alice',
          'avatar_url': 'https://x/y.png',
        },
      });

      expect(log.actorId, 'uid-1');
      expect(log.targetParticipantId, 'uid-2');
      expect(log.metadata, {'amount': '12.50'});
      expect(log.actorName, 'Alice');
      expect(log.actorAvatar, 'https://x/y.png');
    });

    test('replaces "Someone paid" with actor display name', () {
      final log = ActivityLog.fromJson({
        'id': 'a1',
        'trip_id': 't1',
        'category': 'MONEY',
        'event_type': 'CREATE',
        'log_text': 'Someone paid 10 OMR',
        'created_at': '2026-03-01T00:00:00Z',
        'actor': {'display_name': 'Bob'},
      });
      expect(log.logText, 'Bob paid 10 OMR');
    });

    test('replaces "Someone made" with actor display name', () {
      final log = ActivityLog.fromJson({
        'id': 'a1',
        'trip_id': 't1',
        'category': 'MONEY',
        'event_type': 'CREATE',
        'log_text': 'Someone made a payment',
        'created_at': '2026-03-01T00:00:00Z',
        'actor': {'display_name': 'Bob'},
      });
      expect(log.logText, 'Bob made a payment');
    });

    test('replaces lowercase "user paid" variant', () {
      final log = ActivityLog.fromJson({
        'id': 'a1',
        'trip_id': 't1',
        'category': 'MONEY',
        'event_type': 'CREATE',
        'log_text': 'user paid 5 OMR',
        'created_at': '2026-03-01T00:00:00Z',
        'actor': {'display_name': 'Carol'},
      });
      expect(log.logText, 'Carol paid 5 OMR');
    });

    test('replaces capitalized "User paid" variant', () {
      final log = ActivityLog.fromJson({
        'id': 'a1',
        'trip_id': 't1',
        'category': 'MONEY',
        'event_type': 'CREATE',
        'log_text': 'User paid 5 OMR',
        'created_at': '2026-03-01T00:00:00Z',
        'actor': {'display_name': 'Carol'},
      });
      expect(log.logText, 'Carol paid 5 OMR');
    });

    test('replaces lowercase "user made" variant', () {
      final log = ActivityLog.fromJson({
        'id': 'a1',
        'trip_id': 't1',
        'category': 'MONEY',
        'event_type': 'CREATE',
        'log_text': 'user made a payment',
        'created_at': '2026-03-01T00:00:00Z',
        'actor': {'display_name': 'Dave'},
      });
      expect(log.logText, 'Dave made a payment');
    });

    test('replaces capitalized "User made" variant', () {
      final log = ActivityLog.fromJson({
        'id': 'a1',
        'trip_id': 't1',
        'category': 'MONEY',
        'event_type': 'CREATE',
        'log_text': 'User made a payment',
        'created_at': '2026-03-01T00:00:00Z',
        'actor': {'display_name': 'Dave'},
      });
      expect(log.logText, 'Dave made a payment');
    });

    test('does not substitute when display_name is empty', () {
      final log = ActivityLog.fromJson({
        'id': 'a1',
        'trip_id': 't1',
        'category': 'MONEY',
        'event_type': 'CREATE',
        'log_text': 'Someone paid 10 OMR',
        'created_at': '2026-03-01T00:00:00Z',
        'actor': {'display_name': ''},
      });
      expect(log.logText, 'Someone paid 10 OMR');
    });
  });

  group('ActivityLog.fromFirestore + toFirestore', () {
    test('fromFirestore parses camelCase keys, tripId from eventId', () {
      final log = ActivityLog.fromFirestore({
        'id': 'a1',
        'eventId': 'evt-1',
        'actorId': 'uid-1',
        'targetParticipantId': 'uid-2',
        'category': 'MONEY',
        'eventType': 'UPDATE',
        'logText': 'updated',
        'metadata': {'k': 'v'},
        'createdAt': '2026-03-01T00:00:00Z',
        'actorName': 'Alice',
        'actorAvatar': 'https://x/y.png',
      });

      expect(log.id, 'a1');
      expect(log.tripId, 'evt-1');
      expect(log.actorId, 'uid-1');
      expect(log.targetParticipantId, 'uid-2');
      expect(log.eventType, 'UPDATE');
      expect(log.logText, 'updated');
      expect(log.metadata, {'k': 'v'});
      expect(log.actorName, 'Alice');
      expect(log.actorAvatar, 'https://x/y.png');
    });

    test('fromFirestore defaults metadata to empty map when missing', () {
      final log = ActivityLog.fromFirestore({
        'id': 'a1',
        'eventId': 'evt-1',
        'category': 'MONEY',
        'eventType': 'CREATE',
        'logText': 'x',
        'createdAt': '2026-03-01T00:00:00Z',
      });
      expect(log.metadata, isEmpty);
    });

    test('toFirestore round-trips through fromFirestore', () {
      final original = ActivityLog(
        id: 'a1',
        tripId: 't1',
        actorId: 'uid-1',
        targetParticipantId: 'uid-2',
        category: 'MONEY',
        eventType: 'DELETE',
        logText: 'deleted',
        metadata: const {'amount': '5.00'},
        createdAt: DateTime.utc(2026, 3, 1, 12),
        actorName: 'Alice',
      );

      final map = original.toFirestore();
      expect(map['eventId'], 't1');
      expect(map['createdAt'], '2026-03-01T12:00:00.000Z');

      final restored = ActivityLog.fromFirestore(map);
      expect(restored.id, original.id);
      expect(restored.tripId, original.tripId);
      expect(restored.actorId, original.actorId);
      expect(restored.targetParticipantId, original.targetParticipantId);
      expect(restored.category, original.category);
      expect(restored.eventType, original.eventType);
      expect(restored.logText, original.logText);
      expect(restored.metadata, original.metadata);
      expect(restored.actorName, original.actorName);
    });
  });

  group('event type getters', () {
    ActivityLog withType(String type) => ActivityLog(
          id: 'a1',
          tripId: 't1',
          category: 'MONEY',
          eventType: type,
          logText: 'x',
          createdAt: DateTime(2026, 3, 1),
        );

    test('isCreate true for CREATE', () {
      expect(withType('CREATE').isCreate, isTrue);
      expect(withType('CREATE').isUpdate, isFalse);
      expect(withType('CREATE').isDelete, isFalse);
    });

    test('isUpdate true for UPDATE', () {
      expect(withType('UPDATE').isUpdate, isTrue);
      expect(withType('UPDATE').isCreate, isFalse);
      expect(withType('UPDATE').isDelete, isFalse);
    });

    test('isDelete true for DELETE', () {
      expect(withType('DELETE').isDelete, isTrue);
      expect(withType('DELETE').isCreate, isFalse);
      expect(withType('DELETE').isUpdate, isFalse);
    });
  });
}
