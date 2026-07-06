import 'package:sentry_flutter/sentry_flutter.dart';

/// Central Sentry PII scrubber (#968).
///
/// Defense-in-depth belt-and-suspenders over the per-capture-site discipline:
/// a single choke point wired into `SentryFlutter.init`'s `beforeSend` that
/// strips email-shaped substrings from everything user-authored on an event
/// before it leaves the device, so one new capture path (or one Firebase auth
/// error message that embeds the user's email) can't silently leak PII.
///
/// Pure and immutable: returns a new [SentryEvent] via `copyWith` and freshly
/// constructed protocol objects; the incoming event and its lists are never
/// mutated.
SentryEvent scrubSentryPii(SentryEvent event) {
  // `copyWith` is deprecated by the SDK in favour of in-place mutation; we
  // keep it deliberately because the scrubber must NOT mutate the incoming
  // event (immutability contract).
  // ignore: deprecated_member_use
  return event.copyWith(
    message: _scrubMessage(event.message),
    exceptions: _scrubExceptions(event.exceptions),
    breadcrumbs: _scrubBreadcrumbs(event.breadcrumbs),
    user: _scrubUser(event.user),
  );
}

// Unanchored (substring) email matcher — deliberately NOT the anchored
// `^…$` validator in `email_validators.dart`, which only matches a whole
// string. This finds addresses embedded in longer messages.
final RegExp _emailPattern = RegExp(
  r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
);

const String _redactionMarker = '[email-redacted]';

String _redactEmails(String input) =>
    input.replaceAll(_emailPattern, _redactionMarker);

SentryMessage? _scrubMessage(SentryMessage? message) {
  if (message == null) return null;
  final template = message.template;
  return SentryMessage(
    _redactEmails(message.formatted),
    template: template == null ? null : _redactEmails(template),
    params: message.params,
  );
}

List<SentryException>? _scrubExceptions(List<SentryException>? exceptions) {
  if (exceptions == null) return null;
  return [
    for (final exception in exceptions)
      SentryException(
        type: exception.type,
        value: exception.value == null
            ? null
            : _redactEmails(exception.value!),
        module: exception.module,
        stackTrace: exception.stackTrace,
        mechanism: exception.mechanism,
        threadId: exception.threadId,
        throwable: exception.throwable,
      ),
  ];
}

List<Breadcrumb>? _scrubBreadcrumbs(List<Breadcrumb>? breadcrumbs) {
  if (breadcrumbs == null) return null;
  return [
    for (final crumb in breadcrumbs)
      Breadcrumb(
        message: crumb.message == null ? null : _redactEmails(crumb.message!),
        timestamp: crumb.timestamp,
        category: crumb.category,
        data: crumb.data,
        level: crumb.level,
        type: crumb.type,
      ),
  ];
}

SentryUser? _scrubUser(SentryUser? user) {
  if (user == null || user.email == null) return user;
  return SentryUser(
    id: user.id,
    username: user.username,
    email: null,
    ipAddress: user.ipAddress,
    geo: user.geo,
    name: user.name,
    data: user.data,
  );
}
