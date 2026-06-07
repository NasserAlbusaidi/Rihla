// On-device integration test for the #261 PR-0b mixed-currency gate guard.
//
// PR-0b is a SERVER-only change (deleteGroup/leaveGroup/removeMember refuse a
// group whose recomputeNet currency set has size > 1). The client ships no
// change — and because every client money write hardcodes 'OMR' (#61), the app
// itself can never CREATE a mixed-currency group. So this test seeds the
// otherwise-unreachable shape directly into the Firestore emulator (REST,
// `Bearer owner`, rules bypassed) under the app's LIVE anon uid, then drives the
// real Android `cloud_functions` SDK against the emulated PR-0b callables.
//
// What it proves on a real Android device:
//   • A FAKE cross-currency zero (+10 OMR / -10 USD) reads as net-zero on the
//     currency-blind client, so the client pre-check lets it through — and the
//     server guard catches it: delete / leave / remove all throw
//     `failed-precondition`, and the group survives (the money-loss path is shut).
//   • The happy path is intact: a genuine single-currency (OMR) settled group
//     still soft-deletes (no regression from the guard).
//
// Run (Android emulator, with the suite up on default ports):
//   firebase emulators:start --only auth,firestore,functions --project rihla-safar
//   flutter test integration_test/mixed_currency_guard_test.dart \
//     -d emulator-5554 --dart-define-from-file=config.test.json

import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/config/firebase_config.dart';
import 'package:safar/main.dart' as app;

// Android emulator → host loopback. Same mapping main.dart uses for the SDKs.
const String _host = '10.0.2.2';
const String _project = 'rihla-safar';
const String _docBase =
    'http://$_host:8080/v1/projects/$_project/databases/(default)/documents';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('#261 PR-0b: server refuses delete/leave/remove on a mixed-currency group; OMR group still deletes',
      (tester) async {
    _log('--- TEST START ---');
    app.main();

    // Wait for the cold-boot anon session (_AuthGate signs in anonymously).
    final uid = await _waitForUid(tester);
    _log('anon uid = $uid');
    const member2 = 'member2-uid';

    // ───────── Group A: fake-zero MIXED currency (OMR + USD), owned by uid.
    // Mirrors deleteGroup.test.ts case 9b: each actor nets to a bare-Decimal
    // zero ACROSS currencies, so the flat-scalar gate would (without PR-0b)
    // delete a group holding real per-currency debt.
    const gMixed = 'gMixedA';
    await _seedGroup(gMixed, createdBy: uid, memberIds: [uid, member2]);
    await _seedMember(gMixed, 'm-owner', uid);
    await _seedMember(gMixed, 'm-two', member2);
    await _seedEvent(gMixed, 'e1', participantIds: [uid, member2]);
    await _seedExpense(gMixed, 'e1', 'x1',
        amountFils: 10000, currency: 'OMR', payer: uid); // 10.000 OMR
    await _seedExpense(gMixed, 'e1', 'x2',
        amountFils: 1000, currency: 'USD', payer: member2); // 10.00 USD
    _log('seeded mixed-currency group $gMixed');

    // ───────── Group B: genuine single-currency (OMR) settled group.
    // One personal-scope expense paid AND owed by uid → net 0, currencies {OMR}.
    const gOmr = 'gOmrB';
    await _seedGroup(gOmr, createdBy: uid, memberIds: [uid]);
    await _seedMember(gOmr, 'm-owner', uid);
    await _seedEvent(gOmr, 'e1', participantIds: [uid]);
    await _seedExpense(gOmr, 'e1', 'x1',
        amountFils: 5000, currency: 'OMR', payer: uid, scope: 'personal');
    _log('seeded OMR settled group $gOmr');

    final functions = FirebaseConfig.functions;

    // ───────── 1. deleteGroup(A) → failed-precondition, A survives.
    final delCode = await _expectThrowsCode(
        () => functions.httpsCallable('deleteGroup').call({'groupId': gMixed}));
    _log('deleteGroup(mixed) threw code=$delCode');
    expect(delCode, 'failed-precondition',
        reason: 'mixed-currency group must be refused by the delete gate');
    expect(await _isDeleted(gMixed), isFalse,
        reason: 'refused deleteGroup must not soft-delete the group');

    // ───────── 2. leaveGroup(A) → failed-precondition (caller=creator/member).
    final leaveCode = await _expectThrowsCode(
        () => functions.httpsCallable('leaveGroup').call({'groupId': gMixed}));
    _log('leaveGroup(mixed) threw code=$leaveCode');
    expect(leaveCode, 'failed-precondition',
        reason: 'mixed-currency group must block leave');
    expect(await _memberIds(gMixed), containsAll(<String>[uid, member2]),
        reason: 'refused leaveGroup must not drop the leaver from memberIds');

    // ───────── 3. removeMember(A, member2) → failed-precondition (caller=creator).
    final removeCode = await _expectThrowsCode(() => functions
        .httpsCallable('removeMember')
        .call({'groupId': gMixed, 'targetUserId': member2}));
    _log('removeMember(mixed) threw code=$removeCode');
    expect(removeCode, 'failed-precondition',
        reason: 'mixed-currency group must block removeMember');
    expect(await _memberIds(gMixed), contains(member2),
        reason: 'refused removeMember must not drop the target');

    // ───────── 4. HAPPY PATH: deleteGroup(B) succeeds; B is soft-deleted.
    await functions.httpsCallable('deleteGroup').call({'groupId': gOmr});
    _log('deleteGroup(OMR settled) returned OK');
    expect(await _isDeleted(gOmr), isTrue,
        reason: 'single-currency settled group must still soft-delete (no regression)');

    _log('--- TEST END: all PR-0b on-device assertions passed ---');
  });
}

// ──────────────────────────────────────────── callable helper

