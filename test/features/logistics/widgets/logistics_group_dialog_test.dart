import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

import 'package:safar/features/logistics/keys/logistics_keys.dart';
import 'package:safar/features/logistics/models/sub_group_model.dart';
import 'package:safar/features/logistics/providers/sub_group_provider.dart';
import 'package:safar/features/logistics/widgets/logistics_group_dialog.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _existingGroup = SubGroup(
  id: 'sg-1',
  tripId: 'event-1',
  name: 'Defender 1',
  type: SubGroupType.car,
  capacity: 5,
);

Widget _wrap({
  SubGroup? initialGroup,
  Future<void> Function(String name, int capacity)? onCreateGroup,
  Future<void> Function(String name, int capacity)? onUpdateGroup,
}) {
  return ProviderScope(
    overrides: [
      subGroupLoadingProvider.overrideWith((ref) => false),
    ],
    child: MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(
        body: LogisticsGroupDialog(
          initialGroup: initialGroup,
          onCreateGroup: onCreateGroup ?? (_, __) async {},
          onUpdateGroup: onUpdateGroup ?? (_, __) async {},
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LogisticsGroupDialog — create mode (initialGroup == null)', () {
    testWidgets('renders "NEW GROUP" title with createGroupTitle key',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(LogisticsKeys.createGroupTitle), findsOneWidget);
      expect(find.text('NEW GROUP'), findsOneWidget);
    });

    testWidgets('name field starts empty', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final nameField = tester.widget<TextField>(
        find.widgetWithHint(TextField, 'CAR NAME (e.g. DEFENDER 1)'),
      );
      expect(nameField.controller?.text, isEmpty);
    });

    testWidgets('calls onCreateGroup with typed values when CREATE GROUP pressed',
        (tester) async {
      String? capturedName;
      int? capturedCapacity;

      await tester.pumpWidget(_wrap(
        onCreateGroup: (name, capacity) async {
          capturedName = name;
          capturedCapacity = capacity;
        },
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithHint(TextField, 'CAR NAME (e.g. DEFENDER 1)'),
        'Hilux',
      );
      await tester.enterText(
        find.widgetWithHint(TextField, 'CAPACITY'),
        '6',
      );

      await tester.tap(find.byKey(LogisticsKeys.createGroupButton));
      await tester.pumpAndSettle();

      expect(capturedName, equals('Hilux'));
      expect(capturedCapacity, equals(6));
    });

    testWidgets('does not call onCreateGroup when name is empty', (tester) async {
      var called = false;
      await tester.pumpWidget(_wrap(onCreateGroup: (_, __) async => called = true));
      await tester.pumpAndSettle();

      // Name field is empty — tap CREATE GROUP
      await tester.tap(find.byKey(LogisticsKeys.createGroupButton));
      await tester.pumpAndSettle();

      expect(called, isFalse);
    });
  });

  group('LogisticsGroupDialog — edit mode (initialGroup != null)', () {
    testWidgets('renders "EDIT GROUP" title (no createGroupTitle key)',
        (tester) async {
      await tester.pumpWidget(_wrap(initialGroup: _existingGroup));
      await tester.pumpAndSettle();

      expect(find.text('EDIT GROUP'), findsOneWidget);
      expect(find.byKey(LogisticsKeys.createGroupTitle), findsNothing);
    });

    testWidgets('prefills name from initialGroup', (tester) async {
      await tester.pumpWidget(_wrap(initialGroup: _existingGroup));
      await tester.pumpAndSettle();

      final nameField = tester.widget<TextField>(
        find.widgetWithHint(TextField, 'CAR NAME (e.g. DEFENDER 1)'),
      );
      expect(nameField.controller?.text, equals('Defender 1'));
    });

    testWidgets('prefills capacity from initialGroup', (tester) async {
      await tester.pumpWidget(_wrap(initialGroup: _existingGroup));
      await tester.pumpAndSettle();

      final capacityField = tester.widget<TextField>(
        find.widgetWithHint(TextField, 'CAPACITY'),
      );
      expect(capacityField.controller?.text, equals('5'));
    });

    testWidgets('calls onUpdateGroup (not onCreateGroup) when SAVE CHANGES pressed',
        (tester) async {
      var createCalled = false;
      String? updatedName;

      await tester.pumpWidget(_wrap(
        initialGroup: _existingGroup,
        onCreateGroup: (_, __) async => createCalled = true,
        onUpdateGroup: (name, __) async => updatedName = name,
      ));
      await tester.pumpAndSettle();

      // Modify the name
      await tester.enterText(
        find.widgetWithHint(TextField, 'CAR NAME (e.g. DEFENDER 1)'),
        'Land Cruiser',
      );

      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();

      expect(createCalled, isFalse);
      expect(updatedName, equals('Land Cruiser'));
    });
  });
}

// ---------------------------------------------------------------------------
// Finder helpers
// ---------------------------------------------------------------------------

extension on CommonFinders {
  Finder widgetWithHint(Type widgetType, String hint) {
    return find.byWidgetPredicate((widget) {
      if (widget is! TextField) return false;
      return widget.decoration?.hintText == hint;
    });
  }
}
