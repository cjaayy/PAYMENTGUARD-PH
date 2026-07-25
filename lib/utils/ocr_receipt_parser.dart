import 'provider_detector.dart';

/// Container for OCR parsed receipt extraction results.
class OcrParsedResult {
  final double? amount;
  final String? referenceNo;
  final String? sender;
  final String provider; // 'GCash', 'Maya', 'MariBank', or 'Unknown Provider'
  final String walletType; // Alias for provider
  final String rawText;
  final bool isValid;
  final bool isScam;
  final String threatLevel; // 'LOW' or 'HIGH'
  final String? errorMessage;

  const OcrParsedResult({
    this.amount,
    this.referenceNo,
    this.sender,
    required this.provider,
    required this.rawText,
    required this.isValid,
    this.isScam = false,
    this.threatLevel = 'LOW',
    this.errorMessage,
    String? walletType,
  }) : walletType = walletType ?? provider;

  @override
  String toString() {
    return 'OcrParsedResult(amount: $amount, referenceNo: $referenceNo, sender: $sender, provider: $provider, walletType: $walletType, isScam: $isScam, threatLevel: $threatLevel, isValid: $isValid, error: $errorMessage)';
  }
}

/// Robust RegEx Parser Utility to extract receipt fields from recognized OCR text strings
/// across GCash, Maya, MariBank, and generic e-wallet receipt screenshot formats.
class OcrReceiptParser {
  /// Non-transaction footer, header, and banner noise phrases to strip out before parsing fields.
  static const List<String> _noisePhrases = [
    'bangko sentral ng pilipinas',
    'bangko sentral',
    'bsp regulated',
    'regulated by the bangko sentral',
    'para sa pilipinas',
    'buy load',
    'express send',
    'send money',
    'pay bills',
    'bank transfer',
    'gsave',
    'ginvest',
    'gcredit',
    'ggives',
    'gloan',
    'share receipt',
    'save to photos',
    'save image',
    'download',
    'help center',
    'customer support',
    'submit a ticket',
    'official receipt',
    'transaction details',
    'transaction history',
    'payment details',
    'super app',
    'the #1 finance app',
    'promo',
  ];

  /// Blacklisted terms for sender names to prevent garbled system text from being used as a sender name.
  static const List<String> _headerNoiseKeywords = [
    'EXPRESS SEND',
    'SEND MONEY',
    'GCASH',
    'MAYA',
    'PAYMAYA',
    'MARIBANK',
    'TRANSACTION',
    'DETAILS',
    'RECEIPT',
    'BANGKO SENTRAL',
    'PILIPINAS',
    'BUY LOAD',
    'PAY BILLS',
    'AMOUNT',
    'TOTAL',
    'SUCCESS',
    'PAID TO',
    'SENT TO',
    'STATUS',
    'REF NO',
    'REFERENCE',
    'PAYMENTGUARD',
    'SCREENSHOT',
  ];

  /// Phishing & Scam URL / Keyword patterns for OCR text.
  static final RegExp _phishingUrlRegex = RegExp(
    r'(?:https?://|www\.)[^\s]+',
    caseSensitive: false,
  );

  static const List<String> _scamKeywords = [
    'account is locked',
    'account locked',
    'suspicious activity',
    'verify immediately',
    'security-update',
    'click here',
    'claim bonus',
    'account suspended',
    'verify your account',
  ];

