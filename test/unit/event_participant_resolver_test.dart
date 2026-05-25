import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/services/event_participant_resolver.dart';
import 'package:safar/features/groups/services/member_name_resolver.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';

void main() {
  Event event({
    List<String> participantIds = const ['alice', 'bob'],
    Map<String, String> participantNames = const {
      'alice': 'Alice',
      'bob': 'Bob',
    },
  }) {
    return Event(
      id: 'evt-1',
      name: 'Trip',
      type: EventType.trip,
      groupId: 'grp-1',
      createdBy: 'alice',
      participantIds: participantIds,
      participantNames: participantNames,
      modules: const EventModules(),
      createdAt: DateTime(2026, 1, 1),
    );
  }

  GroupMember member({
    required String uid,
    required String name,
    bool isTombstone = false,
  }) {
    return GroupMember(
      id: 'member-$uid',
      groupId: 'grp-1',
      userId: uid,
      displayName: name,
      role: 'MEMBER',
      isTombstone: isTombstone,
      joinedAt: DateTime(2026, 1, 1),
    );
  }

  Expense expense({
    required String id,
    required String payerId,
    String amount = '10.000',
    String? payerName,
    ExpenseScope scope = ExpenseScope.global,
    List<String>? customSplitParticipants,
    Map<String, Decimal>? splitDistribution,
    SplitMode? splitMode,
    bool isDeleted = false,
  }) {
    return Expense(
      id: id,
      tripId: 'evt-1',
      payerParticipantId: payerId,
      payerName: payerName,
      amount: Decimal.parse(amount),
      scope: scope,
      customSplitParticipants: customSplitParticipants,
      splitDistribution: splitDistribution,
      splitMode: splitMode,
      createdAt: DateTime(2026, 1, 2),
      isDeleted: isDeleted,
    );
  }

  Settlement settlement({
    required String id,
    String? payerId,
    String? recipientId,
    String amount = '5.000',
    String? payerName,
    String? recipientName,
    bool isDeleted = false,
  }) {
    return Settlement(
      id: id,
      tripId: 'evt-1',
      payerParticipantId: payerId,
      recipientParticipantId: recipientId,
      amount: Decimal.parse(amount),
      payerName: payerName,
      recipientName: recipientName,
      settledAt: DateTime(2026, 1, 3),
      isDeleted: isDeleted,
    );
  }

  MemberDisplay Function(String, {String? fallbackName}) eventScoped(
    Event e,
    List<GroupMember> members,
  ) {
    return (uid, {String? fallbackName}) => MemberNameResolver.resolveEventScoped(
      uid: uid,
      event: e,
      members: members,
      fallbackName: fallbackName,
    );
  }

  group('buildEventParticipants — union arithmetic', () {
    test('UID only as expense payer is included', () {
      final e = event(participantIds: ['alice'], participantNames: {'alice': 'Alice'});
      final members = [member(uid: 'alice', name: 'Alice')];
      final result = buildEventParticipants(
        event: e,
        expenses: [expense(id: 'x1', payerId: 'orphan', amount: '5.000')],
        settlements: const [],
        resolveDisplay: eventScoped(e, members),
      );
      expect(
        result.participants.map((p) => p.id).toSet(),
        {'alice', 'orphan'},
      );
    });

    test('UID only in customSplitParticipants is included', () {
      final e = event(participantIds: ['alice'], participantNames: {'alice': 'Alice'});
      final members = [member(uid: 'alice', name: 'Alice')];
      final result = buildEventParticipants(
        event: e,
        expenses: [
          expense(
            id: 'x1',
            payerId: 'alice',
            scope: ExpenseScope.custom,
            customSplitParticipants: const ['alice', 'orphan'],
          ),
        ],
        settlements: const [],
        resolveDisplay: eventScoped(e, members),
      );
      expect(
        result.participants.map((p) => p.id).toSet(),
        {'alice', 'orphan'},
      );
    });

    test('UID only in splitDistribution.keys is included', () {
      final e = event(participantIds: ['alice'], participantNames: {'alice': 'Alice'});
      final members = [member(uid: 'alice', name: 'Alice')];
      final result = buildEventParticipants(
        event: e,
        expenses: [
          expense(
            id: 'x1',
            payerId: 'alice',
            splitMode: SplitMode.shares,
            splitDistribution: {
              'alice': Decimal.one,
              'orphan': Decimal.one,
            },
          ),
        ],
        settlements: const [],
        resolveDisplay: eventScoped(e, members),
      );
      expect(
        result.participants.map((p) => p.id).toSet(),
        {'alice', 'orphan'},
      );
    });

    test('UID only as settlement payer is included', () {
      final e = event(participantIds: ['alice'], participantNames: {'alice': 'Alice'});
      final members = [member(uid: 'alice', name: 'Alice')];
      final result = buildEventParticipants(
        event: e,
        expenses: const [],
        settlements: [
          settlement(id: 's1', payerId: 'orphan', recipientId: 'alice'),
        ],
        resolveDisplay: eventScoped(e, members),
      );
      expect(
        result.participants.map((p) => p.id).toSet(),
        {'alice', 'orphan'},
      );
    });

    test('UID only as settlement recipient is included', () {
      final e = event(participantIds: ['alice'], participantNames: {'alice': 'Alice'});
      final members = [member(uid: 'alice', name: 'Alice')];
      final result = buildEventParticipants(
        event: e,
        expenses: const [],
        settlements: [
          settlement(id: 's1', payerId: 'alice', recipientId: 'orphan'),
        ],
        resolveDisplay: eventScoped(e, members),
      );
      expect(
        result.participants.map((p) => p.id).toSet(),
        {'alice', 'orphan'},
      );
    });
  });

  group('buildEventParticipants — liveness is display-only', () {
    test('live member missing from event.participantIds but in financial data is included', () {
      // Gate round-1 [P1] #2 regression: difference(liveUids) was wrong filter.
      final e = event(participantIds: ['alice'], participantNames: {'alice': 'Alice'});
      final members = [
        member(uid: 'alice', name: 'Alice'),
        member(uid: 'charlie', name: 'Charlie'),
      ];
      final result = buildEventParticipants(
        event: e,
        expenses: [expense(id: 'x1', payerId: 'charlie')],
        settlements: const [],
        resolveDisplay: eventScoped(e, members),
      );
      expect(result.participants.map((p) => p.id).toSet(), {'alice', 'charlie'});
      expect(
        result.displays['charlie']!.isFormer,
        isFalse,
        reason: 'charlie has a live (non-tombstone) member doc',
      );
    });

    test('tombstoned member appears in union and is flagged as former', () {
      final e = event(participantIds: ['alice'], participantNames: {'alice': 'Alice'});
      final members = [
        member(uid: 'alice', name: 'Alice'),
        member(uid: 'bob', name: 'Bob', isTombstone: true),
      ];
      final result = buildEventParticipants(
        event: e,
        expenses: const [],
        settlements: [settlement(id: 's1', payerId: 'bob', recipientId: 'alice')],
        resolveDisplay: eventScoped(e, members),
      );
      expect(result.displays['bob']!.isFormer, isTrue);
      expect(result.displays['bob']!.rawName, 'Bob');
    });
  });

  group('buildEventParticipants — fallback names', () {
    test(
      'pure orphan with settlement.payerName fallback resolves to that name, not "Former member"',
      () {
        // Gate round-1 [P1] #3 regression. Without the fallback plumb-through,
        // the helper would emit "Former member (former member)" which then
        // gets persisted into new settlement docs via userRawNames → addSettlement.
        final e = event(participantIds: ['alice'], participantNames: {'alice': 'Alice'});
        final members = [member(uid: 'alice', name: 'Alice')];
        final result = buildEventParticipants(
          event: e,
          expenses: const [],
          settlements: [
            settlement(
              id: 's1',
              payerId: 'ghost',
              payerName: 'Ghost',
              recipientId: 'alice',
            ),
          ],
          resolveDisplay: eventScoped(e, members),
        );
        expect(result.displays['ghost']!.rawName, 'Ghost');
        expect(result.displays['ghost']!.isFormer, isTrue);
        expect(
          result.participants.singleWhere((p) => p.id == 'ghost').displayName,
          'Ghost (former member)',
        );
      },
    );

    test(
      'fallback name harvested from expense.payerName when no live member doc',
      () {
        final e = event(participantIds: ['alice'], participantNames: {'alice': 'Alice'});
        final members = [member(uid: 'alice', name: 'Alice')];
        final result = buildEventParticipants(
          event: e,
          expenses: [
            expense(id: 'x1', payerId: 'ghost', payerName: 'Ghost'),
          ],
          settlements: const [],
          resolveDisplay: eventScoped(e, members),
        );
        expect(result.displays['ghost']!.rawName, 'Ghost');
      },
    );

    test(
      'first fallback name wins when multiple records mention the same UID',
      () {
        // putIfAbsent semantics — stable across reorderings as long as input
        // iteration order is stable (Firestore streams are ordered).
        final e = event(participantIds: const [], participantNames: const {});
        const members = <GroupMember>[];
        final result = buildEventParticipants(
          event: e,
          expenses: [
            expense(id: 'x1', payerId: 'ghost', payerName: 'EarlyName'),
            expense(id: 'x2', payerId: 'ghost', payerName: 'LaterName'),
          ],
          settlements: const [],
          resolveDisplay: eventScoped(e, members),
        );
        expect(result.displays['ghost']!.rawName, 'EarlyName');
      },
    );
  });

  group('buildEventParticipants — soft-deleted filter', () {
    test('soft-deleted expense payer is NOT pulled into union', () {
      final e = event(participantIds: ['alice'], participantNames: {'alice': 'Alice'});
      final members = [member(uid: 'alice', name: 'Alice')];
      final result = buildEventParticipants(
        event: e,
        expenses: [
          expense(id: 'x1', payerId: 'ghost', isDeleted: true),
        ],
        settlements: const [],
        resolveDisplay: eventScoped(e, members),
      );
      expect(result.participants.map((p) => p.id).toSet(), {'alice'});
    });

    test('soft-deleted settlement payer/recipient is NOT pulled into union', () {
      final e = event(participantIds: ['alice'], participantNames: {'alice': 'Alice'});
      final members = [member(uid: 'alice', name: 'Alice')];
      final result = buildEventParticipants(
        event: e,
        expenses: const [],
        settlements: [
          settlement(
            id: 's1',
            payerId: 'ghost',
            recipientId: 'phantom',
            isDeleted: true,
          ),
        ],
        resolveDisplay: eventScoped(e, members),
      );
      expect(result.participants.map((p) => p.id).toSet(), {'alice'});
    });
  });

  group('buildEventParticipants — output contract', () {
    test('displays map is 1:1 with participants list', () {
      final e = event(participantIds: ['alice', 'bob']);
      final members = [
        member(uid: 'alice', name: 'Alice'),
        member(uid: 'bob', name: 'Bob'),
      ];
      final result = buildEventParticipants(
        event: e,
        expenses: [expense(id: 'x1', payerId: 'ghost', payerName: 'Ghost')],
        settlements: [
          settlement(
            id: 's1',
            payerId: 'phantom',
            payerName: 'Phantom',
            recipientId: 'alice',
          ),
        ],
        resolveDisplay: eventScoped(e, members),
      );
      final participantIds = result.participants.map((p) => p.id).toSet();
      expect(result.displays.keys.toSet(), participantIds);
      // Participant.displayName must equal format(displays[uid]).
      for (final p in result.participants) {
        expect(
          p.displayName,
          MemberNameResolver.format(result.displays[p.id]!),
        );
      }
    });

    test('financial-only UIDs are appended in sorted order after event roster', () {
      // Round-3 [P2]: deterministic ordering.
      final e = event(
        participantIds: ['zelda', 'alice'],
        participantNames: {'zelda': 'Zelda', 'alice': 'Alice'},
      );
      final members = [
        member(uid: 'zelda', name: 'Zelda'),
        member(uid: 'alice', name: 'Alice'),
      ];
      final result = buildEventParticipants(
        event: e,
        expenses: const [],
        settlements: [
          settlement(id: 's1', payerId: 'charlie', recipientId: 'zelda'),
          settlement(id: 's2', payerId: 'bob', recipientId: 'alice'),
        ],
        resolveDisplay: eventScoped(e, members),
      );
      // Event roster preserved in declared order; financial-only sorted alpha.
      expect(
        result.participants.map((p) => p.id).toList(),
        ['zelda', 'alice', 'bob', 'charlie'],
      );
    });

    test('empty inputs return empty participant list', () {
      final e = event(participantIds: const [], participantNames: const {});
      final result = buildEventParticipants(
        event: e,
        expenses: const [],
        settlements: const [],
        resolveDisplay: eventScoped(e, const []),
      );
      expect(result.participants, isEmpty);
      expect(result.displays, isEmpty);
    });
  });
}
