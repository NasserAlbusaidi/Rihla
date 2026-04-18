import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/shared/widgets/grain_overlay.dart';

void main() {
  group('GrainOverlay', () {
    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
           theme: AppTheme.lightTheme,
          home: GrainOverlay(
            child: Text('test child'),
          ),
        ),
      );

      expect(find.text('test child'), findsOneWidget);
    });

    testWidgets('renders a DecoratedBox', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
           theme: AppTheme.lightTheme,
          home: GrainOverlay(
            child: SizedBox(),
          ),
        ),
      );

      expect(find.byType(DecoratedBox), findsWidgets);
    });

    testWidgets('default opacity is 0.035', (tester) async {
      const overlay = GrainOverlay(child: SizedBox());
      expect(overlay.opacity, 0.035);
    });

    testWidgets('accepts custom opacity', (tester) async {
      const overlay = GrainOverlay(opacity: 0.02, child: SizedBox());
      expect(overlay.opacity, 0.02);
    });

    testWidgets('GrainOverlay widget tree contains DecoratedBox with grain image', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
           theme: AppTheme.lightTheme,
          home: Scaffold(
            body: GrainOverlay(
              child: Text('content'),
            ),
          ),
        ),
      );

      final decoratedBox = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).firstWhere(
        (box) {
          final decoration = box.decoration;
          if (decoration is BoxDecoration) {
            return decoration.image?.image is AssetImage;
          }
          return false;
        },
        orElse: () => throw TestFailure('No DecoratedBox with AssetImage found'),
      );

      final decoration = decoratedBox.decoration as BoxDecoration;
      final assetImage = decoration.image!.image as AssetImage;
      expect(assetImage.assetName, 'assets/textures/grain.png');
    });

    testWidgets('grain image uses ImageRepeat.repeat', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
           theme: AppTheme.lightTheme,
          home: Scaffold(
            body: GrainOverlay(
              child: SizedBox(),
            ),
          ),
        ),
      );

      final decoratedBox = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).firstWhere(
        (box) {
          final decoration = box.decoration;
          if (decoration is BoxDecoration) {
            return decoration.image?.image is AssetImage;
          }
          return false;
        },
        orElse: () => throw TestFailure('No DecoratedBox with AssetImage found'),
      );

      final decoration = decoratedBox.decoration as BoxDecoration;
      expect(decoration.image!.repeat, ImageRepeat.repeat);
    });

    testWidgets('grain image uses configured opacity', (tester) async {
      const testOpacity = 0.05;
      await tester.pumpWidget(
        MaterialApp(
           theme: AppTheme.lightTheme,
          home: Scaffold(
            body: GrainOverlay(
              opacity: testOpacity,
              child: SizedBox(),
            ),
          ),
        ),
      );

      final decoratedBox = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).firstWhere(
        (box) {
          final decoration = box.decoration;
          if (decoration is BoxDecoration) {
            return decoration.image?.image is AssetImage;
          }
          return false;
        },
        orElse: () => throw TestFailure('No DecoratedBox with AssetImage found'),
      );

      final decoration = decoratedBox.decoration as BoxDecoration;
      expect(decoration.image!.opacity, testOpacity);
    });
  });
}
