import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/settings/keys/profile_keys.dart';
import 'package:safar/features/settings/widgets/profile_qr_sheet.dart';

void main() {
  testWidgets('profile QR sheet renders QR and the handle', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showProfileQrSheet(
                  context,
                  displayName: 'Nasser',
                  handle: '@nasser',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(ProfileKeys.qrCard), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('@nasser'), findsOneWidget);
    expect(find.text('Nasser'), findsOneWidget);
    expect(find.text('Copy handle'), findsOneWidget);
  });
}
