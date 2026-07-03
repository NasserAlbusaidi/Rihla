import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/late_write_notice.dart';
import 'package:safar/core/utils/write_ack.dart';

// #412: awaitServerAck races a Firestore write's server-ack future against a
// bounded timeout so offline saves stop hanging the UI. The real SDK's write
// futures resolve only on SERVER ack — FakeFirebaseFirestore acks instantly,
// which is why these tests drive never-completing Completers instead.
void main() {
  test('resolves acked when the write completes within the timeout', () {
    fakeAsync((async) {
      final completer = Completer<void>();
      WriteAck? outcome;
      awaitServerAck(completer.future).then((o) => outcome = o);
      async.elapse(const Duration(seconds: 1));
      completer.complete();
      async.flushMicrotasks();
      expect(outcome, WriteAck.acked);
    });
  });

  test('resolves queued when the write never completes (offline #412)', () {
    fakeAsync((async) {
      WriteAck? outcome;
      awaitServerAck(Completer<void>().future).then((o) => outcome = o);
      async.elapse(const Duration(seconds: 6));
      expect(outcome, WriteAck.queued);
    });
  });

  test('an error within the timeout propagates to the caller', () {
    fakeAsync((async) {
      final completer = Completer<void>();
      Object? caught;
      awaitServerAck(completer.future).catchError((Object e) {
        caught = e;
        return WriteAck.queued;
      });
      completer.completeError(StateError('rules rejection'));
      async.flushMicrotasks();
      expect(caught, isA<StateError>());
    });
  });

  test('an error after the timeout reaches onLateError, not the caller', () {
    fakeAsync((async) {
      final completer = Completer<void>();
      WriteAck? outcome;
      Object? late;
      awaitServerAck(
        completer.future,
        onLateError: (e, _) => late = e,
      ).then((o) => outcome = o);
      async.elapse(const Duration(seconds: 6));
      expect(outcome, WriteAck.queued);
      completer.completeError(StateError('rejected on replay'));
      async.flushMicrotasks();
      expect(late, isA<StateError>());
    });
  });

  test('skipWait returns queued immediately without waiting', () {
    fakeAsync((async) {
      WriteAck? outcome;
      awaitServerAck(
        Completer<void>().future,
        skipWait: true,
      ).then((o) => outcome = o);
      async.flushMicrotasks();
      expect(outcome, WriteAck.queued);
    });
  });

  test('skipWait still routes a later error to onLateError', () {
    fakeAsync((async) {
      final completer = Completer<void>();
      Object? late;
      awaitServerAck(
        completer.future,
        skipWait: true,
        onLateError: (e, _) => late = e,
      );
      async.flushMicrotasks();
      completer.completeError(StateError('boom'));
      async.flushMicrotasks();
      expect(late, isA<StateError>());
    });
  });

  // Scorecard critical 1: a terminal replay rejection must reach the global
  // user-visible notice, not just debugPrint + Sentry.
  group('late-write notice', () {
    final recorded = <Object>[];

    setUp(recorded.clear);
    tearDown(() {
      lateWriteNoticePresenter = defaultLateWriteNoticePresenter;
    });

    test('a rejection after the queued return reaches the presenter once', () {
      fakeAsync((async) {
        lateWriteNoticePresenter = recorded.add;
        final completer = Completer<void>();
        awaitServerAck(completer.future);
        async.elapse(const Duration(seconds: 6));
        completer.completeError(StateError('rejected on replay'));
        async.flushMicrotasks();
        expect(recorded, hasLength(1));
        expect(recorded.single, isA<StateError>());
      });
    });

    test('a skipWait rejection also reaches the presenter', () {
      fakeAsync((async) {
        lateWriteNoticePresenter = recorded.add;
        final completer = Completer<void>();
        awaitServerAck(completer.future, skipWait: true);
        async.flushMicrotasks();
        completer.completeError(StateError('rejected on replay'));
        async.flushMicrotasks();
        expect(recorded, hasLength(1));
      });
    });

    test('an in-window error propagates to the caller and skips the notice',
        () {
      fakeAsync((async) {
        lateWriteNoticePresenter = recorded.add;
        final completer = Completer<void>();
        awaitServerAck(completer.future).catchError((Object e) {
          return WriteAck.queued;
        });
        completer.completeError(StateError('online rejection'));
        async.flushMicrotasks();
        expect(recorded, isEmpty);
      });
    });

    test('a throwing presenter breaks neither the observer nor onLateError',
        () {
      fakeAsync((async) {
        var onLateCalled = false;
        lateWriteNoticePresenter = (_) => throw StateError('presenter bug');
        final completer = Completer<void>();
        awaitServerAck(
          completer.future,
          onLateError: (_, _) => onLateCalled = true,
        );
        async.elapse(const Duration(seconds: 6));
        completer.completeError(StateError('rejected'));
        async.flushMicrotasks();
        expect(onLateCalled, isTrue);
      });
    });
  });
}
