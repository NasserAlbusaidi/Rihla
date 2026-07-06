import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';

/// The launcher icon plate must sit on the same ground as the app. The Falaj
/// token swap moved the scaffold to plaster but the icon pipeline lagged on
/// the retired travel-journal cream (#935): `flutter_launcher_icons.yaml`
/// `adaptive_icon_background` and the generated `ic_launcher_background`
/// resource both stayed #F6F1E6. This guard pins both to the light scaffold
/// token so the icon plate can never drift from the brand ground again.
String _hex(Color c) {
  int ch(double v) => (v * 255).round();
  String h(int v) => v.toRadixString(16).padLeft(2, '0');
  return '#${h(ch(c.r))}${h(ch(c.g))}${h(ch(c.b))}'.toUpperCase();
}

void main() {
  final plaster = _hex(AppColorTokens.light.scaffoldBackground);

  test('flutter_launcher_icons adaptive background matches the Falaj ground',
      () {
    final yaml = File('flutter_launcher_icons.yaml').readAsStringSync();
    final match = RegExp(
      r'adaptive_icon_background:\s*"(#[0-9A-Fa-f]{6})"',
    ).firstMatch(yaml);
    expect(match, isNotNull,
        reason: 'adaptive_icon_background missing from '
            'flutter_launcher_icons.yaml');
    expect(
      match!.group(1)!.toUpperCase(),
      plaster,
      reason: 'The adaptive icon plate must equal the light scaffold ground; '
          'a mismatch ships the retired identity behind the mark (#935).',
    );
  });

  test('generated ic_launcher_background matches the Falaj ground', () {
    final xml = File('android/app/src/main/res/values/colors.xml')
        .readAsStringSync();
    final match = RegExp(
      r'<color name="ic_launcher_background">(#[0-9A-Fa-f]{6})</color>',
    ).firstMatch(xml);
    expect(match, isNotNull,
        reason: 'ic_launcher_background missing from values/colors.xml');
    expect(
      match!.group(1)!.toUpperCase(),
      plaster,
      reason: 'The generated launcher background must equal the light '
          'scaffold ground; regenerate via dart run flutter_launcher_icons '
          'after editing flutter_launcher_icons.yaml (#935).',
    );
  });
}
