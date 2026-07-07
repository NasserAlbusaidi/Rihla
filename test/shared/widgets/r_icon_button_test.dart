import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/shared/widgets/r_icon_button.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('#1041 §4: ghost variant hit target is >=44dp', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RIconButton(
          variant: RIconButtonVariant.ghost,
          icon: Icons.close,
          onTap: () {},
        ),
      ),
    );

    final size = tester.getSize(find.byType(RIconButton));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('paper variant hit target stays 48dp', (tester) async {
    await tester.pumpWidget(
      _wrap(RIconButton(icon: Icons.close, onTap: () {})),
    );

    final size = tester.getSize(find.byType(RIconButton));
    expect(size.width, 48);
    expect(size.height, 48);
  });
}
