import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web browser implementation that creates a Blob and triggers automatic file download.
void downloadFileImpl(String content, String filename) {
  final bytes = utf8.encode(content);
  downloadBytesImpl(bytes, filename, mimeType: 'text/csv;charset=utf-8');
}

void downloadBytesImpl(List<int> bytes, String filename, {String mimeType = 'application/pdf'}) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
