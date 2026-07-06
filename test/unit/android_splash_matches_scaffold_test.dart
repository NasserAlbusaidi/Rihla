import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';

/// #361 contract: the Android cold-launch window background must equal the
/// scaffold ground, so the first frame on every launch is seamless with the
/// app. The Falaj token swap remapped the scaffold to plaster/kohl but the
/// native `splash_background` lagged on the retired travel-journal cream/brown
/// (#955) — nothing enforced the tie, so it drifted silently. This guard pins
/// the two together permanently.
String _hex(Color c) {
  int ch(double v) => (v * 255).round();
  String h(int v) => v.toRadixString(16).padLeft(2, '0');
  return '#${h(ch(c.r))}${h(ch(c.g))}${h(ch(c.b))}'.toUpperCase();
}

String _splashBackground(String path) {
  final xml = File(path).readAsStringSync();
  final match = RegExp(
    r'<color name="splash_background">(#[0-9A-Fa-f]{6})</color>',
  ).firstMatch(xml);
  expect(match, isNotNull, reason: 'splash_background missing from $path');
  return match!.group(1)!.toUpperCase();
}

void main() {
  test('Android light splash window bg matches the Falaj scaffold ground', () {
    expect(
      _splashBackground('android/app/src/main/res/values/colors.xml'),
      _hex(AppColorTokens.light.scaffoldBackground),
      reason:
          'The launch window background must equal the light scaffold ground '
          '(#361); a mismatch flashes the old identity on cold start (#955).',
    );
  });

  test('Android dark splash window bg matches the Falaj kohl scaffold', () {
    expect(
      _splashBackground('android/app/src/main/res/values-night/colors.xml'),
      _hex(AppColorTokens.dark.scaffoldBackground),
      reason:
          'The dark launch window background must equal the dark scaffold '
          'ground (#361); a mismatch flashes the old identity on cold start.',
    );
  });
}
