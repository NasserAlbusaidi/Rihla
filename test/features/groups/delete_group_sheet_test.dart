import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/widgets/delete_group_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// #227 — direct coverage for the type-to-confirm gating on the destructive
// "Delete group" sheet. The host-screen test (group_settings_screen_test)
// only asserts the sheet OPENS; the gating logic (button stays disabled until
// the typed token matches the group name, cancel is a no-op) was untested.
void main() {
  Future<void> openSheet(
    WidgetTester tester, {
    required String groupName,
    int memberCount = 3,
    required VoidCallback onConfirm,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const Key('open'),
                onPressed: () => showDeleteGroupSheet(
                  context,
                  groupName: groupName,
                  memberCount: memberCount,
                  onConfirm: onConfirm,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  ElevatedButton confirmButton(WidgetTester tester) =>
      tester.widget<ElevatedButton>(
        find.byKey(GroupKeys.deleteGroupConfirmButton),
      );

  testWidgets('confirm stays disabled until the typed name matches', (
    tester,
  ) async {
    var confirmed = 0;
    await openSheet(tester, groupName: 'Trip Crew', onConfirm: () => confirmed++);

    expect(find.byKey(GroupKeys.deleteGroupDialog), findsOneWidget);
    // Empty input → disabled.
    expect(confirmButton(tester).onPressed, isNull);

    // Wrong token → still disabled.
    await tester.enterText(find.byType(TextField), 'wrong name');
    await tester.pump();
    expect(confirmButton(tester).onPressed, isNull);

    // Tapping the disabled button is a no-op (no accidental delete).
    await tester.tap(
      find.byKey(GroupKeys.deleteGroupConfirmButton),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(confirmed, 0);
  });

  testWidgets('matching name (case-insensitive, trimmed) enables confirm and '
      'fires onConfirm exactly once', (tester) async {
    var confirmed = 0;
    await openSheet(tester, groupName: 'Trip Crew', onConfirm: () => confirmed++);

    await tester.enterText(find.byType(TextField), '  trip crew  ');
    await tester.pump();
    expect(confirmButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(GroupKeys.deleteGroupConfirmButton));
    await tester.pumpAndSettle();

    expect(confirmed, 1);
    // Sheet dismissed itself before invoking the callback.
    expect(find.byKey(GroupKeys.deleteGroupDialog), findsNothing);
  });

  testWidgets('cancel dismisses the sheet without confirming', (tester) async {
    var confirmed = 0;
    await openSheet(tester, groupName: 'Trip Crew', onConfirm: () => confirmed++);

    // The cancel control is the only OutlinedButton in the sheet.
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    expect(confirmed, 0);
    expect(find.byKey(GroupKeys.deleteGroupDialog), findsNothing);
  });
}