  /// RegEx rules for extracting Amount in PHP / Php / P / ₱ currency formats, ignoring times/refs/dates.
  static final List<RegExp> _amountRegexes = [
    RegExp(
      r'(?:amount|total\s+amount|amount\s+sent|total|paid|sent)[\s\n\r.:#-]*\s*(?:PHP|Php|php|₱|P\.?)?\s*([\d,]+\.\d{2})\b',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:PHP|Php|php|₱)\s*([\d,]+\.\d{2})\b',
      caseSensitive: false,
    ),
    RegExp(
      r'(?<![A-Za-z0-9])(?:₱|P\.?)\s*([\d,]+\.\d{2})\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b([\d]{1,3}(?:,[\d]{3})*\.\d{2})\b',
    ),
  ];

  static final List<RegExp> _refNumberRegexes = [
    RegExp(
      r'(?:Ref(?:erence)?(?:\s*\.?\s*(?:No|Num|Number|#))?|Trans(?:action)?\s*(?:ID|No|Num|Number|#)|Seq|Trace)[\s\n\r.:#]*([A-Za-z0-9\s]{6,25})',
      caseSensitive: false,
    ),
    RegExp(r'\b(1\d{9,12}|9\d{9,12})\b'),
  ];

  /// RegEx rules for extracting Sender Name across newlines.
  static final List<RegExp> _senderRegexes = [
    RegExp(
      r'(?:sent\s+by|from|sender|payer|received\s+from|by)[\s\n\r.:-]*([A-Z0-9\s\.\-\/]+?)(?=\s+(?:to|via|with|ref|amount|date|09\d{9})|$|\n|\r)',
      caseSensitive: false,
    ),
    RegExp(r'([A-Z\s]{3,25})\s+(?:09\d{9}|\*\*\*\*\d{4})'),
  ];

  /// Strips out non-transaction footer, header, and banner noise from raw text.
  static String stripNoise(String rawText) {
    final lines = rawText.split(RegExp(r'[\r\n]+'));
    final cleanedLines = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final lower = trimmed.toLowerCase();

      bool isNoise = _noisePhrases.any((phrase) => lower.contains(phrase));
      if (!isNoise) {
        cleanedLines.add(trimmed);
      }
    }

    return cleanedLines.join('\n');
  }

  /// Parses raw text extracted by OCR TextRecognizer into structured fields.
  static OcrParsedResult parse(String rawText) {
    if (rawText.trim().isEmpty) {
      return OcrParsedResult(
        provider: 'Unknown Provider',
        rawText: rawText,
        isValid: false,
        isScam: false,
        threatLevel: 'LOW',
        errorMessage: 'OCR text is empty.',
      );
    }

    // 1. Phishing & Scam Assessment (Phishing URLs / Scam Keywords)
    final bool hasPhishingUrl = _phishingUrlRegex.hasMatch(rawText);
    final String lowerRaw = rawText.toLowerCase();
    final bool hasScamKeyword = _scamKeywords.any((kw) => lowerRaw.contains(kw));
    final bool isScam = hasPhishingUrl || hasScamKeyword;
    final String threatLevel = isScam ? 'HIGH' : 'LOW';

    // 2. Automatic Provider Detection (GCash, Maya, MariBank, or Unknown Provider)
    final String provider = ProviderDetector.detect(rawText);

    // 3. Strip out non-transaction noise lines for accurate regex matching
    final String cleanedText = stripNoise(rawText);

    // 4. Extract Amount from cleaned OCR text
    final double? amount = _extractAmount(cleanedText.isNotEmpty ? cleanedText : rawText);

    // 5. Extract Reference Number
    final String? referenceNo = _extractRefNumber(cleanedText.isNotEmpty ? cleanedText : rawText);

    // 6. Extract & Normalize Sender Name
    final String defaultSender = provider != 'Unknown Provider' ? '$provider (Scanned)' : 'GCash (Scanned)';
    String? parsedSender = _extractSender(cleanedText.isNotEmpty ? cleanedText : rawText);

    // Validate extracted sender against garbled header noise
    if (parsedSender != null) {
      final upperSender = parsedSender.toUpperCase();
      final isGarbledHeader = _headerNoiseKeywords.any((noise) => upperSender.contains(noise));
      if (isGarbledHeader || parsedSender.trim().length < 2) {
        parsedSender = null;
      }
    }

    final String sender = parsedSender ?? defaultSender;

    // 7. Check Validity & Format Error
    final bool isValid = amount != null && amount > 0 && referenceNo != null && referenceNo.isNotEmpty;
    String? errorMessage;
    if (isScam) {
      errorMessage = 'PHISHING/SCAM URL DETECTED IN RECEIPT.';
    } else if (amount == null) {
      errorMessage = 'Failed to parse receipt amount.';
    } else if (referenceNo == null || referenceNo.isEmpty) {
      errorMessage = 'Failed to parse reference number.';
    }

    return OcrParsedResult(
      amount: amount,
      referenceNo: referenceNo,
      sender: sender,
      provider: provider,
      rawText: rawText,
      isValid: isValid,
      isScam: isScam,
      threatLevel: threatLevel,
      errorMessage: errorMessage,
    );
  }

  /// Extracts amount from OCR text using multiple regex patterns, ignoring times & ref numbers.
  static double? _extractAmount(String text) {
    for (final regex in _amountRegexes) {
      for (final match in regex.allMatches(text)) {
        final rawStr = match.group(1)?.replaceAll(',', '').trim();
        if (rawStr != null) {
          final fullMatchStr = match.group(0) ?? '';
          if (fullMatchStr.contains(':') || RegExp(r'\b\d{1,2}:\d{2}\b').hasMatch(fullMatchStr)) {
            continue;
          }

          final val = double.tryParse(rawStr);
          if (val != null && val > 0 && val < 1000000) {
            return val;
          }
        }
      }
    }
    return null;
  }

  /// Extracts reference number from OCR text and strips whitespace/newlines.
  static String? _extractRefNumber(String text) {
    for (final regex in _refNumberRegexes) {
      final match = regex.firstMatch(text);
      if (match != null && match.groupCount >= 1) {
        var ref = match.group(1)?.replaceAll(RegExp(r'[\s\n\r]'), '').trim();
        if (ref != null) {
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
  static String? _extractSender(String text) {
    for (final regex in _senderRegexes) {
      final match = regex.firstMatch(text);
      if (match != null && match.groupCount >= 1) {
        var name = match.group(1)?.trim();
        if (name != null && name.length >= 2) {
          name = name.split('\n').first.split('\r').first.trim();
          name = name.replaceAll(RegExp(r'\s+09\d{9}$'), '').trim();
          if (name.isNotEmpty) return name;
        }
      }
    }
    return null;
  }
}
