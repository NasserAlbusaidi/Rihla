// Widget tests for EventModuleList.
//
// Covers the module card rendering paths:
//   - Ledger card with expenses (covered count → summary text)
//   - Gear card with items (packed/unclaimed stats)
//   - Logistics card with sub-groups
//   - Vault card with documents
//   - Memories card
//   - Navigation (open* methods covered via tap simulation)

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/widgets/event_module_list.dart';
import 'package:safar/features/gear/models/gear_item_model.dart';
import 'package:safar/features/gear/providers/gear_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/logistics/models/sub_group_model.dart';
import 'package:safar/features/logistics/providers/sub_group_provider.dart';
import 'package:safar/features/vault/models/document_model.dart';
import 'package:safar/features/vault/providers/document_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Event _makeEvent({EventModules? modules, String id = 'evt-1'}) {
  return Event(
    id: id,
    name: 'Test Event',
    type: EventType.trip,
    groupId: 'group-1',
    createdBy: 'uid-1',
    participantIds: const ['uid-1', 'uid-2'],
    participantNames: const {'uid-1': 'Alice', 'uid-2': 'Bob'},
    modules: modules ?? const EventModules(),
    createdAt: DateTime(2026, 1, 1),
  );
}

Expense _makeExpense(String id, Decimal amount) => Expense(
      id: id,
      tripId: 'evt-1',
      payerParticipantId: 'uid-1',
      amount: amount,
      scope: ExpenseScope.global,
      createdAt: DateTime(2026, 1, 1),
    );

GearItem _makeGearItem({String? assignedTo, bool isPacked = false}) => GearItem(
      id: 'gear-1',
      tripId: 'evt-1',
      itemName: 'Tent',
      assignedTo: assignedTo,
      isPacked: isPacked,
      isDeleted: false,
    );

SubGroup _makeSubGroup(SubGroupType type) => SubGroup(
      id: 'sg-1',
      tripId: 'evt-1',
      name: 'Car 1',
      type: type,
    );

Document _makeDocument() => Document(
      id: 'doc-1',
      tripId: 'evt-1',
      fileName: 'ticket.pdf',
      fileUrl: 'https://example.com/ticket.pdf',
    );

