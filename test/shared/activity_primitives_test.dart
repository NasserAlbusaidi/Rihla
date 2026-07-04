import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/activity_day_section.dart';
import 'package:safar/shared/widgets/activity_filter_strip.dart';
import 'package:safar/shared/widgets/activity_glyph.dart';
import 'package:safar/shared/widgets/activity_row.dart';
import 'package:safar/shared/widgets/caption_title_bar.dart';
import 'package:safar/shared/widgets/paper_backdrop.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('ActivityCategoryIcon', () {
    testWidgets('maps expenseAdded to the receipt_add icon', (tester) async {
      await _pump(
        tester,
        const ActivityCategoryIcon(glyph: ActivityGlyph.expenseAdded),
      );
      expect(find.byIcon(Iconsax.receipt_add), findsOneWidget);
    });

    testWidgets('maps settlement to the wallet_3 icon', (tester) async {
      await _pump(
        tester,
        const ActivityCategoryIcon(glyph: ActivityGlyph.settlement),
      );
      expect(find.byIcon(Iconsax.wallet_3), findsOneWidget);
    });

    testWidgets('maps generic to the activity icon', (tester) async {
      await _pump(
        tester,
        const ActivityCategoryIcon(glyph: ActivityGlyph.generic),
      );
      expect(find.byIcon(Iconsax.activity), findsOneWidget);
    });

    testWidgets('tile corner radius uses the radiusSmall token (8dp)', (
      tester,
    ) async {
      await _pump(
        tester,
        const ActivityCategoryIcon(glyph: ActivityGlyph.generic),
      );
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ActivityCategoryIcon),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      final radius = decoration.borderRadius! as BorderRadius;
      expect(radius.topLeft.x, 8);
    });

    testWidgets('settlement tile has no border', (tester) async {
      await _pump(
        tester,
        const ActivityCategoryIcon(glyph: ActivityGlyph.settlement),
      );
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ActivityCategoryIcon),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNull);
    });

    testWidgets('expenseEdited tile has a border', (tester) async {
      await _pump(
        tester,
        const ActivityCategoryIcon(glyph: ActivityGlyph.expenseEdited),
      );
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ActivityCategoryIcon),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
    });

    testWidgets('every glyph value maps to its expected icon', (
      tester,
    ) async {
      const expected = {
        ActivityGlyph.expenseAdded: Iconsax.receipt_add,
        ActivityGlyph.expenseEdited: Iconsax.receipt_edit,
        ActivityGlyph.expenseDeleted: Iconsax.receipt_minus,
        ActivityGlyph.settlement: Iconsax.wallet_3,
        ActivityGlyph.eventCreated: Iconsax.calendar_1,
        ActivityGlyph.eventDeleted: Iconsax.calendar_remove,
        ActivityGlyph.memberJoined: Iconsax.user_add,
        ActivityGlyph.memberLeft: Iconsax.user_minus,
        ActivityGlyph.generic: Iconsax.activity,
      };
      for (final entry in expected.entries) {
        await _pump(tester, ActivityCategoryIcon(glyph: entry.key));
        expect(
          find.byIcon(entry.value),
          findsOneWidget,
          reason: 'glyph ${entry.key} should render ${entry.value}',
        );
      }
    });
  });

  group('ActivityRow', () {
    testWidgets('renders actor and description as rich text', (
      tester,
    ) async {
      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseAdded,
          actorName: 'Alice',
          description: 'added Dinner',
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      );
      expect(find.textContaining('Alice', findRichText: true), findsOneWidget);
      expect(
        find.textContaining('added Dinner', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('renders group chip only when groupName is given', (
      tester,
    ) async {
      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseAdded,
          actorName: 'Alice',
          description: 'added Dinner',
          timestamp: DateTime.now(),
        ),
      );
      expect(find.text('Beach Trip'), findsNothing);

      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseAdded,
          actorName: 'Alice',
          description: 'added Dinner',
          timestamp: DateTime.now(),
          groupName: 'Beach Trip',
        ),
      );
      expect(find.text('Beach Trip'), findsOneWidget);
    });

    testWidgets('renders the trailingAmount slot when provided', (
      tester,
    ) async {
      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseAdded,
          actorName: 'Alice',
          description: 'added Dinner',
          timestamp: DateTime.now(),
          trailingAmount: const Text('OMR 12.500', key: ValueKey('amt')),
        ),
      );
      expect(find.byKey(const ValueKey('amt')), findsOneWidget);
    });

    testWidgets('muted wraps trailingAmount in Opacity(.6)', (tester) async {
      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseAdded,
          actorName: 'Alice',
          description: 'added Dinner',
          timestamp: DateTime.now(),
          muted: true,
          trailingAmount: const Text('OMR 12.500', key: ValueKey('amt')),
        ),
      );
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('amt')),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, 0.6);
    });

    testWidgets('renders the detail slot when provided', (tester) async {
      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseEdited,
          actorName: 'Bob',
          description: 'edited Dinner',
          timestamp: DateTime.now(),
          detail: const Text('was 12.000 → now 15.000', key: ValueKey('d')),
        ),
      );
      expect(find.byKey(const ValueKey('d')), findsOneWidget);
    });

    testWidgets('onTap fires when the row is tapped', (tester) async {
      var tapped = false;
      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseAdded,
          actorName: 'Alice',
          description: 'added Dinner',
          timestamp: DateTime.now(),
          onTap: () => tapped = true,
        ),
      );
      await tester.tap(find.byType(ActivityRow));
      expect(tapped, isTrue);
    });

    testWidgets('renders a divider hairline when divider is true', (
      tester,
    ) async {
      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseAdded,
          actorName: 'Alice',
          description: 'added Dinner',
          timestamp: DateTime.now(),
          divider: true,
        ),
      );
      final dividerContainers = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(ActivityRow),
              matching: find.byType(Container),
            ),
          )
          .where((c) => c.color != null);
      expect(dividerContainers, isNotEmpty);
    });

    testWidgets('omits the divider hairline when divider is false', (
      tester,
    ) async {
      await _pump(
        tester,
        ActivityRow(
          glyph: ActivityGlyph.expenseAdded,
          actorName: 'Alice',
          description: 'added Dinner',
          timestamp: DateTime.now(),
        ),
      );
      final dividerContainers = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(ActivityRow),
              matching: find.byType(Container),
            ),
          )
          .where((c) => c.color != null);
      expect(dividerContainers, isEmpty);
    });
  });

  group('ActivityDaySection', () {
    testWidgets('raised=true renders shadow without a border', (
      tester,
    ) async {
      await _pump(
        tester,
        const ActivityDaySection(label: 'today', children: [SizedBox()]),
      );
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ActivityDaySection),
              matching: find.byType(Container),
            )
            .last,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.boxShadow, isNotEmpty);
      expect(decoration.border, isNull);
    });

    testWidgets('raised=false renders a border without shadow', (
      tester,
    ) async {
      await _pump(
        tester,
        const ActivityDaySection(
          label: 'today',
          raised: false,
          children: [SizedBox()],
        ),
      );
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ActivityDaySection),
              matching: find.byType(Container),
            )
            .last,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
      expect(decoration.boxShadow, isNull);
    });

    testWidgets('header uppercases the label and dot-joins the dateSuffix', (
      tester,
    ) async {
      await _pump(
        tester,
        const ActivityDaySection(
          label: 'today',
          dateSuffix: 'jul 4',
          children: [SizedBox()],
        ),
      );
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text(' · JUL 4'), findsOneWidget);
    });

    testWidgets('header shows only the label when dateSuffix is null', (
      tester,
    ) async {
      await _pump(
        tester,
        const ActivityDaySection(label: 'today', children: [SizedBox()]),
      );
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);
    });

    testWidgets('card uses antiAlias clip behavior', (tester) async {
      await _pump(
        tester,
        const ActivityDaySection(label: 'today', children: [SizedBox()]),
      );
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ActivityDaySection),
              matching: find.byType(Container),
            )
            .last,
      );
      expect(container.clipBehavior, Clip.antiAlias);
    });
  });

  group('ActivityFilterStrip', () {
    testWidgets('active chip uses the ink fill; inactive uses cardSoft', (
      tester,
    ) async {
      await _pump(
        tester,
        ActivityFilterStrip<String>(
          options: const [
            ActivityFilterOption(
              value: 'all',
              label: 'All',
              key: ValueKey('chip-all'),
            ),
            ActivityFilterOption(
              value: 'events',
              label: 'Events',
              key: ValueKey('chip-events'),
            ),
          ],
          current: 'all',
          onChange: (_) {},
        ),
      );
      final colors = AppTheme.lightTheme.extension<AppColorTokens>()!;

      final activeContainer = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(const ValueKey('chip-all')),
              matching: find.byType(Container),
            )
            .first,
      );
      final activeDecoration = activeContainer.decoration! as BoxDecoration;
      expect(activeDecoration.color, colors.textPrimary);

      final inactiveContainer = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(const ValueKey('chip-events')),
              matching: find.byType(Container),
            )
            .first,
      );
      final inactiveDecoration =
          inactiveContainer.decoration! as BoxDecoration;
      expect(inactiveDecoration.color, colors.cardSoft);
    });

    testWidgets('re-tapping the active chip does not call onChange', (
      tester,
    ) async {
      var calls = 0;
      await _pump(
        tester,
        ActivityFilterStrip<String>(
          options: const [
            ActivityFilterOption(
              value: 'all',
              label: 'All',
              key: ValueKey('chip-all'),
            ),
          ],
          current: 'all',
          onChange: (_) => calls++,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('chip-all')));
      await tester.pump(const Duration(milliseconds: 150));
      expect(calls, 0);
    });

    testWidgets('tapping an inactive chip calls onChange with its value', (
      tester,
    ) async {
      String? changed;
      await _pump(
        tester,
        ActivityFilterStrip<String>(
          options: const [
            ActivityFilterOption(
              value: 'all',
              label: 'All',
              key: ValueKey('chip-all'),
            ),
            ActivityFilterOption(
              value: 'events',
              label: 'Events',
              key: ValueKey('chip-events'),
            ),
          ],
          current: 'all',
          onChange: (v) => changed = v,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('chip-events')));
      await tester.pump(const Duration(milliseconds: 150));
      expect(changed, 'events');
    });

    testWidgets('per-option keys land on the tappable chip', (tester) async {
      await _pump(
        tester,
        ActivityFilterStrip<String>(
          options: const [
            ActivityFilterOption(
              value: 'all',
              label: 'All',
              key: ValueKey('chip-all'),
            ),
          ],
          current: 'all',
          onChange: (_) {},
        ),
      );
      expect(find.byKey(const ValueKey('chip-all')), findsOneWidget);
    });
  });

  group('CaptionTitleBar', () {
    testWidgets('renders the caption and title text', (tester) async {
      await _pump(
        tester,
        const CaptionTitleBar(caption: 'ACTIVITY', title: 'Beach Trip'),
      );
      expect(find.text('ACTIVITY'), findsOneWidget);
      expect(find.text('Beach Trip'), findsOneWidget);
    });

    testWidgets('invokes onBack when the back button is tapped', (
      tester,
    ) async {
      var tapped = false;
      await _pump(
        tester,
        CaptionTitleBar(
          caption: 'ACTIVITY',
          title: 'Beach Trip',
          onBack: () => tapped = true,
          backKey: const ValueKey('back-btn'),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('back-btn')));
      expect(tapped, isTrue);
    });

    testWidgets('omits the back button entirely when onBack is null', (
      tester,
    ) async {
      await _pump(
        tester,
        const CaptionTitleBar(caption: 'ACTIVITY', title: 'Beach Trip'),
      );
      expect(find.byType(InkResponse), findsNothing);
    });

    testWidgets('applies titleKey to the title text', (tester) async {
      await _pump(
        tester,
        const CaptionTitleBar(
          caption: 'ACTIVITY',
          title: 'Beach Trip',
          titleKey: ValueKey('title'),
        ),
      );
      expect(find.byKey(const ValueKey('title')), findsOneWidget);
    });

    testWidgets('back button carries the localized back tooltip (a11y)', (
      tester,
    ) async {
      await _pump(
        tester,
        CaptionTitleBar(
          caption: 'ACTIVITY',
          title: 'Beach Trip',
          onBack: () {},
        ),
      );
      expect(find.byTooltip('Back'), findsOneWidget);
    });

    testWidgets('no tooltip is present when onBack is null', (tester) async {
      await _pump(
        tester,
        const CaptionTitleBar(caption: 'ACTIVITY', title: 'Beach Trip'),
      );
      expect(find.byTooltip('Back'), findsNothing);
    });
  });

  group('PaperBackdrop', () {
    testWidgets('renders the child content', (tester) async {
      await _pump(tester, const PaperBackdrop(child: Text('Hello')));
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('gradient runs from paperDeep to scaffoldBackground', (
      tester,
    ) async {
      await _pump(tester, const PaperBackdrop(child: SizedBox()));
      final decoratedBox = tester.widget<DecoratedBox>(
        find.byType(DecoratedBox).first,
      );
      final decoration = decoratedBox.decoration as BoxDecoration;
      final gradient = decoration.gradient! as LinearGradient;
      final colors = AppTheme.lightTheme.extension<AppColorTokens>()!;
      expect(gradient.colors, [colors.paperDeep, colors.scaffoldBackground]);
    });
  });
}
