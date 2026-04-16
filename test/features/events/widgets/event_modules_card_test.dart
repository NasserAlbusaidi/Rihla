import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/widgets/event_modules_card.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

const _allOn = EventModules(
  ledger: true,
  gear: true,
  logistics: true,
  vault: true,
  memories: true,
);

const _allOff = EventModules(
  ledger: false,
  gear: false,
  logistics: false,
  vault: false,
  memories: false,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('EventModulesCard', () {
    testWidgets('renders one toggle row per module', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EventModulesCard(
            modules: _allOn,
            onModulesChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Ledger'), findsOneWidget);
      expect(find.text('Gear'), findsOneWidget);
      expect(find.text('Logistics'), findsOneWidget);
      expect(find.text('Vault'), findsOneWidget);
      expect(find.text('Memories'), findsOneWidget);
    });

    testWidgets('renders 5 Switch widgets', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EventModulesCard(
            modules: _allOn,
            onModulesChanged: (_) {},
          ),
        ),
      );

      expect(find.byType(Switch), findsNWidgets(5));
    });

    testWidgets('calls onModulesChanged with updated value when toggle flipped',
        (tester) async {
      EventModules? received;

      await tester.pumpWidget(
        _wrap(
          EventModulesCard(
            modules: _allOff,
            onModulesChanged: (m) => received = m,
          ),
        ),
      );

      // Tap the Gear switch (second switch, index 1)
      final switches = find.byType(Switch);
      await tester.tap(switches.at(1)); // Gear
      expect(received, isNotNull);
      expect(received!.gear, isTrue,
          reason: 'Gear should be toggled on');
      // Other fields unchanged
      expect(received!.ledger, isFalse);
      expect(received!.logistics, isFalse);
    });

    testWidgets('switch states reflect module values', (tester) async {
      const modules = EventModules(
        ledger: true,
        gear: false,
        logistics: true,
        vault: false,
        memories: true,
      );

      await tester.pumpWidget(
        _wrap(
          EventModulesCard(
            modules: modules,
            onModulesChanged: (_) {},
          ),
        ),
      );

      final switches =
          tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches[0].value, isTrue,  reason: 'Ledger on');
      expect(switches[1].value, isFalse, reason: 'Gear off');
      expect(switches[2].value, isTrue,  reason: 'Logistics on');
      expect(switches[3].value, isFalse, reason: 'Vault off');
      expect(switches[4].value, isTrue,  reason: 'Memories on');
    });
  });
}
