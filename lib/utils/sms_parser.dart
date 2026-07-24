/// Container for parsed SMS extraction results.
class ParsedSmsResult {
  final double? amount;
  final String? refNumber;
  final String? senderName;
  final String source; // 'GCash', 'Maya', or 'Unknown'
  final String rawBody;
  final bool isValid;
  final String? errorMessage;

  const ParsedSmsResult({
    this.amount,
    this.refNumber,
    this.senderName,
    required this.source,
    required this.rawBody,
    required this.isValid,
    this.errorMessage,
  });

  @override
  String toString() {
    return 'ParsedSmsResult(amount: $amount, refNumber: $refNumber, senderName: $senderName, source: $source, isValid: $isValid, error: $errorMessage)';
  }
}

/// Utility class providing regex parsing capabilities for standard Philippine e-wallet SMS alerts
/// (GCash and Maya / PayMaya).
class SmsParser {
  /// Regular expression to match amounts in PHP / Php / P / ₱ currency formats.
  /// Matches amounts like: PHP 150.00, Php 1,250.50, P500.00, ₱1,000.00, etc.
  static final RegExp _amountRegex = RegExp(
    r'(?:PHP|Php|php|P|₱)\s*([\d,]+\.\d{2}|[\d,]+)',
    caseSensitive: false,
  );

  /// Regular expression to match reference numbers across various e-wallet alert formats.
  /// Matches strings like: Ref. No. 102938475610, Ref No: 987654321012, Reference No. 123456789012, Ref: 12345, etc.
  static final RegExp _refNumberRegex = RegExp(
    r'(?:Ref(?:erence)?(?:\s*\.?\s*(?:No|Num|Number|#))?[\s.:#]*)\s*([A-Za-z0-9]{5,})',
    caseSensitive: false,
  );

  /// Regular expression to match sender name following "from".
  /// Captures names like "JUAN DELA CRUZ", "MARIA S.", etc., stopping before e-wallet markers, phone numbers, or dates.
  static final RegExp _senderNameRegex = RegExp(
    r'from\s+([A-Z0-9\s\.\-\/]+?)(?=\s+(?:via|with|\d{11}|Ref|09\d{9}|on\s+\d{2}\/\d{2}|is\s+now|to\s+your)|$)',
    caseSensitive: false,
  );

  /// Parses raw SMS text (and optional SMS sender ID) to extract amount, reference number, sender name, and e-wallet source.
  static ParsedSmsResult parse(String smsBody, {String? senderHeader}) {
    if (smsBody.trim().isEmpty) {
      return ParsedSmsResult(
        source: 'Unknown',
        rawBody: smsBody,
        isValid: false,
        errorMessage: 'SMS body is empty.',
      );
    }

    // 1. Determine Source (GCash vs Maya)
    final source = detectSource(smsBody, senderHeader: senderHeader);

    // 2. Extract Amount
    final double? amount = extractAmount(smsBody);

    // 3. Extract Reference Number
    final String? refNumber = extractRefNumber(smsBody);

    // 4. Extract Sender Name
    final String? senderName = extractSenderName(smsBody);

    // 5. Validation Check
    final bool isValid = amount != null && amount > 0 && refNumber != null && refNumber.isNotEmpty;
    String? errorMessage;
    if (amount == null) {
      errorMessage = 'Failed to extract valid amount.';
    } else if (refNumber == null || refNumber.isEmpty) {
      errorMessage = 'Failed to extract reference number.';
    }

    return ParsedSmsResult(
      amount: amount,
      refNumber: refNumber,
      senderName: senderName ?? 'UNKNOWN SENDER',
      source: source,
      rawBody: smsBody,
      isValid: isValid,
      errorMessage: errorMessage,
    );
  }

  /// Detects whether the SMS comes from GCash, Maya (PayMaya), or another service.
  static String detectSource(String smsBody, {String? senderHeader}) {
    final combined = '${senderHeader ?? ''} $smsBody'.toUpperCase();

    if (combined.contains('GCASH')) {
      return 'GCash';
    } else if (combined.contains('MAYA') || combined.contains('PAYMAYA')) {
      return 'Maya';
    }

    // Fallback heuristic based on standard text patterns
    if (combined.contains('OF GCASH') || combined.contains('GCASH ACCOUNT')) {
      return 'GCash';
    }

    return 'GCash'; // Default primary e-wallet in PH if unclassified
  }

  /// Extracts the monetary amount from an SMS string as a double.
  static double? extractAmount(String smsBody) {
    final match = _amountRegex.firstMatch(smsBody);
    if (match != null && match.groupCount >= 1) {
      final rawAmountStr = match.group(1)?.replaceAll(',', '');
      if (rawAmountStr != null) {
        return double.tryParse(rawAmountStr);
      }
    }
    return null;
  }

  /// Extracts the reference number string from an SMS text.
  static String? extractRefNumber(String smsBody) {
    final match = _refNumberRegex.firstMatch(smsBody);
    if (match != null && match.groupCount >= 1) {
      final ref = match.group(1)?.trim();
      if (ref != null && ref.isNotEmpty) {
        return ref;
      }
    }
    return null;
  }

  /// Extracts the sender's name from the SMS body text.
  static String? extractSenderName(String smsBody) {
    final match = _senderNameRegex.firstMatch(smsBody);
    if (match != null && match.groupCount >= 1) {
      var name = match.group(1)?.trim();
      if (name != null && name.isNotEmpty) {
        // Strip trailing phone numbers if inadvertently captured (e.g. 09171234567)
        name = name.replaceAll(RegExp(r'\s+09\d{9}$'), '').trim();
        return name;
      }
    }
    return null;
  }
}
