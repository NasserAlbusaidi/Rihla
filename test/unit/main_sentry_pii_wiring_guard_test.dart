import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #968 — guard: the central Sentry PII scrubber must stay wired.
///
/// PII protection is defense-in-depth via a single `beforeSend` choke point in
/// `SentryFlutter.init`. A future refactor of `main.dart` could silently drop
/// the wiring (or the explicit `sendDefaultPii = false`) with no test to catch
/// it — this file-content assertion fails if the scrubber stops being wired.
void main() {
  test('main.dart wires the Sentry PII scrubber into beforeSend (#968)', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('sendDefaultPii = false'),
        reason: 'SentryFlutter.init must set sendDefaultPii = false explicitly.');
    expect(source, contains('options.beforeSend'),
        reason: 'SentryFlutter.init must set a beforeSend callback.');
    expect(source, contains('scrubSentryPii'),
        reason: 'beforeSend must route events through scrubSentryPii.');
  });
}
