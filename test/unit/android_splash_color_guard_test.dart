import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';

/// #955 — guard: the Android cold-launch splash window must match the live
/// Falaj scaffold tokens in both themes.
///
/// `splash_background` in `values/colors.xml` / `values-night/colors.xml`
/// paints the first frame before Flutter boots. It is a hardcoded copy of the
/// scaffold background, so a design-token swap (like the Falaj rebrand) that
/// only touches `color_tokens.dart` leaves the native splash on the OLD
/// palette — a visible flash from stale-cream/brown to the new scaffold on
/// every cold launch.
///
/// This test FAILS if either XML value drifts from
/// `AppColorTokens.light/dark.scaffoldBackground`.
String _splashHex(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');

  final match = RegExp(
    '<color name="splash_background">(#[0-9A-Fa-f]{6})</color>',
  ).firstMatch(file.readAsStringSync());
  expect(match, isNotNull, reason: '$path has no splash_background color');

  return match!.group(1)!.toUpperCase();
}

String _tokenHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

void main() {
  test('light splash_background matches the light scaffold token (#955)', () {
    expect(
      _splashHex('android/app/src/main/res/values/colors.xml'),
      _tokenHex(AppColorTokens.light.scaffoldBackground),
      reason:
          'values/colors.xml splash_background must equal '
          'AppColorTokens.light.scaffoldBackground — the native splash is the '
          'first frame and must not flash a stale palette on cold launch.',
    );
  });

  test('dark splash_background matches the dark scaffold token (#955)', () {
    expect(
      _splashHex('android/app/src/main/res/values-night/colors.xml'),
      _tokenHex(AppColorTokens.dark.scaffoldBackground),
      reason:
          'values-night/colors.xml splash_background must equal '
          'AppColorTokens.dark.scaffoldBackground — the native splash is the '
          'first frame and must not flash a stale palette on cold launch.',
    );
  });
}
