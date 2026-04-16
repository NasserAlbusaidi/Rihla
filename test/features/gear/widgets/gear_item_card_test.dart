import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/gear/models/gear_item_model.dart';
import 'package:safar/features/gear/widgets/gear_item_card.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

GearItem _buildItem({
  required String id,
  String name = 'Sleeping bag',
  bool isPacked = false,
  bool isHighPriority = false,
  String? assignedTo,
  String? assignedToName,
}) {
  return GearItem(
    id: id,
    tripId: 'e1',
    itemName: name,
    isPacked: isPacked,
    isHighPriority: isHighPriority,
    assignedTo: assignedTo,
    assignedToName: assignedToName,
    sequenceId: 1,
    createdAt: DateTime(2026, 4, 1),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GearItemCard — rendering', () {
    testWidgets('renders item name in uppercase', (tester) async {
      final item = _buildItem(id: 'i1', name: 'Flashlight');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GearItemCard(
              item: item,
              currentUserId: 'uid-me',
              onTogglePacked: (_, __) {},
              onMenuAction: (_, __) {},
            ),
          ),
        ),
      );

      expect(find.text('FLASHLIGHT'), findsOneWidget);
    });

    testWidgets('renders status chip with status text', (tester) async {
      final item = _buildItem(id: 'i1');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GearItemCard(
              item: item,
              currentUserId: 'uid-me',
              onTogglePacked: (_, __) {},
              onMenuAction: (_, __) {},
            ),
          ),
        ),
      );

      // Status chip shows displayName in uppercase
      expect(find.text('UNCLAIMED'), findsOneWidget);
    });

    testWidgets('renders HIGH priority badge when isHighPriority is true',
        (tester) async {
      final item = _buildItem(id: 'i1', isHighPriority: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GearItemCard(
              item: item,
              currentUserId: 'uid-me',
              onTogglePacked: (_, __) {},
              onMenuAction: (_, __) {},
            ),
          ),
        ),
      );

      expect(find.text('HIGH'), findsOneWidget);
    });

    testWidgets('does NOT render priority badge when isHighPriority is false',
        (tester) async {
      final item = _buildItem(id: 'i1', isHighPriority: false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GearItemCard(
              item: item,
              currentUserId: 'uid-me',
              onTogglePacked: (_, __) {},
              onMenuAction: (_, __) {},
            ),
          ),
        ),
      );

      expect(find.text('HIGH'), findsNothing);
    });
  });

  group('GearItemCard — callbacks', () {
    testWidgets('calls onTogglePacked with the correct item when tapped',
        (tester) async {
      final item = _buildItem(id: 'i1', name: 'Tent');
      GearItem? tappedItem;
      bool? tappedIsMine;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GearItemCard(
              item: item,
              currentUserId: 'uid-me',
              onTogglePacked: (i, isMine) {
                tappedItem = i;
                tappedIsMine = isMine;
              },
              onMenuAction: (_, __) {},
            ),
          ),
        ),
      );

      final checkbox = find.byType(AnimatedContainer).first;
      await tester.tap(checkbox, warnIfMissed: false);
      await tester.pump();

      expect(tappedItem, isNotNull);
      expect(tappedItem!.id, equals('i1'));
      // item has no assignedTo, currentUserId doesn't match → isMine = false
      expect(tappedIsMine, isFalse);
    });

    testWidgets('calls onMenuAction with delete value when Delete tapped',
        (tester) async {
      final item = _buildItem(id: 'i1');
      String? capturedAction;
      GearItem? capturedItem;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GearItemCard(
              item: item,
              currentUserId: 'uid-me',
              onTogglePacked: (_, __) {},
              onMenuAction: (action, i) {
                capturedAction = action;
                capturedItem = i;
              },
            ),
          ),
        ),
      );

      // Open popup menu
      final menuBtn = find.byType(PopupMenuButton<String>);
      final PopupMenuButtonState<String> state = tester.state(menuBtn);
      state.showButtonMenu();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(capturedAction, equals('delete'));
      expect(capturedItem!.id, equals('i1'));
    });
  });
}
