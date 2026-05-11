import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';

import 'shared_test_contrast_helpers.dart';

/// WCAG AA contrast assertions for [AppColorTokens.dark] (Phase 37 Wave 5).
///
/// Uses the shared `contrastRatio` helper extracted from `design_tokens_test.dart`
/// so both suites share an identical algorithm. The regression watch is:
///
/// - Every documented (text, background) pair in the dark palette must meet
///   WCAG AA (4.5:1 for normal text, 3.0:1 for large text / UI elements).
/// - `textMuted` is deliberately kept below AA per D-11 (decorative-only).
///   A dedicated test asserts this contract so that any palette change that
///   accidentally promotes `textMuted` to functional contrast surfaces as
///   a failure here first.
void main() {
  const dark = AppColorTokens.dark;
  const light = AppColorTokens.light;

  group('Dark theme WCAG AA', () {
    final pairs = <({String name, Color fg, Color bg, double min})>[
      (
        name: 'textPrimary on scaffold',
        fg: dark.textPrimary,
        bg: dark.scaffoldBackground,
        min: 4.5,
      ),
      (
        name: 'textPrimary on cardSurface',
        fg: dark.textPrimary,
        bg: dark.cardSurface,
        min: 4.5,
      ),
      (
        name: 'textSecondary on scaffold',
        fg: dark.textSecondary,
        bg: dark.scaffoldBackground,
        min: 4.5,
      ),
      (
        name: 'textSecondary on cardSurface',
        fg: dark.textSecondary,
        bg: dark.cardSurface,
        min: 4.5,
      ),
      (
        name: 'primary on scaffold',
        fg: dark.primary,
        bg: dark.scaffoldBackground,
        min: 3.0,
      ),
      (
        name: 'successText on scaffold',
        fg: dark.successText,
        bg: dark.scaffoldBackground,
        min: 4.5,
      ),
      (
        name: 'errorText on scaffold',
        fg: dark.errorText,
        bg: dark.scaffoldBackground,
        min: 4.5,
      ),
      (
        name: 'textOnPrimary on primary',
        fg: dark.textOnPrimary,
        bg: dark.primary,
        min: 4.5,
      ),
    ];

    for (final p in pairs) {
      test(p.name, () {
        final ratio = contrastRatio(p.fg, p.bg);
        expect(
          ratio,
          greaterThanOrEqualTo(p.min),
          reason: '${p.name}: ${ratio.toStringAsFixed(2)}:1 < ${p.min}:1',
        );
      });
    }

    test(
      'textMuted stays decorative-only even when dark-mode ratio is accessible',
      () {
        // D-11 classifies textMuted as decorative-only. The CI guard enforces
        // the `// textMuted-decorative-justified:` comment at every call site
        // regardless of ratio.
        //
        // In the LIGHT palette textMuted is #9CA3AF on white (2.86:1) — genuinely
        // below AA.
        // In the DARK palette Slate 400 on Slate 900 incidentally clears AA at
        // ~6.96:1. That accessibility bonus is a property of the dark palette's
        // scaffold choice, not a redesignation of the token's role.
        //
        // This test encodes the contract: the LIGHT textMuted stays below AA
        // (so the decorative-only classification is grounded). If the ratio
        // ever flips above 4.5 there, retire D-11 — don't silence the test.
        final lightRatio = contrastRatio(
          light.textMuted,
          light.scaffoldBackground,
        );
        expect(
          lightRatio,
          lessThan(4.5),
          reason:
              'LIGHT textMuted (${lightRatio.toStringAsFixed(2)}:1) must stay '
              'below AA — this is what grounds the decorative-only rule. '
              'If it flipped above AA, remove D-11 and the CI guard instead '
              'of weakening the test.',
        );
      },
    );
  });

  // Functional text roles (bodySmall/labelSmall) must stay WCAG AA in BOTH
  // brightnesses — Phase 37 B4 correction routed these roles to textSecondary.
  group(
    'Functional text roles (bodySmall/labelSmall) WCAG AA in BOTH themes',
    () {
      test('light: textSecondary on scaffoldBackground >= 4.5:1', () {
        final ratio = contrastRatio(
          light.textSecondary,
          light.scaffoldBackground,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason:
              'B4: bodySmall/labelSmall uses textSecondary on scaffold in '
              'light theme; ratio was ${ratio.toStringAsFixed(2)}:1',
        );
      });

      test('dark: textSecondary on scaffoldBackground >= 4.5:1', () {
        final ratio = contrastRatio(
          dark.textSecondary,
          dark.scaffoldBackground,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason:
              'B4: bodySmall/labelSmall uses textSecondary on scaffold in '
              'dark theme; ratio was ${ratio.toStringAsFixed(2)}:1',
        );
      });
    },
  );
}
