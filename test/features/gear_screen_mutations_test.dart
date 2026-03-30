import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safar/core/types/event_ref.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/gear/keys/gear_keys.dart';
import 'package:safar/features/gear/models/gear_item_model.dart';
import 'package:safar/features/gear/providers/gear_provider.dart';
import 'package:safar/features/gear/screens/gear_screen.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGearService extends Mock implements GearService {}

class MockUser extends Mock implements firebase_auth.User {}

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

final _testEvent = Event(
  id: 'event-1',
  name: 'Camping Trip',
  type: EventType.camping,
  groupId: 'group-1',
  createdBy: 'uid-creator',
  participantIds: const ['uid-creator', 'test-user-uid'],
  participantNames: const {
    'uid-creator': 'Alice',
    'test-user-uid': 'Bob',
  },
  modules: const EventModules(
    ledger: true,
    gear: true,
    logistics: false,
    vault: false,
    memories: false,
  ),
  currency: 'OMR',
  createdAt: DateTime(2026, 3, 1),
);

final EventRef _testEventRef = (groupId: 'group-1', eventId: 'event-1');

final _testItem = GearItem(
  id: 'item-1',
  tripId: 'event-1',
  itemName: 'Tent',
  assignedTo: null,
  isPacked: false,
  sequenceId: 1,
  isHighPriority: false,
);

