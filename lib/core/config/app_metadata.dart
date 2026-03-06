import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Visible app branding and version metadata.
class AppMetadata {
  static const String visibleAppName = 'Rihla';

  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;

  const AppMetadata({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
  });

  factory AppMetadata.fromPackageInfo(PackageInfo info) {
    return AppMetadata(
      appName: visibleAppName,
      packageName: info.packageName,
      version: info.version,
      buildNumber: info.buildNumber,
    );
  }

  factory AppMetadata.fallback() {
    return const AppMetadata(
      appName: visibleAppName,
      packageName: '',
      version: 'Unknown',
      buildNumber: 'Unknown',
    );
  }

  String get versionLabel => '$version (Build $buildNumber)';
}

final appMetadataProvider = FutureProvider<AppMetadata>((ref) async {
  final packageInfo = await PackageInfo.fromPlatform();
  return AppMetadata.fromPackageInfo(packageInfo);
});
