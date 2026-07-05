import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/shared/widgets/falaj_fork.dart';

void main() {
  group('FalajFork', () {
    testWidgets('LTR: painter carries textDirection.ltr', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: FalajFork(size: Size(40, 8), color: Colors.black),
          ),
        ),
      );

      final customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
      final painter = customPaint.painter;
      expect(painter, isA<FalajForkPainter>());
      expect(
        (painter as FalajForkPainter).textDirection,
        TextDirection.ltr,
      );
    });

    testWidgets('RTL: painter carries textDirection.rtl (mirrors via '
        'Directionality, not locale)', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: FalajFork(size: Size(40, 8), color: Colors.black),
          ),
        ),
      );

      final customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
      final painter = customPaint.painter as FalajForkPainter;
      expect(painter.textDirection, TextDirection.rtl);
    });
  });

  group('FalajForkPainter.shouldRepaint', () {
    const base = FalajForkPainter(
      color: Colors.black,
      textDirection: TextDirection.ltr,
    );

    test('differing color -> true', () {
      const other = FalajForkPainter(
        color: Colors.red,
        textDirection: TextDirection.ltr,
      );
      expect(other.shouldRepaint(base), isTrue);
    });

    test('differing textDirection -> true', () {
      const other = FalajForkPainter(
        color: Colors.black,
        textDirection: TextDirection.rtl,
      );
      expect(other.shouldRepaint(base), isTrue);
    });

    test('differing spreadRatio -> true', () {
      const other = FalajForkPainter(
        color: Colors.black,
        textDirection: TextDirection.ltr,
        spreadRatio: 0.55,
      );
      expect(other.shouldRepaint(base), isTrue);
    });

    test('identical params -> false', () {
      const other = FalajForkPainter(
        color: Colors.black,
        textDirection: TextDirection.ltr,
      );
      expect(other.shouldRepaint(base), isFalse);
    });
  });
}
