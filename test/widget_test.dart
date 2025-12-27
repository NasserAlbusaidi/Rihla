import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:safar/main.dart';

void main() {
  testWidgets('App starts and shows loading', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: SafarApp()));

    // Verify app starts (may show loading or login depending on state)
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
