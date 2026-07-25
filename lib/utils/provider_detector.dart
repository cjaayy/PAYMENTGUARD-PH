/// Utility to automatically detect payment provider (GCash, Maya, MariBank, or Unknown Provider)
/// from raw text (SMS body or OCR recognized text) and sender header.
class ProviderDetector {
  /// Detects payment provider from text and optional header.
  static String detect(String rawText, {String? senderHeader}) {
    final combined = '${senderHeader ?? ''} $rawText'.toLowerCase();

    // 1. MariBank detection (contains "maribank" or "mb")
    if (combined.contains('maribank') ||
        RegExp(r'\bmb\b', caseSensitive: false).hasMatch(combined)) {
      return 'MariBank';
    }

    // 2. Maya / PayMaya detection
    if (combined.contains('maya') || combined.contains('paymaya')) {
      return 'Maya';
    }

    // 3. GCash detection
    if (combined.contains('gcash') ||
        combined.contains('express send') ||
        combined.contains('gsave') ||
        combined.contains('gcredit')) {
      return 'GCash';
    }

    // 4. Default fallback
    return 'Unknown Provider';
  }
}
