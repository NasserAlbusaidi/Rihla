import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/directional_icon.dart';
import 'package:safar/shared/widgets/falaj_fork.dart';
import 'package:safar/shared/widgets/r_avatar.dart';

Future<void> _pumpTile(
  WidgetTester tester, {
  required TextDirection textDirection,
  required String fromName,
  required String toName,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Directionality(
        textDirection: textDirection,
        child: Scaffold(
          body: GroupSettlementTile(
            fromName: fromName,
            toName: toName,
            amount: Decimal.parse('5.000'),
            currency: 'OMR',
            breakdown: const {},
            isYourAction: true,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _captionFinder() => find.ancestor(
  of: find.byType(DirectionalIcon),
  matching: find.byType(RichText),
);

double _nameCenterX(
  WidgetTester tester,
  Finder captionFinder,
  String name,
) {
  final paragraph = tester.renderObject<RenderParagraph>(captionFinder);
  final renderedText = paragraph.text.toPlainText(
    includeSemanticsLabels: false,
  );
  final start = renderedText.indexOf(name);
  expect(start, greaterThanOrEqualTo(0));

  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + name.length),
  );
  expect(boxes, isNotEmpty);
  final bounds = boxes
      .map((box) => box.toRect())
      .reduce((current, box) => current.expandToInclude(box));
  return bounds.center.dx;
}

String _captionSemanticsText(WidgetTester tester, Finder captionFinder) {
  final paragraph = tester.renderObject<RenderParagraph>(captionFinder);
  return paragraph.text
      .getSemanticsInformation()
      .where((info) => !info.isPlaceholder)
      .map((info) => info.semanticsLabel ?? info.text)
      .join();
}

void main() {
  testWidgets(
    'payer and payee both render the shared RAvatar — deterministic per-person '
    'color, not a hand-rolled tint (#490, DEC-3)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GroupSettlementTile(
              fromName: 'Alice',
              toName: 'Bob',
              amount: Decimal.parse('10.000'),
              currency: 'OMR',
              breakdown: const {},
              isYourAction: true,
            ),
          ),
        ),
      );
      await tester.pump();

      // Both avatars are the shared RAvatar (name only, no hue override — DEC-3),
      // replacing the prior hand-rolled saffron/cardSoft tint circles.
      final avatars = tester.widgetList<RAvatar>(find.byType(RAvatar)).toList();
      expect(avatars, hasLength(2));
      expect(avatars.map((a) => a.name), containsAll(['Alice', 'Bob']));
      expect(avatars.every((a) => a.hue == null), isTrue);
    },
  );

  testWidgets(
    'direction line keeps the disambiguation discriminator — two same-named '
    'members render "Sam (#aaaa) -> Sam (#bbbb)", never "Sam -> Sam" (#263)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GroupSettlementTile(
              fromName: 'Sam (#aaaa)',
              toName: 'Sam (#bbbb)',
              amount: Decimal.parse('5.000'),
              currency: 'OMR',
              breakdown: const {},
              isYourAction: true,
            ),
          ),
        ),
      );
      await tester.pump();

      // The visible direction line is a RichText, so traverse it.
      expect(
        find.textContaining('Sam (#aaaa)', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Sam (#bbbb)', findRichText: true),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'direction line still compacts a multi-token name to its first token '
    'when no discriminator is present (#263 preserves the #196-era compaction)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GroupSettlementTile(
              fromName: 'Sam Smith',
              toName: 'Bob Jones',
              amount: Decimal.parse('5.000'),
              currency: 'OMR',
              breakdown: const {},
              isYourAction: true,
            ),
          ),
        ),
      );
      await tester.pump();

      // #840: the transfer arrow is now a DirectionalIcon (RTL-mirrorable),
      // never a raw ' -> ' string embedded in the span text.
      expect(find.textContaining('Sam', findRichText: true), findsWidgets);
      expect(find.textContaining('Bob', findRichText: true), findsWidgets);
      expect(find.textContaining('->', findRichText: true), findsNothing);
      expect(find.textContaining('Smith', findRichText: true), findsNothing);
      // One DirectionalIcon: the direction-line caption arrow. The rail's
      // trailing arrow retired with comp-8 — the fork connector carries the
      // direction cue there.
      expect(find.byType(DirectionalIcon), findsOneWidget);
    },
  );

  testWidgets(
    'comp-8 (#900): transfer connector is the structural falaj fork — rule2, '
    'never brass (usage law: connector is channel-work, not the brand mark)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GroupSettlementTile(
              fromName: 'Alice',
              toName: 'Bob',
              amount: Decimal.parse('10.000'),
              currency: 'OMR',
              breakdown: const {},
              isYourAction: true,
            ),
          ),
        ),
      );
      await tester.pump();

      final forkFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FalajForkPainter,
      );
      expect(forkFinder, findsOneWidget);
      final painter =
          tester.widget<CustomPaint>(forkFinder).painter! as FalajForkPainter;
      expect(painter.color, AppColorTokens.light.rule2);
      expect(painter.color, isNot(AppColorTokens.light.primary));
      expect(painter.textDirection, TextDirection.ltr);
    },
  );

  testWidgets(
    'comp-8 (#900): fork connector mirrors under RTL — branches fan into the '
    'payee in reading direction',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: GroupSettlementTile(
                fromName: 'Sam',
                toName: 'Bob',
                amount: Decimal.parse('5.000'),
                currency: 'OMR',
                breakdown: const {},
                isYourAction: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final forkFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FalajForkPainter,
      );
      final painter =
          tester.widget<CustomPaint>(forkFinder).painter! as FalajForkPainter;
      expect(painter.textDirection, TextDirection.rtl);
    },
  );

  testWidgets(
    'settlement transfer arrow mirrors under RTL — no raw directional glyph '
    'is embedded in the direction-line text (#840)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: GroupSettlementTile(
                fromName: 'Sam',
                toName: 'Bob',
                amount: Decimal.parse('5.000'),
                currency: 'OMR',
                breakdown: const {},
                isYourAction: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // DirectionalIcon renders a Transform.scale(scaleX: -1) as a descendant
      // (not an ancestor) when RTL, so anchor on the underlying Icon glyph —
      // same pattern as module_header_rtl_test.dart's backArrowIsMirrored.
      final mirroredTransforms = tester
          .widgetList<Transform>(
            find.ancestor(
              of: find.byIcon(Iconsax.arrow_right_1),
              matching: find.byType(Transform),
            ),
          )
          .where((t) => t.transform.getRow(0).x == -1.0);

      expect(mirroredTransforms, isNotEmpty);
    },
  );

  group('#1066 — direction caption visual order follows the UI direction', () {
    testWidgets(
      'RTL with Latin names renders payer right of payee',
      (tester) async {
        await _pumpTile(
          tester,
          textDirection: TextDirection.rtl,
          fromName: 'Ahmed',
          toName: 'QA Bot',
        );

        final captionFinder = _captionFinder();
        expect(captionFinder, findsOneWidget);
        expect(
          _nameCenterX(tester, captionFinder, 'Ahmed'),
          greaterThan(_nameCenterX(tester, captionFinder, 'QA')),
        );

        final semanticsText = _captionSemanticsText(tester, captionFinder);
        expect(semanticsText, contains('Ahmed'));
        expect(semanticsText, contains('QA'));
        expect(semanticsText, isNot(contains('\u2068')));
        expect(semanticsText, isNot(contains('\u2069')));
      },
    );

    testWidgets(
      'RTL with Arabic names keeps payer right of payee without double-flipping',
      (tester) async {
        await _pumpTile(
          tester,
          textDirection: TextDirection.rtl,
          fromName: 'أحمد',
          toName: 'ليلى',
        );

        final captionFinder = _captionFinder();
        expect(captionFinder, findsOneWidget);
        expect(
          _nameCenterX(tester, captionFinder, 'أحمد'),
          greaterThan(_nameCenterX(tester, captionFinder, 'ليلى')),
        );
      },
    );

    testWidgets(
      'LTR with Latin names keeps payer left of payee',
      (tester) async {
        await _pumpTile(
          tester,
          textDirection: TextDirection.ltr,
          fromName: 'Ahmed',
          toName: 'QA Bot',
        );

        final captionFinder = _captionFinder();
        expect(captionFinder, findsOneWidget);
        expect(
          _nameCenterX(tester, captionFinder, 'Ahmed'),
          lessThan(_nameCenterX(tester, captionFinder, 'QA')),
        );
      },
    );

    testWidgets(
      'LTR with Arabic names keeps payer left of payee without reversal',
      (tester) async {
        await _pumpTile(
          tester,
          textDirection: TextDirection.ltr,
          fromName: 'أحمد',
          toName: 'ليلى',
        );

        final captionFinder = _captionFinder();
        expect(captionFinder, findsOneWidget);
        expect(
          _nameCenterX(tester, captionFinder, 'أحمد'),
          lessThan(_nameCenterX(tester, captionFinder, 'ليلى')),
        );
      },
    );
  });
}
