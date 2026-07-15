// BackupAccountCard copy dispatch (#1256 Task 9b): on iOS the sheet this card
// opens offers Apple + Google, so the Google-worded body must switch to the
// provider-neutral profileBackupCardBodyIos; Android stays byte-identical.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/settings/widgets/profile/backup_account_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: BackupAccountCard()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('iOS renders the provider-neutral body', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await _pump(tester);

    final l10n = AppLocalizationsEn();
    expect(find.text(l10n.profileBackupCardBodyIos), findsOneWidget);
    expect(find.text(l10n.profileBackupCardBody), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('default platform (android) keeps the existing body', (
    tester,
  ) async {
    await _pump(tester);

    final l10n = AppLocalizationsEn();
    expect(find.text(l10n.profileBackupCardBody), findsOneWidget);
    expect(find.text(l10n.profileBackupCardBodyIos), findsNothing);
  });
}
