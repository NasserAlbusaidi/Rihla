import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/shared/widgets/scroll_under_header.dart';

// #1011: the shared fixed-header-over-scroll-view separator. A colors.rule
// hairline fades in under the header once content scrolls beneath it, so the
// header stops sharing the scaffold background seamlessly with the content.

const _hairlineKey = Key('test-hairline');

Widget _harness({ScrollController? controller}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: ScrollUnderHeader(
          hairlineKey: _hairlineKey,
          header: const SizedBox(height: 48, child: Center(child: Text('Header'))),
          child: ListView.builder(
            controller: controller,
            itemCount: 60,
            itemBuilder: (_, i) => SizedBox(height: 56, child: Text('row $i')),
          ),
        ),
      ),
    ),
  );
}

double _opacity(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byKey(_hairlineKey)).opacity;

void main() {
  testWidgets('hairline is hidden at rest (opacity 0)', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.byKey(_hairlineKey), findsOneWidget);
    expect(_opacity(tester), 0.0);
  });

  testWidgets('hairline fades in once content scrolls under the header',
      (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(_harness(controller: controller));
    await tester.pumpAndSettle();

    controller.jumpTo(120);
    await tester.pump();

    expect(_opacity(tester), 1.0);
  });

  testWidgets('hairline hides again when scrolled back to the top',
      (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(_harness(controller: controller));
    await tester.pumpAndSettle();

    controller.jumpTo(120);
    await tester.pump();
    expect(_opacity(tester), 1.0);

    controller.jumpTo(0);
    await tester.pump();
    expect(_opacity(tester), 0.0);
  });

  testWidgets('nested horizontal scrolling does not toggle the hairline',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SafeArea(
            child: ScrollUnderHeader(
              hairlineKey: _hairlineKey,
              header: const SizedBox(height: 48),
              child: ListView(
                children: [
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: 30,
                      itemBuilder: (_, i) =>
                          SizedBox(width: 120, child: Text('h$i')),
                    ),
                  ),
                  for (var i = 0; i < 20; i++)
                    SizedBox(height: 56, child: Text('v$i')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Fling the inner horizontal strip; the vertical hairline must stay hidden.
    await tester.drag(find.text('h0'), const Offset(-300, 0));
    await tester.pump();

    expect(_opacity(tester), 0.0);
  });
}
