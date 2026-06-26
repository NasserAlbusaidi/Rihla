import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #636 — guard: release/CI build invocations must keep icon tree-shaking ON.
///
/// The iconsax icon font is ~1.3MB. Every usage in `lib/` is a
/// `static const IconData` reference, so Flutter's release build subsets it
/// down to only the glyphs actually used — **but only because
/// `--tree-shake-icons` is ON by default**. Passing `--no-tree-shake-icons`
/// to any `flutter build` silently re-inflates every AAB/APK by the full font,
/// with nothing else catching it.
///
/// This test scans the build and CI scripts that invoke `flutter build` and
/// FAILS if any of them contains `--no-tree-shake-icons`. It currently passes
/// (the flag exists nowhere in the repo); it would go red the moment someone
/// disables icon tree-shaking in a build path.
void main() {
  const disableFlag = '--no-tree-shake-icons';

  /// Files that invoke (or document the canonical) `flutter build` commands.
  /// Adding a new release/QA build path? List its script here.
  const scannedFiles = <String>[
    '.github/workflows/release_android.yml',
    '.github/workflows/readiness_check.yml',
    'tool/check_release_readiness.sh',
    'tool/print_android_qa_handoff.sh',
  ];

  String read(String path) => File(path).readAsStringSync();

  bool disablesTreeShake(String contents) => contents.contains(disableFlag);

  test('no scanned build/CI script disables icon tree-shaking (#636)', () {
    for (final path in scannedFiles) {
      final file = File(path);
      expect(
        file.existsSync(),
        isTrue,
        reason:
            '$path is in the tree-shake guard scan list but does not exist — '
            'update scannedFiles in tree_shake_icons_guard_test.dart if a '
            'build script was renamed or removed.',
      );
      expect(
        disablesTreeShake(file.readAsStringSync()),
        isFalse,
        reason:
            '$path contains $disableFlag. Never pass $disableFlag to a release '
            'build — it ships the full ~1.3MB iconsax font unsubsetted (#636). '
            'Tree-shaking is on by default; leave it on.',
      );
    }
  });

  test('every workflow and tool script keeps icon tree-shaking on (#636)', () {
    final scanRoots = <Directory>[
      Directory('.github/workflows'),
      Directory('tool'),
    ];

    for (final dir in scanRoots) {
      expect(dir.existsSync(), isTrue, reason: '${dir.path} must exist');
      final offenders = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.yml') ||
                file.path.endsWith('.yaml') ||
                file.path.endsWith('.sh'),
          )
          .where((file) => disablesTreeShake(file.readAsStringSync()))
          .map((file) => file.path)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            'These files disable icon tree-shaking with $disableFlag and would '
            'ship the full iconsax font (#636): ${offenders.join(', ')}',
      );
    }
  });

  test('guard predicate catches an injected --no-tree-shake-icons flag', () {
    // RED demonstration: prove the scan predicate flags a build line that
    // disables tree-shaking. If this assertion ever needs to change, the guard
    // above is no longer detecting the regression it claims to.
    const injected = 'flutter build appbundle --release '
        '$disableFlag --dart-define-from-file=config.json';

    expect(disablesTreeShake(injected), isTrue);
    // And the clean form (what the real scripts contain) passes:
    const clean = 'flutter build appbundle --release '
        '--dart-define-from-file=config.json';
    expect(disablesTreeShake(clean), isFalse);
  });

  test('scanned scripts still actually invoke flutter build (#636)', () {
    // Guard against silent bypass: if every `flutter build` moves out of these
    // files, the tree-shake scan would pass vacuously. Pin that the build
    // invocations the guard protects are still present where we scan.
    expect(
      read('.github/workflows/release_android.yml'),
      contains('flutter build appbundle'),
    );
    expect(
      read('tool/check_release_readiness.sh'),
      contains('flutter build appbundle'),
    );
    expect(
      read('tool/print_android_qa_handoff.sh'),
      contains('flutter build apk'),
    );
  });
}
