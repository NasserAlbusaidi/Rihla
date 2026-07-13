import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/localized_dates.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #1215 — every date formatter in `localized_dates.dart` must render Western
/// digits under `ar` (DEC-5/#145). The MaterialApp pump loads date symbols via
/// the REAL app localization path (GlobalMaterialLocalizations.delegate), whose
/// generated `ar` DateSymbols carry ZERODIGIT — intl then transliterates every
/// digit to Arabic-Indic unless the formatter sets `useNativeDigits = false`.
void main() {
  testWidgets(
    'localized_dates helpers render Western digits under ar locale',
    (tester) async {
      late String shortMonthDay;
      late String viaHoistedFormatter;
      late String shortMonthDayYear;
      late String monthYear;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final date = DateTime(2026, 5, 19);
              shortMonthDay = formatShortMonthDay(context, date);
              viaHoistedFormatter = shortMonthDayFormatter(
                context,
              ).format(date);
              shortMonthDayYear = formatShortMonthDayYear(context, date);
              monthYear = formatMonthYear(context, date);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(shortMonthDay, contains('19'));
      expect(shortMonthDay, isNot(contains('١٩')));

      expect(viaHoistedFormatter, contains('19'));
      expect(viaHoistedFormatter, isNot(contains('١٩')));

      // Year digits (yMMMd / yMMM skeletons).
      expect(shortMonthDayYear, contains('19'));
      expect(shortMonthDayYear, contains('2026'));
      expect(shortMonthDayYear, isNot(contains('١٩')));
      expect(shortMonthDayYear, isNot(contains('٢٠٢٦')));

      expect(monthYear, contains('2026'));
      expect(monthYear, isNot(contains('٢٠٢٦')));
    },
  );
}
