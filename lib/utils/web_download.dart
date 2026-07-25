import 'web_download_stub.dart'
    if (dart.library.html) 'web_download_web.dart';

/// Triggers automatic CSV download in browser, or simulates download in tests.
void downloadFile(String content, String filename) {
  downloadFileImpl(content, filename);
}

/// Triggers automatic binary (PDF) download in browser.
void downloadBytes(List<int> bytes, String filename) {
  downloadBytesImpl(bytes, filename);
}
