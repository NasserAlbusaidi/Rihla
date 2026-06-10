import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/app_messenger.dart';
import 'package:safar/features/auth/providers/recovery_failure_surface.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/auth/services/recovery_failure_notice.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/recording_recovery_diagnostics.dart';

void main() {
  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: appMessengerKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
  }

  testWidgets('surfaces a seeded failure: shows message, reports, clears',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await writeRecoveryFailureNotice(
      prefs,
      code: 'invalid-action-code',
      op: AuthRecoveryService.opRecover,
    );
    final recording = RecordingRecoveryDiagnostics();

    await pumpHost(tester);
    await surfaceRecoveryFailureNotice(prefs: prefs, diagnostics: recording);
    await tester.pump();

    expect(
      find.text('This link has expired or was already used. Send a new one.'),
      findsOneWidget,
    );
    expect(readRecoveryFailureNotice(prefs), isNull);
    final surfaced =
        recording.calls.firstWhere((c) => c.phase == 'recover.surfaced');
    expect(surfaced.code, 'invalid-action-code');
    expect(surfaced.data['op'], AuthRecoveryService.opRecover);
  });

  testWidgets('no marker is a silent no-op', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final recording = RecordingRecoveryDiagnostics();

    await pumpHost(tester);
    await surfaceRecoveryFailureNotice(prefs: prefs, diagnostics: recording);
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
    expect(recording.calls, isEmpty);
  });
}
