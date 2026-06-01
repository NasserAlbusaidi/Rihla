import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/extensions/build_context_l10n.dart';
import 'package:safar/core/utils/localized_name_validators.dart';
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

  testWidgets('validateDisplayNameLocalized returns localized error messages', (
    tester,
  ) async {
    final messages = <String?>[];
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = context.l10n;
            messages
              ..add(validateDisplayNameLocalized(context, 'Alice\nBob'))
              ..add(validateDisplayNameLocalized(context, 'Bob (former member)'))
              ..add(validateDisplayNameLocalized(context, 'Valid Name'));
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(messages[0], l10n.nameValidationControlChars);
    expect(messages[1], l10n.nameValidationReserved);
    expect(messages[2], isNull);
  });
}
