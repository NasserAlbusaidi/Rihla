import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/widgets/settle_notify_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// #367 — the post-record WhatsApp notify nudge sheet is a PURE presentational
// collector: it shows the prefilled message and returns true (WhatsApp tapped)
// or false (dismissed / Not now). It never launches anything itself — the caller
// owns the url_launcher handoff — so no platform mock is needed here.
void main() {
  Future<bool?> openAndReturn(
    WidgetTester tester, {
    String recipientName = 'Mariam',
    String message =
        "Hey Mariam, I've sent you OMR 18.500 for Beach House in Summer Trip.",
    required Future<void> Function(WidgetTester) act,
  }) async {
    bool? result;
    var resolved = false;
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
                onPressed: () async {
                  result = await showSettleNotifySheet(
                    context,
                    recipientName: recipientName,
                    message: message,
                  );
                  resolved = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    await act(tester);
    await tester.pumpAndSettle();

    expect(resolved, isTrue, reason: 'sheet should have resolved its Future');
    return result;
  }

  testWidgets('renders the prefilled message preview and recipient name', (
    tester,
  ) async {
    await openAndReturn(
      tester,
      act: (t) async {
        expect(find.byKey(GroupKeys.settleNotifySheet), findsOneWidget);
        expect(find.byKey(GroupKeys.settleNotifyMessagePreview), findsOneWidget);
        expect(
          find.textContaining("I've sent you OMR 18.500"),
          findsOneWidget,
        );
        // Title carries the recipient name.
        expect(find.textContaining('Mariam'), findsWidgets);
        await t.tap(find.byKey(GroupKeys.settleNotifyNotNowButton));
      },
    );
  });

  testWidgets('WhatsApp button resolves true (caller does the launch)', (
    tester,
  ) async {
    final result = await openAndReturn(
      tester,
      act: (t) async {
        await t.tap(find.byKey(GroupKeys.settleNotifyWhatsAppButton));
      },
    );
    expect(result, isTrue);
  });

  testWidgets('Not now resolves false', (tester) async {
    final result = await openAndReturn(
      tester,
      act: (t) async {
        await t.tap(find.byKey(GroupKeys.settleNotifyNotNowButton));
      },
    );
    expect(result, isFalse);
  });

  testWidgets('barrier dismiss resolves false (null coerced)', (tester) async {
    final result = await openAndReturn(
      tester,
      act: (t) async {
        await t.tapAt(const Offset(20, 20)); // tap the scrim above the sheet
      },
    );
    expect(result, isFalse);
  });
}
