import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/services/member_name_resolver.dart';

void main() {
  final joinedAt = DateTime(2026, 5, 17);

  GroupMember member(String uid, String name, {bool isTombstone = false}) {
    return GroupMember(
      id: 'member-$uid',
      groupId: 'group-1',
      userId: uid,
      displayName: name,
      role: 'MEMBER',
      isTombstone: isTombstone,
      joinedAt: joinedAt,
    );
  }

  Event event({
    List<String> participantIds = const [],
    Map<String, String> participantNames = const {},
  }) {
    return Event(
      id: 'event-1',
      name: 'Camp',
      type: EventType.camping,
      groupId: 'group-1',
      createdBy: 'alice',
      participantIds: participantIds,
      participantNames: participantNames,
      modules: const EventModules(),
      createdAt: joinedAt,
    );
  }

  group('resolveGroupScoped', () {
    test('returns live member names without former status', () {
      final display = MemberNameResolver.resolveGroupScoped(
        uid: 'alice',
        members: [member('alice', 'Alice')],
        fallbackName: 'Fallback',
      );

      expect(display.rawName, 'Alice');
      expect(display.isFormer, isFalse);
      expect(MemberNameResolver.format(display), 'Alice');
    });

    test('live members win over tombstones for the same uid', () {
      final display = MemberNameResolver.resolveGroupScoped(
        uid: 'alice',
        members: [
          member('alice', 'Deleted Alice', isTombstone: true),
          member('alice', 'Alice'),
        ],
      );

      expect(display.rawName, 'Alice');
      expect(display.isFormer, isFalse);
    });

    test('marks tombstones, fallback names, and last resort as former', () {
      final tombstone = MemberNameResolver.resolveGroupScoped(
        uid: 'old',
        members: [member('old', 'Old Name', isTombstone: true)],
      );
      final fallback = MemberNameResolver.resolveGroupScoped(
        uid: 'orphan',
        members: const [],
        fallbackName: 'Aisha',
      );
      final lastResort = MemberNameResolver.resolveGroupScoped(
        uid: 'missing',
        members: const [],
      );

      expect(MemberNameResolver.format(tombstone), 'Old Name (former member)');
      expect(MemberNameResolver.format(fallback), 'Aisha (former member)');
      expect(lastResort.rawName, MemberNameResolver.formerMemberLiteral);
      expect(
        MemberNameResolver.format(lastResort),
        'Former member (former member)',
      );
    });
  });

  group('resolveEventScoped', () {
    test('uses historical event participant name first', () {
      final display = MemberNameResolver.resolveEventScoped(
        uid: 'alice',
        event: event(participantNames: const {'alice': 'Alice at Camp'}),
        members: [member('alice', 'Alice Today')],
      );

      expect(display.rawName, 'Alice at Camp');
      expect(display.isFormer, isFalse);
    });

    test(
      'marks event participant names former when there is no live member',
      () {
        final display = MemberNameResolver.resolveEventScoped(
          uid: 'orphan',
          event: event(participantNames: const {'orphan': 'Aisha'}),
          members: const [],
        );

        expect(MemberNameResolver.format(display), 'Aisha (former member)');
      },
    );

    test(
      'falls back through live, tombstone, caller fallback, and last resort',
      () {
        final live = MemberNameResolver.resolveEventScoped(
          uid: 'bob',
          event: event(),
          members: [member('bob', 'Bob')],
        );
        final tombstone = MemberNameResolver.resolveEventScoped(
          uid: 'old',
          event: event(),
          members: [member('old', 'Old Name', isTombstone: true)],
        );
        final fallback = MemberNameResolver.resolveEventScoped(
          uid: 'legacy',
          event: event(),
          members: const [],
          fallbackName: 'Legacy Name',
        );
        final lastResort = MemberNameResolver.resolveEventScoped(
          uid: 'missing',
          event: event(),
          members: const [],
        );

        expect(MemberNameResolver.format(live), 'Bob');
        expect(
          MemberNameResolver.format(tombstone),
          'Old Name (former member)',
        );
        expect(
          MemberNameResolver.format(fallback),
          'Legacy Name (former member)',
        );
        expect(
          MemberNameResolver.format(lastResort),
          'Former member (former member)',
        );
      },
    );
  });

  test('stripFormerSuffix removes only the reserved trailing suffix', () {
    expect(
      MemberNameResolver.stripFormerSuffix('Aisha (former member)'),
      'Aisha',
    );
    expect(
      MemberNameResolver.stripFormerSuffix('(former member) Aisha'),
      '(former member) Aisha',
    );
    expect(MemberNameResolver.stripFormerSuffix('Aisha'), 'Aisha');
  });
}
