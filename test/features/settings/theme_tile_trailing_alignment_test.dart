// #1194: the Profile → PREFERENCES → Theme tile's Row rendered the same
// Expanded(label)-vs-Flexible(value) 50/50 defect fixed for the other rows in
// #1184 (`pref_row_trailing_alignment_test.dart`) — but this file
// (`profile_display_section.dart`) was NOT touched by that commit.
//
// The value Text is wrapped in a bare `Flexible` (flex:1, loose) competing
// 50/50 with the `Expanded(label)` (flex:1). The loose Flexible sizes to the
// short value's natural width and is positioned right after the label's
// half — i.e. the row centre, not the trailing edge. Worse: because the
// trailing `DirectionalIcon` chevron is a non-flex child laid out AFTER the
// Flexible in the children list, its position is derived from the
// Flexible's *actual* (shrunk-to-text) render width rather than its
// *allocated* half-share — so the chevron itself gets pulled inward, leaving
// dead space between the chevron and the card's trailing edge.
//
// This is masked at the default value "System • Following device" (long
// enough to nearly fill its half-share) and only exposed by the short
// "Light"/"Dark" values — so this test pins the tile to `AppThemeMode.light`
// (`settings_theme` SharedPreferences index 0, see `SettingsService`) rather
// than relying on the default.
//
// These tests measure geometry (position, not existence): both the value
// text's trailing edge (immediately before the chevron's gap) and the
// chevron's trailing edge (against the row's trailing edge) must sit within
// a couple px of their expected trailing position, in both LTR (right edge)
// and RTL (left edge, proving the AlignmentDirectional mirror).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/features/settings/widgets/profile_display_section.dart';
import 'package:safar/shared/widgets/directional_icon.dart';

import '../../helpers/pump_rihla_app.dart';

void main() {
  // AppThemeMode.light == index 0 (`enum AppThemeMode { light, dark, system }`
  // in app_settings_model.dart); `SettingsService` persists it under the
  // `settings_theme` SharedPreferences key.
  const lightThemeIndex = 0;
  const chevronGap = 8.0; // context.spacing.space8, between value and chevron

  testWidgets(
    'LTR: Theme tile value + chevron hug the row trailing (right) edge with '
    'a short value (#1194)',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings_theme': lightThemeIndex,
      });

      await pumpRihlaApp(
        tester,
        const Scaffold(body: ProfileDisplaySection()),
      );

      final valueFinder = find.text('Light');
      final chevronFinder = find.byType(DirectionalIcon);
      final rowFinder = find
          .ancestor(of: valueFinder, matching: find.byType(Row))
          .first;

      final valueRect = tester.getRect(valueFinder);
      final chevronRect = tester.getRect(chevronFinder);
      final rowRect = tester.getRect(rowFinder);

      // The chevron must hug the row's trailing (right) edge — no dead
      // space pulled in by the shrunk-to-text Flexible sibling.
      expect(
        chevronRect.right,
        closeTo(rowRect.right, 1.5),
        reason:
            'chevron right=${chevronRect.right} vs row right=${rowRect.right}'
            ' — the chevron is not hugging the row trailing edge',
      );

      // The value text must sit immediately before the chevron's gap, not
      // shrink-wrapped at the row's horizontal centre.
      expect(
        valueRect.right,
        closeTo(chevronRect.left - chevronGap, 1.5),
        reason:
            'value right=${valueRect.right} vs expected '
            '${chevronRect.left - chevronGap} (chevron left - $chevronGap) — '
            'the value is not pinned to the trailing edge',
      );
    },
  );

  testWidgets(
    'RTL: Theme tile value + chevron hug the row trailing (left) edge with '
    'a short value (#1194)',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings_theme': lightThemeIndex,
      });

      await pumpRihlaApp(
        tester,
        const Scaffold(body: ProfileDisplaySection()),
        locale: const Locale('ar'),
      );

      final valueFinder = find.text('فاتح');
      final chevronFinder = find.byType(DirectionalIcon);
      final rowFinder = find
          .ancestor(of: valueFinder, matching: find.byType(Row))
          .first;

      final valueRect = tester.getRect(valueFinder);
      final chevronRect = tester.getRect(chevronFinder);
      final rowRect = tester.getRect(rowFinder);

      // Trailing edge in RTL is the left edge (AlignmentDirectional mirror).
      expect(
        chevronRect.left,
        closeTo(rowRect.left, 1.5),
        reason:
            'chevron left=${chevronRect.left} vs row left=${rowRect.left} — '
            'the chevron did not mirror to the RTL trailing edge',
      );

      expect(
        valueRect.left,
        closeTo(chevronRect.right + chevronGap, 1.5),
        reason:
            'value left=${valueRect.left} vs expected '
            '${chevronRect.right + chevronGap} (chevron right + $chevronGap)'
            ' — the value did not mirror to the RTL trailing edge',
      );
    },
  );
}
