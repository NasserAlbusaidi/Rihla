import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings_model.dart';
import '../providers/settings_provider.dart';
import 'system_ui_overlay_style.dart';

/// Keeps the OS status-bar + navigation-bar overlay in sync with the active
/// app theme (resolves `AppThemeMode.system` against the platform brightness).
///
/// Inserted inside `SafarApp.build` AFTER `settingsProvider` is read so a theme
/// change — or a live system appearance switch — triggers a rebuild that
/// re-applies the overlay. Delegates to [systemUiOverlayStyleForBrightness],
/// which sets BOTH the Android (`statusBarIconBrightness`) and iOS
/// (`statusBarBrightness`) fields; setting only the former left iOS status-bar
/// glyphs stale on a live switch (#1051).
class SystemChromeThemeSync extends ConsumerWidget {
  const SystemChromeThemeSync({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final platform = MediaQuery.platformBrightnessOf(context);
    final effective = switch (mode) {
      AppThemeMode.light => Brightness.light,
      AppThemeMode.dark => Brightness.dark,
      AppThemeMode.system => platform,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setSystemUIOverlayStyle(
        systemUiOverlayStyleForBrightness(effective),
      );
    });
    return child;
  }
}
