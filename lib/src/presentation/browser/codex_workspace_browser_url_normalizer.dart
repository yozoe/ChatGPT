import 'dart:io';

/// 将用户地址栏输入规范化为可在内置浏览器打开的 HTTP 或 HTTPS URL。
/// Normalizes an address-bar value into an HTTP or HTTPS URL for the embedded browser.
Uri? normalizeBrowserUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) return null;
  final hasScheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(trimmed);
  final candidate = hasScheme ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(candidate);
  if (uri == null) return null;
  return isBrowserWebUri(uri) ? uri : null;
}

/// 判断 URL 是否可由内置 WebView 直接加载。
/// Reports whether a URL can be loaded directly by the embedded WebView.
bool isBrowserWebUri(Uri uri) {
  if ((uri.scheme != 'http' && uri.scheme != 'https') ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.port < 0 || uri.port > 65535)) {
    return false;
  }
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  if (host == 'localhost' ||
      host.endsWith('.localhost') ||
      host == 'localhost.localdomain' ||
      host.endsWith('.local')) {
    return false;
  }
  final address = InternetAddress.tryParse(host);
  if (address == null) {
    // Reject non-canonical numeric host spellings (for example 127.1 or
    // 0x7f000001) that browsers may interpret as loopback addresses.
    if (RegExp(r'^[0-9A-Fa-fxX:.]+$').hasMatch(host)) return false;
    return true;
  }
  return !_isBlockedAddress(address);
}

/// Resolves a hostname before WebView navigation so DNS names cannot hide a
/// loopback/private destination behind an otherwise public-looking URL.
Future<bool> isBrowserWebUriSafe(Uri uri) async {
  if (!isBrowserWebUri(uri)) return false;
  final literal = InternetAddress.tryParse(uri.host);
  if (literal != null) return true;
  try {
    final addresses = await InternetAddress.lookup(uri.host);
    return addresses.isNotEmpty &&
        addresses.every((a) => !_isBlockedAddress(a));
  } on SocketException {
    return false;
  }
}

/// 判断解析后的 IP 是否属于本机、私网、链路本地或多播地址。
/// Reports whether a resolved IP is loopback, private, link-local, or multicast.
bool _isBlockedAddress(InternetAddress address) {
  if (address.type == InternetAddressType.IPv4) {
    final octets = address.rawAddress;
    final first = octets[0];
    final second = octets[1];
    return first == 0 ||
        first == 10 ||
        first == 127 ||
        (first == 100 && second >= 64 && second <= 127) ||
        (first == 169 && second == 254) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 0) ||
        (first == 192 && second == 168) ||
        (first == 198 && (second == 18 || second == 19)) ||
        first >= 224;
  }
  final bytes = address.rawAddress;
  final isMappedIpv4 =
      bytes.length == 16 &&
      bytes.take(10).every((byte) => byte == 0) &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff;
  if (isMappedIpv4) {
    final first = bytes[12];
    final second = bytes[13];
    if (first == 0 ||
        first == 10 ||
        first == 127 ||
        (first == 169 && second == 254) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && (second == 0 || second == 168)) ||
        (first == 100 && second >= 64 && second <= 127) ||
        first >= 224) {
      return true;
    }
  }
  final isUnspecified = bytes.every((byte) => byte == 0);
  final isLoopback =
      bytes.take(15).every((byte) => byte == 0) && bytes[15] == 1;
  final isLinkLocal =
      (bytes[0] & 0xfe) == 0xfc ||
      (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
  final isMulticast = bytes[0] == 0xff;
  return isUnspecified || isLoopback || isLinkLocal || isMulticast;
}
