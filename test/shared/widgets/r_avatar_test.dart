import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/shared/widgets/r_avatar.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('RAvatar — initials', () {
    testWidgets('extracts first + last word initials', (tester) async {
      await tester.pumpWidget(_wrap(const RAvatar(name: 'Layla Hassan')));
      expect(find.text('LH'), findsOneWidget);
    });

    testWidgets('single word uses first letter only', (tester) async {
      await tester.pumpWidget(_wrap(const RAvatar(name: 'Nasser')));
      expect(find.text('N'), findsOneWidget);
    });

    testWidgets('empty name renders ?', (tester) async {
      await tester.pumpWidget(_wrap(const RAvatar(name: '   ')));
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('three-word name uses first and last only', (tester) async {
      await tester.pumpWidget(
        _wrap(const RAvatar(name: 'Maria Elena Garcia')),
      );
      expect(find.text('MG'), findsOneWidget);
    });
  });

  group('RAvatar — sizing', () {
    testWidgets('renders at requested diameter', (tester) async {
      await tester.pumpWidget(_wrap(const RAvatar(name: 'X', size: 64)));
      final box = tester.getSize(find.byType(RAvatar));
      expect(box.width, 64.0);
      expect(box.height, 64.0);
    });
  });

  group('RAvatar — deterministic colors', () {
    Color bgColor(WidgetTester tester) {
      // RAvatar wraps a Container with BoxDecoration whose color is the
      // background. There may be ancestor Containers (Scaffold body) so we
      // scope the search to the avatar subtree.
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(RAvatar),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      return decoration.color!;
    }

    testWidgets('same name renders same color across rebuilds', (tester) async {
      await tester.pumpWidget(_wrap(const RAvatar(name: 'Layla Hassan')));
      final firstColor = bgColor(tester);

      // Pump again with a fresh widget tree to confirm the hash-derived
      // slot is stable across instances, not memoized.
      await tester.pumpWidget(_wrap(const RAvatar(name: 'Layla Hassan')));
      expect(bgColor(tester), firstColor);
    });

    testWidgets('explicit hue overrides name hash', (tester) async {
      await tester.pumpWidget(_wrap(const RAvatar(name: 'X', hue: 0)));
      // Slot 0 background is #DCE6EC (harbor-blue) per the journal palette.
      expect(bgColor(tester), const Color(0xFFDCE6EC));
    });
  });

  group('RAvatarStack', () {
    testWidgets('renders one avatar per name up to max', (tester) async {
      await tester.pumpWidget(
        _wrap(const RAvatarStack(
          names: ['Layla', 'Omar', 'Yasmin'],
          max: 4,
        )),
      );
      expect(find.byType(RAvatar), findsNWidgets(3));
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('shows +N chip when names exceed max', (tester) async {
      await tester.pumpWidget(
        _wrap(const RAvatarStack(
          names: ['A B', 'C D', 'E F', 'G H', 'I J', 'K L'],
          max: 3,
        )),
      );
      expect(find.byType(RAvatar), findsNWidgets(3));
      expect(find.text('+3'), findsOneWidget);
    });

    testWidgets('empty names list renders nothing', (tester) async {
      await tester.pumpWidget(_wrap(const RAvatarStack(names: [])));
      expect(find.byType(RAvatar), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    });
  });

  group('RAvatarStack — RTL start-anchoring (#967)', () {
    testWidgets('avatars + overflow chip anchor to the start (right) edge '
        'with mirrored overlap order', (tester) async {
      await tester.pumpWidget(
        _wrap(const Directionality(
          textDirection: TextDirection.rtl,
          child: RAvatarStack(
            names: ['Alice', 'Bob', 'Cara', 'Dan', 'Eve', 'Fay'],
            max: 3,
          ),
        )),
      );

      final a0 = tester.getRect(find.byType(RAvatar).at(0));
      final a1 = tester.getRect(find.byType(RAvatar).at(1));
      final a2 = tester.getRect(find.byType(RAvatar).at(2));
      final chip = tester.getRect(find.text('+3'));

      // Start = right in RTL: the first avatar hugs the right (start) edge,
      // each later avatar sits further left, and the +N chip is furthest from
      // the start. A non-directional Positioned(left:) would invert this.
      expect(a0.left, greaterThan(a1.left));
      expect(a1.left, greaterThan(a2.left));
      expect(a2.left, greaterThan(chip.left));
    });
  });
}
