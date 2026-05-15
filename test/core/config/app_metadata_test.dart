import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:safar/core/config/app_metadata.dart';

void main() {
  group('AppMetadata', () {
    test('visibleAppName is "Rihla"', () {
      expect(AppMetadata.visibleAppName, 'Rihla');
    });

    test('fromPackageInfo copies version, buildNumber, packageName', () {
      final info = PackageInfo(
        appName: 'irrelevant',
        packageName: 'com.safar.safar',
        version: '1.2.0',
        buildNumber: '12',
      );
      final metadata = AppMetadata.fromPackageInfo(info);

      expect(metadata.appName, 'Rihla');
      expect(metadata.packageName, 'com.safar.safar');
      expect(metadata.version, '1.2.0');
      expect(metadata.buildNumber, '12');
    });

    test('fallback gives stable Unknown placeholders', () {
      final metadata = AppMetadata.fallback();
      expect(metadata.appName, 'Rihla');
      expect(metadata.packageName, '');
      expect(metadata.version, 'Unknown');
      expect(metadata.buildNumber, 'Unknown');
    });

    test('versionLabel formats version + build', () {
      const metadata = AppMetadata(
        appName: 'Rihla',
        packageName: 'com.safar.safar',
        version: '1.2.0',
        buildNumber: '12',
      );
      expect(metadata.versionLabel, '1.2.0 (Build 12)');
    });
  });
}
