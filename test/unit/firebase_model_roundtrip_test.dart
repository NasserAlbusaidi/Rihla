import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/services/money_serializer.dart';
import 'package:safar/features/activity/models/activity_log_model.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/gear/models/gear_item_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Expense round-trip tests
  // ---------------------------------------------------------------------------

  group('Expense round-trip', () {
    test('all fields survive toFirestore -> fromFirestore', () {
      final original = Expense(
        id: 'e1',
        tripId: 'event-1',
        payerParticipantId: 'p1',
        amount: Decimal.parse('10.500'),
        scope: ExpenseScope.global,
        createdAt: DateTime(2026, 3, 27),
        description: 'Dinner',
        subGroupId: 'sg1',
        customSplitParticipants: ['p1', 'p2'],
        receiptUrl: 'https://storage.example.com/receipt.jpg',
        categoryId: 'cat-food',
        note: 'Team dinner',
        isDeleted: false,
      );

      final map = original.toFirestore();
      final restored = Expense.fromFirestore(map);

      expect(restored.id, equals(original.id));
      expect(restored.tripId, equals(original.tripId));
      expect(restored.payerParticipantId, equals(original.payerParticipantId));
      expect(restored.amount, equals(original.amount));
      expect(restored.scope, equals(original.scope));
      expect(restored.createdAt, equals(original.createdAt));
      expect(restored.description, equals(original.description));
      expect(restored.subGroupId, equals(original.subGroupId));
      expect(restored.customSplitParticipants, equals(original.customSplitParticipants));
      expect(restored.receiptUrl, equals(original.receiptUrl));
      expect(restored.categoryId, equals(original.categoryId));
      expect(restored.note, equals(original.note));
      expect(restored.isDeleted, equals(original.isDeleted));
      expect(restored.deletedAt, isNull);
    });

    test('nullable fields survive round-trip as null', () {
      final original = Expense(
        id: 'e2',
        tripId: 'event-1',
        payerParticipantId: 'p1',
        amount: Decimal.parse('5.000'),
        scope: ExpenseScope.personal,
        createdAt: DateTime(2026, 1, 1),
      );

      final map = original.toFirestore();
      final restored = Expense.fromFirestore(map);

      expect(restored.description, isNull);
      expect(restored.subGroupId, isNull);
      expect(restored.receiptUrl, isNull);
      expect(restored.categoryId, isNull);
      expect(restored.note, isNull);
      expect(restored.deletedAt, isNull);
    });

    test('isDeleted and deletedAt survive round-trip', () {
      final deletedAt = DateTime(2026, 3, 1, 12, 0, 0);
      final original = Expense(
        id: 'e3',
        tripId: 'event-1',
        payerParticipantId: 'p1',
        amount: Decimal.parse('20.000'),
        scope: ExpenseScope.global,
        createdAt: DateTime(2026, 1, 15),
        isDeleted: true,
        deletedAt: deletedAt,
      );

      final map = original.toFirestore();
      final restored = Expense.fromFirestore(map);

      expect(restored.isDeleted, isTrue);
      expect(restored.deletedAt, equals(deletedAt));
    });

    test('subGroup scope with subGroupId survives round-trip', () {
      final original = Expense(
        id: 'e4',
        tripId: 'event-1',
        payerParticipantId: 'p1',
        amount: Decimal.parse('8.500'),
        scope: ExpenseScope.subGroup,
        subGroupId: 'sg-car-1',
        createdAt: DateTime(2026, 2, 10),
      );

      final map = original.toFirestore();
      final restored = Expense.fromFirestore(map);

      expect(restored.scope, equals(ExpenseScope.subGroup));
      expect(restored.subGroupId, equals('sg-car-1'));
    });

    test('custom scope with customSplitParticipants survives round-trip', () {
      final participants = ['uid-1', 'uid-2', 'uid-3'];
      final original = Expense(
        id: 'e5',
        tripId: 'event-1',
        payerParticipantId: 'uid-1',
        amount: Decimal.parse('30.000'),
        scope: ExpenseScope.custom,
        customSplitParticipants: participants,
        createdAt: DateTime(2026, 2, 15),
      );

      final map = original.toFirestore();
      final restored = Expense.fromFirestore(map);

      expect(restored.scope, equals(ExpenseScope.custom));
      expect(restored.customSplitParticipants, equals(participants));
    });

    test('fromFirestore defaults scope to global when field missing', () {
      final map = {
        'id': 'e6',
        'eventId': 'event-1',
        'payerParticipantId': 'p1',
        'amountFils': 10500,
        'currency': 'OMR',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        // scope is missing
      };

      final expense = Expense.fromFirestore(map);
      expect(expense.scope, equals(ExpenseScope.global));
    });

    test('fromFirestore defaults amount to zero when amountFils missing', () {
      final map = {
        'id': 'e7',
        'eventId': 'event-1',
        'payerParticipantId': 'p1',
        'currency': 'OMR',
        'scope': 'global',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        // amountFils missing
      };

      final expense = Expense.fromFirestore(map);
      expect(expense.amount, equals(Decimal.zero));
    });
  });

  // ---------------------------------------------------------------------------
  // Settlement round-trip tests
  // ---------------------------------------------------------------------------

  group('Settlement round-trip', () {
    test('all fields survive toFirestore -> fromFirestore', () {
      final settledAt = DateTime(2026, 3, 15, 10, 30);
      final original = Settlement(
        id: 's1',
        tripId: 'event-1',
        payerParticipantId: 'uid-1',
        recipientParticipantId: 'uid-2',
        amount: Decimal.parse('15.500'),
        note: 'Settling dinner',
        settledAt: settledAt,
        scope: 'event',
        groupId: null,
      );

      final map = original.toFirestore();
      final restored = Settlement.fromFirestore(map);

      expect(restored.id, equals(original.id));
      expect(restored.tripId, equals(original.tripId));
      expect(restored.payerParticipantId, equals(original.payerParticipantId));
      expect(restored.recipientParticipantId, equals(original.recipientParticipantId));
      expect(restored.amount, equals(original.amount));
      expect(restored.note, equals(original.note));
      expect(restored.settledAt, equals(original.settledAt));
      expect(restored.scope, equals(original.scope));
      expect(restored.groupId, isNull);
    });

    test('Settlement scope defaults to event when field missing', () {
      final map = {
        'id': 's2',
        'eventId': 'event-1',
        'payerParticipantId': 'uid-1',
        'recipientParticipantId': 'uid-2',
        'amountFils': 5000,
        'currency': 'OMR',
        'settledAt': DateTime(2026, 1, 1).toIso8601String(),
        // scope is missing — must default to 'event'
      };

      final settlement = Settlement.fromFirestore(map);
      expect(settlement.scope, equals('event'));
    });

    test('group-scope settlement with groupId survives round-trip', () {
      final original = Settlement(
        id: 's3',
        tripId: 'group-1',
        payerParticipantId: 'uid-1',
        recipientParticipantId: 'uid-2',
        amount: Decimal.parse('25.000'),
        settledAt: DateTime(2026, 2, 1),
        scope: 'group',
        groupId: 'group-1',
      );

      final map = original.toFirestore();
      final restored = Settlement.fromFirestore(map);

      expect(restored.scope, equals('group'));
      expect(restored.groupId, equals('group-1'));
      // For group settlements, tripId falls back to groupId
      expect(restored.tripId, equals('group-1'));
    });

    test('nullable fields (note, payerName, recipientName) survive null round-trip', () {
      final original = Settlement(
        id: 's4',
        tripId: 'event-1',
        amount: Decimal.parse('10.000'),
        settledAt: DateTime(2026, 1, 1),
      );

      final map = original.toFirestore();
      final restored = Settlement.fromFirestore(map);

      expect(restored.note, isNull);
      expect(restored.payerParticipantId, isNull);
      expect(restored.recipientParticipantId, isNull);
    });

    test('isDeleted and deletedAt survive round-trip', () {
      final deletedAt = DateTime(2026, 3, 10);
      final original = Settlement(
        id: 's5',
        tripId: 'event-1',
        payerParticipantId: 'uid-1',
        recipientParticipantId: 'uid-2',
        amount: Decimal.parse('5.000'),
        settledAt: DateTime(2026, 1, 1),
        isDeleted: true,
        deletedAt: deletedAt,
      );

      final map = original.toFirestore();
      final restored = Settlement.fromFirestore(map);

      expect(restored.isDeleted, isTrue);
      expect(restored.deletedAt, equals(deletedAt));
    });
  });

  // ---------------------------------------------------------------------------
  // GearItem round-trip tests
  // ---------------------------------------------------------------------------

  group('GearItem round-trip', () {
    test('all fields survive toFirestore -> fromFirestore', () {
      final createdAt = DateTime(2026, 3, 20, 9, 0);
      final original = GearItem(
        id: 'g1',
        tripId: 'event-1',
        itemName: 'Tent',
        assignedTo: 'uid-1',
        isPacked: true,
        sequenceId: 3,
        isHighPriority: true,
        isDeleted: false,
        createdAt: createdAt,
      );

      final map = original.toFirestore();
      final restored = GearItem.fromFirestore(map);

      expect(restored.id, equals(original.id));
      expect(restored.tripId, equals(original.tripId));
      expect(restored.itemName, equals(original.itemName));
      expect(restored.assignedTo, equals(original.assignedTo));
      expect(restored.isPacked, equals(original.isPacked));
      expect(restored.sequenceId, equals(original.sequenceId));
      expect(restored.isHighPriority, equals(original.isHighPriority));
      expect(restored.isDeleted, equals(original.isDeleted));
      expect(restored.createdAt, equals(original.createdAt));
    });

    test('nullable fields default correctly when missing', () {
      final map = {
        'id': 'g2',
        'eventId': 'event-1',
        'itemName': 'Sleeping bag',
        // assignedTo, isPacked, sequenceId, isHighPriority all missing
      };

      final item = GearItem.fromFirestore(map);

      expect(item.assignedTo, isNull);
      expect(item.isPacked, isFalse);
      expect(item.sequenceId, equals(0));
      expect(item.isHighPriority, isFalse);
      expect(item.isDeleted, isFalse);
      expect(item.createdAt, isNull);
    });

    test('isDeleted and deletedAt survive round-trip', () {
      final deletedAt = DateTime(2026, 2, 28);
      final original = GearItem(
        id: 'g3',
        tripId: 'event-1',
        itemName: 'Stove',
        isDeleted: true,
        deletedAt: deletedAt,
      );

      final map = original.toFirestore();
      final restored = GearItem.fromFirestore(map);

      expect(restored.isDeleted, isTrue);
      expect(restored.deletedAt, equals(deletedAt));
    });
  });

  // ---------------------------------------------------------------------------
  // ActivityLog round-trip tests
  // ---------------------------------------------------------------------------

  group('ActivityLog round-trip', () {
    test('all fields survive toFirestore -> fromFirestore', () {
      final createdAt = DateTime(2026, 3, 25, 14, 30);
      final original = ActivityLog(
        id: 'al1',
        tripId: 'event-1',
        actorId: 'uid-1',
        targetParticipantId: 'uid-2',
        category: 'MONEY',
        eventType: 'CREATE',
        logText: 'Alice paid 10.500 OMR',
        metadata: {'expenseId': 'e1', 'amount': 10500},
        createdAt: createdAt,
      );

      final map = original.toFirestore();
      final restored = ActivityLog.fromFirestore(map);

      expect(restored.id, equals(original.id));
      expect(restored.tripId, equals(original.tripId));
      expect(restored.actorId, equals(original.actorId));
      expect(restored.targetParticipantId, equals(original.targetParticipantId));
      expect(restored.category, equals(original.category));
      expect(restored.eventType, equals(original.eventType));
      expect(restored.logText, equals(original.logText));
      expect(restored.metadata, equals(original.metadata));
      expect(restored.createdAt, equals(original.createdAt));
    });

    test('nullable fields default correctly when missing', () {
      final map = {
        'id': 'al2',
        'eventId': 'event-1',
        'category': 'GEAR',
        'eventType': 'UPDATE',
        'logText': 'Tent marked as packed',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        // actorId, targetParticipantId, metadata missing
      };

      final log = ActivityLog.fromFirestore(map);

      expect(log.actorId, isNull);
      expect(log.targetParticipantId, isNull);
      expect(log.metadata, equals(const <String, dynamic>{}));
    });

    test('empty metadata map survives round-trip', () {
      final original = ActivityLog(
        id: 'al3',
        tripId: 'event-1',
        category: 'DOCS',
        eventType: 'DELETE',
        logText: 'Document deleted',
        metadata: const {},
        createdAt: DateTime(2026, 3, 1),
      );

      final map = original.toFirestore();
      final restored = ActivityLog.fromFirestore(map);

      expect(restored.metadata, equals(const <String, dynamic>{}));
    });
  });

  // ---------------------------------------------------------------------------
  // Group round-trip tests (via SQLite map path)
  // ---------------------------------------------------------------------------

  group('Group round-trip (SQLite map path)', () {
    test('all fields survive toMap -> fromMap', () {
      final createdAt = DateTime(2026, 3, 1, 8, 0);
      final updatedAt = DateTime(2026, 3, 27, 10, 0);
      final original = Group(
        id: 'grp-1',
        name: 'Adventure Crew',
        inviteCode: 'ABC123',
        createdBy: 'uid-1',
        memberIds: ['uid-1', 'uid-2', 'uid-3'],
        currency: 'OMR',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final map = original.toMap();
      final restored = Group.fromMap(map);

      expect(restored.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.inviteCode, equals(original.inviteCode));
      expect(restored.createdBy, equals(original.createdBy));
      expect(restored.memberIds, equals(original.memberIds));
      expect(restored.currency, equals(original.currency));
      expect(restored.createdAt, equals(original.createdAt));
      expect(restored.updatedAt, equals(original.updatedAt));
    });

    test('optional updatedAt defaults to null when missing', () {
      final map = {
        'id': 'grp-2',
        'name': 'Test Group',
        'invite_code': 'XYZ789',
        'created_by': 'uid-1',
        'member_ids': '["uid-1"]',
        'currency': 'OMR',
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
        'updated_at': null,
      };

      final group = Group.fromMap(map);

      expect(group.updatedAt, isNull);
    });

    test('memberIds list round-trips through JSON encoding', () {
      final memberIds = ['uid-a', 'uid-b', 'uid-c', 'uid-d'];
      final original = Group(
        id: 'grp-3',
        name: 'Big Group',
        inviteCode: 'BIGGRP',
        createdBy: 'uid-a',
        memberIds: memberIds,
        createdAt: DateTime(2026, 2, 1),
      );

      final map = original.toMap();
      final restored = Group.fromMap(map);

      expect(restored.memberIds, hasLength(memberIds.length));
      expect(restored.memberIds, equals(memberIds));
    });
  });

  // ---------------------------------------------------------------------------
  // Group round-trip tests (via Firestore DocumentSnapshot)
  // ---------------------------------------------------------------------------

  group('Group round-trip (Firestore fromDoc)', () {
    test('all fields survive Firestore write -> fromDoc', () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final createdAt = DateTime(2026, 3, 1).toUtc();
      final updatedAt = DateTime(2026, 3, 27).toUtc();

      await fakeFirestore.collection('groups').doc('grp-fs-1').set({
        'id': 'grp-fs-1',
        'name': 'Firestore Group',
        'inviteCode': 'FS1234',
        'createdBy': 'uid-1',
        'memberIds': ['uid-1', 'uid-2'],
        'currency': 'OMR',
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      });

      final doc = await fakeFirestore.collection('groups').doc('grp-fs-1').get();
      final group = Group.fromDoc(doc);

      expect(group.id, equals('grp-fs-1'));
      expect(group.name, equals('Firestore Group'));
      expect(group.inviteCode, equals('FS1234'));
      expect(group.createdBy, equals('uid-1'));
      expect(group.memberIds, equals(['uid-1', 'uid-2']));
      expect(group.currency, equals('OMR'));
    });

    test('currency defaults to OMR when missing from Firestore', () async {
      final fakeFirestore = FakeFirebaseFirestore();

      await fakeFirestore.collection('groups').doc('grp-fs-2').set({
        'id': 'grp-fs-2',
        'name': 'No Currency Group',
        'inviteCode': 'NOCURR',
        'createdBy': 'uid-1',
        'memberIds': ['uid-1'],
        'createdAt': DateTime(2026, 1, 1).toUtc(),
        // currency field absent
      });

      final doc = await fakeFirestore.collection('groups').doc('grp-fs-2').get();
      final group = Group.fromDoc(doc);

      expect(group.currency, equals('OMR'));
    });
  });

  // ---------------------------------------------------------------------------
  // Event round-trip tests (via Firestore DocumentSnapshot)
  // ---------------------------------------------------------------------------

  group('Event round-trip', () {
    test('all fields survive toFirestoreMap -> fromDoc', () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final startDate = DateTime(2026, 4, 1).toUtc();
      final endDate = DateTime(2026, 4, 5).toUtc();
      final createdAt = DateTime(2026, 3, 20).toUtc();

      final original = Event(
        id: 'evt-1',
        name: 'Summer Camp',
        type: EventType.camping,
        groupId: 'grp-1',
        createdBy: 'uid-1',
        participantIds: ['uid-1', 'uid-2'],
        participantNames: {'uid-1': 'Alice', 'uid-2': 'Bob'},
        modules: const EventModules(ledger: true, gear: true, logistics: true),
        startDate: startDate,
        endDate: endDate,
        currency: 'OMR',
        createdAt: createdAt,
      );

      // Write to fake Firestore (excluding FieldValue.serverTimestamp)
      final mapWithoutServerTimestamp = {
        'name': original.name,
        'type': original.type.value,
        'groupId': original.groupId,
        'createdBy': original.createdBy,
        'participantIds': original.participantIds,
        'participantNames': original.participantNames,
        'modules': original.modules.toMap(),
        'startDate': startDate,
        'endDate': endDate,
        'currency': original.currency,
        'isDeleted': original.isDeleted,
        'deletedAt': null,
        'createdAt': original.createdAt.toIso8601String(),
        'updatedAt': null,
      };

      await fakeFirestore
          .collection('groups')
          .doc('grp-1')
          .collection('events')
          .doc('evt-1')
          .set(mapWithoutServerTimestamp);

      final doc = await fakeFirestore
          .collection('groups')
          .doc('grp-1')
          .collection('events')
          .doc('evt-1')
          .get();

      final restored = Event.fromDoc(doc);

      expect(restored.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.type, equals(original.type));
      expect(restored.groupId, equals(original.groupId));
      expect(restored.createdBy, equals(original.createdBy));
      expect(restored.participantIds, equals(original.participantIds));
      expect(restored.participantNames, equals(original.participantNames));
      expect(restored.modules.ledger, isTrue);
      expect(restored.modules.gear, isTrue);
      expect(restored.modules.logistics, isTrue);
      expect(restored.currency, equals('OMR'));
      expect(restored.isDeleted, isFalse);
    });

    test('EventType.nightDayOut serializes as night_day_out', () {
      expect(EventType.nightDayOut.value, equals('night_day_out'));
    });

    test('EventType.fromString falls back to custom for unknown value', () {
      final type = EventType.fromString('unknown_type');
      expect(type, equals(EventType.custom));
    });

    test('EventModules.fromMap defaults all to false except ledger', () {
      final modules = EventModules.fromMap(const {});
      expect(modules.ledger, isTrue);
      expect(modules.gear, isFalse);
      expect(modules.logistics, isFalse);
      expect(modules.vault, isFalse);
      expect(modules.memories, isFalse);
    });

    test('EventModules.forType(trip) enables all modules', () {
      final modules = EventModules.forType(EventType.trip);
      expect(modules.ledger, isTrue);
      expect(modules.gear, isTrue);
      expect(modules.logistics, isTrue);
      expect(modules.vault, isTrue);
      expect(modules.memories, isTrue);
    });

    test('nullable fields in Event default correctly', () async {
      final fakeFirestore = FakeFirebaseFirestore();

      await fakeFirestore
          .collection('groups')
          .doc('grp-1')
          .collection('events')
          .doc('evt-minimal')
          .set({
        'name': 'Minimal Event',
        'type': 'trip',
        'groupId': 'grp-1',
        'createdBy': 'uid-1',
        'participantIds': <String>[],
        'participantNames': <String, String>{},
        'modules': <String, dynamic>{},
        'currency': 'OMR',
        'isDeleted': false,
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        // startDate, endDate, deletedAt, updatedAt all absent
      });

      final doc = await fakeFirestore
          .collection('groups')
          .doc('grp-1')
          .collection('events')
          .doc('evt-minimal')
          .get();

      final event = Event.fromDoc(doc);

      expect(event.startDate, isNull);
      expect(event.endDate, isNull);
      expect(event.deletedAt, isNull);
      expect(event.updatedAt, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // MoneySerializer boundary tests
  // ---------------------------------------------------------------------------

  group('MoneySerializer boundary values', () {
    test('0 fils -> Decimal.zero', () {
      final result = MoneySerializer.fromSubunits(0, 'OMR');
      expect(result, equals(Decimal.zero));
    });

    test('1 fil -> Decimal.parse("0.001")', () {
      final result = MoneySerializer.fromSubunits(1, 'OMR');
      expect(result, equals(Decimal.parse('0.001')));
    });

    test('999999999 fils -> large Decimal', () {
      final result = MoneySerializer.fromSubunits(999999999, 'OMR');
      expect(result, equals(Decimal.parse('999999.999')));
    });

    test('toSubunits: Decimal.zero -> 0', () {
      final result = MoneySerializer.toSubunits(Decimal.zero, 'OMR');
      expect(result, equals(0));
    });

    test('toSubunits: large OMR amount -> correct fils', () {
      final amount = Decimal.parse('1000.500');
      expect(MoneySerializer.toSubunits(amount, 'OMR'), equals(1000500));
    });

    test('round-trip 0 fils stays zero', () {
      final restored = MoneySerializer.fromSubunits(
        MoneySerializer.toSubunits(Decimal.zero, 'OMR'),
        'OMR',
      );
      expect(restored, equals(Decimal.zero));
    });

    test('round-trip 1 fil stays 0.001', () {
      final amount = Decimal.parse('0.001');
      final subunits = MoneySerializer.toSubunits(amount, 'OMR');
      expect(subunits, equals(1));
      final restored = MoneySerializer.fromSubunits(subunits, 'OMR');
      expect(restored, equals(amount));
    });
  });
}
