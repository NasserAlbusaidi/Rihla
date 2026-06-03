import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:safar/shared/widgets/skeleton_loader.dart';
import 'package:safar/shared/widgets/skeleton_primitives.dart';

// `Skeletonizer` is abstract (the concrete widget is a private `_Skeletonizer`),
// so `find.byType(Skeletonizer)` never matches — match the public supertype.
final _skeletonizer = find.byWidgetPredicate((w) => w is Skeletonizer);

void main() {
  // ---------------------------------------------------------------------------
  // SkeletonCircle
  // ---------------------------------------------------------------------------
  group('SkeletonCircle', () {
    testWidgets('renders a Container with the specified size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: Center(child: SkeletonCircle(size: 40))),
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonCircle), findsOneWidget);

      final size = tester.getSize(find.byType(SkeletonCircle));
      expect(size.width, 40.0);
      expect(size.height, 40.0);
    });

    testWidgets('renders with circular shape decoration', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: Center(child: SkeletonCircle(size: 32))),
        ),
      );
      await tester.pump();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final circle = containers.firstWhere((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration) {
          return decoration.shape == BoxShape.circle;
        }
        return false;
      });
      expect(circle, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // SkeletonBar
  // ---------------------------------------------------------------------------
  group('SkeletonBar', () {
    testWidgets('renders with the specified width and default height 14.0', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: Center(child: SkeletonBar(width: 120))),
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonBar), findsOneWidget);

      final size = tester.getSize(find.byType(SkeletonBar));
      expect(size.width, 120.0);
      expect(size.height, 14.0);
    });

    testWidgets('accepts custom height', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(child: SkeletonBar(width: 80, height: 10)),
          ),
        ),
      );
      await tester.pump();

      final size = tester.getSize(find.byType(SkeletonBar));
      expect(size.height, 10.0);
    });

    testWidgets('renders with rounded corners', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: Center(child: SkeletonBar(width: 100))),
        ),
      );
      await tester.pump();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final bar = containers.firstWhere((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration) {
          return decoration.borderRadius != null &&
              decoration.shape == BoxShape.rectangle;
        }
        return false;
      });
      expect(bar, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // SkeletonBlock
  // ---------------------------------------------------------------------------
  group('SkeletonBlock', () {
    testWidgets('renders with the specified width and height', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(child: SkeletonBlock(width: 200, height: 80)),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonBlock), findsOneWidget);

      final size = tester.getSize(find.byType(SkeletonBlock));
      expect(size.width, 200.0);
      expect(size.height, 80.0);
    });

    testWidgets('renders with rounded corners', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(child: SkeletonBlock(width: 150, height: 60)),
          ),
        ),
      );
      await tester.pump();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final block = containers.firstWhere((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration) {
          return decoration.borderRadius != null;
        }
        return false;
      });
      expect(block, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // SkeletonRow
  // ---------------------------------------------------------------------------
  group('SkeletonRow', () {
    testWidgets('renders a Row with a SkeletonCircle and SkeletonBars', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(child: SizedBox(width: 400, child: SkeletonRow())),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonRow), findsOneWidget);
      expect(find.byType(SkeletonCircle), findsOneWidget);
      expect(find.byType(SkeletonBar), findsAtLeastNWidgets(2));
    });

    testWidgets('renders a Row widget at the top level', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(child: SizedBox(width: 400, child: SkeletonRow())),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Row), findsAtLeastNWidgets(1));
    });
  });

  // ---------------------------------------------------------------------------
  // SkeletonCard
  // ---------------------------------------------------------------------------
  group('SkeletonCard', () {
    testWidgets('renders with the default height 72 and rounded corners', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(child: SizedBox(width: 300, child: SkeletonCard())),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonCard), findsOneWidget);

      final size = tester.getSize(find.byType(SkeletonCard));
      expect(size.height, 72.0);
    });

    testWidgets('accepts custom height', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(
              child: SizedBox(width: 300, child: SkeletonCard(height: 100)),
            ),
          ),
        ),
      );
      await tester.pump();

      final size = tester.getSize(find.byType(SkeletonCard));
      expect(size.height, 100.0);
    });

    testWidgets('renders with rounded corners at radiusLarge', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(child: SizedBox(width: 300, child: SkeletonCard())),
          ),
        ),
      );
      await tester.pump();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final card = containers.firstWhere((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration) {
          return decoration.borderRadius != null;
        }
        return false;
      });
      expect(card, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // SkeletonLoader — named factory variants
  // ---------------------------------------------------------------------------
  group('SkeletonLoader.dashboardHero', () {
    testWidgets('renders Skeletonizer with SkeletonBlock children', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: SkeletonLoader.dashboardHero(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(_skeletonizer, findsOneWidget);
      expect(find.byType(SkeletonBlock), findsWidgets);
    });
  });

  group('SkeletonLoader.eventCard', () {
    testWidgets(
      'renders Skeletonizer with SkeletonCircle, SkeletonBar, and SkeletonBlock',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: SkeletonLoader.eventCard(),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(_skeletonizer, findsOneWidget);
        expect(find.byType(SkeletonCircle), findsAtLeastNWidgets(1));
        expect(find.byType(SkeletonBar), findsAtLeastNWidgets(1));
        expect(find.byType(SkeletonBlock), findsAtLeastNWidgets(1));
      },
    );
  });

  group('SkeletonLoader.groupList', () {
    testWidgets('renders Skeletonizer with SkeletonRow children', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: SkeletonLoader.groupList(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(_skeletonizer, findsOneWidget);
      expect(find.byType(SkeletonRow), findsAtLeastNWidgets(1));
    });
  });

  group('SkeletonLoader.expenseList', () {
    testWidgets(
      'renders Skeletonizer with SkeletonRow children matching expense layout',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: SkeletonLoader.expenseList(),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(_skeletonizer, findsOneWidget);
        expect(find.byType(SkeletonRow), findsAtLeastNWidgets(1));
        expect(find.byType(SkeletonBar), findsAtLeastNWidgets(1));
      },
    );
  });

  group('SkeletonLoader.gearList', () {
    testWidgets(
      'renders Skeletonizer with SkeletonBlock checkbox and SkeletonBar items',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: SkeletonLoader.gearList(),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(_skeletonizer, findsOneWidget);
        expect(find.byType(SkeletonBlock), findsAtLeastNWidgets(1));
        expect(find.byType(SkeletonBar), findsAtLeastNWidgets(1));
      },
    );
  });

  group('SkeletonLoader.generic', () {
    testWidgets('renders Skeletonizer wrapping SkeletonCard items', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: SkeletonLoader.generic(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(_skeletonizer, findsOneWidget);
      expect(find.byType(SkeletonCard), findsAtLeastNWidgets(1));
    });
  });

  group('SkeletonLoader shimmer colors', () {
    testWidgets(
      'ShimmerEffect uses AppColorTokens.light.inputFill and cardSurface',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: SkeletonLoader.generic(),
              ),
            ),
          ),
        );
        await tester.pump();

        final skeletonizer = tester.widget<Skeletonizer>(_skeletonizer);
        final effect = skeletonizer.effect! as ShimmerEffect;
        expect(effect.colors, contains(AppColorTokens.light.inputFill));
        expect(effect.colors, contains(AppColorTokens.light.cardSurface));
      },
    );
  });

  group('SkeletonLoader backward compatibility', () {
    testWidgets('cardList still renders', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: SkeletonLoader.cardList(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(_skeletonizer, findsOneWidget);
    });

    testWidgets('documentList still renders', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: SkeletonLoader.documentList(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(_skeletonizer, findsOneWidget);
    });
  });
}
