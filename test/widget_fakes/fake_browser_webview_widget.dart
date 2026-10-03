// ignore_for_file: use_super_parameters

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'fake_browser_webview_platform.dart';

/// Renders a fake browser view and invokes the real page callbacks in tests.
class FakeBrowserWebViewWidget extends PlatformInAppWebViewWidget {
  FakeBrowserWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
    this.platform,
  ) : super.implementation(params);

  final FakeBrowserWebViewPlatform platform;

  @override
  Widget build(BuildContext context) {
    final controller = platform.createPlatformInAppWebViewController(
      PlatformInAppWebViewControllerCreationParams(id: params.windowId ?? 0),
    );
    final publicController = params.controllerFromPlatform!(controller);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      params.onWebViewCreated?.call(publicController);
      final url = WebUri('https://example.com/');
      params.onLoadStart?.call(publicController, url);
      params.onLoadStop?.call(publicController, url);
      final permissionHandler = params.onPermissionRequest;
      if (permissionHandler != null) {
        permissionHandler(
          publicController,
          PermissionRequest(
            origin: url,
            resources: [PermissionResourceType.CAMERA],
          ),
        ).then((response) => platform.lastPermissionResponse = response);
      }
    });
    return const SizedBox.expand();
  }

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;

  @override
  void dispose() {}
}
