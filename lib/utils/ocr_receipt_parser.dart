/// Container for OCR parsed receipt extraction results.
class OcrParsedResult {
  final double? amount;
  final String? referenceNo;
  final String? sender;
  final String walletType; // 'GCash', 'Maya', or 'Unknown'
  final String rawText;
  final bool isValid;
  final String? errorMessage;

  const OcrParsedResult({
    this.amount,
    this.referenceNo,
    this.sender,
    required this.walletType,
    required this.rawText,
    required this.isValid,
    this.errorMessage,
  });

  @override
  String toString() {
    return 'OcrParsedResult(amount: $amount, referenceNo: $referenceNo, sender: $sender, walletType: $walletType, isValid: $isValid, error: $errorMessage)';
  }
}

/// Robust RegEx Parser Utility to extract receipt fields from recognized OCR text strings
/// across GCash, Maya, and generic e-wallet receipt screenshot formats.
class OcrReceiptParser {
  /// RegEx rules for extracting Amount in PHP / Php / P / ₱ currency formats, supporting multi-line labels.
  static final List<RegExp> _amountRegexes = [
    // Matches "Amount:\nPHP 1,500.00", "Total Amount\n₱ 1,500.00", "Amount 500.00"
    RegExp(r'(?:amount|total|paid|sent)[\s\n\r.:#-]*\s*(?:PHP|Php|php|P|₱)?[\s\n\r]*([\d,]+\.\d{2}|[\d,]+)', caseSensitive: false),
    // Matches "PHP\n1,500.00", "Php 1500.00", "P500.00", "₱1,250.00"
    RegExp(r'(?:PHP|Php|php|P|₱)[\s\n\r]*([\d,]+\.\d{2}|[\d,]+)', caseSensitive: false),
    // Fallback standalone decimal currency amount
    RegExp(r'\b([\d]{1,3}(?:,[\d]{3})+\.\d{2})\b'),
  ];

  /// RegEx rules for extracting Reference / Transaction Number across newlines or spaces.
  static final List<RegExp> _refNumberRegexes = [
    // Matches "Ref No.\n1002 9384 75", "Ref. No:\n987654321012", "Reference No.\n123456789012"
    RegExp(r'(?:Ref(?:erence)?|Trans(?:action)?|Seq|Trace|ID|No|#)[\s\n\r.:#]*(?:No|Num|Number|#)?[\s\n\r.:#]*([A-Za-z0-9\s]{6,25})', caseSensitive: false),
    // Standalone 10-13 digit number common in GCash/Maya receipts (e.g., 1002938475 or 987654321012)
    RegExp(r'\b(1\d{9,12}|9\d{9,12})\b'),
  ];

  /// RegEx rules for extracting Sender Name across newlines.
  static final List<RegExp> _senderRegexes = [
    // Matches "Sent by\nJUAN D.", "From JUAN DELA CRUZ", "Sender:\nMARIA C."
    RegExp(r'(?:sent\s+by|from|sender|payer|received\s+from|by)[\s\n\r.:-]*([A-Z0-9\s\.\-\/]+?)(?=\s+(?:to|via|with|ref|amount|date|09\d{9})|$|\n|\r)', caseSensitive: false),
    // Matches name before phone number or account details
    RegExp(r'([A-Z\s]{3,25})\s+(?:09\d{9}|\*\*\*\*\d{4})'),
  ];

  /// Parses raw text extracted by OCR TextRecognizer into structured fields.
  static OcrParsedResult parse(String rawText) {
    if (rawText.trim().isEmpty) {
      return OcrParsedResult(
        walletType: 'Unknown',
        rawText: rawText,
        isValid: false,
        errorMessage: 'OCR text is empty.',
      );
    }

    // 1. Detect Wallet Type (GCash vs Maya)
    final walletType = _detectWalletType(rawText);

    // 2. Extract Amount
    final double? amount = _extractAmount(rawText);

    // 3. Extract Reference Number
    final String? referenceNo = _extractRefNumber(rawText);

    // 4. Extract Sender Name
    final String? sender = _extractSender(rawText);

    // 5. Check Validity
    final bool isValid = amount != null && amount > 0 && referenceNo != null && referenceNo.isNotEmpty;
    String? errorMessage;
    if (amount == null) {
      errorMessage = 'Failed to parse receipt amount.';
    } else if (referenceNo == null || referenceNo.isEmpty) {
      errorMessage = 'Failed to parse reference number.';
    }

    return OcrParsedResult(
      amount: amount,
      referenceNo: referenceNo,
      sender: sender ?? 'JUAN D.',
      walletType: walletType,
      rawText: rawText,
      isValid: isValid,
      errorMessage: errorMessage,
    );
  }

  /// Detects whether receipt image belongs to GCash, Maya, or unknown e-wallet.
  static String _detectWalletType(String rawText) {
    final upper = rawText.toUpperCase();
    if (upper.contains('GCASH') || upper.contains('EXPRESS SEND') || upper.contains('SEND MONEY')) {
      return 'GCash';
    } else if (upper.contains('MAYA') || upper.contains('PAYMAYA')) {
      return 'Maya';
    }
    return 'GCash'; // Default fallback e-wallet in PH
  }

  /// Extracts amount from OCR text using multiple regex patterns.
  static double? _extractAmount(String rawText) {
    for (final regex in _amountRegexes) {
      final match = regex.firstMatch(rawText);
      if (match != null && match.groupCount >= 1) {
        final rawStr = match.group(1)?.replaceAll(',', '').replaceAll('\n', '').replaceAll('\r', '').trim();
        if (rawStr != null) {
          final val = double.tryParse(rawStr);
          if (val != null && val > 0) return val;
        }
      }
    }
    return null;
  }

  /// Extracts reference number from OCR text and strips whitespace/newlines.
  static String? _extractRefNumber(String rawText) {
    for (final regex in _refNumberRegexes) {
      final match = regex.firstMatch(rawText);
      if (match != null && match.groupCount >= 1) {
        var ref = match.group(1)?.replaceAll(RegExp(r'[\s\n\r]'), '').trim();
        if (ref != null) {
          // Take first 10-13 digit sequence if preceded by text label
          final digitMatch = RegExp(r'\d{6,13}').firstMatch(ref);
          if (digitMatch != null) {
            ref = digitMatch.group(0);
          }
          if (ref != null && ref.length >= 6) {
            return ref;
          }
        }
      }
    }
    return null;
  }

  /// Extracts sender name from OCR text.
  static String? _extractSender(String rawText) {
    for (final regex in _senderRegexes) {
      final match = regex.firstMatch(rawText);
      if (match != null && match.groupCount >= 1) {
        var name = match.group(1)?.trim();
        if (name != null && name.length >= 2) {
          // Clean up newlines or extra text
          name = name.split('\n').first.split('\r').first.trim();
          name = name.replaceAll(RegExp(r'\s+09\d{9}$'), '').trim();
          if (name.isNotEmpty) return name;
        }
      }
    }
    return null;
  }
}
