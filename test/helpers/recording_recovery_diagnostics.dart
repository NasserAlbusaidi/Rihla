import 'package:safar/features/auth/services/recovery_diagnostics.dart';

/// Records every diagnostics call so tests can assert on phases, codes, and —
/// critically — that no PII (email / raw uid / raw link / oobCode) leaks into
/// any breadcrumb `data` map.
class RecordingRecoveryDiagnostics implements RecoveryDiagnostics {
  final List<RecordedDiagnostic> calls = <RecordedDiagnostic>[];

  List<String> get phases => calls.map((c) => c.phase).toList();

  /// Flattened string view of every value passed in any call's `data` map plus
  /// any captured code — used to assert PII never appears.
  Iterable<String> get allValues sync* {
    for (final c in calls) {
      if (c.code != null) yield c.code!;
      for (final v in c.data.values) {
        if (v != null) yield v.toString();
      }
    }
  }

  @override
  void breadcrumb(String phase, {Map<String, Object?> data = const {}}) {
    calls.add(RecordedDiagnostic(phase: phase, data: Map.of(data)));
  }

  @override
  void captureFailure(
    String phase, {
    required String code,
    Map<String, Object?> data = const {},
  }) {
    calls.add(RecordedDiagnostic(phase: phase, code: code, data: Map.of(data)));
  }
}

class RecordedDiagnostic {
  RecordedDiagnostic({required this.phase, this.code, required this.data});
  final String phase;
  final String? code;
  final Map<String, Object?> data;
}
