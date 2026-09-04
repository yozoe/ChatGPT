import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 判断 WebView 主框架错误是否需要展示给用户。
/// Reports whether a main-frame WebView error should be surfaced to the user.
bool shouldReportBrowserWebResourceError(WebResourceError error) {
  return error.type != WebResourceErrorType.CANCELLED;
}
