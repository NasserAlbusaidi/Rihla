import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/widget_to_image.dart';

void main() {
  // The PNG magic number: 0x89 'P' 'N' 'G'.
  const pngHeader = [0x89, 0x50, 0x4E, 0x47];

  testWidgets('captureBoundaryPng rasterizes a boundary to PNG bytes',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                width: 120,
                height: 150,
                color: const Color(0xFFD17B2C),
                alignment: Alignment.center,
                child: const Text('Rihla'),
              ),
            ),
          ),
        ),
      ),
    );

    // toImage / PNG encoding are real-async engine work → drive under runAsync.
    final bytes = await tester.runAsync(() => captureBoundaryPng(key));

    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(0));
    expect(bytes.sublist(0, 4), pngHeader);
  });

  testWidgets('captureBoundaryPng returns null for an unmounted key',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    final bytes = await tester.runAsync(() => captureBoundaryPng(key));
    expect(bytes, isNull);
  });
}
