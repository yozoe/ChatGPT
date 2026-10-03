import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'fake_browser_webview_controller.dart';
import 'fake_browser_webview_widget.dart';

/// Platform implementation that exposes a controllable browser WebView in tests.
class FakeBrowserWebViewPlatform extends InAppWebViewPlatform {
  FakeBrowserWebViewController? lastController;
  PermissionResponse? lastPermissionResponse;
  InAppWebViewSettings? lastInitialSettings;
  bool hasDownloadStartHandler = false;
  bool hasCreateWindowHandler = false;
  bool hasCloseWindowHandler = false;
  final List<FakeBrowserWebViewController> controllers =
      <FakeBrowserWebViewController>[];

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewController(
    PlatformInAppWebViewControllerCreationParams params,
  ) {
    final controller = FakeBrowserWebViewController(params);
    lastController = controller;
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() =>
      FakeBrowserWebViewController(
        const PlatformInAppWebViewControllerCreationParams(id: 'static'),
      );

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    lastInitialSettings = params.initialSettings;
    hasDownloadStartHandler = params.onDownloadStartRequest != null;
    hasCreateWindowHandler = params.onCreateWindow != null;
    hasCloseWindowHandler = params.onCloseWindow != null;
    return FakeBrowserWebViewWidget(params, this);
  }
}
