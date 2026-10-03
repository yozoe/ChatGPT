import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:chatgpt/src/presentation/browser/browser_download_cancellation.dart';

/// Lets tests and the browser workspace replace the native save dialog.
typedef BrowserDownloadLocationPicker =
    Future<FileSaveLocation?> Function(String suggestedName);

/// Lets widget tests replace the transfer and native file-system boundary.
typedef BrowserDownloadSaver =
    Future<String?> Function({
      required DownloadStartRequest request,
      required Future<bool> Function(Uri uri) urlSafetyChecker,
      required BrowserDownloadLocationPicker pickLocation,
      String? downloadDirectory,
      bool askForLocation,
      BrowserDownloadCancellation? cancellation,
    });

/// Opens the native save dialog with a safe, display-only suggested name.
Future<FileSaveLocation?> pickBrowserDownloadLocation(String suggestedName) =>
    getSaveLocation(
      suggestedName: suggestedName,
      confirmButtonText: '保存',
      canCreateDirectories: false,
    );

/// Removes path syntax from a server-provided download name before it reaches
/// the native save dialog. The user still chooses the final absolute path.
String browserDownloadSuggestedFilename(String? value) {
  final sanitized = (value ?? '')
      .replaceAll(RegExp(r'[\\/\x00-\x1f\x7f]'), '_')
      .trim();
  if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
    return 'download';
  }
  return sanitized.length <= 240
      ? sanitized
      : sanitized.substring(0, 240).trimRight();
}

/// Downloads a WebView resource only after the user chooses a destination.
///
/// Redirects are revalidated with [urlSafetyChecker]. The selected parent is
/// resolved before and after the transfer, and the response is written to an
/// exclusive temporary file before it is atomically renamed to the user
/// selected target. Existing files are never overwritten.
Future<String?> saveBrowserDownload({
  required DownloadStartRequest request,
  required Future<bool> Function(Uri uri) urlSafetyChecker,
  BrowserDownloadLocationPicker pickLocation = pickBrowserDownloadLocation,
  String? downloadDirectory,
  bool askForLocation = true,
  HttpClient? httpClient,
  BrowserDownloadCancellation? cancellation,
}) async {
  if (cancellation?.isCancelled == true) {
    throw StateError('下载已取消。');
  }
  final source = Uri.tryParse(request.url.toString());
  if (source == null || !await urlSafetyChecker(source)) {
    throw StateError('已阻止不安全的下载地址。');
  }
  if (cancellation?.isCancelled == true) {
    throw StateError('下载已取消。');
  }

  final suggestedName = browserDownloadSuggestedFilename(
    request.suggestedFilename,
  );
  final File target;
  if (askForLocation) {
    final location = await pickLocation(suggestedName);
    if (location == null) return null;
    target = File(location.path);
  } else {
    final directory = downloadDirectory?.trim();
    if (directory == null || directory.isEmpty) {
      throw StateError('未设置默认下载目录，请先选择保存位置。');
    }
    final canonicalDirectory = await _existingDirectory(Directory(directory));
    target = File(
      '${canonicalDirectory.path}${Platform.pathSeparator}$suggestedName',
    );
  }
  if (cancellation?.isCancelled == true) {
    throw StateError('下载已取消。');
  }
  final targetName = target.uri.pathSegments.isEmpty
      ? ''
      : target.uri.pathSegments.last;
  if (targetName.isEmpty ||
      targetName == '.' ||
      targetName == '..' ||
      targetName.contains(RegExp(r'[\\/\x00]'))) {
    throw StateError('下载目标文件名无效。');
  }

  final parent = target.parent;
  final canonicalParent = await _existingDirectory(parent);
  if (await target.exists()) {
    throw StateError('文件已存在：${target.path}');
  }
  final temporary = File(
    '${canonicalParent.path}${Platform.pathSeparator}.$targetName.${DateTime.now().microsecondsSinceEpoch}.part',
  );
  final client = httpClient ?? HttpClient();
  var ownsClient = httpClient == null;
  HttpClientRequest? activeRequest;
  try {
    cancellation?.whenCancelled.then((_) => activeRequest?.abort());
    var current = source;
    HttpClientResponse? response;
    for (var redirect = 0; redirect <= 5; redirect++) {
      if (!await urlSafetyChecker(current)) {
        throw StateError('重定向到不安全的下载地址。');
      }
      if (cancellation?.isCancelled == true) {
        throw StateError('下载已取消。');
      }
      final requestHandle = await client.getUrl(current);
      activeRequest = requestHandle;
      if (cancellation?.isCancelled == true) {
        requestHandle.abort();
        throw StateError('下载已取消。');
      }
      if (request.userAgent?.trim().isNotEmpty == true) {
        requestHandle.headers.set(
          HttpHeaders.userAgentHeader,
          request.userAgent!,
        );
      }
      requestHandle.followRedirects = false;
      response = await _closeRequest(requestHandle, cancellation);
      if (response.isRedirect) {
        final locationHeader = response.headers.value(
          HttpHeaders.locationHeader,
        );
        if (locationHeader == null || locationHeader.trim().isEmpty) {
          throw StateError('下载重定向缺少目标地址。');
        }
        current = current.resolve(locationHeader);
        await _drainResponse(response, activeRequest, cancellation);
        continue;
      }
      break;
    }
    if (response == null || response.isRedirect) {
      throw StateError('下载重定向次数过多。');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw StateError('下载失败（HTTP ${response.statusCode}）。');
    }

    await temporary.create(exclusive: true);
    final sink = temporary.openWrite(mode: FileMode.writeOnly);
    try {
      await _pipeResponse(response, sink, activeRequest, cancellation);
    } catch (_) {
      await sink.close();
      rethrow;
    }
    final parentAfterDownload = await _existingDirectory(parent);
    if (cancellation?.isCancelled == true) {
      throw StateError('下载已取消。');
    }
    if (parentAfterDownload.path != canonicalParent.path ||
        await target.exists()) {
      throw StateError('下载目录在传输期间发生变化，已取消保存。');
    }
    await temporary.rename(target.path);
    return target.path;
  } finally {
    if (await temporary.exists()) await temporary.delete();
    if (ownsClient) client.close(force: true);
  }
}

