import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('Android release workflow requires external release confirmations', () {
    final workflow = read('.github/workflows/release_android.yml');

    expect(workflow, contains('Release readiness confirmations'));
    expect(workflow, contains('RIHLA_BACKEND_RELEASE_READY'));
    expect(workflow, contains('RIHLA_APP_CHECK_READY'));
    expect(workflow, contains('RIHLA_REAL_DEVICE_QA_READY'));
    expect(workflow, contains('RIHLA_RELEASE_APPROVED_SHA'));
    expect(workflow, contains('GITHUB_SHA'));
    expect(
      workflow,
      contains('Firebase backend and Hosting production checks'),
    );
    expect(workflow, contains('physical-device QA matrix passes'));
  });

  test('real-device QA gate requires completed matrix evidence', () {
    final gate = read('tool/check_real_device_qa_gate.sh');
    final runbook = read('docs/REAL-DEVICE-QA.md');

    expect(gate, contains('check_matrix_results'));
    expect(gate, contains('docs/REAL-DEVICE-QA.md'));
    expect(gate, contains('Real-device QA matrix is incomplete'));
    expect(runbook, contains('Every RD-01 through RD-09 row'));
    expect(runbook, contains('RD-09 | Arabic RTL golden path'));
    expect(runbook, contains('Evidence cell must contain a concrete artifact'));
  });

  test('release readiness runs GitHub release governance gate', () {
    final readiness = read('tool/check_release_readiness.sh');
    final governance = read('tool/check_github_release_governance.sh');

    expect(readiness, contains('GitHub release governance'));
    expect(readiness, contains('tool/check_github_release_governance.sh'));
    expect(governance, contains('RIHLA_RELEASE_APPROVED_SHA'));
    expect(governance, contains('RIHLA_RELEASE_TARGET_SHA'));
    expect(governance, contains('RIHLA_RELEASE_PROTECTED_BRANCH'));
    expect(governance, contains(r'branches/${PROTECTED_BRANCH}/protection'));
    expect(governance, contains('required_status_checks'));
    expect(governance, contains('readiness'));
  });
}
