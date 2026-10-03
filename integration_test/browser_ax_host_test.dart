import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hosts a real webpage for external macOS AX audit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri('https://example.com')),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 5));

    expect(
      InAppWebViewPlatform.instance.runtimeType.toString(),
      contains('MacOSInAppWebViewPlatform'),
    );
    expect(find.byType(InAppWebView), findsOneWidget);

    if (Platform.environment['CODEX_BROWSER_AX_HOLD'] == '1') {
      // The external AX audit process attaches to this live native window.
      await Completer<void>().future;
    }
  });
}
