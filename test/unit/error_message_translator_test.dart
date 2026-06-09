import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/error_message_translator.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  group('classifyError (#356) — pure mapping', () {
    final cases = <String, ({Object error, FriendlyError expected})>{
      'firestore permission-denied': (
        error: FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        expected: FriendlyError.permissionDenied,
      ),
      'functions permission-denied': (
        error: FirebaseFunctionsException(code: 'permission-denied', message: 'x'),
        expected: FriendlyError.permissionDenied,
      ),
      'functions unauthenticated': (
        error: FirebaseFunctionsException(code: 'unauthenticated', message: 'x'),
        expected: FriendlyError.permissionDenied,
      ),
      'functions unavailable': (
        error: FirebaseFunctionsException(code: 'unavailable', message: 'x'),
        expected: FriendlyError.network,
      ),
      'auth network-request-failed': (
        error: FirebaseAuthException(code: 'network-request-failed'),
        expected: FriendlyError.network,
      ),
      'functions deadline-exceeded': (
        error: FirebaseFunctionsException(code: 'deadline-exceeded', message: 'x'),
        expected: FriendlyError.network,
      ),
      'functions resource-exhausted': (
        error: FirebaseFunctionsException(code: 'resource-exhausted', message: 'x'),
        expected: FriendlyError.tooManyRequests,
      ),
      'auth too-many-requests': (
        error: FirebaseAuthException(code: 'too-many-requests'),
        expected: FriendlyError.tooManyRequests,
      ),
      'timeout → network': (
        error: TimeoutException('slow'),
        expected: FriendlyError.network,
      ),
      'unknown firebase code → unexpected': (
        error: FirebaseException(plugin: 'cloud_functions', code: 'internal'),
        expected: FriendlyError.unexpected,
      ),
      'plain exception → unexpected': (
        error: Exception('boom'),
        expected: FriendlyError.unexpected,
      ),
      'raw string → unexpected': (
        error: 'something stringy',
        expected: FriendlyError.unexpected,
      ),
    };

    cases.forEach((label, c) {
      test('$label → ${c.expected}', () {
        expect(classifyError(c.error), c.expected);
      });
    });
  });

  group('friendlyMessageFor (#356) — localized, never raw', () {
    Future<String> messageFor(WidgetTester tester, Object error) async {
      late String result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              result = friendlyMessageFor(context, error);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return result;
    }

    testWidgets('permission-denied maps to the friendly permission string',
        (tester) async {
      final msg = await messageFor(
        tester,
        FirebaseFunctionsException(code: 'permission-denied', message: 'raw'),
      );
      expect(msg, "You don't have permission to do that.");
      expect(msg.contains('permission-denied'), isFalse); // raw code not leaked
    });

    testWidgets('unavailable maps to the friendly network string',
        (tester) async {
      final msg = await messageFor(
        tester,
        FirebaseFunctionsException(code: 'unavailable', message: 'raw'),
      );
      expect(msg, 'Please check your connection and try again.');
    });

    testWidgets('unknown error maps to the generic string, not e.toString()',
        (tester) async {
      final msg = await messageFor(tester, Exception('secret internals'));
      expect(msg, 'Something went wrong. Please try again.');
      expect(msg.contains('secret internals'), isFalse);
    });
  });
}
