import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page.dart';
import 'widget_fakes/fake_browser_webview_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('routes Cmd+R to the active native WebView controller', (
    tester,
  ) async {
    final previousPlatform = InAppWebViewPlatform.instance;
    final fakePlatform = FakeBrowserWebViewPlatform();
    InAppWebViewPlatform.instance = fakePlatform;
    addTearDown(() {
      if (previousPlatform != null) {
        InAppWebViewPlatform.instance = previousPlatform;
      }
    });

    await tester.pumpWidget(
      MaterialApp(home: BrowserWorkspacePage(onOpenConversation: () {})),
    );
    await tester.pump();
    await tester.pump();
    expect(fakePlatform.lastController, isNotNull);
    await tester.pump();
    expect(
      fakePlatform.lastPermissionResponse?.action,
      PermissionResponseAction.DENY,
    );
    await tester.tap(find.byKey(const Key('browser-address')));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(
      fakePlatform.controllers.map((controller) => controller.reloadCalls),
      contains(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'passes download, popup, navigation, and media policy to plugin',
    (tester) async {
      final previousPlatform = InAppWebViewPlatform.instance;
      final fakePlatform = FakeBrowserWebViewPlatform();
      InAppWebViewPlatform.instance = fakePlatform;
      addTearDown(() {
        if (previousPlatform != null) {
          InAppWebViewPlatform.instance = previousPlatform;
        }
      });

      await tester.pumpWidget(
        MaterialApp(home: BrowserWorkspacePage(onOpenConversation: () {})),
      );
      await tester.pump();
      await tester.pump();

      final settings = fakePlatform.lastInitialSettings;
      expect(settings, isNotNull);
      expect(settings!.useOnDownloadStart, isTrue);
      expect(settings.supportMultipleWindows, isTrue);
      expect(settings.useShouldOverrideUrlLoading, isTrue);
      expect(settings.mediaPlaybackRequiresUserGesture, isTrue);
      expect(fakePlatform.hasDownloadStartHandler, isTrue);
      expect(fakePlatform.hasCreateWindowHandler, isTrue);
      expect(fakePlatform.hasCloseWindowHandler, isTrue);
      expect(
        fakePlatform.lastPermissionResponse?.action,
        PermissionResponseAction.DENY,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
