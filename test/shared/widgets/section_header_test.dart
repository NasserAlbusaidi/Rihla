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
    'EN: title keeps the mono caption recipe — Spline Sans Mono, 1.2 tracking, '
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

  testWidgets('Falaj PR-3: leading share-notch tick renders before the title', (
    tester,
  ) async {
    await pumpRihlaApp(
      tester,
      const Scaffold(body: SectionHeader(title: 'Active journeys')),
    );

    final tickFinder = find.byKey(const Key('section_header_tick'));
    expect(tickFinder, findsOneWidget);

    final tickRect = tester.getRect(tickFinder);
    final titleRect = tester.getRect(find.text('ACTIVE JOURNEYS'));
    expect(tickRect.right, lessThanOrEqualTo(titleRect.left));
  });

  testWidgets(
    'title yields with one-line ellipsis while action stays one line (#1064)',
    (tester) async {
      await pumpRihlaApp(
        tester,
        const Scaffold(
          body: SectionHeader(
            title: 'Active journeys',
            actionLabel: 'View history',
          ),
        ),
      );

      final titleFinder = find.text('ACTIVE JOURNEYS');
      final title = tester.widget<Text>(titleFinder);
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);

      final titleFlex = find.ancestor(
        of: titleFinder,
        matching: find.byType(Flexible),
      );
      expect(titleFlex, findsOneWidget);
      expect(tester.widget<Flexible>(titleFlex).fit, FlexFit.tight);

      final action = tester.widget<Text>(find.text('View history'));
      expect(action.maxLines, 1);
    },
  );

  testWidgets('Falaj PR-3: RTL keeps the tick on the leading (right) edge', (
    tester,
  ) async {
    await pumpRihlaApp(
      tester,
      const Scaffold(body: SectionHeader(title: 'الرحلات النشطة')),
      locale: const Locale('ar'),
    );

    final tickRect = tester.getRect(
      find.byKey(const Key('section_header_tick')),
    );
    final titleRect = tester.getRect(find.text('الرحلات النشطة'));
    expect(
      tickRect.left,
      greaterThan(titleRect.left),
      reason: 'under RTL the leading edge is visually on the right',
    );
  });
}
