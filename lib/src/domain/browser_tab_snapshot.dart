/// Persisted, privacy-filtered state for one browser tab.
class BrowserTabSnapshot {
  const BrowserTabSnapshot({required this.url, required this.title});

  factory BrowserTabSnapshot.fromJson(Object? value) {
    if (value is! Map || value['url'] is! String || value['title'] is! String) {
      throw const FormatException('浏览器标签快照格式无效。');
    }
    return BrowserTabSnapshot(
      url: value['url'] as String,
      title: value['title'] as String,
    );
  }

  final String url;
  final String title;

  Map<String, Object> toJson() => {'url': url, 'title': title};
}