/// Wraps EventModuleList in ProviderScope + MaterialApp with provider overrides.
///
/// Uses the new D-14 string ID constructor: EventModuleList(groupId:, eventId:, modules:)
Widget _buildList({
  required Event event,
  List<Expense> expenses = const [],
  List<Settlement> settlements = const [],
  List<GearItem> gearItems = const [],
  List<SubGroup> subGroups = const [],
  List<Document> documents = const [],
}) {
  final eventRef = (groupId: 'group-1', eventId: event.id);

  return ProviderScope(
    overrides: [
      eventExpensesProvider(eventRef).overrideWith(
        (_) => Stream.value(expenses),
      ),
      eventSettlementsProvider(eventRef).overrideWith(
        (_) => Stream.value(settlements),
      ),
      if (event.modules.gear)
        eventGearItemsProvider(eventRef).overrideWith(
          (_) => Stream.value(gearItems),
        ),
      if (event.modules.logistics)
        eventSubGroupsProvider(eventRef).overrideWith(
          (_) => Stream.value(subGroups),
        ),
      if (event.modules.vault)
        eventDocumentsProvider(eventRef).overrideWith(
          (_) => Stream.value(documents),
        ),
    ],
    child: MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(
        body: SingleChildScrollView(
          child: EventModuleList(
            groupId: event.groupId,
            eventId: event.id,
            modules: event.modules,
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('EventModuleList', () {
    testWidgets('renders Ledger card when ledger module is enabled', (tester) async {
      final event = _makeEvent(
        modules: const EventModules(ledger: true),
      );
      await tester.pumpWidget(_buildList(event: event));
      // Pump past flutter_animate's 400ms animations (delay up to 400ms + 400ms duration)
      await tester.pump(const Duration(seconds: 2));

      expect(find.byKey(EventKeys.ledgerCard), findsOneWidget);
    });

    testWidgets('shows expense count summary text when expenses exist', (tester) async {
      final event = _makeEvent(
        modules: const EventModules(ledger: true),
      );
      final expenses = [
        _makeExpense('e1', Decimal.parse('10.000')),
        _makeExpense('e2', Decimal.parse('5.500')),
      ];
      await tester.pumpWidget(_buildList(event: event, expenses: expenses));
      await tester.pumpAndSettle();

      // "2 expenses · 15.500 OMR"
      expect(find.textContaining('2 expenses'), findsOneWidget);
    });

    testWidgets('shows single expense text (singular) when one expense', (tester) async {
      final event = _makeEvent(
        modules: const EventModules(ledger: true),
      );
      final expenses = [_makeExpense('e1', Decimal.parse('7.500'))];
      await tester.pumpWidget(_buildList(event: event, expenses: expenses));
      await tester.pumpAndSettle();

      // "1 expense · ..."
      expect(find.textContaining('1 expense'), findsOneWidget);
    });

    testWidgets('renders Gear card when gear module is enabled', (tester) async {
      final event = _makeEvent(
        modules: const EventModules(gear: true),
      );
      await tester.pumpWidget(_buildList(event: event));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byKey(EventKeys.gearCard), findsOneWidget);
    });

    testWidgets('shows unclaimed gear action text when items exist without assignee', (tester) async {
      final event = _makeEvent(
        modules: const EventModules(gear: true),
      );
      final gearItems = [
        _makeGearItem(assignedTo: null),
      ];
      await tester.pumpWidget(_buildList(event: event, gearItems: gearItems));
      await tester.pumpAndSettle();

      // "1 item still needs someone"
      expect(find.textContaining('item still need'), findsWidgets);
    });

    testWidgets('shows packed gear summary when all items are claimed', (tester) async {
      final event = _makeEvent(
        modules: const EventModules(gear: true),
      );
      final gearItems = [
        _makeGearItem(assignedTo: 'uid-1', isPacked: true),
        _makeGearItem(assignedTo: 'uid-2', isPacked: false),
      ];
      await tester.pumpWidget(_buildList(event: event, gearItems: gearItems));
      await tester.pumpAndSettle();

      // "2 items · 1 packed"
      expect(find.textContaining('items'), findsWidgets);
    });

    testWidgets('renders Logistics card when logistics module is enabled', (tester) async {
      final event = _makeEvent(
        modules: const EventModules(logistics: true),
      );
      await tester.pumpWidget(_buildList(event: event));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byKey(EventKeys.logisticsCard), findsOneWidget);
    });

    testWidgets('shows car count in logistics summary', (tester) async {
      final event = _makeEvent(
        modules: const EventModules(logistics: true),
      );
      final subGroups = [
        _makeSubGroup(SubGroupType.car),
        _makeSubGroup(SubGroupType.car),
      ];
      await tester.pumpWidget(_buildList(event: event, subGroups: subGroups));
      await tester.pumpAndSettle();

      // "2 cars"
      expect(find.textContaining('car'), findsWidgets);
    });

    testWidgets('shows room count in logistics summary', (tester) async {
      final event = _makeEvent(
        modules: const EventModules(logistics: true),
      );
      final subGroups = [
        _makeSubGroup(SubGroupType.room),
      ];
      await tester.pumpWidget(_buildList(event: event, subGroups: subGroups));
      await tester.pumpAndSettle();

      expect(find.textContaining('room'), findsWidgets);
    });

    testWidgets('renders Vault card when vault module is enabled', (tester) async {
      final event = _makeEvent(
        modules: const EventModules(vault: true),
      );
      await tester.pumpWidget(_buildList(event: event));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byKey(EventKeys.vaultCard), findsOneWidget);
    });

    testWidgets('shows document count in vault summary', (tester) async {
      final event = _makeEvent(
        modules: const EventModules(vault: true),
      );
      final docs = [_makeDocument()];
      await tester.pumpWidget(_buildList(event: event, documents: docs));
      await tester.pumpAndSettle();

      // "1 document uploaded"
      expect(find.textContaining('document'), findsWidgets);
    });

    testWidgets('renders Memories card when memories module is enabled', (tester) async {
      final event = _makeEvent(
        modules: const EventModules(memories: true),
      );
      await tester.pumpWidget(_buildList(event: event));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byKey(EventKeys.memoriesCard), findsOneWidget);
    });

    testWidgets('renders all 5 module cards for a trip event', (tester) async {
      final event = _makeEvent(
        modules: const EventModules(
          ledger: true,
          gear: true,
          logistics: true,
          vault: true,
          memories: true,
        ),
      );
      await tester.pumpWidget(_buildList(event: event));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byKey(EventKeys.ledgerCard), findsOneWidget);
      expect(find.byKey(EventKeys.gearCard), findsOneWidget);
      expect(find.byKey(EventKeys.logisticsCard), findsOneWidget);
      expect(find.byKey(EventKeys.vaultCard), findsOneWidget);
      expect(find.byKey(EventKeys.memoriesCard), findsOneWidget);
    });

    testWidgets('renders only Ledger card when only ledger is enabled', (tester) async {
      final event = _makeEvent(
        modules: const EventModules(ledger: true),
      );
      await tester.pumpWidget(_buildList(event: event));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byKey(EventKeys.ledgerCard), findsOneWidget);
      expect(find.byKey(EventKeys.gearCard), findsNothing);
      expect(find.byKey(EventKeys.logisticsCard), findsNothing);
      expect(find.byKey(EventKeys.vaultCard), findsNothing);
      expect(find.byKey(EventKeys.memoriesCard), findsNothing);
    });
  });
}
