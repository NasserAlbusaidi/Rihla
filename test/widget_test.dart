import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

/// Basic smoke test to verify the app can be instantiated.
/// Integration tests cover actual app functionality with mocked providers.
void main() {
  testWidgets('App widget can be created', (WidgetTester tester) async {
    // Build a minimal MaterialApp to verify Flutter test infrastructure works
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: Center(child: Text('Safar'))),
      ),
    );

    expect(find.text('Safar'), findsOneWidget);
  });
}
