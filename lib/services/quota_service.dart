import 'package:flutter/foundation.dart';

class QuotaService {
  static final QuotaService _instance = QuotaService._internal();
  factory QuotaService() => _instance;
  QuotaService._internal();

  static final ValueNotifier<bool> isQuotaExhaustedNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<String?> quotaExhaustedReasonNotifier = ValueNotifier<String?>(null);
  static final ValueNotifier<DateTime?> quotaExhaustedTimestampNotifier = ValueNotifier<DateTime?>(null);

  static bool get isQuotaExhausted => isQuotaExhaustedNotifier.value;

  /// Check if an exception/error is a Firebase quota exhaustion error
  static bool isQuotaError(dynamic error) {
    if (error == null) return false;
    final errStr = error.toString().toLowerCase();
    return errStr.contains('resource-exhausted') ||
        errStr.contains('quota-exceeded') ||
        errStr.contains('resource_exhausted') ||
        errStr.contains('quota exceeded') ||
        errStr.contains('over quota') ||
        errStr.contains('quota limit') ||
        errStr.contains('usage limit');
  }

  /// Record that quota has been exceeded
  static void recordQuotaExceeded({String? reason, dynamic error}) {
    final effectiveReason = reason ?? (error != null ? error.toString() : 'Firebase Cloud Daily Quota Exceeded (50,000 Reads Limit Reached)');
    isQuotaExhaustedNotifier.value = true;
    quotaExhaustedReasonNotifier.value = effectiveReason;
    quotaExhaustedTimestampNotifier.value = DateTime.now();
    debugPrint('🚨 [QuotaService] Cloud Quota Exhaustion Detected: $effectiveReason');
  }

  /// Record a successful cloud operation to recover state after midnight reset
  static void recordSuccess() {
    if (isQuotaExhaustedNotifier.value) {
      final lastExhausted = quotaExhaustedTimestampNotifier.value;
      if (lastExhausted == null || DateTime.now().difference(lastExhausted).inMinutes > 15) {
        isQuotaExhaustedNotifier.value = false;
        quotaExhaustedReasonNotifier.value = null;
        debugPrint('✅ [QuotaService] Firestore connection restored / quota reset.');
      }
    }
  }

  /// Reset manual override (for admin testing/recovery)
  static void resetState() {
    isQuotaExhaustedNotifier.value = false;
    quotaExhaustedReasonNotifier.value = null;
    quotaExhaustedTimestampNotifier.value = null;
  }
}
