import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/module_header.dart';

/// Regression for #126: the ModuleHeader back arrow (Iconsax.arrow_left) was a
/// bare Icon, so it pointed ← in Arabic instead of mirroring to →. It must flip
/// under RTL (via DirectionalIcon's horizontal Transform) and stay put in LTR.
void main() {
  Future<void> pumpHeader(
    WidgetTester tester, {
    required TextDirection direction,
    bool dark = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: ModuleHeader(title: 'Settle Up', useDarkTheme: dark),
          ),
        ),
      ),
    );
  }

  bool backArrowIsMirrored(WidgetTester tester) {
    final transforms = tester.widgetList<Transform>(
      find.ancestor(
        of: find.byIcon(Iconsax.arrow_left),
        matching: find.byType(Transform),
      ),
    );
    return transforms.any((t) => t.transform.getRow(0).x == -1.0);
  }

  testWidgets('light back arrow is mirrored under RTL', (tester) async {
    await pumpHeader(tester, direction: TextDirection.rtl);
    expect(find.byIcon(Iconsax.arrow_left), findsOneWidget);
    expect(backArrowIsMirrored(tester), isTrue);
  });

  testWidgets('light back arrow is NOT mirrored under LTR', (tester) async {
    await pumpHeader(tester, direction: TextDirection.ltr);
    expect(find.byIcon(Iconsax.arrow_left), findsOneWidget);
    expect(backArrowIsMirrored(tester), isFalse);
  });

  testWidgets('dark back arrow is mirrored under RTL', (tester) async {
    await pumpHeader(tester, direction: TextDirection.rtl, dark: true);
    expect(find.byIcon(Iconsax.arrow_left), findsOneWidget);
    expect(backArrowIsMirrored(tester), isTrue);
  });
}
