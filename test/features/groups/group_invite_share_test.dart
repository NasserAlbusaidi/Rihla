import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/widgets/group_info_section.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #277 — the shared invite text must carry a tappable join link, not just the
/// bare 6-char code. Both share callsites must use [groupShareInviteMessage]
/// (which embeds the `web.app/join/<code>` URI), never the link-less
/// [groupShareMessage].
void main() {
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

  final group = Group(
    id: 'g1',
    name: 'Family trip',
    inviteCode: 'ABC123',
    createdBy: 'p1',
    memberIds: const ['p1'],
    createdAt: DateTime(2026, 5, 13),
  );

  testWidgets('Group settings invite share embeds the join link', (
    tester,
  ) async {
    String? sharedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      shareChannel,
      (call) async {
        if (call.method == 'share') {
          sharedText = (call.arguments as Map)['text'] as String?;
        }
        return '';
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        shareChannel,
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: GroupInfoSection(group: group, isCreator: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Iconsax.send_2));
    await tester.pumpAndSettle();

    expect(sharedText, isNotNull);
    expect(sharedText, contains('https://rihla-safar.web.app/join/ABC123'));
  });

  test('both invite share callsites use the link-bearing message', () {
    for (final path in const [
      'lib/features/groups/screens/create_group_screen.dart',
      'lib/features/groups/widgets/group_info_section.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('groupShareInviteMessage('),
        reason: '$path must share the link-bearing invite message',
      );
      expect(
        source,
        isNot(contains('groupShareMessage(')),
        reason: '$path must not share the link-less bare-code message (#277)',
      );
    }
  });
}
