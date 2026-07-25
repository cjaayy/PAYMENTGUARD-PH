import 'web_audio_stub.dart'
    if (dart.library.html) 'web_audio_web.dart';

/// Plays POS success chime sound ("Ding-Dong!") for incoming legitimate payments.
void playChimeSound([String url = 'https://assets.mixkit.co/active_storage/sfx/2869/2869-preview.mp3']) {
  playChimeSoundImpl(url);
}
