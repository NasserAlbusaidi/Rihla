import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/utils/name_validators.dart';
import 'package:safar/features/settings/keys/profile_keys.dart';
import 'package:safar/features/settings/widgets/edit_name_bottom_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// #227 — direct coverage for EditNameBottomSheet (no prior test).
//
// Doubles as the client<->rules name-validation parity guard: the sheet calls
// validateDisplayName / normalizeDisplayName, which mirror isValidDisplayName
// in security/firestore.rules (1-32 chars, no control chars). The tooLong
// (33-char) leg is already covered in profile_screen_test via the full flow;
// here we isolate the widget and exercise the remaining legs: empty (button
// disabled), control character (inline error, no save), and the
// valid+normalize boundary (onSave receives the collapsed/trimmed value).
void main() {
  Future<void> openEditName(
    WidgetTester tester, {
    required String currentName,
    required Future<void> Function(String) onSave,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('open'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => EditNameBottomSheet(
                      currentName: currentName,
                      onSave: onSave,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  ElevatedButton saveButton(WidgetTester tester) => tester.widget<ElevatedButton>(
    find.byKey(ProfileKeys.saveNameButton),
  );

  testWidgets('empty / whitespace-only name keeps Save disabled', (
    tester,
  ) async {
    var saves = 0;
    await openEditName(tester, currentName: '', onSave: (_) async => saves++);

    // Seeded empty → Save disabled.
    expect(saveButton(tester).onPressed, isNull);

    // Whitespace-only is still empty after trim → stays disabled.
    await tester.enterText(find.byKey(ProfileKeys.nameTextField), '   ');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNull);
    expect(saves, 0);
  });

  testWidgets('control character is rejected inline; onSave not called', (
    tester,
  ) async {
    var saves = 0;
    await openEditName(tester, currentName: 'Alice', onSave: (_) async => saves++);

    // U+0007 (BEL) is a C0 control char, rejected by both the client validator
    // and the firestore.rules charset. (Not a newline, so a single-line field
    // won't strip it on input.)
    await tester.enterText(
      find.byKey(ProfileKeys.nameTextField),
      'Bad${String.fromCharCode(7)}Name',
    );
    await tester.tap(find.byKey(ProfileKeys.saveNameButton));
    await tester.pump();

    expect(
      find.text('Remove line breaks or special characters.'),
      findsOneWidget,
    );
    expect(saves, 0);
  });

  testWidgets('valid name is normalized before onSave', (tester) async {
    String? saved;
    await openEditName(
      tester,
      currentName: 'Alice',
      onSave: (name) async => saved = name,
    );

    await tester.enterText(
      find.byKey(ProfileKeys.nameTextField),
      '  Bob   Smith  ',
    );
    await tester.tap(find.byKey(ProfileKeys.saveNameButton));
    await tester.pump(); // onSave runs (captures `saved`) + enters saving state

    // Trimmed + internal whitespace collapsed at the write boundary.
    expect(saved, 'Bob Smith');

    // Drain the success-animation timers (600ms hold + 800ms check) so the
    // sheet pops and no timer outlives the test (teardown asserts none pend).
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'shows the taken-name error and recovers when onSave rejects (#390)',
    (tester) async {
      await openEditName(
        tester,
        currentName: 'Ahmed',
        onSave: (_) async =>
            throw const DisplayNameTakenException('Trip to Muscat'),
      );

      await tester.enterText(find.byKey(ProfileKeys.nameTextField), 'Sara');
      await tester.pump();
      await tester.tap(find.byKey(ProfileKeys.saveNameButton));
      await tester.pumpAndSettle();

      // Localized error names the conflicting group; the spinner cleared so the
      // Save button is interactive again and the sheet did NOT pop.
      expect(find.textContaining('Trip to Muscat'), findsOneWidget);
      expect(saveButton(tester).onPressed, isNotNull);
      expect(find.byKey(ProfileKeys.saveNameButton), findsOneWidget);
    },
  );
}
