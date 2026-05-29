import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/trip/models/trip_model.dart';

void main() {
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
