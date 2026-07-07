import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';
import 'package:safar/features/ledger/widgets/ledger_roster_strip.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/r_amount.dart';

/// PR #1044 codex P2 — the live balance chip renders a functional 9.5px amount
/// over a translucent success/error pill, so its text must use the WCAG-safe
/// `successText`/`errorText` tokens (as the pre-RAmount hand-rolled chip did),
/// never the lighter `success`/`error` surface tones (3.10:1 in light theme).
void main() {
  Widget buildStrip(List<LedgerRosterPerson> others) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: LedgerRosterStrip(
          state: LedgerRosterState.live,
          currency: 'OMR',
          currentUserDisplayName: 'You',
          others: others,
        ),
      ),
    );
  }

  /// Leaf spans of the RAmount rendering [value], in render order:
  /// [sign prefix, whole, decimal fragment].
  List<TextSpan> leavesOf(WidgetTester tester, Decimal value) {
    final amountFinder = find.byWidgetPredicate(
      (w) => w is RAmount && w.value == value,
    );
    expect(amountFinder, findsOneWidget);
    final richText = tester.widget<RichText>(
      find.descendant(of: amountFinder, matching: find.byType(RichText)),
    );
    final leaves = <TextSpan>[];
    richText.text.visitChildren((node) {
      if (node is TextSpan && node.text != null) leaves.add(node);
      return true;
    });
    return leaves;
  }

  Color wholeColorOf(WidgetTester tester, Decimal value) =>
      leavesOf(tester, value)[1].style!.color!;

  /// The decimal-fragment span (".000") — round 2 of the codex review: the
  /// whole part was fixed to successText/errorText but the fraction still
  /// rendered at RAmount's 0.7-alpha fade, below AA on the tinted pill.
  Color fractionColorOf(WidgetTester tester, Decimal value) {
    final leaves = leavesOf(tester, value);
    expect(leaves[2].text, startsWith('.'));
    return leaves[2].style!.color!;
  }

  testWidgets(
    'live chip amounts use the WCAG-safe successText/errorText tokens, '
    'not the surface success/error tones',
    (tester) async {
      final positiveAmount = Decimal.parse('5.000');
      final negativeAmount = -Decimal.parse('3.000');
      await tester.pumpWidget(
        buildStrip([
          LedgerRosterPerson(
            participantId: 'p1',
            displayName: 'Bob',
            signedAmount: positiveAmount,
            currency: 'OMR',
          ),
          LedgerRosterPerson(
            participantId: 'p2',
            displayName: 'Carla',
            signedAmount: negativeAmount,
            currency: 'OMR',
          ),
        ]),
      );
      await tester.pump();

      expect(
        wholeColorOf(tester, positiveAmount),
        AppColorTokens.light.successText,
        reason:
            'positive chip must use the dark text-safe sage, '
            'not colors.success (below AA at 9.5px on the tinted pill)',
      );
      expect(
        wholeColorOf(tester, negativeAmount),
        AppColorTokens.light.errorText,
        reason:
            'negative chip must use the dark text-safe rust, '
            'not colors.error',
      );

      // Every digit is functional at this size — the decimal fragment must be
      // full-strength too, never RAmount's default 0.7-alpha fade.
      expect(
        fractionColorOf(tester, positiveAmount),
        AppColorTokens.light.successText,
        reason:
            'positive chip fraction must render at full-strength '
            'successText — the 0.7-alpha fade is below AA on the pill',
      );
      expect(
        fractionColorOf(tester, negativeAmount),
        AppColorTokens.light.errorText,
        reason: 'negative chip fraction must render at full-strength errorText',
      );
    },
  );
}
