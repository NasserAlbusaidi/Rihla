import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('Android release workflow requires external release confirmations', () {
    final workflow = read('.github/workflows/release_android.yml');
    final readme = read('README.md');
    final configuration = read('docs/CONFIGURATION.md');
    final productionReadiness = read('docs/PRODUCTION-READINESS.md');
    final normalizedProductionReadiness = productionReadiness.replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

    expect(workflow, contains('Release ref validation'));
    expect(workflow, contains('GITHUB_REF_TYPE'));
    expect(workflow, contains('refs/tags/v*'));
    expect(workflow, contains('git fetch --no-tags origin main'));
    expect(workflow, contains('git merge-base --is-ancestor'));
    expect(workflow, contains('origin/main'));
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
    expect(readme, contains('refuses non-`v*` refs'));
    expect(
      configuration,
      contains('manual dispatch must target the release tag'),
    );
    expect(
      normalizedProductionReadiness,
      contains('tag commit is contained in `origin/main`'),
    );
  });

  test('real-device QA gate requires completed matrix evidence', () {
    final gate = read('tool/check_real_device_qa_gate.sh');
    final runbook = read('docs/REAL-DEVICE-QA.md');
    final normalizedRunbook = runbook.replaceAll(RegExp(r'\s+'), ' ');

    expect(gate, contains('check_matrix_results'));
    expect(gate, contains('docs/REAL-DEVICE-QA.md'));
    expect(gate, contains('Real-device QA matrix is incomplete'));
    expect(runbook, contains('Every RD-01 through RD-09 row'));
    expect(runbook, contains('RD-09 | Arabic RTL golden path'));
    expect(
      normalizedRunbook,
      contains('Evidence cell must contain a concrete artifact'),
    );
    expect(
      normalizedRunbook,
      contains('In Android-only mode, iOS cells may start with `Deferred`'),
    );
    expect(
      normalizedRunbook,
      isNot(
        contains(
          'For release, both iOS and Android cells must start with `Pass`',
        ),
      ),
    );
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

  test('Firebase emulator gates use the isolated runner', () {
    final readiness = read('tool/check_release_readiness.sh');
    final emulatorRunner = read('tool/run_firebase_emulator_tests.sh');
    final functionsPackage = read('functions/package.json');
    final readinessWorkflow = read('.github/workflows/readiness_check.yml');
    final releaseWorkflow = read('.github/workflows/release_android.yml');
    final productionReadiness = read('docs/PRODUCTION-READINESS.md');

    expect(emulatorRunner, contains('RIHLA_FIRESTORE_EMULATOR_PORT:-18080'));
    expect(emulatorRunner, contains('RIHLA_AUTH_EMULATOR_PORT:-19099'));
    expect(emulatorRunner, contains(r'${TEMP_FILES[@]-}'));
    expect(emulatorRunner, contains('FIREBASE_TOOLS_VERSION:-15.8.0'));
    expect(
      emulatorRunner,
      contains(r'firebase-tools@${FIREBASE_TOOLS_VERSION}'),
    );
    expect(emulatorRunner, isNot(contains('.XXXXXX.json')));
    expect(
      functionsPackage,
      contains(
        '"test:emulator": "bash ../tool/run_firebase_emulator_tests.sh"',
      ),
    );
    expect(readiness, contains('bash tool/run_firebase_emulator_tests.sh'));
    expect(
      readinessWorkflow,
      contains('npm --prefix functions run test:emulator'),
    );
    expect(
      releaseWorkflow,
      contains('npm --prefix functions run test:emulator'),
    );
    expect(
      productionReadiness,
      contains('npm --prefix functions run test:emulator'),
    );
    expect(
      readiness,
      isNot(contains('npm20 --prefix functions run test:emulator')),
    );
  });

  test('README coverage gate matches the enforced 80 percent threshold', () {
    final readme = read('README.md');
    final readiness = read('.github/workflows/readiness_check.yml');
    final releaseWorkflow = read('.github/workflows/release_android.yml');
    final releaseAudit = read('tool/check_release_readiness.sh');

    expect(readiness, contains('coverage >= 80.0'));
    expect(releaseWorkflow, contains('coverage >= 80.0'));
    expect(releaseAudit, contains('coverage >= 80.0'));
    expect(readme, contains('80% raw line coverage'));
    expect(readme, isNot(contains('temporarily 70%')));
  });

  test('production readiness does not mark verified Hosting files stale', () {
    final productionReadiness = read('docs/PRODUCTION-READINESS.md');

    expect(
      productionReadiness,
      contains('Firebase Hosting invite/auth link files are deployed'),
    );
    expect(productionReadiness, isNot(contains('deployed copies are stale')));
    expect(
      productionReadiness,
      isNot(contains('still tracked as a release blocker below')),
    );
  });

  test('release helper runs readiness before tagging and pushing', () {
    final release = read('tool/release.sh');
    final readme = read('README.md');
    final configuration = read('docs/CONFIGURATION.md');

    final commitIndex = release.indexOf(
      r'git commit -m "chore(release): $NEW_TAG"',
    );
    final postCommitCleanIndex = release.indexOf(
      'require_clean_worktree',
      commitIndex,
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
    expect(postCommitCleanIndex, greaterThan(commitIndex));
    expect(postCommitCleanIndex, lessThan(readinessIndex));
    expect(readinessIndex, greaterThan(commitIndex));
    expect(tagIndex, greaterThan(readinessIndex));
    expect(pushIndex, greaterThan(tagIndex));
  });

  test('Firebase deploy helper refuses dirty tracked worktrees', () {
    final deploy = read('tool/deploy_firebase_backend.sh');

    final buildIndex = deploy.indexOf('npm20 --prefix functions run build');
    final postBuildCleanIndex = deploy.indexOf(
      'require_clean_worktree',
      buildIndex,
    );
    final deployIndex = deploy.indexOf(
      r'firebase-tools@${FIREBASE_TOOLS_VERSION}',
    );

    expect(deploy, contains('require_clean_worktree'));
    expect(deploy, contains('git diff --quiet'));
    expect(deploy, contains('git diff --cached --quiet'));
    expect(deploy, contains('git ls-files --others --exclude-standard'));
    expect(deploy, contains('RIHLA_ALLOW_DIRTY_FIREBASE_DEPLOY'));
    expect(deploy, contains('production can be tied to an exact commit'));
    expect(buildIndex, greaterThanOrEqualTo(0));
    expect(postBuildCleanIndex, greaterThan(buildIndex));
    expect(postBuildCleanIndex, lessThan(deployIndex));
    expect(deployIndex, greaterThan(buildIndex));
  });
}
