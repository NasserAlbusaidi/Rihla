import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

enum OcrStatus {
  success,
  unavailable,
  failed,
}

/// Result of OCR processing on a receipt image.
class OcrResult {
  final OcrStatus status;
  final Decimal? amount;
  final String? description;
  final String rawText;
  final String message;

  const OcrResult({
    required this.status,
    this.amount,
    this.description,
    required this.rawText,
    required this.message,
  });
}

/// Receipt OCR service.
///
/// ML Kit was removed from the app dependency graph because it currently blocks
/// Apple Silicon iOS 26+ simulator builds. Until an iOS-compatible OCR path is
/// added back, receipts remain upload-only and the UI surfaces that explicitly.
class OcrService {
  static Future<OcrResult> processReceipt(File imageFile) async {
    if (kDebugMode) debugPrint('OCR unavailable in this build for ${imageFile.path}');
    return const OcrResult(
      status: OcrStatus.unavailable,
      rawText: '',
      message:
          'Auto-scan is temporarily unavailable in this build. The receipt will still be uploaded.',
    );
  }

  static Future<void> dispose() async {}
}
