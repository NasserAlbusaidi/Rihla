import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/theme/tokens/typography_tokens.dart';
import 'package:safar/shared/widgets/section_header.dart';

import '../../helpers/pump_rihla_app.dart';

TextStyle _titleStyle(WidgetTester tester, String rendered) {
  return tester.widget<Text>(find.text(rendered)).style!;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'EN: title keeps the mono caption recipe — Geist Mono, 1.2 tracking, '
    'uppercase',
    (tester) async {
      await pumpRihlaApp(
        tester,
        const Scaffold(body: SectionHeader(title: 'Active journeys')),
      );

      final style = _titleStyle(tester, 'ACTIVE JOURNEYS');
      expect(style.fontFamily, AppTypography.monoFamily);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.letterSpacing, 1.2);
    },
  );

  testWidgets(
    'AR: title drops mono tracking — sans family, letterSpacing 0 (#841)',
    (tester) async {
      await pumpRihlaApp(
        tester,
        const Scaffold(body: SectionHeader(title: 'الرحلات النشطة')),
        locale: const Locale('ar'),
      );

      final style = _titleStyle(tester, 'الرحلات النشطة');
      expect(
        style.fontFamily,
        isNot(AppTypography.monoFamily),
        reason: 'mono tracking visually disconnects joined Arabic script',
      );
      expect(style.fontFamily, AppTypography.sansFamily);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.letterSpacing, 0);
    },
  );
}
