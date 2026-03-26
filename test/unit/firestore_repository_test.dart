import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/services/firestore_repository.dart';
import 'package:safar/features/activity/models/activity_log_model.dart';
import 'package:safar/features/gear/models/gear_item_model.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/logistics/models/sub_group_model.dart';

// ---------------------------------------------------------------------------
// Concrete test subclass of FirestoreRepository
// ---------------------------------------------------------------------------

class _TestRepository extends FirestoreRepository {
  _TestRepository.withFirestore(FirebaseFirestore db)
      : super.withFirestore(db);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('FirestoreRepository', () {
    late FakeFirebaseFirestore fakeDb;
    late _TestRepository repo;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      repo = _TestRepository.withFirestore(fakeDb);
    });

    // Test 1: eventSubcollection returns correct path
    test('eventSubcollection returns path groups/{groupId}/events/{eventId}/{module}',
        () {
      final ref = repo.eventSubcollection('g1', 'e1', 'expenses');
      expect(ref.path, equals('groups/g1/events/e1/expenses'));
    });

    // Test 2: db getter returns the injected FakeFirebaseFirestore
    test('db getter returns the injected FakeFirebaseFirestore', () {
      expect(repo.db, same(fakeDb));
    });
  });

  // ---------------------------------------------------------------------------
  // Expense serialization
  // ---------------------------------------------------------------------------

  group('Expense Firestore serialization', () {
    // Test 3: fromFirestore deserializes amountFils correctly
    test('fromFirestore correctly deserializes amountFils via MoneySerializer', () {
      final data = {
        'id': 'exp-1',
        'eventId': 'event-1',
        'payerParticipantId': 'uid-1',
        'amountFils': 10500,
        'currency': 'OMR',
        'description': 'Lunch',
        'scope': 'global',
        'subGroupId': null,
        'customSplitParticipants': [],
        'receiptUrl': null,
        'createdAt': '2024-01-15T10:00:00.000Z',
        'categoryId': null,
        'note': null,
        'isDeleted': false,
        'deletedAt': null,
      };

      final expense = Expense.fromFirestore(data);

      expect(expense.amount, equals(Decimal.parse('10.500')));
      expect(expense.id, equals('exp-1'));
      expect(expense.tripId, equals('event-1'));
      expect(expense.payerParticipantId, equals('uid-1'));
    });

    // Test 4: toFirestore serializes amount to amountFils correctly
    test('toFirestore correctly serializes amount to amountFils via MoneySerializer', () {
      final expense = Expense(
        id: 'exp-1',
        tripId: 'event-1',
        payerParticipantId: 'uid-1',
        amount: Decimal.parse('10.500'),
        scope: ExpenseScope.global,
        createdAt: DateTime.utc(2024, 1, 15, 10, 0, 0),
      );

      final data = expense.toFirestore();

      expect(data['amountFils'], equals(10500));
      expect(data['currency'], equals('OMR'));
      expect(data['payerParticipantId'], equals('uid-1'));
      expect(data['eventId'], equals('event-1'));
      // Supabase join artifacts must NOT be present
      expect(data.containsKey('payerName'), isFalse);
      expect(data.containsKey('categoryName'), isFalse);
      expect(data.containsKey('categoryIcon'), isFalse);
    });

    test('fromFirestore and toFirestore round-trip produces equivalent object', () {
      final original = Expense(
        id: 'exp-2',
        tripId: 'event-2',
        payerParticipantId: 'uid-2',
        amount: Decimal.parse('5.750'),
        scope: ExpenseScope.subGroup,
        subGroupId: 'sg-1',
        description: 'Hotel',
        customSplitParticipants: ['uid-2', 'uid-3'],
        createdAt: DateTime.utc(2024, 3, 10, 8, 30, 0),
        isDeleted: false,
      );

      final data = original.toFirestore();
      final restored = Expense.fromFirestore(data);

      expect(restored.id, equals(original.id));
      expect(restored.tripId, equals(original.tripId));
      expect(restored.amount, equals(original.amount));
      expect(restored.scope, equals(original.scope));
      expect(restored.subGroupId, equals(original.subGroupId));
      expect(restored.description, equals(original.description));
      expect(restored.customSplitParticipants,
          equals(original.customSplitParticipants));
    });
  });

  // ---------------------------------------------------------------------------
  // Settlement serialization
  // ---------------------------------------------------------------------------

  group('Settlement Firestore serialization', () {
    // Test 5: fromFirestore correctly deserializes amountFils
    test('fromFirestore correctly deserializes amountFils to Decimal', () {
      final data = {
        'id': 'sett-1',
        'eventId': 'event-1',
        'payerParticipantId': 'uid-1',
        'recipientParticipantId': 'uid-2',
        'amountFils': 5500,
        'currency': 'OMR',
        'note': 'Owed from trip',
        'settledAt': '2024-02-20T12:00:00.000Z',
        'isDeleted': false,
        'deletedAt': null,
      };

      final settlement = Settlement.fromFirestore(data);

      expect(settlement.amount, equals(Decimal.parse('5.500')));
      expect(settlement.id, equals('sett-1'));
      expect(settlement.tripId, equals('event-1'));
    });

    test('toFirestore round-trip produces equivalent Settlement', () {
      final original = Settlement(
        id: 'sett-2',
        tripId: 'event-3',
        payerParticipantId: 'uid-5',
        recipientParticipantId: 'uid-6',
        amount: Decimal.parse('3.250'),
        settledAt: DateTime.utc(2024, 5, 1, 9, 0, 0),
      );

      final data = original.toFirestore();
      final restored = Settlement.fromFirestore(data);

      expect(restored.id, equals(original.id));
      expect(restored.tripId, equals(original.tripId));
      expect(restored.amount, equals(original.amount));
      expect(restored.payerParticipantId, equals(original.payerParticipantId));
      expect(restored.recipientParticipantId,
          equals(original.recipientParticipantId));
    });
  });

  // ---------------------------------------------------------------------------
  // GearItem serialization
  // ---------------------------------------------------------------------------

  group('GearItem Firestore serialization', () {
    // Test 6: fromFirestore deserializes all fields including isHighPriority
    test('fromFirestore correctly deserializes all fields including isHighPriority', () {
      final data = {
        'id': 'gear-1',
        'eventId': 'event-1',
        'itemName': 'Tent',
        'assignedTo': 'uid-1',
        'isPacked': true,
        'sequenceId': 3,
        'isHighPriority': true,
        'isDeleted': false,
        'deletedAt': null,
        'createdAt': '2024-01-10T08:00:00.000Z',
      };

      final item = GearItem.fromFirestore(data);

      expect(item.id, equals('gear-1'));
      expect(item.tripId, equals('event-1'));
      expect(item.itemName, equals('Tent'));
      expect(item.isPacked, isTrue);
      expect(item.isHighPriority, isTrue);
      expect(item.sequenceId, equals(3));
    });

    test('toFirestore round-trip produces equivalent GearItem', () {
      final original = GearItem(
        id: 'gear-2',
        tripId: 'event-2',
        itemName: 'Sleeping Bag',
        assignedTo: 'uid-3',
        isPacked: false,
        sequenceId: 1,
        isHighPriority: true,
        createdAt: DateTime.utc(2024, 2, 5, 7, 0, 0),
      );

      final data = original.toFirestore();
      final restored = GearItem.fromFirestore(data);

      expect(restored.id, equals(original.id));
      expect(restored.tripId, equals(original.tripId));
      expect(restored.itemName, equals(original.itemName));
      expect(restored.isHighPriority, equals(original.isHighPriority));
      expect(restored.isPacked, equals(original.isPacked));
    });
  });

  // ---------------------------------------------------------------------------
  // SubGroup serialization
  // ---------------------------------------------------------------------------

  group('SubGroup Firestore serialization', () {
    // Test 7: fromFirestore deserializes type enum and members is not inlined
    test('fromFirestore correctly deserializes type enum and base fields', () {
      final data = {
        'id': 'sg-1',
        'eventId': 'event-1',
        'name': 'Car A',
        'type': 'CAR',
        'capacity': 5,
        'createdAt': '2024-01-12T09:00:00.000Z',
      };

      final subGroup = SubGroup.fromFirestore(data);

      expect(subGroup.id, equals('sg-1'));
      expect(subGroup.tripId, equals('event-1'));
      expect(subGroup.name, equals('Car A'));
      expect(subGroup.type, equals(SubGroupType.car));
      expect(subGroup.capacity, equals(5));
      // Members are a separate subcollection -- not inlined in fromFirestore
      expect(subGroup.members, isEmpty);
    });

    test('toFirestore round-trip produces equivalent SubGroup base fields', () {
      final original = SubGroup(
        id: 'sg-2',
        tripId: 'event-5',
        name: 'Room B',
        type: SubGroupType.room,
        capacity: 3,
        createdAt: DateTime.utc(2024, 6, 20, 11, 0, 0),
      );

      final data = original.toFirestore();
      final restored = SubGroup.fromFirestore(data);

      expect(restored.id, equals(original.id));
      expect(restored.tripId, equals(original.tripId));
      expect(restored.name, equals(original.name));
      expect(restored.type, equals(original.type));
      expect(restored.capacity, equals(original.capacity));
    });
  });

  // ---------------------------------------------------------------------------
  // ActivityLog serialization
  // ---------------------------------------------------------------------------

  group('ActivityLog Firestore serialization', () {
    // Test 8: fromFirestore deserializes category and metadata
    test('fromFirestore correctly deserializes category and metadata', () {
      final data = {
        'id': 'log-1',
        'eventId': 'event-1',
        'actorId': 'uid-1',
        'targetParticipantId': null,
        'category': 'MONEY',
        'eventType': 'CREATE',
        'logText': 'Nasser paid 10.500 OMR',
        'metadata': {'amount': '10.500', 'currency': 'OMR'},
        'createdAt': '2024-03-01T14:00:00.000Z',
      };

      final log = ActivityLog.fromFirestore(data);

      expect(log.id, equals('log-1'));
      expect(log.tripId, equals('event-1'));
      expect(log.category, equals('MONEY'));
      expect(log.eventType, equals('CREATE'));
      expect(log.metadata['amount'], equals('10.500'));
    });

    test('toFirestore round-trip produces equivalent ActivityLog', () {
      final original = ActivityLog(
        id: 'log-2',
        tripId: 'event-6',
        actorId: 'uid-7',
        category: 'GEAR',
        eventType: 'UPDATE',
        logText: 'Packed tent',
        metadata: {'itemId': 'gear-5'},
        createdAt: DateTime.utc(2024, 7, 1, 10, 0, 0),
      );

      final data = original.toFirestore();
      final restored = ActivityLog.fromFirestore(data);

      expect(restored.id, equals(original.id));
      expect(restored.tripId, equals(original.tripId));
      expect(restored.category, equals(original.category));
      expect(restored.eventType, equals(original.eventType));
      expect(restored.logText, equals(original.logText));
      expect(restored.metadata, equals(original.metadata));
    });
  });
}
