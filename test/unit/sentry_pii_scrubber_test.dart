import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/sentry_pii_scrubber.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  group('scrubSentryPii (#968)', () {
    test('redacts an email in event.message.formatted', () {
      final event = SentryEvent(
        message: SentryMessage('contacted foo@bar.com about the trip'),
      );

      final scrubbed = scrubSentryPii(event);

      expect(scrubbed.message!.formatted, contains('[email-redacted]'));
      expect(scrubbed.message!.formatted, isNot(contains('@')));
      expect(scrubbed.message!.formatted, isNot(contains('foo')));
    });

    test('redacts an email in event.message.template', () {
      final event = SentryEvent(
        message: SentryMessage(
          'raw %s',
          template: 'raw foo@bar.com',
        ),
      );

      final scrubbed = scrubSentryPii(event);

      expect(scrubbed.message!.template, isNot(contains('@')));
      expect(scrubbed.message!.template, contains('[email-redacted]'));
    });

    test('redacts an email embedded in an exception value', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'FirebaseAuthException',
            value: 'the email foo@bar.com is already in use',
          ),
        ],
      );

      final scrubbed = scrubSentryPii(event);

      expect(scrubbed.exceptions!.single.value, isNot(contains('@')));
      expect(
        scrubbed.exceptions!.single.value,
        contains('[email-redacted]'),
      );
      expect(scrubbed.exceptions!.single.type, 'FirebaseAuthException');
    });

    test('redacts multiple emails across exceptions and breadcrumbs', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'A',
            value: 'first a@x.com then b@y.org',
          ),
        ],
        breadcrumbs: [
          Breadcrumb(message: 'sent link to c@z.net'),
          Breadcrumb(message: 'no pii here'),
        ],
      );

      final scrubbed = scrubSentryPii(event);

      expect(scrubbed.exceptions!.single.value, isNot(contains('@')));
      expect(scrubbed.breadcrumbs![0].message, isNot(contains('@')));
      expect(scrubbed.breadcrumbs![0].message, contains('[email-redacted]'));
      expect(scrubbed.breadcrumbs![1].message, 'no pii here');
    });

    test('nulls event.user.email while keeping other identifiers', () {
      final event = SentryEvent(
        user: SentryUser(id: 'anon-123', email: 'foo@bar.com'),
      );

      final scrubbed = scrubSentryPii(event);

      expect(scrubbed.user!.email, isNull);
      expect(scrubbed.user!.id, 'anon-123');
    });

    test('leaves an email-free event untouched in content', () {
      final event = SentryEvent(
        message: SentryMessage('clean message'),
        exceptions: [SentryException(type: 'X', value: 'no address')],
      );

      final scrubbed = scrubSentryPii(event);

      expect(scrubbed.message!.formatted, 'clean message');
      expect(scrubbed.exceptions!.single.value, 'no address');
    });

    test('does not mutate the incoming event (immutable)', () {
      final event = SentryEvent(
        message: SentryMessage('leak foo@bar.com'),
        exceptions: [
          SentryException(type: 'E', value: 'also foo@bar.com'),
        ],
        breadcrumbs: [Breadcrumb(message: 'crumb foo@bar.com')],
        user: SentryUser(id: 'anon-123', email: 'foo@bar.com'),
      );

      scrubSentryPii(event);

      // Original object is unchanged — scrubbing built new instances.
      expect(event.message!.formatted, contains('foo@bar.com'));
      expect(event.exceptions!.single.value, contains('foo@bar.com'));
      expect(event.breadcrumbs!.single.message, contains('foo@bar.com'));
      expect(event.user!.email, 'foo@bar.com');
    });

    test('no @-local-part survives anywhere after scrubbing', () {
      final event = SentryEvent(
        message: SentryMessage('m foo@bar.com'),
        exceptions: [SentryException(type: 'E', value: 'e bar@baz.io')],
        breadcrumbs: [Breadcrumb(message: 'b qux@quux.co')],
        user: SentryUser(id: 'anon-123', email: 'user@corp.com'),
      );

      final scrubbed = scrubSentryPii(event);

      expect(scrubbed.message!.formatted, isNot(contains('@')));
      expect(scrubbed.exceptions!.single.value, isNot(contains('@')));
      expect(scrubbed.breadcrumbs!.single.message, isNot(contains('@')));
      expect(scrubbed.user!.email, isNull);
    });
  });
}
