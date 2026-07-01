import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:safar/core/utils/share_helper.dart';

/// Returns the host temp dir so `XFile.fromData` (via `share_plus`) can write
/// the in-memory PNG without a real platform `path_provider` plugin.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

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

  // ── shareImage: the PNG-share chokepoint (recap card #722). ──────────────
  // Uses method `shareFiles` (not `share`). The same non-zero-origin invariant
  // applies — assert it on the wire, plus the png mime + overridden file name.

  Future<Map<Object?, Object?>?> tapShareImage(
    WidgetTester tester, {
    String? text,
  }) async {
    PathProviderPlatform.instance = _FakePathProvider();

    Map<Object?, Object?>? args;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      shareChannel,
      (call) async {
        if (call.method == 'shareFiles') {
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

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox(width: 200, height: 100);
            },
          ),
        ),
      ),
    );

    // A tiny but non-empty payload; share_plus writes it to a temp file.
    final bytes = Uint8List.fromList(List<int>.generate(16, (i) => i));
    // share_plus performs REAL file I/O (temp-file write) before invoking the
    // channel — that completes only on the real event loop, so drive it under
    // runAsync, not the default FakeAsync zone (else the channel never fires).
    await tester.runAsync(() => shareImage(ctx, bytes, text: text));
    return args;
  }

  testWidgets('shareImage forwards a non-zero share origin', (tester) async {
    final args = await tapShareImage(tester);

    expect(args, isNotNull);
    expect((args!['originWidth'] as double) > 0, isTrue);
    expect((args['originHeight'] as double) > 0, isTrue);
  });

  testWidgets('shareImage shares a png named rihla_recap.png with caption',
      (tester) async {
    final args = await tapShareImage(tester, text: 'Our trip recap');

    final paths = (args!['paths'] as List).cast<String>();
    final mimeTypes = (args['mimeTypes'] as List).cast<String>();
    expect(paths.single, endsWith('rihla_recap.png'));
    expect(mimeTypes.single, 'image/png');
    expect(args['text'], 'Our trip recap');
  });

  // ── shareCsv: the Trip Receipt CSV chokepoint (#704). Same shareFiles wire +
  // non-zero-origin invariant; text/csv mime + .csv name. ──────────────────

  Future<Map<Object?, Object?>?> tapShareCsv(WidgetTester tester) async {
    PathProviderPlatform.instance = _FakePathProvider();

    Map<Object?, Object?>? args;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      shareChannel,
      (call) async {
        if (call.method == 'shareFiles') {
          args = call.arguments as Map<Object?, Object?>;
        }
        return '';
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, null),
    );

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox(width: 200, height: 100);
            },
          ),
        ),
      ),
    );

    await tester.runAsync(() => shareCsv(ctx, 'Event,Camp\nAmount,12.500\n'));
    return args;
  }

  testWidgets('shareCsv forwards a non-zero share origin', (tester) async {
    final args = await tapShareCsv(tester);
    expect(args, isNotNull);
    expect((args!['originWidth'] as double) > 0, isTrue);
    expect((args['originHeight'] as double) > 0, isTrue);
  });

  testWidgets('shareCsv shares a text/csv file named rihla_trip_receipt.csv',
      (tester) async {
    final args = await tapShareCsv(tester);
    final paths = (args!['paths'] as List).cast<String>();
    final mimeTypes = (args['mimeTypes'] as List).cast<String>();
    expect(paths.single, endsWith('rihla_trip_receipt.csv'));
    expect(mimeTypes.single, 'text/csv');
  });

  // ── sharePdf: the Trip Receipt PDF chokepoint (#704 Slice B). Same shareFiles
  // wire + non-zero-origin invariant; application/pdf mime + .pdf name. ──────

  Future<Map<Object?, Object?>?> tapSharePdf(WidgetTester tester) async {
    PathProviderPlatform.instance = _FakePathProvider();

    Map<Object?, Object?>? args;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      shareChannel,
      (call) async {
        if (call.method == 'shareFiles') {
          args = call.arguments as Map<Object?, Object?>;
        }
        return '';
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, null),
    );

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox(width: 200, height: 100);
            },
          ),
        ),
      ),
    );

    // A tiny but non-empty payload standing in for the PDF bytes.
    final bytes = Uint8List.fromList(List<int>.generate(32, (i) => i));
    await tester.runAsync(() => sharePdf(ctx, bytes));
    return args;
  }

  testWidgets('sharePdf forwards a non-zero share origin', (tester) async {
    final args = await tapSharePdf(tester);
    expect(args, isNotNull);
    expect((args!['originWidth'] as double) > 0, isTrue);
    expect((args['originHeight'] as double) > 0, isTrue);
  });

  testWidgets('sharePdf shares an application/pdf file named rihla_trip_receipt.pdf',
      (tester) async {
    final args = await tapSharePdf(tester);
    final paths = (args!['paths'] as List).cast<String>();
    final mimeTypes = (args['mimeTypes'] as List).cast<String>();
    expect(paths.single, endsWith('rihla_trip_receipt.pdf'));
    expect(mimeTypes.single, 'application/pdf');
  });
}
