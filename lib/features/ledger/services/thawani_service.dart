import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:thawani_payment/thawani_payment.dart';
import 'package:thawani_payment/models/products.dart';
import 'package:thawani_payment/models/create.dart';

import '../../../core/config/firebase_config.dart';

/// Thawani payment gateway integration for settling debts
class ThawaniService {
  static const String _apiKey = String.fromEnvironment(
    'THAWANI_API_KEY',
    defaultValue: '',
  );
  static const String _publishableKey = String.fromEnvironment(
    'THAWANI_PUBLISHABLE_KEY',
    defaultValue: '',
  );
  static const bool _testMode = String.fromEnvironment(
    'THAWANI_MODE',
    defaultValue: 'test',
  ) == 'test';

  /// Convert OMR amount to Baisa for Thawani
  /// Thawani expects amounts in the smallest currency unit (Baisa for OMR)
  /// 1 OMR = 1000 Baisa
  static int _toBaisa(Decimal amount) {
    final baisa = amount * Decimal.fromInt(1000);
    return baisa.toBigInt().toInt();
  }

  /// Initiate a Thawani payment for a settlement
  ///
  /// [context] - BuildContext for launching the payment WebView
  /// [fromName] - Name of the person paying
  /// [toName] - Name of the person receiving payment
  /// [amount] - Amount in OMR (Decimal)
  /// [settlementId] - Optional settlement ID for tracking
  /// [onSuccess] - Callback when payment is successful
  /// [onCancel] - Callback when payment is cancelled
  /// [onError] - Callback when payment fails
  static Future<void> paySettlement({
    required BuildContext context,
    required String fromName,
    required String toName,
    required Decimal amount,
    String? settlementId,
    required VoidCallback onSuccess,
    VoidCallback? onCancel,
    Function(String error)? onError,
  }) async {
    final baisaAmount = _toBaisa(amount);

    // Minimum amount check (100 Baisa = 0.100 OMR)
    if (baisaAmount < 100) {
      onError?.call('Amount too small for payment processing');
      return;
    }

    final clientId = FirebaseConfig.currentUser?.uid ?? 'anonymous';

    // ignore: unused_local_variable
    final payment = Thawani.pay(
      context,
      testMode: _testMode,
      api: _apiKey,
      pKey: _publishableKey,
      clintID: clientId,
      saveCard: true,
      products: [
        Product(
          name: 'Settlement: $fromName to $toName',
          quantity: 1,
          unitAmount: baisaAmount,
        ),
      ],
      metadata: <String, dynamic>{
        'type': 'settlement',
        'settlement_id': settlementId ?? '',
        'from_name': fromName,
        'to_name': toName,
        'amount_omr': amount.toString(),
      },
      onPaid: (Map<String, dynamic> payStatus) {
        onSuccess();
      },
      onCancelled: (Map<String, dynamic> payStatus) {
        onCancel?.call();
      },
      onError: (Map<dynamic, dynamic> e) {
        onError?.call(e.toString());
      },
      onCreate: (Create data) {},
      savedCards: (List<dynamic> data) {},
    );
  }
}
