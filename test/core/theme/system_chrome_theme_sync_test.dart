import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/models/app_settings_model.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/settings_service.dart';
import 'package:safar/core/theme/system_chrome_theme_sync.dart';

/// Pumps [SystemChromeThemeSync] for [mode] and returns the arguments of the
/// last `SystemChrome.setSystemUIOverlayStyle` platform call it pushed.
Future<Map<Object?, Object?>> _pumpAndCaptureOverlay(
  WidgetTester tester, {
  required AppThemeMode mode,
  Brightness platformBrightness = Brightness.light,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final service = SettingsService(prefs);
  await service.saveThemeMode(mode);

  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
        calls.add(call);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsServiceProvider.overrideWithValue(service)],
      child: MediaQuery(
        data: MediaQueryData(platformBrightness: platformBrightness),
        child: const SystemChromeThemeSync(
          child: SizedBox(key: Key('sync-child')),
        ),
      ),
    ),
  );
  // Flush the widget's post-frame callback, then SystemChrome's own deferred
  // platform dispatch.
  await tester.pump();
  await tester.pump();

  expect(
    calls,
    isNotEmpty,
    reason: 'SystemChromeThemeSync did not push an overlay style',
  );
  return (calls.last.arguments as Map).cast<Object?, Object?>();
}

void main() {
  testWidgets('renders its child', (tester) async {
    await _pumpAndCaptureOverlay(tester, mode: AppThemeMode.light);
    expect(find.byKey(const Key('sync-child')), findsOneWidget);
  });

  testWidgets(
      'dark theme sets the iOS + Android dark-background overlay (#1051)',
      (tester) async {
    final args = await _pumpAndCaptureOverlay(tester, mode: AppThemeMode.dark);
    // #1051 regression: the iOS field (statusBarBrightness) must be present and
    // correct — it was absent before the fix, leaving iOS glyphs stale.
    expect(args['statusBarBrightness'], 'Brightness.dark');
    expect(args['statusBarIconBrightness'], 'Brightness.light');
  });

  testWidgets(
      'light theme sets the iOS + Android light-background overlay (#1051)',
      (tester) async {
    final args = await _pumpAndCaptureOverlay(tester, mode: AppThemeMode.light);
    expect(args['statusBarBrightness'], 'Brightness.light');
    expect(args['statusBarIconBrightness'], 'Brightness.dark');
  });

  testWidgets('system mode resolves against platform brightness',
      (tester) async {
    final args = await _pumpAndCaptureOverlay(
      tester,
      mode: AppThemeMode.system,
      platformBrightness: Brightness.dark,
    );
    expect(args['statusBarBrightness'], 'Brightness.dark');
  });
}
