import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/trip/models/trip_model.dart';

void main() {
  group('Trip.fromJson back-compat', () {
    test('tolerates legacy currency key after Phase 39 strip', () {
      final trip = Trip.fromJson({
        'id': 't1',
        'name': 'Test',
        'invite_code': 'ABC',
        'leader_id': 'u1',
        'modules': <String, dynamic>{},
        'created_at': '2026-04-26T00:00:00.000Z',
        'icon': 'airplane',
        // Legacy keys that pre-Phase-39 docs may still carry — must be silently ignored.
        'currency': 'USD',
      });
      expect(trip.id, 't1');
      expect(trip.name, 'Test');
      // No assertion on currency — field doesn't exist on Trip anymore.
    });
  });

  group('TripModules.fromJson back-compat', () {
    test('tolerates legacy gear/docs/logistics/memories keys', () {
      final modules = TripModules.fromJson(<String, dynamic>{
        'gear': true,
        'docs': true,
        'logistics': true,
        'memories': true,
      });
      // Surviving fields default; legacy keys are silently dropped.
      expect(modules, isA<TripModules>());
    });
  });
}