/// Calls [fn], expects it to throw [FirebaseFunctionsException], returns its
/// `.code`. Fails the test if no exception is thrown.
Future<String> _expectThrowsCode(Future<void> Function() fn) async {
  try {
    await fn();
  } on FirebaseFunctionsException catch (e) {
    return e.code;
  }
  fail('expected FirebaseFunctionsException, but the call succeeded');
}

// ──────────────────────────────────────────── auth wait

Future<String> _waitForUid(WidgetTester tester) async {
  // 1. Wait for app.main()'s async Firebase.initializeApp to land (accessing
  //    FirebaseAuth.instance.app throws [core/no-app] until then).
  final initDeadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(initDeadline)) {
    try {
      FirebaseAuth.instance.app;
      break;
    } catch (_) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  // 2. Give the app's own _AuthGate a brief window to restore/establish a
  //    session, pumping the tree so its FutureBuilder can progress.
  final gateDeadline = DateTime.now().add(const Duration(seconds: 12));
  while (DateTime.now().isBefore(gateDeadline)) {
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) return u.uid;
    await tester.pump(const Duration(milliseconds: 300));
  }

  // 3. Drive sign-in ourselves, bounded, so a stalled gate cannot hang the test
  //    and any auth/App-Check error surfaces in the failure message.
  try {
    final cred = await FirebaseAuth.instance
        .signInAnonymously()
        .timeout(const Duration(seconds: 30));
    return cred.user!.uid;
  } catch (e) {
    fail('anon sign-in failed/stalled: $e');
  }
}

// ──────────────────────────────────────────── Firestore-emulator REST seed

Future<void> _seedGroup(String id,
    {required String createdBy, required List<String> memberIds}) async {
  await _patch('groups/$id', {
    'id': id,
    'name': 'guard-test-$id',
    'createdBy': createdBy,
    'memberIds': memberIds,
    'modules': {'ledger': true},
    'isDeleted': false,
    'deletedAt': null,
    'createdAt': _ts('2026-01-04T00:00:00.000Z'),
  });
}

Future<void> _seedMember(String gid, String docId, String userId) async {
  await _patch('groups/$gid/members/$docId', {
    'userId': userId,
    'displayName': userId,
    'isTombstone': false,
    'joinedAt': _ts('2026-01-04T00:00:00.000Z'),
  });
}

Future<void> _seedEvent(String gid, String eid,
    {required List<String> participantIds}) async {
  await _patch('groups/$gid/events/$eid', {
    'id': eid,
    'name': 'event-$eid',
    'participantIds': participantIds,
    'modules': {'ledger': true},
    'isDeleted': false,
    'deletedAt': null,
    'createdAt': _ts('2026-01-05T00:00:00.000Z'),
  });
}

Future<void> _seedExpense(String gid, String eid, String xid,
    {required int amountFils,
    required String currency,
    required String payer,
    String scope = 'global'}) async {
  await _patch('groups/$gid/events/$eid/expenses/$xid', {
    'id': xid,
    'eventId': eid,
    'createdBy': payer,
    'payerParticipantId': payer,
    'amountFils': amountFils,
    'currency': currency,
    'description': 'expense $xid',
    'scope': scope,
    'customSplitParticipants': <String>[],
    'splitMode': 'equally',
    'splitDistribution': <String, dynamic>{},
    'isDeleted': false,
    'deletedAt': null,
    'createdAt': _ts('2026-01-06T00:00:00.000Z'),
  });
}

// ──────────────────────────────────────────── Firestore-emulator REST read

Future<bool> _isDeleted(String gid) async {
  final fields = await _get('groups/$gid');
  return (fields['isDeleted']?['booleanValue'] as bool?) ?? false;
}

Future<List<String>> _memberIds(String gid) async {
  final fields = await _get('groups/$gid');
  final values =
      (fields['memberIds']?['arrayValue']?['values'] as List<dynamic>?) ??
          const [];
  return values.map((v) => v['stringValue'] as String).toList();
}

// ──────────────────────────────────────────── REST plumbing

final HttpClient _client = HttpClient();

Future<void> _patch(String path, Map<String, dynamic> data) async {
  final uri = Uri.parse('$_docBase/$path');
  final req = await _client.patchUrl(uri);
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
  req.headers.contentType = ContentType.json;
  req.add(utf8.encode(jsonEncode({'fields': _encodeFields(data)})));
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode >= 300) {
    fail('seed PATCH $path failed: ${res.statusCode} $body');
  }
}

Future<Map<String, dynamic>> _get(String path) async {
  final uri = Uri.parse('$_docBase/$path');
  final req = await _client.getUrl(uri);
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode >= 300) {
    fail('read GET $path failed: ${res.statusCode} $body');
  }
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  return (decoded['fields'] as Map<String, dynamic>?) ?? <String, dynamic>{};
}

Map<String, dynamic> _encodeFields(Map<String, dynamic> data) =>
    data.map((k, v) => MapEntry(k, _encodeValue(v)));

Map<String, dynamic> _encodeValue(dynamic v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': v.toString()};
  if (v is double) return {'doubleValue': v};
  if (v is String) return {'stringValue': v};
  if (v is _Ts) return {'timestampValue': v.iso};
  if (v is List) {
    return {
      'arrayValue': {'values': v.map(_encodeValue).toList()}
    };
  }
  if (v is Map<String, dynamic>) {
    return {
      'mapValue': {'fields': _encodeFields(v)}
    };
  }
  throw ArgumentError('unencodable seed value: $v (${v.runtimeType})');
}

class _Ts {
  const _Ts(this.iso);
  final String iso;
}

_Ts _ts(String iso) => _Ts(iso);

void _log(String msg) {
  // ignore: avoid_print
  print('[mixed_currency_guard] $msg');
}
