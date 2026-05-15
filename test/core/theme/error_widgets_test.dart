import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/theme/error_widgets.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: child),
    );

void main() {
  group('NetworkErrorWidget — default constructor', () {
    testWidgets('renders default title and message', (tester) async {
      await tester.pumpWidget(_wrap(const NetworkErrorWidget()));
      expect(find.text('Connection Issue'), findsOneWidget);
      expect(
        find.textContaining(
            'Unable to load data. Please check your internet connection'),
        findsOneWidget,
      );
    });

    testWidgets('honors custom title, message, icon', (tester) async {
      await tester.pumpWidget(_wrap(const NetworkErrorWidget(
        title: 'Oops',
        message: 'Something broke',
        icon: Iconsax.warning_2,
      )));
      expect(find.text('Oops'), findsOneWidget);
      expect(find.text('Something broke'), findsOneWidget);
      expect(find.byIcon(Iconsax.warning_2), findsOneWidget);
    });

    testWidgets('no Retry button when onRetry is null', (tester) async {
      await tester.pumpWidget(_wrap(const NetworkErrorWidget()));
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('shows Retry button when onRetry provided, invokes callback',
        (tester) async {
      int count = 0;
      await tester.pumpWidget(_wrap(
        NetworkErrorWidget(onRetry: () => count++),
      ));
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(count, 1);
    });

    testWidgets('iconColor override is honored', (tester) async {
      const overrideColor = Color(0xFF112233);
      await tester.pumpWidget(_wrap(const NetworkErrorWidget(
        iconColor: overrideColor,
      )));
      final iconWidget =
          tester.widgetList<Icon>(find.byType(Icon)).firstWhere(
                (i) => i.size == 40,
              );
      expect(iconWidget.color, overrideColor);
    });
  });

  group('NetworkErrorWidget — loadingError factory', () {
    testWidgets('uses "Something Went Wrong" title and warning icon',
        (tester) async {
      await tester.pumpWidget(_wrap(NetworkErrorWidget.loadingError()));
      expect(find.text('Something Went Wrong'), findsOneWidget);
      expect(find.byIcon(Iconsax.warning_2), findsOneWidget);
    });

    testWidgets('honors customMessage override', (tester) async {
      await tester.pumpWidget(_wrap(NetworkErrorWidget.loadingError(
        customMessage: 'Try again later',
      )));
      expect(find.text('Try again later'), findsOneWidget);
    });
  });

  group('NetworkErrorWidget — offline factory', () {
    testWidgets('uses "You\'re Offline" title and wifi icon', (tester) async {
      await tester.pumpWidget(_wrap(NetworkErrorWidget.offline()));
      expect(find.text("You're Offline"), findsOneWidget);
      expect(find.byIcon(Iconsax.wifi_square), findsOneWidget);
    });

    testWidgets('Retry button wired when onRetry provided', (tester) async {
      int count = 0;
      await tester.pumpWidget(_wrap(
        NetworkErrorWidget.offline(onRetry: () => count++),
      ));
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(count, 1);
    });
  });

  group('InlineErrorWidget', () {
    testWidgets('renders default message', (tester) async {
      await tester.pumpWidget(_wrap(const InlineErrorWidget()));
      expect(find.text('Unable to load'), findsOneWidget);
      expect(find.byIcon(Iconsax.warning_2), findsOneWidget);
    });

    testWidgets('honors custom message', (tester) async {
      await tester.pumpWidget(_wrap(const InlineErrorWidget(
        message: 'No data',
      )));
      expect(find.text('No data'), findsOneWidget);
    });

    testWidgets('no Retry button when onRetry is null', (tester) async {
      await tester.pumpWidget(_wrap(const InlineErrorWidget()));
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('shows Retry button and invokes callback', (tester) async {
      int count = 0;
      await tester.pumpWidget(_wrap(
        InlineErrorWidget(onRetry: () => count++),
      ));
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(count, 1);
    });
  });
}
