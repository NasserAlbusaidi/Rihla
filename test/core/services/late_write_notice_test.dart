import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/app_messenger.dart';
import 'package:safar/core/services/late_write_notice.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

// Scorecard critical 1: the default presenter surfaces a queued-write replay
// rejection on the root messenger with the friendly cause — never the raw
// plugin exception — and bursts QUEUE rather than collapse (Gate r1 P2).
Future<void> _pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SizedBox()),
    ),
  );
}

void main() {
  final en = AppLocalizationsEn();

  testWidgets('shows the friendly cause, never the raw exception', (
    tester,
  ) async {
    await _pumpHost(tester);

    notifyLateWriteFailure(
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      ),
    );
    await tester.pump();

    expect(
      find.text(en.lateWriteFailedNotice(en.errorPermissionDenied)),
      findsOneWidget,
    );
    expect(find.textContaining('cloud_firestore'), findsNothing);

    await tester.pumpAndSettle(const Duration(seconds: 9));
  });

  testWidgets('a burst of two rejections queues two sequential notices', (
    tester,
  ) async {
    await _pumpHost(tester);

    notifyLateWriteFailure(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    notifyLateWriteFailure(TimeoutException('replay'));
    // The 8s dismiss timer only ARMS once the entrance animation completes —
    // settle the entrance first, then elapse the window, then settle the
    // exit + queued entrance (argless pumpAndSettle never advances timers).
    await tester.pumpAndSettle();

    expect(
      find.text(en.lateWriteFailedNotice(en.errorPermissionDenied)),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 8, milliseconds: 100));
    await tester.pumpAndSettle();
    expect(
      find.text(en.lateWriteFailedNotice(en.errorNetwork)),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
  });

  test('no-ops without a mounted root messenger', () {
    expect(() => notifyLateWriteFailure(StateError('x')), returnsNormally);
  });
}
