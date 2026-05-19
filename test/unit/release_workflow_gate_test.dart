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
    expect(runbook, isNot(contains('Two paths disagree')));
    expect(runbook, isNot(contains('never invokes the matrix script')));
    expect(runbook, contains('`tool/release.sh` runs the consolidated audit'));
  });

  test(
    'Android-only real-device gate requires two physical Android devices',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'rihla-flutter-stub-',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final flutterStub = File('${tempDir.path}/flutter')
        ..writeAsStringSync('''
#!/usr/bin/env bash
if [ "\$1" = "devices" ] && [ "\$2" = "--machine" ]; then
  cat <<'JSON'
[
  {
    "name": "Pixel QA",
    "id": "pixel-qa",
    "targetPlatform": "android-arm64",
    "emulator": false
  }
]
JSON
  exit 0
fi
echo "unexpected flutter invocation: \$*" >&2
exit 64
''');
      await Process.run('chmod', ['+x', flutterStub.path]);

      final result = await Process.run(
        'bash',
        ['tool/check_real_device_qa_gate.sh'],
        environment: {
          'PATH': '${tempDir.path}:${Platform.environment['PATH']}',
          'RIHLA_SKIP_IOS_QA': 'yes',
        },
      );

      expect(result.exitCode, isNot(0));
      expect(
        '${result.stdout}\n${result.stderr}',
        contains('At least two physical Android devices required'),
      );
    },
  );

  test('release readiness runs GitHub release governance gate', () {
    final readiness = read('tool/check_release_readiness.sh');
    final governance = read('tool/check_github_release_governance.sh');
    final productionReadiness = read('docs/PRODUCTION-READINESS.md');

    expect(readiness, contains('GitHub release governance'));
    expect(readiness, contains('tool/check_github_release_governance.sh'));
    expect(readiness, contains('RIHLA_SKIP_IOS_QA'));
    expect(
      productionReadiness,
      contains(
        'RIHLA_SKIP_IOS_QA=yes RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/check_release_readiness.sh',
      ),
    );
    expect(
      productionReadiness,
      contains('main branch protection is configured'),
    );
    expect(productionReadiness, isNot(contains('main is not protected')));
    expect(governance, contains('RIHLA_RELEASE_APPROVED_SHA'));
    expect(governance, contains('RIHLA_RELEASE_TARGET_SHA'));
    expect(governance, contains('RIHLA_RELEASE_PROTECTED_BRANCH'));
    expect(governance, contains(r'branches/${PROTECTED_BRANCH}/protection'));
    expect(governance, contains('required_status_checks'));
    expect(governance, contains('readiness'));
  });

  test('release helper runs readiness before tagging and pushing', () {
    final release = read('tool/release.sh');
    final readme = read('README.md');
    final configuration = read('docs/CONFIGURATION.md');

    final commitIndex = release.indexOf(
      r'git commit -m "chore(release): $NEW_TAG"',
    );
    final readinessIndex = release.indexOf('tool/check_release_readiness.sh');
    final tagIndex = release.indexOf(r'git tag -a "$NEW_TAG"');
    final pushIndex = release.indexOf(r'git push origin "$NEW_TAG"');

    expect(release, contains(r'RIHLA_RELEASE_TARGET_SHA="$RELEASE_SHA"'));
    expect(release, contains('RIHLA_SKIP_IOS_QA=yes ./tool/release.sh patch'));
    expect(readme, contains('RIHLA_SKIP_IOS_QA=yes ./tool/release.sh patch'));
    expect(
      configuration,
      contains('RIHLA_SKIP_IOS_QA=yes ./tool/release.sh patch'),
    );
    expect(release, contains('require_clean_worktree'));
    expect(release, contains('git diff --quiet'));
    expect(release, contains('git diff --cached --quiet'));
    expect(release, contains('git ls-files --others --exclude-standard'));
    expect(release, contains('release can be tied to an exact commit'));
    expect(commitIndex, greaterThanOrEqualTo(0));
    expect(readinessIndex, greaterThan(commitIndex));
    expect(tagIndex, greaterThan(readinessIndex));
    expect(pushIndex, greaterThan(tagIndex));
  });

  test('Firebase deploy helper refuses dirty tracked worktrees', () {
    final deploy = read('tool/deploy_firebase_backend.sh');

    expect(deploy, contains('require_clean_worktree'));
    expect(deploy, contains('git diff --quiet'));
    expect(deploy, contains('git diff --cached --quiet'));
    expect(deploy, contains('git ls-files --others --exclude-standard'));
    expect(deploy, contains('RIHLA_ALLOW_DIRTY_FIREBASE_DEPLOY'));
    expect(deploy, contains('production can be tied to an exact commit'));
  });
}
