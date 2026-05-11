import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/trip/models/trip_model.dart';

void main() {
  group('Trip.fromJson back-compat', () {
    test('tolerates legacy currency key after Phase 39 strip', () {
      final trip = Trip.fromJson({
        'id': 't1',
        'name': 'Test',
        'invite_code': 'ABC',
        'leader_id': 'u1',
        'modules': <String, dynamic>{},
        'created_at': '2026-04-26T00:00:00.000Z',
        'icon': 'airplane',
        // Legacy keys that pre-Phase-39 docs may still carry — must be silently ignored.
        'currency': 'USD',
      });
      expect(trip.id, 't1');
      expect(trip.name, 'Test');
      // No assertion on currency — field doesn't exist on Trip anymore.
    });

    test('round-trips SQLite JSON fields and optional dates', () {
      final trip = Trip(
        id: 't2',
        name: 'Muscat weekend',
        inviteCode: 'MCT123',
        leaderId: 'leader-1',
        modules: const TripModules(),
        createdAt: DateTime.utc(2026, 5, 1, 9),
        updatedAt: DateTime.utc(2026, 5, 2, 10),
        startDate: DateTime.utc(2026, 5, 10),
        endDate: DateTime.utc(2026, 5, 12),
        icon: 'camping',
      );

      final json = trip.toJson();
      final restored = Trip.fromJson(json);

      expect(restored.id, 't2');
      expect(restored.name, 'Muscat weekend');
      expect(restored.inviteCode, 'MCT123');
      expect(restored.leaderId, 'leader-1');
      expect(restored.icon, 'camping');
      expect(restored.createdAt, DateTime.utc(2026, 5, 1, 9));
      expect(restored.updatedAt, DateTime.utc(2026, 5, 2, 10));
      expect(restored.startDate, DateTime(2026, 5, 10));
      expect(restored.endDate, DateTime(2026, 5, 12));
      expect(json['start_date'], '2026-05-10');
      expect(json['end_date'], '2026-05-12');
    });

    test('uses defaults for omitted modules and icon', () {
      final trip = Trip.fromJson({
        'id': 't3',
        'name': 'No modules',
        'invite_code': 'NOMODS',
        'leader_id': 'u1',
        'created_at': '2026-05-01T00:00:00.000Z',
      });

      expect(trip.modules, isA<TripModules>());
      expect(trip.icon, 'airplane');
      expect(trip.updatedAt, isNull);
      expect(trip.startDate, isNull);
      expect(trip.endDate, isNull);
    });
  });

  group('Trip copy and date helpers', () {
    test('copyWith replaces selected fields and preserves the rest', () {
      final original = Trip(
        id: 't1',
        name: 'Original',
        inviteCode: 'ABC123',
        leaderId: 'leader-1',
        modules: const TripModules(),
        createdAt: DateTime.utc(2026),
      );

      final copy = original.copyWith(
        name: 'Updated',
        updatedAt: DateTime.utc(2026, 2),
        icon: 'ship',
      );

      expect(copy.id, original.id);
      expect(copy.name, 'Updated');
      expect(copy.inviteCode, original.inviteCode);
      expect(copy.updatedAt, DateTime.utc(2026, 2));
      expect(copy.icon, 'ship');
    });

    test('date helpers handle missing, future, active, and past trips', () {
      final noDates = Trip(
        id: 'none',
        name: 'No dates',
        inviteCode: 'NONE',
        leaderId: 'u1',
        modules: const TripModules(),
        createdAt: DateTime.now(),
      );
      expect(noDates.daysUntilStart, isNull);
      expect(noDates.isOngoing, isFalse);
      expect(noDates.isPast, isFalse);
      expect(noDates.totalDays, isNull);
      expect(noDates.daysIntoTrip, isNull);

      final future = noDates.copyWith(
        startDate: DateTime.now().add(const Duration(days: 3)),
        endDate: DateTime.now().add(const Duration(days: 5)),
      );
      expect(future.daysUntilStart, greaterThanOrEqualTo(0));
      expect(future.daysIntoTrip, isNull);
      expect(future.totalDays, 3);

      final active = noDates.copyWith(
        startDate: DateTime.now().subtract(const Duration(days: 1)),
        endDate: DateTime.now().add(const Duration(days: 1)),
      );
      expect(active.isOngoing, isTrue);
      expect(active.daysUntilStart, 0);
      expect(active.daysIntoTrip, greaterThanOrEqualTo(1));

      final past = noDates.copyWith(
        startDate: DateTime.now().subtract(const Duration(days: 5)),
        endDate: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(past.isPast, isTrue);
      expect(past.isOngoing, isFalse);
    });

    test('equality and hashCode are id-based', () {
      final a = Trip(
        id: 'same',
        name: 'A',
        inviteCode: 'A',
        leaderId: 'u1',
        modules: const TripModules(),
        createdAt: DateTime.utc(2026),
      );
      final b = a.copyWith(name: 'B', inviteCode: 'B');
      final c = a.copyWith(id: 'different');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('TripModules.fromJson back-compat', () {
    test('tolerates legacy gear/docs/logistics/memories keys', () {
      final modules = TripModules.fromJson(<String, dynamic>{
        'gear': true,
        'docs': true,
        'logistics': true,
        'memories': true,
      });
      // Surviving fields default; legacy keys are silently dropped.
      expect(modules, isA<TripModules>());
    });

    test('serializes as an empty marker object and copyWith stays empty', () {
      const modules = TripModules();

      expect(modules.toJson(), isEmpty);
      expect(modules.copyWith().toJson(), isEmpty);
    });
  });

  group('Participant model', () {
    test(
      'ParticipantRole.fromString maps known roles and defaults to member',
      () {
        expect(ParticipantRole.fromString('LEADER'), ParticipantRole.leader);
        expect(ParticipantRole.fromString('MEMBER'), ParticipantRole.member);
        expect(ParticipantRole.fromString('UNKNOWN'), ParticipantRole.member);
      },
    );

    test(
      'fromJson reads profile fallback fields and serializes cache fields',
      () {
        final participant = Participant.fromJson({
          'id': 'p1',
          'trip_id': 't1',
          'user_id': 'u1',
          'role': 'LEADER',
          'joined_at': '2026-05-01T00:00:00.000Z',
          'profiles': {
            'display_name': 'Nasser',
            'avatar_url': 'https://example.test/a.png',
          },
          'is_shadow': true,
        });

        expect(participant.role, ParticipantRole.leader);
        expect(participant.displayName, 'Nasser');
        expect(participant.avatarUrl, 'https://example.test/a.png');
        expect(participant.name, 'Nasser');
        expect(participant.isShadow, isTrue);

        final json = participant.toJson();
        expect(json['id'], 'p1');
        expect(json['trip_id'], 't1');
        expect(json['user_id'], 'u1');
        expect(json['role'], 'LEADER');
        expect(json['display_name'], 'Nasser');
        expect(json['is_shadow'], isTrue);
      },
    );

    test('fromJson prefers direct display name and defaults unknown names', () {
      final direct = Participant.fromJson({
        'id': 'p2',
        'trip_id': 't1',
        'joined_at': '2026-05-01T00:00:00.000Z',
        'display_name': 'Direct',
      });
      expect(direct.role, ParticipantRole.member);
      expect(direct.displayName, 'Direct');
      expect(direct.name, 'Direct');
      expect(direct.isShadow, isFalse);

      final unnamed = Participant.fromJson({
        'id': 'p3',
        'trip_id': 't1',
        'joined_at': '2026-05-01T00:00:00.000Z',
      });
      expect(unnamed.name, 'Unknown');
    });
  });
}
