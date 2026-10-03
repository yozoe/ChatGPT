/// A user-visible entry in the app-owned browser history.
class BrowserHistoryEntry {
  const BrowserHistoryEntry({
    required this.url,
    required this.title,
    required this.visitedAt,
  });

  factory BrowserHistoryEntry.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('浏览历史条目格式无效。');
    }
    final url = value['url'];
    final title = value['title'];
    final visitedAt = value['visitedAt'];
    if (url is! String || title is! String || visitedAt is! String) {
      throw const FormatException('浏览历史条目字段无效。');
    }
    final timestamp = DateTime.tryParse(visitedAt)?.toUtc();
    if (url.isEmpty || timestamp == null) {
      throw const FormatException('浏览历史条目内容无效。');
    }
    return BrowserHistoryEntry(url: url, title: title, visitedAt: timestamp);
  }

  final String url;
  final String title;
  final DateTime visitedAt;

  Map<String, Object> toJson() => {
    'url': url,
    'title': title,
    'visitedAt': visitedAt.toUtc().toIso8601String(),
  };
}
