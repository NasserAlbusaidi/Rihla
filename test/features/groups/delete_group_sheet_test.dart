import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/widgets/delete_group_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// #227 — direct coverage for the type-to-confirm gating on the destructive
// "Delete group" sheet. The host-screen test (group_settings_screen_test)
// only asserts the sheet OPENS; the gating logic (button stays disabled until
// the typed token matches the group name, cancel is a no-op) was untested.
void main() {
  Future<void> openSheet(
    WidgetTester tester, {
    required String groupName,
    int memberCount = 3,
    required VoidCallback onConfirm,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const Key('open'),
                onPressed: () => showDeleteGroupSheet(
                  context,
                  groupName: groupName,
                  memberCount: memberCount,
                  onConfirm: onConfirm,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  ElevatedButton confirmButton(WidgetTester tester) =>
      tester.widget<ElevatedButton>(
        find.byKey(GroupKeys.deleteGroupConfirmButton),
      );

  testWidgets('confirm stays disabled until the typed name matches', (
    tester,
  ) async {
    var confirmed = 0;
    await openSheet(tester, groupName: 'Trip Crew', onConfirm: () => confirmed++);

    expect(find.byKey(GroupKeys.deleteGroupDialog), findsOneWidget);
    // Empty input → disabled.
    expect(confirmButton(tester).onPressed, isNull);

    // Wrong token → still disabled.
    await tester.enterText(find.byType(TextField), 'wrong name');
    await tester.pump();
    expect(confirmButton(tester).onPressed, isNull);

    // Tapping the disabled button is a no-op (no accidental delete).
    await tester.tap(
      find.byKey(GroupKeys.deleteGroupConfirmButton),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(confirmed, 0);
  });

  testWidgets('matching name (case-insensitive, trimmed) enables confirm and '
      'fires onConfirm exactly once', (tester) async {
    var confirmed = 0;
    await openSheet(tester, groupName: 'Trip Crew', onConfirm: () => confirmed++);

    await tester.enterText(find.byType(TextField), '  trip crew  ');
    await tester.pump();
    expect(confirmButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(GroupKeys.deleteGroupConfirmButton));
    await tester.pumpAndSettle();

    expect(confirmed, 1);
    // Sheet dismissed itself before invoking the callback.
    expect(find.byKey(GroupKeys.deleteGroupDialog), findsNothing);
  });

  testWidgets('cancel dismisses the sheet without confirming', (tester) async {
    var confirmed = 0;
    await openSheet(tester, groupName: 'Trip Crew', onConfirm: () => confirmed++);

    // The cancel control is the only OutlinedButton in the sheet.
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    expect(confirmed, 0);
    expect(find.byKey(GroupKeys.deleteGroupDialog), findsNothing);
  });

  // #1041 Bundle 1 review fix — an explicit color on the label Text bypasses
  // the button's foregroundColor/disabledForegroundColor, so the disabled
  // label rendered full-strength textOnError (dark: ink) on the washed-out
  // 0.35-alpha error background — near-invisible in dark theme. The label
  // must inherit its color from the button style in BOTH states.
  group('confirm label color follows the button state', () {
    Color? effectiveLabelColor(WidgetTester tester) {
      final textFinder = find.descendant(
        of: find.byKey(GroupKeys.deleteGroupConfirmButton),
        matching: find.byType(Text),
      );
      final text = tester.widget<Text>(textFinder);
      return text.style?.color ??
          DefaultTextStyle.of(tester.element(textFinder)).style.color;
    }

    for (final (themeName, theme, tokens) in [
      ('light', AppTheme.lightTheme, AppColorTokens.light),
      ('dark', AppTheme.darkTheme, AppColorTokens.dark),
    ]) {
      testWidgets('$themeName: disabled label renders the resolved '
          'disabledForegroundColor, not textOnError', (tester) async {
        await openSheet(
          tester,
          groupName: 'Trip Crew',
          onConfirm: () {},
          theme: theme,
        );

        final btn = confirmButton(tester);
        expect(btn.onPressed, isNull);
        final disabledFg =
            btn.style?.foregroundColor?.resolve({WidgetState.disabled});
        expect(disabledFg, isNotNull);
        expect(effectiveLabelColor(tester), disabledFg,
            reason: 'disabled label must inherit disabledForegroundColor');
        expect(effectiveLabelColor(tester), isNot(tokens.textOnError),
            reason: 'full-strength textOnError is the ENABLED color; on the '
                '0.35-alpha disabled background it is unreadable in dark');
      });

      testWidgets('$themeName: enabled label renders textOnError', (
        tester,
      ) async {
        await openSheet(
          tester,
          groupName: 'Trip Crew',
          onConfirm: () {},
          theme: theme,
        );
        await tester.enterText(find.byType(TextField), 'Trip Crew');
        // Settle: the button's Material animates its text style over
        // ~200ms on the disabled→enabled flip; sample the rest state.
        await tester.pumpAndSettle();

        expect(confirmButton(tester).onPressed, isNotNull);
        expect(effectiveLabelColor(tester), tokens.textOnError);
      });
    }
  });

  // The disabled foreground must actually read on the disabled surface: the
  // 0.35-alpha error wash composited over the sheet background (the sheet is
  // scaffoldBackground). WCAG exempts disabled controls, so 4.5 here is a
  // self-imposed floor — but the whole point of the type-to-confirm pattern
  // is that the user READS the disabled button.
  group('disabled foreground reads on the blended disabled background', () {
    double lin(double c) => c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    double luminance(Color c) =>
        0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
    double contrast(Color a, Color b) {
      final la = luminance(a);
      final lb = luminance(b);
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    for (final (themeName, tokens) in [
      ('light', AppColorTokens.light),
      ('dark', AppColorTokens.dark),
    ]) {
      test('$themeName >= 4.5:1', () {
        final disabledBg = Color.alphaBlend(
          tokens.error.withValues(alpha: 0.35),
          tokens.scaffoldBackground,
        );
        final disabledFg = Color.alphaBlend(
          tokens.textPrimary.withValues(alpha: 0.8),
          disabledBg,
        );
        final r = contrast(disabledFg, disabledBg);
        expect(r, greaterThanOrEqualTo(4.5),
            reason: 'disabled label ($themeName) = ${r.toStringAsFixed(2)}:1');
      });
    }
  });
}
