/// 将用户地址栏输入规范化为可在内置浏览器打开的 HTTP 或 HTTPS URL。
/// Normalizes an address-bar value into an HTTP or HTTPS URL for the embedded browser.
Uri? normalizeBrowserUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) return null;
  final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(candidate);
  if (uri == null || !uri.hasAuthority) return null;
  return isBrowserWebUri(uri) ? uri : null;
}

/// 判断 URL 是否可由内置 WebView 直接加载。
/// Reports whether a URL can be loaded directly by the embedded WebView.
bool isBrowserWebUri(Uri uri) =>
    (uri.scheme == 'http' || uri.scheme == 'https') && uri.hasAuthority;
