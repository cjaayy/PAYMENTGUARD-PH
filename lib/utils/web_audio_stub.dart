import 'package:flutter/foundation.dart';

/// Fallback non-web implementation for VM / unit test environment.
void playChimeSoundImpl(String url) {
  debugPrint('[WebAudio] Simulated chime audio playback ($url)');
}