const _downloadCancelledMarker = 'browser-download-cancelled';
const _downloadCompletedMarker = 'browser-download-completed';

Future<HttpClientResponse> _closeRequest(
  HttpClientRequest request,
  BrowserDownloadCancellation? cancellation,
) async {
  if (cancellation == null) return request.close();
  final result = await Future.any<Object>([
    request.close(),
    cancellation.whenCancelled.then((_) {
      request.abort();
      return _downloadCancelledMarker;
    }),
  ]);
  if (result == _downloadCancelledMarker) {
    throw StateError('下载已取消。');
  }
  return result as HttpClientResponse;
}

Future<void> _drainResponse(
  HttpClientResponse response,
  HttpClientRequest? request,
  BrowserDownloadCancellation? cancellation,
) async {
  if (cancellation == null) {
    await response.drain<void>();
    return;
  }
  final result = await Future.any<Object>([
    response.drain<void>().then<Object>((_) => _downloadCompletedMarker),
    cancellation.whenCancelled.then((_) {
      request?.abort();
      return _downloadCancelledMarker;
    }),
  ]);
  if (result == _downloadCancelledMarker) {
    throw StateError('下载已取消。');
  }
}

Future<void> _pipeResponse(
  HttpClientResponse response,
  IOSink sink,
  HttpClientRequest? request,
  BrowserDownloadCancellation? cancellation,
) async {
  if (cancellation == null) {
    await response.pipe(sink);
    return;
  }
  final result = await Future.any<Object>([
    response.pipe(sink).then<Object>((_) => _downloadCompletedMarker),
    cancellation.whenCancelled.then((_) {
      request?.abort();
      return _downloadCancelledMarker;
    }),
  ]);
  if (result == _downloadCancelledMarker) {
    throw StateError('下载已取消。');
  }
}

Future<Directory> _existingDirectory(Directory directory) async {
  try {
    final canonical = await directory.resolveSymbolicLinks();
    final type = await FileSystemEntity.type(canonical, followLinks: true);
    if (type != FileSystemEntityType.directory) {
      throw StateError('下载目录不是目录：${directory.path}');
    }
    return Directory(canonical);
  } on FileSystemException {
    throw StateError('下载目录不可写：${directory.path}');
  }
}
