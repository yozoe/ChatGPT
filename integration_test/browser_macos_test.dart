import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_download.dart';
import 'package:chatgpt/src/presentation/browser/browser_download_cancellation.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('embeds the real macOS WebKit platform view', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserWorkspacePage(
          onOpenConversation: () {},
          initialUrl: 'https://example.com',
          urlSafetyChecker: (_) async => true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      InAppWebViewPlatform.instance.runtimeType.toString(),
      contains('MacOSInAppWebViewPlatform'),
    );
    expect(find.byKey(const Key('browser-native-webview-0')), findsOneWidget);
    expect(find.byKey(const Key('browser-address')), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const Key('browser-workspace-page')))
          .label,
      contains('内置浏览器工作区'),
    );

    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('delivers a WebKit download callback to Dart', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    unawaited(
      server.forEach((request) async {
        if (request.uri.path == '/fixture') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType('application', 'octet-stream')
            ..headers.add(
              'content-disposition',
              'attachment; filename="fixture.txt"',
            )
            ..write('dart download');
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType('text', 'html')
            ..write(
              '<!doctype html><html><body><a id="download" href="/fixture">download</a></body></html>',
            );
        }
        await request.response.close();
      }),
    );
    DownloadStartRequest? request;
    InAppWebViewController? controller;
    final callback = Completer<void>();
    final pageLoaded = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri('http://127.0.0.1:${server.port}/'),
          ),
          initialSettings: InAppWebViewSettings(useOnDownloadStart: true),
          onWebViewCreated: (value) => controller = value,
          onLoadStop: (value, _) {
            if (!pageLoaded.isCompleted) pageLoaded.complete();
          },
          onDownloadStartRequest: (value, valueRequest) {
            request = valueRequest;
            if (!callback.isCompleted) callback.complete();
          },
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(controller, isNotNull);
    await pageLoaded.future.timeout(const Duration(seconds: 10));
    await controller!.evaluateJavascript(
      source: "document.getElementById('download').click()",
    );
    await tester.pump(const Duration(seconds: 2));
    await callback.future.timeout(const Duration(seconds: 10));
    expect(request, isNotNull);
    expect(request!.suggestedFilename, 'fixture.txt');

    final directory = await Directory.systemTemp.createTemp(
      'browser-plugin-download-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final savedPath = await saveBrowserDownload(
      request: request!,
      urlSafetyChecker: (_) async => true,
      downloadDirectory: directory.path,
      askForLocation: false,
    );
    expect(savedPath, isNotNull);
    expect(await File(savedPath!).readAsString(), 'dart download');
  });

  testWidgets('cancels a Dart transfer after a WebKit download callback', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    unawaited(
      server.forEach((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('application', 'octet-stream')
          ..headers.add(
            'content-disposition',
            'attachment; filename="slow.txt"',
          );
        for (var index = 0; index < 100; index++) {
          request.response.write('chunk-$index\n');
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await request.response.close();
      }),
    );
    DownloadStartRequest? request;
    final callback = Completer<void>();
    final pageLoaded = Completer<void>();
    InAppWebViewController? controller;

    await tester.pumpWidget(
      MaterialApp(
        home: InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri('http://127.0.0.1:${server.port}/slow'),
          ),
          initialSettings: InAppWebViewSettings(useOnDownloadStart: true),
          onWebViewCreated: (value) => controller = value,
          onLoadStop: (_, _) {
            if (!pageLoaded.isCompleted) pageLoaded.complete();
          },
          onDownloadStartRequest: (_, value) {
            request = value;
            if (!callback.isCompleted) callback.complete();
          },
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(controller, isNotNull);
    await callback.future.timeout(const Duration(seconds: 10));
    expect(pageLoaded.isCompleted, isFalse);
    expect(request, isNotNull);

    final directory = await Directory.systemTemp.createTemp(
      'browser-plugin-cancel-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final cancellation = BrowserDownloadCancellation();
    final transfer = saveBrowserDownload(
      request: request!,
      urlSafetyChecker: (_) async => true,
      downloadDirectory: directory.path,
      askForLocation: false,
      cancellation: cancellation,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    cancellation.cancel();
    await expectLater(transfer, throwsA(isA<StateError>()));
    expect(await directory.list().toList(), isEmpty);
  });

  testWidgets(
    'reports a failed Dart transfer after a WebKit download callback',
    (tester) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      unawaited(
        server.forEach((request) async {
          request.response
            ..statusCode = HttpStatus.internalServerError
            ..headers.contentType = ContentType('application', 'octet-stream')
            ..headers.add(
              'content-disposition',
              'attachment; filename="failed.txt"',
            )
            ..write('failed');
          await request.response.close();
        }),
      );
      DownloadStartRequest? request;
      final callback = Completer<void>();
      InAppWebViewController? controller;

      await tester.pumpWidget(
        MaterialApp(
          home: InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri('http://127.0.0.1:${server.port}/failure'),
            ),
            initialSettings: InAppWebViewSettings(useOnDownloadStart: true),
            onWebViewCreated: (value) => controller = value,
            onDownloadStartRequest: (_, value) {
              request = value;
              if (!callback.isCompleted) callback.complete();
            },
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(controller, isNotNull);
      await callback.future.timeout(const Duration(seconds: 10));
      expect(request, isNotNull);

      final directory = await Directory.systemTemp.createTemp(
        'browser-plugin-failure-',
      );
      addTearDown(() => directory.delete(recursive: true));
      await expectLater(
        saveBrowserDownload(
          request: request!,
          urlSafetyChecker: (_) async => true,
          downloadDirectory: directory.path,
          askForLocation: false,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('HTTP 500'),
          ),
        ),
      );
      expect(await directory.list().toList(), isEmpty);
    },
  );
}
