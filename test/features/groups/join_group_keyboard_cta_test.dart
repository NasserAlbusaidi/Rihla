import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/join_group_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Focusing the invite-code field opens the keyboard; the Join Group CTA below
// it must scroll into view above the keyboard, not sit half-hidden under it
// (emulator audit 2026-07-07, 07-join-code-focused.png). The default
// TextField scrollPadding (20) only keeps the *field* visible — the fields
// need a scrollPadding tall enough to reveal the hint card + CTA below.
// ---------------------------------------------------------------------------

void main() {
  const screen = Size(402, 874);
  const keyboardInset = 300.0;

  Future<Widget> buildJoinScreen() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        groupLoadingProvider.overrideWith((ref) => false),
        groupErrorProvider.overrideWith((ref) => null),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const JoinGroupScreen(),
      ),
    );
  }

  testWidgets('join CTA is fully visible above the keyboard when the '
      'invite-code field is focused', (tester) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildJoinScreen());
    await tester.pump();

    // Focus the invite-code field (the second TextFormField), then raise the
    // keyboard the way a device does: viewInsets change after focus.
    final codeField = find.byType(TextFormField).at(1);
    await tester.tap(codeField);
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: keyboardInset);
    tester.binding.handleMetricsChanged();
    // Let the caret-on-screen scroll animation run.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final button = find.byKey(GroupKeys.joinGroupButton);
    expect(button, findsOneWidget);
    final rect = tester.getRect(button);
    expect(
      rect.bottom,
      lessThanOrEqualTo(screen.height - keyboardInset + 0.5),
      reason:
          'Join Group CTA bottom ${rect.bottom} must clear the keyboard top '
          '${screen.height - keyboardInset} when the invite-code field is '
          'focused',
    );
  });
}
