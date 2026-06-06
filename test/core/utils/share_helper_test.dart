import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/share_helper.dart';

/// shareText must ALWAYS pass a non-zero sharePositionOrigin. iOS/iPadOS throw
/// `PlatformException(sharePositionOrigin: argument must be set)` on a zero
/// rect, which silently breaks every share path (the app's signature failure
/// mode for sharing). Android ignores the anchor, so this is iOS-only and the
/// mock-the-text tests can't catch it — assert the origin on the wire here.
void main() {
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

  Future<Map<Object?, Object?>?> tapShare(
    WidgetTester tester, {
    required String text,
    String? subject,
  }) async {
    Map<Object?, Object?>? args;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      shareChannel,
      (call) async {
        if (call.method == 'share') {
          args = call.arguments as Map<Object?, Object?>;
        }
        return '';
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        shareChannel,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => shareText(context, text, subject: subject),
                child: const Text('Share'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    return args;
  }

  testWidgets('shareText forwards a non-zero share origin', (tester) async {
    final args = await tapShare(
      tester,
      text: 'join https://example.test/join/X',
      subject: 'Invite',
    );

    expect(args, isNotNull);
    expect(args!['originWidth'], isA<double>());
    expect(args['originHeight'], isA<double>());
    expect((args['originWidth'] as double) > 0, isTrue);
    expect((args['originHeight'] as double) > 0, isTrue);
  });

  testWidgets('shareText forwards the text and subject', (tester) async {
    final args = await tapShare(tester, text: 'hello world', subject: 'Subj');

    expect(args!['text'], 'hello world');
    expect(args['subject'], 'Subj');
  });
}
