import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/widgets/delete_account_dialog.dart';
import 'package:safar/features/auth/widgets/delete_account_retry_dialog.dart';
import 'package:safar/features/auth/widgets/sign_out_confirm_dialog.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

// #227 — direct contract coverage for the destructive/confirmation dialogs
// (MergeOnRecoverDialog deleted in #441 PR4 — no merge to consent to). Their
// confirm/cancel SEMANTICS (does/doesn't call the service) are already
// exercised transitively (delete_account_tile_test, sign_out_tile_test).
// What no test covered: the show() Future contract in
// isolation, and specifically the barrier-dismiss -> null leg — an accidental
// tap outside an account-deletion dialog must NOT resolve truthy.
typedef ShowDialogFn = Future<bool?> Function(BuildContext);

class _Probe {
  bool? result;
  bool resolved = false;
}

void main() {
  Future<_Probe> openDialog(WidgetTester tester, ShowDialogFn show) async {
    final probe = _Probe();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const Key('open'),
                onPressed: () async {
                  probe.result = await show(context);
                  probe.resolved = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    return probe;
  }

  final dialogs = <({
    String name,
    ShowDialogFn show,
    Key confirm,
    Key cancel,
  })>[
    (
      name: 'DeleteAccountDialog',
      show: DeleteAccountDialog.show,
      confirm: const Key('deleteAccount.confirm'),
      cancel: const Key('deleteAccount.cancel'),
    ),
    (
      name: 'SignOutConfirmDialog',
      show: (c) => SignOutConfirmDialog.show(c, email: 'foo@example.com'),
      confirm: const Key('signOutConfirm.confirm'),
      cancel: const Key('signOutConfirm.cancel'),
    ),
    (
      name: 'DeleteAccountRetryDialog',
      show: DeleteAccountRetryDialog.show,
      confirm: const Key('deleteAccount.partialRetry'),
      cancel: const Key('deleteAccount.partialDismiss'),
    ),
  ];

  for (final d in dialogs) {
    group(d.name, () {
      testWidgets('confirm resolves true', (tester) async {
        final probe = await openDialog(tester, d.show);
        await tester.tap(find.byKey(d.confirm));
        await tester.pumpAndSettle();
        expect(probe.result, isTrue);
      });

      testWidgets('cancel resolves false', (tester) async {
        final probe = await openDialog(tester, d.show);
        await tester.tap(find.byKey(d.cancel));
        await tester.pumpAndSettle();
        expect(probe.result, isFalse);
      });

      testWidgets('barrier dismiss resolves null (no accidental confirm)', (
        tester,
      ) async {
        final probe = await openDialog(tester, d.show);
        // Tap the scrim, well outside the centered dialog.
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(probe.resolved, isTrue);
        expect(probe.result, isNull);
      });
    });
  }

  testWidgets('SignOutConfirmDialog renders the linked email', (tester) async {
    await openDialog(
      tester,
      (c) => SignOutConfirmDialog.show(c, email: 'foo@example.com'),
    );
    expect(
      find.textContaining('foo@example.com', findRichText: true),
      findsOneWidget,
    );
  });

  // #1256 D6.3/D6.4 — provider- and platform-accurate copy.
  group('#1256 copy dispatch', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);
    final l10n = AppLocalizationsEn();

    testWidgets(
        'SignOutConfirmDialog: no email + Apple provider → Apple copy '
        '(a relay-withheld email must not get Google advice)', (tester) async {
      await openDialog(
        tester,
        (c) => SignOutConfirmDialog.show(c, email: null, hasAppleProvider: true),
      );
      expect(
        find.text(l10n.signOutContentApple, findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text(l10n.signOutContentGoogle, findRichText: true),
        findsNothing,
      );
    });

    testWidgets('SignOutConfirmDialog: no email, no Apple → Google copy '
        'unchanged', (tester) async {
      await openDialog(tester, (c) => SignOutConfirmDialog.show(c));
      expect(
        find.text(l10n.signOutContentGoogle, findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('DeleteAccountDialog: guest on iOS names Apple among the '
        'linkable providers', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await openDialog(
        tester,
        (c) => DeleteAccountDialog.show(c, isAnonymous: true),
      );
      expect(find.text(l10n.deleteGuestSessionContentIos), findsOneWidget);
      expect(find.text(l10n.deleteGuestSessionContent), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('DeleteAccountDialog: guest on default platform keeps the '
        'existing copy', (tester) async {
      await openDialog(
        tester,
        (c) => DeleteAccountDialog.show(c, isAnonymous: true),
      );
      expect(find.text(l10n.deleteGuestSessionContent), findsOneWidget);
      expect(find.text(l10n.deleteGuestSessionContentIos), findsNothing);
    });
  });
}
