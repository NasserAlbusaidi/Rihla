import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';
import 'package:safar/shared/widgets/loading_button.dart';

// ---------------------------------------------------------------------------
// #1026 — a disabled LoadingButton (onPressed == null, not loading) used to
// keep painting `context.colors.primary` on its outer Container while the
// inner ElevatedButton stayed transparent, so the label rendered with the
// Material default disabled foreground on top of the bright primary fill —
// low contrast, and not visibly inactive. This pins the fix: disabled paints
// the muted `disabled` fill + `disabledText` label; enabled/loading keep the
// primary fill.
// ---------------------------------------------------------------------------

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: Scaffold(body: Center(child: child)),
);

BoxDecoration _outerDecoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(LoadingButton),
          matching: find.byType(Container),
        )
        .first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  testWidgets(
    'disabled button uses the muted disabled fill + disabledText label, not primary',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const LoadingButton(onPressed: null, isLoading: false, label: 'Join'),
        ),
      );

      final deco = _outerDecoration(tester);
      expect(deco.color, AppColorTokens.light.disabled);
      expect(deco.color, isNot(AppColorTokens.light.primary));

      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(
        btn.style?.foregroundColor?.resolve({WidgetState.disabled}),
        AppColorTokens.light.disabledText,
      );
    },
  );

  testWidgets('enabled button keeps the primary fill', (tester) async {
    await tester.pumpWidget(
      _wrap(
        LoadingButton(onPressed: () {}, isLoading: false, label: 'Join'),
      ),
    );
    expect(_outerDecoration(tester).color, AppColorTokens.light.primary);
  });

  testWidgets('loading button keeps the primary fill and shows the spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        LoadingButton(onPressed: () {}, isLoading: true, label: 'Join'),
      ),
    );
    expect(_outerDecoration(tester).color, AppColorTokens.light.primary);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
