import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';

// WCAG 2.x relative luminance. Flutter's Color exposes .r/.g/.b as normalized
// doubles (0..1); linearization + luminance weights operate directly on those.
double _lin(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

// HSV hue angle in degrees (0..360). Scale-invariant, so 0..1 channels yield
// the same angle as 8-bit channels.
double _hue(Color c) {
  final r = c.r, g = c.g, b = c.b;
  final mx = math.max(r, math.max(g, b));
  final mn = math.min(r, math.min(g, b));
  final d = mx - mn;
  if (d == 0) return 0;
  double h;
  if (mx == r) {
    h = ((g - b) / d) % 6;
  } else if (mx == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  h *= 60;
  return h < 0 ? h + 360 : h;
}

class _Pair {
  const _Pair(this.kind, this.theme, this.name, this.fg, this.bg, this.min);
  final String kind; // clean | success | warning | error
  final String theme; // light | dark
  final String name;
  final Color fg;
  final Color bg;
  final double min;
}

void main() {
  const l = AppColorTokens.light;
  const d = AppColorTokens.dark;

  final pairs = <_Pair>[
    // clean: body + on-primary text
    _Pair('clean', 'light', 'textPrimary on scaffold', l.textPrimary, l.scaffoldBackground, 4.5),
    _Pair('clean', 'light', 'textPrimary on card', l.textPrimary, l.cardSurface, 4.5),
    _Pair('clean', 'light', 'textSecondary on scaffold', l.textSecondary, l.scaffoldBackground, 4.5),
    _Pair('clean', 'light', 'textSecondary on card', l.textSecondary, l.cardSurface, 4.5),
    _Pair(
      'clean',
      'light',
      'bottomNavInactiveIcon on bottomNavBackground',
      l.bottomNavInactiveIcon,
      l.bottomNavBackground,
      4.5,
    ),
    _Pair('clean', 'light', 'textOnPrimary on primary', l.textOnPrimary, l.primary, 4.5),
    _Pair('clean', 'dark', 'textPrimary on scaffold', d.textPrimary, d.scaffoldBackground, 4.5),
    _Pair('clean', 'dark', 'textPrimary on card', d.textPrimary, d.cardSurface, 4.5),
    _Pair('clean', 'dark', 'textSecondary on scaffold', d.textSecondary, d.scaffoldBackground, 4.5),
    _Pair('clean', 'dark', 'textSecondary on card', d.textSecondary, d.cardSurface, 4.5),
    _Pair(
      'clean',
      'dark',
      'bottomNavInactiveIcon on bottomNavBackground',
      d.bottomNavInactiveIcon,
      d.bottomNavBackground,
      4.5,
    ),
    _Pair('clean', 'dark', 'textOnPrimary on primary', d.textOnPrimary, d.primary, 4.5),
    // success: positive ledger text
    _Pair('success', 'light', 'successText on scaffold', l.successText, l.scaffoldBackground, 4.5),
    _Pair('success', 'light', 'successText on card', l.successText, l.cardSurface, 4.5),
    _Pair('success', 'dark', 'successText on scaffold', d.successText, d.scaffoldBackground, 4.5),
    _Pair('success', 'dark', 'successText on card', d.successText, d.cardSurface, 4.5),
    // warning: offline/caution text
    _Pair('warning', 'light', 'warning-as-text on scaffold', l.warning, l.scaffoldBackground, 4.5),
    _Pair('warning', 'dark', 'warning-as-text on scaffold', d.warning, d.scaffoldBackground, 4.5),
    // error: negative ledger text
    _Pair('error', 'light', 'errorText on scaffold', l.errorText, l.scaffoldBackground, 4.5),
    _Pair('error', 'light', 'errorText on card', l.errorText, l.cardSurface, 4.5),
    _Pair('error', 'dark', 'errorText on scaffold', d.errorText, d.scaffoldBackground, 4.5),
    _Pair('error', 'dark', 'errorText on card', d.errorText, d.cardSurface, 4.5),
    _Pair('error', 'light', 'textOnError on error', l.textOnError, l.error, 4.5),
    _Pair('error', 'dark', 'textOnError on error', d.textOnError, d.error, 4.5),
  ];

  group('WCAG contrast — Falaj palette', () {
    for (final p in pairs) {
      test('${p.kind} · ${p.theme} · ${p.name} >= ${p.min}', () {
        final r = _contrast(p.fg, p.bg);
        expect(r, greaterThanOrEqualTo(p.min),
            reason: '${p.name} (${p.theme}) = ${r.toStringAsFixed(2)}:1, need ${p.min}:1');
      });
    }
  });

  group('warning is re-hued off brass primary (no amber collision)', () {
    // Spec guard: deltaH must exceed 20deg. Measured Falaj: 20.9deg light /
    // 21.5deg dark (~1deg margin — see PR body). Saffron era was 9deg, so this
    // is the RED driver before the swap. Inequality is a secondary guard only.
    const minHueSeparation = 20.0;
    test('light: warning vs primary hue separation > 20deg', () {
      final delta = (_hue(l.warning) - _hue(l.primary)).abs();
      expect(delta, greaterThan(minHueSeparation),
          reason: 'deltaH = ${delta.toStringAsFixed(1)}deg');
      expect(l.warning.toARGB32(), isNot(equals(l.primary.toARGB32())));
    });
    test('dark: warning vs primary hue separation > 20deg', () {
      final delta = (_hue(d.warning) - _hue(d.primary)).abs();
      expect(delta, greaterThan(minHueSeparation),
          reason: 'deltaH = ${delta.toStringAsFixed(1)}deg');
      expect(d.warning.toARGB32(), isNot(equals(d.primary.toARGB32())));
    });
  });
}
