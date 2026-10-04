import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Delivers a decoded IDE snapshot to the Flutter-facing bridge.
typedef CodexIdeContextHostUpdate = void Function(Object? value);

/// Publishes a loopback HTTP endpoint for a cooperating IDE host.
class CodexIdeContextHostTransport {
  CodexIdeContextHostTransport({
    required CodexIdeContextHostUpdate onUpdate,
    required Directory discoveryDirectory,
  }) : _onUpdate = onUpdate,
       _discoveryDirectory = discoveryDirectory;

  static const discoveryFileName = 'ide-context-host.json';
  static const maxRequestBytes = 512 * 1024;

  final CodexIdeContextHostUpdate _onUpdate;
  final Directory _discoveryDirectory;
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  String? _token;
  File? _discoveryFile;

  bool get isRunning => _server != null;

  /// Starts the endpoint and atomically publishes its discovery record.
  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_server != null) {
      await server.close(force: true);
      return;
    }
    final token = _newToken();
    final discoveryFile = File(
      '${_discoveryDirectory.path}/$discoveryFileName',
    );
    await discoveryFile.parent.create(recursive: true);
    final temporary = File(
      '${discoveryFile.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final discovery = jsonEncode({
      'version': 1,
      'host': '127.0.0.1',
      'port': server.port,
      'path': '/updateContext',
      'token': token,
      'pid': pid,
    });
    try {
      await temporary.writeAsString(discovery, flush: true);
      await temporary.rename(discoveryFile.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    _server = server;
    _token = token;
    _discoveryFile = discoveryFile;
    _subscription = server.listen(_handleRequest);
  }

  /// Stops the endpoint and removes its discovery record.
  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final server = _server;
    _server = null;
    _token = null;
    await server?.close(force: true);
    final discoveryFile = _discoveryFile;
    _discoveryFile = null;
    if (discoveryFile != null && await discoveryFile.exists()) {
      await discoveryFile.delete();
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    if (request.method != 'POST' || request.uri.path != '/updateContext') {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final authorization = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    if (authorization != 'Bearer $_token') {
      response.statusCode = HttpStatus.unauthorized;
      await response.close();
      return;
    }
    if (request.contentLength > maxRequestBytes) {
      response.statusCode = HttpStatus.requestEntityTooLarge;
      await response.close();
      return;
    }
    try {
      final body = await utf8.decoder.bind(request).join();
      if (utf8.encode(body).length > maxRequestBytes) {
        response.statusCode = HttpStatus.requestEntityTooLarge;
      } else {
        _onUpdate(jsonDecode(body));
        response.statusCode = HttpStatus.ok;
        response.write(jsonEncode({'ok': true}));
      }
    } on Object catch (error) {
      response.statusCode = HttpStatus.badRequest;
      response.write(jsonEncode({'error': error.toString()}));
    } finally {
      await response.close();
    }
  }

  String _newToken() {
    final bytes = List<int>.generate(
      32,
      (_) => Random.secure().nextInt(256),
      growable: false,
    );
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
