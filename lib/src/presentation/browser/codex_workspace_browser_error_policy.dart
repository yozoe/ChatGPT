import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 将 WebView 取消请求视为无需展示的导航噪音。
/// Treats cancelled WebView requests as non-reportable navigation noise.
bool shouldReportBrowserWebResourceError(WebResourceError error) {
  return error.type != WebResourceErrorType.CANCELLED;
}
