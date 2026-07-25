// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web browser audio implementation using html.AudioElement.
void playChimeSoundImpl(String url) {
  try {
    final audio = html.AudioElement(url);
    audio.play();
  } catch (e) {
    // Gracefully handle browser autoplay policies
  }
}
