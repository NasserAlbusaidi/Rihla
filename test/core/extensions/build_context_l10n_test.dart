import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/extensions/build_context_l10n.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('context.l10n returns AppLocalizations for current locale', (
    tester,
  ) async {
    late AppLocalizations captured;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            captured = context.l10n;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(captured.offlineBannerMessage, "You're offline — changes will sync later");
  });
}
