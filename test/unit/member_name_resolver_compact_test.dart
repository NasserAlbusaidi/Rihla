import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/services/member_name_resolver.dart';

/// TDD RED — #289: wire `disambiguate` into the split/attribution surfaces.
///
/// These helpers don't exist yet; until they do this file fails to compile
/// (failureKind=not-implemented). They are the pure core the four un-wired
/// surfaces (payer picker, custom picker, split-preview, paid-by card, event
/// hub, ledger roster) will call so two same-named members stay distinct
/// exactly where money is attributed.
void main() {
  MemberDisplay live(String name) =>
      MemberDisplay(rawName: name, isFormer: false);

  Event eventWith(Map<String, String> names) => Event(
        id: 'event-1',
        name: 'Muscat weekend',
        type: EventType.trip,
        groupId: 'group-1',
        createdBy: names.keys.first,
        participantIds: names.keys.toList(),
        participantNames: names,
        modules: const EventModules(),
        createdAt: DateTime(2026, 6, 6),
      );

  GroupMember member(
    String uid,
    String name, {
    bool isTombstone = false,
  }) =>
      GroupMember(
        id: 'doc-$uid',
        groupId: 'group-1',
        userId: uid,
        displayName: name,
        role: 'member',
        isTombstone: isTombstone,
        joinedAt: DateTime(2026, 1, 1),
      );

  group('compactDisambiguated', () {
    test('collapses to first word when there is no discriminator', () {
      expect(MemberNameResolver.compactDisambiguated('Ahmed Ali'), 'Ahmed');
    });

    test('preserves the #196 discriminator while collapsing to first word', () {
      expect(
        MemberNameResolver.compactDisambiguated('Ahmed Ali (#a1b2)'),
        'Ahmed (#a1b2)',
      );
    });

    test('single-word name with discriminator keeps the suffix', () {
      expect(
        MemberNameResolver.compactDisambiguated('Ahmed (#a1b2)'),
        'Ahmed (#a1b2)',
      );
    });

    test('drops the former-member suffix in the compact form', () {
      expect(
        MemberNameResolver.compactDisambiguated('Ahmed (former member)'),
        'Ahmed',
      );
    });

    test('plain single word is returned unchanged', () {
      expect(MemberNameResolver.compactDisambiguated('Mama'), 'Mama');
    });
  });

  group('disambiguateEventParticipants', () {
    test('two live participants with the same name get distinct suffixes', () {
      final names = MemberNameResolver.disambiguateEventParticipants(
        eventWith({
          'uid-ahmed-1111': 'Ahmed',
          'uid-ahmed-2222': 'Ahmed',
          'uid-sara-3333': 'Sara',
        }),
      );

      expect(names['uid-ahmed-1111'], 'Ahmed (#1111)');
      expect(names['uid-ahmed-2222'], 'Ahmed (#2222)');
      // Non-colliding member stays bare.
      expect(names['uid-sara-3333'], 'Sara');
    });

    test('blank participant names are omitted (caller keeps its fallback)', () {
      final names = MemberNameResolver.disambiguateEventParticipants(
        eventWith({'uid-1': '', 'uid-2': 'Omar'}),
      );

      expect(names.containsKey('uid-1'), isFalse);
      expect(names['uid-2'], 'Omar');
    });
  });

  group('disambiguateEventScoped', () {
    test('two live members collide → both discriminated', () {
      final event = eventWith({
        'uid-ahmed-1111': 'Ahmed',
        'uid-ahmed-2222': 'Ahmed',
      });
      final names = MemberNameResolver.disambiguateEventScoped(
        event: event,
        members: [
          member('uid-ahmed-1111', 'Ahmed'),
          member('uid-ahmed-2222', 'Ahmed'),
        ],
      );

      expect(names['uid-ahmed-1111'], 'Ahmed (#1111)');
      expect(names['uid-ahmed-2222'], 'Ahmed (#2222)');
    });

    test(
        'a departed same-named member keeps "(former member)" and never gets '
        'a discriminator', () {
      final event = eventWith({'uid-ahmed-1111': 'Ahmed'});
      final names = MemberNameResolver.disambiguateEventScoped(
        event: event,
        members: [
          member('uid-ahmed-1111', 'Ahmed'),
          member('uid-ahmed-9999', 'Ahmed', isTombstone: true),
        ],
        uids: const ['uid-ahmed-1111', 'uid-ahmed-9999'],
      );

      // Only one LIVE Ahmed → no discriminator on the live entry.
      expect(names['uid-ahmed-1111'], 'Ahmed');
      expect(names['uid-ahmed-9999'], 'Ahmed (former member)');
      expect(names['uid-ahmed-9999'], isNot(contains('(#')));
    });
  });

  group('liveNameCounts + discriminatedLabel', () {
    test('live collider gets the suffix; a caller fallback name is preserved',
        () {
      final counts = MemberNameResolver.liveNameCounts([
        live('Ahmed'),
        live('Ahmed'),
        live('Sara'),
      ]);

      expect(
        MemberNameResolver.discriminatedLabel(
          'uid-ahmed-1111',
          live('Ahmed'),
          counts,
        ),
        'Ahmed (#1111)',
      );
      // Non-colliding name: no suffix.
      expect(
        MemberNameResolver.discriminatedLabel(
          'uid-sara-3333',
          live('Sara'),
          counts,
        ),
        'Sara',
      );
      // Former member (the fallbackName path) is returned via format(): the
      // persisted name survives, no discriminator even on a name collision.
      expect(
        MemberNameResolver.discriminatedLabel(
          'uid-ahmed-9999',
          const MemberDisplay(rawName: 'Ahmed', isFormer: true),
          counts,
        ),
        'Ahmed (former member)',
      );
    });
  });
}
