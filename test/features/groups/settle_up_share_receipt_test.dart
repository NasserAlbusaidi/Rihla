import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/widgets/settle_up_page_body.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #359 — a recorded payment in the settle-up history exposes a "Share receipt"
/// affordance that composes a plain-text receipt and sends it through the
/// iOS-safe `shareText()` helper.
///
/// Asserts BOTH the composed text (payer paid recipient AMOUNT · date · subject)
/// AND a non-zero share origin on the wire — the iOS-only failure mode the
/// channel-mock-text tests can't catch (CLAUDE.md share landmine).
Widget _host(Widget body, {Locale? locale}) {
  return ProviderScope(
    child: MaterialApp(
      locale: locale,
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: body),
      ),
    ),
  );
}

SettleUpPageBody _bodyWithHistory() {
  return SettleUpPageBody(
    scope: SettleScope.group,
    subjectName: 'Beach House',
    simplifyDebts: true,
    buckets: [
      (
        currency: 'OMR',
        optimalSettlements: const <Map<String, dynamic>>[],
        balances: [
          UserBalance(
            participantId: 'uid-ahmed',
            displayName: 'Ahmed',
            totalPaid: Decimal.parse('5.000'),
            totalOwed: Decimal.zero,
            netBalance: Decimal.parse('5.000'),
          ),
          UserBalance(
            participantId: 'uid-sara',
            displayName: 'Sara',
            totalPaid: Decimal.zero,
            totalOwed: Decimal.parse('5.000'),
            netBalance: Decimal.parse('-5.000'),
          ),
        ],
      ),
    ],
    rawNames: const {'uid-ahmed': 'Ahmed', 'uid-sara': 'Sara'},
    settlementsAsync: AsyncValue.data([
      Settlement(
        id: 's1',
        tripId: 'event-1',
        payerParticipantId: 'uid-ahmed',
        recipientParticipantId: 'uid-sara',
        amount: Decimal.parse('5.000'),
        settledAt: DateTime(2026, 6, 7),
        payerName: 'Ahmed',
        recipientName: 'Sara',
      ),
    ]),
    currentUid: 'uid-ahmed',
    tileKeys: const {},
    onRecord: ({
      required settlement,
      required fromRawName,
      required toRawName,
      required fromUserId,
      required toUserId,
      required suggestedAmount,
      required String currency,
    }) {},
  );
}

void main() {
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

  testWidgets(
    'tapping Share receipt composes the text and forwards a non-zero origin',
    (tester) async {
      Map<Object?, Object?>? args;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        shareChannel,
        (call) async {
          if (call.method == 'share') {
            args = call.arguments as Map<Object?, Object?>;
          }
          return '';
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          shareChannel,
          null,
        ),
      );

      await tester.pumpWidget(_host(_bodyWithHistory()));
      await tester.pumpAndSettle();

      final shareButton = find.byKey(GroupKeys.settleUpShareReceiptButton);
      expect(shareButton, findsOneWidget);

      await tester.ensureVisible(shareButton);
      await tester.tap(shareButton);
      await tester.pumpAndSettle();

      expect(args, isNotNull, reason: 'shareText must be invoked');

      final text = args!['text'] as String;
      expect(text, contains('Ahmed'));
      expect(text, contains('Sara'));
      expect(text, contains('OMR 5.000'));
      expect(text, contains('Beach House'));
      expect(text, contains('recorded in Rihla'));

      // iOS-only guard: a zero/absent origin throws PlatformException and
      // silently breaks the share sheet (CLAUDE.md). Assert it on the wire.
      expect((args!['originWidth'] as double) > 0, isTrue);
      expect((args!['originHeight'] as double) > 0, isTrue);

      // Multi-line receipt: amount/context/footer on their own lines, footer
      // last — a keepable artifact, not one run-on string.
      final lines = text.split('\n');
      expect(lines.length, greaterThanOrEqualTo(3));
      expect(lines.last, contains('recorded in Rihla'));
    },
  );

  testWidgets('receipt is composed in Arabic under the ar locale', (
    tester,
  ) async {
    Map<Object?, Object?>? args;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      shareChannel,
      (call) async {
        if (call.method == 'share') {
          args = call.arguments as Map<Object?, Object?>;
        }
        return '';
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        shareChannel,
        null,
      ),
    );

    await tester.pumpWidget(
      _host(_bodyWithHistory(), locale: const Locale('ar')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(GroupKeys.settleUpShareReceiptButton));
    await tester.pumpAndSettle();

    final text = args!['text'] as String;
    // Arabic connector ("دفع … إلى …") and footer, with names + amount intact.
    expect(text, contains('دفع'));
    expect(text, contains('مُسجَّل في رِحلة'));
    expect(text, contains('Ahmed'));
    expect(text, contains('OMR 5.000'));
  });
}
