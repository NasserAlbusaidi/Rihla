import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

import 'package:safar/features/gear/models/gear_item_model.dart';
import 'package:safar/features/gear/widgets/gear_item_card.dart';
import 'package:safar/features/gear/widgets/gear_list_view.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

GearItem _buildItem({required String id, String name = 'Sleeping bag'}) {
  return GearItem(
    id: id,
    tripId: 'e1',
    itemName: name,
    sequenceId: 1,
    createdAt: DateTime(2026, 4, 1),
  );
}

/// Wraps GearListView with MediaQuery.disableAnimations=true so FadeInList
/// uses a plain Column, avoiding pending animation timers in tests.
Widget _wrap(GearListView view) => MaterialApp(theme: AppTheme.lightTheme, home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: view),
      ),
    );

GearListView _buildListView({
  List<GearItem> items = const [],
  String searchQuery = '',
  String? statusFilter,
  bool hideClaimed = false,
}) {
  final controller = TextEditingController();
  return GearListView(
    items: items,
    currentUserId: 'uid-me',
    searchQuery: searchQuery,
    statusFilter: statusFilter,
    hideClaimed: hideClaimed,
    onTogglePacked: (_, __) {},
    onMenuAction: (_, __) {},
    onSearchChanged: (_) {},
    onStatusFilterChanged: (_) {},
    onRefresh: () {},
    onAddItem: () {},
    addController: controller,
    isHighPriority: false,
    onPriorityChanged: (_) {},
    onSubmitAdd: () {},
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GearListView — empty state', () {
    testWidgets('renders empty state widget when items list is empty',
        (tester) async {
      await tester.pumpWidget(_wrap(_buildListView()));

      // EmptyStateView shows "Nothing packed yet" when items is empty
      expect(find.text('Nothing packed yet'), findsOneWidget);
    });

    testWidgets('renders zero GearItemCard widgets when items is empty',
        (tester) async {
      await tester.pumpWidget(_wrap(_buildListView()));

      expect(find.byType(GearItemCard), findsNothing);
    });
  });

  group('GearListView — populated state', () {
    testWidgets('renders N GearItemCard widgets for N items', (tester) async {
      final items = [
        _buildItem(id: 'i1', name: 'Tent'),
        _buildItem(id: 'i2', name: 'Sleeping Bag'),
        _buildItem(id: 'i3', name: 'Torch'),
      ];

      await tester.pumpWidget(_wrap(_buildListView(items: items)));

      expect(find.byType(GearItemCard), findsNWidgets(3));
    });

    testWidgets('renders item names as uppercase text', (tester) async {
      final items = [_buildItem(id: 'i1', name: 'Tent')];
      await tester.pumpWidget(_wrap(_buildListView(items: items)));

      expect(find.text('TENT'), findsOneWidget);
    });

    testWidgets('renders GEAR ITEMS section header when items present',
        (tester) async {
      final items = [_buildItem(id: 'i1')];
      await tester.pumpWidget(_wrap(_buildListView(items: items)));

      expect(find.text('GEAR ITEMS'), findsOneWidget);
    });
  });

  group('GearListView — filtering', () {
    testWidgets('shows no-match message when search has no results',
        (tester) async {
      final items = [_buildItem(id: 'i1', name: 'Tent')];
      await tester.pumpWidget(
        _wrap(_buildListView(items: items, searchQuery: 'zzz_no_match')),
      );

      expect(find.text('No items match your filter'), findsOneWidget);
      expect(find.byType(GearItemCard), findsNothing);
    });
  });
}
