// ignore_for_file: use_super_parameters

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Minimal platform controller used to verify browser workspace commands.
class FakeBrowserWebViewController extends PlatformInAppWebViewController {
  FakeBrowserWebViewController(
    PlatformInAppWebViewControllerCreationParams params,
  ) : super.implementation(params);

  int reloadCalls = 0;
  int stopLoadingCalls = 0;

  @override
  Future<bool> canGoBack() async => false;

  @override
  Future<bool> canGoForward() async => false;

  @override
  Future<void> reload() async {
    reloadCalls += 1;
  }

  @override
  Future<void> stopLoading() async {
    stopLoadingCalls += 1;
  }

  @override
  void dispose({bool isKeepAlive = false}) {}
}
