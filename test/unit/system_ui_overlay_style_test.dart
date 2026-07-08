import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/system_ui_overlay_style.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';

void main() {
  group('systemUiOverlayStyleForBrightness', () {
    test('light app background uses dark overlays on Android and iOS', () {
      final style = systemUiOverlayStyleForBrightness(Brightness.light);

      expect(style.statusBarColor, Colors.transparent);
      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(style.statusBarBrightness, Brightness.light);
      expect(
        style.systemNavigationBarColor,
        AppColorTokens.light.scaffoldBackground,
      );
      expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    });

    test('dark app background uses light overlays on Android and iOS', () {
      final style = systemUiOverlayStyleForBrightness(Brightness.dark);

      expect(style.statusBarColor, Colors.transparent);
      expect(style.statusBarIconBrightness, Brightness.light);
      expect(style.statusBarBrightness, Brightness.dark);
      expect(
        style.systemNavigationBarColor,
        AppColorTokens.dark.scaffoldBackground,
      );
      expect(style.systemNavigationBarIconBrightness, Brightness.light);
    });

    test('matches Flutter platform semantics for status bar brightness', () {
      expect(
        systemUiOverlayStyleForBrightness(Brightness.dark).statusBarBrightness,
        SystemUiOverlayStyle.light.statusBarBrightness,
      );
      expect(
        systemUiOverlayStyleForBrightness(Brightness.light).statusBarBrightness,
        SystemUiOverlayStyle.dark.statusBarBrightness,
      );
    });
  });
}
