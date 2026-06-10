import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
