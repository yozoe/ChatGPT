import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_download.dart';
import 'package:chatgpt/src/presentation/browser/browser_download_cancellation.dart';

void main() {
  test('sanitizes server-provided download filenames', () {
    expect(
      browserDownloadSuggestedFilename('../report\u0000.txt'),
      '.._report_.txt',
    );
    expect(browserDownloadSuggestedFilename(null), 'download');
    expect(browserDownloadSuggestedFilename('..'), 'download');
  });

  test(
    'asks for a destination and saves a safely redirected download',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) {
        if (request.uri.path == '/redirect') {
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, '/payload')
            ..close();
          return;
        }
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.text
          ..write('browser payload')
          ..close();
      });
      final directory = await Directory.systemTemp.createTemp(
        'browser-download-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final target = '${directory.path}/report.txt';
      final request = DownloadStartRequest(
        contentLength: 15,
        suggestedFilename: 'report.txt',
        url: WebUri('http://127.0.0.1:${server.port}/redirect'),
      );

      final saved = await saveBrowserDownload(
        request: request,
        urlSafetyChecker: (_) async => true,
        pickLocation: (suggestedName) async {
          expect(suggestedName, 'report.txt');
          return FileSaveLocation(target);
        },
      );

      expect(saved, target);
      expect(await File(target).readAsString(), 'browser payload');
    },
  );

  test('rejects an unsafe redirect and never creates the target', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(HttpHeaders.locationHeader, '/private')
        ..close();
    });
    final directory = await Directory.systemTemp.createTemp(
      'browser-download-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final target = '${directory.path}/blocked.txt';
    final request = DownloadStartRequest(
      contentLength: 0,
      suggestedFilename: 'blocked.txt',
      url: WebUri('http://127.0.0.1:${server.port}/redirect'),
    );

    await expectLater(
      saveBrowserDownload(
        request: request,
        urlSafetyChecker: (uri) async => uri.path != '/private',
        pickLocation: (_) async => FileSaveLocation(target),
      ),
      throwsA(isA<StateError>()),
    );
    expect(await File(target).exists(), isFalse);
  });

  test(
    'can save directly into a configured directory without prompting',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('automatic payload')
          ..close();
      });
      final directory = await Directory.systemTemp.createTemp(
        'browser-download-default-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final request = DownloadStartRequest(
        contentLength: 17,
        suggestedFilename: 'automatic.txt',
        url: WebUri('http://127.0.0.1:${server.port}/payload'),
      );

      final saved = await saveBrowserDownload(
        request: request,
        urlSafetyChecker: (_) async => true,
        askForLocation: false,
        downloadDirectory: directory.path,
        pickLocation: (_) async => throw StateError('should not prompt'),
      );

      expect(saved, endsWith('/automatic.txt'));
      expect(await File(saved!).readAsString(), 'automatic payload');
    },
  );

  test(
    'does not create a file when the user cancels the save dialog',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'browser-download-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final request = DownloadStartRequest(
        contentLength: 0,
        suggestedFilename: 'cancelled.txt',
        url: WebUri('https://example.com/file.txt'),
      );

      final saved = await saveBrowserDownload(
        request: request,
        urlSafetyChecker: (_) async => true,
        pickLocation: (_) async => null,
      );

      expect(saved, isNull);
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test('reports an HTTP failure and leaves no target file', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..close();
    });
    final directory = await Directory.systemTemp.createTemp(
      'browser-download-http-error-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final target = '${directory.path}/failed.txt';
    final request = DownloadStartRequest(
      contentLength: 0,
      suggestedFilename: 'failed.txt',
      url: WebUri('http://127.0.0.1:${server.port}/failed'),
    );

    await expectLater(
      saveBrowserDownload(
        request: request,
        urlSafetyChecker: (_) async => true,
        pickLocation: (_) async => FileSaveLocation(target),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('503'),
        ),
      ),
    );
    expect(await File(target).exists(), isFalse);
  });

  test('does not overwrite an existing target file', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('new payload')
        ..close();
    });
    final directory = await Directory.systemTemp.createTemp(
      'browser-download-existing-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final target = '${directory.path}/existing.txt';
    await File(target).writeAsString('original payload');
    final request = DownloadStartRequest(
      contentLength: 11,
      suggestedFilename: 'existing.txt',
      url: WebUri('http://127.0.0.1:${server.port}/payload'),
    );

    await expectLater(
      saveBrowserDownload(
        request: request,
        urlSafetyChecker: (_) async => true,
        pickLocation: (_) async => FileSaveLocation(target),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('文件已存在'),
        ),
      ),
    );
    expect(await File(target).readAsString(), 'original payload');
  });

  test('rejects a configured download path that is not a directory', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('payload')
        ..close();
    });
    final directory = await Directory.systemTemp.createTemp(
      'browser-download-not-directory-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final filePath = '${directory.path}/not-a-directory';
    await File(filePath).writeAsString('not a directory');
    final request = DownloadStartRequest(
      contentLength: 7,
      suggestedFilename: 'payload.txt',
      url: WebUri('http://127.0.0.1:${server.port}/payload'),
    );

    await expectLater(
      saveBrowserDownload(
        request: request,
        urlSafetyChecker: (_) async => true,
        askForLocation: false,
        downloadDirectory: filePath,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('不是目录'),
        ),
      ),
    );
  });

  test(
    'cancels an in-flight transfer and removes its temporary file',
    () async {
      final firstChunkSent = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        request.response.headers.contentLength = 1024 * 1024;
        request.response.bufferOutput = false;
        request.response.add(List<int>.filled(1024, 7));
        await request.response.flush();
        if (!firstChunkSent.isCompleted) firstChunkSent.complete();
        for (var index = 0; index < 1024; index++) {
          request.response.add(List<int>.filled(1024, 8));
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        await request.response.close();
      });
      final directory = await Directory.systemTemp.createTemp(
        'browser-download-cancel-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final target = '${directory.path}/cancelled.txt';
      final request = DownloadStartRequest(
        contentLength: 1024 * 1024,
        suggestedFilename: 'cancelled.txt',
        url: WebUri('http://127.0.0.1:${server.port}/slow'),
      );
      final cancellation = BrowserDownloadCancellation();
      final pending = saveBrowserDownload(
        request: request,
        urlSafetyChecker: (_) async => true,
        pickLocation: (_) async => FileSaveLocation(target),
        cancellation: cancellation,
      );
      await firstChunkSent.future;
      cancellation.cancel();

      await expectLater(
        pending,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('取消'),
          ),
        ),
      );
      expect(await File(target).exists(), isFalse);
      final leftovers = await directory
          .list()
          .where((entity) => entity.path.endsWith('.part'))
          .toList();
      expect(leftovers, isEmpty);
    },
  );
}
