import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/extensions/build_context_l10n.dart';

import 'pump_rihla_app.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('pumpRihlaApp defaults to English locale', (tester) async {
    String captured = '';
    await pumpRihlaApp(
      tester,
      Builder(
        builder: (context) {
          captured = context.l10n.offlineBannerMessage;
          return const SizedBox.shrink();
        },
      ),
    );
    expect(captured, "You're offline — changes will sync later");
  });

  testWidgets('pumpRihlaApp honors explicit locale override', (tester) async {
    String captured = '';
    await pumpRihlaApp(
      tester,
      Builder(
        builder: (context) {
          captured = context.l10n.offlineBannerMessage;
          return const SizedBox.shrink();
        },
      ),
      locale: const Locale('ar'),
    );
    expect(captured, 'أنت غير متصل — ستتم مزامنة التغييرات لاحقًا');
  });
}
