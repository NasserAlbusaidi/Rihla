import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/draft_navigation_guard.dart';

// #1208: registry semantics for DraftNavigationGuard — the process-wide guard
// that runtime deep-link/notification navigation consults before router.go()
// so it never silently destroys a dirty editor draft.
// Spec: docs/plans/2026-07-13-1208-deeplink-dirty-draft-guard.md

void main() {
  setUp(DraftNavigationGuard.instance.reset);
  tearDown(DraftNavigationGuard.instance.reset);

  group('DraftNavigationGuard', () {
    test('no guards registered: hasGuards false, mayNavigate resolves true', () async {
      expect(DraftNavigationGuard.instance.hasGuards, isFalse);
      expect(await DraftNavigationGuard.instance.mayNavigate(), isTrue);
    });

    test('a single registered guard is consulted', () async {
      DraftNavigationGuard.instance.register(() async => false);

      expect(DraftNavigationGuard.instance.hasGuards, isTrue);
      expect(await DraftNavigationGuard.instance.mayNavigate(), isFalse);
    });

    test('a guard returning true allows navigation', () async {
      DraftNavigationGuard.instance.register(() async => true);

      expect(await DraftNavigationGuard.instance.mayNavigate(), isTrue);
    });

    test('LIFO: the most recently registered guard is consulted', () async {
      DraftNavigationGuard.instance.register(() async => true);
      DraftNavigationGuard.instance.register(() async => false);

      expect(await DraftNavigationGuard.instance.mayNavigate(), isFalse);
    });

    test(
      'concurrent consults are refused — a second request while a dialog is '
      'showing loses, the first consult wins the user\'s attention',
      () async {
        final gate = Completer<bool>();
        DraftNavigationGuard.instance.register(() => gate.future);

        final first = DraftNavigationGuard.instance.mayNavigate();
        // Give the first consult a chance to mark itself in-flight before the
        // second one is issued.
        await Future<void>.delayed(Duration.zero);

        final second = await DraftNavigationGuard.instance.mayNavigate();
        expect(second, isFalse, reason: 'concurrent consult must be refused');

        gate.complete(true);
        expect(await first, isTrue);
      },
    );

    test('unregister restores prior behavior', () async {
      Future<bool> guard() async => false;
      DraftNavigationGuard.instance.register(guard);
      expect(DraftNavigationGuard.instance.hasGuards, isTrue);

      DraftNavigationGuard.instance.unregister(guard);

      expect(DraftNavigationGuard.instance.hasGuards, isFalse);
      expect(await DraftNavigationGuard.instance.mayNavigate(), isTrue);
    });

    test('unregister falls back to an earlier guard', () async {
      Future<bool> outer() async => true;
      Future<bool> inner() async => false;
      DraftNavigationGuard.instance.register(outer);
      DraftNavigationGuard.instance.register(inner);

      DraftNavigationGuard.instance.unregister(inner);

      expect(await DraftNavigationGuard.instance.mayNavigate(), isTrue);
    });

    test('reset clears registered guards and in-flight state', () async {
      DraftNavigationGuard.instance.register(() async => false);

      DraftNavigationGuard.instance.reset();

      expect(DraftNavigationGuard.instance.hasGuards, isFalse);
      expect(await DraftNavigationGuard.instance.mayNavigate(), isTrue);
    });
  });
}
