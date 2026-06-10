import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:safar/core/config/app_links.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/widgets/qr_invite_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

void main() {
  setUpAll(() => registerFallbackValue(const LaunchOptions()));

  final group = Group(
    id: 'g1',
    name: 'Family trip',
    inviteCode: 'ABC123',
    createdBy: 'p1',
    memberIds: const ['p1'],
    createdAt: DateTime(2026, 5, 13),
  );

  Future<void> openSheet(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
  }

  testWidgets('QR sheet renders the QR card and 6-char code', (tester) async {
    expect(
      AppLinks.inviteUrl(group.inviteCode).toString(),
      'https://rihla-safar.web.app/join/ABC123',
    );

    await openSheet(tester);

    expect(find.byKey(GroupKeys.inviteQrCard), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('ABC123'), findsOneWidget);
    expect(find.text('Family trip'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets('QR sheet exposes a WhatsApp invite button (#354)',
      (tester) async {
    await openSheet(tester);

    expect(find.byKey(GroupKeys.inviteWhatsAppButton), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
  });

  testWidgets(
    'WhatsApp button falls back to the OS share sheet with the web.app/join '
    'message when WhatsApp is not installed (#354)',
    (tester) async {
      // Probe reports WhatsApp absent → the helper must route to shareText.
      final launcher = _MockUrlLauncher();
      when(() => launcher.canLaunch(any())).thenAnswer((_) async => false);
      UrlLauncherPlatform.instance = launcher;

      // Capture what hits the platform share channel.
      Map<Object?, Object?>? shareArgs;
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        shareChannel,
        (call) async {
          if (call.method == 'share') {
            shareArgs = call.arguments as Map<Object?, Object?>;
          }
          return '';
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(shareChannel, null),
      );

      await openSheet(tester);
      await tester.tap(find.byKey(GroupKeys.inviteWhatsAppButton));
      await tester.pumpAndSettle();

      verifyNever(() => launcher.launchUrl(any(), any()));
      expect(shareArgs, isNotNull, reason: 'fallback share never fired');
      final text = shareArgs!['text'] as String;
      expect(text, contains('rihla-safar.web.app/join/ABC123'));
      expect(text, contains('ABC123'));
      expect(text, isNot(contains('rihla.app/')));
    },
  );

  for (final locale in const [Locale('en'), Locale('ar')]) {
    testWidgets(
      'three-button row does not overflow on a narrow phone '
      '(${locale.languageCode}) (#354)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await openSheet(tester, locale: locale);

        expect(tester.takeException(), isNull);
      },
    );
  }

  test('invite links normalize pasted or legacy lowercase codes', () {
    expect(
      AppLinks.inviteUrl(' abc123 ').toString(),
      'https://rihla-safar.web.app/join/ABC123',
    );
  });
}
