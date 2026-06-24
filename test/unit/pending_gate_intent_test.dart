import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/auth/services/pending_gate_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('PendingGateIntent', () {
    test('create intent round-trips through prefs', () async {
      final intent = PendingGateIntent.create(
        groupName: 'Muscat Trip',
        displayName: 'Nasser',
        currencyCode: 'OMR',
      );
      await PendingGateIntent.save(prefs, intent);

      final read = PendingGateIntent.read(prefs);
      expect(read, isNotNull);
      expect(read!.type, 'create');
      expect(read.groupName, 'Muscat Trip');
      expect(read.displayName, 'Nasser');
      expect(read.currencyCode, 'OMR');
    });

    test('read returns null when no marker exists', () {
      expect(PendingGateIntent.read(prefs), isNull);
    });

    test('read returns null on malformed JSON and leaves no crash', () async {
      await prefs.setString(PendingGateIntent.prefsKey, '{not json');
      expect(PendingGateIntent.read(prefs), isNull);
    });

    test('read returns null on unknown type', () async {
      await prefs.setString(
        PendingGateIntent.prefsKey,
        '{"v":1,"type":"teleport","atMillis":${DateTime.now().millisecondsSinceEpoch}}',
      );
      expect(PendingGateIntent.read(prefs), isNull);
    });

    test('read returns null when the marker is older than the TTL', () async {
      final stale = DateTime.now()
          .subtract(PendingGateIntent.ttl + const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      await prefs.setString(
        PendingGateIntent.prefsKey,
        '{"v":1,"type":"create","groupName":"G","displayName":"N",'
        '"atMillis":$stale}',
      );
      expect(PendingGateIntent.read(prefs), isNull);
    });

    test('read returns a marker younger than the TTL', () async {
      final fresh = DateTime.now()
          .subtract(const Duration(minutes: 5))
          .millisecondsSinceEpoch;
      await prefs.setString(
        PendingGateIntent.prefsKey,
        '{"v":1,"type":"create","groupName":"G","displayName":"N",'
        '"atMillis":$fresh}',
      );
      expect(PendingGateIntent.read(prefs), isNotNull);
    });

    test('save overwrites an existing marker', () async {
      await PendingGateIntent.save(
        prefs,
        PendingGateIntent.create(
          groupName: 'First',
          displayName: 'A',
          currencyCode: 'OMR',
        ),
      );
      await PendingGateIntent.save(
        prefs,
        PendingGateIntent.create(
          groupName: 'G',
          displayName: 'B',
          currencyCode: 'USD',
        ),
      );
      final read = PendingGateIntent.read(prefs);
      expect(read!.type, 'create');
      expect(read.groupName, 'G');
    });

    test('clear removes the marker', () async {
      await PendingGateIntent.save(
        prefs,
        PendingGateIntent.create(
          groupName: 'G',
          displayName: 'N',
          currencyCode: 'OMR',
        ),
      );
      await PendingGateIntent.clear(prefs);
      expect(PendingGateIntent.read(prefs), isNull);
      expect(prefs.containsKey(PendingGateIntent.prefsKey), isFalse);
    });

    test('clear is a no-op when nothing is saved', () async {
      await PendingGateIntent.clear(prefs);
      expect(PendingGateIntent.read(prefs), isNull);
    });
  });
}
