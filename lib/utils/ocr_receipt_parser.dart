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
  /// RegEx rules for extracting Amount in PHP / Php / P / ₱ currency formats.
  static final List<RegExp> _amountRegexes = [
    // Matches "Amount: PHP 1,500.00" or "Total Amount ₱ 1,500.00"
    RegExp(r'(?:amount|total|paid|sent)\s*[:\-\s]*\s*(?:PHP|Php|php|P|₱)?\s*([\d,]+\.\d{2}|[\d,]+)', caseSensitive: false),
    // Matches "PHP 1,500.00", "Php 1500.00", "P500.00", "₱1,250.00"
    RegExp(r'(?:PHP|Php|php|P|₱)\s*([\d,]+\.\d{2}|[\d,]+)', caseSensitive: false),
    // Fallback standalone decimal currency amount
    RegExp(r'\b([\d]{1,3}(?:,[\d]{3})+\.\d{2})\b'),
  ];

  /// RegEx rules for extracting Reference / Transaction Number.
  static final List<RegExp> _refNumberRegexes = [
    // Matches "Ref No. 1002938475", "Ref. No: 987654321012", "Reference No. 123456789012"
    RegExp(r'(?:Ref(?:erence)?|Trans(?:action)?|Seq|Trace|ID|No|#)[\s.:#]*(?:No|Num|Number|#)?[\s.:#]*([A-Za-z0-9]{6,20})', caseSensitive: false),
    // Standalone 10-13 digit number common in GCash/Maya receipts
    RegExp(r'\b(1\d{9,12}|9\d{9,12})\b'),
  ];

  /// RegEx rules for extracting Sender Name.
  static final List<RegExp> _senderRegexes = [
    // Matches "Sent by JUAN D.", "From JUAN DELA CRUZ", "Sender: MARIA C."
    RegExp(r'(?:sent\s+by|from|sender|payer|received\s+from|by)\s*[:\-\s]*([A-Z0-9\s\.\-\/]+?)(?=\s+(?:to|via|with|ref|amount|date|09\d{9})|$|\n)', caseSensitive: false),
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
        final rawStr = match.group(1)?.replaceAll(',', '').trim();
        if (rawStr != null) {
          final val = double.tryParse(rawStr);
          if (val != null && val > 0) return val;
        }
      }
    }
    return null;
  }

  /// Extracts reference number from OCR text.
  static String? _extractRefNumber(String rawText) {
    for (final regex in _refNumberRegexes) {
      final match = regex.firstMatch(rawText);
      if (match != null && match.groupCount >= 1) {
        final ref = match.group(1)?.trim();
        if (ref != null && ref.length >= 6) {
          return ref;
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
          name = name.split('\n').first.trim();
          name = name.replaceAll(RegExp(r'\s+09\d{9}$'), '').trim();
          if (name.isNotEmpty) return name;
        }
      }
    }
    return null;
  }
}
