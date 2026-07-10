import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #1079 — guard: the emulator bootstrap must AWAIT `useAuthEmulator`.
///
/// The `_useFirebaseEmulator` branch in `lib/main.dart` sits under a comment
/// requiring emulator hookup to run BEFORE any auth call. Firestore/Functions
/// routing on the adjacent lines is synchronous, but `useAuthEmulator` returns
/// a future — wrapping it in `unawaited(...)` lets restored Keychain auth race
/// the routing during emulator QA (a disposable `await` patch was needed to
/// make a QA scenario reliable). Prod boot is unaffected: the branch is gated
/// on `USE_FIREBASE_EMULATOR`.
///
/// Source-guard style follows `ios_deep_linking_guard_test.dart`: exercising
/// the real `main()` bootstrap in a unit test is infeasible
/// (`FirebaseAuth.instance` throws `[core/no-app]`), and extracting the block
/// behind injectable SDK hooks adds indirection a one-line boot fix does not
/// warrant. Whitespace is stripped so a `dart format` re-wrap cannot dodge
/// the assertions.
void main() {
  test('main.dart awaits useAuthEmulator in the emulator branch (#1079)', () {
    final source = File('lib/main.dart').readAsStringSync();
    final collapsed = source.replaceAll(RegExp(r'\s+'), '');

    expect(
      collapsed,
      contains('awaitFirebaseAuth.instance.useAuthEmulator'),
      reason:
          'The emulator bootstrap must `await '
          'FirebaseAuth.instance.useAuthEmulator(...)` — the adjacent comment '
          'requires emulator routing to complete BEFORE any auth call, and an '
          'unawaited future races restored Keychain auth in emulator QA '
          '(#1079).',
    );
    expect(
      collapsed,
      isNot(contains('unawaited(FirebaseAuth.instance.useAuthEmulator')),
      reason:
          'Never wrap useAuthEmulator in unawaited(...) — that reintroduces '
          'the #1079 auth/emulator-routing race.',
    );
  });
}
