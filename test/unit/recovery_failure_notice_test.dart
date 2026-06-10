import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/auth/services/recovery_failure_notice.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  test('write then read round-trips the code and op', () async {
    final p = await prefs();
    await writeRecoveryFailureNotice(p, code: 'invalid-action-code', op: 'recover');
    final notice = readRecoveryFailureNotice(p);
    expect(notice, isNotNull);
    expect(notice!.code, 'invalid-action-code');
    expect(notice.op, 'recover');
  });

  test('read on empty prefs is null', () async {
    expect(readRecoveryFailureNotice(await prefs()), isNull);
  });

  test('read on a malformed value is null and never throws', () async {
    SharedPreferences.setMockInitialValues({
      kRecoveryFailureKey: 'not-json{{{',
    });
    final p = await prefs();
    expect(() => readRecoveryFailureNotice(p), returnsNormally);
    expect(readRecoveryFailureNotice(p), isNull);
  });

  test('read on a json value missing keys is null', () async {
    SharedPreferences.setMockInitialValues({
      kRecoveryFailureKey: '{"code":"invalid-action-code"}',
    });
    expect(readRecoveryFailureNotice(await prefs()), isNull);
  });

  test('clear removes the marker', () async {
    final p = await prefs();
    await writeRecoveryFailureNotice(p, code: 'expired-action-code', op: 'recover');
    await clearRecoveryFailureNotice(p);
    expect(readRecoveryFailureNotice(p), isNull);
  });
}
