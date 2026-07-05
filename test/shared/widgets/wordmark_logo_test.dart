import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/shared/widgets/falaj_fork.dart';
import 'package:safar/shared/widgets/wordmark_logo.dart';

import '../../helpers/pump_rihla_app.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('WordmarkLogo renders "Rihla" in en locale', (tester) async {
    await pumpRihlaApp(tester, const WordmarkLogo());
    expect(find.text('Rihla'), findsOneWidget);
    expect(find.text('رحلة'), findsNothing);
  });

  testWidgets('WordmarkLogo renders "رحلة" in ar locale', (tester) async {
    await pumpRihlaApp(
      tester,
      const WordmarkLogo(),
      locale: const Locale('ar'),
    );
    expect(find.text('رحلة'), findsOneWidget);
    expect(find.text('Rihla'), findsNothing);
  });

  testWidgets('WordmarkLogo renders the FalajFork underscore (not the '
      'retired flourish)', (tester) async {
    await pumpRihlaApp(tester, const WordmarkLogo());
    expect(find.byType(FalajFork), findsOneWidget);
  });
}
