import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Voice Alert Service utilizing Text-to-Speech (TTS) for Tagalog & English payment notifications.
class VoiceAlertService {
  final FlutterTts _flutterTts;
  bool _isInitialized = false;
  String _activeLanguage = 'tl-PH';

  VoiceAlertService({FlutterTts? tts}) : _flutterTts = tts ?? FlutterTts();

  /// Initializes TTS engine with Tagalog (`tl-PH`) language settings and English fallback.
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // Check available languages
      final languages = await _flutterTts.getLanguages;
      final langList = (languages as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

      if (langList.any((lang) => lang.contains('tl') || lang.contains('fil'))) {
        _activeLanguage = 'tl-PH';
      } else {
        _activeLanguage = 'en-US'; // English fallback
        debugPrint('[VoiceAlertService] Tagalog TTS voice unavailable. Falling back to en-US.');
      }

      await _flutterTts.setLanguage(_activeLanguage);
      await _flutterTts.setSpeechRate(0.48); // Slightly slower for clear Tagalog comprehension
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _isInitialized = true;
      debugPrint('[VoiceAlertService] Initialized TTS with language: $_activeLanguage');
    } catch (e) {
      debugPrint('[VoiceAlertService] TTS Initialization warning: $e');
    }
  }

  /// Helper converter for amounts like 500 -> "limandaang piso" or "500 pesos"
  String _formatAmountInTagalog(double? amount) {
    if (amount == null || amount <= 0) return 'piso';
    if (amount == 500) return 'limandaang piso';
    if (amount == 100) return 'sandaang piso';
    if (amount == 1000) return 'isang libong piso';

    final formattedStr = amount % 1 == 0 ? amount.toInt().toString() : amount.toStringAsFixed(2);
    return '$formattedStr pesos';
  }

  /// Triggers a Tagalog voice announcement for a newly verified payment received.
  /// Example audio: "Nakatanggap ka ng limandaang piso mula kay JUAN D."
  Future<void> speakLegitPaymentAlert({
    required double? amount,
    required String senderName,
  }) async {
    await init();

    final amountText = _formatAmountInTagalog(amount);
    final text = _activeLanguage.startsWith('tl')
        ? 'Nakatanggap ka ng $amountText mula kay $senderName.'
        : 'Payment of $amountText received from $senderName.';

    debugPrint('[VoiceAlertService] Speaking legit payment alert: "$text"');
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  /// Triggers an urgent Tagalog voice warning when a phishing / scam SMS is detected.
  /// Spoken text: "Babala! Ang natanggap mong mensahe ay naglalaman ng kahina-hinalang link. Huwag mag-click."
  Future<void> speakScamWarningAlert() async {
    await init();

    const text = 'Babala! Ang natanggap mong mensahe ay naglalaman ng kahina-hinalang link. Huwag mag-click.';

    debugPrint('[VoiceAlertService] Speaking scam warning alert: "$text"');
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  /// Triggers a Tagalog voice announcement for a newly verified payment received (legacy signature).
  Future<void> speakPaymentReceived({
    required double amount,
    required String senderName,
  }) async {
    await speakLegitPaymentAlert(amount: amount, senderName: senderName);
  }

  /// Triggers a high-priority Tagalog voice warning when a duplicate reference number / fake screenshot attempt occurs.
  /// Example audio: "Babala! Ang reference number 102938475610 ay nagamit na. Fake screenshot alert."
  Future<void> speakDuplicateWarning({
    required String refNumber,
  }) async {
    await init();

    final text = _activeLanguage.startsWith('tl')
        ? 'Babala! Ang reference number $refNumber ay nagamit na. Fake screenshot alert.'
        : 'Warning! Reference number $refNumber has already been used. Fake screenshot alert.';

    debugPrint('[VoiceAlertService] Speaking duplicate warning: "$text"');
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  /// Stops any ongoing audio playback.
  Future<void> stop() async {
    await _flutterTts.stop();
  }
}
