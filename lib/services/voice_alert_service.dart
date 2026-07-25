import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Voice Alert Service utilizing Text-to-Speech (TTS) for English payment notifications.
class VoiceAlertService {
  final FlutterTts _flutterTts;
  bool _isInitialized = false;

  VoiceAlertService({FlutterTts? tts}) : _flutterTts = tts ?? FlutterTts();

  /// Formats reference number string into space-separated digits so TTS speaks digits one-by-one.
  /// Example: "1002938475" -> "1 0 0 2 9 3 8 4 7 5"
  static String formatRefForSpeech(String? refNo) {
    if (refNo == null || refNo.trim().isEmpty) return 'Unknown';
    return refNo.trim().split('').join(' ');
  }

  /// Initializes TTS engine with English (`en-US`) language settings.
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _isInitialized = true;
      debugPrint('[VoiceAlertService] Initialized TTS with language: en-US');
    } catch (e) {
      debugPrint('[VoiceAlertService] TTS Initialization warning: $e');
    }
  }

  /// Helper formatting for numeric amounts (e.g. 150.00 -> "150", 1250.5 -> "1250.50").
  String _formatAmount(double? amount) {
    if (amount == null || amount <= 0) return '0';
    return amount % 1 == 0 ? amount.toInt().toString() : amount.toStringAsFixed(2);
  }

  /// For Legit Incoming SMS:
  /// "Payment received: [Amount] pesos from [SenderName]. Reference number [Formatted_RefNo]."
  Future<void> speakLegitPaymentAlert({
    required double? amount,
    required String senderName,
    required String? refNumber,
    String? provider,
  }) async {
    await init();

    final double amt = amount ?? 0.0;
    final String amountText = _formatAmount(amt);
    final String formattedRef = formatRefForSpeech(refNumber);
    final String sender = (senderName.trim().isNotEmpty &&
            senderName.trim().toLowerCase() != 'unknown' &&
            senderName.trim().toLowerCase() != 'unknown sender' &&
            senderName.trim().toLowerCase() != 'suspicious sender')
        ? senderName.trim()
        : '';

    final String text = sender.isNotEmpty
        ? 'Payment received: $amountText pesos from $sender. Reference number $formattedRef.'
        : 'Payment received: $amountText pesos. Reference number $formattedRef.';

    debugPrint('[VoiceAlertService] Speaking legit payment alert: "$text"');
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  /// For Scam/Phishing SMS Warning:
  /// "Warning! Suspicious message detected from [Sender]. Possible scam alert."
  Future<void> speakScamWarningAlert({String? senderName}) async {
    await init();

    final sender = (senderName != null && senderName.isNotEmpty) ? senderName : 'Unknown Sender';
    final text = 'Warning! Suspicious message detected from $sender. Possible scam alert.';

    debugPrint('[VoiceAlertService] Speaking scam warning alert: "$text"');
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  /// For Successful OCR Receipt Scan:
  /// "Receipt scanned. Amount [Amount] pesos via [Provider]. Reference number [Formatted_RefNo]."
  Future<void> speakOcrMatchedAlert({
    required String? refNumber,
    required double? amount,
    String? senderName,
    String? provider,
  }) async {
    await init();

    final amountText = _formatAmount(amount);
    final formattedRef = formatRefForSpeech(refNumber);
    final providerText = (provider != null && provider.isNotEmpty) ? provider : 'GCash';
    final text = 'Receipt scanned. Amount $amountText pesos via $providerText. Reference number $formattedRef.';

    debugPrint('[VoiceAlertService] Speaking OCR matched alert: "$text"');
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  /// For Unverified OCR Scan:
  /// "Warning. Receipt scanned, but no matching transaction was found in database."
  Future<void> speakOcrUnverifiedWarning({
    String? refNumber,
  }) async {
    await init();

    const text = 'Warning. Receipt scanned, but no matching transaction was found in database.';

    debugPrint('[VoiceAlertService] Speaking OCR unverified warning: "$text"');
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  /// Speaks payment received alert announcing amount, sender name, AND reference number (digit-by-digit).
  /// Examples:
  /// - Sender & Ref: "Payment received: [Amount] pesos from [SenderName]. Reference number [1 0 0 2 9]."
  /// - Sender only: "Payment received: [Amount] pesos from [SenderName]."
  /// - Ref only: "Payment received: [Amount] pesos. Reference number [1 0 0 2 9]."
  /// - Amount only: "Payment received: [Amount] pesos."
  Future<void> speakPaymentReceived({
    required double? amount,
    String? senderName,
    String? refNumber,
  }) async {
    await init();

    final double amt = amount ?? 0.0;
    final String amountText = _formatAmount(amt);

    final String sender = (senderName != null &&
            senderName.trim().isNotEmpty &&
            senderName.trim().toLowerCase() != 'unknown' &&
            senderName.trim().toLowerCase() != 'unknown sender' &&
            senderName.trim().toLowerCase() != 'suspicious sender')
        ? senderName.trim()
        : '';

    String formattedRef = '';
    if (refNumber != null &&
        refNumber.trim().isNotEmpty &&
        refNumber.trim().toUpperCase() != 'NO_REF' &&
        refNumber.trim().toUpperCase() != 'N/A' &&
        refNumber.trim().toUpperCase() != 'NULL') {
      formattedRef = formatRefForSpeech(refNumber);
    }

    String text;
    if (sender.isNotEmpty && formattedRef.isNotEmpty) {
      text = 'Payment received: $amountText pesos from $sender. Reference number $formattedRef. Thank you!';
    } else if (sender.isNotEmpty) {
      text = 'Payment received: $amountText pesos from $sender. Thank you!';
    } else if (formattedRef.isNotEmpty) {
      text = 'Payment received: $amountText pesos. Reference number $formattedRef. Thank you!';
    } else {
      text = 'Payment received: $amountText pesos. Thank you!';
    }

    debugPrint('[VoiceAlertService] Speaking payment received: "$text"');
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  /// High-priority warning when a duplicate reference number occurs.
  Future<void> speakDuplicateWarning({
    required String refNumber,
  }) async {
    await init();

    final formattedRef = formatRefForSpeech(refNumber);
    final text = 'Warning! Reference number $formattedRef has already been used. Possible duplicate alert.';

    debugPrint('[VoiceAlertService] Speaking duplicate warning: "$text"');
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  /// Stops any ongoing audio playback.
  Future<void> stop() async {
    await _flutterTts.stop();
  }
}
