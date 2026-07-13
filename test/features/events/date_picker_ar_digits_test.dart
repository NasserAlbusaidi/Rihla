import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/pump_rihla_app.dart';

/// #1227 — `showDatePicker`'s chrome (header date, year picker, calendar
/// title) comes from Flutter's own `MaterialLocalizations`, NOT from an
/// intl `DateFormat` site the app controls. #1226/#1215 forced Western
/// digits at every app-owned `DateFormat` call, but that fix cannot reach
/// here: `GlobalMaterialLocalizations.delegate.load('ar')` builds its own
/// internal `DateFormat`s (with `useNativeDigits` defaulting to true for
/// `ar`) and hands them to the generated `MaterialLocalizationAr`, which the
/// app never constructs directly. DEC-5/#145 is Western digits everywhere.
///
/// Regex matches Arabic-Indic (U+0660-U+0669) AND Extended Arabic-Indic
/// (U+06F0-U+06F9) digits — flutter_localizations' `ar` DateSymbols carry
/// the former.
final _arabicIndicDigit = RegExp('[٠-٩۰-۹]');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'showDatePicker renders Western digits under ar locale (#1227, DEC-5/#145)',
    (tester) async {
      await pumpRihlaApp(
        tester,
        Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    showDatePicker(
                      context: context,
                      initialDate: DateTime(2026, 5, 19),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
        locale: const Locale('ar'),
      );

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Collect every rendered string in the open picker (header date,
      // month/year title, calendar day-of-month grid, OK/Cancel actions).
      final rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? '')
          .join('\n');

      expect(
        _arabicIndicDigit.hasMatch(rendered),
        isFalse,
        reason:
            'Arabic-Indic digit found in date picker under ar locale:\n$rendered',
      );
      // Vacuous-pass guard: Western digits must actually be present
      // (the picked day "19" renders in the header).
      expect(rendered, contains('19'));
      // Over-fix guard: month name stays Arabic, picker stays RTL-language.
      expect(rendered, contains('مايو')); // "May"
    },
  );
}
