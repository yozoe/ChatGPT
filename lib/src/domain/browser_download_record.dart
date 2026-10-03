/// Metadata for a completed browser download. The file itself is never owned
/// or deleted by this record.
class BrowserDownloadRecord {
  const BrowserDownloadRecord({
    required this.url,
    required this.filePath,
    required this.fileName,
    required this.downloadedAt,
  });

  factory BrowserDownloadRecord.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('下载记录格式无效。');
    }
    final url = value['url'];
    final filePath = value['filePath'];
    final fileName = value['fileName'];
    final downloadedAt = value['downloadedAt'];
    if (url is! String ||
        filePath is! String ||
        fileName is! String ||
        downloadedAt is! String) {
      throw const FormatException('下载记录字段无效。');
    }
    final timestamp = DateTime.tryParse(downloadedAt)?.toUtc();
    if (url.isEmpty ||
        filePath.isEmpty ||
        fileName.isEmpty ||
        timestamp == null) {
      throw const FormatException('下载记录内容无效。');
    }
    return BrowserDownloadRecord(
      url: url,
      filePath: filePath,
      fileName: fileName,
      downloadedAt: timestamp,
    );
  }

  final String url;
  final String filePath;
  final String fileName;
  final DateTime downloadedAt;

  Map<String, Object> toJson() => {
    'url': url,
    'filePath': filePath,
    'fileName': fileName,
    'downloadedAt': downloadedAt.toUtc().toIso8601String(),
  };
}
