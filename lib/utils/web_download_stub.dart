import 'package:flutter/foundation.dart';

/// Fallback non-web implementation for VM / desktop unit testing environment.
void downloadFileImpl(String content, String filename) {
  debugPrint('[WebDownload] Simulated CSV file download ($filename):\n$content');
}

void downloadBytesImpl(List<int> bytes, String filename) {
  debugPrint('[WebDownload] Simulated binary file download ($filename, ${bytes.length} bytes)');
}