final _claimedItem = GearItem(
  id: 'item-2',
  tripId: 'event-1',
  itemName: 'Sleeping Bag',
  assignedTo: 'test-user-uid',
  isPacked: false,
  sequenceId: 2,
  isHighPriority: false,
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrapGearScreen({
  required MockGearService mockService,
  required MockUser mockUser,
  List<GearItem> items = const [],
}) {
  return ProviderScope(
    overrides: [
      gearServiceProvider.overrideWithValue(mockService),
      eventDetailProvider(_testEventRef).overrideWith(
        (ref) => Stream.value(_testEvent),
      ),
      eventGearItemsProvider(_testEventRef).overrideWith(
        (ref) => Stream.value(items),
      ),
      currentUserProvider.overrideWith((ref) => mockUser),
      gearLoadingProvider.overrideWith((ref) => false),
    ],
    child: MaterialApp(
      home: GearScreen(groupId: _testEvent.groupId, eventId: _testEvent.id),
    ),
  );
}

/// Find the add-item text field specifically by hint text.
Finder get _addItemField => find.widgetWithText(TextField, 'ADD GEAR ITEM...');

/// Open the popup menu on the first gear item card and tap a menu item.
///
/// [PopupMenuButton] tap is unreliable in test viewports due to z-ordering
/// with the FAB and RefreshIndicator. Use [PopupMenuButtonState.showButtonMenu]
/// directly instead of simulating a tap.
Future<void> _openMenuAndTap(WidgetTester tester, String itemText) async {
  final menuBtn = find.byType(PopupMenuButton<String>).first;
  final PopupMenuButtonState<String> menuState = tester.state(menuBtn);
  menuState.showButtonMenu();
  await tester.pumpAndSettle();

  await tester.tap(find.text(itemText));
  await tester.pumpAndSettle();
}

void main() {
  late MockGearService mockGearService;
  late MockUser mockUser;

  setUp(() {
    mockGearService = MockGearService();
    mockUser = MockUser();
    when(() => mockUser.uid).thenReturn('test-user-uid');

    // Default stubs — tests can override as needed
    when(
      () => mockGearService.addGearItem(
        groupId: any(named: 'groupId'),
        eventId: any(named: 'eventId'),
        itemName: any(named: 'itemName'),
        isHighPriority: any(named: 'isHighPriority'),
        sequenceId: any(named: 'sequenceId'),
      ),
    ).thenAnswer((_) async => _testItem);

    when(
      () => mockGearService.deleteGearItem(
        groupId: any(named: 'groupId'),
        eventId: any(named: 'eventId'),
        gearItemId: any(named: 'gearItemId'),
      ),
    ).thenAnswer((_) async {});

    when(
      () => mockGearService.togglePacked(
        groupId: any(named: 'groupId'),
        eventId: any(named: 'eventId'),
        gearItemId: any(named: 'gearItemId'),
        isPacked: any(named: 'isPacked'),
      ),
    ).thenAnswer((_) async {});

    when(
      () => mockGearService.updateGearItem(
        groupId: any(named: 'groupId'),
        eventId: any(named: 'eventId'),
        gearItemId: any(named: 'gearItemId'),
        itemName: any(named: 'itemName'),
        assignedTo: any(named: 'assignedTo'),
        isHighPriority: any(named: 'isHighPriority'),
      ),
    ).thenAnswer((_) async {});

    when(
      () => mockGearService.unclaimGearItem(
        groupId: any(named: 'groupId'),
        eventId: any(named: 'eventId'),
        gearItemId: any(named: 'gearItemId'),
      ),
    ).thenAnswer((_) async {});
  });

  group('GearScreen — addItem', () {
    testWidgets('calls addGearItem with correct itemName, groupId, eventId',
        (tester) async {
      await tester.pumpWidget(_wrapGearScreen(
        mockService: mockGearService,
        mockUser: mockUser,
        items: const [],
      ));
      await tester.pumpAndSettle();

      // Find the add item text field specifically by hint text
      await tester.enterText(_addItemField, 'Flashlight');

      // Submit via keyboard done action
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      verify(
        () => mockGearService.addGearItem(
          groupId: 'group-1',
          eventId: 'event-1',
          itemName: 'Flashlight',
          isHighPriority: any(named: 'isHighPriority'),
          sequenceId: any(named: 'sequenceId'),
        ),
      ).called(1);
    });

    testWidgets('does NOT call addGearItem when text field is empty',
        (tester) async {
      await tester.pumpWidget(_wrapGearScreen(
        mockService: mockGearService,
        mockUser: mockUser,
        items: const [],
      ));
      await tester.pumpAndSettle();

      // Focus the add item field but leave it empty, then submit
      await tester.tap(_addItemField);
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      verifyNever(
        () => mockGearService.addGearItem(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
          itemName: any(named: 'itemName'),
          isHighPriority: any(named: 'isHighPriority'),
          sequenceId: any(named: 'sequenceId'),
        ),
      );
    });
  });

  group('GearScreen — deleteItem', () {
    testWidgets('calls deleteGearItem after confirming delete dialog',
        (tester) async {
      await tester.pumpWidget(_wrapGearScreen(
        mockService: mockGearService,
        mockUser: mockUser,
        items: [_testItem],
      ));
      await tester.pumpAndSettle();

      await _openMenuAndTap(tester, 'Delete');

      // Confirm the dialog
      await tester.tap(find.byKey(GearKeys.deleteConfirmButton));
      await tester.pumpAndSettle();

      verify(
        () => mockGearService.deleteGearItem(
          groupId: 'group-1',
          eventId: 'event-1',
          gearItemId: 'item-1',
        ),
      ).called(1);
    });
  });

  group('GearScreen — togglePacked', () {
    testWidgets(
        'calls togglePacked with isPacked=true when tapping unclaimed item checkbox',
        (tester) async {
      await tester.pumpWidget(_wrapGearScreen(
        mockService: mockGearService,
        mockUser: mockUser,
        items: [_testItem], // unclaimed item — assignedTo is null
      ));
      await tester.pumpAndSettle();

      // The packed checkbox is an AnimatedContainer inside a GestureDetector.
      // The first AnimatedContainer in the ListView is the packed checkbox
      // (the progress bar uses LinearProgressIndicator, not AnimatedContainer).
      final checkboxFinder = find.byType(AnimatedContainer).first;
      await tester.ensureVisible(checkboxFinder);
      await tester.pump();
      await tester.tap(checkboxFinder, warnIfMissed: false);
      await tester.pumpAndSettle();

      verify(
        () => mockGearService.togglePacked(
          groupId: 'group-1',
          eventId: 'event-1',
          gearItemId: 'item-1',
          isPacked: true,
        ),
      ).called(1);
    });
  });

  group('GearScreen — priority', () {
    testWidgets(
        'calls updateGearItem with isHighPriority=true when toggling priority',
        (tester) async {
      await tester.pumpWidget(_wrapGearScreen(
        mockService: mockGearService,
        mockUser: mockUser,
        items: [_testItem],
      ));
      await tester.pumpAndSettle();

      await _openMenuAndTap(tester, 'Toggle Priority');

      verify(
        () => mockGearService.updateGearItem(
          groupId: 'group-1',
          eventId: 'event-1',
          gearItemId: 'item-1',
          isHighPriority: true,
        ),
      ).called(1);
    });
  });

  group('GearScreen — claim', () {
    testWidgets(
        'calls updateGearItem with assignedTo=currentUserUid when claiming',
        (tester) async {
      await tester.pumpWidget(_wrapGearScreen(
        mockService: mockGearService,
        mockUser: mockUser,
        items: [_testItem], // unclaimed item
      ));
      await tester.pumpAndSettle();

      await _openMenuAndTap(tester, 'Claim Item');

      verify(
        () => mockGearService.updateGearItem(
          groupId: 'group-1',
          eventId: 'event-1',
          gearItemId: 'item-1',
          assignedTo: 'test-user-uid',
        ),
      ).called(1);
    });
  });

  group('GearScreen — unclaim', () {
    testWidgets('calls unclaimGearItem with correct gearItemId when unclaiming',
        (tester) async {
      await tester.pumpWidget(_wrapGearScreen(
        mockService: mockGearService,
        mockUser: mockUser,
        items: [_claimedItem], // claimed item — shows Unclaim option
      ));
      await tester.pumpAndSettle();

      await _openMenuAndTap(tester, 'Unclaim Item');

      verify(
        () => mockGearService.unclaimGearItem(
          groupId: 'group-1',
          eventId: 'event-1',
          gearItemId: 'item-2',
        ),
      ).called(1);
    });
  });

  group('GearScreen — error handling', () {
    testWidgets('shows snackbar error when addGearItem throws', (tester) async {
      when(
        () => mockGearService.addGearItem(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
          itemName: any(named: 'itemName'),
          isHighPriority: any(named: 'isHighPriority'),
          sequenceId: any(named: 'sequenceId'),
        ),
      ).thenThrow(Exception('network error'));

      await tester.pumpWidget(_wrapGearScreen(
        mockService: mockGearService,
        mockUser: mockUser,
        items: const [],
      ));
      await tester.pumpAndSettle();

      // Enter text and submit via keyboard done
      await tester.enterText(_addItemField, 'Tent');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      // Pump to allow async _addItem to complete
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify snackbar with error message appears
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining("Couldn't add item"),
        ),
        findsOneWidget,
      );
    });
  });
}
