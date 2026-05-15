import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/settings/widgets/legal_links_sheet.dart';

void main() {
  // Stub the url_launcher platform channel so InkWell taps don't throw.
  const urlChannel = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <Map<dynamic, dynamic>>[];

  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  setUp(() {
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlChannel, (call) async {
      if (call.method == 'canLaunch' || call.method == 'launch') {
        launched.add(Map<dynamic, dynamic>.from(call.arguments as Map));
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlChannel, null);
  });

  Future<void> pumpWithSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => LegalLinksSheet.show(ctx),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders three legal rows with their labels', (tester) async {
    await pumpWithSheet(tester);

    expect(find.text('Legal'), findsOneWidget);
    expect(find.text('Terms of service'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Delete my data'), findsOneWidget);
  });

  testWidgets('tapping a row attempts to launch the URL and dismisses sheet',
      (tester) async {
    await pumpWithSheet(tester);

    await tester.tap(find.text('Terms of service'));
    await tester.pumpAndSettle();

    expect(launched, isNotEmpty);
    final args = launched.first;
    expect(args['url'], contains('terms'));

    // Sheet should be dismissed after launch.
    expect(find.text('Legal'), findsNothing);
  });

  testWidgets('tapping privacy row launches privacy URL', (tester) async {
    await pumpWithSheet(tester);

    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();

    expect(launched, isNotEmpty);
    expect(launched.first['url'], contains('privacy'));
  });

  testWidgets('tapping delete-data row launches delete-data URL',
      (tester) async {
    await pumpWithSheet(tester);

    await tester.tap(find.text('Delete my data'));
    await tester.pumpAndSettle();

    expect(launched, isNotEmpty);
    expect(launched.first['url'], contains('delete-data'));
  });
}
