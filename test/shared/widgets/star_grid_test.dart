import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/tokens/star_grid_tokens.dart';
import 'package:safar/shared/widgets/star_grid.dart';

void main() {
  group('StarGridPainter', () {
    test('defaults to kStarGridOpacity, which stays at or under 3%', () {
      const painter = StarGridPainter(color: Colors.white);
      expect(painter.opacity, kStarGridOpacity);
      expect(painter.opacity, lessThanOrEqualTo(0.03));
    });

    test('shouldRepaint is true when color differs', () {
      const a = StarGridPainter(color: Colors.white);
      const b = StarGridPainter(color: Colors.black);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint is true when opacity differs', () {
      const a = StarGridPainter(color: Colors.white, opacity: 0.03);
      const b = StarGridPainter(color: Colors.white, opacity: 0.02);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint is false when color and opacity are identical', () {
      const a = StarGridPainter(color: Colors.white, opacity: 0.03);
      const b = StarGridPainter(color: Colors.white, opacity: 0.03);
      expect(a.shouldRepaint(b), isFalse);
    });

    testWidgets('paints a fixed-size grid without throwing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(
            width: 200,
            height: 100,
            child: CustomPaint(painter: StarGridPainter(color: Colors.white)),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final customPaints = tester.widgetList<CustomPaint>(
        find.byType(CustomPaint),
      );
      expect(customPaints.any((cp) => cp.painter is StarGridPainter), isTrue);
    });
  });
}
