import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';

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

  /// Triggers a Tagalog voice announcement for a newly verified payment received.
  /// Example audio: "Pumasok na ang 150 pesos mula kay JUAN DELA CRUZ. Verified."
  Future<void> speakPaymentReceived({
    required double amount,
    required String senderName,
  }) async {
    await init();

    final formattedAmountStr = amount % 1 == 0 ? amount.toInt().toString() : amount.toStringAsFixed(2);
    final text = _activeLanguage.startsWith('tl')
        ? 'Pumasok na ang $formattedAmountStr pesos mula kay $senderName. Verified.'
        : 'Payment of $formattedAmountStr pesos received from $senderName. Verified.';

    debugPrint('[VoiceAlertService] Speaking payment alert: "$text"');
    await _flutterTts.stop();
    await _flutterTts.speak(text);
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
