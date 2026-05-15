import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:safar/core/config/app_links.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/widgets/qr_invite_sheet.dart';

void main() {
  final group = Group(
    id: 'g1',
    name: 'Family trip',
    inviteCode: 'ABC123',
    createdBy: 'p1',
    memberIds: const ['p1'],
    createdAt: DateTime(2026, 5, 13),
  );

  testWidgets('QR sheet renders the QR card and 6-char code', (tester) async {
    expect(
      AppLinks.inviteUrl(group.inviteCode).toString(),
      'https://rihla-safar.web.app/join/ABC123',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showGroupInviteQrSheet(context, group: group),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.inviteQrCard), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('ABC123'), findsOneWidget);
    expect(find.text('Family trip'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });

  test('invite links normalize pasted or legacy lowercase codes', () {
    expect(
      AppLinks.inviteUrl(' abc123 ').toString(),
      'https://rihla-safar.web.app/join/ABC123',
    );
  });
}
